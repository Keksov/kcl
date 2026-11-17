#!/usr/bin/env bash
# 010_CallerState.sh - the caller's shell state neither changes what the
# unit's calls do nor is changed by them: one scene (a headless application
# with windows whose names differ only in case, W1 and w1, a Cyrillic title;
# Run over the scripted terminal: idle ticks, a key to the focused leaf,
# Alt+1, cmTile, cmCascade, cmNext / cmPrev, a resize, a modal dialog that
# runs to the end of input (a TWindow takes no cmCancel);
# setAppPalette (two symbols allocated); the rows read
# back; Done) runs in a child shell under each setup - nocasematch,
# failglob, nullglob, noglob, extglob on and off, globasciiranges off, odd
# IFS values (digits, '-', letters, empty), set -eu with pipefail, a C
# locale, all at once - and must give the reference output; the setup's
# options, IFS and locale are the same after the scene as before. The
# classes and the application are made before the setup (kklass's `.new`
# and `build` are not this unit's: K-3), the calls run after it; under the
# IFS of letters the dialog is removed first and `inherited` is replaced by
# the built-in body (kklass K-3), compared with a run without the dialog.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: the caller's shell state"

STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
MAKE="
source '$FVA_TESTS_DIR/fva_testlib.sh'
source '$FVA_TESTS_DIR/../fv.app.sh'
FVW_TMP='$FVW_TMP'
fva_classes
class TCApp : TApplication
    public
        override proc HandleEvent
end
TCApp.HandleEvent() {
    # (kklass K-3: inherited fails under an IFS of letters; the built-in body then)
    case \$IFS in *a*) fv.app._appEvent \"\$this\" ;; *) inherited HandleEvent \"\$@\" ;; esac
    if [ \"\$FV_EV_WHAT\" = evKeyDown ] && [ \"\$FV_EV_KEY\" = kbF7 ]; then
        if [[ -n \${__FV_VW_LIVE[dz]-} ]]; then
            fv.views.execView \"\$FV_DESKTOP\" dz
            r+=\"dz=\$RESULT;\"
        fi
        fv.views.clearEvent \"\$this\"
    fi
}
build TCApp
fva_app 80 24 TCApp
TWindow.new W1 5 3 45 13 'Окно' 3
W1_data[Options]=\$(( W1_data[Options] | FV_OF_TILEABLE ))
fv.views.insert \"\$FV_DESKTOP\" W1
TWindow.new dz 20 5 60 15 'Dialog' 0
cut() { local LC_ALL=C.UTF-8; fv.video.getRow \"\$1\" || :; r+=\"\${RESULT:\$2:\$3}|\${REPLY:\$2:\$3};\"; }
bn() { local LC_ALL=C.UTF-8; fv.views.getBounds \"\$1\" || :; r+=\"\$1=\$RESULT;\"; }
"
SCENE='
r=""
case $IFS in *a*) dz.delete ;; esac
fva_events nothing "key kbDown" "key kbAlt1" "cmd cmTile" nothing "key kbAlt3" "cmd cmCascade" "cmd cmNext" "cmd cmPrev" \
    "resize 90 30" nothing "key kbF7" "cmd cmClose" "key kbAltX"
app.Run
r+="eof=$__FV_VW_EOF;cur=${app__fvdesktop_data[Current]};"
bn w1; bn W1; bn w2; bn app__fvstatus
cut 0 0 30; cut 29 0 12
fv.app.setAppPalette 1 10 11 0; fv.app.setAppPalette 2 12 13 1
fv.app.setAppPalette 200 1 1 || r+="rc$?;"
r+="pal=${__FV_VW_APAL:0:8};err=$__FV_VW_ERRSYM;"
case $IFS in *a*) __s=$IFS; IFS=" "; app.delete; IFS=$__s ;; *) app.delete ;; esac
fva_noevents
r+="app=$FV_APP;"
printf "%s" "$r"
'
run() {   # SETUP -> OUT = before-state # scene output # after-state
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
$MAKE
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}

run ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "reference run: the scene as expected"
if [[ $ref == 'dz=cmCancel;eof=1;cur='*'pal='*';err=W;app=;' && $ref != *'command not found'* && $ref == *'rc2;'* ]]; then kt_test_pass "ok"; kt_test_log "# ref $ref"
else kt_test_fail "got [$OUT]"; fi

for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS='0123456789 '" "IFS='-'" 'IFS=' \
    'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='-0123456789Ww'; export LC_ALL=C"; do
    kt_test_start "same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs [$ref]; state before [$before] after [$after]"; fi
done

run "dz.delete"
refnd=${OUT#*#} refnd=${refnd%#*}
kt_test_start "under an IFS of letters (the dialog removed before: K-3): the same output as a run without the dialog, the state kept"
run "IFS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.'"
got=${OUT#*#} got=${got%#*}
before=${OUT%%#*} after=${OUT##*#}
want=$refnd
if [[ $want == eof=0* && $got == "$want" && $before == "$after" ]]; then kt_test_pass "ok"; else kt_test_fail "output [$got] vs [$want]; state before [$before] after [$after]"; fi

kt_test_log "010_CallerState.sh completed"
