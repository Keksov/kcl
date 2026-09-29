#!/bin/bash
# demo_oop.sh — the same application as demo.sh, written the object way
# (PLAN §2.11: "what a descendant implements"):
#
#   TMyApp : THttpApplication   overrides Initialize (inherited Initialize "$@"
#                               first, then its own objects and routes) and
#                               Destroy (frees them, then inherited); its own
#                               methods Home / Count / Quit are route handlers
#   TKvController               a plain class whose METHODS are routes — this
#                               is where state lives (a TDictionary it owns)
#   THelloRoute                 a route class, one instance per request
#   TAuthServer : THttpServer   overrides HandleRequest — a bearer token is
#                               required for everything but GET /; it passes
#                               the arguments on: inherited HandleRequest "$@"
#                               — plugged in through App.ServerClass (D9)
#
#   bash kcl/thttpserver/examples/demo_oop.sh --port=8080 --token=s3cret
#   DEMO_TOKEN=s3cret bash kcl/thttpserver/examples/demo_oop.sh -p 8080
#
#   curl --noproxy '*' http://127.0.0.1:8080/                       # public
#   curl --noproxy '*' http://127.0.0.1:8080/count                  # 401
#   curl --noproxy '*' -H 'Authorization: Bearer s3cret' http://127.0.0.1:8080/count
#   curl --noproxy '*' -H 'Authorization: Bearer s3cret' -X PUT --data-binary v \
#        http://127.0.0.1:8080/kv/k
#   curl --noproxy '*' -H 'Authorization: Bearer s3cret' -X POST http://127.0.0.1:8080/quit
#
# Options: --port=N / -p N, --address=A, --token=T (else $DEMO_TOKEN; with
# neither, no token is required). netcat as in demo.sh: $KCL_NC, else `nc` on
# PATH, else /c/bin/msys64/usr/bin/nc.exe.
#
# Handlers (functions or methods) declare every variable `local`, and a method
# override passes its arguments on (`inherited HandleRequest "$@"` — a bare
# `inherited` in a method passes NONE).

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/../thttpapplication.sh"
source "$DEMO_DIR/../../tdictionary/tdictionary.sh"

if [[ -z "${KCL_NC:-}" ]] && ! type -P nc >/dev/null && [[ -x /c/bin/msys64/usr/bin/nc.exe ]]; then
    export KCL_NC=/c/bin/msys64/usr/bin/nc.exe
fi

# ---------------------------------------------------------------------------
# TAuthServer — cross-cutting logic in a descendant SERVER.
# ---------------------------------------------------------------------------
class TAuthServer : THttpServer
    public
        var Token
        override proc HandleRequest
end
TAuthServer.HandleRequest() {
    local path auth rc=0
    $1.PathInfo
    path="$RESULT"
    if [[ -n "$Token" && "$path" != / ]]; then
        auth=""
        if $1.GetHeader authorization; then
            auth="$RESULT"
        fi
        if [[ "$auth" != "Bearer $Token" ]]; then
            $2.Code = 401
            $2.SetCustomHeader WWW-Authenticate 'Bearer realm="kcl demo"'
            $2.Write "401: send 'Authorization: Bearer <token>'"
            return 0
        fi
    fi
    inherited HandleRequest "$@" || rc=$?
    return "$rc"
}
build TAuthServer

# ---------------------------------------------------------------------------
# TKvController — its methods are registered as INST.METHOD routes.
# ---------------------------------------------------------------------------
class TKvController
    public
        constructor Create
        destructor  Destroy
        proc GetItem
        proc PutItem
        proc DeleteItem
    private
        var _store
end
TKvController.Create() {
    _store="${__inst__}_store"
    TDictionary.new "$_store"
}
TKvController.Destroy() {
    "$_store.delete"
}
TKvController.GetItem() {
    local key
    $1.RouteParam key
    key="$RESULT"
    if "$_store.TryGetValue" "$key"; then
        $2.Write "$RESULT"
    else
        $2.Code = 404
        $2.Write "no such key: $key"
    fi
}
TKvController.PutItem() {
    local key value
    $1.RouteParam key
    key="$RESULT"
    $1.Content
    value="$RESULT"
    if "$_store.ContainsKey" "$key"; then
        $2.Code = 200
    else
        $2.Code = 201
    fi
    "$_store.AddOrSetValue" "$key" "$value"
    $2.Write "stored $key"
}
TKvController.DeleteItem() {
    local key
    $1.RouteParam key
    key="$RESULT"
    if ! "$_store.ContainsKey" "$key"; then
        $2.Code = 404
        $2.Write "no such key: $key"
        return 0
    fi
    "$_store.Remove" "$key"
    $2.Write "deleted $key"
}
build TKvController

