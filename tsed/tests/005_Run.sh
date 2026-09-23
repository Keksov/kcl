#!/bin/bash
# 005_Run.sh — tsed P0: TSed against the real tool on a real fixture tree
# (tsed/PLAN.md §1.1, §2.2–§2.7, §4; pinned facts S5–S12).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same
# arguments — never a second call into the code under test. The fixture tree is
# built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework
# tears it down; this file installs NO `trap … EXIT` of its own.
#
# THE GATE IS THE FIRST CASE. D4 pins the GNU dialect, not a binary (5.2.37
# resolves Git for Windows' sed, 5.3.9 msys64's; both 4.9): if `sed --version`
# does not begin with `sed (GNU sed) `, every behavioural case below is a loud
# `SKIP`, so the case COUNT is the same either way.
#
# In-place cases work on COPIES made inside `_KT_TMPDIR` and assert the bytes
# with `od -c` afterwards. CR fixtures are written with `printf`, never through
# an array literal (tutil README trap 18).
#
# Sections:
#   Z        the banner gate and the fixture tree
#   A  S6    every sink vs bare sed; multi-`-e`; `-f`; `-n` + `p`; `-s` vs the
#            default one stream; the unterminated last line; `addExpr ''` is the
#            identity; stdin; exotic path names behind `--`
#   B  S5    `extended = 1` on `a1` -> `[a]`, and the bare tool with `-E` AFTER
#            the `-e` is rc 1 (why the order is pinned)
#   C  S7    a missing file among good ones (the family contract per sink); a
#            directory operand (lastRc 4, the later file NOT read); a missing
#            `-f` script (lastRc 4); a bad script; `2q7` silent; `2q1` loud
#   D  S8    the sandbox default: `s///e`, `e`, `w FILE`, `s///w /dev/stdout`,
#            a later `-e`, a `-f` script with `w` — refused (rc 1, lastRc 1,
#            marker files prove nothing ran); `sandbox = 0` runs them
#   E  S9    CR: text mode strips, `binary` keeps, `binary` + `crlf` strips one,
#            `inPlace` keeps every CR on disk, `nullData` keeps an embedded CR
#   F  S10   `-z`: NUL records through the derived `-0`; the unterminated last
#            NUL record
#   G  S11   in-place: `run` edits, stdout empty; `.bak`; `bak_*`; `*` rc 2; a
#            missing backup directory rc 1 / lastRc 4; every sink rc 2 with
#            nothing run; a directory before a good file stops the edit; the
#            `q` truncation trap; `--debug` among the extras
#   H  S12   `TSed.edit EXPR PATH...` in three positions, `edit ''` the
#            identity, no path rc 2, nested, sandbox forced, composition

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tsed.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/ts.err"

kt_test_section "005: TSed against GNU sed on a real tree (P0)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`sed\` on PATH is GNU sed (D4 pins the DIALECT, not a binary)"
SED_BIN="$(command -v sed 2>/dev/null || printf '(none)')"
SED_VER="$(sed --version 2>/dev/null | head -1 || :)"
if [[ "$SED_VER" == "sed (GNU sed) "* ]]; then
    GNU_OK=1
    kt_test_pass "$SED_BIN — $SED_VER"
else
    kt_test_pass "SKIP: non-GNU sed ($SED_BIN — '${SED_VER:-no banner}'); every behavioural case below is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU sed"
        return 1
    fi
    return 0
}

printf -v CR '\r'

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/dir"
printf 'a1\nb2\nc3\n'          > "$FX/f3.txt"
printf 'd4\ne5\n'              > "$FX/f3b.txt"
printf 'a1\r\nb2\r\n'          > "$FX/crlf.txt"
printf 'c3\r\r\n'              > "$FX/cr2.txt"
printf 'a\0x\r\ny\0last'       > "$FX/nul.bin"
printf 'u1\nu2'                > "$FX/unterm.txt"
printf 'a1\n'                  > "$FX/a1.txt"
printf 's/b/B/\n'              > "$FX/s.sed"
printf 'sp1\n'                 > "$FX/with space.txt"
printf 'dash1\n'               > "$FX/-dash.txt"

kt_test_start "the fixture tree is in place (a 3-line file, CRLF, NUL, unterminated, script, exotic names, a directory)"
need_ok=1
for f in f3.txt f3b.txt crlf.txt cr2.txt nul.bin unterm.txt a1.txt s.sed 'with space.txt' -dash.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
[[ -d "$FX/dir" ]] || need_ok=0
if [[ "$need_ok" == "1" && "$(od -c < "$FX/crlf.txt" | head -1)" == *'\r'* ]]; then
    kt_test_pass "tree under $FX"
else
    kt_test_fail "a fixture entry is missing under $FX"
fi

# ---------------------------------------------------------------------------
# helpers — every local uses a `__z` prefix so none can shadow the unit's
# `__tsd_*` scratch namerefs.
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

