#!/usr/bin/env bash
# widgets.sh — the kcl fv P3 showcase: the widgets of Free Vision in bash.
# A menu bar, two file panels (real lists: ASCII and Cyrillic names), a
# dialog with every kind of control, message and input boxes:
#
#   F10, Alt+F/E/W/H the menu bar (File, Edit, Window with a Layout submenu,
#                    Help); the status line shows the hint of the item under
#                    the highlight
#   Up/Down, PgUp/PgDn, Home/End   move in a panel; Ins marks and moves
#                    down, Space marks; the wheel scrolls, a click focuses
#   F6 / Shift+F6    the other panel           F5 zoom    Alt+F3 close
#   F3               File > Find: the dialog — input lines with a history
#                    (Down opens it), a password line, check boxes, radio
#                    buttons, a list box, OK / Cancel / Help; in a line:
#                    Shift+arrows select, Ctrl+Ins copies, Shift+Del cuts,
#                    Shift+Ins pastes (your terminal's own paste works too)
#   F2               File > Rename: an input box for the focused name
#   Alt+X            quit
#
#   bash kcl/fv.dialogs/examples/widgets.sh               # live, in this terminal
#   bash kcl/fv.dialogs/examples/widgets.sh --headless    # no terminal (tests, CI)
#
# LIVE (the default) turns the terminal on and gives it back as it was when
# the demo ends: Alt+X, or Ctrl+C (an emergency exit: status 130).
#
# HEADLESS (--headless, or FV_APP_HEADLESS=1 in the environment) touches no
# terminal: the keys come from a file (--keys FILE: the bytes a terminal
# sends; without --keys a built-in script: marks in both panels, the dialog
# filled in and confirmed, a rename, the About box), the frames go to --out
# FILE (default /dev/null), the size is --size WxH (default 80x24), and the
# demo ends by itself (Alt+X in the keys, or the end of the key file). At the
# end it prints the final screen as text on stdout, one line per row.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/../../../kbool.sh" || exit 1
kk.uses fv.app fv.msgbox || exit 1

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HEADLESS=${FV_APP_HEADLESS:-0} KEYS='' OUT=/dev/null SIZE=80x24
while (( $# )); do
    case $1 in
        --headless) HEADLESS=1 ;;
        --keys)     KEYS=${2:?--keys needs a file}; shift ;;
        --keys=*)   KEYS=${1#*=} ;;
        --out)      OUT=${2:?--out needs a file}; shift ;;
        --out=*)    OUT=${1#*=} ;;
        --size)     SIZE=${2:?--size needs WxH}; shift ;;
        --size=*)   SIZE=${1#*=} ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "widgets.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
    esac
    shift
done
[[ $HEADLESS == 1 ]] || HEADLESS=0
if (( ! HEADLESS )) && [[ -n $KEYS || $SIZE != 80x24 ]]; then
    echo "widgets.sh: --keys and --size are for --headless (live: the terminal's keys and size)" >&2; exit 2
fi

# ---- the data -------------------------------------------------------------------
# the panels' names (FILES1 ASCII, FILES2 Cyrillic) and their marks (Marks, D26)
FILES1=() FILES2=()
for (( i = 1; i <= 300; i++ )); do
    printf -v FILES1[i-1] 'report_%03d.txt' "$i"
    printf -v FILES2[i-1] 'Отчёт_%03d.txt' "$i"
done
declare -A MARKS1=() MARKS2=()
ENCODINGS=(UTF-8 CP1251 KOI8-R CP866 ISO-8859-1 ISO-8859-5 UTF-16LE MacCyrillic)
FIND=('*.txt' 'docs' '' 0 0 0)   # the dialog's data: name folder password options mode encoding
for h in report notes '*.log'; do fv.histlist.historyAdd 1 "$h"; done
for h in docs /var/log; do fv.histlist.historyAdd 2 "$h"; done

# ---- the application ------------------------------------------------------------
class TDemoApp : TApplication
    public
        override proc InitMenuBar
        override proc InitStatusLine
        override proc HandleEvent
end
TDemoApp.InitMenuBar() {            # the bar on request (D23): FV's NewMenu chain, flat
    fv.menus.menuBar \
        sub '~F~ile' \
            item '~F~ind...' F3 kbF3 cmFind 1001 \
            item '~R~ename...' F2 kbF2 cmRename 1002 \
            line \
            item 'E~x~it' Alt+X kbAltX cmQuit 1003 \
        end \
        sub '~E~dit' \
            item '~M~ark all' '' '' cmMarkAll 1101 \
            item '~U~nmark all' '' '' cmUnmarkAll 1102 \
            line \
            item 'Show ~c~lipboard' '' '' cmClip 1103 \
        end \
        sub '~W~indow' \
            item '~N~ext' F6 kbF6 cmNext 1201 \
            item '~Z~oom' F5 kbF5 cmZoom 1202 \
            sub '~L~ayout' 1203 \
                item '~T~ile' '' '' cmTile 1204 \
                item '~C~ascade' '' '' cmCascade 1205 \
            end \
            item '~C~lose' Alt+F3 kbAltF3 cmClose 1206 \
        end \
        sub '~H~elp' \
            item '~K~eys...' F1 kbF1 cmKeys 1301 \
            item '~A~bout...' '' '' cmAbout 1302 \
        end
}
TDemoApp.InitStatusLine() {
    TStatusLine.new demo_status 0 $(( SizeY - 1 )) "$SizeX" "$SizeY" \
        '~Alt+X~ Exit' kbAltX cmQuit '~F10~ Menu' kbF10 cmMenu '~F3~ Find' kbF3 cmFind \
        '~F2~ Rename' kbF2 cmRename '~F6~ Next' kbF6 cmNext \
        '' kbShiftF6 cmPrev '' kbF5 cmZoom '' kbCtrlF5 cmResize '' kbAltF3 cmClose
    FV_STATUSLINE=demo_status
}
TDemoApp.HandleEvent() {
    inherited HandleEvent "$@"
    [ "$FV_EV_WHAT" = evCommand ] || return 0
    case $FV_EV_COMMAND in
        cmFind) find_dialog ;;
        cmRename) rename_item ;;
        cmMarkAll|cmUnmarkAll) mark_all "$FV_EV_COMMAND" ;;
        cmClip) fv.msgbox.messageBox $'\x03''The clipboard:\n'$'\x03''%s' $(( FV_MF_INFORMATION | FV_MF_OKBUTTON )) -- "${FV_CLIPBOARD:-(empty)}" ;;
        cmKeys) keys_box ;;
        cmAbout) fv.msgbox.messageBox $'\x03''kcl fv: Free Vision in bash'$'\n\x03''fv.dialogs  fv.msgbox  fv.menus' $(( FV_MF_INFORMATION | FV_MF_OKBUTTON )) ;;
        *) return 0 ;;
    esac
    fv.views.clearEvent "$this"
}
build TDemoApp

