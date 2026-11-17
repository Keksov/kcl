#!/usr/bin/env bash
# demo.sh — the kcl fv.app showcase (fv P2): a small Free Vision application
# in bash. Two windows with some text on the desktop, the status line, and
# the window keys of FV:
#
#   F6 / Shift+F6    the next / previous window      Alt+1, Alt+2   window 1 / 2
#   F5               zoom the window (and back)      Alt+F3         close it
#   Ctrl+F5          move it with the arrows, grow it with Shift+arrows,
#                    Enter keeps, Esc puts it back
#   F2 / F3          tile / cascade the windows      Alt+X          quit
#   the mouse        click a window to focus it, drag it by its top row,
#                    grow it by its lower right corner, the [■] / [↑] icons
#
#   bash kcl/fv.app/examples/demo.sh                 # live, in this terminal
#   bash kcl/fv.app/examples/demo.sh --headless      # no terminal (tests, CI)
#
# LIVE (the default) turns the terminal on (alternate screen, mouse) and gives
# it back as it was when the demo ends: Alt+X, or Ctrl+C (an emergency exit:
# the terminal is restored, status 130).
#
# HEADLESS (--headless, or FV_APP_HEADLESS=1 in the environment) touches no
# terminal: the keys come from a file (--keys FILE: the bytes a terminal
# sends, e.g. printf '\e[17~\ex' for F6 then Alt+X; without --keys a built-in
# script that goes through every key above and a mouse drag), the frames go
# to a file (--out FILE, default /dev/null), the size is --size WxH (default
# 80x24), and the demo ends by itself (Alt+X in the keys, or the end of the
# key file). At the end it prints the final screen as text on stdout, one
# line per row.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/../../../kbool.sh" || exit 1
kk.uses fv.app || exit 1

usage() { sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
        *)          echo "demo.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
    esac
    shift
done
[[ $HEADLESS == 1 ]] || HEADLESS=0
if (( ! HEADLESS )) && [[ -n $KEYS$SIZE && ( -n $KEYS || $SIZE != 80x24 ) ]]; then
    echo "demo.sh: --keys and --size are for --headless (live: the terminal's keys and size)" >&2; exit 2
fi

# ---- the application -----------------------------------------------------------
# TDemoText: a view that shows lines of text (DEMO_TEXT_<name>, one array per
# view) and follows its window when the window grows
declare -a DEMO_TEXT_t1=(
    ''
    ' This is Free Vision in bash: kcl fv.app.'
    ''
    ' F6        the next window'
    ' F5        zoom this window'
    ' Ctrl+F5   move it: arrows, Shift+arrows'
    '           to grow, Enter to keep'
    ' F2 / F3   tile / cascade'
    ' Alt+X     quit'
    ''
    ' The mouse: click, drag the top row,'
    ' grow by the lower right corner.'
)
declare -a DEMO_TEXT_t2=(
    ''
    ' The units under this demo:'
    ''
    '   fv.app      TApplication, TDesktop'
    '   fv.menus    TStatusLine'
    '   fv.views    TView, TGroup, TWindow'
    '   fv.drivers  keys, mouse, resize'
    '   fv.video    the screen buffer'
    ''
    ' Привет, мир: wide and Cyrillic text'
    ' are measured in cells.'
)
class TDemoText : TView
    public
        override proc Draw
end
TDemoText.Draw() {
    local -n __demo_l=DEMO_TEXT_$this
    local y s
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        printf -v s '%-*s' "$SizeX" "${__demo_l[y]-}"
        fv.views.writeStr 0 "$y" "$s" 6
    done
}
build TDemoText

class TDemoApp : TApplication
    public
        override proc InitStatusLine
end
TDemoApp.InitStatusLine() {
    TStatusLine.new demo_status 0 $(( SizeY - 1 )) "$SizeX" "$SizeY" \
        '~Alt+X~ Exit' kbAltX cmQuit '~F6~ Next' kbF6 cmNext '~F5~ Zoom' kbF5 cmZoom \
        '~Ctrl+F5~ Move' kbCtrlF5 cmResize '~F2~ Tile' kbF2 cmTile '~F3~ Cascade' kbF3 cmCascade \
        '' kbShiftF6 cmPrev '' kbAltF3 cmClose
    FV_STATUSLINE=demo_status
}
build TDemoApp

# window NAME AX AY BX BY TITLE NUMBER — a window with a TDemoText inside
window() {
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    TDemoText.new "t$7" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 ))
    local -n __demo_t=t${7}_data __demo_w=${1}_data
    __demo_t[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    __demo_w[Options]=$(( __demo_w[Options] | FV_OF_TILEABLE ))
    fv.views.insert "$1" "t$7"
    fv.views.insert "$FV_DESKTOP" "$1"
}

# the built-in headless script: every key of the header, a mouse drag, Alt+X
script() {
    local e=$'\e'
    REPLY="$e[17~"                                 # F6: window 1
    REPLY+="$e[15~$e[15~"                          # F5 zoom, F5 back
    REPLY+="$e[15;5~$e[C$e[C$e[B$e[1;2C$e[1;2B"$'\r'  # Ctrl+F5: move right 2, down 1, grow, Enter
    REPLY+="$e[15;5~$e[D$e[D"$'\r'               # Ctrl+F5: back left 2, Enter (a lone Esc is
    #                                              known only by a pause: none in a file)
    REPLY+="$e[12~"                                # F2: tile
    REPLY+="$e[13~"                                # F3: cascade
    REPLY+="$e[<0;20;2M$e[<32;24;4M$e[<0;24;4m"    # the mouse: drag window 1 by its top row
    REPLY+="$e[17;2~"                              # Shift+F6: the previous window
    REPLY+="$e"'2'                                 # Alt+2
    REPLY+="$e"'x'                                 # Alt+X
}

if (( HEADLESS )); then
    W=${SIZE%x*} H=${SIZE#*x}
    if ! [[ $SIZE == *x* && $W == +([0-9]) && $H == +([0-9]) ]] || (( 10#$W < 1 || 10#$H < 1 )); then
        echo "demo.sh: --size must be WxH, got '$SIZE'" >&2; exit 2
    fi
    W=$(( 10#$W )) H=$(( 10#$H ))
    if [[ -z $KEYS ]]; then
        KEYS=${TMPDIR:-/tmp}/fvdemo.$$.keys
        trap 'rm -f "$KEYS"' EXIT
        script
        printf '%s' "$REPLY" > "$KEYS"
    fi
    [[ -r $KEYS ]] || { echo "demo.sh: cannot read the key file '$KEYS'" >&2; exit 2; }
    exec {DEMO_OUT}>"$OUT" || exit 2
    exec {DEMO_KEYS}<"$KEYS" || exit 2
    FV_APP_HEADLESS=1 FV_SCREEN_W=$W FV_SCREEN_H=$H FV_VIDEO_OUT_FD=$DEMO_OUT FV_KEY_FD=$DEMO_KEYS
else
    FV_APP_HEADLESS=0
fi

TDemoApp.new app || { echo "demo.sh: no terminal (try --headless)" >&2; exit 1; }
window w1 2 1 44 16 'About' 1
window w2 30 6 76 21 'Notes' 2
app.Run
if (( HEADLESS )); then
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; printf '%s\n' "$RESULT"; done
fi
app.delete
exit 0
