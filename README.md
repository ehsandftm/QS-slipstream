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

### Uplink (client → server)

```
[Hysteria2 / VPN App]
        │  UDP packet
        ▼
[Local: main_client_slip.py]
        │  framed TCP  [2-byte len][type=DATA][payload]
        ▼
[Local: slipstream-client-rust  TCP:5201]
        │  QUIC encoded inside DNS TXT queries
        ▼
   [Public DNS  8.8.8.8:53]
        │  forwards to authoritative NS
        ▼
[Foreign VPS: slipstream-server-rust  UDP:53]
        │  decoded TCP stream
        ▼
[Foreign VPS: main_server_slip.py  TCP:5210]
        │  raw UDP
        ▼
[Foreign VPS: Hysteria2 / Xray backend  UDP:40443]
```

### Downlink (server → client)

```
[Foreign VPS: Hysteria2 / Xray backend  UDP:40443]
        │  UDP reply
        ▼
[Foreign VPS: main_server_slip.py  TCP:5210]
        │  raw spoofed UDP packet
        │  src IP  = foreign VPS IP  (fake, looks like normal UDP)
        │  src port = 53
        ▼
         ╌╌╌╌╌╌ direct internet (no DNS, no tunnel) ╌╌╌╌╌╌
        │
        ▼
[Local: main_client_slip.py  wan_socket]
        │  reassembled via reverse_frag
        ▼
[Hysteria2 / VPN App]
```
