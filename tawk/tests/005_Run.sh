#!/bin/bash
# 005_Run.sh — tawk P0: TAwk against the real tool on a real fixture tree
# (tawk/PLAN.md §1.1, §2.2–§2.7, §4; pinned facts A5–A12).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same
# arguments — never a second call into the code under test. The fixture tree is
# built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework
# tears it down; this file installs NO `trap … EXIT` of its own.
#
# TWO gawk versions: bash 5.2.37 resolves Git for Windows' gawk 5.0.0, bash
# 5.3.9 msys64's 5.4.0. Their message texts differ, so gawk's own lines are
# matched by the `gawk: ` PREFIX — except the directory warning, identical on
# both and pinned exactly. Behaviour, not text, is what the cases pin.
#
# THE GATE IS THE FIRST CASE. D4 pins the GNU dialect, not a binary: if
# `gawk --version` does not begin with `GNU Awk `, every behavioural case below
# is a loud `SKIP`, so the case COUNT is the same either way.
#
# STDIN IS CLOSED for the whole file (`exec </dev/null`): gawk with no program
# operand, or with a path it takes for the program, reads stdin and would HANG.
# A case that means to feed stdin redirects it explicitly.
#
# Sections:
#   Z        the banner gate and the fixture tree
#   A  A6    every sink vs bare gawk; multi-chunk programs in order; `-f` after
#            `-e`; `-F` (a regex, escapes processed); the unterminated last
#            line; stdin; exotic path names incl. `./k=v` and `a::b=v`
#   B  A5    setVar VERBATIM: the §1.1 byte matrix through `run` AND a sink,
#            `od -c` on both versions; typeof; in-place replacement;
#            clearVars; illegal names; setVar wins over `addArg -v`
#   C  A7    a missing file in the middle (FATAL: the later file never read)
#            per sink; syntax error; `exit 7` silent; `exit 1` loud; a
#            directory (rc 0, the exact warning); `exit 300`; a missing `-f`
#   D  A8    the sandbox: system(), `print > f`, `> "/dev/stderr"`, a pipe to
#            getline, `getline < f`, `|&` refused (marker files); `sandbox = 0`
#            runs them; '', yes, 2 stay sandboxed; `@include` allowed
#   E  A9    CR: text mode strips, `binary` keeps, `binary` + `crlf` strips
#            one, `inPlace` keeps every CR on disk, `nullData` keeps an
#            embedded CR
#   F  A10   NUL records through the derived `-0`; the last record terminated
#   G  A11   in-place: sandbox refused; `run` edits; END to stdout; a planted
#            `./inplace.awk` is NOT loaded; `.bak`; a missing middle file;
#            `exit` truncates; every sink rc 2 with nothing run
#   H  A12   `TAwk.apply PROGRAM PATH...` in three positions, `apply ''` rc 2,
#            no path rc 2, an assignment path rc 2, nested, sandbox forced,
#            both TPipe forms

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tawk.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/ta.err"

kt_test_section "005: TAwk against GNU Awk on a real tree (P0)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`gawk\` on PATH is GNU Awk (D4 pins the DIALECT, not a binary)"
AWK_BIN="$(command -v gawk 2>/dev/null || printf '(none)')"
AWK_VER="$(timeout 20 gawk --version 2>/dev/null </dev/null | head -1 || :)"
if [[ "$AWK_VER" == "GNU Awk "* ]]; then
    GNU_OK=1
    kt_test_pass "$AWK_BIN — $AWK_VER"
else
    kt_test_pass "SKIP: non-GNU awk ($AWK_BIN — '${AWK_VER:-no banner}'); every behavioural case below is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU awk"
        return 1
    fi
    return 0
}

printf -v CR '\r'
BS='\'
IPA=/usr/share/awk/inplace.awk

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/dir" "$FX/markers" "$FX/plant"
printf 'a 1\nb 2\nc 3\n'       > "$FX/f3.txt"
printf 'd 4\ne 5\n'            > "$FX/f3b.txt"
printf 'a 1\r\nb 2\r\n'        > "$FX/crlf.txt"
printf 'c 3\r\r\n'             > "$FX/cr2.txt"
printf 'a\0x\r\ny\0last'       > "$FX/nul.bin"
printf 'u1\nu2'                > "$FX/unterm.txt"
printf 'x:y:z\n'               > "$FX/colon.txt"
printf 'p\tq r\ts\n'           > "$FX/tab.txt"
printf 'BEGIN{print "f"}\n'    > "$FX/prog.awk"
printf 'BEGIN{print "inc"}\n'  > "$FX/inc.awk"
printf 'sp 1\n'                > "$FX/with space.txt"
printf 'dash 1\n'              > "$FX/-dash.txt"
printf 'kv 1\n'                > "$FX/k=v"
printf 'ns 1\n'                > "$FX/a::b=v"
MK="$FX/markers"

kt_test_start "the fixture tree is in place (3-line, CRLF, NUL, unterminated, program, exotic names incl. k=v and a::b=v, a directory)"
need_ok=1
for f in f3.txt f3b.txt crlf.txt cr2.txt nul.bin unterm.txt colon.txt tab.txt prog.awk inc.awk \
         'with space.txt' -dash.txt k=v a::b=v; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
[[ -d "$FX/dir" ]] || need_ok=0
if [[ "$need_ok" == "1" && "$(od -c < "$FX/crlf.txt" | head -1)" == *'\r'* ]]; then
    kt_test_pass "tree under $FX"
else
    kt_test_fail "a fixture entry is missing under $FX: $(ls -A "$FX" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# helpers — every local uses a `__z` prefix so none can shadow the unit's
# `__taw_*` scratch namerefs.
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

# oracleL ARRNAME CMD... — newline-framed stdout of the bare tool (stdin closed).
oracleL() {
    local -n __zo="$1"; shift
    __zo=()
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        __zo+=( "$__zl" )
    done < <( timeout 20 "$@" 2>/dev/null </dev/null )
    return 0
}

# oracle0 ARRNAME CMD... — NUL-framed stdout.
oracle0() {
    local -n __zo="$1"; shift
    __zo=()
    mapfile -d '' -t __zo < <( timeout 20 "$@" 2>/dev/null </dev/null )
    return 0
}

odf() { od -c < "$1"; }

# ta_dbg COMMAND... — the switch ON, stderr SPLIT: TA_N/TA_1 are OUR lines
# (`Error:`/`Warning:`), TOOL_N/TOOL_1 gawk's own (the `gawk: ` PREFIX).
TA_RC=0; TA_N=0; TA_1=''; TOOL_N=0; TOOL_1=''
ta_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TA_RC=$?
    VERBOSE_KKLASS=
    TA_N=0; TOOL_N=0; TA_1=''; TOOL_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TA_N=$(( TA_N + 1 ))
                if [[ -z "$TA_1" ]]; then TA_1="$__zl"; fi
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

class TATestList
    public
        var         N
        constructor Create
        proc        Add
end
TATestList.Create() { N=0; return 0; }
TATestList.Add()    { N=$(( N + 1 )); return 0; }
build TATestList

# ===========================================================================
kt_test_section "A. A6 — every sink against the bare tool"
# ===========================================================================

if tcase "A6: toArray / each / count / first / toList / run on \`{print \$2}\` all agree with bare gawk"; then
    TAwk.new aK '{print $2}' "$FX/f3.txt"
    oracleL SWANT gawk --sandbox -e '{print $2}' -- "$FX/f3.txt"
    SGOT=()
    arc=0; aK.toArray SGOT || arc=$?; an="$RESULT"
    CB_RECS=()
    erc=0; aK.each cb_collect || erc=$?
    crc=0; aK.count || crc=$?; cn="$RESULT"
    frc=0; aK.first || frc=$?; fv="$RESULT"
    TATestList.new aKL
    lrc=0; aK.toList aKL || lrc=$?; ln="$RESULT"
    rrc=0; aK.run > "$TMP/run.out" 2>/dev/null || rrc=$?
    timeout 20 gawk --sandbox -e '{print $2}' -- "$FX/f3.txt" > "$TMP/bare.out"
    aK.lastRc; lr="$RESULT"
    if [[ $arc -eq 0 && $erc -eq 0 && $crc -eq 0 && $frc -eq 0 && $lrc -eq 0 && $rrc -eq 0 \
          && "$an" == "3" && "$cn" == "3" && "$ln" == "3" && "$(aKL.N)" == "3" && "$fv" == "1" \
          && "$lr" == "0" ]] \
       && arr_is SWANT 1 2 3 && arr_eq SGOT SWANT && arr_eq CB_RECS SWANT \
       && cmp -s "$TMP/run.out" "$TMP/bare.out"; then
        kt_test_pass "(1 2 3) from all six, rc 0, lastRc 0; run byte-identical to bare gawk"
    else
        kt_test_fail "toArray rc=$arc n=$an got=$(arr_show SGOT); each rc=$erc $(arr_show CB_RECS); count rc=$crc n=$cn; first rc=$frc '$fv'; toList rc=$lrc n=$ln; run rc=$rrc; lastRc=$lr want=$(arr_show SWANT)"
    fi
    aKL.delete
    aK.delete
