#!/bin/bash
# P7 / D3 + R8 — the kcl return contract for the math static class.
#
#   D3   every public member answers through RESULT and prints NOTHING on a
#        direct call; inside $( ) it prints its value exactly once. For a
#        kklass STATIC class this is `static proc` + a unit-local `math._ret`,
#        not `static func` (kcl/README.md 1.1; same as tpath/tfile/dateutils).
#   R8   boolean members carry the answer in the EXIT STATUS and the word
#        true/false in RESULT.
#   M12  `ifThen c x ''` answered `0`: `${3:-0}` treats an explicit empty
#        string as an absent argument. (P1 closed only the echo half of M12.)
#   X-ECHO values that look like echo options round-trip verbatim.
#
# The completeness check at the end walks the CLASS INTERFACE, so a member
# added later cannot skip the contract unnoticed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "D3ReturnContract" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
UNIT="$MATH_DIR/math.sh"
source "$UNIT"
math.feStart

TMPD="$(cd "$(kt_fixture_tmpdir)" && pwd)"; TMPOUT="$TMPD/o"; TMPERR="$TMPD/e"

# ---------------------------------------------------------------------------
# 1. A direct call is SILENT and leaves the value in RESULT.
# ---------------------------------------------------------------------------
kt_test_start "a direct call prints nothing and sets RESULT [D3]"
ok=true; why=""
_silent() {   # EXPECTED MEMBER ARGS...
    local exp="$1"; shift
    RESULT="<unset>"
    # redirect to FILES, not to $( ): a $( ) capture is a subshell, and the
    # contract says a member DOES print there.
    { "math.$1" "${@:2}"; } > "$TMPOUT" 2>"$TMPERR"
    local so se; so="$(<"$TMPOUT")"; se="$(<"$TMPERR")"
    [[ -z "$so" ]] || { ok=false; why+=" [math.$* printed '$so' on stdout]"; }
    [[ -z "$se" ]] || { ok=false; why+=" [math.$* printed '$se' on stderr]"; }
    [[ "$RESULT" == "$exp" ]] || { ok=false; why+=" [math.$* RESULT='$RESULT' want '$exp']"; }
}
_silent 3        min 3 7
_silent 7        max 3 7
_silent -1       sign -5
_silent 5        ensureRange 99 1 5
_silent 0        compareValue 3 3
_silent 9        ifThen true 9 4
_silent 3        ceil 2.1
_silent -3       floor -2.1
_silent "3 2"    divMod 17 5
_silent 1024     intPower 2 10
_silent 15       sumInt 1 2 3 4 5
_silent 3.1415926535897932385 pi
_silent inf      infinity
_silent 2        sqrt 4
_silent 5        hypot 3 4
_silent 5        mean 2 4 4 4 5 5 7 9
_silent 2        roundTo 2.5 0
_silent "0.5 4"  frexp 8
_silent rmNearest getRoundMode
$ok && kt_test_pass "19 members silent, RESULT correct" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 2. Inside $( ) the value is printed EXACTLY ONCE (no trailing duplicate).
# ---------------------------------------------------------------------------
kt_test_start "inside \$( ) the value is printed exactly once [D3]"
ok=true; why=""
_captured() {   # EXPECTED MEMBER ARGS...
    local exp="$1"; shift
    local v; v="$("math.$1" "${@:2}")"
    [[ "$v" == "$exp" ]] || { ok=false; why+=" [\$(math.$*)='$v' want '$exp']"; }
}
_captured 3        min 3 7
_captured -1       sign -5
_captured "3 2"    divMod 17 5
_captured 2        sqrt 4
_captured 5        mean 2 4 4 4 5 5 7 9
_captured 1024     intPower 2 10
_captured inf      infinity
_captured "0.5 4"  frexp 8
_captured true     isNan nan
_captured false    isNan 1
$ok && kt_test_pass "10 members print once under \$( )" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 3. R8 — booleans answer with rc; RESULT carries the word.
# ---------------------------------------------------------------------------
kt_test_start "boolean members answer by exit status [R8]"
ok=true; why=""
_bool() {   # EXPECTED(true|false) MEMBER ARGS...
    local exp="$1"; shift
    RESULT="<unset>"
    if "math.$1" "${@:2}"; then
        [[ "$exp" == true ]] || { ok=false; why+=" [math.$* rc 0, want $exp]"; }
    else
        [[ "$exp" == false ]] || { ok=false; why+=" [math.$* rc!=0, want $exp]"; }
    fi
    [[ "$RESULT" == "$exp" ]] || { ok=false; why+=" [math.$* RESULT='$RESULT' want '$exp']"; }
}
_bool true  inRange 5 1 10
_bool false inRange 11 1 10
_bool false inRange 0 1 10
_bool true  isZero 0
_bool false isZero 1
_bool true  isZero 0.0000000000001
_bool true  sameValue 1.0 1.0
_bool false sameValue 1.0 2.0
_bool true  isNan nan
_bool false isNan 1.5
_bool true  isInfinite inf
_bool true  isInfinite -inf
_bool false isInfinite 1e308
_bool true  feActive
$ok && kt_test_pass "14 boolean rows agree on rc and word" || kt_test_fail "$why"

