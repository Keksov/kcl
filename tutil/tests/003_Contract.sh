#!/bin/bash
# 003_Contract.sh — tutil P1: the kcl-wide contract (kcl/README.md §1) for the
# five sinks (PLAN.md §5 P1.2).
#
# What it pins:
#
#   source integrity  a sweeping mechanical edit must not silently mangle the
#                     file (`bash -n` + "no single-quoted string left open").
#   set -eu           every sink runs from a script under `set -eu`: with a
#                     succeeding tool, with a tool exiting 3 (the CHILD must
#                     survive and the member answer rc 1, not the tool's 3),
#                     with a callback whose own rc is 1 on every record (D2),
#                     with a `TPipe.stop` (where `wait` returns 141/143 while
#                     the member answers rc 0), with a REJECTING `.Add`, and
#                     with every malformed shape (rc 2, no abort).
#   §1.2 diagnostics  exactly ONE `kk.debug` line on every rc 2 path and on the
#                     rc 1 + `lastRc` 127 path, NOTHING on any rc 0 or plain
#                     rc 1 path, and nothing at all with the switch off.
#   D6 final          a sink under `$( )` is never refused; `toArray`/`toList`
#                     warn ONCE through `kk.warn` (printed with the debug switch
#                     OFF), `count`/`first` never do, and `subshellOk = 1`,
#                     `KK_SUBSHELL_OK=1` and `VERBOSE_KKLASS=quiet` each
#                     silence it.
#   zero forks        the callback runs at the script's own BASHPID under
#                     `set -eu`.
#
# Every child sets its own stdin explicitly (`</dev/null`): ktests gives a test
# child the terminal in `--mode single` and /dev/null in the threaded mode.
# Children get `timeout 20`: a cold source of the unit costs ~1 s idle and ~4 s
# with the runner at 8 workers. Producers on the stop path get `2>/dev/null`:
# a closed pipe routinely makes them print "write error: Broken pipe", which is
# the PRODUCER's stderr, not ours.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tutil.sh"
HASHSET="$UNIT_DIR/../thashset/thashset.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "003: the kcl contract for the TUtil sinks (P1)"

# ===========================================================================
kt_test_section "0. source integrity"
# ===========================================================================

kt_test_start "the unit source parses (bash -n)"
if err="$("$BASH" -n "$UNIT" 2>&1)"; then
    kt_test_pass "bash -n clean"
else
    kt_test_fail "bash -n: $err"
fi

kt_test_start "no single-quoted printf format is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then
    kt_test_fail "unterminated format string(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

kt_test_start "no member body carries an inline \$'\\r' (it does not survive \`build\`)"
if bad="$(grep -n "\$'\\\\r'" "$UNIT")"; then
    kt_test_fail "inline CR literal(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none — the CR belongs to tpipe's load-time \$__TPIPE_CR"
fi

# ===========================================================================
kt_test_section "1. set -eu — every sink, every outcome, in a child script"
# ===========================================================================

# expect_clean TITLE SNIPPET
# The snippet runs in a CHILD under `set -eu` with the unit freshly sourced, so
# an abort fails the case instead of this file. The child must end with rc 0,
# print exactly OK and write nothing to stderr.
ERRF="$TMP/setu.err"
expect_clean() {
    local title="$1" snippet="$2" out rc err
    kt_test_start "$title"
    : > "$ERRF"
    out="$(timeout 20 "$BASH" -c "set -eu
source '$UNIT'
$snippet
printf OK" 2>"$ERRF" </dev/null)"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "rc=$rc out='$out' stderr='$err'"
    fi
}

expect_clean "the unit loads under set -eu" ':'

expect_clean "the unit loads TWICE under set -eu (both re-source guards hold)" \
    "source '$UNIT'
source '$UNIT_DIR/../tpipe/tpipe.sh'"

expect_clean "each: a succeeding tool" '
N=0
cb() { N=$(( N + 1 )); }
TUtil.new u printf "%s\n" a b c
u.each cb
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
u.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }'