fi

# same_as_bare TITLE INST WANT_RECS_VAR BAREARGV... — `INST.toArray` equals the
# bare tool's stdout AND the pinned records, rc 0.
same_as_bare() {
    local __zt="$1" __zi="$2" __zw="$3"; shift 3
    if ! tcase "$__zt"; then
        return 0
    fi
    SGOT=()
    local __zrc=0
    "$__zi".toArray SGOT 2>/dev/null || __zrc=$?
    oracleL SWANT "$@"
    local -n __zwant="$__zw"
    if [[ $__zrc -eq 0 ]] && arr_eq SGOT SWANT && arr_eq SGOT __zwant; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool: $(arr_show SGOT)"
    else
        kt_test_fail "rc=$__zrc got=$(arr_show SGOT) bare=$(arr_show SWANT) want=$(arr_show __zwant)"
    fi
}

TAwk.new aM 'BEGIN{printf "1"}' "$FX/f3.txt"
aM.addProgram 'BEGIN{printf "2"}' '' 'BEGIN{print "3"}'
W_123=( 123 )
same_as_bare "A6: \`program\` + \`addProgram\` chunks run IN ORDER (the empty chunk skipped)" aM W_123 \
    gawk --sandbox -e 'BEGIN{printf "1"}' -e 'BEGIN{printf "2"}' -e 'BEGIN{print "3"}' -- "$FX/f3.txt"
aM.delete

TAwk.new aM 'BEGIN{printf "e"}' "$FX/f3.txt"
aM.programFile = "$FX/prog.awk"
W_EF=( ef )
same_as_bare "A6: \`programFile\` after the \`-e\` chunks — \`-e\` text first, then the file" aM W_EF \
    gawk --sandbox -e 'BEGIN{printf "e"}' -f "$FX/prog.awk" -- "$FX/f3.txt"
aM.delete

TAwk.new aM '' "$FX/f3.txt"
aM.programFile = "$FX/prog.awk"
W_F=( f )
same_as_bare "A6: \`programFile\` ALONE" aM W_F gawk --sandbox -f "$FX/prog.awk" -- "$FX/f3.txt"
aM.delete

TAwk.new aM '{print $2}' "$FX/colon.txt"
aM.fieldSep = :
W_Y=( y )
same_as_bare "A6: \`fieldSep = :\` -> \`-F :\`" aM W_Y gawk --sandbox -F : -e '{print $2}' -- "$FX/colon.txt"
aM.delete

TAwk.new aM '{print $2}' "$FX/tab.txt"
aM.fieldSep = "${BS}t"
W_TAB=( 'q r' )
same_as_bare "A6: \`fieldSep = '\\t'\` is escape-processed by gawk (a TAB), awk semantics" aM W_TAB \
    gawk --sandbox -F "${BS}t" -e '{print $2}' -- "$FX/tab.txt"
aM.delete

TAwk.new aM '{print $1}' "$FX/tab.txt"
if tcase "A6: \`fieldSep\` is a REGEX (\`[rq]\`)"; then
    aM.fieldSep = '[rq]'
    SGOT=()
    rc=0; aM.toArray SGOT 2>/dev/null || rc=$?
    oracleL SWANT gawk --sandbox -F '[rq]' -e '{print $1}' -- "$FX/tab.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT "$(printf 'p\t')" && arr_eq SGOT SWANT; then
        kt_test_pass "(p\\t) — the field ended at the first q or r"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) bare=$(arr_show SWANT)"
    fi
fi
aM.delete

if tcase "A6: an unterminated last line comes out TERMINATED (\`print\` appends ORS) — == bare"; then
    TAwk.new aM '{print}' "$FX/unterm.txt"
    got="$(aM.run | od -c)"
    want="$(timeout 20 gawk --sandbox -e '{print}' -- "$FX/unterm.txt" | od -c)"
    exp="$(printf 'u1\nu2\n' | od -c)"
    SGOT=()
    rc=0; aM.toArray SGOT || rc=$?
    if [[ "$got" == "$want" && "$got" == "$exp" && $rc -eq 0 ]] && arr_is SGOT u1 u2; then
        kt_test_pass "u1\\nu2\\n — a newline added, like the bare tool; records (u1 u2)"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}' rc=$rc recs=$(arr_show SGOT)"
    fi
    aM.delete
fi

if tcase "A6: no path — \`run\` reads stdin; the path \`-\` is stdin explicitly"; then
    TAwk.new aM '{print $2}'
    aM.run < "$FX/f3.txt" > "$TMP/stdin1.out" 2>/dev/null
    TAwk.new aM2 '{print $2}' '-'
    aM2.run < "$FX/f3.txt" > "$TMP/stdin2.out" 2>/dev/null
    timeout 20 gawk --sandbox -e '{print $2}' < "$FX/f3.txt" > "$TMP/stdin.bare"
    if cmp -s "$TMP/stdin1.out" "$TMP/stdin.bare" && cmp -s "$TMP/stdin2.out" "$TMP/stdin.bare" \
       && [[ "$(<"$TMP/stdin.bare")" == $'1\n2\n3' ]]; then
        kt_test_pass "both identical to bare gawk on stdin"
    else
        kt_test_fail "stdin1=$(tr '\n' '|' < "$TMP/stdin1.out") stdin2=$(tr '\n' '|' < "$TMP/stdin2.out")"
    fi
    aM.delete
    aM2.delete
fi

if tcase "A6: a name with a space, a name starting with \`-\`, \`./k=v\` and \`./a::b=v\` are read as FILES"; then
    TAwk.new aM '{print $1}'
    cd "$FX" || :
    aM.paths "with space.txt" "-dash.txt" ./k=v ./a::b=v
    SGOT=()
    rc=0; aM.toArray SGOT || rc=$?
    cd "$SCRIPT_DIR" || :
    if [[ $rc -eq 0 && "$PWD" == "$SCRIPT_DIR" ]] && arr_is SGOT sp dash kv ns; then
        kt_test_pass "(sp dash kv ns) — \`-dash.txt\` a file, \`./k=v\` and \`./a::b=v\` files, not assignments"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) pwd=$PWD"
    fi
    aM.delete
fi

if tcase "A6: ABSOLUTE \`…/k=v\` and \`…/a::b=v\` are files too (no \`./\` needed)"; then
    TAwk.new aM '{print $1}' "$FX/k=v" "$FX/a::b=v"
    SGOT=()
    rc=0; aM.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT kv ns; then
        kt_test_pass "(kv ns)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT)"
    fi
    aM.delete
fi

if tcase "A6: a RELATIVE \`k=v\` is rc 2 and nothing runs (gawk would ASSIGN it and read stdin)"; then
    cd "$FX" || :
    TAwk.new aM '{print FILENAME}' k=v
    ta_dbg aM.count
    n="$RESULT"
    aM.lastRc; lr="$RESULT"
    cd "$SCRIPT_DIR" || :
    if [[ "$TA_RC" == "2" && "$n" == "" && "$lr" == "-1" && "$TA_N" == "1" && "$TA_1" == *"./k=v"* ]]; then
        kt_test_pass "rc 2, lastRc -1: ${TA_1:0:90}"
    else
        kt_test_fail "rc=$TA_RC RESULT='$n' lastRc='$lr' lines=$TA_N first='$TA_1'"
    fi
    aM.delete
fi

# ===========================================================================
kt_test_section "B. A5 — setVar is VERBATIM (owner Q2): -v NAME=enc(VALUE)"
# ===========================================================================

