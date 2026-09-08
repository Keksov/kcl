#!/bin/bash
# P7 — integer overflow on the "exact" pure-bash paths, and the RNG.
#
#   M8  `intPower 2 63` answered -9223372036854775808 and `2 64` answered 0;
#       `sumInt 9223372036854775807 1` went negative. bash's $(( )) is
#       intmax_t, so it wraps exactly the way FPC's Int64 does — but FPC's
#       IntPower RETURNS A FLOAT (math.pp:1044), so the wrap is not parity, it
#       is the pure-bash shortcut leaking. Overflow now falls through to the
#       engine and answers the FPC Double.
#   M13 `randomRange` composed two $RANDOM (30 bits) and took `% n`, so any
#       range wider than 2^30 could never reach its upper part and every range
#       that is not a power of two was biased.
#
# The uniformity check is deliberately coarse (a chi-square-free bucket test
# with a wide margin): it must catch "the top half is unreachable", not prove
# the generator is good.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "M8OverflowAndRng" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
source "$MATH_DIR/math.sh"
math.feStart

# ---------------------------------------------------------------------------
# 1. M8 — intPower stays exact while the result fits, then answers the FPC
#    Double instead of a wrapped integer.
# ---------------------------------------------------------------------------
kt_test_start "intPower is exact inside int64 [M8]"
ok=true; why=""
_ip() { RESULT="<unset>"; math.intPower "$1" "$2"; [[ "$RESULT" == "$3" ]] || { ok=false; why+=" [intPower $1 $2 -> '$RESULT' want '$3']"; }; }
_ip 2 10   1024
_ip 2 62   4611686018427387904
_ip -2 63  -9223372036854775808
_ip 10 18  1000000000000000000
_ip 0 0    1
_ip 5 0    1
_ip -3 3   -27
_ip 1 62   1
_ip -1 63  -1
$ok && kt_test_pass "9 exact rows" || kt_test_fail "$why"

kt_test_start "intPower past int64 answers the FPC Double, not a wrap [M8]"
ok=true; why=""
_ipf() { RESULT="<unset>"; math.intPower "$1" "$2"; [[ "$RESULT" == "$3" ]] || { ok=false; why+=" [intPower $1 $2 -> '$RESULT' want '$3']"; }; }
_ipf 2 63   9.2233720368547758e+18
_ipf 2 64   1.8446744073709552e+19
_ipf 10 19  1e+19
_ipf 10 20  1e+20
_ipf 3 40   1.2157665459056929e+19
_ipf 2 -2   0.25
_ipf 1.5 3  3.375
$ok && kt_test_pass "7 engine rows" || kt_test_fail "$why"

kt_test_start "sumInt is exact inside int64 and switches to the engine past it [M8]"
ok=true; why=""
RESULT="<unset>"; math.sumInt 1 2 3 4 5
[[ "$RESULT" == 15 ]] || { ok=false; why+=" [sumInt 1..5 -> '$RESULT']"; }
RESULT="<unset>"; math.sumInt 9223372036854775806 1
[[ "$RESULT" == 9223372036854775807 ]] || { ok=false; why+=" [sumInt maxint-1 +1 -> '$RESULT']"; }
RESULT="<unset>"; math.sumInt 9223372036854775807 1
[[ "$RESULT" == 9.2233720368547758e+18 ]] || { ok=false; why+=" [sumInt maxint+1 -> '$RESULT']"; }
RESULT="<unset>"; math.sumInt -9223372036854775808 -1
[[ "$RESULT" == -9.2233720368547758e+18 ]] || { ok=false; why+=" [sumInt minint-1 -> '$RESULT']"; }
RESULT="<unset>"; math.sumInt 9223372036854775807 1 -1
[[ "$RESULT" == 9.2233720368547758e+18 ]] || { ok=false; why+=" [sumInt overflow-then-back -> '$RESULT']"; }
$ok && kt_test_pass "exact below, Double above" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 2. M13 — randomRange covers its whole range, in both directions, and is not
#    limited to 30 bits.
# ---------------------------------------------------------------------------
kt_test_start "randomRange respects its bounds on 2000 draws [M13]"
ok=true; why=""
lo=1000000000000; hi=1000000000010
for (( i = 0; i < 2000; i++ )); do
    RESULT="<unset>"; math.randomRange $lo $hi
    if (( RESULT < lo || RESULT >= hi )); then ok=false; why+=" [$RESULT outside [$lo,$hi)]"; break; fi
