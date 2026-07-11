# math — Free Pascal `Math` for bash (kcl)

Port of the FPC `Math` unit to a kcl static utility class.

- **Source of truth**: `C:\projects\KKMindWave\VendorsCore\fpc\sources\main\rtl\objpas\math.pp`
  (4083 lines; ~100 distinct public function names, ~587 declarations once the
  Single/Double/Extended type overloads are counted).
- **Destination**: `kcl/math/math.sh` (+ `tests/`, `docs/Math.md`, this plan, `math_ledger.json`).
- **Ledger**: [math_ledger.json](math_ledger.json) — single source of truth for task status.

---

## 1. Core design decision: the hybrid model

Unlike `DateUtils` — which collapsed onto a single integer (KDT) and became
pure-bash, zero-fork, **bit-exact** — `Math` is ~80% irreducibly floating-point
(all trig, inverse-trig, hyperbolic, logs, exponentials, `sqrt`-based
statistics, and the financial annuity functions operate on IEEE `Double`). Bash
has no floating-point type, and there is no integer trick that rescues them.

The port is therefore **hybrid**, splitting the unit by feasibility:

> **Tier A — integer/decimal core**: everything bash can compute *exactly* and
> *fork-free* stays pure bash (`Min` `Max` `Sign` `InRange` `EnsureRange`
> `DivMod` `Ceil` `Floor` `RoundTo` `SimpleRoundTo` `CompareValue` `IfThen`
> `SumInt` `RandomRange` `RandomFrom`, integer `**`). Exact FPC parity, ≤0.3 ms/call.
>
> **Tier B — transcendental**: everything requiring real-number math is
> delegated to a **persistent `awk` co-process** (the "float engine"). One fork
> per process lifetime, then sub-millisecond pipe round-trips. awk computes in C
> `double`s — the same IEEE-754 binary64 FPC uses for `Double` on the x86-64
> targets — so results match FPC to the last 1–2 ulps.
>
> **Tier C — not applicable**: FPU control (`SetRoundMode`, `SetExceptionMask`,
> …) and precision-mode / Extended-vs-Double distinctions have no bash analogue —
> `wontfix`, documented.

### 1a. The float engine — a persistent `awk` co-process

The centerpiece of Tier B. `math` starts **one** `awk` co-process (bash `coproc`)
**lazily**, on the first call that needs real-number math, and keeps it alive for
the process lifetime. Each subsequent call is a pipe round-trip (write one
request line, read one answer line) — **no fork per call**.

- **Spawn** — `math._fe_start` runs the coproc at most once (guarded by a plain
  global `__MATH_FE_UP`); the pid and fds live in plain globals `__MATH_FE_*`
  (the class stays static-var-free → thin dispatch, see §4).
- **Prelude** — the awk program (a) defines every derived function from awk's
  primitives (`sin cos atan2 exp log sqrt int` and `^`): `tan cotan asin acos
  sinh cosh tanh` + all the `arc*`/`ar*` hyperbolics, `log2 log10 logn power
  hypot fmod ldexp frexp` and the financial kernels; and (b) runs a dispatch
  loop — read `op a b c…`, compute, `printf "%.17g\n"`, then **`fflush()`** (so
  the reader never blocks on buffered output).
- **Call** — `math._fe op args… → REPLY`. `%.17g` round-trips a binary64 exactly;
  `nan`/`inf`/`-inf` pass through as literal tokens.
- **Teardown** — `math.feStop` closes the coproc (it also dies with the shell);
  `math.feActive` reports whether it was ever started.
- **Graceful degradation** — if no `awk` is on `PATH`, engine calls return 1 with
  a `VERBOSE_KKLASS=debug` message; the entire Tier-A core still works.
- **Scoped zero-fork guarantee** — the integer/decimal core NEVER touches the
  engine and stays fork-free and ≤0.3 ms/call, pinned by a test the way
  `tfile` 038 pins thin dispatch. Only transcendental calls use the coproc.

*Why a co-process, not a fork-per-call or a pure-bash CORDIC engine*: fork-per-call
(~10–30 ms on MSYS2) would betray the kcl zero-fork ethos on every `sin`; a
pure-bash fixed-point libm (CORDIC/series) is weeks of work and can only reach
tolerance-parity anyway. The lazy co-process is one fork total, sub-ms
thereafter, and inherits libm's accuracy for free.

### 1b. Value representation

