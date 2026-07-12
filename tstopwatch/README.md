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
on MSYS2 (bench.sh, bash 5.2.37 / 5.3.9):

| Path | Example | Cost | Use for |
|---|---|---|---|
| `TStopwatch.getTimeStamp` | `TStopwatch.getTimeStamp; t0=$RESULT` | ~17 / 12 µs | tight loops, µs-scale deltas; RESULT-only in ALL contexts (never echoes) |
| Func form | `sw.GetElapsedMicroseconds; v=$RESULT` | ~0.5 ms | normal reads — fork-free kklass dispatch |
| Property form | `$(sw.elapsedMicroseconds)` | ~18 ms direct, ~35 ms via `$()` | one-off convenience only — see the warning below |

> **Property reads fork.** A method-backed kklass property read is generated
> as `RESULT="$($__inst__.call Getter)"` ([kklass_decl.sh:261]) — one subshell
> fork per read, ~17 ms on MSYS2. This is a house-wide kklass cost (tdictionary
> `d.count` pays exactly the same), not something this unit can fix. In
> anything measured or looped, use the func forms (`GetXxx` + `$RESULT`).

## API

| Member | Forms | Semantics |
|---|---|---|
| `TStopwatch.new sw [startnew]` | ctor | plain: STOPPED watch, elapsed 0 (S1). Token `startnew` (exact lowercase): created RUNNING (S2 — Delphi `StartNew`). Unknown token: rc 1 (silent; message under `VERBOSE_KKLASS=debug`), instance still a valid stopped watch |
| `sw.delete` | dtor | destroys the instance (no external storage) |
| `sw.Start` | proc | starts/**resumes**; no-op if already running (S4) |
| `sw.Stop` | proc | pauses; the segment folds into the accumulated total (S3); no-op if stopped (S4) |
| `sw.Reset` | proc | stops AND zeroes (S5) |
| `sw.Restart` | proc | Reset + Start as one atomic call (S5) |
| `sw.isRunning` / `sw.GetIsRunning` | property / func | 0/1 |
| `sw.elapsedTicks` / `sw.GetElapsedTicks` | property / func | ticks == microseconds (1:1 mapping) |
| `sw.elapsedMicroseconds` / `sw.GetElapsedMicroseconds` | property / func | native unit, lossless (bash extra) |
| `sw.elapsedMilliseconds` / `sw.GetElapsedMilliseconds` | property / func | **truncates** (Delphi Int64 div: 1999 µs → 1 ms, S6) |
| `sw.elapsedSeconds` / `sw.GetElapsedSeconds` | property / func | truncating (bash extra; Delphi exposes seconds via TTimeSpan, not ported) |
| `sw.frequency` / `sw.GetFrequency` | property / func | constant `1000000` |
| `sw.isHighResolution` / `sw.GetIsHighResolution` | property / func | constant `1` |
| `TStopwatch.getTimeStamp` | plain function | raw current stamp, integer µs (S8); RESULT-only |

Reads are pure — no getter mutates state (S7); getters are valid in every
state (a fresh watch reads 0). Elapsed while running = accumulated + (now −
segment start).

## Honest positioning (measured numbers)

From `bash bench.sh` (N=300 dispatched / 10000 fast):

| Metric | 5.2.37 | 5.3.9 |
|---|---|---|
| raw `EPOCHREALTIME` parse, inline | 9.1 µs | 7.9 µs |
| `TStopwatch.getTimeStamp` | 17.7 µs | 12.4 µs |
| func getter (`GetElapsedMicroseconds`) | 544 µs | 535 µs |
| `Start`+`Stop` pair (caller cost) | 1015 µs | 896 µs |
| property getter (`elapsedMicroseconds`) | 17.7 ms | 17.4 ms |
| **empty-bracket bias** (what `Start;Stop` with nothing inside measures) | **654 µs** | **595 µs** |

Consequences:

- The object API structures measurements of **multi-millisecond** work: an
  empty `Start;Stop` bracket already reads ~0.6 ms (the Stop dispatch sits
  inside the measured window). Don't point it at 50 µs intervals.
- For µs-scale timing use `TStopwatch.getTimeStamp` deltas (~17 µs/call,
  RESULT-only, loop-safe) or the raw inline parse (~9 µs).
- Everything is fork-free on the func-form path — the whole API runs under
  `PATH=''` (tests/004). On MSYS2 a single fork is ~17 ms, i.e. one fork
  costs more than 30 empty brackets; that's why the fork-free discipline
  matters here more than anywhere.

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
  construction), 004 zero-fork (`PATH=''`); runner `tests/tests.sh`.
- `bench.sh` — the numbers above; run `bash bench.sh [N] [NFAST]`.
- `docs/TStopwatch.md` — upstream Delphi API reference (kcl docs convention).
- `PLAN.md`, `tstopwatch_ledger.json`, `TEST_COVERAGE_NOTES.md` — port plan,
  status ledger, and the non-FPC coverage protocol (every test here is
  non-FPC by construction: the API is Delphi-only).

[kklass_decl.sh:261]: ../../kklass/kklass_decl.sh
