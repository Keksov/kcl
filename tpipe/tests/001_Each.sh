#!/bin/bash
# 001_Each.sh — tpipe P0: the engine + TPipe.each.
#
# No upstream: TPipe is a kcl addition (PLAN.md §1.2). The oracle is bash
# itself — every answer is compared with what a bare `while read` over the same
# producer would give.
#
# Pinned facts (PLAN.md §3), by section:
#   A  the harness runs the file at BASH_SUBSHELL 0 (the D6 warnings below pin
#      the value, so this has to be true for the assertions to mean anything)
#   B  F3  `exec {fd}< <(cmd); pid=$!; wait $pid` yields the producer's REAL rc:
#          a `bash -c ... exit 4` producer, a shell FUNCTION producer (6), and a
#          missing command (127). RESULT keeps the records delivered (the named
#          deviation from kcl §1.2, PLAN §2.4).
#   C      delivery + F10 (unterminated tail, final empty record) + records are
#          DATA (exotic round-trip byte-exact: '', -e, -n, backslash, $(…), *,
#          ], tab, CR, UTF-8, 4 KiB)
#   D  F13 TPIPE_INDEX is 1-based per sink call and nested-safe
#   E  F9  the callback matrix: plain function / instance member / static member,
#          called from top level AND from inside another instance member; the
#          callback's own rc is ignored (D2)
#   F      malformed calls are rc 2 + RESULT='' and run NOTHING (§2.5 order)
#   G  F1  the stdin form inside a subshell is NOT refused (D6 final Q1): the
#          records are delivered, the object in the PARENT is unchanged, and
#          exactly ONE `kk.warn` line — the stdin template — is printed when the
#          callback is an instance member, with the debug switch on OR off; a
#          plain-function callback in the same position is silent
#   H  F2  the same call under `shopt -s lastpipe` delivers and mutates;
#          PIPESTATUS[0] is the producer's; lastRc stays -1 (no producer of ours)
#   I      the two README forms that exist at P0 (the real pipe under lastpipe,
#          and the `--` form) with a plain function and with `r.onLine`
#   J  Q7  `each` NEVER prints: under `$( )` and on the LHS of a pipe the bytes
#          are exactly the callback's, while a direct call still sets RESULT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$SCRIPT_DIR/.."
source "$TP_DIR/tpipe.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "001: TPipe.each — engine, callbacks, TPIPE_INDEX, D6 final (P0/P3)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# arr_is ARRNAME expected... — rc 0 iff the array holds exactly these elements
# in this order. Fork-free and byte-exact, so exotic records compare correctly.
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

REC=()
rec()   { REC+=( "$1" ); return 0; }             # the plain-function callback
noop()  { return 0; }
recix() { REC+=( "$TPIPE_INDEX:$1" ); return 0; }
recrc() { REC+=( "$1" ); return 7; }             # a callback with a non-zero rc

# a callback whose side effect survives a subshell — the only way to prove that
# a refused call never ran the callback when the call itself is in a pipe RHS.
CBLOG="$TMP/cb.log"
recfile() { printf '%s\n' "$1" >> "$CBLOG"; return 0; }

# producers
p3()      { printf 'a\nb\nc\n'; }
pfail6()  { printf 'a\n'; return 6; }
STARTED="$TMP/started.flag"
pmark()   { : > "$STARTED"; printf 'a\n'; }

# an instance callback (F9) and a class that calls a sink from INSIDE a member
class TRec
    public
        var         Log
        var         N
        constructor Create
        proc        onLine
end

TRec.Create() { Log=""; N=0; return 0; }
TRec.onLine() { Log="$Log$1|"; N=$(( N + 1 )); return 0; }
build TRec

class TDriver
    public
        var         Seen
        constructor Create
        proc        drive
end

TDriver.Create() { Seen=""; return 0; }
TDriver.drive()  {                       # $1 = callback name, $2.. = producer
    local __cb="$1"; shift
    TPipe.each "$__cb" -- "$@"
    Seen="$RESULT"
    return 0
}
build TDriver

# a STATIC-member callback
SREC=()
class TSink
    public
        static proc onLine
end
TSink.onLine() { SREC+=( "$1" ); return 0; }
build TSink

