#!/bin/bash
# GetParent
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetParent" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Get parent from absolute path
kt_test_start "GetParent - parent of absolute path"
result=$(tdirectory.getParent "/home/user/documents")
if [[ "$result" == "/home/user" ]]; then
    kt_test_pass "GetParent - parent of absolute path"
else
    kt_test_fail "GetParent - parent of absolute path (expected: /home/user, got: '$result')"
fi

# Test 2: Get parent from relative path
kt_test_start "GetParent - parent of relative path"
result=$(tdirectory.getParent "folder/subfolder")
if [[ "$result" == "folder" ]]; then
    kt_test_pass "GetParent - parent of relative path"
else
    kt_test_fail "GetParent - parent of relative path (expected: folder, got: '$result')"
fi

# Test 3: Get parent from single level
kt_test_start "GetParent - parent of single level absolute"
result=$(tdirectory.getParent "/folder")
if [[ "$result" == "" || "$result" == "/" ]]; then
    kt_test_pass "GetParent - parent of single level absolute"
else
    kt_test_fail "GetParent - parent of single level absolute (expected: empty or /, got: '$result')"
fi

# Test 4: Get parent from root
kt_test_start "GetParent - parent of root"
result=$(tdirectory.getParent "/")
if [[ "$result" == "/" ]] || [[ "$result" == "" ]]; then
    kt_test_pass "GetParent - parent of root"
else
    kt_test_fail "GetParent - parent of root (expected: / or empty, got: '$result')"
fi

# Test 5: Get parent from path with trailing slash
kt_test_start "GetParent - parent of path with trailing slash"
result=$(tdirectory.getParent "/home/user/")
if [[ "$result" == "/home" ]]; then
    kt_test_pass "GetParent - parent of path with trailing slash"
else
    kt_test_fail "GetParent - parent of path with trailing slash (expected: /home, got: '$result')"
fi

# Test 6: Get parent from deep path
kt_test_start "GetParent - parent of deep path"
result=$(tdirectory.getParent "/var/log/application/debug")
if [[ "$result" == "/var/log/application" ]]; then
    kt_test_pass "GetParent - parent of deep path"
else
    kt_test_fail "GetParent - parent of deep path (expected: /var/log/application, got: '$result')"
fi

# Test 7: Get parent from empty path
kt_test_start "GetParent - parent of empty path"
result=$(tdirectory.getParent "")
if [[ "$result" == "" ]]; then
    kt_test_pass "GetParent - parent of empty path"
else
    kt_test_fail "GetParent - parent of empty path (expected: empty, got: '$result')"
fi

# Test 8: Get parent from Windows drive path
kt_test_start "GetParent - parent of Windows drive path"
result=$(tdirectory.getParent "C:/Users/Documents")
if [[ "$result" == "C:/Users" ]] || [[ "$result" == "C:\\Users" ]]; then
    kt_test_pass "GetParent - parent of Windows drive path"
else
    kt_test_fail "GetParent - parent of Windows drive path (expected: C:/Users, got: '$result')"
fi

# Test 9: Get parent with relative parent notation
kt_test_start "GetParent - parent of path with dots"
result=$(tdirectory.getParent ".")
if [[ -n "$result" ]]; then
    kt_test_pass "GetParent - parent of path with dots"
else
    kt_test_fail "GetParent - parent of path with dots (expected: non-empty, got: '$result')"
fi

# Test 10: Sequential parent extraction
kt_test_start "GetParent - sequential parent extraction"
path="/home/user/documents/file.txt"
parent1=$(tdirectory.getParent "$path")
parent2=$(tdirectory.getParent "$parent1")
parent3=$(tdirectory.getParent "$parent2")
if [[ "$parent1" == "/home/user/documents" && "$parent2" == "/home/user" && "$parent3" == "/home" ]]; then
    kt_test_pass "GetParent - sequential parent extraction"
else
    kt_test_fail "GetParent - sequential parent extraction (p1:'$parent1' p2:'$parent2' p3:'$parent3')"
fi


