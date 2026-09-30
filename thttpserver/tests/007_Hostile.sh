#!/bin/bash
# 007_Hostile.sh — thttpserver P2: hostile input through the whole server.
# §1 over TReplayTransport (always runs): response splitting through every
# field a handler can fill from request data (a custom header, ContentType,
# CodeText, Code, SendRedirect, the Server banner), hostile route params and
# query keys (PLAN §2.2, §2.3 C14, facts 13, 14 server path).
# §2 over real sockets (/dev/tcp raw clients): every parser status incl. a NUL
# body and slowloris (408 under RequestTimeout 2 s), a declared Content-Length
# above the limit with the body NOT sent (413), `gone`, a client that connects
# and leaves, header injection on the wire (facts 12, 13).

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

kt_test_section "007: hostile input through the server (P2)"

# The handlers every server here uses: request data flows into each field a
# handler can set. `local` everything (PLAN §2.11 C25).
H_SNIP='
h_inj()   { local v=""; $1.QueryField v; v="$RESULT"; if $2.SetCustomHeader X-V "$v"; then $2.Write set; else $2.Write refused; fi; }
h_ct()    { local v=""; $1.QueryField t; v="$RESULT"; $2.ContentType = "$v"; $2.Write ct; }
h_ctext() { local v=""; $1.QueryField t; v="$RESULT"; $2.CodeText = "$v"; $2.Write ctext; }
h_code()  { local v=""; $1.QueryField c; v="$RESULT"; $2.Code = "$v"; $2.Write code; }
h_redir() { local v="" r=0; $1.QueryField u; v="$RESULT"; $2.SendRedirect "$v" || r=$?; return "$r"; }
h_p()     { local a b; $1.RouteParam a; a="$RESULT"; $1.RouteParam rest; b="$RESULT"; $2.Write "[$a][$b]"; }
h_q()     { local k o=""; for k in x y; do if $1.QueryField "$k"; then o+="$k=[$RESULT]"; else o+="$k=-"; fi; done; $2.Write "$o"; }
h_hdr()   { local v=""; $1.GetHeader x-a; v="$RESULT"; $2.Write "[$v]"; }
h_ok()    { $2.Write ok; }
THttpRouter.new HR
HR.RegisterRoute /inj      GET h_inj
HR.RegisterRoute /ct       GET h_ct
HR.RegisterRoute /ctext    GET h_ctext
HR.RegisterRoute /code     GET h_code
HR.RegisterRoute /redir    GET h_redir
HR.RegisterRoute /p/:a/*rest GET h_p
HR.RegisterRoute /q        GET h_q
HR.RegisterRoute /hdr      GET h_hdr
HR.RegisterRoute /ok       GET h_ok
'

# ===========================================================================
kt_test_section "1. over TReplayTransport: response splitting refused at every field"
# ===========================================================================

eval "$H_SNIP"
THttpServer.new SV
SV.Router = HR
TReplayTransport.new RP
SV.Transport = RP
N=0
# serve REQUEST_TARGET [HEADERS] — one GET through SV.ServeOne; CAPH (head, CR
# removed) / CAPB (body) / CAPC (code) of the capture.
serve() {
    printf 'GET %s HTTP/1.0\r\n%s\r\n' "$1" "${2:-}" > "$TMP/r$N.req"
    RP.AddRequestFile "$TMP/r$N.req"
    SV.ServeOne; CAPC="$RESULT"
    RP.ResponseFile "$N"; local c=""; [[ -f "$RESULT" ]] && c="$(<"$RESULT")"
    CAPH="${c%%$'\r\n\r\n'*}"; CAPH="${CAPH//$'\r'/}"
    if [[ "$c" == *$'\r\n\r\n'* ]]; then CAPB="${c#*$'\r\n\r\n'}"; else CAPB=""; fi
    N=$(( N + 1 ))
}
# no_evil — the head has no injected line (Set-Cookie / X-Evil) at a line start
no_evil() { [[ $'\n'"$CAPH" != *$'\nSet-Cookie'* && $'\n'"$CAPH" != *$'\nX-Evil'* && $'\n'"$CAPH" != *$'\nEvil'* ]]; }

kt_test_start "a custom header from a query value with %0D%0A → SetCustomHeader rc 2 in the handler, nothing injected"
serve '/inj?v=a%0D%0ASet-Cookie:%20evil'; a="$CAPC|$CAPB"; no_evil; e=$?
serve '/inj?v=fine'; b="$CAPB|$CAPH"
if [[ "$a" == "200|refused" && $e -eq 0 && "$b" == "set|"*$'\nX-V: fine\n'* ]]; then kt_test_pass "refused; control sets X-V"; else kt_test_fail "a='$a' evil=$e b='${b:0:200}'"; fi

kt_test_start "ContentType with CR/LF → 500 with the default head, no injected line"
serve '/ct?t=text/html%0D%0AX-Evil:%201'
if [[ "$CAPC" == 500 && "$CAPH" == "HTTP/1.1 500 Internal Server Error"* && "$CAPH" == *$'\nContent-Type: text/plain; charset=utf-8\n'* && -z "$CAPB" ]] && no_evil; then
    kt_test_pass "500 default head"
else
    kt_test_fail "code=$CAPC head='${CAPH:0:300}' body='$CAPB'"
fi

kt_test_start "CodeText with CR/LF → 500, no injected line"
serve '/ctext?t=OK%0D%0AX-Evil:%201'
if [[ "$CAPC" == 500 && "$CAPH" == "HTTP/1.1 500 Internal Server Error"* ]] && no_evil; then kt_test_pass "500"; else kt_test_fail "code=$CAPC head='${CAPH:0:300}'"; fi

kt_test_start "Code from request data: 99, abc, 2000, '200 x', '\$(touch pwn)' → 500 each"
o=""
for c in 99 abc 2000 '200%20x' '%24%28touch%20pwn%29'; do serve "/code?c=$c"; o+="$CAPC "; done
if [[ "$o" == "500 500 500 500 500 " && ! -e "$TMP/pwn" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

kt_test_start "SendRedirect with CR/LF → rc 2 → the server's 500, no Location, no injected line"
serve '/redir?u=/x%0D%0AX-Evil:%201'
if [[ "$CAPC" == 500 && "$CAPH" != *Location* ]] && no_evil; then kt_test_pass "500"; else kt_test_fail "code=$CAPC head='${CAPH:0:300}'"; fi

kt_test_start "the Server banner with CR/LF → 500 with the default head (Server: kcl-thttpserver)"
SV.ServerBanner = $'kcl\r\nEvil: 1'
serve '/ok'
SV.ServerBanner = kcl-thttpserver
if [[ "$CAPC" == 500 && "$CAPH" == *$'\nServer: kcl-thttpserver\n'* ]] && no_evil; then kt_test_pass "500"; else kt_test_fail "code=$CAPC head='${CAPH:0:300}'"; fi

kt_test_start "hostile route params (:a and *rest) round-trip decoded, as data; nothing executes"
serve '/p/%24%28touch%20pwn%29/a%60touch%20pwn%60/b%0Ac'
if [[ "$CAPC" == 200 && "$CAPB" == '[$(touch pwn)][a`touch pwn`/b'$'\n''c]' && ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" ]] && no_evil; then
    kt_test_pass "verbatim"
else
    kt_test_fail "code=$CAPC body='$CAPB'"
fi

kt_test_start "hostile header values reach the handler as data; a non-token header name is 400"
serve '/hdr' 'X-A: $(touch pwn) `id` ;x'$'\r\n'; a="$CAPC|$CAPB"
serve '/hdr' 'X-$(touch pwn): v'$'\r\n'; b="$CAPC"
if [[ "$a" == '200|[$(touch pwn) `id` ;x]' && "$b" == 400 && ! -e "$TMP/pwn" ]]; then kt_test_pass "data; 400"; else kt_test_fail "a='$a' b='$b'"; fi

kt_test_start "?=x, ?&&, ?=, ?a=1&=2, ?%00=1&x=%00 do not abort the server; it goes on serving"
o=""
for q in '=x' '&&' '=' 'a=1&=2' '%00=1&x=%00&y=2'; do serve "/q?$q"; o+="$CAPC:$CAPB "; done
serve '/ok'; o+="$CAPC:$CAPB"
if [[ "$o" == "200:x=-y=- 200:x=-y=- 200:x=-y=- 200:x=-y=- 200:x=-y=[2] 200:ok" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

SV.delete
RP.delete
HR.delete

# ===========================================================================
kt_test_section "2. over real sockets: every parser status, slowloris, oversize, injection (facts 12, 13)"
# ===========================================================================

W_TITLES=(
    "400: two spaces in the request line; absolute-form target; HTTP/1.1 without Host"
    "413: a declared Content-Length above MaxContentLength (1024) with the body NOT sent — answered at once"
    "414: a 9000-byte request target"
    "431: a 9000-byte header line; 101 headers"
    "501: an unknown method (BREW); Transfer-Encoding"
    "505: HTTP/2.0"
    "400 at once: a NUL in the body"
    "408 (slowloris): request line + one header, then silence — answered after RequestTimeout (2 s)"
    "gone: headers cut off by the client → nothing answered; a client that connects and leaves → nothing either; the server goes on"
    "header injection on the wire: %0D%0A in a value never reaches the head"
    "fact 13 on the wire: hostile query keys/values and header values are data; no pwn anywhere"
    "F2 on the wire: two Host headers → 400 (identical values; different case and values)"
    "F5 on the wire: a leading bare LF before the request line → 400, as the direct parse (001); a leading CRLF likewise"
    "the server survives all of it: /ok 200, Serve rc 0, empty LastError, silent stderr"
)
SNIP_H="$H_SNIP"'
S.Router = HR
S.MaxContentLength = 1024
'

if ! ths_have_nc; then
    ths_skip "${W_TITLES[@]}"
elif ! ths_start h "$SNIP_H" RT=2 IDLE_BUDGET=60; then
    for t in "${W_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "server h never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    H_DIR="$THS_DIR"
    # st REQUEST — send it raw, the status line's code into ST.
    st() { ths_raw "$TMP/st.out" "$1"; ths_split "$TMP/st.out"; ST="${THS_HEAD%%$'\n'*}"; ST="${ST#HTTP/1.1 }"; ST="${ST%% *}"; }

    kt_test_start "${W_TITLES[0]}"
    o=""
    st "GET  / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"; o+="$ST "
    st "GET http://x/ HTTP/1.0${CRLF}${CRLF}"; o+="$ST "
    st "GET / HTTP/1.1${CRLF}${CRLF}"; o+="$ST"
    if [[ "$o" == "400 400 400" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

    kt_test_start "${W_TITLES[1]}"
    t0=${EPOCHREALTIME//[!0-9]/}
    st "POST /ok HTTP/1.0${CRLF}Content-Length: 5000${CRLF}${CRLF}"
    ms=$(( (${EPOCHREALTIME//[!0-9]/} - t0) / 1000 ))
    if [[ "$ST" == 413 && $RAW_RC -eq 0 ]]; then kt_test_pass "413 (${ms} ms, no body sent)"; else kt_test_fail "'$ST' rc=$RAW_RC ${ms} ms"; fi

    kt_test_start "${W_TITLES[2]}"
    printf -v long '%9000s' ''; long="${long// /a}"
    st "GET /$long HTTP/1.0${CRLF}${CRLF}"
    if [[ "$ST" == 414 ]]; then kt_test_pass "414"; else kt_test_fail "'$ST'"; fi

    kt_test_start "${W_TITLES[3]}"
    o=""
    st "GET /ok HTTP/1.0${CRLF}X-Big: $long${CRLF}${CRLF}"; o+="$ST "
    many=""; for (( i = 0; i < 101; i++ )); do many+="X-H$i: v${CRLF}"; done
    st "GET /ok HTTP/1.0${CRLF}${many}${CRLF}"; o+="$ST"
    if [[ "$o" == "431 431" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

    kt_test_start "${W_TITLES[4]}"
    o=""
    st "BREW /ok HTTP/1.0${CRLF}${CRLF}"; o+="$ST "
    st "POST /ok HTTP/1.1${CRLF}Host: x${CRLF}Transfer-Encoding: chunked${CRLF}${CRLF}"; o+="$ST"
    if [[ "$o" == "501 501" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

    kt_test_start "${W_TITLES[5]}"
    st "GET /ok HTTP/2.0${CRLF}${CRLF}"
    if [[ "$ST" == 505 ]]; then kt_test_pass "505"; else kt_test_fail "'$ST'"; fi

    kt_test_start "${W_TITLES[6]}"
    printf 'POST /ok HTTP/1.0\r\nContent-Length: 3\r\n\r\na\0b' > "$TMP/nul.req"
    ths_rawf "$TMP/nul.out" "$TMP/nul.req"; ths_split "$TMP/nul.out"
    if [[ "${THS_HEAD%%$'\n'*}" == "HTTP/1.1 400 Bad Request" ]]; then kt_test_pass "400"; else kt_test_fail "'${THS_HEAD:0:40}'"; fi

    kt_test_start "${W_TITLES[7]}"
    t0=${EPOCHREALTIME//[!0-9]/}
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || exit 7; printf 'GET /ok HTTP/1.1\r\nHost: x\r\n' >&3; timeout 30 cat <&3 > "$TMP/slow.out" ) 2>/dev/null
    src=$?
    ms=$(( (${EPOCHREALTIME//[!0-9]/} - t0) / 1000 ))
    s="$(<"$TMP/slow.out")"
    if [[ $src -eq 0 && "$s" == "HTTP/1.1 408 Request Timeout"* && $ms -ge 1500 ]]; then kt_test_pass "408 after ${ms} ms"; else kt_test_fail "rc=$src '${s:0:40}' ${ms} ms"; fi

    kt_test_start "${W_TITLES[8]}"
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" && printf 'GET /ok HTTP/1.0\r\nX-A: 1\r\n' >&3 && exec 3>&- ) 2>/dev/null
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" && exec 3>&- ) 2>/dev/null
    ths_curl "$TMP/after" "http://127.0.0.1:$THS_PORT/ok"
    if [[ "$CURL_CODE" == 200 && "$(<"$TMP/after")" == ok ]]; then kt_test_pass "the next request: 200"; else kt_test_fail "code=$CURL_CODE"; fi

    kt_test_start "${W_TITLES[9]}"
    ths_raw "$TMP/inj.out" "GET /inj?v=a%0D%0ASet-Cookie:%20evil HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/inj.out"
    if [[ "${THS_HEAD%%$'\n'*}" == "HTTP/1.1 200 OK" && "$THS_BODY" == refused && $'\n'"$THS_HEAD" != *$'\nSet-Cookie'* ]]; then kt_test_pass "refused, head clean"; else kt_test_fail "head='${THS_HEAD:0:200}' body='$THS_BODY'"; fi

    kt_test_start "${W_TITLES[10]}"
    ths_raw "$TMP/q.out" "GET /q?x=\$(touch%20pwn)&%24%28touch%20pwn%29=1&y=%60touch%20pwn%60 HTTP/1.0${CRLF}${CRLF}"; ths_split "$TMP/q.out"; b1="$THS_BODY"
    ths_raw "$TMP/h.out" "GET /hdr HTTP/1.0${CRLF}X-A: \$(touch pwn);\`touch pwn\`${CRLF}${CRLF}"; ths_split "$TMP/h.out"; b2="$THS_BODY"
    if [[ "$b1" == 'x=[$(touch pwn)]y=[`touch pwn`]' && "$b2" == '[$(touch pwn);`touch pwn`]' && ! -e "$H_DIR/pwn" && ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" ]]; then
        kt_test_pass "data, no pwn"
    else
        kt_test_fail "q='$b1' h='$b2'"
    fi

    kt_test_start "${W_TITLES[11]}"
    o=""
    st "GET /ok HTTP/1.1${CRLF}Host: x${CRLF}Host: x${CRLF}${CRLF}"; o+="$ST "
    st "GET /ok HTTP/1.1${CRLF}Host: a${CRLF}hOST: b${CRLF}${CRLF}"; o+="$ST "
    st "GET /ok HTTP/1.1${CRLF}Host: a${CRLF}${CRLF}"; o+="$ST"
    if [[ "$o" == "400 400 200" ]]; then kt_test_pass "$o (one Host: 200)"; else kt_test_fail "'$o'"; fi

    kt_test_start "${W_TITLES[12]}"
    o=""
    st $'\n'"GET /ok HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"; o+="$ST|$THS_BODY "
    st "${CRLF}GET /ok HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"; o+="$ST|$THS_BODY "
    st "GET /ok HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"; o+="$ST|$THS_BODY"
    if [[ "$o" == "400| 400| 200|ok" ]]; then kt_test_pass "$o"; else kt_test_fail "'$o'"; fi

    kt_test_start "${W_TITLES[13]}"
    ths_curl "$TMP/ok" "http://127.0.0.1:$THS_PORT/ok"; okc="$CURL_CODE"
    ths_finish
    ths_result rc; rc="$THS_V"; ths_result le; le="$THS_V"
    e="$(<"$H_DIR/err")"
    if [[ "$okc" == 200 && $THS_RC -eq 0 && "$rc" == 0 && -z "$le" && -z "$e" ]]; then kt_test_pass "alive and clean"; else kt_test_fail "ok=$okc exit=$THS_RC rc=$rc le='$le' stderr='${e:0:300}'"; fi
fi
