#!/bin/bash

# ============================================================
#  Advanced Linux Firewall & IPS (v2.0)
#  Author: Harshil Makwana
# ============================================================

set -uo pipefail

CONFIG_FILE="./config.conf"
WATCHDOG_PID_FILE="/tmp/firewall_watchdog.pid"

# Load Config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Config file not found at $CONFIG_FILE"
    exit 1
fi

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ Please run as root (sudo ./firewall.sh)${NC}"
  exit 1
fi

# Create persistence directory (quoting fixes D3 - an unquoted $(dirname ...)
# would word-split on a BANLIST_FILE path containing spaces)
mkdir -p "$(dirname "$BANLIST_FILE")"
touch "$BANLIST_FILE"

# ---------------------------
# ERROR-CHECKED IPTABLES WRAPPERS
# ---------------------------
# Fixes A2: previously NOTHING checked whether an iptables call actually
# succeeded, so the script printed full green "success" messages and
# exited 0 even when every single rule failed to apply. Every iptables
# call in this file now goes through one of these two wrappers.
IPTABLES_ERRORS=0

# General-purpose wrapper: logs + counts any failure.
run_iptables() {
  if ! iptables "$@"; then
    echo -e "${RED}[!] iptables command failed: iptables $*${NC}" >&2
    IPTABLES_ERRORS=$((IPTABLES_ERRORS + 1))
    return 1
  fi
  return 0
}

# Chain-creation wrapper: "chain already exists" is expected and harmless
# (e.g. after an interrupted previous run) and should NOT be treated as a
# real failure or alarm the operator - but any OTHER failure reason
# (permissions, missing kernel module, etc.) genuinely should be.
ensure_chain() {
  local chain="$1"
  local err
  if ! err=$(iptables -N "$chain" 2>&1); then
    if ! echo "$err" | grep -qi "already exists"; then
      echo -e "${RED}[!] iptables command failed: iptables -N $chain${NC}" >&2
      echo -e "${RED}    $err${NC}" >&2
      IPTABLES_ERRORS=$((IPTABLES_ERRORS + 1))
    fi
  fi
}

# ---------------------------
# ALERTING FUNCTION
# ---------------------------
send_alert() {
  local ip=$1
  local reason=$2
  echo -e "${RED}[ALERT] Banned IP: $ip (Reason: $reason)${NC}"

  # Log to persistent file - skip if already recorded (fixes D2: every
  # restart flushes kernel state via `-F`, so a repeat offender banned in
  # a previous session looks "new" to a kernel-state-only duplicate check
  # and would otherwise be appended again on every restart).
  if ! grep -qxF "$ip" "$BANLIST_FILE" 2>/dev/null; then
    echo "$ip" >> "$BANLIST_FILE"
  fi

  # Send Webhook (Slack/Discord)
  if [ -n "$WEBHOOK_URL" ]; then
    curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"🚨 Firewall Alert: Banned IP $ip. Reason: $reason.\"}" \
    "$WEBHOOK_URL" > /dev/null 2>&1 &
  fi
}

# ---------------------------
# APPLY STATEFUL FIREWALL & GEOIP
# ---------------------------
apply_base_rules() {
  echo -e "${CYAN}[+] Applying Stateful Firewall...${NC}"
  run_iptables -F
  run_iptables -X

  run_iptables -P INPUT DROP
  run_iptables -P FORWARD DROP
  run_iptables -P OUTPUT ACCEPT

  # NOTE: the loopback-accept and established/related-accept rules used to
  # live here. They now get applied last, in apply_priority_rules() below -
  # see that function for why (fixes A4).

  # Re-apply persistent bans from file
  echo -e "${CYAN}[+] Loading persistent ban list...${NC}"
  while read -r ip; do
    if [ -n "$ip" ]; then
      run_iptables -A INPUT -s "$ip" -j DROP
    fi
  done < "$BANLIST_FILE"

  # GeoIP Blocking
  if [ -n "$GEOIP_BLOCK" ]; then
    echo -e "${CYAN}[+] Applying GeoIP blocks for: $GEOIP_BLOCK...${NC}"
    # Note: Requires xtables-addons-common and geoip-database packages
    run_iptables -A INPUT -m geoip --src-cc "$GEOIP_BLOCK" -j DROP
  fi
}

