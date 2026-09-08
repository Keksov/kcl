# math — test coverage notes

The FPC parity seed (`tests/002_FpcParity.sh`) is thin — FPC's own Math tests
cover integer `div`/`mod` (`tmath1.pp`), `Round` half-to-even (`tround.pp`) and
a scatter of `webtbs/tw*.pp` assertions, but nothing for the transcendental,
statistical or financial surface. So most of this suite is **new coverage**.

Per the project protocol, **every test case not traceable to an FPC test file
gets a row here**, classified by why FPC lacks it and by the basis for the
expected value. Gap classes:

- **boundary** — a boundary FPC's tests don't exercise;
- **bash-convention** — echo formats, `-1/0/1`, status codes, perf/shape rules;
- **representation** — bash-specific: decimal-string math, the awk float
  engine, the co-process lifecycle, NaN/Inf tokens;
- **cross-check** — Tier-B value checked against FPC Double / libm / an identity
  (tolerance `kt_assert_near`, not bit-exact).

Row format: **id** (file + label) · **functions** · **case** · **why FPC lacks
it** · **basis**.

---

## P0 — scaffolding, float engine, decimal helpers

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 001/constants | `pi` `e` `infinity` `negInfinity` `nan` `min/maxSingle/Double/Extended` | getters echo the `math.pp` constant values / tokens | representation (bash string constants; IEEE ranges informational) | `math.pp` interface literals (lines 84–98, 173–175) |
| 001/readonly | `__MATH_*` | constants reject reassignment | bash-convention (kcl house rule) | `readonly` behind the re-source guard |
| 001/dec_cmp | `_dec_cmp` | 16 pairs: trailing-zero precision (`1.5==1.50`), signed zero (`0==-0`), length-driven magnitude, fractional magnitude, negatives, cross-sign, zero-vs-tiny, >64-bit ints | representation (no native float → decimal-string comparison) | independent calculation; string compare is overflow-safe |
| 001/trunc-frac | `_trunc` `_frac` `_abs` | `trunc(-2.9)=-2`, `frac(-2.9)=-0.9`, `abs(-2.5)=2.5`, exact integers | representation (toward-zero split of a decimal string) | definition (truncate toward zero; signed fraction) |
| 001/is_int | `_is_int` | integer literals only (`42`,`-7`,`+3` yes; `3.5`,`abc`,``,`1e3` no) | bash-convention (type probe) | regex `^[+-]?[0-9]+$` |
| 001/engine-lazy | `feActive` `_fe_start` | not active until first use (0 awk at load) | representation (lazy co-process) | design; `ps` shows no awk pre-use |
| 001/engine-correctness | `_fe` (`pi sin cos tan sqrt exp ln log10 log2 atan2 pow hypot`) | 12 ops vs FPC Double within 1e-12 | cross-check (Double parity, not bit-exact) | identities (`sin(π/6)=½`, `tan(π/4)=1`, `atan2(1,1)=π/4`, `hypot(3,4)=5`) + libm |
| 001/sincos | `_fe sincos` | echoes `sin cos` as two fields | representation (multi-out via space-separated echo) | identity at `x=1` |
| 001/engine-persist | `_fe_start` (co-process) | one awk process, pid stable across REPLY calls, **reused inside `$()`** | representation (persistent `coproc`, subshell fd inheritance) | design; prototype-verified exactly-one process |
| 001/engine-load | `_fe` | 300 sequential calls, no deadlock | representation (pipe round-trip + `fflush`) | stress run |
| 001/no-awk | `_fe` `_dec_cmp` `_trunc` | empty PATH → engine returns 1, Tier-A core still works | bash-convention (graceful degradation) | design |
| 001/thin-dispatch | `math.pi` dispatcher | no capture (`__kk_static_out` / `REPLY=${`) — static-var-free | bash-convention (perf) | kcl thin-dispatch rule (cf. tfile 038) |
| 001/zero-forks | `_dec_cmp` `_frac` | correct with empty PATH | bash-convention (perf: Tier-A never forks) | empty-PATH run |
| 001/metadata | class metadata | `math_class_static_methods` lists the P0 procs | bash-convention (kklass) | kklass `build` |

## P1 — integer/decimal core

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 003/min-max | `min` `max` | integers/decimals/negatives; **FPC tie rule** `Min/Max(a,b)=b` when `a==b` (so `min 1.5 1.50`→`1.50`) | bash-convention (echoes the winning argument verbatim) | FPC `if a<b then a else b` |
| 003/minmax-value | `minValue` `maxValue` | reduce an arg list; single element; negatives | representation (array = arg list) | FPC array reducer |
| 003/int-value | `minIntValue` `maxIntValue` | integer arrays incl. all-equal | boundary (pure integer path) | FPC `MinIntValue`/`MaxIntValue` |
| 003/sign | `sign` | −1/0/1 for ints, decimals, `-0.0`, `+0` | bash-convention (echoes −1/0/1) | FPC `ord(A>0)−ord(A<0)` |
| 003/zero-fork | `min` `max` `sign` `minIntValue` | correct with empty PATH (plain operands) | bash-convention (perf: Tier-A never forks) | empty-PATH run |
| 003/exotic | `min` `max` `sign` | exponential operands (`1e-9`,`-4e5`) compare via the engine | representation (no native float in bash) | engine `cmp` (Double) |
| 004/inRange | `inRange` | closed `[min,max]`, boundaries inclusive, decimals, negatives | bash-convention (echoes true/false) | FPC `(v>=min) and (v<=max)` |
| 004/ensureRange | `ensureRange` | clamp below/above, pass-through inside | boundary | FPC clamp |
| 004/compareValue | `compareValue` | −1/0/1, ties, decimals | bash-convention (echoes −1/0/1) | FPC Less/Equal/Greater |
| 004/compareValue-delta | `compareValue` | `|a−b|<=delta`→0; outside→sign; delta 0→exact | cross-check (float tolerance → engine) | FPC `if abs(a-b)<=delta` |
| 004/ifThen | `ifThen` | true/1→iftrue; else iffalse; default iffalse=0 | bash-convention (cond as true/1) | FPC ternary |
| 004/isZero | `isZero` | default 1e-12 resolution; integer fast path; explicit eps | cross-check (float resolution → engine; int path fork-free) | FPC `Abs(A)<=eps`, `DZeroResolution=1e-12` |
| 004/isZero-forkfree | `isZero` | integer + default-eps path works with empty PATH | bash-convention (perf) | empty-PATH run |
| 004/sameValue | `sameValue` | default-eps equality (scaled) + explicit eps; boundary rounds to false | cross-check (FPC default-eps formula → engine) | FPC `Max(Min(|a|,|b|)*1e-12,1e-12)` |

## P2 — rounding & number conversion

The FPC-seeded parity assertions (`002`: `tmath1.pp` div/mod, `tround.pp`
banker's Round) are traceable to FPC test files and so are **not** listed here;
only the new-coverage cases are.

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 005/ceil | `ceil` `ceil64` | toward +∞; negatives; exact ints; tiny (`0.001`→1) | boundary | FPC `Trunc(x)+ord(Frac(x)>0)` |
| 005/floor | `floor` `floor64` | toward −∞; negatives; exact ints; tiny (`-0.001`→−1) | boundary | FPC `Trunc(x)−ord(Frac(x)<0)` |
| 005/ceil64floor64 | `ceil64` `floor64` | mirror ceil/floor (`-5.5`) | boundary (Int64 name kept) | FPC identical body |
| 005/divMod | `divMod` | `17/5`; negative-dividend rem sign; `/0`→status 1 | bash-convention (echoes "quot rem"; status code) | FPC `DivMod` (trunc toward zero) |
| 005/roundTo | `roundTo` | banker's (half-to-even): `2.5`→2, `3.5`→4, `0.5`→0 | cross-check (engine == FPC `Round`) | FPC `Round(v/10^d)*10^d` |
| 005/simpleRoundTo | `simpleRoundTo` | arithmetic (half away): `2.5`→3, `-2.5`→−3; default digits −2 | cross-check (engine) | FPC `Int(v*RV±0.5)/RV` |
| 005/fmod | `fmod` | `a−b·Int(a/b)`; remainder sign follows dividend | cross-check (engine) | FPC `FMod` |
| 005/intPower-int | `intPower` | integer exact (`2^10`, `(-2)^3`, `5^0`) — pure-bash | boundary (`$(( ** ))`) | FPC `IntPower` (squaring) |
| 005/intPower-float | `intPower` | float base (`1.5^3`), negative exp (`2^-2`) via engine | cross-check | FPC `IntPower` (squaring) |
| 005/zero-fork | `ceil` `floor` `divMod` `intPower` | Tier-A ops correct with empty PATH | bash-convention (perf) | empty-PATH run |

## P3 — angle conversions

All Tier-B engine results (`kt_assert_near`); FPC returns Double (π is irrational).

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 006/deg-rad | `degToRad` `radToDeg` | `degToRad(180)=π`, `radToDeg(π)=180`, `degToRad(90)=π/2` | cross-check (engine) | FPC `deg·(π/180)` / `rad·(180/π)` |
| 006/grad-rad | `gradToRad` `radToGrad` | `gradToRad(200)=π`, `radToGrad(π)=200` | cross-check (engine) | FPC `grad·(π/200)` / `rad·(200/π)` |
| 006/deg-grad | `degToGrad` `gradToDeg` | `180→200`, `200→180`, `90→100` | cross-check (engine) | FPC `deg·(200/180)` / `grad·(180/200)` |
| 006/cycle | `cycleToDeg` `degToCycle` `cycleToGrad` `gradToCycle` `cycleToRad` `radToCycle` | 1 cycle = 360°=400ᵍ=2π rad, both directions | cross-check (engine) | FPC `x·360`/`x·(1/360)`/`x·400`/`x·(1/400)`/`x·2π`/`x·(1/(2π))` |
| 006/degNormalize | `degNormalize` | wrap into [0,360): `-90→270`, `450→90`, `720→0`, `-730→350`, `-0.5→359.5` | cross-check (engine) | FPC `Deg−Int(Deg/360)·360`, `+360` if `<0` |
| 006/roundtrips | all | `deg→rad→deg`, `deg→grad→deg`, `deg→cycle→deg` recover the input | cross-check (engine) | inverse identity |

## P4 — trig, inverse, hyperbolic, area

All Tier-B engine results (`kt_assert_near`). π fractions given as exact Double
literals in the tests to avoid awk's `%.6g` `print` truncation.

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 007/tan-cotan | `tan` `cotan` `cot` | at π/4 = 1 | cross-check (engine) | FPC `sin/cos`, `cos/sin` |
| 007/sec-csc | `sec` `csc` `secant` `cosecant` | `1/cos`, `1/sin`; `sec(π/3)=2` | cross-check (engine) | FPC `1/cos`, `1/sin` |
| 007/sinCos | `sinCos` | echoes `sin cos` as two fields at x=1 | cross-check (multi-out) | FPC `SinCos` |
| 007/arcSin-arcCos | `arcSin` `arcCos` | principal values; stable `√((1−x)(1+x))` form | cross-check (engine) | FPC `atan2(x,√…)` / `atan2(√…,x)` |
| 007/arcTan2 | `arcTan` `arcTan2` | quadrants: `3π/4`, `−3π/4`, +y axis | cross-check (engine) | FPC `atan2` |
| 007/sin-cos-identity | `sin` `cos` `tan` | convenience + identity `tan=sin/cos` | cross-check (System elementaries) | libm + identity |
| 008/cosh-sinh-tanh | `cosh` `sinh` `tanh` | base values at 0, 1 | cross-check (engine) | FPC exp forms |
| 008/tanh-robust | `tanh` | large `\|x\|` → ±1, no overflow (100, −100, 750) | cross-check (boundary) | FPC robust `\|x\|>10→sign(x)` |
| 008/secH-cscH-cotH | `secH` `cscH` `cotH` | reciprocals of cosh/sinh/tanh | cross-check (engine) | FPC `1/cosh`, `1/sinh`, `cosh/sinh` |
| 008/cosh2-sinh2 | `cosh` `sinh` | identity `cosh²−sinh²=1` | cross-check (engine) | identity |
| 008/area | `arcSinH` `arcCosH` `arcTanH` + `ar*H` | values + Delphi/FK spelling equality | cross-check (engine) | FPC `ln` forms |
| 008/arcSec-Csc-Cot | `arcSec` `arcCsc` `arcCot` | `π/3`, `π/6`, `arcCot(0)=π/2`, `π/4` | cross-check (engine) | FPC `arccos/arcsin(1/x)`, `arctan(1/x)` |
| 008/arcSecH-roundtrip | `arcSecH` `arcCscH` `arcCotH` | values + hyperbolic round-trips | cross-check (engine) | FPC `ln` forms + inverse identity |

## P5 — logs, exponentials, powers, misc

All Tier-B engine results (`kt_assert_near`).

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 009/logs | `log10` `log2` `logN` | `log10(1000)=3`, `log2(1024)=10`, `logN(2,8)=3`, `logN(3,81)=4` | cross-check (engine) | FPC `ln(x)/ln(n)` |
| 009/ln-exp-sqrt | `ln` `exp` `sqrt` | convenience elementaries | cross-check (System elementaries) | libm |
| 009/power | `power` | integer exp exact (→intPower), fractional (`4^0.5=2`), `0^5=0`, `5^0=1` | cross-check (engine) | FPC `intPower`/`exp(e·ln b)` |
| 009/hypot | `hypot` | `3-4-5`, `5-12-13`, overflow-safe `hypot(1e200,1e200)=1.414e200` | cross-check (boundary) | FPC scaled `hypot` |
| 009/lnxp1-expm1 | `lnXP1` `expM1` | accurate near 0: `lnXP1(1e-9)=9.999999995e-10`, `expM1(1e-9)=1.0000000005e-9` (naive give the wrong `1.0000000822e-9`) | cross-check (accuracy) | FPC log1p refinement + accurate expm1 |
| 009/frexp | `frexp` | mantissa in [0.5,1), `x=m·2^e`, echoes 2 fields, negatives, 0 | cross-check (multi-out) | FPC `Frexp` |
| 009/ldexp | `ldexp` | `x·2^p` + frexp→ldexp round-trip recovers x | cross-check (engine) | FPC `Ldexp` |

## P6 — statistics

Engine stats via one awk pass over the array (`kt_assert_near`); `sumInt` is
Tier-A pure-bash. Verified against the hand-computed dataset `[2,4,4,4,5,5,7,9]`.

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 010/sum-mean | `sum` `mean` `sumOfSquares` `sumsAndSquares` | dataset totals; `sumsAndSquares` two fields | cross-check (array = arg list) | FPC `Σ`, `Σ/n`, `Σx²` |
| 010/variance | `variance` `totalVariance` `popnVariance` | sample (N−1) vs population (N); `variance([5])=0` N=1 guard | cross-check (engine) | FPC `TotalVariance/(N−1)` vs `/N` |
| 010/stddev | `stdDev` `popnStdDev` `meanAndStdDev` | `√`variance; `meanAndStdDev` two fields | cross-check (multi-out) | FPC `√Variance` |
| 010/norm | `norm` | `√(Σx²)`; 3-4-5, 5-12-13 | cross-check (engine) | FPC `sqrt(sumOfSquares)` |
| 010/moments | `momentSkewKurtosis` | 6 fields (m1..m4, skew, kurtosis), hand-verified | cross-check (multi-out) | FPC central moments; `skew=m3/m2^1.5`, `kurt=m4/m2²` |
| 010/sumInt | `sumInt` | exact integer sum; empty-PATH (zero forks) | bash-convention (Tier-A perf) | integer `Σ` |
| 010/randG | `randG` | empirical mean/stddev of 400 N(10,2) draws in tolerance | representation (RNG semantic parity only) | Marsaglia polar; distribution |

## P7 — financial, RNG, IEEE predicates, FPU stubs

Financial via the engine (`kt_assert_near`); RNG + predicates + FPU stubs are
pure-bash. Financial correctness is proven by solve-for-x round-trips.

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 011/fv-payment | `futureValue` `payment` | 5%/10-period annuity (FV 1257.79, pmt −129.50) | cross-check (engine) | FPC annuity formulas |
| 011/roundtrips | `payment` `presentValue` `interestRate` `numberOfPeriods` | solve-for-x mutual consistency (recover PV 1000, rate 0.05, N 10) | cross-check (engine + Newton) | inverse consistency |
| 011/rate0 | `futureValue` `payment` `presentValue` | `rate=0` linear branches | boundary | FPC `rate=0` branch |
| 011/ptype | `futureValue` | start-of-period FV = end-of-period × q | cross-check (engine) | FPC `APaymentTime` flag |
| 012/randomRange | `randomRange` | `[min,max)` upper-exclusive; reversed args; degenerate `from==to` | representation (RNG semantic) | FPC `Random(Abs(from-to))+Min` |
| 012/randomFrom | `randomFrom` | always returns a member; single element | representation (RNG semantic) | FPC `RandomFrom` |
| 012/predicates | `isNan` `isInfinite` | nan/±inf tokens + engine `sqrt(-1)`/degenerate `numberOfPeriods` | bash-convention (token tests) | FPC `IsNan`/`IsInfinite` |
| 012/fpu-stubs | `getRoundMode`…`clearExceptions` | getters report a default, setters return 1 | bash-convention (wontfix stub) | Tier-C wontfix |
| 012/zero-fork | `randomRange` `randomFrom` `isNan` `isInfinite` | correct with empty PATH | bash-convention (perf) | empty-PATH run |

**Engine hardening (P7)** — the plan's risk #1 materialized: cygwin (bash 5.3)
truncates the now-8.4 KB awk program when passed as a command-line argument,
corrupting it and killing the co-process. Fix: feed it via `awk -f <tempfile>`
with a probe + `TMPDIR→MATH_DIR→/tmp` fallback (some setups resolve `/tmp`
differently for bash vs the native awk; `MATH_DIR` is a real path both agree on).
Two bash-syntax traps were also hit and fixed: `}#comment` glued with no space
(the `}` never closes the group) and an unquoted `(a|b)` regex inside `[[ =~ ]]`
(parsed as conditional grouping) — both now use a space / a regex variable.

## Corrections to the plan

| # | plan said | actual (faithful) | basis |
|---|---|---|---|
| 1 | P1 is entirely "pure-bash, exact, zero-fork" (with `isZero`/`sameValue` under it) | `isZero`/`sameValue` are inherently FLOAT (FPC default eps `1e-12` for `isZero`; `sameValue` eps `Max(Min(|a|,|b|)·1e-12, 1e-12)`), so they run on the **engine** (Tier B), not Tier-A-zero-fork. `isZero` keeps a fork-free integer + default-eps fast path; `compareValue`'s delta form is engine-backed too. The rest of P1 stays Tier-A zero-fork. | FPC `math.pp` `IsZero`/`SameValue` (3474–3518, 3628–3681) |
| 2 | P2.2 rounding is "pure-bash decimal" | `roundTo`/`simpleRoundTo` (and `fmod`) run on the **engine** (Tier B): awk's `sprintf "%.0f"` is round-half-to-even, identical to FPC `Round`, so parity is EXACT to the FPC Double. A pure-bash decimal rounder would be mathematically clean but **diverge** from FPC at binary-hazard values — engine chosen for faithfulness. `ceil`/`floor`/`divMod`/integer-`intPower` stay Tier-A pure-bash. | FPC `math.pp` `RoundTo`/`SimpleRoundTo` (3872–3950) |

**Documented FPC-Double edges** (faithful results, not bugs — the operands aren't
binary-exact): `roundTo(1.25,-1)` → `1.2000000000000002`; `simpleRoundTo(1.005,-2)`
→ `1.00` (since `1.005·100` = `100.4999…`). Parity fixtures use `kt_assert_near`.

**Running class breakdown** (final): boundary 7 · bash-convention 19 ·
representation 11 · cross-check 43 · **total 80** (P0 14 + P1 14 + P2 10 + P3 6 +
P4 13 + P5 7 + P6 7 + P7 9).

## Finalization (P8)

**Suite**: 81 tests across 12 files (`001`–`012`). The `002_FpcParity` checks are
FPC-test-seeded (`tmath1.pp` div/mod, `tround.pp` banker's `Round`); the other 80
are new coverage, each rowed above.

**Surface**: 123 public methods — Tier A pure-bash/zero-fork (min/max/sign/
ranges/divMod/ceil/floor/compareValue/ifThen/sumInt/randomRange/randomFrom/
isNan/isInfinite/constants/FPU-stubs, integer intPower & isZero), Tier B engine
(all transcendental + rounding + statistics + financial + angle), Tier C wontfix
(7 FPU-control stubs).

**Performance** (`bench.sh`, bash 5.2): Tier-A integer core 0.04–0.12 ms/call — a
bench-driven integer fast-path was added to `_num_cmp` (arithmetic compare for
64-bit integers, ~2–4× faster than the decimal split); decimal-operand
comparison ~0.2–0.4 ms (pure-bash decimal split, fork-free); Tier-B engine
0.13–0.18 ms/call pipe round-trip; zero forks on Tier-A (empty-PATH verified);
exactly one awk co-process reused across calls.

**Notes for further analysis**:
- Engine values print full-precision `Double` (`%.17g`) and may show trailing
  noise (`log10(1000)=2.9999999999999996`) — faithful; compare with tolerance.
- `RoundTo`/`SimpleRoundTo` on binary-non-representable decimals match FPC's
  `Double` result, not the mathematically-exact decimal (documented edges).
- RNG (`randomRange`/`randomFrom`/`randG`) is semantic-parity only (bash/awk vs
  FPC Mersenne).
- A statistics array passes through the request pipe as one line — fine for
  hundreds of elements; a very large array would need chunking.

---

## 013 — the kcl contract (P1, 2026-09-06)

| ID | Functions | Case | Class |
|---|---|---|---|
| 013.parse | — | `bash -n` on the unit + no unterminated `printf '` format | integrity |
| 013.setu | all | loads, RE-loads and runs its main path under `set -eu` | contract |
| 013.inj | divMod/sumInt/minIntValue/maxIntValue/randomRange | an injection-shaped index never reaches `(( ))` (canary file) | security |
| 013.octal | min/sumInt/minIntValue | `08`/`09` are decimal, not octal | contract |
| 013.sete | min/max/sign/compareValue/divMod | Tier-A helpers do not abort the caller under `set -e` | contract |

## 014 — the engine never dies (P7, 2026-09-08 — M1, M2, M5, M11, M14)

Every domain row asserts the value AND that the co-process is the same live
process afterwards AND that the next call is still right: a dead engine used to
answer `''` with rc 0, which is invisible in the failing call itself.

| ID | Functions | Case | Class |
|---|---|---|---|
| 014.domain | 43 rows across fmod, cotan/cot/csc/cosecant, cscH/cotH, arcSec/arcCsc, arcSecH/arcCscH/arcCotH, arcTanH/arTanH, logN, log10/log2/ln, sqrt, exp, power, intPower, roundTo, simpleRoundTo, mean/variance/popnVariance/totalVariance/stdDev/popnStdDev/sum/sumOfSquares/norm, payment, numberOfPeriods, presentValue, ldexp, lnXP1, arcSin/arcCos/arcCosH | every zero denominator the prelude can be asked for: the FPC/IEEE value + the engine still alive | contract (M1/R11) |
| 014.tokens | max/min/sign/isZero/sameValue/ceil/floor/compareValue/inRange/ensureRange/maxValue | the unit's own `inf`/`nan` tokens are VALUES, not zeros; the FPC rule for an unordered operand in each member | behavior (M5) |
| 014.predicates | isNan/isInfinite | what the engine emits feeds the predicates back | behavior (M5) |
| 014.frexp | frexp | `+inf`/`inf`/`-inf`/`nan`/`1e308`/`0`/`-8`/`0.75`/denormal/smallest-normal — all answer, under `timeout` | contract (M2) |
| 014.negzero | roundTo/simpleRoundTo/ceil/floor/fmod/sign/degNormalize/logN | no `-0` on any rounding path | behavior (M11) |
| 014.garbage | 20 members x 9 shapes (`abc`, `0x10`, `1 2`, `''`, `1.2.3`, `-`, `+-5`, `1e`, an injection) | rc 1 + `RESULT=''` + no output | security (M14) |
| 014.newline | sin/mean/roundTo | a newline argument is rejected BEFORE the write and the pipe stays in step | contract (M3) |
| 014.prelude | — | structurally: the awk program divides only through the guarded helper | integrity (M1) |

## 015 — engine protocol and process lifecycle (P7 — M3, M6, M9, M10, M15)

| ID | Functions | Case | Class |
|---|---|---|---|
| 015.desync | sin/cos/sqrt | after a newline argument the NEXT three answers are still correct | contract (M3) |
| 015.desync-shapes | sin/cos | space, tab, empty, multi-value arguments each leave the pipe in step | contract (M3) |
| 015.desync-stats | mean | a rejected element does not eat the next answer | contract (M3) |
| 015.tempfile | sin/roundTo | a child shell that used the engine leaves NO `.math_fe_*.awk` behind | contract (M6) |
| 015.tempfile-trap | sin | the same when the caller has its own EXIT trap — which still runs | contract (M6) |
| 015.lazy | min/divMod | a shell that never touches Tier B starts no engine at all | behavior (M6) |
| 015.respawn | feStop/sin | 5 restarts, empty stderr (no `execute_coproc` warning) | contract (M9) |
| 015.killed | sin/cos/sqrt | an engine killed from outside is replaced silently and answers correctly | contract (M9/R11) |
| 015.noawk | 22 Tier-B members | `PATH=` → rc 1, silent, `RESULT=''`; `feStart`/`feActive` rc 1 | contract (M10) |
| 015.noawk-tiera | min/max/sign/divMod/sumInt/ceil/intPower | the Tier-A core still answers exactly with no awk | contract (M10) |
| 015.locale | sin/mean/roundTo | `de_DE.UTF-8`, `de_DE.UTF-8`+`POSIXLY_CORRECT`, `LC_NUMERIC=de_DE`, empty env → C-decimal output | contract (M15) |
| 015.comma | sin/min | a comma-decimal argument is REJECTED, not truncated | contract (M14/M15) |
| 015.one-process | sin/sqrt/feActive | one co-process serves 200 calls and every `$( )` subshell | behavior (R11) |

## 016 — the return contract (P7 — D3, R8, M12)

| ID | Functions | Case | Class |
|---|---|---|---|
| 016.silent | 19 members | a direct call prints nothing on stdout or stderr and sets `RESULT` | contract (D3) |
| 016.captured | 10 members | inside `$( )` the value is printed EXACTLY once | contract (D3) |
| 016.bool | inRange/isZero/sameValue/isNan/isInfinite/feActive | 14 rows: the exit status IS the answer, `RESULT` carries the word | contract (R8) |
| 016.bool-sete | inRange/isNan/isZero | usable from `if` / `\|\|` / `!` under `set -eu` | contract (R8, D7) |
| 016.ifthen | ifThen | an EXPLICIT empty argument is a value; an absent one still defaults to 0 | behavior (M12) |
| 016.echo-opts | ifThen/randomFrom | `-n`, `-e`, `-E`, `-neE` round-trip verbatim both ways | contract (X-ECHO) |
| 016.errors | 12 error rows | rc != 0, `RESULT` CLEARED, nothing printed | contract (§1.2) |
| 016.forkfree | 18 Tier-A members | `BASHPID` unchanged across a direct call | perf (§1.8) |
| 016.nosubst | 27 Tier-A bodies | no `$( )` or backtick in any body | perf (§1.8) |
| 016.complete | every declared member | the interface is read from the source: all 123 are on the return contract | completeness |

## 017 — integer overflow and the RNG (P7 — M8, M13)

| ID | Functions | Case | Class |
|---|---|---|---|
| 017.ipow-exact | intPower | 9 rows exact inside int64 (`2^62`, `-2^63`, `10^18`, `0^0`, …) | behavior (M8) |
| 017.ipow-float | intPower | 7 rows past int64 answer the FPC Double, not a wrap | behavior (M8) |
| 017.sumint | sumInt | exact below the boundary, Double above, in both directions | behavior (M8) |
| 017.rng-bounds | randomRange | 2000 draws inside `[lo,hi)` | behavior (M13) |
| 017.rng-wide | randomRange | a 2^40 span reaches BOTH halves (the old 30-bit draw could not) | behavior (M13) |
| 017.rng-uniform | randomRange | 8 buckets over 4000 draws on `n = 3*2^28`, each within 2x of its share | behavior (M13) |
| 017.rng-edges | randomRange | equal, reversed, negative and straddling bounds; upper end exclusive | behavior (M13) |
| 017.rng-overflow | randomRange | a span wider than int64 is rc 1; the maximal legal span is accepted | contract (M13) |
| 017.randomfrom | randomFrom | every element of a 5-element list is reachable | behavior (M13) |
| 017.rng-fork | randomRange/randomFrom | fork-free, no command substitution | perf (§1.8) |
