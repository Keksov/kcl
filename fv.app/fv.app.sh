#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.app.sh}../../kbool.sh" || return
kk.unit fv.app || return $__kk_unit_rc

# fv.app — Free Vision's app unit for the fv.* text UI (layer L2): P2 stage
# 2f brings TBackground, TDesktop, TProgram and TApplication (FV app.inc) as
# kklass classes on top of fv.views (TView / TGroup) and fv.menus
# (TStatusLine): the application object, its event source (FV
# TProgram.GetEvent with the resize handled at once and Idle), Run, the
# desktop with Tile / Cascade / cmNext / cmPrev, the app palette.
# Design: kcl/docs/dev/fv/P2_DESIGN.md (§1.1-§1.3, §1.9, §2); API and
# deviations: README.md.
#
# Conventions (as fv.views'): locals `__fva_*`; fields of other instances
# read and written through `${v}_data` (kklass friend contract, decision
# D19), reads as `${d[F]-}`; fork-free and set -eu clean; no `[[ == ]]` /
# `case` / `${x//}` between two names or symbols (nocasematch); procedures
# leave RESULT as it was, getters answer in it; a refused call is rc 2 with
# RESULT='' and a kk.debug line; the loud refusals (a second application) one
# `Error:` line.
#
# Every built-in virtual has its body in a plain function registered in
# fv.views' elision table __FV_VW_IMPL, so the framework runs it without a
# kklass dispatch unless a class of yours overrides it.
#
# Friend uses of fv.views' private parts (the same framework; README
# "Contract and deviations"): reads of __FV_VW_LIVE, __FV_VW_CRC,
# __FV_VW_GRP; the hooks __FV_VW_GETEVENT / __FV_VW_PUTEVENT / __FV_VW_OWNER /
# __FV_VW_EOF (set at Init, put back at Done), __FV_VW_RESIZES (counted per
# resize handled at once), __FV_VW_NODRAW (bulk layout), __FV_VW_APAL /
# __FV_VW_ERRSYM (the app palette); entries added to __FV_VW_IMPL and
# __FV_VW_QGRP; calls of fv.views._virt, _message, _groupEvent,
# _newReserved, _showNow. Of fv.drivers: __FV_DR_PEND. Of fv.video: reads of
# __FV_VS_PAL (a symbol's colours), __FV_VS_DOS (FV's colour order), __FV_VS_H,
# __FV_VS_SHADOW.

kk.uses kklass_pascal fv.views fv.menus fv.drivers || return

# ---- state ------------------------------------------------------------------
# FV's globals Application, Desktop, StatusLine, MenuBar: instance names ('' =
# nil), set by the application's Init, cleared by its Done.
#   FV_APP_HEADLESS  input: 1 = TApplication.new makes no terminal (no
#                    initVideo / initEvents): the size comes from
#                    FV_SCREEN_W / _H, frames go to FV_VIDEO_OUT_FD, events
#                    are read from FV_KEY_FD (tests, the bench)
# Private:
#   OWNER    the process that made the application (BASHPID): Run refuses to
#            run anywhere else (inside $( ), a pipeline)
#   VIDEO    1 when this application's Init turned the terminal on (its Done
#            turns it off again; a terminal the caller turned on stays on)
#   EVENTS   1 when this application's Init turned the event driver on
#            (fv.drivers.initEvents; its Done calls doneEvents, whoever turned
#            the terminal on)
#   SHOWN    1 once the application had its first paint (Run, or the first
#            GetEvent of a modal view executed before Run)
#   ININIT   1 while TProgram.Init runs its InitStatusLine / InitMenuBar /
#            InitDesktop (fv.menus.menuBar then leaves the insert to Init)
#   SGET SPUT SOWN SEOF
#            fv.views' event hooks, the owner and the end-of-input latch as
#            they were before Init (Done puts them back)
#   SAVED    symbol -> its fv.video colours before setAppPalette first
#            redefined it ('' = undefined then): Done puts them back
#   DEFPAL   FV's CAppColor as fv.video symbols (fv.views' default
#            __FV_VW_APAL; Init and Done put the app palette back to it)
#   POOL     the symbols the app palette may allocate (fv.video's 62 minus
#            the default symbol 0 and the shadow symbol V)
# (the four globals keep a caller's value: the settings hook, kkore kk.settings)
fv.app._settings() {
    declare -g FV_APP=${FV_APP-} FV_DESKTOP=${FV_DESKTOP-} FV_STATUSLINE=${FV_STATUSLINE-} FV_MENUBAR=${FV_MENUBAR-}
    return 0
}
kk.settings fv.app._settings FV_APP FV_DESKTOP FV_STATUSLINE FV_MENUBAR || return
declare -g __FV_AP_OWNER=${__FV_AP_OWNER-} __FV_AP_VIDEO=${__FV_AP_VIDEO:-0} __FV_AP_EVENTS=${__FV_AP_EVENTS:-0} __FV_AP_SHOWN=${__FV_AP_SHOWN:-0}
declare -g __FV_AP_ININIT=0
declare -g __FV_AP_SGET=${__FV_AP_SGET-} __FV_AP_SPUT=${__FV_AP_SPUT-} __FV_AP_SOWN=${__FV_AP_SOWN-} __FV_AP_SEOF=${__FV_AP_SEOF:-0}
declare -gA __FV_AP_SAVED
declare -g __FV_AP_DEFPAL=123456789ABBC19DEFGGHIE2JKGG2JL2JKGG22JL5MN3O2PEH9NA5QBBPNHBGRB89A11C89C5MN3OSPEH2NK5TBBPNHBGRBDEFGGHPEH5MN3OP2JL9NA5UB12NL1GR1
declare -g __FV_AP_POOL=123456789ABCDEFGHIJKLMNOPQRSTUWXYZabcdefghijklmnopqrstuvwxyz

# ---- the classes (FV app.inc) ---------------------------------------------------

# TBackground.new NAME AX AY BX BY [PATTERN] — FV TBackground.Init(Bounds,
# APattern): TView's, GrowMode gfGrowHiX + gfGrowHiY, Pattern (default '░',
# FV's #$2591). Draw: one fill of its rect with Pattern in colour 1
# (CBackground #1); in ASCII mode a non-ASCII pattern is drawn as '#'.
class TBackground : TView
    public
        var Pattern
        constructor Create
        nofields override proc Draw
        nofields override func GetPalette
end
TBackground.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.app._bgCreate "$this" "${5-░}"
}
TBackground.Draw() { fv.app._bgDraw "$this" || return; }
TBackground.GetPalette() { fv.app._bgGetPalette "$this" || return; }
build TBackground

# TDesktop.new NAME AX AY BX BY — FV TDesktop.Init: TGroup's, GrowMode
# gfGrowHiX + gfGrowHiY, the background from InitBackground (virtual; the
# built-in makes the TBackground NAME__fvbg over the whole desktop) inserted.
# HandleEvent: cmNext / cmPrev. Tile / Cascade (aliases of fv.app.tile /
# fv.app.cascade with a rect), TileError (virtual; the built-in does nothing).
class TDesktop : TGroup
    public
        var Background
        var TileColumnsFirst
        constructor Create
        nofields override proc HandleEvent
        nofields proc InitBackground
        nofields proc TileError
        nofields proc Tile
        nofields proc Cascade
