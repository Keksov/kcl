#!/bin/bash
# 004_Contract.sh — tpipe P1: the kcl-wide contract (kcl/README.md §1) for TPipe.
#
# What it pins:
#
#   source integrity  a sweeping mechanical edit must not silently mangle the
#                     file (`bash -n` + "no single-quoted string left open").
#   X-SETU (D7)       the unit loads, RE-loads, and runs EVERY sink in BOTH
#                     forms from a script under `set -eu`, including
#                       * the stop path, where `wait` returns 141/143 while the
#                         member itself answers rc 0 — a bare `wait` in
#                         tpipe._close aborts that frame (PLAN §6);
#                       * a callback / `.Add` whose own rc is non-zero (D2);
#                       * a producer that exits non-zero, where the member's own
#                         rc 1 must be what ends the child — exit status 1, not
#                         the producer's 4 leaking out of an unguarded `wait`.
#   §1.2 diagnostics  a malformed CALL is rc 2 and prints EXACTLY ONE line under
#                     `VERBOSE_KKLASS=debug` and NOTHING without it.
#   D6 final          a sink in a subshell is never refused; when the loss is
#                     CERTAIN it prints ONE `kk.warn` line — both templates
#                     (PLAN §2.4) asserted VERBATIM for `each` / `toArray` /
#                     `toList`, with the silence of `first` / `count`, of a
#                     plain-function and a static-member callback, and of every
#                     sink under `-s`, `KK_SUBSHELL_OK=1` and
#                     `VERBOSE_KKLASS=quiet`.
#   D6 final Q7       `TPipe.each` never prints: its stdout is the callback's.
#   §1.1/§1.2 silence TPipe itself prints nothing on any rc 0 / rc 1 path.
#
# Every test sets its own stdin explicitly: ktests gives a test child the
# terminal in `--mode single` and /dev/null in the default threaded mode, so a
# `-- cat` or a stdin-form case must never rely on what it inherits (PLAN §4).
# Producers on the stop path get `2>/dev/null`: a closed pipe routinely makes
# them print "write error: Broken pipe", which is the PRODUCER's stderr.

KTESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../ktests" && pwd)"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Contract" "$(dirname "$0")" "$@"

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$UNIT_DIR/tpipe.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: the kcl contract for TPipe (P1)"

# ===========================================================================
kt_test_section "0. source integrity"
# ===========================================================================

kt_test_start "the unit source parses"
if err="$("$BASH" -n "$UNIT" 2>&1)"; then
    kt_test_pass "bash -n clean"
else
    kt_test_fail "bash -n: $err"
fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then
    kt_test_fail "unterminated format string(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

# ===========================================================================
kt_test_section "1. X-SETU — every sink, both forms, under set -eu"
# ===========================================================================

