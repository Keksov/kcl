# FPC `Math` — API Reference (kcl bash port)

This is the Free Pascal RTL **`Math`** unit API reference for the kcl
[`math`](../README.md) bash port. Every Pascal signature below is taken from the
FPC RTL source (`rtl/objpas/math.pp`); where the unit overloads
Single/Double/Extended the family is collapsed to one representative
`Float`/`Double` signature and marked *(overloaded for Single/Double/Extended)*.
Behavior, echo formats, tiers, and the FPC-Double parity notes follow the port's
[`math_ledger.json`](../math_ledger.json) and [README](../README.md), which are
authoritative for how each `math.<method>` behaves.

The port is a **hybrid** of three tiers:

- **Tier A — pure-bash, exact.** The integer/decimal core (Min/Max/Sign/ranges/
  DivMod/Ceil/Floor/compare/IfThen/SumInt/RNG/predicates) is computed in bash
  with zero forks — byte-for-byte FPC parity.
- **Tier B — the float engine.** Transcendental/float work is delegated to one
  persistent `awk` co-process (spawned lazily on the first Tier-B call). awk
  computes in C `double` = IEEE-754 binary64 = FPC `Double` on the x86-64
  targets, so results match FPC to **~1–2 ulp**; values are echoed via `%.17g`.
  With no `awk` on `PATH` the engine degrades gracefully (returns 1); the Tier-A
  core is unaffected.
- **Tier C — wontfix.** FPU/precision control has no bash analogue (see the last
  section).

Numbers echo as plain tokens; booleans echo `true`/`false`; `Sign` and
`CompareValue` echo `-1`/`0`/`1`; multi-valued results (`SinCos`, `DivMod`,
`Frexp`, `SumsAndSquares`, `MeanAndStdDev`, `MomentSkewKurtosis`) echo
space-separated fields for `read -r`; `NaN`/`±Inf` are the literal tokens
`nan`/`inf`/`-inf`. Arrays are passed as the trailing argument list — FPC's
`array of T` and the `PT + N` pointer overloads both collapse to those args.
A few elementaries the port also exposes — `Sin`, `Cos`, `Sqrt`, `Exp`, `Ln`,
`ArcTan` — are declared in FPC's **System** unit, not `Math`, and are marked
**(System)**; `feStart`/`feStop`/`feActive` are a **(kcl extension)** that
controls the engine.

---

## Constants

The port exposes the FPC `Math` constants (plus `Pi`) as zero-argument getters
that echo the backing `readonly __MATH_*` globals. `Pi`/`E` carry Extended-precision
digits. **The IEEE range constants are informational string tokens** — bash has
no native float to overflow or denormalise, so they carry no runtime effect (see
the ledger `out_of_scope`).

| kcl getter | Echoes | FPC symbol | Notes |
| --- | --- | --- | --- |
| `math.pi` | `3.1415926535897932385` | `Pi` (System) | π; the FPC `Math` unit has no `Pi` constant — it is System's `function Pi: ValReal` |
| `math.e` | `2.7182818284590452354` | — (kcl) | Euler's e = exp(1); not a named FPC symbol, a kcl convenience |
| `math.nan` | `nan` | `NaN` | the `0.0/0.0` token IsNan recognises |
| `math.infinity` | `inf` | `Infinity` | `1.0/0.0` |
| `math.negInfinity` | `-inf` | `NegInfinity` | `-1.0/0.0` |
| `math.minSingle` | `1.1754943508e-38` | `MinSingle` | informational |
| `math.maxSingle` | `3.4028234664e+38` | `MaxSingle` | informational |
| `math.minDouble` | `2.2250738585072014e-308` | `MinDouble` | informational |
| `math.maxDouble` | `1.7976931348623157e+308` | `MaxDouble` | informational |
| `math.minExtended` | `3.36210314311209350626e-4932` | `MinExtended` | informational |
| `math.maxExtended` | `1.18973149535723176502e+4932` | `MaxExtended` | informational |

**kcl:** `math.pi` / `math.e` / `math.nan` / `math.infinity` / `math.negInfinity` / `math.minSingle` … `math.maxExtended` — echo the constant · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/index-4.html)

---

## Float-engine lifecycle (kcl extension)

### `math.feStart` · `math.feStop` · `math.feActive`

```text
{ kcl extension — not part of FPC Math. Controls the Tier-B awk co-process. }
math.feStart      { start the shared engine now; 0 if up, 1 if no awk }
math.feStop       { shut the engine down }
math.feActive     { echo true/false }
```

Explicit control of the persistent `awk` float engine. The engine is spawned
**lazily** on the first Tier-B call and lives for the process, so most code never
touches these. Call `math.feStart` once (e.g. at script top) when your first
engine call happens inside a `$( … )` subshell and you want a single shared
co-process rather than a per-substitution one. `feStop` kills it (it also dies
with the shell); `feActive` reports whether it is currently running.

