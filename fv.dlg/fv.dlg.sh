#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.dlg.sh}../../kbool.sh" || return
kk.unit fv.dlg || return $__kk_unit_rc

# fv.dlg — one-shot dialogs for the fv.* text UI (P4, design
# kcl/docs/dev/fv/P4_DESIGN.md; stages 4a-1: the parser, the boxes, the
# input boxes, the results; 4a-2: the lists, the sizes, the scrolling text,
# sessions and the host application). whiptail / dialog-compatible flags
# (D32) on Free Vision's classes; two faces, one parser (P4-2):
#
#   fv.dlg.main ARG...    the command's face (bin/fvdlg calls it, stage 4b):
#                         the result on stderr (whiptail / dialog), stdout
#                         with --stdout, fd N with --output-fd N; stderr /
#                         stdout buffered while the UI runs when they are
#                         the terminal (P4-6); --help / --version (the text
#                         in fv.dlg.usage.sh, bin/fvdlg's too); answers
#                         the exit status (it returns it: bin/fvdlg exits)
#   fv.dlg.run ARG...     the bash face: the same argv and rules, the answer
#                         in RESULT (+ FV_DLG_TAGS, a list's chosen tags;
#                         FV_DLG_CMD, the FV command that ended the dialog),
#                         nothing printed unless --stdout / --stderr /
#                         --output-fd asks; the same status
#   fv.dlg.begin [OPT...] / fv.dlg.end
#                         a session: one application and one screen for the
#                         fv.dlg.run calls between them (design §2.2)
# Inside a running fv application (FV_APP live) fv.dlg.run builds on its
# desktop (the host-application mode); in a session or a host only in the
# shell that owns the screen (inside $( ): 255).
#
# Status (FV_DLG_OK / FV_DLG_CANCEL / FV_DLG_ESC, readonly): 0 OK / Yes, 1
# Cancel / No (the buttons send cmNo, P4-4), 255 Esc / Ctrl+F4 / the close
# icon / the end of input / no terminal / too small / bad arguments (one line
# on stderr). Ctrl+C / SIGTERM / SIGHUP are fv.video's (130 / 143 / 129,
# restored).
#
# Widgets: --msgbox --yesno --infobox (P4-10: drawn once, no loop, the main
# screen, FV_KBD_PROTO=off unless set, the cursor on the last row; in a
# session / host left on the desktop until the next call) --inputbox
# --passwordbox (INIT selected: the first key replaces it; D38: '*' per
# character, --fv-echo none shows nothing) --menu --checklist --radiolist
# (TDlgList; D37's answers) --gauge (4d: TDlgGauge, the percentages read
# from stdin by TDlgApp.Idle — fv.dlg._gPoll; stdin a terminal: 255 before
# any screen change) --textbox (4d: the file in the scrolling text view and
# OK; fv.dlg._file). Text that does not fit scrolls (TDlgText, P4-9).
# Parser rules (P4-7, design §4.5): options anywhere before `--`, the
# widget's fixed positionals literal, an optional positional unless it is
# exactly a known option, list items in groups (an option only at a group
# boundary), `--` ends the options, --opt=value or --opt value, one widget
# per call; `\n` in TEXT is a newline, dialog's \Z escapes are stripped
# with --colors (P4-9). Sizes (P4-8): 0 fits, -1 the desktop, a number
# clamped, below the widget's minimum 255; spare rows of an explicit H go to
# the list; a resize lays the dialog out again as a build at that size
# would (below the minimum: 255 after the restore); an empty button label
# is a blank button. A caller locale that is not UTF-8: fv.video's D11 scope.
# The screen (D34, a call alone or fv.dlg.begin): --fv-screen alt|main, else
# --keep-tite alt, else --erase-on-exit main, else alt; --clear and
# --erase-on-exit clear the main screen at the exit; on the main screen the
# last dialog stays and the cursor ends on the last row (dialog's endwin);
# the infobox always uses the main screen and is never cleared. No terminal
# (D36): --no-tty=default answers what Enter would, without a UI
# (fv.dlg._dflt); --no-tty=refuse (the default) 255; bin/fvdlg adds
# FVDLG_NOTTY's value and refuses before the load.
#
# Conventions (as the other fv units): locals `__fvl_*`, globals `__FV_DL_*`
# (the list's arrays `__DLFV_*`: fv.views refuses List / Marks names that
# start with _fv / __fv); fork-free on every path but P4-6's buffer (one
# `rm`, one `trap -p`, in a subshell fv.video._drop's one `trap -p`; only
# when a buffer is made); set -eu clean; names compared with `[ "$a" = "$b"
# ]` (nocasematch), character classes as lists (no ranges). Friend uses
# (the same framework): fv.views' __FV_VW_LIVE, __FV_VW_OWNER, __FV_VW_C2A,
# _newReserved, _showNow, _message, _lvEvent / _lvSelectItem (TDlgList's and
# TDlgText's inherited bodies) and its elision table __FV_VW_IMPL (TDlgList,
# TDlgText and TDlgApp register their bodies there, as fv.dialogs does: no
# kklass dispatch per key), fv.video's __FV_VS_PNA (printable ASCII) and
# _drop (P4-6 in a subshell), fv.app's _firstPaint (the infobox's one paint
# without a loop; a session's first paint) and _appEvent (TApplication's
# HandleEvent body), fv.mouse's disable (--fv-mouse off without fv.drivers'
# flush of the keys).
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
#              --stderr 2; --output-fd: o v), w NAME FIXED OPTIONAL [GROUP]
#              (a widget; GROUP: the list items' group size), n NAME (a
#              widget not supported yet), x (a flag
#              refused: outside the subset), m (the command only: --help,
#              --version)
#   BUF        P4-6's buffer while the UI runs: (FILE SAVED1 SAVED2 TRAP)
#   DIR        this file's folder (fv.dlg.usage.sh, the --help / --version
#              text, lives there)
#   KIND[list] a TDlgList's widget (menu | checklist | radiolist)
#   LAY        the running dialog's layout for a resize (fv.dlg._build)
#   SMALL      a resize below the minimum: the message ('' none)
#   SES        the session (fv.dlg.begin): app, title, kfd, ofd, s_VAR (the
#              caller's terminal settings: sVALUE or u), main (1: the main
#              screen), clr (1: cleared at the end), vid (1: begin turned
#              the terminal on, noalt)
#   INFO       the infobox a session / the host still shows ('' none)
#   TOPT       the terminal options' names (refused in a session / host)
#   JUMP[C]    the letter jumps' index of the list JN: its first item whose row
#   JN         starts with C (lower case; built on the first letter, fv.dlg._jumpIdx)
#   G[K]       the running gauge (fv.dlg._gRun; empty when none): d the
#              dialog, pct the percentage read, spct the one shown, text /
#              ntext the prompt and 1 when a new one waits to be shown,
#              part the partial line kept across polls, skip 1 while an
#              over-long partial line is dropped up to its newline, blk the
#              XXX block's state (0 none, 1 its percentage next, 2 its
#              text), bpct / btxt / bn the block read so far, eof 1 at
#              stdin's end, on 1 while it runs (TDlgApp.Idle polls then);
#              polls / shows / tshows: the polls, the meter's and the
#              text's redraws (kept after the call: the tests' view)
#   TXCAP      the textbox's size cap in bytes (fv.dlg._file; an internal
#              self-default, 1 MiB)
# The list's and the text view's arrays (fv.views refuses List / Marks
# names that start with _fv / __fv): __DLFV_TAGS __DLFV_ROWS __DLFV_MARKS
# __DLFV_FIRST __DLFV_NEXT __DLFV_TEXT
# FV_DLG_TAGS  output: the chosen tags of the last list (an array)
# (the two outputs keep a caller's value: the settings hook, kkore kk.settings)
fv.dlg._settings() {
    declare -g FV_DLG_CMD=${FV_DLG_CMD-}
    declare -ga FV_DLG_TAGS
    FV_DLG_TAGS+=()
    return 0
}
kk.settings fv.dlg._settings FV_DLG_CMD FV_DLG_TAGS || return
declare -g __FV_DL_DIR=${BASH_SOURCE[0]%/*}
if [[ $__FV_DL_DIR == "${BASH_SOURCE[0]}" ]]; then __FV_DL_DIR=.; fi
if [[ $__FV_DL_DIR != /* && $__FV_DL_DIR != [A-Za-z]:* ]]; then __FV_DL_DIR=$PWD/$__FV_DL_DIR; fi
declare -ga __FV_DL_BUF __DLFV_TAGS __DLFV_ROWS __DLFV_MARKS __DLFV_FIRST __DLFV_NEXT __DLFV_TEXT __DLFV_RAW
__FV_DL_BUF+=() __DLFV_TAGS+=() __DLFV_ROWS+=() __DLFV_MARKS+=() __DLFV_FIRST+=() __DLFV_NEXT+=() __DLFV_TEXT+=() __DLFV_RAW+=()
declare -gA __FV_DL_KIND __FV_DL_LAY __FV_DL_SES __FV_DL_JUMP __FV_DL_G
declare -g __FV_DL_SMALL=${__FV_DL_SMALL-} __FV_DL_INFO=${__FV_DL_INFO-} __FV_DL_JN=${__FV_DL_JN-}
declare -g __FV_DL_TXCAP=${__FV_DL_TXCAP:-1048576} __FV_DL_TXW=${__FV_DL_TXW:-0} __FV_DL_TXX=${__FV_DL_TXX:-0}
# (dialog's --single-quoted: the characters that make a tag quoted, the
# ones escaped inside the quotes)
__FV_DL_QSET=$' \t[]{}?*;`~#$^&()|<>' __FV_DL_QESC=$'\'\\\n'
declare -gA __FV_DL_TOPT=([headless]=--fv-headless [keys]=--fv-keys [size]=--fv-size [fvout]=--fv-out
    [ascii]='--fv-ascii / --ascii-lines' [mouse]=--fv-mouse [screen]=--fv-screen)
declare -gA __FV_DL_OPT=(
    [--msgbox]='w msgbox 3 0' [--yesno]='w yesno 3 0' [--infobox]='w infobox 3 0'
    [--inputbox]='w inputbox 3 1' [--passwordbox]='w passwordbox 3 1'
    [--menu]='w menu 4 0 2' [--checklist]='w checklist 4 0 3' [--radiolist]='w radiolist 4 0 3'
    [--gauge]='w gauge 3 1' [--textbox]='w textbox 3 0'
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
    [--fv-screen]='v screen' [--fv-output]='v output' [--no-tty]='v notty'
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
    [output]='lines quoted single' [notty]='default refuse'
)

# ---- the application ----------------------------------------------------------------
# TDlgApp : TApplication — no status line (the desktop takes every row; D23
# gives no menu bar). Its HandleEvent: TApplication's, then after a resize
# the running dialog laid out again or ended below the minimum (P4-8,
# fv.dlg._relayout). Its Idle: TProgram's, then a running gauge's stdin
# poll (fv.dlg._appIdle) — paced by the event read's FV_IDLE_TIMEOUT wait
class TDlgApp : TApplication
    public
        nofields override proc InitStatusLine
        nofields override proc HandleEvent
        nofields override proc Idle
end
TDlgApp.InitStatusLine() { return 0; }
TDlgApp.HandleEvent() { fv.dlg._appEvent "$this" "$@" || return; }
TDlgApp.Idle() { fv.dlg._appIdle "$this" "$@" || return; }
build TDlgApp

# TDlgGauge : TView — the gauge's meter (--gauge, 4d): one row, the bar
# (█ done, ░ to do; ASCII mode # and :) and the percentage " NNN%" at its
# right end, in the owner's colour 6 (a dialog's static text: TView has no
# palette). Pct 0..100 (fv.dlg._gShow sets it). A proc override: one
# dispatch per draw, and a gauge draws only when its percentage changes
class TDlgGauge : TView
    public
        var Pct
        override proc Draw
end
TDlgGauge.Draw() {
    local __fvl_s __fvl_b __fvl_n=$(( SizeX - 5 )) __fvl_f __fvl_p=${Pct:-0} __fvl_a='█' __fvl_e='░'
    if (( __fvl_n < 0 )); then __fvl_n=0; fi
    if (( FV_VIDEO_ASCII )); then __fvl_a='#' __fvl_e=':'; fi
    __fvl_f=$(( __fvl_n * __fvl_p / 100 ))
    printf -v __fvl_s '%*s' "$__fvl_f" ''
    printf -v __fvl_b '%*s' "$(( __fvl_n - __fvl_f ))" ''
    __fvl_s=${__fvl_s// /$__fvl_a}${__fvl_b// /$__fvl_e}
    printf -v __fvl_b ' %3d%%' "$__fvl_p"
    fv.views.writeStr 0 0 "${__fvl_s}${__fvl_b:0:SizeX}" 6
}
build TDlgGauge

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

# TDlgList : TListBox — the list of --menu / --checklist / --radiolist
# (design §5.1, M8). Its kind in __FV_DL_KIND[NAME] (menu | checklist |
# radiolist); the rows __DLFV_ROWS, the marks __DLFV_MARKS (D26), the tags
# __DLFV_TAGS and their first characters __DLFV_FIRST (lower case) are the
# unit's arrays (fv.views refuses List / Marks names that start with _fv /
# __fv). HandleEvent: a printable character jumps to the next item whose
# tag (the item with --notags) starts with it, case-insensitive, wrapping
# (dialog's rule; golden2); a character no item starts with does nothing
# (it never reaches the buttons' hot keys); Space in a menu does nothing;
# the rest is TListViewer's. SelectItem (Space, Ins, a double click):
# checklist — TListViewer's toggle; radiolist — that item alone marked
# (Space on the marked one keeps it); menu — a double click ends the dialog
# with cmOK. Both bodies are registered in fv.views' __FV_VW_IMPL (the
# elision fv.dialogs uses for its classes): no kklass dispatch per key
class TDlgList : TListBox
    public
        nofields override proc HandleEvent
        nofields override proc SelectItem
end
TDlgList.HandleEvent() { fv.dlg._lsEvent "$this" "$@" || return; }
TDlgList.SelectItem() { fv.dlg._lsSelect "$this" "$@" || return; }
build TDlgList

# TDlgText : TListViewer — read-only text that does not fit (P4-9): the
# wrapped lines in __DLFV_TEXT, every row in the static text's colour (the
# focused row is not highlighted: GetPalette answers the dialog's entry 6
# five times), Up / Down / PgUp / PgDn / Home / End scroll the text (the
# top row; the focus follows it unseen), the wheel and the bar as
# TListViewer's. Registered in __FV_VW_IMPL as TDlgList's
class TDlgText : TListViewer
    public
        nofields override func GetPalette
        nofields override proc HandleEvent
end
TDlgText.GetPalette() { fv.dlg._txPal "$this" || return; }
TDlgText.HandleEvent() { fv.dlg._txEvent "$this" "$@" || return; }
build TDlgText

# fv.dlg._register — the classes' bodies into fv.views' elision table (at
# load; fv.views keeps the table over its reload, and fv.dlg._build
# registers again when an entry is missing: fv.dialogs' rule, checked once
# per dialog instead of per constructor — the classes have none)
fv.dlg._register() {
    __FV_VW_IMPL[TDlgList.HandleEvent]=fv.dlg._lsEvent
    __FV_VW_IMPL[TDlgList.SelectItem]=fv.dlg._lsSelect
    __FV_VW_IMPL[TDlgText.GetPalette]=fv.dlg._txPal
    __FV_VW_IMPL[TDlgText.HandleEvent]=fv.dlg._txEvent
    __FV_VW_IMPL[TDlgApp.HandleEvent]=fv.dlg._appEvent
    __FV_VW_IMPL[TDlgApp.Idle]=fv.dlg._appIdle
}
fv.dlg._register

# ---- helpers ----------------------------------------------------------------------
# fv.dlg._say FACE MSG — one refusal line on stderr: "fvdlg: MSG" for the
# command, "fv.dlg.run: MSG" for the bash face ("fv.dlg.begin: MSG" for begin)
fv.dlg._say() {
    local __fvl_n=fvdlg
    if [ "$1" = run ]; then __fvl_n=fv.dlg.run; elif [ "$1" = begin ]; then __fvl_n=fv.dlg.begin; fi
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
# fv.dlg._hasTerm FACE — rc 0 when the call has a terminal (P4-5, design
# §3.4 / §3.6; D36's test): FV_TTY (default /dev/tty) exists, opens and is
# a terminal; the command's face (main) also wants TERM set and not `dumb`
# (FVDLG_FORCE=1 lifts that rule) — the bash face (run) has no TERM rule.
# rc 1 with REPLY = why, in bin/fvdlg's words: the path, or 'TERM is empty|
# dumb; FVDLG_FORCE=1 overrides'. The order is bin/fvdlg's pre-load guard's
# (exists, opens, TERM), the isatty last — so the unit names what the guard
# would have named. Fork-free
fv.dlg._hasTerm() {
    local IFS= __fvl_f='' __fvl_t=${FV_TTY:-/dev/tty}
    REPLY=$__fvl_t
    # (-e first: `<>` would create a missing path)
    [[ -e $__fvl_t ]] || return 1
    { exec {__fvl_f}<>"$__fvl_t"; } 2>/dev/null || return 1
    if [ "${1-}" = main ] && { [[ -z ${TERM-} ]] || [ "$TERM" = dumb ]; } && ! [ "${FVDLG_FORCE-}" = 1 ]; then
        exec {__fvl_f}>&-
        if [[ -z ${TERM-} ]]; then REPLY='TERM is empty'; else REPLY='TERM is dumb'; fi
        REPLY+='; FVDLG_FORCE=1 overrides'
        return 1
    fi
    if [[ ! -t $__fvl_f ]]; then exec {__fvl_f}>&-; return 1; fi
    exec {__fvl_f}>&-
    REPLY=''
    return 0
}
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
    local IFS=$' \t\n' __fvl_a __fvl_k __fvl_v __fvl_hv __fvl_kind __fvl_x __fvl_y __fvl_z __fvl_g=0 __fvl_gi=0 __fvl_n
    local __fvl_need=0 __fvl_opt=0 __fvl_dd=0
    while (( $# )); do
        __fvl_a=$1
        shift
        # the widget's fixed positionals: literal (TEXT may look like an
        # option); H and W (and a list's LH) checked as soon as they are
        # taken (the refusal names the word that stood there)
        if (( __fvl_need > 0 )); then
            __fvl_p+=("$__fvl_a")
            __fvl_need=$(( __fvl_need - 1 ))
            if (( __fvl_need == 0 )); then
                # the sizes: integers (0 = fit the text, -1 = the whole screen)
                if ! fv.dlg._int "${__fvl_p[1]}"; then __fvl_err="HEIGHT must be an integer (got '${__fvl_p[1]}')"; return 1; fi
                if ! fv.dlg._int "${__fvl_p[2]}"; then __fvl_err="WIDTH must be an integer (got '${__fvl_p[2]}')"; return 1; fi
                if (( __fvl_g )) && { ! fv.dlg._int "${__fvl_p[3]}" || [[ ${__fvl_p[3]} == -* ]]; }; then
                    __fvl_err="LIST-HEIGHT must be an integer, 0 or more (got '${__fvl_p[3]}')"; return 1
                fi
            fi
            continue
        fi
        # list items (design §4.5 rule 4): inside a group always data; at a
        # group boundary `--` and the known options are what they are,
        # anything else starts a group
        if (( __fvl_g && __fvl_gi )); then
            __fvl_p+=("$__fvl_a") __fvl_gi=$(( (__fvl_gi + 1) % __fvl_g ))
            continue
        fi
        if (( __fvl_dd )); then
            if (( __fvl_g )); then __fvl_p+=("$__fvl_a") __fvl_gi=$(( 1 % __fvl_g )); continue; fi
            if (( __fvl_opt > 0 )); then __fvl_p+=("$__fvl_a"); __fvl_opt=$(( __fvl_opt - 1 )); continue; fi
            __fvl_err="unexpected argument '$__fvl_a'"
            return 1
        fi
        if [ "$__fvl_a" = -- ]; then __fvl_dd=1; continue; fi
        __fvl_k=$__fvl_a __fvl_v='' __fvl_hv=0
        if [[ $__fvl_a == --?*=* ]]; then __fvl_k=${__fvl_a%%=*} __fvl_v=${__fvl_a#*=} __fvl_hv=1; fi
        __fvl_kind=''
        if [[ -n $__fvl_k ]]; then __fvl_kind=${__FV_DL_OPT[$__fvl_k]-}; fi
        if [[ -z $__fvl_kind ]]; then
            if (( __fvl_g )); then __fvl_p+=("$__fvl_a") __fvl_gi=$(( 1 % __fvl_g )); continue; fi
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
                # (FIXED OPTIONAL [GROUP])
                __fvl_w=$__fvl_y __fvl_need=${__fvl_z%% *} __fvl_z=${__fvl_z#* } __fvl_opt=${__fvl_z%% *}
                if [[ $__fvl_z == *' '* ]]; then __fvl_g=${__fvl_z#* }; fi ;;
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
        if (( __fvl_g )); then __fvl_err="'--$__fvl_w' needs TEXT HEIGHT WIDTH LIST-HEIGHT (got ${#__fvl_p[@]} of 4)"
        else __fvl_err="'--$__fvl_w' needs TEXT HEIGHT WIDTH (got ${#__fvl_p[@]} of 3)"; fi
        return 1
    fi
    if [[ -z $__fvl_w ]]; then
        __fvl_err='no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox, --menu, --checklist, --radiolist, --gauge, --textbox)'
        return 1
    fi
    # the gauge's PERCENT: an integer (clamped to 0..100 when shown)
    if [ "$__fvl_w" = gauge ] && (( ${#__fvl_p[@]} > 3 )) && ! fv.dlg._int "${__fvl_p[3]}"; then
        __fvl_err="PERCENT must be an integer (got '${__fvl_p[3]}')"
        return 1
    fi
    # the list items: whole groups, at least one; STATUS on / off in any case
    if (( __fvl_g )); then
        __fvl_n=$(( ${#__fvl_p[@]} - 4 ))
        if (( __fvl_g == 2 )); then __fvl_x='TAG ITEM'; else __fvl_x='TAG ITEM STATUS'; fi
        if (( __fvl_n == 0 )); then __fvl_err="'--$__fvl_w' needs at least one $__fvl_x group (the list is empty)"; return 1; fi
        if (( __fvl_gi )); then
            __fvl_err="'--$__fvl_w' takes $__fvl_x groups ($__fvl_n words after LIST-HEIGHT: the last group is incomplete)"
            return 1
        fi
        if (( __fvl_g == 3 )); then
            for (( __fvl_n = 6; __fvl_n < ${#__fvl_p[@]}; __fvl_n += 3 )); do
                __fvl_v=${__fvl_p[__fvl_n],,}
                if ! [ "$__fvl_v" = on ] && ! [ "$__fvl_v" = off ]; then
                    __fvl_err="STATUS must be on or off (got '${__fvl_p[__fvl_n]}' for the tag '${__fvl_p[__fvl_n-2]}')"
                    return 1
                fi
            done
        fi
    fi
    # the fv extras' values: one of the allowed words, exactly (`[ = ]`, not
    # a pattern: no substring, nocasematch has no say)
    for __fvl_k in palette mouse echo screen output notty; do
        [[ -n ${__fvl_o[$__fvl_k]+x} ]] || continue
        __fvl_v=${__fvl_o[$__fvl_k]} __fvl_x=${__FV_DL_VAL[$__fvl_k]} __fvl_z=0
        while [[ -n $__fvl_x ]]; do
            __fvl_y=${__fvl_x%% *}
            if [ "$__fvl_v" = "$__fvl_y" ]; then __fvl_z=1; break; fi
            if [ "$__fvl_y" = "$__fvl_x" ]; then break; fi
            __fvl_x=${__fvl_x#* }
        done
        if (( ! __fvl_z )); then
            __fvl_x=${__FV_DL_VAL[$__fvl_k]} __fvl_y=--fv-$__fvl_k
            if [ "$__fvl_k" = notty ]; then __fvl_y=--no-tty; fi
            __fvl_err="$__fvl_y must be ${__fvl_x// / | } (got '$__fvl_v')"
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
    local __fvl_l __fvl_w=0 __fvl_n=0 __fvl_x __fvl_c __fvl_ww __fvl_a
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
        __fvl_c=0 __fvl_th=$(( __fvl_th + 1 )) __fvl_a=0
        # (a printable ASCII line: characters = cells, no call per word)
        if [[ ${__fvl_ls[__fvl_n]} != $__FV_VS_PNA ]]; then __fvl_a=1; fi
        for __fvl_l in "${__fvl_wd[@]}"; do
            if (( __fvl_a )); then __fvl_ww=${#__fvl_l}; else fv.video.strWidth "$__fvl_l" || RESULT=${#__fvl_l}; __fvl_ww=$RESULT; fi
            if (( __fvl_c > 0 )); then __fvl_ww=$(( __fvl_ww + 1 )); fi
            if (( __fvl_c + __fvl_ww >= __fvl_tw && __fvl_c > 0 )); then
                __fvl_th=$(( __fvl_th + 1 )) __fvl_c=0
            fi
            __fvl_c=$(( __fvl_c + __fvl_ww ))
            # (a word past the row: a row per tw - 1 cells, counted at once)
            if (( __fvl_c >= __fvl_tw )); then
                __fvl_x=$(( (__fvl_c - __fvl_tw) / (__fvl_tw > 1 ? __fvl_tw - 1 : 1) + 1 ))
                __fvl_th=$(( __fvl_th + __fvl_x )) __fvl_c=$(( __fvl_c - __fvl_x * (__fvl_tw - 1) ))
            fi
        done
    done
    (( __fvl_th > 0 )) || __fvl_th=1
}

# fv.dlg._wrap TEXT W — the caller's array __fvl_wl = TEXT's rows at W cells
# for TDlgText, by TStaticText's rule: a row breaks when its cells reach W,
# at the last blank (which starts the next row), else a word is cut at W
# cells; every line of TEXT starts a row (an empty line: an empty row).
# Linear in TEXT (M3): a line is split into its words once (mapfile on the
# blanks; a token is the blanks before a word and the word), a printable
# ASCII line counts characters, a long word is cut in blocks
# (fv.dlg._wcut) — no expansion of the whole line per token (bash copies
# a variable's whole value on every expansion)
fv.dlg._wrap() {
    local __fvl_l __fvl_f __fvl_tk __fvl_cur __fvl_cw __fvl_tw __fvl_n __fvl_pb __fvl_a __fvl_i __fvl_k
    local -a __fvl_ls=() __fvl_fs=()
    __fvl_wl=()
    mapfile -t __fvl_ls <<< "$1"
    for __fvl_l in "${__fvl_ls[@]}"; do
        # (fewer characters than W: the cells decide; W or more characters
        # take the token walk, which gives a line that fits one row anyway)
        if (( ${#__fvl_l} < $2 )); then
            fv.video.strWidth "$__fvl_l" || RESULT=${#__fvl_l}
            if (( RESULT < $2 )); then __fvl_wl+=("$__fvl_l"); continue; fi
        fi
        __fvl_a=0
        if [[ $__fvl_l != $__FV_VS_PNA ]]; then __fvl_a=1; fi
        mapfile -t -d ' ' __fvl_fs <<< "$__fvl_l"
        __fvl_fs[-1]=${__fvl_fs[-1]%$'\n'}
        __fvl_cur='' __fvl_cw=0 __fvl_n=${#__fvl_wl[@]} __fvl_pb='' __fvl_k=${#__fvl_fs[@]}
        for (( __fvl_i = 0; __fvl_i <= __fvl_k; __fvl_i++ )); do
            # (a field per blank: the token = the blanks since the last word
            # and the next word; past the last field the blanks left over)
            if (( __fvl_i == __fvl_k )); then
                [[ -n $__fvl_pb ]] || break
                __fvl_tk=$__fvl_pb
            else
                if (( __fvl_i )); then __fvl_pb+=' '; fi
                __fvl_f=${__fvl_fs[__fvl_i]}
                [[ -n $__fvl_f ]] || continue
                __fvl_tk=$__fvl_pb$__fvl_f
            fi
            __fvl_pb=''
            if (( __fvl_a )); then __fvl_tw=${#__fvl_tk}; else fv.video.strWidth "$__fvl_tk" || RESULT=${#__fvl_tk}; __fvl_tw=$RESULT; fi
            if (( __fvl_cw + __fvl_tw < $2 )); then __fvl_cur+=$__fvl_tk __fvl_cw=$(( __fvl_cw + __fvl_tw )); continue; fi
            if (( __fvl_cw > 0 )); then __fvl_wl+=("$__fvl_cur"); fi
            __fvl_cur=$__fvl_tk __fvl_cw=$__fvl_tw
            if (( __fvl_cw >= $2 )); then fv.dlg._wcut "$2" "$__fvl_a"; fi
        done
        if [[ -n $__fvl_cur ]] || (( ${#__fvl_wl[@]} == __fvl_n )); then __fvl_wl+=("$__fvl_cur"); fi
    done
    (( ${#__fvl_wl[@]} )) || __fvl_wl=('')
}
# fv.dlg._wcut W ASCII — _wrap's caller-state __fvl_cur (a token of W cells
# or more) cut into rows appended to __fvl_wl, the rest (under W cells) left
# in __fvl_cur / __fvl_cw: a row is the longest head of at most W cells (one
# cell's content at least: a wider one alone). Printable ASCII: pieces of W
# characters (a long token read in pieces from a here-string: each step
# expands a piece, not the whole token — bash copies a variable's whole
# value on every expansion); other text walked by fv.video.clusters (the
# cells as the writes cut them: a cluster is never split), 1024 characters
# at a time, the last cluster carried into the next block (it may grow)
fv.dlg._wcut() {
    local __fvl_t=$__fvl_cur __fvl_bk __fvl_j __fvl_e=0 __fvl_q=''
    local -a _fvdl_cl=() _fvdl_cw=()
    if (( $2 )); then
        if (( ${#__fvl_t} <= 2048 )); then
            while (( __fvl_cw >= $1 )); do
                __fvl_wl+=("${__fvl_cur:0:$1}")
                __fvl_cur=${__fvl_cur:$1} __fvl_cw=$(( __fvl_cw - $1 ))
            done
            return 0
        fi
        __fvl_cur='' __fvl_cw=0
        # (the here-string's newline ends the last piece: dropped)
        while IFS= read -r -N "$1" __fvl_bk || [[ -n $__fvl_bk ]]; do
            __fvl_bk=${__fvl_bk%$'\n'}
            if (( ${#__fvl_bk} >= $1 )); then __fvl_wl+=("$__fvl_bk"); else __fvl_cur=$__fvl_bk __fvl_cw=${#__fvl_bk}; fi
            __fvl_bk=''
        done <<< "$__fvl_t"
        return 0
    fi
    __fvl_cur='' __fvl_cw=0
    while (( ! __fvl_e )); do
        if ! IFS= read -r -N 1024 __fvl_bk; then __fvl_e=1; fi
        __fvl_bk=$__fvl_q${__fvl_bk%$'\n'}
        __fvl_q=''
        fv.video.clusters "$__fvl_bk" _fvdl_cl _fvdl_cw || :
        __fvl_bk=''
        for (( __fvl_j = 0; __fvl_j < ${#_fvdl_cl[@]}; __fvl_j++ )); do
            # (the block's last cluster: carried unless the token ends here)
            if (( ! __fvl_e && __fvl_j == ${#_fvdl_cl[@]} - 1 )); then __fvl_q=${_fvdl_cl[__fvl_j]}; break; fi
            if (( __fvl_cw + _fvdl_cw[__fvl_j] > $1 && __fvl_cw > 0 )); then __fvl_wl+=("$__fvl_cur"); __fvl_cur='' __fvl_cw=0; fi
            __fvl_cur+=${_fvdl_cl[__fvl_j]} __fvl_cw=$(( __fvl_cw + _fvdl_cw[__fvl_j] ))
        done
    done <<< "$__fvl_t"
    if (( __fvl_cw >= $1 )); then __fvl_wl+=("$__fvl_cur"); __fvl_cur='' __fvl_cw=0; fi
    return 0
}

# ---- the lists -------------------------------------------------------------------

# fv.dlg._items — the caller's list record (__fvl_w, __fvl_p, __fvl_o) into
# the unit's arrays: __DLFV_TAGS, __DLFV_ROWS (a row without its mark: the
# tag padded to the widest tag, two blanks, the item; --notags the item,
# --noitem the tag — both: the tag), __DLFV_MARKS (STATUS on; a radiolist
# keeps the LAST `on`: whiptail's rule, golden radio_twoon); the caller's
# __fvl_rw = the widest row in cells with its mark, __fvl_di = the
# --default-item's index (the first tag equal to it; 0 when none). The
# letter jumps' index is built on the first letter (fv.dlg._jumpIdx). L2:
# a list of printable ASCII without \x1f (the common case: cells =
# characters) is split by printf over the argv (tags, items, statuses, the
# padded rows: C speed) and measured by one light loop each; any other
# list takes one loop over its items and one printf per row
fv.dlg._items() {
    local __fvl_i __fvl_g=3 __fvl_c=0 __fvl_tw=0 __fvl_iw=0 __fvl_x __fvl_y __fvl_s __fvl_mode=b __fvl_z=''
    local -a __fvl_tl=() __fvl_il=() __fvl_sl=()
    if [ "$__fvl_w" = menu ]; then __fvl_g=2; else __fvl_z='%.0s'; fi
    __DLFV_TAGS=() __DLFV_ROWS=() __DLFV_MARKS=() __DLFV_FIRST=() __DLFV_NEXT=() __FV_DL_JUMP=() __FV_DL_JN=''
    if [[ -n ${__fvl_o[noitem]-} ]]; then __fvl_mode=t; elif [[ -n ${__fvl_o[notags]-} ]]; then __fvl_mode=i; fi
    local IFS=' '
    __fvl_s="${__fvl_p[*]:4}"
    if [[ $__fvl_s != $__FV_VS_PNA && $__fvl_s != *$'\x1f'* ]]; then
        printf -v __fvl_s "%s"$'\x1f'"%.0s$__fvl_z" "${__fvl_p[@]:4}"
        fv.dlg._usplit __DLFV_TAGS "$__fvl_s"
        printf -v __fvl_s "%.0s%s"$'\x1f'"$__fvl_z" "${__fvl_p[@]:4}"
        fv.dlg._usplit __fvl_il "$__fvl_s"
        for __fvl_x in "${__DLFV_TAGS[@]}"; do if (( ${#__fvl_x} > __fvl_tw )); then __fvl_tw=${#__fvl_x}; fi; done
        for __fvl_x in "${__fvl_il[@]}"; do if (( ${#__fvl_x} > __fvl_iw )); then __fvl_iw=${#__fvl_x}; fi; done
        if (( __fvl_g == 3 )); then
            printf -v __fvl_s '%.0s%.0s%s\x1f' "${__fvl_p[@]:4}"
            fv.dlg._usplit __fvl_sl "${__fvl_s,,}"
        fi
        case $__fvl_mode in
            t) __fvl_y="%s"$'\x1f'"%.0s$__fvl_z" ;;
            i) __fvl_y="%.0s%s"$'\x1f'"$__fvl_z" ;;
            *) __fvl_y="%-${__fvl_tw}s  %s"$'\x1f'"$__fvl_z" ;;
        esac
        printf -v __fvl_s "$__fvl_y" "${__fvl_p[@]:4}"
        fv.dlg._usplit __DLFV_ROWS "$__fvl_s"
        __fvl_c=${#__DLFV_TAGS[@]}
    else
        for (( __fvl_i = 4; __fvl_i < ${#__fvl_p[@]}; __fvl_i += __fvl_g )); do
            __fvl_x=${__fvl_p[__fvl_i]} __fvl_y=${__fvl_p[__fvl_i+1]}
            __DLFV_TAGS+=("$__fvl_x") __fvl_il+=("$__fvl_y")
            if (( __fvl_g == 3 )); then __fvl_sl+=("${__fvl_p[__fvl_i+2],,}"); fi
            fv.video.strWidth "$__fvl_x" || RESULT=${#__fvl_x}
            __fvl_tl+=("$RESULT")
            if (( RESULT > __fvl_tw )); then __fvl_tw=$RESULT; fi
            fv.video.strWidth "$__fvl_y" || RESULT=${#__fvl_y}
            if (( RESULT > __fvl_iw )); then __fvl_iw=$RESULT; fi
        done
        __fvl_c=${#__DLFV_TAGS[@]}
        for (( __fvl_i = 0; __fvl_i < __fvl_c; __fvl_i++ )); do
            __fvl_x=${__DLFV_TAGS[__fvl_i]} __fvl_y=${__fvl_il[__fvl_i]}
            if [ "$__fvl_mode" = t ]; then __fvl_s=$__fvl_x
            elif [ "$__fvl_mode" = i ]; then __fvl_s=$__fvl_y
            else printf -v __fvl_s '%s%*s  %s' "$__fvl_x" "$(( __fvl_tw - __fvl_tl[__fvl_i] ))" '' "$__fvl_y"; fi
            __DLFV_ROWS+=("$__fvl_s")
        done
    fi
    # the marks (STATUS on, any case; a radiolist's last)
    for (( __fvl_i = 0; __fvl_i < ${#__fvl_sl[@]} && __fvl_i < __fvl_c; __fvl_i++ )); do
        if [ "${__fvl_sl[__fvl_i]}" = on ]; then
            if [ "$__fvl_w" = radiolist ]; then __DLFV_MARKS=(); fi
            __DLFV_MARKS[__fvl_i]=1
        fi
    done
    case $__fvl_mode in
        t) __fvl_rw=$__fvl_tw ;;
        i) __fvl_rw=$__fvl_iw ;;
        *) __fvl_rw=$(( __fvl_tw + 2 + __fvl_iw )) ;;
    esac
    if ! [ "$__fvl_w" = menu ]; then __fvl_rw=$(( __fvl_rw + 4 )); fi
    __fvl_di=0
    if [[ -n ${__fvl_o[defitem]+x} ]]; then
        for (( __fvl_i = 0; __fvl_i < __fvl_c; __fvl_i++ )); do
            if [ "${__DLFV_TAGS[__fvl_i]}" = "${__fvl_o[defitem]}" ]; then __fvl_di=$__fvl_i; break; fi
        done
    fi
}
# fv.dlg._usplit NAME TEXT — the array NAME = TEXT's records, each ended by
# \x1f (word splitting in memory, no globbing: a here-string's mapfile
# reads byte by byte)
fv.dlg._usplit() {
    local - IFS=$'\x1f'
    set -f
    local -n __fvl_ua=$1
    __fvl_ua=($2)
}
# fv.dlg._jumpIdx LIST — the letter jumps' index of the running list, built
# on its first letter key (L2; __FV_DL_JN = LIST then): __DLFV_FIRST[I] (the
# row's first character in lower case: the tag's, the item's with
# --notags; a row of an empty tag starts with a blank, which never jumps),
# __FV_DL_JUMP[C] (the first item that starts with C), __DLFV_NEXT[I] (the
# next item with the same first character; none: unset)
fv.dlg._jumpIdx() {
    local __fvl_i=0 __fvl_f
    local -A __fvl_last=()
    __DLFV_FIRST=() __DLFV_NEXT=() __FV_DL_JUMP=()
    for __fvl_f in "${__DLFV_ROWS[@]}"; do __DLFV_FIRST+=("${__fvl_f:0:1}"); done
    __DLFV_FIRST=("${__DLFV_FIRST[@],,}")
    for __fvl_f in "${__DLFV_FIRST[@]}"; do
        if [[ -n $__fvl_f ]]; then
            if [[ -n ${__fvl_last[$__fvl_f]-} ]]; then __DLFV_NEXT[${__fvl_last[$__fvl_f]}]=$__fvl_i; else __FV_DL_JUMP[$__fvl_f]=$__fvl_i; fi
            __fvl_last[$__fvl_f]=$__fvl_i
        fi
        __fvl_i=$(( __fvl_i + 1 ))
    done
    __FV_DL_JN=$1
}
# fv.dlg._fmtC / _fmtR INDEX WIDTH — the checklist's / radiolist's row:
# its mark ([X] / [ ], (*) / ( )) and the row (TListViewer's Formatter)
fv.dlg._fmtC() {
    if [[ ${__DLFV_MARKS[$1]:-0} != 0 ]]; then RESULT="[X] ${__DLFV_ROWS[$1]}"; else RESULT="[ ] ${__DLFV_ROWS[$1]}"; fi
}
fv.dlg._fmtR() {
    if [[ ${__DLFV_MARKS[$1]:-0} != 0 ]]; then RESULT="(*) ${__DLFV_ROWS[$1]}"; else RESULT="( ) ${__DLFV_ROWS[$1]}"; fi
}

# TDlgList.HandleEvent (design §5.1): the letter jumps, Space in a menu
fv.dlg._lsEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbChar ] && [[ -n ${FV_EV_CHAR-} ]]; then
        if ! [ "$FV_EV_CHAR" = ' ' ]; then
            fv.dlg._lsJump "$1" "${FV_EV_CHAR,,}"
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
            return 0
        fi
        if [ "${__FV_DL_KIND[$1]-}" = menu ]; then FV_EV_WHAT=evNothing FV_EV_INFO=$1; return 0; fi
    fi
    fv.views._lvEvent "$1"
}
# fv.dlg._lsJump LIST C — the next item after the focused one (wrapping)
# whose first character is C, focused (FV FocusItemNum); none: nothing.
# Through the index (fv.dlg._jumpIdx, L2): no item starts with C — one
# lookup; the focused item starts with C — its chain's next (or the
# first); else C's chain walked to the first item past the focused one
fv.dlg._lsJump() {
    if ! [ "$__FV_DL_JN" = "$1" ]; then fv.dlg._jumpIdx "$1"; fi
    local __fvl_i=${__FV_DL_JUMP[$2]-} __fvl_f
    [[ -n $__fvl_i ]] || return 0
    local -n __fvl_ld=${1}_data
    __fvl_f=${__fvl_ld[Focused]:-0}
    if [ "${__DLFV_FIRST[__fvl_f]-}" = "$2" ]; then
        if [[ -n ${__DLFV_NEXT[__fvl_f]-} ]]; then __fvl_i=${__DLFV_NEXT[__fvl_f]}; fi
    else
        while [[ -n $__fvl_i ]] && (( __fvl_i < __fvl_f )); do __fvl_i=${__DLFV_NEXT[__fvl_i]-}; done
        if [[ -z $__fvl_i ]]; then __fvl_i=${__FV_DL_JUMP[$2]}; fi
    fi
    fv.views.listFocusItem "$1" "$__fvl_i" || :
    return 0
}
# TDlgList.SelectItem ITEM (design §5.1, M8) — see the class
fv.dlg._lsSelect() {
    local __fvl_i=${2-} __fvl_k __fvl_o=-1
    case ${__FV_DL_KIND[$1]-} in
        checklist) fv.views._lvSelectItem "$@"; return 0 ;;
        menu) fv.views.endModal "$1" cmOK || :; return 0 ;;
    esac
    if [[ -z $__fvl_i || $__fvl_i == *[!0123456789]* || ${#__fvl_i} -gt 9 ]]; then return 0; fi
    __fvl_i=$(( 10#$__fvl_i ))
    for __fvl_k in "${!__DLFV_MARKS[@]}"; do __fvl_o=$__fvl_k; done
    if (( __fvl_o != __fvl_i )); then
        __DLFV_MARKS=()
        __DLFV_MARKS[__fvl_i]=1
        if (( __fvl_o >= 0 )); then fv.views.listDrawItem "$1" "$__fvl_o" || :; fi
    fi
    # (the item's row: the key handler's FocusItem repaints it next — the
    # built-in SelectItem's own rule, fv.views._lvSel)
    if [ "${__fvw_lvsk-}" = "$1:$__fvl_i" ]; then __fvw_lvsk=1
    elif (( __fvl_o != __fvl_i )); then fv.views.listDrawItem "$1" "$__fvl_i" || :; fi
    local -n __fvl_ld=${1}_data
    if [[ -n ${__fvl_ld[Owner]-} && -n ${__FV_VW_LIVE[${__fvl_ld[Owner]}]-} ]]; then fv.views._message "${__fvl_ld[Owner]}" evBroadcast cmListItemSelected "$1" || :; fi
    return 0
}

# TDlgText.GetPalette (func): every row the dialog's static text colour
fv.dlg._txPal() { RESULT='6 6 6 6 6'; }
# fv.dlg._txSide V STEP — Left / Right on the text view V (TDlgText's
# HandleEvent): the textbox's column offset moved by STEP cells, at most
# what brings the widest line's end into view, V redrawn when it moved, the
# key consumed; other text (no Formatter list): the key left alone
fv.dlg._txSide() {
    local -n __fvl_sd=${1}_data
    [ "${__fvl_sd[List]-}" = __DLFV_RAW ] || return 0
    local __fvl_t=$(( __FV_DL_TXX + $2 )) __fvl_m=$(( __FV_DL_TXW - ${__fvl_sd[SizeX]:-1} + 1 ))
    if (( __fvl_t > __fvl_m )); then __fvl_t=$__fvl_m; fi
    if (( __fvl_t < 0 )); then __fvl_t=0; fi
    if (( __fvl_t != __FV_DL_TXX )); then __FV_DL_TXX=$__fvl_t; fv.views.drawView "$1" || :; fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# TDlgText.HandleEvent: the keys scroll the top row (Left / Right: the
# textbox's column, fv.dlg._txSide); the rest TListViewer's
fv.dlg._txEvent() {
    if ! [ "$FV_EV_WHAT" = evKeyDown ]; then fv.views._lvEvent "$1"; return 0; fi
    local -n __fvl_xd=${1}_data
    local __fvl_t=${__fvl_xd[TopItem]:-0} __fvl_h=${__fvl_xd[SizeY]:-1} __fvl_m __fvl_k=${__FV_VW_C2A[${FV_EV_KEY:-kbNoKey}]-$FV_EV_KEY}
    __fvl_m=$(( ${__fvl_xd[Range]:-0} - __fvl_h ))
    if (( __fvl_m < 0 )); then __fvl_m=0; fi
    case $__fvl_k in
        kbLeft) fv.dlg._txSide "$1" -1; return 0 ;;
        kbRight) fv.dlg._txSide "$1" 1; return 0 ;;
        kbDown) __fvl_t=$(( __fvl_t + 1 )) ;;
        kbUp) __fvl_t=$(( __fvl_t - 1 )) ;;
        kbPgDn) __fvl_t=$(( __fvl_t + __fvl_h )) ;;
        kbPgUp) __fvl_t=$(( __fvl_t - __fvl_h )) ;;
        kbHome) __fvl_t=0 ;;
        kbEnd) __fvl_t=$__fvl_m ;;
        *) return 0 ;;
    esac
    if (( __fvl_t > __fvl_m )); then __fvl_t=$__fvl_m; fi
    if (( __fvl_t < 0 )); then __fvl_t=0; fi
    __fvl_xd[Focused]=$__fvl_t
    fv.views.listSetTopItem "$1" "$__fvl_t" || :
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
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
# clips the long labels to 6 cells, so the refusal names the geometric need.
# Two buttons when the caller's __fvl_n2 is 1 (an empty label is a button)
fv.dlg._fitLabels() {
    local __fvl_a __fvl_b1 __fvl_b2 __fvl_m1=0 __fvl_m2=0 __fvl_h
    fv.dlg._bw "$__fvl_l1"; __fvl_b1=$RESULT
    if (( __fvl_n2 )); then
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

# fv.dlg._geom W H — the height split of a W x H dialog (design §5.3, P4-8;
# the same for the build and a resize) from the caller's record: __fvl_t
# (the text), __fvl_w (the widget), __fvl_ex (the rows around the text),
# __fvl_list / __fvl_lhw (LH: 0 = every item) / __fvl_n (the items),
# __fvl_st (--scrolltext on a msgbox / yesno); __fvl_fw = the width the
# text was last fitted at (fv.dlg._fit runs only for a new one). Sets the
# caller's __fvl_tw / __fvl_th (the text fitted at W - 4), __fvl_ta (the
# text's rows), __fvl_lh (the list's rows), __fvl_bar (the list's bar:
# fewer rows than items), __fvl_sc (the text scrolls: more rows than it
# has, or --scrolltext), __fvl_vh (the scrolling view's rows: a msgbox /
# yesno keeps a blank row above the buttons). A list takes every row the
# text does not need (L7: an explicit H or -1 gives its spare rows to the
# list, as dialog does); when both do not fit, the text gets at most half
# of the room (one row at least) and the list the rest, up to LH
fv.dlg._geom() {
    local __fvl_room __fvl_x=$(( $1 - 4 > 1 ? $1 - 4 : 1 ))
    if ! [ "$__fvl_fw" = "$__fvl_x" ]; then fv.dlg._fitT "$__fvl_t" "$__fvl_x"; __fvl_fw=$__fvl_x; fi
    __fvl_lh=0 __fvl_bar=0 __fvl_sc=0
    if (( __fvl_list )); then
        __fvl_room=$(( $2 - __fvl_ex ))
        if (( __fvl_th + __fvl_lhw <= __fvl_room )); then __fvl_lh=$(( __fvl_room - __fvl_th ))
        else
            __fvl_ta=$(( __fvl_room / 2 ))
            if (( __fvl_ta > __fvl_th )); then __fvl_ta=$__fvl_th; fi
            if (( __fvl_ta < 1 )); then __fvl_ta=1; fi
            __fvl_lh=$(( __fvl_room - __fvl_ta ))
            if (( __fvl_lh > __fvl_lhw )); then __fvl_lh=$__fvl_lhw; fi
        fi
        __fvl_ta=$(( __fvl_room - __fvl_lh ))
        if (( __fvl_lh < __fvl_n )); then __fvl_bar=1; fi
    elif [ "$__fvl_w" = infobox ]; then __fvl_ta=$(( $2 - 2 ))
    elif [ "$__fvl_w" = gauge ]; then __fvl_ta=$(( $2 - 4 ))
    else __fvl_ta=$(( $2 - __fvl_ex + 1 )); fi
    # (the infobox and the gauge never scroll: no keys reach a text there —
    # what does not fit is cut, as TStaticText cuts)
    if { (( __fvl_th > __fvl_ta )) && ! [ "$__fvl_w" = infobox ] && ! [ "$__fvl_w" = gauge ]; } || (( __fvl_st )); then __fvl_sc=1; fi
    __fvl_vh=$__fvl_ta
    if [ "$__fvl_w" = msgbox ] || [ "$__fvl_w" = yesno ] || [ "$__fvl_w" = textbox ]; then __fvl_vh=$(( __fvl_ta > 1 ? __fvl_ta - 1 : 1 )); fi
}

# fv.dlg._ins D V TARGET — V into the dialog D: in front of everything
# (TARGET '-'), else directly in front of TARGET ('' = behind everything:
# fv.views.insertBefore)
fv.dlg._ins() {
    if [ "$3" = - ]; then fv.views.insert "$1" "$2" || :; else fv.views.insertBefore "$1" "$2" "$3" || :; fi
}

# fv.dlg._mkText D W TARGET [QUIET] — the text view of the W-wide dialog D from the
# caller's __fvl_t / __fvl_sc / __fvl_ta / __fvl_vh / __fvl_list: a
# TStaticText of __fvl_ta rows from column 2, or the scrolling view
# (TDlgText, __fvl_vh rows from column 1, the text wrapped at W - 5 into
# __DLFV_TEXT; its bar right of it when the rows do not fit); inserted by
# fv.dlg._ins (TARGET). The caller's __fvl_tx = the text view, __fvl_tv =
# the TDlgText ('' none), __fvl_txb = its bar ('' none)
fv.dlg._mkText() {
    local __fvl_g=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    local -a __fvl_wl=()
    if (( __fvl_list )); then __fvl_g=$FV_GF_GROWHIX; fi
    __fvl_tv='' __fvl_txb=''
    if (( ! __fvl_sc )); then
        fv.views._newReserved "$1" text TStaticText 2 1 "$(( $2 - 2 ))" "$(( 1 + __fvl_ta ))" "$__fvl_t" || :
        __fvl_tx=$RESULT
        printf -v "${__fvl_tx}_data[GrowMode]" '%d' "$__fvl_g"
        fv.dlg._ins "$1" "$__fvl_tx" "$3"
        return 0
    fi
    # (the textbox: the file's lines as they are, no wrap — its formatter
    # shows them from the column offset Left / Right move, as whiptail /
    # dialog scroll a text box sideways; a draw formats the visible rows
    # only, so a big file costs its load, not a walk over its words)
    local __fvl_ln=__DLFV_TEXT __fvl_fm=''
    if [ "${__fvl_w-}" = textbox ]; then __fvl_ln=__DLFV_RAW __fvl_fm=fv.dlg._txFmt
    else
        fv.dlg._wrap "$__fvl_t" "$(( $2 - 5 > 1 ? $2 - 5 : 1 ))"
        __DLFV_TEXT=("${__fvl_wl[@]}")
    fi
    local -n __fvl_la=$__fvl_ln
    if (( ${#__fvl_la[@]} > __fvl_vh )); then
        fv.views._newReserved "$1" textbar TScrollBar "$(( $2 - 3 ))" 1 "$(( $2 - 2 ))" "$(( 1 + __fvl_vh ))" || :
        __fvl_txb=$RESULT
        if (( __fvl_list )); then printf -v "${__fvl_txb}_data[GrowMode]" '%d' "$(( FV_GF_GROWLOX | FV_GF_GROWHIX ))"; fi
        fv.dlg._ins "$1" "$__fvl_txb" "$3"
    fi
    fv.views._newReserved "$1" text TDlgText 1 1 "$(( $2 - 3 ))" "$(( 1 + __fvl_vh ))" 1 '' "$__fvl_txb" || :
    __fvl_tv=$RESULT __fvl_tx=$RESULT
    printf -v "${__fvl_tv}_data[GrowMode]" '%d' "$__fvl_g"
    printf -v "${__fvl_tv}_data[List]" '%s' "$__fvl_ln"
    printf -v "${__fvl_tv}_data[Formatter]" '%s' "$__fvl_fm"
    fv.views.listSetRange "$__fvl_tv" "${#__fvl_la[@]}" || :
    # (a resize, QUIET: inserted while not selectable — FV's Show would
    # reset the dialog's current view, and a focused input line selects all
    # its text when it is focused again)
    local -n __fvl_xo=${__fvl_tv}_data
    if (( ${4:-0} )); then __fvl_xo[Options]=$(( ${__fvl_xo[Options]:-0} & ~FV_OF_SELECTABLE )); fi
    if [[ -n $__fvl_txb ]] && ! [ "$3" = - ]; then fv.dlg._ins "$1" "$__fvl_tv" "$__fvl_txb"; else fv.dlg._ins "$1" "$__fvl_tv" "$3"; fi
    if (( ${4:-0} )); then __fvl_xo[Options]=$(( ${__fvl_xo[Options]:-0} | FV_OF_SELECTABLE )); fi
}

# fv.dlg._unsel V — V's ofSelectable cleared: inserted or deleted, it
# leaves its group's current view alone (FV's Show / Hide reset it only for
# a selectable view)
fv.dlg._unsel() {
    local -n __fvl_uo=${1}_data
    __fvl_uo[Options]=$(( ${__fvl_uo[Options]:-0} & ~FV_OF_SELECTABLE ))
}
# fv.dlg._focus0 — RESULT = the control a fresh build focuses (the layout
# record __FV_DL_LAY): the input line (INIT selected: the first key
# replaces it), the list, the scrolling text (its keys scroll; Enter still
# presses the default button), else the default button
fv.dlg._focus0() {
    RESULT=${__FV_DL_LAY[il]-}
    [[ -n $RESULT ]] || RESULT=${__FV_DL_LAY[lb]-}
    [[ -n $RESULT ]] || RESULT=${__FV_DL_LAY[tv]-}
    if [[ -z $RESULT ]]; then
        if [ "${__FV_DL_LAY[df]-1}" = 2 ]; then RESULT=${__FV_DL_LAY[b2]-}; else RESULT=${__FV_DL_LAY[b1]-}; fi
    fi
}

# fv.dlg._build — the dialog of the caller's call record on the live
# application's desktop (the caller's __fvl_*): the size (P4-8, design §5.3),
# the frame and title, the text (a TStaticText; a TDlgText when it does not
# fit, or with --scrolltext on a msgbox / yesno), the input line or the list
# (+ its bar when the items do not fit), the buttons (an empty label is a
# blank button: L3); __fvl_d = the dialog, __fvl_il = the input line,
# __fvl_lb = the list. The caller's __fvl_top = 1 when a background title
# takes the desktop's row 0, __fvl_bt = the background title to make here
# ('' none: no title, or the session's). The layout record __FV_DL_LAY lets
# a resize lay the dialog out again (fv.dlg._relayout; GrowMode on the
# controls for a host's own resize). rc 1 with __fvl_err: the desktop is
# smaller than the widget's minimum
fv.dlg._build() {
    local __fvl_sw __fvl_sh __fvl_ex __fvl_minw __fvl_minh __fvl_bw __fvl_bh __fvl_tw=0 __fvl_th=0 __fvl_ta=0 __fvl_x __fvl_y
    local __fvl_hh=${__fvl_p[1]} __fvl_ww=${__fvl_p[2]} __fvl_l1='' __fvl_l2='' __fvl_c1='' __fvl_c2='' __fvl_n1=0 __fvl_n2=0 __fvl_w1=0 __fvl_w2=0 __fvl_df=1 __fvl_pw
    local __fvl_list=0 __fvl_lh=0 __fvl_lhw=0 __fvl_n=0 __fvl_rw=0 __fvl_di=0 __fvl_bar=0 __fvl_sc=0 __fvl_vh=0 __fvl_st=0 __fvl_fw=''
    local __fvl_tv='' __fvl_tx='' __fvl_txb='' __fvl_role=dlg __fvl_k=1 __fvl_sb='' __fvl_gv=''
    local -n __fvl_ad=${FV_DESKTOP}_data
    if [[ -z ${__FV_VW_IMPL[TDlgList.HandleEvent]-} ]]; then fv.dlg._register; fi
    __fvl_sw=${__fvl_ad[SizeX]:-80} __fvl_sh=${__fvl_ad[SizeY]:-24}
    if [[ $__fvl_hh == -* ]]; then __fvl_hh=-1; else __fvl_hh=$(( 10#$__fvl_hh )); fi
    if [[ $__fvl_ww == -* ]]; then __fvl_ww=-1; else __fvl_ww=$(( 10#$__fvl_ww )); fi
    __fvl_sh=$(( __fvl_sh - __fvl_top ))
    # the buttons: labels, commands (Cancel / No send cmNo, P4-4); rows
    # around the text: frame + blank + buttons (2) + frame; the input line
    # adds itself and a blank; a list its rows and two blanks; the infobox
    # only its frame
    __fvl_ex=2
    if [ "$__fvl_w" = msgbox ] || [ "$__fvl_w" = textbox ]; then
        __fvl_l1=${__fvl_o[ok]-O~K~} __fvl_c1=cmOK __fvl_n1=1 __fvl_ex=5
    elif [ "$__fvl_w" = gauge ]; then
        # (frame, the text, a blank, the meter, frame; no button)
        __fvl_ex=4
    elif [ "$__fvl_w" = yesno ]; then
        __fvl_l1=${__fvl_o[yes]-~Y~es} __fvl_c1=cmYes __fvl_l2=${__fvl_o[no]-~N~o} __fvl_c2=cmNo __fvl_n1=1 __fvl_n2=1 __fvl_ex=5
        if [[ -n ${__fvl_o[defaultno]-} ]]; then __fvl_df=2; fi
    elif ! [ "$__fvl_w" = infobox ]; then
        __fvl_l1=${__fvl_o[ok]-O~K~} __fvl_c1=cmOK __fvl_l2=${__fvl_o[cancel]-Cancel} __fvl_c2=cmNo __fvl_n1=1 __fvl_n2=1 __fvl_ex=7
        if [[ -n ${__fvl_o[nocancel]-} ]]; then __fvl_l2='' __fvl_n2=0; fi
        if ! [ "$__fvl_w" = inputbox ] && ! [ "$__fvl_w" = passwordbox ]; then __fvl_list=1 __fvl_ex=6; fi
    fi
    if [[ -n ${__fvl_o[scrolltext]-} ]] && { [ "$__fvl_w" = msgbox ] || [ "$__fvl_w" = yesno ]; }; then __fvl_st=1; fi
    # (the textbox: always the scrolling view — its keys page the file)
    if [ "$__fvl_w" = textbox ]; then __fvl_st=1; fi
    __fvl_minw=16 __fvl_pw=0
    if (( __fvl_n1 )); then
        # (labels wider than the screen allows are clipped: text never
        # makes the minimum exceed the screen)
        fv.dlg._fitLabels
        fv.dlg._bw "$__fvl_l1"; __fvl_w1=$RESULT
        if (( __fvl_n2 )); then fv.dlg._bw "$__fvl_l2"; __fvl_w2=$RESULT; fi
        __fvl_x=$(( __fvl_w1 + 4 ))
        if (( __fvl_w2 )); then __fvl_x=$(( __fvl_x + __fvl_w2 + 2 )); fi
        if (( __fvl_x > __fvl_minw )); then __fvl_minw=$__fvl_x; fi
    fi
    # the title: the preferred (auto) width only, at most the screen; the
    # frame cuts a longer one. FV TFrame's room for it is W - 10, minus 6
    # for the close icon (a TDialog's wfClose): W = the title + 16 shows it
    # whole (+ 12 left a short title no room in a 16-wide box: dropped)
    if [[ -n ${__fvl_o[title]-} ]]; then
        fv.dlg._cw "${__fvl_o[title]}"
        __fvl_pw=$(( RESULT + 16 > __fvl_sw ? __fvl_sw : RESULT + 16 ))
    fi
    # the minimum (P4-8): the buttons across (+ the frame and a blank each
    # side; 16 for the frame's icon and a title), down: one text row, the
    # input line or one list row, the blanks, the buttons and the frame —
    # msgbox / yesno 5, inputbox / passwordbox 7, the lists 8, the infobox 3
    # (+ the background title's row); a desktop below it is refused, a
    # smaller H / W grown to it
    __fvl_minh=$__fvl_ex
    if [ "$__fvl_w" = infobox ]; then __fvl_minh=3; elif (( __fvl_list )); then __fvl_minh=8; elif [ "$__fvl_w" = gauge ]; then __fvl_minh=5; fi
    if (( __fvl_minw > __fvl_sw || __fvl_minh > __fvl_sh )); then
        __fvl_x="terminal too small"
        if [ "${__fvl_mode-own}" = host ]; then __fvl_x="the desktop is too small"; fi
        __fvl_err="$__fvl_x (need ${__fvl_minw}x$(( __fvl_minh + __fvl_top )), have ${__fvl_ad[SizeX]:-0}x${__fvl_ad[SizeY]:-0})"
        return 1
    fi
    # the list's rows (their widest, with the mark), its default item
    if (( __fvl_list )); then
        fv.dlg._items
        __fvl_n=${#__DLFV_TAGS[@]} __fvl_lhw=$(( 10#${__fvl_p[3]} ))
        if (( __fvl_lhw == 0 || __fvl_lhw > __fvl_n )); then __fvl_lhw=$__fvl_n; fi
    fi
    # the width: -1 the desktop, a number clamped, 0 the fit (the text at
    # most 2/3 of the desktop, the list's widest row + its margins and the
    # bar, at least the title and the buttons)
    if (( __fvl_ww < 0 )); then __fvl_bw=$__fvl_sw
    elif (( __fvl_ww > 0 )); then __fvl_bw=$(( __fvl_ww > __fvl_sw ? __fvl_sw : __fvl_ww ))
    else
        __fvl_x=$(( __fvl_sw * 2 / 3 ))
        if (( __fvl_x < 10 )); then __fvl_x=10; fi
        fv.dlg._fitT "$__fvl_t" "$__fvl_x"
        __fvl_fw=$__fvl_x
        __fvl_bw=$(( __fvl_tw + 4 ))
        # (the textbox: the scrolling view wraps at W - 5 — the widest line
        # fits; the gauge: a meter of 35 cells at least, the screen allowing)
        if [ "$__fvl_w" = textbox ]; then __fvl_bw=$(( __fvl_tw + 5 )); fi
        if [ "$__fvl_w" = gauge ] && (( __fvl_bw < 40 )); then __fvl_bw=40; fi
        if (( __fvl_list )); then
            __fvl_x=$(( __fvl_rw + 6 + (__fvl_lhw < __fvl_n ? 1 : 0) ))
            if (( __fvl_bw < __fvl_x )); then __fvl_bw=$__fvl_x; fi
        fi
        if (( __fvl_bw < __fvl_pw )); then __fvl_bw=$__fvl_pw; fi
        if (( __fvl_bw > __fvl_sw )); then __fvl_bw=$__fvl_sw; fi
    fi
    if (( __fvl_bw < __fvl_minw )); then __fvl_bw=$__fvl_minw; fi
    # the height: -1 the desktop, a number clamped, 0 the fit (the text's
    # rows at this width, the list's LH rows); the split: fv.dlg._geom
    if ! [ "$__fvl_fw" = "$(( __fvl_bw - 4 > 1 ? __fvl_bw - 4 : 1 ))" ]; then
        __fvl_fw=$(( __fvl_bw - 4 > 1 ? __fvl_bw - 4 : 1 ))
        fv.dlg._fitT "$__fvl_t" "$__fvl_fw"
    fi
    if (( __fvl_list )); then __fvl_x=$(( __fvl_th + __fvl_lhw + __fvl_ex )); else __fvl_x=$(( __fvl_th + __fvl_ex )); fi
    if (( __fvl_hh < 0 )); then __fvl_bh=$__fvl_sh
    elif (( __fvl_hh > 0 )); then __fvl_bh=$(( __fvl_hh > __fvl_sh ? __fvl_sh : __fvl_hh ))
    else __fvl_bh=$(( __fvl_x > __fvl_sh ? __fvl_sh : __fvl_x )); fi
    if (( __fvl_bh < __fvl_minh )); then __fvl_bh=$__fvl_minh; fi
    fv.dlg._geom "$__fvl_bw" "$__fvl_bh"
    # (an auto width gets the list bar's column when the screen has it; the
    # split again at the new width)
    if (( __fvl_bar && __fvl_ww == 0 && __fvl_bw < __fvl_rw + 7 && __fvl_bw < __fvl_sw )); then
        __fvl_bw=$(( __fvl_rw + 7 > __fvl_sw ? __fvl_sw : __fvl_rw + 7 ))
        fv.dlg._geom "$__fvl_bw" "$__fvl_bh"
    fi
    if [[ -n ${__fvl_o[topleft]-} ]]; then __fvl_x=0 __fvl_y=$__fvl_top
    else __fvl_x=$(( (__fvl_sw - __fvl_bw) / 2 )) __fvl_y=$(( __fvl_top + (__fvl_sh - __fvl_bh) / 2 )); fi
    if [[ -n $__fvl_bt ]]; then
        fv.views._newReserved "$FV_DESKTOP" backtitle TDlgTitle 0 0 "$__fvl_sw" 1 || :
        printf -v "${RESULT}_data[Text]" '%s' "$__fvl_bt"
        printf -v "${RESULT}_data[GrowMode]" '%d' "$FV_GF_GROWHIX"
        fv.views.insert "$FV_DESKTOP" "$RESULT" || :
    fi
    # (a free name: the family __fvdlg, __fvdlg2, ... as fv.msgbox's)
    while [[ -n ${__FV_VW_LIVE[${FV_DESKTOP}__fv$__fvl_role]-} ]]; do __fvl_k=$(( __fvl_k + 1 )) __fvl_role=dlg$__fvl_k; done
    fv.views._newReserved "$FV_DESKTOP" "$__fvl_role" TDialog "$__fvl_x" "$__fvl_y" "$(( __fvl_x + __fvl_bw ))" "$(( __fvl_y + __fvl_bh ))" "${__fvl_o[title]-}" || {
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
    # the text: static when it fits (as 4a-1), else the scrolling view
    fv.dlg._mkText "$__fvl_d" "$__fvl_bw" -
    if [ "$__fvl_w" = inputbox ] || [ "$__fvl_w" = passwordbox ]; then
        fv.views._newReserved "$__fvl_d" input TInputLine 2 "$(( __fvl_bh - 5 ))" "$(( __fvl_bw - 2 ))" "$(( __fvl_bh - 4 ))" 1024 || :
        __fvl_il=$RESULT
        printf -v "${__fvl_il}_data[GrowMode]" '%d' "$(( FV_GF_GROWLOY | FV_GF_GROWHIY | FV_GF_GROWHIX ))"
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
    if (( __fvl_list )); then
        # the list: from the dialog's column 2, the rows below the text and
        # a blank; the bar (when the items do not fit) right of it
        __fvl_y=$(( __fvl_ta + 2 )) __fvl_sb=''
        if (( __fvl_bar )); then
            fv.views._newReserved "$__fvl_d" listbar TScrollBar "$(( __fvl_bw - 3 ))" "$__fvl_y" "$(( __fvl_bw - 2 ))" "$(( __fvl_y + __fvl_lh ))" || :
            __fvl_sb=$RESULT
            fv.views.insert "$__fvl_d" "$__fvl_sb" || :
        fi
        fv.views._newReserved "$__fvl_d" list TDlgList 2 "$__fvl_y" "$(( __fvl_bw - 2 - __fvl_bar ))" "$(( __fvl_y + __fvl_lh ))" 1 "$__fvl_sb" || :
        __fvl_lb=$RESULT
        __FV_DL_KIND[$__fvl_lb]=$__fvl_w
        printf -v "${__fvl_lb}_data[GrowMode]" '%d' "$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))"
        case $__fvl_w in
            menu) fv.dialogs.newList "$__fvl_lb" __DLFV_ROWS || : ;;
            checklist) fv.dialogs.newList "$__fvl_lb" __DLFV_ROWS fv.dlg._fmtC || : ;;
            radiolist) fv.dialogs.newList "$__fvl_lb" __DLFV_ROWS fv.dlg._fmtR || : ;;
        esac
        if ! [ "$__fvl_w" = menu ]; then printf -v "${__fvl_lb}_data[Marks]" '%s' __DLFV_MARKS; fi
        if (( __fvl_di )); then fv.views.listFocusItem "$__fvl_lb" "$__fvl_di" || :; fi
        fv.views.insert "$__fvl_d" "$__fvl_lb" || :
    fi
    if [ "$__fvl_w" = gauge ]; then
        # the meter: the row above the frame, from column 2; PERCENT clamped
        fv.views._newReserved "$__fvl_d" gauge TDlgGauge 2 "$(( __fvl_bh - 2 ))" "$(( __fvl_bw - 2 ))" "$(( __fvl_bh - 1 ))" || :
        __fvl_gv=$RESULT
        fv.dlg._pct "${__fvl_p[3]:-0}" || RESULT=0
        printf -v "${__fvl_gv}_data[Pct]" '%s' "$RESULT"
        printf -v "${__fvl_gv}_data[GrowMode]" '%d' "$(( FV_GF_GROWLOY | FV_GF_GROWHIY | FV_GF_GROWHIX ))"
        fv.views.insert "$__fvl_d" "$__fvl_gv" || :
    fi
    if (( __fvl_n1 )); then
        __fvl_x=$(( (__fvl_bw - __fvl_w1 - (__fvl_w2 ? __fvl_w2 + 2 : 0)) / 2 ))
        fv.dlg._btn "$__fvl_d" b1 "$__fvl_x" "$(( __fvl_bh - 3 ))" "$__fvl_l1" "$__fvl_c1" "$(( __fvl_df == 1 ? FV_BF_DEFAULT : FV_BF_NORMAL ))" || :
        __fvl_b1=$RESULT
        if (( __fvl_n2 )); then
            fv.dlg._btn "$__fvl_d" b2 "$(( __fvl_x + __fvl_w1 + 2 ))" "$(( __fvl_bh - 3 ))" "$__fvl_l2" "$__fvl_c2" "$(( __fvl_df == 2 ? FV_BF_DEFAULT : FV_BF_NORMAL ))" || :
            __fvl_b2=$RESULT
        fi
    fi
    __FV_DL_LAY=([d]=$__fvl_d [hh]=$__fvl_hh [ww]=$__fvl_ww [pw]=$__fvl_bw [ph]=$__fvl_bh [minw]=$__fvl_minw [minh]=$__fvl_minh
        [top]=$__fvl_top [tl]=${__fvl_o[topleft]-} [b1]=$__fvl_b1 [b2]=$__fvl_b2 [w1]=$__fvl_w1 [w2]=$__fvl_w2 [df]=$__fvl_df
        [w]=$__fvl_w [ex]=$__fvl_ex [list]=$__fvl_list [lhw]=$__fvl_lhw [n]=$__fvl_n [st]=$__fvl_st
        [il]=$__fvl_il [lb]=$__fvl_lb [sb]=$__fvl_sb [tx]=$__fvl_tx [txb]=$__fvl_txb [tv]=$__fvl_tv [text]=$__fvl_t [gv]=$__fvl_gv)
    # the focus (fv.dlg._focus0); the input line's INIT after it (selected)
    fv.dlg._focus0
    if [[ -n $RESULT ]]; then fv.views.select "$RESULT" || :; fi
    if [[ -n $__fvl_il ]]; then fv.dialogs.setText "$__fvl_il" "${__fvl_p[3]-}" || :; fi
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

# ---- the resize ---------------------------------------------------------------------

# TDlgApp.HandleEvent — TApplication's (fv.app's body: the screen, the
# application and the desktop resized and redrawn), then after a
# cmResizeApp the running dialog laid out again (fv.dlg._relayout)
fv.dlg._appEvent() {
    local __fvl_rz=0
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmResizeApp ]; then __fvl_rz=1; fi
    fv.app._appEvent "$1"
    if (( __fvl_rz )); then fv.dlg._relayout; fi
    return 0
}
# fv.dlg._relayout — P4-8 / design §3.5 after a resize: the desktop below
# the dialog's minimum ends it (cmCancel; __FV_DL_SMALL holds the message,
# the call answers 255 and prints it after the restore); else the dialog
# takes its size again (-1: the desktop; a number or the fit: as built, at
# most the desktop, at least the minimum), centred (--topleft: the corner).
# A new size lays the controls out as a build at that size would (H1,
# fv.dlg._geom): the text view made again in its place (static when it
# fits, else the scrolling view wrapped at the new width, its bar when its
# rows do not fit), the input line moved, the list moved to its rows (its
# bar made or dropped; the focused item kept in view, no blank rows below
# the last item while items are above), the buttons centred on their row.
# The focus stays where the user put it; the text's own focus follows the
# text (a scrolling text that goes static gives the focus to the control a
# build would focus; a msgbox / yesno whose text starts to scroll focuses
# it when the default button had the focus, as a build would). Every
# control keeps one row at least: the minimum guarantees it
fv.dlg._relayout() {
    local __fvl_d=${__FV_DL_LAY[d]-} __fvl_sw __fvl_sh __fvl_tp=${__FV_DL_LAY[top]:-0} __fvl_bw __fvl_bh __fvl_x __fvl_y __fvl_b __fvl_bx
    [[ -n $__fvl_d && -n ${__FV_VW_LIVE[$__fvl_d]-} && -n $FV_DESKTOP ]] || return 0
    local -n __fvl_kd=${FV_DESKTOP}_data __fvl_dd=${__fvl_d}_data
    __fvl_sw=${__fvl_kd[SizeX]:-0} __fvl_sh=$(( ${__fvl_kd[SizeY]:-0} - __fvl_tp ))
    if (( __FV_DL_LAY[minw] > __fvl_sw || __FV_DL_LAY[minh] > __fvl_sh )); then
        __FV_DL_SMALL="terminal too small (need ${__FV_DL_LAY[minw]}x$(( __FV_DL_LAY[minh] + __fvl_tp )), have ${__fvl_kd[SizeX]:-0}x${__fvl_kd[SizeY]:-0})"
        fv.views.endModal "$__fvl_d" cmCancel || :
        return 0
    fi
    if (( __FV_DL_LAY[ww] < 0 )); then __fvl_bw=$__fvl_sw; else __fvl_bw=$(( __FV_DL_LAY[pw] > __fvl_sw ? __fvl_sw : __FV_DL_LAY[pw] )); fi
    if (( __FV_DL_LAY[hh] < 0 )); then __fvl_bh=$__fvl_sh; else __fvl_bh=$(( __FV_DL_LAY[ph] > __fvl_sh ? __fvl_sh : __FV_DL_LAY[ph] )); fi
    if (( __fvl_bw < __FV_DL_LAY[minw] )); then __fvl_bw=${__FV_DL_LAY[minw]}; fi
    if (( __fvl_bh < __FV_DL_LAY[minh] )); then __fvl_bh=${__FV_DL_LAY[minh]}; fi
    if [[ -n ${__FV_DL_LAY[tl]-} ]]; then __fvl_x=0 __fvl_y=$__fvl_tp
    else __fvl_x=$(( (__fvl_sw - __fvl_bw) / 2 )) __fvl_y=$(( __fvl_tp + (__fvl_sh - __fvl_bh) / 2 )); fi
    # (the same size: only moved)
    __fvl_b=0
    if (( __fvl_bw == ${__fvl_dd[SizeX]:-0} && __fvl_bh == ${__fvl_dd[SizeY]:-0} )); then __fvl_b=1; fi
    fv.views.locate "$__fvl_d" "$__fvl_x" "$__fvl_y" "$(( __fvl_x + __fvl_bw ))" "$(( __fvl_y + __fvl_bh ))" || :
    (( ! __fvl_b )) || return 0
    # the record fv.dlg._geom / _mkText read
    local __fvl_t=${__FV_DL_LAY[text]-} __fvl_w=${__FV_DL_LAY[w]-} __fvl_ex=${__FV_DL_LAY[ex]:-5} __fvl_list=${__FV_DL_LAY[list]:-0}
    local __fvl_lhw=${__FV_DL_LAY[lhw]:-0} __fvl_n=${__FV_DL_LAY[n]:-0} __fvl_st=${__FV_DL_LAY[st]:-0} __fvl_fw=''
    local __fvl_tw=0 __fvl_th=0 __fvl_ta=0 __fvl_lh=0 __fvl_bar=0 __fvl_sc=0 __fvl_vh=0 __fvl_tv='' __fvl_tx='' __fvl_txb=''
    local __fvl_c0=${__fvl_dd[Current]-} __fvl_otv=${__FV_DL_LAY[tv]-} __fvl_tg='' __fvl_i __fvl_v __fvl_lb=${__FV_DL_LAY[lb]-} __fvl_sb=${__FV_DL_LAY[sb]-}
    local -n __fvl_vl=${__fvl_d}_views
    fv.dlg._geom "$__fvl_bw" "$__fvl_bh"
    # the text view: the old one (and its bar) out, the new one in its place
    for (( __fvl_i = 0; __fvl_i < ${#__fvl_vl[@]}; __fvl_i++ )); do
        if [ "${__fvl_vl[__fvl_i]}" = "${__FV_DL_LAY[txb]-}" ] || [ "${__fvl_vl[__fvl_i]}" = "${__FV_DL_LAY[tx]-}" ]; then
            if (( __fvl_i > 0 )); then __fvl_tg=${__fvl_vl[__fvl_i-1]}; fi
            break
        fi
    done
    for __fvl_v in "${__FV_DL_LAY[tx]-}" "${__FV_DL_LAY[txb]-}"; do
        [[ -n $__fvl_v && -n ${__FV_VW_LIVE[$__fvl_v]-} ]] || continue
        # (one that is not the current view leaves the focus alone: not
        # selectable, its Hide resets nothing)
        if ! [ "$__fvl_v" = "$__fvl_c0" ]; then fv.dlg._unsel "$__fvl_v"; fi
        "$__fvl_v.delete"
    done
    fv.dlg._mkText "$__fvl_d" "$__fvl_bw" "$__fvl_tg" 1
    __FV_DL_LAY[tx]=$__fvl_tx __FV_DL_LAY[txb]=$__fvl_txb __FV_DL_LAY[tv]=$__fvl_tv
    if [[ -n ${__FV_DL_LAY[il]-} ]]; then
        fv.views.locate "${__FV_DL_LAY[il]}" 2 "$(( __fvl_bh - 5 ))" "$(( __fvl_bw - 2 ))" "$(( __fvl_bh - 4 ))" || :
    fi
    if [[ -n ${__FV_DL_LAY[gv]-} && -n ${__FV_VW_LIVE[${__FV_DL_LAY[gv]}]-} ]]; then
        fv.views.locate "${__FV_DL_LAY[gv]}" 2 "$(( __fvl_bh - 2 ))" "$(( __fvl_bw - 2 ))" "$(( __fvl_bh - 1 ))" || :
    fi
    if [[ -n $__fvl_lb && -n ${__FV_VW_LIVE[$__fvl_lb]-} ]]; then
        local -n __fvl_ld=${__fvl_lb}_data
        __fvl_y=$(( __fvl_ta + 2 ))
        if (( __fvl_bar )) && [[ -z $__fvl_sb ]]; then
            # (a bar made behind the list, linked to it; FV's SetRange gives
            # it its steps: the list's height record reset)
            fv.views._newReserved "$__fvl_d" listbar TScrollBar "$(( __fvl_bw - 3 ))" "$__fvl_y" "$(( __fvl_bw - 2 ))" "$(( __fvl_y + __fvl_lh ))" || :
            __fvl_sb=$RESULT __fvl_tg=''
            for (( __fvl_i = 0; __fvl_i < ${#__fvl_vl[@]}; __fvl_i++ )); do
                if [ "${__fvl_vl[__fvl_i]}" = "$__fvl_lb" ]; then
                    if (( __fvl_i > 0 )); then __fvl_tg=${__fvl_vl[__fvl_i-1]}; fi
                    break
                fi
            done
            fv.views.insertBefore "$__fvl_d" "$__fvl_sb" "$__fvl_tg" || :
            __fvl_ld[VScrollBar]=$__fvl_sb __FV_VW_LY[$__fvl_lb]=0
        elif (( ! __fvl_bar )) && [[ -n $__fvl_sb ]]; then
            __fvl_ld[VScrollBar]=''
            if [[ -n ${__FV_VW_LIVE[$__fvl_sb]-} ]]; then "$__fvl_sb.delete"; fi
            __fvl_sb=''
        fi
        __FV_DL_LAY[sb]=$__fvl_sb
        fv.views.locate "$__fvl_lb" 2 "$__fvl_y" "$(( __fvl_bw - 2 - __fvl_bar ))" "$(( __fvl_y + __fvl_lh ))" || :
        if [[ -n $__fvl_sb ]]; then fv.views.locate "$__fvl_sb" "$(( __fvl_bw - 3 ))" "$__fvl_y" "$(( __fvl_bw - 2 ))" "$(( __fvl_y + __fvl_lh ))" || :; fi
        fv.views.listSetRange "$__fvl_lb" "$__fvl_n" || :
        __fvl_i=$(( __fvl_n - __fvl_lh > 0 ? __fvl_n - __fvl_lh : 0 ))
        if (( ${__fvl_ld[TopItem]:-0} > __fvl_i )); then fv.views.listSetTopItem "$__fvl_lb" "$__fvl_i" || :; fi
        fv.views.listFocusItem "$__fvl_lb" "${__fvl_ld[Focused]:-0}" || :
    fi
    __fvl_bx=$(( (__fvl_bw - __FV_DL_LAY[w1] - (__FV_DL_LAY[w2] ? __FV_DL_LAY[w2] + 2 : 0)) / 2 ))
    for __fvl_b in "${__FV_DL_LAY[b1]-}" "${__FV_DL_LAY[b2]-}"; do
        [[ -n $__fvl_b && -n ${__FV_VW_LIVE[$__fvl_b]-} ]] || continue
        local -n __fvl_bd=${__fvl_b}_data
        fv.views.locate "$__fvl_b" "$__fvl_bx" "$(( __fvl_bh - 3 ))" "$(( __fvl_bx + __fvl_bd[SizeX] ))" "$(( __fvl_bh - 1 ))" || :
        __fvl_bx=$(( __fvl_bx + __FV_DL_LAY[w1] + 2 ))
    done
    # the focus: the user's stays (the text views went in and out while not
    # selectable); selected only when it changes — a focused input line selects all
    # its text when it is selected again
    __fvl_v=$__fvl_c0
    if [[ -n $__fvl_otv ]] && [ "$__fvl_c0" = "$__fvl_otv" ]; then
        if [[ -n $__fvl_tv ]]; then __fvl_v=$__fvl_tv; else fv.dlg._focus0; __fvl_v=$RESULT; fi
    elif [[ -n $__fvl_tv && -z ${__FV_DL_LAY[il]-} && -z $__fvl_lb ]]; then
        if [ "${__FV_DL_LAY[df]-1}" = 2 ]; then __fvl_b=${__FV_DL_LAY[b2]-}; else __fvl_b=${__FV_DL_LAY[b1]-}; fi
        if [ "$__fvl_c0" = "$__fvl_b" ]; then __fvl_v=$__fvl_tv; fi
    fi
    if [[ -z $__fvl_v || -z ${__FV_VW_LIVE[$__fvl_v]-} ]]; then fv.dlg._focus0; __fvl_v=$RESULT; fi
    if [[ -n $__fvl_v ]] && ! [ "$__fvl_v" = "${__fvl_dd[Current]-}" ]; then fv.views.select "$__fvl_v" || :; fi
    fv.views.drawView "$__fvl_d" || :
    return 0
}

# ---- the gauge and the textbox (4d) -----------------------------------------------

# fv.dlg._pct V — RESULT = V as a percentage: blanks / tabs around it
# allowed, an integer with an optional '-', clamped to 0..100 (a negative
# 0, more than 100 100); rc 1 (RESULT untouched) when V is not one
fv.dlg._pct() {
    local __fvl_v=$1 __fvl_b=$' \t' __fvl_m=0
    __fvl_v=${__fvl_v#"${__fvl_v%%[!$__fvl_b]*}"}
    __fvl_v=${__fvl_v%"${__fvl_v##*[!$__fvl_b]}"}
    if [[ $__fvl_v == -* ]]; then __fvl_m=1 __fvl_v=${__fvl_v:1}; fi
    [[ -n $__fvl_v && $__fvl_v != *[!0123456789]* ]] || return 1
    # (leading zeros dropped: more than three digits left is more than 100)
    __fvl_v=${__fvl_v#"${__fvl_v%%[!0]*}"}
    if (( __fvl_m )) || [[ -z $__fvl_v ]]; then RESULT=0
    elif (( ${#__fvl_v} > 3 || 10#$__fvl_v > 100 )); then RESULT=100
    else RESULT=$(( 10#$__fvl_v )); fi
}

# fv.dlg._gRun — the gauge's run (the caller's __fvl_d, __fvl_t; sets
# __fvl_cmd): the dialog on the desktop (inserted here, so execView leaves
# it there — a run that goes on without keys still shows it), its modal
# loop, where TDlgApp.Idle polls stdin (fv.dlg._appIdle) and stdin's end
# ends the dialog with cmOK; Esc / Ctrl+F4 / the close icon cmCancel (255,
# as the other boxes), a resize below the minimum as the other boxes. The
# keyboard's end of input (a headless key file that ran out; on a terminal
# it does not happen) does not end a gauge — it has no buttons: stdin is
# then read to its end with timed reads (fv.dlg._gPoll 1), each change
# shown, and the answer is cmOK
fv.dlg._gRun() {
    local -n __fvl_gd=${__FV_DL_LAY[gv]}_data __fvl_od=${__fvl_d}_data
    __FV_DL_G=([d]=$__fvl_d [pct]=${__fvl_gd[Pct]:-0} [spct]=${__fvl_gd[Pct]:-0} [text]=$__fvl_t [ntext]=0 [part]='' [skip]=0
        [blk]=0 [bpct]='' [btxt]='' [bn]=0 [eof]=0 [on]=1 [polls]=0 [shows]=0 [tshows]=0)
    if [[ -z ${__fvl_od[Owner]-} ]]; then fv.views.insert "$FV_DESKTOP" "$__fvl_d" || :; fi
    fv.views.execView "$FV_DESKTOP" "$__fvl_d" || :
    __fvl_cmd=${RESULT:-cmCancel}
    if ! [ "$__fvl_cmd" = cmOK ] && (( __FV_VW_EOF && ! __FV_DL_G[eof] )); then
        while (( ! __FV_DL_G[eof] )); do
            fv.dlg._gPoll 1
            fv.views._showNow
        done
    fi
    if (( __FV_DL_G[eof] )); then __fvl_cmd=cmOK; fi
    __FV_DL_G[on]=0
    return 0
}

# TDlgApp.Idle — TProgram's, then a running gauge's poll; stdin's end ends
# the gauge's dialog with cmOK. Paced by the event read: Idle runs after a
# read that waited FV_IDLE_TIMEOUT (0.05 s) with no key, so an idle gauge
# wakes 20 times a second for one `read -t 0` (no busy loop)
fv.dlg._appIdle() {
    fv.app._progIdle "$1" || :
    if (( ${__FV_DL_G[on]:-0} && ! ${__FV_DL_G[eof]:-0} )); then
        fv.dlg._gPoll 0
        if (( __FV_DL_G[eof] )) && [[ -n ${__FV_VW_LIVE[${__FV_DL_G[d]}]-} ]]; then fv.views.endModal "${__FV_DL_G[d]}" cmOK || :; fi
    fi
    return 0
}

# fv.dlg._gPoll BLIND — the gauge's stdin read (design §4.3, R7): up to 256
# lines per poll, then the changes shown (fv.dlg._gShow). BLIND 0 (Idle):
# a line is read only when something waits (`read -t 0`: nothing read; the
# end of stdin counts as waiting), with `read -t 0.01`; BLIND 1 (no keys
# left): `read -t 0.25` at once. A read that times out keeps what it got:
# the partial line is kept across polls (fv.keyboard's partial-read rule:
# a writer that flushes `4`, later `2\n`, gives 42); a partial line longer
# than 4096 characters is dropped up to its newline. The end of stdin (or
# a read error, taken for it): a last line without its newline counts, eof 1
fv.dlg._gPoll() {
    local __fvl_l __fvl_rc __fvl_n=0 __fvl_t=0.01
    if (( $1 )); then __fvl_t=0.25; fi
    __FV_DL_G[polls]=$(( ${__FV_DL_G[polls]:-0} + 1 ))
    while (( __fvl_n++ < 256 )); do
        if (( ! $1 )) && ! read -t 0 -u 0 2>/dev/null; then break; fi
        __fvl_l='' __fvl_rc=0
        IFS= read -r -t "$__fvl_t" -u 0 __fvl_l 2>/dev/null || __fvl_rc=$?
        if (( __fvl_rc > 128 )); then
            __FV_DL_G[part]+=$__fvl_l
            if (( ${#__FV_DL_G[part]} > 4096 )); then __FV_DL_G[part]='' __FV_DL_G[skip]=1; fi
            break
        fi
        __fvl_l=${__FV_DL_G[part]}$__fvl_l __FV_DL_G[part]=''
        if (( __FV_DL_G[skip] )); then
            __FV_DL_G[skip]=0 __fvl_l=''
            if (( ! __fvl_rc )); then continue; fi
        fi
        if (( __fvl_rc )); then
            if [[ -n $__fvl_l ]]; then fv.dlg._gLine "$__fvl_l"; fi
            __FV_DL_G[eof]=1
            break
        fi
        fv.dlg._gLine "$__fvl_l"
    done
    fv.dlg._gShow
}

# fv.dlg._gLine LINE — one line of the gauge's protocol (whiptail / dialog;
# a trailing CR dropped): a percentage (fv.dlg._pct) sets it; a line that
# starts with XXX opens a block — its next line the percentage (not a
# number: unchanged), the lines up to the next XXX line the new prompt
# (joined by newlines; `\n` escapes and --colors as TEXT's: fv.dlg._text),
# both taken at the closing XXX (a block stdin ends inside is dropped);
# any other line is ignored
fv.dlg._gLine() {
    local __fvl_l=${1%$'\r'}
    case ${__FV_DL_G[blk]:-0} in
        1)
            __FV_DL_G[bpct]=''
            if fv.dlg._pct "$__fvl_l"; then __FV_DL_G[bpct]=$RESULT; fi
            __FV_DL_G[blk]=2 __FV_DL_G[btxt]='' __FV_DL_G[bn]=0 ;;
        2)
            if [[ $__fvl_l == XXX* ]]; then
                __FV_DL_G[blk]=0
                if [[ -n ${__FV_DL_G[bpct]} ]]; then __FV_DL_G[pct]=${__FV_DL_G[bpct]}; fi
                fv.dlg._text "${__FV_DL_G[btxt]}"
                __FV_DL_G[text]=$RESULT __FV_DL_G[ntext]=1
            else
                if (( __FV_DL_G[bn] )); then __FV_DL_G[btxt]+=$'\n'; fi
                __FV_DL_G[btxt]+=$__fvl_l __FV_DL_G[bn]=$(( __FV_DL_G[bn] + 1 ))
            fi ;;
        *)
            if [[ $__fvl_l == XXX* ]]; then __FV_DL_G[blk]=1
            elif fv.dlg._pct "$__fvl_l"; then __FV_DL_G[pct]=$RESULT; fi ;;
    esac
}

# fv.dlg._gShow — what changed drawn (and nothing else): the meter when the
# percentage differs from the one shown, the prompt when a new one differs
# from the text view's (the layout record keeps it for a resize)
fv.dlg._gShow() {
    local __fvl_v __fvl_k
    if ! [ "${__FV_DL_G[pct]}" = "${__FV_DL_G[spct]}" ]; then
        __FV_DL_G[spct]=${__FV_DL_G[pct]}
        __fvl_v=${__FV_DL_LAY[gv]-}
        if [[ -n $__fvl_v && -n ${__FV_VW_LIVE[$__fvl_v]-} ]]; then
            printf -v "${__fvl_v}_data[Pct]" '%s' "${__FV_DL_G[pct]}"
            fv.views.drawView "$__fvl_v" || :
            __FV_DL_G[shows]=$(( __FV_DL_G[shows] + 1 ))
        fi
    fi
    if (( ${__FV_DL_G[ntext]:-0} )); then
        __FV_DL_G[ntext]=0
        __FV_DL_LAY[text]=${__FV_DL_G[text]}
        __fvl_v=${__FV_DL_LAY[tx]-}
        __fvl_k="${__fvl_v}_data[Text]"
        if [[ -n $__fvl_v && -n ${__FV_VW_LIVE[$__fvl_v]-} ]] && ! [ "${!__fvl_k-}" = "${__FV_DL_G[text]}" ]; then
            printf -v "$__fvl_k" '%s' "${__FV_DL_G[text]}"
            fv.views.drawView "$__fvl_v" || :
            __FV_DL_G[tshows]=$(( __FV_DL_G[tshows] + 1 ))
        fi
    fi
}

# fv.dlg._file FILE — RESULT = the textbox's text: the file read whole
# (fork-free, bytes counted in the C locale) up to the cap __FV_DL_TXCAP
# (1 MiB; more: refused), NUL bytes dropped (bash's read), every CR
# dropped, one final newline dropped, tabs expanded to the next multiple of
# 8 cells, the other control characters shown as '?'; `\n` escapes and \Z
# are NOT applied (file content is literal). rc 1 with __fvl_err: a
# directory, a file that does not open, one over the cap
fv.dlg._file() {
    local __fvl_fd='' __fvl_s='' __fvl_n=0 __fvl_cc __fvl_l __fvl_w=0
    __DLFV_RAW=() __FV_DL_TXW=0 __FV_DL_TXX=0
    if [[ -d $1 ]] || ! { exec {__fvl_fd}<"$1"; } 2>/dev/null; then
        __fvl_err="cannot read the file '$1'"
        return 1
    fi
    fv.dlg._fread
    exec {__fvl_fd}<&-
    if (( __fvl_n > __FV_DL_TXCAP )); then
        __fvl_err="the file '$1' is larger than $__FV_DL_TXCAP bytes (the textbox's cap)"
        return 1
    fi
    # the lines (fv.dlg._flines: the C locale, substitutions only where
    # their characters occur — a pattern substitution over a big text in a
    # UTF-8 locale costs ~0.1 ms per match), the controls but tab as '?'
    # (C1 too in a UTF-8 call), the tabs expanded, the widest line's cells
    fv.dlg._flines
    __fvl_cc=${__FV_DG_CC[${#__FV_VS_PB}]-${__FV_DG_CC[5]}}
    __fvl_cc=${__fvl_cc//[$'\t\n\r']/}
    if [[ $__fvl_s == *[$__fvl_cc]* ]]; then __DLFV_RAW=("${__DLFV_RAW[@]//[$__fvl_cc]/?}"); fi
    for (( __fvl_n = 0; __fvl_n < ${#__DLFV_RAW[@]}; __fvl_n++ )); do
        __fvl_l=${__DLFV_RAW[__fvl_n]}
        if [[ $__fvl_l == *$'\t'* ]]; then fv.dlg._untab "$__fvl_l"; __fvl_l=$RESULT __DLFV_RAW[__fvl_n]=$RESULT; fi
        if [[ $__fvl_l != $__FV_VS_PNA ]]; then __fvl_w=${#__fvl_l}; else fv.video.strWidth "$__fvl_l" || RESULT=${#__fvl_l}; __fvl_w=$RESULT; fi
        if (( __fvl_w > __FV_DL_TXW )); then __FV_DL_TXW=$__fvl_w; fi
    done
    if (( ! ${#__DLFV_RAW[@]} )); then __DLFV_RAW=(''); fi
    local IFS=$'\n'
    RESULT="${__DLFV_RAW[*]}"
}
# fv.dlg._fitT TEXT MAXW — fv.dlg._fit, but for the textbox the lines'
# stats from fv.dlg._file (its rows: the lines; its width: the widest line
# + 1, at most MAXW) — no walk over a big file's words
fv.dlg._fitT() {
    if [ "$__fvl_w" = textbox ]; then
        __fvl_tw=$(( __FV_DL_TXW + 1 < $2 ? __FV_DL_TXW + 1 : $2 )) __fvl_th=${#__DLFV_RAW[@]}
        if (( __fvl_th < 1 )); then __fvl_th=1; fi
        return 0
    fi
    fv.dlg._fit "$@"
}
# fv.dlg._txFmt INDEX WIDTH — the textbox's row (TListViewer's Formatter):
# line INDEX of __DLFV_RAW from the column offset __FV_DL_TXX on (cells: a
# printable ASCII line by characters, any other by fv.video.clusters — a
# wide character the offset splits shows as a blank); the view cuts it
fv.dlg._txFmt() {
    local __fvl_l=${__DLFV_RAW[$1]-} __fvl_j __fvl_c=0 __fvl_o=$__FV_DL_TXX
    local -a _fvdl_cl=() _fvdl_cw=()
    if (( ! __fvl_o )); then RESULT=$__fvl_l; return 0; fi
    if [[ $__fvl_l != $__FV_VS_PNA ]]; then RESULT=${__fvl_l:__fvl_o}; return 0; fi
    # (at most the offset + the row's characters walked)
    fv.video.clusters "${__fvl_l:0:__fvl_o + $2}" _fvdl_cl _fvdl_cw || :
    for (( __fvl_j = 0; __fvl_j < ${#_fvdl_cl[@]} && __fvl_c < __fvl_o; __fvl_j++ )); do __fvl_c=$(( __fvl_c + _fvdl_cw[__fvl_j] )); done
    RESULT=''
    if (( __fvl_c > __fvl_o )); then RESULT=' '; fi
    local IFS=
    RESULT+="${_fvdl_cl[*]:__fvl_j}"
}
# fv.dlg._fread — _file's read (its __fvl_fd, __fvl_s, __fvl_n): at most
# the cap + 1 bytes, the length in bytes (the C locale for both)
fv.dlg._fread() {
    local LC_ALL=C
    IFS= read -r -N "$(( __FV_DL_TXCAP + 1 ))" -u "$__fvl_fd" __fvl_s || :
    __fvl_n=${#__fvl_s}
}
# fv.dlg._flines — _file's lines (its __fvl_s, the text read) into
# __DLFV_RAW, every CR dropped, one final newline dropped. Split by word
# splitting on newlines (C speed; mapfile reads a file or a here-string
# byte by byte here: ~70 us a line on the Windows runtimes), with the empty
# lines marked by \x1e first so the splitting keeps them (a \x1e of the
# file's own is a control character, shown as '?' anyway); every
# substitution runs only where its characters occur, in the C locale (bytes)
fv.dlg._flines() {
    # (the characters in variables, quoted where they are used: a $'...'
    # inside these expansions came out empty in a loaded unit on Git-bash)
    local - LC_ALL=C __fvl_x=$__fvl_s __fvl_n=$'\n' __fvl_m=$'\x1e' __fvl_r=$'\r'
    if [[ $__fvl_x == *"$__fvl_m"* ]]; then __fvl_x=${__fvl_x//"$__fvl_m"/?}; fi
    __fvl_x=${__fvl_x%"$__fvl_n"}
    if [[ $__fvl_x == *"$__fvl_n$__fvl_n"* ]]; then
        # (twice: a run of empty lines overlaps the first pass's matches)
        __fvl_x=${__fvl_x//"$__fvl_n$__fvl_n"/"$__fvl_n$__fvl_m$__fvl_n"}
        __fvl_x=${__fvl_x//"$__fvl_n$__fvl_n"/"$__fvl_n$__fvl_m$__fvl_n"}
    fi
    if [[ $__fvl_x == "$__fvl_n"* ]]; then __fvl_x=$__fvl_m$__fvl_x; fi
    if [[ $__fvl_x == *"$__fvl_n" ]]; then __fvl_x+=$__fvl_m; fi
    set -f
    local IFS=$__fvl_n
    # shellcheck disable=SC2206 # (split on purpose: newlines only, no globbing)
    __DLFV_RAW=($__fvl_x)
    __DLFV_RAW=("${__DLFV_RAW[@]#"$__fvl_m"}")
    if [[ $__fvl_x == *"$__fvl_r"* ]]; then
        __DLFV_RAW=("${__DLFV_RAW[@]%"$__fvl_r"}")
        if [[ ${__DLFV_RAW[*]} == *"$__fvl_r"* ]]; then __DLFV_RAW=("${__DLFV_RAW[@]//"$__fvl_r"/}"); fi
    fi
}
# fv.dlg._untab LINE — RESULT = LINE with each tab expanded to the next
# multiple of 8 cells (a printable ASCII piece: characters = cells)
fv.dlg._untab() {
    local __fvl_x=$1 __fvl_r='' __fvl_g __fvl_c=0 __fvl_w __fvl_p
    while [[ $__fvl_x == *$'\t'* ]]; do
        __fvl_g=${__fvl_x%%$'\t'*} __fvl_x=${__fvl_x#*$'\t'}
        if [[ $__fvl_g != $__FV_VS_PNA ]]; then __fvl_w=${#__fvl_g}; else fv.video.strWidth "$__fvl_g" || RESULT=${#__fvl_g}; __fvl_w=$RESULT; fi
        __fvl_c=$(( __fvl_c + __fvl_w ))
        printf -v __fvl_p '%*s' "$(( 8 - __fvl_c % 8 ))" ''
        __fvl_r+=$__fvl_g$__fvl_p __fvl_c=$(( __fvl_c + ${#__fvl_p} ))
    done
    RESULT=$__fvl_r$__fvl_x
}

# ---- the call ---------------------------------------------------------------------

# fv.dlg._call FACE ARG... — both faces: parse, the screen, the dialog, the
# result; RESULT = the answer, FV_DLG_TAGS the chosen tags, FV_DLG_CMD the
# command; the status (0 / 1 / 255). Where the dialog runs (__fvl_mode):
#   own      no fv application in this shell: one is made for the call and
#            deleted after it (the terminal on and off: fv.video)
#   session  inside fv.dlg.begin / end: the session's application
#   host     inside a running fv application of the caller (FV_APP live):
#            its desktop; no background title, NO_COLOR is the host's
# session / host: only in the shell that owns the screen (a subshell is
# refused: 255), the terminal options belong to fv.dlg.begin / the host.
# FACE main: the result printed to O[out] (default 2), P4-6's buffer (own
# mode), --help / --version; run: printed only to an asked fd
fv.dlg._call() {
    # (D11, M2: a caller whose locale is not UTF-8, or with nocasematch, or
    # without globasciiranges, runs the whole call through fv.video._g — a
    # UTF-8 locale of its own, the caller's state and locale put back by
    # fv.video's L-1 rules — so the slicing, the case folding and the keys
    # see characters, not bytes)
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local IFS=$' \t\n' __fvl_face=$1 __fvl_w='' __fvl_err='' __fvl_m='' __fvl_t __fvl_d='' __fvl_il='' __fvl_lb='' __fvl_b1='' __fvl_b2=''
    local __fvl_app='' __fvl_cmd=cmCancel __fvl_rc=255 __fvl_res='' __fvl_vid=0 __fvl_kfd='' __fvl_ofd='' __fvl_fd __fvl_ok=1 __fvl_hl=0
    local __fvl_mode=own __fvl_top=0 __fvl_bt='' __fvl_k __fvl_i __fvl_x __fvl_y __fvl_main=0 __fvl_clr=0 __fvl_built=0
    local -a __fvl_p=() __fvl_tags=()
    local -A __fvl_o=()
    shift
    RESULT='' FV_DLG_CMD='' FV_DLG_TAGS=()
    if ! fv.dlg._parse "$@"; then fv.dlg._say "$__fvl_face" "$__fvl_err"; return 255; fi
    if [[ -n $__fvl_m ]]; then
        if [ "$__fvl_face" = run ]; then fv.dlg._say run "'$__fvl_m' is for the command (fvdlg)"; return 255; fi
        fv.dlg._usage "$__fvl_m"
        return
    fi
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then
        __fvl_mode=host
        if [ "${__FV_DL_SES[app]-}" = "$FV_APP" ]; then __fvl_mode=session; fi
        if ! [ "$BASHPID" = "${__FV_VW_OWNER-}" ]; then
            fv.dlg._say "$__fvl_face" "refused in a subshell (BASHPID $BASHPID; the screen belongs to ${__FV_VW_OWNER-}): call it in the shell that owns the screen, the answer is in RESULT"
            return 255
        fi
        for __fvl_k in headless keys size fvout ascii mouse screen; do
            [[ -n ${__fvl_o[$__fvl_k]+x} ]] || continue
            if [ "$__fvl_mode" = session ]; then __fvl_i='fv.dlg.begin (a session is running)'; else __fvl_i='the running fv application'; fi
            fv.dlg._say "$__fvl_face" "${__FV_DL_TOPT[$__fvl_k]} belongs to $__fvl_i"
            return 255
        done
    fi
    # (4d: what the gauge and the textbox read — refused before any screen
    # change: the gauge's stdin, the textbox's file)
    if [ "$__fvl_w" = gauge ]; then
        if [ "$__fvl_mode" = host ]; then
            fv.dlg._say "$__fvl_face" "--gauge needs fvdlg's own application or a session (the running fv application's Idle does not read stdin)"
            return 255
        fi
        if ! [[ -e /dev/fd/0 ]]; then fv.dlg._say "$__fvl_face" "--gauge reads its percentages from stdin, which is not open"; return 255; fi
        if fv.dlg._isTerm 0; then
            fv.dlg._say "$__fvl_face" "--gauge reads its percentages from stdin, which is a terminal (pipe them in: ... | fvdlg --gauge TEXT H W)"
            return 255
        fi
    fi
    if [ "$__fvl_w" = textbox ]; then
        if ! fv.dlg._file "${__fvl_p[0]}"; then fv.dlg._say "$__fvl_face" "$__fvl_err"; return 255; fi
    else
        fv.dlg._text "${__fvl_p[0]}"
    fi
    __fvl_t=$RESULT RESULT=''
    if [ "$__fvl_mode" = own ]; then
        # the terminal's settings for this call only (the caller's come back
        # at the return): headless (the caller's FV_APP_HEADLESS=1 with its
        # FV_KEY_FD / FV_VIDEO_OUT_FD / FV_SCREEN_W / _H is honoured, fv.app's
        # convention; --fv-headless sets its own), ASCII, the infobox's
        # keyboard protocol
        local FV_APP_HEADLESS=${FV_APP_HEADLESS-} FV_SCREEN_W=$FV_SCREEN_W FV_SCREEN_H=$FV_SCREEN_H FV_VIDEO_OUT_FD=$FV_VIDEO_OUT_FD
        local FV_KEY_FD=$FV_KEY_FD FV_ASCII=${FV_ASCII-} FV_VIDEO_ASCII=$FV_VIDEO_ASCII FV_KBD_PROTO=${FV_KBD_PROTO-}
        if [[ -n ${__fvl_o[ascii]-} ]]; then FV_ASCII=1; fi
        if [ "$__fvl_w" = infobox ] && [[ -z $FV_KBD_PROTO ]]; then FV_KBD_PROTO=off; fi
        if [[ -n ${__fvl_o[headless]-} ]]; then
            if ! fv.dlg._hlOpen "$__fvl_face"; then __DLFV_RAW=(); return 255; fi
            FV_APP_HEADLESS=1 FV_SCREEN_W=$__fvl_x FV_SCREEN_H=$__fvl_y FV_VIDEO_OUT_FD=$__fvl_ofd FV_KEY_FD=$__fvl_kfd
        fi
        if [ "${FV_APP_HEADLESS-}" = 1 ]; then __fvl_hl=1; fi
        # D36: no terminal and --no-tty=default — the answer Enter would
        # give, no UI, printed as the UI's (a headless call has no terminal
        # to miss). The command's face without it: refused here with
        # bin/fvdlg's words (its pre-load guard leaves a call that names
        # --no-tty to this test); the bash face tries the terminal (below)
        if (( ! __fvl_hl )) && { [ "${__fvl_o[notty]-}" = default ] || [ "$__fvl_face" = main ]; } && ! fv.dlg._hasTerm "$__fvl_face"; then
            if ! [ "${__fvl_o[notty]-}" = default ]; then
                __DLFV_RAW=()
                fv.dlg._say main "no terminal ($REPLY)"
                RESULT='' FV_DLG_CMD='' FV_DLG_TAGS=()
                return 255
            fi
            __DLFV_RAW=()
            fv.dlg._dflt
            fv.dlg._emit
            return
        fi
        # D34: the screen mode (fv.dlg._screen)
        fv.dlg._screen
        if [[ -n ${__fvl_o[backtitle]-} ]]; then __fvl_top=1 __fvl_bt=${__fvl_o[backtitle]}; fi
        if [ "$__fvl_face" = main ]; then fv.dlg._bufOn; fi
        # the main screen (the infobox, --fv-screen main): turned on here
        # without the alternate screen (noalt), so the application leaves
        # it on at its Done and the last picture stays visible
        if (( __fvl_main && ! __fvl_hl && ! FV_VIDEO_ON )); then
            if fv.video.initVideo noalt; then __fvl_vid=1; else __fvl_ok=0; fi
        fi
        if (( __fvl_ok )) && fv.views._newReserved '' dlgapp TDlgApp; then
            __fvl_app=$RESULT
            # --fv-mouse off: the reporting the application's start turned on
            # switched off again (fv.mouse alone: fv.drivers.doneEvents would
            # also drop the keys already read)
            if [ "${__fvl_o[mouse]-on}" = off ] && (( ! __fvl_hl )) && [[ -n ${FV_TTY_FD-} ]]; then fv.mouse.disable "$FV_TTY_FD" || :; fi
            if [[ -n ${NO_COLOR-} ]]; then fv.dlg._nocolor; fi
        else
            __fvl_ok=0 __fvl_err="no terminal (${FV_TTY:-/dev/tty})"
        fi
    else
        __fvl_app=$FV_APP
        # (an infobox the session or the host still shows goes first)
        fv.dlg._infoOff
        if [ "$__fvl_mode" = session ]; then
            if [[ -n ${__fvl_o[backtitle]-} ]]; then fv.dlg._title "${__fvl_o[backtitle]}"; fi
            if [[ -n ${__FV_DL_SES[title]-} && -n ${__FV_VW_LIVE[${__FV_DL_SES[title]}]-} ]]; then __fvl_top=1; fi
        fi
    fi
    if (( __fvl_ok )); then
        __FV_DL_SMALL='' __FV_DL_LAY=()
        if fv.dlg._build; then
            __fvl_built=1
            if [ "$__fvl_w" = infobox ]; then
                # (session / host: not selectable — inserted, it takes
                # neither the desktop's current view nor the host window's
                # focus: M1)
                if ! [ "$__fvl_mode" = own ]; then fv.dlg._unsel "$__fvl_d"; fi
                fv.views.insert "$FV_DESKTOP" "$__fvl_d" || :
                if [ "$__fvl_mode" = own ]; then
                    # P4-10: one paint, no loop, the cursor on the last row
                    fv.app._firstPaint "$__fvl_app" || :
                    fv.video.setCursorPos 0 "$(( FV_SCREEN_H - 1 ))" || :
                    fv.video.setCursorType 1 || :
                    fv.video.updateScreen || :
                else
                    # (session / host: shown now, left on the desktop until
                    # the next call or fv.dlg.end)
                    __FV_DL_INFO=$__fvl_d
                    fv.views._showNow
                fi
                __fvl_cmd=cmOK
            else
                # (the main screen: the dialog inserted first, so execView
                # neither inserts nor removes it — it is the desktop's
                # current view, its end redraws nothing — and the last
                # picture stays on the screen: fv.dlg._mainEnd)
                if (( __fvl_main )); then fv.views.insert "$FV_DESKTOP" "$__fvl_d" || :; fi
                if [ "$__fvl_w" = gauge ]; then fv.dlg._gRun
                else
                    fv.views.execView "$FV_DESKTOP" "$__fvl_d" || :
                    __fvl_cmd=${RESULT:-cmCancel}
                fi
            fi
            if [ "$__fvl_cmd" = cmOK ] || [ "$__fvl_cmd" = cmYes ]; then __fvl_rc=0
            elif [ "$__fvl_cmd" = cmNo ]; then __fvl_rc=1; fi
            if [[ -n $__FV_DL_SMALL ]]; then __fvl_ok=0 __fvl_err=$__FV_DL_SMALL; fi
            if (( __fvl_rc == 0 )) && [[ -n $__fvl_il ]] && fv.dialogs.getText "$__fvl_il"; then __fvl_res=$RESULT; fi
            if (( __fvl_rc == 0 )) && [[ -n $__fvl_lb ]]; then fv.dlg._answer; fi
        else
            __fvl_ok=0
        fi
        __FV_DL_LAY=() __FV_DL_SMALL=''
        if [[ -n $__fvl_lb ]]; then unset '__FV_DL_KIND[$__fvl_lb]'; fi
        # (the own infobox's dialog goes with the desktop at the
        # application's Done, which draws nothing: deleted alone first it
        # would repaint the desktop over the box; a session's / host's
        # stays)
        # (the main screen's dialog likewise: it stays on the screen)
        # (the main screen's end only after a dialog was built: a refusal —
        # too small — leaves the screen as it was found)
        if [ "$__fvl_w" != infobox ] && (( ! __fvl_main )) && [[ -n $__fvl_d && -n ${__FV_VW_LIVE[$__fvl_d]-} ]]; then "$__fvl_d.delete"; fi
        if [ "$__fvl_mode" = own ]; then
            if (( __fvl_main && __fvl_built && ! __fvl_clr )) && [ "$__fvl_w" != infobox ]; then fv.video.updateScreen || :; fi
            "$__fvl_app.delete"
            if (( __fvl_main && __fvl_built )); then
                if (( __fvl_clr )); then fv.dlg._clearOut; fi
                fv.dlg._mainEnd
            fi
        else
            fv.views._showNow
        fi
        # (the dialog gone, its arrays emptied — a 10 000-item list is not
        # kept until the next call: _dflt's rule; the text's lines too,
        # unless a session's / host's infobox still shows them)
        __DLFV_TAGS=() __DLFV_ROWS=() __DLFV_MARKS=() __DLFV_FIRST=() __DLFV_NEXT=() __FV_DL_JUMP=() __FV_DL_JN=''
        if [ "$__fvl_w" != infobox ] || [ "$__fvl_mode" = own ]; then __DLFV_TEXT=(); fi
    fi
    __DLFV_RAW=()
    if (( __fvl_vid )); then fv.video.doneVideo || :; fi
    if [[ -n $__fvl_kfd ]]; then exec {__fvl_kfd}<&- {__fvl_ofd}>&-; fi
    if [ "$__fvl_face" = main ] && [ "$__fvl_mode" = own ]; then fv.dlg._bufOff; fi
    if (( ! __fvl_ok )); then
        fv.dlg._say "$__fvl_face" "${__fvl_err:-the dialog could not be made}"
        RESULT='' FV_DLG_CMD='' FV_DLG_TAGS=()
        return 255
    fi
    fv.dlg._emit
}

# fv.dlg._emit — the call's answer (the caller's __fvl_*: face, w, rc, cmd,
# res, tags, o): FV_DLG_CMD, RESULT, FV_DLG_TAGS; the result written once,
# after the restore, only on 0 (nothing on 1 / 255) by the widgets that
# answer text, to O[out] (the command: default 2). An fd that is not open,
# or a write that fails (a full disk, /dev/full): 255, one line, RESULT,
# FV_DLG_TAGS and FV_DLG_CMD empty. The status
fv.dlg._emit() {
    FV_DLG_CMD=$__fvl_cmd
    RESULT=$__fvl_res
    if (( __fvl_rc == 0 )); then FV_DLG_TAGS=("${__fvl_tags[@]}"); fi
    __fvl_fd=${__fvl_o[out]-}
    if [ "$__fvl_face" = main ]; then __fvl_fd=${__fvl_fd:-2}; fi
    if (( __fvl_rc == 0 )) && [[ -n $__fvl_fd ]] && [[ " inputbox passwordbox menu checklist radiolist " == *" $__fvl_w "* ]]; then
        # (an open fd checked first; the write's own error line is dropped:
        # the redirection order sends the text to fd N before 2 moves)
        if ! { : >&$__fvl_fd; } 2>/dev/null || ! printf '%s' "$__fvl_res" >&$__fvl_fd 2>/dev/null; then
            fv.dlg._say "$__fvl_face" "cannot write the result to fd $__fvl_fd"
            RESULT='' FV_DLG_CMD='' FV_DLG_TAGS=()
            return 255
        fi
    fi
    return "$__fvl_rc"
}

# (the gauge: stdin read to its end, rc 0; the textbox: rc 0)
# fv.dlg._dflt — D36 (--no-tty=default without a terminal): the caller's
# __fvl_rc / __fvl_cmd / __fvl_res / __fvl_tags = what Enter on the dialog
# as built would answer, with no UI: msgbox and infobox 0 (cmOK; nothing
# drawn), yesno 0 (cmYes; --defaultno 1, cmNo), inputbox / passwordbox 0
# and INIT as the input line keeps it (control characters dropped, at most
# its 1024 clusters: fv.dialogs' setText rule), menu the --default-item's
# tag (its first item with that tag, else the first), checklist its `on`
# tags, radiolist its `on` tag (the last one: whiptail's rule) or '' when
# none is on — the UI's Enter answers the marks, not the focused row
fv.dlg._dflt() {
    local __fvl_rw=0 __fvl_di=0 __fvl_t __fvg_pw=0
    local -a _fvg_nl=() _fvg_nw=()
    __fvl_rc=0 __fvl_cmd=cmOK __fvl_res='' __fvl_tags=()
    if [ "$__fvl_w" = yesno ]; then
        if [[ -n ${__fvl_o[defaultno]-} ]]; then __fvl_rc=1 __fvl_cmd=cmNo; else __fvl_cmd=cmYes; fi
    elif [ "$__fvl_w" = inputbox ] || [ "$__fvl_w" = passwordbox ]; then
        __fvl_t=${__fvl_p[3]-}
        __fvl_t=${__fvl_t//[${__FV_DG_CC[${#__FV_VS_PB}]-${__FV_DG_CC[5]}}]/}
        if [[ -n $__fvl_t ]] && ! fv.dialogs._ilPre "$__fvl_t" 1024; then _fvg_nl=(); fi
        local IFS=
        __fvl_res="${_fvg_nl[*]}"
    elif [ "$__fvl_w" = gauge ]; then
        # (stdin read to its end, as the dialog would; nothing shown)
        local __fvl_s=''
        while IFS= read -r -N 65536 __fvl_s || [[ -n $__fvl_s ]]; do __fvl_s=''; done
    elif [ "$__fvl_w" = menu ] || [ "$__fvl_w" = checklist ] || [ "$__fvl_w" = radiolist ]; then
        fv.dlg._items
        fv.dlg._answerAt "$__fvl_di"
        __DLFV_TAGS=() __DLFV_ROWS=() __DLFV_MARKS=() __DLFV_FIRST=() __DLFV_NEXT=() __FV_DL_JUMP=() __FV_DL_JN=''
    fi
    return 0
}

# fv.dlg._screen — D34: the caller's __fvl_main (1: this call draws on the
# main screen) and __fvl_clr (1: that screen cleared at the exit) from its
# options (__fvl_o) and widget (__fvl_w; '' for fv.dlg.begin): --fv-screen
# alt|main wins, else --keep-tite = alt, else --erase-on-exit = main, else
# alt; --clear or --erase-on-exit = cleared. The infobox: always main, never
# cleared (P4-10: the box is meant to stay). Main only where this call owns
# the screen's start: headless, or the terminal not on yet (a caller that
# turned it on keeps its own screen)
fv.dlg._screen() {
    local __fvl_s=alt
    __fvl_main=0 __fvl_clr=0
    if [[ -n ${__fvl_o[screen]-} ]]; then __fvl_s=${__fvl_o[screen]}
    elif [[ -n ${__fvl_o[keeptite]-} ]]; then __fvl_s=alt
    elif [[ -n ${__fvl_o[erase]-} ]]; then __fvl_s=main; fi
    if [ "$__fvl_w" = infobox ]; then __fvl_s=main; fi
    if [ "$__fvl_s" = main ] && { [ "${FV_APP_HEADLESS-}" = 1 ] || (( ! FV_VIDEO_ON )); }; then __fvl_main=1; fi
    if (( __fvl_main )) && ! [ "$__fvl_w" = infobox ] && [[ -n ${__fvl_o[clear]-}${__fvl_o[erase]-} ]]; then __fvl_clr=1; fi
    return 0
}
# fv.dlg._mainEnd — the main screen's end (D34), after the application and
# any clear: the cursor on the screen's last row, column 0, shown (dialog's
# endwin: golden `ESC [ 24 ; 1 H`), so the shell's next output starts below
# the dialog. On a terminal that is fv.video's restore after initVideo noalt
# (every exit path: done, exit, a signal) — the one place; here only the
# headless frame file, which has no restore, gets the same tail
fv.dlg._mainEnd() {
    [ "${FV_APP_HEADLESS-}" = 1 ] || return 0
    local IFS= __fvl_f=${FV_VIDEO_OUT_FD-}
    [[ -n $__fvl_f && $__fvl_f != *[!0123456789]* ]] || return 0
    printf '%s' $'\e[0m\e[?25h\e['"$FV_SCREEN_H;1H" 2>/dev/null >&$__fvl_f || :
}
# fv.dlg._clearOut — --clear / --erase-on-exit on the main screen: SGR reset,
# the screen cleared, the cursor home (`clear`'s picture), written where the
# frames go (the terminal, or the headless frame file); the cursor then
# goes to the last row as after any main-screen call (dialog's order)
fv.dlg._clearOut() {
    local IFS= __fvl_f=${FV_VIDEO_OUT_FD:-${FV_TTY_FD-}}
    [[ -n $__fvl_f && $__fvl_f != *[!0123456789]* ]] || return 0
    printf '%s' $'\e[0m\e[H\e[2J' 2>/dev/null >&$__fvl_f || :
}

# fv.dlg._hlOpen FACE — --fv-headless: the key file and the frame file
# opened (the caller's __fvl_kfd / __fvl_ofd), the size in __fvl_x x
# __fvl_y; rc 1 after one refusal line
fv.dlg._hlOpen() {
    if ! { exec {__fvl_kfd}<"${__fvl_o[keys]-/dev/null}"; } 2>/dev/null; then
        __fvl_kfd=''
        fv.dlg._say "$1" "cannot read the key file '${__fvl_o[keys]-}'"
        return 1
    fi
    if ! { exec {__fvl_ofd}>"${__fvl_o[fvout]-/dev/null}"; } 2>/dev/null; then
        exec {__fvl_kfd}<&-
        __fvl_kfd='' __fvl_ofd=''
        fv.dlg._say "$1" "cannot write the frame file '${__fvl_o[fvout]-}'"
        return 1
    fi
    __fvl_x=${__fvl_o[size]-80x24}
    __fvl_y=$(( 10#${__fvl_x#*x} )) __fvl_x=$(( 10#${__fvl_x%%x*} ))
}

# fv.dlg._answer — a list's answer after OK (the caller's __fvl_*): the
# chosen tags in __fvl_tags (menu: the focused item; radiolist: the marked
# one, none possible; checklist: the marked ones in order) and the text
# __fvl_res (D37): the menu's and the radiolist's tag bare; the checklist's
# per --fv-output (else --separate-output = lines, --single-quoted =
# single, else quoted): lines — each tag and a newline; quoted — whiptail's
# form, each tag in double quotes, blank-separated, nothing escaped;
# single — dialog's --single-quoted form (fv.dlg._dq)
fv.dlg._answer() {
    local -n __fvl_la=${__fvl_lb}_data
    fv.dlg._answerAt "${__fvl_la[Focused]:-0}"
}
# fv.dlg._answerAt FOCUSED — _answer's body with the menu's focused item
# given (the UI's list, or D36's default answer: fv.dlg._dflt)
fv.dlg._answerAt() {
    local __fvl_i __fvl_f=quoted __fvl_s=''
    if [ "$__fvl_w" = menu ]; then
        __fvl_tags=("${__DLFV_TAGS[$1]}")
    else
        for __fvl_i in "${!__DLFV_MARKS[@]}"; do
            if [[ ${__DLFV_MARKS[__fvl_i]:-0} != 0 ]]; then __fvl_tags+=("${__DLFV_TAGS[__fvl_i]}"); fi
        done
    fi
    if ! [ "$__fvl_w" = checklist ]; then __fvl_res=${__fvl_tags[0]-}; return 0; fi
    if [[ -n ${__fvl_o[output]-} ]]; then __fvl_f=${__fvl_o[output]}
    elif [[ -n ${__fvl_o[sepout]-} ]]; then __fvl_f=lines
    elif [[ -n ${__fvl_o[single]-} ]]; then __fvl_f=single; fi
    for __fvl_i in "${__fvl_tags[@]}"; do
        case $__fvl_f in
            lines) __fvl_s+=$__fvl_i$'\n' ;;
            quoted) __fvl_s+="${__fvl_s:+ }\"$__fvl_i\"" ;;
            *) fv.dlg._dq "$__fvl_i"; __fvl_s+="${__fvl_s:+ }$RESULT" ;;
        esac
    done
    __fvl_res=$__fvl_s
}
# fv.dlg._dq TAG — RESULT = TAG as dialog's --single-quoted writes it
# (golden2: dlg_add_quoted): quoted when empty or holding a blank, a tab, a
# newline, the quote ' or one of \ [ ] { } ? * ; ` ~ # $ ^ & ( ) | < >;
# inside the quotes ' \ and a newline get a backslash
fv.dlg._dq() {
    local __fvl_s=$1 __fvl_q="'" __fvl_i __fvl_c __fvl_n=0
    if [[ -z $__fvl_s ]]; then __fvl_n=1; fi
    for (( __fvl_i = 0; __fvl_i < ${#__fvl_s}; __fvl_i++ )); do
        __fvl_c=${__fvl_s:__fvl_i:1}
        if [[ $__FV_DL_QESC == *"$__fvl_c"* ]]; then __fvl_q+="\\$__fvl_c" __fvl_n=1
        elif [[ $__FV_DL_QSET == *"$__fvl_c"* ]]; then __fvl_q+=$__fvl_c __fvl_n=1
        else __fvl_q+=$__fvl_c; fi
    done
    if (( __fvl_n )); then RESULT="$__fvl_q'"; else RESULT=$__fvl_s; fi
}

# fv.dlg._infoOff — the infobox a session or the host application still
# shows (__FV_DL_INFO) removed (its rows repainted from under it)
fv.dlg._infoOff() {
    if [[ -n $__FV_DL_INFO && -n ${__FV_VW_LIVE[$__FV_DL_INFO]-} ]]; then "$__FV_DL_INFO.delete"; fi
    __FV_DL_INFO=''
}
# fv.dlg._title TEXT — the session's background title: made on row 0 of the
# desktop, or its text replaced and drawn
fv.dlg._title() {
    local __fvl_v=${__FV_DL_SES[title]-}
    if [[ -n $__fvl_v && -n ${__FV_VW_LIVE[$__fvl_v]-} ]]; then
        printf -v "${__fvl_v}_data[Text]" '%s' "$1"
        fv.views.drawView "$__fvl_v" || :
        return 0
    fi
    local -n __fvl_kd=${FV_DESKTOP}_data
    fv.views._newReserved "$FV_DESKTOP" backtitle TDlgTitle 0 0 "${__fvl_kd[SizeX]:-80}" 1 || return 0
    __fvl_v=$RESULT
    printf -v "${__fvl_v}_data[Text]" '%s' "$1"
    printf -v "${__fvl_v}_data[GrowMode]" '%d' "$FV_GF_GROWHIX"
    fv.views.insert "$FV_DESKTOP" "$__fvl_v" || :
    __FV_DL_SES[title]=$__fvl_v
}

# fv.dlg._usage --help|--version — the command's text, printed from
# fv.dlg.usage.sh (the one copy: bin/fvdlg prints it from there without a
# load); its status (printf's on a failed write); 255 with one line when
# the file is missing
fv.dlg._usage() {
    if ! [[ -r $__FV_DL_DIR/fv.dlg.usage.sh ]]; then fv.dlg._say main "no usage text ($__FV_DL_DIR/fv.dlg.usage.sh)"; return 255; fi
    source "$__FV_DL_DIR/fv.dlg.usage.sh" "$1"
}

# ---- the faces --------------------------------------------------------------------

# fv.dlg.main ARG... — the command's face; returns the status (bin/fvdlg exits
# with it)
fv.dlg.main() { fv.dlg._call main "$@"; }
# fv.dlg.run ARG... — the bash face: RESULT, FV_DLG_TAGS, FV_DLG_CMD, the
# status
fv.dlg.run() { fv.dlg._call run "$@"; }

# fv.dlg.begin [OPTION...] — a session (design §2.2): one application and one
# screen for the fv.dlg.run calls until fv.dlg.end (no terminal start / stop
# per dialog; nothing flashes between them). Options: --backtitle T,
# --fv-ascii / --ascii-lines, --fv-mouse on|off, --fv-screen alt|main,
# --keep-tite, --erase-on-exit, --clear, --fv-headless [--fv-keys F]
# [--fv-size WxH] [--fv-out F]; the terminal settings (FV_APP_HEADLESS,
# FV_SCREEN_W / _H, FV_KEY_FD, FV_VIDEO_OUT_FD, FV_ASCII, FV_VIDEO_ASCII)
# are the session's until fv.dlg.end puts the caller's back. NO_COLOR is
# applied once. The desktop (and the background title) is painted at once.
# The screen (D34, fv.dlg._screen): taken here once — the main screen is
# turned on by begin (initVideo noalt) and off by end, which leaves the
# session's picture with the cursor on the last row (or clears it:
# --clear / --erase-on-exit); the alternate screen is the application's.
# Status 0 (RESULT '', L4); 255 with one line: a session already running, an fv application
# already running (fv.dlg.run uses it: no session needed), a dialog option,
# no terminal
fv.dlg.begin() {
    # (D11, M2: as fv.dlg._call)
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    local IFS=$' \t\n' __fvl_w='' __fvl_err='' __fvl_m='' __fvl_k __fvl_v __fvl_kfd='' __fvl_ofd='' __fvl_x __fvl_y
    local __fvl_main=0 __fvl_clr=0
    local -a __fvl_p=()
    local -A __fvl_o=()
    RESULT=''
    if [[ -n ${__FV_DL_SES[app]-} && -n ${__FV_VW_LIVE[${__FV_DL_SES[app]}]-} ]]; then
        fv.dlg._say begin 'a session is already running (fv.dlg.end first)'; return 255
    fi
    if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then
        fv.dlg._say begin 'an fv application is already running in this shell: fv.dlg.run uses it, no session needed'; return 255
    fi
    # (the parser's rules and checks: the options after a stand-in widget)
    if ! fv.dlg._parse --infobox '' 0 0 "$@"; then fv.dlg._say begin "$__fvl_err"; return 255; fi
    if [[ -n $__fvl_m ]]; then fv.dlg._say begin "'$__fvl_m' is for the command (fvdlg)"; return 255; fi
    for __fvl_k in "${!__fvl_o[@]}"; do
        if [[ ' backtitle ascii mouse screen keeptite erase clear headless keys size fvout ' != *" $__fvl_k "* ]]; then
            fv.dlg._say begin "'$__fvl_k' is a dialog's option, not the session's (give it to fv.dlg.run)"; return 255
        fi
    done
    __FV_DL_SES=()
    for __fvl_k in FV_APP_HEADLESS FV_SCREEN_W FV_SCREEN_H FV_KEY_FD FV_VIDEO_OUT_FD FV_ASCII FV_VIDEO_ASCII; do
        if [[ -n ${!__fvl_k+x} ]]; then __FV_DL_SES[s_$__fvl_k]=s${!__fvl_k}; else __FV_DL_SES[s_$__fvl_k]=u; fi
    done
    if [[ -n ${__fvl_o[ascii]-} ]]; then FV_ASCII=1; fi
    if [[ -n ${__fvl_o[headless]-} ]]; then
        if ! fv.dlg._hlOpen begin; then fv.dlg._sesEnv; __FV_DL_SES=(); return 255; fi
        FV_APP_HEADLESS=1 FV_SCREEN_W=$__fvl_x FV_SCREEN_H=$__fvl_y FV_VIDEO_OUT_FD=$__fvl_ofd FV_KEY_FD=$__fvl_kfd
        __FV_DL_SES[kfd]=$__fvl_kfd __FV_DL_SES[ofd]=$__fvl_ofd
    fi
    # D34: the session's screen, once (fv.dlg._screen with no widget: the
    # infobox rule is a call's); the main screen turned on here (noalt)
    __fvl_w=''
    fv.dlg._screen
    __FV_DL_SES[main]=$__fvl_main __FV_DL_SES[clr]=$__fvl_clr
    if (( __fvl_main )) && ! [ "${FV_APP_HEADLESS-}" = 1 ]; then
        if ! fv.video.initVideo noalt; then
            fv.dlg._sesClose
            fv.dlg._say begin "no terminal (${FV_TTY:-/dev/tty})"
            return 255
        fi
        __FV_DL_SES[vid]=1
    fi
    if ! fv.views._newReserved '' dlgapp TDlgApp; then
        if [[ -n ${__FV_DL_SES[vid]-} ]]; then fv.video.doneVideo || :; fi
        fv.dlg._sesClose
        fv.dlg._say begin "no terminal (${FV_TTY:-/dev/tty})"
        return 255
    fi
    __FV_DL_SES[app]=$RESULT __FV_DL_INFO=''
    if [ "${__fvl_o[mouse]-on}" = off ] && ! [ "${FV_APP_HEADLESS-}" = 1 ] && [[ -n ${FV_TTY_FD-} ]]; then fv.mouse.disable "$FV_TTY_FD" || :; fi
    if [[ -n ${NO_COLOR-} ]]; then fv.dlg._nocolor; fi
    if [[ -n ${__fvl_o[backtitle]-} ]]; then fv.dlg._title "${__fvl_o[backtitle]}"; fi
    fv.app._firstPaint "${__FV_DL_SES[app]}" || :
    RESULT=''
    return 0
}
# fv.dlg.end — the session's end: its application deleted (fv.video gives
# the terminal back), the key / frame files closed, the caller's terminal
# settings back. Inside a host application: the infobox fv.dlg.run left
# there removed. Without either: nothing. Status 0
fv.dlg.end() {
    if [[ -z ${__FV_DL_SES[app]-} ]]; then
        if [[ -n $FV_APP && -n ${__FV_VW_LIVE[$FV_APP]-} ]]; then fv.dlg._infoOff; fv.views._showNow; fi
        return 0
    fi
    __FV_DL_INFO=''
    # (the main screen: what the session shows stays, the cursor on the
    # last row — or the screen cleared; the terminal off when begin turned
    # it on)
    local __fvl_main=${__FV_DL_SES[main]:-0} __fvl_clr=${__FV_DL_SES[clr]:-0} __fvl_vid=${__FV_DL_SES[vid]:-0}
    if [[ -n ${__FV_VW_LIVE[${__FV_DL_SES[app]}]-} ]]; then
        if (( __fvl_main && ! __fvl_clr )); then fv.video.updateScreen || :; fi
        "${__FV_DL_SES[app]}.delete"
        if (( __fvl_main && __fvl_clr )); then fv.dlg._clearOut; fi
        if (( __fvl_main )); then fv.dlg._mainEnd; fi
    fi
    if (( __fvl_vid )); then fv.video.doneVideo || :; fi
    fv.dlg._sesClose
    return 0
}
# fv.dlg._sesClose — the session's files closed, the caller's settings
# back, the record cleared
fv.dlg._sesClose() {
    local __fvl_f
    for __fvl_f in "${__FV_DL_SES[kfd]-}" "${__FV_DL_SES[ofd]-}"; do
        if [[ -n $__fvl_f ]]; then exec {__fvl_f}>&-; fi
    done
    fv.dlg._sesEnv
    __FV_DL_SES=()
}
# fv.dlg._sesEnv — the terminal settings fv.dlg.begin saved put back
fv.dlg._sesEnv() {
    local __fvl_k __fvl_v
    for __fvl_k in FV_APP_HEADLESS FV_SCREEN_W FV_SCREEN_H FV_KEY_FD FV_VIDEO_OUT_FD FV_ASCII FV_VIDEO_ASCII; do
        __fvl_v=${__FV_DL_SES[s_$__fvl_k]-}
        if [[ $__fvl_v == s* ]]; then printf -v "$__fvl_k" '%s' "${__fvl_v:1}"
        elif [ "$__fvl_v" = u ]; then unset "$__fvl_k"; fi
    done
}
