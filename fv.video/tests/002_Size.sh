#!/usr/bin/env bash
# 002_Size.sh - updateSize and querySize without a terminal (querySize
# stubbed, as an application may override it):
#   * "ROWS COLS" -> FV_SCREEN_H / FV_SCREEN_W (spaces, leading zeros);
#   * 0, empty, a failure, garbage, more than 5 digits -> COLUMNS / LINES per
#     dimension, else 80 x 24, with exactly one debug line;
#   * FV_VIDEO_RESIZED is cleared (also on the fallback path), RESULT = '';
#   * the default querySize without a terminal (FV_TTY_FD empty, or a
#     regular file) is rc 1 with RESULT = '' and prints nothing.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: the screen size"

eval "fvv_orig_query() $(declare -f fv.video.querySize | tail -n +2)"
STUB_OUT='' STUB_RC=0
fv.video.querySize() { RESULT=$STUB_OUT; return "$STUB_RC"; }

# size OUT RC COLUMNS LINES WANT_W WANT_H WANT_DEBUG_LINES
size() {
    local out=$1 rc=$2 c=$3 l=$4 w=$5 h=$6 nd=$7 got n
    kt_test_start "querySize '$out' rc $rc, COLUMNS='$c' LINES='$l' -> ${w}x$h${nd:+, $nd debug line(s)}"
    STUB_OUT=$out STUB_RC=$rc FV_VIDEO_RESIZED=1 RESULT=x
    if [[ $c == unset ]]; then unset COLUMNS; else COLUMNS=$c; fi
    if [[ $l == unset ]]; then unset LINES; else LINES=$l; fi
    VERBOSE_KKLASS=debug fv.video.updateSize > "$FVV_TMP/o" 2> "$FVV_TMP/e"; got=$?
    n=0
    if [[ -s $FVV_TMP/e ]]; then mapfile -t n < "$FVV_TMP/e"; n=${#n[@]}; fi
    if [[ $got == 0 && $FV_SCREEN_W == "$w" && $FV_SCREEN_H == "$h" && $FV_VIDEO_RESIZED == 0 && -z $RESULT \
          && ! -s $FVV_TMP/o && $n == "${nd:-0}" ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "rc=$got ${FV_SCREEN_W}x$FV_SCREEN_H resized=$FV_VIDEO_RESIZED RESULT=$RESULT debug=$n: $(<"$FVV_TMP/e")"
    fi
}

size '30 100'      0 unset unset 100 30 ''
size '  24   80  ' 0 unset unset 80 24 ''
size '030 0120'    0 unset unset 120 30 ''
size '99999 99999' 0 unset unset 99999 99999 ''
size '0 0'         0 132 43 132 43 1
size '0 0'         0 unset unset 80 24 1
size ''            0 90 unset 90 24 1
size '30 100'      1 70 20 70 20 1
size '30x100'      0 unset unset 80 24 1
size '30'          0 unset 50 80 50 1
size '0 100'       0 unset 33 100 33 1
size '40 0'        0 120 unset 120 40 1
size '123456 80'   0 unset unset 80 24 1
size '0 0'         0 abc -5 80 24 1
size '0 0'         0 0 '' 80 24 1
size '0 0'         0 123456 25 80 25 1

kt_test_start "no debug line without VERBOSE_KKLASS=debug"
STUB_OUT='0 0' STUB_RC=0
fv.video.updateSize > "$FVV_TMP/o" 2>&1
if [[ ! -s $FVV_TMP/o ]]; then kt_test_pass "ok"; else kt_test_fail "out=[$(<"$FVV_TMP/o")]"; fi

kt_test_start "the default querySize without a terminal: rc 1, RESULT='', silent (FV_TTY_FD empty / a regular file / not open)"
r=''
: > "$FVV_TMP/plain"
exec {pf}< "$FVV_TMP/plain"
for fd in '' "$pf" 987; do
    FV_TTY_FD=$fd RESULT=x
    fvv_orig_query > "$FVV_TMP/o" 2>&1; r+="$?:[$RESULT]:$(wc -c < "$FVV_TMP/o" | tr -d ' ') "
done
exec {pf}<&-
FV_TTY_FD=''
if [[ $r == '1:[]:0 1:[]:0 1:[]:0 ' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "updateSize through the default querySize without a terminal: COLUMNS/LINES"
fv.video.querySize() { fvv_orig_query "$@"; }
COLUMNS=101 LINES=31 fv.video.updateSize
if [[ ${FV_SCREEN_W}x$FV_SCREEN_H == 101x31 ]]; then kt_test_pass "ok"; else kt_test_fail "${FV_SCREEN_W}x$FV_SCREEN_H"; fi

kt_test_log "002_Size.sh completed"
