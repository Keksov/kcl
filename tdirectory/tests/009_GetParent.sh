#!/bin/bash
# 009_GetParent.sh - Test TDirectory.GetParent method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get parent from absolute path
test_start "GetParent - parent of absolute path"
result=$(tdirectory.getParent "/home/user/documents")
if [[ "$result" == "/home/user" ]]; then
    test_pass "GetParent - parent of absolute path"
else
    test_fail "GetParent - parent of absolute path (expected: /home/user, got: '$result')"
fi

# Test 2: Get parent from relative path
test_start "GetParent - parent of relative path"
result=$(tdirectory.getParent "folder/subfolder")
if [[ "$result" == "folder" ]]; then
    test_pass "GetParent - parent of relative path"
else
    test_fail "GetParent - parent of relative path (expected: folder, got: '$result')"
fi

# Test 3: Get parent from single level
test_start "GetParent - parent of single level absolute"
result=$(tdirectory.getParent "/folder")
if [[ "$result" == "" || "$result" == "/" ]]; then
    test_pass "GetParent - parent of single level absolute"
else
    test_fail "GetParent - parent of single level absolute (expected: empty or /, got: '$result')"
fi

# Test 4: Get parent from root
test_start "GetParent - parent of root"
result=$(tdirectory.getParent "/")
if [[ "$result" == "/" ]] || [[ "$result" == "" ]]; then
    test_pass "GetParent - parent of root"
else
    test_fail "GetParent - parent of root (expected: / or empty, got: '$result')"
fi

# Test 5: Get parent from path with trailing slash
test_start "GetParent - parent of path with trailing slash"
result=$(tdirectory.getParent "/home/user/")
if [[ "$result" == "/home" ]]; then
    test_pass "GetParent - parent of path with trailing slash"
else
    test_fail "GetParent - parent of path with trailing slash (expected: /home, got: '$result')"
fi

# Test 6: Get parent from deep path
test_start "GetParent - parent of deep path"
result=$(tdirectory.getParent "/var/log/application/debug")
if [[ "$result" == "/var/log/application" ]]; then
    test_pass "GetParent - parent of deep path"
else
    test_fail "GetParent - parent of deep path (expected: /var/log/application, got: '$result')"
fi

# Test 7: Get parent from empty path
test_start "GetParent - parent of empty path"
result=$(tdirectory.getParent "")
if [[ "$result" == "" ]]; then
    test_pass "GetParent - parent of empty path"
else
    test_fail "GetParent - parent of empty path (expected: empty, got: '$result')"
fi

# Test 8: Get parent from Windows drive path
test_start "GetParent - parent of Windows drive path"
result=$(tdirectory.getParent "C:/Users/Documents")
if [[ "$result" == "C:/Users" ]] || [[ "$result" == "C:\\Users" ]]; then
    test_pass "GetParent - parent of Windows drive path"
else
    test_fail "GetParent - parent of Windows drive path (expected: C:/Users, got: '$result')"
fi

# Test 9: Get parent with relative parent notation
test_start "GetParent - parent of path with dots"
result=$(tdirectory.getParent ".")
if [[ -n "$result" ]]; then
    test_pass "GetParent - parent of path with dots"
else
    test_fail "GetParent - parent of path with dots (expected: non-empty, got: '$result')"
fi

# Test 10: Sequential parent extraction
test_start "GetParent - sequential parent extraction"
path="/home/user/documents/file.txt"
parent1=$(tdirectory.getParent "$path")
parent2=$(tdirectory.getParent "$parent1")
parent3=$(tdirectory.getParent "$parent2")
if [[ "$parent1" == "/home/user/documents" && "$parent2" == "/home/user" && "$parent3" == "/home" ]]; then
    test_pass "GetParent - sequential parent extraction"
else
    test_fail "GetParent - sequential parent extraction (p1:'$parent1' p2:'$parent2' p3:'$parent3')"
fi

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
