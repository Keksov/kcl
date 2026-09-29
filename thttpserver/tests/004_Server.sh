#!/bin/bash
# 004_Server.sh — thttpserver P2: THttpServer over TReplayTransport (§0, no
# socket, always runs) and over real sockets through TNetcatTransport
# (§1–§3; the test is the client, the server a child bash). PLAN §2.5, §2.6,
# §3 facts 1, 2 (wire), 3 (socket, best effort), 4, 5, 6, 7, 8, 9, 13 (wire),
# 16 (wire), 22 (server half); §4 socket-test rules (tests/_ths_socket.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpserver.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
export THS_LIB="$SCRIPT_DIR/_ths_socket.sh"
source "$THS_LIB"
CRLF=$'\r\n'
cd "$TMP" || exit 1

kt_test_section "004: THttpServer — replay-driven and over sockets (P2)"

# ===========================================================================
kt_test_section "0. the server over TReplayTransport (no socket)"
# ===========================================================================

rq() { printf '%s' "$2" > "$TMP/$1"; }
# cap N — the N-th capture of transport RT0 into CAP (whole), CAPH (head, CR
# removed), CAPB (body).
cap() {
    RT0.ResponseFile "$1"; local f="$RESULT"
    CAP=""; [[ -n "$f" && -f "$f" ]] && CAP="$(<"$f")"
    CAPH="${CAP%%$'\r\n\r\n'*}"; CAPH="${CAPH//$'\r'/}"
    if [[ "$CAP" == *$'\r\n\r\n'* ]]; then CAPB="${CAP#*$'\r\n\r\n'}"; else CAPB=""; fi
}
# fresh_replay FILE… — a new TReplayTransport RT0 fed with the request files.
fresh_replay() {
    if declare -F RT0.delete >/dev/null; then RT0.delete; fi
    TReplayTransport.new RT0
    local f
    for f in "$@"; do RT0.AddRequestFile "$TMP/$f"; done
}
LOGS=()
lg() { LOGS+=("$2"); }
ERRS=()
onerr() { ERRS+=("$1 $2 $3"); }

rq get_x.req   "GET /x HTTP/1.0${CRLF}${CRLF}"
rq get_u.req   "GET /u HTTP/1.0${CRLF}${CRLF}"
rq head_x.req  "HEAD /x HTTP/1.0${CRLF}${CRLF}"
rq fail.req    "GET /fail HTTP/1.0${CRLF}${CRLF}"
rq sent.req    "GET /sentfail HTTP/1.0${CRLF}${CRLF}"
rq bad.req     "GET http://x/ HTTP/1.0${CRLF}${CRLF}"
rq big.req     "POST /x HTTP/1.0${CRLF}Content-Length: 99999${CRLF}${CRLF}"
rq gone.req    "GET /x HT"
rq none.req    "GET /none HTTP/1.0${CRLF}${CRLF}"

hx()    { $2.Write "x-body"; $2.SetCustomHeader X-R x; }
hu()    { $2.Write "aж"; }
hfail() { $2.Write "partial"; $2.SetCustomHeader X-Partial 1; return 3; }
hsent() { $2.Write "sent-by-handler"; $2.SendContent; return 4; }
THttpRouter.new RR
RR.RegisterRoute /x GET hx
RR.RegisterRoute /u GET hu
RR.RegisterRoute /fail GET hfail
RR.RegisterRoute /sentfail GET hsent

THttpServer.new SV
SV.Router = RR
SV.OnLog = lg
SV.OnRequestError = onerr

kt_test_start "ServeOne without a transport (no BeginServe, Transport '') → rc 2, LastError set"
r=0; SV.ServeOne || r=$?
SV.LastError; le="$RESULT"
if [[ $r -eq 2 && -n "$le" ]]; then kt_test_pass "rc 2, '$le'"; else kt_test_fail "rc=$r le='$le'"; fi

fresh_replay get_x.req get_u.req none.req
SV.Transport = RT0
kt_test_start "ServeOne × 3 over replay: rc 0, RESULT = the code sent, RequestCount counts, req/resp freed after each"
bad=""
for want in 200 200 404; do
    r=0; RESULT=stale; SV.ServeOne || r=$?
    [[ $r -eq 0 && "$RESULT" == "$want" ]] || bad+=" rc=$r/'$RESULT'(want $want)"
    declare -p SV_req >/dev/null 2>&1 && bad+=" SV_req-left"
    declare -p SV_resp >/dev/null 2>&1 && bad+=" SV_resp-left"
    declare -F SV_req.Method >/dev/null && bad+=" SV_req-fns-left"
done
SV.RequestCount; n="$RESULT"
[[ "$n" == 3 ]] || bad+=" count=$n"
if [[ -z "$bad" ]]; then kt_test_pass "200 200 404, count 3, nothing left"; else kt_test_fail "$bad"; fi

kt_test_start "the captures: route body + custom header; 404 from the router; Server banner and Connection: close"
cap 0; a="$CAPH|$CAPB"; cap 1; b="$CAPB"; cap 2; c="$CAPH"
if [[ "$a" == "HTTP/1.1 200 OK"*$'\nServer: kcl-thttpserver\n'*$'\nX-R: x\n'*$'Content-Length: 6\nConnection: close|x-body' \
      && "$b" == "aж" && "$c" == "HTTP/1.1 404 Not Found"* ]]; then
    kt_test_pass "200 x-body, aж, 404"
else
    kt_test_fail "a='${a:0:300}' b='$b' c='${c:0:60}'"
fi

kt_test_start "ServeOne when the transport has nothing left → rc 2 and LastError = the transport's"
r=0; SV.ServeOne || r=$?
SV.LastError; le="$RESULT"
if [[ $r -eq 2 && "$le" == *"no request file left"* ]]; then kt_test_pass "rc 2 '$le'"; else kt_test_fail "rc=$r le='$le'"; fi

