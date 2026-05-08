#!/usr/bin/env bash
set -e

# QS + Slipstream - Install from GitHub
# Downloads pre-built binary and certificate directly from your GitHub repo

GITHUB_REPO="ehsandftm/QS-slipstream"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
BINARY_URL="${GITHUB_RAW}/binaries/slipstream-client-rust"
CERT_URL="${GITHUB_RAW}/cert-serbia.pem"
INSTALL_SCRIPT_URL="${GITHUB_RAW}/install-prebuilt.sh"

WORKDIR="/tmp/qs-github-install"
BINARY_PATH="${WORKDIR}/slipstream-client-rust"
CERT_PATH="${WORKDIR}/cert-serbia.pem"

# ─────────────────────────────────────────────
print_header() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   QS + Slipstream - Install from GitHub"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

# ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Please run as root"; exit 1
fi

print_header

echo "[+] Creating working directory..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "[+] Downloading slipstream-client-rust from GitHub..."
if ! curl -fsSL "$BINARY_URL" -o "$BINARY_PATH"; then
  echo "[!] ERROR: Failed to download binary from GitHub"
  echo "    URL: $BINARY_URL"
  echo ""
  echo "    Make sure you've uploaded the binary to your repo:"
  echo "    1. Download: wget https://github.com/net2share/slipstream-rust-build/releases/download/v2026.04.22.1/slipstream-client-linux-amd64 -O slipstream-client-rust"
  echo "    2. Upload to repo: git add binaries/slipstream-client-rust && git commit -m 'Add binary' && git push"
  echo ""
  exit 1
fi

chmod +x "$BINARY_PATH"
echo "[+] Binary downloaded: $(du -h $BINARY_PATH | cut -f1)"

echo "[+] Downloading Serbia certificate from GitHub..."
if ! curl -fsSL "$CERT_URL" -o "$CERT_PATH"; then
  echo "[!] WARNING: Failed to download certificate from GitHub"
  echo "    Certificate will be skipped (optional)"
  CERT_PATH=""
else
  echo "[+] Certificate downloaded"
fi

echo "[+] Downloading installer script..."
curl -fsSL "$INSTALL_SCRIPT_URL" -o "${WORKDIR}/install-prebuilt.sh"
chmod +x "${WORKDIR}/install-prebuilt.sh"

echo
echo "[+] Starting installation..."
echo

# Set certificate as base64 for installer if we have it
export CERT_B64=""
if [ -n "$CERT_PATH" ] && [ -f "$CERT_PATH" ]; then
  CERT_B64=$(base64 -w 0 "$CERT_PATH" 2>/dev/null || base64 "$CERT_PATH")
fi

# Run the installer with pre-built binary
cd "$WORKDIR"
BINARY_PATH="$BINARY_PATH" bash install-prebuilt.sh

# Cleanup
echo
echo "[+] Cleaning up temporary files..."
rm -rf "$WORKDIR"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
