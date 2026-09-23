#!/bin/bash
# 006_Contract.sh — tsed P0: the kcl-wide contract (kcl/README.md §1) for TSed
# (tsed/PLAN.md §2.1–§2.7, §3 S13).
#
# What it pins:
#
#   source integrity  `bash -n`, no single-quoted printf format left open, no
#                     inline `$'\r'`, no `$this.` internal call, the skeleton
#                     sentinel gone, `parent.constructor sed` (never `inherited`
#                     in the constructor), the destructor freeing `_paths` AND
#                     `_exprs`, the five overridden sinks in the rc-PRESERVING
#                     spelling (the proc `each` too), no `var` shadowing an
#                     inherited member, no bookkeeping var for the derived `-b`
#                     (owner Q5), one `source` line, both registries extended.
#   set -eu           TSed from a script under `set -eu`, as an instance, through
#                     `s.each` and BOTH TPipe forms, on every outcome: records
#                     (rc 0), a sed error, a partial failure, a `q N` status, a
#                     refused build, a refused in-place sink, a refused `edit`.
#                     EVERY sink call in a child is guarded `|| rc=$?`.
#   §1.2 diagnostics  exactly ONE `kk.debug` line on every rc 2 path and on every
#                     "sed exited 1/2/4" path; NOTHING on rc 0 and NOTHING on a
#                     script's `q N` status with N outside {1, 2, 4, 127}; with
#                     the switch off, complete silence from us either way.
#   D6 final          `$(s.toArray A)` warns about the subshell; `subshellOk = 1`
#                     silences it.
#
# The GNU banner gate of 005 applies here too. Every child sets its own stdin
# (`</dev/null`) and runs under `timeout 60`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tsed.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for TSed (P0)"

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

kt_test_start "the skeleton sentinel \`__TSED_PENDING__\` is GONE from the source"
if bad="$(grep -n '__TSED_PENDING__' "$UNIT")"; then
    kt_test_fail "the red-first skeleton is still in place: ${bad//$'\n'/ | }"
else
    kt_test_pass "no sentinel — every member has a real body"
fi

kt_test_start "the CONSTRUCTOR calls \`parent.constructor sed\`, never \`inherited\`"
ctor="$(sed -n '/^TSed.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor sed"* && "$ctor" != *inherited* \
      && "$ctor" == *'sandbox=1'* && "$ctor" == *'expr="${1:-}"'* ]]; then
    kt_test_pass "explicit \`parent.constructor sed\`, sandbox=1, expr=\$1, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:300}"
fi

kt_test_start "the DESTRUCTOR frees \`_paths\` AND \`_exprs\`, then chains with \`inherited\`"
dtor="$(sed -n '/^TSed.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'"${__inst__}_paths"'* && "$dtor" == *'"${__inst__}_exprs"'* \
      && "$dtor" == *'unset -v'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "both arrays first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:200}"
fi

# thead §6 / ttail §2.1: a `func` body that merely ENDS on `inherited X "$@"`
# answers rc 0 where the base answered 1 (the compiled trailer replaces the rc).
kt_test_start "the four overridden func sinks use the rc-PRESERVING spelling"
bad=""
for m in toArray toList first count; do
    body="$(sed -n "/^TSed.$m()/,/^}/p" "$UNIT")"
    [[ "$body" == *"inherited $m \"\$@\" || "* ]] || bad+=" $m:no-guarded-inherited"
    [[ "$body" == *'kk._return "$__tsd_n"'* ]]     || bad+=" $m:no-saved-RESULT"
    [[ "$body" == *'return "$__tsd_rc"'* ]]        || bad+=" $m:no-rc-reraise"
    last="$(printf '%s\n' "$body" | grep -vE '^\}$' | tail -1)"
    case "$last" in
        *inherited*) bad+=" $m:ends-on-inherited" ;;
    esac
done
if [[ -z "$bad" ]]; then
    kt_test_pass "toArray / toList / first / count each capture the rc and re-raise it"
else
    kt_test_fail "$bad"
fi

kt_test_start "the overridden PROC \`each\` re-raises the rc and never answers RESULT"
body="$(sed -n '/^TSed.each()/,/^}/p' "$UNIT")"
last="$(printf '%s\n' "$body" | grep -vE '^\}$' | tail -1)"
if [[ "$body" == *'inherited each "$@" || '* && "$body" == *'return "$__tsd_rc"'* \
      && "$body" != *'kk._return'* && "$last" != *inherited* ]]; then
    kt_test_pass "\`inherited each \"\$@\" || rc=\$?; return \"\$rc\"\`"
