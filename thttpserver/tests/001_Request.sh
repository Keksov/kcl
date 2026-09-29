#!/bin/bash
# 001_Request.sh — thttpserver P0: THttpRequest (the ReadFrom parser, limits,
# decoding, statuses, read-only fields), the transport seam (THttpTransport is
# abstract, TReplayTransport is the fork-free test double) and the fork-free
# proof of the replay pipeline (PLAN §2.2, §2.5, §3 facts 2, 12, 13, 19, 23, §4).
#
# Every request is a RAW file (or a pipe for the timeout cases) — the parser
# never sees a socket here. Stdin is closed for the whole file; a pipe producer
# that must stay open writes nothing to the runner's stdout/stderr and is
# killed and reaped by the case that started it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/thttpserver.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
CRLF=$'\r\n'
unset -v HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy

# mk NAME CONTENT — a raw request file, byte for byte.
mk() { printf '%s' "$2" > "$TMP/$1"; }

# deadline OFFSET_US — absolute deadline in µs (EPOCHREALTIME digits only, so
# the caller's locale decimal separator does not matter).
deadline() { DL=$(( ${EPOCHREALTIME//[!0-9]/} + $1 )); }

# fresh INST — a clean THttpRequest under INST.
fresh() {
    if declare -p "${1}_class" >/dev/null 2>&1; then
        "$1".delete
    fi
    THttpRequest.new "$1"
}

# parse FILE [MAXBODY [FIRSTLINE [REMOTE]]] — R.ReadFrom over a plain fd on FILE.
# Sets P_RC (member rc) and P_ST (RESULT).
parse() {
    local f="$1" max="${2:-65536}" fd
    shift; [[ $# -gt 0 ]] && shift
    fresh R
    exec {fd}<"$f"
    deadline 10000000
    P_RC=0
    R.ReadFrom "$fd" "$DL" "$max" "$@" || P_RC=$?
    P_ST="$RESULT"
    exec {fd}<&-
}

# get INST MEMBER [ARGS] — a direct read; G = RESULT, GRC = rc.
get() {
    local i="$1" m="$2"; shift 2
    RESULT="__stale__"
    GRC=0
    "$i.$m" "$@" || GRC=$?
    G="$RESULT"
}

kt_test_section "001: THttpRequest, the transport seam, fork-free proof (P0)"

# ===========================================================================
kt_test_section "1. a good request: every field"
# ===========================================================================

mk good.req "GET /a/b%20c?x=1&y=%41 HTTP/1.1${CRLF}Host: example${CRLF}X-Multi: one${CRLF}User-Agent: t/1${CRLF}x-multi: two${CRLF}${CRLF}"
parse "$TMP/good.req" 65536 "" "10.0.0.1:4242"

kt_test_start "ReadFrom on a good HTTP/1.1 request: rc 0, RESULT 0"
if [[ $P_RC -eq 0 && "$P_ST" == "0" ]]; then kt_test_pass "rc 0 / 0"; else kt_test_fail "rc=$P_RC RESULT='$P_ST'"; fi

kt_test_start "Method / URI / PathInfo (NOT decoded) / QueryString / ProtocolVersion / RemoteAddress"
bad=""
get R Method;          [[ "$G" == "GET" ]]                 || bad+=" Method='$G'"
get R URI;             [[ "$G" == "/a/b%20c?x=1&y=%41" ]]  || bad+=" URI='$G'"
get R PathInfo;        [[ "$G" == "/a/b%20c" ]]            || bad+=" PathInfo='$G'"
get R QueryString;     [[ "$G" == "x=1&y=%41" ]]           || bad+=" QueryString='$G'"
get R ProtocolVersion; [[ "$G" == "1.1" ]]                 || bad+=" ProtocolVersion='$G'"
get R RemoteAddress;   [[ "$G" == "10.0.0.1:4242" ]]       || bad+=" RemoteAddress='$G'"
get R Content;         [[ "$G" == "" ]]                    || bad+=" Content='$G'"
get R ContentLength;   [[ "$G" == "0" ]]                   || bad+=" ContentLength='$G'"
if [[ -z "$bad" ]]; then kt_test_pass "all eight"; else kt_test_fail "$bad"; fi

kt_test_start "GetHeader is case-insensitive; a repeated header is joined with ', '"
bad=""
get R GetHeader host;       [[ $GRC -eq 0 && "$G" == "example" ]]  || bad+=" host=$GRC:'$G'"
get R GetHeader HOST;       [[ $GRC -eq 0 && "$G" == "example" ]]  || bad+=" HOST=$GRC:'$G'"
get R GetHeader X-MULTI;    [[ $GRC -eq 0 && "$G" == "one, two" ]] || bad+=" X-MULTI=$GRC:'$G'"
get R GetHeader user-agent; [[ $GRC -eq 0 && "$G" == "t/1" ]]      || bad+=" UA=$GRC:'$G'"
if [[ -z "$bad" ]]; then kt_test_pass "host, HOST, X-MULTI joined, user-agent"; else kt_test_fail "$bad"; fi

kt_test_start "GetHeader: absent → rc 1 + RESULT ''; '' → rc 2 + RESULT ''"
get R GetHeader x-none; a="$GRC:$G"
get R GetHeader "";     b="$GRC:$G"
if [[ "$a" == "1:" && "$b" == "2:" ]]; then kt_test_pass "1:'' and 2:''"; else kt_test_fail "absent=$a empty=$b"; fi

kt_test_start "HasHeader is a predicate: rc 0 present (any case), rc 1 absent, rc 2 for ''"
r1=0; R.HasHeader HoSt || r1=$?
r2=0; R.HasHeader x-none || r2=$?
r3=0; R.HasHeader "" || r3=$?
if [[ "$r1$r2$r3" == "012" ]]; then kt_test_pass "0 1 2"; else kt_test_fail "rc $r1 $r2 $r3"; fi

kt_test_start "HeaderNames OUTARR: lower-cased names, arrival order, one per name; RESULT = count"
declare -a HN=()
get R HeaderNames HN
if [[ $GRC -eq 0 && "$G" == "3" && "${HN[*]}" == "host x-multi user-agent" ]]; then
    kt_test_pass "(${HN[*]}) count 3"
else
    kt_test_fail "rc=$GRC RESULT='$G' names=(${HN[*]})"
fi

kt_test_start "HeaderNames refuses a malformed / reserved OUTARR with rc 2 and writes nothing"
bad=""
for n in "" 1bad "a b" __ths_x __THS_REASON __THS_CR RESULT state R_hdr R_hdrn R_qf R_rp R_data; do
    get R HeaderNames "$n"
    [[ $GRC -eq 2 && "$G" == "" ]] || bad+=" '$n'=$GRC:'$G'"
done
if [[ -z "$bad" ]]; then kt_test_pass "13 names refused"; else kt_test_fail "$bad"; fi

kt_test_start "FIRSTLINE given (with its CR): the fd supplies only the headers; REMOTE lands in RemoteAddress"
mk hdronly.req "Host: h${CRLF}${CRLF}"
parse "$TMP/hdronly.req" 65536 "PUT /first?q=z HTTP/1.1"$'\r' "1.2.3.4:5"
get R Method; m="$G"; get R URI; u="$G"; get R RemoteAddress; ra="$G"; get R GetHeader host; h="$G"
if [[ "$P_ST" == "0" && "$m" == "PUT" && "$u" == "/first?q=z" && "$ra" == "1.2.3.4:5" && "$h" == "h" ]]; then
    kt_test_pass "PUT /first?q=z from FIRSTLINE, Host from the fd"
else
    kt_test_fail "st='$P_ST' m='$m' u='$u' ra='$ra' h='$h'"
fi

kt_test_start "bare LF line endings are accepted; HTTP/1.0 needs no Host"
mk barelf.req $'GET /lf HTTP/1.0\nX-A:  spaced value \t\n\n'
parse "$TMP/barelf.req"
get R GetHeader x-a
if [[ "$P_ST" == "0" && "$G" == "spaced value" ]]; then kt_test_pass "0; OWS trimmed: '$G'"; else kt_test_fail "st='$P_ST' x-a='$G'"; fi

kt_test_start "the same Content-Length twice is one value (not joined, not 400)"
mk samecl.req "POST / HTTP/1.0${CRLF}Content-Length: 3${CRLF}Content-Length: 3${CRLF}${CRLF}abc"
parse "$TMP/samecl.req"
get R GetHeader content-length; cl="$G"; get R Content
if [[ "$P_ST" == "0" && "$cl" == "3" && "$G" == "abc" ]]; then kt_test_pass "CL 3, body abc"; else kt_test_fail "st='$P_ST' cl='$cl' body='$G'"; fi

kt_test_start "ReadFrom resets the instance: a second parse leaves nothing of the first"
parse "$TMP/good.req"
fdr=""; exec {fdr}<"$TMP/barelf.req"; deadline 10000000
R.ReadFrom "$fdr" "$DL" 65536; exec {fdr}<&-
get R GetHeader host; a="$GRC"; get R QueryField x; b="$GRC"; get R RemoteAddress; c="$G"
declare -a HN=(); R.HeaderNames HN
if [[ "$a" == "1" && "$b" == "1" && -z "$c" && "${HN[*]}" == "x-a" ]]; then
    kt_test_pass "old headers, query fields and remote are gone"
else
    kt_test_fail "host rc=$a x rc=$b remote='$c' names=(${HN[*]})"
fi

kt_test_start "ReadFrom rejects a malformed CALL with rc 2 + RESULT '' (fd, deadline, maxbody not integers)"
bad=""
fresh R
for args in "x 1 1" "3 y 1" "3 1 z" "3 1 -1" "-1 1 1"; do
    read -r -a A <<< "$args"
    get R ReadFrom "${A[@]}"
    [[ $GRC -eq 2 && "$G" == "" ]] || bad+=" [$args]=$GRC:'$G'"
done
get R ReadFrom
[[ $GRC -eq 2 && "$G" == "" ]] || bad+=" [none]=$GRC:'$G'"
if [[ -z "$bad" ]]; then kt_test_pass "6 malformed calls refused"; else kt_test_fail "$bad"; fi

# ===========================================================================
kt_test_section "2. byte semantics of the body (fact 2, request half)"
# ===========================================================================

kt_test_start "'aжb' with Content-Length 4 (bytes) is read exactly; ContentLength = 4"
mk mb.req "POST /mb HTTP/1.0${CRLF}Content-Length: 4${CRLF}${CRLF}aжbTRAILING"
parse "$TMP/mb.req"
get R Content; c="$G"; get R ContentLength; n="$G"
if [[ "$P_ST" == "0" && "$c" == "aжb" && "$n" == "4" ]]; then kt_test_pass "Content='aжb' ContentLength=4, trailing bytes not read"; else kt_test_fail "st='$P_ST' Content='$c' ContentLength='$n'"; fi

kt_test_start "a body of 3-byte characters split at a byte count reads exactly CL bytes, CR/LF inside kept"
body="жж"$'\r\n'"ё"   # 2+2+2+2 = 8 bytes
mk mb2.req "PUT /x HTTP/1.0${CRLF}Content-Length: 8${CRLF}${CRLF}${body}XYZ"
parse "$TMP/mb2.req"
get R Content; c="$G"; get R ContentLength; n="$G"
if [[ "$P_ST" == "0" && "$c" == "$body" && "$n" == "8" ]]; then kt_test_pass "8 bytes, CRLF kept"; else kt_test_fail "st='$P_ST' len=$n content='$c'"; fi

kt_test_start "a body of exactly MAXBODY bytes is read (65536)"
printf -v big '%*s' 65536 ''; big="${big// /a}"
mk big.req "POST / HTTP/1.0${CRLF}Content-Length: 65536${CRLF}${CRLF}${big}"
parse "$TMP/big.req" 65536
get R ContentLength
if [[ "$P_ST" == "0" && "$G" == "65536" ]]; then kt_test_pass "65536 bytes"; else kt_test_fail "st='$P_ST' len='$G'"; fi
unset -v big

# ===========================================================================
kt_test_section "3. every parser status from raw request files via TReplayTransport (fact 12)"
# ===========================================================================

printf -v L8192 '%*s' 8178 ''; L8192="GET /${L8192// /a} HTTP/1.0"   # 5 + 8178 + 9 = 8192 bytes
printf -v L8193 '%*s' 8179 ''; L8193="GET /${L8193// /a} HTTP/1.0"   # 8193 bytes
printf -v H8192 '%*s' 8189 ''; H8192="X: ${H8192// /v}"               # 3 + 8189 = 8192 bytes
printf -v H8193 '%*s' 8190 ''; H8193="X: ${H8193// /v}"               # 8193 bytes
H100=""; for (( i = 1; i <= 100; i++ )); do H100+="X-$i: $i${CRLF}"; done

CN=(); CB=(); CE=()
add() { CN+=("$1"); CB+=("$2"); CE+=("$3"); }
add ok-get        "GET /a?b=1 HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                0
add ok-10-nohost  "GET / HTTP/1.0${CRLF}${CRLF}"                                   0
add ok-8192-line  "${L8192}${CRLF}${CRLF}"                                         0
add ok-8192-hdr   "GET / HTTP/1.0${CRLF}${H8192}${CRLF}${CRLF}"                    0
add ok-100-hdrs   "GET / HTTP/1.0${CRLF}${H100}${CRLF}"                            0
add 400-absolute  "GET http://x/ HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"             400
add 400-asterisk  "OPTIONS * HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                 400
add 400-2spaces   "GET  / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                    400
add 400-oneword   "GET${CRLF}${CRLF}"                                              400
add 400-4words    "GET / HTTP/1.1 x${CRLF}Host: x${CRLF}${CRLF}"                   400
add 400-trailsp   "GET / HTTP/1.1 ${CRLF}Host: x${CRLF}${CRLF}"                    400
add 400-tab       "GET"$'\t'"/ HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"               400
add 400-ctl-tgt   "GET /a"$'\001'"b HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"          400
add 400-emptyline "${CRLF}GET / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"              400
add 400-ver-foo   "GET / FOO/1.1${CRLF}${CRLF}"                                    400
add 400-ver-short "GET / HTTP/1${CRLF}${CRLF}"                                     400
add 400-ver-lower "GET / http/1.1${CRLF}${CRLF}"                                   400
add 400-no-host   "GET / HTTP/1.1${CRLF}X: y${CRLF}${CRLF}"                        400
add 400-hdr-space "GET / HTTP/1.0${CRLF}Bad Name: x${CRLF}${CRLF}"                 400
add 400-hdr-paren "GET / HTTP/1.0${CRLF}X-\$(touch pwn): v${CRLF}${CRLF}"          400
add 400-hdr-empty "GET / HTTP/1.0${CRLF}: v${CRLF}${CRLF}"                         400
add 400-hdr-colon "GET / HTTP/1.0${CRLF}NoColonHere${CRLF}${CRLF}"                 400
add 400-hdr-sp-b4 "GET / HTTP/1.0${CRLF}X-A : v${CRLF}${CRLF}"                     400
add 400-obs-fold  "GET / HTTP/1.0${CRLF}X-A: 1${CRLF}  more${CRLF}${CRLF}"         400
add 400-obs-tab   "GET / HTTP/1.0${CRLF}X-A: 1${CRLF}"$'\t'"more${CRLF}${CRLF}"    400
add 400-inner-cr  "GET / HTTP/1.0${CRLF}X-A: a"$'\r'"b${CRLF}${CRLF}"              400
add 400-cl-differ "POST / HTTP/1.0${CRLF}Content-Length: 3${CRLF}Content-Length: 4${CRLF}${CRLF}abcd" 400
add 400-cl-abc    "POST / HTTP/1.0${CRLF}Content-Length: abc${CRLF}${CRLF}"        400
add 400-cl-neg    "POST / HTTP/1.0${CRLF}Content-Length: -1${CRLF}${CRLF}"         400
add 400-cl-plus   "POST / HTTP/1.0${CRLF}Content-Length: +3${CRLF}${CRLF}abc"      400
add 400-cl-2words "POST / HTTP/1.0${CRLF}Content-Length: 1 2${CRLF}${CRLF}abc"     400
add 400-cl-empty  "POST / HTTP/1.0${CRLF}Content-Length:${CRLF}${CRLF}"            400
add 400-cl-huge   "POST / HTTP/1.0${CRLF}Content-Length: 99999999999999999999${CRLF}${CRLF}" 400
add 400-nul-body  "(written below with a real NUL)"                                400
add 413-70000     "POST / HTTP/1.0${CRLF}Content-Length: 70000${CRLF}${CRLF}abc"   413
add 413-plus1     "POST / HTTP/1.0${CRLF}Content-Length: 65537${CRLF}${CRLF}abc"   413
add 414-9000      "GET /$(printf '%*s' 9000 '' | tr ' ' a) HTTP/1.0${CRLF}${CRLF}" 414
add 414-8193      "${L8193}${CRLF}${CRLF}"                                         414
add 431-8193-hdr  "GET / HTTP/1.0${CRLF}${H8193}${CRLF}${CRLF}"                    431
add 431-101-hdrs  "GET / HTTP/1.0${CRLF}${H100}X-101: x${CRLF}${CRLF}"             431
add 501-foo       "FOO / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                     501
add 501-lower     "get / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                     501
add 501-dash      "G-T / HTTP/1.0${CRLF}${CRLF}"                                   501
add 501-connect   "CONNECT / HTTP/1.1${CRLF}Host: x${CRLF}${CRLF}"                 501
add 501-te        "POST / HTTP/1.1${CRLF}Host: x${CRLF}Transfer-Encoding: chunked${CRLF}${CRLF}" 501
add 505-2.0       "GET / HTTP/2.0${CRLF}${CRLF}"                                   505
add 505-1.2       "GET / HTTP/1.2${CRLF}${CRLF}"                                   505
add 505-0.9       "GET / HTTP/0.9${CRLF}${CRLF}"                                   505
add gone-empty    ""                                                               gone
add gone-partial  "GET / HT"                                                       gone
add gone-nohdrend "GET / HTTP/1.0${CRLF}X: 1${CRLF}"                               gone
add gone-parthdr  "GET / HTTP/1.0${CRLF}X: 1"                                      gone
add gone-shortbdy "POST / HTTP/1.0${CRLF}Content-Length: 10${CRLF}${CRLF}abc"      gone
for (( i = 0; i < ${#CN[@]}; i++ )); do mk "c_${CN[i]}.req" "${CB[i]}"; done
# A bash string cannot hold a NUL: the NUL fixture is written by printf itself.
printf 'POST / HTTP/1.0\r\nContent-Length: 5\r\n\r\na\0bcd' > "$TMP/c_400-nul-body.req"

TReplayTransport.new RT
for (( i = 0; i < ${#CN[@]}; i++ )); do RT.AddRequestFile "$TMP/c_${CN[i]}.req"; done

kt_test_start "the NUL fixture really carries a NUL byte (od), so the 400 below is the NUL rule"
if od -An -c "$TMP/c_400-nul-body.req" | grep -q '\\0'; then kt_test_pass "NUL present"; else kt_test_fail "fixture has no NUL"; fi

bad=""; okn=0
for (( i = 0; i < ${#CN[@]}; i++ )); do
    arc=0; RT.Accept 0 10 || arc=$?
    if [[ $arc -ne 0 ]]; then bad+=" ${CN[i]}:accept-rc=$arc"; continue; fi
    RT.InFd; infd="$RESULT"
    fresh R
    deadline 10000000
    rrc=0; R.ReadFrom "$infd" "$DL" 65536 || rrc=$?
    st="$RESULT"
    RT.CloseConnection
    if [[ $rrc -eq 0 && "$st" == "${CE[i]}" ]]; then
        okn=$(( okn + 1 ))
    else
        bad+=" ${CN[i]}:rc=$rrc,st='${st:0:20}'(want ${CE[i]})"
    fi
done
kt_test_start "all ${#CN[@]} raw requests yield their pinned status (0/400/413/414/431/501/505/gone), rc 0 each"
if [[ -z "$bad" && $okn -eq ${#CN[@]} ]]; then kt_test_pass "$okn/${#CN[@]}"; else kt_test_fail "$okn/${#CN[@]}:$bad"; fi

kt_test_start "after the last file, Accept is rc 2 with a LastError"
get RT Accept 0 10; arc="$GRC"; get RT LastError
if [[ "$arc" == "2" && -n "$G" ]]; then kt_test_pass "rc 2, LastError='$G'"; else kt_test_fail "rc=$arc LastError='$G'"; fi
RT.delete

# ---------------------------------------------------------------------------
# 413 does not read the body; 408 on a spent deadline does not read at all.
# ---------------------------------------------------------------------------
kt_test_start "413: the body is NOT read — the next bytes on the fd are the body's"
fd=""; exec {fd}<"$TMP/c_413-70000.req"; fresh R; deadline 10000000
R.ReadFrom "$fd" "$DL" 65536; st="$RESULT"
IFS= read -r -n 3 -u "$fd" nxt; exec {fd}<&-
if [[ "$st" == "413" && "$nxt" == "abc" ]]; then kt_test_pass "413, fd positioned at 'abc'"; else kt_test_fail "st='$st' next='$nxt'"; fi

kt_test_start "408 when the deadline is already spent — without calling read (the fd still holds the request line)"
fd=""; exec {fd}<"$TMP/good.req"; fresh R; deadline -1
rrc=0; R.ReadFrom "$fd" "$DL" 65536 || rrc=$?; st="$RESULT"
IFS= read -r -u "$fd" nxt; exec {fd}<&-
if [[ $rrc -eq 0 && "$st" == "408" && "$nxt" == "GET /a/b%20c?x=1&y=%41 HTTP/1.1"$'\r' ]]; then kt_test_pass "408, nothing consumed"; else kt_test_fail "rc=$rrc st='$st' next='$nxt'"; fi

kt_test_start "408 with a spent deadline also when FIRSTLINE is given"
fd=""; exec {fd}<"$TMP/hdronly.req"; fresh R; deadline -5000000
R.ReadFrom "$fd" "$DL" 65536 "GET / HTTP/1.0"; st="$RESULT"; exec {fd}<&-
if [[ "$st" == "408" ]]; then kt_test_pass "408"; else kt_test_fail "st='$st'"; fi

# ---------------------------------------------------------------------------
# Pipes that stay open: a silent client runs into the deadline (408); a NUL in
# the body is 400 AT ONCE (the pipe is still open, so a parser that waited for
# the missing byte would end at the deadline with 408 instead).
# ---------------------------------------------------------------------------
# slow CONTENT DEADLINE_OFFSET_US — ReadFrom over a pipe that stays open after CONTENT.
slow() {
    local fd pid
    exec {fd}< <(exec 2>/dev/null; printf '%s' "$1"; exec sleep 30)
    pid=$!
    fresh R
    deadline "$2"
    P_RC=0; R.ReadFrom "$fd" "$DL" 65536 || P_RC=$?
    P_ST="$RESULT"
    exec {fd}<&-
    kill "$pid" 2>/dev/null || :
    wait "$pid" 2>/dev/null || :
}

kt_test_start "408: nothing arrives before the deadline"
slow "" 300000
if [[ $P_RC -eq 0 && "$P_ST" == "408" ]]; then kt_test_pass "408"; else kt_test_fail "rc=$P_RC st='$P_ST'"; fi

kt_test_start "408: a partial request line, then silence"
slow "GET / HT" 300000
if [[ "$P_ST" == "408" ]]; then kt_test_pass "408"; else kt_test_fail "st='$P_ST'"; fi

kt_test_start "408: headers without the blank line, then silence (slowloris)"
slow "GET / HTTP/1.0${CRLF}X-A: 1${CRLF}X-B" 300000
if [[ "$P_ST" == "408" ]]; then kt_test_pass "408"; else kt_test_fail "st='$P_ST'"; fi

kt_test_start "408: a short body at the deadline"
slow "POST / HTTP/1.0${CRLF}Content-Length: 10${CRLF}${CRLF}abc" 300000
if [[ "$P_ST" == "408" ]]; then kt_test_pass "408"; else kt_test_fail "st='$P_ST'"; fi

kt_test_start "NUL in the body over an OPEN pipe → 400 at once (not 408 at a 20 s deadline)"
fd=""; exec {fd}< <(exec 2>/dev/null; printf 'POST / HTTP/1.0\r\nContent-Length: 5\r\n\r\na\0bcd'; exec sleep 30)
pid=$!
fresh R; deadline 20000000
R.ReadFrom "$fd" "$DL" 65536; st="$RESULT"
exec {fd}<&-; kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :
if [[ "$st" == "400" ]]; then kt_test_pass "400"; else kt_test_fail "st='$st'"; fi

# ===========================================================================
kt_test_section "4. query fields: decoding, first occurrence, %00, hostile and empty keys (facts 13)"
# ===========================================================================

mk q.req 'GET /p?a=1&b=x+y&c=%41%42&d=%e2%80%94&e=%G1&f=%00z&g&h=&a=2&bs=a\b&pct=%25&bsx=%5Cx41&bsn=%5Cn&tail=%4&u=%C3%A9t%C3%A9 HTTP/1.0'"${CRLF}${CRLF}"
parse "$TMP/q.req"
kt_test_start "the query request parses"
if [[ "$P_ST" == "0" ]]; then kt_test_pass "0"; else kt_test_fail "st='$P_ST'"; fi

qf() {   # NAME EXPECTED_RC EXPECTED_VALUE
    get R QueryField "$1"
    [[ "$GRC" == "$2" && "$G" == "$3" ]] || bad+=" [$1]=$GRC:'$G'(want $2:'$3')"
}
kt_test_start "QueryField: first occurrence, '+' → space, %XX decoded (UTF-8 too), invalid %G1 and a truncated %4 literal"
bad=""
qf a 0 1; qf b 0 "x y"; qf c 0 AB; qf d 0 "—"; qf e 0 "%G1"; qf pct 0 "%"; qf tail 0 "%4"; qf u 0 "été"
if [[ -z "$bad" ]]; then kt_test_pass "8 fields"; else kt_test_fail "$bad"; fi

kt_test_start "QueryField: a backslash is data — never an escape (a\\b, %5Cx41 → \\x41, %5Cn → \\n)"
bad=""
qf bs 0 'a\b'; qf bsx 0 '\x41'; qf bsn 0 '\n'
if [[ -z "$bad" ]]; then kt_test_pass "3 fields verbatim"; else kt_test_fail "$bad"; fi

kt_test_start "QueryField: %00 → rc 1; 'g' and 'h=' → '' rc 0; absent → rc 1; '' → rc 2"
bad=""
qf f 1 ""; qf g 0 ""; qf h 0 ""; qf nope 1 ""; qf "" 2 ""
if [[ -z "$bad" ]]; then kt_test_pass "5 edge cases"; else kt_test_fail "$bad"; fi

# Hostile and empty keys. Each parse runs as ONE compound command followed by a
# marker assignment: an empty assoc key aborts the whole top-level command in
# bash, so a lost marker means the parser tripped over one.
cd "$TMP" || exit 1
rm -f "$TMP/pwn"
hostile_q() {   # QUERY
    mk hq.req "GET /h?$1 HTTP/1.0${CRLF}X-V: \$(touch pwn)\`touch pwn\`\${IFS}${CRLF}\$x: dollar${CRLF}*: star${CRLF}${CRLF}"
    REACHED=0
    { parse "$TMP/hq.req"; REACHED=1; }
}
kt_test_start "empty keys do not abort: ?=x, ?&&, ?=, ?a=1&=2, ?&=&"
bad=""
for q in "=x" "&&" "=" "a=1&=2" "&=&" "%3D=1"; do
    hostile_q "$q"
    [[ "$REACHED" == "1" && "$P_ST" == "0" ]] || bad+=" [$q]=reached:$REACHED,st:$P_ST"
done
hostile_q "a=1&=2"; get R QueryField a; [[ "$G" == "1" ]] || bad+=" a='$G'"
hostile_q "%3D=1"; get R QueryField "="; [[ "$G" == "1" ]] || bad+=" '='='$G'"
if [[ -z "$bad" ]]; then kt_test_pass "6 queries parsed, marker reached each time"; else kt_test_fail "$bad"; fi

kt_test_start "hostile query names and values round-trip as data; nothing executes"
bad=""
hostile_q '%24(touch%20pwn)=v1&%60touch%20pwn%60=v2&a%5B0%5D=v3&%40=v4&*=v5&%5D=v6&x%3By=v7&k=%24(touch%20pwn)&%24%7Bx%7D=v8'
[[ "$REACHED" == "1" && "$P_ST" == "0" ]] || bad+=" parse:reached=$REACHED,st=$P_ST"
qf '$(touch pwn)' 0 v1; qf '`touch pwn`' 0 v2; qf 'a[0]' 0 v3; qf '@' 0 v4; qf '*' 0 v5
qf ']' 0 v6; qf 'x;y' 0 v7; qf k 0 '$(touch pwn)'; qf '${x}' 0 v8
if [[ -z "$bad" ]]; then kt_test_pass "9 hostile fields verbatim"; else kt_test_fail "$bad"; fi

kt_test_start "hostile header names (tokens: \$x, *) and values round-trip; GetHeader '' is rc 2"
bad=""
get R GetHeader x-v;   [[ "$G" == '$(touch pwn)`touch pwn`${IFS}' ]] || bad+=" x-v='$G'"
get R GetHeader '$x';  [[ "$G" == "dollar" ]] || bad+=" \$x='$G'"
get R GetHeader '*';   [[ "$G" == "star" ]]   || bad+=" *='$G'"
get R GetHeader '@';   [[ $GRC -eq 1 ]]       || bad+=" @=$GRC"
get R GetHeader 'a[0]'; [[ $GRC -eq 1 ]]      || bad+=" a[0]=$GRC"
if [[ -z "$bad" ]]; then kt_test_pass "values verbatim, token names usable, non-names a miss"; else kt_test_fail "$bad"; fi

kt_test_start "RouteParam / SetRouteParam: hostile keys and values round-trip; '' → rc 2 (Set does not abort)"
bad=""
fresh R
for k in '$(touch pwn)' '`id`' 'a[0]' '@' '*' ']' 'x;y'; do
    R.SetRouteParam "$k" "val:$k" || bad+=" set[$k]"
    get R RouteParam "$k"; [[ $GRC -eq 0 && "$G" == "val:$k" ]] || bad+=" get[$k]=$GRC:'$G'"
done
REACHED=0; { src=0; R.SetRouteParam "" x || src=$?; REACHED=1; }
[[ "$REACHED" == "1" && "$src" == "2" ]] || bad+=" set''=$src,reached=$REACHED"
get R RouteParam "";   [[ $GRC -eq 2 ]] || bad+=" get''=$GRC"
get R RouteParam none; [[ $GRC -eq 1 && -z "$G" ]] || bad+=" none=$GRC:'$G'"
if [[ -z "$bad" ]]; then kt_test_pass "7 hostile keys, '' refused, miss rc 1"; else kt_test_fail "$bad"; fi

kt_test_start "the pwn marker was never created"
if [[ ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" ]]; then kt_test_pass "no pwn"; else kt_test_fail "pwn exists"; fi
cd "$SCRIPT_DIR" || exit 1

# ===========================================================================
kt_test_section "5. read-only request fields from inside a handler-like member (fact 19)"
# ===========================================================================

class THsProbe001
    public
        constructor Create
        proc Handle
end
THsProbe001.Create() { :; }
THsProbe001.Handle() {
    local req="$1" wrc=0
    RESULT=stale; $req.Method;          HP_M="$RESULT"
    RESULT=stale; $req.Content;         HP_C="$RESULT"
    RESULT=stale; $req.URI;             HP_U="$RESULT"
    RESULT=stale; $req.ContentLength;   HP_L="$RESULT"
    RESULT=stale; $req.GetHeader host;  HP_H="$RESULT"
    $req.Method = HACKED || wrc=$?
    HP_WRC="$wrc"
    RESULT=stale; $req.Method;          HP_M2="$RESULT"
    wrc=0; $req.Content = HACKED || wrc=$?
    HP_WRC2="$wrc"
    RESULT=stale; $req.Content;         HP_C2="$RESULT"
}
build THsProbe001

mk ro.req "POST /ro HTTP/1.1${CRLF}Host: hh${CRLF}Content-Length: 5${CRLF}${CRLF}hello"
parse "$TMP/ro.req"
THsProbe001.new HP
HP.Handle R >"$TMP/hp.out" 2>"$TMP/hp.err"
hpout="$(<"$TMP/hp.out")"; hperr="$(<"$TMP/hp.err")"

kt_test_start "\$req.Method / Content / URI / ContentLength / GetHeader print NOTHING and set RESULT"
if [[ -z "$hpout" && "$HP_M" == "POST" && "$HP_C" == "hello" && "$HP_U" == "/ro" && "$HP_L" == "5" && "$HP_H" == "hh" ]]; then
    kt_test_pass "stdout empty; POST hello /ro 5 hh"
else
    kt_test_fail "stdout='${hpout:0:80}' M='$HP_M' C='$HP_C' U='$HP_U' L='$HP_L' H='$HP_H'"
fi

kt_test_start "\$req.Method = X and \$req.Content = X are rc 1; the values are unchanged"
if [[ "$HP_WRC" == "1" && "$HP_M2" == "POST" && "$HP_WRC2" == "1" && "$HP_C2" == "hello" ]]; then
    kt_test_pass "rc 1, rc 1; POST, hello"
else
    kt_test_fail "wrc=$HP_WRC M2='$HP_M2' wrc2=$HP_WRC2 C2='$HP_C2'"
fi

kt_test_start "the only stderr is kklass's own read-only line, once per write (deviation e)"
exp="Error: Property 'Method' is read-only"$'\n'"Error: Property 'Content' is read-only"
if [[ "$hperr" == "$exp" ]]; then kt_test_pass "two kklass lines"; else kt_test_fail "stderr='$hperr'"; fi
HP.delete

# ===========================================================================
kt_test_section "6. the transport seam: abstract base, TReplayTransport"
# ===========================================================================

kt_test_start "THttpTransport is abstract: .new is rc 1"
rc=0; THttpTransport.new AB 2>"$TMP/ab.err" || rc=$?
if [[ $rc -eq 1 && -z "$(declare -p AB_class 2>/dev/null)" ]]; then kt_test_pass "rc 1, no instance"; else kt_test_fail "rc=$rc"; fi

kt_test_start "TReplayTransport derives from THttpTransport and is concrete"
if kk._class_derives_from TReplayTransport THttpTransport && [[ "${TReplayTransport_class_abstract:-0}" != "1" ]]; then
    kt_test_pass "derives, not abstract"
else
    kt_test_fail "derives/abstract wrong"
fi

TReplayTransport.new T
kt_test_start "fresh transport: InFd/OutFd/FirstLine/RemoteAddress/LastError '' and TimedOut 0"
bad=""
for p in InFd OutFd FirstLine RemoteAddress LastError; do get T "$p"; [[ $GRC -eq 0 && -z "$G" ]] || bad+=" $p=$GRC:'$G'"; done
get T TimedOut; [[ "$G" == "0" ]] || bad+=" TimedOut='$G'"
if [[ -z "$bad" ]]; then kt_test_pass "all empty, TimedOut 0"; else kt_test_fail "$bad"; fi

kt_test_start "AddRequestFile: '' → rc 2; a missing file → rc 1"
r1=0; T.AddRequestFile "" || r1=$?
r2=0; T.AddRequestFile "$TMP/does-not-exist.req" || r2=$?
if [[ "$r1$r2" == "21" ]]; then kt_test_pass "2, 1"; else kt_test_fail "rc $r1 $r2"; fi

kt_test_start "Accept with no request file → rc 2 at once, LastError set"
get T Accept 0 10; a="$GRC"; get T LastError
if [[ "$a" == "2" && -n "$G" ]]; then kt_test_pass "rc 2 '$G'"; else kt_test_fail "rc=$a LastError='$G'"; fi

mk r1.req "first request"; mk r2.req "second request"
T.AddRequestFile "$TMP/r1.req"; T.AddRequestFile "$TMP/r2.req"
fdcount() { local f=(/proc/$BASHPID/fd/*); FDN=${#f[@]}; }
fdcount; fd0=$FDN

kt_test_start "Accept #1: rc 0, InFd reads request 1, OutFd writes to ResponseFile 0; FirstLine '' TimedOut 0"
get T Accept 0 10; a="$GRC"
T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"; get T FirstLine; fl="$G"; get T TimedOut; to="$G"
IFS= read -r -u "$in" l1 || :
printf 'resp-one' >&"$out"
fdcount; fd1=$FDN
if [[ "$a" == "0" && "$l1" == "first request" && -z "$fl" && "$to" == "0" && $fd1 -eq $(( fd0 + 2 )) ]]; then
    kt_test_pass "request 1 in, two fds open"
else
    kt_test_fail "rc=$a line='$l1' fl='$fl' to='$to' fds $fd0→$fd1"
fi

kt_test_start "Accept #2 without CloseConnection closes the previous pair first (fd count stays +2)"
get T Accept 0 10; a="$GRC"
T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"
IFS= read -r -u "$in" l2 || :
printf 'resp-two' >&"$out"
fdcount; fd2=$FDN
if [[ "$a" == "0" && "$l2" == "second request" && $fd2 -eq $(( fd0 + 2 )) ]]; then kt_test_pass "request 2 in, still +2"; else kt_test_fail "rc=$a line='$l2' fds $fd0→$fd2"; fi

kt_test_start "CloseConnection: InFd/OutFd '' and the fd count is back to the start"
T.CloseConnection; crc=$?
get T InFd; i="$G"; get T OutFd; o="$G"
fdcount
if [[ $crc -eq 0 && -z "$i" && -z "$o" && $FDN -eq $fd0 ]]; then kt_test_pass "closed, $FDN fds"; else kt_test_fail "rc=$crc in='$i' out='$o' fds $fd0→$FDN"; fi

kt_test_start "ResponseFile 0 / 1 hold what was written to each OutFd; bad index → rc 1"
get T ResponseFile 0; p0="$G"; get T ResponseFile 1; p1="$G"
c0=""; c1=""; [[ -f "$p0" ]] && c0="$(<"$p0")"; [[ -f "$p1" ]] && c1="$(<"$p1")"
get T ResponseFile 2; b1="$GRC:$G"; get T ResponseFile abc; b2="$GRC:$G"; get T ResponseFile -1; b3="$GRC:$G"
if [[ "$c0" == "resp-one" && "$c1" == "resp-two" && "$p0" != "$p1" && "$b1" == "1:" && "$b2" == "1:" && "$b3" == "1:" ]]; then
    kt_test_pass "two capture files, three misses"
else
    kt_test_fail "c0='$c0' c1='$c1' p0='$p0' p1='$p1' misses $b1 $b2 $b3"
fi

kt_test_start "Accept after the last file: rc 2; Shutdown then delete free the per-instance arrays"
get T Accept 0 10; a="$GRC"
T.Shutdown; s=$?
T.delete
left="$(declare -p T_rqf T_rsf T_data 2>/dev/null)"
if [[ "$a" == "2" && $s -eq 0 && -z "$left" ]]; then kt_test_pass "rc 2; nothing left"; else kt_test_fail "accept=$a shutdown=$s left='${left:0:120}'"; fi

kt_test_start "THttpRequest.delete frees _hdr/_hdrn/_qf/_rp; a new instance with the same name starts empty"
parse "$TMP/good.req"; R.SetRouteParam id 7
before=0; for a in R_hdr R_hdrn R_qf R_rp; do declare -p "$a" >/dev/null 2>&1 && before=$(( before + 1 )); done
R.delete
left="$(declare -p R_hdr R_hdrn R_qf R_rp 2>/dev/null)"
THttpRequest.new R
get R GetHeader host; a="$GRC"; get R RouteParam id; b="$GRC"; get R QueryField x; c="$GRC"; get R Method; m="$G"
if [[ $before -eq 4 && -z "$left" && "$a$b$c" == "111" && -z "$m" ]]; then kt_test_pass "4 arrays existed, freed; clean instance"; else kt_test_fail "before=$before left='${left:0:120}' rc $a$b$c Method='$m'"; fi
R.delete

# ===========================================================================
kt_test_section "7. fork-free proof of the replay pipeline (fact 23, PLAN §4)"
# ===========================================================================

mk ff.req "POST /ff?q=%41b HTTP/1.1${CRLF}Host: h${CRLF}X-A: 1${CRLF}Content-Length: 3${CRLF}${CRLF}xyz"

# pipeline FILE — accept → parse → answer → send → close → free, all direct calls.
pipeline() {
    local in out st
    TReplayTransport.new FT
    FT.AddRequestFile "$1"
    FT.Accept 0 10 || return 11
    FT.InFd; in="$RESULT"; FT.OutFd; out="$RESULT"
    THttpRequest.new FR; THttpResponse.new FS
    FS.Attach "$out" 0 || return 12
    FR.ReadFrom "$in" "$DL" 65536 || return 13
    st="$RESULT"
    [[ "$st" == "0" ]] || return 14
    FR.Method;          FS.Write "m=$RESULT"
    FR.QueryField q;    FS.Write " q=$RESULT"
    FR.GetHeader x-a;   FS.Write " x=$RESULT"
    FR.Content;         FS.Write " c=$RESULT"
    FR.ContentLength;   FS.Write " n=$RESULT"
    FS.SetCustomHeader X-Out yes || return 15
    FS.SendContent || return 16
    FT.CloseConnection
    FR.delete; FS.delete
    FT.ResponseFile 0; PIPE_OUT="$RESULT"
    FT.delete
    return 0
}
expect_body="m=POST q=Ab x=1 c=xyz n=3"

kt_test_start "(a) \$BASHPID is unchanged across the whole pipeline"
p0=$BASHPID; deadline 10000000
prc=0; pipeline "$TMP/ff.req" || prc=$?
body=""; [[ -f "$PIPE_OUT" ]] && body="$(<"$PIPE_OUT")"
if [[ $prc -eq 0 && $BASHPID == "$p0" && "$body" == *$'\r\n\r\n'"$expect_body" ]]; then kt_test_pass "BASHPID $p0, response correct"; else kt_test_fail "rc=$prc pid $p0→$BASHPID body='${body: -60}'"; fi

kt_test_start "(b) the pipeline works with PATH='' (no external command anywhere on it)"
nopath() { local PATH=''; pipeline "$1"; }
deadline 10000000; rm -f "$PIPE_OUT"
prc=0; nopath "$TMP/ff.req" 2>"$TMP/nopath.err" || prc=$?
body=""; [[ -f "$PIPE_OUT" ]] && body="$(<"$PIPE_OUT")"
nperr="$(<"$TMP/nopath.err")"
if [[ $prc -eq 0 && -z "$nperr" && "$body" == *$'\r\n\r\n'"$expect_body" && "$body" == *$'\r\nX-Out: yes\r\n'* ]]; then
    kt_test_pass "rc 0, silent, full response"
else
    kt_test_fail "rc=$prc stderr='${nperr:0:120}' body='${body: -60}'"
fi

kt_test_start "(c) no stored member body of the four classes contains \$( , a backtick or a pipe"
bad=""; nb=0
for C in THttpRequest THttpResponse THttpTransport TReplayTransport; do
    declare -n __ml="${C}_decl_methods"
    for m in "${__ml[@]}" __ctor__; do
        if [[ "$m" == "__ctor__" ]]; then v="${C}_constructor_body"; else v="${C}_method_body_${m}"; fi
        [[ -n "${!v+x}" ]] || continue          # abstract: no body
        b="${!v}"; nb=$(( nb + 1 ))
        probe="${b//'$(('/}"; probe="${probe//'||'/}"
        [[ "$probe" == *'$('* || "$probe" == *'`'* || "$probe" == *'|'* ]] && bad+=" $C.$m"
    done
    unset -n __ml
done
if [[ -z "$bad" && $nb -ge 20 ]]; then kt_test_pass "$nb bodies clean"; else kt_test_fail "bodies=$nb forking:$bad"; fi

kt_test_start "(d) a DEBUG-trap canary (set -T) sees NO subshell during the pipeline — and does see one in a control run"
CANARY="$TMP/fork.canary"; rm -f "$CANARY"
deadline 10000000
set -T
trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
prc=0; pipeline "$TMP/ff.req" || prc=$?
trap - DEBUG
set +T
seen=0; [[ -e "$CANARY" ]] && seen=1
rm -f "$CANARY"
set -T; trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
ctl="$(printf x)"
trap - DEBUG; set +T
ctlseen=0; [[ -e "$CANARY" ]] && ctlseen=1
rm -f "$CANARY"
if [[ $prc -eq 0 && $seen -eq 0 && $ctlseen -eq 1 ]]; then kt_test_pass "pipeline: no subshell; control: detected"; else kt_test_fail "rc=$prc pipeline-seen=$seen control-seen=$ctlseen"; fi

