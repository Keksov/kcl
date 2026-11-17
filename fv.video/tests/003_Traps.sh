#!/usr/bin/env bash
# 003_Traps.sh - the trap chain without a terminal (child shells call the
# unit's trap setup directly; 004/005 run the same paths through initVideo on
# a pty):
#   * the caller's EXIT/INT/TERM/HUP/WINCH traps are saved verbatim (quotes,
#     newlines) and put back exactly; a signal the caller ignores stays
#     ignored; no caller trap -> none afterwards;
#   * WINCH sets FV_VIDEO_RESIZED and runs the caller's WINCH handler;
#   * INT/TERM/HUP: the caller's handler, then the caller's EXIT handler
#     once, then death by the signal (130/143/129); a caller handler that
#     exits wins; plain exit: the caller's EXIT handler once, seeing $?.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

UNIT="$FVV_TESTS_DIR/../fv.video.sh"

kt_test_section "003: the trap chain"

# child SNIPPET — OUT = the output of a child bash that loaded the unit, RC its status
child() {
    OUT=$("$BASH" -c "source '$UNIT'
$1" 2>&1)
    RC=$?
}

kt_test_start "saved verbatim, ours installed (an ignored TERM stays ignored), put back exactly"
child "
trap 'echo \"it'\\''s\"; x=1' EXIT
trap \$'echo int\\necho two' INT
trap '' TERM
trap 'w=1' WINCH
before=\$(trap -p EXIT INT TERM HUP WINCH)
fv.video._trap
during=\$(trap -p EXIT INT TERM HUP WINCH)
[[ \${__FV_VI_PREV[EXIT]} == 'echo \"it'\\''s\"; x=1' ]] || echo bad-prev-exit
[[ \${__FV_VI_PREV[INT]} == \$'echo int\\necho two' ]] || echo bad-prev-int
[[ -z \${__FV_VI_PREV[HUP]+x} ]] || echo bad-prev-hup
fv.video._untrap
after=\$(trap -p EXIT INT TERM HUP WINCH)
[[ \$before == \"\$after\" ]] || echo \"not-restored:[\$after]\"
printf '%s\n' \"\$during\"
trap - EXIT"
want="trap -- 'fv.video._onexit' EXIT
trap -- 'fv.video._onsig INT 2' SIGINT
trap -- '' SIGTERM
trap -- 'fv.video._onsig HUP 1' SIGHUP
trap -- 'fv.video._onwinch' SIGWINCH"
if [[ $RC == 0 && $OUT == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

kt_test_start "no caller traps: none are left after the round trip"
child "fv.video._trap; fv.video._untrap; printf '[%s]' \"\$(trap -p EXIT INT TERM HUP WINCH)\""
if [[ $RC == 0 && $OUT == '[]' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

kt_test_start "WINCH sets FV_VIDEO_RESIZED, then the caller's WINCH handler runs with the \$? plain bash gives it"
child "trap 'echo winch-\$?' WINCH; false; kill -WINCH \$BASHPID; echo after-\$?"
base=$OUT
child "
trap 'echo winch-\$?' WINCH
fv.video._trap
FV_VIDEO_RESIZED=0
false; kill -WINCH \$BASHPID; echo after-\$?
echo \"resized=\$FV_VIDEO_RESIZED\"
fv.video._untrap"
if [[ $RC == 0 && $OUT == "$base"$'\nresized=1' && $base == winch-*$'\n'after-* ]]; then kt_test_pass "ok ($base)"; else kt_test_fail "rc=$RC out=[$OUT] plain=[$base]"; fi

for s in INT:130 TERM:143 HUP:129; do
    kt_test_start "SIG${s%:*}: the caller's handler, the caller's EXIT handler once, then death by the signal (status ${s#*:})"
    child "
trap 'echo exit' EXIT
trap 'echo handler' ${s%:*}
fv.video._trap
kill -${s%:*} \$BASHPID
echo still-alive"
    if [[ $RC == "${s#*:}" && $OUT == $'handler\nexit' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi
done

kt_test_start "SIGTERM without caller traps: status 143, nothing printed"
child "fv.video._trap; kill -TERM \$BASHPID; echo still-alive"
if [[ $RC == 143 && -z $OUT ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

kt_test_start "a caller INT handler that exits 7: its exit wins, the caller's EXIT handler still runs once"
child "
trap 'echo exit-\$?' EXIT
trap 'echo handler; exit 7' INT
fv.video._trap
kill -INT \$BASHPID
echo still-alive"
if [[ $RC == 7 && $OUT == $'handler\nexit-7' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

kt_test_start "plain exit 3: the caller's EXIT handler once, seeing \$? = 3; status 3"
child "
trap 'echo exit-\$?' EXIT
fv.video._trap
exit 3"
if [[ $RC == 3 && $OUT == 'exit-3' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

kt_test_start "an ignored INT (trap '' INT) stays ignored: kill -INT does nothing"
child "
trap '' INT
fv.video._trap
kill -INT \$BASHPID
echo alive
fv.video._untrap"
if [[ $RC == 0 && $OUT == alive ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

# --- set -e / set -E: a handler ending in a false `a && b` is no error in a
# plain trap, and must not become one in ours (critic B1) ---------------------
kt_test_start "set -e, WINCH handler '[[ -n \$x ]] && redraw': the shell goes on (status 0)"
child "
set -e
x=
trap '[[ -n \$x ]] && echo redraw' WINCH
fv.video._trap
kill -WINCH \$BASHPID
echo alive
fv.video._untrap"
if [[ $RC == 0 && $OUT == alive ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

for s in INT:130 TERM:143 HUP:129; do
    kt_test_start "set -e, SIG${s%:*} handler '[[ -n \$x ]] && cleanup': still death by the signal (${s#*:}), the EXIT handler once"
    child "
set -e
x=
trap 'echo exit-\$?' EXIT
trap '[[ -n \$x ]] && echo cleanup' ${s%:*}
fv.video._trap
kill -${s%:*} \$BASHPID
echo alive"
    if [[ $RC == "${s#*:}" && $OUT == "exit-${s#*:}" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi
done

kt_test_start "set -e, EXIT handler '[[ -n \$x ]] && bye': exit 0 stays status 0"
child "
set -e
x=
trap '[[ -n \$x ]] && echo bye' EXIT
fv.video._trap
exit 0"
if [[ $RC == 0 && -z $OUT ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[$OUT]"; fi

# plain bash is the reference: the same snippet with and without the chain,
# compared on stdout and status (bash 5.2 adds "pop_var_context" noise on
# stderr when errexit unwinds out of a trap-called function: stderr dropped)
same_as_plain() {
    local snip=$1 base brc
    OUT=$("$BASH" -c "source '$UNIT'
${snip//@T@/}" 2>/dev/null); RC=$?
    base=$OUT brc=$RC
    OUT=$("$BASH" -c "source '$UNIT'
${snip//@T@/fv.video._trap}" 2>/dev/null); RC=$?
    if [[ $RC == "$brc" && $OUT == "$base" ]]; then kt_test_pass "as plain bash: rc=$RC [${OUT//$'\n'/|}]"
    else kt_test_fail "chained rc=$RC [${OUT//$'\n'/|}] plain rc=$brc [${base//$'\n'/|}]"; fi
}

kt_test_start "set -eE + an ERR trap: the false && in a WINCH handler fires no ERR (as plain bash)"
same_as_plain "
set -eE
trap 'echo ERR' ERR
x=
trap '[[ -n \$x ]] && echo redraw' WINCH
@T@
kill -WINCH \$BASHPID
echo alive"

kt_test_start "set -e: a real error inside the WINCH handler still ends the shell (as plain bash)"
same_as_plain "
set -e
trap 'false; echo not-reached' WINCH
@T@
kill -WINCH \$BASHPID
echo alive"

kt_test_start "set -e: a handler's own exit 4 still wins (as plain bash)"
same_as_plain "
set -e
trap 'echo w; exit 4' WINCH
@T@
kill -WINCH \$BASHPID
echo alive"

# --- subshells: only the traps active in this process are chained (critic B2)
kt_test_start "inside x=\$( ): the parent's EXIT/INT texts are not chained; the parent's EXIT handler runs once, in the parent"
child "
trap 'echo PARENT-EXIT-\$BASHPID' EXIT
trap 'echo PARENT-INT' INT
p=\$BASHPID
x=\$(fv.video._trap; printf '%s|%s|' \"\${__FV_VI_PREV[EXIT]-none}\" \"\${__FV_VI_PREV[INT]-none}\"; fv.video._untrap; printf v)
echo \"x=\$x\"
echo \"traps=\$(( \$(trap -p EXIT INT | wc -l) ))\"
[[ \$p == \$BASHPID ]] && echo parent=\$p"
want_pid=${OUT#*parent=}; want_pid=${want_pid%%$'\n'*}
if [[ $RC == 0 && $OUT == $'x=none|none|v\ntraps=2\nparent='"$want_pid"$'\nPARENT-EXIT-'"$want_pid" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[${OUT//$'\n'/|}]"; fi

kt_test_start "inside ( ) and a pipeline: the same; a subshell's own EXIT trap is chained, an ignored TERM stays ignored"
child "
trap 'echo PARENT-EXIT' EXIT
trap '' TERM
( fv.video._trap; printf '[%s]' \"\${__FV_VI_PREV[EXIT]-none}\"; fv.video._untrap )
echo | { fv.video._trap; printf '[%s]' \"\${__FV_VI_PREV[EXIT]-none}\"; fv.video._untrap; }
( trap 'echo own' EXIT; fv.video._trap; printf '[%s]' \"\${__FV_VI_PREV[EXIT]-none}\"; kill -TERM \$BASHPID; printf '[alive]'; fv.video._untrap; trap - EXIT )
echo"
if [[ $RC == 0 && $OUT == $'[none][none][echo own][alive]\nPARENT-EXIT' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out=[${OUT//$'\n'/|}]"; fi

kt_test_log "003_Traps.sh completed"
