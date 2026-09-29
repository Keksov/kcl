#!/bin/bash
# 008_Contract.sh — thttpserver P0+P1: the kcl contract (kcl/README.md §1,
# PLAN §2.1) for the message classes, the replay transport and the router.
#
# What it pins:
#
#   source integrity  `bash -n` on every unit file; no single-quoted printf
#                     format left open at end of line (the dangling-quote
#                     check); no inline `$'\r'` (it does not survive `build`,
#                     hence `__THS_CR`); no `$this.` internal call; the
#                     red-first sentinel gone; never `local TZ` and the Date in
#                     the `LC_ALL=C TZ=UTC0 printf -v` prefix form (C15); the
#                     file-scope constants; destructors freeing every extra
#                     per-instance array (router: _pat _met _hnd _kind _def
#                     _rdat, never _data); ONE write in SendContent, errors
#                     silenced; P1 scope — thttpserver.sh sources the message
#                     and router files, no netcat/server class yet.
#   set -eu           a child under `set -eu` loads the unit (twice) and runs
#                     the replay pipeline end to end, every parser status path,
#                     every guarded miss and refusal, and exits clean.
#   §1.2 diagnostics  every rc 1 / rc 2 path: silent with the switch off,
#                     exactly ONE `kk.debug` line under VERBOSE_KKLASS=debug;
#                     the successful paths silent either way.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpserver.sh"
MSG="$UNIT_DIR/thttpmessage.sh"
ROUTER="$UNIT_DIR/thttprouter.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/contract.err"
OUTF="$TMP/contract.out"
FILES=("$MSG" "$ROUTER" "$UNIT")

kt_test_section "008: the kcl contract for thttpserver (P0 + P1)"

# ===========================================================================
kt_test_section "0. source integrity"
# ===========================================================================

for f in "${FILES[@]}"; do
    kt_test_start "$(basename "$f") parses (bash -n)"
    if err="$("$BASH" -n "$f" 2>&1)"; then kt_test_pass "clean"; else kt_test_fail "bash -n: $err"; fi
done

kt_test_start "no single-quoted printf format is left open at end of line (dangling quote)"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -nE "printf (-v [A-Za-z_]+ )?'[^']*\$" "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "no inline \$'\\r' anywhere (build drops it) — __THS_CR is the only CR"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -n "\$'\\\\r" "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "no internal member call spelled \`\$this.NAME\`"
bad=""
for f in "${FILES[@]}"; do
    if b="$(grep -n '\$this\.' "$f")"; then bad+=" $(basename "$f"): ${b//$'\n'/ | }"; fi
done
if [[ -z "$bad" ]]; then kt_test_pass "none"; else kt_test_fail "$bad"; fi

kt_test_start "the red-first sentinel __THS_PENDING__ is gone"
if grep -n '__THS_PENDING__' "${FILES[@]}" >/dev/null; then kt_test_fail "skeleton still in place"; else kt_test_pass "gone"; fi

kt_test_start "never \`local TZ\`; the Date is the prefix form \`LC_ALL=C TZ=UTC0 printf -v …'%(%a, %d %b %Y %H:%M:%S GMT)T' -1\`"
if ! grep -nE 'local[^#]*\bTZ=' "${FILES[@]}" >/dev/null \
   && grep -F "LC_ALL=C TZ=UTC0 printf -v __ths_date '%(%a, %d %b %Y %H:%M:%S GMT)T' -1" "$MSG" >/dev/null; then
    kt_test_pass "prefix form, no local TZ"
else
    kt_test_fail "Date idiom missing or local TZ present"
fi

kt_test_start "file-scope constants: __THS_CR is one CR; __THS_REASON is an assoc with the parser statuses"
bad=""
[[ "${__THS_CR:-}" == $'\r' ]] || bad+=" __THS_CR"
[[ "$(declare -p __THS_REASON 2>/dev/null)" == "declare -A"* ]] || bad+=" __THS_REASON-not-assoc"
for c in 200 400 408 413 414 431 500 501 505; do [[ -n "${__THS_REASON[$c]:-}" ]] || bad+=" reason-$c"; done
if [[ -z "$bad" ]]; then kt_test_pass "both"; else kt_test_fail "$bad"; fi

