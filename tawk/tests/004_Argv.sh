#!/bin/bash
# 004_Argv.sh — tawk P0: the argv model (tawk/PLAN.md §1.2, §2.1–§2.4; pinned
# facts A1–A4).
#
# THIS FILE NEVER RUNS gawk. Every option is pinned by comparing the ARRAY that
# `a.argv NAME` hands over, byte for byte, against the argv the plan spells out:
#
#   gawk [--sandbox] [-F FS] [-v RS=\0 -v ORS=\0] [-v BINMODE=3]
#        [-i /usr/share/awk/inplace.awk [-v inplace::suffix=SFX]]
#        [EXTRA OPTIONS] [-v NAME=enc(VALUE) ...] [-e program] [-e chunk ...]
#        [-f FILE] [-- PATH...]
#
# so it is the fast half of the suite and it holds on a box without gawk. The
# behavioural half is `005_Run.sh`.
#
# Sections:
#   A  A3  lifecycle — every declared var in `${inst}_data` after `new` (incl.
#          `sandbox=1`), `_args` EMPTY after `TAwk.new a PROGRAM PATH`, `_paths`
#          right, `_progs`/`_vnames`/`_vvals` EMPTY INDEXED arrays, a reused
#          name starting clean, `delete` freeing all six arrays, `argv` running
#          nothing, and both out-name registries (`__taw_*`, `a_progs`,
#          `a_vnames`, `a_vvals` refused, the lists intact)
#   B  A1  every option SINGLY
#   C  A1  combinations; `program` then the `addProgram` list; empty chunks
#          never emitted; `-f` last; `--` iff paths; extras after the typed
#          options and BEFORE the setVar words; setVar insertion order, in-place
#          replacement and the encoding; the boolean rule; fail-closed sandbox
#   D  A2  the rc 2 list of §2.2 incl. every deny-list spelling (short, long,
#          any prefix, attached, bundled, `-W` attached / separate /
#          abbreviated / bundled), `--`, a non-option extra, a bare `-`, a
#          dangling `-v` / `--assign` / `-W`, the BINMODE-disabling options only
#          while binary mode is derived; and the extras that PASS
#   E  A4  `nullData` -> `nul` (the four-state P3-F1 sequence) and the derived
#          `BINMODE=3` (the `binary` property never written)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tawk.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: TAwk — typed options to argv, nothing executed (P0)"

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
BS='\'
IPA=/usr/share/awk/inplace.awk
P='{print}'

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
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == "Error: TAwk.buildArgv: "*"$__want"* ]] \
       && arr_is GOT stale-1 stale-2 && (( ${#__iv[@]} == 0 )); then
        kt_test_pass "rc 2, RESULT '', array untouched, \${inst}_argv empty, one line: ${DBG_1:0:80}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' got=$(arr_show GOT) instArgv=$(arr_show __iv)"
    fi
}

# reset INST [PROGRAM [PATH...]] — a fresh instance under the same name. `.new`
# over a LIVE instance does not clear `${inst}_data`, so this doubles as a
# standing check that `Create` assigns every var.
reset() {
    TAwk.new "$1" "${@:2}"
}

# ===========================================================================
kt_test_section "A. A3 lifecycle — Create assigns every var, the arrays are right"
# ===========================================================================

TA_VARS=( program programFile fieldSep nullData binary sandbox inPlace backupSuffix _nulDerived )
TU_VARS=( cmd crlf nul _lastRc subshellOk )

kt_test_start "A3: every declared var is present in \`\${inst}_data\` right after \`new\`"
TAwk.new aA "$P" f.txt
missing=""
decl="$(declare -p aA_data 2>&1)"
for v in "${TA_VARS[@]}" "${TU_VARS[@]}"; do
    if [[ "$decl" != *"[$v]="* ]]; then
        missing+=" $v"
    fi
done
if [[ -z "$missing" ]]; then
    kt_test_pass "all ${#TA_VARS[@]} + ${#TU_VARS[@]} vars bound (none unbound under set -u)"
else
    kt_test_fail "missing:$missing"
fi

kt_test_start "A3: the documented defaults — program = arg 1, sandbox 1, the rest 0/'', cmd gawk, _lastRc -1"
bad=""
[[ "$(aA.program)" == "$P" ]]     || bad+=" program='$(aA.program)'"
for v in programFile fieldSep backupSuffix; do
    got="$(aA."$v")"
    [[ "$got" == "" ]] || bad+=" $v='$got'"
done
for v in nullData binary inPlace _nulDerived crlf nul subshellOk; do
    got="$(aA."$v")"
    [[ "$got" == "0" ]] || bad+=" $v='$got'"
done
[[ "$(aA.sandbox)" == "1" ]]  || bad+=" sandbox='$(aA.sandbox)'"
[[ "$(aA.cmd)" == "gawk" ]]   || bad+=" cmd='$(aA.cmd)'"
[[ "$(aA._lastRc)" == "-1" ]] || bad+=" _lastRc='$(aA._lastRc)'"
if [[ -z "$bad" ]]; then
    kt_test_pass "every default as documented; sandbox ON (owner Q1); subshellOk inherited 0"
else
    kt_test_fail "$bad"
fi

kt_test_start "A3: \`\${a}_args\` is EMPTY after \`TAwk.new a PROGRAM PATH\` (the \`inherited\` trap)"
if declare -p aA_args >/dev/null 2>&1 && arr_is aA_args; then
    kt_test_pass "args empty — neither PROGRAM nor the path leaked into TUtil"
else
    kt_test_fail "aA_args=$(declare -p aA_args 2>&1)"
fi

kt_test_start "A3: \`_paths\` holds every argument after PROGRAM verbatim; \`_progs\`, \`_vnames\`, \`_vvals\` are EMPTY INDEXED arrays"
TAwk.new aP "$P" 'a b' '-dash' $'nl\nname' '-'
dx="$(declare -p aP_progs 2>&1)"
dn="$(declare -p aP_vnames 2>&1)"
dv="$(declare -p aP_vvals 2>&1)"
if declare -p aP_paths >/dev/null 2>&1 && arr_is aP_paths 'a b' '-dash' $'nl\nname' '-' \
   && [[ "$dx" == "declare -a aP_progs=()" && "$dn" == "declare -a aP_vnames=()" && "$dv" == "declare -a aP_vvals=()" ]]; then
    kt_test_pass "4 paths, no doubling; $dx; $dn; $dv"
else
    kt_test_fail "paths=$(declare -p aP_paths 2>&1) progs='$dx' vnames='$dn' vvals='$dv'"
fi
aP.delete

kt_test_start "A3: \`TAwk.new a\` with NO argument — program '', no path, no chunk, no variable"
TAwk.new aD
if declare -p aD_paths >/dev/null 2>&1 && arr_is aD_paths && arr_is aD_progs && arr_is aD_vnames && arr_is aD_vvals \
   && [[ "$(aD.program)" == "" && "$(aD.cmd)" == "gawk" ]]; then
    kt_test_pass "empty paths, progs, vnames, vvals; program ''; cmd gawk"
else
    kt_test_fail "paths=$(declare -p aD_paths 2>&1) program='$(aD.program)' cmd='$(aD.cmd)'"
fi
aD.delete

kt_test_start "A3: a REUSED instance name starts clean (every var and all four lists re-assigned)"
TAwk.new aR 'old' x1
aR.fieldSep = ':'
aR.sandbox = 0
aR.inPlace = 1
aR.backupSuffix = .bak
aR.programFile = p.awk
aR.addProgram 'BEGIN{}' 'END{}'
aR.setVar x 1
TAwk.new aR 'new' x2                  # no delete in between — _data is NOT cleared
clean=1
[[ "$(aR.program)" == "new" ]]        || clean=0
[[ "$(aR.fieldSep)" == "" ]]          || clean=0
[[ "$(aR.sandbox)" == "1" ]]          || clean=0
[[ "$(aR.inPlace)" == "0" ]]          || clean=0
[[ "$(aR.backupSuffix)" == "" ]]      || clean=0
[[ "$(aR.programFile)" == "" ]]       || clean=0
arr_is aR_paths x2                    || clean=0
arr_is aR_progs                       || clean=0
arr_is aR_vnames                      || clean=0
arr_is aR_vvals                       || clean=0
if [[ "$clean" == "1" ]]; then
    kt_test_pass "no state survived the second \`new\`"
else
    kt_test_fail "program='$(aR.program)' sandbox='$(aR.sandbox)' inPlace='$(aR.inPlace)' progs=$(arr_show aR_progs) vnames=$(arr_show aR_vnames)"
fi

kt_test_start "A3: \`delete\` removes \`_paths\`, \`_progs\`, \`_vnames\`, \`_vvals\`, \`_args\`, \`_argv\` and \`_data\`"
declare -a W=()
aR.setVar y 2
aR.argv W >/dev/null 2>&1 || :
aR.delete
left=""
for a in _paths _progs _vnames _vvals _args _argv _data; do
    declare -p "aR$a" >/dev/null 2>&1 && left+=" $a"
done
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

kt_test_start "A3: \`argv\` RUNS NOTHING — not even a cmd that exists"
taw_mark() { : > "$FLAG"; printf 'x\n'; }
rm -f "$FLAG"
TAwk.new aN "$P" f.txt
aN.cmd = taw_mark
W=()
rc=0
aN.argv W || rc=$?
if [[ $rc -eq 0 && ! -e "$FLAG" && "$RESULT" == "6" ]] && arr_is W taw_mark --sandbox -e "$P" -- f.txt; then
    kt_test_pass "the 6-word argv was built, the command never ran"
else
    kt_test_fail "rc=$rc flag=$([[ -e $FLAG ]] && echo present || echo absent) RESULT='$RESULT' W=$(arr_show W)"
fi
aN.delete

# --- A3: the two out-name registries (PLAN §2.1) ---------------------------
bad_out() {   # bad_out TITLE MEMBER NAME
    kt_test_start "$1"
    local __m="$2" __n="$3"
    RESULT="sentinel"
    dbg_n aA."$__m" "$__n"
    if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 \
          && "$DBG_1" == *"bad output array name"* && "$DBG_1" == *"$__n"* ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${DBG_1:0:70}"
    else
        kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1'"
    fi
}

aA.addProgram 'END{print NR}' 'BEGIN{}'
aA.setVar x 1
aA.setVar y two
bad_out "A3: \`a.argv __taw_v\` is rc 2 (the TAwk local prefix)"                argv    __taw_v
bad_out "A3: \`a.argv __taw_x\` is rc 2"                                       argv    __taw_x
bad_out "A3: \`a.toArray __taw_a\` is rc 2 — refused BEFORE anything runs"     toArray __taw_a
bad_out "A3: \`a.argv aA_progs\` is rc 2 (the \`_progs\` suffix)"               argv    aA_progs
bad_out "A3: \`a.toArray aA_progs\` is rc 2 (records would become the next program)" toArray aA_progs
bad_out "A3: \`a.argv aA_vnames\` is rc 2 (the \`_vnames\` suffix)"             argv    aA_vnames
bad_out "A3: \`a.toArray aA_vnames\` is rc 2"                                  toArray aA_vnames
bad_out "A3: \`a.argv aA_vvals\` is rc 2 (the \`_vvals\` suffix)"               argv    aA_vvals
bad_out "A3: \`a.toArray aA_vvals\` is rc 2"                                   toArray aA_vvals
bad_out "A3: \`a.argv aA_paths\` is rc 2 (still refused through the registry)" argv    aA_paths
bad_out "A3: \`a.argv aA_args\` is rc 2"                                       argv    aA_args
bad_out "A3: \`a.argv TUTIL_OUT_SUFFIXES\` is rc 2 (the registry's own NAME)"  argv    TUTIL_OUT_SUFFIXES
bad_out "A3: \`a.argv TUTIL_OUT_PREFIXES\` is rc 2"                           argv    TUTIL_OUT_PREFIXES

kt_test_start "A3: the program, chunk and variable lists are INTACT after every refusal above"
if arr_is aA_progs 'END{print NR}' 'BEGIN{}' && arr_is aA_vnames x y && arr_is aA_vvals 1 two \
   && [[ "$(aA.program)" == "$P" ]]; then
    kt_test_pass "progs = $(arr_show aA_progs), vnames = $(arr_show aA_vnames), vvals = $(arr_show aA_vvals)"
else
    kt_test_fail "progs=$(arr_show aA_progs) vnames=$(arr_show aA_vnames) vvals=$(arr_show aA_vvals) program='$(aA.program)'"
fi

kt_test_start "A3: both registries extended — \`__taw_\` and \`_progs _vnames _vvals\` registered exactly once"
if arr_is TUTIL_OUT_PREFIXES __tu_ __tg_ __th_ __tt_ __taw_ \
   && arr_is TUTIL_OUT_SUFFIXES _args _argv _paths _progs _vnames _vvals; then
    kt_test_pass "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
else
    kt_test_fail "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
fi

kt_test_start "A3: sourcing tawk twice appends NOTHING (idempotent)"
source "$UNIT"
source "$UNIT"
if arr_is TUTIL_OUT_PREFIXES __tu_ __tg_ __th_ __tt_ __taw_ \
   && arr_is TUTIL_OUT_SUFFIXES _args _argv _paths _progs _vnames _vvals; then
    kt_test_pass "five prefixes, six suffixes"
else
    kt_test_fail "prefixes = $(arr_show TUTIL_OUT_PREFIXES); suffixes = $(arr_show TUTIL_OUT_SUFFIXES)"
fi

kt_test_start "A3: an ordinary out-name still fills after every refusal"
declare -a OKARR=()
rc=0
aA.argv OKARR || rc=$?
if [[ $rc -eq 0 ]] && arr_is OKARR gawk --sandbox -v x=1 -v y=two -e "$P" -e 'END{print NR}' -e 'BEGIN{}' -- f.txt; then
    kt_test_pass "argv=$(arr_show OKARR)"
else
    kt_test_fail "rc=$rc OKARR=$(arr_show OKARR)"
fi

# ===========================================================================
kt_test_section "B. A1 — every option, singly"
# ===========================================================================

one() {   # one TITLE PROP VALUE WANT...  (on `new a1 '{print}' f.txt`)
    local __t="$1" __p="$2" __v="$3"; shift 3
    reset a1 "$P" f.txt
    a1."$__p" = "$__v"
    check_argv "$__t" a1 "$@"
}

reset a1 "$P" f.txt
check_argv "A1: no option at all — \`gawk --sandbox -e PROGRAM -- PATH\` (sandbox by default)" a1 \
    gawk --sandbox -e "$P" -- f.txt

one "A1: \`sandbox = 0\` drops \`--sandbox\`"          sandbox  0   gawk -e "$P" -- f.txt
one "A1: \`fieldSep = :\` -> \`-F :\` (two words)"      fieldSep :   gawk --sandbox -F : -e "$P" -- f.txt
one "A1: \`fieldSep\` with a space stays ONE word"      fieldSep ' , ' gawk --sandbox -F ' , ' -e "$P" -- f.txt
one "A1: \`nullData = 1\` -> RS/ORS NUL AND the derived BINMODE=3" nullData 1 \
    gawk --sandbox -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -e "$P" -- f.txt
one "A1: \`binary = 1\` -> \`-v BINMODE=3\`"            binary   1   gawk --sandbox -v BINMODE=3 -e "$P" -- f.txt
one "A1: \`programFile = p.awk\` -> \`-f\` AFTER the program" programFile p.awk \
                                                         gawk --sandbox -e "$P" -f p.awk -- f.txt

kt_test_start "A1: the NUL words are the four bytes \`RS=\\0\` / \`ORS=\\0\` (a real backslash, for gawk to process)"
reset a1 "$P" f.txt
a1.nullData = 1
GOT=()
a1.argv GOT >/dev/null 2>&1 || :
if [[ "${GOT[3]:-}" == "RS=${BS}0" && "${GOT[5]:-}" == "ORS=${BS}0" && ${#GOT[3]} -eq 5 && ${#GOT[5]} -eq 6 ]]; then
    kt_test_pass "$(printf '%q %q' "${GOT[3]}" "${GOT[5]}")"
else
    kt_test_fail "GOT=$(arr_show GOT)"
fi

reset a1 "$P" f.txt
a1.sandbox = 0
a1.inPlace = 1
check_argv "A1: \`inPlace = 1\` (sandbox 0) -> BINMODE=3, then the inplace include by ABSOLUTE path" a1 \
    gawk -v BINMODE=3 -i "$IPA" -e "$P" -- f.txt

reset a1 "$P" f.txt
a1.sandbox = 0
a1.inPlace = 1
a1.backupSuffix = .bak
check_argv "A1: \`backupSuffix = .bak\` -> \`-v inplace::suffix=.bak\` right after the include" a1 \
    gawk -v BINMODE=3 -i "$IPA" -v inplace::suffix=.bak -e "$P" -- f.txt

reset a1 "$P" f.txt
a1.sandbox = 0
a1.inPlace = 1
a1.backupSuffix = ' my bak'
check_argv "A1: a suffix with a space stays ONE argv word" a1 \
    gawk -v BINMODE=3 -i "$IPA" -v 'inplace::suffix= my bak' -e "$P" -- f.txt

# backupSuffix goes through the SAME enc() as setVar (reviewer ruling on P0,
# question 6): `-v` escape-processes it, so it is encoded to arrive verbatim.
sfx_case() {   # sfx_case TITLE SUFFIX WANT_WORD
    reset a1 "$P" f.txt
    a1.sandbox = 0
    a1.inPlace = 1
    a1.backupSuffix = "$2"
    check_argv "$1" a1 gawk -v BINMODE=3 -i "$IPA" -v "inplace::suffix=$3" -e "$P" -- f.txt
}
sfx_case "A1 enc: a backslash in \`backupSuffix\` is doubled"          ".b${BS}k"       ".b${BS}${BS}k"
sfx_case "A1 enc: \`backupSuffix\` \`\\t\` (two bytes) stays two bytes" ".${BS}t"        ".${BS}${BS}t"
sfx_case "A1 enc: a LEADING \`@\` in \`backupSuffix\` -> \`\\100\`"      "@bak"           "${BS}100bak"
sfx_case "A1 enc: a newline in \`backupSuffix\` -> \`\\n\`"              $'.a\nb'         ".a${BS}nb"
sfx_case "A1 enc: a plain \`backupSuffix\` is unchanged"                ".orig~"         ".orig~"

kt_test_start "A1 enc: the STORED \`backupSuffix\` stays verbatim"
reset a1 "$P" f.txt
a1.backupSuffix = ".b${BS}k"
if [[ "$(a1.backupSuffix)" == ".b${BS}k" ]]; then
    kt_test_pass "$(printf '%q' "$(a1.backupSuffix)")"
else
    kt_test_fail "backupSuffix=$(printf '%q' "$(a1.backupSuffix)")"
fi

reset a1 '' f.txt
a1.programFile = p.awk
check_argv "A1: \`programFile\` ALONE (program '') — no \`-e\` at all" a1 \
    gawk --sandbox -f p.awk -- f.txt

reset a1 "$P"
check_argv "A1: no path — no \`--\` (gawk reads stdin)" a1 gawk --sandbox -e "$P"

reset a1 "$P" '-weird' '-' 'a b'
check_argv "A1: paths after \`--\`, verbatim — \`-weird\`, \`-\` (stdin) and a space" a1 \
    gawk --sandbox -e "$P" -- '-weird' '-' 'a b'

reset a1 "$P" ./k=v ./a::b=v 1x=v 'é=v' x.y=v C:/x=y "C:${BS}x=y" /abs/k=v =v
check_argv "A1: paths that are NOT assignments pass verbatim (\`./k=v\`, \`1x=v\`, \`é=v\`, \`x.y=v\`, \`C:/x=y\`, …)" a1 \
    gawk --sandbox -e "$P" -- ./k=v ./a::b=v 1x=v 'é=v' x.y=v C:/x=y "C:${BS}x=y" /abs/k=v =v

reset a1 "$P" f.txt
a1.setVar x 1
check_argv "A1: \`setVar x 1\` -> \`-v x=1\` before the program" a1 \
    gawk --sandbox -v x=1 -e "$P" -- f.txt

# ===========================================================================
kt_test_section "C. A1 — the chunks, the extras, the variables, the pinned order"
# ===========================================================================

reset a2 'E0' f.txt
a2.addProgram 'E1'
a2.addProgram 'E2' 'E3'
check_argv "A1: \`program\` FIRST, then every \`addProgram\` chunk in call order" a2 \
    gawk --sandbox -e E0 -e E1 -e E2 -e E3 -- f.txt

reset a2 '' f.txt
a2.addProgram 'X1' 'X2'
check_argv "A1: \`program = ''\` means NONE — only the list is emitted" a2 \
    gawk --sandbox -e X1 -e X2 -- f.txt

reset a2 'E0' f.txt
a2.addProgram '' 'X1' ''
check_argv "A1: an EMPTY chunk is NEVER emitted (gawk drops \`-e ''\` with a warning)" a2 \
    gawk --sandbox -e E0 -e X1 -- f.txt

reset a2 ' ' f.txt
check_argv "A1: a whitespace program is a real (empty) program and IS emitted" a2 \
    gawk --sandbox -e ' ' -- f.txt

reset a2 'BEGIN{' f.txt
a2.addProgram $'x=1\nprint x}'
check_argv "A1: a chunk holding a newline is ONE word" a2 \
    gawk --sandbox -e 'BEGIN{' -e $'x=1\nprint x}' -- f.txt

reset a2 'E0' f.txt
a2.addProgram 'E1' 'E2'
a2.clearPrograms
check_argv "A1: \`clearPrograms\` empties the list and keeps \`program\`" a2 \
    gawk --sandbox -e E0 -- f.txt

reset a2 'E0' f.txt
a2.addProgram
check_argv "A1: \`addProgram\` with no argument is a no-op" a2 gawk --sandbox -e E0 -- f.txt

reset a2 'E0' f.txt
a2.programFile = p.awk
a2.addProgram 'E1'
check_argv "A1: \`-f\` comes after ALL the chunks" a2 \
    gawk --sandbox -e E0 -e E1 -f p.awk -- f.txt

reset a2 'E0' f.txt
a2.setVar x 1
a2.addArg --lint
a2.fieldSep = :
check_argv "A1: an extra lands AFTER the typed options and BEFORE the setVar words" a2 \
    gawk --sandbox -F : --lint -v x=1 -e E0 -- f.txt

reset a2 'E0' f.txt
a2.addArg -v x=extra
a2.setVar x mine
check_argv "A1: \`setVar x\` comes after an \`addArg -v x=…\` (so it wins in gawk)" a2 \
    gawk --sandbox -v x=extra -v x=mine -e E0 -- f.txt

reset a2 'E0' f.txt
a2.addArg --lint=fatal
a2.addArg -n -v a=1
check_argv "A1: several extras keep their order and their words" a2 \
    gawk --sandbox --lint=fatal -n -v a=1 -e E0 -- f.txt

reset a2 'E0' f.txt
a2.addArg -n
a2.clearArgs
check_argv "A1: \`clearArgs\` empties the extras again" a2 gawk --sandbox -e E0 -- f.txt

reset a2 'E0' old1 old2
a2.paths new1 'new 2'
check_argv "A1: \`a.paths new1 'new 2'\` replaced both old paths" a2 \
    gawk --sandbox -e E0 -- new1 'new 2'

reset a2 'E0' old1
a2.paths
check_argv "A1: \`a.paths\` with NO argument is the stdin form — no \`--\`" a2 gawk --sandbox -e E0

reset a2 'E0' f.txt
a2.setVar b 1
a2.setVar a 2
a2.setVar c 3
check_argv "A1: setVar words in INSERTION order (not hash order)" a2 \
    gawk --sandbox -v b=1 -v a=2 -v c=3 -e E0 -- f.txt

reset a2 'E0' f.txt
a2.setVar b 1
a2.setVar a 2
a2.setVar b 9
check_argv "A1: a repeated NAME replaces its value IN PLACE (the slot is kept)" a2 \
    gawk --sandbox -v b=9 -v a=2 -e E0 -- f.txt

kt_test_start "A1: a repeated NAME keeps ONE slot in \`_vnames\` / \`_vvals\`"
if arr_is a2_vnames b a && arr_is a2_vvals 9 2; then
    kt_test_pass "vnames = $(arr_show a2_vnames), vvals = $(arr_show a2_vvals)"
else
    kt_test_fail "vnames = $(arr_show a2_vnames), vvals = $(arr_show a2_vvals)"
fi

reset a2 'E0' f.txt
a2.setVar b 1
a2.clearVars
check_argv "A1: \`clearVars\` empties the variables" a2 gawk --sandbox -e E0 -- f.txt

kt_test_start "A1: \`_vnames\` / \`_vvals\` are empty after \`clearVars\`"
if arr_is a2_vnames && arr_is a2_vvals; then
    kt_test_pass "both empty"
else
    kt_test_fail "vnames = $(arr_show a2_vnames), vvals = $(arr_show a2_vvals)"
fi

# enc(VALUE): every backslash doubled, every newline written `\n`, a leading
# `@` written `\100` (PLAN §2.3). The STORED value stays verbatim.
enc_case() {   # enc_case TITLE VALUE WANT_WORD
    local __t="$1" __v="$2" __w="$3"
    reset a3 'E0' f.txt
    a3.setVar x "$__v"
    check_argv "$__t" a3 gawk --sandbox -v "x=$__w" -e E0 -- f.txt
}

enc_case "A1 enc: a plain value is unchanged"                     'hello world'       'hello world'
enc_case "A1 enc: an empty value -> \`x=\`"                          ''                  ''
enc_case "A1 enc: one backslash is doubled"                        "a${BS}tb"          "a${BS}${BS}tb"
enc_case "A1 enc: two backslashes become four"                     "a${BS}${BS}b"      "a${BS}${BS}${BS}${BS}b"
enc_case "A1 enc: a trailing backslash is doubled"                 "end${BS}"          "end${BS}${BS}"
enc_case "A1 enc: a newline is written \`\\n\`"                     $'l1\nl2'           "l1${BS}nl2"
enc_case "A1 enc: backslash + newline -> \`\\\\\\n\`"              "b${BS}"$'\n'"c"    "b${BS}${BS}${BS}nc"
enc_case "A1 enc: a LEADING \`@\` is written \`\\100\`"             '@/foo/'            "${BS}100/foo/"
enc_case "A1 enc: a lone \`@\` -> \`\\100\`"                        '@'                 "${BS}100"
enc_case "A1 enc: an \`@\` NOT leading is unchanged"                'a@b'               'a@b'
enc_case "A1 enc: quotes, \`\$\`, \`&\` and UTF-8 pass unchanged"    "\$'\"&é中"          "\$'\"&é中"

kt_test_start "A1 enc: the STORED value stays verbatim (\`_vvals\` holds the caller's bytes)"
reset a3 'E0' f.txt
a3.setVar x "a${BS}b"$'\n'"@c"
if arr_is a3_vvals "a${BS}b"$'\n'"@c"; then
    kt_test_pass "vvals = $(arr_show a3_vvals)"
else
    kt_test_fail "vvals = $(arr_show a3_vvals)"
fi

reset a2 'E0' p1 'p 2'
a2.sandbox = 0
a2.fieldSep = :
a2.nullData = 1
a2.binary = 1
a2.inPlace = 1
a2.backupSuffix = .bak
a2.programFile = 'my prog.awk'
a2.addArg --lint -v y=2
a2.setVar x 1
a2.addProgram 'X1' 'X2'
check_argv "A1: EVERYTHING at once — the full pinned order, ONE \`BINMODE=3\`" a2 \
    gawk -F : -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -i "$IPA" -v inplace::suffix=.bak \
    --lint -v y=2 -v x=1 -e E0 -e X1 -e X2 -f 'my prog.awk' -- p1 'p 2'

kt_test_start "A1: a boolean is ON only for the exact string \`1\` (never \`(( x ))\`) — nullData, binary, inPlace"
allgood=1
badv=""
for v in 2 yes true on TRUE -1 '1 ' ' 1' 01 '' 0; do
    reset a4 'E0' f.txt
    a4.sandbox = 0
    for p in nullData binary inPlace; do
        a4."$p" = "$v"
    done
    GOT=()
    a4.argv GOT >/dev/null 2>&1 || :
    if ! arr_is GOT gawk -e E0 -- f.txt; then
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

# `sandbox` FAILS CLOSED (owner Q1): `--sandbox` is omitted ONLY for the exact
# string `0`.
sbx() {   # sbx VALUE WANT...
    local __v="$1"; shift
    reset a4 'E0' f.txt
    a4.sandbox = "$__v"
    check_argv "A1 (Q1, fail closed): \`sandbox = $(printf '%q' "$__v")\` -> $( [[ "$1 $2" == "gawk --sandbox" ]] && printf 'SANDBOXED' || printf 'open' )" a4 "$@"
}

sbx ''      gawk --sandbox -e E0 -- f.txt
sbx yes     gawk --sandbox -e E0 -- f.txt
sbx 2       gawk --sandbox -e E0 -- f.txt
sbx ' 0'    gawk --sandbox -e E0 -- f.txt
sbx '0 '    gawk --sandbox -e E0 -- f.txt
sbx 00      gawk --sandbox -e E0 -- f.txt
sbx false   gawk --sandbox -e E0 -- f.txt
sbx off     gawk --sandbox -e E0 -- f.txt
sbx -0      gawk --sandbox -e E0 -- f.txt
sbx 1       gawk --sandbox -e E0 -- f.txt
sbx 0       gawk -e E0 -- f.txt

kt_test_start "A1: rebuilding does not ACCUMULATE — two \`argv\` calls agree"
reset a2 'E0' f.txt
a2.addProgram E1
a2.setVar x 1
declare -a W1=() W2=()
a2.argv W1 >/dev/null 2>&1 || :
a2.argv W2 >/dev/null 2>&1 || :
if arr_is W1 gawk --sandbox -v x=1 -e E0 -e E1 -- f.txt && arr_is W2 gawk --sandbox -v x=1 -e E0 -e E1 -- f.txt; then
    kt_test_pass "stable across rebuilds"
else
    kt_test_fail "W1=$(arr_show W1) W2=$(arr_show W2)"
fi

kt_test_start "A1: \`argv\` hands over a COPY — writing it does not touch \`\${inst}_argv\`"
declare -a W3=()
a2.argv W3 >/dev/null 2>&1 || :
W3[1]="TAMPERED"
declare -n IV=a2_argv
if [[ "${IV[1]:-}" == "--sandbox" ]]; then
    kt_test_pass "the instance's own argv is intact"
else
    kt_test_fail "a2_argv=$(arr_show IV)"
fi
unset -n IV

# ===========================================================================
kt_test_section "D. A2 — the rc 2 list: nothing runs, RESULT '', one line"
# ===========================================================================

reset aE "$P" f.txt
aE.cmd = ''
check_rc2 "A2: empty \`cmd\` is rc 2" "cmd is empty" aE

reset aE '' f.txt
check_rc2 "A2: NO program at all (program '', no chunk, no programFile) is rc 2" "no program" aE

reset aE '' f.txt
aE.addProgram '' ''
check_rc2 "A2: only EMPTY chunks is 'no program' too (they are never emitted)" "no program" aE

reset aE '' f.txt
aE.addProgram E1
aE.clearPrograms
check_rc2 "A2: no program after \`clearPrograms\` is rc 2 too" "no program" aE

reset aE ''
check_rc2 "A2: no program and no path is rc 2" "no program" aE

reset aE '' f.txt
aE.programFile = '-'
check_rc2 "A2: \`programFile = -\` is rc 2 (gawk would read the program from stdin)" "programFile '-'" aE

reset aE "$P" f.txt
aE.programFile = '-'
check_rc2 "A2: \`programFile = -\` is rc 2 with a program too" "programFile '-'" aE

apath() {   # apath TITLE PATH...
    local __t="$1"; shift
    reset aE "$P" "$@"
    check_rc2 "$__t" "looks like an awk assignment" aE
    kt_test_start "$__t — the line names the \`./\` spelling"
    if [[ "$DBG_1" == *"./"* ]]; then
        kt_test_pass "${DBG_1:0:90}"
    else
        kt_test_fail "first='$DBG_1'"
    fi
}

apath "A2: the path \`k=v\` is an ASSIGNMENT to gawk — rc 2"                   k=v
apath "A2: a namespaced \`a::b=v\` is an assignment too — rc 2"               a::b=v
apath "A2: \`awk::x=v\` — rc 2"                                               awk::x=v
apath "A2: \`_x=\` (empty value) — rc 2"                                      _x=
apath "A2: \`Name_9=a=b\` — rc 2"                                             Name_9=a=b
apath "A2: an assignment AFTER a good path — rc 2"                            good.txt k=v

reset aE "$P"
aE.sandbox = 0
aE.inPlace = 1
check_rc2 "A2: \`inPlace = 1\` with NO path is rc 2" "inPlace = 1 with no path" aE

reset aE "$P" '-'
aE.sandbox = 0
aE.inPlace = 1
check_rc2 "A2: \`inPlace = 1\` with the path \`-\` is rc 2" "inPlace = 1 with the path '-'" aE

reset aE "$P" good.txt '-'
aE.sandbox = 0
aE.inPlace = 1
check_rc2 "A2: \`inPlace = 1\` with \`-\` ANYWHERE in the paths is rc 2" "inPlace = 1 with the path '-'" aE

reset aE "$P" f.txt
aE.inPlace = 1
check_rc2 "A2 (Q4): \`inPlace = 1\` with the DEFAULT sandbox is rc 2" "inPlace = 1 needs sandbox = 0" aE

for sv in 1 '' yes 00 ' 0'; do
    reset aE "$P" f.txt
    aE.inPlace = 1
    aE.sandbox = "$sv"
    check_rc2 "A2 (Q4): \`inPlace = 1\` with \`sandbox = $(printf '%q' "$sv")\` is rc 2 (fail closed)" "inPlace = 1 needs sandbox = 0" aE
done

reset aE "$P" f.txt
aE.backupSuffix = .bak
check_rc2 "A2: \`backupSuffix\` with \`inPlace = 0\` is rc 2" "backupSuffix" aE

reset aE "$P" f.txt
aE.sandbox = 0
aE.backupSuffix = .bak
check_rc2 "A2: \`backupSuffix\` with \`inPlace = 0\` and sandbox 0 is rc 2 too" "backupSuffix" aE

# --- setVar: the NAME is validated at the call (nothing stored) AND at build
setvar_bad() {   # setvar_bad TITLE WANT_SUBSTR NAME
    local __t="$1" __w="$2" __n="$3"
    kt_test_start "$__t"
    reset aV "$P" f.txt
    aV.setVar keep 1
    dbg_n aV.setVar "$__n" 5
    if [[ "$DBG_RC" == "2" && $DBG_N -eq 1 && "$DBG_1" == "Error: TAwk.setVar: "*"$__w"* ]] \
       && arr_is aV_vnames keep && arr_is aV_vvals 1; then
        kt_test_pass "rc 2, nothing stored: ${DBG_1:0:80}"
    else
        kt_test_fail "rc=$DBG_RC lines=$DBG_N first='$DBG_1' vnames=$(arr_show aV_vnames) vvals=$(arr_show aV_vvals)"
    fi
}

setvar_bad "A2: \`setVar ''\` — rc 2"                         "not an awk identifier" ''
setvar_bad "A2: \`setVar 1x\` — rc 2"                         "not an awk identifier" 1x
setvar_bad "A2: \`setVar x.y\` — rc 2"                        "not an awk identifier" x.y
setvar_bad "A2: \`setVar 'a b'\` — rc 2"                      "not an awk identifier" 'a b'
setvar_bad "A2: \`setVar a::b\` (namespaced) — rc 2"          "not an awk identifier" a::b
setvar_bad "A2: \`setVar é\` — rc 2"                          "not an awk identifier" é
setvar_bad "A2: \`setVar x=\` — rc 2"                         "not an awk identifier" x=
for kw in BEGIN END BEGINFILE ENDFILE function func if else while for do break continue next nextfile \
          exit return delete getline print printf in switch case default; do
    setvar_bad "A2: \`setVar $kw\` (a keyword) — rc 2"         "keyword or gawk builtin" "$kw"
done
for bi in and asort asorti atan2 bindtextdomain close compl cos dcgettext dcngettext exp fflush gensub \
          gsub index int isarray length log lshift match mkbool mktime or patsplit rand rshift sin \
          split sprintf sqrt srand strftime strtonum sub substr system systime tolower toupper typeof xor; do
    setvar_bad "A2: \`setVar $bi\` (a builtin) — rc 2"         "keyword or gawk builtin" "$bi"
done
for ar in ENVIRON PROCINFO SYMTAB FUNCTAB; do
    setvar_bad "A2: \`setVar $ar\` (a gawk array) — rc 2"      "gawk array" "$ar"
done

kt_test_start "A2: \`setVar\` with ONE argument or THREE is rc 2 (usage), nothing stored"
reset aV "$P" f.txt
dbg_n aV.setVar x
r1="$DBG_RC/$DBG_N/$DBG_1"
dbg_n aV.setVar x 1 2
r2="$DBG_RC/$DBG_N/$DBG_1"
if [[ "$r1" == "2/1/Error: TAwk.setVar: usage"* && "$r2" == "2/1/Error: TAwk.setVar: usage"* ]] \
   && arr_is aV_vnames && arr_is aV_vvals; then
    kt_test_pass "both rc 2, one line each"
else
    kt_test_fail "one arg: '$r1'; three: '$r2'; vnames=$(arr_show aV_vnames)"
fi

setvar_ok() {   # setvar_ok NAME
    reset aV "$P" f.txt
    aV.setVar "$1" v
    check_argv "A2: \`setVar $1\` PASSES" aV gawk --sandbox -v "$1=v" -e "$P" -- f.txt
}
setvar_ok x
setvar_ok _y
setvar_ok NR
setvar_ok FS
setvar_ok awk
setvar_ok Func_9
setvar_ok BEGINX

reset aV "$P" f.txt
aV.setVar good 1
aV_vnames+=( 'bad name' )
aV_vvals+=( 2 )
check_rc2 "A2: a bad NAME written into \`_vnames\` BY HAND is refused at build" "variable name" aV

reset aV "$P" f.txt
aV_vnames+=( ENVIRON )
aV_vvals+=( 2 )
check_rc2 "A2: \`ENVIRON\` written into \`_vnames\` by hand is refused at build" "variable name" aV

# --- the deny-list over the extras (PLAN §2.2) ------------------------------
# deny SUBSTR WORD... — the extras, on their own, are rc 2 and the line names
# the option as gawk reads it (its canonical long name).
deny() {
    local __w="$1"; shift
    reset aE "$P" f.txt
    aE.addArg "$@"
    check_rc2 "A2 (deny): \`addArg $(printf '%q ' "$@")\` is rc 2 — gawk's $__w" "gawk's $__w" aE
}

# short, separate argument
deny --source          -e "$P"
deny --file            -f p.awk
deny --include         -i inplace
deny --load            -l ext
deny --exec            -E p.awk
deny --field-separator -F :
deny --sandbox         -S
deny --pretty-print    -o
deny --gen-pot         -g
deny --help            -h
deny --version         -V
deny --copyright       -C
deny --dump-variables  -d
deny --profile         -p
deny --debug           -D
deny --bignum          -M
# short, attached argument
deny --source          "-e$P"
deny --file            -fp.awk
deny --include         -iinplace
deny --load            -lext
deny --field-separator -F:
deny --pretty-print    -oout.awk
deny --dump-variables  -dvars.txt
deny --profile         -pprof.txt
deny --debug           -Dcmds.txt
# short, bundled
deny --sandbox         -bS
deny --bignum          -nM
deny --pretty-print    -bo
deny --source          "-be$P"
deny --file            -nfp.awk
deny --include         -Niinplace
# long, full name
deny --source          "--source=$P"
deny --source          --source "$P"
deny --file            --file=p.awk
deny --file            --file p.awk
deny --include         --include=inplace
deny --load            --load=ext
deny --exec            --exec=p.awk
deny --field-separator --field-separator=:
deny --sandbox         --sandbox
deny --pretty-print    --pretty-print
deny --pretty-print    --pretty-print=out.awk
deny --gen-pot         --gen-pot
deny --help            --help
deny --usage           --usage
deny --version         --version
deny --copyright       --copyright
deny --dump-variables  --dump-variables
deny --profile         --profile=prof.txt
deny --debug           --debug
deny --bignum          --bignum
# long, any prefix (never decided per version)
deny --source          --so=x
deny --sandbox         --sa
deny --source          --s
deny --file            --fi=p.awk
deny --file            --f
deny --include         --inc=inplace
deny --include         --i
deny --load            --lo=ext
deny --load            --l
deny --exec            --ex=p.awk
deny --exec            --e
deny --field-separator --fie=:
deny --pretty-print    --pr
deny --pretty-print    --p
deny --gen-pot         --g
deny --help            --h
deny --usage           --us
deny --usage           --u
deny --version         --v
deny --version         --ver
deny --copyright       --co
deny --copyright       --c
deny --dump-variables  --du
deny --dump-variables  --d
deny --debug           --de
deny --bignum          --b
deny --bignum          --big
deny --source          --=x
# -W long options: attached, separate, abbreviated, bundled
deny --source          -W "source=$P"
deny --source          "-Wsource=$P"
deny --source          -W "so=$P"
deny --source          "-Wso=$P"
deny --sandbox         -W sandbox
deny --sandbox         -Wsa
deny --source          -W s
deny --version         -W version
deny --version         -Wv
deny --exec            -W exec=p.awk
deny --include         -W include=inplace
deny --load            -Wload=ext
deny --debug           -W de
deny --source          -bW "source=$P"
deny --source          "-bWsource=$P"
deny --sandbox         -nW sandbox

# the BINMODE-disabling options, only while binary mode is derived
denyb() {   # denyb SUBSTR PROP WORD...
    local __w="$1" __p="$2"; shift 2
    reset aE "$P" f.txt
    if [[ "$__p" == "inPlace" ]]; then
        aE.sandbox = 0
    fi
    aE."$__p" = 1
    aE.addArg "$@"
    check_rc2 "A2 (deny, $__p = 1): \`addArg $(printf '%q ' "$@")\` is rc 2 — gawk's $__w disables BINMODE" "gawk's $__w" aE
}
denyb --posix       binary   -P
denyb --posix       binary   --posix
denyb --posix       binary   --po
denyb --posix       binary   -W posix
denyb --posix       binary   -Wpo
denyb --posix       binary   -bP
denyb --traditional binary   -c
denyb --traditional binary   --traditional
denyb --traditional binary   --tr
denyb --traditional binary   --t
denyb --traditional binary   -W traditional
denyb --traditional binary   -Wt
denyb --traditional binary   -nc
denyb --posix       nullData -P
denyb --traditional nullData --traditional
denyb --posix       inPlace  --posix
denyb --traditional inPlace  -c

# -- among the extras
reset aE "$P" f.txt
aE.addArg --
check_rc2 "A2: \`addArg --\` is rc 2 — \`--\` ends gawk's options" "ends gawk's options" aE

reset aE "$P" f.txt
aE.addArg -n -- --lint
check_rc2 "A2: \`--\` in the MIDDLE of the extras is rc 2 too" "ends gawk's options" aE

# a non-option extra becomes THE program (gawk stops parsing at it)
nonopt() {   # nonopt WORD...
    reset aE "$P" f.txt
    aE.addArg "$@"
    check_rc2 "A2: \`addArg $(printf '%q ' "$@")\` is rc 2 — a non-option word would become THE program" "is not an option word" aE
}
nonopt x
nonopt "$P"
nonopt ''
nonopt -
nonopt k=v
nonopt -n stray
nonopt --lint 'BEGIN{}'

# an argument-taking option as the LAST extra would swallow the next word
dangle() {   # dangle WORD...
    reset aE "$P" f.txt
    aE.addArg "$@"
    check_rc2 "A2: \`addArg $(printf '%q ' "$@")\` (dangling) is rc 2" "takes an argument" aE
}
dangle -v
dangle --assign
dangle --as
dangle --a
dangle -W
dangle -bv
dangle -bW
dangle -W assign
dangle -W as
dangle -Was
dangle -v x=1 -v

kt_test_start "A2: a denied word NOT first among the extras is refused too"
reset aE "$P" f.txt
aE.addArg -n
aE.addArg --lint -S
GOT=( stale-1 stale-2 )
RESULT="sentinel"
dbg_n aE.argv GOT
declare -n EV=aE_argv
if [[ "$DBG_RC" == "2" && "$RESULT" == "" && $DBG_N -eq 1 && "$DBG_1" == *"gawk's --sandbox"* ]] \
   && arr_is GOT stale-1 stale-2 && (( ${#EV[@]} == 0 )); then
    kt_test_pass "the whole extras list is scanned: ${DBG_1:0:70}"
else
    kt_test_fail "rc=$DBG_RC RESULT='$RESULT' lines=$DBG_N first='$DBG_1' instArgv=$(arr_show EV)"
fi
unset -n EV

kt_test_start "A2: the argument of \`-v\` is NOT scanned as an option (\`-v -S=1\` is a value, not \`--sandbox\`)"
reset aE "$P" f.txt
aE.addArg -v e=-S
rc=0
GOT=()
aE.argv GOT 2>/dev/null || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT gawk --sandbox -v e=-S -e "$P" -- f.txt; then
    kt_test_pass "$(arr_show GOT)"
else
    kt_test_fail "rc=$rc GOT=$(arr_show GOT)"
fi

pass_extra() {   # pass_extra WORD...
    reset aE "$P" f.txt
    aE.addArg "$@"
    check_argv "A2: \`addArg $(printf '%q ' "$@")\` PASSES" aE \
        gawk --sandbox "$@" -e "$P" -- f.txt
}

pass_extra -v x=1
pass_extra -vx=1
pass_extra --assign=x=1
pass_extra --assign x=1
pass_extra --as x=1
pass_extra -W assign=x=1
pass_extra -W assign x=1
pass_extra -Wassign=x=1
pass_extra -bv x=1
pass_extra -nvx=1
pass_extra --lint
pass_extra --lint=fatal
pass_extra -L
pass_extra -Lfatal
pass_extra --lint-old
pass_extra -n
pass_extra -N
pass_extra -O
pass_extra -r
pass_extra -s
pass_extra -t
pass_extra -b
pass_extra --characters-as-bytes
pass_extra --ch
pass_extra --non-decimal-data
pass_extra --nostalgia
pass_extra --optimize
pass_extra --no-optimize
pass_extra --re-interval
pass_extra --use-lc-numeric
pass_extra --trace
pass_extra --csv
pass_extra -W lint
pass_extra -Wlint=fatal

# the BINMODE-disabling options PASS while binary mode is NOT derived
pass_extra -P
pass_extra --posix
pass_extra -c
pass_extra --traditional
pass_extra --tr
pass_extra -W posix

kt_test_start "A2: each refused ingredient on its OWN is fine"
ok=1
reset aE "$P" f.txt; aE.sandbox = 0; aE.inPlace = 1;                         aE.argv GOT >/dev/null 2>&1 || ok=0
reset aE "$P" f.txt; aE.sandbox = 0; aE.inPlace = 1; aE.backupSuffix = .b;   aE.argv GOT >/dev/null 2>&1 || ok=0
reset aE "$P" '-';                                                           aE.argv GOT >/dev/null 2>&1 || ok=0
reset aE '' f.txt; aE.programFile = p.awk;                                   aE.argv GOT >/dev/null 2>&1 || ok=0
reset aE '' f.txt; aE.addProgram '' 'X';                                     aE.argv GOT >/dev/null 2>&1 || ok=0
reset aE "$P" ./k=v;                                                         aE.argv GOT >/dev/null 2>&1 || ok=0
if [[ "$ok" == "1" ]]; then
    kt_test_pass "inPlace with sandbox 0, a suffix with inPlace, \`-\` without inPlace, -f alone, a non-empty chunk, ./k=v — all build"
else
    kt_test_fail "a legal shape was refused"
fi

# ===========================================================================
kt_test_section "E. A4 — \`nullData\` derives \`-0\` (P3-F1), and the derived \`BINMODE=3\`"
# ===========================================================================

kt_test_start "A4: \`nullData = 1\` DERIVES \`nul = 1\`"
reset aZ "$P" f.txt
aZ.nullData = 1
GOT=()
rc=0
aZ.argv GOT || rc=$?
if [[ $rc -eq 0 && "$(aZ.nul)" == "1" && "$(aZ._nulDerived)" == "1" ]] \
   && arr_is GOT gawk --sandbox -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -e "$P" -- f.txt; then
    kt_test_pass "nul = 1, _nulDerived = 1, argv has the NUL words and BINMODE=3"
else
    kt_test_fail "rc=$rc nul='$(aZ.nul)' drv='$(aZ._nulDerived)' GOT=$(arr_show GOT)"
fi

kt_test_start "A4: \`nullData = 0\` again takes the derived \`-0\` back off"
aZ.nullData = 0
aZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(aZ.nul)" == "0" && "$(aZ._nulDerived)" == "0" ]]; then
    kt_test_pass "1 -> 0 when the condition stops holding"
else
    kt_test_fail "nul='$(aZ.nul)' drv='$(aZ._nulDerived)'"
fi

kt_test_start "A4: a MANUAL \`nul = 1\` with \`nullData = 0\` is the caller's and survives"
reset aZ "$P" f.txt
aZ.nul = 1
aZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(aZ.nul)" == "1" && "$(aZ._nulDerived)" == "0" ]]; then
    kt_test_pass "buildArgv never clears what it did not set"
else
    kt_test_fail "nul='$(aZ.nul)' drv='$(aZ._nulDerived)'"
fi

kt_test_start "A4 (P3-F1): a deriving build does not CLAIM a \`nul = 1\` the caller already set"
reset aZ "$P" f.txt
aZ.nul = 1
aZ.nullData = 1
aZ.argv GOT >/dev/null 2>&1 || :
mid="$(aZ.nul)" middrv="$(aZ._nulDerived)"
aZ.nullData = 0
aZ.argv GOT >/dev/null 2>&1 || :
end="$(aZ.nul)" enddrv="$(aZ._nulDerived)"
if [[ "$mid" == "1" && "$middrv" == "0" && "$end" == "1" && "$enddrv" == "0" ]]; then
    kt_test_pass "nul stays the caller's 1 through nullData and back; _nulDerived never claimed it"
else
    kt_test_fail "after nullData: nul='$mid' drv='$middrv'; after nullData=0: nul='$end' drv='$enddrv'"
fi

kt_test_start "A4: a REFUSED build derives nothing (the rc 2 path never reaches the rule)"
reset aZ '' f.txt                     # no program -> rc 2
aZ.nullData = 1
aZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(aZ.nul)" == "0" && "$(aZ._nulDerived)" == "0" ]]; then
    kt_test_pass "nul untouched on the rc 2 path"
else
    kt_test_fail "nul='$(aZ.nul)' drv='$(aZ._nulDerived)'"
fi

# derived_bin TITLE PROP — PROP = 1 shows `-v BINMODE=3` with `binary` still 0;
# PROP = 0 again removes it.
derived_bin() {
    local __t="$1" __p="$2"
    kt_test_start "$__t"
    reset aB "$P" f.txt
    aB.sandbox = 0
    aB."$__p" = 1
    local -a __g1=() __g2=()
    aB.argv __g1 >/dev/null 2>&1 || :
    local __bin1; __bin1="$(aB.binary)"
    aB."$__p" = 0
    aB.argv __g2 >/dev/null 2>&1 || :
    local __bin2; __bin2="$(aB.binary)"
    local __has1=0 __has2=0 __w
    for __w in "${__g1[@]}"; do [[ "$__w" == "BINMODE=3" ]] && __has1=$(( __has1 + 1 )); done
    for __w in "${__g2[@]}"; do [[ "$__w" == "BINMODE=3" ]] && __has2=$(( __has2 + 1 )); done
    if [[ "$__has1" == "1" && "$__has2" == "0" && "$__bin1" == "0" && "$__bin2" == "0" ]] \
       && arr_is __g2 gawk -e "$P" -- f.txt; then
        kt_test_pass "on: $(arr_show __g1)| off: $(arr_show __g2)| binary stayed 0"
    else
        kt_test_fail "on=$(arr_show __g1) off=$(arr_show __g2) binary='$__bin1'/'$__bin2'"
    fi
}

derived_bin "A4: \`inPlace = 1\` derives \`BINMODE=3\`, \`binary\` stays 0, and \`inPlace = 0\` takes it away" inPlace
derived_bin "A4: \`nullData = 1\` derives \`BINMODE=3\` the same way" nullData

reset aB "$P" f.txt
aB.sandbox = 0
aB.binary = 1
aB.inPlace = 1
aB.nullData = 1
check_argv "A4: \`binary\` + \`inPlace\` + \`nullData\` — still exactly ONE \`BINMODE=3\`" aB \
    gawk -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -i "$IPA" -e "$P" -- f.txt

reset aB "$P" f.txt
aB.sandbox = 0
aB.binary = 1
aB.inPlace = 1
aB.inPlace = 0
check_argv "A4: a caller's own \`binary = 1\` survives \`inPlace\` going 1 -> 0" aB \
    gawk -v BINMODE=3 -e "$P" -- f.txt

kt_test_start "A4: \`crlf\` is never touched by buildArgv"
reset aZ "$P" f.txt
aZ.sandbox = 0
aZ.crlf = 1
aZ.nullData = 1
aZ.inPlace = 1
aZ.argv GOT >/dev/null 2>&1 || :
if [[ "$(aZ.crlf)" == "1" && "$(aZ.binary)" == "0" ]]; then
    kt_test_pass "crlf = 1 kept, binary 0"
else
    kt_test_fail "crlf='$(aZ.crlf)' binary='$(aZ.binary)'"
fi

for d in aA a1 a2 a3 a4 aE aV aZ aB; do
    "$d".delete 2>/dev/null || :
done
