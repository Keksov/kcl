# dateutils — Free Pascal `DateUtils` for bash

A faithful bash port of FPC's `DateUtils` unit as a kcl [kklass](../../kklass)
Pascal-DSL **static utility class**: 185 public methods called as
`dateutils.<Method>`. Pure-bash integer arithmetic, **zero `date` forks** on the
hot paths, thin (capture-free) dispatch on bash 5.2 and 5.3 alike.

- Design & rationale: [PLAN.md](PLAN.md) · status: [dateutils_ledger.json](dateutils_ledger.json)
- Test-coverage analysis: [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)

```bash
source /path/to/kcl/dateutils/dateutils.sh

dateutils.encodeDateTime 2011 3 26 19 15 30 555   # direct call: sets RESULT
kdt=$RESULT                                        # ... a "KDT" integer

dateutils.dayOfTheWeek "$kdt"; echo "$RESULT"      # 6   (ISO: Sat)
dateutils.incMonth "$kdt" 1;   echo "$RESULT"      # KDT of 2011-04-26 …
read -r y m d <<< "$(dateutils.decodeDate "$kdt")" # $( ) still works: y=2011 …

if dateutils.isValidDate 2011 2 30; then :; else echo "not a date"; fi
```

## The KDT contract

Every date/time value — every argument and every result marked *KDT* below — is
a single **integer: milliseconds since 1970-01-01 00:00:00, naive (no timezone),
proleptic Gregorian.** Negative values are dates before 1970. There is no
separate "date" or "time" type; a *time-of-day* is just the millisecond offset
within a day (`0 … 86399999`), and a *duration* is a plain millisecond count.

- Calendar math uses the Hinnant civil-date algorithms (exact for all years).
- Wall clock comes from the `EPOCHREALTIME` builtin; the local UTC offset from
  `printf '%(%z)T'`. No `date` subprocess is spawned.
- `1970-01-01` = KDT `0` = JD `2440587.5`; `1899-12-30` (the FPC epoch) = KDT
  `-2209161600000`.

## Conventions

This unit follows the [kcl contract](../README.md) §1. Since phase P6 of the
2026-09-06 review that means **`RESULT`, not stdout** (decision D3):

```bash
dateutils.yearOf "$kdt"        # a DIRECT call prints NOTHING and sets RESULT
use "$RESULT"
y="$(dateutils.yearOf "$kdt")" # inside $( ) the value is printed exactly once
```

The direct form is the one to use: `$( )` forks a subshell, measured on this
MSYS2 box at **19 ms against 0.19 ms** for the same call read through `RESULT`
(`bash bench.sh`, "caller cost" section). Every call site written against the
pre-P6 `printf` bodies keeps working, because `$( )` still prints.

| Result kind | How it is returned |
|---|---|
| KDT / integer | `RESULT` = a plain number |
| Boolean | **exit status** carries the answer, and `RESULT` carries `true` / `false` |
| multi-field decode | space-separated fields in `RESULT`, read with `read -r a b c …` |
| `try*` | value in `RESULT`, status 0; on failure `RESULT=''`, status 1, nothing printed |
| `*Span` | fixed-point decimal string, 6 places (e.g. `1.500000`, `-0.500000`) |
| `compare*` | `-1` / `0` / `1` in `RESULT` |
| errors (invalid date, bad parse, a non-numeric argument) | **status 1**, `RESULT=''`, nothing printed; a message goes to stderr only under `VERBOSE_KKLASS=debug` |
| `recode*` "leave field" | pass the literal `-` for a field to keep it |
| offsets (`localTimeToUniversal`, …) | minutes **east** of UTC (`+180` = UTC+3), or an ISO `±hh:mm` / `Z` string |
| `isoTZStrToTZOffset` only | **FPC sign** — `+03:00` → `-180` (kept for parity) |

Invalid inputs to the non-`try` encoders (`encodeDate`, `recodeMonth`, …) return
1 where FPC would raise `EConvertError` (bash has no exceptions).

### Booleans

A predicate answers with its **exit status** and leaves the word in `RESULT`, so
both idioms read correctly:

```bash
if dateutils.isValidDate "$y" "$m" "$d"; then …; fi     # status
[[ "$(dateutils.isInLeapYear "$kdt")" == true ]]        # word, via $( )
```

