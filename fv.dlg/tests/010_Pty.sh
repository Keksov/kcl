#!/usr/bin/env bash
# 010_Pty.sh - the command bin/fvdlg on a real pty: util-linux script(1)
# (MSYS2, Cygwin, Linux; ENV / SKIP elsewhere: Git-bash has no script(1),
# macOS / FreeBSD ship a BSD script(1) — fvv_pty's detection). Never this
# terminal. One script(1) session runs the cases one after the other; a
# feeder types each case's keys once its text is on the screen (the
# typescript, flushed per write):
#   * x=$(fvdlg --stdout --inputbox ...), whiptail's swap idiom
#     `x=$(fvdlg --inputbox ... 3>&1 1>&2 2>&3)`, --output-fd 3;
#   * the exit codes: Enter 0, Tab Enter on a yes/no 1, Esc 255, Ctrl+C 130,
#     SIGTERM 143, SIGHUP 129 (P4-12 / P4-13: restored first);
#   * every case: `stty -g` the same before and after, the restore sequences
#     (?25h, ?7h, mouse off, ?2004l; ?1049l on the alternate screen), no
#     process of the case left (its process groups looked up with ps), no
#     P4-6 buffer file left in TMPDIR;
#   * Q3 / D34: one ?1049h per call on the alternate screen (two calls: two),
#     none with --fv-screen main (two calls: none), the main screen's last
#     dialog left with the cursor sent to the last row (ESC [ 24 ; 1 H),
#     --erase-on-exit's clear before the restore; the infobox on the main
#     screen, the cursor on its last row, the script's next line after it;
#     the main screen + Ctrl+C: the cursor sent to the last row by the
#     restore, before the script's next output; too small on the main
#     screen: refused with the screen untouched (no clear, no paint);
#   * NO_COLOR: the dialog without its colours (no blue / cyan / green SGR);
#     TERM=dumb: refused before anything is sent (255, one line);
#     TERM=dumb with FVDLG_FORCE=1: the dialog runs;
#   * P4-6 through the command: a line the process writes to stderr (the
#     terminal) while the UI runs comes after the restore;
#   * a backgrounded `fvdlg ... &` under job control stops (SIGTTOU at its
#     first stty: "Stopped"), `fg` resumes it and it answers (P4-12);
#   * the session bounded whatever a case does (FVDL_PTY_BOUND, default
#     600 s): timed waits, the script(1) side reaped when it does not end,
#     every case process left reaped and named (a failure), its P4-6 buffer
#     files removed; the script side holds no fd of the runner's capture.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
source "$FVDL_TESTS_DIR/../../fv.video/tests/fvv_pty.sh"
ROOT="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)"
CMD=$ROOT/bin/fvdlg
D=${FVDL_PTY_DIR:-$FVW_TMP/pty}   # (FVDL_PTY_DIR: a folder kept for a look at the run)
# (FVDL_PTY_CASES: a subset, for a look at one case; the checks expect all)
# (FVDL_PTY_BOUND: the session's bound in seconds, default 600; FVDL_PTY_FAULT=leak: the
# bound's self-check, a process that outlives the session — 010 must end and fail)
read -r -a CASES <<< "${FVDL_PTY_CASES:-m i s o y e c t h A M C n N d D p b k S}"

