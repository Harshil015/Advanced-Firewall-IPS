#!/bin/bash

# ============================================================
#  Configuration Module Tests
#  Tests the config.conf file loading and validation
# ============================================================

set -uo pipefail

CONFIG_FILE="./config.conf"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Config file exists
test_config_exists() {
  echo -e "${CYAN}[TEST 1] Checking if config file exists...${NC}"
  if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✓ PASS: Config file found at $CONFIG_FILE${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: Config file not found at $CONFIG_FILE${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 2: Config contains required variables
test_config_variables() {
  echo -e "${CYAN}[TEST 2] Checking for required configuration variables...${NC}"
  local required_vars=("HONEYPORTS" "PROTECTED_PORTS" "MAX_CONN" "BANLIST_FILE")
  local missing=0
  
  for var in "${required_vars[@]}"; do
    if grep -q "^${var}=" "$CONFIG_FILE"; then
      echo -e "${GREEN}✓ Found: $var${NC}"
    else
      echo -e "${RED}✗ Missing: $var${NC}"
      ((missing++))
    fi
  done
  
  if [ $missing -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: All required variables present${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: $missing required variables missing${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 3: HONEYPORTS format validation
test_honeyports_format() {
  echo -e "${CYAN}[TEST 3] Validating HONEYPORTS format (comma-separated numbers)...${NC}"
  source "$CONFIG_FILE"
  
  if [[ $HONEYPORTS =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo -e "${GREEN}✓ PASS: HONEYPORTS format is valid: $HONEYPORTS${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: HONEYPORTS format invalid: $HONEYPORTS${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 4: PROTECTED_PORTS format validation
test_protected_ports_format() {
  echo -e "${CYAN}[TEST 4] Validating PROTECTED_PORTS format (comma-separated numbers)...${NC}"
  source "$CONFIG_FILE"
  
  if [[ $PROTECTED_PORTS =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo -e "${GREEN}✓ PASS: PROTECTED_PORTS format is valid: $PROTECTED_PORTS${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: PROTECTED_PORTS format invalid: $PROTECTED_PORTS${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 5: MAX_CONN is a positive integer
test_max_conn_format() {
  echo -e "${CYAN}[TEST 5] Validating MAX_CONN is a positive integer...${NC}"
  source "$CONFIG_FILE"
  
  if [[ $MAX_CONN =~ ^[0-9]+$ ]] && [ "$MAX_CONN" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS: MAX_CONN is valid: $MAX_CONN${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: MAX_CONN format invalid: $MAX_CONN${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 6: BANLIST_FILE path is set
test_banlist_file_set() {
  echo -e "${CYAN}[TEST 6] Checking if BANLIST_FILE is configured...${NC}"
  source "$CONFIG_FILE"
  
  if [ -n "$BANLIST_FILE" ]; then
    echo -e "${GREEN}✓ PASS: BANLIST_FILE is set to: $BANLIST_FILE${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: BANLIST_FILE is not set${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 7: No duplicate ports in HONEYPORTS and PROTECTED_PORTS
test_no_port_conflicts() {
  echo -e "${CYAN}[TEST 7] Checking for port conflicts between HONEYPORTS and PROTECTED_PORTS...${NC}"
  source "$CONFIG_FILE"
  
  local hp_array=($( echo "$HONEYPORTS" | tr ',' '\n'))
  local pp_array=($( echo "$PROTECTED_PORTS" | tr ',' '\n'))
  local conflicts=0
  
  for hp in "${hp_array[@]}"; do
    for pp in "${pp_array[@]}"; do
      if [ "$hp" == "$pp" ]; then
        echo -e "${YELLOW}! Warning: Port $hp is in both HONEYPORTS and PROTECTED_PORTS${NC}"
        ((conflicts++))
      fi
    done
  done
  
  if [ $conflicts -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: No port conflicts detected${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: $conflicts port conflicts detected${NC}"
    ((TESTS_FAILED++))
  fi
}

# Test 8: DASHBOARD_PORT must not collide with HONEYPORTS (critical - this
# is the exact collision issue A3 was about: dashboard.py listens on
# DASHBOARD_PORT, and any HONEYPORTS hit gets banned automatically, so a
# collision means visiting your own dashboard bans you). Previously this
# couldn't be caught at all because the dashboard's port wasn't in
# config.conf; now that DASHBOARD_PORT lives here, this test actually
# covers it.
test_dashboard_port_conflict() {
  echo -e "${CYAN}[TEST 8] Checking DASHBOARD_PORT against HONEYPORTS...${NC}"
  source "$CONFIG_FILE"

  if [ -z "${DASHBOARD_PORT:-}" ]; then
    echo -e "${RED}✗ FAIL: DASHBOARD_PORT is not set in config.conf${NC}"
    ((TESTS_FAILED++))
    return
  fi

  local hp_array=($( echo "$HONEYPORTS" | tr ',' '\n'))
  local dashboard_conflict=0
  for hp in "${hp_array[@]}"; do
    if [ "$hp" == "$DASHBOARD_PORT" ]; then
      echo -e "${RED}! DASHBOARD_PORT ($DASHBOARD_PORT) is also a honeyport - visiting the dashboard would ban the viewer${NC}"
      dashboard_conflict=1
    fi
  done

  if [ $dashboard_conflict -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: DASHBOARD_PORT ($DASHBOARD_PORT) does not collide with HONEYPORTS${NC}"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗ FAIL: DASHBOARD_PORT collides with HONEYPORTS${NC}"
    ((TESTS_FAILED++))
  fi

  # A collision with PROTECTED_PORTS isn't dangerous (dashboard traffic
  # would just be rate-limited, not banned) but is worth a heads-up.
  local pp_array=($( echo "$PROTECTED_PORTS" | tr ',' '\n'))
  for pp in "${pp_array[@]}"; do
    if [ "$pp" == "$DASHBOARD_PORT" ]; then
      echo -e "${YELLOW}! Note: DASHBOARD_PORT ($DASHBOARD_PORT) is also in PROTECTED_PORTS - dashboard traffic will be rate-limited${NC}"
    fi
  done
}

# ============================================================
# Run all tests
# ============================================================
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📋 Configuration Module Test Suite${NC}"
echo -e "${CYAN}=================================================${NC}\n"

test_config_exists
test_config_variables
test_honeyports_format
test_protected_ports_format
test_max_conn_format
test_banlist_file_set
test_no_port_conflicts
test_dashboard_port_conflict

# Summary
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${CYAN}Total: $((TESTS_PASSED + TESTS_FAILED))${NC}\n"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All configuration tests passed!${NC}\n"
  exit 0
else
  echo -e "${RED}✗ Some tests failed. Please review the configuration.${NC}\n"
  exit 1
fi
