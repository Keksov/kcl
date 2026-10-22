#!/usr/bin/env bash
# 006_TreeStop.sh — launch L2.7-P (owner decision DL13): TPipe.stop stops the
# producer's WHOLE process tree, not only the process substitution.
#
# Before DL13 `tpipe._close` TERMed `$!` alone; a function producer runs IN that
# subshell, so its own children were re-parented and lived on (002_Stop.sh's
# `sleep 8` was the gate's STRAY on Linux). The engine now walks the tree on the
# stop path (README §5, the "tree stop" block in tpipe.sh).
#
# How a case proves it: every producer here writes the pid of each descendant
# it starts to a file ("LABEL PID" lines) and, where the case is about a tree
# that EXISTS when the stop happens, prints its first record only once all of
# them are written. After the sink returns, every recorded pid must be gone:
# the CHILD counts the survivors itself (`kill -0`, up to 3 s — cygwin reports
# a dead process alive for up to ~250 ms) and prints `alive=A/N`, because on
# FreeBSD the `timeout` around it is a reaper that would otherwise make a
# missed descendant look gone; the parent polls the same pids again (5 s). The
# descendants are `sleep 60`, so a missed one is unmistakable, and a survivor
# is KILLed by its recorded pid (child, then parent) before the case reports,
# so a regression fails the case without leaving a stray behind.
#
#   A  the tree through every stop path: `first`, `each` + `stop`, `toList`
#      whose `.Add` stops; depth 3 (producer -> subshell -> subshell -> sleep)
#      and background jobs; lastRc stays the producer's 143; nothing on stderr
#   B  a TPipe NESTED inside the producer: the inner producer's tree too
#   C  forks IN FLIGHT: the producer prints the record and forks right after —
#      the race a plain snapshot loses (the freeze on Linux/BSD, the tree
#      token on cygwin)
#   D  a descendant that IGNORES TERM gets SIGKILL after the 1 s grace
#   E  scope: a job the CALLBACK started survives; the EOF path stops nothing
#   F  the caller's shell options: `set -m` off and on (the same answer), and
#      `set -euf`
#   G  the process-table sources: the full-table `linux` backend where the
#      children files make `linuxc` the default (N/A elsewhere), the `ps`
#      backend where `ps -A -o pid= -o ppid=` works (N/A elsewhere, e.g.
#      cygwin's ps has no -o), and `none`, which falls back to TERMing the
#      producer alone (the pre-DL13 behaviour)
#
# Every case runs in a CHILD bash under `timeout`, so a stop path that hangs
# fails the case instead of the suite.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "006: TPipe.stop stops the producer's whole tree (launch L2.7-P, DL13)"

# ---------------------------------------------------------------------------
# The child: $1 = tpipe unit dir, $2 = pid file, $3 = mode. Prints ONE line:
#   rc=N res=R lastrc=L alive=A/N us=U   (A of the N recorded descendants alive)
# ---------------------------------------------------------------------------
CHILD="$TMP/tree_child.sh"
cat > "$CHILD" <<'CHILD_EOF'
#!/usr/bin/env bash
source "$1/tpipe.sh"
PIDF="$2"
case "$3" in
    setm_on)  set -m ;;
    setm_off) set +m ;;
    setef)    set -euf ;;
esac

