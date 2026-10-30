# math — Free Pascal `Math` for bash (kcl)

A bash port of FPC's `Math` unit as a kcl [kklass](https://github.com/Keksov/kklass/tree/main) Pascal-DSL
**static utility class**: 123 public methods called as `math.<Method>`.

FPC's `Math` is ~80% floating point, and bash has no float type, so the port is
**hybrid** — see [PLAN.md](../docs/dev/math/PLAN.md) for the full rationale:

| Tier | What | How |
|---|---|---|
| **A** — integer/decimal core | `min` `max` `sign` `inRange` `ensureRange` `divMod` `ceil` `floor` `compareValue` `ifThen` `sumInt` `randomRange` `randomFrom` `isNan` `isInfinite`, integer `intPower` | **pure bash, zero forks, exact** FPC parity, ≤0.25 ms/call (see *Cost*) |
| **B** — transcendental | all trig / hyperbolic / log / exp / power / statistics / financial / angle conversions / rounding | delegated to a persistent **`awk` float engine** — matches FPC `Double` to ~1–2 ulps |
| **C** — FPU / precision control | `get/setRoundMode`, `…ExceptionMask`, Single/Extended distinctions | **wontfix** — no bash equivalent (stubs provided) |

```bash
source /path/to/kbool/kbool.sh
kk.uses math

math.min 3 7;               echo "$RESULT"   # 3     (pure bash, exact)
math.roundTo 2.5 0;         echo "$RESULT"   # 2     (banker's rounding, engine)
math.hypot 3 4;             echo "$RESULT"   # 5
math.mean 2 4 4 4 5 5 7 9;  echo "$RESULT"   # 5
math.futureValue 0.05 10 -100 0              # RESULT = 1257.789253554882
read -r s c <<< "$(math.sinCos 1.0)"         # s=sin(1) c=cos(1)

if math.inRange "$v" 0 100; then ... fi      # predicates answer with rc
```

## The return contract

Every member is a `static proc` on the kcl contract
([`kcl/README.md`](../README.md) §1.1): it answers through **`RESULT`** and
**prints nothing** on a direct call; inside `$( )` it prints its value exactly
once. Before P7 the unit echoed on every call, so every use of a result cost a
fork (15–23 ms on a large shell against ~0.12 ms for the direct call).

```bash
math.sqrt 2                  # prints NOTHING; RESULT = 1.4142135623730951
v="$(math.sqrt 2)"           # prints once inside the subshell
```

| | |
|---|---|
| value | `RESULT`, and stdout under `$( )` |
| **predicate** (`inRange` `isZero` `sameValue` `isNan` `isInfinite` `feActive`) | the **exit status** is the answer; `RESULT` also carries `true`/`false` (R8) |
| error (bad argument, `divMod` by 0, no engine) | **rc 1**, `RESULT=""`, nothing printed on stdout **or** stderr |

Under `set -e` a bare `math.isZero 1` aborts the caller — that is bash's rule
for every command, so call predicates from an `if`, a `&&`/`||` or a `!`.

## The float engine

Everything Tier B runs on **one persistent `awk` co-process**, started lazily on
the first transcendental call and kept alive for the process. Each call is a
pipe round-trip (no fork per call); `awk` computes in C `double`s — the same
IEEE-754 binary64 FPC uses for `Double` on the x86-64 targets.

- **Persistence across `$(…)`**: a `$( math.sin … )` subshell reuses a
  parent-started engine. If the *first* engine call is itself inside `$( )`,
  the engine lives only for that substitution — call **`math.feStart`** once
  (e.g. at the top of a script) to guarantee a single shared engine.
- **`math.feActive`** → rc 0/1 (`RESULT` = `true`/`false`); **`math.feStop`**
  shuts it down and removes anything it left behind.