else
    kt_test_fail "each body: ${body:0:300}"
fi

kt_test_start "the derived \`-b\` lives in buildArgv only — no bookkeeping var, \`binary\` never written (Q5)"
bav="$(sed -n '/^TSed.buildArgv()/,/^}/p' "$UNIT")"
if [[ "$bav" != *'binary='* && "$bav" == *'"$inPlace" == 1'* && "$bav" == *'"$nullData" == 1'* ]] \
   && ! grep -q '_binDerived' "$UNIT"; then
    kt_test_pass "\`-b\` from binary/inPlace/nullData; no \`binary=\` in the builder; no \`_binDerived\`"
else
    kt_test_fail "buildArgv body: ${bav:0:200}"
fi

kt_test_start "no \`var\` shadows a TUtil or kklass member name; eleven vars declared"
RESERVED=" cmd crlf nul _lastRc subshellOk buildArgv addArg clearArgs argv run each toArray toList first count lastRc mapRc property call parent delete "
clash=""
declared=""
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
        "var "*)
            name="${line#var }"
            name="${name%%[![:graph:]]*}"
            declared+=" $name"
            if [[ "$RESERVED" == *" $name "* ]]; then
                clash+=" $name"
            fi
            ;;
    esac
done < <(sed -n '/^class TSed : TUtil/,/^end/p' "$UNIT")
nvars=0
for _ in $declared; do nvars=$(( nvars + 1 )); done
if [[ -z "$clash" && $nvars -eq 11 ]]; then
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

kt_test_start "the unit registered \`__tsd_\` and \`_exprs\` at load, once each"
np=0; ns=0
for p in "${TUTIL_OUT_PREFIXES[@]}"; do [[ "$p" == "__tsd_" ]] && np=$(( np + 1 )); done
for p in "${TUTIL_OUT_SUFFIXES[@]}"; do [[ "$p" == "_exprs" ]] && ns=$(( ns + 1 )); done
if [[ "$np" == "1" && "$ns" == "1" ]]; then
    kt_test_pass "prefixes (${TUTIL_OUT_PREFIXES[*]}); suffixes (${TUTIL_OUT_SUFFIXES[*]})"
