#!/usr/bin/env bash
set -euo pipefail

SERVICE_QS="qs-slip-server"
SERVICE_SLIP="slipstream-rust-53"
CONFIG="/root/QS-Tunnel-slip/config_server_slip.json"
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
print("Updated:", "$1", "=", "$2")
PY
}

set_int() {
  "${PYTHON}" - <<PY
import json
p="${CONFIG}"
d=json.load(open(p))
d["$1"]=int("$2")
json.dump(d,open(p,"w"),indent=2)
print("Updated:", "$1", "=", "$2")
PY
}

start_all() {
  systemctl start "$SERVICE_QS"
  sleep 1
  systemctl start "$SERVICE_SLIP"
  echo "Services started."
}

stop_all() {
  systemctl stop "$SERVICE_SLIP" || true
  systemctl stop "$SERVICE_QS" || true
  echo "Services stopped."
}

restart_all() {
  systemctl restart "$SERVICE_QS"
  sleep 1
  systemctl restart "$SERVICE_SLIP"
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

show_ports() {
  echo "===== Listening Ports ====="
  echo "--- UDP (slipstream DNS port) ---"
  ss -ulnp | grep -E ':(53|5304|5305) ' || echo "  none"
  echo "--- TCP (qs-slip-server) ---"
  ss -tlnp | grep -E ':(5210|5202) ' || echo "  none"
  echo "--- UDP (Xray/Hysteria2) ---"
  ss -ulnp | grep ':40443' || echo "  none"
}

menu_edit() {
while true; do
clear
echo "===== QS+Slipstream Server Config ====="
echo "1) listen_host        = $(get_val listen_host)"
echo "2) listen_port        = $(get_val listen_port)"
echo "3) target_host        = $(get_val target_host)"
echo "4) target_port        = $(get_val target_port)"
echo "5) info_encryption_pass = $(get_val info_encryption_pass)"
echo "6) fragment_chunk_size  = $(get_val fragment_chunk_size)"
echo "0) Back"
echo
read -rp "Select: " c

case "$c" in
1) read -rp "New listen_host: " v; set_str listen_host "$v"; pause;;
2) read -rp "New listen_port: " v; set_int listen_port "$v"; pause;;
3) read -rp "New target_host: " v; set_str target_host "$v"; pause;;
4) read -rp "New target_port (your Hysteria2/Xray port): " v; set_int target_port "$v"; pause;;
5) read -rp "New info_encryption_pass: " v; set_str info_encryption_pass "$v"; pause;;
6) read -rp "New fragment_chunk_size [recommended: 1100]: " v; set_int fragment_chunk_size "$v"; pause;;
0) break;;
*) echo "Invalid"; sleep 1;;
esac
done
}

while true; do
clear
echo "===== QS+Slipstream Server ====="
echo "1) Start"
echo "2) Stop"
echo "3) Restart"
echo "4) Status"
echo "5) Logs"
echo "6) Follow Logs"
echo "7) Show Config"
echo "8) Edit Config / Ports"
echo "9) Show Listening Ports"
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
7) cat "$CONFIG"; pause;;
8) menu_edit;;
9) show_ports; pause;;
0) exit 0;;
*) echo "Invalid"; sleep 1;;
esac

done
