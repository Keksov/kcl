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
# `|| true`: math._fe_drop'"'"'s `wait` of the killed awk returns 143, which
# `set -e` turns into an exit of the caller (pre-existing, found_in_U4)
math.feStop || true
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