# expect_clean TITLE SNIPPET [STDIN]
# The snippet runs in a CHILD under `set -eu`, so an abort fails the case
# instead of this file. stdin is ALWAYS explicit (a here-string, or /dev/null).
expect_clean() {
    local title="$1" snippet="$2" out rc err
    local errf="$TMP/setu.err"
    kt_test_start "$title"
    : > "$errf"
    if (( $# >= 3 )); then
        out="$(timeout 30 "$BASH" -c "set -eu
source '$UNIT'
$snippet
printf OK" 2>"$errf" <<< "$3")"; rc=$?
    else
        out="$(timeout 30 "$BASH" -c "set -eu
source '$UNIT'
$snippet
printf OK" 2>"$errf" </dev/null)"; rc=$?
    fi
    err="$(<"$errf")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "rc=$rc out='$out' stderr='$err'"
    fi
}

expect_clean "the unit loads under set -eu [X-SETU, D7]" ":"
expect_clean "loading the unit TWICE under set -eu is a no-op [X-SETU]" "source '$UNIT'"

expect_clean "the \`--\` form of all five sinks under set -eu" '
p3() { printf "a\nb\nc\n"; }
cb() { return 0; }
adder() { ADDED=$(( ADDED + 1 )); return 0; }
ADDED=0
declare -a ARR=()
TPipe.each cb -- p3
[[ "$RESULT" == "3" ]] || { printf "each RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.toArray ARR -- p3
[[ "$RESULT" == "3" && "${#ARR[@]}" == "3" ]] || { printf "toArray RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.count -- p3
[[ "$RESULT" == "3" ]] || { printf "count RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.first -- p3 2>/dev/null
[[ "$RESULT" == "a" ]] || { printf "first RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.lastRc'

expect_clean "the STDIN form of all five sinks under set -eu" '
cb() { return 0; }
declare -a ARR=()
TPipe.each cb < /dev/null
TPipe.toArray ARR < /dev/null
TPipe.count < /dev/null
TPipe.first < /dev/null || rc=$?
[[ "${rc:-0}" == "1" ]] || { printf "first on empty stdin rc=%s\n" "${rc:-0}" >&2; exit 1; }
TPipe.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 1; }'

expect_clean "the stdin form actually reading a here-string under set -eu" '
declare -a ARR=()
TPipe.toArray ARR
[[ "$RESULT" == "2" && "${ARR[0]}" == "s1" && "${ARR[1]}" == "s2" ]] \
    || { printf "toArray RESULT=%s ARR=%s\n" "$RESULT" "${ARR[*]}" >&2; exit 1; }' $'s1\ns2'

# The stop path is the one that runs `wait` on a producer killed by a signal:
# `wait` answers 141/143 while the member answers rc 0, so an UNGUARDED `wait`
# in tpipe._close would abort this child (PLAN §6).
expect_clean "the STOP path under set -eu: each + TPipe.stop on an infinite producer" '
stopper() { TPipe.stop; return 0; }
TPipe.each stopper -- yes 2>/dev/null
[[ "$RESULT" == "1" ]] || { printf "each RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.lastRc
[[ "$RESULT" == "141" || "$RESULT" == "143" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 1; }'

expect_clean "the STOP path under set -eu: first on an infinite producer" '
TPipe.first -- yes 2>/dev/null
[[ "$RESULT" == "y" ]] || { printf "first RESULT=%s\n" "$RESULT" >&2; exit 1; }
TPipe.lastRc
[[ "$RESULT" == "141" || "$RESULT" == "143" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 1; }'

expect_clean "the STOP path under set -eu: toList whose .Add calls TPipe.stop" '
class TS
    public
        var         N
        constructor Create
        proc        Add
end
TS.Create() { N=0; return 0; }
TS.Add()    { N=$(( N + 1 )); if (( N == 2 )); then TPipe.stop; fi; return 0; }
build TS
TS.new S
TPipe.toList S -- yes 2>/dev/null
[[ "$RESULT" == "2" ]] || { printf "toList RESULT=%s\n" "$RESULT" >&2; exit 1; }
S.delete'

expect_clean "D2 under set -eu: a callback that always answers rc 1 does not abort" '
pred() { return 1; }
p3() { printf "a\nb\nc\n"; }
TPipe.each pred -- p3
[[ "$RESULT" == "3" ]] || { printf "each RESULT=%s\n" "$RESULT" >&2; exit 1; }'

expect_clean "a REJECTING .Add (rc 1 per record) under set -eu does not abort" '
class TR
    public
        constructor Create
        proc        Add
end
TR.Create() { return 0; }
TR.Add()    { return 1; }
build TR
TR.new R
p3() { printf "a\nb\nc\n"; }
TPipe.toList R -- p3
[[ "$RESULT" == "3" ]] || { printf "toList RESULT=%s\n" "$RESULT" >&2; exit 1; }
R.delete'

expect_clean "a malformed call under set -eu is rc 2 and does not abort (caught by \`if\`)" '
declare -A BAD=()
if TPipe.toArray BAD -- printf "x\n" 2>/dev/null; then
    printf "assoc target was ACCEPTED\n" >&2; exit 1
fi
[[ "$RESULT" == "" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 1; }
if TPipe.toList tpipe_no_such_inst_004 -- printf "x\n" 2>/dev/null; then
    printf "dangling instance was ACCEPTED\n" >&2; exit 1
fi
if TPipe.first -z -- printf "x\n" 2>/dev/null; then
    printf "bad flag was ACCEPTED\n" >&2; exit 1
fi
if TPipe.count -z -- printf "x\n" 2>/dev/null; then
    printf "bad flag was ACCEPTED\n" >&2; exit 1
fi'

# A producer that exits non-zero: the member answers rc 1, which under `set -e`
# ends the child with status 1. An UNGUARDED `wait` inside tpipe._close would
# end it with the PRODUCER's status (4) before RESULT was ever set — so the
# exit status tells the two apart exactly.
FAILCHILD="$TMP/fail_child.sh"
cat > "$FAILCHILD" <<'FAIL_EOF'
#!/bin/bash
# $1 = tpipe unit dir, $2 = which sink. Runs under set -eu: the sink answers
# rc 1 (the producer exited 4), so errexit must end this script with status 1
# and "NEVER-REACHED" must not be printed.
set -eu
source "$1/tpipe.sh"
pfail4() { printf 'a\nb\n'; return 4; }
cb() { return 0; }
declare -a A=()
case "$2" in
    count)   TPipe.count -- pfail4 ;;
    each)    TPipe.each cb -- pfail4 ;;
    toArray) TPipe.toArray A -- pfail4 ;;
    toList)  TPipe.toList L4 -- pfail4 ;;
esac
printf 'NEVER-REACHED'
FAIL_EOF

kt_test_start "a producer exiting 4 ends a set -eu child with the MEMBER's rc 1, not 4"
fc_ok=1
fc_detail=""
for which in count each toArray; do
    out="$(timeout 30 "$BASH" "$FAILCHILD" "$UNIT_DIR" "$which" </dev/null 2>/dev/null)"; rc=$?
    if [[ $rc -ne 1 || -n "$out" ]]; then
        fc_ok=0
        fc_detail="$fc_detail [$which -> rc=$rc out='$out']"
    fi
done
if (( fc_ok )); then
    kt_test_pass "count / each / toArray: child exit status 1, nothing after the call ran"
else
    kt_test_fail "$fc_detail"
fi

NOECHILD="$TMP/noe_child.sh"
cat > "$NOECHILD" <<'NOE_EOF'
#!/bin/bash
# The same producer WITHOUT set -e: the caller keeps running, RESULT holds the
# records read before the producer failed (the named deviation, PLAN §2.4).
set -u
source "$1/tpipe.sh"
pfail4() { printf 'a\nb\n'; return 4; }
rc=0
TPipe.count -- pfail4 || rc=$?
n="$RESULT"
TPipe.lastRc
printf 'rc=%s n=%s lastrc=%s' "$rc" "$n" "$RESULT"
NOE_EOF

kt_test_start "the same child WITHOUT set -e keeps running and RESULT holds the records"
out="$(timeout 30 "$BASH" "$NOECHILD" "$UNIT_DIR" </dev/null 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 && "$out" == "rc=1 n=2 lastrc=4" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "rc=$rc out='$out'"
fi

# ===========================================================================
kt_test_section "2. rc 2 prints EXACTLY ONE line under the debug switch"
# ===========================================================================

ERRF="$TMP/dbg.err"

# dbg_lines COMMAND... -> DBG_N (line count), DBG_1 (the first line), DBG_RC
# Runs the call with VERBOSE_KKLASS=debug and its stderr captured.
dbg_lines() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" 2>"$ERRF" >/dev/null
    DBG_RC=$?
    VERBOSE_KKLASS=
    DBG_LINES=()
    local ln
    while IFS= read -r ln || [[ -n "$ln" ]]; do
        DBG_LINES+=( "$ln" )
    done < "$ERRF"
    DBG_N=${#DBG_LINES[@]}
    DBG_1="${DBG_LINES[0]:-}"
    return 0
}

# quiet_rc2 COMMAND... -> QRC (rc), QERR (stderr) with the switch OFF
quiet_rc2() {
    : > "$ERRF"
    "$@" 2>"$ERRF" >/dev/null
    QRC=$?
    QERR="$(<"$ERRF")"
    return 0
}

declare -A DBG_ASSOC=( [k]=1 )
declare -i DBG_INT=0
declare -a DBG_ARR=()
dbg_cb() { return 0; }
dbg_p()  { printf 'a\nb\n'; }
# the same producer with its OWN stderr discarded, for the stop-path cases
dbg_pq() { printf 'a\nb\n' 2>/dev/null; }

class TDbgList
    public
        constructor Create
        proc        Add
end
TDbgList.Create() { return 0; }
TDbgList.Add()    { return 0; }
build TDbgList
TDbgList.new DL

# TITLE, then the command: each case must be rc 2, exactly one debug line, and
# completely silent with the switch off.
check_rc2() {
    local title="$1"; shift
    kt_test_start "$title"
    dbg_lines "$@"
    local n="$DBG_N" first="$DBG_1" drc="$DBG_RC"
    quiet_rc2 "$@"
    if [[ $drc -eq 2 && $n -eq 1 && $QRC -eq 2 && -z "$QERR" ]]; then
        kt_test_pass "rc 2, one line: ${first:0:70}"
    else
        kt_test_fail "debug rc=$drc lines=$n first='$first' / quiet rc=$QRC err='$QERR'"
    fi
}

check_rc2 "toArray: a malformed output name"        TPipe.toArray 1bad -- dbg_p
check_rc2 "toArray: a reserved output name"         TPipe.toArray RESULT -- dbg_p
check_rc2 "toArray: an ASSOCIATIVE target"          TPipe.toArray DBG_ASSOC -- dbg_p
check_rc2 "toArray: an INTEGER-attributed target"   TPipe.toArray DBG_INT -- dbg_p
check_rc2 "toArray: a word after the operand"       TPipe.toArray DBG_ARR junk -- dbg_p
check_rc2 "toArray: an unknown flag"                TPipe.toArray -q DBG_ARR -- dbg_p
check_rc2 "toArray: '--' with no producer"          TPipe.toArray DBG_ARR --
check_rc2 "toArray: a missing operand"              TPipe.toArray
check_rc2 "toList: an instance with no .Add"        TPipe.toList tpipe_no_add_004 -- dbg_p
check_rc2 "toList: a word after the operand"        TPipe.toList DL junk -- dbg_p
check_rc2 "toList: an unknown flag"                 TPipe.toList -q DL -- dbg_p
check_rc2 "toList: '--' with no producer"           TPipe.toList DL --
check_rc2 "toList: a missing operand"               TPipe.toList
check_rc2 "first: an unknown flag"                  TPipe.first -q -- dbg_p
check_rc2 "first: a word where '--' belongs"        TPipe.first junk -- dbg_p
check_rc2 "first: '--' with no producer"            TPipe.first --
check_rc2 "count: an unknown flag"                  TPipe.count -q -- dbg_p
check_rc2 "count: a word where '--' belongs"        TPipe.count junk -- dbg_p
check_rc2 "count: '--' with no producer"            TPipe.count --
check_rc2 "each: a callback that is not a function" TPipe.each tpipe_no_cb_004 -- dbg_p

# ===========================================================================
kt_test_section "3. the D6-final subshell warnings, verbatim"
# ===========================================================================
# The owner's ruling of 2026-09-15 (PLAN §2.0 D6 final, nine answers):
#
#   Q1  a sink in a subshell is NEVER refused — the D1 rc 2 is gone;
#   Q2  a warning only when the loss is CERTAIN: `each` whose callback is an
#       INSTANCE member, `toArray`, `toList`. `each` with a plain function or a
#       STATIC member, and `first`/`count`, say nothing at all;
#   Q3  two per-call ways to silence it: the flag `-s` and the dynamically
#       scoped `KK_SUBSHELL_OK=1`;
#   Q5  one line per call, no de-duplication;
#   Q6  it goes through `kk.warn`, so it is printed with the debug switch OFF
#       and silenced by `VERBOSE_KKLASS=quiet`.
#
# The two templates are rebuilt HERE from their parts, so the assertion is a
# real pin and not a comparison of the unit with itself.

# w_line MEMBER WHAT LABEL FORM — the expected line, byte-exact (PLAN §2.4).
# FORM `stdin` (no `--`, almost always a pipe RHS) names `lastpipe` and the
# `--` form; FORM `cmd` (`--` present, almost always an explicit `$( )`) says
# "move the call out".
w_line() {
    if [[ "$4" == "stdin" ]]; then
        printf '%s' "Warning: TPipe.$1: $2 inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; in a pipeline use \`shopt -s lastpipe\` (non-interactive scripts) or the \`TPipe.$1 $3 -- CMD ...\` form at top level; if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
    else
        printf '%s' "Warning: TPipe.$1: $2 inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; move the call out of \$( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
    fi
}

# sub_case COMMAND... — run the command inside `$( )`, which is BASH_SUBSHELL 1
# exactly as the RHS of a pipe is, with a two-record here-string on stdin (the
# stdin form needs it; a `--` producer here ignores it). Sets SUB_OUT (stdout),
# SUB_RC, ERRL (stderr, one element per line) and ERRN.
sub_case() {
    : > "$ERRF"
    SUB_OUT="$( "$@" 2>"$ERRF" <<< $'x\ny' )"
    SUB_RC=$?
    ERRL=()
    local ln
    while IFS= read -r ln || [[ -n "$ln" ]]; do ERRL+=( "$ln" ); done < "$ERRF"
    ERRN=${#ERRL[@]}
    return 0
}

# An INSTANCE callback: `DR.onLine` is `inst.member` with a live `DR_data`,
# which is the whole callback-kind test (`declare -p "${cb%%.*}_data"`).
class TDbgRec
    public
        var         N
        constructor Create
        proc        onLine
end
TDbgRec.Create() { N=0; return 0; }
TDbgRec.onLine() { N=$(( N + 1 )); return 0; }
build TDbgRec
TDbgRec.new DR

# A STATIC member: `TDbgStat.onLine` also contains a dot, and a static class has
# no `_data` array — so it is treated like a plain function and never warns.
class TDbgStat
    public
        static proc onLine
end
TDbgStat.onLine() { return 0; }
build TDbgStat

kt_test_start "D6: both templates, byte-exact, for each / toArray / toList"
w_ok=1
w_detail=""
for member in each toArray toList; do
    case "$member" in
        each)    w_what="the instance member DR.onLine runs"; w_lbl="CB" ;;
        toArray) w_what="the array DBG_ARR is filled";         w_lbl="NAME" ;;
        toList)  w_what="DL.Add runs";                         w_lbl="INST" ;;
    esac
    for form in stdin cmd; do
        case "$member/$form" in
            each/stdin)    sub_case TPipe.each DR.onLine ;;
            each/cmd)      sub_case TPipe.each DR.onLine -- dbg_p ;;
            toArray/stdin) sub_case TPipe.toArray DBG_ARR ;;
            toArray/cmd)   sub_case TPipe.toArray DBG_ARR -- dbg_p ;;
            toList/stdin)  sub_case TPipe.toList DL ;;
            toList/cmd)    sub_case TPipe.toList DL -- dbg_p ;;
        esac
        w_exp="$(w_line "$member" "$w_what" "$w_lbl" "$form")"
        if [[ $SUB_RC -ne 0 || $ERRN -ne 1 || "${ERRL[0]:-}" != "$w_exp" ]]; then
            w_ok=0
            w_detail="$w_detail [$member/$form rc=$SUB_RC lines=$ERRN got='${ERRL[0]:-}']"
        fi
    done