kt_test_start "destructors free every extra per-instance array (request _hdr _hdrn _qf _rp, response _hdr _hdrn, replay _rqf _rsf)"
bad=""
d="$(sed -n '/^THttpRequest.Destroy()/,/^}/p' "$MSG")"
for s in _hdr _hdrn _qf _rp; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" req$s"; done
[[ "$d" == *'unset -v'* ]] || bad+=" req-no-unset"
d="$(sed -n '/^THttpResponse.Destroy()/,/^}/p' "$MSG")"
for s in _hdr _hdrn; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" resp$s"; done
d="$(sed -n '/^TReplayTransport.Destroy()/,/^}/p' "$UNIT")"
for s in _rqf _rsf; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" replay$s"; done
[[ "$d" == *inherited* ]] || bad+=" replay-no-inherited"
d="$(sed -n '/^THttpRouter.Destroy()/,/^}/p' "$ROUTER")"
for s in _pat _met _hnd _kind _def _rdat; do [[ "$d" == *"\"\${__inst__}$s\""* ]] || bad+=" router$s"; done
[[ "$d" == *'unset -v'* ]] || bad+=" router-no-unset"
if grep -n '_data' "$ROUTER" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then bad+=" router-touches-_data"; fi
d="$(sed -n '/^THttpRouteObject.Destroy()/,/^}/p' "$ROUTER")"
[[ -n "$d" && "${THttpRouteObject_destructor_name:-}" == Destroy ]] || bad+=" routeobject-no-destructor"
if [[ -z "$bad" ]]; then kt_test_pass "all fourteen arrays, replay chains with inherited, THttpRouteObject has a destructor, router never names _data"; else kt_test_fail "$bad"; fi

kt_test_start "SendContent writes with ONE printf to the fd, stderr silenced before the fd redirection"
b="$(sed -n '/^THttpResponse.SendContent()/,/^}/p' "$MSG")"
nw=0; while IFS= read -r l; do [[ "$l" == *'>&"$__ths_fd"'* ]] && nw=$(( nw + 1 )); done <<< "$b"
if [[ $nw -eq 1 && "$b" == *"printf '%s' \"\$__ths_out\" 2>/dev/null >&\"\$__ths_fd\""* ]]; then kt_test_pass "one write"; else kt_test_fail "writes=$nw"; fi

kt_test_start "P1 scope: thttpserver.sh sources kklass_pascal.sh, thttpmessage.sh, thttprouter.sh; no netcat/server class yet"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$UNIT" || :)"
n=0; while IFS= read -r l; do [[ -n "$l" ]] && n=$(( n + 1 )); done <<< "$srcs"
if [[ $n -eq 3 && "$srcs" == *kklass_pascal.sh* && "$srcs" == *thttpmessage.sh* && "$srcs" == *thttprouter.sh* ]] \
   && ! grep -nE '^class (TNetcatTransport|THttpServer|THttpApplication)' "$UNIT" "$ROUTER" "$MSG" >/dev/null \
   && [[ ! -e "$UNIT_DIR/thttpapplication.sh" ]]; then
    kt_test_pass "three sources; P2/P3 classes absent"
else
    kt_test_fail "sources: ${srcs//$'\n'/ | }"
fi

kt_test_start "thttprouter.sh: sources kklass_pascal.sh and thttpmessage.sh only (never the entry point), declares exactly THttpRouteObject and THttpRouter"
srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$ROUTER" || :)"
n=0; while IFS= read -r l; do [[ -n "$l" ]] && n=$(( n + 1 )); done <<< "$srcs"
cls="$(grep -E '^class ' "$ROUTER" || :)"
if [[ $n -eq 2 && "$srcs" == *kklass_pascal.sh* && "$srcs" == *thttpmessage.sh* && "$srcs" != *thttpserver.sh* \
      && "$cls" == $'class THttpRouteObject\nclass THttpRouter' ]]; then
    kt_test_pass "two sources; two classes"
