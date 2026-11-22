#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.menus.sh}../../kbool.sh" || return
kk.unit fv.menus || return $__kk_unit_rc

# fv.menus — Free Vision's menus unit for the fv.* text UI (layer L2): P2
# stage 2e brings TStatusLine (FV menus.inc: TStatusLine, TStatusDef /
# TStatusItem, NewStatusDef / NewStatusKey, Draw / DrawSelect, FindItems,
# HandleEvent with the mouse press tracking, Hint, Update) as a kklass class
# on top of fv.views' TView; P3 stage 3f the menus (D22, D23): TMenuView
# (the model, Execute, HotKey / FindItem, GetHelpCtx), TMenuBar, TMenuBox,
# TMenuPopup, fv.menus.newSubView, the one-call bar fv.menus.menuBar and the
# status line's hint table fv.menus.setHint.
# Design: kcl/docs/dev/fv/P2_DESIGN.md (§1.2, §1.3, §1.5, §1.8, §1.9, §2.1),
# P3_DESIGN.md (§7, §8.1, §8.4, §14.4); API and deviations: README.md.
#
# Conventions (as fv.views'): locals `__fvm_*`; fields of other instances
# read and written through `${v}_data` (kklass friend contract, decision
# D19), reads as `${d[F]-}`; fork-free and set -eu clean; no `[[ == ]]` /
# `case` / `${x//}` between two names (nocasematch); procedures leave RESULT
# as it was, getters answer in it; a refused call is rc 2 with RESULT='' and
# a kk.debug line, a malformed constructor list one `Error:` line.
#
# Every built-in virtual of TStatusLine (Draw HandleEvent GetPalette Hint
# Update) and of the menu classes has its body in a plain function registered
# in fv.views' elision table __FV_VW_IMPL, so the framework runs it without a
# kklass dispatch unless a class of yours overrides it (fv.views README,
# "Virtual elision").
#
# Friend uses of fv.views' private parts (this unit belongs to the same
# framework; README "Contract and deviations"): reads of __FV_VW_LIVE (a
# live view), __FV_VW_CRC (a refused TView part's rc), __FV_VW_ERRSYM, the
# disabled-command set __FV_VW_CMDOFF (one array read per item instead of a
# call), the event hooks __FV_VW_PUTEVENT / __FV_VW_EOF / __FV_VW_GETEVENT
# (the menus' own loop, as fv.views' loops), the per-event holds
# __FV_VW_LSU / __FV_VW_EH, the absolute origins __FV_VW_AX / __FV_VW_AY (the
# mouse tests), __FV_VW_PAD (blanks) and __FV_VW_C2A (CtrlToArrow); entries
# added to the elision table __FV_VW_IMPL, __FV_VW_FUNC and the broadcast
# table __FV_VW_BCAST; calls of fv.views._virt (the elision entry),
# fv.views._topView (FV TopView), fv.views._viewEvent (TView.HandleEvent's
# body), _evSave / _evRestore, _ownerOk, _showNow, _resetCursor, _release and
# _newReserved. fv.video: _g (its guard). fv.keyboard: layoutBase. fv.app
# (stage 3f, read only, when loaded): __FV_AP_ININIT (the application's Init
# runs: fv.menus.menuBar leaves the insert to it).

kk.uses kklass_pascal fv.views || return

# ---- state ------------------------------------------------------------------
# Per status line (keyed by its name), kept across a reload:
#   CUR[sl]   the def whose items show (FV `Items`): its index, -1 = none
#   GREY[sl]  the enabled signature (0 / 1 per item with a text) of the items
#             last drawn; '' = nothing drawn yet
#   HINT[sl]  the hint text last drawn
#   AM[sl]    the ASCII mode (FV_VIDEO_ASCII) the items' cell patterns were
#             made in; '' = to be made (a new item, or never)
# The defs and items are per-instance arrays (kcl §1.9; freed by the
# destructor), contiguous per def because items are only ever appended to
# the last def (FV builds its chain in order):
#   ${sl}_sdmin ${sl}_sdmax   def i's HelpCtx range (FV Min / Max)
#   ${sl}_sdfirst             def i's first item; its items end where def
#                             i+1's begin (or at the last item)
#   ${sl}_sitext ${sl}_sikey ${sl}_sicmd
#                             item j's text (with FV's `~` hot marks), key
#                             name ('' = none: a click-only item) and command
#   ${sl}_skey (assoc)        the KEY MAP: "DEF:KEY" -> the first item of
#                             def DEF with that key; ${sl}_sinext[j] = the
#                             next item of the same def with item j's key
#                             (-1: none), so FV's "first item with the key
#                             whose command is enabled" walks a short chain.
#                             Built as items are added (once per def)
#   ${sl}_siplain ${sl}_sipat item j's text as drawn (' ' TEXT ' ' without
#                             the `~`) and its cell pattern: one character
#                             per display cell, `+` for FV's Lo colour and
#                             `-` for the Hi one (the `~` parts); made
#                             lazily for the screen's ASCII mode (AM)
#   ${sl}_hints (assoc)       the HINT TABLE (stage 3f, D22): HelpCtx -> the
#                             text the built-in Hint answers
#                             (fv.menus.setHint)
declare -gA __FV_MN_CUR __FV_MN_GREY __FV_MN_HINT __FV_MN_AM
__FV_MN_CUR+=() __FV_MN_GREY+=() __FV_MN_HINT+=() __FV_MN_AM+=()

# ---- the class (FV menus.inc TStatusLine) -------------------------------------
# TStatusLine.new NAME AX AY BX BY [def MIN MAX] [TEXT KEY CMD]... — FV
# `Init(Bounds, ADefs)`: TView's (corners, B exclusive), then ofPreProcess,
# EventMask + evBroadcast, GrowMode gfGrowLoY + gfGrowHiX + gfGrowHiY, the
# defs, FindItems. The list after the bounds is FV's NewStatusDef /
# NewStatusKey chain written flat: `def MIN MAX` opens a def (FV
# NewStatusDef(MIN, MAX, …)), each triple TEXT KEY CMD is an item of the def
# above it (FV NewStatusKey(TEXT, KEY, CMD, …)); triples before any `def`
# go into an implicit `def 0 65535`. rc 2 and one Error line for a malformed
# list (checked before anything is made, as TView's bounds are: NAME is then
# no view); the TView part's refusals (re-creation, reserved names, bounds)
# as fv.views.
class TStatusLine : TView
    public
        constructor Create
        nofields destructor Done
        nofields override proc Draw
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields func Hint
        nofields proc Update
        nofields proc AddDef
        nofields proc AddItem
end
TStatusLine.Create() {
    local -a __fvm_dn=() __fvm_dx=() __fvm_df=() __fvm_it=() __fvm_ik=() __fvm_ic=()
    # (a live name: TView's part repairs it and refuses; nothing parsed)
    if [[ -z ${__FV_VW_LIVE[$this]-} ]]; then fv.menus._parse "$this" "${@:5}" || return; fi
    inherited
    if [[ -z ${__FV_VW_LIVE[$this]-} ]]; then
        if [[ -n ${__FV_MN_CUR[$this]+x} ]]; then fv.menus._free "$this"; fi
        return "$__FV_VW_CRC"
    fi
    fv.menus._create "$this"
}
TStatusLine.Done() { fv.menus._free "$this"; inherited; }
TStatusLine.Draw() { fv.menus._draw "$this" || return; }
TStatusLine.HandleEvent() { fv.menus._event "$this" "$@" || return; }
TStatusLine.GetPalette() { fv.menus._getPalette "$this" || return; }
TStatusLine.Hint() { fv.menus._hint "$this" "$@" || return; }
TStatusLine.Update() { fv.menus._update "$this" || return; }
TStatusLine.AddDef() { fv.menus.addDef "$this" "$@" || return; }
TStatusLine.AddItem() { fv.menus.addItem "$this" "$@" || return; }
build TStatusLine

# fv.menus._register — TStatusLine's built-in bodies into fv.views' elision
# table (fv.views merges the table on a reload; the constructor registers
# them again only if they are missing)
fv.menus._register() {
    __FV_VW_IMPL[TStatusLine.Draw]=fv.menus._draw
    __FV_VW_IMPL[TStatusLine.HandleEvent]=fv.menus._event
    __FV_VW_IMPL[TStatusLine.GetPalette]=fv.menus._getPalette
    __FV_VW_IMPL[TStatusLine.Hint]=fv.menus._hint
    __FV_VW_IMPL[TStatusLine.Update]=fv.menus._update
}
fv.menus._register

