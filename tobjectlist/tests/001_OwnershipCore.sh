#!/bin/bash
# 001_OwnershipCore.sh - tobjectlist P0: the WORKING ownership core.
# Pins: ctor default owns=true (FPC TestCreate), ctor token true/false
# (FPC Create(FreeObjects)), unknown token rc 1 (still a valid owning list),
# owns_objects readable/writable mid-life, THE HEADLINE CONTRACT (FPC
# TestOwnsObjects): deleting an OWNING list frees its elements — a
# non-owning list leaves them alive; _free guard: double-free and
# non-instance strings are silent no-ops; inherited TList surface works on a
# TObjectList; zero-fork. Removal-path overrides (Delete/Clear/...) are P1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TOL_DIR="$SCRIPT_DIR/.."
source "$TOL_DIR/tobjectlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TObjectList ownership core (P0)"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }   # liveness = dispatcher exists

# --- FPC TestCreate: created empty, owns_objects true by default ---
kt_test_start "create: count 0, owns_objects true by default"
TObjectList.new L
if [[ "$(L.count)" == "0" && "$(L.owns_objects)" == "true" ]]; then
    kt_test_pass "count=0 owns=true"
else
    kt_test_fail "count=$(L.count) owns=$(L.owns_objects)"
fi
L.delete

# --- ctor token: false / true / unknown ---
kt_test_start "ctor token: false -> non-owning; true -> owning; unknown -> rc 1, still valid+owning"
TObjectList.new A false; oa="$(A.owns_objects)"
TObjectList.new B true;  ob="$(B.owns_objects)"
TObjectList.new C bogus 2>/dev/null; rc=$?; oc="$(C.owns_objects)"; C.Add x; cc="$(C.count)"
if [[ "$oa" == "false" && "$ob" == "true" && $rc -ne 0 && "$oc" == "true" && "$cc" == "1" ]]; then
    kt_test_pass "false/true honored; bogus rc!=0, list valid owning"
else
    kt_test_fail "oa=$oa ob=$ob rc=$rc oc=$oc cc=$cc"
fi
A.delete; B.delete; C.delete

# --- THE HEADLINE (FPC TestOwnsObjects): owning list frees elements on delete ---
kt_test_start "owning list.delete frees its elements (FPC TestOwnsObjects)"
TList.new obj1; TList.new obj2            # elements are themselves kklass instances
TObjectList.new OWN
OWN.Add obj1; OWN.Add obj2
a1=$(alive obj1 && echo yes || echo no); a2=$(alive obj2 && echo yes || echo no)
OWN.delete
d1=$(alive obj1 && echo yes || echo no); d2=$(alive obj2 && echo yes || echo no)
if [[ "$a1 $a2" == "yes yes" && "$d1 $d2" == "no no" ]]; then
    kt_test_pass "alive before (yes yes) -> freed after (no no)"
else
    kt_test_fail "before=[$a1 $a2] after=[$d1 $d2]"
fi

# --- non-owning list leaves elements alive (FPC Create(False) pattern) ---
kt_test_start "non-owning list.delete leaves elements alive"
TList.new obj3
TObjectList.new NOWN false
NOWN.Add obj3
NOWN.delete
if alive obj3; then
    kt_test_pass "obj3 still alive"; obj3.delete
else
    kt_test_fail "obj3 was wrongly freed"
fi

# --- owns_objects writable mid-life (FPC property is read/write) ---
kt_test_start "owns_objects toggled mid-life changes destructor behavior"
TList.new obj4
TObjectList.new T
T.Add obj4
T.owns_objects = "false"
T.delete
if alive obj4; then
    kt_test_pass "toggle to false -> element survived"; obj4.delete
else
    kt_test_fail "element freed despite owns=false"
fi

# --- _free guard: non-instance strings + double-free are silent no-ops ---
kt_test_start "_free guard: non-instance string and double-free are no-ops"
TObjectList._free "not_an_instance"; r1=$?
TList.new obj5; TObjectList._free obj5; r2=$?
TObjectList._free obj5; r3=$?                     # second free: dispatcher gone
TObjectList._free ""; r4=$?
if [[ $r1 -eq 0 && $r2 -eq 0 && $r3 -eq 0 && $r4 -eq 0 ]] && ! alive obj5; then
    kt_test_pass "all rc 0; obj5 freed exactly once"
else
    kt_test_fail "rcs=$r1/$r2/$r3/$r4 alive=$(alive obj5 && echo yes || echo no)"
fi

# --- owning list with MIXED elements: instances freed, plain strings ignored ---
kt_test_start "mixed elements: instances freed, plain strings no-op"
TList.new obj6
TObjectList.new M
M.Add obj6; M.Add "just-a-string"; M.Add ""
M.delete; rc=$?
if [[ $rc -eq 0 ]] && ! alive obj6; then
    kt_test_pass "delete rc 0; instance freed, strings ignored"
else
    kt_test_fail "rc=$rc obj6-alive=$(alive obj6 && echo yes || echo no)"
fi

# --- inherited TList surface works on a TObjectList ---
kt_test_start "inherited surface: Add/Get/IndexOf/First/Last/Sort on handles"
TObjectList.new S false
S.Add zeta; S.Add alpha; S.Add mid
S.Get 1; g=$RESULT
S.IndexOf mid; im=$RESULT
S.Sort
S.First; f=$RESULT; S.Last; l=$RESULT
if [[ "$g" == "alpha" && "$im" == "2" && "$f" == "alpha" && "$l" == "zeta" ]]; then
    kt_test_pass "Get=alpha idx(mid)=2 sorted First=alpha Last=zeta"
else
    kt_test_fail "g=$g im=$im f=$f l=$l"
fi
S.delete

# --- empty owning list deletes cleanly ---
kt_test_start "empty owning list deletes cleanly"
TObjectList.new E
E.delete
[[ $? -eq 0 ]] && kt_test_pass "rc 0" || kt_test_fail "rc=$?"

# --- zero-fork: create/add/destroy under PATH='' ---
kt_test_start "PATH='' : ownership core needs no external commands"
zf="$(
    PATH=''
    source "$TOL_DIR/tobjectlist.sh" 2>/dev/null
    TList.new zo
    TObjectList.new ZL
    ZL.Add zo >/dev/null      # Add is a func: under $() it echoes RESULT
    ZL.delete
    declare -F "zo.delete" >/dev/null 2>&1 && printf 'leaked' || printf 'freed'
)"
[[ "$zf" == "freed" ]] && kt_test_pass "owning delete freed element under PATH=''" \
    || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "001_OwnershipCore.sh completed"