else
    kt_test_fail "sources: ${srcs//$'\n'/ | } classes: ${cls//$'\n'/ | }"
fi

kt_test_start "the router sourced ALONE (fresh child) loads its classes and the message classes it needs"
out="$(ROUTER="$ROUTER" timeout 180 "$BASH" -c 'source "$ROUTER"; THttpRouter.new X; THttpRequest.new Y; X.RouteCount; printf "%s" "$RESULT"; X.delete; Y.delete' 2>&1 </dev/null)"
if [[ "$out" == "0" ]]; then kt_test_pass "standalone"; else kt_test_fail "out='${out:0:200}'"; fi

# ===========================================================================
kt_test_section "1. set -eu"
# ===========================================================================

# expect_clean TITLE SNIPPET — a CHILD under `set -eu` with the unit freshly
# sourced; it must end rc 0, print exactly OK and write nothing to stderr.
expect_clean() {
    local title="$1" snippet="$2" out rc err
    kt_test_start "$title"
    : > "$ERRF"
    out="$(TMP="$TMP" UNIT="$UNIT" timeout 180 "$BASH" -c "set -eu
source \"\$UNIT\"
$snippet
printf OK" 2>"$ERRF" </dev/null)"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "[$title] rc=$rc out='${out:0:200}' stderr='${err:0:300}'"
    fi
}

printf 'POST /p?a=1&=&b=%%41 HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\n\r\nxyz' > "$TMP/ok.req"
printf 'GET http://x/ HTTP/1.1\r\nHost: h\r\n\r\n' > "$TMP/400.req"
printf 'GET / HT' > "$TMP/gone.req"
printf 'POST / HTTP/1.0\r\nContent-Length: 70000\r\n\r\n' > "$TMP/413.req"

expect_clean "the unit loads under set -eu, and loads again (every re-source guard holds)" '
source "$UNIT"
source "$UNIT"'

