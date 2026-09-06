#!/bin/bash
# 002_MembershipCore.sh - thashset P1: the membership core. Pins: the
# Boolean-rc contract that is the LOUD difference from TDictionary (Add rc 0
# added / rc 1 dup SILENT; Remove rc 0 removed / rc 1 absent SILENT; Contains
# rc 0/1), Extract hit/miss (RESULT=item / '' — rc 0 both, S6), Clear, the
# ''-element (empty-subscript trap), exotic elements byte-exact through
# Add/Contains/ToArray, ForEach snapshot semantics, Assign copy + operand
# validation, and the hot-path gate (no callback → no dispatch). Events are
# threaded but dormant until P3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TS_DIR="$SCRIPT_DIR/.."
source "$TS_DIR/thashset.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: THashSet membership core (P1)"

sorted_of() {  # echo the sorted elements of set $1, space-joined
    local -n __a="$2"; __a=()
    "$1".ToArray __a
    IFS=$'\n' __a=($(printf '%s\n' "${__a[@]}" | LC_ALL=C sort)); unset IFS
}

kt_test_start "Boolean Add: new → rc 0, duplicate → rc 1 (SILENT, no mutation)"
THashSet.new S
S.Add alpha; r1=$?
S.Add beta
S.Add alpha 2>/dev/null; r2=$?
S.Count; n=$RESULT
[[ $r1 -eq 0 && $r2 -eq 1 && "$n" == "2" ]] && kt_test_pass "0 / 1 / count 2" \
    || kt_test_fail "r1=$r1 r2=$r2 n=$n"

kt_test_start "Contains: hit rc 0, miss rc 1"
S.Contains alpha; a=$?
S.Contains ghost; b=$?
[[ $a -eq 0 && $b -eq 1 ]] && kt_test_pass "0 / 1" || kt_test_fail "$a / $b"

kt_test_start "Boolean Remove: hit → rc 0, absent → rc 1 (SILENT)"
S.Remove alpha; r1=$?
S.Remove alpha 2>/dev/null; r2=$?
S.Count; n=$RESULT
[[ $r1 -eq 0 && $r2 -eq 1 && "$n" == "1" ]] && kt_test_pass "0 / 1 / count 1" \
    || kt_test_fail "r1=$r1 r2=$r2 n=$n"

kt_test_start "Extract: hit RESULT=item, miss RESULT='' (S6: rc 0 both, removed)"
S.Add gamma
S.Extract gamma; e1="$RESULT"; rc1=$?
S.Extract nope;  e2="$RESULT"; rc2=$?
S.Contains gamma; cg=$?
[[ "$e1" == "gamma" && $rc1 -eq 0 && "$e2" == "" && $rc2 -eq 0 && $cg -eq 1 ]] \
    && kt_test_pass "gamma/0 · ''/0 · removed" || kt_test_fail "e1=$e1 rc1=$rc1 e2='$e2' rc2=$rc2 cg=$cg"
S.delete

kt_test_start "'' is a valid element (empty-subscript trap), addable/removable"
THashSet.new E
E.Add ""; a=$?
E.Contains ""; c1=$?
E.Count; n1=$RESULT
E.Remove ""; E.Contains ""; c2=$?
[[ $a -eq 0 && $c1 -eq 0 && "$n1" == "1" && $c2 -eq 1 ]] \
    && kt_test_pass "add/contains/remove '' all correct" || kt_test_fail "a=$a c1=$c1 n1=$n1 c2=$c2"
E.delete

kt_test_start "exotic elements byte-exact through Add/Contains/ToArray"
THashSet.new X
for e in "a b" $'x\ny' '*.txt' '$(boom)' 'café' ']' 'k' 'kk'; do X.Add "$e"; done
X.Count; n=$RESULT
ok=1
for e in "a b" $'x\ny' '*.txt' '$(boom)' 'café' ']' 'k' 'kk'; do X.Contains "$e" || ok=0; done
T=(); X.ToArray T
[[ "$n" == "8" && $ok -eq 1 && "${#T[@]}" == "8" ]] \
    && kt_test_pass "8 exotic elements distinct + lossless" || kt_test_fail "n=$n ok=$ok len=${#T[@]}"
X.delete

# The hole that hid G2-01: only Add/Contains/ToArray were exercised on exotic
# elements, so 23/23 was green while `unset "${__inst__}_items[$pk]"` (DOUBLE
# quoted — the subscript is re-expanded) silently removed nothing for any item
# containing ] [ $ ' " \ or a backtick, AND executed $( ) / backtick content.
kt_test_start "Remove deletes exotic elements instead of silently keeping them [G2-01]"
THashSet.new R
declare -a exotic=( ']' '[' 'a]b' 'a[b' "it's" 'say "hi"' 'a\b' 'a$b' '${HOME}' 'a b' $'x\ny' '*' 'k' 'kk' '' )
for e in "${exotic[@]}"; do R.Add "$e"; done
R.Count; before=$RESULT
broken=""
for e in "${exotic[@]}"; do
    R.Remove "$e" || broken+="rc[$e] "
    R.Contains "$e" && broken+="still-present[$e] "
done
R.Count; after=$RESULT
[[ -z "$broken" && "$before" == "${#exotic[@]}" && "$after" == "0" ]] \
    && kt_test_pass "${#exotic[@]} exotic elements removed, count 0" \
    || kt_test_fail "before=$before after=$after $broken"
