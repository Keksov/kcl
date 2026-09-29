#!/bin/bash
# 006_Application.sh — thttpserver P3: THttpApplication : TCustomApplication
# (PLAN §1.3, §2.7, §2.11; §3 facts 10 (the App.Run path), 18 and 22).
#
#   §0 construction, options, ServerClass (no socket): the defaults; routes
#      registered BEFORE Initialize; --port=N / -p N / --address=A through the
#      inherited FPC parser (last occurrence wins, short name first, an option
#      beats a value assigned before Initialize); every refusal rc 2 with
#      nothing created; ServerClass (D9) — a non-server, a missing, a hostile,
#      an abstract class rc 2, a descendant accepted; the wiring; a second
#      Initialize replaces the server.
#   §1 App.Run over TReplayTransport and two test transports (no socket): the
#      DoRun mapping — MaxRequests, a route calling App.Terminate (/quit), the
#      transport fatal (Run rc 1, HandleException never reached), idle ticks
#      (OnAcceptIdle fires under App.Run — the P3 move into ServeOne), the
#      Stopping property, the Terminate override, TERM and SIGPIPE on the app
#      path (in child bashes: a broken trap would kill the test shell), fact 22
#      through ServerClass, what Run leaves behind (fact 10, replay half), Run /
#      DoRun before Initialize, a BeginServe refusal, Destroy with and without
#      a descendant destructor, the fork-free DoRun.
#   §2 real sockets (the child is an application script, argv on its command
#      line): `--port=N` serves on N, routes registered before Initialize,
#      /quit ends Run and nothing is left (fact 10, socket half); `-p N` with
#      ServerClass = TAuthServer → 401 / 200 (fact 18) and `inherited
#      HandleRequest "$@"` over the wire (fact 22); TERM while a request is
#      handled and TERM while idle with no ticks at all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpapplication.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
export THS_LIB="$SCRIPT_DIR/_ths_socket.sh"
source "$THS_LIB"
CRLF=$'\r\n'
cd "$TMP" || exit 1

kt_test_section "006: THttpApplication (P3)"

rq() { printf '%s' "$2" > "$TMP/$1"; }
rq get_a.req   "GET /a HTTP/1.0${CRLF}${CRLF}"
rq get_d.req   "GET /d/x%20y HTTP/1.0${CRLF}${CRLF}"
rq quit.req    "POST /quit HTTP/1.0${CRLF}${CRLF}"
rq auth.req    "GET /a HTTP/1.0${CRLF}Authorization: Bearer t0k${CRLF}${CRLF}"

# capf FILE — a captured response into CAP / CAPH (head, CR removed) / CAPB.
capf() {
    CAP=""; [[ -n "$1" && -f "$1" ]] && CAP="$(<"$1")"
    CAPH="${CAP%%$'\r\n\r\n'*}"; CAPH="${CAPH//$'\r'/}"
    if [[ "$CAP" == *$'\r\n\r\n'* ]]; then CAPB="${CAP#*$'\r\n\r\n'}"; else CAPB=""; fi
}
# replay NAME FILE… — a fresh TReplayTransport NAME fed with the request files.
replay() {
    local n="$1" f
    shift
    if declare -F "$n.delete" >/dev/null; then "$n.delete"; fi
    TReplayTransport.new "$n"
    for f in "$@"; do "$n.AddRequestFile" "$TMP/$f"; done
}
# left_of PREFIX — every variable / function named PREFIX_* or PREFIX.* into LEFT.
left_of() {
    local v
    LEFT=""
    for v in "$1_data" "$1_class" "$1_router_data" "$1_router_class" "$1_router_pat" "$1_server_data" "$1_server_class" \
             "$1_server_sw_data" "$1_server_sw_class" "$1_server_req_data" "$1_server_resp_data" "$1_server_tr_data"; do
        if declare -p "$v" >/dev/null 2>&1; then LEFT+=" $v"; fi
    done
    for v in "$1.Run" "$1.Port" "$1_router.RegisterRoute" "$1_server.ServeOne" "$1_server_sw.Restart"; do
        if declare -F "$v" >/dev/null; then LEFT+=" $v"; fi
    done
}

# Test classes shared by §0 and §1.
class TAbsServer : THttpServer
    public
        constructor Create
        abstract proc Extra
end
ABS_CTOR=0
TAbsServer.Create() { ABS_CTOR=$(( ABS_CTOR + 1 )); inherited; }
build TAbsServer

class TArgServer : THttpServer
    public
        override proc HandleRequest
end
ARGS_SEEN=()
TArgServer.HandleRequest() {
    local __g_rc=0
    ARGS_SEEN+=("$#:$*")
    if ! $1.HasHeader authorization; then
        $2.Code = 401
        $2.Write denied
        return 0
    fi
    inherited HandleRequest "$@" || __g_rc=$?
    return "$__g_rc"
}
build TArgServer

# TIdleTransport — every Accept is an idle tick (rc 1); after 50 a fatal, so a
# broken stop can never spin forever.
class TIdleTransport : THttpTransport
    public
        var Ticks
        constructor Create
        override func Accept
        override proc CloseConnection
        override proc Shutdown
end
TIdleTransport.Create() { inherited; Ticks=0; }
TIdleTransport.Accept() {
    Ticks=$(( Ticks + 1 ))
    if (( Ticks > 50 )); then
        _lastError="TIdleTransport: 50 ticks"
        kk._return ""
        return 2
    fi
    kk._return ""
    return 1
}
TIdleTransport.CloseConnection() { return 0; }
TIdleTransport.Shutdown() { return 0; }
build TIdleTransport

# ===========================================================================
kt_test_section "0. construction, options, ServerClass (no socket)"
# ===========================================================================

kt_test_start "defaults: Port 8080 and Address 127.0.0.1 (read silently, RESULT), ServerClass THttpServer, Server '', AppRouter = an empty THttpRouter"
THttpApplication.new A0
A0.Port >"$TMP/a0.out"; p="$RESULT"; A0.Address >>"$TMP/a0.out"; a="$RESULT"
A0.Server >>"$TMP/a0.out"; s="$RESULT"; A0.AppRouter >>"$TMP/a0.out"; r="$RESULT"
o1="|$(<"$TMP/a0.out")"
sc="$(A0.ServerClass)"
rcls=""; v="${r}_class"; [[ -n "$r" ]] && rcls="${!v:-}"
"$r.RouteCount" 2>/dev/null; rn="$RESULT"
if [[ "$o1" == "|" && "$p" == 8080 && "$a" == 127.0.0.1 && "$sc" == THttpServer && -z "$s" && "$r" == A0_router && "$rcls" == THttpRouter && "$rn" == 0 ]]; then
    kt_test_pass "8080 127.0.0.1 THttpServer '' A0_router(0)"
else
    kt_test_fail "print='$o1' port=$p addr=$a class=$sc server='$s' router='$r'($rcls, $rn)"
fi

