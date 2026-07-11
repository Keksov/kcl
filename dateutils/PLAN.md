# dateutils — Free Pascal DateUtils for bash (kcl)

Port of the FPC `DateUtils` unit to a kcl static utility class.

- **Source of truth**: `C:\projects\KKMindWave\VendorsCore\fpc\sources\main\packages\rtl-objpas\src\inc\dateutil.inc`
  (3857 lines, 195 functions; ~160 are public API, the rest are internal scan/match helpers).
- **Destination**: `kcl/dateutils/dateutils.sh` (+ `tests/`, this plan, `dateutils_ledger.json`).
- **Ledger**: [dateutils_ledger.json](dateutils_ledger.json) — single source of truth for task status.

---

## 1. Core design decision: the KDT representation

FPC `TDateTime` is a `Double` — days since 1899-12-30, time as the day fraction.
Bash has no floating point, so the port defines:

> **KDT (KDateTime) = integer milliseconds since 1970-01-01 00:00:00 (naive), proleptic Gregorian calendar.**

- Plain 64-bit bash integer: exact arithmetic with `$(( ))`, no precision loss,
  negative values = dates before 1970 (works fine down past 1899-12-30 = `-2209161600000`).
- Millisecond resolution matches the finest unit the FPC API exposes
  (`MilliSecondOf`, `IncMilliSecond`, `MilliSecondsBetween`).
- **Naive** (timezone-agnostic), like `TDateTime` itself: values carry no zone;
  `now`/`today` produce local wall-clock time, `nowUTC` produces UTC.
  Explicit conversion: `localTimeToUniversal` / `universalTimeToLocal`.
- The FPC epoch (1899-12-30) never appears in the public API — Unix conversions
  (`dateTimeToUnix`/`unixToDateTime`) become trivial `*/1000` scalings.

### Calendar math — pure bash, zero forks

- Civil-calendar conversion via the **Hinnant algorithms** (`days_from_civil`,
  `civil_from_days`) — pure integer arithmetic, correct for all years,
  proleptic Gregorian: exactly the Delphi/FPC model.
- Wall clock via **`EPOCHREALTIME`** (bash builtin, microseconds — verified on
  both target bashes: 5.2.37 MSYS2 and 5.3.9), local offset via
  `printf '%(%z)T'` (builtin strftime). **No `date` forks anywhere** — on this
  MSYS2 box a single fork costs ~10-30 ms, i.e. more than a thousand pure-bash
  calendar computations.
- Constants (all in ms): second 1000, minute 60000, hour 3600000, day 86400000,
  week 604800000; FPC approximation parity: year = 31557600000 (365.25 d),
  month = 2629800000 (30.4375 d) — used by the approximate
  `yearsBetween`/`monthsBetween`/`yearSpan`/`monthSpan`, exactly like FPC's
  `ApproxDaysPerYear`/`ApproxDaysPerMonth`.

### Value conventions (kcl house style)

| FPC concept                  | bash convention                                              |
|------------------------------|--------------------------------------------------------------|
| `TDateTime` in/out           | KDT integer (ms), passed/echoed as a plain number             |
| `Boolean` result             | echo `true` / `false`                                         |
| `out` params (`DecodeDate`)  | echo space-separated fields: `"YYYY MM DD"` (`read -r y m d`) |
| `Try*` functions             | echo the result, `return 0`; on failure echo nothing, `return 1` |
| `Double` result (`*Span`)    | fixed-point decimal string, 6 places, via integer scaling     |
| errors (invalid date etc.)   | `return 1`; message to stderr only under `VERBOSE_KKLASS=debug` |
| `RecodeLeaveFieldAsIs`       | literal `-` argument keeps the field                          |
| ISO strings                  | `YYYY-MM-DD`, `hh:mm:ss[.zzz]`, datetime with ` ` or `T`      |

### Class shape

Pascal DSL static utility (same pattern as `tpath`/`tfile`):

