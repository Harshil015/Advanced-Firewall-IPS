#!/bin/bash

# ============================================================
#  Advanced Linux Firewall & Intrusion Prevention System
#  Author: Harshil Makwana
#  Description:
#  Bash-based firewall using iptables featuring:
#    - Stateful packet inspection (conntrack)
#    - Honeyport intrusion detection
#    - Bash watchdog for automated log monitoring & IP banning
#    - True rate-limiting (hashlimit) for brute-force protection
#    - Safe logging and reset mechanisms
#
#  ⚠️ Run with sudo/root privileges
# ============================================================

set -uo pipefail

# ---------------------------
# CONFIGURATION
# ---------------------------
HONEYPORT_PREFIX="HONEYPORT ALERT"
IPTABLES_PREFIX="IPTABLES DROP"
WATCHDOG_PID_FILE="/tmp/firewall_watchdog.pid"
WATCHDOG_LOG_FILE="/tmp/firewall_watchdog.log"

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------------------------
# ROOT CHECK
# ---------------------------
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ Please run as root (sudo ./firewall.sh)${NC}"
  exit 1
fi

# ---------------------------
# HELPER FUNCTIONS
# ---------------------------
validate_port() {
  local port=$1
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo -e "${RED}❌ Invalid port number: $port${NC}"
    return 1
  fi
  return 0
}

rule_exists() {
  iptables -C "$@" 2>/dev/null
}

# ---------------------------
# 1️⃣ STATEFUL FIREWALL
# ---------------------------
enable_stateful() {
  echo -e "${CYAN}[+] Enabling Stateful Firewall...${NC}"

  iptables -F
  iptables -X

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  # Allow localhost
  iptables -A INPUT -i lo -j ACCEPT

  # Allow established sessions
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  echo -e "${GREEN}[+] Stateful firewall active. Default INPUT policy set to DROP.${NC}"
}

# ---------------------------
# 2️⃣ HONEYPORT
# ---------------------------
honeyport() {
  read -p "Enter honeyport (example: 2222): " hp
  validate_port "$hp" || return 1

  echo -e "${CYAN}[+] Setting honeyport on port $hp...${NC}"

  # Create chain if it doesn't exist
  iptables -N HONEYPORT 2>/dev/null

  # Insert rule at the top of INPUT so it triggers before ESTABLISHED/RELATED rules
  if ! rule_exists INPUT -p tcp --dport "$hp" -j HONEYPORT; then
    iptables -I INPUT 1 -p tcp --dport "$hp" -j HONEYPORT
  fi

  # Configure chain: Log, then Drop
  if ! rule_exists HONEYPORT -j LOG --log-prefix "$HONEYPORT_PREFIX: "; then
    iptables -A HONEYPORT -j LOG --log-prefix "$HONEYPORT_PREFIX: "
  fi
  if ! rule_exists HONEYPORT -j DROP; then
    iptables -A HONEYPORT -j DROP
  fi

  echo -e "${GREEN}[+] Honeyport enabled on port $hp.${NC}"
  echo -e "${YELLOW}⚠️  Ensure the Watchdog (Option 5) is running to auto-ban attackers hitting this port.${NC}"
}

