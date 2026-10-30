#!/usr/bin/env bash
# 005_TextMode.sh — the CR contract at the base (owner DL11, launch L2.7-C;
# README §3 "CRLF: one result on every platform").
#
# In TEXT mode TGrep/TSed/TAwk deliver records without the line-end CR on
# every platform. A descendant's `buildArgv` says "text mode" through TUtil's
# private `_textMode`; TUtil then removes the CR itself ONLY where the
# platform's tool keeps it (`__TUTIL_TOOLS_STRIP_CR = 0`: Linux, BSD, macOS),
# and adds nothing where the tool already dropped it (`= 1`: cygwin/msys).
#
# Both platform paths are driven HERE, on any host: the global is flipped per
# case and the producer is a bash function that writes the CRs itself, i.e. a
# stand-in for "a tool that keeps the CR". The base `buildArgv` never touches
# `_textMode`, so a test sets it on a plain TUtil instance.
#
# Sections:
#   A  `_textMode` exists, defaults to 0, and with 0 nothing changes on either
#      path (the CR survives every sink and `run`)
#   B  the strip path (`_textMode = 1`, tool keeps the CR): every sink drops ONE
#      trailing CR per record (a CR inside a record and the second of two stay),
#      `run`'s stream loses the line-end CR, stdin still reaches the tool, the
#      raw rc is the TOOL's, `$( )` carries no framework bytes
#   C  the native path (`_textMode = 1`, the tool already stripped): the
#      wrapper adds nothing — no `-c`, no filter, `run` executes the tool in
#      THIS shell
#   D  `nul = 1` (records are not lines): no strip; `crlf = 1` with text mode
#      strips exactly ONE CR, not two
#   E  `run` on the strip path under `set -euo pipefail` (a child): a tool
#      exiting 3 is member rc 1 + `lastRc` 3 and the script goes on
#   F  (round 2) `run` with `nul = 1` is not filtered; a FAILING filter is not
#      silent (`lastRc` 2 + one debug line); `tutil._crStdin`; `sed -u` when
#      this sed takes it
#
# `_textMode` is the OUTPUT-strip request: TGrep (file operands) and TAwk's
# `--posix` fallback set it; TSed and TAwk otherwise strip on the INPUT side
# (their own tests cover that). The base mechanism is the same either way.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tutil.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "005: the CR contract at the base (DL11)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
printf -v CR '\r'
NATIVE_AT_LOAD="$__TUTIL_TOOLS_STRIP_CR"

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