arr_eq() {
    local -n __zx="$1"
    local -n __zy="$2"
    local __zi
    if (( ${#__zx[@]} != ${#__zy[@]} )); then
        return 1
    fi
    for (( __zi = 0; __zi < ${#__zx[@]}; __zi++ )); do
        if [[ "${__zx[$__zi]}" != "${__zy[$__zi]}" ]]; then
            return 1
        fi
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

# oracleL ARRNAME CMD... — newline-framed stdout, the unterminated tail kept.
oracleL() {
    local -n __zo="$1"; shift
    __zo=()
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        __zo+=( "$__zl" )
    done < <( "$@" 2>/dev/null )
    return 0
}

# oracle0 ARRNAME CMD... — NUL-framed stdout.
oracle0() {
    local -n __zo="$1"; shift
    __zo=()
    mapfile -d '' -t __zo < <( "$@" 2>/dev/null )
    return 0
}

# odf FILE -> the `od -c` rendering of the file's bytes.
odf() { od -c < "$1"; }

# ts_dbg COMMAND... — the switch ON, stderr SPLIT: TS_N/TS_1 are OUR lines
# (`Error:`/`Warning:`), TOOL_N/TOOL_1 sed's own (matched by the `sed: `
# PREFIX — its quoting follows the locale).
TS_RC=0; TS_N=0; TS_1=''; TOOL_N=0; TOOL_1=''
ts_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TS_RC=$?
    VERBOSE_KKLASS=
    TS_N=0; TOOL_N=0; TS_1=''; TOOL_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TS_N=$(( TS_N + 1 ))
                if [[ -z "$TS_1" ]]; then TS_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 ))
                if [[ -z "$TOOL_1" ]]; then TOOL_1="$__zl"; fi
                ;;
        esac
    done < "$ERRF"
    return 0
}

declare -a SGOT=()
declare -a SWANT=()

CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

class TSTestList
    public
        var         N
        constructor Create
        proc        Add
end
TSTestList.Create() { N=0; return 0; }
TSTestList.Add()    { N=$(( N + 1 )); return 0; }
build TSTestList

# ===========================================================================
kt_test_section "A. S6 — every sink against the bare tool"
# ===========================================================================

if tcase "S6: toArray / each / count / first / toList / run on \`s/a/A/\` all agree with bare sed"; then
    TSed.new sK 's/a/A/' "$FX/f3.txt"
    oracleL SWANT sed --sandbox -e 's/a/A/' -- "$FX/f3.txt"
    SGOT=()
    arc=0; sK.toArray SGOT || arc=$?; an="$RESULT"
    CB_RECS=()
    erc=0; sK.each cb_collect || erc=$?
    crc=0; sK.count || crc=$?; cn="$RESULT"
    frc=0; sK.first || frc=$?; fv="$RESULT"
    TSTestList.new sKL
    lrc=0; sK.toList sKL || lrc=$?; ln="$RESULT"
    rrc=0; sK.run > "$TMP/run.out" 2>/dev/null || rrc=$?
    sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" > "$TMP/bare.out"
    sK.lastRc; lr="$RESULT"
    if [[ $arc -eq 0 && $erc -eq 0 && $crc -eq 0 && $frc -eq 0 && $lrc -eq 0 && $rrc -eq 0 \
          && "$an" == "3" && "$cn" == "3" && "$ln" == "3" && "$(sKL.N)" == "3" && "$fv" == "A1" \
          && "$lr" == "0" ]] \
       && arr_is SWANT A1 b2 c3 && arr_eq SGOT SWANT && arr_eq CB_RECS SWANT \
       && cmp -s "$TMP/run.out" "$TMP/bare.out"; then
        kt_test_pass "(A1 b2 c3) from all six, rc 0, lastRc 0; run byte-identical to bare sed"
    else
        kt_test_fail "toArray rc=$arc n=$an got=$(arr_show SGOT); each rc=$erc $(arr_show CB_RECS); count rc=$crc n=$cn; first rc=$frc '$fv'; toList rc=$lrc n=$ln; run rc=$rrc; lastRc=$lr want=$(arr_show SWANT)"
    fi
    sKL.delete
    sK.delete
fi

# same_as_bare TITLE INST BAREARGV... — `INST.toArray` equals the bare tool's
# newline-framed stdout, rc 0.
same_as_bare() {
    local __zt="$1" __zi="$2"; shift 2
    if ! tcase "$__zt"; then
        return 0
    fi
    SGOT=()
    local __zrc=0
    "$__zi".toArray SGOT 2>/dev/null || __zrc=$?
    oracleL SWANT "$@"
    if [[ $__zrc -eq 0 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool: $(arr_show SGOT)"
    else
        kt_test_fail "rc=$__zrc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
}

TSed.new sM '2{' "$FX/f3.txt"
sM.addExpr 's/b/J/' '}'
same_as_bare "S6: a multi-\`-e\` block (\`2{\` + \`s/b/J/\` + \`}\`) — the chunks join into ONE script" sM \
    sed --sandbox -e '2{' -e 's/b/J/' -e '}' -- "$FX/f3.txt"
sM.delete

TSed.new sM '' "$FX/f3.txt"
sM.scriptFile = "$FX/s.sed"
same_as_bare "S6: \`scriptFile\` — the script from a file (\`-f\`)" sM \
    sed --sandbox -f "$FX/s.sed" -- "$FX/f3.txt"
sM.delete

TSed.new sM 's/a/A/' "$FX/f3.txt"
sM.scriptFile = "$FX/s.sed"
same_as_bare "S6: \`expr\` + \`scriptFile\` — both apply, \`-e\` first" sM \
    sed --sandbox -e 's/a/A/' -f "$FX/s.sed" -- "$FX/f3.txt"
sM.delete

if tcase "S6: \`quiet = 1\` + \`2p\` — exactly the printed line"; then
    TSed.new sM '2p' "$FX/f3.txt"
    sM.quiet = 1
    SGOT=()
    rc=0; sM.toArray SGOT || rc=$?
    oracleL SWANT sed --sandbox -n -e 2p -- "$FX/f3.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT b2 && arr_eq SGOT SWANT; then
        kt_test_pass "(b2)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    sM.delete
fi

if tcase "S6: \`quiet = 1\` with NO \`p\` — zero records, rc 0"; then
    TSed.new sM 's/a/A/' "$FX/f3.txt"
    sM.quiet = 1
    SGOT=( stale )
    rc=0; sM.toArray SGOT || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "0" && ${#SGOT[@]} -eq 0 ]]; then
        kt_test_pass "rc 0, RESULT 0, the array emptied"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' got=$(arr_show SGOT)"
    fi
    sM.delete
fi

if tcase "S6: two files are ONE stream by default (\`\$\` = the last line of the LAST file)"; then
    TSed.new sM '$s/$/!/' "$FX/f3.txt" "$FX/f3b.txt"
    SGOT=()
    rc=0; sM.toArray SGOT || rc=$?
    oracleL SWANT sed --sandbox -e '$s/$/!/' -- "$FX/f3.txt" "$FX/f3b.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT a1 b2 c3 d4 'e5!' && arr_eq SGOT SWANT; then
        kt_test_pass "$(arr_show SGOT)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    sM.delete
fi

if tcase "S6: \`separate = 1\` makes them separate (\`\$\` = the last line of EACH file)"; then
    TSed.new sM '$s/$/!/' "$FX/f3.txt" "$FX/f3b.txt"
    sM.separate = 1
    SGOT=()
    rc=0; sM.toArray SGOT || rc=$?
    oracleL SWANT sed --sandbox -s -e '$s/$/!/' -- "$FX/f3.txt" "$FX/f3b.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT a1 b2 'c3!' d4 'e5!' && arr_eq SGOT SWANT; then
        kt_test_pass "$(arr_show SGOT)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    sM.delete
fi

if tcase "S6: an unterminated last line stays unterminated (\`run | od -c\` == bare) and is ONE record"; then
    TSed.new sM 's/u/U/' "$FX/unterm.txt"
    got="$(sM.run | od -c)"
    want="$(sed --sandbox -e 's/u/U/' -- "$FX/unterm.txt" | od -c)"
    SGOT=()
    rc=0; sM.toArray SGOT || rc=$?
    if [[ "$got" == "$want" && "$got" == *'U   2'* && "$got" != *'2  \n'* && $rc -eq 0 ]] \
       && arr_is SGOT U1 U2; then
        kt_test_pass "no newline added; records (U1 U2)"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}' rc=$rc recs=$(arr_show SGOT)"
    fi
    sM.delete
fi

if tcase "S6: \`addExpr ''\` is the IDENTITY — byte-identical to the file and to \`sed --sandbox -e ''\`"; then
    TSed.new sM '' "$FX/unterm.txt" "$FX/f3.txt"
    sM.addExpr ''
    sM.run > "$TMP/id.out" 2>/dev/null
    sed --sandbox -e '' -- "$FX/unterm.txt" "$FX/f3.txt" > "$TMP/id.bare"
    cat "$FX/unterm.txt" "$FX/f3.txt" > "$TMP/id.cat"
    sM.lastRc; lr="$RESULT"
    if [[ "$lr" == "0" ]] && cmp -s "$TMP/id.out" "$TMP/id.bare"; then
        kt_test_pass "identical to bare \`sed -e ''\` (lastRc 0)"
    else
        kt_test_fail "lastRc=$lr out=$(od -c < "$TMP/id.out" | tr '\n' '|') bare=$(od -c < "$TMP/id.bare" | tr '\n' '|')"
    fi
    sM.delete
fi

if tcase "S6: no path — \`run\` reads stdin; the path \`-\` is stdin explicitly"; then
    TSed.new sM 's/a/A/'
    sM.run < "$FX/f3.txt" > "$TMP/stdin1.out" 2>/dev/null
    TSed.new sM2 's/a/A/' '-'
    sM2.run < "$FX/f3.txt" > "$TMP/stdin2.out" 2>/dev/null
    sed --sandbox -e 's/a/A/' < "$FX/f3.txt" > "$TMP/stdin.bare"
    if cmp -s "$TMP/stdin1.out" "$TMP/stdin.bare" && cmp -s "$TMP/stdin2.out" "$TMP/stdin.bare" \
       && [[ -s "$TMP/stdin.bare" ]]; then
        kt_test_pass "both identical to bare sed on stdin"
    else
        kt_test_fail "stdin1=$(tr '\n' '|' < "$TMP/stdin1.out") stdin2=$(tr '\n' '|' < "$TMP/stdin2.out")"
    fi
    sM.delete
    sM2.delete
fi

if tcase "S6: a name with a space and a name starting with \`-\` work behind \`--\`"; then
    TSed.new sM 's/1/!/' "$FX/with space.txt"
    cd "$FX" || :
    sM.paths "with space.txt" "-dash.txt"
    SGOT=()
    rc=0; sM.toArray SGOT || rc=$?
    cd "$SCRIPT_DIR" || :
    if [[ $rc -eq 0 && "$PWD" == "$SCRIPT_DIR" ]] && arr_is SGOT 'sp!' 'dash!'; then
        kt_test_pass "(sp! dash!) — \`-dash.txt\` was read as a FILE, not an option"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) pwd=$PWD"
    fi
    sM.delete
fi

# ===========================================================================
kt_test_section "B. S5 — \`-E\` must precede the first \`-e\`"
# ===========================================================================

if tcase "S5: \`extended = 1\` + \`s/(a)1/[\\1]/\` on \`a1\` -> \`[a]\` (assigned AFTER the expression)"; then
    TSed.new sE 's/(a)1/[\1]/' "$FX/a1.txt"
    sE.extended = 1
    SGOT=()
    rc=0; sE.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT '[a]'; then
        kt_test_pass "([a]) — the group and the back-reference compiled as ERE"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT)"
    fi
    sE.delete
fi

if tcase "S5: the reason — bare \`sed -e 's/(a)1/[\\1]/' -E\` is rc 1 (each \`-e\` compiles when read)"; then
    sed -e 's/(a)1/[\1]/' -E -- "$FX/a1.txt" >/dev/null 2>"$ERRF"; brc=$?
    berr="$(<"$ERRF")"
    if [[ $brc -eq 1 && "$berr" == "sed: "* ]]; then
        kt_test_pass "rc 1: ${berr:0:70}"
    else
        kt_test_fail "rc=$brc err='$berr'"
    fi
fi

# ===========================================================================
kt_test_section "C. S7 — partial failures, I/O errors, and the script's own q/Q status"
# ===========================================================================

# PLAN §2.4: the family contract with a missing file among good ones — NOT
# "every sink rc 1 + count".
TSed.new sP 's/a/A/' "$FX/f3.txt" "$FX/no_such.txt"

if tcase "S7: missing file among good ones — \`toArray\` rc 1, RESULT = the real count, lastRc 2"; then
    SGOT=()
    rc=0; sP.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    sP.lastRc; lr="$RESULT"
    oracleL SWANT sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" "$FX/no_such.txt"
    if [[ $rc -eq 1 && "$n" == "3" && "$lr" == "2" ]] && arr_is SGOT A1 b2 c3 && arr_eq SGOT SWANT; then
        kt_test_pass "rc 1, RESULT 3, lastRc 2 — the good file's records identical to the bare tool"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
fi

if tcase "S7: missing file among good ones — \`count\` rc 1 RESULT 3; \`toList\` rc 1 RESULT 3"; then
    rc=0; sP.count 2>/dev/null || rc=$?; cn="$RESULT"
    TSTestList.new sPL
    lrc=0; sP.toList sPL 2>/dev/null || lrc=$?; ln="$RESULT"
    if [[ $rc -eq 1 && "$cn" == "3" && $lrc -eq 1 && "$ln" == "3" && "$(sPL.N)" == "3" ]]; then
        kt_test_pass "count rc 1 / 3; toList rc 1 / 3 offered, 3 stored"
    else
        kt_test_fail "count rc=$rc n=$cn; toList rc=$lrc n=$ln stored=$(sPL.N)"
    fi
    sPL.delete
fi

if tcase "S7: missing file among good ones — \`each\` rc 1, three callbacks, RESULT UNTOUCHED (a proc)"; then
    CB_RECS=()
    RESULT="each-sentinel"
    rc=0; sP.each cb_collect 2>/dev/null || rc=$?
    r="$RESULT"
    if [[ $rc -eq 1 && "$r" == "each-sentinel" ]] && arr_is CB_RECS A1 b2 c3; then
        kt_test_pass "rc 1, (A1 b2 c3) delivered, RESULT still the caller's"
    else
        kt_test_fail "rc=$rc RESULT='$r' recs=$(arr_show CB_RECS)"
    fi
fi

if tcase "S7: missing file among good ones — \`first\` rc 0, the first record, lastRc 2, NO line of ours"; then
    ts_dbg sP.first
    fv="$RESULT"
    sP.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "0" && "$TS_N" == "0" && "$fv" == "A1" && "$lr" == "2" ]]; then
        kt_test_pass "rc 0, RESULT 'A1', lastRc 2, no diagnostic of ours (TUtil's consumer-stop contract)"
    else
        kt_test_fail "rc=$TS_RC ourLines=$TS_N first='$TS_1' RESULT='$fv' lastRc='$lr'"
    fi
fi

if tcase "S7: the partial path says ONE line of ours, worded per Q3; sed's own line passes through"; then
    ts_dbg sP.count
    if [[ "$TS_RC" == "1" && "$TS_N" == "1" && "$TOOL_N" == "1" && "$TOOL_1" == "sed: "* \
          && "$TS_1" == *"TSed"* && "$TS_1" == *"sed exited 2 (a sed error, or the script's q/Q 2)"* ]]; then
        kt_test_pass "ours: ${TS_1:0:80} | sed's: '${TOOL_1:0:50}'"
    else
        kt_test_fail "rc=$TS_RC ourLines=$TS_N first='$TS_1' toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
fi
sP.delete

if tcase "S7: a DIRECTORY operand — rc 1, lastRc 4, earlier records kept, the LATER file NOT read"; then
    TSed.new sD 's/a/A/' "$FX/f3.txt" "$FX/dir" "$FX/f3b.txt"
    SGOT=()
    rc=0; sD.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    sD.lastRc; lr="$RESULT"
    oracleL SWANT sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" "$FX/dir" "$FX/f3b.txt"
    if [[ $rc -eq 1 && "$n" == "3" && "$lr" == "4" ]] && arr_is SGOT A1 b2 c3 && arr_eq SGOT SWANT; then
        kt_test_pass "(A1 b2 c3), no d4/e5 — rc 4 STOPS at the operand (not partial like rc 2)"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    sD.delete
fi

if tcase "S7: a MISSING \`-f\` script — rc 1, lastRc 4, zero records, one line of ours"; then
    TSed.new sD '' "$FX/f3.txt"
    sD.scriptFile = "$FX/no_such.sed"
    SGOT=( stale )
    ts_dbg sD.toArray SGOT
    sD.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "1" && "$lr" == "4" && ${#SGOT[@]} -eq 0 && "$TS_N" == "1" \
          && "$TS_1" == *"sed exited 4"* && "$TOOL_1" == "sed: "* ]]; then
        kt_test_pass "rc 1, lastRc 4, nothing read: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lastRc='$lr' got=$(arr_show SGOT) ourLines=$TS_N first='$TS_1' tool='$TOOL_1'"
    fi
    sD.delete
fi

if tcase "S7: a BAD script (\`s/a\`) — rc 1, lastRc 1, zero records, one line of ours"; then
    TSed.new sD 's/a' "$FX/f3.txt"
    SGOT=( stale )
    ts_dbg sD.toArray SGOT
    sD.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "1" && "$lr" == "1" && ${#SGOT[@]} -eq 0 && "$TS_N" == "1" \
          && "$TS_1" == *"sed exited 1 (a sed error, or the script's q/Q 1)"* && "$TOOL_1" == "sed: -e expression #1"* ]]; then
        kt_test_pass "rc 1, lastRc 1: ${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC lastRc='$lr' got=$(arr_show SGOT) ourLines=$TS_N first='$TS_1' tool='$TOOL_1'"
    fi
    sD.delete