# ---- helpers --------------------------------------------------------------------
# fv.menus._err MSG — one `Error: fv.menus: MSG` line on stderr unless
# VERBOSE_KKLASS=quiet (the constructor's loud refusal)
fv.menus._err() {
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then printf 'Error: fv.menus: %s\n' "$1" >&2; fi
    return 0
}
# fv.menus._bad CALLER MSG — a malformed call: RESULT='', a debug line, rc 2
fv.menus._bad() {
    RESULT=''
    kk.debug "Error: fv.menus.$1: $2"
    return 2
}
# fv.menus._sl SL CALLER — rc 0 for a live TStatusLine; else _bad's rc 2
fv.menus._sl() {
    if [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} && -n ${__FV_MN_CUR[$1]+x} ]]; then return 0; fi
    fv.menus._bad "$2" "'$1' is not a status line (TStatusLine)"
}
# fv.menus._num VALUE — rc 0 for a HelpCtx bound: 1-9 plain digits (leading
# zeros decimal; FV's Word, 0..65535 in practice)
fv.menus._num() {
    [[ -n $1 && $1 != *[!0123456789]* && ${#1} -le 9 ]]
}
# fv.menus._item TEXT KEY CMD — rc 0 for a valid item: KEY '' or a key name
# (kb + letters / digits, fv.keyboard's names: kbF10, kbAltX), CMD a command
# name (letters, digits, _); else the caller's __fvm_e = why
fv.menus._item() {
    if [[ -n $2 ]] && { ! [ "${2:0:2}" = kb ] || [[ ${#2} -lt 3 || ${2:2} == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]* ]]; }; then
        __fvm_e="'$2' is not a key name (kbF10, kbAltX, ... or '' for none)"; return 1
    fi
    if [[ -z $3 || $3 == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* ]]; then
        __fvm_e="'$3' is not a command name (letters, digits, _)"; return 1
    fi
}

# fv.menus._parse SL ARGS... — the constructor's list into the caller's
# __fvm_dn / __fvm_dx / __fvm_df (each def's MIN, MAX, first item) and
# __fvm_it / __fvm_ik / __fvm_ic (the items); rc 2 and one Error line for a
# malformed list. `def` followed by two HelpCtx numbers opens a def (a
# triple whose TEXT is `def` has a key name or '' second, so it never reads
# as one); triples before any def: an implicit `def 0 65535`
fv.menus._parse() {
    local __fvm_s=$1 __fvm_e=''
    shift
    while (( $# )); do
        if (( $# >= 3 )) && [ "$1" = def ] && fv.menus._num "$2" && fv.menus._num "$3"; then
            __fvm_dn+=("$(( 10#$2 ))") __fvm_dx+=("$(( 10#$3 ))") __fvm_df+=("${#__fvm_it[@]}")
            shift 3
            continue
        fi
        if (( $# < 3 )); then
            fv.menus._err "TStatusLine.Create: '$__fvm_s': the items come as triples TEXT KEY CMD (left over: $*)"
            return 2
        fi
        if ! fv.menus._item "$1" "$2" "$3"; then
            fv.menus._err "TStatusLine.Create: '$__fvm_s': item '$1': $__fvm_e"
            return 2
        fi
        if (( ! ${#__fvm_dn[@]} )); then __fvm_dn=(0) __fvm_dx=(65535) __fvm_df=(0); fi
        __fvm_it+=("$1") __fvm_ik+=("$2") __fvm_ic+=("$3")
        shift 3
    done
}

# fv.menus._create SL — FV TStatusLine.Init after TView's part: the options,
# the mask, the grow mode, the arrays from the parsed list, FindItems
fv.menus._create() {
    local -n __fvm_d=${1}_data
    local __fvm_i __fvm_j
    if [[ -z ${__FV_VW_IMPL[TStatusLine.Draw]-} ]]; then fv.menus._register; fi
    __fvm_d[Options]=$(( ${__fvm_d[Options]:-0} | FV_OF_PREPROCESS ))
    __fvm_d[EventMask]=$(( ${__fvm_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __fvm_d[GrowMode]=$(( FV_GF_GROWLOY | FV_GF_GROWHIX | FV_GF_GROWHIY ))
    declare -ga "${1}_sdmin=()" "${1}_sdmax=()" "${1}_sdfirst=()" "${1}_sitext=()" "${1}_sikey=()" \
        "${1}_sicmd=()" "${1}_sinext=()" "${1}_siplain=()" "${1}_sipat=()"
    declare -gA "${1}_skey=()" "${1}_hints=()"
    __FV_MN_CUR[$1]=-1 __FV_MN_GREY[$1]='' __FV_MN_HINT[$1]='' __FV_MN_AM[$1]=''
    local -n __fvm_dn0=${1}_sdmin __fvm_dx0=${1}_sdmax __fvm_df0=${1}_sdfirst
    __fvm_dn0=("${__fvm_dn[@]}") __fvm_dx0=("${__fvm_dx[@]}") __fvm_df0=("${__fvm_df[@]}")
    __fvm_j=0
    for (( __fvm_i = 0; __fvm_i < ${#__fvm_it[@]}; __fvm_i++ )); do
        # (the def of item i: the last def whose first item is <= i)
        while (( __fvm_j + 1 < ${#__fvm_df[@]} && __fvm_df[__fvm_j + 1] <= __fvm_i )); do __fvm_j=$(( __fvm_j + 1 )); done
        fv.menus._push "$1" "$__fvm_j" "${__fvm_it[__fvm_i]}" "${__fvm_ik[__fvm_i]}" "${__fvm_ic[__fvm_i]}"
    done
    fv.menus._findItems "$1"
}

# fv.menus._push SL DEF TEXT KEY CMD — append an item (to def DEF, the last
# def) and link it into DEF's key map
fv.menus._push() {
    local -n __fvm_t=${1}_sitext __fvm_k=${1}_sikey __fvm_c=${1}_sicmd __fvm_n=${1}_sinext __fvm_m=${1}_skey
    local __fvm_j=${#__fvm_t[@]} __fvm_q
    __fvm_t+=("$3") __fvm_k+=("$4") __fvm_c+=("$5") __fvm_n+=(-1)
    if [[ -n $4 ]]; then
        __fvm_q=${__fvm_m["$2:$4"]-}
        if [[ -z $__fvm_q ]]; then
            __fvm_m["$2:$4"]=$__fvm_j
        else
            while (( __fvm_n[__fvm_q] >= 0 )); do __fvm_q=${__fvm_n[__fvm_q]}; done
            __fvm_n[__fvm_q]=$__fvm_j
        fi
    fi
    __FV_MN_AM[$1]=''
}

# fv.menus._free SL — the status line's own arrays and entries (kcl §1.9)
fv.menus._free() {
    unset "${1}_sdmin" "${1}_sdmax" "${1}_sdfirst" "${1}_sitext" "${1}_sikey" "${1}_sicmd" \
        "${1}_sinext" "${1}_siplain" "${1}_sipat" "${1}_skey" "${1}_hints" \
        '__FV_MN_CUR[$1]' '__FV_MN_GREY[$1]' '__FV_MN_HINT[$1]' '__FV_MN_AM[$1]'
    return 0
}

# fv.menus._findItems SL — FV FindItems: CUR = the first def whose range
# holds the line's HelpCtx (FV: Min <= HelpCtx <= Max), -1 when none
fv.menus._findItems() {
    local -n __fvm_d=${1}_data __fvm_dn=${1}_sdmin __fvm_dx=${1}_sdmax
    local __fvm_h=${__fvm_d[HelpCtx]:-0} __fvm_i
    if [[ $__fvm_h == *[!0123456789]* || ${#__fvm_h} -gt 9 ]]; then __fvm_h=0; fi
    __fvm_h=$(( 10#$__fvm_h ))
    for (( __fvm_i = 0; __fvm_i < ${#__fvm_dn[@]}; __fvm_i++ )); do
        if (( __fvm_h >= __fvm_dn[__fvm_i] && __fvm_h <= __fvm_dx[__fvm_i] )); then __FV_MN_CUR[$1]=$__fvm_i; return 0; fi
    done
    __FV_MN_CUR[$1]=-1
}

# fv.menus._range SL — the caller's __fvm_a / __fvm_z = the current def's
# items [a, z) (empty when none)
fv.menus._range() {
    local -n __fvm_df=${1}_sdfirst __fvm_t=${1}_sitext
    local __fvm_c=${__FV_MN_CUR[$1]:--1}
    __fvm_a=0 __fvm_z=0
    if (( __fvm_c < 0 || __fvm_c >= ${#__fvm_df[@]} )); then return 0; fi
    __fvm_a=${__fvm_df[__fvm_c]}
    if (( __fvm_c + 1 < ${#__fvm_df[@]} )); then __fvm_z=${__fvm_df[__fvm_c + 1]}; else __fvm_z=${#__fvm_t[@]}; fi
}

# fv.menus._pats SL — every item's drawn text and cell pattern for the
# screen's ASCII mode (fv.menus._pat1 per text)
fv.menus._pats() {
    local -n __fvm_t=${1}_sitext __fvm_pl=${1}_siplain __fvm_pp=${1}_sipat
    local __fvm_j __fvm_s __fvm_p __fvm_rr=${RESULT-}
    __fvm_pl=() __fvm_pp=()
    for (( __fvm_j = 0; __fvm_j < ${#__fvm_t[@]}; __fvm_j++ )); do
        fv.menus._pat1 "${__fvm_t[__fvm_j]}"
        __fvm_pl+=("$__fvm_s") __fvm_pp+=("$__fvm_p")
    done
    __FV_MN_AM[$1]=${FV_VIDEO_ASCII:-0}
    RESULT=$__fvm_rr
}
# fv.menus._pat1 TEXT — the caller's __fvm_s = ' TEXT ' as drawn (without
# the `~`) and __fvm_p = its cell pattern: one character per display cell,
# `+` for FV's Lo colour and `-` for the Hi one (the `~` parts). FV CStrLen /
# CTextWidth: `~` takes no cell; a wide character 2 cells (fv.video's width
# table; in ASCII mode 1). A text whose parts measure differently from the
# whole (a cluster cut by a `~`) is drawn in Lo only. RESULT is clobbered
fv.menus._pat1() {
    local __fvm_r __fvm_h=0 __fvm_m __fvm_x=" $1 "
    __fvm_p=''
    while :; do
        __fvm_r=${__fvm_x%%'~'*}
        if [[ -n $__fvm_r ]]; then
            fv.video.strWidth "$__fvm_r" || RESULT=${#__fvm_r}
            printf -v __fvm_m '%*s' "$RESULT" ''
            if (( __fvm_h )); then __fvm_p+=${__fvm_m// /-}; else __fvm_p+=${__fvm_m// /+}; fi
        fi
        if [ "$__fvm_r" = "$__fvm_x" ]; then break; fi
        __fvm_x=${__fvm_x#*'~'} __fvm_h=$(( ! __fvm_h ))
    done
    __fvm_s=" ${1//'~'/} "
    fv.video.strWidth "$__fvm_s" || RESULT=${#__fvm_s}
    if (( ${#__fvm_p} != RESULT )); then printf -v __fvm_p '%*s' "$RESULT" ''; __fvm_p=${__fvm_p// /+}; fi
}

# ---- drawing (FV Draw / DrawSelect; design §1.5: one composed write) ------------------

# TStatusLine.Draw — FV: DrawSelect(nil). Only as the painter's current view
# (as every built-in Draw: V.Draw outside the painter draws nothing)
fv.menus._draw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    fv.menus._compose "$1" -1
}
# fv.menus._paintSel SL SEL — the drawPart painter of the press tracking:
# the line with item SEL pressed (-1: none)
fv.menus._paintSel() { fv.menus._compose "$1" "$2"; }

# fv.menus._compose SL SEL — FV DrawSelect(Selected): the current def's items
# that have a text, each ' TEXT ' with its `~` parts in the Hi colour, in
# CNormal (palette 1 / 3), CSelect (4 / 6, the pressed one), CNormDisabled
# (2) or CSelDisabled (5) by CommandEnabled; then, when Hint(HelpCtx) is not
# '', `│` (ASCII mode: `|`), a blank and the hint in colour 1; blanks in
# colour 1 to the width. ONE fv.views.writeLine for the row (FV WriteLine of
# its TDrawBuffer); a line taller than one row gets the rows below blanked
# by one fill ("Draw must cover its rect"; FV writes row 0 only). Records
# what was drawn (GREY, HINT)
fv.menus._compose() {
    local -n __fvm_d=${1}_data __fvm_c=${1}_sicmd __fvm_t=${1}_sitext __fvm_pl=${1}_siplain __fvm_pp=${1}_sipat
    local __fvm_a __fvm_z __fvm_j __fvm_lo __fvm_hi __fvm_p __fvm_x='' __fvm_y='' __fvm_g='' __fvm_h __fvm_w
    local __fvm_n1 __fvm_n2 __fvm_n3 __fvm_s4 __fvm_s5 __fvm_s6 __fvm_e=$__FV_VW_ERRSYM __fvm_rr=${RESULT-}
    local __fvm_sx=${__fvm_d[SizeX]:-0} __fvm_sy=${__fvm_d[SizeY]:-0}
    if ! [ "${__FV_MN_AM[$1]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._pats "$1"; fi
    __fvm_p=$FV_DRAW_PAL
    __fvm_n1=${__fvm_p:0:1} __fvm_n2=${__fvm_p:1:1} __fvm_n3=${__fvm_p:2:1}
    __fvm_s4=${__fvm_p:3:1} __fvm_s5=${__fvm_p:4:1} __fvm_s6=${__fvm_p:5:1}
    __fvm_n1=${__fvm_n1:-$__fvm_e} __fvm_n2=${__fvm_n2:-$__fvm_e} __fvm_n3=${__fvm_n3:-$__fvm_e}
    __fvm_s4=${__fvm_s4:-$__fvm_e} __fvm_s5=${__fvm_s5:-$__fvm_e} __fvm_s6=${__fvm_s6:-$__fvm_e}
    fv.menus._range "$1"
    for (( __fvm_j = __fvm_a; __fvm_j < __fvm_z; __fvm_j++ )); do
        if [[ -z ${__fvm_t[__fvm_j]} ]]; then continue; fi
        if [[ -z ${__FV_VW_CMDOFF[${__fvm_c[__fvm_j]}]-} ]]; then
            __fvm_g+=1
            if (( __fvm_j == $2 )); then __fvm_lo=$__fvm_s4 __fvm_hi=$__fvm_s6; else __fvm_lo=$__fvm_n1 __fvm_hi=$__fvm_n3; fi
        else
            __fvm_g+=0
            if (( __fvm_j == $2 )); then __fvm_lo=$__fvm_s5 __fvm_hi=$__fvm_s5; else __fvm_lo=$__fvm_n2 __fvm_hi=$__fvm_n2; fi
        fi
        __fvm_p=${__fvm_pp[__fvm_j]}
        __fvm_p=${__fvm_p//+/$__fvm_lo}
        __fvm_x+=${__fvm_pl[__fvm_j]} __fvm_y+=${__fvm_p//-/$__fvm_hi}
    done
    RESULT=''
    fv.views._virt "$1" Hint "${__fvm_d[HelpCtx]:-0}" || RESULT=''
    __fvm_h=${RESULT-}
    if [[ -n $__fvm_h ]]; then
        if [ "${FV_VIDEO_ASCII:-0}" = 1 ]; then __fvm_x+='| '; else __fvm_x+='│ '; fi
        fv.video.strWidth "$__fvm_h" || RESULT=${#__fvm_h}
        __fvm_x+=$__fvm_h
        printf -v __fvm_w '%*s' "$(( RESULT + 2 ))" ''
        __fvm_y+=${__fvm_w// /$__fvm_n1}
    fi
    if (( ${#__fvm_y} < __fvm_sx )); then
        printf -v __fvm_w '%*s' "$(( __fvm_sx - ${#__fvm_y} ))" ''
        __fvm_x+=$__fvm_w __fvm_y+=${__fvm_w// /$__fvm_n1}
    fi
    fv.views.writeLine 0 0 1 "$__fvm_x" "$__fvm_y" || :
    if (( __fvm_sy > 1 )); then fv.views.fill 0 1 "$__fvm_sx" "$(( __fvm_sy - 1 ))" ' ' 1 || :; fi
    __FV_MN_GREY[$1]=$__fvm_g __FV_MN_HINT[$1]=$__fvm_h
    RESULT=$__fvm_rr
    return 0
}

# fv.menus._grey SL — the caller's __fvm_g = the enabled signature of the
# current items that have a text (what _compose records)
fv.menus._grey() {
    local -n __fvm_c=${1}_sicmd __fvm_t=${1}_sitext
    local __fvm_a __fvm_z __fvm_j
    __fvm_g=''
    fv.menus._range "$1"
    for (( __fvm_j = __fvm_a; __fvm_j < __fvm_z; __fvm_j++ )); do
        if [[ -z ${__fvm_t[__fvm_j]} ]]; then continue; fi
        if [[ -z ${__FV_VW_CMDOFF[${__fvm_c[__fvm_j]}]-} ]]; then __fvm_g+=1; else __fvm_g+=0; fi
    done
}

# TStatusLine.GetPalette (func) — FV CStatusLine #2#3#4#5#6#7: normal text,
# disabled text, normal shortcut, selected text, selected disabled, selected
# shortcut (CAppColor entries 2..7)
fv.menus._getPalette() { RESULT='2 3 4 5 6 7'; }
# TStatusLine.Hint HELPCTX (func) — FV: '' (a class of yours answers the text
# shown after the items for a help context); here the line's hint table
# (fv.menus.setHint, D22): its text for HELPCTX, '' when it has none
fv.menus._hint() {
    if [[ -z ${2-} || $2 == *[!0123456789]* || ${#2} -gt 9 ]]; then RESULT=''; return 0; fi
    local -n __fvm_ht=${1}_hints
    RESULT=${__fvm_ht[$(( 10#$2 ))]-}
}

# ---- events (FV TStatusLine.HandleEvent, Update) ------------------------------------

# TStatusLine.HandleEvent — FV: TView's first (click to focus: a status line
# is not selectable), then
#   * evMouseDown: the press tracking (fv.menus._track): the item under the
#     pointer drawn pressed while the button is held; released on an item
#     whose command is enabled -> that command posted (PutEvent); handled;
#   * evKeyDown: the first item of the current def with the key whose command
#     is enabled -> evCommand CMD posted (PutEvent), the key handled
#     (ClearEvent); none: the key goes on (the line has ofPreProcess, so it
#     sees keys before the focused view);
#   * evBroadcast cmCommandSetChanged: redrawn when the greyed state of its
#     items changed (FV redraws always; the pixels are the same). Not handled:
#     the broadcast goes on to the others.
fv.menus._event() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        local -n __fvm_c=${1}_sicmd __fvm_n=${1}_sinext __fvm_m=${1}_skey
        local __fvm_j
        if [[ -z $FV_EV_KEY ]]; then return 0; fi
        __fvm_j=${__fvm_m["${__FV_MN_CUR[$1]:--1}:$FV_EV_KEY"]-}
        while [[ -n $__fvm_j ]] && (( __fvm_j >= 0 )); do
            if [[ -z ${__FV_VW_CMDOFF[${__fvm_c[__fvm_j]}]-} ]]; then
                fv.menus._post "$1" "${__fvm_c[__fvm_j]}"
                return 0
            fi
            __fvm_j=${__fvm_n[__fvm_j]}
        done
    elif [ "$FV_EV_WHAT" = evBroadcast ]; then
        if [ "$FV_EV_COMMAND" = cmCommandSetChanged ]; then
            local __fvm_g
            fv.menus._grey "$1"
            if ! [ "$__fvm_g" = "${__FV_MN_GREY[$1]-}" ]; then fv.views.drawView "$1" || :; fi
        fi
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.menus._track "$1"; fi
    fi
    return 0
}

# fv.menus._post SL CMD — FV: Event.What := evCommand, Command := CMD,
# InfoPtr := nil; PutEvent(Event); ClearEvent(Event). The posted event has
# the other fields cleared (FV's record overlays Command on the key and the
# mouse fields); the current one is handled by SL
fv.menus._post() {
    fv.drivers.clearEvent
    FV_EV_WHAT=evCommand FV_EV_COMMAND=$2 FV_EV_INFO=''
    "$__FV_VW_PUTEVENT" || :
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}

# fv.menus._hit SL X Y — the caller's __fvm_tt = the item with a text under
# the local point (FV ItemMouseIsIn: ' TEXT ' cells from the left), -1 for
# none; the point must lie in the view (FV accepts Y 0..1 and any X)
fv.menus._hit() {
    local -n __fvm_d=${1}_data __fvm_t=${1}_sitext __fvm_pp=${1}_sipat
    local __fvm_a __fvm_z __fvm_j __fvm_x0=0 __fvm_x1
    __fvm_tt=-1
    if (( $2 < 0 || $3 < 0 || $2 >= ${__fvm_d[SizeX]:-0} || $3 >= ${__fvm_d[SizeY]:-0} )); then return 0; fi
    if ! [ "${__FV_MN_AM[$1]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._pats "$1"; fi
    fv.menus._range "$1"
    for (( __fvm_j = __fvm_a; __fvm_j < __fvm_z; __fvm_j++ )); do
        if [[ -z ${__fvm_t[__fvm_j]} ]]; then continue; fi
        __fvm_x1=$(( __fvm_x0 + ${#__fvm_pp[__fvm_j]} ))
        if (( $2 >= __fvm_x0 && $2 < __fvm_x1 )); then __fvm_tt=$__fvm_j; return 0; fi
        __fvm_x0=$__fvm_x1
    done
}

# fv.menus._track SL — FV's evMouseDown loop: repeat (the item under the
# pointer; drawn pressed when it changed: DrawSelect through drawPart, no
# dispatch) until NOT MouseEvent(Event, evMouseMove); the event record is
# saved first and put back after the loop (the inner loop's events are its
# own: design §2.2); then a released item whose command is enabled posts
# it; the event is handled (ClearEvent) and, when an item was drawn pressed,
# the line drawn plain again (DrawSelect(nil)). The loop reads events through
# fv.views.mouseEvent (__FV_VW_GETEVENT): the end of input ends it (latched)
# and then posts nothing
fv.menus._track() {
    local -n __fvm_d=${1}_data __fvm_c=${1}_sicmd
    local __fvm_t=-1 __fvm_tt __fvm_q=0 __fvm_cmd='' __fvm_z=0
    local -a __fvm_es=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF" "${FV_EV_BASE-}")
    while :; do
        if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then __fvm_t=-1; break; fi
        fv.views.makeLocal "$1" "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" || { __fvm_t=-1; break; }
        fv.menus._hit "$1" "$FV_POINT_X" "$FV_POINT_Y"
        if (( __fvm_tt != __fvm_t )); then
            fv.views.drawPart "$1" fv.menus._paintSel 0 "${__fvm_d[SizeY]:-1}" "$__fvm_tt" || :
            __fvm_q=1
        fi
        __fvm_t=$__fvm_tt
        fv.views.mouseEvent "$1" "$FV_EM_MOUSEMOVE" || break
    done
    if (( __FV_VW_EOF )) && [ "$FV_EV_WHAT" = evNothing ]; then __fvm_z=1; fi
    FV_EV_WHAT=${__fvm_es[0]} FV_EV_KEY=${__fvm_es[1]} FV_EV_CHAR=${__fvm_es[2]} FV_EV_COMMAND=${__fvm_es[3]}
    FV_EV_ID=${__fvm_es[4]} FV_EV_INFO=${__fvm_es[5]} FV_EV_MOUSE_X=${__fvm_es[6]} FV_EV_MOUSE_Y=${__fvm_es[7]}
    FV_EV_MOUSE_BUTTONS=${__fvm_es[8]} FV_EV_MOUSE_MODS=${__fvm_es[9]} FV_EV_MOUSE_DOUBLE=${__fvm_es[10]}
    FV_EV_MOUSE_TRIPLE=${__fvm_es[11]} FV_EV_WHEEL=${__fvm_es[12]} FV_EV_EOF=${__fvm_es[13]} FV_EV_BASE=${__fvm_es[14]-}
    if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then FV_EV_WHAT=evNothing FV_EV_INFO=$1; return 0; fi
    if (( __fvm_t >= 0 && ! __fvm_z )); then __fvm_cmd=${__fvm_c[__fvm_t]}; fi
    if [[ -n $__fvm_cmd && -z ${__FV_VW_CMDOFF[$__fvm_cmd]-} ]]; then fv.menus._post "$1" "$__fvm_cmd"
    else FV_EV_WHAT=evNothing FV_EV_INFO=$1; fi
    # (DrawSelect(nil): only when the last drawing showed an item pressed)
    if (( __fvm_q && __fvm_t >= 0 )); then fv.views.drawPart "$1" fv.menus._paintSel 0 "${__fvm_d[SizeY]:-1}" -1 || :; fi
    return 0
}

# TStatusLine.Update — FV: H := TopView's GetHelpCtx (hcNoContext without a
# top view); when H differs from the line's HelpCtx: HelpCtx := H,
# FindItems, DrawView. Called on every idle tick (fv.app's Idle, design
# §2.1), so the unchanged case is a few array reads and the GetHelpCtx chain
# (no dispatch unless a class on it overrides GetHelpCtx). D17: a changed
# HelpCtx redraws only when what the built-in Draw shows changed (another
# def, or another Hint); a class that overrides Draw is redrawn on every
# change, as in FV
fv.menus._update() {
    local -n __fvm_d=${1}_data
    local __fvw_t __fvm_h=$FV_HC_NOCONTEXT __fvm_o __fvm_rr=${RESULT-}
    fv.views._topView "$1"
    if [[ -n $__fvw_t ]]; then
        RESULT=''
        if fv.views._virt "$__fvw_t" GetHelpCtx; then __fvm_h=${RESULT-}; fi
        if [[ -z $__fvm_h || $__fvm_h == *[!0123456789]* || ${#__fvm_h} -gt 9 ]]; then __fvm_h=$FV_HC_NOCONTEXT; fi
        __fvm_h=$(( 10#$__fvm_h ))
    fi
    RESULT=$__fvm_rr
    if [ "$__fvm_h" = "${__fvm_d[HelpCtx]-}" ]; then return 0; fi
    __fvm_d[HelpCtx]=$__fvm_h
    __fvm_o=${__FV_MN_CUR[$1]-}
    fv.menus._findItems "$1"
    fv.menus._changed "$1" "$__fvm_o"
    RESULT=$__fvm_rr
}

# fv.menus._changed SL OLDCUR — after the items or the HelpCtx changed:
# drawView when the built-in Draw would show something else (another def,
# another Hint, nothing drawn yet) or the class overrides Draw
fv.menus._changed() {
    local __fvm_o=${1}_class
    __fvm_o="${!__fvm_o-}_class_method_owner[Draw]"
    if [ "${__FV_VW_IMPL[${!__fvm_o-}.Draw]-}" = fv.menus._draw ] && [ "$2" = "${__FV_MN_CUR[$1]-}" ] && [[ -n ${__FV_MN_GREY[$1]-} ]]; then
        local -n __fvm_cd=${1}_data
        RESULT=''
        fv.views._virt "$1" Hint "${__fvm_cd[HelpCtx]:-0}" || RESULT=''
        if [ "${RESULT-}" = "${__FV_MN_HINT[$1]-}" ]; then return 0; fi
    fi
    fv.views.drawView "$1" || :
}

# ---- the plain API ------------------------------------------------------------------

# fv.menus.addDef SL MIN MAX — FV NewStatusDef(MIN, MAX, …) appended after
# the line's defs (FindItems takes the first def whose range holds the
# HelpCtx); the items that follow go into it. RESULT is kept. The line is
# redrawn when what it shows changed
fv.menus.addDef() {
    if (( $# != 3 )); then fv.menus._bad "${FUNCNAME#fv.menus.}" 'wrong argument count'; return; fi
    fv.menus._sl "$1" addDef || return
    if ! fv.menus._num "$2" || ! fv.menus._num "$3"; then fv.menus._bad addDef 'MIN MAX must be HelpCtx numbers (digits)'; return; fi
    local -n __fvm_dn=${1}_sdmin __fvm_dx=${1}_sdmax __fvm_df=${1}_sdfirst __fvm_t=${1}_sitext
    local __fvm_o=${__FV_MN_CUR[$1]-} __fvm_rr=${RESULT-}
    __fvm_dn+=("$(( 10#$2 ))") __fvm_dx+=("$(( 10#$3 ))") __fvm_df+=("${#__fvm_t[@]}")
    fv.menus._findItems "$1"
    if ! [ "$__fvm_o" = "${__FV_MN_CUR[$1]}" ]; then fv.views.drawView "$1" || :; fi
    RESULT=$__fvm_rr
}

# fv.menus.addItem SL TEXT KEY CMD — FV NewStatusKey(TEXT, KEY, CMD, …)
# appended to the LAST def (an implicit `def 0 65535` when there is none):
# TEXT '' = a key-only binding (not drawn), KEY '' = a click-only item; `~`
# marks the highlighted part of TEXT. RESULT is kept. The line is redrawn
# when the item belongs to the def it shows
fv.menus.addItem() {
    if (( $# != 4 )); then fv.menus._bad "${FUNCNAME#fv.menus.}" 'wrong argument count'; return; fi
    fv.menus._sl "$1" addItem || return
    local __fvm_e='' __fvm_rr=${RESULT-} __fvm_o=${__FV_MN_CUR[$1]-}
    if ! fv.menus._item "$2" "$3" "$4"; then fv.menus._bad addItem "$__fvm_e"; return; fi
    local -n __fvm_dn=${1}_sdmin __fvm_dx=${1}_sdmax __fvm_df=${1}_sdfirst __fvm_t=${1}_sitext
    if (( ! ${#__fvm_dn[@]} )); then
        __fvm_dn=(0) __fvm_dx=(65535) __fvm_df=("${#__fvm_t[@]}")
        fv.menus._findItems "$1"
    fi
    fv.menus._push "$1" "$(( ${#__fvm_dn[@]} - 1 ))" "$2" "$3" "$4"
    # (a key-only item shows nothing: no redraw for it)
    if ! [ "$__fvm_o" = "${__FV_MN_CUR[$1]}" ] || { [[ -n $2 ]] && (( ${__FV_MN_CUR[$1]} == ${#__fvm_dn[@]} - 1 )); }; then
        fv.views.drawView "$1" || :
    fi
    RESULT=$__fvm_rr
}

# fv.menus.update SL — FV Update through the elision (an override of yours
# runs): fv.app's Idle calls it on every idle tick. RESULT is kept; rc 0
fv.menus.update() {
    if (( $# != 1 )); then fv.menus._bad "${FUNCNAME#fv.menus.}" 'wrong argument count'; return; fi
    fv.menus._sl "$1" update || return
    fv.views._virt "$1" Update || :
    return 0
}

# fv.menus.setHint SL HELPCTX TEXT — the status line's hint table (D22): the
# built-in Hint answers TEXT for HELPCTX (digits; FV's Word); TEXT '' removes
# the entry. A class of yours that overrides Hint still wins. RESULT is kept;
# the line is redrawn when it shows that context and the hint changed
fv.menus.setHint() {
    if (( $# != 3 )); then fv.menus._bad "${FUNCNAME#fv.menus.}" 'wrong argument count'; return; fi
    fv.menus._sl "$1" setHint || return
    if ! fv.menus._num "$2"; then fv.menus._bad setHint 'HELPCTX must be a number (digits)'; return; fi
    local __fvm_rr=${RESULT-} __fvm_c=$(( 10#$2 ))
    if ! declare -p "${1}_hints" >/dev/null 2>&1; then declare -gA "${1}_hints=()"; fi
    local -n __fvm_ht=${1}_hints __fvm_hd=${1}_data
    if [[ -n $3 ]]; then __fvm_ht[$__fvm_c]=$3; else unset '__fvm_ht[$__fvm_c]'; fi
    if [ "${__fvm_hd[HelpCtx]-}" = "$__fvm_c" ]; then fv.menus._changed "$1" "${__FV_MN_CUR[$1]-}"; fi
    RESULT=$__fvm_rr
}

# ---- menus (P3 stage 3f, D22 / D23; FV menus.inc TMenuView, TMenuBar,
# TMenuBox, TMenuPopup) ---------------------------------------------------------
# Per menu view (keyed by its name), kept across a reload:
#   MV[v]    view / bar / box / pop: a live menu view of this unit (its kind)
#   OWN[o]   1: o owns ITEM ARRAYS (it was made with an item list: a bar, a
#            popup, any menu view made with one); a box from newSubView
#            borrows its parent's: its Menu field names the owner and the
#            submenu ("OWNER:S", FV's PMenu)
#   MG[v]    the enabled signature of v's items as last drawn ('' = not yet)
#   SH[v]    the item shown highlighted on the screen (-1 = none)
#   SUB[v]   1 for a box made by newSubView (removed and destroyed after its
#            run: its last plain redraw is left out)
#   MAM[o]   the ASCII mode o's item patterns were made in ('' = to be made)
#   RES      the command the last built-in Execute answered ('' = none, FV's
#            0): execView answers cmCancel for '' (its rule), so the menus
#            read this right after their own execView calls
#   HREF / HPAR  newSubView's hand-off to TMenuBox.Create (menu, parent)
#   RUN[v]   how many of v's built-in Execute calls are running (set after
#            the subshell check, cleared on its one way out): menuBar refuses then
# The item arrays of an owner o (FV's TMenuItem / TMenu records, flat; the
# items of one submenu are contiguous, submenu 0 is the top menu):
#   ${o}_mtext ${o}_mparam ${o}_mkey ${o}_mcmd ${o}_mhelp
#                    item i's Name ('' = a NewLine separator), Param, KeyCode
#                    ('' = none), Command ('' for a submenu or a line), HelpCtx
#   ${o}_msub        the submenu of a NewSubMenu item ('' for the others)
#   ${o}_mdis        FV's Disabled (0 / 1): set from the command set at the
#                    start and by cmCommandSetChanged (FV UpdateMenu)
#   ${o}_mfirst ${o}_mlast ${o}_mdef
#                    submenu s's first and last item (first > last: empty)
#                    and its Default (FV TMenu.Default; -1 = none)
#   ${o}_mkmap (assoc) + ${o}_mknext
#                    the KEY MAP: KEY -> the first item of the tree from
#                    submenu 0 (FV HotKey's depth-first order) with that
#                    KeyCode; next[i] = the next one with the same key (-1:
#                    none); a view on another submenu walks its own subtree
#                    (fv.menus._hkSub)
#   ${o}_mhot (assoc) + ${o}_mhnext
#                    the HOT LETTERS: "S:L" -> the first item of submenu S whose
#                    hot letter (the character after its first `~`, folded,
#                    any script) is L; next[i] the next one (-1: none)
#   ${o}_mpl ${o}_mpp ${o}_mqpl ${o}_mqpp
#                    ' NAME ' as drawn and its cell pattern (fv.menus._pat1),
#                    the Param as drawn and its pattern; made for MAM's mode
declare -gA __FV_MN_MV __FV_MN_OWN __FV_MN_MG __FV_MN_SH __FV_MN_SUB __FV_MN_MAM __FV_MN_RUN
__FV_MN_MV+=() __FV_MN_OWN+=() __FV_MN_MG+=() __FV_MN_SH+=() __FV_MN_SUB+=() __FV_MN_MAM+=() __FV_MN_RUN+=()
declare -g __FV_MN_RES=${__FV_MN_RES-} __FV_MN_HREF='' __FV_MN_HPAR=''

# TMenuView.new NAME AX AY BX BY [LIST] — FV TMenuView.Init(Bounds):
# TView's, EventMask + evBroadcast; ParentMenu '', Current / OldItem -1.
# LIST (FV's NewSubMenu / NewItem / NewLine chain written flat, as the status
# line's items):
#   item TEXT PARAM KEY CMD HELPCTX   FV NewItem(Name, Param, KeyCode,
#                                     Command, HelpCtx)
#   line                              FV NewLine
#   sub TEXT [HELPCTX] ... end        FV NewSubMenu(Name, HelpCtx, NewMenu(…))
# KEY '' or a key name, CMD a command name, HELPCTX digits ('' = 0); the
# view then owns the items (Menu "NAME:0"). A malformed list: rc 2, one Error
# line, nothing made
class TMenuView : TView
    public
        var ParentMenu
        var Menu
        var Current
        var OldItem
        constructor Create
        nofields destructor Done
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields override func GetHelpCtx
        nofields override func Execute
        nofields proc GetItemRect
end
TMenuView.Create() {
    local __fvm_ref=$__FV_MN_HREF __fvm_cn=${this}_class
    local -a __fvm_tt=() __fvm_tp=() __fvm_tk=() __fvm_tc=() __fvm_th=() __fvm_ts=() __fvm_sl=()
    __FV_MN_HREF=''
    __fvm_cn=${!__fvm_cn-TMenuView}
    if [[ -z ${__FV_VW_LIVE[$this]-} && -z $__fvm_ref ]] && (( $# > 4 )); then fv.menus._mparse "$__fvm_cn.Create: '$this'" "${@:5}" || return; fi
    parent.constructor "${@:1:4}"
    if [[ -z ${__FV_VW_LIVE[$this]-} ]]; then
        if [[ -n ${__FV_MN_MV[$this]+x} ]]; then fv.menus._mvFree "$this"; fi
        return "$__FV_VW_CRC"
    fi
    fv.menus._mvCreate "$this" "$__fvm_ref"
}
TMenuView.Done() { fv.menus._mvFree "$this"; inherited; }
TMenuView.HandleEvent() { fv.menus._mvEvent "$this" "$@" || return; }
TMenuView.GetPalette() { fv.menus._mvGetPalette "$this" || return; }
TMenuView.GetHelpCtx() { fv.menus._mvGetHelpCtx "$this" || return; }
TMenuView.Execute() { fv.menus._mvExecute "$this" || return; }
TMenuView.GetItemRect() { fv.menus._mvItemRect "$this" "$@" || return; }
build TMenuView

# TMenuBar.new NAME AX AY BX BY [LIST] — FV TMenuBar.Init(Bounds, AMenu):
# TMenuView's, GrowMode gfGrowHiX, ofPreProcess. Draw: one row, one write
class TMenuBar : TMenuView
    public
        constructor Create
        nofields override proc Draw
        nofields override proc GetItemRect
end
TMenuBar.Create() {
    parent.constructor "$@" || return
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.menus._barCreate "$this"
}
TMenuBar.Draw() { fv.menus._barDraw "$this" || return; }
TMenuBar.GetItemRect() { fv.menus._barItemRect "$this" "$@" || return; }
build TMenuBar

# TMenuBox.new NAME AX AY BX BY [LIST] — FV TMenuBox.Init(Bounds, AMenu,
# AParentMenu): sized by its items (width 5 + the widest ' NAME ' [+ ' - '
# PARAM], height 2 + the items) inside the bounds (shortened from the
# top-left corner, else moved left / up to fit: FV), then TMenuView's,
# sfShadow, ofFramed + ofPreProcess. A box of a menu's submenu is made by
# fv.menus.newSubView (the parent's items, ParentMenu set)
class TMenuBox : TMenuView
    public
        constructor Create
        nofields override proc Draw
        nofields override proc GetItemRect
end
TMenuBox.Create() {
    local __fvm_ref=$__FV_MN_HREF __fvm_hp=$__FV_MN_HPAR __fvm_w=0 __fvm_h=2 __fvm_ax __fvm_ay __fvm_bx __fvm_by
    local -a __fvm_q=()
    __FV_MN_HREF='' __FV_MN_HPAR=''
    if [[ -z ${__FV_VW_LIVE[$this]-} ]] && fv.menus._ints4 "$@"; then
        fv.menus._boxSize "$this" "$__fvm_ref" "${@:5}" || return
        __fvm_ax=${__fvm_q[0]} __fvm_ay=${__fvm_q[1]} __fvm_bx=${__fvm_q[2]} __fvm_by=${__fvm_q[3]}
        __fvm_w=$(( __fvm_w + 5 ))
        if (( __fvm_ax + __fvm_w < __fvm_bx )); then __fvm_bx=$(( __fvm_ax + __fvm_w )); else __fvm_ax=$(( __fvm_bx - __fvm_w )); fi
        __fvm_bx=$(( __fvm_ax + __fvm_w ))
        if (( __fvm_ay + __fvm_h < __fvm_by )); then __fvm_by=$(( __fvm_ay + __fvm_h )); else __fvm_ay=$(( __fvm_by - __fvm_h )); fi
        set -- "$__fvm_ax" "$__fvm_ay" "$__fvm_bx" "$__fvm_by" "${@:5}"
    fi
    __FV_MN_HREF=$__fvm_ref
    parent.constructor "$@" || { __fvm_w=$?; __FV_MN_HREF=''; return "$__fvm_w"; }
    __FV_MN_HREF=''
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.menus._boxCreate "$this" "$__fvm_hp"
}
TMenuBox.Draw() { fv.menus._boxDraw "$this" || return; }
TMenuBox.GetItemRect() { fv.menus._boxItemRect "$this" "$@" || return; }
build TMenuBox

# TMenuPopup.new NAME AX AY BX BY LIST — FV TMenuPopup.Init(Bounds, AMenu): a
# TMenuBox without a parent that owns its items (a context menu): executed
# by the view's owner (fv.views.execView OWNER NAME; RESULT the command, FV
# 0 -> execView's cmCancel). HandleEvent (when it sits in a group): Ctrl+
# letter -> the item with that hot letter, else the key map; an enabled
# command is posted; an Alt+letter is swallowed
class TMenuPopup : TMenuBox
    public
        constructor Create
        nofields override proc HandleEvent
end
TMenuPopup.Create() {
    parent.constructor "$@" || return
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    __FV_MN_MV[$this]=pop
}
TMenuPopup.HandleEvent() { fv.menus._popEvent "$this" "$@" || return; }
build TMenuPopup

# fv.menus._mregister — the menu classes' bodies into fv.views' tables
fv.menus._mregister() {
    __FV_VW_IMPL[TMenuView.HandleEvent]=fv.menus._mvEvent
    __FV_VW_IMPL[TMenuView.GetPalette]=fv.menus._mvGetPalette
    __FV_VW_IMPL[TMenuView.GetHelpCtx]=fv.menus._mvGetHelpCtx
    __FV_VW_IMPL[TMenuView.Execute]=fv.menus._mvExecute
    __FV_VW_IMPL[TMenuView.GetItemRect]=fv.menus._mvItemRect
    __FV_VW_IMPL[TMenuBar.Draw]=fv.menus._barDraw
    __FV_VW_IMPL[TMenuBar.GetItemRect]=fv.menus._barItemRect
    __FV_VW_IMPL[TMenuBox.Draw]=fv.menus._boxDraw
    __FV_VW_IMPL[TMenuBox.GetItemRect]=fv.menus._boxItemRect
    __FV_VW_IMPL[TMenuPopup.HandleEvent]=fv.menus._popEvent
    __FV_VW_BCAST[fv.menus._mvEvent]='cmCommandSetChanged'
    __FV_VW_BCAST[fv.menus._popEvent]='cmCommandSetChanged'
}
fv.menus._mregister

# ---- the model --------------------------------------------------------------------

# fv.menus._ints4 AX AY BX BY — rc 0 for four integers (an optional '-', 1-8
# digits), their values in the caller's __fvm_q: the box's sizing runs only
# on bounds TView will take
fv.menus._ints4() {
    local __fvm_x __fvm_y
    (( $# >= 4 )) || return 1
    for __fvm_y in "$1" "$2" "$3" "$4"; do
        __fvm_x=${__fvm_y#-}
        [[ -n $__fvm_x && $__fvm_x != *[!0123456789]* && ${#__fvm_x} -le 8 ]] || return 1
        if [ "$__fvm_x" = "$__fvm_y" ]; then __fvm_q+=("$(( 10#$__fvm_x ))"); else __fvm_q+=("$(( -10#$__fvm_x ))"); fi
    done
}

# fv.menus._mparse LABEL ARGS... — the item list into the caller's
# __fvm_tt __fvm_tp __fvm_tk __fvm_tc __fvm_th __fvm_ts (a temporary item:
# text, param, key, command, help, its submenu) and __fvm_sl (per submenu,
# its temporary items " i j ..."; 0 = the top menu, the others in the order
# their `sub` comes); rc 2 and one Error line (LABEL: why) for a malformed
# list
fv.menus._mparse() {
    local __fvm_k=$1 __fvm_e='' __fvm_c=0 __fvm_i __fvm_h
    local -a __fvm_st=()
    shift
    __fvm_sl=('')
    while (( $# )); do
        __fvm_i=${#__fvm_tt[@]}
        if [ "$1" = item ]; then
            if (( $# < 6 )); then fv.menus._err "$__fvm_k: 'item' takes TEXT PARAM KEY CMD HELPCTX (left over: ${*:2})"; return 2; fi
            if [[ -z $2 ]]; then fv.menus._err "$__fvm_k: an item needs a TEXT"; return 2; fi
            if ! fv.menus._item "$2" "$4" "$5"; then fv.menus._err "$__fvm_k: item '$2': $__fvm_e"; return 2; fi
            __fvm_h=${6:-0}
            if ! fv.menus._num "$__fvm_h"; then fv.menus._err "$__fvm_k: item '$2': '$6' is not a HELPCTX (digits)"; return 2; fi
            __fvm_tt+=("$2") __fvm_tp+=("$3") __fvm_tk+=("$4") __fvm_tc+=("$5") __fvm_th+=("$(( 10#$__fvm_h ))") __fvm_ts+=('')
            __fvm_sl[__fvm_c]+=" $__fvm_i"
            shift 6
        elif [ "$1" = line ]; then
            __fvm_tt+=('') __fvm_tp+=('') __fvm_tk+=('') __fvm_tc+=('') __fvm_th+=(0) __fvm_ts+=('')
            __fvm_sl[__fvm_c]+=" $__fvm_i"
            shift
        elif [ "$1" = sub ]; then
            if (( $# < 2 )) || [[ -z $2 ]]; then fv.menus._err "$__fvm_k: 'sub' takes a TEXT"; return 2; fi
            __fvm_tt+=("$2") __fvm_tp+=('') __fvm_tk+=('') __fvm_tc+=('') __fvm_ts+=("${#__fvm_sl[@]}")
            shift 2
            __fvm_h=0
            if (( $# )) && fv.menus._num "$1"; then __fvm_h=$(( 10#$1 )); shift; fi
            __fvm_th+=("$__fvm_h")
            __fvm_sl[__fvm_c]+=" $__fvm_i"
            __fvm_st+=("$__fvm_c")
            __fvm_c=${#__fvm_sl[@]}
            __fvm_sl+=('')
        elif [ "$1" = end ]; then
            if (( ! ${#__fvm_st[@]} )); then fv.menus._err "$__fvm_k: 'end' without a 'sub'"; return 2; fi
            __fvm_c=${__fvm_st[${#__fvm_st[@]} - 1]}
            __fvm_st=("${__fvm_st[@]:0:${#__fvm_st[@]} - 1}")
            shift
        else
            fv.menus._err "$__fvm_k: '$1' is not item, line, sub or end"
            return 2
        fi
    done
    if (( ${#__fvm_st[@]} )); then fv.menus._err "$__fvm_k: a 'sub' without its 'end'"; return 2; fi
}

# fv.menus._mlayout O — the caller's parsed list (fv.menus._mparse) into O's
# item arrays, each submenu's items contiguous (submenu 0 first), Default =
# the first item (FV NewMenu), Disabled from the command set (FV NewItem),
# then the key map and the hot letters
fv.menus._mlayout() {
    declare -ga "${1}_mtext=()" "${1}_mparam=()" "${1}_mkey=()" "${1}_mcmd=()" "${1}_mhelp=()" "${1}_msub=()" \
        "${1}_mdis=()" "${1}_mfirst=()" "${1}_mlast=()" "${1}_mdef=()" "${1}_mknext=()" "${1}_mhnext=()" \
        "${1}_mpl=()" "${1}_mpp=()" "${1}_mqpl=()" "${1}_mqpp=()"
    declare -gA "${1}_mkmap=()" "${1}_mhot=()"
    local -n __fvm_T=${1}_mtext __fvm_P=${1}_mparam __fvm_K=${1}_mkey __fvm_C=${1}_mcmd __fvm_H=${1}_mhelp \
        __fvm_S=${1}_msub __fvm_D=${1}_mdis __fvm_F=${1}_mfirst __fvm_L=${1}_mlast __fvm_DF=${1}_mdef
    local __fvm_s __fvm_t __fvm_n=0 IFS=' '
    for (( __fvm_s = 0; __fvm_s < ${#__fvm_sl[@]}; __fvm_s++ )); do
        __fvm_F[__fvm_s]=$__fvm_n
        # (temporary indices: digits, no glob character)
        for __fvm_t in ${__fvm_sl[__fvm_s]}; do
            __fvm_T[__fvm_n]=${__fvm_tt[__fvm_t]} __fvm_P[__fvm_n]=${__fvm_tp[__fvm_t]} __fvm_K[__fvm_n]=${__fvm_tk[__fvm_t]}
            __fvm_C[__fvm_n]=${__fvm_tc[__fvm_t]} __fvm_H[__fvm_n]=${__fvm_th[__fvm_t]} __fvm_S[__fvm_n]=${__fvm_ts[__fvm_t]}
            if [[ -n ${__fvm_tc[__fvm_t]} && -n ${__FV_VW_CMDOFF[${__fvm_tc[__fvm_t]}]-} ]]; then __fvm_D[__fvm_n]=1; else __fvm_D[__fvm_n]=0; fi
            __fvm_n=$(( __fvm_n + 1 ))
        done
        __fvm_L[__fvm_s]=$(( __fvm_n - 1 ))
        if (( __fvm_n > __fvm_F[__fvm_s] )); then __fvm_DF[__fvm_s]=${__fvm_F[__fvm_s]}; else __fvm_DF[__fvm_s]=-1; fi
    done
    fv.menus._mmaps "$1"
    __FV_MN_OWN[$1]=1 __FV_MN_MAM[$1]=''
}

# fv.menus._mmaps O — O's hot letters (per submenu, in item order) and key
# map (FV HotKey's depth-first walk from the top menu)
fv.menus._mmaps() {
    local -n __fvm_T=${1}_mtext __fvm_K=${1}_mkey __fvm_S=${1}_msub __fvm_F=${1}_mfirst __fvm_L=${1}_mlast \
        __fvm_kn=${1}_mknext __fvm_hn=${1}_mhnext __fvm_km=${1}_mkmap __fvm_hm=${1}_mhot
    local __fvm_s __fvm_i __fvm_j __fvm_x __fvm_l
    __fvm_kn=() __fvm_hn=() __fvm_km=() __fvm_hm=()
    for (( __fvm_s = 0; __fvm_s < ${#__fvm_F[@]}; __fvm_s++ )); do
        for (( __fvm_i = __fvm_F[__fvm_s]; __fvm_i <= __fvm_L[__fvm_s]; __fvm_i++ )); do
            __fvm_kn[__fvm_i]=-1 __fvm_hn[__fvm_i]=-1
            __fvm_x=${__fvm_T[__fvm_i]#*'~'}
            # (FV: a `~` that is not the last character)
            if [ "$__fvm_x" = "${__fvm_T[__fvm_i]}" ] || [[ -z $__fvm_x ]]; then continue; fi
            fv.menus._letter "$__fvm_x"
            __fvm_j=${__fvm_hm["$__fvm_s:$__fvm_l"]-}
            if [[ -z $__fvm_j ]]; then __fvm_hm["$__fvm_s:$__fvm_l"]=$__fvm_i; continue; fi
            while (( __fvm_hn[__fvm_j] >= 0 )); do __fvm_j=${__fvm_hn[__fvm_j]}; done
            __fvm_hn[__fvm_j]=$__fvm_i
        done
    done
    if (( ${#__fvm_F[@]} )); then fv.menus._mdfs 0; fi
}
# fv.menus._mdfs S — (fv.menus._mmaps' namerefs) submenu S's items into the
# key map, a submenu's own items where it stands (FV FindHotKey's order)
fv.menus._mdfs() {
    local __fvm_i __fvm_j
    for (( __fvm_i = __fvm_F[$1]; __fvm_i <= __fvm_L[$1]; __fvm_i++ )); do
        if [[ -z ${__fvm_T[__fvm_i]} ]]; then continue; fi
        if [[ -n ${__fvm_S[__fvm_i]} ]]; then fv.menus._mdfs "${__fvm_S[__fvm_i]}"; continue; fi
        if [[ -z ${__fvm_K[__fvm_i]} ]]; then continue; fi
        __fvm_j=${__fvm_km[${__fvm_K[__fvm_i]}]-}
        if [[ -z $__fvm_j ]]; then __fvm_km[${__fvm_K[__fvm_i]}]=$__fvm_i; continue; fi
        while (( __fvm_kn[__fvm_j] >= 0 )); do __fvm_j=${__fvm_kn[__fvm_j]}; done
        __fvm_kn[__fvm_j]=$__fvm_i
    done
}
# fv.menus._letter TEXT — the caller's __fvm_l = TEXT's first character,
# folded (${c,,} in fv.video's UTF-8 locale for a non-ASCII one: Cyrillic,
# Greek, … as fv.views' hot-key map folds)
fv.menus._letter() {
    if [[ $1 == [![:ascii:]]* && ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g fv.menus._letter1 "$1"; return 0; fi
    __fvm_l=${1:0:1} __fvm_l=${__fvm_l,,}
}
fv.menus._letter1() { __fvm_l=${1:0:1} __fvm_l=${__fvm_l,,}; }

# fv.menus._mpats O — O's item patterns for the screen's ASCII mode
fv.menus._mpats() {
    local -n __fvm_T=${1}_mtext __fvm_P=${1}_mparam __fvm_pl=${1}_mpl __fvm_pp=${1}_mpp __fvm_ql=${1}_mqpl __fvm_qp=${1}_mqpp
    local __fvm_i __fvm_s __fvm_p __fvm_rr=${RESULT-}
    __fvm_pl=() __fvm_pp=() __fvm_ql=() __fvm_qp=()
    for (( __fvm_i = 0; __fvm_i < ${#__fvm_T[@]}; __fvm_i++ )); do
        if [[ -z ${__fvm_T[__fvm_i]} ]]; then __fvm_pl[__fvm_i]='' __fvm_pp[__fvm_i]='' __fvm_ql[__fvm_i]='' __fvm_qp[__fvm_i]=''; continue; fi
        fv.menus._pat1 "${__fvm_T[__fvm_i]}"
        __fvm_pl[__fvm_i]=$__fvm_s __fvm_pp[__fvm_i]=$__fvm_p
        if [[ -n ${__fvm_P[__fvm_i]} ]]; then
            # (the Param as FV's MoveCStr draws it: no blanks around it)
            fv.menus._pat1 "${__fvm_P[__fvm_i]}"
            __fvm_ql[__fvm_i]=${__fvm_s:1:${#__fvm_s}-2} __fvm_qp[__fvm_i]=${__fvm_p:1:${#__fvm_p}-2}
        else
            __fvm_ql[__fvm_i]='' __fvm_qp[__fvm_i]=''
        fi
    done
    __FV_MN_MAM[$1]=${FV_VIDEO_ASCII:-0}
    RESULT=$__fvm_rr
}

# fv.menus._boxSize NAME REF ARGS... — the caller's __fvm_w (the widest
# ' NAME ' [+ ' - ' PARAM] in cells) and __fvm_h (2 + the items) of the menu
# REF ("OWNER:S") or of the list ARGS (parsed: rc 2 and the Error line when
# malformed)
fv.menus._boxSize() {
    local __fvm_o=${2%:*} __fvm_s=${2##*:} __fvm_i __fvm_x __fvm_p __fvm_rr=${RESULT-}
    if [[ -n $2 && -n ${__FV_MN_OWN[$__fvm_o]-} ]]; then
        if ! [ "${__FV_MN_MAM[$__fvm_o]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._mpats "$__fvm_o"; fi
        local -n __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast __fvm_T=${__fvm_o}_mtext __fvm_C=${__fvm_o}_mcmd \
            __fvm_pp=${__fvm_o}_mpp __fvm_qp=${__fvm_o}_mqpp
        for (( __fvm_i = __fvm_F[__fvm_s]; __fvm_i <= __fvm_L[__fvm_s]; __fvm_i++ )); do
            __fvm_h=$(( __fvm_h + 1 ))
            if [[ -z ${__fvm_T[__fvm_i]} ]]; then continue; fi
            __fvm_x=${#__fvm_pp[__fvm_i]}
            if [[ -n ${__fvm_C[__fvm_i]} && -n ${__fvm_qp[__fvm_i]} ]]; then __fvm_x=$(( __fvm_x + 3 + ${#__fvm_qp[__fvm_i]} )); fi
            if (( __fvm_x > __fvm_w )); then __fvm_w=$__fvm_x; fi
        done
        return 0
    fi
    (( $# > 2 )) || return 0
    local -a __fvm_tt=() __fvm_tp=() __fvm_tk=() __fvm_tc=() __fvm_th=() __fvm_ts=() __fvm_sl=()
    local __fvm_cn=${1}_class IFS=' '
    fv.menus._mparse "${!__fvm_cn-TMenuBox}.Create: '$1'" "${@:3}" || return
    local __fvm_s
    # (temporary indices: digits)
    for __fvm_i in ${__fvm_sl[0]}; do
        __fvm_h=$(( __fvm_h + 1 ))
        if [[ -z ${__fvm_tt[__fvm_i]} ]]; then continue; fi
        fv.menus._pat1 "${__fvm_tt[__fvm_i]}"
        __fvm_x=${#__fvm_p}
        if [[ -n ${__fvm_tc[__fvm_i]} && -n ${__fvm_tp[__fvm_i]} ]]; then
            fv.menus._pat1 "${__fvm_tp[__fvm_i]}"
            __fvm_x=$(( __fvm_x + 1 + ${#__fvm_p} ))
        fi
        if (( __fvm_x > __fvm_w )); then __fvm_w=$__fvm_x; fi
    done
    RESULT=$__fvm_rr
}

# fv.menus._mvCreate V REF — FV TMenuView.Init after TView's part: the
# mask, the fields, the items (the caller's parsed list) or the borrowed
# menu REF
fv.menus._mvCreate() {
    local -n __fvm_d=${1}_data
    if [[ -z ${__FV_VW_IMPL[TMenuView.Execute]-} ]]; then fv.menus._mregister; fi
    __fvm_d[EventMask]=$(( ${__fvm_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __fvm_d[ParentMenu]='' __fvm_d[Menu]='' __fvm_d[Current]=-1 __fvm_d[OldItem]=-1
    __FV_MN_MV[$1]=view __FV_MN_MG[$1]='' __FV_MN_SH[$1]=-1
    if [[ -n $2 ]]; then
        __fvm_d[Menu]=$2
    elif (( ${#__fvm_tt[@]} )); then
        fv.menus._mlayout "$1"
        __fvm_d[Menu]="$1:0"
    fi
}
# fv.menus._barCreate BAR — FV TMenuBar.Init: GrowMode gfGrowHiX, ofPreProcess
fv.menus._barCreate() {
    local -n __fvm_d=${1}_data
    __fvm_d[GrowMode]=$FV_GF_GROWHIX
    __fvm_d[Options]=$(( ${__fvm_d[Options]:-0} | FV_OF_PREPROCESS ))
    __FV_MN_MV[$1]=bar
}
# fv.menus._boxCreate BOX PARENT — FV TMenuBox.Init after TMenuView's:
# sfShadow, ofFramed + ofPreProcess, ParentMenu; Current = the Default
# (shown highlighted from its first draw; FV sets it when Execute starts)
fv.menus._boxCreate() {
    local -n __fvm_d=${1}_data
    __fvm_d[State]=$(( ${__fvm_d[State]:-0} | FV_SF_SHADOW ))
    __fvm_d[Options]=$(( ${__fvm_d[Options]:-0} | FV_OF_FRAMED | FV_OF_PREPROCESS ))
    __fvm_d[ParentMenu]=$2
    __FV_MN_MV[$1]=box
    local __fvm_m=${__fvm_d[Menu]-}
    if [[ -n $__fvm_m ]]; then
        local -n __fvm_df=${__fvm_m%:*}_mdef
        __fvm_d[Current]=${__fvm_df[${__fvm_m##*:}]--1}
    fi
}
# fv.menus._mvFree V — V's entries, and its item arrays when it owns them
fv.menus._mvFree() {
    if [[ -n ${__FV_MN_OWN[$1]-} ]]; then
        unset "${1}_mtext" "${1}_mparam" "${1}_mkey" "${1}_mcmd" "${1}_mhelp" "${1}_msub" "${1}_mdis" \
            "${1}_mfirst" "${1}_mlast" "${1}_mdef" "${1}_mknext" "${1}_mhnext" "${1}_mpl" "${1}_mpp" \
            "${1}_mqpl" "${1}_mqpp" "${1}_mkmap" "${1}_mhot"
    fi
    unset '__FV_MN_MV[$1]' '__FV_MN_OWN[$1]' '__FV_MN_MG[$1]' '__FV_MN_SH[$1]' '__FV_MN_SUB[$1]' '__FV_MN_MAM[$1]'
    return 0
}

# fv.menus._mref V — the caller's __fvm_o / __fvm_s = V's menu (owner,
# submenu); rc 1 when V has none (FV Menu = nil) or its owner is gone
fv.menus._mref() {
    local __fvm_m="${1}_data[Menu]"
    __fvm_m=${!__fvm_m-}
    __fvm_o=${__fvm_m%:*} __fvm_s=${__fvm_m##*:}
    [[ -n $__fvm_m && -n ${__FV_MN_OWN[$__fvm_o]-} ]]
}

# ---- drawing ----------------------------------------------------------------------

# fv.menus._mcol LO HI — the caller's __fvm_lo / __fvm_hi for item I of the
# caller's arrays: FV's CNormal (1 / 3), CSelect (4 / 6, the current item),
# CNormDisabled (2 / 2), CSelDisabled (5 / 5); __fvm_g += the enabled flag
fv.menus._mcol() {
    if (( __fvm_D[$1] )); then
        __fvm_g+=0
        if (( $1 == __fvm_cur )); then __fvm_lo=$__fvm_s5 __fvm_hi=$__fvm_s5; else __fvm_lo=$__fvm_n2 __fvm_hi=$__fvm_n2; fi
    else
        __fvm_g+=1
        if (( $1 == __fvm_cur )); then __fvm_lo=$__fvm_s4 __fvm_hi=$__fvm_s6; else __fvm_lo=$__fvm_n1 __fvm_hi=$__fvm_n3; fi
    fi
}
# fv.menus._pal6 — the caller's palette symbols __fvm_n1 .. __fvm_s6 from
# FV_DRAW_PAL (CMenuView's six entries; a missing one: ErrorAttr)
fv.menus._pal6() {
    local __fvm_e=$__FV_VW_ERRSYM __fvm_q=$FV_DRAW_PAL
    __fvm_n1=${__fvm_q:0:1} __fvm_n2=${__fvm_q:1:1} __fvm_n3=${__fvm_q:2:1}
    __fvm_s4=${__fvm_q:3:1} __fvm_s5=${__fvm_q:4:1} __fvm_s6=${__fvm_q:5:1}
    __fvm_n1=${__fvm_n1:-$__fvm_e} __fvm_n2=${__fvm_n2:-$__fvm_e} __fvm_n3=${__fvm_n3:-$__fvm_e}
    __fvm_s4=${__fvm_s4:-$__fvm_e} __fvm_s5=${__fvm_s5:-$__fvm_e} __fvm_s6=${__fvm_s6:-$__fvm_e}
}

# TMenuBar.Draw — FV: blanks in CNormal over the row, then each item with a
# name ' NAME ' in its colours (the `~` part Hi), left to right: ONE
# writeLine (a bar taller than one row gets the rows below blanked by one
# fill). Records what it showed (SH, MG)
fv.menus._barDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvm_d=${1}_data
    local __fvm_o __fvm_s __fvm_x='' __fvm_y='' __fvm_g='' __fvm_lo __fvm_hi __fvm_p __fvm_i __fvm_w
    local __fvm_n1 __fvm_n2 __fvm_n3 __fvm_s4 __fvm_s5 __fvm_s6 __fvm_cur=${__fvm_d[Current]:--1}
    local __fvm_sx=${__fvm_d[SizeX]:-0} __fvm_sy=${__fvm_d[SizeY]:-0}
    fv.menus._pal6
    if fv.menus._mref "$1"; then
        if ! [ "${__FV_MN_MAM[$__fvm_o]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._mpats "$__fvm_o"; fi
        local -n __fvm_D=${__fvm_o}_mdis __fvm_T=${__fvm_o}_mtext __fvm_pl=${__fvm_o}_mpl __fvm_pp=${__fvm_o}_mpp
        local -n __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast
        for (( __fvm_i = __fvm_F[__fvm_s]; __fvm_i <= __fvm_L[__fvm_s]; __fvm_i++ )); do
            if [[ -z ${__fvm_T[__fvm_i]} ]]; then continue; fi
            fv.menus._mcol "$__fvm_i"
            __fvm_p=${__fvm_pp[__fvm_i]//+/$__fvm_lo}
            __fvm_x+=${__fvm_pl[__fvm_i]} __fvm_y+=${__fvm_p//-/$__fvm_hi}
        done
    fi
    if (( ${#__fvm_y} < __fvm_sx )); then
        __fvm_w=$(( __fvm_sx - ${#__fvm_y} ))
        __fvm_p=${__FV_VW_PAD:0:__fvm_w}
        __fvm_x+=$__fvm_p __fvm_y+=${__fvm_p// /$__fvm_n1}
    fi
    fv.views.writeLine 0 0 1 "$__fvm_x" "$__fvm_y" || :
    if (( __fvm_sy > 1 )); then fv.views.fill 0 1 "$__fvm_sx" "$(( __fvm_sy - 1 ))" ' ' 1 || :; fi
    __FV_MN_SH[$1]=$__fvm_cur __FV_MN_MG[$1]=$__fvm_g
    return 0
}

# TMenuBox.Draw — FV: the frame (a blank column on each side, `┌─┐`,
# `│ │`, `├─┤` for a NewLine, `└─┘`; fv.video's ASCII mode shows `+ - |`)
# in CNormal, each item ' NAME ' from column 2 on a bar of its colour
# (FV CreateBorder: the bar spans the frame's inside), a submenu's `►` at
# SizeX-4 (ASCII mode `>`), a Param right-aligned ending at SizeX-3: ONE
# writeLines for the whole box. Records what it showed (SH, MG)
fv.menus._boxDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvm_d=${1}_data
    local -a _fvm_t=() _fvm_a=()
    local __fvm_y __fvm_sy=${__fvm_d[SizeY]:-0} __fvm_g='' __fvm_rr=${RESULT-}
    fv.menus._boxRows "$1" 0 "$__fvm_sy"
    fv.views.writeLines 0 0 _fvm_t _fvm_a || :
    __FV_MN_SH[$1]=${__fvm_d[Current]:--1} __FV_MN_MG[$1]=$__fvm_g
    RESULT=$__fvm_rr
    return 0
}
# fv.menus._boxPaint BOX Y — the drawPart painter of a highlight move: row Y
# of the box (one writeLine)
fv.menus._boxPaint() {
    local -n __fvm_d=${1}_data
    local -a _fvm_t=() _fvm_a=()
    local __fvm_g='' __fvm_rr=${RESULT-}
    fv.menus._boxRows "$1" "$2" "$(( $2 + 1 ))"
    fv.views.writeLine 0 "$2" 1 "${_fvm_t[$2]}" "${_fvm_a[$2]}" || :
    RESULT=$__fvm_rr
    return 0
}
# fv.menus._boxRows BOX Y1 Y2 — rows Y1 <= y < Y2 of the box into the
# caller's _fvm_t / _fvm_a (index y); __fvm_g = the enabled signature of the
# items composed
fv.menus._boxRows() {
    local -n __fvm_bd=${1}_data
    local __fvm_o __fvm_s __fvm_w=${__fvm_bd[SizeX]:-0} __fvm_h=${__fvm_bd[SizeY]:-0} __fvm_cur=${__fvm_bd[Current]:--1}
    local __fvm_n1 __fvm_n2 __fvm_n3 __fvm_s4 __fvm_s5 __fvm_s6 __fvm_lo __fvm_hi __fvm_y __fvm_i __fvm_f=0 __fvm_l=-1
    local __fvm_ln __fvm_in __fvm_fa __fvm_x __fvm_p __fvm_q __fvm_k __fvm_tl __fvm_tp
    fv.menus._pal6
    if (( __fvm_w < 4 )); then __fvm_w=4; fi
    # (the frame's inside: FV fills SizeX-4 cells)
    __fvm_in=${__FV_VW_PAD:0:__fvm_w-4} __fvm_ln=${__FV_VW_PAD:0:__fvm_w-4}
    __fvm_ln=${__fvm_ln// /─}
    __fvm_fa=${__FV_VW_PAD:0:__fvm_w} __fvm_fa=${__fvm_fa// /$__fvm_n1}
    if fv.menus._mref "$1"; then
        if ! [ "${__FV_MN_MAM[$__fvm_o]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._mpats "$__fvm_o"; fi
        local -n __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast
        __fvm_f=${__fvm_F[__fvm_s]} __fvm_l=${__fvm_L[__fvm_s]}
    fi
    for (( __fvm_y = $2; __fvm_y < $3; __fvm_y++ )); do
        __fvm_i=$(( __fvm_f + __fvm_y - 1 ))
        if (( __fvm_y == 0 )); then
            _fvm_t[__fvm_y]=" ┌$__fvm_ln┐ " _fvm_a[__fvm_y]=$__fvm_fa
        elif (( __fvm_y == __fvm_h - 1 )); then
            _fvm_t[__fvm_y]=" └$__fvm_ln┘ " _fvm_a[__fvm_y]=$__fvm_fa
        elif (( __fvm_i > __fvm_l )); then
            _fvm_t[__fvm_y]=" │$__fvm_in│ " _fvm_a[__fvm_y]=$__fvm_fa
        else
            fv.menus._boxItem "$__fvm_i"
        fi
    done
}
# fv.menus._boxItem I — (fv.menus._boxRows' locals) item I's row
fv.menus._boxItem() {
    local -n __fvm_T=${__fvm_o}_mtext __fvm_D=${__fvm_o}_mdis
    if [[ -z ${__fvm_T[$1]} ]]; then
        _fvm_t[__fvm_y]=" ├$__fvm_ln┤ " _fvm_a[__fvm_y]=$__fvm_fa
        return 0
    fi
    local -n __fvm_pl=${__fvm_o}_mpl __fvm_pp=${__fvm_o}_mpp __fvm_C=${__fvm_o}_mcmd __fvm_ql=${__fvm_o}_mqpl __fvm_qp=${__fvm_o}_mqpp
    fv.menus._mcol "$1"
    # (the inside: ' NAME ', blanks, then the submenu mark or the Param and
    # one blank — FV writes them at SizeX-4 / ending at SizeX-3)
    __fvm_tl='' __fvm_tp=''
    if [[ -z ${__fvm_C[$1]} ]]; then __fvm_tl='► ' __fvm_tp='++'
    elif [[ -n ${__fvm_ql[$1]} ]]; then __fvm_tl="${__fvm_ql[$1]} " __fvm_tp="${__fvm_qp[$1]}+"; fi
    __fvm_k=$(( __fvm_w - 4 - ${#__fvm_pp[$1]} - ${#__fvm_tp} ))
    if (( __fvm_k < 0 )); then __fvm_k=0 __fvm_tl='' __fvm_tp=''; fi
    __fvm_p="==${__fvm_pp[$1]}${__FV_VW_PAD:0:__fvm_k}$__fvm_tp=="
    __fvm_p=${__fvm_p// /+}
    __fvm_p=${__fvm_p//=/$__fvm_n1} __fvm_p=${__fvm_p//+/$__fvm_lo}
    _fvm_t[__fvm_y]=" │${__fvm_pl[$1]}${__FV_VW_PAD:0:__fvm_k}$__fvm_tl│ " _fvm_a[__fvm_y]=${__fvm_p//-/$__fvm_hi}
}

# TMenuView.GetPalette (func) — FV CMenuView #2#3#4#5#6#7
fv.menus._mvGetPalette() { RESULT='2 3 4 5 6 7'; }

# TMenuView.GetHelpCtx (func) — FV: from V up the parent menus, the first
# whose Current is an item with a name and a HelpCtx other than
# hcNoContext; hcNoContext when none
fv.menus._mvGetHelpCtx() {
    local __fvm_v=$1 __fvm_c __fvm_o __fvm_s __fvm_g=0 __fvm_t __fvm_h
    while [[ -n $__fvm_v && -n ${__FV_VW_LIVE[$__fvm_v]-} ]] && (( __fvm_g++ < 64 )); do
        __fvm_c="${__fvm_v}_data[Current]" __fvm_c=${!__fvm_c:--1}
        if (( __fvm_c >= 0 )) && fv.menus._mref "$__fvm_v"; then
            __fvm_t="${__fvm_o}_mtext[$__fvm_c]" __fvm_h="${__fvm_o}_mhelp[$__fvm_c]"
            if [[ -n ${!__fvm_t-} ]] && (( ${!__fvm_h:-0} != FV_HC_NOCONTEXT )); then RESULT=${!__fvm_h}; return 0; fi
        fi
        __fvm_c="${__fvm_v}_data[ParentMenu]" __fvm_v=${!__fvm_c-}
    done
    RESULT=$FV_HC_NOCONTEXT
}

# TMenuView.GetItemRect ITEM — FV GetItemRectX: the item's rect in V's local
# coordinates into FV_RECT_AX .. FV_RECT_BY (the var parameter; RESULT kept).
# TMenuView's is FV's abstract one (an empty rect)
fv.menus._mvItemRect() { FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=0 FV_RECT_BY=0; }
# TMenuBar.GetItemRect ITEM — FV: the items with a name side by side from
# column 0, each ' NAME ' wide (a NewLine: an empty rect where it stands)
fv.menus._barItemRect() {
    local __fvm_o __fvm_s __fvm_i __fvm_x=0
    FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=0 FV_RECT_BY=1
    fv.menus._mref "$1" || return 0
    if ! [ "${__FV_MN_MAM[$__fvm_o]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._mpats "$__fvm_o"; fi
    local -n __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast __fvm_pp=${__fvm_o}_mpp
    for (( __fvm_i = __fvm_F[__fvm_s]; __fvm_i <= __fvm_L[__fvm_s]; __fvm_i++ )); do
        FV_RECT_AX=$__fvm_x FV_RECT_BX=$(( __fvm_x + ${#__fvm_pp[__fvm_i]} ))
        __fvm_x=$FV_RECT_BX
        if [ "$__fvm_i" = "${2-}" ]; then return 0; fi
    done
}
# TMenuBox.GetItemRect ITEM — FV: row 1 + the item's place in the submenu,
# columns 2 .. SizeX-3
fv.menus._boxItemRect() {
    local -n __fvm_d=${1}_data
    local __fvm_o __fvm_s __fvm_y=1
    if fv.menus._mref "$1" && [[ ${2-} != *[!0123456789]* && -n ${2-} ]]; then
        local -n __fvm_F=${__fvm_o}_mfirst
        __fvm_y=$(( 1 + 10#$2 - __fvm_F[__fvm_s] ))
    fi
    FV_RECT_AX=2 FV_RECT_AY=$__fvm_y FV_RECT_BX=$(( ${__fvm_d[SizeX]:-0} - 2 )) FV_RECT_BY=$(( __fvm_y + 1 ))
}

# ---- events -----------------------------------------------------------------------

# fv.menus._find O S — FV FindItem(Ch) with the current key event, through the
# hot-letter map (fv.views.hotKeyIs' order, design §14.4): the typed
# character (FV_EV_CHAR, folded) first, then — for a typed character that is
# not ASCII, or none — the base-layout key (FV_EV_BASE; a plain character:
# the layout tables, fv.keyboard.layoutBase). The first item of submenu S
# with that hot letter that is not Disabled: the caller's __fvm_p (-1 none)
fv.menus._find() {
    local __fvm_l __fvm_b='' __fvm_r
    __fvm_p=-1
    if [[ -n $FV_EV_CHAR ]]; then
        fv.menus._letter "$FV_EV_CHAR"
        fv.menus._hot "$1" "$2" "$__fvm_l"
        if (( __fvm_p >= 0 )) || [[ $FV_EV_CHAR != *[![:ascii:]]* ]]; then return 0; fi
    fi
    __fvm_b=${FV_EV_BASE-}
    if [[ -z $__fvm_b && -n $FV_EV_CHAR ]] && [ "$FV_EV_KEY" = kbChar ]; then
        # (>/dev/null: in a subshell layoutBase would print its answer)
        __fvm_r=${RESULT-}
        if fv.keyboard.layoutBase "$FV_EV_CHAR" >/dev/null 2>&1; then __fvm_b=$RESULT; fi
        RESULT=$__fvm_r
    fi
    if [[ -n $__fvm_b ]]; then fv.menus._hot "$1" "$2" "${__fvm_b,,}"; fi
    return 0
}
# fv.menus._hot O S L — the caller's __fvm_p = the first enabled item of
# submenu S with hot letter L (-1 none)
fv.menus._hot() {
    local -n __fvm_hm=${1}_mhot __fvm_hn=${1}_mhnext __fvm_D=${1}_mdis
    local __fvm_j=${__fvm_hm["$2:$3"]-}
    while [[ -n $__fvm_j ]] && (( __fvm_j >= 0 )); do
        if (( ! __fvm_D[__fvm_j] )); then __fvm_p=$__fvm_j; return 0; fi
        __fvm_j=${__fvm_hn[__fvm_j]}
    done
}
# fv.menus._hotKey O KEY S — FV HotKey(KeyCode): the caller's __fvm_p = the
# first item of submenu S's tree (depth-first, FV walks the view's Menu) with
# that key that is not Disabled (-1 none). S 0 (the bar, a popup): one map
# read and a walk of that key's chain; any other S (a box made by newSubView
# and inserted by hand): FV's walk of that subtree (fv.menus._hkSub)
fv.menus._hotKey() {
    __fvm_p=-1
    if [[ -z $2 ]]; then return 0; fi
    if [[ ${3:-0} != 0 ]]; then fv.menus._hkSub "$1" "$3" "$2" || :; return 0; fi
    local -n __fvm_km=${1}_mkmap __fvm_kn=${1}_mknext __fvm_D=${1}_mdis
    local __fvm_j=${__fvm_km[$2]-}
    while [[ -n $__fvm_j ]] && (( __fvm_j >= 0 )); do
        if (( ! __fvm_D[__fvm_j] )); then __fvm_p=$__fvm_j; return 0; fi
        __fvm_j=${__fvm_kn[__fvm_j]}
    done
}
# fv.menus._hkSub O S KEY — FV FindHotKey(S's items): rc 0 and the caller's
# __fvm_p = the first enabled item with KEY in S's tree (depth-first), rc 1
# for none (or no submenu S)
fv.menus._hkSub() {
    local -n __fvm_hT=${1}_mtext __fvm_hK=${1}_mkey __fvm_hS=${1}_msub __fvm_hD=${1}_mdis \
        __fvm_hF=${1}_mfirst __fvm_hL=${1}_mlast
    [[ -n ${__fvm_hF[$2]-} ]] || return 1
    fv.menus._hkDfs "$2" "$3"
}
# fv.menus._hkDfs S KEY — (fv.menus._hkSub's namerefs) its walk of submenu S
fv.menus._hkDfs() {
    local __fvm_i
    for (( __fvm_i = __fvm_hF[$1]; __fvm_i <= __fvm_hL[$1]; __fvm_i++ )); do
        if [[ -z ${__fvm_hT[__fvm_i]} ]]; then continue; fi
        if [[ -n ${__fvm_hS[__fvm_i]} ]]; then
            if fv.menus._hkDfs "${__fvm_hS[__fvm_i]}" "$2"; then return 0; fi
        elif (( ! __fvm_hD[__fvm_i] )) && [ "${__fvm_hK[__fvm_i]}" = "$2" ]; then
            __fvm_p=$__fvm_i
            return 0
        fi
    done
    return 1
}

# TMenuView.HandleEvent — FV (the bar's: a TMenuView in a group):
#   * evMouseDown, evCommand cmMenu: DoSelect;
#   * evKeyDown: with Alt (kbAlt…) the item of its own menu with that hot
#     letter (fv.menus._find) -> DoSelect; else FV HotKey (the key map): an
#     item whose command is enabled -> evCommand CMD posted, the key handled;
#   * evBroadcast cmCommandSetChanged: FV UpdateMenu (Disabled from the
#     command set, the whole tree below its menu), redrawn when what it shows
#     changed (FV: when an item changed).
# DoSelect (FV): the event put back (PutEvent), the view run modal by its
# owner (fv.views.execView), an enabled command it answers posted as
# evCommand; the event handled. A view without a menu does nothing
fv.menus._mvEvent() {
    local __fvm_o __fvm_s __fvm_p=-1
    fv.menus._mref "$1" || return 0
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [[ $FV_EV_KEY == kbAlt* ]]; then fv.menus._find "$__fvm_o" "$__fvm_s"; fi
        if (( __fvm_p >= 0 )); then fv.menus._doSelect "$1"; return 0; fi
        fv.menus._hotKey "$__fvm_o" "$FV_EV_KEY" "$__fvm_s"
        if (( __fvm_p >= 0 )); then
            local -n __fvm_C=${__fvm_o}_mcmd
            if [[ -z ${__FV_VW_CMDOFF[${__fvm_C[__fvm_p]}]-} ]]; then fv.menus._post "$1" "${__fvm_C[__fvm_p]}"; fi
        fi
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.menus._doSelect "$1"
    elif [ "$FV_EV_WHAT" = evCommand ]; then
        if [ "$FV_EV_COMMAND" = cmMenu ]; then fv.menus._doSelect "$1"; fi
    elif [ "$FV_EV_WHAT" = evBroadcast ]; then
        if [ "$FV_EV_COMMAND" = cmCommandSetChanged ]; then fv.menus._mvUpdate "$1"; fi
    fi
    return 0
}
# fv.menus._doSelect V — FV DoSelect
fv.menus._doSelect() {
    local __fvm_w="${1}_data[Owner]" __fvm_r
    __fvm_w=${!__fvm_w-}
    if [[ -z $__fvm_w ]]; then return 0; fi
    "$__FV_VW_PUTEVENT" || :
    __FV_MN_RES=''
    __fvm_r=${RESULT-}
    fv.views.execView "$__fvm_w" "$1" || :
    if [ "${RESULT-}" = cmCancel ] && ! [ "$__FV_MN_RES" = cmCancel ]; then RESULT=''; fi
    if [[ -n ${RESULT-} && -z ${__FV_VW_CMDOFF[$RESULT]-} ]]; then fv.menus._post "$1" "$RESULT"
    else FV_EV_WHAT=evNothing FV_EV_INFO=$1; fi
    RESULT=$__fvm_r
}
# fv.menus._mvUpdate V — FV UpdateMenu + the redraw (cmCommandSetChanged):
# Disabled from the command set below V's menu; V redrawn when its own
# items show another enabled state than it drew (a class that overrides
# Draw: when an item changed, FV)
fv.menus._mvUpdate() {
    local __fvm_o __fvm_s __fvm_n=0 __fvm_i __fvm_g=''
    fv.menus._mref "$1" || return 0
    local -n __fvm_C=${__fvm_o}_mcmd __fvm_D=${__fvm_o}_mdis __fvm_T=${__fvm_o}_mtext __fvm_S=${__fvm_o}_msub \
        __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast
    fv.menus._mupd "$__fvm_s"
    for (( __fvm_i = __fvm_F[__fvm_s]; __fvm_i <= __fvm_L[__fvm_s]; __fvm_i++ )); do
        if [[ -n ${__fvm_T[__fvm_i]} ]]; then __fvm_g+=$(( ! __fvm_D[__fvm_i] )); fi
    done
    local __fvm_c=${1}_class
    __fvm_c="${!__fvm_c-}_class_method_owner[Draw]"
    __fvm_c=${__FV_VW_IMPL[${!__fvm_c-}.Draw]-}
    if [ "$__fvm_c" = fv.menus._barDraw ] || [ "$__fvm_c" = fv.menus._boxDraw ]; then
        if [[ -n ${__FV_MN_MG[$1]-} ]] && ! [ "$__fvm_g" = "${__FV_MN_MG[$1]}" ]; then fv.views.drawView "$1" || :; fi
    elif (( __fvm_n )); then
        fv.views.drawView "$1" || :
    fi
}
# fv.menus._mupd S — (fv.menus._mvUpdate's namerefs) submenu S and the
# submenus below it: Disabled from the command set; __fvm_n += the changes
fv.menus._mupd() {
    local __fvm_i __fvm_x
    for (( __fvm_i = __fvm_F[$1]; __fvm_i <= __fvm_L[$1]; __fvm_i++ )); do
        if [[ -z ${__fvm_T[__fvm_i]} ]]; then continue; fi
        if [[ -n ${__fvm_S[__fvm_i]} ]]; then fv.menus._mupd "${__fvm_S[__fvm_i]}"; continue; fi
        if [[ -n ${__FV_VW_CMDOFF[${__fvm_C[__fvm_i]}]-} ]]; then __fvm_x=1; else __fvm_x=0; fi
        if (( __fvm_x != __fvm_D[__fvm_i] )); then __fvm_D[__fvm_i]=$__fvm_x __fvm_n=$(( __fvm_n + 1 )); fi
    done
}

# TMenuPopup.HandleEvent — FV: evKeyDown: a Ctrl+letter key -> the item of its
# menu with that hot letter (FV FindItem(GetCtrlChar)), else HotKey; an item
# whose command is enabled -> evCommand CMD posted, the key handled; else an
# Alt+letter / digit key is swallowed (FV GetAltChar <> #0). Then
# TMenuView's
fv.menus._popEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        local __fvm_o __fvm_s __fvm_p=-1 __fvm_l
        if fv.menus._mref "$1"; then
            if [[ $FV_EV_KEY == kbCtrl[ABCDEFGHIJKLMNOPQRSTUVWXYZ] ]]; then
                __fvm_l=${FV_EV_KEY:6}
                fv.menus._hot "$__fvm_o" "$__fvm_s" "${__fvm_l,,}"
            fi
            if (( __fvm_p < 0 )); then fv.menus._hotKey "$__fvm_o" "$FV_EV_KEY" "$__fvm_s"; fi
            if (( __fvm_p >= 0 )); then
                local -n __fvm_C=${__fvm_o}_mcmd
                if [[ -n ${__fvm_C[__fvm_p]} && -z ${__FV_VW_CMDOFF[${__fvm_C[__fvm_p]}]-} ]]; then
                    fv.menus._post "$1" "${__fvm_C[__fvm_p]}"
                    return 0
                fi
            fi
        fi
        if [[ $FV_EV_KEY == kbAlt[ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789] ]]; then FV_EV_WHAT=evNothing FV_EV_INFO=$1; return 0; fi
    fi
    fv.menus._mvEvent "$1"
}

# fv.menus.newSubView V AX AY BX BY MENU PARENT — FV NewSubView(Bounds, AMenu,
# AParentMenu): a TMenuBox for MENU ("OWNER:S", a submenu of OWNER's items)
# whose parent menu is PARENT, sized inside the bounds (FV TMenuBox.Init);
# named PARENT__fvbox (fv.views' reserved names); RESULT = its name. Not
# inserted anywhere (the caller executes it in its owner and destroys it).
# rc 2 for a malformed call, the constructor's rc when it refuses
fv.menus.newSubView() {
    if (( $# != 7 )); then fv.menus._bad "${FUNCNAME#fv.menus.}" 'wrong argument count'; return; fi
    if [[ -z ${__FV_MN_MV[$1]-} || -z ${__FV_VW_LIVE[$1]-} ]]; then fv.menus._bad newSubView "'$1' is not a menu view"; return; fi
    if [[ -z ${__FV_MN_OWN[${6%:*}]-} || ${6##*:} == *[!0123456789]* || -z ${6##*:} ]]; then fv.menus._bad newSubView "'$6' is not a menu (OWNER:S)"; return; fi
    if [[ -z $7 || -z ${__FV_VW_LIVE[$7]-} ]]; then fv.menus._bad newSubView "'$7' is not a view"; return; fi
    # (kklass's .new under the caller's IFS: K-3; a default IFS for it, local)
    local __fvm_s=0 IFS=$' \t\n'
    __FV_MN_HREF=$6 __FV_MN_HPAR=$7
    fv.views._newReserved "$7" box TMenuBox "$2" "$3" "$4" "$5" || __fvm_s=$?
    __FV_MN_HREF='' __FV_MN_HPAR=''
    if (( __fvm_s )); then return "$__fvm_s"; fi
    __FV_MN_SUB[$RESULT]=1
}

# ---- Execute (FV TMenuView.Execute, menus.inc:538-780) -------------------------------

# TMenuView.Execute (func) — FV's loop, reading its own events from the event
# source (__FV_VW_GETEVENT: the application's GetEvent with its resizes and
# Idle; the end of input latches __FV_VW_EOF and closes every level with no
# command). RESULT = the command chosen, '' for none (FV 0; execView then
# answers cmCancel: __FV_MN_RES tells them apart). The event record is saved
# and put back (FV's local E). rc 2 in a subshell (the BASHPID rule)
fv.menus._mvExecute() {
    fv.views._ownerOk Execute || return
    local -n __fvm_d=${1}_data
    local -a __fvw_es
    local __fvm_o='' __fvm_s=0 __fvm_f=0 __fvm_l=-1 __fvm_cur=-1 __fvm_auto=0 __fvm_act __fvm_res='' __fvm_ma=0
    local __fvm_shown=${__FV_MN_SH[$1]--1} __fvm_par=${__fvm_d[ParentMenu]-} __fvm_rt=$1 __fvm_g=0 __fvm_part='' __fvm_rc __fvm_p
    __FV_MN_RUN[$1]=$(( ${__FV_MN_RUN[$1]:-0} + 1 ))
    fv.views._evSave
    if fv.menus._mref "$1"; then
        local -n __fvm_F=${__fvm_o}_mfirst __fvm_L=${__fvm_o}_mlast __fvm_DF=${__fvm_o}_mdef __fvm_T=${__fvm_o}_mtext \
            __fvm_C=${__fvm_o}_mcmd __fvm_S=${__fvm_o}_msub
        __fvm_f=${__fvm_F[__fvm_s]} __fvm_l=${__fvm_L[__fvm_s]} __fvm_cur=${__fvm_DF[__fvm_s]--1}
    else
        local -a __fvm_T=() __fvm_C=() __fvm_S=() __fvm_DF=()
    fi
    __fvm_d[Current]=$__fvm_cur
    while (( __fvm_g++ < 4096 )); do
        local -n __fvm_rd=${__fvm_rt}_data
        if [[ -z ${__fvm_rd[Owner]-} ]]; then break; fi
        __fvm_rt=${__fvm_rd[Owner]}
    done
    __fvm_p=${1}_class
    __fvm_p="${!__fvm_p-}_class_method_owner[Draw]"
    if [ "${__FV_VW_IMPL[${!__fvm_p-}.Draw]-}" = fv.menus._boxDraw ]; then __fvm_part=1; fi
    while :; do
        __fvm_act=0
        if (( __FV_VW_EOF )); then
            fv.drivers.clearEvent
            __fvm_act=2
        else
            __fvm_rc=0
            "$__FV_VW_GETEVENT" || __fvm_rc=$?
            if (( __fvm_rc )); then
                if (( __fvm_rc != 1 )); then kk.debug "Error: fv.menus.Execute: the event source '$__FV_VW_GETEVENT' failed (rc $__fvm_rc): taken for the end of input"; fi
                __FV_VW_EOF=1
                fv.drivers.clearEvent
                __fvm_act=2
            fi
            if [[ -z $FV_EV_WHAT ]]; then FV_EV_WHAT=evNothing; fi
        fi
        if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then __fvm_res='' __fvm_cur=-1; break; fi
        if [ "$FV_EV_WHAT" != evNothing ]; then
            __FV_VW_LSU=$(( __FV_VW_LSU + 1 )) __FV_VW_EH=$(( __FV_VW_EH + 1 ))
            if [ "$FV_EV_WHAT" = evKeyDown ]; then fv.menus._exKey "$1"
            elif [ "$FV_EV_WHAT" = evCommand ]; then
                if [ "$FV_EV_COMMAND" = cmMenu ]; then
                    __fvm_auto=0
                    if [[ -n $__fvm_par ]]; then __fvm_act=2; fi
                else
                    __fvm_act=2
                fi
            elif [[ $FV_EV_WHAT == evMouse* ]]; then fv.menus._exMouse "$1"
            fi
            __fvm_d[Current]=$__fvm_cur
            if (( __fvm_shown != __fvm_cur )); then fv.menus._exShow "$1"; fi
            if (( __fvm_act == 1 || (__fvm_act == 0 && __fvm_auto) )) && (( __fvm_cur >= 0 )) && [[ -n ${__fvm_T[__fvm_cur]-} ]]; then
                if [[ -z ${__fvm_C[__fvm_cur]} ]]; then fv.menus._exDrop "$1"
                elif (( __fvm_act == 1 )); then __fvm_res=${__fvm_C[__fvm_cur]}; fi
            fi
            if [[ -n $__fvm_res && -z ${__FV_VW_CMDOFF[$__fvm_res]-} ]]; then
                __fvm_act=2
                FV_EV_WHAT=evNothing FV_EV_INFO=$1
            else
                __fvm_res=''
            fi
            __FV_VW_LSU=$(( __FV_VW_LSU - 1 )) __FV_VW_EH=$(( __FV_VW_EH - 1 ))
            if (( __FV_VW_LSU < 0 )); then __FV_VW_LSU=0; fi
            if (( __FV_VW_EH < 0 )); then __FV_VW_EH=0; fi
            if [[ -n ${__FV_VW_LIVE[$__fvm_rt]-} ]]; then fv.views._resetCursor "$__fvm_rt"; fi
            fv.views._showNow
            if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then __fvm_res='' __fvm_cur=-1; break; fi
        fi
        if (( __fvm_act == 2 )); then break; fi
    done
    if [ "$FV_EV_WHAT" != evNothing ] && { [[ -n $__fvm_par ]] || [ "$FV_EV_WHAT" = evCommand ]; }; then "$__FV_VW_PUTEVENT" || :; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        __fvm_d[Current]=-1
        if (( __fvm_cur >= 0 )); then
            __fvm_DF[__fvm_s]=$__fvm_cur
            # (a box newSubView made is removed right after: not redrawn)
            if [[ -z ${__FV_MN_SUB[$1]-} ]]; then fv.views.drawView "$1" || :; fi
        fi
    fi
    if (( ${__FV_MN_RUN[$1]:-1} > 1 )); then __FV_MN_RUN[$1]=$(( __FV_MN_RUN[$1] - 1 )); else unset '__FV_MN_RUN[$1]'; fi
    fv.views._evRestore
    __FV_MN_RES=$__fvm_res
    RESULT=$__fvm_res
}

# fv.menus._exShow V — (Execute's locals) FV: OldItem := ItemShown, ItemShown
# := Current, DrawView, OldItem := nil. A box with the built-in Draw repaints
# the old and the new item's row (two one-row drawParts, FV's OldItem
# trick); any other view is drawn whole
fv.menus._exShow() {
    local __fvm_old=$__fvm_shown __fvm_y
    __fvm_d[OldItem]=$__fvm_old
    if [[ -n $__fvm_part ]]; then
        if (( __fvm_old >= __fvm_f && __fvm_old <= __fvm_l )); then
            __fvm_y=$(( 1 + __fvm_old - __fvm_f ))
            fv.views.drawPart "$1" fv.menus._boxPaint "$__fvm_y" "$(( __fvm_y + 1 ))" "$__fvm_y" || :
        fi
        if (( __fvm_cur >= __fvm_f && __fvm_cur <= __fvm_l )); then
            __fvm_y=$(( 1 + __fvm_cur - __fvm_f ))
            fv.views.drawPart "$1" fv.menus._boxPaint "$__fvm_y" "$(( __fvm_y + 1 ))" "$__fvm_y" || :
        fi
    else
        fv.views.drawView "$1" || :
    fi
    __fvm_shown=$__fvm_cur __FV_MN_SH[$1]=$__fvm_cur
    __fvm_d[OldItem]=-1
}

# fv.menus._exKey V — (Execute's locals) FV's evKeyDown case
fv.menus._exKey() {
    local __fvm_k=${__FV_VW_C2A[${FV_EV_KEY:-kbNoKey}]-$FV_EV_KEY} __fvm_sy="${1}_data[SizeY]" __fvm_q
    __fvm_sy=${!__fvm_sy:-0}
    if [ "$__fvm_k" = kbUp ] || [ "$__fvm_k" = kbDown ]; then
        if (( __fvm_sy != 1 )); then fv.menus._trackKey "$__fvm_k"
        elif [ "$FV_EV_KEY" = kbDown ]; then __fvm_auto=1; fi
    elif [ "$__fvm_k" = kbLeft ] || [ "$__fvm_k" = kbRight ]; then
        if [[ -z $__fvm_par ]]; then
            if [ "$__fvm_k" = kbRight ]; then fv.menus._trackKey kbDown; else fv.menus._trackKey kbUp; fi
        else
            __fvm_act=2
        fi
    elif [ "$__fvm_k" = kbHome ] || [ "$__fvm_k" = kbEnd ]; then
        if (( __fvm_sy != 1 )); then
            if (( __fvm_l >= __fvm_f )); then __fvm_cur=$__fvm_f; fi
            if [ "$FV_EV_KEY" = kbEnd ]; then fv.menus._trackKey kbUp; fi
        fi
    elif [ "$__fvm_k" = kbEnter ]; then
        if (( __fvm_sy == 1 )); then __fvm_auto=1; fi
        __fvm_act=1
    elif [ "$__fvm_k" = kbEsc ]; then
        __fvm_act=2
        __fvm_q=0
        if [[ -n $__fvm_par ]]; then __fvm_q="${__fvm_par}_data[SizeY]" __fvm_q=${!__fvm_q:-0}; fi
        if [[ -z $__fvm_par ]] || (( __fvm_q != 1 )); then FV_EV_WHAT=evNothing FV_EV_INFO=$1; fi
    else
        fv.menus._exHot "$1"
    fi
}
# fv.menus._exHot V — (Execute's locals) FV's other keys: with Alt the TOP
# menu's hot letter (Target = TopMenu), without Alt this menu's (a plain
# typed character: kbChar); found in this menu -> select it (a bar:
# AutoSelect); found in the top menu while this is a box -> return (the event
# goes up, unless the parent already shows that item); none -> TopMenu's
# HotKey: an enabled command ends the menu with it
fv.menus._exHot() {
    local __fvm_tg=$1 __fvm_g=0 __fvm_x __fvm_p=-1 __fvm_to='' __fvm_ts='' __fvm_sy="${1}_data[SizeY]"
    __fvm_sy=${!__fvm_sy:-0}
    while (( __fvm_g++ < 64 )); do
        __fvm_x="${__fvm_tg}_data[ParentMenu]" __fvm_x=${!__fvm_x-}
        if [[ -z $__fvm_x || -z ${__FV_VW_LIVE[$__fvm_x]-} ]]; then break; fi
        __fvm_tg=$__fvm_x
    done
    fv.menus._topRef "$__fvm_tg"
    if [[ $FV_EV_KEY == kbAlt* ]]; then
        if [[ -n $__fvm_to ]]; then fv.menus._find "$__fvm_to" "$__fvm_ts"; fi
    elif [ "$FV_EV_KEY" = kbChar ]; then
        __fvm_tg=$1
        if [[ -n $__fvm_o ]]; then fv.menus._find "$__fvm_o" "$__fvm_s"; fi
    fi
    if (( __fvm_p >= 0 )); then
        if [ "$__fvm_tg" = "$1" ]; then
            if (( __fvm_sy == 1 )); then __fvm_auto=1; fi
            __fvm_act=1 __fvm_cur=$__fvm_p
        else
            __fvm_x="${__fvm_par}_data[Current]"
            if ! [ "$__fvm_par" = "$__fvm_tg" ] || ! [ "${!__fvm_x--1}" = "$__fvm_p" ]; then __fvm_act=2; fi
        fi
        return 0
    fi
    # (FV's third case: TopMenu^.HotKey, the F-keys and the other mapped keys)
    if [[ -n $__fvm_to ]]; then
        fv.menus._hotKey "$__fvm_to" "$FV_EV_KEY" "$__fvm_ts"
        if (( __fvm_p >= 0 )); then
            __fvm_x="${__fvm_to}_mcmd[$__fvm_p]" __fvm_x=${!__fvm_x-}
            if [[ -n $__fvm_x && -z ${__FV_VW_CMDOFF[$__fvm_x]-} ]]; then __fvm_res=$__fvm_x __fvm_act=2; fi
        fi
    fi
}
# fv.menus._topRef V — the caller's __fvm_to / __fvm_ts = V's menu ('' none)
fv.menus._topRef() {
    local __fvm_o __fvm_s
    if fv.menus._mref "$1"; then __fvm_to=$__fvm_o __fvm_ts=$__fvm_s; else __fvm_to='' __fvm_ts=''; fi
}
# fv.menus._trackKey KEY — (Execute's locals) FV TrackKey(FindNext): from Current
# to the next (kbDown) / previous (kbUp) item with a name, wrapping; nothing
# without a Current (and nothing found among separators only)
fv.menus._trackKey() {
    local __fvm_n=$(( __fvm_l - __fvm_f + 1 )) __fvm_c=$__fvm_cur
    if (( __fvm_c < 0 || __fvm_n <= 0 )); then return 0; fi
    while (( __fvm_n-- > 0 )); do
        if [ "$1" = kbDown ]; then
            __fvm_c=$(( __fvm_c + 1 ))
            if (( __fvm_c > __fvm_l )); then __fvm_c=$__fvm_f; fi
        else
            __fvm_c=$(( __fvm_c - 1 ))
            if (( __fvm_c < __fvm_f )); then __fvm_c=$__fvm_l; fi
        fi
        if [[ -n ${__fvm_T[__fvm_c]} ]]; then __fvm_cur=$__fvm_c; return 0; fi
    done
}

# fv.menus._exMouse V — (Execute's locals) FV's mouse cases
fv.menus._exMouse() {
    local __fvm_iv=0 __fvm_io=0
    fv.menus._inView "$1" && __fvm_iv=1
    fv.menus._inOwner && __fvm_io=1
    if [ "$FV_EV_WHAT" = evMouseDown ]; then
        if (( __fvm_iv || __fvm_io )); then
            fv.menus._trackMouse "$1"
            local __fvm_q="${1}_data[SizeY]"
            if (( ${!__fvm_q:-0} == 1 )); then __fvm_auto=1; fi
        else
            __fvm_act=2
        fi
    elif [ "$FV_EV_WHAT" = evMouseUp ]; then
        fv.menus._trackMouse "$1"
        fv.menus._inOwner && __fvm_io=1 || __fvm_io=0
        if (( __fvm_io )); then
            __fvm_cur=${__fvm_DF[__fvm_s]--1}
        elif (( __fvm_cur >= 0 )) && [[ -n ${__fvm_T[__fvm_cur]} ]]; then
            __fvm_act=1
        elif (( __fvm_ma || __fvm_iv )); then
            __fvm_act=2
        else
            __fvm_cur=${__fvm_DF[__fvm_s]--1}
            if (( __fvm_cur < 0 && __fvm_l >= __fvm_f )); then __fvm_cur=$__fvm_f; fi
        fi
    elif [ "$FV_EV_WHAT" = evMouseMove ]; then
        if [[ -n $FV_EV_MOUSE_BUTTONS && $FV_EV_MOUSE_BUTTONS != 0 ]]; then
            fv.menus._trackMouse "$1"
            fv.menus._inOwner && __fvm_io=1 || __fvm_io=0
            if (( ! __fvm_iv && ! __fvm_io )) && fv.menus._inMenus; then __fvm_act=2; fi
        fi
    fi
}
# fv.menus._inView V — rc 0 when the event's point lies in V (FV MouseInView)
fv.menus._inView() {
    local -n __fvm_vd=${1}_data
    local __fvm_x=$(( FV_EV_MOUSE_X - ${__FV_VW_AX[$1]:-0} )) __fvm_y=$(( FV_EV_MOUSE_Y - ${__FV_VW_AY[$1]:-0} ))
    (( __fvm_x >= 0 && __fvm_y >= 0 && __fvm_x < ${__fvm_vd[SizeX]:-0} && __fvm_y < ${__fvm_vd[SizeY]:-0} ))
}
# fv.menus._inOwner — (Execute's locals) FV MouseInOwner: the point lies on the
# parent's current item, the parent a one-row menu (a bar)
fv.menus._inOwner() {
    if [[ -z $__fvm_par || -z ${__FV_VW_LIVE[$__fvm_par]-} ]]; then return 1; fi
    local -n __fvm_pd=${__fvm_par}_data
    if (( ${__fvm_pd[SizeY]:-0} != 1 )); then return 1; fi
    fv.views._virt "$__fvm_par" GetItemRect "${__fvm_pd[Current]:--1}" || :
    local __fvm_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$__fvm_par] )) __fvm_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$__fvm_par] ))
    (( __fvm_x >= FV_RECT_AX && __fvm_x < FV_RECT_BX && __fvm_y >= FV_RECT_AY && __fvm_y < FV_RECT_BY ))
}
# fv.menus._inMenus — (Execute's locals) FV MouseInMenus: the point lies in a
# parent menu (any level up)
fv.menus._inMenus() {
    local __fvm_v=$__fvm_par __fvm_g=0
    while [[ -n $__fvm_v && -n ${__FV_VW_LIVE[$__fvm_v]-} ]] && (( __fvm_g++ < 64 )); do
        if fv.menus._inView "$__fvm_v"; then return 0; fi
        __fvm_v="${__fvm_v}_data[ParentMenu]" __fvm_v=${!__fvm_v-}
    done
    return 1
}
# fv.menus._trackMouse V — (Execute's locals) FV TrackMouse: Current = the
# item whose rect (GetItemRect, virtual) holds the point (MouseActive set),
# else none. The built-in GetItemRects' rects are worked out here in one
# pass (a box: one test; a bar: the widths summed once — its GetItemRect
# sums them from the first item on every call); a class with its own
# GetItemRect is asked per item
fv.menus._trackMouse() {
    local __fvm_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvm_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] )) __fvm_i __fvm_k=${1}_class
    __fvm_k="${!__fvm_k-}_class_method_owner[GetItemRect]"
    __fvm_k=${__FV_VW_IMPL[${!__fvm_k-}.GetItemRect]-}
    # (no menu, or its owner gone mid-run: the generic path, as before)
    if [[ -z $__fvm_o || -z ${__FV_MN_OWN[$__fvm_o]-} ]]; then __fvm_k=''; fi
    if [ "$__fvm_k" = fv.menus._boxItemRect ]; then
        # (item i: row 1 + i - first, columns 2 .. SizeX-3)
        __fvm_k="${1}_data[SizeX]" __fvm_i=$(( __fvm_f + __fvm_y - 1 ))
        if (( __fvm_y >= 1 && __fvm_i <= __fvm_l && __fvm_x >= 2 && __fvm_x < ${!__fvm_k:-0} - 2 )); then __fvm_ma=1 __fvm_cur=$__fvm_i; else __fvm_cur=-1; fi
        return 0
    fi
    if [ "$__fvm_k" = fv.menus._barItemRect ]; then
        # (row 0; item i from the sum of the widths before it, ' NAME ' wide)
        __fvm_cur=-1
        if (( __fvm_y != 0 || __fvm_x < 0 )); then return 0; fi
        if ! [ "${__FV_MN_MAM[$__fvm_o]-}" = "${FV_VIDEO_ASCII:-0}" ]; then fv.menus._mpats "$__fvm_o"; fi
        local -n __fvm_pp=${__fvm_o}_mpp
        __fvm_k=0
        for (( __fvm_i = __fvm_f; __fvm_i <= __fvm_l; __fvm_i++ )); do
            __fvm_k=$(( __fvm_k + ${#__fvm_pp[__fvm_i]} ))
            if (( __fvm_x < __fvm_k )); then __fvm_ma=1 __fvm_cur=$__fvm_i; return 0; fi
        done
        return 0
    fi
    for (( __fvm_i = __fvm_f; __fvm_i <= __fvm_l; __fvm_i++ )); do
        fv.views._virt "$1" GetItemRect "$__fvm_i" || :
        if (( __fvm_x >= FV_RECT_AX && __fvm_x < FV_RECT_BX && __fvm_y >= FV_RECT_AY && __fvm_y < FV_RECT_BY )); then
            __fvm_ma=1 __fvm_cur=$__fvm_i
            return 0
        fi
    done
    __fvm_cur=-1
}

# fv.menus._exDrop V — (Execute's locals) FV: the current item is a submenu:
# a mouse event put back for the box, the box under the item (from the
# item's left edge and its bottom, to the owner's size: newSubView), run by
# V's owner (execView), destroyed; its answer is Res
fv.menus._exDrop() {
    local __fvm_w="${1}_data[Owner]" __fvm_b __fvm_ax __fvm_ay __fvm_bx __fvm_by __fvm_r=''
    __fvm_w=${!__fvm_w-}
    if [[ -z $__fvm_w || -z ${__FV_VW_LIVE[$__fvm_w]-} ]]; then return 0; fi
    if [ "$FV_EV_WHAT" = evMouseDown ] || [ "$FV_EV_WHAT" = evMouseMove ]; then "$__FV_VW_PUTEVENT" || :; fi
    fv.views._virt "$1" GetItemRect "$__fvm_cur" || :
    local -n __fvm_wd=${__fvm_w}_data
    __fvm_ax=$(( FV_RECT_AX + ${__fvm_d[OriginX]:-0} )) __fvm_ay=$(( FV_RECT_BY + ${__fvm_d[OriginY]:-0} ))
    __fvm_bx=${__fvm_wd[SizeX]:-0} __fvm_by=${__fvm_wd[SizeY]:-0}
    fv.menus.newSubView "$1" "$__fvm_ax" "$__fvm_ay" "$__fvm_bx" "$__fvm_by" "$__fvm_o:${__fvm_S[__fvm_cur]}" "$1" || return 0
    __fvm_b=$RESULT
    __FV_MN_RES=''
    if fv.views.execView "$__fvm_w" "$__fvm_b"; then
        __fvm_r=${RESULT-}
        if [ "$__fvm_r" = cmCancel ] && ! [ "$__FV_MN_RES" = cmCancel ]; then __fvm_r=''; fi
    fi
    fv.menus._del "$__fvm_b"
    __fvm_res=$__fvm_r
}
# fv.menus._del V — V.delete when V is a live view (kklass's .delete with a
# default IFS, local: the caller's may break it, K-3)
fv.menus._del() {
    local IFS=$' \t\n'
    if [[ -n ${__FV_VW_LIVE[$1]-} ]] && declare -F "$1.delete" >/dev/null; then "$1.delete"; fi
    return 0
}

# ---- the bar on request (D23, 10.10) ---------------------------------------------

# fv.menus.menuBar [LIST] — the application's menu bar from the flat item
# list (TMenuView's LIST: item / line / sub … end): a TMenuBar on row 0 of the
# application (FV_APP), named APP__fvmenubar, FV_MENUBAR = it, the desktop
# from row 1 (fv.views.locate; its other edges kept). In the application's
# InitMenuBar it only makes the bar (TProgram.Init inserts it and InitDesktop
# leaves row 0 to it); after Init it is inserted in front and the desktop
# moved, as one terminal update. Called again: the old bar is replaced; with
# no LIST it is removed and the desktop gets row 0 back. A malformed list
# changes nothing (rc 2, the constructor's Error line); rc 2 without a live
# application. While a menu view's Execute runs (the bar or any box: a hook
# of the event source, Idle) it refuses: rc 2, one debug line, nothing
# changed (the running loop would go on with the new bar). RESULT is kept
fv.menus.menuBar() {
    if [[ -z ${FV_APP-} || -z ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.menus._bad menuBar 'no application (FV_APP)'; return; fi
    if (( ${#__FV_MN_RUN[@]} )); then
        local __fvm_v
        for __fvm_v in "${!__FV_MN_RUN[@]}"; do
            if [[ -n ${__FV_VW_LIVE[$__fvm_v]-} ]]; then kk.debug "Error: fv.menus.menuBar: refused while the menu '$__fvm_v' runs: call it after the menu closes"; return 2; fi
        done
    fi
    local __fvm_rr=${RESULT-} __fvm_a=$FV_APP __fvm_old=${FV_MENUBAR-} __fvm_n __fvm_i=${__FV_AP_ININIT:-0} __fvm_s=0
    if (( $# )); then
        local -a __fvm_tt=() __fvm_tp=() __fvm_tk=() __fvm_tc=() __fvm_th=() __fvm_ts=() __fvm_sl=()
        fv.menus._mparse menuBar "$@" || { RESULT=$__fvm_rr; return 2; }
    fi
    local -n __fvm_ad=${__fvm_a}_data
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
    if [[ -n $__fvm_old && -n ${__FV_VW_LIVE[$__fvm_old]-} ]]; then
        local -n __fvm_od=${__fvm_old}_data
        if [ "${__fvm_od[Owner]-}" = "$__fvm_a" ]; then fv.views.delete "$__fvm_a" "$__fvm_old" || :; fi
        fv.menus._del "$__fvm_old"
    fi
    FV_MENUBAR=''
    if (( $# )); then
        if fv.menus._newBar "$__fvm_a" "${__fvm_ad[SizeX]:-0}" "$@"; then
            FV_MENUBAR=$RESULT
            if (( ! __fvm_i )); then fv.views.insert "$__fvm_a" "$FV_MENUBAR" || :; fi
        fi
    fi
    if (( ! __fvm_i )); then fv.menus._deskRow; fi
    fv.views._release
    RESULT=$__fvm_rr
    return "$__fvm_s"
}
# fv.menus._newBar APP W LIST... — the bar APP__fvmenubar (kklass's .new with
# a default IFS, local: K-3); RESULT = its name
fv.menus._newBar() {
    local IFS=$' \t\n'
    fv.views._newReserved "$1" menubar TMenuBar 0 0 "$2" 1 "${@:3}"
}
# fv.menus._deskRow — the desktop's top edge: row 1 under a live bar, else 0
fv.menus._deskRow() {
    local __fvm_k=${FV_DESKTOP-} __fvm_y=0
    if [[ -z $__fvm_k || -z ${__FV_VW_LIVE[$__fvm_k]-} ]]; then return 0; fi
    if [[ -n ${FV_MENUBAR-} && -n ${__FV_VW_LIVE[$FV_MENUBAR]-} ]]; then __fvm_y=1; fi
    local -n __fvm_kd=${__fvm_k}_data
    if (( ${__fvm_kd[OriginY]:-0} == __fvm_y )); then return 0; fi
    local __fvm_by=$(( ${__fvm_kd[OriginY]:-0} + ${__fvm_kd[SizeY]:-0} ))
    if (( __fvm_by < __fvm_y )); then __fvm_by=$__fvm_y; fi
    fv.views.locate "$__fvm_k" "${__fvm_kd[OriginX]:-0}" "$__fvm_y" "$(( ${__fvm_kd[OriginX]:-0} + ${__fvm_kd[SizeX]:-0} ))" "$__fvm_by" || :
}
