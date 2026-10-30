#!/usr/bin/env bash
# 008_Helpers.sh — tsed H1: the literal-replace helpers (kcl/tutil/HELPERS_PLAN.md
# §2; launch task L2.7-H): `TSed.quoteRe`, `TSed.quoteRepl`, `addReplace`,
# `TSed.replace`, `TSed.replaceInFile`.
#
# The ORACLE for every behavioural case is the bare GNU tool run with a
# HAND-ESCAPED expression — never the code under test's own escaper. The
# fixture tree is built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so
# the framework tears it down; this file installs NO `trap … EXIT` of its own.
# CR fixtures are written with `printf`, never through an array literal (tutil
# README trap 18).
#
# THE GATE IS THE FIRST CASE, as in 005 (`kt_gnu_gate sed SED_BIN`, ktool): with
# no GNU sed every case that runs sed is a loud `SKIP: <ktool's reason>`, so the
# case COUNT is the same either way. The escaper and argv cases (A, B, F, H) never run sed.
#
# Sections:
#   Z  the ktool gate and the fixture tree
#   A  quoteRe / quoteRepl on the owner probe strings, byte-exact (`od -c`), BRE
#      and `ere`; direct call silent + RESULT, `$( )` prints once; the escapes
#      round-trip through real sed (BRE and -E)
#   B  addReplace -> the exact argv (array comparison, sed never runs): the
#      flags, call order with addExpr, `extended` before/after, the -E escapes;
#      the storage shape (marker + three parallel arrays)
#   C  behaviour against bare sed: every sink and `run`, zero matches, the
#      metachar soup, `& \1 / newline` in TO, multibyte under C.UTF-8 and C,
#      a TAB, the flag semantics
#   D  CR: a FROM ending in CR never matches in text mode (both platform
#      paths), `binary = 1` makes it match; `nullData = 1` + a newline in FROM
#   E  in place: `inPlace` + addReplace keeps CRLF on disk; `replaceInFile` on
#      copies, no backup, zero-match rewrite
#   F  the rc 2 list: rc 2 + RESULT '' + one line + `${inst}_argv` EMPTY +
#      storage intact; the reserved marker; the statics' refusals with stdin
#      left unread
#   G  `TSed.replace` in three positions, nested in an outer sink's callback,
#      the throw-away instance deleted
#   H  lifecycle and the registries: `delete` frees the three new arrays,
#      `clearExprs` empties all four, `s_rfrom`/`s_rto`/`s_rflags` refused,
#      each suffix registered exactly once (also across a `--forget` reload)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tsed.sh"
source "$UNIT"
source "$UNIT_DIR/../tutil/tests/gnu_helper.sh" || exit 1

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/h.err"

# The platform's own CR path; the argv sections pin the cygwin/msys argv (no
# prelude) as 004 does, and restore this value afterwards.
H_NAT="$__TUTIL_TOOLS_STRIP_CR"

kt_test_section "008: TSed — the literal-replace helpers (H1)"

# ===========================================================================
kt_test_section "Z. the ktool gate, and the fixture tree"
# ===========================================================================

kt_gnu_gate sed SED_BIN

# Sections B and F (and the child of H) never run sed: they use the stub of
# `kt_gnu_stub` (launch L3.4 D-L34-7), so they hold on a box without GNU sed.
# The real-tool sections restore KCL_GNU_SED to what the gate left (set or not).
if [[ -v KCL_GNU_SED ]]; then H_KGS_SET=1; H_KGS=$KCL_GNU_SED; else H_KGS_SET=0; H_KGS=''; fi
use_stub() { kt_gnu_stub sed "$TMP/stub" STUB_SED || { echo "008: kt_gnu_stub failed" >&2; exit 1; }; }
use_real() {
    if [[ "$H_KGS_SET" == 1 ]]; then KCL_GNU_SED=$H_KGS; else unset -v KCL_GNU_SED; fi
    ktool.gnu sed >/dev/null || :     # re-warm ktool's cache in the main shell (an override change re-keys it)
}

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

printf -v CR '\r'
printf -v TAB '\t'
printf -v NL '\n'
printf -v EAC '\303\251'          # U+00E9, two bytes in UTF-8
printf -v EUC '\303\211'          # U+00C9, its upper case
printf -v CYa '\320\260'          # U+0430 Cyrillic small a
printf -v CYA '\320\220'          # U+0410 Cyrillic capital A

# The owner probe strings (HELPERS_PLAN §2.3, esc_probe.sh).
P_FROM='a.b*c[d]e^f$g\h/i+j?k|l(m){2}&'
P_TO="X&Y\\1/Z${NL}W"
# ... and their escapes, written out BY HAND (the reference sets).
P_BRE='a\.b\*c\[d]e\^f\$g\\h\/i+j?k|l(m){2}&'
P_ERE='a\.b\*c\[d]e\^f\$g\\h\/i\+j\?k\|l\(m\)\{2\}&'
P_REP="X\\&Y\\\\1\\/Z\\${NL}W"

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf '%s\naxb\na.b\n' "$P_FROM"       > "$FX/soup.txt"
printf 'one\ntwo\n'                     > "$FX/none.txt"
printf 'A.B a.b a.b A.b\n'              > "$FX/case.txt"
printf 'a.b\nxax\na.b a.b\n'            > "$FX/lit.txt"
printf 'caf%s cr%sme %s\n' "$EAC" "$EAC" "$EAC" > "$FX/mb.txt"
printf '%s. %s. %s.%s\n%s %s\n' "$EAC" "$EUC" "$EUC" "$EAC" "$CYa" "$CYA" > "$FX/mbci.txt"
printf 'a\tb a b\n'                     > "$FX/tab.txt"
printf 'a1\r\nb2\r\n'                   > "$FX/crlf.txt"
printf 'x\ny\0z\0'                      > "$FX/nul2.bin"
printf 'f3b\n'                          > "$FX/inner.txt"

kt_test_start "the fixture tree is in place"
need_ok=1
for f in soup.txt none.txt case.txt lit.txt mb.txt mbci.txt tab.txt crlf.txt nul2.bin inner.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
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

odf() { od -c < "$1"; }
ods() { printf '%s' "$1" | od -c; }

# ts_dbg COMMAND... — the switch ON, stderr SPLIT: TS_N/TS_1 are OUR lines
# (`Error:`/`Warning:`), TOOL_N/TOOL_1 sed's own.
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

# check_argv TITLE INST WANT... — `INST.argv GOT` answers rc 0, RESULT = the
# word count, GOT holding exactly WANT (the 004 idiom).
declare -a GOT=()
check_argv() {
    local __zt="$1" __zi="$2"; shift 2
    kt_test_start "$__zt"
    GOT=( sentinel-stale )
    RESULT="result-sentinel"
    local __zrc=0
    "$__zi".argv GOT || __zrc=$?
    if [[ $__zrc -eq 0 && "$RESULT" == "${#GOT[@]}" ]] && arr_is GOT "$@"; then
        kt_test_pass "$(arr_show GOT)"
    else
        kt_test_fail "rc=$__zrc RESULT='$RESULT' got=$(arr_show GOT) want=$(printf '%q ' "$@")"
    fi
}

