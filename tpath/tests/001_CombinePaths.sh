#!/bin/bash
# CombinePaths
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CombinePaths" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Basic path combination
kt_test_start "Combine two relative paths"
result=$(tpath.combine "path1" "path2")
# D5: DirectorySeparatorChar is `/` on every platform, so the joint is `/`.
expected="path1/path2"
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Combine two relative paths"
else
    kt_test_fail "Combine two relative paths (expected: $expected, got: '$result')"
fi

# Test 2: Absolute path2 returns path2
kt_test_start "Combine with absolute path2"
result=$(tpath.combine "path1" "/absolute/path")
if [[ "$result" == "/absolute/path" ]]; then
    kt_test_pass "Combine with absolute path2"
else
    kt_test_fail "Combine with absolute path2 (expected: /absolute/path, got: '$result')"
fi

# Test 3: Empty path1
kt_test_start "Combine with empty path1"
result=$(tpath.combine "" "path2")
if [[ "$result" == "path2" ]]; then
    kt_test_pass "Combine with empty path1"
else
    kt_test_fail "Combine with empty path1 (expected: path2, got: '$result')"
fi

# Test 4: Empty path2
kt_test_start "Combine with empty path2"
result=$(tpath.combine "path1" "")
if [[ "$result" == "path1" ]]; then
    kt_test_pass "Combine with empty path2"
else
    kt_test_fail "Combine with empty path2 (expected: path1, got: '$result')"
fi

# Test 5: Path1 with trailing separator
kt_test_start "Combine path1 with trailing separator"
result=$(tpath.combine "path1/" "path2")
expected="path1/path2"
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Combine path1 with trailing separator"
else
    kt_test_fail "Combine path1 with trailing separator (expected: $expected, got: '$result')"
fi

# Test 6: Complex path combination
kt_test_start "Combine complex paths"
result=$(tpath.combine "/home/user" "documents/file.txt")
expected="/home/user/documents/file.txt"
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Combine complex paths"
else
    kt_test_fail "Combine complex paths (expected: $expected, got: '$result')"
fi

# Test 7: the direct call is the cheap one (decision D3 / finding G6-16).
# A wall-clock threshold of 20 s could not fail on any machine; the RELATIVE
# gate can: 100 direct calls must beat 100 $( ) captures of the same member,
# because $( ) forks a whole shell each time (0.65 ms vs 23 ms per 200 in the
# review's measurement).
ms() { printf '%s' $(( ${EPOCHREALTIME/./} / 1000 )); }

kt_test_start "100 direct combines are faster than 100 \$( ) combines [G6-16, D3]"
t0=$(ms)
for i in {1..100}; do
    tpath.combine "path$i" "file$i.txt"
done
t1=$(ms)
for i in {1..100}; do
    result=$(tpath.combine "path$i" "file$i.txt")
done
t2=$(ms)
direct=$(( t1 - t0 ))
forked=$(( t2 - t1 ))
if (( direct < forked )); then
    kt_test_pass "direct ${direct}ms < \$( ) ${forked}ms"
else
    kt_test_fail "direct ${direct}ms is not faster than \$( ) ${forked}ms"
fi

kt_test_start "the last direct combine left its value in RESULT [D3]"
tpath.combine "path7" "file7.txt"
if [[ "$RESULT" == "path7/file7.txt" ]]; then
    kt_test_pass "RESULT=$RESULT"
else
    kt_test_fail "RESULT='$RESULT', expected 'path7/file7.txt'"
fi
