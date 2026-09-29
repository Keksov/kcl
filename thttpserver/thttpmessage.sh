#!/bin/bash
# thttpmessage.sh — THttpRequest and THttpResponse for kcl/thttpserver
# (PLAN.md §1.3, §2.2, §2.3). A kcl addition with its own names; FPC fcl-web
# (httpdefs.pp: TRequest/TResponse) is a design reference only.
#
#   THttpRequest.new R
#   R.ReadFrom FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE]]   # rc 0, RESULT = status
#   R.Method; R.PathInfo; R.QueryField q; R.GetHeader host   # RESULT, nothing printed
#
#   THttpResponse.new S
#   S.Attach FD ISHEAD [BANNER]; S.Code = 404; S.Write text; S.SendContent
#
# THE PROPERTY RULE (PLAN §1.3, D6/C7). Every field another object reads is a
# PROPERTY: a direct read from another object's member body is silent and sets
# RESULT. A plain `var` of another object read directly PRINTS and leaves RESULT
# stale. THttpRequest's fields are read-only (`property X read _x`): a write is
# rc 1 and kklass prints its own `Error: Property 'X' is read-only` line
# (deviation e). THttpResponse's Code/CodeText/ContentType/Content are
# read/write (`property X read X write X`).
#
# STORAGE. Per-instance arrays, allocated in Create and freed in Destroy
# (kcl README §1.9): request `${inst}_hdr` (assoc: lower-cased name → value),
# `${inst}_hdrn` (lower-cased names in arrival order), `${inst}_qf` (assoc:
# decoded query name → 'v'VALUE, or 'x' for a field rejected because of %00),
# `${inst}_rp` (route params); response `${inst}_hdr` (assoc: lower-cased name →
# value) and `${inst}_hdrn` (names as given, insertion order). `${inst}_data` is
# kklass's own storage and is never touched.
#
# HOSTILE DATA IS DATA (PLAN §2.2). Nothing received is ever eval'ed, used as a
# variable or function name, or put into (( )) / ${!…}. Every assoc WRITE is
# preceded by a non-empty check: an empty assoc key (`a[$k]=1` with k='')
# aborts the whole top-level command in bash (PLAN §1.1). Reads use
# `${h[$k]+x}`. Hostile non-empty keys (`$(touch pwn)`, backticks, `]`, `@`,
# `*`, `a[0]`) are safe in both forms (measured, both bashes).
#
# BYTES. Everything the parser reads, counts or slices runs under
# `local LC_ALL=C`: under C.UTF-8 `${#s}` and `read -n` count CHARACTERS. And a
# kklass `var` is a nameref onto `${inst}_data[name]`, for which bash 5.2.37
# answers `${#var}` = 0 (5.3.9 counts correctly — measured P0), so a length is
# always taken from a LOCAL copy.
#
# NO FORKS on any member here (PLAN §2.1, §4): builtins, parameter expansion,
# `read`, `printf -v` only. Proved by tests/001 §7.

# Re-source guard (kcl README §1.4).
if [[ -n "${_THS_THTTPMESSAGE_SOURCED:-}" ]]; then
    return
fi
declare -g _THS_THTTPMESSAGE_SOURCED=1

# Locale self-heal (kcl README §1.6): character semantics everywhere except the
# regions that pin LC_ALL=C locally.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

THTTPMESSAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THTTPMESSAGE_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# File-scope constants (never `static var`: kcl README §1.1).
#
# __THS_CR / __THS_LF — a CR / LF as a VALUE. `build` re-creates every member
# body from `declare -f` output, and an inline ANSI-C CR literal in a body does
# not survive that round trip (tpipe P1 finding): stripping a trailing CR that
# way silently becomes `${x%''}`, which strips nothing.
# __THS_BS / __THS_BS2 — one / two backslashes, for the quoted replacement that
# doubles every `\` before the `%b` decode (a quoted replacement is also immune
# to `patsub_replacement`).
# ---------------------------------------------------------------------------
declare -g __THS_CR __THS_LF
printf -v __THS_CR '\r'
printf -v __THS_LF '\n'
declare -g __THS_BS='\' __THS_BS2='\\'

# A glob that matches any string holding a character outside the RFC 9110
# `tchar` set. Used unquoted on the right of `==` so it stays a pattern; kept
# out of the member bodies so no body carries a `|`.
declare -g __THS_NOTTOKEN='*[!!#$%&'"'"'*+.^_`|~0-9A-Za-z-]*'