kt_test_start "routes registered BEFORE Initialize land on AppRouter and survive Initialize; RegisterRoute's rc passes through (2 malformed, 1 second default)"
f0() { $2.Write f0; }
r1=0; A0.RegisterRoute /a GET f0 || r1=$?
r2=0; A0.RegisterRoute /b f0 || r2=$?
r3=0; A0.RegisterRoute /x GET 'no such' || r3=$?
r4=0; A0.RegisterRoute /d GET f0 1 || r4=$?
r5=0; A0.RegisterRoute /e GET f0 1 || r5=$?
A0.AppRouter; "$RESULT.RouteCount"; n1="$RESULT"
i=0; A0.Initialize || i=$?
A0.AppRouter; "$RESULT.RouteCount"; n2="$RESULT"
A0.Server; s="$RESULT"
sr="$("$s.Router" 2>/dev/null)"
if [[ "$r1$r2$r4 $r3 $r5" == "000 2 1" && "$n1" == 3 && $i -eq 0 && "$n2" == 3 && "$sr" == A0_router ]]; then
    kt_test_pass "3 routes before and after; rc 2 / rc 1 passed through; Server.Router = A0_router"
else
    kt_test_fail "rcs=$r1$r2$r4/$r3/$r5 count $n1→$n2 init=$i server.Router='$sr'"
fi

kt_test_start "Initialize wires the server: ServerClass instance \${App}_server, Router, Port, Address copied; Stopping 0, Active 0"
cls=""; v="${s}_class"; cls="${!v:-}"
sp="$("$s.Port")"; sa="$("$s.Address")"
"$s.Stopping"; st="$RESULT"; "$s.Active"; ac="$RESULT"
if [[ "$s" == A0_server && "$cls" == THttpServer && "$sp" == 8080 && "$sa" == 127.0.0.1 && "$st" == 0 && "$ac" == 0 ]]; then
    kt_test_pass "A0_server: THttpServer 8080 127.0.0.1"
else
    kt_test_fail "server='$s' class='$cls' port='$sp' addr='$sa' stopping='$st' active='$ac'"
fi
A0.delete

# opt_case "ARGV" PRESET WANT_RC WANT_PORT WANT_ADDR — a fresh application
# with ARGV (split on spaces), Port preset to PRESET unless '-', Initialize.
OPT_BAD=""
opt_case() {
    local -a argv=()
    local rc=0 p a sp sa s
    if [[ -n "$1" ]]; then read -ra argv <<< "$1"; fi
    THttpApplication.new OA "${argv[@]}"
    if [[ "$2" != - ]]; then OA.Port = "$2"; fi
    OA.Initialize || rc=$?
    OA.Port; p="$RESULT"; OA.Address; a="$RESULT"; OA.Server; s="$RESULT"
    if (( rc == 0 )); then sp="$("$s.Port")"; sa="$("$s.Address")"; else sp=-; sa=-; fi
    if [[ $rc -ne $3 || "$p" != "$4" || "$a" != "$5" ]] || { (( rc == 0 )) && [[ "$sp" != "$4" || "$sa" != "$5" ]]; } || { (( rc != 0 )) && [[ -n "$s" ]]; }; then
        OPT_BAD+=" [$1 preset=$2: rc=$rc port=$p addr=$a server='$s' $sp/$sa]"
    fi
    OA.delete
}

kt_test_start "options: none / --port=N / -p N / --address=A / mixed with non-options → Port, Address and the server's copies"
OPT_BAD=""
opt_case ""                                   - 0 8080 127.0.0.1
opt_case "--port=9001"                        - 0 9001 127.0.0.1
opt_case "-p 9002"                            - 0 9002 127.0.0.1
opt_case "--address=127.0.0.5"                - 0 8080 127.0.0.5
opt_case "serve -p 9003 --address=127.0.0.6 extra" - 0 9003 127.0.0.6
opt_case "--port=+9010"                       - 0 9010 127.0.0.1
if [[ -z "$OPT_BAD" ]]; then kt_test_pass "6 argv shapes"; else kt_test_fail "$OPT_BAD"; fi

kt_test_start "FPC parser semantics: the LAST --port wins; the SHORT name is looked up first (-p beats a later --port); an option beats a value assigned before Initialize, and the preset stands without one"
OPT_BAD=""
opt_case "--port=9004 --port=9005"            - 0 9005 127.0.0.1
opt_case "-p 9006 --port=9007"                - 0 9006 127.0.0.1
opt_case "--port=9008"                        7001 0 9008 127.0.0.1
opt_case ""                                   7002 0 7002 127.0.0.1
if [[ -z "$OPT_BAD" ]]; then kt_test_pass "last wins; short first; option > preset > default"; else kt_test_fail "$OPT_BAD"; fi

kt_test_start "refusals → rc 2, no server created, Port/Address unchanged: --port=abc, =0, =65536, =8x, --port (no '='), -p (no value), --address="
OPT_BAD=""
opt_case "--port=abc"      - 2 8080 127.0.0.1
opt_case "--port=0"        - 2 8080 127.0.0.1
opt_case "--port=65536"    - 2 8080 127.0.0.1
opt_case "--port=8x"       - 2 8080 127.0.0.1
opt_case "--port 9000"     - 2 8080 127.0.0.1
opt_case "-p"              - 2 8080 127.0.0.1
opt_case "--address="      - 2 8080 127.0.0.1
if [[ -z "$OPT_BAD" ]]; then kt_test_pass "7 refusals"; else kt_test_fail "$OPT_BAD"; fi

