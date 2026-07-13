#!/bin/bash
# 019_GetPut.sh - TList.Get / TList.Put are now REAL (previously subclass stubs).
# A raw TList holds strings, so indexed read/write is meaningful here. Bounds are
# [0,count); out of range -> rc 1 (Get leaves RESULT untouched, Put changes
# nothing). Get is a `func` (returns via RESULT); Put is a `proc`. TStringList
# inherits both unchanged (its own overrides were removed as duplicates).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "019: TList.Get / TList.Put (real indexed access)"

# --- Get: valid indices ---
kt_test_start "Get returns the element at each valid index"
TList.new L; for x in a b c; do L.Add "$x"; done
L.Get 0; g0=$RESULT; L.Get 1; g1=$RESULT; L.Get 2; g2=$RESULT
[[ "$g0" == "a" && "$g1" == "b" && "$g2" == "c" ]] && kt_test_pass "a/b/c" || kt_test_fail "$g0/$g1/$g2"
L.delete

# --- Get: out of bounds -> rc 1, RESULT untouched ---
kt_test_start "Get out-of-bounds (>=count and <0) -> rc 1, RESULT untouched"
TList.new L; for x in a b c; do L.Add "$x"; done
RESULT="sentinel"; L.Get 3; hi=$?; r1=$RESULT
RESULT="sentinel"; L.Get -1; lo=$?; r2=$RESULT
[[ $hi -eq 1 && "$r1" == "sentinel" && $lo -eq 1 && "$r2" == "sentinel" ]] \
    && kt_test_pass "both rc 1, RESULT kept" || kt_test_fail "hi=$hi/$r1 lo=$lo/$r2"
L.delete

# --- Get on empty list -> rc 1 ---
kt_test_start "Get on empty list -> rc 1"
TList.new E; E.Get 0; [[ $? -eq 1 ]] && kt_test_pass "rc 1" || kt_test_fail "rc=$?"
E.delete

# --- Put: valid index writes; Put then Get round-trips ---
kt_test_start "Put writes at index; Get reads it back"
TList.new L; for x in a b c; do L.Add "$x"; done
L.Put 1 "B"; pr=$?
L.Get 1; g=$RESULT
L.Get 0; g0=$RESULT; L.Get 2; g2=$RESULT   # neighbours unchanged
[[ $pr -eq 0 && "$g" == "B" && "$g0" == "a" && "$g2" == "c" ]] \
    && kt_test_pass "put B@1, neighbours intact" || kt_test_fail "pr=$pr g=$g g0=$g0 g2=$g2"
L.delete

# --- Put: out of bounds -> rc 1, no change ---
kt_test_start "Put out-of-bounds (>=count and <0) -> rc 1, no change"
TList.new L; for x in a b c; do L.Add "$x"; done
L.Put 9 "x"; hi=$?
L.Put -1 "y"; lo=$?
L.Get 0; g0=$RESULT; L.Get 2; g2=$RESULT
[[ $hi -eq 1 && $lo -eq 1 && "$g0" == "a" && "$g2" == "c" ]] \
    && kt_test_pass "both rc 1, list unchanged" || kt_test_fail "hi=$hi lo=$lo g0=$g0 g2=$g2"
L.delete

# --- torture: newline/glob/quote elements survive Get/Put losslessly ---
kt_test_start "torture: Put/Get lossless for newline/glob/quote elements"
TList.new L; L.Add "x"; L.Add "y"
L.Put 0 $'a\nb'; L.Put 1 '* "q"'
L.Get 0; g0=$RESULT; L.Get 1; g1=$RESULT
[[ "$g0" == $'a\nb' && "$g1" == '* "q"' ]] && kt_test_pass "lossless" || kt_test_fail "g0=[$g0] g1=[$g1]"
L.delete

# --- $() capture: Get is a func, so $(list.Get i) echoes the value ---
kt_test_start "Get under \$(): value is echoed (func contract)"
TList.new L; for x in a b c; do L.Add "$x"; done
v="$(L.Get 2)"
[[ "$v" == "c" ]] && kt_test_pass "\$(L.Get 2) = c" || kt_test_fail "got '$v'"
L.delete

kt_test_log "019_GetPut.sh completed"