# An INSTANCE callback whose side effect ALSO survives a subshell: `N` dies with
# the subshell, the log FILE does not. That is what separates "the records were
# delivered" from "the mutation reached the parent" in a pipe-RHS case (§G),
# which the D1 refusal used to make impossible to observe.
class TRecLog
    public
        var         N
        constructor Create
        proc        onLine
end
TRecLog.Create() { N=0; return 0; }
TRecLog.onLine() { N=$(( N + 1 )); printf '%s\n' "$1" >> "$CBLOG"; return 0; }
build TRecLog

# ===========================================================================
kt_test_section "A. harness environment"
# ===========================================================================

kt_test_start "the test file runs at BASH_SUBSHELL 0 (the D1 message pins the value)"
if [[ "$BASH_SUBSHELL" == "0" ]]; then
    kt_test_pass "top level, not a subshell"
else
    kt_test_fail "BASH_SUBSHELL=$BASH_SUBSHELL at file top level"
fi

# ===========================================================================
kt_test_section "B. F3 — the producer's real rc reaches lastRc"
# ===========================================================================

kt_test_start "F3: external producer exiting 4 -> RESULT 1, rc 1, lastRc 4"
REC=(); RESULT="sentinel"
TPipe.each rec -- "$BASH" -c 'printf "a\n"; exit 4'; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "1" && $rc -eq 1 && "$lr" == "4" ]] && arr_is REC "a"; then
    kt_test_pass "rc 1 with the count KEPT in RESULT (named deviation)"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' REC=(${REC[*]})"
fi

kt_test_start "F3: shell-FUNCTION producer exiting 6 -> lastRc 6"
REC=()
TPipe.each rec -- pfail6; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "1" && $rc -eq 1 && "$lr" == "6" ]] && arr_is REC "a"; then
    kt_test_pass "a bash function is a legal producer and its rc survives"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' REC=(${REC[*]})"
fi

kt_test_start "F3: missing command -> 0 records, rc 1, lastRc 127"
REC=()
TPipe.each rec -- tpipe_no_such_command_9d3f 2>/dev/null; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "0" && $rc -eq 1 && "$lr" == "127" ]] && arr_is REC; then
    kt_test_pass "no pre-check; the procsub reports 127 through wait"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' REC=(${REC[*]})"
fi

kt_test_start "a successful producer leaves rc 0 and lastRc 0"
REC=()
TPipe.each rec -- p3; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 && "$lr" == "0" ]] && arr_is REC "a" "b" "c"; then
    kt_test_pass "3 records, rc 0, lastRc 0"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' REC=(${REC[*]})"
fi

# ===========================================================================
kt_test_section "C. delivery, F10, and records as DATA"
# ===========================================================================

kt_test_start "F10: an unterminated last record is delivered (printf 'a\\nb')"
REC=()
TPipe.each rec -- printf 'a\nb'; rc=$?
res="$RESULT"
if [[ "$res" == "2" && $rc -eq 0 ]] && arr_is REC "a" "b"; then
    kt_test_pass "2 records, the tail without a terminator included"
else
    kt_test_fail "RESULT='$res' rc=$rc REC=(${REC[*]})"
fi

kt_test_start "F10: a final EMPTY record after the terminator is delivered"
REC=()
TPipe.each rec -- printf 'a\n\n'; rc=$?
res="$RESULT"
if [[ "$res" == "2" && $rc -eq 0 ]] && arr_is REC "a" ""; then
    kt_test_pass "2 records, the second empty"
else
    kt_test_fail "RESULT='$res' rc=$rc REC=(${REC[*]})"
fi

kt_test_start "an empty producer delivers nothing: RESULT 0, rc 0, callback never called"
REC=()
TPipe.each rec -- printf ''; rc=$?
res="$RESULT"
if [[ "$res" == "0" && $rc -eq 0 ]] && arr_is REC; then
    kt_test_pass "0 records, rc 0"
else
    kt_test_fail "RESULT='$res' rc=$rc REC=(${REC[*]})"
fi

# the exotic matrix — records are DATA and must round-trip byte-exact.
# NUL is the documented carve-out (no bash variable can hold it).
printf -v BIG '%0*d' 4096 7
EXOTIC=( "" "-e" "-n" "-neE" 'back\slash' '$(echo pwned)' '`id`' "*" "]" \
         "a b" $'ta\tb' $'cr\r' "café" "日本語" "$BIG" )
pexotic() { printf '%s\n' "${EXOTIC[@]}"; }

