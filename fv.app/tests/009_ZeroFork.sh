#!/usr/bin/env bash
# 009_ZeroFork.sh - fv.app never forks (PLAN.md rule 1); the resize's
# `stty size` (fv.video's querySize, on a real terminal) is the one fork on
# an event path, and it is not fv.app's:
#   * with PATH='' (no external command can run): a headless application,
#     its first paint, Run over the scripted terminal with idle ticks, keys,
#     Alt+1, cmTile / cmCascade, cmNext / cmPrev, a resize (from the scripted
#     source), a modal dialog, a keyboard drag, the end of input; then
#     setAppPalette and Done; nothing prints "command not found";
#   * a real fv.drivers.getEvent reading keys from a file with PATH='';
#   * the static scan (fv.video's 006 scanner, through fv.views' test lib):
#     no $( ), backtick, process substitution, pipe, ( ) subshell, & or
#     coproc on any code line of fv.app.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: no forks"

class TZApp : TApplication
    public
        override proc HandleEvent
end
TZApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbF7 ]; then
        TWindow.new zd 20 5 60 15 'Dialog' 0
        fv.views.execView "$FV_DESKTOP" zd
        ZLOG+="zd=$RESULT;"
        zd.delete
        fv.views.clearEvent "$this"
    fi
}
build TZApp

kt_test_start "PATH='': Init, the first paint, Run over the scripted terminal (idle, keys, Alt+1, tile, cascade, next, prev, a resize, a modal dialog, a keyboard drag, the end of input), setAppPalette, Done"
fva_classes
out=$( {
    ZLOG=''
    fva_app 80 24 TZApp
    PATH=''
    fva_events 'nothing' 'key kbDown' 'key kbAlt1' 'cmd cmTile' 'cmd cmCascade' 'cmd cmNext' 'cmd cmPrev' \
        'resize 100 30' 'nothing' 'key kbF7' 'nothing' 'key kbEsc' 'cmd cmResize' 'key kbRight' 'key kbEnter' 'nothing'
    app.Run
    fv.app.setAppPalette 9 1 2 0
    fv.app.setAppPalette 9 3 4 1
    r="$ZLOG|$__FV_VW_EOF|${#FVA_Q[@]}|$FV_SCREEN_W"
    app.delete
    fva_noevents
    printf '%s|%s' "$r" "$FV_APP"
} 2>&1 )
if [[ $out == 'zd=cmCancel;|1|0|100|' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "PATH='': a real fv.drivers.getEvent reading keys (Alt+X) from a file: Run ends by cmQuit"
printf '\033OQ\033x' > "$FVW_TMP/keys"
out=$( {
    fva_app
    exec {kf}<"$FVW_TMP/keys"
    FV_KEY_FD=$kf
    PATH=''
    app.Run
    r="$__FV_VW_EOF"
    app.delete
    exec {kf}<&-
    printf '%s' "$r"
} 2>&1 )
if [[ $out == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "the static scan: no fork construct on any code line of fv.app.sh"
bad=''
n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvw_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$FVA_TESTS_DIR/../fv.app.sh"
if [[ -z $bad ]]; then kt_test_pass "ok ($n lines)"; else kt_test_fail "$bad"; fi

kt_test_log "009_ZeroFork.sh completed"
