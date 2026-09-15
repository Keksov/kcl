#!/bin/bash
# 004_Argv.sh — ttail P0: the argv model (ttail/PLAN.md §1.2, §2.1, §2.2 and
# thead/PLAN.md §1.2, §2.1–§2.3, §2.8; pinned facts H1–H5, H4b, T1).
#
# THIS FILE NEVER RUNS tail. Every option is pinned by comparing the ARRAY that
# `t.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   tail [-q|-v] [-z] [-f] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
#
# so it is the fast half of the suite and it is true on a box where coreutils is
# missing altogether. The behavioural half is `005_Run.sh`.
#
# Sections:
#   A       lifecycle — every declared var present in `${inst}_data` right after
#           `new` with its documented default, `${t}_args` EMPTY after
#           `TTail.new t N PATH` (the `inherited`-in-a-constructor trap),
#           `${t}_paths` filled, a reused instance name starting clean, `delete`
#           removing `_paths` / `_args` / `_argv`, `argv` running nothing, and
#           H4b: the `__tt_` prefix is refused as an out-name (thead §2.8)
#   B  H1   every option SINGLY, `follow` included
#   C  H1   options in combination, in the pinned order; a non-`1` value is OFF;
#           `follow = 1` STILL yields `-f` from `argv` — the refusal of §2.1 is a
#           SINK rule, not an argv rule
#   D  H1   `--` iff there is at least one path; `addArg` extras land after the
#           options and before `--`; `addArg -n 5` after `lines = 3` yields BOTH
#           (tail is last-flag-wins); `paths` replaces the list
#   E  H2   the rc 2 list: empty `cmd`, `lines`+`bytes`, `quiet`+`verbose`,
#           `zeroTerminated` with 2 paths / with `verbose`, a bad count — rc 2,
#           RESULT '', the caller's array UNTOUCHED, `${inst}_argv` EMPTY, one
#           `kk.debug` line
#   F  T1   the count travels VERBATIM: `+2`, `08`, `-2`, `-0`, `+0`, `0` and a
#           19-digit value reach the argv unchanged. `kk.isInt` would have turned
#           `+2` (from line 2) into `2` (the LAST two lines) — a different
#           request, which is why §2.2 forbids it
#   G  H5   `zeroTerminated` derives the sinks' `-0`, with the P3-F1 guard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/ttail.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: TTail — typed options to argv, nothing executed (P0)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

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