fi

if tcase "S7: \`2q7\` — rc 1 SILENT, lastRc 7, the two lines delivered (a script status, not an error)"; then
    TSed.new sQ '2q7' "$FX/f3.txt"
    SGOT=()
    ts_dbg sQ.toArray SGOT
    n="$RESULT"
    sQ.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "1" && "$TS_N" == "0" && "$TOOL_N" == "0" && "$lr" == "7" && "$n" == "2" ]] \
       && arr_is SGOT a1 b2; then
        kt_test_pass "rc 1, lastRc 7, (a1 b2), not one line on stderr"
    else
        kt_test_fail "rc=$TS_RC ourLines=$TS_N first='$TS_1' toolLines=$TOOL_N lastRc='$lr' RESULT='$n' got=$(arr_show SGOT)"
    fi
    sQ.delete
fi

if tcase "S7: \`2q1\` — rc 1 WITH the debug line (indistinguishable from sed's own 1, worded to say so)"; then
    TSed.new sQ '2q1' "$FX/f3.txt"
    SGOT=()
    ts_dbg sQ.toArray SGOT
    sQ.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "1" && "$TS_N" == "1" && "$TOOL_N" == "0" && "$lr" == "1" \
          && "$TS_1" == *"sed exited 1 (a sed error, or the script's q/Q 1)"* ]] && arr_is SGOT a1 b2; then
        kt_test_pass "rc 1, lastRc 1, (a1 b2): ${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC ourLines=$TS_N first='$TS_1' lastRc='$lr' got=$(arr_show SGOT)"
    fi
    sQ.delete
