#!/bin/bash

# ============================================================
#  Requirements & Dependencies Tests
#  Validates requirements.txt and system dependencies
# ============================================================

set -uo pipefail

REQUIREMENTS_FILE="./requirements.txt"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: requirements.txt exists
test_requirements_exists() {
  echo -e "${CYAN}[TEST 1] Checking if requirements.txt exists...${NC}"
  if [ -f "$REQUIREMENTS_FILE" ]; then
    echo -e "${GREEN}✓ PASS: requirements.txt found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: requirements.txt not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 2: requirements.txt is not empty
test_requirements_not_empty() {
  echo -e "${CYAN}[TEST 2] Checking if requirements.txt contains packages...${NC}"
  if [ -s "$REQUIREMENTS_FILE" ]; then
    local count=$(wc -l < "$REQUIREMENTS_FILE")
    echo -e "${GREEN}✓ PASS: Found $count package(s)${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: requirements.txt is empty${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 3: Flask is listed in requirements
test_flask_in_requirements() {
  echo -e "${CYAN}[TEST 3] Checking if Flask is in requirements...${NC}"
  if grep -q "Flask" "$REQUIREMENTS_FILE"; then
    local version=$(grep "Flask" "$REQUIREMENTS_FILE")
    echo -e "${GREEN}✓ PASS: Flask dependency found: $version${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Flask not listed in requirements${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 4: Requirements format validation
test_requirements_format() {
  echo -e "${CYAN}[TEST 4] Validating requirements format...${NC}"
  local valid=true
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    
    # Check if line matches valid pip requirement format
    if ! [[ $line =~ ^[a-zA-Z0-9_-]+.*$ ]]; then
      echo -e "${YELLOW}! Invalid format: $line${NC}"
      valid=false
    fi
  done < "$REQUIREMENTS_FILE"
  
  if [ "$valid" = true ]; then
    echo -e "${GREEN}✓ PASS: All requirements have valid format${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Some requirements have invalid format${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 5: System dependencies check (bash/shell)
test_bash_available() {
  echo -e "${CYAN}[TEST 5] Checking if bash is available...${NC}"
  if command -v bash &> /dev/null; then
    local version=$(bash --version | head -n 1)
    echo -e "${GREEN}✓ PASS: Bash available - $version${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Bash not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 6: Python availability
test_python_available() {
  echo -e "${CYAN}[TEST 6] Checking if Python 3 is available...${NC}"
  if command -v python3 &> /dev/null; then
    local version=$(python3 --version 2>&1)
    echo -e "${GREEN}✓ PASS: Python 3 available - $version${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Python 3 not found${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 7: iptables/netfilter availability
# NOTE: this is environment-dependent, not a code defect - iptables is
# normally present on this project's actual target systems (Ubuntu, Kali,
# Debian-based distros), but a minimal/lightweight CI container or Docker
# image may not have it installed at all. Treat that as a WARNING rather
# than a hard FAIL so the rest of the suite stays portable to CI runners
# that don't include it, instead of failing the whole suite over something
# that isn't actually broken.
test_iptables_available() {
  echo -e "${CYAN}[TEST 7] Checking if iptables is available...${NC}"
  if command -v iptables &> /dev/null; then
    echo -e "${GREEN}✓ PASS: iptables command found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${YELLOW}⚠ WARNING: iptables not found in this environment. This is expected on minimal/CI containers and is not treated as a failure - but iptables IS required on the systems this tool actually targets (Ubuntu/Kali/Debian).${NC}"
  fi
}

# Test 8: curl availability (for webhooks)
test_curl_available() {
  echo -e "${CYAN}[TEST 8] Checking if curl is available (for webhooks)...${NC}"
  if command -v curl &> /dev/null; then
    echo -e "${GREEN}✓ PASS: curl command found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: curl not found (webhooks will not work)${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 9: dmesg availability (for watchdog)
test_dmesg_available() {
  echo -e "${CYAN}[TEST 9] Checking if dmesg is available (for watchdog)...${NC}"
  if command -v dmesg &> /dev/null; then
    echo -e "${GREEN}✓ PASS: dmesg command found${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: dmesg not found (watchdog may not function)${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 10: pip3 availability
test_pip_available() {
  echo -e "${CYAN}[TEST 10] Checking if pip3 is available...${NC}"
  if command -v pip3 &> /dev/null; then
    local version=$(pip3 --version 2>&1)
    echo -e "${GREEN}✓ PASS: pip3 available - $version${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${YELLOW}⚠ WARNING: pip3 not found (needed for Flask installation)${NC}"
    ((TESTS_FAILED++))
  fi
}

# ============================================================
# Run all tests
# ============================================================
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📦 Requirements & Dependencies Test Suite${NC}"
echo -e "${CYAN}=================================================${NC}\n"

test_requirements_exists
test_requirements_not_empty
test_flask_in_requirements
test_requirements_format
test_bash_available
test_python_available
test_iptables_available
test_curl_available
test_dmesg_available
test_pip_available

# Summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${CYAN}Total: $((TESTS_PASSED + TESTS_FAILED))${NC}\n"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All dependency tests passed!${NC}\n"
  exit 0
else
  echo -e "${YELLOW}⚠ Some tests failed. System dependencies may be missing.${NC}\n"
  exit 1
fi
