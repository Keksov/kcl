#!/bin/bash
# P7 / R11 — the float engine NEVER dies.
#
# Findings closed here:
#   M1  any awk fatal (a division by zero anywhere in the prelude) killed the
#       co-process; the call answered with an EMPTY line and rc 0, and the next
#       call silently respawned awk plus a bash `execute_coproc` warning.
#   M2  frexp inf | nan | 1e308 hung the calling shell forever.
#   M5  the unit's own `inf`/`nan` tokens were read by gawk as 0, so
#       `max inf 1` was 1, `sign inf` 0, `isZero inf` true.
#   M11 roundTo/simpleRoundTo emitted `-0`.
#   M14 non-numeric operands were silently accepted (`min abc 5` -> 5,
#       `sqrt abc` -> 0, `ceil 0x10` -> 0, `sin "1 2"` -> sin(1)).
#
# The shape of every domain row is: make the call, assert the FPC/IEEE answer,
# then assert the engine is still up AND the NEXT call is still correct. A dead
# engine is invisible in the failing call itself (it answered ''), so the
# liveness assertion is the one that actually catches M1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "M1EngineDomain" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
source "$MATH_DIR/math.sh"

math.feStart || { kt_test_start "engine available"; kt_test_fail "no awk on PATH"; return 1 2>/dev/null || exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# alive -> 0 when the co-process is up AND still answers correctly.
_alive() {
    math.feActive || return 1
    math.sin 0 || return 1
    [[ "$RESULT" == 0 ]] || return 1
    math.max 3 7 || return 1
    [[ "$RESULT" == 7 ]] || return 1
}

# _domain EXPECTED MEMBER ARGS...
#   Runs the member DIRECTLY (contract: RESULT, silent), compares RESULT to
#   EXPECTED and then checks the engine survived.
_domain() {
    local exp="$1"; shift
    local pid_before="$__MATH_FE_PID"
    kt_test_start "domain: math.$* -> $exp [M1/R11]"
    RESULT="<unset>"
    "math.$1" "${@:2}"
    local got="$RESULT"
    if [[ "$got" != "$exp" ]]; then
        kt_test_fail "math.$*: RESULT='$got' expected '$exp'"
        return
    fi
    if [[ "$__MATH_FE_PID" != "$pid_before" ]]; then
        kt_test_fail "math.$*: the engine was respawned (pid $pid_before -> $__MATH_FE_PID)"
        return
    fi
    if ! _alive; then
        kt_test_fail "math.$*: the engine died (feActive/next call wrong)"
        return
    fi
    kt_test_pass "$exp, engine alive"
}

# ---------------------------------------------------------------------------
# 1. Every division the awk prelude can be asked to perform by zero.
#    The 13 rows the reviewer reproduced, plus every other zero denominator
#    reachable from a public member.
# ---------------------------------------------------------------------------
_domain nan   fmod 5 0
_domain inf   cotan 0
_domain inf   cot 0
_domain inf   csc 0
_domain inf   cosecant 0
_domain inf   cscH 0
_domain inf   cotH 0
_domain nan   arcSec 0
_domain nan   arcCsc 0
_domain inf   arcSecH 0
_domain inf   arcCscH 0
_domain inf   arcCotH 1
_domain -inf  arcCotH -1
_domain inf   arcTanH 1
_domain -inf  arcTanH -1
_domain inf   arTanH 1
_domain inf   logN 1 5
_domain -inf  log10 0
_domain -inf  log2 0
_domain -inf  ln 0
_domain nan   ln -1
_domain nan   sqrt -1
_domain inf   exp 1000
_domain inf   power 0 -1
_domain inf   intPower 0 -1
_domain nan   roundTo 1 -400
_domain nan   simpleRoundTo 1.5 400
_domain nan   mean
_domain nan   variance
_domain nan   popnVariance
_domain nan   totalVariance
_domain nan   stdDev
_domain nan   popnStdDev
_domain 0     sum
_domain 0     sumOfSquares
_domain 0     norm
_domain -inf  payment 0 0 1 1
_domain -inf  numberOfPeriods 0 0 1 1
_domain -inf  presentValue -1 5 1 1
_domain inf   ldexp 1 1024
_domain -inf  lnXP1 -1
_domain nan   arcSin 2
_domain nan   arcCos 2
_domain nan   arcCosH 0.5

# ---------------------------------------------------------------------------
# 2. M5 — the unit's own inf / nan tokens, fed back into the members that
#    consume numbers. `math.infinity` is the token the unit publishes, so the
#    round trip publisher -> consumer must work.
# ---------------------------------------------------------------------------
kt_test_start "the published inf/nan tokens round-trip into the members [M5]"
ok=true; why=""
math.infinity; inf_tok="$RESULT"
math.negInfinity; ninf_tok="$RESULT"
math.nan; nan_tok="$RESULT"
_chk() {  # EXPECTED MEMBER ARGS...
    local e="$1"; shift
    RESULT="<unset>"; "math.$1" "${@:2}"
    [[ "$RESULT" == "$e" ]] || { ok=false; why+=" [math.$*='$RESULT' want '$e']"; }
}
_chk inf   max "$inf_tok" 1
_chk inf   max 1 "$inf_tok"
# min/max return the WINNING ARGUMENT verbatim (README), so an explicitly
# signed token comes back exactly as it was passed.
_chk +inf  max +inf 1
_chk -inf  min -inf 1
_chk -inf  min "$ninf_tok" 1
_chk 1     sign "$inf_tok"
_chk -1    sign "$ninf_tok"
_chk 0     sign "$nan_tok"
_chk false isZero "$inf_tok"
_chk false sameValue "$inf_tok" "$inf_tok"
_chk inf   ceil "$inf_tok"
_chk -inf  floor "$ninf_tok"
_chk nan   ceil "$nan_tok"
# FPC math.pp:2576 CompareValue = GreaterThanValue unless |a-b|<=delta or a<b,
# so an unordered (NaN) operand answers 1, not 0.
_chk 1     compareValue "$inf_tok" 1
_chk 1     compareValue "$nan_tok" 1
_chk -1    compareValue "$ninf_tok" 1
# FPC math.pp:2157 InRange = (v>=min) and (v<=max) -> NaN is FALSE.
_chk false inRange "$nan_tok" 0 1
_chk false inRange "$inf_tok" 0 1
_chk true  inRange 1 "$ninf_tok" "$inf_tok"
# FPC math.pp:2185 EnsureRange clamps with < / > only, so NaN passes through.
_chk nan   ensureRange "$nan_tok" 0 1
# FPC math.pp:2033 Max = if a>b then a else b -> an unordered pair yields b.
_chk 1     max "$nan_tok" 1
_chk 1     min "$nan_tok" 1
_chk inf   maxValue 1 2 "$inf_tok"
$ok && kt_test_pass "inf/nan tokens are values, not zeros" || kt_test_fail "$why"

kt_test_start "isNan / isInfinite recognise what the engine emits [M5]"
ok=true; why=""
math.sqrt -1;  s="$RESULT"; math.isNan "$s"        || { ok=false; why+=" isNan(sqrt -1)='$s'"; }
math.exp 1000; s="$RESULT"; math.isInfinite "$s"   || { ok=false; why+=" isInfinite(exp 1000)='$s'"; }
math.ln 0;     s="$RESULT"; math.isInfinite "$s"   || { ok=false; why+=" isInfinite(ln 0)='$s'"; }
[[ "$s" == "-inf" ]] || { ok=false; why+=" ln0='$s'"; }
$ok && kt_test_pass "engine tokens feed the predicates" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 3. M2 — frexp of inf / nan / 1e308 must ANSWER, not hang. Run in a child
#    shell under `timeout` so a regression cannot wedge the suite.
# ---------------------------------------------------------------------------
# One child shell for the whole family: `source math.sh` costs seconds under
# the 8-way runner, and a per-row child made the timeout measure the loader
# rather than frexp. The child is still under `timeout`, so a regression that
# spins forever fails the file instead of wedging the suite.
FREXP_ARGS=("+inf" "inf" "-inf" "nan" "1e308" "0" "-8" "0.75" "5e-324" "2.2250738585072014e-308")
FREXP_WANT=("inf 0" "inf 0" "-inf 0" "nan 0" "0.55626846462680035 1024" "0 0" \
            "-0.5 4" "0.75 0" "0.5 -1073" "0.5 -1021")
kt_test_start "frexp answers for every non-finite / extreme input, never hangs [M2]"
frexp_out="$(timeout 300 bash -c "source '$MATH_DIR/math.sh'
for a in ${FREXP_ARGS[*]@Q}; do
    math.frexp \"\$a\" || RESULT='<rc>'
    printf '%s|' \"\$RESULT\"
done" 2>&1)"; frexp_rc=$?
if (( frexp_rc == 124 )); then
    kt_test_fail "frexp HUNG (timeout) — partial output: '$frexp_out'"
else
    want=""
    for w in "${FREXP_WANT[@]}"; do want+="$w|"; done
    if [[ "$frexp_out" == "$want" ]]; then
        kt_test_pass "10 rows: $frexp_out"
    else
        kt_test_fail "got '$frexp_out' want '$want' (rc $frexp_rc)"
    fi
fi

# ---------------------------------------------------------------------------
# 4. M11 — no `-0` ever leaves the unit.
# ---------------------------------------------------------------------------
kt_test_start "negative zero is normalised to 0 [M11]"
ok=true; why=""
for row in "roundTo -0.4 0" "roundTo -0.004 -2" "simpleRoundTo -0.001" \
           "simpleRoundTo -0.4 0" "ceil -0.5" "floor -0.0" "fmod -1 1" \
           "sign -0.0" "degNormalize -0.0" "logN 0 5" "roundTo -0 0"; do
    read -r -a a <<< "$row"
    RESULT="<unset>"; "math.${a[0]}" "${a[@]:1}"
    case "$RESULT" in
        -0|-0.0|-0.00|-0e*|-0.0e*) ok=false; why+=" [math.$row -> '$RESULT']" ;;
    esac
