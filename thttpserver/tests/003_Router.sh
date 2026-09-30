#!/bin/bash
# 003_Router.sh — thttpserver P1: THttpRouteObject and THttpRouter (PLAN §1.3,
# §2.4, §2.11; §3 facts 16 (router half), 17, 20, 21).
#
# Every request is REAL: a raw request file goes through TReplayTransport and
# THttpRequest.ReadFrom, the response is attached to the capture fd, and the
# router works on those instances. The router never sends; where the wire form
# matters (404/405 + Allow, HEAD), the test sends and reads the capture.
#
# Handlers run in THIS shell (the router calls them directly), so the globals
# they set are visible here. Stdin is closed for the whole file; the working
# directory is the fixture dir, so a hostile `$(:>pwn)` that ever executed
# would leave `pwn` right there.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/thttpserver.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
cd "$TMP" || exit 1
unset -v HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy

# ===========================================================================
# THE PATTERN TABLE (PLAN §2.4). Section 1 PARSES this block and runs every
# row, so the table below is exactly what is tested. PARAMS lists every route
# parameter the match must capture — no more, no fewer ('-' = none). It becomes
# the README table in P3.
#
# PATTERN-TABLE-BEGIN
# | pattern                | path                   | match | params                  |
# |------------------------|------------------------|-------|-------------------------|
# | /                      | /                      | yes   | -                       |
# | /                      | /a                     | no    | -                       |
# | /hello                 | /hello                 | yes   | -                       |
# | hello                  | /hello                 | yes   | -                       |
# | /hello                 | /Hello                 | no    | -                       |
# | /Hello                 | /hello                 | no    | -                       |
# | /hello                 | /hello/                | no    | -                       |
# | /hello/                | /hello/                | yes   | -                       |
# | /hello/                | /hello                 | no    | -                       |
# | /a/b                   | /a/b/c                 | no    | -                       |
# | /a/b/c                 | /a/b                   | no    | -                       |
# | /a/b                   | /a/bc                  | no    | -                       |
# | /users/:id             | /users/42              | yes   | id=42                   |
# | users/:id              | /users/42              | yes   | id=42                   |
# | /users/:id             | /users/                | no    | -                       |
# | /users/:id             | /users                 | no    | -                       |
# | /users/:id             | /users/42/x            | no    | -                       |
# | /users/:id/posts/:pid  | /users/7/posts/9       | yes   | id=7 pid=9              |
# | /:a/:b                 | /x/y                   | yes   | a=x b=y                 |
# | /u/:                   | /u/anything            | yes   | -                       |
# | /files/*path           | /files/a/b/c.txt       | yes   | path=a/b/c.txt          |
# | /files/*path           | /files/                | yes   | path=                   |
# | /files/*path           | /files                 | no    | -                       |
# | /files/*path           | /filesx/a              | no    | -                       |
# | /files/*path           | /Files/a               | no    | -                       |
# | /*all                  | /                      | yes   | all=                    |
# | /*all                  | /x/y/                  | yes   | all=x/y/                |
# | /*                     | /any/thing             | yes   | -                       |
# | /u/:id/*rest           | /u/5/a/b               | yes   | id=5 rest=a/b           |
# | /u/:id/*rest           | /u/5                   | no    | -                       |
# | /a%20b                 | /a%20b                 | yes   | -                       |
# | /a b                   | /a%20b                 | no    | -                       |
# | /v/:x                  | /v/%24%28id%29         | yes   | x=$(id)                 |
# | /v/:x                  | /v/a%2Fb               | yes   | x=a/b                   |
# | /v/:x                  | /v/a+b%2B%41%G1%4      | yes   | x=a+b+A%G1%4            |
# | /files/*path           | /files/a%2Fb/c%2F      | yes   | path=a/b/c/             |
# | /v/:x                  | /v/$(:>pwn)            | yes   | x=$(:>pwn)              |
# | /v/:x                  | /v/`:>pwn`             | yes   | x=`:>pwn`               |
# | /v/:x                  | /v/${IFS}a[0]          | yes   | x=${IFS}a[0]            |
# | /v/*r                  | /v/;:>pwn;/&&/*        | yes   | r=;:>pwn;/&&/*          |
# PATTERN-TABLE-END
#
# Reading the table: constant segments compare case-sensitively and literally
# (PathInfo is NOT percent-decoded); a trailing `/` is significant; the leading
# `/` of a pattern is optional; `:name` takes exactly one NON-EMPTY segment
# (bare `:` matches one without capturing); a trailing `*name` takes the rest
# of the path after the `/` before it, `/` included, possibly empty (bare `*`
# captures nothing); a `*` anywhere else is refused at registration (§2).
#
# Matching runs on the RAW PathInfo, so an encoded `%2F` never splits a
# segment (`/v/a%2Fb` is one `:x` segment). Each CAPTURED value is then
# percent-decoded with PATH rules before the handler sees it (review R1):
# `%XX` → the byte, `+` stays a literal `+` (not form data), an invalid `%G1`
# or a truncated `%4` stays literal, a received backslash is data; a `*rest`
# capture is decoded as a whole (`%2F` → `/` there); `%00` in any captured
# value → 400, the handler is not run (§9).
# ===========================================================================

# drop INST — delete INST if it is a live instance.
drop() { if declare -p "${1}_class" >/dev/null 2>&1; then "$1".delete; fi; }