printf -v FF '\377'
# the §1.1 matrix, built without a literal escape anywhere near an editor
SV_VALS=(
    "a${BS}tb"
    "x${BS}${BS}y"
    "end${BS}"
    "b${BS}"$'\n'"c"
    "\$'\""
    "é中"
    "@/foo/"
    "@"
    "a${CR}b"
    "${FF}z"
    "${BS}u0041"
    "/c/foo"
    " 010 "
    $'\n'
    ""
    "&amp&"
    $'two\nlines'
)
SV_NAMES=( 'backslash-t' 'double backslash' 'trailing backslash' 'backslash+newline' "\$'\"" 'UTF-8' '@/foo/' 'lone @' 'CR' 'byte 0xFF' 'backslash-u0041' '/c/foo' "' 010 '" 'newline' 'empty' '&amp&' 'two lines' )

sv_case() {   # sv_case INDEX
    local __zk="$1"
    local __zv="${SV_VALS[$__zk]}"
    if ! tcase "A5: setVar round-trips byte-exact — ${SV_NAMES[$__zk]} (run AND toArray, od -c)"; then
        return 0
    fi
    TAwk.new aV 'BEGIN{printf "%s", x}'
    aV.setVar x "$__zv"
    local __zrc=0
    aV.run > "$TMP/sv.out" 2>"$ERRF" || __zrc=$?
    local __zgot __zwant __zerr
    __zgot="$(odf "$TMP/sv.out")"
    __zwant="$(printf '%s' "$__zv" | od -c)"
    __zerr="$(<"$ERRF")"
    # the sink: NUL records, so a value holding a newline is ONE record
    TAwk.new aV2 'BEGIN{print x}'
    aV2.setVar x "$__zv"
    aV2.nullData = 1
    SGOT=()
    local __zrc2=0
    aV2.toArray SGOT 2>/dev/null || __zrc2=$?
    if [[ $__zrc -eq 0 && $__zrc2 -eq 0 && "$__zgot" == "$__zwant" && -z "$__zerr" ]] && arr_is SGOT "$__zv"; then
        kt_test_pass "run and toArray both give exactly $(printf '%q' "$__zv")"
    else
        kt_test_fail "run rc=$__zrc od='${__zgot//$'\n'/|}' want='${__zwant//$'\n'/|}' stderr='$__zerr'; toArray rc=$__zrc2 got=$(arr_show SGOT)"
    fi
    aV.delete
    aV2.delete
}

for (( k = 0; k < ${#SV_VALS[@]}; k++ )); do
    sv_case "$k"
done

if tcase "A5: WHY — bare \`-v x='\\u0041'\` is NOT verbatim (5.4 decodes it, 5.0 warns and drops the backslash)"; then
    bare="$(timeout 20 gawk -v "x=${BS}u0041" -e 'BEGIN{printf "%s", x}' 2>/dev/null </dev/null)"
    TAwk.new aV 'BEGIN{printf "%s", x}'
    aV.setVar x "${BS}u0041"
    mine="$(aV.run 2>/dev/null)"
    if [[ "$bare" != "${BS}u0041" && "$mine" == "${BS}u0041" ]]; then
        kt_test_pass "bare -v: '$bare'; setVar: '$mine'"
    else
        kt_test_fail "bare='$bare' mine='$mine'"
    fi
    aV.delete
fi

if tcase "A5: \`typeof\` is preserved — \`' 010 '\` is a strnum through setVar, as through bare -v"; then
    TAwk.new aV 'BEGIN{print typeof(x)}'
    aV.setVar x ' 010 '
    mine="$(aV.run 2>/dev/null)"
    bare="$(timeout 20 gawk -v 'x= 010 ' -e 'BEGIN{print typeof(x)}' 2>/dev/null </dev/null)"
    if [[ "$mine" == "strnum" && "$bare" == "strnum" ]]; then
        kt_test_pass "strnum / strnum"
    else
        kt_test_fail "mine='$mine' bare='$bare'"
    fi
    aV.delete
fi

if tcase "A5: a repeated NAME replaces its value in place; \`clearVars\` removes them all"; then
    TAwk.new aV 'BEGIN{print "[" x "][" y "]"}'
    aV.setVar x 1
    aV.setVar y 2
    aV.setVar x 3
    one="$(aV.run 2>/dev/null)"
    aV.clearVars
    two="$(aV.run 2>/dev/null)"
    if [[ "$one" == "[3][2]" && "$two" == "[][]" ]]; then
        kt_test_pass "'$one' then '$two'"
    else
        kt_test_fail "one='$one' two='$two'"
    fi
    aV.delete
fi

if tcase "A5: setVar WINS over an \`addArg -v\` of the same name (emitted after the extras)"; then
    TAwk.new aV 'BEGIN{print x}'
    aV.addArg -v x=extra
    aV.setVar x mine
    out="$(aV.run 2>/dev/null)"
    if [[ "$out" == "mine" ]]; then
        kt_test_pass "'mine'"
    else
        kt_test_fail "out='$out'"
    fi
    aV.delete
fi

if tcase "A5: \`addArg -v\` keeps awk-escape semantics (the Q2 escape hatch) — \`x=a\\tb\` is a TAB"; then
    TAwk.new aV 'BEGIN{printf "%s", x}'
    aV.addArg -v "x=a${BS}tb"
    got="$(aV.run 2>/dev/null | od -c)"
    want="$(printf 'a\tb' | od -c)"
    if [[ "$got" == "$want" ]]; then
        kt_test_pass "a\\tb processed to a TAB"
    else
        kt_test_fail "got='${got//$'\n'/|}'"
    fi
    aV.delete
fi

# illegal NAMEs: setVar is rc 2 and stores nothing; the bare tool shows why
sv_bad() {   # sv_bad NAME
    local __zn="$1"
    if ! tcase "A5: \`setVar $__zn\` is rc 2, nothing stored, the run unaffected; bare \`-v $__zn=1\` is gawk's fatal rc 2"; then
        return 0
    fi
    TAwk.new aV 'BEGIN{print "ran"}'
    ta_dbg aV.setVar "$__zn" 1
    local __zrc="$TA_RC" __zl="$TA_1" __zc="$TA_N"
    local __zout; __zout="$(aV.run 2>/dev/null)"
    local __zb=0
    timeout 20 gawk -v "$__zn=1" -e 'BEGIN{print "ran"}' >/dev/null 2>&1 </dev/null || __zb=$?
    if [[ "$__zrc" == "2" && "$__zc" == "1" && "$__zl" == "Error: TAwk.setVar: "* && "$__zout" == "ran" && "$__zb" == "2" ]] \
       && arr_is aV_vnames; then
        kt_test_pass "rc 2; bare rc $__zb: ${__zl:0:70}"
    else
        kt_test_fail "rc=$__zrc lines=$__zc first='$__zl' out='$__zout' bare=$__zb vnames=$(arr_show aV_vnames)"
    fi
    aV.delete
}
sv_bad 1x
sv_bad BEGIN
sv_bad length
sv_bad ENVIRON
sv_bad switch

# ===========================================================================
kt_test_section "C. A7 — the FATAL missing file, syntax errors, and the program's exit N"
# ===========================================================================

TAwk.new aP '{print}' "$FX/f3.txt" "$FX/no_such.txt" "$FX/f3b.txt"

if tcase "A7: a missing file in the MIDDLE — \`toArray\` rc 1, only the EARLIER file's records, lastRc 2"; then
    SGOT=()
    rc=0; aP.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    aP.lastRc; lr="$RESULT"
    oracleL SWANT gawk --sandbox -e '{print}' -- "$FX/f3.txt" "$FX/no_such.txt" "$FX/f3b.txt"
    if [[ $rc -eq 1 && "$n" == "3" && "$lr" == "2" ]] && arr_is SGOT 'a 1' 'b 2' 'c 3' && arr_eq SGOT SWANT; then
        kt_test_pass "rc 1, RESULT 3, lastRc 2 — f3b.txt NEVER read (FATAL), identical to the bare tool"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
fi

if tcase "A7: missing middle file — \`count\` rc 1 RESULT 3; \`toList\` rc 1 RESULT 3"; then
    rc=0; aP.count 2>/dev/null || rc=$?; cn="$RESULT"
    TATestList.new aPL
    lrc=0; aP.toList aPL 2>/dev/null || lrc=$?; ln="$RESULT"
    if [[ $rc -eq 1 && "$cn" == "3" && $lrc -eq 1 && "$ln" == "3" && "$(aPL.N)" == "3" ]]; then
        kt_test_pass "count rc 1 / 3; toList rc 1 / 3 offered, 3 stored"
    else
        kt_test_fail "count rc=$rc n=$cn; toList rc=$lrc n=$ln stored=$(aPL.N)"
    fi
    aPL.delete
fi

if tcase "A7: missing middle file — \`each\` rc 1, three callbacks, RESULT UNTOUCHED (a proc)"; then
    CB_RECS=()
    RESULT="each-sentinel"
    rc=0; aP.each cb_collect 2>/dev/null || rc=$?
    r="$RESULT"
    if [[ $rc -eq 1 && "$r" == "each-sentinel" ]] && arr_is CB_RECS 'a 1' 'b 2' 'c 3'; then
        kt_test_pass "rc 1, three records delivered, RESULT still the caller's"
    else
        kt_test_fail "rc=$rc RESULT='$r' recs=$(arr_show CB_RECS)"
    fi
fi

if tcase "A7: missing middle file — \`first\` rc 0, the first record, lastRc 2, NO line of ours"; then
    ta_dbg aP.first
    fv="$RESULT"
    aP.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "0" && "$TA_N" == "0" && "$fv" == "a 1" && "$lr" == "2" ]]; then
        kt_test_pass "rc 0, RESULT 'a 1', lastRc 2 (TUtil's consumer-stop contract)"
    else
        kt_test_fail "rc=$TA_RC ourLines=$TA_N first='$TA_1' RESULT='$fv' lastRc='$lr'"
    fi
fi

if tcase "A7: the partial path says ONE line of ours, worded per Q3; gawk's own line passes through"; then
    ta_dbg aP.count
    if [[ "$TA_RC" == "1" && "$TA_N" == "1" && "$TOOL_N" == "1" && "$TOOL_1" == "gawk: "* \
          && "$TA_1" == "Error: TAwk.mapRc: gawk exited 2 (a gawk error, or the program's exit 2)" ]]; then
        kt_test_pass "ours: $TA_1 | gawk's: '${TOOL_1:0:50}'"
    else
        kt_test_fail "rc=$TA_RC ourLines=$TA_N first='$TA_1' toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
fi
aP.delete

if tcase "A7: the missing file FIRST — \`first\` rc 1, no record, lastRc 2"; then
    TAwk.new aP '{print}' "$FX/no_such.txt" "$FX/f3.txt"
    rc=0; aP.first 2>/dev/null || rc=$?
    fv="$RESULT"
    aP.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$fv" == "" && "$lr" == "2" ]]; then
        kt_test_pass "rc 1, RESULT '', lastRc 2"
    else
        kt_test_fail "rc=$rc RESULT='$fv' lastRc='$lr'"
    fi
    aP.delete
fi

if tcase "A7: a SYNTAX error — rc 1, lastRc 1, zero records, one line of ours + gawk's"; then
    TAwk.new aD 'BEGIN{' "$FX/f3.txt"
    SGOT=( stale )
    ta_dbg aD.toArray SGOT
    aD.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "1" && "$lr" == "1" && ${#SGOT[@]} -eq 0 && "$TA_N" == "1" \
          && "$TA_1" == *"gawk exited 1 (a gawk error, or the program's exit 1)"* && "$TOOL_1" == "gawk: "* ]]; then
        kt_test_pass "rc 1, lastRc 1: ${TA_1:0:70}"
    else
        kt_test_fail "rc=$TA_RC lastRc='$lr' got=$(arr_show SGOT) ourLines=$TA_N first='$TA_1' tool='$TOOL_1'"
    fi
    aD.delete
