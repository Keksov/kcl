#!/bin/bash
# 002_Response.sh — thttpserver P0: THttpResponse (PLAN §1.3, §2.3; §3 facts 2,
# 3, 14, 15, 19). The serializer's head format, byte lengths, the 1xx/204/304/
# HEAD rules, custom headers and their refusals, validation → 500 with the
# default head, the English/UTC Date whatever the caller's locale and TZ, the
# deterministic SIGPIPE case, read/write vs read-only properties.
#
# Responses are written to plain capture files through `exec {fd}>FILE`; the
# SIGPIPE and locale cases run in a child bash with stdin closed, under timeout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpmessage.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
CR=$'\r'; LF=$'\n'; CRLF=$'\r\n'
DATE_RE='^Date: (Mon|Tue|Wed|Thu|Fri|Sat|Sun), [0-3][0-9] (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} [0-2][0-9]:[0-5][0-9]:[0-6][0-9] GMT$'

# fresh — a clean THttpResponse named S.
fresh() {
    if declare -p S_class >/dev/null 2>&1; then S.delete; fi
    THttpResponse.new S
}

# send [ISHEAD [BANNER]] — attach S to a new capture file and SendContent.
# SRC = rc; OUT = the whole file (verbatim); HEAD / BODY split at the first
# blank line; HL = head lines (CRLF-split); DATE = the Date line.
send() {
    local fd f="$TMP/cap.$(( ++SEQ ))"
    exec {fd}>"$f"
    if [[ $# -ge 2 ]]; then S.Attach "$fd" "$1" "$2"
    elif [[ $# -eq 1 ]]; then S.Attach "$fd" "$1"
    else S.Attach "$fd"; fi
    SRC=0; S.SendContent 2>"$TMP/send.err" || SRC=$?
    exec {fd}>&-
    OUT=""; IFS= read -r -d '' OUT < "$f" || :
    CAPF="$f"
    HEAD="${OUT%%"$CRLF$CRLF"*}"
    BODY="${OUT#*"$CRLF$CRLF"}"
    [[ "$OUT" == *"$CRLF$CRLF"* ]] || BODY="__no_blank_line__"
    HL=(); local h="$HEAD$CRLF"
    while [[ -n "$h" ]]; do HL+=("${h%%"$CRLF"*}"); h="${h#*"$CRLF"}"; done
    DATE="${HL[1]:-}"
}
SEQ=0

# headof LINES... — the expected head with this response's own Date line.
headof() {
    local IFS=$'\n'
    EXP="$1$CRLF$DATE"; shift
    local l
    for l in "$@"; do EXP+="$CRLF$l"; done
}

get() { local i="$1" m="$2"; shift 2; RESULT="__stale__"; GRC=0; "$i.$m" "$@" || GRC=$?; G="$RESULT"; }

bytes() { local LC_ALL=C; NB=${#1}; }

kt_test_section "002: THttpResponse (P0)"

# ===========================================================================
kt_test_section "1. the head format and byte lengths (fact 2, response half)"
# ===========================================================================

kt_test_start "defaults: Code 200, CodeText '', ContentType text/plain; charset=utf-8, Content '', ContentSent 0"
fresh
bad=""
get S Code;        [[ "$G" == "200" ]] || bad+=" Code='$G'"
get S CodeText;    [[ "$G" == "" ]]    || bad+=" CodeText='$G'"
get S ContentType; [[ "$G" == "text/plain; charset=utf-8" ]] || bad+=" ContentType='$G'"
get S Content;     [[ "$G" == "" ]]    || bad+=" Content='$G'"
get S ContentSent; [[ "$G" == "0" ]]   || bad+=" ContentSent='$G'"
if [[ -z "$bad" ]]; then kt_test_pass "all five"; else kt_test_fail "$bad"; fi

kt_test_start "'aжb' → Content-Length: 4 (bytes); the whole response is byte-exact"
fresh; S.Content = "aжb"
send
headof "HTTP/1.1 200 OK" "Server: kcl-thttpserver" "Content-Type: text/plain; charset=utf-8" "Content-Length: 4" "Connection: close"
if [[ $SRC -eq 0 && "$OUT" == "$EXP$CRLF${CRLF}aжb" && "$DATE" =~ $DATE_RE ]]; then
    kt_test_pass "exact"
else
    kt_test_fail "rc=$SRC out='${OUT//$CR/<CR>}'"
fi

kt_test_start "the capture file's size is head + 4 + 4 bytes — one write, nothing else"
bytes "$EXP"; hb=$NB
sz=$(wc -c < "$CAPF")
if [[ $sz -eq $(( hb + 4 + 4 )) ]]; then kt_test_pass "$sz bytes"; else kt_test_fail "size $sz, head $hb"; fi

kt_test_start "a body that is data: -n, -e, %s, backslashes, CRLF, a trailing newline — verbatim, length in bytes"
fresh
body="-n -e %s %b \\x41 \\\\ ё${CRLF}end${LF}"
S.Content = "$body"
send
bytes "$body"
if [[ "$BODY" == "$body" && " ${HL[*]} " == *" Content-Length: $NB "* ]]; then kt_test_pass "body verbatim, CL $NB"; else kt_test_fail "body='${BODY//$CR/<CR>}' head=(${HL[*]})"; fi

kt_test_start "Code 404 with CodeText '' → the reason from the table; an explicit CodeText wins"
fresh; S.Code = 404; send; a="${HL[0]}"
fresh; S.Code = 404; S.CodeText = "Nope"; send; b="${HL[0]}"
fresh; S.Code = 413; send; c="${HL[0]}"
fresh; S.Code = 505; send; d="${HL[0]}"
if [[ "$a" == "HTTP/1.1 404 Not Found" && "$b" == "HTTP/1.1 404 Nope" && "$c" == "HTTP/1.1 413 Content Too Large" && "$d" == "HTTP/1.1 505 HTTP Version Not Supported" ]]; then
    kt_test_pass "table and override"
else
    kt_test_fail "'$a' '$b' '$c' '$d'"
fi

kt_test_start "a code with no table entry (299) keeps the SP and an empty reason"
fresh; S.Code = 299; send
if [[ "${HL[0]}" == "HTTP/1.1 299 " ]]; then kt_test_pass "'HTTP/1.1 299 '"; else kt_test_fail "'${HL[0]}'"; fi

kt_test_start "every parser status has a reason: 400 408 413 414 431 500 501 505"
bad=""
for c in 400 408 413 414 431 500 501 505; do
    fresh; S.Code = "$c"; send
    [[ "${HL[0]}" == "HTTP/1.1 $c "?* ]] || bad+=" $c='${HL[0]}'"
done
if [[ -z "$bad" ]]; then kt_test_pass "8 reasons"; else kt_test_fail "$bad"; fi

kt_test_start "ContentType '' → no Content-Type line; a custom type is sent as given"
fresh; S.ContentType = ""; send; a=" ${HL[*]} "
fresh; S.ContentType = "application/json"; send; b=" ${HL[*]} "
if [[ "$a" != *"Content-Type"* && "$b" == *" Content-Type: application/json "* ]]; then kt_test_pass "absent / custom"; else kt_test_fail "a=($a) b=($b)"; fi

kt_test_start "Attach's BANNER: '' → no Server line; 'my/1' → 'Server: my/1'"
fresh; send 0 ""; a=" ${HL[*]} "
fresh; send 0 "my/1"; b=" ${HL[*]} "
if [[ "$a" != *"Server:"* && "$b" == *" Server: my/1 "* ]]; then kt_test_pass "absent / custom"; else kt_test_fail "a=($a) b=($b)"; fi

# ===========================================================================
kt_test_section "2. HEAD, 1xx, 204, 304"
# ===========================================================================

kt_test_start "HEAD (ISHEAD 1): the GET head with Content-Length of the body, and no body"
fresh; S.Content = "hello"; send 1
if [[ "$BODY" == "" && " ${HL[*]} " == *" Content-Length: 5 "* && "$OUT" == *"$CRLF$CRLF" ]]; then kt_test_pass "CL 5, empty body"; else kt_test_fail "body='$BODY' head=(${HL[*]})"; fi

kt_test_start "204 and 100: no body, no Content-Length, no Content-Type"
bad=""
for c in 204 100 101 103; do
    fresh; S.Content = "ignored"; S.Code = "$c"; send
    [[ "$BODY" == "" && " ${HL[*]} " != *"Content-Length"* && " ${HL[*]} " != *"Content-Type"* && " ${HL[*]} " == *" Connection: close "* ]] || bad+=" $c:(${HL[*]})body='$BODY'"
done
if [[ -z "$bad" ]]; then kt_test_pass "204 100 101 103"; else kt_test_fail "$bad"; fi

kt_test_start "304: no body; Content-Length kept"
fresh; S.Content = "abc"; S.Code = 304; send
if [[ "$BODY" == "" && " ${HL[*]} " == *" Content-Length: 3 "* && "${HL[0]}" == "HTTP/1.1 304 Not Modified" ]]; then kt_test_pass "CL 3, no body"; else kt_test_fail "body='$BODY' head=(${HL[*]})"; fi

# ===========================================================================
kt_test_section "3. custom headers and their refusals (fact 14)"
# ===========================================================================

kt_test_start "custom headers go out in insertion order between Content-Type and Content-Length; a re-set keeps its place"
fresh
S.SetCustomHeader X-B 1; S.SetCustomHeader X-A 2; S.SetCustomHeader x-b 3
send
headof "HTTP/1.1 200 OK" "Server: kcl-thttpserver" "Content-Type: text/plain; charset=utf-8" "X-B: 3" "X-A: 2" "Content-Length: 0" "Connection: close"
if [[ "$HEAD" == "$EXP" ]]; then kt_test_pass "X-B: 3, X-A: 2"; else kt_test_fail "head='${HEAD//$CR/<CR>}'"; fi

kt_test_start "GetCustomHeader: case-insensitive; absent → rc 1 + ''; '' → rc 2 + ''"
get S GetCustomHeader X-b; a="$GRC:$G"; get S GetCustomHeader x-none; b="$GRC:$G"; get S GetCustomHeader ""; c="$GRC:$G"
if [[ "$a" == "0:3" && "$b" == "1:" && "$c" == "2:" ]]; then kt_test_pass "3, miss, malformed"; else kt_test_fail "$a | $b | $c"; fi

kt_test_start "SetCustomHeader refuses (rc 2, nothing stored): non-token names, CR/LF in the value, server-owned names"
fresh
bad=""
refuse() { local rc=0; S.SetCustomHeader "$1" "$2" || rc=$?; [[ $rc -eq 2 ]] || bad+=" [$1|${2//$CR/<CR>}]=$rc"; }
refuse "" v; refuse "Bad Name" v; refuse "a:b" v; refuse "X(y)" v; refuse "X-A" "a${CR}b"; refuse "X-A" "a${LF}Set-Cookie: x=1"
refuse "X-A" "a${CRLF}b"; refuse Content-Length 5; refuse CONNECTION keep-alive; refuse date x; refuse Server x; refuse content-type text/html
send
[[ "$OUT" != *"Set-Cookie"* && "$OUT" != *"X-A"* && "$OUT" != *"keep-alive"* && " ${HL[*]} " != *"Content-Type: text/html"* ]] || bad+=" leaked:(${HL[*]})"
get S GetCustomHeader X-A; [[ $GRC -eq 1 ]] || bad+=" X-A stored"
if [[ -z "$bad" ]]; then kt_test_pass "12 refusals, nothing sent"; else kt_test_fail "$bad"; fi

kt_test_start "a value may hold any other text: '\$(touch pwn)', backticks, %s — sent verbatim, nothing runs"
cd "$TMP" || exit 1
rm -f "$TMP/pwn"
fresh; S.SetCustomHeader X-H '$(touch pwn)`touch pwn`%s\x41'; send
cd "$SCRIPT_DIR" || exit 1
if [[ " ${HL[*]} " == *' X-H: $(touch pwn)`touch pwn`%s\x41 '* && ! -e "$TMP/pwn" ]]; then kt_test_pass "verbatim, no pwn"; else kt_test_fail "head=(${HL[*]}) pwn=$([[ -e $TMP/pwn ]] && echo yes)"; fi

# ===========================================================================
kt_test_section "4. validation at send → 500 with the default head (fact 14)"
# ===========================================================================

expect500() {   # TITLE — S is prepared; send and check the default 500 head
    local title="$1"; shift
    S.SetCustomHeader X-C dropped
    send "$@"
    headof "HTTP/1.1 500 Internal Server Error" "Server: kcl-thttpserver" "Content-Type: text/plain; charset=utf-8" "Content-Length: 0" "Connection: close"
    get S Code
    if [[ $SRC -eq 0 && "$HEAD" == "$EXP" && "$BODY" == "" && "$G" == "500" && "$OUT" != *"Set-Cookie"* ]]; then
        kt_test_pass "$title → default 500"
    else
        kt_test_fail "[$title] rc=$SRC code=$G head='${HEAD//$CR/<CR>}' body='${BODY:0:40}'"
    fi
}
for case in "ct-cr" "ct-lf" "ctext-cr" "ctext-lf" "code-99" "code-abc" "code-600" "code-empty" "code-space" "code-neg" "banner-cr"; do
    kt_test_start "validation: $case"
    fresh; S.Content = "never sent"
    case "$case" in
        ct-cr)      S.ContentType = "text/html${CR}Set-Cookie: x=1" ;;
        ct-lf)      S.ContentType = "text/html${LF}Set-Cookie: x=1" ;;
        ctext-cr)   S.CodeText = "OK${CR}Set-Cookie: x=1" ;;
        ctext-lf)   S.CodeText = "OK${LF}Set-Cookie: x=1" ;;
        code-99)    S.Code = 99 ;;
        code-abc)   S.Code = abc ;;
        code-600)   S.Code = 600 ;;
        code-empty) S.Code = "" ;;
        code-space) S.Code = "2 00" ;;
        code-neg)   S.Code = -200 ;;
    esac
    if [[ "$case" == "banner-cr" ]]; then expect500 "$case" 0 "srv${CRLF}Set-Cookie: x=1"; else expect500 "$case"; fi