TITLES=(
    "x=\$(fvdlg --stdout --inputbox): abc captured, rc 0"
    "whiptail's swap idiom x=\$(fvdlg --inputbox ... 3>&1 1>&2 2>&3): xy captured, rc 0"
    "--output-fd 3 (a menu, Down Enter): b in the file, rc 0"
    "the exit codes: msgbox Enter 0, yesno Tab Enter 1, Esc 255, Ctrl+C 130, SIGTERM 143, SIGHUP 129"
    "every case: stty -g equal before and after"
    "every case that drew: the restore sequences (?25h ?7h mouse off ?2004l), ?1049l where the alternate screen was used"
    "every case: no process left in its process groups, no fvdlg.* buffer file left in TMPDIR"
    "Q3 alternate (default): one ?1049h / ?1049l per call (two calls: two pairs)"
    "Q3 --fv-screen main: no ?1049h in two calls; each ends with the cursor at ESC [ 24 ; 1 H after its dialog, nothing redrawn over it"
    "--erase-on-exit: no ?1049h, the screen cleared (ESC [ H ESC [ 2 J) after the dialog, before the restore"
    "the infobox: rc 0, no ?1049h, no keyboard query, the cursor at ESC [ 24 ; 1 H, the script's next line after it"
    "NO_COLOR: rc 0, the dialog drawn without the blue / cyan / green of FV's palette (the plain run has them)"
    "TERM=dumb: 255 and one line before anything reaches the terminal; FVDLG_FORCE=1: the dialog runs (rc 0)"
    "P4-6 through the command: a stderr line written during the UI lands after the restore"
    "a backgrounded fvdlg under job control: Stopped (SIGTTOU), fg resumes it, Enter answers 0, restored"
    "--fv-screen main + Ctrl+C: 130, the restore (fv.video, noalt) ends with ESC [ 24 ; 1 H after the last frame, before the caller's next output"
    "--fv-screen main on a terminal too small (20x5): 255, 'terminal too small', the screen untouched (no ESC [ 2 J, no paint, the only cursor move the restore's ESC [ 5 ; 1 H)"
    "the session: bounded (FVDL_PTY_BOUND, default 600 s) whatever a case does; every case seen to its end, no feeder abort, the script(1) side ended by itself"
)

# fid ID -> the case's file suffix (U + an upper-case id: the Windows file
# systems ignore case, rc.M would be rc.m)
fid() { if [[ $1 == [ABCDEFGHIJKLMNOPQRSTUVWXYZ] ]]; then printf U%s "$1"; else printf %s "$1"; fi; }

