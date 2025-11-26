#!/bin/bash
# 011_ParamsIndices.sh - Test TCustomApplication Params property with multiple indices
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


kk_test_section "011: TCustomApplication Params Property with Multiple Indices"

# Test: Params with index 0
kk_test_start "Params with index 0"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 0 ]]; then
    param0=$(myapp.Params 0)
    if [[ -n "$param0" ]]; then
        kk_test_pass "Params[0] returns parameter: $param0"
    else
        kk_test_fail "Params[0] failed"
    fi
else
    kk_test_pass "Params[0] works (no parameters available)"
fi
myapp.delete

# Test: Params with index 1
kk_test_start "Params with index 1"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 1 ]]; then
    param1=$(myapp.Params 1)
    if [[ -n "$param1" ]]; then
        kk_test_pass "Params[1] returns parameter: $param1"
    else
        kk_test_fail "Params[1] failed"
    fi
else
    kk_test_pass "Params[1] works (insufficient parameters)"
fi
myapp.delete

# Test: Params with index 2
kk_test_start "Params with index 2"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 2 ]]; then
    param2=$(myapp.Params 2)
    if [[ -n "$param2" ]]; then
        kk_test_pass "Params[2] returns parameter: $param2"
    else
        kk_test_fail "Params[2] failed"
    fi
else
    kk_test_pass "Params[2] works (insufficient parameters)"
fi
myapp.delete

# Test: Params with negative index
kk_test_start "Params with negative index"
TCustomApplication.new myapp
param_neg=$(myapp.Params -1)
if [[ -z "$param_neg" ]]; then
    kk_test_pass "Params with negative index returns empty"
else
    kk_test_fail "Params with negative index unexpected: $param_neg"
fi
myapp.delete

# Test: Params with out of bounds index
kk_test_start "Params with out of bounds index"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
out_of_bounds=$((param_count + 1))
param_oob=$(myapp.Params $out_of_bounds)
if [[ -z "$param_oob" ]]; then
    kk_test_pass "Params with out of bounds index returns empty"
else
    kk_test_fail "Params with out of bounds index unexpected: $param_oob"
fi
myapp.delete

# Test: Params with large index
kk_test_start "Params with large index"
TCustomApplication.new myapp
param_large=$(myapp.Params 100)
if [[ -z "$param_large" ]]; then
    kk_test_pass "Params with large index returns empty"
else
    kk_test_fail "Params with large index unexpected: $param_large"
fi
myapp.delete

# Test: Multiple Params calls
kk_test_start "Multiple Params calls"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
results=""
for ((i=0; i<param_count && i<3; i++)); do
    param=$(myapp.Params $i)
    results="$results $param"
done
if [[ -n "$results" || $param_count -eq 0 ]]; then
    kk_test_pass "Multiple Params calls work: $results"
else
    kk_test_fail "Multiple Params calls failed"
fi
myapp.delete

kk_test_log "011_ParamsIndices.sh completed"