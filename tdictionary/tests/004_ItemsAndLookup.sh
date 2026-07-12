#!/bin/bash
# 004_ItemsAndLookup.sh - GetItem / SetItem / TryGetValue / ContainsKey (P1.2)
# FPC seed: tests.generics.dictionary2.pas (TestAddModify — Items[] update path;
# AssertKeyVal/AssertKeyNotFound — TryGetValue/ContainsKey shapes).
# FPC impl refs: GetItem :640 (EListError on miss), SetItem :662 (UPDATE-ONLY,
# EListError SItemNotFound — FPC differs from Delphi upsert here!),
# TryGetValue :705 (Default(TValue) + False on miss), ContainsKey :742.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: Items[] accessors and lookups"

TDictionary.new d
d.Add one "value one"
d.Add two "value two"

# --- GetItem ---
kt_test_start "GetItem hit: value via \$() and via direct call + RESULT"
cap="$(d.GetItem one)"
d.GetItem one >/dev/null
if [[ "$cap" == "value one" && "$RESULT" == "value one" ]]; then
    kt_test_pass "both access forms agree"
else
    kt_test_fail "cap=[$cap] RESULT=[$RESULT]"
fi

kt_test_start "GetItem miss: rc=1, RESULT cleared to ''"
d.GetItem one >/dev/null              # prime RESULT with a stale value
d.GetItem missing >/dev/null 2>&1
rc=$?
if [[ $rc -eq 1 && "$RESULT" == "" ]]; then
    kt_test_pass "rc=1 and RESULT='' (stale value NOT leaked)"
else
    kt_test_fail "rc=$rc RESULT=[$RESULT]"
fi

# --- SetItem (update-only!) ---
kt_test_start "SetItem hit: value updated in place (count stable)"
d.SetItem one "updated one"
rc=$?
if [[ $rc -eq 0 && "$(d.GetItem one)" == "updated one" && "$(d.count)" == "2" ]]; then
    kt_test_pass "update ok"
else
    kt_test_fail "rc=$rc value=$(d.GetItem one) count=$(d.count)"
fi

kt_test_start "SetItem miss: rc=1 and dictionary NOT mutated (FPC update-only)"
d.SetItem ghost "phantom" 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(d.count)" == "2" ]] && ! d.ContainsKey ghost; then
    kt_test_pass "no upsert — FPC semantics (Delphi would have inserted)"
else
    kt_test_fail "rc=$rc count=$(d.count) ghost-present=$(d.ContainsKey ghost && echo yes || echo no)"
fi

# --- TryGetValue ---
kt_test_start "TryGetValue hit: rc=0, RESULT=value"
d.TryGetValue two >/dev/null
rc=$?
if [[ $rc -eq 0 && "$RESULT" == "value two" ]]; then
    kt_test_pass "hit ok"
else
    kt_test_fail "rc=$rc RESULT=[$RESULT]"
fi

kt_test_start "TryGetValue miss: rc=1, RESULT='' (FPC Default(TValue))"
d.TryGetValue two >/dev/null          # prime RESULT
d.TryGetValue nothere >/dev/null
rc=$?
if [[ $rc -eq 1 && "$RESULT" == "" ]]; then
    kt_test_pass "miss ok"
else
    kt_test_fail "rc=$rc RESULT=[$RESULT]"
fi

kt_test_start "TryGetValue finds a pair whose VALUE is empty"
d.Add hollow ""
d.TryGetValue hollow >/dev/null
rc=$?
if [[ $rc -eq 0 && "$RESULT" == "" ]]; then
    kt_test_pass "rc distinguishes empty value (rc=0) from miss (rc=1)"
else
    kt_test_fail "rc=$rc RESULT=[$RESULT]"
fi

# --- ContainsKey ---
kt_test_start "ContainsKey hit/miss via exit status"
if d.ContainsKey one && ! d.ContainsKey absent; then
    kt_test_pass "rc=0 present, rc!=0 absent"
else
    kt_test_fail "ContainsKey broken"
fi

# --- exotic keys through the PUBLIC API (P0 torture subset) ---
kt_test_start "Exotic keys via public API: '' ']' '*' 'a b' newline 'k'"
ok=1
for key in '' ']' '*' 'a b' $'a\nb' 'k'; do
    d.Add "$key" "V($key)" || { ok=0; break; }
    d.ContainsKey "$key" || { ok=0; break; }
    [[ "$(d.GetItem "$key")" == "V($key)" ]] || { ok=0; break; }
done
if [[ $ok -eq 1 ]]; then
    kt_test_pass "all exotic keys add/contain/get through the API"
else
    kt_test_fail "failed on key <$key>"
fi

# --- lossless path for trailing newlines ---
kt_test_start "Trailing-newline value: direct call + RESULT is lossless"
v=$'line1\nline2\n\n'
d.AddOrSetValue ml "$v"
d.GetItem ml >/dev/null
direct="$RESULT"
cap="$(d.GetItem ml)"
if [[ "$direct" == "$v" && "$cap" == $'line1\nline2' ]]; then
    kt_test_pass "RESULT exact; \$() strips trailing newlines (documented caveat)"
else
    kt_test_fail "direct=$(printf '%q' "$direct") cap=$(printf '%q' "$cap")"
fi

d.delete

kt_test_log "004_ItemsAndLookup.sh completed"
