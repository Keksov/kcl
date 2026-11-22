#!/usr/bin/env bash
# fva_testlib.sh — what the fv.app test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only). It reuses fv.menus' test lib (and so
# fv.views': the headless screen, the buffer reader, both counters,
# fvw_budget, fvw_full, the scene classes TTLeaf / TTList, fvw_mktwin) and
# adds:
#
#   fva_init NAME "$@"    ktest init + fv.app (with fv.views, fv.menus) +
#                         $FVW_TMP; the file's stderr is captured as in
#                         fvw_init: anything on it fails one test at exit
#   fva_events SPEC...    the scripted terminal: fv.drivers.getEvent is
#                         replaced (a `declare -f` copy keeps the original as
#                         __fva_orig_getEvent) by a source that answers the
#                         put event first, else pops one SPEC per call:
#                         'key K [CHAR [BASE]]' (FV_EV_CHAR, FV_EV_BASE:
#                         P3 3f), 'cmd C [INFO]', 'bc C [INFO]', 'down X Y',
#                         'up X Y', 'move X Y' (button held), 'moveup X Y'
#                         (no button), 'wheel X Y' (down), 'nothing',
#                         'resize W H'
#                         (what fv.drivers gives after a SIGWINCH:
#                         FV_SCREEN_W/H set, evCommand cmResizeApp, ID W,
#                         INFO H), 'run FN' (runs FN, goes on), 'fail N'
#                         (rc N); an empty queue is the end of input (rc 1,
#                         FV_EV_EOF=1). FVA_N counts the calls, FVA_TO logs
#                         each call's TIMEOUT argument ("T/", '' = none)
#   fva_noevents          the original fv.drivers.getEvent back
#   fva_classes           TMyApp (a TApplication whose HandleEvent, an
#                         override, logs "WHAT:KEY/COMMAND;" into FVA_GOT and
#                         calls inherited: the design's TMyApp)
#   fva_app [W H] [CLASS] a headless application (FV_APP_HEADLESS=1,
#                         frames into $FVW_TMP/screen.out) of CLASS (default
#                         TApplication) named app, with two TWindows w1
#                         (2 1 40 20) and w2 in front (30 5 70 22), a TTLeaf
#                         each (fvw_mktwin; GrowMode gfGrowHiX + HiY), ofTileable,
#                         in the desktop. Not
#                         drawn (Run draws)
#   fva_unapp             app.delete (the hooks back), the original source
#   fva_paint             the first paint as Run does it, without the loop
#                         (sfExposed, drawView, resetCursor)
#   fva_b V               REPLY = V's bounds "AX AY BX BY"

FVA_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVA_TESTS_DIR/../../fv.menus/tests/fvm_testlib.sh"

fva_init() {
    local name=$1
    shift
    source "$FVA_TESTS_DIR/../fv.app.sh"
    kt_test_init "$name" "$FVA_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

FVA_Q=() FVA_N=0 FVA_TO='' FVA_GOT=''
fva_events() {
    FVA_Q=("$@") FVA_N=0 FVA_TO=''
    if ! declare -F __fva_orig_getEvent >/dev/null; then
        local src
        src=$(declare -f fv.drivers.getEvent)
        eval "__fva_orig_getEvent${src#fv.drivers.getEvent}"
        fv.drivers.getEvent() { fva_src "$@"; }
    fi
}
fva_noevents() {
    FVA_Q=()
    if declare -F __fva_orig_getEvent >/dev/null; then
        local src
        src=$(declare -f __fva_orig_getEvent)
        eval "fv.drivers.getEvent${src#__fva_orig_getEvent}"
        unset -f __fva_orig_getEvent
    fi
    __FV_DR_PEND=()
}
fva_src() {
    local s a b c d IFS=' '
    FVA_N=$(( FVA_N + 1 )) FVA_TO+="${1-}/"
    if (( ${#__FV_DR_PEND[@]} )); then __fva_orig_getEvent 0; return; fi
    while :; do
        if (( ! ${#FVA_Q[@]} )); then fv.drivers.clearEvent; FV_EV_EOF=1 RESULT=''; return 1; fi
        s=${FVA_Q[0]}
        FVA_Q=("${FVA_Q[@]:1}")
        read -r a b c d <<< "$s"
        if [ "$a" = run ]; then "$b"; continue; fi
        fv.drivers.clearEvent
        case $a in
            fail) return "$b" ;;
            key) FV_EV_WHAT=evKeyDown FV_EV_KEY=$b FV_EV_CHAR=${c-} FV_EV_BASE=${d-} ;;
            cmd) FV_EV_WHAT=evCommand FV_EV_COMMAND=$b FV_EV_INFO=${c-}${d:+ $d} ;;
            bc) FV_EV_WHAT=evBroadcast FV_EV_COMMAND=$b FV_EV_INFO=${c-}${d:+ $d} ;;
            down) FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_MOUSE_BUTTONS=1 ;;
            up) FV_EV_WHAT=evMouseUp FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c ;;
            moveup) FV_EV_WHAT=evMouseMove FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_MOUSE_BUTTONS=0 ;;
            wheel) FV_EV_WHAT=evMouseWheel FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_WHEEL=2 ;;
            move) FV_EV_WHAT=evMouseMove FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_MOUSE_BUTTONS=1 ;;
            resize) FV_SCREEN_W=$b FV_SCREEN_H=$c; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmResizeApp FV_EV_ID=$b FV_EV_INFO=$c ;;
        esac
        RESULT=$FV_EV_WHAT
        return 0
    done
}

fva_classes() {
    declare -F TMyApp.new >/dev/null && return 0
    fvw_classes2
    class TMyApp : TApplication
        public
            override proc HandleEvent
    end
    TMyApp.HandleEvent() {
        FVA_GOT+="$FV_EV_WHAT:$FV_EV_KEY$FV_EV_COMMAND;"
        inherited HandleEvent "$@"
    }
    build TMyApp
}

fva_app() {
    local w=${1:-80} h=${2:-24} cls=${3:-TApplication}
    fva_classes
    FV_SCREEN_W=$w FV_SCREEN_H=$h FV_APP_HEADLESS=1
    if [[ -n ${FVW_OUTFD-} ]]; then exec {FVW_OUTFD}>&-; fi
    exec {FVW_OUTFD}>"$FVW_TMP/screen.out"
    FV_VIDEO_OUT_FD=$FVW_OUTFD
    "$cls.new" app
    fvw_mktwin w1 2 1 40 20 'Files' 1
    fvw_mktwin w2 30 5 70 22 'Panel two' 2
    w1_data[Options]=$(( w1_data[Options] | FV_OF_TILEABLE ))
    w2_data[Options]=$(( w2_data[Options] | FV_OF_TILEABLE ))
    # (the leaves follow their window: FV views inside a window grow with it)
    w1l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) w2l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    fv.views.insert "$FV_DESKTOP" w1
    fv.views.insert "$FV_DESKTOP" w2
    FVW_DRAWS=() FVW_GOT='' FVW_ROW=() FVA_GOT=''
}
fva_unapp() {
    if declare -F app.delete >/dev/null; then app.delete; fi
    fva_noevents
    : # (Done restores the end-of-input latch)
}
fva_paint() {
    app_data[State]=$(( app_data[State] | FV_SF_EXPOSED ))
    fv.views.drawView app
    fv.views.resetCursor app
}
fva_b() { fv.views.getBounds "$1"; REPLY=$RESULT; }
