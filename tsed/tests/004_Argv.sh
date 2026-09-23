#!/bin/bash
# 004_Argv.sh — tsed P0: the argv model (tsed/PLAN.md §1.2, §2.1–§2.5; pinned
# facts S1–S5).
#
# THIS FILE NEVER RUNS sed. Every option is pinned by comparing the ARRAY that
# `s.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   sed [--sandbox] [-E] [-n] [-s] [-z] [-b] [-i[SUFFIX]] [EXTRA OPTIONS]
#       [-e EXPR] [-e X ...] [-f FILE] [-- PATH...]
#
# so it is the fast half of the suite and it holds on a box without GNU sed.
# The behavioural half is `005_Run.sh`.
#
# Sections:
#   A  S3  lifecycle — every declared var in `${inst}_data` after `new` (incl.
#          `sandbox=1` and the inherited `subshellOk`), `${s}_args` EMPTY after
#          `TSed.new s EXPR PATH`, `_paths`/`_exprs` right, a reused name
#          starting clean, `delete` freeing `_paths`/`_exprs`/`_args`/`_argv`,
#          `argv` running nothing, and both out-name registries: `__tsd_*`
#          refused, `s_exprs` refused by `argv` AND `toArray` with the list
#          intact, `TUTIL_OUT_SUFFIXES` refused as a NAME
#   B  S1  every option SINGLY
#   C  S1  combinations; `expr` then the `addExpr` list in order; `-f` after
#          the expressions; `--` iff paths; extras between the typed options
#          and the expressions; the boolean rule
#   D  S2  the rc 2 list of §2.2 incl. every Q6 deny-list word — rc 2, RESULT
#          '', the caller's array untouched, `${inst}_argv` EMPTY, one line; and
#          the extras that PASS (`--posix`, `-u`, `-l 40`, `--debug`, …)
#   E  S4  `nullData` -> `nul` (the four-state P3-F1 sequence) and the derived
#          `-b` for `inPlace` / `nullData` (the `binary` property never written)
#   F  S5  every option precedes the first `-e`, whatever order the caller
#          assigned in (the `-E` pin)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tsed.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: TSed — typed options to argv, nothing executed (P0)"

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

# check_argv TITLE INST WANT... — `INST.argv GOT` answers rc 0, RESULT = the
# word count, GOT holding exactly WANT.
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

