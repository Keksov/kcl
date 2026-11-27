#!/usr/bin/env bash
# 005_Output.sh - where the answer goes (design §3.2, D32 / D37) and P4-6:
#   * THE GOLDEN TABLE's output rows (whiptail 0.52.25 / dialog
#     1.3-20250116, p4/golden): the command's face writes the answer to
#     stderr by default, stdout with --stdout, fd N with --output-fd N,
#     --stderr explicit; ONCE, without a trailing newline; nothing on any fd
#     for 1 / 255 and for the boxes without an answer;
#   * the bash face prints nothing unless asked (RESULT always), the same
#     status; a closed --output-fd is refused (255, one line, RESULT and
#     FV_DLG_CMD '');
#   * the command's face end to end in a child bash (keys from a file through
#     the real fv.drivers): stderr, --stdout, --output-fd 3, whiptail's swap
#     idiom `x=$(... 3>&1 1>&2 2>&3)`;
#   * P4-6: stderr (and stdout) that is the terminal is buffered while the UI
#     runs and replayed after it, before the answer; the buffer file is made
#     under umask 077 in TMPDIR and removed; the caller's EXIT trap is back
#     after; a process that dies during the UI (exit, INT, TERM, HUP) still
#     replays it, then runs the caller's EXIT handler once; inside $( ) the
#     parent's handler runs once, in the parent only (the EXIT trap); a
#     stderr that is a file is never buffered (a message lands at once);
#     the caller's FV_APP_HEADLESS=1 is honoured. "Is the terminal" goes through fv.dlg._isTerm, replaced here
#     (no terminal in the test shell; the pty runs are 4b's 010).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
UNIT="$(cd "$FVDL_TESTS_DIR/.." && pwd)/fv.dlg.sh"
TMP=$FVW_TMP

