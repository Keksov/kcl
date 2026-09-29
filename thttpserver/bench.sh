#!/bin/bash
# bench.sh — kcl/thttpserver micro-benchmark (P3, PLAN §2.8). Publishes the
# numbers README.md §11 quotes; asserts nothing (tests/010_Bench.sh is the
# gate, on the replay path only).
#
#   (a) THE REPLAY PATH — no socket, no fork: per request, from the MEDIANS of
#       NR interleaved samples of NQ requests each: the request object + parse
#       (THttpRequest.new + ReadFrom + delete), routing to a function and to a
#       route class (RouteRequest on a parsed request), the response
#       (THttpResponse.new + Attach + Write + SendContent + delete), the whole
#       THttpServer.ServeOne over TReplayTransport and THttpApplication.DoRun;
#   (b) THE SOCKET PATH — an application child (THttpApplication + a
#       TNetcatTransport descendant that times its own CloseConnection) on a
#       random loopback port; NS sequential requests per sample, NSS samples,
#       INTERLEAVED between two clients: `curl` (one process per request, as a
#       user runs it) and a bash `/dev/tcp` client (no client process at all,
#       so the column is the server's own cost plus the kernel);
#   (c) THE SPLIT of one socket request: the listener spawn — the §2.5
#       mechanism (`exec {rd}< <(nc … < <(exec cat FIFO))` + the O_WRONLY
#       writer), replicated here line for line because `_spawn` is private —
#       timed to its return and to `Listening on`; the handling inside the
#       server (the access log's MS: objects, parse, route, send); the drained
#       close (the child's CloseConnection override); plus (a)'s parse / route
#       / send for the fork-free share;
#   (d) PARALLEL CLIENTS against the pre-spawn (D5): ROUNDS bursts of 8
#       simultaneous curl clients with NO retry, counted per round: 200s,
#       resets (curl rc 56, and 55 — the send side of the same reset), refusals
#       (rc 7) — and the access log, which shows how many were really handled.
#
# The clock is TStopwatch.getTimeStamp (fork-free µs), never `date` (a process
# on msys, ~20 ms a call). Medians, not means: one slow process start on this
# platform moves a mean by more than the effect being measured; the mean is
# printed beside every median. Proxy variables are unset (this machine exports
# HTTP_PROXY): every curl also has --noproxy '*'.
#
# Run: bash kcl/thttpserver/bench.sh [NR] [NS] [ROUNDS]
#      PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/thttpserver/bench.sh
#      (defaults NR=7, NS=20, ROUNDS=5; NQ=4 and NSS=5 are fixed)
# netcat as in the tests: $KCL_NC, else `nc` on PATH, else
# /c/bin/msys64/usr/bin/nc.exe. Without one, (b)–(d) are skipped loudly.
# Everything lives in one `mktemp -d`, removed by an EXIT trap (a bench, not a
# test file) which also stops the server child.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/thttpapplication.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

exec </dev/null

NR=${1:-7}          # interleaved samples per replay shape (odd)
NS=${2:-20}         # sequential socket requests per sample
ROUNDS=${3:-5}      # parallel bursts
NQ=4                # requests per replay sample
NSS=5               # socket samples per client