# the dialog's class: Help opens a message box from inside the modal dialog
class TFindDialog : TDialog
    public
        override proc HandleEvent
end
TFindDialog.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmHelp ]; then
        fv.msgbox.messageBox 'Down in a line: its history. Ctrl+Ins copies, Shift+Del cuts, Shift+Ins pastes.' \
            $(( FV_MF_INFORMATION | FV_MF_OKBUTTON ))
        fv.views.clearEvent "$this"
    fi
}
build TFindDialog

# panel NAME AX AY BX BY TITLE NUMBER FILES MARKS HELPCTX HINT — a window
# with a TListViewer over FILES and its standard bar (FV's file panel)
panel() {
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    local -n __pw=${1}_data
    __pw[Options]=$(( __pw[Options] | FV_OF_TILEABLE ))
    fv.views.standardScrollBar "$1" "$FV_SB_VERTICAL"
    TListViewer.new "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 )) 1 '' "$RESULT"
    local -n __pl=${1}l_data __pa=$8
    __pl[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) __pl[List]=$8 __pl[Marks]=$9 __pl[HelpCtx]=${10}
    fv.views.listSetRange "${1}l" "${#__pa[@]}"
    fv.menus.setHint "$FV_STATUSLINE" "${10}" "${11}"
    fv.views.insert "$1" "${1}l"
    fv.views.insert "$FV_DESKTOP" "$1"
}

