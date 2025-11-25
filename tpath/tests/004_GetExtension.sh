#!/bin/bash
# GetExtension
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetExtension" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Simple extension
kk_test_start "Get simple extension"
result=$(tpath.getExtension "file.txt")
if [[ "$result" == ".txt" ]]; then
    kk_test_pass "Get simple extension"
else
    kk_test_fail "Get simple extension (expected: .txt, got: '$result')"
fi

# Test 2: No extension
kk_test_start "Get extension from file without extension"
result=$(tpath.getExtension "file")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get extension from file without extension"
else
    kk_test_fail "Get extension from file without extension (expected: empty, got: '$result')"
fi

# Test 3: Multiple dots
kk_test_start "Get extension from file with multiple dots"
result=$(tpath.getExtension "file.tar.gz")
if [[ "$result" == ".gz" ]]; then
    kk_test_pass "Get extension from file with multiple dots"
else
    kk_test_fail "Get extension from file with multiple dots (expected: .gz, got: '$result')"
fi

# Test 4: Path with extension
kk_test_start "Get extension from path"
result=$(tpath.getExtension "/home/user/document.pdf")
if [[ "$result" == ".pdf" ]]; then
    kk_test_pass "Get extension from path"
else
    kk_test_fail "Get extension from path (expected: .pdf, got: '$result')"
fi

# Test 5: Hidden file with extension
kk_test_start "Get extension from hidden file"
result=$(tpath.getExtension ".bashrc")
if [[ "$result" == ".bashrc" ]]; then
    kk_test_pass "Get extension from hidden file"
else
    kk_test_fail "Get extension from hidden file (expected: .bashrc, got: '$result')"
fi

# Test 6: Empty path
kk_test_start "Get extension from empty path"
result=$(tpath.getExtension "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get extension from empty path"
else
    kk_test_fail "Get extension from empty path (expected: empty, got: '$result')"
fi

# Test 7: Directory with dot in name
kk_test_start "Get extension from directory with dot"
result=$(tpath.getExtension "/path/folder.name/file.txt")
if [[ "$result" == ".txt" ]]; then
    kk_test_pass "Get extension from directory with dot"
else
    kk_test_fail "Get extension from directory with dot (expected: .txt, got: '$result')"
fi
