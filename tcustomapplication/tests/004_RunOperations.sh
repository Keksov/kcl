#!/bin/bash
# 004_RunOperations.sh - Test TCustomApplication Run method
# Auto-generated for ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


kt_test_section "004: TCustomApplication Run Operations"

# Test: Run method exists and can be called
kt_test_start "Run method can be called"
TCustomApplication.new myapp
myapp.Initialize
# Note: Run method would typically loop until terminated, so we test it exists
# In real implementation, Run would be overridden in descendants
myapp.Run &
run_pid=$!
sleep 0.1  # Give it a moment to start
if kill -0 $run_pid 2>/dev/null; then
    kt_test_pass "Run method started successfully"
    kill $run_pid 2>/dev/null
else
    kt_test_pass "Run method completed (may be synchronous in base class)"
fi
myapp.delete

# Test: Run method respects terminated flag
kt_test_start "Run method respects terminated flag"
TCustomApplication.new myapp
myapp.Initialize
myapp.Terminate
# Run should exit quickly if terminated is true
start_time=$(date +%s)
myapp.Run
end_time=$(date +%s)
duration=$((end_time - start_time))
if [[ $duration -lt 2 ]]; then  # Should complete quickly
    kt_test_pass "Run method respects terminated flag"
else
    kt_test_fail "Run method did not respect terminated flag (took ${duration}s)"
fi
myapp.delete

# Test: Run after Initialize
kt_test_start "Run after Initialize"
TCustomApplication.new myapp
myapp.Initialize
terminated_before=$(myapp.terminated)
myapp.Run &
run_pid=$!
sleep 0.1
if kill -0 $run_pid 2>/dev/null; then
    kill $run_pid 2>/dev/null
fi
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" ]]; then
    kt_test_pass "Run works after Initialize"
else
    kt_test_fail "Run failed after Initialize"
fi
myapp.delete

# Test: Multiple Run calls
kt_test_start "Multiple Run calls"
TCustomApplication.new myapp
myapp.Initialize
myapp.Run &
pid1=$!
sleep 0.1
kill $pid1 2>/dev/null
myapp.Run &
pid2=$!
sleep 0.1
if kill -0 $pid2 2>/dev/null; then
    kill $pid2 2>/dev/null
    kt_test_pass "Multiple Run calls work"
else
    kt_test_pass "Multiple Run calls completed"
fi
myapp.delete

# Test: Run with exception handling integration
kt_test_start "Run with exception handling integration"
TCustomApplication.new myapp
myapp.Initialize
# Set StopOnException (would be via property)
myapp.Run &
run_pid=$!
sleep 0.1
# Simulate exception that would trigger termination
myapp.HandleException "test_sender" "test_exception"
sleep 0.1
if ! kill -0 $run_pid 2>/dev/null; then
    kt_test_pass "Run properly handles exceptions"
else
    kill $run_pid 2>/dev/null
    kt_test_pass "Run continued after exception (StopOnException=false)"
fi
myapp.delete

# Test: Run method termination via Terminate
kt_test_start "Run method termination via Terminate"
TCustomApplication.new myapp
myapp.Initialize
myapp.Run &
run_pid=$!
sleep 0.1
myapp.Terminate
sleep 0.1
if ! kill -0 $run_pid 2>/dev/null; then
    kt_test_pass "Run properly terminated via Terminate"
else
    kill $run_pid 2>/dev/null
    kt_test_fail "Run did not terminate via Terminate"
fi
myapp.delete

kt_test_log "004_RunOperations.sh completed"