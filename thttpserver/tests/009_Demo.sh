#!/bin/bash
# 009_Demo.sh — thttpserver P3: a smoke test of both examples (PLAN §2.10,
# §2.11) run exactly as a user runs them — `bash examples/demo.sh --port=N`
# in a child bash, the test is the client.
#
#   §0 no socket: a bad --port → exit 2 with the usage line, nothing started;
#      an unusable nc → the URL line, then exit 1 with the server's LastError.
#   §1 examples/demo.sh (functions + App.RegisterRoute): every route kind — a
#      function, an INST.METHOD (Hits.Next), a route class (THelloRoute with
#      route DATA), the TDictionary store with GET / PUT / DELETE — plus HEAD,
#      404, 405, and POST /quit ending the demo by itself. Where the bash under
#      test has no nc of its own the child is started WITHOUT KCL_NC, so the
#      demo's own netcat resolution is exercised (bash 5.2.37 here).
#   §2 examples/demo_oop.sh (the §2.11 descendants): TAuthServer via
#      ServerClass with --token=T — 401 without / with a wrong token, the
#      public index, the controller's methods, the app's own methods, /quit
#      refused without the token and accepted with it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO="$UNIT_DIR/examples/demo.sh"
DEMO_OOP="$UNIT_DIR/examples/demo_oop.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
export THS_LIB="$SCRIPT_DIR/_ths_socket.sh"
source "$THS_LIB"
CRLF=$'\r\n'
cd "$TMP" || exit 1

kt_test_section "009: the examples, smoke-tested (P3)"

# ===========================================================================
kt_test_section "0. no socket: a refused command line"
# ===========================================================================