done
if (( w_ok )); then
    kt_test_pass "6 cases: 3 sinks x 2 templates, one verbatim line each, rc 0"
else
    kt_test_fail "$w_detail"
fi

kt_test_start "D6: the records still arrive — a warning never changes rc or RESULT"
# `toArray` in a subshell fills an array nobody will read, but it fills it: the
# member's own answer is exactly the contract table's.
sub_case TPipe.toArray DBG_ARR -- dbg_p
a_out="$SUB_OUT"; a_rc=$SUB_RC
sub_case TPipe.toList DL -- dbg_p
l_out="$SUB_OUT"; l_rc=$SUB_RC
if [[ "$a_out" == "2" && $a_rc -eq 0 && "$l_out" == "2" && $l_rc -eq 0 ]]; then
    kt_test_pass "toArray and toList both answered 2 / rc 0 next to their warning"
else
    kt_test_fail "toArray='$a_out'($a_rc) toList='$l_out'($l_rc)"
fi

kt_test_start "D6: \`first\` and \`count\` NEVER warn, in either form (Q2)"
fc_ok=1
fc_detail=""
for spec in "first stdin" "first cmd" "count stdin" "count cmd"; do
    case "$spec" in
        "first stdin") sub_case TPipe.first ;;
        "first cmd")   sub_case TPipe.first -- dbg_pq ;;
        "count stdin") sub_case TPipe.count ;;
        "count cmd")   sub_case TPipe.count -- dbg_p ;;
    esac
    if [[ $ERRN -ne 0 ]]; then
        fc_ok=0
        fc_detail="$fc_detail [$spec lines=$ERRN got='${ERRL[0]:-}']"
    fi
