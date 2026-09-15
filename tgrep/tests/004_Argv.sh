#!/bin/bash
# 004_Argv.sh — tgrep P2: the argv model (tutil/PLAN.md §1.3, §2.1, §2.7, §5 P2;
# pinned facts G1–G4).
#
# THIS FILE NEVER RUNS grep. Every option is pinned by comparing the ARRAY that
# `g.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   grep [-i] [-v] [-w] [-x] [-F|-E] [-r] [-n] [-l|-L] [-c] [-o] [-h|-H]
#        [-m N] [--include=G] [--exclude=G] [--exclude-dir=G] [-U] [-z] [-Z]
#        -e PATTERN [EXTRA ARGS from addArg] [-- PATH...]
#
# so it is the fast half of the suite and it is true on a box where grep is
# missing altogether. The behavioural half is `005_Search.sh`.
#
# Sections:
#   A       lifecycle — every declared var present in `${inst}_data` right after
#           `new` with its documented default, `${g}_args` EMPTY after
#           `TGrep.new g PAT PATH` (the `inherited`-in-a-constructor trap),
#           `${g}_paths` filled, a reused instance name starting clean, and
#           `delete` removing `_paths` / `_args` / `_argv`
#   B  G1   every flag SINGLY
#   C  G1   flags in combination, in the pinned order; a non-`1` value is OFF
#   D  G1   `-e` always; `--` iff there is at least one path; `addArg` extras
#           land after `-e PATTERN` and before `--`; `paths` replaces the list
#   E  G2   the rc 2 list: empty `cmd`, empty `pattern`, `-F`+`-E`, `-l`+`-L`,
#           `-h`+`-H` — rc 2, RESULT '', the caller's array UNTOUCHED, one line
#   F  G3   `maxCount`: `abc` and `-1` are rc 2; `08` becomes `-m 8` through
#           `$__KK_INT` while the property still reads `08`
#   G  G4   a pattern that looks like a flag (`-v`, `--help`) is DATA — it lands
#           after `-e`; and the §2.7 derived-`-0` rule
#
# The out-name refusals of `argv` itself are TUtil's and are pinned in
# `tutil/tests/001_Core.sh`; this file only uses good names.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tgrep.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: TGrep — typed options to argv, nothing executed (P2)"

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

# arr_show ARRNAME -> a quoted, printable form for a failure message.
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
# RESULT '', the caller's array untouched, and EXACTLY ONE kk.debug line naming
# the reason (kcl README §1.2).
check_rc2() {
    local __t="$1" __want="$2" __i="$3"
    kt_test_start "$__t"
    GOT=( stale-1 stale-2 )
    RESULT="result-sentinel"
    dbg_n "$__i".argv GOT
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"$__want"* ]] \
       && arr_is GOT stale-1 stale-2; then
        kt_test_pass "rc 2, RESULT '', array untouched, one line: ${DBG_1:0:72}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' got=$(arr_show GOT)"
    fi
}