Under `set -e` a bare `dateutils.isAM "$kdt"` with a `false` answer aborts the
caller — that is bash's rule for every command, so call a predicate from an
`if`, a `&&`/`||`, or a `!` (kcl README §1.3).

A predicate distinguishes **"no"** from **"that is not a date"**: `isValidDate
2011 2 30` is status 1 with `RESULT='false'`, while `isValidDate abc 1 1` is
status 1 with `RESULT=''`.

### Numeric arguments

Every year, month, day, index and KDT goes through `kk.isInt` before it reaches
`(( ))` (kcl README §1.5, decision D1). Two consequences:

* **Zero-padded fields work.** `encodeDate 2011 08 09` is August 9th, not an
  octal parse error — which matters because `IFS=- read y m d <<< 2011-08-09`
  produces exactly that (finding G3-01).
* **A non-numeric argument is refused, never evaluated.** `incDay
  'x[$(rm -rf ~)]'` returns 1 and runs nothing; `dayOf ''` returns 1 instead of
  silently answering with the epoch (finding G3-04).

---

## Wall clock & constructors

| Signature | Returns in `RESULT` | Example |
|---|---|---|
| `now` | KDT (local wall clock) | `dateutils.now` |
| `nowUTC` | KDT (UTC wall clock) | `dateutils.nowUTC` |
| `today` / `yesterday` / `tomorrow` | KDT at 00:00 | `dateutils.today` |
| `dateOf <kdt>` | KDT with time zeroed | `dateutils.dateOf "$k"` |
| `timeOf <kdt>` | ms-of-day (0…86399999) | `dateutils.timeOf "$k"` |

## Encode / decode

| Signature | Returns in `RESULT` |
|---|---|
| `encodeDate <y> <m> <d>` · `tryEncodeDate …` | KDT (00:00) |
| `encodeTime <h> <n> <s> <ms>` · `tryEncodeTime …` | ms-of-day (**hour must be < 24**, see below) |
| `encodeDateTime <y> <m> <d> <h> <n> <s> <ms>` · `tryEncodeDateTime …` | KDT |
| `decodeDate <kdt>` | `Y M D` |
| `decodeTime <kdt>` | `H N S MS` |
| `decodeDateTime <kdt>` | `Y M D H N S MS` |
| `encodeDateDay <y> <dayOfYear>` · `tryEncodeDateDay …` | KDT |
| `decodeDateDay <kdt>` | `Y DayOfYear` |

```bash
dateutils.encodeDate 2000 2 29                 # a leap-day KDT in RESULT
dateutils.encodeDate 2011 2 29 || echo bad     # -> bad  (status 1, RESULT='')
read -r y d <<< "$(dateutils.decodeDateDay "$(dateutils.encodeDate 2011 3 26)")"  # y=2011 d=85
```

> **Hour 24 — an asymmetry that belongs to FPC.**
> `DateUtils.IsValidTime(24,0,0,0)` is **True** (dateutil.inc:535 — the
> whole-day marker), but `SysUtils.TryEncodeTime` is
> `(Hour<24) and (Min<60) and (Sec<60) and (MSec<1000)`
> (rtl/objpas/sysutils/dati.inc:117), and every `encode*`/`recode*` goes through
> it. So `isValidTime 24 0 0 0` is true while `encodeTime 24 0 0 0` and
> `encodeDateTime 9999 12 31 24 0 0 0` are status 1 — which is also what stops
> the latter from quietly producing year 10000 (finding G3-10).

## Validity & calendar sizes

