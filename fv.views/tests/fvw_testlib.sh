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
#                         shadeRect)
#   fvw_budget LABEL LIMIT CMD...
#                         one test: run CMD with the dispatch counter on;
#                         pass when it made at most LIMIT dispatches; the
#                         count is logged ("# calls LABEL N")
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
FVW_WRITERS=(fv.video.writeStr fv.video.writeBuf fv.video.writeCStr fv.video.writeChar fv.video.fillRect fv.video.shadeRect)

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
