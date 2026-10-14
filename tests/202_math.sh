#!/bin/bash
# The runtime checks of ONE migrated kcl unit — the stem after `NNN_` names it;
# the checks are kclt_unit_tests in kcl_units.sh (one file per unit: loads run
# in parallel under the threaded runner).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
UNIT_NAME=${BASH_SOURCE[0]##*/}; UNIT_NAME=${UNIT_NAME#[0-9][0-9][0-9]_}; UNIT_NAME=${UNIT_NAME%.sh}
kt_test_init "Unit_$UNIT_NAME" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup

# math only: the float engine (an awk co-process, math._fe_start) across the
# U24' dev hatch, checked inside the once process (hooks of kclt_unit_tests, no
# extra load). `kk.unit --forget math` + a re-source while the engine runs must
# keep THE SAME engine: a reload that reset its pid/fd state made the next call
# start a second `coproc MATH_FE` ("coproc [pid:...] still exists") and left
# the first awk running [G2, pattern rule 10].
rm -f "$KCLT_TMP/engine.out"
KCLT_FORGET_PRE='math.feStart; math.sin 1; KM_a=$RESULT KM_p=$__MATH_FE_PID'
KCLT_FORGET_POST='
math.feActive || true; KM_act=$RESULT
math.sin 1; KM_b=$RESULT KM_q=$__MATH_FE_PID
math.feStop
if kill -0 "$KM_p" 2>/dev/null; then KM_old=alive; else KM_old=gone; fi
[[ $KM_p == "$KM_q" ]] && KM_pid=same || KM_pid=new
[[ -n $KM_a && $KM_a == "$KM_b" ]] && KM_s=same || KM_s="$KM_a/$KM_b"
echo "active=$KM_act pid=$KM_pid sin=$KM_s old=$KM_old" > "$KCLT_TMP/engine.out"'
kclt_unit_tests "$UNIT_NAME"

kt_test_start "math engine: kk.unit --forget math + a re-source under set -eu with the awk co-process running keep that engine (active, same pid, same answer); after math.feStop no awk is left [U24', G2]"
OUT=""; [[ -f $KCLT_TMP/engine.out ]] && OUT="$(<"$KCLT_TMP/engine.out")"
if [[ $OUT == "active=true pid=same sin=same old=gone" ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "out='$OUT' want='active=true pid=same sin=same old=gone' (stderr: see the once test)"
fi

# --- the engine state is this shell's, never the environment's (R1 of the U4
# final review, critic_u4 C1) ---------------------------------------------------
# The state is set once per process (above), keyed on something no environment
# can supply (an assoc). An inherited __MATH_FE_* — a hostile export, or a
# `set -a` parent — is reset at load, and the engine's pid / fds / temp file
# reach kill / exec / rm only as this process recorded them.
cat > "$KCLT_TMP/envA.sh" <<'EOF'
P=$KCLT_TMP/PWN_A; rm -f "$P"
env __MATH_FE_UP=1 __MATH_FE_PID=999999 "__MATH_FE_IN=9>&-; echo PWN > $P; #" "__MATH_FE_OUT=8<&-; echo PWN >> $P; #" \
    __MATH_FE_TRAPPED=1 __MATH_FE_OWN=A "pid=a[\$(echo PWN >> $P)]" "$BASH" -c '
    source "$KCL_DIR/math/math.sh" || exit 9
    math.sin 1; r=$? s=$RESULT p=$__MATH_FE_PID
    math.feStop
    [[ $p == 999999 ]] && p=env || p=own
    echo "rc=$r sin=$s pid=$p"'
[[ -e $P ]] && echo PWN || echo clean
EOF
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/envA.sh"
kclt_expect "math engine: an inherited __MATH_FE_UP/PID/IN/OUT/TRAPPED (an fd value carrying shell code, a foreign pid) and a scalar __MATH_FE_OWN are reset at load: math.sin starts this shell's own engine, nothing is evaluated [R1, critic_u4 C1]" \
    $'rc=0 sin=0.8414709848078965 pid=own\nclean'

cat > "$KCLT_TMP/envA2.sh" <<'EOF'
V=$KCLT_TMP/victim; : > "$V"; P=$KCLT_TMP/PWN_A2; rm -f "$P"
env __MATH_FE_UP= "__MATH_FE_PROGFILE=$V" __MATH_FE_TRAPPED=1 "$BASH" -c '
    source "$KCL_DIR/math/math.sh" || exit 9; math.feStop; echo "env stop=$?"'
[[ -e $V ]] && echo "env victim=kept" || echo "env victim=DELETED"
"$BASH" -c '
    source "$KCL_DIR/math/math.sh" || exit 9
    sleep 30 >/dev/null 2>&1 & s=$!
    math.sin 1 >/dev/null; e=$__MATH_FE_PID
    __MATH_FE_PROGFILE=$1; __MATH_FE_PID=$s
    __MATH_FE_IN="9>&-; echo PWN > $2; #"; __MATH_FE_OUT="8<&-; echo PWN >> $2; #"
    math.feStop; r=$?
    kill -0 "$s" 2>/dev/null && a=alive || a=killed
    kill -0 "$e" 2>/dev/null && b=alive || b=stopped
    kill "$s" 2>/dev/null; wait "$s" 2>/dev/null
    echo "proc stop=$r foreign=$a engine=$b"' _ "$V" "$P"
[[ -e $V ]] && echo "proc victim=kept" || echo "proc victim=DELETED"
[[ -e $P ]] && echo PWN || echo clean
EOF
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/envA2.sh"
kclt_expect "math engine: math.feStop removes only the temp file this shell wrote (*/.math_fe_\$\$.awk), closes only all-digit fds it opened and kills only the awk it started — an inherited __MATH_FE_PROGFILE and in-process overwrites of PROGFILE/PID/IN/OUT touch nothing, and the real engine still stops [R1, critic_u4 C1]" \
    $'env stop=0\nenv victim=kept\nproc stop=0 foreign=alive engine=stopped\nproc victim=kept\nclean'

cat > "$KCLT_TMP/envB.sh" <<'EOF'
"$BASH" -c '
    set -a
    source "$KCL_DIR/math/math.sh" || exit 9
    math.sin 1 >/dev/null; p1=$__MATH_FE_PID
    c=$("$BASH" -c "source \"\$KCL_DIR/math/math.sh\" || exit 9; math.sin 1; echo \"rc=\$? sin=\$RESULT\"; math.feStop" 2>&1)
    c2=$("$BASH" -c "math.sin 1; echo \"rc=\$? sin=\$RESULT\"; math.feStop" 2>&1)
    kill -0 "$p1" 2>/dev/null && a=alive || a=DEAD
    math.sin 1 >/dev/null; r=$?
    [[ $__MATH_FE_PID == "$p1" ]] && q=same || q=new
    math.feStop
    echo "child: $c | inherited: $c2 | parent engine=$a rc=$r pid=$q"'
EOF
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/envB.sh"
kclt_expect "math engine: a set -a parent with a running engine — a child that sources math and one that only inherits the exported functions each start their own engine (no 'Bad file descriptor'); the parent's engine survives (same pid) [R1, critic_u4 C1 case B]" \
    'child: rc=0 sin=0.8414709848078965 | inherited: rc=0 sin=0.8414709848078965 | parent engine=alive rc=0 pid=same'

# --- math.feStop under set -e (R2; found_in_U4 G2) ----------------------------
cat > "$KCLT_TMP/stopE.sh" <<'EOF'
set -e
source "$KCL_DIR/math/math.sh"
math.feStart; math.feStop; echo "stop=$?"
math.feStart; kill -9 "$__MATH_FE_PID"; math.feStop; echo "dead=$?"
math.feStop; echo "idle=$?"
math.sin 1; echo "after=$RESULT"
math.feStop
echo survived
EOF
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/stopE.sh"
kclt_expect "math.feStop under set -e returns its documented rc 0 and the caller survives: a running engine, an engine killed from outside, no engine; math works after [R2, found_in_U4 G2]" \
    $'stop=0\ndead=0\nidle=0\nafter=0.8414709848078965\nsurvived'
