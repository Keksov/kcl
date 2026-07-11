#!/bin/bash
# P1: Min/Max (2-arg + array reducers) and Sign. Tier-A pure-bash on plain
# integers/decimals (zero-fork); engine only for exotic-notation operands.
# All new coverage (basis: FPC source semantics) — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "MinMaxSign" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# 1. Min / Max (two operands): integers, decimals, ties, negatives
# ---------------------------------------------------------------------------
kt_test_start "min/max (2-arg): integers, decimals, ties, negatives"
ok=true
[[ "$(math.min 3 7)" == 3 ]]        || ok=false
[[ "$(math.min 7 3)" == 3 ]]        || ok=false
[[ "$(math.max 3 7)" == 7 ]]        || ok=false
[[ "$(math.min -2.5 -2.4)" == -2.5 ]] || ok=false
[[ "$(math.max -2.5 -2.4)" == -2.4 ]] || ok=false
[[ "$(math.min 2.5 2.45)" == 2.45 ]] || ok=false
# FPC tie rule: Min(a,b)=b and Max(a,b)=b when a==b -> the 2nd token wins
[[ "$(math.min 1.5 1.50)" == 1.50 ]] || ok=false
[[ "$(math.max 1.5 1.50)" == 1.50 ]] || ok=false
$ok && kt_test_pass "min/max (2-arg): integers, decimals, ties, negatives" \
     || kt_test_fail "min/max wrong"

# ---------------------------------------------------------------------------
# 2. MinValue / MaxValue over the argument list
# ---------------------------------------------------------------------------
kt_test_start "minValue/maxValue over an argument list (verbatim winner)"
ok=true
[[ "$(math.minValue 5 2 8 1 9)" == 1 ]] || ok=false
[[ "$(math.maxValue 5 2 8 1 9)" == 9 ]] || ok=false
[[ "$(math.minValue 3.5 3.05 3.4)" == 3.05 ]] || ok=false
[[ "$(math.maxValue 3.5 3.05 3.4)" == 3.5 ]]  || ok=false
[[ "$(math.minValue 42)" == 42 ]] || ok=false           # single element
[[ "$(math.maxValue -7 -3 -9)" == -3 ]] || ok=false
$ok && kt_test_pass "minValue/maxValue over an argument list (verbatim winner)" \
     || kt_test_fail "minValue/maxValue wrong"

# ---------------------------------------------------------------------------
# 3. MinIntValue / MaxIntValue (integer arrays)
# ---------------------------------------------------------------------------
kt_test_start "minIntValue/maxIntValue (integer arrays, negatives)"
if [[ "$(math.minIntValue -3 -10 5)" == -10 && "$(math.maxIntValue -3 -10 5)" == 5 \
   && "$(math.minIntValue 100)" == 100 && "$(math.maxIntValue 0 0 0)" == 0 ]]; then
    kt_test_pass "minIntValue/maxIntValue (integer arrays, negatives)"
else
    kt_test_fail "minIntValue/maxIntValue wrong"
fi

# ---------------------------------------------------------------------------
# 4. Sign: -1 / 0 / 1  (ord(A>0)-ord(A<0))
# ---------------------------------------------------------------------------
kt_test_start "sign returns -1/0/1 incl. decimals and -0"
ok=true
[[ "$(math.sign -5)" == -1 ]]   || ok=false
[[ "$(math.sign 0)" == 0 ]]     || ok=false
[[ "$(math.sign 42)" == 1 ]]    || ok=false
[[ "$(math.sign 3.14)" == 1 ]]  || ok=false
[[ "$(math.sign -0.001)" == -1 ]] || ok=false
[[ "$(math.sign -0.0)" == 0 ]]  || ok=false
[[ "$(math.sign +0)" == 0 ]]    || ok=false
$ok && kt_test_pass "sign returns -1/0/1 incl. decimals and -0" \
     || kt_test_fail "sign wrong"

# ---------------------------------------------------------------------------
# 5. Zero-fork: plain-number min/max/sign/minIntValue work with empty PATH
# ---------------------------------------------------------------------------
kt_test_start "Tier-A min/max/sign make zero forks (empty PATH)"
if o1=$( PATH=''; math.min -2.5 -2.4 ) && [[ "$o1" == -2.5 ]] \
   && o2=$( PATH=''; math.sign -3.14 ) && [[ "$o2" == -1 ]] \
   && o3=$( PATH=''; math.maxValue 1 9 4 ) && [[ "$o3" == 9 ]] \
   && o4=$( PATH=''; math.minIntValue 5 -2 ) && [[ "$o4" == -2 ]]; then
    kt_test_pass "Tier-A min/max/sign make zero forks (empty PATH)"
else
    kt_test_fail "a Tier-A op forked: [$o1] [$o2] [$o3] [$o4]"
fi

# ---------------------------------------------------------------------------
# 6. Exotic operands (exponential notation) route through the engine
# ---------------------------------------------------------------------------
kt_test_start "exotic operands (exponent) compare correctly via the engine"
math.feStart
if [[ "$(math.min 1e-9 2e-9)" == 1e-9 && "$(math.max 1e-9 2e-9)" == 2e-9 \
   && "$(math.sign 1e-30)" == 1 && "$(math.sign -4e5)" == -1 ]]; then
    kt_test_pass "exotic operands (exponent) compare correctly via the engine"
else
    kt_test_fail "engine-backed exotic compare wrong"
fi
math._fe_stop 2>/dev/null