- **No usable `awk`?** A Tier-B member is **rc 1 + `RESULT=""` + silence**;
  the entire Tier-A core still works. The reason of the last failed start is
  in **`MATH_FE_ERROR`** (`""` after a successful start) and, under
  `VERBOSE_KKLASS=debug`, on stderr as one line
  `math: float engine not started: <reason>`:

  ```
  no awk: neither gawk nor awk is on PATH
  awk (/usr/bin/awk, mawk 1.3.4 20240123) cannot run the engine: with -W interactive no answer within 10 s; without it no answer within 10 s
  awk (/usr/bin/awk, …) cannot run the engine: with -W interactive exited before answering; without it exited before answering
  ```

  The second form names the awk (where `command -v` finds it — a path, or
  just the name when `awk` is a shell function — and the first line of its
  `-W version`) and says, per start, whether it *exited* (it rejected a flag,
  could not read or parse the program) or stayed *silent* (block-buffered
  input, or wedged) — a silent try costs the start timeout (10 s).
- **A failed start is not retried by every call.** While `MATH_FE_ERROR` is
  set, a Tier-B member answers rc 1 at once instead of starting the engine
  again (each failed start can cost two start timeouts). **`math.feStart`**
  always tries again — after installing an awk or fixing `PATH`, call it once;
  a successful start clears `MATH_FE_ERROR` (so does clearing it yourself).
- **The co-process is the awk itself** (`exec`): `math.feStop`, and a call
  that times out under `__MATH_FE_STRICT`, kill the awk, also a wedged one
  that no longer reads its input. (An `awk`/`gawk` shell *function* — a test
  shim — cannot be exec'd and runs in the co-process's subshell as before.)
- The program reaches awk through **process substitution** (`awk -f <(…)`), so
  nothing is written to disk. Both bashes here were probed and keep the
  substitution alive for the co-process's lifetime; if it ever fails, the code
  falls back to a temp file plus an `EXIT` trap that **chains** the caller's own
  handler instead of replacing it. Either way a process that used the engine
  leaves no `/tmp/.math_fe_*.awk` behind. A process KILLED by a signal runs no
  EXIT trap (bash 5.2), so on the fallback path an engine start first removes
  the `.math_fe_<pid>.awk` files of dead processes in the folder it writes to
  (only that name shape, a regular file, a pid that is not alive, and older
  than 5 minutes — a younger one may be another MSYS runtime's engine starting
  right now; ktests round 5, DE1 / review R3). A drive-letter folder (`C:/…`,
  `C:\…`) is swept like any absolute one (review round 2, N2).

### Which awk (engine requirements)

