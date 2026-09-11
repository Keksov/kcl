#!/bin/bash
# 002_Stop.sh — tpipe P0: TPipe.stop, the close/kill/wait path, TPipe.lastRc.
#
# Pinned facts (PLAN.md §3), by section:
#   A  lastRc is -1 before any sink has run (this section MUST stay first)
#   B  F4  closing the fd (plus the kill -TERM behind it) ends an infinite
#          producer: a stop on the first record of `yes` returns promptly, with
#          lastRc 141 (SIGPIPE) or 143 (SIGTERM) — see the note at the case.
#          Pinned twice: through `each` + `TPipe.stop` (P0) and through
#          `TPipe.first` (P1 re-points F4/F5 at it, PLAN §3).
#   C  F5  a producer that IGNORES SIGPIPE and then stops writing
#          (`trap '' PIPE; echo a; sleep 8; echo b`) is TERMINATED — without the
#          `kill -TERM` of PLAN §2.3 `wait` blocks for its whole remaining life
#          (8.1 s measured). The whole case runs in a child under `timeout 20` —
#          a cold `source tpipe.sh` alone is ~1 s idle and ~4 s under the
#          threaded runner (measured; a 5 s budget timed out in a master sweep),
#          also through both `each` + `stop` and `first`.
#   D  F6  `$!` clobbered by a callback that starts a job does not affect the
#          captured producer pid
#   E  F12 stop is FRAME-LOCAL: an outer stop requested before an inner sink
#          survives it; a stop inside an inner callback stops only the inner
#          sink; a stray stop outside any sink is harmless
#   F      stop leaves RESULT untouched and always answers rc 0; a stopped sink
#          is rc 0 (the consumer's success, not the producer's failure)
#   G      lastRc is -1 again after a sink that read stdin
#
# B and C run in a CHILD bash under `timeout`, so a regression that hangs
# `wait` fails the case instead of hanging the whole suite. Both give the
# producer `2>/dev/null`: a closed pipe routinely makes it print
# "write error: Broken pipe", which is the PRODUCER's stderr, not TPipe's
# (PLAN §4).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$SCRIPT_DIR/.."
source "$TP_DIR/tpipe.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "002: TPipe.stop / lastRc / the close-kill-wait path (P0)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

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
rec()  { REC+=( "$1" ); return 0; }
noop() { return 0; }
p4()   { printf 'a\nb\nc\nd\n'; }

# ===========================================================================
kt_test_section "A. lastRc before any sink has run"
# ===========================================================================

kt_test_start "lastRc is -1 before any sink has run (RESULT and rc)"
RESULT="sentinel"
TPipe.lastRc; rc=$?
if [[ "$RESULT" == "-1" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT=-1, rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

# ===========================================================================
kt_test_section "B/C. the close-kill-wait path, in a child under timeout"
# ===========================================================================

CHILD="$TMP/stop_child.sh"
cat > "$CHILD" <<'CHILD_EOF'
#!/bin/bash
# $1 = tpipe unit dir, $2 = mode. Prints one line: rc=N res=N lastrc=N us=N
source "$1/tpipe.sh"

stopper() { TPipe.stop; return 0; }

# ignores SIGPIPE and then STOPS WRITING: without the kill -TERM this blocks
# `wait` for the whole `sleep`.
sigpipe_producer() { trap '' PIPE; printf 'a\n'; sleep 8; printf 'b\n'; }

t0="${EPOCHREALTIME/[.,]/}"
rc=0
case "$2" in
    yes)   TPipe.each stopper -- yes 2>/dev/null              || rc=$? ;;
    sigp)  TPipe.each stopper -- sigpipe_producer 2>/dev/null || rc=$? ;;
    fyes)  TPipe.first -- yes 2>/dev/null                     || rc=$? ;;
    fsigp) TPipe.first -- sigpipe_producer 2>/dev/null        || rc=$? ;;
    *)     printf 'bad mode\n' >&2; exit 9 ;;
esac
res="$RESULT"
t1="${EPOCHREALTIME/[.,]/}"
TPipe.lastRc
printf 'rc=%s res=%s lastrc=%s us=%s\n' "$rc" "$res" "$RESULT" "$(( t1 - t0 ))"
CHILD_EOF