# reset INST — a fresh instance under the same name, so one case cannot leak
# into the next. `.new` over a LIVE instance does not clear `${inst}_data`, so
# this doubles as a standing check that `Create` assigns every var (§2.1).
reset() {
    TGrep.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

# The 23 declared vars: TGrep's own 22 (PLAN §1.3) plus `_nulDerived`, the
# private bookkeeping scalar the §2.7 derivation needs (see the unit header),
# and the four TUtil inherits down (cmd, crlf, nul, _lastRc).
TG_VARS=( pattern ignoreCase invert wordRegexp lineRegexp fixed extended
          recursive lineNumber filesOnly filesWithoutMatch countOnly
          onlyMatching noFilename withFilename maxCount include exclude
          excludeDir binary nullData nullOut _nulDerived )
# `subshellOk` is TUtil's (D6 final Q9): TGrep inherits it and must NOT
# redeclare it — a descendant `var` with an ancestor member's name is silently
# overridden by the method wrapper (kklass.sh:911).
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "every declared var is present in \`\${inst}_data\` right after \`new\` (§2.1)"
TGrep.new gA needle f1
missing=""
decl="$(declare -p gA_data)"
for v in "${TG_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TG_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "the documented defaults: booleans 0, strings '', cmd grep, _lastRc -1"
bad=""
for v in ignoreCase invert wordRegexp lineRegexp fixed extended recursive \
         lineNumber filesOnly filesWithoutMatch countOnly onlyMatching \
         noFilename withFilename binary nullData nullOut _nulDerived crlf nul \
         subshellOk; do
    got="$(gA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
for v in maxCount include exclude excludeDir; do
    got="$(gA."$v")"
    [[ "$got" == "" ]] || bad+=" $v='$got'"
done
[[ "$(gA.cmd)" == "grep" ]]   || bad+=" cmd='$(gA.cmd)'"
[[ "$(gA.pattern)" == "needle" ]] || bad+=" pattern='$(gA.pattern)'"
[[ "$(gA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(gA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented"
else
    kt_test_fail "$bad"
fi

kt_test_start "\`\${g}_args\` is EMPTY after \`TGrep.new g PAT PATH\` (the \`inherited\` trap, §2.1)"
# `inherited` in a constructor is rewritten to `parent.constructor "$@"`, which
# would have handed TUtil cmd=needle and args=(f1) — and every path would then
# be emitted twice. TGrep.Create calls `parent.constructor grep` explicitly.
declare -n AA=gA_args
if (( ${#AA[@]} == 0 )); then
    kt_test_pass "args empty — the pattern and the paths did NOT leak into TUtil"
else
    kt_test_fail "gA_args=$(arr_show AA)"
fi
unset -n AA

kt_test_start "\`\${g}_paths\` holds the constructor's paths verbatim, once each"
TGrep.new gP needle 'a b' -dash.txt $'nl\nname'
declare -n PP=gP_paths
if arr_is PP 'a b' '-dash.txt' $'nl\nname'; then
    kt_test_pass "3 paths, no doubling: $(arr_show PP)"
else
    kt_test_fail "gP_paths=$(arr_show PP)"
fi
unset -n PP
gP.delete

kt_test_start "a REUSED instance name starts clean (every var re-assigned by Create)"
TGrep.new gR p1 x1
gR.ignoreCase = 1
gR.maxCount = 7
gR.include = '*.c'
gR.recursive = 1
TGrep.new gR p2 x2                 # no delete in between — _data is NOT cleared
clean=1
[[ "$(gR.ignoreCase)" == "0" ]] || clean=0
[[ "$(gR.maxCount)" == "" ]]     || clean=0
[[ "$(gR.include)" == "" ]]      || clean=0
[[ "$(gR.recursive)" == "0" ]]   || clean=0
[[ "$(gR.pattern)" == "p2" ]]    || clean=0
declare -n RP=gR_paths
arr_is RP x2 || clean=0
unset -n RP
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\`"
else
    kt_test_fail "ic='$(gR.ignoreCase)' mc='$(gR.maxCount)' inc='$(gR.include)' r='$(gR.recursive)' pat='$(gR.pattern)'"
fi

kt_test_start "\`delete\` removes \`_paths\`, \`_args\` AND \`_argv\` (the descendant destructor chains)"
declare -a W=()
gR.argv W >/dev/null
gR.delete
left=""
declare -p gR_paths >/dev/null 2>&1 && left+=" _paths"
declare -p gR_args  >/dev/null 2>&1 && left+=" _args"
declare -p gR_argv  >/dev/null 2>&1 && left+=" _argv"
declare -p gR_data  >/dev/null 2>&1 && left+=" _data"
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "\`argv\` RUNS NOTHING — not even a cmd that exists"
tg_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
TGrep.new gN pat f1
gN.cmd = tg_mark
W=()
rc=0
gN.argv W || rc=$?             # DIRECT, not `$( )`: a subshell would lose the fill
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "5" ]] && arr_is W tg_mark -e pat -- f1; then
    kt_test_pass "the 5-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
gN.delete

# ===========================================================================
kt_test_section "B. G1 — every flag, singly"
# ===========================================================================

# One instance, reset before each case, so a case can only show its own flag.
one() {   # one TITLE PROP VALUE WANTFLAG...
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset g1 pat f
    g1."$__p" = "$__v"
    check_argv "$__t" g1 grep "$@" -e pat -- f
}

reset g1 pat f
check_argv "G1: no option at all — \`grep -e PATTERN -- PATH\`" g1 grep -e pat -- f

one "G1: \`ignoreCase = 1\` -> -i"             ignoreCase        1 -i
one "G1: \`invert = 1\` -> -v"                 invert            1 -v
one "G1: \`wordRegexp = 1\` -> -w"             wordRegexp        1 -w
one "G1: \`lineRegexp = 1\` -> -x"             lineRegexp        1 -x
one "G1: \`fixed = 1\` -> -F"                  fixed             1 -F
one "G1: \`extended = 1\` -> -E"               extended          1 -E
one "G1: \`recursive = 1\` -> -r (never -R: a directory symlink is not followed)" \
                                               recursive         1 -r
one "G1: \`lineNumber = 1\` -> -n"             lineNumber        1 -n
one "G1: \`filesOnly = 1\` -> -l"              filesOnly         1 -l
one "G1: \`filesWithoutMatch = 1\` -> -L"      filesWithoutMatch 1 -L
one "G1: \`countOnly = 1\` -> -c"              countOnly         1 -c
one "G1: \`onlyMatching = 1\` -> -o"           onlyMatching      1 -o
one "G1: \`noFilename = 1\` -> -h"             noFilename        1 -h
one "G1: \`withFilename = 1\` -> -H"           withFilename      1 -H
one "G1: \`binary = 1\` -> -U (the only way to see a CR through grep, §2.6)" \
                                               binary            1 -U
one "G1: \`nullData = 1\` -> -z (NUL-terminated INPUT records)" nullData 1 -z
one "G1: \`nullOut = 1\` -> -Z"                nullOut           1 -Z

one "G1: \`maxCount = 3\` -> -m 3 as TWO words"    maxCount   3       -m 3
one "G1: \`include = '*.txt'\` -> --include=*.txt" include    '*.txt' '--include=*.txt'
one "G1: \`exclude = '*.o'\` -> --exclude=*.o"     exclude    '*.o'   '--exclude=*.o'
one "G1: \`excludeDir = '.git'\` -> --exclude-dir=.git" excludeDir '.git' '--exclude-dir=.git'

reset g1 pat f
g1.include = 'my docs/*.txt'
check_argv "G1: \`include = 'my docs/*.txt'\` is one word, unexpanded" g1 \
    grep '--include=my docs/*.txt' -e pat -- f

# ===========================================================================
kt_test_section "C. G1 — combinations, the pinned order, and the boolean rule"
# ===========================================================================

reset g2 pat f
g2.ignoreCase = 1
g2.lineNumber = 1
check_argv "G1: -i and -n together, in the pinned order" g2 grep -i -n -e pat -- f

reset g2 pat f
g2.lineNumber = 1
g2.ignoreCase = 1
check_argv "G1: the ORDER is buildArgv's, not the order the caller assigned in" g2 \
    grep -i -n -e pat -- f

reset g2 pat f
g2.extended = 1
g2.recursive = 1
g2.filesOnly = 1
g2.nullOut = 1
check_argv "G1: -E -r -l -Z — the classic 'list the files' shape" g2 \
    grep -E -r -l -Z -e pat -- f

reset g2 pat 'dir one' 'dir two'
g2.ignoreCase = 1
g2.invert = 1
g2.wordRegexp = 1
g2.lineRegexp = 1
g2.fixed = 1
g2.recursive = 1
g2.lineNumber = 1
g2.filesOnly = 1
g2.countOnly = 1
g2.onlyMatching = 1
g2.noFilename = 1
g2.maxCount = 5
g2.include = 'I*'
g2.exclude = 'E*'
g2.excludeDir = 'D*'
g2.binary = 1
g2.nullData = 1
g2.nullOut = 1
check_argv "G1: EVERYTHING on at once — the full pinned order, two paths" g2 \
    grep -i -v -w -x -F -r -n -l -c -o -h -m 5 \
    '--include=I*' '--exclude=E*' '--exclude-dir=D*' -U -z -Z \
    -e pat -- 'dir one' 'dir two'

reset g2 pat f
g2.extended = 1
g2.filesWithoutMatch = 1
g2.withFilename = 1
check_argv "G1: the other side of each pair — -E, -L, -H" g2 \
    grep -E -L -H -e pat -- f

kt_test_start "G1: a boolean is ON only for the exact string \`1\` (never \`(( x ))\`)"
allgood=1
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset g3 pat f
    g3.ignoreCase = "$v"
    GOT=()
    g3.argv GOT >/dev/null
    if ! arr_is GOT grep -e pat -- f; then
        allgood=0
        badv="$v -> $(arr_show GOT)"
        break
    fi
done
if [[ "$allgood" == "1" ]]; then
    kt_test_pass "'2', 'yes', 'true', 'on', '01', '-1', ' 1' and '1 ' are all OFF"
else
    kt_test_fail "$badv"
fi

# ===========================================================================
kt_test_section "D. G1 — \`-e\` always, \`--\` only with paths, extras in place"
# ===========================================================================

reset g4 pat
check_argv "G1: \`TGrep.new g PAT\` with no path is \`grep -e PAT\`" g4 grep -e pat

reset g4 pat 'a b'
check_argv "G1: one path -> \`-- 'a b'\` (a space is safe by construction)" g4 \
    grep -e pat -- 'a b'

reset g4 pat a b c
check_argv "G1: three paths, all after the one \`--\`" g4 grep -e pat -- a b c

reset g4 pat f
g4.addArg -a
check_argv "G1: an \`addArg\` extra lands AFTER \`-e PATTERN\` and BEFORE \`--\`" g4 \
    grep -e pat -a -- f

reset g4 pat f
g4.addArg --binary-files=text
g4.addArg -A 2
g4.ignoreCase = 1
check_argv "G1: several extras keep their order, still between \`-e PAT\` and \`--\`" g4 \
    grep -i -e pat --binary-files=text -A 2 -- f

reset g4 pat f
g4.addArg -a
g4.clearArgs
check_argv "G1: \`clearArgs\` empties the extras again" g4 grep -e pat -- f

reset g4 pat old1 old2
g4.paths new1 'new 2'
check_argv "G1: \`g.paths new1 'new 2'\` replaced both old paths" g4 \
    grep -e pat -- new1 'new 2'

reset g4 pat old1
g4.paths
check_argv "G1: \`g.paths\` with no argument is the stdin form" g4 grep -e pat

kt_test_start "G1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset g4 pat f
g4.ignoreCase = 1
declare -a W1=() W2=()
g4.argv W1 >/dev/null
g4.argv W2 >/dev/null
if arr_is W1 grep -i -e pat -- f && arr_is W2 grep -i -e pat -- f; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "G1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
g4.argv W3 >/dev/null
W3[1]="TAMPERED"
declare -n IV=g4_argv
if [[ "${IV[1]}" == "-i" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "g4_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "E. G2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset gE pat f
gE.cmd = ''
check_rc2 "G2: empty \`cmd\` is rc 2" "cmd is empty" gE

reset gE '' f
check_rc2 "G2: empty \`pattern\` is rc 2 (\`-e ''\` would match every line)" \
    "pattern is empty" gE

reset gE pat f
gE.fixed = 1
gE.extended = 1
check_rc2 "G2: \`fixed\` + \`extended\` (-F and -E) is rc 2" "fixed" gE

reset gE pat f
gE.filesOnly = 1
gE.filesWithoutMatch = 1
check_rc2 "G2: \`filesOnly\` + \`filesWithoutMatch\` (-l and -L) is rc 2" "filesOnly" gE

reset gE pat f
gE.noFilename = 1
gE.withFilename = 1
check_rc2 "G2: \`noFilename\` + \`withFilename\` (-h and -H) is rc 2" "noFilename" gE

kt_test_start "G2: a refused build leaves \`\${inst}_argv\` EMPTY, so nothing stale can run"
reset gE pat f
gE.argv GOT >/dev/null              # a good build first
gE.fixed = 1
gE.extended = 1
gE.argv GOT >/dev/null 2>&1 || :
declare -n EV=gE_argv
if (( ${#EV[@]} == 0 )); then
    kt_test_pass "the previous argv was discarded, not left for a sink to run"
else
    kt_test_fail "gE_argv=$(arr_show EV)"
fi
unset -n EV

kt_test_start "G2: each half of a refused pair on its OWN is fine"
ok=1
reset gE pat f; gE.fixed = 1;             gE.argv GOT >/dev/null || ok=0
reset gE pat f; gE.extended = 1;          gE.argv GOT >/dev/null || ok=0
reset gE pat f; gE.filesOnly = 1;         gE.argv GOT >/dev/null || ok=0
reset gE pat f; gE.filesWithoutMatch = 1; gE.argv GOT >/dev/null || ok=0
reset gE pat f; gE.noFilename = 1;        gE.argv GOT >/dev/null || ok=0
reset gE pat f; gE.withFilename = 1;      gE.argv GOT >/dev/null || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "only the COMBINATION is refused"
else
    kt_test_fail "a single flag was refused"
fi

# ===========================================================================
kt_test_section "F. G3 — maxCount goes through kk.isInt"
# ===========================================================================

reset gF pat f
gF.maxCount = abc
check_rc2 "G3: \`maxCount = abc\` is rc 2" "maxCount" gF

reset gF pat f
gF.maxCount = -1
check_rc2 "G3: \`maxCount = -1\` is rc 2 (grep 3.0 takes \`-m -1\` as 'no limit')" \
    "maxCount" gF

reset gF pat f
gF.maxCount = '1 2'
check_rc2 "G3: \`maxCount = '1 2'\` is rc 2 (not an int; never re-split into two words)" \
    "maxCount" gF

reset gF pat f
gF.maxCount = 0x10
check_rc2 "G3: \`maxCount = 0x10\` is rc 2 (kk.isInt takes digits only)" "maxCount" gF

reset gF pat f
gF.maxCount = 0
check_argv "G3: \`maxCount = 0\` is ACCEPTED (>= 0) and emits \`-m 0\`" gF \
    grep -m 0 -e pat -- f

reset gF pat f
gF.maxCount = 08
kt_test_start "G3: \`maxCount = 08\` emits \`-m 8\` (the normalised \$__KK_INT)"
GOT=()
gF.argv GOT >/dev/null
mc="$(gF.maxCount)"
if arr_is GOT grep -m 8 -e pat -- f && [[ "$mc" == "08" ]]; then
    kt_test_pass "argv has \`-m 8\`, the property still reads '08' (no write-back)"
else
    kt_test_fail "GOT=$(arr_show GOT) maxCount='$mc'"
fi

reset gF pat f
gF.maxCount = +5
kt_test_start "G3: \`maxCount = +5\` emits \`-m 5\`, the property still reads '+5'"
GOT=()
gF.argv GOT >/dev/null
mc="$(gF.maxCount)"
if arr_is GOT grep -m 5 -e pat -- f && [[ "$mc" == "+5" ]]; then
    kt_test_pass "normalised for grep, untouched on the instance"
else
    kt_test_fail "GOT=$(arr_show GOT) maxCount='$mc'"
fi

reset gF pat f
check_argv "G3: \`maxCount = ''\` (the default) emits NO \`-m\` at all" gF grep -e pat -- f

# ===========================================================================
kt_test_section "G. G4 — a flag-shaped pattern is data; the derived \`-0\` (§2.7)"
# ===========================================================================

reset gG -v f
check_argv "G4: pattern \`-v\` lands AFTER \`-e\` and is searched, not parsed" gG \
    grep -e -v -- f

reset gG --help f
check_argv "G4: pattern \`--help\` is data too" gG grep -e --help -- f

reset gG '-e' f
gG.invert = 1
check_argv "G4: pattern \`-e\` next to a real \`-v\` flag stays in its slot" gG \
    grep -v -e -e -- f

reset gG $'a\nb' f
check_argv "G4: a pattern with a NEWLINE is one word (grep's own multi-pattern form)" gG \
    grep -e $'a\nb' -- f

# --- the §2.7 derivation ---------------------------------------------------
# `-Z` is NUL TERMINATION only together with `-l`/`-L`; with `-c` and with
# normal output it only replaces the separator after the file name and the
# record still ends in `\n` (measured on grep 3.0: `a.txt\0 2\n`). Feeding those
# to TPipe's `-0` would mis-frame every record, so `buildArgv` DERIVES the
# sinks' `-0` instead of letting `nullOut` set it.

kt_test_start "§2.7: \`nullOut = 1\` + \`filesOnly = 1\` DERIVES \`nul = 1\` (the sinks get -0)"
reset gZ pat f
gZ.nullOut = 1
gZ.filesOnly = 1
GOT=()
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "1" ]] && arr_is GOT grep -l -Z -e pat -- f; then
    kt_test_pass "nul = 1 after buildArgv, argv has -l -Z"
else
    kt_test_fail "nul='$(gZ.nul)' GOT=$(arr_show GOT)"
fi

kt_test_start "§2.7: \`nullOut = 1\` + \`filesWithoutMatch = 1\` derives it too"
reset gZ pat f
gZ.nullOut = 1
gZ.filesWithoutMatch = 1
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "1" ]]; then
    kt_test_pass "nul = 1"
else
    kt_test_fail "nul='$(gZ.nul)'"
fi

kt_test_start "§2.7: \`nullOut = 1\` + \`countOnly = 1\` does NOT derive it (records stay \\n-framed)"
reset gZ pat f
gZ.nullOut = 1
gZ.countOnly = 1
GOT=()
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "0" ]] && arr_is GOT grep -c -Z -e pat -- f; then
    kt_test_pass "nul stays 0 — \`-c -Z\` writes \`name\\0count\\n\`"
else
    kt_test_fail "nul='$(gZ.nul)' GOT=$(arr_show GOT)"
fi

kt_test_start "§2.7: \`nullOut = 1\` alone (normal output) does NOT derive it"
reset gZ pat f
gZ.nullOut = 1
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "0" ]]; then
    kt_test_pass "nul stays 0"
else
    kt_test_fail "nul='$(gZ.nul)'"
fi

kt_test_start "§2.7: the derivation is IDEMPOTENT — dropping \`filesOnly\` takes \`-0\` back off"
reset gZ pat f
gZ.nullOut = 1
gZ.filesOnly = 1
gZ.argv GOT >/dev/null
first="$(gZ.nul)"
gZ.filesOnly = 0
gZ.argv GOT >/dev/null
second="$(gZ.nul)"
if [[ "$first" == "1" && "$second" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding (the \`_nulDerived\` bookkeeping)"
else
    kt_test_fail "first='$first' second='$second'"
fi

kt_test_start "§2.7: a MANUAL \`nul = 1\` with \`nullOut = 0\` is the caller's and survives"
reset gZ pat f
gZ.nul = 1
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "1" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(gZ.nul)'"
fi

kt_test_start "§2.7: a MANUAL \`nul = 1\` survives a non-deriving \`nullOut\`/\`countOnly\` build too"
reset gZ pat f
gZ.nul = 1
gZ.nullOut = 1
gZ.countOnly = 1
gZ.argv GOT >/dev/null
if [[ "$(gZ.nul)" == "1" ]]; then
    kt_test_pass "still the caller's 1"
else
    kt_test_fail "nul='$(gZ.nul)'"
fi

# P3-F1. The undo used to be one condition too coarse: `_nulDerived` was claimed
# whenever the derivation CONDITION held, even when `nul` was already 1 because
# the CALLER set it — so the next build that stopped deriving took the caller's
# own `nul` down to 0 with it. The guard is "claim it only if we really set it",
# and this case is the sequence that needs all three steps.
kt_test_start "§2.7 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset gZ pat f
gZ.nul = 1                      # the caller's own framing decision
gZ.nullOut   = 1
gZ.filesOnly = 1
gZ.argv GOT >/dev/null          # derives: the condition holds, but nul was already 1
mid="$(gZ.nul)" middrv="$(gZ._nulDerived)"
gZ.filesOnly = 0
gZ.argv GOT >/dev/null          # stops deriving: must NOT clear the caller's nul
end="$(gZ.nul)" enddrv="$(gZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through -lZ and back; _nulDerived never claimed it"
else
    kt_test_fail "after -lZ: nul='$mid' _nulDerived='$middrv'; after filesOnly=0: nul='$end' _nulDerived='$enddrv'"
fi

kt_test_start "§2.7: \`crlf\` is never touched by buildArgv"
reset gZ pat f
gZ.crlf = 1
gZ.nullOut = 1
gZ.filesOnly = 1
gZ.argv GOT >/dev/null
if [[ "$(gZ.crlf)" == "1" ]]; then
    kt_test_pass "crlf = 1 kept"
else
    kt_test_fail "crlf='$(gZ.crlf)'"
fi

gA.delete
g1.delete
g2.delete
g3.delete
g4.delete
gE.delete
gF.delete
gG.delete
gZ.delete
