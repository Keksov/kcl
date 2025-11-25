#!/bin/bash
# ChangeExtension
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "ChangeExtension" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Change extension with dot
kk_test_start "Change extension with dot"
result=$(tpath.changeExtension "file.txt" ".md")
if [[ "$result" == "file.md" ]]; then
    kk_test_pass "Change extension with dot"
else
    kk_test_fail "Change extension with dot (expected: file.md, got: '$result')"
fi

# Test 2: Change extension without dot
kk_test_start "Change extension without dot"
result=$(tpath.changeExtension "file.txt" "md")
if [[ "$result" == "file.md" ]]; then
    kk_test_pass "Change extension without dot"
else
    kk_test_fail "Change extension without dot (expected: file.md, got: '$result')"
fi

# Test 3: Remove extension (empty extension)
kk_test_start "Remove extension with empty string"
result=$(tpath.changeExtension "file.txt" "")
if [[ "$result" == "file" ]]; then
    kk_test_pass "Remove extension with empty string"
else
    kk_test_fail "Remove extension (expected: file, got: '$result')"
fi

# Test 4: File with path
kk_test_start "Change extension with path"
result=$(tpath.changeExtension "/path/to/file.txt" ".md")
if [[ "$result" == "/path/to/file.md" ]]; then
    kk_test_pass "Change extension with path"
else
    kk_test_fail "Change extension with path (expected: /path/to/file.md, got: '$result')"
fi

# Test 5: File without extension
kk_test_start "Add extension to file without extension"
result=$(tpath.changeExtension "file" ".txt")
if [[ "$result" == "file.txt" ]]; then
    kk_test_pass "Add extension to file without extension"
else
    kk_test_fail "Add extension to file without extension (expected: file.txt, got: '$result')"
fi

# Test 6: File with multiple dots
kk_test_start "Change extension in file with multiple dots"
result=$(tpath.changeExtension "file.tar.gz" ".zip")
if [[ "$result" == "file.tar.zip" ]]; then
    kk_test_pass "Change extension in file with multiple dots"
else
    kk_test_fail "Change extension in file with multiple dots (expected: file.tar.zip, got: '$result')"
fi

# Test 7: Empty path
kk_test_start "Change extension with empty path"
result=$(tpath.changeExtension "" ".txt")
if [[ "$result" == "" ]]; then
    kk_test_pass "Change extension with empty path"
else
    kk_test_fail "Change extension with empty path (expected: empty, got: '$result')"
fi