```bash
source "../../kklass/kklass_pascal.sh"
class dateutils
    public
        static proc now
        static proc encodeDate
        ...
end
dateutils.now() { ... }
...
build dateutils
```

- **No `static var`** — the class must stay on the thin, capture-free
  dispatcher path (fast on bash 5.2 and 5.3). Constants are therefore NOT
  class members but top-level variables. NOTE: bash has no file scope — a
  top-level variable in a sourced file is a **process-wide global**. To keep
  them collision-safe they are (a) prefixed `__KDT_` (`__KDT_MS_PER_DAY`,
  `__KDT_MS_PER_HOUR`, ...), (b) declared `readonly` (guarded by a re-source
  check, same as the `_KKLASS_PASCAL_SOURCED` idiom), so no other library can
  silently overwrite them. The thin-dispatch property is regression-pinned the
  same way as `tfile` test 038.

  *Why not a `TDateUtils` class with `static var` constants*: kklass stores a
  static var as the very same process global (`TDateUtils_static_MsPerDay`) —
  no encapsulation is gained; reading it through the accessor costs a subshell
  per read in hot paths; the accessor makes "constants" silently writable
  (`TDateUtils.MsPerDay = 0`), while `readonly` fails loudly; and static vars
  on the `dateutils` class itself would push all ~160 methods onto the slow
  capturing dispatcher. What IS taken from that idea: **public constant
  getters as `static proc`s on `dateutils`** (`dateutils.msPerDay`,
  `dateutils.approxDaysPerMonth`, ... — FPC exposes the same constants), which
  keep the class static-var-free and thin while giving consumers a namespaced
  API; internals keep using the `__KDT_*` readonly globals directly.
- Method names: FPC names in lowerCamelCase (`YearOf` → `dateutils.yearOf`),
  matching `tpath.getFileName` house style.
- Internal helpers (`dateutils._days_from_civil`, `dateutils._civil_from_days`,
  `dateutils._parse_iso`, ...) are plain functions, not class members.

---

## 2. Semantics notes (FPC parity points)

- **`dayOfTheWeek`**: ISO — Monday=1 .. Sunday=7 (DateUtils flavor, NOT the
  SysUtils Sun=1 `DayOfWeek`).
- **Weeks are ISO-8601**: week 1 is the week containing Jan 4; `weekOf`,
  `weekOfTheYear`, `encodeDateWeek`/`decodeDateWeek` follow it, including the
  year-boundary cases (2004-01-01 → week 53 of 2003, 2008-12-29 → week 1 of 2009).
- **`incMonth`** (from SysUtils, included for completeness) clamps the day:
  Jan 31 + 1 month → Feb 28/29.
- **`yearsBetween`/`monthsBetween`** are approximate by default (365.25 /
  30.4375 days), with an optional `exact` flag that switches to calendar-true
  `periodBetween` decomposition — mirroring the FPC `AExact` parameter.
- **`compareDate/Time/DateTime`** echo `-1` / `0` / `1`.
- **`withinPastXxx now then range`** = `xxxBetween(now, then) <= range`.
- **Spans** (`daySpan`, `hourSpan`, ...) are true fractional ratios of the ms
  difference, printed with 6 decimal places.

---

## 3. Out of scope (recorded as wontfix in the ledger)

| FPC item | Reason |
|---|---|
| `DateTimeToMac`, `MacToDateTime`, `MacTimeStampToUnix`, `UnixTimeStampToMac` | Mac OS classic timestamps — no practical bash use case |
| `DateTimeToDosDateTime`, `DosDateTimeToDateTime` | 16-bit DOS packed format — same |
| `DateTimeToNumber`, `NumberToDateTime`, `DateTimeDiff` as *Double* emulation | KDT **is** the number; provided as trivial aliases where meaningful (`dateTimeDiff` = signed ms) |
| `TDateTimeHelper`, `TTimeZone`, `TLocalTimeZone` | FPC type-helper / class sugar over the same functions |
| Full `ScanDateTime` pattern language | P7 implements the practical subset (`yyyy mm dd hh nn ss zzz` + literals); the full FPC matcher (ampm, timezones, `[]` optionals) only if the subset proves insufficient |