kt_test_start "records are data: the exotic matrix round-trips byte-exact through each"
REC=()
TPipe.each rec -- pexotic; rc=$?
res="$RESULT"
if [[ "$res" == "${#EXOTIC[@]}" && $rc -eq 0 ]] && arr_is REC "${EXOTIC[@]}"; then
    kt_test_pass "${#EXOTIC[@]} exotic records verbatim (CR kept: no -c)"
else
    kt_test_fail "RESULT='$res' rc=$rc got ${#REC[@]} records"
fi

kt_test_start "the each answer equals a bare \`while read\` over the same producer"
ORACLE=()
while IFS= read -r ln || [[ -n "$ln" ]]; do ORACLE+=( "$ln" ); done < <(pexotic)
REC=()
TPipe.each rec -- pexotic
if arr_is REC "${ORACLE[@]}" && [[ "$RESULT" == "${#ORACLE[@]}" ]]; then
    kt_test_pass "identical to the bash oracle (${#ORACLE[@]} records)"
else
    kt_test_fail "oracle ${#ORACLE[@]} vs each ${#REC[@]} / RESULT=$RESULT"
fi

# ===========================================================================
kt_test_section "D. F13 — TPIPE_INDEX"
# ===========================================================================

kt_test_start "F13: TPIPE_INDEX is 1-based and counts this sink's records"
REC=()
TPipe.each recix -- p3
if arr_is REC "1:a" "2:b" "3:c"; then
    kt_test_pass "1:a 2:b 3:c"
else
    kt_test_fail "REC=(${REC[*]})"
fi

# nested: the outer callback runs a whole inner sink on its FIRST record only.
NEST_OUT=(); NEST_IN=()
inner_cb() { NEST_IN+=( "$TPIPE_INDEX:$1" ); return 0; }
outer_cb() {
    NEST_OUT+=( "$TPIPE_INDEX:$1" )
    if [[ "$TPIPE_INDEX" == "1" ]]; then
        TPipe.each inner_cb -- printf 'x\ny\n'
    fi
    return 0
}

kt_test_start "F13: a nested sink has its OWN TPIPE_INDEX and the outer one is restored"
NEST_OUT=(); NEST_IN=()
TPipe.each outer_cb -- p3
if arr_is NEST_OUT "1:a" "2:b" "3:c" && arr_is NEST_IN "1:x" "2:y"; then
    kt_test_pass "outer 1..3 and inner 1..2, neither disturbed"
else
    kt_test_fail "outer=(${NEST_OUT[*]}) inner=(${NEST_IN[*]})"
fi

# TPIPE_INDEX has a load-time global (0) beside __TPIPE_STOP and __TPIPE_RC, so
# that a shared callback which reads the ordinal is usable OUTSIDE a sink too:
# without it `set -u` aborts the caller on the very first read (PLAN §6 — the
# globals of these names exist only so `set -u` never trips). The probe runs in
# a CHILD under `set -eu`, so a regression fails this case instead of killing
# the whole test file.
IXCHILD="$TMP/index_child.sh"
cat > "$IXCHILD" <<'IX_EOF'
#!/bin/bash
set -eu
source "$1/tpipe.sh"
ix() { printf 'ix=%s;' "$TPIPE_INDEX"; return 0; }
ix                                       # outside any sink: the load-time global
TPipe.each ix -- printf 'a\nb\n'         # inside a sink: the frame-local, 1..n
printf 'n=%s\n' "$RESULT"
IX_EOF

kt_test_start "TPIPE_INDEX is readable outside any sink under set -u (0), and is 1..n inside one"
ixout="$(timeout 20 "$BASH" "$IXCHILD" "$TP_DIR" 2>"$TMP/index.err")"; ixrc=$?
if [[ $ixrc -eq 0 && "$ixout" == "ix=0;ix=1;ix=2;n=2" && ! -s "$TMP/index.err" ]]; then
    kt_test_pass "ix=0 outside, 1..2 inside, no diagnostic"
else
    kt_test_fail "rc=$ixrc out='$ixout' err='$(cat "$TMP/index.err")'"
fi

kt_test_start "a nested sink leaves the OUTER RESULT/lastRc as the outer sink's own"
NEST_OUT=(); NEST_IN=()
TPipe.each outer_cb -- p3; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 && "$lr" == "0" ]]; then
    kt_test_pass "outer RESULT 3 after an inner sink of 2"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr'"