**kcl:** `math.feStart` — no output, status 0/1 · `math.feStop` — no output · `math.feActive` — `true`/`false` · engine control

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/index.html) (n/a — kcl extension)

---

## Min / Max determination

### `Math.Min` · `Math.Max`

```pascal
function Min(a, b: Integer): Integer; inline; overload;
function Max(a, b: Integer): Integer; inline; overload;
```

Return the smaller / larger of two operands (*overloaded for Integer/Int64/QWord/
Single/Double/Extended*). Ties return the **second** operand (`a < b ? a : b`).
The winning operand is echoed **verbatim**. Plain integers and decimals compare
fork-free via the pure-bash decimal comparator; operands in exponent/`inf`/`nan`
notation route through the engine.

**kcl:** `math.min <a> <b>` · `math.max <a> <b>` — echoes the winning operand · pure-bash (engine for exotic notation)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/min.html)

---

### `Math.MinValue` · `Math.MaxValue`

```pascal
function MinValue(const data: array of Double): Double;
function MaxValue(const data: array of Double): Double;
```

The smallest / largest element of a data set (*overloaded for Single/Double/
Extended/Integer and the `PT + N` pointer forms*). The array is the argument
list; the winning element is echoed verbatim using the same comparator as
`Min`/`Max`.

**kcl:** `math.minValue <x> <x> …` · `math.maxValue <x> <x> …` — echoes the extreme element · pure-bash (engine for exotic notation)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/minvalue.html)

---

### `Math.MinIntValue` · `Math.MaxIntValue`

```pascal
function MinIntValue(const Data: array of Integer): Integer;
function MaxIntValue(const Data: array of Integer): Integer;
```

The smallest / largest of an integer array. Pure integer arithmetic — always
exact and fork-free.

**kcl:** `math.minIntValue <int> <int> …` · `math.maxIntValue <int> <int> …` — integer · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/minintvalue.html)

---

## Ranges

### `Math.InRange` · `Math.EnsureRange`

```pascal
function InRange(const AValue, AMin, AMax: Integer): Boolean; inline; overload;
function EnsureRange(const AValue, AMin, AMax: Integer): Integer; inline; overload;
```

`InRange` tests membership in the **closed** interval `[AMin, AMax]`;
`EnsureRange` clamps the value into `[AMin, AMax]` (returns `AMin` below the
range, `AMax` above it, else the value). Both *overloaded for Integer/Int64/
Double*; comparisons are pure-bash on plain numbers.

**kcl:** `math.inRange <value> <min> <max>` — `true`/`false` · `math.ensureRange <value> <min> <max>` — clamped value · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/inrange.html)

---

## Sign & comparison

### `Math.Sign`

```pascal
function Sign(const AValue: Integer): TValueSign; inline; overload;
```

Returns the sign as `TValueSign` (`-1..1`): `-1` if negative, `0` if zero
(including `-0.0`), `1` if positive (*overloaded for Integer/Int64/Single/Double/
Extended*).

**kcl:** `math.sign <value>` — `-1`/`0`/`1` · pure-bash (engine for exotic notation)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sign.html)

---

### `Math.IsZero` · `Math.SameValue`

```pascal
function IsZero(const A: Double; Epsilon: Double): Boolean; overload;
function IsZero(const A: Double): Boolean; inline; overload;
function SameValue(const A, B: Double): Boolean; inline; overload;
function SameValue(const A, B: Double; Epsilon: Double): Boolean; overload;
```

Fuzzy float comparisons (*overloaded for Single/Double/Extended*). `IsZero`
tests `|A| <= Epsilon`, defaulting to the FPC `Double` resolution
`DZeroResolution = 1e-12`. `SameValue` tests `|A-B| <= Epsilon`, defaulting to
`Max(Min(|A|,|B|)*1e-12, 1e-12)` exactly as FPC. Both are inherently float
(Tier B); `IsZero` keeps a fork-free fast path for an integer argument with the
default epsilon. **Faithful edge:** at exactly the scaled-epsilon boundary the
binary difference can round just above `Epsilon`, so e.g. `sameValue 100 100.0000000001`
is `false`.

**kcl:** `math.isZero <value> [epsilon]` — `true`/`false` · `math.sameValue <a> <b> [epsilon]` — `true`/`false` · pure-bash fast path / engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/iszero.html)

---

### `Math.CompareValue`

```pascal
function CompareValue(const A, B: Integer): TValueRelationship; inline;
function CompareValue(const A, B: Double; delta: Double = 0.0): TValueRelationship; inline;
```

Three-way comparison returning `TValueRelationship`: `-1` (`LessThanValue`),
`0` (`EqualsValue`), `1` (`GreaterThanValue`) (*overloaded for Integer/Int64/
QWord/Single/Double/Extended*). The float overloads take an optional tolerance
`delta` (equal when `|A-B| <= delta`). Plain operands with no/zero delta compare
fork-free; a nonzero delta or exotic notation routes through the engine.

