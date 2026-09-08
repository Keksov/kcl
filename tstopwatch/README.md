# kcl/tstopwatch — TStopwatch for bash

Port of Delphi `System.Diagnostics.TStopwatch` (a Delphi-spec unit — there is no
FPC RTL equivalent; where the Delphi DocWiki is silent, .NET `Stopwatch`
semantics break ties — Delphi's type mirrors it). An **instantiable** kklass
class: any number of stopwatches coexist, each with its own accumulated time.

The clock is the `EPOCHREALTIME` builtin (integer microseconds, bash ≥ 5.0,
zero forks). Mapping: **1 tick := 1 µs, `frequency` := 1000000** — exact and
ratio-compatible (code that divides ticks by frequency keeps working); we do
not emulate the Windows 10 MHz QPC frequency. It is a **wall clock**: NTP steps
or manual clock changes during a running measurement WILL distort it (bash has
no monotonic builtin — documented wontfix).

## Quick start

```bash
source kcl/tstopwatch/tstopwatch.sh

TStopwatch.new sw            # Delphi TStopwatch.Create — created STOPPED
sw.Start
step_one
sw.Stop                      # elapsed accumulates across Start/Stop cycles
sw.Start                     # resumes
step_two
sw.Stop
sw.GetElapsedMilliseconds >/dev/null
echo "total: $RESULT ms"     # fork-free read (func form + RESULT)
sw.delete

TStopwatch.new op startnew   # Delphi TStopwatch.StartNew — created RUNNING
```

## Reading results — three paths, three costs

kklass call contract: a **direct** call of a `func` is silent and sets
`$RESULT`; the value is echoed only under `$()` capture (subshell). Measured
2026-09-08 on MSYS2 with `bash bench.sh`, bash 5.2.37 / 5.3.9:

| Path | Example | Cost (5.2 / 5.3) | Use for |
|---|---|---|---|
| `TStopwatch.getTimeStamp` | `TStopwatch.getTimeStamp; t0=$RESULT` | 14 / 14 µs | tight loops, µs-scale deltas; RESULT-only in ALL contexts (never echoes) |
| Func form | `sw.GetElapsedMicroseconds; v=$RESULT` | 0.31 / 0.30 ms | normal reads — fork-free kklass dispatch |
| Property form | `sw.elapsedMicroseconds; v=$RESULT` | 0.73 / 0.75 ms | convenience — a dispatch, not a fork |
| Property under `$( )` | `$(sw.elapsedMicroseconds)` | 18 / 17.5 ms | avoid: the subshell, not the property, is the cost |

> **Property reads no longer fork** (this box, 2026-09-08). The old text here
> said a method-backed property read costs ~17.7 ms because kklass generated
> `RESULT="$($__inst__.call Getter)"`. Decision **D1** of the kklass fix plan
> landed: for a RESULT-returning getter the generated body is now
> `RESULT=""; $__inst__.call Getter`, which runs in the caller's shell. What is
> left is ~2.4× the func form — `kk._prop_computed` dispatching on top of the
> same call — not a process. The 17–18 ms figure now belongs only to `$( )`
> capture, which forks whatever is inside it (finding **G3-11**).

## API

| Member | Forms | Semantics |
|---|---|---|
| `TStopwatch.new sw [startnew]` | ctor | plain: STOPPED watch, elapsed 0 (S1). Token `startnew` (exact lowercase): created RUNNING (S2 — Delphi `StartNew`). Unknown token: rc 1 (silent; message under `VERBOSE_KKLASS=debug`), instance still a valid stopped watch |
| `sw.delete` | dtor | destroys the instance (no external storage) |
| `sw.Start` | proc | starts/**resumes**; no-op if already running (S4) |
| `sw.Stop` | proc | pauses; the segment folds into the accumulated total (S3); no-op if stopped (S4) |
| `sw.Reset` | proc | stops AND zeroes (S5) |
| `sw.Restart` | proc | Reset + Start as one atomic call (S5) |
| `sw.isRunning` / `sw.GetIsRunning` | property / func | `true`/`false` — see "Booleans" below |
| `sw.elapsedTicks` / `sw.GetElapsedTicks` | property / func | ticks == microseconds (1:1 mapping) |
| `sw.elapsedMicroseconds` / `sw.GetElapsedMicroseconds` | property / func | native unit, lossless (bash extra) |
| `sw.elapsedMilliseconds` / `sw.GetElapsedMilliseconds` | property / func | **truncates** (Delphi Int64 div: 1999 µs → 1 ms, S6) |
| `sw.elapsedSeconds` / `sw.GetElapsedSeconds` | property / func | truncating (bash extra; Delphi exposes seconds via TTimeSpan, not ported) |
| `sw.frequency` / `sw.GetFrequency` | property / func | constant `1000000` |
| `sw.isHighResolution` / `sw.GetIsHighResolution` | property / func | constant `true` |
| `TStopwatch.getTimeStamp` | plain function | raw current stamp, integer µs (S8); RESULT-only |

### Booleans — an API change in P6 (finding G3-12, default R8)

`isRunning` and `isHighResolution` used to answer with the **numbers 0 and 1**.
They now follow the kcl contract ([kcl/README.md](../README.md) §1.3): the word
`true`/`false` lands in `RESULT`, and **both the func form and the property
form carry the answer in the exit status** (a property getter's status is
propagated since kklass P6-F1, 2026-09-08).

```bash
if sw.isRunning; then echo "running"; fi           # status  (property form)
if sw.GetIsRunning; then echo "running"; fi        # status  (func form)
sw.isRunning;        [[ "$RESULT" == true ]]       # word
[[ "$(sw.isRunning)" == true ]]                    # word via $( )
```

*Migration:* `sw.isRunning; [[ "$RESULT" == 1 ]]` becomes
`if sw.GetIsRunning; then …`, or `[[ "$RESULT" == true ]]` if you prefer the
word.

The **property form cannot carry the status**: kklass builds a shim method for a
method-backed property and appends `kk._return "$RESULT"` to every function
body, which flattens the status to 0 before `kk._prop_computed` (kklass.sh:319)
can propagate it. Use `GetIsRunning` when you want `if`/`&&`/`||`; both forms
agree on the word. This is recorded as `found_in_P6` in `kcl/kcl_ledger.json`
and is a kklass-level gap, not a tstopwatch one.

Under `set -e`, a bare `sw.GetIsRunning` on a stopped watch aborts the caller —
bash's rule for every command — so call it from an `if`, a `&&`/`||`, or a `!`.

Reads are pure — no getter mutates state (S7); getters are valid in every
state (a fresh watch reads 0). Elapsed while running = accumulated + (now −
segment start).

## Honest positioning (measured numbers)

From `bash bench.sh` (N=300 dispatched / 10000 fast), **re-measured 2026-09-08**
after kklass D1 removed the per-read property fork (finding G3-11). The previous
edition of this table quoted 17.7 ms for a property read and 654 µs for the
empty bracket; both were from before D1 and are gone.

| Metric | 5.2.37 | 5.3.9 |
|---|---|---|
| raw `EPOCHREALTIME` parse, inline | 8.9 µs | 9.1 µs |
| `TStopwatch.getTimeStamp` | 14.4 µs | 14.4 µs |
| func getter (`GetElapsedMicroseconds`) | 312 µs | 298 µs |
| func boolean (`GetIsRunning`) | — | 305 µs |
| `Start`+`Stop` pair (caller cost) | 537 µs | 575 µs |
| property getter (`elapsedMicroseconds`) | 726 µs | 751 µs |
| property getter under `$( )` | 18.1 ms | 17.5 ms |
| **empty-bracket bias** (what `Start;Stop` with nothing inside measures) | **261 µs** | **295 µs** |

Consequences:

- The object API structures measurements of **multi-millisecond** work: an
  empty `Start;Stop` bracket already reads ~0.3 ms (the Stop dispatch sits
  inside the measured window). Don't point it at 50 µs intervals.
- For µs-scale timing use `TStopwatch.getTimeStamp` deltas (~14 µs/call,
  RESULT-only, loop-safe) or the raw inline parse (~9 µs).
- Property reads are now ~2.4× a func read, not ~35×. Both are dispatches; use
  the func form in loops, either form elsewhere.
- Everything is fork-free on the direct-call path — the whole API, properties
  included, runs under `PATH=''` (tests/004, tests/006). On MSYS2 a single fork
  is ~17 ms, i.e. one `$( )` costs more than 60 empty brackets; that's why the
  fork-free discipline matters here more than anywhere.
- The clock survives a decimal-comma locale: on bash 5.2 `EPOCHREALTIME` prints
  `1788676658,546051` under `de_DE`/`ru_RU`, which the `${er%[.,]*}` parse
  handles (tests/006 runs the whole API under three locales).

## Not ported (wontfix, with reasons)

1. **`Elapsed: TTimeSpan`** — kcl has no TTimeSpan; the numeric getters
   (µs/ms/s/ticks) cover the use cases.
2. **Record value semantics** (copy-on-assign) — kklass instances are
   references; no bash analog.
3. **Monotonic-clock guarantee (QPC)** — `EPOCHREALTIME` is wall-clock; NTP
   steps can distort a running measurement. No monotonic builtin exists.
4. **Thread-affinity caveats** — no threads in bash.

## Files

- `tstopwatch.sh` — the unit (class + `TStopwatch.getTimeStamp`).
- `tests/` — 001 creation/destruction, 002 state machine (exact, timing-free),
  003 timing/accumulation (busy-loop lower bounds — guaranteed by
  construction), 004 zero-fork (`PATH=''`), 005 kcl contract, 006 booleans
  and locale (G3-11/G3-12: the rc contract, the absence of the property fork,
  and the clock under C/de_DE/ru_RU); runner `tests/tests.sh`.
- `bench.sh` — the numbers above; run `bash bench.sh [N] [NFAST]`.
- `docs/TStopwatch.md` — upstream Delphi API reference (kcl docs convention).
- `PLAN.md`, `tstopwatch_ledger.json`, `TEST_COVERAGE_NOTES.md` — port plan,
  status ledger, and the non-FPC coverage protocol (every test here is
  non-FPC by construction: the API is Delphi-only).

