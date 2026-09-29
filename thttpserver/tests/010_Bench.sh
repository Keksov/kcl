#!/bin/bash
# 010_Bench.sh — thttpserver P3: the loose performance gate on the fork-free
# REPLAY path (PLAN §2.8, C22). Socket numbers are REPORTED by ../bench.sh,
# never asserted: a socket request is one listener spawn (a fork, an msys
# process start) plus a drained close, and those move by several times under
# the threaded runner for reasons outside this unit (timing lessons).
#
# TWO SETS OF NUMBERS, on purpose. `../bench.sh`, run by hand on an idle
# machine, publishes the README's Performance table. THIS file asserts shapes
# with generous, RELATIVE ceilings — both sides of every ratio are bash work
# in this same shell, so the threaded runner's load inflates them together:
#
#   A  ServeOne over TReplayTransport (accept, the request/response objects,
#      parse, route to a function, send, close, free) ≤ 15× the request-object
#      baseline (THttpRequest.new + ReadFrom of the same request + delete).
#      Idle: ≈ 5.5× (≈ 27 ms against ≈ 5 ms, both bashes). A per-request
#      `source`, an O(n) scan per header, a second parse would all break it;
#   B  App.DoRun ≤ 2× ServeOne on the same requests — the application layer
#      costs less than a second ServeOne (idle ≈ 1.1×);
#   C  no accumulation: over 60 requests through one server and one transport
#      the median of the LAST 20 is ≤ 2× the median of the FIRST 20;
#   D  $BASHPID is the same across every timed loop and every one of the
#      requests was answered 200 (the fork-free proofs proper are 001/006/008).
# A ceiling alone would pass on code that does nothing, fast: every gate also
# requires ITS timed requests to have been real — each capture a `200 … b1`,
# each baseline parse status 0, the 60-request run counted 60.
#
# Samples are INTERLEAVED (one of each shape per iteration) and the ratios are
# taken between MEDIANS: one slow sample on this platform can move a mean by
# more than the whole head-room. The clock is TStopwatch.getTimeStamp (fork-
# free µs), never `date` (a process on msys). Nothing is forked inside a timed
# region; the median sort is pure bash.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/thttpapplication.sh"
source "$UNIT_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
cd "$TMP" || exit 1

kt_test_section "010: the replay-path performance gate (P3)"

NR=7          # interleaved samples per shape (odd: a real median)
NQ=4          # requests per sample
K_SERVE=15    # A: ServeOne / request-object baseline
K_APP=2       # B: DoRun / ServeOne
K_GROW=2      # C: last 20 / first 20

printf 'GET /b?x=1 HTTP/1.1\r\nHost: h\r\nUser-Agent: bench\r\nAccept: */*\r\nX-A: 1\r\n\r\n' > "$TMP/b.req"
fb() { local q; $1.QueryField x; q="$RESULT"; $2.Write "b$q"; }

