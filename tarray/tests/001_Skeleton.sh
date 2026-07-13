#!/bin/bash
# 001_Skeleton.sh - tarray P0.2 skeleton gate. Proves the SCAFFOLDING, not
# behavior: (1) source green, (2) `build TArray` green, (3) all 13 static-proc
# members dispatch, (4) the silent RESULT contract (direct call sets RESULT,
# prints nothing; $() does not leak globals), (5) source+dispatch fork-free
# (PATH=''). Real behavior arrives P1 (sort), P2 (search/min/max), P3 (copy/
# reverse/concat). Every case has a TEST_COVERAGE_NOTES.md row.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TARRAY_DIR="$SCRIPT_DIR/.."
source "$TARRAY_DIR/tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TArray skeleton — source/build/dispatch/contract (P0.2)"

# --- source + build succeeded; all 13 members defined
kt_test_start "source + build: all 13 members defined"
missing=""
for m in sort binarySearch indexOf firstIndexOf lastIndexOf contains min max \
         copy reverse reverseInPlace concat compact; do
    declare -F "TArray.$m" >/dev/null || missing="$missing $m"
done
[[ -z "$missing" ]] && kt_test_pass "all 13 TArray.* defined" || kt_test_fail "missing:$missing"

# --- all 13 members are implemented as of P3 (no stub sentinels remain)
kt_test_start "representative members real (sort/min/reverse behave)"
a=(3 1 2); TArray.sort a -n
TArray.min a -n; mn=$RESULT
b=(); TArray.reverse a b
if [[ "${a[*]}" == "1 2 3" && "$mn" == "1" && "${b[*]}" == "3 2 1" ]]; then
    kt_test_pass "sort/min/reverse all real"
else
    kt_test_fail "sort=${a[*]} min=$mn reverse=${b[*]}"
fi

# --- direct call sets RESULT and prints nothing (real min, a value-returner)
kt_test_start "direct call: RESULT set, silent stdout"
a=(5 2 8); RESULT="preset"; tmpout="$(mktemp)"
TArray.min a -n >"$tmpout" 2>/dev/null
if [[ "$RESULT" == "2" && ! -s "$tmpout" ]]; then
    kt_test_pass "RESULT=2 (min), no stdout"
else
    kt_test_fail "RESULT='$RESULT' stdout=[$(cat "$tmpout")]"
fi
rm -f "$tmpout"

# --- $() runs in a subshell -> globals do not leak back
kt_test_start "under \$(): silent + globals do not leak to parent"
RESULT="__sentinel__"
cap="$(TArray.binarySearch)"
[[ -z "$cap" && "$RESULT" == "__sentinel__" ]] && kt_test_pass "\$() empty, RESULT unchanged" \
    || kt_test_fail "cap='$cap' RESULT='$RESULT'"

# --- RESULT_CANDIDATE / RESULT_COMPARE shaped by the stub
kt_test_start "RESULT_CANDIDATE / RESULT_COMPARE present"
TArray.binarySearch
[[ "$RESULT_CANDIDATE" == "-1" && "$RESULT_COMPARE" == "0" ]] && kt_test_pass "candidate=-1 compare=0" \
    || kt_test_fail "candidate='$RESULT_CANDIDATE' compare='$RESULT_COMPARE'"

# --- zero-fork: source + real sort under PATH=''
kt_test_start "PATH='' : source + real sort need no external commands"
zf="$(
    PATH=''
    source "$TARRAY_DIR/tarray.sh" 2>/dev/null
    z=(3 1 2); TArray.sort z
    printf '%s' "${z[*]}"
)"
[[ "$zf" == "1 2 3" ]] && kt_test_pass "sort under PATH='' -> $zf" \
    || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "001_Skeleton.sh completed"
