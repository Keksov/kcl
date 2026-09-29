#!/bin/bash
# demo.sh — the kcl/thttpserver showcase (PLAN §2.10): an HTTP application
# built from plain FUNCTIONS and App.RegisterRoute, with objects that live
# across requests. The handlers run in THIS shell, so the counter and the
# key-value store keep their state from one request to the next; only `nc` is
# started per connection.
#
#   bash kcl/thttpserver/examples/demo.sh --port=8080        # or: -p 8080
#
#   curl --noproxy '*' http://127.0.0.1:8080/                 # the route list
#   curl --noproxy '*' http://127.0.0.1:8080/count            # 1, 2, 3, ...
#   curl --noproxy '*' -X PUT --data-binary 'hello' http://127.0.0.1:8080/kv/greeting
#   curl --noproxy '*' http://127.0.0.1:8080/kv/greeting      # hello
#   curl --noproxy '*' -X DELETE http://127.0.0.1:8080/kv/greeting
#   curl --noproxy '*' http://127.0.0.1:8080/hello/world      # Hello, world!
#   curl --noproxy '*' -X POST http://127.0.0.1:8080/quit     # stops the demo
#
# Ctrl-C (INT) or TERM stops it too, after the request in progress. Options:
# --port=N / -p N (default 8080), --address=A (default 127.0.0.1). The store
# has no authentication: --address=0.0.0.0 exposes it to the network (and may
# raise a firewall prompt) — see demo_oop.sh for a token-protected variant.
#
# NETCAT. GNU netcat 0.7.1 is resolved as the tests do: $KCL_NC, else `nc` on
# PATH, else /c/bin/msys64/usr/bin/nc.exe when it exists (bash 5.2.37 from Git
# for Windows has no nc on its PATH; msys64's works by absolute path).
#
# HANDLERS get REQ RESP DATA: read the request with direct calls
# (`$1.RouteParam key; key="$RESULT"` — nothing printed, no fork), answer with
# `$2.Code = 404` / `$2.Write TEXT`; the server sends. They declare EVERY
# variable `local`: they run inside the application's, server's and router's
# frames, where a bare `Port=…` or `Title=…` would write those objects.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEMO_DIR/../thttpapplication.sh"
source "$DEMO_DIR/../../tdictionary/tdictionary.sh"

if [[ -z "${KCL_NC:-}" ]] && ! type -P nc >/dev/null && [[ -x /c/bin/msys64/usr/bin/nc.exe ]]; then
    export KCL_NC=/c/bin/msys64/usr/bin/nc.exe
fi

# ---------------------------------------------------------------------------
# Objects that outlive a request.
# ---------------------------------------------------------------------------

# TCounter — Hits.Next is registered as a route handler (INST.METHOD): the
# router calls it with REQ RESP DATA, and _n survives between requests.
class TCounter
    public
        property Value read _n
        constructor Create
        proc Next
    private
        var _n
end
TCounter.Create() { _n=0; }
TCounter.Next() {
    _n=$(( _n + 1 ))
    $2.Write "$_n"
}
build TCounter

# THelloRoute — a route CLASS: the router creates one instance per request,
# assigns the route's DATA to RouteData, calls HandleRequest REQ RESP, frees it.
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

TCounter.new Hits
TDictionary.new Store

# ---------------------------------------------------------------------------
# Function handlers.
# ---------------------------------------------------------------------------

home() {
    local text
    text='kcl/thttpserver demo: the handlers run in the server shell, so state survives requests.

  GET    /             this list
  GET    /count        a counter object (Hits.Next)
  GET    /kv/KEY       the value stored under KEY (404 if none)
  PUT    /kv/KEY       store the request body under KEY (201 new, 200 replaced)
  DELETE /kv/KEY       remove KEY (404 if none)
  GET    /hello/NAME   a route class, one object per request
  POST   /quit         stop the server
'
    $2.Write "$text"
}

kvGet() {
    local key
    $1.RouteParam key
    key="$RESULT"
    if Store.TryGetValue "$key"; then
        $2.Write "$RESULT"
    else
        $2.Code = 404
        $2.Write "no such key: $key"
    fi
}

kvPut() {
    local key value
    $1.RouteParam key
    key="$RESULT"
    $1.Content
    value="$RESULT"
    if Store.ContainsKey "$key"; then
        $2.Code = 200
    else
        $2.Code = 201
    fi
    Store.AddOrSetValue "$key" "$value"
    $2.Write "stored $key"
}

kvDel() {
    local key
    $1.RouteParam key
    key="$RESULT"
    if ! Store.ContainsKey "$key"; then
        $2.Code = 404
        $2.Write "no such key: $key"
        return 0
    fi
    Store.Remove "$key"
    $2.Write "deleted $key"
}

quit() {
    App.Terminate
    $2.Write "bye"
}

# The access log: one line per request, 'ADDR METHOD URI CODE BYTES MS'.
access_log() { printf '%s\n' "$2"; }

# ---------------------------------------------------------------------------
# The application. "$@" reaches the option parser (--port, -p, --address).
# ---------------------------------------------------------------------------

THttpApplication.new App "$@"
App.Title = 'kcl demo'
App.RegisterRoute /              GET    home
App.RegisterRoute /count         GET    Hits.Next
App.RegisterRoute /kv/:key       GET    kvGet
App.RegisterRoute /kv/:key       PUT    kvPut
App.RegisterRoute /kv/:key       DELETE kvDel
App.RegisterRoute /hello/:name   GET    THelloRoute 0 Hello
App.RegisterRoute /quit          POST   quit

if ! App.Initialize; then
    printf 'usage: %s [--port=N | -p N] [--address=A]   (N: 1-65535)\n' "${0##*/}" >&2
    App.delete; Store.delete; Hits.delete
    exit 2
fi
App.Server
"$RESULT.OnLog" = access_log
App.Address; demo_addr="$RESULT"
App.Port; demo_port="$RESULT"
if [[ "$demo_addr" != 127.* ]]; then
    printf 'warning: listening on %s — the store has no authentication\n' "$demo_addr" >&2
fi
printf 'kcl demo: http://%s:%s/   (POST /quit or Ctrl-C to stop)\n' "$demo_addr" "$demo_port"

demo_rc=0
App.Run || demo_rc=$?
if (( demo_rc != 0 )); then
    App.Server
    "$RESULT.LastError"
    printf 'kcl demo: the server stopped: %s\n' "$RESULT" >&2
fi
Hits.Value
printf 'kcl demo: stopped after %s /count hit(s)\n' "$RESULT"
App.delete
Store.delete
Hits.delete
exit "$demo_rc"
