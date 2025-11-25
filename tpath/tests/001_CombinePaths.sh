#!/bin/bash
# CombinePaths
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CombinePaths" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Basic path combination
kk_test_start "Combine two relative paths"
result=$(tpath.combine "path1" "path2" | xargs)
# Should combine with separator
expected="path1\\path2"
if [[ "$result" == "$expected" ]]; then
    kk_test_pass "Combine two relative paths"
else
    kk_test_fail "Combine two relative paths (expected: $expected, got: '$result')"
fi

# Test 2: Absolute path2 returns path2
kk_test_start "Combine with absolute path2"
result=$(tpath.combine "path1" "/absolute/path")
if [[ "$result" == "/absolute/path" ]]; then
    kk_test_pass "Combine with absolute path2"
else
    kk_test_fail "Combine with absolute path2 (expected: /absolute/path, got: '$result')"
fi

# Test 3: Empty path1
kk_test_start "Combine with empty path1"
result=$(tpath.combine "" "path2")
if [[ "$result" == "path2" ]]; then
    kk_test_pass "Combine with empty path1"
else
    kk_test_fail "Combine with empty path1 (expected: path2, got: '$result')"
fi

# Test 4: Empty path2
kk_test_start "Combine with empty path2"
result=$(tpath.combine "path1" "")
if [[ "$result" == "path1" ]]; then
    kk_test_pass "Combine with empty path2"
else
    kk_test_fail "Combine with empty path2 (expected: path1, got: '$result')"
fi

# Test 5: Path1 with trailing separator
kk_test_start "Combine path1 with trailing separator"
result=$(tpath.combine "path1/" "path2" | xargs)
expected="path1\\path2"
if [[ "$result" == "$expected" ]]; then
    kk_test_pass "Combine path1 with trailing separator"
else
    kk_test_fail "Combine path1 with trailing separator (expected: $expected, got: '$result')"
fi

# Test 6: Complex path combination
kk_test_start "Combine complex paths"
result=$(tpath.combine "/home/user" "documents/file.txt" | xargs)
expected="/home/user\\documents/file.txt"
if [[ "$result" == "$expected" ]]; then
    kk_test_pass "Combine complex paths"
else
    kk_test_fail "Combine complex paths (expected: $expected, got: '$result')"
fi

# Test 7: Performance test - combine many paths
kk_test_start "Performance test for path combination"
start_time=$(date +%s%N)
for i in {1..100}; do
    result=$(tpath.combine "path$i" "file$i.txt")
done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))  # milliseconds
if [[ $duration -lt 20000 ]]; then  # Less than 20 seconds
    kk_test_pass "Performance test for path combination (${duration}ms)"
else
    kk_test_fail "Performance test for path combination (too slow: ${duration}ms)"
fi
