#!/usr/bin/env bash
# fvw_testlib.sh — what the fv.views test files share. Not a test file: the
# ktests runner picks up NNN_*.sh only. Headless: no terminal is touched,
# frames go to a file (never initVideo).
#
#   fvw_init NAME "$@"    ktest init + the unit + a scratch folder ($FVW_TMP);
#                         the file's stderr is captured: anything on it fails
#                         one test at exit (fvw_errcheck)
#   fvw_screen [W H]      a headless screen buffer (default 80x24): fv.video
#                         initScreen with frames into $FVW_TMP/screen.out
#   fvw_row Y             RESULT = row Y of the buffer as text, REPLY = its
#                         palette symbols (fv.video.getRow)
#   fvw_check TITLE WANT GOT
#                         one test: pass when GOT == WANT
#   fvw_count_on / fvw_count_off
#                         count kklass dispatches in FVW_CALLS: counting shims
#                         around kk._exec (obj.M, $this.M), kk._call (.call),
#                         kk._parent (inherited) and kk._constructor_exec
#                         (.new), made from `declare -f` copies (kklass book,
#                         "Friend tables": tests may wrap them; rc, RESULT,
#                         set -e and $( ) unchanged). A missing dispatcher
#                         name fails loudly (rc 1, a message on stderr)
#   fvw_writes_on / fvw_writes_off
#                         count fv.video writes in FVW_WRITES the same way
#                         (writeStr writeBuf writeCStr writeChar fillRect
#                         shadeRect fillColumns; the friend
#                         entries fv.video._shadef, _wstr, _fcf, _wbf and _wrows
#                         count as shadeRect, writeStr, fillColumns, writeBuf
#                         and one write per writeLines call)
#   fvw_budget LABEL LIMIT CMD...
#                         one test: run CMD with the dispatch counter on;
#                         pass when it made at most LIMIT dispatches; the
#                         count is logged ("# calls LABEL N")
#   fvw_budgetw LABEL LIMIT CMD...
#                         the same with the write counter on in the same run;
#                         logs "# writes LABEL N" too; FVW_LASTC / FVW_LASTW
#   fvw_tree G            REPLY = "G[a b c]*cur" — G's subviews back to
#                         front and its Current, nested groups in braces
#   fvw_forks LINE        rc 0 when a code line holds a construct that forks
#                         (the scan of fv.video's 006, reused)
#   fvw_expose G          G's State += sfExposed (a root that is drawn: fv.app
#                         sets it on the application)
#   fvw_cells X Y W       RESULT = W cells of row Y from column X (text),
#                         REPLY = their symbols (narrow text only)
#   fvw_classes           the scene classes (stage 2c-2): TTWin (a TGroup
#                         with TWindow's Flags Title Number Palette fields and
#                         TWindow's GetPalette, an override: 1 dispatch per
#                         palette resolution), TTList (a leaf whose Draw, an
#                         override, writes "row N of NAME" padded to its width
#                         on each row the paint may change (FV_CLIP_Y1..Y2) in
#                         colour 1, counting its calls in FVW_DRAWS[NAME])
#   fvw_mkwin NAME AX AY BX BY TITLE NUM
#                         a TTWin with FV's flags (move grow close zoom),
#                         sfShadow, ofSelectable + ofTopSelect, a full-size
#                         TFrame NAME__fvframe and a TTList NAMEl inside
#   fvw_scene [W H]       a headless screen and the desktop-like scene: root
#                         group desk (exposed), a TView bg filling it, two
#                         framed windows w1 (2 1 40 20) and w2 (in front,
#                         30 5 70 22, active frame) with shadows and lists,
#                         not drawn yet
#   fvw_unscene           desk.delete
#   fvw_outsize           REPLY = the size of the frames written so far
#   fvw_snap              REPLY = every row's text and symbols
#   fvw_full ROOT         rc 0 when the screen equals a full repaint of ROOT
#                         from garbage; FVW_DIFF = the rows that differ
# Stage 2c-3 (events, focus, modal views):
#   fvw_events SPEC...    the scripted event source: __FV_VW_GETEVENT =
#                         fvw_getev, which answers fv.drivers' put event
#                         first (TWindow's modal cmClose posts one), else
#                         pops one SPEC per call: 'key K', 'cmd C [INFO]',
#                         'bc C [INFO]', 'down X Y', 'up X Y', 'move X Y',
#                         'wheel X Y', 'nothing'; 'run FN' runs FN and goes
#                         on; 'fail N' is rc N. An empty queue is the end
#                         of input (rc 1, FV_EV_EOF=1). FVW_EVN counts the
#                         calls. fvw_noevents: back to fv.drivers.getEvent,
#                         the EOF latch reset
#   fvw_root G            G as fv.app makes the application: sfExposed,
#                         sfSelected and sfModal, then sfFocused through
#                         setState (the focus chain below it)
#   fvw_classes2          TTApp (a TGroup whose HandleEvent, an override,
#                         calls inherited and then takes cmNext as FV's
#                         TDesktop does: focusNext Current 0 — the design's
#                         TMyApp + desktop), TTLeaf (a TTList whose
#                         HandleEvent, an override, records each event in
#                         FVW_GOT ("NAME:WHAT:KEY/COMMAND;"), moves its
#                         marked row on kbDown with two drawParts, and calls
#                         inherited only for a mouse-down; its Draw and the
#                         drawPart painter fvw_leafrow write "row N of NAME",
#                         '>' on the marked row FVW_ROW[NAME])
#   fvw_mktwin NAME AX AY BX BY TITLE NUM [CLASS]
#                         a TWindow (its frame NAME__fvframe from InitFrame)
#                         with a selectable leaf NAMEl (TTLeaf or CLASS)
#                         over its interior
#   fvw_tscene [W H] [side]
#                         a headless screen and the events scene: root app
#                         (TTApp, fvw_root) > desk (TGroup, full size) > bg
#                         (TView), w1 (2 1 40 20) and w2 in front (30 5 70
#                         22); `side`: w1 0 0 40 23 and w2 40 0 80 23. Not
#                         drawn yet
# Stage 2g (the call budget, design §3.1):
#   fvw_classes3          TTestList (design §3.1's list stand-in: a TView
#                         with TView's default EventMask and fields Top /
#                         Focused; Draw, an override, writes its visible
#                         rows with ONE fv.views.writeLines call (D21 stage
#                         E, as P3's TListViewer: one fv.video write per
#                         list; " item N" in palette entry 6, the focused
#                         row in entry 7; rows FV_CLIP_Y1..Y2-1);
#                         HandleEvent, an override: kbDown -> two drawParts
#                         (the old and the new focused row, painter
#                         fvw_tlpaint), kbPgDn -> the next page (Top +=
#                         SizeY: every row a new text) and drawView, both
#                         handled; a mouse-down goes to inherited (TView's:
#                         select); anything else is ignored, as TTLeaf does.
#                         Counts its Draws in FVW_DRAWS[NAME])
#   fvw_mklwin NAME AX AY BX BY TITLE NUM
#                         a TWindow with a selectable TTestList NAMEl over
#                         its interior
#
# Timing runs never use the shims.

