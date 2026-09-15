#!/bin/bash
# 006_Contract.sh — thead P0: the kcl-wide contract (kcl/README.md §1) for
# THead (thead/PLAN.md §2.1, §2.5, §3 H12).
#
# What it pins:
#
#   source integrity  a sweeping mechanical edit must not silently mangle the
#                     file (`bash -n`, "no single-quoted string left open", no
#                     inline `$'\r'` in a member body, no `$this.` internal call,
#                     no `inherited` inside the constructor, no `kk.isInt` on the
#                     count — §2.2 forbids it).
#   set -eu           THead used from a script under `set -eu`, as an instance
#                     and through BOTH TPipe forms (`TPipe.<sink> … -- ARGV` and
#                     a real pipe under `shopt -s lastpipe`), on every outcome:
#                     records (rc 0), a tool error (raw 1 -> rc 1), a partial
#                     failure, a refused build (rc 2) and a refused `take`.
#                     EVERY sink call in a child is guarded `|| rc=$?`: an
#                     unguarded rc 1 aborts the caller, which is the documented
#                     caller rule and not a bug (H12).
#   §1.2 diagnostics  exactly ONE `kk.debug` line on each rc 2 path and on each
#                     "head exited 1" path, and NOTHING on a rc 0 path — with the
#                     switch off, complete silence from us either way. head's own
#                     `head: …` lines are the TOOL's stderr and pass through
#                     untouched; `th_dbg` counts the two separately.
#   D6 final          `$(h.toArray A)` warns about the subshell, and
#                     `subshellOk = 1` silences it.
#
# The GNU banner gate of 005 applies here too: the cases that actually run head
# are skipped loudly on a box whose `head` is not GNU coreutils.
#
# Every child sets its own stdin explicitly (`</dev/null`): ktests gives a test
# child the terminal in `--mode single` and /dev/null in the threaded mode.
# Children get `timeout 20` — a cold source of the unit costs ~1 s idle and ~4 s
# with the runner at 8 workers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thead.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for THead (P0)"

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

kt_test_start "no internal member call is spelled \`\$this.NAME\` (tutil PLAN §2.2)"
if bad="$(grep -n '\$this\.' "$UNIT")"; then
    kt_test_fail "found \$this. call(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "every internal call goes through kk.call_silent"
fi

kt_test_start "the CONSTRUCTOR calls \`parent.constructor head\`, never \`inherited\` (§2.1)"
# The Pascal front-end rewrites `inherited` in a constructor to
# `parent.constructor "$@"`, forwarding the descendant's own arguments: TUtil
# would get cmd=N and every path would be emitted twice.
ctor="$(sed -n '/^THead.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor head"* && "$ctor" != *inherited* ]]; then
    kt_test_pass "explicit \`parent.constructor head\`, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:200}"
fi

kt_test_start "the DESTRUCTOR frees \`\${inst}_paths\` and then chains with \`inherited\`"
dtor="$(sed -n '/^THead.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'unset -v "${__inst__}_paths"'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "own array first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:200}"
fi