fi

if tcase "S7: \`q256\` wraps to 0 (N mod 256) — rc 0, lastRc 0"; then
    TSed.new sQ '1q256' "$FX/f3.txt"
    SGOT=()
    rc=0; sQ.toArray SGOT 2>/dev/null || rc=$?
    sQ.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$lr" == "0" ]] && arr_is SGOT a1; then
        kt_test_pass "rc 0, lastRc 0, (a1)"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got=$(arr_show SGOT)"
    fi
    sQ.delete
fi

# ===========================================================================
kt_test_section "D. S8 — the sandbox default (owner Q1)"
# ===========================================================================

MK="$FX/markers"
mkdir -p "$MK"
printf '1w %s\n' "$MK/m_fw" > "$FX/w.sed"

# sbox TITLE MARKER SETUP... — the default instance must be rc 1, lastRc 1, zero
# records, one line of ours, sed's `e/r/w commands disabled` line, and the
# marker file must NOT exist. SETUP words are `expr=…`, `add=…`, `file=…`.
sbox() {
    local __zt="$1" __zm="$2"; shift 2
    if ! tcase "$__zt"; then
        return 0
    fi
    rm -f "$__zm"
    TSed.new sS '' "$FX/f3.txt"
    local __zw
    for __zw in "$@"; do
        case "$__zw" in
            expr=*) sS.expr = "${__zw#expr=}" ;;
            add=*)  sS.addExpr "${__zw#add=}" ;;
            file=*) sS.scriptFile = "${__zw#file=}" ;;
        esac
    done
    SGOT=( stale )
    ts_dbg sS.toArray SGOT
    sS.lastRc
    local __zlr="$RESULT"
    if [[ "$TS_RC" == "1" && "$__zlr" == "1" && ${#SGOT[@]} -eq 0 && "$TS_N" == "1" \
          && "$TOOL_1" == "sed: "*"disabled in sandbox mode"* && ! -e "$__zm" ]]; then
        kt_test_pass "refused at compile time: '${TOOL_1:0:70}'; no marker"
    else
        kt_test_fail "rc=$TS_RC lastRc='$__zlr' got=$(arr_show SGOT) ourLines=$TS_N tool='$TOOL_1' marker=$([[ -e $__zm ]] && echo present || echo absent)"
    fi
    sS.delete
}

sbox "S8: \`s///e\` is refused by default"                 "$MK/m_se" "expr=1s|.*|touch $MK/m_se|e"
sbox "S8: the \`e\` command is refused by default"        "$MK/m_e"  "expr=1e touch $MK/m_e"
sbox "S8: \`w FILE\` is refused by default"               "$MK/m_w"  "expr=1w $MK/m_w"
sbox "S8: \`r FILE\` is refused by default"               "$MK/m_r"  "expr=1r $FX/f3b.txt"
sbox "S8: an \`e\` in a LATER \`-e\` is refused too (compile time, whole script)" "$MK/m_le" \
     "expr=s/a/A/" "add=1e touch $MK/m_le"
