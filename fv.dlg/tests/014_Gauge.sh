#!/usr/bin/env bash
# 014_Gauge.sh - --gauge TEXT H W [PERCENT] (stage 4d, design §4.3 / §5.1,
# R7): the percentages read from stdin while the dialog runs.
#   * the protocol (fv.dlg._gLine, line by line): a number line sets the
#     percentage (blanks around it, leading zeros), clamped 0..100 (250 ->
#     100, -5 -> 0); garbage lines ignored ("12abc", "", "4 2"); CRLF; an
#     XXX block: its next line the percentage, the lines up to the closing
#     XXX the new prompt (newline-joined, `\n` escapes applied), taken at
#     the closing XXX; a block whose percentage line is not a number keeps
#     the percentage; PERCENT on the command line clamped; not an integer
#     refused;
#   * headless runs (the real event loop, stdin a process substitution):
#     the keyboard read paces Idle (keys from a pipe that stays open: Idle
#     polls stdin), a writer that flushes `4` and later `2\n` gives 42 (no
#     lost digit, no 4 shown), CRLF lines, the end of stdin -> rc 0 cmOK,
#     nothing printed, RESULT ''; the keyboard's end of input (a key file
#     that ran out) does not end a gauge: stdin read to its end, rc 0;
#     Esc during a slow writer -> 255 at once (the dialog stays responsive
#     while stdin is idle); redraw only on change (the same percentage
#     three times: one meter redraw; the same prompt again: no text
#     redraw); every writer / key process ended with the test;
#   * the screen: the box, the prompt from cell 2 of row 1, the meter on
#     the row above the bottom frame (████░░░ 42%), the meter in the static
#     text's colour, --fv-ascii (#:), the auto size (40 wide at least), a
#     resize lays it out again (the meter follows);
#   * stdin a terminal (the _isTerm seam; the real pty in the last section):
#     255 and one line before any screen change (no frame written); stdin
#     closed: 255; the host application: refused; a session: works;
#     --no-tty=default without a terminal: stdin read to its end, rc 0;
#   * the command bin/fvdlg in a pipeline: `printf ... | fvdlg --gauge`;
#   * on a real pty (MSYS2 / Cygwin / Linux; util-linux script(1), ENV
#     elsewhere): stdin the terminal -> 255 + one line and nothing sent to
#     the terminal; stdin a pipe -> the gauge drawn, rc 0, the terminal
#     restored; Ctrl+C during a gauge -> 130, restored, no process left.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
TMP=$FVW_TMP
ROOT="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)"
CMD=$ROOT/bin/fvdlg

# ---- the protocol, line by line --------------------------------------------------
# lines LINE... -> REPLY = "pct|text|blk" after feeding the lines to a fresh
# gauge state (percentage 0, prompt P)
lines() {
    local l
    __FV_DL_G=([pct]=0 [spct]=0 [text]=P [ntext]=0 [blk]=0 [bpct]='' [btxt]='' [bn]=0)
    local -A __fvl_o=()
    for l; do fv.dlg._gLine "$l"; done
    REPLY="${__FV_DL_G[pct]}|${__FV_DL_G[text]}|${__FV_DL_G[blk]}"
}
pl() {
    local title=$1 want=$2
    shift 2
    lines "$@"
    kt_test_start "protocol: $title"
    if [[ $REPLY == "$want" ]]; then kt_test_pass "$REPLY"; else kt_test_fail "got [$REPLY] want [$want]"; fi
}

kt_test_section "014: the protocol"
pl "a number line" '42|P|0' 42
pl "the last number wins" '70|P|0' 10 40 70
pl "blanks and a tab around, leading zeros" '7|P|0' $' \t007  '
pl "more than 100 -> 100, many digits too" '100|P|0' 250
pl "a long number -> 100" '100|P|0' 000000000000000000099999999999
pl "a negative number -> 0" '0|P|0' 50 -5
pl "garbage ignored (12abc, empty, '4 2', +5, 1.5)" '30|P|0' 30 12abc '' '4 2' +5 1.5
pl "CRLF: the CR dropped" '55|P|0' $'55\r'
pl "XXX block: percentage and a two-line prompt, \\n escapes" $'60|Copying a\nb\nc|0' XXX 60 'Copying a\nb' c XXX
pl "XXX with CRLF lines" $'61|new|0' $'XXX\r' $'61\r' $'new\r' $'XXX\r'
pl "XXX block, the percentage line not a number: kept" '20|T2|0' 20 XXX abc T2 XXX
pl "XXX block, an empty prompt" '33||0' XXX 33 XXX
pl "an XXX prefix line is a marker (dialog's rule)" '44|T|0' 'XXXstart' 44 T 'XXX end'
pl "an open block changes nothing yet" '10|P|2' 10 XXX 90 'half'
pl "lower-case xxx is garbage" '10|P|0' 10 xxx 90x

