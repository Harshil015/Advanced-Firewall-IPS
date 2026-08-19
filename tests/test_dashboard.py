#!/usr/bin/env python3

"""
Dashboard Module Tests
Tests the Flask dashboard for syntax, imports, and functionality
"""

import sys
import os
import subprocess
import importlib.util

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN = '\033[0;36m'
NC = '\033[0m'

TESTS_PASSED = 0
TESTS_FAILED = 0

def print_test(test_name, passed, message=""):
    global TESTS_PASSED, TESTS_FAILED
    if passed:
        print(f"{GREEN}✓ PASS: {test_name}{NC}")
        if message:
            print(f"  {message}")
        TESTS_PASSED += 1
    else:
        print(f"{RED}✗ FAIL: {test_name}{NC}")
        if message:
            print(f"  {message}")
        TESTS_FAILED += 1

# Test 1: Dashboard file exists
def test_dashboard_exists():
    print(f"{CYAN}[TEST 1] Checking if dashboard.py exists...{NC}")
    if os.path.isfile("./dashboard.py"):
        print_test("Dashboard file existence", True, "Found at ./dashboard.py")
    else:
        print_test("Dashboard file existence", False, "File not found at ./dashboard.py")

# Test 2: Python syntax validation
def test_python_syntax():
    print(f"{CYAN}[TEST 2] Validating Python syntax...{NC}")
    try:
        result = subprocess.run([sys.executable, "-m", "py_compile", "./dashboard.py"], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            print_test("Python syntax validation", True, "No syntax errors")
        else:
            print_test("Python syntax validation", False, result.stderr)
    except Exception as e:
        print_test("Python syntax validation", False, str(e))

# Test 3: Flask import availability
def test_flask_import():
    print(f"{CYAN}[TEST 3] Checking Flask import...{NC}")
    try:
        import flask
        print_test("Flask import", True, f"Flask version: {flask.__version__}")
    except ImportError as e:
        print_test("Flask import", False, f"Flask not installed: {e}")

# Test 4: Check required functions in dashboard
def test_required_functions():
    print(f"{CYAN}[TEST 4] Checking for required functions...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    required_funcs = ["dashboard()"]
    missing = []
    
    for func in required_funcs:
        if func not in content:
            missing.append(func)
    
    if not missing:
        print_test("Required functions", True, f"All functions found")
    else:
        print_test("Required functions", False, f"Missing: {', '.join(missing)}")

# Test 5: Check for Flask app initialization
def test_flask_app_init():
    print(f"{CYAN}[TEST 5] Checking Flask app initialization...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "Flask(__name__)" in content or "Flask(" in content:
        print_test("Flask app initialization", True, "Flask app properly initialized")
    else:
        print_test("Flask app initialization", False, "Flask app initialization not found")

# Test 6: Check for route definition
def test_route_definition():
    print(f"{CYAN}[TEST 6] Checking for route definition...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "@app.route" in content:
        print_test("Route definition", True, "Flask routes properly defined")
    else:
        print_test("Route definition", False, "No Flask routes found")

# Test 7: Check for iptables command usage
def test_iptables_command():
    print(f"{CYAN}[TEST 7] Checking for iptables integration...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "iptables" in content and "subprocess" in content:
        print_test("iptables integration", True, "Dashboard retrieves iptables rules")
    else:
        print_test("iptables integration", False, "iptables integration not found")

# Test 8: Check for banned IPs file handling
def test_banned_ips_handling():
    print(f"{CYAN}[TEST 8] Checking banned IPs file handling...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "BANLIST_FILE" in content or "banned" in content.lower():
        print_test("Banned IPs handling", True, "Ban list file handling implemented")
    else:
        print_test("Banned IPs handling", False, "Ban list file handling not found")

# Test 9: Check for HTML template
def test_html_template():
    print(f"{CYAN}[TEST 9] Checking for HTML template...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "html" in content.lower() or "<!DOCTYPE" in content:
        print_test("HTML template", True, "HTML template found")
    else:
        print_test("HTML template", False, "HTML template not found")

# Test 10: Check for main execution block
def test_main_block():
    print(f"{CYAN}[TEST 10] Checking for main execution block...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "if __name__" in content and "app.run" in content:
        print_test("Main execution block", True, "Proper main block with app.run()")
    else:
        print_test("Main execution block", False, "Main execution block not properly configured")

# Test 11: Check for error handling
def test_error_handling():
    print(f"{CYAN}[TEST 11] Checking for error handling...{NC}")
    with open("./dashboard.py", "r") as f:
        content = f.read()
    
    if "except" in content or "try" in content:
        print_test("Error handling", True, "Exception handling implemented")
    else:
        print_test("Error handling", False, "No exception handling found")

# ============================================================
# Behavioral tests (fixes C2)
# Everything above this point is textual: it greps dashboard.py's source
# for expected strings, but never actually imports the module, calls its
# route, or exercises its logic. These two tests actually DO that - the
# same category of gap the issues report flagged across the whole suite.
# ============================================================

def _load_dashboard_module():
    """Import dashboard.py as a real module (not just read as text) so we
    can call its actual functions and hit its actual Flask route."""
    spec = importlib.util.spec_from_file_location("dashboard_under_test", "./dashboard.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

# Test 12: A real HTTP request against the real Flask route, via Flask's
# own test client - not a grep for "@app.route" in the source text.
def test_dashboard_live_request():
    print(f"{CYAN}[TEST 12] Making a real request to the dashboard via Flask's test client...{NC}")
    try:
        module = _load_dashboard_module()
        client = module.app.test_client()
        response = client.get("/")
        ok = response.status_code == 200 and b"Firewall" in response.data
        print_test(
            "Live dashboard request",
            ok,
            f"GET / returned HTTP {response.status_code}, expected content present: {b'Firewall' in response.data}",
        )
    except Exception as e:
        print_test("Live dashboard request", False, f"{type(e).__name__}: {e}")

# Test 13: Actually CALL the port-collision guard (issue A3's fix) with a
# forced collision and confirm it refuses to start, rather than just
# grepping for the word "DASHBOARD_PORT" somewhere in the file.
def test_dashboard_port_collision_guard():
    print(f"{CYAN}[TEST 13] Checking the DASHBOARD_PORT/HONEYPORTS collision guard actually refuses to start...{NC}")
    try:
        module = _load_dashboard_module()

        original_port = module.DASHBOARD_PORT
        original_honeyports = module.HONEYPORTS
        try:
            # Force a collision and confirm check_port_collision() exits.
            module.DASHBOARD_PORT = 9999
            module.HONEYPORTS = ["2222", "8080", "9999"]
            try:
                module.check_port_collision()
                collision_caught = False
            except SystemExit:
                collision_caught = True

            # Also confirm it does NOT falsely refuse on a non-colliding config.
            module.DASHBOARD_PORT = 5050
            module.HONEYPORTS = ["2222", "8080", "9999"]
            try:
                module.check_port_collision()
                no_false_positive = True
            except SystemExit:
                no_false_positive = False
        finally:
            module.DASHBOARD_PORT = original_port
            module.HONEYPORTS = original_honeyports

        ok = collision_caught and no_false_positive
        print_test(
            "Dashboard port/honeypot collision guard",
            ok,
            f"refuses on collision: {collision_caught}, allows non-colliding config: {no_false_positive}",
        )
    except Exception as e:
        print_test("Dashboard port/honeypot collision guard", False, f"{type(e).__name__}: {e}")

# ============================================================
# Run all tests
# ============================================================
print(f"\n{CYAN}================================================={NC}")
print(f"{CYAN}   🐍 Dashboard Module Test Suite{NC}")
print(f"{CYAN}================================================={NC}\n")

test_dashboard_exists()
test_python_syntax()
test_flask_import()
test_required_functions()
test_flask_app_init()
test_route_definition()
test_iptables_command()
test_banned_ips_handling()
test_html_template()
test_main_block()
test_error_handling()
test_dashboard_live_request()
test_dashboard_port_collision_guard()

# Summary
print(f"\n{CYAN}================================================={NC}")
print(f"{CYAN}   📊 Test Summary{NC}")
print(f"{CYAN}================================================={NC}")
print(f"{GREEN}Passed: {TESTS_PASSED}{NC}")
print(f"{RED}Failed: {TESTS_FAILED}{NC}")
print(f"{CYAN}Total: {TESTS_PASSED + TESTS_FAILED}{NC}\n")

if TESTS_FAILED == 0:
    print(f"{GREEN}✓ All dashboard tests passed!{NC}\n")
    sys.exit(0)
else:
    print(f"{RED}✗ Some tests failed. Please review the dashboard.{NC}\n")
    sys.exit(1)