done
$ok && kt_test_pass "in range" || kt_test_fail "$why"

kt_test_start "randomRange reaches the top of a range wider than 2^30 [M13]"
# The old body drew 30 bits and took % n, so for n > 2^30 the values above
# 2^30 were UNREACHABLE. 400 draws with a 2^40 span must land above 2^35.
lo=0; hi=$(( 1 << 40 ))
seen_high=0; seen_low=0
for (( i = 0; i < 400; i++ )); do
    math.randomRange $lo $hi
    (( RESULT > (1 << 35) )) && seen_high=1
    (( RESULT < (1 << 35) )) && seen_low=1
done
if (( seen_high && seen_low )); then
    kt_test_pass "both halves reachable"
else
    kt_test_fail "seen_high=$seen_high seen_low=$seen_low (the draw is narrower than the range)"
fi

kt_test_start "randomRange is unbiased enough: 8 buckets over 4000 draws [M13]"
# n = 3 * 2^k is the shape a plain `% n` skews worst. Every bucket must get
# between half and double its expected share.
declare -a bucket=(0 0 0 0 0 0 0 0)
n=$(( 3 * (1 << 28) ))
for (( i = 0; i < 4000; i++ )); do
    math.randomRange 0 $n
    b=$(( RESULT * 8 / n ))
    (( b > 7 )) && b=7
    (( bucket[b] += 1 )) || :
done
lowest=99999; highest=0
for b in "${bucket[@]}"; do
    (( b < lowest )) && lowest=$b
    (( b > highest )) && highest=$b
done
if (( lowest >= 250 && highest <= 1000 )); then
    kt_test_pass "buckets ${bucket[*]} (expected ~500 each)"
else
    kt_test_fail "buckets ${bucket[*]} — min $lowest max $highest, expected ~500 each"
fi

kt_test_start "randomRange edge cases: equal bounds, reversed bounds, negatives [M13]"
ok=true; why=""
RESULT="<unset>"; math.randomRange 5 5
[[ "$RESULT" == 5 ]] || { ok=false; why+=" [5,5 -> '$RESULT']"; }
for (( i = 0; i < 200; i++ )); do
    math.randomRange 10 0
    (( RESULT >= 0 && RESULT < 10 )) || { ok=false; why+=" [reversed -> $RESULT]"; break; }
    math.randomRange -5 -1
    (( RESULT >= -5 && RESULT < -1 )) || { ok=false; why+=" [negative -> $RESULT]"; break; }
    math.randomRange -3 3
    (( RESULT >= -3 && RESULT < 3 )) || { ok=false; why+=" [straddling -> $RESULT]"; break; }
done
$ok && kt_test_pass "bounds honoured, upper end exclusive" || kt_test_fail "$why"

kt_test_start "a span that overflows int64 is rc 1, not a wrapped negative [M13]"
ok=true; why=""
RESULT="<unset>"
math.randomRange -9223372036854775808 9223372036854775807 && { ok=false; why+=" [full span accepted -> '$RESULT']"; }
[[ -z "$RESULT" ]] || { ok=false; why+=" [RESULT='$RESULT']"; }
# ... but a span that just fits is fine
RESULT="<unset>"
math.randomRange 0 9223372036854775807 || { ok=false; why+=" [0..maxint rejected]"; }
(( RESULT >= 0 )) || { ok=false; why+=" [0..maxint -> negative $RESULT]"; }
$ok && kt_test_pass "overflowing span rejected, maximal legal span accepted" || kt_test_fail "$why"

kt_test_start "randomFrom picks every element of a 5-element list [M13]"
declare -A seen=()
for (( i = 0; i < 300; i++ )); do
    math.randomFrom a b c d e
    seen[$RESULT]=1
done
if (( ${#seen[@]} == 5 )); then
    kt_test_pass "all 5 reachable"
else
    kt_test_fail "only ${#seen[@]} distinct values: ${!seen[*]}"
fi

kt_test_start "randomRange and randomFrom are fork-free [1.8]"
p0=$BASHPID; ok=true
math.randomRange 1 1000000000000 >/dev/null; [[ $BASHPID == "$p0" ]] || ok=false
math.randomFrom a b c >/dev/null;            [[ $BASHPID == "$p0" ]] || ok=false
body="$(declare -f math.randomRange)$(declare -f math.randomFrom)"
[[ "$body" == *'$('* ]] && ok=false
$ok && kt_test_pass "no fork, no command substitution" || kt_test_fail "randomRange/randomFrom forked"