sbox "S8: a \`-f\` script with \`w\` is refused too"      "$MK/m_fw" "file=$FX/w.sed"

if tcase "S8: \`s/a/X/w /dev/stdout\` is refused by default (use \`p\`) — nothing doubled"; then
    TSed.new sS 's/a/X/w /dev/stdout' "$FX/f3.txt"
    SGOT=( stale )
    ts_dbg sS.toArray SGOT
    if [[ "$TS_RC" == "1" && ${#SGOT[@]} -eq 0 && "$TOOL_1" == *"disabled in sandbox mode"* ]]; then
        kt_test_pass "rc 1, zero records"
    else
        kt_test_fail "rc=$TS_RC got=$(arr_show SGOT) tool='$TOOL_1'"
    fi
    sS.delete
fi

if tcase "S8: \`sandbox = 0\` RUNS \`s///e\`, \`e\`, \`w\` and the \`-f\` script — every marker appears"; then
    rm -f "$MK"/m_*
    ok=1
    for spec in "1s|.*|touch $MK/m_se|e" "1e touch $MK/m_e" "1w $MK/m_w"; do
        TSed.new sS "$spec" "$FX/f3.txt"
        sS.sandbox = 0
        rc=0; sS.count 2>/dev/null || rc=$?
        [[ $rc -eq 0 ]] || ok=0
        sS.delete
    done
    TSed.new sS '' "$FX/f3.txt"
    sS.sandbox = 0
    sS.scriptFile = "$FX/w.sed"
    rc=0; sS.count 2>/dev/null || rc=$?
    [[ $rc -eq 0 ]] || ok=0
    sS.delete
    if [[ "$ok" == "1" && -e "$MK/m_se" && -e "$MK/m_e" && -e "$MK/m_w" && -e "$MK/m_fw" ]] \
       && [[ "$(<"$MK/m_w")" == "a1" ]]; then
        kt_test_pass "rc 0 each; m_se, m_e, m_w (holding 'a1') and m_fw created"
    else
        kt_test_fail "ok=$ok markers: $(ls "$MK" 2>/dev/null | tr '\n' ' ')"
    fi
fi

if tcase "S8: \`sandbox = 0\` + \`s/a/X/w /dev/stdout\` doubles the line, exactly like the bare tool"; then
    TSed.new sS 's/a/X/w /dev/stdout' "$FX/f3.txt"
    sS.sandbox = 0
    SGOT=()
    rc=0; sS.toArray SGOT || rc=$?
    oracleL SWANT sed -e 's/a/X/w /dev/stdout' -- "$FX/f3.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT X1 X1 b2 c3 && arr_eq SGOT SWANT; then
        kt_test_pass "(X1 X1 b2 c3)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    sS.delete
fi

# ===========================================================================
kt_test_section "E. S9 — the CR (owner Q5)"
# ===========================================================================

if tcase "S9: text mode STRIPS the CR — records (a1 b2), bytes == bare sed, no \\r in the stream"; then
    TSed.new sC '' "$FX/crlf.txt"
    sC.addExpr ''
    SGOT=()
    rc=0; sC.toArray SGOT || rc=$?
    got="$(sC.run | od -c)"
    want="$(sed --sandbox -e '' -- "$FX/crlf.txt" | od -c)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$got" != *'\r'* ]] && arr_is SGOT a1 b2; then
        kt_test_pass "(a1 b2); the tool ate the CR itself (crlf is a no-op here)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) od='${got//$'\n'/|}'"
    fi
    sC.delete
fi

if tcase "S9: \`binary = 1\` KEEPS the CR — records (a1\\r b2\\r)"; then
    TSed.new sC '' "$FX/crlf.txt"
    sC.addExpr ''
    sC.binary = 1
    SGOT=()
    rc=0; sC.toArray SGOT || rc=$?
    got="$(sC.run | od -c)"
    want="$(od -c < "$FX/crlf.txt")"
    if [[ $rc -eq 0 && "$got" == "$want" ]] && arr_is SGOT "a1$CR" "b2$CR"; then
        kt_test_pass "the file's bytes, untouched"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) od='${got//$'\n'/|}'"
    fi
    sC.delete
fi

if tcase "S9: \`binary = 1\` + \`crlf = 1\` strips EXACTLY one CR (\`c3\\r\\r\` -> \`c3\\r\`)"; then
    TSed.new sC '' "$FX/cr2.txt" "$FX/crlf.txt"
    sC.addExpr ''
    sC.binary = 1
    sC.crlf = 1
    SGOT=()
    rc=0; sC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "c3$CR" a1 b2; then
        kt_test_pass "(c3\\r a1 b2)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT)"
    fi
    sC.delete
fi

if tcase "S9: \`inPlace = 1\` on a CRLF file keeps EVERY CR on disk (the derived -b); bare \`sed -i\` does not"; then
    cp "$FX/crlf.txt" "$FX/ip_crlf.txt"
    cp "$FX/crlf.txt" "$FX/ip_bare.txt"
    TSed.new sC 's/a/A/' "$FX/ip_crlf.txt"
    sC.inPlace = 1
    rc=0; sC.run > "$TMP/ip.out" 2>/dev/null || rc=$?
    sed -i -e 's/a/A/' -- "$FX/ip_bare.txt"
    got="$(odf "$FX/ip_crlf.txt")"
    want="$(printf 'A1\r\nb2\r\n' | od -c)"
    bare="$(odf "$FX/ip_bare.txt")"
    bwant="$(printf 'A1\nb2\n' | od -c)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$bare" == "$bwant" && ! -s "$TMP/ip.out" ]]; then
        kt_test_pass "wrapper: A1\\r\\nb2\\r\\n on disk; bare \`sed -i\`: A1\\nb2\\n (why Q5 derives -b)"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' bare='${bare//$'\n'/|}'"
    fi
    sC.delete
fi

if tcase "S9: \`nullData = 1\` keeps a CR embedded in a NUL record (bare \`sed -z\` strips it)"; then
    TSed.new sC '' "$FX/nul.bin"
    sC.addExpr ''
    sC.nullData = 1
    SGOT=()
    rc=0; sC.toArray SGOT || rc=$?
    oracle0 SWANT sed -z -e '' -- "$FX/nul.bin"
    if [[ $rc -eq 0 ]] && arr_is SGOT a "x$CR"$'\n'"y" last && arr_is SWANT a $'x\ny' last; then
        kt_test_pass "(a 'x\\r\\ny' last); the bare text-mode -z gives 'x\\ny'"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) bare=$(arr_show SWANT)"
    fi
    sC.delete
fi

# ===========================================================================
kt_test_section "F. S10 — \`-z\` NUL records"
# ===========================================================================

