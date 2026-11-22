#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.dlg.sh}../../kbool.sh" || return
kk.unit fv.dlg || return $__kk_unit_rc

# fv.dlg — one-shot dialogs for the fv.* text UI (P4, design
# kcl/docs/dev/fv/P4_DESIGN.md; stage 4a-1: the parser, the boxes, the input
# boxes, the results). whiptail / dialog-compatible flags (D32) on Free
# Vision's classes; two faces, one parser (P4-2):
#
#   fv.dlg.main ARG...    the command's face (bin/fvdlg, stage 4b, calls it):
#                         the result on stderr (whiptail / dialog), stdout
#                         with --stdout, fd N with --output-fd N; stderr /
#                         stdout buffered while the UI runs when they are
#                         the terminal (P4-6); --help / --version; answers
#                         the exit status (it returns it: bin/fvdlg exits)
#   fv.dlg.run ARG...     the bash face: the same argv and rules, the answer
#                         in RESULT (+ FV_DLG_CMD, the FV command that ended
#                         the dialog), nothing printed unless --stdout /
#                         --stderr / --output-fd asks; the same status
#
# Status (FV_DLG_OK / FV_DLG_CANCEL / FV_DLG_ESC, readonly): 0 OK / Yes, 1
# Cancel / No (the buttons send cmNo, P4-4), 255 Esc / Ctrl+F4 / the close
# icon / the end of input / no terminal / bad arguments (one line on stderr).
# Ctrl+C / SIGTERM / SIGHUP are fv.video's (130 / 143 / 129, restored).
#
# Widgets of this stage: --msgbox --yesno --infobox (P4-10: drawn once, no
# loop, the main screen, FV_KBD_PROTO=off unless set, the cursor on the last
# row) --inputbox --passwordbox (INIT selected: the first key replaces it;
# D38: '*' per character, --fv-echo none shows nothing). The list widgets,
# --gauge and --textbox are parsed and refused "not supported yet" (4a-2,
# 4d). Parser rules (P4-7, design §4.5): options anywhere before `--`, the
# widget's fixed positionals literal, an optional positional unless it is
# exactly a known option, `--` ends the options, --opt=value or --opt value,
# one widget per call; `\n` in TEXT is a newline, dialog's \Z escapes are
# stripped with --colors (P4-9).
#
# Conventions (as the other fv units): locals `__fvl_*`, globals `__FV_DL_*`;
# fork-free on every path but P4-6's buffer (one `rm`, one `trap -p`, in a
# subshell fv.video._drop's one `trap -p`; only when a buffer is made); set
# -eu clean; names compared with `[ "$a" = "$b" ]` (nocasematch), character
# classes as lists (no ranges). Friend uses (the same framework): fv.views'
# __FV_VW_LIVE and _newReserved, fv.app's _firstPaint (the infobox's one
# paint without a loop), fv.video's _drop (P4-6 in a subshell), fv.mouse's
# disable (--fv-mouse off without fv.drivers' flush of the keys).
# API, flag table and the differences from whiptail / dialog: README.md.

kk.uses kklass_pascal fv.app fv.dialogs || return

# ---- constants (dialog's DIALOG_OK / _CANCEL / _ESC; readonly once per process) ----
if [[ -z ${FV_DLG_OK+x} || ${FV_DLG_OK@a} != *r* ]]; then
    FV_DLG_OK=0 FV_DLG_CANCEL=1 FV_DLG_ESC=255
    readonly FV_DLG_OK FV_DLG_CANCEL FV_DLG_ESC
fi

# ---- state ----------------------------------------------------------------------
# FV_DLG_CMD   output: the FV command that ended the last dialog ('' = none)
# Private:
#   OPT[flag]  the option table: "KIND [KEY [ARGS]]" — f KEY (a flag: O[KEY]=1),
#              v KEY (a value: O[KEY]=VALUE), o N (the result fd: --stdout 1,
#              --stderr 2; --output-fd: o v), w NAME FIXED OPTIONAL (a widget
#              of this stage), n NAME (a widget not supported yet), x (a flag
#              refused: outside the subset), m (the command only: --help,
#              --version)
#   BUF        P4-6's buffer while the UI runs: (FILE SAVED1 SAVED2 TRAP)
#   VERSION    what --version prints
declare -g FV_DLG_CMD=${FV_DLG_CMD-}
declare -g __FV_DL_VERSION=0.1
declare -ga __FV_DL_BUF
__FV_DL_BUF+=()
declare -gA __FV_DL_OPT=(
    [--msgbox]='w msgbox 3 0' [--yesno]='w yesno 3 0' [--infobox]='w infobox 3 0'
    [--inputbox]='w inputbox 3 1' [--passwordbox]='w passwordbox 3 1'
    [--menu]='n menu' [--checklist]='n checklist' [--radiolist]='n radiolist'
    [--gauge]='n gauge' [--textbox]='n textbox'
    [--title]='v title' [--backtitle]='v backtitle'
    [--ok-button]='v ok' [--ok-label]='v ok' [--cancel-button]='v cancel' [--cancel-label]='v cancel'
    [--yes-button]='v yes' [--yes-label]='v yes' [--no-button]='v no' [--no-label]='v no'
    [--default-item]='v defitem'
    [--defaultno]='f defaultno' [--nocancel]='f nocancel' [--no-cancel]='f nocancel'
    [--separate-output]='f sepout' [--single-quoted]='f single'
    [--notags]='f notags' [--no-tags]='f notags' [--noitem]='f noitem' [--no-items]='f noitem'
    [--clear]='f clear' [--colors]='f colors' [--keep-tite]='f keeptite' [--erase-on-exit]='f erase'
    [--scrolltext]='f scrolltext' [--fb]='f fb' [--fullbuttons]='f fb' [--topleft]='f topleft'
    [--no-collapse]='f nocollapse' [--cr-wrap]='f crwrap' [--trim]='f trim' [--insecure]='f insecure'
    [--ascii-lines]='f ascii' [--no-shadow]='f noshadow'
    [--stdout]='o 1' [--stderr]='o 2' [--output-fd]='o v'
    [--fv-palette]='v palette' [--fv-ascii]='f ascii' [--fv-mouse]='v mouse' [--fv-echo]='v echo'
    [--fv-screen]='v screen' [--fv-output]='v output'
    [--fv-headless]='f headless' [--fv-keys]='v keys' [--fv-size]='v size' [--fv-out]='v fvout'
    [--help]='m' [--version]='m'
    [--help-button]='x' [--extra-button]='x' [--and-widget]='x' [--item-help]='x' [--timeout]='x'
    [--calendar]='x' [--form]='x' [--fselect]='x' [--dselect]='x' [--editbox]='x' [--buildlist]='x'
    [--mixedform]='x' [--mixedgauge]='x' [--passwordform]='x' [--pause]='x' [--prgbox]='x'
    [--programbox]='x' [--progressbox]='x' [--rangebox]='x' [--tailbox]='x' [--tailboxbg]='x'
    [--timebox]='x' [--treeview]='x' [--inputmenu]='x'
)
# the values an fv extra takes
declare -gA __FV_DL_VAL=(
    [palette]='gray blue cyan' [mouse]='on off' [echo]='star none' [screen]='alt main'
    [output]='lines quoted single'
)

