#!/bin/bash
# 001_Core.sh — tutil P0: the TUtil core (PLAN.md §5 P0.1–P0.3, pinned facts §3).
#
# TUtil is CONCRETE: `TUtil.new u git log --format=%H` is the whole TProcess use
# case with no subclass. This file pins the core that P1 (the TPipe sinks) and
# P2 (TGrep) build on. Every answer is compared with the bare tool or with a
# `declare -p` of the instance's own storage — never with a second call to the
# code under test.
#
# Sections:
#   0  source integrity (`bash -n` + the open-quote guard the house carries
#      since two mechanical sweeps corrupted sources while tests stayed green)
#   A  U3 — lifecycle: every declared var is present in `${inst}_data` right
#      after `new` with the documented default; `${inst}_args`/`_argv` exist and
#      are gone after `delete`; reading every var under `set -u` is clean
#   B  U2 — buildArgv / argv / addArg / clearArgs; `--format=%H` reaches Create
#      verbatim; `argv` hands out a COPY and runs nothing
#   C  `argv`'s out-name validation (kcl/README.md §1.7 + PLAN §2.1): rc 2,
#      RESULT='' and nothing written
#   D  U4/U5/U7 — `run`: cmd='' runs nothing and leaves stdin unread; a missing
#      command is rc 1 + lastRc 127 + exactly ONE stderr line under the switch
#      and NONE without it; the stream is byte-identical to the bare tool in all
#      three positions (`$( )`, `<( )`, the LHS of a pipe) — no leaked
#      kk._return digits (PLAN §2.2); a tool exiting 3 is rc 1 + lastRc 3 and
#      silent; two instances keep separate `_lastRc`
#   E  mapRc's base table (0→0, 127→1 + one debug line, anything else → 1 silent)
#   F  the `set -eu` contract: loading, re-loading, and a FAILING tool under
#      `run` that must NOT abort the caller (PLAN §2.3)
#   G  the P0 sink STUBS are gone (P1.1): no member answers the
#      `__TUTIL_PENDING__` sentinel, the string is absent from the source, and
#      the whole PLAN §1.2 surface is bound to a real body
#
# U1, U6 and U8 — what the sinks DO — are 002_Sinks.sh's subject; the `set -eu`
# and debug-switch contract for them is 003_Contract.sh's.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tutil.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "001: TUtil core — argv model, run, mapRc, lifecycle (P0)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# arr_is ARRNAME expected... — rc 0 iff the array holds exactly these elements
# in this order. Fork-free and byte-exact, so exotic argv words compare right.
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

# arr_show ARRNAME -> a printable form for a failure message.
arr_show() {
    local -n __a="$1"
    printf '(%s)' "${__a[*]:-}"
}

# nlines FILE -> NLINES (counts an unterminated last line too).
NLINES=0
nlines() {
    local __n=0 __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do __n=$(( __n + 1 )); done < "$1"
    NLINES=$__n
}

# run_child SNIPPET -> CHILD_OUT / CHILD_RC / CHILD_ERRTXT
# The snippet runs in a CHILD under `set -eu` with the unit freshly sourced, so
# an abort fails the case instead of this file. stdin is always explicit.
CHILD_ERR="$TMP/child.err"
CHILD_OUT=""
CHILD_RC=0
CHILD_ERRTXT=""
run_child() {
    : > "$CHILD_ERR"
    CHILD_OUT="$(timeout 20 "$BASH" -c "set -eu
source '$UNIT'
$1
printf OK" 2>"$CHILD_ERR" </dev/null)"
    CHILD_RC=$?
    CHILD_ERRTXT="$(<"$CHILD_ERR")"
}

OUTF="$TMP/run.out"
ERRF="$TMP/run.err"
FLAG="$TMP/ran.flag"

# A producer that leaves a trace on disk: "nothing runs" is asserted by the
# ABSENCE of this file, which survives any subshell the call may sit in.
pmark() { : > "$FLAG"; printf 'marked\n'; }

# A producer whose output is hostile to `echo` and to line-oriented handling:
# a leading `-n`, a backslash, a glob, a bare CR, and an unterminated tail.
p_exotic() {
    printf '%s\n' '-n' 'back\slash' '*'
    printf 'cr\r\n'
    printf 'no-newline-tail'
}

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