# ---------------------------
# APPLY HONEYPORTS & RATE LIMITS
# ---------------------------
apply_custom_rules() {
  # Honeyports
  IFS=',' read -ra HP_ARRAY <<< "$HONEYPORTS"
  for hp in "${HP_ARRAY[@]}"; do
    echo -e "${CYAN}[+] Setting honeyport on $hp...${NC}"
    ensure_chain "HONEYPORT_$hp"
    run_iptables -I INPUT 1 -p tcp --dport "$hp" -j "HONEYPORT_$hp"
    run_iptables -A "HONEYPORT_$hp" -j LOG --log-prefix "HONEYPORT ALERT: "
    run_iptables -A "HONEYPORT_$hp" -j DROP
  done

  # Rate Limiting
  IFS=',' read -ra PP_ARRAY <<< "$PROTECTED_PORTS"
  for port in "${PP_ARRAY[@]}"; do
    echo -e "${CYAN}[+] Applying rate-limiting on port $port ($MAX_CONN/min)...${NC}"
    ensure_chain "AUTOBAN_$port"
    run_iptables -I INPUT 1 -p tcp --dport "$port" -j "AUTOBAN_$port"
    run_iptables -A "AUTOBAN_$port" -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${MAX_CONN}/minute" --hashlimit-burst "${MAX_CONN}" \
      -j LOG --log-prefix "IPTABLES DROP: "
    run_iptables -A "AUTOBAN_$port" -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${MAX_CONN}/minute" --hashlimit-burst "${MAX_CONN}" \
      -j DROP
    run_iptables -A "AUTOBAN_$port" -j ACCEPT
  done
}

# ---------------------------
# PRIORITY ACCEPT RULES
# ---------------------------
# Fixes A4: apply_base_rules() used to APPEND the loopback-accept and
# established/related-accept rules (so they landed at the bottom of an
# empty chain), and apply_custom_rules() then INSERTED every honeypot and
# rate-limit rule at position 1 (so the LAST one inserted ends up FIRST).
# Net effect: every honeypot/rate-limit rule ended up sitting ABOVE the
# loopback rule, so even a connection to a honeyport from 127.0.0.1 itself
# hit the trap before ever reaching "-i lo -j ACCEPT".
#
# The fix: apply these two rules LAST (after apply_custom_rules has done
# its inserting) and INSERT them too, in this specific order, so they end
# up pinned at positions 1 and 2 - above everything custom_rules added.
apply_priority_rules() {
  echo -e "${CYAN}[+] Pinning loopback & established/related rules above honeypot/rate-limit rules...${NC}"
  # Insert established/related first, then loopback - since each -I INPUT 1
  # pushes the previous top rule down, loopback (inserted last) ends up
  # truly first.
  run_iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  run_iptables -I INPUT 1 -i lo -j ACCEPT
}

# ---------------------------
# WATCHDOG DAEMON
# ---------------------------
start_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null; then
    echo -e "${YELLOW}[!] Watchdog is already running.${NC}"
    return
  fi

  echo -e "${CYAN}[+] Starting Auto-Ban Watchdog...${NC}"
  cat << 'EOF' > /tmp/firewall_watchdog.sh
#!/bin/bash
source ./config.conf
dmesg -w | while read -r line; do
  if echo "$line" | grep -q "HONEYPORT ALERT\|IPTABLES DROP"; then
    ip=$(echo "$line" | awk -F'SRC=' '{print $2}' | awk '{print $1}')
    if [ -n "$ip" ]; then
      if ! iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
        if iptables -I INPUT 1 -s "$ip" -j DROP; then
          # Determine reason and send alert
          if echo "$line" | grep -q "HONEYPORT"; then
            reason="Honeyport Connection"
          else
            reason="Rate Limit Exceeded"
          fi

          # Record the ban - skip if this IP is already in the file from a
          # previous session (fixes D2; see send_alert()'s comment above).
          if ! grep -qxF "$ip" "$BANLIST_FILE" 2>/dev/null; then
            echo "$ip" >> "$BANLIST_FILE"
          fi
          if [ -n "$WEBHOOK_URL" ]; then
            curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 Firewall Alert: Banned IP $ip. Reason: $reason.\"}" \
            "$WEBHOOK_URL" > /dev/null 2>&1 &
          fi
          echo "[Watchdog] Banned IP: $ip ($reason)"
        else
          # Fixes A2 in the watchdog's own runtime path too: don't claim a
          # ban happened (and don't fire a webhook about it) if the DROP
          # rule itself failed to insert.
          echo "[Watchdog] ERROR: failed to insert DROP rule for $ip - it is NOT banned." >&2
        fi
      fi
    fi
  fi
