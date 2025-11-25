#!/bin/bash
# 015_Performance_Test.sh - Test Performance Test
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tlist module
TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kk_test_section "015: Performance Test"

# Create TList instance
TList.new testlist

kk_test_start "Create list"
if [[ -n "$(testlist.count)" ]]; then
    kk_test_pass "TList created successfully"
else
    kk_test_fail "Failed to create TList"
fi

# Cleanup
testlist.delete

kk_test_log "015_Performance_Test.sh completed"
