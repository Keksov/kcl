#!/bin/bash
# 001_Skeleton.sh - thashset P0 skeleton gate. Pins the ctor core: storage init
# (${inst}_items assoc), computed Count == ${#items[@]}, and a REDUCED storage
# torture proving the tdictionary k-prefix idioms survive on the exotic
# subscripts that broke naive implementations (the full 34-key matrix is
# already proven in tdictionary/tests/002; here a representative subset guards
# against drift: '' / ']' / '*' / newline / $()-looking / k-vs-kk / unicode).
# Membership + algebra + events arrive P1/P2/P3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TS_DIR="$SCRIPT_DIR/.."
source "$TS_DIR/thashset.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: THashSet skeleton (P0 ctor core)"

kt_test_start "storage init: items assoc exists, Count 0, on_notify empty"
THashSet.new S
ok=1
declare -p S_items >/dev/null 2>&1 || ok=0
S.Count
[[ $ok -eq 1 && "$RESULT" == "0" && "$(S.on_notify)" == "" ]] \
    && kt_test_pass "clean set" || kt_test_fail "ok=$ok count=$RESULT cb='$(S.on_notify)'"

kt_test_start "Count is computed from the storage (direct-inject probe)"
S_items["kalpha"]=1; S_items["kbeta"]=1
S.Count
[[ "$RESULT" == "2" ]] && kt_test_pass "counts set members" || kt_test_fail "got $RESULT"
S_items=()

kt_test_start "reduced storage torture: exotic elements coexist by k-prefix"
# inject the exotic subscripts directly (P1 Add lands the API); prove the
# k-prefix keeps them distinct and countable — no collisions, no empty subscript
declare -n it=S_items
it=()
for e in "" "]" "*" "a b" $'x\ny' '$(echo pwned)' "k" "kk" "café"; do
    it["k$e"]=1
done
S.Count; n=$RESULT
# k-vs-kk distinctness: "kk" and "kkk" (k + "kk") must be different subscripts
[[ "$n" == "9" && -n "${it[k]+x}" && -n "${it[kk]+x}" && -n "${it[kkk]+x}" ]] \
    && kt_test_pass "9 exotic keys distinct (incl. '' / k / kk)" || kt_test_fail "n=$n"
it=()

kt_test_start "empty subscript is never used ('' element -> subscript 'k')"
it["k"]=1                      # this is the '' element (k + '')
[[ -n "${it[k]+x}" && -z "${it[+x]+x}" ]] && kt_test_pass "'' -> [k], no empty subscript" \
    || kt_test_fail "wrong subscript"
it=()
unset -n it

kt_test_start "pending sentinels: P2/P3 members dispatch and mark RESULT"
S.UnionWith y
r1="$RESULT"
S.Notify v added
r2="$RESULT"
[[ "$r1" == "__ths_pending__:UnionWith" && "$r2" == "__ths_pending__:Notify" ]] \
    && kt_test_pass "sentinels via kk._return" || kt_test_fail "r1='$r1' r2='$r2'"

kt_test_start "delete tears the storage down"
S.delete
declare -p S_items >/dev/null 2>&1 && kt_test_fail "S_items survived" || kt_test_pass "storage gone"

kt_test_start "re-source is a clean no-op"
source "$TS_DIR/thashset.sh"
[[ $? -eq 0 ]] && kt_test_pass "second source rc 0" || kt_test_fail "rc=$?"

kt_test_start "two sets are independent (per-instance storage)"
THashSet.new A; THashSet.new B
A_items["konly"]=1
A.Count; a=$RESULT
B.Count; b=$RESULT
[[ "$a" == "1" && "$b" == "0" ]] && kt_test_pass "isolated" || kt_test_fail "a=$a b=$b"
A.delete; B.delete

kt_test_start "PATH='' : ctor/Count/teardown fork-free"
zf="$(
    PATH=''
    source "$TS_DIR/thashset.sh" 2>/dev/null
    THashSet.new Z
    Z_items["kx"]=1; Z_items["ky"]=1
    Z.Count >/dev/null; a="$RESULT"
    Z.delete
    printf '%s' "$a"
)"
[[ "$zf" == "2" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "001_Skeleton.sh completed"