FVW_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVW_TESTS_DIR/../../../ktests/ktest.sh"

fvw_init() {
    local name=$1
    shift
    source "$FVW_TESTS_DIR/../fv.views.sh"
    kt_test_init "$name" "$FVW_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    # every test file's stderr goes to a file; at exit (before ktest's own
    # trap reports the counts) anything there is one failed test: a test
    # that expects stderr redirects it itself
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

fvw_errcheck() {
    exec 2>&"$FVW_ERRFD"
    if [[ -s $FVW_ERR ]]; then
        local e
        e=$(head -c 800 "$FVW_ERR")
        kt_test_start "no unexpected output on stderr"
        kt_test_fail "$e"
    fi
}

fvw_screen() {
    FV_SCREEN_W=${1:-80} FV_SCREEN_H=${2:-24}
    if [[ -n ${FVW_OUTFD-} ]]; then exec {FVW_OUTFD}>&-; fi
    exec {FVW_OUTFD}>"$FVW_TMP/screen.out"
    FV_VIDEO_OUT_FD=$FVW_OUTFD
    fv.video.initScreen
}

fvw_row() { fv.video.getRow "$1"; }

fvw_check() {
    kt_test_start "$1"
    if [[ "$3" == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}

FVW_CALLS=0 FVW_WRITES=0
FVW_DISPATCHERS=(kk._exec kk._call kk._parent kk._constructor_exec)
FVW_WRITERS=(fv.video.writeStr fv.video.writeBuf fv.video.writeCStr fv.video.writeChar fv.video.fillRect fv.video.shadeRect fv.video.fillColumns fv.video._shadef fv.video._wstr fv.video._fcf fv.video._wbf fv.video._wrows)

# fvw_wrap COUNTER FUNC... / fvw_unwrap FUNC... — the shim: FUNC becomes
# "COUNTER += 1; __fvw_orig_FUNC "$@"" (the original's last command), the
# original kept as __fvw_orig_FUNC; unwrap redefines the original text
fvw_wrap() {
    local c=$1 f src
    shift
    for f; do
        if ! declare -F "$f" >/dev/null; then echo "fvw_wrap: no function $f" >&2; return 1; fi
        declare -F "__fvw_orig_$f" >/dev/null && continue
        src=$(declare -f "$f")
        eval "__fvw_orig_${src}"
        eval "$f() { $c=\$(( $c + 1 )); __fvw_orig_$f \"\$@\"; }"
    done
}
fvw_unwrap() {
    local f src
    for f; do
        declare -F "__fvw_orig_$f" >/dev/null || continue
        src=$(declare -f "__fvw_orig_$f")
        eval "${src#__fvw_orig_}"
        unset -f "__fvw_orig_$f"
    done
}
fvw_count_on() { fvw_wrap FVW_CALLS "${FVW_DISPATCHERS[@]}"; }
fvw_count_off() { fvw_unwrap "${FVW_DISPATCHERS[@]}"; }
fvw_writes_on() { fvw_wrap FVW_WRITES "${FVW_WRITERS[@]}"; }
fvw_writes_off() { fvw_unwrap "${FVW_WRITERS[@]}"; }

fvw_budget() {
    local label=$1 limit=$2
    shift 2
    kt_test_start "budget $label: at most $limit dispatches"
    if ! fvw_count_on; then kt_test_fail "the dispatch shim could not be installed"; return; fi
    FVW_CALLS=0
    "$@"
    local n=$FVW_CALLS
    fvw_count_off
    kt_test_log "# calls $label $n"
    if (( n <= limit )); then kt_test_pass "$n dispatches"; else kt_test_fail "$n dispatches > $limit"; fi
}
# fvw_budgetw LABEL LIMIT CMD... — fvw_budget with the write counter on in
# the same run (one run: an action that changes the scene is counted once);
# logs "# calls LABEL N" and "# writes LABEL N"; FVW_LASTC / FVW_LASTW = the
# counts
fvw_budgetw() {
    local label=$1 limit=$2
    shift 2
    kt_test_start "budget $label: at most $limit dispatches"
    if ! fvw_count_on || ! fvw_writes_on; then kt_test_fail "the shims could not be installed"; return; fi
    FVW_CALLS=0 FVW_WRITES=0
    "$@"
    FVW_LASTC=$FVW_CALLS FVW_LASTW=$FVW_WRITES
    fvw_count_off
    fvw_writes_off
    kt_test_log "# calls $label $FVW_LASTC"
    kt_test_log "# writes $label $FVW_LASTW"
    if (( FVW_LASTC <= limit )); then kt_test_pass "$FVW_LASTC dispatches, $FVW_LASTW writes"; else kt_test_fail "$FVW_LASTC dispatches > $limit ($FVW_LASTW writes)"; fi
}

fvw_tree() {
    local g=$1 k out
    local -n __t_l=${g}_views __t_d=${g}_data
    out="$g["
    for k in "${__t_l[@]}"; do
        if [[ -n ${__FV_VW_GRP[$k]-} ]]; then fvw_tree "$k"; out+="{$REPLY} "; else out+="$k "; fi
    done
    out="${out% }]"
    if [[ -n ${__t_d[Current]-} ]]; then out+="*${__t_d[Current]}"; fi
    REPLY=$out
}

fvw_expose() {
    local -n __t_d=${1}_data
    __t_d[State]=$(( ${__t_d[State]:-0} | FV_SF_EXPOSED ))
}

fvw_cells() {
    fv.video.getRow "$2"
    RESULT=${RESULT:$1:$3} REPLY=${REPLY:$1:$3}
}

fvw_classes() {
    declare -F TTWin.new >/dev/null && return 0
    declare -gA FVW_DRAWS=()
    class TTWin : TGroup
        public
            var Flags
            var Title
            var Number
            var Palette
            override func GetPalette
    end
    TTWin.GetPalette() {
        case ${Palette:-0} in
            1) RESULT='16 17 18 19 20 21 22 23' ;;
            2) RESULT='24 25 26 27 28 29 30 31' ;;
            *) RESULT='8 9 10 11 12 13 14 15' ;;
        esac
    }
    build TTWin
    class TTList : TView
        public
            override proc Draw
    end
    TTList.Draw() {
        local y s
        FVW_DRAWS[$this]=$(( ${FVW_DRAWS[$this]:-0} + 1 ))
        # (each row padded to the width: FV's "Draw must cover the whole view";
        # only the rows this paint may change: FV_CLIP_Y1 .. FV_CLIP_Y2 - 1)
        for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
            printf -v s '%-*s' "$SizeX" "row $y of $this"
            fv.views.writeStr 0 "$y" "${s:0:SizeX}" 1
        done
    }
    build TTList
}