expect_clean "toArray: a succeeding tool" '
TUtil.new u printf "%s\n" a b c
declare -a A=()
u.toArray A
[[ "$RESULT" == "3" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 9; }
[[ "${A[2]}" == "c" ]] || { printf "A2=%s\n" "${A[2]}" >&2; exit 8; }'

expect_clean "toList: a succeeding tool" '
class TL
    public
        var         N
        constructor Create
        proc        Add
end
TL.Create() { N=0; return 0; }
TL.Add()    { N=$(( N + 1 )); return 0; }
build TL
TL.new L
TUtil.new u printf "%s\n" a b c
u.toList L
[[ "$RESULT" == "3" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
# a plain `var` read at a CALL SITE PRINTS and leaves RESULT empty (PLAN §6),
# so `$( )` is the only correct spelling outside a member body
[[ "$(L.N)" == "3" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }'

expect_clean "first: a succeeding tool" '
TUtil.new u printf "%s\n" a b c
u.first 2>/dev/null
[[ "$RESULT" == "a" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 9; }'

expect_clean "count: a succeeding tool" '
TUtil.new u printf "%s\n" a b c
u.count
[[ "$RESULT" == "3" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 9; }'

expect_clean "each: a tool exiting 3 — the CHILD survives and the member is rc 1" '
N=0
cb() { N=$(( N + 1 )); }
p() { printf "%s\n" a b; return 3; }
TUtil.new u p
rc=0
u.each cb || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
u.lastRc
[[ "$RESULT" == "3" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }'

expect_clean "toArray/toList/first/count: a tool exiting 3 — rc 1, the records KEPT" '
class TL2
    public
        var         N
        constructor Create
        proc        Add
end
TL2.Create() { N=0; return 0; }
TL2.Add()    { N=$(( N + 1 )); return 0; }
build TL2
TL2.new L
p() { printf "%s\n" a b; return 3; }
TUtil.new u p
declare -a A=()
rc=0; u.toArray A || rc=$?
[[ "$rc" == "1" && "$RESULT" == "2" && "${A[1]}" == "b" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; u.toList L || rc=$?
[[ "$rc" == "1" && "$RESULT" == "2" ]] || { printf "toList rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 8; }
rc=0; u.count || rc=$?
[[ "$rc" == "1" && "$RESULT" == "2" ]] || { printf "count rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 7; }
rc=0; u.first 2>/dev/null || rc=$?
[[ "$rc" == "0" && "$RESULT" == "a" ]] || { printf "first rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 6; }'

expect_clean "each: a callback answering rc 1 on EVERY record (D2) does not abort" '
N=0
cb() { N=$(( N + 1 )); return 1; }
TUtil.new u printf "%s\n" a b c
u.each cb
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "each + TPipe.stop on an INFINITE producer: rc 0 and no hang" '
N=0
cb() { N=$(( N + 1 )); TPipe.stop; }
TUtil.new u yes
u.each cb 2>/dev/null
[[ "$N" == "1" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
u.lastRc
case "$RESULT" in
    141|143) : ;;
    *) printf "lastRc=%s\n" "$RESULT" >&2; exit 8 ;;
esac'

expect_clean "first on an INFINITE producer: rc 0 and no hang" '
TUtil.new u yes
u.first 2>/dev/null
[[ "$RESULT" == "y" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 9; }'

expect_clean "toList into a REJECTING .Add (THashSet duplicates) does not abort" "
source '$HASHSET'
THashSet.new H
TUtil.new u printf '%s\\n' a b a b c
u.toList H
[[ \"\$RESULT\" == \"5\" ]] || { printf 'offered=%s\\n' \"\$RESULT\" >&2; exit 9; }
H.Count
[[ \"\$RESULT\" == \"3\" ]] || { printf 'stored=%s\\n' \"\$RESULT\" >&2; exit 8; }"

expect_clean "cmd='' — every sink is rc 2 with RESULT '' and nothing aborts" '
cb() { return 0; }
TUtil.new u
declare -a A=()
rc=0; u.each cb || rc=$?
[[ "$rc" == "2" ]] || { printf "each rc=%s\n" "$rc" >&2; exit 9; }
for m in toArray toList first count; do
    RESULT="sentinel"
    rc=0
    "u.$m" A || rc=$?
    [[ "$rc" == "2" ]] || { printf "%s rc=%s\n" "$m" "$rc" >&2; exit 8; }
    [[ -z "$RESULT" ]] || { printf "%s RESULT=%s\n" "$m" "$RESULT" >&2; exit 7; }
done
u.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }'

expect_clean "a missing command — every sink is rc 1 with lastRc 127 and nothing aborts" '
cb() { return 0; }
TUtil.new u tutil_no_such_tool_xyz
declare -a A=()
rc=0; u.each cb || rc=$?
[[ "$rc" == "1" ]] || { printf "each rc=%s\n" "$rc" >&2; exit 9; }
for m in toArray toList first count; do
    RESULT="sentinel"
    rc=0
    "u.$m" A || rc=$?
    [[ "$rc" == "1" ]] || { printf "%s rc=%s\n" "$m" "$rc" >&2; exit 8; }
    [[ -z "$RESULT" ]] || { printf "%s RESULT=%s\n" "$m" "$RESULT" >&2; exit 7; }
done
u.lastRc
[[ "$RESULT" == "127" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }'

expect_clean "a malformed CB / out-name / list is rc 2 and leaves lastRc alone" '
TUtil.new u printf "%s\n" a b
rc=0; u.each tutil_not_a_function || rc=$?
[[ "$rc" == "2" ]] || { printf "each rc=%s\n" "$rc" >&2; exit 9; }
RESULT="sentinel"
rc=0; u.toArray state || rc=$?
[[ "$rc" == "2" && -z "$RESULT" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 8; }
RESULT="sentinel"
rc=0; u.toList tutil_no_such_instance || rc=$?
[[ "$rc" == "2" && -z "$RESULT" ]] || { printf "toList rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 7; }
u.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }'

expect_clean "the sinks under \`\$( )\` answer with their value and do not abort" '
TUtil.new u printf "%s\n" a b
n="$(u.count)"
[[ "$n" == "2" ]] || { printf "count=%s\n" "$n" >&2; exit 9; }
f="$(u.first 2>/dev/null)"
[[ "$f" == "a" ]] || { printf "first=%s\n" "$f" >&2; exit 8; }'

# ===========================================================================
kt_test_section "2. zero forks: the callback runs in the script's own process"
# ===========================================================================

kt_test_start "every callback call happens at the child's own BASHPID (under set -eu)"
: > "$ERRF"
out="$(timeout 20 "$BASH" -c "set -eu
source '$UNIT'
MINE=\$BASHPID
BAD=0
N=0
cb() { N=\$(( N + 1 )); if [[ \"\$BASHPID\" != \"\$MINE\" ]]; then BAD=\$(( BAD + 1 )); fi; }
TUtil.new u printf '%s\\n' a b c d e
u.each cb
printf 'n=%s bad=%s\\n' \"\$N\" \"\$BAD\"" 2>"$ERRF" </dev/null)"; rc=$?
err="$(<"$ERRF")"
if [[ $rc -eq 0 && "$out" == "n=5 bad=0" && -z "$err" ]]; then
    kt_test_pass "5 callback calls, 0 of them in another process"
else
    kt_test_fail "rc=$rc out='$out' stderr='$err'"
fi

# ===========================================================================
kt_test_section "3. the debug switch — one line per rc 2 / 127 path, none else"
# ===========================================================================

DBGF="$TMP/dbg.err"

# dbg_lines COMMAND... -> DBG_N / DBG_1 / DBG_RC, with VERBOSE_KKLASS=debug.
dbg_lines() {
    : > "$DBGF"
    VERBOSE_KKLASS=debug
    "$@" 2>"$DBGF" >/dev/null
    DBG_RC=$?
    VERBOSE_KKLASS=
    DBG_LINES=()
    local ln
    while IFS= read -r ln || [[ -n "$ln" ]]; do
        DBG_LINES+=( "$ln" )
    done < "$DBGF"
    DBG_N=${#DBG_LINES[@]}
    DBG_1="${DBG_LINES[0]:-}"
    return 0
}

# quiet_rc COMMAND... -> QRC / QERR with the switch OFF.
quiet_rc() {
    : > "$DBGF"
    "$@" 2>"$DBGF" >/dev/null
    QRC=$?
    QERR="$(<"$DBGF")"
    return 0
}

dbg_cb() { return 0; }
dbg_p()  { printf '%s\n' a b; }
dbg_p3() { printf '%s\n' a b; return 3; }
# the same producer with its OWN stderr discarded, for the `first` cases: they
# always take the close-kill-wait path and a producer may report a broken pipe
dbg_pq() { { printf '%s\n' a b; } 2>/dev/null; }

class TDbgList
    public
        constructor Create
        proc        Add
end
TDbgList.Create() { return 0; }
TDbgList.Add()    { return 0; }
build TDbgList
TDbgList.new DL

TUtil.new dEmpty                          # cmd = '' -> every runner is rc 2
TUtil.new dMiss tutil_no_such_tool_xyz    # -> rc 1 with lastRc 127
TUtil.new dOk dbg_p                       # -> rc 0
TUtil.new dBad dbg_p3                     # -> plain rc 1
TUtil.new dQ   dbg_pq                     # -> rc 0, producer stderr discarded
declare -a DBG_ARR=()

# check_one TITLE WANT_RC COMMAND... — exactly one debug line, the expected rc,
# and complete silence with the switch off.
check_one() {
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    dbg_lines "$@"
    local n="$DBG_N" first="$DBG_1" drc="$DBG_RC"
    quiet_rc "$@"
    if [[ "$drc" == "$want" && $n -eq 1 && "$QRC" == "$want" && -z "$QERR" ]]; then
        kt_test_pass "rc $want, one line: ${first:0:78}"
    else
        kt_test_fail "debug rc=$drc lines=$n first='$first' / quiet rc=$QRC err='$QERR'"
    fi
}

# check_silent TITLE WANT_RC COMMAND... — no stderr at all, switch on or off.
check_silent() {
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    dbg_lines "$@"
    local n="$DBG_N" first="$DBG_1" drc="$DBG_RC"
    if [[ "$drc" == "$want" && $n -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic"
    else
        kt_test_fail "rc=$drc lines=$n first='$first'"
    fi
}

check_one "each: cmd='' is rc 2 and one line"        2 dEmpty.each dbg_cb
check_one "toArray: cmd='' is rc 2 and one line"     2 dEmpty.toArray DBG_ARR
check_one "toList: cmd='' is rc 2 and one line"      2 dEmpty.toList DL
check_one "first: cmd='' is rc 2 and one line"       2 dEmpty.first
check_one "count: cmd='' is rc 2 and one line"       2 dEmpty.count

check_one "each: a CB that is not a function is rc 2 and one line"   2 dOk.each tutil_not_a_function
check_one "toArray: a reserved out-name is rc 2 and one line"        2 dOk.toArray RESULT
check_one "toArray: the instance's own _argv is rc 2 and one line"   2 dOk.toArray dOk_argv
check_one "toArray: this family's \`__tu_\` prefix is rc 2 and one line" 2 dOk.toArray __tu_v
check_one "toList: an INST with no .Add is rc 2 and one line"        2 dOk.toList tutil_no_add_003

check_one "each: a missing command is rc 1 (lastRc 127) and one line"    1 dMiss.each dbg_cb
check_one "toArray: a missing command is rc 1 and one line"              1 dMiss.toArray DBG_ARR
check_one "toList: a missing command is rc 1 and one line"               1 dMiss.toList DL
check_one "first: a missing command is rc 1 and one line"                1 dMiss.first
check_one "count: a missing command is rc 1 and one line"                1 dMiss.count

check_silent "each: a successful run says NOTHING under the switch"      0 dOk.each dbg_cb
check_silent "toArray: a successful run says NOTHING"                    0 dOk.toArray DBG_ARR
check_silent "toList: a successful run says NOTHING"                     0 dOk.toList DL
check_silent "count: a successful run says NOTHING"                      0 dOk.count

check_silent "first: a successful run says NOTHING"                      0 dQ.first

check_silent "each: a plain rc 1 (tool exited 3) says NOTHING"           1 dBad.each dbg_cb
check_silent "toArray: a plain rc 1 says NOTHING"                        1 dBad.toArray DBG_ARR
check_silent "toList: a plain rc 1 says NOTHING"                         1 dBad.toList DL
check_silent "count: a plain rc 1 says NOTHING"                          1 dBad.count

kt_test_start "the \`127\` line names the MEMBER that was called, not just \`run\`"
dbg_lines dMiss.count
l1="$DBG_1"
dbg_lines dMiss.toArray DBG_ARR
l2="$DBG_1"
if [[ "$l1" == *"TUtil.count"* && "$l1" == *"command not found"* \
   && "$l2" == *"TUtil.toArray"* ]]; then
    kt_test_pass "count: ${l1:0:60} / toArray names itself too"
else
    kt_test_fail "count line='$l1' toArray line='$l2'"
fi

# --- D6 final (owner ruling 2026-09-15, tutil PLAN P4.2) --------------------
# The subshell warning is NOT a debug line: it goes through `kk.warn`, so it is
# printed with the switch OFF and silenced only by `VERBOSE_KKLASS=quiet`, by
# `-s` (spelled `subshellOk = 1` on an instance) or by `KK_SUBSHELL_OK=1`. And
# it is printed only where the loss is CERTAIN: `count` and `first`, whose whole
# answer is RESULT, never warn — which is what the case below used to assert the
# opposite of.

# sub3 COMMAND... — run it inside `$( )`; SUB_OUT / SUB_RC / SUB_N / SUB_1.
sub3() {
    : > "$DBGF"
    SUB_OUT="$( "$@" 2>"$DBGF" )"
    SUB_RC=$?
    local ln
    SUB_L=()
    while IFS= read -r ln || [[ -n "$ln" ]]; do SUB_L+=( "$ln" ); done < "$DBGF"
    SUB_N=${#SUB_L[@]}
    SUB_1="${SUB_L[0]:-}"
    return 0
}

kt_test_start "D6: \`\$(u.count)\` and \`\$(u.first)\` NEVER warn, switch on or off"
sub3 dOk.count
c_n=$SUB_N; c_out="$SUB_OUT"
VERBOSE_KKLASS=debug
sub3 dOk.count
c_dn=$SUB_N
VERBOSE_KKLASS=
sub3 dQ.first
f_n=$SUB_N; f_out="$SUB_OUT"
if [[ $c_n -eq 0 && $c_dn -eq 0 && $f_n -eq 0 && "$c_out" == "2" && "$f_out" == "a" ]]; then
    kt_test_pass "silent both ways, values still 2 and 'a'"
else
    kt_test_fail "count lines=$c_n/$c_dn out='$c_out' / first lines=$f_n out='$f_out'"
fi

kt_test_start "D6: \`\$(u.toArray NAME)\` warns ONCE with the DEBUG SWITCH OFF"
declare -a D6_ARR=()
sub3 dOk.toArray D6_ARR
exp="Warning: TPipe.toArray: the array D6_ARR is filled inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; move the call out of \$( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
if [[ "$SUB_OUT" == "2" && $SUB_RC -eq 0 && $SUB_N -eq 1 && "$SUB_1" == "$exp" ]]; then
    kt_test_pass "one line, verbatim, value still '2'"
else
    kt_test_fail "out='$SUB_OUT' rc=$SUB_RC lines=$SUB_N first='$SUB_1'"
fi

kt_test_start "D6: and the SAME single line under \`VERBOSE_KKLASS=debug\` — no second copy"
VERBOSE_KKLASS=debug
sub3 dOk.toArray D6_ARR
VERBOSE_KKLASS=
if [[ $SUB_N -eq 1 && "$SUB_1" == "$exp" ]]; then
    kt_test_pass "a warning is not a debug line"
else
    kt_test_fail "lines=$SUB_N first='$SUB_1'"
fi

kt_test_start "D6: \`subshellOk = 1\`, \`KK_SUBSHELL_OK=1\` and \`quiet\` each silence it"
dOk.subshellOk = 1
sub3 dOk.toArray D6_ARR
s_n=$SUB_N; s_out="$SUB_OUT"
dOk.subshellOk = 0
: > "$DBGF"
k_out="$(KK_SUBSHELL_OK=1 dOk.toArray D6_ARR 2>"$DBGF")"
k_err="$(<"$DBGF")"
VERBOSE_KKLASS=quiet
sub3 dOk.toArray D6_ARR
VERBOSE_KKLASS=
q_n=$SUB_N; q_out="$SUB_OUT"
if [[ $s_n -eq 0 && "$s_out" == "2" && -z "$k_err" && "$k_out" == "2" \
   && $q_n -eq 0 && "$q_out" == "2" ]]; then
    kt_test_pass "three switches, three silences, RESULT unchanged each time"
else
    kt_test_fail "subshellOk lines=$s_n out='$s_out' / KK_SUBSHELL_OK err='$k_err' out='$k_out' / quiet lines=$q_n out='$q_out'"
fi

kt_test_start "D6: a DIRECT sink call (BASH_SUBSHELL 0) warns about nothing"
: > "$DBGF"
dOk.toArray D6_ARR 2>"$DBGF" >/dev/null
d_err="$(<"$DBGF")"
if [[ -z "$d_err" ]]; then
    kt_test_pass "the position the unit exists for is silent"
else
    kt_test_fail "stderr='$d_err'"
fi

dEmpty.delete
dMiss.delete
dOk.delete
dBad.delete
dQ.delete
DL.delete