# median NAME → MED (pure bash insertion sort: no fork).
median() {
    local -n __m_a="$1"
    local -a __m_s=()
    local __m_v __m_i
    for __m_v in "${__m_a[@]}"; do
        __m_i=${#__m_s[@]}
        while (( __m_i > 0 && __m_s[__m_i - 1] > __m_v )); do
            __m_s[__m_i]=${__m_s[__m_i - 1]}
            __m_i=$(( __m_i - 1 ))
        done
        __m_s[__m_i]=$__m_v
    done
    MED=${__m_s[${#__m_s[@]} / 2]}
}

# fresh_t NAME COUNT — a TReplayTransport NAME fed COUNT copies of b.req.
fresh_t() {
    local i
    if declare -F "$1.delete" >/dev/null; then "$1.delete"; fi
    TReplayTransport.new "$1"
    for (( i = 0; i < $2; i++ )); do "$1.AddRequestFile" "$TMP/b.req"; done
}
# check_t NAME COUNT VAR — every capture of NAME is a 200 with body b1; each
# one that is not is appended to the variable VAR.
check_t() {
    local i c
    local -n __c_bad="$3"
    for (( i = 0; i < $2; i++ )); do
        "$1.ResponseFile" "$i"; c="$(<"$RESULT")"
        [[ "$c" == "HTTP/1.1 200 OK"*$'\r\n\r\n'b1 ]] || __c_bad+=" $1#$i"
    done
}

THttpApplication.new BA
BA.RegisterRoute /b GET fb
BA.Initialize
BA.Server; SRV="$RESULT"
BAD_BASE=""; BAD_SERVE=""; BAD_APP=""; BAD_GROW=""
P0=$BASHPID
PIDS_SAME=1

# ===========================================================================
kt_test_section "A/B. interleaved: baseline, ServeOne, DoRun"
# ===========================================================================

S_BASE=(); S_SERVE=(); S_APP=()
for (( s = 0; s < NR; s++ )); do
    # the request-object baseline
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do
        THttpRequest.new BR
        exec {fd}<"$TMP/b.req"
        BR.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
        [[ "$RESULT" == 0 ]] || BAD_BASE+=" status=$RESULT"
        exec {fd}<&-
        BR.delete
    done
    TStopwatch.getTimeStamp; S_BASE+=( $(( (RESULT - t0) / NQ )) )

    # ServeOne
    fresh_t BT "$NQ"
    "$SRV.Transport" = BT
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do "$SRV.ServeOne"; done
    TStopwatch.getTimeStamp; S_SERVE+=( $(( (RESULT - t0) / NQ )) )
    check_t BT "$NQ" BAD_SERVE

    # App.DoRun (BeginServe's one fork stays outside the timed region)
    fresh_t BT "$NQ"
    "$SRV.Transport" = BT
    "$SRV.BeginServe"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do BA.DoRun; done
    TStopwatch.getTimeStamp; S_APP+=( $(( (RESULT - t0) / NQ )) )
    "$SRV.EndServe"
    check_t BT "$NQ" BAD_APP
    [[ $BASHPID == "$P0" ]] || PIDS_SAME=0
done
median S_BASE;  M_BASE=$MED
median S_SERVE; M_SERVE=$MED
median S_APP;   M_APP=$MED

kt_test_start "A: ServeOne over replay ≤ ${K_SERVE}× the request-object baseline (medians of $NR interleaved samples × $NQ requests; idle ≈ 5.5×)"
if [[ -z "$BAD_BASE$BAD_SERVE" ]] && (( M_BASE > 0 && M_SERVE <= K_SERVE * M_BASE )); then
    kt_test_pass "ServeOne $(( M_SERVE / 1000 )).$(( M_SERVE % 1000 / 100 )) ms vs baseline $(( M_BASE / 1000 )).$(( M_BASE % 1000 / 100 )) ms = $(( M_SERVE * 10 / M_BASE / 10 )).$(( M_SERVE * 10 / M_BASE % 10 ))×"
else
    kt_test_fail "ServeOne ${M_SERVE} us vs baseline ${M_BASE} us (samples: ${S_SERVE[*]} / ${S_BASE[*]}) not-200:${BAD_SERVE:0:200} baseline:${BAD_BASE:0:100}"
fi

kt_test_start "B: App.DoRun ≤ ${K_APP}× ServeOne (the application layer; idle ≈ 1.1×)"
if [[ -z "$BAD_APP" ]] && (( M_SERVE > 0 && M_APP <= K_APP * M_SERVE )); then
    kt_test_pass "DoRun $(( M_APP / 1000 )).$(( M_APP % 1000 / 100 )) ms vs ServeOne $(( M_SERVE / 1000 )).$(( M_SERVE % 1000 / 100 )) ms = $(( M_APP * 100 / M_SERVE ))%"
else
    kt_test_fail "DoRun ${M_APP} us vs ServeOne ${M_SERVE} us (samples: ${S_APP[*]} / ${S_SERVE[*]}) not-200:${BAD_APP:0:200}"
fi

# ===========================================================================
kt_test_section "C. no accumulation over 60 requests"
# ===========================================================================

fresh_t BL 60
"$SRV.Transport" = BL
"$SRV.BeginServe"
S_ALL=()
for (( q = 0; q < 60; q++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    BA.DoRun
    TStopwatch.getTimeStamp; S_ALL+=( $(( RESULT - t0 )) )
done
"$SRV.EndServe"
check_t BL 60 BAD_GROW
"$SRV.RequestCount"; [[ "$RESULT" == 60 ]] || BAD_GROW+=" count=$RESULT"
[[ $BASHPID == "$P0" ]] || PIDS_SAME=0
S_FIRST=("${S_ALL[@]:0:20}"); S_LAST=("${S_ALL[@]:40:20}")
median S_FIRST; M_FIRST=$MED
median S_LAST;  M_LAST=$MED

kt_test_start "C: per-request cost does not grow: median of requests 41–60 ≤ ${K_GROW}× the median of 1–20 (one server, one transport, 60 DoRuns)"
if [[ -z "$BAD_GROW" ]] && (( M_FIRST > 0 && M_LAST <= K_GROW * M_FIRST )); then
    kt_test_pass "first 20: $(( M_FIRST / 1000 )) ms, last 20: $(( M_LAST / 1000 )) ms"
else
    kt_test_fail "first ${M_FIRST} us, last ${M_LAST} us; not-200:${BAD_GROW:0:200}"
fi

# ===========================================================================
kt_test_section "D. fork-free and correct while timed"
# ===========================================================================

kt_test_start "D: \$BASHPID unchanged across every timed loop, and all $(( NR * NQ * 2 + 60 )) timed requests were real (answered '200 … b1')"
all="$BAD_SERVE$BAD_APP$BAD_GROW"
if [[ $PIDS_SAME -eq 1 && -z "$all" ]]; then kt_test_pass "same pid, all 200"; else kt_test_fail "pid-same=$PIDS_SAME not-200:${all:0:300}"; fi

BA.delete
for v in BT BL; do if declare -F "$v.delete" >/dev/null; then "$v.delete"; fi; done