# req METHOD TARGET — a REAL request: a raw HTTP/1.1 file, TReplayTransport
# Accept, THttpRequest.ReadFrom into Q, THttpResponse S attached to the capture
# fd (ISHEAD for HEAD). rc 0 only if the parse status is 0.
NREQ=0
req() {
    local m="$1" t="$2" f in out dl hd=0
    NREQ=$(( NREQ + 1 ))
    f="$TMP/r$NREQ.req"
    printf '%s %s HTTP/1.1\r\nHost: t\r\n\r\n' "$m" "$t" > "$f"
    drop Q; drop S; drop RT
    TReplayTransport.new RT
    RT.AddRequestFile "$f" || return 91
    RT.Accept 0 10 || return 92
    RT.InFd; in="$RESULT"; RT.OutFd; out="$RESULT"
    THttpRequest.new Q; THttpResponse.new S
    dl=$(( ${EPOCHREALTIME//[!0-9]/} + 10000000 ))
    Q.ReadFrom "$in" "$dl" 65536 || return 93
    [[ "$RESULT" == "0" ]] || return 94
    [[ "$m" == HEAD ]] && hd=1
    S.Attach "$out" "$hd" || return 95
    return 0
}

# route ROUTER METHOD TARGET — req + ROUTER.RouteRequest Q S with stdout and
# stderr captured: RR = rc, RO / RE = what it printed, CODE = S.Code,
# ALLOW = the Allow header ('' if none), SENT = S.ContentSent.
route() {
    local r="$1"
    RR=0; RO=""; RE=""; CODE=""; ALLOW=""; SENT=""
    if ! req "$2" "$3"; then RR=99; return 0; fi
    "$r".RouteRequest Q S >"$TMP/route.out" 2>"$TMP/route.err" || RR=$?
    RO="$(<"$TMP/route.out")"; RE="$(<"$TMP/route.err")"
    S.Code; CODE="$RESULT"
    if S.GetCustomHeader Allow; then ALLOW="$RESULT"; fi
    S.ContentSent; SENT="$RESULT"
    return 0
}

# send — S.SendContent, close, CAP = the captured response bytes, STATUS = its
# status line (CR stripped).
send() {
    local f
    S.SendContent
    RT.CloseConnection
    RT.ResponseFile 0; f="$RESULT"
    CAP=""; [[ -f "$f" ]] && IFS= read -r -d "" CAP < "$f"
    STATUS="${CAP%%$'\r'*}"
}

# reg ROUTER ARGS... — ROUTER.RegisterRoute with stdout+stderr captured:
# GRC = rc, GO = everything printed.
reg() {
    local r="$1"; shift
    GRC=0
    "$r".RegisterRoute "$@" >"$TMP/reg.out" 2>&1 || GRC=$?
    GO="$(<"$TMP/reg.out")"
}

# count ROUTER — RC_N = RouteCount.
count() { RESULT=stale; "$1".RouteCount; RC_N="$RESULT"; }

# ---- handlers (all run in this shell) --------------------------------------
LOG=()
hOk()       { "$2".Write ok; }
hA()        { LOG+=("A:$#:$1:$2:${3-UNSET}"); "$2".Write A; }
hB()        { LOG+=("B:$#:$1:$2:${3-UNSET}"); "$2".Write B; }
hG()        { LOG+=("G"); "$2".Write "get-body"; }
hH()        { LOG+=("H"); "$2".Write "head-body"; }
hDefGet()   { LOG+=("defGET"); }
hDefAll()   { LOG+=("defALL"); }
hDefPut()   { LOG+=("defPUT"); }
hFail()     { LOG+=("fail"); "$2".Code = 418; return 7; }
hBefore()   { LOG+=("before:$#:$1:$2"); }
hAfter()    { LOG+=("after:$#:$1:$2"); }
hAfter2()   { LOG+=("after2"); }
hBeforeRc() { LOG+=("before-rc"); return 5; }
hAfterRc()  { LOG+=("after-rc"); return 6; }
hBeforeSend() { LOG+=("before-send"); "$2".Code = 401; "$2".SendContent; }
hData()     { DATA_SEEN="$3"; DATA_N=$#; }

kt_test_section "003: THttpRouteObject and THttpRouter (P1)"

# ===========================================================================
kt_test_section "1. the pattern table (PLAN §2.4), parsed from this file's comment block"
# ===========================================================================

ROWS=()
inblock=0
while IFS= read -r line; do
    if [[ "$line" == "# PATTERN-TABLE-BEGIN" ]]; then inblock=1; continue; fi
    if [[ "$line" == "# PATTERN-TABLE-END" ]]; then break; fi
    (( inblock )) || continue
    [[ "$line" == "# | pattern "* || "$line" == "# |--"* ]] && continue
    ROWS+=("$line")
done < "$SCRIPT_DIR/003_Router.sh"

trim() { local s="$1"; s="${s#"${s%%[! ]*}"}"; s="${s%"${s##*[! ]}"}"; T="$s"; }

kt_test_start "the table block parses: at least 35 rows, four cells each"
badrows=0
for line in "${ROWS[@]}"; do
    body="${line#\# |}"; body="${body%|}"
    IFS='|' read -r -a cells <<< "$body"
    [[ ${#cells[@]} -eq 4 ]] || badrows=$(( badrows + 1 ))
done
if [[ ${#ROWS[@]} -ge 35 && $badrows -eq 0 ]]; then kt_test_pass "${#ROWS[@]} rows"; else kt_test_fail "rows=${#ROWS[@]} malformed=$badrows"; fi

for line in "${ROWS[@]}"; do
    body="${line#\# |}"; body="${body%|}"
    IFS='|' read -r -a cells <<< "$body"
    trim "${cells[0]}"; pat="$T"; trim "${cells[1]}"; path="$T"
    trim "${cells[2]}"; want="$T"; trim "${cells[3]}"; params="$T"
    kt_test_start "pattern '$pat' vs path '$path' → $want${params:+ ($params)}"
    drop PT; THttpRouter.new PT
    reg PT "$pat" GET hOk
    if [[ $GRC -ne 0 ]]; then kt_test_fail "RegisterRoute '$pat' rc=$GRC '$GO'"; continue; fi
    route PT GET "$path"
    bad=""
    [[ $RR -eq 0 && -z "$RO$RE" ]] || bad+=" rr=$RR out='$RO' err='$RE'"
    if [[ "$want" == yes ]]; then
        [[ "$CODE" == 200 ]] || bad+=" code=$CODE"
        S.Content; [[ "$RESULT" == ok ]] || bad+=" handler-not-run"
    else
        [[ "$CODE" == 404 ]] || bad+=" code=$CODE (want 404)"
    fi
    declare -n __rp=Q_rp
    nwant=0
    if [[ "$params" != "-" ]]; then
        read -r -a kv <<< "$params"
        for p in "${kv[@]}"; do
            nwant=$(( nwant + 1 ))
            k="${p%%=*}"; v="${p#*=}"
            RESULT=stale; prc=0; Q.RouteParam "$k" || prc=$?
            [[ $prc -eq 0 && "$RESULT" == "$v" ]] || bad+=" $k: rc=$prc '$RESULT' (want '$v')"
        done
    fi
    [[ ${#__rp[@]} -eq $nwant ]] || bad+=" params captured=${#__rp[@]} (want $nwant)"
    unset -n __rp
    if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi
done
drop PT

# ===========================================================================
kt_test_section "2. RegisterRoute: the argument rule (PLAN §2.4, D7)"
# ===========================================================================

THttpRouter.new AR

kt_test_start "a fresh router: RouteCount 0, read silently into RESULT"
RESULT=stale; AR.RouteCount >"$TMP/rc.out" 2>&1; o="$(<"$TMP/rc.out")"
if [[ "$RESULT" == "0" && -z "$o" ]]; then kt_test_pass "0, silent"; else kt_test_fail "RESULT='$RESULT' printed='$o'"; fi

kt_test_start "2 arguments = PATTERN HANDLER, METHOD ALL: GET, POST, DELETE, HEAD, PATCH all reach it"
drop R2; THttpRouter.new R2; reg R2 /any hA
bad=""; [[ $GRC -eq 0 ]] || bad+=" reg=$GRC"
for m in GET POST DELETE HEAD PATCH; do
    LOG=(); route R2 "$m" /any
    [[ $RR -eq 0 && "$CODE" == 200 && "${LOG[0]:-}" == "A:3:Q:S:" ]] || bad+=" $m:rr=$RR code=$CODE log=${LOG[*]}"
done
if [[ -z "$bad" ]]; then kt_test_pass "five methods, handler got Q S ''"; else kt_test_fail "$bad"; fi

kt_test_start "≥ 3 arguments: the 2nd is ALWAYS METHOD — '/x hA 0' is rc 2 (hA is not a method), nothing registered"
count AR; n0="$RC_N"
reg AR /x hA 0; a="$GRC:$GO"
reg AR /x hA GET; b="$GRC:$GO"
count AR
if [[ "$a" == "2:" && "$b" == "2:" && "$RC_N" == "$n0" ]]; then kt_test_pass "rc 2 twice, silent, count $RC_N"; else kt_test_fail "'$a' '$b' count $n0→$RC_N"; fi

kt_test_start "METHOD must be one of GET POST PUT DELETE OPTIONS HEAD TRACE PATCH ALL, exactly (rc 2 otherwise)"
bad=""
for m in get Get FOO "GET POST" " GET" "GET " "" ANY '$(:>pwn)' 'G*'; do
    reg AR /x "$m" hA; [[ "$GRC:$GO" == "2:" ]] || bad+=" '$m'=$GRC"
done
for m in GET POST PUT DELETE OPTIONS HEAD TRACE PATCH ALL; do
    reg AR "/m/$m" "$m" hA; [[ "$GRC:$GO" == "0:" ]] || bad+=" $m=$GRC:'$GO'"
done
count AR
if [[ -z "$bad" && "$RC_N" == "9" ]]; then kt_test_pass "11 refused, 9 accepted"; else kt_test_fail "$bad count=$RC_N"; fi

kt_test_start "ISDEFAULT must be 0 or 1 (rc 2 for '', 2, yes, true, ' 1')"
bad=""
for d in "" 2 yes true " 1" 01; do reg AR /d GET hA "$d"; [[ "$GRC:$GO" == "2:" ]] || bad+=" '$d'=$GRC"; done
reg AR /d0 GET hA 0; [[ "$GRC" == 0 ]] || bad+=" 0=$GRC"
count AR
if [[ -z "$bad" && "$RC_N" == "10" ]]; then kt_test_pass "six refused, 0 accepted"; else kt_test_fail "$bad count=$RC_N"; fi

kt_test_start "fewer than 2 or more than 5 arguments → rc 2"
bad=""
reg AR; [[ "$GRC:$GO" == "2:" ]] || bad+=" 0args=$GRC"
reg AR /only; [[ "$GRC:$GO" == "2:" ]] || bad+=" 1arg=$GRC"
reg AR /six GET hA 0 data extra; [[ "$GRC:$GO" == "2:" ]] || bad+=" 6args=$GRC"
count AR
if [[ -z "$bad" && "$RC_N" == "10" ]]; then kt_test_pass "three refused"; else kt_test_fail "$bad count=$RC_N"; fi

kt_test_start "HANDLER must match ^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)?\$ (rc 2, nothing run)"
bad=""
for h in "" "a b" '$(:>pwn)' '`:>pwn`' a.b.c 1abc .x x. a-b 'hA;hB' 'hA hB' 'a[0]' '*' 'hA.' '.'; do
    reg AR /h GET "$h"; [[ "$GRC:$GO" == "2:" ]] || bad+=" '$h'=$GRC"
done
count AR
if [[ -z "$bad" && "$RC_N" == "10" && ! -e pwn ]]; then kt_test_pass "15 refused"; else kt_test_fail "$bad count=$RC_N"; fi

kt_test_start "a HANDLER that is no function, no route class and no INST.METHOD → rc 2"
bad=""
for h in noSuchFunction003 NoInst.Method THttpRequest THttpRouter THttpRouteObject; do
    reg AR /h GET "$h"; [[ "$GRC:$GO" == "2:" ]] || bad+=" '$h'=$GRC:'$GO'"
done
if [[ -z "$bad" ]]; then kt_test_pass "five refused"; else kt_test_fail "$bad"; fi

kt_test_start "a '*' that is not the start of the LAST segment → rc 2"
bad=""
for p in '/a/*r/b' '/a*' '/**' '/*a/b' '/x/a*b' '*/x' '/a/*b*'; do
    reg AR "$p" GET hA; [[ "$GRC:$GO" == "2:" ]] || bad+=" '$p'=$GRC"
done
count AR
if [[ -z "$bad" && "$RC_N" == "10" ]]; then kt_test_pass "seven refused"; else kt_test_fail "$bad count=$RC_N"; fi

kt_test_start "DATA (5th argument) is accepted as anything; RouteCount counts every accepted route"
reg AR /data GET hA 0 'any $(:>pwn) data'; a="$GRC"
reg AR /data2 GET hA 1 ''; b="$GRC"
count AR
if [[ "$a$b" == "00" && "$RC_N" == "12" && ! -e pwn ]]; then kt_test_pass "12 routes"; else kt_test_fail "rc $a$b count=$RC_N"; fi

kt_test_start "RouteCount is read-only (a write is rc 1, the count unchanged)"
wrc=0; AR.RouteCount = 99 2>/dev/null || wrc=$?
count AR
if [[ $wrc -eq 1 && "$RC_N" == "12" ]]; then kt_test_pass "rc 1, 12"; else kt_test_fail "rc=$wrc count=$RC_N"; fi

kt_test_start "the route table lives in _pat _met _hnd _kind _def _rdat; kklass's _data holds only the declared properties"
bad=""
for s in _pat _met _hnd _kind _def _rdat; do
    declare -n __a="AR$s"; [[ ${#__a[@]} -eq 12 ]] || bad+=" AR$s=${#__a[@]}"; unset -n __a
done
for k in "${!AR_data[@]}"; do [[ " BeforeRequest AfterRequest RouteCount " == *" $k "* ]] || bad+=" data-key:'$k'"; done
declare -n __r=AR_rdat
[[ "${__r[10]}" == 'any $(:>pwn) data' && "${__r[11]}" == '' ]] || bad+=" rdat='${__r[10]}'/'${__r[11]}'"
unset -n __r
if [[ -z "$bad" ]]; then kt_test_pass "six arrays of 12; _data clean; DATA verbatim"; else kt_test_fail "$bad"; fi

kt_test_start "Destroy frees all six arrays; a new router under the same name starts empty"
AR.delete
left="$(declare -p AR_pat AR_met AR_hnd AR_kind AR_def AR_rdat AR_data 2>/dev/null)"
THttpRouter.new AR; count AR
if [[ -z "$left" && "$RC_N" == "0" ]]; then kt_test_pass "freed; RouteCount 0"; else kt_test_fail "left='${left:0:160}' count=$RC_N"; fi
AR.delete

# ===========================================================================
kt_test_section "3. the three handler kinds, resolved once at registration (fact 17)"
# ===========================================================================

class THsCounter003
    public
        var Label
        property Total read GetTotal
        constructor Create
        func GetTotal
        proc Next
    private
        var _n
end
THsCounter003.Create() { Label=counter; _n=0; }
THsCounter003.GetTotal() { kk._return "$_n"; }
THsCounter003.Next() {
    local req="$1" resp="$2"
    _n=$(( _n + 1 ))
    CTR_ARGS="$#:$1:$2:${3-UNSET}"
    $resp.Write "n=$_n"
}
build THsCounter003

HELLO_CTOR=0; HELLO_DTOR=0
class THsHello003 : THttpRouteObject
    public
        constructor Create
        destructor  Destroy
        override proc HandleRequest
end
THsHello003.Create() { inherited; HELLO_CTOR=$(( HELLO_CTOR + 1 )); HELLO_SELF="$__inst__"; }
THsHello003.Destroy() { HELLO_DTOR=$(( HELLO_DTOR + 1 )); inherited; }
THsHello003.HandleRequest() {
    local req="$1" resp="$2" name=""
    HELLO_ARGS="$#:$1:$2"
    HELLO_DATA="$RouteData"
    if $req.RouteParam name; then name="$RESULT"; fi
    $resp.Write "hello $name"
    return "${HELLO_RC:-0}"
}
build THsHello003

NOH_CTOR=0
class THsNoHandler003 : THttpRouteObject
    public
        constructor Create
end
THsNoHandler003.Create() { NOH_CTOR=$(( NOH_CTOR + 1 )); }
build THsNoHandler003

class THsForgot003 : THttpRouteObject
    public
        proc HandleRequest
end
THsForgot003.HandleRequest() { $2.Write forgot-ok; }
build THsForgot003

BADCTOR_RUN=0
class THsBadCtor003 : THttpRouteObject
    public
        constructor Create
        override proc HandleRequest
end
THsBadCtor003.Create() { inherited; false; }
THsBadCtor003.HandleRequest() { BADCTOR_RUN=1; }
build THsBadCtor003

THsCounter003.new Ctr
THttpRouter.new K

kt_test_start "a function: called FN REQ RESP DATA — exactly three arguments, DATA '' when none was given"
reg K /fn GET hA; a="$GRC"
LOG=(); route K GET /fn
if [[ "$a" == 0 && $RR -eq 0 && "${LOG[*]}" == "A:3:Q:S:" && "$CODE" == 200 ]]; then kt_test_pass "hA Q S ''"; else kt_test_fail "reg=$a rr=$RR log=${LOG[*]} code=$CODE"; fi

kt_test_start "INST.METHOD: called INST.METHOD REQ RESP DATA; the object's state persists across requests"
reg K /count GET Ctr.Next 0 "cdata"; a="$GRC"
bad=""
for i in 1 2 3; do
    route K GET /count; S.Content
    [[ $RR -eq 0 && "$RESULT" == "n=$i" ]] || bad+=" #$i rr=$RR body='$RESULT'"
done
Ctr.GetTotal; t="$RESULT"
if [[ "$a" == 0 && -z "$bad" && "$t" == 3 && "$CTR_ARGS" == "3:Q:S:cdata" ]]; then kt_test_pass "n=1,2,3; args $CTR_ARGS"; else kt_test_fail "reg=$a $bad total=$t args=$CTR_ARGS"; fi

kt_test_start "INST.METHOD refused (rc 2, silent) for a property wrapper — a plain var and a computed property — and a missing method"
bad=""
for h in Ctr.Label Ctr.Total Ctr.NoSuch Ctr.delete Ctr.call Ctr.property; do
    reg K /p GET "$h"; [[ "$GRC:$GO" == "2:" ]] || bad+=" $h=$GRC:'$GO'"
done
reg K /gt GET Ctr.GetTotal; [[ "$GRC" == 0 ]] || bad+=" Ctr.GetTotal=$GRC"
if [[ -z "$bad" ]]; then kt_test_pass "six refused; the func GetTotal accepted"; else kt_test_fail "$bad"; fi

kt_test_start "INST.METHOD refused when INST is not a live instance (never created; deleted)"
THsCounter003.new Tmp
reg K /t1 GET Tmp.Next; a="$GRC"
Tmp.delete
reg K /t2 GET Tmp.Next; b="$GRC:$GO"
reg K /t3 GET Ghost003.Next; c="$GRC:$GO"
if [[ "$a" == 0 && "$b" == "2:" && "$c" == "2:" ]]; then kt_test_pass "live 0; deleted 2; never 2"; else kt_test_fail "live=$a deleted='$b' never='$c'"; fi

kt_test_start "a handler that vanished after registration (instance deleted, function unset) → rc 2 at dispatch, nothing printed"
THsCounter003.new Tmp2
reg K /gone1 GET Tmp2.Next; a="$GRC"
gone_fn003() { :; }
reg K /gone2 GET gone_fn003; b="$GRC"
Tmp2.delete; unset -f gone_fn003
route K GET /gone1; c="$RR:$RO$RE"
route K GET /gone2; d="$RR:$RO$RE"
if [[ "$a$b" == 00 && "$c" == "2:" && "$d" == "2:" ]]; then kt_test_pass "rc 2 twice, silent"; else kt_test_fail "reg $a$b; inst='$c' fn='$d'"; fi

kt_test_start "a route class: per request CLASS.new, RouteData, HandleRequest REQ RESP, delete; route params visible"
reg K /hello/:name GET THsHello003 0 "hdata"; a="$GRC"
HELLO_CTOR=0; HELLO_DTOR=0
route K GET /hello/bob; S.Content; body="$RESULT"
if [[ "$a" == 0 && $RR -eq 0 && "$body" == "hello bob" && "$HELLO_ARGS" == "2:Q:S" && "$HELLO_DATA" == hdata \
      && "$HELLO_SELF" == "__ths_route_obj" && $HELLO_CTOR -eq 1 && $HELLO_DTOR -eq 1 ]]; then
    kt_test_pass "hello bob; args $HELLO_ARGS; RouteData hdata; 1 ctor, 1 dtor"
else
    kt_test_fail "reg=$a rr=$RR body='$body' args='$HELLO_ARGS' data='$HELLO_DATA' self='$HELLO_SELF' ctor=$HELLO_CTOR dtor=$HELLO_DTOR"
fi

kt_test_start "the route object is gone after EVERY request: 3 requests → 3 constructions, 3 destructions, nothing left"
HELLO_CTOR=0; HELLO_DTOR=0; bad=""
for who in ann bob cid; do
    route K GET "/hello/$who"; S.Content; [[ "$RESULT" == "hello $who" ]] || bad+=" $who:'$RESULT'"
    declare -p __ths_route_obj_class __ths_route_obj_data >/dev/null 2>&1 && bad+=" $who:left-vars"
    declare -F __ths_route_obj.HandleRequest __ths_route_obj.RouteData __ths_route_obj.delete >/dev/null && bad+=" $who:left-fns"
done
if [[ -z "$bad" && $HELLO_CTOR -eq 3 && $HELLO_DTOR -eq 3 ]]; then kt_test_pass "3/3, clean"; else kt_test_fail "$bad ctor=$HELLO_CTOR dtor=$HELLO_DTOR"; fi

kt_test_start "a route object's non-zero rc is returned; the object is deleted all the same"
HELLO_CTOR=0; HELLO_DTOR=0; HELLO_RC=9
route K GET /hello/x; HELLO_RC=0
left=0; declare -p __ths_route_obj_class >/dev/null 2>&1 && left=1
if [[ $RR -eq 9 && $HELLO_DTOR -eq 1 && $left -eq 0 && "$SENT" == 0 ]]; then kt_test_pass "rc 9, deleted, not sent"; else kt_test_fail "rr=$RR dtor=$HELLO_DTOR left=$left sent=$SENT"; fi

kt_test_start "a stale __ths_route_obj from an aborted pass is deleted first, then the request is served"
THsHello003.new __ths_route_obj
HELLO_CTOR=0; HELLO_DTOR=0
route K GET /hello/stale; S.Content; body="$RESULT"
left=0; declare -p __ths_route_obj_class >/dev/null 2>&1 && left=1
if [[ $RR -eq 0 && "$body" == "hello stale" && $HELLO_CTOR -eq 1 && $HELLO_DTOR -eq 2 && $left -eq 0 ]]; then kt_test_pass "stale + own destroyed"; else kt_test_fail "rr=$RR body='$body' ctor=$HELLO_CTOR dtor=$HELLO_DTOR left=$left"; fi

kt_test_start "a route class whose constructor fails: its rc is returned, HandleRequest not run, no instance left"
reg K /badctor GET THsBadCtor003; a="$GRC"
BADCTOR_RUN=0
route K GET /badctor
left=0; declare -p __ths_route_obj_class >/dev/null 2>&1 && left=1
if [[ "$a" == 0 && $RR -ne 0 && $BADCTOR_RUN -eq 0 && $left -eq 0 ]]; then kt_test_pass "rc $RR, not run, clean"; else kt_test_fail "reg=$a rr=$RR run=$BADCTOR_RUN left=$left"; fi

kt_test_start "THttpRouteObject is abstract: .new is rc 1 and leaves no instance"
rc=0; THttpRouteObject.new AbsRO 2>"$TMP/abs.err" || rc=$?
if [[ $rc -eq 1 && -z "$(declare -p AbsRO_class 2>/dev/null)" && "${THttpRouteObject_class_abstract:-}" == 1 ]]; then kt_test_pass "rc 1, no instance, flag 1"; else kt_test_fail "rc=$rc flag=${THttpRouteObject_class_abstract:-}"; fi

kt_test_start "D8 (fact 21): a route class with no HandleRequest → rc 2, NOTHING printed, no constructor run"
NOH_CTOR=0; count K; n0="$RC_N"
reg K /noh GET THsNoHandler003; a="$GRC:$GO"
count K
if [[ "$a" == "2:" && $NOH_CTOR -eq 0 && "$RC_N" == "$n0" && "${THsNoHandler003_class_abstract:-}" == 1 ]]; then
    kt_test_pass "rc 2, silent, 0 constructions, not registered"
else
    kt_test_fail "'$a' ctor=$NOH_CTOR count $n0→$RC_N flag=${THsNoHandler003_class_abstract:-}"
fi

kt_test_start "D8 reads the flag, not the name: the abstract base itself → rc 2; a non-route class → rc 2"
reg K /b1 GET THttpRouteObject; a="$GRC:$GO"
reg K /b2 GET THsCounter003; b="$GRC:$GO"
if [[ "$a" == "2:" && "$b" == "2:" ]]; then kt_test_pass "both rc 2, silent"; else kt_test_fail "base='$a' plain='$b'"; fi

kt_test_start "kklass: HandleRequest redeclared WITHOUT \`override\` still implements it — the class is concrete and accepted"
reg K /forgot GET THsForgot003; a="$GRC"
route K GET /forgot; S.Content
if [[ "$a" == 0 && "${THsForgot003_class_abstract:-}" == 0 && $RR -eq 0 && "$RESULT" == forgot-ok ]]; then kt_test_pass "flag 0, served"; else kt_test_fail "reg=$a flag=${THsForgot003_class_abstract:-} rr=$RR body='$RESULT'"; fi

kt_test_start "a route class's destructor chains with a bare \`inherited\` (the empty base destructor, C9)"
HELLO_DTOR=0
route K GET /hello/chain 2>"$TMP/chain.err"
if [[ $RR -eq 0 && -z "$RE" && $HELLO_DTOR -eq 1 ]]; then kt_test_pass "no rc 127, silent"; else kt_test_fail "rr=$RR err='$RE' dtor=$HELLO_DTOR"; fi

# ===========================================================================
kt_test_section "4. matching: order, HEAD → GET, 404, 405 + Allow (facts 16, 17)"
# ===========================================================================

THttpRouter.new M
reg M /a/:x GET hA
reg M /a/b  GET hB
reg M /g    GET hG
reg M /h    GET hG
reg M /h    HEAD hH
reg M /r    POST hA
reg M /r    GET hA
reg M /r    DELETE hA
reg M /p    POST hA
reg M /hh   HEAD hH

kt_test_start "registration order: /a/:x registered before /a/b wins for /a/b"
LOG=(); route M GET /a/b
Q.RouteParam x; x="$RESULT"
if [[ $RR -eq 0 && "${LOG[0]:-}" == "A:3:Q:S:" && "$x" == b ]]; then kt_test_pass "hA, x=b"; else kt_test_fail "rr=$RR log=${LOG[*]} x='$x'"; fi

kt_test_start "…and the other way round in a router that registered /a/b first"
THttpRouter.new M2; reg M2 /a/b GET hB; reg M2 /a/:x GET hA
LOG=(); route M2 GET /a/b
if [[ $RR -eq 0 && "${LOG[0]:-}" == "B:3:Q:S:" ]]; then kt_test_pass "hB"; else kt_test_fail "rr=$RR log=${LOG[*]}"; fi
M2.delete

kt_test_start "no route matches the path → Code 404, rc 0, nothing sent, no handler run"
LOG=(); route M GET /nowhere
if [[ $RR -eq 0 && "$CODE" == 404 && "$SENT" == 0 && ${#LOG[@]} -eq 0 && -z "$ALLOW" && -z "$RO$RE" ]]; then kt_test_pass "404"; else kt_test_fail "rr=$RR code=$CODE sent=$SENT log=${LOG[*]} allow='$ALLOW'"; fi

kt_test_start "…and on the wire: HTTP/1.1 404 Not Found"
send
if [[ "$STATUS" == "HTTP/1.1 404 Not Found" ]]; then kt_test_pass "$STATUS"; else kt_test_fail "'$STATUS'"; fi

kt_test_start "the path matches, the method does not → 405, Allow in registration order with HEAD right after GET"
LOG=(); route M PUT /r
if [[ $RR -eq 0 && "$CODE" == 405 && "$ALLOW" == "POST, GET, HEAD, DELETE" && ${#LOG[@]} -eq 0 && "$SENT" == 0 ]]; then kt_test_pass "405 '$ALLOW'"; else kt_test_fail "rr=$RR code=$CODE allow='$ALLOW' log=${LOG[*]} sent=$SENT"; fi

kt_test_start "…and on the wire: HTTP/1.1 405 Method Not Allowed + Allow header"
send
if [[ "$STATUS" == "HTTP/1.1 405 Method Not Allowed" && "$CAP" == *$'\r\nAllow: POST, GET, HEAD, DELETE\r\n'* ]]; then kt_test_pass "status + Allow"; else kt_test_fail "'$STATUS' cap='${CAP:0:200}'"; fi

kt_test_start "Allow lists HEAD whenever GET is allowed (a GET-only route, POST → 'GET, HEAD')"
route M POST /g
if [[ "$CODE" == 405 && "$ALLOW" == "GET, HEAD" ]]; then kt_test_pass "'$ALLOW'"; else kt_test_fail "code=$CODE allow='$ALLOW'"; fi

kt_test_start "no GET → no implied HEAD: POST-only /p → GET and HEAD both 405 'POST'; HEAD-only /hh → GET 405 'HEAD'"
route M GET /p; a="$CODE:$ALLOW"
route M HEAD /p; b="$CODE:$ALLOW"
route M GET /hh; c="$CODE:$ALLOW"
if [[ "$a" == "405:POST" && "$b" == "405:POST" && "$c" == "405:HEAD" ]]; then kt_test_pass "$a | $b | $c"; else kt_test_fail "'$a' '$b' '$c'"; fi

kt_test_start "fact 16: HEAD on a GET-only route runs the GET handler; Code 200, no 405"
LOG=(); route M HEAD /g
if [[ $RR -eq 0 && "$CODE" == 200 && "${LOG[*]}" == "G" ]]; then kt_test_pass "GET handler"; else kt_test_fail "rr=$RR code=$CODE log=${LOG[*]}"; fi

kt_test_start "fact 16: …on the wire the GET headers (Content-Length of the GET body) and NO body"
send; head="$CAP"
route M GET /g; send; get="$CAP"
if [[ "$head" == *$'\r\nContent-Length: 8\r\n'* && "$head" == *$'\r\n\r\n' && "$head" != *get-body* \
      && "$get" == *$'\r\nContent-Length: 8\r\n'* && "$get" == *$'\r\n\r\nget-body' && "${head%%$'\r'*}" == "HTTP/1.1 200 OK" ]]; then
    kt_test_pass "HEAD: 200, Content-Length 8, no body"
else
    kt_test_fail "head='${head: -80}' get='${get: -80}'"
fi

kt_test_start "HEAD prefers a HEAD route over the GET route of the same pattern (even one registered after it)"
LOG=(); route M HEAD /h
if [[ $RR -eq 0 && "${LOG[*]}" == "H" ]]; then kt_test_pass "HEAD handler"; else kt_test_fail "log=${LOG[*]}"; fi

kt_test_start "an ALL route answers HEAD itself (it matches HEAD directly)"
THttpRouter.new M3; reg M3 /x GET hG; reg M3 /x ALL hA
LOG=(); route M3 HEAD /x
if [[ $RR -eq 0 && "${LOG[0]:-}" == "A:3:Q:S:" ]]; then kt_test_pass "ALL route"; else kt_test_fail "log=${LOG[*]}"; fi
M3.delete

kt_test_start "route params are captured into the request and visible to the handler"
THttpRouter.new M4
rp_h() { local a b; $1.RouteParam id; a="$RESULT"; $1.RouteParam rest; b="$RESULT"; RP_SEEN="$a|$b"; }
reg M4 /u/:id/*rest GET rp_h
RP_SEEN=""; route M4 GET /u/77/x/y/z
if [[ $RR -eq 0 && "$RP_SEEN" == "77|x/y/z" ]]; then kt_test_pass "$RP_SEEN"; else kt_test_fail "rr=$RR seen='$RP_SEEN'"; fi
M4.delete

kt_test_start "FindRoute PATH METHOD: RESULT = the route index; HEAD → the GET route's index"
bad=""
M.FindRoute /a/zz GET;  [[ $? -eq 0 && "$RESULT" == 0 ]] || bad+=" /a/zz='$RESULT'"
M.FindRoute /g GET;     [[ $? -eq 0 && "$RESULT" == 2 ]] || bad+=" /g='$RESULT'"
M.FindRoute /g HEAD;    [[ $? -eq 0 && "$RESULT" == 2 ]] || bad+=" HEAD/g='$RESULT'"
M.FindRoute /h HEAD;    [[ $? -eq 0 && "$RESULT" == 4 ]] || bad+=" HEAD/h='$RESULT'"
M.FindRoute /r DELETE;  [[ $? -eq 0 && "$RESULT" == 7 ]] || bad+=" DELETE/r='$RESULT'"
if [[ -z "$bad" ]]; then kt_test_pass "0 2 2 4 7"; else kt_test_fail "$bad"; fi

kt_test_start "FindRoute miss: rc 1, RESULT '', REPLY 404 or 405; a malformed call rc 2"
bad=""
rc=0; REPLY=x; M.FindRoute /none GET || rc=$?; [[ $rc -eq 1 && -z "$RESULT" && "$REPLY" == 404 ]] || bad+=" 404:$rc:'$RESULT':$REPLY"
rc=0; REPLY=x; M.FindRoute /r PUT || rc=$?;    [[ $rc -eq 1 && -z "$RESULT" && "$REPLY" == 405 ]] || bad+=" 405:$rc:'$RESULT':$REPLY"
rc=0; M.FindRoute /r || rc=$?;                 [[ $rc -eq 2 ]] || bad+=" 1arg:$rc"
rc=0; M.FindRoute /r get || rc=$?;             [[ $rc -eq 2 ]] || bad+=" lower:$rc"
rc=0; M.FindRoute /r ALL || rc=$?;             [[ $rc -eq 2 ]] || bad+=" ALL:$rc"
if [[ -z "$bad" ]]; then kt_test_pass "1/404, 1/405, three rc 2"; else kt_test_fail "$bad"; fi

# ===========================================================================
kt_test_section "5. default routes (fallback, pattern ignored, one per method)"
# ===========================================================================

THttpRouter.new D
reg D /a GET hA
reg D /ignored/get GET hDefGet 1; r1="$GRC"
reg D /ignored/all ALL hDefAll 1; r2="$GRC"
reg D /ignored/put PUT hDefPut 1; r3="$GRC"

kt_test_start "one default per method: GET, ALL and PUT defaults coexist (rc 0 each)"
if [[ "$r1$r2$r3" == "000" ]]; then kt_test_pass "three defaults"; else kt_test_fail "rc $r1$r2$r3"; fi

kt_test_start "a second default for the same method → rc 1, not registered (GET, ALL, PUT)"
count D; n0="$RC_N"; bad=""
reg D /other GET hA 1;  [[ "$GRC:$GO" == "1:" ]] || bad+=" GET=$GRC:'$GO'"
reg D /other ALL hA 1;  [[ "$GRC:$GO" == "1:" ]] || bad+=" ALL=$GRC:'$GO'"
reg D /other PUT hA 1 data;  [[ "$GRC:$GO" == "1:" ]] || bad+=" PUT=$GRC:'$GO'"
count D
if [[ -z "$bad" && "$n0" == 4 && "$RC_N" == 4 ]]; then kt_test_pass "rc 1 ×3, count $RC_N"; else kt_test_fail "$bad count $n0→$RC_N"; fi

kt_test_start "no route matches → the default route OF THE METHOD, its pattern ignored"
LOG=(); route D GET /zzz/yyy
if [[ $RR -eq 0 && "$CODE" == 200 && "${LOG[*]}" == defGET ]]; then kt_test_pass "defGET"; else kt_test_fail "rr=$RR code=$CODE log=${LOG[*]}"; fi

kt_test_start "…else the ALL default (POST has none of its own); PUT gets its own"
LOG=(); route D POST /zzz; a="${LOG[*]}"
LOG=(); route D PUT /zzz;  b="${LOG[*]}"
if [[ "$a" == defALL && "$b" == defPUT ]]; then kt_test_pass "defALL, defPUT"; else kt_test_fail "POST='$a' PUT='$b'"; fi

kt_test_start "HEAD with no match → the GET default (HEAD → GET, as for ordinary routes)"
LOG=(); route D HEAD /zzz
if [[ "${LOG[*]}" == defGET ]]; then kt_test_pass "defGET"; else kt_test_fail "log=${LOG[*]}"; fi

kt_test_start "the path matches another method's route → 405, the defaults do NOT hide it"
LOG=(); route D POST /a
if [[ "$CODE" == 405 && "$ALLOW" == "GET, HEAD" && ${#LOG[@]} -eq 0 ]]; then kt_test_pass "405"; else kt_test_fail "code=$CODE allow='$ALLOW' log=${LOG[*]}"; fi

kt_test_start "no default for the method and none for ALL → 404"
THttpRouter.new D2; reg D2 /x PUT hDefPut 1
LOG=(); route D2 POST /y
if [[ "$CODE" == 404 && ${#LOG[@]} -eq 0 ]]; then kt_test_pass "404"; else kt_test_fail "code=$CODE log=${LOG[*]}"; fi
D2.delete

kt_test_start "a default route still matches its own pattern as an ordinary route (params captured); as a fallback it captures none"
THttpRouter.new D3
dp_h() { local v=none; if $1.RouteParam id; then v="$RESULT"; fi; DP_SEEN="$v"; }
reg D3 /items/:id GET dp_h 1
DP_SEEN=""; route D3 GET /items/7; a="$DP_SEEN"
DP_SEEN=""; route D3 GET /other;    b="$DP_SEEN"
FR=0; D3.FindRoute /other GET || FR=$?; c="$FR:$RESULT"
if [[ "$a" == 7 && "$b" == none && "$c" == "0:0" ]]; then kt_test_pass "id=7; fallback none; FindRoute → 0"; else kt_test_fail "a='$a' b='$b' find='$c'"; fi
D3.delete

# ===========================================================================
kt_test_section "6. RouteRequest: BeforeRequest → handler → AfterRequest; rc; the router never sends"
# ===========================================================================

THttpRouter.new F
reg F /ok GET hA 0 fdata
reg F /fail GET hFail
F.BeforeRequest = hBefore
F.AfterRequest = hAfter

kt_test_start "the order is BeforeRequest REQ RESP → handler REQ RESP DATA → AfterRequest REQ RESP"
LOG=(); route F GET /ok
if [[ $RR -eq 0 && "${LOG[*]}" == "before:2:Q:S A:3:Q:S:fdata after:2:Q:S" && "$SENT" == 0 && -z "$RO$RE" ]]; then
    kt_test_pass "${LOG[*]}"
else
    kt_test_fail "rr=$RR log=${LOG[*]} sent=$SENT out='$RO' err='$RE'"
fi

kt_test_start "a handler's non-zero rc is returned; AfterRequest still runs; nothing is sent (the server makes it 500 in P2)"
LOG=(); route F GET /fail
if [[ $RR -eq 7 && "${LOG[*]}" == "before:2:Q:S fail after:2:Q:S" && "$SENT" == 0 && "$CODE" == 418 ]]; then kt_test_pass "rc 7"; else kt_test_fail "rr=$RR log=${LOG[*]} sent=$SENT code=$CODE"; fi

kt_test_start "404 and 405 still run both hooks and are rc 0"
LOG=(); route F GET /none; a="$RR:$CODE:${LOG[*]}"
LOG=(); route F POST /ok;  b="$RR:$CODE:${LOG[*]}"
if [[ "$a" == "0:404:before:2:Q:S after:2:Q:S" && "$b" == "0:405:before:2:Q:S after:2:Q:S" ]]; then kt_test_pass "both"; else kt_test_fail "'$a' '$b'"; fi

kt_test_start "BeforeRequest non-zero → the handler is skipped, AfterRequest runs, its rc is returned"
F.BeforeRequest = hBeforeRc
LOG=(); route F GET /ok
if [[ $RR -eq 5 && "${LOG[*]}" == "before-rc after:2:Q:S" ]]; then kt_test_pass "rc 5"; else kt_test_fail "rr=$RR log=${LOG[*]}"; fi

kt_test_start "BeforeRequest that SENT the response → the handler is skipped (FPC's safety), rc 0"
F.BeforeRequest = hBeforeSend
LOG=(); route F GET /ok
if [[ $RR -eq 0 && "${LOG[*]}" == "before-send after:2:Q:S" && "$SENT" == 1 && "$CODE" == 401 ]]; then kt_test_pass "skipped"; else kt_test_fail "rr=$RR log=${LOG[*]} sent=$SENT code=$CODE"; fi

kt_test_start "AfterRequest non-zero is returned when all else was rc 0; the handler's rc wins over it"
F.BeforeRequest = ""; F.AfterRequest = hAfterRc
LOG=(); route F GET /ok;   a="$RR:${LOG[*]}"
LOG=(); route F GET /fail; b="$RR:${LOG[*]}"
if [[ "$a" == "6:A:3:Q:S:fdata after-rc" && "$b" == "7:fail after-rc" ]]; then kt_test_pass "6, then 7"; else kt_test_fail "'$a' '$b'"; fi

kt_test_start "empty hooks are skipped; a hook that is not a handler name or not a function → rc 2, nothing run"
F.AfterRequest = ""
bad=""
for h in 'no_such_fn003' 'a b' '$(:>pwn)' 'x.y.z'; do
    F.BeforeRequest = "$h"
    LOG=(); route F GET /ok; [[ $RR -eq 2 && ${#LOG[@]} -eq 0 ]] || bad+=" before='$h':$RR:${LOG[*]}"
done
F.BeforeRequest = ""
for h in 'no_such_fn003' 'a;b'; do
    F.AfterRequest = "$h"
    LOG=(); route F GET /ok; [[ $RR -eq 2 && ${#LOG[@]} -eq 0 ]] || bad+=" after='$h':$RR:${LOG[*]}"
done
F.AfterRequest = ""
LOG=(); route F GET /ok; [[ $RR -eq 0 && "${LOG[*]}" == "A:3:Q:S:fdata" ]] || bad+=" plain:$RR:${LOG[*]}"
if [[ -z "$bad" && ! -e pwn ]]; then kt_test_pass "six refused, plain route ok"; else kt_test_fail "$bad"; fi

kt_test_start "RouteRequest malformed calls → rc 2: no args, one arg, not instances, swapped types, an unparsed request"
bad=""
rc=0; F.RouteRequest 2>/dev/null || rc=$?;        [[ $rc -eq 2 ]] || bad+=" none:$rc"
req GET /ok
rc=0; F.RouteRequest Q 2>/dev/null || rc=$?;      [[ $rc -eq 2 ]] || bad+=" one:$rc"
rc=0; F.RouteRequest Nope003 S || rc=$?;          [[ $rc -eq 2 ]] || bad+=" nope:$rc"
rc=0; F.RouteRequest S Q || rc=$?;                [[ $rc -eq 2 ]] || bad+=" swapped:$rc"
rc=0; F.RouteRequest 'Q;x' S || rc=$?;            [[ $rc -eq 2 ]] || bad+=" hostile:$rc"
THttpRequest.new Blank003
LOG=(); rc=0; F.RouteRequest Blank003 S || rc=$?; [[ $rc -eq 2 && ${#LOG[@]} -eq 0 ]] || bad+=" unparsed:$rc:${LOG[*]}"
Blank003.delete
if [[ -z "$bad" ]]; then kt_test_pass "six rc 2"; else kt_test_fail "$bad"; fi

# ===========================================================================
kt_test_section "7. the handler contract (§2.11): DATA verbatim (fact 20), local, silent reads"
# ===========================================================================

class THsData003 : THttpRouteObject
    public
        override proc HandleRequest
end
THsData003.HandleRequest() { DATA_SEEN="$RouteData"; DATA_N=$#; }
build THsData003

class THsDataCtl003
    public
        constructor Create
        proc Take
end
THsDataCtl003.Create() { :; }
THsDataCtl003.Take() { DATA_SEEN="$3"; DATA_N=$#; }
build THsDataCtl003
THsDataCtl003.new DCtl

DATAS=('a  b' '*' '$(:>pwn)' '`:>pwn`' '' '-n' '=' $'x\ny' '${IFS}' '\t\\' ' lead' 'trail ' '%41&x=1')
kt_test_start "D7: DATA reaches \$3 (function, INST.METHOD) and RouteData (route object) verbatim — ${#DATAS[@]} values"
bad=""
for i in "${!DATAS[@]}"; do
    d="${DATAS[i]}"
    drop DR; THttpRouter.new DR
    reg DR /f GET hData 0 "$d"
    reg DR /m GET DCtl.Take 0 "$d"
    reg DR /o GET THsData003 0 "$d"
    for p in f m o; do
        DATA_SEEN="__unset__"; DATA_N=""
        route DR GET "/$p"
        want=3; [[ $p == o ]] && want=2
        [[ $RR -eq 0 && "$DATA_SEEN" == "$d" && "$DATA_N" == "$want" ]] || bad+=" #$i/$p:rr=$RR n=$DATA_N got='$DATA_SEEN'"
    done
done
drop DR
if [[ -z "$bad" && ! -e pwn ]]; then kt_test_pass "all verbatim, no pwn"; else kt_test_fail "$bad"; fi

kt_test_start "a handler reading \$req.Method / \$req.RouteParam / \$req.PathInfo / \$resp.Code prints nothing and gets RESULT"
THttpRouter.new HR
hRead() {
    local req="$1" resp="$2" m p pi c
    RESULT=stale; $req.Method;         m="$RESULT"
    RESULT=stale; $req.RouteParam id;  p="$RESULT"
    RESULT=stale; $req.PathInfo;       pi="$RESULT"
    RESULT=stale; $resp.Code;          c="$RESULT"
    READ_SEEN="$m|$p|$pi|$c"
}
reg HR /read/:id GET hRead
READ_SEEN=""; route HR GET /read/5
if [[ $RR -eq 0 && -z "$RO$RE" && "$READ_SEEN" == "GET|5|/read/5|200" ]]; then kt_test_pass "$READ_SEEN, silent"; else kt_test_fail "rr=$RR out='$RO' err='$RE' seen='$READ_SEEN'"; fi

kt_test_start "a handler that declares everything \`local\` leaves the router intact (C25)"
hLocal() {
    local BeforeRequest=x AfterRequest=y RouteCount=z state=s RouteData=r Label=l
    BeforeRequest=x2; AfterRequest=y2; state=s2
    $2.Write local-ok
}
reg HR /local GET hLocal
HR.BeforeRequest = hBefore; HR.AfterRequest = hAfter
LOG=(); route HR GET /local
b="$(HR.BeforeRequest)"; a="$(HR.AfterRequest)"
S.Content; body="$RESULT"
count HR
if [[ $RR -eq 0 && "$b" == hBefore && "$a" == hAfter && "${LOG[*]}" == "before:2:Q:S after:2:Q:S" && "$body" == local-ok && "$RC_N" == 2 ]]; then
    kt_test_pass "hooks unchanged, both ran"
else
    kt_test_fail "rr=$RR before='$b' after='$a' log=${LOG[*]} body='$body' count=$RC_N"
fi

kt_test_start "…while a BARE assignment writes the router's property (the documented hazard, §2.11)"
hBare() { AfterRequest=hAfter2; }
reg HR /bare GET hBare
LOG=(); route HR GET /bare
a="$(HR.AfterRequest)"
if [[ "$a" == hAfter2 && "${LOG[*]}" == "before:2:Q:S after2" ]]; then kt_test_pass "AfterRequest became hAfter2 and ran"; else kt_test_fail "after='$a' log=${LOG[*]}"; fi
HR.delete

kt_test_start "hostile route params (the table's \$(…), backtick, \${IFS}, ;…&&) never ran: no pwn anywhere"
if [[ ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" && ! -e "$UNIT_DIR/pwn" ]]; then kt_test_pass "no pwn"; else kt_test_fail "pwn exists"; fi

# ===========================================================================
kt_test_section "8. fork-free routing (PLAN §2.1, §4)"
# ===========================================================================

THttpRouter.new FF
reg FF /c/:name GET THsHello003 0 ffdata
reg FF /m GET Ctr.Next
reg FF /f GET hA
FF.BeforeRequest = hBefore; FF.AfterRequest = hAfter

# ffrun — three requests (route object, INST.METHOD, function), plus a 404
# and a 405, through RouteRequest; FFRC = 0 only if all answered as expected.
ffrun() {
    FFRC=0
    req GET /c/zed || { FFRC=1; return; }
    FF.RouteRequest Q S || FFRC=2
    S.Content; [[ "$RESULT" == "hello zed" ]] || FFRC=3
    req GET /m || { FFRC=4; return; }
    FF.RouteRequest Q S || FFRC=5
    req GET /f || { FFRC=6; return; }
    FF.RouteRequest Q S || FFRC=7
    req GET /none || { FFRC=8; return; }
    FF.RouteRequest Q S || FFRC=9
    S.Code; [[ "$RESULT" == 404 ]] || FFRC=10
    req POST /f || { FFRC=11; return; }
    FF.RouteRequest Q S || FFRC=12
    S.Code; [[ "$RESULT" == 405 ]] || FFRC=13
}

kt_test_start "(a) \$BASHPID unchanged across routing"
p0=$BASHPID; ffrun
if [[ $FFRC -eq 0 && $BASHPID == "$p0" ]]; then kt_test_pass "pid $p0"; else kt_test_fail "rc=$FFRC"; fi

kt_test_start "(b) routing works with PATH='' (no external command)"
ffnopath() { local PATH=''; ffrun; }
ffnopath 2>"$TMP/ffnp.err"; e="$(<"$TMP/ffnp.err")"
if [[ $FFRC -eq 0 && -z "$e" ]]; then kt_test_pass "rc 0, silent"; else kt_test_fail "rc=$FFRC err='${e:0:160}'"; fi

kt_test_start "(c) no stored member body of THttpRouter / THttpRouteObject contains \$( , a backtick or a pipe"
bad=""; nb=0
for C in THttpRouter THttpRouteObject; do
    declare -n __ml="${C}_decl_methods"
    for m in "${__ml[@]}" __ctor__; do
        if [[ "$m" == "__ctor__" ]]; then v="${C}_constructor_body"; else v="${C}_method_body_${m}"; fi
        [[ -n "${!v+x}" ]] || continue
        b="${!v}"; nb=$(( nb + 1 ))
        probe="${b//'$(('/}"; probe="${probe//'||'/}"
        [[ "$probe" == *'$('* || "$probe" == *'`'* || "$probe" == *'|'* ]] && bad+=" $C.$m"
    done
    unset -n __ml
done
if [[ -z "$bad" && $nb -ge 8 ]]; then kt_test_pass "$nb bodies clean"; else kt_test_fail "bodies=$nb forking:$bad"; fi

kt_test_start "(d) a DEBUG-trap canary (set -T) sees NO subshell during RouteRequest — and does in a control run"
CANARY="$TMP/fork.canary"; rm -f "$CANARY"
routeonly() {
    FFRC=0
    FF.RouteRequest Q S || FFRC=1
}
req GET /c/can%41ry%20x
set -T
trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
routeonly
trap - DEBUG
set +T
seen=0; [[ -e "$CANARY" ]] && seen=1
rm -f "$CANARY"
set -T; trap 'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi' DEBUG
ctl="$(printf x)"
trap - DEBUG; set +T
ctlseen=0; [[ -e "$CANARY" ]] && ctlseen=1
rm -f "$CANARY"
S.Content; cbody="$RESULT"
if [[ $FFRC -eq 0 && $seen -eq 0 && $ctlseen -eq 1 && "$cbody" == "hello canAry x" ]]; then kt_test_pass "routing (a decoded param included): no subshell; control: detected"; else kt_test_fail "rc=$FFRC seen=$seen control=$ctlseen body='$cbody'"; fi

# ===========================================================================
kt_test_section "9. route params are percent-decoded with PATH rules (review R1)"
# ===========================================================================

THttpRouter.new PD
pd_h() { local v=__none__; if $1.RouteParam v; then v="$RESULT"; fi; PD_SEEN="$v"; PD_RUN=$(( PD_RUN + 1 )); }
pd_r() { local v=__none__; if $1.RouteParam rest; then v="$RESULT"; fi; PD_SEEN="$v"; PD_RUN=$(( PD_RUN + 1 )); }
reg PD /p/:v GET pd_h
reg PD /r/*rest GET pd_r

# pd TARGET WANT — the handler must see exactly WANT; PathInfo stays raw.
pd() {
    local target="$1" want="$2" pi
    kt_test_start "GET $target → RouteParam = '${want//$'\n'/\\n}'"
    PD_SEEN="__unset__"; PD_RUN=0
    route PD GET "$target"
    Q.PathInfo; pi="$RESULT"
    if [[ $RR -eq 0 && "$CODE" == 200 && $PD_RUN -eq 1 && "$PD_SEEN" == "$want" && "$pi" == "$target" && -z "$RO$RE" ]]; then
        kt_test_pass "decoded; PathInfo raw"
    else
        kt_test_fail "rr=$RR code=$CODE run=$PD_RUN seen='$PD_SEEN' pathinfo='$pi' out='$RO' err='$RE'"
    fi
}
pd /p/John%20Doe            'John Doe'
pd /p/%C3%B6                $'\xc3\xb6'
pd /p/a%2Fb                 'a/b'
pd /p/a+b                   'a+b'
pd /p/%2B                   '+'
pd /p/%G1                   '%G1'
pd /p/ab%4                  'ab%4'
pd /p/ab%                   'ab%'
pd '/p/a\b'                 'a\b'
pd /p/%5C                   '\'
pd /p/%5Cn%5Cx41            '\n\x41'
pd '/p/\x41%41'             '\x41A'
pd /p/%24%28touch%20pwn%29  '$(touch pwn)'
pd /p/%60touch%20pwn%60     '`touch pwn`'
pd /r/a%20b/c%2Fd/          'a b/c/d/'
pd /r/                      ''

kt_test_start "%2F inside a :param is ONE segment: /p/a%2Fb matches /p/:v, while /p/a/b does not"
route PD GET /p/a/b
if [[ "$CODE" == 404 ]]; then kt_test_pass "raw /p/a/b → 404"; else kt_test_fail "code=$CODE"; fi

kt_test_start "%00 in a :param → Code 400, rc 0, handler NOT run, both hooks run, nothing sent"
PD.BeforeRequest = hBefore; PD.AfterRequest = hAfter
LOG=(); PD_RUN=0
route PD GET /p/a%00b
if [[ $RR -eq 0 && "$CODE" == 400 && $PD_RUN -eq 0 && "${LOG[*]}" == "before:2:Q:S after:2:Q:S" && "$SENT" == 0 && -z "$RO$RE" ]]; then
    kt_test_pass "400, not run"
else
    kt_test_fail "rr=$RR code=$CODE run=$PD_RUN log=${LOG[*]} sent=$SENT out='$RO' err='$RE'"
fi

kt_test_start "%00 in a *rest capture → 400 as well; no route param is set"
LOG=(); PD_RUN=0
route PD GET /r/x/%00
declare -n __rp=Q_rp; np=${#__rp[@]}; unset -n __rp
if [[ $RR -eq 0 && "$CODE" == 400 && $PD_RUN -eq 0 && $np -eq 0 ]]; then kt_test_pass "400, no params"; else kt_test_fail "rr=$RR code=$CODE run=$PD_RUN params=$np"; fi

kt_test_start "…on the wire: HTTP/1.1 400 Bad Request"
send
if [[ "$STATUS" == "HTTP/1.1 400 Bad Request" ]]; then kt_test_pass "$STATUS"; else kt_test_fail "'$STATUS'"; fi

kt_test_start "a route OBJECT gets the decoded param too; %00 → no route object is created"
PD.BeforeRequest = ""; PD.AfterRequest = ""
reg PD /o/:name GET THsHello003
HELLO_CTOR=0
route PD GET /o/Jos%C3%A9%20M; S.Content; a="$RESULT"
route PD GET /o/x%00; b="$CODE"
if [[ "$a" == "hello José M" && "$b" == 400 && $HELLO_CTOR -eq 1 ]]; then kt_test_pass "hello José M; 400 without an object"; else kt_test_fail "body='$a' code=$b ctor=$HELLO_CTOR"; fi

kt_test_start "the decoded hostile values were never executed: no pwn anywhere"
if [[ ! -e "$TMP/pwn" && ! -e "$SCRIPT_DIR/pwn" && ! -e "$UNIT_DIR/pwn" ]]; then kt_test_pass "no pwn"; else kt_test_fail "pwn exists"; fi
PD.delete

# ===========================================================================
kt_test_section "10. nested dispatch: a route object that routes through another router (review 2026-09-30 F1)"
# ===========================================================================

# THsNest003 — one class for every level: RouteData names the NEXT router
# ('' = the innermost level). Tag is per object (a serial from the
# constructor), so every level can prove it still reads ITS OWN fields after
# the nested dispatch returned.
class THsNest003 : THttpRouteObject
    public
        var Tag
        constructor Create
        destructor  Destroy
        override proc HandleRequest
end
THsNest003.Create() { inherited; NEST_SERIAL=$(( NEST_SERIAL + 1 )); Tag="t$NEST_SERIAL"; }
THsNest003.Destroy() { NEST_LOG+=("dtor:$Tag"); inherited; }
THsNest003.HandleRequest() {
    local req="$1" resp="$2" irc=0 next="$RouteData"
    NEST_LOG+=("in:$__inst__:$RouteData:$Tag")
    $resp.Write "[$Tag"
    if [[ -n "$next" ]]; then
        "$next.RouteRequest" "$req" "$resp" || irc=$?
        NEST_LOG+=("back:$__inst__:$RouteData:$Tag:$irc")
    fi
    $resp.Write "$Tag]"
    return 0
}
build THsNest003

THttpRouter.new NestA; THttpRouter.new NestB; THttpRouter.new NestC
reg NestA /n/:x GET THsNest003 0 NestB
reg NestB /n/:x GET THsNest003 0 ""
reg NestA /m/:x GET THsNest003 0 NestB
reg NestB /m/:x GET THsNest003 0 NestC
reg NestC /m/:x GET THsNest003 0 ""
nest_fn() { NestB.RouteRequest "$1" "$2"; }
THttpRouter.new NestF
reg NestF /n/:x GET nest_fn

# nest_left — every route-object instance that is still alive ('' = none).
nest_left() {
    local v; NL=""
    for v in __ths_route_obj __ths_route_obj1 __ths_route_obj2 __ths_route_obj3; do
        declare -p "${v}_class" >/dev/null 2>&1 && NL+=" $v"
        declare -F "$v.HandleRequest" >/dev/null && NL+=" $v()"
    done
}

# nest ROUTER PATH — GET PATH through ROUTER in a SUBSHELL, the results
# through a file: RR, NLOG (the log), BODY, NL (route objects left), HD
# (HELLO_DTOR). The subshell is there because the pre-F1 router ABORTED the
# whole top-level command here (the outer object's namerefs pointed into the
# instance the inner pass had deleted: "expression recursion level
# exceeded") — under the runner, which sources the test file, that silently
# truncated the file; now it is a FAIL. (Inside a subshell kklass prints every
# member read by design, so the subshell's stdout is discarded; the silence of
# a dispatch is pinned by §3/§6 in this shell.)
nest() {
    local f="$TMP/nest.out"
    rm -f "$f"
    ( NEST_LOG=(); NEST_SERIAL=0
      route "$1" GET "$2"; S.Content; body="$RESULT"; nest_left
      printf '%s\n' "$RR" "${NEST_LOG[*]}" "$body" "$NL" "$HELLO_DTOR" > "$f" ) >/dev/null 2>&1
    RR=aborted; NLOG=""; BODY=""; NL="?"; HD=""
    if [[ -f "$f" ]]; then
        { IFS= read -r RR; IFS= read -r NLOG; IFS= read -r BODY; IFS= read -r NL; IFS= read -r HD; } < "$f"
    fi
}

kt_test_start "F1: two levels — the outer object survives the inner dispatch: its RouteData and Tag intact afterwards, the inner is a DIFFERENT instance"
nest NestA /n/1
want="in:__ths_route_obj:NestB:t1 in:__ths_route_obj1::t2 dtor:t2 back:__ths_route_obj:NestB:t1:0 dtor:t1"
if [[ "$RR" == 0 && "$NLOG" == "$want" && "$BODY" == "[t1[t2t2]t1]" && -z "$NL" ]]; then
    kt_test_pass "$NLOG"
else
    kt_test_fail "rr=$RR log='$NLOG' body='$BODY' left='$NL'"
fi

kt_test_start "F1: three levels — each level has its own instance, each resumes with its own fields, all deleted innermost first"
nest NestA /m/1
want="in:__ths_route_obj:NestB:t1 in:__ths_route_obj1:NestC:t2 in:__ths_route_obj2::t3 dtor:t3"
want+=" back:__ths_route_obj1:NestC:t2:0 dtor:t2 back:__ths_route_obj:NestB:t1:0 dtor:t1"
if [[ "$RR" == 0 && "$NLOG" == "$want" && "$BODY" == "[t1[t2[t3t3]t2]t1]" && -z "$NL" ]]; then
    kt_test_pass "3 levels, 3 instances, clean"
else
    kt_test_fail "rr=$RR log='$NLOG' body='$BODY' left='$NL'"
fi

kt_test_start "F1: nesting leaves no level behind — in the SAME shell a nested dispatch, then a plain one: the plain one uses __ths_route_obj again"
f="$TMP/nest2.out"; rm -f "$f"
( NEST_LOG=(); NEST_SERIAL=0
  route NestA GET /n/2; a="$RR"; NEST_LOG=(); NEST_SERIAL=0
  route NestB GET /n/2; nest_left
  printf '%s\n' "$a:$RR" "${NEST_LOG[*]}" "$NL" > "$f" ) >/dev/null 2>&1
r=""; l=""; left="?"; [[ -f "$f" ]] && { IFS= read -r r; IFS= read -r l; IFS= read -r left; } < "$f"
if [[ "$r" == "0:0" && "$l" == "in:__ths_route_obj::t1 dtor:t1" && -z "$left" ]]; then kt_test_pass "$l"; else kt_test_fail "rr='$r' log='$l' left='$left'"; fi

kt_test_start "F1: a stale object of the NESTED level (an aborted inner pass) is deleted first; the live outer one is untouched"
THsHello003.new __ths_route_obj1
HELLO_DTOR=0
nest NestA /n/3
drop __ths_route_obj1
want="in:__ths_route_obj:NestB:t1 in:__ths_route_obj1::t2 dtor:t2 back:__ths_route_obj:NestB:t1:0 dtor:t1"
if [[ "$RR" == 0 && "$HD" == 1 && "$NLOG" == "$want" && -z "$NL" ]]; then kt_test_pass "stale inner deleted, outer intact"; else kt_test_fail "rr=$RR stale-dtor='$HD' log='$NLOG' left='$NL'"; fi

kt_test_start "F1: a nested dispatch under a FUNCTION route (no outer object) — the inner object is the first level: __ths_route_obj"
nest NestF /n/4
if [[ "$RR" == 0 && "$NLOG" == "in:__ths_route_obj::t1 dtor:t1" && -z "$NL" ]]; then kt_test_pass "$NLOG"; else kt_test_fail "rr=$RR log='$NLOG' left='$NL'"; fi
NestA.delete; NestB.delete; NestC.delete; NestF.delete

kt_test_start "RouteRequest refuses a request whose parse ENDED in a status (Method is kept since F4, but nothing was parsed past the request line): rc 2, no hook, no handler"
THttpRouter.new NestG
reg NestG /ok GET hA
NestG.BeforeRequest = hBefore
printf 'GET /ok HTTP/1.1\r\nHost: t\r\nBad Name: v\r\n\r\n' > "$TMP/f4route.req"
drop Q; drop S; drop RT
TReplayTransport.new RT; RT.AddRequestFile "$TMP/f4route.req"; RT.Accept 0 10
RT.InFd; in="$RESULT"; RT.OutFd; out="$RESULT"
THttpRequest.new Q; THttpResponse.new S; S.Attach "$out" 0
Q.ReadFrom "$in" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536; st="$RESULT"
LOG=(); rc=0; NestG.RouteRequest Q S 2>/dev/null || rc=$?
if [[ "$st" == 400 && $rc -eq 2 && ${#LOG[@]} -eq 0 ]]; then kt_test_pass "status 400 → rc 2, nothing ran"; else kt_test_fail "st=$st rc=$rc log=${LOG[*]}"; fi
NestG.delete

FF.delete; F.delete; D.delete; M.delete; K.delete; R2.delete; Ctr.delete; DCtl.delete
drop Q; drop S; drop RT