- **Integers** — plain bash integers, exact `$(( ))`.
- **Reals** — decimal strings (`3.14159265358979`, `-2.5`, `1e-9`, `inf`,
  `-inf`, `nan`). Passed as arguments, echoed as results. `%.17g` on the way out
  of the engine.
- **Arrays** (`Mean`, `Sum`, `MinValue`, `Norm`, …) — passed as the argument
  list: `math.mean 1 2 3 4`. FPC's `array of T` and `PT + N` overloads both
  collapse to "the remaining arguments".
- **Decimal comparison in the core** — a pure-bash comparator `_dec_cmp a b →
  -1/0/1` (split sign/integer/fraction, pad, compare) keeps `Sign` / `CompareValue`
  / `InRange` / `Min` / `Max` fork-free on decimal inputs; no engine needed.

### Value conventions (kcl house style — same spirit as `dateutils`)

| FPC concept | bash convention |
|---|---|
| numeric in/out | integer or decimal string, echoed as a plain token |
| `Boolean` result | echo `true` / `false` |
| `TValueSign` (`Sign`) | echo `-1` / `0` / `1` |
| `TValueRelationship` (`CompareValue`) | echo `-1` / `0` / `1` (= `LessThanValue`/`EqualsValue`/`GreaterThanValue`) |
| `out`/`var` params (`SinCos`, `DivMod`, `Frexp`, `SumsAndSquares`) | echo space-separated fields (`read -r a b`) |
| `Double` result | decimal string, `%.17g` from the engine |
| `NaN` / `±Inf` | literal `nan` / `inf` / `-inf` tokens |
| errors (`EInvalidArgument`) | `return 1`, echo nothing; stderr only under `VERBOSE_KKLASS=debug` |
| type overloads (Single/Double/Extended) | collapse to one method (bash is typeless; engine works in Double) |

---

## 2. Class shape

Pascal DSL static utility class, identical pattern to `dateutils`/`tpath`/`tfile`:

```bash
source "../../kklass/kklass_pascal.sh"
class math
    public
        static proc min
        static proc max
        static proc sign
        static proc degToRad
        ...
end
math.min() { ... }
...
build math
```

- **No `static var`** — the class must stay on the thin, capture-free dispatcher
  (fast on bash 5.2 which lacks funsub, and 5.3). The engine's pid/fds and all
  constants are therefore top-level globals, prefixed `__MATH_` and declared
  `readonly` where constant (behind a `_MATH_SOURCED` re-source guard), exactly
  as `dateutils` does with `__KDT_*`.
- **Public constant getters as `static proc`s**: `math.pi`, `math.e`,
  `math.infinity`, `math.nan`, `math.minDouble`, `math.maxDouble`, … — keeps the
  class static-var-free while giving a namespaced API for the constants FPC
  exposes; internals read the `__MATH_*` globals directly.
- **Method names**: FPC names in lowerCamelCase (`ArcTan2` → `math.arcTan2`,
  `RoundTo` → `math.roundTo`, `DegToRad` → `math.degToRad`).
- **Internal helpers** (`math._fe`, `math._dec_cmp`, `math._trunc`, …) are plain
  functions, not class members; they return via `REPLY`.
- **Overload folding**: `Min(a,b)` over all numeric types → one `math.min a b`;
  the array reducers keep their distinct FPC names (`math.minValue`,
  `math.minIntValue`, `math.maxValue`, `math.maxIntValue`).

---

## 3. Semantics notes (FPC parity points, verified against the source)

- **`RoundTo`** = `Round(AValue / 10^Digits) * 10^Digits` — **banker's rounding**
  (round-half-to-**even**), `Digits` is the power of ten (`Digits=-2` → 2 dp).
- **`SimpleRoundTo`** = `Int(AValue·RV ± 0.5)/RV`, `RV=10^(-Digits)` — **arithmetic
  rounding** (half **away from zero**), default `Digits=-2`. The two rounders
  differ deliberately; both are honored.
- **`Sign`** returns `-1/0/1` (`TValueSign = -1..1`).
- **`CompareValue(A,B,delta)`** → `EqualsValue` when `|A-B| ≤ delta`, else sign of
  `A-B`; the `delta` tolerance form is kept (default `0`).
- **`DivMod`** — integer division + remainder with FPC truncation-toward-zero
  semantics (seed: `tmath1.pp` — `-10 div 5 = -2`, etc.); echoes `quotient remainder`.