fi

if tcase "A7: a chunk must be COMPLETE — \`-e 'BEGIN{'\` + \`-e 'print 1}'\` is gawk's rc 1"; then
    TAwk.new aD 'BEGIN{'
    aD.addProgram 'print 1}'
    ta_dbg aD.run
    aD.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "1" && "$lr" == "1" && "$TOOL_1" == "gawk: "* ]]; then
        kt_test_pass "rc 1, lastRc 1 — each -e is its own source"
    else
        kt_test_fail "rc=$TA_RC lastRc='$lr' tool='$TOOL_1'"
    fi
    aD.delete
fi

if tcase "A7: a MISSING \`-f\` file — rc 1, lastRc 2, zero records, one line of ours"; then
    TAwk.new aD '' "$FX/f3.txt"
    aD.programFile = "$FX/no_such.awk"
    SGOT=( stale )
    ta_dbg aD.toArray SGOT
    aD.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "1" && "$lr" == "2" && ${#SGOT[@]} -eq 0 && "$TA_N" == "1" \
          && "$TA_1" == *"gawk exited 2"* && "$TOOL_1" == "gawk: "* ]]; then
        kt_test_pass "rc 1, lastRc 2, nothing read: ${TA_1:0:60}"
    else
        kt_test_fail "rc=$TA_RC lastRc='$lr' got=$(arr_show SGOT) ourLines=$TA_N first='$TA_1' tool='$TOOL_1'"
    fi
    aD.delete
fi

if tcase "A7: \`exit 7\` — rc 1 SILENT, lastRc 7, the records before it delivered"; then
    TAwk.new aQ 'NR==3{exit 7} {print}' "$FX/f3.txt"
    SGOT=()
    ta_dbg aQ.toArray SGOT
    n="$RESULT"
    aQ.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "1" && "$TA_N" == "0" && "$TOOL_N" == "0" && "$lr" == "7" && "$n" == "2" ]] \
       && arr_is SGOT 'a 1' 'b 2'; then
        kt_test_pass "rc 1, lastRc 7, ('a 1' 'b 2'), not one line on stderr"
    else
        kt_test_fail "rc=$TA_RC ourLines=$TA_N first='$TA_1' toolLines=$TOOL_N lastRc='$lr' RESULT='$n' got=$(arr_show SGOT)"
    fi
    aQ.delete
fi

if tcase "A7: \`exit 1\` — rc 1 WITH the debug line (indistinguishable from gawk's own 1, worded to say so)"; then
    TAwk.new aQ 'NR==2{exit 1} {print}' "$FX/f3.txt"
    SGOT=()
    ta_dbg aQ.toArray SGOT
    aQ.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "1" && "$TA_N" == "1" && "$TOOL_N" == "0" && "$lr" == "1" \
          && "$TA_1" == *"gawk exited 1 (a gawk error, or the program's exit 1)"* ]] && arr_is SGOT 'a 1'; then
        kt_test_pass "rc 1, lastRc 1, ('a 1'): ${TA_1:0:70}"
    else
        kt_test_fail "rc=$TA_RC ourLines=$TA_N first='$TA_1' lastRc='$lr' got=$(arr_show SGOT)"
    fi
    aQ.delete
fi

if tcase "A7: \`exit 300\` -> lastRc 44 (N mod 256), rc 1 silent; \`exit 256\` -> rc 0"; then
    TAwk.new aQ 'BEGIN{exit 300}'
    ta_dbg aQ.run
    aQ.lastRc; lr="$RESULT"
    r1="$TA_RC/$TA_N/$lr"
    TAwk.new aQ 'BEGIN{exit 256}'
    ta_dbg aQ.run
    aQ.lastRc; lr2="$RESULT"
    if [[ "$r1" == "1/0/44" && "$TA_RC" == "0" && "$lr2" == "0" ]]; then
        kt_test_pass "exit 300: rc 1, silent, lastRc 44; exit 256: rc 0, lastRc 0"
    else
        kt_test_fail "exit 300: rc/lines/lastRc=$r1; exit 256: rc=$TA_RC lastRc=$lr2"
    fi
    aQ.delete
fi

if tcase "A7: a DIRECTORY operand — rc 0, skipped with the EXACT warning (identical on both), later file read"; then
    TAwk.new aD '{print}' "$FX/f3.txt" "$FX/dir" "$FX/f3b.txt"
    SGOT=()
    rc=0; aD.toArray SGOT 2>"$ERRF" || rc=$?
    err="$(<"$ERRF")"
    aD.lastRc; lr="$RESULT"
    want="gawk: cmd. line:1: warning: command line argument \`$FX/dir' is a directory: skipped"
    if [[ $rc -eq 0 && "$lr" == "0" && "$err" == "$want" ]] && arr_is SGOT 'a 1' 'b 2' 'c 3' 'd 4' 'e 5'; then
        kt_test_pass "rc 0, lastRc 0, five records; '${err:0:60}…'"
    else
        kt_test_fail "rc=$rc lastRc='$lr' err='$err' want='$want' got=$(arr_show SGOT)"
    fi
    aD.delete
