#!/bin/bash
# Core (P0): the float engine (lazy awk co-process), pure-bash decimal helpers,
# constants, and the perf/shape contracts. Every check here is "new coverage"
# (P0's plumbing has no FPC test counterpart) — see ../TEST_COVERAGE_NOTES.md.
# Tier-B engine values are compared with kt_assert_near (Double ~1-2 ulp parity).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "Core" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
[[ -f "$MATH_DIR/math.sh" ]] && source "$MATH_DIR/math.sh"

# ---------------------------------------------------------------------------
# 1. Constant getters
# ---------------------------------------------------------------------------
kt_test_start "constant getters return the __MATH_* values"
if [[ "$(math.pi)" == "3.1415926535897932385" && "$(math.e)" == "2.7182818284590452354" \
   && "$(math.infinity)" == "inf" && "$(math.negInfinity)" == "-inf" && "$(math.nan)" == "nan" \
   && "$(math.minDouble)" == "2.2250738585072014e-308" \
   && "$(math.maxDouble)" == "1.7976931348623157e+308" \
   && "$(math.minSingle)" == "1.1754943508e-38" && "$(math.maxSingle)" == "3.4028234664e+38" \
   && "$(math.maxExtended)" == "1.18973149535723176502e+4932" ]]; then
    kt_test_pass "constant getters return the __MATH_* values"
else
    kt_test_fail "constant getter mismatch"
fi

kt_test_start "__MATH_* constants are readonly (writes fail loudly)"
if (__MATH_PI=1) 2>/dev/null; then
    kt_test_fail "__MATH_PI write unexpectedly succeeded"
else
    kt_test_pass "__MATH_* constants are readonly (writes fail loudly)"
fi

# ---------------------------------------------------------------------------
# 2. Pure-bash decimal comparator (_dec_cmp)
# ---------------------------------------------------------------------------
kt_test_start "_dec_cmp: signs, precision, magnitude, zero/-0, big numbers"
dc_fail=""
# each row: "a b expected"
dc_cases=(
    "1.5 1.50 0"          # trailing-zero precision
    "3 3.0000 0"          # integer vs padded decimal
    "0 -0 0"              # signed zero
    "-0.0 0 0"
    "10 9 1"              # length-driven magnitude
    "9 10 -1"
    "2.5 2.45 1"          # fractional magnitude
    "2.45 2.5 -1"
    "-2.5 -2.4 -1"        # negatives: more-negative is smaller
    "-2.4 -2.5 1"
    "-1 1 -1"             # cross-sign
    "1 -1 1"
    "0 0.0001 -1"         # zero vs tiny positive
    "0 -0.0001 1"         # zero vs tiny negative
    "123456789012345678901234567890 123456789012345678901234567891 -1"  # >64-bit
    "5 5 0"
)
for row in "${dc_cases[@]}"; do
    read -r a b exp <<< "$row"
    math._dec_cmp "$a" "$b"
    [[ "$REPLY" == "$exp" ]] || { dc_fail="_dec_cmp($a,$b)=$REPLY want $exp"; break; }
done
if [[ -z "$dc_fail" ]]; then
    kt_test_pass "_dec_cmp: signs, precision, magnitude, zero/-0, big numbers (${#dc_cases[@]} cases)"
else
    kt_test_fail "$dc_fail"
fi

# ---------------------------------------------------------------------------
# 3. _trunc / _frac / _is_int / _abs
# ---------------------------------------------------------------------------
kt_test_start "_trunc / _frac toward zero, signed fraction"
ok=true
math._trunc -2.9;  [[ "$REPLY" == "-2" ]]  || ok=false
math._trunc 2.9;   [[ "$REPLY" == "2" ]]   || ok=false
math._trunc 5;     [[ "$REPLY" == "5" ]]   || ok=false
math._trunc -0.5;  [[ "$REPLY" == "0" ]]   || ok=false
math._frac -2.9;   [[ "$REPLY" == "-0.9" ]] || ok=false
math._frac 3.25;   [[ "$REPLY" == "0.25" ]] || ok=false
math._frac 7;      [[ "$REPLY" == "0" ]]   || ok=false
math._abs -2.5;    [[ "$REPLY" == "2.5" ]] || ok=false
math._abs 4;       [[ "$REPLY" == "4" ]]   || ok=false
if $ok; then kt_test_pass "_trunc / _frac toward zero, signed fraction"; else kt_test_fail "trunc/frac/abs wrong (last REPLY=$REPLY)"; fi

kt_test_start "_is_int recognises integer literals only"
if math._is_int 42 && math._is_int -7 && math._is_int +3 \
   && ! math._is_int 3.5 && ! math._is_int abc && ! math._is_int "" && ! math._is_int 1e3; then
    kt_test_pass "_is_int recognises integer literals only"
else
    kt_test_fail "_is_int classification wrong"
fi

# ---------------------------------------------------------------------------
# 4. Float engine — laziness
# ---------------------------------------------------------------------------
kt_test_start "float engine is lazy: not active until first use"
math._fe_stop 2>/dev/null           # ensure a clean slate
if [[ "$(math.feActive)" == "false" ]]; then
    kt_test_pass "float engine is lazy: not active until first use"
else
    kt_test_fail "engine reported active before any use"
fi

