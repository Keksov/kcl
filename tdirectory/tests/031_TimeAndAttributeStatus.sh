#!/bin/bash
# Time and attribute status consistency

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TimeAndAttributeStatus" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

kt_test_start "TDirectory time getters return normalized timestamps"
test_dir="$_KT_TMPDIR/time_format"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.getLastWriteTime "$test_dir")
if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    kt_test_pass "TDirectory time getters return normalized timestamps"
else
    kt_test_fail "TDirectory time getter returned invalid timestamp: $result"
fi

kt_test_start "TDirectory time getters fail for missing directories"
if tdirectory.getCreationTime "$_KT_TMPDIR/no-such-directory" >/dev/null 2>&1; then
    kt_test_fail "TDirectory time getters fail for missing directories"
else
    kt_test_pass "TDirectory time getters fail for missing directories"
fi

kt_test_start "TDirectory time setters fail for missing directories"
if tdirectory.setLastWriteTime "$_KT_TMPDIR/no-such-directory" "2024-01-01 12:00:00" >/dev/null 2>&1; then
    kt_test_fail "TDirectory time setters fail for missing directories"
else
    kt_test_pass "TDirectory time setters fail for missing directories"
fi

kt_test_start "TDirectory setAttributes fails for missing directories"
if tdirectory.setAttributes "$_KT_TMPDIR/no-such-directory" "faReadOnly" >/dev/null 2>&1; then
    kt_test_fail "TDirectory setAttributes fails for missing directories"
else
    kt_test_pass "TDirectory setAttributes fails for missing directories"
fi