fi

# ===========================================================================
kt_test_section "D. A8 — the sandbox default (owner Q1)"
# ===========================================================================

# sbox TITLE MARKER PROGRAM — the default instance must be rc 1, lastRc 2, zero
# records, one line of ours, gawk's own fatal line, and the marker must NOT
# exist.
sbox() {
    local __zt="$1" __zm="$2" __zp="$3"
    if ! tcase "$__zt"; then
        return 0
    fi
    rm -f "$__zm"
    TAwk.new aS "$__zp" "$FX/f3.txt"
    SGOT=( stale )
    ta_dbg aS.toArray SGOT
    aS.lastRc
    local __zlr="$RESULT"
    if [[ "$TA_RC" == "1" && "$__zlr" == "2" && ${#SGOT[@]} -eq 0 && "$TA_N" == "1" \
          && "$TOOL_1" == "gawk: "*"sandbox mode"* && ! -e "$__zm" ]]; then
        kt_test_pass "refused: '${TOOL_1:0:70}'; no marker"
    else
        kt_test_fail "rc=$TA_RC lastRc='$__zlr' got=$(arr_show SGOT) ourLines=$TA_N tool='$TOOL_1' marker=$([[ -e $__zm ]] && echo present || echo absent)"
    fi
    aS.delete
}

sbox "A8: \`system()\` is refused by default"              "$MK/m_sys"  "BEGIN{system(\"touch $MK/m_sys\")}"
sbox "A8: \`print > FILE\` is refused by default"          "$MK/m_out"  "{print > \"$MK/m_out\"}"
sbox "A8: \`print >> FILE\` is refused by default"         "$MK/m_app"  "{print >> \"$MK/m_app\"}"
sbox "A8: \`print | CMD\` is refused by default"           "$MK/m_pip"  "{print | \"cat > $MK/m_pip\"}"
sbox "A8: \`\"CMD\" | getline\` is refused by default"      "$MK/m_gl"   "BEGIN{\"touch $MK/m_gl\" | getline x}"
sbox "A8: \`print > \\\"/dev/stderr\\\"\` is refused too" "$MK/m_none1" "{print > \"/dev/stderr\"}"
sbox "A8: \`print > \\\"/dev/stdout\\\"\` is refused too" "$MK/m_none2" "{print > \"/dev/stdout\"}"
sbox "A8: \`getline < FILE\` (INPUT redirection) is refused" "$MK/m_none3" "BEGIN{while ((getline l < \"$FX/f3b.txt\") > 0) print l}"
sbox "A8: the coprocess \`|&\` is refused"                 "$MK/m_co"   "BEGIN{print \"x\" |& \"touch $MK/m_co\"}"

if tcase "A8: \`sandbox = 0\` RUNS system(), \`print > f\`, a getline pipe and \`getline < f\`"; then
    rm -f "$MK"/m_*
    ok=1
    for spec in "BEGIN{system(\"touch $MK/m_sys\")}" "{print > \"$MK/m_out\"}" "BEGIN{\"touch $MK/m_gl\" | getline x}"; do
        TAwk.new aS "$spec" "$FX/f3.txt"
        aS.sandbox = 0
        rc=0; aS.count 2>/dev/null || rc=$?
        [[ $rc -eq 0 ]] || ok=0
        aS.delete
    done
    TAwk.new aS "BEGIN{while ((getline l < \"$FX/f3b.txt\") > 0) print l}"
    aS.sandbox = 0
    SGOT=()
    rc=0; aS.toArray SGOT 2>/dev/null || rc=$?
    [[ $rc -eq 0 ]] || ok=0
    aS.delete
    if [[ "$ok" == "1" && -e "$MK/m_sys" && -e "$MK/m_gl" && "$(<"$MK/m_out")" == $'a 1\nb 2\nc 3' ]] \
       && arr_is SGOT 'd 4' 'e 5'; then
        kt_test_pass "rc 0 each; m_sys, m_gl created, m_out holds the three lines; getline read f3b.txt"
    else
        kt_test_fail "ok=$ok markers: $(ls "$MK" 2>/dev/null | tr '\n' ' ') got=$(arr_show SGOT)"
    fi
fi

for sv in '' yes 2 ' 0' 00; do
    if tcase "A8 (fail closed): \`sandbox = $(printf '%q' "$sv")\` stays SANDBOXED — system() refused, no marker"; then
        rm -f "$MK/m_fc"
        TAwk.new aS "BEGIN{system(\"touch $MK/m_fc\")}"
        aS.sandbox = "$sv"
        rc=0; aS.run 2>/dev/null || rc=$?
        aS.lastRc; lr="$RESULT"
        if [[ $rc -eq 1 && "$lr" == "2" && ! -e "$MK/m_fc" ]]; then
            kt_test_pass "rc 1, lastRc 2, no marker"
        else
            kt_test_fail "rc=$rc lastRc='$lr' marker=$([[ -e $MK/m_fc ]] && echo present || echo absent)"
        fi
        aS.delete
    fi
done

if tcase "A8: \`@include \\\"FILE\\\"\` is ALLOWED under the sandbox (and the included system() is still refused)"; then
    printf 'BEGIN{system("touch %s")}\n' "$MK/m_inc" > "$FX/inc2.awk"
    rm -f "$MK/m_inc"
    TAwk.new aS "@include \"$FX/inc.awk\""
    SGOT=()
    rc=0; aS.toArray SGOT 2>/dev/null || rc=$?
    TAwk.new aS2 "@include \"$FX/inc2.awk\""
    rc2=0; aS2.run 2>/dev/null || rc2=$?
    if [[ $rc -eq 0 && $rc2 -eq 1 && ! -e "$MK/m_inc" ]] && arr_is SGOT inc; then
        kt_test_pass "(inc), rc 0; the included system(): rc 1, no marker"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) rc2=$rc2 marker=$([[ -e $MK/m_inc ]] && echo present || echo absent)"
    fi
    aS.delete
    aS2.delete
fi

# ===========================================================================
kt_test_section "E. A9 — the CR"
# ===========================================================================

if tcase "A9: text mode STRIPS the CR — records ('a 1' 'b 2'), bytes == bare gawk, no \\r in the stream"; then
    TAwk.new aC '{print}' "$FX/crlf.txt"
    SGOT=()
    rc=0; aC.toArray SGOT || rc=$?
    got="$(aC.run | od -c)"
    want="$(timeout 20 gawk --sandbox -e '{print}' -- "$FX/crlf.txt" | od -c)"
    if [[ $rc -eq 0 && "$got" == "$want" && "$got" != *'\r'* ]] && arr_is SGOT 'a 1' 'b 2'; then
        kt_test_pass "('a 1' 'b 2'); gawk ate the CR itself (crlf is a no-op here)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) od='${got//$'\n'/|}'"
    fi
    aC.delete
fi

if tcase "A9: \`binary = 1\` KEEPS the CR — records ('a 1\\r' 'b 2\\r'), the stream == the file"; then
    TAwk.new aC '{print}' "$FX/crlf.txt"
    aC.binary = 1
    SGOT=()
    rc=0; aC.toArray SGOT || rc=$?
    got="$(aC.run | od -c)"
    want="$(odf "$FX/crlf.txt")"
    if [[ $rc -eq 0 && "$got" == "$want" ]] && arr_is SGOT "a 1$CR" "b 2$CR"; then
        kt_test_pass "the file's bytes, untouched"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) od='${got//$'\n'/|}'"
    fi
    aC.delete
fi

if tcase "A9: \`binary = 1\` + \`crlf = 1\` strips EXACTLY one CR (\`c 3\\r\\r\` -> \`c 3\\r\`)"; then
    TAwk.new aC '{print}' "$FX/cr2.txt" "$FX/crlf.txt"
    aC.binary = 1
    aC.crlf = 1
    SGOT=()
    rc=0; aC.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "c 3$CR" 'a 1' 'b 2'; then
        kt_test_pass "('c 3\\r' 'a 1' 'b 2')"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT)"
    fi
    aC.delete
fi

if tcase "A9: \`inPlace = 1\` on a CRLF file keeps EVERY CR on disk (derived BINMODE=3); bare \`-i inplace\` does not"; then
    cp "$FX/crlf.txt" "$FX/ip_crlf.txt"
    cp "$FX/crlf.txt" "$FX/ip_bare.txt"
    TAwk.new aC '{sub(/a/, "A"); print}' "$FX/ip_crlf.txt"
    aC.sandbox = 0
    aC.inPlace = 1
    rc=0; aC.run > "$TMP/ip.out" 2>/dev/null || rc=$?
    timeout 20 gawk -i "$IPA" -e '{sub(/a/, "A"); print}' -- "$FX/ip_bare.txt" </dev/null
    got="$(odf "$FX/ip_crlf.txt")"
    wantc="$(printf 'A 1\r\nb 2\r\n' | od -c)"
    bare="$(odf "$FX/ip_bare.txt")"
    bwant="$(printf 'A 1\nb 2\n' | od -c)"
    if [[ $rc -eq 0 && "$got" == "$wantc" && "$bare" == "$bwant" && ! -s "$TMP/ip.out" ]]; then
        kt_test_pass "wrapper: A 1\\r\\nb 2\\r\\n on disk; bare: A 1\\nb 2\\n (why Q4 derives BINMODE)"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' bare='${bare//$'\n'/|}'"
    fi
    aC.delete
fi

if tcase "A9: \`nullData = 1\` keeps a CR embedded in a NUL record (bare RS/ORS NUL without BINMODE strips it)"; then
    TAwk.new aC '{print}' "$FX/nul.bin"
    aC.nullData = 1
    SGOT=()
    rc=0; aC.toArray SGOT || rc=$?
    oracle0 SWANT gawk -v 'RS=\0' -v 'ORS=\0' -e '{print}' -- "$FX/nul.bin"
    if [[ $rc -eq 0 ]] && arr_is SGOT a "x$CR"$'\n'"y" last && arr_is SWANT a $'x\ny' last; then
        kt_test_pass "(a 'x\\r\\ny' last); the bare text-mode run gives 'x\\ny'"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) bare=$(arr_show SWANT)"
    fi
    aC.delete
fi

# ===========================================================================
kt_test_section "F. A10 — NUL records"
# ===========================================================================

if tcase "A10: \`nullData = 1\` — NUL records through the derived \`-0\`, the sinks agree with the bare tool"; then
    TAwk.new aZ '{print ">" $0}' "$FX/nul.bin"
    aZ.nullData = 1
    SGOT=()
    rc=0; aZ.toArray SGOT || rc=$?
    crc=0; aZ.count || crc=$?; cn="$RESULT"
    frc=0; aZ.first || frc=$?; fv="$RESULT"
    oracle0 SWANT gawk --sandbox -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -e '{print ">" $0}' -- "$FX/nul.bin"
    if [[ $rc -eq 0 && $crc -eq 0 && "$cn" == "3" && $frc -eq 0 && "$fv" == ">a" \
          && "$(aZ.nul)" == "1" ]] && arr_eq SGOT SWANT && arr_is SGOT '>a' ">x$CR"$'\n'"y" '>last'; then
        kt_test_pass "3 records, nul = 1 derived, first '>a'"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) count rc=$crc n=$cn first rc=$frc '$fv' nul=$(aZ.nul)"
    fi
    aZ.delete
fi

if tcase "A10: the unterminated last NUL record comes out TERMINATED (\`run | od -c\` == bare)"; then
    TAwk.new aZ '{print}' "$FX/nul.bin"
    aZ.nullData = 1
    aZ.run > "$TMP/z.out" 2>/dev/null
    timeout 20 gawk --sandbox -v 'RS=\0' -v 'ORS=\0' -v BINMODE=3 -e '{print}' -- "$FX/nul.bin" > "$TMP/z.bare" </dev/null
    last="$(tail -c 5 "$TMP/z.out" | od -c | head -1)"
    if cmp -s "$TMP/z.out" "$TMP/z.bare" && [[ "$last" == *'l   a   s   t  \0'* ]]; then
        kt_test_pass "byte-identical; the stream ends in 'last\\0'"
    else
        kt_test_fail "out=$(od -c < "$TMP/z.out" | tr '\n' '|') bare=$(od -c < "$TMP/z.bare" | tr '\n' '|')"
    fi
    aZ.delete
fi

# ===========================================================================
kt_test_section "G. A11 — in-place (owner Q4)"
# ===========================================================================

F3_OD="$(odf "$FX/f3.txt")"
F3B_OD="$(odf "$FX/f3b.txt")"
UP_OD="$(printf 'A 1\nB 2\nC 3\n' | od -c)"

if tcase "A11: \`inPlace = 1\` with the DEFAULT sandbox is rc 2 — nothing runs, the file byte-identical"; then
    cp "$FX/f3.txt" "$FX/ip0.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ip0.txt"
    aI.inPlace = 1
    ta_dbg aI.run
    aI.lastRc; lr="$RESULT"
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" && "$TA_1" == *"inPlace = 1 needs sandbox = 0"* && "$lr" == "-1" \
          && "$(odf "$FX/ip0.txt")" == "$F3_OD" ]]; then
        kt_test_pass "rc 2, lastRc -1, untouched: ${TA_1:0:70}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1' lastRc='$lr'"
    fi
    aI.delete
fi

if tcase "A11: \`inPlace = 1\` + \`run\` edits the file, stdout EMPTY, rc 0, lastRc 0, no backup"; then
    cp "$FX/f3.txt" "$FX/ip1.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ip1.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    rc=0; aI.run > "$TMP/ip1.out" 2>/dev/null || rc=$?
    aI.lastRc; lr="$RESULT"
    nback="$(ls "$FX" | grep -c '^ip1\.txt.' || :)"
    if [[ $rc -eq 0 && "$lr" == "0" && "$(odf "$FX/ip1.txt")" == "$UP_OD" && ! -s "$TMP/ip1.out" && "$nback" == "0" ]]; then
        kt_test_pass "A 1 / B 2 / C 3 on disk, nothing on stdout"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got='$(odf "$FX/ip1.txt" | tr '\n' '|')' stdout=$(wc -c < "$TMP/ip1.out") backups=$nback"
    fi
    aI.delete
fi

if tcase "A11: the documented trap — END output goes to STDOUT, not into the file"; then
    cp "$FX/f3.txt" "$FX/ip1e.txt"
    TAwk.new aI '{print} END{print "done"}' "$FX/ip1e.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    out="$(aI.run 2>/dev/null)"
    if [[ "$out" == "done" && "$(odf "$FX/ip1e.txt")" == "$F3_OD" ]]; then
        kt_test_pass "stdout 'done'; the file keeps its three lines"
    else
        kt_test_fail "out='$out' file='$(odf "$FX/ip1e.txt" | tr '\n' '|')'"
    fi
    aI.delete
fi

if tcase "A11: a PLANTED \`./inplace.awk\` in the cwd is NOT loaded (the include is absolute); bare \`-i inplace\` loads it"; then
    printf 'BEGIN { printf "" > "PLANTED" }\n' > "$FX/plant/inplace.awk"
    cp "$FX/f3.txt" "$FX/plant/c.txt"
    cp "$FX/f3.txt" "$FX/plant/bare.txt"
    rm -f "$FX/plant/PLANTED"
    cd "$FX/plant" || :
    TAwk.new aI '{print toupper($0)}' c.txt
    aI.sandbox = 0
    aI.inPlace = 1
    rc=0; AWKPATH=".:/usr/share/awk" aI.run >/dev/null 2>&1 || rc=$?
    ours_planted=0; [[ -e PLANTED ]] && ours_planted=1
    rm -f PLANTED
    AWKPATH=".:/usr/share/awk" timeout 20 gawk -i inplace -e '{print}' -- bare.txt >/dev/null 2>&1 </dev/null
    bare_planted=0; [[ -e PLANTED ]] && bare_planted=1
    cd "$SCRIPT_DIR" || :
    if [[ $rc -eq 0 && "$PWD" == "$SCRIPT_DIR" && "$ours_planted" == "0" && "$bare_planted" == "1" \
          && "$(odf "$FX/plant/c.txt")" == "$UP_OD" ]]; then
        kt_test_pass "ours: edited, no PLANTED marker; bare \`-i inplace\` from the same cwd: PLANTED"
    else
        kt_test_fail "rc=$rc pwd=$PWD ours_planted=$ours_planted bare_planted=$bare_planted c.txt='$(odf "$FX/plant/c.txt" | tr '\n' '|')'"
    fi
    aI.delete