# run_child MODE -> sets CH_RC (timeout's rc) and CH_OUT (the child's line)
run_child() {
    CH_OUT="$(timeout 20 "$BASH" "$CHILD" "$TP_DIR" "$1" 2>/dev/null)"
    CH_RC=$?
    return 0
}

# WHICH signal kills `yes` is a race and both answers are correct (PLAN §2.3):
# the stop path is close -> kill -TERM -> wait, so the producer dies of SIGPIPE
# (141) if it attempted a write in that window and of SIGTERM (143) if the kill
# won. Under a loaded master sweep the kill wins on 5.3.9. What this case pins is
# that `wait` RETURNS at all, with one record and rc 0 — not which signal did it.
kt_test_start "F4: a stop on \`yes\` -> 1 record, rc 0, and the producer is dead (lastRc 141 or 143)"
run_child yes
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=1 lastrc=14"[13]" us="* ]]; then
    kt_test_pass "F4: $CH_OUT"
else
    kt_test_fail "F4 (yes): timeout rc=$CH_RC out='$CH_OUT'"
fi

# F5 has no such race: this producer IGNORES SIGPIPE, so only the kill -TERM can
# end it and 143 is the single correct answer.
kt_test_start "F5: a SIGPIPE-ignoring producer that stops writing is TERMINATED (lastRc 143)"
run_child sigp
us="${CH_OUT##*us=}"
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=1 lastrc=143 us="* \
      && "$us" =~ ^[0-9]+$ && $us -lt 1000000 ]]; then
    kt_test_pass "F5: $CH_OUT (under 1 s, not the producer's 8 s)"
else
    kt_test_fail "F5 (SIGPIPE-ignoring): timeout rc=$CH_RC out='$CH_OUT'"
fi

# P1 re-points F4/F5 at `TPipe.first`, which takes the same close-kill-wait path
# for free after its single record (PLAN §3). The each+stop cases above stay:
# they pin the same engine path reached through an explicit TPipe.stop.
kt_test_start "F4 (first): \`TPipe.first -- yes\` returns 'y' in < 250 ms, lastRc 141 or 143"
run_child fyes
us="${CH_OUT##*us=}"
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=y lastrc=14"[13]" us="* \
      && "$us" =~ ^[0-9]+$ && $us -lt 250000 ]]; then
    kt_test_pass "F4 (first): $CH_OUT"
else
    kt_test_fail "F4 (first -- yes): timeout rc=$CH_RC out='$CH_OUT'"
fi

kt_test_start "F5 (first): a SIGPIPE-ignoring producer that stops writing is TERMINATED (lastRc 143)"
run_child fsigp
us="${CH_OUT##*us=}"
if [[ $CH_RC -eq 0 && "$CH_OUT" == "rc=0 res=a lastrc=143 us="* \
      && "$us" =~ ^[0-9]+$ && $us -lt 1000000 ]]; then
    kt_test_pass "F5 (first): $CH_OUT (under 1 s, not the producer's 8 s)"
else
    kt_test_fail "F5 (first, SIGPIPE-ignoring): timeout rc=$CH_RC out='$CH_OUT'"
fi

# ===========================================================================
kt_test_section "D. F6 — \$! clobbered inside the callback"
# ===========================================================================

CLOB=()
clobber_cb() {
    CLOB+=( "$1" )
    ( : ) &                 # a background job: this overwrites $!
    wait $! 2>/dev/null || :
    return 0
}

kt_test_start "F6: a callback that starts a job does not disturb the producer's rc"
TPipe.each clobber_cb -- "$BASH" -c 'printf "a\nb\n"; exit 5'; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "2" && $rc -eq 1 && "$lr" == "5" ]] && arr_is CLOB "a" "b"; then
    kt_test_pass "lastRc is still the producer's 5"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' CLOB=(${CLOB[*]})"
fi

# ===========================================================================
kt_test_section "E. F12 — stop is frame-local"
# ===========================================================================

OUTR=(); INR=(); INRES=""

in_cb()      { INR+=( "$1" ); return 0; }
in_cb_stop() { INR+=( "$1" ); TPipe.stop; return 0; }

# (a) the callback asks the OUTER sink to stop and THEN runs a whole inner sink
out_cb_a() {
    OUTR+=( "$1" )
    if [[ "$TPIPE_INDEX" == "2" ]]; then
        TPipe.stop
        TPipe.each in_cb -- p4
        INRES="$RESULT"
    fi
    return 0
}