BD="$(mktemp -d)"
CHILD=""
cleanup() {
    if [[ -n "$CHILD" ]] && kill -0 "$CHILD" 2>/dev/null; then
        : > "$BD/srv/done"
        wait "$CHILD" 2>/dev/null
    fi
    rm -rf "$BD"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# median NAME → MED, MEAN (µs). Sorting is one fork, outside every timed region.
MED=0; MEAN=0
median() {
    local -n __m_a="$1"
    local -a __m_s=()
    local __m_v __m_sum=0
    mapfile -t __m_s < <( printf '%s\n' "${__m_a[@]}" | sort -n )
    MED="${__m_s[ ${#__m_s[@]} / 2 ]}"
    for __m_v in "${__m_s[@]}"; do __m_sum=$(( __m_sum + __m_v )); done
    MEAN=$(( __m_sum / ${#__m_s[@]} ))
}
ms() { printf '%d.%02d' $(( $1 / 1000 )) $(( $1 % 1000 / 10 )); }
row() {   # LABEL ARRAYNAME — median and mean in ms, and the sample count
    local -n __r_a="$2"
    median "$2"
    printf '  %-66s median %8s ms   mean %8s ms   (%d)\n' "$1" "$(ms "$MED")" "$(ms "$MEAN")" "${#__r_a[@]}"
}

echo "thttpserver micro-benchmark  (bash ${BASH_VERSION})"
echo

# ===========================================================================
# (a) the replay path
# ===========================================================================
printf 'GET /b?x=1 HTTP/1.1\r\nHost: h\r\nUser-Agent: bench\r\nAccept: */*\r\nX-A: 1\r\n\r\n' > "$BD/b.req"
fb() { local q; $1.QueryField x; q="$RESULT"; $2.Write "b$q"; }
class TBenchRoute : THttpRouteObject
    public
        override proc HandleRequest
end
TBenchRoute.HandleRequest() { $2.Write "o"; }
build TBenchRoute

THttpApplication.new BA
BA.RegisterRoute /b GET fb
BA.RegisterRoute /o GET TBenchRoute
BA.Initialize
BA.Server; SRV="$RESULT"
BA.AppRouter; RTR="$RESULT"
fresh_t() {
    local i
    if declare -F "$1.delete" >/dev/null; then "$1.delete"; fi
    TReplayTransport.new "$1"
    for (( i = 0; i < $2; i++ )); do "$1.AddRequestFile" "$BD/b.req"; done
}
printf 'GET /o HTTP/1.1\r\nHost: h\r\n\r\n' > "$BD/o.req"
THttpRequest.new RQ; exec {fd}<"$BD/b.req"; RQ.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536; exec {fd}<&-
THttpRequest.new RO; exec {fd}<"$BD/o.req"; RO.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536; exec {fd}<&-
THttpResponse.new RS
exec {NULLFD}>/dev/null

A_PARSE=(); A_RFN=(); A_ROBJ=(); A_SEND=(); A_SERVE=(); A_APP=()
P0=$BASHPID
for (( s = 0; s < NR; s++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do
        THttpRequest.new BR
        exec {fd}<"$BD/b.req"
        BR.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
        exec {fd}<&-
        BR.delete
    done
    TStopwatch.getTimeStamp; A_PARSE+=( $(( (RESULT - t0) / NQ )) )

    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do RS.Content = ""; "$RTR.RouteRequest" RQ RS; done
    TStopwatch.getTimeStamp; A_RFN+=( $(( (RESULT - t0) / NQ )) )

    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do RS.Content = ""; "$RTR.RouteRequest" RO RS; done
    TStopwatch.getTimeStamp; A_ROBJ+=( $(( (RESULT - t0) / NQ )) )

    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do
        THttpResponse.new BS
        BS.Attach "$NULLFD" 0
        BS.Write "b1"
        BS.SendContent
        BS.delete
    done
    TStopwatch.getTimeStamp; A_SEND+=( $(( (RESULT - t0) / NQ )) )

    fresh_t BT "$NQ"
    "$SRV.Transport" = BT
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do "$SRV.ServeOne"; done
    TStopwatch.getTimeStamp; A_SERVE+=( $(( (RESULT - t0) / NQ )) )

    fresh_t BT "$NQ"
    "$SRV.Transport" = BT
    "$SRV.BeginServe"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NQ; q++ )); do BA.DoRun; done
    TStopwatch.getTimeStamp; A_APP+=( $(( (RESULT - t0) / NQ )) )
    "$SRV.EndServe"
done
exec {NULLFD}>&-
echo "(a) the replay path — per request, NR=$NR interleaved samples x NQ=$NQ requests (no socket, no fork):"
row "request object + parse (new + ReadFrom 4-header GET + delete)" A_PARSE
row "route to a function (RouteRequest, parsed request)" A_RFN
row "route to a route class (new + HandleRequest + delete)" A_ROBJ
row "response (new + Attach + Write + SendContent + delete)" A_SEND
row "THttpServer.ServeOne over TReplayTransport (all of it)" A_SERVE
median A_SERVE; M_SERVE=$MED
row "THttpApplication.DoRun (one ServeOne + the app's checks)" A_APP
median A_APP; M_APP=$MED
# (the check itself outside any $( ): $BASHPID inside one is the subshell's)
if [[ $BASHPID == "$P0" ]]; then FORKS='none ($BASHPID unchanged)'; else FORKS='$BASHPID CHANGED'; fi
printf '  %-66s %s\n' "forks" "$FORKS"
median A_PARSE; M_PARSE=$MED; median A_RFN; M_RFN=$MED; median A_SEND; M_SEND=$MED
RS.delete; RQ.delete; RO.delete; BA.delete; BT.delete
echo

# ===========================================================================
# (b)–(d) sockets
# ===========================================================================
TMP="$BD"
UNIT_DIR="$DIR"
source "$DIR/tests/_ths_socket.sh"
if ! ths_have_nc; then
    echo "(b)-(d) SKIPPED — no netcat (KCL_NC unset, no nc on PATH, no /c/bin/msys64/usr/bin/nc.exe)"
    exit 0
fi
echo "netcat: $THS_NC  ($("$THS_NC" --version 2>/dev/null </dev/null | head -1))"
echo

cat > "$BD/srv.sh" <<'EOF'
exec </dev/null
cd "$SRV_DIR" || exit 90
source "$UNIT_DIR/thttpapplication.sh" || exit 91
class TBenchNetcat : TNetcatTransport
    public
        override proc CloseConnection
end
TBenchNetcat.CloseConnection() {
    local t0=${EPOCHREALTIME//[!0-9]/} r=0
    inherited CloseConnection "$@" || r=$?
    printf '%s\n' $(( ${EPOCHREALTIME//[!0-9]/} - t0 )) >> "$SRV_DIR/close.us"
    return "$r"
}
build TBenchNetcat
b_idle() { if [[ -e "$SRV_DIR/done" ]]; then "$1.Terminate"; fi; }
b_log()  { printf '%s\n' "$2" >> "$SRV_DIR/access.log"; }
b_x()    { $2.Write "ok"; }
THttpApplication.new App "$@"
App.RegisterRoute /x   GET b_x
App.RegisterRoute /par GET b_x
App.Initialize || exit 3
App.Server; srv="$RESULT"
TBenchNetcat.new BT
BT.Port = "$PORT"
"$srv.Transport" = BT
"$srv.AcceptIdleTimeout" = 1000
"$srv.OnAcceptIdle" = b_idle
"$srv.OnLog" = b_log
rc=0; App.Run || rc=$?
printf 'rc=%s\n' "$rc" >> "$SRV_DIR/result"
App.delete
BT.delete
EOF

if ! ths_launch srv "$BD/srv.sh" "--port={PORT}"; then
    echo "(b)-(d) SKIPPED — the bench server never listened: $(tr '\n' ' ' < "$BD/srv/err" 2>/dev/null)"
    exit 0
fi
CHILD=$THS_PID
PORT=$THS_PORT
URL="http://127.0.0.1:$PORT/x"

# raw_get — one request through bash's /dev/tcp (no client process); rc 0 when
# the answer is a 200. A refused connect is retried (the listener respawns
# between connections only in the first request of a burst).
raw_get() {
    local c r="" i
    for (( i = 0; i < 100; i++ )); do
        if { exec {c}<>"/dev/tcp/127.0.0.1/$PORT"; } 2>/dev/null; then break; fi
        c=""
    done
    [[ -n "$c" ]] || return 1
    printf 'GET /x HTTP/1.0\r\n\r\n' >&"$c"
    IFS= read -r -d '' -u "$c" r
    exec {c}<&-
    [[ "$r" == "HTTP/1.1 200 OK"* ]]
}
curl_get() {
    local code
    code="$(curl --noproxy '*' -s -m 30 -o /dev/null -w '%{http_code}' "$URL")"
    [[ "$code" == 200 ]]
}

# ---------------------------------------------------------------------------
# (b) sequential
# ---------------------------------------------------------------------------
B_CURL=(); B_RAW=(); BAD=0
curl_get || BAD=$(( BAD + 1 ))      # warm-up (the first connection spawns)
for (( s = 0; s < NSS; s++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NS; q++ )); do curl_get || BAD=$(( BAD + 1 )); done
    TStopwatch.getTimeStamp; B_CURL+=( $(( (RESULT - t0) / NS )) )
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( q = 0; q < NS; q++ )); do raw_get || BAD=$(( BAD + 1 )); done
    TStopwatch.getTimeStamp; B_RAW+=( $(( (RESULT - t0) / NS )) )
done
echo "(b) the socket path, sequential — NSS=$NSS interleaved samples x NS=$NS requests per client:"
row "curl per request (a curl process + the server)" B_CURL
median B_CURL; printf '  %-66s %d req/s\n' "  = requests per second, curl" $(( 1000000 / MED ))
row "/dev/tcp per request (no client process)" B_RAW
median B_RAW; printf '  %-66s %d req/s\n' "  = requests per second, /dev/tcp" $(( 1000000 / MED ))
printf '  %-66s %d\n' "requests not answered 200" "$BAD"
echo

# ---------------------------------------------------------------------------
# (c) the split
# ---------------------------------------------------------------------------
mapfile -t C_CLOSE < "$BD/srv/close.us"
C_HANDLE=()
while IFS= read -r l; do
    [[ "$l" == *" GET /x 200 "* ]] && C_HANDLE+=( $(( ${l##* } * 1000 )) )
done < "$BD/srv/access.log"
ths_nport; P2=$THS_PORT
C_SPAWN=(); C_LISTEN=()
for (( s = 0; s < NR; s++ )); do
    f="$BD/fifo$s"; e="$BD/err$s"
    mkfifo "$f"; : > "$e"
    TStopwatch.getTimeStamp; t0=$RESULT
    exec {rd}< <( export LC_ALL=C; exec "$THS_NC" -l -c -vv -n -w 5 -s 127.0.0.1 -p "$P2" < <(exec cat "$f" 2>/dev/null) 2>"$e" )
    pid=$!
    exec {wr}>"$f"
    TStopwatch.getTimeStamp; t1=$RESULT
    ok=0
    for (( i = 0; i < 4000 && ! ok; i++ )); do
        while IFS= read -r l; do [[ "$l" == 'Listening on'* ]] && ok=1; done < "$e"
    done
    TStopwatch.getTimeStamp; t2=$RESULT
    C_SPAWN+=( $(( t1 - t0 )) ); C_LISTEN+=( $(( t2 - t0 )) )
    exec {wr}>&- {rd}<&-
    kill -TERM "$pid" 2>/dev/null || :
    wait "$pid" 2>/dev/null || :
done
echo "(c) the split of one socket request (per request):"
row "listener spawn, synchronous part (fork + cat relay + writer open)" C_SPAWN
row "  … until nc reports 'Listening on'" C_LISTEN
row "handling inside the server (access-log MS: objects+parse+route+send)" C_HANDLE
row "drained close (CloseConnection: close wr, drain to EOF, reap)" C_CLOSE
printf '  %-66s %s / %s / %s ms\n' "of which fork-free (a): parse / route / send" "$(ms "$M_PARSE")" "$(ms "$M_RFN")" "$(ms "$M_SEND")"
echo

# ---------------------------------------------------------------------------
# (d) parallel bursts
# ---------------------------------------------------------------------------
echo "(d) parallel: $ROUNDS bursts of 8 simultaneous curl clients, NO retry (D5: one pre-spawned listener):"
par_client() {
    local r=0 code
    code="$(curl --noproxy '*' -s -m 30 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/par")" || r=$?
    printf '%s %s\n' "$r" "$code" > "$BD/par.$1"
}
T_OK=0; T_RST=0; T_REF=0; T_OTH=0
before=0; while IFS= read -r l; do [[ "$l" == *" GET /par 200 "* ]] && before=$(( before + 1 )); done < "$BD/srv/access.log"
for (( rd_i = 1; rd_i <= ROUNDS; rd_i++ )); do
    curl_get || :                    # the server is up and a listener is pre-spawned
    pp=()
    for c in 1 2 3 4 5 6 7 8; do par_client "$c" & pp+=($!); done
    wait "${pp[@]}"
    ok=0; rst=0; ref=0; oth=0
    for c in 1 2 3 4 5 6 7 8; do
        read -r r code < "$BD/par.$c"
        if [[ "$r" == 0 && "$code" == 200 ]]; then ok=$(( ok + 1 ))
        elif [[ "$r" == 56 || "$r" == 55 ]]; then rst=$(( rst + 1 ))
        elif [[ "$r" == 7 ]]; then ref=$(( ref + 1 ))
        else oth=$(( oth + 1 )); fi
    done
    printf '  round %d: %d x 200, %d reset (rc 55/56), %d refused (rc 7), %d other\n' "$rd_i" "$ok" "$rst" "$ref" "$oth"
    T_OK=$(( T_OK + ok )); T_RST=$(( T_RST + rst )); T_REF=$(( T_REF + ref )); T_OTH=$(( T_OTH + oth ))
done
after=0; while IFS= read -r l; do [[ "$l" == *" GET /par 200 "* ]] && after=$(( after + 1 )); done < "$BD/srv/access.log"
printf '  %-66s %d x 200, %d resets, %d refused, %d other (of %d)\n' "total" "$T_OK" "$T_RST" "$T_REF" "$T_OTH" $(( ROUNDS * 8 ))
printf '  %-66s %d\n' "handled by the server (access log)" $(( after - before ))

: > "$BD/srv/done"
wait "$CHILD" 2>/dev/null
CHILD=""
echo
printf 'server child: %s\n' "$(tr '\n' ' ' < "$BD/srv/result" 2>/dev/null)"
