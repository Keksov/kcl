#!/bin/bash
# P7: financial (annuity) functions (engine). APaymentTime is a 0/1 flag.
# Verified by solve-for-x round-trips (payment<->presentValue, interestRate,
# numberOfPeriods) + rate=0 edge + start-of-period. New coverage — see NOTES.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Financial" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart

# ---------------------------------------------------------------------------
# 1. FutureValue / Payment (worked annuity: 5%, 10 periods)
# ---------------------------------------------------------------------------
kt_test_start "futureValue / payment on a 5%/10-period annuity"
ok=true
kt_assert_near 1257.789253554883 "$(math.futureValue 0.05 10 -100 0)" 1e-9 || ok=false
kt_assert_near -129.5045749654568 "$(math.payment 0.05 10 1000 0)" 1e-9 || ok=false
$ok && kt_test_pass "futureValue / payment on a 5%/10-period annuity" || kt_test_fail "fv/payment wrong"

# ---------------------------------------------------------------------------
# 2. Solve-for-x round-trips (the 5 functions are mutually consistent)
# ---------------------------------------------------------------------------
kt_test_start "annuity round-trips: payment->presentValue/interestRate/numberOfPeriods"
pmt=$(math.payment 0.05 10 1000 0)
ok=true
kt_assert_near 1000 "$(math.presentValue 0.05 10 "$pmt" 0)" 1e-6 || ok=false     # recover PV
kt_assert_near 0.05 "$(math.interestRate 10 "$pmt" 1000 0)" 1e-6 || ok=false      # recover rate (Newton)
kt_assert_near 10 "$(math.numberOfPeriods 0.05 "$pmt" 1000 0)" 1e-6 || ok=false   # recover N
$ok && kt_test_pass "annuity round-trips: payment->presentValue/interestRate/numberOfPeriods" \
     || kt_test_fail "annuity round-trip wrong"

# ---------------------------------------------------------------------------
# 3. rate = 0 edge cases
# ---------------------------------------------------------------------------
kt_test_start "rate=0: linear formulas"
ok=true
kt_assert_near 500 "$(math.futureValue 0 5 -100 0)" || ok=false        # -pv - pmt*n = -(-100*5)
kt_assert_near -250 "$(math.payment 0 4 1000 0)" || ok=false            # -(fv+pv)/n = -1000/4
kt_assert_near 400 "$(math.presentValue 0 4 -100 0)" || ok=false        # -fv - pmt*n
$ok && kt_test_pass "rate=0: linear formulas" || kt_test_fail "rate=0 wrong"

# ---------------------------------------------------------------------------
# 4. PaymentTime flag: start-of-period yields a larger future value
# ---------------------------------------------------------------------------
kt_test_start "ptype=start (1) > ptype=end (0) for the same annuity"
fend=$(math.futureValue 0.05 10 -100 0)
fstart=$(math.futureValue 0.05 10 -100 0 1)
# start-of-period payments accrue one extra period: fstart = fend * 1.05
if kt_assert_near "$(awk -v f="$fend" 'BEGIN{printf "%.17g", f*1.05}')" "$fstart" 1e-9; then
    kt_test_pass "ptype=start (1) > ptype=end (0) for the same annuity"
else
    kt_test_fail "ptype flag wrong (end=$fend start=$fstart)"
fi

math._fe_stop 2>/dev/null