# wait_lines N — until the pid file holds N lines (10 s at most), so the first
# record is printed only when the whole tree exists and is recorded.
wait_lines() {
    local -a l=()
    local i=0
    while (( i < 200 )); do
        mapfile -t l < "$PIDF"
        if (( ${#l[@]} >= $1 )); then return 0; fi
        sleep 0.05
        i=$(( i + 1 ))
    done
    return 0
}

# is_alive PID — kill -0 sees it and Linux's /proc does not say it is a zombie
# (cygwin's stat state is not trusted here: a process in its exec hand-over can
# read as one): a killed, re-parented process stays a zombie until its new
# parent reaps it (busybox init: about once a second), and it is dead already.
is_alive() {
    local l=''
    kill -0 "$1" 2>/dev/null || return 1
    if [[ "$OSTYPE" != cygwin* && "$OSTYPE" != msys* ]] &&
       { IFS= read -r l < "/proc/$1/stat"; } 2>/dev/null; then
        l="${l##*) }"
        [[ "${l%% *}" != Z ]] || return 1
    fi
    return 0
}

# depth 3 and background jobs: root -> bg sleep; root -> sub -> sleep;
# root -> mid -> deep -> sleep. Six pids, recorded before the record.
tree_producer() {
    exec 2>/dev/null; trap '' PIPE
    sleep 60 & echo "bg $!" >> "$PIDF"
    ( sleep 60 & echo "sub-sleep $!" >> "$PIDF"; echo "sub $BASHPID" >> "$PIDF"; wait ) &
    ( ( sleep 60 & echo "deep-sleep $!" >> "$PIDF"; echo "deep $BASHPID" >> "$PIDF"; wait ); : ) &
    echo "mid $!" >> "$PIDF"
    wait_lines 6
    printf 'a\n'
    wait
    printf 'b\n'
}

# a TPipe inside the producer: the outer stop must reach the INNER producer's tree
inner_prod() { exec 2>/dev/null; trap '' PIPE; sleep 60 & echo "inner-sleep $!" >> "$PIDF"; wait_lines 1; printf 'x\n'; wait; }
relay()      { printf '%s\n' "$1"; }
outer_prod() { exec 2>/dev/null; trap '' PIPE; TPipe.each relay -- inner_prod; }

# the fork happens AFTER the record: the consumer's stop races it
inflight_producer() {
    exec 2>/dev/null; trap '' PIPE
    printf 'a\n'
    ( echo "if-sub $BASHPID" >> "$PIDF"; sleep 60 & echo "if-sleep $!" >> "$PIDF"; wait; : )
    printf 'b\n'
}

# a subtree that ignores TERM (the disposition is inherited by its sleep)
ignterm_producer() {
    exec 2>/dev/null; trap '' PIPE
    ( trap '' TERM; sleep 60 & echo "ign-sleep $!" >> "$PIDF"; echo "ign $BASHPID" >> "$PIDF"; wait ) &
    wait_lines 2
    printf 'a\n'
    wait
}

# leaves a background job behind and ends on its own (stdout detached, so the
# reader still sees EOF)
eof_producer() { exec 2>/dev/null; sleep 60 >/dev/null & echo "left $!" >> "$PIDF"; printf 'a\nb\n'; }

# `yes` on a closed pipe prints "write error"; its own stderr goes, not ours
quiet_yes() { exec 2>/dev/null; exec yes; }

stopper()   { TPipe.stop; return 0; }
cb_job()    { sleep 60 >/dev/null 2>&1 & echo "cb $!" >> "$PIDF"; TPipe.stop; return 0; }
rec()       { return 0; }
stoplist.Add() { TPipe.stop; return 0; }

run_it() { TPipe.first -- tree_producer; }

t0="${EPOCHREALTIME/[.,]/}"
rc=0
case "$3" in
    first|setm_on|setm_off|setef)
                run_it                                 || rc=$? ;;
    each)       TPipe.each stopper -- tree_producer    || rc=$? ;;
    tolist)     TPipe.toList stoplist -- tree_producer || rc=$? ;;
    nested)     TPipe.first -- outer_prod              || rc=$? ;;
    inflight)   for (( k = 0; k < 10; k++ )); do
                    TPipe.first -- inflight_producer   || rc=$?
                done ;;
    ignterm)    TPipe.first -- ignterm_producer        || rc=$? ;;
    cbjob)      TPipe.each cb_job -- quiet_yes         || rc=$? ;;
    eof)        TPipe.each rec -- eof_producer         || rc=$? ;;
    pt_linux)   __TPIPE_PT=linux; run_it               || rc=$? ;;
    pt_ps)      __TPIPE_PT=ps;   run_it                || rc=$? ;;
    pt_none)    __TPIPE_PT=none; run_it                || rc=$? ;;
    *)          printf 'bad mode\n' >&2; exit 9 ;;
esac
res="$RESULT"
t1="${EPOCHREALTIME/[.,]/}"
TPipe.lastRc
# The caller's stderr must still be ITS stderr after a stop: the parent reads
# this line as the LAST one of the child's stderr. No TPipe call here carries
# a `2>/dev/null` — that would restore fd 2 when the call returns and hide a
# permanent redirection inside the stop path (the producers silence their OWN
# stderr instead). After it, the child's stderr goes away: its cleanup below
# kills a job of its own, and bash reports that ("Killed").
printf 'stderr-ok\n' >&2
exec 2>/dev/null
# The recorded descendants are counted HERE, before this script exits, and
# whatever is left is removed by its recorded pid: FreeBSD's timeout(1) is a
# reaper — it waits for, and then kills, everything below it once its command
# ends — so seen from the parent a missed `sleep 60` would only cost 60 s and
# then look gone (measured: 3 x 60 s for the cases that keep survivors).
# Survivor cases count at once; the others give the tree 3 s to die (cygwin
# reports a dead process alive for up to ~250 ms).
n=0; a=0; left=()
mapfile -t lines < "$PIDF"
pids=()
for l in "${lines[@]}"; do pids+=( "${l##* }" ); done
n=${#pids[@]}
case "$3" in
    cbjob|eof|pt_none) end=0 ;;
    *)                 end=$(( ${EPOCHREALTIME/[.,]/} + 3000000 )) ;;
