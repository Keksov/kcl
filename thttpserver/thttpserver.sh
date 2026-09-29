#!/bin/bash
# thttpserver.sh — the entry point of kcl/thttpserver (PLAN.md §1.2).
#
# Sources thttpmessage.sh (THttpRequest, THttpResponse) and thttprouter.sh
# (THttpRouteObject, THttpRouter). Own content so far: the transport seam —
# THttpTransport (abstract) and TReplayTransport (the fork-free test double).
# TNetcatTransport and THttpServer arrive in P2.
#
#   TReplayTransport.new T
#   T.AddRequestFile req1.txt; T.AddRequestFile req2.txt
#   T.Accept 0 10                 # rc 0: InFd reads req1.txt, OutFd writes a capture
#   T.InFd; in=$RESULT; T.OutFd; out=$RESULT
#   ...                           # parse from $in, answer to $out
#   T.CloseConnection
#   T.ResponseFile 0              # RESULT = the path of the captured response

# Re-source guard (kcl README §1.4).
if [[ -n "${_THS_THTTPSERVER_SOURCED:-}" ]]; then
    return
fi
declare -g _THS_THTTPSERVER_SOURCED=1

# Locale self-heal (kcl README §1.6).
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

THTTPSERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THTTPSERVER_DIR/../../kklass/kklass_pascal.sh"
source "$THTTPSERVER_DIR/thttpmessage.sh"
source "$THTTPSERVER_DIR/thttprouter.sh"

# ===========================================================================
# THttpTransport — the network seam (PLAN §2.5). The server only knows
# InFd / OutFd / FirstLine / TimedOut / RemoteAddress / LastError, all
# read-only properties over PROTECTED fields a descendant transport sets.
#
#   Accept IDLE_MS REQUEST_TIMEOUT_S → rc 0 a connection · 1 an idle tick ·
#                                      2 fatal (LastError says why)
#   CloseConnection                  → close the current connection's fds
#   Shutdown                         → stop listening; release everything
#
# The destructor is empty ON PURPOSE: every descendant may chain with a bare
# `inherited` (a destructor whose parent has none gets rc 127, PLAN C9).
# ===========================================================================
class THttpTransport
    public
        property InFd          read _inFd
        property OutFd         read _outFd
        property FirstLine     read _firstLine
        property TimedOut      read _timedOut
        property RemoteAddress read _remoteAddress
        property LastError     read _lastError
        constructor Create
        destructor  Destroy
        abstract func Accept
        abstract proc CloseConnection
        abstract proc Shutdown
    protected
        var _inFd
        var _outFd
        var _firstLine
        var _timedOut
        var _remoteAddress
        var _lastError
end

THttpTransport.Create() {
    _inFd=""
    _outFd=""
    _firstLine=""
    _timedOut=0
    _remoteAddress=""
    _lastError=""
}

THttpTransport.Destroy() {
    :
}

build THttpTransport

# ===========================================================================
# TReplayTransport — the test double: no socket, no fork (PLAN §2.5).
#
# Each Accept opens the NEXT added request file on InFd (`exec {fd}<FILE`) and
# a fresh capture file on OutFd (`exec {fd}>CAPTURE`); with none left it is
# rc 2 (LastError set). The capture of the N-th accepted request (0-based) is
# `<request file>.N.out`, reported by `ResponseFile N`. An Accept while a
# connection is still open closes that one first. FirstLine is always '' (the
# parser reads the request line itself), TimedOut 0, RemoteAddress ''.
#
# Per-instance arrays: `${inst}_rqf` (request files, in order) and
# `${inst}_rsf` (capture files, by accept ordinal), freed in Destroy.
# ===========================================================================
class TReplayTransport : THttpTransport
    public
        constructor Create
        destructor  Destroy
        proc AddRequestFile
        func ResponseFile
        override func Accept
        override proc CloseConnection
        override proc Shutdown
    private
        var _next
end

TReplayTransport.Create() {
    inherited
    _next=0
    declare -ga "${__inst__}_rqf=()" "${__inst__}_rsf=()"
}

TReplayTransport.Destroy() {
    kk.call_silent "$__inst__" Shutdown
    unset -v "${__inst__}_rqf" "${__inst__}_rsf"
    inherited
}

# AddRequestFile FILE — one raw request per Accept, in order. rc 2 for '',
# rc 1 for a file that is not a readable regular file.
TReplayTransport.AddRequestFile() {
    local __ths_f="${1:-}"
    if [[ -z "$__ths_f" ]]; then
        kk.debug "Error: TReplayTransport.AddRequestFile: empty file name"
        return 2
    fi
    if [[ ! -f "$__ths_f" || ! -r "$__ths_f" ]]; then
        kk.debug "Error: TReplayTransport.AddRequestFile: '$__ths_f' is not a readable file"
        return 1
    fi
    local -n __ths_q="${__inst__}_rqf"
    __ths_q+=("$__ths_f")
    return 0
}

# ResponseFile INDEX — the capture path of the INDEX-th accepted request
# (0-based); rc 1 for an index that was not accepted (or is not an integer).
TReplayTransport.ResponseFile() {
    local __ths_i="${1:-}"
    local -n __ths_s="${__inst__}_rsf"
    if ! kk.isInt "$__ths_i" __ths_i || (( __ths_i < 0 || __ths_i >= ${#__ths_s[@]} )); then
        kk.debug "Error: TReplayTransport.ResponseFile: no captured response #$__ths_i"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_s[__ths_i]}"
    return 0
}

# Accept IDLE_MS REQUEST_TIMEOUT_S — both ignored (a file never idles and never
# stalls). RESULT = the accept ordinal on rc 0.
TReplayTransport.Accept() {
    local __ths_n="$_next" __ths_f __ths_cap __ths_in="" __ths_out=""
    local -n __ths_q="${__inst__}_rqf" __ths_s="${__inst__}_rsf"
    if [[ -n "$_inFd" || -n "$_outFd" ]]; then
        kk.call_silent "$__inst__" CloseConnection
    fi
    if (( __ths_n >= ${#__ths_q[@]} )); then
        _lastError="TReplayTransport: no request file left"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    __ths_f="${__ths_q[__ths_n]}"
    __ths_cap="$__ths_f.$__ths_n.out"
    if ! { exec {__ths_in}<"$__ths_f"; } 2>/dev/null; then
        _lastError="TReplayTransport: cannot open '$__ths_f'"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    if ! { exec {__ths_out}>"$__ths_cap"; } 2>/dev/null; then
        exec {__ths_in}<&-
        _lastError="TReplayTransport: cannot create '$__ths_cap'"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    _inFd="$__ths_in"
    _outFd="$__ths_out"
    _firstLine=""
    _timedOut=0
    _remoteAddress=""
    __ths_s[__ths_n]="$__ths_cap"
    _next=$(( __ths_n + 1 ))
    kk._return "$__ths_n"
    return 0
}

# CloseConnection — closes InFd and OutFd (if open); rc 0.
TReplayTransport.CloseConnection() {
    local __ths_fd
    if [[ -n "$_inFd" ]]; then
        __ths_fd="$_inFd"
        exec {__ths_fd}<&-
    fi
    if [[ -n "$_outFd" ]]; then
        __ths_fd="$_outFd"
        exec {__ths_fd}>&-
    fi
    _inFd=""
    _outFd=""
    return 0
}

# Shutdown — nothing listens; closes the current connection, if any.
TReplayTransport.Shutdown() {
    kk.call_silent "$__inst__" CloseConnection
    return 0
}

build TReplayTransport
