# TStopwatch — upstream Delphi API reference

Source of truth: Delphi `System.Diagnostics.TStopwatch` (Embarcadero DocWiki:
<https://docwiki.embarcadero.com/Libraries/en/System.Diagnostics.TStopwatch>).
There is **no FPC RTL equivalent** — this is a Delphi-spec unit, the same
situation as tfile/tpath/tdirectory/tstringhelper. Delphi's TStopwatch mirrors
.NET `System.Diagnostics.Stopwatch`; where the DocWiki is terse, the .NET spec
is the tiebreaker (noted per member below).

Upstream declaration shape:

```pascal
TStopwatch = record            // a VALUE type in Delphi
  class function Create: TStopwatch; static;
  class function StartNew: TStopwatch; static;
  class function GetTimeStamp: Int64; static;
  procedure Start;
  procedure Stop;
  procedure Reset;
  class property Frequency: Int64 read ...;
  class property IsHighResolution: Boolean read ...;
  property Elapsed: TTimeSpan read ...;
  property ElapsedMilliseconds: Int64 read ...;
  property ElapsedTicks: Int64 read ...;
  property IsRunning: Boolean read ...;
end;
```

(`Restart` exists in .NET; Delphi ships it from XE8+ — kept, see below.)

This document lists every public member with its kcl/bash mapping. Members
with no bash counterpart are **wontfix** with the reason (see also PLAN.md §1).

kcl mapping conventions: the class is a kklass **instance** class (see the
Record semantics note); `func` results → `RESULT` on direct call, echoed under
`$()` capture; booleans → `0`/`1` values.

---

## Class functions

### Create

```pascal
class function Create: TStopwatch; static;
```

Returns an initialized, **stopped** stopwatch with zero elapsed time. (In
Delphi this is a class function returning a record value, not a constructor.)

**kcl:** `TStopwatch.new sw` — created stopped, elapsed 0 (pin S1).

### StartNew

```pascal
class function StartNew: TStopwatch; static;
```

Returns a new stopwatch that is **already running** (Create + Start in one
step).

**kcl:** `TStopwatch.new sw startnew` — ctor token, exact lowercase (token
style per TObjectDictionary ownership tokens). Unknown tokens → rc 1, silent
(message under `VERBOSE_KKLASS=debug`); the instance is still a valid stopped
watch (fields initialize before validation).

### GetTimeStamp

```pascal
class function GetTimeStamp: Int64; static;
```

The current raw timestamp in ticks: QPC counter value when high-resolution,
otherwise `TDateTime`-derived ticks.

**kcl:** `TStopwatch.getTimeStamp` — a PLAIN file-level function (no kklass
dispatch), returns the current stamp in integer µs via `RESULT` **only**
(never echoes, in any context — deliberate deviation from the func
convention: this is the tight-loop path, where an echo would flood stdout and
`$()` would fork; pin S8). ~17 µs/call on MSYS2 vs ~0.5 ms for dispatched
methods.

## Instance methods

### Start

```pascal
procedure Start;
```

Starts, or **resumes**, measuring elapsed time. Starting an already-running
stopwatch has no effect (.NET: "has no effect").

**kcl:** `sw.Start` — begins a new segment; no-op while running (pins S3/S4).

### Stop

```pascal
procedure Stop;
```

Stops measuring. Elapsed accumulates across Start/Stop cycles. Stopping a
stopped watch has no effect.

**kcl:** `sw.Stop` — folds the finished segment into the accumulated total;
no-op while stopped (pins S3/S4).

### Reset

```pascal
procedure Reset;
```

Stops the stopwatch and resets the elapsed time to zero (.NET semantics; the
DocWiki matches).

**kcl:** `sw.Reset` (pin S5).

### Restart

```pascal
procedure Restart;
```

Reset + Start as one operation: the watch ends up running with elapsed ~0.

**kcl:** `sw.Restart` — atomic (one method call; pin S5).

## Properties

### IsRunning

```pascal
property IsRunning: Boolean read FRunning;
```

**kcl:** `sw.isRunning` (property) / `sw.GetIsRunning` (func form) — `1`/`0`.

### ElapsedTicks

```pascal
property ElapsedTicks: Int64 read GetElapsedTicks;
```

Elapsed time in ticks; `ElapsedTicks / Frequency` = seconds.

**kcl:** `sw.elapsedTicks` / `sw.GetElapsedTicks`. **1 tick := 1 µs** — the
bash mapping keeps the ratio contract exactly (`frequency` is 1e6); we do not
emulate the 10 MHz Windows QPC tick.

### ElapsedMilliseconds

```pascal
property ElapsedMilliseconds: Int64 read GetElapsedMilliseconds;
```

Elapsed time in whole milliseconds — Int64 division, i.e. **truncation**.

**kcl:** `sw.elapsedMilliseconds` / `sw.GetElapsedMilliseconds` — truncates
(1999 µs → 1 ms; pin S6, proven by seeding in tests/002).

### Elapsed

```pascal
property Elapsed: TTimeSpan read GetElapsed;
```

**wontfix** — kcl has no TTimeSpan type; the numeric getters cover the use
cases. In its place the port adds two bash extras (TEST_COVERAGE_NOTES rows):

- `sw.elapsedMicroseconds` / `sw.GetElapsedMicroseconds` — the native unit,
  lossless;
- `sw.elapsedSeconds` / `sw.GetElapsedSeconds` — truncating whole seconds.

## Class properties

### Frequency

```pascal
class property Frequency: Int64 read FFrequency;
```

Ticks per second of the underlying timer.

**kcl:** `sw.frequency` / `sw.GetFrequency` — constant **1000000**.

### IsHighResolution

```pascal
class property IsHighResolution: Boolean read FIsHighResolution;
```

True when backed by the high-resolution counter.

**kcl:** `sw.isHighResolution` / `sw.GetIsHighResolution` — constant **1**
(`EPOCHREALTIME` is the µs builtin clock). Caveat kept honest: the clock is
**wall-clock**, not monotonic — a QPC-grade steadiness guarantee is exactly
what bash cannot give (wontfix; NTP steps can distort a running measurement).

## Not ported (summary)

| Upstream | Reason |
|---|---|
| `Elapsed: TTimeSpan` | no TTimeSpan in kcl; numeric getters + µs/s extras instead |
| Record value semantics (copy-on-assign) | kklass instances are references; no bash analog |
| QPC / monotonic guarantee | `EPOCHREALTIME` is wall-clock; no monotonic builtin in bash |
| Thread-affinity notes | no threads in bash |