# outs SPEC... -- ARG... : fv.dlg.main in a subshell with the scripted events;
# O_RC, O_OUT, O_ERR, O_FD3 (the bytes of each fd, '' when nothing)
outs() {
    local -a specs=()
    while (( $# )) && [ "$1" != -- ]; do specs+=("$1"); shift; done
    shift
    fvdl_events "${specs[@]}"
    ( fv.dlg.main --fv-headless "$@" ) >"$TMP/o.out" 2>"$TMP/o.err" 3>"$TMP/o.fd3"
    O_RC=$?
    fva_noevents
    __FV_VW_EOF=0
    { IFS= read -r -d "" O_OUT || :; } < "$TMP/o.out"; { IFS= read -r -d "" O_ERR || :; } < "$TMP/o.err"; { IFS= read -r -d "" O_FD3 || :; } < "$TMP/o.fd3"
}
# grow ID WHIPTAIL DIALOG RC OUT ERR FD3 SPEC... -- ARG... — a golden output row
grow() {
    local id=$1 wt=$2 dg=$3 rc=$4 out=$5 err=$6 fd3=$7
    shift 7
    outs "$@"
    kt_test_start "golden $id (whiptail: $wt; dialog: $dg)"
    if [[ $O_RC == "$rc" && $O_OUT == "$out" && $O_ERR == "$err" && $O_FD3 == "$fd3" ]]; then kt_test_pass "rc $O_RC out [$O_OUT] err [$O_ERR] fd3 [$O_FD3]"
    else kt_test_fail "rc $O_RC out [$O_OUT] err [$O_ERR] fd3 [$O_FD3]; want rc $rc out [$out] err [$err] fd3 [$fd3]"; fi
}

kt_test_section "005: the golden table's output rows (the command's face)"
grow in_abc      'stderr abc' 'stderr abc' 0 '' abc '' 'char a' 'char b' 'char c' 'key kbEnter' -- --inputbox 'Name:' 8 40
grow in_init     'stderr init' 'stderr init' 0 '' init '' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
grow in_tab1     'stderr init' 'stderr init' 0 '' init '' 'key kbTab' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
grow in_tab2     'rc 1, nothing' 'rc 1, nothing' 1 '' '' '' 'key kbTab' 'key kbTab' 'key kbEnter' -- --inputbox 'Name:' 8 40 init
grow in_esc      '255, nothing' '255, nothing' 255 '' '' '' 'char a' 'key kbEsc' -- --inputbox 'Name:' 8 40 init
grow in_stdout   'unknown option, rc 1' 'stdout val' 0 val '' '' 'key kbEnter' -- --stdout --inputbox 'Name:' 8 40 val
grow in_fd3      'fd 3 val' 'fd 3 val' 0 '' '' val 'key kbEnter' -- --output-fd 3 --inputbox 'Name:' 8 40 val
grow in_stderr   'unknown option, rc 1' 'stderr val' 0 '' val '' 'key kbEnter' -- --stderr --inputbox 'Name:' 8 40 val
grow in_nocancel 'stderr val' 'stderr val' 0 '' val '' 'key kbTab' 'key kbEnter' -- --nocancel --inputbox 'Name:' 8 40 val
grow in_00       'stderr val' 'stderr val' 0 '' val '' 'key kbEnter' -- --inputbox 'Name:' 0 0 val
grow in_empty    'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --inputbox 'Name:' 8 40
grow in_spaces   "stderr '  a b  '" "stderr '  a b  '" 0 '' '  a b  ' '' 'key kbEnter' -- --inputbox 'Name:' 8 40 '  a b  '
grow in_cyr      'stderr жк (UTF-8)' 'stderr жк' 0 '' 'жк' '' 'char ж' 'char к' 'key kbEnter' -- --inputbox 'Name:' 8 40
grow pw_abc2     'stderr abc' 'stderr abc' 0 '' abc '' 'char a' 'char b' 'char c' 'key kbEnter' -- --passwordbox 'Password:' 8 40
grow pw_init     'stderr sec' 'stderr sec' 0 '' sec '' 'key kbEnter' -- --passwordbox 'Password:' 8 40 sec
grow pw_esc      '255, nothing' '255, nothing' 255 '' '' '' 'char p' 'key kbEsc' -- --passwordbox 'Password:' 8 40
grow msg_enter   'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --msgbox 'Hello world' 8 30
grow msg_esc     '255, nothing' '255, nothing' 255 '' '' '' 'key kbEsc' -- --msgbox 'Hello world' 8 30
grow msg_stdout  'unknown option, rc 1' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --stdout --msgbox Hello 8 30
grow yn_enter    'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --yesno 'Proceed?' 8 30
grow yn_tab      'rc 1, nothing' 'rc 1, nothing' 1 '' '' '' 'key kbTab' 'key kbEnter' -- --yesno 'Proceed?' 8 30
grow yn_defno    'rc 1, nothing' 'rc 1, nothing' 1 '' '' '' 'key kbEnter' -- --defaultno --yesno 'Proceed?' 8 30
grow info        'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' -- --infobox 'Please wait' 8 30
grow msg_unknown "'--bogus: unknown option' rc 1" "'Unknown option --bogus.' 255" 255 '' $'fvdlg: unknown option \'--bogus\'\n' '' -- --bogus --msgbox Hello 8 30
grow msg_missing 'usage, 255' 'Expected ... tokens, 255' 255 '' $'fvdlg: \'--msgbox\' needs TEXT HEIGHT WIDTH (got 2 of 3)\n' '' -- --msgbox Hello 8
grow msg_onlytitle 'usage, 255' 'rc 0, nothing' 255 '' $'fvdlg: no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist, --gauge, --textbox)\n' '' -- --title T
grow msg_realnl  'rc 0, nothing (two lines shown)' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --msgbox $'one\ntwo' 10 30
grow msg_long    'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --msgbox 'The quick brown fox jumps over the lazy dog and keeps running far past the end of this box' 0 0
grow yn_00       'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' 'key kbEnter' -- --yesno 'Proceed?' 0 0
grow info_00     'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' -- --infobox 'Please wait' 0 0
grow info_clear  'rc 0, nothing' 'rc 0, nothing' 0 '' '' '' -- --clear --infobox 'Please wait' 8 30
grow pw_abc      'no rc: a timing artefact of the run (rerun pw_abc2: stderr abc)' 'stderr pw' 0 '' pw '' 'char p' 'char w' 'key kbEnter' -- --passwordbox 'Password:' 8 40

kt_test_section "005: the bash face, the fds"
kt_test_start "fv.dlg.run prints nothing (RESULT holds the answer); --stdout / --output-fd print as the command does"
fvdl_events 'key kbEnter'; a=$( fv.dlg.run --fv-headless --inputbox N 0 0 v 2>&1 ); ra=$?
fvdl_events 'key kbEnter'; b=$( fv.dlg.run --fv-headless --stdout --inputbox N 0 0 v 2>/dev/null ); rb=$?
fvdl_events 'key kbEnter'; c=$( fv.dlg.run --fv-headless --output-fd 4 --inputbox N 0 0 v 4>&1 >/dev/null 2>/dev/null ); rc=$?
fvdl_events 'key kbEnter'; fv.dlg.run --fv-headless --inputbox N 0 0 v; rr=$? r=$RESULT
fva_noevents; __FV_VW_EOF=0
if [[ $ra == 0 && -z $a && $rb == 0 && $b == v && $rc == 0 && $c == v && $rr == 0 && $r == v ]]; then kt_test_pass ok
else kt_test_fail "[$ra:$a] [$rb:$b] [$rc:$c] [$rr:$r]"; fi
kt_test_start "a closed --output-fd: 255 and one line (after the dialog), RESULT kept"
outs 'key kbEnter' -- --output-fd 9 --inputbox N 0 0 v
if [[ $O_RC == 255 && -z $O_OUT && $O_ERR == $'fvdlg: cannot write the result to fd 9\n' ]]; then kt_test_pass ok; else kt_test_fail "rc $O_RC out [$O_OUT] err [$O_ERR]"; fi
kt_test_start "a closed --output-fd, the bash face: 255, RESULT '' and FV_DLG_CMD '' (as for every 255)"
fvdl_run 'key kbEnter' -- --output-fd 9 --inputbox N 0 0 v 2>"$TMP/cfd.err"
e=$(<"$TMP/cfd.err")
if [[ $FVDL_RC == 255 && -z $FVDL_RES && -z $FVDL_CMD && $e == 'fv.dlg.run: cannot write the result to fd 9' ]]; then kt_test_pass ok
else kt_test_fail "rc $FVDL_RC RESULT [$FVDL_RES] CMD [$FVDL_CMD] err [$e]"; fi

kt_test_section "005: the caller's FV_APP_HEADLESS=1 (fv.app's convention)"
printf 'abc\r' > "$TMP/hl.keys"
kt_test_start "FV_APP_HEADLESS=1 with the caller's FV_KEY_FD / FV_VIDEO_OUT_FD / FV_SCREEN_W/H: honoured (no --fv-headless; the box on the 60 x 20 screen, the frames in the caller's file)"
(
    fva_noevents
    exec {k}<"$TMP/hl.keys" {o}>"$TMP/hl.out"
    # (the box taken at the first event: the screen as the dialog runs)
    src=$(declare -f fv.drivers.getEvent); eval "__hl_${src}"
    BOX=''
    fv.drivers.getEvent() { if [[ -z $BOX ]]; then fvdl_snap; fvdl_box; BOX=$REPLY; fi; __hl_fv.drivers.getEvent "$@"; }
    FV_APP_HEADLESS=1 FV_KEY_FD=$k FV_VIDEO_OUT_FD=$o FV_SCREEN_W=60 FV_SCREEN_H=20
    fv.dlg.run --inputbox N 0 0 2>"$TMP/hl.err"
    r=$?
    printf '%s|%s|%s|%s|%s' "$r" "$RESULT" "$BOX" "$FV_APP_HEADLESS" "$(<"$TMP/hl.err")" > "$TMP/hl.res"
)
hl=$(<"$TMP/hl.res") hs=$(( $(wc -c < "$TMP/hl.out") ))
if [[ $hl == '0|abc|17 6 43 14|1|' && $hs -gt 100 ]]; then kt_test_pass "$hl ($hs bytes of frames)"
else kt_test_fail "[$hl] frames $hs bytes"; fi

kt_test_section "005: the command's face in a child bash (keys from a file)"
printf 'abc\r' > "$TMP/abc.keys"
printf '\t\t\r' > "$TMP/cancel.keys"
child() { "$BASH" -c 'source "$1"; shift; fv.dlg.main "$@"' _ "$UNIT" --fv-headless "$@"; }
child --fv-keys "$TMP/abc.keys" --inputbox 'Name:' 0 0 >"$TMP/c.out" 2>"$TMP/c.err"; r1=$? o1=$(<"$TMP/c.out") e1=$(<"$TMP/c.err")
x=$(child --fv-keys "$TMP/abc.keys" --stdout --inputbox 'Name:' 0 0 2>/dev/null); r2=$?
y=$(child --fv-keys "$TMP/abc.keys" --inputbox 'Name:' 0 0 old 3>&1 1>&2 2>&3); r3=$?
child --fv-keys "$TMP/cancel.keys" --output-fd 3 --inputbox 'Name:' 0 0 old 3>"$TMP/c.fd3" 2>"$TMP/c.err2"; r4=$? f4=$(<"$TMP/c.fd3") e4=$(<"$TMP/c.err2")
kt_test_start "stderr; x=\$(fvdlg --stdout ...); whiptail's swap x=\$(... 3>&1 1>&2 2>&3); Cancel writes nothing"
if [[ $r1 == 0 && -z $o1 && $e1 == abc && $r2 == 0 && $x == abc && $r3 == 0 && $y == abc && $r4 == 1 && -z $f4 && -z $e4 ]]; then kt_test_pass ok
else kt_test_fail "[$r1:$o1:$e1] [$r2:$x] [$r3:$y] [$r4:$f4:$e4]"; fi

kt_test_section "005: P4-6, output during the UI"
mkdir -p "$TMP/t"
# p46 MODE SPEC... -- ARG... : fv.dlg.main in a subshell, TMPDIR=$TMP/t,
# fv.dlg._isTerm saying yes for the fds in MODE ("2", "1", "12", ""); an
# event 'run say' writes "warn" to stderr and "note" to stdout, and records
# in SEEN what the real files held at that moment. P_RC P_OUT P_ERR P_SEEN
# P_LEFT (files left in $TMP/t) P_TRAP (the EXIT trap after, as `trap -p`)
p46() {
    local mode=$1
    shift
    local -a specs=()
    while (( $# )) && [ "$1" != -- ]; do specs+=("$1"); shift; done
    shift
    fvdl_events "${specs[@]}"
    local pe=$TMP/p.err po=$TMP/p.out   # (read while the subshell writes them)
    # (the group: the shell's own "Terminated" / "Hangup" notice for the
    # subshell killed by a signal goes nowhere)
    { (
        TMPDIR=$TMP/t
        fv.dlg._isTerm() { [[ $mode == *"$1"* ]]; }
        say() {
            printf 'warn\n' >&2
            printf 'note\n'
            printf '%s/%s' "$(( $(wc -c < "$pe") ))" "$(( $(wc -c < "$po") ))" > "$TMP/p.seen"
        }
        die() { exit 7; }
        sig() { kill -"$SIG" "$BASHPID"; }
        trap 'echo "mytrap:$?" >> "$TMP/p.mark"' EXIT
        fv.dlg.main --fv-headless "$@"
        r=$?
        trap -p EXIT > "$TMP/p.trap"
        exit "$r"
    ) >"$TMP/p.out" 2>"$TMP/p.err"; } 2>/dev/null
    P_RC=$?
    fva_noevents
    __FV_VW_EOF=0
    P_OUT=$(<"$TMP/p.out") P_ERR=$(<"$TMP/p.err") P_SEEN=$(<"$TMP/p.seen") P_TRAP=$(cat "$TMP/p.trap" 2>/dev/null)
    P_MARK=$(cat "$TMP/p.mark" 2>/dev/null)
    P_LEFT=$(ls -A "$TMP/t")
    rm -f "$TMP/p.seen" "$TMP/p.trap" "$TMP/p.mark"
}
p46 2 'run say' 'char a' 'key kbEnter' -- --inputbox N 0 0
kt_test_start "stderr the terminal: buffered while the UI runs, replayed after it, then the answer; the file removed; the EXIT trap back"
if [[ $P_RC == 0 && $P_SEEN == 0/5 && $P_ERR == $'warn\na' && $P_OUT == note && -z $P_LEFT && $P_TRAP == *mytrap* ]]; then kt_test_pass ok
else kt_test_fail "rc $P_RC seen [$P_SEEN] err [$P_ERR] out [$P_OUT] left [$P_LEFT] trap [$P_TRAP]"; fi
p46 '' 'run say' 'char a' 'key kbEnter' -- --inputbox N 0 0
kt_test_start "stderr a file: never buffered (the message lands at once)"
if [[ $P_RC == 0 && $P_SEEN == 5/5 && $P_ERR == $'warn\na' && -z $P_LEFT ]]; then kt_test_pass ok
else kt_test_fail "rc $P_RC seen [$P_SEEN] err [$P_ERR] left [$P_LEFT]"; fi
p46 12 'run say' 'key kbEnter' -- --msgbox t 0 0
kt_test_start "stdout and stderr the terminal: both buffered, replayed to stderr in their order"
if [[ $P_RC == 0 && $P_SEEN == 0/0 && $P_ERR == $'warn\nnote' && -z $P_OUT && -z $P_LEFT ]]; then kt_test_pass ok
else kt_test_fail "rc $P_RC seen [$P_SEEN] err [$P_ERR] out [$P_OUT] left [$P_LEFT]"; fi
p46 1 'run say' 'key kbEnter' -- --msgbox t 0 0
kt_test_start "stdout alone the terminal: replayed to stdout"
if [[ $P_RC == 0 && $P_SEEN == 5/0 && $P_ERR == warn && $P_OUT == note && -z $P_LEFT ]]; then kt_test_pass ok
else kt_test_fail "rc $P_RC seen [$P_SEEN] err [$P_ERR] out [$P_OUT] left [$P_LEFT]"; fi
kt_test_start "after a normal call the caller's EXIT handler runs once, at the caller's own exit"
if [[ $P_MARK == 'mytrap:0' ]]; then kt_test_pass ok; else kt_test_fail "marks [$P_MARK]"; fi
p46 2 'run say' 'run die' -- --msgbox t 0 0
kt_test_start "the process dies during the UI (exit 7): the EXIT trap replays the buffer, removes the file, then runs the caller's EXIT handler once with \$? 7; rc 7"
if [[ $P_RC == 7 && $P_ERR == warn && -z $P_LEFT && $P_MARK == 'mytrap:7' ]]; then kt_test_pass ok
else kt_test_fail "rc $P_RC err [$P_ERR] left [$P_LEFT] marks [$P_MARK]"; fi
# (headless: no fv.video traps, bash's own death by the signal runs the EXIT
# trap; the caller's handler sees the $? bash gives it, 0 here as without
# fv.dlg. On a terminal fv.video's INT / TERM / HUP handler runs the EXIT
# trap's text: the pty check)
for SIG in INT TERM HUP; do
    case $SIG in INT) n=130 ;; TERM) n=143 ;; *) n=129 ;; esac
    p46 2 'run say' 'run sig' -- --msgbox t 0 0
    kt_test_start "SIG$SIG during the UI (headless): replayed, removed, the caller's EXIT handler once; rc $n"
    if [[ $P_RC == "$n" && $P_ERR == warn && -z $P_LEFT && $P_MARK == 'mytrap:0' ]]; then kt_test_pass "marks [$P_MARK]"
    else kt_test_fail "rc $P_RC err [$P_ERR] left [$P_LEFT] marks [$P_MARK]"; fi
done

kt_test_start "P4-6 under set -e with no rm on PATH: the buffer's rm fails quietly, the call goes on (rc 0)"
mkdir -p "$TMP/t2"
printf '\r' > "$TMP/e.keys"
se=$("$BASH" -c 'set -e; source "$1"; fv.dlg._isTerm() { return 0; }; TMPDIR=$2; PATH=""
    fv.dlg.main --fv-headless --fv-keys "$3" --msgbox t 0 0; echo "rc=$?"' _ "$UNIT" "$TMP/t2" "$TMP/e.keys" 2>&1)
rm -f "$TMP/t2/"fvdlg.*
if [[ $se == 'rc=0' ]]; then kt_test_pass ok; else kt_test_fail "[$se]"; fi

kt_test_start "P4-6 inside \$( ) with a parent EXIT trap: the parent's handler runs once, in the parent, after its last command (never inside the substitution)"
rm -f "$TMP/h1.mark"
fvdl_events 'key kbEnter'
(
    TMPDIR=$TMP/t
    fv.dlg._isTerm() { return 0; }
    trap 'echo "P:$BASHPID" >> "$TMP/h1.mark"' EXIT
    x=$(fv.dlg.main --fv-headless --stdout --inputbox N 0 0 val)
    echo "after:$x:$BASHPID" >> "$TMP/h1.mark"
) 2>/dev/null
fva_noevents; __FV_VW_EOF=0
mapfile -t hm < "$TMP/h1.mark"
if [[ ${#hm[@]} == 2 && ${hm[0]} == after:val:* && ${hm[1]} == "P:${hm[0]##*:}" && -z $(ls -A "$TMP/t") ]]; then kt_test_pass "${hm[*]}"
else kt_test_fail "marks [${hm[*]}] left [$(ls -A "$TMP/t")]"; fi
kt_test_start "the bash face never buffers"
fvdl_events 'run say2' 'key kbEnter'
say2() { SEEN2=$(( $(wc -c < "$TMP/q.err") )); printf 'warn\n' >&2; }
( fv.dlg._isTerm() { return 0; }; TMPDIR=$TMP/t; fv.dlg.run --fv-headless --msgbox t 0 0; echo "$SEEN2" > "$TMP/q.seen" ) 2>"$TMP/q.err"
fva_noevents; __FV_VW_EOF=0
q=$(<"$TMP/q.err") qs=$(<"$TMP/q.seen")
if [[ $q == warn && -z $(ls -A "$TMP/t") ]]; then kt_test_pass ok; else kt_test_fail "err [$q] left [$(ls -A "$TMP/t")]"; fi

kt_test_log "005_Output.sh completed"