arr_show() {
    local -n __a="$1"
    if (( ${#__a[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__a[@]}"
}

ERRF="$TMP/argv.err"
FLAG="$TMP/ran.flag"

DBG_RC=0; DBG_N=0; DBG_1=''
dbg_n() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    DBG_RC=$?
    VERBOSE_KKLASS=
    DBG_LINES=()
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        DBG_LINES+=( "$__l" )
    done < "$ERRF"
    DBG_N=${#DBG_LINES[@]}
    DBG_1="${DBG_LINES[0]:-}"
    return 0
}

declare -a GOT=()
check_argv() {
    local __t="$1" __i="$2"; shift 2
    kt_test_start "$__t"
    GOT=( sentinel-stale )
    RESULT="result-sentinel"
    local __rc=0
    "$__i".argv GOT || __rc=$?
    if [[ $__rc -eq 0 && "$RESULT" == "${#GOT[@]}" ]] && arr_is GOT "$@"; then
        kt_test_pass "$(arr_show GOT)"
    else
        kt_test_fail "rc=$__rc RESULT='$RESULT' got=$(arr_show GOT) want=$(printf '%q ' "$@")"
    fi
}

check_rc2() {
    local __t="$1" __want="$2" __i="$3"
    kt_test_start "$__t"
    GOT=( stale-1 stale-2 )
    RESULT="result-sentinel"
    dbg_n "$__i".argv GOT
    local -n __iv="${__i}_argv"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"$__want"* ]] \
       && arr_is GOT stale-1 stale-2 && (( ${#__iv[@]} == 0 )); then
        kt_test_pass "rc 2, RESULT '', array untouched, \${inst}_argv empty, one line: ${DBG_1:0:66}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' got=$(arr_show GOT) instArgv=$(arr_show __iv)"
    fi
}

reset() {
    TTail.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

# TTail's own seven (PLAN §1.2 — THead's six plus `follow`) plus TUtil's five.
TT_VARS=( lines bytes quiet verbose zeroTerminated follow _nulDerived )
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "every declared var is present in \`\${inst}_data\` right after \`new\`"
TTail.new tA 2 f1
missing=""
decl="$(declare -p tA_data)"
for v in "${TT_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TT_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "the documented defaults: booleans 0 (\`follow\` included), cmd tail, _lastRc -1"
bad=""
for v in quiet verbose zeroTerminated follow _nulDerived crlf nul subshellOk; do
    got="$(tA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
[[ "$(tA.bytes)" == "" ]]     || bad+=" bytes='$(tA.bytes)'"
[[ "$(tA.cmd)" == "tail" ]]   || bad+=" cmd='$(tA.cmd)'"
[[ "$(tA.lines)" == "2" ]]    || bad+=" lines='$(tA.lines)'"
[[ "$(tA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(tA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented; the constructor's N became \`lines\`"
else
    kt_test_fail "$bad"
fi

kt_test_start "\`TTail.new t\` with no argument at all leaves \`lines\` '' (tail's own default of 10)"
TTail.new tD
if [[ "$(tD.lines)" == "" && "$(tD.bytes)" == "" && "$(tD.cmd)" == "tail" ]]; then
    kt_test_pass "lines '', bytes '', cmd tail"
else
    kt_test_fail "lines='$(tD.lines)' bytes='$(tD.bytes)' cmd='$(tD.cmd)'"
fi
tD.delete

kt_test_start "\`\${t}_args\` is EMPTY after \`TTail.new t N PATH\` (the \`inherited\` trap)"
declare -n AA=tA_args
if (( ${#AA[@]} == 0 )); then
    kt_test_pass "args empty — the count and the paths did NOT leak into TUtil"
else
    kt_test_fail "tA_args=$(arr_show AA)"
fi
unset -n AA

kt_test_start "\`\${t}_paths\` holds the constructor's paths verbatim, once each"
TTail.new tP 3 'a b' -dash.txt $'nl\nname'
declare -n PP=tP_paths
if arr_is PP 'a b' '-dash.txt' $'nl\nname'; then
    kt_test_pass "3 paths, no doubling: $(arr_show PP)"
else
    kt_test_fail "tP_paths=$(arr_show PP)"
fi
unset -n PP
tP.delete

kt_test_start "a REUSED instance name starts clean (every var re-assigned by Create)"
TTail.new tR 1 x1
tR.follow = 1
tR.bytes = 7
tR.zeroTerminated = 1
TTail.new tR 4 x2                  # no delete in between — _data is NOT cleared
clean=1
[[ "$(tR.follow)" == "0" ]]         || clean=0
[[ "$(tR.bytes)" == "" ]]           || clean=0
[[ "$(tR.zeroTerminated)" == "0" ]] || clean=0
[[ "$(tR.lines)" == "4" ]]          || clean=0
declare -n RP=tR_paths
arr_is RP x2 || clean=0
unset -n RP
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\` — \`follow\` back to 0"
else
    kt_test_fail "follow='$(tR.follow)' bytes='$(tR.bytes)' z='$(tR.zeroTerminated)' lines='$(tR.lines)'"
fi

kt_test_start "\`delete\` removes \`_paths\`, \`_args\` AND \`_argv\` (the descendant destructor chains)"
declare -a W=()
tR.argv W >/dev/null 2>&1 || :
tR.delete
left=""
declare -p tR_paths >/dev/null 2>&1 && left+=" _paths"
declare -p tR_args  >/dev/null 2>&1 && left+=" _args"
declare -p tR_argv  >/dev/null 2>&1 && left+=" _argv"
declare -p tR_data  >/dev/null 2>&1 && left+=" _data"
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "\`argv\` RUNS NOTHING — not even a cmd that exists"
tt_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
TTail.new tN 2 f1
tN.cmd = tt_mark
W=()
rc=0
tN.argv W || rc=$?
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "5" ]] && arr_is W tt_mark -n 2 -- f1; then
    kt_test_pass "the 5-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
tN.delete

# --- H4b: the `__tt_` prefix is refused as an out-name (thead §2.8) ---------
bad_out() {
    kt_test_start "$1"
    local __m="$2" __n="$3"
    RESULT="sentinel"
    dbg_n tA."$__m" "$__n"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 \
          && "$DBG_1" == *"bad output array name"* && "$DBG_1" == *"$__n"* ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1'"
    fi
}

bad_out "H4b: \`t.argv __tt_v\` is rc 2 (the TTail local prefix, thead §2.8)"  argv    __tt_v
bad_out "H4b: \`t.argv __tt_p\` is rc 2"                                       argv    __tt_p
bad_out "H4b: \`t.toArray __tt_a\` is rc 2 — refused BEFORE anything runs"     toArray __tt_a
bad_out "H4b: \`t.argv __tu_x\` is still rc 2 (TUtil's own prefix)"            argv    __tu_x
bad_out "H4b: \`t.argv __tg_x\` is still rc 2 (the tgrep prefix)"              argv    __tg_x
bad_out "H4b: \`t.argv __th_x\` is rc 2 (the thead prefix)"                    argv    __th_x
bad_out "H4b: \`t.argv tA_paths\` is rc 2 (the instance's own operand array)"  argv    tA_paths

# ===========================================================================
kt_test_section "B. H1 — every option, singly"
# ===========================================================================

one() {   # one TITLE PROP VALUE WANTWORD...
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset t1 '' f
    t1."$__p" = "$__v"
    check_argv "$__t" t1 tail "$@" -- f
}

reset t1 '' f
check_argv "H1: no option at all — \`tail -- PATH\` (tail's own default of 10 lines)" t1 tail -- f

one "H1: \`quiet = 1\` -> -q"                                            quiet          1 -q
one "H1: \`verbose = 1\` -> -v"                                          verbose        1 -v
one "H1: \`zeroTerminated = 1\` -> -z (NUL-delimited INPUT records)"     zeroTerminated 1 -z
one "H1: \`follow = 1\` -> -f (the sink rules of §2.1 are separate)"     follow         1 -f
one "H1: \`lines = 3\` -> -n 3 as TWO words"                             lines          3 -n 3
one "H1: \`bytes = 3\` -> -c 3 as TWO words"                             bytes          3 -c 3

# ===========================================================================
kt_test_section "C. H1 — combinations, the pinned order, and the boolean rule"
# ===========================================================================

reset t2 5 f
t2.follow = 1
check_argv "H1: -f before -n, the pinned order" t2 tail -f -n 5 -- f

reset t2 '' f
t2.lines = 5
t2.follow = 1
t2.quiet = 1
check_argv "H1: -q -f -n 5 — the ORDER is buildArgv's, not the caller's" t2 \
    tail -q -f -n 5 -- f

reset t2 '' f
t2.quiet = 1
t2.zeroTerminated = 1
t2.follow = 1
t2.bytes = 12
check_argv "H1: -q -z -f -c 12 — the full pinned order on one path" t2 \
    tail -q -z -f -c 12 -- f

reset t2 '' 'dir one' 'dir two'
t2.verbose = 1
t2.lines = +2
check_argv "H1: -v with two paths and a \`+N\` count" t2 \
    tail -v -n +2 -- 'dir one' 'dir two'

reset t2 7 f
t2.quiet = 1
t2.zeroTerminated = 1
t2.follow = 1
t2.addArg --extra
check_argv "H1: EVERYTHING compatible at once, extras last" t2 \
    tail -q -z -f -n 7 --extra -- f

kt_test_start "T2: \`argv\` with \`follow = 1\` STILL yields \`-f\` (the refusal is a SINK rule, §2.1)"
reset t2 5 f
t2.follow = 1
GOT=()
rc=0
t2.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT tail -f -n 5 -- f; then
    kt_test_pass "rc 0 and \`-f\` in its slot — only toArray/count/toList refuse"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "H1: a boolean is ON only for the exact string \`1\` (\`follow\` included)"
allgood=1
badv=""
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset t3 '' f
    t3.follow = "$v"
    GOT=()
    t3.argv GOT >/dev/null 2>&1 || :
    if ! arr_is GOT tail -- f; then
        allgood=0
        badv="'$v' -> $(arr_show GOT)"
        break
    fi
done
if [[ "$allgood" == "1" ]]; then
    kt_test_pass "'2', 'yes', 'true', 'on', '01', '-1', ' 1' and '1 ' are all OFF"
else
    kt_test_fail "$badv"
fi

# ===========================================================================
kt_test_section "D. H1 — \`--\` only with paths, extras in place, \`paths\`"
# ===========================================================================

reset t4 2
check_argv "H1: \`TTail.new t N\` with no path is the STDIN form — no \`--\` at all" t4 tail -n 2

reset t4 2 'a b'
check_argv "H1: one path -> \`-- 'a b'\`" t4 tail -n 2 -- 'a b'

reset t4 2 a b c
check_argv "H1: three paths, all after the one \`--\`" t4 tail -n 2 -- a b c

reset t4 2 -weird.txt
check_argv "H1: a path that starts with \`-\` is an operand, not a flag" t4 \
    tail -n 2 -- -weird.txt

reset t4 2 f
t4.addArg --zero-terminated
check_argv "H1: an \`addArg\` extra lands AFTER the options and BEFORE \`--\`" t4 \
    tail -n 2 --zero-terminated -- f

reset t4 '' f
t4.lines = 3
t4.addArg -n 5
check_argv "H1: \`addArg -n 5\` after \`lines = 3\` yields BOTH — tail is last-flag-wins" t4 \
    tail -n 3 -n 5 -- f

reset t4 2 f
t4.addArg --pid=1234
check_argv "H1: \`addArg --pid=PID\` (the only self-terminating \`-f\`, §2.1)" t4 \
    tail -n 2 --pid=1234 -- f

reset t4 2 f
t4.addArg -q
t4.clearArgs
check_argv "H1: \`clearArgs\` empties the extras again" t4 tail -n 2 -- f

reset t4 2 old1 old2
t4.paths new1 'new 2'
check_argv "H1: \`t.paths new1 'new 2'\` replaced both old paths" t4 \
    tail -n 2 -- new1 'new 2'

reset t4 2 old1
t4.paths
check_argv "H1: \`t.paths\` with no argument is the stdin form" t4 tail -n 2

kt_test_start "H1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset t4 2 f
t4.follow = 1
declare -a W1=() W2=()
t4.argv W1 >/dev/null 2>&1 || :
t4.argv W2 >/dev/null 2>&1 || :
if arr_is W1 tail -f -n 2 -- f && arr_is W2 tail -f -n 2 -- f; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "H1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
t4.argv W3 >/dev/null 2>&1 || :
W3[1]="TAMPERED"
declare -n IV=t4_argv
if [[ "${IV[1]:-}" == "-f" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "t4_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "E. H2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset tE 2 f
tE.cmd = ''
check_rc2 "H2: empty \`cmd\` is rc 2" "cmd is empty" tE

reset tE 2 f
tE.bytes = 3
check_rc2 "H2: \`lines\` + \`bytes\` (-n and -c) is rc 2" "lines" tE

reset tE '' f
tE.quiet = 1
tE.verbose = 1
check_rc2 "H2: \`quiet\` + \`verbose\` (-q and -v) is rc 2" "quiet" tE

reset tE '' a b
tE.zeroTerminated = 1
check_rc2 "H2: \`zeroTerminated\` with TWO paths is rc 2 (the headers stay \\n-framed)" \
    "zeroTerminated" tE

reset tE '' f
tE.zeroTerminated = 1
tE.verbose = 1
check_rc2 "H2: \`zeroTerminated\` + \`verbose\` is rc 2" "zeroTerminated" tE

reset tE x f
check_rc2 "H2: \`lines = x\` is rc 2 (the count regex \`^[+-]?[0-9]+\$\`)" "lines" tE

reset tE 1K f
check_rc2 "H2: \`lines = 1K\` is rc 2 — the suffix hatch is \`addArg -n 1K\`" "lines" tE

reset tE '1 2' f
check_rc2 "H2: \`lines = '1 2'\` is rc 2 (never re-split into two words)" "lines" tE

reset tE '' f
tE.lines = '--5'
check_rc2 "H2: \`lines = '--5'\` is rc 2 (one optional sign only)" "lines" tE

reset tE 99999999999999999999 f
check_rc2 "H2: a 20-digit \`lines\` is rc 2 — the magnitude guard" "lines" tE

reset tE '' f
tE.bytes = abc
check_rc2 "H2: \`bytes = abc\` is rc 2 (the same regex)" "bytes" tE

reset tE '' f
tE.bytes = 99999999999999999999
check_rc2 "H2: a 20-digit \`bytes\` is rc 2" "bytes" tE

reset tE '' f
tE.lines = ' 2'
check_rc2 "H2: \`lines = ' 2'\` is rc 2 (no surrounding blanks)" "lines" tE

kt_test_start "H2: each half of a refused pair on its OWN is fine, \`follow\` too"
ok=1
reset tE '' f; tE.lines = 3;          tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f; tE.bytes = 3;          tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f; tE.quiet = 1;          tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f; tE.verbose = 1;        tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f; tE.zeroTerminated = 1; tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f; tE.follow = 1;         tE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "only the COMBINATION is refused; \`follow\` alone always builds"
else
    kt_test_fail "a single option was refused"
fi

kt_test_start "H2: \`zeroTerminated\` with ONE path (and with none) is accepted"
ok=1
reset tE '' f;  tE.zeroTerminated = 1; tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '';    tE.zeroTerminated = 1; tE.argv GOT >/dev/null 2>&1 || ok=0
reset tE '' f;  tE.zeroTerminated = 1; tE.quiet = 1; tE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "one path, stdin, and \`-q\` all build"
else
    kt_test_fail "a legal \`-z\` shape was refused"
fi

# ===========================================================================
kt_test_section "F. T1 — the count travels VERBATIM (§2.2, thead §2.2)"
# ===========================================================================

verbatim() {   # verbatim PROP VALUE FLAG
    local __p="$1" __v="$2" __f="$3"
    reset tF '' f
    tF."$__p" = "$__v"
    check_argv "T1: \`$__p = $__v\` reaches tail as \`$__f $__v\`, unchanged" tF \
        tail "$__f" "$__v" -- f
}

verbatim lines +2  -n
verbatim lines 08  -n
verbatim lines -2  -n
verbatim lines -0  -n
verbatim lines +0  -n
verbatim lines 0   -n
verbatim bytes +3  -c
verbatim bytes 08  -c
verbatim bytes -2  -c
verbatim bytes -0  -c

kt_test_start "T1: a 19-digit count PASSES the guard and reaches tail verbatim"
reset tF '' f
tF.lines = 9999999999999999999
GOT=()
rc=0
tF.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT tail -n 9999999999999999999 -- f; then
    kt_test_pass "19 digits is the bound the guard allows; 20 is rc 2 (§E)"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "T1: the property still READS what the caller wrote (no write-back)"
reset tF '' f
tF.lines = +2
tF.argv GOT >/dev/null 2>&1 || :
a="$(tF.lines)"
reset tF '' f
tF.lines = 08
tF.argv GOT >/dev/null 2>&1 || :
b="$(tF.lines)"
if [[ "$a" == "+2" && "$b" == "08" ]]; then
    kt_test_pass "'+2' and '08' survive a build (kk.isInt would have written 2 and 8)"
else
    kt_test_fail "after +2: '$a'; after 08: '$b'"
fi

# ===========================================================================
kt_test_section "G. H5 — \`zeroTerminated\` derives the sinks' \`-0\` (P3-F1)"
# ===========================================================================

kt_test_start "H5: \`zeroTerminated = 1\` with one path DERIVES \`nul = 1\`"
reset tZ 2 f
tZ.zeroTerminated = 1
GOT=()
rc=0
tZ.argv GOT || rc=$?
if [[ $rc -eq 0 && "$(tZ.nul)" == "1" && "$(tZ._nulDerived)" == "1" ]] \
   && arr_is GOT tail -z -n 2 -- f; then
    kt_test_pass "nul = 1, _nulDerived = 1, argv has -z"
else
    kt_test_fail "rc=$rc nul='$(tZ.nul)' drv='$(tZ._nulDerived)' GOT=$(arr_show GOT)"
fi

kt_test_start "H5: \`zeroTerminated = 0\` again takes the derived \`-0\` back off"
tZ.zeroTerminated = 0
tZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(tZ.nul)" == "0" && "$(tZ._nulDerived)" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding"
else
    kt_test_fail "nul='$(tZ.nul)' drv='$(tZ._nulDerived)'"
fi

kt_test_start "H5: a MANUAL \`nul = 1\` with \`zeroTerminated = 0\` is the caller's and survives"
reset tZ 2 f
tZ.nul = 1
tZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(tZ.nul)" == "1" && "$(tZ._nulDerived)" == "0" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(tZ.nul)' drv='$(tZ._nulDerived)'"
fi

kt_test_start "H5 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset tZ 2 f
tZ.nul = 1
tZ.zeroTerminated = 1
tZ.argv GOT >/dev/null 2>&1 || :
mid="$(tZ.nul)" middrv="$(tZ._nulDerived)"
tZ.zeroTerminated = 0
tZ.argv GOT >/dev/null 2>&1 || :
end="$(tZ.nul)" enddrv="$(tZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through -z and back"
else
    kt_test_fail "after -z: nul='$mid' drv='$middrv'; after zeroTerminated=0: nul='$end' drv='$enddrv'"
fi

kt_test_start "H5: a REFUSED build derives nothing (\`-z\` with two paths never reaches the rule)"
reset tZ 2 a b
tZ.zeroTerminated = 1
tZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(tZ.nul)" == "0" && "$(tZ._nulDerived)" == "0" ]]; then
    kt_test_pass "nul untouched on the rc 2 path"
else
    kt_test_fail "nul='$(tZ.nul)' drv='$(tZ._nulDerived)'"
fi

kt_test_start "H5: \`crlf\` is never touched by buildArgv"
reset tZ 2 f
tZ.crlf = 1
tZ.zeroTerminated = 1
tZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(tZ.crlf)" == "1" ]]; then
    kt_test_pass "crlf = 1 kept"
else
    kt_test_fail "crlf='$(tZ.crlf)'"
fi

tA.delete
t1.delete
t2.delete
t3.delete
t4.delete
tE.delete
tF.delete
tZ.delete