# ---------------------------------------------------------------------------
# THelloRoute — a route class (one object per request, DATA in RouteData).
# ---------------------------------------------------------------------------
class THelloRoute : THttpRouteObject
    public
        override proc HandleRequest
end
THelloRoute.HandleRequest() {
    local who
    $1.RouteParam name
    who="$RESULT"
    $2.Write "$RouteData, $who!"
}
build THelloRoute

# ---------------------------------------------------------------------------
# TMyApp — the application: options, the owned controller, the routes.
# ---------------------------------------------------------------------------
class TMyApp : THttpApplication
    public
        constructor Create
        override proc Initialize
        destructor Destroy
        proc Home
        proc Count
        proc Quit
    private
        var _kv
        var _hits
end
TMyApp.Create() {
    inherited
    _kv=""
    _hits=0
}
TMyApp.Initialize() {
    local token srv
    ServerClass=TAuthServer
    inherited Initialize "$@" || return
    $this.GetOptionValue "" token
    token="$RESULT"
    if [[ -z "$token" ]]; then
        token="${DEMO_TOKEN:-}"
    fi
    $this.Server
    srv="$RESULT"
    "$srv.Token" = "$token"
    "$srv.OnLog" = access_log
    _hits=0
    # A method of THIS object is registered as "$__inst__.Method", never as
    # "$this.Method": kklass rewrites the text `$this.NAME` of a member body
    # into its call form, quoted or not — the router would get 'App.call Home'.
    if [[ -z "$_kv" ]]; then
        _kv="${__inst__}_kv"
        TKvController.new "$_kv"
        $this.RegisterRoute /             GET    "$__inst__.Home" || return 2
        $this.RegisterRoute /count        GET    "$__inst__.Count" || return 2
        $this.RegisterRoute /kv/:key      GET    "$_kv.GetItem" || return 2
        $this.RegisterRoute /kv/:key      PUT    "$_kv.PutItem" || return 2
        $this.RegisterRoute /kv/:key      DELETE "$_kv.DeleteItem" || return 2
        $this.RegisterRoute /hello/:name  GET    THelloRoute 0 Hello || return 2
        $this.RegisterRoute /quit         POST   "$__inst__.Quit" || return 2
    fi
    return 0
}
TMyApp.Destroy() {
    if [[ -n "$_kv" ]]; then
        "$_kv.delete"
    fi
    inherited
}
TMyApp.Home() {
    $2.Write 'kcl/thttpserver demo, object style: GET /count, GET|PUT|DELETE /kv/KEY, GET /hello/NAME, POST /quit
(everything but this page needs "Authorization: Bearer <token>" when a token is set)
'
}
TMyApp.Count() {
    _hits=$(( _hits + 1 ))
    $2.Write "$_hits"
}
TMyApp.Quit() {
    $this.Terminate
    $2.Write "bye"
}
build TMyApp

access_log() { printf '%s\n' "$2"; }

TMyApp.new App "$@"
if ! App.Initialize; then
    printf 'usage: %s [--port=N | -p N] [--address=A] [--token=T]   (N: 1-65535)\n' "${0##*/}" >&2
    App.delete
    exit 2
fi
App.Address; demo_addr="$RESULT"
App.Port; demo_port="$RESULT"
if [[ "$demo_addr" != 127.* ]]; then
    printf 'warning: listening on %s\n' "$demo_addr" >&2
fi
printf 'kcl demo (object style): http://%s:%s/   (POST /quit or Ctrl-C to stop)\n' "$demo_addr" "$demo_port"

demo_rc=0
App.Run || demo_rc=$?
if (( demo_rc != 0 )); then
    App.Server
    "$RESULT.LastError"
    printf 'kcl demo: the server stopped: %s\n' "$RESULT" >&2
fi
App.delete
exit "$demo_rc"