fi

# ===========================================================================
kt_test_section "E. F9 — the callback matrix"
# ===========================================================================

kt_test_start "F9: an INSTANCE member keeps its state (this is the whole point of the unit)"
TRec.new R
TPipe.each R.onLine -- p3; rc=$?
res="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 && "$(R.N)" == "3" && "$(R.Log)" == "a|b|c|" ]]; then
    kt_test_pass "R.N=3, R.Log='a|b|c|' in THIS shell"
else
    kt_test_fail "RESULT='$res' rc=$rc N='$(R.N)' Log='$(R.Log)'"
fi
R.delete

kt_test_start "F9: a STATIC member is a legal callback"
SREC=()
TPipe.each TSink.onLine -- p3; rc=$?
if [[ "$RESULT" == "3" && $rc -eq 0 ]] && arr_is SREC "a" "b" "c"; then
    kt_test_pass "TSink.onLine received all 3 records"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc SREC=(${SREC[*]})"
fi

kt_test_start "F9: a sink called from INSIDE another instance member keeps the callback's state"
TRec.new R2
TDriver.new DRV
DRV.drive R2.onLine p3
if [[ "$(DRV.Seen)" == "3" && "$(R2.N)" == "3" && "$(R2.Log)" == "a|b|c|" ]]; then
    kt_test_pass "R2 mutated from inside TDriver.drive; DRV saw RESULT=3"
else
    kt_test_fail "Seen='$(DRV.Seen)' N='$(R2.N)' Log='$(R2.Log)'"
fi
R2.delete
DRV.delete

kt_test_start "D2: the callback's own exit status is IGNORED (a predicate may say 1)"
REC=()
TPipe.each recrc -- p3; rc=$?
if [[ "$RESULT" == "3" && $rc -eq 0 ]] && arr_is REC "a" "b" "c"; then
    kt_test_pass "callback rc 7 on every record, sink still rc 0 / 3 records"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc REC=(${REC[*]})"
fi

# ===========================================================================
kt_test_section "F. malformed calls -> rc 2, RESULT='', nothing run"
# ===========================================================================

kt_test_start "a callback name that is not a function is rc 2 and the producer is NOT started"
rm -f "$STARTED"
RESULT="sentinel"
TPipe.each tpipe_dangling_cb_7a1 -- pmark; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -e "$STARTED" ]]; then
    kt_test_pass "rc 2, RESULT='', producer never ran"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' started=$( [[ -e "$STARTED" ]] && echo yes || echo no )"
fi

kt_test_start "a missing callback operand is rc 2"
RESULT="sentinel"
TPipe.each; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" ]]; then
    kt_test_pass "rc 2, RESULT=''"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "an unknown flag is rc 2 and the producer is NOT started"
rm -f "$STARTED"
RESULT="sentinel"
TPipe.each -x rec -- pmark; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -e "$STARTED" ]]; then
    kt_test_pass "rc 2 before anything runs"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "a flag written AFTER the callback is rc 2 (only \`--\` may follow it)"
rm -f "$STARTED"
RESULT="sentinel"
REC=()
TPipe.each rec -c -- pmark; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -e "$STARTED" ]] && arr_is REC; then
    kt_test_pass "the late flag is caught, not silently taken as a producer word"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' REC=(${REC[*]})"
fi

