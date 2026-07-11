#!/bin/bash
# P5: logarithms, exponentials, powers, hypot, frexp/ldexp (engine).
# Highlights: LnXP1/ExpM1 accuracy near 0, overflow-safe Hypot, frexp/ldexp
# round-trip. New coverage — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "LogExp" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart

# ---------------------------------------------------------------------------
# 1. Logarithms
# ---------------------------------------------------------------------------
kt_test_start "log10 / log2 / logN"
ok=true
kt_assert_near 3 "$(math.log10 1000)" 1e-12 || ok=false
kt_assert_near 10 "$(math.log2 1024)" || ok=false
kt_assert_near 3 "$(math.logN 2 8)" || ok=false        # log base 2 of 8
kt_assert_near 2 "$(math.logN 10 100)" 1e-12 || ok=false
kt_assert_near 4 "$(math.logN 3 81)" 1e-12 || ok=false
$ok && kt_test_pass "log10 / log2 / logN" || kt_test_fail "log wrong"

# ---------------------------------------------------------------------------
# 2. Convenience ln / exp / sqrt
# ---------------------------------------------------------------------------
kt_test_start "convenience ln / exp / sqrt"
ok=true
kt_assert_near 1 "$(math.ln "$(math.e)")" || ok=false
kt_assert_near 2.718281828459045 "$(math.exp 1)" || ok=false
kt_assert_near 1.4142135623730951 "$(math.sqrt 2)" || ok=false
kt_assert_near 5 "$(math.sqrt 25)" || ok=false
$ok && kt_test_pass "convenience ln / exp / sqrt" || kt_test_fail "ln/exp/sqrt wrong"

# ---------------------------------------------------------------------------
# 3. Power (integer exponent exact, fractional, special cases)
# ---------------------------------------------------------------------------
kt_test_start "power: integer/fractional exponents + special cases"
ok=true
kt_assert_near 1024 "$(math.power 2 10)" || ok=false           # integer -> intPower (exact)
kt_assert_near 0.25 "$(math.power 2 -2)" || ok=false
kt_assert_near 2 "$(math.power 4 0.5)" || ok=false             # sqrt via exp(0.5*ln)
kt_assert_near 1.4142135623730951 "$(math.power 2 0.5)" 1e-12 || ok=false
[[ "$(math.power 0 5)" == 0 ]] || ok=false                     # base 0, exp>0
[[ "$(math.power 5 0)" == 1 ]] || ok=false                     # exp 0
kt_assert_near 1000 "$(math.power 10 3)" || ok=false
$ok && kt_test_pass "power: integer/fractional exponents + special cases" || kt_test_fail "power wrong"

# ---------------------------------------------------------------------------
# 4. Hypot (overflow-safe)
# ---------------------------------------------------------------------------
kt_test_start "hypot: 3-4-5, 5-12-13, overflow-safe for huge args"
ok=true
kt_assert_near 5 "$(math.hypot 3 4)" || ok=false
kt_assert_near 13 "$(math.hypot 5 12)" || ok=false
kt_assert_near 1.4142135623730951e+200 "$(math.hypot 1e200 1e200)" 1e-12 || ok=false  # no overflow
$ok && kt_test_pass "hypot: 3-4-5, 5-12-13, overflow-safe for huge args" || kt_test_fail "hypot wrong"

# ---------------------------------------------------------------------------
# 5. LnXP1 / ExpM1 accuracy near zero
# ---------------------------------------------------------------------------
kt_test_start "lnXP1 / expM1 accurate near zero (vs naive ln(1+x)/exp(x)-1)"
ok=true
# away from zero they equal the plain functions
kt_assert_near 1.0986122886681098 "$(math.lnXP1 2)" || ok=false   # ln(3)
kt_assert_near 6.38905609893065 "$(math.expM1 2)" || ok=false     # e^2-1
# near zero: accurate value of ln(1+1e-9) is 9.999999995e-10 (naive gives 1.0000000822e-9)
kt_assert_near 9.999999995e-10 "$(math.lnXP1 1e-9)" 1e-9 || ok=false
kt_assert_near 1.0000000005e-9 "$(math.expM1 1e-9)" 1e-9 || ok=false
$ok && kt_test_pass "lnXP1 / expM1 accurate near zero (vs naive ln(1+x)/exp(x)-1)" || kt_test_fail "lnXP1/expM1 wrong"

# ---------------------------------------------------------------------------
# 6. Frexp / Ldexp
# ---------------------------------------------------------------------------
kt_test_start "frexp: mantissa in [0.5,1), x = mantissa * 2^exponent"
ok=true
[[ "$(math.frexp 8)" == "0.5 4" ]]   || ok=false
[[ "$(math.frexp 0.5)" == "0.5 0" ]] || ok=false
[[ "$(math.frexp 1)" == "0.5 1" ]]   || ok=false
[[ "$(math.frexp 6)" == "0.75 3" ]]  || ok=false
[[ "$(math.frexp -8)" == "-0.5 4" ]] || ok=false
[[ "$(math.frexp 0)" == "0 0" ]]     || ok=false
# reconstruct: mantissa*2^exponent == x
for x in 13.7 0.001 123456 -42.5; do
    read -r m e <<< "$(math.frexp "$x")"
    kt_assert_near "$x" "$(math.ldexp "$m" "$e")" 1e-12 || { ok=false; break; }
    # mantissa magnitude in [0.5,1)
    mag=${m#-}
    awk -v v="$mag" 'BEGIN{exit !(v>=0.5 && v<1)}' || { ok=false; break; }
done
$ok && kt_test_pass "frexp: mantissa in [0.5,1), x = mantissa * 2^exponent" || kt_test_fail "frexp wrong (x=$x m=$m e=$e)"

kt_test_start "ldexp: x * 2^p"
if kt_assert_near 8 "$(math.ldexp 0.5 4)" && kt_assert_near 1024 "$(math.ldexp 1 10)" \
   && kt_assert_near 0.75 "$(math.ldexp 0.75 0)" && kt_assert_near 0.375 "$(math.ldexp 0.75 -1)"; then
    kt_test_pass "ldexp: x * 2^p"
else
    kt_test_fail "ldexp wrong"
fi

math._fe_stop 2>/dev/null