done
if (( fc_ok )); then
    kt_test_pass "4 cases, not a byte on stderr — RESULT is the answer and the caller reads it"
else
    kt_test_fail "$fc_detail"
fi

kt_test_start "D6: \`each\` with a PLAIN FUNCTION and with a STATIC MEMBER is silent (Q2)"
k_ok=1
k_detail=""
for spec in "fn stdin" "fn cmd" "static stdin" "static cmd"; do
    case "$spec" in
        "fn stdin")     sub_case TPipe.each dbg_cb ;;
        "fn cmd")       sub_case TPipe.each dbg_cb -- dbg_p ;;
        "static stdin") sub_case TPipe.each TDbgStat.onLine ;;
        "static cmd")   sub_case TPipe.each TDbgStat.onLine -- dbg_p ;;
    esac
    if [[ $ERRN -ne 0 || $SUB_RC -ne 0 ]]; then
        k_ok=0
        k_detail="$k_detail [$spec rc=$SUB_RC lines=$ERRN got='${ERRL[0]:-}']"
    fi
done
if (( k_ok )); then
    kt_test_pass "a dotted STATIC name has no \`_data\` and is not an instance callback"
else
    kt_test_fail "$k_detail"
fi

kt_test_start "D6: \`-s\` silences every warning, in both forms (Q3)"
s_ok=1
s_detail=""
for spec in "each stdin" "each cmd" "toArray stdin" "toArray cmd" "toList stdin" "toList cmd"; do
    case "$spec" in
        "each stdin")    sub_case TPipe.each -s DR.onLine ;;
        "each cmd")      sub_case TPipe.each -s DR.onLine -- dbg_p ;;
        "toArray stdin") sub_case TPipe.toArray -s DBG_ARR ;;
        "toArray cmd")   sub_case TPipe.toArray -s DBG_ARR -- dbg_p ;;
        "toList stdin")  sub_case TPipe.toList -s DL ;;
        "toList cmd")    sub_case TPipe.toList -s DL -- dbg_p ;;
    esac
    if [[ $ERRN -ne 0 || $SUB_RC -ne 0 ]]; then
        s_ok=0
        s_detail="$s_detail [$spec rc=$SUB_RC lines=$ERRN got='${ERRL[0]:-}']"
    fi