# ---------------------------
# 3️⃣ RATE-LIMITING & AUTO-BAN
# ---------------------------
auto_ban() {
  read -p "Protect which port? (example: 22): " port
  validate_port "$port" || return 1
  
  read -p "Max connections per minute before ban? (example: 5): " max_conn
  if ! [[ "$max_conn" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Invalid number.${NC}"
    return 1
  fi

  echo -e "${CYAN}[+] Enabling rate-limiting on port $port ($max_conn/min max)...${NC}"

  iptables -N AUTOBAN 2>/dev/null

  # Insert at top of INPUT
  if ! rule_exists INPUT -p tcp --dport "$port" -j AUTOBAN; then
    iptables -I INPUT 1 -p tcp --dport "$port" -j AUTOBAN
  fi

  # True Rate Limiting using hashlimit
  if ! rule_exists AUTOBAN -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${max_conn}/minute" --hashlimit-burst "${max_conn}" \
      -j LOG --log-prefix "$IPTABLES_PREFIX: "; then
    iptables -A AUTOBAN -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${max_conn}/minute" --hashlimit-burst "${max_conn}" \
      -j LOG --log-prefix "$IPTABLES_PREFIX: "
  fi

  if ! rule_exists AUTOBAN -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${max_conn}/minute" --hashlimit-burst "${max_conn}" \
      -j DROP; then
    iptables -A AUTOBAN -m hashlimit --hashlimit-name "PORT_$port" \
      --hashlimit-above "${max_conn}/minute" --hashlimit-burst "${max_conn}" \
      -j DROP
  fi

  # Allow normal traffic that doesn't exceed the limit
  if ! rule_exists AUTOBAN -j ACCEPT; then
    iptables -A AUTOBAN -j ACCEPT
  fi

  echo -e "${GREEN}[+] Rate-limiting active on port $port.${NC}"
  echo -e "${YELLOW}⚠️  Ensure the Watchdog (Option 5) is running to permanently ban IPs triggering the rate limit.${NC}"
}

# ---------------------------
# 4️⃣ CATCH-ALL LOGGING
# ---------------------------
enable_logging() {
  echo -e "${CYan}[+] Enabling catch-all logging for dropped packets...${NC}"

  iptables -N LOGGING 2>/dev/null

  # Limit logs to prevent disk exhaustion (5 per min)
  if ! rule_exists LOGGING -m limit --limit 5/min -j LOG --log-prefix "$IPTABLES_PREFIX: "; then
    iptables -A LOGGING -m limit --limit 5/min -j LOG --log-prefix "$IPTABLES_PREFIX: "
  fi
  if ! rule_exists LOGGING -j DROP; then
    iptables -A LOGGING -j DROP
  fi

  # Append catch-all to the END of the INPUT chain
  if ! rule_exists INPUT -j LOGGING; then
    iptables -A INPUT -j LOGGING
  fi

  echo -e "${GREEN}[+] Logging enabled.${NC}"
  echo -e "View logs using: ${CYAN}sudo dmesg | grep IPTABLES${NC}"
}

# ---------------------------
# 5️⃣ WATCHDOG (AUTO-BAN DAEMON)
# ---------------------------
start_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat $WATCHDOG_PID_FILE)" 2>/dev/null; then
    echo -e "${YELLOW}[!] Watchdog is already running.${NC}"
    return
  fi

  echo -e "${CYAN}[+] Starting Auto-Ban Watchdog...${NC}"
  
  # Create the watchdog script dynamically
  cat << 'EOF' > /tmp/firewall_watchdog.sh
#!/bin/bash
# Watchdog script: Tails dmesg for IPTABLES logs and bans source IPs
dmesg -w | while read -r line; do
  if echo "$line" | grep -q "HONEYPORT ALERT\|IPTABLES DROP"; then
    # Extract Source IP using awk
    ip=$(echo "$line" | awk -F'SRC=' '{print $2}' | awk '{print $1}')
    if [ -n "$ip" ]; then
      # Check if already banned to avoid duplicate rules
      if ! iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Insert ban at the very top of INPUT
        iptables -I INPUT 1 -s "$ip" -j DROP
        echo "[Watchdog] Banned IP: $ip"
      fi
    fi
  fi
done
EOF
  chmod +x /tmp/firewall_watchdog.sh
  
  # Start in background
  nohup /tmp/firewall_watchdog.sh > "$WATCHDOG_LOG_FILE" 2>&1 &
  echo $! > "$WATCHDOG_PID_FILE"
  
  echo -e "${GREEN}[+] Watchdog started (PID: $(cat $WATCHDOG_PID_FILE)).${NC}"
  echo -e "Watchdog log: ${CYAN}$WATCHDOG_LOG_FILE${NC}"
}

stop_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    kill "$(cat $WATCHDOG_PID_FILE)" 2>/dev/null
    rm -f "$WATCHDOG_PID_FILE"
    rm -f /tmp/firewall_watchdog.sh
    echo -e "${GREEN}[+] Watchdog stopped.${NC}"
  else
    echo -e "${YELLOW}[!] Watchdog is not running.${NC}"
  fi
}

# ---------------------------
# 6️⃣ SHOW RULES & STATUS
# ---------------------------
show_rules() {
  echo -e "${CYAN}=== Active iptables Rules ===${NC}"
  iptables -L -n -v --line-numbers
  
  echo -e "\n${CYAN}=== Watchdog Status ===${NC}"
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat $WATCHDOG_PID_FILE)" 2>/dev/null; then
    echo -e "${GREEN}Running (PID: $(cat $WATCHDOG_PID_FILE))${NC}"
  else
    echo -e "${RED}Stopped${NC}"
  fi
}

# ---------------------------
# 7️⃣ FLUSH & RESET
# ---------------------------
flush_all() {
  read -p "⚠️  Reset firewall to ACCEPT all and stop watchdog? (y/n): " confirm

  if [[ $confirm == "y" ]]; then
    stop_watchdog
    
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT

    echo -e "${GREEN}[+] Firewall reset complete. All policies set to ACCEPT.${NC}"
  else
    echo -e "${YELLOW}[!] Reset cancelled.${NC}"
  fi
}

# ---------------------------
# MENU LOOP
# ---------------------------
while true; do
  echo -e "\n${CYAN}=======================================${NC}"
  echo -e "${CYAN}   🔥 Advanced Firewall Manager${NC}"
  echo -e "${CYAN}=======================================${NC}"
  echo "1) Enable Stateful Firewall"
  echo "2) Enable Honeyport Auto-Ban"
  echo "3) Enable Rate-Limiting (Brute-force protection)"
  echo "4) Enable Catch-all Logging"
  echo "5) Start Watchdog Daemon (Auto-Banner)"
  echo "6) Stop Watchdog Daemon"
  echo "7) Show Rules & Status"
  echo "8) Flush & Reset Firewall"
  echo "9) Exit"
  echo -e "${CYAN}=======================================${NC}"

  read -p "Select an option: " opt

  case $opt in
    1) enable_stateful ;;
    2) honeyport ;;
    3) auto_ban ;;
    4) enable_logging ;;
    5) start_watchdog ;;
    6) stop_watchdog ;;
    7) show_rules ;;
    8) flush_all ;;
    9) echo "Exiting..."; break ;;
    *) echo -e "${RED}Invalid option.${NC}" ;;
  esac
done
