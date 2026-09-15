#!/bin/bash
# 006_Contract.sh — tgrep P2: the kcl-wide contract (kcl/README.md §1) for
# TGrep (tutil/PLAN.md §2.2, §2.4, §5 P2.2).
#
# What it pins:
#
#   source integrity  a sweeping mechanical edit must not silently mangle the
#                     file (`bash -n`, "no single-quoted string left open", no
#                     inline `$'\r'` in a member body, no `$this.` internal call,
#                     no `inherited` inside the constructor).
#   set -eu           TGrep used from a script under `set -eu`, as an instance
#                     and through BOTH TPipe forms (`TPipe.<sink> … -- ARGV` and
#                     a real pipe under `shopt -s lastpipe`), on every outcome:
#                     a hit, no match (rc 1), a grep error (raw 2 -> rc 1), a
#                     refused build (rc 2) and a refused `search` (rc 2).
#   §1.2 diagnostics  exactly ONE `kk.debug` line on each rc 2 path and on each
#                     "grep exited >= 2" path, and NOTHING on a rc 0 path or on a
#                     plain no-match rc 1 — with the switch off, complete silence
#                     from us either way. grep's own `grep: …` lines are the
#                     TOOL's stderr and pass through untouched; `tg_dbg` counts
#                     the two separately.
#
# The GNU banner gate of 005 applies here too: the cases that actually run grep
# are skipped loudly on a box whose `grep` is not GNU.
#
# Every child sets its own stdin explicitly (`</dev/null`): ktests gives a test
# child the terminal in `--mode single` and /dev/null in the threaded mode.
# Children get `timeout 20` — a cold source of the unit costs ~1 s idle and ~4 s
# with the runner at 8 workers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tgrep.sh"
TUTIL="$UNIT_DIR/../tutil/tutil.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for TGrep (P2)"

# ===========================================================================
kt_test_section "0. source integrity"
# ===========================================================================

kt_test_start "the unit source parses (bash -n)"
if err="$("$BASH" -n "$UNIT" 2>&1)"; then
    kt_test_pass "bash -n clean"
else
    kt_test_fail "bash -n: $err"
fi

kt_test_start "no single-quoted printf format is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then
    kt_test_fail "unterminated format string(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

kt_test_start "no member body carries an inline \$'\\r' (it does not survive \`build\`)"
if bad="$(grep -n "\$'\\\\r'" "$UNIT")"; then
    kt_test_fail "inline CR literal(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

kt_test_start "no internal member call is spelled \`\$this.NAME\` (PLAN §2.2)"
# `$this.NAME` compiles to `$__inst__.call NAME`, which does not set
# `__kk_return_silent`; the callee's `kk._return` then PRINTS whenever the outer
# member runs under `$( )`, `|` or `<( )` — exactly where `run` is used.
if bad="$(grep -n '\$this\.' "$UNIT")"; then
    kt_test_fail "found \$this. call(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "every internal call goes through kk.call_silent"
fi

kt_test_start "the CONSTRUCTOR calls \`parent.constructor grep\`, never \`inherited\` (PLAN §2.1)"
# The Pascal front-end rewrites `inherited` in a constructor to
# `parent.constructor "$@"`, forwarding the descendant's own arguments: TUtil
# would get cmd=PATTERN and every path would be emitted twice.
ctor="$(sed -n '/^TGrep.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor grep"* && "$ctor" != *inherited* ]]; then
    kt_test_pass "explicit \`parent.constructor grep\`, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:200}"
fi

kt_test_start "the DESTRUCTOR frees \`\${inst}_paths\` and then chains with \`inherited\`"
dtor="$(sed -n '/^TGrep.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'unset -v "${__inst__}_paths"'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "own array first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:200}"
fi

kt_test_start "no \`var\` shadows a TUtil or kklass member name (PLAN §1.2 reserved set)"
# A method wrapper is generated after the property wrapper and wins silently, so
# `obj.count = 5` on a shadowing var would be accepted and discarded.
RESERVED=" cmd crlf nul _lastRc buildArgv addArg clearArgs argv run each toArray toList first count lastRc mapRc property call parent delete "
clash=""
declared=""
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"          # left-trim
    case "$line" in
        "var "*)
            name="${line#var }"
            name="${name%%[![:graph:]]*}"            # the first word only
            declared+=" $name"
            if [[ "$RESERVED" == *" $name "* ]]; then
                clash+=" $name"
            fi
            ;;
    esac
