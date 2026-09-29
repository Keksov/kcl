# thttpserver — test coverage notes

**Status: FINALIZED at P3 (2026-09-29).** Suite `001`–`010` = **472 cases**,
green on bash 5.2.37 and on bash 5.3.9, threaded and (5.2.37) under `--mode
single`, with the socket files **run** on both (5.2.37 through
`KCL_NC=/c/bin/msys64/usr/bin/nc.exe`, which the tests export themselves; 5.3.9
with `nc` on PATH). The per-section counts below sum to 472 — 53 + 42 + 131 +
45 + 17 + 40 + 21 + 105 + 14 + 4.

**Protocol.** There is no FPC upstream to diff against (D1): the oracle is the
wire. Every request in the replay files is a **real** raw request that goes
through `TReplayTransport` and `THttpRequest.ReadFrom`, and every response is
read back from its capture file; the socket files start the server as a
**child bash** under `timeout 180` (output in files, never the runner's
stdout), and the test is the client — `curl --noproxy '*' -m 30`, or a raw
bash `/dev/tcp` client for requests curl will not send. The child ends on its
own (MaxRequests, `/quit`, or an idle-tick budget through `OnAcceptIdle`);
ports are random with a retry on a bind failure; ordering is by marker files;
signals are TERM (INT is ignored in a `&` child). Checks that only the server
shell can make — traps, `/proc/$BASHPID/fd`, children through
`/proc/*/ppid`, leftover instances and temp dirs — are made by the child and
written to its result file. Hostile input always runs in the fixture dir, so a
`$(:>pwn)` that ever executed would leave `pwn` where the tests look.

**Red first.** Every phase ran its new tests against a stubbed skeleton first
(every member body `: __THS_PENDING__; return 1`); the counts are in the
ledger's `red_before` per phase. P3: `006` 40/40 FAIL, `008` 12/105 FAIL (the
93 passing: the P0–P2 contract plus the P3 checks a skeleton with the real
declarations legitimately meets — `bash -n`, the file scope, the examples'
text), `009` 12/14 FAIL (the two passing: a bad `--port` is refused with the
usage line — the stub refuses everything; the `KCL_NC=/no/such/nc` cases were
added to tell a refusal from a working Initialize), `010` 4/4 FAIL (after the
gates were made to require that their timed requests were real — a bare
ceiling passed on the stub).

Basis: **F1–F23** = PLAN §3 pinned facts; **C1–C26** = the critic pass (PLAN
§8); **D1–D9** = owner decisions (PLAN §2.0); **R1** = a review remark in the
ledger.

---

## 1. Cases per file and section

