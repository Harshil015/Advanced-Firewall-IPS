#!/bin/bash

# ============================================================
#  Master Test Runner
#  Executes all test suites and generates comprehensive report
# ============================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TEST_DIR="./tests"
REPORT_FILE="./TEST_REPORT.md"
TOTAL_PASSED=0
TOTAL_FAILED=0

# Initialize report
echo "# Advanced Firewall IPS - Test Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Generated:** $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   🧪 Running All Test Suites${NC}"
echo -e "${CYAN}=================================================${NC}\n"

# Test 1: Configuration Tests
echo -e "${CYAN}[1/5] Running Configuration Tests...${NC}"
echo "" >> "$REPORT_FILE"
echo "## 1. Configuration Module Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

if bash "$TEST_DIR/test_config.sh" 2>&1 | tee -a "$REPORT_FILE"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Test 2: Firewall Script Tests
echo -e "${CYAN}[2/5] Running Firewall Script Tests...${NC}"
echo "" >> "$REPORT_FILE"
echo "## 2. Firewall Script Syntax & Logic Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

if bash "$TEST_DIR/test_firewall_syntax.sh" 2>&1 | tee -a "$REPORT_FILE"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Test 3: Requirements Tests
echo -e "${CYAN}[3/5] Running Requirements & Dependencies Tests...${NC}"
echo "" >> "$REPORT_FILE"
echo "## 3. Requirements & Dependencies Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

if bash "$TEST_DIR/test_requirements.sh" 2>&1 | tee -a "$REPORT_FILE"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Test 4: Dashboard Tests
echo -e "${CYAN}[4/5] Running Dashboard Module Tests...${NC}"
echo "" >> "$REPORT_FILE"
echo "## 4. Dashboard Module (Python) Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

if python3 "$TEST_DIR/test_dashboard.py" 2>&1 | tee -a "$REPORT_FILE"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Test 5: nftables Tests
echo -e "${CYAN}[5/5] Running nftables Rules Tests...${NC}"
echo "" >> "$REPORT_FILE"
echo "## 5. nftables Rules File Tests" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"

if bash "$TEST_DIR/test_nftables.sh" 2>&1 | tee -a "$REPORT_FILE"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Generate Summary
echo "" >> "$REPORT_FILE"
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Metric | Result |" >> "$REPORT_FILE"
echo "|---|---|" >> "$REPORT_FILE"
echo "| Test Suites Passed | $TOTAL_PASSED/5 |" >> "$REPORT_FILE"
echo "| Test Suites Failed | $TOTAL_FAILED/5 |" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ $TOTAL_FAILED -eq 0 ]; then
  echo "${GREEN}✅ Status: ALL TESTS PASSED${NC}" | tee -a "$REPORT_FILE"
else
  echo "${RED}❌ Status: SOME TESTS FAILED${NC}" | tee -a "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Full report saved to:** $REPORT_FILE" >> "$REPORT_FILE"

echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}   📊 Overall Test Summary${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Test Suites Passed: $TOTAL_PASSED/5${NC}"
echo -e "${RED}Test Suites Failed: $TOTAL_FAILED/5${NC}"
echo -e "\n${CYAN}Report saved to: $REPORT_FILE${NC}\n"

if [ $TOTAL_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All test suites completed successfully!${NC}\n"
  exit 0
else
  echo -e "${RED}❌ Some test suites failed. Review the report for details.${NC}\n"
  exit 1
fi
