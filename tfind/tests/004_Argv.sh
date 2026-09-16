#!/bin/bash
# 004_Argv.sh — tfind P0: the argv model (tfind/PLAN.md §1.2, §2.1–§2.3, §2.6;
# pinned facts F1–F5, F5b).
#
# THIS FILE NEVER RUNS find. Every option is pinned by comparing the ARRAY that
# `f.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   find [-L] [START...] [-maxdepth N] [-mindepth N] [-name P] [-iname P]
#        [-type T] [-newer F] [EXTRA ARGS from addArg] [-print0]
#
# so it is the fast half of the suite and it is true on a box where findutils is
# missing altogether. The behavioural half is `005_Run.sh`.
#
# Sections:
#   A       lifecycle (F4) — every declared var present in `${inst}_data` right
#           after `new` with its documented default, `${f}_args` EMPTY after
#           `TFind.new f START` (the `inherited`-in-a-constructor trap),
#           `${f}_paths` filled, a reused instance name starting clean, `delete`
#           removing `_paths` / `_args` / `_argv`, `argv` running nothing, and
#           the out-name registry: `__tfd_*` refused, `TUTIL_OUT_PREFIXES`
#           refused as a NAME with the registry intact afterwards, the four
#           older family prefixes still refused (§2.6)
#   B  F1   every option SINGLY
#   C  F1   options in combination, in the pinned order; a non-`1` value is OFF
#   D  F1   start points are POSITIONAL and come first; no `--` is ever emitted;
#           extras land between the typed tests and the action; `paths` replaces
#           the list and `paths` with no argument is find's own `.`
#   E  F2   the rc 2 list: empty `cmd`, an empty start point, a start point
#           matching `^[-!(]`, a bad `type`, a non-int or negative depth, and
#           `print0 = 1` together with EVERY action word of §2.3 — rc 2,
#           RESULT '', the caller's array UNTOUCHED, `${inst}_argv` EMPTY, one
#           `kk.debug` line
#   F  F3   the depths are emitted from `$__KK_INT`: `08` -> 8, `+1` -> 1, with
#           no write-back onto the property; `type = f,f` passes the regex (it
#           is the TOOL's rc 1 — parity, 005)
#   G  F5   `print0` derives the sinks' `-0`, with the P3-F1 guard — the
#           four-state sequence of tgrep 004 §G
#   H  F5b  the caller-side glob trap: `f.name = *.txt` unquoted in a directory
#           with two `.txt` files keeps ONE word, silently
#
# The out-name refusals of `argv` itself are TUtil's and are pinned in
# `tutil/tests/001_Core.sh`; this file adds the `__tfd_` and registry halves.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tfind.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: TFind — typed options to argv, nothing executed (P0)"

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