done
$ok && kt_test_pass "no -0 on any rounding path" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 5. M14 — non-numeric operands are REJECTED (rc 1 + RESULT='' + no output),
#    not silently coerced to 0. One row per argument shape, applied to a
#    representative member of every arity family.
# ---------------------------------------------------------------------------
kt_test_start "garbage operands are rejected on every arity family [M14]"
ok=true; why=""
_reject() {  # MEMBER ARGS...
    local out rc
    out="$("math.$1" "${@:2}" 2>&1)"; rc=$?
    if (( rc == 0 )); then ok=false; why+=" [math.$* accepted -> '$out']"; return; fi
    [[ -z "$out" ]] || { ok=false; why+=" [math.$* printed '$out']"; }
    RESULT="<unset>"; "math.$1" "${@:2}" >/dev/null 2>&1
    [[ -z "$RESULT" ]] || { ok=false; why+=" [math.$* left RESULT='$RESULT']"; }
}
for g in "abc" "0x10" "1 2" "" "1.2.3" "-" "+-5" "1e" "\$(touch /dev/null)"; do
    _reject sqrt  "$g"
    _reject sin   "$g"
    _reject ceil  "$g"
    _reject floor "$g"
    _reject logN  2 "$g"
    _reject power "$g" 2
    _reject mean  1 "$g" 3
    _reject min   "$g" 5
    _reject max   5 "$g"
    _reject sign  "$g"
    _reject compareValue "$g" 1
    _reject inRange 1 "$g" 3
    _reject ensureRange 1 0 "$g"
    _reject isZero "$g"
    _reject sameValue "$g" 1
    _reject roundTo "$g" 0
    _reject futureValue 0.05 10 "$g" 0
    _reject frexp "$g"
    _reject ldexp 1 "$g"
    _reject randG "$g" 1
