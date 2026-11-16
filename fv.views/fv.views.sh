#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.views.sh}../../kbool.sh" || return
kk.unit fv.views || return $__kk_unit_rc

# fv.views — the view tree of the fv.* text UI (layer L2): Free Vision's TView
# and TGroup as kklass classes with FV's field names, the subview lists, FV
# corner bounds, GrowMode, and the "virtual elision" that runs a built-in
# virtual as a plain function unless the view's class overrides it. Port of
# FV views.inc (TView, TGroup); design: kcl/docs/dev/fv/P2_DESIGN.md (§1),
# API and deviations: README.md.
#
# P2 stage 2c-1: constants, TView / TGroup, the tree (insert, insertBefore,
# delete, makeFirst, putInFrontOf, first / last / next / prev / nextView /
# prevView), the bounds cache, GrowMode, locate / moveTo / growTo /
# changeBounds, makeLocal / makeGlobal / mouseInView, the elision
# (fv.views._virt) with its RESULT rule, reserved names and the constructor
# guard. Stage 2c-2: palettes and getColor, the drawing context and the
# writers, the painter (paint / drawView / over / drawUnder, the covering
# skip, shadows), show / hide, drawPart, redraw, both lock counters and the
# minimal TFrame; the redraw hook fv.views._changed draws. Events, focus and
# modal views (2c-3) build on the focus hook fv.views._setCurrent and the
# frame's border-only entry fv.views._frameBorder.
#
# Conventions of every plain function here:
#   * the view name first; locals `__fvw_*`; fields read and written through
#     `${v}_data` (kklass friend contract, kklass book "Friend tables"), reads
#     as `${d[F]-}`;
#   * fork-free, set -eu clean; no `[[ == ]]` / `case` / `${x//}` between two
#     names (nocasematch would make `Win1` equal to `win1`): `[ "$a" = "$b" ]`
#     and `${a#"$b"}` are case-sensitive under it;
#   * procedures leave RESULT as it was (as kklass procs do); getters answer
#     in RESULT; a refused call is rc 1 (a value the caller may try) or rc 2
#     (not a view, a bad number, a bad argument count) with RESULT='' and a
#     kk.debug line. Programming errors that would corrupt the tree (a live
#     name re-created, a reserved name, a constructor that skipped
#     `inherited`) print one `Error:` line on stderr (silent only under
#     VERBOSE_KKLASS=quiet): the design's "fail loudly".

kk.uses kklass_pascal fv.video fv.drivers || return

if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# ---- constants (FV values; readonly once per process, kcl §1.10 rule 7) -----
# Naming: FV's identifier upper-cased behind a unit prefix: sfCursorVis ->
# FV_SF_CURSORVIS, ofTopSelect -> FV_OF_TOPSELECT, gfGrowLoX -> FV_GF_GROWLOX,
# dmLimitLoY -> FV_DM_LIMITLOY, hcNoContext -> FV_HC_NOCONTEXT. EventMask bits
# (FPC drivers.inc: evMouseDown $0001 ... evMouseWheel $0020) are FV_EM_*, so
# that they do not mix with the event record FV_EV_* of fv.drivers.
if [[ -z ${FV_SF_VISIBLE+x} || ${FV_SF_VISIBLE@a} != *r* ]]; then
    FV_SF_VISIBLE=$(( 0x1 )) FV_SF_CURSORVIS=$(( 0x2 )) FV_SF_CURSORINS=$(( 0x4 )) FV_SF_SHADOW=$(( 0x8 ))
    FV_SF_ACTIVE=$(( 0x10 )) FV_SF_SELECTED=$(( 0x20 )) FV_SF_FOCUSED=$(( 0x40 )) FV_SF_DRAGGING=$(( 0x80 ))
    FV_SF_DISABLED=$(( 0x100 )) FV_SF_MODAL=$(( 0x200 )) FV_SF_DEFAULT=$(( 0x400 )) FV_SF_EXPOSED=$(( 0x800 ))
    FV_OF_SELECTABLE=$(( 0x1 )) FV_OF_TOPSELECT=$(( 0x2 )) FV_OF_FIRSTCLICK=$(( 0x4 )) FV_OF_FRAMED=$(( 0x8 ))
    FV_OF_PREPROCESS=$(( 0x10 )) FV_OF_POSTPROCESS=$(( 0x20 )) FV_OF_BUFFERED=$(( 0x40 )) FV_OF_TILEABLE=$(( 0x80 ))
    FV_OF_CENTERX=$(( 0x100 )) FV_OF_CENTERY=$(( 0x200 )) FV_OF_CENTERED=$(( 0x300 )) FV_OF_VALIDATE=$(( 0x400 ))
    FV_GF_GROWLOX=$(( 0x1 )) FV_GF_GROWLOY=$(( 0x2 )) FV_GF_GROWHIX=$(( 0x4 )) FV_GF_GROWHIY=$(( 0x8 ))
    FV_GF_GROWALL=$(( 0xF )) FV_GF_GROWREL=$(( 0x10 ))
    FV_DM_DRAGMOVE=$(( 0x1 )) FV_DM_DRAGGROW=$(( 0x2 )) FV_DM_LIMITLOX=$(( 0x10 )) FV_DM_LIMITLOY=$(( 0x20 ))
    FV_DM_LIMITHIX=$(( 0x40 )) FV_DM_LIMITHIY=$(( 0x80 )) FV_DM_LIMITALL=$(( 0xF0 ))
    FV_HC_NOCONTEXT=0 FV_HC_DRAGGING=1
    FV_EM_MOUSEDOWN=$(( 0x1 )) FV_EM_MOUSEUP=$(( 0x2 )) FV_EM_MOUSEMOVE=$(( 0x4 )) FV_EM_MOUSEAUTO=$(( 0x8 ))
    FV_EM_KEYDOWN=$(( 0x10 )) FV_EM_MOUSEWHEEL=$(( 0x20 )) FV_EM_COMMAND=$(( 0x100 )) FV_EM_BROADCAST=$(( 0x200 ))
    FV_EM_MOUSE=$(( 0x2F )) FV_EM_KEYBOARD=$(( 0x10 )) FV_EM_MESSAGE=$(( 0xFF00 ))
    # FV MaxViewWidth (= fv.video's widest row) and high(Sw_Integer) (SizeLimits)
    __FV_VW_MAXW=1024 __FV_VW_HIGH=2147483647
    readonly FV_SF_VISIBLE FV_SF_CURSORVIS FV_SF_CURSORINS FV_SF_SHADOW FV_SF_ACTIVE FV_SF_SELECTED \
        FV_SF_FOCUSED FV_SF_DRAGGING FV_SF_DISABLED FV_SF_MODAL FV_SF_DEFAULT FV_SF_EXPOSED \
        FV_OF_SELECTABLE FV_OF_TOPSELECT FV_OF_FIRSTCLICK FV_OF_FRAMED FV_OF_PREPROCESS FV_OF_POSTPROCESS \
        FV_OF_BUFFERED FV_OF_TILEABLE FV_OF_CENTERX FV_OF_CENTERY FV_OF_CENTERED FV_OF_VALIDATE \
        FV_GF_GROWLOX FV_GF_GROWLOY FV_GF_GROWHIX FV_GF_GROWHIY FV_GF_GROWALL FV_GF_GROWREL \
        FV_DM_DRAGMOVE FV_DM_DRAGGROW FV_DM_LIMITLOX FV_DM_LIMITLOY FV_DM_LIMITHIX FV_DM_LIMITHIY FV_DM_LIMITALL \
        FV_HC_NOCONTEXT FV_HC_DRAGGING \
        FV_EM_MOUSEDOWN FV_EM_MOUSEUP FV_EM_MOUSEMOVE FV_EM_MOUSEAUTO FV_EM_KEYDOWN FV_EM_MOUSEWHEEL \
        FV_EM_COMMAND FV_EM_BROADCAST FV_EM_MOUSE FV_EM_KEYBOARD FV_EM_MESSAGE \
        __FV_VW_MAXW __FV_VW_HIGH
fi
# (stage 2c-2, its own guard: a process that loaded 2c-1 keeps the block above)
# TWindow Flags (wf), palettes (wp), wnNoNumber, TFrame FrameMode (fm)
if [[ -z ${FV_WF_MOVE+x} || ${FV_WF_MOVE@a} != *r* ]]; then
    FV_WF_MOVE=$(( 0x1 )) FV_WF_GROW=$(( 0x2 )) FV_WF_CLOSE=$(( 0x4 )) FV_WF_ZOOM=$(( 0x8 ))
    FV_WP_BLUEWINDOW=0 FV_WP_CYANWINDOW=1 FV_WP_GRAYWINDOW=2 FV_WN_NONUMBER=0
    FV_FM_CLOSECLICKED=$(( 0x1 )) FV_FM_ZOOMCLICKED=$(( 0x2 ))
    readonly FV_WF_MOVE FV_WF_GROW FV_WF_CLOSE FV_WF_ZOOM FV_WP_BLUEWINDOW FV_WP_CYANWINDOW \
        FV_WP_GRAYWINDOW FV_WN_NONUMBER FV_FM_CLOSECLICKED FV_FM_ZOOMCLICKED
fi

# ---- state ------------------------------------------------------------------
# Derived state keyed by the view name (design §1.2), kept across a reload:
#   AX AY        the absolute origin (screen cells)
#   C1 C2 C3 C4  the absolute clip X1 Y1 X2 Y2 (X2/Y2 exclusive) = the view's
#                rect ∩ its owner's clip; a view without an owner: its rect.
#                Empty when C1 == C3 or C2 == C4 (never C3 < C1)
#   LIVE         1 from TView's constructor to the destructor
#   GRP          1 for a group (TGroup's constructor); its subviews are the
#                instance array ${g}_views, back to front: the last element
#                is FV's First (the front)
# CRC: the rc of the last refused TView constructor (a subclass constructor
# returns it after `inherited`); RESNAME: the one reserved name the next
# constructor may take (fv.views._newReserved).
declare -gA __FV_VW_AX __FV_VW_AY __FV_VW_C1 __FV_VW_C2 __FV_VW_C3 __FV_VW_C4 __FV_VW_LIVE __FV_VW_GRP
declare -g __FV_VW_CRC=${__FV_VW_CRC:-0} __FV_VW_RESNAME=${__FV_VW_RESNAME-}
# Drawing state (stage 2c-2):
#   PAL[v]       v's palette resolved to fv.video symbols (design §1.9): a
#                string, entry i = ${PAL[v]:i-1:1}; filled on first use,
#                dropped for a subtree on insert / delete / resetPalette
#   FRM[f]       1 for a TFrame (the covering test of a framed group)
#   FK[f.s]      the frame's string cache, one slot s per state (0-3: active
#                + 2 dragging): FK the key of what it holds; FT/FTA, FM/FMA,
#                FB/FBA the top, body and bottom row (text / symbols), FS/FSA
#                the side column's character and symbol (border-only redraw)
#   LK[g]        g's user lock count (fv.views.lock), mirrored in LockFlag
# APAL: the root mapping, CAppColor's 127 entries as fv.video symbols (its
# default palette assigns 1-9 A-U to CAppColor's distinct bytes in order of
# first appearance, so the string follows by construction). A STUB until
# fv.app (P2 stage 2f): its setAppPalette changes this string and calls
# fv.views.resetPalette. ERRSYM: the symbol of FV's ErrorAttr (an index
# outside a palette); fv.video's default palette has no $CF, so it is the
# default symbol 0 until fv.app allocates one.
# LSU: the lockScreenUpdate count; LOCKN: the sum of the user lock counts;
# NODRAW: > 0 holds every redraw (bulk layout: ChangeBounds inside locate,
# a group resize's subview loop, fv.app's tile / cascade / resize);
# DEPTH: the nesting of drawing entries; UCLIP: the caller's fv.video clip
# saved by the outermost one; INGRP: 1 while a framework loop (not a Draw
# body) runs, so a finished paint need not restore the clip; P1..P4: the
# absolute rectangle the current paint may write; OIDX: a reordered view's
# old index (putInFrontOf -> the `order` redraw).
declare -gA __FV_VW_PAL __FV_VW_FRM __FV_VW_FK __FV_VW_FT __FV_VW_FTA __FV_VW_FM __FV_VW_FMA \
    __FV_VW_FB __FV_VW_FBA __FV_VW_FS __FV_VW_FSA __FV_VW_LK
declare -g __FV_VW_APAL=${__FV_VW_APAL:-123456789ABBC19DEFGGHIE2JKGG2JL2JKGG22JL5MN3O2PEH9NA5QBBPNHBGRB89A11C89C5MN3OSPEH2NK5TBBPNHBGRBDEFGGHPEH5MN3OP2JL9NA5UB12NL1GR1}
declare -g __FV_VW_ERRSYM=${__FV_VW_ERRSYM:-0}
declare -g __FV_VW_LSU=${__FV_VW_LSU:-0} __FV_VW_LOCKN=${__FV_VW_LOCKN:-0} __FV_VW_NODRAW=${__FV_VW_NODRAW:-0}
declare -g __FV_VW_DEPTH=${__FV_VW_DEPTH:-0} __FV_VW_UCLIP=${__FV_VW_UCLIP-} __FV_VW_INGRP=${__FV_VW_INGRP:-0}
declare -g __FV_VW_P1=${__FV_VW_P1:-0} __FV_VW_P2=${__FV_VW_P2:-0} __FV_VW_P3=${__FV_VW_P3:-0} __FV_VW_P4=${__FV_VW_P4:-0}
declare -g __FV_VW_OIDX=${__FV_VW_OIDX:--1}
# INDRAW[v]: set while v's Draw runs (the paint stack; re-entrancy rule);
# WROW[y]: 1 for a screen row that holds or held wide cells (repainted in
# full-width bands); FORCE: a forced update (redraw) waiting for the release
declare -gA __FV_VW_INDRAW
declare -ga __FV_VW_WROW
__FV_VW_INDRAW+=() __FV_VW_WROW+=()
declare -g __FV_VW_FORCE=${__FV_VW_FORCE:-0}
# The drawing context of the Draw that runs (design §1.5; '' / 0 outside one):
# the view, its absolute origin, its resolved palette, and the part of it
# this paint may write in the view's own coordinates ([X1,X2) x [Y1,Y2)).
declare -g FV_DRAW_VIEW=${FV_DRAW_VIEW-} FV_DRAW_X=${FV_DRAW_X:-0} FV_DRAW_Y=${FV_DRAW_Y:-0} FV_DRAW_PAL=${FV_DRAW_PAL-}
declare -g FV_CLIP_X1=${FV_CLIP_X1:-0} FV_CLIP_Y1=${FV_CLIP_Y1:-0} FV_CLIP_X2=${FV_CLIP_X2:-0} FV_CLIP_Y2=${FV_CLIP_Y2:-0}
# The elision tables (design §1.4): IMPL = the plain body of each built-in
# virtual, keyed DEFININGCLASS.METHOD; FUNC = the virtuals FV declares as
# functions (they answer in RESULT on both paths; the others leave it).
declare -gA __FV_VW_IMPL=(
    [TView.ChangeBounds]=fv.views._viewChangeBounds [TView.CalcBounds]=fv.views._viewCalcBounds
    [TView.SizeLimits]=fv.views._viewSizeLimits [TView.GetHelpCtx]=fv.views._viewGetHelpCtx
    [TGroup.ChangeBounds]=fv.views._groupChangeBounds [TGroup.GetHelpCtx]=fv.views._groupGetHelpCtx
    [TView.Draw]=fv.views._viewDraw [TGroup.Draw]=fv.views._groupDraw [TFrame.Draw]=fv.views._frameDraw
    [TView.GetPalette]=fv.views._viewGetPalette [TFrame.GetPalette]=fv.views._frameGetPalette
)
declare -gA __FV_VW_FUNC=(
    [GetPalette]=1 [GetHelpCtx]=1 [Valid]=1 [Execute]=1 [GetTitle]=1 [Hint]=1 [GetEvent]=1
)
# The event-name -> EventMask bit lookup (used by the dispatch, stage 2c-3).
declare -gA __FV_VW_EVBIT=(
    [evMouseDown]=1 [evMouseUp]=2 [evMouseMove]=4 [evMouseAuto]=8 [evKeyDown]=16
    [evMouseWheel]=32 [evCommand]=256 [evBroadcast]=512
)
# The var parameters of FV's geometry procedures (TRect Bounds, TPoint, the
# Min / Max of SizeLimits): procedures leave RESULT alone, so these are the
# answer of CalcBounds and SizeLimits (both paths), and getBounds /
# getExtent / makeLocal / makeGlobal set them besides RESULT.
declare -g FV_RECT_AX=${FV_RECT_AX:-0} FV_RECT_AY=${FV_RECT_AY:-0} FV_RECT_BX=${FV_RECT_BX:-0} FV_RECT_BY=${FV_RECT_BY:-0}
declare -g FV_POINT_X=${FV_POINT_X:-0} FV_POINT_Y=${FV_POINT_Y:-0}
declare -g FV_MIN_X=${FV_MIN_X:-0} FV_MIN_Y=${FV_MIN_Y:-0} FV_MAX_X=${FV_MAX_X:-0} FV_MAX_Y=${FV_MAX_Y:-0}

