# QS-Slipstream

QUIC-over-DNS uplink + IP spoofing downlink tunnel for bypassing censorship.

- **Uplink**: QUIC inside DNS TXT queries (Slipstream) through public resolvers (8.8.8.8)
- **Downlink**: Raw IP spoofing — foreign VPS sends replies as if they come directly from itself

---

## Quick Install

### 1. Foreign VPS (run first)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install-server.sh)
```

At the end it prints a **base64 certificate string** — copy it, you will need it for the local client install.

### 2. Local Client Server (run after foreign VPS)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ehsandftm/QS-slipstream/main/install.sh)
```

Paste the base64 cert from the foreign VPS when asked (question 7). Leave blank to skip cert pinning.

---

## DNS Setup (Cloudflare — DNS Only, no proxy)

| Type | Name | Value |
|------|------|-------|
| A | `ser.your-domain.com` | `<Foreign VPS IP>` |
| NS | `q.your-domain.com` | `ser.your-domain.com` |

---

## Management

| Command | Side | Description |
|---------|------|-------------|
| `qs-client-slip` | Local client server | Start/stop/config local client |
| `qs-server-slip` | Foreign VPS | Start/stop/config foreign VPS server |

---

## Architecture

```
[Hysteria2 App]
      │  UDP:54322
      ▼
[Local: main_client_slip.py]  ←── spoofed downlink (UDP, fake src = foreign VPS IP)
      │  TCP:5201
      ▼
[Local: slipstream-client-rust]
      │  QUIC-in-DNS TXT via 8.8.8.8
      ▼
[Foreign VPS: slipstream-server-rust  UDP:53]
      │  TCP:5210
      ▼
[Foreign VPS: main_server_slip.py]
      │  UDP:40443
      ▼
[Foreign VPS: Hysteria2 / Xray backend]
```
