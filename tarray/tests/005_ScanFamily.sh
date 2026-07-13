#!/bin/bash
# 005_ScanFamily.sh - TArray.indexOf / firstIndexOf / lastIndexOf / contains /
# min / max: first-vs-last on duplicates (S3), the empty/default contract (S5),
# the three comparator modes, and torture. FPC-oracle values live in
# 006_FpcParity.sh. Basis: FPC impl (:1371 IndexOf==FirstIndexOf, :1342
# Contains==IndexOf<>-1) + linear-scan oracle.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: TArray scan family (indexOf/first/last/contains/min/max)"

dup=(1 3 5 9 7 9 13 9 20)   # 9 appears at indices 3, 5, 7

# --- indexOf == firstIndexOf (S3); lastIndexOf = last ---
kt_test_start "indexOf == firstIndexOf == first occurrence (3)"
TArray.indexOf dup 9 -n; a=$RESULT
TArray.firstIndexOf dup 9 -n; b=$RESULT
[[ "$a" == "3" && "$b" == "3" ]] && kt_test_pass "both 3" || kt_test_fail "indexOf=$a first=$b"

kt_test_start "lastIndexOf = last occurrence (7)"
TArray.lastIndexOf dup 9 -n
[[ "$RESULT" == "7" ]] && kt_test_pass "last @7" || kt_test_fail "got $RESULT"

kt_test_start "indexOf miss -> -1, rc 1"
TArray.indexOf dup 42 -n; rc=$?
[[ "$RESULT" == "-1" && $rc -eq 1 ]] && kt_test_pass "-1 / rc1" || kt_test_fail "R=$RESULT rc=$rc"

kt_test_start "single-occurrence: first == last"
TArray.firstIndexOf dup 13 -n; f=$RESULT
TArray.lastIndexOf dup 13 -n;  l=$RESULT
[[ "$f" == "6" && "$l" == "6" ]] && kt_test_pass "both @6" || kt_test_fail "first=$f last=$l"

# --- contains ---
kt_test_start "contains: present / absent / empty"
TArray.contains dup 9 -n; p=$?
TArray.contains dup 8 -n; q=$?
e=(); TArray.contains e 9 -n; z=$?
[[ $p -eq 0 && $q -eq 1 && $z -eq 1 ]] && kt_test_pass "0/1/1" || kt_test_fail "$p/$q/$z"

# --- min / max: value + default-on-empty (S5) ---
kt_test_start "min / max value (numeric)"
n=(37 -5 99 0 12)
TArray.min n -n -1; mn=$RESULT
TArray.max n -n -1; mx=$RESULT
[[ "$mn" == "-5" && "$mx" == "99" ]] && kt_test_pass "min -5 max 99" || kt_test_fail "min=$mn max=$mx"

kt_test_start "min / max on empty -> default, rc 1"
e=(); TArray.min e -n 777; r1=$?; d1=$RESULT
TArray.max e -n 777; r2=$?; d2=$RESULT
[[ "$d1" == "777" && $r1 -eq 1 && "$d2" == "777" && $r2 -eq 1 ]] && kt_test_pass "default 777 / rc1" \
    || kt_test_fail "min=$d1/$r1 max=$d2/$r2"

kt_test_start "min / max preserve original strings (007 not 7)"
b=(100 007 5 020)
TArray.min b -n; mn=$RESULT   # value 5
TArray.max b -n; mx=$RESULT   # value 100
[[ "$mn" == "5" && "$mx" == "100" ]] && kt_test_pass "min 5 max 100 (strings)" || kt_test_fail "min=$mn max=$mx"

kt_test_start "min / max single-element"
one=(42); TArray.min one -n; a=$RESULT; TArray.max one -n; b=$RESULT
[[ "$a" == "42" && "$b" == "42" ]] && kt_test_pass "both 42" || kt_test_fail "$a $b"

# --- byte mode (default) ---
kt_test_start "byte-mode min/max/indexOf (upper<lower)"
s=(banana Apple cherry Banana)
TArray.min s; mn=$RESULT      # Apple (A=65 lowest)
TArray.max s; mx=$RESULT      # cherry (c lowest-case highest here)
TArray.indexOf s cherry; ix=$RESULT
[[ "$mn" == "Apple" && "$mx" == "cherry" && "$ix" == "2" ]] && kt_test_pass "Apple/cherry/@2" \
    || kt_test_fail "min=$mn max=$mx idx=$ix"

# --- cmpFn mode ---
kt_test_start "cmpFn-mode min/max (by length)"
bylen(){ (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
L=(ccc a dddd bb)
TArray.min L bylen; mn=$RESULT     # shortest: a
TArray.max L bylen; mx=$RESULT     # longest: dddd
[[ "$mn" == "a" && "$mx" == "dddd" ]] && kt_test_pass "a / dddd" || kt_test_fail "min=$mn max=$mx"

kt_test_start "min tie keeps FIRST occurrence"
# two equal-length shortest -> first in input order
t=(bb aa cc dd)     # all length 2; byfirst? use bylen -> all equal -> min = first (bb)
TArray.min t bylen
[[ "$RESULT" == "bb" ]] && kt_test_pass "first tie (bb)" || kt_test_fail "got $RESULT"

# --- torture: newline / unicode elements ---
kt_test_start "torture: indexOf element with newline"
u=(a $'x\ny' café)
TArray.indexOf u $'x\ny'; i1=$RESULT
TArray.indexOf u café;     i2=$RESULT
[[ "$i1" == "1" && "$i2" == "2" ]] && kt_test_pass "newline@1 unicode@2" || kt_test_fail "$i1 $i2"

# --- zero-fork ---
kt_test_start "PATH='' : scan family needs no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tarray.sh" 2>/dev/null
    q=(3 1 2 1)
    TArray.indexOf q 1 -n;     a=$RESULT
    TArray.lastIndexOf q 1 -n; b=$RESULT
    TArray.min q -n;           c=$RESULT
    TArray.max q -n;           d=$RESULT
    TArray.contains q 2 -n;    e=$?
    printf '%s|%s|%s|%s|%s' "$a" "$b" "$c" "$d" "$e"
)"
[[ "$zf" == "1|3|1|3|0" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "005_ScanFamily.sh completed"
