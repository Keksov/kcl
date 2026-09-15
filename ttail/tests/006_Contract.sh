#!/bin/bash
# 006_Contract.sh — ttail P0: the kcl-wide contract (kcl/README.md §1) for
# TTail (ttail/PLAN.md §2.1; thead/PLAN.md §2.1, §2.5, §3 H12, §6).
#
# What it pins:
#
#   source integrity  `bash -n`, "no single-quoted string left open", no inline
#                     `$'\r'` in a member body, no `$this.` internal call, no
#                     `inherited` inside the constructor, no `kk.isInt` on the
#                     count, and — the ttail-specific one — the three overridden
#                     sinks end with the rc-PRESERVING spelling of thead §6
#                     (`inherited X "$@" || rc=$?` … `kk._return "$n"; return
#                     "$rc"`), never on a bare trailing `inherited`.
#                     Also: `ttail.sh` never sources `thead.sh` (§ header).
#   set -eu           TTail used from a script under `set -eu`, as an instance
#                     and through BOTH TPipe forms, on every outcome, with every
#                     sink call guarded `|| rc=$?` (H12).
#   §1.2 diagnostics  exactly ONE `kk.debug` line on each rc 2 path (the follow
#                     refusals included) and on each "tail exited 1" path, and
#                     NOTHING on a rc 0 path.
#   D6 final          `$(t.toArray A)` warns about the subshell, `subshellOk = 1`
#                     silences it.
#
# No case in this file starts a follower that it does not end: the `follow`
# cases here are the REFUSED sinks, which run nothing at all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/ttail.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"

kt_test_section "006: the kcl contract for TTail (P0)"

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

kt_test_start "the CONSTRUCTOR calls \`parent.constructor tail\`, never \`inherited\`"
ctor="$(sed -n '/^TTail.Create()/,/^}/p' "$UNIT")"
if [[ "$ctor" == *"parent.constructor tail"* && "$ctor" != *inherited* ]]; then
    kt_test_pass "explicit \`parent.constructor tail\`, no \`inherited\`"
else
    kt_test_fail "constructor body: ${ctor:0:200}"
fi

kt_test_start "the DESTRUCTOR frees \`\${inst}_paths\` and then chains with \`inherited\`"
dtor="$(sed -n '/^TTail.Destroy()/,/^}/p' "$UNIT")"
if [[ "$dtor" == *'unset -v "${__inst__}_paths"'* && "$dtor" == *inherited* ]]; then
    kt_test_pass "own array first, then the chain to TUtil.Destroy"
else
    kt_test_fail "destructor body: ${dtor:0:200}"
fi

kt_test_start "the count is NOT validated with \`kk.isInt\` (it would fold \`+2\` into \`2\`)"
if bad="$(grep -nE "^[^#]*kk\.isInt" "$UNIT")"; then
    kt_test_fail "kk.isInt used: ${bad//$'\n'/ | }"
else
    kt_test_pass "the regex + the 19-digit guard, no kk.isInt anywhere in the unit"
fi

kt_test_start "the count regex is held in a VARIABLE and applied with \`[[ =~ ]]\`"
if grep -q '\^\[+-\]?\[0-9\]+\$' "$UNIT" && grep -q '=~ \$' "$UNIT"; then
    kt_test_pass "\`^[+-]?[0-9]+\$\` in a variable, matched with \`[[ =~ \$re ]]\`"
else
    kt_test_fail "the regex or the \`[[ =~ \$var ]]\` form is missing"
fi

kt_test_start "the unit sources ONLY \`../tutil/tutil.sh\` (\`TTail : THead\` would be wrong: \`+N\` differs)"
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

# The blocker the critic measured: a `func` body that merely ENDS on
# `inherited toArray "$@"` returns 0 where the base returned 1, because the
# compiled `kk._return "$RESULT"` trailer replaces the rc. Each of the three
# overrides must capture the rc and re-raise it.
kt_test_start "the three overridden sinks use the rc-PRESERVING spelling (thead §6)"
bad=""
for m in toArray toList count; do
    body="$(sed -n "/^TTail.$m()/,/^}/p" "$UNIT")"
    [[ "$body" == *"inherited $m \"\$@\" || "* ]] || bad+=" $m:no-guarded-inherited"
    [[ "$body" == *'kk._return "$__tt_n"'* ]]     || bad+=" $m:no-saved-RESULT"
    [[ "$body" == *'return "$__tt_rc"'* ]]        || bad+=" $m:no-rc-reraise"
    # the LAST statement must not be `inherited` — a body that ends on it
    # returns 0 where the base returned 1 (the compiled trailer replaces the rc)
    last="$(printf '%s\n' "$body" | grep -vE '^\}$' | tail -1)"
    case "$last" in
        *inherited*) bad+=" $m:ends-on-inherited" ;;
    esac
