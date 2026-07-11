#!/bin/bash
# P1: InRange / EnsureRange / CompareValue / IfThen / IsZero / SameValue.
# Tier-A (pure-bash) for the range/compare ops; the engine handles the float-
# tolerance predicates (isZero decimals, sameValue, compareValue delta).
# New coverage (basis: FPC source) — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "RangeCompare" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# 1. InRange — closed interval [min,max]
# ---------------------------------------------------------------------------
kt_test_start "inRange: closed interval incl. boundaries, decimals"
ok=true
[[ "$(math.inRange 5 1 10)" == true ]]   || ok=false
[[ "$(math.inRange 0 1 10)" == false ]]  || ok=false
[[ "$(math.inRange 11 1 10)" == false ]] || ok=false
[[ "$(math.inRange 1 1 10)" == true ]]   || ok=false   # lower boundary inclusive
[[ "$(math.inRange 10 1 10)" == true ]]  || ok=false   # upper boundary inclusive
[[ "$(math.inRange 2.5 2.5 3)" == true ]] || ok=false
[[ "$(math.inRange -5 -10 -1)" == true ]] || ok=false
$ok && kt_test_pass "inRange: closed interval incl. boundaries, decimals" \
     || kt_test_fail "inRange wrong"

# ---------------------------------------------------------------------------
# 2. EnsureRange — clamp into [min,max]
# ---------------------------------------------------------------------------
kt_test_start "ensureRange: clamps below/above, passes through inside"
ok=true
[[ "$(math.ensureRange 5 1 10)" == 5 ]]   || ok=false
[[ "$(math.ensureRange -3 1 10)" == 1 ]]  || ok=false
[[ "$(math.ensureRange 99 1 10)" == 10 ]] || ok=false
[[ "$(math.ensureRange 2.5 0 3)" == 2.5 ]] || ok=false
[[ "$(math.ensureRange 3.5 0 3)" == 3 ]]  || ok=false
$ok && kt_test_pass "ensureRange: clamps below/above, passes through inside" \
     || kt_test_fail "ensureRange wrong"

# ---------------------------------------------------------------------------
# 3. CompareValue — -1 / 0 / 1
# ---------------------------------------------------------------------------
kt_test_start "compareValue: -1/0/1 (Less/Equal/Greater)"
ok=true
[[ "$(math.compareValue 3 5)" == -1 ]] || ok=false
[[ "$(math.compareValue 5 5)" == 0 ]]  || ok=false
[[ "$(math.compareValue 7 5)" == 1 ]]  || ok=false
[[ "$(math.compareValue -2.5 -2.4)" == -1 ]] || ok=false
[[ "$(math.compareValue 3.0 3)" == 0 ]] || ok=false
$ok && kt_test_pass "compareValue: -1/0/1 (Less/Equal/Greater)" \
     || kt_test_fail "compareValue wrong"

# ---------------------------------------------------------------------------
# 4. CompareValue with delta tolerance (engine)
# ---------------------------------------------------------------------------
kt_test_start "compareValue delta: |a-b|<=delta => 0 (equal within tolerance)"
math.feStart
ok=true
[[ "$(math.compareValue 1.0 1.0001 0.001)" == 0 ]]  || ok=false   # within tolerance
[[ "$(math.compareValue 1.0 1.01 0.001)" == -1 ]]   || ok=false   # outside -> Less
[[ "$(math.compareValue 5.0 4.99 0.001)" == 1 ]]    || ok=false   # outside -> Greater
[[ "$(math.compareValue 3 3 0)" == 0 ]]             || ok=false   # delta 0 -> exact
$ok && kt_test_pass "compareValue delta: |a-b|<=delta => 0 (equal within tolerance)" \
     || kt_test_fail "compareValue delta wrong"

# ---------------------------------------------------------------------------
# 5. IfThen — ternary
# ---------------------------------------------------------------------------
kt_test_start "ifThen: true/1 -> iftrue, else iffalse (default 0)"
ok=true
[[ "$(math.ifThen true A B)" == A ]]  || ok=false
[[ "$(math.ifThen false A B)" == B ]] || ok=false
[[ "$(math.ifThen 1 9 4)" == 9 ]]     || ok=false
[[ "$(math.ifThen 0 9 4)" == 4 ]]     || ok=false
[[ "$(math.ifThen false 9)" == 0 ]]   || ok=false   # default iffalse = 0
$ok && kt_test_pass "ifThen: true/1 -> iftrue, else iffalse (default 0)" \
     || kt_test_fail "ifThen wrong"

# ---------------------------------------------------------------------------
# 6. IsZero — |value| <= epsilon (default 1e-12)
# ---------------------------------------------------------------------------
kt_test_start "isZero: default 1e-12 resolution; integer fast path; explicit eps"
math.feStart
ok=true
[[ "$(math.isZero 0)" == true ]]        || ok=false   # integer fast path
[[ "$(math.isZero 5)" == false ]]       || ok=false
[[ "$(math.isZero 1e-15)" == true ]]    || ok=false   # below default resolution
[[ "$(math.isZero 1e-9)" == false ]]    || ok=false   # above default resolution
[[ "$(math.isZero 0.5)" == false ]]     || ok=false
[[ "$(math.isZero 0.05 0.1)" == true ]] || ok=false   # explicit epsilon
$ok && kt_test_pass "isZero: default 1e-12 resolution; integer fast path; explicit eps" \
     || kt_test_fail "isZero wrong"

kt_test_start "isZero integer fast path is fork-free (empty PATH)"
if o=$( PATH=''; math.isZero 0 ) && [[ "$o" == true ]] \
   && o2=$( PATH=''; math.isZero 7 ) && [[ "$o2" == false ]]; then
    kt_test_pass "isZero integer fast path is fork-free (empty PATH)"
else
    kt_test_fail "isZero integer path forked: [$o] [$o2]"
fi

# ---------------------------------------------------------------------------
# 7. SameValue — |a-b| <= epsilon (FPC default-epsilon formula)
# ---------------------------------------------------------------------------
kt_test_start "sameValue: default-epsilon equality and explicit epsilon"
math.feStart
ok=true
[[ "$(math.sameValue 1.0 1.0)" == true ]]        || ok=false
[[ "$(math.sameValue 1.0 1.5)" == false ]]       || ok=false
[[ "$(math.sameValue 100 100.00000000001)" == true ]] || ok=false  # diff 1e-11 << scaled eps 1e-10
[[ "$(math.sameValue 100 100.001)" == false ]]   || ok=false      # diff 1e-3 >> scaled eps
[[ "$(math.sameValue 1.0 1.1 0.2)" == true ]]    || ok=false      # explicit eps
[[ "$(math.sameValue 1.0 1.5 0.2)" == false ]]   || ok=false
$ok && kt_test_pass "sameValue: default-epsilon equality and explicit epsilon" \
     || kt_test_fail "sameValue wrong"

math._fe_stop 2>/dev/null