**kcl:** `math.compareValue <a> <b> [delta]` — `-1`/`0`/`1` · pure-bash (engine when delta≠0 or exotic)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/comparevalue.html)

---

### `Math.IfThen`

```pascal
function IfThen(val: boolean; const iftrue: integer; const iffalse: integer = 0): integer; inline; overload;
```

Expression-style ternary: echoes `iftrue` when the condition is truthy
(`true` or `1`), otherwise `iffalse` (default `0`) (*overloaded for integer/
int64/double*). Values are echoed verbatim, so it is type-agnostic in the port.

**kcl:** `math.ifThen <cond> <iftrue> [iffalse=0]` — echoes the chosen operand · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/ifthen.html)

---

## Rounding & number conversion

### `Math.RoundTo` · `Math.SimpleRoundTo`

```pascal
function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
function SimpleRoundTo(const AValue: Double; const Digits: TRoundToRange = -2): Double;
```

Round to a power-of-ten position `Digits` (`TRoundToRange = -37..37`; *overloaded
for Single/Double/Extended*). **`RoundTo` is banker's rounding** —
`Round(AValue/10^Digits)*10^Digits`, half-to-even — while **`SimpleRoundTo` is
arithmetic rounding** — `Int(AValue*RV ± 0.5)/RV`, `RV = 10^(-Digits)`, half away
from zero, default `Digits = -2`. The two are deliberately different. Both run in
the engine (awk `sprintf "%.0f"` is round-half-to-even, giving exact FPC-`Double`
parity). **Faithful FPC-Double edges** (binary-representation quirks, not bugs):
`roundTo 1.25 -1` → `1.2000000000000002`; `simpleRoundTo 1.005 -2` → `1.00`.

**kcl:** `math.roundTo <value> <digits>` — banker's · `math.simpleRoundTo <value> [digits=-2]` — arithmetic · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/roundto.html)

---

### `Math.Ceil` · `Math.Ceil64` · `Math.Floor` · `Math.Floor64`

```pascal
function Ceil(x: float): Integer;
function Ceil64(x: float): Int64;
function Floor(x: float): Integer;
function Floor64(x: float): Int64;
```

`Ceil` rounds toward +∞ (`Trunc(x)+ord(Frac(x)>0)`); `Floor` rounds toward −∞
(`Trunc(x)-ord(Frac(x)<0)`). Examples: `ceil -2.1` → `-2`, `floor -2.1` → `-3`,
`ceil 3` → `3`. The `…64` forms differ from the 32-bit forms only in FPC result
type; **bash has one integer domain, so `ceil64`/`floor64` are aliases** of
`ceil`/`floor`. Pure-bash via the decimal trunc/frac helpers; operands in
exponent/`inf`/`nan` notation fall back to the engine.

**kcl:** `math.ceil <x>` · `math.ceil64 <x>` · `math.floor <x>` · `math.floor64 <x>` — integer · pure-bash (engine for exotic notation)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/ceil.html)

---

### `Math.DivMod`

```pascal
procedure DivMod(Dividend: LongInt; Divisor: LongInt; var Result, Remainder: LongInt);
```

Integer division and remainder in one call (*overloaded for Word/SmallInt/DWord/
LongInt*). Truncation toward zero, with the remainder taking the **dividend's**
sign — matching Pascal `div`/`mod` and bash `/`/`%` (e.g. `-10 div 5 = -2`). The
port echoes `quotient remainder`; division by zero returns status `1` with no
output.

**kcl:** `math.divMod <dividend> <divisor>` — echoes `quot rem` (status 1 on ÷0) · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/divmod.html)

---

### `Math.FMod`

```pascal
function FMod(const a, b: Double): Double; inline; overload;
```

Floating-point modulo `a - b*Int(a/b)` (*overloaded for Single/Double/Extended*).
The result carries the sign of `a`. Engine (Tier B) — e.g. `fmod 5.3 2` → `1.3`
to Double tolerance.

**kcl:** `math.fmod <a> <b>` — remainder · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/fmod.html)

---

### `Math.IntPower`

```pascal
function IntPower(base: float; exponent: longint): float;
```

`base` raised to an **integer** `exponent` by repeated squaring. An integer base
with a non-negative exponent is exact pure-bash (`$(( base ** exponent ))`); a
float base or a negative exponent (fractional result) uses the engine. FPC's
integer `**` operator maps here; the float `**` operator maps to
[`Power`](#mathpower--mathhypot).

**kcl:** `math.intPower <base> <exp>` — `base^exp` · pure-bash (integer, exp≥0) / engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/intpower.html)

---

### `Math.Frexp` · `Math.Ldexp`

```pascal
procedure Frexp(X: double; out Mantissa: double; out Exponent: integer);
function Ldexp(X: double; p: Integer): double;
```

