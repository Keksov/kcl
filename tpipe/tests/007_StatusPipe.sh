#!/usr/bin/env bash
# 007_StatusPipe.sh — launch L3.5-8: the status pipe that recovers a producer's
# exit status when bash loses it (tpipe.sh, "__TPIPE_ST").
#
# The bash race itself is load-dependent (~0.3 % of fast producers under an
# 8-way load on Linux, 0 when idle), so it cannot be a deterministic test. What
# IS deterministic is the recovery branch: a `wait` FUNCTION that answers 127
# with bash's "not a child" line, exactly what bash does after the race, while
# the real `builtin wait` still reaps the child. tpipe calls `wait` by name, so
# the function stands in for the race on every call it is defined for.
#
#   A  activation: Linux with /proc on, everything else off (FreeBSD's FIFO
#      procsub, the cygwin branch)
#   B  the EOF path recovers the RC of a function and of a builtin producer
#      when `wait` answers 127, through count / toArray / each / toList, with
#      NOTHING on stderr; a real status from `wait` (0, 143) is kept; a real
#      127 and an `exit 4` stay themselves; an EXTERNAL producer is started as
#      before and keeps wait's 127 (and bash's line). 5.2.37's -1 cannot be
#      faked (a function returns 255 for -1); the load repro covers it.
#   C  the stop path recovers it too (the callback waits until the producer's
#      line is in the pipe, so the producer is certainly done before the kill),
#      and an infinite function producer that the stop ends keeps 141/143 —
#      its EXIT-trap report says 0 and must not win
#   D  the pipe is drained on every close: nothing pending, nothing queued
#   E  nesting: an inner sink that drains the OUTER producer's line keeps it for
#      the outer close; a TPipe inside a producer opens that process's own pipe
#      and the outer status still lands in the outer one
#   F  a subshell opens its OWN pipe (keyed by BASHPID)
#   G  `set -eu` and IFS=':' in the caller change nothing
#   H  guards: the claim rule called directly (-1 and 256 take the report — the
#      only deterministic proof of the 5.2.37 branch — 127 too, a real 3
#      stays); the script's own file on our fd number, after a call and during
#      one, is neither written nor read and a new pipe is opened; a producer
#      that redirects that number gets no line in its log; user functions
#      `printf` / `enable` change nothing; a producer with its own EXIT trap
#      keeps wait's answer and the close says so through `kk.debug`; an
#      inherited `set -e` exit is reported; a failed open is not retried
#
# Off Linux every case after A passes as N/A: the workaround is not active there
# and the plain `wait` path is what 001-006 already test.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$SCRIPT_DIR/.."
source "$TP_DIR/tpipe.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/stderr.txt"

kt_test_section "007: the status pipe (launch L3.5-8)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
p3()     { printf 'a\nb\nc\n'; }
pfail6() { printf 'a\nb\n'; return 6; }
p1rc5()  { printf 'a\n'; return 5; }
p127()   { printf 'a\n'; return 127; }

# the race, simulated: reap for real, then answer like bash after a lost child
fake_wait_on() {
    wait() {
        builtin wait "$@" 2>/dev/null
        printf 'bash: wait: pid %s is not a child of this shell\n' "$1" >&2
        return 127
    }
}
fake_wait_off() { unset -f wait; }

# st_wait_line — wait (bounded: 500 naps of 10 ms, no fork per nap) until a
# line is pending in this process's status pipe; rc 0 when one is. The nap is
# a `read -t 0.01` on an idle pipe of the test's own, opened on first use.
NAPFD=''
st_wait_line() {
    local __k __z
    if [[ -z "$NAPFD" ]]; then
        exec {NAPFD}<> <(:)
    fi
    for (( __k = 0; __k < 500; __k++ )); do
        if read -t 0 -u "$__TPIPE_STFD" 2>/dev/null; then
            return 0
        fi
        read -r -t 0.01 -u "$NAPFD" __z || :
    done
    return 1
}

# st_clean — rc 0 when nothing is pending in the pipe and nothing is queued
st_clean() {
    ! read -t 0 -u "$__TPIPE_STFD" 2>/dev/null && (( ${#__TPIPE_STQ[@]} == 0 ))
}

na() { kt_test_pass "N/A: the status pipe is off here (__TPIPE_ST=$__TPIPE_ST, OSTYPE=$OSTYPE)"; }

# ===========================================================================
kt_test_section "A. activation"
# ===========================================================================

kt_test_start "the status pipe is on exactly on Linux with /proc"
if [[ "$OSTYPE" == linux* && -d /proc/self/fd ]]; then want=1; else want=0; fi
if [[ "$__TPIPE_ST" == "$want" ]]; then
    kt_test_pass "__TPIPE_ST=$__TPIPE_ST on $OSTYPE"
else
    kt_test_fail "__TPIPE_ST=$__TPIPE_ST, expected $want on $OSTYPE"
fi
ON="$__TPIPE_ST"

# ===========================================================================
kt_test_section "B. the EOF path"
# ===========================================================================

kt_test_start "count on a FUNCTION producer: wait says 127, lastRc is the real 6, stderr empty"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    TPipe.count -- pfail6 2>"$ERRF"; rc=$?
    res="$RESULT"
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ "$res" == 2 && $rc -eq 1 && "$lr" == 6 && ! -s "$ERRF" && -n "$__TPIPE_STFD" ]]; then
        kt_test_pass "RESULT 2, rc 1, lastRc 6, no stderr"
    else
        kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' stfd='$__TPIPE_STFD' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "toArray, each and toList on a function producer recover it too"
if [[ "$ON" == 1 ]]; then
    cb_007() { return 0; }
    class TAdd007
        public
            var         N
            constructor Create
            proc        Add
    end
    TAdd007.Create() { N=0; return 0; }
    TAdd007.Add()    { N=$(( N + 1 )); return 0; }
    build TAdd007
    TAdd007.new AD
    fake_wait_on
    GOT=()
    TPipe.toArray GOT -- pfail6 2>"$ERRF"; a_rc=$?; TPipe.lastRc; a_lr="$RESULT"
    TPipe.each cb_007 -- pfail6 2>>"$ERRF"; e_rc=$?; TPipe.lastRc; e_lr="$RESULT"
    TPipe.toList AD -- pfail6 2>>"$ERRF"; l_rc=$?; TPipe.lastRc; l_lr="$RESULT"
    fake_wait_off
    AD.delete
    if [[ $a_rc -eq 1 && "$a_lr" == 6 && "${#GOT[@]}" == 2 && $e_rc -eq 1 && "$e_lr" == 6 \
          && $l_rc -eq 1 && "$l_lr" == 6 && ! -s "$ERRF" ]]; then
        kt_test_pass "toArray / each / toList: rc 1, lastRc 6, no stderr"
    else
        kt_test_fail "toArray rc=$a_rc lr=$a_lr n=${#GOT[@]} / each rc=$e_rc lr=$e_lr / toList rc=$l_rc lr=$l_lr / stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "a BUILTIN producer (printf) is recovered: lastRc 0, rc 0"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    TPipe.count -- printf 'a\nb\n' 2>"$ERRF"; rc=$?
    res="$RESULT"
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ "$res" == 2 && $rc -eq 0 && "$lr" == 0 && ! -s "$ERRF" && -n "${__TPIPE_BI[printf]:-}" ]]; then
        kt_test_pass "RESULT 2, rc 0, lastRc 0; printf is in the builtin set"
    else
        kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' bi='${__TPIPE_BI[printf]:-}' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "a REAL status from wait is kept: the report only fills a lost one"
