#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.msgbox.sh}../../kbool.sh" || return
kk.unit fv.msgbox || return $__kk_unit_rc

# fv.msgbox — Free Vision's MsgBox unit for the fv.* text UI (layer L3, P3
# stage 3e, design kcl/docs/dev/fv/P3_DESIGN.md §6, P3-9): plain functions
# that build a dialog, run it modal and destroy it, answering the command in
# RESULT. No classes, no forks; API and deviations: README.md.
#
#   fv.msgbox.messageBox MSG OPTIONS [-- PARAMS...]
#                         FV MessageBox(Msg, Params, AOptions): a 40x9 TDialog
#                         centred on the desktop (on the application with
#                         FV_MF_INSERTINAPP), MSG (through `printf -v` with
#                         PARAMS after `--`: FV's FormatStr) in a TStaticText,
#                         the buttons OPTIONS names; RESULT = the command
#   fv.msgbox.messageBoxRect AX AY BX BY MSG OPTIONS [-- PARAMS...]
#                         FV MessageBoxRect: the same over an explicit
#                         rectangle (the owner's coordinates, B exclusive)
#   fv.msgbox.inputBox [-p] TITLE LABEL VARNAME LIMIT
#                         FV InputBox(Title, ALabel, S, Limit): a 60x8
#                         TDialog centred on the desktop, a TLabel, a
#                         TInputLine of LIMIT clusters (-p: PasswordChar '*')
#                         holding VARNAME's value, OK (default) and Cancel;
#                         VARNAME := the text unless cancelled (FV's var S);
#                         RESULT = the command
#   fv.msgbox.inputBoxRect [-p] AX AY BX BY TITLE LABEL VARNAME LIMIT
#                         FV InputBoxRect: the same over an explicit rectangle
#
# OPTIONS is one integer, the FV_MF_* flags OR'd (FV values, readonly). Esc,
# Ctrl+F4, the close icon and the end of input answer cmCancel. Titles and
# button labels: FV_MSGBOX_TITLES / FV_MSGBOX_BUTTONS (README "Translations").
#
# Each call builds, runs and destroys its dialog (FV) under the reserved name
# ${FV_DESKTOP}__fvmsgbox (a nested box — one opened while another runs,
# from a Valid handler or an event source — takes the first free
# __fvmsgbox2, __fvmsgbox3, ...), its controls under the dialog's name
# (fv.views' _newReserved). After the end of input (fv.views' latch) a box
# answers cmCancel at once.
#
# Refusals: in a process that does not own the screen (inside $( ), a
# pipeline; fv.views' owner rule) rc 2 with one `Error: fv.msgbox:` line on
# stderr (VERBOSE_KKLASS=quiet silences it) and nothing drawn; a malformed
# call or no application (FV_DESKTOP not a live group; with
# FV_MF_INSERTINAPP FV_APP too) rc 2, RESULT='' and a kk.debug line.
#
# Conventions: locals `__fvx_*` (fv.drivers has __fvd_, fv.dialogs __fvg_);
# fork-free and set -eu clean; names compared with `[ "$a" = "$b" ]`
# (nocasematch). Friend uses (the same framework): reads of fv.views'
# __FV_VW_LIVE, __FV_VW_GRP, __FV_VW_OWNER and the views' `_data` fields;
# calls of fv.views._newReserved and fv.dialogs._ptCount, fv.dialogs._aname.

kk.uses fv.dialogs || return

# ---- constants (FV msgbox.pas; readonly once per process) -----------------------
if [[ -z ${FV_MF_WARNING+x} || ${FV_MF_WARNING@a} != *r* ]]; then
    FV_MF_WARNING=0 FV_MF_ERROR=1 FV_MF_INFORMATION=2 FV_MF_CONFIRMATION=3 FV_MF_INSERTINAPP=128
    FV_MF_YESBUTTON=256 FV_MF_NOBUTTON=512 FV_MF_OKBUTTON=1024 FV_MF_CANCELBUTTON=2048
    FV_MF_YESNOCANCEL=2816 FV_MF_OKCANCEL=3072
    readonly FV_MF_WARNING FV_MF_ERROR FV_MF_INFORMATION FV_MF_CONFIRMATION FV_MF_INSERTINAPP \
        FV_MF_YESBUTTON FV_MF_NOBUTTON FV_MF_OKBUTTON FV_MF_CANCELBUTTON FV_MF_YESNOCANCEL FV_MF_OKCANCEL
fi

