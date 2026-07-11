#!/bin/bash
# P4: circular trig + inverse trig (engine). kt_assert_near throughout.
# pi fractions given as exact Double literals (avoid awk %.6g truncation).
# New coverage — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Trig" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart
HALFPI=1.5707963267948966      # pi/2
QUARTPI=0.7853981633974483     # pi/4
PI6=0.5235987755982988         # pi/6
PI3=1.0471975511965976         # pi/3

# ---------------------------------------------------------------------------
# 1. tan / cotan / cot
# ---------------------------------------------------------------------------
kt_test_start "tan/cotan/cot at pi/4 = 1"
if kt_assert_near 1 "$(math.tan $QUARTPI)" 1e-12 && kt_assert_near 1 "$(math.cotan $QUARTPI)" 1e-12 \
   && kt_assert_near 1 "$(math.cot $QUARTPI)" 1e-12; then
    kt_test_pass "tan/cotan/cot at pi/4 = 1"
else
    kt_test_fail "tan/cotan/cot wrong"
fi

# ---------------------------------------------------------------------------
# 2. sec / csc / secant / cosecant
# ---------------------------------------------------------------------------
kt_test_start "sec/csc/secant/cosecant reciprocals"
ok=true
kt_assert_near 1 "$(math.sec 0)" || ok=false          # 1/cos(0)
kt_assert_near 1 "$(math.csc $HALFPI)" || ok=false     # 1/sin(pi/2)
kt_assert_near 1 "$(math.secant 0)" || ok=false
kt_assert_near 1 "$(math.cosecant $HALFPI)" || ok=false
kt_assert_near 2 "$(math.sec $PI3)" || ok=false        # 1/cos(pi/3)=1/0.5=2
$ok && kt_test_pass "sec/csc/secant/cosecant reciprocals" || kt_test_fail "sec/csc wrong"

# ---------------------------------------------------------------------------
# 3. sinCos -> two fields
# ---------------------------------------------------------------------------
kt_test_start "sinCos echoes sin and cos as two fields"
read -r s c <<< "$(math.sinCos 1.0)"
if kt_assert_near 0.8414709848078965 "$s" && kt_assert_near 0.5403023058681398 "$c"; then
    kt_test_pass "sinCos echoes sin and cos as two fields"
else
    kt_test_fail "sinCos = [$s|$c]"
fi

# ---------------------------------------------------------------------------
# 4. arcSin / arcCos  (numerically-stable sqrt((1-x)(1+x)) form)
# ---------------------------------------------------------------------------
kt_test_start "arcSin/arcCos principal values"
ok=true
kt_assert_near "$HALFPI" "$(math.arcSin 1)" || ok=false
kt_assert_near "$PI6" "$(math.arcSin 0.5)" || ok=false
kt_assert_near 0 "$(math.arcSin 0)" || ok=false
kt_assert_near "$HALFPI" "$(math.arcCos 0)" || ok=false
kt_assert_near 0 "$(math.arcCos 1)" || ok=false
kt_assert_near "$PI3" "$(math.arcCos 0.5)" || ok=false
$ok && kt_test_pass "arcSin/arcCos principal values" || kt_test_fail "arcSin/arcCos wrong"

# ---------------------------------------------------------------------------
# 5. arcTan / arcTan2 (quadrant-aware)
# ---------------------------------------------------------------------------
kt_test_start "arcTan/arcTan2 incl. quadrants"
ok=true
kt_assert_near "$QUARTPI" "$(math.arcTan 1)" || ok=false
kt_assert_near "$QUARTPI" "$(math.arcTan2 1 1)" || ok=false
kt_assert_near "$HALFPI" "$(math.arcTan2 1 0)" || ok=false           # +y axis
kt_assert_near 2.356194490192345 "$(math.arcTan2 1 -1)" || ok=false  # 3pi/4
kt_assert_near -2.356194490192345 "$(math.arcTan2 -1 -1)" || ok=false # -3pi/4
$ok && kt_test_pass "arcTan/arcTan2 incl. quadrants" || kt_test_fail "arcTan2 wrong"

# ---------------------------------------------------------------------------
# 6. Convenience sin/cos + identities
# ---------------------------------------------------------------------------
kt_test_start "sin/cos convenience + identity tan=sin/cos"
ok=true
kt_assert_near 0 "$(math.sin 0)" || ok=false
kt_assert_near 1 "$(math.cos 0)" || ok=false
kt_assert_near 1 "$(math.sin $HALFPI)" || ok=false
# tan(1.2) == sin(1.2)/cos(1.2)
ratio=$(awk -v s="$(math.sin 1.2)" -v c="$(math.cos 1.2)" 'BEGIN{printf "%.17g", s/c}')
kt_assert_near "$ratio" "$(math.tan 1.2)" 1e-12 || ok=false
$ok && kt_test_pass "sin/cos convenience + identity tan=sin/cos" || kt_test_fail "sin/cos/identity wrong"

math._fe_stop 2>/dev/null