# ---- classes (FV views.inc; fields design §1.2, virtuals §1.3) --------------
# Each built-in virtual's kklass body is one line calling its plain body, so
# a user override reaches it with `inherited NAME "$@"` (a bare `inherited`
# in a method forwards no arguments). The thin aliases (D16: MakeFirst,
# PutInFrontOf, Locate, MoveTo, GrowTo, Insert, InsertBefore) are for set-up
# code; the framework calls the plain functions. No `Delete` alias: removal
# is `fv.views.delete G V`, destruction `V.delete`.
class TView
    public
        var Owner
        var OriginX
        var OriginY
        var SizeX
        var SizeY
        var CursorX
        var CursorY
        var State
        var Options
        var EventMask
        var GrowMode
        var DragMode
        var HelpCtx
        constructor Create
        destructor Done
        proc ChangeBounds
        proc CalcBounds
        proc SizeLimits
        func GetHelpCtx
        proc Draw
        func GetPalette
        proc MakeFirst
        proc PutInFrontOf
        proc Locate
        proc MoveTo
        proc GrowTo
        proc DrawView
        proc Show
        proc Hide
end
# TView.new NAME AX AY BX BY — FV `Init(R)` with `R.Assign(AX, AY, BX, BY)`
# (corners, B exclusive). rc 1: NAME is a live view (the tree is repaired,
# one Error line); rc 2: a reserved name (`__fv` inside) or a bound that is
# not an integer (one Error line).
TView.Create() { fv.views._create "$this" "$@"; }
TView.Done() { fv.views._done "$this"; }
TView.ChangeBounds() { fv.views._viewChangeBounds "$this" "$@"; }
TView.CalcBounds() { fv.views._viewCalcBounds "$this" "$@"; }
TView.SizeLimits() { fv.views._viewSizeLimits "$this" "$@"; }
TView.GetHelpCtx() { fv.views._viewGetHelpCtx "$this" "$@"; }
TView.MakeFirst() { fv.views.makeFirst "$this"; }
TView.PutInFrontOf() { fv.views.putInFrontOf "$this" "$@"; }
TView.Locate() { fv.views.locate "$this" "$@"; }
TView.MoveTo() { fv.views.moveTo "$this" "$@"; }
TView.GrowTo() { fv.views.growTo "$this" "$@"; }
TView.Draw() { fv.views._viewDraw "$this"; }
TView.GetPalette() { fv.views._viewGetPalette "$this"; }
TView.DrawView() { fv.views.drawView "$this"; }
TView.Show() { fv.views.show "$this"; }
TView.Hide() { fv.views.hide "$this"; }
build TView

class TGroup : TView
    public
        var Current
        var Phase
        var EndState
        var LockFlag
        constructor Create
        override proc ChangeBounds
        override func GetHelpCtx
        override proc Draw
        proc Insert
        proc InsertBefore
        proc Lock
        proc Unlock
end
# TGroup.new NAME AX AY BX BY — FV TGroup.Init: TView's, then ofSelectable +
# ofBuffered, EventMask $FFFF, an empty subview list. A refused TView part
# returns its rc (the group part does not run).
TGroup.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._groupCreate "$this"
}
TGroup.ChangeBounds() { fv.views._groupChangeBounds "$this" "$@"; }
TGroup.GetHelpCtx() { fv.views._groupGetHelpCtx "$this" "$@"; }
TGroup.Insert() { fv.views.insert "$this" "$@"; }
TGroup.InsertBefore() { fv.views.insertBefore "$this" "$@"; }
TGroup.Draw() { fv.views._groupDraw "$this"; }
TGroup.Lock() { fv.views.lock "$this"; }
TGroup.Unlock() { fv.views.unlock "$this"; }
build TGroup

# TFrame.new NAME AX AY BX BY — FV TFrame.Init: TView's, then GrowMode
# gfGrowHiX + gfGrowHiY, EventMask + evBroadcast, FrameMode 0. It draws the
# FV look of its owner (a TWindow from stage 2c-3; any group): double line
# when sfActive, single when not, the owner's title centred, `[■]` (wfClose)
# and `[↑]` / `↕` (wfZoom) while active, the window number (1..9), the grow
# corner (wfGrow, active), in CFrame's colours through the owner's palette.
# The owner fields read: Flags, Number, Title (or its GetTitle, a func, when
# its class has one).
class TFrame : TView
    public
        var FrameMode
        constructor Create
        override proc Draw
        override func GetPalette
end
TFrame.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._frameCreate "$this"
}
TFrame.Draw() { fv.views._frameDraw "$this"; }
TFrame.GetPalette() { fv.views._frameGetPalette "$this"; }
build TFrame

# ---- the hooks ------------------------------------------------------------------
# fv.views._changed WHY V G AX1 AY1 AX2 AY2 — the REDRAW HOOK. Called after
# the tree or a view's place changed: G is V's owner ('' for a view without
# one; for `delete` the group V was removed from) and the rectangle
# (absolute, B exclusive, not clipped, no shadow) the screen area concerned.
# Nothing is drawn for an invisible V (a V whose State is unset, as in the
# constructor guard's repair, counts as visible); the rectangle is widened by
# FV's ShadowSize (2, 1) when V has sfShadow. WHY and the redraw:
#   insert  fv.views.insert / insertBefore: V's rect (FV InsertBefore ->
#           Show) -> drawView V (V, its shadow, the views in front over it)
#   delete  fv.views.delete, V.delete, the constructor guard's repair: V's
#           rect before the removal (FV Hide -> DrawHide) -> drawUnder G
#   order   putInFrontOf / makeFirst of a visible V: V's rect -> moved to
#           the front past a view that overlapped it: drawView V; moved
#           back past one: the views now in front of it over S(V); else
#           nothing (FV PutInFrontOf's LastView test)
#   bounds  TView / TGroup ChangeBounds: V's old rect ∪ its new rect (FV
#           ChangeBounds -> DrawView / Redraw) -> drawUnder G (a view without
#           an owner: drawView V); a group with a size change calls it once,
#           after its subviews' own `bounds` calls, which run under NODRAW
#   move    locate / moveTo / growTo, after ChangeBounds (which ran under
#           NODRAW): old ∪ new (FV Locate -> DrawUnderRect) -> drawUnder G
# So one place change draws S(A) ∪ S(B) once, in z-order. RESULT is kept.
fv.views._changed() {
    local __fvw_rs0=${RESULT-} __fvw_st=$FV_SF_VISIBLE __fvw_x2=$6 __fvw_y2=$7
    if [[ -n ${__FV_VW_LIVE[$2]-} ]]; then
        local -n __fvw_cd=${2}_data
        __fvw_st=${__fvw_cd[State]-$FV_SF_VISIBLE}
    fi
    if (( ! (__fvw_st & FV_SF_VISIBLE) )); then return 0; fi
    if (( __fvw_st & FV_SF_SHADOW )); then __fvw_x2=$(( __fvw_x2 + 2 )) __fvw_y2=$(( __fvw_y2 + 1 )); fi
    if [ "$1" = insert ]; then fv.views._drawView "$2"
    elif [ "$1" = order ]; then fv.views._order "$2" "$3"
    elif [[ -n $3 ]]; then fv.views._drawUnder "$3" "$4" "$5" "$__fvw_x2" "$__fvw_y2"
    elif ! [ "$1" = delete ]; then fv.views._drawView "$2"; fi
    RESULT=$__fvw_rs0
    return 0
}