# store_of INST -> the four storage arrays, rendered (for "storage intact").
store_of() {
    declare -p "$1_exprs" "$1_rfrom" "$1_rto" "$1_rflags" 2>&1
}

# check_rc2 TITLE WANT_MSG_SUBSTR INST — `INST.argv GOT`: rc 2, RESULT '', the
# caller's array untouched, `${inst}_argv` EMPTY, EXACTLY ONE kk.debug line
# naming the reason, the four storage arrays byte-identical; then `INST.run`
# with a here-string on stdin: rc 2, nothing printed, stdin left UNREAD.
check_rc2() {
    local __zt="$1" __zw="$2" __zi="$3"
    kt_test_start "$__zt"
    local __zbefore __zafter __zout __zrrc
    __zbefore="$(store_of "$__zi")"
    GOT=( stale-1 stale-2 )
    RESULT="result-sentinel"
    ts_dbg "$__zi".argv GOT
    local __zres="$RESULT"
    local -n __ziv="${__zi}_argv"
    __zout="$( { "$__zi".run 2>/dev/null; printf 'rc=%s|' "$?"; IFS= read -r __zl; printf '%s' "$__zl"; } <<< 'stdin-kept' )"
    __zafter="$(store_of "$__zi")"
    if [[ "$TS_RC" == "2" && "$__zres" == "" && "$TS_N" == "1" && "$TOOL_N" == "0" && "$TS_1" == *"$__zw"* ]] \
       && arr_is GOT stale-1 stale-2 && (( ${#__ziv[@]} == 0 )) \
       && [[ "$__zbefore" == "$__zafter" && "$__zout" == "rc=2|stdin-kept" ]]; then
        kt_test_pass "rc 2, RESULT '', argv empty, storage intact, run rc 2 with stdin unread: ${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC RESULT='$__zres' lines=$TS_N tool=$TOOL_N first='$TS_1' got=$(arr_show GOT) instArgv=$(arr_show __ziv) run='$__zout' storage-same=$([[ "$__zbefore" == "$__zafter" ]] && echo yes || echo no)"
    fi
}

declare -a SGOT=()
declare -a SWANT=()

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

# ===========================================================================
kt_test_section "A. quoteRe / quoteRepl — the escape sets, byte-exact"
# ===========================================================================

# q_is TITLE WANT MEMBER ARG... — a DIRECT call: rc 0, RESULT == WANT byte for
# byte (`od -c`), nothing on stdout (redirected to a file, no subshell).
q_is() {
    local __zt="$1" __zw="$2"; shift 2
    kt_test_start "$__zt"
    RESULT="sentinel"
    local __zrc=0
    "$@" > "$TMP/q.out" 2>"$TMP/q.err" || __zrc=$?
    local __zg="$RESULT"
    if [[ $__zrc -eq 0 && "$(ods "$__zg")" == "$(ods "$__zw")" && ! -s "$TMP/q.out" && ! -s "$TMP/q.err" ]]; then
        kt_test_pass "RESULT=$(printf '%q' "$__zg"), silent"
    else
        kt_test_fail "rc=$__zrc RESULT=$(printf '%q' "$__zg") want=$(printf '%q' "$__zw") stdout=$(wc -c < "$TMP/q.out") stderr=$(wc -c < "$TMP/q.err")"
    fi
}

q_is "quoteRe PROBE (BRE): \`\\ / . * [ ^ \$\` escaped, \`+ ? | ( ) { } &\` left alone" "$P_BRE" TSed.quoteRe "$P_FROM"
q_is "quoteRe PROBE ere: also \`+ ? ( ) { } |\`" "$P_ERE" TSed.quoteRe "$P_FROM" ere
q_is "quoteRepl PROBE: \`\\ / &\` escaped, the newline -> backslash + newline" "$P_REP" TSed.quoteRepl "$P_TO"
q_is "quoteRe: a newline becomes \`\\n\` (BRE and ere alike)" 'a\nb\\n' TSed.quoteRe "a${NL}b\\n"
q_is "quoteRe ere: a newline becomes \`\\n\` too" 'a\nb\(' TSed.quoteRe "a${NL}b(" ere
kt_test_start "quoteRe: a dialect word other than exactly \`ere\` (\`ERE\`, \`-E\`, \`1\`, '' given) is rc 2, RESULT '', one line, \`\$( )\` prints nothing — it fails CLOSED"
out=""
for w in ERE -E 1 ''; do
    RESULT=sentinel
    ts_dbg TSed.quoteRe 'a+.b(' "$w"
    r="$RESULT"
    c="$(TSed.quoteRe 'a+.b(' "$w" 2>/dev/null)"
    if [[ "$TS_RC" == "2" && -z "$r" && "$TS_N" == "1" && "$TOOL_N" == "0" && "$TS_1" == *"exactly 'ere'"* && -z "$c" ]]; then
        out+="ok "
    else
        out+="BAD[$w]:rc=$TS_RC,RESULT=$r,lines=$TS_N,first=$TS_1,captured=$c "
    fi
done
if [[ "$out" == "ok ok ok ok " ]]; then
    kt_test_pass "ERE -E 1 '' all refused; absent and \`ere\` are pinned above"
else
    kt_test_fail "$out"
fi
q_is "quoteRe: an empty TEXT is RESULT '', rc 0" '' TSed.quoteRe ''
q_is "quoteRe: a backslash already in TEXT is doubled ONCE (backslash escaped first)" 'a\\\.\\\/' TSed.quoteRe 'a\.\/'
q_is "quoteRe: TAB, CR and multibyte pass through unescaped" "a${TAB}b${CR}${EAC}" TSed.quoteRe "a${TAB}b${CR}${EAC}"
q_is "quoteRepl: \`\\1\`, \`&\`, \`/\` and two newlines" "\\\\1\\&\\/\\${NL}\\${NL}" TSed.quoteRepl "\\1&/${NL}${NL}"
q_is "quoteRepl: an empty TEXT is RESULT ''" '' TSed.quoteRepl ''

kt_test_start "\`\$( )\` prints the value exactly ONCE (quoteRe, quoteRe ere, quoteRepl)"
v1="$(TSed.quoteRe 'a.b/c')"
v2="$(TSed.quoteRe 'a(b)' ere)"
v3="$(TSed.quoteRepl 'x&y')"
if [[ "$v1" == 'a\.b\/c' && "$v2" == 'a\(b\)' && "$v3" == 'x\&y' ]]; then
    kt_test_pass "$(printf '%q %q %q' "$v1" "$v2" "$v3")"
else
    kt_test_fail "$(printf '%q %q %q' "$v1" "$v2" "$v3")"
fi

kt_test_start "the BRE escape of a string WITHOUT metacharacters is the string itself"
TSed.quoteRe 'plain words 123' > /dev/null
r1="$RESULT"
TSed.quoteRepl 'plain words 123' > /dev/null
r2="$RESULT"
if [[ "$r1" == 'plain words 123' && "$r2" == 'plain words 123' ]]; then
    kt_test_pass "unchanged"
else
    kt_test_fail "re='$r1' repl='$r2'"
fi

if tcase "the probe round-trips through REAL sed (BRE): \`s/<quoteRe FROM>/<quoteRepl TO>/g\` — FROM replaced, \`axb\` and \`a.b\` untouched"; then
    TSed.quoteRe "$P_FROM"; qf="$RESULT"
    TSed.quoteRepl "$P_TO"; qt="$RESULT"
    got="$("$SED_BIN" --sandbox -e "s/$qf/$qt/g" -- "$FX/soup.txt" | od -c)"
    want="$(printf '%s\naxb\na.b\n' "$P_TO" | od -c)"
    if [[ "$got" == "$want" ]]; then
        kt_test_pass "byte-exact"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "the probe round-trips through REAL sed -E: \`quoteRe FROM ere\`"; then
    TSed.quoteRe "$P_FROM" ere; qf="$RESULT"
    TSed.quoteRepl "$P_TO"; qt="$RESULT"
    got="$("$SED_BIN" --sandbox -E -e "s/$qf/$qt/g" -- "$FX/soup.txt" | od -c)"
    want="$(printf '%s\naxb\na.b\n' "$P_TO" | od -c)"
    if [[ "$got" == "$want" ]]; then
        kt_test_pass "byte-exact"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

# ===========================================================================
kt_test_section "B. addReplace -> the argv (sed never runs)"
# ===========================================================================

__TUTIL_TOOLS_STRIP_CR=1
use_stub

TSed.new hB '' f.txt
hB.addReplace 'a.b' 'x&y'
check_argv "no FLAGS = every occurrence: \`s/a\\.b/x\\&y/g\`" hB \
    "$STUB_SED" --sandbox -e 's/a\.b/x\&y/g' -- f.txt

TSed.new hB '' f.txt
hB.addReplace 'a.b' 'x' rfIgnoreCase
check_argv "FLAGS \`rfIgnoreCase\` = ONLY what it names: \`I\` (no \`g\` — TStringHelper's rule)" hB \
    "$STUB_SED" --sandbox -e 's/a\.b/x/I' -- f.txt

TSed.new hB '' f.txt
hB.addReplace 'a.b' 'x' ''
check_argv "FLAGS \`''\` (given, empty): neither \`g\` nor \`I\` — the first occurrence" hB \
    "$STUB_SED" --sandbox -e 's/a\.b/x/' -- f.txt

TSed.new hB '' f.txt
hB.addReplace 'a.b' 'x' rfReplaceAll
check_argv "FLAGS \`rfReplaceAll\`: \`g\`" hB \
    "$STUB_SED" --sandbox -e 's/a\.b/x/g' -- f.txt

TSed.new hB '' f.txt
hB.addReplace 'a' 'x' 'rfReplaceAll rfIgnoreCase'
hB.addReplace 'b' 'y' 'rfIgnoreCase rfReplaceAll'
hB.addReplace 'c' 'z' "  rfIgnoreCase${TAB}rfReplaceAll${NL}"
check_argv "\`rfReplaceAll rfIgnoreCase\` in any order and with any blanks: \`gI\`" hB \
    "$STUB_SED" --sandbox -e 's/a/x/gI' -e 's/b/y/gI' -e 's/c/z/gI' -- f.txt

TSed.new hB 'E0' f.txt
hB.addExpr '1d'
hB.addReplace '/' '\'
hB.addExpr '' 'p'
hB.addReplace 'q' 'r'
check_argv "call order with interleaved addExpr (expr first; an empty addExpr keeps its slot)" hB \
    "$STUB_SED" --sandbox -e E0 -e 1d -e 's/\//\\/g' -e '' -e p -e 's/q/r/g' -- f.txt

TSed.new hB '' f.txt
hB.extended = 1
hB.addReplace 'a+b(c)|{2}?' 'R'
declare -a GOT_BEFORE=(); hB.argv GOT_BEFORE
TSed.new hB '' f.txt
hB.addReplace 'a+b(c)|{2}?' 'R'
hB.extended = 1
check_argv "-E: \`+?(){}|\` escaped, and the SAME argv whether \`extended = 1\` came before or after addReplace" hB \
    "$STUB_SED" --sandbox -E -e 's/a\+b\(c\)\|\{2\}\?/R/g' -- f.txt
kt_test_start "... the \`extended\`-before build is identical word for word"
if arr_eq GOT_BEFORE GOT; then
    kt_test_pass "$(arr_show GOT_BEFORE)"
else
    kt_test_fail "before=$(arr_show GOT_BEFORE) after=$(arr_show GOT)"
fi

hB.extended = 0
check_argv "the dialect is read at BUILD time: \`extended\` back to 0 -> the BRE escape again" hB \
    "$STUB_SED" --sandbox -e 's/a+b(c)|{2}?/R/g' -- f.txt

TSed.new hB '' f.txt
hB.addReplace "$P_FROM" "$P_TO"
check_argv "the owner probe: FROM and TO escaped exactly like the hand-written reference" hB \
    "$STUB_SED" --sandbox -e "s/$P_BRE/$P_REP/g" -- f.txt

TSed.new hB '' f.txt
hB.nullData = 1
hB.addReplace "x${NL}y" 'Q'
check_argv "\`nullData = 1\`: a newline in FROM is legal and becomes \`\\n\` (+ the derived -z -b)" hB \
    "$STUB_SED" --sandbox -z -b -e 's/x\ny/Q/g' -- f.txt

TSed.new hB '' f.txt
hB.addReplace 'a' "b${NL}c"
check_argv "a newline in TO is fine in line mode: backslash + newline, ONE word" hB \
    "$STUB_SED" --sandbox -e "s/a/b\\${NL}c/g" -- f.txt

TSed.new hB '' f.txt
hB.addReplace "a${CR}" 'b'
check_argv "a CR in FROM is passed through (text mode strips the line-end CR before the script — §D)" hB \
    "$STUB_SED" --sandbox -e "s/a${CR}/b/g" -- f.txt

TSed.new hB '' f.txt
hB.inPlace = 1
hB.addReplace 'a' 'b'
check_argv "\`inPlace = 1\` + addReplace: -b -i, then the expression" hB \
    "$STUB_SED" --sandbox -b -i -e 's/a/b/g' -- f.txt

kt_test_start "the prelude path (__TUTIL_TOOLS_STRIP_CR = 0): the CR prelude first, then the literal s///"
__TUTIL_TOOLS_STRIP_CR=0
TSed.new hB '' f.txt
hB.addReplace 'a.b' 'c'
GOT=(); rc=0; hB.argv GOT || rc=$?
__TUTIL_TOOLS_STRIP_CR=1
if [[ $rc -eq 0 ]] && arr_is GOT "$STUB_SED" --sandbox -e "$__TUTIL_CR_SED" -e t__tsd_cr -e :__tsd_cr -e 's/a\.b/c/g' -- f.txt; then
    kt_test_pass "$(arr_show GOT)"
else
    kt_test_fail "rc=$rc got=$(arr_show GOT)"
fi

kt_test_start "storage: \`_exprs\` keeps call order with the marker, the raw data in three parallel arrays at the SAME index"
TSed.new hS 'E0' f.txt
hS.addExpr 'x'
hS.addReplace 'a.b' 'c&d' rfIgnoreCase
hS.addExpr ''
hS.addReplace 'F2' 'T2'
hS.addReplace 'F3' 'T3' ''
if arr_is hS_exprs x __tsd_r__ '' __tsd_r__ __tsd_r__ \
   && arr_is hS_rfrom '' 'a.b' '' F2 F3 \
   && arr_is hS_rto '' 'c&d' '' T2 T3 \
   && arr_is hS_rflags '' rfIgnoreCase '' rfReplaceAll ''; then
    kt_test_pass "exprs=$(arr_show hS_exprs) rfrom=$(arr_show hS_rfrom) rflags=$(arr_show hS_rflags)"
else
    kt_test_fail "exprs=$(arr_show hS_exprs) rfrom=$(arr_show hS_rfrom) rto=$(arr_show hS_rto) rflags=$(arr_show hS_rflags)"
fi

kt_test_start "addReplace stores RAW and builds nothing: a refused FROM/FLAGS is stored as given, rc 0"
TSed.new hS '' f.txt
rc1=0; hS.addReplace '' 'x' || rc1=$?
rc2=0; hS.addReplace 'a' 'x' 'rfBogus' || rc2=$?
if [[ $rc1 -eq 0 && $rc2 -eq 0 ]] && arr_is hS_rfrom '' a && arr_is hS_rflags rfReplaceAll rfBogus \
   && ! declare -p hS_argv 2>/dev/null | grep -q '\[0\]'; then
    kt_test_pass "both stored; the refusal is buildArgv's (§F)"
else
    kt_test_fail "rc1=$rc1 rc2=$rc2 rfrom=$(arr_show hS_rfrom) rflags=$(arr_show hS_rflags)"
fi
hS.delete

TSed.new hB '' f.txt
hB.addReplace 'a.b'
check_argv "\`addReplace FROM\` with NO TO: TO is '' — the text is deleted (\`s/a\\.b//g\`)" hB \
    "$STUB_SED" --sandbox -e 's/a\.b//g' -- f.txt

kt_test_start "buildArgv leaves NO \`__tsd_\` scratch variable behind (a success and a refused build)"
v_before="$(compgen -v | grep '^__tsd_' | tr '\n' ' ' || :)"
TSed.new hB '' f.txt
hB.addExpr 'p'
hB.addReplace 'a.b' 'c&d' 'rfReplaceAll rfIgnoreCase'
hB.argv GOT >/dev/null 2>&1
TSed.new hG '' f.txt
hG.addReplace 'a' 'b' 'rfNope'
hG.argv GOT >/dev/null 2>&1
TSed.quoteRe 'a.b' ere >/dev/null
TSed.quoteRepl 'a&b' >/dev/null
v_after="$(compgen -v | grep '^__tsd_' | tr '\n' ' ' || :)"
if [[ "$v_before" == "$v_after" && -z "$v_after" ]]; then
    kt_test_pass "no __tsd_* variable outside a member frame, before or after"
else
    kt_test_fail "before='$v_before' after='$v_after'"
fi
hG.delete
hB.delete

__TUTIL_TOOLS_STRIP_CR="$H_NAT"
use_real

# ===========================================================================
kt_test_section "C. behaviour against the bare tool"
# ===========================================================================

if tcase "every sink and \`run\` agree with bare sed: \`addReplace a.b Q\` on (a.b xax 'a.b a.b')"; then
    TSed.new hK '' "$FX/lit.txt"
    hK.addReplace 'a.b' 'Q'
    oracleL SWANT "$SED_BIN" --sandbox -e 's/a\.b/Q/g' -- "$FX/lit.txt"
    SGOT=()
    arc=0; hK.toArray SGOT || arc=$?; an="$RESULT"
    CB_RECS=()
    erc=0; hK.each cb_collect || erc=$?
    crc=0; hK.count || crc=$?; cn="$RESULT"
    frc=0; hK.first || frc=$?; fv="$RESULT"
    THTestList.new hKL
    lrc=0; hK.toList hKL || lrc=$?; ln="$RESULT"
    rrc=0; hK.run > "$TMP/run.out" 2>/dev/null || rrc=$?
    "$SED_BIN" --sandbox -e 's/a\.b/Q/g' -- "$FX/lit.txt" > "$TMP/bare.out"
    if [[ "$arc$erc$crc$frc$lrc$rrc" == "000000" && "$an" == "3" && "$cn" == "3" && "$ln" == "3" \
          && "$(hKL.N)" == "3" && "$fv" == "Q" ]] \
       && arr_is SWANT Q xax 'Q Q' && arr_eq SGOT SWANT && arr_eq CB_RECS SWANT \
       && cmp -s "$TMP/run.out" "$TMP/bare.out"; then
        kt_test_pass "(Q xax 'Q Q') from all six, rc 0; run byte-identical to bare sed"
    else
        kt_test_fail "rc=$arc$erc$crc$frc$lrc$rrc toArray=$(arr_show SGOT) each=$(arr_show CB_RECS) count=$cn first='$fv' list=$ln want=$(arr_show SWANT)"
    fi
    hKL.delete
    hK.delete
fi

if tcase "zero matches: rc 0, lastRc 0, \`run\` byte-identical to the file"; then
    TSed.new hZ '' "$FX/none.txt"
    hZ.addReplace 'zzz' 'Q'
    rc=0; hZ.run > "$TMP/none.out" 2>/dev/null || rc=$?
    hZ.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$lr" == "0" ]] && cmp -s "$TMP/none.out" "$FX/none.txt"; then
        kt_test_pass "the file's own bytes"
    else
        kt_test_fail "rc=$rc lastRc=$lr out=$(od -c < "$TMP/none.out" | tr '\n' '|')"
    fi
    hZ.delete
fi

if tcase "the metachar soup FROM is matched LITERALLY, TO with \`& \\1 / newline\` is literal — == bare sed with the hand escape"; then
    TSed.new hP '' "$FX/soup.txt"
    hP.addReplace "$P_FROM" "$P_TO"
    got="$(hP.run 2>/dev/null | od -c)"
    want="$("$SED_BIN" --sandbox -e "s/$P_BRE/$P_REP/g" -- "$FX/soup.txt" | od -c)"
    lit="$(printf '%s\naxb\na.b\n' "$P_TO" | od -c)"
    SGOT=(); hP.toArray SGOT
    if [[ "$got" == "$want" && "$got" == "$lit" ]] && arr_is SGOT 'X&Y\1/Z' W axb a.b; then
        kt_test_pass "$(arr_show SGOT)"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}' records=$(arr_show SGOT)"
    fi
    hP.delete
fi

if tcase "the same under \`extended = 1\` (the -E escape set) — the same bytes"; then
    TSed.new hP '' "$FX/soup.txt"
    hP.addReplace "$P_FROM" "$P_TO"
    hP.extended = 1
    got="$(hP.run 2>/dev/null | od -c)"
    want="$("$SED_BIN" --sandbox -E -e "s/$P_ERE/$P_REP/g" -- "$FX/soup.txt" | od -c)"
    lit="$(printf '%s\naxb\na.b\n' "$P_TO" | od -c)"
    if [[ "$got" == "$want" && "$got" == "$lit" ]]; then
        kt_test_pass "byte-exact"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
    hP.delete
fi

if tcase "the flags against the text \`A.B a.b a.b A.b\`: default, \`''\`, rfIgnoreCase, both"; then
    out=""
    for fl in DEFAULT '' rfIgnoreCase 'rfReplaceAll rfIgnoreCase'; do
        TSed.new hF '' "$FX/case.txt"
        if [[ "$fl" == DEFAULT ]]; then
            hF.addReplace 'a.b' 'Q'
        else
            hF.addReplace 'a.b' 'Q' "$fl"
        fi
        hF.first; out+="[$RESULT]"
        hF.delete
    done
    b1="$("$SED_BIN" --sandbox -e 's/a\.b/Q/g'  -- "$FX/case.txt")"
    b2="$("$SED_BIN" --sandbox -e 's/a\.b/Q/'   -- "$FX/case.txt")"
    b3="$("$SED_BIN" --sandbox -e 's/a\.b/Q/I'  -- "$FX/case.txt")"
    b4="$("$SED_BIN" --sandbox -e 's/a\.b/Q/gI' -- "$FX/case.txt")"
    if [[ "$out" == "[A.B Q Q A.b][A.B Q a.b A.b][Q a.b a.b A.b][Q Q Q Q]" && "$out" == "[$b1][$b2][$b3][$b4]" ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "got $out; bare [$b1][$b2][$b3][$b4]"
    fi
fi

if tcase "a multibyte FROM under LC_CTYPE=C.UTF-8 AND under C — the same bytes as bare sed in each"; then
    out=""
    for loc in C.UTF-8 C; do
        TSed.new hM '' "$FX/mb.txt"
        hM.addReplace "$EAC" 'E'
        g="$(LC_ALL="$loc" hM.run 2>/dev/null | od -c)"
        b="$(LC_ALL="$loc" "$SED_BIN" --sandbox -e "s/$EAC/E/g" -- "$FX/mb.txt" | od -c)"
        w="$(printf 'cafE crEme E\n' | od -c)"
        if [[ "$g" == "$b" && "$g" == "$w" ]]; then out+="ok:$loc "; else out+="BAD:$loc:${g//$'\n'/|} "; fi
        hM.delete
    done
    if [[ "$out" == "ok:C.UTF-8 ok:C " ]]; then
        kt_test_pass "cafE crEme E in both"
    else
        kt_test_fail "$out"
    fi
fi

if tcase "a FROM with a TAB: \`a<TAB>b\` replaced, \`a b\` untouched"; then
    TSed.new hT '' "$FX/tab.txt"
    hT.addReplace "a${TAB}b" 'T'
    SGOT=(); rc=0; hT.toArray SGOT || rc=$?
    oracleL SWANT "$SED_BIN" --sandbox -e "s/a${TAB}b/T/g" -- "$FX/tab.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT 'T a b' && arr_eq SGOT SWANT; then
        kt_test_pass "(T a b)"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hT.delete
fi

if tcase "addReplace and addExpr in one script, in call order: \`addExpr 2d\` + \`addReplace a.b Q\` + \`addExpr s/Q/R/\`"; then
    TSed.new hO '' "$FX/lit.txt"
    hO.addExpr '2d'
    hO.addReplace 'a.b' 'Q'
    hO.addExpr 's/Q/R/'
    SGOT=(); rc=0; hO.toArray SGOT || rc=$?
    oracleL SWANT "$SED_BIN" --sandbox -e 2d -e 's/a\.b/Q/g' -e 's/Q/R/' -- "$FX/lit.txt"
    if [[ $rc -eq 0 ]] && arr_is SGOT R 'R Q' && arr_eq SGOT SWANT; then
        kt_test_pass "(R 'R Q')"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hO.delete
fi

# The locale is set the kcl way: exported inside the `$( )` that runs the
# sink, so this shell's own locale is never touched.
if tcase "\`rfIgnoreCase\` folds non-ASCII ONLY under a UTF-8 locale: \`é.\`->X and \`а\`->Y (gI) under C.UTF-8 vs C, each == bare sed"; then
    out=""
    for loc in C.UTF-8 C; do
        TSed.new hU '' "$FX/mbci.txt"
        hU.addReplace "${EAC}." 'X' 'rfReplaceAll rfIgnoreCase'
        hU.addReplace "$CYa" 'Y' 'rfReplaceAll rfIgnoreCase'
        g="$( export LC_ALL="$loc"; hU.run 2>/dev/null )"
        b="$( export LC_ALL="$loc"; "$SED_BIN" --sandbox -e "s/${EAC}\./X/gI" -e "s/${CYa}/Y/gI" -- "$FX/mbci.txt" 2>/dev/null )"
        if [[ "$g" == "$b" ]]; then out+="[$loc:$g]"; else out+="[$loc:DIFF:$g|bare:$b]"; fi
        hU.delete
    done
    want="[C.UTF-8:X X X${EAC}${NL}Y Y][C:X ${EUC}. ${EUC}.${EAC}${NL}Y ${CYA}]"
    if [[ "$out" == "$want" ]]; then
        kt_test_pass "UTF-8 folds é/É and а/А; C folds neither (plain matching is the same in both)"
    else
        kt_test_fail "got $(printf '%q' "$out") want $(printf '%q' "$want")"
    fi
fi

# ===========================================================================
kt_test_section "D. CR and NUL data"
# ===========================================================================

if tcase "text mode: a FROM ending in CR NEVER matches (the line-end CR is gone before the script) — both platform paths"; then
    out=""
    for nat in "$H_NAT" 0; do
        __TUTIL_TOOLS_STRIP_CR=$nat
        TSed.new hC '' "$FX/crlf.txt"
        hC.addReplace "a1${CR}" 'Z'
        SGOT=(); rc=0; hC.toArray SGOT || rc=$?
        g="$(hC.run 2>/dev/null | od -c)"
        if [[ $rc -eq 0 && "$g" == "$(printf 'a1\nb2\n' | od -c)" ]] && arr_is SGOT a1 b2; then
            out+="ok$nat "
        else
            out+="BAD$nat:rc=$rc,$(arr_show SGOT),${g//$'\n'/|} "
        fi
        hC.delete
    done
    __TUTIL_TOOLS_STRIP_CR="$H_NAT"
    if [[ "$out" == "ok$H_NAT ok0 " ]]; then
        kt_test_pass "(a1 b2) unchanged on the native path and on the prelude path"
    else
        kt_test_fail "$out"
    fi
fi

if tcase "\`binary = 1\`: the same FROM MATCHES — records (Z b2\\r), == bare \`sed -b\`"; then
    TSed.new hC '' "$FX/crlf.txt"
    hC.addReplace "a1${CR}" 'Z'
    hC.binary = 1
    SGOT=(); rc=0; hC.toArray SGOT || rc=$?
    g="$(hC.run 2>/dev/null | od -c)"
    b="$("$SED_BIN" --sandbox -b -e "s/a1${CR}/Z/g" -- "$FX/crlf.txt" | od -c)"
    if [[ $rc -eq 0 && "$g" == "$b" && "$g" == "$(printf 'Z\nb2\r\n' | od -c)" ]] && arr_is SGOT Z "b2$CR"; then
        kt_test_pass "(Z b2\\r); run == bare -b"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) run='${g//$'\n'/|}' bare='${b//$'\n'/|}'"
    fi
    hC.delete
fi

if tcase "\`nullData = 1\`: a newline inside FROM is legal and matches across the line — records (Q z)"; then
    TSed.new hN '' "$FX/nul2.bin"
    hN.nullData = 1
    hN.addReplace "x${NL}y" 'Q'
    SGOT=(); rc=0; hN.toArray SGOT || rc=$?
    oracle0 SWANT "$SED_BIN" --sandbox -z -b -e 's/x\ny/Q/g' -- "$FX/nul2.bin"
    if [[ $rc -eq 0 ]] && arr_is SGOT Q z && arr_eq SGOT SWANT; then
        kt_test_pass "(Q z) == bare sed -z"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    hN.delete
fi

# ===========================================================================
kt_test_section "E. in place"
# ===========================================================================

if tcase "\`inPlace = 1\` + addReplace edits in place, CRLF KEPT on disk (the derived -b), stdout empty"; then
    cp "$FX/crlf.txt" "$FX/ip1.txt"
    TSed.new hI '' "$FX/ip1.txt"
    hI.addReplace 'a1' 'A.1'
    hI.inPlace = 1
    rc=0; hI.run > "$TMP/ip1.out" 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && "$(odf "$FX/ip1.txt")" == "$(printf 'A.1\r\nb2\r\n' | od -c)" && ! -s "$TMP/ip1.out" ]]; then
        kt_test_pass "A.1\\r\\nb2\\r\\n on disk"
    else
        kt_test_fail "rc=$rc bytes=$(odf "$FX/ip1.txt" | tr '\n' '|')"
    fi
    hI.delete
fi

if tcase "\`TSed.replaceInFile\` on two copies: both edited literally, CRLF kept, stdout empty, NO backup file"; then
    mkdir -p "$FX/rif"
    cp "$FX/soup.txt" "$FX/rif/a.txt"
    cp "$FX/crlf.txt" "$FX/rif/b.txt"
    printf 'a.b\r\n' >> "$FX/rif/b.txt"
    before="$(ls -A "$FX/rif" | tr '\n' ' ')"
    rc=0; TSed.replaceInFile 'a.b' 'Q/&' "$FX/rif/a.txt" "$FX/rif/b.txt" > "$TMP/rif.out" 2>/dev/null || rc=$?
    after="$(ls -A "$FX/rif" | tr '\n' ' ')"
    wa="$(printf 'Q/&%s\naxb\nQ/&\n' "${P_FROM#a.b}" | od -c)"
    wb="$(printf 'a1\r\nb2\r\nQ/&\r\n' | od -c)"
    if [[ $rc -eq 0 && "$before" == "$after" && "$(odf "$FX/rif/a.txt")" == "$wa" && "$(odf "$FX/rif/b.txt")" == "$wb" && ! -s "$TMP/rif.out" ]]; then
        kt_test_pass "a.txt and b.txt edited; the directory still holds exactly: $after"
    else
        kt_test_fail "rc=$rc before='$before' after='$after' a=$(odf "$FX/rif/a.txt" | tr '\n' '|') b=$(odf "$FX/rif/b.txt" | tr '\n' '|')"
    fi
fi

if tcase "\`TSed.replaceInFile\` with ZERO matches: rc 0, the bytes identical (sed still rewrites the file — mtime not asserted)"; then
    cp "$FX/crlf.txt" "$FX/rif/z.txt"
    rc=0; TSed.replaceInFile 'zzz' 'Q' "$FX/rif/z.txt" 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && cmp -s "$FX/rif/z.txt" "$FX/crlf.txt"; then
        kt_test_pass "rc 0, byte-identical"
    else
        kt_test_fail "rc=$rc bytes=$(odf "$FX/rif/z.txt" | tr '\n' '|')"
    fi
fi

if tcase "\`TSed.replaceInFile\` on a MISSING file among good ones: rc 1, one line (sed's 2), the good file still edited"; then
    printf 'a.b\n' > "$FX/rif/g.txt"
    ts_dbg TSed.replaceInFile 'a.b' 'Q' "$FX/rif/no_such.txt" "$FX/rif/g.txt"
    if [[ "$TS_RC" == "1" && "$TS_N" == "1" && "$TS_1" == *"sed exited 2"* && "$(cat "$FX/rif/g.txt")" == "Q" ]]; then
        kt_test_pass "rc 1: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' g=$(cat "$FX/rif/g.txt")"
    fi
fi

# ===========================================================================
kt_test_section "F. the rc 2 list"
# ===========================================================================

use_stub

TSed.new hR '' "$FX/lit.txt"
hR.addExpr 'p'
hR.addReplace '' 'x'
check_rc2 "an EMPTY FROM is rc 2 (sed would reuse the previous regex)" "empty FROM" hR

TSed.new hR '' "$FX/lit.txt"
hR.addReplace 'ok' 'x'
hR.addReplace "a${NL}b" 'x'
check_rc2 "a FROM holding a newline with \`nullData = 0\` is rc 2 (it can never match a line)" "newline" hR

TSed.new hR '' "$FX/lit.txt"
hR.addReplace "a${NL}b" 'x'
hR.nullData = 2
check_rc2 "... and with \`nullData = 2\` (only the exact string 1 is on)" "newline" hR

TSed.new hR '' "$FX/lit.txt"
hR.addReplace 'a' 'x' 'rfReplaceAll rfBogus'
check_rc2 "an unknown FLAGS word is rc 2 and the line names it" "'rfBogus'" hR

TSed.new hR '' "$FX/lit.txt"
hR.addReplace 'a' 'x' 'rfReplaceAll,rfIgnoreCase'
check_rc2 "a comma-joined FLAGS string is ONE unknown word (blanks separate the tokens)" "'rfReplaceAll,rfIgnoreCase'" hR

TSed.new hR '' "$FX/lit.txt"
hR.addReplace 'a' 'x' 'rfreplaceall'
check_rc2 "the tokens are case-sensitive: \`rfreplaceall\` is unknown" "'rfreplaceall'" hR

kt_test_start "a refused build derives nothing: \`nullData = 1\` + a bad flag leaves \`nul\` at 0"
TSed.new hR '' "$FX/lit.txt"
hR.nullData = 1
hR.addReplace 'a' 'x' 'rfNope'
hR.argv GOT >/dev/null 2>&1
if [[ "$(hR.nul)" == "0" && "$(hR._nulDerived)" == "0" ]]; then
    kt_test_pass "nul 0, _nulDerived 0"
else
    kt_test_fail "nul='$(hR.nul)' _nulDerived='$(hR._nulDerived)'"
fi
hR.delete

kt_test_start "\`addExpr '__tsd_r__'\` is rc 2 with one line naming the reserved word; NOTHING of that call is appended"
TSed.new hX '' f.txt
hX.addExpr 'keep'
bx="$(store_of hX)"
ts_dbg hX.addExpr 'before' '__tsd_r__' 'after'
ax="$(store_of hX)"
if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TS_1" == *"__tsd_r__"* && "$TS_1" == *reserved* && "$bx" == "$ax" ]] \
   && arr_is hX_exprs keep; then
    kt_test_pass "${TS_1:0:80}"
else
    kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' exprs=$(arr_show hX_exprs)"
fi
hX.delete

if tcase "\`TSed.edit '__tsd_r__' f\` is rc 2 with ONE line, nothing printed"; then
    ts_dbg TSed.edit '__tsd_r__' "$FX/lit.txt"
    out="$(TSed.edit '__tsd_r__' "$FX/lit.txt" 2>/dev/null)"
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TOOL_N" == "0" && -z "$out" && "$TS_1" == *"__tsd_r__"* ]]; then
        kt_test_pass "${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N tool=$TOOL_N out='$out' first='$TS_1'"
    fi
fi

# st_rc2 TITLE WANT MEMBER ARG... — a static refusal: rc 2, ONE line of ours,
# nothing from sed, nothing on stdout, and a here-string on stdin left UNREAD.
st_rc2() {
    local __zt="$1" __zw="$2"; shift 2
    kt_test_start "$__zt"
    ts_dbg "$@" <<< 'stdin-kept'
    local __zout
    __zout="$( { "$@" 2>/dev/null; printf 'rc=%s|' "$?"; IFS= read -r __zl; printf '%s' "$__zl"; } <<< 'stdin-kept' )"
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TOOL_N" == "0" && "$TS_1" == *"$__zw"* && "$__zout" == "rc=2|stdin-kept" ]]; then
        kt_test_pass "rc 2, nothing printed, stdin unread: ${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N tool=$TOOL_N first='$TS_1' out='$__zout'"
    fi
}

st_rc2 "\`TSed.replace FROM TO\` with NO path is rc 2 (sed would read the caller's stdin)" "TSed.replace" TSed.replace a b
st_rc2 "\`TSed.replace\` with no argument at all is rc 2" "TSed.replace" TSed.replace
st_rc2 "\`TSed.replaceInFile FROM TO\` with NO path is rc 2" "TSed.replaceInFile" TSed.replaceInFile a b
st_rc2 "\`TSed.replaceInFile FROM TO -\` is rc 2 (the in-place refusal of the path \`-\`)" "path '-'" TSed.replaceInFile a b -
st_rc2 "\`TSed.replace '' TO f\` is rc 2 (an empty FROM, buildArgv's line)" "empty FROM" TSed.replace '' b "$FX/lit.txt"
st_rc2 "\`TSed.replace\` with a newline in FROM is rc 2" "newline" TSed.replace "a${NL}b" c "$FX/lit.txt"

if tcase "\`TSed.replaceInFile '' TO f\` is rc 2 and the file is byte-identical"; then
    cp "$FX/lit.txt" "$FX/rif/e.txt"
    ts_dbg TSed.replaceInFile '' 'x' "$FX/rif/e.txt"
    if [[ "$TS_RC" == "2" && "$TS_N" == "1" ]] && cmp -s "$FX/rif/e.txt" "$FX/lit.txt"; then
        kt_test_pass "${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1'"
    fi
fi

kt_test_start "\`addReplace\` with MORE than three arguments (unquoted flags) is rc 2 AT THE CALL, one line naming the usage, nothing appended; the next build is unaffected"
__TUTIL_TOOLS_STRIP_CR=1
TSed.new hY '' f.txt
hY.addReplace 'a.b' 'c'
by="$(store_of hY)"
ts_dbg hY.addReplace 'x' 'y' rfReplaceAll rfIgnoreCase
ay="$(store_of hY)"
GOT=(); arc=0; hY.argv GOT || arc=$?
__TUTIL_TOOLS_STRIP_CR="$H_NAT"
if [[ "$TS_RC" == "2" && "$TS_N" == "1" && "$TS_1" == *"addReplace FROM TO [FLAGS]"* && "$by" == "$ay" && $arc -eq 0 ]] \
   && arr_is hY_exprs __tsd_r__ && arr_is GOT "$STUB_SED" --sandbox -e 's/a\.b/c/g' -- f.txt; then
    kt_test_pass "${TS_1:0:80}"
else
    kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' storage-same=$([[ "$by" == "$ay" ]] && echo yes || echo no) argvRc=$arc argv=$(arr_show GOT)"
fi
hY.delete
use_real

# ===========================================================================
kt_test_section "G. \`TSed.replace FROM TO PATH...\` — the stream one-liner"
# ===========================================================================

if tcase "\`TSed.replace\` DIRECT == bare sed with the hand escape (bytes), rc 0"; then
    rc=0; TSed.replace "$P_FROM" "$P_TO" "$FX/soup.txt" "$FX/lit.txt" > "$TMP/r1.out" 2>/dev/null || rc=$?
    "$SED_BIN" --sandbox -e "s/$P_BRE/$P_REP/g" -- "$FX/soup.txt" "$FX/lit.txt" > "$TMP/r1.bare"
    if [[ $rc -eq 0 && -s "$TMP/r1.bare" ]] && cmp -s "$TMP/r1.out" "$TMP/r1.bare"; then
        kt_test_pass "rc 0 and the same bytes as the bare tool (two files)"
    else
        kt_test_fail "rc=$rc out=$(od -c < "$TMP/r1.out" | tr '\n' '|')"
    fi
fi

if tcase "\`TSed.replace\` never edits in place: the file is byte-identical afterwards"; then
    cp "$FX/lit.txt" "$FX/keep.txt"
    TSed.replace 'a.b' 'Q' "$FX/keep.txt" >/dev/null 2>&1
    if cmp -s "$FX/keep.txt" "$FX/lit.txt"; then
        kt_test_pass "untouched"
    else
        kt_test_fail "the file changed"
    fi
fi

if tcase "\`TSed.replace\` through a PIPE (\`| od -c\`) and through \`< <( )\` — byte-identical"; then
    g1="$(TSed.replace 'a.b' 'Q' "$FX/lit.txt" 2>/dev/null | od -c)"
    g2="$(od -c < <(TSed.replace 'a.b' 'Q' "$FX/lit.txt" 2>/dev/null))"
    want="$("$SED_BIN" --sandbox -e 's/a\.b/Q/g' -- "$FX/lit.txt" | od -c)"
    if [[ "$g1" == "$want" && "$g2" == "$want" && -n "$want" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "pipe='${g1//$'\n'/|}' procsub='${g2//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcaseT "\`TSed.replace\` in the three positions: terminal (a file), lastpipe, the TPipe \`--\` form"; then
    N1=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- TSed.replace 'a.b' 'Q' "$FX/lit.txt" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" "$KT_TIMEOUT" -k 5 30 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
R=()
cb() { R+=( "$1" ); return 0; }
TSed.replace "a.b" "Q" "$FX/lit.txt" | TPipe.each cb
printf "%s|" "${R[@]}"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "3" && $crc -eq 0 && "$out" == "Q|xax|Q Q|" ]]; then
        kt_test_pass "the \`--\` form: 3 records; the lastpipe form: (Q xax 'Q Q')"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi

if tcase "\`TSed.replace\` on a MISSING file is rc 1 with one line of ours (sed's 2, mapped)"; then
    ts_dbg TSed.replace 'a' 'b' "$FX/no_such.txt"
    if [[ "$TS_RC" == "1" && "$TS_N" == "1" && "$TS_1" == *"sed exited 2"* && "$TOOL_1" == "$SED_BIN: "* ]]; then
        kt_test_pass "rc 1: ${TS_1:0:60}"
    else
        kt_test_fail "rc=$TS_RC lines=$TS_N first='$TS_1' tool='$TOOL_1'"
    fi
fi

if tcase "\`replace\` and \`replaceInFile\` delete their throw-away instance and bump \`__TSD_SEQ\` once each"; then
    cp "$FX/lit.txt" "$FX/rif/s.txt"
    before="$__TSD_SEQ"
    TSed.replace 'a' 'b' "$FX/lit.txt" >/dev/null 2>&1
    TSed.replaceInFile 'a' 'b' "$FX/rif/s.txt" >/dev/null 2>&1
    TSed.replace 'a' 'b' >/dev/null 2>&1          # refused before the instance: no bump
    after="$__TSD_SEQ"
    left=""
    for s in "$(( before + 1 ))" "$after"; do
        nm="__tsd_e_${BASHPID}_${s}"
        for a in _data _paths _exprs _rfrom _rto _rflags _args _argv; do
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
    inner="$(TSed.replace 'f3b' 'F.3' "$FX/inner.txt" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "a nested \`TSed.replace\` inside an outer \`each\` — both complete, the outer instance survives"; then
    TSed.new hT '' "$FX/lit.txt"
    hT.addReplace 'a.b' 'Q'
    NEST_OUT=(); NEST_IN=()
    rc=0; hT.each cb_nest 2>/dev/null || rc=$?
    hT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == 'F.3' ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_IN[@]} -eq 3 && "$inner_ok" == "1" && "$lr" == "0" ]] \
       && arr_is NEST_OUT Q xax 'Q Q' && arr_is hT_exprs __tsd_r__ && arr_is hT_rfrom 'a.b'; then
        kt_test_pass "3 outer records, 3 nested replaces, the outer storage untouched"
    else
        kt_test_fail "rc=$rc outer=$(arr_show NEST_OUT) inner=$(arr_show NEST_IN) lastRc='$lr'"
    fi
    hT.delete
fi

# ===========================================================================
kt_test_section "H. lifecycle and the out-name registries"
# ===========================================================================

kt_test_start "\`new\` declares the three arrays EMPTY; a reused name starts clean"
TSed.new hL 'x' f.txt
hL.addReplace 'a' 'b' rfIgnoreCase
TSed.new hL 'y' f.txt
if [[ "$(declare -p hL_rfrom 2>&1)" == "declare -a hL_rfrom=()" \
      && "$(declare -p hL_rto 2>&1)" == "declare -a hL_rto=()" \
      && "$(declare -p hL_rflags 2>&1)" == "declare -a hL_rflags=()" ]] && arr_is hL_exprs; then
    kt_test_pass "three empty arrays, _exprs empty"
else
    kt_test_fail "$(store_of hL | tr '\n' ' ')"
fi

kt_test_start "\`clearExprs\` empties ALL FOUR arrays (and keeps \`expr\`)"
hL.addExpr 'p'
hL.addReplace 'a' 'b'
hL.clearExprs
if arr_is hL_exprs && arr_is hL_rfrom && arr_is hL_rto && arr_is hL_rflags && [[ "$(hL.expr)" == "y" ]]; then
    kt_test_pass "all four empty, expr 'y'"
else
    kt_test_fail "$(store_of hL | tr '\n' ' ')"
fi

kt_test_start "\`delete\` frees \`_rfrom\`, \`_rto\`, \`_rflags\` (and \`_exprs\`, \`_paths\`)"
hL.addReplace 'a' 'b'
hL.delete
left=""
for a in _paths _exprs _rfrom _rto _rflags _args _argv _data; do
    declare -p "hL$a" >/dev/null 2>&1 && left+=" $a"
done
if [[ -z "$left" ]]; then
    kt_test_pass "nothing left behind"
else
    kt_test_fail "still declared:$left"
fi

# bad_out TITLE MEMBER NAME — the registry refusal (004's idiom).
TSed.new hA '' f.txt
hA.addReplace 'F' 'T' rfIgnoreCase
bad_out() {
    kt_test_start "$1"
    local __zm="$2" __zn="$3" __zb __za
    __zb="$(store_of hA)"
    RESULT="sentinel"
    ts_dbg hA."$__zm" "$__zn"
    local __zr="$RESULT"
    __za="$(store_of hA)"
    if [[ "$TS_RC" == "2" && "$__zr" == "" && $TS_N -eq 1 && "$TS_1" == *"bad output array name"* \
          && "$TS_1" == *"$__zn"* && "$__zb" == "$__za" ]]; then
        kt_test_pass "rc 2, storage intact: ${TS_1:0:70}"
    else
        kt_test_fail "rc=$TS_RC RESULT='$__zr' lines=$TS_N first='$TS_1'"
    fi
}
bad_out "\`s.argv s_rfrom\` is rc 2 (the suffix registry)"       argv    hA_rfrom
bad_out "\`s.toArray s_rfrom\` is rc 2"                          toArray hA_rfrom
bad_out "\`s.argv s_rto\` is rc 2"                               argv    hA_rto
bad_out "\`s.toArray s_rto\` is rc 2"                            toArray hA_rto
bad_out "\`s.argv s_rflags\` is rc 2"                            argv    hA_rflags
bad_out "\`s.toArray s_rflags\` is rc 2"                         toArray hA_rflags
hA.delete

kt_test_start "each suffix is registered EXACTLY once (\`_exprs _rfrom _rto _rflags\`), \`__tsd_\` once"
cnt=""
for want in _exprs _rfrom _rto _rflags; do
    n=0
    for q in "${TUTIL_OUT_SUFFIXES[@]}"; do [[ "$q" == "$want" ]] && n=$(( n + 1 )); done
    cnt+="$want=$n "
done
n=0
for q in "${TUTIL_OUT_PREFIXES[@]}"; do [[ "$q" == "__tsd_" ]] && n=$(( n + 1 )); done
cnt+="__tsd_=$n"
if [[ "$cnt" == "_exprs=1 _rfrom=1 _rto=1 _rflags=1 __tsd_=1" ]]; then
    kt_test_pass "suffixes (${TUTIL_OUT_SUFFIXES[*]}); prefixes (${TUTIL_OUT_PREFIXES[*]})"
else
    kt_test_fail "$cnt — suffixes (${TUTIL_OUT_SUFFIXES[*]})"
fi

kt_test_start "... still exactly once after a re-source AND after \`kk.unit --forget tsed\` + a re-source (a child under set -eu)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
out="$(KCL_GNU_SED="$STUB_SED" UNIT="$UNIT" "$KT_TIMEOUT" -k 5 60 "$BASH" -c '
set -eu
source "$UNIT"
source "$UNIT"
kk.unit --forget tsed
source "$UNIT"
c=""
for w in _exprs _rfrom _rto _rflags __tsd_; do
    n=0
    for q in "${TUTIL_OUT_SUFFIXES[@]}" "${TUTIL_OUT_PREFIXES[@]}"; do
        if [[ "$q" == "$w" ]]; then n=$(( n + 1 )); fi
    done
    c+="$w=$n "
done
TSed.new s "" f
s.addReplace a b
declare -a W=()
s.argv W
printf "%s|%s" "$c" "${W[*]}"' 2>/dev/null </dev/null)"; crc=$?
if [[ $crc -eq 0 && "$out" == "_exprs=1 _rfrom=1 _rto=1 _rflags=1 __tsd_=1 |"*"-e s/a/b/g -- f" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "rc=$crc out='$out'"
fi
fi   # kt_need_timeout

