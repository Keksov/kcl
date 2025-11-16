#!/bin/bash
# 012_get_attributes.sh - Test TPath.getAttributes method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

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
test_start "GetAttributes for regular file"
result=$(tpath.getAttributes "$test_file")
if [[ -n "$result" ]] && [[ "$result" != *"faDirectory"* ]]; then
    test_pass "GetAttributes for regular file"
else
    test_fail "GetAttributes for regular file (expected non-empty, non-directory, got: '$result')"
fi

# Test 2: Directory attributes
test_start "GetAttributes for directory"
result=$(tpath.getAttributes "$test_dir")
if [[ "$result" == *"faDirectory"* ]]; then
    test_pass "GetAttributes for directory"
else
    test_fail "GetAttributes for directory (expected to contain faDirectory, got: '$result')"
fi

# Test 3: Read-only file
test_start "GetAttributes for read-only file"
result=$(tpath.getAttributes "$readonly_file")
if [[ "$result" == *"faReadOnly"* ]]; then
    test_pass "GetAttributes for read-only file"
else
    test_fail "GetAttributes for read-only file (expected to contain faReadOnly, got: '$result')"
fi

# Test 4: Hidden file
test_start "GetAttributes for hidden file"
result=$(tpath.getAttributes "$hidden_file")
if [[ "$result" == *"faHidden"* ]]; then
    test_pass "GetAttributes for hidden file"
else
    test_fail "GetAttributes for hidden file (expected to contain faHidden, got: '$result')"
fi

# Test 5: Non-existent file
test_start "GetAttributes for non-existent file"
result=$(tpath.getAttributes "$temp_dir/non_existent_file.txt" 2>/dev/null) || result=""
if [[ -z "$result" ]]; then
    test_pass "GetAttributes for non-existent file"
else
    test_fail "GetAttributes for non-existent file (expected empty, got: '$result')"
fi

# Test 6: Empty path
test_start "GetAttributes with empty path"
result=$(tpath.getAttributes "" 2>/dev/null) || result=""
if [[ -z "$result" ]]; then
    test_pass "GetAttributes with empty path"
else
    test_fail "GetAttributes with empty path (expected empty, got: '$result')"
fi

# Cleanup
rm -f "$test_file" "$readonly_file" "$hidden_file"
rmdir "$test_dir"