run_all() {
    rm -rf "$D"
    mkdir -p "$D"
    # the P4-6 child: kbool + fv.dlg loaded first, getEvent wrapped to write
    # one line to stderr, then bin/fvdlg SOURCED (its load is then a no-op:
    # the command's own path with the wrapped event source)
    {
        printf 'source %q || exit 99\nkk.uses fv.dlg || exit 98\n' "$ROOT/kbool.sh"
        cat <<'EOF'
src=$(declare -f fv.drivers.getEvent); eval "__o_ge${src#fv.drivers.getEvent}"
__said=0
fv.drivers.getEvent() { if (( ! __said )); then __said=1; printf 'MSG-DURING-UI\n' >&2; fi; __o_ge "$@"; }
EOF
        printf 'source %q --msgbox %q 0 0\n' "$CMD" 'Qp7 replay'
    } > "$D/p46.sh"
    {
        printf 'CL=%q B=%q F=%q D=%q FAULT=%q\n' "${CASES[*]}" "$BASH" "$CMD" "$D" "${FVDL_PTY_FAULT-}"
        cat <<'EOF'
cd "$D" || exit 89
printf '%s' "$$" > wpid
printf '%s' "$PPID" > spid
trap : INT QUIT TSTP
stty rows 24 cols 80 2>/dev/null
XPG=''
# procs PGID... -> "PID COMMAND" of the processes in those groups but this
# shell and ps
procs() {
    local pid ppid pgid rest g hit
    case $OSTYPE in
        cygwin*|msys*) ps > ps.tmp 2>/dev/null ;;
        *) ps -e -o pid= -o ppid= -o pgid= -o args= > ps.tmp 2>/dev/null ;;
    esac
    while read -r pid ppid pgid rest; do
        [[ $pid == "$$" || $pid == PID ]] && continue
        hit=0
        for g; do [[ -n $g && $pgid == "$g" ]] && hit=1; done
        (( hit )) || continue
        [[ $rest == */ps || $rest == 'ps '* ]] && continue
        printf '%s %s\n' "$pid" "$rest"
    done < ps.tmp
}
mypg() {
    local pid ppid pgid rest
    PG=''
    procs x > /dev/null
    while read -r pid ppid pgid rest; do if [[ $pid == "$$" ]]; then PG=$pgid; fi; done < ps.tmp
}
# nbuf -> REPLY = the P4-6 buffer files in TMPDIR (fvdlg.PID.N.N, + .u)
nbuf() { local f; REPLY=0; for f in "${TMPDIR:-/tmp}"/fvdlg.[0123456789]*.*; do [[ -e $f ]] && REPLY=$(( REPLY + 1 )); done; }
case_m() { "$B" "$F" --msgbox 'Qm7 hello from the pty' 0 0; rc=$?; }
case_i() { x=$("$B" "$F" --stdout --inputbox 'Qi7 name:' 0 0); rc=$?; printf '%s' "$x" > val.i; }
case_s() { x=$("$B" "$F" --inputbox 'Qs7 name:' 0 0 3>&1 1>&2 2>&3); rc=$?; printf '%s' "$x" > val.s; }
case_o() { "$B" "$F" --output-fd 3 --menu 'Qo7 pick' 0 0 0 a Apple b Banana 3> val.o; rc=$?; }
case_y() { "$B" "$F" --yesno 'Qy7 sure?' 0 0; rc=$?; }
case_e() { "$B" "$F" --yesno 'Qe7 sure?' 0 0; rc=$?; }
case_c() { "$B" "$F" --yesno 'Qc7 sure?' 0 0; rc=$?; }
case_t() { "$B" -c 'printf %s "$$" > pid.t; exec "$0" "$@"' "$B" "$F" --yesno 'Qt7 sure?' 0 0; rc=$?; }
case_h() { "$B" -c 'printf %s "$$" > pid.h; exec "$0" "$@"' "$B" "$F" --yesno 'Qh7 sure?' 0 0; rc=$?; }
case_A() { "$B" "$F" --msgbox 'QA7 one of two' 0 0; rc=$?; "$B" "$F" --msgbox 'QB7 two of two' 0 0; rc+=$?; }
case_M() { "$B" "$F" --fv-screen main --msgbox 'QM7 one of two' 0 0; rc=$?; "$B" "$F" --fv-screen main --msgbox 'QN7 two of two' 0 0; rc+=$?; }
case_C() { "$B" "$F" --erase-on-exit --msgbox 'QC7 erased' 0 0; rc=$?; }
case_n() { "$B" "$F" --infobox 'Qn7 please wait' 0 0; rc=$?; printf 'AFTER-INFO\n'; }
case_N() { NO_COLOR=1 "$B" "$F" --msgbox 'QK7 no colour' 0 0; rc=$?; }
case_d() { TERM=dumb "$B" "$F" --msgbox 'Qd7' 0 0 2> err.d; rc=$?; }
case_D() { TERM=dumb FVDLG_FORCE=1 "$B" "$F" --msgbox 'QD7 forced' 0 0; rc=$?; }
case_p() { "$B" p46.sh; rc=$?; }
case_k() { "$B" "$F" --fv-screen main --inputbox 'Qk7 main input' 0 0; rc=$?; printf 'NEXT-OUTPUT\n'; }
case_S() { printf 'QS7-BEFORE\n'; stty rows 5 cols 20; "$B" "$F" --fv-screen main --yesno 'QS7 a long question text here' 0 0 2> err.US; rc=$?; stty rows 24 cols 80; }
# (job control in an interactive child shell, as a user's shell has it: it
# takes the terminal, puts the job in its own group, gives the terminal
# back at its exit; `set -m` in this wrapper would leave the foreground
# group)
case_b() {
    "$B" --norc --noprofile -i -c '
        printf "%s" "$$" > ipid
        "$0" "$1" --msgbox "Qb7 from the background" 0 0 > b.out 2> b.err &
        printf "%s" "$!" > bgpid
        n=0
        while (( n++ < 150 )); do
            jobs -l > jobs.b 2>&1
            IFS= read -r -d "" s < jobs.b
            [[ $s == *Stopped* ]] && break
            sleep 0.1
        done
        cp jobs.b bgstate
        fg %1 > /dev/null 2>&1
        exit $?' "$B" "$F" 2> bi.err
    rc=$?
    XPG=$(cat bgpid 2>/dev/null)
}
# (FVDL_PTY_FAULT=leak: a stand-in for a case that never ends — a process of
# the wrapper's group that ignores HUP / INT / TERM and outlives the session;
# the check of the session's bound: 010 must still end, reap it and fail)
if [[ $FAULT == leak ]]; then "$B" -c 'trap "" HUP INT TERM; while :; do sleep 1; done' fault "$F" & fi
mypg
printf '%s' "$PG" > pg
for c in $CL; do
    f=$c; if [[ $c == [ABCDEFGHIJKLMNOPQRSTUVWXYZ] ]]; then f=U$c; fi
    XPG=''
    stty -g > "before.$f" 2>&1
    nbuf; b0=$REPLY
    printf 'CASE-%s-START\n' "$c"
    rc=''
    "case_$c"
    printf 'CASE-%s-END\n' "$c"
    printf '%s' "$rc" > "rc.$f"
    stty -g > "after.$f" 2>&1
    n=0
    while (( n++ < 30 )); do
        procs "$PG" "$XPG" > "surv.$f"
        [[ -s surv.$f ]] || break
        sleep 0.1
    done
    nbuf; printf "%s" "$(( REPLY - b0 ))" > "buf.$f"
    : > "done.$f"