# ---- translations (FV's resourcestrings; a script may replace any element) --------
# FV_MSGBOX_TITLES[OPTIONS & 3]: the message box's title (FV MsgBoxTitles:
# sWarning sError sInformation sConfirm). FV_MSGBOX_BUTTONS: 0-3 the message
# box's buttons in FV's order (FV ButtonName: slYes slNo slOk slCancel), 4-5
# the input box's OK and Cancel (FV's literals there). An element unset or
# '' takes the default. Kept across a reload and as the caller set them
# before the load.
if [[ -z ${FV_MSGBOX_TITLES[*]+x} ]]; then declare -ga FV_MSGBOX_TITLES=(Warning Error Information Confirm); fi
if [[ -z ${FV_MSGBOX_BUTTONS[*]+x} ]]; then declare -ga FV_MSGBOX_BUTTONS=('~Y~es' '~N~o' 'O~k~' 'Cancel' 'O~K~' 'Cancel'); fi
declare -ga __FV_MB_TDEF=(Warning Error Information Confirm)
declare -ga __FV_MB_BDEF=('~Y~es' '~N~o' 'O~k~' 'Cancel' 'O~K~' 'Cancel')
declare -ga __FV_MB_CMD=(cmYes cmNo cmOK cmCancel)

# ---- helpers ----------------------------------------------------------------------
# fv.msgbox._bad CALLER MSG — a malformed call: RESULT='', a debug line, rc 2
fv.msgbox._bad() {
    RESULT=''
    kk.debug "Error: fv.msgbox.$1: $2"
    return 2
}
# fv.msgbox._owner CALLER — rc 0 in the process that owns the screen
# (fv.views' __FV_VW_OWNER: its execView would refuse anywhere else); else
# one Error line on stderr (unless VERBOSE_KKLASS=quiet), RESULT='', rc 2,
# before anything is made or drawn
fv.msgbox._owner() {
    if [ "$BASHPID" = "${__FV_VW_OWNER-}" ]; then return 0; fi
    RESULT=''
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then
        printf 'Error: fv.msgbox: %s: refused in a subshell (BASHPID %s; the screen belongs to %s): call it in the shell that owns the screen\n' \
            "$1" "$BASHPID" "${__FV_VW_OWNER-}" >&2
    fi
    return 2
}
# fv.msgbox._int VALUE — rc 0 for an integer: an optional '-', 1-9 digits
fv.msgbox._int() {
    local __fvx_t=${1#-}
    [[ -n $__fvx_t && $__fvx_t != *[!0123456789]* && ${#__fvx_t} -le 9 ]]
}
# fv.msgbox._group V — rc 0 for a live group
fv.msgbox._group() {
    [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} && -n ${__FV_VW_GRP[$1]-} ]]
}
# fv.msgbox._name — the caller's __fvx_d = the first free name of the
# family ${FV_DESKTOP}__fvmsgbox, __fvmsgbox2, ... and __fvx_role its role
fv.msgbox._name() {
    local __fvx_i=1
    __fvx_role=msgbox
    while [[ -n ${__FV_VW_LIVE[${FV_DESKTOP}__fv$__fvx_role]-} ]]; do
        __fvx_i=$(( __fvx_i + 1 )) __fvx_role=msgbox$__fvx_i
    done
    __fvx_d=${FV_DESKTOP}__fv$__fvx_role
}
# fv.msgbox._opts CALLER OPTIONS — the message box's OPTIONS (the caller's
# __fvx_o: one integer 0-65535, FV's Word) and the owner (__fvx_g: the
# desktop, the application with FV_MF_INSERTINAPP) checked; rc 2 (_bad)
# otherwise. PARAMS are checked by the caller (`--` first)
fv.msgbox._opts() {
    if [[ -n $2 && $2 != *[!0123456789]* && ${#2} -le 5 ]] && (( 10#$2 <= 65535 )); then
        __fvx_o=$(( 10#$2 ))
    else
        fv.msgbox._bad "$1" "OPTIONS must be one integer 0-65535, the FV_MF_* flags OR'd (got: '$2')"; return
    fi
    __fvx_g=${FV_DESKTOP-}
    if (( __fvx_o & FV_MF_INSERTINAPP )); then __fvx_g=${FV_APP-}; fi
    if ! fv.msgbox._group "${FV_DESKTOP-}" || ! fv.msgbox._group "$__fvx_g"; then
        fv.msgbox._bad "$1" "no application (FV_DESKTOP '${FV_DESKTOP-}', FV_APP '${FV_APP-}' must be live groups: make the application first)"; return
    fi
}
# fv.msgbox._var CALLER VARNAME LIMIT — inputBox's VARNAME (as fv.views'
# array names: an identifier, not RESULT, not _fv* / __fv*; not readonly,
# not an associative array) and LIMIT (digits), and the application
fv.msgbox._var() {
    if ! fv.dialogs._aname "$2"; then fv.msgbox._bad "$1" "'$2' is not a usable variable name (an identifier; not RESULT, _fv* or __fv*)"; return; fi
    # (the attributes of a variable that may be unset, also under the
    # caller's set -u: `local -` restores the option at the return)
    local - __fvx_a
    set +u
    local -n __fvx_vr=$2
    __fvx_a=${__fvx_vr@a}
    if ! [ "${__fvx_a#*[rA]}" = "$__fvx_a" ]; then fv.msgbox._bad "$1" "'$2' is readonly or an associative array"; return; fi
    if [[ -z $3 || $3 == *[!0123456789]* || ${#3} -gt 9 ]]; then fv.msgbox._bad "$1" "LIMIT must be digits (got: '$3')"; return; fi
    if ! fv.msgbox._group "${FV_DESKTOP-}"; then
        fv.msgbox._bad "$1" "no application (FV_DESKTOP '${FV_DESKTOP-}' must be a live group: make the application first)"; return
    fi
}

# ---- the message box (FV MessageBox, MessageBoxRect, MessageBoxRectDlg) -------------
# fv.msgbox.messageBox MSG OPTIONS [-- PARAMS...] — FV MessageBox: R :=
# (0, 0, 40, 9) moved to the owner's centre ((Size - R.B) div 2), then
# MessageBoxRect. RESULT = the command
fv.msgbox.messageBox() {
    fv.msgbox._owner messageBox || return
    if (( $# < 2 )); then fv.msgbox._bad messageBox 'MSG OPTIONS [-- PARAMS...]: wrong argument count'; return; fi
    if (( $# > 2 )) && ! [ "$3" = -- ]; then fv.msgbox._bad messageBox "PARAMS follow '--' (got: '$3')"; return; fi
    local __fvx_o __fvx_g __fvx_ax __fvx_ay
    fv.msgbox._opts messageBox "$2" || return
    local -n __fvx_gd=${__fvx_g}_data
    __fvx_ax=$(( (${__fvx_gd[SizeX]:-0} - 40) / 2 )) __fvx_ay=$(( (${__fvx_gd[SizeY]:-0} - 9) / 2 ))
    fv.msgbox._box "$__fvx_ax" "$__fvx_ay" "$(( __fvx_ax + 40 ))" "$(( __fvx_ay + 9 ))" "$@"
}
# fv.msgbox.messageBoxRect AX AY BX BY MSG OPTIONS [-- PARAMS...] — FV
# MessageBoxRect over (AX, AY)-(BX, BY) in the owner's coordinates
fv.msgbox.messageBoxRect() {
    fv.msgbox._owner messageBoxRect || return
    if (( $# < 6 )); then fv.msgbox._bad messageBoxRect 'AX AY BX BY MSG OPTIONS [-- PARAMS...]: wrong argument count'; return; fi
    if (( $# > 6 )) && ! [ "$7" = -- ]; then fv.msgbox._bad messageBoxRect "PARAMS follow '--' (got: '$7')"; return; fi
    if ! fv.msgbox._int "$1" || ! fv.msgbox._int "$2" || ! fv.msgbox._int "$3" || ! fv.msgbox._int "$4"; then
        fv.msgbox._bad messageBoxRect "AX AY BX BY must be integers (got: '$1' '$2' '$3' '$4')"; return
    fi
    local __fvx_o __fvx_g
    fv.msgbox._opts messageBoxRect "$6" || return
    fv.msgbox._box "$@"
}
# fv.msgbox._box AX AY BX BY MSG OPTIONS [-- PARAMS...] (the caller's __fvx_o,
# __fvx_g checked) — FV MessageBoxRect + MessageBoxRectDlg: the dialog titled
# FV_MSGBOX_TITLES[OPTIONS & 3]; the text (3, 2, SizeX - 2, SizeY - 3); the
# buttons of OPTIONS ($100 shl I: Yes No OK Cancel), 10 x 2 each, 2 cells
# apart, centred on row SizeY - 3 ((SizeX - X) shr 1); SelectNext(False):
# the first button; ExecView by the owner; the dialog destroyed
fv.msgbox._box() {
    local __fvx_d __fvx_role __fvx_t __fvx_m=$5 __fvx_sx=$(( $3 - $1 )) __fvx_sy=$(( $4 - $2 )) __fvx_x __fvx_i __fvx_r
    local __fvx_k=$(( __fvx_o % 4 ))
    local __fvx_ti=${FV_MSGBOX_TITLES[__fvx_k]-}
    local -a __fvx_b=() __fvx_a=()
    fv.msgbox._name
    fv.views._newReserved "$FV_DESKTOP" "$__fvx_role" TDialog "$1" "$2" "$3" "$4" "${__fvx_ti:-${__FV_MB_TDEF[__fvx_k]}}" \
        || { fv.msgbox._bad messageBox "the dialog was refused (bounds $1 $2 $3 $4)"; return; }
    # (FV FormatStr: printf -v with PARAMS, never more of them than the
    # format's conversions take — printf would repeat the format for the
    # surplus —; a refused format: what printf made, without its message.
    # Shifts, not a "${@:N}" slice: no slice in this unit, README "Contract")
    if (( $# > 6 )); then
        local __fvg_pn
        fv.dialogs._ptCount "$__fvx_m"
        shift 7
        while (( $# && ${#__fvx_a[@]} < __fvg_pn )); do __fvx_a+=("$1"); shift; done
        printf -v __fvx_m -- "$__fvx_m" "${__fvx_a[@]}" 2>/dev/null || :
    fi
    fv.views._newReserved "$__fvx_d" text TStaticText 3 2 "$(( __fvx_sx - 2 ))" "$(( __fvx_sy - 3 ))" "$__fvx_m" || :
    fv.views.insert "$__fvx_d" "$RESULT" || :
    for (( __fvx_i = 0; __fvx_i < 4; __fvx_i++ )); do
        if (( __fvx_o & (256 << __fvx_i) )); then __fvx_b+=("$__fvx_i"); fi
    done
    __fvx_x=$(( (__fvx_sx - (12 * ${#__fvx_b[@]} - 2)) >> 1 ))
    for __fvx_i in "${__fvx_b[@]}"; do
        __fvx_t=${FV_MSGBOX_BUTTONS[__fvx_i]-}
        fv.views._newReserved "$__fvx_d" "btn$__fvx_i" TButton "$__fvx_x" "$(( __fvx_sy - 3 ))" "$(( __fvx_x + 10 ))" "$(( __fvx_sy - 1 ))" \
            "${__fvx_t:-${__FV_MB_BDEF[__fvx_i]}}" "${__FV_MB_CMD[__fvx_i]}" 0 || :
        fv.views.insert "$__fvx_d" "$RESULT" || :
        __fvx_x=$(( __fvx_x + 12 ))
    done
    fv.views.selectNext "$__fvx_d" 0 || :
    fv.views.execView "$__fvx_g" "$__fvx_d" || :
    __fvx_r=${RESULT:-cmCancel}
    if [[ -n ${__FV_VW_LIVE[$__fvx_d]-} ]]; then "$__fvx_d.delete"; fi
    RESULT=$__fvx_r
}

# ---- the input box (FV InputBox, InputBoxRect) --------------------------------------
# fv.msgbox.inputBox [-p] TITLE LABEL VARNAME LIMIT — FV InputBox: R := (0, 0,
# 60, 8) moved to the desktop's centre, then InputBoxRect
fv.msgbox.inputBox() {
    fv.msgbox._owner inputBox || return
    local __fvx_p=''
    if (( $# )) && [ "$1" = -p ]; then __fvx_p='*'; shift; fi
    if (( $# != 4 )); then fv.msgbox._bad inputBox '[-p] TITLE LABEL VARNAME LIMIT: wrong argument count'; return; fi
    fv.msgbox._var inputBox "$3" "$4" || return
    local -n __fvx_gd=${FV_DESKTOP}_data
    local __fvx_ax=$(( (${__fvx_gd[SizeX]:-0} - 60) / 2 )) __fvx_ay=$(( (${__fvx_gd[SizeY]:-0} - 8) / 2 ))
    fv.msgbox._ibox "$__fvx_ax" "$__fvx_ay" "$(( __fvx_ax + 60 ))" "$(( __fvx_ay + 8 ))" "$@"
}
# fv.msgbox.inputBoxRect [-p] AX AY BX BY TITLE LABEL VARNAME LIMIT — FV
# InputBoxRect over (AX, AY)-(BX, BY) in the desktop's coordinates
fv.msgbox.inputBoxRect() {
    fv.msgbox._owner inputBoxRect || return
    local __fvx_p=''
    if (( $# )) && [ "$1" = -p ]; then __fvx_p='*'; shift; fi
    if (( $# != 8 )); then fv.msgbox._bad inputBoxRect '[-p] AX AY BX BY TITLE LABEL VARNAME LIMIT: wrong argument count'; return; fi
    if ! fv.msgbox._int "$1" || ! fv.msgbox._int "$2" || ! fv.msgbox._int "$3" || ! fv.msgbox._int "$4"; then
        fv.msgbox._bad inputBoxRect "AX AY BX BY must be integers (got: '$1' '$2' '$3' '$4')"; return
    fi
    fv.msgbox._var inputBoxRect "$7" "$8" || return
    fv.msgbox._ibox "$@"
}
# fv.msgbox._ibox AX AY BX BY TITLE LABEL VARNAME LIMIT (the caller's
# __fvx_p) — FV InputBoxRect: the dialog titled TITLE; the input line (4 +
# CStrLen(LABEL), 2, SizeX - 3, 3) of LIMIT clusters; the label (2, 2, 3 +
# CStrLen(LABEL), 3) linked to it; OK (SizeX - 24, SizeY - 4) - (SizeX - 14,
# SizeY - 2), bfDefault, and Cancel 12 cells right; SelectNext(False): the
# input line; SetData(VARNAME's value); ExecView by the desktop; GetData
# into VARNAME unless cmCancel; the dialog destroyed
fv.msgbox._ibox() {
    local __fvx_d __fvx_role __fvx_il __fvx_w __fvx_sx=$(( $3 - $1 )) __fvx_sy=$(( $4 - $2 )) __fvx_r __fvx_t
    local -n __fvx_v=$7
    fv.video.strWidth "${6//'~'/}" || RESULT=${#6}
    __fvx_w=$RESULT
    fv.msgbox._name
    fv.views._newReserved "$FV_DESKTOP" "$__fvx_role" TDialog "$1" "$2" "$3" "$4" "$5" \
        || { fv.msgbox._bad inputBox "the dialog was refused (bounds $1 $2 $3 $4)"; return; }
    fv.views._newReserved "$__fvx_d" input TInputLine "$(( 4 + __fvx_w ))" 2 "$(( __fvx_sx - 3 ))" 3 "$(( 10#$8 ))" || :
    __fvx_il=$RESULT
    fv.views.insert "$__fvx_d" "$__fvx_il" || :
    if [[ -n $__fvx_p ]]; then printf -v "${__fvx_il}_data[PasswordChar]" '%s' "$__fvx_p"; fi
    fv.views._newReserved "$__fvx_d" label TLabel 2 2 "$(( 3 + __fvx_w ))" 3 "$6" "$__fvx_il" || :
    fv.views.insert "$__fvx_d" "$RESULT" || :
    __fvx_t=${FV_MSGBOX_BUTTONS[4]-}
    fv.views._newReserved "$__fvx_d" ok TButton "$(( __fvx_sx - 24 ))" "$(( __fvx_sy - 4 ))" "$(( __fvx_sx - 14 ))" "$(( __fvx_sy - 2 ))" \
        "${__fvx_t:-${__FV_MB_BDEF[4]}}" cmOK "$FV_BF_DEFAULT" || :
    fv.views.insert "$__fvx_d" "$RESULT" || :
    __fvx_t=${FV_MSGBOX_BUTTONS[5]-}
    fv.views._newReserved "$__fvx_d" cancel TButton "$(( __fvx_sx - 12 ))" "$(( __fvx_sy - 4 ))" "$(( __fvx_sx - 2 ))" "$(( __fvx_sy - 2 ))" \
        "${__fvx_t:-${__FV_MB_BDEF[5]}}" cmCancel "$FV_BF_NORMAL" || :
    fv.views.insert "$__fvx_d" "$RESULT" || :
    fv.views.selectNext "$__fvx_d" 0 || :
    fv.dialogs.setText "$__fvx_il" "${__fvx_v-}" || :
    fv.views.execView "$FV_DESKTOP" "$__fvx_d" || :
    __fvx_r=${RESULT:-cmCancel}
    if ! [ "$__fvx_r" = cmCancel ] && fv.dialogs.getText "$__fvx_il"; then __fvx_v=$RESULT; fi
    if [[ -n ${__FV_VW_LIVE[$__fvx_d]-} ]]; then "$__fvx_d.delete"; fi
    RESULT=$__fvx_r
}