- **`Ceil`/`Floor`** round toward +∞ / −∞ and return an integer; `Ceil64`/`Floor64`
  the Int64 forms (in bash one integer domain, but both names kept).
- **`RandomRange(aFrom,aTo)`** = `Random(Abs(aFrom-aTo)) + Min(aFrom,aTo)` →
  uniform in `[min, max)` (**upper-exclusive**). FPC uses its own Mersenne RNG, so
  value-for-value parity is impossible; parity is **semantic** ("result in range").
- **`IfThen(cond, a, b=0)`** — ternary; `cond` given as `true`/`false` or `0`/`1`.
- **`IsZero`/`SameValue`** use FPC's default epsilon when none is given
  (resolution-scaled); the explicit-epsilon overloads are kept.
- **`InRange`/`EnsureRange`** — closed interval `[AMin,AMax]`; `EnsureRange` clamps.
- **Angle conversions** — `DegToRad`/`RadToDeg`/`GradToRad`/`RadToGrad`/`CycleTo*`/
  `*ToCycle` go through the engine (π is irrational; FPC returns `Double`).
  `DegToGrad`/`GradToDeg` are rational but still routed through the engine so the
  `Double` result matches FPC bit-for-bit. `DegNormalize` wraps into `[0,360)`.
- **`Hypot(x,y)`** = `sqrt(x²+y²)` with overflow-safe scaling (engine).
- **NaN/Inf** — `IsNan`/`IsInfinite` test for the `nan`/`inf`/`-inf` tokens.

---

## 4. Out of scope (recorded as wontfix in the ledger)

| FPC item | Reason |
|---|---|
| `GetRoundMode`/`SetRoundMode`, `GetPrecisionMode`/`SetPrecisionMode`, `GetExceptionMask`/`SetExceptionMask`, `ClearExceptions` + the `TFPU*` types | FPU control-word access — no bash/awk equivalent. Provided as stubs that report the default mode and `return 1` on set. |
| Rounding-mode-dependent int→float conversion (seed `troundm.pp`) | Bit patterns depend on the FPU rounding mode; N/A once the FPU is out of scope. |
| Single / Extended precision distinct from Double | Bash has one numeric domain; the engine works in `Double`. Single/Extended overloads fold into the Double method. Documented; tolerance parity covers the Extended-only last digits. |
| `PSingle/PDouble/PExtended + N` pointer overloads | Bash has no pointers; the `array of T` form (arg list) is the single surviving shape. |
| IEEE range constants (`MinSingle` `MaxDouble` `MinExtended` …) as *operational* limits | Exposed as **informational** string constants via getters; bash cannot overflow/denormalise like a native float, so they carry no runtime effect. |
| `generic RandomFrom<T>` | Generics have no bash meaning; the concrete `RandomFrom` (arg list) covers it. |

*Convenience additions (NOT in `math.pp`, provided anyway)*: `math.sin` `math.cos`
`math.sqrt` `math.exp` `math.ln` `math.arcTan` — the System-unit elementaries the
engine already defines, exposed because a bash "math" library is expected to have
them. Marked clearly as System-sourced in the docs.

---

## 5. Phases

Each phase = implement → per-function ktest file(s) → **full kcl+kklass sweep
green on bash 5.2** → spot-check on 5.3 → ledger update. The kcl baseline
(**kcl 1512** incl. dateutils 123, **kklass 226**, examples 48/48 — measured
2026-07-11) must never regress; the math suite adds on top.

- **P0 — Scaffolding, float engine, decimal helpers** *(gate for everything)*
  Directory, `class math` skeleton, tests runner, `__MATH_*` constants
  (`Pi` `E` `Infinity` `NaN` `NegInfinity` + informational IEEE constants), the
  **`awk` float-engine co-process** (`_fe_start`/`_fe`/`_fe_stop`, the awk
  prelude of derived functions, the `fflush` protocol, lazy spawn, graceful
  no-awk degradation), and the pure-bash decimal helpers (`_dec_cmp` `_dec_split`
  `_is_int` `_trunc`). Acceptance: engine round-trips `sin`/`sqrt`/`atan2` to
  Double precision; **exactly one** awk process, spawned lazily; `math.pi`
  correct; `_dec_cmp` correct incl. negatives and unequal precision; the core
  path spawns zero forks (empty-`PATH` check).

