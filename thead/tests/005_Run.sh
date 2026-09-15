#!/bin/bash
# 005_Run.sh — thead P0: THead against the real tool on a real tree
# (thead/PLAN.md §1.1, §2.2–§2.7, §3, §4; pinned facts H3, H6–H11).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same argv —
# never a second call into the code under test. The fixture tree is built under
# `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework tears it down;
# this file installs NO `trap … EXIT` of its own, which would replace ktests'
# trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GATE IS THE FIRST CASE. D4 of the tpipe plan pins the GNU dialect, not a
# binary: if `head --version` does not begin with `head (GNU coreutils) `, every
# behavioural case below is a loud `SKIP`, so the suite stays honest.
#
# Sections:
#   Z        the GNU banner gate, and the fixture tree
#   A  H6    one file: `each` / `count` / `toArray` / `first` / `toList` / `run`
#            against the bare tool; the unterminated last record
#   B  H7    headers are RECORDS: 9 records for two terminated 3-line files
#            under `-n 5`, 8 when the first is unterminated (the leading `\n` of
#            a later header is an empty record only after a terminated file);
#            `first` is `==> A <==`; `quiet` = data only; `verbose` on ONE file
#   C  H8    a missing operand among good ones: records KEPT, RESULT = the real
#            count, rc 1, `lastRc` 1, exactly ONE line of ours — head's own
#            diagnostic passes through and is matched by PREFIX
#   D  H9    CRLF: head keeps the CR, `crlf = 1` strips exactly one per record,
#            in bytes mode too
#   E  H10   `-z`: NUL records, the unterminated last one delivered, and a TEXT
#            file under `-z` is ONE record
#   F  H3    the sign table, behaviourally: `2` / `+3` / `-2` / `-0` / `+0` /
#            `0` / `08`, and a 19-digit `bytes` that the TOOL refuses (rc 1)
#   G  H11   `THead.take` in all three positions, with several paths, refused
#            without a path, and nested inside an outer `each`
#
# Calls that make head itself write to stderr (a missing operand) get
# `2>/dev/null`; where the count matters, `th_dbg` separates OUR lines
# (`Error:`/`Warning:`) from the tool's (`head: …`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thead.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/th.err"