fvw_mkwin() {
    fvw_classes
    TTWin.new "$1" "$2" "$3" "$4" "$5"
    local -n __t_d=${1}_data
    __t_d[Flags]=$(( FV_WF_MOVE | FV_WF_GROW | FV_WF_CLOSE | FV_WF_ZOOM )) __t_d[Title]=$6 __t_d[Number]=$7 __t_d[Palette]=0
    __t_d[State]=$(( __t_d[State] | FV_SF_SHADOW )) __t_d[Options]=$(( __t_d[Options] | FV_OF_SELECTABLE | FV_OF_TOPSELECT ))
    fv.views._newReserved "$1" frame TFrame 0 0 $(( $4 - $2 )) $(( $5 - $3 ))
    fv.views.insert "$1" "$RESULT"
    TTList.new "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 ))
    fv.views.insert "$1" "${1}l"
}

fvw_scene() {
    fvw_screen "${1:-80}" "${2:-24}"
    TGroup.new desk 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H"
    TView.new bg 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H"
    fv.views.insert desk bg
    fvw_mkwin w1 2 1 40 20 'Files' 1
    fvw_mkwin w2 30 5 70 22 'Panel two' 2
    fv.views.insert desk w1
    fv.views.insert desk w2
    w2__fvframe_data[State]=$(( w2__fvframe_data[State] | FV_SF_ACTIVE ))
    fvw_expose desk
    FVW_DRAWS=()
}
fvw_unscene() { desk.delete; }

# ---- stage 2c-3 ----------------------------------------------------------------
FVW_EVQ=() FVW_EVN=0 FVW_GOT=''
fvw_events() { FVW_EVQ=("$@"); FVW_EVN=0; __FV_VW_GETEVENT=fvw_getev; }
fvw_noevents() { FVW_EVQ=(); __FV_VW_GETEVENT=fv.drivers.getEvent; __FV_VW_EOF=0; __FV_DR_PEND=(); }
fvw_getev() {
    local s a b c IFS=' '
    FVW_EVN=$(( FVW_EVN + 1 ))
    if (( ${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    while :; do
        if (( ! ${#FVW_EVQ[@]} )); then fv.drivers.clearEvent; FV_EV_EOF=1; return 1; fi
        s=${FVW_EVQ[0]}
        FVW_EVQ=("${FVW_EVQ[@]:1}")
        read -r a b c <<< "$s"
        if [ "$a" = run ]; then "$b"; continue; fi
        fv.drivers.clearEvent
        case $a in
            fail) return "$b" ;;
            key) FV_EV_WHAT=evKeyDown FV_EV_KEY=$b ;;
            cmd) FV_EV_WHAT=evCommand FV_EV_COMMAND=$b FV_EV_INFO=${c-} ;;
            bc) FV_EV_WHAT=evBroadcast FV_EV_COMMAND=$b FV_EV_INFO=${c-} ;;
            down) FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_MOUSE_BUTTONS=1 ;;
            up) FV_EV_WHAT=evMouseUp FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c ;;
            move) FV_EV_WHAT=evMouseMove FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_MOUSE_BUTTONS=1 ;;
            wheel) FV_EV_WHAT=evMouseWheel FV_EV_MOUSE_X=$b FV_EV_MOUSE_Y=$c FV_EV_WHEEL=2 ;;
        esac
        RESULT=$FV_EV_WHAT
        return 0
    done
}

fvw_root() {
    local -n __t_d=${1}_data
    __t_d[State]=$(( __t_d[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
    fv.views.setState "$1" "$FV_SF_FOCUSED" 1
}

fvw_classes2() {
    declare -F TTApp.new >/dev/null && return 0
    fvw_classes
    declare -gA FVW_ROW=()
    class TTApp : TGroup
        public
            override proc HandleEvent
    end
    TTApp.HandleEvent() {
        inherited HandleEvent "$@"
        if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmNext ]; then
            fv.views.focusNext "$Current" 0
            fv.views.clearEvent "$this"
        fi
    }
    build TTApp
    class TTLeaf : TTList
        public
            override proc Draw
            override proc HandleEvent
    end
    TTLeaf.Draw() {
        FVW_DRAWS[$this]=$(( ${FVW_DRAWS[$this]:-0} + 1 ))
        fvw_leafrow "$this"
    }
    TTLeaf.HandleEvent() {
        FVW_GOT+="$this:$FV_EV_WHAT:$FV_EV_KEY$FV_EV_COMMAND;"
        if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbDown ]; then
            local o=${FVW_ROW[$this]:-0} n
            n=$(( (o + 1) % SizeY ))
            FVW_ROW[$this]=$n
            fv.views.drawPart "$this" fvw_leafrow "$o" "$(( o + 1 ))"
            fv.views.drawPart "$this" fvw_leafrow "$n" "$(( n + 1 ))"
            fv.views.clearEvent "$this"
        elif [ "$FV_EV_WHAT" = evMouseDown ]; then
            inherited HandleEvent "$@"
        fi
    }
    build TTLeaf
}
fvw_leafrow() {
    local -n __t_d=${1}_data
    local y s m w=${__t_d[SizeX]:-0}
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        m=' '
        if (( y == ${FVW_ROW[$1]:-0} )); then m='>'; fi
        printf -v s '%-*s' "$w" "${m}row $y of $1"
        fv.views.writeStr 0 "$y" "${s:0:w}" 1
    done
}

fvw_mktwin() {
    fvw_classes2
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    "${8:-TTLeaf}.new" "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 ))
    local -n __t_d=${1}l_data
    __t_d[Options]=$(( __t_d[Options] | FV_OF_SELECTABLE ))
    fv.views.insert "$1" "${1}l"
}

fvw_tscene() {
    fvw_screen "${1:-80}" "${2:-24}"
    fvw_classes2
    TTApp.new app 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H"
    TGroup.new desk 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H"
    TView.new bg 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H"
    fv.views.insert desk bg
    if [ "${3-}" = side ]; then
        fvw_mktwin w1 0 0 40 23 'Files' 1
        fvw_mktwin w2 40 0 80 23 'Panel two' 2
    else
        fvw_mktwin w1 2 1 40 20 'Files' 1
        fvw_mktwin w2 30 5 70 22 'Panel two' 2
    fi
    fv.views.insert desk w1
    fv.views.insert desk w2
    fv.views.insert app desk
    fvw_root app
    FVW_DRAWS=() FVW_GOT='' FVW_ROW=()
}
fvw_untscene() { app.delete; }

# ---- stage 2g --------------------------------------------------------------------
fvw_classes3() {
    declare -F TTestList.new >/dev/null && return 0
    fvw_classes2
    declare -gA FVW_TLA=()
    class TTestList : TView
        public
            var Top
            var Focused
            override proc Draw
            override proc HandleEvent
    end
    TTestList.Draw() {
        FVW_DRAWS[$this]=$(( ${FVW_DRAWS[$this]:-0} + 1 ))
        fvw_tlpaint "$this" "${Top:-0}" "${Focused:-0}"
    }
    TTestList.HandleEvent() {
        if [ "$FV_EV_WHAT" = evKeyDown ]; then
            if [ "$FV_EV_KEY" = kbDown ]; then
                local o=${Focused:-0} n
                n=$(( (o + 1) % SizeY ))
                Focused=$n
                fv.views.drawPart "$this" fvw_tlpaint "$o" "$(( o + 1 ))" "${Top:-0}" "$n"
                fv.views.drawPart "$this" fvw_tlpaint "$n" "$(( n + 1 ))" "${Top:-0}" "$n"
                fv.views.clearEvent "$this"
            elif [ "$FV_EV_KEY" = kbPgDn ]; then
                Top=$(( ${Top:-0} + SizeY ))
                fv.views.drawView "$this"
                fv.views.clearEvent "$this"
            fi
        elif [ "$FV_EV_WHAT" = evMouseDown ]; then
            inherited HandleEvent "$@"
        fi
    }
    build TTestList
}
# fvw_tlpaint V TOP FOCUSED — the stand-in's rows FV_CLIP_Y1 .. FV_CLIP_Y2-1
# in one writeLines call (D21 stage E; element y = row y; a single row with
# writeLine, as a list's FocusItem repaint), attributes resolved from
# FV_DRAW_PAL (entry 6 normal, 7 focused; FV's TDrawBuffer holds resolved
# attributes), the strings of attributes kept per symbol and width
fvw_tlpaint() {
    local -n __t_d=${1}_data
    local y s a n=${FV_DRAW_PAL:5:1} f=${FV_DRAW_PAL:6:1} w=${__t_d[SizeX]:-0}
    local -a tt=() aa=()
    [[ -n $n ]] || n=${FV_DRAW_PAL:0:1}
    [[ -n $f ]] || f=$n
    if [[ -z ${FVW_TLA[$n$w]-} ]]; then printf -v a '%*s' "$w" ''; FVW_TLA[$n$w]=${a// /$n}; fi
    if [[ -z ${FVW_TLA[$f$w]-} ]]; then printf -v a '%*s' "$w" ''; FVW_TLA[$f$w]=${a// /$f}; fi
    if (( FV_CLIP_Y2 - FV_CLIP_Y1 == 1 )); then
        # (one row, e.g. kbDown's drawPart: writeLine, as a list's FocusItem
        # repaint does; writeLines pays ~50 us more for a single row)
        y=$FV_CLIP_Y1
        printf -v s '%-*s' "$w" " item $(( $2 + y ))"
        if (( y == $3 )); then a=${FVW_TLA[$f$w]}; else a=${FVW_TLA[$n$w]}; fi
        fv.views.writeLine 0 "$y" 1 "${s:0:w}" "$a"
        return
    fi
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        printf -v s '%-*s' "$w" " item $(( $2 + y ))"
        tt[y]=${s:0:w}
        if (( y == $3 )); then aa[y]=${FVW_TLA[$f$w]}; else aa[y]=${FVW_TLA[$n$w]}; fi
    done
    fv.views.writeLines 0 0 tt aa
}
fvw_mklwin() {
    fvw_classes3
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    TTestList.new "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 ))
    local -n __t_d=${1}l_data
    __t_d[Options]=$(( __t_d[Options] | FV_OF_SELECTABLE ))
    fv.views.insert "$1" "${1}l"
}

# fvw_snap -> REPLY = every row's text and symbols
fvw_snap() {
    local y s=''
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; s+="$RESULT|$REPLY"$'\n'; done
    REPLY=$s
}
# fvw_full ROOT -> rc 0 when the screen equals a full repaint of ROOT from
# garbage ('#' in symbol Z everywhere first); FVW_DIFF = the rows that differ
fvw_full() {
    local a b i
    local -a x y
    fvw_snap; a=$REPLY
    fv.video.resetClip
    fv.video.fillRect 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H" Z '#'
    fv.views.drawView "$1"
    fvw_snap; b=$REPLY
    FVW_DIFF=''
    if [[ $a == "$b" ]]; then return 0; fi
    mapfile -t x <<< "$a"; mapfile -t y <<< "$b"
    for i in "${!x[@]}"; do [[ ${x[i]} == "${y[i]-}" ]] || FVW_DIFF+=" row $i: [${x[i]}] vs full [${y[i]-}]"; done
    return 1
}

fvw_outsize() {
    local s
    s=$(wc -c < "$FVW_TMP/screen.out")
    REPLY=${s//[!0-9]/}
}

# (only the function's text is taken from fvv_testlib.sh: sourcing that file
# would source ktest.sh a second time)
fvw_forks() {
    if ! declare -F fvv_forks >/dev/null; then
        local l src='' on=0
        while IFS= read -r l || [[ -n $l ]]; do
            if [[ $l == 'fvv_forks() {' ]]; then on=1; fi
            if (( on )); then src+=$l$'\n'; fi
            if (( on )) && [[ $l == '}' ]]; then break; fi
        done < "$FVW_TESTS_DIR/../../fv.video/tests/fvv_testlib.sh"
        eval "$src"
    fi
    fvv_forks "$1"
}