# ---------------------------------------------------------------------------
# 5. Float engine — correctness (Double parity, tolerance 1e-12)
# ---------------------------------------------------------------------------
kt_test_start "float engine: transcendentals match FPC Double (tolerance 1e-12)"
math.feStart
fe_fail=""
# "op args | expected"
fe_cases=(
    "pi | 3.141592653589793"
    "sin 0.5235987755982988 | 0.5"          # sin(pi/6)
    "cos 0 | 1"
    "tan 0.7853981633974483 | 1"            # tan(pi/4)
    "sqrt 2 | 1.4142135623730951"
    "exp 0 | 1"
    "ln 1 | 0"
    "log10 1000 | 3"
    "log2 1024 | 10"
    "atan2 1 1 | 0.7853981633974483"        # pi/4
    "pow 2 10 | 1024"
    "hypot 3 4 | 5"
)
for c in "${fe_cases[@]}"; do
    req=${c%|*}; exp=${c#*|}
    req=${req%% }; exp=${exp# }
    # shellcheck disable=SC2086
    math._fe $req
    kt_assert_near "$exp" "$REPLY" 1e-12 || { fe_fail="$req -> $REPLY (want ~$exp)"; break; }
done
if [[ -z "$fe_fail" ]]; then
    kt_test_pass "float engine: transcendentals match FPC Double (${#fe_cases[@]} ops)"
else
    kt_test_fail "engine value wrong: $fe_fail"
fi

kt_test_start "float engine: sincos returns two fields"
math._fe sincos 1.0
read -r s c <<< "$REPLY"
if kt_assert_near 0.8414709848078965 "$s" 1e-12 && kt_assert_near 0.5403023058681398 "$c" 1e-12; then
    kt_test_pass "float engine: sincos returns two fields"
else
    kt_test_fail "sincos(1.0) = [$REPLY]"
fi

# ---------------------------------------------------------------------------
# 6. Float engine — single persistent process, reused across $()
# ---------------------------------------------------------------------------
kt_test_start "engine persists: one co-process reused across calls incl. \$()"
math.feStart
p1=$__MATH_FE_PID
for i in 1 2 3 4 5; do math._fe sin "$i" >/dev/null; done
p2=$__MATH_FE_PID
mfe() { math._fe "$@"; echo "$REPLY"; }   # an echoing wrapper, consumed via $()
v=$(mfe pow 2 5)                          # 32, computed in a subshell
act=$(math.feActive)
if [[ "$p1" == "$p2" ]] && kill -0 "$p1" 2>/dev/null && [[ "$act" == "true" ]] \
   && kt_assert_near 32 "$v" 1e-12; then
    kt_test_pass "engine persists: one co-process reused across calls incl. \$()"
else
    kt_test_fail "reuse broken: p1=$p1 p2=$p2 active=$act v=$v"
fi

# ---------------------------------------------------------------------------
# 7. Float engine — no deadlock under load
# ---------------------------------------------------------------------------
kt_test_start "engine: 300 sequential calls complete without deadlock"
math.feStart
load_ok=true
for ((i=0;i<300;i++)); do math._fe sqrt "$i" || { load_ok=false; break; }; done
if $load_ok && [[ -n "$REPLY" ]]; then
    kt_test_pass "engine: 300 sequential calls complete without deadlock"
else
    kt_test_fail "engine stalled/failed under load at REPLY=$REPLY"
fi

# ---------------------------------------------------------------------------
# 8. Graceful degradation: no awk on PATH
# ---------------------------------------------------------------------------
kt_test_start "no awk on PATH: engine returns 1, Tier-A core still works"
math._fe_stop 2>/dev/null                 # force _fe_start to re-probe for awk
deg_ok=true
# engine call with empty PATH must fail (return 1), not hang or error out
if ( PATH=''; math._fe sin 1 ) 2>/dev/null; then deg_ok=false; fi
# ...but pure-bash decimal helpers still work with no PATH (zero forks)
( PATH=''; math._dec_cmp 2.5 2.4; [[ "$REPLY" == "1" ]] ) || deg_ok=false
( PATH=''; math._trunc -9.9; [[ "$REPLY" == "-9" ]] ) || deg_ok=false
if $deg_ok; then
    kt_test_pass "no awk on PATH: engine returns 1, Tier-A core still works"
else
    kt_test_fail "graceful-degradation contract broken"
fi

# ---------------------------------------------------------------------------
# 9. Perf / shape contracts
# ---------------------------------------------------------------------------
kt_test_start "math dispatchers are thin (no capture overhead)"
decl="$(declare -f math.pi)"
if [[ "$decl" == *"__kk_static_out"* || "$decl" == *'REPLY=${'* ]]; then
    kt_test_fail "capturing dispatcher found — a static var crept in?"
else
    kt_test_pass "math dispatchers are thin (no capture overhead)"
fi

kt_test_start "Tier-A decimal helpers make zero forks (work with an empty PATH)"
if out=$( PATH=''; math._dec_cmp -3.14 -3.15; echo "$REPLY" ) && [[ "$out" == "1" ]] \
   && out2=$( PATH=''; math._frac 12.5; echo "$REPLY" ) && [[ "$out2" == "0.5" ]]; then
    kt_test_pass "Tier-A decimal helpers make zero forks (work with an empty PATH)"
else
    kt_test_fail "a Tier-A helper forked (empty-PATH run failed): [$out] [$out2]"
fi

kt_test_start "kklass metadata lists the P0 static methods"
expected=(pi e infinity nan feStart feActive maxDouble)
missing=()
for m in "${expected[@]}"; do
    found=false
    for r in "${math_class_static_methods[@]}"; do [[ "$r" == "$m" ]] && { found=true; break; }; done
    $found || missing+=("$m")
done
if (( ${#math_class_static_methods[@]} > 0 && ${#missing[@]} == 0 )); then
    kt_test_pass "kklass metadata lists the P0 static methods"
else
    kt_test_fail "metadata missing: ${missing[*]:-(none)}; count ${#math_class_static_methods[@]}"
fi

# clean up the co-process so it doesn't leak into later suites sharing the shell
math._fe_stop 2>/dev/null
