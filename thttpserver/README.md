# thttpserver — a minimal HTTP server on kklass + GNU netcat or socat

> **Status: COMPLETE (P0–P3; the socat backend L2.7-N2).** Ten classes in four files — the messages
> (`THttpRequest`, `THttpResponse`), the router (`THttpRouteObject`,
> `THttpRouter`), the transport seam (`THttpTransport`, `TReplayTransport`,
> `TNetcatTransport`, `TSocatTransport`), the server (`THttpServer`) and the application
> (`THttpApplication : TCustomApplication`) — plus two runnable examples, the
> bench and the docs. Suite `tests/001`–`010` = **533 checks, green on bash
> 5.2.37 and on bash 5.3.9**, threaded and (5.2.37) under `--mode single`, the
> socket tests **run** (not skipped) on both — on GNU netcat under Windows,
> on socat in the Linux lab VMs. A post-completion review
> (2026-09-30, F1–F6) fixed nested route-object dispatch, a duplicate `Host`,
> `gone` counting toward `MaxRequests`, the HEAD flag of a failed request, a
> consumed empty request line, and deduplicated the transport's slot code (§7). What the tests pin, member by
> member: **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Design record:
> [PLAN.md](PLAN.md) (§1.1 the measured facts, §2 the design and the owner
> decisions D1–D9, §8 the critic pass) and
> [thttpserver_ledger.json](thttpserver_ledger.json).

A **kcl addition with its own names** (D1): there is no FPC/Delphi source. FPC
fcl-web (`fphttpserver.pp`, `httpdefs.pp`, `httproute.pp`, `fphttpapp.pp`) is a
design reference only — `Active := True` blocks, `OnRequest`, route objects,
route data, default routes, the 404/405 texts, `AcceptIdleTimeout = 0` are
borrowed and say so; there is no parity requirement.

**The goal is to demonstrate kklass, not to be a web server.** A small, honest,
tested HTTP/1.0-style server whose value is the object model: every kklass
feature that matters — inheritance, `abstract`, `override` + `inherited` with
arguments, virtual dispatch through `$this`, read-only and read/write
properties, a property setter that acts, constructors/destructors with owned
objects, `private`/`protected`, events as properties, factory by class name,
composition with other kcl units — appears where it is the natural tool (§8).

**The one idea.** The request handlers run **in the server's own shell**, so
objects live across requests: a counter, an in-memory key-value store, a
router. The classic bash web server (`nc -e script`, `ncat --sh-exec`) starts a
fresh shell per connection — state is lost, and with kklass loaded every
request would pay a cold `source` (1–3.5 s on this machine). Here only the
listener (`nc`, or `socat`) is started per connection.

**How a connection is noticed.** Never *detected*: a listener `nc` (or
`socat`) is started **in advance** and blocks in accept, while bash waits in
`read -t` on its stdout. The first bytes of a request arriving there **are**
the event; the listener's stderr (`Listening on …`, `Connection from …` for
GNU nc; `N listening on …`, `N accepting connection from …` for socat) tells
the other states apart. One process = one connection (GNU nc 0.7.1 has no
`-k`; socat runs without `fork`), so the server alternates two listener slots
and starts the next listener as soon as the current request line has arrived
(D5) — see §6.

---

## 0. Quick start

```bash
bash kcl/thttpserver/examples/demo.sh --port=8080        # or: -p 8080
```

```text
kcl demo: http://127.0.0.1:8080/   (POST /quit or Ctrl-C to stop)
```

```bash
curl --noproxy '*' http://127.0.0.1:8080/count                     # 1, then 2, 3, …
curl --noproxy '*' -X PUT --data-binary 'hello' http://127.0.0.1:8080/kv/greeting   # 201
curl --noproxy '*' http://127.0.0.1:8080/kv/greeting              # hello
curl --noproxy '*' http://127.0.0.1:8080/hello/world              # Hello, world!
curl --noproxy '*' -X POST http://127.0.0.1:8080/quit             # bye — the demo exits 0
```

The demo prints one access-log line per request (`127.0.0.1:62414 PUT
/kv/greeting 201 15 29` — address, method, URI, code, body bytes, ms).
[`examples/demo_oop.sh`](examples/demo_oop.sh) is the same application written
the descendant way (§4), with a bearer token (`--token=T` or `$DEMO_TOKEN`).

The smallest application needs no class of its own:

```bash
source /path/to/kbool/kbool.sh
kk.uses thttpapplication

hello() {                                   # handler: REQ RESP DATA
    local who                               # every variable local (§3)
    $1.RouteParam name; who="$RESULT"       # a direct read: nothing printed, no fork
    $2.Write "Hello, $who!"                 # the server sends; echo would go to the console
}

THttpApplication.new App "$@"               # "$@": --port=N / -p N / --address=A
App.RegisterRoute /hello/:name GET hello    # routes may come before Initialize
App.Initialize || exit 2
App.Run                                     # blocks until TERM / INT / App.Terminate
App.delete
```

Without the application, the server alone:

```bash
source /path/to/kbool/kbool.sh
kk.uses thttpserver
THttpRouter.new R;  R.RegisterRoute /hello/:name GET hello
THttpServer.new S;  S.Port = 8080;  S.Router = R
S.Serve                                     # or: S.Active = true (FPC style) — blocks
S.delete; R.delete
```

**This machine exports `HTTP_PROXY`** — plain `curl http://127.0.0.1:…` goes
through the proxy (a 503). Use `--noproxy '*'`. **Cyrillic on a native curl's
command line** passes through the Windows code page (`дом` → `???`): send
multibyte data from a file, `--data-binary @file`.

---

## 1. Files and classes

| file | classes | sources |
|---|---|---|
| `thttpmessage.sh` | `THttpRequest`, `THttpResponse` | kklass |
| `thttprouter.sh` | `THttpRouteObject` (abstract), `THttpRouter` | + thttpmessage.sh |
| `thttpserver.sh` — **the entry point** | `THttpTransport` (abstract), `TReplayTransport`, `TNetcatTransport`, `THttpServer` | + thttprouter.sh, [`../tstopwatch`](../tstopwatch/README.md) |
| `thttpapplication.sh` | `THttpApplication : TCustomApplication` | + thttpserver.sh, [`../tcustomapplication`](../tcustomapplication/README.md) |
| `examples/demo.sh`, `examples/demo_oop.sh` | the showcase (§0, §4) | + [`../tdictionary`](../tdictionary/README.md) |