kt_test_start "a refused Initialize is silent, and prints exactly ONE kk.debug line under VERBOSE_KKLASS=debug"
THttpApplication.new OB --port=abc
r1=0; OB.Initialize >"$TMP/ob.out" 2>"$TMP/ob.err" || r1=$?
e1="$(<"$TMP/ob.err")$(<"$TMP/ob.out")"
r2=0; VERBOSE_KKLASS=debug OB.Initialize >"$TMP/ob.out" 2>"$TMP/ob.err" || r2=$?
mapfile -t EL < "$TMP/ob.err"
if [[ $r1 -eq 2 && $r2 -eq 2 && -z "$e1" && ${#EL[@]} -eq 1 && "${EL[0]}" == *port* && ! -s "$TMP/ob.out" ]]; then kt_test_pass "silent; debug: '${EL[0]}'"; else kt_test_fail "rc $r1/$r2 off='$e1' debug=(${EL[*]})"; fi
OB.delete

kt_test_start "ServerClass (D9): a non-server class, a missing, an empty, a hostile name and an ABSTRACT THttpServer descendant → rc 2, nothing created, no constructor run, nothing executed"
THttpApplication.new OC
bad=""
for c in TReplayTransport THttpRouter NoSuchClass006 '' '$(touch pwn)' 'THttpServer;touch pwn' TAbsServer; do
    OC.ServerClass = "$c"
    r=0; OC.Initialize 2>"$TMP/oc.err" || r=$?
    OC.Server
    [[ $r -eq 2 && -z "$RESULT" && ! -s "$TMP/oc.err" ]] || bad+=" [$c: rc=$r server='$RESULT' err='$(<"$TMP/oc.err")']"
done
[[ -e "$TMP/pwn" || -e "$SCRIPT_DIR/pwn" ]] && bad+=" pwn"
[[ $ABS_CTOR -eq 0 ]] || bad+=" abstract-ctor-ran=$ABS_CTOR"
if [[ -z "$bad" ]]; then kt_test_pass "7 refused, silent"; else kt_test_fail "$bad"; fi

kt_test_start "ServerClass = a concrete descendant (TArgServer) → Initialize rc 0, Server is a TArgServer, wired like the base"
OC.ServerClass = TArgServer
r=0; OC.Initialize || r=$?
OC.Server; s="$RESULT"; v="${s}_class"; cls="${!v:-}"
sr="$("$s.Router")"
if [[ $r -eq 0 && "$s" == OC_server && "$cls" == TArgServer && "$sr" == OC_router ]]; then kt_test_pass "TArgServer, router wired"; else kt_test_fail "rc=$r server='$s' class='$cls' router='$sr'"; fi

kt_test_start "a second Initialize replaces the server: the old instance is freed (its stopwatch too), the new one is fresh (RequestCount 0, the new ServerClass)"
"$s.MaxRequests" = 5
OC.ServerClass = THttpServer
r=0; OC.Initialize || r=$?
OC.Server; s2="$RESULT"; v="${s2}_class"; cls="${!v:-}"
"$s2.MaxRequests"; mr="$RESULT"; "$s2.RequestCount"; rcnt="$RESULT"
nsw=0; declare -F OC_server_sw.Restart >/dev/null && nsw=1
if [[ $r -eq 0 && "$s2" == OC_server && "$cls" == THttpServer && "$mr" == 0 && "$rcnt" == 0 && $nsw -eq 1 ]]; then kt_test_pass "fresh THttpServer"; else kt_test_fail "rc=$r class='$cls' MaxRequests=$mr count=$rcnt sw=$nsw"; fi
OC.delete

# ===========================================================================
kt_test_section "1. App.Run over replay and test transports (no socket)"
# ===========================================================================

# app_replay NAME FILE… — THttpApplication NAME, Initialize, its server on a
# fresh TReplayTransport NAME_T with the files; SRV = the server.
app_replay() {
    local n="$1"
    shift
    if declare -F "$n.delete" >/dev/null; then "$n.delete"; fi
    THttpApplication.new "$n"
    "$n.Initialize"
    replay "${n}_T" "$@"
    "$n.Server"; SRV="$RESULT"
    "$SRV.Transport" = "${n}_T"
}
fa()   { $2.Write "a"; }
fd()   { local x; $1.RouteParam x; x="$RESULT"; $2.Write "d:$x:$3:$#"; }
fquit() { R1.Terminate; $2.Write bye; }

kt_test_start "MaxRequests 2 with 3 queued: Run rc 0, exactly 2 served, Terminated true, Active 0 after, nothing on stderr (no 'Exception:' line)"
app_replay R1 get_a.req get_a.req get_a.req
R1.RegisterRoute /a GET fa
"$SRV.MaxRequests" = 2
r=0; R1.Run >"$TMP/r1.out" 2>"$TMP/r1.err" || r=$?
"$SRV.RequestCount"; n="$RESULT"; t="$(R1.Terminated)"; "$SRV.Active"; ac="$RESULT"
R1_T.ResponseFile 2; third="$RESULT"
if [[ $r -eq 0 && "$n" == 2 && "$t" == true && "$ac" == 0 && -z "$third" && ! -s "$TMP/r1.err" && ! -s "$TMP/r1.out" ]]; then
    kt_test_pass "rc 0, 2 served, the third request file untouched"
else
    kt_test_fail "rc=$r count=$n terminated=$t active=$ac third='$third' err='$(<"$TMP/r1.err")'"
fi

kt_test_start "/quit: a route calling App.Terminate — that response is still sent, then Run ends rc 0 and the NEXT request is not served"
app_replay R1 get_a.req quit.req get_a.req
R1.RegisterRoute /a GET fa
R1.RegisterRoute /quit POST fquit
r=0; R1.Run 2>"$TMP/r1.err" || r=$?
"$SRV.RequestCount"; n="$RESULT"; "$SRV.Stopping"; st="$RESULT"
R1_T.ResponseFile 1; capf "$RESULT"
R1_T.ResponseFile 2; third="$RESULT"
if [[ $r -eq 0 && "$n" == 2 && "$CAPH" == "HTTP/1.1 200 OK"* && "$CAPB" == bye && -z "$third" && "$st" == 1 && ! -s "$TMP/r1.err" ]]; then
    kt_test_pass "200 bye, stopped after 2"
else
    kt_test_fail "rc=$r count=$n body='$CAPB' third='$third' stopping=$st err='$(<"$TMP/r1.err")'"
fi

kt_test_start "a transport fatal (replay exhausted) → Terminate, Run rc 1, Server.LastError says why; DoRun returned 0, so HandleException never ran"
EXC=0
exc() { EXC=$(( EXC + 1 )); }
app_replay R1 get_a.req
R1.RegisterRoute /a GET fa
R1.OnException = exc
r=0; R1.Run 2>"$TMP/r1.err" || r=$?
"$SRV.LastError"; le="$RESULT"; "$SRV.RequestCount"; n="$RESULT"; t="$(R1.Terminated)"
if [[ $r -eq 1 && "$le" == *"no request file left"* && "$n" == 1 && "$t" == true && $EXC -eq 0 && ! -s "$TMP/r1.err" ]]; then
    kt_test_pass "rc 1, '$le', OnException 0 times"
else
    kt_test_fail "rc=$r le='$le' count=$n terminated=$t OnException=$EXC err='$(<"$TMP/r1.err")'"
fi

kt_test_start "the handler contract through the application: a function gets exactly REQ RESP DATA (\${App}_server_req/_resp, DATA verbatim), route params decoded"
app_replay R1 get_d.req
R1.RegisterRoute /d/:x GET fd 0 'da ta'
"$SRV.MaxRequests" = 1
R1.Run
R1_T.ResponseFile 0; capf "$RESULT"
if [[ "$CAPB" == "d:x y:da ta:3" ]]; then kt_test_pass "'$CAPB'"; else kt_test_fail "body='$CAPB'"; fi

kt_test_start "OnAcceptIdle fires under App.Run (P3: the event moved from Serve's loop into ServeOne): SERVER as \$1, Terminate from it ends Run rc 0, every DoRun rc 0"
IDLE=()
idle3() { IDLE+=("$1"); if (( ${#IDLE[@]} >= 3 )); then "$1.Terminate"; fi; }
if declare -F R1.delete >/dev/null; then R1.delete; fi
THttpApplication.new R1
R1.Initialize
R1.OnException = exc
EXC=0
TIdleTransport.new IT
R1.Server; SRV="$RESULT"
"$SRV.Transport" = IT
"$SRV.OnAcceptIdle" = idle3
r=0; R1.Run 2>"$TMP/r1.err" || r=$?
ticks="$(IT.Ticks)"; t="$(R1.Terminated)"
if [[ $r -eq 0 && "${IDLE[*]}" == "R1_server R1_server R1_server" && "$ticks" == 3 && "$t" == true && $EXC -eq 0 && ! -s "$TMP/r1.err" ]]; then
    kt_test_pass "3 ticks, 3 events, rc 0"
else
    kt_test_fail "rc=$r events=(${IDLE[*]}) ticks=$ticks terminated=$t OnException=$EXC err='$(<"$TMP/r1.err")'"
fi

kt_test_start "the same event through the plain server: ServeOne alone fires it once per idle rc 1, and Serve still fires it once per tick (no double firing)"
THttpServer.new SI
TIdleTransport.new IT2
SI.Transport = IT2
IDLE=()
idle2() { IDLE+=("$1"); if (( ${#IDLE[@]} >= 2 )); then "$1.Terminate"; fi; }
SI.OnAcceptIdle = idle2
r1=0; SI.ServeOne || r1=$?
n1=${#IDLE[@]}
IDLE=()
r2=0; SI.Serve 2>"$TMP/si.err" || r2=$?
n2=${#IDLE[@]}; ticks="$(IT2.Ticks)"
if [[ $r1 -eq 1 && $n1 -eq 1 && $r2 -eq 0 && $n2 -eq 2 && "$ticks" == 3 && ! -s "$TMP/si.err" ]]; then
    kt_test_pass "ServeOne: 1 event; Serve: 2 ticks, 2 events"
else
    kt_test_fail "ServeOne rc=$r1 events=$n1; Serve rc=$r2 events=$n2 ticks=$ticks"
fi
SI.delete; IT2.delete

kt_test_start "Stopping (read-only, the public view of the private stop flag): 0, 1 after Terminate, reset by BeginServe; a write is rc 1 with kklass's own line"
THttpServer.new SS
SS.Stopping; a="$RESULT"
SS.Terminate; SS.Stopping; b="$RESULT"
replay SST get_a.req
SS.Transport = SST
SS.BeginServe; SS.Stopping; c="$RESULT"; SS.EndServe
w=0; SS.Stopping = 0 2>"$TMP/ss.err" || w=$?
SS.Stopping; d="$RESULT"
if [[ "$a$b$c$d" == 0100 && $w -eq 1 && "$(<"$TMP/ss.err")" == *"read-only"* ]]; then kt_test_pass "0 → 1 → 0; write rc 1"; else kt_test_fail "values=$a$b$c$d write rc=$w err='$(<"$TMP/ss.err")'"; fi
SS.delete; SST.delete

kt_test_start "Terminate (override): Terminated true AND the server stops; 'Terminate 7' sets EXITCODE; a bad code keeps the inherited rc 1 but still stops both"
THttpApplication.new RT1
RT1.Initialize
RT1.Server; s="$RESULT"
unset -v EXITCODE
r1=0; RT1.Terminate 7 || r1=$?
t1="$(RT1.Terminated)"; "$s.Stopping"; st1="$RESULT"; ec="${EXITCODE:-}"
RT1.Initialize
RT1.Server; s="$RESULT"
r2=0; RT1.Terminate abc || r2=$?
t2="$(RT1.Terminated)"; "$s.Stopping"; st2="$RESULT"
if [[ $r1 -eq 0 && "$t1" == true && "$st1" == 1 && "$ec" == 7 && $r2 -eq 1 && "$t2" == true && "$st2" == 1 ]]; then
    kt_test_pass "both stopped, EXITCODE 7, rc 1 kept"
else
    kt_test_fail "r1=$r1 t1=$t1 st1=$st1 ec='$ec' r2=$r2 t2=$t2 st2=$st2"
fi
RT1.delete
unset -v EXITCODE

kt_test_start "fact 22 through ServerClass: the override gets exactly REQ RESP, 'inherited HandleRequest \"\$@\"' routes (the handler gets REQ RESP DATA); without the header it short-circuits to 401"
if declare -F R1.delete >/dev/null; then R1.delete; fi
THttpApplication.new R1
R1.ServerClass = TArgServer
R1.Initialize
replay R1_T get_d.req get_a.req auth.req
R1.Server; SRV="$RESULT"
"$SRV.Transport" = R1_T
"$SRV.MaxRequests" = 3
R1.RegisterRoute /d/:x GET fd 0 D22
R1.RegisterRoute /a GET fa
ARGS_SEEN=()
R1.Run
R1_T.ResponseFile 0; capf "$RESULT"; c0="$CAPH|$CAPB"
R1_T.ResponseFile 2; capf "$RESULT"; c2="$CAPH|$CAPB"
if [[ "${ARGS_SEEN[*]}" == "2:R1_server_req R1_server_resp 2:R1_server_req R1_server_resp 2:R1_server_req R1_server_resp" \
      && "$c0" == "HTTP/1.1 401 Unauthorized"*"|denied" && "$c2" == "HTTP/1.1 200 OK"*"|a" ]]; then
    kt_test_pass "2 args ×3; 401 denied; 200 through inherited"
else
    kt_test_fail "args=(${ARGS_SEEN[*]}) c0='${c0:0:40}…${c0: -10}' c2='${c2:0:40}…${c2: -10}'"
fi

kt_test_start "and with the header the route behind inherited gets REQ RESP DATA (fd sees 3 args)"
rq authd.req "GET /d/q HTTP/1.0${CRLF}Authorization: x${CRLF}${CRLF}"
replay R1_T authd.req
R1.Initialize
R1.Server; SRV="$RESULT"
"$SRV.Transport" = R1_T
"$SRV.MaxRequests" = 1
R1.Run
R1_T.ResponseFile 0; capf "$RESULT"
if [[ "$CAPB" == "d:q:D22:3" ]]; then kt_test_pass "'$CAPB'"; else kt_test_fail "body='$CAPB'"; fi

kt_test_start "fact 10 (replay half): after App.Run no request/response instance, traps identical, the fd count unchanged, Active 0"
app_replay R1 get_a.req get_a.req
R1.RegisterRoute /a GET fa
"$SRV.MaxRequests" = 2
trap ': custom int' INT; trap ': custom term' TERM; trap ': custom pipe' PIPE
tb="$(trap -p INT TERM PIPE)"
fb=(/proc/$BASHPID/fd/*)
R1.Run
fa2=(/proc/$BASHPID/fd/*)
ta="$(trap -p INT TERM PIPE)"
trap - INT TERM PIPE
left=""
for v in R1_server_req_data R1_server_resp_data R1_server_req_class R1_server_resp_class; do declare -p "$v" >/dev/null 2>&1 && left+=" $v"; done
declare -F R1_server_req.Method >/dev/null && left+=" R1_server_req.Method"
"$SRV.Active"; ac="$RESULT"
if [[ "$tb" == *"custom int"*"custom term"*"custom pipe"* && "$ta" == "$tb" && ${#fb[@]} -eq ${#fa2[@]} && -z "$left" && "$ac" == 0 ]]; then
    kt_test_pass "traps restored, ${#fb[@]} fds, nothing left"
else
    kt_test_fail "traps '$tb' → '$ta' fds ${#fb[@]} → ${#fa2[@]} left:$left active=$ac"
fi

kt_test_start "Run and DoRun before Initialize → rc 2 (DoRun also terminates), silent; one kk.debug line each under debug"
THttpApplication.new RN
r1=0; RN.Run >"$TMP/rn.out" 2>"$TMP/rn.err" || r1=$?
e1="$(<"$TMP/rn.err")$(<"$TMP/rn.out")"
r2=0; VERBOSE_KKLASS=debug RN.Run 2>"$TMP/rn.err" || r2=$?
mapfile -t EL < "$TMP/rn.err"
r3=0; RN.DoRun 2>"$TMP/rn2.err" || r3=$?
t="$(RN.Terminated)"
if [[ $r1 -eq 2 && $r2 -eq 2 && -z "$e1" && ${#EL[@]} -eq 1 && $r3 -eq 2 && "$t" == true && ! -s "$TMP/rn2.err" ]]; then
    kt_test_pass "rc 2 / rc 2, silent; debug '${EL[0]}'"
else
    kt_test_fail "run rc=$r1/$r2 off='$e1' debug=(${EL[*]}) dorun rc=$r3 terminated=$t"
fi
RN.delete

kt_test_start "a BeginServe refusal passes through Run (rc 2 for MaxRequests -1) and changes no trap; Initialize while the server is serving → rc 1"
THttpApplication.new RB
RB.Initialize
RB.Server; s="$RESULT"
"$s.MaxRequests" = -1
tb="$(trap -p INT TERM PIPE)"
r1=0; RB.Run 2>/dev/null || r1=$?
ta="$(trap -p INT TERM PIPE)"
REINIT=""
reinit() { local r=0; RB.Initialize || r=$?; REINIT="$r"; $2.Write r; }
"$s.MaxRequests" = 1
replay RBT get_a.req
"$s.Transport" = RBT
RB.RegisterRoute /a GET reinit
RB.Run
RB.Server; s2="$RESULT"; v="${s2}_class"
if [[ $r1 -eq 2 && "$tb" == "$ta" && "$REINIT" == 1 && -n "${!v:-}" ]]; then kt_test_pass "rc 2, traps untouched; re-Initialize while serving rc 1, server kept"; else kt_test_fail "run rc=$r1 traps '$tb' → '$ta' reinit=$REINIT server='$s2'"; fi
RB.delete; RBT.delete

kt_test_start "Destroy frees the server (with its stopwatch) and the router: no \${App}_* variable or function is left"
THttpApplication.new RD
RD.RegisterRoute /a GET fa
RD.Initialize
had=0; declare -F RD_server_sw.Restart >/dev/null && declare -F RD_router.RegisterRoute >/dev/null && had=1
RD.delete
left_of RD
if [[ $had -eq 1 && -z "$LEFT" ]]; then kt_test_pass "all four existed; nothing left"; else kt_test_fail "existed=$had left:$LEFT"; fi

kt_test_start "a descendant application (§2.11): override Initialize with 'inherited Initialize \"\$@\"', a destructor chaining with 'inherited' — its own object and the base's are freed"
class TMyApp006 : THttpApplication
    public
        override proc Initialize
        destructor Destroy
    private
        var _extra
end
TMyApp006.Initialize() {
    local __m_rc=0
    ServerClass=TArgServer
    inherited Initialize "$@" || return
    _extra="${__inst__}_dict"
    THttpRouter.new "$_extra"
    return "$__m_rc"
}
TMyApp006.Destroy() {
    "$_extra.delete"
    inherited
}
build TMyApp006
TMyApp006.new MY -p 9099
r=0; MY.Initialize || r=$?
MY.Port; p="$RESULT"; MY.Server; s="$RESULT"; v="${s}_class"; cls="${!v:-}"
had=0; declare -F MY_dict.RegisterRoute >/dev/null && had=1
MY.delete
left_of MY
declare -F MY_dict.RegisterRoute >/dev/null && LEFT+=" MY_dict"
if [[ $r -eq 0 && "$p" == 9099 && "$cls" == TArgServer && $had -eq 1 && -z "$LEFT" ]]; then kt_test_pass "9099 TArgServer; everything freed"; else kt_test_fail "rc=$r port=$p class=$cls extra=$had left:$LEFT"; fi

kt_test_start "TERM on the app path (child bash): a handler signals its own shell — that response is sent, Run rc 0, 1 of 3 served; during the handler PIPE is ignored and TERM is the server's; custom traps restored exactly"
out="$(UNIT="$UNIT" TMP="$TMP" timeout 180 "$BASH" -c '
source "$UNIT"
DURING=""
sig() { DURING="$(trap -p PIPE)|$(trap -p TERM)"; $2.Write sig; kill -TERM "$BASHPID"; }
THttpApplication.new A
A.RegisterRoute /a GET sig
A.Initialize
TReplayTransport.new T
for i in 1 2 3; do T.AddRequestFile "$TMP/get_a.req"; done
A.Server; s="$RESULT"
"$s.Transport" = T
trap ": custom int" INT; trap ": custom term" TERM; trap ": custom pipe" PIPE
tb="$(trap -p INT TERM PIPE)"
rc=0; A.Run || rc=$?
ta="$(trap -p INT TERM PIPE)"
"$s.RequestCount"; n="$RESULT"
T.ResponseFile 0; b="$(<"$RESULT")"
same=0; [[ "$tb" == "$ta" && "$tb" == *custom* ]] && same=1
printf "rc=%s n=%s body=%s same=%s during=%s" "$rc" "$n" "${b##*$'"'"'\n'"'"'}" "$same" "${DURING//$'"'"'\n'"'"'/ }"
' 2>"$TMP/term.err" </dev/null)"; crc=$?
if [[ $crc -eq 0 && "$out" == "rc=0 n=1 body=sig same=1 during=trap -- '' SIGPIPE|trap -- '__THS_SIGNAL=TERM' SIGTERM" && ! -s "$TMP/term.err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "child rc=$crc out='$out' err='$(<"$TMP/term.err")'"
fi

kt_test_start "SIGPIPE on the app path (child bash): responses written to a pipe whose reader is gone — Run goes on (2 served, rc 0), the shell lives, nothing on stderr"
out="$(UNIT="$UNIT" TMP="$TMP" timeout 180 "$BASH" -c '
source "$UNIT"
class TDeadPipeTransport : TReplayTransport
    public
        override func Accept
end
TDeadPipeTransport.Accept() {
    local __d_r=0 __d_fd __d_cap __d_pid
    inherited Accept "$@" || __d_r=$?
    if (( __d_r != 0 )); then kk._return ""; return "$__d_r"; fi
    __d_cap="$_outFd"
    exec {__d_fd}> >(exec true)
    __d_pid=$!
    wait "$__d_pid"
    exec {__d_cap}>&-
    _outFd="$__d_fd"
    kk._return ""
    return 0
}
build TDeadPipeTransport
fa() { $2.Write "to nobody"; }
lg() { LOG+="$2|"; }
LOG=""
THttpApplication.new A
A.RegisterRoute /a GET fa
A.Initialize
TDeadPipeTransport.new T
T.AddRequestFile "$TMP/get_a.req"; T.AddRequestFile "$TMP/get_a.req"
A.Server; s="$RESULT"
"$s.Transport" = T
"$s.OnLog" = lg
"$s.MaxRequests" = 2
rc=0; A.Run || rc=$?
"$s.RequestCount"
printf "alive rc=%s n=%s log=%s" "$rc" "$RESULT" "$LOG"
' 2>"$TMP/pipe.err" </dev/null)"; crc=$?
if [[ $crc -eq 0 && "$out" =~ ^alive\ rc=0\ n=2\ log=-\ GET\ /a\ 200\ 9\ [0-9]+\|-\ GET\ /a\ 200\ 9\ [0-9]+\|$ && ! -s "$TMP/pipe.err" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "child rc=$crc out='$out' err='$(<"$TMP/pipe.err")'"
fi

kt_test_start "DoRun is fork-free (§2.1): BASHPID unchanged, works under PATH='', a DEBUG canary sees no subshell (control: it does), the stored bodies hold no \$( , backtick or pipe"
app_replay RF get_a.req get_a.req get_a.req
RF.RegisterRoute /a GET fa
"$SRV.BeginServe"
p0=$BASHPID
dorun_np() { local PATH=''; RF.DoRun; }
r1=0; RF.DoRun || r1=$?
r2=0; dorun_np 2>"$TMP/np.err" || r2=$?
CANARY="$TMP/fork.canary"; rm -f "$CANARY"
set -T
trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
r3=0; RF.DoRun || r3=$?
trap - DEBUG
set +T
seen=0; [[ -e "$CANARY" ]] && seen=1; rm -f "$CANARY"
set -T; trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
ctl="$(printf x)"
trap - DEBUG; set +T
ctlseen=0; [[ -e "$CANARY" ]] && ctlseen=1; rm -f "$CANARY"
"$SRV.EndServe"
"$SRV.RequestCount"; n="$RESULT"
bad=""
for m in DoRun Terminate RegisterRoute; do
    v="THttpApplication_method_body_${m}"
    if [[ -z "${!v+x}" ]]; then bad+=" missing:$m"; continue; fi
    b="${!v}"; b="${b//'$(('/}"; b="${b//'||'/}"
    [[ "$b" == *'$('* || "$b" == *'`'* || "$b" == *'|'* ]] && bad+=" $m"
done
if [[ $r1$r2$r3 == 000 && $BASHPID == "$p0" && "$n" == 3 && ! -s "$TMP/np.err" && $seen -eq 0 && $ctlseen -eq 1 && -z "$bad" ]]; then
    kt_test_pass "3 DoRuns, no fork, bodies clean"
else
    kt_test_fail "rcs=$r1$r2$r3 count=$n nopath-err='$(<"$TMP/np.err")' canary=$seen control=$ctlseen bodies:$bad"
fi
RF.delete; RF_T.delete
if declare -F R1.delete >/dev/null; then R1.delete; fi
for v in R1_T IT; do if declare -F "$v.delete" >/dev/null; then "$v.delete"; fi; done

# ===========================================================================
kt_test_section "2. real sockets: the application as a child script (facts 10, 18, 22)"
# ===========================================================================

# The common head of every application child: the unit, the idle budget
# (OnAcceptIdle counts ticks since the last request; the `done` marker or
# IDLE_BUDGET ticks → Server.Terminate → DoRun sees Stopping → App.Terminate),
# the access log, and the in-child probe `chk TAG SERVER` (traps, fds,
# children, temp dirs, request/response instances → the result file).
APP_HEAD='exec </dev/null
cd "$SRV_DIR" || exit 90
source "$UNIT_DIR/thttpapplication.sh" || exit 91
printf "%s" "$BASHPID" > "$SRV_DIR/pid"
__t_ticks=0
__t_last=0
__t_idle() {
    local __t_n
    "$1.RequestCount"; __t_n="$RESULT"
    if [[ "$__t_n" != "$__t_last" ]]; then __t_last="$__t_n"; __t_ticks=0; fi
    __t_ticks=$(( __t_ticks + 1 ))
    printf "%s\n" "$__t_ticks" > "$SRV_DIR/ticks"
    if [[ -e "$SRV_DIR/done" ]] || (( __t_ticks >= ${IDLE_BUDGET:-40} )); then "$1.Terminate"; fi
    return 0
}
__t_log() { printf "%s\n" "$2" >> "$SRV_DIR/access.log"; }
chk() {
    local t p pp n=0 d dirs="" v left=""
    t="$(trap -p INT TERM PIPE)"
    local -a f=(/proc/$BASHPID/fd/*)
    for p in /proc/[0-9]*; do
        pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue
        if [[ "$pp" == "$BASHPID" ]]; then n=$(( n + 1 )); fi
    done
    for d in "$TMPDIR"/thttpserver.*; do if [[ -e "$d" ]]; then dirs+=" $d"; fi; done
    for v in "$2_req_data" "$2_resp_data" "$2_tr_data" "$2_req_hdr" "$2_resp_hdr"; do
        if declare -p "$v" >/dev/null 2>&1; then left+=" $v"; fi
    done
    printf "%s_traps=%s\n%s_fds=%s\n%s_children=%s\n%s_dirs=[%s]\n%s_left=[%s]\n" \
        "$1" "${t//$'"'"'\n'"'"'/|}" "$1" "${#f[@]}" "$1" "$n" "$1" "$dirs" "$1" "$left" >> "$SRV_DIR/result"
}
'
# app_script FILE BODY — APP_HEAD + BODY into FILE (outside the child's dir).
app_script() { printf '%s\n%s\n' "$APP_HEAD" "$2" > "$1"; }
# res_load — the child's result file into the assoc R.
res_load() {
    local l
    R=()
    [[ -f "$THS_DIR/result" ]] || return 0
    while IFS= read -r l; do [[ "$l" == *=* ]] && R["${l%%=*}"]="${l#*=}"; done < "$THS_DIR/result"
}
declare -A R=()

# ---------------------------------------------------------------------------
S1_TITLES=(
    "fact 18: 'THttpApplication.new App --port=N' (argv on the child's command line) serves on N; the routes were registered BEFORE Initialize"
    "the handlers run in the application's shell (\$BASHPID = the child's), state persists; 404 for an unknown path"
    "a client that sends a request and closes at once does not stop the next request (SIGPIPE ignored on the app path, best effort)"
    "POST /quit → 200 bye, then App.Run returns 0 and the child exits 0 by itself (no idle budget used)"
    "fact 10 (app path): after Run no child process, no temp dir, no request/response/transport instance, traps identical, fd count unchanged"
    "the port is free afterwards; App.delete leaves no App_* variable or function; the child's stderr is empty"
)
S1_BODY='
s1_hello() { local n; $1.RouteParam name; n="$RESULT"; $2.Write "hello $n"; }
S1_N=0
s1_count() { S1_N=$(( S1_N + 1 )); $2.Write "$S1_N:$BASHPID"; }
s1_big()   { local b; printf -v b "%*s" 20000 ""; $2.Content = "${b// /y}"; }
s1_quit()  { App.Terminate; $2.Write bye; }
THttpApplication.new App "$@"
App.RegisterRoute /hello/:name GET  s1_hello
App.RegisterRoute /count       GET  s1_count
App.RegisterRoute /big         GET  s1_big
App.RegisterRoute /quit        POST s1_quit
App.Initialize || { printf "init=%s\n" "$?" >> "$SRV_DIR/result"; exit 3; }
App.Server; srv="$RESULT"
"$srv.AcceptIdleTimeout" = 1000
"$srv.OnAcceptIdle" = __t_idle
"$srv.OnLog" = __t_log
trap ": custom int" INT
trap ": custom term" TERM
trap ": custom pipe" PIPE
chk before "$srv"
rc=0; App.Run || rc=$?
App.Port; p="$RESULT"; "$srv.RequestCount"; n="$RESULT"; "$srv.LastError"; le="$RESULT"
printf "rc=%s\nport=%s\nn=%s\nle=%s\nticks=%s\n" "$rc" "$p" "$n" "$le" "$__t_ticks" >> "$SRV_DIR/result"
chk after "$srv"
App.delete
left=""
for v in App_data App_class App_router_data App_server_data App_server_sw_data App_server_req_data App_server_resp_data; do
    if declare -p "$v" >/dev/null 2>&1; then left+=" $v"; fi
done
for fn in App.Run App_router.RegisterRoute App_server.ServeOne App_server_sw.Restart; do
    if declare -F "$fn" >/dev/null; then left+=" $fn"; fi
done
printf "deleted_left=[%s]\n" "$left" >> "$SRV_DIR/result"
: > "$SRV_DIR/ended"
'
app_script "$TMP/s1.sh" "$S1_BODY"
if ! ths_have_nc; then
    ths_skip "${S1_TITLES[@]}"
elif ! ths_launch s1 "$TMP/s1.sh" "--port={PORT}"; then
    for t in "${S1_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "s1 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null) $(tr '\n' ' ' < "$THS_DIR/result" 2>/dev/null)"; done
else
    SPID="$(<"$THS_DIR/pid")"
    ths_curl "$TMP/s1a" "http://127.0.0.1:$THS_PORT/hello/world"; ca="$CURL_CODE:$(<"$TMP/s1a")"
    ths_curl "$TMP/s1b" "http://127.0.0.1:$THS_PORT/count"; cb="$CURL_CODE:$(<"$TMP/s1b")"
    ths_curl "$TMP/s1c" "http://127.0.0.1:$THS_PORT/count"; cc="$CURL_CODE:$(<"$TMP/s1c")"
    ths_curl "$TMP/s1d" "http://127.0.0.1:$THS_PORT/nope"; cd4="$CURL_CODE"
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" && printf 'GET /big HTTP/1.0\r\n\r\n' >&3 && exec 3>&- ) 2>/dev/null
    ths_curl "$TMP/s1e" "http://127.0.0.1:$THS_PORT/count"; ce="$CURL_CODE:$(<"$TMP/s1e")"
    ths_curl "$TMP/s1q" -X POST --data-binary x "http://127.0.0.1:$THS_PORT/quit"; cq="$CURL_CODE:$(<"$TMP/s1q")"
    ths_reap 60
    res_load

    kt_test_start "${S1_TITLES[0]}"
    if [[ "$ca" == "200:hello world" && "${R[port]:-}" == "$THS_PORT" ]]; then kt_test_pass "port $THS_PORT: '$ca'"; else kt_test_fail "'$ca' App.Port='${R[port]:-}' want $THS_PORT"; fi

    kt_test_start "${S1_TITLES[1]}"
    if [[ "$cb" == "200:1:$SPID" && "$cc" == "200:2:$SPID" && "$cd4" == 404 ]]; then kt_test_pass "1 then 2 in pid $SPID; 404"; else kt_test_fail "'$cb' '$cc' 404='$cd4' pid=$SPID"; fi

    kt_test_start "${S1_TITLES[2]}"
    if [[ "$ce" == "200:3:$SPID" ]]; then kt_test_pass "next request 200 (count 3)"; else kt_test_fail "'$ce'"; fi

    kt_test_start "${S1_TITLES[3]}"
    if [[ "$cq" == "200:bye" && $THS_TERMED -eq 0 && $THS_RC -eq 0 && "${R[rc]:-}" == 0 && -z "${R[le]-x}" && "${R[ticks]:-}" =~ ^[0-9]+$ && -e "$THS_DIR/ended" ]] && (( ${R[ticks]} < 40 )); then
        kt_test_pass "bye; rc 0, exit 0, ${R[n]:-?} served"
    else
        kt_test_fail "quit='$cq' termed=$THS_TERMED exit=$THS_RC rc='${R[rc]:-}' le='${R[le]-none}' ticks=${R[ticks]:-?}"
    fi

    kt_test_start "${S1_TITLES[4]}"
    tb="${R[before_traps]:-}"
    if [[ "$tb" == *"custom int"*"custom term"*"custom pipe"* && "${R[after_traps]:-}" == "$tb" && -n "${R[before_fds]:-}" && "${R[after_fds]:-}" == "${R[before_fds]}" \
          && "${R[after_children]:-x}" == 0 && "${R[after_dirs]:-x}" == "[]" && "${R[after_left]:-x}" == "[]" ]]; then
        kt_test_pass "clean; ${R[before_fds]} fds; traps '$tb'"
    else
        kt_test_fail "traps '$tb' → '${R[after_traps]:-}' fds ${R[before_fds]:-?} → ${R[after_fds]:-?} children=${R[after_children]:-?} dirs=${R[after_dirs]:-?} left=${R[after_left]:-?}"
    fi

    kt_test_start "${S1_TITLES[5]}"
    "$THS_NC" -l -n -vv -w 1 -s 127.0.0.1 -p "$THS_PORT" >/dev/null 2>"$TMP/s1probe.err" </dev/null
    e="$(<"$THS_DIR/err")"
    if grep -q '^Listening on' "$TMP/s1probe.err" && [[ "${R[deleted_left]:-x}" == "[]" && -z "$e" ]]; then kt_test_pass "bound; nothing left; silent"; else kt_test_fail "probe: $(tr '\n' ' ' < "$TMP/s1probe.err") left=${R[deleted_left]:-?} stderr='${e:0:300}'"; fi
fi

# ---------------------------------------------------------------------------
S2_TITLES=(
    "fact 18: '-p N' with ServerClass = TAuthServer (token from the environment): no token → 401, a wrong token → 401, the right one → 200"
    "fact 22 over the wire: the override received exactly REQ RESP each time; 'inherited HandleRequest \"\$@\"' reached the route"
    "POST /quit without the token → 401 and the server goes on; with it → 200, Run rc 0, exit 0, stderr empty"
)
S2_BODY='
class TAuthServer : THttpServer
    public
        var Token
        override proc HandleRequest
end
TAuthServer.HandleRequest() {
    local __a_rc=0
    printf "%s:%s\n" "$#" "$*" >> "$SRV_DIR/args.log"
    if ! $1.GetHeader authorization || [[ "$RESULT" != "Bearer $Token" ]]; then
        $2.Code = 401
        $2.SetCustomHeader WWW-Authenticate Bearer
        return 0
    fi
    inherited HandleRequest "$@" || __a_rc=$?
    return "$__a_rc"
}
build TAuthServer
s2_hello() { local n; $1.RouteParam name; n="$RESULT"; $2.Write "hi $n"; }
s2_quit()  { App.Terminate; $2.Write bye; }
THttpApplication.new App "$@"
App.ServerClass = TAuthServer
App.RegisterRoute /hello/:name GET s2_hello
App.RegisterRoute /quit POST s2_quit
App.Initialize || { printf "init=%s\n" "$?" >> "$SRV_DIR/result"; exit 3; }
App.Server; srv="$RESULT"
"$srv.Token" = "$S2_TOKEN"
"$srv.AcceptIdleTimeout" = 1000
"$srv.OnAcceptIdle" = __t_idle
rc=0; App.Run || rc=$?
printf "rc=%s\n" "$rc" >> "$SRV_DIR/result"
App.delete
: > "$SRV_DIR/ended"
'
app_script "$TMP/s2.sh" "$S2_BODY"
if ! ths_have_nc; then
    ths_skip "${S2_TITLES[@]}"
elif ! S2_TOKEN=s3cr3t ths_launch s2 "$TMP/s2.sh" -p "{PORT}"; then
    for t in "${S2_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "s2 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null) $(tr '\n' ' ' < "$THS_DIR/result" 2>/dev/null)"; done
else
    ths_curl "$TMP/s2a" -i "http://127.0.0.1:$THS_PORT/hello/x"; ths_split "$TMP/s2a"; a="$CURL_CODE"; ah="$THS_HEAD"
    ths_curl "$TMP/s2b" -H 'Authorization: Bearer nope' "http://127.0.0.1:$THS_PORT/hello/x"; b="$CURL_CODE"
    ths_curl "$TMP/s2c" -H 'Authorization: Bearer s3cr3t' "http://127.0.0.1:$THS_PORT/hello/x"; c="$CURL_CODE:$(<"$TMP/s2c")"
    ths_curl "$TMP/s2d" -X POST --data-binary x "http://127.0.0.1:$THS_PORT/quit"; d="$CURL_CODE"
    ths_curl "$TMP/s2e" -H 'Authorization: Bearer s3cr3t' "http://127.0.0.1:$THS_PORT/hello/y"; e2="$CURL_CODE:$(<"$TMP/s2e")"
    ths_curl "$TMP/s2f" -X POST --data-binary x -H 'Authorization: Bearer s3cr3t' "http://127.0.0.1:$THS_PORT/quit"; f="$CURL_CODE:$(<"$TMP/s2f")"
    ths_reap 60
    res_load

    kt_test_start "${S2_TITLES[0]}"
    if [[ "$a" == 401 && "$ah" == *$'\nWWW-Authenticate: Bearer'* && "$b" == 401 && "$c" == "200:hi x" ]]; then kt_test_pass "401 401 200"; else kt_test_fail "a=$a b=$b c='$c' head='${ah:0:120}'"; fi

    kt_test_start "${S2_TITLES[1]}"
    mapfile -t AG < "$THS_DIR/args.log" 2>/dev/null
    bad=""; for l in "${AG[@]}"; do [[ "$l" == "2:App_server_req App_server_resp" ]] || bad+=" '$l'"; done
    if [[ ${#AG[@]} -eq 6 && -z "$bad" && "$e2" == "200:hi y" ]]; then kt_test_pass "6 × '2:App_server_req App_server_resp'"; else kt_test_fail "n=${#AG[@]} bad:$bad e2='$e2'"; fi

    kt_test_start "${S2_TITLES[2]}"
    e="$(<"$THS_DIR/err")"
    if [[ "$d" == 401 && "$f" == "200:bye" && $THS_TERMED -eq 0 && $THS_RC -eq 0 && "${R[rc]:-}" == 0 && -z "$e" ]]; then kt_test_pass "401, then 200 bye; rc 0"; else kt_test_fail "noauth=$d auth='$f' termed=$THS_TERMED exit=$THS_RC rc='${R[rc]:-}' stderr='${e:0:300}'"; fi
fi

# ---------------------------------------------------------------------------
S3_TITLES=(
    "TERM while a request is handled (app path): that response is still sent (200), then Run returns 0 and the child exits 0 — no idle budget, AcceptIdleTimeout 0"
    "after the TERM: no child process, no temp dir, traps identical to before Run, stderr empty"
)
S3_BODY='
s3_hold() {
    local i
    : > "$SRV_DIR/holding"
    for (( i = 0; i < 1200; i++ )); do
        if [[ -n "$__THS_SIGNAL" ]]; then $2.Write held-done; return 0; fi
        sleep 0.05
    done
    $2.Write no-signal
}
THttpApplication.new App "$@"
App.RegisterRoute /hold GET s3_hold
App.Initialize || exit 3
App.Server; srv="$RESULT"
trap ": custom term" TERM
chk before "$srv"
rc=0; App.Run || rc=$?
"$srv.RequestCount"; n="$RESULT"
printf "rc=%s\nn=%s\n" "$rc" "$n" >> "$SRV_DIR/result"
chk after "$srv"
App.delete
: > "$SRV_DIR/ended"
'
app_script "$TMP/s3.sh" "$S3_BODY"
if ! ths_have_nc; then
    ths_skip "${S3_TITLES[@]}"
elif ! ths_launch s3 "$TMP/s3.sh" "--port={PORT}"; then
    for t in "${S3_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "s3 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    ths_raw "$TMP/s3.out" "GET /hold HTTP/1.0${CRLF}${CRLF}" &
    C1=$!
    hold=0; ths_poll 60 test -e "$THS_DIR/holding" && hold=1
    kill -TERM "$(<"$THS_DIR/pid")" 2>/dev/null
    wait "$C1"
    ths_reap 60
    res_load

    kt_test_start "${S3_TITLES[0]}"
    ths_split "$TMP/s3.out"
    if [[ $hold -eq 1 && "${THS_HEAD%%$'\n'*}" == "HTTP/1.1 200 OK" && "$THS_BODY" == held-done && $THS_TERMED -eq 0 && $THS_RC -eq 0 && "${R[rc]:-}" == 0 && "${R[n]:-}" == 1 ]]; then
        kt_test_pass "200 held-done; rc 0, exit 0"
    else
        kt_test_fail "holding=$hold head='${THS_HEAD:0:40}' body='$THS_BODY' termed=$THS_TERMED exit=$THS_RC rc='${R[rc]:-}' n='${R[n]:-}'"
    fi

    kt_test_start "${S3_TITLES[1]}"
    e="$(<"$THS_DIR/err")"
    if [[ "${R[after_children]:-x}" == 0 && "${R[after_dirs]:-x}" == "[]" && -n "${R[before_traps]:-}" && "${R[after_traps]:-}" == "${R[before_traps]}" && -z "$e" ]]; then
        kt_test_pass "clean; traps '${R[after_traps]}'"
    else
        kt_test_fail "children=${R[after_children]:-?} dirs=${R[after_dirs]:-?} traps '${R[before_traps]:-}' → '${R[after_traps]:-}' stderr='${e:0:300}'"
    fi
fi

# ---------------------------------------------------------------------------
S4_TITLE="TERM while idle in App.Run with AcceptIdleTimeout 0 (no tick, no OnAcceptIdle): DoRun maps the signal (ServeOne rc 1 + Stopping) to Terminate — Run rc 0, exit 0, nothing served, no child, no dir, stderr empty"
S4_BODY='
THttpApplication.new App "$@"
App.Initialize || exit 3
App.Server; srv="$RESULT"
rc=0; App.Run || rc=$?
"$srv.RequestCount"; n="$RESULT"; t="$(App.Terminated)"
printf "rc=%s\nn=%s\nterminated=%s\n" "$rc" "$n" "$t" >> "$SRV_DIR/result"
chk after "$srv"
App.delete
'
app_script "$TMP/s4.sh" "$S4_BODY"
if ! ths_have_nc; then
    ths_skip "$S4_TITLE"
elif ! ths_launch s4 "$TMP/s4.sh" "--port={PORT}"; then
    kt_test_start "$S4_TITLE"; kt_test_fail "s4 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"
else
    kill -TERM "$(<"$THS_DIR/pid")" 2>/dev/null
    ths_reap 60
    res_load
    e="$(<"$THS_DIR/err")"
    kt_test_start "$S4_TITLE"
    if [[ $THS_TERMED -eq 0 && $THS_RC -eq 0 && "${R[rc]:-}" == 0 && "${R[n]:-}" == 0 && "${R[terminated]:-}" == true \
          && "${R[after_children]:-x}" == 0 && "${R[after_dirs]:-x}" == "[]" && -z "$e" ]]; then
        kt_test_pass "rc 0, exit 0, clean"
    else
        kt_test_fail "termed=$THS_TERMED exit=$THS_RC (124 = the guard) rc='${R[rc]:-}' n='${R[n]:-}' terminated='${R[terminated]:-}' children=${R[after_children]:-?} dirs=${R[after_dirs]:-?} stderr='${e:0:200}'"
    fi
fi
