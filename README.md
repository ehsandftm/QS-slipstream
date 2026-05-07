# QS-Slipstream

QUIC-over-DNS uplink + IP spoofing downlink tunnel for bypassing censorship.

- **Uplink**: QUIC inside DNS TXT queries (Slipstream) through public resolvers (8.8.8.8)
- **Downlink**: Raw IP spoofing — Serbia sends replies as if they come directly from itself

---

## Quick Install

### 1. Serbia VPS (run first)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-server.sh)
```

At the end it prints a **base64 certificate string** — copy it, you will need it for the Iran install.

### 2. Iran Server (run after Serbia)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install.sh)
```

Paste the base64 cert from Serbia when asked (question 7). Leave blank to skip cert pinning.

---

## DNS Setup (Cloudflare — DNS Only, no proxy)

| Type | Name | Value |
|------|------|-------|
| A | `ser.your-domain.com` | `<Serbia VPS IP>` |
| NS | `q.your-domain.com` | `ser.your-domain.com` |

---

## Management

| Command | Side | Description |
|---------|------|-------------|
| `qs-client-slip` | Iran | Start/stop/config Iran client |
| `qs-server-slip` | Serbia | Start/stop/config Serbia server |

---

## Architecture

```
[Hysteria2 App]
      │  UDP:54322
      ▼
[Iran: main_client_slip.py]  ←── spoofed downlink (UDP, fake src = Serbia IP)
      │  TCP:5201
      ▼
[Iran: slipstream-client-rust]
      │  QUIC-in-DNS TXT via 8.8.8.8
      ▼
[Serbia: slipstream-server-rust  UDP:53]
      │  TCP:5210
      ▼
[Serbia: main_server_slip.py]
      │  UDP:40443
      ▼
[Serbia: Hysteria2 / Xray backend]
```
