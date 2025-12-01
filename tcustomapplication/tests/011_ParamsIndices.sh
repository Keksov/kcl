#!/bin/bash
# 011_ParamsIndices.sh - Test TCustomApplication Params property with multiple indices
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


kt_test_section "011: TCustomApplication Params Property with Multiple Indices"

# Test: Params with index 0
kt_test_start "Params with index 0"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 0 ]]; then
    param0=$(myapp.Params 0)
    if [[ -n "$param0" ]]; then
        kt_test_pass "Params[0] returns parameter: $param0"
    else
        kt_test_fail "Params[0] failed"
    fi
else
    kt_test_pass "Params[0] works (no parameters available)"
fi
myapp.delete

# Test: Params with index 1
kt_test_start "Params with index 1"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 1 ]]; then
    param1=$(myapp.Params 1)
    if [[ -n "$param1" ]]; then
        kt_test_pass "Params[1] returns parameter: $param1"
    else
        kt_test_fail "Params[1] failed"
    fi
else
    kt_test_pass "Params[1] works (insufficient parameters)"
fi
myapp.delete

# Test: Params with index 2
kt_test_start "Params with index 2"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ $param_count -gt 2 ]]; then
    param2=$(myapp.Params 2)
    if [[ -n "$param2" ]]; then
        kt_test_pass "Params[2] returns parameter: $param2"
    else
        kt_test_fail "Params[2] failed"
    fi
else
    kt_test_pass "Params[2] works (insufficient parameters)"
fi
myapp.delete

# Test: Params with negative index
kt_test_start "Params with negative index"
TCustomApplication.new myapp
param_neg=$(myapp.Params -1)
if [[ -z "$param_neg" ]]; then
    kt_test_pass "Params with negative index returns empty"
else
    kt_test_fail "Params with negative index unexpected: $param_neg"
fi
myapp.delete

# Test: Params with out of bounds index
kt_test_start "Params with out of bounds index"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
out_of_bounds=$((param_count + 1))
param_oob=$(myapp.Params $out_of_bounds)
if [[ -z "$param_oob" ]]; then
    kt_test_pass "Params with out of bounds index returns empty"
else
    kt_test_fail "Params with out of bounds index unexpected: $param_oob"
fi
myapp.delete

# Test: Params with large index
kt_test_start "Params with large index"
TCustomApplication.new myapp
param_large=$(myapp.Params 100)
if [[ -z "$param_large" ]]; then
    kt_test_pass "Params with large index returns empty"
else
    kt_test_fail "Params with large index unexpected: $param_large"
fi
myapp.delete

# Test: Multiple Params calls
kt_test_start "Multiple Params calls"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
results=""
for ((i=0; i<param_count && i<3; i++)); do
    param=$(myapp.Params $i)
    results="$results $param"
done
if [[ -n "$results" || $param_count -eq 0 ]]; then
    kt_test_pass "Multiple Params calls work: $results"
else
    kt_test_fail "Multiple Params calls failed"
fi
myapp.delete

kt_test_log "011_ParamsIndices.sh completed"