Every file is a kbool unit (the unit header, [kcl/README.md §1.10](../README.md#110-every-unit-is-a-kbool-unit);
the four are one package: `kk.uses thttpserver` or `kk.uses thttpapplication`
loads what it needs), has the §1.6 locale self-heal and loads under
`set -eu`. Prefixes: `__ths_` (locals), `__THS_` (file-scope constants),
`ths.` (file-scope helpers: a namespace the package's files declare with
`kk.namespace ths`, owned by `thttpmessage`). Class names carry `THttp` to stay
clear of generic names (a class declared again from another file is a
*Duplicate identifier*).

---

## 2. API

`func` members answer in `RESULT` (a direct call prints nothing); rc 1 is a
miss with `RESULT=''`, rc 2 a malformed call, each with one `kk.debug` line
under `VERBOSE_KKLASS=debug` and silence otherwise (kcl README §1.2).
**Properties** read the same way: `$req.Method; m="$RESULT"`.

### THttpRequest — one parsed request

| member | kind | |
|---|---|---|
| `Method`, `URI`, `PathInfo`, `QueryString`, `ProtocolVersion`, `Content`, `RemoteAddress` | read-only properties | `PathInfo` = URI before `?`, **not** percent-decoded; `QueryString` after the first `?`; `RemoteAddress` = `IP:PORT` from nc (`''` under replay). A write is rc 1 (deviation e) |
| `ContentLength` | read-only property | the **byte** length of `Content` |
| `GetHeader NAME` | func | case-insensitive; a repeated header joined with `, ` (a second `Host` is a 400 instead); rc 1 absent, rc 2 for `''` |
| `HasHeader NAME` | predicate | rc 0 / 1 (an answer, silent); rc 2 for `''` |
| `HeaderNames OUTARR` | func | lower-cased names in arrival order, `RESULT` = count; rc 2 for a malformed / reserved array name |
| `QueryField NAME` | func | percent-decoded value of the **first** occurrence (`+` → space); rc 1 absent or rejected (`%00`); rc 2 for `''` |
| `RouteParam NAME` | func | a value the router captured (`:name`, `*name`), percent-decoded with path rules (`+` stays `+`); rc 1 absent |
| `SetRouteParam NAME VALUE` | proc | the router's use; rc 2 for `''` |
| `ReadFrom FD DEADLINE_US MAXBODY [FIRSTLINE [REMOTE [CONSUMED]]]` | func | the parser (the server's use). **rc 0** with `RESULT` = `0` parsed, or `400 408 413 414 431 501 505` to answer, or `gone` (the client left); rc 2 only for a malformed call (C20). `FIRSTLINE` = a request line the transport already consumed; `CONSUMED` 1 = it did, **even when `FIRSTLINE` is empty** (then 400); 0 / omitted = a non-empty `FIRSTLINE` was consumed, an empty one means read the line from `FD` (review F5) |

The parser, in order: request-line length (414) → structure / control
characters (400) → `HTTP/D.D` (400) → method (`GET POST PUT DELETE OPTIONS
HEAD TRACE PATCH`, else 501) → target starts with `/` (origin-form, else 400) →
version `1.0`/`1.1` (505) → headers (> 8192 bytes or > 100 of them 431; a
non-token name, obs-fold, a control character in a value, a second `Host` in
any case and with any value — RFC 9112 §3.2 — 400) → HTTP/1.1 without `Host`
(400) → `Transfer-Encoding` (501) → `Content-Length` (non-numeric
or two different values 400, above MAXBODY 413 — the body is not read) → the
body (a NUL → 400 at once; short at the deadline 408, at EOF `gone`). Every
`read` gets the time left to the deadline; a spent deadline is 408 without a
`read`. Bare LF is accepted as a line end; an empty line BEFORE the request
line (a bare LF or a CRLF) is a 400 — there is no RFC 9112 §2.2 leading-CRLF
skip, and over the netcat transport the answer is the same (review F5).

**The fields after a status** (review F4): a status from the request line
itself (414, 400, 501, 505) leaves every field empty; once the request line is
accepted, `Method`, `URI` and `ProtocolVersion` are set and stay set whatever
a later stage returns (400, 408, 413, 431, 501, `gone`) — the server answers a
failed HEAD without a body, and the access log names the request.
`PathInfo`, `QueryString`, `Content` and the query fields are set only on
status 0 (the router refuses a request without a `PathInfo`).

### THttpResponse — filled by the handler, sent by the server

| member | kind | |
|---|---|---|
| `Code`, `CodeText`, `ContentType`, `Content` | read/write properties | defaults 200, `''` (→ the reason from the table), `text/plain; charset=utf-8`, `''` |
| `ContentSent` | read-only property | 1 after any write attempt |
| `Write TEXT…` | proc | appends the arguments joined by one space, verbatim, no newline (handlers never `echo`) |
| `SetCustomHeader NAME VALUE` | proc | rc 2 for a non-token NAME, CR/LF/NUL in VALUE, or a server-owned name (`Content-Length Connection Date Server Content-Type` — use `ContentType`) |
| `GetCustomHeader NAME` | func | case-insensitive; rc 1 absent, rc 2 for `''` |
| `SendRedirect URL [CODE]` | proc | **sets** Code (302, or 300–399), clears CodeText, sets `Location` (FPC semantics); the server sends. rc 2 for a bad code or URL |
| `Attach FD [ISHEAD [BANNER]]` | proc | the server's use |
| `SendContent` | proc | the server's use: **one** `printf` of head + body, errors silenced; rc 1 if already sent or the write failed |

The head: `HTTP/1.1 CODE TEXT`, `Date` (English, UTC, whatever `LANG`/`TZ`),
`Server`, `Content-Type`, the custom headers in insertion order,
`Content-Length` (**bytes**: `aжb` → 4), `Connection: close`. 1xx/204: no body,
no `Content-Length`; 304 and HEAD: no body. **Validated at send** (C14): a
`Code` that is not an integer 100–599, or CR/LF/NUL in `CodeText`,
`ContentType` or the server's banner → **500 with the default head**, never
sent raw.

### THttpRouteObject — the base of a route class (abstract)

`var RouteData` (the route's DATA, assigned before the call), `constructor
Create`, `destructor Destroy` (empty, so a descendant may chain with
`inherited`), **`abstract proc HandleRequest REQ RESP`**. One instance per
request (§3).

### THttpRouter

| member | kind | |
|---|---|---|
| `RegisterRoute PATTERN HANDLER` / `RegisterRoute PATTERN METHOD HANDLER [ISDEFAULT [DATA]]` | proc | with 2 arguments METHOD is `ALL`; with ≥ 3 the 2nd is **always** METHOD (`GET POST PUT DELETE OPTIONS HEAD TRACE PATCH ALL`). ISDEFAULT `0`/`1`, DATA any string, kept verbatim (D7). rc 0 · rc 1 a second default for the same METHOD · rc 2 malformed |
| `RouteCount` | read-only property | |
| `RouteRequest REQ RESP` | proc | `BeforeRequest` → the handler (or 404 / 405 + `Allow`) → `AfterRequest`; rc = the first non-zero of the three. Never sends |
| `FindRoute PATH METHOD` | func | `RESULT` = the route index; rc 1 + `REPLY` = 404/405 on a miss |
| `BeforeRequest`, `AfterRequest` | vars (events) | handler names, `REQ RESP` |

**HANDLER is resolved once, at registration**, and must match
`^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$`:

1. a **class** deriving from `THttpRouteObject` and not abstract (D8: a class
   that does not implement `HandleRequest` is refused with rc 2, nothing
   printed, no constructor run) → per request `CLASS.new`, `RouteData = DATA`,
   `HandleRequest REQ RESP`, `.delete` — under `__ths_route_obj`, and under
   `__ths_route_obj1`, `2`, … for a dispatch nested inside a route object's
   `HandleRequest` (a route object may route through another router: the
   inner pass never touches the outer, live object — review F1);
2. **`INST.METHOD`** — a live instance and a *method* of its class (a property
   wrapper such as `INST.SomeVar` is refused) → `INST.METHOD REQ RESP DATA`;
   the object's state persists;
3. a **function** → `FN REQ RESP DATA`.

Anything else is rc 2. The route patterns are in §5.

### THttpTransport (abstract), TReplayTransport, TNetcatTransport, TSocatTransport — the network seam

`THttpTransport`: read-only properties `InFd`, `OutFd`, `FirstLine`,
`LineConsumed`, `TimedOut`, `RemoteAddress`, `LastError` over **protected**
fields a descendant sets (`LineConsumed` 1 = Accept consumed the request line,
which is `FirstLine` even when that is empty — review F5; the server passes it
to `ReadFrom` as CONSUMED); `abstract func Accept IDLE_MS REQUEST_TIMEOUT_S` (rc 0 a
connection · 1 an idle tick · 2 fatal), `abstract proc CloseConnection`,
`abstract proc Shutdown`; an empty destructor (C9).

`TReplayTransport` — the **test double: no socket, no fork**.
`AddRequestFile FILE` (one raw request per Accept, in order; rc 2 for `''`, rc
1 unreadable), `ResponseFile INDEX` (`RESULT` = the capture path
`<file>.N.out`), Accept rc 2 when no file is left. It drives the *same* server
the socket tests drive — substitutability, and the fork-free proofs.

`TNetcatTransport` — GNU netcat 0.7.1, two alternating listener slots:

| var | default | |
|---|---|---|
| `NcBinary` | `''` | `''` → `$KCL_NC` → `nc` on PATH (a fork-free PATH walk); none → BuildArgv rc 1, Accept rc 2 `nc not found …`, no respawn loop; an nc that is not GNU netcat → BuildArgv rc 2, Accept rc 2 with the `no usable network backend: …` LastError (see *Network backend*; with `NcBinary` and `KCL_NC` both empty — an nc found on PATH — the reason ends `; TNetcatTransport runs GNU netcat only (use TSocatTransport, or leave THttpServer.Transport '' for automatic selection)`) |
| `Address` / `Port` | `127.0.0.1` / `8080` | |
| `ListenerTTL` | 60 | `nc -w`: an orphan's time-to-live only (it limits accept, not a connection) |
| `CloseTimeout` | 2 | the bound of the drained close |
| `StdinRelay` | 1 | nc's stdin through `cat` (required under bash 5.2.37, §6); 0 only for a same-runtime nc |

`BuildArgv OUTARR` (virtual) → `NC -l -c -vv -n -w TTL -s ADDR -p PORT`, after
the nc was found (rc 1 `nc not found …` otherwise) **and identified as GNU
netcat** (rc 2, LastError = the reason, the array left empty, otherwise); a
descendant for another listener overrides it — as `TSocatTransport` does.

`TSocatTransport : TNetcatTransport` — the same mechanism (slots, relay,
drained close, Accept / CloseConnection / Shutdown inherited unchanged) over
**socat >= 1.7.4**; it overrides `BuildArgv` and `_state` only:

| var | default | |
|---|---|---|
| `SocatBinary` | `''` | `''` → `$KCL_SOCAT` → `socat` on PATH; none → BuildArgv rc 1 `socat not found …`; a socat without `accept-timeout` → rc 2 with that reason |
| `Address` / `Port` / `ListenerTTL` / `CloseTimeout` / `StdinRelay` | as above | `Address` may only contain `0-9 A-Z a-z . : -` (else BuildArgv rc 2: a `,` would add socat options); `ListenerTTL` is socat's `accept-timeout`; `NcBinary` is inherited and unused |

`BuildArgv OUTARR` → `SOCAT -d -d -lpsocat -t 0.5
TCP4-LISTEN:PORT,bind=ADDR,reuseaddr,accept-timeout=TTL STDIO` (an `Address`
with `:` → `TCP6-LISTEN:PORT,bind=[ADDR]`; `-lpsocat` fixes the log name,
which socat otherwise takes from argv[0] — a binary named `socat1` would log
`socat1[PID]`). `_state` reads the `-d -d` lines
(`YYYY/MM/DD HH:MM:SS socat[PID] S TEXT`): `N listening on` → listening; `N
accepting connection from AF=… A:P on …` → connected, `RemoteAddress` = `A:P`
(`[::1]:P` for IPv6 — socat prints all eight groups, the address is put in
the RFC 5952 short form; an IPv4-mapped peer comes out as `::ffff:7f00:1`,
not the dotted form); `W accept: Connection timed out` (FreeBSD: `Operation timed out`; FreeBSD
also writes `LEN=16 AF=2` where Linux writes `AF=2`) → the TTL (respawn);
the first `E` / `F` line → fatal, `LastError` = its text after the severity
letter (a busy port: `bind(5, {AF=2 127.0.0.1:P}, 16): Address already in
use`); every other line is ignored. `_state` is **public** in the descendant:
called from the base's Accept / Shutdown, a private or protected override
prints a kklass visibility warning (measured).

#### Network backend

thttpserver chooses and identifies its listener before it ever starts one
(`ths._backend [NCBIN] [SOCATBIN]`, a plain function of `thttpserver.sh`;
`THttpServer.BeginServe` calls it when no `Transport` is set, each transport's
`BuildArgv` for its own binary). Windows keeps GNU netcat 0.7.1, byte for byte
as before; a Linux whose `nc` is OpenBSD netcat / Ncat / nc.traditional runs on
**socat** (decision D2 of the launch triage: OpenBSD nc keeps its listening
socket open while it serves and sets `SO_REUSEPORT`, so with two pre-spawned
slots the next client lands in the busy slot's backlog — 10 of 20 runs;
socat and ncat close the listener after the accept, 10 of 10).

Precedence — the first rule that applies decides:

1. **an explicit netcat** — `NCBIN` (BuildArgv passes its resolved
   `NcBinary`), else `$KCL_NC`: GNU netcat → `gnu`; an existing nc that is
   not GNU → `none` (socat is **not** consulted); no such file → `missing`;
2. **else an explicit socat** — `SOCATBIN` (`SocatBinary`), else
   `$KCL_SOCAT`: passes the probe → `socat`, else `none`;
3. **else automatic**: GNU `nc` on PATH → `gnu`; else `socat` on PATH that
   passes the probe → `socat`; else a socat on PATH that fails it → `none`;
   else an existing non-GNU nc → `none`; else `missing`.

| backend | meaning |
|---|---|
| `gnu` | `NC --version` prints `GNU Netcat` (netcat 0.7.1 — msys64's; Debian/Ubuntu `netcat-traditional` is NOT it) → `TNetcatTransport` |
| `socat` | `SOCAT -hhh` lists `accept-timeout` (socat >= 1.7.4) → `TSocatTransport` |
| `none` | refused: BeginServe rc 2 with the reason as LastError, before it installs a trap or creates a transport; a transport's BuildArgv / Accept rc 2 with it |
| `missing` | neither exists. BeginServe goes on with a `TNetcatTransport`, whose Accept reports `nc not found …` (rc 2; `Serve` rc 1) |

A non-GNU nc is named by its `--version` text (a second probe, `-h`, only if
that names nothing): `OpenBSD netcat`, `Ncat`, `BusyBox nc`, `traditional nc
(v1.10)`, an OpenBSD-upstream usage line `[-46…` (no name in it, e.g.
Fedora's nc) also counts as `OpenBSD netcat`, else `unknown nc`. The reasons,
exactly:

* automatic, a non-GNU nc, no socat: `no usable network backend: <flavour>
  at <nc> is not GNU netcat 0.7.1 (refused: thttpserver never runs another
  netcat with GNU flags); no socat on PATH — install socat (apt/dnf/apk/pkg
  install socat) or GNU netcat 0.7.1 (Homebrew netcat, FreeBSD net/gnetcat,
  Arch gnu-netcat, or from source)`;
* an explicit non-GNU nc: `no usable network backend: <flavour> at <nc> is not
  GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU
  flags); socat was not consulted because the netcat was set explicitly
  (NcBinary/KCL_NC)`;
* an explicit socat failing the probe: `no usable network backend: <socat>
  does not support accept-timeout (socat >= 1.7.4 needed)`;
* automatic, a non-GNU nc and a socat on PATH failing the probe (`none`, BIN
  = the nc): `no usable network backend: <flavour> at <nc> is not GNU netcat
  0.7.1 (refused: thttpserver never runs another netcat with GNU flags);
  <socat> does not support accept-timeout (socat >= 1.7.4 needed)`;
* automatic, no nc and a socat on PATH failing the probe (`none`, not
  `missing`; BIN = the socat): `nc not found (NcBinary, KCL_NC, PATH);
  <socat> does not support accept-timeout (socat >= 1.7.4 needed)`;
* `TNetcatTransport.BuildArgv` with `NcBinary` and `KCL_NC` empty and a
  non-GNU nc on PATH: the nc part, then `; TNetcatTransport runs GNU netcat
  only (use TSocatTransport, or leave THttpServer.Transport '' for automatic
  selection)`;
* neither: `nc not found (NcBinary, KCL_NC, PATH); no socat on PATH either`
  (an explicit nc that does not exist: `nc not found (NcBinary, KCL_NC,
  PATH)`).

Why another nc is refused rather than tried: the listener's flags are GNU's.
In **ncat** and **nc.traditional** `-c` / `-e` execute a command for every
connection (the GNU flag `-c` is "run this command" there, not "close on EOF"
— a hazard, not a harmless mismatch); the **OpenBSD** nc has no accept
timeout (`-w` limits only connect and idle), so an orphaned listener would
live forever. The probes (`--version`, `-h`; `-hhh` for socat) are the only
things an unidentified binary is ever run with. The result is cached per
`"$PATH|$KCL_NC|$KCL_SOCAT|NCBIN|SOCATBIN"` (a hit forks nothing; a miss one to
three forks per process: `--version`, perhaps `-h`, `-hhh`).

**Where to get one.** GNU netcat 0.7.1: msys64 (`/c/bin/msys64/usr/bin/nc.exe`
here), Homebrew `netcat`, FreeBSD `net/gnetcat`, Arch `gnu-netcat`, or from
source; Debian/Ubuntu/Fedora/Alpine do not package it. socat: `apt install
socat`, `dnf install socat`, `apk add socat`, `pkg install socat` (measured:
1.8.0.0 Ubuntu 24.04, 1.8.0.3 Debian 13, 1.8.1.1 Fedora, 1.8.1.3 FreeBSD 15.1).

**The two backends differ** in their events and their linger, nothing else:

| | GNU netcat (`TNetcatTransport`) | socat (`TSocatTransport`) |
|---|---|---|
| listener | `nc -l -c -vv -n -w TTL -s ADDR -p PORT` | `socat -d -d -lpsocat -t 0.5 TCP4-LISTEN:PORT,bind=ADDR,reuseaddr,accept-timeout=TTL STDIO` |
| bound / accepted | `Listening on …` / `Connection from A:P` | `… N listening on …` / `… N accepting connection from AF=… A:P on …` (FreeBSD: `LEN=16 AF=2 A:P`) |
| TTL expired | `Listen mode failed: Connection timed out` | `… W accept: Connection timed out` (FreeBSD: `Operation timed out`; exit 0) |
| busy port (`LastError`) | `Error: Couldn't setup listening socket (err=-3)` | `bind(5, {AF=2 127.0.0.1:P}, 16): Address already in use` |
| after the server's stdin EOF | `-c`: closes the connection | `-t 0.5`: shuts the socket's write side, exits at the client's EOF or **0.5 s** later (measured 514–847 ms with a client that keeps the connection open, 1–6 ms with one that closes — below `CloseTimeout` 2 s, the drain never needs the kill) |
| a client that half-closes after its request | — | socat waits at most `-t` 0.5 s for the response: a handler slower than that answers nobody |

The socket tests run on whichever backend the detection picks and report
`SKIP: <the reason>` (case counts unchanged) where there is none.

### THttpServer

| member | kind | |
|---|---|---|
| `Address`, `Port` | vars | `127.0.0.1`, `8080` (copied to the owned transport) |
| `Transport` | var | `''` → an **owned** `${inst}_tr` created by BeginServe — a `TSocatTransport` when the detection says `socat`, else a `TNetcatTransport` (*Network backend*) — freed by EndServe |
| `Router` | var | a `THttpRouter` or `''` |
| `OnRequest` | var (event) | `handler REQ RESP` — wins over `Router` |
| `OnRequestError` | var (event) | `handler REQ RESP RC` — a handler returned non-zero with nothing sent (then a fresh 500 is sent) |
| `OnAcceptIdle` | var (event) | `handler SERVER` — every idle tick (fired by `ServeOne`, so under `Serve` **and** `App.Run`) |
| `OnLog` | var (event) | `handler SERVER LINE` — `ADDR METHOD URI CODE BYTES MS` per answered request, control characters → `?`, empty fields `-` (METHOD and URI are `-` only when the request line did not parse) |
| `AcceptIdleTimeout` | var | ms, default **0 = off** (D4); ticks are ~1 s grained |
| `RequestTimeout` | var | s, default 10 → 408 |
| `MaxContentLength` | var | default 65536 → 413 |
| `MaxRequests` | read/write property | 0 = unlimited |
| `ServerBanner` | var | `Server:` header, default `kcl-thttpserver` (`''` → none) |
| `RequestCount`, `LastError`, `Stopping` | read-only properties | `Stopping` = 1 once Terminate / `Active = false` / a signal asked the server to stop |
| `Active` | read/write property | **`= true` blocks in Serve** (as FPC); `= false` from a handler → Terminate; rc 1 if already active, rc 2 for a non-boolean |
| `Serve` | proc | BeginServe; ServeOne until stopped; EndServe. rc 0, or **rc 1 on a transport fatal** (`LastError`, e.g. `Error: Couldn't setup listening socket (err=-3)` for a busy port under GNU nc, `bind(…): Address already in use` under socat) |
| `BeginServe` / `EndServe` | procs | save the traps (the one fork of a Serve), `trap '' PIPE`, INT/TERM → a stop flag; create/free the owned transport; restore the traps exactly. BeginServe rc 2 for a bad number, a non-transport `Transport`, or (no `Transport`) a detected backend `none` |
| `ServeOne` | func | accept + handle ONE connection: rc 0 (`RESULT` = the code sent, or `gone`) · 1 idle / a client that left / a signal · 2 fatal. `RequestCount` + 1 for every answered connection (408 included), **never for `gone`** (review F3) |
| `Terminate` | proc | stop after the current request (its response is still sent) |
| `HandleRequest REQ RESP` | proc, **virtual** | `OnRequest`, else `Router.RouteRequest`, else 404 — the override point (§4) |
| `_handleConnection`, `_log` | **protected** | for descendant servers |

### THttpApplication : TCustomApplication

| member | kind | |
|---|---|---|
| `Port`, `Address` | read/write properties | 8080, 127.0.0.1; `Initialize` resolves `--port=N` / `-p N` / `--address=A` and writes the result back |
| `ServerClass` | var | default `THttpServer` (D9); a concrete descendant plugs in |
| `Server`, `AppRouter` | read-only properties | the owned `${inst}_server` (after Initialize) and `${inst}_router` (from Create) |
| `Create [ARG…]` | constructor | the inherited one stores the argv for the option parser — hence **`THttpApplication.new App "$@"`** (C24); creates AppRouter, so routes may be registered **before** Initialize |
| `Initialize` | override proc | `inherited Initialize "$@"`; the options; `ServerClass.new`; wires Router/Port/Address. rc 2 (nothing created) for a port that is not an integer 1–65535, an empty address, or a ServerClass that is not a concrete THttpServer descendant; rc 1 while serving. A second Initialize replaces the server |
| `RegisterRoute …` | proc | `AppRouter.RegisterRoute …`, rc passed through |
| `Run` | override proc | `Server.BeginServe`; `inherited Run "$@"` (TCustomApplication's `repeat DoRun until Terminated`); `Server.EndServe`. rc 0 · **rc 1** if the server recorded a transport fatal · rc 2 before Initialize |
| `DoRun` | override proc | one `Server.ServeOne`: rc 0/1 → rc 0; rc 2 → Terminate, rc 0 (Run reports it); `Server.Stopping` or MaxRequests reached → Terminate. **Never non-zero for an expected condition** — the inherited Run hands a non-zero DoRun to HandleException, which prints `Exception: …` |
| `Terminate [EXITCODE]` | override proc | `inherited Terminate "$@"` (Terminated, EXITCODE), then `Server.Terminate` |
| `Destroy` | destructor | frees the server and the router — **no `inherited`**: TCustomApplication has no destructor |

The option parser is TCustomApplication's FPC port: the **last** occurrence of
an option wins, the **short** name is looked up first (`-p 1 --port=2` → 1),
and a long option needs `=` (`--port 8080` has no value → rc 2). An option
beats a value assigned before Initialize. Everything else of
TCustomApplication is inherited as is (`Title`, `HasOption`, `GetOptionValue`,
`Terminated`, `OnException`, …).

---

## 3. The handler contract

All three handler kinds get **`$1` = the request instance, `$2` = the response
instance**; functions and `INST.METHOD` also get **`$3` = the route DATA** (a
route object reads `RouteData`).

* **Read the request with direct calls** — `$1.Method`, `$1.Content`,
  `$1.RouteParam id`, `$1.GetHeader host`, `$1.QueryField q`: the value in
  `RESULT`, nothing printed, no fork. Never read a plain `var` of another
  object directly: it **prints** and leaves `RESULT` stale (§1.1 of the plan);
  every field another object reads is a property for this reason.
* **Answer** with `$2.Code = 404`, `$2.Write TEXT`, `$2.SetCustomHeader N V`,
  `$2.ContentType = …`; the server sends. A non-zero return with nothing sent
  → 500 (`OnRequestError` first). `echo` goes to the server's console, not to
  the client (deviation b).
* **Declare every variable `local`** (C25): a handler runs inside the
  application's, server's and router's member frames, where every property of
  those objects is a nameref — a bare `Port=…`, `Title=…`, `Router=…` or
  `state=…` writes that object.
* **In a method override, pass the arguments on**: `inherited HandleRequest
  "$@"`, `inherited Initialize "$@"` — a bare `inherited` outside a
  constructor passes **none** (C8).
* **Register a method of the running instance as `"$__inst__.Method"`**. Since
  kklass R2_P8 `"$this.Method"` is the same string; before it, kklass rewrote
  the text `$this.NAME` of a member body into its call form (`App.call Method`),
  quoted or not, and the router refused that name (found in P3,
  `examples/demo_oop.sh`) — a `.ckk` cache compiled before R2_P8 still carries
  the rewritten text until it is rebuilt.
* A **stopping** route calls `App.Terminate` (or `$srv.Terminate`); the
  response is still sent.

### What a descendant implements (PLAN §2.11)

| base | must implement | may override | lifetime |
|---|---|---|---|
| `THttpRouteObject` | `HandleRequest` (refused at registration if missing, D8) | `Create`, `Destroy` | one instance **per request**; state via `RouteData` or a controller |
| any class (a *controller*: its methods registered as `INST.METHOD`) | nothing | — | as long as the caller keeps it: **this is where state lives** |
| `THttpApplication` | in practice `Initialize` (`inherited Initialize "$@"` first, then routes and the app's own objects) | `Destroy` (free them, then `inherited`), rarely `DoRun`; set `ServerClass` (D9) | the application's run |
| `THttpServer` | nothing | `HandleRequest` — cross-cutting logic; `inherited HandleRequest "$@"` routes, omitting it short-circuits; may call `protected` `_log` | the server's run |
| `TNetcatTransport` / `THttpTransport` | another one-connection listener on the same mechanism: `BuildArgv` and `_state` (declared **public**, as `TSocatTransport` does — a private/protected override called from the base's `Accept` / `Shutdown` prints a kklass visibility warning); another backend: `Accept`, `CloseConnection`, `Shutdown` (setting the `protected` fields) | — | not application logic |

A minimal application needs no subclass at all (§0).
[`examples/demo_oop.sh`](examples/demo_oop.sh) uses every row: `TMyApp :
THttpApplication` (Initialize/Destroy overridden, its own methods Home / Count
/ Quit as routes), `TKvController` (a controller owning a `TDictionary`),
`THelloRoute : THttpRouteObject`, and `TAuthServer : THttpServer`
(`HandleRequest` checks a bearer token, then `inherited HandleRequest "$@"`),
plugged in with `ServerClass = TAuthServer`.

---

## 4. The examples

| | `examples/demo.sh` | `examples/demo_oop.sh` |
|---|---|---|
| style | functions + `App.RegisterRoute` (PLAN §2.10) | descendants (PLAN §2.11) |
| `GET /` | a function | `TMyApp.Home` (INST.METHOD) — public |
| `GET /count` | `Hits.Next` — a `TCounter` instance's method | `TMyApp.Count` |
| `GET PUT DELETE /kv/KEY` | functions on a `TDictionary` (201 new / 200 replaced / 404) | a `TKvController`'s methods |
| `GET /hello/NAME` | `THelloRoute` (a route class, DATA `Hello`) | the same |
| `POST /quit` | `App.Terminate` | `TMyApp.Quit` |
| auth | none | `TAuthServer`: `Authorization: Bearer T` for all but `/`; `--token=T` or `$DEMO_TOKEN` |

Both leave the backend to the server (*Network backend*: GNU netcat — `$KCL_NC`,
else `nc` on PATH — else socat); their only addition is the Windows fallback
`KCL_NC=/c/bin/msys64/usr/bin/nc.exe` when no nc is on PATH and that file
exists (Git-bash). They print their URL, log each request, answer a
bad `--port` with a usage line and exit 2, and report a transport fatal (e.g.
no backend) with `kcl demo: the server stopped: …` and exit 1. `tests/009_Demo.sh`
runs both exactly this way.

---

## 5. Route patterns

Constant segments compare literally and case-sensitively; `:name` takes one
**non-empty** segment; a trailing `*name` takes the rest (the `/` included,
possibly empty); a bare `:` / `*` capture nothing. The leading `/` is
optional, a trailing `/` is significant; a `*` anywhere but at the start of the
last segment is rc 2. Matching runs on the **raw** PathInfo (an encoded `%2F`
never splits a segment); each captured value is then percent-decoded with path
rules (`+` stays `+`, `%G1` literal, a backslash is data), and `%00` in a
captured value is answered 400 without running the handler. The table is parsed
and run by `tests/003_Router.sh` §1:

| pattern | path | match | params |
|---|---|---|---|
| `/` | `/` | yes | – |
| `/` | `/a` | no | – |
| `/hello` | `/hello` | yes | – |
| `hello` | `/hello` | yes | – |
| `/hello` | `/Hello` | no | – |
| `/Hello` | `/hello` | no | – |
| `/hello` | `/hello/` | no | – |
| `/hello/` | `/hello/` | yes | – |
| `/hello/` | `/hello` | no | – |
| `/a/b` | `/a/b/c` | no | – |
| `/a/b/c` | `/a/b` | no | – |
| `/a/b` | `/a/bc` | no | – |
| `/users/:id` | `/users/42` | yes | id=42 |
| `users/:id` | `/users/42` | yes | id=42 |
| `/users/:id` | `/users/` | no | – |
| `/users/:id` | `/users` | no | – |
| `/users/:id` | `/users/42/x` | no | – |
| `/users/:id/posts/:pid` | `/users/7/posts/9` | yes | id=7 pid=9 |
| `/:a/:b` | `/x/y` | yes | a=x b=y |
| `/u/:` | `/u/anything` | yes | – |
| `/files/*path` | `/files/a/b/c.txt` | yes | path=a/b/c.txt |
| `/files/*path` | `/files/` | yes | path= |
| `/files/*path` | `/files` | no | – |
| `/files/*path` | `/filesx/a` | no | – |
| `/files/*path` | `/Files/a` | no | – |
| `/*all` | `/` | yes | all= |
| `/*all` | `/x/y/` | yes | all=x/y/ |
| `/*` | `/any/thing` | yes | – |
| `/u/:id/*rest` | `/u/5/a/b` | yes | id=5 rest=a/b |
| `/u/:id/*rest` | `/u/5` | no | – |
| `/a%20b` | `/a%20b` | yes | – |
| `/a b` | `/a%20b` | no | – |
| `/v/:x` | `/v/%24%28id%29` | yes | x=`$(id)` |
| `/v/:x` | `/v/a%2Fb` | yes | x=a/b |
| `/v/:x` | `/v/a+b%2B%41%G1%4` | yes | x=`a+b+A%G1%4` |
| `/files/*path` | `/files/a%2Fb/c%2F` | yes | path=a/b/c/ |
| `/v/:x` | ``/v/$(:>pwn)`` | yes | x=``$(:>pwn)`` — data, never run |
| `/v/:x` | ``/v/`:>pwn` `` | yes | x=``` `:>pwn` ``` — data |
| `/v/:x` | `/v/${IFS}a[0]` | yes | x=`${IFS}a[0]` — data |
| `/v/*r` | `/v/;:>pwn;/&&/*` | yes | r=`;:>pwn;/&&/*` — data |

**Which route wins.** Registration order among the routes whose pattern
matches; the METHOD must be the request's or `ALL`. **HEAD** takes a HEAD
route, else the GET route of the same pattern (the body is dropped). No pattern
matches → the **default route** of the method (HEAD: HEAD, then GET), else the
`ALL` default, its pattern ignored; none → **404**. A pattern matches but no
method → **405** + `Allow:` (registration order, HEAD right after GET) — a 405
wins over the defaults. A default route also matches its own pattern as an
ordinary route.

---

## 6. The transport, in short

Per slot: a FIFO feeding the listener's stdin, a process-substitution fd
reading its stdout, a `-vv` stderr file and a pid, under one `mktemp -d`
(created at the first Accept, removed by Shutdown). The mechanism was measured
before it was written (PLAN §1.1, the critic's C1–C4) and re-proved inside a
kklass class in P2:

```bash
# _spawn SLOT   (o = the other slot)
exec {rd}< <( [[ -n $wrO ]] && exec {wrO}>&- {rdO}<&-    # never inherit the live connection (C4)
              export LC_ALL=C                              # nc's -vv lines are classified by text
              exec nc -l -c -vv -n -w TTL -s ADDR -p PORT < <(exec cat "$dir/fifo$s") 2>"$dir/err$s" )
pid=$!
exec {wr}>"$dir/fifo$s"      # O_WRONLY: an O_RDWR writer never lets nc see EOF (C1)
```

* **Accept** reads the request line in ≤ 1 s ticks (partial input kept); the
  moment it arrives, the **other** slot's listener is spawned (D5), so a second
  client can connect while the first request is handled. The consumed line is
  `FirstLine` with `LineConsumed` 1 — an EMPTY line too, which the parser then
  answers 400 (review F5). An idle tick (rc 1)
  leaves the listener alive — no port gap. A connected but silent client is
  answered **408** after `RequestTimeout`. `Connection from` → the address;
  `Listen mode failed: Connection timed out` (the TTL) → respawn; **any other
  stderr line is fatal** (rc 2, `LastError` = that line) — a bind failure or a
  missing nc never becomes a respawn loop. `TSocatTransport` reads socat's
  lines instead (*Network backend*); the rest is the same code.
* **CloseConnection is a drained close** (C2): close the writer → read the
  reader to EOF (nc flushed, closed and exited) within `CloseTimeout` → close →
  kill **only** past the deadline → reap. Killing first truncated 5 of 5
  responses in the planning probes.
* **Shutdown** drains a slot that has *accepted* a client (review R1: killing
  it reset the client) and kills a slot that only listens; then removes the
  FIFOs and the dir.
* **Signals** (§2.6 as implemented): BeginServe traps INT/TERM with a bare
  assignment to a file-scope flag; the serving loop, ServeOne and Accept (every
  tick) look at it at safe points. A signal lets the current response finish,
  closes a connection waiting in the pre-spawned listener without a response,
  and Serve / Run return 0. A trapped signal does not cut `read -t` short
  (measured), so the reaction time is one tick.

---

## 7. Contract, deviations, limits

kcl README §1 in full (P0–P3 of its own roadmap, complete), with **five named
deviations** (PLAN §2.1):

* **(a) `Active = true`, `Serve` and `App.Run` block** until the server stops
  (FPC's `Active := True` does too).
* **(b) A handler's stdout goes to the server's stdout, not to the client** —
  the client gets what the handler put into the response (`$2.Write`,
  `$2.Content`).
* **(c) One request at a time, no keep-alive** — every response is
  `Connection: close`. One further client can wait in the pre-spawned listener.
* **(d) A server that is KILLed** leaves its temp dir, and its listeners until
  their `ListenerTTL` (60 s) expires: the unit may not install an EXIT trap
  (C26). TERM and INT are handled cleanly.
* **(e) A write to a read-only property** (`$req.Method = X`, `S.Stopping = 1`)
  is rc 1 and prints kklass's own `Error: Property 'X' is read-only`
  unconditionally.

What a user can observe of the accepted P0–P2 interpretations (all in the
ledger with their reasons): `ReadFrom` answers a parser status as **rc 0 + a
value** (C20); `Content-Length` must be plain digits, the same value twice is
kept once; any control character other than HTAB in a header value is 400; a
request whose REQUEST LINE failed leaves every field empty, a later-stage
status keeps Method/URI/ProtocolVersion (amended by review F4); `Attach` takes a
third argument (the banner); a failed validation sends a **500 with the default
head** and updates Code/CodeText/ContentType to what was sent; `ContentSent` is
1 after any write attempt; `SendRedirect` only *sets*; `Write` joins with one
space and adds no newline; a code with no reason is sent as `HTTP/1.1 299 ` (SP
kept); query **names** are decoded too, `?g` is `g=''`; `HasHeader ''` is rc 2;
route parameters are percent-decoded (review R1); a default route also matches
its own pattern, a 405 wins over the defaults, HEAD falls back to the GET
default; `RouteRequest` runs `AfterRequest` always, skips the handler after a
failed or *sending* `BeforeRequest`, and treats 404/405 as rc 0; a
`HandleRequest` redeclared **without** `override` still counts as implemented
(a kklass fact — D8 catches only a missing one); `MaxRequests` is a property;
`RequestCount` counts every ANSWERED connection (408 included, `gone` not —
amended by review F3) and is reset by BeginServe; a `gone` connection is
neither answered, logged nor counted, so it never uses up `MaxRequests`;
`OnRequestError` sees the original response before it is replaced by a fresh
500; BeginServe validates its numbers (rc 2, nothing changed). P3 added the
read-only `Stopping` property, moved the `OnAcceptIdle` event from Serve's loop
into `ServeOne` (so it fires under `App.Run` too), and made the application's
`Port`/`Address` read/write properties (the demo prints its URL from them).

**Limits.**

* **Serial.** One request at a time in the server shell. A **burst** of
  clients is not absorbed: GNU nc (and socat, which also closes its listener
  after the accept; its burst numbers are unmeasured) closes its listening
  socket after its one accept, which **resets** the connections queued in its
  backlog — 8
  simultaneous clients get 5–7 answers, 1–3 resets and up to 2 refusals per
  burst (§11). The reset requests never reached a handler, so an idempotent
  request may be retried on curl rc 55/56 (a refusal, rc 7, on anything); the
  tests do exactly that and prove each was handled once.
* **No keep-alive, no TLS, no chunked bodies, no multipart, no cookies, no
  `Expect: 100-continue`** (curl sends it only above 1 MiB, far past the 64 KiB
  limit → 413). `Transfer-Encoding` → 501.
* **Text only.** A bash variable cannot hold NUL: a request body with a NUL is
  400, responses are written from a variable, no file streaming (D3: no static
  files).
* **Bodies are read a byte per syscall over a pipe**: a 64 KiB body takes ≈ 1.2
  s (≈ 80 ms from a file) — `MaxContentLength` 65536 is the sane ceiling.
* **~10 requests/s** sequentially (§11): per request one listener spawn (a
  fork, the `cat` relay and nc: ≈ 36–38 ms) and a drained close.
* A background process a handler starts inherits the current connection's
  writer and holds the connection open until `CloseTimeout`.

**Post-completion review (2026-09-30).** Six findings, fixed red-first (PLAN
§8, the ledger's `review_2026_09_30`):

* **F1** — a route object whose `HandleRequest` routes through another router
  (where a route class wins too) no longer deletes the outer, live object: each
  nesting level has its own instance name (`__ths_route_obj`, `…1`, `…2`).
  Before, the outer pass aborted the whole top-level command.
* **F2** — a second `Host` header is a 400 (RFC 9112 §3.2), identical values
  and any case included.
* **F3** — a `gone` connection does not count in `RequestCount`, so gone
  probes cannot use up `MaxRequests` and stop a server that served nothing.
* **F4** — once the request line parsed, `Method`/`URI`/`ProtocolVersion` stay
  set after a later-stage status; the server takes the HEAD flag from
  `REQ.Method` (the transport's `FirstLine` prefix only as a fallback), so a
  failed HEAD is answered without a body on every transport.
* **F5** — `ReadFrom … CONSUMED` and `THttpTransport.LineConsumed` tell "the
  transport consumed an empty line" from "it consumed nothing": a bare LF
  before the request line is a 400 on the wire, as in the direct parse.
* **F6** — `TNetcatTransport`'s per-slot selection (`_rd0`/`_rd1`, …) is
  one `local -n` per field instead of fifteen copied `if` blocks (no
  behaviour change).

---

## 8. What the unit demonstrates about kklass (PLAN §2.9)

| kklass feature | where |
|---|---|
| inheritance, multi-level | `TSocatTransport : TNetcatTransport : THttpTransport`; `THttpApplication : TCustomApplication`; `TAuthServer : THttpServer`, `TMyApp : THttpApplication` (demo_oop) |
| `abstract` | `THttpTransport`, `THttpRouteObject`; D8 refuses a still-abstract route class by `kk.isAbstract` (the flag `.new` checks) |
| `override` + `inherited` with arguments | `THttpApplication.Initialize/Run/Terminate`; `TAuthServer.HandleRequest` → `inherited HandleRequest "$@"`; `TSocatTransport` overrides `BuildArgv` and `_state`, which the inherited `Accept` / `Shutdown` call (a public override: no visibility warning) |
| virtual dispatch via `$this` (template method) | `ServeOne` calls `$inst.HandleRequest`; TCustomApplication's `Run` calls `$this.DoRun` — the overrides win |
| read-only property over a private field | every `THttpRequest` field, the transport's state, `RequestCount`, `LastError`, `Stopping`, `Server`, `AppRouter` |
| read/write property | `THttpResponse.Code/CodeText/ContentType/Content`, `MaxRequests`, the application's `Port`/`Address` |
| property with a setter that acts | `THttpServer.Active` (`= true` starts serving) |
| constructor/destructor, owned objects | the server owns its transport and stopwatch; the app owns server + router; a request/response pair and a route object per request; destructor chains through empty base destructors |
| `private` / `protected` | private fields everywhere; `protected` `_handleConnection` / `_log` for descendant servers, `protected` transport fields for descendant transports |
| events as properties | `OnRequest`, `OnRequestError`, `OnAcceptIdle`, `OnLog`, `BeforeRequest`, `AfterRequest` |
| factory by class name | `RegisterRoute /hello/:name GET THelloRoute`; `ServerClass` (D9) |
| substitutability | `TReplayTransport` drives the same server with no sockets |
| composition with kcl | `TCustomApplication` (the loop, the options), `TDictionary` (the demo's store), `TStopwatch` (the access log's ms) |
| state that outlives a request | the demos' counter and key-value store |

---

## 9. Environment

* **network backend** (*Network backend*): GNU netcat 0.7.1, else socat
  (>= 1.7.4), **identified, not assumed**; any other nc is refused with `no
  usable network backend: …`. On Linux the distro's nc is usually OpenBSD
  netcat, Ncat or nc.traditional — install `socat`. `KCL_NC` / `NcBinary`
  force a netcat, `KCL_SOCAT` / `SocatBinary` a socat (precedence: an explicit
  netcat, then an explicit socat, then PATH). Under bash 5.3.9 (msys64) `nc`
  is on PATH. Under bash 5.2.37 (Git for Windows) it is **not** — point
  `KCL_NC` (or `NcBinary`) at `/c/bin/msys64/usr/bin/nc.exe`; the examples and
  the tests do that fallback themselves. A Git-runtime FIFO cannot be msys64
  nc's stdin (`select(core_readwrite): Bad file descriptor` on accept): the
  `cat` relay (`StdinRelay = 1`, the default) is what makes it work.
* **Proxy**: `HTTP_PROXY`/`HTTPS_PROXY` are exported on this machine — use
  `curl --noproxy '*'`; the tests unset every proxy variable.
* **Firewall**: listeners bind `127.0.0.1` by default and raised no prompt.
  `--address=0.0.0.0` exposes the server (the plain demo's store has no
  authentication) and may raise a Windows firewall prompt; the demos warn on a
  non-loopback address. The tests never bind anything but loopback.
* A child bash that sources the unit cold takes ≈ 3.5 s idle, ≈ 12 s under
  load — relevant to anything that starts a server under `timeout`.

---

## 10. Tests

```bash
bash kcl/thttpserver/tests/tests.sh                 # the whole suite (threaded)
bash kcl/thttpserver/tests/tests.sh --mode single   # sequential
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/thttpserver/tests/tests.sh
```

**533 checks, green on bash 5.2.37 and bash 5.3.9**, threaded (twice each) and
under `--mode single` (5.2.37), the socket files run on both (GNU netcat); in
the Linux lab VMs they run on socat (L2.7-N2). Case by case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| file | checks | what | transport |
|---|---|---|---|
| `001_Request.sh` | 63 | the parser: every field, headers, byte semantics, 53 raw requests → every status, 408 paths, query decoding, hostile keys, read-only fields, the transport seam, the fork-free proof; review 2026-09-30: a second Host, the fields after a later-stage status, CONSUMED, LineConsumed | replay |
| `002_Response.sh` | 42 | the head, byte lengths, HEAD/1xx/204/304, custom headers and refusals, validation → 500, SendRedirect, Date in English/UTC, SIGPIPE | replay |
| `003_Router.sh` | 137 | the 40-row pattern table, the argument rule, the three handler kinds, D7 DATA, D8, 404/405 + Allow, HEAD → GET, defaults, hooks, the handler contract, fork-free routing, param decoding, nested route-object dispatch (review F1), the router refusing a request whose parse ended in a status | replay |
| `004_Server.sh` | 50 | the server over replay (codes, 500, HEAD, precedence, Active, MaxRequests, a `gone` connection not counted, a failed HEAD without a body, a consumed empty line, traps, TERM, a descendant server); real sockets: state in the server shell, bytes, 50 kB bodies, 408, D5, 8 parallel clients, busy port, no nc | replay + netcat/socat |
| `005_Lifecycle.sh` | 17 | what a Serve leaves (fds, traps, children, temp dir, instances), port release, TERM with a held connection, TERM while idle, the listening-only Shutdown | netcat/socat |
| `006_Application.sh` | 40 | options, ServerClass, routes before Initialize, the DoRun mapping, OnAcceptIdle under Run, Stopping, Terminate, TERM and SIGPIPE on the app path, fact 22, Destroy, fork-free DoRun; sockets: `--port=N`, `/quit`, fact 10, TAuthServer 401/200, TERM | replay + netcat/socat |
| `007_Hostile.sh` | 23 | response splitting at every field, hostile params/headers/queries, every parser status over `/dev/tcp`, slowloris, oversize, two `Host` headers and a leading bare LF on the wire | replay + netcat/socat |
| `008_Contract.sh` | 143 | source integrity, the scope of every file, the transport's mechanism, C8/C9/C11, `set -eu` children, one debug line per rc 1/2 path, fork-free ServeOne; the backend detection (L2.7-N1/N2: every precedence rule and WHY), TSocatTransport's argv and `_state` on recorded socat lines, the mechanism over a fake socat, the server factory | replay + fake nc/socat |
| `009_Demo.sh` | 14 | both examples as a user runs them: every route kind, the store, HEAD/404/405, the token, `/quit`, the refused command line, no nc | netcat/socat |
| `010_Bench.sh` | 4 | the loose relative gate on the replay path (§11) | replay |

**The socket rules** (PLAN §4): the server is a child bash under `timeout 180`
with its output in files; it ends on its own through MaxRequests or an
idle-tick budget (`OnAcceptIdle`); ports are random with a retry on a bind
failure; clients retry only on curl rc 7 (and on 55/56 in the one idempotent
burst case); ordering is by marker files, never by sleeps; signals are TERM.
Red-first counts per phase are in the ledger.

---

## 11. Performance

`bash kcl/thttpserver/bench.sh [NR] [NS] [ROUNDS]` — the socket phases (b)–(d)
are **GNU-netcat only by design** (their spawn replica and listener events
are GNU's): with socat, or no backend, the bench prints the replay rows and
skips (b)–(d) loudly. Measured **2026-09-29** on
Windows 11 / MSYS2, NR = 7 interleaved samples, NS = 20 sequential requests per
sample (5 samples per client, interleaved), ROUNDS = 5; medians:

| measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| request object + parse (`new` + `ReadFrom` of a 4-header GET + `delete`) | 5.16 ms | 4.77 ms |
| route to a function (`RouteRequest`, parsed request) | 4.32 ms | 4.56 ms |
| route to a route class (`new` + `HandleRequest` + `delete`) | 4.78 ms | 4.86 ms |
| response (`new` + `Attach` + `Write` + `SendContent` + `delete`) | 3.46 ms | 3.45 ms |
| **`ServeOne` over `TReplayTransport`** — all of it, no fork | **28.1 ms** | **26.5 ms** |
| `THttpApplication.DoRun` (one ServeOne + the app's checks) | 31.0 ms | 29.6 ms |
| **socket, sequential, `/dev/tcp` client** (no client process) | **107.4 ms — 9 req/s** | **94.7 ms — 10 req/s** |
| socket, sequential, `curl` (a process per request) | 139.0 ms — 7 req/s | 106.5 ms — 9 req/s |
| listener spawn, synchronous part (fork + `cat` relay + writer open) | 36.2 ms | 35.6 ms |
| … until nc reports `Listening on` | 51.0 ms | 42.0 ms |
| handling inside the server (the access log's MS) | 24 ms | 23 ms |
| drained close (`CloseConnection`) | 14.5 ms | 8.1 ms |
| 8 simultaneous clients, no retry, 5 bursts | 28 × 200, 10 resets, 2 refused (of 40) | 31 × 200, 9 resets (of 40) |

Reading the table:

* **Where a socket request goes** (≈ 95–107 ms): the synchronous pre-spawn of
  the next listener (≈ 36 ms, inside Accept), the handling (≈ 23 ms: two
  objects, the parse, the route, the send, the log), the drained close (≈ 8–15
  ms), and the rest in nc itself — accepting, relaying the request line,
  flushing — and the kernel. The fork-free share (the replay rows) is under a
  third of it; **the fork is the cost**, as PLAN §2.8 predicted (≈ 100 ms per
  request in the planning probe).
* **curl vs `/dev/tcp`**: the difference is the client's own process start
  (≈ 10–35 ms); the `/dev/tcp` column is the server's throughput.
* **The replay path is the one that is gated** (`tests/010_Bench.sh`, relative
  to a baseline measured in the same shell: ServeOne ≤ 15× the request-object
  cost — idle 5.5×; DoRun ≤ 2× ServeOne — idle 1.1×; no growth over 60
  requests). Socket numbers are reported, never asserted.
* **Bursts**: the resets are GNU nc closing its listening socket after its one
  accept, which resets the connections queued in its backlog; they never
  reached a handler (the access log counts exactly the 200s: 28 and 31). The
  pre-spawn lets one further client wait; it cannot absorb a burst. The
  planning baseline with a single listener was 6 of 8.
* The planning probe's per-request object cost (≈ 2.7 ms for `new` + property
  sets + `delete` of the request/response pair) is inside the handling row; the
  P2 costs (Accept with the line waiting 42–52 ms, close 9–44 ms, Shutdown
  33–67 ms) are in the ledger's `measured_p2`.
