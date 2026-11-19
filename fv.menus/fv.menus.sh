#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.menus.sh}../../kbool.sh" || return
kk.unit fv.menus || return $__kk_unit_rc

# fv.menus — Free Vision's menus unit for the fv.* text UI (layer L2): P2
# stage 2e brings TStatusLine (FV menus.inc: TStatusLine, TStatusDef /
# TStatusItem, NewStatusDef / NewStatusKey, Draw / DrawSelect, FindItems,
# HandleEvent with the mouse press tracking, Hint, Update) as a kklass class
# on top of fv.views' TView. TMenuBar / TMenuBox come with P3 (O3).
# Design: kcl/docs/dev/fv/P2_DESIGN.md (§1.2, §1.3, §1.5, §1.8, §1.9, §2.1);
# API and deviations: README.md.
#
# Conventions (as fv.views'): locals `__fvm_*`; fields of other instances
# read and written through `${v}_data` (kklass friend contract, decision
# D19), reads as `${d[F]-}`; fork-free and set -eu clean; no `[[ == ]]` /
# `case` / `${x//}` between two names (nocasematch); procedures leave RESULT
# as it was, getters answer in it; a refused call is rc 2 with RESULT='' and
# a kk.debug line, a malformed constructor list one `Error:` line.
#
# Every built-in virtual of TStatusLine (Draw HandleEvent GetPalette Hint
# Update) has its body in a plain function registered in fv.views' elision
# table __FV_VW_IMPL, so the framework runs it without a kklass dispatch
# unless a class of yours overrides it (fv.views README, "Virtual elision").
#
# Friend uses of fv.views' private parts (this unit belongs to the same
# framework; README "Contract and deviations"): reads of __FV_VW_LIVE (a
# live view), __FV_VW_CRC (a refused TView part's rc), __FV_VW_ERRSYM, the
# disabled-command set __FV_VW_CMDOFF (one array read per item instead of a
# call) and the event hooks __FV_VW_PUTEVENT / __FV_VW_EOF; entries added to
# the elision table __FV_VW_IMPL; calls of fv.views._virt (the elision
# entry), fv.views._topView (FV TopView) and fv.views._viewEvent
# (TView.HandleEvent's body).

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
    declare -gA "${1}_skey=()"
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
        "${1}_sinext" "${1}_siplain" "${1}_sipat" "${1}_skey" \
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
# screen's ASCII mode (FV CStrLen / CTextWidth: `~` takes no cell; a wide
# character 2 cells, fv.video's width table). A text whose parts measure
# differently from the whole (a cluster cut by a `~`) is drawn in Lo only
fv.menus._pats() {
    local -n __fvm_t=${1}_sitext __fvm_pl=${1}_siplain __fvm_pp=${1}_sipat
    local __fvm_j __fvm_s __fvm_r __fvm_p __fvm_w __fvm_h __fvm_m __fvm_rr=${RESULT-}
    __fvm_pl=() __fvm_pp=()
    for (( __fvm_j = 0; __fvm_j < ${#__fvm_t[@]}; __fvm_j++ )); do
        __fvm_s=" ${__fvm_t[__fvm_j]} " __fvm_p='' __fvm_h=0
        while :; do
            __fvm_r=${__fvm_s%%'~'*}
            if [[ -n $__fvm_r ]]; then
                fv.video.strWidth "$__fvm_r" || RESULT=${#__fvm_r}
                printf -v __fvm_m '%*s' "$RESULT" ''
                if (( __fvm_h )); then __fvm_p+=${__fvm_m// /-}; else __fvm_p+=${__fvm_m// /+}; fi
            fi
            if [ "$__fvm_r" = "$__fvm_s" ]; then break; fi
            __fvm_s=${__fvm_s#*'~'} __fvm_h=$(( ! __fvm_h ))
        done
        __fvm_s=" ${__fvm_t[__fvm_j]//'~'/} "
        fv.video.strWidth "$__fvm_s" || RESULT=${#__fvm_s}
        __fvm_w=$RESULT
        if (( ${#__fvm_p} != __fvm_w )); then printf -v __fvm_p '%*s' "$__fvm_w" ''; __fvm_p=${__fvm_p// /+}; fi
        __fvm_pl+=("$__fvm_s") __fvm_pp+=("$__fvm_p")
    done
    __FV_MN_AM[$1]=${FV_VIDEO_ASCII:-0}
    RESULT=$__fvm_rr
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
# shown after the items for a help context)
fv.menus._hint() { RESULT=''; }

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
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF")
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
    FV_EV_MOUSE_TRIPLE=${__fvm_es[11]} FV_EV_WHEEL=${__fvm_es[12]} FV_EV_EOF=${__fvm_es[13]}
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