done

kt_test_start "an invalid response gives exactly ONE kk.debug line under VERBOSE_KKLASS=debug, none without"
fresh; S.Code = 99; send; quiet="$(<"$TMP/send.err")"
fresh; S.Code = 99; VERBOSE_KKLASS=debug; send; unset VERBOSE_KKLASS
loud="$(<"$TMP/send.err")"
nl=0; while IFS= read -r l; do nl=$(( nl + 1 )); done <<< "$loud"
if [[ -z "$quiet" && -n "$loud" && $nl -eq 1 ]]; then kt_test_pass "debug: '$loud'"; else kt_test_fail "quiet='$quiet' loud='$loud' lines=$nl"; fi

# ===========================================================================
kt_test_section "5. SendContent state, Attach, Write, SendRedirect"
# ===========================================================================

kt_test_start "SendContent twice: the second is rc 1 and writes nothing; ContentSent 1"
fresh; S.Content = "once"
fd=""; exec {fd}>"$TMP/twice"
S.Attach "$fd" 0
r1=0; S.SendContent || r1=$?
s1=$(wc -c < "$TMP/twice")
r2=0; S.SendContent 2>"$TMP/twice.err" || r2=$?
exec {fd}>&-
s2=$(wc -c < "$TMP/twice"); get S ContentSent
if [[ $r1 -eq 0 && $r2 -eq 1 && $s1 -eq $s2 && "$G" == "1" && ! -s "$TMP/twice.err" ]]; then kt_test_pass "0 then 1, $s1 bytes, silent"; else kt_test_fail "r1=$r1 r2=$r2 size $s1→$s2 sent='$G'"; fi