# reset INST START... — a fresh instance under the same name, so one case cannot
# leak into the next. `.new` over a LIVE instance does not clear `${inst}_data`,
# so this doubles as a standing check that `Create` assigns every var.
reset() {
    TFind.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. F4 lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

# TFind's own nine (PLAN §1.2) plus the five TUtil hands down.
TF_VARS=( name iname type maxDepth minDepth newer followSymlinks print0 _nulDerived )
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "F4: every declared var is present in \`\${inst}_data\` right after \`new\`"
TFind.new fA /tmp/tree
missing=""
decl="$(declare -p fA_data)"
for v in "${TF_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TF_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "F4: the documented defaults — strings '', booleans 0, cmd find, _lastRc -1"
bad=""
for v in name iname type maxDepth minDepth newer; do
    got="$(fA."$v")"
    [[ "$got" == "" ]] || bad+=" $v='$got'"
done
for v in followSymlinks print0 _nulDerived crlf nul subshellOk; do
    got="$(fA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
[[ "$(fA.cmd)" == "find" ]]   || bad+=" cmd='$(fA.cmd)'"
[[ "$(fA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(fA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented; cmd is \`find\`"
else
    kt_test_fail "$bad"
fi

kt_test_start "F4: \`\${f}_args\` is EMPTY after \`TFind.new f START\` (the \`inherited\` trap)"
# `inherited` in a constructor is rewritten to `parent.constructor "$@"`, which
# would have handed TUtil cmd=/tmp/tree — and every start point would then be
# emitted twice. TFind.Create calls `parent.constructor find` explicitly.
declare -n AA=fA_args
if (( ${#AA[@]} == 0 )); then
    kt_test_pass "args empty — the start points did NOT leak into TUtil"
else
    kt_test_fail "fA_args=$(arr_show AA)"
fi
unset -n AA

kt_test_start "F4: \`\${f}_paths\` holds EVERY constructor argument verbatim, once each"
TFind.new fP 'a b' './-weird' $'nl\nname' ')paren'
declare -n PP=fP_paths
if arr_is PP 'a b' './-weird' $'nl\nname' ')paren'; then
    kt_test_pass "4 start points, no doubling: $(arr_show PP)"
else
    kt_test_fail "fP_paths=$(arr_show PP)"
fi
unset -n PP
fP.delete

kt_test_start "F4: \`TFind.new f\` with NO argument leaves the start-point list empty (find's own \`.\`)"
TFind.new fD
declare -n DP=fD_paths
if (( ${#DP[@]} == 0 )) && [[ "$(fD.cmd)" == "find" ]]; then
    kt_test_pass "no start point, cmd find"
else
    kt_test_fail "fD_paths=$(arr_show DP) cmd='$(fD.cmd)'"
fi
unset -n DP
fD.delete

kt_test_start "F4: a REUSED instance name starts clean (every var re-assigned by Create)"
TFind.new fR x1
fR.name = 'old*'
fR.type = f
fR.maxDepth = 3
fR.print0 = 1
TFind.new fR x2                    # no delete in between — _data is NOT cleared
clean=1
[[ "$(fR.name)" == "" ]]     || clean=0
[[ "$(fR.type)" == "" ]]     || clean=0
[[ "$(fR.maxDepth)" == "" ]] || clean=0
[[ "$(fR.print0)" == "0" ]]  || clean=0
declare -n RP=fR_paths
arr_is RP x2 || clean=0
unset -n RP
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\`"
else
    kt_test_fail "name='$(fR.name)' type='$(fR.type)' maxDepth='$(fR.maxDepth)' print0='$(fR.print0)'"
fi

kt_test_start "F4: \`delete\` removes \`_paths\`, \`_args\` AND \`_argv\` (the descendant destructor chains)"
declare -a W=()
fR.argv W >/dev/null 2>&1 || :
fR.delete
left=""
declare -p fR_paths >/dev/null 2>&1 && left+=" _paths"
declare -p fR_args  >/dev/null 2>&1 && left+=" _args"
declare -p fR_argv  >/dev/null 2>&1 && left+=" _argv"
declare -p fR_data  >/dev/null 2>&1 && left+=" _data"
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "F4: \`argv\` RUNS NOTHING — not even a cmd that exists"
tfd_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
TFind.new fN tree
fN.cmd = tfd_mark
fN.name = '*.txt'
W=()
rc=0
fN.argv W || rc=$?             # DIRECT, not `$( )`: a subshell would lose the fill
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "4" ]] && arr_is W tfd_mark tree -name '*.txt'; then
    kt_test_pass "the 4-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
fN.delete

# --- F4: the TUTIL_OUT_PREFIXES registry (§2.6) ----------------------------
# TFind's namerefs are `__tfd_*` and bash scopes locals DYNAMICALLY, so a caller
# array of that shape would bind this unit's own scratch. P0 turns the
# hard-coded prefix list of `tutil._badOut` into the `TUTIL_OUT_PREFIXES`
# registry that this unit appends to at load; the tutil half is
# `tutil/tests/001_Core.sh` §C.

# bad_out TITLE MEMBER NAME — rc 2, RESULT '', one line naming the out-name.
bad_out() {
    kt_test_start "$1"
    local __m="$2" __n="$3"
    RESULT="sentinel"
    dbg_n fA."$__m" "$__n"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 \
          && "$DBG_1" == *"bad output array name"* && "$DBG_1" == *"$__n"* ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1'"
    fi
}

bad_out "F4: \`f.argv __tfd_v\` is rc 2 (the TFind local prefix, §2.6)"      argv    __tfd_v
bad_out "F4: \`f.argv __tfd_p\` is rc 2"                                     argv    __tfd_p
bad_out "F4: \`f.toArray __tfd_a\` is rc 2 — refused BEFORE anything runs"   toArray __tfd_a
bad_out "F4: \`f.argv __tu_x\` is still rc 2 (TUtil's own prefix)"           argv    __tu_x
bad_out "F4: \`f.argv __tg_x\` is still rc 2 (the tgrep prefix)"             argv    __tg_x
bad_out "F4: \`f.argv __th_x\` is still rc 2 (the thead prefix)"             argv    __th_x
bad_out "F4: \`f.argv __tt_x\` is still rc 2 (the ttail prefix)"             argv    __tt_x
bad_out "F4: \`f.argv fA_paths\` is rc 2 (the instance's own start-point array)" argv fA_paths
bad_out "F4: \`f.argv TUTIL_OUT_PREFIXES\` is rc 2 (the registry's own NAME, §2.6)" \
                                                                             argv    TUTIL_OUT_PREFIXES

kt_test_start "F4: the registry SURVIVED the refusal and still holds five prefixes (§2.6 guard 1)"
# Without the reserved-name case one `f.argv TUTIL_OUT_PREFIXES` replaced the
# registry with the argv, and every `__tu_`/`__tg_`/… name became fillable
# process-wide.
reg_ok=1
declare -a REG_SEEN=( "${TUTIL_OUT_PREFIXES[@]}" )
(( ${#REG_SEEN[@]} == 5 )) || reg_ok=0
for p in __tu_ __tg_ __th_ __tt_ __tfd_; do
    found=0
    for q in "${REG_SEEN[@]}"; do
        [[ "$q" == "$p" ]] && found=1
    done
    [[ "$found" == "1" ]] || reg_ok=0
done
if [[ "$reg_ok" == "1" ]]; then
    kt_test_pass "TUTIL_OUT_PREFIXES = $(arr_show REG_SEEN)"
else
    kt_test_fail "registry = $(arr_show REG_SEEN)"
fi

kt_test_start "F4: sourcing tfind twice does NOT append \`__tfd_\` twice (idempotent, §2.6)"
source "$UNIT"
source "$UNIT"
declare -a REG2=( "${TUTIL_OUT_PREFIXES[@]}" )
n_tfd=0
for q in "${REG2[@]}"; do
    [[ "$q" == "__tfd_" ]] && n_tfd=$(( n_tfd + 1 ))
done
if [[ "$n_tfd" == "1" && ${#REG2[@]} -eq 5 ]]; then
    kt_test_pass "one \`__tfd_\` entry, five in all"
else
    kt_test_fail "__tfd_ appears $n_tfd time(s); registry = $(arr_show REG2)"
fi

kt_test_start "F4: an ordinary out-name still fills after every refusal"
declare -a OKARR=()
rc=0
fA.argv OKARR || rc=$?
if [[ $rc -eq 0 ]] && arr_is OKARR find /tmp/tree; then
    kt_test_pass "argv=(find /tmp/tree)"
else
    kt_test_fail "rc=$rc OKARR=$(arr_show OKARR)"
fi

# ===========================================================================
kt_test_section "B. F1 — every option, singly"
# ===========================================================================

# One instance, reset before each case, so a case can only show its own option.
one() {   # one TITLE PROP VALUE WANTWORD...
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset f1 tree
    f1."$__p" = "$__v"
    check_argv "$__t" f1 find tree "$@"
}

reset f1 tree
check_argv "F1: no option at all — \`find START\` (the implied \`-print\`)" f1 find tree

one "F1: \`name = '*.txt'\` -> -name '*.txt' as TWO words"   name     '*.txt'  -name '*.txt'
one "F1: \`iname = '*.TXT'\` -> -iname"                      iname    '*.TXT'  -iname '*.TXT'
one "F1: \`type = f\` -> -type f"                            type     f        -type f
one "F1: \`type = f,d\` -> -type f,d (a comma list is ONE word)" type  f,d      -type f,d
one "F1: \`maxDepth = 2\` -> -maxdepth 2"                    maxDepth 2        -maxdepth 2
one "F1: \`minDepth = 1\` -> -mindepth 1"                    minDepth 1        -mindepth 1
one "F1: \`newer = ref\` -> -newer ref"                      newer    ref      -newer ref
one "F1: \`print0 = 1\` -> -print0 as THE action, last"      print0   1        -print0

reset f1 tree
f1.followSymlinks = 1
check_argv "F1: \`followSymlinks = 1\` puts \`-L\` BEFORE the start points (§6)" f1 find -L tree

kt_test_start "F1: a pattern is ONE argv element — a glob, a space and a \`[\` all survive"
reset f1 tree
f1.name = '* ?[a-z].txt'
GOT=()
rc=0
f1.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -name '* ?[a-z].txt'; then
    kt_test_pass "the pattern was never expanded or re-split by the wrapper"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

# ===========================================================================
kt_test_section "C. F1 — combinations, the pinned order, and the boolean rule"
# ===========================================================================

reset f2 tree
f2.name = '*.c'
f2.maxDepth = 3
check_argv "F1: the global option comes BEFORE the test, whatever the caller's order" f2 \
    find tree -maxdepth 3 -name '*.c'

reset f2 tree
f2.type = f
f2.iname = 'A*'
f2.minDepth = 1
f2.maxDepth = 4
check_argv "F1: -maxdepth before -mindepth before -name/-iname before -type" f2 \
    find tree -maxdepth 4 -mindepth 1 -iname 'A*' -type f

reset f2 'dir one' 'dir two'
f2.followSymlinks = 1
f2.name = 'x y'
f2.type = d
f2.newer = 'ref file'
f2.maxDepth = 9
f2.minDepth = 0
f2.print0 = 1
check_argv "F1: EVERYTHING at once — the full pinned order, two start points" f2 \
    find -L 'dir one' 'dir two' -maxdepth 9 -mindepth 0 -name 'x y' -type d \
    -newer 'ref file' -print0

kt_test_start "F1: a boolean is ON only for the exact string \`1\` (never \`(( x ))\`)"
allgood=1
badv=""
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset f3 tree
    f3.followSymlinks = "$v"
    f3.print0 = "$v"
    GOT=()
    f3.argv GOT >/dev/null 2>&1 || :
    if ! arr_is GOT find tree; then
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
kt_test_section "D. F1 — start points are POSITIONAL; no \`--\`; extras in place"
# ===========================================================================

reset f4
check_argv "F1: NO start point at all — bare \`find\` (find's own \`.\`, §2.1)" f4 find

reset f4
f4.name = 'x*'
f4.maxDepth = 1
check_argv "F1: no start point but an expression — the tool accepts it (§1.1)" f4 \
    find -maxdepth 1 -name 'x*'

reset f4 a b c
check_argv "F1: three start points, all BEFORE the expression, no \`--\`" f4 find a b c

reset f4 './-weird'
check_argv "F1: \`./-weird\` is a legal start point (the \`./\` is what saves it)" f4 \
    find './-weird'

reset f4 ')paren' ',comma'
check_argv "F1: \`)\` and \`,\` are fine as start points — only \`-\`, \`!\` and \`(\` are refused" f4 \
    find ')paren' ',comma'

reset f4 'C:\Users\x\tree'
check_argv "F1: a Windows-spelled start point travels verbatim" f4 find 'C:\Users\x\tree'

reset f4 tree
f4.addArg -size +1M
check_argv "F1: an \`addArg\` extra lands AFTER the typed tests" f4 find tree -size +1M

reset f4 tree
f4.type = f
f4.maxDepth = 2
f4.addArg '!' -name '*.o'
f4.print0 = 1
check_argv "F1: extras sit between the typed tests and the action (\`-print0\` stays last)" f4 \
    find tree -maxdepth 2 -type f '!' -name '*.o' -print0

reset f4 tree
f4.addArg '(' -name a -o -name b ')'
check_argv "F1: a parenthesised group through \`addArg\` keeps its words" f4 \
    find tree '(' -name a -o -name b ')'

reset f4 tree
f4.addArg -size +1M
f4.clearArgs
check_argv "F1: \`clearArgs\` empties the extras again" f4 find tree

reset f4 old1 old2
f4.paths new1 'new 2'
check_argv "F1: \`f.paths new1 'new 2'\` replaced both old start points" f4 \
    find new1 'new 2'

reset f4 old1
f4.paths
check_argv "F1: \`f.paths\` with NO argument is the empty list = find's own \`.\`" f4 find

kt_test_start "F1: \`--\` is NEVER emitted, in any shape (§1.1 — it cannot rescue a start point)"
dashdash=""
for shape in 1 2 3; do
    reset f5 tree 'a b'
    case "$shape" in
        1) : ;;
        2) f5.name = '*.txt'; f5.type = f; f5.maxDepth = 1 ;;
        3) f5.print0 = 1; f5.addArg -size +0; f5.followSymlinks = 1 ;;
    esac
    GOT=()
    f5.argv GOT >/dev/null 2>&1 || :
    for w in "${GOT[@]}"; do
        [[ "$w" == "--" ]] && dashdash+=" shape$shape"
    done
done
if [[ -z "$dashdash" ]]; then
    kt_test_pass "no \`--\` in any of the three shapes"
else
    kt_test_fail "\`--\` emitted in:$dashdash"
fi

kt_test_start "F1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset f4 tree
f4.type = f
declare -a W1=() W2=()
f4.argv W1 >/dev/null 2>&1 || :
f4.argv W2 >/dev/null 2>&1 || :
if arr_is W1 find tree -type f && arr_is W2 find tree -type f; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "F1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
f4.argv W3 >/dev/null 2>&1 || :
W3[1]="TAMPERED"
declare -n IV=f4_argv
if [[ "${IV[1]:-}" == "tree" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "f4_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "E. F2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset fE tree
fE.cmd = ''
check_rc2 "F2: empty \`cmd\` is rc 2" "cmd is empty" fE

reset fE ''
check_rc2 "F2: an EMPTY start point is rc 2 (the tool's own \`'': No such file\`, §2.1)" \
    "start point" fE

reset fE good ''
check_rc2 "F2: an empty start point among GOOD ones is rc 2 too" "start point" fE

reset fE '-weird'
check_rc2 "F2: a start point beginning with \`-\` is rc 2 (find reads it as a predicate)" \
    "start point" fE

reset fE '-'
check_rc2 "F2: a start point of exactly \`-\` is rc 2 (it is NOT stdin for find)" \
    "start point" fE

reset fE '!bang'
check_rc2 "F2: a start point beginning with \`!\` is rc 2" "start point" fE

reset fE '(paren'
check_rc2 "F2: a start point beginning with \`(\` is rc 2" "start point" fE

reset fE good '-weird'
check_rc2 "F2: a refused start point ANYWHERE in the list is rc 2" "start point" fE

reset fE tree
fE.type = x
check_rc2 "F2: \`type = x\` is rc 2 (the regex \`^[bcdflps](,[bcdflps])*\$\`)" "type" fE

reset fE tree
fE.type = D
check_rc2 "F2: \`type = D\` is rc 2 (uppercase is not in the class)" "type" fE

reset fE tree
fE.type = 'f,'
check_rc2 "F2: \`type = 'f,'\` is rc 2 (a trailing comma)" "type" fE

reset fE tree
fE.type = ',f'
check_rc2 "F2: \`type = ',f'\` is rc 2 (a leading comma)" "type" fE

reset fE tree
fE.type = 'fd'
check_rc2 "F2: \`type = fd\` is rc 2 (a list is comma separated, not concatenated)" "type" fE

reset fE tree
fE.type = 'f d'
check_rc2 "F2: \`type = 'f d'\` is rc 2 (never re-split into two words)" "type" fE

reset fE tree
fE.maxDepth = x
check_rc2 "F2: \`maxDepth = x\` is rc 2 (\`kk.isInt\`)" "maxDepth" fE

reset fE tree
fE.maxDepth = -1
check_rc2 "F2: \`maxDepth = -1\` is rc 2 (negative)" "maxDepth" fE

reset fE tree
fE.maxDepth = 1.5
check_rc2 "F2: \`maxDepth = 1.5\` is rc 2" "maxDepth" fE

reset fE tree
fE.maxDepth = ' 2'
check_rc2 "F2: \`maxDepth = ' 2'\` is rc 2 (no surrounding blanks)" "maxDepth" fE

reset fE tree
fE.minDepth = x
check_rc2 "F2: \`minDepth = x\` is rc 2" "minDepth" fE

reset fE tree
fE.minDepth = -2
check_rc2 "F2: \`minDepth = -2\` is rc 2 (negative)" "minDepth" fE

# §2.3: two actions interleave into one corrupted NUL record, and an `-exec`
# that exits non-zero short-circuits the AND chain so `-print0` never fires —
# rc 0, zero records, no diagnostic. Every word of the action set is refused.
for aw in -print -print0 -printf -fprint -fprint0 -fprintf -ls -fls -exec -execdir -ok -okdir -delete -quit; do
    reset fE tree
    fE.print0 = 1
    fE.addArg "$aw"
    check_rc2 "F2: \`print0 = 1\` with the action extra \`$aw\` is rc 2 (§2.3)" "print0" fE
done

kt_test_start "F2: \`print0 = 1\` with an action word NOT first among the extras is refused too"
reset fE tree
fE.print0 = 1
fE.addArg -size +0
fE.addArg -exec false '{}' ';'
GOT=( stale-1 stale-2 )
RESULT="sentinel"
dbg_n fE.argv GOT
declare -n EV=fE_argv
if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"print0"* ]] \
   && arr_is GOT stale-1 stale-2 && (( ${#EV[@]} == 0 )); then
    kt_test_pass "the whole extras list is scanned: ${DBG_1:0:60}"
else
    kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' instArgv=$(arr_show EV)"
fi
unset -n EV

kt_test_start "F2: \`print0 = 0\` with the SAME action extra builds fine (§1.3 item 3)"
reset fE tree
fE.addArg -exec printf 'X:%s\n' '{}' ';'
GOT=()
rc=0
fE.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -exec printf 'X:%s\n' '{}' ';'; then
    kt_test_pass "the extra's output IS the record stream when print0 is off"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "F2: \`print0 = 1\` with a NON-action extra builds fine"
reset fE tree
fE.print0 = 1
fE.addArg -size +0
GOT=()
rc=0
fE.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -size +0 -print0; then
    kt_test_pass "\`-size +0\` is a test, not an action"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "F2: an extra that merely CONTAINS an action word is NOT refused (whole-word match)"
reset fE tree
fE.print0 = 1
fE.addArg -execute
fE.addArg -printx
GOT=()
rc=0
fE.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -execute -printx -print0; then
    kt_test_pass "the match is on the WHOLE word, not a substring"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

# `addArg -name '-exec'` puts the literal word `-exec` in the extras. The
# wrapper does not parse find's expression grammar — it scans the words — so
# this shape is refused with `print0 = 1`. Documented over-refusal, and the
# escape hatch is `print0 = 0` plus a manual `nul`.
reset fE tree
fE.print0 = 1
fE.addArg -name '-exec'
check_rc2 "F2: \`print0 = 1\` + \`addArg -name '-exec'\` is rc 2 (the word scan, documented)" \
    "print0" fE

kt_test_start "F2: each refused ingredient on its OWN is fine"
ok=1
reset fE tree; fE.type = f;            fE.argv GOT >/dev/null 2>&1 || ok=0
reset fE tree; fE.maxDepth = 0;        fE.argv GOT >/dev/null 2>&1 || ok=0
reset fE tree; fE.minDepth = 0;        fE.argv GOT >/dev/null 2>&1 || ok=0
reset fE tree; fE.print0 = 1;          fE.argv GOT >/dev/null 2>&1 || ok=0
reset fE tree; fE.addArg -delete;      fE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "only the COMBINATION (and the malformed values) are refused"
else
    kt_test_fail "a legal single option was refused"
fi

# ===========================================================================
kt_test_section "F. F3 — the depths are emitted from \`\$__KK_INT\` (§2.2)"
# ===========================================================================

# `-maxdepth +1` is the TOOL's rc 1 ("Expected a positive decimal integer …
# got '+1'"), so the wrapper must emit the NORMALISED value, never the property
# verbatim. This is the opposite decision from thead/ttail, where the sign is
# meaning and `kk.isInt` is forbidden.
norm() {   # norm PROP VALUE FLAG WANT
    local __p="$1" __v="$2" __f="$3" __w="$4"
    reset fF tree
    fF."$__p" = "$__v"
    check_argv "F3: \`$__p = $__v\` reaches find as \`$__f $__w\` (\$__KK_INT)" fF \
        find tree "$__f" "$__w"
}

norm maxDepth 08   -maxdepth 8
norm maxDepth +1   -maxdepth 1
norm maxDepth 0    -maxdepth 0
norm maxDepth -0   -maxdepth 0
norm maxDepth 007  -maxdepth 7
norm minDepth 08   -mindepth 8
norm minDepth +2   -mindepth 2
norm minDepth 0    -mindepth 0

kt_test_start "F3: the property still READS what the caller wrote (no write-back)"
reset fF tree
fF.maxDepth = 08
fF.argv GOT >/dev/null 2>&1 || :
a="$(fF.maxDepth)"
reset fF tree
fF.minDepth = +2
fF.argv GOT >/dev/null 2>&1 || :
b="$(fF.minDepth)"
if [[ "$a" == "08" && "$b" == "+2" ]]; then
    kt_test_pass "'08' and '+2' survive a build on the instance; only the ARGV is normalised"
else
    kt_test_fail "after 08: '$a'; after +2: '$b'"
fi

kt_test_start "F3: a depth above INT_MAX PASSES the guard and reaches find (its own rc 1, §2.2)"
reset fF tree
fF.maxDepth = 2147483648
GOT=()
rc=0
fF.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -maxdepth 2147483648; then
    kt_test_pass "the wrapper builds it; 'Numerical result out of range' is the TOOL's rc 1"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

kt_test_start "F3: \`type = f,f\` PASSES the regex — the duplicate is the TOOL's rc 1 (parity)"
reset fF tree
fF.type = f,f
GOT=()
rc=0
fF.argv GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT find tree -type f,f; then
    kt_test_pass "the regex admits duplicates on purpose; 005 pins the tool's rc 1"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

# ===========================================================================
kt_test_section "G. F5 — \`print0\` derives the sinks' \`-0\` (§2.3, P3-F1)"
# ===========================================================================

kt_test_start "F5: \`print0 = 1\` DERIVES \`nul = 1\`"
reset fZ tree
fZ.print0 = 1
GOT=()
rc=0
fZ.argv GOT || rc=$?
if [[ $rc -eq 0 && "$(fZ.nul)" == "1" && "$(fZ._nulDerived)" == "1" ]] \
   && arr_is GOT find tree -print0; then
    kt_test_pass "nul = 1, _nulDerived = 1, argv ends in -print0"
else
    kt_test_fail "rc=$rc nul='$(fZ.nul)' drv='$(fZ._nulDerived)' GOT=$(arr_show GOT)"
fi

kt_test_start "F5: \`print0 = 0\` again takes the derived \`-0\` back off"
fZ.print0 = 0
fZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(fZ.nul)" == "0" && "$(fZ._nulDerived)" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding (the \`_nulDerived\` bookkeeping)"
else
    kt_test_fail "nul='$(fZ.nul)' drv='$(fZ._nulDerived)'"
fi

kt_test_start "F5: a MANUAL \`nul = 1\` with \`print0 = 0\` is the caller's and survives"
reset fZ tree
fZ.nul = 1
fZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(fZ.nul)" == "1" && "$(fZ._nulDerived)" == "0" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(fZ.nul)' drv='$(fZ._nulDerived)'"
fi

# P3-F1. The undo used to be one condition too coarse: `_nulDerived` was claimed
# whenever the derivation CONDITION held, even when `nul` was already 1 because
# the CALLER set it — so the next build that stopped deriving took the caller's
# own `nul` down to 0 with it.
kt_test_start "F5 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset fZ tree
fZ.nul = 1                      # the caller's own framing decision
fZ.print0 = 1
fZ.argv GOT >/dev/null 2>&1 || :
mid="$(fZ.nul)" middrv="$(fZ._nulDerived)"
fZ.print0 = 0
fZ.argv GOT >/dev/null 2>&1 || :
end="$(fZ.nul)" enddrv="$(fZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through -print0 and back; _nulDerived never claimed it"
else
    kt_test_fail "after -print0: nul='$mid' drv='$middrv'; after print0=0: nul='$end' drv='$enddrv'"
fi

kt_test_start "F5: a REFUSED build derives nothing (the rc 2 path never reaches the rule)"
reset fZ '-weird'
fZ.print0 = 1
fZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(fZ.nul)" == "0" && "$(fZ._nulDerived)" == "0" ]]; then
    kt_test_pass "nul untouched on the rc 2 path"
else
    kt_test_fail "nul='$(fZ.nul)' drv='$(fZ._nulDerived)'"
fi

kt_test_start "F5: \`crlf\` is never touched by buildArgv"
reset fZ tree
fZ.crlf = 1
fZ.print0 = 1
fZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(fZ.crlf)" == "1" ]]; then
    kt_test_pass "crlf = 1 kept"
else
    kt_test_fail "crlf='$(fZ.crlf)'"
fi

# ===========================================================================
kt_test_section "H. F5b — the caller-side glob trap (§2.2)"
# ===========================================================================

# `f.name = *.txt` UNQUOTED expands at the CALL SITE, and the property setter
# keeps only the first word — silently. The `cd` happens in THIS file's own
# shell (never in a subshell, D6) and is undone immediately afterwards.
GDIR="$(cd "$(kt_fixture_tmpdir_create globtrap)" && pwd)"
printf 'x\n' > "$GDIR/one.txt"
printf 'x\n' > "$GDIR/two.txt"

cd "$GDIR" || :
reset fG .
fG.name = *.txt                      # UNQUOTED — the shell expands it here
UNQ="$(fG.name)"
declare -a UNQ_ARGV=()
unq_rc=0
fG.argv UNQ_ARGV || unq_rc=$?
reset fG2 .
fG2.name = '*.txt'                   # QUOTED — the pattern reaches find
QUO="$(fG2.name)"
declare -a QUO_ARGV=()
quo_rc=0
fG2.argv QUO_ARGV || quo_rc=$?
cd "$SCRIPT_DIR" || :

kt_test_start "F5b: \`f.name = *.txt\` UNQUOTED keeps ONE word — the first match, silently"
if [[ "$UNQ" == "one.txt" && $unq_rc -eq 0 ]] && arr_is UNQ_ARGV find . -name one.txt; then
    kt_test_pass "the property holds 'one.txt'; 'two.txt' was dropped without a word"
else
    kt_test_fail "name='$UNQ' rc=$unq_rc argv=$(arr_show UNQ_ARGV)"
fi

kt_test_start "F5b: \`f.name = '*.txt'\` QUOTED keeps the pattern — always quote at the call site"
if [[ "$QUO" == '*.txt' && $quo_rc -eq 0 ]] && arr_is QUO_ARGV find . -name '*.txt'; then
    kt_test_pass "the pattern reaches find as one argv element"
else
    kt_test_fail "name='$QUO' rc=$quo_rc argv=$(arr_show QUO_ARGV)"
fi

kt_test_start "F5b: the \`cd\` was undone — this file's shell is back in its own directory"
if [[ "$PWD" == "$SCRIPT_DIR" ]]; then
    kt_test_pass "PWD = $SCRIPT_DIR"
else
    kt_test_fail "PWD = $PWD"
fi

fA.delete
f1.delete
f2.delete
f3.delete
f4.delete
f5.delete
fE.delete
fF.delete
fZ.delete
fG.delete
fG2.delete