# The methods the parser accepts (anything else that is a token → 501).
declare -g __THS_METHODS=' GET POST PUT DELETE OPTIONS HEAD TRACE PATCH '

# Header names the server owns: SetCustomHeader refuses them (PLAN §2.3).
declare -g __THS_OWNED=' content-length connection date server content-type '

# The default Server banner and Content-Type.
declare -g __THS_BANNER='kcl-thttpserver'
declare -g __THS_CTYPE='text/plain; charset=utf-8'

# Reason phrases (RFC 9110 §15). A code outside the table and with no CodeText
# is sent with an empty reason: `HTTP/1.1 299 ` (the SP is mandatory).
declare -gA __THS_REASON=(
    [100]='Continue' [101]='Switching Protocols' [103]='Early Hints'
    [200]='OK' [201]='Created' [202]='Accepted' [203]='Non-Authoritative Information'
    [204]='No Content' [205]='Reset Content' [206]='Partial Content'
    [300]='Multiple Choices' [301]='Moved Permanently' [302]='Found' [303]='See Other'
    [304]='Not Modified' [307]='Temporary Redirect' [308]='Permanent Redirect'
    [400]='Bad Request' [401]='Unauthorized' [402]='Payment Required' [403]='Forbidden'
    [404]='Not Found' [405]='Method Not Allowed' [406]='Not Acceptable'
    [407]='Proxy Authentication Required' [408]='Request Timeout' [409]='Conflict'
    [410]='Gone' [411]='Length Required' [412]='Precondition Failed'
    [413]='Content Too Large' [414]='URI Too Long' [415]='Unsupported Media Type'
    [416]='Range Not Satisfiable' [417]='Expectation Failed' [421]='Misdirected Request'
    [422]='Unprocessable Content' [426]='Upgrade Required' [428]='Precondition Required'
    [429]='Too Many Requests' [431]='Request Header Fields Too Large'
    [451]='Unavailable For Legal Reasons'
    [500]='Internal Server Error' [501]='Not Implemented' [502]='Bad Gateway'
    [503]='Service Unavailable' [504]='Gateway Timeout' [505]='HTTP Version Not Supported'
)

# ---------------------------------------------------------------------------
# File-scope helpers of the parser. They read and write the CALLER's
# `__ths_*` locals (bash scopes locals dynamically) and run under the caller's
# `local LC_ALL=C`. Fork-free.
# ---------------------------------------------------------------------------

# ths._left DEADLINE_US — the time left, as `S.UUUUUU` in the caller's
# __ths_left; rc 1 when the deadline is spent. `read -t 0` would look like EOF
# and `read -t -1` prints an error, so a spent deadline never reaches `read`.
# EPOCHREALTIME's separator follows the locale (`,` under ru_RU), hence the
# digits-only form.
ths._left() {
    local __ths_us=$(( $1 - ${EPOCHREALTIME//[!0-9]/} ))
    if (( __ths_us <= 0 )); then
        return 1
    fi
    printf -v __ths_left '%d.%06d' $(( __ths_us / 1000000 )) $(( __ths_us % 1000000 ))
    return 0
}

# ths._readLine FD DEADLINE_US — one line into the caller's __ths_line, one
# trailing CR stripped (bare LF accepted). rc 0 a line · 3 longer than 8192
# bytes · 4 deadline / timeout · 5 EOF (nothing, or a partial line).
# `read -n 8194` = 8192 bytes + CR + one byte to detect the overflow; a stray
# NUL inside a line is dropped by `read` itself (measured, both bashes).
ths._readLine() {
    local __ths_r=0 __ths_left
    __ths_line=""
    ths._left "$2" || return 4
    IFS= read -r -n 8194 -t "$__ths_left" -u "$1" __ths_line 2>/dev/null || __ths_r=$?
    if (( __ths_r > 128 )); then
        return 4
    fi
    if (( __ths_r != 0 )); then
        return 5
    fi
    __ths_line="${__ths_line%"$__THS_CR"}"
    if (( ${#__ths_line} > 8192 )); then
        return 3
    fi
    return 0
}

# ths._decode RAW — application/x-www-form-urlencoded decoding into the
# caller's __ths_dec: `+` → space, `%XX` → the byte, an invalid `%G1` or a
# truncated `%4` stays literal. Every `\` is doubled FIRST, so the only escapes
# `%b` ever sees are the `\xHH` built here — a received backslash is data.
# rc 1 on `%00` (a bash string cannot hold NUL: the field is rejected).
ths._decode() {
    local __ths_s="${1//+/ }" __ths_o="" __ths_hx
    __ths_s="${__ths_s//"$__THS_BS"/"$__THS_BS2"}"
    while [[ "$__ths_s" == *%* ]]; do
        __ths_o+="${__ths_s%%\%*}"
        __ths_s="${__ths_s#*\%}"
        __ths_hx="${__ths_s:0:2}"
        if [[ "$__ths_hx" == [0-9A-Fa-f][0-9A-Fa-f] ]]; then
            if [[ "$__ths_hx" == 00 ]]; then
                return 1
            fi
            __ths_o+="${__THS_BS}x${__ths_hx}"
            __ths_s="${__ths_s:2}"
        else
            __ths_o+='%'
        fi
    done
    __ths_o+="$__ths_s"
    printf -v __ths_dec '%b' "$__ths_o"
    return 0
}

# ===========================================================================
# THttpRequest — one parsed request. Filled by ReadFrom; read by handlers.
# ===========================================================================
class THttpRequest
    public
        property Method          read _method
        property URI             read _uri
        property PathInfo        read _pathInfo
        property QueryString     read _queryString
        property ProtocolVersion read _protocolVersion
        property Content         read _content
        property RemoteAddress   read _remoteAddress
        property ContentLength   read GetContentLength
        constructor Create
        destructor  Destroy
        func GetContentLength
        func GetHeader
        proc HasHeader
        func HeaderNames
        func QueryField
        func RouteParam
        proc SetRouteParam
        func ReadFrom
    private
        var _method
        var _uri
        var _pathInfo
        var _queryString
        var _protocolVersion
        var _content
        var _remoteAddress
        proc _reset
end

THttpRequest.Create() {
    _method=""
    _uri=""
    _pathInfo=""
    _queryString=""
    _protocolVersion=""
    _content=""
    _remoteAddress=""
    declare -gA "${__inst__}_hdr=()" "${__inst__}_qf=()" "${__inst__}_rp=()"
    declare -ga "${__inst__}_hdrn=()"
}

THttpRequest.Destroy() {
    unset -v "${__inst__}_hdr" "${__inst__}_hdrn" "${__inst__}_qf" "${__inst__}_rp"
}

# Every field back to empty; the four arrays emptied (kept allocated).
THttpRequest._reset() {
    local -n __ths_h="${__inst__}_hdr" __ths_hn="${__inst__}_hdrn" \
             __ths_q="${__inst__}_qf" __ths_p="${__inst__}_rp"
    _method=""
    _uri=""
    _pathInfo=""
    _queryString=""
    _protocolVersion=""
    _content=""
    _remoteAddress=""
    __ths_h=()
    __ths_hn=()
    __ths_q=()
    __ths_p=()
    return 0
}

# ContentLength — the BYTE length of Content.
THttpRequest.GetContentLength() {
    local __ths_c="$_content"
    local LC_ALL=C
    kk._return "${#__ths_c}"
    return 0
}

# GetHeader NAME — case-insensitive; a repeated header was joined with ', '.
THttpRequest.GetHeader() {
    local __ths_k="${1:-}"
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpRequest.GetHeader: empty header name"
        kk._return ""
        return 2
    fi
    local -n __ths_h="${__inst__}_hdr"
    __ths_k="${__ths_k,,}"
    if [[ -z "${__ths_h[$__ths_k]+x}" ]]; then
        kk.debug "Error: THttpRequest.GetHeader: no header '$__ths_k'"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_h[$__ths_k]}"
    return 0
}

# HasHeader NAME — a predicate: rc 0 present, rc 1 absent (an answer, silent),
# rc 2 for an empty name.
THttpRequest.HasHeader() {
    local __ths_k="${1:-}"
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpRequest.HasHeader: empty header name"
        return 2
    fi
    local -n __ths_h="${__inst__}_hdr"
    __ths_k="${__ths_k,,}"
    if [[ -n "${__ths_h[$__ths_k]+x}" ]]; then
        return 0
    fi
    return 1
}

# HeaderNames OUTARR — the lower-cased names in arrival order (one per name);
# RESULT = count. A malformed or reserved OUTARR is rc 2 and nothing is written.
THttpRequest.HeaderNames() {
    local __ths_o="${1:-}"
    if ! kk._outName "$__ths_o" __ths_ __THS_ \
       || [[ "$__ths_o" == "${__inst__}_hdr" || "$__ths_o" == "${__inst__}_hdrn" \
             || "$__ths_o" == "${__inst__}_qf" || "$__ths_o" == "${__inst__}_rp" ]]; then
        kk.debug "Error: THttpRequest.HeaderNames: unusable output array name '$__ths_o'"
        kk._return ""
        return 2
    fi
    local -n __ths_out="$__ths_o" __ths_hn="${__inst__}_hdrn"
    __ths_out=("${__ths_hn[@]}")
    kk._return "${#__ths_hn[@]}"
    return 0
}

# QueryField NAME — the percent-decoded value of the FIRST occurrence; rc 1 if
# absent or rejected (%00); rc 2 for an empty name.
THttpRequest.QueryField() {
    local __ths_k="${1:-}" __ths_v
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpRequest.QueryField: empty field name"
        kk._return ""
        return 2
    fi
    local -n __ths_q="${__inst__}_qf"
    if [[ -z "${__ths_q[$__ths_k]+x}" ]]; then
        kk.debug "Error: THttpRequest.QueryField: no field '$__ths_k'"
        kk._return ""
        return 1
    fi
    __ths_v="${__ths_q[$__ths_k]}"
    if [[ "$__ths_v" != v* ]]; then
        kk.debug "Error: THttpRequest.QueryField: field '$__ths_k' rejected (%00)"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_v#v}"
    return 0
}

# RouteParam NAME — a value the router captured (`:name`, `*name`).
THttpRequest.RouteParam() {
    local __ths_k="${1:-}"
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpRequest.RouteParam: empty parameter name"
        kk._return ""
        return 2
    fi
    local -n __ths_p="${__inst__}_rp"
    if [[ -z "${__ths_p[$__ths_k]+x}" ]]; then
        kk.debug "Error: THttpRequest.RouteParam: no parameter '$__ths_k'"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_p[$__ths_k]}"
    return 0
}

# SetRouteParam NAME VALUE — the router's use.
THttpRequest.SetRouteParam() {
    local __ths_k="${1:-}"
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpRequest.SetRouteParam: empty parameter name"
        return 2
    fi
    local -n __ths_p="${__inst__}_rp"
    __ths_p[$__ths_k]="${2:-}"
    return 0
}

# ReadFrom FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE]]
#
# Parses one request from FD (PLAN §2.2). rc 0 with the status in RESULT (C20):
#   0                           parsed — the fields are set
#   400 408 413 414 431 501 505 the status to answer (Method … Content stay
#                               empty; RemoteAddress and the headers read so
#                               far are kept)
#   gone                        the client left (EOF): nothing is answered
# rc 2 + RESULT '' for a malformed CALL (FD / DEADLINE_US / MAXBODY not
# integers, FD or MAXBODY negative).
#
# DEADLINE_US is absolute (EPOCHREALTIME in µs). FIRSTLINE, when non-empty, is
# the request line a transport already consumed (a trailing CR is stripped);
# REMOTE lands in RemoteAddress. The checks, in order: the request line (414;
# structure / a control character / a garbage version → 400; the method → 501;
# a target that is not origin-form → 400; the version → 505); every header
# (431 for a line over 8192 bytes or the 101st header; a non-token name,
# obs-fold, no colon, a control character in the value, two different
# Content-Length values → 400); then HTTP/1.1 without Host → 400,
# Transfer-Encoding → 501, a Content-Length that is not plain digits within
# int64 → 400, above MAXBODY → 413 (the body is not read); the body in a
# `read -d '' -n` loop — a NUL is 400 at once.
THttpRequest.ReadFrom() {
    local __ths_fd="${1:-}" __ths_dl="${2:-}" __ths_max="${3:-}"
    if ! kk.isInt "$__ths_fd" __ths_fd || (( __ths_fd < 0 )) \
       || ! kk.isInt "$__ths_dl" __ths_dl \
       || ! kk.isInt "$__ths_max" __ths_max || (( __ths_max < 0 )); then
        kk.debug "Error: THttpRequest.ReadFrom: usage: FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE]]"
        kk._return ""
        return 2
    fi
    local LC_ALL=C
    local __ths_line="" __ths_r=0 __ths_left="" __ths_st=0
    local __ths_m __ths_t __ths_v __ths_rest __ths_sp
    local __ths_n=0 __ths_name __ths_val __ths_ln __ths_len=0
    local __ths_got=0 __ths_need __ths_chunk __ths_body=""
    local __ths_qs __ths_part __ths_k __ths_dec
    local -n __ths_h="${__inst__}_hdr" __ths_hn="${__inst__}_hdrn" __ths_q="${__inst__}_qf"

    kk.call_silent "$__inst__" _reset
    _remoteAddress="${5:-}"

    # ---- the request line --------------------------------------------------
    if [[ -n "${4:-}" ]]; then
        __ths_line="${4%"$__THS_CR"}"
        if (( ${#__ths_line} > 8192 )); then
            kk._return 414
            return 0
        fi
    else
        ths._readLine "$__ths_fd" "$__ths_dl" || __ths_r=$?
        if (( __ths_r == 3 )); then
            kk._return 414
            return 0
        elif (( __ths_r == 4 )); then
            kk._return 408
            return 0
        elif (( __ths_r != 0 )); then
            kk._return gone
            return 0
        fi
    fi
    __ths_sp="${__ths_line//[! ]/}"
    __ths_m="${__ths_line%% *}"
    __ths_rest="${__ths_line#* }"
    __ths_t="${__ths_rest%% *}"
    __ths_v="${__ths_rest#* }"
    if [[ ${#__ths_sp} -ne 2 || -z "$__ths_m" || -z "$__ths_t" || -z "$__ths_v" \
          || "$__ths_line" == *[[:cntrl:]]* ]]; then
        kk._return 400
        return 0
    fi
    if [[ "$__ths_v" != HTTP/[0-9].[0-9] ]]; then
        kk._return 400
        return 0
    fi
    if [[ "$__ths_m" == *[!A-Z]* || "$__THS_METHODS" != *" $__ths_m "* ]]; then
        kk._return 501
        return 0
    fi
    if [[ "$__ths_t" != /* ]]; then
        kk._return 400
        return 0
    fi
    if [[ "$__ths_v" != HTTP/1.[01] ]]; then
        kk._return 505
        return 0
    fi

    # ---- the headers -------------------------------------------------------
    while :; do
        __ths_r=0
        ths._readLine "$__ths_fd" "$__ths_dl" || __ths_r=$?
        if (( __ths_r == 3 )); then
            kk._return 431
            return 0
        elif (( __ths_r == 4 )); then
            kk._return 408
            return 0
        elif (( __ths_r != 0 )); then
            kk._return gone
            return 0
        fi
        if [[ -z "$__ths_line" ]]; then
            break
        fi
        if [[ "$__ths_line" == [[:blank:]]* ]]; then          # obs-fold
            kk._return 400
            return 0
        fi
        __ths_n=$(( __ths_n + 1 ))
        if (( __ths_n > 100 )); then
            kk._return 431
            return 0
        fi
        if [[ "$__ths_line" != *:* ]]; then
            kk._return 400
            return 0
        fi
        __ths_name="${__ths_line%%:*}"
        __ths_val="${__ths_line#*:}"
        if [[ -z "$__ths_name" || "$__ths_name" == $__THS_NOTTOKEN ]]; then
            kk._return 400
            return 0
        fi
        __ths_val="${__ths_val#"${__ths_val%%[![:blank:]]*}"}"
        __ths_val="${__ths_val%"${__ths_val##*[![:blank:]]}"}"
        if [[ "${__ths_val//[[:blank:]]/}" == *[[:cntrl:]]* ]]; then
            kk._return 400
            return 0
        fi
        __ths_ln="${__ths_name,,}"
        if [[ -n "${__ths_h[$__ths_ln]+x}" ]]; then
            if [[ "$__ths_ln" == content-length ]]; then
                if [[ "${__ths_h[$__ths_ln]}" != "$__ths_val" ]]; then
                    kk._return 400
                    return 0
                fi
            else
                __ths_h[$__ths_ln]+=", $__ths_val"
            fi
        else
            __ths_h[$__ths_ln]="$__ths_val"
            __ths_hn+=("$__ths_ln")
        fi
    done

    # ---- what the headers imply ---------------------------------------------
    if [[ "$__ths_v" == HTTP/1.1 && -z "${__ths_h[host]+x}" ]]; then
        kk._return 400
        return 0
    fi
    if [[ -n "${__ths_h[transfer-encoding]+x}" ]]; then
        kk._return 501
        return 0
    fi
    if [[ -n "${__ths_h[content-length]+x}" ]]; then
        __ths_val="${__ths_h[content-length]}"
        if [[ -z "$__ths_val" || "$__ths_val" == *[!0-9]* ]] || ! kk.isInt "$__ths_val" __ths_len; then
            kk._return 400
            return 0
        fi
        if (( __ths_len > __ths_max )); then
            kk._return 413
            return 0
        fi
    fi

    # ---- the body -------------------------------------------------------------
    # `read -d '' -n NEED` stops at NEED bytes or at a NUL: a short chunk with
    # rc 0 IS a NUL (400 at once — `read -N` would drop it and wait for a byte
    # that never comes, PLAN C18).
    while (( __ths_got < __ths_len )); do
        if ! ths._left "$__ths_dl"; then
            kk._return 408
            return 0
        fi
        __ths_need=$(( __ths_len - __ths_got ))
        __ths_chunk=""
        __ths_r=0
        IFS= read -r -d '' -n "$__ths_need" -t "$__ths_left" -u "$__ths_fd" __ths_chunk 2>/dev/null || __ths_r=$?
        __ths_body+="$__ths_chunk"
        __ths_got=$(( __ths_got + ${#__ths_chunk} ))
        if (( __ths_r > 128 )); then
            kk._return 408
            return 0
        fi
        if (( __ths_r != 0 )); then
            kk._return gone
            return 0
        fi
        if (( ${#__ths_chunk} < __ths_need )); then
            kk._return 400
            return 0
        fi
    done

    # ---- accepted: the fields ---------------------------------------------------
    _method="$__ths_m"
    _uri="$__ths_t"
    _protocolVersion="${__ths_v#HTTP/}"
    _pathInfo="${__ths_t%%\?*}"
    if [[ "$__ths_t" == *\?* ]]; then
        _queryString="${__ths_t#*\?}"
    else
        _queryString=""
    fi
    _content="$__ths_body"

    # Query fields: split on '&', then on the first '='; the first occurrence
    # wins; an empty (decoded) name is skipped; a name with %00 is skipped; a
    # value with %00 marks the name rejected.
    __ths_qs="$_queryString"
    while [[ -n "$__ths_qs" ]]; do
        __ths_part="${__ths_qs%%&*}"
        if [[ "$__ths_qs" == *'&'* ]]; then
            __ths_qs="${__ths_qs#*&}"
        else
            __ths_qs=""
        fi
        if [[ -z "$__ths_part" ]]; then
            continue
        fi
        if ! ths._decode "${__ths_part%%=*}"; then
            continue
        fi
        __ths_k="$__ths_dec"
        if [[ -z "$__ths_k" || -n "${__ths_q[$__ths_k]+x}" ]]; then
            continue
        fi
        if [[ "$__ths_part" != *=* ]]; then
            __ths_q[$__ths_k]="v"
        elif ths._decode "${__ths_part#*=}"; then
            __ths_q[$__ths_k]="v$__ths_dec"
        else
            __ths_q[$__ths_k]="x"
        fi
    done

    kk._return 0
    return 0
}

build THttpRequest

# ===========================================================================
# THttpResponse — one response; the handler fills it, the server sends it.
# ===========================================================================
class THttpResponse
    public
        property Code        read Code        write Code
        property CodeText    read CodeText    write CodeText
        property ContentType read ContentType write ContentType
        property Content     read Content     write Content
        property ContentSent read _contentSent
        constructor Create
        destructor  Destroy
        proc Attach
        proc SetCustomHeader
        func GetCustomHeader
        proc Write
        proc SendContent
        proc SendRedirect
    private
        var _fd
        var _head
        var _banner
        var _contentSent
end

THttpResponse.Create() {
    Code=200
    CodeText=""
    ContentType="$__THS_CTYPE"
    Content=""
    _fd=""
    _head=0
    _banner="$__THS_BANNER"
    _contentSent=0
    declare -gA "${__inst__}_hdr=()"
    declare -ga "${__inst__}_hdrn=()"
}

THttpResponse.Destroy() {
    unset -v "${__inst__}_hdr" "${__inst__}_hdrn"
}

# Attach FD [ISHEAD [BANNER]] — the server's use: the output fd, the HEAD flag
# (0/1, default 0) and, when given, the Server banner ('' = no Server line;
# default 'kcl-thttpserver'). A malformed call is rc 2.
THttpResponse.Attach() {
    local __ths_fd="${1:-}" __ths_hd="${2:-0}"
    if ! kk.isInt "$__ths_fd" __ths_fd || (( __ths_fd < 0 )); then
        kk.debug "Error: THttpResponse.Attach: FD must be a non-negative integer"
        return 2
    fi
    if [[ "$__ths_hd" != 0 && "$__ths_hd" != 1 ]]; then
        kk.debug "Error: THttpResponse.Attach: ISHEAD must be 0 or 1"
        return 2
    fi
    _fd="$__ths_fd"
    _head="$__ths_hd"
    if (( $# >= 3 )); then
        _banner="$3"
    fi
    return 0
}

# SetCustomHeader NAME VALUE — rc 2 for a non-token NAME, a CR or LF in VALUE,
# or a server-owned name (Content-Length, Connection, Date, Server,
# Content-Type — use ContentType). A second set of the same name (any case)
# replaces the value and keeps the first position and spelling.
THttpResponse.SetCustomHeader() {
    local __ths_n="${1:-}" __ths_v="${2:-}" __ths_ln
    if [[ -z "$__ths_n" || "$__ths_n" == $__THS_NOTTOKEN ]]; then
        kk.debug "Error: THttpResponse.SetCustomHeader: '$__ths_n' is not a header name"
        return 2
    fi
    if [[ "$__ths_v" == *"$__THS_CR"* || "$__ths_v" == *"$__THS_LF"* ]]; then
        kk.debug "Error: THttpResponse.SetCustomHeader: CR/LF in the value of '$__ths_n'"
        return 2
    fi
    __ths_ln="${__ths_n,,}"
    if [[ "$__THS_OWNED" == *" $__ths_ln "* ]]; then
        kk.debug "Error: THttpResponse.SetCustomHeader: '$__ths_n' is set by the server"
        return 2
    fi
    local -n __ths_h="${__inst__}_hdr" __ths_hn="${__inst__}_hdrn"
    if [[ -z "${__ths_h[$__ths_ln]+x}" ]]; then
        __ths_hn+=("$__ths_n")
    fi
    __ths_h[$__ths_ln]="$__ths_v"
    return 0
}

# GetCustomHeader NAME — case-insensitive; rc 1 absent, rc 2 for ''.
THttpResponse.GetCustomHeader() {
    local __ths_k="${1:-}"
    if [[ -z "$__ths_k" ]]; then
        kk.debug "Error: THttpResponse.GetCustomHeader: empty header name"
        kk._return ""
        return 2
    fi
    local -n __ths_h="${__inst__}_hdr"
    __ths_k="${__ths_k,,}"
    if [[ -z "${__ths_h[$__ths_k]+x}" ]]; then
        kk.debug "Error: THttpResponse.GetCustomHeader: no header '$__ths_k'"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_h[$__ths_k]}"
    return 0
}

# Write TEXT... — appends the arguments, joined by one space, to Content
# verbatim (no newline added). Handlers answer through this, never `echo`.
THttpResponse.Write() {
    local IFS=' '
    Content+="$*"
    return 0
}

# SendRedirect URL [CODE] — sets Code (default 302, must be 300–399), clears
# CodeText and sets the Location header; the server sends (as FPC's
# TResponse.SendRedirect, which only sets). A malformed call is rc 2 and
# changes nothing.
THttpResponse.SendRedirect() {
    local __ths_u="${1:-}" __ths_c="${2:-302}"
    if [[ -z "$__ths_u" || "$__ths_u" == *"$__THS_CR"* || "$__ths_u" == *"$__THS_LF"* ]]; then
        kk.debug "Error: THttpResponse.SendRedirect: empty URL or CR/LF in it"
        return 2
    fi
    if ! kk.isInt "$__ths_c" __ths_c || (( __ths_c < 300 || __ths_c > 399 )); then
        kk.debug "Error: THttpResponse.SendRedirect: CODE must be 300-399"
        return 2
    fi
    local -n __ths_h="${__inst__}_hdr" __ths_hn="${__inst__}_hdrn"
    if [[ -z "${__ths_h[location]+x}" ]]; then
        __ths_hn+=("Location")
    fi
    __ths_h[location]="$__ths_u"
    Code="$__ths_c"
    CodeText=""
    return 0
}

# SendContent — writes the whole response with ONE printf to the attached fd
# (PLAN §2.3):
#   HTTP/1.1 CODE TEXT · Date · Server · Content-Type · custom headers in
#   insertion order · Content-Length (bytes) · Connection: close · blank · body
# 1xx and 204: no body, no Content-Length, no Content-Type; 304 and HEAD: no
# body. A Code that is not an integer in 100–599, or a CR/LF in CodeText,
# ContentType or the banner, is answered 500 with the DEFAULT head (default
# banner and Content-Type, no custom header, empty body) plus one kk.debug
# line — never sent raw; Code/CodeText/ContentType then reflect what was sent.
# rc 1 if already sent, not attached, or the write failed (stderr silenced;
# the caller must have SIGPIPE ignored — the server does, PLAN §2.6).
# ContentSent is 1 after any write attempt.
THttpResponse.SendContent() {
    if [[ "$_contentSent" == 1 ]]; then
        kk.debug "Error: THttpResponse.SendContent: already sent"
        return 1
    fi
    if [[ -z "$_fd" ]]; then
        kk.debug "Error: THttpResponse.SendContent: not attached"
        return 1
    fi
    local __ths_fd="$_fd" __ths_code="$Code" __ths_text="$CodeText" __ths_ct="$ContentType"
    local __ths_banner="$_banner" __ths_body="$Content" __ths_head="$_head"
    local __ths_bad="" __ths_custom=1 __ths_nobody=0 __ths_nolen=0
    local __ths_date __ths_out __ths_nm __ths_i __ths_len
    local -n __ths_h="${__inst__}_hdr" __ths_hn="${__inst__}_hdrn"

    if ! kk.isInt "$__ths_code" __ths_code || (( __ths_code < 100 || __ths_code > 599 )); then
        __ths_bad="Code '$Code' is not 100-599"
    elif [[ "$__ths_text" == *"$__THS_CR"* || "$__ths_text" == *"$__THS_LF"* ]]; then
        __ths_bad="CR/LF in CodeText"
    elif [[ "$__ths_ct" == *"$__THS_CR"* || "$__ths_ct" == *"$__THS_LF"* ]]; then
        __ths_bad="CR/LF in ContentType"
    elif [[ "$__ths_banner" == *"$__THS_CR"* || "$__ths_banner" == *"$__THS_LF"* ]]; then
        __ths_bad="CR/LF in the Server banner"
    fi
    if [[ -n "$__ths_bad" ]]; then
        kk.debug "Error: THttpResponse.SendContent: $__ths_bad - answering 500 with the default head"
        __ths_code=500
        __ths_text=""
        __ths_ct="$__THS_CTYPE"
        __ths_banner="$__THS_BANNER"
        __ths_body=""
        __ths_custom=0
        Code=500
        CodeText=""
        ContentType="$__THS_CTYPE"
    fi
    if [[ -z "$__ths_text" ]]; then
        __ths_text="${__THS_REASON[$__ths_code]:-}"
    fi
    if (( __ths_code < 200 || __ths_code == 204 )); then
        __ths_nobody=1
        __ths_nolen=1
    fi
    if (( __ths_code == 304 || __ths_head == 1 )); then
        __ths_nobody=1
    fi

    LC_ALL=C TZ=UTC0 printf -v __ths_date '%(%a, %d %b %Y %H:%M:%S GMT)T' -1
    __ths_out="HTTP/1.1 $__ths_code $__ths_text$__THS_CR${__THS_LF}Date: $__ths_date$__THS_CR$__THS_LF"
    if [[ -n "$__ths_banner" ]]; then
        __ths_out+="Server: $__ths_banner$__THS_CR$__THS_LF"
    fi
    if (( ! __ths_nolen )) && [[ -n "$__ths_ct" ]]; then
        __ths_out+="Content-Type: $__ths_ct$__THS_CR$__THS_LF"
    fi
    if (( __ths_custom )); then
        for (( __ths_i = 0; __ths_i < ${#__ths_hn[@]}; __ths_i++ )); do
            __ths_nm="${__ths_hn[__ths_i]}"
            __ths_out+="$__ths_nm: ${__ths_h[${__ths_nm,,}]}$__THS_CR$__THS_LF"
        done
    fi
    local LC_ALL=C
    if (( ! __ths_nolen )); then
        __ths_len=${#__ths_body}
        __ths_out+="Content-Length: $__ths_len$__THS_CR$__THS_LF"
    fi
    __ths_out+="Connection: close$__THS_CR$__THS_LF$__THS_CR$__THS_LF"
    if (( ! __ths_nobody )); then
        __ths_out+="$__ths_body"
    fi
    _contentSent=1
    if ! printf '%s' "$__ths_out" 2>/dev/null >&"$__ths_fd"; then
        kk.debug "Error: THttpResponse.SendContent: the write to fd $__ths_fd failed"
        return 1
    fi
    return 0
}

build THttpResponse