| file · section | cases | basis |
|---|---|---|
| **001_Request** | **53** | |
| 1 a good request: every field, headers, FIRSTLINE/REMOTE, bare LF, repeated Content-Length, reset between parses, malformed calls | 12 | C20 |
| 2 byte semantics of the body (`aжb` = 4, 3-byte characters split by bytes, MAXBODY exactly) | 3 | F2 |
| 3 every parser status from 53 raw files; 413 not read; 408 without a read (spent deadline, with FIRSTLINE); four open-pipe 408s; NUL → 400 at once | 11 | F12, C18, C19 |
| 4 query fields: first occurrence, `+`, `%XX`, backslashes as data, `%00`, empty keys, hostile names/values/headers/route params, no `pwn` | 9 | F13, C12 |
| 5 read-only fields from a handler-like member: silent reads, writes rc 1, kklass's own line only | 3 | F19, D6, (e) |
| 6 the transport seam: abstract base, TReplayTransport's Accept/Close/ResponseFile/Shutdown, fd counts, delete | 11 | §2.5 |
| 7 fork-free replay pipeline: BASHPID, `PATH=''`, stored bodies, DEBUG canary with a control | 4 | F23, C21 |
| **002_Response** | **42** | |
| 1 head format, byte-exact `Content-Length`, one write, body as data, reasons, ContentType `''`, banner | 9 | F2 |
| 2 HEAD, 1xx, 204, 304 | 3 | F16 |
| 3 custom headers: order, GetCustomHeader, refusals (non-token, CR/LF, server-owned), hostile values | 4 | F14 |
| 4 validation at send → 500 with the default head (10 cases), one debug line | 12 | F14, C14 |
| 5 SendContent twice / before Attach, Attach refusals, Write, SendRedirect (302/301/307/308, refusals), delete | 8 | |
| 6 properties from a handler-like member | 2 | F19 |
| 7 Date English + UTC under `ru_RU` / `JST-9` (and the non-vacuous check) | 2 | F15, C15 |
| 8 SIGPIPE deterministic: rc 1, silent, alive; without `trap '' PIPE` rc 141 | 2 | F3, C16 |
| **003_Router** | **131** | |
| 1 the pattern table parsed from the file's own comment block (40 rows + the parse check) | 41 | F17 |
| 2 RegisterRoute's argument rule, METHOD/ISDEFAULT/handler-name refusals, `*` placement, DATA, RouteCount read-only, storage arrays, Destroy | 13 | D7, C10 |
| 3 the three handler kinds; property wrappers refused; vanished handlers; the route object's lifecycle; D8 (nothing printed, no constructor); `override`-less implementation accepted; destructor chaining | 15 | F17, F21, D8, C9, C17 |
| 4 order, 404, 405 + Allow, HEAD → GET (router and wire), FindRoute | 15 | F16, F17, C13 |
| 5 default routes | 8 | F17 |
| 6 Before → handler → After; rc rules; a sending BeforeRequest; malformed calls | 8 | |
| 7 the handler contract: DATA verbatim ×13 values, silent reads, `local` vs a bare assignment, no `pwn` | 5 | F20, C25 |
| 8 fork-free routing (four-part proof) | 4 | C21 |
| 9 route params percent-decoded with path rules; `%2F`, `%00` → 400, route object | 22 | R1 |
| **004_Server** | **45** | |
| 0 over replay: ServeOne codes and captures, OnLog format, 500 + OnRequestError, a handler that sent, HEAD, parser statuses, `gone`, precedence, Serve/Active/MaxRequests/Terminate, traps, TERM from a handler, a descendant server (`inherited HandleRequest "$@"`, protected `_log`), the owned transport, BeginServe refusals, delete | 23 | F22 (server half), C11 |
| 1 real sockets: idle ticks with the same listener, state in the server shell, bytes both ways, HEAD/405, 404/500, hostile data on the wire, 50 kB ×5 and to EOF, a client that leaves, 408, D5 (client 2 in the pre-spawned listener), 8 parallel clients handled exactly once, the access log, Terminate from OnAcceptIdle | 17 | F1–F3, F6–F9, F13, F16, D5 |
| 2 busy port → rc 1, the bind line, nothing left | 1 | F4 |
| 3 no usable nc (missing, not on PATH, bad interpreter, an nc that exits) → rc 1 at once, spawned once | 4 | F5, C6 |
| **005_Lifecycle** | **17** | |
| 1 a clean Serve twice on the same port: traps, fds, children, temp dir, instances, delete | 7 | F10 (server path) |
| 2 TERM while the pre-spawned listener holds client 2 | 7 | F11, R1 |
| 3 TERM while idle, `AcceptIdleTimeout 0` | 2 | |
| 4 Shutdown of a listening-only slot is not drained | 1 | R1 |
| **006_Application** | **40** | |
| 0 defaults (silent property reads); routes before Initialize; wiring; option table (6 shapes, FPC last-wins and short-first, option > preset); 7 refusals, silent + one debug line; ServerClass refusals (7, abstract without a constructor run, hostile names never executed) and a descendant; a second Initialize | 10 | F18, D9, C24 |
| 1 App.Run over replay: MaxRequests, `/quit` via App.Terminate, the fatal path (rc 1, HandleException never reached), the handler contract through the app, OnAcceptIdle under Run and under the plain server (no double firing), Stopping, the Terminate override, fact 22 via ServerClass (both halves), fact 10 (replay half), Run/DoRun before Initialize, a BeginServe refusal and Initialize while serving, Destroy, a descendant app with Initialize/Destroy overrides, TERM and SIGPIPE on the app path (child bashes), fork-free DoRun | 18 | F10, F18, F22, C8, C9, C11 |
| 2 sockets: `--port=N` serves on N, state and pid, a client that leaves, `/quit` → exit 0, fact 10 (app path) incl. traps and fds, port free + nothing left; `-p N` + TAuthServer 401/200 and `inherited` over the wire; TERM during a request; TERM idle with no ticks | 12 | F10, F18, F22 |
| **007_Hostile** | **21** | |
| 1 over replay: response splitting refused at every field, hostile params/headers/queries | 9 | F13, F14, C14 |
| 2 over sockets: every parser status on the wire, NUL body, slowloris 408, `gone`, header injection, hostile data, the server survives | 12 | F8, F12, F13 |
| **008_Contract** | **105** | |
| 0 source integrity: `bash -n` ×6 (the four unit files and both examples), dangling quote, no inline CR, no `$this.` in the unit, sentinel gone, Date idiom, constants, destructors, one write, the file scopes (server, application, router), the transport's mechanism, the drained close, traps/EXIT, P3: C8/C9/C11 in the application, `Stopping` + the idle event's place, the examples' text | 24 | C1–C4, C8, C9, C11, C15, C16 |
| 1 `set -eu` children: loading ×2, the replay pipeline, statuses, misses, the router, the server, the netcat transport's refusals, the application | 10 | §2.1 |
| 2 one kk.debug line on every rc 1 / rc 2 path, silence otherwise (67 members/paths, 9 of them the application's) | 67 | kcl §1.2 |
| 3 ServeOne fork-free (four-part proof) | 4 | C21 |
| **009_Demo** | **14** | |
| 0 per example: a bad `--port` → usage, exit 2; an unusable nc → the URL, `the server stopped: nc not found`, exit 1 | 4 | |
| 1 `demo.sh` (own nc resolution where the bash has none): URL, a function, INST.METHOD state, the TDictionary store (201/200/404, multibyte), a route class + HEAD, 405/404, `/quit` → exit 0, the summary, 14 log lines, clean | 7 | §2.10 |
| 2 `demo_oop.sh --token=T`: public index, 401 ×2, the app's and the controller's methods, the route class, `/quit` refused without the token and accepted with it | 3 | §2.11 |
| **010_Bench** | **4** | |
| A/B ServeOne ≤ 15× the request-object baseline; DoRun ≤ 2× ServeOne (interleaved medians; each gate requires its timed requests answered `200 … b1`) | 2 | §2.8, C22 |
| C no growth over 60 requests; D BASHPID unchanged and every timed request real | 2 | |

---

## 2. Member → assertions

| member | pinned by |
|---|---|
| `THttpRequest.ReadFrom` | 001 §1–§3 (every status, the check order, 408 paths, `gone`, NUL, 413 not read, FIRSTLINE/REMOTE, reset), §2 (bytes); 007 §2 (on the wire); 008 §1–§3 |
| `Method … RemoteAddress`, `ContentLength` | 001 §1, §2, §5 (silent reads, writes rc 1); 003 §7; 004 §1 (X-Len) |
| `GetHeader`, `HasHeader`, `HeaderNames` | 001 §1, §4; 008 §2 |
| `QueryField` | 001 §4; 004 §1 (wire); 007 §1–§2 |
| `RouteParam`, `SetRouteParam` | 001 §4; 003 §1, §4, §9; 006 §1 (through the app); 008 §2 |
| `THttpResponse` properties, `Write` | 002 §1, §5, §6; 003 §7 |
| `SetCustomHeader`, `GetCustomHeader` | 002 §3; 007 §1; 008 §2 |
| `SendContent`, `Attach` | 002 §1, §2, §4, §5, §8; 008 §0 (one write); 006 §1 (SIGPIPE on the app path) |
| `SendRedirect` | 002 §5; 007 §1 |
| `THttpRouteObject` | 003 §3 (abstract, lifecycle, D8, destructor chaining); 009 (THelloRoute) |
| `THttpRouter.RegisterRoute` | 003 §1–§3, §5; 006 §0 (through the app); 008 §1–§2 |
| `RouteRequest`, `FindRoute`, `RouteCount`, hooks | 003 §4–§8 |
| `THttpTransport` | 001 §6 (abstract, fresh state); 006 §1 (a test descendant `TIdleTransport`) |
| `TReplayTransport` | 001 §6; used by 001–004, 006–008, 010 |
| `TNetcatTransport.BuildArgv` | 008 §1–§2; 004 §3 |
| `Accept` (spawn, pre-spawn, ticks, 408, EOF classification) | 004 §1–§3; 005 §2; 007 §2; 006 §2 |
| `CloseConnection` (drained) | 004 §1 (50 kB ×5, EOF); 008 §0 (the order in the body) |
| `Shutdown` | 005 §1–§4 |
| `THttpServer.Serve`, `Active`, `BeginServe`, `EndServe`, `Terminate` | 004 §0–§1; 005; 008 §1–§2 |
| `ServeOne` | 004 §0; 006 §1 (the idle event); 008 §3; 010 |
| `HandleRequest` (virtual) | 004 §0 (precedence, a descendant); 006 §1–§2 (fact 22) |
| `OnRequest`, `OnRequestError`, `OnLog` | 004 §0–§1 |
| `OnAcceptIdle` | 004 §1 (fact 6, Terminate from it); 006 §1 (under App.Run; ServeOne alone; Serve without double firing) and every socket child's idle budget |
| `MaxRequests`, `RequestCount`, `LastError` | 004 §0–§2; 006 §1; 008 §1 |
| `Stopping` | 006 §1; 008 §0 |
| `_log`, `_handleConnection` (protected) | 004 §0 (a descendant calls `_log` without a warning) |
| `THttpApplication` Create / defaults / `Port` / `Address` / `Server` / `AppRouter` | 006 §0 |
| `Initialize` (options, ServerClass, wiring, re-Initialize, rc 1/2) | 006 §0–§2; 008 §1–§2 |
| `RegisterRoute` | 006 §0; 008 §2 |
| `Run` | 006 §1–§2; 008 §0 (the order), §1–§2 |
| `DoRun` | 006 §1 (every rc mapping, fork-free); 010 |
| `Terminate` | 006 §1; 008 §2 |
| `Destroy` | 006 §1 (and a descendant's chaining); 008 §0 (no `inherited`) |
| the examples | 009; 008 §0 |

---

## 3. Known, deliberate gaps

* **INT is not sent to a server.** A `&` child has INT ignored and cannot trap
  it; the tests signal with TERM, which goes through the same trap code
  (`__THS_SIGNAL=INT|TERM`). 004 §0 and 006 §1 check that TERM is the
  server's while serving and that INT/TERM/PIPE are restored exactly after;
  the INT trap line itself is not triggered by any case.
* **A KILLed server** (deviation d) is not tested: by definition it leaves its
  listeners until `ListenerTTL` and its temp dir; nothing in the unit can react.
* **The `ListenerTTL` expiry → respawn** and **both slots connected at
  Shutdown** were measured (P2 spike S6; `measured_p2.shutdown_held_connection`,
  24/25 then 20/20) but are not suite cases: a TTL test needs a ≥ 1 s idle
  listener with no client and a fixed wait, and the double-connected case
  depends on client timing the suite cannot order without sleeps.
* **`CloseTimeout` expiry** (the kill after the drain deadline) is not forced:
  it needs a client that keeps the connection open without reading; 005 §4 pins
  the other side (a listening-only slot is not drained).
* **`StdinRelay = 0`** (a same-runtime nc without the `cat` relay) is not run
  on the wire; the default relay is used on both bashes.
* **Bursts** are pinned as measured (fact 7): 8 parallel clients all get 200
  when the idempotent GET is retried on rc 55/56, and each is handled exactly
  once. The number of resets per burst is reported by `bench.sh`, not asserted.
* **Large request bodies over a socket**: the 64 KiB limit and the byte-exact
  body are pinned from files (001 §2) and with a 9-byte multibyte body on the
  wire (004 §1); the ≈ 1.2 s pipe cost of a 64 KiB body is a measurement
  (`measured_p0.pipe_body`), not a case.
* **Background processes started by a handler** inherit the connection's
  writer (documented fd hygiene); not tested.
* **Socket performance** is never asserted (timing lessons, C22) — only the
  fork-free replay path is gated (010).
* **`demo_oop.sh` with `$DEMO_TOKEN`**: the `--token=T` path is run by 009; the
  environment fallback is one line and is not.
* **`--address=0.0.0.0`** is never bound (firewall prompt; the tests stay on
  loopback); the non-loopback warning of the demos is not asserted.
* **Other netcat flavours** (OpenBSD, ncat, socat) are out of scope (D2);
  `BuildArgv` is the documented override point.