done
: > done
EOF
    } > "$D/wrap.sh"

    # the feeder: per case, wait for its text on the screen, type, wait for
    # its end
    # The session is bounded whatever a case does (stage 4b: an MSYS2 gate
    # cell hung for 30 min, its log empty: case k's dialog never saw its keys,
    # the feeder's waits were counted in sleeps — a fork each, minutes under
    # load —, and the dialog, left alive after the session, held the runner's
    # capture of this file open). Every wait is timed (SECONDS) and the whole
    # feed ends by FEED_END (FVDL_PTY_BOUND s, default 600; the script side's
    # timeout is 40 s longer); the feeder's last step waits for the script(1)
    # side and reaps it when it does not end; after the session every
    # recorded process and what is left in the case groups is reaped (and
    # named: a failure), with the P4-6 buffer files of the reaped. The script
    # side runs with every fd but 0 / 1 / 2 closed: no case process can hold
    # the runner's capture (stdout / stderr, FVW_ERRFD), which `$(...)` reads
    # to its end
    FEED_END=$(( SECONDS + ${FVDL_PTY_BOUND:-600} ))
    # alive PID -> rc 0 when PID runs (kill -0, not a zombie in /proc)
    alive() {
        local s=''
        [[ -n $1 ]] && kill -0 "$1" 2>/dev/null || return 1
        if [[ -r /proc/$1/stat ]] && { IFS= read -r s < "/proc/$1/stat"; } 2>/dev/null; then s=${s##*) }; [[ $s != Z* ]]; fi
    }
    # late -> " (the session bound ... passed)" once FEED_END is reached
    late() { if (( SECONDS >= FEED_END )); then printf ' (the session bound, %s s, passed)' "${FVDL_PTY_BOUND:-600}"; fi; }
    # fw FILE SECONDS -> rc 0 once FILE exists (timed; FEED_END too)
    fw() {
        local end=$(( SECONDS + $2 ))
        while (( SECONDS < end && SECONDS < FEED_END )); do
            if [[ -e $1 ]]; then return 0; fi
            sleep 0.05
        done
        [[ -e $1 ]]
    }
    # the feeder: per case, wait for its text on the screen, type, wait for
    # its end
    # (each wait generous — a loaded Windows host forks slowly —; the
    # session's bound caps their sum)
    ts_has() {   # TEXT -> rc 0 once the typescript holds it (60 s)
        local s end=$(( SECONDS + 60 ))
        while (( SECONDS < end && SECONDS < FEED_END )); do
            s=''
            { IFS= read -r -d '' s || :; } 2>/dev/null < "$D/ts"
            if [[ $s == *"$1"* ]]; then return 0; fi
            sleep 0.1
        done
        printf 'feeder: no [%s]%s\n' "$1" "$(late)" >> "$D/feeder.log"
        feed_abort
        return 1
    }
    # feed_abort — a case that never showed up or never ended: the wrapper
    # and the recorded case processes killed, so the session ends now
    # (script(1) closes the pty); what is left is reaped after the session
    feed_abort() {
        local p
        FEED_ABORT=1
        for p in bgpid pid.t pid.h ipid wpid; do
            if [[ -s $D/$p ]]; then kill -KILL "$(<"$D/$p")" 2>/dev/null; fi
        done
    }
    # feed_tail — the script(1) side (tpid: the timeout running script) must
    # end once the session has: up to 60 s (after an abort too), then the
    # session is aborted and 20 s more, then script and the timeout reaped
    feed_tail() {
        local t end
        t=$(cat "$D/tpid" 2>/dev/null)
        end=$(( SECONDS + 60 ))
        while (( SECONDS < end )); do alive "$t" || return 0; sleep 0.1; done
        if [[ -z $FEED_ABORT ]]; then
            printf 'feeder: the session did not end after its last case\n' >> "$D/feeder.log"
            feed_abort
            end=$(( SECONDS + 20 ))
            while (( SECONDS < end )); do alive "$t" || return 0; sleep 0.1; done
        fi
        printf 'feeder: the script(1) side still ran after the session: reaped\n' >> "$D/feeder.log"
        if [[ -s $D/spid ]] && alive "$(<"$D/spid")"; then fvp_reap "$(<"$D/spid")"; fi
        fvp_reap "$t"
    }
    feed() {
        local c FEED_ABORT=''
        for c in "${CASES[@]}"; do
            case $c in
                m) ts_has Qm7 && printf '\r' ;;
                i) ts_has Qi7 && printf 'abc\r' ;;
                s) ts_has Qs7 && printf 'xy\r' ;;
                o) ts_has Qo7 && printf '\e[B\r' ;;
                y) ts_has Qy7 && printf '\t\r' ;;
                e) ts_has Qe7 && printf '\e' ;;
                c) ts_has Qc7 && printf '\003' ;;
                t) ts_has Qt7 && kill -TERM "$(<"$D/pid.t")" ;;
                h) ts_has Qh7 && kill -HUP "$(<"$D/pid.h")" ;;
                A) ts_has QA7 && printf '\r' && ts_has QB7 && printf '\r' ;;
                M) ts_has QM7 && printf '\r' && ts_has QN7 && printf '\r' ;;
                C) ts_has QC7 && printf '\r' ;;
                N) ts_has QK7 && printf '\r' ;;
                D) ts_has QD7 && printf '\r' ;;
                p) ts_has Qp7 && printf '\r' ;;
                b)
                    if fw "$D/bgstate" 60; then ts_has Qb7 && printf '\r'
                    else printf 'feeder: no bgstate%s\n' "$(late)" >> "$D/feeder.log"; feed_abort; fi ;;
                k) ts_has Qk7 && printf 'ab' && sleep 0.3 && printf '\003' ;;
                S) : ;;
            esac
            if [[ -n $FEED_ABORT ]]; then break; fi
            fw "$D/done.$(fid "$c")" 120 || { printf 'feeder: no done.%s%s\n' "$c" "$(late)" >> "$D/feeder.log"; feed_abort; break; }
        done
        if [[ -z $FEED_ABORT ]] && ! fw "$D/done" 60; then printf 'feeder: no done%s\n' "$(late)" >> "$D/feeder.log"; fi
        feed_tail
    }
    # (the script side: its pid first — exec keeps it —, then every fd but
    # 0 / 1 / 2 closed: /proc/self/fd, else /dev/fd; the glob's own fd fails)
    feed | {
        printf '%s' "$BASHPID" > "$D/tpid"
        for n in /proc/self/fd/* /dev/fd/*; do
            n=${n##*/}
            if [[ $n == *[!0123456789]* || $n == [012] ]]; then continue; fi
            { exec {n}>&-; } 2>/dev/null || :
        done
        export SHELL=$BASH TERM=xterm-256color
        exec "$KT_TIMEOUT" -k 5 $(( ${FVDL_PTY_BOUND:-600} + 40 )) "$FVP_SCRIPT" -qfec "'$BASH' '$D/wrap.sh'" "$D/ts"
    } > "$D/script.out" 2>&1
    # unbuf PID -> REPLY = how many P4-6 buffer files of PID (fvdlg.PID.*,
    # the name it makes) were left in TMPDIR; they are removed
    unbuf() {
        local f
        REPLY=0
        for f in "${TMPDIR:-/tmp}/fvdlg.$1".*; do if [[ -e $f ]]; then rm -f -- "$f"; REPLY=$(( REPLY + 1 )); fi; done
    }
    # reap PID NAME — PID ended for sure: TERM (a dialog restores, removes
    # its buffer), up to 2 s, then fvp_reap (KILL, taskkill); NAME is a
    # survivor, with the buffer files it left
    reap() {
        local end=$(( SECONDS + 2 ))
        kill -TERM "$1" 2>/dev/null
        while alive "$1" && (( SECONDS < end )); do sleep 0.1; done
        if alive "$1"; then fvp_reap "$1"; fi
        unbuf "$1"
        if (( REPLY )); then printf '%s (buffer files left: %s)\n' "$2" "$REPLY" >> "$D/survivors"; else printf '%s\n' "$2" >> "$D/survivors"; fi
    }
    local p q s g hit
    local -a G=() L=()
    for p in wpid ipid pid.t pid.h bgpid spid tpid; do
        if [[ -s $D/$p ]] && alive "$(<"$D/$p")"; then reap "$(<"$D/$p")" "$p"; fi
    done
    # (a dialog that feed_abort killed outright left its buffer)
    for p in pid.t pid.h bgpid; do
        if [[ -s $D/$p ]]; then unbuf "$(<"$D/$p")"; if (( REPLY )); then printf '%s: buffer files left: %s\n' "$p" "$REPLY" >> "$D/survivors"; fi; fi
    done
    # what is left in the case groups (the wrapper's, the background job's,
    # the interactive shell's: the fvdlg calls, their readers and watchdogs),
    # from /proc (MSYS2's ps does not list every process): a process counts
    # only when its command line names this run (D or bin/fvdlg) — never
    # another run's process that has the same pgid number
    for p in pg bgpid ipid; do if [[ -s $D/$p ]]; then G+=("$(<"$D/$p")"); fi; done
    if (( ${#G[@]} )) && [[ -r /proc/self/stat ]]; then
        for q in /proc/[0123456789]*; do
            q=${q#/proc/}
            [[ $q == *[!0123456789]* || $q == "$BASHPID" || $q == "$$" ]] && continue
            s=''
            { IFS= read -r s < "/proc/$q/stat"; } 2>/dev/null || continue
            s=${s##*) } s=${s#* } s=${s#* } s=${s%% *}   # (state ppid PGRP ...)
            hit=0
            for g in "${G[@]}"; do [[ -n $g && $s == "$g" ]] && hit=1; done
            (( hit )) || continue
            L=()
            { mapfile -d '' L < "/proc/$q/cmdline"; } 2>/dev/null || L=()
            s=${L[*]}
            [[ $s == *"$D/"* || $s == *"$CMD"* ]] || continue
            alive "$q" && reap "$q" "group process $q: ${s:0:80}"
        done
    fi

    local LC_ALL=C ts c s n
    { IFS= read -r -d '' ts || :; } < "$D/ts"
    ts=${ts//$'\r'/}
    declare -gA SEG=() RC=() SAME=()
    for c in "${CASES[@]}"; do
        s=${ts#*"CASE-$c-START"}
        SEG[$c]=${s%%"CASE-$c-END"*}
        if [[ $ts != *"CASE-$c-END"* ]]; then SEG[$c]=''; fi
        RC[$c]=$(cat "$D/rc.$(fid "$c")" 2>/dev/null)
        local b a
        b=$(cat "$D/before.$(fid "$c")" 2>/dev/null) a=$(cat "$D/after.$(fid "$c")" 2>/dev/null)
        if [[ -n $b && $b == "$a" ]]; then SAME[$c]=1; else SAME[$c]=0; fi
    done
    if [[ -s $D/feeder.log ]]; then kt_test_log "010 feeder: $(tr '\n' ' ' < "$D/feeder.log")"; fi
    # cnt CASE SEQ -> REPLY = how often SEQ occurs in the case's segment
    cnt() { local x=${SEG[$1]} y; y=${x//"$2"/}; REPLY=$(( (${#x} - ${#y}) / ${#2} )); }
    # restored CASE ALT -> rc 0 when the segment holds the restore sequences
    restored() {
        local x=${SEG[$1]} bad=''
        [[ $x == *$'\e[?25h'* ]] || bad+=' ?25h'
        [[ $x == *$'\e[?7h'* ]] || bad+=' ?7h'
        [[ $x == *$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'* ]] || bad+=' mouse-off'
        [[ $x == *$'\e[?2004l'* ]] || bad+=' ?2004l'
        if [[ $2 == 1 && $x != *$'\e[?1049l'* ]]; then bad+=' ?1049l'; fi
        if [[ $2 == 0 && $x == *$'\e[?1049'* ]]; then bad+=' ?1049-on-main'; fi
        REPLY=$bad
        [[ -z $bad ]]
    }

    kt_test_start "${TITLES[0]}"
    if [[ ${RC[i]} == 0 && $(cat "$D/val.i" 2>/dev/null) == abc ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[i]} [$(cat "$D/val.i" 2>/dev/null)]"; fi
    kt_test_start "${TITLES[1]}"
    if [[ ${RC[s]} == 0 && $(cat "$D/val.s" 2>/dev/null) == xy ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[s]} [$(cat "$D/val.s" 2>/dev/null)]"; fi
    kt_test_start "${TITLES[2]}"
    if [[ ${RC[o]} == 0 && $(cat "$D/val.o" 2>/dev/null) == b ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[o]} [$(cat "$D/val.o" 2>/dev/null)]"; fi
    kt_test_start "${TITLES[3]}"
    s="${RC[m]} ${RC[y]} ${RC[e]} ${RC[c]} ${RC[t]} ${RC[h]}"
    if [[ $s == '0 1 255 130 143 129' ]]; then kt_test_pass "$s"; else kt_test_fail "$s"; fi
    kt_test_start "${TITLES[4]}"
    s=''; for c in "${CASES[@]}"; do (( SAME[$c] )) || s+=" $c"; done
    if [[ -z $s ]]; then kt_test_pass "${#CASES[@]} cases"; else kt_test_fail "differ:$s"; fi
    kt_test_start "${TITLES[5]}"
    s=''
    for c in m i s o y e c t h A N D p b; do restored "$c" 1 || s+=" $c:$REPLY"; done
    for c in M C n k S; do restored "$c" 0 || s+=" $c:$REPLY"; done
    if [[ -z $s ]]; then kt_test_pass ok; else kt_test_fail "$s"; fi
    kt_test_start "${TITLES[6]}"
    s=''
    for c in "${CASES[@]}"; do
        if [[ -s $D/surv.$(fid "$c") ]]; then s+=" $c:[$(tr '\n' ';' < "$D/surv.$(fid "$c")")]"; fi
        if [[ $(cat "$D/buf.$(fid "$c")" 2>/dev/null) != 0 ]]; then s+=" $c:buf=$(cat "$D/buf.$(fid "$c")" 2>/dev/null)"; fi
    done
    if [[ -e $D/survivors ]]; then s+=" reaped:$(tr '\n' ' ' < "$D/survivors")"; fi
    if [[ -z $s ]]; then kt_test_pass ok; else kt_test_fail "$s"; fi
    kt_test_start "${TITLES[7]}"
    cnt A $'\e[?1049h'; a=$REPLY
    cnt A $'\e[?1049l'; b=$REPLY
    cnt m $'\e[?1049h'; n=$REPLY
    if [[ ${RC[A]} == 00 && $a == 2 && $b == 2 && $n == 1 ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[A]} ?1049h $a ?1049l $b (msgbox: $n)"; fi
    kt_test_start "${TITLES[8]}"
    cnt M $'\e[?1049h'; a=$REPLY
    x=${SEG[M]#*QM7} y=${SEG[M]#*QN7}
    x=${x%%QN7*}
    if [[ ${RC[M]} == 00 && $a == 0 && $x == *$'\e[24;1H'* && $y == *$'\e[24;1H'* && $y != *$'\e[2J'* && $y != *'QM7'* ]]; then kt_test_pass ok
    else kt_test_fail "rc ${RC[M]} ?1049h $a tail1 [$(printf '%q' "${x: -60}")] tail2 [$(printf '%q' "${y: -80}")]"; fi
    kt_test_start "${TITLES[9]}"
    cnt C $'\e[?1049h'; a=$REPLY
    y=${SEG[C]#*QC7}
    if [[ ${RC[C]} == 0 && $a == 0 && $y == *$'\e[H\e[2J'*$'\e[?2004l'* ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[C]} ?1049h $a tail [$(printf '%q' "${y: -80}")]"; fi
    kt_test_start "${TITLES[10]}"
    cnt n $'\e[?1049h'; a=$REPLY
    y=${SEG[n]#*Qn7}
    if [[ ${RC[n]} == 0 && $a == 0 && ${SEG[n]} != *$'\e[c'* && $y == *$'\e[24;1H'*'AFTER-INFO'* ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[n]} ?1049h $a tail [$(printf '%q' "${y: -80}")]"; fi
    kt_test_start "${TITLES[11]}"
    # (FV's gray dialog: blue / cyan / green in its buttons and frame icons;
    # the colours as fv.video sends them: 16-colour SGR or 256-colour 38;5 / 48;5)
    local re1=$'\e\\[([0-9]+;)*(3[2346]|4[2346]|9[2346]|10[2346])(;[0-9]+)*m' re2=$'\e\\[([0-9]+;)*[34]8;5;([2346]|1[0246])(;[0-9]+)*m'
    col() { [[ $1 =~ $re1 || $1 =~ $re2 ]]; }
    a=0 b=0
    if col "${SEG[m]}"; then a=1; fi
    if col "${SEG[N]}"; then b=1; fi
    if [[ ${RC[N]} == 0 && $a == 1 && $b == 0 ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[N]} colours: plain $a, NO_COLOR $b"; fi
    kt_test_start "${TITLES[12]}"
    e=$(cat "$D/err.d" 2>/dev/null)
    if [[ ${RC[d]} == 255 && $e == 'fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)' && ${SEG[d]} != *$'\e'* && ${RC[D]} == 0 ]]; then kt_test_pass ok
    else kt_test_fail "rc ${RC[d]} [$e] esc in seg: $([[ ${SEG[d]} == *$'\e'* ]] && echo yes || echo no) forced rc ${RC[D]}"; fi
    kt_test_start "${TITLES[13]}"
    y=${SEG[p]##*$'\e[?1049l'}
    if [[ ${RC[p]} == 0 && $y == *MSG-DURING-UI* && ${SEG[p]%%$'\e[?1049l'*} != *MSG-DURING-UI* ]]; then kt_test_pass ok; else kt_test_fail "rc ${RC[p]} after [$(printf '%q' "${y:0:80}")]"; fi
    kt_test_start "${TITLES[14]}"
    s=$(cat "$D/bgstate" 2>/dev/null)
    if [[ ${RC[b]} == 0 && $s == *Stopped* ]]; then kt_test_pass "${s//$'\n'/ }"; else kt_test_fail "rc ${RC[b]} jobs [$s] err [$(cat "$D/b.err" 2>/dev/null)]"; fi
    kt_test_start "${TITLES[15]}"
    # (before the next output: after the restore's last mode reset (?2004l,
    # the cursor shape's ESC [ 0 SP q may follow) only the move, no frame)
    x=${SEG[k]%%NEXT-OUTPUT*} y=${SEG[k]##*$'\e[?2004l'}
    y=${y%%NEXT-OUTPUT*}
    if [[ ${RC[k]} == 130 && ${SEG[k]} == *NEXT-OUTPUT* && $x == *$'\e[24;1H' && ( $y == $'\e[24;1H' || $y == $'\e[0 q\e[24;1H' ) ]]; then kt_test_pass ok
    else kt_test_fail "rc ${RC[k]} tail [$(printf '%q' "${x: -80}")]"; fi
    kt_test_start "${TITLES[16]}"
    e=$(cat "$D/err.US" 2>/dev/null)
    x=${SEG[S]#*QS7-BEFORE} y=''
    y=${x//$'\e[5;1H'/}
    local re3=$'\e''\[[0-9]*;?[0-9]*[Hf]'
    if [[ ${RC[S]} == 255 && $e == 'fvdlg: terminal too small'* && $x == *$'\e[5;1H'* && $x != *$'\e[2J'* && $x != *'░'* && $x != *'╔'* && ! $y =~ $re3 ]]; then kt_test_pass "${e}"
    else kt_test_fail "rc ${RC[S]} err [$e] seg [$(printf '%q' "${x:0:200}")]"; fi
    kt_test_start "${TITLES[17]}"
    if [[ ! -s $D/feeder.log ]]; then kt_test_pass "${#CASES[@]} cases"; else kt_test_fail "$(tr '\n' ' ' < "$D/feeder.log")"; fi
}

if fvp_detect; then run_all; else for t in "${TITLES[@]}"; do kt_test_start "$t"; kt_test_pass "SKIP: $FVP_WHY"; done; fi

kt_test_log "010_Pty.sh completed"
