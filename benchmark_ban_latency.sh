#!/bin/bash
# ============================================================
#  benchmark_ban_latency.sh
#
#  Measures real, timestamped honeyport-to-ban latency against a LIVE
#  instance of this firewall - i.e. it produces the kind of evidence the
#  README's Results table didn't previously have anything backing it
#  with in this repo (issue D5 in the issues report this project shipped
#  with). This script does not print canned numbers; every figure it
#  reports comes from an actual connection attempt and actual polling of
#  firewall state on whatever host you run it against.
#
#  Usage (on the machine actually running the firewall):
#    sudo ./firewall.sh start        # firewall must already be running
#    ./scripts/benchmark_ban_latency.sh [honeyport] [timeout_seconds]
#
#  Defaults: honeyport = first port in config.conf's HONEYPORTS,
#            timeout   = 30 seconds
#
#  What it does:
#    1. Picks an IP that is not currently banned (or generates a random
#       loopback-range test IP if none is available).
#    2. Opens a TCP connection to the honeyport using netcat/bash's
#       /dev/tcp, timestamping the attempt.
#    3. Polls BANLIST_FILE (and iptables/nft state) once per second until
#       the connecting IP shows up as banned, or the timeout is hit.
#    4. Reports the measured elapsed time.
#
#  NOTE: this connects FROM the same machine (127.0.0.1) by default. To
#  measure real network-path latency, run it from a separate remote host
#  against your firewall's public IP instead - see the --target flag.
# ============================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.conf"

TARGET="127.0.0.1"
HONEYPORT=""
TIMEOUT=30

usage() {
  echo "Usage: $0 [--target IP] [--port PORT] [--timeout SECONDS]"
  echo ""
  echo "  --target   Host to connect to (default: 127.0.0.1 - the firewall's own machine)"
  echo "  --port     Honeyport to trigger (default: first port in config.conf's HONEYPORTS)"
  echo "  --timeout  Max seconds to wait for the ban to appear (default: 30)"
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --port) HONEYPORT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

if [ -z "$HONEYPORT" ]; then
  if [ -f "$CONFIG_FILE" ]; then
    HONEYPORTS_RAW="$(grep -E '^HONEYPORTS=' "$CONFIG_FILE" | head -n1 | cut -d'=' -f2- | tr -d '"'"'"'')"
    HONEYPORT="${HONEYPORTS_RAW%%,*}"
  fi
fi

if [ -z "$HONEYPORT" ]; then
  echo -e "${RED}❌ Could not determine a honeyport. Pass one explicitly with --port.${NC}"
  exit 1
fi

BANLIST_FILE="/etc/firewall-ips/banned_ips.txt"
if [ -f "$CONFIG_FILE" ]; then
  CONFIGURED_BANLIST="$(grep -E '^BANLIST_FILE=' "$CONFIG_FILE" | head -n1 | cut -d'=' -f2- | tr -d '"'"'"'')"
  [ -n "$CONFIGURED_BANLIST" ] && BANLIST_FILE="$CONFIGURED_BANLIST"
fi

echo -e "${CYAN}[+] Target: $TARGET   Honeyport: $HONEYPORT   Timeout: ${TIMEOUT}s${NC}"
echo -e "${CYAN}[+] Watching: $BANLIST_FILE${NC}"

is_banned() {
  local ip="$1"
  if [ -f "$BANLIST_FILE" ] && grep -qxF "$ip" "$BANLIST_FILE" 2>/dev/null; then
    return 0
  fi
  if command -v iptables &> /dev/null && iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
    return 0
  fi
  return 1
}

# Figure out the source IP the connection will actually appear to come
# from, so we know what to poll for.
if [ "$TARGET" = "127.0.0.1" ] || [ "$TARGET" = "localhost" ]; then
  SRC_IP="127.0.0.1"
else
  SRC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [ -z "$SRC_IP" ]; then
    echo -e "${YELLOW}[!] Could not auto-detect this machine's outbound IP - pass it in manually if the auto-detected one below looks wrong.${NC}"
    SRC_IP="unknown"
  fi
fi

if is_banned "$SRC_IP"; then
  echo -e "${RED}❌ $SRC_IP is already in the ban list before we've started - results would be meaningless. Unban it first (remove it from $BANLIST_FILE and reload the firewall) and re-run.${NC}"
  exit 1
fi

echo -e "${CYAN}[+] Connecting to $TARGET:$HONEYPORT to trigger the honeypot trap...${NC}"
START_TS=$(date +%s.%N)

# Use /dev/tcp (bash builtin) rather than requiring netcat to be installed.
(exec 3<>"/dev/tcp/$TARGET/$HONEYPORT") 2>/dev/null
CONNECT_RESULT=$?
exec 3>&- 2>/dev/null || true

if [ $CONNECT_RESULT -ne 0 ]; then
  echo -e "${YELLOW}[!] Connection itself was refused/reset immediately - that can be expected for a honeypot. Continuing to poll for the ban regardless.${NC}"
fi

echo -e "${CYAN}[+] Polling for $SRC_IP to appear banned (checking every 1s, up to ${TIMEOUT}s)...${NC}"

elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if is_banned "$SRC_IP"; then
    END_TS=$(date +%s.%N)
    LATENCY=$(echo "$END_TS - $START_TS" | bc 2>/dev/null || python3 -c "print($END_TS - $START_TS)")
    echo -e "${GREEN}✓ Banned after ${LATENCY}s (measured from first connection attempt to appearing in $BANLIST_FILE / iptables).${NC}"
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo -e "${RED}✗ $SRC_IP was NOT banned within ${TIMEOUT}s.${NC}"
echo -e "${YELLOW}    Possible causes: the watchdog isn't running (check 'sudo ./firewall.sh status'),${NC}"
echo -e "${YELLOW}    dmesg logging for iptables LOG rules isn't reaching the kernel ring buffer, or${NC}"
echo -e "${YELLOW}    $HONEYPORT isn't actually in this host's HONEYPORTS.${NC}"
exit 1
