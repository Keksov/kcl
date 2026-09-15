#!/bin/bash
# 004_Argv.sh — thead P0: the argv model (thead/PLAN.md §1.2, §2.1–§2.3, §2.8;
# pinned facts H1–H5, H4b).
#
# THIS FILE NEVER RUNS head. Every option is pinned by comparing the ARRAY that
# `h.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   head [-q|-v] [-z] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
#
# so it is the fast half of the suite and it is true on a box where coreutils is
# missing altogether. The behavioural half is `005_Run.sh`.
#
# Sections:
#   A       lifecycle — every declared var present in `${inst}_data` right after
#           `new` with its documented default, `${h}_args` EMPTY after
#           `THead.new h N PATH` (the `inherited`-in-a-constructor trap),
#           `${h}_paths` filled, a reused instance name starting clean, `delete`
#           removing `_paths` / `_args` / `_argv`, `argv` running nothing, and
#           H4b: the `__th_` prefix is refused as an out-name (§2.8)
#   B  H1   every option SINGLY
#   C  H1   options in combination, in the pinned order; a non-`1` value is OFF
#   D  H1   `--` iff there is at least one path; `addArg` extras land after the
#           options and before `--`; `addArg -n 5` after `lines = 3` yields BOTH
#           (head is last-flag-wins, §1.3); `paths` replaces the list
#   E  H2   the rc 2 list: empty `cmd`, `lines`+`bytes`, `quiet`+`verbose`,
#           `zeroTerminated` with 2 paths / with `verbose`, a bad count — rc 2,
#           RESULT '', the caller's array UNTOUCHED, `${inst}_argv` EMPTY, one
#           `kk.debug` line
#   F  H3   the count travels VERBATIM: `08`, `+3`, `-2`, `-0`, `+0`, `0` and a
#           19-digit value reach the argv unchanged (NOT through `kk.isInt`,
#           which would strip the sign and fold `-0` into `0`)
#   G  H5   `zeroTerminated` derives the sinks' `-0`, with the P3-F1 guard —
#           the four-state sequence of tgrep 004 §G
#
# The out-name refusals of `argv` itself are TUtil's and are pinned in
# `tutil/tests/001_Core.sh`; this file adds only the `__th_` half (H4b).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thead.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: THead — typed options to argv, nothing executed (P0)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# arr_is ARRNAME expected... — rc 0 iff the array holds exactly these elements
# in this order. Fork-free and byte-exact, so a glob, a space or a leading `-`
# in a word compares correctly.
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

# dbg_n COMMAND... -> DBG_RC / DBG_N / DBG_1, with the switch ON.
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

# check_argv TITLE INST WANT... — `INST.argv GOT` must answer rc 0 with
# RESULT = the word count and GOT holding exactly WANT.
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

# check_rc2 TITLE WANT_MSG_SUBSTR INST — `INST.argv GOT` must answer rc 2 with
# RESULT '', the caller's array untouched, `${inst}_argv` EMPTY, and EXACTLY ONE
# kk.debug line naming the reason (kcl README §1.2).
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