done
if (( s_ok )); then
    kt_test_pass "6 cases, silent, rc unchanged — \`-s\` touches nothing but the warning"
else
    kt_test_fail "$s_detail"
fi

kt_test_start "D6: \`-s\` is accepted by \`first\`/\`count\` too and is inert there"
sub_case TPipe.first -s -- dbg_pq
i_out="$SUB_OUT"; i_rc=$SUB_RC; i_n=$ERRN
sub_case TPipe.count -s -- dbg_p
c_out="$SUB_OUT"; c_rc=$SUB_RC; c_n=$ERRN
if [[ "$i_out" == "a" && $i_rc -eq 0 && $i_n -eq 0 && "$c_out" == "2" && $c_rc -eq 0 && $c_n -eq 0 ]]; then
    kt_test_pass "first='a', count=2, no rc 2 for an unknown flag"
else
    kt_test_fail "first='$i_out'($i_rc,$i_n) count='$c_out'($c_rc,$c_n)"
fi

kt_test_start "D6: \`KK_SUBSHELL_OK=1 TPipe.toArray …\` as a PREFIX assignment silences it (Q3)"
: > "$ERRF"
p_out="$(KK_SUBSHELL_OK=1 TPipe.toArray DBG_ARR -- dbg_p 2>"$ERRF")"; p_rc=$?
p_err="$(<"$ERRF")"
if [[ "$p_out" == "2" && $p_rc -eq 0 && -z "$p_err" ]]; then
    kt_test_pass "the variable is the primitive; the flag is sugar over it"