kt_test_start "SendContent before Attach: rc 1, silent, ContentSent stays 0"
fresh; r=0; S.SendContent 2>"$TMP/na.err" || r=$?; get S ContentSent
if [[ $r -eq 1 && "$G" == "0" && ! -s "$TMP/na.err" ]]; then kt_test_pass "rc 1"; else kt_test_fail "rc=$r sent='$G'"; fi

kt_test_start "Attach refuses a malformed call with rc 2: fd abc / -1 / '', ISHEAD 2 / x"
fresh; bad=""
for args in "abc 0" "-1 0" "5 2" "5 x"; do read -r -a A <<< "$args"; r=0; S.Attach "${A[@]}" || r=$?; [[ $r -eq 2 ]] || bad+=" [$args]=$r"; done
r=0; S.Attach "" || r=$?; [[ $r -eq 2 ]] || bad+=" ['']=$r"
r=0; S.Attach || r=$?; [[ $r -eq 2 ]] || bad+=" [none]=$r"
if [[ -z "$bad" ]]; then kt_test_pass "6 refusals"; else kt_test_fail "$bad"; fi

kt_test_start "Write appends its arguments (joined by one space) verbatim — '-n' and '%s' are data"
fresh; S.Write a b; S.Write c; S.Write -n; S.Write " %s\\n"
get S Content
if [[ "$G" == 'a bc-n %s\n' ]]; then kt_test_pass "'$G'"; else kt_test_fail "'$G'"; fi

