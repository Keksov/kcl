#!/bin/bash
# 003_OwnershipTorture.sh - the ownership matrix across every removal path
# (owning AND non-owning), plus the hostile cases: duplicate handles, mixed
# live/plain-string/dead elements, owns toggled mid-life, invalid indices
# freeing nothing, Extract-then-destroy, FindInstanceOf arg edges, zero-fork.
# Basis: contnrs.pp Notify/lnDeleted semantics + the _free guard contract.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TOL_DIR="$SCRIPT_DIR/.."
source "$TOL_DIR/tobjectlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: TObjectList ownership torture"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }

# --- Delete: owning frees exactly the victim; non-owning frees nothing ---
kt_test_start "Delete: owning frees victim only; non-owning frees nothing"
TList.new a1; TList.new a2; TObjectList.new L
L.Add a1 >/dev/null; L.Add a2 >/dev/null
L.Delete 0
own_ok=$([[ "$(alive a1 && echo y || echo n)$(alive a2 && echo y || echo n)" == "ny" ]] && echo ok)
L.delete
TList.new a3; TObjectList.new N false
N.Add a3 >/dev/null; N.Delete 0
non_ok=$(alive a3 && echo ok)
N.delete; a3.delete
[[ "$own_ok" == "ok" && "$non_ok" == "ok" ]] && kt_test_pass "both semantics" \
    || kt_test_fail "own=$own_ok non=$non_ok"

# --- Delete invalid index: rc 1, NOTHING freed ---
kt_test_start "Delete out-of-bounds: rc 1, nothing freed"
TList.new b1; TObjectList.new L
L.Add b1 >/dev/null
L.Delete 5 2>/dev/null; hi=$?
L.Delete -1 2>/dev/null; lo=$?
if [[ $hi -eq 1 && $lo -eq 1 ]] && alive b1; then
    kt_test_pass "rc 1/1, b1 alive"
else
    kt_test_fail "hi=$hi lo=$lo alive=$(alive b1 && echo y || echo n)"
fi
L.delete

# --- Remove: frees only when present; miss frees nothing ---
kt_test_start "Remove: hit frees (owning); miss leaves alive"
TList.new c1; TList.new c2; TObjectList.new L
L.Add c1 >/dev/null
L.Remove c1; r1=$RESULT
L.Remove c2; r2=$RESULT
if [[ "$r1" == "0" && "$r2" == "-1" ]] && ! alive c1 && alive c2; then
    kt_test_pass "hit freed (idx 0), miss alive (-1)"
else
    kt_test_fail "r1=$r1 r2=$r2 c1=$(alive c1 && echo y || echo n) c2=$(alive c2 && echo y || echo n)"
fi
L.delete; c2.delete

# --- Put: replacement frees OLD; same-handle no-op; oob frees nothing ---
kt_test_start "Put: old freed on replace; same handle kept; oob frees nothing"
TList.new d1; TList.new d2; TObjectList.new L
L.Add d1 >/dev/null
L.Put 0 d2
step1=$([[ "$(alive d1 && echo y || echo n)" == "n" ]] && alive d2 && echo ok)
L.Put 0 d2                      # same handle -> must NOT free
step2=$(alive d2 && echo ok)
L.Put 7 d2 2>/dev/null; rc=$?   # oob -> rc1, d2 untouched
step3=$([[ $rc -eq 1 ]] && alive d2 && echo ok)
[[ "$step1$step2$step3" == "okokok" ]] && kt_test_pass "replace/same/oob all correct" \
    || kt_test_fail "$step1/$step2/$step3"
L.delete

# --- BatchDelete: frees exactly the clamped range ---
kt_test_start "BatchDelete: frees the clamped range only"
TList.new e1; TList.new e2; TList.new e3; TObjectList.new L
L.Add e1 >/dev/null; L.Add e2 >/dev/null; L.Add e3 >/dev/null
L.BatchDelete 1 99              # clamps to [1,2]
st="$(alive e1 && echo y || echo n)$(alive e2 && echo y || echo n)$(alive e3 && echo y || echo n)"
[[ "$st" == "ynn" && "$(L.count)" == "1" ]] && kt_test_pass "e1 alive, e2+e3 freed, count 1" \
    || kt_test_fail "st=$st count=$(L.count)"
L.delete

