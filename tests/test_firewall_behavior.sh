#!/bin/bash

# ============================================================
#  Firewall Script Behavioral Tests  (fixes C2)
#
#  Every other test file in this suite is textual: it greps firewall.sh's
#  source for expected strings, but never actually RUNS it. That gap is
#  exactly how issue A1 (no start/stop/status handling - every invocation
#  ran the same code) made it into a "fully tested" project in the first
#  place: no test ever actually called `./firewall.sh stop` and checked
#  what it did.
#
#  This file closes that gap the same way the issues report itself did:
#  put a logging shim named `iptables` at the front of PATH, actually run
#  firewall.sh against it, and inspect what it really called - instead of
#  grepping the source for the word "stop".
#
#  Requires root (matches firewall.sh's own root requirement) since
#  firewall.sh checks $EUID, which cannot be overridden from a test
#  harness - and deliberately should not be able to be, for a firewall
#  script. Skips gracefully (not a failure) when not root, the same
#  pattern this project already uses for other environment-dependent
#  checks (see test_iptables_available in test_requirements.sh).
# ============================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}⚠ WARNING: not running as root - firewall.sh refuses to run at all without root (by design), so these behavioral tests can't execute here. Skipping, not failing. Re-run this suite with sudo to exercise them.${NC}"
  exit 0
fi

WORKDIR="$(mktemp -d)"
MOCK_BIN="$WORKDIR/bin"
TESTREPO="$WORKDIR/repo"
mkdir -p "$MOCK_BIN" "$TESTREPO"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Work on a throwaway copy so nothing here can affect the real repo checkout.
cp "$REPO_ROOT/firewall.sh" "$TESTREPO/firewall.sh"
cp "$REPO_ROOT/config.conf" "$TESTREPO/config.conf"
chmod +x "$TESTREPO/firewall.sh"
# Give this test its own BANLIST_FILE so it never touches the real one.
sed -i "s#^BANLIST_FILE=.*#BANLIST_FILE=\"$WORKDIR/banned_ips.txt\"#" "$TESTREPO/config.conf"

# --- Mock iptables: logs every call instead of touching the kernel ---
cat > "$MOCK_BIN/iptables" << 'MOCKEOF'
#!/bin/bash
echo "IPTABLES_CALL: $*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-L" ]]; then
  echo "Chain INPUT (policy DROP)"
fi
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/iptables"

run_firewall() {
  # $1 = subcommand, $2 = path to write the call trace to
  ( cd "$TESTREPO" && MOCK_LOG="$2" PATH="$MOCK_BIN:$PATH" ./firewall.sh "$1" )
}

print_test() {
  local name="$1" passed="$2" detail="${3:-}"
  if [ "$passed" = "1" ]; then
    echo -e "${GREEN}✓ PASS: $name${NC}"
    [ -n "$detail" ] && echo "  $detail"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: $name${NC}"
    [ -n "$detail" ] && echo "  $detail"
    ((TESTS_FAILED++))
  fi
}

echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   🔥 Firewall Behavioral Test Suite${NC}"
echo -e "${CYAN}=================================================${NC}\n"

# --- Test 1: start applies a DROP policy and makes iptables calls ---
echo -e "${CYAN}[TEST 1] Running './firewall.sh start' against mocked iptables...${NC}"
START_LOG="$WORKDIR/trace_start.log"
: > "$START_LOG"
run_firewall start "$START_LOG" > "$WORKDIR/start_stdout.log" 2>&1
start_exit=$?
start_called_drop_policy=0
grep -q -- "-P INPUT DROP" "$START_LOG" && start_called_drop_policy=1
print_test "start applies INPUT DROP policy" "$start_called_drop_policy" \
  "exit=$start_exit, calls logged=$(wc -l < "$START_LOG")"

# --- Test 2: stop is DIFFERENT from start, and resets policy to ACCEPT ---
# This is precisely the check that would have caught A1: prior to the fix,
# start and stop ran identical code, so their call traces were identical.
echo -e "${CYAN}[TEST 2] Running './firewall.sh stop' and diffing it against start...${NC}"
STOP_LOG="$WORKDIR/trace_stop.log"
: > "$STOP_LOG"
run_firewall stop "$STOP_LOG" > "$WORKDIR/stop_stdout.log" 2>&1
stop_exit=$?

traces_differ=0
diff -q "$START_LOG" "$STOP_LOG" > /dev/null 2>&1 || traces_differ=1
print_test "stop's call trace differs from start's" "$traces_differ" \
  "start had $(wc -l < "$START_LOG") calls, stop had $(wc -l < "$STOP_LOG") calls"