done
if [[ -z "$bad" ]]; then
    kt_test_pass "toArray / toList / count each capture the rc and re-raise it"
else
    kt_test_fail "$bad"
fi

kt_test_start "no \`var\` shadows a TUtil or kklass member name"
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
done < <(sed -n '/^class TTail : TUtil/,/^end/p' "$UNIT")
nvars=0
for _ in $declared; do nvars=$(( nvars + 1 )); done
if [[ -z "$clash" && $nvars -eq 7 ]]; then
    kt_test_pass "$nvars declared vars, none colliding with an inherited member"
else
    kt_test_fail "vars=$nvars shadowing:$clash declared:$declared"
fi

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and a small tree for the children"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`tail\` on PATH is GNU coreutils"
TAIL_VER="$(tail --version 2>/dev/null | head -1 || :)"
if [[ "$TAIL_VER" == "tail (GNU coreutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$TAIL_VER"
else
    kt_test_pass "SKIP: non-GNU tail ('${TAIL_VER:-no banner}'); every case that runs tail is skipped"
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
printf '1\n2\n3\n4\n5\n'   > "$FX/f5.txt"
printf 'a1\na2\na3\n'      > "$FX/a3.txt"

# ===========================================================================
kt_test_section "1. set -eu — the instance and BOTH TPipe forms, every outcome"
# ===========================================================================

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

expect_clean "t.each: an instance that delivers records" '
N=0
cb() { N=$(( N + 1 )); }
TTail.new t 2 "$FX/f5.txt"
rc=0
t.each cb || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
t.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
t.delete'

expect_clean "form 2: TPipe.each CB -- \"\${argv[@]}\" with the argv TTail built" '
N=0
cb() { N=$(( N + 1 )); }
TTail.new t 2 "$FX/f5.txt"
declare -a W=()
rc=0
t.argv W || rc=$?
[[ "$rc" == "0" && "$RESULT" == "5" ]] || { printf "words=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
TPipe.each cb -- "${W[@]}" || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
t.delete'

expect_clean "form 2 with \`TTail.take\` as the producer command" '
N=0
cb() { N=$(( N + 1 )); }
rc=0
TPipe.each cb -- TTail.take 2 "$FX/f5.txt" || rc=$?
[[ "$rc" == "0" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }'

expect_clean "form 1: a REAL pipe under \`shopt -s lastpipe\`" '
shopt -s lastpipe
N=0
cb() { N=$(( N + 1 )); }
rc=0
TTail.take 2 "$FX/f5.txt" | TPipe.each cb || rc=$?
[[ "$N" == "2" ]] || { printf "N=%s\n" "$N" >&2; exit 9; }'

expect_clean "every func sink on an instance that delivers" '
TTail.new t 3 "$FX/f5.txt"
declare -a A=()
rc=0
t.toArray A || rc=$?
[[ "$rc" == "0" && "$RESULT" == "3" && "${A[2]}" == "5" ]] || { printf "toArray=%s rc=%s\n" "$RESULT" "$rc" >&2; exit 9; }
t.count || rc=$?
[[ "$RESULT" == "3" ]] || { printf "count=%s\n" "$RESULT" >&2; exit 8; }
t.first || rc=$?
[[ "$RESULT" == "3" ]] || { printf "first=%s\n" "$RESULT" >&2; exit 7; }
t.delete'

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
TTail.new t 2 "$FX/f5.txt"
rc=0
t.toList L || rc=$?
[[ "$RESULT" == "2" ]] || { printf "offered=%s\n" "$RESULT" >&2; exit 9; }
[[ "$(L.N)" == "2" ]] || { printf "stored=%s\n" "$(L.N)" >&2; exit 8; }
t.delete
L.delete'

expect_clean "a TOOL ERROR (a missing file, raw 1) — rc 1, the child survives" '
N=0
cb() { N=$(( N + 1 )); }
TTail.new t 1 "$FX/no_such.txt"
rc=0
t.each cb 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
t.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
t.delete'

expect_clean "PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT" '
TTail.new t 1 "$FX/f5.txt" "$FX/no_such.txt"
declare -a A=()
rc=0
t.toArray A 2>/dev/null || rc=$?
[[ "$rc" == "1" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "${#A[@]}" ]] || { printf "RESULT=%s kept=%s\n" "$RESULT" "${#A[@]}" >&2; exit 8; }
(( ${#A[@]} > 0 )) || { printf "kept=%s\n" "${#A[@]}" >&2; exit 7; }
t.lastRc
[[ "$RESULT" == "1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 6; }
t.delete'

expect_clean "a REFUSED build (\`lines\` + \`bytes\`) — rc 2, nothing runs, no abort" '
N=0
cb() { N=$(( N + 1 )); }
TTail.new t 2 "$FX/f5.txt"
t.bytes = 3
rc=0
t.each cb || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ "$N" == "0" ]] || { printf "N=%s\n" "$N" >&2; exit 8; }
t.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 7; }
t.delete'

expect_clean "the FOLLOW refusal (\`toArray\` with \`follow = 1\`) — rc 2, no abort, nothing runs" '
TTail.new t 1 "$FX/f5.txt"
t.follow = 1
declare -a A=( keep )
rc=0
t.toArray A || rc=$?
[[ "$rc" == "2" ]] || { printf "toArray rc=%s\n" "$rc" >&2; exit 9; }
[[ "$RESULT" == "" ]] || { printf "RESULT=%s\n" "$RESULT" >&2; exit 8; }
[[ "${A[0]}" == "keep" ]] || { printf "A=%s\n" "${A[0]}" >&2; exit 7; }
rc=0
t.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 6; }
t.lastRc
[[ "$RESULT" == "-1" ]] || { printf "lastRc=%s (nothing may have run)\n" "$RESULT" >&2; exit 5; }
t.delete'

expect_clean "an EMPTY \`cmd\` — rc 2 from every runner, no abort" '
TTail.new t 2 "$FX/f5.txt"
t.cmd = ""
declare -a A=( stale )
rc=0; t.toArray A || rc=$?
[[ "$rc" == "2" && "$RESULT" == "" ]] || { printf "toArray rc=%s RESULT=%s\n" "$rc" "$RESULT" >&2; exit 9; }
rc=0; t.count || rc=$?
[[ "$rc" == "2" ]] || { printf "count rc=%s\n" "$rc" >&2; exit 8; }
rc=0; t.run || rc=$?
[[ "$rc" == "2" ]] || { printf "run rc=%s\n" "$rc" >&2; exit 7; }
t.delete'

expect_clean "a bad \`lines\` — rc 2, no abort" '
TTail.new t 2 "$FX/f5.txt"
t.lines = 1K
rc=0
t.count || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
t.delete'

expect_clean "\`zeroTerminated\` with two paths — rc 2, no abort" '
TTail.new t 2 "$FX/f5.txt" "$FX/a3.txt"
t.zeroTerminated = 1
rc=0
t.count || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
t.delete'

expect_clean "\`TTail.take\` with no path — rc 2, no abort, nothing printed" '
rc=0
out="$(TTail.take 2 </dev/null)" || rc=$?
[[ "$rc" == "2" ]] || { printf "rc=%s\n" "$rc" >&2; exit 9; }
[[ -z "$out" ]] || { printf "out=%s\n" "$out" >&2; exit 8; }'

expect_clean "\`run\` streams and the raw rc is readable afterwards" '
TTail.new t 2 "$FX/f5.txt"
rc=0
out="$(t.run)" || rc=$?
[[ "$out" == "4
5" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
t.run > /dev/null || rc=$?
t.lastRc
[[ "$RESULT" == "0" ]] || { printf "lastRc=%s\n" "$RESULT" >&2; exit 8; }
t.delete'

expect_clean "\`delete\` on an instance that never ran anything" '
TTail.new t 2 "$FX/f5.txt"
t.delete
declare -p t_paths 2>/dev/null && { printf "t_paths survived\n" >&2; exit 9; }
declare -p t_args  2>/dev/null && { printf "t_args survived\n" >&2; exit 8; }
:'

expect_clean "an instance reading STDIN (no path) under set -eu" '
TTail.new t 2
rc=0
out="$(printf "s1\ns2\ns3\n" | t.run)" || rc=$?
[[ "$out" == "s2
s3" ]] || { printf "out=%s\n" "$out" >&2; exit 9; }
t.delete'

expect_clean "the \`\$( )\` position: a func sink prints its value exactly ONCE" '
TTail.new t 2 "$FX/f5.txt"
n="$(t.count)"
[[ "$n" == "2" ]] || { printf "n=%s (a doubled value means __TPIPE_QUIET is not in place)\n" "$n" >&2; exit 9; }
t.delete'

expect_clean "D6 final: \`subshellOk = 1\` silences TPipe's subshell warning through TTail" '
TTail.new t 2 "$FX/f5.txt"
t.subshellOk = 1
declare -a A=()
n="$(t.toArray A)"
[[ "$n" == "2" ]] || { printf "n=%s\n" "$n" >&2; exit 9; }
t.delete
TTail.new t2 2 "$FX/f5.txt"
declare -a A2=()
w="$( { t2.toArray A2 >/dev/null; } 2>&1 )"
case "$w" in
    "Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — "*) : ;;
    *) printf "unexpected warning: %s\n" "$w" >&2; exit 8 ;;
esac
t2.delete'

if tcase "H12: an UNGUARDED sink call with rc 1 aborts a \`set -eu\` caller (the documented rule)"; then
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
TTail.new t 1 "$FX/no_such.txt"
t.count
printf NOTREACHED' 2>/dev/null </dev/null)"; urc=$?
    guarded="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c 'set -eu
source "$UNIT"
TTail.new t 1 "$FX/no_such.txt"
rc=0
t.count || rc=$?
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

TT_RC=0; TT_N=0; TT_1=''; TOOL_N=0
tt_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TT_RC=$?
    VERBOSE_KKLASS=
    TT_N=0; TOOL_N=0; TT_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TT_N=$(( TT_N + 1 ))
                if [[ -z "$TT_1" ]]; then TT_1="$__l"; fi
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
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*) QOURS=$(( QOURS + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

check_one() {
    local title="$1" want="$2" sub="$3"; shift 3
    if ! tcase "$title"; then
        return 0
    fi
    tt_dbg "$@"
    local n="$TT_N" first="$TT_1" drc="$TT_RC"
    quiet_rc "$@"
    if [[ "$drc" == "$want" && $n -eq 1 && "$first" == *"$sub"* \
          && "$QRC" == "$want" && "$QOURS" -eq 0 ]]; then
        kt_test_pass "rc $want, one line: ${first:0:74}"
    else
        kt_test_fail "debug rc=$drc lines=$n first='$first' / quiet rc=$QRC ourLines=$QOURS"
    fi
}

check_silent() {
    local title="$1" want="$2"; shift 2
    if ! tcase "$title"; then
        return 0
    fi
    tt_dbg "$@"
    if [[ "$TT_RC" == "$want" && $TT_N -eq 0 ]]; then
        kt_test_pass "rc $want, no diagnostic of ours (tool lines: $TOOL_N)"
    else
        kt_test_fail "rc=$TT_RC ourLines=$TT_N first='$TT_1'"
    fi
}

cb_nul() { return 0; }
declare -a DBG_ARR=()

class TLC
    public
        var         N
        constructor Create
        proc        Add
end
TLC.Create() { N=0; return 0; }
TLC.Add()    { N=$(( N + 1 )); return 0; }
build TLC
TLC.new dList

TTail.new dOk   2  "$FX/f5.txt"                        # rc 0
TTail.new dMiss 1  "$FX/f5.txt" "$FX/no_such.txt"      # raw 1, partial
TTail.new dGone 1  "$FX/no_such.txt"                   # raw 1, nothing
TTail.new dNB   2  "$FX/f5.txt"                        # buildArgv rc 2
dNB.bytes = 3
TTail.new dQV   2  "$FX/f5.txt"
dQV.quiet = 1
dQV.verbose = 1
TTail.new dZ2   2  "$FX/f5.txt" "$FX/a3.txt"
dZ2.zeroTerminated = 1
TTail.new dZV   2  "$FX/f5.txt"
dZV.zeroTerminated = 1
dZV.verbose = 1
TTail.new dBad  2  "$FX/f5.txt"
dBad.lines = 1K
TTail.new dCmd  2  "$FX/f5.txt"
dCmd.cmd = ''
TTail.new dFol  1  "$FX/f5.txt"                        # the follow refusals
dFol.follow = 1

check_one "rc 2: \`lines\` + \`bytes\` — one line, through \`each\`"   2 "lines"          dNB.each cb_nul
check_one "rc 2: \`lines\` + \`bytes\` — one line, through \`count\`"  2 "lines"          dNB.count
check_one "rc 2: \`quiet\` + \`verbose\` — one line"                   2 "quiet"          dQV.count
check_one "rc 2: \`zeroTerminated\` with two paths — one line"         2 "zeroTerminated" dZ2.count
check_one "rc 2: \`zeroTerminated\` + \`verbose\` — one line"          2 "zeroTerminated" dZV.count
check_one "rc 2: a bad \`lines\` — one line"                           2 "lines"          dBad.count
check_one "rc 2: an empty \`cmd\` — one line"                          2 "cmd"            dCmd.count
check_one "rc 2: \`TTail.take\` with no path — one line"               2 "take"           TTail.take 2
check_one "rc 2: \`TTail.take\` with a bad count — one line"           2 "take"           TTail.take 1K "$FX/f5.txt"
check_one "rc 2: \`toArray\` with a bad out-name — one line (TUtil's check)" \
                                                                       2 "output array"   dOk.toArray RESULT
check_one "rc 2: \`toArray __tt_x\` — one line (the \`__tt_\` prefix, thead §2.8)" \
                                                                       2 "output array"   dOk.toArray __tt_x

check_one "rc 2: \`toArray\` with \`follow = 1\` — one line (§2.1)"    2 "follow = 1"     dFol.toArray DBG_ARR
check_one "rc 2: \`count\` with \`follow = 1\` — one line"             2 "follow = 1"     dFol.count
check_one "rc 2: \`toList\` with \`follow = 1\` — one line"            2 "follow = 1"     dFol.toList dList

check_one "tail raw 1 (a missing operand among good ones) — rc 1 and one line" \
                                                                       1 "tail exited 1"  dMiss.count
check_one "tail raw 1 (the only operand missing) — rc 1 and one line"  1 "tail exited 1"  dGone.count

check_silent "rc 0: a successful run says NOTHING"                     0 dOk.count
check_silent "rc 0: \`each\` on records says NOTHING"                  0 dOk.each cb_nul
check_silent "rc 0: \`toArray\` on records says NOTHING"               0 dOk.toArray DBG_ARR
check_silent "rc 0: \`TTail.take\` that succeeded says NOTHING"        0 TTail.take 2 "$FX/f5.txt"

if tcase "the \`tail exited\` line names TTail, and tail's OWN line is left alone"; then
    tt_dbg dGone.count
    if [[ "$TT_N" == "1" && "$TT_1" == *"TTail"* && "$TOOL_N" -ge 1 ]]; then
        kt_test_pass "ours: ${TT_1:0:60} | tail's: $TOOL_N line(s) untouched"
    else
        kt_test_fail "ourLines=$TT_N first='$TT_1' toolLines=$TOOL_N"
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
dFol.delete
dList.delete
