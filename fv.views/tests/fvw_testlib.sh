#!/usr/bin/env bash
# fvw_testlib.sh — what the fv.views test files share. Not a test file: the
# ktests runner picks up NNN_*.sh only. Headless: no terminal is touched,
# frames go to a file (never initVideo).
#
#   fvw_init NAME "$@"    ktest init + the unit + a scratch folder ($FVW_TMP)
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