- **P1 — Integer/decimal core** (pure-bash, exact, zero-fork)
  `Min` `Max` `MinIntValue` `MaxIntValue` `MinValue` `MaxValue` `Sign`
  `InRange` `EnsureRange` `IsZero` `SameValue` `CompareValue` `IfThen`.
  Acceptance: exact integer AND decimal inputs; `Sign` ∈ {−1,0,1}; `EnsureRange`
  clamps to `[min,max]`; `CompareValue` delta form; zero forks (pinned).

- **P2 — Rounding & number conversion** (pure-bash decimal + engine `fmod`)
  `Ceil` `Ceil64` `Floor` `Floor64` `RoundTo` `SimpleRoundTo` `DivMod` `FMod`
  `operator mod`, integer `IntPower`/`**`, helpers `Trunc`/`Frac`. Acceptance:
  Ceil/Floor on decimals incl. negatives and exact integers; `RoundTo`
  half-to-even fixtures (`2.5→2`, `3.5→4`, `2.115@-2`); `SimpleRoundTo`
  half-away fixtures; `DivMod` seeded from `tmath1.pp`; documented note on the
  rare binary-vs-decimal half-way divergence from FPC's `Double`.

- **P3 — Angle conversions** (engine)
  `DegToRad` `RadToDeg` `GradToRad` `RadToGrad` `DegToGrad` `GradToDeg`
  `CycleToDeg` `DegToCycle` `CycleToGrad` `GradToCycle` `CycleToRad` `RadToCycle`
  `DegNormalize`. Acceptance: `DegToRad(180)=π`, `RadToDeg(π)=180`, grad/cycle
  roundtrips; `DegNormalize` wraps `-90→270`, `450→90`.

- **P4 — Trig, inverse, hyperbolic, area** (engine, ~30 fn)
  `Tan` `Cotan` `Cot` `SinCos` `Secant` `Cosecant` `Sec` `Csc` `ArcCos`
  `ArcSin` `ArcTan2` `cosh` `sinh` `tanh` `SecH` `CscH` `CotH` `ArcCosH`
  `ArcSinH` `ArcTanH` `ArCosH` `ArSinH` `ArTanH` `ArcSec` `ArcCsc` `ArcCot`
  `ArcSecH` `ArcCscH` `ArcCotH` + convenience `sin` `cos` `arcTan`. Acceptance:
  tolerance parity vs an FPC-reference fixture grid; `SinCos` echoes `sin cos`;
  identities (`tan=sin/cos`, `sinh²−cosh²=−1`) hold to tolerance.

- **P5 — Logs, exponentials, powers, misc** (engine + pure integer power)
  `Log10` `Log2` `LogN` `LnXP1` `ExpM1` `Power` `IntPower` `operator **`(float)
  `Hypot` `Frexp` `Ldexp` + convenience `sqrt` `exp` `ln`. Integer
  `**`(Int64,Int64) stays pure-bash. Acceptance: `Power(2,10)=1024`,
  `Log2(1024)=10`, `Hypot(3,4)=5`, `LnXP1`/`ExpM1` accurate for `x≈1e-9`,
  `Frexp`/`Ldexp` roundtrip (`x = mantissa·2^exp`).

- **P6 — Statistics** (engine + pure-bash integer sums)
  `Mean` `Sum` `SumInt` `SumOfSquares` `SumsAndSquares` `MinValue`/`MaxValue`
  (reuse P1) `StdDev` `MeanAndStdDev` `Variance` `TotalVariance` `PopnStdDev`
  `PopnVariance` `MomentSkewKurtosis` `Norm` `RandG`. `SumInt` pure-bash.
  Acceptance: known-dataset fixtures (mean/variance/stddev/norm); sample vs
  population variance distinction (`Variance` = n−1, `PopnVariance` = n);
  `RandG` distribution sanity (empirical mean/stddev over N draws within
  tolerance); `MomentSkewKurtosis` echoes its 6 fields.

- **P7 — Financial, RNG, IEEE predicates, FPU wontfix**
  `FutureValue` `InterestRate` `NumberOfPeriods` `Payment` `PresentValue`
  (engine; `ptEndOfPeriod`/`ptStartOfPeriod` via a `0/1` flag argument);
  `RandomRange` `RandomFrom` (pure-bash RNG); `IsNan` `IsInfinite` (token tests);
  the IEEE constant getters; FPU-control stubs (`getRoundMode` reports default,
  `setRoundMode` etc. `return 1` — wontfix). Acceptance: annuity fixtures vs FPC
  (`FutureValue`/`Payment`/`PresentValue` cross-checked); `RandomRange`
  upper-exclusive and in range; `RandomFrom` returns a member; `IsNan nan`=true.

