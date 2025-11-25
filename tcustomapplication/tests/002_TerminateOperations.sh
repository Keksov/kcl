#!/bin/bash
# 002_TerminateOperations.sh - Test TCustomApplication Terminate method
# Auto-generated for kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


kk_test_section "002: TCustomApplication Terminate Operations"

# Test: Terminate without exit code
kk_test_start "Terminate without exit code"
TCustomApplication.new myapp
terminated_before=$(myapp.terminated)
myapp.Terminate
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kk_test_pass "Terminate sets terminated to true"
else
    kk_test_fail "Terminate failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: Terminate with exit code
kk_test_start "Terminate with exit code"
TCustomApplication.new myapp
myapp.Terminate 42
terminated=$(myapp.terminated)
if [[ "$terminated" == "true" ]]; then
    kk_test_pass "Terminate with exit code sets terminated to true"
else
    kk_test_fail "Terminate with exit code failed: terminated=$terminated"
fi
myapp.delete

# Test: Multiple terminate calls
kk_test_start "Multiple terminate calls"
TCustomApplication.new myapp
myapp.Terminate
terminated1=$(myapp.terminated)
myapp.Terminate 1
terminated2=$(myapp.terminated)
if [[ "$terminated1" == "true" && "$terminated2" == "true" ]]; then
    kk_test_pass "Multiple terminate calls work correctly"
else
    kk_test_fail "Multiple terminate calls failed: terminated1=$terminated1, terminated2=$terminated2"
fi
myapp.delete

# Test: Terminate on initialized application
kk_test_start "Terminate on initialized application"
TCustomApplication.new myapp
myapp.Initialize
terminated_before=$(myapp.terminated)
myapp.Terminate
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kk_test_pass "Terminate works on initialized application"
else
    kk_test_fail "Terminate on initialized app failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: Terminate with zero exit code
kk_test_start "Terminate with zero exit code"
TCustomApplication.new myapp
myapp.Terminate 0
terminated=$(myapp.terminated)
if [[ "$terminated" == "true" ]]; then
    kk_test_pass "Terminate with zero exit code works"
else
    kk_test_fail "Terminate with zero exit code failed: terminated=$terminated"
fi
myapp.delete

# Test: Terminate with negative exit code
kk_test_start "Terminate with negative exit code"
TCustomApplication.new myapp
myapp.Terminate -1
terminated=$(myapp.terminated)
if [[ "$terminated" == "true" ]]; then
    kk_test_pass "Terminate with negative exit code works"
else
    kk_test_fail "Terminate with negative exit code failed: terminated=$terminated"
fi
myapp.delete

kk_test_log "002_TerminateOperations.sh completed"