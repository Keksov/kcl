#!/usr/bin/env bash
# 006_CallerState.sh - the caller's shell state neither changes what the
# boxes do nor is changed by them: fvx_testlib's child scene (every public
# function, nested boxes, refusals; the boxes are made under the setup, as
# every call makes its dialog) runs under IFS ' \t\n' / $'\x1f' / '',
# nocasematch, extglob, a C locale, set -u and all at once, and must give
# the reference answers (fvx_want.sh: the rows of the boxes, the answers,
# the variables) with the setup's IFS, options and locale unchanged after
# it. RESULT is the answer (it is replaced by design). An IFS holding \x01
# is not among the setups: unsupported in fv.views / fv.dialogs (their
# README, "Contract"), so in the boxes too. Over 100 boxes (nested ones
# among them) leave no view, array, variable or function and grow no table.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: the caller's shell state"
fvx_scenefile
source "$FVX_TESTS_DIR/fvx_want.sh"

for setup in "IFS=\$' \\t\\n'" "IFS=\$'\\x1f'" "IFS=" "shopt -s nocasematch" "shopt -s extglob" "LC_ALL=C" "set -u" \
             "shopt -s nocasematch extglob; IFS=\$'\\x1f'; LC_ALL=C; set -u"; do
    kt_test_start "the caller's state: $setup"
    out=$(SETUP=$setup "$BASH" "$FVW_TMP/scene.sh" 2>&1)
    if [[ $out == "$FVX_WANT" ]]; then kt_test_pass ok; else kt_test_fail "got [$out] want [$FVX_WANT]"; fi
done

kt_test_start "RESULT is the answer; nothing else of the caller's changes (a variable named like the box's own words)"
fvx_app 80 24
d='mine' role='mine' r='mine' v='x'
fvx_events 'key kbEnter'
RESULT=before
fv.msgbox.messageBox 'Hello' "$FV_MF_OKBUTTON"
a=$RESULT
fvx_events 'char y' 'key kbEnter'
fv.msgbox.inputBox 'T' 'L' v 5
fva_noevents
if [[ "$a|$RESULT|$v|$d|$role|$r" == 'cmOK|cmOK|y|mine|mine|mine' ]]; then kt_test_pass ok; else kt_test_fail "$a|$RESULT|$v|$d|$role|$r"; fi

kt_test_section "006: over 100 boxes leave nothing"
# sizes: every global array's element count and every name (variables and
# functions), after a warm-up run
sizes() {
    local v out=''
    for v in $(compgen -v); do
        case $v in FVW_*|FVA_*|FVX_*|RESULT|REPLY|BASH_*|FUNCNAME|PIPESTATUS|_|v|out|COLUMNS|LINES|RANDOM|SECONDS|EPOCH*|SRANDOM|LINENO|BASHPID|i|ev|n|nb|SZ|s0|s1|d|w) continue ;; esac
        local -n __t_a=$v
        out+="$v:${#__t_a[@]} "
        unset -n __t_a
    done
    SZ="$out|$(compgen -A function | wc -l)"
}
# cycle: a message box (Enter), an input box (typing, Enter), a nested pair
# (a box inside an input box, both cancelled)
nb() { fv.msgbox.messageBox 'In %s' "$FV_MF_OKCANCEL" -- x; }
cycle() {
    fvx_events 'key kbTab' 'key kbEnter'
    fv.msgbox.messageBox 'Hello %s' "$(( FV_MF_ERROR | FV_MF_YESNOCANCEL ))" -- 'жук'
    fvx_events 'char a' 'char 中' 'key kbEnter'
    fv.msgbox.inputBox -p 'T' '~L~' v 10
    fvx_events 'run nb' 'key kbEsc' 'key kbEsc'
    fv.msgbox.inputBoxRect 1 1 61 9 'T' 'L' v 10
    fva_noevents; __FV_VW_EOF=0
}
v=''
cycle
sizes; s0=$SZ
for (( i = 0; i < 34; i++ )); do cycle; done
sizes; s1=$SZ
kt_test_start "136 boxes (34 cycles: a message box, an input box with -p, an input box with a box nested inside): no view, array, variable or function left; no table grew"
fvx_live
if [[ $s0 == "$s1" && -z $REPLY && $v == 'a中' ]]; then kt_test_pass "${#s0} chars of sizes equal"
else
    d=''
    for w in $s1; do [[ " $s0 " == *" $w "* ]] || d+=" $w"; done
    kt_test_fail "changed: [$d] (functions ${s0##*|} -> ${s1##*|}) live [$REPLY] v [$v]"
fi
kt_test_start "after them: == a full repaint"
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fvx_unapp

kt_test_log "006_CallerState.sh completed"
