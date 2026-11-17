#!/usr/bin/env bash
# 008_CallerState.sh - the caller's shell state neither changes the answers
# nor is changed by a call:
#   * `shopt -s nocasematch`: the same events (key names, mouse kinds, SGR
#     press M vs release m) and nocasematch still on after every entry point,
#     on every return path (rc 0, 1, 2);
#   * the caller's locale is back after each entry point: in a UTF-8 caller
#     ${#ж} stays 1, with LC_ALL set and with only LC_CTYPE set;
#   * a caller IFS of ':' changes nothing.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: the caller's nocasematch, locale and IFS"

STREAM=$'\eoP\e[<0;3;3M\e[<0;3;3m\eOp\e[A'
# events — REPLY = every event of the fed STREAM, then the end-of-input rc
events() {
    local r=''
    fvd_feed "$STREAM"
    __FV_DR_NOW=100
    while fv.drivers.getEvent 0; do fvd_ev; r+="$REPLY|"; done
    REPLY="$r$?"
}

events; base=$REPLY

kt_test_start "nocasematch on: the same events, nocasematch still on"
shopt -s nocasematch
events; got=$REPLY
on=$(shopt -q nocasematch && echo on)
shopt -u nocasematch
if [[ $got == "$base" && $on == on && $base == *'evMouseDown x=2 y=2 b=1|evMouseUp x=2 y=2|'* ]]; then kt_test_pass "ok"; else kt_test_fail "got [$got] base [$base] nocasematch=$on"; fi

kt_test_start "nocasematch on: every entry point and return path leaves it on"
shopt -s nocasematch
r=''
fvd_feed 'x'
fv.drivers.getEvent 0; r+="$?$(shopt -q nocasematch && echo +)"
fv.drivers.getEvent 0; r+="$?$(shopt -q nocasematch && echo +)"
fv.drivers.getEvent bad; r+="$?$(shopt -q nocasematch && echo +)"
fv.drivers.putEvent; fv.drivers.clearEvent; r+="$(shopt -q nocasematch && echo +)"
fv.drivers.initEvents ANY; r+="$?$(shopt -q nocasematch && echo +)"
fv.drivers.doneEvents; r+="$?$(shopt -q nocasematch && echo +)"
shopt -u nocasematch
if [[ $r == '0+1+2++2+0+' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "a caller IFS of ':' changes nothing"
IFS=: events; got=$REPLY
if [[ $got == "$base" ]]; then kt_test_pass "ok"; else kt_test_fail "[$got]"; fi

printf '%s' $'x\e[<0;1;1Mж' > "$FVD_TMP/loc.bin"
# (the child starts without the runner's own LC_CTYPE: macOS images export one)
for setup in 'export LC_ALL=C.UTF-8' 'unset LC_ALL; export LC_CTYPE=C.UTF-8'; do
    kt_test_start "the caller's locale is back after every entry point ($setup): \${#ж} stays 1"
    out=$("$BASH" -c "unset LC_CTYPE
$setup
source '$FVD_TESTS_DIR/../fv.drivers.sh'
r=''
exec 7<'$FVD_TMP/loc.bin'; FV_KEY_FD=7
w=ж
fv.drivers.getEvent; r+=\${#w}
fv.drivers.getEvent; r+=\${#w}
fv.drivers.getEvent; r+=\${#w}\$FV_EV_CHAR
fv.drivers.getEvent; r+=\${#w}
fv.drivers.getEvent bad; r+=\${#w}
fv.drivers.putEvent; fv.drivers.clearEvent; r+=\${#w}
fv.drivers.initEvents; fv.drivers.doneEvents; r+=\${#w}
printf '%s|%s|%s' \"\$r\" \"\${LC_ALL-unset}\" \"\${LC_CTYPE-unset}\"" 2>&1)
    case $setup in
        export\ LC_ALL*) want='111ж1111|C.UTF-8|unset' ;;
        *) want='111ж1111|unset|C.UTF-8' ;;
    esac
    if [[ $out == "$want" ]]; then kt_test_pass "$out"; else kt_test_fail "got '$out' want '$want'"; fi
done

kt_test_log "008_CallerState.sh completed"
