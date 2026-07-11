#!/bin/bash
# P3: angle conversions (deg/rad/grad/cycle) + DegNormalize. All Tier-B engine
# results -> kt_assert_near. New coverage — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Angles" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart
PI=$(math.pi)

# ---------------------------------------------------------------------------
# 1. Degrees <-> radians
# ---------------------------------------------------------------------------
kt_test_start "deg<->rad: degToRad(180)=pi, radToDeg(pi)=180"
if kt_assert_near "$PI" "$(math.degToRad 180)" && kt_assert_near 180 "$(math.radToDeg "$PI")" \
   && kt_assert_near 1.5707963267948966 "$(math.degToRad 90)"; then
    kt_test_pass "deg<->rad: degToRad(180)=pi, radToDeg(pi)=180"
else
    kt_test_fail "deg<->rad wrong"
fi

# ---------------------------------------------------------------------------
# 2. Grads <-> radians
# ---------------------------------------------------------------------------
kt_test_start "grad<->rad: gradToRad(200)=pi, radToGrad(pi)=200"
if kt_assert_near "$PI" "$(math.gradToRad 200)" && kt_assert_near 200 "$(math.radToGrad "$PI")"; then
    kt_test_pass "grad<->rad: gradToRad(200)=pi, radToGrad(pi)=200"
else
    kt_test_fail "grad<->rad wrong"
fi

# ---------------------------------------------------------------------------
# 3. Degrees <-> grads  (rational)
# ---------------------------------------------------------------------------
kt_test_start "deg<->grad: degToGrad(180)=200, gradToDeg(200)=180"
if kt_assert_near 200 "$(math.degToGrad 180)" && kt_assert_near 180 "$(math.gradToDeg 200)" \
   && kt_assert_near 100 "$(math.degToGrad 90)"; then
    kt_test_pass "deg<->grad: degToGrad(180)=200, gradToDeg(200)=180"
else
    kt_test_fail "deg<->grad wrong"
fi

# ---------------------------------------------------------------------------
# 4. Cycles <-> deg / grad / rad
# ---------------------------------------------------------------------------
kt_test_start "cycle conversions: 1 cycle = 360 deg = 400 grad = 2pi rad"
ok=true
kt_assert_near 360 "$(math.cycleToDeg 1)"  || ok=false
kt_assert_near 1 "$(math.degToCycle 360)"  || ok=false
kt_assert_near 400 "$(math.cycleToGrad 1)" || ok=false
kt_assert_near 1 "$(math.gradToCycle 400)" || ok=false
tworpi=$(awk -v p="$PI" 'BEGIN{printf "%.17g", 2*p}')
kt_assert_near "$tworpi" "$(math.cycleToRad 1)" || ok=false
kt_assert_near 1 "$(math.radToCycle "$(math.cycleToRad 1)")" || ok=false
$ok && kt_test_pass "cycle conversions: 1 cycle = 360 deg = 400 grad = 2pi rad" \
     || kt_test_fail "cycle conversions wrong"

# ---------------------------------------------------------------------------
# 5. DegNormalize — wrap into [0,360)
# ---------------------------------------------------------------------------
kt_test_start "degNormalize wraps into [0,360)"
ok=true
kt_assert_near 270 "$(math.degNormalize -90)"  || ok=false
kt_assert_near 90 "$(math.degNormalize 450)"   || ok=false
kt_assert_near 0 "$(math.degNormalize 360)"    || ok=false
kt_assert_near 0 "$(math.degNormalize 720)"    || ok=false
kt_assert_near 359.5 "$(math.degNormalize -0.5)" || ok=false
kt_assert_near 45 "$(math.degNormalize 45)"    || ok=false
kt_assert_near 350 "$(math.degNormalize -730)" || ok=false   # -730 + 3*360 = 350
$ok && kt_test_pass "degNormalize wraps into [0,360)" \
     || kt_test_fail "degNormalize wrong"

# ---------------------------------------------------------------------------
# 6. Round-trips
# ---------------------------------------------------------------------------
kt_test_start "round-trips: deg->rad->deg, deg->grad->deg, deg->cycle->deg"
ok=true
kt_assert_near 37 "$(math.radToDeg "$(math.degToRad 37)")" || ok=false
kt_assert_near 37 "$(math.gradToDeg "$(math.degToGrad 37)")" || ok=false
kt_assert_near 137.5 "$(math.cycleToDeg "$(math.degToCycle 137.5)")" || ok=false
$ok && kt_test_pass "round-trips: deg->rad->deg, deg->grad->deg, deg->cycle->deg" \
     || kt_test_fail "round-trip wrong"

math._fe_stop 2>/dev/null
