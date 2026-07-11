#!/bin/bash
# P6: statistics. Arrays as arg lists; engine computes each in one awk pass.
# sumInt is pure-bash integer (exact, zero-fork). Sample stats use N-1, popn N.
# New coverage — see ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Stats" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

math.feStart
# Classic dataset: mean 5, popn variance 4, sample variance 32/7.
D=(2 4 4 4 5 5 7 9)

# ---------------------------------------------------------------------------
# 1. Sum / Mean / SumOfSquares / SumsAndSquares
# ---------------------------------------------------------------------------
kt_test_start "sum/mean/sumOfSquares/sumsAndSquares"
ok=true
kt_assert_near 40 "$(math.sum "${D[@]}")" || ok=false
kt_assert_near 5 "$(math.mean "${D[@]}")" || ok=false
kt_assert_near 232 "$(math.sumOfSquares "${D[@]}")" || ok=false
read -r sm sq <<< "$(math.sumsAndSquares "${D[@]}")"
kt_assert_near 40 "$sm" || ok=false
kt_assert_near 232 "$sq" || ok=false
kt_assert_near 2.5 "$(math.mean 1 2 3 4)" || ok=false
$ok && kt_test_pass "sum/mean/sumOfSquares/sumsAndSquares" || kt_test_fail "sum/mean wrong"

# ---------------------------------------------------------------------------
# 2. Variance (sample N-1) / TotalVariance / PopnVariance (N)
# ---------------------------------------------------------------------------
kt_test_start "variance(sample N-1) / totalVariance / popnVariance(N)"
ok=true
kt_assert_near 32 "$(math.totalVariance "${D[@]}")" || ok=false
kt_assert_near 4.571428571428571 "$(math.variance "${D[@]}")" || ok=false   # 32/7
kt_assert_near 4 "$(math.popnVariance "${D[@]}")" || ok=false                # 32/8
kt_assert_near 1.6666666666666667 "$(math.variance 1 2 3 4)" || ok=false     # 5/3
kt_assert_near 1.25 "$(math.popnVariance 1 2 3 4)" || ok=false               # 5/4
[[ "$(math.variance 5)" == 0 ]] || ok=false                                  # N=1 guard
$ok && kt_test_pass "variance(sample N-1) / totalVariance / popnVariance(N)" || kt_test_fail "variance wrong"

# ---------------------------------------------------------------------------
# 3. StdDev / PopnStdDev / MeanAndStdDev
# ---------------------------------------------------------------------------
kt_test_start "stdDev / popnStdDev / meanAndStdDev"
ok=true
kt_assert_near 2.1380899352993953 "$(math.stdDev "${D[@]}")" || ok=false   # sqrt(32/7)
kt_assert_near 2 "$(math.popnStdDev "${D[@]}")" || ok=false                  # sqrt(4)
read -r mn sd <<< "$(math.meanAndStdDev "${D[@]}")"
kt_assert_near 5 "$mn" && kt_assert_near 2.1380899352993953 "$sd" || ok=false
$ok && kt_test_pass "stdDev / popnStdDev / meanAndStdDev" || kt_test_fail "stdDev wrong"

# ---------------------------------------------------------------------------
# 4. Norm (euclidean L2)
# ---------------------------------------------------------------------------
kt_test_start "norm = sqrt(sum of squares)"
if kt_assert_near 15.231546211727817 "$(math.norm "${D[@]}")" \
   && kt_assert_near 5 "$(math.norm 3 4)" && kt_assert_near 13 "$(math.norm 5 12)"; then
    kt_test_pass "norm = sqrt(sum of squares)"
else
    kt_test_fail "norm wrong"
fi

# ---------------------------------------------------------------------------
# 5. MomentSkewKurtosis (m1,m2,m3,m4,skew,kurtosis)
# ---------------------------------------------------------------------------
kt_test_start "momentSkewKurtosis: 6 central-moment fields"
read -r m1 m2 m3 m4 skew kurt <<< "$(math.momentSkewKurtosis "${D[@]}")"
ok=true
kt_assert_near 5 "$m1" || ok=false        # mean
kt_assert_near 4 "$m2" || ok=false        # popn variance
kt_assert_near 5.25 "$m3" || ok=false     # 42/8
kt_assert_near 44.5 "$m4" || ok=false     # 356/8
kt_assert_near 0.65625 "$skew" || ok=false  # m3/m2^1.5 = 5.25/8
kt_assert_near 2.78125 "$kurt" || ok=false  # m4/m2^2 = 44.5/16
$ok && kt_test_pass "momentSkewKurtosis: 6 central-moment fields" || kt_test_fail "moments = [$m1 $m2 $m3 $m4 $skew $kurt]"

# ---------------------------------------------------------------------------
# 6. SumInt (pure-bash integer, exact, zero-fork)
# ---------------------------------------------------------------------------
kt_test_start "sumInt: exact integer sum, zero forks (empty PATH)"
ok=true
[[ "$(math.sumInt 1 2 3 4 5 6 7 8 9 10)" == 55 ]] || ok=false
[[ "$(math.sumInt -5 3 -2)" == -4 ]] || ok=false
[[ "$(math.sumInt 42)" == 42 ]] || ok=false
o=$( PATH=''; math.sumInt 10 20 30 ); [[ "$o" == 60 ]] || ok=false   # zero-fork
$ok && kt_test_pass "sumInt: exact integer sum, zero forks (empty PATH)" || kt_test_fail "sumInt wrong (empty-PATH=$o)"

# ---------------------------------------------------------------------------
# 7. RandG — Gaussian distribution sanity (semantic parity only)
# ---------------------------------------------------------------------------
kt_test_start "randG: empirical mean/stddev of N(10,2) samples in tolerance"
samples=()
for ((i=0;i<400;i++)); do samples+=("$(math.randG 10 2)"); done
emean=$(math.mean "${samples[@]}")
estd=$(math.stdDev "${samples[@]}")
# 400 samples: SE(mean)=2/20=0.1, so ±0.6 is >5sigma; stddev within ±0.5
if awk -v m="$emean" -v s="$estd" 'BEGIN{exit !(m>9.4 && m<10.6 && s>1.5 && s<2.5)}'; then
    kt_test_pass "randG: empirical mean/stddev of N(10,2) samples in tolerance (mean=$emean sd=$estd)"
else
    kt_test_fail "randG distribution off: mean=$emean stddev=$estd (want ~10, ~2)"
fi

math._fe_stop 2>/dev/null