if tcase "S10: \`nullData = 1\` — NUL records through the derived \`-0\`, the sinks agree"; then
    TSed.new sZ 's/^/>/' "$FX/nul.bin"
    sZ.nullData = 1
    SGOT=()
    rc=0; sZ.toArray SGOT || rc=$?
    crc=0; sZ.count || crc=$?; cn="$RESULT"
    frc=0; sZ.first || frc=$?; fv="$RESULT"
    oracle0 SWANT sed --sandbox -z -b -e 's/^/>/' -- "$FX/nul.bin"
    if [[ $rc -eq 0 && $crc -eq 0 && "$cn" == "3" && $frc -eq 0 && "$fv" == ">a" \
          && "$(sZ.nul)" == "1" ]] && arr_eq SGOT SWANT && arr_is SGOT '>a' ">x$CR"$'\n'"y" '>last'; then
        kt_test_pass "3 records, nul = 1 derived, first '>a'"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) count rc=$crc n=$cn first rc=$frc '$fv' nul=$(sZ.nul)"
    fi
    sZ.delete
fi

if tcase "S10: the unterminated last NUL record stays unterminated (\`run | od -c\` == bare)"; then
    TSed.new sZ 's/^/>/' "$FX/nul.bin"
    sZ.nullData = 1
    sZ.run > "$TMP/z.out" 2>/dev/null
    sed --sandbox -z -b -e 's/^/>/' -- "$FX/nul.bin" > "$TMP/z.bare"
    last="$(tail -c 4 "$TMP/z.out")"
    if cmp -s "$TMP/z.out" "$TMP/z.bare" && [[ "$last" == "last" ]]; then
        kt_test_pass "byte-identical; the stream ends in 'last' with no NUL"
    else
        kt_test_fail "out=$(od -c < "$TMP/z.out" | tr '\n' '|') bare=$(od -c < "$TMP/z.bare" | tr '\n' '|')"
    fi
    sZ.delete
fi

# ===========================================================================
kt_test_section "G. S11 — in-place (owner Q4)"
# ===========================================================================

F3_OD="$(odf "$FX/f3.txt")"

if tcase "S11: \`inPlace = 1\` + \`run\` edits the file, stdout EMPTY, rc 0, lastRc 0, no backup"; then
    cp "$FX/f3.txt" "$FX/ip1.txt"
    TSed.new sI 's/a/A/' "$FX/ip1.txt"
    sI.inPlace = 1
    rc=0; sI.run > "$TMP/ip1.out" 2>/dev/null || rc=$?
    sI.lastRc; lr="$RESULT"
    got="$(odf "$FX/ip1.txt")"
    want="$(printf 'A1\nb2\nc3\n' | od -c)"
    nback="$(ls "$FX" | grep -c '^ip1\.txt.' || :)"
    if [[ $rc -eq 0 && "$lr" == "0" && "$got" == "$want" && ! -s "$TMP/ip1.out" && "$nback" == "0" ]]; then
        kt_test_pass "A1 b2 c3 on disk, nothing on stdout"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got='${got//$'\n'/|}' stdout=$(wc -c < "$TMP/ip1.out") backups=$nback"
    fi
    sI.delete
fi

if tcase "S11: \`backupSuffix = .bak\` keeps the original as \`FILE.bak\`"; then
    cp "$FX/f3.txt" "$FX/ip2.txt"
    TSed.new sI 's/a/A/' "$FX/ip2.txt"
    sI.inPlace = 1
    sI.backupSuffix = .bak
    rc=0; sI.run 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && "$(odf "$FX/ip2.txt.bak")" == "$F3_OD" \
          && "$(odf "$FX/ip2.txt")" == "$(printf 'A1\nb2\nc3\n' | od -c)" ]]; then
        kt_test_pass "ip2.txt edited, ip2.txt.bak holds the original bytes"
    else
        kt_test_fail "rc=$rc files: $(ls "$FX" | tr '\n' ' ')"
    fi
    sI.delete
fi

# `*` in the suffix is replaced by the OPERAND AS GIVEN, directory part
# included (measured at P0 on sed 4.9 — PLAN §1.1 said "the base name", which
# holds only for an operand without a directory). So `bak_*` on a bare `ip3.txt`
# is `bak_ip3.txt`; on `DIR/ip3b.txt` it is `bak_DIR/ip3b.txt`, a directory that
# does not exist -> rc 4, the file untouched. The `cd` happens in THIS shell and
# is undone at once.
if tcase "S11: \`backupSuffix = 'bak_*'\` on a BARE operand names the backup \`bak_FILE\`"; then
    cp "$FX/f3.txt" "$FX/ip3.txt"
    cd "$FX" || :
    TSed.new sI 's/a/A/' ip3.txt
    sI.inPlace = 1
    sI.backupSuffix = 'bak_*'
    rc=0; sI.run 2>/dev/null || rc=$?
    cd "$SCRIPT_DIR" || :
    if [[ $rc -eq 0 && "$PWD" == "$SCRIPT_DIR" && -f "$FX/bak_ip3.txt" && "$(odf "$FX/bak_ip3.txt")" == "$F3_OD" \
          && "$(odf "$FX/ip3.txt")" == "$(printf 'A1\nb2\nc3\n' | od -c)" ]]; then
        kt_test_pass "bak_ip3.txt holds the original, ip3.txt edited"
    else
        kt_test_fail "rc=$rc pwd=$PWD files: $(ls "$FX" | tr '\n' ' ')"
    fi
    sI.delete
fi

if tcase "S11: \`bak_*\` on an operand WITH a directory — \`*\` is the whole operand: rc 1, lastRc 4, untouched"; then
    cp "$FX/f3.txt" "$FX/ip3b.txt"
    TSed.new sI 's/a/A/' "$FX/ip3b.txt"
    sI.inPlace = 1
    sI.backupSuffix = 'bak_*'
    rc=0; sI.run 2>/dev/null || rc=$?
    sI.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == "4" && "$(odf "$FX/ip3b.txt")" == "$F3_OD" && ! -e "$FX/bak_ip3b.txt" ]]; then
        kt_test_pass "rc 1, lastRc 4, ip3b.txt byte-identical, no bak_ip3b.txt — README trap"
    else
        kt_test_fail "rc=$rc lastRc='$lr' files: $(ls "$FX" | tr '\n' ' ')"
    fi
    sI.delete
fi

if tcase "S11: \`backupSuffix = '*'\` is rc 2 — nothing runs, the file byte-identical"; then
    cp "$FX/f3.txt" "$FX/ip4.txt"
    TSed.new sI 's/a/A/' "$FX/ip4.txt"
    sI.inPlace = 1
    sI.backupSuffix = '*'
    ts_dbg sI.run
    sI.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TS_1" == *"backupSuffix"* && "$lr" == "-1" \
          && "$(odf "$FX/ip4.txt")" == "$F3_OD" ]]; then
        kt_test_pass "rc 2, lastRc -1, untouched: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' lastRc='$lr'"
    fi
    sI.delete
