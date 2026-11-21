#!/usr/bin/env bash
# fvx_testlib.sh — what the fv.msgbox test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only). It reuses fv.app's test lib (and so
# fv.menus' and fv.views': the headless screen, the buffer reader, both
# counters, fvw_full, the scripted terminal fva_events, the headless
# application fva_app) and adds:
#
#   fvx_init NAME "$@"    ktest init + fv.msgbox (with fv.dialogs, fv.views)
#                         + fv.app + $FVW_TMP; the file's stderr is captured
#                         as in fvw_init: anything on it fails one test at exit
#   fvx_app [W H] [CLASS] fva_app (a headless application `app` with two
#                         windows in its desktop), painted (fva_paint), the
#                         end-of-input latch reset
#   fvx_unapp             fva_unapp, the latch reset
#   fvx_events SPEC...    fva_events with two more specs: 'char C' (kbChar
#                         C; `_` stands for a blank) and 'alt L' (kbAlt + L
#                         upper-cased, FV_EV_CHAR L)
#   fvx_box               FVX_D = the message box family's first name
#                         (${FV_DESKTOP}__fvmsgbox)
#   fvx_rows Y1 Y2        REPLY = rows Y1..Y2-1 of the screen, text only,
#                         joined by '|'
#   fvx_snap [Y1 Y2]      FVX_SNAP = the same, taken by a `run fvx_snap`
#                         spec while a box runs (default rows 0..24)
#   fvx_boxes             REPLY = the live boxes (the family's dialogs)
#   fvx_live              REPLY = the live views whose name holds
#                         `__fvmsgbox` (none after every call)

FVX_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVX_TESTS_DIR/../../fv.app/tests/fva_testlib.sh"

