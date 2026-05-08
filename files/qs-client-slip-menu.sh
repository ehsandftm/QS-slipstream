#!/usr/bin/env bash
set -euo pipefail

SERVICE_QS="qs-slipstream"
SERVICE_SLIP="slipstream-client"
CONFIG="/root/QS-Tunnel/config_client_slip.json"
SVC_FILE="/etc/systemd/system/slipstream-client.service"
PYTHON="/usr/bin/python3.11"

pause() {
  echo
  read -r -p "Press Enter to continue..."
}

get_val() {
  "${PYTHON}" - <<PY
import json
with open("${CONFIG}") as f:
    v = json.load(f).get("$1","")
    print(v if v != "" else "")
PY
}

set_str() {
  "${PYTHON}" - <<PY
import json
p="${CONFIG}"
d=json.load(open(p))
d["$1"]="$2"
json.dump(d,open(p,"w"),indent=2)
print("Updated: $1 = $2")
PY
}

set_int() {
  "${PYTHON}" - <<PY
import json
p="${CONFIG}"
d=json.load(open(p))
d["$1"]=int("$2")
json.dump(d,open(p,"w"),indent=2)
print("Updated: $1 = $2")
PY
}

normalize_resolvers() {
  local input="$1" output=""
  for r in $input; do
    if [[ "$r" =~ :[0-9]+$ ]]; then
      output="$output $r"
    else
      output="$output $r:53"
    fi
  done
  echo "${output# }"  # trim leading space
}

svc_get_resolvers() {
  grep -oP '(?<=-r )\S+' "$SVC_FILE" 2>/dev/null | sed 's/\\$//' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//' || echo ""
}

svc_get_domain() {
  grep -oP '(?<=-d )\S+' "$SVC_FILE" 2>/dev/null | head -1 || echo ""
}

svc_get_cert() {
  grep -oP '(?<=--cert )\S+' "$SVC_FILE" 2>/dev/null | head -1 || echo ""
}

svc_get_port() {
  grep -oP '(?<=-l )\S+' "$SVC_FILE" 2>/dev/null | head -1 || echo "5201"
}

svc_is_direct() {
  grep -q -- '--authoritative' "$SVC_FILE" 2>/dev/null
}

svc_get_uplink_mode() {
  if svc_is_direct; then
    echo "DIRECT  -> $(grep -oP '(?<=--authoritative )\S+' "$SVC_FILE" 2>/dev/null)"
  else
    local r; r=$(svc_get_resolvers)
    echo "DNS resolver  -> ${r:-(none set)}"
  fi
}

svc_write() {
  local mode="$1"   # "resolver" or "direct"
  local target="$2" # resolvers (space-sep) or direct addr
  local domain cert port cert_line

  domain=$(svc_get_domain)
  cert=$(svc_get_cert)
  port=$(svc_get_port)

  if [ -n "$cert" ] && [ "$cert" != "(none)" ]; then
    cert_line="  --cert $cert \\"
  else
    cert_line=""
  fi

  {
    cat <<EOF
[Unit]
Description=Slipstream Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/root/slipstream-client-rust \\
EOF
    if [ "$mode" = "direct" ]; then
      echo "  --authoritative $target \\"
    else
      for r in $target; do
        echo "  -r $r \\"
      done
    fi
    [ -n "$cert_line" ] && echo "$cert_line"
    cat <<EOF
  -d $domain \\
  -l $port
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  } > "$SVC_FILE"

  systemctl daemon-reload
}

start_all() {
  systemctl start "$SERVICE_SLIP"
  sleep 1
  systemctl start "$SERVICE_QS"
  echo "Services started."
}

stop_all() {
  systemctl stop "$SERVICE_QS" || true
  systemctl stop "$SERVICE_SLIP" || true
  echo "Services stopped."
}

restart_all() {
  systemctl restart "$SERVICE_SLIP"
  sleep 1
  systemctl restart "$SERVICE_QS"
  echo "Services restarted."
}

status_all() {
  echo "===== $SERVICE_SLIP ====="
  systemctl status "$SERVICE_SLIP" --no-pager -n 5
  echo
  echo "===== $SERVICE_QS ====="
  systemctl status "$SERVICE_QS" --no-pager -n 5
}

