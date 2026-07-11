#!/bin/bash
# P4: hyperbolic + area (inverse hyperbolic) functions (engine). Includes the
# Delphi (arc*H) and FK (ar*H) spellings, robust large-x tanh, and round-trips.
# New coverage — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Hyperbolic" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart
HALFPI=1.5707963267948966
QUARTPI=0.7853981633974483
PI6=0.5235987755982988
PI3=1.0471975511965976

# ---------------------------------------------------------------------------
# 1. cosh / sinh / tanh
# ---------------------------------------------------------------------------
kt_test_start "cosh/sinh/tanh base values"
ok=true
kt_assert_near 1 "$(math.cosh 0)" || ok=false
kt_assert_near 0 "$(math.sinh 0)" || ok=false
kt_assert_near 0 "$(math.tanh 0)" || ok=false
kt_assert_near 1.5430806348152437 "$(math.cosh 1)" || ok=false
kt_assert_near 1.1752011936438014 "$(math.sinh 1)" || ok=false
kt_assert_near 0.7615941559557649 "$(math.tanh 1)" || ok=false
$ok && kt_test_pass "cosh/sinh/tanh base values" || kt_test_fail "cosh/sinh/tanh wrong"

kt_test_start "tanh robust for large |x| (-> +/-1, no overflow)"
if kt_assert_near 1 "$(math.tanh 100)" && kt_assert_near -1 "$(math.tanh -100)" \
   && kt_assert_near 1 "$(math.tanh 750)"; then
    kt_test_pass "tanh robust for large |x| (-> +/-1, no overflow)"
else
    kt_test_fail "tanh large-x not robust"
fi

# ---------------------------------------------------------------------------
# 2. secH / cscH / cotH
# ---------------------------------------------------------------------------
kt_test_start "secH/cscH/cotH reciprocals of cosh/sinh/tanh"
ok=true
kt_assert_near 1 "$(math.secH 0)" || ok=false                 # 1/cosh(0)
kt_assert_near 0.8509181282393216 "$(math.cscH 1)" || ok=false  # 1/sinh(1)
kt_assert_near 1.3130352854993312 "$(math.cotH 1)" || ok=false  # cosh(1)/sinh(1)
$ok && kt_test_pass "secH/cscH/cotH reciprocals of cosh/sinh/tanh" || kt_test_fail "secH/cscH/cotH wrong"

# ---------------------------------------------------------------------------
# 3. cosh^2 - sinh^2 = 1 identity
# ---------------------------------------------------------------------------
kt_test_start "identity: cosh^2(x) - sinh^2(x) = 1"
val=$(awk -v c="$(math.cosh 1.7)" -v s="$(math.sinh 1.7)" 'BEGIN{printf "%.17g", c*c - s*s}')
kt_assert_near 1 "$val" 1e-10 && kt_test_pass "identity: cosh^2(x) - sinh^2(x) = 1" \
    || kt_test_fail "cosh^2-sinh^2 = $val (want 1)"

# ---------------------------------------------------------------------------
# 4. Area functions (inverse hyperbolic) + both spellings
# ---------------------------------------------------------------------------
kt_test_start "arcSinH/arcCosH/arcTanH values + ar*H spellings agree"
ok=true
kt_assert_near 0 "$(math.arcSinH 0)" || ok=false
kt_assert_near 0.8813735870195429 "$(math.arcSinH 1)" || ok=false
kt_assert_near 0 "$(math.arcCosH 1)" || ok=false
kt_assert_near 1.3169578969248166 "$(math.arcCosH 2)" || ok=false
kt_assert_near 0.5493061443340548 "$(math.arcTanH 0.5)" || ok=false
# FK spellings must equal the Delphi ones
[[ "$(math.arSinH 1.5)" == "$(math.arcSinH 1.5)" ]] || ok=false
[[ "$(math.arCosH 2.5)" == "$(math.arcCosH 2.5)" ]] || ok=false
[[ "$(math.arTanH 0.3)" == "$(math.arcTanH 0.3)" ]] || ok=false
$ok && kt_test_pass "arcSinH/arcCosH/arcTanH values + ar*H spellings agree" \
     || kt_test_fail "area functions wrong"

# ---------------------------------------------------------------------------
# 5. arcSec / arcCsc / arcCot
# ---------------------------------------------------------------------------
kt_test_start "arcSec/arcCsc/arcCot (incl. arcCot(0)=pi/2)"
ok=true
kt_assert_near "$PI3" "$(math.arcSec 2)" || ok=false     # arccos(1/2)=pi/3
kt_assert_near "$PI6" "$(math.arcCsc 2)" || ok=false     # arcsin(1/2)=pi/6
kt_assert_near "$HALFPI" "$(math.arcCot 0)" || ok=false  # special case
kt_assert_near "$QUARTPI" "$(math.arcCot 1)" || ok=false # arctan(1)=pi/4
$ok && kt_test_pass "arcSec/arcCsc/arcCot (incl. arcCot(0)=pi/2)" || kt_test_fail "arcSec/arcCsc/arcCot wrong"

# ---------------------------------------------------------------------------
# 6. arcSecH / arcCscH / arcCotH + round-trips
# ---------------------------------------------------------------------------
kt_test_start "arcSecH/arcCscH/arcCotH + hyperbolic round-trips"
ok=true
kt_assert_near 1.3169578969248166 "$(math.arcSecH 0.5)" || ok=false  # arccosh(2)
kt_assert_near 0.8813735870195429 "$(math.arcCscH 1)" || ok=false     # arcsinh(1)
kt_assert_near 0.5493061443340548 "$(math.arcCotH 2)" || ok=false     # arctanh(1/2)
# round-trips
kt_assert_near 2 "$(math.arcSinH "$(math.sinh 2)")" || ok=false
kt_assert_near 1.5 "$(math.arcCosH "$(math.cosh 1.5)")" || ok=false
kt_assert_near 0.4 "$(math.arcTanH "$(math.tanh 0.4)")" || ok=false
$ok && kt_test_pass "arcSecH/arcCscH/arcCotH + hyperbolic round-trips" \
     || kt_test_fail "arcSecH/arcCscH/arcCotH/roundtrips wrong"

math._fe_stop 2>/dev/null