# ===========================================================================
kt_test_section "A. U3 — lifecycle, and every declared var assigned"
# ===========================================================================

kt_test_start "U3: right after \`new\` \${inst}_data lists cmd/crlf/nul/_lastRc with the documented defaults"
TUtil.new uL
d="$(declare -p uL_data 2>&1)"
if [[ "$d" == *'[cmd]=""'* && "$d" == *'[crlf]="0"'* \
   && "$d" == *'[nul]="0"'* && "$d" == *'[_lastRc]="-1"'* ]]; then
    kt_test_pass "all four vars present: $d"
else
    kt_test_fail "declare -p uL_data = $d"
fi

kt_test_start "U3: \${inst}_args and \${inst}_argv exist as EMPTY indexed arrays right after \`new\`"
da="$(declare -p uL_args 2>&1)"
dv="$(declare -p uL_argv 2>&1)"
if [[ "$da" == "declare -a uL_args="* && "$dv" == "declare -a uL_argv="* ]] \
   && arr_is uL_args && arr_is uL_argv; then
    kt_test_pass "both empty: $da / $dv"
else
    kt_test_fail "args='$da' argv='$dv'"
fi

kt_test_start "lastRc is -1 until something ran"
uL.lastRc; lr="$RESULT"; rc=$?
if [[ "$lr" == "-1" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT=-1, rc 0"
else
    kt_test_fail "RESULT='$lr' rc=$rc"
fi

kt_test_start "U3: after \`delete\` neither \${inst}_args nor \${inst}_argv nor \${inst}_data exists"
uL.delete
a_gone=0; v_gone=0; d_gone=0
declare -p uL_args >/dev/null 2>&1 || a_gone=1
declare -p uL_argv >/dev/null 2>&1 || v_gone=1
declare -p uL_data >/dev/null 2>&1 || d_gone=1
if [[ $a_gone -eq 1 && $v_gone -eq 1 && $d_gone -eq 1 ]]; then
    kt_test_pass "the destructor freed both arrays; kklass freed _data"
else
    kt_test_fail "args_gone=$a_gone argv_gone=$v_gone data_gone=$d_gone"
fi

kt_test_start "U3: a SECOND instance reusing the name starts empty (no storage left over)"
TUtil.new uL printf x
uL.delete
TUtil.new uL
if arr_is uL_args && [[ "$(uL.cmd)" == "" ]]; then
    kt_test_pass "args empty, cmd ''"
else
    kt_test_fail "args=$(arr_show uL_args) cmd='$(uL.cmd)'"
fi
uL.delete

kt_test_start "every declared var is readable under \`set -u\` right after \`new\` (no unbound)"
run_child 'TUtil.new u
u.cmd    >/dev/null
u.crlf   >/dev/null
u.nul    >/dev/null
u._lastRc >/dev/null'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "all four vars bound"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

# ===========================================================================
kt_test_section "B. U2 — buildArgv, argv, addArg, clearArgs"
# ===========================================================================

kt_test_start "U2: constructor arguments reach Create verbatim (\`--format=%H\` included)"
TUtil.new uG git log --format=%H
if [[ "$(uG.cmd)" == "git" ]] && arr_is uG_args "log" "--format=%H"; then
    kt_test_pass "cmd=git, args=(log --format=%H)"
else
    kt_test_fail "cmd='$(uG.cmd)' args=$(arr_show uG_args)"
fi

kt_test_start "U2: buildArgv fills \${inst}_argv with cmd + args and RESULT = the count"
uG.buildArgv; n="$RESULT"; rc=$?
if [[ "$n" == "3" && $rc -eq 0 ]] && arr_is uG_argv "git" "log" "--format=%H"; then
    kt_test_pass "argv=(git log --format=%H), RESULT=3"
else
    kt_test_fail "RESULT='$n' rc=$rc argv=$(arr_show uG_argv)"
fi

kt_test_start "buildArgv REBUILDS: calling it twice does not accumulate"
uG.buildArgv >/dev/null
uG.buildArgv; n="$RESULT"
if [[ "$n" == "3" ]] && arr_is uG_argv "git" "log" "--format=%H"; then
    kt_test_pass "still 3 elements after three builds"
else
    kt_test_fail "RESULT='$n' argv=$(arr_show uG_argv)"
fi

kt_test_start "U2: \`argv NAME\` copies the built array into the caller and RESULT = the count"
declare -a OUT=( stale1 stale2 stale3 stale4 )
uG.argv OUT; n="$RESULT"; rc=$?
if [[ "$n" == "3" && $rc -eq 0 ]] && arr_is OUT "git" "log" "--format=%H"; then
    kt_test_pass "the caller's array is REPLACED with the 3 words"
else
    kt_test_fail "RESULT='$n' rc=$rc OUT=$(arr_show OUT)"
fi

kt_test_start "U2: the caller's array is a COPY — mutating it does not touch \${inst}_argv"
OUT=( mutated )
if arr_is uG_argv "git" "log" "--format=%H"; then
    kt_test_pass "uG_argv untouched"
else
    kt_test_fail "uG_argv=$(arr_show uG_argv)"
fi

kt_test_start "\`argv\` runs NOTHING (no process, no side effect)"
rm -f "$FLAG"
TUtil.new uP pmark
declare -a OUT2=()
uP.argv OUT2; n="$RESULT"
if [[ "$n" == "1" && ! -e "$FLAG" ]] && arr_is OUT2 "pmark"; then
    kt_test_pass "argv built (pmark) and the producer never ran"
else
    kt_test_fail "RESULT='$n' flag=$( [[ -e "$FLAG" ]] && echo yes || echo no ) OUT2=$(arr_show OUT2)"
fi
uP.delete

kt_test_start "U2: addArg APPENDS to \${inst}_args (and reaches argv)"
uG.addArg -n 5
uG.addArg "a b"
declare -a OUT3=()
uG.argv OUT3; n="$RESULT"
if [[ "$n" == "6" ]] && arr_is uG_args "log" "--format=%H" "-n" "5" "a b" \
   && arr_is OUT3 "git" "log" "--format=%H" "-n" "5" "a b"; then
    kt_test_pass "three appends land in order, a word with a space stays one word"
else
    kt_test_fail "RESULT='$n' args=$(arr_show uG_args) OUT3=$(arr_show OUT3)"
fi

kt_test_start "addArg with NO arguments is a no-op"
uG.addArg
if arr_is uG_args "log" "--format=%H" "-n" "5" "a b"; then
    kt_test_pass "args unchanged"
else
    kt_test_fail "args=$(arr_show uG_args)"
fi

kt_test_start "U2: clearArgs EMPTIES \${inst}_args; argv is then cmd alone"
uG.clearArgs
declare -a OUT4=()
uG.argv OUT4; n="$RESULT"
if [[ "$n" == "1" ]] && arr_is uG_args && arr_is OUT4 "git"; then
    kt_test_pass "args empty, argv=(git), RESULT=1"
else
    kt_test_fail "RESULT='$n' args=$(arr_show uG_args) OUT4=$(arr_show OUT4)"
fi
uG.delete

kt_test_start "cmd='' -> buildArgv is rc 2 with RESULT='' and leaves argv empty"
TUtil.new uE
uE.addArg would-be-arg
RESULT="sentinel"
uE.buildArgv; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" ]] && arr_is uE_argv; then
    kt_test_pass "rc 2, RESULT='', argv empty"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' argv=$(arr_show uE_argv)"
fi

kt_test_start "cmd assigned later makes buildArgv succeed (the property is the surface)"
uE.cmd = "printf"
uE.buildArgv; n="$RESULT"; rc=$?
if [[ "$n" == "2" && $rc -eq 0 ]] && arr_is uE_argv "printf" "would-be-arg"; then
    kt_test_pass "argv=(printf would-be-arg)"
else
    kt_test_fail "RESULT='$n' rc=$rc argv=$(arr_show uE_argv)"
fi
uE.delete

# ===========================================================================
kt_test_section "C. \`argv\` out-name validation — rc 2, RESULT='', nothing written"
# ===========================================================================

TUtil.new uV printf hello

# bad_name TITLE NAME — rc 2, RESULT='', and the instance's own storage intact.
bad_name() {
    kt_test_start "$1"
    RESULT="sentinel"
    uV.argv "$2"; local rc=$?
    if [[ $rc -eq 2 && -z "$RESULT" ]] && arr_is uV_args "hello" \
       && [[ "$(uV.cmd)" == "printf" ]]; then
        kt_test_pass "rc 2, RESULT='', storage intact"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' args=$(arr_show uV_args) cmd='$(uV.cmd)'"
    fi
}

bad_name "argv 'state' is rc 2 (kklass binds it onto \${inst}_data in every frame)" "state"
bad_name "argv 'RESULT' is rc 2" "RESULT"
bad_name "argv '__tu_x' is rc 2 (this unit's own local prefix)" "__tu_x"
bad_name "argv '__tg_x' is rc 2 (the tgrep prefix, reserved from P0)" "__tg_x"
bad_name "argv '\${inst}_args' is rc 2 (the instance's own extra array)" "uV_args"
bad_name "argv '\${inst}_argv' is rc 2 (the instance's own extra array)" "uV_argv"
bad_name "argv '\${inst}_paths' is rc 2 (reserved for TGrep from P0)" "uV_paths"
bad_name "argv 'uV_data' is rc 2 (the kklass storage)" "uV_data"
bad_name "argv 'a.b' is rc 2 (not a plain identifier)" "a.b"
bad_name "argv '1bad' is rc 2 (identifiers do not start with a digit)" "1bad"
bad_name "argv '' is rc 2 (missing operand)" ""

kt_test_start "a refused out-name does NOT create the variable as a side effect"
RESULT="sentinel"
uV.argv tutil_never_created_9d3 >/dev/null 2>&1 || :
uV.argv "a.b" >/dev/null 2>&1 || :
if declare -p "a.b" >/dev/null 2>&1; then
    kt_test_fail "'a.b' exists after the refusal"
else
    kt_test_pass "nothing created"
fi

kt_test_start "a GOOD out-name still works after all the refusals"
declare -a OKARR=()
uV.argv OKARR; n="$RESULT"
if [[ "$n" == "2" ]] && arr_is OKARR "printf" "hello"; then
    kt_test_pass "argv=(printf hello)"
else
    kt_test_fail "RESULT='$n' OKARR=$(arr_show OKARR)"
fi
uV.delete

# ===========================================================================
kt_test_section "D. U4/U5/U7 — run"
# ===========================================================================

kt_test_start "U4: cmd='' -> \`run\` is rc 2, NOTHING runs, and stdin is left unread"
rm -f "$FLAG"
TUtil.new u4
u4.addArg "$BASH" -c ": > '$FLAG'"
line=""
{ u4.run; rc=$?; IFS= read -r line; } <<< $'stdin1\nstdin2'
if [[ $rc -eq 2 && ! -e "$FLAG" && "$line" == "stdin1" ]]; then
    kt_test_pass "rc 2, the flag file never appeared, the here-string is still at record 1"
else
    kt_test_fail "rc=$rc flag=$( [[ -e "$FLAG" ]] && echo yes || echo no ) line='$line'"
fi

kt_test_start "U4: cmd='' -> \`argv\` is rc 2 as well and nothing runs"
rm -f "$FLAG"
RESULT="sentinel"
declare -a OUT5=( keep )
u4.argv OUT5; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -e "$FLAG" ]] && arr_is OUT5 "keep"; then
    kt_test_pass "rc 2, RESULT='', the caller's array untouched"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' OUT5=$(arr_show OUT5)"