# focused_list — REPLY = the list of the focused panel ('' when none is left)
focused_list() {
    local c="${FV_DESKTOP}_data[Current]"
    REPLY=${!c}l
    fv.views.isView "$REPLY" || REPLY=''
}

# File > Find: the dialog built, run modal and destroyed (FV), its data kept in FIND
find_dialog() {
    local d=fdlg v
    TFindDialog.new $d 8 1 72 20 'Find files'
    TLabel.new f_l1 3 2 13 3 '~N~ame' f_name
    TInputLine.new f_name 13 2 44 3 64
    THistory.new f_h1 44 2 47 3 f_name 1
    TLabel.new f_l2 3 4 13 5 '~F~older' f_dir
    TInputLine.new f_dir 13 4 44 5 128
    THistory.new f_h2 44 4 47 5 f_dir 2
    TLabel.new f_l3 3 6 13 7 '~P~assword' f_pass
    TInputLine.new f_pass 13 6 44 7 32
    f_pass_data[PasswordChar]='*'
    TLabel.new f_l4 3 8 13 9 '~O~ptions' f_opts
    TCheckBoxes.new f_opts 3 9 30 12 '~C~ase sensitive' '~W~hole words' 'Sub~d~irectories'
    TLabel.new f_l5 32 8 40 9 '~M~ode' f_mode
    TRadioButtons.new f_mode 32 9 48 12 '~T~ext' '~R~egex' 'Wi~l~dcards'
    TLabel.new f_l6 49 2 61 3 '~E~ncoding' f_enc
    TScrollBar.new f_sb 61 3 62 12
    TListBox.new f_enc 49 3 61 12 1 f_sb
    fv.dialogs.newList f_enc ENCODINGS
    TButton.new f_ok 10 15 20 17 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new f_cn 23 15 35 17 'Cancel' cmCancel
    TButton.new f_hp 38 15 48 17 '~H~elp' cmHelp
    for v in f_l1 f_name f_h1 f_l2 f_dir f_h2 f_l3 f_pass f_l4 f_opts f_l5 f_mode f_l6 f_sb f_enc f_ok f_cn f_hp; do
        fv.views.insert $d "$v"
    done
    fv.dialogs.setData $d FIND
    fv.views.select f_name
    fv.views.execView "$FV_DESKTOP" $d
    if [ "$RESULT" = cmOK ]; then fv.dialogs.getData $d FIND; fi
    v=$RESULT
    $d.delete
    if [ "$v" = cmOK ]; then
        local modes=(text regex wildcards) names=('case' 'whole words' 'subdirectories') o='' b
        for b in 0 1 2; do if (( FIND[3] >> b & 1 )); then o+="${o:+, }${names[b]}"; fi; done
        fv.msgbox.messageBox 'Find "%s" in "%s"\n%s, %s, %s\na password of %d characters' \
            $(( FV_MF_INFORMATION | FV_MF_OKBUTTON )) -- "${FIND[0]}" "${FIND[1]}" "${o:-no options}" \
            "${modes[FIND[4]]-?}" "${ENCODINGS[FIND[5]]-?}" "${#FIND[2]}"
    fi
}

# File > Rename: an input box with the focused name; the list redrawn
rename_item() {
    focused_list; [[ -n $REPLY ]] || return 0
    local l=$REPLY
    local -n __rl=${l}_data
    local -n __ra=${__rl[List]}
    local i=${__rl[Focused]:-0} name=${__ra[${__rl[Focused]:-0}]}
    fv.msgbox.inputBox 'Rename' '~N~ew name' name 60
    if [ "$RESULT" != cmCancel ] && [[ -n $name ]]; then __ra[i]=$name; fv.views.drawView "$l"; fi
}

# Edit > Mark all / Unmark all, in the focused panel
mark_all() {
    focused_list; [[ -n $REPLY ]] || return 0
    local l=$REPLY i
    local -n __ml=${l}_data
    local -n __mm=${__ml[Marks]}
    __mm=()
    if [ "$1" = cmMarkAll ]; then for (( i = 0; i < ${__ml[Range]:-0}; i++ )); do __mm[$i]=1; done; fi
    fv.views.drawView "$l"
}

