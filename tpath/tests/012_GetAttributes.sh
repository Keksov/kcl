#!/bin/bash
# GetAttributes
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetAttributes" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Create temporary test files
temp_dir=$(tpath.getTempPath)
test_file="$temp_dir/test_file.txt"
test_dir="$temp_dir/test_dir"
readonly_file="$temp_dir/readonly_file.txt"
hidden_file="$temp_dir/.hidden_file.txt"

# Setup test files
echo "test content" > "$test_file"
mkdir -p "$test_dir"
rm -f "$readonly_file"
echo "readonly content" > "$readonly_file"
chmod 444 "$readonly_file"
echo "hidden content" > "$hidden_file"

# Test 1: Regular file attributes
kt_test_start "GetAttributes for regular file"
result=$(tpath.getAttributes "$test_file")
if [[ -n "$result" ]] && [[ "$result" != *"faDirectory"* ]]; then
    kt_test_pass "GetAttributes for regular file"
else
    kt_test_fail "GetAttributes for regular file (expected non-empty, non-directory, got: '$result')"
fi

# Test 2: Directory attributes
kt_test_start "GetAttributes for directory"
result=$(tpath.getAttributes "$test_dir")
if [[ "$result" == *"faDirectory"* ]]; then
    kt_test_pass "GetAttributes for directory"
else
    kt_test_fail "GetAttributes for directory (expected to contain faDirectory, got: '$result')"
fi

# Test 3: Read-only file
kt_test_start "GetAttributes for read-only file"
result=$(tpath.getAttributes "$readonly_file")
if [[ "$result" == *"faReadOnly"* ]]; then
    kt_test_pass "GetAttributes for read-only file"
else
    kt_test_fail "GetAttributes for read-only file (expected to contain faReadOnly, got: '$result')"
fi

# Test 4: Hidden file
kt_test_start "GetAttributes for hidden file"
result=$(tpath.getAttributes "$hidden_file")
if [[ "$result" == *"faHidden"* ]]; then
    kt_test_pass "GetAttributes for hidden file"
else
    kt_test_fail "GetAttributes for hidden file (expected to contain faHidden, got: '$result')"
fi

# Test 5: Non-existent file
kt_test_start "GetAttributes for non-existent file"
result=$(tpath.getAttributes "$temp_dir/non_existent_file.txt" 2>/dev/null) || result=""
if [[ -z "$result" ]]; then
    kt_test_pass "GetAttributes for non-existent file"
else
    kt_test_fail "GetAttributes for non-existent file (expected empty, got: '$result')"
fi

# Test 6: Empty path
kt_test_start "GetAttributes with empty path"
result=$(tpath.getAttributes "" 2>/dev/null) || result=""
if [[ -z "$result" ]]; then
    kt_test_pass "GetAttributes with empty path"
else
    kt_test_fail "GetAttributes with empty path (expected empty, got: '$result')"
fi

# Test 7: Permission denied directory
kt_test_start "GetAttributes for permission denied path"
denied_dir="$temp_dir/denied"
mkdir -p "$denied_dir"
chmod 000 "$denied_dir"
result=$(tpath.getAttributes "$denied_dir" 2>/dev/null) || result=""
chmod 755 "$denied_dir"  # Restore permissions for cleanup
if [[ -n "$result" ]]; then
    kt_test_pass "GetAttributes for permission denied path"
else
    kt_test_fail "GetAttributes for permission denied path (expected non-empty, got empty)"
fi

# Test 8: Null bytes in path
kt_test_start "GetAttributes with null bytes in path"
null_path="test$(printf '\0')file.txt"
result=$(tpath.getAttributes "$null_path" 2>/dev/null) || result=""
if [[ -z "$result" ]]; then
    kt_test_pass "GetAttributes with null bytes in path"
else
    kt_test_fail "GetAttributes with null bytes in path (expected empty, got: '$result')"
fi

# Cleanup
rm -f "$test_file" "$readonly_file" "$hidden_file"
rmdir "$test_dir" "$denied_dir"