fi
u4.delete

kt_test_start "U5: a missing command is rc 1 with lastRc 127 and NOTHING runs"
TUtil.new u5 tutil_no_such_tool_xyz -x
: > "$OUTF"; : > "$ERRF"
u5.run >"$OUTF" 2>"$ERRF"; rc=$?
u5.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && "$lr" == "127" && ! -s "$OUTF" ]]; then
    kt_test_pass "rc 1, lastRc 127, no stdout"
else
    kt_test_fail "rc=$rc lastRc='$lr' stdout='$(<"$OUTF")'"
fi

kt_test_start "U5: with the debug switch OFF the missing command is COMPLETELY silent"
# bash's own 'command not found' goes to stderr UNCONDITIONALLY; the pre-check
# is what keeps this file empty (PLAN §2.3).
: > "$ERRF"
u5.run >/dev/null 2>"$ERRF" || :
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "no stderr at all"
else
    kt_test_fail "stderr: $(<"$ERRF")"
fi

kt_test_start "U5: under VERBOSE_KKLASS=debug it prints EXACTLY ONE stderr line"
: > "$ERRF"
VERBOSE_KKLASS=debug
u5.run >/dev/null 2>"$ERRF" || :
VERBOSE_KKLASS=
nlines "$ERRF"
if [[ $NLINES -eq 1 ]]; then
    kt_test_pass "one line: $(<"$ERRF")"
