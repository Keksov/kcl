# thttpserver — a minimal HTTP server on kklass + netcat (kcl/thttpserver)

**Status: COMPLETE (P0–P3, 2026-09-29)** — nine classes in four files, both examples,
the bench and the docs; 472 unit tests green on both bashes (§5); a post-completion
review (2026-09-30, F1–F6, §8) brought the suite to 497. Planned and
critic-hardened 2026-09-27 → 2026-09-28; owner decisions D1–D9 DECIDED (§2.0). A critic pass (§8: 3 blockers, 11 majors, 12 minors, nits — all
folded in) rewrote the network transport (§2.5): the first draft's FIFO writer never
delivered EOF, its close path truncated every response, and on bash 5.2.37 a FIFO cannot
be msys64 nc's stdin at all. The corrected mechanism is measured working on both bashes.

Owner request (2026-09-27): *"спланировать реализацию минимального web сервера в стиле
kcl, использующего kklass и netcat (nc) в качестве сетевого бэкенда. Цель —
продемонстрировать возможности kklass, а не реализовывать полноценный web сервер."*

**Goal, restated.** A small, honest, tested HTTP/1.0-style server whose value is the
**object model**, not the protocol coverage: every kklass feature that matters
(inheritance, `abstract`, `override` + `inherited`, virtual dispatch through `$this`,
read-only and read/write properties, a property setter that acts, constructor/destructor
with owned objects, `private`/`protected`, events as properties, factory-by-class-name,
composition with other kcl units) appears in a place where it is the natural tool — §2.9.

**The one idea that makes it a kklass demo.** The request handlers run **in the
server's own shell**, so objects live across requests (a counter, an in-memory
key-value store, a router). The classic bash web server (`nc -e script`, `ncat
--sh-exec`) starts a fresh shell per connection: state is lost, and with kklass loaded
every request would pay a cold `source` (≈1–3.5 s idle on this machine, measured by the
2026-09-26 timing-flake work). Here only `nc` is spawned per connection.

**How a connection is noticed.** The script never *detects* a connection: a listener
`nc` is started **in advance** and blocks in accept, while bash waits in `read -t` on
that `nc`'s stdout. The first bytes of a request arriving there **are** the event; the
listener's `-vv` stderr (`Listening on …`, `Connection from …`) tells the other states
apart (§2.5). Why not one `nc` for the server's whole lifetime: GNU nc 0.7.1 has no `-k`
(measured: one process = one connection, the second client is refused), and even with
`-k` (OpenBSD, ncat) the stdout stream has no connection boundaries, bash cannot close one
connection without closing stdin for all of them, and a reply to a client that already
left is delivered to the next client.

**Kind of unit (D1):** a **kcl addition with its own names** — no FPC/Delphi source,
like tpipe/tutil. FPC fcl-web (`fphttpserver.pp`, `httpdefs.pp`, `httproute.pp`,
`fphttpapp.pp`; local checkout at
`C:/projects/KKMindWave/VendorsCore/fpc/sources/main/packages/fcl-web/src/base/`) is a
**design reference only**: several choices borrow its semantics (`Active := True`
blocks, `OnRequest`, route objects, route data, default routes, 404/405 texts,
`AcceptIdleTimeout = 0`) and say so; there is no parity requirement.

**Ledger:** [`thttpserver_ledger.json`](thttpserver_ledger.json). **Prefix:** `__ths_`
(locals), `__THS_` (file-scope constants). No `static var` (kcl README §1.1: constants
stay file-scope globals).

---

## 1. Scoping

### 1.1 Measured facts (2026-09-27 planning probes + 2026-09-28 critic probes, both bashes)

**Backend and transport**

