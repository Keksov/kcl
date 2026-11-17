#!/usr/bin/env bash
# 001_Contract.sh - the kcl-wide contract for fv.views (kcl/README.md §1):
# source integrity; loads (with kklass_pascal, fv.video and fv.drivers by
# name), re-loads and runs its main path under `set -eu`; `kk.unit --forget`
# + a re-source under set -e keeps the live tree (the private arrays and the
# readonly constants) and rebuilds the classes; a failing call returns to the
# caller from `if` / `||`; nothing is ever printed on stdout, also inside
# $( ); using the unit leaves only its constants and FV_RECT_* / FV_POINT_* /
# FV_MIN_* / FV_MAX_* (and FV_DRAW_* / FV_CLIP_*, FV_COMMANDSETCHANGED),
# __FV_VW_*, RESULT, the classes' kklass tables and fv.views.* / TView.* /
# TGroup.* / TFrame.* / TWindow.* behind (instances deleted; kklass's own
# build globals and its __kkc. / __kkm. functions of the four classes
# allowed); the main path draws too (a frame, locks, show / hide, drawPart)
# and runs the events (a window, focus, a message, commands, a modal view
# at the end of input); the public API of the three stages exists;
# the test lib's shims (dispatch and write counters), buffer reader and
# fvw_budget work.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVW_TESTS_DIR/.." && pwd)/fv.views.sh"
KBOOL="$(cd "$FVW_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the public API of stages 2c-1, 2c-2, 2c-3 and 2d is defined"
miss=''
for f in insert insertBefore delete makeFirst putInFrontOf first last next prev nextView prevView \
    getBounds getExtent locate moveTo growTo changeBounds makeLocal makeGlobal mouseInView isView \
    drawView redraw drawPart show hide lock unlock lockScreenUpdate unlockScreenUpdate getColor resetPalette \
    writeStr writeChar writeCStr writeLine fill _frameBorder \
    message clearEvent setState select focus focusNext selectNext \
    enableCommands disableCommands commandEnabled getCommands setCommands \
    resetCursor setCursor showCursor hideCursor blockCursor normalCursor \
    execView endModal topView mouseEvent dragView \
    _virt _changed _setCurrent _newReserved; do
    declare -F "fv.views.$f" >/dev/null || miss+=" fv.views.$f"
done
for c in TView TGroup TFrame TWindow; do declare -F "$c.new" >/dev/null || miss+=" $c.new"; done
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$TMP/setu.err")"; rc=$?
    err="$(<"$TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}

expect_clean "the unit loads under set -eu, with its dependencies" \
    "source '$UNIT'; [[ -n \${__KK_UNITS[fv.video]-} && -n \${__KK_UNITS[fv.drivers]-} && -n \${__KK_UNITS[fv.views]-} ]]; declare -F TGroup.new >/dev/null"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.views by name under set -eu" "source '$KBOOL'; kk.uses fv.views; declare -F fv.views.insert >/dev/null"