Inverse operations on the base-2 representation (*overloaded for Single/Double/
Extended*). `Frexp` splits `X` into a mantissa in `[0.5, 1)` and an integer
exponent such that `X = Mantissa * 2^Exponent` (echoed as `mantissa exponent`);
`Ldexp` reassembles `X * 2^p`. Round-trip: `frexp 8` → `0.5 4`, `ldexp 0.5 4`
→ `8`. Engine.

**kcl:** `math.frexp <x>` — echoes `mantissa exponent` · `math.ldexp <x> <p>` — `x·2^p` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/frexp.html)

---

## Angle conversion

### `Math.DegToRad` · `Math.RadToDeg` · `Math.GradToRad` · `Math.RadToGrad` · `Math.DegToGrad` · `Math.GradToDeg` · `Math.CycleToDeg` · `Math.DegToCycle` · `Math.CycleToGrad` · `Math.GradToCycle` · `Math.CycleToRad` · `Math.RadToCycle`

```pascal
function DegToRad(deg: float): float; inline;
function RadToDeg(rad: float): float; inline;
function GradToRad(grad: float): float; inline;
function RadToGrad(rad: float): float; inline;
function DegToGrad(deg: float): float; inline;
function GradToDeg(grad: float): float; inline;
function CycleToDeg(const Cycles: Double): Double;
function DegToCycle(const Degrees: Double): Double;
function CycleToGrad(const Cycles: Double): Double;
function GradToCycle(const Grads: Double): Double;
function CycleToRad(const Cycles: Double): Double;
function RadToCycle(const Rads: Double): Double;
```

The full interconversion set among the four angular units, where
**1 cycle = 360° = 400 grad = 2π rad** (the `Cycle*` forms are *overloaded for
Single/Double/Extended*). The port mirrors FPC's exact multiplicative factors
(`×π/180`, `×π/200`, the `200/180` rational, `×360`, `×2π`, and the reciprocal
`×(1/k)` forms where FPC uses them). All run in the engine since π is irrational
and FPC returns `Double`; round-trips agree to ~1e-12 (e.g. `degToRad 180` → π,
`radToDeg` π → `180`, `gradToDeg 200` → `180`, `cycleToDeg 1` → `360`).

**kcl:** `math.degToRad <deg>`, `math.radToDeg <rad>`, `math.gradToRad`, `math.radToGrad`, `math.degToGrad`, `math.gradToDeg`, `math.cycleToDeg`, `math.degToCycle`, `math.cycleToGrad`, `math.gradToCycle`, `math.cycleToRad`, `math.radToCycle` — converted angle · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/degtorad.html)

---

### `Math.DegNormalize`

```pascal
Function DegNormalize(deg: double): double; inline;
```

Wrap an angle in degrees into `[0, 360)`: `Deg - Int(Deg/360)*360`, `+360` if
negative (*overloaded for Single/Double/Extended*). E.g. `degNormalize -90` →
`270`, `degNormalize 450` → `90`, `degNormalize 720` → `0`. Engine.

**kcl:** `math.degNormalize <deg>` — angle in `[0,360)` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/degnormalize.html)

---

## Trigonometric

### `Math.Tan` · `Math.Cotan` · `Math.Cot`

```pascal
function Tan(x: float): float;
function Cotan(x: float): float;
function Cot(x: float): float; inline;
```

Tangent (`sin/cos`) and cotangent (`cos/sin`). `Cot` is a documented synonym of
`Cotan`; the port maps both to the same engine op. Radians in, engine out.
Identity `tan == sin/cos` holds to tolerance.