fi

if tcase "A11: \`backupSuffix = .bak\` keeps the original as \`FILE.bak\` (\`inplace::suffix\`, both versions)"; then
    cp "$FX/f3.txt" "$FX/ip2.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ip2.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    aI.backupSuffix = .bak
    rc=0; aI.run 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && -f "$FX/ip2.txt.bak" && "$(odf "$FX/ip2.txt.bak")" == "$F3_OD" \
          && "$(odf "$FX/ip2.txt")" == "$UP_OD" ]]; then
        kt_test_pass "ip2.txt edited, ip2.txt.bak holds the original bytes"
    else
        kt_test_fail "rc=$rc files: $(ls "$FX" | tr '\n' ' ')"
    fi
    aI.delete
fi

# backupSuffix is encoded like setVar (reviewer ruling on P0, question 6). The
# suffix `.b\k` must name the backup `FILE.b\k` EXACTLY — on msys a backslash in
# a path is a directory separator, so that is `FILE.b/k`, which needs the
# directory `FILE.b` (measured on 5.0 and 5.4; without it gawk's link() fails,
# fatal rc 2, the file untouched). Unencoded, gawk would process `\k` to `k`
# with a warning and write `FILE.bk` — the bare contrast below.
if tcase "A11: \`backupSuffix\` with a BACKSLASH (\`.b\\k\`) names the backup exactly \`FILE.b\\k\` — no escape processing"; then
    cp "$FX/f3.txt" "$FX/ipbs.txt"
    mkdir -p "$FX/ipbs.txt.b"
    cp "$FX/f3.txt" "$FX/ipraw.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ipbs.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    aI.backupSuffix = ".b${BS}k"
    rc=0; aI.run 2>"$ERRF" || rc=$?
    err="$(<"$ERRF")"
    timeout 20 gawk -v BINMODE=3 -i "$IPA" -v "inplace::suffix=.b${BS}k" -e '{print toupper($0)}' -- "$FX/ipraw.txt" >/dev/null 2>&1 </dev/null
    if [[ $rc -eq 0 && -z "$err" && -f "$FX/ipbs.txt.b${BS}k" && -f "$FX/ipbs.txt.b/k" \
          && "$(odf "$FX/ipbs.txt.b${BS}k")" == "$F3_OD" && "$(odf "$FX/ipbs.txt")" == "$UP_OD" \
          && ! -e "$FX/ipbs.txt.bk" && -f "$FX/ipraw.txt.bk" ]]; then
        kt_test_pass "ipbs.txt.b\\k holds the original, no warning; the unencoded bare -v wrote ipraw.txt.bk"
    else
        kt_test_fail "rc=$rc err='$err' files: $(cd "$FX" && find . -name 'ip*' | sort | tr '\n' ' ')"
    fi
    aI.delete
fi

if tcase "A11: \`backupSuffix = '.b\\k'\` with NO \`FILE.b\` directory — gawk's fatal link(): rc 1, lastRc 2, the file untouched"; then
    cp "$FX/f3.txt" "$FX/ipbn.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ipbn.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    aI.backupSuffix = ".b${BS}k"
    rc=0; aI.run 2>"$ERRF" || rc=$?
    err="$(<"$ERRF")"
    aI.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == "2" && "$err" == "gawk: "*"ipbn.txt.b${BS}k"* && "$(odf "$FX/ipbn.txt")" == "$F3_OD" \
          && ! -e "$FX/ipbn.txt.bk" ]]; then
        kt_test_pass "rc 1, lastRc 2, untouched; gawk names 'ipbn.txt.b\\k'"
    else
        kt_test_fail "rc=$rc lastRc='$lr' err='$err' ipbn='$(odf "$FX/ipbn.txt" | tr '\n' '|')'"
    fi
    aI.delete
fi

if tcase "A11: a MISSING middle file — earlier file edited, the later one byte-identical, rc 1, lastRc 2"; then
    cp "$FX/f3.txt" "$FX/ipa.txt"
    cp "$FX/f3b.txt" "$FX/ipb.txt"
    TAwk.new aI '{print toupper($0)}' "$FX/ipa.txt" "$FX/no_such.txt" "$FX/ipb.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    rc=0; aI.run 2>/dev/null || rc=$?
    aI.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$lr" == "2" && "$(odf "$FX/ipa.txt")" == "$UP_OD" && "$(odf "$FX/ipb.txt")" == "$F3B_OD" ]]; then
        kt_test_pass "ipa.txt edited, ipb.txt untouched (FATAL stops there)"
    else
        kt_test_fail "rc=$rc lastRc='$lr' ipa='$(odf "$FX/ipa.txt" | tr '\n' '|')' ipb='$(odf "$FX/ipb.txt" | tr '\n' '|')'"
    fi
    aI.delete
fi

if tcase "A11: the documented trap — \`exit\` mid-file TRUNCATES that file and leaves later files untouched (rc 0)"; then
    cp "$FX/f3.txt" "$FX/ipx.txt"
    cp "$FX/f3b.txt" "$FX/ipy.txt"
    TAwk.new aI 'FNR==2{exit} {print}' "$FX/ipx.txt" "$FX/ipy.txt"
    aI.sandbox = 0
    aI.inPlace = 1
    rc=0; aI.run 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && "$(odf "$FX/ipx.txt")" == "$(printf 'a 1\n' | od -c)" && "$(odf "$FX/ipy.txt")" == "$F3B_OD" ]]; then
        kt_test_pass "ipx.txt holds 'a 1' only; ipy.txt untouched — README trap"
    else
        kt_test_fail "rc=$rc ipx='$(odf "$FX/ipx.txt" | tr '\n' '|')' ipy='$(odf "$FX/ipy.txt" | tr '\n' '|')'"
    fi
    aI.delete
fi

# refuse_sink TITLE MEMBER [ARG] — inPlace = 1: rc 2, ONE line naming the
# in-place rule, the file byte-identical, `_lastRc` still -1.
taw_never() { : > "$TMP/never.flag"; printf 'ran\n'; }
declare -a REF_ARR=()
TATestList.new aRL
cb_nul() { return 0; }

refuse_sink() {
    local __zt="$1" __zm="$2" __za="${3:-}"
    if ! tcase "$__zt"; then
        return 0
    fi
    cp "$FX/f3.txt" "$FX/ipr.txt"
    TAwk.new aR '{print toupper($0)}' "$FX/ipr.txt"
    aR.sandbox = 0
    aR.inPlace = 1
    RESULT="sentinel"
    ta_dbg aR."$__zm" ${__za:+"$__za"}
    local __zr="$RESULT"
    aR.lastRc
    local __zlr="$RESULT"
    rm -f "$TMP/never.flag"
    aR.cmd = taw_never
    aR."$__zm" ${__za:+"$__za"} >/dev/null 2>&1
    local __zrc2=$?
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" && "$TA_1" == *"TAwk.$__zm"* && "$TA_1" == *"in-place"* \
          && "$TA_1" == *"use run"* && "$__zlr" == "-1" && "$__zrc2" == "2" && ! -e "$TMP/never.flag" \
          && "$(odf "$FX/ipr.txt")" == "$F3_OD" ]] \
       && { [[ "$__zm" == "each" && "$__zr" == "sentinel" ]] || [[ "$__zm" != "each" && "$__zr" == "" ]]; }; then
        kt_test_pass "rc 2, one line, file byte-identical, lastRc -1, nothing ran: ${TA_1:0:60}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1' RESULT='$__zr' lastRc='$__zlr' rc2=$__zrc2 flag=$([[ -e $TMP/never.flag ]] && echo present || echo absent) bytes=$(odf "$FX/ipr.txt" | tr '\n' '|')"
    fi
    aR.delete
}