# ---- the application ----------------------------------------------------------------
# TDlgApp : TApplication — no status line (the desktop takes every row; D23
# gives no menu bar). A resize re-centres the dialog through TDialog's own
# CalcBounds (FPC 2025: the margins kept in proportion); the minimum-size
# check on a resize comes with 4a-2 (P4-8)
class TDlgApp : TApplication
    public
        nofields override proc InitStatusLine
end
TDlgApp.InitStatusLine() { return 0; }
build TDlgApp

# TDlgTitle : TView — the background title (--backtitle): one row, a blank
# and Text, in colour 1 (TView has no palette: the app palette's entry 1, the
# background's colour). A proc override (a func would print its answer
# inside $( )): one dispatch per draw
class TDlgTitle : TView
    public
        var Text
        override proc Draw
end
TDlgTitle.Draw() {
    local __fvl_s __fvl_n __fvl_r=${RESULT-}
    fv.video.strWidth "$Text" || RESULT=${#Text}
    __fvl_n=$(( SizeX - 1 - RESULT ))
    if (( __fvl_n < 0 )); then __fvl_n=0; fi
    printf -v __fvl_s ' %s%*s' "$Text" "$__fvl_n" ''
    fv.views.writeStr 0 0 "$__fvl_s" 1
    RESULT=$__fvl_r
}
build TDlgTitle

# ---- helpers ----------------------------------------------------------------------
# fv.dlg._say FACE MSG — one refusal line on stderr: "fvdlg: MSG" for the
# command, "fv.dlg.run: MSG" for the bash face
fv.dlg._say() {
    local __fvl_n=fvdlg
    if [ "$1" = run ]; then __fvl_n=fv.dlg.run; fi
    printf '%s: %s\n' "$__fvl_n" "$2" >&2
}
# fv.dlg._int V — rc 0 for an integer: an optional '-', 1-6 digits
fv.dlg._int() {
    local __fvl_v=${1#-}
    [[ -n $__fvl_v && $__fvl_v != *[!0123456789]* && ${#__fvl_v} -le 6 ]]
}
# fv.dlg._isTerm FD — rc 0 when FD is a terminal (P4-6's test; a seam the
# tests replace)
fv.dlg._isTerm() { [[ -t $1 ]]; }
# fv.dlg._cw TEXT — RESULT = TEXT's cells without its `~` marks (FV CStrLen)
fv.dlg._cw() {
    fv.video.strWidth "${1//'~'/}" || RESULT=${#1}
}

# fv.dlg._parse ARG... — the argv into the caller's record (design §4.5):
# __fvl_w (the widget), __fvl_p (its positionals), __fvl_o (the options by
# key: O[out] the result fd), __fvl_m (a command-only flag seen: --help /
# --version, parsing stops there); rc 1 with __fvl_err (one line) for a
# malformed call
fv.dlg._parse() {
    local IFS=$' \t\n' __fvl_a __fvl_k __fvl_v __fvl_hv __fvl_kind __fvl_x __fvl_y __fvl_z
    local __fvl_need=0 __fvl_opt=0 __fvl_dd=0
    while (( $# )); do
        __fvl_a=$1
        shift
        # the widget's fixed positionals: literal (TEXT may look like an
        # option); H and W checked as soon as the three are taken (the
        # refusal names the word that stood there)
        if (( __fvl_need > 0 )); then
            __fvl_p+=("$__fvl_a")
            __fvl_need=$(( __fvl_need - 1 ))
            if (( __fvl_need == 0 )); then
                # the sizes: integers (0 = fit the text, -1 = the whole screen)
                if ! fv.dlg._int "${__fvl_p[1]}"; then __fvl_err="HEIGHT must be an integer (got '${__fvl_p[1]}')"; return 1; fi
                if ! fv.dlg._int "${__fvl_p[2]}"; then __fvl_err="WIDTH must be an integer (got '${__fvl_p[2]}')"; return 1; fi
            fi
            continue
        fi
        if (( __fvl_dd )); then
            if (( __fvl_opt > 0 )); then __fvl_p+=("$__fvl_a"); __fvl_opt=$(( __fvl_opt - 1 )); continue; fi
            __fvl_err="unexpected argument '$__fvl_a'"
            return 1
        fi
        if [ "$__fvl_a" = -- ]; then __fvl_dd=1; continue; fi
        __fvl_k=$__fvl_a __fvl_v='' __fvl_hv=0
        if [[ $__fvl_a == --?*=* ]]; then __fvl_k=${__fvl_a%%=*} __fvl_v=${__fvl_a#*=} __fvl_hv=1; fi
        __fvl_kind=${__FV_DL_OPT[$__fvl_k]-}
        if [[ -z $__fvl_kind ]]; then
            if (( __fvl_opt > 0 )); then __fvl_p+=("$__fvl_a"); __fvl_opt=$(( __fvl_opt - 1 )); continue; fi
            if [[ $__fvl_a == -?* ]]; then __fvl_err="unknown option '$__fvl_a'"
            else __fvl_err="unexpected argument '$__fvl_a'"; fi
            return 1
        fi
        read -r __fvl_x __fvl_y __fvl_z <<< "$__fvl_kind"
        if (( __fvl_hv )) && { [ "$__fvl_x" = f ] || [ "$__fvl_x" = w ] || [ "$__fvl_x" = n ] || [ "$__fvl_x" = m ] || [ "$__fvl_kind" = 'o 1' ] || [ "$__fvl_kind" = 'o 2' ]; }; then
            __fvl_err="option '$__fvl_k' takes no value"
            return 1
        fi
        case $__fvl_x in
            w)
                if [[ -n $__fvl_w ]]; then __fvl_err="one widget per call ('$__fvl_k' after '--$__fvl_w'); --and-widget is not supported"; return 1; fi
                __fvl_w=$__fvl_y __fvl_need=${__fvl_z% *} __fvl_opt=${__fvl_z#* } ;;
            n)
                if [[ -n $__fvl_w ]]; then __fvl_err="one widget per call ('$__fvl_k' after '--$__fvl_w'); --and-widget is not supported"; return 1; fi
                __fvl_err="'$__fvl_k' is not supported yet"
                return 1 ;;
            x)
                __fvl_err="option '$__fvl_k' is not supported (outside fvdlg's whiptail / dialog subset)"
                return 1 ;;
            m)
                __fvl_m=$__fvl_k
                return 0 ;;
            f)
                __fvl_o[$__fvl_y]=1 ;;
            *)  # v, o
                if [ "$__fvl_x" = o ] && ! [ "$__fvl_y" = v ]; then __fvl_o[out]=$__fvl_y; continue; fi
                if (( ! __fvl_hv )); then
                    if (( ! $# )); then __fvl_err="option '$__fvl_k' needs a value"; return 1; fi
                    __fvl_v=$1
                    shift
                fi
                if [ "$__fvl_x" = o ]; then
                    if [[ -z $__fvl_v || $__fvl_v == *[!0123456789]* || ${#__fvl_v} -gt 4 ]]; then
                        __fvl_err="--output-fd needs a file descriptor number (got '$__fvl_v')"
                        return 1
                    fi
                    __fvl_o[out]=$(( 10#$__fvl_v ))
                else
                    __fvl_o[$__fvl_y]=$__fvl_v
                fi ;;
        esac
    done
    if (( __fvl_need > 0 )); then
        __fvl_err="'--$__fvl_w' needs TEXT HEIGHT WIDTH (got ${#__fvl_p[@]} of 3)"
        return 1
    fi
    if [[ -z $__fvl_w ]]; then
        __fvl_err='no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox)'
        return 1
    fi
    # the fv extras' values: one of the allowed words, exactly (`[ = ]`, not
    # a pattern: no substring, nocasematch has no say)
    for __fvl_k in palette mouse echo screen output; do
        [[ -n ${__fvl_o[$__fvl_k]+x} ]] || continue
        __fvl_v=${__fvl_o[$__fvl_k]} __fvl_x=${__FV_DL_VAL[$__fvl_k]} __fvl_z=0
        while [[ -n $__fvl_x ]]; do
            __fvl_y=${__fvl_x%% *}
            if [ "$__fvl_v" = "$__fvl_y" ]; then __fvl_z=1; break; fi
            if [ "$__fvl_y" = "$__fvl_x" ]; then break; fi
            __fvl_x=${__fvl_x#* }
        done
        if (( ! __fvl_z )); then
            __fvl_x=${__FV_DL_VAL[$__fvl_k]}
            __fvl_err="--fv-$__fvl_k must be ${__fvl_x// / | } (got '$__fvl_v')"
            return 1
        fi
    done
    # --fv-size: 1..1000 cells per side
    if [[ -n ${__fvl_o[size]+x} ]]; then
        __fvl_v=${__fvl_o[size]} __fvl_x=${__fvl_o[size]%%x*} __fvl_y=${__fvl_o[size]#*x}
        if [[ $__fvl_v != *x* || -z $__fvl_x || -z $__fvl_y || $__fvl_x == *[!0123456789]* || $__fvl_y == *[!0123456789]* \
              || ${#__fvl_x} -gt 6 || ${#__fvl_y} -gt 6 ]] || (( 10#$__fvl_x < 1 || 10#$__fvl_y < 1 || 10#$__fvl_x > 1000 || 10#$__fvl_y > 1000 )); then
            __fvl_err="--fv-size must be WxH, 1..1000 each (got '$__fvl_v')"
            return 1
        fi
    fi
    if [[ -z ${__fvl_o[headless]-} ]] && [[ -n ${__fvl_o[keys]+x}${__fvl_o[size]+x}${__fvl_o[fvout]+x} ]]; then
        __fvl_err='--fv-keys, --fv-size and --fv-out are for --fv-headless'
        return 1
    fi
    return 0
}

# fv.dlg._text TEXT — RESULT = TEXT as shown: `\n` (two characters) a newline,
# dialog's \Z escapes stripped with --colors (the caller's __fvl_o)
fv.dlg._text() {
    local __fvl_t=$1 __fvl_nc=0
    # (exact matching: nocasematch would make `\N` a newline too)
    if shopt -q nocasematch; then __fvl_nc=1; shopt -u nocasematch; fi
    __fvl_t=${__fvl_t//'\n'/$'\n'}
    if [[ -n ${__fvl_o[colors]-} ]]; then __fvl_t=${__fvl_t//\\Z[01234567bBrRuUn]/}; fi
    if (( __fvl_nc )); then shopt -s nocasematch; fi
    RESULT=$__fvl_t
}

# fv.dlg._fit TEXT MAXW — the caller's __fvl_tw (the text area's width, at
# most MAXW) and __fvl_th (its rows) for TEXT: the widest line + 1 (a line
# that fills TStaticText's width breaks), else MAXW and the rows the words
# take there (TStaticText breaks at the last blank, which starts the next
# line; a longer word is cut)
fv.dlg._fit() {
    local __fvl_l __fvl_w=0 __fvl_n=0 __fvl_x __fvl_c __fvl_ww
    local -a __fvl_ls=() __fvl_lw=() __fvl_wd=()
    local IFS=' '
    # (every line, empty ones too: "a\n" is two rows)
    mapfile -t __fvl_ls <<< "$1"
    for __fvl_l in "${__fvl_ls[@]}"; do
        fv.video.strWidth "$__fvl_l" || RESULT=${#__fvl_l}
        __fvl_lw+=("$RESULT")
        if (( RESULT > __fvl_w )); then __fvl_w=$RESULT; fi
    done
    if (( __fvl_w + 1 <= $2 )); then
        __fvl_tw=$(( __fvl_w + 1 )) __fvl_th=${#__fvl_ls[@]}
        return 0
    fi
    __fvl_tw=$2 __fvl_th=0
    for (( __fvl_n = 0; __fvl_n < ${#__fvl_ls[@]}; __fvl_n++ )); do
        if (( __fvl_lw[__fvl_n] < __fvl_tw )); then __fvl_th=$(( __fvl_th + 1 )); continue; fi
        read -r -a __fvl_wd <<< "${__fvl_ls[__fvl_n]}"
        __fvl_c=0 __fvl_th=$(( __fvl_th + 1 ))
        for __fvl_l in "${__fvl_wd[@]}"; do
            fv.video.strWidth "$__fvl_l" || RESULT=${#__fvl_l}
            __fvl_ww=$RESULT
            if (( __fvl_c > 0 )); then __fvl_ww=$(( __fvl_ww + 1 )); fi
            if (( __fvl_c + __fvl_ww >= __fvl_tw && __fvl_c > 0 )); then
                __fvl_th=$(( __fvl_th + 1 )) __fvl_c=0
            fi
            __fvl_c=$(( __fvl_c + __fvl_ww ))
            while (( __fvl_c >= __fvl_tw )); do __fvl_th=$(( __fvl_th + 1 )) __fvl_c=$(( __fvl_c - __fvl_tw + 1 )); done
        done
    done
    (( __fvl_th > 0 )) || __fvl_th=1
}

# ---- the screen (the application, P4-6's buffer, the terminal) -----------------------

# fv.dlg._bufOn — P4-6: stderr (and stdout) that is the terminal goes to a
# private file while the UI runs (umask 077, noclobber, a name that cannot be
# predicted); the EXIT trap replays it if the process dies meanwhile, then
# runs the caller's EXIT handler. A file / pipe / capture is left alone; no
# buffer when the file cannot be made. The caller's EXIT trap is the one
# active in this process: in a subshell the parent's texts that `trap -p`
# still shows are dropped first (fv.video's rule); the trap is set before
# the fds move (no signal window)
fv.dlg._bufOn() {
    local - IFS= __fvl_t1=0 __fvl_t2=0 __fvl_f __fvl_p='' __fvl_u='' __fvl_wf='' __fvl_b1='' __fvl_b2='' __fvl_tr
    __FV_DL_BUF=()
    if fv.dlg._isTerm 2; then __fvl_t2=1; fi
    if fv.dlg._isTerm 1; then __fvl_t1=1; fi
    (( __fvl_t1 || __fvl_t2 )) || return 0
    __fvl_f=${TMPDIR:-/tmp}/fvdlg.$BASHPID.$SRANDOM.$SRANDOM
    if [[ -e $__fvl_f || -L $__fvl_f || -e $__fvl_f.u || -L $__fvl_f.u ]]; then return 0; fi
    set -C
    { exec {__fvl_p}>"$__fvl_f.u"; } 2>/dev/null || return 0
    umask >&$__fvl_p
    { exec {__fvl_p}>&-; } 2>/dev/null
    { IFS= read -r __fvl_u <"$__fvl_f.u"; } 2>/dev/null || __fvl_u=''
    if [[ -n $__fvl_u && $__fvl_u != *[!01234567]* ]]; then
        umask 077
        { exec {__fvl_wf}>"$__fvl_f"; } 2>/dev/null || __fvl_wf=''
        umask "$__fvl_u"
    fi
    if [[ -z $__fvl_wf ]]; then
        command rm -f -- "$__fvl_f.u" 2>/dev/null || :   # fork: P4-6
        return 0
    fi
    if [[ $BASHPID != "$$" ]]; then fv.video._drop; fi   # (fork: trap -p)
    __fvl_tr=$(trap -p EXIT) || __fvl_tr=''   # fork: P4-6
    __FV_DL_BUF=("$__fvl_f" '' '' "$__fvl_tr")
    trap 'fv.dlg._bufOff exit' EXIT
    # (each saved fd recorded before its fd moves: a death in between puts
    # back what has moved)
    if (( __fvl_t2 )); then exec {__fvl_b2}>&2; __FV_DL_BUF[2]=$__fvl_b2; exec 2>&$__fvl_wf; fi
    if (( __fvl_t1 )); then exec {__fvl_b1}>&1; __FV_DL_BUF[1]=$__fvl_b1; exec 1>&$__fvl_wf; fi
    exec {__fvl_wf}>&-
}
# fv.dlg._bufOff [exit] — the buffer's end: the fds back, what it holds
# replayed to the terminal (stderr's when it was buffered, else stdout's),
# the file removed (one rm), the caller's EXIT trap back. `exit` (the EXIT
# trap: the process is going away): the caller's EXIT handler then runs,
# once, with the status kept (as fv.video's _onexit runs it). Nothing
# without a buffer
fv.dlg._bufOff() {
    local __fvl_rc=$? __fvl_tr __fvl_h
    (( ${#__FV_DL_BUF[@]} )) || return 0
    __fvl_tr=${__FV_DL_BUF[3]}
    fv.dlg._bufEnd
    if ! [ "${1-}" = exit ]; then
        if [[ -n $__fvl_tr ]]; then eval "$__fvl_tr"; else trap - EXIT; fi
        return 0
    fi
    trap - EXIT
    [[ -n $__fvl_tr ]] || return 0
    # (the handler text out of `trap -- 'TEXT' EXIT`, as fv.video._trap does)
    __fvl_h=${__fvl_tr% *} __fvl_h=${__fvl_h#trap -- }
    eval "__fvl_h=$__fvl_h"
    [[ -n $__fvl_h ]] || return 0
    __fvl_h+=$'\n:'
    set --
    if (( ! __fvl_rc )); then eval "$__fvl_h"; else fv.dlg._rc "$__fvl_rc" || eval "$__fvl_h"; fi
}
# fv.dlg._rc N — rc N (the status a handler sees in $?)
fv.dlg._rc() { return "$1"; }
# fv.dlg._bufEnd — _bufOff's fds, replay and file (bare fd redirects: IFS '')
fv.dlg._bufEnd() {
    local IFS= __fvl_f=${__FV_DL_BUF[0]} __fvl_b1=${__FV_DL_BUF[1]} __fvl_b2=${__FV_DL_BUF[2]} __fvl_r='' __fvl_s __fvl_to
    __FV_DL_BUF=()
    if [[ -n $__fvl_b2 ]]; then exec 2>&$__fvl_b2; exec {__fvl_b2}>&-; fi
    if [[ -n $__fvl_b1 ]]; then exec 1>&$__fvl_b1; exec {__fvl_b1}>&-; fi
    __fvl_to=1
    if [[ -n $__fvl_b2 ]]; then __fvl_to=2; fi
    if { exec {__fvl_r}<"$__fvl_f"; } 2>/dev/null; then
        while IFS= read -r -N 65536 -u "$__fvl_r" __fvl_s || [[ -n $__fvl_s ]]; do
            printf '%s' "$__fvl_s" >&$__fvl_to 2>/dev/null || :
            __fvl_s=''
        done
        exec {__fvl_r}<&-
    fi
    command rm -f -- "$__fvl_f" "$__fvl_f.u" 2>/dev/null || :   # fork: P4-6
    return 0
}

# ---- the widgets ------------------------------------------------------------------

# fv.dlg._btn D ROLE X Y TITLE CMD FLAGS — a button of the dialog D, its
# width the title's cells + 4, at least FV's 10, 2 rows (the shadow)
fv.dlg._btn() {
    local __fvl_bw
    fv.dlg._cw "$5"
    __fvl_bw=$(( RESULT + 4 ))
    if (( __fvl_bw < 10 )); then __fvl_bw=10; fi
    fv.views._newReserved "$1" "$2" TButton "$3" "$4" "$(( $3 + __fvl_bw ))" "$(( $4 + 2 ))" "$5" "$6" "$7" || return
    fv.views.insert "$1" "$RESULT"
}
# fv.dlg._bw TITLE — RESULT = a button's width (as _btn makes it)
fv.dlg._bw() {
    fv.dlg._cw "$1"
    RESULT=$(( RESULT + 4 ))
    if (( RESULT < 10 )); then RESULT=10; fi
}
# fv.dlg._clip LABEL N — RESULT = LABEL cut to N cells (the `~` marks cost
# nothing; a hot-key span the cut leaves open is closed with a `~`)
fv.dlg._clip() {
    local __fvl_s=$1 __fvl_q='' __fvl_c __fvl_i __fvl_n=0 __fvl_m=0
    for (( __fvl_i = 0; __fvl_i < ${#__fvl_s}; __fvl_i++ )); do
        __fvl_c=${__fvl_s:__fvl_i:1}
        if [ "$__fvl_c" = '~' ]; then __fvl_q+=$__fvl_c __fvl_m=$(( 1 - __fvl_m )); continue; fi
        fv.video.strWidth "$__fvl_c" || RESULT=1
        if (( __fvl_n + RESULT > $2 )); then break; fi
        __fvl_q+=$__fvl_c __fvl_n=$(( __fvl_n + RESULT ))
    done
    # (an open span: closed; one the cut left empty: its mark dropped)
    if (( __fvl_m )) && [[ $__fvl_q == *'~' ]]; then __fvl_q=${__fvl_q%'~'}
    elif (( __fvl_m )); then __fvl_q+='~'; fi
    RESULT=$__fvl_q
}
# fv.dlg._fitLabels — the caller's __fvl_l1 / __fvl_l2 clipped so that the
# buttons (each the label's cells + 4, at least FV's 10; 2 apart; 2 from
# each side) fit the screen's width __fvl_sw: a button that fits in half
# the room keeps its label, the other gets the rest (both long: half each).
# A screen too narrow even for buttons of 10 (geometry: refused later)
# clips the long labels to 6 cells, so the refusal names the geometric need
fv.dlg._fitLabels() {
    local __fvl_a __fvl_b1 __fvl_b2 __fvl_m1=0 __fvl_m2=0 __fvl_h
    fv.dlg._bw "$__fvl_l1"; __fvl_b1=$RESULT
    if [[ -n $__fvl_l2 ]]; then
        fv.dlg._bw "$__fvl_l2"; __fvl_b2=$RESULT
        __fvl_a=$(( __fvl_sw - 6 ))
        (( __fvl_b1 + __fvl_b2 > __fvl_a )) || return 0
        __fvl_h=$(( __fvl_a / 2 ))
        if (( __fvl_h < 10 )); then __fvl_m1=6 __fvl_m2=6
        elif (( __fvl_b2 <= __fvl_h )); then __fvl_m1=$(( __fvl_a - __fvl_b2 - 4 ))
        elif (( __fvl_b1 <= __fvl_h )); then __fvl_m2=$(( __fvl_a - __fvl_b1 - 4 ))
        else __fvl_m1=$(( __fvl_a - __fvl_h - 4 )) __fvl_m2=$(( __fvl_h - 4 )); fi
        if (( __fvl_m2 && __fvl_b2 - 4 > __fvl_m2 )); then fv.dlg._clip "$__fvl_l2" "$__fvl_m2"; __fvl_l2=$RESULT; fi
    else
        __fvl_m1=$(( __fvl_sw - 8 ))
        if (( __fvl_m1 < 6 )); then __fvl_m1=6; fi
    fi
    if (( __fvl_m1 && __fvl_b1 - 4 > __fvl_m1 )); then fv.dlg._clip "$__fvl_l1" "$__fvl_m1"; __fvl_l1=$RESULT; fi
    return 0
}

# fv.dlg._build — the dialog of the caller's call record on the live
# application (the caller's __fvl_*): the size (P4-8), the frame and title,
# the text, the input line, the buttons; __fvl_d = the dialog, __fvl_il =
# the input line. rc 1 with __fvl_err: the screen is too small
fv.dlg._build() {
    local __fvl_sw __fvl_sh __fvl_top=0 __fvl_ex __fvl_minw __fvl_minh __fvl_bw __fvl_bh __fvl_tw __fvl_th __fvl_x __fvl_y
    local __fvl_hh=${__fvl_p[1]} __fvl_ww=${__fvl_p[2]} __fvl_l1 __fvl_l2 __fvl_c1 __fvl_c2 __fvl_w1 __fvl_w2=0 __fvl_df __fvl_pw
    local -n __fvl_ad=${FV_APP}_data
    __fvl_sw=${__fvl_ad[SizeX]:-80} __fvl_sh=${__fvl_ad[SizeY]:-24}
    if [[ $__fvl_hh == -* ]]; then __fvl_hh=-1; else __fvl_hh=$(( 10#$__fvl_hh )); fi
    if [[ $__fvl_ww == -* ]]; then __fvl_ww=-1; else __fvl_ww=$(( 10#$__fvl_ww )); fi
    if [[ -n ${__fvl_o[backtitle]-} ]]; then __fvl_top=1; fi
    __fvl_sh=$(( __fvl_sh - __fvl_top ))
    # the buttons: labels, commands (Cancel / No send cmNo, P4-4)
    # rows around the text: frame + blank + buttons (2) + frame; the input
    # line adds itself and a blank; the infobox only its frame
    __fvl_l1='' __fvl_l2='' __fvl_ex=2
    if [ "$__fvl_w" = msgbox ]; then
        __fvl_l1=${__fvl_o[ok]-O~K~} __fvl_c1=cmOK __fvl_ex=5
    elif [ "$__fvl_w" = yesno ]; then
        __fvl_l1=${__fvl_o[yes]-~Y~es} __fvl_c1=cmYes __fvl_l2=${__fvl_o[no]-~N~o} __fvl_c2=cmNo __fvl_ex=5
    elif [ "$__fvl_w" = inputbox ] || [ "$__fvl_w" = passwordbox ]; then
        __fvl_l1=${__fvl_o[ok]-O~K~} __fvl_c1=cmOK __fvl_l2=${__fvl_o[cancel]-Cancel} __fvl_c2=cmNo __fvl_ex=7
        if [[ -n ${__fvl_o[nocancel]-} ]]; then __fvl_l2=''; fi
    fi
    __fvl_minw=16 __fvl_pw=0
    if [[ -n $__fvl_l1 ]]; then
        # (labels wider than the screen allows are clipped: text never
        # makes the minimum exceed the screen)
        fv.dlg._fitLabels
        fv.dlg._bw "$__fvl_l1"; __fvl_w1=$RESULT
        if [[ -n $__fvl_l2 ]]; then fv.dlg._bw "$__fvl_l2"; __fvl_w2=$RESULT; fi
        __fvl_x=$(( __fvl_w1 + 4 ))
        if (( __fvl_w2 )); then __fvl_x=$(( __fvl_x + __fvl_w2 + 2 )); fi
        if (( __fvl_x > __fvl_minw )); then __fvl_minw=$__fvl_x; fi
    fi
    # the title: the preferred (auto) width only, at most the screen; the
    # frame cuts a longer one
    if [[ -n ${__fvl_o[title]-} ]]; then
        fv.dlg._cw "${__fvl_o[title]}"
        __fvl_pw=$(( RESULT + 12 > __fvl_sw ? __fvl_sw : RESULT + 12 ))
    fi
    # the minimum (P4-8, the basic rule; 4a-2 makes it exact): the buttons
    # across, one text row, the input line, the buttons and the frame down;
    # a screen below it is refused, a smaller H / W grown to it
    __fvl_minh=$__fvl_ex
    if [ "$__fvl_w" = infobox ]; then __fvl_minh=3; fi
    if (( __fvl_minw > __fvl_sw || __fvl_minh > __fvl_sh )); then
        __fvl_err="terminal too small (need ${__fvl_minw}x$(( __fvl_minh + __fvl_top )), have ${__fvl_ad[SizeX]:-0}x${__fvl_ad[SizeY]:-0})"
        return 1
    fi
    # the width: -1 the screen, a number clamped, 0 the text's fit (at most
    # 2/3 of the screen for the text, at least the title and the buttons)
    if (( __fvl_ww < 0 )); then __fvl_bw=$__fvl_sw
    elif (( __fvl_ww > 0 )); then __fvl_bw=$(( __fvl_ww > __fvl_sw ? __fvl_sw : __fvl_ww ))
    else
        __fvl_x=$(( __fvl_sw * 2 / 3 ))
        if (( __fvl_x < 10 )); then __fvl_x=10; fi
        fv.dlg._fit "$__fvl_t" "$__fvl_x"
        __fvl_bw=$(( __fvl_tw + 4 ))
        if (( __fvl_bw < __fvl_pw )); then __fvl_bw=$__fvl_pw; fi
        if (( __fvl_bw > __fvl_sw )); then __fvl_bw=$__fvl_sw; fi
    fi
    if (( __fvl_bw < __fvl_minw )); then __fvl_bw=$__fvl_minw; fi
    fv.dlg._fit "$__fvl_t" "$(( __fvl_bw - 4 > 1 ? __fvl_bw - 4 : 1 ))"
    if (( __fvl_hh < 0 )); then __fvl_bh=$__fvl_sh
    elif (( __fvl_hh > 0 )); then __fvl_bh=$(( __fvl_hh > __fvl_sh ? __fvl_sh : __fvl_hh ))
    else __fvl_bh=$(( __fvl_th + __fvl_ex )); if (( __fvl_bh > __fvl_sh )); then __fvl_bh=$__fvl_sh; fi
    fi
    if (( __fvl_bh < __fvl_minh )); then __fvl_bh=$__fvl_minh; fi
    __fvl_th=$(( __fvl_bh - __fvl_ex + 1 ))
    if [ "$__fvl_w" = infobox ]; then __fvl_th=$(( __fvl_bh - 2 )); fi
    if [[ -n ${__fvl_o[topleft]-} ]]; then __fvl_x=0 __fvl_y=$__fvl_top
    else __fvl_x=$(( (__fvl_sw - __fvl_bw) / 2 )) __fvl_y=$(( __fvl_top + (__fvl_sh - __fvl_bh) / 2 )); fi
    if [[ -n ${__fvl_o[backtitle]-} ]]; then
        fv.views._newReserved "$FV_DESKTOP" backtitle TDlgTitle 0 0 "$__fvl_sw" 1 || :
        printf -v "${RESULT}_data[Text]" '%s' "${__fvl_o[backtitle]}"
        fv.views.insert "$FV_DESKTOP" "$RESULT" || :
    fi
    fv.views._newReserved "$FV_DESKTOP" dlg TDialog "$__fvl_x" "$__fvl_y" "$(( __fvl_x + __fvl_bw ))" "$(( __fvl_y + __fvl_bh ))" "${__fvl_o[title]-}" || {
        __fvl_err="the dialog was refused (bounds $__fvl_x $__fvl_y $(( __fvl_x + __fvl_bw )) $(( __fvl_y + __fvl_bh )))"
        return 1
    }
    __fvl_d=$RESULT
    local -n __fvl_dd=${__fvl_d}_data
    # (NO_COLOR: always the gray palette, the entries _nocolor mapped)
    if [[ -z ${NO_COLOR-} ]]; then
        case ${__fvl_o[palette]-gray} in
            blue) __fvl_dd[Palette]=$FV_DP_BLUEDIALOG ;;
            cyan) __fvl_dd[Palette]=$FV_DP_CYANDIALOG ;;
        esac
    fi
    if [[ -n ${__fvl_o[noshadow]-} ]]; then __fvl_dd[State]=$(( ${__fvl_dd[State]:-0} & ~FV_SF_SHADOW )); fi
    fv.views._newReserved "$__fvl_d" text TStaticText 2 1 "$(( __fvl_bw - 2 ))" "$(( 1 + __fvl_th ))" "$__fvl_t" || :
    fv.views.insert "$__fvl_d" "$RESULT" || :
    if [ "$__fvl_w" = inputbox ] || [ "$__fvl_w" = passwordbox ]; then
        fv.views._newReserved "$__fvl_d" input TInputLine 2 "$(( __fvl_bh - 5 ))" "$(( __fvl_bw - 2 ))" "$(( __fvl_bh - 4 ))" 1024 || :
        __fvl_il=$RESULT
        fv.views.insert "$__fvl_d" "$__fvl_il" || :
        if [ "$__fvl_w" = passwordbox ]; then
            if [ "${__fvl_o[echo]-star}" = none ]; then
                # D38 --fv-echo none: blanks in the field and no cursor
                printf -v "${__fvl_il}_data[PasswordChar]" '%s' ' '
                fv.views.hideCursor "$__fvl_il" || :
            else
                printf -v "${__fvl_il}_data[PasswordChar]" '%s' '*'
            fi
        fi
    fi
    if [[ -n $__fvl_l1 ]]; then
        __fvl_x=$(( (__fvl_bw - __fvl_w1 - (__fvl_w2 ? __fvl_w2 + 2 : 0)) / 2 ))
        __fvl_df=1
        if [ "$__fvl_w" = yesno ] && [[ -n ${__fvl_o[defaultno]-} ]]; then __fvl_df=2; fi
        fv.dlg._btn "$__fvl_d" b1 "$__fvl_x" "$(( __fvl_bh - 3 ))" "$__fvl_l1" "$__fvl_c1" "$(( __fvl_df == 1 ? FV_BF_DEFAULT : FV_BF_NORMAL ))" || :
        __fvl_b1=$RESULT
        if [[ -n $__fvl_l2 ]]; then
            fv.dlg._btn "$__fvl_d" b2 "$(( __fvl_x + __fvl_w1 + 2 ))" "$(( __fvl_bh - 3 ))" "$__fvl_l2" "$__fvl_c2" "$(( __fvl_df == 2 ? FV_BF_DEFAULT : FV_BF_NORMAL ))" || :
            __fvl_b2=$RESULT
        fi
    fi
    # the focus: the input line (INIT selected: the first key replaces it),
    # else the default button
    if [[ -n $__fvl_il ]]; then
        fv.views.select "$__fvl_il" || :
        fv.dialogs.setText "$__fvl_il" "${__fvl_p[3]-}" || :
    elif [[ -n $__fvl_l2 ]] && (( __fvl_df == 2 )); then fv.views.select "$__fvl_b2" || :
    elif [[ -n $__fvl_l1 ]]; then fv.views.select "$__fvl_b1" || :
    fi
    return 0
}

# fv.dlg._nocolor — NO_COLOR (no-color.org): the app palette's entries a
# dialog uses mapped to light grey / white / black (FV's apBlackWhite idea:
# the focused button, the input field and the selection in reverse), before
# the first paint; one fv.app.setAppPalettes call (one palette scan, one
# reset). A --fv-palette blue / cyan is not applied under NO_COLOR (_build)
fv.dlg._nocolor() {
    # (FV_APP '' for the call: setAppPalettes then skips its redraw of the
    # application, which has not been painted yet; the first paint comes
    # after with every palette resolved afresh)
    local FV_APP=''
    # entry FG BG BOLD (the app palette; the gray dialog maps 1..31 to 32..62)
    fv.app.setAppPalettes '1 7 0 0' '32 7 0 0' '33 15 0 1' '34 15 0 1' '35 7 0 0' '36 7 0 0' '37 7 0 0' \
        '38 7 0 0' '39 15 0 1' '40 15 0 1' '41 0 7 0' '42 0 7 0' '43 15 0 1' '44 0 7 0' '45 15 7 1' \
        '46 7 0 0' '47 7 0 0' '48 15 0 1' '49 15 0 1' '50 0 7 0' '51 15 0 1' '52 15 7 1' '53 0 7 0' \
        '54 0 7 0' '55 7 0 0' '56 7 0 0' '57 7 0 0' '58 0 7 0' '59 15 0 1' '60 7 0 0' '61 7 0 0' '62 7 0 0' || :
}

# ---- the call ---------------------------------------------------------------------

# fv.dlg._call FACE ARG... — both faces: parse, the application, the
# dialog, the result; RESULT = the answer, FV_DLG_CMD the command; the
# status (0 / 1 / 255). FACE main: the result printed to O[out] (default 2),
# P4-6's buffer, --help / --version; run: printed only to an asked fd
fv.dlg._call() {
    local IFS=$' \t\n' __fvl_face=$1 __fvl_w='' __fvl_err='' __fvl_m='' __fvl_t __fvl_d='' __fvl_il='' __fvl_b1='' __fvl_b2=''
    local __fvl_app='' __fvl_cmd=cmCancel __fvl_rc=255 __fvl_res='' __fvl_vid=0 __fvl_kfd='' __fvl_ofd='' __fvl_fd __fvl_ok=1 __fvl_hl=0
    local -a __fvl_p=()
    local -A __fvl_o=()
    shift
    RESULT='' FV_DLG_CMD=''
    if ! fv.dlg._parse "$@"; then fv.dlg._say "$__fvl_face" "$__fvl_err"; return 255; fi
    if [[ -n $__fvl_m ]]; then
        if [ "$__fvl_face" = run ]; then fv.dlg._say run "'$__fvl_m' is for the command (fvdlg)"; return 255; fi
        if [ "$__fvl_m" = --version ]; then printf 'fvdlg %s (kbool fv.dlg)\n' "$__FV_DL_VERSION"; else fv.dlg._usage; fi
        return 0
    fi
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then
        fv.dlg._say "$__fvl_face" 'an fv application is already running in this shell (not supported yet)'
        return 255
    fi
    fv.dlg._text "${__fvl_p[0]}"
    __fvl_t=$RESULT RESULT=''
    # the terminal's settings for this call only (the caller's come back at
    # the return): headless (the caller's FV_APP_HEADLESS=1 with its
    # FV_KEY_FD / FV_VIDEO_OUT_FD / FV_SCREEN_W / _H is honoured, fv.app's
    # convention; --fv-headless sets its own), ASCII, the infobox's keyboard
    # protocol
    local FV_APP_HEADLESS=${FV_APP_HEADLESS-} FV_SCREEN_W=$FV_SCREEN_W FV_SCREEN_H=$FV_SCREEN_H FV_VIDEO_OUT_FD=$FV_VIDEO_OUT_FD
    local FV_KEY_FD=$FV_KEY_FD FV_ASCII=${FV_ASCII-} FV_VIDEO_ASCII=$FV_VIDEO_ASCII FV_KBD_PROTO=${FV_KBD_PROTO-}
    if [[ -n ${__fvl_o[ascii]-} ]]; then FV_ASCII=1; fi
    if [ "$__fvl_w" = infobox ] && [[ -z $FV_KBD_PROTO ]]; then FV_KBD_PROTO=off; fi
    if [[ -n ${__fvl_o[headless]-} ]]; then
        if ! { exec {__fvl_kfd}<"${__fvl_o[keys]-/dev/null}"; } 2>/dev/null; then
            fv.dlg._say "$__fvl_face" "cannot read the key file '${__fvl_o[keys]-}'"
            return 255
        fi
        if ! { exec {__fvl_ofd}>"${__fvl_o[fvout]-/dev/null}"; } 2>/dev/null; then
            exec {__fvl_kfd}<&-
            fv.dlg._say "$__fvl_face" "cannot write the frame file '${__fvl_o[fvout]-}'"
            return 255
        fi
        __fvl_fd=${__fvl_o[size]-80x24}
        FV_APP_HEADLESS=1 FV_SCREEN_W=$(( 10#${__fvl_fd%%x*} )) FV_SCREEN_H=$(( 10#${__fvl_fd#*x} )) FV_VIDEO_OUT_FD=$__fvl_ofd FV_KEY_FD=$__fvl_kfd
    fi
    if [ "${FV_APP_HEADLESS-}" = 1 ]; then __fvl_hl=1; fi
    if [ "$__fvl_face" = main ]; then fv.dlg._bufOn; fi
    # the infobox: the main screen (noalt) turned on here, so the application
    # leaves it on at its Done and the box stays visible
    if [ "$__fvl_w" = infobox ] && (( ! __fvl_hl )) && (( ! FV_VIDEO_ON )); then
        if fv.video.initVideo noalt; then __fvl_vid=1; else __fvl_ok=0; fi
    fi
    if (( __fvl_ok )) && fv.views._newReserved '' dlgapp TDlgApp; then
        __fvl_app=$RESULT
        # --fv-mouse off: the reporting the application's start turned on
        # switched off again (fv.mouse alone: fv.drivers.doneEvents would
        # also drop the keys already read)
        if [ "${__fvl_o[mouse]-on}" = off ] && (( ! __fvl_hl )) && [[ -n ${FV_TTY_FD-} ]]; then fv.mouse.disable "$FV_TTY_FD" || :; fi
        if [[ -n ${NO_COLOR-} ]]; then fv.dlg._nocolor; fi
        if fv.dlg._build; then
            if [ "$__fvl_w" = infobox ]; then
                # P4-10: one paint, no loop, the cursor on the last row
                fv.views.insert "$FV_DESKTOP" "$__fvl_d" || :
                fv.app._firstPaint "$__fvl_app" || :
                fv.video.setCursorPos 0 "$(( FV_SCREEN_H - 1 ))" || :
                fv.video.setCursorType 1 || :
                fv.video.updateScreen || :
                __fvl_cmd=cmOK
            else
                fv.views.execView "$FV_DESKTOP" "$__fvl_d" || :
                __fvl_cmd=${RESULT:-cmCancel}
            fi
            if [ "$__fvl_cmd" = cmOK ] || [ "$__fvl_cmd" = cmYes ]; then __fvl_rc=0
            elif [ "$__fvl_cmd" = cmNo ]; then __fvl_rc=1; fi
            if (( __fvl_rc == 0 )) && [[ -n $__fvl_il ]] && fv.dialogs.getText "$__fvl_il"; then __fvl_res=$RESULT; fi
        else
            __fvl_ok=0
        fi
        # (the infobox's dialog goes with the desktop at the application's
        # Done, which draws nothing: deleted alone first it would repaint
        # the desktop over the box)
        if [ "$__fvl_w" != infobox ] && [[ -n $__fvl_d && -n ${__FV_VW_LIVE[$__fvl_d]-} ]]; then "$__fvl_d.delete"; fi
        "$__fvl_app.delete"
    else
        __fvl_ok=0 __fvl_err="no terminal (${FV_TTY:-/dev/tty})"
    fi
    if (( __fvl_vid )); then fv.video.doneVideo || :; fi
    if [[ -n $__fvl_kfd ]]; then exec {__fvl_kfd}<&- {__fvl_ofd}>&-; fi
    if [ "$__fvl_face" = main ]; then fv.dlg._bufOff; fi
    if (( ! __fvl_ok )); then
        fv.dlg._say "$__fvl_face" "${__fvl_err:-the dialog could not be made}"
        RESULT='' FV_DLG_CMD=''
        return 255
    fi
    FV_DLG_CMD=$__fvl_cmd
    RESULT=$__fvl_res
    # the result: once, after the restore, only on 0 (nothing on 1 / 255)
    __fvl_fd=${__fvl_o[out]-}
    if [ "$__fvl_face" = main ]; then __fvl_fd=${__fvl_fd:-2}; fi
    if (( __fvl_rc == 0 )) && [[ -n $__fvl_fd && -n $__fvl_il ]]; then
        # (an open fd checked first: the probe's own stderr is /dev/null, so
        # fd 2 itself is written without a redirection around it)
        if ! { : >&$__fvl_fd; } 2>/dev/null; then
            fv.dlg._say "$__fvl_face" "cannot write the result to fd $__fvl_fd"
            RESULT='' FV_DLG_CMD=''
            return 255
        fi
        printf '%s' "$__fvl_res" >&$__fvl_fd
    fi
    return "$__fvl_rc"
}

# fv.dlg._usage — --help (the command)
fv.dlg._usage() {
    printf '%s\n' \
        'Usage: fvdlg [OPTION...] WIDGET TEXT HEIGHT WIDTH [ARG...]' \
        'Free Vision dialogs for shell scripts (kbool fv.dlg); whiptail / dialog flags.' \
        '' \
        'Widgets:' \
        '  --msgbox TEXT H W            a message, OK' \
        '  --yesno TEXT H W             Yes / No (status 0 / 1)' \
        '  --infobox TEXT H W           drawn once, returns at once' \
        '  --inputbox TEXT H W [INIT]   a line of text, OK / Cancel' \
        '  --passwordbox TEXT H W [INIT]  the same, typed text shown as *' \
        '' \
        'H / W: 0 = fit the text, -1 = the whole screen.' \
        'Status: 0 OK / Yes, 1 Cancel / No, 255 Esc or an error.' \
        'The answer goes to stderr; --stdout, --output-fd N choose another.' \
        '' \
        'Options: --title T --backtitle T --ok-button/--ok-label L --cancel-button/--cancel-label L' \
        '  --yes-button/--yes-label L --no-button/--no-label L --defaultno --nocancel/--no-cancel' \
        '  --stdout --stderr --output-fd N --colors --topleft --no-shadow --ascii-lines' \
        '  --clear --keep-tite --erase-on-exit --scrolltext --fb --insecure (accepted)' \
        '  --fv-palette gray|blue|cyan  --fv-ascii  --fv-mouse on|off  --fv-echo star|none' \
        '  --fv-screen alt|main  --fv-output lines|quoted|single' \
        '  --fv-headless [--fv-keys FILE] [--fv-size WxH] [--fv-out FILE]   (tests)' \
        '  --help  --version'
}

# ---- the faces --------------------------------------------------------------------

# fv.dlg.main ARG... — the command's face; returns the status (bin/fvdlg exits
# with it)
fv.dlg.main() { fv.dlg._call main "$@"; }
# fv.dlg.run ARG... — the bash face: RESULT, FV_DLG_CMD, the status
fv.dlg.run() { fv.dlg._call run "$@"; }