**kcl:** `math.tan <x>` · `math.cotan <x>` · `math.cot <x>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/tan.html)

---

### `Math.SinCos`

```pascal
procedure SinCos(theta: double; out sinus, cosinus: double);
```

Computes sine and cosine of `theta` together (*overloaded for Single/Double/
Extended*). The port echoes both as `sin cos` for `read -r s c`, e.g.
`sinCos <pi/6>` → `0.5 0.8660…`. Engine.

**kcl:** `math.sinCos <theta>` — echoes `sin cos` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sincos.html)

---

### `Math.Secant` · `Math.Cosecant` · `Math.Sec` · `Math.Csc`

```pascal
function Secant(x: float): float; inline;
function Cosecant(x: float): float; inline;
function Sec(x: float): float; inline;
function Csc(x: float): float; inline;
```

The reciprocal circular functions: secant `1/cos(x)` (`Secant` = `Sec`) and
cosecant `1/sin(x)` (`Cosecant` = `Csc`). Each pair maps to a single engine op.

**kcl:** `math.secant <x>` / `math.sec <x>` — `1/cos` · `math.cosecant <x>` / `math.csc <x>` — `1/sin` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sec.html)

---

### `Math.Sin` · `Math.Cos` (System)

```pascal
function Sin(d: ValReal): ValReal;   { System unit }
function Cos(d: ValReal): ValReal;   { System unit }
```

Sine and cosine of an angle in radians. These are **System-unit** elementaries,
not part of `Math`, but the port exposes them because a bash math library is
expected to have them. Engine.

**kcl:** `math.sin <x>` · `math.cos <x>` — value · engine · (System)

[FPC docs](https://www.freepascal.org/docs-html/rtl/system/sin.html)

---

## Inverse trigonometric

### `Math.ArcCos` · `Math.ArcSin`

```pascal
function ArcCos(x: Double): Double;
function ArcSin(x: Double): Double;
```

Principal inverse cosine / sine, result in radians, domain `[-1, 1]`
(*overloaded for Single/Double/Extended*). The port uses the numerically-stable
`sqrt((1-x)*(1+x))` form (`arcSin = atan2(x, sqrt((1-x)(1+x)))`,
`arcCos = atan2(sqrt((1-x)(1+x)), x)`), so `arcSin 1` → π/2, `arcCos 0` → π/2.
Engine.

**kcl:** `math.arcCos <x>` · `math.arcSin <x>` — radians · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/arccos.html)

---

### `Math.ArcTan2`

```pascal
function ArcTan2(y, x: float): float;
```

Computes `arctan(y/x)` returning an angle in the correct quadrant `(-π, π]`,
handling `x = 0`. E.g. `arcTan2 1 1` → π/4. Engine.

**kcl:** `math.arcTan2 <y> <x>` — radians · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/arctan2.html)

---

### `Math.ArcTan` (System)

```pascal
function ArcTan(d: ValReal): ValReal;   { System unit }
```

Single-argument inverse tangent, result in `(-π/2, π/2)`. A **System-unit**
elementary exposed by the port for convenience (implemented as `atan2(x, 1)`).
Engine.

**kcl:** `math.arcTan <x>` — radians · engine · (System)

[FPC docs](https://www.freepascal.org/docs-html/rtl/system/arctan.html)

---

## Hyperbolic

### `Math.Cosh` · `Math.Sinh` · `Math.Tanh`

```pascal
function cosh(x: Double): Double;
function sinh(x: Double): Double;
function tanh(x: Double): Double;
```

Hyperbolic cosine `(e^x+e^-x)/2`, sine `(e^x-e^-x)/2`, and tangent
(*overloaded for Single/Double/Extended*). `Tanh` uses FPC's robust large-|x|
formulation (`|x|>10 →` sign(x), else the `(1∓e^∓2x)/(1±e^∓2x)` form) to avoid
overflow. `cosh 0` → `1`, `sinh 0` → `0`, `tanh 0` → `0`; identity
`cosh² − sinh² = 1` holds. Engine.

**kcl:** `math.cosh <x>` · `math.sinh <x>` · `math.tanh <x>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/cosh.html)

---

### `Math.SecH` · `Math.CscH` · `Math.CotH`

```pascal
function SecH(const X: Double): Double;
function CscH(const X: Double): Double;
function CotH(const X: Double): Double;
```

The reciprocal hyperbolic functions: `SecH = 1/cosh`, `CscH = 1/sinh`,
`CotH = cosh/sinh` (*overloaded for Single/Double/Extended*). Engine.

**kcl:** `math.secH <x>` · `math.cscH <x>` · `math.cotH <x>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sech.html)

---

## Area / inverse hyperbolic

### `Math.ArcCosH` · `Math.ArcSinH` · `Math.ArcTanH` · `Math.ArCosH` · `Math.ArSinH` · `Math.ArTanH`

```pascal
function ArcCosH(x: float): float; inline;   { Delphi spelling }
function ArcSinH(x: float): float; inline;
function ArcTanH(x: float): float; inline;
function ArCosH(x: float): float;            { FK spelling }
function ArSinH(x: float): float;
function ArTanH(x: float): float;
```

The area (inverse hyperbolic) functions, provided under **both** the Delphi
`Arc*H` and the FPC `Ar*H` spellings, which are equal:
`ArcSinH = ln(x+√(x²+1))` (sign-preserving), `ArcCosH = ln(x+√((x-1)(x+1)))`
(domain `x ≥ 1`), `ArcTanH = ½·ln((1+x)/(1-x))` (domain `|x| < 1`). Round-trips
such as `arcSinH(sinh x) = x` hold to tolerance. Engine.

**kcl:** `math.arcCosH <x>` / `math.arCosH <x>` · `math.arcSinH <x>` / `math.arSinH <x>` · `math.arcTanH <x>` / `math.arTanH <x>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/arccosh.html)

---

### `Math.ArcSec` · `Math.ArcCsc` · `Math.ArcCot`

```pascal
function ArcSec(X: Double): Double;
function ArcCsc(X: Double): Double;
function ArcCot(X: Double): Double;
```

Inverse secant `arccos(1/x)`, cosecant `arcsin(1/x)`, and cotangent
(*overloaded for Single/Double/Extended*). `ArcCot` has the special case
`arcCot 0` → π/2 (else `atan2(1/x, 1)`). Engine.

**kcl:** `math.arcSec <x>` · `math.arcCsc <x>` · `math.arcCot <x>` — radians · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/arcsec.html)

