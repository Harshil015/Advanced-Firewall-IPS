#!/bin/bash
# ============================================================
#  populate_geoip_set.sh
#  Populates nftables.rules' `geoip_blocked` set with real country
#  CIDR blocks, since nftables has no built-in geoip matcher (see the
#  comment above `set geoip_blocked` in nftables.rules, and issue B1
#  in the issues report this repo shipped with).
#
#  Data source: ipdeny.com's per-country IP zone files
#  (https://www.ipdeny.com/ipblocks/), which are published specifically
#  for this use case ("...used to set-up firewall or packet filter
#  rules..."). This script uses the "aggregated" zone files, which
#  ipdeny recommends for firewall use since they mean fewer, larger
#  CIDR blocks and therefore a smaller/faster nftables set.
#
#  Usage:
#    sudo ./scripts/populate_geoip_set.sh                 # uses GEOIP_BLOCK from config.conf
#    sudo ./scripts/populate_geoip_set.sh CN RU            # explicit country codes
#
#  Re-run this periodically (e.g. via cron) to keep blocks current -
#  it always flushes and reloads the set from scratch, so it's safe
#  to run repeatedly.
# ============================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.conf"
TABLE="inet firewall"
SET_NAME="geoip_blocked"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ Please run as root (sudo ./scripts/populate_geoip_set.sh) - loading an nftables set requires root.${NC}"
  exit 1
fi

if ! command -v nft &> /dev/null; then
  echo -e "${RED}❌ nft not found. Install the 'nftables' package first.${NC}"
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo -e "${RED}❌ curl not found. Install curl first.${NC}"
  exit 1
fi

# Country codes: CLI args win; otherwise fall back to GEOIP_BLOCK in config.conf.
if [ "$#" -gt 0 ]; then
  RAW_CODES="$*"
elif [ -f "$CONFIG_FILE" ]; then
  RAW_CODES="$(grep -E '^GEOIP_BLOCK=' "$CONFIG_FILE" | head -n1 | cut -d'=' -f2- | tr -d '"'"'"'')"
else
  RAW_CODES=""
fi

if [ -z "$RAW_CODES" ]; then
  echo -e "${YELLOW}[!] No country codes given and GEOIP_BLOCK is empty in config.conf - nothing to do.${NC}"
  exit 0
fi

# Normalize "CN,RU" or "CN RU" into a clean lowercase array (ipdeny's zone
# filenames are lowercase, e.g. cn.zone).
IFS=', ' read -ra CODES <<< "$(echo "$RAW_CODES" | tr ',' ' ')"

if ! nft list table $TABLE &> /dev/null; then
  echo -e "${RED}❌ Table '$TABLE' isn't loaded. Run 'sudo nft -f nftables.rules' first.${NC}"
  exit 1
fi

echo -e "${CYAN}[+] Fetching aggregated CIDR zone files for: ${CODES[*]}${NC}"

ALL_BLOCKS=()
FAILED_CODES=()

for code in "${CODES[@]}"; do
  code_lc="$(echo "$code" | tr '[:upper:]' '[:lower:]')"
  [ -z "$code_lc" ] && continue
  url="https://www.ipdeny.com/ipblocks/data/aggregated/${code_lc}-aggregated.zone"
  outfile="$TMP_DIR/${code_lc}.zone"

  if curl -fsSL --max-time 15 -o "$outfile" "$url"; then
    count=$(grep -cve '^[[:space:]]*$' "$outfile" 2>/dev/null)
    count=${count:-0}
    echo -e "${GREEN}    ✓ ${code^^}: $count CIDR block(s) from $url${NC}"
    while read -r cidr; do
      [ -n "$cidr" ] && ALL_BLOCKS+=("$cidr")
    done < "$outfile"
  else
    echo -e "${RED}    ✗ ${code^^}: failed to download $url${NC}"
    FAILED_CODES+=("$code")
  fi
done

if [ "${#ALL_BLOCKS[@]}" -eq 0 ]; then
  echo -e "${RED}❌ No CIDR blocks were downloaded - leaving the existing set untouched.${NC}"
  exit 1
fi

# Build "1.2.3.0/24, 5.6.7.0/24, ..." and reload the set atomically: flush
# then add, so a failed run never leaves the set half-populated with a
# mix of old and new data.
JOINED="$(IFS=,; echo "${ALL_BLOCKS[*]}")"

echo -e "${CYAN}[+] Loading ${#ALL_BLOCKS[@]} total CIDR block(s) into set '$SET_NAME'...${NC}"
if nft flush set $TABLE "$SET_NAME" && nft add element $TABLE "$SET_NAME" "{ $JOINED }"; then
  echo -e "${GREEN}[+] Done. '$SET_NAME' now blocks ${#ALL_BLOCKS[@]} CIDR block(s) across: ${CODES[*]}${NC}"
else
  echo -e "${RED}❌ Failed to load elements into '$SET_NAME'. Is nftables.rules loaded? (sudo nft -f nftables.rules)${NC}"
  exit 1
fi

if [ "${#FAILED_CODES[@]}" -gt 0 ]; then
  echo -e "${YELLOW}[!] Note: ${#FAILED_CODES[@]} country code(s) failed to download and were skipped: ${FAILED_CODES[*]}${NC}"
  exit 1
fi