else
    kt_test_fail "$NLINES line(s): $(<"$ERRF")"
fi
u5.delete

kt_test_start "a tool exiting 3 is rc 1 with lastRc 3, and silent"
TUtil.new u3 "$BASH" -c 'exit 3'
: > "$OUTF"; : > "$ERRF"
u3.run >"$OUTF" 2>"$ERRF"; rc=$?
u3.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && "$lr" == "3" && ! -s "$OUTF" && ! -s "$ERRF" ]]; then
    kt_test_pass "rc 1, lastRc 3, no output"
else
    kt_test_fail "rc=$rc lastRc='$lr' stdout='$(<"$OUTF")' stderr='$(<"$ERRF")'"
fi

kt_test_start "a tool exiting 3 stays silent under VERBOSE_KKLASS=debug too (only 127 speaks)"
: > "$ERRF"
VERBOSE_KKLASS=debug
u3.run >/dev/null 2>"$ERRF" || :
VERBOSE_KKLASS=
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "no diagnostic for an ordinary tool failure"
else
    kt_test_fail "stderr: $(<"$ERRF")"
fi

kt_test_start "a tool exiting 0 is rc 0 with lastRc 0"
TUtil.new u0 "$BASH" -c 'exit 0'
u0.run >/dev/null 2>&1; rc=$?
u0.lastRc; lr="$RESULT"
if [[ $rc -eq 0 && "$lr" == "0" ]]; then
    kt_test_pass "rc 0, lastRc 0"
else
    kt_test_fail "rc=$rc lastRc='$lr'"
fi

kt_test_start "two instances interleaved keep SEPARATE _lastRc"
u3.run >/dev/null 2>&1 || :
u0.run >/dev/null 2>&1 || :
u3.lastRc; lr3="$RESULT"
u0.lastRc; lr0="$RESULT"
if [[ "$lr3" == "3" && "$lr0" == "0" ]]; then
    kt_test_pass "u3 -> 3, u0 -> 0"
else
    kt_test_fail "u3.lastRc='$lr3' u0.lastRc='$lr0'"
fi
u3.delete
u0.delete

kt_test_start "U7: \`\$(u.run)\` is byte-identical to the bare tool"
TUtil.new uR printf '%s\n' a b
got="$(uR.run)"
want="$(printf '%s\n' a b)"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "no leaked kk._return digits under \$( )"
else
    kt_test_fail "got='$got' want='$want'"
fi

kt_test_start "U7: \`od -c < <(u.run)\` is byte-identical to the bare tool"
got="$(od -c < <(uR.run))"
want="$(od -c < <(printf '%s\n' a b))"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "byte-exact through a process substitution"
else
    kt_test_fail "got='$got' want='$want'"
fi

kt_test_start "U7: \`u.run | od -c\` is byte-identical to the bare tool"
got="$(uR.run | od -c)"
want="$(printf '%s\n' a b | od -c)"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "byte-exact on the LHS of a pipe"
else
    kt_test_fail "got='$got' want='$want'"
fi
uR.delete

kt_test_start "U7: a producer emitting -n, a backslash, a glob, a CR and an unterminated tail — all three forms byte-exact"
TUtil.new uX p_exotic
want="$(p_exotic | od -c)"
g1="$(od -c < <(uX.run))"
g2="$(uX.run | od -c)"
g3="$(uX.run)"
w3="$(p_exotic)"
if [[ "$g1" == "$want" && "$g2" == "$want" && "$g3" == "$w3" ]]; then
    kt_test_pass "a shell FUNCTION is a legal cmd and its bytes survive verbatim"
else
    kt_test_fail "procsub='$g1' pipe='$g2' want='$want' subst_eq=$( [[ "$g3" == "$w3" ]] && echo yes || echo no )"
fi

kt_test_start "the direct call \`u.run\` prints the tool's stream and nothing else"
: > "$OUTF"; : > "$ERRF"
uX.run >"$OUTF" 2>"$ERRF"; rc=$?
if [[ $rc -eq 0 && ! -s "$ERRF" ]] && cmp -s "$OUTF" <(p_exotic); then
    kt_test_pass "stdout inherited byte-for-byte, stderr empty, rc 0"
else
    kt_test_fail "rc=$rc stderr='$(<"$ERRF")' stdout differs"
fi
uX.delete

kt_test_start "run REBUILDS argv: a changed cmd is used on the next run"
TUtil.new uC "$BASH" -c 'exit 0'
uC.run >/dev/null 2>&1 || :
uC.cmd = "$BASH"
uC.clearArgs
uC.addArg -c 'exit 5'
uC.run >/dev/null 2>&1; rc=$?
uC.lastRc; lr="$RESULT"
if [[ $rc -eq 1 && "$lr" == "5" ]]; then
    kt_test_pass "the second run used the new argv (lastRc 5)"
else
    kt_test_fail "rc=$rc lastRc='$lr' argv=$(arr_show uC_argv)"
fi
uC.delete

# ===========================================================================
kt_test_section "E. mapRc — the base table"
# ===========================================================================

TUtil.new uM "$BASH"

kt_test_start "mapRc 0 -> RESULT 0, rc 0"
RESULT="sentinel"
uM.mapRc 0; rc=$?
if [[ "$RESULT" == "0" && $rc -eq 0 ]]; then
    kt_test_pass "0 -> 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "mapRc 3 -> RESULT 1, rc 0, and silent under the debug switch"
: > "$ERRF"
VERBOSE_KKLASS=debug
uM.mapRc 3 2>"$ERRF"; rc=$?
VERBOSE_KKLASS=
if [[ "$RESULT" == "1" && $rc -eq 0 && ! -s "$ERRF" ]]; then
    kt_test_pass "3 -> 1, no diagnostic"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc stderr='$(<"$ERRF")'"
fi

kt_test_start "mapRc 127 -> RESULT 1, rc 0, and EXACTLY ONE debug line"
: > "$ERRF"
VERBOSE_KKLASS=debug
uM.mapRc 127 2>"$ERRF"; rc=$?
VERBOSE_KKLASS=
nlines "$ERRF"
if [[ "$RESULT" == "1" && $rc -eq 0 && $NLINES -eq 1 ]]; then
    kt_test_pass "127 -> 1 with one line: $(<"$ERRF")"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc lines=$NLINES stderr='$(<"$ERRF")'"
fi

kt_test_start "mapRc 127 is silent with the switch OFF"
: > "$ERRF"
uM.mapRc 127 2>"$ERRF" || :
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "no stderr"
else
    kt_test_fail "stderr: $(<"$ERRF")"
fi

kt_test_start "mapRc 1 -> RESULT 1 (the base has no 'no match' case; TGrep overrides it)"
uM.mapRc 1; rc=$?
if [[ "$RESULT" == "1" && $rc -eq 0 ]]; then
    kt_test_pass "1 -> 1"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi
uM.delete

# ===========================================================================
kt_test_section "F. the set -eu contract (PLAN §2.3, §6)"
# ===========================================================================

