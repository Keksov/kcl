#!/bin/bash
# 005_Run.sh — ttail P0: TTail against the real tool on a real tree
# (ttail/PLAN.md §1.1, §2.1, §2.2, §3; thead/PLAN.md §2.2–§2.7, §4; pinned facts
# H3, H6–H11 mirrored for tail, and T1–T4).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same argv —
# never a second call into the code under test. The fixture tree is built under
# `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework tears it down;
# this file installs NO `trap … EXIT` of its own, which would replace ktests'
# trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GATE IS THE FIRST CASE: if `tail --version` does not begin with
# `tail (GNU coreutils) `, every behavioural case below is a loud `SKIP`.
#
# ---- `tail -f` hygiene (the reason §4 of the plan exists) ------------------
# Leaked followers from earlier sessions were found on this box. Every case that
# starts a follower runs it in a CHILD under `timeout 20`, and every such child
# ends its `tail` itself:
#   * `each` + a stopping callback and `first` take TPipe's stop path (close ->
#     `kill -TERM` -> wait), which ends `tail -f` in ~45 ms with raw rc 143;
#   * the `run` case, which has no consumer to stop it, uses `addArg --pid=HP`
#     against a short-lived helper — §2.1 names it as the ONE shape in which
#     `-f` terminates on its own.
# The background APPENDER each growing-file case needs is started by THIS file,
# its pid is recorded, and it is `kill -TERM`ed in the case's own teardown. No
# `trap … EXIT` is installed anywhere.
#
# Sections:
#   Z        the GNU banner gate, and the fixture tree
#   A  H6    one file: `each` / `count` / `toArray` / `first` / `toList` / `run`
#   B  H7    the `==> NAME <==` headers are RECORDS (9 / 8 / `quiet` / `verbose`)
#   C  H8    a missing operand among good ones: records KEPT, rc 1, lastRc 1
#   D  H9    CRLF: tail keeps the CR, `crlf = 1` strips one per record
#   E  H10   `-z`: NUL records in, NUL records out
#   F  T1    the sign table, behaviourally — `+N` means FROM line N here
#   G  T4    `TTail.take`, including `TTail.take +2 f`
#   H  T2/T3 `follow`: the three refused sinks, the two streaming ones, and the
#            overridden sinks with `follow = 0`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/ttail.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/tt.err"

kt_test_section "005: TTail against GNU tail on a real tree (P0)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`tail\` on PATH is GNU coreutils (D4 pins the DIALECT, not a binary)"
TAIL_BIN="$(command -v tail 2>/dev/null || printf '(none)')"
TAIL_VER="$(tail --version 2>/dev/null | head -1 || :)"
if [[ "$TAIL_VER" == "tail (GNU coreutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$TAIL_BIN — $TAIL_VER"
else
    kt_test_pass "SKIP: non-GNU tail ($TAIL_BIN — '${TAIL_VER:-no banner}'); every behavioural case below is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU tail"
        return 1
    fi
    return 0
}

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
printf 'fol1\nfol2\n'                              > "$FX/follow.txt"
printf 'grw1\n'                                    > "$FX/grow.txt"

kt_test_start "the fixture tree is in place"
need_ok=1
for f in f5.txt f11.txt a3.txt b3.txt unterm.txt crlf.txt z.dat 'with space.txt' \
         -dash.txt follow.txt grow.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
if [[ "$need_ok" == "1" ]]; then
    kt_test_pass "11 fixture files under $FX"
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

declare -a SGOT=()
declare -a SWANT=()

oracle() {
    local -n __o="$1"; shift
    __o=()
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        __o+=( "$__l" )
    done < <( "$@" 2>/dev/null )
}

TT_RC=0; TT_N=0; TT_1=''; TOOL_N=0; TOOL_1=''
tt_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TT_RC=$?
    VERBOSE_KKLASS=
    TT_N=0; TOOL_N=0; TT_1=''; TOOL_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TT_N=$(( TT_N + 1 ))
                if [[ -z "$TT_1" ]]; then TT_1="$__l"; fi
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

class TTTestList
    public
        var         N
        constructor Create
        proc        Add
end
TTTestList.Create() { N=0; return 0; }
TTTestList.Add()    { N=$(( N + 1 )); return 0; }
build TTTestList

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

if tcase "H6: \`lines = 2\`, \`each\` delivers exactly \`tail -n 2\`'s records"; then
    TTail.new tA 2 "$FX/f5.txt"
    CB_RECS=()
    rc=0; tA.each cb_collect || rc=$?
    oracle SWANT tail -n 2 -- "$FX/f5.txt"
    tA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$lr" == "0" ]] && arr_eq CB_RECS SWANT && arr_is CB_RECS 4 5; then
        kt_test_pass "2 records (4, 5), rc 0, lastRc 0"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got=$(arr_show CB_RECS) want=$(arr_show SWANT)"
    fi
    tA.delete
fi

TTail.new tA 3 "$FX/f11.txt"
same_as_bare "H6: \`toArray\` == \`tail -n 3\`" tA tail -n 3 -- "$FX/f11.txt"

if tcase "H6: \`count\` is the record count, rc 0, \`lastRc\` 0"; then
    RESULT=sentinel
    rc=0; tA.count || rc=$?
    n="$RESULT"
    tA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$n" == "3" && "$lr" == "0" ]]; then
        kt_test_pass "rc 0, RESULT 3, lastRc 0"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr'"
    fi
fi

if tcase "H6: \`first\` is the FIRST record of the tail window"; then
    RESULT=sentinel
    rc=0; tA.first || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "9" ]]; then
        kt_test_pass "rc 0, RESULT '9' (the first of the last three)"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
