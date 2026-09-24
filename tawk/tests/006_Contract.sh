#!/bin/bash
# 006_Contract.sh — tawk P0: the kcl-wide contract (kcl/README.md §1) for TAwk
# (tawk/PLAN.md §2.1–§2.7, §3 A13).
#
# What it pins:
#
#   source integrity  `bash -n`, no single-quoted printf format left open, no
#                     inline `$'\r'`, no `$this.` internal call, the skeleton
#                     sentinel gone, `parent.constructor gawk` (never
#                     `inherited` in the constructor), the destructor freeing
#                     `_paths`, `_progs`, `_vnames` AND `_vvals`, the five
#                     overridden sinks in the rc-PRESERVING spelling (the proc
#                     `each` too), no `var` shadowing an inherited member, no
#                     bookkeeping var for the derived BINMODE, the inplace
#                     include only by its ABSOLUTE path, no env route, one
#                     `source` line, both registries extended.
#   set -eu           TAwk from a script under `set -eu`, as an instance, through
#                     `a.each` and BOTH TPipe forms, on every outcome: records
#                     (rc 0), a gawk error, the fatal missing file, an `exit N`
#                     status, a refused build, a refused in-place sink, a
#                     refused `apply`, a refused `setVar`. EVERY sink call in a
#                     child is guarded `|| rc=$?`.
#   §1.2 diagnostics  exactly ONE `kk.debug` line on every rc 2 path and on every
#                     "gawk exited 1/2" path; NOTHING on rc 0 and NOTHING on a
#                     program's `exit N` with N outside {1, 2, 127}; with the
#                     switch off, complete silence from us either way.
#   D6 final          `$(a.toArray A)` warns about the subshell; `subshellOk = 1`
#                     silences it.
#
# The GNU banner gate of 005 applies here too. Stdin is closed for the whole
# file; every child sets its own stdin (`</dev/null`) and runs under `timeout 60`.

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
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for TAwk (P0)"

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

kt_test_start "the skeleton sentinel \`__TAWK_PENDING__\` is GONE from the source"
if bad="$(grep -n '__TAWK_PENDING__' "$UNIT")"; then
    kt_test_fail "the red-first skeleton is still in place: ${bad//$'\n'/ | }"
else
    kt_test_pass "no sentinel — every member has a real body"
fi

kt_test_start "the CONSTRUCTOR calls \`parent.constructor gawk\`, never \`inherited\`"
ctor="$(sed -n '/^TAwk.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor gawk"* && "$ctor" != *inherited* \
      && "$ctor" == *'sandbox=1'* && "$ctor" == *'program="${1:-}"'* \
      && "$ctor" == *'"${__inst__}_progs=()"'* && "$ctor" == *'"${__inst__}_vnames=()"'* \
      && "$ctor" == *'"${__inst__}_vvals=()"'* && "$ctor" == *'declare -ga'* ]]; then
    kt_test_pass "explicit \`parent.constructor gawk\`, sandbox=1, program=\$1, four indexed arrays, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:400}"
fi

kt_test_start "the DESTRUCTOR frees \`_paths\`, \`_progs\`, \`_vnames\`, \`_vvals\`, then chains with \`inherited\`"
dtor="$(sed -n '/^TAwk.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'"${__inst__}_paths"'* && "$dtor" == *'"${__inst__}_progs"'* \
      && "$dtor" == *'"${__inst__}_vnames"'* && "$dtor" == *'"${__inst__}_vvals"'* \
      && "$dtor" == *'unset -v'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "the four arrays first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:300}"
fi

kt_test_start "the four overridden func sinks use the rc-PRESERVING spelling"
bad=""
for m in toArray toList first count; do
    body="$(sed -n "/^TAwk.$m()/,/^}/p" "$UNIT")"
    [[ "$body" == *"inherited $m \"\$@\" || "* ]] || bad+=" $m:no-guarded-inherited"
    [[ "$body" == *'kk._return "$__taw_n"'* ]]     || bad+=" $m:no-saved-RESULT"
    [[ "$body" == *'return "$__taw_rc"'* ]]        || bad+=" $m:no-rc-reraise"
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
body="$(sed -n '/^TAwk.each()/,/^}/p' "$UNIT")"
last="$(printf '%s\n' "$body" | grep -vE '^\}$' | tail -1)"
if [[ "$body" == *'inherited each "$@" || '* && "$body" == *'return "$__taw_rc"'* \
      && "$body" != *'kk._return'* && "$last" != *inherited* ]]; then
    kt_test_pass "\`inherited each \"\$@\" || rc=\$?; return \"\$rc\"\`"