kt_test_start "SendRedirect URL: Code 302 + Location, not sent yet; sending gives 'HTTP/1.1 302 Found' + 'Location: URL'"
fresh; r=0; S.SendRedirect "/next?a=1" || r=$?
get S Code; c="$G"; get S GetCustomHeader location; l="$G"; get S ContentSent; s="$G"
send
if [[ $r -eq 0 && "$c" == "302" && "$l" == "/next?a=1" && "$s" == "0" && "${HL[0]}" == "HTTP/1.1 302 Found" && " ${HL[*]} " == *" Location: /next?a=1 "* ]]; then
    kt_test_pass "302 Found, Location"
else
    kt_test_fail "rc=$r code=$c loc='$l' sent=$s head=(${HL[*]})"
fi

kt_test_start "SendRedirect URL 301 → 'HTTP/1.1 301 Moved Permanently'; 307 and 308 accepted"
fresh; S.SendRedirect /p 301; send; a="${HL[0]}"
fresh; r7=0; S.SendRedirect /p 307 || r7=$?; fresh; r8=0; S.SendRedirect /p 308 || r8=$?
if [[ "$a" == "HTTP/1.1 301 Moved Permanently" && $r7 -eq 0 && $r8 -eq 0 ]]; then kt_test_pass "301, 307, 308"; else kt_test_fail "'$a' r7=$r7 r8=$r8"; fi