fi

if tcase "H6: \`toList\` offers every record to an instance with an \`.Add\`"; then
    TTTestList.new tL
    rc=0; tA.toList tL || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "3" && "$(tL.N)" == "3" ]]; then
        kt_test_pass "3 offered, 3 stored"
    else
        kt_test_fail "rc=$rc offered='$n' stored='$(tL.N)'"
    fi
    tL.delete
fi

if tcase "H6: \`run\` streams tail's own bytes and leaves the raw rc readable"; then
    out="$(tA.run 2>/dev/null)"; rc=$?
    want="$(tail -n 3 -- "$FX/f11.txt" 2>/dev/null)"
    tA.run >/dev/null 2>&1
    tA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$out" == "$want" && "$lr" == "0" ]]; then
        kt_test_pass "byte-identical to the bare tool, lastRc 0"
    else
        kt_test_fail "rc=$rc lastRc='$lr' out='${out//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi
tA.delete

if tcase "H6: an UNTERMINATED last line is delivered as a record"; then
    TTail.new tA 5 "$FX/unterm.txt"
    SGOT=()
    rc=0; tA.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT u1 u2 u3; then
        kt_test_pass "3 records; 'u3' had no trailing newline and still arrived"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tA.delete
fi

if tcase "H6: \`lines = 0\` runs tail and delivers NOTHING — rc 0, count 0, \`first\` rc 1"; then
    TTail.new tA 0 "$FX/f5.txt"
    rc=0; tA.count || rc=$?
    n="$RESULT"
    frc=0; tA.first || frc=$?
    fv="$RESULT"
    tA.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$n" == "0" && $frc -eq 1 && "$fv" == "" && "$lr" == "0" ]]; then
        kt_test_pass "count rc 0 / 0 records; first rc 1 with RESULT '' (its own answer)"
    else
        kt_test_fail "count rc=$rc n='$n'; first rc=$frc RESULT='$fv'; lastRc='$lr'"
    fi
    tA.delete
fi

if tcase "H6: a path with a SPACE and one starting with \`-\` are operands, not flags"; then
    TTail.new tA 1 "$FX/with space.txt"
    SGOT=()
    rc=0; tA.toArray SGOT || rc=$?
    TTail.new tB 1 "$FX/-dash.txt"
    SWANT=()
    rc2=0; tB.toArray SWANT || rc2=$?
    if [[ $rc -eq 0 && $rc2 -eq 0 ]] && arr_is SGOT s2 && arr_is SWANT d2; then
        kt_test_pass "'with space.txt' -> s2; '-dash.txt' -> d2 (the \`--\` did its job)"
    else
        kt_test_fail "rc=$rc/$rc2 space=$(arr_show SGOT) dash=$(arr_show SWANT)"
    fi
    tA.delete
    tB.delete
fi

# ===========================================================================
kt_test_section "B. H7 — the \`==> NAME <==\` headers are RECORDS"
# ===========================================================================

if tcase "H7: two TERMINATED 3-line files under \`-n 5\` are 9 records"; then
    TTail.new tH 5 "$FX/a3.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; tH.toArray SGOT || rc=$?
    oracle SWANT tail -n 5 -- "$FX/a3.txt" "$FX/b3.txt"
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 9 && "${SGOT[4]}" == "" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "9 records, the 5th empty — identical to the bare tool"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    tH.delete
fi