---

## 4. Phases

Each phase = implement → per-function ktest file(s) → **full kcl+kklass sweep
green on bash 5.2** → spot-check on 5.3 → ledger update. The kcl baseline
(1584 green tests across 7 suites) must never regress.

- **P0 — Scaffolding & core** *(gate for everything)*
  Directory, class skeleton, tests runner, civil-calendar helpers, ISO
  parse/format, `now`/`nowUTC`/`today`/`yesterday`/`tomorrow`, `dateOf`/`timeOf`.
  Acceptance: encode↔decode roundtrip over a sampled grid (incl. leap edges,
  pre-1970), `now` sane vs `EPOCHREALTIME`, zero `date` forks in the hot paths.

- **P1 — Encode/Decode & validity** (~24 fn)
  `encodeDate/Time/DateTime`, `decodeDate/Time/DateTime`, `try*` variants,
  `encodeDateDay`/`decodeDateDay`, `isValidDate/Time/DateTime/DateDay/DateWeek/
  DateMonthWeek`, `isInLeapYear`, `daysInAMonth/daysInMonth`,
  `daysInAYear/daysInYear`, `weeksInAYear/weeksInYear`.

- **P2 — Extraction** (~40 fn)
  `yearOf`..`milliSecondOf`, `dayOfTheWeek/Month/Year`, `monthOfTheYear`,
  `weekOf`/`weekOfTheYear`/`weekOfTheMonth` (ISO), the `hourOfThe*`,
  `minuteOfThe*`, `secondOfThe*`, `milliSecondOfThe*` families,
  `nthDayOfWeek`, `decodeDayOfWeekInMonth`, `isAM`/`isPM`.

- **P3 — Start/End & day predicates** (~20 fn)
  `startOfTheYear/Month/Week/Day` + `AYear/AMonth/AWeek/ADay` twins,
  `endOfThe*`/`EndOfA*` twins, `isToday`, `isSameDay`, `isSameMonth`,
  `previousDayOfWeek`.

- **P4 — Arithmetic, spans, comparison** (~40 fn)
  `incYear/Month/Week/Day/Hour/Minute/Second/MilliSecond`,
  `yearsBetween`..`milliSecondsBetween` (+ `exact` flag), `periodBetween`,
  `yearSpan`..`milliSecondSpan`, `withinPastYears`..`withinPastMilliSeconds`,
  `compareDate/Time/DateTime`, `sameDate/Time/DateTime`, `dateTimeDiff`,
  `dateInRange`/`timeInRange`/`dateTimeInRange`.

- **P5 — Recode & week/day encodings** (~18 fn)
  `recodeYear`..`recodeMilliSecond`, `recodeDate/Time/DateTime`,
  `tryRecodeDateTime` (`-` = leave as is), `encodeDateWeek`/`decodeDateWeek`,
  `encodeDateMonthWeek`/`decodeDateMonthWeek`, `encodeDayOfWeekInMonth`
  (+ `try*` variants).

- **P6 — Conversions & timezones** (~16 fn)
  `dateTimeToUnix`/`unixToDateTime`, `dateToISO8601`/`iso8601ToDate`(+`Def`/`try`),
  `tryISOStrToDate/Time/DateTime`, `isoTZStrToTZOffset`/`try`,
  `localTimeToUniversal`/`universalTimeToLocal` (explicit offset, default =
  system zone via `%(%z)T`), Julian / Modified Julian (decimal strings, 6 dp),
  `encodeTimeInterval`/`tryEncodeTimeInterval`. Mac/DOS: wontfix.

- **P7 — scanDateTime subset, docs, bench, final sweep**
  `scanDateTime` practical subset; `README.md` (API reference per group);
  micro-benchmark (target: extraction/arithmetic ≤ 0.3 ms/call thin-dispatch);
  full-suite + examples sweep on 5.2, spot 5.3; close the ledger.

Estimated test volume: 12-14 ktest files, ≥400 checks, incl. fixtures for ISO
week edges, leap centuries (1900 no / 2000 yes / 2100 no), month-end clamping,
pre-1970 dates, `periodBetween` leap-day asymmetries, and a GNU-`date`
cross-check sample (100 random epochs, guarded as optional if `date` absent).

### Test basis: FPC's own tests as the seed

The FPC test suite is the authority on intended semantics — its dateutils
tests are ported 1:1 as the **FPC-parity fixture set** before any tests of our
own design:

| seed file (FPC tree) | what it pins | lands in phase |
|---|---|---|
| `tests/webtbs/tw16040.pp` — **primary seed** (17 assertions) | Julian/MJD anchors (JD 2455277.5 ↔ 2010-03-22, 2455278.5 ↔ 2010-03-23, MJD roundtrip); `IsInLeapYear(2011)=false`; `IsPM`; `YearOf/MonthOf/DayOf/HourOf(TheDay)/MinuteOf(TheHour)/SecondOf(TheMinute)/MilliSecondOf(TheSecond)` on 2011-03-26 19:15:30.555; `StartOfTheYear`/`EndOfTheYear` anchors; `scandatetime 'YYYY.MM.DD HH:NN:SS:ZZZ'` | P1 (encode), P2 (extraction), P3 (start/end), P6 (Julian), P7 (scan) |
| `tests/test/units/dateutil/tunitdt1.pp` | far-future Unix roundtrips: `UnixToDateTime(15796372693)` → 2470-07-26 09:18:13; encode(2345-12-12 04:45:49) → unix → decode roundtrip | P6 |
| `tests/webtbs/tw25170.pp`, `tests/webtbs/tw40121.pp` | mined for additional assertions at implementation time | per function group |
| `tests/webtbf/tw35866.pp` (must-FAIL test) | negative-case semantics | error-path fixtures |

The parity file (`tests/00X_FpcParity_*.sh`) is built incrementally: each
phase ports the tw16040 assertions whose functions land in that phase; the
file is complete when P7 delivers `scanDateTime`. A parity assertion keeps the
FPC values **verbatim** (translated to KDT) and is never "improved".

### New-coverage protocol (tests beyond FPC's suite)

The seed is knowingly thin (17 assertions vs ~160 functions), so most of our
fixtures are new. **Every test case not traceable to an FPC test file gets a
row in [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)** — the document the
user reviews for further analysis (and potential upstreaming to FPC). Row
format:

- **id** — test file + check label;
- **functions** covered;
- **case** — the concrete scenario (e.g. "2004-01-01 is ISO week 53 of 2003");
- **why FPC lacks it** — gap classification: boundary not exercised /
  bash-specific convention (echo formats, `-` sentinel, status codes) /
  representation-specific (KDT negatives, ms overflow) / cross-check vs GNU date;
- **basis for the expected value** — FPC source reading, independent
  calculation, RFC/ISO citation, or GNU `date` output.

---

## 5. Risks / open questions

1. **ISO week + `encodeDateWeek` edge cases** — richest source of off-by-ones;
   mitigated by the dedicated fixture table (12 boundary dates) before code.
2. **`periodBetween` semantics** — FPC has subtle borrow logic around month
   ends; port the algorithm, not an approximation, and pin with fixtures
   (e.g. 2004-02-29 → 2005-02-28).
3. **Span decimal output** — 6 dp via integer scaling can overflow for spans
   > ~292 000 years in ms·10⁶; accepted (documented) limit.
4. **`%(%z)T` on MSYS2/cygwin bash** — verify offset format `+HHMM` on both
   bashes in P0; fall back to `date +%z` only if the builtin misbehaves
   (would be the single permitted fork, cached per process).
