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
# P2 stage 2c-1 (this file so far): constants, TView / TGroup, the tree
# (insert, insertBefore, delete, makeFirst, putInFrontOf, first / last /
# next / prev / nextView / prevView), the bounds cache, GrowMode,
# locate / moveTo / growTo / changeBounds, makeLocal / makeGlobal /
# mouseInView, the elision (fv.views._virt) with its RESULT rule, reserved
# names and the constructor guard. Drawing (2c-2) and events, focus and modal
# views (2c-3) build on two hooks left here: fv.views._changed (the redraw
# hook) and fv.views._setCurrent (the focus hook).
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
# The elision tables (design §1.4): IMPL = the plain body of each built-in
# virtual, keyed DEFININGCLASS.METHOD; FUNC = the virtuals FV declares as
# functions (they answer in RESULT on both paths; the others leave it).
declare -gA __FV_VW_IMPL=(
    [TView.ChangeBounds]=fv.views._viewChangeBounds [TView.CalcBounds]=fv.views._viewCalcBounds
    [TView.SizeLimits]=fv.views._viewSizeLimits [TView.GetHelpCtx]=fv.views._viewGetHelpCtx
    [TGroup.ChangeBounds]=fv.views._groupChangeBounds [TGroup.GetHelpCtx]=fv.views._groupGetHelpCtx
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
        proc MakeFirst
        proc PutInFrontOf
        proc Locate
        proc MoveTo
        proc GrowTo
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
        proc Insert
        proc InsertBefore
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
build TGroup

# ---- the hooks for the later stages -----------------------------------------
# fv.views._changed WHY V G AX1 AY1 AX2 AY2 — the REDRAW HOOK, a no-op until
# P2 stage 2c-2 fills it. Called after the tree or a view's place changed:
# G is V's owner ('' for a view without one; for `delete` the group V was
# removed from) and the rectangle (absolute, B exclusive, not clipped, no
# shadow) the screen area concerned. WHY:
#   insert  fv.views.insert / insertBefore: V's rect (FV InsertBefore -> Show)
#   delete  fv.views.delete, V.delete, the constructor guard's repair: V's
#           rect before the removal (FV Hide -> DrawHide)
#   order   putInFrontOf / makeFirst of a visible V: V's rect
#   bounds  TView / TGroup ChangeBounds: V's old rect ∪ its new rect (FV
#           ChangeBounds -> DrawView / Redraw); a group with a size change
#           calls it once, after its subviews' own `bounds` calls
#   move    locate / moveTo / growTo, after ChangeBounds: old ∪ new (FV
#           Locate -> DrawUnderRect)
fv.views._changed() { :; }

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
    unset '__FV_VW_LIVE[$1]' '__FV_VW_AX[$1]' '__FV_VW_AY[$1]' \
        '__FV_VW_C1[$1]' '__FV_VW_C2[$1]' '__FV_VW_C3[$1]' '__FV_VW_C4[$1]'
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
        fv.views._changed order "$1" "$__fvw_g" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
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
    fv.views._virt "$1" ChangeBounds "$__fvw_ax" "$__fvw_ay" "$(( __fvw_ax + __fvw_w ))" "$(( __fvw_ay + __fvw_h ))" || return
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
        local -a __fvw_kids=("${__fvw_l[@]}")
        for (( __fvw_i = ${#__fvw_kids[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
            __fvw_k=${__fvw_kids[__fvw_i]}
            fv.views._kid "$1" "$__fvw_k" || continue
            local -n __fvw_kd=${__fvw_k}_data
            FV_RECT_AX=${__fvw_kd[OriginX]:-0} FV_RECT_AY=${__fvw_kd[OriginY]:-0}
            FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_kd[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_kd[SizeY]:-0} ))
            fv.views._virt "$__fvw_k" CalcBounds "$__fvw_dx" "$__fvw_dy"
            fv.views._kid "$1" "$__fvw_k" || continue
            fv.views._virt "$__fvw_k" ChangeBounds "$FV_RECT_AX" "$FV_RECT_AY" "$FV_RECT_BX" "$FV_RECT_BY"
        done
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