else
    kt_test_fail "out='$p_out' rc=$p_rc err='$p_err'"
fi

kt_test_start "D6: \`local KK_SUBSHELL_OK=1\` covers a whole BLOCK, through a wrapper frame (Q3)"
# Dynamic scoping: the setting reaches every sink called below this frame and
# ends with it — the same seam `__TPIPE_QUIET` and `__TPIPE_STOP` use.
ok_block() {
    local KK_SUBSHELL_OK=1
    TPipe.toArray DBG_ARR -- dbg_p
    TPipe.toList DL -- dbg_p
    TPipe.each DR.onLine -- dbg_p
    return 0
}
: > "$ERRF"
b_out="$(ok_block 2>"$ERRF")"; b_rc=$?
b_err="$(<"$ERRF")"
: > "$ERRF"
n_out="$(TPipe.toArray DBG_ARR -- dbg_p 2>"$ERRF")"
n_err="$(<"$ERRF")"
if [[ $b_rc -eq 0 && -z "$b_err" && -n "$n_err" ]]; then
    kt_test_pass "three sinks silent inside the frame, the next call outside it warns again"
else
    kt_test_fail "block rc=$b_rc out='$b_out' err='$b_err' / after='$n_err'"
fi

kt_test_start "D6: \`VERBOSE_KKLASS=quiet\` silences the warning corpus-wide (Q6)"
VERBOSE_KKLASS=quiet
sub_case TPipe.toArray DBG_ARR -- dbg_p
q_n=$ERRN; q_out="$SUB_OUT"
sub_case TPipe.each DR.onLine
q_n2=$ERRN
VERBOSE_KKLASS=
if [[ $q_n -eq 0 && $q_n2 -eq 0 && "$q_out" == "2" ]]; then
    kt_test_pass "nothing on stderr under quiet, RESULT unchanged"
else
    kt_test_fail "toArray lines=$q_n out='$q_out' / each lines=$q_n2"
fi

kt_test_start "D6: the warning is printed with the debug switch OFF **and** under debug (Q6)"
# Everything above ran with the switch off, which is the point: a warning is not
# a debug line. Under `debug` the SAME single line appears — no second copy.
sub_case TPipe.toArray DBG_ARR -- dbg_p
off_n=$ERRN; off_1="${ERRL[0]:-}"
VERBOSE_KKLASS=debug
sub_case TPipe.toArray DBG_ARR -- dbg_p
VERBOSE_KKLASS=
on_n=$ERRN; on_1="${ERRL[0]:-}"
w_exp="$(w_line toArray "the array DBG_ARR is filled" NAME cmd)"
if [[ $off_n -eq 1 && $on_n -eq 1 && "$off_1" == "$w_exp" && "$on_1" == "$w_exp" ]]; then
    kt_test_pass "one identical line either way"
else
    kt_test_fail "off=$off_n '$off_1' / on=$on_n '$on_1'"
fi

kt_test_start "D6: an rc 2 path in a subshell warns NEVER — only its debug line, and only under debug"
# The warning is decided AFTER validation, so a malformed call cannot reach it
# (PLAN §2.5 step 5, §6).
VERBOSE_KKLASS=debug
sub_case TPipe.toArray RESULT -- dbg_p
r2_n=$ERRN; r2_1="${ERRL[0]:-}"; r2_rc=$SUB_RC; r2_out="$SUB_OUT"
VERBOSE_KKLASS=
sub_case TPipe.toArray RESULT -- dbg_p
r2q_n=$ERRN; r2q_rc=$SUB_RC
if [[ $r2_rc -eq 2 && -z "$r2_out" && $r2_n -eq 1 && "$r2_1" == "Error: TPipe.toArray:"* \
   && $r2q_rc -eq 2 && $r2q_n -eq 0 ]]; then
    kt_test_pass "one Error line under debug, nothing without it, no Warning either way"
else
    kt_test_fail "debug rc=$r2_rc lines=$r2_n first='$r2_1' / quiet rc=$r2q_rc lines=$r2q_n"
fi

