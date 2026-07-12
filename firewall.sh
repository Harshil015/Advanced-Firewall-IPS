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

# Create persistence directory
mkdir -p $(dirname "$BANLIST_FILE")
touch "$BANLIST_FILE"

# ---------------------------
# ALERTING FUNCTION
# ---------------------------
send_alert() {
  local ip=$1
  local reason=$2
  echo -e "${RED}[ALERT] Banned IP: $ip (Reason: $reason)${NC}"
  
  # Log to persistent file
  echo "$ip" >> "$BANLIST_FILE"
  
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
  iptables -F
  iptables -X
  
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT
  
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Re-apply persistent bans from file
  echo -e "${CYAN}[+] Loading persistent ban list...${NC}"
  while read -r ip; do
    if [ -n "$ip" ]; then
      iptables -A INPUT -s "$ip" -j DROP
    fi
  done < "$BANLIST_FILE"

  # GeoIP Blocking
  if [ -n "$GEOIP_BLOCK" ]; then
    echo -e "${CYAN}[+] Applying GeoIP blocks for: $GEOIP_BLOCK...${NC}"
    # Note: Requires xtables-addons-common and geoip-database packages
    iptables -A INPUT -m geoip --src-cc "$GEOIP_BLOCK" -j DROP
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
    iptables -N HONEYPORT_$hp 2>/dev/null
    iptables -I INPUT 1 -p tcp --dport "$hp" -j HONEYPORT_$hp
    iptables -A HONEYPORT_$hp -j LOG --log-prefix "HONEYPORT ALERT: "
    iptables -A HONEYPORT_$hp -j DROP
  done

  # Rate Limiting
  IFS=',' read -ra PP_ARRAY <<< "$PROTECTED_PORTS"
  for port in "${PP_ARRAY[@]}"; do
    echo -e "${CYAN}[+] Applying rate-limiting on port $port ($MAX_CONN/min)...${NC}"
    iptables -N AUTOBAN_$port 2>/dev/null
    iptables -I INPUT 1 -p tcp --dport "$port" -j AUTOBAN_$port
    iptables -A AUTOBAN_$port -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${MAX_CONN}/minute" --hashlimit-burst "${MAX_CONN}" \
      -j LOG --log-prefix "IPTABLES DROP: "
    iptables -A AUTOBAN_$port -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${MAX_CONN}/minute" --hashlimit-burst "${MAX_CONN}" \
      -j DROP
    iptables -A AUTOBAN_$port -j ACCEPT
  done
}

# ---------------------------
# WATCHDOG DAEMON
# ---------------------------
start_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat $WATCHDOG_PID_FILE)" 2>/dev/null; then
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
        iptables -I INPUT 1 -s "$ip" -j DROP
        
        # Determine reason and send alert
        if echo "$line" | grep -q "HONEYPORT"; then
          reason="Honeyport Connection"
        else
          reason="Rate Limit Exceeded"
        fi
        
        # Call alert function
        echo "$ip" >> "$BANLIST_FILE"
        if [ -n "$WEBHOOK_URL" ]; then
          curl -s -X POST -H 'Content-type: application/json' \
          --data "{\"text\":\"🚨 Firewall Alert: Banned IP $ip. Reason: $reason.\"}" \
          "$WEBHOOK_URL" > /dev/null 2>&1 &
        fi
        echo "[Watchdog] Banned IP: $ip ($reason)"
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

# ---------------------------
# MAIN EXECUTION
# ---------------------------
echo -e "\n${CYAN}=======================================${NC}"
echo -e "${CYAN}   🔥 Advanced Firewall Manager v2.0${NC}"
echo -e "${CYAN}=======================================${NC}"

apply_base_rules
apply_custom_rules
start_watchdog

echo -e "${GREEN}[+] Firewall fully configured and active.${NC}"
echo -e "To start the web dashboard, run: ${CYAN}python3 dashboard.py${NC}"