| awk | status |
|---|---|
| **gawk** | preferred: when `command -v gawk` finds one, the engine runs on it (no extra flags) — the awk it was developed against (Windows Git-bash/MSYS2, Fedora; installable everywhere) |
| **mawk** (`awk` on Debian/Ubuntu) | supported when there is no gawk: started as `awk -W interactive` (mawk reads a pipe in blocks and answers nothing without it). One limit: mawk 1.3.4 20240123 (Ubuntu 24.04) then reads a request through a 4096-byte buffer and never answers a request of 4096 characters or more — the newline not counted: 4095 characters plus the newline (4096 bytes) is the longest that answers. So on such a mawk a request of more than **4095 characters** is refused with rc 1 at once instead of hanging (`__MATH_FE_LINEMAX`); in practice a statistics call (`mean`, `stdDev`, …) over more than ~200 full-precision values. mawk 1.3.4 20250131 (Debian 13) has no such limit (a 360005-character request answered) and gets none. mawk 20250131 reads the operands `+nan` `-nan` `+inf` `-inf` as 0 and `-0` (that spelling only; `-0.0` `-.0` `-0.` `-0e0` `-00` read as -0) as +0; the engine rewrites those operands itself, so the answers do not change. Probed on mawk 1.3.4 20240123 (Ubuntu 24.04) and 20250131 (Debian 13) |
| any other `awk` | started with `-W interactive` first; one that rejects the flag exits at once and is restarted without it. **busybox awk** with math (Alpine 3.24, BusyBox v1.37.0, the `awk` of the `clean` system): runs the engine — it ignores `-W` with a warning, answers line by line, has no line limit (a 360005-character request answered) and gets none; `tests/` 197 rows: 195 pass, the 2 rows of `018` fail only because busybox `touch -d '10 minutes ago'` is not supported (probed 2026-10-22). busybox awk on Debian/Ubuntu is built **without math** (`Math support is not compiled in`) and cannot run the engine. **BWK awk** (one-true-awk: FreeBSD, macOS; probed on FreeBSD 15.1, `awk version 20250804`, the `awk` of the `clean` system): runs the engine — `-W` is not an option to it (it takes `interactive` for its program and exits), so the engine is restarted on plain `awk`, which answers a pipe line by line (no `__MATH_FE_LINEMAX` is set for it). BWK awk stores every computed `-0` as `+0` but reads an operand `-0` as -0, so the engine rewrites a `-0` operand only on an awk whose own -0 is negative (`math.arcTan2 0 -0` is pi on BWK too). BWK awk reads a nonzero operand of magnitude below 2.2250738585072014e-308 (a subnormal) as 0; results that are subnormal are computed correctly (`math.frexp 5e-324` answers `0 0` on BWK, `0.5 -1073` elsewhere; `tests/014` expects that by the engine's awk). macOS's BWK is not probed |

The 4095-character limit is applied only to a mawk that has it: when plain
`awk` answers under `-W interactive`, its `-W version` is read once (one
fork per awk name + `PATH` and process, cached; never when gawk starts). The
limit is set when that line starts with `mawk` **and** the date after the
version (`mawk 1.3.4 20240123`) is before **20250131**, or cannot be read
(unknown counts as limited, the safe side); mawk 20250131 and later get no
limit. Another awk that merely accepts the flag (busybox, a gawk installed
as `awk`) gets none either.

The prelude does not rely on how an awk orders NaN: mawk says `nan == 0`
is true, gawk 5.0 orders NaN above every number, gawk 5.2+ follows IEEE. Every
compare that can see a NaN is guarded with `_isnan()`/`_nf()` (they look at
the `%g` spelling), and every loop whose bound comes from an argument checks
that it is finite first. The answers are therefore the same on every awk
(probed across a 2280-request nan/inf/±0 matrix: mawk 20240123 and 20250131,
gawk 5.2 and 5.3 give identical answers; gawk 5.0 of Git-bash/MSYS2 through the
non-finite rows of `tests/019`), and IEEE — except where the formula the
engine computes has no IEEE special case for the operand (probed on gawk
5.2.1 and mawk 1.3.4 20250131, kb-debian):

| call | answer | IEEE / C libm | why |
|---|---|---|---|
| `expM1 inf` | `nan` | `inf` | the accurate form `(u-1)·x/ln(u)` is `inf/inf` |
| `hypot inf inf` | `nan` | `inf` | the overflow-safe form `x·sqrt(1+(y/x)²)` has `y/x = inf/inf` |
| `hypot inf nan`, `hypot nan inf` | `nan` | `inf` | a NaN operand answers `nan` first |
| `csc -0`, `cotan -0` | `inf` | `-inf` | a division by zero takes its sign from the numerator only (`_dv`), not from the zero's sign |

Otherwise:

```bash
math.futureValue 0.05 inf -100 0   # nan — a non-finite n (also presentValue,
math.payment 0.05 nan 1000 0       # nan    payment, interestRate) used to
math.tanh nan                      # nan    loop forever in the integer power
math.hypot 0 nan                   # nan
math.logN 1 -1                     # nan  (NaN/0 is NaN, not inf)
math.compareValue 1 2 nan          # -1   (|a-b| <= NaN is false, as in FPC)
```

### The engine never dies

Before P7, one division by zero anywhere in the awk prelude killed the
co-process: gawk treats it as a *fatal*, so the call answered an empty line
with rc 0 and the next call silently respawned awk with a bash warning. Every
division now goes through a guarded helper that returns the IEEE value an FPU
with the zero-divide exception masked would produce, so the poles answer
instead of exploding:

```bash
math.fmod 5 0      # nan            math.cotan 0     # inf
math.logN 1 5      # inf            math.ln 0        # -inf
math.mean          # nan            math.power 0 -1  # inf
math.roundTo 1 -400 # nan           math.exp 1000    # inf
```

`math/tests/014` asserts, for each of ~45 such inputs, both the value **and**
that the engine is still the same live process afterwards, and checks
structurally that no unguarded `/` has crept back into the prelude.

Three more lifecycle rules:

- an argument is validated (`math._is_num`) **before** it is written, so a
  newline in it can never split one request into two and shift every later
  answer by one;
- the engine's `inf`/`nan` tokens are normalised in both directions — gawk
  parses a bare `inf` as **0** and emits `+inf`/`-nan`, so what this unit
  publishes (`inf`, `-inf`, `nan`) is exactly what it accepts;
- awk runs under `LC_ALL=C`, so `%.17g` prints `2.5` even when the caller's
  locale uses a comma.

The answer is read with a plain blocking `read`: a dead engine closes the pipe
and `read` fails at once, which is the case that matters. `read -t` is used on
the start probe, and on **every** call when `__MATH_FE_STRICT` is set — it
costs ~410 µs a call on this platform (measured on 5.2.37 and 5.3.9,
independent of the timeout value), against ~105 µs for the whole round trip,
so it is opt-in rather than default. Set it if a stopped or wedged `awk` is a
real risk where you run.

## Conventions

| Result kind | How it is returned |
|---|---|
| number | `RESULT` as a token; engine results use `%.17g` (round-trippable `Double`, may show trailing noise like `2.9999999999999996`) |
| Boolean | exit status; `RESULT` also holds `true` / `false` |
| `Sign` / `CompareValue` | `-1` / `0` / `1` |
| multi-value (`sinCos` `divMod` `frexp` `sumsAndSquares` `meanAndStdDev` `momentSkewKurtosis`) | space-separated fields, read with `read -r a b …` |
| `NaN` / `±Inf` | the literal tokens `nan` / `inf` / `-inf` (accepted on input too, in any case and with an optional sign, plus `infinity`) |
| arrays (`mean` `sum` `norm` …) | passed as the **argument list**: `math.mean 1 2 3 4` |
| `TPaymentTime` (financial) | a `0`/`1` flag: `0` = end-of-period (default), `1` = start |
| errors (bad args, `divMod` by 0, no engine) | `return 1`, `RESULT=""`, nothing printed |

**Every numeric argument is validated** before it is used
(`kk.isInt`/`kk.isNum` plus this unit's `inf`/`nan` tokens). `math.min abc 5`,
`math.sqrt 0x10`, `math.sin "1 2"` and `math.ceil 1,5` are rc 1 with an empty
`RESULT` — they are *not* silently read as 0.

**Parity**: Tier-A results are exact; Tier-B results match FPC `Double` within
~1–2 ulps (compare with a tolerance, e.g. the tests' `kt_assert_near`).

## Differences from FPC

FPC runs on an x86 FPU with the invalid-operation, zero-divide and overflow
exceptions **unmasked**, so it *raises* where IEEE would produce a value. bash
has no exception mechanism, and the kcl contract reserves rc 1 for "this
argument is not a value I can use" — so R11 (owner, 2026-09-06) chose the IEEE
answer:

| | FPC 3.2.2 | this port |
|---|---|---|
| `fmod x 0`, `cotan 0`, `logN 1 x`, `power 0 -1`, `mean` of `[]` | `EZeroDivide` / `EInvalidOp` | `nan` / `±inf`, engine unharmed |
| `Frexp(±Inf)` (`math.pp:1118`) | halves `X` until `|X| < 1` — **never terminates** | the C `frexp` answer: the value itself, exponent 0 |
| `IntPower(2,63)` (`math.pp:1044`) | returns a **float**: `9.2233720368547758E18` | same — the exact int64 path falls through to the engine on overflow |
| `SumInt` (`math.pp:1224`) | Int64 accumulator, **wraps** silently | overflow goes to the engine and answers the Double (P7/M8: a wrapped bash integer is indistinguishable from a real total) |
| `RandomRange` (`math.pp:1405`) | `Random(Abs(aFrom-aTo))+Min(…)`, span computed in Int64 | same, and a span that overflows Int64 is rc 1 instead of a wrapped negative |
| `Ceil`/`Floor` of a value past Int64 | `Trunc` overflows | the `%.17g` float |

Rules the port follows exactly, and the source lines they came from:
`Max(a,b) = if a>b then a else b` (`:2033` — ties **and NaN** yield the second
operand), `Sign = ord(v>0)-ord(v<0)` (`:729` — NaN is 0), `InRange =
(v>=min) and (v<=max)` (`:2157` — NaN is false), `EnsureRange` clamps with
`<`/`>` only (`:2185` — NaN passes through), `CompareValue` is
GreaterThanValue unless `|a-b|<=delta` or `a<b` (`:2576` — NaN is **1**),
`SameValue` epsilon `Max(Min(|a|,|b|)*1e-12, 1e-12)` (`:2382`), `RoundTo =
Round(AValue/RV)*RV` with `RV=IntPower(10,Digits)` and `Round` half-to-even
(`:2606`; awk's `sprintf("%.0f")` is half-to-even too), `DivMod` negates both
quotient and remainder for a negative dividend (`:2463` — exactly bash `/` and
`%`).

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
| `isNan <x>` · `isInfinite <x>` | rc + `true`/`false` (test the `nan` / `±inf` tokens) |

RNG parity is semantic only (bash `$RANDOM` vs FPC's Mersenne generator), but
the distribution is honest: both draw **63 bits** from five `$RANDOM`, mask
down to the next power of two and **reject-sample**, so every value in the
range is equally likely and the full `int64` span is reachable. (Until P7 they
composed 30 bits and took `% n`: the top of any range wider than 2^30 was
unreachable and every non-power-of-two range was biased.) A `from`/`to` pair
whose span does not fit in `int64` is rc 1 rather than a wrapped negative.

## Cost (measured, `bash bench.sh`, MSYS2 5.2.37)

Two numbers, not one — the callee's cost and the caller's:

| | before P7 | after P7 |
|---|---|---|
| Tier-A member, callee | 99–200 µs | 117–240 µs |
| `intPower 2 10` | 76 µs | 111 µs |
| `sumInt` (5 values) | 396 µs | 415 µs |
| Tier-B round trip (`sin`) | 184 µs | 232 µs |
| **using a result** (`min` + read it) | **~17.7 ms** (`$( )` — the old contract left no choice) | **96 µs** — 184× cheaper |

The callee's cost went up by 10–25 % and that is deliberate: every numeric
argument is now validated before it reaches `(( ))` or the engine (M14), and
each member routes its answer through `math._ret` instead of `printf`. The
caller's cost — the number a program actually pays — fell by two orders of
magnitude, because the direct call no longer needs a subshell. `intPower` pays
most (a real overflow check replaced a bare `**`, M8) and still stays under a
fifth of a millisecond.

`bench.sh` also asserts, every run, that a Tier-A path spawns no external
process, that one awk co-process serves 100 calls, and that three domain
errors in a row leave the engine alive.

## Out of scope (wontfix)

FPU control has no bash equivalent — `getRoundMode` (→ `rmNearest`),
`getPrecisionMode` (→ `pmDouble`), `getExceptionMask` are informational stubs;
`setRoundMode`/`setPrecisionMode`/`setExceptionMask` **return 1**;
`clearExceptions` is a no-op. Also wontfix: the Single/Extended precision
distinctions (the engine is `Double`), the `PT+N` pointer-array overloads (the
port takes an argument list), `generic RandomFrom<T>`, and the FPU-rounding-mode-
dependent integer→float conversion. See [PLAN.md](../docs/dev/math/PLAN.md) §4.

---

- Upstream API reference: [docs/Math.md](docs/Math.md)
- Design & rationale: [PLAN.md](../docs/dev/math/PLAN.md) · status: [math_ledger.json](../docs/dev/math/math_ledger.json)
- Test-coverage analysis: [TEST_COVERAGE_NOTES.md](../docs/dev/math/TEST_COVERAGE_NOTES.md)
- Micro-benchmark: [bench.sh](bench.sh)