if tcase "H7: the same pair with the FIRST file UNTERMINATED is 8 records"; then
    TTail.new tH 5 "$FX/unterm.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; tH.toArray SGOT || rc=$?
    oracle SWANT tail -n 5 -- "$FX/unterm.txt" "$FX/b3.txt"
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 8 && "${SGOT[3]}" == "u3" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "8 records — no empty one; 'u3' was terminated by the separator"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    tH.delete
fi

if tcase "H7: \`first\` on two files is the HEADER of the first one"; then
    TTail.new tH 5 "$FX/a3.txt" "$FX/b3.txt"
    RESULT=sentinel
    rc=0; tH.first || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "==> $FX/a3.txt <==" ]]; then
        kt_test_pass "RESULT = '${RESULT:0:40}…'"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
    tH.delete
fi

if tcase "H7: \`quiet = 1\` on two files is DATA ONLY — 6 records"; then
    TTail.new tH 5 "$FX/a3.txt" "$FX/b3.txt"
    tH.quiet = 1
    SGOT=()
    rc=0; tH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT a1 a2 a3 b1 b2 b3; then
        kt_test_pass "6 records, no header, no empty separator"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tH.delete
fi

if tcase "H7: \`verbose = 1\` on ONE file forces the header — 2 records for \`-n 1\`"; then
    TTail.new tH 1 "$FX/a3.txt"
    tH.verbose = 1
    SGOT=()
    rc=0; tH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "==> $FX/a3.txt <==" a3; then
        kt_test_pass "the header and the one data line"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tH.delete
fi

if tcase "H7: ONE file without \`verbose\` has NO header (tool parity)"; then
    TTail.new tH 1 "$FX/a3.txt"
    SGOT=()
    rc=0; tH.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT a3; then
        kt_test_pass "one record, no header"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tH.delete
fi

# ===========================================================================
kt_test_section "C. H8 — a missing operand among good ones"
# ===========================================================================