MAIN="
TGroup.new desk 0 1 80 24
TGroup.new w1 0 0 40 20
TGroup.new w2 40 0 80 20
TView.new lab 1 1 10 2
w1_data[GrowMode]=\$FV_GF_GROWALL
fv.views.insert desk w1
fv.views.insert desk w2
fv.views.insertBefore w1 lab ''
fv.views.makeFirst w1
fv.views.putInFrontOf w2 w1
fv.views.first desk; [[ \$RESULT == w2 ]]
fv.views.last desk; [[ \$RESULT == w1 ]]
fv.views.next w1; fv.views.prev w1
if fv.views.nextView w1; then exit 9; fi
if fv.views.prevView w2; then exit 9; fi
fv.views.locate w1 1 1 30 15
fv.views.moveTo w1 2 2
fv.views.growTo w1 20 10
fv.views.changeBounds desk 0 1 100 30
fv.views.getBounds w1; [[ \$RESULT == '22 8 42 18' ]]
fv.views.getExtent lab
fv.views.makeLocal lab 30 40; fv.views.makeGlobal lab 0 0
fv.views.mouseInView lab 23 10
if fv.views.mouseInView lab 0 0; then exit 9; fi
w1.GetHelpCtx; desk.GetHelpCtx
w1.SizeLimits; w1.CalcBounds 1 1
w1.MoveTo 3 3; w1.GrowTo 10 5; w1.Locate 0 0 5 5; w1.MakeFirst; w1.PutInFrontOf ''
desk.Insert lab 2>/dev/null || :
fv.views.delete w1 lab
desk.InsertBefore lab w1
exec {FV_VIDEO_OUT_FD}>/dev/null
fv.video.initScreen
desk_data[State]=\$(( desk_data[State] | FV_SF_EXPOSED ))
TFrame.new fr 0 0 20 10
fv.views.insert w2 fr
fv.views.drawView desk
fv.views.redraw w2
fv.views.lock desk; fv.views.moveTo w2 41 1; fv.views.unlock desk
fv.views.lockScreenUpdate; fv.views._frameBorder fr; fv.views.unlockScreenUpdate
fv.views.hide w2; fv.views.show w2
fv.views.getColor fr 3; [[ \$RESULT == 2 ]]
fv.views.resetPalette w2; fv.views.resetPalette
fv.views.drawPart lab fv.views.isView 0 1; fv.views.drawPart w2 fv.views.isView 0 1 || :
fv.views.writeStr 0 0 x 1 || :
w2.DrawView; w2.Hide; w2.Show; desk.Lock; desk.Unlock
TWindow.new tw 30 2 60 12 Win 1; fv.views.insert desk tw
desk_data[State]=\$(( desk_data[State] | FV_SF_SELECTED | FV_SF_MODAL )); fv.views.setState desk \$FV_SF_FOCUSED 1
fv.views.select w1; fv.views.select tw; fv.views.focusNext desk 0; fv.views.selectNext desk 1; tw.Select; desk.SelectNext 0
fv.views.message desk evBroadcast cmSelectWindowNum 1 || :
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbTab; fv.views._virt desk HandleEvent
fv.views.disableCommands cmX; fv.views.enableCommands cmX; fv.views.commandEnabled cmQuit; fv.views.getCommands; fv.views.setCommands cmZoom
fv.views.setCursor tw 1 1; fv.views.showCursor tw; fv.views.blockCursor tw; fv.views.normalCursor tw; fv.views.hideCursor tw; fv.views.resetCursor tw
eofev() { FV_EV_WHAT=evNothing; return 1; }; __FV_VW_GETEVENT=eofev
TWindow.new dl 5 5 20 10 Dlg 0; fv.views.execView desk dl; [[ \$RESULT == cmCancel ]]; desk.ExecView dl >/dev/null
fv.views.mouseEvent tw 4 || :; fv.views.endModal tw cmQuit; [[ \${desk_data[EndState]} == cmQuit ]]
dl.delete; tw.delete; __FV_VW_EOF=0 __FV_VW_GETEVENT=fv.drivers.getEvent; unset -f eofev
fv.views.insert nosuch lab || :
fv.views.locate w1 x 0 0 0 || :
TView.new lab 0 0 1 1 2>/dev/null || :
TView.new a__fvb 0 0 1 1 2>/dev/null || a__fvb.delete
fv.views.isView lab || lab.delete
w2.delete
desk.delete
"
expect_clean "the main path under set -eu (tree, navigation in if, geometry, GrowMode, the aliases, refusals in ||, the guard)" "source '$UNIT'
$MAIN"

expect_clean "kk.unit --forget + re-source under set -e: the live tree, its cache and the constants are kept, the classes rebuilt, new instances work" "
source '$UNIT'
TGroup.new desk 0 0 80 24
TView.new v 1 2 3 4
fv.views.insert desk v
kk.unit --forget fv.views
source '$UNIT'
[[ \${__FV_VW_AX[v]} == 1 && \${__FV_VW_LIVE[desk]} == 1 && \${desk_views[*]} == v && \$FV_SF_VISIBLE == 1 ]]
[[ \${FV_SF_VISIBLE@a} == *r* ]]
fv.views.moveTo v 5 5
fv.views.getBounds v; [[ \$RESULT == '5 5 7 7' ]]
TGroup.new w 0 0 9 9
fv.views.insert desk w
fv.views.first desk; [[ \$RESULT == w ]]
desk.delete
fv.views.isView v && exit 9 || :"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
TGroup.new g 0 0 9 9
TView.new v 0 0 1 1
if fv.views.first g; then echo got; else echo none; fi
fv.views.insert g nosuch || echo rc\$?
fv.views.delete g v || echo rc\$?
fv.views.moveTo v 1 || echo rc\$?
TView.new g 0 0 1 1 2>/dev/null || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nrc1\nrc2\nrc1\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout, also inside \$( ) and a pipeline (refusals and the guard's Error lines go to stderr)"
out="$(bash -c "
source '$UNIT'
x=\$( $MAIN )
y=\$(true | { TGroup.new g 0 0 9 9; TView.new g 0 0 1 1 2>/dev/null; fv.views.first g; fv.views.getBounds g; :; })
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
# (MAIN's two GetHelpCtx calls are kklass funcs: inside $( ) kklass prints a func's
# value, 0 each; the plain functions print nothing)
if [[ $out == '[00][]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (FV_* constants and var parameters, __FV_VW_*, RESULT, FV_DRAW_* / FV_CLIP_*, FV_COMMANDSETCHANGED, TView* / TGroup* / TFrame* / TWindow* class tables, fv.views.* / TView.* / TGroup.* / TFrame.* / TWindow.* functions)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
kk.uses kklass_pascal fv.video fv.drivers
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
$MAIN
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_(SF|OF|GF|DM|HC|EM|WF|WP|WN|FM)_[A-Z]+|FV_DRAW_(VIEW|X|Y|PAL)|FV_CLIP_[XY][12]|FV_COMMANDSETCHANGED|FV_MINWINSIZE_[XY]|FV_(RECT_[AB][XY]|POINT_[XY]|MIN_[XY]|MAX_[XY])|__FV_VW_[A-Z0-9]+|RESULT|(TView|TGroup|TFrame|TWindow)_[A-Za-z_]+|KK_UNIT_DIR|METHOD_BODY|METHOD_WRAPPER|__KK_SITE_[A-Z0-9]+|__kk_ft)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^((fv\.views|TView|TGroup|TFrame|TWindow)\.|__kk[cm]\.(TView|TGroup|TFrame|TWindow)(\.|$))' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi


kt_test_start "the test lib: the dispatch counter (.new, obj.M, inherited, .call) and the write counter count, keep rc and RESULT, and unwrap"
class TLibT : TView
    public
        override func GetHelpCtx
end
TLibT.GetHelpCtx() { inherited GetHelpCtx "$@"; RESULT="t$RESULT"; }
build TLibT
fvw_count_on; FVW_CALLS=0
TLibT.new lt 0 0 1 1; a=$FVW_CALLS
FVW_CALLS=0; lt.GetHelpCtx; b="$FVW_CALLS:$RESULT"
FVW_CALLS=0; lt.call GetHelpCtx; c="$FVW_CALLS:$RESULT"
FVW_CALLS=0; fv.views._virt lt SizeLimits; d=$FVW_CALLS
fvw_count_off
FVW_CALLS=0; lt.GetHelpCtx; e=$FVW_CALLS
fvw_screen 20 3
fvw_writes_on; FVW_WRITES=0
fv.video.writeStr 1 0 'abc' 1; fv.video.writeBuf 0 1 'xy' '22'; fv.video.fillRect 0 2 3 1 3 '#'; w=$FVW_WRITES
fv.video.writeStr x 0 'abc' 1; wr=$?
fvw_writes_off
FVW_WRITES=0; fv.video.writeStr 0 0 'z' 1; w2=$FVW_WRITES
fvw_row 0; r0="$RESULT|$REPLY"
fvw_row 2; r2=$RESULT
left=''
for f in "${FVW_DISPATCHERS[@]}" "${FVW_WRITERS[@]}"; do declare -F "__fvw_orig_$f" >/dev/null && left+=" $f"; done
want='1 2:t0 2:t0 0 0 3 2 0'
got="$a $b $c $d $e $w $wr $w2"
if [[ $got == "$want" && ${r0:0:4} == 'zabc' && ${r0#*|} == 11110000000000000000 && ${r2:0:3} == '###' && -z $left ]]; then kt_test_pass "ok"
else kt_test_fail "got [$got] want [$want] row0=[$r0] row2=[$r2] left=[$left]"; fi
lt.delete

kt_test_start "the test lib: a user override + inherited = 2 dispatches; fvw_budget logs the count and passes at the limit"
TLibT.new lb 0 0 1 1
fvw_count_on; FVW_CALLS=0; lb.GetHelpCtx; n=$FVW_CALLS; fvw_count_off
if [[ $n == 2 ]]; then kt_test_pass "a user override + inherited = $n dispatches"; else kt_test_fail "$n"; fi
fvw_budget "lib self-test: GetHelpCtx through an override" 2 lb.GetHelpCtx
lb.delete
kt_test_log "001_Contract.sh completed"
