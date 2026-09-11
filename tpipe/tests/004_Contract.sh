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
#                     `VERBOSE_KKLASS=debug` and NOTHING without it; the D1 and
#                     D6 lines are asserted VERBATIM (PLAN §2.5) for every sink.
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
kt_test_section "3. the D1 line, verbatim, for every sink"
# ===========================================================================

# PLAN §2.5 pins this text. Two things vary and nothing else does: the member
# name, and the OPERAND label in the suggested `--` form — `CB` for `each`,
# `NAME` for `toArray`, `INST` for `toList`, and nothing at all for `first` and
# `count`, which take no operand (so the line reads `TPipe.first -- CMD ...`,
# with single spaces and no double space where the operand would have been).
d1_line() {   # $1 = member, $2 = operand label ('' for the operand-less sinks)
    local __use="TPipe.$1"
    if [[ -n "$2" ]]; then
        __use="$__use $2"
    fi
    printf '%s' "Error: TPipe.$1: stdin form ran in a subshell (BASH_SUBSHELL=1); use \`$__use -- CMD ...\`, or \`shopt -s lastpipe\` at the top of a NON-interactive script (lastpipe is inert while job control is on)"
}

# The stdin form inside `$( )` — BASH_SUBSHELL is 1 there, and the printed
# RESULT (tpipe._ret prints in a subshell) must be empty on the refusal.
kt_test_start "D1: the stdin form in a subshell is rc 2 with EXACTLY the pinned line, per sink"
d1_ok=1
d1_detail=""
for member in toArray toList first count each; do
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    case "$member" in
        toArray) out="$(TPipe.toArray DBG_ARR 2>"$ERRF" <<< $'x\ny')"; drc=$?; lbl="NAME" ;;
        toList)  out="$(TPipe.toList DL 2>"$ERRF" <<< $'x\ny')";       drc=$?; lbl="INST" ;;
        each)    out="$(TPipe.each dbg_cb 2>"$ERRF" <<< $'x\ny')";     drc=$?; lbl="CB" ;;
        first)   out="$(TPipe.first 2>"$ERRF" <<< $'x\ny')";           drc=$?; lbl="" ;;
        count)   out="$(TPipe.count 2>"$ERRF" <<< $'x\ny')";           drc=$?; lbl="" ;;
    esac
    VERBOSE_KKLASS=
    LNS=()
    while IFS= read -r ln || [[ -n "$ln" ]]; do LNS+=( "$ln" ); done < "$ERRF"
    exp="$(d1_line "$member" "$lbl")"
    if [[ $drc -ne 2 || -n "$out" || ${#LNS[@]} -ne 1 || "${LNS[0]:-}" != "$exp" ]]; then
        d1_ok=0
        d1_detail="$d1_detail [$member rc=$drc out='$out' lines=${#LNS[@]} got='${LNS[0]:-}']"
    fi
done
if (( d1_ok )); then
    kt_test_pass "five sinks, one verbatim line each, RESULT empty"
else
    kt_test_fail "$d1_detail"
fi

kt_test_start "D1: with the switch OFF the refusal is completely silent"
: > "$ERRF"
out="$(TPipe.toArray DBG_ARR 2>"$ERRF" <<< $'x\ny')"; rc=$?
if [[ $rc -eq 2 && -z "$out" && ! -s "$ERRF" ]]; then
    kt_test_pass "rc 2, nothing on stderr"
else
    kt_test_fail "rc=$rc out='$out' err='$(cat "$ERRF")'"
fi

kt_test_start "D1: the pipe-RHS shape (no lastpipe) refuses too and reads nothing"
CBLOG="$TMP/d1_cb.log"
: > "$CBLOG"
logcb() { printf '%s\n' "$1" >> "$CBLOG"; return 0; }
OUTF="$TMP/d1.out"
{ printf 'x\ny\n' | TPipe.each logcb; rc=$?; } 2>/dev/null >"$OUTF"
n=0
while IFS= read -r ln; do n=$(( n + 1 )); done < "$CBLOG"
if [[ $rc -eq 2 && $n -eq 0 && ! -s "$OUTF" ]]; then
    kt_test_pass "rc 2, callback never ran, RESULT empty"
else
    kt_test_fail "rc=$rc callback lines=$n stdout='$(cat "$OUTF")'"
fi

# ===========================================================================
kt_test_section "4. the D6 warning, verbatim, for every sink"
# ===========================================================================

d6_line() {   # $1 = member
    printf '%s' "Warning: TPipe.$1: running in a subshell (BASH_SUBSHELL=1); records are delivered, but every mutation the callback makes is lost when the subshell exits"
}

kt_test_start "D6: the \`--\` form in a subshell is ALLOWED with EXACTLY the pinned warning, per sink"
d6_ok=1
d6_detail=""
for member in toArray toList first count each; do
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    case "$member" in
        toArray) out="$(TPipe.toArray DBG_ARR -- dbg_p 2>"$ERRF")"; drc=$?; expres="2" ;;
        toList)  out="$(TPipe.toList DL -- dbg_p 2>"$ERRF")";       drc=$?; expres="2" ;;
        each)    out="$(TPipe.each dbg_cb -- dbg_p 2>"$ERRF")";     drc=$?; expres="2" ;;
        first)   out="$(TPipe.first -- dbg_pq 2>"$ERRF")";          drc=$?; expres="a" ;;
        count)   out="$(TPipe.count -- dbg_p 2>"$ERRF")";           drc=$?; expres="2" ;;
    esac
    VERBOSE_KKLASS=
    LNS=()
    while IFS= read -r ln || [[ -n "$ln" ]]; do LNS+=( "$ln" ); done < "$ERRF"
    exp="$(d6_line "$member")"
    if [[ $drc -ne 0 || "$out" != "$expres" || ${#LNS[@]} -ne 1 || "${LNS[0]:-}" != "$exp" ]]; then
        d6_ok=0
        d6_detail="$d6_detail [$member rc=$drc out='$out' want='$expres' lines=${#LNS[@]} got='${LNS[0]:-}']"
    fi
done
if (( d6_ok )); then
    kt_test_pass "five sinks, records delivered, one verbatim warning each"
else
    kt_test_fail "$d6_detail"
fi

kt_test_start "D6: with the switch OFF the \`--\` form in a subshell is silent"
: > "$ERRF"
out="$(TPipe.count -- dbg_p 2>"$ERRF")"; rc=$?
if [[ $rc -eq 0 && "$out" == "2" && ! -s "$ERRF" ]]; then
    kt_test_pass "rc 0, RESULT printed once, nothing on stderr"
else
    kt_test_fail "rc=$rc out='$out' err='$(cat "$ERRF")'"
fi

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
