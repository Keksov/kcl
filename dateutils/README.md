# dateutils — Free Pascal `DateUtils` for bash

A faithful bash port of FPC's `DateUtils` unit as a kcl [kklass](../../kklass)
Pascal-DSL **static utility class**: 185 public methods called as
`dateutils.<Method>`. Pure-bash integer arithmetic, **zero `date` forks** on the
hot paths, thin (capture-free) dispatch on bash 5.2 and 5.3 alike.

- Design & rationale: [PLAN.md](PLAN.md) · status: [dateutils_ledger.json](dateutils_ledger.json)
- Test-coverage analysis: [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)

```bash
source /path/to/kcl/dateutils/dateutils.sh

kdt=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)   # a "KDT" integer
dateutils.dayOfTheWeek "$kdt"                             # 6   (ISO: Sat)
dateutils.incMonth "$kdt" 1                               # KDT of 2011-04-26 …
read -r y m d <<< "$(dateutils.decodeDate "$kdt")"       # y=2011 m=3 d=26
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

| Result kind | How it is returned |
|---|---|
| KDT / integer | echoed as a plain number |
| Boolean | echoes `true` / `false` |
| multi-field decode | space-separated fields, read with `read -r a b c …` |
| `try*` | echoes the value and returns 0 on success; **echoes nothing, returns 1** on failure |
| `*Span` | fixed-point decimal string, 6 places (e.g. `1.500000`) |
| `compare*` | echoes `-1` / `0` / `1` |
| errors (invalid date, bad parse) | **return 1**, echo nothing; a message goes to stderr only under `VERBOSE_KKLASS=debug` |
| `recode*` "leave field" | pass the literal `-` for a field to keep it |
| offsets (`localTimeToUniversal`, …) | minutes **east** of UTC (`+180` = UTC+3), or an ISO `±hh:mm` / `Z` string |
| `isoTZStrToTZOffset` only | **FPC sign** — `+03:00` → `-180` (kept for parity) |

Invalid inputs to the non-`try` encoders (`encodeDate`, `recodeMonth`, …) return
1 where FPC would raise `EConvertError` (bash has no exceptions).

---

## Wall clock & constructors

| Signature | Echoes | Example |
|---|---|---|
| `now` | KDT (local wall clock) | `dateutils.now` |
| `nowUTC` | KDT (UTC wall clock) | `dateutils.nowUTC` |
| `today` / `yesterday` / `tomorrow` | KDT at 00:00 | `dateutils.today` |
| `dateOf <kdt>` | KDT with time zeroed | `dateutils.dateOf "$k"` |
| `timeOf <kdt>` | ms-of-day (0…86399999) | `dateutils.timeOf "$k"` |

## Encode / decode

| Signature | Echoes |
|---|---|
| `encodeDate <y> <m> <d>` · `tryEncodeDate …` | KDT (00:00) |
| `encodeTime <h> <n> <s> <ms>` · `tryEncodeTime …` | ms-of-day (`24:00:00.000` → 86400000) |
| `encodeDateTime <y> <m> <d> <h> <n> <s> <ms>` · `tryEncodeDateTime …` | KDT |
| `decodeDate <kdt>` | `Y M D` |
| `decodeTime <kdt>` | `H N S MS` |
| `decodeDateTime <kdt>` | `Y M D H N S MS` |
| `encodeDateDay <y> <dayOfYear>` · `tryEncodeDateDay …` | KDT |
| `decodeDateDay <kdt>` | `Y DayOfYear` |

```bash
dateutils.encodeDate 2000 2 29           # a leap-day KDT
dateutils.encodeDate 2011 2 29 || echo bad   # -> bad  (status 1)
read -r y d <<< "$(dateutils.decodeDateDay "$(dateutils.encodeDate 2011 3 26)")"  # y=2011 d=85
```

## Validity & calendar sizes

| Signature | Echoes |
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

| Signature | Echoes |
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

| Signature | Echoes |
|---|---|
| `incYear/Month/Week/Day/Hour/Minute/Second/MilliSecond <kdt> [n=1]` | KDT |

`incMonth`/`incYear` clamp the day (Jan 31 +1m → Feb 28/29; Feb 29 +1y → Feb 28).

## Differences, spans & comparison

| Signature | Echoes |
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

| Signature | Echoes |
|---|---|
| `recodeYear/Month/Day/Hour/Minute/Second/MilliSecond <kdt> <value>` | KDT |
| `recodeDate <kdt> <y> <m> <d>` · `recodeTime <kdt> <h> <n> <s> <ms>` | KDT |
| `recodeDateTime <kdt> <y> <m> <d> <h> <n> <s> <ms>` · `tryRecodeDateTime …` | KDT |

Pass `-` for any field to keep it: `recodeDateTime "$k" - 6 - - - 0 -` sets month=6, second=0.

## Week-date & day-of-week-in-month encodings

| Signature | Echoes |
|---|---|
| `encodeDateWeek <y> <week> [dow=1]` · `tryEncodeDateWeek …` | KDT |
| `decodeDateWeek <kdt>` | `Y Week Dow` (ISO) |
| `encodeDateMonthWeek <y> <m> <wom> <dow>` · `tryEncodeDateMonthWeek …` | KDT |
| `decodeDateMonthWeek <kdt>` | `Y M WeekOfMonth Dow` |
| `encodeDayOfWeekInMonth <y> <m> <nth> <dow>` · `tryEncodeDayOfWeekInMonth …` | KDT (Nth ≥ 1; no "last" form) |

## Conversions & time zones

| Signature | Echoes |
|---|---|
| `dateTimeToUnix <kdt> [inputIsUTC=true]` | Unix seconds |
| `unixToDateTime <sec> [returnUTC=true]` | KDT |
| `dateTimeToJulianDate <kdt>` · `dateTimeToModifiedJulianDate <kdt>` | 6-dp JD / MJD string |
| `julianDateToDateTime <jd>` · `tryJulianDateToDateTime …` | KDT |
| `modifiedJulianDateToDateTime <mjd>` · `tryModifiedJulianDateToDateTime …` | KDT |
| `localTimeToUniversal <kdt> [offset]` · `universalTimeToLocal <kdt> [offset]` | KDT (offset = minutes east or `±hh:mm`) |
| `encodeTimeInterval <h> <n> <s> <ms>` · `tryEncodeTimeInterval …` | ms (hours may exceed 24) |
| `dateToISO8601 <kdt> [inputIsUTC=true]` | `YYYY-MM-DDThh:mm:ss.zzzZ` (or `±hh:mm`) |
| `iso8601ToDate <str> [returnUTC=true]` · `tryISO8601ToDate …` · `iso8601ToDateDef <str> <default> [returnUTC]` | KDT |
| `tryISOStrToDate <str>` | KDT (00:00) — accepts `YYYY`, `YYYYMM`, `YYYY-MM`, `YYYYMMDD`, `YYYY-MM-DD` |
| `tryISOStrToTime <str>` | ms-of-day |
| `tryISOStrToDateTime <str>` | KDT (naive, as written) |
| `isoTZStrToTZOffset <tz>` · `tryISOTZStrToTZOffset <tz>` | minutes (**FPC sign**: `+03:00` → `-180`) |

```bash
dateutils.julianDateToDateTime 2455277.5        # KDT of 2010-03-22 00:00
dateutils.unixToDateTime 0                       # KDT 0 = 1970-01-01
dateutils.iso8601ToDate 2010-03-22T09:00:00.000+03:00   # -> 2010-03-22 06:00 UTC
```

> **Julian precision:** JD/MJD strings carry 6 decimals (≈ 86 ms). Midnight and
> noon are exact; other times of day round-trip to within one ulp.

## Parsing: scanDateTime

`scanDateTime <pattern> <input>` → KDT (status 1 on mismatch). Case-insensitive
tokens: `yyyy`/`yy` year, `mm` month, `dd` day, `hh` hour, **`nn` minute**, `ss`
second, `zzz` millisecond. `'literals'`/`"literals"` match verbatim; whitespace
is elastic; other characters must match exactly. Two-digit years pivot at 50;
unset fields default to the epoch.

```bash
dateutils.scanDateTime 'YYYY.MM.DD HH:NN:SS:ZZZ' '2011.03.29 16:46:56:777'   # KDT of that instant
dateutils.scanDateTime 'dd/mm/yyyy' '26/03/2011'
```

## Constants (getters)

`msPerSecond` `msPerMinute` `msPerHour` `msPerDay` `msPerWeek`
`approxMsPerMonth` `approxMsPerYear` `approxDaysPerMonth` (`30.4375`)
`approxDaysPerYear` (`365.25`). The backing `__KDT_*` globals are `readonly`.

## Out of scope

Mac/DOS timestamps, `TDateTimeHelper`/`TTimeZone` sugar, and the full
`ScanDateTime` matcher (month/day names, am/pm, `[]` optionals) are intentionally
not ported — see [PLAN.md](PLAN.md) §3.
