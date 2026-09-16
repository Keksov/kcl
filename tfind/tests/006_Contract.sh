#!/bin/bash
# 006_Contract.sh — tfind P0: the kcl-wide contract (kcl/README.md §1) for
# TFind (tfind/PLAN.md §2.1–§2.6, §3 F12).
#
# What it pins:
#
#   source integrity  a sweeping mechanical edit must not silently mangle the
#                     file (`bash -n`, "no single-quoted string left open", no
#                     inline `$'\r'` in a member body, no `$this.` internal call,
#                     no `inherited` inside the constructor, the `type` regex in
#                     a VARIABLE, the depths emitted from `$__KK_INT`, no `--`
#                     word anywhere in the builder, the skeleton sentinel gone).
#   set -eu           TFind used from a script under `set -eu`, as an instance
#                     and through BOTH TPipe forms (`TPipe.<sink> … -- ARGV` and
#                     a real pipe under `shopt -s lastpipe`), on every outcome:
#                     records (rc 0), a tool error (raw 1 -> rc 1), a partial
#                     failure, a refused build (rc 2) and a refused `byName`.
#                     EVERY sink call in a child is guarded `|| rc=$?`: an
#                     unguarded rc 1 aborts the caller, which is the documented
#                     caller rule and not a bug (F12).
#   §1.2 diagnostics  exactly ONE `kk.debug` line on each rc 2 path and on each
#                     "find exited 1" path, and NOTHING on a rc 0 path — with the
#                     switch off, complete silence from us either way. find's own
#                     `find: …` lines are the TOOL's stderr and pass through
#                     untouched; `tf_dbg` counts the two separately.
#   D6 final          `$(f.toArray A)` warns about the subshell, and
#                     `subshellOk = 1` silences it.
#   Windows paths     a start point spelled `C:\…` survives as the record
#                     PREFIX, and every separator find appends after it is `/`.
#
# The GNU banner gate of 005 applies here too: the cases that actually run find
# are skipped loudly on a box whose `find` is not GNU findutils.
#
# Every child sets its own stdin explicitly (`</dev/null`): ktests gives a test
# child the terminal in `--mode single` and /dev/null in the threaded mode.
# Children get `timeout 60` — a cold source of the unit costs ~1 s idle and ~4 s
# with the runner at 8 workers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tfind.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for TFind (P0)"

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

kt_test_start "the skeleton sentinel \`__TFIND_PENDING__\` is GONE from the source"
if bad="$(grep -n '__TFIND_PENDING__' "$UNIT")"; then
    kt_test_fail "the red-first skeleton is still in place: ${bad//$'\n'/ | }"
else
    kt_test_pass "no sentinel — every member has a real body"
fi

kt_test_start "the CONSTRUCTOR calls \`parent.constructor find\`, never \`inherited\` (§2.1)"
# The Pascal front-end rewrites `inherited` in a constructor to
# `parent.constructor "$@"`, forwarding the descendant's own arguments: TUtil
# would get cmd=START and every start point would be emitted twice.
ctor="$(sed -n '/^TFind.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor find"* && "$ctor" != *inherited* ]]; then
    kt_test_pass "explicit \`parent.constructor find\`, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:200}"
fi

kt_test_start "the DESTRUCTOR frees \`\${inst}_paths\` and then chains with \`inherited\`"
dtor="$(sed -n '/^TFind.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'unset -v "${__inst__}_paths"'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "own array first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:200}"
fi

kt_test_start "the \`type\` regex is held in a VARIABLE and applied with \`[[ =~ \$re ]]\` (§6)"
if grep -q 'bcdflps' "$UNIT" && grep -q '=~ \$' "$UNIT"; then
    kt_test_pass "\`^[bcdflps](,[bcdflps])*\$\` in a variable, matched with \`[[ =~ \$re ]]\`"
else
    kt_test_fail "the regex or the \`[[ =~ \$var ]]\` form is missing"
fi

