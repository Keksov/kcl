#!/bin/bash
# thttprouter.sh — THttpRouteObject and THttpRouter for kcl/thttpserver
# (PLAN.md §1.3, §2.4, §2.11). A kcl addition with its own names; FPC fcl-web
# (httproute.pp: THTTPRouter, TRouteObject) is a design reference only.
#
#   THttpRouter.new Router
#   Router.RegisterRoute /                  home                # 2 args: METHOD = ALL
#   Router.RegisterRoute /kv/:key     GET   kvGet               # a function
#   Router.RegisterRoute /count       GET   Hits.Next           # INST.METHOD
#   Router.RegisterRoute /hello/:name GET   THelloRoute 0 DATA  # a route class
#   Router.RegisterRoute /x           GET   notFound 1          # the GET default route
#   Router.RouteRequest REQ RESP      # Before → handler → After; 404/405 set Code
#
# REGISTRATION (PLAN §2.4). With 2 arguments PATTERN HANDLER (METHOD ALL);
# with 3 to 5 the 2nd is ALWAYS METHOD: PATTERN METHOD HANDLER [ISDEFAULT
# [DATA]]. METHOD ∈ GET POST PUT DELETE OPTIONS HEAD TRACE PATCH ALL, ISDEFAULT
# 0/1, DATA an opaque string kept verbatim. The HANDLER is resolved ONCE, here:
#   1. a CLASS deriving from THttpRouteObject whose abstract flag
#      (${CLASS}_class_abstract, the one .new checks — D8) is not 1. Per
#      request: CLASS.new __ths_route_obj, RouteData = DATA, HandleRequest REQ
#      RESP, delete. A still-abstract class (no HandleRequest) is refused with
#      nothing printed and no constructor run;
#   2. INST.METHOD — INST a live instance, METHOD a METHOD of its class (not a
#      property wrapper such as INST.SomeVar, not .delete/.call): called
#      INST.METHOD REQ RESP DATA; the object's state persists;
#   3. a FUNCTION — called FN REQ RESP DATA.
# Anything else is rc 2 (malformed); a second default route for one METHOD is
# rc 1 (a conflict).
#
# PATTERNS. Constant segments compare literally and case-sensitively (PathInfo
# is not percent-decoded); `:name` takes one NON-EMPTY segment; a trailing
# `*name` takes the rest after the `/` before it, `/` included, possibly empty
# (bare `:` / `*` capture nothing). The leading `/` is optional, a trailing `/`
# is significant. A `*` anywhere but at the start of the LAST segment is rc 2.
# The full table is pinned (and parsed) in tests/003_Router.sh.
#
# PARAMETER DECODING (review R1). Matching runs on the RAW PathInfo (which
# itself stays undecoded), so an encoded `%2F` never splits a segment. Each
# CAPTURED value is then percent-decoded with path rules before
# SetRouteParam: `%XX` → the byte, `+` stays `+`, an invalid `%G1` or a
# truncated `%4` stays literal, a received backslash is data; a `*rest` value
# is decoded as a whole (`%2F` → `/`). `%00` in any captured value → Code 400,
# the handler is not run (AfterRequest still is), rc 0. FindRoute only
# matches, it does not decode.
#
# MATCHING. Routes are tried in registration order; the first whose pattern
# matches and whose METHOD is the request's (or ALL) wins. HEAD falls back to
# the GET route of a matching pattern (C13; the response's ISHEAD drops the
# body). No pattern matches → the default route of the method (HEAD: of HEAD,
# else of GET), else the ALL default, its pattern ignored (FPC's fallback; a
# default route also matches its own pattern as an ordinary route); none →
# Code 404. A pattern matches but no method → Code 405 + `Allow:` (registration
# order, HEAD right after GET whenever GET is allowed). The router SETS the
# response; the server sends it.
#
# ROUTEREQUEST REQ RESP. BeforeRequest REQ RESP → (unless it failed or already
# sent) the handler → AfterRequest REQ RESP. rc: the first non-zero of Before /
# handler / After, else 0 (404/405 are answers, rc 0). A handler's non-zero rc
# with nothing sent becomes 500 in the server (P2). An empty hook is skipped; a
# hook that is not a handler name of a defined function is rc 2 before anything
# runs; a registered function / INST.METHOD that no longer exists is rc 2 at
# dispatch. A route object: a live __ths_route_obj left by an aborted pass is
# deleted first; a failing constructor's rc is returned (HandleRequest not
# run); the object is deleted whatever HandleRequest returned.
#
# HANDLERS run inside the router's member frame, where each router property
# (BeforeRequest, AfterRequest, RouteCount) is a nameref — a handler declares
# every variable `local` (PLAN §2.11, C25).
#
# STORAGE. Per-instance indexed arrays `${inst}_pat` (normalized pattern),
# `_met`, `_hnd`, `_kind` (class | method | function), `_def` (0/1) and
# `_rdat` (DATA), one element per route, allocated in Create and freed in
# Destroy. kklass's own `${inst}` data array is never touched (C10).
#
# NO FORKS on the request path (RouteRequest, FindRoute): builtins and
# parameter expansion only. Proved by tests/003 §8.

