#!/bin/bash

# ============================================================
#  Firewall Script Syntax & Logic Tests
#  Tests bash syntax, function definitions, and logic flow
# ============================================================

set -uo pipefail

FIREWALL_SCRIPT="./firewall.sh"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Script file exists
test_script_exists() {
  echo -e "${CYAN}[TEST 1] Checking if firewall.sh exists...${NC}"
  if [ -f "$FIREWALL_SCRIPT" ]; then
    echo -e "${GREEN}✓ PASS: Script found at $FIREWALL_SCRIPT${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Script not found at $FIREWALL_SCRIPT${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 2: Script has shebang
test_shebang() {
  echo -e "${CYAN}[TEST 2] Checking for valid shebang...${NC}"
  if head -n 1 "$FIREWALL_SCRIPT" | grep -q "^#!/bin/bash"; then
    echo -e "${GREEN}✓ PASS: Valid shebang found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Invalid or missing shebang${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 3: Bash syntax validation
test_bash_syntax() {
  echo -e "${CYAN}[TEST 3] Validating Bash syntax...${NC}"
  if bash -n "$FIREWALL_SCRIPT" 2>/dev/null; then
    echo -e "${GREEN}✓ PASS: Bash syntax is valid${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Bash syntax errors found:${NC}"
    bash -n "$FIREWALL_SCRIPT" 2>&1 | sed 's/^/  /'
    ((TESTS_FAILED++))
  fi
}

# Test 4: Required functions exist
test_required_functions() {
  echo -e "${CYAN}[TEST 4] Checking for required function definitions...${NC}"
  local required_funcs=("send_alert" "apply_base_rules" "apply_custom_rules" "start_watchdog")
  local missing=0
  
  for func in "${required_funcs[@]}"; do
    if grep -q "^${func}()" "$FIREWALL_SCRIPT"; then
      echo -e "${GREEN}✓ Found function: $func${NC}"
    else
      echo -e "${RED}✗ Missing function: $func${NC}"
      ((missing++))
    fi
  done
  
  if [ $missing -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: All required functions present${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: $missing required functions missing${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 5: Config file loading
test_config_loading() {
  echo -e "${CYAN}[TEST 5] Checking config file loading logic...${NC}"
  if grep -q 'source "\$CONFIG_FILE"' "$FIREWALL_SCRIPT" || grep -q '. "\$CONFIG_FILE"' "$FIREWALL_SCRIPT"; then
    echo -e "${GREEN}✓ PASS: Config file loading logic found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Config file loading logic not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 6: Root privilege check
test_root_check() {
  echo -e "${CYAN}[TEST 6] Checking for root privilege validation...${NC}"
  if grep -q 'EUID -ne 0' "$FIREWALL_SCRIPT"; then
    echo -e "${GREEN}✓ PASS: Root privilege check found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Root privilege check not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 7: iptables commands present
test_iptables_usage() {
  echo -e "${CYAN}[TEST 7] Checking for iptables command usage...${NC}"
  if grep -q 'iptables' "$FIREWALL_SCRIPT"; then
    local count=$(grep -c 'iptables' "$FIREWALL_SCRIPT")
    echo -e "${GREEN}✓ PASS: Found $count iptables references${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: No iptables commands found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 8: Watchdog startup logic
test_watchdog_logic() {
  echo -e "${CYAN}[TEST 8] Checking watchdog startup logic...${NC}"
  if grep -q 'nohup /tmp/firewall_watchdog.sh' "$FIREWALL_SCRIPT"; then
    echo -e "${GREEN}✓ PASS: Watchdog startup logic found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Watchdog startup logic not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 9: Webhook integration
test_webhook_integration() {
  echo -e "${CYAN}[TEST 9] Checking webhook/alert integration...${NC}"
  if grep -q 'curl.*WEBHOOK_URL' "$FIREWALL_SCRIPT"; then
    echo -e "${GREEN}✓ PASS: Webhook integration found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Webhook integration not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 10: Persistent ban list handling
test_banlist_handling() {
  echo -e "${CYAN}[TEST 10] Checking persistent ban list handling...${NC}"
  if grep -q 'BANLIST_FILE' "$FIREWALL_SCRIPT"; then
    echo -e "${GREEN}✓ PASS: Ban list file handling found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Ban list file handling not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# ============================================================
# Run all tests
# ============================================================
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   🔥 Firewall Script Test Suite${NC}"
echo -e "${CYAN}=================================================${NC}\n"

test_script_exists
test_shebang
test_bash_syntax
test_required_functions
test_config_loading
test_root_check
test_iptables_usage
test_watchdog_logic
test_webhook_integration
test_banlist_handling

# Summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${CYAN}Total: $((TESTS_PASSED + TESTS_FAILED))${NC}\n"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All firewall script tests passed!${NC}\n"
  exit 0
else
  echo -e "${RED}✗ Some tests failed. Please review the script.${NC}\n"
  exit 1
fi