kt_test_start "PERCENT on the command line: parsed, not an integer refused (255, one line)"
fvdl_parse --gauge t 0 0 42; p1=$REPLY
fvdl_parse --gauge t 0 0; p2=$REPLY
fvdl_parse --gauge t 0 0 4x; p3=$REPLY
fvdl_parse --gauge t 0 0 -7; p4=$REPLY
if [[ $p1 == '0|gauge|t|0|0|42||' && $p2 == '0|gauge|t|0|0||' && $p3 == "1|PERCENT must be an integer (got '4x')" && $p4 == '0|gauge|t|0|0|-7||' ]]; then kt_test_pass ok
else kt_test_fail "[$p1] [$p2] [$p3] [$p4]"; fi

# ---- headless runs ----------------------------------------------------------------
# grun KEYS WRITER ARG... — fv.dlg.run --fv-headless --fv-out $TMP/g.out ARG...
# with stdin from the function WRITER (a process substitution) and the keys
# from the function KEYS (a process substitution; '' = no --fv-keys: the
# keyboard's input ends at once). G_RC G_CMD G_RES G_ERR G_PCT G_POLLS
# G_SHOWS G_TSHOWS G_MS (the call's time), G_LEFT (a writer / key process
# still alive after the call and a wait: named)
grun() {
    local kf=$1 wf=$2 t0 p i
    shift 2
    rm -f "$TMP/kp" "$TMP/sp"
    : > "$TMP/g.out"
    t0=$EPOCHREALTIME
    if [[ -n $kf ]]; then
        fv.dlg.run --fv-headless --fv-out "$TMP/g.out" --fv-keys <(printf '%s' "$BASHPID" > "$TMP/kp"; "$kf" 2>/dev/null) "$@" \
            < <(printf '%s' "$BASHPID" > "$TMP/sp"; "$wf" 2>/dev/null) 2>"$TMP/g.err"
    else
        fv.dlg.run --fv-headless --fv-out "$TMP/g.out" "$@" < <(printf '%s' "$BASHPID" > "$TMP/sp"; "$wf" 2>/dev/null) 2>"$TMP/g.err"
    fi
    G_RC=$? G_CMD=$FV_DLG_CMD G_RES=$RESULT
    G_MS=$(( (${EPOCHREALTIME/[.,]/} - ${t0/[.,]/}) / 1000 ))
    G_ERR=$(<"$TMP/g.err")
    G_PCT=${__FV_DL_G[pct]-} G_POLLS=${__FV_DL_G[polls]-} G_SHOWS=${__FV_DL_G[shows]-} G_TSHOWS=${__FV_DL_G[tshows]-}
    G_LEFT=''
    for p in kp sp; do
        [[ -s $TMP/$p ]] || continue
        p=$(<"$TMP/$p")
        for (( i = 0; i < 100; i++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.05; done
        if kill -0 "$p" 2>/dev/null; then G_LEFT+="$p "; kill -KILL "$p" 2>/dev/null; fi
    done
    __FV_VW_EOF=0
}
# pcts -> REPLY = the meter percentages the frame file shows, in order
pcts() {
    local LC_ALL=C s r=''
    s=$(<"$TMP/g.out")
    while [[ $s =~ \ ([\ 0-9][\ 0-9][0-9])%(.*) ]]; do r+="${BASH_REMATCH[1]// /} "; s=${BASH_REMATCH[2]}; done
    REPLY=$r
}
k_open() { sleep 2.5; }
k_esc() { sleep 0.6; printf '\033'; }
w_42() { printf '10\n'; sleep 0.3; printf 4; sleep 0.4; printf '2\n'; sleep 0.3; }
w_crlf() { printf '15\r\n'; sleep 0.2; printf 'XXX\r\n65\r\nCRLF text\r\nXXX\r\n'; sleep 0.2; }
w_slow() { printf '30\n'; sleep 1.4; printf '90\n'; }
w_same() { printf '42\n'; sleep 0.2; printf '42\n'; sleep 0.2; printf ' 42\n'; sleep 0.2; printf 'XXX\n42\nGo\nXXX\n'; sleep 0.2; }
w_fast() { printf '5\n'; printf 4; sleep 0.3; printf '7\n80\n'; }
w_end() { printf '25\n'; }

kt_test_section "014: headless runs"
grun k_open w_42 --gauge 'Copying...' 0 0
pcts; p=$REPLY
kt_test_start "Idle polls stdin while the keys stay open; '4' then later '2\\n' gives 42 (no 4 shown); the end of stdin: rc 0 cmOK, RESULT '', nothing printed"
if [[ $G_RC == 0 && $G_CMD == cmOK && -z $G_RES && -z $G_ERR && $G_PCT == 42 && $p == '0 10 42 ' && $G_POLLS -gt 5 && -z $G_LEFT ]]; then kt_test_pass "frames: $p polls $G_POLLS, ${G_MS} ms"
else kt_test_fail "rc $G_RC $G_CMD [$G_RES] err [$G_ERR] pct $G_PCT frames [$p] polls $G_POLLS left [$G_LEFT]"; fi

kt_test_start "the gauge ends at stdin's end, not at the keys' (it returned before the key pipe closed)"
if (( G_MS < 2300 )); then kt_test_pass "${G_MS} ms"; else kt_test_fail "${G_MS} ms (the key pipe stays open 2.5 s)"; fi

grun k_open w_crlf --gauge 'Start' 8 50 5
pcts; p=$REPLY
kt_test_start "CRLF lines and an XXX block with CRLF: 15, then 65 and the new prompt"
if [[ $G_RC == 0 && $G_PCT == 65 && $p == '5 15 65 ' && ${__FV_DL_G[text]} == 'CRLF text' && $G_TSHOWS == 1 && -z $G_LEFT ]]; then kt_test_pass "frames: $p"
else kt_test_fail "rc $G_RC pct $G_PCT frames [$p] text [${__FV_DL_G[text]}] tshows $G_TSHOWS left [$G_LEFT]"; fi

grun '' w_fast --gauge 'No keys' 0 0
pcts; p=$REPLY
kt_test_start "the keyboard's end of input (no key file) does not end a gauge: stdin read to its end (partial line kept), rc 0 cmOK"
if [[ $G_RC == 0 && $G_CMD == cmOK && $G_PCT == 80 && $p == *' 80 ' && $p != *' 4 '* && $p != *' 47 '* && -z $G_ERR && -z $G_LEFT ]]; then kt_test_pass "frames: $p"
else kt_test_fail "rc $G_RC $G_CMD pct $G_PCT frames [$p] err [$G_ERR] left [$G_LEFT]"; fi

grun k_esc w_slow --gauge 'Slow' 0 0
kt_test_start "Esc during a slow writer: 255 at once (the dialog stays responsive while stdin is idle), 30 shown, the writer ended"
if [[ $G_RC == 255 && $G_CMD == cmCancel && $G_PCT == 30 && -z $G_ERR && -z $G_LEFT ]] && (( G_MS < 1300 )); then kt_test_pass "${G_MS} ms"
else kt_test_fail "rc $G_RC $G_CMD pct $G_PCT ${G_MS} ms err [$G_ERR] left [$G_LEFT]"; fi

grun k_open w_same --gauge 'Go' 0 0
kt_test_start "redraw only on change: 42 three times (separate polls) -> one meter redraw; the same prompt again -> no text redraw"
if [[ $G_RC == 0 && $G_SHOWS == 1 && $G_TSHOWS == 0 && $G_POLLS -gt 3 && -z $G_LEFT ]]; then kt_test_pass "shows $G_SHOWS tshows $G_TSHOWS polls $G_POLLS"
else kt_test_fail "rc $G_RC shows $G_SHOWS tshows $G_TSHOWS polls $G_POLLS left [$G_LEFT]"; fi

kt_test_start "an idle gauge polls at the keyboard read's pace (FV_IDLE_TIMEOUT 0.05 s): about 20 polls a second, not a busy loop"
grun k_open w_slow --gauge 'Pace' 0 0
# (1.4 s of idle stdin: ~28 polls at 0.05 s; a busy loop would make thousands)
if [[ $G_RC == 0 ]] && (( G_POLLS >= 5 && G_POLLS <= 60 )); then kt_test_pass "$G_POLLS polls in ${G_MS} ms"
else kt_test_fail "rc $G_RC polls $G_POLLS in ${G_MS} ms"; fi

# ---- the screen ------------------------------------------------------------------
# the snap is taken at each change shown (fv.dlg._gShow wrapped)
src=$(declare -f fv.dlg._gShow)
eval "__o_gShow${src#fv.dlg._gShow}"
fv.dlg._gShow() { __o_gShow; fvdl_snap; }
w_42only() { printf '42\n'; }
grun '' w_42only --gauge 'Copying files' 6 50
fvdl_box; b=$REPLY
fvdl_find 'Copying files'; t=$REPLY
fvdl_row 13; r13=$REPLY
fvdl_find ' 42%'; m=$REPLY
kt_test_start "the box 6 x 50 centred, the prompt at cell 2 of row 1, the meter on row H-2 from cell 2: 17 of 41 cells done, then ' 42%'"
want=$(printf '%*s' 17 ''); want=${want// /█}; w2=$(printf '%*s' 24 ''); want+="${w2// /░}  42%"
if [[ $b == '15 9 65 15' && $t == '17 10' && $r13 == *"║ $want ║"* && $m == '59 13' ]]; then kt_test_pass "$b"
else kt_test_fail "box [$b] text [$t] meter at [$m] row 13 [$r13]"; fi

kt_test_start "the meter in the static text's colour (the dialog's entry 6: TView has no palette)"
IFS='|' read -r -a A <<< "$FVDL_SNAPA"
a13=${A[13]} a10=${A[10]}
if [[ ${a13:17:1} == "${a10:17:1}" && ${a13:40:1} == "${a10:17:1}" && -n ${a13:17:1} ]]; then kt_test_pass "symbol ${a13:17:1}"
else kt_test_fail "meter [${a13:17:5}] text [${a10:17:5}]"; fi

grun '' w_42only --fv-ascii --gauge 'A' 6 30
kt_test_start "--fv-ascii: the meter in # and : (8 of 21 cells done)"
# (ASCII frames draw | : the snap's row separator — the snap searched whole)
if [[ $FVDL_SNAP == *' ########:::::::::::::  42% '* ]]; then kt_test_pass ok; else kt_test_fail "snap [${FVDL_SNAP:0:2000}]"; fi

grun '' w_42only --gauge 'Copying...' 0 0
fvdl_box; b=$REPLY
kt_test_start "auto size 0 0: 40 wide at least, the prompt's rows + 4 high"
if [[ $b == '20 9 60 14' ]]; then kt_test_pass "$b"; else kt_test_fail "box [$b]"; fi
fv.dlg._gShow() { __o_gShow; }

# a resize (the scripted terminal): the box laid out again, the meter on its
# new row H-2 and as wide as the box allows
rz() { fvdl_snap; RZ=$FVDL_SNAP; }
fvdl_events 'resize 60 20' 'run rz'
# (stdin open a little longer than the scripted events: the Idle after the
# resize finds nothing yet)
fv.dlg.run --fv-headless --gauge 'Resize me' -1 -1 37 < <(printf '%s' "$BASHPID" > "$TMP/sp"; sleep 0.4)
r=$? FVDL_SNAP=$RZ
fva_noevents; __FV_VW_EOF=0
p=$(<"$TMP/sp"); for (( i = 0; i < 100; i++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.05; done
fvdl_box; b=$REPLY
fvdl_find ' 37%'; m=$REPLY
kt_test_start "a resize: the -1 -1 box takes the new screen, the meter follows (row H-2, its percentage at the right end)"
if [[ $r == 0 && $b == '0 0 60 20' && $m == '54 18' ]]; then kt_test_pass "$b meter at $m"
else kt_test_fail "rc $r box [$b] meter at [$m]"; fi

# ---- refusals, faces ---------------------------------------------------------------
kt_test_section "014: refusals and faces"
src=$(declare -f fv.dlg._isTerm)
eval "__o_isTerm${src#fv.dlg._isTerm}"
fv.dlg._isTerm() { if [[ $1 == 0 ]]; then return 0; fi; __o_isTerm "$@"; }
: > "$TMP/r.out"
fv.dlg.run --fv-headless --fv-out "$TMP/r.out" --gauge t 0 0 < /dev/null 2>"$TMP/r.err"; r=$?
fv.dlg._isTerm() { __o_isTerm "$@"; }
mapfile -t e < "$TMP/r.err"
fvdl_live
kt_test_start "stdin a terminal (the _isTerm seam): 255, one line, before any screen change (no frame written, no view)"
if [[ $r == 255 && ${#e[@]} == 1 && ${e[0]} == 'fv.dlg.run: --gauge reads its percentages from stdin, which is a terminal (pipe them in: ... | fvdlg --gauge TEXT H W)' && ! -s $TMP/r.out && -z $REPLY && -z $FV_APP ]]; then kt_test_pass ok
else kt_test_fail "rc $r err [${e[*]}] frame bytes $(wc -c < "$TMP/r.out") live [$REPLY]"; fi

fv.dlg.run --fv-headless --gauge t 0 0 <&- 2>"$TMP/r.err"; r=$?
mapfile -t e < "$TMP/r.err"
kt_test_start "stdin closed: 255, one line"
if [[ $r == 255 && ${#e[@]} == 1 && ${e[0]} == 'fv.dlg.run: --gauge reads its percentages from stdin, which is not open' ]]; then kt_test_pass ok
else kt_test_fail "rc $r err [${e[*]}]"; fi

fv.dlg.run --fv-headless --gauge t 0 0 x 2>"$TMP/r.err" < /dev/null; r=$?
mapfile -t e < "$TMP/r.err"
kt_test_start "PERCENT not an integer: 255, one line"
if [[ $r == 255 && ${e[0]-} == "fv.dlg.run: PERCENT must be an integer (got 'x')" && ${#e[@]} == 1 ]]; then kt_test_pass ok; else kt_test_fail "rc $r err [${e[*]}]"; fi

# the host application: refused
hostcase() {
    (
        fva_app 80 24
        fva_paint
        fv.dlg.run --gauge t 0 0 < /dev/null 2>"$TMP/h.err"; r=$?
        printf '%s|%s' "$r" "$(<"$TMP/h.err")"
        fva_unapp
    )
}
out=$(hostcase)
kt_test_start "inside a running fv application: refused (255, one line: its Idle does not read stdin)"
if [[ $out == "255|fv.dlg.run: --gauge needs fvdlg's own application or a session (the running fv application's Idle does not read stdin)" ]]; then kt_test_pass ok
else kt_test_fail "got [$out]"; fi

fv.dlg.begin --fv-headless 2>"$TMP/s.err"; r1=$?
fv.dlg.run --gauge 'In a session' 0 0 < <(printf '20\n60\n'); r2=$?
p=${__FV_DL_G[pct]}
fv.dlg.end; r3=$?
__FV_VW_EOF=0
wait
kt_test_start "a session: the gauge runs on the session's application (Idle is TDlgApp's), rc 0"
if [[ $r1 == 0 && $r2 == 0 && $r3 == 0 && $p == 60 && ! -s $TMP/s.err && -z $FV_APP ]]; then kt_test_pass ok
else kt_test_fail "begin $r1 run $r2 pct $p end $r3 err [$(<"$TMP/s.err")]"; fi

FV_TTY=$TMP/none/tty fv.dlg.run --no-tty=default --gauge t 0 0 < <(printf '10\n20\n30\n'; sleep 0.2; printf '40\n'); r=$?
wait
kt_test_start "--no-tty=default without a terminal: stdin read to its end, rc 0, RESULT '', no UI"
if [[ $r == 0 && -z $RESULT && $FV_DLG_CMD == cmOK && -z $FV_APP ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$RESULT] $FV_DLG_CMD"; fi

kt_test_start "the command in a pipeline: printf ... | fvdlg --fv-headless --gauge: rc 0, nothing on stdout / stderr, the last percentage drawn"
{ printf '10\n'; sleep 0.2; printf '50\n'; } | "$BASH" "$CMD" --fv-headless --fv-out "$TMP/c.out" --gauge 'Copying...' 0 0 >"$TMP/c.o" 2>"$TMP/c.e"
r=$?
cp "$TMP/c.out" "$TMP/g.out"; pcts; p=$REPLY
if [[ $r == 0 && ! -s $TMP/c.o && ! -s $TMP/c.e && $p == *' 50 ' ]]; then kt_test_pass "frames: $p"
else kt_test_fail "rc $r out [$(<"$TMP/c.o")] err [$(<"$TMP/c.e")] frames [$p]"; fi

# ---- the real pty ------------------------------------------------------------------
source "$FVDL_TESTS_DIR/../../fv.video/tests/fvv_pty.sh"
PTY_TITLES=(
    "pty: stdin the terminal -> 255 and one line, nothing sent to the terminal"
    "pty: stdin a pipe -> the gauge drawn (its prompt, 100% at the end), rc 0, the terminal restored, no process left"
    "pty: Ctrl+C during a gauge -> 130, the terminal restored, the writer gone"
)
pty_all() {
    FVP_ROOT=$TMP/pty
    mkdir -p "$FVP_ROOT"
    fvp_case term "
'$BASH' '$CMD' --gauge 'Qg1 term' 0 0 2> err1
printf '%s' \$? > rc1
: > \"\$D/ready\"
"
    fvp_run term ready
    fvp_file term rc1; local r1=$REPLY
    fvp_file term err1; local e1=$REPLY
    fvp_ts term; local ts=$REPLY
    kt_test_start "${PTY_TITLES[0]}"
    if [[ $r1 == 255 && $e1 == 'fvdlg: --gauge reads its percentages from stdin, which is a terminal (pipe them in: ... | fvdlg --gauge TEXT H W)' && $ts != *$'\e['* ]]; then kt_test_pass ok
    else kt_test_fail "rc [$r1] err [$e1] ts has ESC: $([[ $ts == *$'\e['* ]] && echo yes || echo no)"; fi

    fvp_case pipe "
: > \"\$D/ready\"
{ printf '10\n'; sleep 0.4; printf '55\n'; sleep 0.4; printf '100\n'; sleep 0.2; } | '$BASH' '$CMD' --gauge 'Qg2 pipe' 0 0
printf '%s' \"\${PIPESTATUS[1]}\" > rc2
"
    fvp_run pipe ready
    fvp_file pipe rc2; local r2=$REPLY
    fvp_ts pipe; ts=$REPLY
    fvp_restored pipe; local bad=$REPLY
    kt_test_start "${PTY_TITLES[1]}"
    # (the terminal gets only the changed cells: 10% -> 55% sends "55"; the
    # whole " 100%" is new)
    if [[ $r2 == 0 && $ts == *'Qg2 pipe'* && $ts == *'100%'* && -z $bad ]]; then kt_test_pass ok
    else kt_test_fail "rc [$r2] restored [$bad] prompt: $([[ $ts == *'Qg2 pipe'* ]] && echo y) 100: $([[ $ts == *'100%'* ]] && echo y)"; fi

    # (the command's face in this shell, its first poll marked: the feeder
    # types Ctrl+C once the gauge runs)
    fvp_case ctrlc "
trap : INT
kk.uses fv.dlg || exit 92
src=\$(declare -f fv.dlg._gShow); eval \"__o_gs\${src#fv.dlg._gShow}\"
fv.dlg._gShow() { __o_gs; [[ -e \$D/shown ]] || : > \"\$D/shown\"; }
{ printf '10\n'; sleep 6; printf '90\n'; } | { fv.dlg.main --gauge 'Qg3 ctrlc' 0 0; exit; }
printf '%s' \"\${PIPESTATUS[1]}\" > rc3
"
    fvp_run ctrlc wait:shown sleep:0.4 'type:\003'
    fvp_file ctrlc rc3; local r3=$REPLY
    fvp_restored ctrlc; bad=$REPLY
    kt_test_start "${PTY_TITLES[2]}"
    if [[ $r3 == 130 && -z $bad ]]; then kt_test_pass ok; else kt_test_fail "rc [$r3] restored [$bad]"; fi
}
if fvp_detect; then pty_all; else for t in "${PTY_TITLES[@]}"; do kt_test_start "$t"; kt_test_pass "SKIP: $FVP_WHY"; done; fi

kt_test_log "014_Gauge.sh completed"