else
    kt_test_fail "each body: ${body:0:300}"
fi

kt_test_start "the derived BINMODE lives in buildArgv only — no bookkeeping var, \`binary\` never written"
bav="$(sed -n '/^TAwk.buildArgv()/,/^}/p' "$UNIT")"
if [[ "$bav" != *'binary='* && "$bav" == *'"$inPlace" == 1'* && "$bav" == *'"$nullData" == 1'* \
      && "$bav" == *'BINMODE=3'* ]] && ! grep -q '_binDerived' "$UNIT"; then
    kt_test_pass "BINMODE=3 from binary/inPlace/nullData; no \`binary=\` in the builder; no \`_binDerived\`"
else
    kt_test_fail "buildArgv body: ${bav:0:200}"
fi

kt_test_start "the inplace extension is included by its ABSOLUTE path only; no env / ENVIRON route (Q2)"
if [[ "$bav" == *'-i /usr/share/awk/inplace.awk'* ]] \
   && ! grep -nE '(-i|--include)[= ]+inplace([^.]|$)' <<< "$bav" >/dev/null \
   && [[ "$bav" != *ENVIRON* && "$bav" != *' env '* ]]; then
    kt_test_pass "\`-i /usr/share/awk/inplace.awk\`; never \`-i inplace\`; no ENVIRON prologue"
else
    kt_test_fail "buildArgv body: ${bav:0:300}"
fi

kt_test_start "no \`var\` shadows a TUtil or kklass member name; nine vars declared"
RESERVED=" cmd crlf nul _lastRc subshellOk buildArgv addArg clearArgs argv run each toArray toList first count lastRc mapRc property call parent delete "
clash=""
declared=""
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
        "var "*)
            name="${line#var }"
            name="${name#"${name%%[![:space:]]*}"}"
            name="${name%%[![:graph:]]*}"
            declared+=" $name"
            if [[ "$RESERVED" == *" $name "* ]]; then
                clash+=" $name"
            fi
            ;;
    esac
done < <(sed -n '/^class TAwk : TUtil/,/^end/p' "$UNIT")
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

kt_test_start "the unit registered \`__taw_\` and \`_progs _vnames _vvals\` at load, once each"
np=0; n1=0; n2=0; n3=0
for p in "${TUTIL_OUT_PREFIXES[@]}"; do [[ "$p" == "__taw_" ]] && np=$(( np + 1 )); done
for p in "${TUTIL_OUT_SUFFIXES[@]}"; do
    [[ "$p" == "_progs" ]]  && n1=$(( n1 + 1 ))
    [[ "$p" == "_vnames" ]] && n2=$(( n2 + 1 ))
    [[ "$p" == "_vvals" ]]  && n3=$(( n3 + 1 ))
done
if [[ "$np$n1$n2$n3" == "1111" ]]; then
    kt_test_pass "prefixes (${TUTIL_OUT_PREFIXES[*]}); suffixes (${TUTIL_OUT_SUFFIXES[*]})"