if tcase "H8: \`toArray\` over good+MISSING+good — rc 1, RESULT = the real count, lastRc 1"; then
    TTail.new tM 1 "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    SGOT=()
    rc=0; tM.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    tM.lastRc; lr="$RESULT"
    oracle SWANT tail -n 1 -- "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    if [[ $rc -eq 1 && "$lr" == "1" && "$n" == "${#SGOT[@]}" && ${#SGOT[@]} -gt 0 ]] \
       && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records kept, RESULT $n, rc 1, lastRc 1 — identical to the bare tool"
    else
        kt_test_fail "rc=$rc lastRc='$lr' RESULT='$n' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    tM.delete
fi

if tcase "H8: \`count\` and \`each\` on the same operands keep everything too"; then
    TTail.new tM 1 "$FX/a3.txt" "$FX/no_such_file.txt" "$FX/b3.txt"
    rc=0; tM.count 2>/dev/null || rc=$?
    cnt="$RESULT"
    CB_RECS=()
    rc2=0; tM.each cb_collect 2>/dev/null || rc2=$?
    if [[ $rc -eq 1 && $rc2 -eq 1 && "$cnt" == "${#CB_RECS[@]}" && ${#CB_RECS[@]} -gt 0 ]]; then
        kt_test_pass "count: rc 1 RESULT $cnt; each: rc 1, ${#CB_RECS[@]} callback calls"
    else
        kt_test_fail "count rc=$rc RESULT='$cnt'; each rc=$rc2 recs=${#CB_RECS[@]}"
    fi
    tM.delete
fi

if tcase "H8: the partial-failure path emits exactly ONE line of ours; tail's own passes through"; then
    TTail.new tM 1 "$FX/a3.txt" "$FX/no_such_file.txt"
    tt_dbg tM.count
    if [[ "$TT_RC" == "1" && "$TT_N" == "1" && "$TOOL_N" -ge 1 \
          && "$TT_1" == *"TTail"* && "$TT_1" == *"tail exited 1"* \
          && "$TOOL_1" == "tail: cannot open "* ]]; then
        kt_test_pass "ours: ${TT_1:0:56}… | tail's: '${TOOL_1:0:46}…'"
    else
        kt_test_fail "rc=$TT_RC ourLines=$TT_N first='$TT_1' toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
    tM.delete
fi

if tcase "H8: a MISSING file alone — zero records, rc 1, lastRc 1"; then
    TTail.new tM 1 "$FX/no_such_file.txt"
    SGOT=( stale )
    rc=0; tM.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    tM.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "0" && ${#SGOT[@]} -eq 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, RESULT 0, array emptied, lastRc 1"
    else
        kt_test_fail "rc=$rc RESULT='$n' SGOT=$(arr_show SGOT) lastRc='$lr'"
    fi
    tM.delete
fi

# ===========================================================================
kt_test_section "D. H9 — tail is a BYTE tool: the CR survives, \`crlf\` trims it"
# ===========================================================================

if tcase "H9: \`crlf = 0\` (the default) keeps the CR"; then
    TTail.new tC 2 "$FX/crlf.txt"
    SGOT=()
    rc=0; tC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "x$CR" "y$CR"; then
        kt_test_pass "'x\\r' and 'y\\r' — ${#SGOT[0]} characters each"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tC.delete
fi

if tcase "H9: \`crlf = 1\` strips exactly ONE CR per record"; then
    TTail.new tC 2 "$FX/crlf.txt"
    tC.crlf = 1
    SGOT=()
    rc=0; tC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT x y; then
        kt_test_pass "'x' and 'y'"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tC.delete
fi

if tcase "H9: \`crlf = 1\` works in BYTES mode too (\`bytes = 3\` cuts mid-record)"; then
    TTail.new tC '' "$FX/crlf.txt"
    tC.bytes = 3
    tC.crlf = 1
    SGOT=()
    rc=0; tC.toArray SGOT || rc=$?
    # the last 3 bytes of 'x\r\ny\r\n' are 'y\r\n': one record, one CR stripped
    if [[ $rc -eq 0 ]] && arr_is SGOT y; then
        kt_test_pass "the last 3 bytes -> one record 'y'"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tC.delete
fi

# ===========================================================================
kt_test_section "E. H10 — \`-z\`: NUL records in, NUL records out"
# ===========================================================================

if tcase "H10: \`zeroTerminated = 1\` on a NUL-separated file gives NUL records"; then
    TTail.new tZ 2 "$FX/z.dat"
    tZ.zeroTerminated = 1
    SGOT=()
    rc=0; tZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 && "$(tZ.nul)" == "1" ]] && arr_is SGOT z2 z3; then
        kt_test_pass "2 records (the LAST two), the sinks' -0 derived"
    else
        kt_test_fail "rc=$rc nul='$(tZ.nul)' SGOT=$(arr_show SGOT)"
    fi
    tZ.delete
fi

if tcase "H10: the UNTERMINATED last NUL record is delivered"; then
    TTail.new tZ 3 "$FX/z.dat"
    tZ.zeroTerminated = 1
    SGOT=()
    rc=0; tZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT z1 z2 z3; then
        kt_test_pass "3 records; 'z3' had no trailing NUL and still arrived"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    tZ.delete
fi

if tcase "H10: a TEXT file under \`-z\` is ONE record for any \`lines\` >= 1"; then
    TTail.new tZ 1 "$FX/f5.txt"
    tZ.zeroTerminated = 1
    SGOT=()
    rc=0; tZ.toArray SGOT || rc=$?
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 1 && "${SGOT[0]}" == $'1\n2\n3\n4\n5\n' ]]; then
        kt_test_pass "one record holding the whole file — \`-z\` re-delimits the INPUT"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} first='${SGOT[0]:-}'"
    fi
    tZ.delete
fi

# ===========================================================================
kt_test_section "F. T1 — the sign table: \`+N\` means FROM line N (§2.2)"
# ===========================================================================