refuse_sink "A11: \`each\` with \`inPlace = 1\` is rc 2 and NOTHING runs"    each    cb_nul
refuse_sink "A11: \`toArray\` with \`inPlace = 1\` is rc 2 and NOTHING runs" toArray REF_ARR
refuse_sink "A11: \`toList\` with \`inPlace = 1\` is rc 2 and NOTHING runs"  toList  aRL
refuse_sink "A11: \`first\` with \`inPlace = 1\` is rc 2 and NOTHING runs"   first
refuse_sink "A11: \`count\` with \`inPlace = 1\` is rc 2 and NOTHING runs"   count

if tcase "A11: the refusal leaves the caller's array alone"; then
    TAwk.new aR '{print}' "$FX/f3.txt"
    aR.sandbox = 0
    aR.inPlace = 1
    REF_ARR=( keep1 keep2 )
    rc=0; aR.toArray REF_ARR 2>/dev/null || rc=$?
    if [[ $rc -eq 2 && "$RESULT" == "" ]] && arr_is REF_ARR keep1 keep2; then
        kt_test_pass "rc 2, RESULT '', (keep1 keep2)"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' arr=$(arr_show REF_ARR)"
    fi
    aR.delete
fi

if tcase "A11: \`inPlace\` back to 0 — the same instance's sinks work again"; then
    TAwk.new aR '{print}' "$FX/f3.txt"
    aR.sandbox = 0
    aR.inPlace = 1
    aR.count >/dev/null 2>&1
    aR.inPlace = 0
    rc=0; aR.count || rc=$?
    if [[ $rc -eq 0 && "$RESULT" == "3" ]]; then
        kt_test_pass "count rc 0, 3"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
    aR.delete
fi
aRL.delete

# ===========================================================================
kt_test_section "H. A12 — \`TAwk.apply PROGRAM PATH...\`, the static one-liner (§2.7)"
# ===========================================================================

if tcase "A12: \`TAwk.apply '{print \$2}' f\` == \`gawk --sandbox -e '{print \$2}' -- f\`, DIRECT (bytes)"; then
    rc=0; TAwk.apply '{print $2}' "$FX/f3.txt" > "$TMP/e1.out" 2>/dev/null || rc=$?
    timeout 20 gawk --sandbox -e '{print $2}' -- "$FX/f3.txt" > "$TMP/e1.bare" </dev/null
    if [[ $rc -eq 0 && -s "$TMP/e1.bare" ]] && cmp -s "$TMP/e1.out" "$TMP/e1.bare"; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc out=$(tr '\n' '|' < "$TMP/e1.out")"
    fi
fi

if tcase "A12: the same through a PIPE (\`| od -c\`) — byte-identical"; then
    got="$(TAwk.apply '{print $2}' "$FX/f3.txt" "$FX/unterm.txt" 2>/dev/null | od -c)"
    want="$(timeout 20 gawk --sandbox -e '{print $2}' -- "$FX/f3.txt" "$FX/unterm.txt" </dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream (two files)"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "A12: the same through \`< <( )\` — byte-identical"; then
    got="$(od -c < <(TAwk.apply '{print $2}' "$FX/f3.txt" 2>/dev/null))"
    want="$(timeout 20 gawk --sandbox -e '{print $2}' -- "$FX/f3.txt" </dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "A12: \`TAwk.apply '' PATH\` is rc 2 — gawk would drop \`-e ''\` and compile the path as the program"; then
    ta_dbg TAwk.apply '' "$FX/f3.txt"
    out="$(cd "$FX" && TAwk.apply '' 1 2>/dev/null <<< 'stdin-must-not-be-read')"
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" && "$TA_1" == "Error: TAwk.apply: "* && -z "$out" ]]; then
        kt_test_pass "rc 2, nothing printed (not even for a path named 1): ${TA_1:0:70}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1' out='$out'"
    fi
fi

if tcase "A12: \`TAwk.apply PROGRAM\` with NO path is rc 2, prints nothing, reads nothing"; then
    ta_dbg TAwk.apply '{print}'
    out="$(TAwk.apply '{print}' 2>/dev/null <<< 'stdin-must-not-be-read')"
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" && -z "$out" && "$TA_1" == "Error: TAwk.apply: "* ]]; then
        kt_test_pass "rc 2: ${TA_1:0:70}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N out='$out' first='$TA_1'"
    fi
fi

if tcase "A12: \`TAwk.apply\` with NO argument at all is rc 2 too"; then
    ta_dbg TAwk.apply
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" ]]; then
        kt_test_pass "rc 2, one line"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1'"
    fi
fi

if tcase "A12: an assignment-looking path (\`k=v\`) is rc 2 — nothing read"; then
    ta_dbg TAwk.apply '{print}' k=v
    out="$(TAwk.apply '{print}' k=v 2>/dev/null <<< 'stdin-must-not-be-read')"
    if [[ "$TA_RC" == "2" && "$TA_N" == "1" && "$TA_1" == *"./k=v"* && -z "$out" ]]; then
        kt_test_pass "rc 2: ${TA_1:0:80}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1' out='$out'"
    fi
fi

if tcase "A12: \`apply\` with \`system()\` is REFUSED (sandbox forced) — rc 1, no marker"; then
    rm -f "$MK/m_apply"
    ta_dbg TAwk.apply "BEGIN{system(\"touch $MK/m_apply\")}" "$FX/f3.txt"
    if [[ "$TA_RC" == "1" && "$TOOL_1" == "gawk: "*"sandbox mode"* && ! -e "$MK/m_apply" ]]; then
        kt_test_pass "rc 1; '${TOOL_1:0:60}'"
    else
        kt_test_fail "rc=$TA_RC tool='$TOOL_1' marker=$([[ -e $MK/m_apply ]] && echo present || echo absent)"
    fi
fi

if tcase "A12: \`apply\` on a MISSING file is rc 1 with one line of ours (gawk's 2, mapped)"; then
    ta_dbg TAwk.apply '{print}' "$FX/no_such.txt"
    if [[ "$TA_RC" == "1" && "$TA_N" == "1" && "$TA_1" == *"gawk exited 2"* && "$TOOL_1" == "gawk: "* ]]; then
        kt_test_pass "rc 1: ${TA_1:0:60}"
    else
        kt_test_fail "rc=$TA_RC lines=$TA_N first='$TA_1' tool='$TOOL_1'"
    fi
fi

if tcase "A12: \`apply\` deletes its throw-away instance and bumps \`__TAW_SEQ\`"; then
    before="$__TAW_SEQ"
    TAwk.apply '{print}' "$FX/f3.txt" >/dev/null 2>&1
    TAwk.apply '{print}' "$FX/f3.txt" >/dev/null 2>&1
    after="$__TAW_SEQ"
    left=""
    for s in "$(( before + 1 ))" "$after"; do
        nm="__taw_a_${BASHPID}_${s}"
        for a in _data _paths _progs _vnames _vvals _args _argv; do
            declare -p "${nm}${a}" >/dev/null 2>&1 && left+=" ${nm}${a}"
        done
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TAW_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(TAwk.apply '{print $1}' "$FX/f3b.txt" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "A12: a nested \`apply\` inside an outer \`each\` — both complete, the outer instance survives"; then
    TAwk.new aT '{print $2}' "$FX/f3.txt"
    NEST_OUT=(); NEST_IN=()
    rc=0; aT.each cb_nest 2>/dev/null || rc=$?
    SGOT=()
    arc=0; aT.argv SGOT || arc=$?
    aT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == $'d\ne' ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_IN[@]} -eq 3 && "$inner_ok" == "1" && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is NEST_OUT 1 2 3 && arr_is SGOT gawk --sandbox -e '{print $2}' -- "$FX/f3.txt"; then
        kt_test_pass "3 outer records, 3 nested applies, the outer argv untouched"
    else
        kt_test_fail "rc=$rc outer=$(arr_show NEST_OUT) inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    aT.delete
fi

if tcase "A12: \`apply\` composes with both TPipe forms"; then
    N1=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- TAwk.apply '{print $2}' "$FX/f3.txt" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
N=0
cb() { N=$(( N + 1 )); return 0; }
TAwk.apply "{print \$2}" "$FX/f3.txt" | TPipe.each cb
printf "%s" "$N"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "3" && $crc -eq 0 && "$out" == "3" ]]; then
        kt_test_pass "the \`--\` form: 3 records; the lastpipe form: 3 records"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi
