#!/bin/bash

# ============================================================
#  Advanced Linux Firewall & Intrusion Prevention System
#  Author: Your Name
#  Description:
#  Bash-based firewall using iptables featuring:
#    - Stateful packet inspection (conntrack)
#    - Honeyport intrusion detection
#    - Fail2ban-style auto-banning
#    - Logging
#    - Safe reset mechanism
#
#  ⚠️ Run with sudo/root privileges
# ============================================================

# ---------------------------
# ROOT CHECK
# ---------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root (sudo ./firewall_super_advanced.sh)"
  exit 1
fi

# ---------------------------
# MENU
# ---------------------------
echo "======================================="
echo "   🔥 Advanced Firewall Manager"
echo "======================================="
echo "1) Enable Stateful Firewall"
echo "2) Enable Honeyport Auto-Ban"
echo "3) Enable Auto-Ban Protection"
echo "4) Enable Logging"
echo "5) Show Rules"
echo "6) Flush & Reset Firewall"
echo "7) Exit"
echo "======================================="

read -p "Select an option: " opt

# ============================================================
# 1️⃣ STATEFUL FIREWALL
# ============================================================
enable_stateful() {
  echo "[+] Enabling Stateful Firewall..."

  iptables -F
  iptables -X

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  # Allow established sessions
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Allow localhost
  iptables -A INPUT -i lo -j ACCEPT

  echo "[+] Stateful firewall active."
}

# ============================================================
# 2️⃣ HONEYPORT
# ============================================================
honeyport() {
  read -p "Enter honeyport (example: 2222): " hp

  echo "[+] Setting honeyport on port $hp"

  iptables -N HONEYPORT 2>/dev/null

  iptables -A INPUT -p tcp --dport $hp -j HONEYPORT
  iptables -A HONEYPORT -m recent --name HONEYPOT --set
  iptables -A HONEYPORT -j LOG --log-prefix "HONEYPORT ALERT: "
  iptables -A HONEYPORT -j DROP

  # Ban attacker for 5 minutes
  iptables -A INPUT -m recent --name HONEYPOT --update --seconds 300 -j DROP

  echo "[+] Honeyport enabled. Attackers will be auto-banned."
}

# ============================================================
# 3️⃣ AUTO-BAN (FAIL2BAN-LIKE)
# ============================================================
auto_ban() {
  read -p "Protect which port? (example: 22): " port

  echo "[+] Protecting port $port"

  iptables -N AUTOBAN 2>/dev/null

  iptables -A INPUT -p tcp --dport $port -m recent --name BANLIST --set
  iptables -A INPUT -p tcp --dport $port -m recent --name BANLIST --update --seconds 60 --hitcount 5 -j DROP
  iptables -A INPUT -p tcp --dport $port -j ACCEPT

  echo "[+] Auto-ban active (5 attempts in 60s = blocked)."
}

# ============================================================
# 4️⃣ LOGGING
# ============================================================
enable_logging() {
  echo "[+] Enabling logging..."

  iptables -N LOGGING 2>/dev/null
  iptables -A INPUT -j LOGGING
  iptables -A LOGGING -m limit --limit 5/min -j LOG --log-prefix "IPTABLES DROP: "
  iptables -A LOGGING -j DROP

  echo "[+] Logging enabled."
  echo "View logs using:"
  echo "sudo dmesg | grep IPTABLES"
}

# ============================================================
# 5️⃣ SHOW RULES
# ============================================================
show_rules() {
  iptables -L -n --line-numbers
}

# ============================================================
# 6️⃣ FLUSH & RESET
# ============================================================
flush_all() {
  read -p "⚠️ Reset firewall to ACCEPT all? (y/n): " confirm

  if [[ $confirm == "y" ]]; then
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X

    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT

    echo "[+] Firewall reset complete."
  else
    echo "[!] Reset cancelled."
  fi
}

# ============================================================
# EXECUTION
# ============================================================
case $opt in
  1) enable_stateful ;;
  2) honeyport ;;
  3) auto_ban ;;
  4) enable_logging ;;
  5) show_rules ;;
  6) flush_all ;;
  7) exit ;;
  *) echo "Invalid option." ;;
esac