# Re-source guard (kcl README §1.4).
if [[ -n "${_THS_THTTPROUTER_SOURCED:-}" ]]; then
    return
fi
declare -g _THS_THTTPROUTER_SOURCED=1

# Locale self-heal (kcl README §1.6).
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

THTTPROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THTTPROUTER_DIR/../../kklass/kklass_pascal.sh"
source "$THTTPROUTER_DIR/thttpmessage.sh"

# ---------------------------------------------------------------------------
# File-scope constants (never `static var`: kcl README §1.1).
# ---------------------------------------------------------------------------

# The METHOD values RegisterRoute accepts (FindRoute: the same minus ALL).
declare -g __THS_ROUTE_METHODS=' GET POST PUT DELETE OPTIONS HEAD TRACE PATCH ALL '

# A handler name: a function / class, or INST.METHOD (PLAN §2.4); an instance
# name. Used unquoted on the right of `=~`; kept file-scope so a regex never
# has to survive `build`'s declare -f round trip.
declare -g __THS_HANDLER_RE='^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)?$'
declare -g __THS_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'

# The instance name every route object is created under, one per request.
declare -g __THS_ROUTE_OBJ='__ths_route_obj'

# ---------------------------------------------------------------------------
# File-scope helpers. They read and write the CALLER's `__ths_*` locals
# (bash scopes locals dynamically). Fork-free.
# ---------------------------------------------------------------------------

