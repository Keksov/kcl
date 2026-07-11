#!/bin/bash
# P2: rounding & number conversion. Ceil/Floor/DivMod/integer-IntPower are
# Tier-A exact (string compare); RoundTo/SimpleRoundTo/FMod/float-IntPower are
# Tier-B engine results (kt_assert_near). New coverage — see TEST_COVERAGE_NOTES.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Rounding" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# 1. Ceil / Floor (Trunc(x)+ord(Frac>0) / Trunc(x)-ord(Frac<0))
# ---------------------------------------------------------------------------
kt_test_start "ceil: toward +inf incl. negatives and exact integers"
if [[ "$(math.ceil 2.1)" == 3 && "$(math.ceil 2.9)" == 3 && "$(math.ceil -2.1)" == -2 \
   && "$(math.ceil 3)" == 3 && "$(math.ceil -2.0)" == -2 && "$(math.ceil 0.001)" == 1 ]]; then
    kt_test_pass "ceil: toward +inf incl. negatives and exact integers"
else
    kt_test_fail "ceil wrong"
fi

kt_test_start "floor: toward -inf incl. negatives and exact integers"
if [[ "$(math.floor 2.9)" == 2 && "$(math.floor 2.1)" == 2 && "$(math.floor -2.1)" == -3 \
   && "$(math.floor 3)" == 3 && "$(math.floor -0.001)" == -1 ]]; then
    kt_test_pass "floor: toward -inf incl. negatives and exact integers"
else
    kt_test_fail "floor wrong"
fi

kt_test_start "ceil64/floor64 mirror ceil/floor"
if [[ "$(math.ceil64 -5.5)" == -5 && "$(math.floor64 -5.5)" == -6 \
   && "$(math.ceil64 5.5)" == 6 && "$(math.floor64 5.5)" == 5 ]]; then
    kt_test_pass "ceil64/floor64 mirror ceil/floor"
else
    kt_test_fail "ceil64/floor64 wrong"
fi

# ---------------------------------------------------------------------------
# 2. DivMod (truncation toward zero; remainder sign = dividend sign)
# ---------------------------------------------------------------------------
kt_test_start "divMod: quotient + remainder, negative-dividend semantics"
ok=true
[[ "$(math.divMod 17 5)" == "3 2" ]]    || ok=false
[[ "$(math.divMod -10 3)" == "-3 -1" ]] || ok=false
[[ "$(math.divMod -10 5)" == "-2 0" ]]  || ok=false
[[ "$(math.divMod 20 10)" == "2 0" ]]   || ok=false
math.divMod 5 0 && ok=false             # division by zero -> status 1, no output
$ok && kt_test_pass "divMod: quotient + remainder, negative-dividend semantics" \
     || kt_test_fail "divMod wrong"

# ---------------------------------------------------------------------------
# 3. RoundTo — banker's rounding (half to even)
# ---------------------------------------------------------------------------
kt_test_start "roundTo: banker's rounding (ties to even)"
math.feStart
ok=true
kt_assert_near 2 "$(math.roundTo 2.5 0)" || ok=false   # 2.5 -> 2 (even)
kt_assert_near 4 "$(math.roundTo 3.5 0)" || ok=false   # 3.5 -> 4 (even)
kt_assert_near 0 "$(math.roundTo 0.5 0)" || ok=false   # 0.5 -> 0 (even)
kt_assert_near 2 "$(math.roundTo 1.5 0)" || ok=false   # 1.5 -> 2 (even)
kt_assert_near -2 "$(math.roundTo -2.5 0)" || ok=false
kt_assert_near 3.14 "$(math.roundTo 3.14159 -2)" 1e-9 || ok=false
$ok && kt_test_pass "roundTo: banker's rounding (ties to even)" \
     || kt_test_fail "roundTo wrong"

# ---------------------------------------------------------------------------
# 4. SimpleRoundTo — arithmetic rounding (half away from zero), default -2
# ---------------------------------------------------------------------------
kt_test_start "simpleRoundTo: arithmetic rounding (half away from zero)"
ok=true
kt_assert_near 3 "$(math.simpleRoundTo 2.5 0)"  || ok=false   # away from zero
kt_assert_near -3 "$(math.simpleRoundTo -2.5 0)" || ok=false
kt_assert_near 1 "$(math.simpleRoundTo 0.5 0)"  || ok=false
kt_assert_near 1.23 "$(math.simpleRoundTo 1.2345)" 1e-9 || ok=false   # default digits=-2
kt_assert_near 3.14 "$(math.simpleRoundTo 3.14159 -2)" 1e-9 || ok=false
$ok && kt_test_pass "simpleRoundTo: arithmetic rounding (half away from zero)" \
     || kt_test_fail "simpleRoundTo wrong"

# ---------------------------------------------------------------------------
# 5. FMod — floating-point modulo a - b*Int(a/b)
# ---------------------------------------------------------------------------
kt_test_start "fmod: a - b*Int(a/b), remainder sign follows dividend"
ok=true
kt_assert_near 1.3 "$(math.fmod 5.3 2)" 1e-12 || ok=false
kt_assert_near -1.3 "$(math.fmod -5.3 2)" 1e-12 || ok=false
kt_assert_near 0.5 "$(math.fmod 5.5 2.5)" || ok=false
$ok && kt_test_pass "fmod: a - b*Int(a/b), remainder sign follows dividend" \
     || kt_test_fail "fmod wrong"

# ---------------------------------------------------------------------------
# 6. IntPower — exponentiation by squaring
# ---------------------------------------------------------------------------
kt_test_start "intPower: integer exact + float/negative-exp via engine"
ok=true
[[ "$(math.intPower 2 10)" == 1024 ]] || ok=false     # integer exact
[[ "$(math.intPower -2 3)" == -8 ]]   || ok=false
[[ "$(math.intPower 5 0)" == 1 ]]     || ok=false
kt_assert_near 3.375 "$(math.intPower 1.5 3)" || ok=false   # float base -> engine
kt_assert_near 0.25 "$(math.intPower 2 -2)"   || ok=false   # negative exp -> engine
$ok && kt_test_pass "intPower: integer exact + float/negative-exp via engine" \
     || kt_test_fail "intPower wrong"

# ---------------------------------------------------------------------------
# 7. Zero-fork: Tier-A ceil/floor/divMod/integer-intPower (empty PATH)
# ---------------------------------------------------------------------------
kt_test_start "Tier-A ceil/floor/divMod/intPower(int) make zero forks (empty PATH)"
if o1=$( PATH=''; math.ceil -2.1 ) && [[ "$o1" == -2 ]] \
   && o2=$( PATH=''; math.floor -2.1 ) && [[ "$o2" == -3 ]] \
   && o3=$( PATH=''; math.divMod -10 3 ) && [[ "$o3" == "-3 -1" ]] \
   && o4=$( PATH=''; math.intPower 2 10 ) && [[ "$o4" == 1024 ]]; then
    kt_test_pass "Tier-A ceil/floor/divMod/intPower(int) make zero forks (empty PATH)"
else
    kt_test_fail "a Tier-A op forked: [$o1] [$o2] [$o3] [$o4]"
fi

math._fe_stop 2>/dev/null