done < <(sed -n '/^class TGrep : TUtil/,/^end/p' "$UNIT")
nvars=0
for _ in $declared; do nvars=$(( nvars + 1 )); done
if [[ -z "$clash" && $nvars -ge 22 ]]; then
    kt_test_pass "$nvars declared vars, none colliding with an inherited member"
else
    kt_test_fail "vars=$nvars shadowing:$clash declared:$declared"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`grep\` on PATH is GNU grep"
GREP_VER="$(grep --version 2>/dev/null | head -1 || :)"
if [[ "$GREP_VER" == "grep (GNU grep) "* ]]; then
    GNU_OK=1
    kt_test_pass "$GREP_VER"
else
    kt_test_pass "SKIP: non-GNU grep ('${GREP_VER:-no banner}'); every case that runs grep is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU grep"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/sub"
printf 'alpha needle here\nbeta\nneedle again\n' > "$FX/plain.txt"
printf 'nothing here at all\n'                   > "$FX/other.txt"
printf 'has ( paren\n'                           > "$FX/paren.txt"
printf 'needle deep\n'                           > "$FX/sub/deep.txt"

# ===========================================================================
kt_test_section "1. set -eu — the instance and BOTH TPipe forms, every outcome"
# ===========================================================================

# expect_clean TITLE SNIPPET — the snippet runs in a CHILD under `set -eu` with
# the unit freshly sourced, so an abort fails the case instead of this file. The
# child must end rc 0, print exactly OK and write nothing to stderr. `$FX` and
# `$UNIT` reach it through the ENVIRONMENT, so the snippet itself is single
# quoted and nothing in it is expanded twice.
expect_clean() {
    local title="$1" snippet="$2" out rc err
    if ! tcase "$title"; then
        return 0
    fi
    : > "$ERRF"
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c "set -eu
source \"\$UNIT\"
$snippet
printf OK" 2>"$ERRF" </dev/null)"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "rc=$rc out='$out' stderr='${err:0:200}'"
    fi
}

expect_clean "the unit loads under set -eu" ':'

expect_clean "the unit loads TWICE under set -eu (every re-source guard holds)" \
    'source "$UNIT"
source "$UNIT"'

expect_clean "g.each: a matching instance" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g needle "$FX/plain.txt"
g.each cb
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
g.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
g.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv TGrep built" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g needle "$FX/plain.txt"
declare -a W=()
g.argv W
[[ "$RESULT" == "5" ]] || { printf "words=%s\n" "$RESULT" >&2; exit 9; }
TPipe.each cb -- "${W[@]}"
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
g.delete'

expect_clean "form 2 with \`TGrep.search\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
TPipe.each cb -- TGrep.search needle "$FX/sub"
[[ "$N" == "1" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\`" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
TGrep.search needle "$FX/sub" | TPipe.each cb
[[ "$N" == "1" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "every func sink on a matching instance" '
TGrep.new g needle "$FX/plain.txt"
declare -a A=()
g.toArray A
[[ "$RESULT" == "2" && "${A[1]}" == "needle again" ]] || { printf "toArray=%s\n" "$RESULT" >&2; exit 9; }
g.count
[[ "$RESULT" == "2" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
g.first 2>/dev/null
[[ "$RESULT" == "alpha needle here" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
g.delete'

expect_clean "toList into a kklass instance with an .Add" '
class TL
    public
        var         N
        constructor Create
        proc        Add
end
TL.Create() { N=0; return 0; }
TL.Add()    { N=$(( N + 1 )); return 0; }
build TL
TL.new L
TGrep.new g needle "$FX/plain.txt"
g.toList L
[[ "$RESULT" == "2" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "2" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
g.delete
L.delete'

expect_clean "NO MATCH (raw 1) — rc 1, the child survives, nothing on stderr" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g zzz_no_such "$FX/plain.txt"
rc=0
g.each cb || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
g.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
g.delete'

expect_clean "a GREP ERROR (raw 2: a directory without \`recursive\`) — rc 1, no abort" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g needle "$FX/sub"
rc=0
g.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
g.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
g.delete'

expect_clean "PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT" '
TGrep.new g needle "$FX/plain.txt" "$FX/no_such.txt"
declare -a A=()
rc=0
g.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "2" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 8; }
[[ "${#A[@]}" == "2" ]] || { printf "kept=%s\n" "${#A[@]}" >&2; exit 7; }
g.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
g.delete'

expect_clean "a REFUSED build (-F and -E together) — rc 2, nothing runs, no abort" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g needle "$FX/plain.txt"
g.fixed = 1
g.extended = 1
rc=0
g.each cb || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
g.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s (nothing ran, so it must still be -1)\n" "$RESULT" >&2; exit 7; }
g.delete'

expect_clean "an EMPTY pattern — rc 2 from every runner, no abort" '
TGrep.new g "" "$FX/plain.txt"
declare -a A=( stale )
rc=0; g.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; g.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; g.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
g.delete'

expect_clean "a bad \`maxCount\` — rc 2, no abort" '
TGrep.new g needle "$FX/plain.txt"
g.maxCount = abc
rc=0
g.count || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
g.delete'

expect_clean "\`TGrep.search\` with no path — rc 2, no abort, nothing printed" '
out="$(TGrep.search needle)" || rc=$?
[[ "${rc:-0}" == "2" ]] || { printf "rc=%s\n" "${rc:-0}" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
TGrep.new g needle "$FX/plain.txt"
out="$(g.run)"
[[ "$out" == "alpha needle here
needle again" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
g.run > /dev/null
g.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
g.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
TGrep.new g needle "$FX/plain.txt"
g.delete
declare -p g_paths 2>/dev/null && { printf "g_paths survived\n" >&2; exit 9; }
declare -p g_args  2>/dev/null && { printf "g_args survived\n" >&2; exit 8; }
:'

expect_clean "an instance reading STDIN (no path) under set -eu" '
N=0
cb() { N=$(( N + 1 )); }
TGrep.new g needle
declare -a W=()
g.argv W
TPipe.each cb -- printf "%s\n" "one needle" two
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
out="$(printf "one needle\ntwo\n" | g.run)"
[[ "$out" == "one needle" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }
g.delete'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
TGrep.new g needle "$FX/plain.txt"
n="$(g.count)"
[[ "$n" == "2" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
g.delete'

# D6 final Q9: `subshellOk` is TUtil's, inherited unchanged, and it reaches
# TPipe as the `-s` flag through two frames of wrapper. The case asserts BOTH
# directions: silent with the property set (the child's stderr must be empty),
# and the verbatim TPipe warning without it.
expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through TGrep" '
TGrep.new g needle "$FX/plain.txt"
g.subshellOk = 1
declare -a A=()
n="$(g.toArray A)"
[[ "$n" == "2" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
g.delete
TGrep.new g2 needle "$FX/plain.txt"
declare -a A2=()
w="$( { g2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
g2.delete'

# ===========================================================================
kt_test_section "2. the debug switch — one line per rc 2 / grep-error path"
# ===========================================================================

# tg_dbg COMMAND... — run it with the switch on and SPLIT stderr: TG_N/TG_1 are
# OUR lines (kk.debug prints `Error: …` / `Warning: …`), TOOL_N is grep's own
# `grep: …`, which is the tool's stderr and passes through by design.
TG_RC=0; TG_N=0; TG_1=''; TOOL_N=0
tg_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TG_RC=$?
    VERBOSE_KKLASS=
    TG_N=0; TOOL_N=0; TG_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TG_N=$(( TG_N + 1 ))
                if [[ -z "$TG_1" ]]; then TG_1="$__l"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

# quiet_rc COMMAND... — the same call with the switch OFF: QRC and the stderr we
# produced (grep's own lines are filtered out; they are not ours to suppress).
QRC=0; QOURS=0
quiet_rc() {
    : > "$ERRF"
    "$@" >/dev/null 2>"$ERRF"
    QRC=$?
    QOURS=0
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*) QOURS=$(( QOURS + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

# check_one TITLE WANT_RC WANT_SUBSTR COMMAND... — exactly one line of ours, the
# expected rc, and complete silence from us with the switch off.
check_one() {
    local title="$1" want="$2" sub="$3"; shift 3
    if ! tcase "$title"; then
        return 0
    fi
    tg_dbg "$@"
    local n="$TG_N" first="$TG_1" drc="$TG_RC"
    quiet_rc "$@"
    if [[ "$drc" == "$want" && $n -eq 1 && "$first" == *"$sub"* \
          && "$QRC" == "$want" && "$QOURS" -eq 0 ]]; then
        kt_test_pass "rc $want, one line: ${first:0:74}"
    else
        kt_test_fail "debug rc=$drc lines=$n first='$first' / quiet rc=$QRC ourLines=$QOURS"
    fi
}

# check_silent TITLE WANT_RC COMMAND... — not one line from us, switch on.
check_silent() {
    local title="$1" want="$2"; shift 2
    if ! tcase "$title"; then
        return 0
    fi
    tg_dbg "$@"
    if [[ "$TG_RC" == "$want" && $TG_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TG_RC ourLines=$TG_N first='$TG_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

TGrep.new dOk   needle          "$FX/plain.txt"      # rc 0
TGrep.new dNone zzz_no_such     "$FX/plain.txt"      # plain rc 1 (no match)
TGrep.new dDir  needle          "$FX/sub"            # grep raw 2 (Is a directory)
TGrep.new dMiss needle          "$FX/plain.txt" "$FX/no_such.txt"   # raw 2, partial
TGrep.new dEre  '('             "$FX/paren.txt"      # raw 2 under -E
dEre.extended = 1
TGrep.new dFE   needle          "$FX/plain.txt"      # buildArgv rc 2
dFE.fixed = 1
dFE.extended = 1
TGrep.new dLL   needle          "$FX/plain.txt"
dLL.filesOnly = 1
dLL.filesWithoutMatch = 1
TGrep.new dHH   needle          "$FX/plain.txt"
dHH.noFilename = 1
dHH.withFilename = 1
TGrep.new dMC   needle          "$FX/plain.txt"
dMC.maxCount = abc
TGrep.new dPat  ''              "$FX/plain.txt"
TGrep.new dCmd  needle          "$FX/plain.txt"
dCmd.cmd = ''

check_one "rc 2: \`-F\` + \`-E\` — one line, through \`each\`"      2 "fixed"     dFE.each cb_nul
check_one "rc 2: \`-F\` + \`-E\` — one line, through \`count\`"     2 "fixed"     dFE.count
check_one "rc 2: \`-l\` + \`-L\` — one line"                        2 "filesOnly" dLL.count
check_one "rc 2: \`-h\` + \`-H\` — one line"                        2 "noFilename" dHH.count
check_one "rc 2: a bad \`maxCount\` — one line"                     2 "maxCount"  dMC.count
check_one "rc 2: an empty \`pattern\` — one line"                   2 "pattern"   dPat.count
check_one "rc 2: an empty \`cmd\` — one line"                       2 "cmd"       dCmd.count
check_one "rc 2: \`TGrep.search\` with no path — one line"          2 "search"    TGrep.search needle
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                    2 "output array" dOk.toArray RESULT

check_one "grep raw 2 (a directory without \`recursive\`) — rc 1 and one line" \
                                                                    1 "grep exited 2" dDir.count
check_one "grep raw 2 (an unmatched \`(\` under -E) — rc 1 and one line" \
                                                                    1 "grep exited 2" dEre.count
check_one "grep raw 2 (a missing operand among good ones) — rc 1 and one line" \
                                                                    1 "grep exited 2" dMiss.count

check_silent "rc 0: a successful search says NOTHING"               0 dOk.count
check_silent "rc 0: \`each\` on a hit says NOTHING"                 0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on a hit says NOTHING"              0 dOk.toArray DBG_ARR
check_silent "rc 1: NO MATCH is an answer and says NOTHING"         1 dNone.count
check_silent "rc 1: \`each\` on no match says NOTHING"              1 dNone.each cb_nul
check_silent "rc 1: \`first\` on no match says NOTHING"             1 dNone.first
check_silent "rc 0: \`TGrep.search\` that matched says NOTHING"     0 TGrep.search needle "$FX/sub"
check_silent "rc 1: \`TGrep.search\` that matched nothing says NOTHING" \
                                                                    1 TGrep.search zzz_no_such "$FX/sub"

if tcase "the \`grep exited\` line names TGrep, and grep's OWN line is left alone"; then
    tg_dbg dDir.count
    if [[ "$TG_N" == "1" && "$TG_1" == *"TGrep"* && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "ours: ${TG_1:0:60} | grep's: $TOOL_N line(s) untouched"
    else
        kt_test_fail "ourLines=$TG_N first='$TG_1' toolLines=$TOOL_N"
    fi
fi

dOk.delete
dNone.delete
dDir.delete
dMiss.delete
dEre.delete
dFE.delete
dLL.delete
dHH.delete
dMC.delete
dPat.delete
dCmd.delete
