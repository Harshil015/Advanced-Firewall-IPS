#!/bin/bash

# ============================================================
#  nftables Rules File Tests
#  Validates nftables.rules syntax and configuration
# ============================================================

set -uo pipefail

NFTABLES_FILE="./nftables.rules"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: nftables.rules file exists
test_nftables_exists() {
  echo -e "${CYAN}[TEST 1] Checking if nftables.rules exists...${NC}"
  if [ -f "$NFTABLES_FILE" ]; then
    echo -e "${GREEN}✓ PASS: nftables.rules found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: nftables.rules not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 2: File has valid shebang for nft
test_shebang() {
  echo -e "${CYAN}[TEST 2] Checking for valid nft shebang...${NC}"
  if head -n 1 "$NFTABLES_FILE" | grep -q "^#!/.*nft"; then
    echo -e "${GREEN}✓ PASS: Valid nft shebang found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Invalid or missing nft shebang${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 3: Check for table definition
test_table_definition() {
  echo -e "${CYAN}[TEST 3] Checking for nftables table definition...${NC}"
  if grep -q 'table.*firewall' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Table definition found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Table definition not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 4: Check for input chain
test_input_chain() {
  echo -e "${CYAN}[TEST 4] Checking for input chain...${NC}"
  if grep -q 'chain input' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Input chain defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Input chain not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 5: Check for forward chain
test_forward_chain() {
  echo -e "${CYAN}[TEST 5] Checking for forward chain...${NC}"
  if grep -q 'chain forward' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Forward chain defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Forward chain not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 6: Check for output chain
test_output_chain() {
  echo -e "${CYAN}[TEST 6] Checking for output chain...${NC}"
  if grep -q 'chain output' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Output chain defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Output chain not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 7: Check for honeypot set definition
test_honeypot_set() {
  echo -e "${CYAN}[TEST 7] Checking for honeypot ban set...${NC}"
  if grep -q 'set honeypot_bans' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Honeypot ban set defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Honeypot ban set not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 8: Check for rate limit set definition
test_rate_limit_set() {
  echo -e "${CYAN}[TEST 8] Checking for rate limit set...${NC}"
  if grep -q 'set rate_limit_bans' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Rate limit ban set defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Rate limit ban set not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 9: Check for localhost allow rule
test_localhost_rule() {
  echo -e "${CYAN}[TEST 9] Checking for localhost (loopback) allow rule...${NC}"
  if grep -q 'iif "lo" accept' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Localhost allow rule found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Localhost allow rule not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 10: Check for established/related connections rule
test_established_rule() {
  echo -e "${CYAN}[TEST 10] Checking for established/related connections rule...${NC}"
  if grep -q 'ct state established' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Established/related rule found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Established/related rule not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 11: Check for honeyport rules
test_honeyport_rules() {
  echo -e "${CYAN}[TEST 11] Checking for honeyport definitions...${NC}"
  if grep -q 'dport.*2222.*8080.*9999' "$NFTABLES_FILE" || grep -q 'dport { 2222' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Honeyport rules defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Honeyport rules not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 12: Check for logging rules
test_logging_rules() {
  echo -e "${CYAN}[TEST 12] Checking for logging configuration...${NC}"
  if grep -q 'log prefix' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: Logging rules defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Logging rules not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 13: Check for HTTP/HTTPS allow rules
test_http_https_rules() {
  echo -e "${CYAN}[TEST 13] Checking for HTTP/HTTPS allow rules...${NC}"
  if grep -q 'dport.*80.*443' "$NFTABLES_FILE" || grep -q 'dport { 80, 443' "$NFTABLES_FILE"; then
    echo -e "${GREEN}✓ PASS: HTTP/HTTPS rules defined${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: HTTP/HTTPS rules not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 14: Actually parse the ruleset with nft's own syntax checker
# (fixes C2). Every test above this line is textual - it greps the file
# for expected substrings, but a file can contain all the right
# substrings and still be syntactically invalid nftables (wrong
# punctuation, bad set flags, etc). `nft -c` is a real, non-mutating
# dry-run parse: it validates the file exactly the way `nft -f` would
# without touching any live ruleset, so it's safe to run in CI/tests.
# Gracefully skipped (not failed) if nft isn't installed, matching the
# project's existing convention for environment-dependent checks.
test_nft_syntax_check() {
  echo -e "${CYAN}[TEST 14] Validating with nft's real syntax checker (nft -c)...${NC}"
  if ! command -v nft &> /dev/null; then
    echo -e "${YELLOW}⚠ WARNING: nft not installed in this environment - skipping real syntax check. Not counted as a failure, but nftables.rules has NOT been validated by the actual nft parser.${NC}"
    return
  fi

  local nft_output
  if nft_output=$(nft -c -f "$NFTABLES_FILE" 2>&1); then
    echo -e "${GREEN}✓ PASS: nft -c confirms nftables.rules is valid, parseable syntax${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: nft rejected nftables.rules:${NC}"
    echo -e "${RED}$nft_output${NC}"
    ((TESTS_FAILED++))
  fi
}

# ============================================================
# Run all tests
# ============================================================
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   🛡️  nftables Rules Test Suite${NC}"
echo -e "${CYAN}=================================================${NC}\n"

test_nftables_exists
test_shebang
test_table_definition
test_input_chain
test_forward_chain
test_output_chain
test_honeypot_set
test_rate_limit_set
test_localhost_rule
test_established_rule
test_honeyport_rules
test_logging_rules
test_http_https_rules
test_nft_syntax_check

# Summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${CYAN}Total: $((TESTS_PASSED + TESTS_FAILED))${NC}\n"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All nftables tests passed!${NC}\n"
  exit 0
else
  echo -e "${RED}✗ Some tests failed. Please review the nftables configuration.${NC}\n"
  exit 1
fi