kt_test_start "OnLog: one line per answered request, 'ADDR METHOD URI CODE BYTES MS' (ADDR '-' under replay; BYTES = body bytes)"
bad=""
[[ ${#LOGS[@]} -eq 3 ]] || bad+=" n=${#LOGS[@]}"
[[ "${LOGS[0]:-}" =~ ^-\ GET\ /x\ 200\ 6\ [0-9]+$ ]] || bad+=" l0='${LOGS[0]:-}'"
[[ "${LOGS[1]:-}" =~ ^-\ GET\ /u\ 200\ 3\ [0-9]+$ ]] || bad+=" l1='${LOGS[1]:-}'"
[[ "${LOGS[2]:-}" =~ ^-\ GET\ /none\ 404\ 0\ [0-9]+$ ]] || bad+=" l2='${LOGS[2]:-}'"
if [[ -z "$bad" ]]; then kt_test_pass "${LOGS[*]}"; else kt_test_fail "$bad"; fi

LOGS=(); ERRS=()
fresh_replay fail.req sent.req head_x.req bad.req big.req gone.req get_x.req
SV.Transport = RT0
codes=()
for i in 1 2 3 4 5 6 7; do r=0; SV.ServeOne || r=$?; codes+=("$r:$RESULT"); done

kt_test_start "a handler rc≠0 with nothing sent → OnRequestError REQ RESP RC once, then 500 with an EMPTY body (partial output and headers dropped)"
cap 0
if [[ "${codes[0]}" == "0:500" && "${#ERRS[@]}" -ge 1 && "${ERRS[0]}" == "SV_req SV_resp 3" \
      && "$CAPH" == "HTTP/1.1 500 Internal Server Error"* && "$CAPH" == *$'\nContent-Length: 0\n'* \
      && "$CAPH" != *X-Partial* && -z "$CAPB" ]]; then
    kt_test_pass "500, empty, OnRequestError '${ERRS[0]}'"
else
    kt_test_fail "code=${codes[0]} errs=(${ERRS[*]}) head='${CAPH:0:200}' body='$CAPB'"
fi

kt_test_start "a handler that SENT and then returned non-zero: its response stands, no second write, no OnRequestError"
cap 1
if [[ "${codes[1]}" == "0:200" && "${#ERRS[@]}" -eq 1 && "$CAPB" == "sent-by-handler" && "$CAP" != *"HTTP/1.1 500"* ]]; then
    kt_test_pass "one 200"
else
    kt_test_fail "code=${codes[1]} errs=${#ERRS[@]} cap='${CAP:0:200}'"
fi

kt_test_start "HEAD on a GET route: the GET head (Content-Length 6, X-R), no body"
cap 2
if [[ "${codes[2]}" == "0:200" && "$CAPH" == *$'\nX-R: x\n'* && "$CAPH" == *$'\nContent-Length: 6\n'* && -z "$CAPB" ]]; then
    kt_test_pass "head only"
else
    kt_test_fail "code=${codes[2]} head='${CAPH:0:200}' body='$CAPB'"
fi

kt_test_start "a parser status is sent as the response code, no handler runs (400, 413)"
cap 3; a="$CAPH"; cap 4; b="$CAPH"
if [[ "${codes[3]}" == "0:400" && "${codes[4]}" == "0:413" && "$a" == "HTTP/1.1 400 Bad Request"* && "$b" == "HTTP/1.1 413 Content Too Large"* ]]; then
    kt_test_pass "400, 413"
else
    kt_test_fail "codes=${codes[3]} ${codes[4]} a='${a:0:40}' b='${b:0:40}'"
fi

kt_test_start "'gone' (the client left mid-request): nothing is written, ServeOne rc 0 RESULT gone, no log line"
cap 5
if [[ "${codes[5]}" == "0:gone" && -z "$CAP" && ${#LOGS[@]} -eq 6 ]]; then kt_test_pass "empty capture, 6 log lines for 7 connections"; else kt_test_fail "code=${codes[5]} cap='${CAP:0:60}' logs=${#LOGS[@]}"; fi

kt_test_start "the server goes on after all of it: the next request is 200; RequestCount 10 (3 + 7 connections, the fatal Accept not counted)"
cap 6; SV.RequestCount
if [[ "${codes[6]}" == "0:200" && "$CAPB" == "x-body" && "$RESULT" == 10 ]]; then kt_test_pass "200, 10"; else kt_test_fail "code=${codes[6]} body='$CAPB' count=$RESULT"; fi

kt_test_start "log lines of the error paths: '- - - 400 0 MS' (no method/URI parsed), HEAD logs 0 bytes"
if [[ "${LOGS[2]:-}" =~ ^-\ HEAD\ /x\ 200\ 0\ [0-9]+$ && "${LOGS[3]:-}" =~ ^-\ -\ -\ 400\ 0\ [0-9]+$ && "${LOGS[0]:-}" =~ ^-\ GET\ /fail\ 500\ 0\ [0-9]+$ ]]; then
    kt_test_pass "HEAD 0, 400 '-', 500 0"
else
    kt_test_fail "logs=(${LOGS[*]})"
fi

kt_test_start "HandleRequest precedence: OnRequest wins over Router; neither → 404"
on() { $2.Write "on"; }
fresh_replay get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = on
SV.ServeOne; cap 0; a="$CAPB"
SV.OnRequest = ""
SV.Router = ""
SV.ServeOne; cap 1; b="$CAPH"
if [[ "$a" == "on" && "$b" == "HTTP/1.1 404 Not Found"* ]]; then kt_test_pass "OnRequest, then 404"; else kt_test_fail "a='$a' b='${b:0:40}'"; fi
SV.Router = RR

kt_test_start "Serve over replay: serves every request, then the transport fatal → rc 1, LastError; Active 1 inside a handler, 0 after"
ACT=()
act() { $2.Write a; SV.Active; ACT+=("$RESULT"); }
fresh_replay get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = act
r=0; SV.Serve || r=$?
SV.LastError; le="$RESULT"; SV.Active; a="$RESULT"
if [[ $r -eq 1 && "$le" == *"no request file left"* && "${ACT[*]}" == "1 1" && "$a" == 0 ]]; then
    kt_test_pass "rc 1, two handled, Active 1 1 → 0"
else
    kt_test_fail "rc=$r le='$le' act=(${ACT[*]}) after=$a"
fi

kt_test_start "the Active setter RUNS Serve (FPC): SV.Active = true blocks and serves; = false from a handler ends after that response"
stopper() { $2.Write s; SV.Active = false; }
fresh_replay get_x.req get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = stopper
SV.MaxRequests = 0
SV.RequestCount; c0="$RESULT"
r=0; SV.Active = true || r=$?
SV.RequestCount; c1="$RESULT"; SV.Active; a="$RESULT"
if [[ $r -eq 0 && "$c1" == 1 && "$a" == 0 ]]; then kt_test_pass "one served, then stopped, rc 0"; else kt_test_fail "rc=$r count $c0→$c1 active=$a"; fi

kt_test_start "SetActive: true while active → rc 1 (nothing nested); a value other than true/false/1/0 → rc 2"
NEST=""
nest() { local r=0; SV.Active = true || r=$?; NEST="$r"; $2.Write n; }
fresh_replay get_x.req
SV.Transport = RT0
SV.OnRequest = nest
SV.Serve || :
r2=0; SV.Active = maybe || r2=$?
if [[ "$NEST" == 1 && $r2 -eq 2 ]]; then kt_test_pass "1, 2"; else kt_test_fail "nested=$NEST bad-value=$r2"; fi

kt_test_start "MaxRequests = 2 with 3 queued: Serve stops after 2, rc 0 (not a fatal), Terminate from a handler likewise"
fresh_replay get_x.req get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = hx
SV.MaxRequests = 2
r=0; SV.Serve || r=$?
SV.RequestCount; c="$RESULT"
term() { $2.Write t; SV.Terminate; }
fresh_replay get_x.req get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = term
SV.MaxRequests = 0
r2=0; SV.Serve || r2=$?
SV.RequestCount; c2="$RESULT"
if [[ $r -eq 0 && "$c" == 2 && $r2 -eq 0 && "$c2" == 1 ]]; then kt_test_pass "2 then stop; 1 then stop"; else kt_test_fail "max: rc=$r count=$c; terminate: rc=$r2 count=$c2"; fi

kt_test_start "Serve saves and restores INT/TERM/PIPE exactly; during a handler PIPE is ignored and INT/TERM belong to the server"
trap ': custom int' INT
trap ': custom term' TERM
trap ': custom pipe' PIPE
before="$(trap -p INT TERM PIPE)"
DURING=""
td() { DURING="$(trap -p PIPE)|$(trap -p TERM)"; $2.Write t; }
fresh_replay get_x.req
SV.Transport = RT0
SV.OnRequest = td
SV.Serve || :
after="$(trap -p INT TERM PIPE)"
trap - INT TERM PIPE
if [[ "$before" == "$after" && "$DURING" == "trap -- '' SIGPIPE|trap -- "*SIGTERM && "$DURING" != *"custom"* ]]; then
    kt_test_pass "restored; during: ${DURING//$'\n'/ }"
else
    kt_test_fail "before='$before' after='$after' during='$DURING'"
fi

kt_test_start "TERM during Serve (a handler signals its own shell): that response is sent, then Serve ends rc 0; traps restored"
sig() { $2.Write sig; kill -TERM "$BASHPID"; }
fresh_replay get_x.req get_x.req get_x.req
SV.Transport = RT0
SV.OnRequest = sig
SV.RequestCount; c0="$RESULT"
r=0; SV.Serve || r=$?
SV.RequestCount; c1="$RESULT"
cap 0; b="$CAPB"
if [[ $r -eq 0 && "$c1" == 1 && "$b" == sig && -z "$(trap -p TERM)" ]]; then kt_test_pass "one served (RequestCount 1: BeginServe resets it), rc 0, no trap left"; else kt_test_fail "rc=$r served=$c1 body='$b' trap='$(trap -p TERM)'"; fi

kt_test_start "a descendant server: override HandleRequest + inherited HandleRequest \"\$@\" routes; the protected _log is callable (no warning), control characters → '?'"
class TAuditServer : THttpServer
    public
        override proc HandleRequest
        proc Audit
end
TAuditServer.HandleRequest() {
    local __a_rc=0
    $2.SetCustomHeader X-Audit yes
    inherited HandleRequest "$@" || __a_rc=$?
    return "$__a_rc"
}
TAuditServer.Audit() {
    $this._log "$1" GET /a 200 1 2
}
build TAuditServer
TAuditServer.new AU
AU.Router = RR
AU.OnLog = lg
fresh_replay get_x.req
AU.Transport = RT0
LOGS=()
AU.ServeOne 2>"$TMP/au.err"
cap 0
AU.Audit $'ev\x01il\x7f' 2>>"$TMP/au.err"
auerr="$(<"$TMP/au.err")"
if [[ "$CAPH" == *$'\nX-Audit: yes\n'* && "$CAPB" == "x-body" && "${LOGS[1]:-}" == "ev?il? GET /a 200 1 2" && -z "$auerr" ]]; then
    kt_test_pass "routed through inherited, audit line '${LOGS[1]}'"
else
    kt_test_fail "head='${CAPH:0:200}' body='$CAPB' logs=(${LOGS[*]}) stderr='$auerr'"
fi
AU.delete

kt_test_start "BeginServe with Transport '' creates an OWNED TNetcatTransport (SV_tr, Port/Address copied); EndServe frees it and resets Transport"
SV.Transport = ""
SV.Port = 12345
SV.Address = 127.0.0.2
r=0; SV.BeginServe || r=$?
p="$(SV_tr.Port)"; a="$(SV_tr.Address)"; tr="$(SV.Transport)"
SV.EndServe
tr2="$(SV.Transport)"
left=0; declare -p SV_tr_data >/dev/null 2>&1 && left=1
if [[ $r -eq 0 && "$tr" == SV_tr && "$p" == 12345 && "$a" == 127.0.0.2 && -z "$tr2" && $left -eq 0 ]]; then
    kt_test_pass "owned, configured, freed"
else
    kt_test_fail "rc=$r tr='$tr' port='$p' addr='$a' after='$tr2' left=$left"
fi

kt_test_start "BeginServe refuses a Transport that is not a THttpTransport instance (rc 2) and changes no trap"
before="$(trap -p INT TERM PIPE)"
SV.Transport = RR
r=0; SV.BeginServe || r=$?
SV.Active; a="$RESULT"
after="$(trap -p INT TERM PIPE)"
SV.Transport = ""
if [[ $r -eq 2 && "$a" == 0 && "$before" == "$after" ]]; then kt_test_pass "rc 2, inactive, traps untouched"; else kt_test_fail "rc=$r active=$a traps '$before' → '$after'"; fi

kt_test_start "SV.delete frees the server's own objects (the stopwatch) and leaves no SV_* variable"
had=0; declare -p SV_sw_data >/dev/null 2>&1 && declare -F SV_sw.Restart >/dev/null && had=1
SV.delete
RT0.delete
left=""
for v in SV_data SV_class SV_sw_data SV_sw_class SV_tr_data SV_req_data SV_resp_data; do declare -p "$v" >/dev/null 2>&1 && left+=" $v"; done
declare -F SV.Serve >/dev/null && left+=" SV.Serve"
declare -F SV_sw.Restart >/dev/null && left+=" SV_sw.Restart"
if [[ $had -eq 1 && -z "$left" ]]; then kt_test_pass "the owned stopwatch existed; nothing left"; else kt_test_fail "stopwatch-before=$had left:$left"; fi
RR.delete

# ===========================================================================
kt_test_section "1. real sockets: one long-lived server (facts 1, 2, 3, 6, 7, 8, 9, 13, 16)"
# ===========================================================================

SNIP_A='
printf -v A_BIG "%s" x
while (( ${#A_BIG} < 50000 )); do A_BIG+="$A_BIG"; done
A_BIG="${A_BIG:0:50000}"
A_COUNT=0
a_pid()   { $2.Write "$BASHPID"; }
a_count() { A_COUNT=$(( A_COUNT + 1 )); $2.Write "$A_COUNT"; }
a_utf()   { $2.Write "aжb"; }
a_echo()  { local c n; $1.Content; c="$RESULT"; $1.ContentLength; n="$RESULT"; $2.SetCustomHeader X-Len "$n"; $2.Write "$c"; }
a_big()   { $2.Content = "$A_BIG"; }
a_head()  { $2.SetCustomHeader X-Route head; $2.Write "head-body"; }
a_fail()  { $2.Write "partial"; return 3; }
a_err()   { printf "%s %s %s\n" "$1" "$2" "$3" >> "$SRV_DIR/onerror.log"; }
a_q()     { local k o=""; for k in x y z; do if $1.QueryField "$k"; then o+="$k=[$RESULT]"; else o+="$k=-"; fi; done; $2.Write "$o"; }
a_key()   { $1.RouteParam key; $2.Write "[$RESULT]"; }
a_hold()  {
    source "$THS_LIB"
    ths_poll 60 ths_prespawned "$SRV_DIR" || { $2.Write "no-prespawn"; return 0; }
    : > "$SRV_DIR/ready"
    ths_poll 60 test -e "$SRV_DIR/go" || { $2.Write "no-go"; return 0; }
    $2.Write "hold-done"
}
a_tick() {
    local p pp s=""
    for p in /proc/[0-9]*; do
        pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue
        if [[ "$pp" == "$BASHPID" ]]; then s+=" ${p#/proc/}"; fi
    done
    printf "%s\n" "${s# }" >> "$SRV_DIR/tick.log"
}
TICK_HOOK=a_tick
THttpRouter.new RT
RT.RegisterRoute /pid   GET  a_pid
RT.RegisterRoute /par   GET  a_pid
RT.RegisterRoute /count GET  a_count
RT.RegisterRoute /utf   GET  a_utf
RT.RegisterRoute /echo  POST a_echo
RT.RegisterRoute /big   GET  a_big
RT.RegisterRoute /head  GET  a_head
RT.RegisterRoute /fail  GET  a_fail
RT.RegisterRoute /q     GET  a_q
RT.RegisterRoute /k/:key GET a_key
RT.RegisterRoute /hold  GET  a_hold
S.Router = RT
S.OnRequestError = a_err
a_after() { local p pp n=0; for p in /proc/[0-9]*; do pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue; [[ "$pp" == "$BASHPID" ]] && n=$(( n + 1 )); done; printf "children=%s\n" "$n" >> "$SRV_DIR/result"; }
AFTER_HOOK=a_after
'

A_TITLES=(
    "fact 6: AcceptIdleTimeout 1000 → OnAcceptIdle ticks while the SAME listener stays alive (no respawn between ticks)"
    "fact 1: the handler runs in the server shell — \$BASHPID equal across requests and equal to the server's"
    "fact 1: state persists across requests (a counter: 1 2 3)"
    "fact 2 (wire): aжb → Content-Length: 4 and the exact bytes"
    "fact 2 (wire): a multibyte request body is read exactly (echo + X-Len = byte count)"
    "fact 16 (wire): HEAD on a GET-only route → the GET head, no body; POST → 405 + Allow: GET, HEAD"
    "404 for an unknown path; a failing handler → 500 with an empty body, OnRequestError got REQ RESP 3"
    "fact 13 (wire): hostile query values and route params round-trip as data, nothing executes"
    "fact 13 (wire): ?=x, ?&&, ?=, ?a=1&=2 do not abort the server"
    "fact 9: the drained close delivers a 50 kB body complete, 5/5 (curl)"
    "fact 9: an HTTP/1.0 client that reads to EOF sees EOF (raw /dev/tcp, 50 kB)"
    "fact 3 (socket, best effort): a client that sends a request and closes at once does not stop the next request"
    "fact 8: a connected but silent client gets 408 after RequestTimeout (2 s), and the next client is served"
    "fact 7 (D5): client 2 is accepted by the PRE-SPAWNED listener while request 1 is handled — no refusal — and answered after it"
    "fact 7: 8 parallel clients all get 200 and each request is handled exactly once (retry on curl rc 7, and on rc 55/56 = a reset in a listener backlog, never handled)"
    "access log: 'ADDR METHOD URI CODE BYTES MS' per answered request"
    "Terminate from OnAcceptIdle ends Serve: rc 0, empty LastError, RequestCount = the logged requests, no listener left, silent stderr"
)

if ! ths_have_nc; then
    ths_skip "${A_TITLES[@]}"
elif ! ths_start a "$SNIP_A" RT=2 IDLE_BUDGET=60; then
    for t in "${A_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "server A never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null) $(tr '\n' ' ' < "$THS_DIR/result" 2>/dev/null)"; done
else
    A_DIR="$THS_DIR"
    SPID="$(<"$A_DIR/pid")"

    kt_test_start "${A_TITLES[0]}"
    ths_poll 60 ths_ticks_ge 3
    mapfile -t TL < "$A_DIR/tick.log" 2>/dev/null
    same=1; for l in "${TL[@]}"; do [[ "$l" == "${TL[0]}" ]] || same=0; done
    if [[ ${#TL[@]} -ge 3 && -n "${TL[0]}" && $same -eq 1 ]]; then kt_test_pass "${#TL[@]} ticks, child pid(s) '${TL[0]}' throughout"; else kt_test_fail "ticks=(${TL[*]})"; fi

    kt_test_start "${A_TITLES[1]}"
    ths_curl "$TMP/pid1" "http://127.0.0.1:$THS_PORT/pid"; c1="$CURL_CODE"
    ths_curl "$TMP/pid2" "http://127.0.0.1:$THS_PORT/pid"; c2="$CURL_CODE"
    p1="$(<"$TMP/pid1")"; p2="$(<"$TMP/pid2")"
    if [[ "$c1$c2" == 200200 && -n "$p1" && "$p1" == "$p2" && "$p1" == "$SPID" ]]; then kt_test_pass "pid $p1 twice = server"; else kt_test_fail "codes $c1/$c2 pids '$p1' '$p2' server '$SPID'"; fi

    kt_test_start "${A_TITLES[2]}"
    o=""
    for i in 1 2 3; do ths_curl "$TMP/cnt" "http://127.0.0.1:$THS_PORT/count"; o+="$CURL_CODE:$(<"$TMP/cnt") "; done
    if [[ "$o" == "200:1 200:2 200:3 " ]]; then kt_test_pass "$o"; else kt_test_fail "$o"; fi

    kt_test_start "${A_TITLES[3]}"
    ths_curl "$TMP/utf" -i "http://127.0.0.1:$THS_PORT/utf"; ths_split "$TMP/utf"
    bytes="$(LC_ALL=C; b="$THS_BODY"; printf '%s' "${#b}")"
    if [[ "$CURL_CODE" == 200 && "$THS_HEAD" == *$'\nContent-Length: 4\n'* && "$THS_BODY" == "aжb" && "$bytes" == 4 ]]; then kt_test_pass "Content-Length: 4, aжb"; else kt_test_fail "code=$CURL_CODE head='${THS_HEAD:0:200}' body='$THS_BODY'"; fi

    kt_test_start "${A_TITLES[4]}"
    # The body from a FILE: a native curl receives its command line through the
    # Windows code page, where Cyrillic arguments turn into '?'.
    printf '%s' 'дом ok' > "$TMP/echo.body"
    ths_curl "$TMP/echo" -i --data-binary "@$TMP/echo.body" -H 'Content-Type: text/plain' "http://127.0.0.1:$THS_PORT/echo"; ths_split "$TMP/echo"
    if [[ "$CURL_CODE" == 200 && "$THS_BODY" == 'дом ok' && "$THS_HEAD" == *$'\nX-Len: 9\n'* && "$THS_HEAD" == *$'\nContent-Length: 9\n'* ]]; then kt_test_pass "9 bytes both ways"; else kt_test_fail "code=$CURL_CODE head='${THS_HEAD:0:250}' body='$THS_BODY'"; fi

    kt_test_start "${A_TITLES[5]}"
    ths_curl "$TMP/getb" -D "$TMP/geth" "http://127.0.0.1:$THS_PORT/head"; gc="$CURL_CODE"
    ths_raw "$TMP/headraw" "HEAD /head HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/headraw"; hh="$THS_HEAD"; hb="$THS_BODY"
    gh="$(<"$TMP/geth")"; gh="${gh//$'\r'/}"; gh="${gh%$'\n'}"
    strip_date() { local l o=""; while IFS= read -r l; do [[ "$l" == Date:* || -z "$l" ]] || o+="$l|"; done <<< "$1"; printf '%s' "$o"; }
    g1="$(strip_date "$gh")"; h1="$(strip_date "$hh")"
    ths_curl "$TMP/p405" -i -X POST --data-binary x "http://127.0.0.1:$THS_PORT/head"; ths_split "$TMP/p405"
    if [[ "$gc" == 200 && $RAW_RC -eq 0 && "$g1" == "$h1" && "$g1" == *"X-Route: head|"*"Content-Length: 9|"* && -z "$hb" \
          && "$CURL_CODE" == 405 && "$THS_HEAD" == *$'\nAllow: GET, HEAD\n'* ]]; then
        kt_test_pass "identical heads, no HEAD body, 405 Allow: GET, HEAD"
    else
        kt_test_fail "get='$g1' head='$h1' headbody='${hb:0:40}' 405=$CURL_CODE '${THS_HEAD:0:160}'"
    fi

    kt_test_start "${A_TITLES[6]}"
    ths_curl "$TMP/nf" "http://127.0.0.1:$THS_PORT/none"; c404="$CURL_CODE"
    ths_curl "$TMP/f500" -i "http://127.0.0.1:$THS_PORT/fail"; ths_split "$TMP/f500"
    oe="$(<"$A_DIR/onerror.log")"
    if [[ "$c404" == 404 && "$CURL_CODE" == 500 && -z "$THS_BODY" && "$THS_HEAD" == *$'\nContent-Length: 0\n'* && "$oe" == "S_req S_resp 3" ]]; then
        kt_test_pass "404; 500 empty; OnRequestError '$oe'"
    else
        kt_test_fail "404=$c404 500=$CURL_CODE body='$THS_BODY' onerror='$oe'"
    fi

    kt_test_start "${A_TITLES[7]}"
    ths_raw "$TMP/hq" "GET /q?x=\$(touch%20pwn)&y=%60touch%20pwn%60&z=a%26b%3B%20rm HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/hq"; b1="$THS_BODY"
    ths_raw "$TMP/hk" "GET /k/%24%28touch%20pwn%29%3B%60id%60 HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/hk"; b2="$THS_BODY"
    if [[ "$b1" == 'x=[$(touch pwn)]y=[`touch pwn`]z=[a&b; rm]' && "$b2" == '[$(touch pwn);`id`]' \
          && ! -e "$A_DIR/pwn" && ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" ]]; then
        kt_test_pass "verbatim, no pwn"
    else
        kt_test_fail "q='$b1' k='$b2' pwn: $(ls "$A_DIR"/pwn "$TMP"/pwn 2>/dev/null)"
    fi

    kt_test_start "${A_TITLES[8]}"
    o=""
    for q in '=x' '&&' '=' 'a=1&=2'; do
        ths_raw "$TMP/eq" "GET /q?$q HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/eq"; o+="${THS_HEAD%%$'\n'*}|$THS_BODY "
    done
    ths_curl "$TMP/alive" "http://127.0.0.1:$THS_PORT/pid"
    want="HTTP/1.1 200 OK|x=-y=-z=- HTTP/1.1 200 OK|x=-y=-z=- HTTP/1.1 200 OK|x=-y=-z=- HTTP/1.1 200 OK|x=-y=-z=- "
    if [[ "$o" == "$want" && "$CURL_CODE" == 200 ]]; then kt_test_pass "four 200s, alive"; else kt_test_fail "'$o' alive=$CURL_CODE"; fi

    kt_test_start "${A_TITLES[9]}"
    ok=0; o=""
    for i in 1 2 3 4 5; do
        ths_curl "$TMP/big$i" "http://127.0.0.1:$THS_PORT/big"
        sz=$(wc -c < "$TMP/big$i"); o+="$CURL_CODE/$sz "
        if [[ "$CURL_CODE" == 200 && "$sz" -eq 50000 ]] && ! grep -q '[^x]' "$TMP/big$i"; then ok=$(( ok + 1 )); fi
    done
    if [[ $ok -eq 5 ]]; then kt_test_pass "5/5 × 50000 bytes"; else kt_test_fail "$ok/5: $o"; fi

    kt_test_start "${A_TITLES[10]}"
    ths_raw "$TMP/bigraw" "GET /big HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/bigraw"
    if [[ $RAW_RC -eq 0 && ${#THS_BODY} -eq 50000 && "$THS_HEAD" == *$'\nConnection: close'* ]]; then kt_test_pass "EOF after 50000 bytes"; else kt_test_fail "rc=$RAW_RC (124 = no EOF) body=${#THS_BODY}"; fi

    kt_test_start "${A_TITLES[11]}"
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" && printf 'GET /big HTTP/1.0\r\n\r\n' >&3 && exec 3>&- ) 2>/dev/null
    ths_curl "$TMP/after" "http://127.0.0.1:$THS_PORT/count"
    if [[ "$CURL_CODE" == 200 && "$(<"$TMP/after")" == 4 ]]; then kt_test_pass "next request 200 (count 4)"; else kt_test_fail "code=$CURL_CODE body='$(<"$TMP/after")'"; fi

    kt_test_start "${A_TITLES[12]}"
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || exit 7; : > "$TMP/silent.conn"; timeout 30 cat <&3 > "$TMP/silent.out" ) 2>/dev/null
    ths_curl "$TMP/after408" "http://127.0.0.1:$THS_PORT/pid"
    s="$(<"$TMP/silent.out")"
    if [[ -e "$TMP/silent.conn" && "$s" == "HTTP/1.1 408 Request Timeout"* && "$CURL_CODE" == 200 ]]; then kt_test_pass "408, then 200"; else kt_test_fail "silent='${s:0:60}' next=$CURL_CODE"; fi

    kt_test_start "${A_TITLES[13]}"
    rm -f "$A_DIR/ready" "$A_DIR/go"
    ths_raw "$TMP/c1.out" "GET /hold HTTP/1.0${CRLF}${CRLF}" &
    C1=$!
    rdy=0; ths_poll 60 test -e "$A_DIR/ready" && rdy=1
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || { : > "$TMP/c2.refused"; exit 7; }
      : > "$TMP/c2.conn"; printf 'GET /count HTTP/1.0\r\n\r\n' >&3; timeout 30 cat <&3 > "$TMP/c2.out" ) 2>/dev/null &
    C2=$!
    ths_poll 30 eval '[[ -e $TMP/c2.conn || -e $TMP/c2.refused ]]'
    : > "$A_DIR/go"
    wait "$C1"; wait "$C2"
    ths_split "$TMP/c1.out"; b1="$THS_BODY"; ths_split "$TMP/c2.out"; b2="$THS_BODY"; h2="${THS_HEAD%%$'\n'*}"
    mapfile -t AL < "$A_DIR/access.log"
    ih=-1; ic=-1
    for (( i = 0; i < ${#AL[@]}; i++ )); do
        [[ "${AL[i]}" == *" GET /hold 200 "* ]] && ih=$i
        [[ "${AL[i]}" == *" GET /count 200 "* ]] && ic=$i
    done
    if [[ $rdy -eq 1 && ! -e "$TMP/c2.refused" && -e "$TMP/c2.conn" && "$b1" == hold-done && "$h2" == "HTTP/1.1 200 OK" && "$b2" == 5 && $ih -ge 0 && $ic -gt $ih ]]; then
        kt_test_pass "no refusal; hold-done, then count 5 (log order $ih < $ic)"
    else
        kt_test_fail "ready=$rdy refused=$([[ -e $TMP/c2.refused ]] && echo y) c1='$b1' c2='$h2|$b2' order $ih/$ic"
    fi

    kt_test_start "${A_TITLES[14]}"
    # GNU nc closes its listening socket after its one accept, which RESETS the
    # connections already queued in that socket's backlog (measured P2: 2-3 of
    # 8 parallel clients get curl rc 56 per round, with or without the
    # pre-spawn; 5.3.9 also showed one rc 55, the send side of the same reset).
    # Such a request never reached a handler, so for this idempotent GET the
    # client retries on rc 55/56 as well as on rc 7 — and the
    # access log must then show EXACTLY 8 /par requests: a retried request
    # that had been handled would make it 9+.
    par_client() {
        local i r=0 code=""
        PAR_RESETS=0
        for (( i = 0; i < 60; i++ )); do
            r=0; code="$(curl --noproxy '*' -s -m 30 -o "$TMP/par$1" -w '%{http_code}' "http://127.0.0.1:$THS_PORT/par")" || r=$?
            if (( r == 55 || r == 56 )); then PAR_RESETS=$(( PAR_RESETS + 1 )); fi
            if (( r != 7 && r != 55 && r != 56 )); then break; fi
            sleep 0.1
        done
        printf '%s %s %s\n' "$r" "$code" "$PAR_RESETS" > "$TMP/par$1.rc"
    }
    pp=()
    for i in 1 2 3 4 5 6 7 8; do par_client "$i" & pp+=($!); done
    wait "${pp[@]}"
    o=""; ok=0; resets=0
    for i in 1 2 3 4 5 6 7 8; do
        read -r r code nr < "$TMP/par$i.rc"; o+="$r/$code/$nr|"
        if [[ "$r $code" == "0 200" ]]; then ok=$(( ok + 1 )); fi
        resets=$(( resets + nr ))
    done
    handled=0; while IFS= read -r l; do [[ "$l" == *" GET /par 200 "* ]] && handled=$(( handled + 1 )); done < "$A_DIR/access.log"
    if [[ $ok -eq 8 && $handled -eq 8 ]]; then kt_test_pass "8/8, handled exactly 8 (backlog resets retried: $resets)"; else kt_test_fail "$ok/8 handled=$handled: $o"; fi

    kt_test_start "${A_TITLES[15]}"
    l="$(grep ' GET /utf ' "$A_DIR/access.log")"
    l4="$(grep ' 408 ' "$A_DIR/access.log")"
    if [[ "$l" =~ ^127\.0\.0\.1:[0-9]+\ GET\ /utf\ 200\ 4\ [0-9]+$ && "$l4" =~ ^127\.0\.0\.1:[0-9]+\ -\ -\ 408\ 0\ [0-9]+$ ]]; then kt_test_pass "'$l' / '$l4'"; else kt_test_fail "utf='$l' 408='$l4'"; fi

    kt_test_start "${A_TITLES[16]}"
    ths_finish
    ths_result rc; rc="$THS_V"; ths_result le; le="$THS_V"; ths_result n; n="$THS_V"; ths_result children; ch="$THS_V"
    nl=0; while IFS= read -r l; do nl=$(( nl + 1 )); done < "$A_DIR/access.log"
    serr="$(<"$A_DIR/err")"
    if [[ $THS_RC -eq 0 && "$rc" == 0 && -z "$le" && "$n" == "$nl" && "$ch" == 0 && -z "$serr" ]]; then
        kt_test_pass "rc 0, $n requests = $nl log lines, no child left"
    else
        kt_test_fail "exit=$THS_RC rc=$rc le='$le' n=$n log=$nl children=$ch stderr='${serr:0:300}'"
    fi
fi

# ===========================================================================
kt_test_section "2. fact 4: a busy port → Serve rc 1, LastError = the bind line, no listener left"
# ===========================================================================

B_TITLE="fact 4: busy port → Serve rc 1 at once, LastError 'Error: Couldn't setup listening socket (err=-3)', no child left"
if ! ths_have_nc; then
    ths_skip "$B_TITLE"
else
    kt_test_start "$B_TITLE"
    BL=""; bport=""
    for try in 1 2 3 4 5; do
        ths_nport; bport="$THS_PORT"
        "$THS_NC" -l -n -vv -w 170 -s 127.0.0.1 -p "$bport" >/dev/null 2>"$TMP/blocker.err" </dev/null &
        BL=$!
        if ths_poll 30 grep -q '^Listening on' "$TMP/blocker.err"; then break; fi
        kill "$BL" 2>/dev/null; wait "$BL" 2>/dev/null; BL=""
    done
    B_DIR="$TMP/b"; rm -rf "$B_DIR"; mkdir -p "$B_DIR/tmp"
    ths_server_script "$B_DIR/srv.sh" '
b_after() { local p pp n=0; for p in /proc/[0-9]*; do pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue; [[ "$pp" == "$BASHPID" ]] && n=$(( n + 1 )); done; printf "children=%s\n" "$n" >> "$SRV_DIR/result"; }
AFTER_HOOK=b_after'
    if (( THS_NC_ENV )); then export KCL_NC="$THS_NC"; fi
    UNIT="$UNIT" SRV_DIR="$B_DIR" PORT="$bport" TMPDIR="$B_DIR/tmp" timeout 180 "$BASH" "$B_DIR/srv.sh" >"$B_DIR/out" 2>"$B_DIR/err" </dev/null
    brc=$?
    if [[ -n "$BL" ]]; then kill "$BL" 2>/dev/null; wait "$BL" 2>/dev/null; fi
    THS_DIR="$B_DIR"
    ths_result rc; rc="$THS_V"; ths_result le; le="$THS_V"; ths_result children; ch="$THS_V"
    left="$(ls "$B_DIR/tmp")"
    if [[ -n "$BL$bport" && $brc -eq 0 && "$rc" == 1 && "$le" == "Error: Couldn't setup listening socket (err=-3)" && "$ch" == 0 && -z "$left" && -z "$(<"$B_DIR/err")" ]]; then
        kt_test_pass "rc 1, '$le', no child, no temp dir"
    else
        kt_test_fail "exit=$brc rc=$rc le='$le' children=$ch tmp='$left' stderr='$(<"$B_DIR/err")'"
    fi
fi

# ===========================================================================
kt_test_section "3. fact 5: no usable nc → Accept rc 2 at once, LastError, no respawn loop"
# ===========================================================================

C_TITLES=(
    "fact 5: NcBinary=/no/such/nc → Serve rc 1 at once, LastError 'nc not found …', nothing spawned, no child, no temp dir"
    "fact 5: NcBinary '', KCL_NC unset, no nc on PATH → the same"
    "an nc that cannot be executed (bad interpreter) → Serve rc 1, LastError = the exec error line, no child, no temp dir"
    "an nc that exits at once with an unknown stderr line → Serve rc 1, LastError = that line, spawned exactly ONCE (no respawn loop)"
)
if ! ths_have_nc; then
    ths_skip "${C_TITLES[@]}"
else
    C_DIR="$TMP/c"; rm -rf "$C_DIR"; mkdir -p "$C_DIR/tmp"
    printf '#!/no/such/interp\n' > "$C_DIR/fake_nc"; chmod +x "$C_DIR/fake_nc"
    printf '#!/bin/bash\nprintf x >> "%s/spawns"\nprintf "fake: no listener here\\n" >&2\nexit 1\n' "$C_DIR" > "$C_DIR/once_nc"; chmod +x "$C_DIR/once_nc"
    cat > "$C_DIR/srv.sh" <<'EOF'
exec </dev/null
cd "$SRV_DIR" || exit 90
source "$UNIT" || exit 91
unset -v KCL_NC
kids() { local p pp n=0; for p in /proc/[0-9]*; do pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue; [[ "$pp" == "$BASHPID" ]] && n=$(( n + 1 )); done; KIDS=$n; }
one() {   # TAG NCBINARY [PATH]
    local rc=0 t0 ms le dirs d
    TNetcatTransport.new T
    T.Port = "$PORT"
    T.NcBinary = "$2"
    THttpServer.new S
    S.Transport = T
    S.AcceptIdleTimeout = 1000
    t0=${EPOCHREALTIME//[!0-9]/}
    if [[ -n "${3:-}" ]]; then
        PATH="$3" S.Serve || rc=$?
    else
        S.Serve || rc=$?
    fi
    ms=$(( (${EPOCHREALTIME//[!0-9]/} - t0) / 1000 ))
    S.LastError; le="$RESULT"
    kids
    dirs=""; for d in "$TMPDIR"/*; do [[ -e "$d" ]] && dirs+=" $d"; done
    printf '%s rc=%s ms=%s kids=%s dirs=[%s] le=%s\n' "$1" "$rc" "$ms" "$KIDS" "$dirs" "$le" >> "$SRV_DIR/result"
    S.delete
    T.delete
}
one missing /no/such/nc
one nopath "" /no/such/dir
one fake "$SRV_DIR/fake_nc"
one once "$SRV_DIR/once_nc"
: > "$SRV_DIR/ended"
EOF
    ths_nport
    UNIT="$UNIT" SRV_DIR="$C_DIR" PORT="$THS_PORT" TMPDIR="$C_DIR/tmp" timeout 180 "$BASH" "$C_DIR/srv.sh" >"$C_DIR/out" 2>"$C_DIR/err" </dev/null
    crc=$?
    cres="$(<"$C_DIR/result")"
    cerr="$(<"$C_DIR/err")"
    l_missing="$(grep '^missing ' <<< "$cres")"; l_nopath="$(grep '^nopath ' <<< "$cres")"
    l_fake="$(grep '^fake ' <<< "$cres")"; l_once="$(grep '^once ' <<< "$cres")"
    spawns="$(cat "$C_DIR/spawns" 2>/dev/null)"
    kt_test_start "${C_TITLES[0]}"
    if [[ "$l_missing" =~ ^missing\ rc=1\ ms=([0-9]+)\ kids=0\ dirs=\[\]\ le=nc\ not\ found ]] && (( BASH_REMATCH[1] < 5000 )); then kt_test_pass "$l_missing"; else kt_test_fail "exit=$crc '$l_missing' stderr='$cerr'"; fi
    kt_test_start "${C_TITLES[1]}"
    if [[ "$l_nopath" =~ ^nopath\ rc=1\ ms=([0-9]+)\ kids=0\ dirs=\[\]\ le=nc\ not\ found ]] && (( BASH_REMATCH[1] < 5000 )); then kt_test_pass "$l_nopath"; else kt_test_fail "'$l_nopath'"; fi
    kt_test_start "${C_TITLES[2]}"
    if [[ "$l_fake" =~ ^fake\ rc=1\ ms=([0-9]+)\ kids=0\ dirs=\[\]\ le=.*(bad\ interpreter|cannot\ execute|required\ file\ not\ found) ]] && (( BASH_REMATCH[1] < 5000 )); then
        kt_test_pass "${l_fake:0:160}"
    else
        kt_test_fail "'$l_fake'"
    fi
    kt_test_start "${C_TITLES[3]}"
    if [[ "$l_once" =~ ^once\ rc=1\ ms=[0-9]+\ kids=0\ dirs=\[\]\ le=fake:\ no\ listener\ here$ && "$spawns" == x && -z "$cerr" ]]; then
        kt_test_pass "one spawn, '$l_once'"
    else
        kt_test_fail "'$l_once' spawns='$spawns' stderr='$cerr'"
    fi
fi
