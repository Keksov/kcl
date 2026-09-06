#!/bin/bash
# 009_KeysValues.sh - Keys / Values / KeysToArray / ValuesToArray / ToArrays (P3.1)
# FPC seed: tests.generics.dictionary.pas TestKeys (all keys present exactly
# once). Collections analogs: Keys/Values echo one item per line; the *ToArray
# nameref fills are the LOSSLESS forms (newline-safe). Order is UNSPECIFIED —
# comparisons are order-independent (sorted / set-based), same as FPC.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "009: Keys / Values / ToArray fills"

TDictionary.new d
d.AddPairs alpha A beta B gamma C

kt_test_start "Keys: every key exactly once (TestKeys analog, sorted compare)"
got="$(d.Keys | sort | tr '\n' '|')"
if [[ "$got" == "alpha|beta|gamma|" ]]; then
    kt_test_pass "keys: alpha beta gamma"
else
    kt_test_fail "got [$got]"
fi

kt_test_start "Values: every value exactly once (incl. duplicates twice)"
d.Add delta B          # duplicate VALUE
got="$(d.Values | sort | tr '\n' '|')"
if [[ "$got" == "A|B|B|C|" ]]; then
    kt_test_pass "values with duplicate B listed twice"
else
    kt_test_fail "got [$got]"
fi
d.Remove delta

kt_test_start "Keys/Values on an EMPTY dict: no output at all"
TDictionary.new e0
if [[ -z "$(e0.Keys)" && -z "$(e0.Values)" ]]; then
    kt_test_pass "empty output (zero lines, not one empty line)"
else
    kt_test_fail "unexpected output"
fi
e0.delete

kt_test_start "Keys->GetItem closure: every listed key resolves"
ok=1
while IFS= read -r k; do
    d.ContainsKey "$k" || { ok=0; break; }
done < <(d.Keys)
if [[ $ok -eq 1 && "$(d.Keys | wc -l)" == "3" ]]; then
    kt_test_pass "3 keys, all resolvable"
else
    kt_test_fail "a listed key did not resolve"
fi

kt_test_start "KeysToArray: LOSSLESS for exotic keys (newline, glob, empty)"
TDictionary.new x
x.AddPairs $'n\nl' NL '*' GLOB '' EMPTY 'a b' SP
x.KeysToArray XK
rc=$?
declare -A xkset=()
for k in "${XK[@]}"; do xkset["x$k"]=1; done
if [[ $rc -eq 0 && ${#XK[@]} -eq 4 && -n "${xkset[x$'n\nl']+x}" && -n "${xkset[x*]+x}" \
      && -n "${xkset[x]+x}" && -n "${xkset[xa b]+x}" ]]; then
    kt_test_pass "4 exotic keys round-trip byte-exact via nameref"
else
    kt_test_fail "rc=$rc n=${#XK[@]}"
fi

kt_test_start "ValuesToArray: values byte-exact (incl. trailing newline)"
TDictionary.new y
tv=$'v\n\n'
y.AddPairs one "$tv" two plain
y.ValuesToArray YV
found=0
for v in "${YV[@]}"; do [[ "$v" == "$tv" ]] && found=1; done
if [[ ${#YV[@]} -eq 2 && $found -eq 1 ]]; then
    kt_test_pass "trailing-newline value intact in the array"
else
    kt_test_fail "n=${#YV[@]} found=$found"
fi
y.delete

kt_test_start "ToArrays: index-aligned parallel arrays"
x.ToArrays TK TV
ok=1
[[ ${#TK[@]} -eq 4 && ${#TV[@]} -eq 4 ]] || ok=0
for i in "${!TK[@]}"; do
    x.GetItem "${TK[$i]}" >/dev/null
    [[ "$RESULT" == "${TV[$i]}" ]] || { ok=0; break; }
done
if [[ $ok -eq 1 ]]; then
    kt_test_pass "keys[i] -> values[i] for all i"
else
    kt_test_fail "misalignment at i=$i"
fi
x.delete

kt_test_start "ToArray fills RESET pre-existing content of the output arrays"
PRE=(junk1 junk2 junk3 junk4 junk5)
d.KeysToArray PRE
if [[ ${#PRE[@]} -eq 3 ]]; then
    kt_test_pass "old content cleared (5 -> 3 elements)"
else
    kt_test_fail "n=${#PRE[@]}"
fi

# A malformed output-array name is a malformed CALL, not a value the caller may
# legitimately try, so it answers rc 2 — kcl/README.md sections 1.2 and 1.7
# (owner decision, 2026-09-07: the README contract wins over the rc 1 these
# three members used to return, and over the rc 1 the review report suggested).
kt_test_start "Output-variable validation: empty / invalid / same-var -> rc 2"
d.KeysToArray "" 2>/dev/null;         rc1=$?
d.KeysToArray "bad name" 2>/dev/null; rc2=$?
d.ToArrays SAME SAME 2>/dev/null;     rc3=$?
d.KeysToArray "1bad" 2>/dev/null;     rc4=$?
d.ValuesToArray "a-b" 2>/dev/null;    rc5=$?
if [[ $rc1 -eq 2 && $rc2 -eq 2 && $rc3 -eq 2 && $rc4 -eq 2 && $rc5 -eq 2 ]]; then
    kt_test_pass "all five rejected with rc=2"
else
    kt_test_fail "rc1=$rc1 rc2=$rc2 rc3=$rc3 rc4=$rc4 rc5=$rc5"
fi

# The same validation must also refuse names that would ALIAS the unit's own
# nameref or the instance's storage. `d.KeysToArray __td_items` used to bind the
# output nameref to the very array the body then re-declares, so the `out=()`
# reset WIPED the dictionary and reported success (kcl review 2026-09-06, the
# G2-02 shape — found in tqueuestack/thashset, present here too).
kt_test_start "Output-variable validation: the unit's own and the instance's names -> rc 2, dict intact"
before="$(d.count)"
bad=""
for name in __td_items __td_oref __kk_x RESULT IFS this __inst__ d_items d_data; do
    d.KeysToArray "$name" 2>/dev/null; rc=$?
    [[ $rc -eq 2 ]] || bad+="rc[$name]=$rc "
done
after="$(d.count)"
if [[ -z "$bad" && "$before" == "$after" && "$before" != "0" ]]; then
    kt_test_pass "9 reserved names rejected, $after pairs intact"
else
    kt_test_fail "$bad count $before -> $after"
fi

kt_test_start "Output-variable validation: an associative target -> rc 2, target untouched"
declare -A ASSOC_TARGET=()
d.KeysToArray ASSOC_TARGET 2>/dev/null; rck=$?
d.ValuesToArray ASSOC_TARGET 2>/dev/null; rcv=$?
if [[ $rck -eq 2 && $rcv -eq 2 && ${#ASSOC_TARGET[@]} -eq 0 ]]; then
    kt_test_pass "rc 2 twice, target untouched"
else
    kt_test_fail "rck=$rck rcv=$rcv keys='${!ASSOC_TARGET[*]}'"
fi

kt_test_start "a valid name still fills and still returns rc 0"
declare -a OK_TARGET=(stale)
d.KeysToArray OK_TARGET; rc=$?
[[ $rc -eq 0 && ${#OK_TARGET[@]} -eq 3 ]] && kt_test_pass "rc 0, 3 keys" \
    || kt_test_fail "rc=$rc n=${#OK_TARGET[@]}"

d.delete

kt_test_log "009_KeysValues.sh completed"
