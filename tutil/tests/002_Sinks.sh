#!/bin/bash
# 002_Sinks.sh — tutil P1: the five sinks through TPipe (PLAN.md §2.3, §2.4,
# §5 P1; pinned facts U1, U6, U7-for-sinks, U8).
#
# The oracle is `TPipe` itself, called DIRECTLY with the very argv the wrapper
# built (`u.argv WORDS` hands it over without running anything), so every case
# compares "the sugar" with "the thing the sugar stands for" — never a second
# call to the code under test.
#
# Sections:
#   A  U1   `each` delivers every record in THIS shell; a plain function and an
#           instance member both keep their state
#   B  U8   the four `func` sinks answer RESULT = count / record AND rc =
#           mapped, on a DIRECT call and under `$( )`; and (D6 final, tutil PLAN
#           P4.2) the TPipe subshell warning as it reaches a caller THROUGH a
#           wrapper — `toArray`/`toList`/`each r.onLine` warn once, `count`/
#           `first`/`each fn` never, and `subshellOk = 1`, `KK_SUBSHELL_OK=1`
#           and `VERBOSE_KKLASS=quiet` each silence it
#   C       each sink == `TPipe.<sink>` with the same argv, byte-exact on a
#           producer emitting `-n`, a space, a backslash, a bare CR, UTF-8 and
#           an unterminated tail
#   D       `nul = 1` -> TPipe `-0`; `crlf = 1` -> TPipe `-c` (and both are OFF
#           by default, so the CR survives)
#   E       three-frame nested dispatch (`g.each` -> `TPipe.each` -> `r.onLine`)
#           keeps the callee instance's state; a nested sink inside a callback
#           does not disturb the outer one
#   F       zero forks per record: every callback runs at the test's own BASHPID
#   G       `toList` with a REJECTING `.Add` (THashSet duplicates): RESULT counts
#           records OFFERED, the set keeps fewer
#   H       the named deviation — a producer exiting non-zero is rc 1 with the
#           COUNT kept, and `lastRc` is the raw status
#   I  U6   a callback that calls `TPipe.stop`: rc 0, `lastRc` 141/143, no hang
#           (run in a child under `timeout`)
#   J       malformed calls: `cmd=''`, a missing command, a bad out-name, a CB
#           that is not a function, an INST without `.Add` — rc, RESULT,
#           `_lastRc` and "nothing ran"
#   K       two instances interleaved keep separate `_lastRc`; `argv` still runs
#           nothing now that the sinks exist
#   L       the three forms agree: `u.run | TPipe.each cb` under `lastpipe` ==
#           `TPipe.each cb -- "${argv[@]}"` == `u.each cb`
#
# Producers on the stop path get `2>/dev/null`: a closed pipe routinely makes
# them print "write error: Broken pipe", which is the PRODUCER's stderr.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tutil.sh"
source "$UNIT"
# TPipe is the oracle. tutil.sh already sources it; the explicit line keeps this
# file honest if that ever changes, and the re-source guard makes it free.
source "$UNIT_DIR/../tpipe/tpipe.sh"
source "$UNIT_DIR/../thashset/thashset.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "002: the five sinks through TPipe (P1)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# arr_is ARRNAME expected... — rc 0 iff the array holds exactly these elements
# in this order. Fork-free and byte-exact, so exotic records compare correctly.
arr_is() {
    local -n __a="$1"; shift
    local __i=0 __e
    if (( ${#__a[@]} != $# )); then
        return 1
    fi
    for __e in "$@"; do
        if [[ "${__a[$__i]}" != "$__e" ]]; then
            return 1
        fi
        __i=$(( __i + 1 ))
    done
    return 0
}

# arr_eq A B — rc 0 iff the two named arrays are element-for-element identical.
arr_eq() {
    local -n __x="$1"
    local -n __y="$2"
    local __i
    if (( ${#__x[@]} != ${#__y[@]} )); then
        return 1
    fi
    for (( __i = 0; __i < ${#__x[@]}; __i++ )); do
        if [[ "${__x[$__i]}" != "${__y[$__i]}" ]]; then
            return 1
        fi
    done
    return 0
}

# arr_show ARRNAME -> a quoted, printable form for a failure message. `%q` so a
# CR, a backslash or a leading `-n` in a record is visible in the diagnostic.
arr_show() {
    local -n __a="$1"
    if (( ${#__a[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__a[@]}"
}

# nlines FILE -> NLINES (counts an unterminated last line too).
NLINES=0
nlines() {
    local __n=0 __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do __n=$(( __n + 1 )); done < "$1"
    NLINES=$__n
}

# run_child SNIPPET -> CHILD_OUT / CHILD_RC / CHILD_ERRTXT
# The snippet runs in a CHILD under `set -eu` with the unit freshly sourced.
# 20 s is the floor for a child here: a cold source costs ~1 s idle and ~4 s
# under the threaded runner.
CHILD_ERR="$TMP/child.err"
CHILD_OUT=""
CHILD_RC=0
CHILD_ERRTXT=""
run_child() {
    : > "$CHILD_ERR"
    CHILD_OUT="$(timeout 20 "$BASH" -c "set -eu
source '$UNIT'
$1" 2>"$CHILD_ERR" </dev/null)"
    CHILD_RC=$?
    CHILD_ERRTXT="$(<"$CHILD_ERR")"
}

FLAG="$TMP/ran.flag"
ERRF="$TMP/sink.err"

# producers ------------------------------------------------------------------
p2()      { printf '%s\n' a b; }
p4()      { printf '%s\n' a b c d; }
# p4 with its OWN stderr discarded: `first` always takes the close-kill-wait
# path, where a producer routinely reports a broken pipe, so a case that ASSERTS
# on stderr (the D6 warning cases in §B) must not see the producer's noise.
p4q()     { { printf '%s\n' a b c d; } 2>/dev/null; }
pfail3()  { printf '%s\n' a b; return 3; }
pnul()    { printf 'a b\0c\0'; }
pcr()     { printf 'x\r\ny\r\n'; }
pmark()   { : > "$FLAG"; printf 'marked\n'; }
ppid5()   { local __i; for __i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }
# hostile to `echo` and to line-oriented handling: a leading `-n`, a space, a
# backslash, a glob, a bare CR, UTF-8 and an unterminated tail.
pexotic() {
    printf '%s\n' '-n' '-neE' 'back\slash' '*' 'a b' 'café' '日本語'
    printf 'cr\r\n'
    printf 'tail-no-newline'
}
# The CR comes from a VARIABLE and the element is QUOTED. Measured on 5.2.37 and
# 5.3.9 while writing this file: an unquoted `$'cr\r'` inside a COMPOUND array
# assignment loses the CR (`A=( $'cr\r' )` -> `${#A[0]}` is 2, and `$'a\rb'`
# there becomes `ab`), while `x=$'cr\r'` and a plain command argument keep it.
# It is the same re-parse class tpipe README §7 records for `declare -f`/`build`:
# a raw CR does not survive the second pass. `A=( "cr$CR" )` is 3 characters.
printf -v CR '\r'
EXOTIC_WANT=( '-n' '-neE' 'back\slash' '*' 'a b' 'café' '日本語' "cr$CR" 'tail-no-newline' )

# collectors -----------------------------------------------------------------
CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

PID_RECS=()
cb_pid() { PID_RECS+=( "$BASHPID" ); return 0; }

# a callback that answers rc 1 on every record (D2: its status is data)
cb_false() { CB_RECS+=( "$1" ); return 1; }

REC_RECS=()
class TRec
    public
        var         N
        constructor Create
        proc        onLine
end
TRec.Create() { N=0; return 0; }
TRec.onLine() { N=$(( N + 1 )); REC_RECS+=( "$1" ); return 0; }
build TRec

# a collector with an .Add, for toList
LADD=()
class TCollector
    public
        var         N
        constructor Create
        proc        Add
end
TCollector.Create() { N=0; return 0; }
TCollector.Add()    { LADD+=( "$1" ); N=$(( N + 1 )); return 0; }
build TCollector

# a callback that PRINTS, to prove a sink never adds bytes of its own
cb_print() { printf 'rec:%s\n' "$1"; return 0; }

# a toList target whose .Add PRINTS — a `>/dev/null` on the delegated call would
# swallow it, the `__TPIPE_QUIET` seam does not
class TPrinter
    public
        constructor Create
        proc        Add
end
TPrinter.Create() { return 0; }
TPrinter.Add()    { printf 'add:%s\n' "$1"; return 0; }
build TPrinter

# a class with no .Add at all (the rc 2 operand path of toList)
class TNoAdd
    public
        constructor Create
        proc        Push
end
TNoAdd.Create() { return 0; }
TNoAdd.Push()   { return 0; }
build TNoAdd

# a callback that starts a NESTED sink on its own TUtil instance (§E)
NEST_OUTER=()
NEST_INNER=()
cb_nest() {
    NEST_OUTER+=( "$1" )
    declare -a __inner=()
    NU.toArray __inner
    NEST_INNER+=( "inner=$RESULT:${__inner[*]}" )
    return 0
}

# ===========================================================================
kt_test_section "A. U1 — \`each\` delivers records and the callback keeps state"
# ===========================================================================

kt_test_start "U1: \`TUtil.new u printf '%s\\n' a b; u.each cb\` delivers 2 records to a plain function"
TUtil.new uA printf '%s\n' a b
CB_RECS=()
uA.each cb_collect; rc=$?
if [[ $rc -eq 0 ]] && arr_is CB_RECS "a" "b"; then
    kt_test_pass "2 records, rc 0"
else
    kt_test_fail "rc=$rc CB_RECS=$(arr_show CB_RECS)"
fi

kt_test_start "U1: the same through an INSTANCE member — the object's mutations survive"
TRec.new RA
REC_RECS=()
uA.each RA.onLine; rc=$?
n="$(RA.N)"      # a plain `var` read at a CALL SITE PRINTS and leaves RESULT empty (PLAN §6)
if [[ $rc -eq 0 && "$n" == "2" ]] && arr_is REC_RECS "a" "b"; then
    kt_test_pass "r.N = 2 after the sink returned (no subshell ate it)"
else
    kt_test_fail "rc=$rc N='$n' REC_RECS=$(arr_show REC_RECS)"
fi

kt_test_start "\`each\` is a PROC: it answers with its rc alone and leaves the caller's RESULT"
RESULT="caller-sentinel"
uA.each cb_collect; rc=$?
if [[ $rc -eq 0 && "$RESULT" == "caller-sentinel" ]]; then
    kt_test_pass "RESULT untouched (kk._invoke restores it — use \`count\` for the number)"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "a callback whose own rc is 1 does not tear the stream down (D2)"
CB_RECS=()
uA.each cb_false; rc=$?
if [[ $rc -eq 0 ]] && arr_is CB_RECS "a" "b"; then
    kt_test_pass "both records delivered, member rc 0"
else
    kt_test_fail "rc=$rc CB_RECS=$(arr_show CB_RECS)"
fi

kt_test_start "\`each\` sets \`lastRc\` to the producer's RAW status"
uA.lastRc; lr="$RESULT"
if [[ "$lr" == "0" ]]; then
    kt_test_pass "lastRc 0"
else
    kt_test_fail "lastRc='$lr'"
fi
uA.delete
RA.delete

# ===========================================================================
kt_test_section "B. U8 — the four func sinks: RESULT and rc, direct and under \$( )"
# ===========================================================================

TUtil.new uB p4

kt_test_start "U8: \`toArray\` — RESULT = the count, rc 0, the caller's array replaced"
declare -a BA=( stale1 stale2 stale3 stale4 stale5 )
RESULT="sentinel"
uB.toArray BA; rc=$?
if [[ "$RESULT" == "4" && $rc -eq 0 ]] && arr_is BA a b c d; then
    kt_test_pass "RESULT=4, rc 0, BA=(a b c d)"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc BA=$(arr_show BA)"
fi

kt_test_start "U8: \`toList\` — RESULT = records offered, rc 0"
TCollector.new LB
LADD=()
RESULT="sentinel"
uB.toList LB; rc=$?
n="$(LB.N)"
if [[ $rc -eq 0 && "$n" == "4" ]] && arr_is LADD a b c d; then
    kt_test_pass "4 offered and 4 stored, rc 0"
else
    kt_test_fail "rc=$rc N='$n' LADD=$(arr_show LADD)"
fi
LB.delete

kt_test_start "U8: \`first\` — RESULT = the first record, rc 0"
RESULT="sentinel"
uB.first 2>/dev/null; rc=$?
if [[ "$RESULT" == "a" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT='a', rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "U8: \`count\` — RESULT = the number of records, rc 0"
RESULT="sentinel"
uB.count; rc=$?
if [[ "$RESULT" == "4" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT=4, rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "U8: under \`\$( )\` each func sink prints its value EXACTLY ONCE"
declare -a BS=()
o_arr="$(uB.toArray BS 2>/dev/null)"; ra=$?
o_cnt="$(uB.count)"; rn=$?
o_fst="$(uB.first 2>/dev/null)"; rf=$?
TCollector.new LS
o_lst="$(uB.toList LS 2>/dev/null)"; rl=$?
LS.delete
if [[ "$o_arr" == "4" && "$o_cnt" == "4" && "$o_fst" == "a" && "$o_lst" == "4" \
   && $ra -eq 0 && $rn -eq 0 && $rf -eq 0 && $rl -eq 0 ]]; then
    kt_test_pass "no doubled value: TPipe's own subshell echo is discarded"
else
    kt_test_fail "toArray='$o_arr'($ra) count='$o_cnt'($rn) first='$o_fst'($rf) toList='$o_lst'($rl)"
fi

# --- D6 final (tutil PLAN P4.2): the subshell warning through a wrapper -----
# A sink always delegates in TPipe's `--` form, so the template is the `$( )`
# one and MEMBER is the TPipe member the sink delegated to — `TPipe.toArray`,
# not `TUtil.toArray`. The line is rebuilt here from its parts, so the assertion
# pins the text rather than comparing the unit with itself.
w_cmd() {   # $1 = TPipe member, $2 = WHAT
    printf '%s' "Warning: TPipe.$1: $2 inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; move the call out of \$( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
}

SUBERR="$TMP/sub.err"

# sub_err COMMAND... — run it inside `$( )`; SUB_OUT = stdout, SUB_RC = rc,
# ERRL/ERRN = the stderr lines.
sub_err() {
    : > "$SUBERR"
    SUB_OUT="$( "$@" 2>"$SUBERR" )"
    SUB_RC=$?
    ERRL=()
    local ln
    while IFS= read -r ln || [[ -n "$ln" ]]; do ERRL+=( "$ln" ); done < "$SUBERR"
    ERRN=${#ERRL[@]}
    return 0
}

kt_test_start "D6: \`\$(u.toArray NAME)\` warns ONCE, with the TPipe line verbatim"
declare -a BW=()
sub_err uB.toArray BW
exp="$(w_cmd toArray "the array BW is filled")"
if [[ $SUB_RC -eq 0 && "$SUB_OUT" == "4" && $ERRN -eq 1 && "${ERRL[0]:-}" == "$exp" ]]; then
    kt_test_pass "one line, verbatim, value still 4"
else
    kt_test_fail "rc=$SUB_RC out='$SUB_OUT' lines=$ERRN got='${ERRL[0]:-}'"
fi

kt_test_start "D6: \`\$(u.toList INST)\` warns ONCE too, naming the instance's \`.Add\`"
TCollector.new LW
sub_err uB.toList LW
exp="$(w_cmd toList "LW.Add runs")"
if [[ $SUB_RC -eq 0 && "$SUB_OUT" == "4" && $ERRN -eq 1 && "${ERRL[0]:-}" == "$exp" ]]; then
    kt_test_pass "one line, verbatim"
else
    kt_test_fail "rc=$SUB_RC out='$SUB_OUT' lines=$ERRN got='${ERRL[0]:-}'"
fi
LW.delete

kt_test_start "D6: \`subshellOk = 1\` silences every sink of THIS instance (Q9)"
uB.subshellOk = 1
declare -a BQ=()
sub_err uB.toArray BQ
a_n=$ERRN; a_out="$SUB_OUT"
TCollector.new LQ
sub_err uB.toList LQ
l_n=$ERRN; l_out="$SUB_OUT"
LQ.delete
uB.subshellOk = 0
if [[ $a_n -eq 0 && $l_n -eq 0 && "$a_out" == "4" && "$l_out" == "4" ]]; then
    kt_test_pass "the property is the object-style spelling of TPipe's \`-s\`"
else
    kt_test_fail "toArray lines=$a_n out='$a_out' / toList lines=$l_n out='$l_out'"
fi

kt_test_start "D6: with \`subshellOk = 0\` again the very next call warns (it is not sticky)"
sub_err uB.toArray BQ
if [[ $ERRN -eq 1 ]]; then
    kt_test_pass "the switch is read per call, from the property"
else
    kt_test_fail "lines=$ERRN got='${ERRL[0]:-}'"
fi

kt_test_start "D6: \`KK_SUBSHELL_OK=1 u.toArray …\` reaches TPipe through the wrapper (Q3)"
# No TUtil code at all: the variable is dynamically scoped, so it is visible in
# TUtil's frame and in TPipe's below it.
: > "$SUBERR"
k_out="$(KK_SUBSHELL_OK=1 uB.toArray BQ 2>"$SUBERR")"; k_rc=$?
k_err="$(<"$SUBERR")"
if [[ "$k_out" == "4" && $k_rc -eq 0 && -z "$k_err" ]]; then
    kt_test_pass "silent through two frames of wrapper"
else
    kt_test_fail "out='$k_out' rc=$k_rc err='$k_err'"
fi

kt_test_start "D6: \`VERBOSE_KKLASS=quiet\` silences it as well"
VERBOSE_KKLASS=quiet
sub_err uB.toArray BQ
VERBOSE_KKLASS=
if [[ $ERRN -eq 0 && "$SUB_OUT" == "4" ]]; then
    kt_test_pass "nothing on stderr under quiet"
else
    kt_test_fail "lines=$ERRN out='$SUB_OUT' got='${ERRL[0]:-}'"
fi

kt_test_start "D6: \`\$(u.count)\` and \`\$(u.first)\` NEVER warn — RESULT is the answer"
sub_err uB.count
c_n=$ERRN; c_out="$SUB_OUT"
TUtil.new uQ p4q
sub_err uQ.first
f_n=$ERRN; f_out="$SUB_OUT"
uQ.delete
if [[ $c_n -eq 0 && "$c_out" == "4" && $f_n -eq 0 && "$f_out" == "a" ]]; then
    kt_test_pass "count and first are silent in a subshell by contract (Q2)"
else
    kt_test_fail "count lines=$c_n out='$c_out' / first lines=$f_n out='$f_out'"
fi

kt_test_start "D6: \`\$(u.each r.onLine)\` warns, \`\$(u.each fn)\` does not (the callback-kind rule)"
TRec.new RW
sub_err uB.each RW.onLine
i_n=$ERRN; i_1="${ERRL[0]:-}"
RW.delete
sub_err uB.each cb_collect
p_n=$ERRN
exp="$(w_cmd each "the instance member RW.onLine runs")"
if [[ $i_n -eq 1 && "$i_1" == "$exp" && $p_n -eq 0 ]]; then
    kt_test_pass "an instance-member callback warns; a plain function is silent"
else
    kt_test_fail "instance lines=$i_n got='$i_1' / plain lines=$p_n"
fi

kt_test_start "U8: on the LHS of a pipe the value is printed exactly once too"
o_cnt="$(uB.count | cat)"
o_fst="$(uB.first 2>/dev/null | cat)"
if [[ "$o_cnt" == "4" && "$o_fst" == "a" ]]; then
    kt_test_pass "count='4', first='a'"
else
    kt_test_fail "count='$o_cnt' first='$o_fst'"
fi

kt_test_start "\`each\` under \`\$( )\` carries ONLY what the callback printed"
# The sink declares `local __TPIPE_QUIET=1`, so TPipe's own subshell echo of the
# record count never reaches the stream; `each` has no return channel of its own,
# so what comes out is exactly the callback's bytes.
out="$(uB.each cb_print)"
if [[ "$out" == $'rec:a\nrec:b\nrec:c\nrec:d' ]]; then
    kt_test_pass "4 callback lines, no record count glued on"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "\`each\` on the LHS of a pipe carries ONLY what the callback printed"
out="$(uB.each cb_print | cat)"
if [[ "$out" == $'rec:a\nrec:b\nrec:c\nrec:d' ]]; then
    kt_test_pass "same through a real pipe"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "\`toList\` under \`\$( )\`: a PRINTING .Add still reaches stdout, and the count once"
TPrinter.new PR
out="$(uB.toList PR 2>/dev/null)"      # the D6 warning has its own cases above
PR.delete
if [[ "$out" == $'add:a\nadd:b\nadd:c\nadd:d\n4' ]]; then
    kt_test_pass "the target's own 4 lines are untouched, then the member's value once"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "U8: rc = the MAPPED rc, under \`\$( )\` as well as direct (producer exits 3)"
TUtil.new uB3 pfail3
o="$(uB3.count)"; rc=$?
uB3.count; drc=$?; dres="$RESULT"
if [[ "$o" == "2" && $rc -eq 1 && $drc -eq 1 && "$dres" == "2" ]]; then
    kt_test_pass "rc 1 both ways, RESULT keeps the count (§2.4)"
else
    kt_test_fail "subst='$o'($rc) direct rc=$drc RESULT='$dres'"
fi
uB3.delete
uB.delete

# ===========================================================================
kt_test_section "C. every sink == TPipe called directly with the same argv"
# ===========================================================================

TUtil.new uC pexotic
declare -a CARGV=()
uC.argv CARGV

kt_test_start "\`argv\` hands over exactly what the sinks will run"
if arr_is CARGV "pexotic"; then
    kt_test_pass "argv=(pexotic)"
else
    kt_test_fail "CARGV=$(arr_show CARGV)"
fi

kt_test_start "toArray == TPipe.toArray on the exotic producer (byte-exact, 9 records)"
declare -a MINE=() THEIRS=()
uC.toArray MINE; mrc=$?; mres="$RESULT"
TPipe.toArray THEIRS -- "${CARGV[@]}"; trc=$?; tres="$RESULT"
if [[ "$mres" == "$tres" && $mrc -eq $trc && "$mres" == "9" ]] \
   && arr_eq MINE THEIRS && arr_is MINE "${EXOTIC_WANT[@]}"; then
    kt_test_pass "9 records identical to TPipe's and to the literal matrix"
else
    kt_test_fail "mine='$mres'($mrc) theirs='$tres'($trc) MINE=$(arr_show MINE) THEIRS=$(arr_show THEIRS)"
fi

kt_test_start "count == TPipe.count on the same argv"
uC.count; mrc=$?; mres="$RESULT"
TPipe.count -- "${CARGV[@]}"; trc=$?; tres="$RESULT"
if [[ "$mres" == "$tres" && $mrc -eq $trc && "$mres" == "9" ]]; then
    kt_test_pass "both 9, rc $mrc"
else
    kt_test_fail "mine='$mres'($mrc) theirs='$tres'($trc)"
fi

kt_test_start "first == TPipe.first on the same argv (a record starting with '-n')"
uC.first 2>/dev/null; mrc=$?; mres="$RESULT"
TPipe.first -- "${CARGV[@]}" 2>/dev/null; trc=$?; tres="$RESULT"
if [[ "$mres" == "$tres" && $mrc -eq $trc && "$mres" == "-n" ]]; then
    kt_test_pass "both '-n', rc $mrc (printf, not echo, on the return path)"
else
    kt_test_fail "mine='$mres'($mrc) theirs='$tres'($trc)"
fi

kt_test_start "each == TPipe.each on the same argv (same records, same order)"
CB_RECS=()
uC.each cb_collect; mrc=$?
# A PLAIN compound assignment, never `declare -a X=( "${Y[@]}" )`: `declare`
# re-parses its argument and a raw CR does not survive that second pass (3 -> 2
# characters, measured on both bashes) — the same class as the `EXOTIC_WANT`
# note above.
MINE_E=( "${CB_RECS[@]}" )
CB_RECS=()
TPipe.each cb_collect -- "${CARGV[@]}"; trc=$?
if [[ $mrc -eq $trc ]] && arr_eq MINE_E CB_RECS && arr_is MINE_E "${EXOTIC_WANT[@]}"; then
    kt_test_pass "9 records identical through both spellings"
else
    kt_test_fail "mine=$(arr_show MINE_E) theirs=$(arr_show CB_RECS) rc $mrc/$trc"
fi

kt_test_start "toList == TPipe.toList on the same argv"
TCollector.new LC
LADD=()
uC.toList LC; mrc=$?; mres="$RESULT"
MINE_L=( "${LADD[@]}" )
LADD=()
TPipe.toList LC -- "${CARGV[@]}"; trc=$?; tres="$RESULT"
if [[ "$mres" == "$tres" && $mrc -eq $trc ]] && arr_eq MINE_L LADD; then
    kt_test_pass "same records offered ($mres) and same rc"
else
    kt_test_fail "mine='$mres'($mrc)=$(arr_show MINE_L) theirs='$tres'($trc)=$(arr_show LADD)"
fi
LC.delete
uC.delete

# ===========================================================================
kt_test_section "D. \`nul\` -> -0 and \`crlf\` -> -c"
# ===========================================================================

kt_test_start "nul = 1 frames NUL-terminated records (a record with a space stays one record)"
TUtil.new uN pnul
uN.nul = 1
declare -a NA=()
uN.toArray NA; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 ]] && arr_is NA "a b" "c"; then
    kt_test_pass "2 records: 'a b' and 'c'"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc NA=$(arr_show NA)"
fi

kt_test_start "nul = 1 equals TPipe called with -0 on the same argv"
declare -a NT=()
declare -a NARGV=()
uN.argv NARGV
TPipe.toArray -0 NT -- "${NARGV[@]}"
if arr_eq NA NT; then
    kt_test_pass "identical to \`TPipe.toArray -0\`"
else
    kt_test_fail "mine=$(arr_show NA) theirs=$(arr_show NT)"
fi

kt_test_start "nul = 0 (the default) reads the SAME bytes as ONE truncated record"
uN.nul = 0
declare -a NA0=()
uN.toArray NA0
# With the newline delimiter the whole stream is one record, and no bash
# variable can hold a NUL (tpipe README §7), so everything from the first NUL
# on is dropped: ONE record, `a b`. The flag really is what changes the framing.
if [[ "$RESULT" == "1" ]] && arr_is NA0 "a b"; then
    kt_test_pass "one truncated record 'a b' against the two framed ones above"
else
    kt_test_fail "RESULT='$RESULT' NA0=$(arr_show NA0)"
fi
uN.delete

kt_test_start "crlf = 1 strips ONE trailing CR per record; crlf = 0 keeps it"
TUtil.new uCR pcr
declare -a CRON=() CROFF=()
uCR.crlf = 1
uCR.toArray CRON; n_on="$RESULT"
uCR.crlf = 0
uCR.toArray CROFF; n_off="$RESULT"
if [[ "$n_on" == "2" && "$n_off" == "2" ]] \
   && arr_is CRON "x" "y" && arr_is CROFF "x$CR" "y$CR"; then
    kt_test_pass "on: (x y); off: (x\\r y\\r) — a bash function producer keeps the CR"
else
    kt_test_fail "on=$(arr_show CRON) off=$(arr_show CROFF)"
fi

kt_test_start "crlf = 1 reaches \`each\`, \`first\` and \`count\` too"
uCR.crlf = 1
CB_RECS=()
uCR.each cb_collect
uCR.first 2>/dev/null; f="$RESULT"
uCR.count; c="$RESULT"
if arr_is CB_RECS "x" "y" && [[ "$f" == "x" && "$c" == "2" ]]; then
    kt_test_pass "each=(x y), first='x', count=2"
else
    kt_test_fail "each=$(arr_show CB_RECS) first='$f' count='$c'"
fi
uCR.delete

# ===========================================================================
kt_test_section "E. three-frame nested dispatch, and a nested sink"
# ===========================================================================

kt_test_start "g.each -> TPipe.each -> r.onLine: the callee instance keeps every mutation"
TUtil.new uE p4
TRec.new RE
REC_RECS=()
uE.each RE.onLine; rc=$?
n="$(RE.N)"
if [[ $rc -eq 0 && "$n" == "4" ]] && arr_is REC_RECS a b c d; then
    kt_test_pass "three frames deep, RE.N = 4"
else
    kt_test_fail "rc=$rc N='$n' REC_RECS=$(arr_show REC_RECS)"
fi
RE.delete

kt_test_start "a NESTED sink started from inside the callback does not disturb the outer one"
TUtil.new NU p2
NEST_OUTER=(); NEST_INNER=()
uE.each cb_nest; rc=$?
if [[ $rc -eq 0 ]] && arr_is NEST_OUTER a b c d \
   && arr_is NEST_INNER "inner=2:a b" "inner=2:a b" "inner=2:a b" "inner=2:a b"; then
    kt_test_pass "4 outer records, each with its own complete inner toArray"
else
    kt_test_fail "rc=$rc outer=$(arr_show NEST_OUTER) inner=$(arr_show NEST_INNER)"
fi

kt_test_start "the outer instance's \`lastRc\` is its own, not the inner sink's"
uE.lastRc; olr="$RESULT"
NU.lastRc; ilr="$RESULT"
if [[ "$olr" == "0" && "$ilr" == "0" ]]; then
    kt_test_pass "both 0 (both producers succeeded)"
else
    kt_test_fail "outer='$olr' inner='$ilr'"
fi
NU.delete
uE.delete

# ===========================================================================
kt_test_section "F. zero forks per record"
# ===========================================================================

kt_test_start "\`each\`: the callback runs in THIS process for every record"
TUtil.new uF p4
PID_RECS=()
uF.each cb_pid
same=1
for p in "${PID_RECS[@]}"; do
    if [[ "$p" != "$BASHPID" ]]; then
        same=0
    fi
done
if [[ "${#PID_RECS[@]}" == "4" ]] && (( same )); then
    kt_test_pass "4 callback calls, all at BASHPID=$BASHPID"
else
    kt_test_fail "pids=(${PID_RECS[*]}) mine=$BASHPID"
fi
uF.delete

kt_test_start "the ONLY fork per call is the producer (5 records, one foreign pid)"
TUtil.new uFP ppid5
declare -a FP=()
uFP.toArray FP
uniq_ok=1
for e in "${FP[@]}"; do
    if [[ "$e" != "${FP[0]}" ]]; then
        uniq_ok=0
    fi
done
if [[ "$RESULT" == "5" && "${FP[0]}" != "$BASHPID" ]] && (( uniq_ok )); then
    kt_test_pass "5 records all tagged with the single producer pid ${FP[0]} (ours is $BASHPID)"
else
    kt_test_fail "RESULT='$RESULT' FP=$(arr_show FP) mine=$BASHPID"
fi
uFP.delete

# ===========================================================================
kt_test_section "G. toList with a REJECTING .Add"
# ===========================================================================

kt_test_start "THashSet duplicates: RESULT counts records OFFERED, the set keeps fewer"
TUtil.new uG printf '%s\n' a b a b c
THashSet.new HS
uG.toList HS; rc=$?
off="$RESULT"
HS.Count; kept="$RESULT"
if [[ "$off" == "5" && "$kept" == "3" && $rc -eq 0 ]]; then
    kt_test_pass "5 offered, 3 kept, rc 0 — Add's rc 1 is not a stream error"
else
    kt_test_fail "offered='$off' kept='$kept' rc=$rc"
fi
HS.delete
uG.delete

# ===========================================================================
kt_test_section "H. the named deviation — rc 1 with the count KEPT"
# ===========================================================================

kt_test_start "a producer exiting 3: \`count\` is rc 1, RESULT = 2, lastRc = 3"
TUtil.new uH pfail3
uH.count; rc=$?; res="$RESULT"
uH.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && "$res" == "2" && "$lr" == "3" ]]; then
    kt_test_pass "rc 1, RESULT 2, lastRc 3"
else
    kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr'"
fi

kt_test_start "the same for \`toArray\` — the array still holds what arrived"
declare -a HA=()
uH.toArray HA; rc=$?; res="$RESULT"
if [[ $rc -eq 1 && "$res" == "2" ]] && arr_is HA a b; then
    kt_test_pass "rc 1 with both records in the caller's array"
else
    kt_test_fail "rc=$rc RESULT='$res' HA=$(arr_show HA)"
fi

kt_test_start "the same for \`each\` (rc 1) and \`toList\` (rc 1, records offered)"
CB_RECS=()
uH.each cb_collect; erc=$?
TCollector.new LH
LADD=()
uH.toList LH; lrc=$?; lres="$RESULT"
LH.delete
if [[ $erc -eq 1 && $lrc -eq 1 && "$lres" == "2" ]] \
   && arr_is CB_RECS a b && arr_is LADD a b; then
    kt_test_pass "both rc 1, both delivered everything the producer managed"
else
    kt_test_fail "each rc=$erc CB_RECS=$(arr_show CB_RECS) / toList rc=$lrc RESULT='$lres' LADD=$(arr_show LADD)"
fi

kt_test_start "\`first\` on a failing producer that DID give a record is rc 0 (we stopped it)"
uH.first 2>/dev/null; rc=$?; res="$RESULT"
if [[ $rc -eq 0 && "$res" == "a" ]]; then
    kt_test_pass "rc 0 with RESULT='a' — the consumer ended the stream"
else
    kt_test_fail "rc=$rc RESULT='$res'"
fi

kt_test_start "a producer that fails WITHOUT writing: \`first\` is rc 1, RESULT '', lastRc 4"
TUtil.new uH4 "$BASH" -c 'exit 4'
RESULT="sentinel"
uH4.first; rc=$?; res="$RESULT"
uH4.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && -z "$res" && "$lr" == "4" ]]; then
    kt_test_pass "rc 1, RESULT '', lastRc 4"
else
    kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr'"
fi
uH4.delete

kt_test_start "a producer that SUCCEEDS without writing: \`first\` is still rc 1 with RESULT ''"
# "no record" is `first`'s own answer and does not depend on the producer's rc:
# TPipe.first answered 1, so the member answers 1 whatever mapRc makes of the
# raw 0. `count` is the member to ask when the question is "how many".
TUtil.new uH0 true
RESULT="sentinel"
uH0.first; rc=$?; res="$RESULT"
uH0.lastRc; lr="$RESULT"
uH0.count; crc=$?; cres="$RESULT"
if [[ $rc -eq 1 && -z "$res" && "$lr" == "0" && $crc -eq 0 && "$cres" == "0" ]]; then
    kt_test_pass "first: rc 1 RESULT ''; lastRc 0; count: rc 0 RESULT 0"
else
    kt_test_fail "first rc=$rc RESULT='$res' lastRc='$lr' / count rc=$crc RESULT='$cres'"
fi
uH0.delete

kt_test_start "\`first\` stays SILENT on the no-record path when the raw rc is not 127"
: > "$ERRF"
TUtil.new uH1 "$BASH" -c 'exit 5'
VERBOSE_KKLASS=debug
uH1.first 2>"$ERRF" >/dev/null || :
VERBOSE_KKLASS=
uH1.delete
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "mapRc ran for its diagnostic side effect and had nothing to say"
else
    kt_test_fail "stderr: $(<"$ERRF")"
fi
uH.delete

# ===========================================================================
kt_test_section "I. U6 — a callback that calls TPipe.stop"
# ===========================================================================

kt_test_start "U6: \`each\` + \`TPipe.stop\` on an INFINITE producer: rc 0, lastRc 141/143, no hang"
run_child 'TUtil.new u yes
SN=0
cb() { SN=$(( SN + 1 )); TPipe.stop; }
rc=0
u.each cb 2>/dev/null || rc=$?
u.lastRc
printf "rc=%s n=%s lastRc=%s\n" "$rc" "$SN" "$RESULT"'
# 141 (SIGPIPE from the close) or 143 (SIGTERM from the kill) is a documented
# RACE in tpipe's close-kill-wait path, so the pattern admits both and nothing
# else; rc and the record count are pinned exactly.
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" =~ ^rc=0\ n=1\ lastRc=(141|143)$ ]]; then
    kt_test_pass "$CHILD_OUT (mapRc is NOT applied on the consumer-stop path)"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "U6: the stop is not a failure — the same callback over a FINITE producer is rc 0"
TUtil.new uI p4
SN=0
cb_stop() { SN=$(( SN + 1 )); CB_RECS+=( "$1" ); if (( SN == 2 )); then TPipe.stop; fi; return 0; }
CB_RECS=()
uI.each cb_stop 2>/dev/null; rc=$?
if [[ $rc -eq 0 && "$SN" == "2" ]] && arr_is CB_RECS a b; then
    kt_test_pass "stopped after 2 records, rc 0"
else
    kt_test_fail "rc=$rc SN='$SN' CB_RECS=$(arr_show CB_RECS)"
fi
uI.delete

kt_test_start "U6: \`first\` on an infinite producer answers at once and does not hang"
run_child 'TUtil.new u yes
rc=0
u.first 2>/dev/null || rc=$?
res="$RESULT"
u.lastRc
printf "rc=%s res=%s lastRc=%s\n" "$rc" "$res" "$RESULT"'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" =~ ^rc=0\ res=y\ lastRc=(141|143)$ ]]; then
    kt_test_pass "$CHILD_OUT"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

# ===========================================================================
kt_test_section "J. malformed calls: rc, RESULT, _lastRc and 'nothing ran'"
# ===========================================================================

kt_test_start "cmd='': every sink is rc 2, RESULT is '' for the funcs, and NOTHING runs"
rm -f "$FLAG"
TUtil.new uJ
uJ.addArg pmark
bad=""
RESULT="sentinel"
uJ.each cb_collect >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] || bad="$bad each(rc=$rc)"
for m in toArray toList first count; do
    RESULT="sentinel"
    "uJ.$m" JOUT >/dev/null 2>&1; rc=$?
    [[ $rc -eq 2 ]] || bad="$bad $m(rc=$rc)"
    [[ -z "$RESULT" ]] || bad="$bad $m(RESULT='$RESULT')"
done
[[ ! -e "$FLAG" ]] || bad="$bad flag-file-appeared"
uJ.lastRc
[[ "$RESULT" == "-1" ]] || bad="$bad lastRc=$RESULT"
if [[ -z "$bad" ]]; then
    kt_test_pass "all five rc 2, funcs RESULT '', producer never started, lastRc still -1"
else
    kt_test_fail "unexpected:$bad"
fi

kt_test_start "cmd='': a here-string handed to a refused sink is still fully readable"
line=""
{ uJ.count; rc=$?; IFS= read -r line; } <<< $'stdin1\nstdin2'
if [[ $rc -eq 2 && "$line" == "stdin1" ]]; then
    kt_test_pass "rc 2 and the here-string is still at record 1"
else
    kt_test_fail "rc=$rc line='$line'"
fi
uJ.delete

kt_test_start "a MISSING command: every sink is rc 1, lastRc 127, and NOTHING runs"
TUtil.new uM tutil_no_such_tool_xyz
bad=""
RESULT="sentinel"
uM.each cb_collect >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] || bad="$bad each(rc=$rc)"
for m in toArray toList first count; do
    RESULT="sentinel"
    "uM.$m" MOUT >/dev/null 2>&1; rc=$?
    [[ $rc -eq 1 ]] || bad="$bad $m(rc=$rc)"
    [[ -z "$RESULT" ]] || bad="$bad $m(RESULT='$RESULT')"
done
uM.lastRc
[[ "$RESULT" == "127" ]] || bad="$bad lastRc=$RESULT"
if [[ -z "$bad" ]]; then
    kt_test_pass "all five rc 1 with lastRc 127 and RESULT ''"
else
    kt_test_fail "unexpected:$bad"
fi

kt_test_start "a MISSING command is COMPLETELY silent with the debug switch off"
: > "$ERRF"
uM.count 2>"$ERRF" >/dev/null || :
uM.each cb_collect 2>>"$ERRF" >/dev/null || :
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "no stderr at all (bash's own 'command not found' is pre-empted)"
else
    kt_test_fail "stderr: $(<"$ERRF")"
fi

kt_test_start "a MISSING command prints EXACTLY ONE line per sink under VERBOSE_KKLASS=debug"
bad=""
for m in each toArray toList first count; do
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "uM.$m" MOUT 2>"$ERRF" >/dev/null || :
    VERBOSE_KKLASS=
    nlines "$ERRF"
    [[ $NLINES -eq 1 ]] || bad="$bad $m($NLINES lines)"
done
if [[ -z "$bad" ]]; then
    kt_test_pass "one line each, naming the member"
else
    kt_test_fail "unexpected:$bad"
fi
uM.delete

kt_test_start "a CB that is not a function: rc 2, nothing runs, \`lastRc\` UNTOUCHED"
rm -f "$FLAG"
TUtil.new uK pmark
RESULT="sentinel"
uK.each tutil_not_a_function_xyz >/dev/null 2>&1; rc=$?
uK.lastRc; lr="$RESULT"
if [[ $rc -eq 2 && "$lr" == "-1" && ! -e "$FLAG" ]]; then
    kt_test_pass "rc 2, lastRc still -1, the producer never started"
else
    kt_test_fail "rc=$rc lastRc='$lr' flag=$( [[ -e "$FLAG" ]] && echo yes || echo no )"
fi

kt_test_start "an INST without \`.Add\`: \`toList\` is rc 2, RESULT '', lastRc untouched"
TNoAdd.new NA1
rm -f "$FLAG"
RESULT="sentinel"
uK.toList NA1 >/dev/null 2>&1; rc=$?
res="$RESULT"
uK.lastRc; lr="$RESULT"
if [[ $rc -eq 2 && -z "$res" && "$lr" == "-1" && ! -e "$FLAG" ]]; then
    kt_test_pass "rc 2, RESULT '', lastRc -1, nothing ran"
else
    kt_test_fail "rc=$rc RESULT='$res' lastRc='$lr'"
fi
NA1.delete

kt_test_start "a bad out-name for \`toArray\`: rc 2, RESULT '', lastRc untouched, nothing runs"
rm -f "$FLAG"
bad=""
for n in state RESULT 1bad "a.b" "" __tu_v __tg_x uK_argv uK_args uK_data; do
    RESULT="sentinel"
    uK.toArray "$n" >/dev/null 2>&1; rc=$?
    [[ $rc -eq 2 ]] || bad="$bad $n(rc=$rc)"
    [[ -z "$RESULT" ]] || bad="$bad $n(RESULT='$RESULT')"
done
uK.lastRc; lr="$RESULT"
[[ "$lr" == "-1" ]] || bad="$bad lastRc=$lr"
[[ ! -e "$FLAG" ]] || bad="$bad flag-file-appeared"
if [[ -z "$bad" ]]; then
    kt_test_pass "10 refusals, each rc 2 with RESULT '' and nothing run"
else
    kt_test_fail "unexpected:$bad"
fi

kt_test_start "\`toArray __tu_v\` does NOT reach the instance's own argv array"
RESULT="sentinel"
uK.toArray __tu_v >/dev/null 2>&1 || :
declare -a KARGV=()
uK.argv KARGV
if arr_is KARGV "pmark" && arr_is uK_argv "pmark"; then
    kt_test_pass "the instance's argv is intact — the refusal happened before anything ran"
else
    kt_test_fail "KARGV=$(arr_show KARGV) uK_argv=$(arr_show uK_argv)"
fi
uK.delete

# ===========================================================================
kt_test_section "K. per-instance state, and \`argv\` still runs nothing"
# ===========================================================================

kt_test_start "two instances interleaved keep SEPARATE _lastRc"
TUtil.new uOK p2
TUtil.new uBAD pfail3
uOK.count >/dev/null; uBAD.count >/dev/null || :
uOK.count >/dev/null
uBAD.count >/dev/null || :
uOK.lastRc; lok="$RESULT"
uBAD.lastRc; lbad="$RESULT"
if [[ "$lok" == "0" && "$lbad" == "3" ]]; then
    kt_test_pass "uOK -> 0, uBAD -> 3"
else
    kt_test_fail "uOK.lastRc='$lok' uBAD.lastRc='$lbad'"
fi
uOK.delete
uBAD.delete

kt_test_start "\`argv\` still RUNS NOTHING now that the sinks exist"
rm -f "$FLAG"
TUtil.new uZ pmark
declare -a ZA=()
uZ.argv ZA; n="$RESULT"
if [[ "$n" == "1" && ! -e "$FLAG" ]] && arr_is ZA "pmark"; then
    kt_test_pass "argv=(pmark), the producer never ran"
else
    kt_test_fail "RESULT='$n' flag=$( [[ -e "$FLAG" ]] && echo yes || echo no ) ZA=$(arr_show ZA)"
fi
uZ.delete

kt_test_start "a sink REBUILDS the argv: a changed \`cmd\` is used on the next call"
TUtil.new uRB p2
uRB.count; a="$RESULT"
uRB.cmd = "p4"
uRB.count; b="$RESULT"
if [[ "$a" == "2" && "$b" == "4" ]]; then
    kt_test_pass "2 then 4"
else
    kt_test_fail "first='$a' second='$b'"
fi
uRB.delete

# ===========================================================================
kt_test_section "L. the three forms agree"
# ===========================================================================

kt_test_start "\`u.run | TPipe.each cb\` under lastpipe == \`TPipe.each cb -- argv\` == \`u.each cb\`"
FORMS="$TMP/forms.sh"
cat > "$FORMS" <<'FORMS_EOF'
#!/bin/bash
set -eu
shopt -s lastpipe
source "$1"          # tutil.sh, which sources tpipe.sh itself
p() { printf '%s\n' '-n' 'a b' 'back\slash' 'café'; }
GOT=()
cb() { GOT+=( "$1" ); }
TUtil.new u p

GOT=(); u.run | TPipe.each cb;            A="${GOT[*]}"
declare -a W=(); u.argv W
GOT=(); TPipe.each cb -- "${W[@]}";       B="${GOT[*]}"
GOT=(); u.each cb;                        C="${GOT[*]}"
if [[ "$A" == "$B" && "$B" == "$C" ]]; then
    printf 'SAME:%s\n' "$A"
else
    printf 'DIFF:[%s][%s][%s]\n' "$A" "$B" "$C"
fi
FORMS_EOF
out="$(timeout 20 "$BASH" "$FORMS" "$UNIT" 2>"$CHILD_ERR" </dev/null)"; rc=$?
err="$(<"$CHILD_ERR")"
if [[ $rc -eq 0 && "$out" == 'SAME:-n a b back\slash café' && -z "$err" ]]; then
    kt_test_pass "all three forms deliver the same records: ${out#SAME:}"
else
    kt_test_fail "rc=$rc out='$out' stderr='$err'"
fi

kt_test_start "the wrapper as a producer INSIDE a pipeline: \`u.run | wc -l\` is the tool's stream only"
TUtil.new uL p4
got="$(uL.run | wc -l)"
want="$(p4 | wc -l)"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "$got lines, no framework bytes"
else
    kt_test_fail "got='$got' want='$want'"
fi
uL.delete
