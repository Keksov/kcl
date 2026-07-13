#!/bin/bash
# 007_CopyReverseConcat.sh - TArray.copy / reverse / reverseInPlace / concat /
# compact: the source-pinned semantics S4 (reverse via temp, in-place safe),
# S6 (copy same-array error + strict bounds, dst NOT auto-grown), S7 (concat
# skips empties). FPC Test_Reverse parity is in 006. Basis: FPC impl
# (:1301-1369) + array-mutation semantics.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: TArray copy / reverse / concat / compact"

# --- reverse: into target, source untouched (S4) ---
kt_test_start "reverse src->dst, source untouched"
a=(1 2 3 4 5); b=(x)
TArray.reverse a b
[[ "${b[*]}" == "5 4 3 2 1" && "${a[*]}" == "1 2 3 4 5" ]] && kt_test_pass "dst reversed, src intact" \
    || kt_test_fail "b=${b[*]} a=${a[*]}"

kt_test_start "reverse in-place (src==dst) safe via temp (S4)"
c=(1 2 3 4 5); TArray.reverse c c
[[ "${c[*]}" == "5 4 3 2 1" ]] && kt_test_pass "in-place ok" || kt_test_fail "got ${c[*]}"

kt_test_start "reverseInPlace + empty + single"
d=(a b c); TArray.reverseInPlace d
e=(); TArray.reverse e e; er=$?
s=(z); TArray.reverse s s
[[ "${d[*]}" == "c b a" && $er -eq 0 && "${#e[@]}" == "0" && "${s[*]}" == "z" ]] \
    && kt_test_pass "rip=c b a, empty ok, single z" || kt_test_fail "d=${d[*]} e=${#e[@]} s=${s[*]}"

kt_test_start "reverse: missing name -> rc 2"
TArray.reverse a; [[ $? -eq 2 ]] && kt_test_pass "rc 2" || kt_test_fail "rc=$?"

# --- copy: count form + indexed form ---
kt_test_start "copy count form: src[0..]->dst[0..]"
src=(a b c d e); dst=(_ _ _ _ _)
TArray.copy src dst 3
[[ "${dst[*]}" == "a b c _ _" ]] && kt_test_pass "${dst[*]}" || kt_test_fail "got ${dst[*]}"

kt_test_start "copy indexed form: srcIdx dstIdx count"
src=(a b c d e); dst=(0 1 2 3 4)
TArray.copy src dst 1 2 2       # src[1..2] -> dst[2..3]
[[ "${dst[*]}" == "0 1 b c 4" ]] && kt_test_pass "${dst[*]}" || kt_test_fail "got ${dst[*]}"

# --- copy S6: same-array error, strict bounds, no auto-grow ---
kt_test_start "copy same array -> rc 2, unchanged (S6 SErrSameArrays)"
x=(1 2 3); TArray.copy x x 2; rc=$?
[[ $rc -eq 2 && "${x[*]}" == "1 2 3" ]] && kt_test_pass "rejected, unchanged" || kt_test_fail "rc=$rc x=${x[*]}"

kt_test_start "copy dst too small -> rc 2, NOT auto-grown (S6)"
src=(a b c); dst=(_)
TArray.copy src dst 3; rc=$?
[[ $rc -eq 2 && "${#dst[@]}" == "1" ]] && kt_test_pass "rejected, dst still size 1" || kt_test_fail "rc=$rc n=${#dst[@]}"

kt_test_start "copy count>src or negative -> rc 2"
src=(a b); dst=(_ _ _ _ _)
TArray.copy src dst 5; r1=$?
TArray.copy src dst -1; r2=$?
[[ $r1 -eq 2 && $r2 -eq 2 ]] && kt_test_pass "both rc 2" || kt_test_fail "$r1 $r2"

kt_test_start "copy count 0 -> rc 0, no change"
src=(a b c); dst=(x y z)
TArray.copy src dst 0; rc=$?
[[ $rc -eq 0 && "${dst[*]}" == "x y z" ]] && kt_test_pass "no-op" || kt_test_fail "rc=$rc dst=${dst[*]}"

# --- concat: multiple, empties skipped (S7), dst==src, all-empty ---
kt_test_start "concat: src1 ++ src2 ++ src3"
p=(1 2); q=(3 4 5); r=(6)
TArray.concat out p q r
[[ "${out[*]}" == "1 2 3 4 5 6" && "${#out[@]}" == "6" ]] && kt_test_pass "${out[*]}" || kt_test_fail "got ${out[*]}"

kt_test_start "concat: empty sources contribute nothing (S7)"
p=(1); em=(); q=(2)
TArray.concat out p em q
[[ "${out[*]}" == "1 2" ]] && kt_test_pass "${out[*]}" || kt_test_fail "got ${out[*]}"

kt_test_start "concat: dst may be a source (temp-built)"
p=(1 2); q=(3)
TArray.concat p p q
[[ "${p[*]}" == "1 2 3" ]] && kt_test_pass "concat into src ok" || kt_test_fail "got ${p[*]}"

kt_test_start "concat: all-empty -> empty; missing dst -> rc 2"
e1=(); e2=(); TArray.concat out e1 e2; n=${#out[@]}
TArray.concat ""; rc=$?
[[ "$n" == "0" && $rc -eq 2 ]] && kt_test_pass "empty result, rc2 no-name" || kt_test_fail "n=$n rc=$rc"

# --- compact: sparse -> dense ---
kt_test_start "compact: sparse array re-indexed dense, order kept"
declare -a sp=([0]=a [3]=b [7]=c [20]=d)
TArray.compact sp
[[ "${sp[*]}" == "a b c d" && "${!sp[*]}" == "0 1 2 3" ]] && kt_test_pass "dense a b c d" \
    || kt_test_fail "vals=${sp[*]} idx=${!sp[*]}"

# --- torture: exotic elements survive reverse/concat losslessly ---
kt_test_start "torture: reverse/concat lossless (newline/glob/quotes)"
t=($'x\ny' '*' 'a"q"')
TArray.reverse t rt
p=($'n\nl'); q=('*g'); TArray.concat cc p q
rok=0; [[ "${rt[0]}" == 'a"q"' && "${rt[2]}" == $'x\ny' ]] && rok=1
cok=0; [[ "${cc[0]}" == $'n\nl' && "${cc[1]}" == '*g' ]] && cok=1
(( rok && cok )) && kt_test_pass "lossless" || kt_test_fail "rok=$rok cok=$cok"

# --- zero-fork ---
kt_test_start "PATH='' : copy/reverse/concat/compact need no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tarray.sh" 2>/dev/null
    a=(1 2 3); TArray.reverse a a
    s=(x y); d=(_ _); TArray.copy s d 2
    p=(1); q=(2); TArray.concat cc p q
    declare -a sp=([2]=z [5]=w); TArray.compact sp
    printf '%s|%s|%s|%s' "${a[*]}" "${d[*]}" "${cc[*]}" "${sp[*]}"
)"
[[ "$zf" == "3 2 1|x y|1 2|z w" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "007_CopyReverseConcat.sh completed"
