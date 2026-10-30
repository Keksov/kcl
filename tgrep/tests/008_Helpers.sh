#!/usr/bin/env bash
# 008_Helpers.sh — tgrep H2: `quiet` (-q), `TGrep.contains`, `TGrep.countMatching`
# (kcl/docs/dev/tutil/HELPERS_PLAN.md §3; launch task L6.0). The pattern is H1's
# (`tsed/tests/008_Helpers.sh`).
#
# The ORACLE for every behavioural case is the bare GNU tool run on the same
# fixture — never a second call into the code under test. The fixture tree is
# built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework
# tears it down; this file installs NO `trap … EXIT` of its own. CR fixtures are
# written with `printf`, never through an array literal (tutil README trap 18).
#
# THE GATE IS THE FIRST CASE, as in 005 (`kt_gnu_gate grep GREP_BIN`, ktool): with
# no GNU grep every case that runs grep is a loud `SKIP: <ktool's reason>`, so the
# case COUNT is the same either way. Section B0 never runs grep: a recording stub
# GNU grep (`kt_gnu_stub` + a script that writes its argv to a file) pins the
# argv the two statics build, on every box.
#
# Sections:
#   Z   the ktool gate and the fixture tree
#   B0  the statics' argv, pinned by a recording stub (grep never runs):
#       `-F -r -q -e TEXT -- PATH...` and `-F -r -h -e TEXT -- PATH...`
#   A   `quiet` against the real tool: `run` prints nothing, every sink sees zero
#       records (`count` -> 0), the rc is the answer; legal with -l/-c/-o; the
#       measured `-q` + failing-operand rc (a match wins over a failed operand)
#   B   `TGrep.contains`: rc 0 / 1, silent, literal (-F), recursive, several
#       paths, CRLF, binary, a leading `-`; a tool error is rc 1 + ONE line
#       (never rc 2); rc 2 only for a malformed call (usage, empty TEXT) with
#       stdin untouched and exactly one line
#   C   `TGrep.countMatching`: RESULT through the `count` sink (direct call
#       silent, `$( )` once), the named deviation (rc 1 with the real count),
#       no `file:count` parsing, a binary file is ONE record, rc 2 paths
#   D   nested calls from inside an outer sink's callback, the throw-away
#       instance is deleted, `quiet` in the lifecycle, `set -eu` predicates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tgrep.sh"
source "$UNIT"
source "$UNIT_DIR/../tutil/tests/gnu_helper.sh" || exit 1

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/h.err"

kt_test_section "008: TGrep — the helpers (H2): quiet, contains, countMatching"

# ===========================================================================
kt_test_section "Z. the ktool gate, and the fixture tree"
# ===========================================================================

kt_gnu_gate grep GREP_BIN

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: $GNU_WHY"
        return 1
    fi
    return 0
}

# tcaseT TITLE — tcase, and the case also needs timeout(1): without
# timeout/gtimeout it passes as `SKIP: $KT_TIMEOUT_WHY` (launch L5.4-9).
tcaseT() {
    tcase "$1" || return 1
    if ! kt_need_timeout; then
        kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
        return 1
    fi
    return 0
}

# The grep the real-tool sections run; the recording stub of B0 is selected
# only inside B0 and is gone afterwards.
if [[ -v KCL_GNU_GREP ]]; then H_KGS_SET=1; H_KGS=$KCL_GNU_GREP; else H_KGS_SET=0; H_KGS=''; fi
use_real() {
    if [[ "$H_KGS_SET" == 1 ]]; then KCL_GNU_GREP=$H_KGS; else unset -v KCL_GNU_GREP; fi
    ktool.gnu grep >/dev/null || :     # re-warm ktool's cache in the main shell (an override change re-keys it)
}

printf -v CR '\r'
printf -v NL '\n'

# --- the trees --------------------------------------------------------------
# FX: 8 lines hold `needle` in total (plain 2, spaced 1, dash 1, deep 1, colon 2,
# crlf 1); other.txt holds none. MX: literal-text cases. BX: ONE binary file.
FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/sub"
printf 'alpha needle here\nbeta\nneedle again\n'  > "$FX/plain.txt"
printf 'gamma\nneedle in spaced\n'                > "$FX/with space.txt"
printf 'needle dash\n'                            > "$FX/-dash.txt"
printf 'needle:3\nneedle:4\n'                     > "$FX/colon.txt"
printf 'needle crlf\r\nsecond\r\n'                > "$FX/crlf.txt"
printf 'nothing here at all\n'                    > "$FX/other.txt"
printf 'needle deep\n'                            > "$FX/sub/deep.txt"

MX="$(cd "$(kt_fixture_tmpdir_create meta)" && pwd)"
printf 'a.b\naXb\na.b a.b\n'                      > "$MX/m.txt"
printf 'aXb\n'                                    > "$MX/x.txt"
printf 'x [y] z\n'                                > "$MX/br.txt"
printf 'cost $5\nsecond\n'                        > "$MX/lf.txt"
printf 'say -v loudly\nplain\n'                   > "$MX/flag.txt"

BX="$(cd "$(kt_fixture_tmpdir_create bin)" && pwd)"
printf 'needle bin\n\000\001binary\n'             > "$BX/bin.dat"

kt_test_start "the fixture trees are in place"
need_ok=1
for f in plain.txt 'with space.txt' -dash.txt colon.txt crlf.txt other.txt sub/deep.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
for f in m.txt x.txt br.txt lf.txt flag.txt; do
    [[ -f "$MX/$f" ]] || need_ok=0
done
[[ -f "$BX/bin.dat" ]] || need_ok=0
if [[ "$need_ok" == "1" && "$(od -c < "$FX/crlf.txt" | head -1)" == *'\r'* ]]; then
    kt_test_pass "FX=$FX MX=$MX BX=$BX"
else
    kt_test_fail "a fixture entry is missing"
fi