# check_rc2 TITLE WANT_MSG_SUBSTR INST — rc 2, RESULT '', the caller's array
# untouched, `${inst}_argv` EMPTY, EXACTLY ONE kk.debug line naming the reason.
check_rc2() {
    local __t="$1" __want="$2" __i="$3"
    kt_test_start "$__t"
    GOT=( stale-1 stale-2 )
    RESULT="result-sentinel"
    dbg_n "$__i".argv GOT
    local -n __iv="${__i}_argv"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"$__want"* ]] \
       && arr_is GOT stale-1 stale-2 && (( ${#__iv[@]} == 0 )); then
        kt_test_pass "rc 2, RESULT '', array untouched, \${inst}_argv empty, one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' got=$(arr_show GOT) instArgv=$(arr_show __iv)"
    fi
}

# reset INST [EXPR [PATH...]] — a fresh instance under the same name. `.new`
# over a LIVE instance does not clear `${inst}_data`, so this doubles as a
# standing check that `Create` assigns every var.
reset() {
    TSed.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. S3 lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

TS_VARS=( expr scriptFile extended quiet separate nullData binary sandbox inPlace backupSuffix _nulDerived )
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "S3: every declared var is present in \`\${inst}_data\` right after \`new\`"
TSed.new sA 's/a/A/' f.txt
missing=""
decl="$(declare -p sA_data)"
for v in "${TS_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TS_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "S3: the documented defaults — expr = arg 1, sandbox 1, the rest 0/'', cmd sed, _lastRc -1"
bad=""
[[ "$(sA.expr)" == 's/a/A/' ]]     || bad+=" expr='$(sA.expr)'"
for v in scriptFile backupSuffix; do
    got="$(sA."$v")"
    [[ "$got" == "" ]] || bad+=" $v='$got'"
done
for v in extended quiet separate nullData binary inPlace _nulDerived crlf nul subshellOk; do
    got="$(sA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
[[ "$(sA.sandbox)" == "1" ]]  || bad+=" sandbox='$(sA.sandbox)'"
[[ "$(sA.cmd)" == "sed" ]]    || bad+=" cmd='$(sA.cmd)'"
[[ "$(sA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(sA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented; sandbox ON (owner Q1); subshellOk inherited 0"
else
    kt_test_fail "$bad"
fi

kt_test_start "S1/S3: \`\${s}_args\` is EMPTY after \`TSed.new s EXPR PATH\` (the \`inherited\` trap)"
declare -n AA=sA_args
if (( ${#AA[@]} == 0 )); then
    kt_test_pass "args empty — neither EXPR nor the path leaked into TUtil"
else
    kt_test_fail "sA_args=$(arr_show AA)"
fi
unset -n AA

kt_test_start "S3: \`\${s}_paths\` holds every argument after EXPR verbatim; \`\${s}_exprs\` is an EMPTY array"
TSed.new sP 'p' 'a b' '-dash' $'nl\nname' '-'
declare -n PP=sP_paths
dx="$(declare -p sP_exprs 2>&1)"
if arr_is PP 'a b' '-dash' $'nl\nname' '-' && [[ "$dx" == "declare -a sP_exprs=()" ]]; then
    kt_test_pass "4 paths, no doubling: $(arr_show PP); $dx"
else
    kt_test_fail "sP_paths=$(arr_show PP) exprs='$dx'"
fi
unset -n PP
sP.delete

kt_test_start "S3: \`TSed.new s\` with NO argument — expr '', no path, no expression"
TSed.new sD
declare -n DP=sD_paths
declare -n DX=sD_exprs
if (( ${#DP[@]} == 0 && ${#DX[@]} == 0 )) && [[ "$(sD.expr)" == "" && "$(sD.cmd)" == "sed" ]]; then
    kt_test_pass "empty paths, empty exprs, expr '', cmd sed"
else
    kt_test_fail "paths=$(arr_show DP) exprs=$(arr_show DX) expr='$(sD.expr)'"
fi
unset -n DP DX
sD.delete

kt_test_start "S3: a REUSED instance name starts clean (every var and both lists re-assigned)"
TSed.new sR 'old' x1
sR.quiet = 1
sR.sandbox = 0
sR.inPlace = 1
sR.backupSuffix = .bak
sR.addExpr 'p' 'q'
TSed.new sR 'new' x2                  # no delete in between — _data is NOT cleared
clean=1
[[ "$(sR.expr)" == "new" ]]         || clean=0
[[ "$(sR.quiet)" == "0" ]]          || clean=0
[[ "$(sR.sandbox)" == "1" ]]        || clean=0
[[ "$(sR.inPlace)" == "0" ]]        || clean=0
[[ "$(sR.backupSuffix)" == "" ]]    || clean=0
arr_is sR_paths x2                  || clean=0
arr_is sR_exprs                     || clean=0
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\`"
else
    kt_test_fail "expr='$(sR.expr)' quiet='$(sR.quiet)' sandbox='$(sR.sandbox)' inPlace='$(sR.inPlace)' exprs=$(arr_show sR_exprs)"
fi

kt_test_start "S3: \`delete\` removes \`_paths\`, \`_exprs\`, \`_args\`, \`_argv\` and \`_data\`"
declare -a W=()
sR.argv W >/dev/null 2>&1 || :
sR.delete
left=""
for a in _paths _exprs _args _argv _data; do
    declare -p "sR$a" >/dev/null 2>&1 && left+=" $a"
done
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "S3: \`argv\` RUNS NOTHING — not even a cmd that exists"
tsd_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
TSed.new sN 's/a/A/' f.txt
sN.cmd = tsd_mark
W=()
rc=0
sN.argv W || rc=$?
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "6" ]] && arr_is W tsd_mark --sandbox -e 's/a/A/' -- f.txt; then
    kt_test_pass "the 6-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
sN.delete

# --- S3: the two out-name registries (PLAN §2.1) ---------------------------
# `__tsd_*` is this unit's scratch prefix (bash scopes locals dynamically), and
# `${inst}_exprs` is its own storage: measured, `s.toArray s_exprs` turned the
# records into the NEXT run's script. P0 turns the hard-coded suffix list of
# `tutil._badOut` into `TUTIL_OUT_SUFFIXES`, which this unit extends with
# `_exprs`; the tutil half is `tutil/tests/001_Core.sh` §C.

bad_out() {   # bad_out TITLE MEMBER NAME
    kt_test_start "$1"
    local __m="$2" __n="$3"
    RESULT="sentinel"
    dbg_n sA."$__m" "$__n"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 \
          && "$DBG_1" == *"bad output array name"* && "$DBG_1" == *"$__n"* ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1'"
    fi
}

sA.addExpr 's/b/B/' 'p'
bad_out "S3: \`s.argv __tsd_v\` is rc 2 (the TSed local prefix)"               argv    __tsd_v
bad_out "S3: \`s.argv __tsd_x\` is rc 2"                                      argv    __tsd_x
bad_out "S3: \`s.toArray __tsd_a\` is rc 2 — refused BEFORE anything runs"    toArray __tsd_a
bad_out "S3: \`s.argv sA_exprs\` is rc 2 (the suffix registry, \`_exprs\`)"    argv    sA_exprs
bad_out "S3: \`s.toArray sA_exprs\` is rc 2 (records would become the next script)" toArray sA_exprs
bad_out "S3: \`s.argv sA_paths\` is rc 2 (still refused through the registry)" argv   sA_paths
bad_out "S3: \`s.argv sA_args\` is rc 2"                                      argv    sA_args
bad_out "S3: \`s.argv TUTIL_OUT_SUFFIXES\` is rc 2 (the registry's own NAME)"  argv    TUTIL_OUT_SUFFIXES
bad_out "S3: \`s.toArray TUTIL_OUT_SUFFIXES\` is rc 2"                        toArray TUTIL_OUT_SUFFIXES
bad_out "S3: \`s.argv TUTIL_OUT_PREFIXES\` is rc 2"                           argv    TUTIL_OUT_PREFIXES

kt_test_start "S3: the expression list is INTACT after every refusal above"
if arr_is sA_exprs 's/b/B/' 'p' && [[ "$(sA.expr)" == 's/a/A/' ]]; then
    kt_test_pass "exprs = $(arr_show sA_exprs), expr = 's/a/A/'"
else
    kt_test_fail "exprs=$(arr_show sA_exprs) expr='$(sA.expr)'"
fi

kt_test_start "S3: both registries survived — \`__tsd_\` and \`_exprs\` registered exactly once"
n_p=0; n_s=0
for q in "${TUTIL_OUT_PREFIXES[@]}"; do [[ "$q" == "__tsd_" ]] && n_p=$(( n_p + 1 )); done
for q in "${TUTIL_OUT_SUFFIXES[@]}"; do [[ "$q" == "_exprs" ]] && n_s=$(( n_s + 1 )); done
if [[ "$n_p" == "1" && "$n_s" == "1" ]] \
   && arr_is TUTIL_OUT_PREFIXES __tu_ __tg_ __th_ __tt_ __tsd_ \
   && arr_is TUTIL_OUT_SUFFIXES _args _argv _paths _exprs; then
    kt_test_pass "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
else
    kt_test_fail "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
fi

kt_test_start "S3: sourcing tsed twice appends NOTHING (idempotent)"
source "$UNIT"
source "$UNIT"
if arr_is TUTIL_OUT_PREFIXES __tu_ __tg_ __th_ __tt_ __tsd_ \
   && arr_is TUTIL_OUT_SUFFIXES _args _argv _paths _exprs; then
    kt_test_pass "five prefixes, four suffixes"
else
    kt_test_fail "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
fi

kt_test_start "S3: an ordinary out-name still fills after every refusal"
declare -a OKARR=()
rc=0
sA.argv OKARR || rc=$?
if [[ $rc -eq 0 ]] && arr_is OKARR sed --sandbox -e 's/a/A/' -e 's/b/B/' -e p -- f.txt; then
    kt_test_pass "argv=$(arr_show OKARR)"
else
    kt_test_fail "rc=$rc OKARR=$(arr_show OKARR)"
fi

# ===========================================================================
kt_test_section "B. S1 — every option, singly"
# ===========================================================================

one() {   # one TITLE PROP VALUE WANT...  (on `new s1 's/a/A/' f.txt`)
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset s1 's/a/A/' f.txt
    s1."$__p" = "$__v"
    check_argv "$__t" s1 "$@"
}

reset s1 's/a/A/' f.txt
check_argv "S1: no option at all — \`sed --sandbox -e EXPR -- PATH\` (sandbox by default)" s1 \
    sed --sandbox -e 's/a/A/' -- f.txt

one "S1: \`sandbox = 0\` drops \`--sandbox\`"        sandbox  0   sed -e 's/a/A/' -- f.txt
one "S1: \`extended = 1\` -> -E"                     extended 1   sed --sandbox -E -e 's/a/A/' -- f.txt
one "S1: \`quiet = 1\` -> -n"                        quiet    1   sed --sandbox -n -e 's/a/A/' -- f.txt
one "S1: \`separate = 1\` -> -s"                     separate 1   sed --sandbox -s -e 's/a/A/' -- f.txt
one "S1: \`nullData = 1\` -> -z AND the derived -b"  nullData 1   sed --sandbox -z -b -e 's/a/A/' -- f.txt
one "S1: \`binary = 1\` -> -b"                       binary   1   sed --sandbox -b -e 's/a/A/' -- f.txt
one "S1: \`inPlace = 1\` -> the derived -b, then -i" inPlace  1   sed --sandbox -b -i -e 's/a/A/' -- f.txt
one "S1: \`scriptFile = s.sed\` -> -f AFTER the expressions" scriptFile s.sed \
                                                     sed --sandbox -e 's/a/A/' -f s.sed -- f.txt

reset s1 's/a/A/' f.txt
s1.inPlace = 1
s1.backupSuffix = .bak
check_argv "S1: \`backupSuffix = .bak\` is ATTACHED to -i (one word, \`-i.bak\`)" s1 \
    sed --sandbox -b -i.bak -e 's/a/A/' -- f.txt

reset s1 's/a/A/' f.txt
s1.inPlace = 1
s1.backupSuffix = 'bak_*'
check_argv "S1: \`backupSuffix = 'bak_*'\` passes (base-name substitution, documented)" s1 \
    sed --sandbox -b '-ibak_*' -e 's/a/A/' -- f.txt

reset s1 's/a/A/' f.txt
s1.inPlace = 1
s1.backupSuffix = 'bk/*'
check_argv "S1: \`backupSuffix = 'bk/*'\` passes (a directory; missing -> the tool's rc 4)" s1 \
    sed --sandbox -b '-ibk/*' -e 's/a/A/' -- f.txt

reset s1 's/a/A/' f.txt
s1.inPlace = 1
s1.backupSuffix = ' my bak'
check_argv "S1: a suffix with a space stays ONE argv word" s1 \
    sed --sandbox -b '-i my bak' -e 's/a/A/' -- f.txt

reset s1 '' f.txt
s1.scriptFile = s.sed
check_argv "S1: \`scriptFile\` ALONE (expr '') — no \`-e\` at all" s1 \
    sed --sandbox -f s.sed -- f.txt

reset s1 's/a/A/'
check_argv "S1: no path — no \`--\` (sed reads stdin)" s1 sed --sandbox -e 's/a/A/'

reset s1 's/a/A/' '-weird' '-' 'a b'
check_argv "S1: paths after \`--\`, verbatim — \`-weird\`, \`-\` (stdin) and a space" s1 \
    sed --sandbox -e 's/a/A/' -- '-weird' '-' 'a b'

# ===========================================================================
kt_test_section "C. S1 — the expressions, the extras, the pinned order"
# ===========================================================================

reset s2 'E0' f.txt
s2.addExpr 'E1'
s2.addExpr 'E2' 'E3'
check_argv "S1: \`expr\` FIRST, then every \`addExpr\` item in call order" s2 \
    sed --sandbox -e E0 -e E1 -e E2 -e E3 -- f.txt

reset s2 '' f.txt
s2.addExpr 'X1' 'X2'
check_argv "S1: \`expr = ''\` means NONE — only the list is emitted" s2 \
    sed --sandbox -e X1 -e X2 -- f.txt

reset s2 '' f.txt
s2.addExpr ''
check_argv "S1: \`addExpr ''\` is a REAL element — \`-e ''\`, sed's identity" s2 \
    sed --sandbox -e '' -- f.txt

reset s2 's/a/A/' f.txt
s2.addExpr '' 'p'
check_argv "S1: an empty element INSIDE the list keeps its slot" s2 \
    sed --sandbox -e 's/a/A/' -e '' -e p -- f.txt

reset s2 '1{' f.txt
s2.addExpr $'s/a/J/\np' '}'
check_argv "S1: an expression holding a newline is ONE word" s2 \
    sed --sandbox -e '1{' -e $'s/a/J/\np' -e '}' -- f.txt

reset s2 'E0' f.txt
s2.addExpr 'E1' 'E2'
s2.clearExprs
check_argv "S1: \`clearExprs\` empties the list and keeps \`expr\`" s2 \
    sed --sandbox -e E0 -- f.txt

reset s2 'E0' f.txt
s2.addExpr
check_argv "S1: \`addExpr\` with no argument is a no-op" s2 sed --sandbox -e E0 -- f.txt

reset s2 'E0' f.txt
s2.scriptFile = s.sed
s2.addExpr 'E1'
check_argv "S1: \`-f\` comes after ALL the expressions" s2 \
    sed --sandbox -e E0 -e E1 -f s.sed -- f.txt

reset s2 'E0' f.txt
s2.addArg --posix
s2.extended = 1
check_argv "S1: an extra lands AFTER the typed options and BEFORE the first \`-e\`" s2 \
    sed --sandbox -E --posix -e E0 -- f.txt

reset s2 'E0' f.txt
s2.addArg -u
s2.addArg -l 40
s2.addArg --follow-symlinks
check_argv "S1: several extras keep their order and their words" s2 \
    sed --sandbox -u -l 40 --follow-symlinks -e E0 -- f.txt

reset s2 'E0' f.txt
s2.addArg -u
s2.clearArgs
check_argv "S1: \`clearArgs\` empties the extras again" s2 sed --sandbox -e E0 -- f.txt

reset s2 'E0' old1 old2
s2.paths new1 'new 2'
check_argv "S1: \`s.paths new1 'new 2'\` replaced both old paths" s2 \
    sed --sandbox -e E0 -- new1 'new 2'

reset s2 'E0' old1
s2.paths
check_argv "S1: \`s.paths\` with NO argument is the stdin form — no \`--\`" s2 sed --sandbox -e E0

reset s2 'E0' p1 'p 2'
s2.extended = 1
s2.quiet = 1
s2.separate = 1
s2.nullData = 1
s2.binary = 1
s2.inPlace = 1
s2.backupSuffix = .bak
s2.scriptFile = 'my script.sed'
s2.addArg --posix -u -l 40
s2.addExpr 'X1' 'X2'
check_argv "S1: EVERYTHING at once — the full pinned order, ONE \`-b\`" s2 \
    sed --sandbox -E -n -s -z -b -i.bak --posix -u -l 40 -e E0 -e X1 -e X2 \
    -f 'my script.sed' -- p1 'p 2'

kt_test_start "S1: a boolean is ON only for the exact string \`1\` (never \`(( x ))\`) — every flag but \`sandbox\`"
allgood=1
badv=""
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset s3 'E0' f.txt
    for p in extended quiet separate nullData binary inPlace; do
        s3."$p" = "$v"
    done
    GOT=()
    s3.argv GOT >/dev/null 2>&1 || :
    if ! arr_is GOT sed --sandbox -e E0 -- f.txt; then
        allgood=0
        badv="'$v' -> $(arr_show GOT)"
        break
    fi
done
if [[ "$allgood" == "1" ]]; then
    kt_test_pass "'2', 'yes', 'true', 'on', '01', '-1', ' 1', '1 ' are all OFF"
else
    kt_test_fail "$badv"
fi

# `sandbox` FAILS CLOSED (owner Q1 is a security default; reviewer ruling on
# P0): `--sandbox` is omitted ONLY for the exact string `0`. Every other value —
# empty, `yes`, `2`, a padded or doubled zero — keeps it. The deliberate
# exception to the family boolean rule pinned just above.
sbx() {   # sbx VALUE WANT...
    local __v="$1"; shift
    reset s3 'E0' f.txt
    s3.sandbox = "$__v"
    check_argv "S1 (Q1, fail closed): \`sandbox = $(printf '%q' "$__v")\` -> $( [[ "$1 $2" == "sed --sandbox" ]] && printf 'SANDBOXED' || printf 'open' )" s3 "$@"
}

sbx ''      sed --sandbox -e E0 -- f.txt
sbx yes     sed --sandbox -e E0 -- f.txt
sbx 2       sed --sandbox -e E0 -- f.txt
sbx ' 0'    sed --sandbox -e E0 -- f.txt
sbx '0 '    sed --sandbox -e E0 -- f.txt
sbx 00      sed --sandbox -e E0 -- f.txt
sbx false   sed --sandbox -e E0 -- f.txt
sbx off     sed --sandbox -e E0 -- f.txt
sbx -0      sed --sandbox -e E0 -- f.txt
sbx 1       sed --sandbox -e E0 -- f.txt
sbx 0       sed -e E0 -- f.txt

kt_test_start "S1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset s2 'E0' f.txt
s2.addExpr E1
declare -a W1=() W2=()
s2.argv W1 >/dev/null 2>&1 || :
s2.argv W2 >/dev/null 2>&1 || :
if arr_is W1 sed --sandbox -e E0 -e E1 -- f.txt && arr_is W2 sed --sandbox -e E0 -e E1 -- f.txt; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "S1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
s2.argv W3 >/dev/null 2>&1 || :
W3[1]="TAMPERED"
declare -n IV=s2_argv
if [[ "${IV[1]:-}" == "--sandbox" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "s2_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "D. S2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset sE 's/a/A/' f.txt
sE.cmd = ''
check_rc2 "S2: empty \`cmd\` is rc 2" "cmd is empty" sE

reset sE '' f.txt
check_rc2 "S2: NO script at all (expr '', no list, no scriptFile) is rc 2 — sed would read the path AS the script" \
    "no script" sE

reset sE '' f.txt
sE.addExpr E1
sE.clearExprs
check_rc2 "S2: no script after \`clearExprs\` is rc 2 too" "no script" sE

reset sE ''
check_rc2 "S2: no script and no path is rc 2" "no script" sE

reset sE 's/a/A/'
sE.inPlace = 1
check_rc2 "S2: \`inPlace = 1\` with NO path is rc 2" "inPlace" sE

reset sE 's/a/A/' '-'
sE.inPlace = 1
check_rc2 "S2: \`inPlace = 1\` with the path \`-\` is rc 2" "inPlace" sE

reset sE 's/a/A/' good.txt '-'
sE.inPlace = 1
check_rc2 "S2: \`inPlace = 1\` with \`-\` ANYWHERE in the paths is rc 2" "inPlace" sE

reset sE 's/a/A/' f.txt
sE.backupSuffix = .bak
check_rc2 "S2: \`backupSuffix\` with \`inPlace = 0\` is rc 2" "backupSuffix" sE

reset sE 's/a/A/' f.txt
sE.inPlace = 1
sE.backupSuffix = '*'
check_rc2 "S2: \`backupSuffix = '*'\` is rc 2 (the backup name would BE the file: no backup, silently)" \
    "backupSuffix" sE

# deny WORDS... — every extra word on the Q6 deny-list, on its own, is rc 2
# with the property named in the line.
deny() {   # deny PROPERTY WORD...
    local __prop="$1"; shift
    reset sE 's/a/A/' f.txt
    sE.addArg "$@"
    check_rc2 "S2 (Q6): \`addArg $(printf '%q ' "$@")\` is rc 2 — use \`$__prop\`" "$__prop" sE
}

deny inPlace    -i
deny inPlace    --in-place
deny inPlace    --in-place=.bak
deny nullData   -z
deny nullData   --null-data
deny expr       -e 'p'
deny expr       --expression 'p'
deny expr       --expression=p
deny scriptFile -f s.sed
deny scriptFile --file s.sed
deny scriptFile --file=s.sed
deny quiet      -n
deny quiet      --quiet
deny quiet      --silent
deny separate   -s
deny separate   --separate
deny extended   -E
deny extended   -r
deny extended   --regexp-extended
deny binary     -b
deny binary     --binary
deny sandbox    --sandbox
deny quiet      -ni
deny quiet      -nE
deny separate   -us
deny inPlace    -ui

# The same options in the other spellings getopt reads identically (sed 4.9,
# measured): an ATTACHED short argument (`-i.bak` is `--in-place=.bak`), an
# unambiguous long-option ABBREVIATION (`--in=.bak` edited the file in place
# with rc 0), the undocumented `--zero-terminated` alias of `-z`, and a long
# form with `=VALUE` sed would itself reject.
deny inPlace    -i.bak
deny quiet      -ni.bak
deny expr       '-es/a/b/'
deny scriptFile -fs.sed
deny inPlace    --in=.bak
deny inPlace    --in
deny expr       --expr=p
deny scriptFile --fi=s.sed
deny nullData   --null
deny nullData   --zero-terminated
deny nullData   --zero
deny quiet      --qui
deny quiet      --sil
deny separate   --sep
deny extended   --reg
deny binary     --bin
deny sandbox    --sand
deny sandbox    --sandbox=1
deny quiet      --quiet=1

# `--` among the extras ends sed's options: measured, `addArg --` built
# `sed --sandbox -- -e s/a/A/ -- f`, so every expression became an OPERAND (sed
# then read `-e` as its script). Reviewer ruling on P0: on the deny-list.
reset sE 's/a/A/' f.txt
sE.addArg --
check_rc2 "S2 (Q6): \`addArg --\` is rc 2 — \`--\` ends sed's options (the wrapper emits its own before the paths)" \
    "ends sed's options" sE

reset sE 's/a/A/' f.txt
sE.addArg -u -- --posix
check_rc2 "S2 (Q6): \`--\` in the MIDDLE of the extras is rc 2 too" "ends sed's options" sE

reset sE 's/a/A/'
sE.addArg --
check_rc2 "S2 (Q6): \`addArg --\` with NO path is rc 2 too" "ends sed's options" sE

kt_test_start "S2 (Q6): a denied word NOT first among the extras is refused too"
reset sE 's/a/A/' f.txt
sE.addArg -u
sE.addArg --posix -n
GOT=( stale-1 stale-2 )
RESULT="sentinel"
dbg_n sE.argv GOT
declare -n EV=sE_argv
if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"quiet"* ]] \
   && arr_is GOT stale-1 stale-2 && (( ${#EV[@]} == 0 )); then
    kt_test_pass "the whole extras list is scanned: ${DBG_1:0:70}"
else
    kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' instArgv=$(arr_show EV)"
fi
unset -n EV

pass_extra() {   # pass_extra WORD...
    reset sE 's/a/A/' f.txt
    sE.addArg "$@"
    check_argv "S2 (Q6): \`addArg $(printf '%q ' "$@")\` PASSES — not a typed property" sE \
        sed --sandbox "$@" -e 's/a/A/' -- f.txt
}

pass_extra --posix
pass_extra -u
pass_extra --unbuffered
pass_extra -l 40
pass_extra -l40
pass_extra -ul40
pass_extra --line-length=40
pass_extra --follow-symlinks
pass_extra --debug

kt_test_start "S2: each refused ingredient on its OWN is fine"
ok=1
reset sE 's/a/A/' f.txt; sE.inPlace = 1;                         sE.argv GOT >/dev/null 2>&1 || ok=0
reset sE 's/a/A/' f.txt; sE.inPlace = 1; sE.backupSuffix = .b;   sE.argv GOT >/dev/null 2>&1 || ok=0
reset sE 's/a/A/' '-';                                           sE.argv GOT >/dev/null 2>&1 || ok=0
reset sE '' f.txt; sE.scriptFile = s.sed;                        sE.argv GOT >/dev/null 2>&1 || ok=0
reset sE '' f.txt; sE.addExpr '';                                sE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "inPlace, a suffix with inPlace, \`-\` without inPlace, -f alone, the identity — all build"
else
    kt_test_fail "a legal shape was refused"
fi

# ===========================================================================
kt_test_section "E. S4 — \`nullData\` derives \`-0\` (P3-F1), and the derived \`-b\`"
# ===========================================================================

kt_test_start "S4: \`nullData = 1\` DERIVES \`nul = 1\`"
reset sZ 'p' f.txt
sZ.nullData = 1
GOT=()
rc=0
sZ.argv GOT || rc=$?
if [[ $rc -eq 0 && "$(sZ.nul)" == "1" && "$(sZ._nulDerived)" == "1" ]] \
   && arr_is GOT sed --sandbox -z -b -e p -- f.txt; then
    kt_test_pass "nul = 1, _nulDerived = 1, argv has -z -b"
else
    kt_test_fail "rc=$rc nul='$(sZ.nul)' drv='$(sZ._nulDerived)' GOT=$(arr_show GOT)"
fi

kt_test_start "S4: \`nullData = 0\` again takes the derived \`-0\` back off"
sZ.nullData = 0
sZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(sZ.nul)" == "0" && "$(sZ._nulDerived)" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding"
else
    kt_test_fail "nul='$(sZ.nul)' drv='$(sZ._nulDerived)'"
fi

kt_test_start "S4: a MANUAL \`nul = 1\` with \`nullData = 0\` is the caller's and survives"
reset sZ 'p' f.txt
sZ.nul = 1
sZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(sZ.nul)" == "1" && "$(sZ._nulDerived)" == "0" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(sZ.nul)' drv='$(sZ._nulDerived)'"
fi

kt_test_start "S4 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset sZ 'p' f.txt
sZ.nul = 1
sZ.nullData = 1
sZ.argv GOT >/dev/null 2>&1 || :
mid="$(sZ.nul)" middrv="$(sZ._nulDerived)"
sZ.nullData = 0
sZ.argv GOT >/dev/null 2>&1 || :
end="$(sZ.nul)" enddrv="$(sZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through -z and back; _nulDerived never claimed it"
else
    kt_test_fail "after -z: nul='$mid' drv='$middrv'; after nullData=0: nul='$end' drv='$enddrv'"
fi

kt_test_start "S4: a REFUSED build derives nothing (the rc 2 path never reaches the rule)"
reset sZ '' f.txt                     # no script -> rc 2
sZ.nullData = 1
sZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(sZ.nul)" == "0" && "$(sZ._nulDerived)" == "0" ]]; then
    kt_test_pass "nul untouched on the rc 2 path"
else
    kt_test_fail "nul='$(sZ.nul)' drv='$(sZ._nulDerived)'"
fi

# derived_b TITLE PROP — PROP = 1 shows `-b` with `binary` still 0; PROP = 0
# again removes it (owner Q5: the derivation lives in buildArgv only).
derived_b() {
    local __t="$1" __p="$2" __w1 __w2
    kt_test_start "$__t"
    reset sB 'p' f.txt
    sB."$__p" = 1
    local -a __g1=() __g2=()
    sB.argv __g1 >/dev/null 2>&1 || :
    local __bin1; __bin1="$(sB.binary)"
    sB."$__p" = 0
    sB.argv __g2 >/dev/null 2>&1 || :
    local __bin2; __bin2="$(sB.binary)"
    local __has1=0 __has2=0 __w
    for __w in "${__g1[@]}"; do [[ "$__w" == "-b" ]] && __has1=$(( __has1 + 1 )); done
    for __w in "${__g2[@]}"; do [[ "$__w" == "-b" ]] && __has2=$(( __has2 + 1 )); done
    if [[ "$__has1" == "1" && "$__has2" == "0" && "$__bin1" == "0" && "$__bin2" == "0" ]] \
       && arr_is __g2 sed --sandbox -e p -- f.txt; then
        kt_test_pass "on: $(arr_show __g1)| off: $(arr_show __g2)| binary stayed 0"
    else
        kt_test_fail "on=$(arr_show __g1) off=$(arr_show __g2) binary='$__bin1'/'$__bin2'"
    fi
}

derived_b "S4 (Q5): \`inPlace = 1\` derives \`-b\`, the \`binary\` property stays 0, and \`inPlace = 0\` takes it away" inPlace
derived_b "S4 (Q5): \`nullData = 1\` derives \`-b\` the same way" nullData

reset sB 'p' f.txt
sB.binary = 1
sB.inPlace = 1
sB.nullData = 1
check_argv "S4: \`binary\` + \`inPlace\` + \`nullData\` — still exactly ONE \`-b\`" sB \
    sed --sandbox -z -b -i -e p -- f.txt

reset sB 'p' f.txt
sB.binary = 1
sB.inPlace = 1
sB.inPlace = 0
check_argv "S4: a caller's own \`binary = 1\` survives \`inPlace\` going 1 -> 0" sB \
    sed --sandbox -b -e p -- f.txt

kt_test_start "S4: \`crlf\` is never touched by buildArgv"
reset sZ 'p' f.txt
sZ.crlf = 1
sZ.nullData = 1
sZ.inPlace = 1
sZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(sZ.crlf)" == "1" && "$(sZ.binary)" == "0" ]]; then
    kt_test_pass "crlf = 1 kept, binary 0"
else
    kt_test_fail "crlf='$(sZ.crlf)' binary='$(sZ.binary)'"
fi

# ===========================================================================
kt_test_section "F. S5 — every option precedes the first \`-e\`"
# ===========================================================================

# first_e_after_options ARR — rc 0 iff no word that is an OPTION (typed or
# extra) comes after the first `-e`. In this builder the words after the first
# `-e` are only `-e X` pairs, `-f F` and `-- PATH...`.
opts_before_e() {
    local -n __o="$1"
    local __k=0 __seen=0 __w
    while (( __k < ${#__o[@]} )); do
        __w="${__o[$__k]}"
        if [[ "$__seen" == "1" ]]; then
            case "$__w" in
                -e|-f) __k=$(( __k + 2 )); continue ;;
                --)    return 0 ;;
                *)     return 1 ;;
            esac
        fi
        if [[ "$__w" == "-e" ]]; then
            __seen=1
            __k=$(( __k + 2 ))
            continue
        fi
        __k=$(( __k + 1 ))
    done
    return 0
}

reset sF 's/(a)1/[\1]/' a1.txt
sF.addExpr 'p'
sF.extended = 1                       # assigned AFTER the expressions
check_argv "S5: \`extended\` set AFTER the expressions still emits \`-E\` BEFORE the first \`-e\`" sF \
    sed --sandbox -E -e 's/(a)1/[\1]/' -e p -- a1.txt

kt_test_start "S5: across every option shape, no option word follows the first \`-e\`"
okall=1
badshape=""
for shape in 1 2 3 4; do
    reset sF 'E0' p1
    sF.addExpr E1
    case "$shape" in
        1) sF.quiet = 1; sF.extended = 1 ;;
        2) sF.nullData = 1; sF.separate = 1; sF.addArg --posix ;;
        3) sF.inPlace = 1; sF.backupSuffix = .b; sF.scriptFile = s.sed ;;
        4) sF.binary = 1; sF.sandbox = 0; sF.addArg -u -l 9 ;;
    esac
    GOT=()
    sF.argv GOT >/dev/null 2>&1 || :
    if (( ${#GOT[@]} == 0 )) || ! opts_before_e GOT; then
        okall=0
        badshape+=" $shape:$(arr_show GOT)"
    fi
done
if [[ "$okall" == "1" ]]; then
    kt_test_pass "four shapes, every option before the first \`-e\`"
else
    kt_test_fail "$badshape"
fi

sA.delete
s1.delete
s2.delete
s3.delete
sE.delete
sZ.delete
sB.delete
sF.delete