done
EOF
  chmod +x /tmp/firewall_watchdog.sh
  nohup /tmp/firewall_watchdog.sh > /tmp/firewall_watchdog.log 2>&1 &
  echo $! > "$WATCHDOG_PID_FILE"
  echo -e "${GREEN}[+] Watchdog started.${NC}"
}

stop_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    local wpid
    wpid="$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)"
    if [ -n "$wpid" ] && kill -0 "$wpid" 2>/dev/null; then
      kill "$wpid" 2>/dev/null
      echo -e "${GREEN}[+] Watchdog (PID $wpid) stopped.${NC}"
    else
      echo -e "${YELLOW}[!] Watchdog PID file present but process was not running.${NC}"
    fi
    rm -f "$WATCHDOG_PID_FILE"
  else
    echo -e "${YELLOW}[!] No watchdog PID file found; watchdog may not have been running.${NC}"
  fi
}

# ---------------------------
# MAIN EXECUTION
# ---------------------------
# Fixes A1: there used to be NO argument handling at all - `start`, `stop`,
# `status`, and even no argument ran the exact same code (which applies the
# firewall). Running `./firewall.sh stop` set INPUT's policy to DROP, the
# opposite of what stopping a firewall should do, with no code path that
# ever flushed rules back to ACCEPT.
print_banner() {
  echo -e "\n${CYAN}=======================================${NC}"
  echo -e "${CYAN}   🔥 Advanced Firewall Manager v2.0${NC}"
  echo -e "${CYAN}=======================================${NC}"
}

do_start() {
  print_banner
  apply_base_rules
  apply_custom_rules
  apply_priority_rules
  start_watchdog

  if [ "$IPTABLES_ERRORS" -gt 0 ]; then
    echo -e "${RED}[!] Firewall started with $IPTABLES_ERRORS failed iptables command(s) - see above. This host may NOT be fully protected.${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] Firewall fully configured and active.${NC}"
  echo -e "To start the web dashboard, run: ${CYAN}python3 dashboard.py${NC}"
}

do_stop() {
  print_banner
  echo -e "${CYAN}[+] Stopping firewall and flushing all rules...${NC}"

  run_iptables -F
  run_iptables -X
  run_iptables -P INPUT ACCEPT
  run_iptables -P FORWARD ACCEPT
  run_iptables -P OUTPUT ACCEPT

  stop_watchdog

  if [ "$IPTABLES_ERRORS" -gt 0 ]; then
    echo -e "${RED}[!] Stop completed with $IPTABLES_ERRORS failed iptables command(s) - rules may not be fully flushed.${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] Firewall stopped. All rules flushed, policies reset to ACCEPT.${NC}"
}

do_status() {
  print_banner
  echo -e "${CYAN}[+] Current iptables rules:${NC}"
  if ! iptables -L -n -v --line-numbers; then
    echo -e "${RED}[!] Failed to read iptables rules (are you root? is iptables installed?)${NC}"
  fi

  echo ""
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo -e "${GREEN}[+] Watchdog: RUNNING (PID $(cat "$WATCHDOG_PID_FILE"))${NC}"
  else
    echo -e "${YELLOW}[!] Watchdog: NOT RUNNING${NC}"
  fi

  echo ""
  if [ -f "$BANLIST_FILE" ]; then
    local ban_count
    ban_count=$(grep -cve '^[[:space:]]*$' "$BANLIST_FILE" 2>/dev/null)
    ban_count=${ban_count:-0}
    echo -e "${CYAN}[+] Persistent ban list: $ban_count IP(s) in $BANLIST_FILE${NC}"
  fi
}

usage() {
  echo -e "${YELLOW}Usage: $0 {start|stop|status}${NC}"
  exit 1
}

case "${1:-}" in
  start)
    do_start
    ;;
  stop)
    do_stop
    ;;
  status)
    do_status
    ;;
  *)
    usage
    ;;
esac