logs_all() {
  echo "===== $SERVICE_SLIP logs ====="
  journalctl -u "$SERVICE_SLIP" -n 40 --no-pager
  echo
  echo "===== $SERVICE_QS logs ====="
  journalctl -u "$SERVICE_QS" -n 40 --no-pager
}

follow_logs() {
  journalctl -u "$SERVICE_SLIP" -u "$SERVICE_QS" -f
}

show_config() {
  echo "===== QS+Slipstream Client Config ====="
  echo
  echo "  -- Downlink (spoofed replies to your client) --"
  echo "  1) Hysteria listen port = $(get_val h_in_address | cut -d: -f2)"
  echo "  2) My real public IP    = $(get_val my_public_ip)"
  echo "  3) Downlink spoof IP    = $(get_val fake_send_ip)"
  echo "  4) Downlink spoof port  = $(get_val fake_send_port)"
  echo
  echo "  -- Uplink (QUIC tunnel through DNS) --"
  echo "  5) Uplink mode          = $(svc_get_uplink_mode)"
  echo "  6) DNS resolvers        = $(svc_get_resolvers)"
  echo "  7) Tunnel domain        = $(svc_get_domain)"
  echo "  8) Server cert pin      = $(svc_get_cert)    (optional)"
  echo
  echo "  -- Security --"
  echo "  9) Encryption pass      = $(get_val info_encryption_pass)    (plain text, must match foreign VPS item 5)"
}

menu_edit() {
while true; do
clear
echo "===== QS+Slipstream Client Config ====="
echo
echo "  -- Downlink (spoofed replies to your client) --"
echo "  1) Hysteria listen port = $(get_val h_in_address | cut -d: -f2)    (your VPN app connects to this port)"
echo "  2) My real public IP    = $(get_val my_public_ip)    (this server's real IP — foreign VPS sends downlink HERE)"
echo "  3) Downlink spoof IP    = $(get_val fake_send_ip)    (fake source IP on downlink, e.g. 78.157.42.100)"
echo "  4) Downlink spoof port  = $(get_val fake_send_port)    (fake source port on downlink, usually 53)"
echo
echo "  -- Uplink (QUIC tunnel through DNS) --"
echo "  5) Uplink mode          = $(svc_get_uplink_mode)"
echo "  6) DNS resolvers        = $(svc_get_resolvers)"
echo "  7) Tunnel domain        = $(svc_get_domain)"
echo "  8) Server cert pin      = $(svc_get_cert)    (optional — leave blank = no pinning)"
echo
echo "  -- Security --"
echo "  9) Encryption pass      = $(get_val info_encryption_pass)    (plain text, must match foreign VPS item 5)"
echo
echo "  0) Back"
echo
read -rp "Select: " c

case "$c" in
1)
  read -rp "New Hysteria listen port [e.g. 54322]: " v
  set_str h_in_address "0.0.0.0:$v"
  echo "Note: restart services to apply."
  pause
  ;;
2)
  echo "  The REAL public IP of this server."
  echo "  The foreign VPS sends spoofed downlink packets TO this IP."
  echo "  Or type: ezping  (auto-detect from ezping.ir)"
  echo "  Or type: ipmyp   (auto-detect from ipmyp.ir)"
  read -rp "New my_public_ip: " v
  set_str my_public_ip "$v"
  pause
  ;;
3)
  echo "  The FAKE source IP the foreign VPS stamps on downlink packets."
  echo "  This is NOT your server IP and NOT the foreign VPS IP."
  echo "  Choose a trusted/local IP that won't be blocked by firewalls (e.g. 78.157.42.100)."
  echo "  Your Hysteria2 app receives replies appearing to come FROM this IP:53."
  read -rp "New downlink spoof IP: " v
  set_str fake_send_ip "$v"
  pause
  ;;
4)
  echo "  Port the foreign VPS uses as fake sender port on spoofed replies (usually 53)."
  read -rp "New spoof source port: " v
  set_int fake_send_port "$v"
  pause
  ;;