kt_test_start "the unit loads under \`set -eu\`"
run_child ':'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "clean"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "loading the unit TWICE under \`set -eu\` is a no-op"
run_child "source '$UNIT'"
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "the re-source guard holds"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "a FAILING tool under \`run\` does NOT abort a \`set -eu\` caller"
run_child 'TUtil.new u "$BASH" -c "exit 4"
rc=0
u.run || rc=$?
[[ "$rc" == "1" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 9; }
u.lastRc
[[ "$RESULT" == "4" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "rc 1 from the member, lastRc 4 stored before the frame ended"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "a MISSING tool under \`run\` does not abort a \`set -eu\` caller either"
run_child 'TUtil.new u tutil_no_such_tool_xyz
rc=0
u.run || rc=$?
[[ "$rc" == "1" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 9; }
u.lastRc
[[ "$RESULT" == "127" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "rc 1, lastRc 127, no bash diagnostic"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "the whole happy path runs under \`set -eu\`"
run_child 'TUtil.new u printf "%s\n" a b
declare -a A=()
u.argv A
[[ "$RESULT" == "4" ]] || { printf "argv RESULT=%s\n" "$RESULT" >&2; exit 9; }
u.addArg c
u.buildArgv
[[ "$RESULT" == "5" ]] || { printf "buildArgv RESULT=%s\n" "$RESULT" >&2; exit 8; }
u.clearArgs
u.addArg "ok\n"
u.run >/dev/null
u.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
u.mapRc 0
u.delete'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "clean"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

kt_test_start "a malformed CALL (bad out-name) does not abort a \`set -eu\` caller"
run_child 'TUtil.new u printf x
rc=0
u.argv state || rc=$?
[[ "$rc" == "2" ]] || { printf "argv rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$RESULT" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 8; }'
if [[ $CHILD_RC -eq 0 && "$CHILD_OUT" == "OK" && -z "$CHILD_ERRTXT" ]]; then
    kt_test_pass "rc 2 with RESULT='' and no abort"
else
    kt_test_fail "rc=$CHILD_RC out='$CHILD_OUT' stderr='$CHILD_ERRTXT'"
fi

# ===========================================================================
kt_test_section "G. the P0 sink stubs are GONE (P1.1)"
# ===========================================================================
# P0 shipped the five sinks as stubs answering `__TUTIL_PENDING__` with rc 2,
# and this section asserted exactly that. P1 gave them real bodies, so the same
# section now asserts the ABSENCE of the sentinel: no member of a live instance
# may answer it, on a valid call or on a refused one. The sinks' behaviour
# itself is 002/003's subject.

kt_test_start "no member answers the \`__TUTIL_PENDING__\` sentinel any more"
TUtil.new uS printf '%s\n' a b
declare -a SOUT=()
TCollectS_RECS=()
collect_s() { TCollectS_RECS+=( "$1" ); return 0; }
bad=""
# every sink on a VALID call
RESULT="sentinel"; uS.each collect_s >/dev/null 2>&1 || :
[[ "$RESULT" != "__TUTIL_PENDING__" ]] || bad="$bad each"
for m in first count; do
    RESULT="sentinel"
    "uS.$m" >/dev/null 2>&1 || :
    [[ "$RESULT" != "__TUTIL_PENDING__" ]] || bad="$bad $m"
done
RESULT="sentinel"; uS.toArray SOUT >/dev/null 2>&1 || :
[[ "$RESULT" != "__TUTIL_PENDING__" ]] || bad="$bad toArray"
# and on a REFUSED one (rc 2 must answer '' — never the sentinel)
for m in each toArray toList first count; do
    RESULT="sentinel"
    "uS.$m" "1bad" >/dev/null 2>&1 || :
    [[ "$RESULT" != "__TUTIL_PENDING__" ]] || bad="$bad refused-$m"
done
if [[ -z "$bad" ]]; then
    kt_test_pass "the sentinel is gone from every member, valid call and refusal alike"
else
    kt_test_fail "still pending:$bad"
fi
uS.delete

kt_test_start "the string \`__TUTIL_PENDING__\` is not in the unit source at all"
if bad="$(grep -n '__TUTIL_PENDING__' "$UNIT")"; then
    kt_test_fail "sentinel still in the source: ${bad//$'\n'/ | }"
else
    kt_test_pass "no stub left behind"
fi

kt_test_start "every declared member exists as a real body (none is a bare rc 2 stub)"
TUtil.new uR2 printf '%s\n' a b
missing=""
for m in cmd crlf nul _lastRc buildArgv addArg clearArgs argv run \
         each toArray toList first count lastRc mapRc; do
    declare -F -- "uR2.$m" >/dev/null 2>&1 || missing="$missing $m"
done
uR2.delete
if [[ -z "$missing" ]]; then
    kt_test_pass "all 16 members of the PLAN §1.2 surface are bound"
else
    kt_test_fail "missing:$missing"
fi
