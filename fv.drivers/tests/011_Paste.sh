#!/usr/bin/env bash
# 011_Paste.sh - a bracketed paste as an event (design P3 §4.5, row 10.8):
# fv.keyboard's kbPaste becomes FV's evCommand cmPasteText (FPC 2025
# drivers.inc), the text in FV_EV_INFO, its length in FV_EV_ID — ONE event,
# so a pasted newline is never a kbEnter (which would press a dialog's
# default button mid-paste); the event after it is the next key; like a key
# it ends evMouseAuto's held state (L2); putEvent keeps it whole.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: bracketed paste -> evCommand cmPasteText"

P0=$'\e[200~' P1=$'\e[201~'

kt_test_start "a paste: one evCommand cmPasteText, FV_EV_INFO the text, FV_EV_ID its length; rc 0, RESULT evCommand"
fvd_feed "${P0}hello${P1}"
fv.drivers.getEvent 0; rc=$?
if [[ $rc == 0 && $FV_EV_WHAT == evCommand && $FV_EV_COMMAND == cmPasteText && $FV_EV_INFO == hello && $FV_EV_ID == 5 && $RESULT == evCommand && -z $FV_EV_KEY ]]; then kt_test_pass "ok"
else fvd_ev; kt_test_fail "rc=$rc $REPLY"; fi

kt_test_start "a pasted newline (LF, CR) stays in the text: no kbEnter event before, inside or after it; then the typed key"
fvd_feed "${P0}a"$'\n'"b"$'\r'"c${P1}x"
got=''
while fv.drivers.getEvent 0; do
    [[ $FV_EV_WHAT == evNothing ]] && break
    if [[ $FV_EV_WHAT == evKeyDown ]]; then got+="key:$FV_EV_KEY:$FV_EV_CHAR|"; else got+="$FV_EV_WHAT:$FV_EV_COMMAND:${#FV_EV_INFO}|"; fi
done
if [[ $got == 'evCommand:cmPasteText:5|key:kbChar:x|' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "UTF-8 text keeps its characters; FV_EV_ID its bytes (FV's Id: the size), 7 for жи中"
fvd_feed "${P0}жи中${P1}"
fv.drivers.getEvent 0
if [[ $FV_EV_INFO == жи中 && $FV_EV_ID == 7 ]]; then kt_test_pass "ok"; else kt_test_fail "[$FV_EV_INFO] $FV_EV_ID"; fi

kt_test_start "F8: FV_EV_ID the bytes whatever the caller's locale: C, C.UTF-8, an LC_ALL the C library rejects; the caller's LC_ALL kept"
# (the caller's locale in a function scope, the setlocale warnings of a
# rejected value silenced: fv.keyboard's own scope warns on its restore)
f8() {
    local LC_ALL
    { LC_ALL=$1; } 2>/dev/null
    fv.drivers.getEvent 0 2>/dev/null
    got+="$FV_EV_ID:$LC_ALL|"
}
got=''
for loc in C C.UTF-8 xx_NOT.LOCALE; do
    fvd_feed "${P0}жи中a${P1}"
    f8 "$loc" 2>/dev/null
done
if [[ $got == '8:C|8:C.UTF-8|8:xx_NOT.LOCALE|' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "putEvent keeps the paste whole for the next getEvent"
fvd_feed "${P0}keep me${P1}"
fv.drivers.getEvent 0
fv.drivers.putEvent
fv.drivers.clearEvent
fv.drivers.getEvent 0
if [[ $FV_EV_WHAT == evCommand && $FV_EV_COMMAND == cmPasteText && $FV_EV_INFO == 'keep me' ]]; then kt_test_pass "ok"; else fvd_ev; kt_test_fail "$REPLY"; fi

kt_test_start "a paste ends evMouseAuto's held state (as a key does, L2)"
fvd_feed $'\e[<0;5;5M'"${P0}x${P1}"
fv.drivers.getEvent 0; a="$FV_EV_WHAT:$__FV_DR_AA"
fv.drivers.getEvent 0; b="$FV_EV_WHAT:$__FV_DR_AA"
if [[ $a == evMouseDown:1 && $b == evCommand:0 ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b"; fi

kt_test_log "011_Paste.sh completed"