kt_test_section "005: THead against GNU head on a real tree (P0)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`head\` on PATH is GNU coreutils (D4 pins the DIALECT, not a binary)"
HEAD_BIN="$(command -v head 2>/dev/null || printf '(none)')"
HEAD_VER="$(head --version 2>/dev/null | head -1 || :)"
if [[ "$HEAD_VER" == "head (GNU coreutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$HEAD_BIN — $HEAD_VER"
else
    kt_test_pass "SKIP: non-GNU head ($HEAD_BIN — '${HEAD_VER:-no banner}'); every behavioural case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so a case body reads `if tcase "…"; then … fi` and the case COUNT is
# the same on a GNU box and on one without.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU head"
        return 1
    fi
    return 0
}

# --- the tree --------------------------------------------------------------
FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf '1\n2\n3\n4\n5\n'                           > "$FX/f5.txt"
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n'       > "$FX/f11.txt"
printf 'a1\na2\na3\n'                              > "$FX/a3.txt"
printf 'b1\nb2\nb3\n'                              > "$FX/b3.txt"
printf 'u1\nu2\nu3'                                > "$FX/unterm.txt"
printf 'x\r\ny\r\n'                                > "$FX/crlf.txt"
printf 'z1\000z2\000z3'                            > "$FX/z.dat"
printf 's1\ns2\n'                                  > "$FX/with space.txt"
printf 'd1\nd2\n'                                  > "$FX/-dash.txt"

kt_test_start "the fixture tree is in place"
need_ok=1
for f in f5.txt f11.txt a3.txt b3.txt unterm.txt crlf.txt z.dat 'with space.txt' -dash.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
if [[ "$need_ok" == "1" ]]; then
    kt_test_pass "9 fixture files under $FX"
else
    kt_test_fail "a fixture file is missing under $FX"
fi

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

arr_eq() {
    local -n __x="$1"
    local -n __y="$2"
    local __i
    if (( ${#__x[@]} != ${#__y[@]} )); then
        return 1
    fi
    for (( __i = 0; __i < ${#__x[@]}; __i++ )); do
        if [[ "${__x[$__i]}" != "${__y[$__i]}" ]]; then
            return 1
        fi
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

# SGOT / SWANT are the two arrays every comparison uses; globals, so no nameref
# of ours can ever alias a caller's local.
declare -a SGOT=()
declare -a SWANT=()

# oracle ARRNAME CMD... — fill ARRNAME with the command's stdout, one element
# per `\n`-terminated record, the unterminated tail included.
oracle() {
    local -n __o="$1"; shift
    __o=()
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        __o+=( "$__l" )
    done < <( "$@" 2>/dev/null )
}

# th_dbg COMMAND... — run it with the debug switch on and SPLIT stderr:
# TH_N/TH_1 are OUR lines (`Error:`/`Warning:` — kk.debug's shape), TOOL_N is
# everything else, and TOOL_1 the first of those (head writes `head: …` of its
# own on exactly the paths where the count matters).
TH_RC=0; TH_N=0; TH_1=''; TOOL_N=0; TOOL_1=''
th_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TH_RC=$?
    VERBOSE_KKLASS=
    TH_N=0; TOOL_N=0; TH_1=''; TOOL_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TH_N=$(( TH_N + 1 ))
                if [[ -z "$TH_1" ]]; then TH_1="$__l"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 ))
                if [[ -z "$TOOL_1" ]]; then TOOL_1="$__l"; fi
                ;;
        esac
    done < "$ERRF"
    return 0
}

CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

printf -v CR '\r'

# A minimal list for `toList`, duck-typed by TPipe (anything with an `.Add`).
class THTestList
    public
        var         N
        constructor Create
        proc        Add
end
THTestList.Create() { N=0; return 0; }
THTestList.Add()    { N=$(( N + 1 )); return 0; }
build THTestList

# same_as_bare TITLE INST BAREARGV... — `INST.toArray` must equal the bare tool.
same_as_bare() {
    local __t="$1" __i="$2"; shift 2
    if ! tcase "$__t"; then
        return 0
    fi
    SGOT=()
    "$__i".toArray SGOT 2>/dev/null || :
    oracle SWANT "$@"
    if (( ${#SWANT[@]} > 0 )) && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool"
    else
        kt_test_fail "got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
}

# ===========================================================================
kt_test_section "A. H6 — one file, every runner against the bare tool"
# ===========================================================================

if tcase "H6: \`lines = 2\`, \`each\` delivers exactly \`head -n 2\`'s records"; then
    THead.new hA 2 "$FX/f5.txt"
    CB_RECS=()
    rc=0; hA.each cb_collect || rc=$?
    oracle SWANT head -n 2 -- "$FX/f5.txt"
    hA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$lr" == "0" ]] && arr_eq CB_RECS SWANT && (( ${#SWANT[@]} == 2 )); then
        kt_test_pass "2 records, rc 0, lastRc 0"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got=$(arr_show CB_RECS) want=$(arr_show SWANT)"
    fi
    hA.delete
fi

THead.new hA 3 "$FX/f11.txt"
same_as_bare "H6: \`toArray\` == \`head -n 3\`" hA head -n 3 -- "$FX/f11.txt"

if tcase "H6: \`count\` is the record count, rc 0, \`lastRc\` 0"; then
    RESULT=sentinel
    rc=0; hA.count || rc=$?
    n="$RESULT"
    hA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$n" == "3" && "$lr" == "0" ]]; then
        kt_test_pass "rc 0, RESULT 3, lastRc 0"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr'"
    fi
fi

if tcase "H6: \`first\` is the FIRST record and then stops the producer"; then
    RESULT=sentinel
    rc=0; hA.first || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "1" ]]; then
        kt_test_pass "rc 0, RESULT '1'"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
fi

if tcase "H6: \`toList\` offers every record to an instance with an \`.Add\`"; then
    THTestList.new hL
    rc=0; hA.toList hL || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "3" && "$(hL.N)" == "3" ]]; then
        kt_test_pass "3 offered, 3 stored"
    else
        kt_test_fail "rc=$rc offered='$n' stored='$(hL.N)'"
    fi
    hL.delete
fi

if tcase "H6: \`run\` streams head's own bytes and leaves the raw rc readable"; then
    out="$(hA.run 2>/dev/null)"; rc=$?
    want="$(head -n 3 -- "$FX/f11.txt" 2>/dev/null)"
    hA.run >/dev/null 2>&1
    hA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$out" == "$want" && "$lr" == "0" ]]; then
        kt_test_pass "byte-identical to the bare tool, lastRc 0"
    else
        kt_test_fail "rc=$rc lastRc='$lr' out='${out//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi
hA.delete

if tcase "H6: an UNTERMINATED last line is delivered as a record"; then
    THead.new hA 5 "$FX/unterm.txt"
    SGOT=()
    rc=0; hA.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT u1 u2 u3; then
        kt_test_pass "3 records; 'u3' had no trailing newline and still arrived"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hA.delete
fi

if tcase "H6: \`lines = 0\` runs head and delivers NOTHING — rc 0, count 0, \`first\` rc 1"; then
    THead.new hA 0 "$FX/f5.txt"
    rc=0; hA.count || rc=$?
    n="$RESULT"
    frc=0; hA.first || frc=$?
    fv="$RESULT"
    hA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$n" == "0" && $frc -eq 1 && "$fv" == "" && "$lr" == "0" ]]; then
        kt_test_pass "count rc 0 / 0 records; first rc 1 with RESULT '' (its own answer)"
    else
        kt_test_fail "count rc=$rc n='$n'; first rc=$frc RESULT='$fv'; lastRc='$lr'"
    fi
    hA.delete
fi

if tcase "H6: a path with a SPACE and one starting with \`-\` are operands, not flags"; then
    THead.new hA 1 "$FX/with space.txt"
    SGOT=()
    rc=0; hA.toArray SGOT || rc=$?
    THead.new hB 1 "$FX/-dash.txt"
    SWANT=()
    rc2=0; hB.toArray SWANT || rc2=$?
    if [[ $rc -eq 0 && $rc2 -eq 0 ]] && arr_is SGOT s1 && arr_is SWANT d1; then
        kt_test_pass "'with space.txt' -> s1; '-dash.txt' -> d1 (the \`--\` did its job)"
    else
        kt_test_fail "rc=$rc/$rc2 space=$(arr_show SGOT) dash=$(arr_show SWANT)"
    fi
    hA.delete
    hB.delete
fi

# ===========================================================================
kt_test_section "B. H7 — the \`==> NAME <==\` headers are RECORDS (§2.4)"
# ===========================================================================

if tcase "H7: two TERMINATED 3-line files under \`-n 5\` are 9 records"; then
    THead.new hH 5 "$FX/a3.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; hH.toArray SGOT || rc=$?
    oracle SWANT head -n 5 -- "$FX/a3.txt" "$FX/b3.txt"
    # header, a1, a2, a3, '' (the leading \n of the second header), header, b1, b2, b3
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 9 && "${SGOT[4]}" == "" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "9 records, the 5th empty — identical to the bare tool"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hH.delete
fi

if tcase "H7: the same pair with the FIRST file UNTERMINATED is 8 records"; then
    THead.new hH 5 "$FX/unterm.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; hH.toArray SGOT || rc=$?
    oracle SWANT head -n 5 -- "$FX/unterm.txt" "$FX/b3.txt"
    # the separator's leading \n TERMINATES 'u3' instead of making an empty record
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 8 && "${SGOT[3]}" == "u3" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "8 records — no empty one; 'u3' was terminated by the separator"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hH.delete
fi

if tcase "H7: \`first\` on two files is the HEADER of the first one"; then
    THead.new hH 5 "$FX/a3.txt" "$FX/b3.txt"
    RESULT=sentinel
    rc=0; hH.first || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "==> $FX/a3.txt <==" ]]; then
        kt_test_pass "RESULT = '${RESULT:0:40}…'"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
    hH.delete
fi

if tcase "H7: \`quiet = 1\` on two files is DATA ONLY — 6 records"; then
    THead.new hH 5 "$FX/a3.txt" "$FX/b3.txt"
    hH.quiet = 1
    SGOT=()
    rc=0; hH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT a1 a2 a3 b1 b2 b3; then
        kt_test_pass "6 records, no header, no empty separator"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hH.delete
fi

if tcase "H7: \`verbose = 1\` on ONE file forces the header — 2 records for \`-n 1\`"; then
    THead.new hH 1 "$FX/a3.txt"
    hH.verbose = 1
    SGOT=()
    rc=0; hH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "==> $FX/a3.txt <==" a1; then
        kt_test_pass "the header and the one data line"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hH.delete
fi

if tcase "H7: ONE file without \`verbose\` has NO header (tool parity, default \`quiet = 0\`)"; then
    THead.new hH 1 "$FX/a3.txt"
    SGOT=()
    rc=0; hH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT a1; then
        kt_test_pass "one record, no header"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hH.delete
fi

# ===========================================================================
kt_test_section "C. H8 — a missing operand among good ones (§2.5 deviation a/b)"
# ===========================================================================

if tcase "H8: \`toArray\` over good+MISSING+good — rc 1, RESULT = the real count, lastRc 1"; then
    THead.new hM 1 "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; hM.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    hM.lastRc; lr="$RESULT"
    oracle SWANT head -n 1 -- "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    if [[ $rc -eq 1 && "$lr" == "1" && "$n" == "${#SGOT[@]}" && ${#SGOT[@]} -gt 0 ]] \
       && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records kept, RESULT $n, rc 1, lastRc 1 — identical to the bare tool"
    else
        kt_test_fail "rc=$rc lastRc='$lr' RESULT='$n' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hM.delete
fi

if tcase "H8: \`count\` and \`each\` on the same operands keep everything too"; then
    THead.new hM 1 "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    rc=0; hM.count 2>/dev/null || rc=$?
    cnt="$RESULT"
    CB_RECS=()
    rc2=0; hM.each cb_collect 2>/dev/null || rc2=$?
    if [[ $rc -eq 1 && $rc2 -eq 1 && "$cnt" == "${#CB_RECS[@]}" && ${#CB_RECS[@]} -gt 0 ]]; then
        kt_test_pass "count: rc 1 RESULT $cnt; each: rc 1, ${#CB_RECS[@]} callback calls"
    else
        kt_test_fail "count rc=$rc RESULT='$cnt'; each rc=$rc2 recs=${#CB_RECS[@]}"
    fi
    hM.delete
fi

if tcase "H8: the partial-failure path emits exactly ONE line of ours; head's own passes through"; then
    THead.new hM 1 "$FX/a3.txt" "$FX/no_such_file.txt"
    th_dbg hM.count
    # the tool's diagnostic is unconditional and locale-quoted: match the PREFIX
    if [[ "$TH_RC" == "1" && "$TH_N" == "1" && "$TOOL_N" -ge 1 \
          && "$TH_1" == *"THead"* && "$TH_1" == *"head exited 1"* \
          && "$TOOL_1" == "head: cannot open "* ]]; then
        kt_test_pass "ours: ${TH_1:0:56}… | head's: '${TOOL_1:0:46}…'"
    else
        kt_test_fail "rc=$TH_RC ourLines=$TH_N first='$TH_1' toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
    hM.delete
fi

if tcase "H8: a MISSING file alone — zero records, rc 1, lastRc 1"; then
    THead.new hM 1 "$FX/no_such_file.txt"
    SGOT=( stale )
    rc=0; hM.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    hM.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "0" && ${#SGOT[@]} -eq 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, RESULT 0, array emptied, lastRc 1"
    else
        kt_test_fail "rc=$rc RESULT='$n' SGOT=$(arr_show SGOT) lastRc='$lr'"
    fi
    hM.delete
fi

if tcase "H8: a DIRECTORY operand is rc 1 with head's own message (never rc 2)"; then
    THead.new hM 1 "$FX"
    th_dbg hM.count
    if [[ "$TH_RC" == "1" && "$TH_N" == "1" && "$TOOL_N" -ge 1 && "$TOOL_1" == "head: "* ]]; then
        kt_test_pass "rc 1, one line of ours, head's own: '${TOOL_1:0:52}…'"
    else
        kt_test_fail "rc=$TH_RC ourLines=$TH_N toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
    hM.delete
fi

# ===========================================================================
kt_test_section "D. H9 — head is a BYTE tool: the CR survives, \`crlf\` trims it"
# ===========================================================================

if tcase "H9: \`crlf = 0\` (the default) keeps the CR — this is where head differs from grep"; then
    THead.new hC 2 "$FX/crlf.txt"
    SGOT=()
    rc=0; hC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "x$CR" "y$CR"; then
        kt_test_pass "'x\\r' and 'y\\r' — ${#SGOT[0]} characters each"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hC.delete
fi

if tcase "H9: \`crlf = 1\` strips exactly ONE CR per record"; then
    THead.new hC 2 "$FX/crlf.txt"
    hC.crlf = 1
    SGOT=()
    rc=0; hC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT x y; then
        kt_test_pass "'x' and 'y'"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hC.delete
fi

if tcase "H9: \`crlf = 1\` works in BYTES mode too (\`bytes = 5\` cuts mid-record)"; then
    THead.new hC '' "$FX/crlf.txt"
    hC.bytes = 5
    hC.crlf = 1
    SGOT=()
    rc=0; hC.toArray SGOT || rc=$?
    # `head -c 5` of 'x\r\ny\r\n' is 'x\r\ny\r': two records, the second
    # unterminated, both losing exactly one CR to the sink's -c
    if [[ $rc -eq 0 ]] && arr_is SGOT x y; then
        kt_test_pass "5 bytes -> 'x', 'y' (the second record was unterminated)"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hC.delete
fi

# ===========================================================================
kt_test_section "E. H10 — \`-z\`: NUL records in, NUL records out (§2.3)"
# ===========================================================================

if tcase "H10: \`zeroTerminated = 1\` on a NUL-separated file gives NUL records"; then
    THead.new hZ 2 "$FX/z.dat"
    hZ.zeroTerminated = 1
    SGOT=()
    rc=0; hZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 && "$(hZ.nul)" == "1" ]] && arr_is SGOT z1 z2; then
        kt_test_pass "2 records, the sinks' -0 derived"
    else
        kt_test_fail "rc=$rc nul='$(hZ.nul)' SGOT=$(arr_show SGOT)"
    fi
    hZ.delete
fi

if tcase "H10: the UNTERMINATED last NUL record is delivered"; then
    THead.new hZ 3 "$FX/z.dat"
    hZ.zeroTerminated = 1
    SGOT=()
    rc=0; hZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT z1 z2 z3; then
        kt_test_pass "3 records; 'z3' had no trailing NUL and still arrived"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    hZ.delete
fi

if tcase "H10: a TEXT file under \`-z\` is ONE record for any \`lines\` >= 1"; then
    THead.new hZ 1 "$FX/f5.txt"
    hZ.zeroTerminated = 1
    SGOT=()
    rc=0; hZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 1 && "${SGOT[0]}" == $'1\n2\n3\n4\n5\n' ]]; then
        kt_test_pass "one record holding the whole file — \`-z\` re-delimits the INPUT"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} first='${SGOT[0]:-}'"
    fi
    hZ.delete
fi

# ===========================================================================
kt_test_section "F. H3 — the sign table, behaviourally (§2.2)"
# ===========================================================================

# sign TITLE N WANT... — `lines = N` on f5.txt must deliver exactly WANT.
sign() {
    local __t="$1" __n="$2"; shift 2
    if ! tcase "$__t"; then
        return 0
    fi
    THead.new hS '' "$FX/f5.txt"
    hS.lines = "$__n"
    SGOT=()
    local __rc=0
    hS.toArray SGOT || __rc=$?
    oracle SWANT head -n "$__n" -- "$FX/f5.txt"
    if [[ $__rc -eq 0 ]] && arr_is SGOT "$@" && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, identical to \`head -n $__n\`"
    else
        kt_test_fail "rc=$__rc got=$(arr_show SGOT) want=$(printf '%q ' "$@") bare=$(arr_show SWANT)"
    fi
    hS.delete
}

sign "H3: \`lines = 2\` — the first 2"                                   2  1 2
sign "H3: \`lines = +3\` — head reads \`+N\` as plain N (unlike tail)"  +3  1 2 3
sign "H3: \`lines = -2\` — ALL BUT THE LAST 2"                          -2  1 2 3
sign "H3: \`lines = -0\` — EVERYTHING ('all but the last 0')"           -0  1 2 3 4 5
sign "H3: \`lines = +0\` — nothing"                                     +0
sign "H3: \`lines = 0\` — nothing"                                       0

if tcase "H3: \`lines = 08\` is DECIMAL 8 (pinned on an 11-line file)"; then
    THead.new hS '' "$FX/f11.txt"
    hS.lines = 08
    rc=0; hS.count || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "8" ]]; then
        kt_test_pass "8 records — head's own decimal reading, passed through verbatim"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    hS.delete
fi

if tcase "H1/§1.3: \`addArg -n 5\` after \`lines = 3\` — the TOOL takes 5 (extras are last)"; then
    # 004 pins that both words reach the argv; this is the other half of the
    # claim: head is last-flag-wins, so the escape-hatch extra REPLACES the
    # typed option in silence.
    THead.new hS '' "$FX/f11.txt"
    hS.lines = 3
    hS.addArg -n 5
    rc=0; hS.count || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "5" ]]; then
        kt_test_pass "5 records, not 3 — the documented escape hatch"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    hS.delete
fi

if tcase "H1/§1.3: \`addArg -c 4\` after \`lines = 3\` even switches head to BYTE mode"; then
    THead.new hS '' "$FX/f11.txt"
    hS.lines = 3
    hS.addArg -c 4
    SGOT=()
    rc=0; hS.toArray SGOT || rc=$?
    oracle SWANT head -n 3 -c 4 -- "$FX/f11.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT '1' '2' && arr_eq SGOT SWANT; then
        kt_test_pass "the first 4 bytes ('1\\n2\\n'), identical to the bare tool"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hS.delete
fi

if tcase "H3: \`bytes = -3\` is 'all but the last 3 bytes'"; then
    THead.new hS '' "$FX/f5.txt"
    hS.bytes = -3
    SGOT=()
    rc=0; hS.toArray SGOT || rc=$?
    oracle SWANT head -c -3 -- "$FX/f5.txt"
    if [[ $rc -eq 0 && ${#SGOT[@]} -gt 0 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, identical to \`head -c -3\`"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hS.delete
fi

if tcase "H3: a 19-digit \`bytes = -9999999999999999999\` reaches head and is its OWN rc 1"; then
    # It passes the regex and the 19-digit guard, so the wrapper builds it; the
    # TOOL then refuses it ('Value too large'). That is an ordinary rc 1 with
    # head's own message on stderr, never a rc 2 (§2.5).
    THead.new hS '' "$FX/f5.txt"
    hS.bytes = -9999999999999999999
    th_dbg hS.count
    hS.lastRc; lr="$RESULT"
    if [[ "$TH_RC" == "1" && "$TH_N" == "1" && "$TOOL_N" -ge 1 && "$lr" == "1" \
          && "$TOOL_1" == "head: invalid number of bytes"* ]]; then
        kt_test_pass "rc 1, lastRc 1, one line of ours, head's: '${TOOL_1:0:56}…'"
    else
        kt_test_fail "rc=$TH_RC ourLines=$TH_N toolLines=$TOOL_N lastRc='$lr' toolFirst='$TOOL_1'"
    fi
    hS.delete
fi

# ===========================================================================
kt_test_section "G. H11 — \`THead.take N PATH...\`, the static one-liner (§2.7)"
# ===========================================================================

if tcase "H11: \`THead.take 2 f\` == \`head -n 2 -- f\`, DIRECT"; then
    got="$(THead.take 2 "$FX/f5.txt" 2>/dev/null)"; rc=$?
    want="$(head -n 2 -- "$FX/f5.txt" 2>/dev/null)"; wrc=$?
    if [[ $rc -eq 0 && $wrc -eq 0 && "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc/$wrc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "H11: the same through a PIPE (\`| od -c\`) — byte-identical"; then
    got="$(THead.take 2 "$FX/f5.txt" 2>/dev/null | od -c)"
    want="$(head -n 2 -- "$FX/f5.txt" 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "H11: the same through \`< <( )\` — byte-identical"; then
    got="$(cat < <(THead.take 2 "$FX/f5.txt" 2>/dev/null) | od -c)"
    want="$(head -n 2 -- "$FX/f5.txt" 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "H11: \`take\` with TWO paths carries the headers (tool parity, §2.7)"; then
    got="$(THead.take 1 "$FX/a3.txt" "$FX/b3.txt" 2>/dev/null)"; rc=$?
    want="$(head -n 1 -- "$FX/a3.txt" "$FX/b3.txt" 2>/dev/null)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$got" == "==> "* ]]; then
        kt_test_pass "headers included, identical to the bare tool"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "H11: \`take\` accepts \`+N\` and \`-N\` verbatim"; then
    ok=1
    for v in +3 -2 -0 0; do
        got="$(THead.take "$v" "$FX/f5.txt" 2>/dev/null)"
        want="$(head -n "$v" -- "$FX/f5.txt" 2>/dev/null)"
        [[ "$got" == "$want" ]] || ok=0
    done
    if [[ "$ok" == "1" ]]; then
        kt_test_pass "+3, -2, -0 and 0 all match the bare tool"
    else
        kt_test_fail "a signed count diverged from the bare tool"
    fi
fi

if tcase "H11: \`THead.take\` with NO path is rc 2, prints nothing, one line"; then
    th_dbg THead.take 2
    out="$(THead.take 2 2>/dev/null </dev/null)"
    if [[ "$TH_RC" == "2" && "$TH_N" == "1" && -z "$out" && "$TH_1" == *"take"* ]]; then
        kt_test_pass "rc 2 (with none head would read the CALLER's stdin): ${TH_1:0:56}"
    else
        kt_test_fail "rc=$TH_RC lines=$TH_N out='$out' first='$TH_1'"
    fi
fi

if tcase "H11: \`THead.take\` with a BAD count is rc 2 and runs nothing"; then
    th_dbg THead.take 1K "$FX/f5.txt"
    out="$(THead.take 1K "$FX/f5.txt" 2>/dev/null)"
    if [[ "$TH_RC" == "2" && "$TH_N" == "1" && -z "$out" ]]; then
        kt_test_pass "rc 2 before any instance is built: ${TH_1:0:56}"
    else
        kt_test_fail "rc=$TH_RC lines=$TH_N out='$out' first='$TH_1'"
    fi
fi

if tcase "H11: \`take\` on a MISSING file is rc 1 (head's own status, mapped)"; then
    th_dbg THead.take 1 "$FX/no_such_file.txt"
    if [[ "$TH_RC" == "1" && "$TH_N" == "1" && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "rc 1, one line of ours, head's own passed through"
    else
        kt_test_fail "rc=$TH_RC ourLines=$TH_N toolLines=$TOOL_N"
    fi
fi

if tcase "H11: \`take\` deletes its throw-away instance and bumps \`__TH_SEQ\`"; then
    before="$__TH_SEQ"
    THead.take 1 "$FX/f5.txt" >/dev/null 2>&1
    THead.take 1 "$FX/f5.txt" >/dev/null 2>&1
    after="$__TH_SEQ"
    left=""
    for s in "$before" "$(( before + 1 ))" "$after"; do
        nm="__th_t_${BASHPID}_${s}"
        declare -p "${nm}_data" >/dev/null 2>&1 && left+=" ${nm}_data"
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TH_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(THead.take 1 "$FX/b3.txt" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "H11: a nested \`take\` inside an outer \`each\` — both complete, the outer instance survives"; then
    THead.new hT 3 "$FX/a3.txt"
    NEST_OUT=(); NEST_IN=()
    rc=0; hT.each cb_nest 2>/dev/null || rc=$?
    SGOT=()
    arc=0; hT.argv SGOT || arc=$?
    hT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == "b1" ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_OUT[@]} -eq 3 && ${#NEST_IN[@]} -eq 3 && "$inner_ok" == "1" \
          && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is SGOT head -n 3 -- "$FX/a3.txt"; then
        kt_test_pass "3 outer records, 3 nested takes, the outer instance untouched"
    else
        kt_test_fail "rc=$rc outer=${#NEST_OUT[@]} inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    hT.delete
fi

if tcase "H11: \`take\` composes with both TPipe forms"; then
    N1=0; N2=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- THead.take 3 "$FX/f11.txt" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
N=0
cb() { N=$(( N + 1 )); return 0; }
THead.take 3 "$FX/f11.txt" | TPipe.each cb
printf "%s" "$N"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "3" && $crc -eq 0 && "$out" == "3" ]]; then
        kt_test_pass "the \`--\` form: 3 records; the lastpipe form: 3 records"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi
