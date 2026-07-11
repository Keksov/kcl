# math — Free Pascal `Math` for bash (kcl)

A bash port of FPC's `Math` unit as a kcl [kklass](../../kklass) Pascal-DSL
**static utility class**: 123 public methods called as `math.<Method>`.

FPC's `Math` is ~80% floating point, and bash has no float type, so the port is
**hybrid** — see [PLAN.md](PLAN.md) for the full rationale:

| Tier | What | How |
|---|---|---|
| **A** — integer/decimal core | `min` `max` `sign` `inRange` `ensureRange` `divMod` `ceil` `floor` `compareValue` `ifThen` `sumInt` `randomRange` `randomFrom` `isNan` `isInfinite`, integer `intPower` | **pure bash, zero forks, exact** FPC parity, ≤0.3 ms/call |
| **B** — transcendental | all trig / hyperbolic / log / exp / power / statistics / financial / angle conversions / rounding | delegated to a persistent **`awk` float engine** — matches FPC `Double` to ~1–2 ulps |
| **C** — FPU / precision control | `get/setRoundMode`, `…ExceptionMask`, Single/Extended distinctions | **wontfix** — no bash equivalent (stubs provided) |

```bash
source /path/to/kcl/math/math.sh

math.min 3 7                 # 3            (pure bash, exact)
math.roundTo 2.5 0           # 2            (banker's rounding, engine)
math.hypot 3 4               # 5
math.mean 2 4 4 4 5 5 7 9    # 5
math.futureValue 0.05 10 -100 0   # 1257.789253554882   (annuity)
read -r s c <<< "$(math.sinCos 1.0)"   # s=sin(1) c=cos(1)
```

## The float engine

Everything Tier B runs on **one persistent `awk` co-process**, started lazily on
the first transcendental call and kept alive for the process. Each call is a
pipe round-trip (no fork per call); `awk` computes in C `double`s — the same
IEEE-754 binary64 FPC uses for `Double` on the x86-64 targets.

- **Persistence across `$(…)`**: a `$( math.sin … )` subshell reuses a
  parent-started engine. If the *first* engine call is itself inside `$( )`,
  the engine lives only for that substitution — call **`math.feStart`** once
  (e.g. at the top of a script) to guarantee a single shared engine.
- **`math.feActive`** → `true`/`false`; **`math.feStop`** shuts it down.
- **No `awk`?** Tier-B calls return non-zero (a debug message under
  `VERBOSE_KKLASS=debug`); the entire Tier-A core still works.
- The engine program is fed via `awk -f <tempfile>` (a large program passed as a
  command-line argument is truncated on cygwin); the temp file is auto-cleaned.

## Conventions

| Result kind | How it is returned |
|---|---|
| number | echoed as a token; engine results use `%.17g` (round-trippable `Double`, may show trailing noise like `2.9999999999999996`) |
| Boolean | `true` / `false` |
| `Sign` / `CompareValue` | `-1` / `0` / `1` |
| multi-value (`sinCos` `divMod` `frexp` `sumsAndSquares` `meanAndStdDev` `momentSkewKurtosis`) | space-separated fields, read with `read -r a b …` |
| `NaN` / `±Inf` | the literal tokens `nan` / `inf` / `-inf` |
| arrays (`mean` `sum` `norm` …) | passed as the **argument list**: `math.mean 1 2 3 4` |
| `TPaymentTime` (financial) | a `0`/`1` flag: `0` = end-of-period (default), `1` = start |
| errors (bad args, `divMod` by 0) | `return 1`, echo nothing |