fi

if tcase "S11: a MISSING backup directory (\`nodir/*\`) — rc 1, lastRc 4, the file untouched"; then
    cp "$FX/f3.txt" "$FX/ip5.txt"
    TSed.new sI 's/a/A/' "$FX/ip5.txt"
    sI.inPlace = 1
    sI.backupSuffix = 'nodir/*'
    ts_dbg sI.run
    sI.lastRc; lr="$RESULT"
    if [[ "$TS_RC" == "1" && "$lr" == "4" && "$TS_N" == "1" && "$TOOL_1" == "sed: "* \
          && "$(odf "$FX/ip5.txt")" == "$F3_OD" ]]; then
        kt_test_pass "rc 1, lastRc 4, bytes unchanged; sed: '${TOOL_1:0:50}'"
    else
        kt_test_fail "rc=$TS_RC lastRc='$lr' ourLines=$TS_N tool='$TOOL_1' bytes=$(odf "$FX/ip5.txt" | tr '\n' '|')"
    fi
    sI.delete
fi

if tcase "S11: a DIRECTORY before a good file — rc 1, lastRc 4, the good file NOT edited (rc 4 stops)"; then
    cp "$FX/f3.txt" "$FX/ip6.txt"
    TSed.new sI 's/a/A/' "$FX/dir" "$FX/ip6.txt"
    sI.inPlace = 1
    rc=0; sI.run 2>/dev/null || rc=$?
    sI.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == "4" && "$(odf "$FX/ip6.txt")" == "$F3_OD" ]]; then
        kt_test_pass "ip6.txt byte-identical"
    else
        kt_test_fail "rc=$rc lastRc='$lr' bytes=$(odf "$FX/ip6.txt" | tr '\n' '|')"
    fi
    sI.delete
fi

if tcase "S11: the documented TRAP — \`inPlace\` + \`2q\` TRUNCATES the file silently (rc 0)"; then
    cp "$FX/f3.txt" "$FX/ip7.txt"
    TSed.new sI '2q' "$FX/ip7.txt"
    sI.inPlace = 1
    rc=0; sI.run 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && "$(odf "$FX/ip7.txt")" == "$(printf 'a1\nb2\n' | od -c)" ]]; then
        kt_test_pass "c3 is gone from disk, rc 0 — README trap"
    else
        kt_test_fail "rc=$rc bytes=$(odf "$FX/ip7.txt" | tr '\n' '|')"
    fi
    sI.delete
fi

# refuse_sink TITLE MEMBER [ARG] — inPlace = 1: rc 2, ONE line naming the
# in-place rule, the file byte-identical, `_lastRc` still -1.
tsd_never() { : > "$TMP/never.flag"; printf 'ran\n'; }
declare -a REF_ARR=()
TSTestList.new sRL
cb_nul() { return 0; }

refuse_sink() {
    local __zt="$1" __zm="$2" __za="${3:-}"
    if ! tcase "$__zt"; then
        return 0
    fi
    cp "$FX/f3.txt" "$FX/ipr.txt"
    TSed.new sR 's/a/A/' "$FX/ipr.txt"
    sR.inPlace = 1
    RESULT="sentinel"
    ts_dbg sR."$__zm" ${__za:+"$__za"}
    local __zr="$RESULT"
    sR.lastRc
    local __zlr="$RESULT"
    # the same sink once more with a producer that leaves a flag file
    rm -f "$TMP/never.flag"
    sR.cmd = tsd_never
    sR."$__zm" ${__za:+"$__za"} >/dev/null 2>&1
    local __zrc2=$?
    # `each` is a proc: RESULT is the caller's; the four funcs answer RESULT ''.
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TS_1" == *"TSed.$__zm"* && "$TS_1" == *"in-place"* \
          && "$TS_1" == *"use run"* && "$__zlr" == "-1" && "$__zrc2" == "2" && ! -e "$TMP/never.flag" \
          && "$(odf "$FX/ipr.txt")" == "$F3_OD" ]] \
       && { [[ "$__zm" == "each" && "$__zr" == "sentinel" ]] || [[ "$__zm" != "each" && "$__zr" == "" ]]; }; then
        kt_test_pass "rc 2, one line, file byte-identical, lastRc -1, nothing ran: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' RESULT='$__zr' lastRc='$__zlr' rc2=$__zrc2 flag=$([[ -e $TMP/never.flag ]] && echo present || echo absent) bytes=$(odf "$FX/ipr.txt" | tr '\n' '|')"
    fi
    sR.delete
}

refuse_sink "S11: \`each\` with \`inPlace = 1\` is rc 2 and NOTHING runs"    each    cb_nul
refuse_sink "S11: \`toArray\` with \`inPlace = 1\` is rc 2 and NOTHING runs" toArray REF_ARR
refuse_sink "S11: \`toList\` with \`inPlace = 1\` is rc 2 and NOTHING runs"  toList  sRL
refuse_sink "S11: \`first\` with \`inPlace = 1\` is rc 2 and NOTHING runs"   first
refuse_sink "S11: \`count\` with \`inPlace = 1\` is rc 2 and NOTHING runs"   count

if tcase "S11: the refusal leaves the caller's array alone"; then
    TSed.new sR 's/a/A/' "$FX/f3.txt"
    sR.inPlace = 1
    REF_ARR=( keep1 keep2 )
    rc=0; sR.toArray REF_ARR 2>/dev/null || rc=$?
    if [[ $rc -eq 2 && "$RESULT" == "" ]] && arr_is REF_ARR keep1 keep2; then
        kt_test_pass "rc 2, RESULT '', (keep1 keep2)"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' arr=$(arr_show REF_ARR)"
    fi
    sR.delete
fi

if tcase "S11: \`inPlace\` back to 0 — the same instance's sinks work again"; then
    TSed.new sR 's/a/A/' "$FX/f3.txt"
    sR.inPlace = 1
    sR.count >/dev/null 2>&1
    sR.inPlace = 0
    rc=0; sR.count || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "3" ]]; then
        kt_test_pass "count rc 0, 3"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
    sR.delete
fi