if [[ "$ON" == 1 ]]; then
    wait() { builtin wait "$@" 2>/dev/null; return 0; }
    TPipe.count -- pfail6 2>"$ERRF"; rc1=$?; TPipe.lastRc; lr1="$RESULT"
    wait() { builtin wait "$@" 2>/dev/null; return 143; }
    TPipe.count -- pfail6 2>>"$ERRF"; rc2=$?; TPipe.lastRc; lr2="$RESULT"
    fake_wait_off
    if [[ $rc1 -eq 0 && "$lr1" == 0 && $rc2 -eq 1 && "$lr2" == 143 && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "wait 0 -> lastRc 0, wait 143 -> lastRc 143 (the report 6 is not used), queue empty"
    else
        kt_test_fail "0: rc=$rc1 lr=$lr1 / 143: rc=$rc2 lr=$lr2 / queue=${#__TPIPE_STQ[@]} stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "a function that really returns 127 still reports 127"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    TPipe.count -- p127 2>"$ERRF"; rc=$?
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == 127 && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "rc 1, lastRc 127, its report line consumed"
    else
        kt_test_fail "rc=$rc lastRc='$lr' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "a function that ends through \`exit 4\` is recovered (the EXIT trap reports it)"
if [[ "$ON" == 1 ]]; then
    pexit4_007() { printf 'a\n'; exit 4; }
    fake_wait_on
    TPipe.count -- pexit4_007 2>"$ERRF"; rc=$?
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == 4 && ! -s "$ERRF" ]]; then
        kt_test_pass "rc 1, lastRc 4"
    else
        kt_test_fail "rc=$rc lastRc='$lr' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "an EXTERNAL producer is started as before: wait's 127 and bash's line stand"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    TPipe.count -- "$BASH" -c 'printf "a\n"; exit 6' 2>"$ERRF"; rc=$?
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == 127 ]] && grep -q 'is not a child' "$ERRF"; then
        kt_test_pass "lastRc 127 (no status line for an exec'd producer), the line on stderr"
    else
        kt_test_fail "rc=$rc lastRc='$lr' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "without the race the real wait answers and nothing is left behind"
if [[ "$ON" == 1 ]]; then
    TPipe.count -- pfail6 2>"$ERRF"; rc=$?
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == 6 && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "lastRc 6, pipe drained, queue empty"
    else
        kt_test_fail "rc=$rc lastRc='$lr' queue=${#__TPIPE_STQ[@]} stderr='$(<"$ERRF")'"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "C. the stop path"
# ===========================================================================

stop_when_done_007() {
    st_wait_line || :
    TPipe.stop
}

kt_test_start "each + stop on a producer that is already done: lastRc is its own 5"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    TPipe.each stop_when_done_007 -- p1rc5 2>"$ERRF"; rc=$?
    res="$RESULT"
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$res" == 1 && "$lr" == 5 && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "rc 0, 1 record, lastRc 5, no stderr, pipe drained"
    else
        kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr' queue=${#__TPIPE_STQ[@]} stderr='$(<"$ERRF")'"
    fi
else
    na
fi

pinf_007() { while :; do printf 'y\n'; done; }

kt_test_start "first on an INFINITE function producer: lastRc 141/143, not the trap's 0"
if [[ "$ON" == 1 ]]; then
    TPipe.first -- pinf_007 2>"$ERRF"; rc=$?
    res="$RESULT"
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$res" == y && ( "$lr" == 141 || "$lr" == 143 ) ]] && st_clean; then
        kt_test_pass "rc 0, RESULT y, lastRc $lr, queue empty"
    else
        kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr' queue=${#__TPIPE_STQ[@]} stderr='$(<"$ERRF")'"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "D. draining"
# ===========================================================================

kt_test_start "200 function-producer calls leave nothing pending and nothing queued"
if [[ "$ON" == 1 ]]; then
    for (( i = 0; i < 200; i++ )); do
        TPipe.count -- p3
    done
    if st_clean; then
        kt_test_pass "pipe empty, queue empty"
    else
        kt_test_fail "queue=${#__TPIPE_STQ[@]} (${!__TPIPE_STQ[*]})"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "E. nesting"
# ===========================================================================

NEST_N=()
nest_cb_007() {
    if [[ "$TPIPE_INDEX" == 1 ]]; then
        st_wait_line || :              # the OUTER producer's line is pending now
        TPipe.count -- p3
        NEST_N+=( "$RESULT" )
        TPipe.count -- printf 'x\n'
        NEST_N+=( "$RESULT" )
    fi
    return 0
}

kt_test_start "an inner sink drains the OUTER line and keeps it: the outer lastRc is 6"
if [[ "$ON" == 1 ]]; then
    NEST_N=()
    fake_wait_on
    TPipe.each nest_cb_007 -- pfail6 2>"$ERRF"; rc=$?
    res="$RESULT"
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$res" == 2 && "$lr" == 6 && "${NEST_N[*]}" == "3 1" && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "outer rc 1, lastRc 6; inner counts 3 and 1; queue empty"
    else
        kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr' inner=(${NEST_N[*]}) queue=${#__TPIPE_STQ[@]} stderr='$(<"$ERRF")'"
    fi
else
    na
fi

pnest_007() {
    local __TPIPE_QUIET=1
    TPipe.count -- p3                  # opens THIS process's own pipe
    printf 'x\n'
    return 6
}

kt_test_start "a TPipe inside the producer: the outer status still reaches the outer pipe"
if [[ "$ON" == 1 ]]; then
    fake_wait_on
    GOT=()
    TPipe.toArray GOT -- pnest_007 2>"$ERRF"; rc=$?
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "${GOT[*]}" == "x" && "$lr" == 6 && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "records (x), lastRc 6"
    else
        kt_test_fail "rc=$rc GOT=(${GOT[*]}) lastRc='$lr' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "F. a subshell opens its own pipe"
# ===========================================================================

kt_test_start "inside \$( ) the pipe belongs to the subshell and the status is recovered"
if [[ "$ON" == 1 ]]; then
    parent_fd="$__TPIPE_STFD"
    out="$(
        __TPIPE_QUIET=1
        fake_wait_on
        TPipe.count -- pfail6 2>/dev/null
        TPipe.lastRc
        own=shared
        if [[ "$__TPIPE_STPID" == "$BASHPID" ]]; then
            own=own
        fi
        printf '%s %s %s' "$RESULT" "$own" "$__TPIPE_STFD"
    )"
    read -r o_lr o_own o_fd <<< "$out"
    if [[ "$o_lr" == 6 && "$o_own" == own && -n "$o_fd" && "$__TPIPE_STPID" == "$BASHPID" ]]; then
        kt_test_pass "lastRc 6 in the subshell, its own pipe (fd $o_fd; parent's fd $parent_fd)"
    else
        kt_test_fail "out='$out'"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "G. the caller's shell options"
# ===========================================================================

kt_test_start "set -eu and IFS=':' in the caller: recovered all the same"
if [[ "$ON" == 1 ]]; then
    out="$(
        set -eu
        IFS=':'
        __TPIPE_QUIET=1
        fake_wait_on
        TPipe.count -- pfail6 2>/dev/null || :
        TPipe.lastRc
        printf '%s' "$RESULT"
    )"; rc=$?
    if [[ $rc -eq 0 && "$out" == 6 ]]; then
        kt_test_pass "lastRc 6 under set -eu, IFS=':'"
    else
        kt_test_fail "rc=$rc out='$out'"
    fi
else
    na
fi

# ===========================================================================
kt_test_section "H. guards: the fd, builtins by name, the rc rule, lost reports"
# ===========================================================================

if [[ "$ON" == 1 && -z "$__TPIPE_STFD" ]]; then
    TPipe.count -- p3                  # the cases below need this shell's pipe
fi

CL_RC=''
# claim_007 WAIT_RC REPORT — write a report line for a made-up pid, run the
# claim as tpipe._close would after a `wait` that answered WAIT_RC; CL_RC = the
# resulting rc
claim_007() {
    local __tpi_sf="$__TPIPE_STFD" __tpi_pid=999991
    builtin printf '%s %s\n' "$__tpi_pid" "$2" >&"$__tpi_sf"
    __TPIPE_RC="$1"
    tpipe._stClaim
    CL_RC="$__TPIPE_RC"
}

kt_test_start "tpipe._stClaim: wait's -1 (5.2.37) and 256 take the report, 127 too, a real 3 stays"
if [[ "$ON" == 1 ]]; then
    claim_007 -1 7;  r1="$CL_RC"
    claim_007 256 8; r2="$CL_RC"
    claim_007 127 5; r3="$CL_RC"
    claim_007 3 9;   r4="$CL_RC"
    if [[ "$r1" == 7 && "$r2" == 8 && "$r3" == 5 && "$r4" == 3 ]] && st_clean; then
        kt_test_pass "-1 -> 7, 256 -> 8, 127 -> 5, 3 stays 3; every line consumed"
    else
        kt_test_fail "-1 -> '$r1', 256 -> '$r2', 127 -> '$r3', 3 -> '$r4', queue=${#__TPIPE_STQ[@]}"
    fi
else
    na
fi

kt_test_start "the script opens its OWN file on our fd number after a call: file intact, a new pipe, rc right"
if [[ "$ON" == 1 ]]; then
    F="$__TPIPE_STFD"
    printf 'l1\nl2\nl3\n' > "$TMP/user.txt"
    cp "$TMP/user.txt" "$TMP/user.orig"
    eval "exec $F<\"\$TMP/user.txt\""
    fake_wait_on
    TPipe.count -- pfail6 2>"$ERRF"; rc=$?
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    NF="$__TPIPE_STFD"
    UG=()
    while IFS= read -r -u "$F" l; do UG+=( "$l" ); done
    eval "exec $F<&-"
    if [[ $rc -eq 1 && "$lr" == 6 && -n "$NF" && "$NF" != "$F" && "${UG[*]}" == "l1 l2 l3" && ! -s "$ERRF" ]] \
       && cmp -s "$TMP/user.txt" "$TMP/user.orig" && st_clean; then
        kt_test_pass "lastRc 6 through fd $NF; fd $F still reads l1 l2 l3; the file unchanged"
    else
        kt_test_fail "rc=$rc lastRc='$lr' old=$F new=$NF read=(${UG[*]}) file='$(<"$TMP/user.txt")' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

own_fd_cb_007() {
    if [[ "$TPIPE_INDEX" == 1 ]]; then
        eval "exec $__TPIPE_STFD<\"\$TMP/user2.txt\""
    fi
    return 0
}

kt_test_start "the fd is taken over DURING a sink: the close reads nothing from the file and forgets the fd"
if [[ "$ON" == 1 ]]; then
    F="$__TPIPE_STFD"
    printf 'm1\nm2\nm3\n' > "$TMP/user2.txt"
    fake_wait_on
    TPipe.each own_fd_cb_007 -- pfail6 2>"$ERRF"; rc=$?
    TPipe.lastRc; lr1="$RESULT"
    UG=()
    while IFS= read -r -u "$F" l; do UG+=( "$l" ); done
    eval "exec $F<&-"
    TPipe.count -- pfail6 2>>"$ERRF"; TPipe.lastRc; lr2="$RESULT"
    fake_wait_off
    if [[ $rc -eq 1 && "$lr1" == 127 && "${UG[*]}" == "m1 m2 m3" && "$lr2" == 6 \
          && -n "$__TPIPE_STFD" && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "lastRc 127 (the report went to the replaced pipe), the file read intact, the next call recovers 6 on a new pipe"
    else
        kt_test_fail "rc=$rc lastRc1='$lr1' read=(${UG[*]}) lastRc2='$lr2' stfd='$__TPIPE_STFD' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "a function producer that redirects our fd number (exec N>log): no status line in its log"
if [[ "$ON" == 1 ]]; then
    F="$__TPIPE_STFD"
    : > "$TMP/plog.txt"
    plog_007() { eval "exec $F>\"\$TMP/plog.txt\""; printf 'a\n'; return 6; }
    TPipe.count -- plog_007 2>"$ERRF"; rc=$?
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$RESULT" == 6 && ! -s "$TMP/plog.txt" && ! -s "$ERRF" ]] && st_clean; then
        kt_test_pass "lastRc 6 (the real wait), the log empty"
    else
        kt_test_fail "rc=$rc lastRc='$lr' log='$(<"$TMP/plog.txt")' stderr='$(<"$ERRF")'"
    fi
else
    na
fi

kt_test_start "user functions named printf and enable change nothing (builtin by name)"
if [[ "$ON" == 1 ]]; then
    out="$(
        __TPIPE_QUIET=1
        __TPIPE_BI=()
        __TPIPE_STPID=''
        printf() { builtin echo HIJACK; }
        enable() { builtin echo "enable bogus_007"; }
        wait() { builtin wait "$@" 2>/dev/null; return 127; }
        pecho6_007() { echo a; echo b; return 6; }
        TPipe.count -- pecho6_007 2>/dev/null
        n="$RESULT"
        TPipe.lastRc
        echo "$n $RESULT ${__TPIPE_BI[read]:-none} ${__TPIPE_BI[bogus_007]:-none}"
    )"
    if [[ "$out" == "2 6 1 none" ]]; then
        kt_test_pass "count 2, lastRc 6, the builtin set is the real one"
    else
        kt_test_fail "out='$out' (want '2 6 1 none')"
    fi
else
    na
fi

kt_test_start "a producer with its OWN EXIT trap writes no report: wait's 127 stays, and kk.debug says so"
if [[ "$ON" == 1 ]]; then
    ptrap_007() { trap ':' EXIT; printf 'a\n'; return 6; }
    fake_wait_on
    VERBOSE_KKLASS=debug TPipe.count -- ptrap_007 2>"$ERRF"; rc=$?
    TPipe.count -- ptrap_007 2>"$TMP/quiet.err"
    fake_wait_off
    TPipe.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == 127 && ! -s "$TMP/quiet.err" ]] \
       && grep -q 'left no status report' "$ERRF" && st_clean; then
        kt_test_pass "lastRc 127; the debug line with the switch on, nothing with it off"
    else
        kt_test_fail "rc=$rc lastRc='$lr' debug-stderr='$(<"$ERRF")' quiet-stderr='$(<"$TMP/quiet.err")'"
    fi
else
    na
fi

kt_test_start "an inherited \`set -e\` that ends the producer early is reported (rc 1 after one record)"
if [[ "$ON" == 1 ]]; then
    out="$(
        set -e
        __TPIPE_QUIET=1
        fake_wait_on
        pseterr_007() { printf 'a\n'; false; printf 'never\n'; }
        TPipe.count -- pseterr_007 2>/dev/null || :
        n="$RESULT"
        TPipe.lastRc
        printf '%s %s' "$n" "$RESULT"
    )"
    if [[ "$out" == "1 1" ]]; then
        kt_test_pass "1 record, lastRc 1 recovered"
    else
        kt_test_fail "out='$out' (want '1 1')"
    fi
else
    na
fi

kt_test_start "a process whose pipe could not be opened does not retry: plain form, wait's answer"
if [[ "$ON" == 1 ]]; then
    out="$(
        __TPIPE_QUIET=1
        __TPIPE_STPID="$BASHPID"           # "tried" ...
        __TPIPE_STFD=''                    # ... and failed
        fake_wait_on
        TPipe.count -- pfail6 2>/dev/null
        TPipe.lastRc
        printf '%s [%s]' "$RESULT" "$__TPIPE_STFD"
    )"
    if [[ "$out" == "127 []" ]]; then
        kt_test_pass "lastRc 127, still no pipe"
    else
        kt_test_fail "out='$out' (want '127 []')"
    fi
else
    na
fi
