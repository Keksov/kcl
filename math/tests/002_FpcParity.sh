#!/bin/bash
# FPC parity fixtures — ported verbatim from the FPC test tree, values kept
# exactly (never "improved"). Built up incrementally: each assertion lands in
# the phase that implements its function.
#
#   seed: tests/test/tmath1.pp                      integer div/mod  -> DivMod   (P2) [here]
#         tests/test/units/system/tround.pp         Round half-even  -> RoundTo  (P2) [here]
#         tests/webtbs/tw*.pp (Power/Log/Sign/...)   mined per group             (P3+)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "FpcParity" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# tmath1.pp — integer div/mod (truncation toward zero on negative dividends)
# ---------------------------------------------------------------------------
kt_test_start "FPC parity (tmath1.pp): DivMod quotient == Pascal div"
ok=true
[[ "$(math.divMod -10 5)" == "-2 0" ]]        || ok=false   # -10 div 5 = -2
[[ "$(math.divMod -20 10)" == "-2 0" ]]       || ok=false   # -20 div 10 = -2
[[ "$(math.divMod 64000 2)" == "32000 0" ]]   || ok=false   # word test
[[ "$(math.divMod -1000000 2)" == "-500000 0" ]]  || ok=false   # longint test
[[ "$(math.divMod -1000000 10)" == "-100000 0" ]] || ok=false
[[ "$(math.divMod -10 3)" == "-3 -1" ]]       || ok=false   # negative remainder
$ok && kt_test_pass "FPC parity (tmath1.pp): DivMod quotient == Pascal div" \
     || kt_test_fail "DivMod parity failed"

# ---------------------------------------------------------------------------
# tround.pp / FPC Round — round half to even (banker's), used by RoundTo
# ---------------------------------------------------------------------------
kt_test_start "FPC parity (tround.pp): RoundTo is round-half-to-even"
math.feStart
ok=true
for c in "2.5 0 2" "3.5 0 4" "0.5 0 0" "1.5 0 2" "-0.5 0 0" "-2.5 0 -2" "-3.5 0 -4"; do
    read -r v d exp <<< "$c"
    kt_assert_near "$exp" "$(math.roundTo "$v" "$d")" || { ok=false; break; }
done
$ok && kt_test_pass "FPC parity (tround.pp): RoundTo is round-half-to-even" \
     || kt_test_fail "RoundTo banker's-rounding parity failed at v=$v"
math._fe_stop 2>/dev/null
