#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/ehsandftm/QS-slipstream.git"
RUST_CLIENT_URL="https://github.com/net2share/slipstream-rust-build/releases/download/v2026.04.22.1/slipstream-client-linux-amd64"
WORKDIR="/tmp/QS-slipstream-install"
INSTALL_DIR="/root/QS-Tunnel"
RUST_CLIENT="/root/slipstream-client-rust"
SVC_FILE="/etc/systemd/system/slipstream-client.service"

# ─────────────────────────────────────────────
print_header() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   QS + Slipstream  —  Local (Client) Installer"
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

ask_required() {
  local prompt="$1" var
  while true; do
    read -rp "$prompt: " var
    [ -n "$var" ] && break
    echo "   [!] This field is required. Please enter a value."
  done
  echo "$var"
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
echo "1) Real public IP of THIS local server"
echo "   The actual IP of this server. Sent to the foreign VPS so it knows"
echo "   where to deliver spoofed downlink UDP packets (to your wan_socket)."
echo "   Type 'ezping' or 'ipmyp' to auto-detect."
MY_PUBLIC_IP=$(ask_required "   My real public IP")
echo

# ── Question 2 ──────────────────────────────
echo "2) Foreign VPS IP address"
echo "   The remote server running the tunnel backend."
echo "   Used for the uplink tunnel (direct mode) and config reference."
VPS_IP=$(ask_required "   Foreign VPS IP")
echo

# ── Question 3 ──────────────────────────────
echo "3) Downlink spoof IP  (the fake source IP on packets the foreign VPS sends back)"
echo "   The foreign VPS sends raw UDP packets directly to this server using a FAKE"
echo "   source IP to bypass firewalls/DPI. Choose an IP that looks trusted in your country."
echo "   This is NOT your server IP and NOT the foreign VPS IP."
echo "   Example: 78.157.42.100  (a local trusted/CDN IP that won't be blocked)"
echo "   The Hysteria2 app connects to Q1, but downlink arrives from THIS IP:53."
FAKE_SEND_IP=$(ask_required "   Downlink spoof IP")
echo

# ── Question 4 ──────────────────────────────
echo "4) Hysteria2 listen port"
echo "   Your VPN users connect their Hysteria2 app to THIS port on this server."
HYSTERIA_PORT=$(ask "   Hysteria2 port" "54322")
echo

# ── Question 5 ──────────────────────────────
echo "5) DNS tunnel domain"
echo "   The domain used for the QUIC-over-DNS uplink tunnel."
echo "   Must have an NS record pointing to your foreign VPS."
echo "   Example: q.firmware-update-service.com"
echo "   *** Must be the SAME domain entered during foreign VPS installation. ***"
SLIP_DOMAIN=$(ask_required "   Tunnel domain")
echo

# ── Question 6 ──────────────────────────────
echo "6) Uplink mode"
echo "   d) DNS resolver  — route through a public DNS (8.8.8.8 etc.)"
echo "      Bypasses local censorship. Upload ~200-500 kbps, higher latency."
echo "   a) Direct        — connect straight to ${VPS_IP}:53"
echo "      Faster (~1 Mbps upload). Use only if foreign VPS port 53 is not blocked."
read -rp "   Select mode [d/a, default: d]: " UPLINK_MODE
UPLINK_MODE="${UPLINK_MODE:-d}"
echo

DNS_RESOLVERS=""
if [[ "$UPLINK_MODE" =~ ^[dD]$ ]]; then
  echo "   DNS resolvers (space-separated, e.g. 8.8.8.8:53 8.8.4.4:53 1.1.1.1:53)"
  DNS_RESOLVERS=$(ask "   Resolvers" "8.8.8.8:53 8.8.4.4:53 1.1.1.1:53")
fi
echo

# ── Question 7 ──────────────────────────────
echo "7) Encryption password  (optional)"
echo "   Protects the INFO packet that tells the foreign VPS where to send replies."
echo "   Must be the SAME plain-text string on both local and foreign VPS."
echo "   Leave blank = no encryption (fine for private setups)."
ENC_PASS=$(ask "   Encryption pass" "")
echo

# ── Question 8 ──────────────────────────────
echo "8) Foreign VPS TLS certificate  (optional)"
echo "   Paste the base64 cert printed at the end of foreign VPS installation."
echo "   This pins the QUIC connection to the foreign VPS's exact certificate."
echo "   Leave blank = still encrypted, just without certificate pinning."
CERT_B64=$(ask "   VPS cert (base64, or blank)" "")
echo

# ─────────────────────────────────────────────
echo "[+] Installing dependencies..."
apt-get update -y -qq
apt-get install -y -qq software-properties-common curl git openssl psmisc

if ! command -v python3.11 >/dev/null 2>&1; then
  echo "[+] Installing Python 3.11..."
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -y -qq
  apt-get install -y -qq python3.11 python3.11-distutils
fi

if ! python3.11 -c "import aiohttp" 2>/dev/null; then
  echo "[+] Installing aiohttp..."
  curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3.11 -q
  python3.11 -m pip install -q aiohttp
fi

# ─────────────────────────────────────────────
echo "[+] Stopping and removing any old QS/slipstream services..."
for svc in $(systemctl list-units --all --no-legend 2>/dev/null | awk '{print $1}' | grep -E 'slipstream|qs-tunnel|qs-slip|qs-client'); do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done
# also scan unit files on disk
for f in /etc/systemd/system/*slipstream* /etc/systemd/system/qs-tunnel* /etc/systemd/system/qs-slip* /etc/systemd/system/qs-client*; do
  [ -f "$f" ] || continue
  svc=$(basename "$f")
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done
echo "[+] Freeing ports 5201 and ${HYSTERIA_PORT}..."
fuser -k 5201/tcp 2>/dev/null || true
fuser -k "${HYSTERIA_PORT}/udp" 2>/dev/null || true
systemctl daemon-reload

# ─────────────────────────────────────────────
echo "[+] Cloning repo..."
rm -rf "$WORKDIR"
git clone --quiet --depth 1 "$REPO_URL" "$WORKDIR"

# ─────────────────────────────────────────────
echo "[+] Installing slipstream-client-rust binary..."
if [ -f "$WORKDIR/files/slipstream-client-rust" ]; then
  cp "$WORKDIR/files/slipstream-client-rust" "$RUST_CLIENT"
  chmod +x "$RUST_CLIENT"
  echo "[+] Binary installed from repo."
elif curl -fL --connect-timeout 15 --max-time 60 -o "$RUST_CLIENT" "$RUST_CLIENT_URL" 2>/dev/null; then
  chmod +x "$RUST_CLIENT"
  echo "[+] Binary downloaded."
else
  echo "[!] Could not download slipstream-client-rust."
  echo "    Upload it manually to $RUST_CLIENT and run this script again."
  exit 1
fi

# ─────────────────────────────────────────────
echo "[+] Installing files..."
mkdir -p "$INSTALL_DIR"
cp "$WORKDIR/files/main_client_slip.py"    "$INSTALL_DIR/"
cp "$WORKDIR/files/qs-client-slip-menu.sh" "$INSTALL_DIR/"
cp "$WORKDIR/files/reverse_frag.py"        "$INSTALL_DIR/"
rm -rf "$INSTALL_DIR/utility"
cp -r  "$WORKDIR/files/utility"            "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/qs-client-slip-menu.sh"
ln -sf "$INSTALL_DIR/qs-client-slip-menu.sh" /usr/local/bin/qs-client-slip

# ─────────────────────────────────────────────
echo "[+] Saving cert..."
CERT_PATH=""
if [ -n "$CERT_B64" ]; then
  CERT_PATH="/root/slip-cert-san.pem"
  echo "$CERT_B64" | base64 -d > "$CERT_PATH"
  echo "[+] Cert saved to $CERT_PATH"
fi

# ─────────────────────────────────────────────
echo "[+] Writing config_client_slip.json..."
python3.11 - <<PY
import json
cfg = {
  "h_in_address":        "0.0.0.0:${HYSTERIA_PORT}",
  "my_public_ip":        """${MY_PUBLIC_IP}""",
  "fake_send_ip":        """${FAKE_SEND_IP}""",
  "fake_send_port":      53,
  "info_encryption_pass": """${ENC_PASS}""",
  "slipstream_host":     "127.0.0.1",
  "slipstream_port":     5201
}
with open("${INSTALL_DIR}/config_client_slip.json", "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(json.dumps(cfg, indent=2))
PY

# ─────────────────────────────────────────────
echo "[+] Writing systemd service: slipstream-client..."
{
  cat <<EOF
[Unit]
Description=Slipstream Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/root
ExecStart=${RUST_CLIENT} \\
EOF
  if [[ "$UPLINK_MODE" =~ ^[aA]$ ]]; then
    echo "  --authoritative ${VPS_IP}:53 \\"
  else
    for r in $DNS_RESOLVERS; do
      echo "  -r $r \\"
    done
  fi
  [ -n "$CERT_PATH" ] && echo "  --cert ${CERT_PATH} \\"
  cat <<EOF
  -d ${SLIP_DOMAIN} \\
  -l 5201
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
} > "$SVC_FILE"

echo "[+] Writing systemd service: qs-slipstream..."
cp "$WORKDIR/systemd/qs-slipstream.service" /etc/systemd/system/

# ─────────────────────────────────────────────
echo "[+] Enabling and starting services..."
systemctl daemon-reload
systemctl enable slipstream-client qs-slipstream
systemctl start slipstream-client
sleep 4
systemctl start qs-slipstream

# ─────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Manage with:  qs-client-slip"
echo
echo "  Your Hysteria2 users should connect to:"
echo "    ${MY_PUBLIC_IP}:${HYSTERIA_PORT}"
echo
systemctl --no-pager status slipstream-client qs-slipstream 2>/dev/null | grep -E 'Active:|●' || true
