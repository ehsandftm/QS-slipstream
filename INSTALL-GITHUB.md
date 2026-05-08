# Install from GitHub (Iran-Friendly Method)

**Use this when GitHub is accessible but other sites might be blocked.**

**NO laptop needed!** Everything downloads directly from GitHub/releases.

---

## One-Line Install on Iran Server

```bash
curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-github.sh | bash
```

**Or if curl is blocked, use wget:**

```bash
wget -qO- https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-github.sh | bash
```

That's it! The installer will:
- ✅ Download binary from **official release** (net2share/slipstream-rust-build)
- ✅ Download Serbia certificate from **your GitHub repo**
- ✅ Download all Python files from **your GitHub repo**
- ✅ Install and configure everything
- ✅ Start services automatically

**No Rust compiler needed! No laptop needed!**

---

## What Gets Asked During Install

Same questions as normal install:

1. My real public IP (or `ezping`/`ipmyp`)
2. Foreign VPS IP
3. Downlink spoof IP (e.g., `78.157.42.100`)
4. Hysteria2 port (default: `54322`)
5. Tunnel domain (e.g., `qs.gtgp.space`)
6. Uplink mode (`d` for DNS resolver)
7. DNS resolvers (e.g., `8.8.8.8 8.8.4.4 1.1.1.1`)
8. Encryption pass (optional)
9. ~~VPS cert~~ (auto-downloaded from GitHub!)

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

**GitHub download fails:**

```bash
# Test if GitHub is accessible
curl -I https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/README.md

# If blocked, use VPN temporarily or fallback to Telegram method
```

**Binary download fails:**

The binary downloads from the official release. If it fails:

```bash
# Test if GitHub releases are accessible
curl -I https://github.com/net2share/slipstream-rust-build/releases/download/v2026.04.22.1/slipstream-client-linux-amd64

# If blocked, fallback to Telegram method
```