kt_test_start "D6: at BASH_SUBSHELL 0 nothing warns at all — the stdin form included"
: > "$ERRF"
{
    TPipe.toArray DBG_ARR <<< $'x\ny'
    TPipe.toList DL <<< $'x\ny'
    TPipe.each DR.onLine <<< $'x\ny'
    TPipe.toArray DBG_ARR -- dbg_p
    TPipe.toList DL -- dbg_p
    TPipe.each DR.onLine -- dbg_p
} >/dev/null 2>"$ERRF"
z_err="$(<"$ERRF")"
if [[ -z "$z_err" ]]; then
    kt_test_pass "6 calls in the calling shell, not one warning"
else
    kt_test_fail "stderr='$z_err'"
fi

# ===========================================================================
kt_test_section "4. Q7 — \`TPipe.each\` never prints; its stdout is the callback's"
# ===========================================================================
# D6 final Q7, a named deviation from kcl §1.1 for this one member: `each` sets
# RESULT and returns, and never calls `tpipe._ret`. Before the ruling the record
# count was glued onto the callback's bytes in every subshell position.

q7_fmt() { printf 'F:%s\n' "$1"; return 0; }

kt_test_start "Q7: \`x=\$(TPipe.each fmt -- printf 'a\\nb\\n')\` is EXACTLY fmt's output"
x="$(TPipe.each q7_fmt -- printf 'a\nb\n' 2>/dev/null)"; rc=$?
if [[ "$x" == $'F:a\nF:b' && $rc -eq 0 ]]; then
    kt_test_pass "two formatted lines, no record count"
else
    kt_test_fail "x='$x' rc=$rc"
fi

kt_test_start "Q7: \`TPipe.each fmt -- cmd | cat\` likewise"
x="$(TPipe.each q7_fmt -- printf 'a\nb\n' 2>/dev/null | cat)"; rc=$?
if [[ "$x" == $'F:a\nF:b' && $rc -eq 0 ]]; then
    kt_test_pass "the LHS of a pipe carries only the callback's bytes"
else
    kt_test_fail "x='$x' rc=$rc"
fi

kt_test_start "Q7: a DIRECT call still sets RESULT to the record count"
RESULT="sentinel"
Q7OUT="$TMP/q7.out"
TPipe.each dbg_cb -- dbg_p >"$Q7OUT" 2>/dev/null; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 && ! -s "$Q7OUT" ]]; then
    kt_test_pass "RESULT=2, rc 0, stdout empty"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc stdout='$(cat "$Q7OUT")'"
fi

kt_test_start "Q7: an rc 2 path leaves RESULT '' and prints nothing, direct or in \$( )"
RESULT="sentinel"
TPipe.each tpipe_no_cb_q7 -- dbg_p >"$Q7OUT" 2>/dev/null; rc=$?
dres="$RESULT"
x="$(TPipe.each tpipe_no_cb_q7 -- dbg_p 2>/dev/null)"; src=$?
if [[ $rc -eq 2 && -z "$dres" && ! -s "$Q7OUT" && $src -eq 2 && -z "$x" ]]; then
    kt_test_pass "rc 2 both ways, RESULT='', not a byte on stdout"
else
    kt_test_fail "direct rc=$rc RESULT='$dres' out='$(cat "$Q7OUT")' / subst rc=$src x='$x'"
fi

kt_test_start "Q7: rc 1 (the producer failed) still answers with the count in RESULT"
RESULT="sentinel"
q7_fail() { printf 'a\nb\n'; return 4; }
TPipe.each dbg_cb -- q7_fail >"$Q7OUT" 2>/dev/null; rc=$?
n="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && "$n" == "2" && "$lr" == "4" && ! -s "$Q7OUT" ]]; then
    kt_test_pass "rc 1, RESULT=2, lastRc 4, nothing printed (the §2.4 deviation is unchanged)"
else
    kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr' stdout='$(cat "$Q7OUT")'"
fi

DR.delete

# ===========================================================================
kt_test_section "5. TPipe says nothing on any rc 0 / rc 1 path"
# ===========================================================================

# The producer's own stderr is not TPipe's (PLAN §4), so every producer used
# here discards it inside a wrapper function.
q_ok()    { printf 'a\nb\nc\n' 2>/dev/null; }
q_fail()  { printf 'a\n' 2>/dev/null; return 5; }
q_yes()   { yes 2>/dev/null; }
q_stop()  { TPipe.stop; return 0; }

kt_test_start "no output on rc 0 / rc 1 paths, with the debug switch ON"
: > "$ERRF"
SOUT="$TMP/silence.out"
declare -a S_ARR=()
VERBOSE_KKLASS=debug
{
    TPipe.each dbg_cb -- q_ok
    TPipe.toArray S_ARR -- q_ok
    TPipe.toList DL -- q_ok
    TPipe.first -- q_ok
    TPipe.count -- q_ok
    TPipe.each dbg_cb -- q_fail   || :
    TPipe.toArray S_ARR -- q_fail || :
    TPipe.toList DL -- q_fail     || :
    TPipe.count -- q_fail         || :
    TPipe.first -- printf ''      || :
    TPipe.each q_stop -- q_yes
    TPipe.first -- q_yes
    TPipe.stop
    TPipe.lastRc
} >"$SOUT" 2>"$ERRF"
VERBOSE_KKLASS=
if [[ ! -s "$ERRF" && ! -s "$SOUT" ]]; then
    kt_test_pass "13 calls, nothing on stdout or stderr"
