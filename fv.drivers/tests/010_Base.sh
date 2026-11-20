#!/usr/bin/env bash
# 010_Base.sh - FV_EV_BASE (design P3 §14.4, row 10.14): getEvent copies
# fv.keyboard's FV_KEY_BASE into the key event (a kitty CSI u report, a
# legacy ESC + non-ASCII character through the layout tables), '' for a key
# without one; every other event clears it (mouse, resize, nothing, the
# auto-repeat, clearEvent); putEvent / getEvent carry it; a reply to
# fv.video's query is no event (evNothing) and the key after it is the next
# event; the reply's hook (fv.video's push) runs from getEvent.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: FV_EV_BASE"

E=$'\e'
# ev — REPLY = fvd_ev + " base=FV_EV_BASE"
ev() { fvd_ev; REPLY+=" base=$FV_EV_BASE"; }
get() {   # WANT [NOTE]
    local rc
    kt_test_start "getEvent -> $1${2:+ ($2)}"
    fv.drivers.getEvent 0; rc=$?
    ev
    if [[ $rc == 0 && $REPLY == "$1" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc got [$REPLY]"; fi
}

fvd_feed "${E}[1072::102;3u${E}а${E}f${E}[1095::120;5ua${E}ж${E}[1072:1040:102;4u"
get "evKeyDown key=kbAltF char=а base=f" 'kitty Alt+F, Russian'
get "evKeyDown key=kbAltF char=а base=f" 'legacy ESC а: the tables'
get "evKeyDown key=kbAltF char=f base=" 'legacy ESC f: no base known'
get "evKeyDown key=kbCtrlX char=ч base=x" 'kitty Ctrl+X, Russian'
get "evKeyDown key=kbChar char=a base=" 'plain typing: no base'
get "evKeyDown key=kbAltSemiCol char=ж base=;" 'legacy ESC ж'
get "evKeyDown key=kbAltF char=А base=f" 'kitty Alt+Shift+F, Russian'

kt_test_start "a mouse event after a key with a base clears FV_EV_BASE"
fvd_feed "${E}[1072::102;3u${E}[<0;5;3M"
fv.drivers.getEvent 0; r=$FV_EV_BASE
fv.drivers.getEvent 0; ev; r+=" $REPLY"
if [[ $r == "f evMouseDown x=4 y=2 b=1 base=" ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "evNothing (no input) and a resize clear it"
fvd_feed "${E}[1072::102;3u"
fv.drivers.getEvent 0; r=$FV_EV_BASE
fv.drivers.getEvent 0; r+=" $FV_EV_WHAT:[$FV_EV_BASE]"
fv.drivers.clearEvent; FV_EV_BASE=stale
FV_VIDEO_RESIZED=1
fv.video.querySize() { RESULT='24 80'; }
fv.drivers.getEvent 0; r+=" $FV_EV_WHAT:$FV_EV_COMMAND:[$FV_EV_BASE]"
if [[ $r == 'f evNothing:[] evCommand:cmResizeApp:[]' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "clearEvent clears it"
FV_EV_BASE=x
fv.drivers.clearEvent
if [[ -z $FV_EV_BASE ]]; then kt_test_pass "ok"; else kt_test_fail "got [$FV_EV_BASE]"; fi

kt_test_start "putEvent / getEvent carry it (and a put mouse event carries '')"
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltF FV_EV_CHAR='φ' FV_EV_BASE=f
fv.drivers.putEvent
fv.drivers.clearEvent
fv.drivers.getEvent 0; ev; r=$REPLY
fv.drivers.clearEvent
FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=1 FV_EV_MOUSE_Y=1
fv.drivers.putEvent
FV_EV_BASE=stale
fv.drivers.getEvent 0; r+=" | $FV_EV_WHAT [$FV_EV_BASE]"
if [[ $r == 'evKeyDown key=kbAltF char=φ base=f | evMouseDown []' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "the auto-repeat (evMouseAuto) clears it"
r="$(
    fvd_feed "${E}[<0;3;3M"
    __FV_DR_NOW=1000.000000
    fv.drivers.getEvent 0
    # (a live terminal with nothing typed: the reader answers "no key")
    fv.keyboard.getKeyEvent() { FV_KEY_EOF=0 FV_KEY=''; return 1; }
    FV_EV_BASE=stale
    __FV_DR_NOW=1001.000000
    fv.drivers.getEvent 0; printf '%s [%s]' "$FV_EV_WHAT" "$FV_EV_BASE"
)"
if [[ $r == 'evMouseAuto []' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

HOOKS=0
hook() { HOOKS=$(( HOOKS + 1 )); }
kt_test_start "replies are no events: the key after them is the event; the hook ran once from getEvent"
__FV_KB_ONKITTY=hook
fvd_feed "${E}[?5u${E}[?62;22c${E}[1499::102;3u"
fv.drivers.getEvent 0; ev; r="$REPLY hooks=$HOOKS kitty=$__FV_KB_KITTY da1=$__FV_KB_DA1"
if [[ $r == 'evKeyDown key=kbAltF char=כ base=f hooks=1 kitty=5 da1=1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a reply alone on a live pipe: getEvent 0 answers evNothing at once (rc 0), no block"
if mkfifo "$FVD_TMP/fifo" 2>/dev/null && kt_need_timeout; then
    out="$("$KT_TIMEOUT" -k 2 20 bash -c "
source '$FVD_TESTS_DIR/../fv.drivers.sh' 2>/dev/null
hook() { :; }
__FV_KB_ONKITTY=hook
exec {w}<>'$FVD_TMP/fifo'
printf '%s' \$'\\e[?5u' >&\$w
FV_KEY_FD=\$w
fv.drivers.getEvent 0; r=\"\$?:\$FV_EV_WHAT:\$__FV_KB_KITTY\"
fv.drivers.getEvent 0; r+=\" \$?:\$FV_EV_WHAT\"
printf '%s' \"\$r\"" 2>&1)"
    if [[ $out == '0:evNothing:5 0:evNothing' ]]; then kt_test_pass "$out"; else kt_test_fail "got [$out] (rc 124 = it blocked)"; fi
else
    kt_test_pass "SKIP: no mkfifo / timeout here"
fi
__FV_KB_ONKITTY='' __FV_KB_KITTY=-1 __FV_KB_DA1=0

kt_test_log "010_Base.sh completed"