kt_test_start "SendRedirect refuses (rc 2, Code unchanged): code 200 / abc / 400, URL '' / with CR / with LF"
fresh; bad=""
for args in "/p|200" "/p|abc" "/p|400" "|302" "/p${CR}x|302" "/p${LF}Set-Cookie: x|302"; do
    u="${args%|*}"; c="${args##*|}"
    r=0; S.SendRedirect "$u" "$c" || r=$?
    [[ $r -eq 2 ]] || bad+=" [${args//$CR/<CR>}]=$r"
done
get S Code; [[ "$G" == "200" ]] || bad+=" Code='$G'"
get S GetCustomHeader Location; [[ $GRC -eq 1 ]] || bad+=" Location stored"
if [[ -z "$bad" ]]; then kt_test_pass "6 refusals"; else kt_test_fail "$bad"; fi

kt_test_start "delete frees S_hdr / S_hdrn; a new S starts with no custom header and the defaults"
fresh; S.SetCustomHeader X-Z 1; S.Code = 404
before=0; for a in S_hdr S_hdrn; do declare -p "$a" >/dev/null 2>&1 && before=$(( before + 1 )); done
S.delete
left="$(declare -p S_hdr S_hdrn 2>/dev/null)"
THttpResponse.new S
get S GetCustomHeader X-Z; a="$GRC"; get S Code; c="$G"
if [[ $before -eq 2 && -z "$left" && "$a" == "1" && "$c" == "200" ]]; then kt_test_pass "2 arrays existed, freed, clean"; else kt_test_fail "before=$before left='${left:0:100}' X-Z rc=$a Code=$c"; fi

# ===========================================================================
kt_test_section "6. properties from inside a handler-like member (fact 19)"
# ===========================================================================

class THsProbe002
    public
        constructor Create
        proc Handle
end
THsProbe002.Create() { :; }
THsProbe002.Handle() {
    local resp="$1" wrc=0
    RESULT=stale; $resp.Code;        HP_CODE="$RESULT"
    RESULT=stale; $resp.ContentSent; HP_SENT="$RESULT"
    RESULT=stale; $resp.ContentType; HP_CT="$RESULT"
    $resp.Code = 404
    RESULT=stale; $resp.Code;        HP_CODE2="$RESULT"
    $resp.ContentSent = 1 || wrc=$?
    HP_WRC="$wrc"
    RESULT=stale; $resp.ContentSent; HP_SENT2="$RESULT"
}
build THsProbe002
fresh
THsProbe002.new HP
HP.Handle S >"$TMP/hp.out" 2>"$TMP/hp.err"
hpout="$(<"$TMP/hp.out")"; hperr="$(<"$TMP/hp.err")"

kt_test_start "\$resp.Code / ContentSent / ContentType print NOTHING and set RESULT; \$resp.Code = 404 writes"
if [[ -z "$hpout" && "$HP_CODE" == "200" && "$HP_SENT" == "0" && "$HP_CT" == "text/plain; charset=utf-8" && "$HP_CODE2" == "404" ]]; then
    kt_test_pass "silent: 200 0 text/plain; then 404"