kt_test_start "the depths are emitted from \`\$__KK_INT\`, never from the property (§2.2, §6)"
# `-maxdepth +1` is the TOOL's rc 1, so the wrapper MUST normalise.
body="$(sed -n '/^TFind.buildArgv()/,/^}/p' "$UNIT")"
if [[ "$body" == *'kk.isInt'* && "$body" == *'__KK_INT'* \
      && "$body" != *'-maxdepth" "$maxDepth"'* && "$body" != *'-mindepth" "$minDepth"'* ]]; then
    kt_test_pass "kk.isInt + \$__KK_INT; the raw property never reaches the argv"
else
    kt_test_fail "buildArgv body: ${body:0:300}"
fi

kt_test_start "the builder never emits a \`--\` word (§1.1 — it cannot rescue a start point)"
if bad="$(grep -nE '^[^#]*\+=\(.*[^-]--[^-]' "$UNIT")"; then
    kt_test_fail "a \`--\` is appended somewhere: ${bad//$'\n'/ | }"
else
    kt_test_pass "no \`--\` in any argv append"
fi

kt_test_start "the start-point class is \`[-!\\(]*\`, not the NEGATED \`[!-(]*\` (§6, NIT 18)"
# Comment lines are stripped first: this file's own prose names the wrong
# spelling, and the check is about CODE.
code="$(grep -v '^[[:space:]]*#' "$UNIT")"
if [[ "$code" == *'== [-!\(]*'* && "$code" != *'[!-(]*'* ]]; then
    kt_test_pass "the \`-\` stays first in the class, so \`!\` is a literal"
else
    kt_test_fail "the class is spelled wrong: $(printf '%s\n' "$code" | grep -n '\[[-!]' | head -3 | tr '\n' '|')"
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
done < <(sed -n '/^class TFind : TUtil/,/^end/p' "$UNIT")
nvars=0
for _ in $declared; do nvars=$(( nvars + 1 )); done
if [[ -z "$clash" && $nvars -eq 9 ]]; then
    kt_test_pass "$nvars declared vars, none colliding with an inherited member"
else
    kt_test_fail "vars=$nvars shadowing:$clash declared:$declared"
fi

kt_test_start "the unit sources ONLY \`../tutil/tutil.sh\`"
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

kt_test_start "the unit registered \`__tfd_\` in \`TUTIL_OUT_PREFIXES\` at load (§2.6)"
seen=0
for p in "${TUTIL_OUT_PREFIXES[@]}"; do
    [[ "$p" == "__tfd_" ]] && seen=$(( seen + 1 ))