# fv.views._order V G — the `order` redraw after putInFrontOf (V's old index
# in __FV_VW_OIDX): V moved in front of a view whose S() met S(V) -> drawView
# V; moved behind one -> the views in front of V over S(V); else nothing
fv.views._order() {
    local -n __fvw_l=${2}_views
    local __fvw_i=-1 __fvw_j=$__FV_VW_OIDX __fvw_a __fvw_b __fvw_k __fvw_m=0
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4
    fv.views._idx "$2" "$1"
    if (( __fvw_i < 0 || __fvw_j < 0 || __fvw_i == __fvw_j )); then return 0; fi
    fv.views._srect "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    if (( __fvw_i > __fvw_j )); then __fvw_a=$__fvw_j __fvw_b=$(( __fvw_i - 1 )); else __fvw_a=$(( __fvw_i + 1 )) __fvw_b=$__fvw_j; fi
    for (( ; __fvw_a <= __fvw_b; __fvw_a++ )); do
        __fvw_k=${__fvw_l[__fvw_a]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
        fv.views._srect "$__fvw_k"
        if (( __fvw_r1 < __fvw_q3 && __fvw_q1 < __fvw_r3 && __fvw_r2 < __fvw_q4 && __fvw_q2 < __fvw_r4 )); then __fvw_m=1; break; fi
    done
    if (( ! __fvw_m )); then return 0; fi
    if (( __fvw_i > __fvw_j )); then fv.views._drawView "$1"
    else fv.views._overOnly "$1" "$__fvw_q1" "$__fvw_q2" "$__fvw_q3" "$__fvw_q4"; fi
}

# fv.views._setCurrent G V — the FOCUS HOOK: G's Current becomes V ('' =
# none), the sfSelected bits move (FV SetCurrent with NormalSelect). P2 stage
# 2c-3 adds the focus chain (sfFocused, the focus broadcasts), the bit
# changes through the virtual-aware setState and the redraw.
fv.views._setCurrent() {
    local -n __fvw_g=${1}_data
    local __fvw_o=${__fvw_g[Current]-}
    if [ "$__fvw_o" = "$2" ]; then return 0; fi
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then
        local -n __fvw_od=${__fvw_o}_data
        __fvw_od[State]=$(( ${__fvw_od[State]:-0} & ~FV_SF_SELECTED ))
    fi
    if [[ -n $2 ]]; then
        local -n __fvw_nd=${2}_data
        __fvw_nd[State]=$(( ${__fvw_nd[State]:-0} | FV_SF_SELECTED ))
    fi
    __fvw_g[Current]=$2
}

# ---- the elision (design §1.4) ----------------------------------------------
# fv.views._virt V METHOD ARGS — call V's METHOD as FV would call a virtual:
# the plain body directly when the method's defining class (the kklass owner
# table, read on every call: no cache) is a built-in one, a kklass dispatch
# (user code) otherwise. The RESULT / rc rule, the same on both paths for
# the supported body forms:
#   * a proc leaves the caller's RESULT; its rc is the body's;
#   * a FUNC answers by setting RESULT and ending WITHOUT an explicit
#     `return` (rc 0); it fails with an explicit `return N` (N != 0), which
#     leaves the caller's RESULT;
#   * not supported in a func override (kklass, its kk._return trailer): an
#     explicit `return 0` (the RESULT is lost: the caller's stays) and a
#     failing last command without `return` (the rc is lost: rc 0, the
#     RESULT kept). Every built-in body here has the supported form.
# The plain path: a FUNC with rc 0 answers, a FUNC with rc != 0 and every
# proc leave the caller's RESULT.
fv.views._virt() {
    local __fvw_c=${1}_class __fvw_f __fvw_r=${RESULT-} __fvw_s=0
    __fvw_c=${!__fvw_c-}
    __fvw_f="${__fvw_c}_class_method_owner[$2]"
    __fvw_f=${__FV_VW_IMPL[${!__fvw_f-}.$2]-}
    if [[ -z $__fvw_f ]]; then "$1.$2" "${@:3}"; return; fi
    "$__fvw_f" "$1" "${@:3}" || __fvw_s=$?
    if [[ -z ${__FV_VW_FUNC[$2]-} ]] || (( __fvw_s )); then RESULT=$__fvw_r; fi
    return "$__fvw_s"
}

# ---- private helpers ----------------------------------------------------------
# fv.views._err MSG — one `Error: fv.views: MSG` line on stderr unless
# VERBOSE_KKLASS=quiet (the loud refusals, see the header)
fv.views._err() {
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then printf 'Error: fv.views: %s\n' "$1" >&2; fi
    return 0
}

# fv.views._bad CALLER MSG — a malformed call: RESULT='', one debug line,
# rc 2 (`if …; then fv.views._bad insert 'wrong argument count'; return; fi`)
fv.views._bad() {
    RESULT=''
    kk.debug "Error: fv.views.$1: $2"
    return 2
}

# fv.views._ints VALUE... — each VALUE an integer (an optional '-', 1-9
# digits, leading zeros decimal) -> the caller's array __fvw_v; rc 1 at the
# first that is not
fv.views._ints() {
    local __fvw_a __fvw_s
    __fvw_v=()
    for __fvw_a; do
        __fvw_s=${__fvw_a#-}
        if [[ -z $__fvw_s || $__fvw_s == *[!0123456789]* || ${#__fvw_s} -gt 9 ]]; then return 1; fi
        if [[ $__fvw_a == -* ]]; then __fvw_v+=("$(( -10#$__fvw_s ))"); else __fvw_v+=("$(( 10#$__fvw_s ))"); fi
    done
}

# fv.views._view V / fv.views._group G — rc 0 for a live view / group; else
# rc 2, RESULT='' and a debug line; a kklass instance that is not a live
# view is a loud error (one Error line): its constructor skipped
# `inherited`, or it was re-created over a live name. A destroyed view is no
# kklass instance any more (`.delete` removed its tables): a debug line only.
fv.views._view() {
    if [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    RESULT=''
    fv.views._dead "$1" "$2"
    return 2
}
fv.views._group() {
    if [[ -n $1 && -n ${__FV_VW_GRP[$1]-} && -n ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    RESULT=''
    if [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} ]]; then kk.debug "Error: fv.views.$2: '$1' is not a group"
    else fv.views._dead "$1" "$2"; fi
    return 2
}
fv.views._dead() {   # NAME CALLER
    local __fvw_n=$1
    # an identifier that names a kklass instance (its class variable is set)
    if [[ -n $__fvw_n && $__fvw_n != *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* \
          && $__fvw_n != [0123456789]* ]]; then
        __fvw_n=${__fvw_n}_class
        if [[ -n ${!__fvw_n-} ]]; then
            __fvw_n="${1}_data[State]"
            if [[ -z ${!__fvw_n+x} ]]; then
                fv.views._err "$2: '$1' is not a live view: its constructor did not call inherited (TView.Create)"
            else
                fv.views._err "$2: '$1' is not a live view (re-created over a live name)"
            fi
            return 0
        fi
    fi
    kk.debug "Error: fv.views.$2: '$1' is not a view"
}

# fv.views._idx G V — __fvw_i (the caller's) = V's index in ${G}_views, -1
# when it is not there
fv.views._idx() {
    local -n __fvw_l=${1}_views
    for (( __fvw_i = ${#__fvw_l[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        if [ "${__fvw_l[__fvw_i]}" = "$2" ]; then return 0; fi
    done
}

# fv.views._calc V [ONLY] — the absolute origin and clip of V and its
# subtree (ONLY 1: of V alone; its subviews keep their old cache)
fv.views._calc() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_x __fvw_y __fvw_w __fvw_h __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_k
    __fvw_x=${__fvw_d[OriginX]:-0} __fvw_y=${__fvw_d[OriginY]:-0}
    __fvw_w=${__fvw_d[SizeX]:-0} __fvw_h=${__fvw_d[SizeY]:-0}
    if [[ -n $__fvw_o ]]; then
        __fvw_x=$(( __fvw_x + __FV_VW_AX[$__fvw_o] )) __fvw_y=$(( __fvw_y + __FV_VW_AY[$__fvw_o] ))
        __fvw_1=${__FV_VW_C1[$__fvw_o]} __fvw_2=${__FV_VW_C2[$__fvw_o]}
        __fvw_3=${__FV_VW_C3[$__fvw_o]} __fvw_4=${__FV_VW_C4[$__fvw_o]}
        if (( __fvw_x > __fvw_1 )); then __fvw_1=$__fvw_x; fi
        if (( __fvw_y > __fvw_2 )); then __fvw_2=$__fvw_y; fi
        if (( __fvw_x + __fvw_w < __fvw_3 )); then __fvw_3=$(( __fvw_x + __fvw_w )); fi
        if (( __fvw_y + __fvw_h < __fvw_4 )); then __fvw_4=$(( __fvw_y + __fvw_h )); fi
    else
        __fvw_1=$__fvw_x __fvw_2=$__fvw_y __fvw_3=$(( __fvw_x + __fvw_w )) __fvw_4=$(( __fvw_y + __fvw_h ))
    fi
    if (( __fvw_3 < __fvw_1 )); then __fvw_3=$__fvw_1; fi
    if (( __fvw_4 < __fvw_2 )); then __fvw_4=$__fvw_2; fi
    __FV_VW_AX[$1]=$__fvw_x __FV_VW_AY[$1]=$__fvw_y
    __FV_VW_C1[$1]=$__fvw_1 __FV_VW_C2[$1]=$__fvw_2 __FV_VW_C3[$1]=$__fvw_3 __FV_VW_C4[$1]=$__fvw_4
    if [[ -n ${__FV_VW_GRP[$1]-} && ${2-} != 1 ]]; then
        local -n __fvw_l=${1}_views
        for __fvw_k in "${__fvw_l[@]}"; do fv.views._calc "$__fvw_k"; done
    fi
}

# fv.views._setBounds V AX AY BX BY [ONLY] — FV SetBounds (the width capped
# at MaxViewWidth) + the bounds cache of V's subtree (ONLY 1: of V alone)
fv.views._setBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_w=$(( $4 - $2 ))
    if (( __fvw_w > __FV_VW_MAXW )); then __fvw_w=$__FV_VW_MAXW; fi
    __fvw_d[OriginX]=$2 __fvw_d[OriginY]=$3 __fvw_d[SizeX]=$__fvw_w __fvw_d[SizeY]=$(( $5 - $3 ))
    fv.views._calc "$1" "${6-}"
}

# fv.views._abs V — __fvw_r1..4 (the caller's): V's absolute rect
fv.views._abs() {
    local -n __fvw_d=${1}_data
    __fvw_r1=${__FV_VW_AX[$1]} __fvw_r2=${__FV_VW_AY[$1]}
    __fvw_r3=$(( __fvw_r1 + ${__fvw_d[SizeX]:-0} )) __fvw_r4=$(( __fvw_r2 + ${__fvw_d[SizeY]:-0} ))
}

# fv.views._resetCurrent G — FV ResetCurrent: Current := the front-most
# visible selectable subview (FirstMatch(sfVisible, ofSelectable)), else none
fv.views._resetCurrent() {
    local -n __fvw_l=${1}_views
    local __fvw_i __fvw_k
    for (( __fvw_i = ${#__fvw_l[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        __fvw_k=${__fvw_l[__fvw_i]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) && (${__fvw_kd[Options]:-0} & FV_OF_SELECTABLE) )); then
            fv.views._setCurrent "$1" "$__fvw_k"
            return 0
        fi
    done
    fv.views._setCurrent "$1" ''
}

# fv.views._detach G V I — remove V (at index I) from G's list, Owner = '',
# Current reset as FV's Delete does (Hide -> ResetCurrent for a visible
# selectable V; and whenever V was Current), V's subtree cache made
# root-relative
fv.views._detach() {
    local -n __fvw_l=${1}_views __fvw_d=${2}_data __fvw_g=${1}_data
    __fvw_l=("${__fvw_l[@]:0:$3}" "${__fvw_l[@]:$3+1}")
    __fvw_d[Owner]=''
    if (( (${__fvw_d[State]:-0} & FV_SF_VISIBLE) && (${__fvw_d[Options]:-0} & FV_OF_SELECTABLE) )) \
       || [ "${__fvw_g[Current]-}" = "$2" ]; then
        fv.views._resetCurrent "$1"
    fi
    fv.views._calc "$2"
    fv.views._palReset "$2"
}

# fv.views._free V — the destruction of V's own part: a group's subviews
# are destroyed (front to back, each with Owner cleared first, so that none
# goes through a per-view removal), its list freed; the private entries go
fv.views._free() {
    local __fvw_k
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        local -n __fvw_l=${1}_views
        local -a __fvw_kids=("${__fvw_l[@]}")
        __fvw_l=()
        for (( __fvw_k = ${#__fvw_kids[@]} - 1; __fvw_k >= 0; __fvw_k-- )); do
            if [[ -n ${__FV_VW_LIVE[${__fvw_kids[__fvw_k]}]-} ]]; then
                local -n __fvw_kd=${__fvw_kids[__fvw_k]}_data
                __fvw_kd[Owner]=''
            fi
            if declare -F "${__fvw_kids[__fvw_k]}.delete" >/dev/null; then "${__fvw_kids[__fvw_k]}.delete"; fi
        done
        unset "${1}_views" '__FV_VW_GRP[$1]'
    fi
    # a group destroyed while locked no longer holds the flush; when nothing
    # holds it any more, what was drawn meanwhile (its removal) is sent now
    if [[ -n ${__FV_VW_LK[$1]-} ]]; then
        __FV_VW_LOCKN=$(( __FV_VW_LOCKN - ${__FV_VW_LK[$1]} ))
        if (( __FV_VW_LOCKN < 0 )); then __FV_VW_LOCKN=0; fi
        if (( __FV_VW_LOCKN == 0 )); then
            local __fvw_rr=${RESULT-}
            fv.views._flush
            RESULT=$__fvw_rr
        fi
    fi
    # a frame's string cache: one slot per state (fv.views._frameRows)
    if [[ -n ${__FV_VW_FRM[$1]-} ]]; then
        for __fvw_k in 0 1 2 3; do
            unset "__FV_VW_FK[$1.$__fvw_k]" "__FV_VW_FT[$1.$__fvw_k]" "__FV_VW_FTA[$1.$__fvw_k]" \
                "__FV_VW_FM[$1.$__fvw_k]" "__FV_VW_FMA[$1.$__fvw_k]" "__FV_VW_FB[$1.$__fvw_k]" \
                "__FV_VW_FBA[$1.$__fvw_k]" "__FV_VW_FS[$1.$__fvw_k]" "__FV_VW_FSA[$1.$__fvw_k]"
        done
    fi
    unset '__FV_VW_LIVE[$1]' '__FV_VW_AX[$1]' '__FV_VW_AY[$1]' \
        '__FV_VW_C1[$1]' '__FV_VW_C2[$1]' '__FV_VW_C3[$1]' '__FV_VW_C4[$1]' \
        '__FV_VW_PAL[$1]' '__FV_VW_FRM[$1]' '__FV_VW_LK[$1]'
}

# ---- construction, destruction, reserved names (design §1.6) ----------------
fv.views._create() {   # V AX AY BX BY
    local __fvw_n=$1 __fvw_g __fvw_i
    local -a __fvw_v
    shift
    # a reserved name (`__fv` inside: framework-made views) only through
    # fv.views._newReserved
    if [[ ${__fvw_n#*__fv} != "$__fvw_n" ]] && ! [ "$__fvw_n" = "$__FV_VW_RESNAME" ]; then
        fv.views._err "TView.Create: '$__fvw_n': names with '__fv' are reserved for framework-made views"
        __FV_VW_CRC=2
        return 2
    fi
    __FV_VW_RESNAME=''
    # the constructor guard: kklass re-creates a live instance without its
    # destructor; repair the tree (the stale name out of its owner's list,
    # its old subviews destroyed, its entries freed) and refuse
    if [[ -n ${__FV_VW_LIVE[$__fvw_n]-} ]]; then
        for __fvw_g in "${!__FV_VW_GRP[@]}"; do
            fv.views._idx "$__fvw_g" "$__fvw_n"
            if (( __fvw_i >= 0 )); then
                local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
                fv.views._abs "$__fvw_n"
                fv.views._detach "$__fvw_g" "$__fvw_n" "$__fvw_i"
                fv.views._changed delete "$__fvw_n" "$__fvw_g" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
                break
            fi
        done
        local -n __fvw_d=${__fvw_n}_data
        __fvw_d[Owner]=''
        fv.views._free "$__fvw_n"
        fv.views._err "TView.Create: '$__fvw_n' is a live view: re-creating it is refused (delete it first: $__fvw_n.delete); its old tree was removed"
        __FV_VW_CRC=1
        return 1
    fi
    if (( $# < 4 )) || ! fv.views._ints "$1" "$2" "$3" "$4"; then
        fv.views._err "TView.Create: '$__fvw_n': the bounds must be four integers AX AY BX BY (got: $*)"
        __FV_VW_CRC=2
        return 2
    fi
    local -n __fvw_d=${__fvw_n}_data
    __fvw_d[Owner]='' __fvw_d[CursorX]=0 __fvw_d[CursorY]=0 __fvw_d[State]=$FV_SF_VISIBLE __fvw_d[Options]=0
    __fvw_d[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
    __fvw_d[GrowMode]=0 __fvw_d[DragMode]=$FV_DM_LIMITLOY __fvw_d[HelpCtx]=$FV_HC_NOCONTEXT
    __FV_VW_LIVE[$__fvw_n]=1
    fv.views._setBounds "$__fvw_n" "${__fvw_v[@]}"
}

fv.views._groupCreate() {   # G
    local -n __fvw_d=${1}_data
    __fvw_d[Options]=$(( ${__fvw_d[Options]:-0} | FV_OF_SELECTABLE | FV_OF_BUFFERED ))
    __fvw_d[EventMask]=$(( 0xFFFF ))
    __fvw_d[Current]='' __fvw_d[Phase]=phFocused __fvw_d[EndState]='' __fvw_d[LockFlag]=0
    declare -ga "${1}_views=()"
    __FV_VW_GRP[$1]=1
}

# V.delete (FV Done): V out of its owner first (one `delete` redraw of its
# area), then a group's subviews destroyed, then V's entries freed. A name
# that is not live (refused or repaired by the guard) has nothing to undo.
fv.views._done() {   # V
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    if [[ -n $__fvw_o && -n ${__FV_VW_GRP[$__fvw_o]-} ]]; then
        fv.views._idx "$__fvw_o" "$1"
        if (( __fvw_i >= 0 )); then
            fv.views._abs "$1"
            fv.views._detach "$__fvw_o" "$1" "$__fvw_i"
            fv.views._changed delete "$1" "$__fvw_o" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        fi
    fi
    fv.views._free "$1"
}

# fv.views._newReserved OWNER ROLE CLASS ARGS... — the framework's way to make
# a view with the reserved name ${OWNER}__fv${ROLE} (win1__fvframe,
# app__fvdesktop): CLASS.new under that name; RESULT = the name. ROLE:
# letters and digits. rc: the constructor's (2 for a bad ROLE).
fv.views._newReserved() {
    if [[ -z ${2-} || $2 == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]* ]] || (( $# < 3 )); then
        fv.views._bad _newReserved 'OWNER ROLE CLASS ARGS (ROLE: letters and digits)'; return
    fi
    local __fvw_n=${1}__fv$2 __fvw_s=0
    __FV_VW_RESNAME=$__fvw_n
    "$3.new" "$__fvw_n" "${@:4}" || __fvw_s=$?
    __FV_VW_RESNAME=''
    RESULT=$__fvw_n
    return "$__fvw_s"
}

# fv.views.isView V — rc 0 when V is a live view (constructed through
# TView.Create and not destroyed or re-created since); for a constructor of
# yours: `inherited; fv.views.isView "$this" || return 1`
fv.views.isView() {
    [[ -n ${1-} && -n ${__FV_VW_LIVE[$1]-} ]]
}

# ---- the tree (FV TGroup.Insert / InsertBefore / Delete, TView.MakeFirst /
# PutInFrontOf / Next / Prev / NextView / PrevView, TGroup.First / Last) ------

# fv.views.insert G V — FV Insert: V in front of every subview of G
fv.views.insert() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" insert || return
    local -n __fvw_l=${1}_views
    local __fvw_t=''
    if (( ${#__fvw_l[@]} )); then __fvw_t=${__fvw_l[-1]}; fi
    fv.views._insert "$1" "$2" "$__fvw_t" insert
}

# fv.views.insertBefore G V TARGET — FV InsertBefore: V directly in front of
# TARGET (a subview of G); TARGET '' = behind every subview (FV Target = nil)
fv.views.insertBefore() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" insertBefore || return
    fv.views._insert "$1" "$2" "$3" insertBefore
}

fv.views._insert() {   # G V TARGET CALLER
    local __fvw_i=-1 __fvw_p __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    fv.views._view "$2" "$4" || return
    local -n __fvw_d=${2}_data __fvw_gd=${1}_data __fvw_l=${1}_views
    if [[ -n ${__fvw_d[Owner]-} ]]; then
        RESULT=''; kk.debug "Error: fv.views.$4: '$2' is already in '${__fvw_d[Owner]}'"; return 1
    fi
    # no cycle: V is neither G nor an owner of G
    __fvw_p=$1
    while [[ -n $__fvw_p ]]; do
        if [ "$__fvw_p" = "$2" ]; then RESULT=''; kk.debug "Error: fv.views.$4: '$2' would own itself"; return 1; fi
        local -n __fvw_pd=${__fvw_p}_data
        __fvw_p=${__fvw_pd[Owner]-}
    done
    if [[ -n $3 ]]; then
        fv.views._idx "$1" "$3"
        if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.$4: '$3' is not a subview of '$1'"; return 1; fi
    fi
    # FV InsertBefore: centring by ofCenterX / ofCenterY (FV `div`: toward 0)
    if (( ${__fvw_d[Options]:-0} & FV_OF_CENTERX )); then
        __fvw_d[OriginX]=$(( (${__fvw_gd[SizeX]:-0} - ${__fvw_d[SizeX]:-0}) / 2 ))
    fi
    if (( ${__fvw_d[Options]:-0} & FV_OF_CENTERY )); then
        __fvw_d[OriginY]=$(( (${__fvw_gd[SizeY]:-0} - ${__fvw_d[SizeY]:-0}) / 2 ))
    fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_i+1}" "$2" "${__fvw_l[@]:$__fvw_i+1}")
    __fvw_d[Owner]=$1
    fv.views._calc "$2"
    fv.views._palReset "$2"
    # FV: Show -> SetState(sfVisible) -> Owner^.ResetCurrent for a selectable
    # V. (2c-3: a group with sfActive passes sfActive to V, FV InsertBefore.)
    if (( (${__fvw_d[State]:-0} & FV_SF_VISIBLE) && (${__fvw_d[Options]:-0} & FV_OF_SELECTABLE) )); then
        fv.views._resetCurrent "$1"
    fi
    fv.views._abs "$2"
    fv.views._changed insert "$2" "$1" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# fv.views.delete G V — FV Delete: V out of G (its Owner '', Current reset
# as FV does, V keeps its State); V stays a live view that may be inserted
# again. Destroying it is V.delete.
fv.views.delete() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" delete || return
    fv.views._view "$2" delete || return
    local __fvw_i=-1 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    fv.views._idx "$1" "$2"
    if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.delete: '$2' is not a subview of '$1'"; return 1; fi
    fv.views._abs "$2"
    fv.views._detach "$1" "$2" "$__fvw_i"
    fv.views._changed delete "$2" "$1" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# fv.views.putInFrontOf V TARGET — FV PutInFrontOf: V directly in front of
# TARGET (a sibling; '' = behind all). A no-op without an owner, for TARGET =
# V or when V already is directly in front of TARGET. A visible V: the
# `order` redraw and, when V is selectable, FV's ResetCurrent.
fv.views.putInFrontOf() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" putInFrontOf || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_j __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    [[ -n $__fvw_g ]] || return 0
    if [ "$2" = "$1" ]; then return 0; fi
    local -n __fvw_l=${__fvw_g}_views
    fv.views._idx "$__fvw_g" "$1"
    __fvw_j=$__fvw_i
    if [[ -n $2 ]]; then
        fv.views._idx "$__fvw_g" "$2"
        if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.putInFrontOf: '$2' is not a sibling of '$1'"; return 1; fi
        # TARGET = V's NextView (the view directly behind V)
        if (( __fvw_i == __fvw_j - 1 )); then return 0; fi
    elif (( __fvw_j == 0 )); then
        return 0
    fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_j}" "${__fvw_l[@]:$__fvw_j+1}")
    __fvw_i=-1
    if [[ -n $2 ]]; then fv.views._idx "$__fvw_g" "$2"; fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_i+1}" "$1" "${__fvw_l[@]:$__fvw_i+1}")
    if (( ${__fvw_d[State]:-0} & FV_SF_VISIBLE )); then
        if (( ${__fvw_d[Options]:-0} & FV_OF_SELECTABLE )); then fv.views._resetCurrent "$__fvw_g"; fi
        fv.views._abs "$1"
        __FV_VW_OIDX=$__fvw_j
        fv.views._changed order "$1" "$__fvw_g" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        __FV_VW_OIDX=-1
    fi
}

# fv.views.makeFirst V — FV MakeFirst: V in front of its siblings
fv.views.makeFirst() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" makeFirst || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-}
    [[ -n $__fvw_g ]] || return 0
    local -n __fvw_l=${__fvw_g}_views
    fv.views.putInFrontOf "$1" "${__fvw_l[-1]}"
}

# navigation: RESULT = the view, rc 1 and RESULT='' for FV's nil
# first G (FV First: the front), last G (FV Last: the back)
fv.views.first() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" first || return
    local -n __fvw_l=${1}_views
    if (( ${#__fvw_l[@]} )); then RESULT=${__fvw_l[-1]}; return 0; fi
    RESULT=''
    return 1
}
fv.views.last() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" last || return
    local -n __fvw_l=${1}_views
    if (( ${#__fvw_l[@]} )); then RESULT=${__fvw_l[0]}; return 0; fi
    RESULT=''
    return 1
}
# next V (FV Next: the view behind V; the back one's Next is the front one,
# a ring), prev V (FV Prev: the view in front of V; the front one's Prev is
# the back one), nextView / prevView (FV NextView / PrevView: nil at the
# end instead of the wrap). A view without an owner: nil.
fv.views.next() { fv.views._step "${1-}" -1 1 next "$#"; }
fv.views.prev() { fv.views._step "${1-}" 1 1 prev "$#"; }
fv.views.nextView() { fv.views._step "${1-}" -1 0 nextView "$#"; }
fv.views.prevView() { fv.views._step "${1-}" 1 0 prevView "$#"; }
fv.views._step() {   # V DIR WRAP CALLER ARGC
    if (( $5 != 1 )); then fv.views._bad "${FUNCNAME[1]#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" "$4" || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_n
    RESULT=''
    [[ -n $__fvw_g ]] || return 1
    local -n __fvw_l=${__fvw_g}_views
    fv.views._idx "$__fvw_g" "$1"
    __fvw_n=${#__fvw_l[@]}
    __fvw_i=$(( __fvw_i + $2 ))
    if (( __fvw_i < 0 || __fvw_i >= __fvw_n )); then
        (( $3 )) || return 1
        __fvw_i=$(( (__fvw_i + __fvw_n) % __fvw_n ))
    fi
    RESULT=${__fvw_l[__fvw_i]}
}

# ---- geometry (FV GetBounds, GetExtent, Locate, MoveTo, GrowTo, MakeLocal,
# MakeGlobal, MouseInView; ChangeBounds, CalcBounds, SizeLimits) ---------------

# fv.views.getBounds V — RESULT="AX AY BX BY" (owner-relative corners, B
# exclusive) and FV_RECT_AX/_AY/_BX/_BY
fv.views.getBounds() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getBounds || return
    local -n __fvw_d=${1}_data
    FV_RECT_AX=${__fvw_d[OriginX]:-0} FV_RECT_AY=${__fvw_d[OriginY]:-0}
    FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_d[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_d[SizeY]:-0} ))
    RESULT="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
}
# fv.views.getExtent V — RESULT="0 0 SizeX SizeY" and FV_RECT_*
fv.views.getExtent() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getExtent || return
    local -n __fvw_d=${1}_data
    FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=${__fvw_d[SizeX]:-0} FV_RECT_BY=${__fvw_d[SizeY]:-0}
    RESULT="0 0 $FV_RECT_BX $FV_RECT_BY"
}

# fv.views.locate V AX AY BX BY — FV Locate: the size clamped by V's
# SizeLimits (virtual), then, when the bounds differ, V's ChangeBounds
# (virtual) and the `move` redraw of old ∪ new
fv.views.locate() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" locate || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3" "$4" "$5"; then
        RESULT=''; kk.debug "Error: fv.views.locate: the bounds must be integers"; return 2
    fi
    fv.views._locate "$1" "${__fvw_v[@]}"
}
fv.views._locate() {   # V AX AY BX BY (integers)
    local -n __fvw_d=${1}_data
    local __fvw_ax=$2 __fvw_ay=$3 __fvw_w=$(( $4 - $2 )) __fvw_h=$(( $5 - $3 ))
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4
    fv.views._virt "$1" SizeLimits
    if (( __fvw_w < FV_MIN_X )); then __fvw_w=$FV_MIN_X; elif (( __fvw_w > FV_MAX_X )); then __fvw_w=$FV_MAX_X; fi
    if (( __fvw_h < FV_MIN_Y )); then __fvw_h=$FV_MIN_Y; elif (( __fvw_h > FV_MAX_Y )); then __fvw_h=$FV_MAX_Y; fi
    if (( __fvw_ax == ${__fvw_d[OriginX]:-0} && __fvw_ay == ${__fvw_d[OriginY]:-0} )) \
       && (( __fvw_w == ${__fvw_d[SizeX]:-0} && __fvw_h == ${__fvw_d[SizeY]:-0} )); then
        return 0
    fi
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    # ChangeBounds' own redraw is held: the `move` redraw below covers old ∪ new once
    local __fvw_s=0
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
    fv.views._virt "$1" ChangeBounds "$__fvw_ax" "$__fvw_ay" "$(( __fvw_ax + __fvw_w ))" "$(( __fvw_ay + __fvw_h ))" || __fvw_s=$?
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
    if (( __fvw_s )); then return "$__fvw_s"; fi
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed move "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}
# fv.views.moveTo V X Y — FV MoveTo: locate at (X, Y) with V's size
fv.views.moveTo() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" moveTo || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.moveTo: X Y must be integers"; return 2; fi
    local -n __fvw_d=${1}_data
    fv.views._locate "$1" "${__fvw_v[0]}" "${__fvw_v[1]}" \
        "$(( __fvw_v[0] + ${__fvw_d[SizeX]:-0} ))" "$(( __fvw_v[1] + ${__fvw_d[SizeY]:-0} ))"
}
# fv.views.growTo V W H — FV GrowTo: locate at V's origin with size W x H
fv.views.growTo() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" growTo || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.growTo: W H must be integers"; return 2; fi
    local -n __fvw_d=${1}_data
    local __fvw_x=${__fvw_d[OriginX]:-0} __fvw_y=${__fvw_d[OriginY]:-0}
    fv.views._locate "$1" "$__fvw_x" "$__fvw_y" "$(( __fvw_x + __fvw_v[0] ))" "$(( __fvw_y + __fvw_v[1] ))"
}
# fv.views.changeBounds V AX AY BX BY — V's ChangeBounds through the
# elision (an override of yours runs; FV calls ChangeBounds directly)
fv.views.changeBounds() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" changeBounds || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3" "$4" "$5"; then
        RESULT=''; kk.debug "Error: fv.views.changeBounds: the bounds must be integers"; return 2
    fi
    fv.views._virt "$1" ChangeBounds "${__fvw_v[@]}"
}

# fv.views.makeLocal V X Y / makeGlobal V X Y — a screen point to V's
# coordinates and back: RESULT="X Y" and FV_POINT_X / FV_POINT_Y. From the
# cached absolute origin (FV walks the owner chain; FPC's MakeLocal stops
# that walk at a negative coordinate, this one never does).
fv.views.makeLocal() { fv.views._point "$@" -1 makeLocal; }
fv.views.makeGlobal() { fv.views._point "$@" 1 makeGlobal; }
fv.views._point() {   # V X Y SIGN CALLER
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME[1]#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" "$5" || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.$5: X Y must be integers"; return 2; fi
    FV_POINT_X=$(( __fvw_v[0] + $4 * __FV_VW_AX[$1] )) FV_POINT_Y=$(( __fvw_v[1] + $4 * __FV_VW_AY[$1] ))
    RESULT="$FV_POINT_X $FV_POINT_Y"
}
# fv.views.mouseInView V X Y — rc 0 when the screen point (X, Y) lies in V's
# rect (FV MouseInView; not clipped by the owners)
fv.views.mouseInView() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" mouseInView || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then fv.views._bad mouseInView 'X Y must be integers'; return; fi
    local -n __fvw_d=${1}_data
    (( __fvw_v[0] >= __FV_VW_AX[$1] && __fvw_v[1] >= __FV_VW_AY[$1] )) \
       && (( __fvw_v[0] < __FV_VW_AX[$1] + ${__fvw_d[SizeX]:-0} && __fvw_v[1] < __FV_VW_AY[$1] + ${__fvw_d[SizeY]:-0} ))
}

# ---- the built-in virtuals' plain bodies (registered in __FV_VW_IMPL) ---------

# TView.ChangeBounds AX AY BX BY — FV: SetBounds; DrawView (the `bounds` redraw)
fv.views._viewChangeBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2
    local __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    fv.views._setBounds "$1" "$2" "$3" "$4" "$5"
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed bounds "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# TGroup.ChangeBounds AX AY BX BY — FV: without a size change SetBounds +
# Redraw; with one SetBounds, then each subview (front to back, FV ForEach)
# takes CalcBounds by its GrowMode and its ChangeBounds (both virtual), then
# the group's `bounds` redraw (FV: Lock ... Unlock).
# With a size change only the group's own cache moves first, so that each
# subview's ChangeBounds still sees its old absolute rect (its `bounds` hook
# gets old ∪ new); the whole subtree's cache is recomputed at the end (also
# for a subview whose ChangeBounds override skipped `inherited`).
# FV_RECT_* holds the subview's current bounds before its CalcBounds: an
# override that sets nothing (or fails) keeps the subview where it is. A
# subview that an earlier one destroyed or removed from the group is skipped.
fv.views._groupChangeBounds() {
    local -n __fvw_d=${1}_data __fvw_l=${1}_views
    local __fvw_dx=$(( $4 - $2 - ${__fvw_d[SizeX]:-0} )) __fvw_dy=$(( $5 - $3 - ${__fvw_d[SizeY]:-0} ))
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4 __fvw_k __fvw_i
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    if (( __fvw_dx != 0 || __fvw_dy != 0 )); then
        fv.views._setBounds "$1" "$2" "$3" "$4" "$5" 1
        # the subviews' own redraws are held (bulk layout): the group's
        # `bounds` redraw below covers them all, once
        __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
        local -a __fvw_kids=("${__fvw_l[@]}")
        for (( __fvw_i = ${#__fvw_kids[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
            __fvw_k=${__fvw_kids[__fvw_i]}
            fv.views._kid "$1" "$__fvw_k" || continue
            local -n __fvw_kd=${__fvw_k}_data
            FV_RECT_AX=${__fvw_kd[OriginX]:-0} FV_RECT_AY=${__fvw_kd[OriginY]:-0}
            FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_kd[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_kd[SizeY]:-0} ))
            fv.views._virt "$__fvw_k" CalcBounds "$__fvw_dx" "$__fvw_dy" || :
            fv.views._kid "$1" "$__fvw_k" || continue
            fv.views._virt "$__fvw_k" ChangeBounds "$FV_RECT_AX" "$FV_RECT_AY" "$FV_RECT_BX" "$FV_RECT_BY" || :
        done
        __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
        fv.views._calc "$1"
    else
        fv.views._setBounds "$1" "$2" "$3" "$4" "$5"
    fi
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed bounds "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# fv.views._kid G K — rc 0 while K is a live view whose owner is G
fv.views._kid() {
    [[ -n ${__FV_VW_LIVE[$2]-} ]] || return 1
    local -n __fvw_kk=${2}_data
    [ "${__fvw_kk[Owner]-}" = "$1" ]
}

# TView.CalcBounds DX DY — FV CalcBounds: FV_RECT_* = V's bounds after its
# owner grew by (DX, DY), by GrowMode (gfGrowLoX/HiX/LoY/HiY move the edge by
# the delta; gfGrowRel scales it with the owner's new / old size), the width
# capped at MaxViewWidth, the size clamped by SizeLimits (virtual). A view
# without an owner or with GrowMode 0 keeps its bounds.
fv.views._viewCalcBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_m=${__fvw_d[GrowMode]:-0} __fvw_o=${__fvw_d[Owner]-} __fvw_s __fvw_dd
    FV_RECT_AX=${__fvw_d[OriginX]:-0} FV_RECT_AY=${__fvw_d[OriginY]:-0}
    FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_d[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_d[SizeY]:-0} ))
    if (( __fvw_m == 0 )) || [[ -z $__fvw_o ]]; then return 0; fi
    local -n __fvw_od=${__fvw_o}_data
    __fvw_s=${__fvw_od[SizeX]:-0} __fvw_dd=$2
    if (( __fvw_m & FV_GF_GROWLOX )); then fv.views._grow FV_RECT_AX; fi
    if (( __fvw_m & FV_GF_GROWHIX )); then fv.views._grow FV_RECT_BX; fi
    if (( FV_RECT_BX - FV_RECT_AX > __FV_VW_MAXW )); then FV_RECT_BX=$(( FV_RECT_AX + __FV_VW_MAXW )); fi
    __fvw_s=${__fvw_od[SizeY]:-0} __fvw_dd=$3
    if (( __fvw_m & FV_GF_GROWLOY )); then fv.views._grow FV_RECT_AY; fi
    if (( __fvw_m & FV_GF_GROWHIY )); then fv.views._grow FV_RECT_BY; fi
    local __fvw_w=$(( FV_RECT_BX - FV_RECT_AX )) __fvw_h=$(( FV_RECT_BY - FV_RECT_AY ))
    local __fvw_ax=$FV_RECT_AX __fvw_ay=$FV_RECT_AY
    fv.views._virt "$1" SizeLimits
    if (( __fvw_w < FV_MIN_X )); then __fvw_w=$FV_MIN_X; elif (( __fvw_w > FV_MAX_X )); then __fvw_w=$FV_MAX_X; fi
    if (( __fvw_h < FV_MIN_Y )); then __fvw_h=$FV_MIN_Y; elif (( __fvw_h > FV_MAX_Y )); then __fvw_h=$FV_MAX_Y; fi
    # (a SizeLimits override of yours may use FV_RECT_*: put them back)
    FV_RECT_AX=$__fvw_ax FV_RECT_AY=$__fvw_ay FV_RECT_BX=$(( __fvw_ax + __fvw_w )) FV_RECT_BY=$(( __fvw_ay + __fvw_h ))
}
# FV GrowI: the edge (a variable name) by the caller's __fvw_dd / __fvw_s /
# __fvw_m: + delta, or relative I := (I*S + (S-D) shr 1) div (S-D), 1 when
# the old size S-D is 0
fv.views._grow() {
    local -n __fvw_e=$1
    if (( ! (__fvw_m & FV_GF_GROWREL) )); then __fvw_e=$(( __fvw_e + __fvw_dd ))
    elif (( __fvw_s == __fvw_dd )); then __fvw_e=1
    else __fvw_e=$(( (__fvw_e * __fvw_s + ((__fvw_s - __fvw_dd) >> 1)) / (__fvw_s - __fvw_dd) )); fi
}

# TView.SizeLimits — FV: FV_MIN_X/_Y = 0; FV_MAX_X/_Y = the owner's size
# (FV TGroup.ClipChilds is true), high(Sw_Integer) without an owner
fv.views._viewSizeLimits() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-}
    FV_MIN_X=0 FV_MIN_Y=0
    if [[ -n $__fvw_o ]]; then
        local -n __fvw_od=${__fvw_o}_data
        FV_MAX_X=${__fvw_od[SizeX]:-0} FV_MAX_Y=${__fvw_od[SizeY]:-0}
    else
        FV_MAX_X=$__FV_VW_HIGH FV_MAX_Y=$__FV_VW_HIGH
    fi
}

# TView.GetHelpCtx (func) — FV: hcDragging while sfDragging, else HelpCtx
fv.views._viewGetHelpCtx() {
    local -n __fvw_d=${1}_data
    if (( ${__fvw_d[State]:-0} & FV_SF_DRAGGING )); then RESULT=$FV_HC_DRAGGING
    else RESULT=${__fvw_d[HelpCtx]:-0}; fi
}
# TGroup.GetHelpCtx (func) — FV: Current's GetHelpCtx (virtual), else TView's
fv.views._groupGetHelpCtx() {
    local -n __fvw_d=${1}_data
    local __fvw_c=${__fvw_d[Current]-}
    RESULT=$FV_HC_NOCONTEXT
    if [[ -n $__fvw_c && -n ${__FV_VW_LIVE[$__fvw_c]-} ]]; then fv.views._virt "$__fvw_c" GetHelpCtx; fi
    if [[ ${RESULT-} == "$FV_HC_NOCONTEXT" ]]; then fv.views._viewGetHelpCtx "$1"; fi
}

# ==== drawing (P2 stage 2c-2; design §1.5, §1.7, §1.9, §1.10) ===================
#
# The painter: back to front, no z-order clip walk. paint(V, R) draws V (its
# Draw through the elision) clipped to V's clip ∩ R; a group's Draw paints its
# visible subviews back to front, skipping one that a COVERING front sibling
# hides entirely (a leaf, or a group whose back-most subview is a visible
# frame of its full size: "Draw must cover its rect"), and shades the
# shadow of each sfShadow subview after drawing it. drawView V = paint(V) +
# V's shadow + over(V, S(V)): every visible view in front of V or of one of
# its owners whose S() meets the rectangle is painted again, clipped to it.
# drawUnder(G, rect) = paint(G, rect) + over(G, rect). The terminal update
# (fv.video.updateScreen) runs once at the end of each outermost drawing
# entry, unless lockScreenUpdate or a user lock holds it.
#
# The fv.video clip: the outermost drawing entry saves the caller's clip
# (fv.video.getClip) and puts it back at its end. Each paint sets the clip
# to what it may write; a paint that returns into a Draw body (a nested
# drawView, a decoration after `inherited Draw`) puts that Draw's clip back,
# one that returns into a framework loop does not (the next paint sets its
# own). The drawing context (FV_DRAW_*, FV_CLIP_*) is saved and restored by
# each paint, so a drawView or drawPart nested inside a Draw leaves the outer
# Draw's context intact.
#
# Rules on top (review round of 2c-2): a view whose Draw runs is never painted
# again from inside it (__FV_VW_INDRAW; a nested draw behind a covering one of
# them leaves that part out: fv.views._nestCut); a change inside a frameless
# group is repainted from the first covering owner (fv.views._drawUnder);
# screen rows with wide cells are repainted across the whole width
# (fv.views._bands); a Draw's rc is ignored (FV procedure).

# fv.views._begin / fv.views._end — a drawing entry's frame: the caller
# declares `local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4`
fv.views._begin() {
    __fvw_bg=$__FV_VW_INGRP __fvw_b1=$__FV_VW_P1 __fvw_b2=$__FV_VW_P2 __fvw_b3=$__FV_VW_P3 __fvw_b4=$__FV_VW_P4
    if (( __FV_VW_DEPTH == 0 )); then
        if fv.video.getClip; then __FV_VW_UCLIP=$RESULT; else __FV_VW_UCLIP=''; fi
    fi
    __FV_VW_DEPTH=$(( __FV_VW_DEPTH + 1 )) __FV_VW_INGRP=1
}
fv.views._end() {
    local __fvw_c=$__FV_VW_UCLIP __fvw_1 __fvw_2 __fvw_3
    __FV_VW_DEPTH=$(( __FV_VW_DEPTH - 1 ))
    __FV_VW_INGRP=$__fvw_bg __FV_VW_P1=$__fvw_b1 __FV_VW_P2=$__fvw_b2 __FV_VW_P3=$__fvw_b3 __FV_VW_P4=$__fvw_b4
    if (( __FV_VW_DEPTH == 0 )); then
        if [[ -n $__fvw_c ]]; then
            __fvw_1=${__fvw_c%% *} __fvw_c=${__fvw_c#* }
            __fvw_2=${__fvw_c%% *} __fvw_c=${__fvw_c#* }
            __fvw_3=${__fvw_c%% *} __fvw_c=${__fvw_c#* }
            fv.video.setClip "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_c" || :
        fi
    elif (( ! __fvw_bg )); then
        fv.video.setClip "$__fvw_b1" "$__fvw_b2" "$__fvw_b3" "$__fvw_b4" || :
    fi
    return 0
}

# fv.views._flush — the terminal update, unless held (lockScreenUpdate, a
# user lock) or inside another drawing entry (the outermost one flushes)
fv.views._flush() {
    if (( __FV_VW_LSU == 0 && __FV_VW_LOCKN == 0 && __FV_VW_DEPTH == 0 )); then
        # (a redraw's forced update waits here while the update is held)
        if (( __FV_VW_FORCE )); then __FV_VW_FORCE=0; fv.video.updateScreen force || :
        else fv.video.updateScreen || :; fi
    fi
    return 0
}

# fv.views._drawable V — rc 0 when V may be drawn now: drawing not held
# (NODRAW), V and every owner visible, none of them locked (fv.views.lock:
# its unlock redraws it), and the root of V's tree has sfExposed (FV: a view
# is drawn only inside the application's tree; fv.app sets the bit on the
# application, a desktop-less user or test on its root group)
fv.views._drawable() {
    if (( __FV_VW_NODRAW > 0 )); then return 1; fi
    local __fvw_v=$1
    while :; do
        local -n __fvw_dd=${__fvw_v}_data
        if (( ! (${__fvw_dd[State]:-0} & FV_SF_VISIBLE) )) || [[ -n ${__FV_VW_LK[$__fvw_v]-} ]]; then return 1; fi
        if [[ -z ${__fvw_dd[Owner]-} ]]; then break; fi
        __fvw_v=${__fvw_dd[Owner]}
    done
    (( ${__fvw_dd[State]:-0} & FV_SF_EXPOSED ))
}

# fv.views._srect V — __fvw_r1..4 (the caller's): S(V), V's absolute rect
# widened by FV's ShadowSize (2, 1) when V has sfShadow
fv.views._srect() {
    local -n __fvw_sd=${1}_data
    __fvw_r1=${__FV_VW_AX[$1]} __fvw_r2=${__FV_VW_AY[$1]}
    __fvw_r3=$(( __fvw_r1 + ${__fvw_sd[SizeX]:-0} )) __fvw_r4=$(( __fvw_r2 + ${__fvw_sd[SizeY]:-0} ))
    if (( ${__fvw_sd[State]:-0} & FV_SF_SHADOW )); then __fvw_r3=$(( __fvw_r3 + 2 )) __fvw_r4=$(( __fvw_r4 + 1 )); fi
}

# fv.views._paint V R1 R2 R3 R4 — paint V clipped to its clip ∩ the absolute
# rectangle R (no flush, no over): the context set, V's Draw through the
# elision (inline: a built-in TGroup.Draw runs as fv.views._groupDraw V 1),
# the context restored
fv.views._paint() {
    # re-entrancy: a view whose Draw is running (on the paint stack: the view
    # and the groups painting it) is never painted again from inside it
    if [[ -n ${__FV_VW_INDRAW[$1]-} ]]; then return 0; fi
    local __fvw_1=${__FV_VW_C1[$1]} __fvw_2=${__FV_VW_C2[$1]} __fvw_3=${__FV_VW_C3[$1]} __fvw_4=${__FV_VW_C4[$1]}
    if (( $2 > __fvw_1 )); then __fvw_1=$2; fi
    if (( $3 > __fvw_2 )); then __fvw_2=$3; fi
    if (( $4 < __fvw_3 )); then __fvw_3=$4; fi
    if (( $5 < __fvw_4 )); then __fvw_4=$5; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    local __fvw_sv=$FV_DRAW_VIEW __fvw_sx=$FV_DRAW_X __fvw_sy=$FV_DRAW_Y __fvw_sp=$FV_DRAW_PAL
    local __fvw_c1=$FV_CLIP_X1 __fvw_c2=$FV_CLIP_Y1 __fvw_c3=$FV_CLIP_X2 __fvw_c4=$FV_CLIP_Y2
    local __fvw_p1=$__FV_VW_P1 __fvw_p2=$__FV_VW_P2 __fvw_p3=$__FV_VW_P3 __fvw_p4=$__FV_VW_P4
    local __fvw_g=$__FV_VW_INGRP __fvw_f __fvw_o
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    FV_DRAW_VIEW=$1 FV_DRAW_X=${__FV_VW_AX[$1]} FV_DRAW_Y=${__FV_VW_AY[$1]} FV_DRAW_PAL=${__FV_VW_PAL[$1]}
    FV_CLIP_X1=$(( __fvw_1 - FV_DRAW_X )) FV_CLIP_Y1=$(( __fvw_2 - FV_DRAW_Y ))
    FV_CLIP_X2=$(( __fvw_3 - FV_DRAW_X )) FV_CLIP_Y2=$(( __fvw_4 - FV_DRAW_Y ))
    __FV_VW_P1=$__fvw_1 __FV_VW_P2=$__fvw_2 __FV_VW_P3=$__fvw_3 __FV_VW_P4=$__fvw_4 __FV_VW_INGRP=0
    fv.video.setClip "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4" || :
    __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    __fvw_f=${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}
    # Draw is an FV procedure: its rc is ignored (a Draw of yours ending in a
    # false test must not end a caller running under set -e)
    __FV_VW_INDRAW[$1]=1
    if [[ -z $__fvw_f ]]; then "$1.Draw" || :
    elif [ "$__fvw_f" = fv.views._groupDraw ]; then fv.views._groupDraw "$1" 1 || :
    else "$__fvw_f" "$1" || :; fi
    unset '__FV_VW_INDRAW[$1]'
    FV_DRAW_VIEW=$__fvw_sv FV_DRAW_X=$__fvw_sx FV_DRAW_Y=$__fvw_sy FV_DRAW_PAL=$__fvw_sp
    FV_CLIP_X1=$__fvw_c1 FV_CLIP_Y1=$__fvw_c2 FV_CLIP_X2=$__fvw_c3 FV_CLIP_Y2=$__fvw_c4
    __FV_VW_P1=$__fvw_p1 __FV_VW_P2=$__fvw_p2 __FV_VW_P3=$__fvw_p3 __FV_VW_P4=$__fvw_p4 __FV_VW_INGRP=$__fvw_g
    if (( ! __fvw_g )); then fv.video.setClip "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4" || :; fi
    return 0
}

# fv.views._shade V R1 R2 R3 R4 — V's shadow (FV ShadowSize 2 x 1: the two
# columns right of V from its second row, the row below V from its third
# column) ∩ R ∩ V's owner's clip, attribute only (fv.video.shadeRect, the
# shadow symbol V). rc 0 when something was shaded (the fv.video clip was set
# to R ∩ the owner's clip), 1 when nothing
fv.views._shade() {
    local -n __fvw_hd=${1}_data
    local __fvw_o=${__fvw_hd[Owner]-}
    if [[ -z $__fvw_o ]] || (( ! (${__fvw_hd[State]:-0} & FV_SF_SHADOW) )); then return 1; fi
    local __fvw_1=${__FV_VW_C1[$__fvw_o]} __fvw_2=${__FV_VW_C2[$__fvw_o]} __fvw_3=${__FV_VW_C3[$__fvw_o]} __fvw_4=${__FV_VW_C4[$__fvw_o]}
    if (( $2 > __fvw_1 )); then __fvw_1=$2; fi
    if (( $3 > __fvw_2 )); then __fvw_2=$3; fi
    if (( $4 < __fvw_3 )); then __fvw_3=$4; fi
    if (( $5 < __fvw_4 )); then __fvw_4=$5; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 1; fi
    local __fvw_x=${__FV_VW_AX[$1]} __fvw_y=${__FV_VW_AY[$1]} __fvw_w=${__fvw_hd[SizeX]:-0} __fvw_h=${__fvw_hd[SizeY]:-0}
    local __fvw_ax __fvw_ay __fvw_bx __fvw_by __fvw_n=0
    local -a __fvw_q=(
        "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + 1 ))" "$(( __fvw_x + __fvw_w + 2 ))" "$(( __fvw_y + __fvw_h + 1 ))"
        "$(( __fvw_x + 2 ))" "$(( __fvw_y + __fvw_h ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h + 1 ))"
    )
    for __fvw_x in 0 4; do
        __fvw_ax=${__fvw_q[__fvw_x]} __fvw_ay=${__fvw_q[__fvw_x+1]} __fvw_bx=${__fvw_q[__fvw_x+2]} __fvw_by=${__fvw_q[__fvw_x+3]}
        if (( __fvw_ax < __fvw_1 )); then __fvw_ax=$__fvw_1; fi
        if (( __fvw_ay < __fvw_2 )); then __fvw_ay=$__fvw_2; fi
        if (( __fvw_bx > __fvw_3 )); then __fvw_bx=$__fvw_3; fi
        if (( __fvw_by > __fvw_4 )); then __fvw_by=$__fvw_4; fi
        if (( __fvw_ax >= __fvw_bx || __fvw_ay >= __fvw_by )); then continue; fi
        if (( ! __fvw_n )); then fv.video.setClip "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4" || :; __fvw_n=1; fi
        fv.video.shadeRect "$__fvw_ax" "$__fvw_ay" "$(( __fvw_bx - __fvw_ax ))" "$(( __fvw_by - __fvw_ay ))" || :
    done
    (( __fvw_n ))
}

# fv.views._covers V — rc 0 when V paints its whole rect: a leaf, or a group
# whose back-most subview is a visible TFrame of the group's full size (a
# frameless group is not covering; a shadow never covers)
fv.views._covers() {
    if [[ -z ${__FV_VW_GRP[$1]-} ]]; then return 0; fi
    local -n __fvw_vl=${1}_views
    if (( ! ${#__fvw_vl[@]} )); then return 1; fi
    local __fvw_f=${__fvw_vl[0]}
    if [[ -z ${__FV_VW_FRM[$__fvw_f]-} ]]; then return 1; fi
    local -n __fvw_fd=${__fvw_f}_data __fvw_gd=${1}_data
    if (( ! (${__fvw_fd[State]:-0} & FV_SF_VISIBLE) )); then return 1; fi
    if (( ${__fvw_fd[OriginX]:-0} != 0 || ${__fvw_fd[OriginY]:-0} != 0 )); then return 1; fi
    (( ${__fvw_fd[SizeX]:-0} == ${__fvw_gd[SizeX]:-0} && ${__fvw_fd[SizeY]:-0} == ${__fvw_gd[SizeY]:-0} ))
}

# fv.views._over V — paint, clipped to each rectangle of the caller's array
# __fvw_rs (absolute X1 Y1 X2 Y2, ...), every visible view in front of V or
# of one of V's owners whose S() meets it (back to front at each level), and
# its shadow
fv.views._over() {
    local __fvw_v=$1 __fvw_o __fvw_i=-1 __fvw_n __fvw_k __fvw_j __fvw_m=${#__fvw_rs[@]}
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    while :; do
        local -n __fvw_vd=${__fvw_v}_data
        __fvw_o=${__fvw_vd[Owner]-}
        if [[ -z $__fvw_o ]]; then return 0; fi
        local -n __fvw_ol=${__fvw_o}_views
        __fvw_n=${#__fvw_ol[@]}
        fv.views._idx "$__fvw_o" "$__fvw_v"
        for (( __fvw_i = __fvw_i + 1; __fvw_i < __fvw_n; __fvw_i++ )); do
            __fvw_k=${__fvw_ol[__fvw_i]}
            local -n __fvw_kd=${__fvw_k}_data
            if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
            # (a view whose Draw is running: not painted again from inside it)
            if [[ -n ${__FV_VW_INDRAW[$__fvw_k]-} ]]; then continue; fi
            fv.views._srect "$__fvw_k"
            for (( __fvw_j = 0; __fvw_j < __fvw_m; __fvw_j += 4 )); do
                if (( __fvw_r1 >= __fvw_rs[__fvw_j+2] || __fvw_rs[__fvw_j] >= __fvw_r3 )); then continue; fi
                if (( __fvw_r2 < __fvw_rs[__fvw_j+3] && __fvw_rs[__fvw_j+1] < __fvw_r4 )); then
                    fv.views._paint "$__fvw_k" "${__fvw_rs[@]:__fvw_j:4}"
                    if (( ${__fvw_kd[State]:-0} & FV_SF_SHADOW )); then fv.views._shade "$__fvw_k" "${__fvw_rs[@]:__fvw_j:4}" || :; fi
                fi
            done
        done
        __fvw_v=$__fvw_o
    done
}

# fv.views._nestCut X — for a drawView / drawPart nested inside a Draw: take
# out of the caller's rectangles __fvw_rs the clip of the COVERING view in
# front of X whose Draw is running (the paint stack): X is behind it, so
# what X paints must not land on it (that view finishes its own Draw). One
# such view at most (the paint stack is one chain); found by walking X's
# owners for a front sibling on the stack, then down the stack to the first
# covering view. Up to four pieces per rectangle
fv.views._nestCut() {
    if (( ! ${#__FV_VW_INDRAW[@]} )); then return 0; fi
    local __fvw_v=$1 __fvw_o __fvw_i=-1 __fvw_n __fvw_k='' __fvw_c __fvw_j
    while [[ -z $__fvw_k ]]; do
        local -n __fvw_vd=${__fvw_v}_data
        __fvw_o=${__fvw_vd[Owner]-}
        if [[ -z $__fvw_o ]]; then return 0; fi
        local -n __fvw_ol=${__fvw_o}_views
        __fvw_n=${#__fvw_ol[@]}
        fv.views._idx "$__fvw_o" "$__fvw_v"
        for (( __fvw_i = __fvw_i + 1; __fvw_i < __fvw_n; __fvw_i++ )); do
            if [[ -n ${__FV_VW_INDRAW[${__fvw_ol[__fvw_i]}]-} ]]; then __fvw_k=${__fvw_ol[__fvw_i]}; break; fi
        done
        __fvw_v=$__fvw_o
    done
    # down the stack to the first view that covers its rect
    while ! fv.views._covers "$__fvw_k"; do
        local -n __fvw_kl=${__fvw_k}_views
        __fvw_c=''
        for __fvw_j in "${__fvw_kl[@]}"; do
            if [[ -n ${__FV_VW_INDRAW[$__fvw_j]-} ]]; then __fvw_c=$__fvw_j; break; fi
        done
        if [[ -z $__fvw_c ]]; then return 0; fi
        __fvw_k=$__fvw_c
    done
    local __fvw_e1=${__FV_VW_C1[$__fvw_k]} __fvw_e2=${__FV_VW_C2[$__fvw_k]} __fvw_e3=${__FV_VW_C3[$__fvw_k]} __fvw_e4=${__FV_VW_C4[$__fvw_k]}
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_t __fvw_b
    local -a __fvw_nr=()
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
        if (( __fvw_1 >= __fvw_e3 || __fvw_e1 >= __fvw_3 || __fvw_2 >= __fvw_e4 || __fvw_e2 >= __fvw_4 )); then
            __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"); continue
        fi
        __fvw_t=$__fvw_2 __fvw_b=$__fvw_4
        if (( __fvw_2 < __fvw_e2 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_e2"); __fvw_t=$__fvw_e2; fi
        if (( __fvw_e4 < __fvw_4 )); then __fvw_nr+=("$__fvw_1" "$__fvw_e4" "$__fvw_3" "$__fvw_4"); __fvw_b=$__fvw_e4; fi
        if (( __fvw_1 < __fvw_e1 )); then __fvw_nr+=("$__fvw_1" "$__fvw_t" "$__fvw_e1" "$__fvw_b"); fi
        if (( __fvw_e3 < __fvw_3 )); then __fvw_nr+=("$__fvw_e3" "$__fvw_t" "$__fvw_3" "$__fvw_b"); fi
    done
    __fvw_rs=("${__fvw_nr[@]}")
}

# fv.views._bands — wide characters and the repaint edges: a write cut by a
# clip edge leaves a blank in the visible half of a wide character and blanks
# the other half of the one it covers (fv.video's rules), so a repaint
# rectangle whose edge cuts a wide character would differ from a full
# repaint. Rows that hold or held wide cells (__FV_VW_WROW, kept by
# fv.views._wideMark) are therefore repainted across the whole screen width:
# each rectangle of the caller's __fvw_rs is split into runs of rows, and a
# run of such rows becomes a full-width band (each row banded once). No such
# row: nothing to do
fv.views._bands() {
    if (( ! ${#__FV_VW_WROW[@]} )); then return 0; fi
    local __fvw_j __fvw_y __fvw_r __fvw_s __fvw_w=$FV_SCREEN_W __fvw_q
    local -a __fvw_nr=() __fvw_dn=()
    local __fvw_e
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        # (the rows on the screen only: nothing is drawn outside it)
        __fvw_y=${__fvw_rs[__fvw_j+1]} __fvw_e=${__fvw_rs[__fvw_j+3]}
        if (( __fvw_y < 0 )); then __fvw_y=0; fi
        if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
        while (( __fvw_y < __fvw_e )); do
            __fvw_s=${__FV_VW_WROW[__fvw_y]-}
            for (( __fvw_r = __fvw_y + 1; __fvw_r < __fvw_e; __fvw_r++ )); do
                if ! [ "${__FV_VW_WROW[__fvw_r]-}" = "$__fvw_s" ]; then break; fi
            done
            if [[ -z $__fvw_s ]]; then
                __fvw_nr+=("${__fvw_rs[__fvw_j]}" "$__fvw_y" "${__fvw_rs[__fvw_j+2]}" "$__fvw_r")
            else
                # (the rows not banded yet, as one band)
                for (( __fvw_q = __fvw_y; __fvw_q < __fvw_r; __fvw_q++ )); do
                    if [[ -z ${__fvw_dn[__fvw_q]-} ]]; then break; fi
                done
                if (( __fvw_q < __fvw_r )); then
                    __fvw_nr+=(0 "$__fvw_y" "$__fvw_w" "$__fvw_r")
                    for (( __fvw_q = __fvw_y; __fvw_q < __fvw_r; __fvw_q++ )); do __fvw_dn[__fvw_q]=1; done
                fi
            fi
            __fvw_y=$__fvw_r
        done
    done
    __fvw_rs=("${__fvw_nr[@]}")
}

# fv.views._wideMark — after a repaint: the rows of the caller's __fvw_rs
# that now hold wide cells (fv.video's per-row flag __FV_VS_WIDE, read as a
# friend) are marked in __FV_VW_WROW; a row repainted across the whole width
# without one is unmarked
fv.views._wideMark() {
    local __fvw_j __fvw_y __fvw_a=$FV_SCREEN_H __fvw_b=0
    local -a __fvw_full=()
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if (( __fvw_rs[__fvw_j+1] < __fvw_a )); then __fvw_a=${__fvw_rs[__fvw_j+1]}; fi
        if (( __fvw_rs[__fvw_j+3] > __fvw_b )); then __fvw_b=${__fvw_rs[__fvw_j+3]}; fi
        if (( __fvw_rs[__fvw_j] <= 0 && __fvw_rs[__fvw_j+2] >= FV_SCREEN_W )); then
            for (( __fvw_y = __fvw_rs[__fvw_j+1]; __fvw_y < __fvw_rs[__fvw_j+3]; __fvw_y++ )); do __fvw_full[__fvw_y]=1; done
        fi
    done
    if (( __fvw_a < 0 )); then __fvw_a=0; fi
    if (( __fvw_b > FV_SCREEN_H )); then __fvw_b=$FV_SCREEN_H; fi
    for (( __fvw_y = __fvw_a; __fvw_y < __fvw_b; __fvw_y++ )); do
        if (( ${__FV_VS_WIDE[__fvw_y]:-0} )); then __FV_VW_WROW[__fvw_y]=1
        elif [[ -n ${__fvw_full[__fvw_y]-} ]]; then unset '__FV_VW_WROW[__fvw_y]'; fi
    done
}

# fv.views._drawView V — FV DrawView (+ DrawShow's shadow): when V may be
# drawn, paint V, shade its shadow, the views in front over S(V), flush.
# Nested inside a Draw: what lies under a covering view in that Draw is left
# out (fv.views._nestCut); rows with wide cells are banded (fv.views._bands)
fv.views._drawView() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_j
    fv.views._srect "$1"
    local -a __fvw_rs=("$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4")
    fv.views._nestCut "$1"
    fv.views._bands
    fv.views._begin
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        fv.views._paint "$1" "${__fvw_rs[@]:__fvw_j:4}"
        fv.views._shade "$1" "${__fvw_rs[@]:__fvw_j:4}" || :
    done
    fv.views._over "$1"
    fv.views._wideMark
    fv.views._end
    fv.views._flush
}

# fv.views._drawUnder G X1 Y1 X2 Y2 — FV DrawUnderRect: the rectangle ∩ G's
# clip (only that can have changed: G's subviews and their shadows are clipped
# to it) repainted from below. A group that does not cover its rect (a
# frameless group) leaves its uncovered cells to the views behind it, so the
# repaint starts at the first owner that covers (a framed group) or at the
# root: that group painted clipped to the rectangle, then the views in front
# of it over it, flush
fv.views._drawUnder() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_g=$1 __fvw_j
    local __fvw_1=$2 __fvw_2=$3 __fvw_3=$4 __fvw_4=$5
    if (( __FV_VW_C1[$1] > __fvw_1 )); then __fvw_1=${__FV_VW_C1[$1]}; fi
    if (( __FV_VW_C2[$1] > __fvw_2 )); then __fvw_2=${__FV_VW_C2[$1]}; fi
    if (( __FV_VW_C3[$1] < __fvw_3 )); then __fvw_3=${__FV_VW_C3[$1]}; fi
    if (( __FV_VW_C4[$1] < __fvw_4 )); then __fvw_4=${__FV_VW_C4[$1]}; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    while ! fv.views._covers "$__fvw_g"; do
        local -n __fvw_gd=${__fvw_g}_data
        if [[ -z ${__fvw_gd[Owner]-} ]]; then break; fi
        __fvw_g=${__fvw_gd[Owner]}
    done
    local -a __fvw_rs=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4")
    fv.views._bands
    fv.views._begin
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        fv.views._paint "$__fvw_g" "${__fvw_rs[@]:__fvw_j:4}"
    done
    fv.views._over "$__fvw_g"
    fv.views._wideMark
    fv.views._end
    fv.views._flush
}

# fv.views._overOnly V X1 Y1 X2 Y2 — only the views in front of V over the
# rectangle, flush (V moved behind views that overlap it)
fv.views._overOnly() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4
    local -a __fvw_rs=("$2" "$3" "$4" "$5")
    fv.views._bands
    fv.views._begin
    fv.views._over "$1"
    fv.views._wideMark
    fv.views._end
    fv.views._flush
}

# ---- the public drawing API (FV DrawView, Redraw, Show, Hide, Lock, Unlock,
# LockScreenUpdate, UnlockScreenUpdate; drawPart) -------------------------------

# fv.views.drawView V — FV DrawView: V drawn in place with its shadow, the
# views in front of it over it, the terminal updated (unless held). Nothing
# for a V that is hidden, has a hidden or locked owner, or whose tree's root
# lacks sfExposed
fv.views.drawView() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" drawView || return
    local __fvw_r=${RESULT-}
    fv.views._drawView "$1"
    RESULT=$__fvw_r
}

# fv.views.redraw V — FV Redraw: as drawView, with a forced terminal update
# (every cell sent again); while the update is held (lockScreenUpdate, a user
# lock, another drawing entry) the force waits for the release
fv.views.redraw() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" redraw || return
    local __fvw_r=${RESULT-}
    __FV_VW_FORCE=1
    if fv.views._drawable "$1"; then fv.views._drawView "$1"; else fv.views._flush; fi
    RESULT=$__fvw_r
}

# fv.views.drawPart V FN Y1 Y2 [ARGS] — partial redraw of a LEAF (rule 4):
# the plain painter FN runs as `FN V ARGS` with V's drawing context, its
# writes clipped to V's local rows Y1 <= y < Y2; then the views in front of V
# that overlap those rows are painted again over them, and the terminal is
# updated. No dispatch. A group is refused (rc 2): its painter would write
# over its own subviews. Nested inside a Draw, the part under a covering view
# in that Draw is left out (FN may then run once per remaining piece). rc:
# FN's (the last non-zero one; 0 when V cannot be drawn now: FN does not run)
fv.views.drawPart() {
    if (( $# < 4 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" drawPart || return
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then fv.views._bad drawPart "'$1' is a group: drawPart paints a leaf (redraw a group with drawView)"; return; fi
    if ! declare -F "$2" >/dev/null; then fv.views._bad drawPart "'$2' is not a function"; return; fi
    local -a __fvw_v
    if ! fv.views._ints "$3" "$4"; then fv.views._bad drawPart 'Y1 Y2 must be integers'; return; fi
    local __fvw_r=${RESULT-} __fvw_s=0 __fvw_j __fvw_e=0
    if ! fv.views._drawable "$1"; then return 0; fi
    if [[ -n ${__FV_VW_INDRAW[$1]-} ]]; then return 0; fi
    local __fvw_1=${__FV_VW_C1[$1]} __fvw_2=$(( __FV_VW_AY[$1] + __fvw_v[0] )) __fvw_3=${__FV_VW_C3[$1]} __fvw_4=$(( __FV_VW_AY[$1] + __fvw_v[1] ))
    if (( __fvw_2 < __FV_VW_C2[$1] )); then __fvw_2=${__FV_VW_C2[$1]}; fi
    if (( __fvw_4 > __FV_VW_C4[$1] )); then __fvw_4=${__FV_VW_C4[$1]}; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4
    local __fvw_sv=$FV_DRAW_VIEW __fvw_sx=$FV_DRAW_X __fvw_sy=$FV_DRAW_Y __fvw_sp=$FV_DRAW_PAL
    local __fvw_c1=$FV_CLIP_X1 __fvw_c2=$FV_CLIP_Y1 __fvw_c3=$FV_CLIP_X2 __fvw_c4=$FV_CLIP_Y2
    local -a __fvw_rs=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4")
    fv.views._nestCut "$1"
    if (( ! ${#__fvw_rs[@]} )); then return 0; fi
    fv.views._begin
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    FV_DRAW_VIEW=$1 FV_DRAW_X=${__FV_VW_AX[$1]} FV_DRAW_Y=${__FV_VW_AY[$1]} FV_DRAW_PAL=${__FV_VW_PAL[$1]}
    __FV_VW_INGRP=0 __FV_VW_INDRAW[$1]=1
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
        FV_CLIP_X1=$(( __fvw_1 - FV_DRAW_X )) FV_CLIP_Y1=$(( __fvw_2 - FV_DRAW_Y ))
        FV_CLIP_X2=$(( __fvw_3 - FV_DRAW_X )) FV_CLIP_Y2=$(( __fvw_4 - FV_DRAW_Y ))
        __FV_VW_P1=$__fvw_1 __FV_VW_P2=$__fvw_2 __FV_VW_P3=$__fvw_3 __FV_VW_P4=$__fvw_4
        fv.video.setClip "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4" || :
        __fvw_e=0
        "$2" "$1" "${@:5}" || __fvw_e=$?
        if (( __fvw_e )); then __fvw_s=$__fvw_e; fi
    done
    unset '__FV_VW_INDRAW[$1]'
    FV_DRAW_VIEW=$__fvw_sv FV_DRAW_X=$__fvw_sx FV_DRAW_Y=$__fvw_sy FV_DRAW_PAL=$__fvw_sp
    FV_CLIP_X1=$__fvw_c1 FV_CLIP_Y1=$__fvw_c2 FV_CLIP_X2=$__fvw_c3 FV_CLIP_Y2=$__fvw_c4
    __FV_VW_INGRP=1
    fv.views._bands
    fv.views._over "$1"
    fv.views._wideMark
    fv.views._end
    fv.views._flush
    RESULT=$__fvw_r
    return "$__fvw_s"
}

# fv.views.show V / hide V — FV Show / Hide (SetState sfVisible; the
# virtual-aware setState is stage 2c-3): the bit, then (V in a group) FV's
# DrawShow (drawView V with its shadow) / DrawHide (drawUnder the owner over
# S(V)), then the owner's ResetCurrent for a selectable V. A no-op when the
# bit already is so
fv.views.show() { fv.views._showHide "${1-}" 1 show "$#"; }
fv.views.hide() { fv.views._showHide "${1-}" 0 hide "$#"; }
fv.views._showHide() {   # V ON CALLER ARGC
    if (( $4 != 1 )); then fv.views._bad "$3" 'wrong argument count'; return; fi
    fv.views._view "$1" "$3" || return
    local -n __fvw_d=${1}_data
    local __fvw_st=${__fvw_d[State]:-0} __fvw_o=${__fvw_d[Owner]-} __fvw_r=${RESULT-}
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    if (( $2 )); then
        if (( __fvw_st & FV_SF_VISIBLE )); then return 0; fi
        __fvw_d[State]=$(( __fvw_st | FV_SF_VISIBLE ))
        if [[ -n $__fvw_o ]]; then fv.views._drawView "$1"; fi
    else
        if (( ! (__fvw_st & FV_SF_VISIBLE) )); then return 0; fi
        __fvw_d[State]=$(( __fvw_st & ~FV_SF_VISIBLE ))
        if [[ -n $__fvw_o ]]; then
            fv.views._srect "$1"
            fv.views._drawUnder "$__fvw_o" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        fi
    fi
    if [[ -n $__fvw_o ]] && (( ${__fvw_d[Options]:-0} & FV_OF_SELECTABLE )); then fv.views._resetCurrent "$__fvw_o"; fi
    RESULT=$__fvw_r
}

# fv.views.lock G / unlock G — FV TGroup.Lock / Unlock (the LockFlag count):
# while G is locked, no drawView of G or of a view inside it is drawn (the
# hooks' redraws included) and the terminal update is held; when its count
# returns to 0, G is redrawn once (FV Unlock -> DrawView; when an owner of G
# is still locked, that owner's unlock draws it). unlock of an unlocked
# group: a no-op
fv.views.lock() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" lock || return
    local -n __fvw_d=${1}_data
    __FV_VW_LK[$1]=$(( ${__FV_VW_LK[$1]:-0} + 1 ))
    __fvw_d[LockFlag]=${__FV_VW_LK[$1]}
    __FV_VW_LOCKN=$(( __FV_VW_LOCKN + 1 ))
}
fv.views.unlock() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" unlock || return
    if [[ -z ${__FV_VW_LK[$1]-} ]]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_r=${RESULT-}
    __FV_VW_LOCKN=$(( __FV_VW_LOCKN - 1 ))
    if (( __FV_VW_LOCKN < 0 )); then __FV_VW_LOCKN=0; fi
    if (( ${__FV_VW_LK[$1]} > 1 )); then
        __FV_VW_LK[$1]=$(( ${__FV_VW_LK[$1]} - 1 ))
        __fvw_d[LockFlag]=${__FV_VW_LK[$1]}
        return 0
    fi
    unset '__FV_VW_LK[$1]'
    __fvw_d[LockFlag]=0
    if fv.views._drawable "$1"; then fv.views._drawView "$1"; else fv.views._flush; fi
    RESULT=$__fvw_r
}

# fv.views.lockScreenUpdate / unlockScreenUpdate — FV LockScreenUpdate /
# UnlockScreenUpdate: hold the terminal update (a count); the drawing into
# the buffer goes on. At 0 again, unlockScreenUpdate updates the terminal
# (unless a user lock still holds it); unlockScreenUpdate at 0: a no-op
fv.views.lockScreenUpdate() {
    if (( $# )); then fv.views._bad "${FUNCNAME#fv.views.}" 'no arguments'; return; fi
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
}
fv.views.unlockScreenUpdate() {
    if (( $# )); then fv.views._bad "${FUNCNAME#fv.views.}" 'no arguments'; return; fi
    if (( __FV_VW_LSU == 0 )); then return 0; fi
    local __fvw_r=${RESULT-}
    __FV_VW_LSU=$(( __FV_VW_LSU - 1 ))
    fv.views._flush
    RESULT=$__fvw_r
}

# ---- palettes (design §1.9) ------------------------------------------------------

# fv.views._pal V — resolve V's palette into __FV_VW_PAL[V] (FV GetColor's
# owner walk, done once): V's GetPalette (a func, through the elision) is a
# list of indices into its owner's resolved palette ('' = none: V maps as
# its owner does); the root maps into the app palette __FV_VW_APAL. An index
# that is 0, not a number or past the palette below gives ErrorAttr's
# symbol (__FV_VW_ERRSYM). RESULT is kept.
fv.views._pal() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_b __fvw_r=${RESULT-} __fvw_p='' __fvw_n __fvw_i
    if [[ -n $__fvw_o ]]; then
        if [[ -z ${__FV_VW_PAL[$__fvw_o]+x} ]]; then fv.views._pal "$__fvw_o"; fi
        __fvw_b=${__FV_VW_PAL[$__fvw_o]}
    else
        __fvw_b=$__FV_VW_APAL
    fi
    RESULT=''
    fv.views._virt "$1" GetPalette || RESULT=''
    if [[ -z ${RESULT-} ]]; then __FV_VW_PAL[$1]=$__fvw_b; RESULT=$__fvw_r; return 0; fi
    local -a __fvw_a
    local IFS=' '
    read -r -a __fvw_a <<< "$RESULT"
    for __fvw_n in "${__fvw_a[@]}"; do
        if [[ $__fvw_n == *[!0123456789]* || ${#__fvw_n} -gt 4 ]]; then __fvw_p+=$__FV_VW_ERRSYM; continue; fi
        __fvw_i=$(( 10#$__fvw_n ))
        if (( __fvw_i >= 1 && __fvw_i <= ${#__fvw_b} )); then __fvw_p+=${__fvw_b:__fvw_i-1:1}; else __fvw_p+=$__FV_VW_ERRSYM; fi
    done
    __FV_VW_PAL[$1]=$__fvw_p
    RESULT=$__fvw_r
}

# fv.views._palReset V — drop the resolved palette of V and its subtree
fv.views._palReset() {
    unset '__FV_VW_PAL[$1]'
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        local -n __fvw_pl=${1}_views
        local __fvw_k
        for __fvw_k in "${__fvw_pl[@]}"; do fv.views._palReset "$__fvw_k"; done
    fi
}

# fv.views.resetPalette [V] — forget resolved palettes (V's subtree, or every
# view): after a GetPalette answer changed (a TWindow's Palette field, an
# override of yours) or the app palette did (fv.app's setAppPalette). They
# are resolved again at the next draw; nothing is redrawn here
fv.views.resetPalette() {
    if (( $# > 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    if (( $# == 0 )); then __FV_VW_PAL=(); return 0; fi
    fv.views._view "$1" resetPalette || return
    fv.views._palReset "$1"
}

# fv.views.getColor V I — FV GetColor(I): RESULT = the fv.video symbol of
# V's palette entry I (1-based), ErrorAttr's symbol for an index outside it.
# Inside a Draw the same is ${FV_DRAW_PAL:I-1:1}
fv.views.getColor() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getColor || return
    if [[ -z $2 || $2 == *[!0123456789]* || ${#2} -gt 4 ]]; then fv.views._bad getColor 'I must be a palette index (digits)'; return; fi
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    local __fvw_p=${__FV_VW_PAL[$1]} __fvw_i=$(( 10#$2 ))
    if (( __fvw_i >= 1 && __fvw_i <= ${#__fvw_p} )); then RESULT=${__fvw_p:__fvw_i-1:1}; else RESULT=$__FV_VW_ERRSYM; fi
}

# ---- the writers (design §1.5): view-local coordinates, one fv.video call ------
# Only inside a Draw or a drawPart painter (FV_DRAW_VIEW set; else rc 2);
# COLOR is an index into the view's palette (FV WriteStr's Color);
# RESULT = fv.video's answer (the cells the write advances), rc = its rc.
# Writes are clipped to the part of the view the paint may change; FV writes
# update the terminal at once, these leave it to the drawing entry.

# fv.views._wxy X Y CALLER — the caller's __fvw_x / __fvw_y = the absolute
# point; rc 2 (fv.views._bad) outside a Draw or for a non-integer
fv.views._wxy() {
    if [[ -z $FV_DRAW_VIEW ]]; then fv.views._bad "$3" 'outside a Draw (draw through drawView / drawPart)'; return; fi
    local __fvw_a=${1#-} __fvw_b=${2#-}
    if [[ -z $__fvw_a || $__fvw_a == *[!0123456789]* || ${#__fvw_a} -gt 7 \
          || -z $__fvw_b || $__fvw_b == *[!0123456789]* || ${#__fvw_b} -gt 7 ]]; then
        fv.views._bad "$3" 'X Y must be integers'; return
    fi
    if [[ $1 == -* ]]; then __fvw_x=$(( FV_DRAW_X - 10#$__fvw_a )); else __fvw_x=$(( FV_DRAW_X + 10#$__fvw_a )); fi
    if [[ $2 == -* ]]; then __fvw_y=$(( FV_DRAW_Y - 10#$__fvw_b )); else __fvw_y=$(( FV_DRAW_Y + 10#$__fvw_b )); fi
}
# fv.views._wcol I CALLER — the caller's __fvw_c = palette entry I's symbol
# (ErrorAttr's outside the palette); rc 2 for a non-index
fv.views._wcol() {
    if [[ -z $1 || $1 == *[!0123456789]* || ${#1} -gt 4 ]]; then fv.views._bad "$2" 'COLOR must be a palette index'; return; fi
    local __fvw_i=$(( 10#$1 ))
    if (( __fvw_i >= 1 && __fvw_i <= ${#FV_DRAW_PAL} )); then __fvw_c=${FV_DRAW_PAL:__fvw_i-1:1}; else __fvw_c=$__FV_VW_ERRSYM; fi
}

# Each writer first tries the fast path: inside a Draw, X and Y plain digits
# (1-7), COLOR 1-99 within the palette, the right count -> one arithmetic
# step and the fv.video call; anything else (negative coordinates, an index
# outside the palette, an error) takes the checked path below.

# fv.views.writeStr X Y TEXT COLOR — FV WriteStr
fv.views.writeStr() {
    if (( $# == 4 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${4-} == [123456789] || ${4-} == [123456789][0123456789] ]] && (( $4 <= ${#FV_DRAW_PAL} )); then
            fv.video.writeStr "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "${FV_DRAW_PAL:$4-1:1}"
            return
        fi
    fi
    if (( $# != 4 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" writeStr || return
    fv.views._wcol "$4" writeStr || return
    fv.video.writeStr "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c"
}
# fv.views.writeChar X Y CH COLOR [COUNT] — FV WriteChar (COUNT default 1)
fv.views.writeChar() {
    if (( $# == 4 || $# == 5 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${4-} == [123456789] || ${4-} == [123456789][0123456789] ]] && (( $4 <= ${#FV_DRAW_PAL} )); then
            fv.video.writeChar "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "${FV_DRAW_PAL:$4-1:1}" "${5:-1}"
            return
        fi
    fi
    if (( $# != 4 && $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" writeChar || return
    fv.views._wcol "$4" writeChar || return
    fv.video.writeChar "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c" "${5:-1}"
}
# fv.views.writeCStr X Y TEXT C1 C2 — FV MoveCStr + WriteLine: each `~`
# switches between the palette entries C1 and C2 (FV's Word Lo / Hi)
fv.views.writeCStr() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c __fvw_c1
    fv.views._wxy "$1" "$2" writeCStr || return
    fv.views._wcol "$4" writeCStr || return
    __fvw_c1=$__fvw_c
    fv.views._wcol "$5" writeCStr || return
    fv.video.writeCStr "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c1" "$__fvw_c"
}
# fv.views.writeLine X Y H TEXT ATTRS — FV WriteLine(X, Y, W, H, Buf): the row
# TEXT with the RESOLVED symbols ATTRS (one per display cell, as FV's
# TDrawBuffer holds resolved attributes: build them with getColor /
# FV_DRAW_PAL) on the H rows Y .. Y+H-1 (fv.video.writeBuf's repeat count)
fv.views.writeLine() {
    if (( $# == 5 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        fv.video.writeBuf "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$4" "$5" "$3"
        return
    fi
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y
    fv.views._wxy "$1" "$2" writeLine || return
    fv.video.writeBuf "$__fvw_x" "$__fvw_y" "$4" "$5" "$3"
}
# fv.views.fill X Y W H CH COLOR — the rectangle filled with CH's first
# cluster in palette entry COLOR (FV MoveChar + WriteLine with H rows)
fv.views.fill() {
    if (( $# == 6 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${6-} == [123456789] || ${6-} == [123456789][0123456789] ]] && (( $6 <= ${#FV_DRAW_PAL} )); then
            fv.video.fillRect "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "$4" "${FV_DRAW_PAL:$6-1:1}" "$5"
            return
        fi
    fi
    if (( $# != 6 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" fill || return
    fv.views._wcol "$6" fill || return
    fv.video.fillRect "$__fvw_x" "$__fvw_y" "$3" "$4" "$__fvw_c" "$5"
}

# ---- the built-in Draw / GetPalette bodies -----------------------------------------
# A Draw body draws only as the painter's current view (FV_DRAW_VIEW = V):
# calling V.Draw outside the painter draws nothing (draw with drawView).

# TView.Draw — FV: blanks in colour 1 over the whole view (one fill)
fv.views._viewDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_c=${FV_DRAW_PAL:0:1}
    fv.video.fillRect "$FV_DRAW_X" "$FV_DRAW_Y" "${__fvw_d[SizeX]:-0}" "${__fvw_d[SizeY]:-0}" "${__fvw_c:-$__FV_VW_ERRSYM}" ' ' || :
}

# TGroup.Draw [NOCLIP] — FV DrawSubViews(First, nil): the visible subviews
# back to front, each painted clipped to the current paint rectangle,
# skipping one whose part in it a covering front sibling holds entirely;
# after a subview with sfShadow its shadow. NOCLIP 1 (from fv.views._paint):
# leave the fv.video clip to the caller; else put the group's back when a
# subview changed it (a Draw override of yours may write after `inherited`)
fv.views._groupDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_l=${1}_views
    local __fvw_n=${#__fvw_l[@]} __fvw_i __fvw_j __fvw_k __fvw_q __fvw_t=0 __fvw_cv
    local __fvw_p1=$__FV_VW_P1 __fvw_p2=$__FV_VW_P2 __fvw_p3=$__FV_VW_P3 __fvw_p4=$__FV_VW_P4 __fvw_g=$__FV_VW_INGRP
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4
    __FV_VW_INGRP=1
    for (( __fvw_i = 0; __fvw_i < __fvw_n; __fvw_i++ )); do
        __fvw_k=${__fvw_l[__fvw_i]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
        __fvw_1=${__FV_VW_C1[$__fvw_k]} __fvw_2=${__FV_VW_C2[$__fvw_k]} __fvw_3=${__FV_VW_C3[$__fvw_k]} __fvw_4=${__FV_VW_C4[$__fvw_k]}
        if (( __fvw_p1 > __fvw_1 )); then __fvw_1=$__fvw_p1; fi
        if (( __fvw_p2 > __fvw_2 )); then __fvw_2=$__fvw_p2; fi
        if (( __fvw_p3 < __fvw_3 )); then __fvw_3=$__fvw_p3; fi
        if (( __fvw_p4 < __fvw_4 )); then __fvw_4=$__fvw_p4; fi
        if (( __fvw_1 < __fvw_3 && __fvw_2 < __fvw_4 )); then
            __fvw_cv=0
            for (( __fvw_j = __fvw_i + 1; __fvw_j < __fvw_n; __fvw_j++ )); do
                __fvw_q=${__fvw_l[__fvw_j]}
                if (( __FV_VW_C1[$__fvw_q] > __fvw_1 || __FV_VW_C2[$__fvw_q] > __fvw_2 )); then continue; fi
                if (( __FV_VW_C3[$__fvw_q] < __fvw_3 || __FV_VW_C4[$__fvw_q] < __fvw_4 )); then continue; fi
                local -n __fvw_qd=${__fvw_q}_data
                if (( ! (${__fvw_qd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
                if fv.views._covers "$__fvw_q"; then __fvw_cv=1; break; fi
            done
            if (( ! __fvw_cv )); then fv.views._paint "$__fvw_k" "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; __fvw_t=1; fi
        fi
        if (( ${__fvw_kd[State]:-0} & FV_SF_SHADOW )); then
            if fv.views._shade "$__fvw_k" "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; then __fvw_t=1; fi
        fi
    done
    __FV_VW_INGRP=$__fvw_g
    if (( __fvw_t )) && [[ ${2-} != 1 ]]; then fv.video.setClip "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4" || :; fi
    return 0
}

# TView.GetPalette (func) — FV: nil, '' (the view maps as its owner does)
fv.views._viewGetPalette() { RESULT=''; }
# TFrame.GetPalette (func) — FV CFrame: passive frame, passive title, active
# frame, active title, icons
fv.views._frameGetPalette() { RESULT='1 1 2 2 3'; }

# ---- TFrame (design §1.5; FV TFrame.Draw, FrameLine) -----------------------------
fv.views._frameCreate() {   # F
    local -n __fvw_d=${1}_data
    __fvw_d[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    __fvw_d[EventMask]=$(( ${__fvw_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __fvw_d[FrameMode]=0
    __FV_VW_FRM[$1]=1
}

# fv.views._frameTitle O L — the caller's __fvw_ti = the owner's title as
# asked for at most L characters (FV: GetTitle(L), a func of TWindow from
# stage 2c-3, through the elision when O's class has one; else the owner's
# Title field). Not cut here: fv.views._titleFit cuts it on a cache miss
fv.views._frameTitle() {
    local __fvw_c=${1}_class __fvw_r=${RESULT-}
    __fvw_c="${!__fvw_c-}_class_method_owner[GetTitle]"
    if [[ -n ${!__fvw_c-} ]]; then
        RESULT=''
        fv.views._virt "$1" GetTitle "$2" || RESULT=''
        __fvw_ti=${RESULT-}
        RESULT=$__fvw_r
    else
        local -n __fvw_od=${1}_data
        __fvw_ti=${__fvw_od[Title]-}
    fi
}

# fv.views._titleFit L — the caller's __fvw_ti cut to at most L characters
# (TWindow.GetTitle's Copy) and then to at most L cells; __fvw_tw = its width.
# Runs through fv.video._g (fv.video's locale guard): a caller in a non-UTF-8
# locale would otherwise cut a UTF-8 title by bytes
fv.views._titleFit() {
    if (( $1 <= 0 )); then __fvw_ti='' __fvw_tw=0; return 0; fi
    if (( ${#__fvw_ti} > $1 )); then __fvw_ti=${__fvw_ti:0:$1}; fi
    fv.video.strWidth "$__fvw_ti" || RESULT=${#__fvw_ti}
    __fvw_tw=$RESULT
    while (( __fvw_tw > $1 )) && [[ -n $__fvw_ti ]]; do
        __fvw_ti=${__fvw_ti%?}
        fv.video.strWidth "$__fvw_ti" || RESULT=${#__fvw_ti}
        __fvw_tw=$RESULT
    done
}

# fv.views._frameRows F — the frame's row strings for its state, size,
# owner fields and palette, cached per frame and state slot (active x
# dragging; the caller's __fvw_fc = "F.SLOT" names it, __FV_VW_FK[F.SLOT]
# the key of what it holds): FT/FTA top, FM/FMA body, FB/FBA bottom (text /
# symbols), FS/FSA the side column.
# FV TFrame.Draw: by state (sfDragging: single line, everything in colour 5;
# not sfActive: single, frame 1, title 2; active: double, frame 3, icons 5,
# title 4); the number (1..9) at W-3 (W-7 with wfZoom); the title centred,
# a blank either side, in the title colour; while active `[■]` at 2
# (wfClose; `☼` while FrameMode has fmCloseClicked), `[↑]` at W-5 (wfZoom;
# `↕` when the owner is at its SizeLimits maximum, `☼` with fmZoomClicked),
# the grow corner `─┘` at W-2 in colour 5 (wfGrow). FV's junctions with
# ofFramed subviews are not drawn (deviation). The title is cut so that it
# never reaches an icon (FV caps it at W-10 only after asking for L).
fv.views._frameRows() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_w=${__fvw_d[SizeX]:-0} __fvw_st=${__fvw_d[State]:-0} __fvw_fm=${__fvw_d[FrameMode]:-0}
    local __fvw_fl=0 __fvw_nm=0 __fvw_ti='' __fvw_z=0 __fvw_lo __fvw_hi __fvw_tc __fvw_f __fvw_a __fvw_L __fvw_key
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    local __fvw_p=${__FV_VW_PAL[$1]}
    if (( __fvw_st & FV_SF_DRAGGING )); then __fvw_lo=5 __fvw_hi=5 __fvw_tc=5 __fvw_f=0
    elif (( ! (__fvw_st & FV_SF_ACTIVE) )); then __fvw_lo=1 __fvw_hi=1 __fvw_tc=2 __fvw_f=0
    else __fvw_lo=3 __fvw_hi=5 __fvw_tc=4 __fvw_f=9; fi
    __fvw_a=$(( (__fvw_st & FV_SF_ACTIVE) ? 1 : 0 ))
    if [[ -n $__fvw_o ]]; then
        local -n __fvw_od=${__fvw_o}_data
        __fvw_fl=${__fvw_od[Flags]:-0} __fvw_nm=${__fvw_od[Number]:-0}
        if [[ $__fvw_fl == *[!0123456789]* || ${#__fvw_fl} -gt 9 ]]; then __fvw_fl=0; else __fvw_fl=$(( 10#$__fvw_fl )); fi
        if ! [[ $__fvw_nm == [123456789] ]]; then __fvw_nm=0; fi
    fi
    __fvw_L=$(( __fvw_w - 10 ))
    if (( __fvw_fl & (FV_WF_CLOSE | FV_WF_ZOOM) )); then __fvw_L=$(( __fvw_L - 6 )); fi
    if (( __fvw_nm )); then __fvw_L=$(( __fvw_L - 4 )); fi
    if [[ -n $__fvw_o ]]; then fv.views._frameTitle "$__fvw_o" "$__fvw_L"; fi
    if (( __fvw_a && (__fvw_fl & FV_WF_ZOOM) )) && [[ -n $__fvw_o ]]; then
        local __fvw_m1=$FV_MIN_X __fvw_m2=$FV_MIN_Y __fvw_m3=$FV_MAX_X __fvw_m4=$FV_MAX_Y
        fv.views._virt "$__fvw_o" SizeLimits || :
        if (( ${__fvw_od[SizeX]:-0} == FV_MAX_X && ${__fvw_od[SizeY]:-0} == FV_MAX_Y )); then __fvw_z=1; fi
        FV_MIN_X=$__fvw_m1 FV_MIN_Y=$__fvw_m2 FV_MAX_X=$__fvw_m3 FV_MAX_Y=$__fvw_m4
    fi
    # one cache slot per state (active x dragging), so a focus change back and
    # forth finds both looks built: the caller's __fvw_fc = "F.SLOT"
    __fvw_fc="$1.$(( (__fvw_st & FV_SF_DRAGGING ? 2 : 0) + __fvw_a ))"
    __fvw_key="$__fvw_f.$__fvw_lo$__fvw_hi$__fvw_tc.$__fvw_a.$__fvw_w.$__fvw_fl.$__fvw_nm.$__fvw_fm.$__fvw_z.${FV_VIDEO_ASCII:-0}.$__fvw_p|$__fvw_ti"
    if [ "${__FV_VW_FK[$__fvw_fc]-}" = "$__fvw_key" ]; then return 0; fi
    # (a cache miss: build the rows)
    local __fvw_cl=${__fvw_p:__fvw_lo-1:1} __fvw_ch=${__fvw_p:__fvw_hi-1:1} __fvw_ct=${__fvw_p:__fvw_tc-1:1}
    __fvw_cl=${__fvw_cl:-$__FV_VW_ERRSYM} __fvw_ch=${__fvw_ch:-$__FV_VW_ERRSYM} __fvw_ct=${__fvw_ct:-$__FV_VW_ERRSYM}
    local __fvw_tl __fvw_hz __fvw_tr __fvw_vl __fvw_bl __fvw_br __fvw_s __fvw_r __fvw_i __fvw_n
    if (( __fvw_f )); then __fvw_tl='╔' __fvw_hz='═' __fvw_tr='╗' __fvw_vl='║' __fvw_bl='╚' __fvw_br='╝'
    else __fvw_tl='┌' __fvw_hz='─' __fvw_tr='┐' __fvw_vl='│' __fvw_bl='└' __fvw_br='┘'; fi
    if (( __fvw_w < 1 )); then
        __FV_VW_FT[$__fvw_fc]='' __FV_VW_FTA[$__fvw_fc]='' __FV_VW_FM[$__fvw_fc]='' __FV_VW_FMA[$__fvw_fc]='' __FV_VW_FB[$__fvw_fc]='' __FV_VW_FBA[$__fvw_fc]=''
        __FV_VW_FS[$__fvw_fc]=$__fvw_vl __FV_VW_FSA[$__fvw_fc]=$__fvw_cl __FV_VW_FK[$__fvw_fc]=$__fvw_key
        return 0
    fi
    __fvw_n=$(( __fvw_w > 2 ? __fvw_w - 2 : 0 ))
    # the cells as array elements (box characters are several bytes: no
    # substring offsets on them, whatever the caller's locale)
    local -a __fvw_tc_=() __fvw_bc=()
    printf -v __fvw_r '%*s' "$__fvw_n" ''
    __fvw_s=${__fvw_r// /"$__fvw_hz "}
    local IFS=' '
    # (unquoted on purpose: box characters and blanks only, no glob character; split on the blanks)
    __fvw_tc_=($__fvw_tl $__fvw_s $__fvw_tr) __fvw_bc=($__fvw_bl $__fvw_s $__fvw_br)
    if (( __fvw_w == 1 )); then __fvw_tc_=("$__fvw_tr") __fvw_bc=("$__fvw_br"); fi
    printf -v __fvw_s '%*s' "$__fvw_w" ''
    local __fvw_ta=${__fvw_s// /$__fvw_cl} __fvw_ba=${__fvw_s// /$__fvw_cl}
    # the number (its cell keeps the frame colour)
    if (( __fvw_nm )); then
        if (( __fvw_fl & FV_WF_ZOOM )); then __fvw_i=$(( __fvw_w - 7 )); else __fvw_i=$(( __fvw_w - 3 )); fi
        if (( __fvw_i >= 0 )); then __fvw_tc_[__fvw_i]=$__fvw_nm; fi
    fi
    # the title block: blank, title, blank in the title colour
    if [[ -n $__fvw_ti ]]; then
        # (cut to L, its width in cells as a write stores it: wide characters, marks)
        local __fvw_tw=0
        fv.video._g fv.views._titleFit "$__fvw_L" || :
        if (( __fvw_tw > 0 )); then
            __fvw_i=$(( (__fvw_w - __fvw_tw) >> 1 ))
            __fvw_tc_[__fvw_i-1]=' ' __fvw_tc_[__fvw_i]=$__fvw_ti __fvw_tc_[__fvw_i+__fvw_tw]=' '
            for (( __fvw_n = __fvw_i + 1; __fvw_n < __fvw_i + __fvw_tw; __fvw_n++ )); do __fvw_tc_[__fvw_n]=''; done
            printf -v __fvw_s '%*s' "$(( __fvw_tw + 2 ))" ''
            __fvw_ta=${__fvw_ta:0:__fvw_i-1}${__fvw_s// /$__fvw_ct}${__fvw_ta:__fvw_i+__fvw_tw+1}
        fi
    fi
    # the icons, while active
    if (( __fvw_a )); then
        if (( (__fvw_fl & FV_WF_CLOSE) && __fvw_w > 4 )); then
            __fvw_tc_[2]='[' __fvw_tc_[4]=']'
            if (( __fvw_fm & FV_FM_CLOSECLICKED )); then __fvw_tc_[3]='☼'; else __fvw_tc_[3]='■'; fi
            __fvw_ta=${__fvw_ta:0:2}$__fvw_cl$__fvw_ch$__fvw_cl${__fvw_ta:5}
        fi
        if (( (__fvw_fl & FV_WF_ZOOM) && __fvw_w >= 5 )); then
            __fvw_i=$(( __fvw_w - 5 ))
            __fvw_tc_[__fvw_i]='[' __fvw_tc_[__fvw_i+1]='↑' __fvw_tc_[__fvw_i+2]=']'
            if (( __fvw_fm & FV_FM_ZOOMCLICKED )); then __fvw_tc_[__fvw_i+1]='☼'; elif (( __fvw_z )); then __fvw_tc_[__fvw_i+1]='↕'; fi
            __fvw_ta=${__fvw_ta:0:__fvw_i}$__fvw_cl$__fvw_ch$__fvw_cl${__fvw_ta:__fvw_i+3}
        fi
        if (( (__fvw_fl & FV_WF_GROW) && __fvw_w >= 2 )); then
            __fvw_bc[__fvw_w-2]='─' __fvw_bc[__fvw_w-1]='┘'
            __fvw_ba=${__fvw_ba:0:__fvw_w-2}$__fvw_ch$__fvw_ch
        fi
    fi
    IFS=''
    printf -v "__FV_VW_FT[$__fvw_fc]" '%s' "${__fvw_tc_[@]}"
    printf -v "__FV_VW_FB[$__fvw_fc]" '%s' "${__fvw_bc[@]}"
    printf -v __fvw_s '%*s' "$(( __fvw_w > 2 ? __fvw_w - 2 : 0 ))" ''
    if (( __fvw_w == 1 )); then __FV_VW_FM[$__fvw_fc]=$__fvw_vl; else __FV_VW_FM[$__fvw_fc]=$__fvw_vl$__fvw_s$__fvw_vl; fi
    __FV_VW_FTA[$__fvw_fc]=$__fvw_ta __FV_VW_FBA[$__fvw_fc]=$__fvw_ba __FV_VW_FMA[$__fvw_fc]=${__fvw_ba//?/$__fvw_cl}
    __FV_VW_FS[$__fvw_fc]=$__fvw_vl __FV_VW_FSA[$__fvw_fc]=$__fvw_cl __FV_VW_FK[$__fvw_fc]=$__fvw_key
}

# TFrame.Draw — FV: the top row, the body row on the H-2 rows between, the
# bottom row: three writes (fv.video.writeBuf, the body with its repeat count)
fv.views._frameDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_h=${__fvw_d[SizeY]:-0} __fvw_fc
    if (( ${__fvw_d[SizeX]:-0} < 1 )); then return 0; fi
    fv.views._frameRows "$1"
    fv.video.writeBuf "$FV_DRAW_X" "$FV_DRAW_Y" "${__FV_VW_FT[$__fvw_fc]}" "${__FV_VW_FTA[$__fvw_fc]}" || :
    if (( __fvw_h > 2 )); then
        fv.video.writeBuf "$FV_DRAW_X" "$(( FV_DRAW_Y + 1 ))" "${__FV_VW_FM[$__fvw_fc]}" "${__FV_VW_FMA[$__fvw_fc]}" "$(( __fvw_h - 2 ))" || :
    fi
    fv.video.writeBuf "$FV_DRAW_X" "$(( FV_DRAW_Y + __fvw_h - 1 ))" "${__FV_VW_FB[$__fvw_fc]}" "${__FV_VW_FBA[$__fvw_fc]}" || :
}

# fv.views._frameBorder F — the BORDER-ONLY redraw (stage 2c-3 calls it when
# sfActive or sfDragging changes; design §1.5): the top and bottom rows and
# the two side columns, then the views in front over what was written
# (scroll bars on the ring, shadows), flush. The interior is not touched.
# The parts of the ring that a covering view in front of the frame (or of an
# owner) holds are left out first (fv.views._uncover), so a window in front
# is neither overwritten nor painted again: 4 writes for an uncovered ring,
# one more per extra piece of a ring cut by a window in front. A frame whose
# class overrides Draw is drawn whole (drawView: its Draw runs).
fv.views._frameBorder() {
    local __fvw_o=${1}_class __fvw_r=${RESULT-}
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    if ! [ "${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}" = fv.views._frameDraw ]; then fv.views._drawView "$1"; RESULT=$__fvw_r; return 0; fi
    fv.views._drawable "$1" || return 0
    local -n __fvw_d=${1}_data
    local __fvw_x=${__FV_VW_AX[$1]} __fvw_y=${__FV_VW_AY[$1]} __fvw_w=${__fvw_d[SizeX]:-0} __fvw_h=${__fvw_d[SizeY]:-0}
    if (( __fvw_w < 1 || __fvw_h < 1 )); then return 0; fi
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_j __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_c=0
    # the ring as pieces (X1 Y1 X2 Y2) with a tag: t top, b bottom, s side
    local -a __fvw_rs=() __fvw_tg=() __fvw_q=(
        "$__fvw_x" "$__fvw_y" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + 1 ))"
        "$__fvw_x" "$(( __fvw_y + __fvw_h - 1 ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h ))")
    local -a __fvw_qt=(t b)
    if (( __fvw_h > 2 )); then
        __fvw_q+=("$__fvw_x" "$(( __fvw_y + 1 ))" "$(( __fvw_x + 1 ))" "$(( __fvw_y + __fvw_h - 1 ))")
        __fvw_qt+=(s)
        if (( __fvw_w > 1 )); then
            __fvw_q+=("$(( __fvw_x + __fvw_w - 1 ))" "$(( __fvw_y + 1 ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h - 1 ))")
            __fvw_qt+=(s)
        fi
    fi
    # each clipped to the frame's clip
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_q[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_q[__fvw_j]} __fvw_2=${__fvw_q[__fvw_j+1]} __fvw_3=${__fvw_q[__fvw_j+2]} __fvw_4=${__fvw_q[__fvw_j+3]}
        if (( __fvw_1 < __FV_VW_C1[$1] )); then __fvw_1=${__FV_VW_C1[$1]}; fi
        if (( __fvw_2 < __FV_VW_C2[$1] )); then __fvw_2=${__FV_VW_C2[$1]}; fi
        if (( __fvw_3 > __FV_VW_C3[$1] )); then __fvw_3=${__FV_VW_C3[$1]}; fi
        if (( __fvw_4 > __FV_VW_C4[$1] )); then __fvw_4=${__FV_VW_C4[$1]}; fi
        if (( __fvw_1 < __fvw_3 && __fvw_2 < __fvw_4 )); then
            __fvw_rs+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_tg+=("${__fvw_qt[__fvw_j/4]}")
        fi
    done
    fv.views._uncover "$1"
    if (( ! ${#__fvw_rs[@]} )); then RESULT=$__fvw_r; return 0; fi
    fv.views._begin
    local __fvw_fc
    fv.views._frameRows "$1"
    # the side pieces under the frame's clip, then each row piece under its own
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if ! [ "${__fvw_tg[__fvw_j/4]}" = s ]; then continue; fi
        if (( ! __fvw_c )); then
            fv.video.setClip "${__FV_VW_C1[$1]}" "${__FV_VW_C2[$1]}" "${__FV_VW_C3[$1]}" "${__FV_VW_C4[$1]}" || :
            __fvw_c=1
        fi
        fv.video.fillRect "${__fvw_rs[__fvw_j]}" "${__fvw_rs[__fvw_j+1]}" 1 "$(( __fvw_rs[__fvw_j+3] - __fvw_rs[__fvw_j+1] ))" \
            "${__FV_VW_FSA[$__fvw_fc]}" "${__FV_VW_FS[$__fvw_fc]}" || :
    done
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if [ "${__fvw_tg[__fvw_j/4]}" = s ]; then continue; fi
        fv.video.setClip "${__fvw_rs[@]:__fvw_j:4}" || :
        if [ "${__fvw_tg[__fvw_j/4]}" = t ]; then
            fv.video.writeBuf "$__fvw_x" "$__fvw_y" "${__FV_VW_FT[$__fvw_fc]}" "${__FV_VW_FTA[$__fvw_fc]}" || :
        else
            fv.video.writeBuf "$__fvw_x" "$(( __fvw_y + __fvw_h - 1 ))" "${__FV_VW_FB[$__fvw_fc]}" "${__FV_VW_FBA[$__fvw_fc]}" || :
        fi
    done
    # the views in front over what was written (one pass over all pieces: a
    # non-covering view meeting several pieces is painted once per piece)
    fv.views._bands
    fv.views._over "$1"
    fv.views._wideMark
    fv.views._end
    fv.views._flush
    RESULT=$__fvw_r
}

# fv.views._uncover V — remove from the caller's pieces (__fvw_rs, one cell
# thick, tags in __fvw_tg) what a COVERING visible view in front of V or of
# one of V's owners holds (its clip): such a view hides them entirely (FV
# relies on z-clipping there). A row piece keeps its parts left and right of
# the view, a column piece those above and below
fv.views._uncover() {
    local __fvw_v=$1 __fvw_o __fvw_i=-1 __fvw_n __fvw_k __fvw_j __fvw_hit
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_e1 __fvw_e2 __fvw_e3 __fvw_e4 __fvw_t
    local -a __fvw_nr __fvw_nt
    while (( ${#__fvw_rs[@]} )); do
        local -n __fvw_vd=${__fvw_v}_data
        __fvw_o=${__fvw_vd[Owner]-}
        if [[ -z $__fvw_o ]]; then return 0; fi
        local -n __fvw_ol=${__fvw_o}_views
        __fvw_n=${#__fvw_ol[@]}
        fv.views._idx "$__fvw_o" "$__fvw_v"
        for (( __fvw_i = __fvw_i + 1; __fvw_i < __fvw_n && ${#__fvw_rs[@]}; __fvw_i++ )); do
            __fvw_k=${__fvw_ol[__fvw_i]}
            __fvw_e1=${__FV_VW_C1[$__fvw_k]} __fvw_e2=${__FV_VW_C2[$__fvw_k]} __fvw_e3=${__FV_VW_C3[$__fvw_k]} __fvw_e4=${__FV_VW_C4[$__fvw_k]}
            __fvw_hit=0
            for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
                if (( __fvw_rs[__fvw_j] < __fvw_e3 && __fvw_e1 < __fvw_rs[__fvw_j+2] )); then
                    if (( __fvw_rs[__fvw_j+1] < __fvw_e4 && __fvw_e2 < __fvw_rs[__fvw_j+3] )); then __fvw_hit=1; break; fi
                fi
            done
            if (( ! __fvw_hit )); then continue; fi
            local -n __fvw_kd=${__fvw_k}_data
            if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
            if ! fv.views._covers "$__fvw_k"; then continue; fi
            __fvw_nr=() __fvw_nt=()
            for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
                __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
                __fvw_t=${__fvw_tg[__fvw_j/4]}
                if (( __fvw_1 >= __fvw_e3 || __fvw_e1 >= __fvw_3 || __fvw_2 >= __fvw_e4 || __fvw_e2 >= __fvw_4 )); then
                    __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t")
                elif (( __fvw_4 - __fvw_2 == 1 )); then
                    if (( __fvw_1 < __fvw_e1 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_e1" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
                    if (( __fvw_e3 < __fvw_3 )); then __fvw_nr+=("$__fvw_e3" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
                else
                    if (( __fvw_2 < __fvw_e2 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_e2") __fvw_nt+=("$__fvw_t"); fi
                    if (( __fvw_e4 < __fvw_4 )); then __fvw_nr+=("$__fvw_1" "$__fvw_e4" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
                fi
            done
            __fvw_rs=("${__fvw_nr[@]}") __fvw_tg=("${__fvw_nt[@]}")
        done
        __fvw_v=$__fvw_o
    done
    return 0
}