else
    kt_test_fail "stdout='${hpout:0:60}' code=$HP_CODE sent=$HP_SENT ct='$HP_CT' code2=$HP_CODE2"
fi

kt_test_start "\$resp.ContentSent = 1 is rc 1, unchanged, with kklass's own line only"
if [[ "$HP_WRC" == "1" && "$HP_SENT2" == "0" && "$hperr" == "Error: Property 'ContentSent' is read-only" ]]; then kt_test_pass "rc 1, 0"; else kt_test_fail "wrc=$HP_WRC sent2=$HP_SENT2 stderr='$hperr'"; fi
HP.delete

# ===========================================================================
kt_test_section "7. Date: English and UTC whatever LANG/LC_ALL/TZ (fact 15)"
# ===========================================================================

kt_test_start "under LC_ALL=ru_RU.UTF-8 TZ=JST-9 the Date is English, GMT and equals the UTC clock; LC_ALL/TZ untouched"
out="$(UNIT="$UNIT" LC_ALL=ru_RU.UTF-8 LANG=ru_RU.UTF-8 TZ=JST-9 timeout 180 "$BASH" -c '
source "$UNIT"
b="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M")"
THttpResponse.new S
exec {fd}>"$1"
S.Attach "$fd" 0
S.SendContent
exec {fd}>&-
a="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M")"
printf "%s\n%s\n%s|%s|%s\n" "$b" "$a" "$LC_ALL" "$TZ" "$(date +%H)"
' _ "$TMP/date.cap" 2>"$TMP/date.err" </dev/null)"
before="$(sed -n 1p <<< "$out")"; after="$(sed -n 2p <<< "$out")"; env3="$(sed -n 3p <<< "$out")"
dline="$(grep -a '^Date: ' "$TMP/date.cap" | tr -d '\r')"
dmin="${dline#Date: }"; dmin="${dmin%:?? GMT}"
if [[ "$dline" =~ $DATE_RE && ( "$dmin" == "$before" || "$dmin" == "$after" ) && "$env3" == "ru_RU.UTF-8|JST-9|"* && ! -s "$TMP/date.err" ]]; then
    kt_test_pass "'$dline' (UTC $before), env kept"
else
    kt_test_fail "date='$dline' utc='$before'/'$after' env='$env3' err='$(<"$TMP/date.err")'"
fi

kt_test_start "the UTC hour differs from the child's JST local hour (so the check above is not vacuous)"
lh="${env3##*|}"; uh="${dmin: -5:2}"
if [[ -n "$lh" && -n "$uh" && "$lh" != "$uh" ]]; then kt_test_pass "local $lh vs UTC $uh"; else kt_test_fail "local '$lh' UTC '$uh'"; fi

# ===========================================================================
kt_test_section "8. SIGPIPE, deterministic (fact 3)"
# ===========================================================================

kt_test_start "a reader that is already gone: SendContent rc 1, nothing on stderr, ContentSent 1, the shell alive"
out="$(UNIT="$UNIT" timeout 180 "$BASH" -c '
source "$UNIT"
trap "" PIPE
exec {fd}> >(exec true)
pid=$!
wait "$pid"
THttpResponse.new S
S.Content = "hello, nobody"
S.Attach "$fd" 0
rc=0; S.SendContent || rc=$?
S.ContentSent; sent="$RESULT"
printf "alive rc=%s sent=%s" "$rc" "$sent"
' 2>"$TMP/pipe.err" </dev/null)"; crc=$?
if [[ $crc -eq 0 && "$out" == "alive rc=1 sent=1" && ! -s "$TMP/pipe.err" ]]; then kt_test_pass "$out"; else kt_test_fail "child rc=$crc out='$out' err='$(<"$TMP/pipe.err")'"; fi

kt_test_start "(why the server ignores PIPE) without the trap the same write kills the shell (rc 141)"
out="$(UNIT="$UNIT" timeout 180 "$BASH" -c '
source "$UNIT"
exec {fd}> >(exec true)
pid=$!
wait "$pid"
THttpResponse.new S
S.Attach "$fd" 0
S.SendContent
printf "alive"
' 2>/dev/null </dev/null)"; crc=$?
if [[ $crc -eq 141 && -z "$out" ]]; then kt_test_pass "rc 141, no 'alive'"; else kt_test_fail "rc=$crc out='$out'"; fi
