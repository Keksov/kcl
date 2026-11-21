#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.dialogs.sh}../../kbool.sh" || return
kk.unit fv.dialogs || return $__kk_unit_rc

# fv.dialogs — Free Vision's Dialogs unit for the fv.* text UI (layer L3): P3
# stage 3c brings TDialog, TButton, TStaticText, TParamText, TLabel, TCluster,
# TCheckBoxes and TRadioButtons (FV dialogs.inc) as kklass classes on fv.views'
# TView / TWindow, the data transfer (fv.dialogs.getData / setData / dataSize
# over the GetData / SetData / DataSize virtuals), the setters and FV's TDialog
# helpers. TInputLine / TListBox come with 3d, THistory with 3h.
# Design: kcl/docs/dev/fv/P3_DESIGN.md (§1, §2.1, §2.4, §2.6, §2.7, §3, §4.6);
# API and deviations: README.md.
#
# Conventions (as fv.views'): locals `__fvg_*` (fv.drivers has __fvd_), the
# painters' local arrays `_fvg_*`; fields of other instances read and written
# through `${v}_data` (kklass friend contract, D19), reads as `${d[F]-}`;
# fork-free and set -eu clean; no `[[ == ]]` / `case` / `${x//}` between two
# names (nocasematch): `[ "$a" = "$b" ]`; procedures leave RESULT as it was,
# getters answer in it; a refused call is rc 2 with RESULT='' and a kk.debug
# line, a malformed constructor list one `Error:` line.
#
# Every built-in virtual has its body in a plain function registered in
# fv.views' elision table __FV_VW_IMPL (fv.dialogs._register): the framework
# runs it without a kklass dispatch unless a class of yours overrides it.
#
# Friend uses of fv.views' private parts (the same framework; README
# "Contract and deviations"): reads of __FV_VW_LIVE, __FV_VW_GRP, __FV_VW_CRC,
# __FV_VW_ERRSYM, __FV_VW_PAD, __FV_VW_MAXW, __FV_VW_C2A, the disabled-command
# set __FV_VW_CMDOFF, the hooks __FV_VW_PUTEVENT and __FV_VW_TRK; entries added
# to __FV_VW_IMPL, __FV_VW_FUNC, the broadcast table __FV_VW_BCAST and the
# hot-key tables __FV_VW_HKS / __FV_VW_HKE (the cluster's item test); calls of
# fv.views._virt, _message, _viewEvent,
# _viewSetState, _windowEvent, _windowCalcBounds, _groupValid, _topView,
# _track, _hk, _hkDirty and _newReserved.

kk.uses kklass_pascal fv.views || return

# ---- constants (FV values; readonly once per process) -------------------------
# TButton Flags (FV bf*), TDialog Palette (FV dp*)
if [[ -z ${FV_BF_NORMAL+x} || ${FV_BF_NORMAL@a} != *r* ]]; then
    FV_BF_NORMAL=0 FV_BF_DEFAULT=1 FV_BF_LEFTJUST=2 FV_BF_BROADCAST=4 FV_BF_GRABFOCUS=8
    FV_DP_BLUEDIALOG=0 FV_DP_CYANDIALOG=1 FV_DP_GRAYDIALOG=2
    readonly FV_BF_NORMAL FV_BF_DEFAULT FV_BF_LEFTJUST FV_BF_BROADCAST FV_BF_GRABFOCUS \
        FV_DP_BLUEDIALOG FV_DP_CYANDIALOG FV_DP_GRAYDIALOG
fi

# ---- state ------------------------------------------------------------------
# Per view (keyed by its name), kept across a reload:
#   KIND[v]  btn / st / lbl / pt / cl: a live widget of this unit (its kind)
#   CK[v]    the key of the cached picture: what the rows were made from
#            (button: colours, palette, DownFlag, Flags, size, ASCII mode, Title;
#            label: colours, size, mode, Text; static text: colour, size,
#            mode, the text; cluster: mode and the items — its cell patterns)
#   CN[v]    the cached rows' count; RT[v.y] / RA[v.y] row y's text and
#            symbols (design §2.1 rule 2: a button's two rows, a label's,
#            a static text's wrapped rows; cluster rows are composed per draw
#            from the per-item patterns ${v}_cpl / _cpp / _cpw / _chot)
#   PK[p] / PN[p]  a TParamText's format and the arguments it takes (its
#            conversions, fv.dialogs._ptCount), counted once per text
declare -gA __FV_DG_KIND __FV_DG_CK __FV_DG_CN __FV_DG_RT __FV_DG_RA __FV_DG_PK __FV_DG_PN
__FV_DG_KIND+=() __FV_DG_CK+=() __FV_DG_CN+=() __FV_DG_RT+=() __FV_DG_RA+=() __FV_DG_PK+=() __FV_DG_PN+=()

# ---- the classes (FV dialogs.inc; fields design §1.2, virtuals §1.3) ---------

# TDialog.new NAME AX AY BX BY TITLE — FV TDialog.Init(Bounds, ATitle):
# TWindow's (number wnNoNumber), then GrowMode 0, Flags wfMove + wfClose,
# Palette dpGrayDialog. HandleEvent: Esc / Ctrl+F4 -> cmCancel posted, Enter
# -> the cmDefault broadcast posted, Ctrl+F5 -> cmResize (modal), cmOK
# cmCancel cmYes cmNo end the modal state
class TDialog : TWindow
    public
        constructor Create
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields override func Valid
        nofields override proc CalcBounds
end
TDialog.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.dialogs._dlgCreate "$this"
}
TDialog.HandleEvent() { fv.dialogs._dlgEvent "$this" "$@" || return; }
TDialog.GetPalette() { fv.dialogs._dlgGetPalette "$this" || return; }
TDialog.Valid() { fv.dialogs._dlgValid "$this" "$@" || return; }
TDialog.CalcBounds() { fv.dialogs._dlgCalcBounds "$this" "$@" || return; }
build TDialog

# TButton.new NAME AX AY BX BY TITLE COMMAND [FLAGS] — FV TButton.Init(Bounds,
# ATitle, ACommand, AFlags): TView's, then EventMask + evBroadcast, ofSelectable
# + ofFirstClick + ofPreProcess + ofPostProcess, sfDisabled when COMMAND is
# disabled, AmDefault from bfDefault. COMMAND: a command name; FLAGS: FV_BF_*
# bits. Refused before anything is made (rc 2, one Error line)
class TButton : TView
    public
        var Title
        var Command
        var Flags
        var AmDefault
        var DownFlag
        constructor Create
        nofields destructor Done
        nofields override proc Draw
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields override proc SetState
        nofields proc Press
end
TButton.Create() {
    fv.dialogs._btnArgs "$this" "$@" || return
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.dialogs._btnCreate "$this" "$5" "$6" "${7:-0}"
}
TButton.Done() { fv.dialogs._free "$this"; fv.views._done "$this"; }
TButton.Draw() { fv.dialogs._btnDraw "$this" || return; }
TButton.HandleEvent() { fv.dialogs._btnEvent "$this" "$@" || return; }
TButton.GetPalette() { fv.dialogs._btnGetPalette "$this" || return; }
TButton.SetState() { fv.dialogs._btnSetState "$this" "$@" || return; }
TButton.Press() { fv.dialogs._btnPress "$this" || return; }
build TButton

# TStaticText.new NAME AX AY BX BY TEXT — FV TStaticText.Init(Bounds, AText):
# the text word-wrapped (FV_UNICODE's algorithm), a line starting with ^C
# ($'\x03') centred, ^B ($'\x02') right-justified
class TStaticText : TView
    public
        var Text
        constructor Create
        nofields destructor Done
        nofields override proc Draw
        nofields override func GetPalette
        nofields func GetText
end
TStaticText.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.dialogs._stCreate "$this" "${5-}"
}
TStaticText.Done() { fv.dialogs._free "$this"; fv.views._done "$this"; }
TStaticText.Draw() { fv.dialogs._stDraw "$this" || return; }
TStaticText.GetPalette() { fv.dialogs._stGetPalette "$this" || return; }
TStaticText.GetText() { fv.dialogs._stGetText "$this" || return; }
build TStaticText

# TParamText.new NAME AX AY BX BY TEXT [PARAMCOUNT] — FV TParamText.Init: a
# static text whose GetText is `printf -v` of TEXT (FV's FormatStr) with the
# PARAMCOUNT parameters SetData gave it (${NAME}_params)
class TParamText : TStaticText
    public
        var ParamCount
        constructor Create
        nofields destructor Done
        nofields override func GetText
        nofields func DataSize
        nofields proc GetData
        nofields proc SetData
end
TParamText.Create() {
    fv.dialogs._ptArgs "$this" "${6-}" || return
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.dialogs._ptCreate "$this" "${6:-0}"
}
TParamText.Done() { unset "${this}_params"; fv.dialogs._free "$this"; fv.views._done "$this"; }
TParamText.GetText() { fv.dialogs._ptGetText "$this" || return; }
TParamText.DataSize() { fv.dialogs._ptDataSize "$this" || return; }
TParamText.GetData() { fv.dialogs._ptGetData "$this" "$@" || return; }
TParamText.SetData() { fv.dialogs._ptSetData "$this" "$@" || return; }
build TParamText

# TLabel.new NAME AX AY BX BY TEXT LINK — FV TLabel.Init(Bounds, AText, ALink):
# TStaticText's, then ofPreProcess + ofPostProcess, EventMask + evBroadcast;
# LINK = the view its hot key and a click focus ('' = none)
class TLabel : TStaticText
    public
        var Link
        var Light
        constructor Create
        nofields override proc Draw
        nofields override func GetPalette
        nofields override proc HandleEvent
end
TLabel.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.dialogs._lblCreate "$this" "${6-}"
}
TLabel.Draw() { fv.dialogs._lblDraw "$this" || return; }
TLabel.GetPalette() { fv.dialogs._lblGetPalette "$this" || return; }
TLabel.HandleEvent() { fv.dialogs._lblEvent "$this" "$@" || return; }
build TLabel

# TCluster.new NAME AX AY BX BY [ITEM]... — FV TCluster.Init(Bounds, AStrings):
# TView's, then ofSelectable + ofFirstClick + ofPreProcess + ofPostProcess,
# the items (FV's NewSItem chain written flat) in ${NAME}_items, Sel 0, the
# cursor at (2, 0) shown, EnableMask $FFFFFFFF. TCheckBoxes / TRadioButtons
# take the same arguments
class TCluster : TView
    public
        var Id
        var Value
        var Sel
        var EnableMask
        constructor Create
        nofields destructor Done
        nofields override proc Draw
        nofields override proc HandleEvent
        nofields override func GetPalette
        nofields override proc SetState
        nofields override func GetHelpCtx
        nofields func Mark
        nofields proc Press
        nofields proc MovedTo
        nofields func DataSize
        nofields proc GetData
        nofields proc SetData