else
    kt_test_fail "__taw_ x$np, _progs x$n1, _vnames x$n2, _vvals x$n3"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`gawk\` on PATH is GNU Awk"
AWK_VER="$(timeout 20 gawk --version 2>/dev/null </dev/null | head -1 || :)"
if [[ "$AWK_VER" == "GNU Awk "* ]]; then
    GNU_OK=1
    kt_test_pass "$AWK_VER"
else
    kt_test_pass "SKIP: non-GNU awk ('${AWK_VER:-no banner}'); every case that runs gawk is skipped"
fi

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU awk"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf 'a 1\nb 2\nc 3\n' > "$FX/f3.txt"

# ===========================================================================
kt_test_section "1. set -eu — the instance, \`a.each\` and BOTH TPipe forms"
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

expect_clean "a.each: an instance that delivers records" '
N=0
cb() { N=$(( N + 1 )); }
TAwk.new a "{print \$2}" "$FX/f3.txt"
rc=0
a.each cb || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
a.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
a.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv TAwk built" '
N=0
cb() { N=$(( N + 1 )); }
TAwk.new a "{print \$2}" "$FX/f3.txt"
declare -a W=()
rc=0
a.argv W || rc=$?
[[ "$rc" == "0" && "$RESULT" == "6" ]] || { printf "words=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
TPipe.each cb -- "${W[@]}" || rc=$?
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
a.delete'

expect_clean "form 2 with \`TAwk.apply\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
rc=0
TPipe.each cb -- TAwk.apply "{print \$2}" "$FX/f3.txt" || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\` (apply and a.run)" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
rc=0
TAwk.apply "{print \$2}" "$FX/f3.txt" | TPipe.each cb || rc=$?
[[ "$N" == "3" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }
TAwk.new a "NR==2" "$FX/f3.txt"
N=0
a.run | TPipe.each cb || rc=$?
[[ "$N" == "1" ]] || { printf "N2=%s\n" "$N" >&2; exit 8; }
a.delete'

expect_clean "every func sink on an instance that delivers" '
TAwk.new a "{print \$2}" "$FX/f3.txt"
declare -a A=()
rc=0
a.toArray A || rc=$?
[[ "$rc" == "0" && "$RESULT" == "3" ]] || { printf "toArray=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
a.count || rc=$?
[[ "$RESULT" == "3" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
a.first || rc=$?
[[ "$RESULT" == "1" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 6; }
a.delete'

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
TAwk.new a "{print}" "$FX/f3.txt"
rc=0
a.toList L || rc=$?
[[ "$RESULT" == "3" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "3" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
a.delete
L.delete'

expect_clean "setVar: a value with a backslash, a newline and a leading @ arrives verbatim" '
TAwk.new a "BEGIN{printf \"%s\", x}"
printf -v v "@a%sb\nc" "\\"
[[ "${#v}" == "6" ]] || { printf "fixture v=%q\n" "$v" >&2; exit 10; }
a.setVar x "$v"
out="$(a.run)"
[[ "$out" == "$v" ]] || { printf "out=%q want=%q\n" "$out" "$v" >&2; exit 9; }
a.delete'

expect_clean "a refused \`setVar\` (a builtin name) — rc 2, nothing stored, no abort" '
TAwk.new a "BEGIN{print 1}"
rc=0
a.setVar length 1 || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
declare -n VN=a_vnames
[[ "${#VN[@]}" == "0" ]] || exit 8
a.delete'

expect_clean "a gawk ERROR (the only file missing, raw 2) — each rc 1, the child survives" '
N=0
cb() { N=$(( N + 1 )); }
TAwk.new a "{print}" "$FX/no_such.txt"
rc=0
a.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
a.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
a.delete'

expect_clean "the FATAL missing file in the middle — rc 1, the earlier records KEPT" '
TAwk.new a "{print}" "$FX/f3.txt" "$FX/no_such.txt" "$FX/f3.txt"
declare -a A=()
rc=0
a.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "3" && "${#A[@]}" == "3" ]] || { printf "RESULT=%s kept=%s\n" "$RESULT" "${#A[@]}" >&2; exit 8; }
a.lastRc
[[ "$RESULT" == "2" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
a.delete'

expect_clean "a program exit N status (\`exit 7\` on line 3) — count rc 1 RESULT 2, lastRc 7, no abort" '
TAwk.new a "NR==3{exit 7} {print}" "$FX/f3.txt"
rc=0
a.count || rc=$?
[[ "$rc" == "1" && "$RESULT" == "2" ]] || { printf "rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
a.lastRc
[[ "$RESULT" == "7" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
a.delete'

expect_clean "a REFUSED build (no program) — rc 2 from each/toArray/count/run, lastRc -1" '
N=0
cb() { N=$(( N + 1 )); }
TAwk.new a "" "$FX/f3.txt"
rc=0; a.each cb || rc=$?
[[ "$rc" == "2" && "$N" == "0" ]] || { printf "each rc=%s N=%s\n" "$rc" "$N" >&2; exit 9; }
declare -a A=( stale )
rc=0; a.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" && "${A[0]}" == "stale" ]] || { printf "toArray rc=%s\n" "$rc" >&2; exit 8; }
rc=0; a.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 7; }
rc=0; a.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 6; }
a.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 5; }
a.delete'

expect_clean "in-place: every sink rc 2, the file untouched; \`run\` (sandbox 0) then edits it" '
cp "$FX/f3.txt" "$FX/c_ip.txt"
N=0
cb() { N=$(( N + 1 )); }
TAwk.new a "{print toupper(\$0)}" "$FX/c_ip.txt"
a.sandbox = 0
a.inPlace = 1
declare -a A=()
TAwk.new t "{print}"
rc=0; a.each cb || rc=$?;    [[ "$rc" == "2" ]] || exit 9
rc=0; a.toArray A || rc=$?;  [[ "$rc" == "2" ]] || exit 8
rc=0; a.toList t || rc=$?;   [[ "$rc" == "2" ]] || exit 7
rc=0; a.first || rc=$?;      [[ "$rc" == "2" ]] || exit 6
rc=0; a.count || rc=$?;      [[ "$rc" == "2" ]] || exit 5
printf -v W0 "a 1\nb 2\nc 3"
printf -v W1 "A 1\nB 2\nC 3"
[[ "$(<"$FX/c_ip.txt")" == "$W0" ]] || exit 4
rc=0; a.run || rc=$?
[[ "$rc" == "0" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 3; }
[[ "$(<"$FX/c_ip.txt")" == "$W1" ]] || exit 2
a.delete
t.delete'

expect_clean "in-place with the DEFAULT sandbox — rc 2 from run, no abort, the file untouched" '
cp "$FX/f3.txt" "$FX/c_ip2.txt"
TAwk.new a "{print toupper(\$0)}" "$FX/c_ip2.txt"
a.inPlace = 1
rc=0; a.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 9; }
printf -v W0 "a 1\nb 2\nc 3"
[[ "$(<"$FX/c_ip2.txt")" == "$W0" ]] || exit 8
a.delete'

expect_clean "a denied extra (\`addArg -W sandbox\`) — rc 2 from every runner, no abort" '
TAwk.new a "{print}" "$FX/f3.txt"
a.addArg -W sandbox
declare -a A=( stale )
rc=0; a.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s\n" "$rc" >&2; exit 9; }
rc=0; a.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; a.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
a.delete'

expect_clean "an EMPTY \`cmd\` — rc 2 from every runner, no abort" '
TAwk.new a "{print}" "$FX/f3.txt"
a.cmd = ""
rc=0; a.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 9; }
rc=0; a.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 8; }
a.delete'

expect_clean "\`TAwk.apply\` with no path, and with an empty PROGRAM — rc 2, no abort, nothing printed" '
rc=0
out="$(TAwk.apply "{print}" </dev/null)" || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }
rc=0
out="$(TAwk.apply "" "$FX/f3.txt" </dev/null)" || rc=$?
[[ "$rc" == "2" && -z "$out" ]] || { printf "rc=%s out=%s\n" "$rc" "$out" >&2; exit 7; }'

expect_clean "\`TAwk.apply\` refused by the sandbox — rc 1, no abort" '
rc=0
TAwk.apply "BEGIN{system(\"true\")}" "$FX/f3.txt" 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
TAwk.new a "NR==2" "$FX/f3.txt"
rc=0
out="$(a.run)" || rc=$?
[[ "$out" == "b 2" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
a.run > /dev/null || rc=$?
a.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
a.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
TAwk.new a "{print}" "$FX/f3.txt"
a.addProgram "END{}"
a.setVar x 1
a.delete
declare -p a_paths  2>/dev/null && { printf "a_paths survived\n" >&2; exit 9; }
declare -p a_progs  2>/dev/null && { printf "a_progs survived\n" >&2; exit 8; }
declare -p a_vnames 2>/dev/null && { printf "a_vnames survived\n" >&2; exit 7; }
declare -p a_vvals  2>/dev/null && { printf "a_vvals survived\n" >&2; exit 6; }
declare -p a_args   2>/dev/null && { printf "a_args survived\n" >&2; exit 5; }
:'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
TAwk.new a "{print \$2}" "$FX/f3.txt"
n="$(a.count)"
[[ "$n" == "3" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
f="$(a.first)"
[[ "$f" == "1" ]] || { printf "first=%s\n" "$f" >&2; exit 8; }
a.delete'

expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through TAwk" '
TAwk.new a "{print}" "$FX/f3.txt"
a.subshellOk = 1
declare -a A=()
n="$(a.toArray A)"
[[ "$n" == "3" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
a.delete
TAwk.new a2 "{print}" "$FX/f3.txt"
declare -a A2=()
w="$( { a2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
a2.delete'

if tcase "A13: an UNGUARDED sink call with rc 1 aborts a \`set -eu\` caller (the documented rule)"; then
    out="$(FX="$FX" UNIT="$UNIT" timeout 60 "$BASH" -c 'set -eu
source "$UNIT"
TAwk.new a "{print}" "$FX/no_such.txt"
a.count 2>/dev/null
printf NOTREACHED' 2>/dev/null </dev/null)"; urc=$?
    guarded="$(FX="$FX" UNIT="$UNIT" timeout 60 "$BASH" -c 'set -eu
source "$UNIT"
TAwk.new a "{print}" "$FX/no_such.txt"
rc=0
a.count 2>/dev/null || rc=$?
printf "%s" "$rc"' 2>/dev/null </dev/null)"; grc=$?
    if [[ $urc -ne 0 && -z "$out" && $grc -eq 0 && "$guarded" == "1" ]]; then
        kt_test_pass "unguarded: the caller died (rc $urc, nothing printed); guarded: rc 1 and it goes on"
    else
        kt_test_fail "unguarded rc=$urc out='$out'; guarded rc=$grc out='$guarded'"
    fi
fi

# ===========================================================================
kt_test_section "2. the debug switch — one line per rc 2 / gawk-error path, silence otherwise"
# ===========================================================================

TA_RC=0; TA_N=0; TA_1=''; TOOL_N=0
ta_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TA_RC=$?
    VERBOSE_KKLASS=
    TA_N=0; TOOL_N=0; TA_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TA_N=$(( TA_N + 1 ))
                if [[ -z "$TA_1" ]]; then TA_1="$__zl"; fi
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
    ta_dbg "$@"
    local n="$TA_N" first="$TA_1" drc="$TA_RC"
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
    ta_dbg "$@"
    if [[ "$TA_RC" == "$want" && $TA_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TA_RC ourLines=$TA_N first='$TA_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

TAwk.new dOk    '{print}' "$FX/f3.txt"
TAwk.new dNone  ''        "$FX/f3.txt"
TAwk.new dPfd   ''        "$FX/f3.txt"
dPfd.programFile = '-'
TAwk.new dIpNo  '{print}'
dIpNo.sandbox = 0
dIpNo.inPlace = 1
TAwk.new dIpSb  '{print}' "$FX/f3.txt"
dIpSb.inPlace = 1
TAwk.new dSuf   '{print}' "$FX/f3.txt"
dSuf.backupSuffix = .bak
TAwk.new dAsg   '{print}' k=v
TAwk.new dDeny  '{print}' "$FX/f3.txt"
dDeny.addArg --so=x
TAwk.new dDenyW '{print}' "$FX/f3.txt"
dDenyW.addArg -Wsandbox
TAwk.new dDash  '{print}' "$FX/f3.txt"
dDash.addArg --
TAwk.new dStray '{print}' "$FX/f3.txt"
dStray.addArg stray
TAwk.new dDangl '{print}' "$FX/f3.txt"
dDangl.addArg -v
TAwk.new dCmd   '{print}' "$FX/f3.txt"
dCmd.cmd = ''
TAwk.new dIp    '{print}' "$FX/f3.txt"
dIp.sandbox = 0
dIp.inPlace = 1
TAwk.new dMiss  '{print}' "$FX/f3.txt" "$FX/no_such.txt"
TAwk.new dBad   'BEGIN{'  "$FX/f3.txt"
TAwk.new dNoF   ''        "$FX/f3.txt"
dNoF.programFile = "$FX/no_such.awk"
TAwk.new dX1    'NR==2{exit 1} 1' "$FX/f3.txt"
TAwk.new dX2    'NR==2{exit 2} 1' "$FX/f3.txt"
TAwk.new dX7    'NR==2{exit 7} 1' "$FX/f3.txt"
TAwk.new dX3    'NR==1{exit 3} 1' "$FX/f3.txt"
TAwk.new dX256  'NR==1{exit 256} 1' "$FX/f3.txt"

check_one "rc 2: no program — one line, through \`each\`"                   2 "no program"    dNone.each cb_nul
check_one "rc 2: no program — one line, through \`count\`"                  2 "no program"    dNone.count
check_one "rc 2: no program — one line, through \`run\`"                    2 "no program"    dNone.run
check_one "rc 2: \`programFile = -\` — one line"                            2 "programFile"   dPfd.count
check_one "rc 2: \`inPlace\` with no path — one line"                       2 "inPlace"       dIpNo.run
check_one "rc 2: \`inPlace\` with the default sandbox — one line"           2 "sandbox = 0"   dIpSb.run
check_one "rc 2: \`backupSuffix\` without \`inPlace\` — one line"           2 "backupSuffix"  dSuf.count
check_one "rc 2: an assignment-looking path — one line"                     2 "./k=v"         dAsg.count
check_one "rc 2: a denied extra (\`--so=x\`) — one line"                    2 "gawk's --source" dDeny.count
check_one "rc 2: a denied \`-W\` extra (\`-Wsandbox\`) — one line"          2 "gawk's --sandbox" dDenyW.count
check_one "rc 2: \`--\` among the extras — one line"                        2 "ends gawk's options" dDash.count
check_one "rc 2: a non-option extra — one line"                             2 "not an option word" dStray.count
check_one "rc 2: a dangling \`-v\` — one line"                              2 "takes an argument" dDangl.count
check_one "rc 2: an empty \`cmd\` — one line"                               2 "cmd"           dCmd.count
check_one "rc 2: \`count\` with \`inPlace = 1\` — one line"                 2 "in-place"      dIp.count
check_one "rc 2: \`each\` with \`inPlace = 1\` — one line"                  2 "in-place"      dIp.each cb_nul
check_one "rc 2: \`TAwk.apply\` with no path — one line"                    2 "TAwk.apply"    TAwk.apply '{print}'
check_one "rc 2: \`TAwk.apply ''\` — one line"                              2 "TAwk.apply"    TAwk.apply '' "$FX/f3.txt"
check_one "rc 2: \`setVar\` with a keyword — one line"                      2 "TAwk.setVar"   dOk.setVar BEGIN 1
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                             2 "output array"  dOk.toArray RESULT
check_one "rc 2: \`toArray __taw_x\` — one line (the \`__taw_\` prefix)"    2 "output array"  dOk.toArray __taw_x
check_one "rc 2: \`toArray dOk_progs\` — one line (the \`_progs\` suffix)"  2 "output array"  dOk.toArray dOk_progs
check_one "rc 2: \`toArray dOk_vnames\` — one line (the \`_vnames\` suffix)" 2 "output array" dOk.toArray dOk_vnames
check_one "rc 2: \`toArray dOk_vvals\` — one line (the \`_vvals\` suffix)"  2 "output array"  dOk.toArray dOk_vvals

check_one "gawk raw 2 (the fatal missing file) — rc 1 and one line"         1 "gawk exited 2" dMiss.count
check_one "gawk raw 1 (a syntax error) — rc 1 and one line"                 1 "gawk exited 1" dBad.count
check_one "gawk raw 2 (a missing \`-f\` file) — rc 1 and one line"         1 "gawk exited 2" dNoF.count
check_one "a program's \`exit 1\` — rc 1 and one line, worded to say it may be the program's" \
                                                                             1 "or the program's exit 1" dX1.count
check_one "a program's \`exit 2\` — rc 1 and one line"                      1 "or the program's exit 2" dX2.count

check_silent "rc 0: a successful \`count\` says NOTHING"                    0 dOk.count
check_silent "rc 0: \`each\` on records says NOTHING"                       0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on records says NOTHING"                    0 dOk.toArray DBG_ARR
check_silent "rc 0: \`run\` says NOTHING"                                   0 dOk.run
check_silent "rc 0: \`setVar\` with a good name says NOTHING"               0 dOk.setVar good 1
check_silent "rc 0: \`TAwk.apply\` that succeeded says NOTHING"             0 TAwk.apply '{print}' "$FX/f3.txt"
check_silent "a program's \`exit 7\` — rc 1 and SILENT (N outside {1,2,127})" 1 dX7.count
check_silent "a program's \`exit 3\` — rc 1 and SILENT"                     1 dX3.count
check_silent "a program's \`exit 256\` wraps to 0 — rc 0 and SILENT"        0 dX256.count

if tcase "the \`exit N\` status reaches \`lastRc\` RAW (7 and 3) while the member answers 1"; then
    dX7.count >/dev/null 2>&1; dX7.lastRc; a="$RESULT"
    dX3.count >/dev/null 2>&1; dX3.lastRc; b="$RESULT"
    if [[ "$a" == "7" && "$b" == "3" ]]; then
        kt_test_pass "lastRc 7 and 3"
    else
        kt_test_fail "lastRc '$a' and '$b'"
    fi
fi

for d in dOk dNone dPfd dIpNo dIpSb dSuf dAsg dDeny dDenyW dDash dStray dDangl dCmd dIp dMiss dBad dNoF dX1 dX2 dX7 dX3 dX256; do
    "$d".delete
done
