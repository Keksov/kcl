#!/usr/bin/env bash
# 007_Subshell.sh - a box in a process that does not own the screen (design
# P3 §6, L9; fv.views' owner rule for execView): `$(fv.msgbox.messageBox
# ...)` and the other three functions in `$( )`, a `( )` subshell and a
# pipeline are refused before anything is made: rc 2, exactly one
# `Error: fv.msgbox: NAME: refused in a subshell ...` line on stderr
# (VERBOSE_KKLASS=quiet: none), nothing on stdout, the terminal untouched
# (the frames written and the screen buffer as before), no view made, the
# parent's RESULT and the input box's variable unchanged; the refusal wins
# over a malformed call; the same calls in the owner process work.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: the subshell refusal"
fvx_app 80 24
fvw_outsize; s0=$REPLY
fvw_snap; b0=$REPLY
v='kept'
RESULT=parent

# sub NAME CMD... -- CMD in $( ); OUT = its stdout, RC, E = its stderr lines
sub() {
    local n=$1
    shift
    OUT=$("$@" 2>"$FVW_TMP/sub.err"); RC=$?
    mapfile -t E < "$FVW_TMP/sub.err"
    kt_test_start "\$($n ...): rc 2, one Error line, nothing on stdout"
    if (( RC == 2 )) && [[ -z $OUT && ${#E[@]} == 1 && ${E[0]} == "Error: fv.msgbox: $n: refused in a subshell (BASHPID "*"; the screen belongs to $BASHPID): call it in the shell that owns the screen" ]]; then
        kt_test_pass "${E[0]:0:60}"
    else kt_test_fail "rc $RC out [$OUT] err [${E[*]}]"; fi
}
sub messageBox fv.msgbox.messageBox 'Hello' "$FV_MF_OKBUTTON"
sub messageBoxRect fv.msgbox.messageBoxRect 1 1 41 10 'Hello' "$FV_MF_YESNOCANCEL" -- a b
sub inputBox fv.msgbox.inputBox 'T' 'L' v 10
sub inputBox fv.msgbox.inputBox -p 'T' 'L' v 10
sub inputBoxRect fv.msgbox.inputBoxRect 1 1 61 9 'T' 'L' v 10
sub messageBox fv.msgbox.messageBox
sub inputBox fv.msgbox.inputBox RESULT

kt_test_start "a ( ) subshell and a pipeline: refused the same way (rc 2, one line each)"
( fv.msgbox.messageBox 'Hello' "$FV_MF_OKBUTTON" ) 2>"$FVW_TMP/p1.err"; r1=$?
fv.msgbox.inputBox 'T' 'L' v 10 2>"$FVW_TMP/p2.err" | :; r2=${PIPESTATUS[0]}
mapfile -t E1 < "$FVW_TMP/p1.err"; mapfile -t E2 < "$FVW_TMP/p2.err"
if (( r1 == 2 && r2 == 2 )) && [[ ${#E1[@]} == 1 && ${#E2[@]} == 1 && ${E1[0]} == 'Error: fv.msgbox: messageBox: refused'* && ${E2[0]} == 'Error: fv.msgbox: inputBox: refused'* ]]; then
    kt_test_pass ok
else kt_test_fail "$r1 $r2 [${E1[*]}] [${E2[*]}]"; fi

kt_test_start "VERBOSE_KKLASS=quiet: rc 2 and no line"
OUT=$(VERBOSE_KKLASS=quiet fv.msgbox.messageBox 'Hello' "$FV_MF_OKBUTTON" 2>&1); RC=$?
if (( RC == 2 )) && [[ -z $OUT ]]; then kt_test_pass ok; else kt_test_fail "rc $RC [$OUT]"; fi

kt_test_start "the terminal untouched: no frame written, the screen buffer as before; no view made; RESULT and the variable kept"
rr=$RESULT
fvw_outsize; s1=$REPLY
fvw_snap; b1=$REPLY
fvx_live
if [[ $s1 == "$s0" && $b1 == "$b0" && -z $REPLY && $rr == parent && $v == kept ]]; then kt_test_pass ok
else kt_test_fail "out $s0 -> $s1, screen same: $([[ $b1 == "$b0" ]] && echo y || echo n), live [$REPLY], RESULT $rr, v $v"; fi

kt_test_start "in the owner process the same calls work"
fvx_events 'key kbEnter'
fv.msgbox.messageBox 'Hello' "$FV_MF_OKBUTTON"; a=$RESULT
fvx_events 'char n' 'key kbEnter'
fv.msgbox.inputBox 'T' 'L' v 10
fva_noevents
if [[ "$a|$RESULT|$v" == 'cmOK|cmOK|n' ]]; then kt_test_pass ok; else kt_test_fail "$a|$RESULT|$v"; fi
fvx_unapp

kt_test_log "007_Subshell.sh completed"
