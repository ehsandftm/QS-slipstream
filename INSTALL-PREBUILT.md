# Pre-built Binary Installation Guide

Use this method when **Rust installation is blocked** in your country (e.g., Iran).

## Overview

1. **Build on your laptop** (Germany/unrestricted network)
2. **Transfer binary** via Telegram/SCP to Iran server
3. **Run one-line installer** using pre-built binary

---

## Step 1: Build the Binary (On Your Laptop)

### Option A: Download from Release

```bash
# Download the latest release
wget https://github.com/net2share/slipstream-rust-build/releases/download/v2026.04.22.1/slipstream-client-linux-amd64
mv slipstream-client-linux-amd64 slipstream-client-rust
chmod +x slipstream-client-rust
```

### Option B: Build from Source (if you have Rust)

```bash
# Clone slipstream-rust repository
git clone https://github.com/Mygod/slipstream-rust.git
cd slipstream-rust/client

# Build
cargo build --release

# Binary will be at: target/release/slipstream-client
cp target/release/slipstream-client ../slipstream-client-rust
chmod +x ../slipstream-client-rust
```

---

## Step 2: Transfer Binary to Iran Server

### Via Telegram

1. Send `slipstream-client-rust` file to your Telegram **Saved Messages**
2. On Iran server, download from Telegram Desktop/Web
3. Place in `/ubuntu/qs-slip/`:

```bash
mkdir -p /ubuntu/qs-slip
# Move downloaded file to /ubuntu/qs-slip/
mv ~/Downloads/slipstream-client-rust /ubuntu/qs-slip/
chmod +x /ubuntu/qs-slip/slipstream-client-rust
```

### Via SCP (if you have SSH access)

```bash
# From your laptop
scp slipstream-client-rust root@YOUR_IRAN_IP:/ubuntu/qs-slip/
```

---

## Step 3: One-Line Installation

On your Iran server:

```bash
BINARY_PATH=/ubuntu/qs-slip/slipstream-client-rust bash <(curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-prebuilt.sh)
```

**Or download first:**

```bash
curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-prebuilt.sh -o install-prebuilt.sh
BINARY_PATH=/ubuntu/qs-slip/slipstream-client-rust bash install-prebuilt.sh
```

---

## Configuration During Install

You'll be asked:

1. **My real public IP** - Your Iran server's real IP (or `ezping`/`ipmyp` for auto-detect)
2. **Foreign VPS IP** - Your Serbia/foreign server IP
3. **Downlink spoof IP** - Fake source IP (e.g., `78.157.42.100`)
4. **Hysteria2 port** - Port for VPN clients (default: `54322`)
5. **Tunnel domain** - DNS domain (e.g., `qs.gtgp.space`)
6. **Uplink mode** - `d` for DNS resolver (recommended for Iran)
7. **DNS resolvers** - Space-separated IPs (e.g., `8.8.8.8 8.8.4.4 1.1.1.1`)
8. **Encryption pass** - Optional password (leave blank)
9. **VPS cert** - Optional TLS cert base64 (leave blank)

---

## After Installation

```bash
# Manage services
qs-client-slip

# Check status
systemctl status slipstream-client qs-slipstream

# View logs
journalctl -u slipstream-client -f
```

---

## Troubleshooting

**Binary not found:**
```bash
# Verify binary exists and is executable
ls -lh /ubuntu/qs-slip/slipstream-client-rust
chmod +x /ubuntu/qs-slip/slipstream-client-rust
```

**Installation fails:**
```bash
# Check you're running as root
sudo su -
BINARY_PATH=/ubuntu/qs-slip/slipstream-client-rust bash install-prebuilt.sh
```

**Connection errors:**
```bash
# Check logs for TLS errors
journalctl -u slipstream-client -n 50

# Verify domain NS records are correct
nslookup -type=NS your-domain.com dns1.registrar-servers.com
```

---

## Binary Compatibility

- **Architecture**: `x86_64` (Intel/AMD 64-bit)
- **OS**: Linux (Ubuntu 20.04+, Debian 10+)
- **Kernel**: 4.15+

If your server is ARM or different architecture, you must build on a compatible system.