# --- duplicate handle stored twice: freed once, second free is a no-op ---
kt_test_start "duplicate handle in owning list: Clear survives double entry"
TList.new f1; TObjectList.new L
L.Add f1 >/dev/null; L.Add f1 >/dev/null
L.Clear; rc=$?
[[ $rc -eq 0 && "$(L.count)" == "0" ]] && ! alive f1 && kt_test_pass "freed once, rc 0" \
    || kt_test_fail "rc=$rc count=$(L.count) alive=$(alive f1 && echo y || echo n)"
L.delete

# --- mixed elements: live handle + plain string + already-dead handle ---
kt_test_start "mixed live/string/dead elements: Clear is clean"
TList.new g1; TList.new g2; g2.delete        # g2 = dead handle string
TObjectList.new L
L.Add g1 >/dev/null; L.Add "plain text" >/dev/null; L.Add g2 >/dev/null; L.Add "" >/dev/null
L.Clear; rc=$?
[[ $rc -eq 0 && "$(L.count)" == "0" ]] && ! alive g1 && kt_test_pass "live freed, rest no-ops, rc 0" \
    || kt_test_fail "rc=$rc count=$(L.count)"
L.delete

# --- owns toggled mid-life changes Delete behavior ---
kt_test_start "owns_objects toggle mid-life: Delete honors the current value"
TList.new h1; TList.new h2; TObjectList.new L
L.Add h1 >/dev/null; L.Add h2 >/dev/null
L.owns_objects = "false"
L.Delete 0                       # h1 must survive
s1=$(alive h1 && echo ok)
L.owns_objects = "true"
L.Delete 0                       # h2 must be freed
s2=$([[ "$(alive h2 && echo y || echo n)" == "n" ]] && echo ok)
[[ "$s1$s2" == "okok" ]] && kt_test_pass "false->alive, true->freed" || kt_test_fail "$s1/$s2"
L.delete; h1.delete

# --- Extract releases ownership: survives the list's destruction ---
kt_test_start "Extract releases ownership: element survives list.delete"
TList.new i1; TObjectList.new L
L.Add i1 >/dev/null
L.Extract i1 >/dev/null
L.delete
if alive i1; then kt_test_pass "extracted element survived"; i1.delete
else kt_test_fail "extracted element was freed by the list"; fi

# --- FindInstanceOf edges: skips non-instances; bad arg rc 2 ---
kt_test_start "FindInstanceOf: skips plain strings; empty class -> rc 2"
TList.new j1; TObjectList.new L false
L.Add "TList" >/dev/null          # a STRING that spells a class name — not an instance
L.Add j1 >/dev/null
L.FindInstanceOf TList; f=$RESULT
L.FindInstanceOf "" 2>/dev/null; rc=$?
[[ "$f" == "1" && $rc -eq 2 ]] && kt_test_pass "string skipped (found @1); rc 2 on empty" \
    || kt_test_fail "f=$f rc=$rc"
L.delete; j1.delete

# --- destructor with many owned elements ---
kt_test_start "destructor frees ALL owned elements (5)"
hs=()
for k in 1 2 3 4 5; do TList.new "tk$k"; hs+=("tk$k"); done
TObjectList.new L
for h in "${hs[@]}"; do L.Add "$h" >/dev/null; done
L.delete
left=0; for h in "${hs[@]}"; do alive "$h" && left=$((left+1)); done
[[ $left -eq 0 ]] && kt_test_pass "all 5 freed" || kt_test_fail "$left survivors"

# --- zero-fork: full ownership lifecycle under PATH='' ---
kt_test_start "PATH='' : removal paths + Extract + FindInstanceOf fork-free"
zf="$(
    PATH=''
    source "$TOL_DIR/tobjectlist.sh" 2>/dev/null
    TList.new z1; TList.new z2; TList.new z3
    TObjectList.new ZL
    ZL.Add z1 >/dev/null; ZL.Add z2 >/dev/null; ZL.Add z3 >/dev/null
    ZL.Delete 0
    ZL.Extract z2 >/dev/null
    ZL.FindInstanceOf TList >/dev/null
    ZL.Clear
    ZL.delete
    a=$(declare -F z1.delete >/dev/null 2>&1 && echo y || echo n)
    b=$(declare -F z2.delete >/dev/null 2>&1 && echo y || echo n)
    c=$(declare -F z3.delete >/dev/null 2>&1 && echo y || echo n)
    printf '%s%s%s' "$a" "$b" "$c"
)"
[[ "$zf" == "nyn" ]] && kt_test_pass "deleted-freed / extracted-alive / cleared-freed" \
    || kt_test_fail "PATH='' got '$zf' (want nyn)"

kt_test_log "003_OwnershipTorture.sh completed"