end
TCluster.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    # (shift, not a "${@:N}" slice: no slice in this unit, see the README)
    if (( $# > 4 )); then shift 4; else set --; fi
    fv.dialogs._clCreate "$this" "$@"
}
TCluster.Done() { fv.dialogs._free "$this"; fv.views._done "$this"; }
TCluster.Draw() { fv.dialogs._clDraw "$this" || return; }
TCluster.HandleEvent() { fv.dialogs._clEvent "$this" "$@" || return; }
TCluster.GetPalette() { fv.dialogs._clGetPalette "$this" || return; }
TCluster.SetState() { fv.dialogs._clSetState "$this" "$@" || return; }
TCluster.GetHelpCtx() { fv.dialogs._clGetHelpCtx "$this" || return; }
TCluster.Mark() { fv.dialogs._clMark "$this" "$@" || return; }
TCluster.Press() { fv.dialogs._clPress "$this" "$@" || return; }
TCluster.MovedTo() { fv.dialogs._clMovedTo "$this" "$@" || return; }
TCluster.DataSize() { fv.dialogs._clDataSize "$this" || return; }
TCluster.GetData() { fv.dialogs._clGetData "$this" "$@" || return; }
TCluster.SetData() { fv.dialogs._clSetData "$this" "$@" || return; }
build TCluster

# TCheckBoxes (FV): ' [X] Item' per row, Value a bit mask, Press toggles
class TCheckBoxes : TCluster
    public
        nofields override proc Draw
        nofields override func Mark
        nofields override proc Press
end
TCheckBoxes.Draw() { fv.dialogs._cbDraw "$this" || return; }
TCheckBoxes.Mark() { fv.dialogs._cbMark "$this" "$@" || return; }
TCheckBoxes.Press() { fv.dialogs._cbPress "$this" "$@" || return; }
build TCheckBoxes

# TRadioButtons (FV): ' (*) Item' per row, Value the marked item; a move
# marks (MovedTo), SetData moves Sel too
class TRadioButtons : TCluster
    public
        nofields override proc Draw
        nofields override func Mark
        nofields override proc Press
        nofields override proc MovedTo
        nofields override proc SetData
end
TRadioButtons.Draw() { fv.dialogs._rbDraw "$this" || return; }
TRadioButtons.Mark() { fv.dialogs._rbMark "$this" "$@" || return; }
TRadioButtons.Press() { fv.dialogs._rbPress "$this" "$@" || return; }
TRadioButtons.MovedTo() { fv.dialogs._rbMovedTo "$this" "$@" || return; }
TRadioButtons.SetData() { fv.dialogs._rbSetData "$this" "$@" || return; }
build TRadioButtons

# fv.dialogs._register — the built-in bodies into fv.views' elision table,
# the broadcast reactions into its broadcast table (design §1.5) and the
# hot-key texts into its hot-key table (§3.1); fv.views merges the tables on
# a reload, and the constructors register again when an entry is missing
fv.dialogs._register() {
    __FV_VW_IMPL[TDialog.HandleEvent]=fv.dialogs._dlgEvent
    __FV_VW_IMPL[TDialog.GetPalette]=fv.dialogs._dlgGetPalette
    __FV_VW_IMPL[TDialog.Valid]=fv.dialogs._dlgValid
    __FV_VW_IMPL[TDialog.CalcBounds]=fv.dialogs._dlgCalcBounds
    __FV_VW_IMPL[TButton.Draw]=fv.dialogs._btnDraw
    __FV_VW_IMPL[TButton.HandleEvent]=fv.dialogs._btnEvent
    __FV_VW_IMPL[TButton.GetPalette]=fv.dialogs._btnGetPalette
    __FV_VW_IMPL[TButton.SetState]=fv.dialogs._btnSetState
    __FV_VW_IMPL[TButton.Press]=fv.dialogs._btnPress
    __FV_VW_IMPL[TStaticText.Draw]=fv.dialogs._stDraw
    __FV_VW_IMPL[TStaticText.GetPalette]=fv.dialogs._stGetPalette
    __FV_VW_IMPL[TStaticText.GetText]=fv.dialogs._stGetText
    __FV_VW_IMPL[TParamText.GetText]=fv.dialogs._ptGetText
    __FV_VW_IMPL[TParamText.DataSize]=fv.dialogs._ptDataSize
    __FV_VW_IMPL[TParamText.GetData]=fv.dialogs._ptGetData
    __FV_VW_IMPL[TParamText.SetData]=fv.dialogs._ptSetData
    __FV_VW_IMPL[TLabel.Draw]=fv.dialogs._lblDraw
    __FV_VW_IMPL[TLabel.GetPalette]=fv.dialogs._lblGetPalette
    __FV_VW_IMPL[TLabel.HandleEvent]=fv.dialogs._lblEvent
    __FV_VW_IMPL[TCluster.Draw]=fv.dialogs._clDraw
    __FV_VW_IMPL[TCluster.HandleEvent]=fv.dialogs._clEvent
    __FV_VW_IMPL[TCluster.GetPalette]=fv.dialogs._clGetPalette
    __FV_VW_IMPL[TCluster.SetState]=fv.dialogs._clSetState
    __FV_VW_IMPL[TCluster.GetHelpCtx]=fv.dialogs._clGetHelpCtx
    __FV_VW_IMPL[TCluster.Mark]=fv.dialogs._clMark
    __FV_VW_IMPL[TCluster.Press]=fv.dialogs._clPress
    __FV_VW_IMPL[TCluster.MovedTo]=fv.dialogs._clMovedTo
    __FV_VW_IMPL[TCluster.DataSize]=fv.dialogs._clDataSize
    __FV_VW_IMPL[TCluster.GetData]=fv.dialogs._clGetData
    __FV_VW_IMPL[TCluster.SetData]=fv.dialogs._clSetData
    __FV_VW_IMPL[TCheckBoxes.Draw]=fv.dialogs._cbDraw
    __FV_VW_IMPL[TCheckBoxes.Mark]=fv.dialogs._cbMark
    __FV_VW_IMPL[TCheckBoxes.Press]=fv.dialogs._cbPress
    __FV_VW_IMPL[TRadioButtons.Draw]=fv.dialogs._rbDraw
    __FV_VW_IMPL[TRadioButtons.Mark]=fv.dialogs._rbMark
    __FV_VW_IMPL[TRadioButtons.Press]=fv.dialogs._rbPress
    __FV_VW_IMPL[TRadioButtons.MovedTo]=fv.dialogs._rbMovedTo
    __FV_VW_IMPL[TRadioButtons.SetData]=fv.dialogs._rbSetData
    __FV_VW_FUNC[GetText]=1 __FV_VW_FUNC[Mark]=1 __FV_VW_FUNC[DataSize]=1
    __FV_VW_BCAST[fv.dialogs._dlgEvent]='cmSelectWindowNum'
    __FV_VW_BCAST[fv.dialogs._btnEvent]='cmDefault cmGrabDefault cmReleaseDefault cmCommandSetChanged'
    __FV_VW_BCAST[fv.dialogs._lblEvent]='cmReceivedFocus cmReleasedFocus'
    __FV_VW_BCAST[fv.dialogs._clEvent]=''
    __FV_VW_HKS[fv.dialogs._btnEvent]='_data[Title]'
    __FV_VW_HKS[fv.dialogs._lblEvent]='_data[Text]'
    __FV_VW_HKS[fv.dialogs._clEvent]='_items[@]'
    __FV_VW_HKE[fv.dialogs._clEvent]=fv.dialogs._clOn
}
fv.dialogs._register

# ---- helpers --------------------------------------------------------------------
# fv.dialogs._err MSG — one `Error: fv.dialogs: MSG` line on stderr unless
# VERBOSE_KKLASS=quiet (a constructor's loud refusal)
fv.dialogs._err() {
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then printf 'Error: fv.dialogs: %s\n' "$1" >&2; fi
    return 0
}
# fv.dialogs._bad CALLER MSG — a malformed call: RESULT='', a debug line, rc 2
fv.dialogs._bad() {
    RESULT=''
    kk.debug "Error: fv.dialogs.$1: $2"
    return 2
}
# fv.dialogs._kind V KIND... CALLER — rc 0 for a live widget of one of the
# KINDs (btn st lbl pt cl); else _bad's rc 2
fv.dialogs._kind() {
    local __fvg_k=${__FV_DG_KIND[${1:-.}]-} __fvg_a __fvg_n=0 __fvg_l=''
    # (each argument by a loop: "${@:2}" loses parts under a caller IFS holding \x01)
    for __fvg_a; do
        __fvg_n=$(( __fvg_n + 1 ))
        if (( __fvg_n == 1 || __fvg_n == $# )); then continue; fi
        __fvg_l+="$__fvg_a "
        if [[ -n $__fvg_k && -n ${__FV_VW_LIVE[$1]-} ]] && [ "$__fvg_a" = "$__fvg_k" ]; then return 0; fi
    done
    fv.dialogs._bad "${!#}" "'$1' is not a ${__fvg_l% } widget of fv.dialogs"
}
# fv.dialogs._cmd NAME — rc 0 for a command name (letters, digits, _)
fv.dialogs._cmd() {
    [[ -n $1 && $1 != *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* ]]
}
# fv.dialogs._num VALUE — rc 0 for 1-10 plain digits
fv.dialogs._num() {
    [[ -n $1 && $1 != *[!0123456789]* && ${#1} -le 10 ]]
}
# fv.dialogs._aname NAME — rc 0 when NAME may be a data array: an
# identifier, not RESULT, not starting with _fv / __fv in any case (this
# framework's globals and locals, which a nameref would reach instead)
fv.dialogs._aname() {
    [[ -n $1 && $1 != *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* && $1 != [0123456789]* \
       && $1 != _[fF][vV]* && $1 != __[fF][vV]* ]] && ! [ "$1" = RESULT ]
}
# fv.dialogs._free V — the widget's private entries: its cached rows, its
# kind, a cluster's items and patterns (the destructors; a name re-created
# over a live view starts clean too: the constructors call it first)
fv.dialogs._free() {
    local __fvg_y
    for (( __fvg_y = 0; __fvg_y < ${__FV_DG_CN[$1]:-0}; __fvg_y++ )); do
        unset "__FV_DG_RT[$1.$__fvg_y]" "__FV_DG_RA[$1.$__fvg_y]"
    done
    if [ "${__FV_DG_KIND[$1]-}" = cl ]; then unset "${1}_items" "${1}_cpl" "${1}_cpp" "${1}_cpw" "${1}_chot"; fi
    unset '__FV_DG_CK[$1]' '__FV_DG_CN[$1]' '__FV_DG_KIND[$1]' '__FV_DG_PK[$1]' '__FV_DG_PN[$1]'
    return 0
}
# fv.dialogs._impl V METHOD — the caller's __fvg_im = the body the elision
# runs for V's METHOD ('' = a class of yours overrides it)
fv.dialogs._impl() {
    __fvg_im=${1}_class
    __fvg_im="${!__fvg_im-}_class_method_owner[$2]" __fvg_im=${__FV_VW_IMPL[${!__fvg_im-}.$2]-}
}
# fv.dialogs._clear V — FV ClearEvent: the event handled by V
fv.dialogs._clear() { FV_EV_WHAT=evNothing FV_EV_INFO=$1; }
# fv.dialogs._post WHAT COMMAND INFO — FV PutEvent of a new event (the other
# fields empty); the caller's event record is put back afterwards
fv.dialogs._post() {
    local -a __fvg_es=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF" "${FV_EV_BASE-}")
    fv.drivers.clearEvent
    FV_EV_WHAT=$1 FV_EV_COMMAND=$2 FV_EV_INFO=$3
    "$__FV_VW_PUTEVENT" || :
    fv.dialogs._evBack
}
# (the record of the caller's __fvg_es back)
fv.dialogs._evBack() {
    FV_EV_WHAT=${__fvg_es[0]} FV_EV_KEY=${__fvg_es[1]} FV_EV_CHAR=${__fvg_es[2]} FV_EV_COMMAND=${__fvg_es[3]}
    FV_EV_ID=${__fvg_es[4]} FV_EV_INFO=${__fvg_es[5]} FV_EV_MOUSE_X=${__fvg_es[6]} FV_EV_MOUSE_Y=${__fvg_es[7]}
    FV_EV_MOUSE_BUTTONS=${__fvg_es[8]} FV_EV_MOUSE_MODS=${__fvg_es[9]} FV_EV_MOUSE_DOUBLE=${__fvg_es[10]}
    FV_EV_MOUSE_TRIPLE=${__fvg_es[11]} FV_EV_WHEEL=${__fvg_es[12]} FV_EV_EOF=${__fvg_es[13]} FV_EV_BASE=${__fvg_es[14]-}
}
# fv.dialogs._hot TEXT — the caller's __fvg_c = FV HotKey(TEXT): the
# character after the first `~` ('' when none). A UTF-8 caller or ASCII text
fv.dialogs._hot() {
    __fvg_c=${1#*'~'}
    if [ "$__fvg_c" = "$1" ]; then __fvg_c=''; else __fvg_c=${__fvg_c:0:1}; fi
}
# fv.dialogs._post1 V — the caller's __fvg_p = 1 when V's owner is in
# phPostProcess (FV: a plain hot letter counts there)
fv.dialogs._post1() {
    local __fvg_o="${1}_data[Owner]"
    __fvg_o=${!__fvg_o-}
    if [[ -n $__fvg_o ]]; then
        __fvg_o="${__fvg_o}_data[Phase]"
        if [ "${!__fvg_o-}" = phPostProcess ]; then __fvg_p=1; fi
    fi
    return 0
}
# fv.dialogs._cutw TEXT N — the caller's __fvg_ct = TEXT cut to at most N
# cells by fv.video's clusters (a wide one that does not fit is left out),
# __fvg_cw its cells (no `~` processing)
fv.dialogs._cutw() {
    local __fvg_i
    local -a _fvg_cl _fvg_cc
    __fvg_ct='' __fvg_cw=0
    if [[ $1 != $__FV_VS_PNA ]]; then __fvg_ct=${1:0:$2} __fvg_cw=${#__fvg_ct}; return 0; fi
    fv.video.clusters "$1" _fvg_cl _fvg_cc || :
    for (( __fvg_i = 0; __fvg_i < ${#_fvg_cl[@]}; __fvg_i++ )); do
        if (( __fvg_cw + _fvg_cc[__fvg_i] > $2 )); then break; fi
        __fvg_ct+=${_fvg_cl[__fvg_i]} __fvg_cw=$(( __fvg_cw + _fvg_cc[__fvg_i] ))
    done
}
# fv.dialogs._u8 — rc 0 when a non-ASCII text needs fv.video's locale guard
# (the caller's locale does not take a UTF-8 character for one)
fv.dialogs._u8() { [[ ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; }

# fv.dialogs._cstr TEXT LO HI MAX — FV MoveCStr into the caller's __fvg_ct
# (the text, `~` dropped), __fvg_ca (one symbol per display cell: LO, or HI
# between `~` marks) and __fvg_cw (the cells), cut to MAX cells (a cluster
# that does not fit ends it). Cells from fv.video (fv.video.clusters: wide
# characters, ASCII mode's one cell per character); printable ASCII takes a
# fast path. Under fv.video's guard (the composers call it there)
fv.dialogs._cstr() {
    local __fvg_x=$1 __fvg_r __fvg_h=0 __fvg_y __fvg_q __fvg_i __fvg_z
    local -a _fvg_cl _fvg_cc
    __fvg_ct='' __fvg_ca='' __fvg_cw=0
    while (( __fvg_cw < $4 )); do
        __fvg_r=${__fvg_x%%'~'*} __fvg_z=0
        if [ "$__fvg_r" = "$__fvg_x" ]; then __fvg_z=1; fi
        if (( __fvg_h )); then __fvg_y=$3; else __fvg_y=$2; fi
        if [[ -n $__fvg_r ]]; then
            if [[ $__fvg_r != $__FV_VS_PNA ]]; then
                if (( __fvg_cw + ${#__fvg_r} > $4 )); then __fvg_r=${__fvg_r:0:$4-__fvg_cw}; fi
                __fvg_q=${__FV_VW_PAD:0:${#__fvg_r}}
                __fvg_ct+=$__fvg_r __fvg_ca+=${__fvg_q// /"$__fvg_y"} __fvg_cw=$(( __fvg_cw + ${#__fvg_r} ))
            else
                fv.video.clusters "$__fvg_r" _fvg_cl _fvg_cc || :
                for (( __fvg_i = 0; __fvg_i < ${#_fvg_cl[@]}; __fvg_i++ )); do
                    if (( __fvg_cw + _fvg_cc[__fvg_i] > $4 )); then __fvg_z=1; break; fi
                    __fvg_ct+=${_fvg_cl[__fvg_i]} __fvg_ca+=$__fvg_y
                    if (( _fvg_cc[__fvg_i] == 2 )); then __fvg_ca+=$__fvg_y; fi
                    __fvg_cw=$(( __fvg_cw + _fvg_cc[__fvg_i] ))
                done
            fi
        fi
        if (( __fvg_z )); then break; fi
        __fvg_x=${__fvg_x#*'~'} __fvg_h=$(( ! __fvg_h ))
    done
}
# fv.dialogs._rep SYM N — the caller's __fvg_rp = SYM N times
fv.dialogs._rep() {
    __fvg_rp=''
    if (( $2 > 0 )); then __fvg_rp=${__FV_VW_PAD:0:$2} __fvg_rp=${__fvg_rp// /"$1"}; fi
}
# fv.dialogs._rows V — the cached rows of V written: one writeLine (one row)
# or one writeLines (design §2.1 rule 1)
fv.dialogs._rows() {
    local __fvg_n=${__FV_DG_CN[$1]:-0} __fvg_y
    if (( __fvg_n == 1 )); then fv.views.writeLine 0 0 1 "${__FV_DG_RT[$1.0]}" "${__FV_DG_RA[$1.0]}" || :; return 0; fi
    local -a _fvg_t=() _fvg_a=()
    for (( __fvg_y = 0; __fvg_y < __fvg_n; __fvg_y++ )); do
        _fvg_t[__fvg_y]=${__FV_DG_RT[$1.$__fvg_y]} _fvg_a[__fvg_y]=${__FV_DG_RA[$1.$__fvg_y]}
    done
    if (( __fvg_n )); then fv.views.writeLines 0 0 _fvg_t _fvg_a || :; fi
    return 0
}
# fv.dialogs._keep V ROWS... — the composed rows (text, symbols, text,
# symbols, ...) become V's cached picture under the caller's key __fvg_k
fv.dialogs._keep() {
    local __fvg_y=0 __fvg_v=$1 __fvg_n
    shift
    while (( $# >= 2 )); do
        __FV_DG_RT[$__fvg_v.$__fvg_y]=$1 __FV_DG_RA[$__fvg_v.$__fvg_y]=$2
        __fvg_y=$(( __fvg_y + 1 ))
        shift 2
    done
    for (( __fvg_n = __fvg_y; __fvg_n < ${__FV_DG_CN[$__fvg_v]:-0}; __fvg_n++ )); do
        unset "__FV_DG_RT[$__fvg_v.$__fvg_n]" "__FV_DG_RA[$__fvg_v.$__fvg_n]"
    done
    __FV_DG_CN[$__fvg_v]=$__fvg_y __FV_DG_CK[$__fvg_v]=$__fvg_k
}
# fv.dialogs._guard — rc 0 when the caller's state needs fv.video's guard
# for the text work (nocasematch, no globasciiranges, a locale that does not
# take a UTF-8 character for one), and the guard is not running yet
fv.dialogs._guard() {
    [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]
}

# ---- TDialog (FV dialogs.inc TDialog) -------------------------------------------
fv.dialogs._dlgCreate() {
    local -n __fvg_d=${1}_data
    __fvg_d[GrowMode]=0 __fvg_d[Flags]=$(( FV_WF_MOVE | FV_WF_CLOSE )) __fvg_d[Palette]=$FV_DP_GRAYDIALOG
    if [[ -z ${__FV_VW_IMPL[TDialog.HandleEvent]-} ]]; then fv.dialogs._register; fi
    fv.views.resetPalette "$1" || :
}
# TDialog.GetPalette (func) — FV CBlueDialog / CCyanDialog / CGrayDialog by
# Palette (dpBlueDialog 0, dpCyanDialog 1, dpGrayDialog 2): CAppColor 64-95
# (FV's 30th entry is 92, not 93: kept), 96-127, 32-63
fv.dialogs._dlgGetPalette() {
    local -n __fvg_d=${1}_data
    case ${__fvg_d[Palette]:-2} in
        0) RESULT='64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 92 94 95' ;;
        1) RESULT='96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127' ;;
        *) RESULT='32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63' ;;
    esac
}
# TDialog.Valid CMD (func; rc 0 = valid) — FV: cmCancel is always valid;
# any other command asks the subviews (TGroup.Valid)
fv.dialogs._dlgValid() {
    if [ "${2-}" = cmCancel ]; then RESULT=1; return 0; fi
    fv.views._groupValid "$@" || return
}
# TDialog.HandleEvent — FV: TWindow's, then evKeyDown kbEsc / kbCtrlF4 ->
# evCommand cmCancel posted, kbCtrlF5 (modal) -> cmResize posted, kbEnter ->
# evBroadcast cmDefault posted (each handled); evCommand cmOK cmCancel cmYes
# cmNo while modal -> EndModal(command), handled
fv.dialogs._dlgEvent() {
    fv.views._windowEvent "$1"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbEsc ] || [ "$FV_EV_KEY" = kbCtrlF4 ]; then
            fv.dialogs._post evCommand cmCancel ''; fv.dialogs._clear "$1"
        elif [ "$FV_EV_KEY" = kbEnter ]; then
            fv.dialogs._post evBroadcast cmDefault ''; fv.dialogs._clear "$1"
        elif [ "$FV_EV_KEY" = kbCtrlF5 ] && [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
            local -n __fvg_d=${1}_data
            if (( ${__fvg_d[State]:-0} & FV_SF_MODAL )); then fv.dialogs._post evCommand cmResize ''; fv.dialogs._clear "$1"; fi
        fi
    elif [ "$FV_EV_WHAT" = evCommand ] && [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        if [ "$FV_EV_COMMAND" = cmOK ] || [ "$FV_EV_COMMAND" = cmCancel ] || [ "$FV_EV_COMMAND" = cmYes ] || [ "$FV_EV_COMMAND" = cmNo ]; then
            local -n __fvg_d=${1}_data
            if (( ${__fvg_d[State]:-0} & FV_SF_MODAL )); then
                fv.views._virt "$1" EndModal "$FV_EV_COMMAND" || :
                fv.dialogs._clear "$1"
            fi
        fi
    fi
    return 0
}
# TDialog.CalcBounds DX DY — FPC 2025: GrowMode set -> TWindow's; else the
# dialog keeps its place in proportion to the margins (FV MoveRel: a one-cell
# growth moves it toward the larger margin, else the margins scale, Pascal's
# Round). Answer: FV_RECT_AX/_AY/_BX/_BY
fv.dialogs._dlgCalcBounds() {
    local -n __fvg_d=${1}_data
    if (( ${__fvg_d[GrowMode]:-0} )); then fv.views._windowCalcBounds "$@" || return; return 0; fi
    local __fvg_o=${__fvg_d[Owner]-} __fvg_ax=${__fvg_d[OriginX]:-0} __fvg_ay=${__fvg_d[OriginY]:-0} __fvg_na __fvg_nb
    FV_RECT_AX=$__fvg_ax FV_RECT_AY=$__fvg_ay
    FV_RECT_BX=$(( __fvg_ax + ${__fvg_d[SizeX]:-0} )) FV_RECT_BY=$(( __fvg_ay + ${__fvg_d[SizeY]:-0} ))
    local -a __fvw_v
    if [[ -z $__fvg_o || -z ${__FV_VW_LIVE[$__fvg_o]-} ]] || ! fv.views._ints "${2-0}" "${3-0}"; then return 0; fi
    local -n __fvg_od=${__fvg_o}_data
    fv.dialogs._moveRel "${__fvg_od[SizeX]:-0}" "${__fvw_v[0]}" "$FV_RECT_AX" "$FV_RECT_BX"
    FV_RECT_AX=$__fvg_na FV_RECT_BX=$__fvg_nb
    fv.dialogs._moveRel "${__fvg_od[SizeY]:-0}" "${__fvw_v[1]}" "$FV_RECT_AY" "$FV_RECT_BY"
    FV_RECT_AY=$__fvg_na FV_RECT_BY=$__fvg_nb
    return 0
}
# fv.dialogs._moveRel S D A B — FV TDialog.CalcBounds' MoveRel (owner size S
# after the growth D, the old edges A B): the caller's __fvg_na / __fvg_nb
fv.dialogs._moveRel() {
    local __fvg_i=$(( $1 - $2 - $4 )) __fvg_k=$(( $1 - $2 - $4 + $3 )) __fvg_m=$(( $1 - $4 + $3 )) __fvg_n
    local __fvg_p __fvg_q __fvg_r __fvg_s=1
    if (( $2 == 1 && $3 - __fvg_i <= 1 && __fvg_i - $3 <= 1 )); then
        __fvg_n=$3
        if (( $3 < __fvg_i )); then __fvg_n=$(( __fvg_n + 1 )); fi
    elif (( __fvg_k != 0 )); then
        # (Pascal's Round of M*rA/K: to the nearest, a half to the even)
        __fvg_p=$(( __fvg_m * $3 )) __fvg_q=$__fvg_k
        if (( __fvg_q < 0 )); then __fvg_p=$(( -__fvg_p )) __fvg_q=$(( -__fvg_q )); fi
        if (( __fvg_p < 0 )); then __fvg_s=-1; fi
        __fvg_n=$(( __fvg_p / __fvg_q )) __fvg_r=$(( __fvg_p % __fvg_q ))
        if (( __fvg_r < 0 )); then __fvg_r=$(( -__fvg_r )); fi
        if (( 2 * __fvg_r > __fvg_q || (2 * __fvg_r == __fvg_q && __fvg_n % 2 != 0) )); then __fvg_n=$(( __fvg_n + __fvg_s )); fi
    else
        __fvg_n=$(( (__fvg_m < 0 ? -__fvg_m : __fvg_m) >> 1 ))
    fi
    __fvg_na=$__fvg_n __fvg_nb=$(( $4 + __fvg_n - $3 ))
}

# ---- TButton (FV dialogs.inc TButton) -------------------------------------------
# fv.dialogs._btnArgs B AX AY BX BY TITLE COMMAND [FLAGS] — the refusals
fv.dialogs._btnArgs() {
    if (( $# < 7 )) || ! fv.dialogs._cmd "$7" || { (( $# >= 8 )) && ! fv.dialogs._num "$8"; }; then
        local __fvg_b=$1 IFS=' '
        shift
        fv.dialogs._err "TButton.Create: '$__fvg_b': the arguments are AX AY BX BY TITLE COMMAND [FLAGS] (a command name; FLAGS digits) (got: $*)"
        __FV_VW_CRC=2
        return 2
    fi
}
fv.dialogs._btnCreate() {   # B TITLE COMMAND FLAGS
    local -n __fvg_d=${1}_data
    fv.dialogs._free "$1"
    if [[ -z ${__FV_VW_IMPL[TButton.Draw]-} ]]; then fv.dialogs._register; fi
    __fvg_d[EventMask]=$(( ${__fvg_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __fvg_d[Options]=$(( ${__fvg_d[Options]:-0} | FV_OF_SELECTABLE | FV_OF_FIRSTCLICK | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    if [[ -n ${__FV_VW_CMDOFF[$3]-} ]]; then __fvg_d[State]=$(( ${__fvg_d[State]:-0} | FV_SF_DISABLED )); fi
    __fvg_d[Flags]=$(( 10#$4 )) __fvg_d[Title]=$2 __fvg_d[Command]=$3 __fvg_d[DownFlag]=0 __fvg_d[AmDefault]=0
    if (( 10#$4 & FV_BF_DEFAULT )); then __fvg_d[AmDefault]=1; fi
    __FV_DG_KIND[$1]=btn
}
# TButton.GetPalette (func) — FV CButton 10 11 12 13 14 14 14 15
fv.dialogs._btnGetPalette() { RESULT='10 11 12 13 14 14 14 15'; }
# fv.dialogs._btnPic B — the caller's __fvg_pc = the button's colour pair
# (FV Draw's GetColor word: the text entry and the shortcut entry): 44
# disabled, 37 active + selected, 26 active + AmDefault, else 15 — what
# P3-12 compares before and after a state change
fv.dialogs._btnPic() {
    local -n __fvg_pd=${1}_data
    local __fvg_s=${__fvg_pd[State]:-0}
    if (( __fvg_s & FV_SF_DISABLED )); then __fvg_pc=44
    elif (( (__fvg_s & FV_SF_ACTIVE) && (__fvg_s & FV_SF_SELECTED) )); then __fvg_pc=37
    elif (( (__fvg_s & FV_SF_ACTIVE) )) && [ "${__fvg_pd[AmDefault]-}" = 1 ]; then __fvg_pc=26
    else __fvg_pc=15; fi
}
# TButton.Draw — FV's (FV_UNICODE): row 0 the title centred (bfLeftJust: from
# cell 1) with its `~` letter in the shortcut colour, the last cell the shadow
# `▄` in colour 8; row 1 a blank and `▀`s in colour 8. Pressed (DownFlag): the
# title one cell right, row 0's last cell in the button's colour, row 1
# blanks. ASCII mode: no shadow characters (blanks, design §2.7). Rows past
# the second: blanks in colour 8 ("Draw must cover its rect"). The rows are
# cached by what makes them (design §2.1 rule 2): one writeLines
fv.dialogs._btnDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvg_d=${1}_data
    local __fvg_pc __fvg_k
    fv.dialogs._btnPic "$1"
    __fvg_k="$__fvg_pc|$FV_DRAW_PAL|${__fvg_d[DownFlag]:-0}|${__fvg_d[Flags]:-0}|${__fvg_d[SizeX]:-0}|${__fvg_d[SizeY]:-0}|${FV_VIDEO_ASCII:-0}|${__fvg_d[Title]-}"
    if ! [ "${__FV_DG_CK[$1]-}" = "$__fvg_k" ]; then fv.dialogs._btnRows "$1"; fi
    fv.dialogs._rows "$1"
}
# fv.dialogs._btnRows B — the button's rows composed and kept (the caller's
# __fvg_pc, __fvg_k)
fv.dialogs._btnRows() {
    if fv.dialogs._guard; then fv.video._g fv.dialogs._btnRows "$1"; return; fi
    local -n __fvg_d=${1}_data
    local __fvg_p=$FV_DRAW_PAL __fvg_e=$__FV_VW_ERRSYM __fvg_t=${__fvg_d[Title]-} __fvg_dn=${__fvg_d[DownFlag]:-0}
    local __fvg_sx=${__fvg_d[SizeX]:-0} __fvg_sy=${__fvg_d[SizeY]:-0} __fvg_lo __fvg_hi __fvg_s8 __fvg_i __fvg_r0 __fvg_a0
    local __fvg_ct __fvg_ca __fvg_cw __fvg_rp __fvg_pr='' __fvg_pa='' __fvg_room __fvg_y __fvg_c1 __fvg_c2
    local -a __fvg_rr=()
    __fvg_lo=${__fvg_p:${__fvg_pc:0:1}-1:1} __fvg_hi=${__fvg_p:${__fvg_pc:1:1}-1:1} __fvg_s8=${__fvg_p:7:1}
    __fvg_lo=${__fvg_lo:-$__fvg_e} __fvg_hi=${__fvg_hi:-$__fvg_e} __fvg_s8=${__fvg_s8:-$__fvg_e}
    if (( __fvg_sx < 1 || __fvg_sy < 1 )); then fv.dialogs._keep "$1"; return 0; fi
    if [ "$__fvg_dn" = 1 ]; then __fvg_pr=' ' __fvg_pa=$__fvg_s8; fi
    __fvg_ct='' __fvg_ca='' __fvg_cw=0
    if [[ -n $__fvg_t ]]; then
        fv.dialogs._cstr "$__fvg_t" "$__fvg_lo" "$__fvg_hi" "$__FV_VW_MAXW"
        if (( ${__fvg_d[Flags]:-0} & FV_BF_LEFTJUST )); then __fvg_i=1; else __fvg_i=$(( (__fvg_sx - __fvg_cw) / 2 )); fi
        if (( __fvg_i < 0 )); then __fvg_i=0; fi
        fv.dialogs._rep "$__fvg_lo" "$__fvg_i"
        __fvg_pr+=${__FV_VW_PAD:0:__fvg_i} __fvg_pa+=$__fvg_rp
    fi
    __fvg_room=$(( __fvg_sx - 1 - ${#__fvg_pa} ))
    if (( __fvg_room < 0 )); then __fvg_pr=${__fvg_pr:0:__fvg_sx-1} __fvg_pa=${__fvg_pa:0:__fvg_sx-1} __fvg_room=0; fi
    if (( __fvg_cw > __fvg_room )); then fv.dialogs._cstr "$__fvg_t" "$__fvg_lo" "$__fvg_hi" "$__fvg_room"; fi
    fv.dialogs._rep "$__fvg_lo" "$(( __fvg_room - __fvg_cw ))"
    __fvg_r0=$__fvg_pr$__fvg_ct${__FV_VW_PAD:0:__fvg_room-__fvg_cw} __fvg_a0=$__fvg_pa$__fvg_ca$__fvg_rp
    # (the last cell: the shadow's `▄` when a second row follows, else blank)
    if [ "$__fvg_dn" = 1 ]; then __fvg_r0+=' ' __fvg_a0+=$__fvg_lo
    elif (( __fvg_sy > 1 )) && ! [ "${FV_VIDEO_ASCII:-0}" = 1 ]; then __fvg_r0+='▄' __fvg_a0+=$__fvg_s8
    else __fvg_r0+=' ' __fvg_a0+=$__fvg_s8; fi
    __fvg_rr=("$__fvg_r0" "$__fvg_a0")
    if (( __fvg_sy > 1 )); then
        fv.dialogs._rep "$__fvg_s8" "$__fvg_sx"
        __fvg_c1=${__FV_VW_PAD:0:__fvg_sx-1}
        if ! [ "$__fvg_dn" = 1 ] && ! [ "${FV_VIDEO_ASCII:-0}" = 1 ]; then __fvg_c1=${__fvg_c1// /▀}; fi
        __fvg_c2=${__FV_VW_PAD:0:__fvg_sx}
        __fvg_rr+=(" $__fvg_c1" "$__fvg_rp")
        for (( __fvg_y = 2; __fvg_y < __fvg_sy; __fvg_y++ )); do __fvg_rr+=("$__fvg_c2" "$__fvg_rp"); done
    fi
    fv.dialogs._keep "$1" "${__fvg_rr[@]}"
}
# TButton.SetState BIT ENABLE — FV: TView's; sfSelected / sfActive -> the
# button redrawn, P3-12: only when its colours change; sfFocused -> MakeDefault
fv.dialogs._btnSetState() {
    local __fvg_pc __fvg_o
    fv.dialogs._btnPic "$1"
    __fvg_o=$__fvg_pc
    fv.views._viewSetState "$@"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( $2 & (FV_SF_SELECTED | FV_SF_ACTIVE) )); then
        fv.dialogs._btnPic "$1"
        if ! [ "$__fvg_pc" = "$__fvg_o" ]; then fv.views.drawView "$1" || :; fi
    fi
    if (( $2 & FV_SF_FOCUSED )); then fv.dialogs._btnDefault "$1" "$3"; fi
    return 0
}
# fv.dialogs._btnDefault B ENABLE — FV MakeDefault: a button without
# bfDefault broadcasts cmGrabDefault / cmReleaseDefault to its owner (the
# default button gives the look up / takes it back) and sets AmDefault;
# redrawn when its colours change (P3-12)
fv.dialogs._btnDefault() {
    local -n __fvg_d=${1}_data
    local __fvg_pc __fvg_o __fvg_w=${__fvg_d[Owner]-}
    if (( ${__fvg_d[Flags]:-0} & FV_BF_DEFAULT )); then return 0; fi
    fv.dialogs._btnPic "$1"
    __fvg_o=$__fvg_pc
    if [[ -n $__fvg_w && -n ${__FV_VW_LIVE[$__fvg_w]-} ]]; then
        if (( $2 )); then fv.views._message "$__fvg_w" evBroadcast cmGrabDefault "$1" || :
        else fv.views._message "$__fvg_w" evBroadcast cmReleaseDefault "$1" || :; fi
    fi
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    __fvg_d[AmDefault]=$(( $2 ? 1 : 0 ))
    fv.dialogs._btnPic "$1"
    if ! [ "$__fvg_pc" = "$__fvg_o" ]; then fv.views.drawView "$1" || :; fi
}
# TButton.Press — FV: the cmRecordHistory broadcast to the owner (every
# THistory records its line), then with bfBroadcast the broadcast of Command
# to the owner (FV_EV_INFO = the button), else evCommand Command posted
# (FV_EV_INFO = the button)
fv.dialogs._btnPress() {
    local -n __fvg_d=${1}_data
    local __fvg_w=${__fvg_d[Owner]-} __fvg_c=${__fvg_d[Command]-} __fvg_rr=${RESULT-}
    if [[ -n $__fvg_w && -n ${__FV_VW_LIVE[$__fvg_w]-} ]]; then fv.views._message "$__fvg_w" evBroadcast cmRecordHistory '' || :; fi
    if [[ -z $__fvg_c || -z ${__FV_VW_LIVE[$1]-} ]]; then RESULT=$__fvg_rr; return 0; fi
    if (( ${__fvg_d[Flags]:-0} & FV_BF_BROADCAST )); then
        if [[ -n $__fvg_w && -n ${__FV_VW_LIVE[$__fvg_w]-} ]]; then fv.views._message "$__fvg_w" evBroadcast "$__fvg_c" "$1" || :; fi
    else
        fv.dialogs._post evCommand "$__fvg_c" "$1"
    fi
    RESULT=$__fvg_rr
    return 0
}
# fv.dialogs._btnState B DOWN — FV DrawState: DownFlag := DOWN, drawn
fv.dialogs._btnState() {
    local -n __fvg_d=${1}_data
    __fvg_d[DownFlag]=$2
    fv.views.drawView "$1" || :
}
# TButton.HandleEvent — FV:
#   * evMouseDown (enabled): with bfGrabFocus TView's click to focus first
#     (without it a click does not focus the button: FV); the press tracking
#     (the pressed look while the mouse is on the button, its shadow
#     included: FV's ButRect), released on it -> Press, the look back; handled;
#   * evKeyDown: Alt + the title's hot letter, the plain letter in the
#     owner's phPostProcess, or (focused) Space / Enter -> pressed look, Press,
#     handled, the look back (through fv.views' hot-key helper: any layout);
#   * evBroadcast cmDefault (AmDefault, enabled) -> Press, handled;
#     cmGrabDefault / cmReleaseDefault (bfDefault) -> AmDefault; and
#     cmCommandSetChanged -> sfDisabled follows Command (each redrawn only
#     when its colours change: P3-12)
fv.dialogs._btnEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then fv.dialogs._btnKey "$1"
    elif [ "$FV_EV_WHAT" = evBroadcast ]; then fv.dialogs._btnBcast "$1"
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then fv.dialogs._btnMouse "$1"; fi
    return 0
}
fv.dialogs._btnKey() {
    local -n __fvg_d=${1}_data
    local __fvg_t=${__fvg_d[Title]-} __fvg_c __fvg_p=0
    if [[ $__fvg_t == *[![:ascii:]]* ]] && fv.dialogs._u8 && [[ -z ${__fvv_g-} ]]; then fv.video._g fv.dialogs._btnKey "$1"; return 0; fi
    fv.dialogs._hot "$__fvg_t"
    fv.dialogs._post1 "$1"
    if { [[ -n $__fvg_c ]] && fv.views._hk "$__fvg_c" "$__fvg_p" "$1"; } \
       || { (( ${__fvg_d[State]:-0} & FV_SF_FOCUSED )) && { [ "$FV_EV_KEY" = kbEnter ] || { [ "$FV_EV_KEY" = kbChar ] && [ "$FV_EV_CHAR" = ' ' ]; }; }; }; then
        fv.dialogs._btnState "$1" 1
        fv.views._virt "$1" Press || :
        fv.dialogs._clear "$1"
        if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.dialogs._btnState "$1" 0; fi
    fi
}
fv.dialogs._btnBcast() {
    local -n __fvg_d=${1}_data
    local __fvg_pc __fvg_o
    if [ "$FV_EV_COMMAND" = cmDefault ]; then
        if [ "${__fvg_d[AmDefault]-}" = 1 ] && (( ! (${__fvg_d[State]:-0} & FV_SF_DISABLED) )); then
            fv.views._virt "$1" Press || :
            fv.dialogs._clear "$1"
        fi
        return 0
    fi
    fv.dialogs._btnPic "$1"
    __fvg_o=$__fvg_pc
    if [ "$FV_EV_COMMAND" = cmGrabDefault ] || [ "$FV_EV_COMMAND" = cmReleaseDefault ]; then
        if (( ! (${__fvg_d[Flags]:-0} & FV_BF_DEFAULT) )); then return 0; fi
        __fvg_d[AmDefault]=0
        if [ "$FV_EV_COMMAND" = cmReleaseDefault ]; then __fvg_d[AmDefault]=1; fi
    elif [ "$FV_EV_COMMAND" = cmCommandSetChanged ]; then
        if [[ -n ${__FV_VW_CMDOFF[${__fvg_d[Command]:-.}]-} ]]; then fv.views._virt "$1" SetState "$FV_SF_DISABLED" 1 || :
        else fv.views._virt "$1" SetState "$FV_SF_DISABLED" 0 || :; fi
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    else
        return 0
    fi
    fv.dialogs._btnPic "$1"
    if ! [ "$__fvg_pc" = "$__fvg_o" ]; then fv.views.drawView "$1" || :; fi
}
fv.dialogs._btnMouse() {
    local -n __fvg_d=${1}_data
    local __fvg_dn=0 __fvg_in __fvg_up=0
    if (( ${__fvg_d[Flags]:-0} & FV_BF_GRABFOCUS )); then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" != evMouseDown ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    fi
    if (( ${__fvg_d[State]:-0} & FV_SF_DISABLED )); then fv.dialogs._clear "$1"; return 0; fi
    local -a __fvg_es=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF" "${FV_EV_BASE-}")
    # (FV's ButRect: the button and its shadow, Size + (2, 1))
    __FV_VW_TRK=''
    while :; do
        fv.dialogs._btnIn "$1"
        if (( __fvg_in != __fvg_dn )); then __fvg_dn=$__fvg_in; fv.dialogs._btnState "$1" "$__fvg_dn"; fi
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
        fv.views._track "$1" "$FV_EM_MOUSEMOVE" || break
    done
    # (the release's own place decides, as fv.views' frame icons: a terminal
    # that reports no motion while a button is held)
    if [ "$FV_EV_WHAT" = evMouseUp ]; then fv.dialogs._btnIn "$1"; __fvg_up=1; fi
    fv.dialogs._evBack
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( __fvg_up && __fvg_in )); then
        fv.views._virt "$1" Press || :
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || { fv.dialogs._clear "$1"; return 0; }
    fi
    if [ "${__fvg_d[DownFlag]:-0}" = 1 ]; then fv.dialogs._btnState "$1" 0; fi
    fv.dialogs._clear "$1"
}
# (the caller's __fvg_in: 1 when the mouse is on the button or its shadow)
fv.dialogs._btnIn() {
    __fvg_in=0
    fv.views.makeLocal "$1" "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" || return 0
    local -n __fvg_bd=${1}_data
    if (( FV_POINT_X >= 0 && FV_POINT_Y >= 0 && FV_POINT_X < ${__fvg_bd[SizeX]:-0} + 2 && FV_POINT_Y < ${__fvg_bd[SizeY]:-0} + 1 )); then __fvg_in=1; fi
}

# ---- TStaticText, TParamText, TLabel (FV dialogs.inc) -----------------------------
fv.dialogs._stCreate() {   # S TEXT
    local -n __fvg_d=${1}_data
    fv.dialogs._free "$1"
    if [[ -z ${__FV_VW_IMPL[TStaticText.Draw]-} ]]; then fv.dialogs._register; fi
    __fvg_d[Text]=$2
    __FV_DG_KIND[$1]=st
}
# TStaticText.GetPalette (func) — FV CStaticText 6 7 8 9
fv.dialogs._stGetPalette() { RESULT='6 7 8 9'; }
# TStaticText.GetText (func) — FV: the Text field
fv.dialogs._stGetText() {
    local -n __fvg_d=${1}_data
    RESULT=${__fvg_d[Text]-}
}
# TStaticText.Draw — FV_UNICODE's TStaticText.Draw over GetText (virtual): the
# text in colour 1, word-wrapped at the view's width, a line that starts with
# ^C centred and ^B right-justified, CR / LF / CRLF end a line, the rows
# below blank. The rows cached by text, colour, size and mode: one writeLines
fv.dialogs._stDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvg_d=${1}_data
    local __fvg_rr=${RESULT-} __fvg_s __fvg_k
    RESULT=''
    fv.views._virt "$1" GetText || RESULT=''
    __fvg_s=${RESULT-} RESULT=$__fvg_rr
    __fvg_k="${FV_DRAW_PAL:0:1}|${__fvg_d[SizeX]:-0}|${__fvg_d[SizeY]:-0}|${FV_VIDEO_ASCII:-0}|$__fvg_s"
    if ! [ "${__FV_DG_CK[$1]-}" = "$__fvg_k" ]; then fv.dialogs._stRows "$1" "$__fvg_s"; fi
    fv.dialogs._rows "$1"
}
# fv.dialogs._stRows S TEXT — FV_UNICODE's wrap over TEXT's clusters (the
# caller's __fvg_k): a line breaks when its cells reach the width (at the
# last blank, which the next line keeps at its start, else at the last
# cluster that fits), or at CR / LF / CRLF; ^B / ^C as a line's first
# character set its justification (they take no cell elsewhere); another
# control character is fv.video's `?`
fv.dialogs._stRows() {
    if fv.dialogs._guard; then fv.video._g fv.dialogs._stRows "$1" "$2"; return; fi
    local -n __fvg_d=${1}_data
    local __fvg_sx=${__fvg_d[SizeX]:-0} __fvg_sy=${__fvg_d[SizeY]:-0} __fvg_c1=${FV_DRAW_PAL:0:1} __fvg_s=$2 __fvg_x __fvg_w __fvg_i
    local __fvg_cur='' __fvg_curw=0 __fvg_lwl=0 __fvg_lww=0 __fvg_ltl=0 __fvg_ltw=0 __fvg_nx='' __fvg_nxw=0 __fvg_j=0 __fvg_at=1 __fvg_y=0
    local __fvg_rp __fvg_bl __fvg_seg __fvg_nl
    local -a __fvg_rr=() _fvg_e=() _fvg_ew=() _fvg_cl _fvg_cc
    __fvg_c1=${__fvg_c1:-$__FV_VW_ERRSYM}
    if (( __fvg_sx < 1 || __fvg_sy < 1 )); then fv.dialogs._keep "$1"; return 0; fi
    fv.dialogs._rep "$__fvg_c1" "$__fvg_sx"
    __fvg_bl=${__FV_VW_PAD:0:__fvg_sx}
    # (the clusters: _fvg_e / _fvg_ew; a line end is the item $'\n' of width -1)
    while [[ -n $__fvg_s ]]; do
        __fvg_seg=${__fvg_s%%[[:cntrl:]]*}
        if [[ -n $__fvg_seg ]]; then
            if [[ $__fvg_seg != $__FV_VS_PNA ]]; then
                for (( __fvg_i = 0; __fvg_i < ${#__fvg_seg}; __fvg_i++ )); do _fvg_e+=("${__fvg_seg:__fvg_i:1}") _fvg_ew+=(1); done
            else
                fv.video.clusters "$__fvg_seg" _fvg_cl _fvg_cc || :
                _fvg_e+=("${_fvg_cl[@]}") _fvg_ew+=("${_fvg_cc[@]}")
            fi
            __fvg_s=${__fvg_s:${#__fvg_seg}}
        fi
        [[ -n $__fvg_s ]] || break
        __fvg_x=${__fvg_s:0:1} __fvg_s=${__fvg_s:1}
        if [ "$__fvg_x" = $'\r' ]; then
            _fvg_e+=($'\n') _fvg_ew+=(-1)
            if [ "${__fvg_s:0:1}" = $'\n' ]; then __fvg_s=${__fvg_s:1}; fi
        elif [ "$__fvg_x" = $'\n' ]; then _fvg_e+=($'\n') _fvg_ew+=(-1)
        elif [ "$__fvg_x" = $'\x02' ] || [ "$__fvg_x" = $'\x03' ]; then _fvg_e+=("$__fvg_x") _fvg_ew+=(0)
        else _fvg_e+=('?') _fvg_ew+=(1); fi
    done
    for (( __fvg_i = 0; __fvg_i < ${#_fvg_e[@]}; __fvg_i++ )); do
        __fvg_x=${_fvg_e[__fvg_i]} __fvg_w=${_fvg_ew[__fvg_i]}
        if (( __fvg_w == 0 )); then
            if (( __fvg_at )); then
                __fvg_at=0
                if [ "$__fvg_x" = $'\x02' ]; then __fvg_j=2; else __fvg_j=1; fi
            fi
            continue
        fi
        __fvg_at=0 __fvg_nl=0
        if (( __fvg_w < 0 )); then __fvg_nl=1
        else
            if [ "$__fvg_x" = ' ' ]; then __fvg_lwl=${#__fvg_cur} __fvg_lww=$__fvg_curw; fi
            __fvg_cur+=$__fvg_x __fvg_curw=$(( __fvg_curw + __fvg_w ))
            if (( __fvg_curw <= __fvg_sx )); then __fvg_ltl=${#__fvg_cur} __fvg_ltw=$__fvg_curw; fi
        fi
        if (( __fvg_curw >= __fvg_sx || __fvg_nl )); then
            if (( __fvg_curw >= __fvg_sx )); then
                if (( __fvg_lwl > 0 )); then
                    __fvg_nx=${__fvg_cur:__fvg_lwl} __fvg_nxw=$(( __fvg_curw - __fvg_lww )) __fvg_cur=${__fvg_cur:0:__fvg_lwl} __fvg_curw=$__fvg_lww
                else
                    __fvg_nx=${__fvg_cur:__fvg_ltl} __fvg_nxw=$(( __fvg_curw - __fvg_ltw )) __fvg_cur=${__fvg_cur:0:__fvg_ltl} __fvg_curw=$__fvg_ltw
                fi
            else
                __fvg_nx='' __fvg_nxw=0
            fi
            __fvg_lwl=0 __fvg_lww=0 __fvg_ltl=0 __fvg_ltw=0
            fv.dialogs._stLine
            if (( __fvg_y >= __fvg_sy )); then fv.dialogs._keep "$1" "${__fvg_rr[@]}"; return 0; fi
            __fvg_cur=$__fvg_nx __fvg_curw=$__fvg_nxw __fvg_j=0 __fvg_at=1
        fi
    done
    fv.dialogs._stLine
    while (( __fvg_y < __fvg_sy )); do __fvg_rr+=("$__fvg_bl" "$__fvg_rp"); __fvg_y=$(( __fvg_y + 1 )); done
    fv.dialogs._keep "$1" "${__fvg_rr[@]}"
}
# (FV FinishLine: the caller's line __fvg_cur placed by __fvg_j in a blank
# row of the width — cut to the width when a wide cluster made it longer)
fv.dialogs._stLine() {
    local __fvg_o=0 __fvg_ct __fvg_ca __fvg_cw
    if [[ -n $__fvg_cur ]]; then
        if (( __fvg_j == 1 )); then __fvg_o=$(( (__fvg_sx - __fvg_curw) / 2 )); elif (( __fvg_j == 2 )); then __fvg_o=$(( __fvg_sx - __fvg_curw )); fi
        if (( __fvg_o < 0 )); then __fvg_o=0; fi
        __fvg_ct=$__fvg_cur __fvg_cw=$__fvg_curw
        if (( __fvg_o + __fvg_cw > __fvg_sx )); then fv.dialogs._cutw "$__fvg_cur" "$(( __fvg_sx - __fvg_o ))"; fi
        __fvg_rr+=("${__FV_VW_PAD:0:__fvg_o}$__fvg_ct${__FV_VW_PAD:0:__fvg_sx-__fvg_o-__fvg_cw}" "$__fvg_rp")
    else
        __fvg_rr+=("$__fvg_bl" "$__fvg_rp")
    fi
    __fvg_y=$(( __fvg_y + 1 ))
}

# fv.dialogs._ptArgs P [PARAMCOUNT] — the refusal: PARAMCOUNT not digits
fv.dialogs._ptArgs() {
    if [[ -n $2 ]] && ! fv.dialogs._num "$2"; then
        fv.dialogs._err "TParamText.Create: '$1': PARAMCOUNT must be digits (got: $2)"
        __FV_VW_CRC=2
        return 2
    fi
}
fv.dialogs._ptCreate() {   # P PARAMCOUNT
    local -n __fvg_d=${1}_data
    __fvg_d[ParamCount]=$(( 10#$2 ))
    declare -ga "${1}_params=()"
    __FV_DG_KIND[$1]=pt
}
# TParamText.GetText (func) — FV FormatStr(Text, ParamList): `printf -v` of
# Text with the first ParamCount parameters (a missing one ''), but never
# more than the format's conversions take (fv.dialogs._ptCount): printf
# would repeat the format for the surplus, FormatStr ignores it; a refused
# format answers what printf made of it, without its message
fv.dialogs._ptGetText() {
    local -n __fvg_d=${1}_data __fvg_pa=${1}_params
    local __fvg_t=${__fvg_d[Text]-} __fvg_n=${__fvg_d[ParamCount]:-0} __fvg_i __fvg_pn
    local -a __fvg_a=()
    if [[ -z $__fvg_t ]]; then RESULT=''; return 0; fi
    # (the count is kept with the text it was made from: once per text)
    if ! [ "${__FV_DG_PK[$1]-}" = "$__fvg_t" ]; then
        fv.dialogs._ptCount "$__fvg_t"
        __FV_DG_PK[$1]=$__fvg_t __FV_DG_PN[$1]=$__fvg_pn
    fi
    if (( __fvg_n > ${__FV_DG_PN[$1]} )); then __fvg_n=${__FV_DG_PN[$1]}; fi
    for (( __fvg_i = 0; __fvg_i < __fvg_n; __fvg_i++ )); do __fvg_a+=("${__fvg_pa[__fvg_i]-}"); done
    printf -v RESULT -- "$__fvg_t" "${__fvg_a[@]}" 2>/dev/null || :
}
# fv.dialogs._ptCount FORMAT — the caller's __fvg_pn = the arguments one
# pass of printf's FORMAT takes: one per conversion (`%%` none), one more
# per `*` width / precision; `%(…)T` one
fv.dialogs._ptCount() {
    local __fvg_s=$1 __fvg_f
    __fvg_pn=0
    while [[ $__fvg_s == *%* ]]; do
        __fvg_s=${__fvg_s#*%}
        if [[ $__fvg_s == %* ]]; then __fvg_s=${__fvg_s:1}; continue; fi
        # (the flags, width and precision; each `*` takes an argument)
        __fvg_f=${__fvg_s%%[!-+ #0-9.*]*}
        __fvg_s=${__fvg_s:${#__fvg_f}}
        __fvg_f=${__fvg_f//[!*]/}
        __fvg_pn=$(( __fvg_pn + 1 + ${#__fvg_f} ))
        if [[ $__fvg_s == '('* ]]; then __fvg_s=${__fvg_s#*')'}; fi
        __fvg_s=${__fvg_s:1}
    done
}
# TParamText.DataSize (func) — ParamCount elements
fv.dialogs._ptDataSize() {
    local -n __fvg_d=${1}_data
    RESULT=${__fvg_d[ParamCount]:-0}
}
# TParamText.GetData ARRAY INDEX / SetData ARRAY INDEX — the parameters to /
# from ARRAY[INDEX ...]; SetData redraws (FV)
fv.dialogs._ptGetData() {
    local -n __fvg_d=${1}_data __fvg_pa=${1}_params __fvg_ar=$2
    local __fvg_i
    for (( __fvg_i = 0; __fvg_i < ${__fvg_d[ParamCount]:-0}; __fvg_i++ )); do __fvg_ar[$3 + __fvg_i]=${__fvg_pa[__fvg_i]-}; done
}
fv.dialogs._ptSetData() {
    local -n __fvg_d=${1}_data __fvg_pa=${1}_params __fvg_ar=$2
    local __fvg_i
    __fvg_pa=()
    for (( __fvg_i = 0; __fvg_i < ${__fvg_d[ParamCount]:-0}; __fvg_i++ )); do __fvg_pa[__fvg_i]=${__fvg_ar[$3 + __fvg_i]-}; done
    fv.views.drawView "$1" || :
}

fv.dialogs._lblCreate() {   # L LINK
    local -n __fvg_d=${1}_data
    if [[ -z ${__FV_VW_IMPL[TLabel.Draw]-} ]]; then fv.dialogs._register; fi
    __fvg_d[Link]=$2 __fvg_d[Light]=0
    __fvg_d[Options]=$(( ${__fvg_d[Options]:-0} | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    __fvg_d[EventMask]=$(( ${__fvg_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __FV_DG_KIND[$1]=lbl
}
# TLabel.GetPalette (func) — FV CLabel 7 8 9 9
fv.dialogs._lblGetPalette() { RESULT='7 8 9 9'; }
# TLabel.Draw — FV: a blank, then Text with its `~` letter (colours 1 / 3, or
# 2 / 4 while Light), blanks to the width; rows below blank ("cover its
# rect"). Cached by colours, size, mode and Text: one write
fv.dialogs._lblDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvg_d=${1}_data
    local __fvg_pc=13 __fvg_k
    if [ "${__fvg_d[Light]-}" = 1 ]; then __fvg_pc=24; fi
    __fvg_k="${FV_DRAW_PAL:${__fvg_pc:0:1}-1:1}${FV_DRAW_PAL:${__fvg_pc:1:1}-1:1}|${__fvg_d[SizeX]:-0}|${__fvg_d[SizeY]:-0}|${FV_VIDEO_ASCII:-0}|${__fvg_d[Text]-}"
    if ! [ "${__FV_DG_CK[$1]-}" = "$__fvg_k" ]; then fv.dialogs._lblRows "$1"; fi
    fv.dialogs._rows "$1"
}
fv.dialogs._lblRows() {
    if fv.dialogs._guard; then fv.video._g fv.dialogs._lblRows "$1"; return; fi
    local -n __fvg_d=${1}_data
    local __fvg_sx=${__fvg_d[SizeX]:-0} __fvg_sy=${__fvg_d[SizeY]:-0} __fvg_lo=${FV_DRAW_PAL:${__fvg_pc:0:1}-1:1} __fvg_hi=${FV_DRAW_PAL:${__fvg_pc:1:1}-1:1}
    local __fvg_ct='' __fvg_ca='' __fvg_cw=0 __fvg_rp __fvg_y __fvg_r0 __fvg_a0
    local -a __fvg_rr=()
    __fvg_lo=${__fvg_lo:-$__FV_VW_ERRSYM} __fvg_hi=${__fvg_hi:-$__FV_VW_ERRSYM}
    if (( __fvg_sx < 1 || __fvg_sy < 1 )); then fv.dialogs._keep "$1"; return 0; fi
    if (( __fvg_sx > 1 )); then fv.dialogs._cstr "${__fvg_d[Text]-}" "$__fvg_lo" "$__fvg_hi" "$(( __fvg_sx - 1 ))"; fi
    fv.dialogs._rep "$__fvg_lo" "$(( __fvg_sx - 1 - __fvg_cw ))"
    __fvg_r0=" $__fvg_ct${__FV_VW_PAD:0:__fvg_sx-1-__fvg_cw}" __fvg_a0=$__fvg_lo$__fvg_ca$__fvg_rp
    __fvg_rr=("${__fvg_r0:0:${#__fvg_r0}}" "${__fvg_a0:0:__fvg_sx}")
    fv.dialogs._rep "$__fvg_lo" "$__fvg_sx"
    for (( __fvg_y = 1; __fvg_y < __fvg_sy; __fvg_y++ )); do __fvg_rr+=("${__FV_VW_PAD:0:__fvg_sx}" "$__fvg_rp"); done
    fv.dialogs._keep "$1" "${__fvg_rr[@]}"
}
# TLabel.HandleEvent — FV: TView's (a label is not selectable: nothing),
# then evMouseDown -> the link focused (when selectable), handled; evKeyDown
# Alt + the hot letter, or the plain letter in the owner's phPostProcess ->
# the same; evBroadcast cmReceivedFocus / cmReleasedFocus (a link set) ->
# Light := the link has sfFocused, redrawn when Light changed (P3-12)
fv.dialogs._lblEvent() {
    local -n __fvg_d=${1}_data
    if [ "$FV_EV_WHAT" = evBroadcast ]; then
        local __fvg_l=${__fvg_d[Link]-} __fvg_g=0
        if [[ -z $__fvg_l || -z ${__FV_VW_LIVE[$__fvg_l]-} ]]; then return 0; fi
        local -n __fvg_ld=${__fvg_l}_data
        if (( ${__fvg_ld[State]:-0} & FV_SF_FOCUSED )); then __fvg_g=1; fi
        if ! [ "${__fvg_d[Light]-}" = "$__fvg_g" ]; then __fvg_d[Light]=$__fvg_g; fv.views.drawView "$1" || :; fi
    elif [ "$FV_EV_WHAT" = evKeyDown ]; then
        local __fvg_t=${__fvg_d[Text]-} __fvg_c __fvg_p=0
        if [[ $__fvg_t == *[![:ascii:]]* ]] && fv.dialogs._u8 && [[ -z ${__fvv_g-} ]]; then fv.video._g fv.dialogs._lblEvent "$1"; return 0; fi
        fv.dialogs._hot "$__fvg_t"
        [[ -n $__fvg_c ]] || return 0
        fv.dialogs._post1 "$1"
        if fv.views._hk "$__fvg_c" "$__fvg_p" "$1"; then fv.dialogs._lblFocus "$1"; fi
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.dialogs._lblFocus "$1"; fi
    fi
    return 0
}
# (FV FocusLink: the link focused when it is a selectable live view; handled)
fv.dialogs._lblFocus() {
    local -n __fvg_d=${1}_data
    local __fvg_l=${__fvg_d[Link]-}
    if [[ -n $__fvg_l && -n ${__FV_VW_LIVE[$__fvg_l]-} ]]; then
        local -n __fvg_ld=${__fvg_l}_data
        if (( ${__fvg_ld[Options]:-0} & FV_OF_SELECTABLE )); then fv.views.focus "$__fvg_l" || :; fi
    fi
    fv.dialogs._clear "$1"
}

# ---- TCluster, TCheckBoxes, TRadioButtons (FV dialogs.inc) -------------------------
fv.dialogs._clCreate() {   # C ITEM...
    local __fvg_v=$1
    shift
    fv.dialogs._free "$__fvg_v"
    if [[ -z ${__FV_VW_IMPL[TCluster.Draw]-} ]]; then fv.dialogs._register; fi
    local -n __fvg_d=${__fvg_v}_data
    __fvg_d[Options]=$(( ${__fvg_d[Options]:-0} | FV_OF_SELECTABLE | FV_OF_FIRSTCLICK | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    __fvg_d[Id]=0 __fvg_d[Value]=0 __fvg_d[Sel]=0 __fvg_d[EnableMask]=$(( 0xFFFFFFFF ))
    __fvg_d[CursorX]=2 __fvg_d[CursorY]=0 __fvg_d[State]=$(( ${__fvg_d[State]:-0} | FV_SF_CURSORVIS ))
    declare -ga "${__fvg_v}_items=()" "${__fvg_v}_cpl=()" "${__fvg_v}_cpp=()" "${__fvg_v}_cpw=()" "${__fvg_v}_chot=()"
    local -n __fvg_it=${__fvg_v}_items
    __fvg_it=("$@")
    __FV_DG_KIND[$__fvg_v]=cl
}
# TCluster.GetPalette (func) — FV CCluster 16 17 18 18 31 6
fv.dialogs._clGetPalette() { RESULT='16 17 18 18 31 6'; }
# TCluster.GetHelpCtx (func) — FV: hcNoContext, or HelpCtx + Sel
fv.dialogs._clGetHelpCtx() {
    local -n __fvg_d=${1}_data
    local __fvg_h=${__fvg_d[HelpCtx]:-0}
    if [[ $__fvg_h == *[!0123456789]* || ${#__fvg_h} -gt 9 ]] || (( 10#$__fvg_h == FV_HC_NOCONTEXT )); then RESULT=$FV_HC_NOCONTEXT
    else RESULT=$(( 10#$__fvg_h + ${__fvg_d[Sel]:-0} )); fi
}
# TCluster.Mark ITEM (func; rc 0 = marked) — FV: false. TCheckBoxes: ITEM's
# bit of Value; TRadioButtons: ITEM = Value
fv.dialogs._clMark() { return 1; }
fv.dialogs._cbMark() {
    local -n __fvg_d=${1}_data
    [[ ${2-} != *[!0123456789]* && -n ${2-} && ${#2} -le 2 ]] && (( (${__fvg_d[Value]:-0} >> 10#$2) & 1 ))
}
fv.dialogs._rbMark() {
    local -n __fvg_d=${1}_data
    [ "${2-}" = "${__fvg_d[Value]:-0}" ]
}
# TCluster.Press ITEM — FV: Id <> 0 -> cmIdCommunicate (evCommand) to the top
# view (FV_EV_ID = Id, FV_EV_INFO = the cluster; FV's Data = its Value).
# TCheckBoxes: Value xor ITEM's bit first; TRadioButtons: Value := ITEM first
fv.dialogs._clPress() {
    local -n __fvg_d=${1}_data
    local __fvw_t __fvg_i=${__fvg_d[Id]:-0}
    if [[ $__fvg_i == *[!0123456789]* || -z $__fvg_i ]] || (( 10#$__fvg_i == 0 )); then return 0; fi
    fv.views._topView "$1"
    if [[ -n $__fvw_t ]]; then fv.views._message "$__fvw_t" evCommand cmIdCommunicate "$1" "$__fvg_i" || :; fi
    return 0
}
fv.dialogs._cbPress() {
    local -n __fvg_d=${1}_data
    if [[ ${2-} != *[!0123456789]* && -n ${2-} && ${#2} -le 2 ]]; then __fvg_d[Value]=$(( ${__fvg_d[Value]:-0} ^ (1 << 10#$2) )); fi
    fv.dialogs._clPress "$@"
}
fv.dialogs._rbPress() {
    local -n __fvg_d=${1}_data
    __fvg_d[Value]=${2-0}
    fv.dialogs._clPress "$@"
}
# TCluster.MovedTo ITEM — FV: nothing. TRadioButtons: Value := ITEM; Id <> 0
# -> cmIdCommunicate (evCommand) to the owner
fv.dialogs._clMovedTo() { return 0; }
fv.dialogs._rbMovedTo() {
    local -n __fvg_d=${1}_data
    local __fvg_i=${__fvg_d[Id]:-0} __fvg_o=${__fvg_d[Owner]-}
    __fvg_d[Value]=${2-0}
    if [[ $__fvg_i == *[!0123456789]* || -z $__fvg_i ]] || (( 10#$__fvg_i == 0 )); then return 0; fi
    if [[ -n $__fvg_o && -n ${__FV_VW_LIVE[$__fvg_o]-} ]]; then fv.views._message "$__fvg_o" evCommand cmIdCommunicate "$1" "$__fvg_i" || :; fi
    return 0
}
# DataSize (func) 1; GetData ARRAY INDEX -> ARRAY[INDEX] = Value; SetData
# ARRAY INDEX -> Value := ARRAY[INDEX] (a number), redrawn. TRadioButtons'
# SetData moves Sel there too (FV)
fv.dialogs._clDataSize() { RESULT=1; }
fv.dialogs._clGetData() {
    local -n __fvg_d=${1}_data __fvg_ar=$2
    __fvg_ar[$3]=${__fvg_d[Value]:-0}
}
fv.dialogs._clSetData() {
    local -n __fvg_d=${1}_data __fvg_ar=$2
    local __fvg_x=${__fvg_ar[$3]-0}
    if [[ -z $__fvg_x || $__fvg_x == *[!0123456789]* || ${#__fvg_x} -gt 10 ]]; then __fvg_x=0; fi
    __fvg_d[Value]=$(( 10#$__fvg_x ))
    fv.views.drawView "$1" || :
}
fv.dialogs._rbSetData() {
    local -n __fvg_d=${1}_data __fvg_ar=$2
    local __fvg_x=${__fvg_ar[$3]-0}
    if [[ -z $__fvg_x || $__fvg_x == *[!0123456789]* || ${#__fvg_x} -gt 10 ]]; then __fvg_x=0; fi
    __fvg_d[Sel]=$(( 10#$__fvg_x ))
    fv.dialogs._clSetData "$@"
}
# fv.dialogs._clOn C I — rc 0 when item I is enabled (FV ButtonState: I <= 31
# and its EnableMask bit)
fv.dialogs._clOn() {
    local -n __fvg_od=${1}_data
    (( $2 >= 0 && $2 <= 31 && ((${__fvg_od[EnableMask]:-0} >> $2) & 1) ))
}
# fv.dialogs._clPats C — the items' drawn text (`~` dropped), cell pattern
# (`+` FV's Lo colour, `-` the Hi one, one per cell), cells and hot letter,
# for the screen's ASCII mode; kept until the items or the mode change
# (__FV_DG_CK). Under fv.video's guard
fv.dialogs._clPats() {
    if fv.dialogs._guard; then fv.video._g fv.dialogs._clPats "$1"; return; fi
    local -n __fvg_it=${1}_items __fvg_pl=${1}_cpl __fvg_pp=${1}_cpp __fvg_pw=${1}_cpw __fvg_ph=${1}_chot
    local __fvg_s __fvg_ct __fvg_ca __fvg_cw __fvg_c IFS=' '
    __fvg_pl=() __fvg_pp=() __fvg_pw=() __fvg_ph=()
    for __fvg_s in "${__fvg_it[@]}"; do
        fv.dialogs._cstr "$__fvg_s" + - "$__FV_VW_MAXW"
        fv.dialogs._hot "$__fvg_s"
        __fvg_pl+=("$__fvg_ct") __fvg_pp+=("$__fvg_ca") __fvg_pw+=("$__fvg_cw") __fvg_ph+=("$__fvg_c")
    done
    __FV_DG_CK[$1]="${FV_VIDEO_ASCII:-0}|${__fvg_it[*]@Q}"
}
# fv.dialogs._clReady C — the patterns current (rebuilt when stale)
fv.dialogs._clReady() {
    local -n __fvg_it=${1}_items
    local IFS=' '
    if ! [ "${__FV_DG_CK[$1]-}" = "${FV_VIDEO_ASCII:-0}|${__fvg_it[*]@Q}" ]; then fv.dialogs._clPats "$1"; fi
}
# fv.dialogs._clCols C — the caller's __fvg_cs[k] = FV Column() of every
# item in column k (k = item div SizeY), for the columns the items fill and
# one more: column k+1 starts at column k + its widest item + 6 (FV; an item
# past the last counts the last item's width, as FV's L keeps it)
fv.dialogs._clCols() {
    local -n __fvg_d=${1}_data __fvg_pw=${1}_cpw
    local __fvg_h=${__fvg_d[SizeY]:-0} __fvg_n=${#__fvg_pw[@]} __fvg_i __fvg_w=0 __fvg_c=0 __fvg_l=0 __fvg_z
    __fvg_cs=(0)
    if (( __fvg_h < 1 )); then return 0; fi
    __fvg_z=$(( ((__fvg_n + __fvg_h - 1) / __fvg_h + 1) * __fvg_h ))
    for (( __fvg_i = 0; __fvg_i < __fvg_z; __fvg_i++ )); do
        if (( __fvg_i > 0 && __fvg_i % __fvg_h == 0 )); then
            __fvg_cs[__fvg_c + 1]=$(( __fvg_cs[__fvg_c] + __fvg_w + 6 )) __fvg_c=$(( __fvg_c + 1 )) __fvg_w=0
        fi
        if (( __fvg_i < __fvg_n )); then __fvg_l=${__fvg_pw[__fvg_i]}; fi
        if (( __fvg_l > __fvg_w )); then __fvg_w=$__fvg_l; fi
    done
    __fvg_cs[__fvg_c + 1]=$(( __fvg_cs[__fvg_c] + __fvg_w + 6 ))
}
# TCluster.Draw — FV's is empty (abstract); here blanks in colour 1 so that
# it covers its rect. TCheckBoxes / TRadioButtons: FV DrawMultiBox
fv.dialogs._clDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvg_d=${1}_data
    fv.views.fill 0 0 "${__fvg_d[SizeX]:-0}" "${__fvg_d[SizeY]:-0}" ' ' 1 || :
}
fv.dialogs._cbDraw() { fv.dialogs._multiBox "$1" ' [ ] ' ' X' fv.dialogs._cbMark; }
fv.dialogs._rbDraw() { fv.dialogs._multiBox "$1" ' ( ) ' ' *' fv.dialogs._rbMark; }
# fv.dialogs._multiBox C ICON MARKERS MARKBODY — FV DrawMultiBox(Icon,
# Marker): per row, the items of that row (item J*SizeY + row) at FV's
# Column, each from its column to the next drawn one (or the row's end) in
# its colour — CDis (5) when its EnableMask bit is off, CSel (2 / 4) for Sel
# while focused, else CNorm (1 / 3): ICON with MARKERS[Mark] in its third
# cell, then the item's text with its `~` letter in the Hi colour. Mark is
# read inline when it is the class's built-in (MARKBODY), one dispatch per
# item otherwise. Only the rows FV_CLIP_Y1 .. Y2 (drawPart's painter too);
# one writeLines. The cursor at (Column(Sel) + 2, Row(Sel)) (FV SetCursor)
fv.dialogs._multiBox() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvg_d=${1}_data __fvg_it=${1}_items
    fv.dialogs._clReady "$1"
    local -n __fvg_pl=${1}_cpl __fvg_pp=${1}_cpp __fvg_pw=${1}_cpw
    local __fvg_sx=${__fvg_d[SizeX]:-0} __fvg_sy=${__fvg_d[SizeY]:-0} __fvg_n=${#__fvg_it[@]} __fvg_sel=${__fvg_d[Sel]:-0}
    local __fvg_v=${__fvg_d[Value]:-0} __fvg_em=${__fvg_d[EnableMask]:-0} __fvg_p=$FV_DRAW_PAL __fvg_e=$__FV_VW_ERRSYM
    local __fvg_f=0 __fvg_mk=0 __fvg_y __fvg_y2=$FV_CLIP_Y2 __fvg_j __fvg_c __fvg_x __fvg_nx __fvg_lo __fvg_hi __fvg_m
    local __fvg_t __fvg_a __fvg_s __fvg_q __fvg_rp __fvg_l __fvg_ct __fvg_ca __fvg_cw __fvg_im
    local __fvg_n1=${__fvg_p:0:1} __fvg_n3=${__fvg_p:2:1} __fvg_s2=${__fvg_p:1:1} __fvg_s4=${__fvg_p:3:1} __fvg_d5=${__fvg_p:4:1}
    local -a __fvg_cs _fvg_t=() _fvg_a=()
    __fvg_n1=${__fvg_n1:-$__fvg_e} __fvg_n3=${__fvg_n3:-$__fvg_e} __fvg_s2=${__fvg_s2:-$__fvg_e} __fvg_s4=${__fvg_s4:-$__fvg_e} __fvg_d5=${__fvg_d5:-$__fvg_e}
    if (( __fvg_y2 > __fvg_sy )); then __fvg_y2=$__fvg_sy; fi
    if (( __fvg_sx < 1 || FV_CLIP_Y1 >= __fvg_y2 )); then return 0; fi
    if (( ${__fvg_d[State]:-0} & FV_SF_FOCUSED )); then __fvg_f=1; fi
    fv.dialogs._impl "$1" Mark
    if [ "$__fvg_im" = fv.dialogs._cbMark ]; then __fvg_mk=1
    elif [ "$__fvg_im" = fv.dialogs._rbMark ]; then __fvg_mk=2
    elif ! [ "$__fvg_im" = fv.dialogs._clMark ]; then __fvg_mk=9; fi
    fv.dialogs._clCols "$1"
    for (( __fvg_y = FV_CLIP_Y1; __fvg_y < __fvg_y2; __fvg_y++ )); do
        __fvg_t='' __fvg_a='' __fvg_x=0
        for (( __fvg_j = 0; ; __fvg_j++ )); do
            __fvg_c=$(( __fvg_j * __fvg_sy + __fvg_y ))
            if (( __fvg_c >= __fvg_n )) || (( __fvg_cs[__fvg_j] >= __fvg_sx )); then break; fi
            # (the next drawn item of the row ends this one's part)
            __fvg_nx=$__fvg_sx
            if (( __fvg_c + __fvg_sy < __fvg_n && ${__fvg_cs[__fvg_j + 1]:-$__fvg_sx} < __fvg_sx )); then __fvg_nx=${__fvg_cs[__fvg_j + 1]}; fi
            __fvg_x=${__fvg_cs[__fvg_j]}
            if (( __fvg_c > 31 || ! ((__fvg_em >> __fvg_c) & 1) )); then __fvg_lo=$__fvg_d5 __fvg_hi=$__fvg_d5
            elif (( __fvg_c == __fvg_sel && __fvg_f )); then __fvg_lo=$__fvg_s2 __fvg_hi=$__fvg_s4
            else __fvg_lo=$__fvg_n1 __fvg_hi=$__fvg_n3; fi
            __fvg_m=0
            if (( __fvg_mk == 1 )); then __fvg_m=$(( __fvg_c <= 62 && ((__fvg_v >> __fvg_c) & 1) ))
            elif (( __fvg_mk == 2 )); then __fvg_m=$(( __fvg_c == __fvg_v ))
            elif (( __fvg_mk == 9 )); then
                if fv.views._virt "$1" Mark "$__fvg_c"; then __fvg_m=1; fi
                [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
            fi
            __fvg_s="${2:0:2}${3:__fvg_m:1}${2:3}${__fvg_pl[__fvg_c]}" __fvg_q=${__fvg_pp[__fvg_c]}
            __fvg_q=${__fvg_q//+/"$__fvg_lo"} __fvg_q=${__fvg_q//-/"$__fvg_hi"}
            fv.dialogs._rep "$__fvg_lo" 5
            __fvg_q=$__fvg_rp$__fvg_q __fvg_l=$(( __fvg_nx - __fvg_x ))
            if (( 5 + ${__fvg_pw[__fvg_c]} > __fvg_l )); then fv.dialogs._clCut; fi
            fv.dialogs._rep "$__fvg_lo" "$(( __fvg_l - ${#__fvg_q} ))"
            __fvg_t+=$__fvg_s${__FV_VW_PAD:0:__fvg_l-${#__fvg_q}} __fvg_a+=$__fvg_q$__fvg_rp __fvg_x=$__fvg_nx
        done
        if (( __fvg_x < __fvg_sx )); then
            fv.dialogs._rep "$__fvg_n1" "$(( __fvg_sx - __fvg_x ))"
            __fvg_t+=${__FV_VW_PAD:0:__fvg_sx-__fvg_x} __fvg_a+=$__fvg_rp
        fi
        _fvg_t[__fvg_y]=$__fvg_t _fvg_a[__fvg_y]=$__fvg_a
    done
    if (( __fvg_y2 - FV_CLIP_Y1 == 1 )); then fv.views.writeLine 0 "$FV_CLIP_Y1" 1 "${_fvg_t[FV_CLIP_Y1]}" "${_fvg_a[FV_CLIP_Y1]}" || :
    else fv.views.writeLines 0 0 _fvg_t _fvg_a || :; fi
    if (( __fvg_sy > 0 )); then
        if (( __fvg_sel >= __fvg_sy )); then __fvg_x=${__fvg_cs[__fvg_sel / __fvg_sy]:-0}; else __fvg_x=0; fi
        __fvg_d[CursorX]=$(( __fvg_x + 2 )) __fvg_d[CursorY]=$(( __fvg_sel % __fvg_sy ))
    fi
}
# (_multiBox's item part cut to the room __fvg_l: the caller's __fvg_s text
# and __fvg_q symbols; a wide cluster that does not fit is left out)
fv.dialogs._clCut() {
    if [[ $__fvg_s != $__FV_VS_PNA ]]; then __fvg_s=${__fvg_s:0:__fvg_l} __fvg_q=${__fvg_q:0:__fvg_l}; return 0; fi
    local __fvg_ct __fvg_cw
    fv.dialogs._cutw "$__fvg_s" "$__fvg_l"
    __fvg_s=$__fvg_ct __fvg_q=${__fvg_q:0:__fvg_cw}
}
# fv.dialogs._clRows C ITEM... — rule 4 (design §2.1): the rows that show
# the ITEMs repainted with the class's Draw body as drawPart's painter (one
# drawPart over two neighbouring rows, else one per row; more than two rows,
# or a Draw or Mark of yours: the whole cluster)
fv.dialogs._clRows() {
    local -n __fvg_rd=${1}_data
    local __fvg_im __fvg_h=${__fvg_rd[SizeY]:-0} __fvg_r __fvg_a=-1 __fvg_b=-1 __fvg_i
    fv.dialogs._impl "$1" Mark
    if [ "$__fvg_im" = fv.dialogs._cbMark ] || [ "$__fvg_im" = fv.dialogs._rbMark ] || [ "$__fvg_im" = fv.dialogs._clMark ]; then
        fv.dialogs._impl "$1" Draw
    else __fvg_im=''; fi
    if (( __fvg_h < 1 )); then return 0; fi
    if ! [ "$__fvg_im" = fv.dialogs._cbDraw ] && ! [ "$__fvg_im" = fv.dialogs._rbDraw ]; then fv.views.drawView "$1" || :; return 0; fi
    local __fvg_n=0
    for __fvg_i; do
        if (( __fvg_n++ == 0 )); then continue; fi
        if [[ -z $__fvg_i ]] || (( __fvg_i < 0 )); then continue; fi
        __fvg_r=$(( __fvg_i % __fvg_h ))
        if (( __fvg_a < 0 )); then __fvg_a=$__fvg_r
        elif (( __fvg_r != __fvg_a && __fvg_b < 0 )); then __fvg_b=$__fvg_r
        elif (( __fvg_r != __fvg_a && __fvg_r != __fvg_b )); then fv.views.drawView "$1" || :; return 0; fi
    done
    if (( __fvg_a < 0 )); then return 0; fi
    if (( __fvg_b < 0 )); then __fvg_b=$__fvg_a; fi
    if (( __fvg_a > __fvg_b )); then __fvg_r=$__fvg_a __fvg_a=$__fvg_b __fvg_b=$__fvg_r; fi
    if (( __fvg_b - __fvg_a <= 1 )); then fv.views.drawPart "$1" "$__fvg_im" "$__fvg_a" "$(( __fvg_b + 1 ))" || :; return 0; fi
    fv.views.drawPart "$1" "$__fvg_im" "$__fvg_a" "$(( __fvg_a + 1 ))" || :
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    fv.views.drawPart "$1" "$__fvg_im" "$__fvg_b" "$(( __fvg_b + 1 ))" || :
}
# fv.dialogs._clChanged C OLDSEL OLDVALUE — after a key or a click: the rows
# whose picture changed (the old and the new Sel; the items whose mark
# changed: a check box's toggled bit, a radio's old and new Value) by rule 4
fv.dialogs._clChanged() {
    local -n __fvg_cd=${1}_data
    local __fvg_s=${__fvg_cd[Sel]:-0} __fvg_v=${__fvg_cd[Value]:-0} __fvg_i __fvg_im
    local -a __fvg_ii=("$2" "$__fvg_s")
    if ! [ "$3" = "$__fvg_v" ]; then
        # (a check box: every changed bit; a radio: the old and the new item)
        fv.dialogs._impl "$1" Mark
        if [ "$__fvg_im" = fv.dialogs._cbMark ]; then
            for (( __fvg_i = 0; __fvg_i < 32; __fvg_i++ )); do
                if (( (($3 ^ __fvg_v) >> __fvg_i) & 1 )); then __fvg_ii+=("$__fvg_i"); fi
            done
        else __fvg_ii+=("$3" "$__fvg_v"); fi
    fi
    fv.dialogs._clRows "$1" "${__fvg_ii[@]}"
}
# TCluster.SetState BIT ENABLE — FV: TView's; sfFocused -> redrawn; P3-12:
# only Sel's row, and only when Sel is enabled (its colour is what changes)
fv.dialogs._clSetState() {
    local -n __fvg_d=${1}_data
    local __fvg_o=$(( ${__fvg_d[State]:-0} & FV_SF_FOCUSED ))
    fv.views._viewSetState "$@"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( ($2 & FV_SF_FOCUSED) && (${__fvg_d[State]:-0} & FV_SF_FOCUSED) != __fvg_o )) && fv.dialogs._clOn "$1" "${__fvg_d[Sel]:-0}"; then
        fv.dialogs._clRows "$1" "${__fvg_d[Sel]:-0}"
    fi
    return 0
}
# TCluster.HandleEvent — FV: TView's (a click focuses: ofFirstClick, the click
# goes on); nothing when not selectable; then
#   * evMouseDown: the item under the press becomes Sel (enabled), tracked to
#     the release; released on Sel (enabled) -> Press(Sel); handled;
#   * evKeyDown (through FV's CtrlToArrow): Up / Down / Right / Left while
#     focused -> the next enabled item (wrapping; Right / Left by a column)
#     becomes Sel, MovedTo; else Alt + an item's hot letter, or the plain
#     letter in the owner's phPostProcess or while focused -> (enabled) the
#     cluster focused, Sel := it, MovedTo, Press; Space while focused ->
#     Press(Sel). Each redraws only the changed rows (rule 4)
fv.dialogs._clEvent() {
    local -n __fvg_d=${1}_data
    if [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" != evMouseDown ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
        if (( ${__fvg_d[Options]:-0} & FV_OF_SELECTABLE )); then fv.dialogs._clMouse "$1"; fi
    elif [ "$FV_EV_WHAT" = evKeyDown ]; then
        if (( ${__fvg_d[Options]:-0} & FV_OF_SELECTABLE )); then fv.dialogs._clKey "$1"; fi
    fi
    return 0
}
fv.dialogs._clKey() {
    local -n __fvg_d=${1}_data __fvg_it=${1}_items
    local __fvg_k=${__FV_VW_C2A[${FV_EV_KEY:-kbNoKey}]-$FV_EV_KEY} __fvg_n=${#__fvg_it[@]} __fvg_s=${__fvg_d[Sel]:-0}
    local __fvg_v=${__fvg_d[Value]:-0} __fvg_f=$(( ${__fvg_d[State]:-0} & FV_SF_FOCUSED )) __fvg_i __fvg_h=${__fvg_d[SizeY]:-0} __fvg_p=0
    if [ "$__fvg_k" = kbUp ] || [ "$__fvg_k" = kbDown ] || [ "$__fvg_k" = kbRight ] || [ "$__fvg_k" = kbLeft ]; then
        if (( ! __fvg_f || __fvg_n < 1 || __fvg_h < 1 )); then return 0; fi
        for (( __fvg_i = 1; ; __fvg_i++ )); do
            if [ "$__fvg_k" = kbUp ]; then __fvg_s=$(( __fvg_s - 1 ))
            elif [ "$__fvg_k" = kbDown ]; then __fvg_s=$(( __fvg_s + 1 ))
            elif [ "$__fvg_k" = kbRight ]; then
                __fvg_s=$(( __fvg_s + __fvg_h ))
                if (( __fvg_s >= __fvg_n )); then __fvg_s=$(( (__fvg_s + 1) % __fvg_h )); fi
            else
                __fvg_s=$(( __fvg_s - __fvg_h ))
                if (( __fvg_s < 0 )); then __fvg_s=$(( (__fvg_n + __fvg_h - 1) / __fvg_h * __fvg_h + __fvg_s - 1 )); fi
            fi
            if (( __fvg_s >= __fvg_n )); then __fvg_s=0; fi
            if (( __fvg_s < 0 )); then __fvg_s=$(( __fvg_n - 1 )); fi
            if fv.dialogs._clOn "$1" "$__fvg_s" || (( __fvg_i > __fvg_n )); then break; fi
        done
        if (( __fvg_i <= __fvg_n )); then
            __fvg_i=${__fvg_d[Sel]:-0}
            __fvg_d[Sel]=$__fvg_s
            fv.views._virt "$1" MovedTo "$__fvg_s" || :
            [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
            fv.dialogs._clChanged "$1" "$__fvg_i" "$__fvg_v"
        fi
        fv.dialogs._clear "$1"
        return 0
    fi
    # (only an Alt key or a plain character can be an item's hot letter)
    if [[ $FV_EV_KEY == kbAlt* || $FV_EV_KEY == kbChar ]]; then
        fv.dialogs._clReady "$1"
        local -n __fvg_ph=${1}_chot
        fv.dialogs._post1 "$1"
        if (( __fvg_f )); then __fvg_p=1; fi
        for (( __fvg_i = 0; __fvg_i < __fvg_n; __fvg_i++ )); do
            if [[ -z ${__fvg_ph[__fvg_i]-} ]] || ! fv.views._hk "${__fvg_ph[__fvg_i]}" "$__fvg_p" "$1"; then continue; fi
            if fv.dialogs._clOn "$1" "$__fvg_i"; then
                if fv.views.focus "$1"; then
                    __fvg_s=${__fvg_d[Sel]:-0}
                    __fvg_d[Sel]=$__fvg_i
                    fv.views._virt "$1" MovedTo "$__fvg_i" || :
                    [[ -n ${__FV_VW_LIVE[$1]-} ]] && fv.views._virt "$1" Press "$__fvg_i" || :
                    [[ -n ${__FV_VW_LIVE[$1]-} ]] && fv.dialogs._clChanged "$1" "$__fvg_s" "$__fvg_v"
                fi
                fv.dialogs._clear "$1"
            fi
            return 0
        done
    fi
    if [ "$FV_EV_KEY" = kbChar ] && [ "$FV_EV_CHAR" = ' ' ] && (( __fvg_f )) && fv.dialogs._clOn "$1" "$__fvg_s"; then
        fv.views._virt "$1" Press "$__fvg_s" || :
        [[ -n ${__FV_VW_LIVE[$1]-} ]] && fv.dialogs._clChanged "$1" "$__fvg_s" "$__fvg_v"
        fv.dialogs._clear "$1"
    fi
    return 0
}
# (FV FindSel: the caller's __fvg_fs = the item under the local point, -1)
fv.dialogs._clFind() {
    local -n __fvg_fd=${1}_data __fvg_fi=${1}_items
    local __fvg_h=${__fvg_fd[SizeY]:-0} __fvg_i=0 __fvg_k=0
    local -a __fvg_cs
    __fvg_fs=-1
    if (( $2 < 0 || $3 < 0 || $2 >= ${__fvg_fd[SizeX]:-0} || $3 >= __fvg_h )); then return 0; fi
    fv.dialogs._clReady "$1"
    fv.dialogs._clCols "$1"
    while (( $2 >= ${__fvg_cs[__fvg_k + 1]:-2147483647} )); do __fvg_i=$(( __fvg_i + __fvg_h )) __fvg_k=$(( __fvg_k + 1 )); done
    __fvg_i=$(( __fvg_i + $3 ))
    if (( __fvg_i >= 0 && __fvg_i < ${#__fvg_fi[@]} )); then __fvg_fs=$__fvg_i; fi
}
fv.dialogs._clMouse() {
    local -n __fvg_d=${1}_data
    local __fvg_fs __fvg_o=${__fvg_d[Sel]:-0} __fvg_v=${__fvg_d[Value]:-0} __fvg_up=0
    fv.views.makeLocal "$1" "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" || :
    fv.dialogs._clFind "$1" "$FV_POINT_X" "$FV_POINT_Y"
    if (( __fvg_fs != -1 )) && fv.dialogs._clOn "$1" "$__fvg_fs"; then __fvg_d[Sel]=$__fvg_fs; fi
    fv.dialogs._clRows "$1" "$__fvg_o" "${__fvg_d[Sel]:-0}"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -a __fvg_es=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF" "${FV_EV_BASE-}")
    __FV_VW_TRK=''
    while fv.views._track "$1" "$FV_EM_MOUSEMOVE"; do [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0; done
    if [ "$FV_EV_WHAT" = evMouseUp ]; then
        __fvg_up=1
        fv.views.makeLocal "$1" "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" || :
        fv.dialogs._clFind "$1" "$FV_POINT_X" "$FV_POINT_Y"
    fi
    fv.dialogs._evBack
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    __fvg_o=${__fvg_d[Sel]:-0}
    if (( __fvg_up )) && [ "$__fvg_fs" = "$__fvg_o" ] && fv.dialogs._clOn "$1" "$__fvg_o"; then
        fv.views._virt "$1" Press "$__fvg_o" || :
        [[ -n ${__FV_VW_LIVE[$1]-} ]] && fv.dialogs._clChanged "$1" "$__fvg_o" "$__fvg_v"
    fi
    fv.dialogs._clear "$1"
}

# ---- the data transfer (FV TGroup.GetData / SetData / DataSize; design §4.6) ------
# fv.dialogs._dsize V — the caller's __fvg_ds = V's DataSize: its virtual
# when its class has one (a number, else 0), else a group's subviews summed
# (FV TGroup.DataSize), else 0 (FV TView's)
fv.dialogs._dsize() {
    local __fvg_r=${RESULT-} __fvg_k
    __fvg_ds=0
    __fvg_k=${1}_class __fvg_k="${!__fvg_k-}_class_method_owner[DataSize]"
    if [[ -n ${!__fvg_k-} ]]; then
        RESULT=0
        if fv.views._virt "$1" DataSize && fv.dialogs._num "${RESULT-}"; then __fvg_ds=$(( 10#$RESULT )); fi
        RESULT=$__fvg_r
    elif [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        local -n __fvg_sl=${1}_views
        local __fvg_t=0
        for __fvg_k in "${__fvg_sl[@]}"; do
            [[ -n ${__FV_VW_LIVE[$__fvg_k]-} ]] || continue
            fv.dialogs._dsize "$__fvg_k"
            __fvg_t=$(( __fvg_t + __fvg_ds ))
        done
        __fvg_ds=$__fvg_t
    fi
}
# fv.dialogs._xfer V GET|SET ARRAY — V's data at the caller's index __fvg_x
# (then advanced): its GetData / SetData virtual, or a group's subviews in
# FV's order (insertion order: the back of the list first)
fv.dialogs._xfer() {
    local __fvg_k __fvg_ds __fvg_r=${RESULT-}
    __fvg_k=${1}_class __fvg_k="${!__fvg_k-}_class_method_owner[DataSize]"
    if [[ -n ${!__fvg_k-} ]]; then
        fv.dialogs._dsize "$1"
        if (( __fvg_ds > 0 )); then
            if [ "$2" = GET ]; then fv.views._virt "$1" GetData "$3" "$__fvg_x" || :; else fv.views._virt "$1" SetData "$3" "$__fvg_x" || :; fi
            __fvg_x=$(( __fvg_x + __fvg_ds ))
        fi
    elif [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        local -n __fvg_sl=${1}_views
        local -a __fvg_ks=("${__fvg_sl[@]}")
        for __fvg_k in "${__fvg_ks[@]}"; do
            if [[ -n ${__FV_VW_LIVE[$__fvg_k]-} ]]; then fv.dialogs._xfer "$__fvg_k" "$2" "$3"; fi
        done
    fi
    RESULT=$__fvg_r
}
# fv.dialogs.getData G ARRAY — FV TGroup.GetData: the indexed array ARRAY
# (replaced) gets each data-bearing subview's elements in FV's order (a
# cluster its Value, a TParamText its parameters, a view of yours what its
# GetData writes; a static text, a button, a label: nothing). RESULT kept;
# rc 2: G not a view, ARRAY not a usable name (an identifier; not RESULT,
# not _fv* / __fv*; not an associative array)
fv.dialogs.getData() {
    if (( $# != 2 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._arr getData "$1" "$2" || return
    local __fvg_x=0
    local -n __fvg_ga=$2
    __fvg_ga=()
    fv.dialogs._xfer "$1" GET "$2"
}
# fv.dialogs.setData G ARRAY — FV TGroup.SetData: each data-bearing subview
# takes its elements from ARRAY, in the same order (and redraws). RESULT kept
fv.dialogs.setData() {
    if (( $# != 2 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._arr setData "$1" "$2" || return
    local __fvg_x=0
    fv.dialogs._xfer "$1" SET "$2"
}
# fv.dialogs.dataSize V — FV DataSize: RESULT = the elements V's data takes
fv.dialogs.dataSize() {
    if (( $# != 1 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    if [[ -z $1 || -z ${__FV_VW_LIVE[$1]-} ]]; then fv.dialogs._bad dataSize "'$1' is not a view"; return; fi
    local __fvg_ds
    fv.dialogs._dsize "$1"
    RESULT=$__fvg_ds
}
fv.dialogs._arr() {   # CALLER V ARRAY
    if [[ -z $2 || -z ${__FV_VW_LIVE[$2]-} ]]; then fv.dialogs._bad "$1" "'$2' is not a view"; return; fi
    if ! fv.dialogs._aname "$3"; then fv.dialogs._bad "$1" "'$3' is not a usable array name (an identifier; not RESULT, _fv* or __fv*)"; return; fi
    local -n __fvg_aa=$3
    local __fvg_t
    # (the attributes of the elements; ${t#*A}: case-sensitive under nocasematch)
    __fvg_t=${__fvg_aa[*]@a}
    if ! [ "${__fvg_t#*A}" = "$__fvg_t" ]; then fv.dialogs._bad "$1" "'$3' is an associative array"; return; fi
}

# ---- the setters and FV's TDialog helpers ---------------------------------------
# fv.dialogs.setTitle BTN TEXT — the button's Title (its hot key in the
# owner's hot-key map follows), redrawn. RESULT kept
fv.dialogs.setTitle() {
    if (( $# != 2 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._kind "$1" btn setTitle || return
    local -n __fvg_d=${1}_data
    __fvg_d[Title]=$2
    fv.views._hkDirty "${__fvg_d[Owner]-}"
    fv.views.drawView "$1" || :
}
# fv.dialogs.setLabel LB TEXT — a label's (or a static text's) Text, the
# hot-key map kept current, redrawn. RESULT kept
fv.dialogs.setLabel() {
    if (( $# != 2 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._kind "$1" lbl st pt setLabel || return
    local -n __fvg_d=${1}_data
    __fvg_d[Text]=$2
    fv.views._hkDirty "${__fvg_d[Owner]-}"
    fv.views.drawView "$1" || :
}
# fv.dialogs.setItems CLUSTER [ITEM]... — the cluster's items replaced (Sel
# kept inside them), the hot-key map kept current, redrawn. RESULT kept
fv.dialogs.setItems() {
    if (( $# < 1 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._kind "$1" cl setItems || return
    local -n __fvg_d=${1}_data __fvg_it=${1}_items
    local __fvg_v=$1
    # (shift, not "${@:2}": that expansion loses parts under an IFS holding \x01)
    shift
    __fvg_it=("$@")
    if (( ${__fvg_d[Sel]:-0} >= ${#__fvg_it[@]} )); then __fvg_d[Sel]=0; fi
    fv.views._hkDirty "${__fvg_d[Owner]-}"
    fv.views.drawView "$__fvg_v" || :
}
# fv.dialogs.setButtonState CLUSTER MASK 1|0 — FV SetButtonState: the
# EnableMask bits of MASK set (1) or cleared (0); with at most 32 items the
# cluster is selectable while one of them is enabled (FV); redrawn when the
# mask changed (FV leaves that to the caller). RESULT kept
fv.dialogs.setButtonState() {
    if (( $# != 3 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._kind "$1" cl setButtonState || return
    if ! fv.dialogs._num "$2" || ! [[ $3 == [01] ]]; then fv.dialogs._bad setButtonState 'MASK must be digits, ENABLE 1 or 0'; return; fi
    local -n __fvg_d=${1}_data __fvg_it=${1}_items
    local __fvg_o=${__fvg_d[EnableMask]:-0} __fvg_m=$(( 10#$2 )) __fvg_i
    if (( $3 )); then __fvg_d[EnableMask]=$(( __fvg_o | __fvg_m )); else __fvg_d[EnableMask]=$(( __fvg_o & ~__fvg_m )); fi
    if (( ${#__fvg_it[@]} <= 32 )); then
        __fvg_d[Options]=$(( ${__fvg_d[Options]:-0} & ~FV_OF_SELECTABLE ))
        for (( __fvg_i = 0; __fvg_i < ${#__fvg_it[@]}; __fvg_i++ )); do
            if fv.dialogs._clOn "$1" "$__fvg_i"; then __fvg_d[Options]=$(( ${__fvg_d[Options]:-0} | FV_OF_SELECTABLE )); break; fi
        done
    fi
    if ! [ "$__fvg_o" = "${__fvg_d[EnableMask]}" ]; then fv.views.drawView "$1" || :; fi
}
# fv.dialogs.makeDefault BTN 1|0 — FV TButton.MakeDefault. RESULT kept
fv.dialogs.makeDefault() {
    if (( $# != 2 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    fv.dialogs._kind "$1" btn makeDefault || return
    if ! [[ $2 == [01] ]]; then fv.dialogs._bad makeDefault 'ENABLE must be 1 or 0'; return; fi
    local __fvg_rr=${RESULT-}
    fv.dialogs._btnDefault "$1" "$2"
    RESULT=$__fvg_rr
}
# fv.dialogs.newButton G X Y W H TITLE CMD HELPCTX FLAGS — FV TDialog.NewButton:
# a TButton (X, Y)-(X+W, Y+H) with HelpCtx, inserted into G; RESULT = its
# name (reserved: G__fvbtnN). fv.dialogs.newLabel G X Y TEXT LINK — FV
# NewLabel: a TLabel (X, Y)-(X + the text's cells + 1, Y + 1); RESULT =
# G__fvlblN. rc 2: G not a group, a bad number, the constructor's refusal
fv.dialogs.newButton() {
    if (( $# != 9 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    local -a __fvw_v
    if [[ -z ${__FV_VW_GRP[${1:-.}]-} || -z ${__FV_VW_LIVE[$1]-} ]]; then fv.dialogs._bad newButton "'$1' is not a group"; return; fi
    if ! fv.views._ints "$2" "$3" "$4" "$5" || ! fv.dialogs._num "$8"; then fv.dialogs._bad newButton 'X Y W H must be integers, HELPCTX digits'; return; fi
    fv.dialogs._newName "$1" btn
    fv.views._newReserved "$1" "$__fvg_nn" TButton "${__fvw_v[0]}" "${__fvw_v[1]}" "$(( __fvw_v[0] + __fvw_v[2] ))" "$(( __fvw_v[1] + __fvw_v[3] ))" "$6" "$7" "$9" \
        || { fv.dialogs._bad newButton "the button was refused (TITLE CMD FLAGS: $6 $7 $9)"; return; }
    local __fvg_b=$RESULT
    printf -v "${__fvg_b}_data[HelpCtx]" '%d' "$(( 10#$8 ))"
    fv.views.insert "$1" "$__fvg_b" || :
    RESULT=$__fvg_b
}
fv.dialogs.newLabel() {
    if (( $# != 5 )); then fv.dialogs._bad "${FUNCNAME#fv.dialogs.}" 'wrong argument count'; return; fi
    local -a __fvw_v
    if [[ -z ${__FV_VW_GRP[${1:-.}]-} || -z ${__FV_VW_LIVE[$1]-} ]]; then fv.dialogs._bad newLabel "'$1' is not a group"; return; fi
    if ! fv.views._ints "$2" "$3"; then fv.dialogs._bad newLabel 'X Y must be integers'; return; fi
    local __fvg_w __fvg_rr
    fv.video.strWidth "${4//'~'/}" || RESULT=${#4}
    __fvg_w=$RESULT
    fv.dialogs._newName "$1" lbl
    fv.views._newReserved "$1" "$__fvg_nn" TLabel "${__fvw_v[0]}" "${__fvw_v[1]}" "$(( __fvw_v[0] + __fvg_w + 1 ))" "$(( __fvw_v[1] + 1 ))" "$4" "$5" \
        || { fv.dialogs._bad newLabel 'the label was refused'; return; }
    __fvg_rr=$RESULT
    fv.views.insert "$1" "$__fvg_rr" || :
    RESULT=$__fvg_rr
}
# (the caller's __fvg_nn = ROLE + the first N from 1 whose G__fvROLEN is free)
fv.dialogs._newName() {
    local __fvg_i=1
    while [[ -n ${__FV_VW_LIVE[${1}__fv$2$__fvg_i]-} ]]; do __fvg_i=$(( __fvg_i + 1 )); done
    __fvg_nn=$2$__fvg_i
}