end
TDesktop.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.app._deskCreate "$this"
}
TDesktop.HandleEvent() { fv.app._deskEvent "$this" "$@" || return; }
TDesktop.InitBackground() { fv.app._deskInitBackground "$this" || return; }
TDesktop.TileError() { fv.app._deskTileError "$this" || return; }
TDesktop.Tile() { fv.app.tile "$this" "$@" || return; }
TDesktop.Cascade() { fv.app.cascade "$this" "$@" || return; }
build TDesktop

# TProgram.new NAME — FV TProgram.Init: the TGroup part over the screen
# (0 0 FV_SCREEN_W FV_SCREEN_H), Application := NAME (FV_APP), the event
# hooks, InitScreen, State sfVisible + sfSelected + sfFocused + sfModal
# (sfExposed: at Run, the first paint), Options 0, then the virtuals
# InitStatusLine, InitMenuBar, InitDesktop and the desktop, status line and
# menu bar they made (FV_DESKTOP, FV_STATUSLINE, FV_MENUBAR) inserted, in
# FV's order. Draws nothing. One application at a time: a second one while
# FV_APP is live is refused (rc 1, one Error line). No terminal: that is
# TApplication's (TProgram alone draws to FV_VIDEO_OUT_FD / FV_TTY_FD as set)
class TProgram : TGroup
    public
        constructor Create
        nofields destructor Done
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields proc Run
        nofields func GetEvent
        nofields proc PutEvent
        nofields proc Idle
        nofields proc InitScreen
        nofields proc InitStatusLine
        nofields proc InitMenuBar
        nofields proc InitDesktop
end
TProgram.Create() {
    if [[ -n ${__FV_VW_LIVE[$this]-} ]]; then
        local __fva_was=0
        if [ "$this" = "$FV_APP" ]; then __fva_was=1; fi
        parent.constructor "$@"
        fv.app._recreated "$__fva_was"
        return "$__FV_VW_CRC"
    fi
    fv.app._single "$this" || return
    local __fva_w __fva_h
    fv.app._size
    parent.constructor 0 0 "$__fva_w" "$__fva_h"
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.app._progCreate "$this"
}
TProgram.Done() { fv.app._progDone "$this"; inherited; }
TProgram.HandleEvent() { fv.app._progEvent "$this" "$@" || return; }
TProgram.GetPalette() { fv.app._progGetPalette "$this" || return; }
TProgram.Run() { fv.app._run "$this" || return; }
TProgram.GetEvent() { fv.app._progGetEvent "$this" "$@" || return; }
TProgram.PutEvent() { fv.app._progPutEvent "$this" "$@" || return; }
TProgram.Idle() { fv.app._progIdle "$this" || return; }
TProgram.InitScreen() { fv.app._progInitScreen "$this" || return; }
TProgram.InitStatusLine() { fv.app._progInitStatusLine "$this" || return; }
TProgram.InitMenuBar() { fv.app._progInitMenuBar "$this" || return; }
TProgram.InitDesktop() { fv.app._progInitDesktop "$this" || return; }
build TProgram

# TApplication.new NAME — FV TApplication.Init: the terminal on
# (fv.video.initVideo: rc 1 -> the constructor fails, nothing made;
# fv.drivers.initEvents), unless FV_APP_HEADLESS=1; then TProgram's. Done:
# TProgram's, then doneEvents and doneVideo (when this Init turned the
# terminal on). HandleEvent: cmTile, cmCascade, cmResizeApp. GetTileRect
# (virtual): the desktop's extent in FV_RECT_* (FV's var parameter).
class TApplication : TProgram
    public
        constructor Create
        nofields destructor Done
        nofields override proc HandleEvent
        nofields proc GetTileRect
        nofields proc Tile
        nofields proc Cascade
end
TApplication.Create() {
    local __fva_v=0
    if [[ -z ${__FV_VW_LIVE[$this]-} ]]; then
        fv.app._single "$this" || return
        fv.app._video || return
        __fva_v=1
    fi
    inherited
    if [[ -z ${__FV_VW_LIVE[$this]-} ]]; then
        if (( __fva_v )); then fv.app._videoOff; fi
        return "$__FV_VW_CRC"
    fi
}
TApplication.Done() { inherited; fv.app._appDone "$this"; }
TApplication.HandleEvent() { fv.app._appEvent "$this" "$@" || return; }
TApplication.GetTileRect() { fv.app._appGetTileRect "$this" || return; }
TApplication.Tile() { fv.app.tile "$this" || return; }
TApplication.Cascade() { fv.app.cascade "$this" || return; }
build TApplication

# fv.app._register — the built-in bodies into fv.views' elision tables
# (fv.views merges them on a reload; the constructors register them again
# only when they are missing). QGRP: handlers that react to no broadcast and
# pass one on as TGroup's does (fv.views._quiet walks into them)
fv.app._register() {
    __FV_VW_IMPL[TBackground.Draw]=fv.app._bgDraw
    __FV_VW_IMPL[TBackground.GetPalette]=fv.app._bgGetPalette
    __FV_VW_IMPL[TDesktop.HandleEvent]=fv.app._deskEvent
    __FV_VW_IMPL[TDesktop.InitBackground]=fv.app._deskInitBackground
    __FV_VW_IMPL[TDesktop.TileError]=fv.app._deskTileError
    __FV_VW_IMPL[TProgram.HandleEvent]=fv.app._progEvent
    __FV_VW_IMPL[TProgram.GetPalette]=fv.app._progGetPalette
    __FV_VW_IMPL[TProgram.Run]=fv.app._run
    __FV_VW_IMPL[TProgram.GetEvent]=fv.app._progGetEvent
    __FV_VW_IMPL[TProgram.PutEvent]=fv.app._progPutEvent
    __FV_VW_IMPL[TProgram.Idle]=fv.app._progIdle
    __FV_VW_IMPL[TProgram.InitScreen]=fv.app._progInitScreen
    __FV_VW_IMPL[TProgram.InitStatusLine]=fv.app._progInitStatusLine
    __FV_VW_IMPL[TProgram.InitMenuBar]=fv.app._progInitMenuBar
    __FV_VW_IMPL[TProgram.InitDesktop]=fv.app._progInitDesktop
    __FV_VW_IMPL[TApplication.HandleEvent]=fv.app._appEvent
    __FV_VW_IMPL[TApplication.GetTileRect]=fv.app._appGetTileRect
    __FV_VW_QGRP[fv.app._deskEvent]=1
    __FV_VW_QGRP[fv.app._progEvent]=1
    __FV_VW_QGRP[fv.app._appEvent]=1
}
fv.app._register