arr_show() {
    local -n __a="$1"
    if (( ${#__a[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__a[@]}"
}

# The stand-in tools. `cr_tool` keeps every CR it writes, like a Linux grep
# over a CRLF file: a plain CRLF line, a line with a CR INSIDE it, a line
# ending in TWO CRs, and an unterminated tail ending in a CR. `cr1_tool` has
# only single line-end CRs (the `run` stream cases: a doubled CR would also
# meet the host sed's own text mode on cygwin/msys, which is not the path
# under test). Both exit with $TOOL_RC.
TOOL_RC=0
cr_tool()  { printf 'a 1\r\np\rq\r\nb 2\r\r\nc\r'; return "$TOOL_RC"; }
cr1_tool() { printf 'a 1\r\nb 2\r\n'; return "$TOOL_RC"; }
nul_tool() { printf 'x\r\0y\r\0'; return 0; }
pid_tool() { printf '%s\n' "$BASHPID" > "$TMP/pid"; printf 'z\r\n'; return 0; }

CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

class TTMList
    public
        var         N
        constructor Create
        proc        Add
end
TTMList.Create() { N=0; return 0; }
TTMList.Add()    { N=$(( N + 1 )); TTM_RECS+=( "$1" ); return 0; }
build TTMList

declare -a GOT=() TTM_RECS=()

# sinks_of INST — run all five sinks; fills GOT (toArray), CB_RECS (each),
# TTM_RECS (toList), FIRST, COUNT and their rcs.
FIRST='' COUNT='' S_RC=''
sinks_of() {
    local i="$1" a=0 e=0 l=0 f=0 c=0
    GOT=(); CB_RECS=(); TTM_RECS=()
    "$i".toArray GOT || a=$?
    "$i".each cb_collect || e=$?
    TTMList.new ttmL
    "$i".toList ttmL || l=$?
    ttmL.delete
    "$i".first || f=$?; FIRST="$RESULT"
    "$i".count || c=$?; COUNT="$RESULT"
    S_RC="$a$e$l$f$c"
}

# ===========================================================================
kt_test_section "A. the property, and text mode OFF"
# ===========================================================================

kt_test_start "A: \`_textMode\` is a TUtil var, 0 after \`new\`; \`__TUTIL_TOOLS_STRIP_CR\` is 0 or 1 (1 exactly on cygwin/msys)"
TUtil.new uA cr_tool
d="$(declare -p uA_data 2>/dev/null)"
case "${OSTYPE:-}" in cygwin*|msys*) wantn=1 ;; *) wantn=0 ;; esac
if [[ "$(uA._textMode)" == "0" && "$d" == *'[_textMode]="0"'* && "$NATIVE_AT_LOAD" == "$wantn" ]]; then
    kt_test_pass "_textMode 0; __TUTIL_TOOLS_STRIP_CR=$NATIVE_AT_LOAD on OSTYPE=$OSTYPE"
else
    kt_test_fail "_textMode='$(uA._textMode)' strip='$NATIVE_AT_LOAD' want '$wantn' data=$d"
fi

for nat in 0 1; do
    kt_test_start "A: \`_textMode = 0\` with __TUTIL_TOOLS_STRIP_CR=$nat — every CR survives every sink and \`run\`"
    __TUTIL_TOOLS_STRIP_CR=$nat
    sinks_of uA
    out="$(uA.run | od -c)"
    want="$(cr_tool | od -c)"
    if [[ "$S_RC" == "00000" && "$FIRST" == "a 1$CR" && "$COUNT" == "4" && "$out" == "$want" ]] \
       && arr_is GOT "a 1$CR" "p${CR}q$CR" "b 2$CR$CR" "c$CR" \
       && arr_is CB_RECS "${GOT[@]}" && arr_is TTM_RECS "${GOT[@]}"; then
        kt_test_pass "4 records with their CRs, run == the tool's bytes"
    else
        kt_test_fail "rc=$S_RC got=$(arr_show GOT) first=$(printf %q "$FIRST") count=$COUNT"
    fi
done
__TUTIL_TOOLS_STRIP_CR="$NATIVE_AT_LOAD"
uA.delete

# ===========================================================================
kt_test_section "B. the strip path: text mode, the tool KEEPS the CR"
# ===========================================================================

kt_test_start "B: every sink drops ONE trailing CR per record — ('a 1' 'p\\rq' 'b 2\\r' 'c'); first 'a 1'; count 4"
TUtil.new uB cr_tool
uB._textMode = 1
__TUTIL_TOOLS_STRIP_CR=0
sinks_of uB
if [[ "$S_RC" == "00000" && "$FIRST" == "a 1" && "$COUNT" == "4" ]] \
   && arr_is GOT "a 1" "p${CR}q" "b 2$CR" "c" \
   && arr_is CB_RECS "${GOT[@]}" && arr_is TTM_RECS "${GOT[@]}"; then
    kt_test_pass "the line-end CR is gone, a CR inside the record and the second of two stay"
else
    kt_test_fail "rc=$S_RC got=$(arr_show GOT) each=$(arr_show CB_RECS) list=$(arr_show TTM_RECS) first=$(printf %q "$FIRST") count=$COUNT"
fi

kt_test_start "B: \`run\` streams LF-only lines (no CR), rc 0, lastRc 0; \`\$( )\` carries no framework bytes"
uB.cmd = cr1_tool
TOOL_RC=0
rc=0; uB.run > "$TMP/b.out" || rc=$?
uB.lastRc; lr="$RESULT"
got="$(od -c < "$TMP/b.out")"
want="$(printf 'a 1\nb 2\n' | od -c)"
cap="$(uB.run)"
if [[ $rc -eq 0 && "$lr" == "0" && "$got" == "$want" && "$cap" == $'a 1\nb 2' ]]; then
    kt_test_pass "LF-only stream, captured exactly"
else
    kt_test_fail "rc=$rc lastRc=$lr od='${got//$'\n'/|}' cap=$(printf %q "$cap")"
fi

kt_test_start "B: \`run\` keeps a CR INSIDE a line and leaves an unterminated tail unterminated"
pq_tool() { printf 'p\rq\r\nc\r'; return 0; }
uB.cmd = pq_tool
got="$(uB.run | od -c)"
want="$(printf 'p\rq\nc' | od -c)"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "only the line-end CRs went"
else
    kt_test_fail "od='${got//$'\n'/|}' want='${want//$'\n'/|}'"
fi

kt_test_start "B: \`run\` on the strip path: the tool's raw rc 3 -> member rc 1, lastRc 3 (never the filter's 0)"
uB.cmd = cr1_tool
TOOL_RC=3
rc=0; uB.run > "$TMP/b3.out" || rc=$?
uB.lastRc; lr="$RESULT"
TOOL_RC=0
if [[ $rc -eq 1 && "$lr" == "3" && "$(od -c < "$TMP/b3.out")" == "$(printf 'a 1\nb 2\n' | od -c)" ]]; then
    kt_test_pass "rc 1, lastRc 3, the records still arrived without CR"
else
    kt_test_fail "rc=$rc lastRc=$lr"
fi

kt_test_start "B: \`run\` on the strip path still hands the caller's stdin to the tool"
uB.cmd = cat
got="$(printf 'in 1\r\nin 2\r\n' | uB.run | od -c)"
want="$(printf 'in 1\nin 2\n' | od -c)"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "cat read the pipe; its CRs were removed"
else
    kt_test_fail "od='${got//$'\n'/|}'"
fi
__TUTIL_TOOLS_STRIP_CR="$NATIVE_AT_LOAD"
uB.delete

# ===========================================================================
kt_test_section "C. the native path: text mode, the tool ALREADY stripped"
# ===========================================================================

kt_test_start "C: __TUTIL_TOOLS_STRIP_CR=1 — the wrapper adds nothing: a CR the tool wrote itself reaches every sink"
TUtil.new uC cr_tool
uC._textMode = 1
__TUTIL_TOOLS_STRIP_CR=1
sinks_of uC
if [[ "$S_RC" == "00000" && "$FIRST" == "a 1$CR" && "$COUNT" == "4" ]] \
   && arr_is GOT "a 1$CR" "p${CR}q$CR" "b 2$CR$CR" "c$CR" \
   && arr_is CB_RECS "${GOT[@]}" && arr_is TTM_RECS "${GOT[@]}"; then
    kt_test_pass "no -c: the tool's bytes, as on cygwin/msys before L2.7-C"
else
    kt_test_fail "rc=$S_RC got=$(arr_show GOT) first=$(printf %q "$FIRST")"
fi

kt_test_start "C: __TUTIL_TOOLS_STRIP_CR=1 — \`run\` is byte-identical to the tool and runs it in THIS shell (no filter)"
uC.cmd = pid_tool
rm -f "$TMP/pid"
uC.run > "$TMP/c.out"
p="$(< "$TMP/pid")"
if [[ "$p" == "$BASHPID" && "$(od -c < "$TMP/c.out")" == "$(printf 'z\r\n' | od -c)" ]]; then
    kt_test_pass "pid $p == this shell; 'z\\r\\n' untouched"
else
    kt_test_fail "tool pid=$p shell=$BASHPID od='$(od -c < "$TMP/c.out" | tr '\n' '|')'"
fi
__TUTIL_TOOLS_STRIP_CR="$NATIVE_AT_LOAD"
uC.delete

# ===========================================================================
kt_test_section "D. NUL records, and \`crlf\` together with text mode"
# ===========================================================================

kt_test_start "D: \`nul = 1\` on the strip path — a NUL record is not a line, its CR stays ('x\\r' 'y\\r')"
TUtil.new uD nul_tool
uD._textMode = 1
uD.nul = 1
__TUTIL_TOOLS_STRIP_CR=0
GOT=()
rc=0; uD.toArray GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT "x$CR" "y$CR"; then
    kt_test_pass "no -c with -0"
else
    kt_test_fail "rc=$rc got=$(arr_show GOT)"
fi
uD.delete

kt_test_start "D: \`crlf = 1\` + text mode on the strip path strips exactly ONE CR ('b 2\\r\\r' -> 'b 2\\r')"
TUtil.new uD cr_tool
uD._textMode = 1
uD.crlf = 1
GOT=()
rc=0; uD.toArray GOT || rc=$?
if [[ $rc -eq 0 ]] && arr_is GOT "a 1" "p${CR}q" "b 2$CR" "c"; then
    kt_test_pass "one -c for both reasons"
else
    kt_test_fail "rc=$rc got=$(arr_show GOT)"
fi
__TUTIL_TOOLS_STRIP_CR="$NATIVE_AT_LOAD"
uD.delete

# ===========================================================================
kt_test_section "E. \`run\` on the strip path under set -euo pipefail"
# ===========================================================================

kt_test_start "E: a child under \`set -euo pipefail\`: tool rc 3 -> \`u.run || rc=\$?\` is 1, lastRc 3, the script reaches its end"
cat > "$TMP/e.sh" <<EOF
set -euo pipefail
__TUTIL_TOOLS_STRIP_CR=0
source "$UNIT"
t3() { printf 'a\r\n'; return 3; }
t0() { printf 'b\r\n'; return 0; }
TUtil.new u t3
u._textMode = 1
rc=0; u.run > /dev/null || rc=\$?
u.lastRc; lr="\$RESULT"
u.cmd = t0
r0=0; out="\$(u.run)" || r0=\$?
printf 'rc=%s lr=%s r0=%s out=%s END\n' "\$rc" "\$lr" "\$r0" "\$out"
EOF
# stdout only: the child's stderr is not this case's subject (and on FreeBSD
# kklass itself writes a line there today — an L3 item, not the CR contract).
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
res="$("$KT_TIMEOUT" -k 10 60 "$BASH" "$TMP/e.sh" 2>"$TMP/e.err")"
if [[ "$res" == "rc=1 lr=3 r0=0 out=b END" ]]; then
    kt_test_pass "$res"
else
    kt_test_fail "res=$(printf %q "$res") err=$(head -c 300 "$TMP/e.err" | tr '\n' '|')"
fi
fi   # kt_need_timeout

# ===========================================================================
kt_test_section "F. the filters themselves (round 2): nul, a failing filter, the stdin filter, -u"
# ===========================================================================

kt_test_start "F: \`run\` with \`nul = 1\` on the strip path is NOT filtered (records are not lines) — the tool's bytes"
TUtil.new uF nul_tool
uF._textMode = 1
uF.nul = 1
__TUTIL_TOOLS_STRIP_CR=0
got="$(uF.run | od -c)"
__TUTIL_TOOLS_STRIP_CR="$NATIVE_AT_LOAD"
if [[ "$got" == "$(nul_tool | od -c)" ]]; then
    kt_test_pass "the NUL records and their CRs, untouched"
else
    kt_test_fail "od='${got//$'\n'/|}'"
fi
uF.delete

# A sed that fails: a child whose PATH starts with a fake `sed` exiting 4.
mkdir -p "$TMP/fakesed"
printf '#!/bin/sh\ncat >/dev/null\nexit 4\n' > "$TMP/fakesed/sed"
chmod +x "$TMP/fakesed/sed"
cat > "$TMP/f.sh" <<EOF2
__TUTIL_TOOLS_STRIP_CR=0
source "$UNIT"
PATH="$TMP/fakesed:\$PATH"
t0() { printf 'a\r\n'; return 0; }
t3() { printf 'a\r\n'; return 3; }
TUtil.new u t0
u._textMode = 1
VERBOSE_KKLASS=debug
rc=0; out="\$(u.run 2>"$TMP/f.err")"; u.run >/dev/null 2>"$TMP/f.err" || rc=\$?
VERBOSE_KKLASS=
u.lastRc; lr="\$RESULT"
nerr=\$(grep -c 'CR filter (sed) exited 4' "$TMP/f.err")
u.cmd = t3
r3=0; u.run >/dev/null 2>/dev/null || r3=\$?
u.lastRc; l3="\$RESULT"
s0=0; printf 'q\r\n' | tutil._crStdin cat >/dev/null 2>/dev/null || s0=\$?
printf 'rc=%s lr=%s nerr=%s out=[%s] r3=%s l3=%s stdin=%s END\n' "\$rc" "\$lr" "\$nerr" "\$out" "\$r3" "\$l3" "\$s0"
EOF2
kt_test_start "F: a CR filter that FAILS (sed exit 4) is not silent — tool ok: lastRc 2, rc 1, one debug line; tool rc 3 wins; the stdin filter answers 2"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
res="$("$KT_TIMEOUT" -k 10 60 "$BASH" "$TMP/f.sh" 2>/dev/null)"
if [[ "$res" == "rc=1 lr=2 nerr=1 out=[] r3=1 l3=3 stdin=2 END" ]]; then
    kt_test_pass "$res"
else
    kt_test_fail "res=$(printf %q "$res")"
fi
fi   # kt_need_timeout

kt_test_start "F: \`tutil._crStdin CMD\` — the tool reads LF lines; its own rc comes back; SIGPIPE from a tool that stops reading is not an error"
got="$(printf 'x\r\ny\r\n' | tutil._crStdin cat | od -c)"
r1=0; printf 'x\r\n' | tutil._crStdin false || r1=$?
r2=0; yes 2>/dev/null | head -c 200000 | tutil._crStdin head -n 1 >/dev/null || r2=$?
if [[ "$got" == "$(printf 'x\ny\n' | od -c)" && $r1 -eq 1 && $r2 -eq 0 ]]; then
    kt_test_pass "LF lines; false -> 1; head -n 1 -> 0"
else
    kt_test_fail "od='${got//$'\n'/|}' false=$r1 head=$r2"
fi

kt_test_start "F: the filter's sed gets \`-u\` exactly when this sed accepts it (probed once, on first use)"
want=""
if LC_ALL=C command sed -u -e '' </dev/null >/dev/null 2>&1; then want="-u"; fi
unset __TUTIL_SED_OPTS_DONE
tutil._sedOpts
first="${__TUTIL_SED_OPTS[*]}"
__TUTIL_SED_OPTS=( sentinel )
tutil._sedOpts
if [[ "$first" == "$want" && "${__TUTIL_SED_OPTS[*]}" == "sentinel" ]]; then
    kt_test_pass "opts=[$first], not probed again"
else
    kt_test_fail "first=[$first] want=[$want] second=[${__TUTIL_SED_OPTS[*]}]"
fi
unset __TUTIL_SED_OPTS_DONE
tutil._sedOpts
