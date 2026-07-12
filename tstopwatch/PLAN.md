# TStopwatch → bash port plan (kcl/tstopwatch)

**Roadmap position:** 1/7 (owner priority order, 2026-07-12: tstopwatch → tregex → tarray → tinifile → tqueuestack → thashset → fpjson).
**Source of truth:** Delphi `System.Diagnostics.TStopwatch` (record; **no FPC RTL equivalent** — the spec comes from the Delphi DocWiki API, same situation as tfile/tpath/tdirectory/tstringhelper which are also Delphi-spec units). Delphi's TStopwatch mirrors .NET `System.Diagnostics.Stopwatch`; where DocWiki is silent, .NET semantics are the tiebreaker.
**Target:** `kcl/tstopwatch/tstopwatch.sh` — kklass Pascal-DSL **instantiable** class `TStopwatch` (model: kcl/tlist family; multiple concurrent stopwatches must coexist).
**Ledger (single source of truth for status):** `kcl/tstopwatch/tstopwatch_ledger.json`.
**Workflow:** same as dateutils/math/tdictionary — implement per phase, dual-bash tests (5.2.37 + 5.3.9), full master sweep, STOP with a brief review, next phase on explicit "go". Commits gated. Never edit the unit while a master sweep is in flight (tdictionary P3 lesson).
**Conventions:** RESULT/rc mapping, error convention (rc=1 + stderr only under `VERBOSE_KKLASS=debug`), `$()`-capture caveat, `__prefix` locals in nameref methods, TEST_COVERAGE_NOTES protocol — all identical to `kcl/tdictionary/PLAN.md` §2.2–2.4/§6; not repeated here.

---

## 1. Scoping analysis

The whole unit is Tier A: pure bash, zero forks. The clock is the `EPOCHREALTIME` builtin
(microseconds since epoch, bash ≥ 5.0 — both target bashes qualify). There is no
allocator, no float, no OS handle: TStopwatch is a tiny state machine over integer
microsecond arithmetic, which is exactly what bash does well.

### Ported

