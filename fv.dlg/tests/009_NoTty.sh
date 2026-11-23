#!/usr/bin/env bash
# 009_NoTty.sh - the command bin/fvdlg without a terminal (stage 4b: P4-5,
# D36 / Q5, design §3.4 / §3.6 / §7.1; R11). The test shell has no terminal;
# FV_TTY=$TMP/none/tty (a folder that does not exist: nothing can create it) makes that sure on every runtime:
#   * the guards run BEFORE the load: a copy of bin/fvdlg in a fake kbool
#     tree whose kbool.sh only leaves a marker proves it (no terminal, TERM
#     unset / dumb, --help / --version first, FVDLG_NOTTY refused: no marker;
#     --no-tty=default, FVDLG_NOTTY=default, --fv-headless, --help anywhere
#     in the line, any --no-tty word anywhere (a value, after --), an
#     invalid FVDLG_NOTTY beside --no-tty= / --fv-headless, FVDLG_FORCE=1:
#     the marker) — and a refusal costs bash's start; the file missing named
#     (the kcl submodule: the update hint);
#   * the messages and 255; TERM unset or dumb = no terminal unless
#     FVDLG_FORCE=1; a loaded call without a terminal refused by
#     fv.dlg.main with the guard's words; the TERM rule the command's only
#     (fv.dlg.run tests FV_TTY alone);
#   * Q5's policy (D36): --no-tty=default / FVDLG_NOTTY=default answer what
#     Enter would, printed as the UI prints (stderr / --stdout / --output-fd,
#     no newline, the list formats) for every widget; --no-tty=refuse wins
#     over the variable; the bash face with --no-tty=default; a bad value;
#     begin refuses it; a headless call ignores it;
#   * the result write that fails: a closed fd, /dev/full (where present);
#   * --help / --version: the unit's text file, the same bytes as
#     fv.dlg.main's; a failed write (stdout closed, /dev/full) not 0;
#   * the root found from the call path: relative, ./, a PATH lookup, a
#     symlink (where ln -s makes one); the file run by its +x bit (not on
#     the Windows runtimes);
#   * the bash-3.2-safe prologue: its lines parse under `bash --posix -n`,
#     hold no construct bash 3.2 lacks, and refuse old bash / sh / POSIX
#     mode with one line and 255 (a real bash 3.2 where /bin/bash is one:
#     macOS; else SKIP for that check).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
TMP=$FVW_TMP
ROOT="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)"
CMD=$ROOT/bin/fvdlg
NOTTY=$TMP/none/tty
export FV_TTY=$NOTTY
NOTTY_LINE="fvdlg: no terminal ($NOTTY)"$'\n'