- **P8 — Docs, README, bench, closeout**
  `docs/Math.md` (upstream FPC `Math` API reference — grouped, per-function,
  DocWiki-style, with the bash method mapping and freepascal.org reference links,
  matching the other kcl units' `docs/`); `README.md` (bash-side API by group +
  the hybrid/engine contract + conventions); `bench.sh` (core ≤0.3 ms/call &
  zero-fork **and** engine round-trip latency + a "single awk process" assertion);
  `TEST_COVERAGE_NOTES.md`; full-suite + examples sweep on 5.2, spot 5.3; close
  the ledger.

Estimated test volume: 14–18 ktest files, ≥350 checks, incl. fixtures for
rounding half-way cases, negative-argument Ceil/Floor/DivMod, angle roundtrips,
a transcendental reference grid (values captured from FPC), the sample-vs-
population statistics split, financial annuities, and NaN/Inf token handling.

### Test basis: FPC's own tests as the seed

| seed file (FPC tree) | what it pins | lands in phase |
|---|---|---|
| `tests/test/tmath1.pp` — **primary seed** | integer `div`/`mod` truncation semantics (`-10 div 5 = -2`, word/longint ranges) | P2 (`DivMod`) |
| `tests/test/units/math/troundm.pp` | FPU-rounding-mode-dependent int→float bit patterns — **confirms** that mode-dependent rounding is out of scope | P0 note / Tier-C |
| `tests/test/units/system/tround.pp` | `Round` half-to-even reference | P2 (`RoundTo`) |
| `tests/webtbs/tw*.pp` referencing `math` (tw16018, tw3005, tw3900, tw8633, tw10540, tw30299, tw37397/8, …) | mined for per-function assertions (Power/Log/Ceil/Floor/Sign/statistics) at implementation time | per function group |

**Parity model** — two tiers, matching the design:
- **Exact** (byte-for-byte) for the Tier-A integer/decimal core.
- **Tolerance** for Tier-B engine functions: a `kt_assert_near expected actual
  [reltol=1e-12]` helper (FPC `Double` has ~15–16 significant digits; `1e-12`
  relative catches real errors while absorbing the last-ulp libm differences and
  the FPC-Extended-vs-awk-Double gap). Reference values are captured verbatim
  from FPC and never "improved"; every non-FPC fixture gets a row in
  `TEST_COVERAGE_NOTES.md` (id / functions / case / why-FPC-lacks-it / basis),
  exactly as in the dateutils effort.

---

## 6. Risks / open questions

1. **`coproc` reliability on MSYS2/cygwin bash 5.2 & 5.3** — verify in P0 that the
   co-process round-trip is deadlock-free (awk `fflush()` after every answer; the
   reader uses `read -r -u`), survives many calls, and that a second `coproc` is
   never spawned. Fallback if `coproc` misbehaves on a target: a single
   long-lived `awk` fed through a FIFO pair (same one-fork property).
2. **awk flavour** — the prelude uses only POSIX-awk primitives, so `gawk`,
   `mawk`, and BusyBox awk all work; prefer `gawk` when present. `%.17g` output
   is POSIX. Detected once at spawn; absence → graceful degradation (Tier-A only).
3. **Double vs Extended parity** — FPC `Float`=`Extended` (80-bit) on i386 but
   `Double` on the x86-64 targets here; awk is `Double`. Fixtures assert against
   the **Double** result; the tolerance absorbs any Extended-only digits.
4. **RoundTo binary-vs-decimal edge** — computing `RoundTo`/`SimpleRoundTo` on a
   decimal string yields the mathematically-correct decimal result, which can
   differ from FPC's `Double`-binary result at a value not exactly representable
   in binary (e.g. classic `2.675@-2`). Documented as a known, benign divergence
   (like the dateutils JD 6-dp note); parity fixtures avoid binary-hazard values,
   with the hazard itself captured as a documented row.
5. **RNG parity** — `RandomRange`/`RandomFrom`/`RandG` can only be *semantically*
   faithful (bash `$RANDOM`/`/dev/urandom` vs FPC Mersenne). Tests assert
   range/membership/distribution, never exact draws.
6. **Engine latency budget** — the co-process is not free per call (pipe
   round-trip, ~tens of µs). It is a **cold-path** tool; hot loops must use the
   Tier-A core. `bench.sh` measures and documents both so callers can choose.
