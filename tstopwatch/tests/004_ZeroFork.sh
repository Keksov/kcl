#!/bin/bash
# 004_ZeroFork.sh - the ENTIRE TStopwatch API runs with PATH='' (zero forks:
# every operation is builtins + 64-bit shell arithmetic; EPOCHREALTIME is a
# builtin variable). House goal — on MSYS2 a single fork costs ~10-17 ms,
# which would dwarf the µs clock being read.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSW_DIR="$SCRIPT_DIR/.."
source "$TSW_DIR/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: TStopwatch zero-fork (full API under PATH='')"

# fork-free wait (same clock)
_t_busy_us() {
    local __t_target=$1 __t_er __t_t0 __t_now
    __t_er=$EPOCHREALTIME; __t_t0=$(( ${__t_er%[.,]*} * 1000000 + 10#${__t_er##*[.,]} ))
    while :; do
        __t_er=$EPOCHREALTIME; __t_now=$(( ${__t_er%[.,]*} * 1000000 + 10#${__t_er##*[.,]} ))
        (( __t_now - __t_t0 >= __t_target )) && break
    done
}

kt_test_start "Full lifecycle + every getter + getTimeStamp under PATH=''"
_saved_path=$PATH
PATH=''
fails=""
TStopwatch.new zw                          || fails+=" new"
zw.Start                                   || fails+=" Start"
_t_busy_us 2000
zw.Stop                                    || fails+=" Stop"
zw.elapsedMicroseconds >/dev/null          || fails+=" us"
us=$RESULT
zw.elapsedTicks        >/dev/null          || fails+=" ticks"
zw.elapsedMilliseconds >/dev/null          || fails+=" ms"
zw.elapsedSeconds      >/dev/null          || fails+=" s"
zw.isRunning           >/dev/null          || fails+=" isRunning"
zw.frequency           >/dev/null          || fails+=" freq"
zw.isHighResolution    >/dev/null          || fails+=" hires"
zw.Restart                                 || fails+=" Restart"
zw.Reset                                   || fails+=" Reset"
TStopwatch.getTimeStamp                    || fails+=" getTimeStamp"
TStopwatch.new zw2 startnew                || fails+=" new-startnew"
zw2.delete                                 || fails+=" delete2"
zw.delete                                  || fails+=" delete"
PATH=$_saved_path
if [[ -z "$fails" ]] && (( us >= 2000 )); then
    kt_test_pass "every call rc 0 fork-free; measured $us µs across a 2 ms window"
else
    kt_test_fail "failed calls:${fails:-none}; us=$us"
fi

# Getter call contracts under PATH='' (kklass kk._return): a DIRECT call is
# SILENT and sets RESULT only; the echo happens exclusively in a subshell
# context, i.e. under $() capture (kklass.sh kk._return: BASH_SUBSHELL>0).
# Both paths must be builtin-only — $() forks a subshell but execs nothing.
kt_test_start "Direct call = silent + RESULT; \$() capture echoes — both under PATH=''"
TStopwatch.new ew
ew_out="${TMPDIR:-/tmp}/tsw004_out.$$"
_saved_path=$PATH
PATH=''
RESULT=""
ew.frequency >"$ew_out" 2>&1          # direct: must print NOTHING, set RESULT
rc_direct=$?
direct_result=$RESULT
captured="$(ew.frequency)"            # subshell: must echo the value
rc_capture=$?
PATH=$_saved_path
direct_bytes=$(wc -c <"$ew_out")
rm -f "$ew_out"
if [[ $rc_direct -eq 0 && "$direct_bytes" -eq 0 && "$direct_result" == "1000000" \
      && $rc_capture -eq 0 && "$captured" == "1000000" ]]; then
    kt_test_pass "direct: 0 bytes + RESULT=1000000; \$(): '1000000' — both rc 0, no PATH needed"
else
    kt_test_fail "direct rc=$rc_direct bytes=$direct_bytes RESULT='$direct_result'; capture rc=$rc_capture val='$captured'"
fi
ew.delete

kt_test_log "004_ZeroFork.sh completed"