done
if [[ "$seen" == "1" && ${#TUTIL_OUT_PREFIXES[@]} -eq 5 ]]; then
    kt_test_pass "five prefixes, \`__tfd_\` exactly once"
else
    kt_test_fail "__tfd_ seen $seen time(s); registry = (${TUTIL_OUT_PREFIXES[*]})"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`find\` on PATH is GNU findutils"
FIND_VER="$(find --version 2>/dev/null | head -1 || :)"
if [[ "$FIND_VER" == "find (GNU findutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$FIND_VER"
else
    kt_test_pass "SKIP: non-GNU find ('${FIND_VER:-no banner}'); every case that runs find is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU find"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/sub"
printf 'x\n' > "$FX/a.txt"
printf 'x\n' > "$FX/sub/b.txt"

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

expect_clean "f.each: an instance that delivers records" '
N=0
cb() { N=$(( N + 1 )); }
TFind.new f "$FX"
f.print0 = 1
f.type = f
rc=0
f.each cb || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
f.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
f.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv TFind built" '
N=0
cb() { N=$(( N + 1 )); }
TFind.new f "$FX"
f.type = f
declare -a W=()
rc=0
f.argv W || rc=$?
[[ "$rc" == "0" && "$RESULT" == "4" ]] || { printf "words=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
TPipe.each cb -- "${W[@]}" || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
f.delete'

expect_clean "form 2 with \`TFind.byName\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
rc=0
TPipe.each cb -- TFind.byName "a.txt" "$FX" || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "1" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\`" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
rc=0
TFind.byName "*.txt" "$FX" | TPipe.each cb || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "every func sink on an instance that delivers" '
TFind.new f "$FX"
f.print0 = 1
f.type = f
declare -a A=()
rc=0
f.toArray A || rc=$?
[[ "$rc" == "0" && "$RESULT" == "2" ]] || { printf "toArray=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
f.count || rc=$?
[[ "$RESULT" == "2" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
f.first || rc=$?
[[ -n "$RESULT" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
f.delete'

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
TFind.new f "$FX"
f.print0 = 1
f.type = f
rc=0
f.toList L || rc=$?
[[ "$RESULT" == "2" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "2" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
f.delete
L.delete'

expect_clean "a TOOL ERROR (a missing start point, raw 1) — rc 1, the child survives" '
N=0
cb() { N=$(( N + 1 )); }
TFind.new f "$FX/no_such_dir"
f.print0 = 1
rc=0
f.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
f.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
f.delete'

expect_clean "PARTIAL failure (a missing start point among good ones) — rc 1, records KEPT" '
TFind.new f "$FX" "$FX/no_such_dir"
f.print0 = 1
declare -a A=()
rc=0
f.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "${#A[@]}" ]] || { printf "RESULT=%s kept=%s\n" "$RESULT" "${#A[@]}" >&2; exit 8; }
(( ${#A[@]} > 0 )) || { printf "kept=%s\n" "${#A[@]}" >&2; exit 7; }
f.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
f.delete'

expect_clean "a REFUSED build (a start point beginning with \`-\`) — rc 2, nothing runs, no abort" '
N=0
cb() { N=$(( N + 1 )); }
TFind.new f "-weird"
rc=0
f.each cb || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
f.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s (nothing ran, so it must still be -1)\n" "$RESULT" >&2; exit 7; }
f.delete'

expect_clean "a REFUSED build (\`print0\` + an action extra) — rc 2 from every runner" '
TFind.new f "$FX"
f.print0 = 1
f.addArg -delete
declare -a A=( stale )
rc=0; f.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; f.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; f.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
f.delete'

expect_clean "an EMPTY \`cmd\` — rc 2 from every runner, no abort" '
TFind.new f "$FX"
f.cmd = ""
declare -a A=( stale )
rc=0; f.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; f.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; f.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
f.delete'

expect_clean "a bad \`type\` and a bad \`maxDepth\` — rc 2, no abort" '
TFind.new f "$FX"
f.type = x
rc=0
f.count || rc=$?
[[ "$rc" == "2" ]] || { printf "type rc=%s\n" "$rc" >&2; exit 9; }
TFind.new f2 "$FX"
f2.maxDepth = -1
rc=0
f2.count || rc=$?
[[ "$rc" == "2" ]] || { printf "depth rc=%s\n" "$rc" >&2; exit 8; }
f.delete
f2.delete'

expect_clean "\`TFind.byName\` with no start point — rc 2, no abort, nothing printed" '
rc=0
out="$(TFind.byName "*.txt" </dev/null)" || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
TFind.new f "$FX"
f.name = "a.txt"
rc=0
out="$(f.run)" || rc=$?
[[ "$out" == "$FX/a.txt" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
f.run > /dev/null || rc=$?
f.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
f.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
TFind.new f "$FX"
f.delete
declare -p f_paths 2>/dev/null && { printf "f_paths survived\n" >&2; exit 9; }
declare -p f_args  2>/dev/null && { printf "f_args survived\n" >&2; exit 8; }
:'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
TFind.new f "$FX"
f.print0 = 1
f.type = f
n="$(f.count)"
[[ "$n" == "2" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
f.delete'

expect_clean "\`paths\` with no argument is find's own \`.\` — it runs in the child's cwd" '
cd "$FX"
TFind.new f x
f.paths
f.print0 = 1
f.type = f
declare -a A=()
rc=0
f.toArray A || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "${#A[@]}" == "2" ]] || { printf "n=%s\n" "${#A[@]}" >&2; exit 8; }
case "${A[0]}" in ./*) : ;; *) printf "rec=%s\n" "${A[0]}" >&2; exit 7 ;; esac
f.delete'

# D6 final Q9: `subshellOk` is TUtil's, inherited unchanged, and it reaches
# TPipe as the `-s` flag through two frames of wrapper. The case asserts BOTH
# directions: silent with the property set (the child's stderr must be empty),
# and the verbatim TPipe warning without it.
expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through TFind" '
TFind.new f "$FX"
f.print0 = 1
f.type = f
f.subshellOk = 1
declare -a A=()
n="$(f.toArray A)"
[[ "$n" == "2" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
f.delete
TFind.new f2 "$FX"
f2.print0 = 1
f2.type = f
declare -a A2=()
w="$( { f2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
f2.delete'

if tcase "F12: an UNGUARDED sink call with rc 1 aborts a \`set -eu\` caller (the documented rule)"; then
    # Two children, the same call: the unguarded one must die before its
    # `printf`, the guarded one must read rc 1 and carry on. This is the caller
    # rule, not a defect — every sink call in these tests is `|| rc=$?`.
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
TFind.new f "$FX/no_such_dir"
f.count
printf NOTREACHED' 2>/dev/null </dev/null)"; urc=$?
    guarded="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
TFind.new f "$FX/no_such_dir"
rc=0
f.count || rc=$?
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

# tf_dbg COMMAND... — run it with the switch on and SPLIT stderr: TF_N/TF_1 are
# OUR lines (kk.debug prints `Error: …` / `Warning: …`), TOOL_N is find's own
# `find: …`, which is the tool's stderr and passes through by design.
TF_RC=0; TF_N=0; TF_1=''; TOOL_N=0
tf_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TF_RC=$?
    VERBOSE_KKLASS=
    TF_N=0; TOOL_N=0; TF_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TF_N=$(( TF_N + 1 ))
                if [[ -z "$TF_1" ]]; then TF_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

# quiet_rc COMMAND... — the same call with the switch OFF: QRC and the stderr we
# produced (find's own lines are filtered out; they are not ours to suppress).
QRC=0; QOURS=0
quiet_rc() {
    : > "$ERRF"
    "$@" >/dev/null 2>"$ERRF"
    QRC=$?
    QOURS=0
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
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
    tf_dbg "$@"
    local n="$TF_N" first="$TF_1" drc="$TF_RC"
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
    tf_dbg "$@"
    if [[ "$TF_RC" == "$want" && $TF_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N first='$TF_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

TFind.new dOk   "$FX"                          # rc 0
dOk.print0 = 1
TFind.new dMiss "$FX" "$FX/no_such_dir"        # raw 1, partial
dMiss.print0 = 1
TFind.new dGone "$FX/no_such_dir"              # raw 1, nothing
TFind.new dSP   '-weird'                       # buildArgv rc 2: start point
TFind.new dEmpty ''                            # buildArgv rc 2: empty start point
TFind.new dTy   "$FX"                          # buildArgv rc 2: type
dTy.type = x
TFind.new dDep  "$FX"                          # buildArgv rc 2: depth
dDep.maxDepth = -1
TFind.new dAct  "$FX"                          # buildArgv rc 2: print0 + action
dAct.print0 = 1
dAct.addArg -exec true '{}' ';'
TFind.new dCmd  "$FX"
dCmd.cmd = ''
TFind.new dNewer "$FX"                         # raw 1, fatal
dNewer.newer = "$FX/no_such_ref"

check_one "rc 2: a start point beginning with \`-\` — one line, through \`each\`"  2 "start point" dSP.each cb_nul
check_one "rc 2: a start point beginning with \`-\` — one line, through \`count\`" 2 "start point" dSP.count
check_one "rc 2: an EMPTY start point — one line"                                  2 "start point" dEmpty.count
check_one "rc 2: a bad \`type\` — one line"                                        2 "type"        dTy.count
check_one "rc 2: a negative \`maxDepth\` — one line"                               2 "maxDepth"    dDep.count
check_one "rc 2: \`print0\` + an action extra — one line"                          2 "print0"      dAct.count
check_one "rc 2: an empty \`cmd\` — one line"                                      2 "cmd"         dCmd.count
check_one "rc 2: \`TFind.byName\` with no start point — one line"                  2 "byName"      TFind.byName '*.txt'
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                                   2 "output array" dOk.toArray RESULT
check_one "rc 2: \`toArray __tfd_x\` — one line (the \`__tfd_\` prefix, §2.6)" \
                                                                                   2 "output array" dOk.toArray __tfd_x
check_one "rc 2: \`toArray TUTIL_OUT_PREFIXES\` — one line (the registry's NAME, §2.6)" \
                                                                                   2 "output array" dOk.toArray TUTIL_OUT_PREFIXES

check_one "find raw 1 (a missing start point among good ones) — rc 1 and one line" \
                                                                                   1 "find exited 1" dMiss.count
check_one "find raw 1 (the only start point missing) — rc 1 and one line"           1 "find exited 1" dGone.count
check_one "find raw 1 (\`newer\` on a missing file, fatal) — rc 1 and one line"     1 "find exited 1" dNewer.count

check_silent "rc 0: a successful run says NOTHING"                                 0 dOk.count
check_silent "rc 0: \`each\` on records says NOTHING"                              0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on records says NOTHING"                           0 dOk.toArray DBG_ARR
check_silent "rc 0: \`TFind.byName\` that succeeded says NOTHING"                  0 TFind.byName 'a.txt' "$FX"

if tcase "the \`find exited\` line names TFind, and find's OWN line is left alone"; then
    tf_dbg dGone.count
    if [[ "$TF_N" == "1" && "$TF_1" == *"TFind"* && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "ours: ${TF_1:0:60} | find's: $TOOL_N line(s) untouched"
    else
        kt_test_fail "ourLines=$TF_N first='$TF_1' toolLines=$TOOL_N"
    fi
fi

kt_test_start "the registry survived every refusal above and still holds five prefixes"
if [[ ${#TUTIL_OUT_PREFIXES[@]} -eq 5 ]]; then
    kt_test_pass "TUTIL_OUT_PREFIXES = (${TUTIL_OUT_PREFIXES[*]})"
else
    kt_test_fail "registry = (${TUTIL_OUT_PREFIXES[*]})"
fi

# ===========================================================================
kt_test_section "3. a Windows-spelled start point (§1.1, §2.1, F12)"
# ===========================================================================

# `C:\…\tree` is accepted by find under both bashes; the start point's own
# spelling survives as a PREFIX and every separator find appends after it is a
# forward slash (`C:\…\tree/a.txt`). Pinned that way, never as whole-record
# equality.
if tcase "F12: a \`C:\\…\` start point yields records with that PREFIX and \`/\` after it"; then
    if ! command -v cygpath >/dev/null 2>&1; then
        kt_test_pass "SKIP: no cygpath on this box"
    else
        WINFX="$(cygpath -w "$FX")"
        TFind.new fw "$WINFX"
        fw.print0 = 1
        fw.type = f
        declare -a WGOT=()
        rc=0; fw.toArray WGOT 2>/dev/null || rc=$?
        pref_ok=1
        slash_after=0
        for r in "${WGOT[@]}"; do
            [[ "$r" == "$WINFX"* ]] || pref_ok=0
            rest="${r#"$WINFX"}"
            [[ "$rest" == /* ]] && slash_after=$(( slash_after + 1 ))
        done
        if [[ $rc -eq 0 && ${#WGOT[@]} -eq 2 && "$pref_ok" == "1" && "$slash_after" -eq 2 \
              && "$WINFX" == *'\'* ]]; then
            kt_test_pass "2 records, all prefixed '$WINFX' and continuing with '/'"
        else
            kt_test_fail "rc=$rc n=${#WGOT[@]} prefixOk=$pref_ok slashAfter=$slash_after win='$WINFX' first='${WGOT[0]:-}'"
        fi
        fw.delete
    fi
fi

dOk.delete
dMiss.delete
dGone.delete
dSP.delete
dEmpty.delete
dTy.delete
dDep.delete
dAct.delete
dCmd.delete
dNewer.delete