stop_restores_accept=0
grep -q -- "-P INPUT ACCEPT" "$STOP_LOG" && stop_restores_accept=1
print_test "stop resets INPUT policy to ACCEPT" "$stop_restores_accept"

stop_does_not_set_drop=1
grep -q -- "-P INPUT DROP" "$STOP_LOG" && stop_does_not_set_drop=0
print_test "stop does NOT (re-)apply a DROP policy" "$stop_does_not_set_drop"

# --- Test 3: status is read-only - makes no mutating iptables calls ---
echo -e "${CYAN}[TEST 3] Running './firewall.sh status' and confirming it's read-only...${NC}"
STATUS_LOG="$WORKDIR/trace_status.log"
: > "$STATUS_LOG"
run_firewall status "$STATUS_LOG" > "$WORKDIR/status_stdout.log" 2>&1
status_exit=$?

status_is_readonly=1
grep -qE -- "-(F|X|P|I|A) " "$STATUS_LOG" 2>/dev/null && status_is_readonly=0
print_test "status makes no mutating iptables calls (no -F/-X/-P/-I/-A)" "$status_is_readonly" \
  "calls logged: $(cat "$STATUS_LOG" 2>/dev/null | tr '\n' ' ')"

status_shows_rules=0
grep -q "Chain INPUT" "$WORKDIR/status_stdout.log" && status_shows_rules=1
print_test "status prints the current rule listing" "$status_shows_rules"

# --- Test 4: no argument / unknown argument does NOT silently apply the firewall ---
# Before the fix, running with no argument at all applied the full ruleset -
# a script silently doing something destructive when given no instruction.
echo -e "${CYAN}[TEST 4] Running './firewall.sh' with no argument...${NC}"
NOARG_LOG="$WORKDIR/trace_noarg.log"
run_firewall "" "$NOARG_LOG" > "$WORKDIR/noarg_stdout.log" 2>&1
noarg_exit=$?

noarg_made_no_calls=1
[ -s "$NOARG_LOG" ] && noarg_made_no_calls=0
print_test "no argument makes zero iptables calls" "$noarg_made_no_calls"

noarg_nonzero_exit=0
[ "$noarg_exit" -ne 0 ] && noarg_nonzero_exit=1
print_test "no argument exits non-zero (usage error, not silent success)" "$noarg_nonzero_exit" \
  "exit code: $noarg_exit"

# --- Test 5: rule ORDER - loopback/established must end up above
# honeypot/rate-limit rules (fixes A4). Reconstruct the actual final
# INPUT chain order from the real call trace, the same way iptables
# itself would build it from a sequence of -A (append) / -I INPUT 1
# (insert-at-top) calls.
echo -e "${CYAN}[TEST 5] Reconstructing final INPUT chain order from the start trace...${NC}"
final_order=$(python3 - "$START_LOG" << 'PYEOF'
import sys
chain = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line.startswith("IPTABLES_CALL:"):
            continue
        call = line[len("IPTABLES_CALL: "):]
        parts = call.split()
        if len(parts) < 2:
            continue
        if parts[0] == "-A" and parts[1] == "INPUT":
            chain.append(call)
        elif parts[0] == "-I" and parts[1] == "INPUT" and len(parts) > 2 and parts[2] == "1":
            chain.insert(0, call)
for rule in chain:
    print(rule)
PYEOF
)

first_rule=$(echo "$final_order" | head -n1)
second_rule=$(echo "$final_order" | sed -n '2p')

loopback_is_first=0
echo "$first_rule" | grep -q -- "-i lo -j ACCEPT" && loopback_is_first=1
print_test "loopback accept is the FIRST rule in the final chain" "$loopback_is_first" \
  "first rule was: $first_rule"

established_is_second=0
echo "$second_rule" | grep -q -- "ESTABLISHED,RELATED -j ACCEPT" && established_is_second=1
print_test "established/related accept is the SECOND rule in the final chain" "$established_is_second" \
  "second rule was: $second_rule"

# Summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${CYAN}Total: $((TESTS_PASSED + TESTS_FAILED))${NC}\n"

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo -e "${GREEN}✓ All firewall behavioral tests passed!${NC}\n"
  exit 0
else
  echo -e "${RED}✗ Some tests failed. Please review firewall.sh.${NC}\n"
  exit 1
fi
