#!/usr/bin/env bash
# 005_ZeroFork.sh - fv.msgbox never forks (PLAN.md rule 1):
#   * with PATH='' (no external command can run): the child scene of
#     fvx_testlib (messageBox with PARAMS, keys, a hot letter and a click;
#     messageBoxRect in the application; inputBox typing Cyrillic and CJK
#     into a LIMIT-8 line; -p; inputBoxRect with a box nested inside it;
#     refusals) gives the reference answers, no "command not found";
#   * the static scan (fv.video's 006 scanner, through fv.views' test lib):
#     no $( ), backtick, process substitution, pipe, ( ) subshell, & or
#     coproc on any code line of fv.msgbox.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: no forks"
fvx_scenefile
source "$FVX_TESTS_DIR/fvx_want.sh"

kt_test_start "PATH='': the whole path, no external command; the reference answers"
out=$(SETUP="PATH=''" "$BASH" "$FVW_TMP/scene.sh" 2>&1)
if [[ $out == "$FVX_WANT" ]]; then kt_test_pass ok; else kt_test_fail "got [$out] want [$FVX_WANT]"; fi

kt_test_start "the static scan: no forking construct on any code line of fv.msgbox.sh"
bad='' n=0 fn=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$FVX_TESTS_DIR/../fv.msgbox.sh"
if [[ -z $bad ]] && (( n > 200 )); then kt_test_pass "$n lines clean"; else kt_test_fail "${bad:-only $n lines}"; fi

kt_test_log "005_ZeroFork.sh completed"