fvx_init() {
    local name=$1
    shift
    source "$FVX_TESTS_DIR/../fv.msgbox.sh"
    source "$FVX_TESTS_DIR/../../fv.app/fv.app.sh"
    kt_test_init "$name" "$FVX_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

fvx_app() {
    fva_app "$@"
    fva_paint
    __FV_VW_EOF=0
}
fvx_unapp() {
    fva_unapp
    __FV_VW_EOF=0
}

fvx_events() {
    fva_events "$@"
    fv.drivers.getEvent() { fvx_src "$@"; }
}
fvx_src() {
    local s a b c IFS=' '
    if (( ${#__FV_DR_PEND[@]} )) || (( ! ${#FVA_Q[@]} )); then fva_src "$@"; return; fi
    s=${FVA_Q[0]}
    read -r a b c <<< "$s"
    if [ "$a" = char ] || [ "$a" = alt ]; then
        FVA_Q=("${FVA_Q[@]:1}")
        FVA_N=$(( FVA_N + 1 ))
        fv.drivers.clearEvent
        if [ "$b" = _ ]; then b=' '; fi
        if [ "$a" = char ]; then FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=$b
        else FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt${b^^} FV_EV_CHAR=$b; fi
        RESULT=$FV_EV_WHAT
        return 0
    fi
    fva_src "$@"
}

fvx_box() { FVX_D=${FV_DESKTOP}__fvmsgbox; }
fvx_rows() {
    local y s=''
    for (( y = $1; y < $2; y++ )); do fv.video.getRow "$y"; s+="$RESULT|"; done
    REPLY=$s
}
FVX_SNAP=''
fvx_snap() { fvx_rows "${1:-0}" "${2:-${FV_SCREEN_H:-24}}"; FVX_SNAP=$REPLY; }
fvx_live() {
    local v s=''
    for v in "${!__FV_VW_LIVE[@]}"; do [[ $v == *__fvmsgbox* ]] && s+="$v "; done
    REPLY=$s
}
# fvx_boxes: REPLY = the live boxes only (the family's dialogs, not their
# controls), sorted by depth
fvx_boxes() {
    local v s='' n
    for n in '' 2 3 4 5 6 7 8 9; do
        v=${FV_DESKTOP}__fvmsgbox$n
        if [[ -n ${__FV_VW_LIVE[$v]-} ]]; then s+="$v "; fi
    done
    REPLY=$s
}

# fvx_scenefile — writes $FVW_TMP/scene.sh: a child scene for 005 / 006. It
# loads fv.msgbox and fv.app, makes a headless 80 x 24 application (drawn),
# runs eval "$SETUP", then every public function through the scripted
# source (keys, characters, clicks, nested boxes, refusals), and prints the
# answers, '#', and whether the caller's state (IFS, $-, BASHOPTS, LC_ALL,
# a Cyrillic string's length) is unchanged ("same"); then eval "$RESTORE"
fvx_scenefile() {
    cat > "$FVW_TMP/scene.sh" <<SCENE
source '$FVX_TESTS_DIR/../fv.msgbox.sh'
source '$FVX_TESTS_DIR/../../fv.app/fv.app.sh'
exec {FVO}>/dev/null
FV_VIDEO_OUT_FD=\$FVO FV_APP_HEADLESS=1 FV_SCREEN_W=80 FV_SCREEN_H=24
TApplication.new app
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED )); fv.views.drawView app
src=\$(declare -f fv.drivers.getEvent); eval "__orig\${src#fv.drivers.getEvent}"
q=()
fv.drivers.getEvent() {
    local s k
    if (( \${#__FV_DR_PEND[@]} )); then __orig 0; return; fi
    while :; do
        if (( ! \${#q[@]} )); then fv.drivers.clearEvent; FV_EV_EOF=1; return 1; fi
        s=\${q[0]}; q=("\${q[@]:1}")
        k=\${s%%:*} s=\${s#*:}
        if [ "\$k" = run ]; then "\$s"; continue; fi
        fv.drivers.clearEvent
        case \$k in
            key) FV_EV_WHAT=evKeyDown FV_EV_KEY=\$s ;;
            char) FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=\$s ;;
            down) FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=\${s%%:*} FV_EV_MOUSE_Y=\${s#*:} FV_EV_MOUSE_BUTTONS=1 ;;
            up) FV_EV_WHAT=evMouseUp FV_EV_MOUSE_X=\${s%%:*} FV_EV_MOUSE_Y=\${s#*:} ;;
        esac
        RESULT=\$FV_EV_WHAT
        return 0
    done
}
st() { printf -v "\$1" '%s|' "\${IFS@Q}" "\$-" "\$BASHOPTS" "\${LC_ALL-unset}" "\${#ZH}"; }
row() { fv.video.getRow "\$1"; r+="\$RESULT|"; }
inner() { fv.msgbox.messageBox 'Inner %s' "\$FV_MF_OKCANCEL" -- 'ok'; r+="in:\$RESULT|"; }
ZH=ж
eval "\$SETUP"
st S0
r=''
RESULT=keep
q=('run:r9' 'key:kbTab' 'key:kbEnter')
r9() { row 9; row 13; }
fv.msgbox.messageBox 'Файл %s: %d строк' "\$(( FV_MF_ERROR | FV_MF_YESNOCANCEL ))" -- 'жук.txt' 12 surplus; r+="\$RESULT|"
q=('char:n')
fv.msgbox.messageBox 'Save? 100%' "\$(( FV_MF_CONFIRMATION | FV_MF_YESNOCANCEL ))"; r+="\$RESULT|"
q=('down:37:13' 'up:37:13')
fv.msgbox.messageBox 'Click' "\$FV_MF_YESNOCANCEL"; r+="\$RESULT|"
q=('run:r10' 'key:kbEsc')
r10() { row 10; }
fv.msgbox.messageBoxRect 2 2 42 11 'Rect' "\$(( FV_MF_OKBUTTON | FV_MF_INSERTINAPP ))"; r+="\$RESULT|"
v='старое'
q=('run:r9' 'key:kbEnd' 'char:ж' 'char:中' 'char:x' 'key:kbEnter')
fv.msgbox.inputBox 'Имя' '~И~мя' v 8; r+="\$RESULT:\$v|"
pw='секрет'
q=('run:r9' 'char:中' 'key:kbEnter')
fv.msgbox.inputBox -p 'Login' '~P~ass' pw 20; r+="\$RESULT:\$pw|"
v='keep'
q=('char:z' 'run:inner' 'key:kbEnter' 'key:kbEsc')
fv.msgbox.inputBoxRect 1 1 61 9 'Outer' 'L' v 10; r+="\$RESULT:\$v|"
fv.msgbox.messageBox 'x' 99999 || r+="rc\$?:\$RESULT|"
fv.msgbox.inputBox 'T' 'L' RESULT 5 || r+="rc\$?|"
fv.msgbox.inputBox 'T' 'L' v x5 || r+="rc\$?|"
n=0; for k in "\${!__FV_VW_LIVE[@]}"; do [[ \$k == *__fvmsgbox* ]] && n=\$(( n + 1 )); done; r+="live \$n|"
st S1
eval "\${RESTORE:-:}"
if [ "\$S0" = "\$S1" ]; then printf '%s#same' "\$r"; else printf '%s#%s -> %s' "\$r" "\$S0" "\$S1"; fi
SCENE
}