# ---------------------------------------------------------------------------
# helpers — every local uses a `__z` prefix so none can shadow the unit's
# `__tg_*` scratch namerefs.
# ---------------------------------------------------------------------------

arr_is() {
    local -n __za="$1"; shift
    local __zi=0 __ze
    if (( ${#__za[@]} != $# )); then
        return 1
    fi
    for __ze in "$@"; do
        if [[ "${__za[$__zi]}" != "$__ze" ]]; then
            return 1
        fi
        __zi=$(( __zi + 1 ))
    done
    return 0
}

arr_show() {
    local -n __za="$1"
    if (( ${#__za[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__za[@]}"
}

# tg_dbg COMMAND... — the switch ON, stderr SPLIT: TG_N/TG_1 are OUR lines
# (`Error:`/`Warning:`), TOOL_N/TOOL_1 grep's own. stdout is discarded.
TG_RC=0; TG_N=0; TG_1=''; TOOL_N=0; TOOL_1=''
tg_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TG_RC=$?
    VERBOSE_KKLASS=
    TG_N=0; TOOL_N=0; TG_1=''; TOOL_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TG_N=$(( TG_N + 1 ))
                if [[ -z "$TG_1" ]]; then TG_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 ))
                if [[ -z "$TOOL_1" ]]; then TOOL_1="$__zl"; fi
                ;;
        esac
    done < "$ERRF"
    return 0
}

# sil COMMAND... — a DIRECT call (no subshell), stdout and stderr to files:
# S_RC, and S_OUT / S_ERR = 1 when that stream got any byte. RESULT survives.
S_RC=0; S_OUT=0; S_ERR=0
sil() {
    "$@" >"$TMP/s.out" 2>"$TMP/s.err"
    S_RC=$?
    S_OUT=0; S_ERR=0
    if [[ -s "$TMP/s.out" ]]; then S_OUT=1; fi
    if [[ -s "$TMP/s.err" ]]; then S_ERR=1; fi
    return 0
}

# stdin_kept COMMAND... — run it with a here-string on stdin; STDIN_RC and
# STDIN_OUT = "<stdout>|<what the here-string still holds>". A grep that read
# stdin would eat the line.
STDIN_RC=0; STDIN_OUT=''
stdin_kept() {
    STDIN_OUT="$( { "$@" 2>/dev/null; printf 'rc=%s|' "$?"; IFS= read -r __zl; printf '%s' "$__zl"; } <<< 'stdin-kept' )"
    STDIN_RC=${STDIN_OUT#*rc=}
    STDIN_RC=${STDIN_RC%%|*}
}

declare -a GOT=()
declare -a WANT=()
CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

class THTestList
    public
        var         N
        constructor Create
        proc        Add
end
THTestList.Create() { N=0; return 0; }
THTestList.Add()    { N=$(( N + 1 )); return 0; }
build THTestList

# oracle_n ARGS... — the bare tool's line count for `grep ARGS`.
oracle_n() {
    local -a __zr=()
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        __zr+=( "$__zl" )
    done < <( "$GREP_BIN" "$@" 2>/dev/null )
    ORACLE_N=${#__zr[@]}
}

# ===========================================================================
kt_test_section "B0. the statics' argv, pinned by a recording stub (grep never runs)"
# ===========================================================================

# A fake GNU grep that records its argv NUL-framed and prints two lines. It is
# selected through KCL_GNU_GREP (a SHELL variable: `$( )` sees it, a child
# process does not) and unselected right after this section.
REC="$TMP/rec.argv"
kt_gnu_stub grep "$TMP/stubdir" STUB_GREP || { echo "008: kt_gnu_stub failed" >&2; exit 1; }
printf '%s\n' '#!/bin/sh' \
    "case \$1 in --version) printf '%s\\n' 'grep (GNU grep) 3.11'; exit 0;; esac" \
    "printf '%s\\000' \"\$@\" > '$REC'" \
    "printf '%s\\n' one two" \
    'exit 0' > "$STUB_GREP"
chmod +x "$STUB_GREP"

rec_of() {   # rec_of COMMAND... -> WANT = the argv the stub saw (without word 0)
    rm -f "$REC"
    "$@" >/dev/null 2>&1 || :
    WANT=()
    if [[ -f "$REC" ]]; then
        mapfile -d '' -t WANT < "$REC"
    fi
}

kt_test_start "B0: \`TGrep.contains TEXT PATH...\` -> \`-F -r -q -e TEXT -- PATH...\`"
ktool.gnu grep >/dev/null || :
rec_of TGrep.contains 'a.b' 'dir one' "$TMP/two"
if arr_is WANT -F -r -q -e 'a.b' -- 'dir one' "$TMP/two"; then
    kt_test_pass "$(arr_show WANT)"
else
    kt_test_fail "got $(arr_show WANT)"
fi

kt_test_start "B0: \`TGrep.countMatching TEXT PATH...\` -> \`-F -r -h -e TEXT -- PATH...\` (the \`count\` sink, no -c)"
rec_of TGrep.countMatching 'a.b' 'dir one' "$TMP/two"
if arr_is WANT -F -r -h -e 'a.b' -- 'dir one' "$TMP/two"; then
    kt_test_pass "$(arr_show WANT)"
else
    kt_test_fail "got $(arr_show WANT)"
fi

kt_test_start "B0: a TEXT that starts with \`-\` travels as \`-e TEXT\` (data), after the flags"
rec_of TGrep.contains -v f1
a1=("${WANT[@]}")
rec_of TGrep.countMatching -v f1
if arr_is a1 -F -r -q -e -v -- f1 && arr_is WANT -F -r -h -e -v -- f1; then
    kt_test_pass "$(arr_show a1)| $(arr_show WANT)"
else
    kt_test_fail "contains $(arr_show a1)| countMatching $(arr_show WANT)"
fi

kt_test_start "B0: \`quiet = 1\` on an instance lands LAST among the flags (after -Z, before -e)"
TGrep.new gB0 pat f
gB0.quiet = 1
gB0.nullOut = 1
gB0.ignoreCase = 1
GOT=()
gB0.argv GOT
if arr_is GOT "$STUB_GREP" -i -Z -q -e pat -- f; then
    kt_test_pass "$(arr_show GOT)"
else
    kt_test_fail "got $(arr_show GOT)"
fi
gB0.delete

kt_test_start "B0: the usage refusals run NOTHING (the recording stub is never started)"
rm -f "$REC"
TGrep.contains onlytext >/dev/null 2>&1; r1=$?
TGrep.contains >/dev/null 2>&1; r2=$?
TGrep.countMatching onlytext >/dev/null 2>&1; r3=$?
TGrep.countMatching >/dev/null 2>&1; r4=$?
if [[ "$r1$r2$r3$r4" == "2222" && ! -e "$REC" ]]; then
    kt_test_pass "four rc 2, no process"
else
    kt_test_fail "rcs=$r1$r2$r3$r4 stub-ran=$([[ -e "$REC" ]] && echo yes || echo no)"
fi

use_real
rm -f "$REC"

# ===========================================================================
kt_test_section "A. quiet — the rc is the answer, every sink sees zero records"
# ===========================================================================

if tcase "A: \`quiet = 1\` + a match: \`run\` is rc 0, lastRc 0, prints NOTHING"; then
    TGrep.new gQ needle "$FX/plain.txt"
    gQ.quiet = 1
    sil gQ.run
    gQ.lastRc; lr="$RESULT"
    if [[ $S_RC -eq 0 && $S_OUT -eq 0 && $S_ERR -eq 0 && "$lr" == "0" ]]; then
        kt_test_pass "rc 0, lastRc 0, no stdout, no stderr"
    else
        kt_test_fail "rc=$S_RC out=$S_OUT err=$S_ERR lastRc=$lr"
    fi
    gQ.delete
fi

if tcase "A: \`quiet = 1\` and NO match: rc 1, lastRc 1, silent, no line of ours"; then
    TGrep.new gQ zzzabsent "$FX/plain.txt"
    gQ.quiet = 1
    tg_dbg gQ.run
    gQ.lastRc; lr="$RESULT"
    if [[ $TG_RC -eq 1 && "$lr" == "1" && $TG_N -eq 0 && $TOOL_N -eq 0 ]]; then
        kt_test_pass "rc 1 (an answer, not a failure), lastRc 1, nothing on stderr"
    else
        kt_test_fail "rc=$TG_RC lastRc=$lr ours=$TG_N tool=$TOOL_N"
    fi
    gQ.delete
fi

if tcase "A: every sink sees ZERO records under \`quiet\`: each, toArray, toList, count (RESULT 0), first"; then
    TGrep.new gQ needle "$FX/plain.txt"
    gQ.quiet = 1
    CB_RECS=()
    erc=0; gQ.each cb_collect || erc=$?
    GOT=( stale )
    arc=0; gQ.toArray GOT || arc=$?
    ar_res="$RESULT"
    THTestList.new gQL
    lrc=0; gQ.toList gQL || lrc=$?
    nl="$(gQL.N)"
    crc=0; gQ.count || crc=$?
    cn="$RESULT"
    frc=0; gQ.first || frc=$?
    fr="$RESULT"
    if [[ $erc -eq 0 && ${#CB_RECS[@]} -eq 0 && $arc -eq 0 && ${#GOT[@]} -eq 0 && "$ar_res" == "0" \
          && $lrc -eq 0 && "$nl" == "0" && $crc -eq 0 && "$cn" == "0" && $frc -eq 1 && -z "$fr" ]]; then
        kt_test_pass "each 0 / toArray 0 / toList 0 / count 0 (rc 0: the answer is the rc) / first rc 1 ''"
    else
        kt_test_fail "each rc=$erc n=${#CB_RECS[@]}; toArray rc=$arc n=${#GOT[@]} RESULT=$ar_res; toList rc=$lrc n=$nl; count rc=$crc n=$cn; first rc=$frc '$fr'"
    fi
    gQL.delete
    gQ.delete
fi

if tcase "A: \`quiet\` + NO match: \`count\` is RESULT 0 with rc 1 — the rc, not the number, is the answer"; then
    TGrep.new gQ zzzabsent "$FX/plain.txt"
    gQ.quiet = 1
    crc=0; gQ.count || crc=$?
    if [[ $crc -eq 1 && "$RESULT" == "0" ]]; then
        kt_test_pass "count rc 1, RESULT 0"
    else
        kt_test_fail "rc=$crc RESULT='$RESULT'"
    fi
    gQ.delete
fi

if tcase "A: \`quiet\` is LEGAL with -l, -c, -o, -n, -v: no rc 2, grep prints nothing, the sinks see zero records"; then
    bad=""
    for opt in filesOnly filesWithoutMatch countOnly onlyMatching lineNumber; do
        TGrep.new gQ needle "$FX/plain.txt"
        gQ.quiet = 1
        gQ."$opt" = 1
        GOT=( stale )
        arc=0; tg_dbg gQ.toArray GOT
        arc=$TG_RC
        # -L over a file that DOES match selects nothing: grep 3.0 exits 1 there
        # (3.5+ says 0); either way no rc 2, no record, no line of ours.
        if [[ $arc -ne 2 && ${#GOT[@]} -eq 0 && $TG_N -eq 0 ]]; then
            :
        else
            bad+=" $opt:rc=$arc,n=${#GOT[@]},ours=$TG_N"
        fi
        gQ.delete
    done
    TGrep.new gQ needle "$FX/plain.txt"
    gQ.quiet = 1
    gQ.invert = 1
    tg_dbg gQ.run
    inv_rc=$TG_RC
    gQ.delete
    if [[ -z "$bad" && $inv_rc -eq 0 ]]; then
        kt_test_pass "5 options x toArray: no rc 2, zero records; invert + quiet: rc 0 (a non-matching line exists)"
    else
        kt_test_fail "bad:$bad invert-rc=$inv_rc"
    fi
fi

# --- the measured -q + failing-operand rc (GNU grep 3.0) -----------------------
# `grep -q` exits 0 as soon as ONE match is found, even if another operand failed
# (before or after the match in the list); with no match anywhere, a failed
# operand is its usual 2 -> rc 1 + one line of ours.
if tcase "A: \`-q\`: a match then a MISSING operand — grep stops at the match: rc 0, lastRc 0, no line of ours, no tool line"; then
    TGrep.new gQ needle "$FX/plain.txt" "$FX/no_such"
    gQ.quiet = 1
    tg_dbg gQ.run
    gQ.lastRc; lr="$RESULT"
    if [[ $TG_RC -eq 0 && "$lr" == "0" && $TG_N -eq 0 && $TOOL_N -eq 0 ]]; then
        kt_test_pass "rc 0 lastRc 0 and grep never reached the missing operand"
    else
        kt_test_fail "rc=$TG_RC lastRc=$lr ours=$TG_N tool=$TOOL_N tool1='$TOOL_1'"
    fi
    gQ.delete
fi

if tcase "A: \`-q\`: a MISSING operand then a match — grep complains but still exits 0: rc 0, lastRc 0, no line of ours"; then
    TGrep.new gQ needle "$FX/no_such" "$FX/plain.txt"
    gQ.quiet = 1
    tg_dbg gQ.run
    gQ.lastRc; lr="$RESULT"
    if [[ $TG_RC -eq 0 && "$lr" == "0" && $TG_N -eq 0 && $TOOL_N -eq 1 && "$TOOL_1" == *"no_such"* ]]; then
        kt_test_pass "rc 0 lastRc 0; grep's own one complaint passes through: ${TOOL_1: -40}"
    else
        kt_test_fail "rc=$TG_RC lastRc=$lr ours=$TG_N tool=$TOOL_N tool1='$TOOL_1'"
    fi
    gQ.delete
fi

if tcase "A: \`-q\`: NO match and a MISSING operand — grep's 2: rc 1, lastRc 2, ONE line of ours"; then
    TGrep.new gQ zzzabsent "$FX/other.txt" "$FX/no_such"
    gQ.quiet = 1
    tg_dbg gQ.run
    gQ.lastRc; lr="$RESULT"
    if [[ $TG_RC -eq 1 && "$lr" == "2" && $TG_N -eq 1 && "$TG_1" == *"mapRc"* && $TOOL_N -eq 1 ]]; then
        kt_test_pass "rc 1, lastRc 2, one line: ${TG_1:0:60}"
    else
        kt_test_fail "rc=$TG_RC lastRc=$lr ours=$TG_N tool=$TOOL_N first='$TG_1'"
    fi
    gQ.delete
fi

if tcase "A: \`quiet\` is on for the exact string \`1\` only (the family rule); the default is 0"; then
    bad=""
    TGrep.new gQ needle "$FX/plain.txt"
    [[ "$(gQ.quiet)" == "0" ]] || bad+=" default='$(gQ.quiet)'"
    for v in 2 yes true on 01 '' ' 1' 0; do
        gQ.quiet = "$v"
        GOT=()
        gQ.argv GOT >/dev/null
        arr_is GOT "$GREP_BIN" -e needle -- "$FX/plain.txt" || bad+=" [$v]->$(arr_show GOT)"
    done
    gQ.quiet = 1
    GOT=()
    gQ.argv GOT >/dev/null
    arr_is GOT "$GREP_BIN" -q -e needle -- "$FX/plain.txt" || bad+=" [1]->$(arr_show GOT)"
    if [[ -z "$bad" ]]; then
        kt_test_pass "off for 2 yes true on 01 '' ' 1' 0; on for 1"
    else
        kt_test_fail "$bad"
    fi
    gQ.delete
fi

# ===========================================================================
kt_test_section "B. TGrep.contains — a predicate: rc only, prints nothing"
# ===========================================================================

if tcase "B: found -> rc 0, a DIRECT call prints NOTHING (stdout and stderr empty)"; then
    sil TGrep.contains needle "$FX/plain.txt"
    if [[ $S_RC -eq 0 && $S_OUT -eq 0 && $S_ERR -eq 0 ]]; then
        kt_test_pass "rc 0, silent"
    else
        kt_test_fail "rc=$S_RC out=$S_OUT err=$S_ERR"
    fi
fi

if tcase "B: not found -> rc 1, silent, NO line of ours, none of grep's"; then
    tg_dbg TGrep.contains zzzabsent "$FX/plain.txt"
    sil TGrep.contains zzzabsent "$FX/plain.txt"
    if [[ $TG_RC -eq 1 && $TG_N -eq 0 && $TOOL_N -eq 0 && $S_RC -eq 1 && $S_OUT -eq 0 && $S_ERR -eq 0 ]]; then
        kt_test_pass "rc 1 and nothing at all, with the debug switch on too"
    else
        kt_test_fail "rc=$TG_RC ours=$TG_N tool=$TOOL_N; direct rc=$S_RC out=$S_OUT err=$S_ERR"
    fi
fi

if tcase "B: under \`\$( )\` it prints nothing either, and the rc survives into \`if\`"; then
    out="$(TGrep.contains needle "$FX/plain.txt" 2>&1)"
    yes=no; if TGrep.contains needle "$FX/plain.txt"; then yes=yes; fi
    no=yes; if TGrep.contains zzzabsent "$FX/plain.txt"; then no=yes; else no=no; fi
    if [[ -z "$out" && "$yes" == yes && "$no" == no ]]; then
        kt_test_pass "empty capture; if-true on a hit, if-false on a miss"
    else
        kt_test_fail "out='$out' yes=$yes no=$no"
    fi
fi

if tcase "B: the TEXT is LITERAL (-F): \`a.b\` is not \`aXb\`, and \`[y]\`, \`\$\` and \`a.*b\` are plain text"; then
    bad=""
    # (TEXT, file with the text, file without it)
    TGrep.contains 'a.b' "$MX/m.txt"       || bad+=" a.b/m"
    TGrep.contains 'a.b' "$MX/x.txt"       && bad+=" a.b/x(aXb matched)"
    TGrep.contains 'a.*b' "$MX/x.txt"      && bad+=" a.*b/x"
    TGrep.contains '[y]' "$MX/br.txt"      || bad+=" [y]/br"
    TGrep.contains 'x [y] z' "$MX/br.txt"  || bad+=" whole-line/br"
    TGrep.contains 'cost $5' "$MX/lf.txt"  || bad+=" cost\$5"
    TGrep.contains 'second$' "$MX/lf.txt"  && bad+=" second\$(anchor)"
    TGrep.contains '^cost' "$MX/lf.txt"    && bad+=" ^cost(anchor)"
    if [[ -z "$bad" ]]; then
        kt_test_pass "every metacharacter is data"
    else
        kt_test_fail "wrong:$bad"
    fi
fi

if tcase "B: a TEXT that looks like a flag is data: \`-v\` is found in 'say -v loudly' and is NOT an invert"; then
    TGrep.contains -v "$MX/flag.txt"; r1=$?
    TGrep.contains --help "$MX/flag.txt"; r2=$?
    if [[ $r1 -eq 0 && $r2 -eq 1 ]]; then
        kt_test_pass "\`-v\` rc 0, \`--help\` (absent) rc 1 — grep never saw a flag"
    else
        kt_test_fail "-v rc=$r1, --help rc=$r2"
    fi
fi

if tcase "B: it is RECURSIVE: found only in sub/deep.txt of a directory operand; and a miss over the whole tree is rc 1"; then
    TGrep.contains 'needle deep' "$FX"; r1=$?
    TGrep.contains 'no such text anywhere' "$FX"; r2=$?
    if [[ $r1 -eq 0 && $r2 -eq 1 ]]; then
        kt_test_pass "rc 0 for the nested hit, rc 1 for the miss"
    else
        kt_test_fail "hit rc=$r1 miss rc=$r2"
    fi
fi

if tcase "B: several paths — a hit in the SECOND one is rc 0; a hit in none is rc 1; a path with a space and a leading-dash name work"; then
    TGrep.contains 'needle in spaced' "$FX/other.txt" "$FX/with space.txt"; r1=$?
    TGrep.contains 'needle in spaced' "$FX/other.txt" "$FX/plain.txt"; r2=$?
    ( cd "$FX" && TGrep.contains 'needle dash' -dash.txt ); r3=$?
    if [[ $r1 -eq 0 && $r2 -eq 1 && $r3 -eq 0 ]]; then
        kt_test_pass "second-path hit rc 0, no hit rc 1, './-dash.txt' by its bare name rc 0 (after \`--\`)"
    else
        kt_test_fail "second=$r1 none=$r2 dash=$r3"
    fi
fi

if tcase "B: a CRLF file: the text before the line end is found, and the oracle agrees"; then
    TGrep.contains 'needle crlf' "$FX/crlf.txt"; r1=$?
    TGrep.contains 'second' "$FX/crlf.txt"; r2=$?
    "$GREP_BIN" -q -F -e 'needle crlf' -- "$FX/crlf.txt"; o1=$?
    if [[ $r1 -eq 0 && $r2 -eq 0 && $o1 -eq 0 ]]; then
        kt_test_pass "rc 0 / 0, as the bare tool"
    else
        kt_test_fail "needle crlf=$r1 second=$r2 oracle=$o1"
    fi
fi

if tcase "B: a BINARY file that holds the text is found (rc 0): -q needs no 'Binary file X matches' line"; then
    sil TGrep.contains needle "$BX/bin.dat"
    r1=$S_RC
    TGrep.contains 'binary' "$BX/bin.dat"; r2=$?
    if [[ $r1 -eq 0 && $S_OUT -eq 0 && $r2 -eq 0 ]]; then
        kt_test_pass "rc 0, nothing printed"
    else
        kt_test_fail "needle rc=$r1 out=$S_OUT; binary rc=$r2"
    fi
fi

# --- a tool error is rc 1 + ONE line, never rc 2 (D4) -----------------------------
if tcase "B: a MISSING operand alone is a TOOL error: rc 1 (never rc 2), ONE line of ours, grep's own passes through"; then
    tg_dbg TGrep.contains needle "$FX/no_such"
    if [[ $TG_RC -eq 1 && $TG_N -eq 1 && "$TG_1" == *"mapRc"* && $TOOL_N -eq 1 && "$TOOL_1" == *"no_such"* ]]; then
        kt_test_pass "rc 1, one line: ${TG_1:0:70}"
    else
        kt_test_fail "rc=$TG_RC ours=$TG_N tool=$TOOL_N first='$TG_1'"
    fi
fi

if tcase "B: a hit AND a missing operand: rc 0 and NO line of ours (the -q measurement, through the static)"; then
    tg_dbg TGrep.contains needle "$FX/plain.txt" "$FX/no_such"
    r1=$TG_RC; n1=$TG_N
    tg_dbg TGrep.contains needle "$FX/no_such" "$FX/plain.txt"
    if [[ $r1 -eq 0 && $n1 -eq 0 && $TG_RC -eq 0 && $TG_N -eq 0 ]]; then
        kt_test_pass "both orders rc 0, silent on our side"
    else
        kt_test_fail "hit-first rc=$r1/$n1; missing-first rc=$TG_RC/$TG_N"
    fi
fi

if tcase "B: a miss AND a missing operand: rc 1, ONE line of ours (the error wins when nothing matched)"; then
    tg_dbg TGrep.contains zzzabsent "$FX/other.txt" "$FX/no_such"
    if [[ $TG_RC -eq 1 && $TG_N -eq 1 && "$TG_1" == *"mapRc"* ]]; then
        kt_test_pass "rc 1, one line: ${TG_1:0:60}"
    else
        kt_test_fail "rc=$TG_RC ours=$TG_N first='$TG_1'"
    fi
fi

# --- rc 2: a malformed call, nothing ran, stdin untouched, exactly one line ---------
if tcase "B: rc 2 — no argument, and TEXT without a PATH: ONE usage line each, nothing printed, stdin UNREAD"; then
    bad=""
    for form in 0 1; do
        if [[ $form -eq 0 ]]; then
            tg_dbg TGrep.contains
            stdin_kept TGrep.contains
        else
            tg_dbg TGrep.contains needle
            stdin_kept TGrep.contains needle
        fi
        if [[ $TG_RC -eq 2 && $TG_N -eq 1 && $TOOL_N -eq 0 && "$TG_1" == *"usage"* \
              && "$STDIN_OUT" == "rc=2|stdin-kept" ]]; then
            :
        else
            bad+=" form$form:rc=$TG_RC,ours=$TG_N,tool=$TOOL_N,stdin='$STDIN_OUT'"
        fi
    done
    if [[ -z "$bad" ]]; then
        kt_test_pass "rc 2 x2, one 'usage' line each, the here-string still held its line"
    else
        kt_test_fail "$bad"
    fi
fi

if tcase "B: rc 2 — an EMPTY TEXT is \`buildArgv\`'s refusal: ONE line, nothing ran, stdin UNREAD"; then
    tg_dbg TGrep.contains '' "$FX/plain.txt"
    stdin_kept TGrep.contains '' "$FX/plain.txt"
    if [[ $TG_RC -eq 2 && $TG_N -eq 1 && $TOOL_N -eq 0 && "$TG_1" == *"pattern is empty"* \
          && "$STDIN_OUT" == "rc=2|stdin-kept" ]]; then
        kt_test_pass "rc 2, one line: ${TG_1:0:60}"
    else
        kt_test_fail "rc=$TG_RC ours=$TG_N tool=$TOOL_N first='$TG_1' stdin='$STDIN_OUT'"
    fi
fi

if tcase "B: a hit/miss leaves a here-string on stdin UNREAD too (a path operand: grep never touches stdin)"; then
    stdin_kept TGrep.contains needle "$FX/plain.txt"
    s1="$STDIN_OUT"
    stdin_kept TGrep.contains zzzabsent "$FX/plain.txt"
    if [[ "$s1" == "rc=0|stdin-kept" && "$STDIN_OUT" == "rc=1|stdin-kept" ]]; then
        kt_test_pass "rc 0 / rc 1, stdin untouched"
    else
        kt_test_fail "hit='$s1' miss='$STDIN_OUT'"
    fi
fi

# ===========================================================================
kt_test_section "C. TGrep.countMatching — the number of matching lines, in RESULT"
# ===========================================================================

if tcase "C: over a tree: RESULT is the bare tool's line count (8), a DIRECT call prints nothing"; then
    oracle_n -r -h -F -e needle -- "$FX"
    RESULT=sentinel
    sil TGrep.countMatching needle "$FX"
    res="$RESULT"
    if [[ $S_RC -eq 0 && $S_OUT -eq 0 && $S_ERR -eq 0 && "$res" == "8" && "$ORACLE_N" == "8" ]]; then
        kt_test_pass "rc 0, RESULT 8 == oracle $ORACLE_N, silent"
    else
        kt_test_fail "rc=$S_RC out=$S_OUT err=$S_ERR RESULT='$res' oracle=$ORACLE_N"
    fi
fi

if tcase "C: under \`\$( )\` the value is printed EXACTLY ONCE"; then
    out="$(TGrep.countMatching needle "$FX" 2>/dev/null)"
    out0="$(TGrep.countMatching zzzabsent "$FX" 2>/dev/null)"
    if [[ "$out" == "8" && "$out0" == "0" ]]; then
        kt_test_pass "'8' and '0' — once each, no doubling"
    else
        kt_test_fail "hit='$out' miss='$out0'"
    fi
fi

if tcase "C: zero matches is the \`count\` sink's answer: RESULT 0 with rc 1, no line of ours"; then
    RESULT=sentinel
    tg_dbg TGrep.countMatching zzzabsent "$FX"
    RESULT=sentinel
    TGrep.countMatching zzzabsent "$FX" >/dev/null 2>&1; rc=$?
    if [[ $TG_RC -eq 1 && $TG_N -eq 0 && $TOOL_N -eq 0 && $rc -eq 1 && "$RESULT" == "0" ]]; then
        kt_test_pass "rc 1, RESULT 0, nothing on stderr"
    else
        kt_test_fail "rc=$TG_RC/$rc ours=$TG_N tool=$TOOL_N RESULT='$RESULT'"
    fi
fi

if tcase "C: the named deviation — a MISSING operand among good ones: rc 1 with the REAL count, ONE line of ours"; then
    tg_dbg TGrep.countMatching needle "$FX/plain.txt" "$FX/no_such" "$FX/colon.txt"
    RESULT=sentinel
    TGrep.countMatching needle "$FX/plain.txt" "$FX/no_such" "$FX/colon.txt" >/dev/null 2>&1; rc=$?
    if [[ $TG_RC -eq 1 && $rc -eq 1 && $TG_N -eq 1 && "$TG_1" == *"mapRc"* && "$RESULT" == "4" ]]; then
        kt_test_pass "rc 1, RESULT 4 (2 + 2), one line: ${TG_1:0:50}"
    else
        kt_test_fail "rc=$TG_RC/$rc ours=$TG_N RESULT='$RESULT' first='$TG_1'"
    fi
fi

if tcase "C: NO \`file:count\` parsing — lines that contain a colon each count ONE (colon.txt = 2), and there is no filename prefix"; then
    TGrep.countMatching needle "$FX/colon.txt"; r1=$?; n1="$RESULT"
    TGrep.countMatching 'needle:3' "$FX/colon.txt"; r2=$?; n2="$RESULT"
    # a single file under -r and a directory give the same -h shape
    TGrep.countMatching needle "$FX/plain.txt" "$FX/colon.txt"; r3=$?; n3="$RESULT"
    if [[ $r1 -eq 0 && "$n1" == "2" && $r2 -eq 0 && "$n2" == "1" && $r3 -eq 0 && "$n3" == "4" ]]; then
        kt_test_pass "2, 1 and 4 — records are lines, not 'file:N' pairs"
    else
        kt_test_fail "colon=$r1/$n1 single=$r2/$n2 two-files=$r3/$n3"
    fi
fi

if tcase "C: a matching BINARY file is ONE record (grep's 'Binary file X matches' line): kept, not filtered, not -a"; then
    oracle_n -r -h -F -e needle -- "$BX"
    TGrep.countMatching needle "$BX"; r1=$?; n1="$RESULT"
    TGrep.countMatching needle "$BX" "$FX/plain.txt"; r2=$?; n2="$RESULT"
    TGrep.countMatching binary "$BX"; r3=$?; n3="$RESULT"
    if [[ "$ORACLE_N" == "1" && $r1 -eq 0 && "$n1" == "1" && $r2 -eq 0 && "$n2" == "3" && $r3 -eq 0 && "$n3" == "1" ]]; then
        kt_test_pass "bin.dat alone 1 (oracle $ORACLE_N); with plain.txt (2 lines) 3; the same file matched on another line is still 1"
    else
        kt_test_fail "oracle=$ORACLE_N alone=$r1/$n1 with-plain=$r2/$n2 binary-text=$r3/$n3"
    fi
fi

if tcase "C: the TEXT is LITERAL (-F): \`a.b\` counts the 2 lines holding a.b (not aXb); \`a.*b\` counts 0"; then
    TGrep.countMatching 'a.b' "$MX/m.txt"; r1=$?; n1="$RESULT"
    TGrep.countMatching 'a.*b' "$MX/m.txt"; r2=$?; n2="$RESULT"
    TGrep.countMatching 'second$' "$MX/lf.txt"; r3=$?; n3="$RESULT"
    oracle_n -r -h -F -e 'a.b' -- "$MX/m.txt"
    if [[ $r1 -eq 0 && "$n1" == "2" && "$ORACLE_N" == "2" && $r2 -eq 1 && "$n2" == "0" && $r3 -eq 1 && "$n3" == "0" ]]; then
        kt_test_pass "2 (oracle $ORACLE_N), 0, 0"
    else
        kt_test_fail "a.b=$r1/$n1 (oracle $ORACLE_N) a.*b=$r2/$n2 second\$=$r3/$n3"
    fi
fi

if tcase "C: a CRLF file counts per LINE (text mode: the CR is not part of the match or the count)"; then
    TGrep.countMatching 'needle crlf' "$FX/crlf.txt"; r1=$?; n1="$RESULT"
    TGrep.countMatching e "$FX/crlf.txt"; r2=$?; n2="$RESULT"
    oracle_n -r -h -F -e e -- "$FX/crlf.txt"
    if [[ $r1 -eq 0 && "$n1" == "1" && $r2 -eq 0 && "$n2" == "$ORACLE_N" && "$n2" == "2" ]]; then
        kt_test_pass "1, and 2 for 'e' (both lines) == oracle $ORACLE_N"
    else
        kt_test_fail "crlf=$r1/$n1 e=$r2/$n2 oracle=$ORACLE_N"
    fi
fi

if tcase "C: a TEXT that looks like a flag is data (\`-v\` -> 1 line)"; then
    TGrep.countMatching -v "$MX/flag.txt"; r1=$?; n1="$RESULT"
    if [[ $r1 -eq 0 && "$n1" == "1" ]]; then
        kt_test_pass "RESULT 1"
    else
        kt_test_fail "rc=$r1 RESULT=$n1"
    fi
fi

if tcase "C: rc 2 — usage (0 args, TEXT alone): RESULT '', ONE line, stdin UNREAD, \`\$( )\` prints nothing"; then
    bad=""
    for form in 0 1; do
        RESULT=sentinel
        if [[ $form -eq 0 ]]; then
            tg_dbg TGrep.countMatching
            RESULT=sentinel; TGrep.countMatching >/dev/null 2>&1; res="$RESULT"
            stdin_kept TGrep.countMatching
            cap="$(TGrep.countMatching 2>/dev/null)"
        else
            tg_dbg TGrep.countMatching needle
            RESULT=sentinel; TGrep.countMatching needle >/dev/null 2>&1; res="$RESULT"
            stdin_kept TGrep.countMatching needle
            cap="$(TGrep.countMatching needle 2>/dev/null)"
        fi
        if [[ $TG_RC -eq 2 && $TG_N -eq 1 && $TOOL_N -eq 0 && "$TG_1" == *"usage"* && -z "$res" \
              && "$STDIN_OUT" == "rc=2|stdin-kept" && -z "$cap" ]]; then
            :
        else
            bad+=" form$form:rc=$TG_RC,ours=$TG_N,tool=$TOOL_N,RESULT='$res',stdin='$STDIN_OUT',cap='$cap'"
        fi
    done
    if [[ -z "$bad" ]]; then
        kt_test_pass "rc 2 x2, RESULT '', one 'usage' line, stdin kept, nothing captured"
    else
        kt_test_fail "$bad"
    fi
fi

if tcase "C: rc 2 — an EMPTY TEXT is \`buildArgv\`'s refusal: RESULT '', ONE line, stdin UNREAD"; then
    tg_dbg TGrep.countMatching '' "$FX"
    RESULT=sentinel; TGrep.countMatching '' "$FX" >/dev/null 2>&1; res="$RESULT"
    stdin_kept TGrep.countMatching '' "$FX"
    cap="$(TGrep.countMatching '' "$FX" 2>/dev/null)"
    if [[ $TG_RC -eq 2 && $TG_N -eq 1 && "$TG_1" == *"pattern is empty"* && -z "$res" \
          && "$STDIN_OUT" == "rc=2|stdin-kept" && -z "$cap" ]]; then
        kt_test_pass "rc 2, RESULT '', one line: ${TG_1:0:55}"
    else
        kt_test_fail "rc=$TG_RC ours=$TG_N first='$TG_1' RESULT='$res' stdin='$STDIN_OUT' cap='$cap'"
    fi
fi

if tcase "C: RESULT survives the \`delete\` of the throw-away instance, and the caller's own RESULT is replaced (not kept)"; then
    RESULT=old-value
    TGrep.countMatching needle "$FX/plain.txt"
    if [[ "$RESULT" == "2" ]]; then
        kt_test_pass "RESULT 2"
    else
        kt_test_fail "RESULT='$RESULT'"
    fi
fi

# ===========================================================================
kt_test_section "D. nesting, the throw-away instance, the lifecycle, set -eu"
# ===========================================================================

NEST_C=()
NEST_N=()
cb_nest() {
    NEST_C+=( "$1" )
    local c n
    if TGrep.contains 'needle deep' "$FX/sub" 2>/dev/null; then c=hit; else c=miss; fi
    n="$(TGrep.countMatching needle "$FX/plain.txt" 2>/dev/null)"
    NEST_N+=( "$c:$n" )
    return 0
}

if tcase "D: \`contains\` and \`countMatching\` nested inside an outer \`each\` callback — all complete, the outer instance survives"; then
    TGrep.new gD needle "$FX/plain.txt"
    NEST_C=(); NEST_N=()
    rc=0; gD.each cb_nest 2>/dev/null || rc=$?
    GOT=()
    arc=0; gD.argv GOT || arc=$?
    gD.lastRc; lr="$RESULT"
    ok=1
    for x in "${NEST_N[@]}"; do
        [[ "$x" == "hit:2" ]] || ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_C[@]} -eq 2 && ${#NEST_N[@]} -eq 2 && "$ok" == 1 && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is GOT "$GREP_BIN" -e needle -- "$FX/plain.txt"; then
        kt_test_pass "2 outer records, 2 nested contains (rc 0), 2 nested counts (2), outer argv untouched"
    else
        kt_test_fail "rc=$rc outer=${#NEST_C[@]} nested=${NEST_N[*]} argvRc=$arc lastRc='$lr' argv=$(arr_show GOT)"
    fi
    gD.delete
fi

if tcase "D: a nested call from a \`TGrep.search\`-fed \`TPipe.each\` callback (the \`--\` form) completes too"; then
    NEST_C=(); NEST_N=()
    rc=0
    TPipe.each cb_nest -- TGrep.search needle "$FX/sub" 2>/dev/null || rc=$?
    ok=1
    for x in "${NEST_N[@]}"; do
        [[ "$x" == "hit:2" ]] || ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_C[@]} -eq 1 && "$ok" == 1 ]]; then
        kt_test_pass "1 outer record, the nested pair answered ${NEST_N[*]}"
    else
        kt_test_fail "rc=$rc outer=${#NEST_C[@]} nested=${NEST_N[*]}"
    fi
fi

if tcase "D: both statics bump \`__TG_SEQ\` and delete their throw-away instance"; then
    before="$__TG_SEQ"
    TGrep.contains needle "$FX/plain.txt" >/dev/null 2>&1
    TGrep.countMatching needle "$FX/plain.txt" >/dev/null 2>&1
    TGrep.contains needle "$FX/no_such" >/dev/null 2>&1
    after="$__TG_SEQ"
    left=""
    for (( s = before; s <= after; s++ )); do
        nm="__tg_s_${BASHPID}_${s}"
        declare -p "${nm}_data" >/dev/null 2>&1 && left+=" ${nm}_data"
        declare -p "${nm}_paths" >/dev/null 2>&1 && left+=" ${nm}_paths"
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 3 && -z "$left" ]]; then
        kt_test_pass "__TG_SEQ $before -> $after, no instance left behind (also after the tool-error call)"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

if tcase "D: \`quiet\` lifecycle — present in \`\${inst}_data\` after \`new\`, reset by a re-\`new\` of a live name, gone after \`delete\`"; then
    TGrep.new gL1 p1 f
    d1="$(declare -p gL1_data)"
    gL1.quiet = 1
    TGrep.new gL1 p2 f                    # a live name: Create must re-assign it
    q2="$(gL1.quiet)"
    gL1.delete
    declare -p gL1_data >/dev/null 2>&1 && left=yes || left=no
    if [[ "$d1" == *"[quiet]="* && "$q2" == "0" && "$left" == no ]]; then
        kt_test_pass "declared, reset to 0 by Create, freed by delete"
    else
        kt_test_fail "declared=$([[ "$d1" == *'[quiet]='* ]] && echo y || echo n) after-renew='$q2' data-left=$left"
    fi
fi

if tcaseT "D: as predicates under \`set -eu\` in a CHILD script: \`if contains\`, \`|| echo no\`, the count in \`\$( )\`"; then
    out="$(FX="$FX" UNIT="$UNIT" "$KT_TIMEOUT" 30 "$BASH" -c '
set -eu
source "$UNIT"
if TGrep.contains needle "$FX/plain.txt"; then printf "hit;"; fi
TGrep.contains zzzabsent "$FX/plain.txt" || printf "miss;"
n=$(TGrep.countMatching needle "$FX/plain.txt")
printf "n=%s;" "$n"
z=0; TGrep.countMatching zzzabsent "$FX/plain.txt" || z=$?
printf "zero=%s/%s;" "$z" "$RESULT"
e=0; TGrep.contains || e=$?
printf "usage=%s" "$e"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $crc -eq 0 && "$out" == "hit;miss;n=2;zero=1/0;usage=2" ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "rc=$crc out='$out'"
    fi
fi

use_real