**Parity**: Tier-A results are exact; Tier-B results match FPC `Double` within
~1–2 ulps (compare with a tolerance, e.g. the tests' `kt_assert_near`).

---

## Constants

`pi` `e` `infinity` `negInfinity` `nan` and the IEEE range constants
`minSingle` `maxSingle` `minDouble` `maxDouble` `minExtended` `maxExtended`
(informational — bash cannot over/underflow a native float). All are `static
proc` getters over `readonly __MATH_*` globals.

## Min / Max, ranges, sign & comparison (Tier A)

| Signature | Echoes |
|---|---|
| `min <a> <b>` · `max <a> <b>` | the smaller / larger operand (ties → 2nd, per FPC) |
| `minValue <x…>` · `maxValue <x…>` | min / max of the argument list |
| `minIntValue <n…>` · `maxIntValue <n…>` | integer-array min / max |
| `sign <x>` | `-1` / `0` / `1` |
| `inRange <v> <min> <max>` | true/false (closed interval) |
| `ensureRange <v> <min> <max>` | `v` clamped into `[min,max]` |
| `compareValue <a> <b> [delta]` | `-1`/`0`/`1` (with optional float tolerance → engine) |
| `isZero <x> [eps]` | true/false (`\|x\| ≤ eps`, default `1e-12`; integer path is fork-free) |
| `sameValue <a> <b> [eps]` | true/false (default eps `Max(Min(\|a\|,\|b\|)·1e-12, 1e-12)`) |
| `ifThen <cond> <ifTrue> [ifFalse=0]` | `ifTrue` if `cond` is `true`/`1`, else `ifFalse` |

## Rounding & number conversion

| Signature | Echoes | Tier |
|---|---|---|
| `ceil <x>` · `ceil64 <x>` · `floor <x>` · `floor64 <x>` | integer toward ±∞ | A |
| `divMod <a> <b>` | `quotient remainder` (Pascal `div`/`mod`; `/0` → status 1) | A |
| `intPower <base> <exp>` | `base^exp` (integer base+exp≥0 exact; else engine) | A/B |
| `roundTo <x> <digits>` | banker's rounding (half-to-even) | B |
| `simpleRoundTo <x> [digits=-2]` | arithmetic rounding (half away from zero) | B |
| `fmod <a> <b>` | `a − b·trunc(a/b)` | B |

## Angle conversions (Tier B)

`degToRad` `radToDeg` `gradToRad` `radToGrad` `degToGrad` `gradToDeg`
`cycleToDeg` `degToCycle` `cycleToGrad` `gradToCycle` `cycleToRad` `radToCycle`
(1 cycle = 360° = 400ᵍ = 2π rad) · `degNormalize <deg>` → `[0,360)`.

## Trigonometry, inverse, hyperbolic, area (Tier B)

| Group | Functions (take radians) |
|---|---|
| circular | `tan` `cotan` `cot` `sinCos` (→`sin cos`) `sec` `csc` `secant` `cosecant` |
| inverse | `arcSin` `arcCos` `arcTan2 <y> <x>` |
| hyperbolic | `cosh` `sinh` `tanh` `secH` `cscH` `cotH` |
| area (inv. hyp.) | `arcCosH` `arcSinH` `arcTanH` · `arCosH` `arSinH` `arTanH` (FK spellings) · `arcSec` `arcCsc` `arcCot` · `arcSecH` `arcCscH` `arcCotH` |
| convenience | `sin` `cos` `arcTan` (System-unit elementaries, exposed for ergonomics) |

## Logs, exponentials, powers (Tier B)

`log10` `log2` `logN <base> <x>` · `lnXP1 <x>` (accurate `ln(1+x)` near 0) ·
`expM1 <x>` (accurate `exp(x)-1` near 0) · `power <base> <exp>` ·
`hypot <x> <y>` (overflow-safe) · `frexp <x>` (→`mantissa exponent`, mantissa in
`[0.5,1)`) · `ldexp <x> <p>` (`x·2^p`) · convenience `sqrt` `exp` `ln`.

## Statistics

Arrays are the argument list. `sumInt` is Tier-A (pure integer); the rest are
engine (one awk pass each).

| Signature | Echoes |
|---|---|
| `sum <x…>` · `sumInt <n…>` · `mean <x…>` | sum / integer sum / mean |
| `sumOfSquares <x…>` · `sumsAndSquares <x…>` | `Σx²` / `sum sumOfSquares` |
| `variance <x…>` · `totalVariance <x…>` · `popnVariance <x…>` | sample (n−1) / `Σ(x−μ)²` / population (n) |
| `stdDev <x…>` · `popnStdDev <x…>` · `meanAndStdDev <x…>` | `√variance` / `√popnVariance` / `mean stddev` |
| `momentSkewKurtosis <x…>` | `m1 m2 m3 m4 skew kurtosis` |
| `norm <x…>` | euclidean L2 = `√Σx²` |
| `randG <mean> <stddev>` | one Gaussian draw (Marsaglia polar) |

## Financial (annuities, Tier B)

`APaymentTime` is a `0`/`1` flag (`0` = end-of-period default, `1` = start).

| Signature |
|---|
| `futureValue <rate> <n> <payment> <presentValue> [ptype]` |
| `presentValue <rate> <n> <payment> <futureValue> [ptype]` |
| `payment <rate> <n> <presentValue> <futureValue> [ptype]` |
| `interestRate <n> <payment> <presentValue> <futureValue> [ptype]` (Newton) |
| `numberOfPeriods <rate> <payment> <presentValue> <futureValue> [ptype]` |

## RNG & IEEE predicates (Tier A)

| Signature | Echoes |
|---|---|
| `randomRange <from> <to>` | uniform integer in `[min,max)` (upper-exclusive) |
| `randomFrom <x…>` | a random element of the arguments |
| `isNan <x>` · `isInfinite <x>` | true/false (test the `nan` / `±inf` tokens) |

RNG parity is semantic only (bash `$RANDOM` vs FPC's Mersenne generator).

## Out of scope (wontfix)

FPU control has no bash equivalent — `getRoundMode` (→ `rmNearest`),
`getPrecisionMode` (→ `pmDouble`), `getExceptionMask` are informational stubs;
`setRoundMode`/`setPrecisionMode`/`setExceptionMask` **return 1**;
`clearExceptions` is a no-op. Also wontfix: the Single/Extended precision
distinctions (the engine is `Double`), the `PT+N` pointer-array overloads (the
port takes an argument list), `generic RandomFrom<T>`, and the FPU-rounding-mode-
dependent integer→float conversion. See [PLAN.md](PLAN.md) §4.

---

- Upstream API reference: [docs/Math.md](docs/Math.md)
- Design & rationale: [PLAN.md](PLAN.md) · status: [math_ledger.json](math_ledger.json)
- Test-coverage analysis: [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)
- Micro-benchmark: [bench.sh](bench.sh)