else
    kt_test_fail "stdout='$(cat "$SOUT")' stderr='$(cat "$ERRF")'"
fi

DL.delete

# ===========================================================================
kt_test_section "6. __TPIPE_QUIET — the caller's opt-out from the subshell echo"
# ===========================================================================
# `tpipe._ret` prints RESULT under any `BASH_SUBSHELL > 0`, which is the right
# default for a caller that IS the answer. A composing caller — a kklass member
# that runs a sink and then answers through its OWN return channel — would have
# the value printed twice (measured: `$(u.count)` read back as `22` while tutil
# P1 was being written). kklass's `__kk_return_silent` cannot be borrowed for
# this: the THIN static dispatcher sets it to 1 for every static body already,
# so a static member could never tell "quiet" from "loud". Hence a dedicated,
# dynamically scoped opt-out the CALLER declares as a `local` of its own frame.

quiet_p() { printf '%s\n' a b c; }
quiet_add() { printf 'add:%s\n' "$1"; return 0; }

# the composing caller: a plain function is enough to prove the frame rule
quiet_caller() {
    local __TPIPE_QUIET=1
    TPipe.count -- quiet_p
    printf 'N=%s' "$RESULT"
}
loud_caller() {
    TPipe.count -- quiet_p
    printf 'N=%s' "$RESULT"
}

kt_test_start "with \`local __TPIPE_QUIET=1\` in the caller's frame the sink prints NOTHING and RESULT is still set"
out="$(quiet_caller 2>/dev/null)"
if [[ "$out" == "N=3" ]]; then
    kt_test_pass "only the caller's own bytes: '$out'"
else
    kt_test_fail "got '$out', want 'N=3'"
fi

kt_test_start "without it the same sink prints its RESULT once (the default is unchanged)"
out="$(loud_caller 2>/dev/null)"
if [[ "$out" == "3N=3" ]]; then
    kt_test_pass "the echo is still there by default: '$out'"
else
    kt_test_fail "got '$out', want '3N=3'"
fi

kt_test_start "the opt-out silences only tpipe._ret — a callback's own stdout still flows"
q_echo() { printf 'rec:%s\n' "$1"; }
quiet_each() {
    local __TPIPE_QUIET=1
    TPipe.each q_echo -- quiet_p
}
out="$(quiet_each 2>/dev/null)"
if [[ "$out" == $'rec:a\nrec:b\nrec:c' ]]; then
    kt_test_pass "three callback lines and no record count"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "the opt-out does not touch a toList target's own stdout either"
class TQuietList
    public
        constructor Create
        proc        Add
end
TQuietList.Create() { return 0; }
TQuietList.Add()    { printf 'add:%s\n' "$1"; return 0; }
build TQuietList
TQuietList.new QL
quiet_list() {
    local __TPIPE_QUIET=1
    TPipe.toList QL -- quiet_p
}
out="$(quiet_list 2>/dev/null)"
if [[ "$out" == $'add:a\nadd:b\nadd:c' ]]; then
    kt_test_pass "three Add lines and no record count"
else
    kt_test_fail "got '$out'"
fi
QL.delete

kt_test_start "a DIRECT call is unaffected by the flag in either state (nothing is printed anyway)"
: > "$ERRF"
QOUT="$TMP/quiet.out"
{
    __TPIPE_QUIET=1
    TPipe.count -- quiet_p
    a="$RESULT"
    __TPIPE_QUIET=0
    TPipe.count -- quiet_p
    b="$RESULT"
} >"$QOUT" 2>"$ERRF"
if [[ "$a" == "3" && "$b" == "3" && ! -s "$QOUT" && ! -s "$ERRF" ]]; then
    kt_test_pass "RESULT=3 both ways, no stdout at BASH_SUBSHELL 0"
else
    kt_test_fail "a='$a' b='$b' stdout='$(cat "$QOUT")' stderr='$(cat "$ERRF")'"
fi

kt_test_start "the load-time global exists, so reading it under \`set -u\` outside any sink is safe"
out="$(timeout 20 "$BASH" -c "set -eu
source '$UNIT'
printf 'q=%s' \"\$__TPIPE_QUIET\"" 2>"$ERRF" </dev/null)"; rc=$?
err="$(<"$ERRF")"
if [[ $rc -eq 0 && "$out" == "q=0" && -z "$err" ]]; then
    kt_test_pass "declared 0 at load"
else
    kt_test_fail "rc=$rc out='$out' stderr='$err'"
fi