---

### `Math.ArcSecH` · `Math.ArcCscH` · `Math.ArcCotH`

```pascal
function ArcSecH(X: Double): Double;
function ArcCscH(X: Double): Double;
function ArcCotH(X: Double): Double;
```

The inverse reciprocal hyperbolic functions (*overloaded for Single/Double/
Extended*): `ArcSecH = ln((1+√(1-x²))/x)`, `ArcCscH = ln(1/x+√(1/x²+1))`,
`ArcCotH = ½·ln((x+1)/(x-1))`. Engine.

**kcl:** `math.arcSecH <x>` · `math.arcCscH <x>` · `math.arcCotH <x>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/arcsech.html)

---

## Logarithmic

### `Math.Log10` · `Math.Log2` · `Math.LogN`

```pascal
function Log10(x: float): float;
function Log2(x: float): float;
function LogN(n, x: float): float;
```

Base-10, base-2, and arbitrary-base logarithms (`LogN = ln(x)/ln(n)`). E.g.
`log10 1000` → `3`, `log2 1024` → `10`, `logN 2 8` → `3`. Note the port's
argument order is **base then value** (`math.logN <base> <value>`). Engine.

**kcl:** `math.log10 <x>` · `math.log2 <x>` · `math.logN <base> <value>` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/logn.html)

---

### `Math.LnXP1` · `Math.ExpM1`

```pascal
function LnXP1(x: float): float;
function ExpM1(x: double): double;
```

Accurate-near-zero companions to `Ln`/`Exp`: `LnXP1` returns `ln(1+x)` and
`ExpM1` returns `exp(x)-1`, both preserving precision for `x ≈ 0` where the naive
forms lose it (*`ExpM1` overloaded for Double/Extended*). Verified:
`lnXP1 1e-9` → `9.9999999950e-10`, `expM1 1e-9` → `1.0000000005e-9`. Engine.

**kcl:** `math.lnXP1 <x>` — `ln(1+x)` · `math.expM1 <x>` — `exp(x)-1` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/lnxp1.html)

---

### `Math.Ln` (System)

```pascal
function Ln(d: ValReal): ValReal;   { System unit }
```

Natural logarithm. A **System-unit** elementary exposed by the port for
convenience. Engine.

**kcl:** `math.ln <x>` — natural log · engine · (System)

[FPC docs](https://www.freepascal.org/docs-html/rtl/system/ln.html)

---

## Exponential / power

### `Math.Power` · `Math.Hypot`

```pascal
function Power(base, exponent: float): float;
function Hypot(x, y: float): float;
```

`Power` raises `base` to an arbitrary **float** `exponent`: an integer exponent
is dispatched to the exact `IntPower` path, otherwise `exp(exponent*ln(base))`,
with the `exponent=0` and `base=0` special cases handled (`power 2 10` → `1024`,
`power 2 0.5` → √2). FPC's float `**` operator maps to `Power`. `Hypot` returns
`√(x²+y²)`, the length of a right-triangle hypotenuse, using overflow-safe
scaling (`hypot 3 4` → `5`; `hypot 1e200 1e200` does not overflow). Engine.

**kcl:** `math.power <base> <exp>` — `base^exp` · `math.hypot <x> <y>` — `√(x²+y²)` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/power.html)

---

### `Math.IntPower`

Integer-exponent power — see [Rounding & number conversion →
`Math.IntPower`](#mathintpower) above. FPC's integer `**` operator maps there;
the float `**` operator maps to `Power`.

**kcl:** `math.intPower <base> <exp>` — `base^exp` · pure-bash (integer, exp≥0) / engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/intpower.html)

---

### `Math.Exp` · `Math.Sqrt` (System)

```pascal
function Exp(d: ValReal): ValReal;    { System unit }
function Sqrt(d: ValReal): ValReal;   { System unit }
```

The exponential `e^x` and the square root. **System-unit** elementaries exposed
by the port for convenience. `sqrt` of a negative argument yields `nan`. Engine.

**kcl:** `math.exp <x>` — `e^x` · `math.sqrt <x>` — `√x` · engine · (System)

[FPC docs](https://www.freepascal.org/docs-html/rtl/system/exp.html)

---

## Statistical

All statistics take the data set as the trailing argument list (FPC's `array of
T` and `PT + N` forms both collapse to those args); the engine computes each in a
single `awk` pass (*overloaded for Single/Double/Extended*). `SumInt` is the one
exact pure-bash integer reducer.

### `Math.Sum` · `Math.SumInt` · `Math.Mean`

```pascal
function Sum(const data: array of double): float; inline;
function SumInt(const data: array of Int64): Int64; inline;
function Mean(const data: array of double): float; inline;
```

Arithmetic sum, integer sum, and average (`Sum/N`). `sumInt 1 2 … 10` → `55`
(exact, zero-fork); `mean 1 2 3 4` → `2.5`. `SumInt` also *overloads Integer*.

**kcl:** `math.sum <x> …` · `math.mean <x> …` — value (engine) · `math.sumInt <int> …` — integer (pure-bash)

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sum.html)

---

### `Math.SumOfSquares` · `Math.SumsAndSquares` · `Math.Norm`

```pascal
function SumOfSquares(const data: array of double): float; inline;
procedure SumsAndSquares(const data: array of Double; var sum, sumofsquares: float); inline;
function Norm(const data: array of double): float; inline;
```

`SumOfSquares` returns `Σxᵢ²`; `SumsAndSquares` returns both the sum and the sum
of squares in one pass (echoed `sum sumOfSquares`); `Norm` returns the Euclidean
L2 norm `√(Σxᵢ²)` (`norm 3 4` → `5`). Engine.

**kcl:** `math.sumOfSquares <x> …` — `Σx²` · `math.sumsAndSquares <x> …` — echoes `sum sumOfSquares` · `math.norm <x> …` — L2 norm · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/sumofsquares.html)

---

### `Math.Variance` · `Math.TotalVariance` · `Math.PopnVariance`

```pascal
function Variance(const data: array of Double): float; inline;
function TotalVariance(const data: array of Double): float; inline;
function PopnVariance(const data: array of Double): float; inline;
```

`Variance` is the **sample** variance (divisor `N-1`; `0` when `N=1`);
`PopnVariance` is the **population** variance (divisor `N`); `TotalVariance` is
the raw sum of squared deviations `Σ(xᵢ-mean)²`. Engine.

**kcl:** `math.variance <x> …` — sample (N−1) · `math.totalVariance <x> …` — Σ(x−mean)² · `math.popnVariance <x> …` — population (N) · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/variance.html)

---

### `Math.StdDev` · `Math.PopnStdDev` · `Math.MeanAndStdDev`

```pascal
function StdDev(const data: array of Double): float; inline;
function PopnStdDev(const data: array of Double): float; inline;
procedure MeanAndStdDev(const data: array of Double; var mean, stddev: float); inline;
```

`StdDev` is the **sample** standard deviation (`√` of the `N-1` variance);
`PopnStdDev` is the **population** form (`N`); `MeanAndStdDev` returns the mean
and the sample stddev together (echoed `mean stddev`). Engine.

**kcl:** `math.stdDev <x> …` — sample · `math.popnStdDev <x> …` — population · `math.meanAndStdDev <x> …` — echoes `mean stddev` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/stddev.html)

---

### `Math.MomentSkewKurtosis`

```pascal
procedure MomentSkewKurtosis(const data: array of Double; out m1, m2, m3, m4, skew, kurtosis: float); inline;
```

Computes the first four moments about the mean plus skewness and kurtosis in one
pass: `m1 = mean`, `m2/m3/m4 = (1/N)Σ(xᵢ-mean)^k`, `skew = m3/m2^1.5`,
`kurtosis = m4/m2²` (raw, not excess). The port echoes all six fields
space-separated. Engine.

**kcl:** `math.momentSkewKurtosis <x> …` — echoes `m1 m2 m3 m4 skew kurtosis` · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/momentskewkurtosis.html)

---

### `Math.RandG`

```pascal
function RandG(mean, stddev: float): float;
```

A Gaussian (normally distributed) random value with the given mean and standard
deviation, via the Marsaglia polar method (awk `srand()` seeded in the engine
prelude). Distribution parity only — the RNG stream differs from FPC's Mersenne
Twister. Engine.

**kcl:** `math.randG <mean> <stddev>` — a normal deviate · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/randg.html)

---

## Financial

```pascal
function FutureValue(ARate: Float; NPeriods: Integer; APayment, APresentValue: Float; APaymentTime: TPaymentTime): Float;
function PresentValue(ARate: Float; NPeriods: Integer; APayment, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
function Payment(ARate: Float; NPeriods: Integer; APresentValue, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
function InterestRate(NPeriods: Integer; APayment, APresentValue, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
function NumberOfPeriods(ARate, APayment, APresentValue, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
```

The standard annuity (time-value-of-money) solvers. Given an interest rate per
period, a number of periods, a periodic payment, and present/future values, each
routine solves for the remaining unknown. The port implements the FPC kernels
(`q = 1+rate`, `qⁿ = q^NPeriods`, `factor = (qⁿ-1)/(q-1)`, `×q` for
start-of-period; rate-zero linear forms; `InterestRate` by Newton iteration;
`NumberOfPeriods` via `ln(x1/x2)/ln(q)`, `→ inf` on degenerate inputs).
`APaymentTime` is a **0/1 flag**: `0 = ptEndOfPeriod` (the default), `1 =
ptStartOfPeriod` (the FPC enum `TPaymentTime = (ptEndOfPeriod, ptStartOfPeriod)`).
The five are mutually consistent (solve-for-x round-trips). Engine.

**kcl:**
`math.futureValue <rate> <n> <payment> <presentValue> [ptype=0]` ·
`math.presentValue <rate> <n> <payment> <futureValue> [ptype=0]` ·
`math.payment <rate> <n> <presentValue> <futureValue> [ptype=0]` ·
`math.interestRate <nPeriods> <payment> <presentValue> <futureValue> [ptype=0]` ·
`math.numberOfPeriods <rate> <payment> <presentValue> <futureValue> [ptype=0]` — value · engine

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/futurevalue.html)

---

## Misc (RNG)

### `Math.RandomRange` · `Math.RandomFrom`

```pascal
function RandomRange(const aFrom, aTo: Integer): Integer;
function RandomFrom(const AValues: array of Double): Double; overload;
```

`RandomRange` returns a uniform integer in the **upper-exclusive** interval
`[min(aFrom,aTo), max(aFrom,aTo))` (FPC `Random(Abs(aFrom-aTo))+Min`; *overloaded
for Integer/Int64*). `RandomFrom` returns a random element of its argument list
(*overloaded for Double/Integer/Int64*; the generic `RandomFrom<T>` is out of
scope). Both are pure-bash and zero-fork, using a 30-bit value from two
`$RANDOM` draws. Semantic parity only — the RNG stream differs from FPC.

**kcl:** `math.randomRange <from> <to>` — integer in `[min,max)` · `math.randomFrom <x> …` — a random argument · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/randomrange.html)

---

## IEEE predicates

### `Math.IsNan` · `Math.IsInfinite`

```pascal
function IsNan(const d: Double): Boolean; overload;
function IsInfinite(const d: Double): Boolean; overload;
```

Test a value for the special IEEE tokens (*overloaded for Single/Double/
Extended*). `IsNan` matches the `nan` token (e.g. the engine's `sqrt -1`);
`IsInfinite` matches `inf`/`-inf`/`infinity` (e.g. a degenerate
`numberOfPeriods`). Pure-bash regex on the token — no engine round-trip.

**kcl:** `math.isNan <value>` · `math.isInfinite <value>` — `true`/`false` · pure-bash

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/isnan.html)

---

## FPU control — out of scope (wontfix)

### `Math.GetRoundMode` · `Math.SetRoundMode` · `Math.GetPrecisionMode` · `Math.SetPrecisionMode` · `Math.GetExceptionMask` · `Math.SetExceptionMask` · `Math.ClearExceptions`

```pascal
function GetRoundMode: TFPURoundingMode;
function SetRoundMode(const RoundMode: TFPURoundingMode): TFPURoundingMode;
function GetPrecisionMode: TFPUPrecisionMode;
function SetPrecisionMode(const Precision: TFPUPrecisionMode): TFPUPrecisionMode;
function GetExceptionMask: TFPUExceptionMask;
function SetExceptionMask(const Mask: TFPUExceptionMask): TFPUExceptionMask;
procedure ClearExceptions(RaisePending: Boolean = true);
```

These manipulate the hardware **FPU control word** (rounding mode, precision
mode, exception mask, pending-exception state). **Bash and awk have no FPU
control-word access, so this whole family is wontfix** (Tier C). The port
provides stubs so callers don't break: the getters report the conventional
default (`getRoundMode` → `rmNearest`, `getPrecisionMode` → `pmDouble`,
`getExceptionMask` → `[exInvalidOp,exDenormalized,exZeroDivide,exOverflow,exUnderflow,exPrecision]`),
the setters return status `1` (no effect), and `clearExceptions` is a no-op
returning `0` (there are no pending FPU exceptions in bash). The `TFPU*` types
are likewise not modelled.

**kcl:** `math.getRoundMode` / `math.getPrecisionMode` / `math.getExceptionMask` — default token · `math.setRoundMode` / `math.setPrecisionMode` / `math.setExceptionMask` — status 1 · `math.clearExceptions` — no-op · **wontfix**

[FPC docs](https://www.freepascal.org/docs-html/rtl/math/getroundmode.html)

---

### Other out-of-scope items (from the ledger)

Beyond the FPU-control family above, the port marks these **wontfix** because
bash has a single numeric domain and no pointers or generics (see the ledger
`out_of_scope`):

- **Single / Extended precision distinct from Double** — every Single/Extended
  overload folds into the one Double-domain method; the engine works in Double
  and tolerance parity covers the Extended-only last digits.
- **`PSingle`/`PDouble`/`PExtended` + N pointer overloads** — bash has no
  pointers; the `array of T` (argument-list) shape is the single surviving form.
- **Rounding-mode-dependent int→float conversion** — the resulting bit patterns
  depend on the FPU rounding mode, which is out of scope once the FPU is.
- **IEEE range constants as operational limits** — `MinSingle`/`MaxDouble`/… are
  exposed only as informational string constants (see [Constants](#constants)).
- **generic `RandomFrom<T>`** — generics have no bash meaning; the concrete
  `RandomFrom` over the argument list covers it.