R.delete

kt_test_start "Extract deletes exotic elements and returns them verbatim [G2-01]"
THashSet.new E2
broken=""
for e in "${exotic[@]}"; do
    E2.Add "$e"
    E2.Extract "$e"
    [[ "$RESULT" == "$e" ]] || broken+="value[$e] "
    E2.Contains "$e" && broken+="still-present[$e] "
done
E2.Count; n=$RESULT
[[ -z "$broken" && "$n" == "0" ]] && kt_test_pass "extracted verbatim, set empty" \
    || kt_test_fail "n=$n $broken"
E2.delete

kt_test_start "Remove/Extract never EXECUTE the element [G2-01]"
canary="$(kt_fixture_tmpdir)/thashset_pwn"
rm -f "$canary"
THashSet.new I
I.Add "\$(touch '$canary')"
I.Add "\`touch '$canary'\`"
I.Remove "\$(touch '$canary')"
I.Extract "\`touch '$canary'\`" >/dev/null
I.Count; n=$RESULT
if [[ -e "$canary" ]]; then
    kt_test_fail "the element was executed: $canary exists"
    rm -f "$canary"
else
    [[ "$n" == "0" ]] && kt_test_pass "nothing executed, both removed" \
        || kt_test_fail "nothing executed but count=$n"
fi
I.delete

kt_test_start "ForEach visits every element once (snapshot semantics)"
THashSet.new F
F.Add 1; F.Add 2; F.Add 3
SEEN=(); cb() { SEEN+=("$1"); }
F.ForEach cb
IFS=$'\n' ss=($(printf '%s\n' "${SEEN[@]}" | sort)); unset IFS
[[ "${ss[*]}" == "1 2 3" ]] && kt_test_pass "1 2 3" || kt_test_fail "${SEEN[*]}"
F.delete

kt_test_start "ForEach snapshot: a mutating callback sees a stable iteration"
THashSet.new M
M.Add a; M.Add b; M.Add c
cnt=0; mut() { cnt=$((cnt+1)); M.Add "extra$cnt" 2>/dev/null; }   # add during iterate
M.ForEach mut
[[ $cnt -eq 3 ]] && kt_test_pass "visited exactly the 3 originals" || kt_test_fail "visited $cnt"
M.delete

kt_test_start "Clear empties the set"
THashSet.new C
C.Add x; C.Add y; C.Add z
C.Clear
C.Count; n=$RESULT
C.Contains x; cx=$?
[[ "$n" == "0" && $cx -eq 1 ]] && kt_test_pass "count 0, membership gone" || kt_test_fail "n=$n cx=$cx"
C.delete

kt_test_start "Assign: replaces contents with a copy; validates the operand"
THashSet.new SRC; SRC.Add p; SRC.Add q; SRC.Add r
THashSet.new DST; DST.Add old
DST.Assign SRC
DST.Count; n=$RESULT
DST.Contains p; cp=$?; DST.Contains old; co=$?
sorted_of DST DA
DST.Assign no_such_set 2>/dev/null; rc=$?
[[ "$n" == "3" && $cp -eq 0 && $co -eq 1 && "${DA[*]}" == "p q r" && $rc -eq 1 ]] \
    && kt_test_pass "3 copied, old gone, bad operand rc 1" \
    || kt_test_fail "n=$n cp=$cp co=$co arr='${DA[*]}' rc=$rc"
SRC.delete; DST.delete

kt_test_start "Assign is atomic: a rejected operand leaves the target untouched"
THashSet.new K; K.Add keep1; K.Add keep2
K.Assign not_a_set 2>/dev/null
K.Count; n=$RESULT
[[ "$n" == "2" ]] && kt_test_pass "target intact after bad Assign" || kt_test_fail "n=$n"
K.delete

kt_test_start "hot-path gate: no callback → ops work, nothing dispatched"
THashSet.new G
G.Add z; G.Extract z >/dev/null; G.Add w; G.Remove w
G.Count; n=$RESULT
[[ "$n" == "0" ]] && kt_test_pass "gate off, ops fine" || kt_test_fail "n=$n"
G.delete

kt_test_start "two sets are independent (per-instance storage)"
THashSet.new A; THashSet.new B
A.Add only-a; B.Add only-b
A.Contains only-b; ab=$?
B.Contains only-a; ba=$?
[[ $ab -eq 1 && $ba -eq 1 ]] && kt_test_pass "isolated" || kt_test_fail "ab=$ab ba=$ba"
A.delete; B.delete

kt_test_start "PATH='' : full membership lifecycle fork-free"
zf="$(
    PATH=''
    source "$TS_DIR/thashset.sh" 2>/dev/null
    THashSet.new Z
    Z.Add a; Z.Add b; Z.Add a
    Z.Contains a >/dev/null; c=$?
    Z.Remove a >/dev/null
    Z.Extract b >/dev/null; e="$RESULT"
    O=(); Z.ToArray O >/dev/null
    Z.Count >/dev/null; n="$RESULT"
    Z.delete
    printf '%s|%s|%s|%s' "$c" "$e" "${#O[@]}" "$n"
)"
[[ "$zf" == "0|b|0|0" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "002_MembershipCore.sh completed"