kt_test_start "the count is NOT validated with \`kk.isInt\` (§2.2 — it would fold \`+3\` and \`-0\`)"
if bad="$(grep -nE "^[^#]*kk\.isInt" "$UNIT")"; then
    kt_test_fail "kk.isInt used: ${bad//$'\n'/ | }"
else
    kt_test_pass "the regex + the 19-digit guard, no kk.isInt anywhere in the unit"
fi

kt_test_start "the count regex is held in a VARIABLE and applied with \`[[ =~ ]]\` (§6)"
if grep -q '\^\[+-\]?\[0-9\]+\$' "$UNIT" && grep -q '=~ \$' "$UNIT"; then
    kt_test_pass "\`^[+-]?[0-9]+\$\` in a variable, matched with \`[[ =~ \$re ]]\`"
else
    kt_test_fail "the regex or the \`[[ =~ \$var ]]\` form is missing"
fi

kt_test_start "no \`var\` shadows a TUtil or kklass member name (tutil PLAN §1.2 reserved set)"
# A method wrapper is generated after the property wrapper and wins silently, so
# `obj.count = 5` on a shadowing var would be accepted and discarded.
RESERVED=" cmd crlf nul _lastRc subshellOk buildArgv addArg clearArgs argv run each toArray toList first count lastRc mapRc property call parent delete "
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
done < <(sed -n '/^class THead : TUtil/,/^end/p' "$UNIT")
nvars=0
for _ in $declared; do nvars=$(( nvars + 1 )); done
if [[ -z "$clash" && $nvars -eq 6 ]]; then
    kt_test_pass "$nvars declared vars, none colliding with an inherited member"
else
    kt_test_fail "vars=$nvars shadowing:$clash declared:$declared"
fi

kt_test_start "the unit sources ONLY \`../tutil/tutil.sh\` (nothing is shared with ttail but the plan text)"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$UNIT" || :)"
nsrc=0
while IFS= read -r line; do
    [[ -n "$line" ]] && nsrc=$(( nsrc + 1 ))
done <<< "$srcs"
if [[ $nsrc -eq 1 && "$srcs" == *'/../tutil/tutil.sh"'* ]]; then
    kt_test_pass "one \`source\` line, and it is ../tutil/tutil.sh"
else
    kt_test_fail "$nsrc source line(s): ${srcs//$'\n'/ | }"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`head\` on PATH is GNU coreutils"
HEAD_VER="$(head --version 2>/dev/null | head -1 || :)"
if [[ "$HEAD_VER" == "head (GNU coreutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$HEAD_VER"
else
    kt_test_pass "SKIP: non-GNU head ('${HEAD_VER:-no banner}'); every case that runs head is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU head"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf '1\n2\n3\n4\n5\n'   > "$FX/f5.txt"
printf 'a1\na2\na3\n'      > "$FX/a3.txt"

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
    out="$(FX="$FX" UNIT="$UNIT" timeout 60 "$BASH" -c "set -eu
source \"\$UNIT\"
$snippet
printf OK" 2>"$ERRF" </dev/null)"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "[$title] rc=$rc out='$out' stderr='${err:0:200}'"
    fi
}

expect_clean "the unit loads under set -eu" ':'

expect_clean "the unit loads TWICE under set -eu (every re-source guard holds)" \
    'source "$UNIT"
source "$UNIT"'

expect_clean "h.each: an instance that delivers records" '
N=0
cb() { N=$(( N + 1 )); }
THead.new h 2 "$FX/f5.txt"
rc=0
h.each cb || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
h.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
h.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv THead built" '
N=0
cb() { N=$(( N + 1 )); }
THead.new h 2 "$FX/f5.txt"
declare -a W=()
rc=0
h.argv W || rc=$?
[[ "$rc" == "0" && "$RESULT" == "5" ]] || { printf "words=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
TPipe.each cb -- "${W[@]}" || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
h.delete'

expect_clean "form 2 with \`THead.take\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
rc=0
TPipe.each cb -- THead.take 2 "$FX/f5.txt" || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\`" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
rc=0
THead.take 2 "$FX/f5.txt" | TPipe.each cb || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "every func sink on an instance that delivers" '
THead.new h 3 "$FX/f5.txt"
declare -a A=()
rc=0
h.toArray A || rc=$?
[[ "$rc" == "0" && "$RESULT" == "3" && "${A[2]}" == "3" ]] || { printf "toArray=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
h.count || rc=$?
[[ "$RESULT" == "3" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
h.first || rc=$?
[[ "$RESULT" == "1" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
h.delete'

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
THead.new h 2 "$FX/f5.txt"
rc=0
h.toList L || rc=$?
[[ "$RESULT" == "2" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "2" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
h.delete
L.delete'

expect_clean "a TOOL ERROR (a missing file, raw 1) — rc 1, the child survives" '
N=0
cb() { N=$(( N + 1 )); }
THead.new h 1 "$FX/no_such.txt"
rc=0
h.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
h.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
h.delete'

expect_clean "PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT" '
THead.new h 1 "$FX/f5.txt" "$FX/no_such.txt"
declare -a A=()
rc=0
h.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "${#A[@]}" ]] || { printf "RESULT=%s kept=%s\n" "$RESULT" "${#A[@]}" >&2; exit 8; }
(( ${#A[@]} > 0 )) || { printf "kept=%s\n" "${#A[@]}" >&2; exit 7; }
h.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
h.delete'

expect_clean "a REFUSED build (\`lines\` + \`bytes\`) — rc 2, nothing runs, no abort" '
N=0
cb() { N=$(( N + 1 )); }
THead.new h 2 "$FX/f5.txt"
h.bytes = 3
rc=0
h.each cb || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
h.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s (nothing ran, so it must still be -1)\n" "$RESULT" >&2; exit 7; }
h.delete'

expect_clean "an EMPTY \`cmd\` — rc 2 from every runner, no abort" '
THead.new h 2 "$FX/f5.txt"
h.cmd = ""
declare -a A=( stale )
rc=0; h.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; h.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; h.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
h.delete'

expect_clean "a bad \`lines\` — rc 2, no abort" '
THead.new h 2 "$FX/f5.txt"
h.lines = 1K
rc=0
h.count || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
h.delete'

expect_clean "\`zeroTerminated\` with two paths — rc 2, no abort" '
THead.new h 2 "$FX/f5.txt" "$FX/a3.txt"
h.zeroTerminated = 1
rc=0
h.count || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
h.delete'

expect_clean "\`THead.take\` with no path — rc 2, no abort, nothing printed" '
rc=0
out="$(THead.take 2 </dev/null)" || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
THead.new h 2 "$FX/f5.txt"
rc=0
out="$(h.run)" || rc=$?
[[ "$out" == "1
2" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
h.run > /dev/null || rc=$?
h.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
h.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
THead.new h 2 "$FX/f5.txt"
h.delete
declare -p h_paths 2>/dev/null && { printf "h_paths survived\n" >&2; exit 9; }
declare -p h_args  2>/dev/null && { printf "h_args survived\n" >&2; exit 8; }
:'

expect_clean "an instance reading STDIN (no path) under set -eu" '
THead.new h 2
rc=0
out="$(printf "s1\ns2\ns3\n" | h.run)" || rc=$?
[[ "$out" == "s1
s2" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
h.delete'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
THead.new h 2 "$FX/f5.txt"
n="$(h.count)"
[[ "$n" == "2" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
h.delete'

# D6 final Q9: `subshellOk` is TUtil's, inherited unchanged, and it reaches
# TPipe as the `-s` flag through two frames of wrapper. The case asserts BOTH
# directions: silent with the property set (the child's stderr must be empty),
# and the verbatim TPipe warning without it.
expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through THead" '
THead.new h 2 "$FX/f5.txt"
h.subshellOk = 1
declare -a A=()
n="$(h.toArray A)"
[[ "$n" == "2" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
h.delete
THead.new h2 2 "$FX/f5.txt"
declare -a A2=()
w="$( { h2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
h2.delete'

if tcase "H12: an UNGUARDED sink call with rc 1 aborts a \`set -eu\` caller (the documented rule)"; then
    # Two children, the same call: the unguarded one must die before its
    # `printf`, the guarded one must read rc 1 and carry on. This is the caller
    # rule, not a defect — every sink call in these tests is `|| rc=$?`.
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
THead.new h 1 "$FX/no_such.txt"
h.count
printf NOTREACHED' 2>/dev/null </dev/null)"; urc=$?
    guarded="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
THead.new h 1 "$FX/no_such.txt"
rc=0
h.count || rc=$?
printf "%s" "$rc"' 2>/dev/null </dev/null)"; grc=$?
    if [[ $urc -ne 0 && -z "$out" && $grc -eq 0 && "$guarded" == "1" ]]; then
        kt_test_pass "unguarded: the caller died (rc $urc, nothing printed); guarded: rc 1 and it goes on"
    else
        kt_test_fail "unguarded rc=$urc out='$out'; guarded rc=$grc out='$guarded'"
    fi
fi

# ===========================================================================
kt_test_section "2. the debug switch — one line per rc 2 / tool-error path"
# ===========================================================================

# th_dbg COMMAND... — run it with the switch on and SPLIT stderr: TH_N/TH_1 are
# OUR lines (kk.debug prints `Error: …` / `Warning: …`), TOOL_N is head's own
# `head: …`, which is the tool's stderr and passes through by design.
TH_RC=0; TH_N=0; TH_1=''; TOOL_N=0
th_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TH_RC=$?
    VERBOSE_KKLASS=
    TH_N=0; TOOL_N=0; TH_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TH_N=$(( TH_N + 1 ))
                if [[ -z "$TH_1" ]]; then TH_1="$__l"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

# quiet_rc COMMAND... — the same call with the switch OFF: QRC and the stderr we
# produced (head's own lines are filtered out; they are not ours to suppress).
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
    th_dbg "$@"
    local n="$TH_N" first="$TH_1" drc="$TH_RC"
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
    th_dbg "$@"
    if [[ "$TH_RC" == "$want" && $TH_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TH_RC ourLines=$TH_N first='$TH_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

THead.new dOk   2  "$FX/f5.txt"                        # rc 0
THead.new dMiss 1  "$FX/f5.txt" "$FX/no_such.txt"      # raw 1, partial
THead.new dGone 1  "$FX/no_such.txt"                   # raw 1, nothing
THead.new dNB   2  "$FX/f5.txt"                        # buildArgv rc 2
dNB.bytes = 3
THead.new dQV   2  "$FX/f5.txt"
dQV.quiet = 1
dQV.verbose = 1
THead.new dZ2   2  "$FX/f5.txt" "$FX/a3.txt"
dZ2.zeroTerminated = 1
THead.new dZV   2  "$FX/f5.txt"
dZV.zeroTerminated = 1
dZV.verbose = 1
THead.new dBad  2  "$FX/f5.txt"
dBad.lines = 1K
THead.new dCmd  2  "$FX/f5.txt"
dCmd.cmd = ''

check_one "rc 2: \`lines\` + \`bytes\` — one line, through \`each\`"   2 "lines"          dNB.each cb_nul
check_one "rc 2: \`lines\` + \`bytes\` — one line, through \`count\`"  2 "lines"          dNB.count
check_one "rc 2: \`quiet\` + \`verbose\` — one line"                   2 "quiet"          dQV.count
check_one "rc 2: \`zeroTerminated\` with two paths — one line"         2 "zeroTerminated" dZ2.count
check_one "rc 2: \`zeroTerminated\` + \`verbose\` — one line"          2 "zeroTerminated" dZV.count
check_one "rc 2: a bad \`lines\` — one line"                           2 "lines"          dBad.count
check_one "rc 2: an empty \`cmd\` — one line"                          2 "cmd"            dCmd.count
check_one "rc 2: \`THead.take\` with no path — one line"               2 "take"           THead.take 2
check_one "rc 2: \`THead.take\` with a bad count — one line"           2 "take"           THead.take 1K "$FX/f5.txt"
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                       2 "output array"   dOk.toArray RESULT
check_one "rc 2: \`toArray __th_x\` — one line (the \`__th_\` prefix, §2.8)" \
                                                                       2 "output array"   dOk.toArray __th_x

check_one "head raw 1 (a missing operand among good ones) — rc 1 and one line" \
                                                                       1 "head exited 1"  dMiss.count
check_one "head raw 1 (the only operand missing) — rc 1 and one line"  1 "head exited 1"  dGone.count

check_silent "rc 0: a successful run says NOTHING"                     0 dOk.count
check_silent "rc 0: \`each\` on records says NOTHING"                  0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on records says NOTHING"               0 dOk.toArray DBG_ARR
check_silent "rc 0: \`THead.take\` that succeeded says NOTHING"        0 THead.take 2 "$FX/f5.txt"

if tcase "the \`head exited\` line names THead, and head's OWN line is left alone"; then
    th_dbg dGone.count
    if [[ "$TH_N" == "1" && "$TH_1" == *"THead"* && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "ours: ${TH_1:0:60} | head's: $TOOL_N line(s) untouched"
    else
        kt_test_fail "ourLines=$TH_N first='$TH_1' toolLines=$TOOL_N"
    fi
fi

dOk.delete
dMiss.delete
dGone.delete
dNB.delete
dQV.delete
dZ2.delete
dZV.delete
dBad.delete
dCmd.delete
