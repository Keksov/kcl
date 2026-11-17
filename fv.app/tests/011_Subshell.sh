#!/usr/bin/env bash
# 011_Subshell.sh - the owner-process rule (design §2.2, finding 14): the
# application belongs to the process that made it (BASHPID at Init):
#   * Run inside $( ) and in a pipeline element is refused (rc 2, a debug
#     line), nothing read or drawn there;
#   * execView inside $( ) refused (fv.views' rule, its owner set by Init);
#   * the parent's application is untouched and Run works there afterwards;
#   * an application made inside a subshell owns its own loop there (Face C).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: the owner process"

kt_test_start "Run in \$( ) and in a pipeline: rc 2, a debug line, nothing read, nothing drawn"
fva_app
fva_events 'key kbF2' 'cmd cmQuit'
fvw_outsize; s0=$REPLY
x=$(VERBOSE_KKLASS=debug app.Run 2>&1; echo "rc=$?|$FVA_N")
: | { app.Run; echo "rc=$?" > "$FVW_TMP/pipe"; }
fvw_outsize
r="${x##*$'\n'}|$(<"$FVW_TMP/pipe")|$(( REPLY - s0 ))|$FVA_N|${#FVA_Q[@]}"
if [[ $r == 'rc=2|0|rc=2|0|0|2' && $x == *'refused in a subshell'* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] [$x]"; fi

kt_test_start "execView in \$( ): refused (rc 2: fv.views' owner is the application's process)"
TWindow.new dlg 20 5 40 10 'D' 0
x=$(fv.views.execView "$FV_DESKTOP" dlg; echo "rc=$?")
dlg.delete
if [[ $x == 'rc=2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$x]"; fi

kt_test_start "the parent's application is untouched: Run works there afterwards (first paint, cmQuit)"
app.Run; rc=$?
r="$rc|$FVA_N|${#FVA_Q[@]}|$__FV_VW_EOF"
if [[ $r == '0|2|0|0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_start "an application made inside a subshell owns its loop there (Face C); the parent has no application"
x=$(
    exec {o}>/dev/null; FV_VIDEO_OUT_FD=$o FV_APP_HEADLESS=1
    TApplication.new sub
    fva_events 'cmd cmQuit'
    sub.Run; rc=$?
    echo "rc=$rc|$__FV_AP_OWNER|$BASHPID|$FVA_N"
    sub.delete
)
IFS='|' read -r a b c d <<< "$x"
if [[ $a == rc=0 && $b == "$c" && $b != "$BASHPID" && $d == 1 && -z $FV_APP ]]; then kt_test_pass "ok"; else kt_test_fail "[$x] parent app [$FV_APP]"; fi

kt_test_log "011_Subshell.sh completed"