5)
  echo "  d) DNS resolver mode  (local -> public DNS like 8.8.8.8 -> foreign VPS)"
  echo "     Bypasses local blocking. Slower upload (~200-500 kbps), higher latency."
  echo "  a) DIRECT mode        (local -> foreign VPS:53 directly)"
  echo "     Faster upload (~1 Mbps+), lower latency. Only works if foreign VPS:53 is not blocked."
  echo
  read -rp "Select mode [d/a]: " m
  case "$m" in
    d|D)
      echo "  Enter DNS resolvers (space-separated, e.g. 8.8.8.8 8.8.4.4 1.1.1.1)"
      echo "  Port :53 will be added automatically if not specified."
      read -rp "DNS resolvers: " v
      v=$(normalize_resolvers "$v")
      svc_write "resolver" "$v"
      echo "Switched to DNS resolver mode. Run Restart (option 3) to apply."
      pause
      ;;
    a|A)
      read -rp "Foreign VPS address (e.g. 1.2.3.4:53): " v
      svc_write "direct" "$v"
      echo "Switched to DIRECT mode. Run Restart (option 3) to apply."
      pause
      ;;
    *) echo "Invalid"; sleep 1;;
  esac
  ;;
6)
  echo "  Current: $(svc_get_resolvers)"
  echo "  These are the public DNS servers QUIC packets are routed through."
  echo "  Examples: 8.8.8.8  8.8.4.4  1.1.1.1"
  echo "  Port :53 will be added automatically if not specified."
  echo "  (Only applies in DNS resolver mode)"
  read -rp "New resolvers (space-separated): " v
  v=$(normalize_resolvers "$v")
  svc_write "resolver" "$v"
  echo "Updated. Run Restart (option 3) to apply."
  pause
  ;;
7)
  echo "  The DNS domain that QUIC is tunneled through."
  echo "  Must have NS record pointing to foreign VPS."
  echo "  Current: $(svc_get_domain)"
  read -rp "New tunnel domain: " v
  sed -i "s|-d [^ \\\\]*|-d ${v}|" "$SVC_FILE"
  systemctl daemon-reload
  echo "Updated. Run Restart (option 3) to apply."
  pause
  ;;
8)
  echo "  OPTIONAL: Foreign VPS TLS certificate path for QUIC identity verification."
  echo "  Prevents a man-in-the-middle attack on the DNS tunnel."
  echo "  The cert file must be copied from the foreign VPS to this server manually."
  echo "  Foreign VPS cert location: /root/slipstream-certs/cert-san.pem"
  echo "  Leave blank to disable pinning (connection still encrypted, just not pinned)."
  echo "  Current: $(svc_get_cert)"
  echo
  read -rp "New cert path (or leave blank to disable): " v
  if [ -z "$v" ]; then
    sed -i '/--cert /d' "$SVC_FILE"
    systemctl daemon-reload
    echo "Cert pinning disabled."
  else
    if grep -q -- '--cert' "$SVC_FILE"; then
      sed -i "s|--cert [^ \\\\]*|--cert ${v}|" "$SVC_FILE"
    else
      sed -i "/ExecStart=.*slipstream-client-rust/a\\  --cert $v \\\\" "$SVC_FILE"
    fi
    systemctl daemon-reload
    echo "Updated. Run Restart (option 3) to apply."
  fi
  pause
  ;;
9)
  echo "  Plain text password shared between local client and foreign VPS."
  echo "  Used to encrypt the INFO packet that tells the foreign VPS where to send"
  echo "  spoofed downlink replies (your real IP + port)."
  echo "  Same as item 5 on the foreign VPS server menu."
  echo "  Format: any plain text string, e.g: mysecretpass123"
  echo "  Leave blank = no encryption (fine for private setups)."
  read -rp "New encryption pass (or blank to clear): " v
  set_str info_encryption_pass "$v"
  pause
  ;;
0) break;;
*) echo "Invalid"; sleep 1;;
esac
done
}

while true; do
clear
echo "===== QS+Slipstream Client ====="
echo "1) Start"
echo "2) Stop"
echo "3) Restart"
echo "4) Status"
echo "5) Logs"
echo "6) Follow Logs"
echo "7) Show Config"
echo "8) Edit Config"
echo "0) Exit"
echo
read -rp "Select: " c

case "$c" in
1) start_all; pause;;
2) stop_all; pause;;
3) restart_all; pause;;
4) status_all; pause;;
5) logs_all; pause;;
6) follow_logs;;
7) show_config; pause;;
8) menu_edit;;
0) exit 0;;
*) echo "Invalid"; sleep 1;;
esac

done