# reset INST — a fresh instance under the same name, so one case cannot leak
# into the next. `.new` over a LIVE instance does not clear `${inst}_data`, so
# this doubles as a standing check that `Create` assigns every var (§2.1).
reset() {
    THead.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

# THead's own six (PLAN §1.2) plus the five TUtil hands down.
TH_VARS=( lines bytes quiet verbose zeroTerminated _nulDerived )
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "every declared var is present in \`\${inst}_data\` right after \`new\` (§2.1)"
THead.new hA 2 f1
missing=""
decl="$(declare -p hA_data)"
for v in "${TH_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TH_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "the documented defaults: booleans 0, \`bytes\` '', cmd head, _lastRc -1, lines = N"
bad=""
for v in quiet verbose zeroTerminated _nulDerived crlf nul subshellOk; do
    got="$(hA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
[[ "$(hA.bytes)" == "" ]]    || bad+=" bytes='$(hA.bytes)'"
[[ "$(hA.cmd)" == "head" ]]  || bad+=" cmd='$(hA.cmd)'"
[[ "$(hA.lines)" == "2" ]]   || bad+=" lines='$(hA.lines)'"
[[ "$(hA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(hA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented; the constructor's N became \`lines\`"
else
    kt_test_fail "$bad"
fi

kt_test_start "\`THead.new h\` with no argument at all leaves \`lines\` '' (head's own default of 10)"
THead.new hD
if [[ "$(hD.lines)" == "" && "$(hD.bytes)" == "" && "$(hD.cmd)" == "head" ]]; then
    kt_test_pass "lines '', bytes '', cmd head"
else
    kt_test_fail "lines='$(hD.lines)' bytes='$(hD.bytes)' cmd='$(hD.cmd)'"
fi
hD.delete

kt_test_start "\`\${h}_args\` is EMPTY after \`THead.new h N PATH\` (the \`inherited\` trap, §2.1)"
# `inherited` in a constructor is rewritten to `parent.constructor "$@"`, which
# would have handed TUtil cmd=2 and args=(f1) — and every path would then be
# emitted twice. THead.Create calls `parent.constructor head` explicitly.
declare -n AA=hA_args
if (( ${#AA[@]} == 0 )); then
    kt_test_pass "args empty — the count and the paths did NOT leak into TUtil"
else
    kt_test_fail "hA_args=$(arr_show AA)"
fi
unset -n AA

kt_test_start "\`\${h}_paths\` holds the constructor's paths verbatim, once each"
THead.new hP 3 'a b' -dash.txt $'nl\nname'
declare -n PP=hP_paths
if arr_is PP 'a b' '-dash.txt' $'nl\nname'; then
    kt_test_pass "3 paths, no doubling: $(arr_show PP)"
else
    kt_test_fail "hP_paths=$(arr_show PP)"
fi
unset -n PP
hP.delete

kt_test_start "a REUSED instance name starts clean (every var re-assigned by Create)"
THead.new hR 1 x1
hR.quiet = 1
hR.bytes = 7
hR.zeroTerminated = 1
THead.new hR 4 x2                  # no delete in between — _data is NOT cleared
clean=1
[[ "$(hR.quiet)" == "0" ]]          || clean=0
[[ "$(hR.bytes)" == "" ]]           || clean=0
[[ "$(hR.zeroTerminated)" == "0" ]] || clean=0
[[ "$(hR.lines)" == "4" ]]          || clean=0
declare -n RP=hR_paths
arr_is RP x2 || clean=0
unset -n RP
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\`"
else
    kt_test_fail "quiet='$(hR.quiet)' bytes='$(hR.bytes)' z='$(hR.zeroTerminated)' lines='$(hR.lines)'"
fi

kt_test_start "\`delete\` removes \`_paths\`, \`_args\` AND \`_argv\` (the descendant destructor chains)"
declare -a W=()
hR.argv W >/dev/null 2>&1 || :
hR.delete
left=""
declare -p hR_paths >/dev/null 2>&1 && left+=" _paths"
declare -p hR_args  >/dev/null 2>&1 && left+=" _args"
declare -p hR_argv  >/dev/null 2>&1 && left+=" _argv"
declare -p hR_data  >/dev/null 2>&1 && left+=" _data"
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "\`argv\` RUNS NOTHING — not even a cmd that exists"
th_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
THead.new hN 2 f1
hN.cmd = th_mark
W=()
rc=0
hN.argv W || rc=$?             # DIRECT, not `$( )`: a subshell would lose the fill
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "5" ]] && arr_is W th_mark -n 2 -- f1; then
    kt_test_pass "the 5-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
hN.delete

# --- H4b: the `__th_` prefix is refused as an out-name (§2.8) ---------------
# THead's namerefs are `__th_*` and bash scopes locals DYNAMICALLY, so a caller
# array of that shape would bind this unit's own scratch. `tutil._badOut` is
# extended to `__tu_ __tg_ __th_ __tt_` in P0 and this is the thead half of the
# pin (the tutil half is `tutil/tests/001_Core.sh` §C).

# bad_out TITLE MEMBER NAME — rc 2, RESULT '', one line naming the out-name.
bad_out() {
    kt_test_start "$1"
    local __m="$2" __n="$3"
    RESULT="sentinel"
    dbg_n hA."$__m" "$__n"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 \
          && "$DBG_1" == *"bad output array name"* && "$DBG_1" == *"$__n"* ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1'"
    fi
}

bad_out "H4b: \`h.argv __th_v\` is rc 2 (the THead local prefix, §2.8)"    argv    __th_v
bad_out "H4b: \`h.argv __th_p\` is rc 2"                                   argv    __th_p
bad_out "H4b: \`h.toArray __th_a\` is rc 2 — refused BEFORE anything runs" toArray __th_a
bad_out "H4b: \`h.argv __tu_x\` is still rc 2 (TUtil's own prefix)"        argv    __tu_x
bad_out "H4b: \`h.argv __tg_x\` is still rc 2 (the tgrep prefix)"          argv    __tg_x
bad_out "H4b: \`h.argv __tt_x\` is rc 2 (the ttail prefix, §2.8)"          argv    __tt_x
bad_out "H4b: \`h.argv hA_paths\` is rc 2 (the instance's own operand array)" argv  hA_paths

# ===========================================================================
kt_test_section "B. H1 — every option, singly"
# ===========================================================================

# One instance, reset before each case, so a case can only show its own option.
one() {   # one TITLE PROP VALUE WANTWORD...
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset h1 '' f
    h1."$__p" = "$__v"
    check_argv "$__t" h1 head "$@" -- f
}

reset h1 '' f
check_argv "H1: no option at all — \`head -- PATH\` (head's own default of 10 lines)" h1 head -- f

one "H1: \`quiet = 1\` -> -q (never print the \`==> NAME <==\` headers)" quiet          1 -q
one "H1: \`verbose = 1\` -> -v (always print them)"                      verbose        1 -v
one "H1: \`zeroTerminated = 1\` -> -z (NUL-delimited INPUT records)"     zeroTerminated 1 -z
one "H1: \`lines = 3\` -> -n 3 as TWO words"                             lines          3 -n 3
one "H1: \`bytes = 3\` -> -c 3 as TWO words"                             bytes          3 -c 3

# ===========================================================================
kt_test_section "C. H1 — combinations, the pinned order, and the boolean rule"
# ===========================================================================

reset h2 5 f
h2.quiet = 1
check_argv "H1: -q before -n, the pinned order" h2 head -q -n 5 -- f

reset h2 '' f
h2.lines = 5
h2.quiet = 1
check_argv "H1: the ORDER is buildArgv's, not the order the caller assigned in" h2 \
    head -q -n 5 -- f

reset h2 '' f
h2.quiet = 1
h2.zeroTerminated = 1
h2.bytes = 12
check_argv "H1: -q -z -c 12 — one path, so \`-z\` is allowed (§2.3)" h2 \
    head -q -z -c 12 -- f

reset h2 '' 'dir one' 'dir two'
h2.verbose = 1
h2.lines = -2
check_argv "H1: -v with two paths and a negative count" h2 \
    head -v -n -2 -- 'dir one' 'dir two'

reset h2 7 f
h2.quiet = 1
h2.zeroTerminated = 1
h2.addArg --extra
check_argv "H1: EVERYTHING compatible at once — the full pinned order" h2 \
    head -q -z -n 7 --extra -- f

kt_test_start "H1: a boolean is ON only for the exact string \`1\` (never \`(( x ))\`)"
allgood=1
badv=""
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset h3 '' f
    h3.quiet = "$v"
    GOT=()
    h3.argv GOT >/dev/null 2>&1 || :
    if ! arr_is GOT head -- f; then
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

reset h4 2
check_argv "H1: \`THead.new h N\` with no path is the STDIN form — no \`--\` at all" h4 head -n 2

reset h4 2 'a b'
check_argv "H1: one path -> \`-- 'a b'\` (a space is safe by construction)" h4 \
    head -n 2 -- 'a b'

reset h4 2 a b c
check_argv "H1: three paths, all after the one \`--\`" h4 head -n 2 -- a b c

reset h4 2 -weird.txt
check_argv "H1: a path that starts with \`-\` is an operand, not a flag" h4 \
    head -n 2 -- -weird.txt

reset h4 2 f
h4.addArg --zero-terminated
check_argv "H1: an \`addArg\` extra lands AFTER the options and BEFORE \`--\`" h4 \
    head -n 2 --zero-terminated -- f

reset h4 '' f
h4.lines = 3
h4.addArg -n 5
check_argv "H1: \`addArg -n 5\` after \`lines = 3\` yields BOTH — head is last-flag-wins (§1.3)" h4 \
    head -n 3 -n 5 -- f

reset h4 2 f
h4.addArg -q
h4.addArg -c 4
check_argv "H1: several extras keep their order, still between the options and \`--\`" h4 \
    head -n 2 -q -c 4 -- f

reset h4 2 f
h4.addArg -q
h4.clearArgs
check_argv "H1: \`clearArgs\` empties the extras again" h4 head -n 2 -- f

reset h4 2 old1 old2
h4.paths new1 'new 2'
check_argv "H1: \`h.paths new1 'new 2'\` replaced both old paths" h4 \
    head -n 2 -- new1 'new 2'

reset h4 2 old1
h4.paths
check_argv "H1: \`h.paths\` with no argument is the stdin form" h4 head -n 2

kt_test_start "H1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset h4 2 f
h4.quiet = 1
declare -a W1=() W2=()
h4.argv W1 >/dev/null 2>&1 || :
h4.argv W2 >/dev/null 2>&1 || :
if arr_is W1 head -q -n 2 -- f && arr_is W2 head -q -n 2 -- f; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "H1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
h4.argv W3 >/dev/null 2>&1 || :
W3[1]="TAMPERED"
declare -n IV=h4_argv
if [[ "${IV[1]:-}" == "-q" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "h4_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "E. H2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset hE 2 f
hE.cmd = ''
check_rc2 "H2: empty \`cmd\` is rc 2" "cmd is empty" hE

reset hE 2 f
hE.bytes = 3
check_rc2 "H2: \`lines\` + \`bytes\` (-n and -c) is rc 2" "lines" hE

reset hE '' f
hE.quiet = 1
hE.verbose = 1
check_rc2 "H2: \`quiet\` + \`verbose\` (-q and -v) is rc 2" "quiet" hE

reset hE '' a b
hE.zeroTerminated = 1
check_rc2 "H2: \`zeroTerminated\` with TWO paths is rc 2 (the headers stay \\n-framed, §2.3)" \
    "zeroTerminated" hE

reset hE '' f
hE.zeroTerminated = 1
hE.verbose = 1
check_rc2 "H2: \`zeroTerminated\` + \`verbose\` is rc 2 (a forced header would frame wrong)" \
    "zeroTerminated" hE

reset hE x f
check_rc2 "H2: \`lines = x\` is rc 2 (the count regex \`^[+-]?[0-9]+\$\`)" "lines" hE

reset hE 1K f
check_rc2 "H2: \`lines = 1K\` is rc 2 — the suffix hatch is \`addArg -n 1K\` (§1.3)" "lines" hE

reset hE '1 2' f
check_rc2 "H2: \`lines = '1 2'\` is rc 2 (never re-split into two words)" "lines" hE

reset hE '' f
hE.lines = '--5'
check_rc2 "H2: \`lines = '--5'\` is rc 2 (one optional sign only)" "lines" hE

reset hE 99999999999999999999 f
check_rc2 "H2: a 20-digit \`lines\` is rc 2 — the magnitude guard, before the tool sees it" \
    "lines" hE

reset hE '' f
hE.bytes = abc
check_rc2 "H2: \`bytes = abc\` is rc 2 (the same regex)" "bytes" hE

reset hE '' f
hE.bytes = 99999999999999999999
check_rc2 "H2: a 20-digit \`bytes\` is rc 2" "bytes" hE

reset hE '' f
hE.lines = ' 2'
check_rc2 "H2: \`lines = ' 2'\` is rc 2 (no surrounding blanks)" "lines" hE

kt_test_start "H2: each half of a refused pair on its OWN is fine"
ok=1
reset hE '' f; hE.lines = 3;          hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '' f; hE.bytes = 3;          hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '' f; hE.quiet = 1;          hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '' f; hE.verbose = 1;        hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '' f; hE.zeroTerminated = 1; hE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "only the COMBINATION is refused"
else
    kt_test_fail "a single option was refused"
fi

kt_test_start "H2: \`zeroTerminated\` with ONE path (and with none) is accepted"
ok=1
reset hE '' f;  hE.zeroTerminated = 1; hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '';    hE.zeroTerminated = 1; hE.argv GOT >/dev/null 2>&1 || ok=0
reset hE '' f;  hE.zeroTerminated = 1; hE.quiet = 1; hE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "one path, stdin, and \`-q\` all build"
else
    kt_test_fail "a legal \`-z\` shape was refused"
fi

# ===========================================================================
kt_test_section "F. H3 — the count travels VERBATIM (no \`kk.isInt\`, §2.2)"
# ===========================================================================

# `kk.isInt` normalises: it would hand head `3` for `+3` and `0` for `-0`, and
# head reads those as entirely different requests (§2.2's sign table). The
# wrapper therefore validates with a regex and passes the string through.
verbatim() {   # verbatim PROP VALUE FLAG
    local __p="$1" __v="$2" __f="$3"
    reset hF '' f
    hF."$__p" = "$__v"
    check_argv "H3: \`$__p = $__v\` reaches head as \`$__f $__v\`, unchanged" hF \
        head "$__f" "$__v" -- f
}

verbatim lines 08  -n
verbatim lines +3  -n
verbatim lines -2  -n
verbatim lines -0  -n
verbatim lines +0  -n
verbatim lines 0   -n
verbatim bytes 08  -c
verbatim bytes +3  -c
verbatim bytes -2  -c
verbatim bytes -0  -c

kt_test_start "H3: a 19-digit count PASSES the guard and reaches head verbatim"
reset hF '' f
hF.lines = 9999999999999999999
GOT=()
rc=0
hF.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT head -n 9999999999999999999 -- f; then
    kt_test_pass "19 digits is the int64 bound the guard allows; 20 is rc 2 (§E)"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "H3: a 19-digit count with a SIGN passes too (the sign is not a digit)"
reset hF '' f
hF.bytes = -9999999999999999999
GOT=()
rc=0
hF.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT head -c -9999999999999999999 -- f; then
    kt_test_pass "\`-c -19digits\` built; the tool's own 'Value too large' is an rc 1 (005)"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "H3: the property still READS what the caller wrote (no write-back)"
reset hF '' f
hF.lines = 08
hF.argv GOT >/dev/null 2>&1 || :
a="$(hF.lines)"
reset hF '' f
hF.lines = -0
hF.argv GOT >/dev/null 2>&1 || :
b="$(hF.lines)"
if [[ "$a" == "08" && "$b" == "-0" ]]; then
    kt_test_pass "'08' and '-0' survive a build (kk.isInt would have written 8 and 0)"
else
    kt_test_fail "after 08: '$a'; after -0: '$b'"
fi

# ===========================================================================
kt_test_section "G. H5 — \`zeroTerminated\` derives the sinks' \`-0\` (§2.3, P3-F1)"
# ===========================================================================

kt_test_start "H5: \`zeroTerminated = 1\` with one path DERIVES \`nul = 1\`"
reset hZ 2 f
hZ.zeroTerminated = 1
GOT=()
rc=0
hZ.argv GOT || rc=$?
if [[ $rc -eq 0 && "$(hZ.nul)" == "1" && "$(hZ._nulDerived)" == "1" ]] \
   && arr_is GOT head -z -n 2 -- f; then
    kt_test_pass "nul = 1, _nulDerived = 1, argv has -z"
else
    kt_test_fail "rc=$rc nul='$(hZ.nul)' drv='$(hZ._nulDerived)' GOT=$(arr_show GOT)"
fi

kt_test_start "H5: \`zeroTerminated = 0\` again takes the derived \`-0\` back off"
hZ.zeroTerminated = 0
hZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(hZ.nul)" == "0" && "$(hZ._nulDerived)" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding (the \`_nulDerived\` bookkeeping)"
else
    kt_test_fail "nul='$(hZ.nul)' drv='$(hZ._nulDerived)'"
fi

kt_test_start "H5: a MANUAL \`nul = 1\` with \`zeroTerminated = 0\` is the caller's and survives"
reset hZ 2 f
hZ.nul = 1
hZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(hZ.nul)" == "1" && "$(hZ._nulDerived)" == "0" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(hZ.nul)' drv='$(hZ._nulDerived)'"
fi

# P3-F1. The undo used to be one condition too coarse: `_nulDerived` was claimed
# whenever the derivation CONDITION held, even when `nul` was already 1 because
# the CALLER set it — so the next build that stopped deriving took the caller's
# own `nul` down to 0 with it. The guard is "claim it only if we really set it",
# and this is the four-state sequence that needs all of it.
kt_test_start "H5 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset hZ 2 f
hZ.nul = 1                      # the caller's own framing decision
hZ.zeroTerminated = 1
hZ.argv GOT >/dev/null 2>&1 || :
mid="$(hZ.nul)" middrv="$(hZ._nulDerived)"
hZ.zeroTerminated = 0
hZ.argv GOT >/dev/null 2>&1 || :
end="$(hZ.nul)" enddrv="$(hZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through -z and back; _nulDerived never claimed it"
else
    kt_test_fail "after -z: nul='$mid' drv='$middrv'; after zeroTerminated=0: nul='$end' drv='$enddrv'"
fi

kt_test_start "H5: a REFUSED build derives nothing (\`-z\` with two paths never reaches the rule)"
reset hZ 2 a b
hZ.zeroTerminated = 1
hZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(hZ.nul)" == "0" && "$(hZ._nulDerived)" == "0" ]]; then
    kt_test_pass "nul untouched on the rc 2 path"
else
    kt_test_fail "nul='$(hZ.nul)' drv='$(hZ._nulDerived)'"
fi

kt_test_start "H5: \`crlf\` is never touched by buildArgv"
reset hZ 2 f
hZ.crlf = 1
hZ.zeroTerminated = 1
hZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(hZ.crlf)" == "1" ]]; then
    kt_test_pass "crlf = 1 kept"
else
    kt_test_fail "crlf='$(hZ.crlf)'"
fi

hA.delete
h1.delete
h2.delete
h3.delete
h4.delete
hE.delete
hF.delete
hZ.delete