# --debug writes SED PROGRAM:/INPUT:/PATTERN: to STDOUT, i.e. into the records:
# the sinks refuse it the same way, and `run` streams it.
if tcase "S11 (§2.4): \`--debug\` among the extras — every sink rc 2, \`run\` streams the debug output"; then
    TSed.new sG 's/a/A/' "$FX/f3.txt"
    sG.addArg --debug
    bad=""
    for m in each toArray toList first count; do
        case "$m" in
            each)    ts_dbg sG.each cb_nul ;;
            toArray) ts_dbg sG.toArray REF_ARR ;;
            toList)  ts_dbg sG.toList sRL ;;
            *)       ts_dbg sG."$m" ;;
        esac
        [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TS_1" == *"--debug"* && "$TS_1" == *"use run"* ]] \
            || bad+=" $m:rc=$TS_RC,n=$TS_N,'$TS_1'"
    done
    sG.lastRc; lr="$RESULT"
    rc=0; sG.run > "$TMP/dbg.out" 2>/dev/null || rc=$?
    firstline="$(head -1 "$TMP/dbg.out")"
    if [[ -z "$bad" && "$lr" == "-1" && $rc -eq 0 && "$firstline" == "SED PROGRAM:" ]]; then
        kt_test_pass "five sinks rc 2 (lastRc stayed -1); run rc 0, first line 'SED PROGRAM:'"
    else
        kt_test_fail "bad:$bad lastRc='$lr' run rc=$rc first='$firstline'"
    fi
    sG.delete
fi
sRL.delete

# ===========================================================================
kt_test_section "H. S12 — \`TSed.edit EXPR PATH...\`, the static one-liner (§2.7)"
# ===========================================================================

if tcase "S12: \`TSed.edit 's/a/A/' f\` == \`sed --sandbox -e 's/a/A/' -- f\`, DIRECT (bytes)"; then
    rc=0; TSed.edit 's/a/A/' "$FX/f3.txt" > "$TMP/e1.out" 2>/dev/null || rc=$?
    sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" > "$TMP/e1.bare"
    if [[ $rc -eq 0 && -s "$TMP/e1.bare" ]] && cmp -s "$TMP/e1.out" "$TMP/e1.bare"; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc out=$(tr '\n' '|' < "$TMP/e1.out")"
    fi
fi

if tcase "S12: the same through a PIPE (\`| od -c\`) — byte-identical"; then
    got="$(TSed.edit 's/a/A/' "$FX/f3.txt" "$FX/unterm.txt" 2>/dev/null | od -c)"
    want="$(sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" "$FX/unterm.txt" | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream (two files, the unterminated tail kept)"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "S12: the same through \`< <( )\` — byte-identical"; then
    got="$(od -c < <(TSed.edit 's/a/A/' "$FX/f3.txt" 2>/dev/null))"
    want="$(sed --sandbox -e 's/a/A/' -- "$FX/f3.txt" | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "S12: \`TSed.edit '' f\` is the IDENTITY (== \`sed --sandbox -e '' -- f\` == the file)"; then
    rc=0; TSed.edit '' "$FX/unterm.txt" > "$TMP/e2.out" 2>/dev/null || rc=$?
    sed --sandbox -e '' -- "$FX/unterm.txt" > "$TMP/e2.bare"
    if [[ $rc -eq 0 ]] && cmp -s "$TMP/e2.out" "$TMP/e2.bare" && cmp -s "$TMP/e2.out" "$FX/unterm.txt"; then
        kt_test_pass "rc 0; the file's own bytes (an empty EXPR is a real \`-e ''\`, not 'no script')"
    else
        kt_test_fail "rc=$rc out=$(od -c < "$TMP/e2.out" | tr '\n' '|')"
    fi
fi

if tcase "S12: \`TSed.edit EXPR\` with NO path is rc 2, prints nothing, one line"; then
    ts_dbg TSed.edit 's/a/A/'
    out="$(TSed.edit 's/a/A/' 2>/dev/null <<< 'stdin-must-not-be-read')"
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" && -z "$out" && "$TS_1" == *"TSed.edit"* ]]; then
        kt_test_pass "rc 2 (with none sed reads the caller's stdin): ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N out='$out' first='$TS_1'"
    fi
fi

if tcase "S12: \`TSed.edit\` with NO argument at all is rc 2 too"; then
    ts_dbg TSed.edit
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" ]]; then
        kt_test_pass "rc 2, one line"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1'"
    fi
fi

if tcase "S12: \`edit\` with \`s///e\` is REFUSED (sandbox forced) — rc 1, no marker"; then
    rm -f "$MK/m_edit"
    ts_dbg TSed.edit "1s|.*|touch $MK/m_edit|e" "$FX/f3.txt"
    if [[ "$TS_RC" == "1" && "$TOOL_1" == *"disabled in sandbox mode"* && ! -e "$MK/m_edit" ]]; then
        kt_test_pass "rc 1; '${TOOL_1:0:60}'"
    else
        kt_test_fail "rc=$TS_RC tool='$TOOL_1' marker=$([[ -e $MK/m_edit ]] && echo present || echo absent)"
    fi
fi

if tcase "S12: \`edit\` on a MISSING file is rc 1 with one line of ours (sed's 2, mapped)"; then
    ts_dbg TSed.edit 's/a/A/' "$FX/no_such.txt"
    if [[ "$TS_RC" == "1" && "$TS_N" == "1" && "$TS_1" == *"sed exited 2"* && "$TOOL_1" == "sed: "* ]]; then
        kt_test_pass "rc 1: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' tool='$TOOL_1'"
    fi
fi

if tcase "S12: \`edit\` deletes its throw-away instance and bumps \`__TSD_SEQ\`"; then
    before="$__TSD_SEQ"
    TSed.edit 's/a/A/' "$FX/f3.txt" >/dev/null 2>&1
    TSed.edit 's/a/A/' "$FX/f3.txt" >/dev/null 2>&1
    after="$__TSD_SEQ"
    left=""
    for s in "$(( before + 1 ))" "$after"; do
        nm="__tsd_e_${BASHPID}_${s}"
        for a in _data _paths _exprs _args _argv; do
            declare -p "${nm}${a}" >/dev/null 2>&1 && left+=" ${nm}${a}"
        done
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TSD_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(TSed.edit 's/b/B/' "$FX/f3b.txt" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "S12: a nested \`edit\` inside an outer \`each\` — both complete, the outer instance survives"; then
    TSed.new sT 's/a/A/' "$FX/f3.txt"
    NEST_OUT=(); NEST_IN=()
    rc=0; sT.each cb_nest 2>/dev/null || rc=$?
    SGOT=()
    arc=0; sT.argv SGOT || arc=$?
    sT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == $'d4\ne5' ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_IN[@]} -eq 3 && "$inner_ok" == "1" && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is NEST_OUT A1 b2 c3 && arr_is SGOT sed --sandbox -e 's/a/A/' -- "$FX/f3.txt"; then
        kt_test_pass "3 outer records, 3 nested edits, the outer argv untouched"
    else
        kt_test_fail "rc=$rc outer=$(arr_show NEST_OUT) inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    sT.delete
fi

if tcase "S12: \`edit\` composes with both TPipe forms"; then
    N1=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- TSed.edit 's/a/A/' "$FX/f3.txt" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
N=0
cb() { N=$(( N + 1 )); return 0; }
TSed.edit "s/a/A/" "$FX/f3.txt" | TPipe.each cb
printf "%s" "$N"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "3" && $crc -eq 0 && "$out" == "3" ]]; then
        kt_test_pass "the \`--\` form: 3 records; the lastpipe form: 3 records"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi
