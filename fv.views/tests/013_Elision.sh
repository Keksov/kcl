#!/usr/bin/env bash
# 013_Elision.sh - the virtual elision (design §1.4, risk R3, "probe first"
# item 2): fv.views._virt runs a built-in virtual's plain body without a
# kklass dispatch unless the view's class overrides the method; it reads the
# owner table on every call (no cache).
#   * stage 2c-2: Draw (a proc) and GetPalette (a func) of TView, TGroup and
#     TFrame overridden with `inherited`: 0 / 2 dispatches, the RESULT rule
#     both ways, and in the painter (one dispatch per Draw, the override's
#     palette resolved into the drawing, fields intact, RESULT kept);
#   * stage 2c-3: every built-in kklass body passes its plain body's rc
#     on (`... || return`): a failing Valid / Execute reached through an
#     override's `inherited ... || return` and the failing aliases keep it;
#     a bare failing `inherited` as an override's last command loses it
#     (kklass K-2, pinned);
#   * stage 2c-3: HandleEvent, SetState, EndModal (procs), Valid, Execute
#     (funcs) of TView / TGroup and TWindow's HandleEvent, SetState,
#     GetPalette, GetTitle, InitFrame, Close overridden with `inherited`:
#     0 / 2 dispatches (also through a TWindow subclass that overrides
#     nothing), the RESULT rule both ways (Valid's refusal: rc 1, the
#     caller's RESULT), through the dispatch (a key to a user group's user
#     Current: 4), a select seen by SetState overrides, execView of a user
#     group (its Execute, Valid and EndModal overrides), a user TWindow
#     (InitFrame at construction, GetTitle on the frame, Close by cmClose);
#   * every built-in virtual of stage 2c-1 (TView ChangeBounds CalcBounds
#     SizeLimits GetHelpCtx, TGroup ChangeBounds GetHelpCtx) overridden with
#     `inherited` in user subclasses whose fields are named like common
#     locals (i k n x y s d r c f v o w h): the dispatch counts (0 without an
#     override, also for a subclass that inherits the built-in; 2 = the
#     override + its inherited), the results, the user's fields intact;
#   * the RESULT rule both ways, for the supported body forms: a proc leaves
#     the caller's RESULT (also when its body sets RESULT); a func answers by
#     setting RESULT and ending WITHOUT an explicit `return`; it fails with an
#     explicit `return N` (N != 0), which leaves the caller's RESULT; the rc
#     is the body's (a test class registered in __FV_VW_IMPL, and its user
#     subclass);
#   * the two func shapes that are NOT supported, pinned as kklass behaves
#     today (a kklass change shows up here): an explicit `return 0` loses the
#     RESULT (the caller's stays; also after `inherited`), a failing last
#     command without `return` loses the rc (rc 0, RESULT kept) - so
#     TGroup.GetHelpCtx through such a Current answers the group's own;
#   * kk.class --forget + a redefinition with / without the override: the
#     next instance takes the new decision at once;
#   * one scene (a group resize by GrowMode through user overrides, locate
#     clamped by a user SizeLimits, GetHelpCtx through Current) in child
#     shells under set -eu, nocasematch, odd IFS values and all at once (set
#     after the classes are built: kklass's own class builder needs a sane IFS): the
#     same output as plain bash.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: the virtual elision"

# the user classes, shared by this process and the child shells
cat > "$FVW_TMP/classes.sh" <<'EOF'
# the arguments as one string, joined by a blank under any caller IFS
ulog_args() { local IFS=' '; REPLY="$*"; }
class TUv : TView
    public
        var i
        var k
        var n
        var x
        var y
        var s
        var d
        var r
        var c
        var f
        var v
        var o
        var w
        var h
        var log
        override proc ChangeBounds
        override proc CalcBounds
        override proc SizeLimits
        override func GetHelpCtx
end
TUv.ChangeBounds() {
    ulog_args "$@"; log+="CB($REPLY)"
    i=1 k=2 n=3 x=4 y=5 s=6 d=7 r=8 c=9 f=10 v=11 o=12 w=13 h=14
    RESULT=clobbered-by-a-proc
    inherited ChangeBounds "$@"
}
TUv.CalcBounds() { ulog_args "$@"; log+="CA($REPLY)"; inherited CalcBounds "$@"; FV_RECT_BX=$(( FV_RECT_BX + 1 )); }
TUv.SizeLimits() { log+="SL"; inherited SizeLimits "$@"; FV_MIN_X=3 FV_MIN_Y=2; }
TUv.GetHelpCtx() { inherited GetHelpCtx "$@"; RESULT="u$RESULT"; }
build TUv

class TUg : TGroup
    public
        var i
        var k
        var n
        var x
        var s
        var log
        override proc ChangeBounds
        override func GetHelpCtx
end
TUg.ChangeBounds() { ulog_args "$@"; log+="GCB($REPLY)"; i=a k=b n=c x=d s=e; inherited ChangeBounds "$@"; }
TUg.GetHelpCtx() { inherited GetHelpCtx "$@"; RESULT="g$RESULT"; }
build TUg

# a subclass of each built-in that overrides nothing
class TKidV : TView
    public
        var i
end
build TKidV
class TKidG : TGroup
    public
        var k
end
build TKidG
EOF
source "$FVW_TMP/classes.sh"

TView.new pv 0 0 10 5
TKidV.new kidv 0 0 10 5
TUv.new uv 0 0 10 5
TGroup.new pg 0 0 40 20
TKidG.new kg 0 0 40 20
TUg.new ug 0 0 40 20

count() {   # CMD... -> REPLY = dispatches
    fvw_count_on || return 1
    FVW_CALLS=0
    "$@"
    REPLY=$FVW_CALLS
    fvw_count_off
}

kt_test_start "the elision decision: 0 dispatches for the built-ins and for subclasses that inherit them, 2 (override + inherited) for each user override"
out=""
for vw in pv kidv uv pg kg ug; do fv.views.isView "$vw" || out+="[no view $vw]"; done
for m in 'ChangeBounds 0 0 10 5' 'CalcBounds 0 0' 'SizeLimits' 'GetHelpCtx'; do
    for vw in pv kidv uv; do count fv.views._virt "$vw" $m; out+="$REPLY"; done
    out+=' '
done
for m in 'ChangeBounds 0 0 40 20' 'GetHelpCtx'; do
    for vw in pg kg ug; do count fv.views._virt "$vw" $m; out+="$REPLY"; done
    out+=' '
done
# (a view's ChangeBounds does not call SizeLimits: each override = exec + parent)
want='002 002 002 002 002 002 '
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "results through the overrides: CalcBounds (+1 on BX), SizeLimits (min 3x2), GetHelpCtx (u / g prefixes, the group asks Current)"
fv.views.insert ug uv
uv_data[GrowMode]=$FV_GF_GROWHIX uv_data[HelpCtx]=5 uv_data[Options]=$FV_OF_SELECTABLE
fv.views.delete ug uv; fv.views.insert ug uv
fv.views._virt uv CalcBounds 4 0; a="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
fv.views._virt uv SizeLimits; b="$FV_MIN_X $FV_MIN_Y $FV_MAX_X $FV_MAX_Y"
RESULT=x; fv.views._virt ug GetHelpCtx; c=$RESULT
fv.views.locate uv 0 0 1 1; fv.views.getBounds uv; d=$RESULT
if [[ $a == '0 0 15 5' && $b == '3 2 40 20' && $c == gu5 && $d == '0 0 3 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c] [$d]"; fi

kt_test_start "an owner resize reaches the user's CalcBounds / ChangeBounds of the subview through the group's own (overridden) ChangeBounds; the user's fields keep their values"
uv_data[log]='' ug_data[log]=''
fv.views.changeBounds ug 0 0 50 20
fv.views.getBounds uv; a=$RESULT
f="${uv_data[i]}${uv_data[k]}${uv_data[n]}${uv_data[x]}${uv_data[y]}${uv_data[s]}${uv_data[d]}${uv_data[r]}${uv_data[c]}${uv_data[f]}${uv_data[v]}${uv_data[o]}${uv_data[w]}${uv_data[h]}"
g="${ug_data[i]}${ug_data[k]}${ug_data[n]}${ug_data[x]}${ug_data[s]}"
# uv 0 0 3 2, GrowHiX: BX 3 + 10 = 13, +1 by the user's CalcBounds -> 14
if [[ $a == '0 0 14 2' && ${ug_data[log]} == 'GCB(0 0 50 20)' && ${uv_data[log]} == 'CA(10 0)SLCB(0 0 14 2)' \
   && $f == 1234567891011121314 && $g == abcde ]]; then kt_test_pass "ok"
else kt_test_fail "[$a] ug.log=[${ug_data[log]}] uv.log=[${uv_data[log]}] fields=[$f] [$g]"; fi

kt_test_start "the RESULT rule: a proc leaves the caller's RESULT on both paths (the user's ChangeBounds sets RESULT itself), a func answers on both"
out=''
RESULT=caller; fv.views._virt pv ChangeBounds 0 0 10 5; out+="$RESULT "
RESULT=caller; fv.views._virt uv ChangeBounds 0 0 14 2; out+="$RESULT "
RESULT=caller; fv.views._virt pv SizeLimits; out+="$RESULT "
RESULT=caller; fv.views._virt uv SizeLimits; out+="$RESULT "
RESULT=caller; fv.views._virt pv GetHelpCtx; out+="$RESULT "
RESULT=caller; fv.views._virt uv GetHelpCtx; out+="$RESULT"
if [[ $out == 'caller caller caller caller 0 u5' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

# a test class whose built-ins are test functions (registered as the unit
# registers its own) with a set RESULT and an rc, and a user override of it
tst_proc() { RESULT=from-plain-proc; return 5; }
tst_func() { RESULT=from-plain-func; return 6; }
class TTst : TView
    public
        override proc ChangeBounds
        override func GetHelpCtx
end
TTst.ChangeBounds() { tst_proc "$this" "$@"; }
TTst.GetHelpCtx() { tst_func "$this" "$@"; }
build TTst
class TTstU : TTst
    public
        override proc ChangeBounds
        override func GetHelpCtx
end
TTstU.ChangeBounds() { inherited ChangeBounds "$@"; RESULT=from-user-proc; return 7; }
TTstU.GetHelpCtx() { inherited GetHelpCtx "$@"; RESULT=from-user-func; return 8; }
build TTstU
__FV_VW_IMPL[TTst.ChangeBounds]=tst_proc __FV_VW_IMPL[TTst.GetHelpCtx]=tst_func
TTst.new tp 0 0 1 1
TTstU.new tu 0 0 1 1

kt_test_start "rc and RESULT both ways with bodies that fail: the rc passes (proc 5 / 7, func 6 / 8) and the caller's RESULT stays (a func answers in RESULT only with rc 0: kklass drops a func's RESULT after an explicit return)"
out=''
RESULT=caller; fv.views._virt tp ChangeBounds 1 2; out+="$?:$RESULT "
RESULT=caller; fv.views._virt tu ChangeBounds 1 2; out+="$?:$RESULT "
RESULT=caller; fv.views._virt tp GetHelpCtx; out+="$?:$RESULT "
RESULT=caller; fv.views._virt tu GetHelpCtx; out+="$?:$RESULT"
if [[ $out == '5:caller 7:caller 6:caller 8:caller' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "the same under set -e in an if / || context (no early exit inside _virt on either path)"
out=$(
    set -e
    r="" RESULT=keep
    if fv.views._virt tp ChangeBounds; then r+=t; else r+="f$?"; fi
    if fv.views._virt tu ChangeBounds; then r+=t; else r+="f$?"; fi
    fv.views._virt tp GetHelpCtx || r+="f$?:$RESULT"
    fv.views._virt tu GetHelpCtx || r+="f$?:$RESULT"
    printf '%s' "$r"
)
if [[ $out == 'f5f7f6:keepf8:keep' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi
unset '__FV_VW_IMPL[TTst.ChangeBounds]' '__FV_VW_IMPL[TTst.GetHelpCtx]'
tp.delete; tu.delete

# the unsupported func shapes, pinned as kklass behaves today (review 2c-1 #1;
# a kklass finding: a func body's RESULT trailer, kk._return, runs only when
# the body ends without `return`)
class TRet0 : TView
    public
        override func GetHelpCtx
end
TRet0.GetHelpCtx() { RESULT=42; return 0; }
build TRet0
class TInhRet0 : TView
    public
        override func GetHelpCtx
end
TInhRet0.GetHelpCtx() { inherited GetHelpCtx "$@"; return 0; }
build TInhRet0
class TFalse : TView
    public
        override func GetHelpCtx
end
TFalse.GetHelpCtx() { RESULT=43; false; }
build TFalse
class TSupp : TView
    public
        override func GetHelpCtx
end
TSupp.GetHelpCtx() { RESULT=44; }
build TSupp

kt_test_start "kklass today: a func override ending with 'return 0' loses its RESULT (also after inherited); one ending with a failing command loses its rc; the supported form answers"
TRet0.new r0 0 0 1 1; TInhRet0.new ri 0 0 1 1; TFalse.new rf 0 0 1 1; TSupp.new rs 0 0 1 1
ri_data[HelpCtx]=5
out=''
for v in r0 ri rf rs; do RESULT=caller; fv.views._virt "$v" GetHelpCtx; out+="$v:$?:$RESULT "; done
if [[ $out == 'r0:0:caller ri:0:caller rf:0:43 rs:0:44 ' ]]; then kt_test_pass "ok (as documented: return 0 and a failing last command are not supported)"
else kt_test_fail "[$out] - kklass's func RESULT / rc behaviour changed: update the documented rule (fv.views.sh _virt, README, this test)"; fi

kt_test_start "... so TGroup.GetHelpCtx through a Current whose override ends with 'return 0' answers the group's own HelpCtx (the supported form: the Current's)"
TGroup.new hg 0 0 9 9; hg_data[HelpCtx]=3
r0_data[Options]=$FV_OF_SELECTABLE rs_data[Options]=$FV_OF_SELECTABLE
fv.views.insert hg r0
RESULT=x; fv.views._virt hg GetHelpCtx; a=$RESULT
fv.views.delete hg r0; fv.views.insert hg rs
RESULT=x; fv.views._virt hg GetHelpCtx; b=$RESULT
if [[ $a == 3 && $b == 44 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
hg.delete; r0.delete; ri.delete; rf.delete

# --- stage 2c-2: Draw (proc) and GetPalette (func), on TView, TGroup, TFrame -----
class TUd : TView
    public
        var i
        var x
        var y
        override proc Draw
        override func GetPalette
end
TUd.Draw() { i=a x=b y=c; RESULT=clobbered-by-draw; inherited Draw; DLOG+="d:$FV_DRAW_VIEW;"; }
TUd.GetPalette() { inherited GetPalette; RESULT="${RESULT}3 4"; }
build TUd
class TUgd : TGroup
    public
        var k
        override proc Draw
        override func GetPalette
end
TUgd.Draw() { k=z; inherited Draw; DLOG+="g:$FV_DRAW_VIEW;"; }
TUgd.GetPalette() { inherited GetPalette; RESULT="${RESULT}5 6 7 8 9"; }
build TUgd
class TUfr : TFrame
    public
        override proc Draw
        override func GetPalette
end
TUfr.Draw() { inherited Draw; DLOG+="f:$FV_DRAW_VIEW;"; }
TUfr.GetPalette() { inherited GetPalette; RESULT="$RESULT 4"; }
build TUfr
class TKidF : TFrame
    public
        var n
end
build TKidF

kt_test_start "2c-2: Draw and GetPalette: 0 dispatches for the built-ins (TView, TGroup, TFrame and a subclass that inherits), 2 for each override + inherited"
TUd.new ud 0 0 2 1; TUgd.new ugd 0 0 9 4; TUfr.new ufr 0 0 9 4; TKidF.new kf 0 0 9 4; TFrame.new pfr 0 0 9 4
out=''
for m in Draw GetPalette; do
    for vw in pv pg pfr kf ud ugd ufr; do count fv.views._virt "$vw" "$m"; out+="$REPLY"; done
    out+=' '
done
if [[ $out == '0000222 0000222 ' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out]"; fi

kt_test_start "2c-2: the RESULT rule: Draw (a proc) leaves the caller's RESULT on both paths (the override sets RESULT itself); GetPalette (a func) answers on both"
out=''
RESULT=caller; fv.views._virt pv Draw; out+="$RESULT,"
RESULT=caller; fv.views._virt ud Draw; out+="$RESULT,"
RESULT=caller; fv.views._virt pv GetPalette; out+="[$RESULT],"
RESULT=caller; fv.views._virt pfr GetPalette; out+="[$RESULT],"
RESULT=caller; fv.views._virt ud GetPalette; out+="[$RESULT],"
RESULT=caller; fv.views._virt ufr GetPalette; out+="[$RESULT]"
if [[ $out == 'caller,caller,[],[1 1 2 2 3],[3 4],[1 1 2 2 3 4]' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "2c-2: in the painter: each user Draw dispatched once (+ inherited), the user's GetPalette shapes the resolved palette, fields intact, RESULT kept"
fvw_screen 20 6
fv.views.insert ugd ufr; fv.views.insert ugd ud
fvw_expose ugd
fv.views.resetPalette
DLOG=''
fvw_count_on; FVW_CALLS=0
RESULT=keep
fv.views.drawView ugd
n=$FVW_CALLS r=$RESULT
fvw_count_off
# ugd: app entries 5..9 = symbols 5 6 7 8 9; ufr: CFrame + 4 -> 5 5 6 6 7 8; ud: '' + "3 4" -> 7 8
p="${__FV_VW_PAL[ugd]} ${__FV_VW_PAL[ufr]} ${__FV_VW_PAL[ud]}"
fvw_cells 0 0 3; c=$REPLY
# dispatches: 3 Draws + 3 inherited, 3 GetPalettes + 3 inherited
if [[ $n == 12 && $r == keep && $DLOG == 'f:ufr;d:ud;g:ugd;' && $p == '56789 556678 78' && ${ud_data[i]}${ud_data[x]}${ud_data[y]}${ugd_data[k]} == abcz && $c == 775 ]]; then kt_test_pass "ok"
else kt_test_fail "calls=$n RESULT=$r log=[$DLOG] pal=[$p] fields=[${ud_data[i]}${ud_data[x]}${ud_data[y]}${ugd_data[k]}] cells=[$c]"; fi
ugd.delete; kf.delete; pfr.delete

kt_test_start "an unknown method: a kklass dispatch that fails like a direct call (rc 127), RESULT kept"
RESULT=caller; fv.views._virt pv NoSuchMethod 2>/dev/null; r=$?
if [[ $r == 127 && $RESULT == caller ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r RESULT=$RESULT"; fi

kt_test_start "kk.class --forget + a redefinition: with an override the next instance dispatches it; without, the built-in runs again (no cache)"
fv.views.delete ug uv
uv.delete; kidv.delete
kk.class --forget TKidV 2>/dev/null
class TKidV : TView
    public
        var i
        override func GetHelpCtx
end
TKidV.GetHelpCtx() { inherited GetHelpCtx "$@"; RESULT="redef$RESULT"; }
build TKidV
TKidV.new kidv 0 0 1 1
count fv.views._virt kidv GetHelpCtx; a="$REPLY:$RESULT"
kidv.delete
kk.class --forget TKidV 2>/dev/null
class TKidV : TView
    public
        var i
end
build TKidV
TKidV.new kidv 0 0 1 1
count fv.views._virt kidv GetHelpCtx; b="$REPLY:$RESULT"
kidv.delete
kk.class --forget TUv 2>/dev/null
class TUv : TView
    public
        var i
end
build TUv
TUv.new uv 0 0 1 1
count fv.views._virt uv ChangeBounds 0 0 2 2; c=$REPLY
fv.views.getBounds uv; c+=":$RESULT"
uv.delete
if [[ $a == 2:redef0 && $b == 0:0 && $c == '0:0 0 2 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

# --- the scene under caller setups ------------------------------------------------
SCENE='
r=""
TUg.new ug 0 0 40 20
TUv.new uv 2 2 12 7
TView.new pv 1 1 5 5
TKidG.new kg 0 0 20 10
TUv.new uw 1 1 6 4
uv_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) uv_data[Options]=$FV_OF_SELECTABLE uv_data[HelpCtx]=9
pv_data[GrowMode]=$(( FV_GF_GROWALL | FV_GF_GROWREL ))
kg_data[GrowMode]=$FV_GF_GROWLOX uw_data[GrowMode]=$FV_GF_GROWHIX
fv.views.insert ug uv; fv.views.insert ug pv; fv.views.insert ug kg; fv.views.insert kg uw
fv.views.makeFirst uv
fv.views.changeBounds ug 0 0 60 30
for q in uv pv kg uw; do fv.views.getBounds "$q"; r+="$q=$RESULT;"; done
fv.views.locate uv 0 0 1 1; fv.views.getBounds uv; r+="uv=$RESULT;"
fv.views.moveTo kg 30 2; fv.views.getBounds uw; r+="uw=$RESULT abs=${__FV_VW_AX[uw]},${__FV_VW_AY[uw]};"
RESULT=x; ug.GetHelpCtx; r+="help=$RESULT;"
RESULT=keep; fv.views._virt uv ChangeBounds 0 0 4 4; r+="proc=$RESULT;"
r+="log=${uv_data[log]}|${uw_data[log]}|${ug_data[log]};"
r+="fields=${uv_data[i]}${uv_data[x]}${uv_data[h]}${ug_data[s]}"
ug.delete
printf "%s" "$r"
'
STATE='printf "%s|" "$(shopt -p nocasematch extglob)" "$-" "${IFS@Q}"'
run() {   # SETUP -> OUT
    OUT=$("$BASH" -c "FVW_TMP='$FVW_TMP'
source '$FVW_TESTS_DIR/../fv.views.sh'
source '$FVW_TMP/classes.sh'
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}
run ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "the scene in a plain child shell"
want='uv=2 2 33 17;pv=2 2 8 8;kg=20 0 20 10;uw=1 1 5 4;uv=0 0 3 2;uw=1 1 5 4 abs=31,3;help=gu9;proc=keep;'
want+='log=CA(20 10)SLCB(2 2 33 17)SLCB(0 0 3 2)CB(0 0 4 4)|CA(-20 0)SLCB(1 1 5 4)|GCB(0 0 60 30);fields=1414e'
if [[ $ref == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$ref] want [$want]"; fi
for setup in 'set -eu' 'set -eu -o pipefail' 'shopt -s nocasematch' "IFS='0123456789 '" 'IFS=' "IFS='-*?[]'" \
    'shopt -s extglob failglob nullglob; set -f' "set -eu; shopt -s nocasematch extglob; IFS='0123456789x_'"; do
    kt_test_start "the scene under: $setup (same output, the state kept)"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state [$before] -> [$after]"; fi
done


# ---- stage 2c-3: HandleEvent, SetState, Valid, Execute, EndModal; TWindow's
# HandleEvent, SetState, GetPalette, GetTitle, InitFrame, Close ---------------
class TUe : TView
    public
        var i
        var k
        var n
        var log
        override proc HandleEvent
        override proc SetState
        override func Valid
        override func Execute
        override proc EndModal
end
TUe.HandleEvent() { log+="HE($FV_EV_WHAT)"; i=1 k=2 n=3; RESULT=clobbered; inherited HandleEvent "$@"; }
TUe.SetState() { ulog_args "$@"; log+="SS($REPLY)"; RESULT=clobbered; inherited SetState "$@"; }
TUe.Valid() { log+="VA($1)"; if [[ $1 == cmNo ]]; then return 1; fi; inherited Valid "$@"; }
TUe.Execute() { log+="EX"; inherited Execute "$@"; RESULT="u$RESULT"; }
TUe.EndModal() { log+="EM($1)"; RESULT=clobbered; inherited EndModal "$@"; }
build TUe
class TUge : TGroup
    public
        var i
        var log
        override proc HandleEvent
        override proc SetState
        override func Valid
        override func Execute
        override proc EndModal
end
TUge.HandleEvent() { log+="GHE($FV_EV_WHAT)"; i=7; inherited HandleEvent "$@"; }
TUge.SetState() { ulog_args "$@"; log+="GSS($REPLY)"; inherited SetState "$@"; }
TUge.Valid() { log+="GVA($1)"; inherited Valid "$@"; }
TUge.Execute() { log+="GEX"; inherited Execute "$@"; RESULT="g$RESULT"; }
TUge.EndModal() { log+="GEM($1)"; inherited EndModal "$@"; }
build TUge
class TUw : TWindow
    public
        var i
        var log
        override proc HandleEvent
        override proc SetState
        override func GetPalette
        override func GetTitle
        override proc InitFrame
        override proc Close
end
TUw.HandleEvent() { log+="WHE"; inherited HandleEvent "$@"; }
TUw.SetState() { log+="WSS"; inherited SetState "$@"; }
TUw.GetPalette() { inherited GetPalette "$@"; RESULT="${RESULT% *}"; }
TUw.GetTitle() { inherited GetTitle "$@"; RESULT="<$RESULT>"; }
TUw.InitFrame() { log+="WIF"; inherited InitFrame "$@"; }
TUw.Close() { log+="WCL"; inherited Close "$@"; }
build TUw
class TKidW : TWindow
    public
        var i
end
build TKidW

eofsrc() { FV_EV_WHAT=evNothing; return 1; }
TGroup.new eg 0 0 40 20
TView.new ev0 0 0 5 5; TUe.new ue 0 0 5 5; TGroup.new eg0 0 0 9 9; TUge.new uge 0 0 9 9
TWindow.new ew 0 0 20 10 'Plain' 1; TKidW.new kw 0 0 20 10 'Kid' 2; TUw.new uw2 0 0 20 10 'Mine' 3

kt_test_start "2c-3: 0 dispatches for the built-ins (TView, TGroup, TWindow, a subclass that inherits), 2 for each override + inherited"
out=''
FV_EV_WHAT=evBroadcast FV_EV_COMMAND=cmX
for vw in ev0 ue; do count fv.views._virt "$vw" HandleEvent; out+=$REPLY; done
for vw in ev0 ue; do count fv.views._virt "$vw" SetState "$FV_SF_CURSORVIS" 1; out+=$REPLY; done
for vw in ev0 ue; do count fv.views._virt "$vw" Valid cmOK; out+=$REPLY; done
for vw in ev0 ue; do count fv.views._virt "$vw" Execute; out+=$REPLY; done
for vw in ev0 ue; do count fv.views._virt "$vw" EndModal cmOK; out+=$REPLY; done
out+=' '
__FV_VW_GETEVENT=eofsrc
for m in 'HandleEvent' "SetState $FV_SF_CURSORVIS 1" 'Valid cmOK' 'EndModal cmOK' 'Execute'; do
    for vw in eg0 uge; do __FV_VW_EOF=0; count fv.views._virt "$vw" $m; out+=$REPLY; done
done
out+=' '
for m in 'HandleEvent' "SetState $FV_SF_CURSORVIS 1" 'GetPalette' 'GetTitle 9'; do
    for vw in ew kw uw2; do count fv.views._virt "$vw" $m; out+=$REPLY; done
done
__FV_VW_EOF=0 __FV_VW_GETEVENT=fv.drivers.getEvent
want='0202020202 0202020202 002002002002'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "2c-3: the RESULT rule: HandleEvent, SetState, EndModal (procs) leave the caller's RESULT on both paths; Valid, Execute, GetTitle (funcs) answer"
r=''
for vw in ev0 ue; do RESULT=keep; fv.views._virt "$vw" HandleEvent; r+="$RESULT,"; done
for vw in ev0 ue; do RESULT=keep; fv.views._virt "$vw" SetState "$FV_SF_CURSORINS" 1; r+="$RESULT,"; done
for vw in ev0 ue; do RESULT=keep; fv.views._virt "$vw" EndModal cmOK; r+="$RESULT,"; done
for vw in ev0 ue; do RESULT=keep; fv.views._virt "$vw" Valid cmOK; r+="$?:$RESULT,"; done
for vw in ev0 ue; do RESULT=keep; fv.views._virt "$vw" Execute; r+="$?:$RESULT,"; done
for vw in ew uw2; do RESULT=keep; fv.views._virt "$vw" GetTitle 3; r+="$RESULT,"; done
RESULT=keep; fv.views._virt ue Valid cmNo; r+="$?:$RESULT"
want='keep,keep,keep,keep,keep,keep,0:1,0:1,0:cmCancel,0:ucmCancel,Pla,<Min>,1:keep'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "2c-3: through the framework: a key to a user group reaches its user Current (2 + 2 dispatches), fields intact; SetState overrides see a select"
fv.views.insert uge ue; ue_data[Options]=$FV_OF_SELECTABLE
fv.views.delete uge ue; fv.views.insert uge ue
fv.views.insert eg uge
ue_data[log]='' uge_data[log]=''
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbA
count fv.views._virt eg HandleEvent; n=$REPLY
r="$n|${uge_data[log]}|${ue_data[log]}|${ue_data[i]}${ue_data[k]}${ue_data[n]}|${uge_data[i]}"
eg_data[State]=$(( eg_data[State] | FV_SF_FOCUSED ))
fv.views.insert eg ev0; ev0_data[Options]=$FV_OF_SELECTABLE; fv.views.delete eg ev0; fv.views.insert eg ev0
ue_data[log]='' uge_data[log]=''
fv.views.select uge
r+="|${uge_data[log]}|${ue_data[log]}"
# (the select: ev0 loses the focus (its broadcast to eg reaches uge), uge is
# selected and focused (its broadcast to eg reaches uge too), then ue (its
# broadcast to uge: uge once more)
want="4|GHE(evKeyDown)|HE(evKeyDown)|123|7|GHE(evBroadcast)GSS($FV_SF_SELECTED 1)GSS($FV_SF_FOCUSED 1)GHE(evBroadcast)GHE(evBroadcast)|SS($FV_SF_FOCUSED 1)"
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "2c-3: execView of a user group: its Execute (+ inherited loop) and Valid overrides run; endModal through a user EndModal"
uge_data[log]='' ue_data[log]=''
q=(endit)
qsrc() {
    if (( ${#q[@]} )); then q=(); fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbB; fv.views.endModal ue cmOK; return 0; fi
    FV_EV_WHAT=evNothing; return 1
}
__FV_VW_GETEVENT=qsrc
fv.views.delete eg uge
fv.views.execView eg uge; r="$RESULT|${uge_data[log]}|${ue_data[log]}"
__FV_VW_GETEVENT=fv.drivers.getEvent __FV_VW_EOF=0
if [[ $r == 'gcmOK|'*GEX*'GEM(cmOK)'*'GHE(evKeyDown)'*'GVA(cmOK)'*'|'*'VA(cmOK)'* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "2c-3: TWindow overrides: InitFrame at construction, GetPalette shapes the frame's colours, GetTitle the frame's title, Close through cmClose"
TUw.new uw 0 0 30 8 'Title' 4
r1=${uw_data[log]}
fvw_screen 40 10
TGroup.new er 0 0 40 10; fvw_root er; fv.views.insert er uw
fv.views.drawView er
fv.video.getRow 0; t=$RESULT
uw_data[log]=''
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmClose
fv.views._virt er HandleEvent
r2=$( fv.views.isView uw && echo kept || echo closed )
if [[ $r1 == WIF && $t == *'<Title>'* && $r2 == closed ]]; then kt_test_pass "ok"; else kt_test_fail "init [$r1] top [$t] close [$r2]"; fi
er.delete
eg.delete; ev0.delete 2>/dev/null || :; ue.delete 2>/dev/null || :; eg0.delete; ew.delete; kw.delete; uw2.delete

kt_test_start "2c-3: a failing built-in keeps its rc through kklass: an override's 'inherited NAME \"\$@\" || return' (Valid, Execute), the aliases (ExecView, Insert, InsertBefore, MoveTo, Locate, GrowTo, PutInFrontOf, Select, DrawView, Lock)"
class TRf : TView
    public
        override func Valid
end
TRf.Valid() { return 1; }
build TRf
class TVo : TGroup
    public
        override func Valid
        override func Execute
end
TVo.Valid() { inherited Valid "$@" || return; }
TVo.Execute() { inherited Execute "$@" || return; }
build TVo
TVo.new vo 0 0 10 10; TRf.new rf 0 0 1 1; fv.views.insert vo rf
TGroup.new og 0 0 9 9; TView.new ov 0 0 1 1; fv.views.insert og ov
r=''
RESULT=keep; fv.views._virt vo Valid cmOK; r+="$?:$RESULT,"
RESULT=keep; vo.Valid cmOK; r+="$?:$RESULT,"
r+="$( fv.views._virt vo Execute >/dev/null; printf %s "$?" ),"
r+="$( vo.ExecView ov >/dev/null; printf %s "$?" ),"
vo.ExecView nosuch >/dev/null; r+="$?,"
vo.Insert ov; r+="$?,"
vo.InsertBefore ov nosuch; r+="$?,"
ov.MoveTo x 1; r+="$?,"; ov.Locate 0 0 x 1; r+="$?,"; ov.GrowTo x 1; r+="$?,"
ov.PutInFrontOf nosuch; r+="$?,"
fv.views.delete og ov; ov.Select; r+="$?,"
ov.DrawView; r+="$?,"
og.Lock; og.Unlock; r+="$?"
og.delete; ov.delete; vo.delete
want='1:keep,1:keep,2,2,2,1,1,2,2,2,1,0,0,0'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "kklass today (K-2): an override whose LAST command is a bare 'inherited Valid \"\$@\"' that fails answers rc 0 (write '|| return': README)"
class TVb : TGroup
    public
        override func Valid
end
TVb.Valid() { inherited Valid "$@"; }
build TVb
TVb.new vb 0 0 10 10; TRf.new rf2 0 0 1 1; fv.views.insert vb rf2
fv.views._virt vb Valid cmOK; r=$?
vb.delete
if [[ $r == 0 ]]; then kt_test_pass "rc 0, as kklass behaves today (pinned)"; else kt_test_fail "rc $r: kklass changed, update the README's note"; fi
kt_test_log "013_Elision.sh completed"