sign() {
    local __t="$1" __n="$2"; shift 2
    if ! tcase "$__t"; then
        return 0
    fi
    TTail.new tS '' "$FX/f5.txt"
    tS.lines = "$__n"
    SGOT=()
    local __rc=0
    tS.toArray SGOT || __rc=$?
    oracle SWANT tail -n "$__n" -- "$FX/f5.txt"
    if [[ $__rc -eq 0 ]] && arr_is SGOT "$@" && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, identical to \`tail -n $__n\`"
    else
        kt_test_fail "rc=$__rc got=$(arr_show SGOT) want=$(printf '%q ' "$@") bare=$(arr_show SWANT)"
    fi
    tS.delete
}

sign "T1: \`lines = 2\` — the LAST 2"                                     2  4 5
sign "T1: \`lines = -2\` — the last 2 as well"                           -2  4 5
sign "T1: \`lines = +3\` — FROM line 3 (the mirror of head's \`+N\`)"    +3  3 4 5
sign "T1: \`lines = +0\` — EVERYTHING"                                   +0  1 2 3 4 5
sign "T1: \`lines = -0\` — nothing"                                      -0
sign "T1: \`lines = 0\` — nothing"                                        0

if tcase "T1: \`lines = +2\` on a 5-line file counts 4 (the pin \`kk.isInt\` would break)"; then
    TTail.new tS '' "$FX/f5.txt"
    tS.lines = +2
    rc=0; tS.count || rc=$?
    n="$RESULT"
    # kk.isInt would have normalised `+2` to `2` and the count would read 2
    if [[ $rc -eq 0 && "$n" == "4" ]]; then
        kt_test_pass "4 records — lines 2..5; a normalised '2' would have read 2"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    tS.delete
fi

if tcase "T1: \`lines = 08\` is DECIMAL 8 (pinned on an 11-line file)"; then
    TTail.new tS '' "$FX/f11.txt"
    tS.lines = 08
    rc=0; tS.count || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "8" ]]; then
        kt_test_pass "8 records — tail's own decimal reading, passed through verbatim"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    tS.delete
fi

if tcase "H1: \`addArg -n 5\` after \`lines = 3\` — the TOOL takes 5 (extras are last)"; then
    # 004 pins that both words reach the argv; this is the other half of the
    # claim: tail is last-flag-wins, so the escape-hatch extra REPLACES the
    # typed option in silence.
    TTail.new tS '' "$FX/f11.txt"
    tS.lines = 3
    tS.addArg -n 5
    rc=0; tS.count || rc=$?
    n="$RESULT"
    if [[ $rc -eq 0 && "$n" == "5" ]]; then
        kt_test_pass "5 records, not 3 — the documented escape hatch"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    tS.delete
fi

if tcase "T1: \`bytes = +3\` starts at BYTE 3"; then
    TTail.new tS '' "$FX/f5.txt"
    tS.bytes = +3
    SGOT=()
    rc=0; tS.toArray SGOT || rc=$?
    oracle SWANT tail -c +3 -- "$FX/f5.txt"
    if [[ $rc -eq 0 && ${#SGOT[@]} -gt 0 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, identical to \`tail -c +3\`"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    tS.delete
fi

# ===========================================================================
kt_test_section "G. T4 — \`TTail.take N PATH...\`, the static one-liner"
# ===========================================================================

if tcase "T4: \`TTail.take 2 f\` == \`tail -n 2 -- f\`, DIRECT"; then
    got="$(TTail.take 2 "$FX/f5.txt" 2>/dev/null)"; rc=$?
    want="$(tail -n 2 -- "$FX/f5.txt" 2>/dev/null)"; wrc=$?
    if [[ $rc -eq 0 && $wrc -eq 0 && "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc/$wrc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "T4: \`TTail.take +2 f\` == \`tail -n +2 -- f\` (the plan's own pin)"; then
    got="$(TTail.take +2 "$FX/f5.txt" 2>/dev/null)"; rc=$?
    want="$(tail -n +2 -- "$FX/f5.txt" 2>/dev/null)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$got" == "2"* ]]; then
        kt_test_pass "lines 2..5, identical to the bare tool"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "T4: the same through a PIPE (\`| od -c\`) — byte-identical"; then
    got="$(TTail.take 2 "$FX/f5.txt" 2>/dev/null | od -c)"
    want="$(tail -n 2 -- "$FX/f5.txt" 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "T4: the same through \`< <( )\` — byte-identical"; then
    got="$(cat < <(TTail.take 2 "$FX/f5.txt" 2>/dev/null) | od -c)"
    want="$(tail -n 2 -- "$FX/f5.txt" 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "T4: \`take\` with TWO paths carries the headers (tool parity)"; then
    got="$(TTail.take 1 "$FX/a3.txt" "$FX/b3.txt" 2>/dev/null)"; rc=$?
    want="$(tail -n 1 -- "$FX/a3.txt" "$FX/b3.txt" 2>/dev/null)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$got" == "==> "* ]]; then
        kt_test_pass "headers included, identical to the bare tool"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "T4: \`TTail.take\` with NO path is rc 2, prints nothing, one line"; then
    tt_dbg TTail.take 2
    out="$(TTail.take 2 2>/dev/null </dev/null)"
    if [[ "$TT_RC" == "2" && "$TT_N" == "1" && -z "$out" && "$TT_1" == *"take"* ]]; then
        kt_test_pass "rc 2 (with none tail would read the CALLER's stdin): ${TT_1:0:56}"
    else
        kt_test_fail "rc=$TT_RC lines=$TT_N out='$out' first='$TT_1'"
    fi
fi

if tcase "T4: \`TTail.take\` with a BAD count is rc 2 and runs nothing"; then
    tt_dbg TTail.take 1K "$FX/f5.txt"
    out="$(TTail.take 1K "$FX/f5.txt" 2>/dev/null)"
    if [[ "$TT_RC" == "2" && "$TT_N" == "1" && -z "$out" ]]; then
        kt_test_pass "rc 2 before any instance is built: ${TT_1:0:56}"
    else
        kt_test_fail "rc=$TT_RC lines=$TT_N out='$out' first='$TT_1'"
    fi
fi

if tcase "T4: \`take\` on a MISSING file is rc 1 (tail's own status, mapped)"; then
    tt_dbg TTail.take 1 "$FX/no_such_file.txt"
    if [[ "$TT_RC" == "1" && "$TT_N" == "1" && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "rc 1, one line of ours, tail's own passed through"
    else
        kt_test_fail "rc=$TT_RC ourLines=$TT_N toolLines=$TOOL_N"
    fi
fi

if tcase "T4: \`take\` deletes its throw-away instance and bumps \`__TT_SEQ\`"; then
    before="$__TT_SEQ"
    TTail.take 1 "$FX/f5.txt" >/dev/null 2>&1
    TTail.take 1 "$FX/f5.txt" >/dev/null 2>&1
    after="$__TT_SEQ"
    left=""
    for s in "$before" "$(( before + 1 ))" "$after"; do
        nm="__tt_t_${BASHPID}_${s}"
        declare -p "${nm}_data" >/dev/null 2>&1 && left+=" ${nm}_data"
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TT_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(TTail.take 1 "$FX/b3.txt" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "T4: a nested \`take\` inside an outer \`each\` — both complete, the outer instance survives"; then
    TTail.new tT 3 "$FX/a3.txt"
    NEST_OUT=(); NEST_IN=()
    rc=0; tT.each cb_nest 2>/dev/null || rc=$?
    SGOT=()
    arc=0; tT.argv SGOT || arc=$?
    tT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == "b3" ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_OUT[@]} -eq 3 && ${#NEST_IN[@]} -eq 3 && "$inner_ok" == "1" \
          && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is SGOT tail -n 3 -- "$FX/a3.txt"; then
        kt_test_pass "3 outer records, 3 nested takes, the outer instance untouched"
    else
        kt_test_fail "rc=$rc outer=${#NEST_OUT[@]} inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    tT.delete
fi

if tcase "T4: \`take\` composes with both TPipe forms"; then
    N1=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- TTail.take 3 "$FX/f11.txt" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
N=0
cb() { N=$(( N + 1 )); return 0; }
TTail.take 3 "$FX/f11.txt" | TPipe.each cb
printf "%s" "$N"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "3" && $crc -eq 0 && "$out" == "3" ]]; then
        kt_test_pass "the \`--\` form: 3 records; the lastpipe form: 3 records"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi

# ===========================================================================
kt_test_section "H. T2/T3 — \`follow\`: three sinks refuse, two stream (§2.1)"
# ===========================================================================

# --- T3: the overridden sinks with `follow = 0` still answer like the base ---
# The naive spelling (`inherited toArray "$@"` as the LAST statement) would have
# answered rc 0 with RESULT 0 here: the compiled `kk._return "$RESULT"` trailer
# replaces the rc, and the caller's own RESULT comes back. The three overrides
# therefore end `inherited X "$@" || rc=$?; n="$RESULT"; kk._return "$n";
# return "$rc"` (thead §6).

if tcase "T3: \`toArray\` with \`follow = 0\` and a missing operand — rc 1, RESULT = the real count"; then
    TTail.new tO 1 "$FX/a3.txt" "$FX/no_such_file.txt"
    SGOT=()
    rc=0; tO.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    tO.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "${#SGOT[@]}" && ${#SGOT[@]} -gt 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1 (not 0), RESULT $n == ${#SGOT[@]} records, lastRc 1"
    else
        kt_test_fail "rc=$rc RESULT='$n' kept=${#SGOT[@]} lastRc='$lr'"
    fi
    tO.delete
fi

if tcase "T3: \`count\` with \`follow = 0\` and a missing operand — rc 1, RESULT = the real count"; then
    TTail.new tO 1 "$FX/a3.txt" "$FX/no_such_file.txt"
    rc=0; tO.count 2>/dev/null || rc=$?
    n="$RESULT"
    if [[ $rc -eq 1 && "$n" -gt 0 ]]; then
        kt_test_pass "rc 1 (not 0), RESULT $n"
    else
        kt_test_fail "rc=$rc RESULT='$n'"
    fi
    tO.delete
fi

if tcase "T3: \`toList\` with \`follow = 0\` and a missing operand — rc 1, RESULT = the real count"; then
    TTail.new tO 1 "$FX/a3.txt" "$FX/no_such_file.txt"
    TTTestList.new tOL
    rc=0; tO.toList tOL 2>/dev/null || rc=$?
    n="$RESULT"
    if [[ $rc -eq 1 && "$n" -gt 0 && "$(tOL.N)" == "$n" ]]; then
        kt_test_pass "rc 1 (not 0), RESULT $n offered, $n stored"
    else
        kt_test_fail "rc=$rc RESULT='$n' stored='$(tOL.N)'"
    fi
    tOL.delete
    tO.delete
fi

if tcase "T3: the three overrides also pass a rc 2 build straight through"; then
    TTail.new tO 1 "$FX/a3.txt"
    tO.bytes = 3                    # lines + bytes -> buildArgv rc 2
    SGOT=( stale )
    a=0; tO.toArray SGOT || a=$?
    c=0; tO.count || c=$?
    TTTestList.new tOL
    l=0; tO.toList tOL || l=$?
    if [[ $a -eq 2 && $c -eq 2 && $l -eq 2 ]]; then
        kt_test_pass "toArray/count/toList all rc 2 from buildArgv, not from the follow rule"
    else
        kt_test_fail "toArray=$a count=$c toList=$l"
    fi
    tOL.delete
    tO.delete
fi

# --- T2: the three refused sinks, and the proof that NOTHING ran ------------
tt_never() { : > "$RAN_FLAG"; printf 'ran\n'; }
RAN_FLAG="$TMP/follow_ran.flag"

refuse() {   # refuse TITLE MEMBER [ARG]
    local __t="$1" __m="$2" __a="${3:-}"
    if ! tcase "$__t"; then
        return 0
    fi
    rm -f "$RAN_FLAG"
    TTail.new tR 1 "$FX/follow.txt"
    tR.follow = 1
    tR.cmd = tt_never              # a producer that leaves a flag file behind
    RESULT="sentinel"
    tt_dbg tR."$__m" ${__a:+"$__a"}
    local __ok=1
    [[ "$TT_RC" == "2" ]]                  || __ok=0
    [[ "$TT_N" == "1" ]]                   || __ok=0
    [[ "$TT_1" == *"follow = 1"* ]]        || __ok=0
    [[ ! -e "$RAN_FLAG" ]]                 || __ok=0
    tR.lastRc
    [[ "$RESULT" == "-1" ]]                || __ok=0
    tR.delete
    if [[ "$__ok" == "1" ]]; then
        kt_test_pass "rc 2, one line, the flag file was never created, lastRc still -1"
    else
        kt_test_fail "rc=$TT_RC lines=$TT_N first='$TT_1' flag=$([[ -e $RAN_FLAG ]] && echo present || echo absent)"
    fi
}

declare -a FOLLOW_ARR=()
TTTestList.new tFL
refuse "T2: \`toArray\` with \`follow = 1\` is rc 2 and NOTHING runs (§2.1)" toArray FOLLOW_ARR
refuse "T2: \`count\` with \`follow = 1\` is rc 2 and NOTHING runs"          count
refuse "T2: \`toList\` with \`follow = 1\` is rc 2 and NOTHING runs"         toList  tFL
tFL.delete

if tcase "T2: the refusal names the reason and points at the shapes that DO work"; then
    TTail.new tR 1 "$FX/follow.txt"
    tR.follow = 1
    declare -a A2=()
    tt_dbg tR.toArray A2
    if [[ "$TT_RC" == "2" && "$TT_N" == "1" && "$TT_1" == *"TTail.toArray"* \
          && "$TT_1" == *"each"* && "$TT_1" == *"first"* && "$TT_1" == *"run"* ]]; then
        kt_test_pass "${TT_1:0:92}…"
    else
        kt_test_fail "rc=$TT_RC lines=$TT_N first='$TT_1'"
    fi
    tR.delete
fi

if tcase "T2: RESULT is '' on the refusal and the caller's array is left alone"; then
    TTail.new tR 1 "$FX/follow.txt"
    tR.follow = 1
    declare -a A3=( keep1 keep2 )
    RESULT="sentinel"
    rc=0; tR.toArray A3 2>/dev/null || rc=$?
    if [[ $rc -eq 2 && "$RESULT" == "" ]] && arr_is A3 keep1 keep2; then
        kt_test_pass "rc 2, RESULT '', the array untouched"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' A3=$(arr_show A3)"
    fi
    tR.delete
fi

# --- T2: `each` + a stopping callback, and `first` --------------------------
# Both run in a CHILD under `timeout 20`. `tail -f -n 1` prints the last line at
# once, the callback stops, and TPipe's stop path (close -> kill -TERM -> wait)
# ends tail with raw rc 143 in ~45 ms. No follower survives the case.

if tcase "T2: \`each\` + a stopping callback — rc 0, lastRc 143, exactly one record"; then
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
source "$UNIT"
N=0
REC=""
cb() { N=$(( N + 1 )); REC="$1"; TPipe.stop; return 0; }
TTail.new t 1 "$FX/follow.txt"
t.follow = 1
rc=0
t.each cb || rc=$?
t.lastRc
printf "rc=%s lastRc=%s N=%s rec=%s" "$rc" "$RESULT" "$N" "$REC"
t.delete' 2>/dev/null </dev/null)"; crc=$?
    if [[ $crc -eq 0 && "$out" == "rc=0 lastRc=143 N=1 rec=fol2" ]]; then
        kt_test_pass "$out — the tpipe stop path ended \`tail -f\`"
    else
        kt_test_fail "child rc=$crc out='$out'"
    fi
fi

if tcase "T2: \`first\` on a follow stream returns the last line and stops"; then
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
source "$UNIT"
TTail.new t 1 "$FX/follow.txt"
t.follow = 1
rc=0
t.first || rc=$?
v="$RESULT"
t.lastRc
printf "rc=%s first=%s lastRc=%s" "$rc" "$v" "$RESULT"
t.delete' 2>/dev/null </dev/null)"; crc=$?
    if [[ $crc -eq 0 && "$out" == "rc=0 first=fol2 lastRc=143" ]]; then
        kt_test_pass "$out — 'wait for the next line' is \`first\` on a follow stream"
    else
        kt_test_fail "child rc=$crc out='$out'"
    fi
fi

# --- T2: `run` on a file that GROWS ----------------------------------------
# The appender is started HERE, its pid is recorded, and it is killed in this
# case's own teardown. The child ends its own follower with `--pid=HP` against a
# 5 s helper — §2.1's self-terminating shape — so nothing can outlive the case;
# the appender writes at ~2 s, which leaves ~3 s of slack for the ~1 s msys poll.

if tcase "T2: \`run\` with \`follow = 1\` streams a line appended while it waits"; then
    OUTF="$TMP/follow_run.out"
    READY="$TMP/follow_run.ready"
    : > "$OUTF"
    rm -f "$READY"
    # The appender waits for the child's READY flag instead of a fixed delay: a
    # cold `source` of the unit costs seconds under the threaded runner, and a
    # bare `sleep 2` fired BEFORE tail had started — `tail -n 1` then printed the
    # appended line as the file's last line and nothing followed. The wait is
    # bounded (12 s) so the appender cannot outlive a child that never starts,
    # and it still leaves >= 3 s of slack for the ~1 s msys poll before the
    # child's `--pid` helper ends the follow at ~5 s.
    { i=0
      while [[ ! -e "$READY" && $i -lt 60 ]]; do sleep 0.2; i=$(( i + 1 )); done
      sleep 1
      printf 'appended\n' >> "$FX/grow.txt"; } &
    APPENDER_PID=$!
    out="$(FX="$FX" UNIT="$UNIT" OUTF="$OUTF" READY="$READY" timeout 20 "$BASH" -c '
set -u
source "$UNIT"
( sleep 5 ) &
HP=$!
TTail.new t 1 "$FX/grow.txt"
t.follow = 1
t.addArg --pid=$HP
rc=0
: > "$READY"
t.run > "$OUTF" || rc=$?
t.lastRc
printf "rc=%s lastRc=%s" "$rc" "$RESULT"
kill -TERM "$HP" 2>/dev/null || :
wait "$HP" 2>/dev/null || :
t.delete' 2>/dev/null </dev/null)"; crc=$?
    kill -TERM "$APPENDER_PID" 2>/dev/null || :
    wait "$APPENDER_PID" 2>/dev/null || :
    streamed="$(cat "$OUTF" 2>/dev/null || :)"
    if [[ $crc -eq 0 && "$out" == "rc=0 lastRc=0" && "$streamed" == $'grw1\nappended' ]]; then
        kt_test_pass "the pre-existing line and the appended one, rc 0 (\`--pid\` ended the follow)"
    else
        kt_test_fail "child rc=$crc out='$out' streamed='${streamed//$'\n'/|}'"
    fi
fi

if tcase "T2: no follower of ours survived the section"; then
    # Only OUR followers matter; older leaked `tail` processes from earlier
    # sessions predate this suite and are reported, not killed.
    mine="$(ps 2>/dev/null | awk -v me="$$" 'NR > 1 && $2 == me && $NF ~ /tail/ { print $1 }' | tr '\n' ' ')"
    if [[ -z "${mine// /}" ]]; then
        kt_test_pass "no \`tail\` process has this test (pid $$) as its parent"
    else
        kt_test_fail "leaked follower pid(s) under $$: $mine"
    fi
fi