# ths._routeMatch PATTERN PATH — rc 0 when PATH matches PATTERN; the captured
# parameters replace the caller's __ths_pn (names) / __ths_pv (values).
ths._routeMatch() {
    local __ths_p="${1#/}" __ths_s="${2#/}" __ths_ps __ths_ss
    __ths_pn=()
    __ths_pv=()
    while :; do
        if [[ "$__ths_p" == \** ]]; then
            if [[ -n "${__ths_p#\*}" ]]; then
                __ths_pn+=("${__ths_p#\*}")
                __ths_pv+=("$__ths_s")
            fi
            return 0
        fi
        __ths_ps="${__ths_p%%/*}"
        __ths_ss="${__ths_s%%/*}"
        if [[ "$__ths_ps" == :* ]]; then
            if [[ -z "$__ths_ss" ]]; then
                return 1
            fi
            if [[ -n "${__ths_ps#:}" ]]; then
                __ths_pn+=("${__ths_ps#:}")
                __ths_pv+=("$__ths_ss")
            fi
        elif [[ "$__ths_ps" != "$__ths_ss" ]]; then
            return 1
        fi
        if [[ "$__ths_p" == */* ]]; then
            if [[ "$__ths_s" != */* ]]; then
                return 1
            fi
            __ths_p="${__ths_p#*/}"
            __ths_s="${__ths_s#*/}"
        elif [[ "$__ths_s" == */* ]]; then
            return 1
        else
            return 0
        fi
    done
}

# ths._routeFind ROUTER PATH METHOD — the routing decision, into the caller's
# locals: __ths_idx (the route index, '' if none), __ths_st (0 | 404 | 405),
# __ths_allow (the Allow value for 405) and __ths_pn / __ths_pv (the matched
# route's parameters; empty for a default-route fallback).
ths._routeFind() {
    local -n __ths_fP="${1}_pat" __ths_fM="${1}_met" __ths_fD="${1}_def"
    local __ths_path="$2" __ths_m="$3" __ths_i __ths_n __ths_mm
    local __ths_get="" __ths_seen=" " __ths_want
    local -a __ths_gpn=() __ths_gpv=()
    __ths_n=${#__ths_fP[@]}
    __ths_idx=""
    __ths_st=404
    __ths_allow=""
    for (( __ths_i = 0; __ths_i < __ths_n; __ths_i++ )); do
        if ! ths._routeMatch "${__ths_fP[__ths_i]}" "$__ths_path"; then
            continue
        fi
        __ths_mm="${__ths_fM[__ths_i]}"
        if [[ "$__ths_mm" == ALL || "$__ths_mm" == "$__ths_m" ]]; then
            __ths_idx="$__ths_i"
            __ths_st=0
            return 0
        fi
        if [[ "$__ths_m" == HEAD && "$__ths_mm" == GET && -z "$__ths_get" ]]; then
            __ths_get="$__ths_i"
            __ths_gpn=("${__ths_pn[@]}")
            __ths_gpv=("${__ths_pv[@]}")
        fi
        if [[ "$__ths_seen" != *" $__ths_mm "* ]]; then
            __ths_seen+="$__ths_mm "
            __ths_allow+=", $__ths_mm"
            if [[ "$__ths_mm" == GET && "$__ths_seen" != *" HEAD "* ]]; then
                __ths_seen+="HEAD "
                __ths_allow+=", HEAD"
            fi
        fi
    done
    if [[ -n "$__ths_get" ]]; then
        __ths_idx="$__ths_get"
        __ths_st=0
        __ths_pn=("${__ths_gpn[@]}")
        __ths_pv=("${__ths_gpv[@]}")
        __ths_allow=""
        return 0
    fi
    __ths_pn=()
    __ths_pv=()
    if [[ -n "$__ths_allow" ]]; then
        __ths_allow="${__ths_allow#, }"
        __ths_st=405
        return 0
    fi
    # No pattern matched: the default route of the method (HEAD: of HEAD,
    # then GET), then of ALL.
    local -a __ths_order=("$__ths_m" ALL)
    if [[ "$__ths_m" == HEAD ]]; then
        __ths_order=(HEAD GET ALL)
    fi
    for __ths_want in "${__ths_order[@]}"; do
        for (( __ths_i = 0; __ths_i < __ths_n; __ths_i++ )); do
            if [[ "${__ths_fD[__ths_i]}" == 1 && "${__ths_fM[__ths_i]}" == "$__ths_want" ]]; then
                __ths_idx="$__ths_i"
                __ths_st=0
                return 0
            fi
        done
    done
    return 0
}

# ths._decodeParams — percent-decodes every captured value in the caller's
# __ths_pv in place, with PATH rules (`ths._decode RAW path`: `+` stays `+`,
# an invalid or truncated escape stays literal, a backslash is data), under a
# local LC_ALL=C so the result is the exact bytes. A `*rest` value is decoded
# as a whole (`%2F` → `/`). rc 1 if a value holds `%00` (review R1).
ths._decodeParams() {
    local LC_ALL=C __ths_j __ths_dec
    for (( __ths_j = 0; __ths_j < ${#__ths_pv[@]}; __ths_j++ )); do
        if [[ "${__ths_pv[__ths_j]}" == *%* ]]; then
            if ! ths._decode "${__ths_pv[__ths_j]}" path; then
                return 1
            fi
            __ths_pv[__ths_j]="$__ths_dec"
        fi
    done
    return 0
}

# ths._hookOk NAME — rc 0 when NAME is '' (no hook) or a handler name of a
# defined function (a plain function or an INST.METHOD wrapper).
ths._hookOk() {
    if [[ -z "$1" ]]; then
        return 0
    fi
    if [[ "$1" =~ $__THS_HANDLER_RE ]] && declare -F "$1" >/dev/null; then
        return 0
    fi
    return 1
}

# ===========================================================================
# THttpRouteObject — the base of a route class (FPC's TRouteObject). One
# instance per request; the router assigns RouteData, then calls
# HandleRequest REQ RESP. Abstract: a descendant must override HandleRequest.
# The destructor is empty ON PURPOSE, so descendants may chain with a bare
# `inherited` (C9).
# ===========================================================================
class THttpRouteObject
    public
        var RouteData
        constructor Create
        destructor  Destroy
        abstract proc HandleRequest
end

THttpRouteObject.Create() {
    RouteData=""
}

THttpRouteObject.Destroy() {
    :
}

build THttpRouteObject

# ===========================================================================
# THttpRouter
# ===========================================================================
class THttpRouter
    public
        var BeforeRequest
        var AfterRequest
        property RouteCount read GetRouteCount
        constructor Create
        destructor  Destroy
        proc RegisterRoute
        func GetRouteCount
        proc RouteRequest
        func FindRoute
end

THttpRouter.Create() {
    BeforeRequest=""
    AfterRequest=""
    declare -ga "${__inst__}_pat=()" "${__inst__}_met=()" "${__inst__}_hnd=()" \
                "${__inst__}_kind=()" "${__inst__}_def=()" "${__inst__}_rdat=()"
}

THttpRouter.Destroy() {
    unset -v "${__inst__}_pat" "${__inst__}_met" "${__inst__}_hnd" \
             "${__inst__}_kind" "${__inst__}_def" "${__inst__}_rdat"
}

# RegisterRoute PATTERN HANDLER | PATTERN METHOD HANDLER [ISDEFAULT [DATA]]
# rc 0 registered · rc 1 a second default route for METHOD · rc 2 malformed.
THttpRouter.RegisterRoute() {
    local __ths_pat="${1:-}" __ths_m=ALL __ths_h __ths_d=0 __ths_dat=""
    local __ths_pp __ths_last __ths_kind __ths_in __ths_me __ths_cls __ths_v __ths_x __ths_ok
    local __ths_i
    if (( $# < 2 || $# > 5 )); then
        kk.debug "Error: THttpRouter.RegisterRoute: usage: PATTERN HANDLER, or PATTERN METHOD HANDLER [ISDEFAULT [DATA]]"
        return 2
    fi
    if (( $# == 2 )); then
        __ths_h="$2"
    else
        __ths_m="$2"
        __ths_h="$3"
        if (( $# >= 4 )); then
            __ths_d="$4"
        fi
        if (( $# == 5 )); then
            __ths_dat="$5"
        fi
    fi
    if [[ -z "$__ths_m" || "$__ths_m" == *[!A-Z]* || "$__THS_ROUTE_METHODS" != *" $__ths_m "* ]]; then
        kk.debug "Error: THttpRouter.RegisterRoute: '$__ths_m' is not a route method"
        return 2
    fi
    if [[ "$__ths_d" != 0 && "$__ths_d" != 1 ]]; then
        kk.debug "Error: THttpRouter.RegisterRoute: ISDEFAULT must be 0 or 1"
        return 2
    fi

    # The pattern: '*' only at the start of the last segment.
    __ths_pp="${__ths_pat#/}"
    __ths_last="${__ths_pp##*/}"
    if [[ "$__ths_pp" == */* && "${__ths_pp%/*}" == *\** ]] || [[ "${__ths_last#\*}" == *\** ]]; then
        kk.debug "Error: THttpRouter.RegisterRoute: '*' is allowed only at the start of the last segment of '$__ths_pat'"
        return 2
    fi

    # The handler, resolved once.
    if [[ ! "$__ths_h" =~ $__THS_HANDLER_RE ]]; then
        kk.debug "Error: THttpRouter.RegisterRoute: '$__ths_h' is not a handler name"
        return 2
    fi
    if [[ "$__ths_h" == *.* ]]; then
        __ths_in="${__ths_h%%.*}"
        __ths_me="${__ths_h#*.}"
        __ths_v="${__ths_in}_class"
        __ths_cls="${!__ths_v:-}"
        __ths_ok=0
        if [[ -n "$__ths_cls" ]] && declare -F "$__ths_h" >/dev/null; then
            local -n __ths_cm="${__ths_cls}_class_methods" __ths_cp="${__ths_cls}_class_properties"
            for __ths_x in "${__ths_cm[@]}"; do
                if [[ "$__ths_x" == "$__ths_me" ]]; then
                    __ths_ok=1
                    break
                fi
            done
            for __ths_x in "${__ths_cp[@]}"; do
                if [[ "$__ths_x" == "$__ths_me" ]]; then
                    __ths_ok=0
                    break
                fi
            done
        fi
        if (( ! __ths_ok )); then
            kk.debug "Error: THttpRouter.RegisterRoute: '$__ths_h' is not a method of a live instance"
            return 2
        fi
        __ths_kind=method
    elif kk._class_derives_from "$__ths_h" THttpRouteObject; then
        __ths_v="${__ths_h}_class_abstract"
        if [[ "${!__ths_v:-0}" == 1 ]] || ! declare -F "$__ths_h.new" >/dev/null; then
            kk.debug "Error: THttpRouter.RegisterRoute: route class '$__ths_h' is abstract (no HandleRequest)"
            return 2
        fi
        __ths_kind=class
    elif declare -F "$__ths_h" >/dev/null; then
        __ths_kind=function
    else
        kk.debug "Error: THttpRouter.RegisterRoute: '$__ths_h' is no function, route class or INST.METHOD"
        return 2
    fi

    local -n __ths_P="${__inst__}_pat" __ths_M="${__inst__}_met" __ths_H="${__inst__}_hnd" \
             __ths_K="${__inst__}_kind" __ths_D="${__inst__}_def" __ths_R="${__inst__}_rdat"
    if [[ "$__ths_d" == 1 ]]; then
        for (( __ths_i = 0; __ths_i < ${#__ths_P[@]}; __ths_i++ )); do
            if [[ "${__ths_D[__ths_i]}" == 1 && "${__ths_M[__ths_i]}" == "$__ths_m" ]]; then
                kk.debug "Error: THttpRouter.RegisterRoute: a default route for $__ths_m exists already"
                return 1
            fi
        done
    fi
    __ths_P+=("/$__ths_pp")
    __ths_M+=("$__ths_m")
    __ths_H+=("$__ths_h")
    __ths_K+=("$__ths_kind")
    __ths_D+=("$__ths_d")
    __ths_R+=("$__ths_dat")
    return 0
}

# RouteCount — the number of registered routes.
THttpRouter.GetRouteCount() {
    local -n __ths_P="${__inst__}_pat"
    kk._return "${#__ths_P[@]}"
    return 0
}

# FindRoute PATH METHOD — RESULT = the index of the route that would serve it
# (a default-route fallback included); rc 1 + RESULT '' + REPLY 404|405 when
# none; rc 2 for a malformed call (METHOD not an HTTP method; ALL is not one).
THttpRouter.FindRoute() {
    local __ths_idx __ths_st __ths_allow
    local -a __ths_pn=() __ths_pv=()
    if (( $# != 2 )) || [[ -z "$2" || "$2" == ALL || "$2" == *[!A-Z]* || "$__THS_ROUTE_METHODS" != *" $2 "* ]]; then
        kk.debug "Error: THttpRouter.FindRoute: usage: PATH METHOD"
        kk._return ""
        return 2
    fi
    ths._routeFind "$__inst__" "$1" "$2"
    if [[ -z "$__ths_idx" ]]; then
        REPLY="$__ths_st"
        kk.debug "Error: THttpRouter.FindRoute: $2 '$1' → $__ths_st"
        kk._return ""
        return 1
    fi
    kk._return "$__ths_idx"
    return 0
}

# RouteRequest REQ RESP — BeforeRequest → the handler (or Code 404 / 405 +
# Allow) → AfterRequest. Never sends. rc: the first non-zero of the three, or
# 0; rc 2 for a malformed call (REQ not a parsed THttpRequest, RESP not a
# THttpResponse, a hook that is not a defined handler).
THttpRouter.RouteRequest() {
    local __ths_req="${1:-}" __ths_resp="${2:-}" __ths_v __ths_rc=0 __ths_hrc=0
    local __ths_idx __ths_st __ths_allow __ths_i __ths_m __ths_path __ths_h __ths_dat
    local -a __ths_pn=() __ths_pv=()
    if (( $# != 2 )) || [[ ! "$__ths_req" =~ $__THS_NAME_RE || ! "$__ths_resp" =~ $__THS_NAME_RE ]]; then
        kk.debug "Error: THttpRouter.RouteRequest: usage: REQ RESP"
        return 2
    fi
    __ths_v="${__ths_req}_class"
    if ! kk._class_derives_from "${!__ths_v:-}" THttpRequest; then
        kk.debug "Error: THttpRouter.RouteRequest: '$__ths_req' is not a THttpRequest"
        return 2
    fi
    __ths_v="${__ths_resp}_class"
    if ! kk._class_derives_from "${!__ths_v:-}" THttpResponse; then
        kk.debug "Error: THttpRouter.RouteRequest: '$__ths_resp' is not a THttpResponse"
        return 2
    fi
    "$__ths_req.Method"
    __ths_m="$RESULT"
    if [[ -z "$__ths_m" ]]; then
        kk.debug "Error: THttpRouter.RouteRequest: '$__ths_req' holds no parsed request"
        return 2
    fi
    if ! ths._hookOk "$BeforeRequest" || ! ths._hookOk "$AfterRequest"; then
        kk.debug "Error: THttpRouter.RouteRequest: BeforeRequest/AfterRequest is not a defined handler"
        return 2
    fi

    if [[ -n "$BeforeRequest" ]]; then
        "$BeforeRequest" "$__ths_req" "$__ths_resp" || __ths_rc=$?
    fi
    "$__ths_resp.ContentSent"
    if (( __ths_rc == 0 )) && [[ "$RESULT" != 1 ]]; then
        "$__ths_req.PathInfo"
        __ths_path="$RESULT"
        ths._routeFind "$__inst__" "$__ths_path" "$__ths_m"
        if [[ "$__ths_st" == 404 ]]; then
            "$__ths_resp.Code" = 404
        elif [[ "$__ths_st" == 405 ]]; then
            "$__ths_resp.Code" = 405
            "$__ths_resp.SetCustomHeader" Allow "$__ths_allow"
        elif ! ths._decodeParams; then
            # %00 in a captured value (review R1): an answer, not a failure.
            "$__ths_resp.Code" = 400
        else
            for (( __ths_i = 0; __ths_i < ${#__ths_pn[@]}; __ths_i++ )); do
                "$__ths_req.SetRouteParam" "${__ths_pn[__ths_i]}" "${__ths_pv[__ths_i]}"
            done
            local -n __ths_H="${__inst__}_hnd" __ths_K="${__inst__}_kind" __ths_R="${__inst__}_rdat"
            __ths_h="${__ths_H[__ths_idx]}"
            __ths_dat="${__ths_R[__ths_idx]}"
            if [[ "${__ths_K[__ths_idx]}" == class ]]; then
                __ths_v="${__THS_ROUTE_OBJ}_class"
                if [[ -n "${!__ths_v:-}" ]]; then
                    "$__THS_ROUTE_OBJ.delete"
                fi
                "$__ths_h.new" "$__THS_ROUTE_OBJ" || __ths_hrc=$?
                if (( __ths_hrc == 0 )); then
                    "$__THS_ROUTE_OBJ.RouteData" = "$__ths_dat"
                    "$__THS_ROUTE_OBJ.HandleRequest" "$__ths_req" "$__ths_resp" || __ths_hrc=$?
                fi
                if [[ -n "${!__ths_v:-}" ]]; then
                    "$__THS_ROUTE_OBJ.delete"
                fi
            elif declare -F "$__ths_h" >/dev/null; then
                "$__ths_h" "$__ths_req" "$__ths_resp" "$__ths_dat" || __ths_hrc=$?
            else
                # The function was unset, or the instance deleted, after registration.
                kk.debug "Error: THttpRouter.RouteRequest: handler '$__ths_h' no longer exists"
                __ths_hrc=2
            fi
            __ths_rc="$__ths_hrc"
        fi
    fi

    # AfterRequest is read again: a handler may (wrongly) have assigned it.
    if [[ -n "$AfterRequest" ]]; then
        if ! ths._hookOk "$AfterRequest"; then
            kk.debug "Error: THttpRouter.RouteRequest: AfterRequest '$AfterRequest' is not a defined handler"
            if (( __ths_rc == 0 )); then
                __ths_rc=2
            fi
        else
            __ths_hrc=0
            "$AfterRequest" "$__ths_req" "$__ths_resp" || __ths_hrc=$?
            if (( __ths_rc == 0 )); then
                __ths_rc="$__ths_hrc"
            fi
        fi
    fi
    return "$__ths_rc"
}

build THttpRouter