| Delphi | bash | Notes |
|---|---|---|
| `TStopwatch.Create` (returns a **stopped** watch) | `TStopwatch.new sw` | fresh watch: elapsed 0, not running |
| `TStopwatch.StartNew` | `TStopwatch.new sw startnew` (ctor token) | created running (exact form pinned at P0) |
| `Start` | `sw.Start` | begins/**resumes**; no-op if already running |
| `Stop` | `sw.Stop` | pauses; elapsed **accumulates** across Start/Stop cycles; no-op if stopped |
| `Reset` | `sw.Reset` | stops + zeroes accumulated time |
| `Restart` | `sw.Restart` | Reset + Start as one atomic call |
| `IsRunning` | `sw.isRunning` (property) | 0/1 view of the running flag |
| `ElapsedTicks` | `sw.elapsedTicks` | ticks := microseconds (see §2.2) |
| `ElapsedMilliseconds` | `sw.elapsedMilliseconds` | integer **truncation**, not rounding (Delphi Int64 div) |
| `Frequency` (class prop) | `sw.frequency` | constant **1000000** (1 tick = 1 µs) |
| `IsHighResolution` (class prop) | `sw.isHighResolution` | constant true (µs builtin clock) |
| `GetTimeStamp` (class func) | `TStopwatch.getTimeStamp` (file-level helper) | raw current µs stamp; also the escape hatch for tight loops (§2.4) |

Bash-convenience extras (documented per TEST_COVERAGE_NOTES protocol):
`sw.elapsedMicroseconds` (the native unit — lossless), `sw.elapsedSeconds` (trunc).

### NOT ported (wontfix, with reasons)

1. **`Elapsed: TTimeSpan`** — kcl has no TTimeSpan type; numeric getters cover the use
   cases. If a ttimespan port ever lands, a getter can be added then.
2. **Record semantics** (value-type copies, `TStopwatch` as a stack value) — bash port is
   a kklass instance; copy-on-assign of records has no bash analog.
3. **QueryPerformanceCounter/monotonic-clock guarantees** — `EPOCHREALTIME` is wall-clock:
   NTP steps/manual clock changes CAN affect a running measurement. Documented honestly;
   bash offers no monotonic builtin.
4. **Thread affinity notes** from DocWiki — no threads in bash.

---

## 2. Design decisions

### 2.1 State model
Three per-instance fields (kklass `var`s): `_accum` (µs accumulated over completed
run segments), `_t0` (µs stamp when the current segment started; meaningful only while
running), `_running` (0/1). Reading elapsed while running = `_accum + (now - _t0)` —
**no side effects, no state writes on read**.

### 2.2 Ticks := microseconds, Frequency := 1e6
Delphi's ElapsedTicks/Frequency pair is meaningful only as a ratio. Defining 1 tick = 1 µs
makes `elapsedTicks` exact, `frequency` = 1000000, and every conversion integer. This is
the honest bash mapping (documented in README): we do NOT emulate the Windows 10 MHz QPC
frequency — code that divides ticks by frequency keeps working unchanged.

### 2.3 EPOCHREALTIME parsing
`EPOCHREALTIME` yields `seconds.micros` where the decimal separator is **locale-dependent**
(`.` or `,`). Pinned idiom (already proven in kcl bench scripts):
`local er=$EPOCHREALTIME; us=$(( ${er%[.,]*} * 1000000 + 10#${er##*[.,]} ))`.
The `10#` guard prevents octal surprises on `.0xxxxx` fractions. Read the variable ONCE
per timestamp (two reads = two different times).

**P0 probe confirmation (2026-07-12):** the comma is REAL on 5.2.37 (`LC_ALL=de_DE`/`ru_RU`
→ `1783855237,987393`); 5.3.9 always emits `.` (bash 5.3 formats EPOCHREALTIME
locale-independently). Fraction is 6 digits on both. The `[.,]` parse is therefore
required on 5.2 and harmless on 5.3.

### 2.4 Honest overhead positioning
A kklass method call costs ~0.5 ms on MSYS2 (tdictionary bench). A stopwatch whose query
costs 500 µs cannot time 50 µs intervals through its object API. The port documents this
up front: TStopwatch structures measurements of **multi-millisecond** work; for tight
loops use `TStopwatch.getTimeStamp` deltas (plain function, no dispatch) or raw
`EPOCHREALTIME`. bench.sh measures the self-overhead of every getter and the README
publishes the numbers. Delphi has the same disclaimer in miniature (method-call cost vs
QPC granularity) — ours is just bigger.

### 2.5 Start/Stop edge semantics (.NET-aligned, P0 pins final)
- `Start` while running → no-op (NOT a reset, NOT an error).
- `Stop` while stopped → no-op.
- `Reset` on a running watch → stops it AND zeroes.
- `Restart` always leaves the watch running with elapsed ≈ 0.
- Getters valid in every state; fresh watch reads 0.

---

## 3. Pinned semantics (verify/finalize at P0)

| # | Semantic | Source | bash consequence |
|---|---|---|---|
| S1 | Create yields a STOPPED watch, elapsed 0 | DocWiki TStopwatch.Create | `new` without token: `_running=0 _accum=0` |
| S2 | StartNew yields a RUNNING watch | DocWiki TStopwatch.StartNew | ctor token `startnew` |
| S3 | Elapsed accumulates across Start/Stop cycles | DocWiki Start ("resumes"), .NET | `_accum += now-_t0` on Stop |
| S4 | Start on running / Stop on stopped = no-op | .NET Stopwatch spec | guard on `_running` |
| S5 | Reset = stop + zero; Restart = zero + start | DocWiki Reset/Restart | Restart atomic (one method) |
| S6 | ElapsedMilliseconds truncates | Delphi Int64 division | `$(( us / 1000 ))` |
| S7 | Reads have no side effects, work while running | DocWiki Elapsed* | pure arithmetic in getters |
| S8 | GetTimeStamp = current raw stamp, monotone-nondecreasing between calls (modulo wall-clock steps) | DocWiki | `TStopwatch.getTimeStamp` plain function |

---

## 4. Parity & test model

No FPC test files exist (Delphi-only API). Test basis:
- **State-machine tests** (exact, timing-free): fresh=0/stopped; start→running; double-start
  no-op (state unchanged); stop→stopped; double-stop no-op; reset zeroes both states;
  restart running+~0; getters in every state; two instances independent.
- **Timing tests** (tolerance-based, generous windows to survive CI noise): busy segment
  → elapsed in [lower, WIDE upper]; accumulation over two segments ≈ sum; paused watch
  does not advance (exact: two reads while stopped are EQUAL — this one is timing-free
  and exact). Waits: **arithmetic busy-loop on the same EPOCHREALTIME clock** (P0 pin:
  lower bound guaranteed by construction, zero forks; 20 ms target achieved 20000/20003 µs
  on 5.2/5.3). `read -t` over a procsub rw-fd was probed and REJECTED — on MSYS2/Cygwin it
  returns on EOF, not timeout (14 ms for a 20 ms request on 5.3). `sleep` is out (external
  fork).
- **Zero-fork check**: full lifecycle under `PATH=''`.
- Dual-bash: full suite on 5.2.37 AND 5.3.9 (EPOCHREALTIME format probed on both).
- Every case is non-FPC by construction → each gets a TEST_COVERAGE_NOTES.md row
  (basis: DocWiki/.NET spec reading or invariant).

## 5. Phases

- **P0 — probes + skeleton.** EPOCHREALTIME format/locale probe on both bashes; fork-free
  wait idiom pick (`read -t` vs busy-loop); ctor-token form for startnew; class skeleton
  (Create/Destroy + fields) + tests runner; baseline re-measure via master suite (BEFORE
  adding the runner — upfront discovery). STOP/review.
- **P1 — full implementation + tests.** Start/Stop/Reset/Restart/isRunning/getters/
  getTimeStamp; state-machine + timing + zero-fork tests; dual-bash; full master sweep
  gate. STOP/review.
- **P2 — docs, bench, closeout.** README.md (bash API, overhead numbers, positioning);
  docs/TStopwatch.md (upstream Delphi reference per kcl docs convention); bench.sh
  (getter self-overhead, getTimeStamp cost, dispatch-vs-raw delta); TEST_COVERAGE_NOTES.md
  finalized; ledger COMPLETE; final sweep. STOP.

## 6. Bash traps to respect

1. `EPOCHREALTIME` decimal separator is locale-dependent — always `%[.,]*` parse; `10#` guard.
2. Read `$EPOCHREALTIME` once per stamp; never twice in one arithmetic expression.
3. `sleep` is an external binary (fork + ~10 ms MSYS2 startup): tests use builtin waits.
4. kklass `func` early-return skips the auto `kk._return` trailer — explicit `kk._return ""`
   on any fail path (tdictionary P1 lesson). Getters here never fail, but the ctor token
   validation path (unknown token → rc=1) needs it.
5. µs values exceed 32 bits (epoch µs ~1.7e15) — bash arithmetic is 64-bit, fine; never
   pass through `printf %d` of awk or anything 32-bit.

## 7. Deliverables

`kcl/tstopwatch/`: tstopwatch.sh, PLAN.md (this), tstopwatch_ledger.json, README.md,
docs/TStopwatch.md, bench.sh, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh.