# run [ENV=V...] -- ARG... : bin/fvdlg in a child (env first), R_RC, R_OUT,
# R_ERR, R_FD3 (the bytes)
run() {
    local -a env=()
    while (( $# )) && [ "$1" != -- ]; do env+=("$1"); shift; done
    shift
    env "${env[@]}" "$BASH" "$CMD" "$@" >"$TMP/r.out" 2>"$TMP/r.err" 3>"$TMP/r.fd3"
    R_RC=$?
    R_OUT='' R_ERR='' R_FD3=''
    { IFS= read -r -d '' R_OUT || :; } < "$TMP/r.out"
    { IFS= read -r -d '' R_ERR || :; } < "$TMP/r.err"
    { IFS= read -r -d '' R_FD3 || :; } < "$TMP/r.fd3"
}

# ---- the fake tree: bin/fvdlg's copy, a kbool.sh that marks and fails ----
FAKE=$TMP/fake
mkdir -p "$FAKE/bin" "$FAKE/kcl/fv.dlg"
cp "$CMD" "$FAKE/bin/fvdlg"
cp "$ROOT/kcl/fv.dlg/fv.dlg.usage.sh" "$FAKE/kcl/fv.dlg/"
printf ': > "%s/loaded"\nreturn 3\n' "$FAKE" > "$FAKE/kbool.sh"
# fake [ENV=V...] -- ARG... : the copy in a child; F_RC, F_ERR, F_OUT, F_LOAD
# (1 = kbool.sh was sourced)
fake() {
    local -a env=()
    while (( $# )) && [ "$1" != -- ]; do env+=("$1"); shift; done
    shift
    rm -f "$FAKE/loaded"
    env "${env[@]}" "$BASH" "$FAKE/bin/fvdlg" "$@" >"$TMP/f.out" 2>"$TMP/f.err"
    F_RC=$? F_LOAD=0 F_OUT='' F_ERR=''
    if [[ -e $FAKE/loaded ]]; then F_LOAD=1; fi
    { IFS= read -r -d '' F_OUT || :; } < "$TMP/f.out"
    { IFS= read -r -d '' F_ERR || :; } < "$TMP/f.err"
}

kt_test_section "009: the guards run before the load"

fake -- --msgbox Hi 0 0
kt_test_start "no terminal (FV_TTY in a missing folder): 255, one line 'fvdlg: no terminal (PATH)', kbool.sh never sourced"
if [[ $F_RC == 255 && $F_LOAD == 0 && $F_ERR == "$NOTTY_LINE" && -z $F_OUT ]]; then kt_test_pass ok
else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR] out [$F_OUT]"; fi

t0=${EPOCHREALTIME/./}
for i in 1 2 3; do fake -- --yesno Sure 0 0; done
t1=${EPOCHREALTIME/./}
kt_test_log "009: three pre-load refusals took $(( (t1 - t0) / 1000 )) ms (logged; the marker is the proof)"

fake TERM=dumb FV_TTY=/dev/null -- --msgbox Hi 0 0
kt_test_start "TERM=dumb (the terminal opens): 255, 'no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)', not loaded"
if [[ $F_RC == 255 && $F_LOAD == 0 && $F_ERR == $'fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)\n' ]]; then kt_test_pass ok
else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

fake -u TERM FV_TTY=/dev/null -- --msgbox Hi 0 0
kt_test_start "TERM unset: 255 and not loaded (bash itself sets TERM=dumb when the environment has none: 'TERM is dumb')"
if [[ $F_RC == 255 && $F_LOAD == 0 && ( $F_ERR == $'fvdlg: no terminal (TERM is empty; FVDLG_FORCE=1 overrides)\n' || $F_ERR == $'fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)\n' ) ]]; then kt_test_pass "${F_ERR%$'\n'}"
else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

fake TERM=dumb FV_TTY=/dev/null FVDLG_FORCE=1 -- --msgbox Hi 0 0
kt_test_start "FVDLG_FORCE=1 lifts the TERM rule: the load runs (marker)"
if [[ $F_LOAD == 1 && $F_RC == 255 && $F_ERR == *'cannot load kbool fv.dlg'* ]]; then kt_test_pass ok; else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

fake TERM=dumb FV_TTY=/dev/null FVDLG_FORCE=0 -- --msgbox Hi 0 0
kt_test_start "FVDLG_FORCE other than 1 does not: refused, not loaded"
if [[ $F_RC == 255 && $F_LOAD == 0 ]]; then kt_test_pass ok; else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

fake -- --no-tty=default --msgbox Hi 0 0
a=$F_LOAD
fake FVDLG_NOTTY=default -- --msgbox Hi 0 0
b=$F_LOAD
fake -- --msgbox Hi 0 0 --no-tty default
c=$F_LOAD
fake FVDLG_NOTTY=default -- --no-tty=refuse --msgbox Hi 0 0
d=$F_LOAD
kt_test_start "D36 opt-in: --no-tty=default, FVDLG_NOTTY=default, '--no-tty default' load; so does --no-tty=refuse with the variable (the unit refuses it: below)"
if [[ $a$b$c$d == 1111 ]]; then kt_test_pass ok; else kt_test_fail "loads $a$b$c$d"; fi

fake FVDLG_NOTTY=yes -- --msgbox Hi 0 0
kt_test_start "FVDLG_NOTTY other than default / refuse: 255, one line, not loaded"
if [[ $F_RC == 255 && $F_LOAD == 0 && $F_ERR == $'fvdlg: FVDLG_NOTTY must be default or refuse (got \'yes\')\n' ]]; then kt_test_pass ok
else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

# (4b fix L7)
fake FVDLG_NOTTY=yes -- --no-tty=default --msgbox Hi 0 0
a="$F_LOAD|$F_ERR"
fake FVDLG_NOTTY=yes -- --fv-headless --msgbox Hi 0 0
b="$F_LOAD|$F_ERR"
kt_test_start "an invalid FVDLG_NOTTY is ignored when the call carries --no-tty=... or --fv-headless: loaded, no FVDLG_NOTTY line"
if [[ $a == '1|'* && $a != *FVDLG_NOTTY* && $b == '1|'* && $b != *FVDLG_NOTTY* ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi

fake -- --no-tty=maybe --msgbox Hi 0 0
kt_test_start "a --no-tty value the unit refuses is the unit's to name: loaded"
if [[ $F_LOAD == 1 ]]; then kt_test_pass ok; else kt_test_fail "rc $F_RC load $F_LOAD err [$F_ERR]"; fi

fake -- --fv-headless --msgbox Hi 0 0
a=$F_LOAD
fake -- --title T --help
b=$F_LOAD
fake -- -- --fv-headless
c=$F_LOAD
fake -- --title T --msgbox Hi 0 0
d=$F_LOAD
kt_test_start "no guard for --fv-headless or a --help anywhere in the line, also after -- (loaded: the parser decides); a plain call is refused"
if [[ $a$b$c$d == 1110 ]]; then kt_test_pass ok; else kt_test_fail "loads $a$b$c$d"; fi

# (4b fix L1: the critic's cases — a --no-tty word anywhere loads)
s=''
for args in '--no-tty=default --title --no-tty=refuse --msgbox Hi 0 0' '--title --no-tty=default --msgbox Hi 0 0' \
            '--stdout --inputbox -- 0 0 v --no-tty=default' '--msgbox Hi 0 0 --no-tty' '--msgbox Hi 0 0 --no-tty refuse'; do
    read -r -a av <<< "$args"
    fake -- "${av[@]}"
    s+=$F_LOAD
done
kt_test_start "a --no-tty word anywhere (an option's value, after a TEXT --, without a value, refuse) is the unit's to decide: loaded"
if [[ $s == 11111 ]]; then kt_test_pass ok; else kt_test_fail "loads $s"; fi

# (4b fix L3: the file missing named)
FAKE2=$TMP/fake2
mkdir -p "$FAKE2/bin" "$FAKE2/kcl"
cp "$CMD" "$FAKE2/bin/fvdlg"
"$BASH" "$FAKE2/bin/fvdlg" --version >/dev/null 2>"$TMP/m1.err"; r1=$?
printf 'return 3\n' > "$FAKE2/kbool.sh"
"$BASH" "$FAKE2/bin/fvdlg" --version >/dev/null 2>"$TMP/m2.err"; r2=$?
e1=$(<"$TMP/m1.err") e2=$(<"$TMP/m2.err")
kt_test_start "kbool's files missing: 255, the file named; the kcl submodule's: the hint 'git submodule update --init' (a clone without --recurse-submodules)"
if [[ $r1 == 255 && $e1 == "fvdlg: cannot find kbool next to $FAKE2/bin/fvdlg (no $FAKE2/bin/../kbool.sh)" \
      && $r2 == 255 && $e2 == "fvdlg: cannot find kbool next to $FAKE2/bin/fvdlg (no $FAKE2/bin/../kcl/fv.dlg/fv.dlg.usage.sh; kcl/ is a git submodule: run git submodule update --init in $FAKE2/bin/..)" ]]; then kt_test_pass ok
else kt_test_fail "$r1 [$e1] $r2 [$e2]"; fi

fake -- --help
a=$F_RC$F_LOAD h=$F_OUT
fake -- --version
b=$F_RC$F_LOAD v=$F_OUT
kt_test_start "--help / --version first: rc 0, the text on stdout, no load, no terminal needed"
if [[ $a$b == 0000 && $h == 'Usage: fvdlg '* && $v == $'fvdlg 0.1 (kbool fv.dlg)\n' ]]; then kt_test_pass ok; else kt_test_fail "help $a [${h:0:30}] version $b [$v]"; fi

kt_test_start "the help / version text is the unit's: fv.dlg.main --help / --version print the same bytes"
um=$(fv.dlg.main --help; printf x) uv=$(fv.dlg.main --version; printf x)
if [[ ${um%x} == "$h" && ${uv%x} == "$v" ]]; then kt_test_pass ok; else kt_test_fail "differ"; fi

# (4b fix L5: a failed write is not 0)
"$BASH" "$CMD" --help >&- 2>/dev/null; a=$?
"$BASH" "$CMD" --version >&- 2>/dev/null; b=$?
"$BASH" "$CMD" --title T --help >&- 2>/dev/null; c=$?
( fv.dlg.main --version >&- 2>/dev/null ); d=$?
kt_test_start "--help / --version with stdout closed: printf's status (1), not 0 — before the load, through the unit, fv.dlg.main"
if [[ $a$b$c$d == 1111 ]]; then kt_test_pass ok; else kt_test_fail "$a $b $c $d"; fi
kt_test_start "--help / --version into /dev/full: 1 (SKIP where there is no /dev/full)"
if [[ -c /dev/full ]]; then
    "$BASH" "$CMD" --help >/dev/full 2>/dev/null; a=$?
    "$BASH" "$CMD" --title T --version >/dev/full 2>/dev/null; b=$?
    if [[ $a$b == 11 ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
else
    kt_test_pass "SKIP: no /dev/full here"
fi

kt_test_section "009: the real command"

run -- --msgbox Hi 0 0
kt_test_start "no terminal: 255, one line, nothing on stdout"
if [[ $R_RC == 255 && $R_ERR == "$NOTTY_LINE" && -z $R_OUT$R_FD3 ]]; then kt_test_pass ok; else kt_test_fail "rc $R_RC err [$R_ERR] out [$R_OUT]"; fi

run TERM=dumb FV_TTY=/dev/null FVDLG_FORCE=1 -- --msgbox Hi 0 0
kt_test_start "FVDLG_FORCE=1 with a path that opens but is no terminal: loaded, fv.video refuses it: 255 'no terminal (/dev/null)'"
if [[ $R_RC == 255 && $R_ERR == $'fvdlg: no terminal (/dev/null)\n' ]]; then kt_test_pass ok; else kt_test_fail "rc $R_RC err [$R_ERR]"; fi

run -- --title T --help
kt_test_start "--help later in the line without a terminal: the unit prints it, rc 0"
if [[ $R_RC == 0 && $R_OUT == 'Usage: fvdlg '* && -z $R_ERR ]]; then kt_test_pass ok; else kt_test_fail "rc $R_RC err [$R_ERR] out [${R_OUT:0:30}]"; fi

run FVDLG_NOTTY=default -- --no-tty=refuse --msgbox Hi 0 0
a="$R_RC|$R_ERR"
run -- --no-tty=default --title --no-tty=refuse --stdout --inputbox N 0 0 v
b="$R_RC|$R_OUT|$R_ERR"
run -- --title --no-tty=default --msgbox Hi 0 0
c="$R_RC|$R_ERR"
run -- --stdout --inputbox -- 0 0 v --no-tty=default
d="$R_RC|$R_OUT|$R_ERR"
run TERM=dumb FV_TTY=/dev/null -- --no-tty=refuse --msgbox Hi 0 0
e="$R_RC|$R_ERR"
kt_test_start "loaded calls the guard left alone, decided by the unit with the guard's words: --no-tty=refuse over FVDLG_NOTTY=default (255), a --no-tty=refuse that is a title (answers), one that is the only --no-tty (refused), options after a TEXT -- (answers), TERM=dumb (the TERM line)"
if [[ $a == "255|$NOTTY_LINE" && $b == '0|v|' && $c == "255|$NOTTY_LINE" && $d == '0|v|' && $e == $'255|fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)\n' ]]; then kt_test_pass ok
else kt_test_fail "[$a] [$b] [$c] [$d] [$e]"; fi

run FVDLG_NOTTY=yes -- --no-tty=default --stdout --inputbox N 0 0 v
kt_test_start "an invalid FVDLG_NOTTY with --no-tty=default on the call: ignored (not passed on), the call answers"
if [[ $R_RC == 0 && $R_OUT == v && -z $R_ERR ]]; then kt_test_pass ok; else kt_test_fail "rc $R_RC [$R_OUT] [$R_ERR]"; fi

printf 'abc\r' > "$TMP/abc.keys"
run -- --fv-headless --fv-keys "$TMP/abc.keys" --inputbox Name 0 0
kt_test_start "--fv-headless needs no terminal: the keys answer (abc on stderr, rc 0)"
if [[ $R_RC == 0 && $R_ERR == abc ]]; then kt_test_pass ok; else kt_test_fail "rc $R_RC err [$R_ERR]"; fi

kt_test_section "009: Q5 / D36 — what Enter would answer, without a UI"

# the bash face, in this shell (the same code as the command's)
nt() {   # WANT_RC WANT_RESULT WANT_CMD TITLE ARG... : fv.dlg.run --no-tty=default
    local wr=$1 wres=$2 wc=$3 title=$4 out
    shift 4
    out=$(fv.dlg.run --no-tty=default --stdout "$@"; printf '|%s' "$?")
    fv.dlg.run --no-tty=default "$@"
    local rc=$? res=$RESULT cmd=$FV_DLG_CMD
    fvdl_live
    kt_test_start "$title"
    local wout=$wres
    if (( wr != 0 )) || [[ " msgbox yesno infobox " == *" ${wid-} "* ]]; then wout=''; fi
    if [[ $rc == "$wr" && $res == "$wres" && $cmd == "$wc" && $out == "$wout|$wr" && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "rc $rc [$res] $cmd"
    else kt_test_fail "rc $rc [$res] $cmd out [$out] live [$REPLY] app [$FV_APP], want $wr [$wres] $wc [$wout|$wr]"; fi
}
wid=msgbox nt 0 '' cmOK "msgbox: 0, cmOK, nothing printed" --msgbox Hi 0 0
wid=yesno nt 0 '' cmYes "yesno: 0 (cmYes)" --yesno Sure 0 0
wid=yesno nt 1 '' cmNo "yesno --defaultno: 1 (cmNo), nothing printed" --defaultno --yesno Sure 0 0
wid=infobox nt 0 '' cmOK "infobox: 0, nothing drawn, nothing printed" --infobox Wait 0 0
wid=inputbox nt 0 'init text' cmOK "inputbox: INIT" --inputbox Name 0 0 'init text'
wid=inputbox nt 0 '' cmOK "inputbox without INIT: '' with 0" --inputbox Name 0 0
wid=passwordbox nt 0 'pw' cmOK "passwordbox: INIT" --passwordbox Pass 0 0 pw
wid=inputbox nt 0 'ab' cmOK "inputbox: INIT as the input line keeps it (control characters dropped)" --inputbox Name 0 0 $'a\tb'
long=$(printf 'x%.0s' {1..1030})
wid=inputbox nt 0 "${long:0:1024}" cmOK "inputbox: a 1030-character INIT cut to the line's 1024 clusters" --inputbox Name 0 0 "$long"
wid=menu nt 0 a cmOK "menu: the first tag" --menu Pick 0 0 0 a A b B c C
wid=menu nt 0 b cmOK "menu --default-item b: b" --default-item b --menu Pick 0 0 0 a A b B c C
wid=menu nt 0 a cmOK "menu --default-item naming no tag: the first" --default-item zz --menu Pick 0 0 0 a A b B
wid=checklist nt 0 '"a" "my app"' cmOK "checklist: its on tags, whiptail's quoted form" --checklist Pick 0 0 0 a A on b B off 'my app' M ON
wid=checklist nt 0 $'a\nmy app\n' cmOK "checklist --separate-output: one per line" --separate-output --checklist Pick 0 0 0 a A on b B off 'my app' M on
wid=checklist nt 0 "a 'my app'" cmOK "checklist --single-quoted: dialog's form" --single-quoted --checklist Pick 0 0 0 a A on 'my app' M on
wid=checklist nt 0 '' cmOK "checklist with nothing on: '' with 0" --checklist Pick 0 0 0 a A off
wid=radiolist nt 0 c cmOK "radiolist: the on tag (two on: the last, whiptail)" --radiolist Pick 0 0 0 a A on b B off c C on
wid=radiolist nt 0 '' cmOK "radiolist with nothing on: '' with 0 (what Enter answers; not the first tag)" --radiolist Pick 0 0 0 a A off b B off

kt_test_start "the list answer's tags: FV_DLG_TAGS"
fv.dlg.run --no-tty=default --checklist Pick 0 0 0 a A on b B off c C on
if [[ ${FV_DLG_TAGS[*]} == 'a c' ]]; then kt_test_pass ok; else kt_test_fail "[${FV_DLG_TAGS[*]}]"; fi

kt_test_start "a checklist of 2000 items answers its on tags"
args=()
for (( i = 0; i < 2000; i++ )); do if (( i % 500 == 7 )); then args+=("t$i" "I$i" on); else args+=("t$i" "I$i" off); fi; done
fv.dlg.run --no-tty=default --checklist Pick 0 0 0 "${args[@]}"
if [[ $? == 0 && $RESULT == '"t7" "t507" "t1007" "t1507"' && ${#__DLFV_TAGS[@]} == 0 ]]; then kt_test_pass ok; else kt_test_fail "[$RESULT] tags left ${#__DLFV_TAGS[@]}"; fi

fv.dlg.run --no-tty=refuse --msgbox Hi 0 0 2>"$TMP/e1"; r1=$?
fv.dlg.run --msgbox Hi 0 0 2>"$TMP/e2"; r2=$?
kt_test_start "the bash face without the opt-in (or --no-tty=refuse): 255 'no terminal' after the try"
if [[ $r1 == 255 && $r2 == 255 && $(<"$TMP/e1") == "fv.dlg.run: no terminal ($NOTTY)" ]]; then kt_test_pass ok; else kt_test_fail "$r1 $r2 [$(<"$TMP/e1")]"; fi

fv.dlg.run --no-tty=sometimes --msgbox Hi 0 0 2>"$TMP/e3"; r3=$?
fv.dlg.begin --no-tty=default 2>"$TMP/e4"; r4=$?
kt_test_start "--no-tty: a bad value refused; fv.dlg.begin refuses it (a dialog's option)"
if [[ $r3 == 255 && $(<"$TMP/e3") == "fv.dlg.run: --no-tty must be default | refuse (got 'sometimes')" && $r4 == 255 && $(<"$TMP/e4") == *"'notty' is a dialog's option"* ]]; then kt_test_pass ok
else kt_test_fail "$r3 [$(<"$TMP/e3")] $r4 [$(<"$TMP/e4")]"; fi

printf '\033' > "$TMP/esc.keys"
fv.dlg.run --no-tty=default --fv-headless --fv-keys "$TMP/esc.keys" --yesno Sure 0 0; r=$?
kt_test_start "a headless call ignores --no-tty=default (it has its keys): Esc -> 255"
if [[ $r == 255 ]]; then kt_test_pass ok; else kt_test_fail "rc $r"; fi

kt_test_start "fv.dlg._hasTerm: a missing path (never created) and /dev/null (not a terminal) are none, REPLY = the path"
s=''
for f in run main; do
    FV_TTY=$NOTTY fv.dlg._hasTerm "$f" && s+=" $f:yes"; [[ $REPLY == "$NOTTY" ]] || s+=" $f:[$REPLY]"
    FV_TTY=/dev/null TERM=xterm fv.dlg._hasTerm "$f" && s+=" $f:yes"; [[ $REPLY == /dev/null ]] || s+=" $f:[$REPLY]"
done
if [[ -z $s && ! -e $NOTTY && ! -e ${NOTTY%/*} ]]; then kt_test_pass ok; else kt_test_fail "$s"; fi

# (4b fix L4: the TERM rule is the command's)
TERM=dumb FV_TTY=/dev/null fv.dlg._hasTerm run; a=$REPLY
TERM=dumb FV_TTY=/dev/null fv.dlg._hasTerm main; b=$REPLY
TERM=dumb FV_TTY=/dev/null FVDLG_FORCE=1 fv.dlg._hasTerm main; c=$REPLY
TERM=dumb FV_TTY=/dev/null fv.dlg.main --msgbox Hi 0 0 2>"$TMP/h1"; r1=$?
TERM=dumb FV_TTY=/dev/null fv.dlg.run --msgbox Hi 0 0 2>"$TMP/h2"; r2=$?
TERM=dumb fv.dlg.run --no-tty=default --stdout --inputbox N 0 0 x >"$TMP/h3" 2>&1; r3=$?
kt_test_start "the TERM rule is the command's only: fv.dlg.main names 'TERM is dumb' (FVDLG_FORCE=1 lifts it), fv.dlg.run tests FV_TTY alone (with or without --no-tty=default)"
if [[ $a == /dev/null && $b == 'TERM is dumb; FVDLG_FORCE=1 overrides' && $c == /dev/null \
      && $r1 == 255 && $(<"$TMP/h1") == 'fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1 overrides)' \
      && $r2 == 255 && $(<"$TMP/h2") == 'fv.dlg.run: no terminal (/dev/null)' && $r3 == 0 && $(<"$TMP/h3") == x ]]; then kt_test_pass ok
else kt_test_fail "[$a] [$b] [$c] $r1 [$(<"$TMP/h1")] $r2 [$(<"$TMP/h2")] $r3 [$(<"$TMP/h3")]"; fi

# the command end to end (one load each)
run -- --no-tty=default --inputbox Name 0 0 hello
a="$R_RC|$R_OUT|$R_ERR"
run FVDLG_NOTTY=default -- --stdout --checklist Pick 0 0 0 a A on b B on
b="$R_RC|$R_OUT|$R_ERR"
run FVDLG_NOTTY=default -- --output-fd 3 --menu Pick 0 0 0 a A b B --default-item b
c="$R_RC|$R_OUT|$R_ERR|$R_FD3"
run FVDLG_NOTTY=default -- --defaultno --yesno Sure 0 0
d="$R_RC|$R_OUT|$R_ERR"
kt_test_start "the command: --no-tty=default inputbox -> stderr, FVDLG_NOTTY + --stdout checklist, --output-fd 3 menu, --defaultno 1 — no newline, nothing else"
if [[ $a == '0||hello' && $b == '0|"a" "b"|' && $c == '0|||b' && $d == '1||' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b] [$c] [$d]"; fi

kt_test_start "the result fd closed (--stdout, stdout closed): 255, 'cannot write the result to fd 1'"
"$BASH" "$CMD" --no-tty=default --stdout --inputbox Name 0 0 v >&- 2>"$TMP/w.err"; r=$?
if [[ $r == 255 && $(<"$TMP/w.err") == 'fvdlg: cannot write the result to fd 1' ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$TMP/w.err")]"; fi

kt_test_start "stderr closed (the default result fd): 255, nothing anywhere (the line has nowhere to go)"
"$BASH" "$CMD" --no-tty=default --inputbox Name 0 0 v 2>&- >"$TMP/w3.out"; r=$?
if [[ $r == 255 && ! -s $TMP/w3.out ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$TMP/w3.out")]"; fi

kt_test_start "the result write fails (/dev/full): 255, 'cannot write the result to fd 1' (SKIP where there is no /dev/full)"
if [[ -c /dev/full ]]; then
    fv.dlg.main --no-tty=default --stdout --inputbox Name 0 0 v >/dev/full 2>"$TMP/w2.err"; r=$?
    if [[ $r == 255 && $(<"$TMP/w2.err") == 'fvdlg: cannot write the result to fd 1' && -z $RESULT ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$TMP/w2.err")] [$RESULT]"; fi
else
    kt_test_pass "SKIP: no /dev/full here"
fi

kt_test_section "009: the root from the call path"

v=$(cd "$ROOT/bin" && "$BASH" fvdlg --version)
w=$(cd "$ROOT" && "$BASH" ./bin/fvdlg --version)
x=$(cd "$ROOT/kcl" && "$BASH" ../bin/fvdlg --version)
y=$(cd "$TMP" && PATH=$ROOT/bin:$PATH "$BASH" fvdlg --version)
z=$(cd "$ROOT/kcl" && FVDLG_NOTTY=default "$BASH" ../bin/fvdlg --stdout --inputbox N 0 0 rel)
kt_test_start "bash fvdlg in bin/, ./bin/fvdlg, ../bin/fvdlg, a PATH lookup: the root found (also through a load: ../bin/fvdlg answers)"
vv='fvdlg 0.1 (kbool fv.dlg)'
if [[ $v == "$vv" && $w == "$vv" && $x == "$vv" && $y == "$vv" && $z == rel ]]; then kt_test_pass ok
else kt_test_fail "[$v] [$w] [$x] [$y] [$z]"; fi

# (4b fix L8: the file run by its own +x bit and shebang, as a user runs it)
kt_test_start "\"\$CMD\" executed directly (its +x bit, #!/usr/bin/env bash): --version, and an answer through the load (SKIP on the Windows runtimes: no +x bit there; the index's 100755 is checked at commit)"
case $OSTYPE in
    msys*|cygwin*) kt_test_pass "SKIP: $OSTYPE has no +x bit" ;;
    *)
        v=$(PATH=${BASH%/*}:$PATH "$CMD" --version 2>&1)
        w=$(cd "$TMP" && PATH=${BASH%/*}:$PATH FVDLG_NOTTY=default "$CMD" --stdout --inputbox N 0 0 direct 2>&1)
        if [[ -x $CMD && $v == "$vv" && $w == direct ]]; then kt_test_pass ok; else kt_test_fail "x=$([[ -x $CMD ]] && echo y || echo n) [$v] [$w]"; fi ;;
esac

mkdir -p "$TMP/lnk"
ln -s "$CMD" "$TMP/lnk/fvdlg" 2>/dev/null
kt_test_start "a symlink to bin/fvdlg on PATH: followed (one readlink), the load works (SKIP where ln -s makes no symlink)"
if [[ -L $TMP/lnk/fvdlg ]]; then
    s=$(cd "$TMP" && FVDLG_NOTTY=default PATH=$TMP/lnk:$PATH "$BASH" fvdlg --stdout --inputbox N 0 0 via-link)
    if [[ $s == via-link ]]; then kt_test_pass ok; else kt_test_fail "[$s]"; fi
else
    kt_test_pass "SKIP: ln -s made no symlink here"
fi

kt_test_section "009: the bash-3.2-safe prologue (R11)"

# the prologue: from line 2 to its end mark
pro=$TMP/prologue.sh
{
    n=0 seen=0
    while IFS= read -r l; do
        n=$(( n + 1 ))
        (( n == 1 )) && continue
        printf '%s\n' "$l"
        if [[ $l == '# ---- the end of the bash-3.2-safe prologue ----' ]]; then seen=1; break; fi
    done < "$CMD"
    printf 'echo PASSED\n'
} > "$pro"
kt_test_start "the prologue has its end mark and parses under bash --posix -n"
if grep -q 'the end of the bash-3.2-safe prologue' "$pro" && "$BASH" --posix -n "$pro" 2>"$TMP/p.err"; then kt_test_pass ok; else kt_test_fail "$(<"$TMP/p.err")"; fi

kt_test_start "the prologue's code lines hold nothing bash 3.2 lacks ({fd} redirects, \${x,,} / \${x^^}, [[ -v, local -n, declare -A / -g, mapfile / readarray, ;& / ;;&, \${x@...}, |&, &>>)"
bad=''
while IFS= read -r l; do
    [[ $l =~ ^[[:space:]]*# ]] && continue
    if [[ $l =~ \{[A-Za-z_][A-Za-z0-9_]*\}[\<\>] || $l == *',,}'* || $l == *'^^}'* || $l == *'[[ -v'* || $l == *'local -n'* \
          || $l =~ declare\ -[a-zA-Z]*[Ag] || $l == *mapfile* || $l == *readarray* || $l == *';&'* || $l =~ \$\{[A-Za-z_0-9]+@ \
          || $l == *'|&'* || $l == *'&>>'* || $l == *'[['* ]]; then bad+=" [$l]"; fi
done < "$pro"
if [[ -z $bad ]]; then kt_test_pass ok; else kt_test_fail "$bad"; fi

# the version table exercised with this bash: the copy's 5.x row widened to
# every version
sed -e 's/\[1234\]\.\*|5\.0\*)/*)/' "$pro" > "$TMP/pro_any.sh"
o=$("$BASH" "$TMP/pro_any.sh" 2>&1); r=$?
kt_test_start "the refusal's words (the version row widened in a copy): 255, 'fvdlg: needs bash 5.1 or later (this is X.Y.Z)'"
if [[ $r == 255 && $o == "fvdlg: needs bash 5.1 or later (this is ${BASH_VERSION%%(*})" ]]; then kt_test_pass "$o"; else kt_test_fail "rc $r [$o]"; fi

o=$("$BASH" "$pro" 2>&1); r=$?
o2=$("$BASH" --posix "$CMD" --msgbox Hi 0 0 2>&1); r2=$?
kt_test_start "this bash passes the prologue; bash --posix is refused with one line and 255"
if [[ $r == 0 && $o == PASSED && $r2 == 255 && $o2 == 'fvdlg: bash in POSIX mode (sh, --posix, POSIXLY_CORRECT) is not supported; run it as bash' ]]; then kt_test_pass ok
else kt_test_fail "[$o] $r / [$o2] $r2"; fi

kt_test_start "sh fvdlg: one line and 255 (dash: 'this shell is not bash'; bash as sh: POSIX mode)"
if command -v sh >/dev/null 2>&1; then
    o=$(sh "$CMD" --msgbox Hi 0 0 2>&1); r=$?
    if [[ $r == 255 && ( $o == 'fvdlg: needs bash 5.1 or later (this shell is not bash)' || $o == 'fvdlg: bash in POSIX mode'* || $o == 'fvdlg: needs bash 5.1 or later (this is '* ) ]]; then kt_test_pass "$o"
    else kt_test_fail "rc $r [$o]"; fi
else
    kt_test_pass "SKIP: no sh"
fi

kt_test_start "a real bash 3.2 (/bin/bash where it is one, macOS): 255, 'needs bash 5.1 or later (this is 3.2.x)' (SKIP elsewhere)"
v32=''
if [[ -x /bin/bash ]]; then v32=$(/bin/bash -c 'printf %s "$BASH_VERSION"' 2>/dev/null); fi
if [[ $v32 == 3.* || $v32 == 4.* || $v32 == 5.0* ]]; then
    o=$(/bin/bash "$CMD" --msgbox Hi 0 0 2>&1); r=$?
    if [[ $r == 255 && $o == "fvdlg: needs bash 5.1 or later (this is ${v32%%(*})" ]]; then kt_test_pass "$o"; else kt_test_fail "rc $r [$o]"; fi
else
    kt_test_pass "SKIP: /bin/bash is ${v32:-absent} here"
fi

kt_test_log "009_NoTty.sh completed"