# Help > Keys: a larger message box (messageBoxRect) over the desktop
keys_box() {
    local -n __kd=${FV_DESKTOP}_data
    local x=$(( (__kd[SizeX] - 56) / 2 )) y=$(( (__kd[SizeY] - 14) / 2 )) t
    t='Panels: arrows, PgUp / PgDn, Home / End;'$'\n''Ins / Space mark a file.'$'\n'
    t+='F6 the other panel, F5 zoom, Ctrl+F5 move.'$'\n''F3 Find, F2 Rename, F10 or Alt+letter: the menu.'$'\n'
    t+='In a line: Ctrl+Ins copy, Shift+Del cut,'$'\n''Shift+Ins paste, Down its history.'
    fv.msgbox.messageBoxRect "$x" "$y" $(( x + 56 )) $(( y + 14 )) "$t" $(( FV_MF_INFORMATION | FV_MF_OKBUTTON ))
}

# the built-in headless script (each step: what a user would press)
script() {
    local e=$'\e'
    REPLY="$e[B$e[B$e[2~$e[2~"              # left panel: Down Down, Ins Ins (two marks)
    REPLY+="$e[17~$e[B "                     # F6: the right panel, Down, Space (a mark)
    REPLY+="${e}ff"                          # Alt+F, f: File > Find (the dialog)
    REPLY+="notes$e[1;2H$e[2;5~"             # Name: type over '*.txt', Shift+Home, Ctrl+Ins (copy)
    REPLY+=$'\t'"$e[2;2~/2026"               # Tab to Folder, Shift+Ins (paste over it), more text
    REPLY+=$'\t'"secret"                     # Tab to Password: shown as ******
    REPLY+="${e}w${e}r"$'\r'                 # Alt+W Whole words, Alt+R Regex, Enter = OK
    REPLY+=$'\r'                             # the result's message box: OK
    REPLY+="$e[12~Итоги_2026.txt"$'\r'       # F2: rename the focused file
    REPLY+="${e}ha"$'\r'                     # Help > About, OK
    REPLY+="${e}x"                           # Alt+X
}

if (( HEADLESS )); then
    W=${SIZE%x*} H=${SIZE#*x}
    if ! [[ $SIZE == *x* && $W == +([0-9]) && $H == +([0-9]) ]] || (( 10#$W < 1 || 10#$H < 1 )); then
        echo "widgets.sh: --size must be WxH, got '$SIZE'" >&2; exit 2
    fi
    W=$(( 10#$W )) H=$(( 10#$H ))
    if [[ -z $KEYS ]]; then
        KEYS=${TMPDIR:-/tmp}/fvwidgets.$$.keys
        trap 'rm -f "$KEYS"' EXIT
        script
        printf '%s' "$REPLY" > "$KEYS"
    fi
    [[ -r $KEYS ]] || { echo "widgets.sh: cannot read the key file '$KEYS'" >&2; exit 2; }
    exec {DEMO_OUT}>"$OUT" || exit 2
    exec {DEMO_KEYS}<"$KEYS" || exit 2
    FV_APP_HEADLESS=1 FV_SCREEN_W=$W FV_SCREEN_H=$H FV_VIDEO_OUT_FD=$DEMO_OUT FV_KEY_FD=$DEMO_KEYS
else
    FV_APP_HEADLESS=0
fi

TDemoApp.new app || { echo "widgets.sh: no terminal (try --headless)" >&2; exit 1; }
HALF=$(( FV_SCREEN_W / 2 )) DH="${FV_DESKTOP}_data[SizeY]"; DH=${!DH}
panel w1 0 0 "$HALF" "$DH" 'Files' 1 FILES1 MARKS1 2001 'Ins / Space mark a file'
panel w2 "$HALF" 0 "$FV_SCREEN_W" "$DH" 'Отчёты' 2 FILES2 MARKS2 2002 'Ins / Space mark, F2 rename'
fv.views.select w1
app.Run
if (( HEADLESS )); then
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; printf '%s\n' "$RESULT"; done
fi
app.delete
exit 0