expect_clean "the replay pipeline end to end: accept, parse, answer, send, close, free" '
TReplayTransport.new T
T.AddRequestFile "$TMP/ok.req"
T.Accept 0 10
T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"
THttpRequest.new R; THttpResponse.new S
S.Attach "$out" 0
dl=$(( ${EPOCHREALTIME//[!0-9]/} + 10000000 ))
R.ReadFrom "$in" "$dl" 65536
[[ "$RESULT" == "0" ]] || { printf "status=%s\n" "$RESULT" >&2; exit 9; }
R.Method; S.Write "$RESULT"
R.QueryField b; S.Write "$RESULT"
R.ContentLength; S.Write "$RESULT"
declare -a N=(); R.HeaderNames N
S.SetCustomHeader X-A 1
S.SendContent
S.ContentSent; [[ "$RESULT" == "1" ]] || exit 8
T.CloseConnection
R.delete; S.delete
T.ResponseFile 0; f="$RESULT"
body="$(<"$f")"; [[ "$body" == *"POSTA3" ]] || { printf "body=%s\n" "$body" >&2; exit 7; }
T.Shutdown
T.delete'

expect_clean "non-zero parser statuses are rc 0 (a value, not a miss): 400, 413, gone, 408" '
THttpRequest.new R
for f in 400 413 gone; do
    exec {fd}<"$TMP/$f.req"
    R.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
    [[ "$RESULT" == "$f" ]] || { printf "%s → %s\n" "$f" "$RESULT" >&2; exit 9; }
    exec {fd}<&-
done
exec {fd}<"$TMP/ok.req"
R.ReadFrom "$fd" 0 65536
[[ "$RESULT" == "408" ]] || exit 8
exec {fd}<&-
R.delete'

expect_clean "misses and refusals under set -eu, each guarded: request" '
THttpRequest.new R
rc=0
R.GetHeader x || rc=$?;          [[ $rc -eq 1 ]] || exit 9; rc=0
R.GetHeader "" || rc=$?;         [[ $rc -eq 2 ]] || exit 8; rc=0
R.QueryField q || rc=$?;         [[ $rc -eq 1 ]] || exit 7; rc=0
R.RouteParam p || rc=$?;         [[ $rc -eq 1 ]] || exit 6; rc=0
R.SetRouteParam "" v || rc=$?;   [[ $rc -eq 2 ]] || exit 5; rc=0
R.HeaderNames 1bad || rc=$?;     [[ $rc -eq 2 ]] || exit 4; rc=0
R.ReadFrom x y z || rc=$?;       [[ $rc -eq 2 ]] || exit 3; rc=0
if R.HasHeader host; then exit 2; fi
R.ContentLength; [[ "$RESULT" == "0" ]] || exit 1
R.delete'

expect_clean "misses and refusals under set -eu, each guarded: response and replay" '
THttpResponse.new S
rc=0
S.SetCustomHeader "a b" v || rc=$?;  [[ $rc -eq 2 ]] || exit 9; rc=0
S.GetCustomHeader x || rc=$?;        [[ $rc -eq 1 ]] || exit 8; rc=0
S.Attach abc || rc=$?;               [[ $rc -eq 2 ]] || exit 7; rc=0
S.SendRedirect /p 200 || rc=$?;      [[ $rc -eq 2 ]] || exit 6; rc=0
S.SendContent || rc=$?;              [[ $rc -eq 1 ]] || exit 5; rc=0
S.Code = 99
exec {fd}>"$TMP/v500.cap"
S.Attach "$fd" 0
S.SendContent
S.SendContent || rc=$?;              [[ $rc -eq 1 ]] || exit 4; rc=0
exec {fd}>&-
S.Code; [[ "$RESULT" == "500" ]] || exit 3
S.delete
TReplayTransport.new T
T.AddRequestFile "" || rc=$?;        [[ $rc -eq 2 ]] || exit 2; rc=0
T.Accept 0 10 || rc=$?;              [[ $rc -eq 2 ]] || exit 1; rc=0
T.ResponseFile 0 || rc=$?;           [[ $rc -eq 1 ]] || exit 10; rc=0
T.CloseConnection
T.delete'

printf 'GET /u/7/a/b HTTP/1.0\r\n\r\n' > "$TMP/route.req"
printf 'PUT /u/7/a/b HTTP/1.0\r\n\r\n' > "$TMP/route405.req"
printf 'GET /none HTTP/1.0\r\n\r\n' > "$TMP/route404.req"

expect_clean "the router end to end: register the three kinds, route 200/405/404, a failing handler, free" '
class TEuRoute : THttpRouteObject
    public
        override proc HandleRequest
end
TEuRoute.HandleRequest() { $2.Write "obj:$RouteData"; }
build TEuRoute
class TEuCtl
    public
        constructor Create
        proc Hit
end
TEuCtl.Create() { :; }
TEuCtl.Hit() { $2.Write "ctl:$3"; }
build TEuCtl
TEuCtl.new C
fn() { local id; $1.RouteParam id; id="$RESULT"; $2.Write "fn:$id:$3"; }
bad() { return 3; }
THttpRouter.new RT
RT.RegisterRoute /u/:id/*rest GET fn 0 d1
RT.RegisterRoute /c GET C.Hit 0 d2
RT.RegisterRoute /o GET TEuRoute 0 d3
RT.RegisterRoute /bad POST bad
RT.RegisterRoute /any ALL fn 1
RT.RouteCount; [[ "$RESULT" == 5 ]] || exit 9
RT.FindRoute /c GET; [[ "$RESULT" == 1 ]] || exit 8
RT.FindRoute /c HEAD
RT.BeforeRequest = fn
RT.BeforeRequest = ""
for f in route route405 route404; do
    TReplayTransport.new T
    T.AddRequestFile "$TMP/$f.req"
    T.Accept 0 10
    T.InFd; in="$RESULT"; T.OutFd; out="$RESULT"
    THttpRequest.new R; THttpResponse.new S
    S.Attach "$out" 0
    R.ReadFrom "$in" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536
    RT.RouteRequest R S
    S.SendContent
    T.CloseConnection
    T.ResponseFile 0; cap="$(<"$RESULT")"
    case $f in
        route)    [[ "$cap" == *"fn:7:d1" ]] || exit 7 ;;
        route405) [[ "$cap" == "HTTP/1.1 405 "* && "$cap" == *"Allow: GET, HEAD"* ]] || exit 6 ;;
        route404) [[ "$cap" == *"fn::"* ]] || exit 5 ;;
    esac
    R.delete; S.delete; T.delete
done
C.delete
RT.delete'

expect_clean "router misses and refusals under set -eu, each guarded" '
THttpRouter.new RT
fn() { :; }
rc=0
RT.RegisterRoute || rc=$?;                     [[ $rc -eq 2 ]] || exit 9; rc=0
RT.RegisterRoute /x fn 0 || rc=$?;             [[ $rc -eq 2 ]] || exit 8; rc=0
RT.RegisterRoute /x GET "a b" || rc=$?;        [[ $rc -eq 2 ]] || exit 7; rc=0
RT.RegisterRoute "/*a/b" GET fn || rc=$?;      [[ $rc -eq 2 ]] || exit 6; rc=0
RT.RegisterRoute /x GET THttpRouteObject || rc=$?; [[ $rc -eq 2 ]] || exit 5; rc=0
RT.RegisterRoute /d GET fn 1
RT.RegisterRoute /e GET fn 1 || rc=$?;         [[ $rc -eq 1 ]] || exit 4; rc=0
RT.FindRoute /none PUT || rc=$?;               [[ $rc -eq 1 && "$REPLY" == 404 ]] || exit 3; rc=0
RT.FindRoute /d || rc=$?;                      [[ $rc -eq 2 ]] || exit 2; rc=0
RT.RouteRequest || rc=$?;                      [[ $rc -eq 2 ]] || exit 1; rc=0
THttpRouteObject.new X 2>/dev/null || rc=$?;   [[ $rc -eq 1 ]] || exit 10; rc=0
RT.delete'

# ===========================================================================
kt_test_section "2. §1.2: one kk.debug line on every rc 1 / rc 2 path, none otherwise"
# ===========================================================================

THttpRequest.new DR; THttpResponse.new DS; TReplayTransport.new DT
printf 'GET / HTTP/1.0\r\nX-A: 1\r\n\r\n' > "$TMP/d.req"
fd=""; exec {fd}<"$TMP/d.req"; DR.ReadFrom "$fd" $(( ${EPOCHREALTIME//[!0-9]/} + 10000000 )) 65536; exec {fd}<&-

# lines RC CALL... — run CALL twice (switch off, switch on); stdout must be
# empty both times; stderr 0 lines off, WANT lines on.
lines() {
    local want="$1" wrc="$2"; shift 2
    local r1=0 r2=0 o1 o2 e1 e2 n=0 l
    "$@" >"$OUTF" 2>"$ERRF" || r1=$?
    o1="$(<"$OUTF")"; e1="$(<"$ERRF")"
    VERBOSE_KKLASS=debug "$@" >"$OUTF" 2>"$ERRF" || r2=$?
    o2="$(<"$OUTF")"; e2="$(<"$ERRF")"
    if [[ -n "$e2" ]]; then while IFS= read -r l; do n=$(( n + 1 )); done <<< "$e2"; fi
    if [[ $r1 -eq $wrc && $r2 -eq $wrc && -z "$o1$o2" && -z "$e1" && $n -eq $want ]]; then
        kt_test_pass "rc $r1; off: silent; debug: $n line(s)"
    else
        kt_test_fail "[$*] rc=$r1/$r2 (want $wrc) stdout='${o1:0:40}|${o2:0:40}' off='${e1:0:80}' debug-lines=$n (want $want) '${e2:0:120}'"
    fi
}
dcase() { kt_test_start "$1"; shift; lines "$@"; }
dcase "GetHeader miss"                1 1 DR.GetHeader x-none
dcase "GetHeader ''"                  1 2 DR.GetHeader ""
dcase "QueryField miss"               1 1 DR.QueryField q
dcase "QueryField ''"                 1 2 DR.QueryField ""
dcase "RouteParam miss"               1 1 DR.RouteParam p
dcase "RouteParam ''"                 1 2 DR.RouteParam ""
dcase "SetRouteParam ''"              1 2 DR.SetRouteParam "" v
dcase "HeaderNames bad name"          1 2 DR.HeaderNames 1bad
dcase "ReadFrom malformed call"       1 2 DR.ReadFrom x 1 1
dcase "SetCustomHeader non-token"     1 2 DS.SetCustomHeader "a b" v
dcase "SetCustomHeader server-owned"  1 2 DS.SetCustomHeader Date v
dcase "SetCustomHeader CR in value"   1 2 DS.SetCustomHeader X-A $'a\rb'
dcase "GetCustomHeader miss"          1 1 DS.GetCustomHeader x
dcase "GetCustomHeader ''"            1 2 DS.GetCustomHeader ""
dcase "Attach malformed"              1 2 DS.Attach abc 0
dcase "SendRedirect bad code"         1 2 DS.SendRedirect /p 200
dcase "SendContent before Attach"     1 1 DS.SendContent
dcase "AddRequestFile ''"             1 2 DT.AddRequestFile ""
dcase "AddRequestFile missing"        1 1 DT.AddRequestFile "$TMP/none.req"
dcase "Accept with nothing left"      1 2 DT.Accept 0 10
dcase "ResponseFile out of range"     1 1 DT.ResponseFile 0
dcase "HasHeader false: an answer, not a miss — silent"   0 1 DR.HasHeader x-none
dcase "GetHeader hit — silent"                            0 0 DR.GetHeader x-a
dcase "SetCustomHeader ok — silent"                       0 0 DS.SetCustomHeader X-Ok 1
dcase "Write — silent"                                    0 0 DS.Write text
dcase "CloseConnection with nothing open — silent"        0 0 DT.CloseConnection

THttpRouter.new DX
dfn() { :; }
dfail() { return 4; }
DX.RegisterRoute /d GET dfn 1
DX.RegisterRoute /f GET dfail
dcase "RegisterRoute bad argument count"   1 2 DX.RegisterRoute /x
dcase "RegisterRoute bad METHOD"           1 2 DX.RegisterRoute /x get dfn
dcase "RegisterRoute bad ISDEFAULT"        1 2 DX.RegisterRoute /x GET dfn yes
dcase "RegisterRoute bad handler name"     1 2 DX.RegisterRoute /x GET 'a b'
dcase "RegisterRoute unknown handler"      1 2 DX.RegisterRoute /x GET no_such_fn008
dcase "RegisterRoute abstract route class" 1 2 DX.RegisterRoute /x GET THttpRouteObject
dcase "RegisterRoute property wrapper"     1 2 DX.RegisterRoute /x GET DX.BeforeRequest
dcase "RegisterRoute '*' not last"         1 2 DX.RegisterRoute '/*a/b' GET dfn
dcase "RegisterRoute second default"       1 1 DX.RegisterRoute /y GET dfn 1
dcase "FindRoute miss"                     1 1 DX.FindRoute /none POST
dcase "FindRoute malformed"                1 2 DX.FindRoute /x
dcase "RouteRequest malformed"             1 2 DX.RouteRequest Nope Nope
dcase "RegisterRoute ok — silent"          0 0 DX.RegisterRoute /ok GET dfn
dcase "FindRoute hit — silent"             0 0 DX.FindRoute /ok GET
dcase "RouteCount — silent"                0 0 DX.RouteCount
dcase "RouteRequest to the default route — silent"      0 0 DX.RouteRequest DR DS
THttpRouter.new DY
dcase "RouteRequest 404 — an answer, silent"            0 0 DY.RouteRequest DR DS
DX.delete; DY.delete
DR.delete; DS.delete; DT.delete
