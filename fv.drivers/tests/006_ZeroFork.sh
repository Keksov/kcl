#!/usr/bin/env bash
# 006_ZeroFork.sh - no fork on the event path (PLAN.md rule 1):
#   * the whole API with PATH='' (no external command can run) over a fed fd:
#     keys, SGR / X10 mouse, wheel, a double click on the real clock,
#     put / clear, a resize over an overridden querySize, the knobs, end of
#     input, the rc 2 paths, initEvents / doneEvents to a file fd;
#   * fv.drivers.sh has no $( ), backtick, process substitution, pipe, ( )
#     subshell, & or coproc in any code line (the forks PATH='' cannot see).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"
source "$FVD_TESTS_DIR/../../fv.video/tests/fvv_testlib.sh"

kt_test_section "006: fork-free"

kt_test_start "the whole API with PATH=''"
printf '%s' $'a\e[A\e[<0;3;4M\e[<0;3;4m\e[<0;3;4M\e[M##$\e[<65;1;1M\e[<66;1;1Mz' > "$FVD_TMP/in.bin"
fv.video.querySize() { RESULT='30 100'; }
exec {f1}< "$FVD_TMP/in.bin" {f2}</dev/null {f3}> "$FVD_TMP/tty.out"
saved=$PATH
PATH=''
r=''
__FV_DR_NOW=''
FV_KEY_FD=$f1
fv.keyboard.flush
fv.drivers.getEvent; r+="$FV_EV_KEY "
fv.drivers.getEvent 0; r+="$FV_EV_KEY "
fv.drivers.getEvent; r+="$FV_EV_WHAT:$FV_EV_MOUSE_BUTTONS "
fv.drivers.getEvent; r+="$FV_EV_WHAT "
fv.drivers.getEvent; r+="$FV_EV_WHAT:$FV_EV_MOUSE_DOUBLE "
fv.drivers.getEvent; r+="$FV_EV_WHAT "
fv.drivers.getEvent; r+="$FV_EV_WHAT:$FV_EV_WHEEL "
fv.drivers.getEvent; r+="$FV_EV_WHAT "
FV_EV_WHAT=evCommand FV_EV_COMMAND=cmQuit
fv.drivers.putEvent; fv.drivers.clearEvent; fv.drivers.getEvent; r+="$FV_EV_COMMAND "
FV_VIDEO_RESIZED=1; fv.drivers.getEvent; r+="$FV_EV_COMMAND:$FV_EV_ID:$FV_EV_INFO "
FV_IDLE_TIMEOUT=0.01 FV_DOUBLE_DELAY=0.3 fv.drivers.getEvent; r+="$FV_EV_CHAR "
FV_IDLE_TIMEOUT=x FV_DOUBLE_DELAY=y fv.drivers.getEvent; r+="$?:$FV_EV_EOF "
FV_KEY_FD=$f2
fv.drivers.getEvent 0.01; r+="$?:$FV_EV_EOF "
fv.drivers.getEvent bad; r+="$? "
FV_KEY_FD=x fv.drivers.getEvent; r+="$? "
FV_TTY_FD=$f3
fv.drivers.initEvents any; r+="$? "
fv.drivers.doneEvents; r+="$? "
fv.drivers.initEvents bad; r+="$? "
FV_TTY_FD=''
fv.drivers.initEvents; r+="$?"
PATH=$saved
exec {f1}<&- {f2}<&- {f3}>&-
want='kbChar kbUp evMouseDown:1 evMouseUp evMouseDown:1 evMouseUp evMouseWheel:2 evNothing cmQuit cmResizeApp:100:30 z 1:1 1:1 2 2 0 0 2 1'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got  $r"$'\n'"want $want"; fi

kt_test_start "fv.drivers.sh: no \$( ), backtick, <( ), >( ), pipe, ( ) subshell, & or coproc in any code line"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvv_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$FVD_TESTS_DIR/../fv.drivers.sh"
if [[ -z $bad ]]; then kt_test_pass "$n lines clean"; else kt_test_fail "$bad"; fi

kt_test_log "006_ZeroFork.sh completed"