| Signature | Returns in `RESULT` |
|---|---|
| `isValidDate <y> <m> <d>` | true/false (year 1…9999) |
| `isValidTime <h> <n> <s> <ms>` | true/false (`24:00:00.000` is valid) |
| `isValidDateTime <y> <m> <d> <h> <n> <s> <ms>` | true/false |
| `isValidDateDay <y> <doy>` | true/false |
| `isValidDateWeek <y> <week> <dow>` | true/false |
| `isValidDateMonthWeek <y> <m> <wom> <dow>` | true/false |
| `isInLeapYear <kdt>` | true/false (of the date's year) |
| `daysInAMonth <y> <m>` · `daysInMonth <kdt>` | day count |
| `daysInAYear <y>` · `daysInYear <kdt>` | 365 / 366 |
| `weeksInAYear <y>` · `weeksInYear <kdt>` | 52 / 53 (ISO-8601) |

## Extraction

| Group | Functions (all take a `<kdt>`) |
|---|---|
| fields | `yearOf` `monthOf` `dayOf` `hourOf` `minuteOf` `secondOf` `milliSecondOf` |
| aliases | `monthOfTheYear` `dayOfTheMonth` `hourOfTheDay` `minuteOfTheHour` `secondOfTheMinute` `milliSecondOfTheSecond` |
| ISO calendar | `dayOfTheWeek` (Mon=1…Sun=7) · `dayOfTheYear` · `weekOf` `weekOfTheYear` `weekOfTheMonth` |
| am/pm | `isAM` `isPM` |
| of-the-day | `minuteOfTheDay` `secondOfTheDay` `milliSecondOfTheDay` |
| of-the-hour | `secondOfTheHour` `milliSecondOfTheHour` |
| of-the-minute | `milliSecondOfTheMinute` |
| of-the-week | `hourOfTheWeek` `minuteOfTheWeek` `secondOfTheWeek` `milliSecondOfTheWeek` |
| of-the-month | `hourOfTheMonth` `minuteOfTheMonth` `secondOfTheMonth` `milliSecondOfTheMonth` |
| of-the-year | `hourOfTheYear` `minuteOfTheYear` `secondOfTheYear` `milliSecondOfTheYear` |
| nth weekday | `nthDayOfWeek` · `decodeDayOfWeekInMonth <kdt>` → `Y M Nth Dow` |

```bash
dateutils.dayOfTheWeek "$(dateutils.encodeDate 1970 1 1)"   # 4  (Thursday)
dateutils.weekOfTheYear "$(dateutils.encodeDate 2005 1 1)"  # 53 (ISO year 2004)
```

## Start / end of period & day predicates

| Signature | Returns in `RESULT` |
|---|---|
| `startOfTheYear/Month/Week/Day <kdt>` · `endOfThe…` | KDT (start = 00:00, end = 23:59:59.999) |
| `startOfAYear <y>` · `endOfAYear <y>` | KDT |
| `startOfAMonth <y> <m>` · `endOfAMonth <y> <m>` | KDT |
| `startOfAWeek <y> <week> [dow=1]` · `endOfAWeek <y> <week> [dow=7]` | KDT (ISO week-date) |
| `startOfADay <y> <m> <d>` **or** `<y> <doy>` · `endOfADay …` | KDT |
| `isToday <kdt>` | true/false |
| `isSameDay <kdt> <basis>` · `isSameMonth <a> <b>` | true/false |
| `previousDayOfWeek <dow>` | prior ISO weekday (1…7; takes a **number**, not a date) |

Week boundaries are ISO (Monday…Sunday). `endOfTheX == startOfNext(X) - 1ms`.

## Arithmetic

| Signature | Returns in `RESULT` |
|---|---|
| `incYear/Month/Week/Day/Hour/Minute/Second/MilliSecond <kdt> [n=1]` | KDT |

`incMonth`/`incYear` clamp the day (Jan 31 +1m → Feb 28/29; Feb 29 +1y → Feb 28).

FPC's `IncYear` (dateutil.inc:1561) and `SysUtils.IncMonth` both end in
`EncodeDate(Y,M,D)`, which raises outside year 1…9999, so a step that would land
on year 0 or 10000 is **status 1**, not an answer (finding G3-10):

```bash
dateutils.incYear "$(dateutils.encodeDate 9999 6 1)" 1 || echo "out of range"
```

## Differences, spans & comparison

| Signature | Returns in `RESULT` |
|---|---|
| `yearsBetween <a> <b> [exact]` · `monthsBetween <a> <b> [exact]` | integer (approx by default; `exact` = calendar-true) |
| `weeksBetween` `daysBetween` `hoursBetween` `minutesBetween` `secondsBetween` `milliSecondsBetween` `<a> <b>` | integer |
| `periodBetween <a> <b>` | `Years Months Days` (calendar decomposition) |
| `dateTimeDiff <a> <b>` | signed ms (`a - b`) |
| `yearSpan/monthSpan/weekSpan/daySpan/hourSpan/minuteSpan/secondSpan/milliSecondSpan <a> <b>` | 6-dp decimal |
| `withinPastYears/Months/Weeks/Days/Hours/Minutes/Seconds/MilliSeconds <now> <then> <range>` | true/false |
| `compareDateTime/compareDate/compareTime <a> <b>` | -1 / 0 / 1 |
| `sameDateTime/sameDate/sameTime <a> <b>` | true/false |
| `dateInRange/timeInRange/dateTimeInRange <v> <start> <end> [inclusive=true]` | true/false |

`timeInRange` handles overnight ranges (end < start) with OR-logic.

```bash
a=$(dateutils.encodeDate 2001 1 1); b=$(dateutils.encodeDate 2002 1 1)
dateutils.yearsBetween "$a" "$b"          # 0   (approx: 365 < 365.25 days)
dateutils.yearsBetween "$a" "$b" exact    # 1   (calendar-true)
dateutils.daySpan "$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)" "$(dateutils.encodeDate 2011 3 26)"  # 0.500000
```

## Recode (field surgery)

| Signature | Returns in `RESULT` |
|---|---|
| `recodeYear/Month/Day/Hour/Minute/Second/MilliSecond <kdt> <value>` | KDT |
| `recodeDate <kdt> <y> <m> <d>` · `recodeTime <kdt> <h> <n> <s> <ms>` | KDT |
| `recodeDateTime <kdt> <y> <m> <d> <h> <n> <s> <ms>` · `tryRecodeDateTime …` | KDT |

Pass `-` for any field to keep it: `recodeDateTime "$k" - 6 - - - 0 -` sets month=6, second=0.

## Week-date & day-of-week-in-month encodings

| Signature | Returns in `RESULT` |
|---|---|
| `encodeDateWeek <y> <week> [dow=1]` · `tryEncodeDateWeek …` | KDT |
| `decodeDateWeek <kdt>` | `Y Week Dow` (ISO) |
| `encodeDateMonthWeek <y> <m> <wom> <dow>` · `tryEncodeDateMonthWeek …` | KDT |
| `decodeDateMonthWeek <kdt>` | `Y M WeekOfMonth Dow` |
| `encodeDayOfWeekInMonth <y> <m> <nth> <dow>` · `tryEncodeDayOfWeekInMonth …` | KDT (Nth ≥ 1; no "last" form) |

## Conversions & time zones

| Signature | Returns in `RESULT` |
|---|---|
| `dateTimeToUnix <kdt> [inputIsUTC=true]` | Unix seconds |
| `unixToDateTime <sec> [returnUTC=true]` | KDT |
| `dateTimeToJulianDate <kdt>` · `dateTimeToModifiedJulianDate <kdt>` | 6-dp JD / MJD string |
| `julianDateToDateTime <jd>` · `tryJulianDateToDateTime …` | KDT |
| `modifiedJulianDateToDateTime <mjd>` · `tryModifiedJulianDateToDateTime …` | KDT |
| `localTimeToUniversal <kdt> [offset]` · `universalTimeToLocal <kdt> [offset]` | KDT (offset = minutes east or `±hh:mm`) |
| `encodeTimeInterval <h> <n> <s> <ms>` · `tryEncodeTimeInterval …` | ms (hours may exceed 24; the four fields are FPC `word`s — `0…65535`, `n<60`, `s<60`, `ms<1000`) |
| `dateToISO8601 <kdt> [inputIsUTC=true]` | `YYYY-MM-DDThh:mm:ss.zzzZ` (or `±hh:mm`) |
| `iso8601ToDate <str> [returnUTC=true]` · `tryISO8601ToDate …` · `iso8601ToDateDef <str> <default> [returnUTC]` | KDT |
| `tryISOStrToDate <str>` | KDT (00:00) — see the form table below |
| `tryISOStrToTime <str>` | ms-of-day |
| `tryISOStrToDateTime <str>` | KDT (naive, as written) |
| `isoTZStrToTZOffset <tz>` · `tryISOTZStrToTZOffset <tz>` | minutes (**FPC sign**: `+03:00` → `-180`) |

```bash
dateutils.julianDateToDateTime 2455277.5; echo "$RESULT"   # KDT of 2010-03-22 00:00
dateutils.unixToDateTime 0; echo "$RESULT"                  # KDT 0 = 1970-01-01
dateutils.iso8601ToDate 2010-03-22T09:00:00.000+03:00       # -> 2010-03-22 06:00 UTC
```

> **Julian precision:** JD/MJD strings carry 6 decimals (≈ 86.4 ms). A value on
> a micro-day boundary (midnight, noon, quarter days) round-trips exactly;
> anything else comes back within one micro-day. Dates before the epoch print
> with the sign in front — `-0.500000`, `-21503.750000` — and parse back.
>
> A malformed JD/MJD string is status 1 with `RESULT=''`, not the epoch.

### ISO 8601 forms

The FPC reference is `packages/rtl-objpas/src/inc/dateutil.inc` —
`TryISOStrToDate` (:2740), `TryISOStrToTime` (:2763), `TryISOStrToDateTime`
(:2849), `TryISOTZStrToTZOffset` (:2876), `TryISO8601ToDate` (:2915). FPC
selects a form by the **length** of the string (and, for a datetime, by the
character at a fixed position), and this port does the same.

| Member | Accepted | Refused |
|---|---|---|
| `tryISOStrToDate` | `YYYYMMDD`, `YYYY-MM-DD` (FPC) plus `YYYY`, `YYYYMM`, `YYYY-MM` (port extension) | anything else, and any impossible date |
| `tryISOStrToTime` | lengths 2 `hh`, 4 `hhmm`, 5 `hh:mm`, 6 `hhmmss`, 8 `hh:mm:ss`, 10 `hhmmss.zzz`, 12 `hh:mm:ss.zzz`, each optionally followed by `Z`, `±hh`, `±hhmm` or `±hh:mm` (validated, then **ignored** — FPC does the same) | `19-15`, `19Z` (FPC parses the length-2 form from the *whole* string) |
| `tryISOStrToDateTime` | `<8-char date><' ' or 'T'><time>` and `<10-char date><' ' or 'T'><time>` | a bare date (`2011`, `20110326`) and a bare time (`T19:15`) — FPC's split is positional |
| `tryISO8601ToDate` / `iso8601ToDate` | everything `tryISOStrToDateTime` takes, plus a trailing zone, **plus a date-only string** (port extension) | the rest |

Two deliberate departures, both documented rather than silently different:

1. **Impossible dates are refused** — `2011-02-31`, `2011-04-31`, `0000-01-01`
   used to be accepted and rolled over (`2011-02-31` → March 3rd). Every ISO
   entry point now validates through the same `_valid_date` as `isValidDate`,
   which is what FPC's `TryEncodeDate` does (finding G3-02).
2. **A date-only string is accepted** by `tryISO8601ToDate`. FPC reads the
   trailing `-26` of `2011-03-26` as a timezone and returns False for every
   date-only input; the port strips a zone only from a string that has a time
   part, and falls back to the date parser otherwise.

### Local time and DST

Conversions that involve the local zone (`dateToISO8601 … false`,
`universalTimeToLocal`, `localTimeToUniversal`, `unixToDateTime … false`,
`dateTimeToUnix … false`, `tryISO8601ToDate … false`) use the offset **in force
at the value being converted**, like FPC's `GetLocalTimeOffset(AValue, …)` —
not the offset in force today (finding G3-05). `now`, `today`, `yesterday` and
`tomorrow` are the current instant, so they keep using the current offset.

The lookup is `printf '%(%z)T' <epoch>`, a builtin: still zero forks. It honours
a POSIX `TZ` string with no tzdata installed, which is how the DST behaviour is
tested on this box (`TZ=EST5EDT,M3.2.0,M11.1.0`, tests/022).

## Parsing: scanDateTime

`scanDateTime <pattern> <input>` → KDT (status 1 on mismatch). Case-insensitive
tokens: `yyyy`/`yy` year, `dd` day, `hh` hour, `nn` minute, `ss` second, `zzz`
millisecond — and `mm`, which is the **month everywhere except directly after an
hour token, where it is minutes**. That is FPC's `lasttoken` rule
(`dateutil.inc:2505`), and the `:` time separator is transparent to it
(`dateutil.inc:2615-2618`), so all four of these mean what they look like:

```bash
dateutils.scanDateTime 'yyyy-mm-dd hh:mm:ss' '2011-03-26 19:15:30'   # month, then minutes
dateutils.scanDateTime 'yyyy-mm-dd hh:nn:ss' '2011-03-26 19:15:30'   # the same
dateutils.scanDateTime 'dd/mm/yyyy' '26/03/2011'                     # month
dateutils.scanDateTime 'hh:mm' '19:15'                               # minutes
```

`'literals'`/`"literals"` match verbatim; whitespace in the pattern is elastic
(FPC matches a pattern space exactly — a deliberate convenience); other
characters must match exactly. Two-digit years pivot at 50; unset fields default
to the epoch, so a time-only pattern yields a ms-of-day. Input left over after
the pattern is consumed is allowed, as in FPC.

Refused (status 1): a run of more than two `m` after an hour (FPC
`Shhmmerror`), an **unterminated quote** in the pattern (FPC walks off the end
of the pattern and returns a value; a pattern that cannot be written down
correctly is a malformed call here), a literal that does not match, input that
runs out inside a token, and a scanned date that is not a real date.

Out of scope, as before: month/day *names*, `am`/`pm`, the `c`/`t` date-format
tokens and `[]` optionals.

## Constants (getters)

`msPerSecond` `msPerMinute` `msPerHour` `msPerDay` `msPerWeek`
`approxMsPerMonth` `approxMsPerYear` `approxDaysPerMonth` (`30.4375`)
`approxDaysPerYear` (`365.25`). The backing `__KDT_*` globals are `readonly`.

## Performance

`bash bench.sh` publishes two different numbers, and the older "≤ 0.3 ms/call,
zero forks" claim only ever described the first:

| What | Measured (bash 5.2.37, MSYS2, 2026-09-08) |
|---|---|
| **callee** — dispatch + body, read through `RESULT` | `yearOf` 0.22 ms · `monthOf` 0.22 ms · `dayOfTheWeek` 0.14 ms · `incDay` 0.19 ms · `daysBetween` 0.19 ms · `compareDateTime` 0.19 ms · `weekOfTheYear` 0.39 ms · `incMonth` 0.54 ms |
| **caller** — the same `yearOf`, direct vs `$( )` | 0.19 ms vs **19 ms** — the `$( )` fork is ~100× the call |

Phase P6 moved the two families in opposite directions on purpose:

* the callee got **5–10 % slower** for the simple extractors and about twice as
  slow for `dayOfTheWeek`, because every public member now validates its numeric
  arguments (one `kk.isInt` ≈ 52 µs) — `dayOfTheWeek` validated nothing at all
  before, which is finding G3-04;
* `weekOfTheYear` got **38 % faster** (0.63 → 0.39 ms): the internal helpers no
  longer re-validate values the unit produced itself. Helpers come in pairs —
  `_days_from_civil` / `_days_from_civil_i`, `_floor_day` / `_floor_day_i` — and
  `_split_kdt` publishes `__kdt_day` and `__kdt_dow` so its callers need neither
  `_floor_day` nor `_weekday_iso`;
* the **caller** went from "one fork per read, always" to a fork-free direct
  call, which is the point of decision D3 and is worth far more than either.

No external process is spawned on any hot path (`bench.sh` runs the check under
`PATH=''`).

## Tests

```bash
bash tests/tests.sh                    # 444 assertions across 24 files
bash tests/tests.sh 019                # one file
KCL_SLOW_TESTS=1 bash tests/tests.sh 024   # the FULL perl calendar sweep
```

`024_IsoWeekSweep.sh` cross-checks the ISO week/year/weekday, the day of the
year, the `encodeDateWeek`∘`decodeDateWeek` round trip and `weeksInAYear`
against perl's `%G %V %u %j`. By default it samples every 37th day of
1900…2100 (~2000 days, a few seconds); with **`KCL_SLOW_TESTS=1`** it walks all
73 414 days, which is the reviewer's original `repro/g3/r3_isoweek.sh` sweep
turned into a regression test.

## Out of scope

Mac/DOS timestamps, `TDateTimeHelper`/`TTimeZone` sugar, and the full
`ScanDateTime` matcher (month/day names, am/pm, `[]` optionals) are intentionally
not ported — see [PLAN.md](PLAN.md) §3.