kt_test_start "a boolean member is usable from if / && / ! under set -eu [R8, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if math.inRange 5 1 10; then printf 'in '; fi
math.inRange 50 1 10 || printf 'out '
! math.isNan 1 && printf 'notnan '
math.isZero 0 && printf 'zero '
printf 'end'" 2>&1)"
if [[ "$out" == "in out notnan zero end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

# ---------------------------------------------------------------------------
# 4. M12 — an explicitly empty argument is a VALUE, not an absent argument.
# ---------------------------------------------------------------------------
kt_test_start "ifThen with an explicit empty third argument answers empty [M12]"
ok=true; why=""
RESULT="<unset>"; math.ifThen false x ""
[[ -z "$RESULT" ]] || { ok=false; why+=" [ifThen false x '' -> '$RESULT']"; }
v="$(math.ifThen false x "")"
[[ -z "$v" ]] || { ok=false; why+=" [\$() -> '$v']"; }
RESULT="<unset>"; math.ifThen false x
[[ "$RESULT" == 0 ]] || { ok=false; why+=" [ifThen false x -> '$RESULT' want the 0 default]"; }
RESULT="<unset>"; math.ifThen true "" y
[[ -z "$RESULT" ]] || { ok=false; why+=" [ifThen true '' y -> '$RESULT']"; }
$ok && kt_test_pass "explicit '' survives, absent still defaults to 0" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 5. X-ECHO — echo-option-shaped values round-trip verbatim.
# ---------------------------------------------------------------------------
kt_test_start "values that look like echo options round-trip [X-ECHO]"
ok=true; why=""
for v in -n -e -E -neE "-n -e"; do
    RESULT="<unset>"; math.ifThen true "$v" z
    [[ "$RESULT" == "$v" ]] || { ok=false; why+=" [ifThen -> '$RESULT' want '$v']"; }
    c="$(math.ifThen true "$v" z)"
    [[ "$c" == "$v" ]] || { ok=false; why+=" [\$() -> '$c' want '$v']"; }
    RESULT="<unset>"; math.randomFrom "$v"
    [[ "$RESULT" == "$v" ]] || { ok=false; why+=" [randomFrom -> '$RESULT']"; }
done
$ok && kt_test_pass "5 shapes verbatim, direct and captured" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 6. Errors: rc 1, RESULT cleared, nothing printed anywhere (kcl README 1.2).
#    RESULT must be CLEARED, not left holding the previous call's answer.
# ---------------------------------------------------------------------------
kt_test_start "an error clears RESULT and prints nothing [contract 1.2]"
ok=true; why=""
_err() {   # MEMBER ARGS...
    math.max 1234 5678 >/dev/null            # prime RESULT with something visible
    { "math.$1" "${@:2}"; } > "$TMPOUT" 2>"$TMPERR"; local rc=$?
    local so se; so="$(<"$TMPOUT")"; se="$(<"$TMPERR")"
    (( rc != 0 )) || { ok=false; why+=" [math.$* rc 0]"; }
    [[ -z "$so$se" ]] || { ok=false; why+=" [math.$* printed '$so$se']"; }
    [[ -z "$RESULT" ]] || { ok=false; why+=" [math.$* left RESULT='$RESULT']"; }
}
_err divMod 1 0
_err divMod abc 1
_err sumInt 1 abc
_err minIntValue 1 abc
_err maxIntValue abc
_err randomRange 1 abc
_err randomFrom
_err sqrt abc
_err mean 1 abc
_err setRoundMode rmDown
_err setPrecisionMode pmSingle
_err setExceptionMask "[]"
$ok && kt_test_pass "12 error rows clean" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 7. No forks on the Tier-A hot paths: a direct call must not change BASHPID,
#    and the whole core must work with an empty PATH.
# ---------------------------------------------------------------------------
kt_test_start "Tier-A direct calls are fork-free (BASHPID unchanged) [1.8]"
ok=true; why=""
p0=$BASHPID
for m in "min 3 7" "max 3 7" "sign -5" "inRange 5 1 10" "ensureRange 9 1 5" \
         "compareValue 3 5" "ifThen true 9 4" "ceil -2.1" "floor -2.1" \
         "divMod 17 5" "intPower 2 10" "sumInt 1 2 3" "randomRange 1 100" \
         "isNan 1.0" "isInfinite 1.0" "randomFrom a b c" "pi" "maxDouble"; do
    read -r -a a <<< "$m"
    "math.${a[0]}" "${a[@]:1}" >/dev/null 2>&1
    [[ $BASHPID == "$p0" ]] || { ok=false; why+=" [math.$m forked]"; }
done
$ok && kt_test_pass "18 members, BASHPID $p0 throughout" || kt_test_fail "$why"

kt_test_start "no member body contains a command substitution [1.8]"
# NB `declare -f math.min` returns kklass's static DISPATCHER, not the body —
# the real body is math.__static_min (kklass.sh:982). Reading the dispatcher
# would make this assertion (and the completeness one below) vacuous: its own
# local is named __kk_return_value, which contains the substring `_ret`.
bad=""
for m in min max minValue maxValue minIntValue maxIntValue sign inRange \
         ensureRange isZero sameValue compareValue ifThen ceil ceil64 floor \
         floor64 divMod intPower sumInt randomRange randomFrom isNan \
         isInfinite pi e infinity nan; do
    body="$(declare -f "math.__static_$m" 2>/dev/null)"
    [[ -n "$body" ]] || { bad+="$m:no-body "; continue; }
    # `$(( … ))` is ARITHMETIC expansion — fork-free, and half the Tier-A core
    # is built out of it. Only `$( … )` and backticks fork, so drop the
    # arithmetic openers before looking.
    probe="${body//'$(('/}"
    [[ "$probe" == *'$('* || "$probe" == *'`'* ]] && bad+="$m "
done
[[ -z "$bad" ]] && kt_test_pass "none of 27 Tier-A bodies substitutes a command" \
                || kt_test_fail "command substitution in: $bad"

# ---------------------------------------------------------------------------
# 8. Completeness: EVERY public member of the class obeys D3 (no member is
#    still on the old `printf ... "$REPLY"` shape). Read the interface out of
#    the source rather than a hand-kept list.
# ---------------------------------------------------------------------------
kt_test_start "every declared member returns through math._ret [D3, completeness]"
members=()
while read -r _ _ name; do
    [[ -n "$name" ]] && members+=("$name")
done < <(grep -E '^ +static proc [a-zA-Z0-9_]+$' "$UNIT")
bad=""; n=0
for m in "${members[@]}"; do
    body="$(declare -f "math.__static_$m" 2>/dev/null)"
    [[ -n "$body" ]] || { bad+="$m:missing "; continue; }
    (( n += 1 ))
    # feStart/feStop are lifecycle procs with no value; ceil64/floor64 are
    # one-line delegations to ceil/floor (FPC has both, the port has one body);
    # everything else must reach math._ret — or math._err, the error half of
    # the same contract — directly or through one of the _fe* shims.
    case "$m" in feStart|feStop) continue ;; esac
    [[ "$body" == *"math._ret"* || "$body" == *"math._retBool"* \
       || "$body" == *"math._err"* || "$body" == *"math._fe"* \
       || "$body" == *"math.ceil "* || "$body" == *"math.floor "* ]] || bad+="$m "
    [[ "$body" == *"printf '%s\\n'"* ]] && bad+="$m:still-echoes "
done
if [[ -z "$bad" && $n -ge 120 ]]; then
    kt_test_pass "$n members, all on the return contract"
else
    kt_test_fail "n=$n offenders: $bad"
fi
