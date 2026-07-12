#!/bin/bash
# 010_ForEach.sh - ForEach (P3.2): pair-enumerator analog with SNAPSHOT
# semantics. FPC enumeration over a mutating dictionary is undefined; this
# implementation is defined-safe: deleted pairs are skipped (existence
# re-check), added pairs are not visited in the current pass.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "010: ForEach"

kt_test_start "visits every pair exactly once, key+value byte-exact"
TDictionary.new d
d.AddPairs alpha A '' EMPTY $'n\nl' NL '*' GLOB 'a b' SP
declare -A SEEN=()
rec() { SEEN["x$1"]="$2"; }
d.ForEach rec
rc=$?
if [[ $rc -eq 0 && ${#SEEN[@]} -eq 5 && "${SEEN[xalpha]}" == "A" && "${SEEN[x]}" == "EMPTY" \
      && "${SEEN[x$'n\nl']}" == "NL" && "${SEEN[x*]}" == "GLOB" && "${SEEN[xa b]}" == "SP" ]]; then
    kt_test_pass "5 pairs visited, exotic keys/values intact"
else
    kt_test_fail "rc=$rc seen=${#SEEN[@]}"
fi
d.delete

kt_test_start "callback deleting OTHER pairs: visited once, no crash, skips deleted"
TDictionary.new m
m.AddPairs a 1 b 2 c 3
declare -A SEEN2=()
FIRST=""
wipe_others() {
    SEEN2["x$1"]=1
    if [[ -z "$FIRST" ]]; then
        FIRST="$1"
        local k
        for k in a b c; do
            [[ "$k" != "$1" ]] && m.Remove "$k"
        done
    fi
}
m.ForEach wipe_others
rc=$?
if [[ $rc -eq 0 && ${#SEEN2[@]} -eq 1 && "$(m.count)" == "1" ]] && m.ContainsKey "$FIRST"; then
    kt_test_pass "only the first-visited pair ($FIRST) seen; deletions honored mid-pass"
else
    kt_test_fail "rc=$rc visited=${#SEEN2[@]} count=$(m.count)"
fi

kt_test_start "callback deleting ITS OWN pair: all pairs still visited"
m.Clear; m.AddPairs a 1 b 2 c 3
declare -A SEEN3=()
suicide() { SEEN3["x$1"]=1; m.Remove "$1"; }
m.ForEach suicide
if [[ ${#SEEN3[@]} -eq 3 && "$(m.count)" == "0" ]]; then
    kt_test_pass "3 visits, dict empty afterwards"
else
    kt_test_fail "visited=${#SEEN3[@]} count=$(m.count)"
fi

kt_test_start "callback ADDING pairs: additions not visited in this pass"
m.Clear; m.AddPairs a 1 b 2 c 3
declare -A SEEN4=()
grower() {
    SEEN4["x$1"]=1
    [[ "$1" == z* ]] || m.AddOrSetValue "z$1" zz
}
m.ForEach grower
if [[ ${#SEEN4[@]} -eq 3 && "$(m.count)" == "6" \
      && -z "${SEEN4[xza]+x}" ]] && m.ContainsKey za && m.ContainsKey zb; then
    kt_test_pass "3 originals visited, 3 additions present but unvisited"
else
    kt_test_fail "visited=${#SEEN4[@]} count=$(m.count)"
fi

kt_test_start "callback exit status ignored: iteration continues"
m.Clear; m.AddPairs a 1 b 2 c 3
CALLS=0
failing() { CALLS=$((CALLS+1)); return 7; }
m.ForEach failing
rc=$?
if [[ $rc -eq 0 && $CALLS -eq 3 ]]; then
    kt_test_pass "all 3 called despite rc=7; ForEach rc=0"
else
    kt_test_fail "rc=$rc calls=$CALLS"
fi

kt_test_start "empty dict: callback never invoked, rc=0"
m.Clear
CALLS=0
counter() { CALLS=$((CALLS+1)); }
m.ForEach counter
rc=$?
if [[ $rc -eq 0 && $CALLS -eq 0 ]]; then
    kt_test_pass "zero invocations"
else
    kt_test_fail "rc=$rc calls=$CALLS"
fi

kt_test_start "nonexistent callback: rc=1"
m.ForEach no_such_function 2>/dev/null
rc=$?
if [[ $rc -eq 1 ]]; then
    kt_test_pass "rejected"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "zero-fork: ForEach over 50 pairs with empty PATH"
m.Clear
for i in $(seq 1 50); do m.Add "k$i" "v$i"; done
if ( PATH=''
     n=0
     cnt() { n=$((n+1)); }
     m.ForEach cnt || exit 1
     [[ $n -eq 50 ]] || exit 1
   ); then
    kt_test_pass "50 callbacks, no external process"
else
    kt_test_fail "forked or miscounted"
fi
m.delete

kt_test_log "010_ForEach.sh completed"