else
    kt_test_fail "__tsd_ x$np, _exprs x$ns"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`sed\` on PATH is GNU sed"
SED_VER="$(sed --version 2>/dev/null | head -1 || :)"
if [[ "$SED_VER" == "sed (GNU sed) "* ]]; then
    GNU_OK=1
    kt_test_pass "$SED_VER"
else
    kt_test_pass "SKIP: non-GNU sed ('${SED_VER:-no banner}'); every case that runs sed is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU sed"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf 'a1\nb2\nc3\n' > "$FX/f3.txt"

# ===========================================================================
kt_test_section "1. set -eu — the instance, \`s.each\` and BOTH TPipe forms"
# ===========================================================================

# expect_clean TITLE SNIPPET — a CHILD under `set -eu` with the unit freshly
# sourced; it must end rc 0, print exactly OK and write nothing to stderr.
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

expect_clean "s.each: an instance that delivers records" '
N=0
cb() { N=$(( N + 1 )); }
TSed.new s "s/a/A/" "$FX/f3.txt"
rc=0
s.each cb || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
s.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
s.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv TSed built" '
N=0
cb() { N=$(( N + 1 )); }
TSed.new s "s/a/A/" "$FX/f3.txt"
declare -a W=()
rc=0
s.argv W || rc=$?
[[ "$rc" == "0" && "$RESULT" == "6" ]] || { printf "words=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
TPipe.each cb -- "${W[@]}" || rc=$?
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
s.delete'

expect_clean "form 2 with \`TSed.edit\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
rc=0
TPipe.each cb -- TSed.edit "s/a/A/" "$FX/f3.txt" || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\` (edit and s.run)" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
rc=0
TSed.edit "s/a/A/" "$FX/f3.txt" | TPipe.each cb || rc=$?
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
TSed.new s "2p" "$FX/f3.txt"
s.quiet = 1
N=0
s.run | TPipe.each cb || rc=$?
[[ "$N" == "1" ]] || { printf "N2=%s\n" "$N" >&2; exit 8; }
s.delete'

expect_clean "every func sink on an instance that delivers" '
TSed.new s "s/a/A/" "$FX/f3.txt"
declare -a A=()
rc=0
s.toArray A || rc=$?
[[ "$rc" == "0" && "$RESULT" == "3" ]] || { printf "toArray=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
s.count || rc=$?
[[ "$RESULT" == "3" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
s.first || rc=$?
[[ "$RESULT" == "A1" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 6; }
s.delete'

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
TSed.new s "s/a/A/" "$FX/f3.txt"
rc=0
s.toList L || rc=$?
[[ "$RESULT" == "3" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "3" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
s.delete
L.delete'

expect_clean "a sed ERROR (the only file missing, raw 2) — each rc 1, the child survives" '
N=0
cb() { N=$(( N + 1 )); }
TSed.new s "s/a/A/" "$FX/no_such.txt"
rc=0
s.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
s.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
s.delete'

expect_clean "PARTIAL failure (a missing file among good ones) — rc 1, records KEPT" '
TSed.new s "s/a/A/" "$FX/f3.txt" "$FX/no_such.txt"
declare -a A=()
rc=0
s.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "3" && "${#A[@]}" == "3" ]] || { printf "RESULT=%s kept=%s\n" "$RESULT" "${#A[@]}" >&2; exit 8; }
s.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
s.delete'

expect_clean "a script q N status (\`2q7\`) — count rc 1 RESULT 2, lastRc 7, no abort" '
TSed.new s "2q7" "$FX/f3.txt"
rc=0
s.count || rc=$?
[[ "$rc" == "1" && "$RESULT" == "2" ]] || { printf "rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
s.lastRc
[[ "$RESULT" == "7" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
s.delete'

expect_clean "a REFUSED build (no script) — rc 2 from each/toArray/count/run, lastRc -1" '
N=0
cb() { N=$(( N + 1 )); }
TSed.new s "" "$FX/f3.txt"
rc=0; s.each cb || rc=$?
[[ "$rc" == "2" && "$N" == "0" ]] || { printf "each rc=%s N=%s\n" "$rc" "$N" >&2; exit 9; }
declare -a A=( stale )
rc=0; s.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" && "${A[0]}" == "stale" ]] || { printf "toArray rc=%s\n" "$rc" >&2; exit 8; }
rc=0; s.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 7; }
rc=0; s.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 6; }
s.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 5; }
s.delete'

expect_clean "in-place: every sink rc 2, the file untouched; \`run\` then edits it" '
cp "$FX/f3.txt" "$FX/c_ip.txt"
N=0
cb() { N=$(( N + 1 )); }
TSed.new s "s/a/A/" "$FX/c_ip.txt"
s.inPlace = 1
declare -a A=()
TSed.new t "p"
rc=0; s.each cb || rc=$?;    [[ "$rc" == "2" ]] || exit 9
rc=0; s.toArray A || rc=$?;  [[ "$rc" == "2" ]] || exit 8
rc=0; s.toList t || rc=$?;   [[ "$rc" == "2" ]] || exit 7
rc=0; s.first || rc=$?;      [[ "$rc" == "2" ]] || exit 6
rc=0; s.count || rc=$?;      [[ "$rc" == "2" ]] || exit 5
printf -v W0 "a1\nb2\nc3"
printf -v W1 "A1\nb2\nc3"
[[ "$(<"$FX/c_ip.txt")" == "$W0" ]] || exit 4
rc=0; s.run || rc=$?
[[ "$rc" == "0" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 3; }
[[ "$(<"$FX/c_ip.txt")" == "$W1" ]] || exit 2
s.delete
t.delete'

expect_clean "a denied extra (\`addArg -i\`) — rc 2 from every runner, no abort" '
TSed.new s "s/a/A/" "$FX/f3.txt"
s.addArg -i
declare -a A=( stale )
rc=0; s.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s\n" "$rc" >&2; exit 9; }
rc=0; s.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; s.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
s.delete'

expect_clean "an EMPTY \`cmd\` — rc 2 from every runner, no abort" '
TSed.new s "p" "$FX/f3.txt"
s.cmd = ""
rc=0; s.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 9; }
rc=0; s.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 8; }
s.delete'

expect_clean "\`TSed.edit\` with no path — rc 2, no abort, nothing printed" '
rc=0
out="$(TSed.edit "s/a/A/" </dev/null)" || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }'

expect_clean "\`TSed.edit\` refused by the sandbox — rc 1, no abort" '
rc=0
TSed.edit "1e true" "$FX/f3.txt" 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
TSed.new s "2p" "$FX/f3.txt"
s.quiet = 1
rc=0
out="$(s.run)" || rc=$?
[[ "$out" == "b2" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
s.run > /dev/null || rc=$?
s.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
s.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
TSed.new s "p" "$FX/f3.txt"
s.addExpr x
s.delete
declare -p s_paths 2>/dev/null && { printf "s_paths survived\n" >&2; exit 9; }
declare -p s_exprs 2>/dev/null && { printf "s_exprs survived\n" >&2; exit 8; }
declare -p s_args  2>/dev/null && { printf "s_args survived\n" >&2; exit 7; }
:'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
TSed.new s "s/a/A/" "$FX/f3.txt"
n="$(s.count)"
[[ "$n" == "3" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
f="$(s.first)"
[[ "$f" == "A1" ]] || { printf "first=%s\n" "$f" >&2; exit 8; }
s.delete'

expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through TSed" '
TSed.new s "s/a/A/" "$FX/f3.txt"
s.subshellOk = 1
declare -a A=()
n="$(s.toArray A)"
[[ "$n" == "3" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
s.delete
TSed.new s2 "s/a/A/" "$FX/f3.txt"
declare -a A2=()
w="$( { s2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
s2.delete'

if tcase "S13: an UNGUARDED sink call with rc 1 aborts a \`set -eu\` caller (the documented rule)"; then
    out="$(FX="$FX" UNIT="$UNIT" timeout 60 "$BASH" -c 'set -eu
source "$UNIT"
TSed.new s "p" "$FX/no_such.txt"
s.count 2>/dev/null
printf NOTREACHED' 2>/dev/null </dev/null)"; urc=$?
    guarded="$(FX="$FX" UNIT="$UNIT" timeout 60 "$BASH" -c 'set -eu
source "$UNIT"
TSed.new s "p" "$FX/no_such.txt"
rc=0
s.count 2>/dev/null || rc=$?
printf "%s" "$rc"' 2>/dev/null </dev/null)"; grc=$?
    if [[ $urc -ne 0 && -z "$out" && $grc -eq 0 && "$guarded" == "1" ]]; then
        kt_test_pass "unguarded: the caller died (rc $urc, nothing printed); guarded: rc 1 and it goes on"
    else
        kt_test_fail "unguarded rc=$urc out='$out'; guarded rc=$grc out='$guarded'"
    fi
fi

# ===========================================================================
kt_test_section "2. the debug switch — one line per rc 2 / sed-error path, silence otherwise"
# ===========================================================================

TS_RC=0; TS_N=0; TS_1=''; TOOL_N=0
ts_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TS_RC=$?
    VERBOSE_KKLASS=
    TS_N=0; TOOL_N=0; TS_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TS_N=$(( TS_N + 1 ))
                if [[ -z "$TS_1" ]]; then TS_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

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

check_one() {   # check_one TITLE WANT_RC WANT_SUBSTR COMMAND...
    local title="$1" want="$2" sub="$3"; shift 3
    if ! tcase "$title"; then
        return 0
    fi
    ts_dbg "$@"
    local n="$TS_N" first="$TS_1" drc="$TS_RC"
    quiet_rc "$@"
    if [[ "$drc" == "$want" && $n -eq 1 && "$first" == *"$sub"* \
          && "$QRC" == "$want" && "$QOURS" -eq 0 ]]; then
        kt_test_pass "rc $want, one line: ${first:0:74}"
    else
        kt_test_fail "debug rc=$drc lines=$n first='$first' / quiet rc=$QRC ourLines=$QOURS"
    fi
}

check_silent() {   # check_silent TITLE WANT_RC COMMAND...
    local title="$1" want="$2"; shift 2
    if ! tcase "$title"; then
        return 0
    fi
    ts_dbg "$@"
    if [[ "$TS_RC" == "$want" && $TS_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TS_RC ourLines=$TS_N first='$TS_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

TSed.new dOk    's/a/A/' "$FX/f3.txt"
TSed.new dNone  ''       "$FX/f3.txt"
TSed.new dIpNo  's/a/A/'
dIpNo.inPlace = 1
TSed.new dSuf   's/a/A/' "$FX/f3.txt"
dSuf.backupSuffix = .bak
TSed.new dStar  's/a/A/' "$FX/f3.txt"
dStar.inPlace = 1
dStar.backupSuffix = '*'
TSed.new dDeny  's/a/A/' "$FX/f3.txt"
dDeny.addArg --expression=p
TSed.new dDash  's/a/A/' "$FX/f3.txt"
dDash.addArg --
TSed.new dCmd   's/a/A/' "$FX/f3.txt"
dCmd.cmd = ''
TSed.new dIp    's/a/A/' "$FX/f3.txt"
dIp.inPlace = 1
TSed.new dDbg   's/a/A/' "$FX/f3.txt"
dDbg.addArg --debug
TSed.new dMiss  's/a/A/' "$FX/f3.txt" "$FX/no_such.txt"
TSed.new dBad   's/a'    "$FX/f3.txt"
TSed.new dNoF   ''       "$FX/f3.txt"
dNoF.scriptFile = "$FX/no_such.sed"
TSed.new dQ1    '2q1'    "$FX/f3.txt"
TSed.new dQ7    '2q7'    "$FX/f3.txt"
TSed.new dQ3    '1Q3'    "$FX/f3.txt"
TSed.new dQ256  '1q256'  "$FX/f3.txt"

check_one "rc 2: no script — one line, through \`each\`"                  2 "no script"    dNone.each cb_nul
check_one "rc 2: no script — one line, through \`count\`"                 2 "no script"    dNone.count
check_one "rc 2: no script — one line, through \`run\`"                   2 "no script"    dNone.run
check_one "rc 2: \`inPlace\` with no path — one line"                     2 "inPlace"      dIpNo.run
check_one "rc 2: \`backupSuffix\` without \`inPlace\` — one line"         2 "backupSuffix" dSuf.count
check_one "rc 2: \`backupSuffix = '*'\` — one line"                       2 "backupSuffix" dStar.run
check_one "rc 2: a denied extra (\`--expression=p\`) — one line"          2 "expr"         dDeny.count
check_one "rc 2: \`--\` among the extras — one line"                      2 "ends sed's options" dDash.count
check_one "rc 2: an empty \`cmd\` — one line"                             2 "cmd"          dCmd.count
check_one "rc 2: \`count\` with \`inPlace = 1\` — one line"               2 "in-place"     dIp.count
check_one "rc 2: \`each\` with \`inPlace = 1\` — one line"                2 "in-place"     dIp.each cb_nul
check_one "rc 2: \`first\` with \`--debug\` in the extras — one line"     2 "--debug"      dDbg.first
check_one "rc 2: \`TSed.edit\` with no path — one line"                   2 "TSed.edit"    TSed.edit 's/a/A/'
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                           2 "output array" dOk.toArray RESULT
check_one "rc 2: \`toArray __tsd_x\` — one line (the \`__tsd_\` prefix)"  2 "output array" dOk.toArray __tsd_x
check_one "rc 2: \`toArray dOk_exprs\` — one line (the \`_exprs\` suffix)" 2 "output array" dOk.toArray dOk_exprs
check_one "rc 2: \`toArray TUTIL_OUT_SUFFIXES\` — one line (the registry's NAME)" \
                                                                           2 "output array" dOk.toArray TUTIL_OUT_SUFFIXES

check_one "sed raw 2 (a missing file among good ones) — rc 1 and one line" 1 "sed exited 2" dMiss.count
check_one "sed raw 1 (a bad script) — rc 1 and one line"                   1 "sed exited 1" dBad.count
check_one "sed raw 4 (a missing \`-f\` script) — rc 1 and one line"       1 "sed exited 4" dNoF.count
check_one "a script's \`2q1\` — rc 1 and one line, worded to say it may be the script's" \
                                                                           1 "or the script's q/Q 1" dQ1.count

check_silent "rc 0: a successful \`count\` says NOTHING"                  0 dOk.count
check_silent "rc 0: \`each\` on records says NOTHING"                     0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on records says NOTHING"                  0 dOk.toArray DBG_ARR
check_silent "rc 0: \`run\` says NOTHING"                                 0 dOk.run
check_silent "rc 0: \`TSed.edit\` that succeeded says NOTHING"            0 TSed.edit 's/a/A/' "$FX/f3.txt"
check_silent "a script's \`2q7\` — rc 1 and SILENT (N outside {1,2,4,127})" 1 dQ7.count
check_silent "a script's \`1Q3\` — rc 1 and SILENT"                       1 dQ3.count
check_silent "a script's \`1q256\` wraps to 0 — rc 0 and SILENT"          0 dQ256.count

if tcase "the \`q N\` status reaches \`lastRc\` RAW (7 and 3) while the member answers 1"; then
    dQ7.count >/dev/null 2>&1; dQ7.lastRc; a="$RESULT"
    dQ3.count >/dev/null 2>&1; dQ3.lastRc; b="$RESULT"
    if [[ "$a" == "7" && "$b" == "3" ]]; then
        kt_test_pass "lastRc 7 and 3"
    else
        kt_test_fail "lastRc '$a' and '$b'"
    fi
fi

for d in dOk dNone dIpNo dSuf dStar dDeny dDash dCmd dIp dDbg dMiss dBad dNoF dQ1 dQ7 dQ3 dQ256; do
    "$d".delete
done
