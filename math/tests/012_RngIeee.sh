#!/bin/bash
# P7: RNG (randomRange/randomFrom, pure-bash), IEEE predicates (isNan/
# isInfinite), and the FPU-control wontfix stubs. New coverage — see NOTES.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "RngIeee" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# 1. RandomRange — in [min,max), upper-exclusive, reversed, degenerate
# ---------------------------------------------------------------------------
kt_test_start "randomRange: uniform in [min,max), upper-exclusive"
ok=true
for ((i=0;i<200;i++)); do
    r=$(math.randomRange 5 10)
    (( r >= 5 && r < 10 )) || { ok=false; break; }          # in [5,10)
done
# [0,2) yields only 0 or 1, never 2
for ((i=0;i<100;i++)); do
    r=$(math.randomRange 0 2)
    (( r == 0 || r == 1 )) || { ok=false; break; }
done
[[ "$(math.randomRange 5 6)" == 5 ]] || ok=false            # [5,6) = {5}
[[ "$(math.randomRange 7 7)" == 7 ]] || ok=false            # degenerate from==to
r=$(math.randomRange 10 5); (( r >= 5 && r < 10 )) || ok=false   # reversed args
$ok && kt_test_pass "randomRange: uniform in [min,max), upper-exclusive" || kt_test_fail "randomRange wrong (r=$r)"

# ---------------------------------------------------------------------------
# 2. RandomFrom — always returns a member of the list
# ---------------------------------------------------------------------------
kt_test_start "randomFrom: returns a member of the argument list"
ok=true
for ((i=0;i<100;i++)); do
    v=$(math.randomFrom alpha beta gamma delta)
    case "$v" in alpha|beta|gamma|delta) ;; *) ok=false; break;; esac
done
[[ "$(math.randomFrom solo)" == solo ]] || ok=false          # single element
$ok && kt_test_pass "randomFrom: returns a member of the argument list" || kt_test_fail "randomFrom returned '$v'"

# ---------------------------------------------------------------------------
# 3. IsNan / IsInfinite — on tokens and engine-produced values
# ---------------------------------------------------------------------------
kt_test_start "isNan / isInfinite on tokens and engine values"
math.feStart
ok=true
[[ "$(math.isNan nan)" == true ]] || ok=false
[[ "$(math.isNan -nan)" == true ]] || ok=false
[[ "$(math.isNan 1.0)" == false ]] || ok=false
[[ "$(math.isNan inf)" == false ]] || ok=false
[[ "$(math.isInfinite inf)" == true ]] || ok=false
[[ "$(math.isInfinite -inf)" == true ]] || ok=false
[[ "$(math.isInfinite 5)" == false ]] || ok=false
[[ "$(math.isInfinite nan)" == false ]] || ok=false
# engine-produced: sqrt(-1) -> nan; degenerate numberOfPeriods -> inf
[[ "$(math.isNan "$(math.sqrt -1)")" == true ]] || ok=false
[[ "$(math.isInfinite "$(math.numberOfPeriods 0.05 0 0 0)")" == true ]] || ok=false
$ok && kt_test_pass "isNan / isInfinite on tokens and engine values" || kt_test_fail "isNan/isInfinite wrong"

# ---------------------------------------------------------------------------
# 4. FPU-control wontfix stubs
# ---------------------------------------------------------------------------
kt_test_start "FPU stubs: getters report a default, setters return 1 (wontfix)"
ok=true
[[ "$(math.getRoundMode)" == "rmNearest" ]] || ok=false
[[ "$(math.getPrecisionMode)" == "pmDouble" ]] || ok=false
[[ -n "$(math.getExceptionMask)" ]] || ok=false
math.setRoundMode rmUp && ok=false          # setter must return 1
math.setPrecisionMode pmSingle && ok=false
math.setExceptionMask x && ok=false
math.clearExceptions || ok=false            # no-op returns 0
$ok && kt_test_pass "FPU stubs: getters report a default, setters return 1 (wontfix)" || kt_test_fail "FPU stubs wrong"

# ---------------------------------------------------------------------------
# 5. Zero-fork: RNG + predicates work with an empty PATH
# ---------------------------------------------------------------------------
kt_test_start "RNG + predicates make zero forks (empty PATH)"
if o1=$( PATH=''; math.randomRange 1 100 ) && (( o1 >= 1 && o1 < 100 )) \
   && o2=$( PATH=''; math.randomFrom x y z ) && [[ "$o2" == [xyz] ]] \
   && o3=$( PATH=''; math.isNan nan ) && [[ "$o3" == true ]] \
   && o4=$( PATH=''; math.isInfinite -inf ) && [[ "$o4" == true ]]; then
    kt_test_pass "RNG + predicates make zero forks (empty PATH)"
else
    kt_test_fail "a pure-bash P7 op forked: [$o1] [$o2] [$o3] [$o4]"
fi

math._fe_stop 2>/dev/null
