#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/ehsandftm/QS-slipstream.git"
RUST_SERVER_URL="https://github.com/net2share/slipstream-rust-build/releases/download/v2026.04.22.1/slipstream-server-linux-amd64"
WORKDIR="/tmp/QS-slipstream-install"
INSTALL_DIR="/root/QS-Tunnel-slip"
RUST_SERVER="/root/slipstream-server-rust"
CERT_DIR="/root/slipstream-certs"
SVC_SLIP="/etc/systemd/system/slipstream-rust-53.service"

# ─────────────────────────────────────────────
print_header() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   QS + Slipstream  —  Foreign VPS (Server) Installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

ask() {
  local prompt="$1" default="$2" var
  if [ -n "$default" ]; then
    read -rp "$prompt [$default]: " var
    echo "${var:-$default}"
  else
    read -rp "$prompt: " var
    echo "$var"
  fi
}

# ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Please run as root"; exit 1
fi

print_header

echo "You will be asked a few questions. Defaults are shown in [brackets]."
echo "Press Enter to accept the default."
echo

# ── Question 1 ──────────────────────────────
echo "1) Hysteria2 / Xray backend port"
echo "   The local port where your VPN backend (Hysteria2 or Xray) is listening."
echo "   The slipstream server will forward decrypted tunnel traffic here."
BACKEND_PORT=$(ask "   Backend port" "40443")
echo

# ── Question 2 ──────────────────────────────
echo "2) DNS tunnel domain"
echo "   The domain used for the QUIC-over-DNS tunnel."
echo "   Must have an NS record pointing to THIS server."
echo "   Example: q.firmware-update-service.com"
echo "   *** Must be the SAME domain entered during local client installation. ***"
SLIP_DOMAIN=$(ask "   Tunnel domain")
echo

# ── Question 3 ──────────────────────────────
echo "3) Encryption password  (optional)"
echo "   Protects the INFO packet that tells this server where to send spoofed replies."
echo "   Must be the SAME plain-text string on both foreign VPS and local client."
echo "   Leave blank = no encryption (fine for private setups)."
ENC_PASS=$(ask "   Encryption pass" "")
echo

# ─────────────────────────────────────────────
echo "[+] Installing dependencies..."
apt-get update -y -qq
apt-get install -y -qq software-properties-common curl git openssl

if ! command -v python3.11 >/dev/null 2>&1; then
  echo "[+] Installing Python 3.11..."
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -y -qq
  apt-get install -y -qq python3.11 python3.11-distutils
fi

if ! python3.11 -c "import numba" 2>/dev/null; then
  echo "[+] Installing numba (fast checksum)..."
  curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3.11 -q
  python3.11 -m pip install -q numba
fi

# ─────────────────────────────────────────────
echo "[+] Stopping old services..."
systemctl stop slipstream-rust-53 slipstream-5304 qs-slip-server 2>/dev/null || true

# ─────────────────────────────────────────────
echo "[+] Cloning repo..."
rm -rf "$WORKDIR"
git clone --quiet --depth 1 "$REPO_URL" "$WORKDIR"

# ─────────────────────────────────────────────
echo "[+] Installing slipstream-server-rust binary..."
if [ -f "$WORKDIR/files/slipstream-server-rust" ]; then
  cp "$WORKDIR/files/slipstream-server-rust" "$RUST_SERVER"
  chmod +x "$RUST_SERVER"
  echo "[+] Binary installed from repo."
elif curl -fL --connect-timeout 15 --max-time 60 -o "$RUST_SERVER" "$RUST_SERVER_URL" 2>/dev/null; then
  chmod +x "$RUST_SERVER"
  echo "[+] Binary downloaded."
else
  echo "[!] Could not download slipstream-server-rust."
  echo "    Upload it manually to $RUST_SERVER and run this script again."
  exit 1
fi

# ─────────────────────────────────────────────
echo "[+] Installing server files..."
mkdir -p "$INSTALL_DIR"
cp "$WORKDIR/files/main_server_slip.py"    "$INSTALL_DIR/"
cp "$WORKDIR/files/qs-server-slip-menu.sh" "$INSTALL_DIR/"
cp "$WORKDIR/files/reverse_frag.py"        "$INSTALL_DIR/"
rm -rf "$INSTALL_DIR/utility"
cp -r  "$WORKDIR/files/utility"            "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/qs-server-slip-menu.sh"
ln -sf "$INSTALL_DIR/qs-server-slip-menu.sh" /usr/local/bin/qs-server-slip

# ─────────────────────────────────────────────
echo "[+] Writing config_server_slip.json..."
python3.11 - <<PY
import json
cfg = {
  "listen_host": "127.0.0.1",
  "listen_port": 5210,
  "target_host": "127.0.0.1",
  "target_port": int("${BACKEND_PORT}"),
  "info_encryption_pass": """${ENC_PASS}""",
  "fragment_chunk_size": 1100
}
with open("${INSTALL_DIR}/config_server_slip.json", "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(json.dumps(cfg, indent=2))
PY

# ─────────────────────────────────────────────
echo "[+] Generating TLS certificate with SAN..."
mkdir -p "$CERT_DIR"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout "$CERT_DIR/key-san.pem" \
  -out    "$CERT_DIR/cert-san.pem" \
  -days 3650 -nodes \
  -subj "/CN=${SLIP_DOMAIN}" \
  -addext "subjectAltName=DNS:${SLIP_DOMAIN},DNS:*.${SLIP_DOMAIN}" 2>/dev/null
echo "[+] Certificate: $CERT_DIR/cert-san.pem"

# ─────────────────────────────────────────────
echo "[+] Writing systemd service: slipstream-rust-53..."
cat > "$SVC_SLIP" <<EOF
[Unit]
Description=Slipstream Rust Server - DNS authoritative NS port 53
After=network-online.target qs-slip-server.service
Wants=network-online.target
Requires=qs-slip-server.service

[Service]
Type=simple
WorkingDirectory=/root
ExecStart=${RUST_SERVER} \\
  -l 53 \\
  -d ${SLIP_DOMAIN} \\
  -a 127.0.0.1:5210 \\
  -c ${CERT_DIR}/cert-san.pem \\
  -k ${CERT_DIR}/key-san.pem \\
  --reset-seed /root/slipstream-reset-seed \\
  --fallback 8.8.8.8:53
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Writing systemd service: qs-slip-server..."
cp "$WORKDIR/systemd/qs-slip-server.service" /etc/systemd/system/

# ─────────────────────────────────────────────
echo "[+] Enabling and starting services..."
systemctl daemon-reload
systemctl enable qs-slip-server slipstream-rust-53
systemctl restart qs-slip-server
sleep 2
systemctl restart slipstream-rust-53

# ─────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Manage with:  qs-server-slip"
echo
echo "  DNS setup required (Cloudflare → DNS Only):"
echo "    NS  record:  ${SLIP_DOMAIN}          →  ser.<your-domain>"
echo "    A   record:  ser.<your-domain>       →  <this server IP>"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Foreign VPS TLS Certificate (base64)"
echo "   Copy this when running install.sh on the local client server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
base64 -w 0 "$CERT_DIR/cert-san.pem"
echo
echo
systemctl --no-pager status slipstream-rust-53 qs-slip-server 2>/dev/null | grep -E 'Active:|●' || true