| probe | result |
|---|---|
| availability | bash 5.3.9 (msys64): `nc` = **GNU netcat 0.7.1**. bash 5.2.37 (Git for Windows): **no `nc` on PATH**; msys64's `/c/bin/msys64/usr/bin/nc.exe` by absolute path works from 5.2.37 **over pipes** (coproc) — **not over a FIFO** (next rows). `openbsd-netcat`, `socat` in pacman, not installed. No `ncat`. |
| one nc, many clients | **impossible with GNU 0.7.1**: no `-k`; with stdin held open, client 1 is served, client 2 is **refused** while the process lives on |
| port released on accept | after nc #1 accepted client 1 (connection still open), nc #2 **binds the same port** and receives client 2 |
| FIFO writer `O_RDWR` (`exec {wr}<>fifo`) | 5.3.9: nc **never sees EOF** after `wr` is closed (alive ≥ 4.7 s), so `-c` never closes the connection; an HTTP/1.0 client reading to EOF hangs. Earlier probes missed it because curl stops at Content-Length. **Forbidden.** |
| FIFO writer `O_WRONLY` (`exec {wr}>fifo`) | nc exits ≈100 ms after the close, the client sees EOF in ≈32 ms; no open-order deadlock (the reader is the child's own redirect, a different process) |
| FIFO as msys64 nc's stdin under 5.2.37 | `Connection from …` then `select(core_readwrite): Bad file descriptor`; nc dies on accept, curl rc 56 (Git-runtime FIFO, msys64-runtime nc). **A relay fixes it:** `< <(exec cat FIFO)` makes stdin a same-runtime pipe; harmless on 5.3.9 |
| close, close, immediate `kill -TERM` | **5/5 truncated** responses (a 200-byte body arrived as 0 or 57 bytes; 50 kB as 0–3133): nc was killed before it had flushed |
| fd inheritance | a pre-spawned listener inherits the parent's writer fd of the current connection unless its child closes it: connection 1 then stays open until the new listener's `-w` (10 041 ms with `-w 10`) |
| the working variant | O_WRONLY writer + the child closes the other slot's fds + `cat` relay + drained close: **3/3 requests on each bash** (re-run by the supervisor 2026-09-28), 6/6 runs in the critic's probes incl. client 2 accepted by the pre-spawned listener while request 1 was in progress; spawn 34–46 ms with the relay (11–17 ms without), close 14–57 ms; `$!` of the process substitution is the listener (kill/wait work, also cross-runtime from 5.2) |
| `-w N` | limits **accept only**: rc 1 after N s with no client; a 4 s slow response and an 8 s silent client were **not** cut |
| `-vv` stderr | `Listening on 127.0.0.1 PORT` (bound) · `Connection from 127.0.0.1:59097` (accepted) · `Listen mode failed: Connection timed out` (`-w` expired) · `Error: Couldn't setup listening socket (err=-3)` (bind failure, ≈74 ms) · `Total received bytes: N` |
| nc exit status | rc 1 on every normal close — never used for classification |
| sequential throughput | ≈100 ms per request end-to-end (20 requests, one curl each, single listener, 5.3.9) |
| concurrency, single listener | 8 parallel no-retry clients: 6×200, 2× curl rc 56 (reset) |
| concurrency **with the pre-spawn** (P2) | 8 parallel clients retrying on rc 7 only: **2–3 × rc 56 in each of 5 rounds** (5.2.37); **3 per round** on 5.3.9 (rc 56, once rc 55 — the send side of the same reset). The resets are consistent with GNU nc closing its listening socket after its one accept, which resets the connections already queued in its backlog: they never reached a handler (access-log lines = successes: 27/27 on 5.2.37, 25/25 on 5.3.9). D5 lets ONE further client wait, it cannot absorb a burst — see fact 7 |
| P2 spike: the §2.5 variant inside a kklass class | 6 scenarios × both bashes, all as designed: 3 requests with client 2 accepted by the pre-spawned listener, 2 × 50 kB, silent client → TimedOut, a partial first line accumulated across ticks, busy port → `Error: Couldn't setup listening socket (err=-3)` in 98–126 ms, exec failure / nc not found → fatal at once, Shutdown with client 2 in the pre-spawned listener → 0 bytes, `-w 2` expiry → respawn with the idle ticks going on; `wait PID` works for a process substitution that is not the last one (rc 1 = nc's) |
| P2 costs (TNetcatTransport, 12 requests) | Accept with the request line already waiting (read + state + the pre-spawn) 42–52 ms; drained CloseConnection 20–44 ms (5.2.37) / 9–29 ms (5.3.9); Shutdown 67 / 33 ms |
| P2: trapped signal vs `read -t` | a trapped TERM does **not** cut `read -t 3` short: the trap runs, the read goes on to its timeout (rc 142 after 3.03 s, both bashes). The 1 s Accept tick bounds the delay |
| P2: kklass member as the trap | a **private** method run by a trap while ANOTHER class's frame is on top prints `[kk] warning: private method 'X._onSignal' accessed from 'Y'` (both bashes) — hence the flag design of §2.6 |
| P2: `trap -p` capture | `$(trap -p …)` sees the parent's traps (both bashes; 1 fork). Fork-free alternatives: `trap -p > file` + `read` works but the file needs `rm` (a fork) or stays; the 5.3 funsub `${ trap -p; }` runs in the shell but is a parse error for 5.2. The one `$( )` per Serve stays |

**Bash and kklass**

| probe | result |
|---|---|
| per-request objects | `new` + property set + `func` + `TDictionary.new/Add/delete` + `delete` ≈ **2.7 ms**; `.delete` then `.new` with the same name gives a clean instance |
| byte semantics | under `C.UTF-8` `${#s}` and `read -N` count **characters**; `local LC_ALL=C` counts bytes and is restored on return |
| `read -N LEN` over a NUL | the NUL is dropped **and not counted**: `read -N 3` over `a\0b` waits for the timeout (rc 142, length 2) |
| `read -t` | `-t 0` → rc 1 at once without reading (looks like EOF); `-t -1` → stderr error; on a timeout the partial input stays in the variable; `read -n 8193` splits a 9000-byte line 8193 + 808 |
| empty assoc key | `a[$k]=1` with `k=''` → `bad array subscript` and **the whole top-level command aborts** (re-verified by the supervisor: nothing after it ran); a read `${a[$k]+x}` prints the error and continues. Hostile non-empty keys (`$(touch pwn)`, `` ` ``, `]`, `@`, `*`, `a[0]`, `x;y`) are safe with `${h[$k]+x}` |
| `printf '%(…)T'` | ignores a non-exported `local TZ` (re-verified: 22 vs 19 UTC); `TZ=UTC0 printf …` prefix form works and does not leak; day/month names follow `LANG` (Russian here) unless `LC_ALL=C` |
| SIGPIPE | ignored → the write returns rc 1 and prints `write error: Broken pipe` (5.3.9 prints two lines); not ignored → the shell dies. A signal ignored at non-interactive start cannot be trapped (a `&` child has INT ignored) |
| `patsub_replacement` | on in both bashes: `${x//</&lt;}` yields `a<lt;b` — quote `&` in replacements |
| cross-object property read | a plain `var` of **another** object read directly **prints** its value and leaves `RESULT` **unchanged (stale)**; `property X read X write X` and `property X read _x` read silently into `RESULT` (≈0.4–0.5 ms); a write to a read-only property is rc 1 and prints `Error: Property 'X' is read-only` unconditionally (kklass's own line) |
| `inherited` | in a **constructor**, bare `inherited` forwards `"$@"`; in a **method**, bare `inherited` becomes `inherited <Name>` **with no arguments** (`kklass_pascal.sh:153-163`); in a destructor whose parent has none → `inherited: command not found`, rc 127 on stderr |
| abstract | `.new` of a still-abstract class → rc 1 + an unconditional stderr line; a concrete class whose `Create` ends on a false test also gets rc 1; the flag `.new` checks is `${CLASS}_class_abstract` (`kklass_decl.sh:435-436`) |
| visibility | a `private` member used from a descendant prints `[kk] warning: private method … accessed from '<class>'` (`kklass.sh:218-221`) |
| clients | curl 8.14.1 (5.2) / 8.20.0 (5.3) send `Expect: 100-continue` only for bodies > 1 MiB; bash `/dev/tcp/127.0.0.1/PORT` is a raw client on both |
| **proxy** | this machine exports `HTTP_PROXY=HTTPS_PROXY=http://127.0.0.1:2080`: plain curl to localhost goes through it (503, rc 0). Tests use `curl --noproxy '*'` and unset all proxy variables |
| firewall | loopback-only listeners (`-s 127.0.0.1`) raised no prompt; all-interface binding may — tests never do it |
| P3: `$this.NAME` inside quotes | (historical — kklass R2_P8, 2026-10-02, removed the rewrite; `"$this.Home"` is now the string `App.Home`, the same as `"$__inst__.Home"`) at P3 kklass rewrote the **text** `$this.NAME` of a member body into `$__inst__.call NAME` for every method NAME of the class (`kklass.sh:141-146` then), quoted data included: `RegisterRoute / GET "$this.Home"` registered `App.call Home` (refused, rc 2). A method of the running instance is registered as `"$__inst__.Home"` (works before and after R2_P8) |
| P3 costs (`bench.sh`, 5.2.37 / 5.3.9) | fork-free replay ServeOne 28.1 / 26.5 ms, DoRun 31.0 / 29.6 ms; over sockets 107 / 95 ms per request with a `/dev/tcp` client (9 / 10 req/s), 139 / 107 ms with curl; the spawn's synchronous part 36 ms; the drained close 14.5 / 8.1 ms; 8-client bursts without retry 28 / 31 of 40 answered, the rest resets (and 2 refusals on 5.2.37), the access log = the 200s |

### 1.2 Classes and files

```
kcl/thttpserver/
    thttpmessage.sh      THttpRequest, THttpResponse
    thttprouter.sh       THttpRouteObject (abstract), THttpRouter
    thttpserver.sh       THttpTransport (abstract), TNetcatTransport, TReplayTransport,
                         THttpServer                      (entry point, sources the two above)
    thttpapplication.sh  THttpApplication : TCustomApplication   (sources ../tcustomapplication)
    examples/demo.sh     the showcase application, functions + App.RegisterRoute (§2.10)
    examples/demo_oop.sh the same application in the descendant style (§2.11)
    tests/ bench.sh README.md TEST_COVERAGE_NOTES.md thttpserver_ledger.json
```

Each `.sh` has the kcl re-source guard (`${_THS_<FILE>_SOURCED:-}`), the §1.6 locale
self-heal and sources kklass through `kklass_pascal.sh`. Class names carry the `THttp`
prefix to stay clear of generic names — kklass refuses a same-name class from a
different file.

### 1.3 Surface

**The property rule (D6 generalised, C7):** any field that **another object** reads is a
property, never a plain `var` — `property X read _x` (read-only) or `property X read X
write X` (read/write). A plain `var` is only for fields the owner's own bodies use, or
fields only ever *written* from outside (`$srv.Port = 8080` does not print).

```bash
class THttpRequest
    public
        property Method          read _method           # token ^[A-Z]+$
        property URI             read _uri              # request-target as received: /path?query
        property PathInfo        read _pathInfo         # URI before '?', NOT percent-decoded
        property QueryString     read _queryString      # URI after the first '?', '' if none
        property ProtocolVersion read _protocolVersion  # '1.0' | '1.1'
        property Content         read _content          # body, text only (§1.4)
        property RemoteAddress   read _remoteAddress    # 'IP:PORT' from nc -vv, '' if unknown
        property ContentLength   read GetContentLength  # BYTE length of Content
        constructor Create              # every field assigned; allocates ${inst}_hdr, _hdrn, _qf, _rp
        destructor  Destroy             # frees them (§1.9)
        func GetContentLength
        func GetHeader                  # NAME (case-insensitive) → RESULT; rc 1 + '' if absent; '' → rc 2
        proc HasHeader                  # NAME → rc (predicate, §1.3)
        func HeaderNames                # OUTARR → names in arrival order, RESULT = count (§1.7)
        func QueryField                 # NAME → percent-decoded value, first occurrence; rc 1 if absent; '' → rc 2
        func RouteParam                 # NAME → value captured by the router
        proc SetRouteParam              # NAME VALUE (the router's use)
        func ReadFrom                   # FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE [CONSUMED]]] — rc 0 (rc 2 =
                                        #   malformed call); RESULT = 0 parsed | 400/408/413/414/431/501/505 to
                                        #   answer | 'gone' (C20); CONSUMED 1 = FIRSTLINE is the request line even
                                        #   when empty (review F5); Method/URI/ProtocolVersion kept after a
                                        #   later-stage status (review F4)
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

class THttpResponse
    public
        property Code        read Code        write Code         # default 200; validated at send (§2.3)
        property CodeText    read CodeText    write CodeText     # '' → from Code (file-scope table)
        property ContentType read ContentType write ContentType  # default 'text/plain; charset=utf-8'
        property Content     read Content     write Content
        property ContentSent read _contentSent
        constructor Create
        destructor  Destroy             # frees ${inst}_hdr, _hdrn
        proc Attach                     # FD ISHEAD — the server's use: output fd, HEAD flag
        proc SetCustomHeader            # NAME VALUE — rc 2 on a non-token NAME, CR/LF/NUL in VALUE, or a
                                        #   server-owned name (Content-Length, Connection, Date, Server, Content-Type)
        func GetCustomHeader            # NAME → RESULT
        proc Write                      # TEXT… appended to Content (handlers do not echo)
        proc SendContent                # one printf, errors silenced; rc 1 if already sent or the write failed
        proc SendRedirect               # URL [CODE=302]
    private
        var _fd
        var _head
        var _contentSent
end

class THttpRouteObject
    public
        var RouteData                   # DATA from RegisterRoute, assigned by the router before HandleRequest (D7)
        constructor Create
        destructor  Destroy             # empty, so descendants may chain with inherited (C9)
        abstract proc HandleRequest     # REQ RESP
end

class THttpRouter
    public
        var BeforeRequest               # handler REQ RESP, run first
        var AfterRequest                # handler REQ RESP, run last
        constructor Create
        destructor  Destroy             # frees ${inst}_pat, _met, _hnd, _kind, _def, _rdat (never _data — C10)
        proc RegisterRoute              # PATTERN HANDLER | PATTERN METHOD HANDLER [ISDEFAULT [DATA]] — §2.4
        property RouteCount read GetRouteCount
        func GetRouteCount
        proc RouteRequest               # REQ RESP → dispatch, or 404/405
        func FindRoute                  # PATH METHOD → RESULT = route index; rc 1 with REPLY = 404|405
end

class THttpTransport                    # the network seam
    public
        property InFd          read _inFd
        property OutFd         read _outFd
        property FirstLine     read _firstLine       # request line consumed by Accept ('' if none)
        property LineConsumed  read _lineConsumed    # 1: FirstLine was consumed, even '' (review F5)
        property TimedOut      read _timedOut        # 1: connected but silent past RequestTimeout → 408
        property RemoteAddress read _remoteAddress
        property LastError     read _lastError
        constructor Create
        destructor  Destroy             # empty, so descendants may chain (C9)
        abstract func Accept            # IDLE_MS REQUEST_TIMEOUT_S → rc 0 connection | 1 idle tick | 2 fatal
        abstract proc CloseConnection
        abstract proc Shutdown          # stop listening; kill and reap every listener; remove temp files
    protected
        var _inFd
        var _outFd
        var _firstLine
        var _lineConsumed
        var _timedOut
        var _remoteAddress
        var _lastError
end

class TNetcatTransport : THttpTransport # GNU netcat 0.7.1, two alternating listener slots (D5)
    public
        var NcBinary                    # '' → ${KCL_NC:-} → `nc` on PATH; none → Accept rc 2 'nc not found'
        var Address                     # default 127.0.0.1
        var Port
        var ListenerTTL                 # s, default 60 — nc -w: only an orphan time-to-live (C5)
        var CloseTimeout                # s, default 2 — bound of the drained close (C2)
        var StdinRelay                  # default 1 — nc's stdin through `cat` (C3); 0 only for a same-runtime nc
        constructor Create
        destructor  Destroy             # Shutdown, then inherited
        func BuildArgv                  # OUTARR → NC -l -c -vv -n -w TTL -s ADDR -p PORT (virtual)
        override func Accept
        override proc CloseConnection
        override proc Shutdown
    private
        var _dir                        # mktemp -d under $TMPDIR: fifo0/1, err0/1
        var _cur
        var _pid0
        var _pid1
        var _rd0
        var _rd1
        var _wr0
        var _wr1
        var _seen0                      # EPOCHREALTIME when 'Connection from' was first seen in slot 0/1
        var _seen1
        proc _spawn                     # SLOT
        func _state                     # SLOT → RESULT = listening | connected | ttl | failed:<line> | none
end

class TReplayTransport : THttpTransport # the test double: no sockets, no forks
    public
        constructor Create
        destructor  Destroy             # Shutdown, then inherited
        proc AddRequestFile             # FILE — one raw request per Accept, in order
        func ResponseFile               # INDEX → path of the captured response
        override func Accept            # next request file on InFd, a capture file on OutFd; none left → rc 2
        override proc CloseConnection
        override proc Shutdown
end

class THttpServer
    public
        var Address                     # default 127.0.0.1
        var Port                        # default 8080
        var Transport                   # THttpTransport instance; '' → an owned TNetcatTransport on BeginServe
        var Router                      # THttpRouter instance or ''
        var OnRequest                   # handler REQ RESP; wins over Router
        var OnRequestError              # handler REQ RESP RC — a handler returned non-zero
        var OnAcceptIdle                # handler SERVER — every idle tick
        var OnLog                       # handler SERVER LINE — one access-log line per request
        var AcceptIdleTimeout           # ms, default 0 = off (D4); ticks have ~1 s granularity (C5)
        var RequestTimeout              # s, default 10 → 408
        var MaxContentLength            # default 65536 → 413
        var MaxRequests                 # 0 = unlimited
        var ServerBanner                # 'Server:' header, default 'kcl-thttpserver'
        property RequestCount read _requestCount
        property LastError    read _lastError
        property Active       read GetActive write SetActive     # Active = true BLOCKS in Serve (as FPC)
        constructor Create
        destructor  Destroy             # EndServe if needed; frees an owned transport
        func GetActive
        proc SetActive                  # true → Serve; false (from a handler) → Terminate
        proc Serve                      # BeginServe + loop over ServeOne + EndServe; rc 1 on a transport fatal
        proc BeginServe                 # save traps; trap '' PIPE; TERM/INT → stop; create/open the transport (C11)
        func ServeOne                   # accept + handle ONE connection: rc 0 handled | 1 idle | 2 fatal
        proc EndServe                   # transport Shutdown; restore the saved traps exactly
        proc Terminate                  # stop after the current request
        proc HandleRequest              # REQ RESP — VIRTUAL: OnRequest, else Router.RouteRequest, else 404
    protected
        proc _handleConnection          # descendants may call it without a visibility warning (C23)
        proc _log
    private
        var _active
        var _stop
        var _requestCount
        var _lastError
        var _ownsTransport
        var _savedTraps
        proc _onSignal                  # the INT/TERM trap: _stop=1, transport Shutdown
end

class THttpApplication : TCustomApplication
    public
        var Port                        # default 8080; --port=N / -p N
        var Address                     # default 127.0.0.1; --address=A
        var ServerClass                 # default THttpServer (D9); must derive from THttpServer
        property Server    read _server
        property AppRouter read _router
        constructor Create              # inherited (forwards argv); creates AppRouter here, so routes may be
                                        #   registered before Initialize (C24)
        destructor  Destroy             # frees server and router; NO inherited — TCustomApplication has no destructor
        override proc Initialize        # inherited Initialize "$@"; options → Port/Address; ServerClass check
                                        #   (rc 2) and ServerClass.new; wires Router, Port, Address
        proc RegisterRoute              # delegates to AppRouter
        override proc Run               # Server.BeginServe; inherited Run "$@"; Server.EndServe;
                                        #   rc 1 if the server recorded a transport fatal (C11)
        override proc DoRun             # Server.ServeOne: rc 0/1 → 0; rc 2 → Terminate, rc 0 (Run reports it);
                                        #   MaxRequests reached (Server.RequestCount) → Terminate
        override proc Terminate         # inherited Terminate "$@"; Server.Terminate
    private
        var _server
        var _router
end
```

### 1.4 Not in scope

* **Parallel handling / `QueueSize`** — requests are handled strictly one at a time in
  the server shell. With D5 one further connection can wait in the pre-spawned listener
  (queue depth 1); beyond that a client meets a refusal or a reset and **retries**.
* **Keep-alive** — every response carries `Connection: close` and the connection is
  closed, whatever the version.
* **TLS, chunked bodies, multipart, cookies, sessions, compression, `Expect:
  100-continue`** (curl only sends it above 1 MiB, far past the 64 KiB limit → 413).
  A request with `Transfer-Encoding` is answered **501**.
* **Binary bodies** — a bash variable cannot hold NUL: a request body with a NUL is
  **400**; responses are written from a variable. No file streaming.
* **Static files** (D3). Other netcat flavours (D2). Route pattern forms beyond constant
  segments, `:name` and a trailing `*name`. Deleting routes.

---

## 2. Design decisions

### 2.0 Owner decisions

| id | question | decision |
|---|---|---|
| D1 | naming | **own kcl names**: `kcl/thttpserver`, `THttp*` classes; FPC fcl-web is a design reference only |
| D2 | backends | **GNU netcat only + `TReplayTransport`** test double |
| D3 | static files | **out of scope** |
| D4 | `AcceptIdleTimeout` default | **0** (off, as FPC); tests always set 1000 ms |
| D5 | pre-spawn the next listener | **yes, in P2**: start the next `nc` right after the current connection's request line arrives (§2.5). Critic note: the riskiest piece with little demo value of its own; it is feasible (§1.1, measured) |

Added 2026-09-28 after designing the descendants (§2.11):

| id | decision |
|---|---|
| D6 | **request fields are read-only properties** over private fields — generalised by C7 to every field another object reads (§1.3 property rule). A direct read inside a handler is silent and sets `RESULT`; a write is rc 1 |
| D7 | **route data**: `RegisterRoute … [ISDEFAULT [DATA]]` (after FPC's `RegisterRoute(APattern, AData, ACallBack)`); a route object gets it in `RouteData`, a function or `inst.method` handler as `$3` |
| D8 | **an abstract route class is refused at registration** with rc 2 — implemented by reading `${CLASS}_class_abstract`, the flag `.new` itself checks (C17): no probe instance, no constructor run, nothing printed. This couples to one kklass internal; a public `kk.isAbstract` in kklass would remove the coupling (roadmap note) |
| D9 | **`THttpApplication.ServerClass`** (default `THttpServer`): `Initialize` creates the server as `ServerClass.new`; a class not derived from `THttpServer` → rc 2 |

### 2.1 kcl contract (README §1) — applies in full

`RESULT` via `kk._return` for instance `func`s, rc 1 + `RESULT=''` + `kk.debug` for a
miss, rc 2 for a malformed call, predicates by rc, `set -eu` clean (`008_Contract.sh`),
numbers through `kk.isInt`, output arrays through `kk._outName` with `__ths_` and the
unit's own `_hdr`/`_hdrn`/`_qf`/`_rp`/`_pat`/`_met`/`_hnd`/`_kind`/`_def`/`_rdat`
suffixes reserved (never `_data`: kklass's own storage), every extra per-instance array
freed in the destructor, no fork on a per-request path **inside the server shell** except
the listener spawn — proved three ways under `TReplayTransport` (§4).

`ReadFrom` answers rc 0 with the status in `RESULT` (C20), so the parser's "error" is a
value, not a miss, and §1.2 holds. **Amended by review F4 (2026-09-30):** a status from
the request line itself leaves every field empty, but once the request line is accepted
`Method`/`URI`/`ProtocolVersion` are set and stay set whatever a later stage returns
(400/408/413/431/501/`gone`) — the server takes the HEAD flag from `REQ.Method` (the
transport's `FirstLine` prefix only when Method is ''), so a failed HEAD is answered
without a body on every transport; `PathInfo`/`QueryString`/`Content` stay status-0-only
(the P0 deviation-9 contract, "an error status leaves Method..Content empty", is
superseded).

**Named deviations** (README §2 row): (a) `Active = true` / `Serve` / `App.Run` **block**
until the server stops; (b) handlers' **stdout goes to the server's stdout, not to the
client** — a handler writes through `$resp.Write` / `$resp.Content`; (c) requests are
handled one at a time, no keep-alive (§1.4); (d) a server that is **KILLed** leaves its
temp dir and its listener until the listener's `ListenerTTL` (60 s) expires — the unit
may not install an EXIT trap (C26); (e) a write to a read-only property prints kklass's
own `Error: Property 'X' is read-only` line unconditionally.

### 2.2 Request parsing (`THttpRequest.ReadFrom FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE [CONSUMED]]]`)

* **Time.** Every `read` gets `-t LEFT`, LEFT = deadline − `EPOCHREALTIME` formatted
  `S.UUUUUU`; **LEFT ≤ 0 → 408 without calling `read`** (`-t 0` would look like EOF,
  `-t -1` prints an error). A short body seen at the deadline → **408**; seen at EOF → the
  client is gone (`RESULT=gone`, nothing answered).
* **Lines** are read with `local LC_ALL=C; read -r -n 8194` (8192 bytes + CR + one to
  detect overflow): longer → **414** for the request line, **431** for a header. More than
  100 headers → **431**. A trailing CR is stripped with the file-scope `__THS_CR`
  (an inline `$'\r'` in a member body does not survive `build`). Bare LF is accepted.
  A partial first line followed by EOF → `gone`. An EMPTY line before the request line is
  **400** (no RFC 9112 §2.2 leading-CRLF skip) — also when a transport consumed it: the
  transport's `LineConsumed` reaches ReadFrom as **CONSUMED 1**, "FIRSTLINE is the request
  line even when ''"; CONSUMED 0 / omitted keeps the P0 rule (a non-empty FIRSTLINE was
  consumed, an empty one means read it from FD) (review F5 — before it, a bare LF sent
  over netcat was dropped and the next line parsed: 200 on the wire, 400 in the direct
  parse).
* **Request line** = exactly `METHOD SP TARGET SP HTTP/1.x`: METHOD `^[A-Z]+$` and one of
  `GET POST PUT DELETE OPTIONS HEAD TRACE PATCH`, else **501**; TARGET starting with `/`
  (origin-form only) else **400**; version `1.0`/`1.1` else **505** (garbage **400**);
  HTTP/1.1 without `Host` → **400**.
* **Headers** `NAME: VALUE`: NAME an RFC 9110 token else **400**; obs-fold → **400**;
  stored lower-cased in `${inst}_hdr` + arrival order in `${inst}_hdrn`; a repeat is
  joined with `, `, except two **different** `Content-Length` values → **400** and a
  **second `Host`** (any case, any value, identical included — RFC 9112 §3.2 MUST) →
  **400** (review F2).
* **Body.** `Transfer-Encoding` → **501**. `Content-Length` through `kk.isInt`, negative
  or non-numeric → **400**, above MAXBODY → **413** (the body is not read). Read under
  `LC_ALL=C` in a loop of `read -r -d '' -n $((LEN-got))` (C18): a returned delimiter
  means a NUL → **400** at once; this also avoids waiting for bytes `read -N` never counts.
* **Query fields**: split on `&`, then `=`; **an empty name is skipped** (C12: an empty
  assoc key aborts the whole top-level command); `+` → space; `%XX` → `\xXX` +
  `printf -v … '%b'` **after** doubling every `\` (measured correct on both bashes);
  `%00` → the field is rejected (rc 1 from `QueryField`); invalid `%G1` stays literal.
* **Hostile data is data**: never `eval`ed, never a variable or function name, never in
  `(( ))` or `${!…}` unvalidated. **Every assoc access is guarded by `[[ -n $k ]]`**;
  reads use `${h[$k]+x}`. `GetHeader ''` / `QueryField ''` → rc 2. Replacements in
  `${x//…/…}` quote `&` (`patsub_replacement` is on).

### 2.3 Response (`THttpResponse.SendContent`)

* **Head**: `HTTP/1.1 CODE TEXT` + `Date` + `Server` + `Content-Type` + custom headers in
  insertion order + `Content-Length` (bytes, `local LC_ALL=C`) + `Connection: close` +
  blank line + body. 1xx and 204: no body and no Content-Length; 304 and HEAD: no body.
  One `printf` per response, to `_fd`, with `2>/dev/null` (C16); a failed write is rc 1
  and one `_log` line — never a dead server.
* **Date** = `LC_ALL=C TZ=UTC0 printf -v __ths_date '%(%a, %d %b %Y %H:%M:%S GMT)T' -1` —
  a prefix assignment on the builtin; **never `local TZ`** (C15).
* **Validation at send (C14)**: `Code` through `kk.isInt` and 100–599, else the response
  becomes **500**; CR, LF or NUL in `CodeText`, `ContentType` or the server's
  `ServerBanner` → **500** with the default head plus one `kk.debug` line — never sent raw.
  `SetCustomHeader` refuses the server-owned names, `Content-Type` included (use
  `ContentType`), so no header is duplicated.
* The reason-phrase table is a file-scope assoc (`__THS_REASON`).

### 2.4 Router (`RegisterRoute`)

* **Arguments**: with 2 arguments `PATTERN HANDLER` (METHOD = `ALL`); with ≥ 3 the 2nd is
  **always** METHOD — `PATTERN METHOD HANDLER [ISDEFAULT [DATA]]`. METHOD ∈ `GET POST
  PUT DELETE OPTIONS HEAD TRACE PATCH ALL`; ISDEFAULT `0`/`1`; DATA an opaque string
  stored verbatim in `${inst}_rdat` (D7). Anything else → rc 2.
* **HANDLER** is first checked against `^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$`,
  then resolved **once, at registration**, and stored with its kind:
  1. a **class** deriving from `THttpRouteObject` (`kk._class_derives_from`) and **not
     abstract** (`${CLASS}_class_abstract` ≠ 1, D8) → per request: `CLASS.new
     __ths_route_obj`, `RouteData` assigned, `.HandleRequest REQ RESP`, `.delete`. A
     dispatch nested inside a route object's HandleRequest (a sub-router) uses
     `__ths_route_obj1`, `2`, … — one name per level, the level a `local` inherited
     through bash's dynamic scope, so an inner pass never deletes the outer, live object
     and an aborted pass leaves no level behind (review F1);
  2. **`INST.METHOD`**: INST is a live instance (`${INST}_class` set) and METHOD is a
     **method** of its class (not a property wrapper, which `declare -F` would also
     accept) → called `INST.METHOD REQ RESP DATA`; state persists;
  3. a **function** → called `FN REQ RESP DATA`.
  Anything else → rc 2.
* **Patterns**: constant segments, `:name` (one non-empty segment → `RouteParam`), a
  **trailing** `*name` (the rest, `/` included, possibly empty). Leading `/` optional;
  constant segments compare case-sensitively; a trailing `/` is significant. `*` not last
  → rc 2. The full table is pinned in 003 and printed in the README.
* **Matching**: registration order among ordinary routes. **HEAD** matches a HEAD route,
  else the GET route of the same pattern (the body is suppressed by `ISHEAD`) (C13).
  No route matches the path → the **default route** of the method (else of `ALL`), whose
  pattern is ignored (FPC's fallback); one default per method, a second → rc 1; without a
  default → **404 Not Found**. The path matches but not the method → **405 Method Not
  Allowed** + `Allow:` (HEAD listed whenever GET is).
* `BeforeRequest` → handler → `AfterRequest`. A handler that returns non-zero with nothing
  sent → 500 via the server.

### 2.5 Transport seam and the two listener slots (D5)

`THttpTransport` is **abstract**; the server only knows `InFd`/`OutFd`/`FirstLine`/
`LineConsumed`/`TimedOut`/`RemoteAddress` (`LineConsumed`: review F5).
**`TReplayTransport`** (`exec {InFd}<REQFILE`, `exec {OutFd}>CAPTUREFILE`) runs the whole
pipeline with no socket and no fork; P0/P1 tests are built on it, and it demonstrates
substitutability.

**`TNetcatTransport`** — two slots; each is a FIFO feeding the listener's stdin, a
process-substitution fd reading its stdout, a `-vv` stderr file and a pid, under a
`mktemp -d` dir (`mkfifo` once per slot per `BeginServe`). The mechanism below is the
critic's working variant (`scratchpad/critic/p7.sh`), measured on both bashes:

```bash
# _spawn SLOT  (o = the other slot)
exec {rd}< <( if [[ -n $wrO ]]; then exec {wrO}>&- {rdO}<&-; fi      # C4: never inherit the live connection
              exec "${argv[@]}" < <(exec cat "$dir/fifo$s") 2>"$dir/err$s" )   # C3: cat relay (StdinRelay=1)
pid=$!
exec {wr}>"$dir/fifo$s"      # C1: O_WRONLY — pairs with the relay's open; O_RDWR (<>) is FORBIDDEN
```

The spawn is synchronous (≈35–45 ms with the relay) and adds to the current request;
only nc's own startup overlaps.

**`Accept IDLE_MS REQ_TIMEOUT_S`** (C5, C6):
1. If the current slot has no listener, `_spawn` it.
2. Loop `LC_ALL=C read -r -n 8194 -t TICK chunk <&rd`, accumulating partial input,
   TICK = min(1 s, remaining idle budget):
   * **rc 0** (a line, or 8194 bytes) → `FirstLine` (+ `LineConsumed` 1, an empty line
     included — review F5), `RemoteAddress` from `Connection
     from` in the stderr file (fork-free `while read`), then **`_spawn` the other slot**,
     rc 0.
   * **rc > 128** → `_state`: `connected` → remember when first seen; once older than
     REQ_TIMEOUT_S → rc 0 with `FirstLine=''`, `TimedOut=1` (the server answers 408 —
     one silent client can no longer hold the server); `listening` → if IDLE_MS > 0 and
     the idle budget is spent → **rc 1 (idle tick; the listener stays alive, no port
     gap)**; else keep waiting.
   * **rc 1 (EOF)** → `_state`: `connected` (the client left) → rc 1, the slot is spawned
     again at the next Accept; `ttl` (`Listen mode failed: Connection timed out`) → spawn
     again and keep waiting; **anything else** — bind failure, `command not found`, an
     empty file — → **rc 2**, `LastError` = the first non-`Listening` stderr line.
3. A pre-spawned slot that fails to bind is spawned **once** more at the next Accept; a
   second failure is rc 2.

**`CloseConnection`** (C2): (1) `exec {wr}>&-`; (2) drain `rd` with `read -r -t LEFT`
until EOF, LEFT counting down to `CloseTimeout` — EOF means nc has flushed, closed and
exited, and the drain swallows unread request bytes (no RST); (3) `exec {rd}<&-`;
(4) only if the deadline passed, `kill -TERM "$pid" 2>/dev/null || :`; (5) `rc=0; wait
"$pid" 2>/dev/null || rc=$?`; switch `_cur`. **Never** the tpipe kill-first stop path here:
it truncates every response (§1.1).

**`Shutdown`** closes both slots' fds, kills and reaps both pids (`2>/dev/null || :` —
an exited-but-unreaped pid makes a bare `kill` print), removes the FIFOs, stderr files
and dir. A connection already accepted by the pre-spawned listener is closed without a
response (documented; pinned by 005). **Review R1 (P2):** closing and killing at once is
the C2 kill-first race for a slot that has ACCEPTED a client — measured 3/30 resets on
5.2.37 (the client's read ends rc 1 instead of a clean EOF). A **connected** slot
(`Connection from` in its stderr) is therefore closed the drained way — its writer
closed first, then `_closeSlot drain` with one deadline (now + CloseTimeout) shared by
the connected slots; a slot that is only **listening** is still killed at once (its
stdin EOF would not end nc's accept). After the change 60/60 clean on each bash.

**Fd hygiene.** A background process a handler starts inherits the current connection's
writer and would hold the connection open; `CloseTimeout` bounds it (documented).

**Fallback (owner to be told if used):** if the P2 opening spike cannot reproduce the
variant above on both bashes, the transport falls back to one coproc listener (D5 off),
with the concrete failing trigger recorded.

### 2.6 The serving loop

```
BeginServe: saved=$(trap -p INT TERM PIPE) — the ONE fork of the call, not per request;
            trap '' PIPE; trap "<srv>._onSignal" INT TERM (sets _stop, Shutdown kills listeners)
            create the owned transport if Transport is ''; _active=1
Serve:      BeginServe; while ! _stop && (MaxRequests==0 || RequestCount<MaxRequests): ServeOne
              rc 2 → _lastError, stop, rc 1      rc 1 → OnAcceptIdle, continue
            EndServe
ServeOne:   a live ${srv}_req/${srv}_resp from an aborted pass → .delete first
            Accept → THttpRequest.new/THttpResponse.new → RESP.Attach OutFd ISHEAD
            → TimedOut ? 408 : ReadFrom (FIRSTLINE, REMOTE, CONSUMED = LineConsumed — review F5)
            → RESULT gone → nothing sent; status → RESP.Code=status; 0 → $this.HandleRequest REQ RESP (VIRTUAL)
            → handler rc≠0 and not ContentSent → OnRequestError, 500
            → not ContentSent → SendContent → _log (OnLog: 'ADDR METHOD URI CODE BYTES MS', control
              characters replaced by '?', TStopwatch)
            → CloseConnection → .delete both → RequestCount++ unless gone (review F3: a gone
              connection is neither answered, logged nor counted — it cannot use up MaxRequests)
EndServe:   transport Shutdown; trap - INT TERM PIPE; eval "$saved"; _active=0
```

(`trap -p` inside `$( )` is the one place the loop forks, once per `Serve`; P2 checks
whether `trap -p` output can be captured fork-free and prefers that — **measured P2: not
without another fork or a 5.3-only syntax (§1.1); the `$( )` stays**.)

**As implemented (P2 — the measurements contradicted the trap line above).** The trap is
not `<srv>._onSignal`: a private member run by a trap while another object's frame is
on top (the transport in `Accept`, the router, a handler) prints a kklass visibility
warning, and a Shutdown run from inside a trap could land in the middle of `_spawn` /
`_closeSlot`. BeginServe sets `trap '__THS_SIGNAL=INT' INT` / `trap '__THS_SIGNAL=TERM'
TERM` — a bare assignment to a file-scope flag. The flag is read at safe points: the
Serve loop and ServeOne (then the private `_onSignal`: `_stop=1` + transport Shutdown)
and TNetcatTransport.Accept at every ≤ 1 s tick (rc 1). So a signal lets the current
response finish, a connection waiting in the pre-spawned listener is closed without a
response (fact 11), and Serve returns 0. `read -t` is not interrupted by a trapped
signal anyway (§1.1), so the reaction time is one tick.

* The server never touches `EXIT`. Tests signal the child with **TERM** (INT is ignored
  in a `&` child and cannot be trapped).
* `Active = false` / `Terminate` from a handler: the response is still sent, then the loop
  ends. `SetActive true` while active → rc 1.
* 005 checks after `Serve`: port free, no listener pid, temp dir gone, `${srv}_req`/
  `${srv}_resp` gone, traps identical, fd count unchanged (`f=(/proc/$BASHPID/fd/*)`,
  fork-free).

### 2.7 Application

`THttpApplication` reuses `TCustomApplication`'s loop: `Run` (overridden) wraps
`inherited Run "$@"` in `Server.BeginServe` / `Server.EndServe`, so the application path
gets the PIPE/TERM handling and the Shutdown that the plain `Serve` has (C11). One `DoRun`
= one `Server.ServeOne`. Options come from the inherited parser, which only sees argv
given to `Create` — so `THttpApplication.new App "$@"` (C24). `AppRouter` exists from
`Create`, so routes may be registered before `Initialize`. A route that calls
`App.Terminate` ends the application after that response.

### 2.8 Performance model

Per request: one listener spawn (fork + `cat` relay + nc start, ≈35–45 ms, synchronous)
+ ≈2.7 ms of kklass object lifecycle + fork-free parse/send + the drained close
(≈15–60 ms). `bench.sh` (P3) reports requests/s on both bashes, the replay-only cost, and
parallel-client behaviour with the pre-spawn against the 6/8 single-listener baseline.
Only the fork-free replay path is gated (`010_Bench.sh`, loose ceiling); socket numbers
are reported, not asserted (C22, timing lessons).

### 2.9 What the unit demonstrates about kklass

| kklass feature | where |
|---|---|
| inheritance, multi-level | `TNetcatTransport : THttpTransport`; `THttpApplication : TCustomApplication`; `TAuthServer : THttpServer` (demo_oop) |
| `abstract` | `THttpTransport`, `THttpRouteObject`; D8 refuses a still-abstract route class |
| `override` + `inherited` with arguments | `THttpApplication.Initialize/Run/Terminate`; `TAuthServer.HandleRequest` → `inherited HandleRequest "$@"` |
| virtual dispatch via `$this` (template method) | `ServeOne` calls `$this.HandleRequest`; the subclass override wins |
| read-only property over a private field | every `THttpRequest` field, the transport's state, `RequestCount`, `LastError` |
| read/write property | `THttpResponse.Code/CodeText/ContentType/Content` |
| property with a setter that acts | `THttpServer.Active` (`= true` starts serving) |
| constructor/destructor, owned objects | server owns its transport; app owns server + router; per-request request/response/route objects; destructor chaining via empty base destructors |
| `private` / `protected` | private fields everywhere; `protected` `_handleConnection`/`_log` for descendant servers, `protected` transport fields for descendant transports |
| events as properties | `OnRequest`, `OnRequestError`, `OnAcceptIdle`, `OnLog`, `BeforeRequest`, `AfterRequest` |
| factory by class name | `RegisterRoute /hello/:name GET THelloRoute`; `ServerClass` (D9) |
| substitutability | `TReplayTransport` drives the same server with no sockets |
| composition with kcl | `TCustomApplication`, `TDictionary` (KV store), `TStopwatch` (access log) |
| state that outlives a request | demo counter and KV store |

### 2.10 The demo (`examples/demo.sh`, smoke-tested by `009_Demo.sh`)

```bash
source kcl/thttpserver/thttpapplication.sh; source kcl/tdictionary/tdictionary.sh
THttpApplication.new App "$@"; App.Title = 'kcl demo'   # "$@": --port reaches the option parser
TDictionary.new Store                                   # KV state survives requests
class TCounter ... ; TCounter.new Hits
class THelloRoute : THttpRouteObject; override proc HandleRequest; end   # factory route
App.RegisterRoute /                 GET    home
App.RegisterRoute /count            GET    Hits.Next            # object method as handler
App.RegisterRoute /kv/:key          GET    kvGet                # 404 when missing
App.RegisterRoute /kv/:key          PUT    kvPut                # body → Store
App.RegisterRoute /kv/:key          DELETE kvDel
App.RegisterRoute /hello/:name      GET    THelloRoute
App.RegisterRoute /quit             POST   quit                 # App.Terminate
App.Initialize && App.Run           # bash examples/demo.sh --port=8080
```

nc resolution as in the tests (on bash 5.2.37 here: `KCL_NC=/c/bin/msys64/usr/bin/nc.exe`).
`examples/demo_oop.sh` builds the same application in the §2.11 style (`TMyApp :
THttpApplication`, `TKvController`, `THelloRoute`, `TAuthServer` via `ServerClass`).
The README warns that `--address=0.0.0.0` exposes an unauthenticated store and may raise
a firewall prompt.

### 2.11 Extending: what a descendant implements

**Handler contract** (all three kinds): `$1` = request instance name, `$2` = response
instance name, `$3` = route DATA (functions / `inst.method`; a route object reads
`RouteData`).
* Read the request with **direct** calls — `$req.Method`, `$req.Content`,
  `$req.RouteParam id`, `$req.GetHeader host`, `$req.QueryField q` — value in `RESULT`,
  nothing printed, no fork. Never read a plain `var` of another object directly: it
  prints (§1.1).
* Answer with `$resp.Code = 404`, `$resp.Write TEXT`, `$resp.SetCustomHeader N V`; the
  server sends. A non-zero return with nothing sent → 500. `echo` goes to the server
  console.
* **Declare every variable `local`** (C25): a handler runs inside the router's, server's
  and application's frames, where every property is a nameref — a bare `Port=…`,
  `Title=…`, `Router=…` or `state=…` writes that object's property (the tawk precedent).
* **In a method override, pass the arguments on**: `inherited HandleRequest "$@"`,
  `inherited Terminate "$@"` — bare `inherited` outside a constructor passes none (C8).
* Destructors may always chain with `inherited` (every base has one), except that
  `THttpApplication.Destroy` itself does not (TCustomApplication has none).

| base | must implement | may override | lifetime |
|---|---|---|---|
| `THttpRouteObject` | `HandleRequest` (refused at registration if missing, D8) | `Create`, `Destroy` | one instance **per request**; state via `RouteData` or a controller |
| any class (a *controller*: its methods registered as `inst.method`) | nothing | — | as long as the caller keeps it: **this is where state lives** |
| `THttpApplication` | in practice `Initialize` (`inherited Initialize "$@"` first, then routes and the app's own objects) | `Destroy` (free them, then `inherited`), rarely `DoRun`; set `ServerClass` (D9) | the application's run |
| `THttpServer` | nothing | `HandleRequest` — cross-cutting logic; `inherited HandleRequest "$@"` routes, omitting it short-circuits; may call `protected` `_log` | the server's run |
| `TNetcatTransport` / `THttpTransport` | another nc flavour: `BuildArgv`; another backend: `Accept`, `CloseConnection`, `Shutdown` (setting the `protected` fields) | — | not application logic |

A minimal application needs no subclass at all (functions + `App.RegisterRoute`).

---

## 3. Pinned facts (each is a test)

1. The handler runs in the server shell: `$BASHPID` equal across requests, a counter
   increments (004).
2. `Content-Length` = bytes: `aжb` → `Content-Length: 4`, read back intact; a multibyte
   request body is read exactly (001, 004).
3. SIGPIPE, deterministic: `exec {fd}> >(exec true)`, wait for its end, `SendContent` to
   that fd → rc 1, nothing on stderr, the shell alive (002); over sockets a client closing
   early does not stop the next request being served (004, best effort).
4. Busy port → `Serve` rc 1, `LastError` = the bind line, no listener left (004).
5. `nc` not found → `Accept` rc 2 at once with `LastError`, **no respawn loop** (004).
6. `AcceptIdleTimeout=1000` → `OnAcceptIdle` fires with the listener still alive (no
   respawn); `Terminate` from it ends `Serve` (004).
7. D5, deterministic: the request-1 handler waits until slot 1's stderr shows `Listening
   on` and only then creates the "ready" marker; client 2 then connects **without a
   refusal** and is answered after request 1 (004). 8 parallel clients retrying on rc 7
   only all get 200 (004). **Measured P2: false as written** — 2–3 of 8 get rc 56, a reset
   of connections queued in the listener's accept backlog (§1.1). 004 pins instead: all 8
   get 200 when the (idempotent) GET is also retried on rc 55/56, and the access log shows
   **exactly 8** handled requests — so no retried request had been handled.
8. A connected but silent client gets **408** after `RequestTimeout` and the next client
   is served (004, 007).
9. The drained close delivers a 50 kB body complete, 5/5 (004); an HTTP/1.0 client that
   reads to EOF sees EOF (004).
10. After `Serve` and after `App.Run`: port free, no listener pid, temp dir gone, request/
    response instances gone, traps identical, fd count unchanged (005, 006).
11. TERM to the serving child: clean exit, both slots reaped; a connection held by the
    pre-spawned listener is closed without a response (005).
12. Every parser status (400/408/413/414/431/501/505, `gone`) from crafted raw requests
    (001 replay; 007 over `/dev/tcp`); a NUL in the body → 400 at once (001).
13. Hostile keys/paths/query values never execute (`pwn` marker never appears) and
    round-trip as data; `?=x`, `?&&`, `?=`, `?a=1&=2` do not abort the server (007).
14. `SetCustomHeader` with CR/LF or a server-owned name → rc 2; CR/LF in `ContentType` or
    `CodeText`, or `Code = 99`/`abc` → 500 with the default head (002).
15. `Date` is English and UTC whatever `LANG`/`TZ` (002).
16. `HEAD` on a GET-only route → the GET headers, no body; `Allow` lists HEAD (003, 004).
17. 404 vs 405 + `Allow`, `:param`, trailing `*rest`, default routes (fallback, pattern
    ignored, second default rc 1), the ≥3-argument METHOD rule, three handler kinds, a
    property wrapper refused as `inst.method`, the route object freed after each request
    (003).
18. `THttpApplication.new App --port=N` serves on N; `/quit` ends `Run` with no listener
    left; `ServerClass=TAuthServer` → 401 without the token, 200 with it; a non-server
    class → `Initialize` rc 2 (006).
19. D6/C7: inside a handler `$req.Method`, `$req.Content`, `$resp.Code` print nothing and
    set `RESULT`; `$req.Method = X` is rc 1, value unchanged (001, 002).
20. D7: DATA reaches `RouteData` and `$3` verbatim (spaces, `*`, `$(…)`, empty) (003).
21. D8: a still-abstract route class → rc 2, nothing printed, no constructor run (003).
22. `inherited HandleRequest "$@"` in a descendant server receives REQ RESP (006).
23. Parse → route → send under `TReplayTransport` is fork-free (§4) (001).

## 4. Test model

| file | what | transport |
|---|---|---|
| `001_Request.sh` | parser, limits, decoding, statuses, read-only fields, fork-free proof | replay |
| `002_Response.sh` | serializer, byte lengths, HEAD/1xx/204/304, headers, validation, Date, SIGPIPE | replay |
| `003_Router.sh` | pattern table, 404/405 + Allow, HEAD→GET, handler kinds, defaults, DATA, D8 | replay |
| `004_Server.sh` | real sockets, child bash serves, the test is the client; D5, idle, 408, close, bind/nc failures | netcat |
| `005_Lifecycle.sh` | leaks (instances, fds, temp dir, pids), traps, port release, TERM | netcat |
| `006_Application.sh` | options, routes, `/quit`, `ServerClass`, `inherited` with arguments | netcat |
| `007_Hostile.sh` | injection, empty and hostile keys, oversize (a declared Content-Length above the limit, body not sent), slowloris | replay + netcat |
| `008_Contract.sh` | `set -eu` main path | replay |
| `009_Demo.sh`, `010_Bench.sh` | both demos smoke; bench gate on the replay path only | netcat / replay |

**Fork-free proof** (C21) — the repo's three-part pattern
(`kcl/math/tests/016_D3_ReturnContract.sh:192-225`): `$BASHPID` unchanged, the replay run
also works under `PATH=''`, and the stored bodies `${Class}_method_body_*` contain no
`$(`, backtick or `|` on the request path.

**Socket-test rules** (timing lessons + C22): the server is a **child bash** under
`timeout` with a guard of **≥ 180 s**, its stdout/stderr always redirected to files (the
runner captures each test file with `$( … 2>&1 )` and waits for every holder of its
stdout); every curl has `-m`; the child ends on its own through `MaxRequests` **and** an
idle-tick budget (OnAcceptIdle terminates after N ticks), so a failed client does not
cost the whole guard; ports come from `20000 + (BASHPID*7919 + RANDOM) % 20000` with a
retry on a bind failure; clients retry **only on curl rc 7** (a retry on 52/56 may repeat
a non-idempotent request) or the test asserts `≥`; ordering is event-driven (marker
files), never sleeps; nc = `${KCL_NC:-$(command -v nc)}`, else
`/c/bin/msys64/usr/bin/nc.exe`; with none, socket files **skip visibly** — but the gate
on this machine requires them to **run** on both bashes. Suites unset every proxy
variable. Red-first against a stubbed skeleton, red counts in the ledger.

## 5. Phases

| phase | content | gate |
|---|---|---|
| **P0** | `thttpmessage.sh`, the transport base + `TReplayTransport`, tests 001/002/008 | 001/002/008 green on 5.2.37 and 5.3.9, sweep 0 [FAIL] on both |
| **P1** | `thttprouter.sh`, test 003 | 001–003/008 green both, sweep |
| **P2** | **opening spike**: reproduce §2.5 from `scratchpad/critic/p7.sh` inside a kklass class on both bashes (fallback rule §2.5); then `TNetcatTransport`, `THttpServer`, tests 004/005/007 | all green both (socket files **run**), sweep |
| **P3** | `thttpapplication.sh`, both demos, 006/009/010, `bench.sh`, README (API, §2.9, §2.11, deviations, numbers), TEST_COVERAGE_NOTES, kcl README §2 row (26 units), ledger closeout | all green both, sweep, bench numbers recorded |

**P0 DONE 2026-09-29** — `thttpmessage.sh` (THttpRequest, THttpResponse), `thttpserver.sh`
with THttpTransport + TReplayTransport only, tests 001/002/008: 137/137 on 5.2.37 (threaded
and single) and 5.3.9; red against the stub 47/42/34 FAIL; sweep 7434/7434, 0 [FAIL] on both
bashes (run in three parts: one `tests/tests.sh` now exceeds the 600 s tool limit). Deviations,
the measured facts found on the way (5.2.37 `${#var}` = 0 on a kklass var; EPOCHREALTIME's
separator follows the locale; a NUL inside a header line is dropped by `read`; a 64 KiB body
over a pipe ≈ 1.2 s) and the gate numbers are in the ledger's P0 entry.

**P1 DONE 2026-09-29** — `thttprouter.sh` (THttpRouteObject, THttpRouter), sourced by
`thttpserver.sh`; test 003 (106, incl. the 37-row pattern table parsed from its own comment
block) and 008 extended to the router (64): unit suite 265/265 on 5.2.37 (threaded and
single) and 5.3.9; red against the stub 102/106 (003) and 22/64 (008); sweep 7562/7562,
0 [FAIL] on both bashes (three parts each). Interpretations (a default route also matches its
own pattern; 405 wins over the defaults; HEAD → GET default; Before/After semantics and rc
rules), the kklass facts found (a redeclared `proc HandleRequest` without `override` is an
implementation, so D8 catches only a MISSING one) and the gate numbers are in the ledger's P1
entry. Review R1 (same day): captured route params are percent-decoded with path rules
(`+` literal, `%00` → 400, matching still on the raw PathInfo) — 003 grew to 131, the unit
suite to 290/290 on both bashes; details in the ledger's `review_remarks`.

**P2 DONE 2026-09-29** — opening spike first (§2.5 inside a throw-away kklass class, 6
scenarios, both bashes: works as designed, no fallback); then `TNetcatTransport` and
`THttpServer` in `thttpserver.sh` (+ `kcl/tstopwatch` for the access log), tests 004
(45: a replay-driven server section + real sockets), 005 (16), 007 (21), 008 extended
(88) and the shared socket helper `tests/_ths_socket.sh`: unit suite 396/396 on 5.2.37
(threaded ×3, single ×1) and 5.3.9 (threaded ×4); red against the stub 45/45, 16/16,
21/21, 24/88; kklass 344/344 and tcustomapplication 377/377 on both bashes (the full
sweep is the reviewer's). Measurements that contradicted the plan — the accept-backlog
resets (fact 7), the trap design (§2.6) — are in §1.1 and the ledger's `measured_p2`.
Review R1 (same day): Shutdown drains a CONNECTED slot instead of killing it (§2.5), 005
grew a listening-only Shutdown bound (17 tests); unit suite 397/397 threaded on both
bashes and single on 5.2.37; the 005 fork-storm check 10/10 on each bash before and after
(the storm did not reproduce the sweep failure; `probe_held` did: 27/30 → 60/60).

**P3 DONE 2026-09-29** — `thttpapplication.sh` (THttpApplication : TCustomApplication per
§1.3/§2.7: Run wraps `inherited Run "$@"` in BeginServe/EndServe, one DoRun = one
ServeOne, Destroy without `inherited`), `examples/demo.sh` (§2.10) and
`examples/demo_oop.sh` (§2.11), tests 006 (40), 009 (14), 010 (4), 008 extended (105),
`bench.sh`, `README.md`, `TEST_COVERAGE_NOTES.md`, the kcl README §2 row (twenty-six
units): unit suite 472/472 on 5.2.37 (threaded ×2, single ×1) and 5.3.9 (threaded ×2);
red against the stub 40/40, 12/105, 12/14, 4/4; kklass 344/344 and tcustomapplication
377/377 on both bashes; both demos run by hand on both bashes. On THttpServer: a
read-only `Stopping` property, and the `OnAcceptIdle` event moved from Serve's loop into
ServeOne so it fires under `App.Run` too; the application's `Port`/`Address` are
read/write properties (§1.3 rule). Found: kklass rewrote the text `$this.NAME` of a body
into its call form even inside quotes — register a method of the running instance as
`"$__inst__.M"` (the rewrite was removed in kklass R2_P8; `"$__inst__.M"` keeps working). Deviations, the measured costs (≈ 28 ms per request on the fork-free
replay path, ≈ 95–107 ms per request over sockets, 9–10 req/s) and the gate numbers are in
the ledger's P3 entry.

**Post-completion review 2026-09-30 DONE** — F1–F6 (§8): unit suite 497/497 on 5.2.37
(threaded ×2, single ×1) and 5.3.9 (threaded ×2); red against the unfixed code 20 FAIL
(001: 6, 003: 4, 004: 5, 007: 2, 008: 3); the 005 fork-storm check 5/5 on each bash;
kklass 344/344 and tcustomapplication 377/377 on both. Details in the ledger's
`review_2026_09_30`.

Mode: the kcl orchestration mode — one Opus worker per phase, review against the live
tree, remarks, commit kcl then the kbool bump; no push unless asked. The critic's probe
scripts live in the session scratchpad and may be gone; §1.1 and §2.5 carry everything
needed to rebuild them.

## 6. Traps

* **FIFO writer O_WRONLY only**; the listener child closes the other slot's fds; nc's
  stdin through the `cat` relay; close = drain to EOF, kill only past `CloseTimeout`.
* Only one `coproc` per shell — hence the FIFO slots; `$!` right after `exec {fd}< <(…)`
  is the listener.
* nc rc is always 1 — classify by the `-vv` stderr file; unknown stderr → fatal, never a
  silent respawn loop.
* `-w` limits accept only: it is an orphan TTL, not a request timeout.
* **A plain `var` of another object is never read directly** — it prints and leaves
  `RESULT` stale; use properties (§1.3 rule).
* **`inherited` in a method passes no arguments** — write `inherited Name "$@"`.
  `inherited` in a destructor needs a parent destructor (empty base destructors).
* `private` members used by descendants warn — `protected` for anything a subclass calls.
* **Empty assoc keys abort the whole top-level command** — `[[ -n $k ]]` first.
* `read -N`/`${#}` count characters under UTF-8 — `local LC_ALL=C`; `read -N` does not
  count a dropped NUL — `read -d '' -n` loop; `read -t` with LEFT ≤ 0 is never called.
* Inline `$'\r'` in a member body is lost by `build` — file-scope `__THS_CR`.
* `printf '%(…)T'` ignores `local TZ` — prefix form `LC_ALL=C TZ=UTC0 printf -v …`.
* `patsub_replacement`: quote `&` in `${x//…/…}` replacements.
* `$this.func` inside a member prints under `$( )`/pipe — call directly, or
  `kk.call_silent`; never capture a member with `$( )` on the request path.
* `func` ends with `kk._return v; return n`; unassigned `var` is unbound under `set -u`.
* `printf '%s'` everywhere; `%b` only on the backslash-doubled decode buffer.
* `trap '' PIPE` during serving; restore with `trap - INT TERM PIPE; eval "$saved"`;
  never touch EXIT; tests signal with TERM.
* `kill` of an exited-but-unreaped pid prints — always `2>/dev/null || :`.
* Proxy variables on this machine; `--noproxy '*'`.
* `python` is a hanging Store stub; probes with stdin closed and under `timeout`;
  `tasklist | grep nc.exe` also matches other processes (e.g. `Resilio Sync.exe`) —
  match the image name exactly.
* A KILLed server leaves listeners until `ListenerTTL` — tests always leave them a TTL
  and 005 checks the port is released.

## 7. Deliverables

`thttpmessage.sh`, `thttprouter.sh`, `thttpserver.sh`, `thttpapplication.sh`,
`examples/demo.sh`, `examples/demo_oop.sh`, `tests/001–010` + `tests.sh`, `bench.sh`,
`README.md`, `TEST_COVERAGE_NOTES.md`, `thttpserver_ledger.json` (phase SHAs), kcl README
§2 row.

## 8. Critic pass (2026-09-28)

One Opus critic, 67 tool uses, probes on both bashes. The supervisor re-verified C1/C3
(re-ran the working and the failing transport variant: 3/3 on each bash with the relay,
5.2 without the relay fails), C8 (`kklass_pascal.sh:153-163`), C12 (the empty-key abort)
and C15 (`local TZ` ignored) before folding. Every finding is folded in:

| id | sev | finding | where folded |
|---|---|---|---|
| C1 | blocker | O_RDWR FIFO writer: nc never sees EOF, `-c` never fires | §1.1, §2.5, §6 |
| C2 | blocker | close + immediate TERM truncates every response | §1.1, §2.5 CloseConnection, fact 9 |
| C3 | blocker | 5.2: a Git FIFO as msys64 nc's stdin dies on accept; `cat` relay fixes it | §1.1, §2.5, `StdinRelay` |
| C4 | major | pre-spawned listener inherits the live connection's writer | §2.5 spawn, fd hygiene |
| C5 | major | Accept timeout unclassified; silent client holds the server; `-w` vs D5 test | §2.5 Accept, `ListenerTTL`, `TimedOut`, facts 6–8 |
| C6 | major | "client left" catch-all → endless respawn on nc-not-found | §2.5 EOF classification, fact 5 |
| C7 | major | cross-object plain-var reads print (beyond the request) | §1.3 property rule, D6, facts 19 |
| C8 | major | bare `inherited` in a method drops arguments | §2.11, §6, fact 22 |
| C9 | major | `inherited` in a destructor without a parent destructor → rc 127 | §1.3 empty base destructors, §2.11 |
| C10 | major | `${inst}_data` collides with kklass storage | `_rdat`, §2.1 |
| C11 | major | app path had no PIPE ignore, no Shutdown, unmapped idle rc, no MaxRequests | `BeginServe/EndServe`, `App.Run/DoRun` |
| C12 | major | empty query-field name aborts the server | §2.2, fact 13 |
| C13 | major | HEAD on a GET route → 405 | §2.4, fact 16 |
| C14 | major | response splitting via `ContentType`/`CodeText`/`Code` | §2.3, fact 14 |
| C15 | minor | `local TZ` ignored, localized Date | §2.3, fact 15 |
| C16 | minor | SIGPIPE messages, restore, non-deterministic socket test | §2.3, §2.6, fact 3 |
| C17 | minor | D8 probe instance: false positives, side effects | D8 → abstract flag |
| C18 | minor | `read -N` waits over a NUL | §2.2 body loop |
| C19 | minor | `read -t 0/-1` pitfalls; 408 vs gone | §2.2 |
| C20 | minor | `ReadFrom` rc 1 + status breaks §1.2 | rc 0 + status in `RESULT` |
| C21 | minor | `$BASHPID` alone does not prove fork-free | §4 three-part proof |
| C22 | minor | runner captures stdout, retries, bench under load, oversize test | §4 |
| C23 | minor | private helpers used by descendants warn | `protected`, private state |
| C24 | minor | demo without `"$@"`; router must exist before Initialize; nc resolution | §2.7, §2.10 |
| C25 | minor | handler assignments hit object properties (dynamic scope) | §2.11 `local` rule |
| C26 | minor | temp dir outlives a KILL, no EXIT trap allowed | deviation (d), `mktemp -d` |
| nits | — | spawn not overlapped; RESULT stale not empty; ≥3-arg METHOD rule; default-route meaning; `demo_oop` in §1.2; method-list check; handler regex; `-n 8194`; OnLog sanitising; `patsub_replacement`; `HeadersSent` dropped; 501 for unknown methods; Host on 1.1; `gone`; stale instances; `0.0.0.0` warning; `DeleteRoute` cut | throughout |

### Post-completion review (2026-09-30)

A deep code review of the finished unit found six issues; all fixed red-first (20 FAIL
against the unfixed code), details and red counts in the ledger's `review_2026_09_30`:

* **F1** (router) — every route-class dispatch used the one name `__ths_route_obj`: a
  route object routing through a sub-router where a route class won too had its live
  instance deleted by the inner pass, and the outer pass then ABORTED the whole top-level
  command. Fix: one name per nesting level (`__ths_route_obj`, `…1`, `…2`), the level a
  `local` inherited through dynamic scope (§2.4).
* **F2** (parser) — a repeated `Host` was joined like any header; now a second `Host` →
  400 (RFC 9112 §3.2), whatever the case and values (§2.2).
* **F3** (server) — `gone` counted toward `RequestCount`, so gone probes could use up
  `MaxRequests`; now only answered connections count (408 included) (§2.6; amends the P2
  interpretation "RequestCount counts every handled connection incl. gone/408").
* **F4** (parser + server) — the HEAD flag of an error response came from the transport's
  `FirstLine` prefix, '' under replay; now ReadFrom keeps Method/URI/ProtocolVersion after
  a later-stage status and the server reads `REQ.Method` (§2.1; amends the P0
  deviation-9 contract).
* **F5** (parser + transport) — `FIRSTLINE=''` meant both "nothing consumed" and "an
  empty line consumed": a bare LF before the request line was 200 over netcat, 400 in the
  direct parse. Now `ReadFrom … CONSUMED` + `THttpTransport.LineConsumed` (§1.3, §2.2).
* **F6** (transport, no behaviour change) — the per-slot `if (( s == 0 ))` selection,
  copied at ~15 sites, became `local -n` onto the kklass private vars (`_rd$s` …),
  probed first on both bashes (read, write, rebinding in a loop, no visibility warning,
  no fork); the 005 fork-storm check 5/5 on each bash.

## 9. Side observation (outside this unit)

`kklass/kklass_serializable.sh` `_addSerializable_json` embeds property values into JSON
**without escaping** (`\"${prop}\"`), so a value with `"` or `\` yields invalid JSON. Read
in the code, not probed. The demo does not use `toJSON`; worth a kklass ledger entry if
confirmed. A public `kk.isAbstract` (D8) would be a second small kklass roadmap item.