for d in "$DEMO" "$DEMO_OOP"; do
    kt_test_start "$(basename "$d") --port=70000 → exit 2, one usage line on stderr, nothing on stdout, no temp dir"
    mkdir -p "$TMP/bad"
    rc=0; TMPDIR="$TMP/bad" timeout 180 "$BASH" "$d" --port=70000 >"$TMP/bad.out" 2>"$TMP/bad.err" </dev/null || rc=$?
    mapfile -t EL < "$TMP/bad.err"
    left="$(ls -A "$TMP/bad")"
    if [[ $rc -eq 2 && ${#EL[@]} -eq 1 && "${EL[0]}" == "usage: "*"--port=N"* && ! -s "$TMP/bad.out" && -z "$left" ]]; then
        kt_test_pass "exit 2: '${EL[0]}'"
    else
        kt_test_fail "exit=$rc stderr=(${EL[*]}) stdout='$(<"$TMP/bad.out")' tmp='$left'"
    fi

    kt_test_start "$(basename "$d") --port=N with KCL_NC=/no/such/nc → the URL line, then exit 1 at once with 'the server stopped: nc not found …' (a transport fatal, not a usage error), no temp dir"
    rc=0; KCL_NC=/no/such/nc TMPDIR="$TMP/bad" timeout 180 "$BASH" "$d" --port=28999 >"$TMP/bad.out" 2>"$TMP/bad.err" </dev/null || rc=$?
    mapfile -t EL < "$TMP/bad.err"
    mapfile -t OL < "$TMP/bad.out"
    left="$(ls -A "$TMP/bad")"
    if [[ $rc -eq 1 && ${#EL[@]} -eq 1 && "${EL[0]}" == "kcl demo: the server stopped: nc not found"* && "${OL[0]:-}" == *"http://127.0.0.1:28999/"* && -z "$left" ]]; then
        kt_test_pass "exit 1: '${EL[0]:0:60}…'"
    else
        kt_test_fail "exit=$rc stderr=(${EL[*]}) stdout=(${OL[*]}) tmp='$left'"
    fi
done

# own_nc — 1 when the child can find nc WITHOUT KCL_NC (on its PATH, or the
# msys64 fallback path the demos know).
own_nc() { [[ "$THS_NC" == /c/bin/msys64/usr/bin/nc.exe ]] || type -P nc >/dev/null; }
URL_RE='^kcl demo[^:]*: http://127\.0\.0\.1:([0-9]+)/ '

# ===========================================================================
kt_test_section "1. examples/demo.sh"
# ===========================================================================

D1_TITLES=(
    "the demo resolves nc itself and prints its URL on start (http://127.0.0.1:N/)"
    "GET / (a function): 200 with the route list"
    "GET /count twice (Hits.Next, an INST.METHOD handler): 1, then 2 — the counter lives in the server shell"
    "the TDictionary store: PUT (multibyte, from a file) 201 → GET the exact bytes → PUT again 200 → DELETE 200 → GET 404 → DELETE 404"
    "GET /hello/world (a route class with route DATA): 'Hello, world!'; HEAD → the GET head, no body"
    "POST /count → 405 + Allow: GET, HEAD; an unknown path → 404"
    "POST /quit → 200 bye; the demo exits 0 by itself, prints its summary, one access-log line per request, stderr empty, temp dir gone"
)
if ! ths_have_nc; then
    ths_skip "${D1_TITLES[@]}"
else
    own=0; if own_nc; then own=1; fi
    if ! THS_OWN_NC=$own ths_launch d1 "$DEMO" "--port={PORT}"; then
        for t in "${D1_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "demo.sh never listened (own nc=$own): $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
    else
        U="http://127.0.0.1:$THS_PORT"
        ths_curl "$TMP/d1a" "$U/"; ca="$CURL_CODE"; ba="$(<"$TMP/d1a")"
        ths_curl "$TMP/d1b" "$U/count"; cb="$CURL_CODE:$(<"$TMP/d1b")"
        ths_curl "$TMP/d1c" "$U/count"; cc="$CURL_CODE:$(<"$TMP/d1c")"
        printf '%s' 'значение 1' > "$TMP/kv.body"
        kv=""
        ths_curl "$TMP/k1" -X PUT --data-binary "@$TMP/kv.body" "$U/kv/greeting"; kv+="$CURL_CODE "
        ths_curl "$TMP/k2" "$U/kv/greeting"; kv+="$CURL_CODE "; k2="$(<"$TMP/k2")"
        ths_curl "$TMP/k3" -X PUT --data-binary x "$U/kv/greeting"; kv+="$CURL_CODE "
        ths_curl "$TMP/k4" -X DELETE "$U/kv/greeting"; kv+="$CURL_CODE "
        ths_curl "$TMP/k5" "$U/kv/greeting"; kv+="$CURL_CODE "
        ths_curl "$TMP/k6" -X DELETE "$U/kv/greeting"; kv+="$CURL_CODE"
        ths_curl "$TMP/h1" "$U/hello/world"; ch="$CURL_CODE:$(<"$TMP/h1")"
        ths_raw "$TMP/h2" "HEAD /hello/x HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/h2"
        hh="$RAW_RC:${THS_HEAD%%$'\n'*}"; hhead="$THS_HEAD"; hbody="$THS_BODY"
        ths_curl "$TMP/p1" -i -X POST --data-binary x "$U/count"; ths_split "$TMP/p1"; c405="$CURL_CODE"; h405="$THS_HEAD"
        ths_curl "$TMP/p2" "$U/nope"; c404="$CURL_CODE"
        ths_curl "$TMP/q" -X POST --data-binary x "$U/quit"; cq="$CURL_CODE:$(<"$TMP/q")"
        ths_reap 60
        mapfile -t OUT < "$THS_DIR/out"

        kt_test_start "${D1_TITLES[0]}"
        if [[ "${OUT[0]:-}" =~ $URL_RE && "${BASH_REMATCH[1]}" == "$THS_PORT" ]]; then kt_test_pass "'${OUT[0]}' (own nc=$own)"; else kt_test_fail "first line '${OUT[0]:-}' port $THS_PORT"; fi

        kt_test_start "${D1_TITLES[1]}"
        if [[ "$ca" == 200 && "$ba" == *"GET    /count"* && "$ba" == *"PUT    /kv/KEY"* && "$ba" == *"POST   /quit"* ]]; then kt_test_pass "200, list"; else kt_test_fail "code=$ca body='${ba:0:120}'"; fi

        kt_test_start "${D1_TITLES[2]}"
        if [[ "$cb $cc" == "200:1 200:2" ]]; then kt_test_pass "1 2"; else kt_test_fail "'$cb' '$cc'"; fi

        kt_test_start "${D1_TITLES[3]}"
        if [[ "$kv" == "201 200 200 200 404 404" && "$k2" == 'значение 1' ]]; then kt_test_pass "$kv; bytes intact"; else kt_test_fail "codes '$kv' get='$k2'"; fi

        kt_test_start "${D1_TITLES[4]}"
        if [[ "$ch" == "200:Hello, world!" && "$hh" == "0:HTTP/1.1 200 OK" && "$hhead" == *$'\nContent-Length: 9'* && -z "$hbody" ]]; then kt_test_pass "Hello, world!; HEAD: Content-Length 9, no body"; else kt_test_fail "get='$ch' head=$hh '${hhead:0:200}' body='$hbody'"; fi

        kt_test_start "${D1_TITLES[5]}"
        if [[ "$c405" == 405 && "$h405" == *$'\nAllow: GET, HEAD'* && "$c404" == 404 ]]; then kt_test_pass "405 Allow: GET, HEAD; 404"; else kt_test_fail "405=$c405 '${h405:0:160}' 404=$c404"; fi

        kt_test_start "${D1_TITLES[6]}"
        nlog=0; for l in "${OUT[@]}"; do [[ "$l" =~ ^127\.0\.0\.1:[0-9]+\ [A-Z]+\ /[^\ ]*\ [0-9]{3}\ [0-9]+\ [0-9]+$ ]] && nlog=$(( nlog + 1 )); done
        e="$(<"$THS_DIR/err")"; left="$(ls -A "$THS_DIR/tmp")"
        if [[ "$cq" == "200:bye" && $THS_TERMED -eq 0 && $THS_RC -eq 0 && $nlog -eq 14 && "${OUT[-1]:-}" == "kcl demo: stopped after 2 /count hit(s)" && -z "$e" && -z "$left" ]]; then
            kt_test_pass "exit 0, 14 log lines, '${OUT[-1]}'"
        else
            kt_test_fail "quit='$cq' termed=$THS_TERMED exit=$THS_RC log=$nlog last='${OUT[-1]:-}' stderr='${e:0:200}' tmp='$left'"
        fi
    fi
fi

# ===========================================================================
kt_test_section "2. examples/demo_oop.sh"
# ===========================================================================

D2_TITLES=(
    "demo_oop.sh -p N --token=T prints its URL; GET / is public (200); without a token or with a wrong one → 401 + WWW-Authenticate"
    "with the token: the app's own method (/count 1, 2), the controller's methods (PUT 201 / GET / DELETE / GET 404), the route class (/hello)"
    "POST /quit without the token → 401 and the demo goes on; with it → 200 bye, exit 0, stderr empty, temp dir gone"
)
if ! ths_have_nc; then
    ths_skip "${D2_TITLES[@]}"
elif ! ths_launch d2 "$DEMO_OOP" -p "{PORT}" "--token=tk9"; then
    for t in "${D2_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "demo_oop.sh never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    U="http://127.0.0.1:$THS_PORT"
    AUTH='Authorization: Bearer tk9'
    ths_curl "$TMP/o1" "$U/"; o1="$CURL_CODE"; b1="$(<"$TMP/o1")"
    ths_curl "$TMP/o2" -i "$U/count"; ths_split "$TMP/o2"; o2="$CURL_CODE"; h2="$THS_HEAD"
    ths_curl "$TMP/o3" -H 'Authorization: Bearer nope' "$U/count"; o3="$CURL_CODE"
    ths_curl "$TMP/o4" -H "$AUTH" "$U/count"; o4="$CURL_CODE:$(<"$TMP/o4")"
    ths_curl "$TMP/o5" -H "$AUTH" "$U/count"; o5="$CURL_CODE:$(<"$TMP/o5")"
    kv=""
    ths_curl "$TMP/o6" -H "$AUTH" -X PUT --data-binary v1 "$U/kv/k"; kv+="$CURL_CODE "
    ths_curl "$TMP/o7" -H "$AUTH" "$U/kv/k"; kv+="$CURL_CODE:$(<"$TMP/o7") "
    ths_curl "$TMP/o8" -H "$AUTH" -X DELETE "$U/kv/k"; kv+="$CURL_CODE "
    ths_curl "$TMP/o9" -H "$AUTH" "$U/kv/k"; kv+="$CURL_CODE"
    ths_curl "$TMP/oa" -H "$AUTH" "$U/hello/oop"; oa="$CURL_CODE:$(<"$TMP/oa")"
    ths_curl "$TMP/ob" -X POST --data-binary x "$U/quit"; ob="$CURL_CODE"
    ths_curl "$TMP/oc" "$U/"; oc="$CURL_CODE"
    ths_curl "$TMP/od" -H "$AUTH" -X POST --data-binary x "$U/quit"; od="$CURL_CODE:$(<"$TMP/od")"
    ths_reap 60
    mapfile -t OUT < "$THS_DIR/out"

    kt_test_start "${D2_TITLES[0]}"
    if [[ "${OUT[0]:-}" =~ $URL_RE && "${BASH_REMATCH[1]}" == "$THS_PORT" && "$o1" == 200 && "$b1" == *"/kv/KEY"* && "$o2" == 401 && "$h2" == *$'\nWWW-Authenticate: Bearer'* && "$o3" == 401 ]]; then
        kt_test_pass "URL; 200 public; 401 401"
    else
        kt_test_fail "first='${OUT[0]:-}' index=$o1 noauth=$o2 '${h2:0:120}' wrong=$o3"
    fi

    kt_test_start "${D2_TITLES[1]}"
    if [[ "$o4 $o5" == "200:1 200:2" && "$kv" == "201 200:v1 200 404" && "$oa" == "200:Hello, oop!" ]]; then kt_test_pass "1 2; $kv; Hello, oop!"; else kt_test_fail "count '$o4' '$o5' kv '$kv' hello '$oa'"; fi

    kt_test_start "${D2_TITLES[2]}"
    e="$(<"$THS_DIR/err")"; left="$(ls -A "$THS_DIR/tmp")"
    if [[ "$ob" == 401 && "$oc" == 200 && "$od" == "200:bye" && $THS_TERMED -eq 0 && $THS_RC -eq 0 && -z "$e" && -z "$left" ]]; then
        kt_test_pass "401, still serving, 200 bye, exit 0"
    else
        kt_test_fail "noauth-quit=$ob after=$oc quit='$od' termed=$THS_TERMED exit=$THS_RC stderr='${e:0:200}' tmp='$left'"
    fi
fi
