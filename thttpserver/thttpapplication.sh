#!/bin/bash
# thttpapplication.sh — THttpApplication : TCustomApplication for
# kcl/thttpserver (PLAN.md §1.3, §2.7, §2.10, §2.11). A kcl addition with its
# own names; FPC fcl-web (fphttpapp.pp: THTTPApplication) is a design
# reference only.
#
#   source kcl/thttpserver/thttpapplication.sh
#   THttpApplication.new App "$@"          # "$@": the option parser sees argv
#   App.RegisterRoute /hello/:name GET hello   # routes before Initialize: fine
#   App.Initialize || exit 2               # --port=N / -p N, --address=A
#   App.Run                                # blocks until /quit, TERM, INT ...
#   App.delete
#
# THE LOOP IS TCustomApplication's. Run (overridden) wraps `inherited Run "$@"`
# in Server.BeginServe / Server.EndServe, so the application path gets exactly
# the handling the plain THttpServer.Serve has (C11): PIPE ignored, INT/TERM
# turned into a stop at a safe point, the transport shut down, the caller's
# traps restored. The inherited loop is `repeat DoRun until Terminated`, and
# one DoRun is one Server.ServeOne:
#   ServeOne rc 0 (handled) / rc 1 (idle tick, a client that left, a signal)
#       → DoRun rc 0 — NEVER non-zero for an expected condition: the inherited
#         Run hands a non-zero DoRun to HandleException, which prints
#         `Exception: …` unconditionally;
#   ServeOne rc 2 (transport fatal) → Terminate, DoRun rc 0; Run then answers
#       rc 1 (the server's LastError says why);
#   Server.Stopping (Terminate from a handler or OnAcceptIdle, Active = false,
#       a signal) or MaxRequests reached → Terminate.
# A route that calls `App.Terminate` ends the application after that response.
#
# OPTIONS come from the inherited FPC-ported parser, which only sees the argv
# given to Create — hence `THttpApplication.new App "$@"` (C24). Initialize
# reads `--port=N` / `-p N` and `--address=A` (the long form needs `=`: FPC's
# `--port 8080` has no value); an option wins over a value assigned before
# Initialize, the resolved value is written back to Port / Address.
#
# OWNED OBJECTS. AppRouter (`${inst}_router`, a THttpRouter) is created by
# Create, so routes may be registered before Initialize. Server
# (`${inst}_server`) is created by Initialize as `ServerClass.new` (D9: a
# descendant server plugs in; a class that does not derive from THttpServer,
# or is abstract, is rc 2) and wired: Router, Port, Address. A second
# Initialize replaces the server (rc 1 while it is serving). Destroy frees
# both — WITHOUT `inherited`: TCustomApplication has no destructor (C9).
#
# THE PROPERTY RULE (§1.3). Server and AppRouter are read-only properties;
# Port and Address are read/write properties (the application's own caller
# reads them back — the demo prints its URL from them); ServerClass is a plain
# var, only written from outside. Handlers run inside the application's,
# server's and router's frames, where every field of the three is a nameref —
# a handler declares every variable `local` (C25): a bare `Port=…` or
# `Title=…` there writes the application's property.
#
# NO FORKS on the request path: DoRun adds builtins only to ServeOne's (proved
# by tests/006 over TReplayTransport).

# Re-source guard (kcl README §1.4).
if [[ -n "${_THS_THTTPAPPLICATION_SOURCED:-}" ]]; then
    return
fi
declare -g _THS_THTTPAPPLICATION_SOURCED=1

# Locale self-heal (kcl README §1.6).
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

THTTPAPPLICATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THTTPAPPLICATION_DIR/../../kklass/kklass_pascal.sh"
source "$THTTPAPPLICATION_DIR/thttpserver.sh"
source "$THTTPAPPLICATION_DIR/../tcustomapplication/tcustomapplication.sh"

class THttpApplication : TCustomApplication
    public
        property Port      read Port    write Port
        property Address   read Address write Address
        var ServerClass
        property Server    read _server
        property AppRouter read _router
        constructor Create
        destructor  Destroy
        override proc Initialize
        proc RegisterRoute
        override proc Run
        override proc DoRun
        override proc Terminate
    private
        var _server
        var _router
end

# Create [ARG…] — the inherited constructor stores the argv for the option
# parser; then the defaults and the owned router.
THttpApplication.Create() {
    local __ths_v="${__inst__}_router_class"
    inherited
    Port=8080
    Address=127.0.0.1
    ServerClass=THttpServer
    _server=""
    _router="${__inst__}_router"
    if [[ -n "${!__ths_v:-}" ]]; then
        "$_router.delete"
    fi
    THttpRouter.new "$_router"
}

# Destroy — the server (its own destructor ends a serve still in progress)
# and the router. No `inherited`: TCustomApplication declares no destructor.
THttpApplication.Destroy() {
    if [[ -n "$_server" ]] && declare -F "$_server.delete" >/dev/null; then
        "$_server.delete"
    fi
    if [[ -n "$_router" ]] && declare -F "$_router.delete" >/dev/null; then
        "$_router.delete"
    fi
    _server=""
    _router=""
}