esac
while :; do
    left=()
    for p in "${pids[@]}"; do
        if is_alive "$p"; then left+=( "$p" ); fi
    done
    if (( ${#left[@]} == 0 || ${EPOCHREALTIME/[.,]/} >= end )); then break; fi
    sleep 0.05
done
a=${#left[@]}
# KILLed until gone, 3 s at most: under load the Git runtime loses a signal
# sent while the target is still in its exec hand-over (a KILL included).
end=$(( ${EPOCHREALTIME/[.,]/} + 3000000 ))
while (( ${#left[@]} > 0 && ${EPOCHREALTIME/[.,]/} < end )); do
    kill -KILL "${left[@]}" 2>/dev/null || :
    sleep 0.05
    still=()
    for p in "${left[@]}"; do
        if is_alive "$p"; then still+=( "$p" ); fi
    done
    left=( "${still[@]}" )
done
printf 'rc=%s res=%s lastrc=%s alive=%s/%s us=%s\n' "$rc" "$res" "$RESULT" "$a" "$n" $(( t1 - t0 ))
CHILD_EOF

# run_child MODE -> CH_RC (timeout's rc), CH_OUT (the child's line), PIDF.
# `timeout -k`: a hung stop path must not outlive the case.
run_child() {
    PIDF="$TMP/pids.$1"
    : > "$PIDF"
    CH_OUT="$(timeout -k 10 120 "$BASH" "$CHILD" "$TP_DIR" "$PIDF" "$1" </dev/null 2>"$TMP/err.$1")"
    CH_RC=$?
    return 0
}

# recorded_pids -> REC_PIDS (the pids of $PIDF), REC_DESC ("label pid ...")
recorded_pids() {
    local -a lines=()
    local l
    REC_PIDS=(); REC_DESC=''
    mapfile -t lines < "$PIDF"
    for l in "${lines[@]}"; do
        if [[ "$l" =~ ^([a-z-]+)\ ([0-9]+)$ ]]; then
            REC_PIDS+=( "${BASH_REMATCH[2]}" )
            REC_DESC+="${BASH_REMATCH[1]}=${BASH_REMATCH[2]} "
        fi
    done
    return 0
}

# is_alive PID — as in the child: kill -0, and not a zombie by Linux's /proc
is_alive() {
    local l=''
    kill -0 "$1" 2>/dev/null || return 1
    if [[ "$OSTYPE" != cygwin* && "$OSTYPE" != msys* ]] &&
       { IFS= read -r l < "/proc/$1/stat"; } 2>/dev/null; then
        l="${l##*) }"
        [[ "${l%% *}" != Z ]] || return 1
    fi
    return 0
}

# alive_now -> ALIVE ("pid ..." of the recorded pids still alive, zombies not)
alive_now() {
    local p
    ALIVE=''
    for p in "${REC_PIDS[@]}"; do
        if is_alive "$p"; then ALIVE+="$p "; fi
    done
    ALIVE="${ALIVE% }"
    return 0
}

# gone_within US -> rc 0 when every recorded pid is gone within US µs; ALIVE
# holds the survivors otherwise. The survivors are KILLed (by recorded pid)
# either way, so a failing case leaves nothing behind.
gone_within() {
    local end=$(( ${EPOCHREALTIME/[.,]/} + $1 ))
    recorded_pids
    alive_now
    while [[ -n "$ALIVE" ]] && (( ${EPOCHREALTIME/[.,]/} < end )); do
        sleep 0.05
        alive_now
    done
    if [[ -n "$ALIVE" ]]; then
        kill_until_gone $ALIVE
        return 1
    fi
    return 0
}

# kill_until_gone PID... — SIGKILL, re-sent every 50 ms for up to 3 s until
# none of the PIDs is alive (the Git runtime loses a signal sent during an exec
# hand-over, a KILL included)
kill_until_gone() {
    local -a left=( "$@" ) still=()
    local p end=$(( ${EPOCHREALTIME/[.,]/} + 3000000 ))
    while (( ${#left[@]} > 0 && ${EPOCHREALTIME/[.,]/} < end )); do
        kill -KILL "${left[@]}" 2>/dev/null || :
        sleep 0.05
        still=()
        for p in "${left[@]}"; do
            if is_alive "$p"; then still+=( "$p" ); fi
        done
        left=( "${still[@]}" )
    done
    return 0
}

# kill_recorded — the cleanup of a case that EXPECTS survivors
kill_recorded() {
    recorded_pids
    if (( ${#REC_PIDS[@]} > 0 )); then
        kill_until_gone "${REC_PIDS[@]}"
    fi
    return 0
}

# stderr_ok MODE — rc 0 when the LAST line of the child's stderr is the
# `stderr-ok` it prints after the call: the caller's stderr survived the stop
# (a permanent redirection inside the stop path would swallow it).
stderr_ok() {
    local e
    e="$(< "$TMP/err.$1")"
    [[ "${e##*$'\n'}" == "stderr-ok" ]]
}

# expect_tree_gone TITLE MODE EXPECTED_LINE_GLOB NPIDS
# Also pins SILENCE: the producers' stderr goes to /dev/null inside the child,
# so anything on the child's stderr but its own `stderr-ok` is the shell's or
# TPipe's — a job notice under `set -m`, a "Terminated", a cygwin signal
# message.
expect_tree_gone() {
    local title="$1" mode="$2" want="$3" n="$4" err=''
    kt_test_start "$title"
    run_child "$mode"
    err="$(< "$TMP/err.$mode")"
    if gone_within 5000000; then
        if [[ $CH_RC -eq 0 && "$CH_OUT" == $want && ${#REC_PIDS[@]} -ge $n && "$err" == "stderr-ok" ]]; then
            kt_test_pass "$CH_OUT; ${#REC_PIDS[@]} descendants gone: $REC_DESC"
        else
            kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded=${#REC_PIDS[@]} (want >= $n): $REC_DESC stderr='${err//$'\n'/ | }'"
        fi
    else
        kt_test_fail "ALIVE 5 s after the stop: $ALIVE (recorded: $REC_DESC; child: rc=$CH_RC '$CH_OUT')"
    fi
}

# ===========================================================================
kt_test_section "A. the tree through every stop path"
# ===========================================================================

expect_tree_gone "first: the producer's tree (depth 3, background jobs) is gone; lastRc 143" \
    first "rc=0 res=a lastrc=143 alive=0/* us=*" 6
expect_tree_gone "each + TPipe.stop: the tree is gone, RESULT counts 1 record" \
    each "rc=0 res=1 lastrc=143 alive=0/* us=*" 6
expect_tree_gone "toList whose .Add calls TPipe.stop: the tree is gone" \
    tolist "rc=0 res=1 lastrc=143 alive=0/* us=*" 6

# ===========================================================================
kt_test_section "B. a TPipe nested inside the producer"
# ===========================================================================

expect_tree_gone "the outer stop reaches the INNER producer's tree" \
    nested "rc=0 res=x lastrc=143 alive=0/* us=*" 1

# ===========================================================================
kt_test_section "C. forks in flight when the stop happens"
# ===========================================================================

# Ten calls; each producer forks a subshell (which forks a sleep) right AFTER
# the record that triggers the stop. On cygwin a TERM to a process in the middle
# of a fork is delivered only after the fork completes, and the child is
# re-parented at once — before the tree token, every one of these survived
# (30 of 30, measured on both bashes). A pid the producer had no time to record
# was never born, or is the stray guard's to report.
expect_tree_gone "10 stops racing a fork right after the record: no descendant survives" \
    inflight "rc=0 res=a lastrc=* alive=0/* us=*" 0

# ===========================================================================
kt_test_section "D. a descendant that ignores TERM"
# ===========================================================================

kt_test_start "a TERM-ignoring subtree gets SIGKILL after the 1 s grace"
run_child ignterm
us="${CH_OUT##*us=}"
if gone_within 5000000; then
    if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=a lastrc=143 alive=0/2 us="* && ${#REC_PIDS[@]} -ge 2 \
          && "$us" =~ ^[0-9]+$ ]] && (( us >= 900000 )) && stderr_ok ignterm; then
        kt_test_pass "$CH_OUT (the grace was waited out); gone: $REC_DESC"
    else
        kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' (want us >= 900000) recorded: $REC_DESC"
    fi
else
    kt_test_fail "ALIVE 5 s after the stop: $ALIVE (recorded: $REC_DESC; child: rc=$CH_RC '$CH_OUT')"
fi

# ===========================================================================
kt_test_section "E. scope: only the producer's tree, only on the stop path"
# ===========================================================================

kt_test_start "a job the CALLBACK started is not the producer's and survives the stop"
run_child cbjob
recorded_pids
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=1 lastrc=14"[13]" alive=1/1 us="* ]] && stderr_ok cbjob; then
    kt_test_pass "$CH_OUT; the callback's sleep ${REC_PIDS[0]:-?} was alive after the stop (then removed by the test)"
else
    kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded: $REC_DESC"
fi
kill_recorded

kt_test_start "the EOF path stops nothing: a producer's leftover background job lives on"
run_child eof
recorded_pids
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=2 lastrc=0 alive=1/1 us="* ]] && stderr_ok eof; then
    kt_test_pass "$CH_OUT; the leftover ${REC_PIDS[0]:-?} was alive after the sink (then removed by the test)"
else
    kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded: $REC_DESC"
fi
kill_recorded

# ===========================================================================
kt_test_section "F. the caller's shell options"
# ===========================================================================

# The producer runs from a FUNCTION the caller calls, with job control off and
# on in the caller. A process substitution joins the caller's process group
# either way (no new group, no terminal hand-over): the answer is the same.
expect_tree_gone "set +m in the caller: the tree is gone" \
    setm_off "rc=0 res=a lastrc=143 alive=0/* us=*" 6
SETM_OFF="${CH_OUT% us=*}"
expect_tree_gone "set -m in the caller: the tree is gone" \
    setm_on "rc=0 res=a lastrc=143 alive=0/* us=*" 6
SETM_ON="${CH_OUT% us=*}"

kt_test_start "set -m on and off give the same answer"
if [[ -n "$SETM_OFF" && "$SETM_OFF" == "$SETM_ON" ]]; then
    kt_test_pass "both: $SETM_ON"
else
    kt_test_fail "off: '$SETM_OFF' on: '$SETM_ON'"
fi

# set -e: every step of the walk is a guarded test; set -f: the table is read
# through a glob, which the stop path re-enables for itself (`local -`).
expect_tree_gone "set -euf in the caller: the tree is gone, nothing aborts" \
    setef "rc=0 res=a lastrc=143 alive=0/* us=*" 6

# ===========================================================================
kt_test_section "G. the process-table sources"
# ===========================================================================

# Linux has two sources: the per-process children files (linuxc, the default
# where the kernel has them) and the full /proc/PID/stat table (linux). Where
# linuxc is the default, the full-table path is forced here so both are run.
kt_test_start "the full-table linux backend (every /proc/PID/stat) stops the tree too"
if [[ "$OSTYPE" == cygwin* || "$OSTYPE" == msys* || ! -r "/proc/$$/task/$$/children" ]]; then
    kt_test_pass "N/A: no /proc/PID/task/TID/children here (off Linux, or the full table IS the default)"
else
    run_child pt_linux
    if gone_within 5000000; then
        if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=a lastrc=143 alive=0/6 us="* && ${#REC_PIDS[@]} -ge 6 ]] && stderr_ok pt_linux; then
            kt_test_pass "$CH_OUT; gone: $REC_DESC"
        else
            kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded: $REC_DESC"
        fi
    else
        kt_test_fail "ALIVE 5 s after the stop: $ALIVE (recorded: $REC_DESC; child: rc=$CH_RC '$CH_OUT')"
    fi
fi

kt_test_start "the ps backend (ps -A -o pid= -o ppid=) stops the tree too"
psline=''
if command -v ps >/dev/null 2>&1; then
    psline="$(ps -A -o pid= -o ppid= 2>/dev/null | while read -r a b; do
        if [[ "$a" == "$$" ]]; then printf '%s %s' "$a" "$b"; fi; done)"
fi
if [[ -z "$psline" ]]; then
    kt_test_pass "N/A: this ps cannot list pid/ppid with -A -o (cygwin's ps has no -o)"
else
    run_child pt_ps
    if gone_within 5000000; then
        if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=a lastrc=143 alive=0/6 us="* && ${#REC_PIDS[@]} -ge 6 ]] && stderr_ok pt_ps; then
            kt_test_pass "$CH_OUT; gone: $REC_DESC"
        else
            kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded: $REC_DESC"
        fi
    else
        kt_test_fail "ALIVE 5 s after the stop: $ALIVE (recorded: $REC_DESC; child: rc=$CH_RC '$CH_OUT')"
    fi
fi

# With no process table the stop path is exactly the pre-DL13 one: the
# producer is TERMed (lastRc 143, the call returns), its descendants are not.
kt_test_start "no process table: the producer alone is TERMed (the documented fallback)"
run_child pt_none
recorded_pids
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=a lastrc=143 alive="[1-9]"/6 us="* ]] && stderr_ok pt_none; then
    kt_test_pass "$CH_OUT; descendants left as before DL13 (then removed by the test)"
else
    kt_test_fail "timeout rc=$CH_RC out='$CH_OUT' recorded: $REC_DESC"
fi
kill_recorded