done
$ok && kt_test_pass "every arity family rejects every garbage shape" || kt_test_fail "$why"

kt_test_start "a newline inside an argument never reaches the engine [M3/M14]"
ok=true; why=""
_reject sin "$(printf '0\n2')"
_reject mean "$(printf '1\n2')" 3
_reject roundTo "$(printf '1\n2')" 0
# and the engine still answers correctly afterwards
_alive || { ok=false; why+=" engine desynchronised"; }
math.cos 0; [[ "$RESULT" == 1 ]] || { ok=false; why+=" cos 0 -> '$RESULT'"; }
$ok && kt_test_pass "rejected before the write, no desync" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 6. Structural: the awk prelude performs NO division outside the guarded
#    helper. This is the invariant behind M1 — a future op added with a bare
#    `/` reintroduces the whole class of defect, and no behavioural test would
#    see it until someone hits that particular zero.
# ---------------------------------------------------------------------------
kt_test_start "the awk prelude divides only through the guarded helper [M1/R11]"
mapfile -t __lines <<< "$__MATH_AWK_PROG"
bad=""
for l in "${__lines[@]}"; do
    # the one line that DEFINES the guarded divide is allowed to divide
    [[ "$l" == "function _dv("* ]] && continue
    [[ "$l" == *"/"* ]] && bad+="|$l"
done
if [[ -z "$bad" ]]; then
    kt_test_pass "no bare '/' outside _dv()"
else
    kt_test_fail "unguarded division(s):${bad:0:400}"
fi
