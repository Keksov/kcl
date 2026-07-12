# tstopwatch — test coverage notes (non-FPC cases)

**Status: FINALIZED at P2 (2026-07-12).** 34 test cases across 001–004, all
non-FPC by construction (Delphi-only API) — 23 rows below. P2 added no test
cases (README/docs/bench only); bench.sh measurements are not tests and are
recorded in README.md and the ledger instead.

Protocol (same as dateutils/math/tdictionary): every test case **not traceable to an
FPC test file** gets a row here. For tstopwatch that is EVERY case: the API is
Delphi-only (System.Diagnostics.TStopwatch — no FPC RTL unit, no FPC tests). Basis
column therefore cites the Delphi DocWiki member semantics, the .NET Stopwatch spec
(tiebreaker), or the invariant being cross-checked. Classes: `boundary`,
`bash-convention` (rc mapping, RESULT, lifecycle, tokens), `representation`
(clock/µs specifics), `cross-check` (internal consistency, no external oracle).

## P0 — skeleton (001)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 001.create-stopped | Create | fresh watch: rc 0, `_running=0 _accum=0 _t0=0` | bash-convention | DocWiki Create — "initialized instance… stopped" (S1); fields white-box until P1 getters |
| 001.field-store | Create | `${inst}_data` is `declare -A` with exactly the 3 declared fields | representation | kklass var storage contract; guards accidental field additions |
| 001.startnew-window | Create(startnew) | `_t0` ∈ [before, after] stamps around the call; `_running=1 _accum=0` | cross-check | DocWiki StartNew — "created… started" (S2); window read with the same clock — exact by construction, timing-free |
| 001.bad-token | Create | unknown token → rc 1, instance = valid STOPPED watch | bash-convention | token style per TObjectDictionary ownership tokens; fields init before validation (defensive shape) |
| 001.token-exact | Create | `StartNew` (wrong case) rejected — token is exact lowercase `startnew` | bash-convention | pinned P0 decision: one spelling, like doOwnsKeys is FPC-cased |
| 001.token-silence | Create | rejection silent by default; message only under `VERBOSE_KKLASS=debug` | bash-convention | house error convention (tlist/tdictionary style) |
| 001.independence | Create | stopped and running instance coexist without cross-talk | cross-check | kklass per-instance store; two-watch scenario is the unit's raison d'être |
| 001.lifecycle | Destroy | delete → rc 0, `${inst}_data` unset, second delete fails, recreate fresh | bash-convention | kklass `.delete` + destructor contract |
| 001.zero-fork | Create/Destroy | full new/new-startnew/delete lifecycle under `PATH=''` | representation | zero-fork house goal; EPOCHREALTIME is a builtin |

## P1 — state machine, timing, zero-fork (002, 003, 004)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 002.fresh-zero | all getters | fresh watch: isRunning 0, us/ticks/ms/s all 0 | bash-convention | DocWiki Create (S1); getters valid in every state (S7) |
| 002.reads-nondecreasing | elapsedMicroseconds | two successive reads while running: r2 >= r1 | cross-check | same-clock monotonicity between consecutive reads (wall-clock steps aside — wontfix) |
| 002.reads-pure | all getters | state triple `_accum/_t0/_running` byte-identical after 5 getter calls | cross-check | DocWiki Elapsed* are read-only (S7); white-box proves no state writes |
| 002.double-start | Start | Start while running: `_t0` unchanged, still running | boundary | .NET Stopwatch.Start — "has no effect" when running (S4); white-box t0 makes the no-op EXACT |
| 002.double-stop | Stop | second Stop: `_accum` unchanged | boundary | .NET Stopwatch.Stop no-op when stopped (S4) |
| 002.frozen-stopped | elapsedMicroseconds | two reads while stopped EXACTLY equal | cross-check | stopped watch reads `_accum` only — timing-free exactness |
| 002.reset-running | Reset | Reset on a RUNNING watch: stops AND zeroes (S5) | boundary | DocWiki Reset; .NET: "stops and resets" |
| 002.restart-window | Restart | after Restart: running, `_accum`=0, `_t0` ∈ [before, after] | cross-check | DocWiki Restart = Reset+Start atomic (S5); window on the same clock — exact by construction |
| 002.ms-truncation | elapsedMilliseconds | white-box `_accum` seed: 999→0, 1999→1 | representation | Delphi Int64 `div` truncates (S6); seeding removes real time from the test entirely |
| 002.s-truncation | elapsedSeconds | seed: 1999999→1, 2000000→2 | representation | bash-convenience getter (TTimeSpan not ported); same truncation rule |
| 002.ticks-eq-us | elapsedTicks | seeded 123456: ticks == us exactly | representation | 1 tick := 1 µs mapping (PLAN §2.2) |
| 002.ratio | elapsedTicks/frequency | ticks/frequency == elapsedSeconds (2500000/1000000==2) | cross-check | the Delphi-shaped division contract the mapping promises |
| 002.constants | frequency/isHighResolution | 1000000/1 in fresh, running AND stopped states | bash-convention | class constants (PLAN §2.2); state-independence check |
| 002.independence | all | full op cycle on watch B leaves watch A's triple untouched | cross-check | kklass per-instance store; concurrent-watches use case |
| 003.segment-lower | Start/Stop | 15 ms busy window inside a segment → elapsed >= 15000 µs, < +10 s | cross-check | busy-wait spins on the SAME clock → lower bound guaranteed by construction; wide upper catches unit confusion (µs/ms/ns) only |
| 003.gap-frozen | Stop | 10 ms busy gap while stopped adds NOTHING (exact equality) | cross-check | S3 accumulate-on-Stop model: stopped state has no clock term |
| 003.accumulation | Start/Stop | second 15 ms segment → total >= 30000 µs and > segment1 | cross-check | DocWiki Start "resumes"; .NET cumulative elapsed (S3) |
| 003.startnew-measures | Create(startnew) | startnew watch covers a 10 ms window immediately | cross-check | DocWiki StartNew (S2) — no separate Start needed |
| 003.gettimestamp-delta | getTimeStamp | delta across 10 ms busy window >= 10000 µs | cross-check | DocWiki GetTimeStamp (S8); same-clock lower bound |
| 003.gettimestamp-monotone | getTimeStamp | 3 immediate calls nondecreasing | boundary | S8 modulo wall-clock steps (documented wontfix) |
| 003.gettimestamp-silent | getTimeStamp | direct call: 0 bytes stdout, RESULT = epoch-µs magnitude | bash-convention | RESULT-ONLY design pin (tight-loop path: echo would flood stdout, $() would fork) |
| 004.zero-fork-api | ALL members | new/Start/Stop/getters×7/Restart/Reset/getTimeStamp/new-startnew/delete — every rc 0 under `PATH=''` | representation | zero-fork house goal: builtins + 64-bit shell arithmetic only |
| 004.call-contract | frequency (repr. getter) | under `PATH=''`: DIRECT call silent + RESULT; `$()` capture echoes | bash-convention | kklass kk._return contract (echo only when BASH_SUBSHELL>0); $() is a subshell fork, not an exec — both paths PATH-independent |