# Initialize — inherited Initialize (Terminated = false); options → Port /
# Address; ServerClass checked and instantiated; the server wired. rc 2 (one
# kk.debug line, nothing created) for a port that is not an integer 1–65535,
# an empty address or a ServerClass that is not a concrete THttpServer
# descendant; rc 1 while the current server is serving.
THttpApplication.Initialize() {
    local __ths_p="$Port" __ths_a="$Address" __ths_cls="$ServerClass" __ths_srv="${__inst__}_server" __ths_v
    inherited Initialize "$@"
    if "$__inst__.HasOption" p port; then
        "$__inst__.GetOptionValue" p port
        __ths_p="$RESULT"
    fi
    if "$__inst__.HasOption" "" address; then
        "$__inst__.GetOptionValue" "" address
        __ths_a="$RESULT"
    fi
    if ! kk.isInt "$__ths_p" __ths_p || (( __ths_p < 1 || __ths_p > 65535 )); then
        kk.debug "Error: THttpApplication.Initialize: the port must be an integer 1-65535 (--port=N, -p N)"
        return 2
    fi
    if [[ -z "$__ths_a" ]]; then
        kk.debug "Error: THttpApplication.Initialize: the address is empty (--address=A)"
        return 2
    fi
    __ths_v="${__ths_cls}_class_abstract"
    if [[ ! "$__ths_cls" =~ $__THS_NAME_RE ]] || ! kk._class_derives_from "$__ths_cls" THttpServer \
       || [[ "${!__ths_v:-0}" == 1 ]] || ! declare -F "$__ths_cls.new" >/dev/null; then
        kk.debug "Error: THttpApplication.Initialize: ServerClass '$__ths_cls' is not a concrete THttpServer descendant"
        return 2
    fi
    if [[ -n "$_server" ]] && declare -F "$_server.delete" >/dev/null; then
        "$_server.Active"
        if [[ "$RESULT" == 1 ]]; then
            kk.debug "Error: THttpApplication.Initialize: the server is serving"
            return 1
        fi
        "$_server.delete"
    fi
    _server=""
    __ths_v="${__ths_srv}_class"
    if [[ -n "${!__ths_v:-}" ]]; then
        "$__ths_srv.delete"
    fi
    "$__ths_cls.new" "$__ths_srv" || {
        kk.debug "Error: THttpApplication.Initialize: $__ths_cls.new failed"
        return 2
    }
    Port="$__ths_p"
    Address="$__ths_a"
    "$__ths_srv.Router" = "$_router"
    "$__ths_srv.Port" = "$__ths_p"
    "$__ths_srv.Address" = "$__ths_a"
    _server="$__ths_srv"
    return 0
}

# RegisterRoute … — THttpRouter.RegisterRoute on AppRouter (PLAN §2.4): rc 0,
# rc 1 a second default route, rc 2 malformed.
THttpApplication.RegisterRoute() {
    "$_router.RegisterRoute" "$@"
}

# Run — Server.BeginServe; the inherited `repeat DoRun until Terminated`;
# Server.EndServe. rc 0 · rc 1 the server recorded a transport fatal
# (Server.LastError) · rc 2 no Initialize yet · BeginServe's own rc 1 / 2
# when it refuses (already serving, a bad number).
THttpApplication.Run() {
    local __ths_srv="$_server" __ths_le __ths_r=0
    if [[ -z "$__ths_srv" ]] || ! declare -F "$__ths_srv.BeginServe" >/dev/null; then
        kk.debug "Error: THttpApplication.Run: no server — Initialize first"
        return 2
    fi
    "$__ths_srv.BeginServe" || return $?
    inherited Run "$@" || __ths_r=$?
    "$__ths_srv.LastError"
    __ths_le="$RESULT"
    "$__ths_srv.EndServe"
    if [[ -n "$__ths_le" ]]; then
        return 1
    fi
    return "$__ths_r"
}

# DoRun — one Server.ServeOne (see the header). rc 0 always while a server
# exists; rc 2 (and Terminate) without one.
THttpApplication.DoRun() {
    local __ths_srv="$_server" __ths_r=0 __ths_max
    if [[ -z "$__ths_srv" ]] || ! declare -F "$__ths_srv.ServeOne" >/dev/null; then
        kk.debug "Error: THttpApplication.DoRun: no server — Initialize first"
        "$__inst__.Terminate"
        return 2
    fi
    "$__ths_srv.ServeOne" || __ths_r=$?
    if (( __ths_r == 2 )); then
        "$__inst__.Terminate"
        return 0
    fi
    "$__ths_srv.Stopping"
    if [[ "$RESULT" == 1 ]]; then
        "$__inst__.Terminate"
        return 0
    fi
    "$__ths_srv.MaxRequests"
    __ths_max="$RESULT"
    if [[ "$__ths_max" != 0 ]]; then
        "$__ths_srv.RequestCount"
        if (( RESULT >= __ths_max )); then
            "$__inst__.Terminate"
        fi
    fi
    return 0
}

# Terminate [EXITCODE] — inherited Terminate (Terminated = true, EXITCODE),
# then Server.Terminate (stop after the current request). The inherited rc is
# kept (rc 1 for a non-integer EXITCODE — Terminated is set all the same).
THttpApplication.Terminate() {
    local __ths_rc=0
    inherited Terminate "$@" || __ths_rc=$?
    if [[ -n "$_server" ]] && declare -F "$_server.Terminate" >/dev/null; then
        "$_server.Terminate"
    fi
    return "$__ths_rc"
}

build THttpApplication