# ---- helpers ----------------------------------------------------------------------
fv.app._err() {
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then printf 'Error: fv.app: %s\n' "$1" >&2; fi
    return 0
}
fv.app._bad() {
    RESULT=''
    kk.debug "Error: fv.app.$1: $2"
    return 2
}
# fv.app._int VALUE MAX — rc 0 for 1-9 plain digits whose value is <= MAX
fv.app._int() {
    [[ -n $1 && $1 != *[!0123456789]* && ${#1} -le 9 ]] && (( 10#$1 <= $2 ))
}
# fv.app._size — the caller's __fva_w / __fva_h = FV_SCREEN_W / _H (1-5
# digits, else 80 x 24; the width at most FV's MaxViewWidth 1024)
fv.app._size() {
    __fva_w=${FV_SCREEN_W-} __fva_h=${FV_SCREEN_H-}
    if ! fv.app._int "$__fva_w" 99999 || (( 10#$__fva_w < 1 )); then __fva_w=80; fi
    if ! fv.app._int "$__fva_h" 99999 || (( 10#$__fva_h < 1 )); then __fva_h=24; fi
    __fva_w=$(( 10#$__fva_w )) __fva_h=$(( 10#$__fva_h ))
    if (( __fva_w > 1024 )); then __fva_w=1024; fi
}
# fv.app._single NAME — rc 0 unless another application is live (rc 1, one
# Error line: FV has one Application; a second would take over the hooks).
# FV_APP naming a dead view: its state released first
fv.app._single() {
    if [[ -n $FV_APP && -z ${__FV_VW_LIVE[$FV_APP]-} ]]; then
        # (the application's name was taken over by a view of another class:
        # its hooks, globals, palette and terminal go as at Done)
        fv.app._release
        fv.app._videoOff
    fi
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then
        fv.app._err "TProgram.Create: '$1': the application '$FV_APP' is live (one application at a time: $FV_APP.delete first)"
        __FV_VW_CRC=1
        return 1
    fi
    return 0
}
# fv.app._video — TApplication's terminal: initVideo + initEvents unless
# FV_APP_HEADLESS=1; __FV_AP_VIDEO = 1 when this call turned it on. rc 1:
# no terminal (initVideo's debug line)
fv.app._video() {
    __FV_AP_VIDEO=0 __FV_AP_EVENTS=0
    if [ "${FV_APP_HEADLESS-}" = 1 ]; then return 0; fi
    local __fva_on=${FV_VIDEO_ON:-0}
    if ! fv.video.initVideo; then
        kk.debug "Error: fv.app: TApplication.Create: no terminal (fv.video.initVideo failed)"
        __FV_VW_CRC=1
        return 1
    fi
    if (( ! __fva_on )); then __FV_AP_VIDEO=1; fi
    if fv.drivers.initEvents; then __FV_AP_EVENTS=1; fi
}
# fv.app._videoOff — what _video turned on, off: doneEvents when it called
# initEvents, doneVideo when it turned the terminal on
fv.app._videoOff() {
    if (( __FV_AP_EVENTS )); then fv.drivers.doneEvents || :; fi
    if (( __FV_AP_VIDEO )); then fv.video.doneVideo || :; fi
    __FV_AP_VIDEO=0 __FV_AP_EVENTS=0
}
# fv.app._recreated WAS — after `.new` over a live name (TView's guard
# repaired the tree and refused): when the name was the application (WAS 1)
# its hooks, globals and terminal go as at Done
fv.app._recreated() {
    if (( $1 )); then
        fv.app._release
        fv.app._videoOff
    fi
    return 0
}

# ---- TBackground ------------------------------------------------------------------
fv.app._bgCreate() {
    local -n __fva_d=${1}_data
    if [[ -z ${__FV_VW_IMPL[TBackground.Draw]-} ]]; then fv.app._register; fi
    __fva_d[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    __fva_d[Pattern]=$2
}
# TBackground.Draw — FV: MoveChar(B, Pattern, GetColor(1), Size.X);
# WriteLine(0, 0, Size.X, Size.Y, B): one fill
fv.app._bgDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fva_d=${1}_data
    local __fva_p=${__fva_d[Pattern]-} __fva_c=${FV_DRAW_PAL:0:1}
    if [[ -z $__fva_p ]]; then __fva_p=' '; fi
    if [ "${FV_VIDEO_ASCII:-0}" = 1 ] && [[ ${__fva_p:0:1} == [![:ascii:]] ]]; then __fva_p='#'; fi
    fv.video.fillRect "$FV_DRAW_X" "$FV_DRAW_Y" "${__fva_d[SizeX]:-0}" "${__fva_d[SizeY]:-0}" "${__fva_c:-$__FV_VW_ERRSYM}" "$__fva_p" || :
}
# TBackground.GetPalette (func) — FV CBackground #1
fv.app._bgGetPalette() { RESULT='1'; }

# ---- TDesktop ---------------------------------------------------------------------
fv.app._deskCreate() {
    local -n __fva_d=${1}_data
    if [[ -z ${__FV_VW_IMPL[TDesktop.HandleEvent]-} ]]; then fv.app._register; fi
    __fva_d[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    __fva_d[Background]='' __fva_d[TileColumnsFirst]=0
    fv.views._virt "$1" InitBackground || :
    local __fva_b=${__fva_d[Background]-}
    if [[ -n $__fva_b && -n ${__FV_VW_LIVE[$__fva_b]-} ]]; then
        local -n __fva_bd=${__fva_b}_data
        if [[ -z ${__fva_bd[Owner]-} ]]; then fv.views.insert "$1" "$__fva_b" || :; fi
    fi
}
# TDesktop.InitBackground — FV: Background := a TBackground over the extent
# with FV's pattern (#$2591 '░'): NAME__fvbg
fv.app._deskInitBackground() {
    local -n __fva_d=${1}_data
    local __fva_r=${RESULT-}
    if fv.views._newReserved "$1" bg TBackground 0 0 "${__fva_d[SizeX]:-0}" "${__fva_d[SizeY]:-0}" '░'; then
        __fva_d[Background]=$RESULT
    fi
    RESULT=$__fva_r
}
# TDesktop.TileError — FV: abstract (nothing)
fv.app._deskTileError() { return 0; }

# TDesktop.HandleEvent — FV: TGroup's, then evCommand cmNext ->
# FocusNext(False); cmPrev -> with a Background: Current put in front of the
# background (behind every window) when Valid(cmReleasedFocus) agrees,
# without one FocusNext(True); handled
fv.app._deskEvent() {
    fv.views._groupEvent "$1"
    if ! [ "$FV_EV_WHAT" = evCommand ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    if [ "$FV_EV_COMMAND" = cmNext ]; then
        fv.views.focusNext "$1" 0 || :
    elif [ "$FV_EV_COMMAND" = cmPrev ]; then
        local -n __fva_d=${1}_data
        local __fva_b=${__fva_d[Background]-} __fva_c=${__fva_d[Current]-}
        if [[ -n $__fva_b && -n ${__FV_VW_LIVE[$__fva_b]-} ]]; then
            if fv.views._virt "$1" Valid cmReleasedFocus && [[ -n $__fva_c && -n ${__FV_VW_LIVE[$__fva_c]-} ]]; then
                fv.views.putInFrontOf "$__fva_c" "$__fva_b" || :
            fi
        else
            fv.views.focusNext "$1" 1 || :
        fi
    else
        return 0
    fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}

# ---- Tile / Cascade (FV TDesktop.Tile / Cascade, TApplication.Tile / Cascade) ----

# fv.app.tile V [AX AY BX BY] — V a desktop with a rect (desktop
# coordinates, B exclusive): FV TDesktop.Tile(R); V an application without
# one: FV TApplication.Tile (GetTileRect, then the desktop's Tile). The
# visible views with ofTileable are laid out as FV does (MostEqualDivisors by
# TileColumnsFirst, the front-most last), each by `locate` (its SizeLimits
# apply) with the drawing held, then the desktop drawn once. Too small a rect
# (a column or a row of 0 cells): TileError (virtual), nothing moved. RESULT
# kept; rc 2 for a malformed call
fv.app.tile() { fv.app._layout tile "$@"; }
# fv.app.cascade V [AX AY BX BY] — FV TDesktop.Cascade(R) / TApplication.
# Cascade: the tileable views offset by one cell each from R's corner (the
# back-most at R's corner, the front-most furthest in), each up to R's
# bottom-right; TileError when the back-most one's SizeLimits minimum does
# not fit. As tile otherwise
fv.app.cascade() { fv.app._layout cascade "$@"; }
fv.app._layout() {   # tile|cascade V [AX AY BX BY]
    local __fva_k=$1 __fva_r=${RESULT-}
    shift
    if (( $# != 1 && $# != 5 )); then fv.app._bad "$__fva_k" 'wrong argument count (V, or a desktop and AX AY BX BY)'; return; fi
    if [[ -z $1 || -z ${__FV_VW_LIVE[$1]-} ]]; then fv.app._bad "$__fva_k" "'$1' is not a view"; return; fi
    local __fva_d=$1 __fva_a1 __fva_a2 __fva_b1 __fva_b2
    if (( $# == 1 )); then
        # (an application: its desktop; GetTileRect through the elision)
        __fva_d=${FV_DESKTOP-}
        if ! [ "$1" = "${FV_APP-}" ]; then fv.app._bad "$__fva_k" "'$1' is not the application (FV_APP), and no rect was given"; return; fi
        if [[ -z $__fva_d || -z ${__FV_VW_LIVE[$__fva_d]-} ]]; then RESULT=$__fva_r; return 0; fi
        # (a TProgram has no GetTileRect: TApplication's answer, the desktop's extent)
        local __fva_o=${1}_class
        __fva_o="${!__fva_o-}_class_method_owner[GetTileRect]"
        if [[ -n ${!__fva_o-} ]]; then
            FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=0 FV_RECT_BY=0
            fv.views._virt "$1" GetTileRect || :
        else
            fv.app._appGetTileRect "$1"
        fi
        __fva_a1=$FV_RECT_AX __fva_a2=$FV_RECT_AY __fva_b1=$FV_RECT_BX __fva_b2=$FV_RECT_BY
    else
        local __fva_x __fva_m
        local -a __fva_q=()
        for __fva_x in "$2" "$3" "$4" "$5"; do
            __fva_m=1
            if [ "${__fva_x:0:1}" = - ]; then __fva_m=-1 __fva_x=${__fva_x:1}; fi
            if [[ -z $__fva_x || $__fva_x == *[!0123456789]* || ${#__fva_x} -gt 8 ]]; then
                fv.app._bad "$__fva_k" 'AX AY BX BY must be integers'; return
            fi
            __fva_q+=("$(( __fva_m * 10#$__fva_x ))")
        done
        __fva_a1=${__fva_q[0]} __fva_a2=${__fva_q[1]} __fva_b1=${__fva_q[2]} __fva_b2=${__fva_q[3]}
    fi
    if [[ -z ${__FV_VW_GRP[$__fva_d]-} ]]; then fv.app._bad "$__fva_k" "'$__fva_d' is not a group"; return; fi
    if [ "$__fva_k" = tile ]; then fv.app._tile "$__fva_d" "$__fva_a1" "$__fva_a2" "$__fva_b1" "$__fva_b2"
    else fv.app._cascade "$__fva_d" "$__fva_a1" "$__fva_a2" "$__fva_b1" "$__fva_b2"; fi
    RESULT=$__fva_r
    return 0
}
# fv.app._tileable D — the caller's __fva_t = D's tileable subviews front to
# back (FV ForEach order: First .. Last): ofTileable and sfVisible
fv.app._tileable() {
    local -n __fva_l=${1}_views
    local __fva_i __fva_v
    __fva_t=()
    for (( __fva_i = ${#__fva_l[@]} - 1; __fva_i >= 0; __fva_i-- )); do
        __fva_v=${__fva_l[__fva_i]}
        [[ -n ${__FV_VW_LIVE[$__fva_v]-} ]] || continue
        local -n __fva_vd=${__fva_v}_data
        if (( (${__fva_vd[Options]:-0} & FV_OF_TILEABLE) && (${__fva_vd[State]:-0} & FV_SF_VISIBLE) )); then __fva_t+=("$__fva_v"); fi
    done
}
# fv.app._tileError D — D's TileError (virtual) when its class has one (a
# plain TGroup has none: nothing)
fv.app._tileError() {
    local __fva_o=${1}_class
    __fva_o="${!__fva_o-}_class_method_owner[TileError]"
    if [[ -n ${!__fva_o-} ]]; then fv.views._virt "$1" TileError || :; fi
    return 0
}
# FV DividerLoc(Lo, Hi, Num, Pos) into the caller's __fva_q
fv.app._div() { __fva_q=$(( ($2 - $1) * $4 / $3 + $1 )); }
fv.app._tile() {   # D AX AY BX BY
    local -n __fva_dd=${1}_data
    local -a __fva_t
    local __fva_n __fva_i __fva_c __fva_r __fva_lo __fva_d __fva_x __fva_y __fva_q __fva_p
    local __fva_x1 __fva_x2 __fva_y1 __fva_y2
    fv.app._tileable "$1"
    __fva_n=${#__fva_t[@]}
    if (( __fva_n == 0 )); then return 0; fi
    # FV MostEqualDivisors(N, NumCols, NumRows, NOT TileColumnsFirst)
    __fva_i=0
    while (( (__fva_i + 1) * (__fva_i + 1) <= __fva_n )); do __fva_i=$(( __fva_i + 1 )); done
    if (( __fva_n % __fva_i != 0 && __fva_n % (__fva_i + 1) == 0 )); then __fva_i=$(( __fva_i + 1 )); fi
    if (( __fva_i < __fva_n / __fva_i )); then __fva_i=$(( __fva_n / __fva_i )); fi
    if [[ ${__fva_dd[TileColumnsFirst]:-0} == [123456789]* ]]; then
        __fva_r=$(( __fva_n / __fva_i )) __fva_c=$__fva_i
    else
        __fva_c=$(( __fva_n / __fva_i )) __fva_r=$__fva_i
    fi
    if (( ($4 - $2) / __fva_c == 0 || ($5 - $3) / __fva_r == 0 )); then
        fv.app._tileError "$1"
        return 0
    fi
    __fva_lo=$(( __fva_n % __fva_c ))
    __fva_d=$(( (__fva_c - __fva_lo) * __fva_r ))
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
    for (( __fva_i = 0; __fva_i < __fva_n; __fva_i++ )); do
        # (FV's TileNum counts down from N-1: the front-most view takes the last place)
        __fva_p=$(( __fva_n - 1 - __fva_i ))
        if (( __fva_p < __fva_d )); then
            __fva_x=$(( __fva_p / __fva_r )) __fva_y=$(( __fva_p % __fva_r ))
        else
            __fva_x=$(( (__fva_p - __fva_d) / (__fva_r + 1) + __fva_c - __fva_lo )) __fva_y=$(( (__fva_p - __fva_d) % (__fva_r + 1) ))
        fi
        fv.app._div "$2" "$4" "$__fva_c" "$__fva_x"; __fva_x1=$__fva_q
        fv.app._div "$2" "$4" "$__fva_c" "$(( __fva_x + 1 ))"; __fva_x2=$__fva_q
        if (( __fva_p >= __fva_d )); then
            fv.app._div "$3" "$5" "$(( __fva_r + 1 ))" "$__fva_y"; __fva_y1=$__fva_q
            fv.app._div "$3" "$5" "$(( __fva_r + 1 ))" "$(( __fva_y + 1 ))"; __fva_y2=$__fva_q
        else
            fv.app._div "$3" "$5" "$__fva_r" "$__fva_y"; __fva_y1=$__fva_q
            fv.app._div "$3" "$5" "$__fva_r" "$(( __fva_y + 1 ))"; __fva_y2=$__fva_q
        fi
        if [[ -n ${__FV_VW_LIVE[${__fva_t[__fva_i]}]-} ]]; then
            fv.views.locate "${__fva_t[__fva_i]}" "$__fva_x1" "$__fva_y1" "$__fva_x2" "$__fva_y2" || :
        fi
    done
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
    if (( __FV_VW_NODRAW < 0 )); then __FV_VW_NODRAW=0; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views.drawView "$1" || :; fi
}
fv.app._cascade() {   # D AX AY BX BY
    local -a __fva_t
    local __fva_n __fva_i __fva_v
    fv.app._tileable "$1"
    __fva_n=${#__fva_t[@]}
    if (( __fva_n == 0 )); then return 0; fi
    # (FV: the SizeLimits of LastView, the last tileable one in ForEach order)
    fv.views._virt "${__fva_t[__fva_n - 1]}" SizeLimits || :
    if (( FV_MIN_X > $4 - $2 - __fva_n || FV_MIN_Y > $5 - $3 - __fva_n )); then
        fv.app._tileError "$1"
        return 0
    fi
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
    for (( __fva_i = 0; __fva_i < __fva_n; __fva_i++ )); do
        __fva_v=$(( __fva_n - 1 - __fva_i ))
        if [[ -n ${__FV_VW_LIVE[${__fva_t[__fva_i]}]-} ]]; then
            fv.views.locate "${__fva_t[__fva_i]}" "$(( $2 + __fva_v ))" "$(( $3 + __fva_v ))" "$4" "$5" || :
        fi
    done
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
    if (( __FV_VW_NODRAW < 0 )); then __FV_VW_NODRAW=0; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views.drawView "$1" || :; fi
}

# ---- TProgram ---------------------------------------------------------------------

# fv.app._progCreate APP — FV TProgram.Init after the TGroup part (above)
fv.app._progCreate() {
    local -n __fva_d=${1}_data
    local __fva_v
    if [[ -z ${__FV_VW_IMPL[TProgram.Run]-} ]]; then fv.app._register; fi
    __FV_AP_OWNER=$BASHPID
    __FV_AP_SGET=$__FV_VW_GETEVENT __FV_AP_SPUT=$__FV_VW_PUTEVENT __FV_AP_SOWN=$__FV_VW_OWNER __FV_AP_SEOF=$__FV_VW_EOF __FV_AP_SHOWN=0
    __FV_VW_GETEVENT=fv.app._getEvent __FV_VW_PUTEVENT=fv.app._putEvent __FV_VW_OWNER=$BASHPID __FV_VW_EOF=0
    FV_APP=$1 FV_DESKTOP='' FV_STATUSLINE='' FV_MENUBAR=''
    fv.views._virt "$1" InitScreen || :
    __fva_d[State]=$(( FV_SF_VISIBLE | FV_SF_SELECTED | FV_SF_FOCUSED | FV_SF_MODAL ))
    __fva_d[Options]=0
    __FV_AP_ININIT=1
    fv.views._virt "$1" InitStatusLine || :
    fv.views._virt "$1" InitMenuBar || :
    fv.views._virt "$1" InitDesktop || :
    for __fva_v in "$FV_DESKTOP" "$FV_STATUSLINE" "$FV_MENUBAR"; do
        [[ -n $__fva_v && -n ${__FV_VW_LIVE[$__fva_v]-} ]] || continue
        local -n __fva_vd=${__fva_v}_data
        if [[ -z ${__fva_vd[Owner]-} ]]; then fv.views.insert "$1" "$__fva_v" || :; fi
    done
    __FV_AP_ININIT=0
    return 0
}
# fv.app._release — the application's globals, fv.views' hooks, owner and
# end-of-input latch put back; the app palette and the colours setAppPalette
# changed back to the defaults (Done, a re-creation over the live name)
fv.app._release() {
    local __fva_r=${RESULT-} __fva_c __fva_v __fva_f __fva_b
    __FV_VW_GETEVENT=${__FV_AP_SGET:-fv.drivers.getEvent} __FV_VW_PUTEVENT=${__FV_AP_SPUT:-fv.drivers.putEvent}
    __FV_VW_OWNER=${__FV_AP_SOWN:-$BASHPID} __FV_VW_EOF=${__FV_AP_SEOF:-0}
    FV_APP='' FV_DESKTOP='' FV_STATUSLINE='' FV_MENUBAR='' __FV_AP_OWNER='' __FV_AP_SHOWN=0
    __FV_VW_APAL=$__FV_AP_DEFPAL __FV_VW_ERRSYM=0
    # (the symbols setAppPalette redefined get their colours back; one that
    # was undefined before stays defined: nothing refers to it any more)
    for __fva_c in "${!__FV_AP_SAVED[@]}"; do
        __fva_v=${__FV_AP_SAVED[$__fva_c]}
        [[ -n $__fva_v ]] || continue
        __fva_f=${__fva_v%% *} __fva_v=${__fva_v#* }
        __fva_b=${__fva_v%% *} __fva_v=${__fva_v#* }
        fv.video.definePalette "$__fva_c" "$__fva_f" "$__fva_b" "$__fva_v" || :
    done
    __FV_AP_SAVED=()
    fv.views.resetPalette || :
    RESULT=$__fva_r
}
# TProgram.Done — FV: the desktop, menu bar and status line destroyed,
# Application := nil; then TGroup's (the rest of the subviews). Nothing is
# drawn (sfExposed off first: the program is going away)
fv.app._progDone() {
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -n __fva_d=${1}_data
    local __fva_v
    __fva_d[State]=$(( ${__fva_d[State]:-0} & ~FV_SF_EXPOSED ))
    if [ "$1" = "$FV_APP" ]; then
        for __fva_v in "$FV_DESKTOP" "$FV_MENUBAR" "$FV_STATUSLINE"; do
            if [[ -n $__fva_v && -n ${__FV_VW_LIVE[$__fva_v]-} ]] && declare -F "$__fva_v.delete" >/dev/null; then "$__fva_v.delete"; fi
        done
        fv.app._release
    fi
    return 0
}
# TApplication.Done (after TProgram's) — FV: DoneEvents, DoneVideo (each
# only when this application's Init turned it on)
fv.app._appDone() {
    fv.app._videoOff
    return 0
}

# TProgram.GetPalette (func) — FV CAppColor: '' here, the root maps into the
# app palette (__FV_VW_APAL) as it is; an override answers an index list
# into it
fv.app._progGetPalette() { RESULT=''; }

# TProgram.InitScreen — FV: the video detected (passive). fv.video's buffer
# at FV_SCREEN_W x FV_SCREEN_H (initScreen: the default palette, the shadow
# symbol V), the app palette back to CAppColor and FV's ErrorAttr ($CF)
# given a symbol of its own (the first free one, W): an index outside a
# palette shows white on red as in FV
fv.app._progInitScreen() {
    local __fva_r=${RESULT-} __fva_s
    fv.video.initScreen || :
    __FV_VW_APAL=$__FV_AP_DEFPAL __FV_VW_ERRSYM=0 __FV_AP_SAVED=()
    __fva_s=''
    fv.app._free
    if [[ -n $__fva_s ]] && fv.video.definePalette "$__fva_s" "${__FV_VS_DOS[15]:-15}" "${__FV_VS_DOS[12]:-9}" 0; then __FV_VW_ERRSYM=$__fva_s; fi
    fv.views.resetPalette || :
    RESULT=$__fva_r
}

# TProgram.InitStatusLine — FV: the last row, NewStatusDef(0, $FFFF,
# '~Alt-X~ Exit' kbAltX cmQuit + StdStatusKeys): APP__fvstatus;
# FV_STATUSLINE = it
fv.app._progInitStatusLine() {
    local -n __fva_d=${1}_data
    local __fva_r=${RESULT-} __fva_w=${__fva_d[SizeX]:-0} __fva_h=${__fva_d[SizeY]:-0}
    if fv.views._newReserved "$1" status TStatusLine 0 "$(( __fva_h - 1 ))" "$__fva_w" "$__fva_h" def 0 65535 \
        '~Alt-X~ Exit' kbAltX cmQuit '' kbAltX cmQuit '' kbF10 cmMenu '' kbAltF3 cmClose '' kbF5 cmZoom \
        '' kbCtrlF5 cmResize '' kbF6 cmNext '' kbShiftF6 cmPrev; then
        FV_STATUSLINE=$RESULT
    fi
    RESULT=$__fva_r
}
# TProgram.InitMenuBar — nothing: the bar only on request (D23; FV makes an
# empty one-row TMenuBar, app.inc:958-964). An override makes one (FV's way:
# a TMenuBar on the extent's first row, FV_MENUBAR = it) or calls
# fv.menus.menuBar; InitDesktop then leaves row 0 to it
fv.app._progInitMenuBar() { return 0; }
# TProgram.InitDesktop — FV: the extent minus the menu bar's row and the
# status line's: APP__fvdesktop; FV_DESKTOP = it
fv.app._progInitDesktop() {
    local -n __fva_d=${1}_data
    local __fva_r=${RESULT-} __fva_ay=0 __fva_by=${__fva_d[SizeY]:-0}
    if [[ -n $FV_MENUBAR && -n ${__FV_VW_LIVE[$FV_MENUBAR]-} ]]; then __fva_ay=1; fi
    if [[ -n $FV_STATUSLINE && -n ${__FV_VW_LIVE[$FV_STATUSLINE]-} ]]; then __fva_by=$(( __fva_by - 1 )); fi
    if fv.views._newReserved "$1" desktop TDesktop 0 "$__fva_ay" "${__fva_d[SizeX]:-0}" "$__fva_by"; then FV_DESKTOP=$RESULT; fi
    RESULT=$__fva_r
}

# TProgram.Run — FV: Execute (a procedure: RESULT kept). The first paint
# (sfExposed set, the whole application drawn once, the cursor), then the
# modal loop (TGroup.Execute through the elision, fv.views) until EndModal
# (cmQuit; also at the end of input, __FV_VW_EOF then 1). rc 2 in a process
# other than the one that made the application (inside $( ), a pipeline)
fv.app._run() {
    if ! [ "$BASHPID" = "$__FV_AP_OWNER" ]; then
        fv.app._bad Run "refused in a subshell (BASHPID $BASHPID; the application belongs to ${__FV_AP_OWNER:-none}): run it in the shell that made it"
        return 2
    fi
    if (( ! __FV_AP_SHOWN )); then fv.app._firstPaint "$1"; fi
    local __fva_s=0 __fva_r=${RESULT-}
    fv.views._virt "$1" Execute || __fva_s=$?
    RESULT=$__fva_r
    return "$__fva_s"
}

# fv.app._firstPaint APP — the first paint (Run, or the first GetEvent of a
# modal view executed before Run): sfExposed set, the whole application
# drawn once, the cursor, shown; SHOWN = 1
fv.app._firstPaint() {
    __FV_AP_SHOWN=1
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -n __fva_d=${1}_data
    if (( ! (${__fva_d[State]:-0} & FV_SF_EXPOSED) )); then
        __fva_d[State]=$(( ${__fva_d[State]:-0} | FV_SF_EXPOSED ))
        fv.views.drawView "$1" || :
        fv.views.resetCursor "$1" || :
    fi
    fv.views._showNow
}

# fv.app._getEvent [TIMEOUT] — the event source of fv.views' loops
# (__FV_VW_GETEVENT while an application is live): the application's
# GetEvent through the elision (an override of yours is dispatched)
fv.app._getEvent() {
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.views._virt "$FV_APP" GetEvent "$@"; return; fi
    fv.drivers.getEvent "$@"
}
# fv.app._putEvent — FV PutEvent of the application (__FV_VW_PUTEVENT)
fv.app._putEvent() {
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.views._virt "$FV_APP" PutEvent; return; fi
    fv.drivers.putEvent
}
# TProgram.PutEvent — FV: Pending := Event (fv.drivers' one slot)
fv.app._progPutEvent() {
    local __fva_r=${RESULT-}
    fv.drivers.putEvent
    RESULT=$__fva_r
}

# TProgram.GetEvent [TIMEOUT] (func) — FV TProgram.GetEvent:
#   * the application's first paint when it had none yet (a modal view
#     executed before Run);
#   * after the end of input (the latch __FV_VW_EOF): rc 1 at once;
#   * the pending event (PutEvent) as it is;
#   * else fv.drivers.getEvent TIMEOUT (default FV_IDLE_TIMEOUT, 0.05 s; 0 =
#     only what is there): a cmResizeApp (FV's system event) is handed to
#     the application's HandleEvent right away (TApplication's resize) and
#     counted in __FV_VW_RESIZES, and what is left of it goes on (normally
#     nothing: the resize handled it); evNothing -> Idle (virtual);
#   * rc 1 at the end of input (FV_EV_EOF=1; latched), fv.drivers' rc 2 as
#     it is.
# RESULT = FV_EV_WHAT. What a resize or Idle drew is shown at once
fv.app._progGetEvent() {
    if (( ! __FV_AP_SHOWN )); then fv.app._firstPaint "$1"; fi
    if (( __FV_VW_EOF )); then fv.drivers.clearEvent; FV_EV_EOF=1 RESULT=''; return 1; fi
    if (( ${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    local __fva_s=0
    fv.drivers.getEvent "${@:2}" || __fva_s=$?
    if (( __fva_s )); then
        if (( __fva_s == 1 )); then __FV_VW_EOF=1; fi
        return "$__fva_s"
    fi
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmResizeApp ]; then
        __FV_VW_RESIZES=$(( ${__FV_VW_RESIZES:-0} + 1 ))
        fv.views._virt "$1" HandleEvent || :
        fv.views._showNow
    fi
    if [ "${FV_EV_WHAT:-evNothing}" = evNothing ]; then
        FV_EV_WHAT=evNothing
        fv.views._virt "$1" Idle || :
        fv.views._showNow
    fi
    RESULT=$FV_EV_WHAT
}

# TProgram.Idle — FV: the status line's Update; when the command set
# changed, the broadcast cmCommandSetChanged to the application, then the
# flag cleared. With built-in views: no dispatch
fv.app._progIdle() {
    local __fva_s=$FV_STATUSLINE __fva_o
    if [[ -n $__fva_s && -n ${__FV_VW_LIVE[$__fva_s]-} ]]; then
        __fva_o=${__fva_s}_class
        __fva_o="${!__fva_o-}_class_method_owner[Update]"
        if [[ -n ${!__fva_o-} ]]; then fv.views._virt "$__fva_s" Update || :; fi
    fi
    if (( FV_COMMANDSETCHANGED )); then
        fv.views._message "$1" evBroadcast cmCommandSetChanged '' || :
        FV_COMMANDSETCHANGED=0
    fi
    return 0
}

# TProgram.HandleEvent — FV: Alt+1..9 -> the broadcast cmSelectWindowNum
# (FV_EV_INFO = the digit) to the desktop, handled when a window took it;
# TGroup's; evCommand cmQuit -> EndModal(cmQuit) of the program, handled
fv.app._progEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ] && [[ ${FV_EV_KEY-} == kbAlt[123456789] ]]; then
        local __fva_r=${RESULT-}
        if [[ -n $FV_DESKTOP ]] && fv.views.message "$FV_DESKTOP" evBroadcast cmSelectWindowNum "${FV_EV_KEY:5}"; then
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        fi
        RESULT=$__fva_r
    fi
    fv.views._groupEvent "$1"
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmQuit ] && [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        fv.views._virt "$1" EndModal cmQuit || :
        FV_EV_WHAT=evNothing FV_EV_INFO=$1
    fi
    return 0
}

# ---- TApplication -----------------------------------------------------------------

# TApplication.HandleEvent — FV: TProgram's, then evCommand cmTile (Tile),
# cmCascade (Cascade), cmResizeApp (ResizeApplication(FV_EV_ID,
# FV_EV_INFO)), handled
fv.app._appEvent() {
    fv.app._progEvent "$1"
    if ! [ "$FV_EV_WHAT" = evCommand ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    if [ "$FV_EV_COMMAND" = cmResizeApp ]; then fv.app._resize "$1" "$FV_EV_ID" "$FV_EV_INFO"
    elif [ "$FV_EV_COMMAND" = cmTile ]; then fv.app.tile "$1" || :
    elif [ "$FV_EV_COMMAND" = cmCascade ]; then fv.app.cascade "$1" || :
    else return 0; fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# TApplication.GetTileRect — FV: the desktop's extent, else the
# application's: FV_RECT_* (FV's var parameter; RESULT kept)
fv.app._appGetTileRect() {
    local __fva_v=$1
    if [[ -n $FV_DESKTOP && -n ${__FV_VW_LIVE[$FV_DESKTOP]-} ]]; then __fva_v=$FV_DESKTOP; fi
    local -n __fva_d=${__fva_v}_data
    FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=${__fva_d[SizeX]:-0} FV_RECT_BY=${__fva_d[SizeY]:-0}
}
# fv.app._resize APP W H — FV ResizeApplication (design §2.3): when the size
# differs from the application's: the drawing held, fv.video.resizeScreen at
# W x H, ChangeBounds 0 0 W H through the elision (each subview by its
# GrowMode: the desktop and the status line as FV makes them, windows
# gfGrowAll + gfGrowRel with their ZoomRect), then one full redraw (forced)
# and the cursor. W / H not 1-5 digits: nothing
fv.app._resize() {
    local -n __fva_d=${1}_data
    local __fva_w=$2 __fva_h=$3
    if ! fv.app._int "$__fva_w" 99999 || ! fv.app._int "$__fva_h" 99999 || (( 10#$__fva_w < 1 || 10#$__fva_h < 1 )); then
        kk.debug "Error: fv.app: cmResizeApp with a bad size '$2' x '$3': ignored"
        return 0
    fi
    __fva_w=$(( 10#$__fva_w )) __fva_h=$(( 10#$__fva_h ))
    if (( __fva_w > 1024 )); then __fva_w=1024; fi
    if (( __fva_w == ${__fva_d[SizeX]:-0} && __fva_h == ${__fva_d[SizeY]:-0} )) && (( __fva_h == ${__FV_VS_H:-0} )); then return 0; fi
    FV_SCREEN_W=$__fva_w FV_SCREEN_H=$__fva_h
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
    fv.video.resizeScreen || :
    fv.views._virt "$1" ChangeBounds 0 0 "$__fva_w" "$__fva_h" || :
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
    if (( __FV_VW_NODRAW < 0 )); then __FV_VW_NODRAW=0; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        fv.views.redraw "$1" || :
        fv.views.resetCursor "$1" || :
    fi
    return 0
}

# ---- the app palette (design §1.9) --------------------------------------------------

# fv.app._free — the caller's __fva_s = the first symbol of the pool that
# the app palette does not use and that is not ErrorAttr's ('' = none)
fv.app._free() {
    local -A __fva_u=()
    local __fva_i __fva_c
    for (( __fva_i = 0; __fva_i < ${#__FV_VW_APAL}; __fva_i++ )); do __fva_u[${__FV_VW_APAL:__fva_i:1}]=1; done
    __fva_u[$__FV_VW_ERRSYM]=1
    __fva_s=''
    for (( __fva_i = 0; __fva_i < ${#__FV_AP_POOL}; __fva_i++ )); do
        __fva_c=${__FV_AP_POOL:__fva_i:1}
        if [[ -z ${__fva_u[$__fva_c]-} ]]; then __fva_s=$__fva_c; return 0; fi
    done
}

# fv.app.setAppPalette ENTRY FG BG [BOLD] — the app palette's entry ENTRY
# (1-127, CAppColor's index) gets the colours FG / BG (0-255, D10) and BOLD
# (0 / 1, default 0), without changing the other entries that share its
# symbol: a symbol only this entry uses is redefined in place
# (fv.video.definePalette); else a symbol the palette already uses with
# these colours is taken, else a free one is allocated (the pool: 1-9 A-U
# W-Z a-z, less ErrorAttr's; 0 and the shadow symbol V never). Then every
# view's resolved palette is dropped and the application redrawn; the
# application's Done gives the redefined symbols their colours back. The pool
# belongs to the app palette (design §1.9): a symbol of it you defined for
# your own fv.video drawing may be taken over. rc 1 and
# one Error line when every symbol is in use (nothing changed); rc 2 for a
# malformed call; rc 1 without a screen (fv.video.initScreen). RESULT kept
fv.app.setAppPalette() {
    if (( $# != 3 && $# != 4 )); then fv.app._bad "${FUNCNAME#fv.app.}" 'wrong argument count'; return; fi
    if ! fv.app._int "$1" 127 || (( 10#$1 < 1 )); then fv.app._bad setAppPalette 'ENTRY must be 1..127'; return; fi
    if ! fv.app._int "$2" 255 || ! fv.app._int "$3" 255 || ! [[ ${4:-0} == [01] ]]; then fv.app._bad setAppPalette 'FG BG must be 0..255, BOLD 0 or 1'; return; fi
    if (( ! ${#__FV_VS_PAL[@]} )); then RESULT=''; kk.debug "Error: fv.app.setAppPalette: no screen (fv.video.initScreen first)"; return 1; fi
    local __fva_r=${RESULT-} __fva_p=$__FV_VW_APAL
    local -A __fva_cnt=()
    fv.app._palCount
    if ! fv.app._palSet "$1" "$(( 10#$1 - 1 ))" "$(( 10#$2 ))" "$(( 10#$3 ))" "${4:-0}"; then RESULT=$__fva_r; return 1; fi
    __FV_VW_APAL=$__fva_p
    fv.views.resetPalette || :
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.views.redraw "$FV_APP" || :; fi
    RESULT=$__fva_r
    return 0
}

# fv.app.setAppPalettes "ENTRY FG BG [BOLD]"... — setAppPalette for several
# entries in one call, each word one entry, applied in order with the same
# rules (an entry sees the palette the earlier ones made) but with one scan
# of the palette (the use counts kept up to date as entries change), one
# fv.views.resetPalette and one redraw. Every word is checked first: a
# malformed one (or no word) is rc 2 and nothing changes; rc 1 without a
# screen. An entry that finds every symbol in use gets its Error line and
# is left as it was, the others still apply: rc 1 at the end. RESULT kept
fv.app.setAppPalettes() {
    if (( ! $# )); then fv.app._bad setAppPalettes 'wrong argument count'; return; fi
    local - IFS=$' \t\n' __fva_a __fva_i=0 __fva_rc=0
    local -a __fva_w=() __fva_l=()
    set -f
    for __fva_a in "$@"; do
        __fva_i=$(( __fva_i + 1 ))
        __fva_w=($__fva_a)
        if (( ${#__fva_w[@]} != 3 && ${#__fva_w[@]} != 4 )); then fv.app._bad setAppPalettes "argument $__fva_i '$__fva_a': ENTRY FG BG [BOLD] expected"; return; fi
        if ! fv.app._int "${__fva_w[0]}" 127 || (( 10#${__fva_w[0]} < 1 )); then fv.app._bad setAppPalettes "argument $__fva_i '$__fva_a': ENTRY must be 1..127"; return; fi
        if ! fv.app._int "${__fva_w[1]}" 255 || ! fv.app._int "${__fva_w[2]}" 255 || ! [[ ${__fva_w[3]:-0} == [01] ]]; then
            fv.app._bad setAppPalettes "argument $__fva_i '$__fva_a': FG BG must be 0..255, BOLD 0 or 1"
            return
        fi
        __fva_l+=("${__fva_w[0]}" "$(( 10#${__fva_w[0]} - 1 ))" "$(( 10#${__fva_w[1]} ))" "$(( 10#${__fva_w[2]} ))" "${__fva_w[3]:-0}")
    done
    if (( ! ${#__FV_VS_PAL[@]} )); then RESULT=''; kk.debug "Error: fv.app.setAppPalettes: no screen (fv.video.initScreen first)"; return 1; fi
    local __fva_r=${RESULT-} __fva_p=$__FV_VW_APAL
    local -A __fva_cnt=()
    fv.app._palCount
    for (( __fva_i = 0; __fva_i < ${#__fva_l[@]}; __fva_i += 5 )); do
        fv.app._palSet "${__fva_l[@]:__fva_i:5}" || __fva_rc=1
    done
    __FV_VW_APAL=$__fva_p
    fv.views.resetPalette || :
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.views.redraw "$FV_APP" || :; fi
    RESULT=$__fva_r
    return "$__fva_rc"
}

# fv.app._palCount — the caller's __fva_cnt = symbol -> the entries of the
# caller's palette string __fva_p that use it
fv.app._palCount() {
    local __fva_i __fva_c
    for (( __fva_i = 0; __fva_i < ${#__fva_p}; __fva_i++ )); do
        __fva_c=${__fva_p:__fva_i:1}
        __fva_cnt[$__fva_c]=$(( ${__fva_cnt[$__fva_c]:-0} + 1 ))
    done
}
# fv.app._palSet ENTRY E FG BG BOLD — one entry of setAppPalette(s) on the
# caller's __fva_p / __fva_cnt (E = ENTRY - 1; the colours checked and
# normalised): the symbol chosen by setAppPalette's rules (only this entry
# uses its symbol: in place; a used symbol with these colours; the first
# free one of the pool), defined when its colours differ (its old ones kept
# in __FV_AP_SAVED first), the entry and the counts updated. rc 1: every
# symbol in use (one Error line, nothing changed) or definePalette refused
fv.app._palSet() {
    local __fva_e=$2 __fva_k="$3 $4 $5" __fva_y __fva_s='' __fva_c __fva_i
    __fva_y=${__fva_p:__fva_e:1}
    if (( ${__fva_cnt[$__fva_y]:-0} == 1 )) && ! [ "$__fva_y" = 0 ] && ! [ "$__fva_y" = "${__FV_VS_SHADOW:-V}" ] && ! [ "$__fva_y" = "$__FV_VW_ERRSYM" ]; then
        __fva_s=$__fva_y
    else
        # (a symbol of the palette with these colours: one with a count)
        for __fva_c in "${!__fva_cnt[@]}"; do
            if (( ! ${__fva_cnt[$__fva_c]} )) || [ "$__fva_c" = "$__fva_y" ] || [ "$__fva_c" = 0 ] || [ "$__fva_c" = "$__FV_VW_ERRSYM" ]; then continue; fi
            if [ "${__FV_VS_PAL[$__fva_c]-}" = "$__fva_k" ]; then __fva_s=$__fva_c; break; fi
        done
        if [[ -z $__fva_s ]]; then
            # (the first symbol of the pool the palette does not use, not ErrorAttr's)
            for (( __fva_i = 0; __fva_i < ${#__FV_AP_POOL}; __fva_i++ )); do
                __fva_c=${__FV_AP_POOL:__fva_i:1}
                if (( ! ${__fva_cnt[$__fva_c]:-0} )) && ! [ "$__fva_c" = "$__FV_VW_ERRSYM" ]; then __fva_s=$__fva_c; break; fi
            done
            if [[ -z $__fva_s ]]; then
                fv.app._err "setAppPalette: entry $1: every symbol of the pool is in use ($(( ${#__FV_AP_POOL} - 1 )) for the palette); nothing changed"
                return 1
            fi
        fi
    fi
    if ! [ "${__FV_VS_PAL[$__fva_s]-}" = "$__fva_k" ]; then
        if [[ -z ${__FV_AP_SAVED[$__fva_s]+1} ]]; then __FV_AP_SAVED[$__fva_s]=${__FV_VS_PAL[$__fva_s]-}; fi
        fv.video.definePalette "$__fva_s" "$3" "$4" "$5" || return 1
    fi
    __fva_p=${__fva_p:0:__fva_e}$__fva_s${__fva_p:__fva_e+1}
    if ! [ "$__fva_s" = "$__fva_y" ]; then
        __fva_cnt[$__fva_y]=$(( ${__fva_cnt[$__fva_y]:-0} - 1 ))
        __fva_cnt[$__fva_s]=$(( ${__fva_cnt[$__fva_s]:-0} + 1 ))
    fi
    return 0
}
