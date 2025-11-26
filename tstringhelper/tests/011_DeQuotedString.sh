#!/bin/bash
# DeQuotedString
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "DeQuotedString" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Remove quotes
kk_test_start "Dequote string"
result=$(string.deQuotedString "\"hello\"")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Dequote string"
else
    kk_test_fail "Dequote string (expected: 'hello', got: '$result')"
fi
