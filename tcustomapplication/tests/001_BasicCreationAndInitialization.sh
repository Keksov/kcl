#!/bin/bash
# 001_BasicCreationAndInitialization.sh - Test TCustomApplication creation, initialization and destruction
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


kt_test_section "001: TCustomApplication Basic Creation and Initialization"

# Test: Create TCustomApplication instance
kt_test_start "Create TCustomApplication instance"
TCustomApplication.new myapp
if [[ -n "$(myapp.Terminated)" ]]; then
    kt_test_pass "TCustomApplication instance created successfully"
else
    kt_test_fail "Failed to create TCustomApplication instance"
fi

# Test: Check initial terminated property
kt_test_start "Check initial terminated property is false"
terminated=$(myapp.Terminated)
if [[ "$terminated" == "false" ]]; then
    kt_test_pass "Initial terminated is false"
else
    kt_test_fail "Initial terminated is $terminated, expected false"
fi

# Test: Check exeName property
kt_test_start "Check exeName property is set"
exe_name=$(myapp.ExeName)
if [[ -n "$exe_name" ]]; then
    kt_test_pass "exeName is set to: $exe_name"
else
    kt_test_fail "exeName is not set"
fi

# Test: Check title property
kt_test_start "Check initial title property"
title=$(myapp.Title)
if [[ -n "$title" ]]; then
    kt_test_pass "Initial title is: $title"
else
    kt_test_fail "Initial title is not set"
fi

# Test: Call Initialize method
kt_test_start "Call Initialize method"
myapp.Initialize
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "Initialize method called successfully"
else
    kt_test_fail "Initialize method failed"
fi

# Test: Verify terminated is still false after Initialize
kt_test_start "Verify terminated remains false after Initialize"
terminated=$(myapp.Terminated)
if [[ "$terminated" == "false" ]]; then
    kt_test_pass "Terminated remains false after Initialize"
else
    kt_test_fail "Terminated changed to $terminated after Initialize"
fi

# Test: Destroy the instance
kt_test_start "Destroy TCustomApplication instance"
myapp.delete
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "TCustomApplication instance destroyed successfully"
else
    kt_test_fail "Failed to destroy TCustomApplication instance"
fi

# Test: Create multiple TCustomApplication instances
kt_test_start "Create multiple TCustomApplication instances"
TCustomApplication.new app1
TCustomApplication.new app2
TCustomApplication.new app3
terminated1=$(app1.Terminated 2>/dev/null)
terminated2=$(app2.Terminated 2>/dev/null)
terminated3=$(app3.Terminated 2>/dev/null)
if [[ -n "$terminated1" && -n "$terminated2" && -n "$terminated3" ]]; then
    kt_test_pass "Multiple TCustomApplication instances created successfully"
else
    kt_test_fail "Failed to create multiple TCustomApplication instances"
fi

# Test: Verify instances are independent
kt_test_start "Verify instances are independent"
app1.property Title = "App1"
app2.property Title = "App2"
title1=$(app1.Title)
title2=$(app2.Title)
if [[ "$title1" == "App1" && "$title2" == "App2" ]]; then
    kt_test_pass "Instances are independent"
else
    kt_test_fail "Instances are not independent: app1.title=$title1, app2.title=$title2"
fi

# Destroy them
app1.delete
app2.delete
app3.delete

kt_test_log "001_BasicCreationAndInitialization.sh completed"