kt_test_start "any other word after the callback is rc 2"
RESULT="sentinel"
TPipe.each rec junk -- p3; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" ]]; then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "\`--\` with an EMPTY producer argv is rc 2 (not 'read stdin')"
RESULT="sentinel"
REC=()
TPipe.each rec -- <<< $'a\nb'; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" ]] && arr_is REC; then
    kt_test_pass "rc 2, stdin left alone"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' REC=(${REC[*]})"
fi

# ===========================================================================
kt_test_section "G. F1 — the stdin form inside a subshell: delivered + warned (D6 final)"
# ===========================================================================

# The stdin template, byte-exact (PLAN §2.4). `WHAT` for `each` is
# "the instance member CB runs" with CB spelled exactly as the caller wrote it,
# and the suggested form carries the operand LABEL `CB`, not the callback name.
W_STDIN_EACH='Warning: TPipe.each: the instance member RL.onLine runs inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; in a pipeline use `shopt -s lastpipe` (non-interactive scripts) or the `TPipe.each CB -- CMD ...` form at top level; if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1'

ERRF="$TMP/d6.err"

# read_lines FILE -> ERRL=( … ) — the whole file, one element per line.
read_lines() {
    ERRL=()
    local __ln
    while IFS= read -r __ln || [[ -n "$__ln" ]]; do ERRL+=( "$__ln" ); done < "$1"
    return 0
}

# count_lines FILE -> CBN
count_lines() {
    CBN=0
    local __ln
    while IFS= read -r __ln; do CBN=$(( CBN + 1 )); done < "$1"
    return 0
}

TRecLog.new RL

kt_test_start "F1: \`producer | TPipe.each r.onLine\` DELIVERS the records (nothing is refused)"
# D6 final Q1: the D1 rc 2 is gone. The callback runs — in the subshell — so its
# file side effect is visible here while its object mutation is not.
: > "$CBLOG"
: > "$ERRF"
{ printf 'x\ny\n' | TPipe.each RL.onLine; rc=${PIPESTATUS[1]}; } 2>"$ERRF" >/dev/null
count_lines "$CBLOG"
if [[ $rc -eq 0 && $CBN -eq 2 ]]; then
    kt_test_pass "rc 0, both records reached the callback"
else
    kt_test_fail "rc=$rc callback lines=$CBN"
fi

kt_test_start "F1: …and the object in the PARENT shell is unchanged — that is what the warning is for"
if [[ "$(RL.N)" == "0" ]]; then
    kt_test_pass "RL.N is still 0 in this shell"
else
    kt_test_fail "RL.N='$(RL.N)'"
fi

kt_test_start "F1: exactly ONE warning line, the stdin template, VERBATIM"
read_lines "$ERRF"
if [[ ${#ERRL[@]} -eq 1 && "${ERRL[0]}" == "$W_STDIN_EACH" ]]; then
    kt_test_pass "one line, verbatim"
else
    kt_test_fail "${#ERRL[@]} line(s); first='${ERRL[0]:-}'"
fi

kt_test_start "F1: the warning is printed with the DEBUG switch OFF — it is not a debug line"
# The run above already had the switch off; this pins the other direction too,
# so a regression that routed the line through kk.debug cannot pass.
: > "$ERRF"
VERBOSE_KKLASS=debug
{ printf 'x\ny\n' | TPipe.each RL.onLine; } 2>"$ERRF" >/dev/null
VERBOSE_KKLASS=
read_lines "$ERRF"
if [[ ${#ERRL[@]} -eq 1 && "${ERRL[0]}" == "$W_STDIN_EACH" ]]; then
    kt_test_pass "the same single line under debug"
else
    kt_test_fail "${#ERRL[@]} line(s); first='${ERRL[0]:-}'"
fi

kt_test_start "F1: \`-s\` silences it, and the records are still delivered"
: > "$CBLOG"
: > "$ERRF"
{ printf 'x\ny\n' | TPipe.each -s RL.onLine; rc=${PIPESTATUS[1]}; } 2>"$ERRF" >/dev/null
count_lines "$CBLOG"
if [[ $rc -eq 0 && $CBN -eq 2 && ! -s "$ERRF" ]]; then
    kt_test_pass "2 records, no stderr"
else
    kt_test_fail "rc=$rc lines=$CBN stderr='$(cat "$ERRF")'"
fi

kt_test_start "F1: \`VERBOSE_KKLASS=quiet\` silences it too (the corpus-wide off switch)"
: > "$ERRF"
VERBOSE_KKLASS=quiet
{ printf 'x\ny\n' | TPipe.each RL.onLine; } 2>"$ERRF" >/dev/null
VERBOSE_KKLASS=
if [[ ! -s "$ERRF" ]]; then
    kt_test_pass "no stderr under quiet"
else
    kt_test_fail "stderr: $(cat "$ERRF")"
fi

kt_test_start "a PLAIN-FUNCTION callback in the same pipe RHS delivers and says NOTHING"
# Q2: a plain function may print, count into a file or answer through the
# producer's stdout — none of which a subshell loses — so there is nothing to
# warn about and the line would be noise on every `cmd | TPipe.each fmt`.
: > "$CBLOG"
: > "$ERRF"
{ printf 'x\ny\n' | TPipe.each recfile; rc=${PIPESTATUS[1]}; } 2>"$ERRF" >/dev/null
count_lines "$CBLOG"
if [[ $rc -eq 0 && $CBN -eq 2 && ! -s "$ERRF" ]]; then
    kt_test_pass "2 records, not a word on stderr"
else
    kt_test_fail "rc=$rc lines=$CBN stderr='$(cat "$ERRF")'"
fi

kt_test_start "F1: the same inside \$( ) — the OTHER accidental subshell, same stdin template"
: > "$CBLOG"
: > "$ERRF"
out="$(TPipe.each RL.onLine 2>"$ERRF" <<< $'x\ny')"; rc=$?
count_lines "$CBLOG"
read_lines "$ERRF"
if [[ $rc -eq 0 && $CBN -eq 2 && -z "$out" && ${#ERRL[@]} -eq 1 && "${ERRL[0]}" == "$W_STDIN_EACH" ]]; then
    kt_test_pass "delivered, nothing on stdout (Q7), one verbatim warning"
else
    kt_test_fail "rc=$rc lines=$CBN out='$out' warn='${ERRL[0]:-}'"
fi

RL.delete

kt_test_start "the stdin form OUTSIDE any subshell is fine (BASH_SUBSHELL 0)"
REC=()
TPipe.each rec <<< $'a\nb\nc'; rc=$?
res="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 ]] && arr_is REC "a" "b" "c"; then
    kt_test_pass "3 records read from a here-string"
else
    kt_test_fail "RESULT='$res' rc=$rc REC=(${REC[*]})"
fi

kt_test_start "after a stdin-form sink lastRc is -1 (there was no producer of ours)"
TPipe.each rec -- p3            # sets lastRc 0 first
TPipe.each noop <<< $'a\nb'
TPipe.lastRc; lr="$RESULT"
if [[ "$lr" == "-1" ]]; then
    kt_test_pass "lastRc reset to -1"
else
    kt_test_fail "lastRc='$lr'"
fi

# ===========================================================================
kt_test_section "H. F2 — the same call under \`shopt -s lastpipe\`"
# ===========================================================================

shopt -s lastpipe

kt_test_start "F2: under lastpipe the pipe RHS runs in THIS shell and delivers"
REC=()
RESULT=""
printf 'a\nb\nc\n' | TPipe.each rec
rc=${PIPESTATUS[1]}
res="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 ]] && arr_is REC "a" "b" "c"; then
    kt_test_pass "3 records, rc 0, state kept"
else
    kt_test_fail "RESULT='$res' rc=$rc REC=(${REC[*]})"
fi

kt_test_start "F2: under lastpipe an INSTANCE callback keeps its mutations"
TRec.new R3
printf 'a\nb\nc\n' | TPipe.each R3.onLine
if [[ "$(R3.N)" == "3" && "$(R3.Log)" == "a|b|c|" ]]; then
    kt_test_pass "R3.N=3 after the real pipe"
else
    kt_test_fail "N='$(R3.N)' Log='$(R3.Log)'"
fi
R3.delete

kt_test_start "F2: PIPESTATUS[0] is the producer's own rc and lastRc stays -1"
REC=()
TPipe.each noop -- printf 'z\n'          # lastRc is 0 going in
"$BASH" -c 'printf "a\n"; exit 3' | TPipe.each rec
PS=( "${PIPESTATUS[@]}" )       # one command: any other command resets PIPESTATUS
ps0=${PS[0]}; ps1=${PS[1]}
TPipe.lastRc; lr="$RESULT"
if [[ "$ps0" == "3" && "$ps1" == "0" && "$lr" == "-1" && "$RESULT" == "-1" ]] && arr_is REC "a"; then
    kt_test_pass "PIPESTATUS=(3 0), lastRc -1 — read PIPESTATUS for the stdin form"
else
    kt_test_fail "PIPESTATUS=($ps0 $ps1) lastRc='$lr' REC=(${REC[*]})"
fi

shopt -u lastpipe

# ===========================================================================
kt_test_section "I. the README forms"
# ===========================================================================

kt_test_start "form 1 (real pipe + lastpipe) and form 2 (\`--\`) agree, plain function"
shopt -s lastpipe
REC=()
p3 | TPipe.each rec
FORM1=( "${REC[@]}" ); f1res="$RESULT"
shopt -u lastpipe
REC=()
TPipe.each rec -- p3
FORM2=( "${REC[@]}" ); f2res="$RESULT"
if [[ "$f1res" == "3" && "$f2res" == "3" ]] && arr_is FORM1 "a" "b" "c" && arr_is FORM2 "a" "b" "c"; then
    kt_test_pass "both forms deliver the same 3 records"
else
    kt_test_fail "form1=(${FORM1[*]}) RESULT=$f1res / form2=(${FORM2[*]}) RESULT=$f2res"
fi

kt_test_start "form 1 and form 2 agree with an INSTANCE callback (r.onLine)"
shopt -s lastpipe
TRec.new RA
p3 | TPipe.each RA.onLine
a_log="$(RA.Log)"; a_n="$(RA.N)"
shopt -u lastpipe
TRec.new RB
TPipe.each RB.onLine -- p3
b_log="$(RB.Log)"; b_n="$(RB.N)"
if [[ "$a_log" == "a|b|c|" && "$a_n" == "3" && "$b_log" == "$a_log" && "$b_n" == "$a_n" ]]; then
    kt_test_pass "both forms mutate the object identically"
else
    kt_test_fail "pipe: N=$a_n Log='$a_log' / --: N=$b_n Log='$b_log'"
fi
RA.delete
RB.delete

# ===========================================================================
kt_test_section "J. Q7 — \`each\` never prints; its stdout is the callback's"
# ===========================================================================
# D6 final Q7. `each` is the one member of the unit that does not go through
# `tpipe._ret`: its stdout belongs to the CALLBACK, so composing it with `$( )`
# or with a pipe must yield exactly the callback's bytes. Before the ruling both
# positions got the record count glued on ('3' here, 'F:aF:bF:c3' there).

fmt() { printf 'F:%s\n' "$1"; return 0; }

kt_test_start "Q7: \`x=\$(TPipe.each fmt -- cmd)\` is EXACTLY fmt's output — no record count"
x="$(TPipe.each fmt -- p3 2>/dev/null)"; rc=$?
if [[ "$x" == $'F:a\nF:b\nF:c' && $rc -eq 0 ]]; then
    kt_test_pass "three formatted lines and nothing else"
else
    kt_test_fail "x='$x' rc=$rc"
fi

kt_test_start "Q7: \`TPipe.each fmt -- cmd | cat\` likewise"
x="$(TPipe.each fmt -- p3 2>/dev/null | cat)"; rc=$?
if [[ "$x" == $'F:a\nF:b\nF:c' && $rc -eq 0 ]]; then
    kt_test_pass "the LHS of a pipe carries only the callback's bytes"
else
    kt_test_fail "x='$x' rc=$rc"
fi

kt_test_start "Q7: a DIRECT call still sets RESULT to the record count"
RESULT="sentinel"
OUTF="$TMP/q7.out"
TPipe.each noop -- p3 >"$OUTF" 2>/dev/null; rc=$?
if [[ "$RESULT" == "3" && $rc -eq 0 && ! -s "$OUTF" ]]; then
    kt_test_pass "RESULT=3, rc 0, nothing on stdout"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc stdout='$(cat "$OUTF")'"
fi

kt_test_start "Q7: an rc 2 path leaves RESULT '' and prints nothing, in a subshell too"
RESULT="sentinel"
x="$(TPipe.each tpipe_no_such_cb_j1 -- p3 2>/dev/null)"; rc=$?
TPipe.each tpipe_no_such_cb_j1 -- p3 2>/dev/null; drc=$?
if [[ $rc -eq 2 && -z "$x" && $drc -eq 2 && -z "$RESULT" ]]; then
    kt_test_pass "rc 2 both ways, RESULT='', stdout empty"
else
    kt_test_fail "subst rc=$rc x='$x' / direct rc=$drc RESULT='$RESULT'"
fi

kt_test_start "the \`--\` form under \$( ) with a PLAIN callback delivers and is silent (Q2)"
: > "$CBLOG"
: > "$ERRF"
x="$(TPipe.each recfile -- p3 2>"$ERRF")"
count_lines "$CBLOG"
if [[ -z "$x" && $CBN -eq 3 && ! -s "$ERRF" ]]; then
    kt_test_pass "3 records delivered inside \$( ), no bytes, no warning"
else
    kt_test_fail "x='$x' cb lines=$CBN stderr='$(cat "$ERRF")'"
fi