# (b) the stop happens inside the INNER callback
out_cb_b() {
    OUTR+=( "$1" )
    if [[ "$TPIPE_INDEX" == "1" ]]; then
        TPipe.each in_cb_stop -- p4
        INRES="$RESULT"
    fi
    return 0
}

kt_test_start "F12(a): an outer stop requested BEFORE an inner sink survives it (outer 2, inner 4)"
OUTR=(); INR=(); INRES=""
TPipe.each out_cb_a -- p4; rc=$?
res="$RESULT"
if [[ "$res" == "2" && $rc -eq 0 && "$INRES" == "4" ]] \
   && arr_is OUTR "a" "b" && arr_is INR "a" "b" "c" "d"; then
    kt_test_pass "outer stopped after record 2, the inner sink ran in full"
else
    kt_test_fail "outer RESULT='$res' rc=$rc inner RESULT='$INRES' OUTR=(${OUTR[*]}) INR=(${INR[*]})"
fi

kt_test_start "F12(b): a stop inside the INNER callback stops only the inner sink (outer 4, inner 1)"
OUTR=(); INR=(); INRES=""
TPipe.each out_cb_b -- p4; rc=$?
res="$RESULT"
if [[ "$res" == "4" && $rc -eq 0 && "$INRES" == "1" ]] \
   && arr_is OUTR "a" "b" "c" "d" && arr_is INR "a"; then
    kt_test_pass "the outer sink ran to EOF, the inner one stopped at record 1"
else
    kt_test_fail "outer RESULT='$res' rc=$rc inner RESULT='$INRES' OUTR=(${OUTR[*]}) INR=(${INR[*]})"
fi

kt_test_start "F12(c): a STRAY stop writes the process-wide slot and no sink reads it"
TPipe.stop; rc=$?
strayflag="$__TPIPE_STOP"
REC=()
TPipe.each rec -- p4; rc2=$?
if [[ $rc -eq 0 && "$strayflag" == "1" && "$RESULT" == "4" && $rc2 -eq 0 ]] \
   && arr_is REC "a" "b" "c" "d"; then
    kt_test_pass "the stray stop is inert; the next sink delivered all 4 records"
else
    kt_test_fail "stop rc=$rc flag='$strayflag' RESULT='$RESULT' rc2=$rc2 REC=(${REC[*]})"
fi

# ===========================================================================
kt_test_section "F. what stop does and does not touch"
# ===========================================================================

kt_test_start "stop leaves RESULT untouched and answers rc 0"
RESULT="mid-computation"
TPipe.stop; rc=$?
if [[ "$RESULT" == "mid-computation" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT survives a call from inside a callback"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "a stopped sink is rc 0 and RESULT counts the records DELIVERED"
REC=()
stop_at_2() { REC+=( "$1" ); if [[ "$TPIPE_INDEX" == "2" ]]; then TPipe.stop; fi; return 0; }
TPipe.each stop_at_2 -- p4 2>/dev/null; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 ]] && arr_is REC "a" "b"; then
    kt_test_pass "2 of 4 records, rc 0 — the consumer's success"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc REC=(${REC[*]})"
fi

kt_test_start "the record that requested the stop is still fully processed"
REC=()
TPipe.each stop_at_2 -- p4 2>/dev/null
if arr_is REC "a" "b"; then
    kt_test_pass "the loop breaks AFTER the callback returns"
else
    kt_test_fail "REC=(${REC[*]})"
fi

# ===========================================================================
kt_test_section "G. lastRc after a stdin-form sink"
# ===========================================================================

kt_test_start "lastRc is -1 again after a sink that read stdin"
TPipe.each noop -- "$BASH" -c 'printf "a\n"; exit 4'      # lastRc 4 going in
TPipe.lastRc; before="$RESULT"
REC=()
TPipe.each rec <<< $'x\ny'; rc=$?
res="$RESULT"
TPipe.lastRc; after="$RESULT"
if [[ "$before" == "4" && "$res" == "2" && $rc -eq 0 && "$after" == "-1" ]] \
   && arr_is REC "x" "y"; then
    kt_test_pass "4 -> stdin sink -> -1"
else
    kt_test_fail "before='$before' RESULT='$res' rc=$rc after='$after' REC=(${REC[*]})"
fi
