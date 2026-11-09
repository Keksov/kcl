#!/usr/bin/env bash
# 009_CallerState.sh - the caller's shell state neither changes the answers
# nor is changed by a call:
#   * `shopt -s nocasematch` (case-insensitive [[ == ]] and case) is cleared
#     for each call and restored after it, on every return path;
#   * the caller's locale is back after each entry point: in a UTF-8 caller
#     ${#ж} is still 1 (the unit pins LC_ALL=C locally), with LC_ALL set and
#     with only LC_CTYPE set.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: the caller's nocasematch and locale"

exec {nullfd}</dev/null
FV_KEY_FD=$nullfd

shopt -s nocasematch
# nc BYTES KEY — under nocasematch: decode gives KEY and nocasematch is still on
nc() {
    local v
    printf -v v '%q' "$1"
    kt_test_start "nocasematch on: decode $v -> $2, nocasematch still on"
    fv.keyboard.decode "$1"
    if [[ $FV_KEY == "$2" ]] && shopt -q nocasematch; then kt_test_pass "ok"; else kt_test_fail "got $FV_KEY, nocasematch=$(shopt -q nocasematch && echo on || echo off)"; fi
}
nc $'\eoP' kbAltO                        # Alt-o, then P (not SS3 F1)
nc $'\eOp' kbUnknown                     # SS3 p: not F1
nc $'\e[[a' kbUnknown                    # the Linux console's [[A..E is upper case only
nc $'\e[a' kbShiftUp                     # rxvt lowercase is not [A]
nc $'\e[A' kbUp
nc $'\eOa' kbCtrlUp
nc $'\ex' kbAltX
nc $'\e[<0;10;5m' kbMouse

kt_test_start "nocasematch on: getKeyEvent / pollKeyEvent decode exactly and restore it on every return path (rc 0, 1, 2)"
fv.keyboard.flush
fv.keyboard.feed $'\eOp\eoP'
r=''
fv.keyboard.pollKeyEvent; r+="$?:$FV_KEY:$(shopt -q nocasematch && echo on) "
fv.keyboard.getKeyEvent;  r+="$?:$FV_KEY:$(shopt -q nocasematch && echo on) "
fv.keyboard.getKeyEvent 0; r+="$?:$FV_KEY:$(shopt -q nocasematch && echo on) "
fv.keyboard.getKeyEvent 0; r+="$?:$FV_KEY:$(shopt -q nocasematch && echo on) "
fv.keyboard.getKeyEvent 0; r+="$?:$FV_KEY:$(shopt -q nocasematch && echo on) "
fv.keyboard.getKeyEvent junk; r+="$?:$(shopt -q nocasematch && echo on) "
fv.keyboard.decode ''; r+="$?:$(shopt -q nocasematch && echo on)"
if [[ $r == '0:kbUnknown:on 0:kbUnknown:on 0:kbAltO:on 0:kbChar:on 1:kbNoKey:on 2:on 1:on' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi
shopt -u nocasematch

kt_test_start "nocasematch off stays off"
fv.keyboard.decode $'\e[A'
fv.keyboard.getKeyEvent 0
if ! shopt -q nocasematch; then kt_test_pass "ok"; else kt_test_fail "turned on"; fi

# --- locale ---------------------------------------------------------------------
printf '%s' $'x\e[Aж' > "$FVK_TMP/loc.bin"
for setup in 'export LC_ALL=C.UTF-8' 'unset LC_ALL; export LC_CTYPE=C.UTF-8'; do
    kt_test_start "the caller's locale is back after every entry point ($setup): \${#ж} stays 1"
    out=$(bash -c "
$setup
source '$FVK_TESTS_DIR/../fv.keyboard.sh'
r=''
exec 7<'$FVK_TMP/loc.bin'; FV_KEY_FD=7
w=ж
fv.keyboard.decode \$'\\e[1;5D' >/dev/null; r+=\${#w}
fv.keyboard.pollKeyEvent; r+=\${#w}
fv.keyboard.getKeyEvent; r+=\${#w}
fv.keyboard.getKeyEvent 0; r+=\${#w}
fv.keyboard.getKeyEvent 1; r+=\${#w}
fv.keyboard.getKeyEvent; r+=\${#w}
fv.keyboard.getKeyEvent bad; r+=\${#w}
fv.keyboard.feed x; fv.keyboard.flush; r+=\${#w}
shopt -s nocasematch; fv.keyboard.decode a >/dev/null; r+=\${#w}
printf '%s|%s|%s' \"\$r\" \"\${LC_ALL-unset}\" \"\${LC_CTYPE-unset}\"" 2>&1)
    case $setup in
        export\ LC_ALL*) want='111111111|C.UTF-8|unset' ;;
        *) want='111111111|unset|C.UTF-8' ;;
    esac
    if [[ $out == "$want" ]]; then kt_test_pass "$out"; else kt_test_fail "got '$out' want '$want'"; fi
done
exec {nullfd}<&-

kt_test_start "nocasematch + IFS=0123456789: the return status is kept (rc 2 for a bad timeout, rc 1 for an empty decode)"
exec {nullfd2}</dev/null
FV_KEY_FD=$nullfd2
shopt -s nocasematch; IFS=0123456789
r=''
fv.keyboard.getKeyEvent junk; r+=$?
fv.keyboard.decode ''; r+=$?
IFS=$' \t\n'; shopt -u nocasematch
exec {nullfd2}<&-
if [[ $r == 21 ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r"; fi

kt_test_log "009_CallerState.sh completed"
