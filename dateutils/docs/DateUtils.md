# FPC `DateUtils` — API Reference (kcl bash port)

This is the Free Pascal RTL **`DateUtils`** unit API reference for the kcl
[`dateutils`](../README.md) bash port. Every Pascal signature below is copied
verbatim from the FPC RTL source
(`packages/rtl-objpas/src/inc/dateutil.inc`); a handful of routines the port
also exposes are declared in FPC's **`SysUtils`** and are marked **(SysUtils)**
after the name. Behavior, echo formats, and the FPC quirks follow the port's
[README](../README.md), which is the authoritative source of truth for how each
`dateutils.<method>` behaves.

In the port every `TDateTime` argument and result (marked *KDT* in the README)
is a single **integer: milliseconds since 1970-01-01 00:00:00, naive (no
timezone), proleptic Gregorian.** A *time-of-day* is just the millisecond offset
within a day (`0 … 86399999`); a *duration* is a plain millisecond count. See
the README's "KDT contract" for the full model. `try*` methods echo the value
and return 0 on success, or echo nothing and return 1 on failure; non-`try`
encoders return 1 where FPC would raise `EConvertError`.

---

## Wall clock & constructors

### `DateUtils.Now` (SysUtils) · `DateUtils.NowUTC` (SysUtils)

```pascal
function Now: TDateTime;
function NowUTC: TDateTime;
```

Return the current date and time. `Now` reads the local wall clock; `NowUTC`
returns UTC (falling back to local if the OS cannot supply UTC). The port sources
the wall clock from the `EPOCHREALTIME` builtin and the local offset from
`printf '%(%z)T'` — no `date` subprocess is spawned.

**kcl:** `dateutils.now` — KDT (local wall clock) · `dateutils.nowUTC` — KDT (UTC wall clock)

[FPC docs](https://www.freepascal.org/docs-html/rtl/sysutils/now.html)

---

### `DateUtils.Today` · `DateUtils.Yesterday` · `DateUtils.Tomorrow`

```pascal
Function Today: TDateTime; inline;
Function Yesterday: TDateTime;
Function Tomorrow: TDateTime;
```

The current local date with the time-of-day zeroed (`Today`), the day before it
(`Yesterday`), and the day after it (`Tomorrow`).

**kcl:** `dateutils.today` / `dateutils.yesterday` / `dateutils.tomorrow` — KDT at 00:00

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/today.html)

---

### `DateUtils.DateOf` · `DateUtils.TimeOf`

```pascal
Function DateOf(const AValue: TDateTime): TDateTime; inline;
Function TimeOf(const AValue: TDateTime): TDateTime; inline;
```

`DateOf` strips the time, returning the date at midnight (`Int` of the value);
`TimeOf` strips the date, returning the time-of-day (`Frac` of the value). In KDT
terms `dateOf` zeroes the intraday milliseconds and `timeOf` echoes the
millisecond offset within the day (`0 … 86399999`).

**kcl:** `dateutils.dateOf <kdt>` — KDT with time zeroed · `dateutils.timeOf <kdt>` — ms-of-day

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/dateof.html)

---

## Encode / decode

### `DateUtils.EncodeDate` (SysUtils) · `DateUtils.TryEncodeDate` (SysUtils)

```pascal
function EncodeDate(Year, Month, Day :word): TDateTime;
function TryEncodeDate(Year, Month, Day: Word; out Date: TDateTime): Boolean;
```

Build a date (time = 00:00) from calendar fields. `EncodeDate` returns 1 in the
port where FPC raises `EConvertError` on an out-of-range date; `TryEncodeDate`
signals failure instead of raising.

**kcl:** `dateutils.encodeDate <y> <m> <d>` · `dateutils.tryEncodeDate …` — KDT (00:00) · e.g. `dateutils.encodeDate 2000 2 29`

[FPC docs](https://www.freepascal.org/docs-html/rtl/sysutils/encodedate.html)

---

### `DateUtils.EncodeTime` (SysUtils) · `DateUtils.TryEncodeTime` (SysUtils)

```pascal
function EncodeTime(Hour, Minute, Second, MilliSecond:word): TDateTime;
function TryEncodeTime(Hour, Min, Sec, MSec: Word; out Time: TDateTime): Boolean;
```

Build a time-of-day fraction from clock fields. In the port the result is the
millisecond offset within a day; the special valid time `24:00:00.000` encodes to
`86400000`.

**kcl:** `dateutils.encodeTime <h> <n> <s> <ms>` · `dateutils.tryEncodeTime …` — ms-of-day

[FPC docs](https://www.freepascal.org/docs-html/rtl/sysutils/encodetime.html)

---

### `DateUtils.EncodeDateTime` · `DateUtils.TryEncodeDateTime`

```pascal
Function EncodeDateTime(const AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word): TDateTime;
Function TryEncodeDateTime(const AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word; out AValue: TDateTime): Boolean;
```

Combine calendar and clock fields into a full timestamp. `EncodeDateTime` returns
1 on an invalid field set; `TryEncodeDateTime` echoes the KDT and returns 0, or
returns 1 without echoing.

**kcl:** `dateutils.encodeDateTime <y> <m> <d> <h> <n> <s> <ms>` · `dateutils.tryEncodeDateTime …` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodedatetime.html)

---

### `DateUtils.DecodeDate` (SysUtils) · `DateUtils.DecodeTime` (SysUtils) · `DateUtils.DecodeDateTime`

```pascal
procedure DecodeDate(Date: TDateTime; out Year, Month, Day: word);
procedure DecodeTime(Time: TDateTime; out Hour, Minute, Second, MilliSecond: word);
Procedure DecodeDateTime(const AValue: TDateTime; out AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word);
```

Split a KDT into its component fields. The port returns the fields
space-separated for `read -r`.

**kcl:** `dateutils.decodeDate <kdt>` → `Y M D` · `dateutils.decodeTime <kdt>` → `H N S MS` · `dateutils.decodeDateTime <kdt>` → `Y M D H N S MS`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/decodedatetime.html)

---

### `DateUtils.EncodeDateDay` · `DateUtils.TryEncodeDateDay` · `DateUtils.DecodeDateDay`

```pascal
Function EncodeDateDay(const AYear, ADayOfYear: Word): TDateTime;
Function TryEncodeDateDay(const AYear, ADayOfYear: Word; out AValue: TDateTime): Boolean;
Procedure DecodeDateDay(const AValue: TDateTime; out AYear, ADayOfYear: Word);
```

Encode/decode a date by its **ordinal day of the year** (1 = Jan 1). Day 60 of a
leap year is Feb 29.

**kcl:** `dateutils.encodeDateDay <y> <dayOfYear>` · `dateutils.tryEncodeDateDay …` — KDT · `dateutils.decodeDateDay <kdt>` → `Y DayOfYear`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodedateday.html)

---

## Validity & calendar sizes

### `DateUtils.IsValidDate` · `IsValidTime` · `IsValidDateTime` · `IsValidDateDay` · `IsValidDateWeek` · `IsValidDateMonthWeek`

```pascal
Function IsValidDate(const AYear, AMonth, ADay: Word): Boolean;
Function IsValidTime(const AHour, AMinute, ASecond, AMilliSecond: Word): Boolean;
Function IsValidDateTime(const AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word): Boolean;
Function IsValidDateDay(const AYear, ADayOfYear: Word): Boolean;
Function IsValidDateWeek(const AYear, AWeekOfYear, ADayOfWeek: Word): Boolean;
Function IsValidDateMonthWeek(const AYear, AMonth, AWeekOfMonth, ADayOfWeek: Word): Boolean;
```

Range-check field sets without raising. Valid years are `1 … 9999`.
**FPC quirk:** `IsValidTime` treats `24:00:00.000` as valid (the end-of-day
sentinel) in addition to the normal `00:00:00.000 … 23:59:59.999` range.
`IsValidDateWeek` validates ISO-8601 week numbers (a year has 52 or 53 weeks);
`IsValidDateMonthWeek` accepts a week-of-month `1 … 5` and day-of-week `1 … 7`.

**kcl:** `dateutils.isValidDate <y> <m> <d>` etc. — echo `true` / `false` · e.g. `dateutils.isValidTime 24 0 0 0` → `true`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/isvaliddate.html)

---

### `DateUtils.IsInLeapYear`

```pascal
Function IsInLeapYear(const AValue: TDateTime): Boolean;
```

Whether the **year of the given date** is a leap year. **FPC quirk:** the
argument is a date/KDT, not a bare year number — it is `IsLeapYear(YearOf(AValue))`.

**kcl:** `dateutils.isInLeapYear <kdt>` — `true` / `false` (of the date's year)

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/isinleapyear.html)

---

### `DateUtils.DaysInAMonth` · `DaysInMonth` · `DaysInAYear` · `DaysInYear` · `WeeksInAYear` · `WeeksInYear`

```pascal
Function DaysInAMonth(const AYear, AMonth: Word): Word;
Function DaysInMonth(const AValue: TDateTime): Word;
Function DaysInAYear(const AYear: Word): Word;
Function DaysInYear(const AValue: TDateTime): Word;
Function WeeksInAYear(const AYear: Word): Word;
Function WeeksInYear(const AValue: TDateTime): Word;
```

Calendar sizes. The `…InA…` forms take bare numbers; the `…In…` forms take a
KDT and derive the year/month from it. `DaysIn(A)Year` is 365 or 366;
`WeeksIn(A)Year` is 52 or 53 per **ISO-8601** (a year has 53 weeks when it starts
on a Thursday, or on a Wednesday in a leap year).

**kcl:** `dateutils.daysInAMonth <y> <m>` · `dateutils.daysInMonth <kdt>` · `dateutils.weeksInAYear <y>` … — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/daysinamonth.html)

---

## Extraction

All extraction functions take a KDT and echo an integer.

### `DateUtils.YearOf` · `MonthOf` · `DayOf` · `HourOf` · `MinuteOf` · `SecondOf` · `MilliSecondOf`

```pascal
Function YearOf(const AValue: TDateTime): Word;
Function MonthOf(const AValue: TDateTime): Word;
Function DayOf(const AValue: TDateTime): Word;
Function HourOf(const AValue: TDateTime): Word;
Function MinuteOf(const AValue: TDateTime): Word;
Function SecondOf(const AValue: TDateTime): Word;
Function MilliSecondOf(const AValue: TDateTime): Word;
```

The individual calendar/clock fields of the timestamp.

**kcl:** `dateutils.yearOf <kdt>` … `dateutils.milliSecondOf <kdt>` — the field as an integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/yearof.html)

---

### `DateUtils.MonthOfTheYear` · `DayOfTheMonth` · `HourOfTheDay` · `MinuteOfTheHour` · `SecondOfTheMinute` · `MilliSecondOfTheSecond`

```pascal
Function MonthOfTheYear(const AValue: TDateTime): Word; inline;
Function DayOfTheMonth(const AValue: TDateTime): Word;
Function HourOfTheDay(const AValue: TDateTime): Word; inline;
Function MinuteOfTheHour(const AValue: TDateTime): Word; inline;
Function SecondOfTheMinute(const AValue: TDateTime): Word; inline;
Function MilliSecondOfTheSecond(const AValue: TDateTime): Word; inline;
```

Verbose aliases for the plain field extractors above (`MonthOfTheYear` ≡
`MonthOf`, `HourOfTheDay` ≡ `HourOf`, and so on).

**kcl:** `dateutils.monthOfTheYear <kdt>` · `dateutils.dayOfTheMonth <kdt>` · `dateutils.hourOfTheDay <kdt>` … — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/monthoftheyear.html)

---

### `DateUtils.DayOfTheWeek`

```pascal
Function DayOfTheWeek(const AValue: TDateTime): Word;
```

The **ISO-8601** day of the week: Monday = 1 … Sunday = 7 (unlike SysUtils'
`DayOfWeek`, which is Sunday = 1).

**kcl:** `dateutils.dayOfTheWeek <kdt>` — 1…7 (Mon…Sun) · e.g. `dateutils.dayOfTheWeek "$(dateutils.encodeDate 1970 1 1)"` → `4`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/dayoftheweek.html)

---

### `DateUtils.DayOfTheYear`

```pascal
Function DayOfTheYear(const AValue: TDateTime): Word;
```

The ordinal day within the year, 1 = Jan 1.

**kcl:** `dateutils.dayOfTheYear <kdt>` — 1…366

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/dayoftheyear.html)

---

### `DateUtils.WeekOf` · `WeekOfTheYear` · `WeekOfTheMonth`

```pascal
Function WeekOf(const AValue: TDateTime): Word; inline;
Function WeekOfTheYear(const AValue: TDateTime): Word; overload;
Function WeekOfTheYear(const AValue: TDateTime; out AYear: Word): Word; overload;
Function WeekOfTheMonth(const AValue: TDateTime): Word; overload;
Function WeekOfTheMonth(const AValue: TDateTime; out AYear, AMonth: Word): Word; overload;
```

**ISO-8601** week numbers. `WeekOf` is an alias for `WeekOfTheYear`. A date early
in January may belong to the last ISO week (52/53) of the *previous* year — e.g.
2005-01-01 is week 53 of ISO-year 2004. The port's `weekOf`/`weekOfTheYear` echo
that ISO week number; `weekOfTheMonth` echoes the week ordinal within the month.

**kcl:** `dateutils.weekOf <kdt>` · `dateutils.weekOfTheYear <kdt>` · `dateutils.weekOfTheMonth <kdt>` — integer · e.g. `dateutils.weekOfTheYear "$(dateutils.encodeDate 2005 1 1)"` → `53`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/weekoftheyear.html)

---

### `DateUtils.IsAM` · `DateUtils.IsPM`

```pascal
function IsAM(const AValue: TDateTime): Boolean; inline;
Function IsPM(const AValue: TDateTime): Boolean; inline;
```

`IsAM` is true for hours `0 … 11`; `IsPM` is true for hours `12 … 23`.

**kcl:** `dateutils.isAM <kdt>` · `dateutils.isPM <kdt>` — `true` / `false`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/isam.html)

---

### `DateUtils.MinuteOfTheDay` · `SecondOfTheDay` · `MilliSecondOfTheDay`

```pascal
Function MinuteOfTheDay(const AValue: TDateTime): Word;
Function SecondOfTheDay(const AValue: TDateTime): LongWord;
Function MilliSecondOfTheDay(const AValue: TDateTime): LongWord;
```

Elapsed minutes / seconds / milliseconds since the start of the day (midnight).

**kcl:** `dateutils.minuteOfTheDay <kdt>` · `dateutils.secondOfTheDay <kdt>` · `dateutils.milliSecondOfTheDay <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/minuteoftheday.html)

---

### `DateUtils.SecondOfTheHour` · `MilliSecondOfTheHour`

```pascal
Function SecondOfTheHour(const AValue: TDateTime): Word;
Function MilliSecondOfTheHour(const AValue: TDateTime): LongWord;
```

Elapsed seconds / milliseconds since the top of the hour.

**kcl:** `dateutils.secondOfTheHour <kdt>` · `dateutils.milliSecondOfTheHour <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/secondofthehour.html)

---

### `DateUtils.MilliSecondOfTheMinute`

```pascal
Function MilliSecondOfTheMinute(const AValue: TDateTime): LongWord;
```

Elapsed milliseconds since the start of the current minute (`Second*1000 + MS`).

**kcl:** `dateutils.milliSecondOfTheMinute <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/millisecondoftheminute.html)

---

### `DateUtils.HourOfTheWeek` · `MinuteOfTheWeek` · `SecondOfTheWeek` · `MilliSecondOfTheWeek`

```pascal
Function HourOfTheWeek(const AValue: TDateTime): Word;
Function MinuteOfTheWeek(const AValue: TDateTime): Word;
Function SecondOfTheWeek(const AValue: TDateTime): LongWord;
Function MilliSecondOfTheWeek(const AValue: TDateTime): LongWord;
```

Elapsed hours / minutes / seconds / milliseconds since the start of the ISO week
(Monday 00:00), computed from `DayOfTheWeek` (Mon = 1).

**kcl:** `dateutils.hourOfTheWeek <kdt>` … `dateutils.milliSecondOfTheWeek <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/houroftheweek.html)

---

### `DateUtils.HourOfTheMonth` · `MinuteOfTheMonth` · `SecondOfTheMonth` · `MilliSecondOfTheMonth`

```pascal
Function HourOfTheMonth(const AValue: TDateTime): Word;
Function MinuteOfTheMonth(const AValue: TDateTime): Word;
Function SecondOfTheMonth(const AValue: TDateTime): LongWord;
Function MilliSecondOfTheMonth(const AValue: TDateTime): LongWord;
```

Elapsed hours / minutes / seconds / milliseconds since the start of the month
(day 1, 00:00).

**kcl:** `dateutils.hourOfTheMonth <kdt>` … `dateutils.milliSecondOfTheMonth <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/hourofthemonth.html)

---

### `DateUtils.HourOfTheYear` · `MinuteOfTheYear` · `SecondOfTheYear` · `MilliSecondOfTheYear`

```pascal
Function HourOfTheYear(const AValue: TDateTime): Word;
Function MinuteOfTheYear(const AValue: TDateTime): LongWord;
Function SecondOfTheYear(const AValue: TDateTime): LongWord;
Function MilliSecondOfTheYear(const AValue: TDateTime): Int64;
```

Elapsed hours / minutes / seconds / milliseconds since the start of the year
(Jan 1, 00:00).

**kcl:** `dateutils.hourOfTheYear <kdt>` … `dateutils.milliSecondOfTheYear <kdt>` — integer

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/houroftheyear.html)

---

### `DateUtils.NthDayOfWeek` · `DateUtils.DecodeDayOfWeekInMonth`

```pascal
Function NthDayOfWeek(const AValue: TDateTime): Word;
Procedure DecodeDayOfWeekInMonth(const AValue: TDateTime; out AYear, AMonth, ANthDayOfWeek, ADayOfWeek: Word);
```

`NthDayOfWeek` answers "which occurrence of its weekday within the month is this
date?" — e.g. the second Thursday returns 2. `DecodeDayOfWeekInMonth` unpacks the
date into year, month, that Nth-occurrence count, and the ISO day-of-week.

**kcl:** `dateutils.nthDayOfWeek <kdt>` — 1…5 · `dateutils.decodeDayOfWeekInMonth <kdt>` → `Y M Nth Dow`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/nthdayofweek.html)

---

## Start / end of period & day predicates

Week boundaries are **ISO** (Monday … Sunday). `endOfTheX` equals
`startOfNext(X) − 1 ms`: starts are at 00:00, ends at 23:59:59.999.

### `DateUtils.StartOfTheYear` · `EndOfTheYear` · `StartOfAYear` · `EndOfAYear`

```pascal
Function StartOfTheYear(const AValue: TDateTime): TDateTime;
Function EndOfTheYear(const AValue: TDateTime): TDateTime;
Function StartOfAYear(const AYear: Word): TDateTime;
Function EndOfAYear(const AYear: Word): TDateTime;
```

First/last instant of a year. The `…TheYear` forms take a KDT and use its year;
the `…AYear` forms take a bare year number.

**kcl:** `dateutils.startOfTheYear <kdt>` · `dateutils.endOfTheYear <kdt>` · `dateutils.startOfAYear <y>` · `dateutils.endOfAYear <y>` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/startoftheyear.html)

---

### `DateUtils.StartOfTheMonth` · `EndOfTheMonth` · `StartOfAMonth` · `EndOfAMonth`

```pascal
Function StartOfTheMonth(const AValue: TDateTime): TDateTime;
Function EndOfTheMonth(const AValue: TDateTime): TDateTime;
Function StartOfAMonth(const AYear, AMonth: Word): TDateTime; inline;
Function EndOfAMonth(const AYear, AMonth: Word): TDateTime;
```

First/last instant of a month; the end lands on the correct last day (28/29/30/31).

**kcl:** `dateutils.startOfTheMonth <kdt>` · `dateutils.endOfTheMonth <kdt>` · `dateutils.startOfAMonth <y> <m>` · `dateutils.endOfAMonth <y> <m>` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/startofthemonth.html)

---

### `DateUtils.StartOfTheWeek` · `EndOfTheWeek` · `StartOfAWeek` · `EndOfAWeek`

```pascal
Function StartOfTheWeek(const AValue: TDateTime): TDateTime;
Function EndOfTheWeek(const AValue: TDateTime): TDateTime;
Function StartOfAWeek(const AYear, AWeekOfYear: Word; const ADayOfWeek: Word): TDateTime;
Function StartOfAWeek(const AYear, AWeekOfYear: Word): TDateTime; inline; // ADayOFWeek 1
Function EndOfAWeek(const AYear, AWeekOfYear: Word; const ADayOfWeek: Word): TDateTime; inline;
Function EndOfAWeek(const AYear, AWeekOfYear: Word): TDateTime; // const ADayOfWeek: Word = 7
```

Boundaries of an ISO week. `…TheWeek` uses the ISO Monday-to-Sunday week
containing the given KDT. The `…AWeek` forms take an ISO year, week number, and
optional day-of-week (default 1 = Monday for start, 7 = Sunday for end).

**kcl:** `dateutils.startOfTheWeek <kdt>` · `dateutils.endOfTheWeek <kdt>` · `dateutils.startOfAWeek <y> <week> [dow=1]` · `dateutils.endOfAWeek <y> <week> [dow=7]` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/startoftheweek.html)

---

### `DateUtils.StartOfTheDay` · `EndOfTheDay` · `StartOfADay` · `EndOfADay`

```pascal
Function StartOfTheDay(const AValue: TDateTime): TDateTime; inline;
Function EndOfTheDay(const AValue: TDateTime): TDateTime;
Function StartOfADay(const AYear, AMonth, ADay: Word): TDateTime; overload; inline;
Function StartOfADay(const AYear, ADayOfYear: Word): TDateTime; overload;
Function EndOfADay(const AYear, AMonth, ADay: Word): TDateTime; overload; inline;
Function EndOfADay(const AYear, ADayOfYear: Word): TDateTime; overload;
```

First/last instant of a day. The `…ADay` forms are overloaded: pass `<y> <m> <d>`
(calendar day) **or** `<y> <doy>` (ordinal day of year).

**kcl:** `dateutils.startOfADay <y> <m> <d>` **or** `<y> <doy>` · `dateutils.endOfADay …` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/startoftheday.html)

---

### `DateUtils.IsToday` · `DateUtils.IsSameDay` · `DateUtils.IsSameMonth`

```pascal
Function IsToday(const AValue: TDateTime): Boolean;
Function IsSameDay(const AValue, ABasis: TDateTime): Boolean;
function IsSameMonth(const Avalue, ABasis: TDateTime): Boolean;
```

`IsToday` tests whether the value falls on the current local date. `IsSameDay`
tests whether `AValue` lies within the calendar day of `ABasis` (`[Basis,
Basis+1)`). `IsSameMonth` tests same year *and* same month.

**kcl:** `dateutils.isToday <kdt>` · `dateutils.isSameDay <kdt> <basis>` · `dateutils.isSameMonth <a> <b>` — `true` / `false`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/issameday.html)

---

### `DateUtils.PreviousDayOfWeek`

```pascal
Function PreviousDayOfWeek (DayOfWeek : Word) : Word;
```

**FPC quirk:** the argument is an ISO weekday **number** (1 … 7), *not* a date.
It returns the ISO number of the day before it (1→7, 2→1, 3→2, …). FPC raises
`EConvertError` for values outside 1 … 7; the port returns status 1 (echoing
nothing) instead.

**kcl:** `dateutils.previousDayOfWeek <dow>` — prior ISO weekday (1…7)

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/previousdayofweek.html)

---

## Arithmetic (Inc*)

### `DateUtils.IncYear` · `IncMonth` (SysUtils) · `IncWeek` · `IncDay` · `IncHour` · `IncMinute` · `IncSecond` · `IncMilliSecond`

```pascal
Function IncYear(const AValue: TDateTime; const ANumberOfYears: Integer ): TDateTime;
Function IncYear(const AValue: TDateTime): TDateTime; // ; const ANumberOfYears: Integer = 1)
function IncMonth(const DateTime: TDateTime; NumberOfMonths: integer = 1 ): TDateTime;
Function IncWeek(const AValue: TDateTime; const ANumberOfWeeks: Integer): TDateTime;
Function IncWeek(const AValue: TDateTime): TDateTime; // ; const ANumberOfWeeks: Integer = 1)
Function IncDay(const AValue: TDateTime; const ANumberOfDays: Integer): TDateTime;
Function IncDay(const AValue: TDateTime): TDateTime; //; const ANumberOfDays: Integer = 1)
Function IncHour(const AValue: TDateTime; const ANumberOfHours: Int64): TDateTime;
Function IncHour(const AValue: TDateTime): TDateTime; //; const ANumberOfHours: Int64 = 1
Function IncMinute(const AValue: TDateTime; const ANumberOfMinutes: Int64): TDateTime;
Function IncMinute(const AValue: TDateTime): TDateTime; // ; const ANumberOfMinutes: Int64 = 1
Function IncSecond(const AValue: TDateTime; const ANumberOfSeconds: Int64): TDateTime;
Function IncSecond(const AValue: TDateTime): TDateTime; // ; const ANumberOfSeconds: Int64 = 1
Function IncMilliSecond(const AValue: TDateTime; const ANumberOfMilliSeconds: Int64): TDateTime;
Function IncMilliSecond(const AValue: TDateTime): TDateTime; // ; const ANumberOfMilliSeconds: Int64 = 1
```

Add (or, with a negative count, subtract) a number of the named units to a KDT;
the count defaults to 1. `IncMonth` (declared in SysUtils) and `IncYear` do
**calendar** arithmetic and clamp the day when the target month is shorter — Jan 31
`+1` month → Feb 28/29, and Feb 29 `+1` year → Feb 28. `IncWeek`/`IncDay`/
`IncHour`/`IncMinute`/`IncSecond`/`IncMilliSecond` are exact fixed-duration
offsets.

**kcl:** `dateutils.incYear <kdt> [n=1]` · `dateutils.incMonth <kdt> [n=1]` … `dateutils.incMilliSecond <kdt> [n=1]` — KDT · e.g. `dateutils.incMonth "$k" 1`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/incyear.html)

---

## Differences, spans & comparison

### `DateUtils.YearsBetween` · `MonthsBetween` · `WeeksBetween` · `DaysBetween` · `HoursBetween` · `MinutesBetween` · `SecondsBetween` · `MilliSecondsBetween`

```pascal
Function YearsBetween(const ANow, AThen: TDateTime; AExact : Boolean = False): Integer;
Function MonthsBetween(const ANow, AThen: TDateTime; AExact : Boolean = False): Integer;
Function WeeksBetween(const ANow, AThen: TDateTime): Integer;
Function DaysBetween(const ANow, AThen: TDateTime): Integer;
Function HoursBetween(const ANow, AThen: TDateTime): Int64;
Function MinutesBetween(const ANow, AThen: TDateTime): Int64;
Function SecondsBetween(const ANow, AThen: TDateTime): Int64;
Function MilliSecondsBetween(const ANow, AThen: TDateTime): Int64;
```

The number of **whole** units between two instants (order-independent — the
result is unsigned). `YearsBetween` and `MonthsBetween` are **approximate by
default** (dividing the elapsed time by `ApproxDaysPerYear` / `ApproxDaysPerMonth`);
pass `exact` for calendar-true counts. The others are exact duration divisions.

**kcl:** `dateutils.yearsBetween <a> <b> [exact]` · `dateutils.monthsBetween <a> <b> [exact]` · `dateutils.daysBetween <a> <b>` … — integer · e.g. `dateutils.yearsBetween "$a" "$b" exact`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/yearsbetween.html)

---

### `DateUtils.PeriodBetween`

```pascal
Procedure PeriodBetween(const ANow, AThen: TDateTime; Out Years, months, days : Word);
```

Decomposes the gap between two dates into calendar years, months, and days
(a mixed-radix breakdown rather than a single unit count).

**kcl:** `dateutils.periodBetween <a> <b>` → `Years Months Days`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/periodbetween.html)

---

### `DateUtils.DateTimeDiff` (kcl helper)

```pascal
{ no FPC DateUtils function — plain TDateTime subtraction, A - B }
```

A port-specific convenience: the **signed** millisecond difference `a − b`
(positive when `a` is later). Unlike `MilliSecondsBetween`, which is unsigned, this
preserves direction. There is no corresponding named function in FPC `DateUtils`
(in Pascal it is simply the expression `A - B`).

**kcl:** `dateutils.dateTimeDiff <a> <b>` — signed ms (`a - b`)

---

### `DateUtils.YearSpan` · `MonthSpan` · `WeekSpan` · `DaySpan` · `HourSpan` · `MinuteSpan` · `SecondSpan` · `MilliSecondSpan`

```pascal
Function YearSpan(const ANow, AThen: TDateTime): Double;
Function MonthSpan(const ANow, AThen: TDateTime): Double;
Function WeekSpan(const ANow, AThen: TDateTime): Double;
Function DaySpan(const ANow, AThen: TDateTime): Double;
Function HourSpan(const ANow, AThen: TDateTime): Double;
Function MinuteSpan(const ANow, AThen: TDateTime): Double;
Function SecondSpan(const ANow, AThen: TDateTime): Double;
Function MilliSecondSpan(const ANow, AThen: TDateTime): Double;
```

The **fractional** number of units between two instants. `YearSpan` and
`MonthSpan` are approximate (based on `ApproxDaysPerYear` / `ApproxDaysPerMonth`);
the rest are exact. The port echoes a fixed-point decimal with **6 places**.

**kcl:** `dateutils.daySpan <a> <b>` … — 6-dp decimal · e.g. `dateutils.daySpan "$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)" "$(dateutils.encodeDate 2011 3 26)"` → `0.500000`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/dayspan.html)

---

### `DateUtils.WithinPastYears` · `WithinPastMonths` · `WithinPastWeeks` · `WithinPastDays` · `WithinPastHours` · `WithinPastMinutes` · `WithinPastSeconds` · `WithinPastMilliSeconds`

```pascal
Function WithinPastYears(const ANow, AThen: TDateTime; const AYears: Integer): Boolean; inline;
Function WithinPastMonths(const ANow, AThen: TDateTime; const AMonths: Integer): Boolean; inline;
Function WithinPastWeeks(const ANow, AThen: TDateTime; const AWeeks: Integer): Boolean; inline;
Function WithinPastDays(const ANow, AThen: TDateTime; const ADays: Integer): Boolean; inline;
Function WithinPastHours(const ANow, AThen: TDateTime; const AHours: Int64): Boolean; inline;
Function WithinPastMinutes(const ANow, AThen: TDateTime; const AMinutes: Int64): Boolean; inline;
Function WithinPastSeconds(const ANow, AThen: TDateTime; const ASeconds: Int64): Boolean; inline;
Function WithinPastMilliSeconds(const ANow, AThen: TDateTime; const AMilliSeconds: Int64): Boolean; inline;
```

True when the two instants are within the given number of units of each other —
i.e. the corresponding `…Between(ANow, AThen)` count is `<=` the range argument.

**kcl:** `dateutils.withinPastDays <now> <then> <range>` … — `true` / `false`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/withinpastdays.html)

---

### `DateUtils.CompareDateTime` · `DateUtils.CompareDate` · `DateUtils.CompareTime`

```pascal
Function CompareDateTime(const A, B: TDateTime): TValueRelationship;
Function CompareDate(const A, B: TDateTime): TValueRelationship;
Function CompareTime(const A, B: TDateTime): TValueRelationship;
```

Three-way comparison. `CompareDateTime` compares full instants; `CompareDate`
compares only the date portion; `CompareTime` only the time-of-day. The FPC
`TValueRelationship` (`LessThan/Equal/GreaterThan`) maps to the port's `-1` / `0`
/ `1`.

**kcl:** `dateutils.compareDateTime <a> <b>` · `dateutils.compareDate <a> <b>` · `dateutils.compareTime <a> <b>` — `-1` / `0` / `1`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/comparedatetime.html)

---

### `DateUtils.SameDateTime` · `DateUtils.SameDate` · `DateUtils.SameTime`

```pascal
Function SameDateTime(const A, B: TDateTime): Boolean;
Function SameDate(const A, B: TDateTime): Boolean; inline;
Function SameTime(const A, B: TDateTime): Boolean;
```

Equality counterparts of the compare functions — true when the respective
comparison is `0` (same instant / same date / same time-of-day).

**kcl:** `dateutils.sameDateTime <a> <b>` · `dateutils.sameDate <a> <b>` · `dateutils.sameTime <a> <b>` — `true` / `false`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/samedatetime.html)

---

### `DateUtils.DateInRange` · `DateUtils.TimeInRange` · `DateUtils.DateTimeInRange`

```pascal
function DateInRange(ADate: TDate; AStartDate, AEndDate: TDate; AInclusive: Boolean = True): Boolean;
function TimeInRange(ATime: TTime; AStartTime, AEndTime: TTime; AInclusive: Boolean = True): Boolean;
function DateTimeInRange(ADateTime: TDateTime; AStartDateTime, AEndDateTime: TDateTime; aInclusive: Boolean = True): Boolean;
```

Whether a value falls between a start and end bound; `AInclusive` (default true)
controls whether the endpoints count. **`TimeInRange` handles overnight ranges**
(when the end time is before the start time) with OR-logic, so e.g. 22:00 → 02:00
is treated as spanning midnight.

**kcl:** `dateutils.dateInRange <v> <start> <end> [inclusive=true]` · `dateutils.timeInRange …` · `dateutils.dateTimeInRange …` — `true` / `false`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/datetimeinrange.html)

---

## Recode (field surgery)

Pass the literal `-` for any field to leave it unchanged (the port's spelling of
FPC's `RecodeLeaveFieldAsIs` sentinel). Invalid resulting field values return 1
where FPC would raise `EConvertError`.

### `DateUtils.RecodeYear` · `RecodeMonth` · `RecodeDay` · `RecodeHour` · `RecodeMinute` · `RecodeSecond` · `RecodeMilliSecond`

```pascal
Function RecodeYear(const AValue: TDateTime; const AYear: Word): TDateTime;
Function RecodeMonth(const AValue: TDateTime; const AMonth: Word): TDateTime;
Function RecodeDay(const AValue: TDateTime; const ADay: Word): TDateTime;
Function RecodeHour(const AValue: TDateTime; const AHour: Word): TDateTime;
Function RecodeMinute(const AValue: TDateTime; const AMinute: Word): TDateTime;
Function RecodeSecond(const AValue: TDateTime; const ASecond: Word): TDateTime;
Function RecodeMilliSecond(const AValue: TDateTime; const AMilliSecond: Word): TDateTime;
```

Return a copy of the KDT with a single field replaced, leaving the others intact.

**kcl:** `dateutils.recodeYear <kdt> <value>` … `dateutils.recodeMilliSecond <kdt> <value>` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/recodeyear.html)

---

### `DateUtils.RecodeDate` · `DateUtils.RecodeTime`

```pascal
Function RecodeDate(const AValue: TDateTime; const AYear, AMonth, ADay: Word): TDateTime;
Function RecodeTime(const AValue: TDateTime; const AHour, AMinute, ASecond, AMilliSecond: Word): TDateTime;
```

Replace all the date fields (`RecodeDate`) or all the time fields (`RecodeTime`)
at once, keeping the other half.

**kcl:** `dateutils.recodeDate <kdt> <y> <m> <d>` · `dateutils.recodeTime <kdt> <h> <n> <s> <ms>` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/recodedate.html)

---

### `DateUtils.RecodeDateTime` · `DateUtils.TryRecodeDateTime`

```pascal
Function RecodeDateTime(const AValue: TDateTime; const AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word): TDateTime;
Function TryRecodeDateTime(const AValue: TDateTime; const AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word; out AResult: TDateTime): Boolean;
```

Replace any combination of all seven fields in one call; use `-` per field to
keep it. `TryRecodeDateTime` reports validity instead of returning 1.

**kcl:** `dateutils.recodeDateTime <kdt> <y> <m> <d> <h> <n> <s> <ms>` · `dateutils.tryRecodeDateTime …` — KDT · e.g. `dateutils.recodeDateTime "$k" - 6 - - - 0 -` (set month=6, second=0)

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/recodedatetime.html)

---

## Week-date & day-of-week-in-month encodings

### `DateUtils.EncodeDateWeek` · `TryEncodeDateWeek` · `DecodeDateWeek`

```pascal
Function EncodeDateWeek(const AYear, AWeekOfYear: Word; const ADayOfWeek: Word): TDateTime;
Function EncodeDateWeek(const AYear, AWeekOfYear: Word): TDateTime; //; const ADayOfWeek: Word = 1
Procedure DecodeDateWeek(const AValue: TDateTime; out AYear, AWeekOfYear, ADayOfWeek: Word);
Function TryEncodeDateWeek(const AYear, AWeekOfYear: Word; out AValue: TDateTime; const ADayOfWeek: Word): Boolean;
Function TryEncodeDateWeek(const AYear, AWeekOfYear: Word; out AValue: TDateTime): Boolean; //; const ADayOfWeek: Word = 1
```

Convert between a KDT and an **ISO-8601 week-date** (year, week number, day of
week). Day-of-week defaults to 1 (Monday). Note the ISO year may differ from the
calendar year at year boundaries.

**kcl:** `dateutils.encodeDateWeek <y> <week> [dow=1]` · `dateutils.tryEncodeDateWeek …` — KDT · `dateutils.decodeDateWeek <kdt>` → `Y Week Dow`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodedateweek.html)

---

### `DateUtils.EncodeDateMonthWeek` · `TryEncodeDateMonthWeek` · `DecodeDateMonthWeek`

```pascal
Function EncodeDateMonthWeek(const AYear, AMonth, AWeekOfMonth, ADayOfWeek: Word): TDateTime;
Procedure DecodeDateMonthWeek(const AValue: TDateTime; out AYear, AMonth, AWeekOfMonth, ADayOfWeek: Word);
Function TryEncodeDateMonthWeek(const AYear, AMonth, AWeekOfMonth, ADayOfWeek: Word; out AValue: TDateTime): Boolean;
```

Convert between a KDT and a (year, month, week-of-month, day-of-week) tuple.

**kcl:** `dateutils.encodeDateMonthWeek <y> <m> <wom> <dow>` · `dateutils.tryEncodeDateMonthWeek …` — KDT · `dateutils.decodeDateMonthWeek <kdt>` → `Y M WeekOfMonth Dow`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodedatemonthweek.html)

---

### `DateUtils.EncodeDayOfWeekInMonth` · `DateUtils.TryEncodeDayOfWeekInMonth`

```pascal
Function EncodeDayOfWeekInMonth(const AYear, AMonth, ANthDayOfWeek,  ADayOfWeek: Word): TDateTime;
Function TryEncodeDayOfWeekInMonth(const AYear, AMonth, ANthDayOfWeek,  ADayOfWeek: Word; out AValue: TDateTime): Boolean;
```

Encode "the Nth <weekday> of a month" — e.g. the 3rd Friday of 2011-03. `Nth`
starts at 1; there is no "last-of-month" sentinel form.

**kcl:** `dateutils.encodeDayOfWeekInMonth <y> <m> <nth> <dow>` · `dateutils.tryEncodeDayOfWeekInMonth …` — KDT (Nth ≥ 1)

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodedayofweekinmonth.html)

---

## Conversions & time zones

### `DateUtils.DateTimeToUnix` · `DateUtils.UnixToDateTime`

```pascal
Function DateTimeToUnix(const AValue: TDateTime; AInputIsUTC: Boolean = True): Int64;
Function UnixToDateTime(const AValue: Int64; aReturnUTC : Boolean = true): TDateTime;
```

Convert between a KDT and a Unix timestamp in **seconds** since 1970-01-01. The
boolean controls whether the KDT side is treated as UTC (default true).

**kcl:** `dateutils.dateTimeToUnix <kdt> [inputIsUTC=true]` — Unix seconds · `dateutils.unixToDateTime <sec> [returnUTC=true]` — KDT · e.g. `dateutils.unixToDateTime 0` → KDT 0

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/datetimetounix.html)

---

### `DateUtils.DateTimeToJulianDate` · `JulianDateToDateTime` · `TryJulianDateToDateTime`

```pascal
Function DateTimeToJulianDate(const AValue: TDateTime): Double;
Function JulianDateToDateTime(const AValue: Double): TDateTime;
Function TryJulianDateToDateTime(const AValue: Double; out ADateTime: TDateTime): Boolean;
```

Convert between a KDT and an astronomical **Julian Date**. `1970-01-01 00:00`
is JD `2440587.5`. **Precision:** the port's JD strings carry 6 decimals
(≈ 86 ms); midnight and noon are exact, other times of day round-trip to within
one ulp.

**kcl:** `dateutils.dateTimeToJulianDate <kdt>` — 6-dp JD string · `dateutils.julianDateToDateTime <jd>` · `dateutils.tryJulianDateToDateTime …` — KDT · e.g. `dateutils.julianDateToDateTime 2455277.5`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/datetimetojuliandate.html)

---

### `DateUtils.DateTimeToModifiedJulianDate` · `ModifiedJulianDateToDateTime` · `TryModifiedJulianDateToDateTime`

```pascal
Function DateTimeToModifiedJulianDate(const AValue: TDateTime): Double;
Function ModifiedJulianDateToDateTime(const AValue: Double): TDateTime;
Function TryModifiedJulianDateToDateTime(const AValue: Double; out ADateTime: TDateTime): Boolean;
```

As above for the **Modified Julian Date** (MJD = JD − 2400000.5, epoch
1858-11-17 00:00). Same ~86 ms string resolution.

**kcl:** `dateutils.dateTimeToModifiedJulianDate <kdt>` — 6-dp MJD string · `dateutils.modifiedJulianDateToDateTime <mjd>` · `dateutils.tryModifiedJulianDateToDateTime …` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/datetimetomodifiedjuliandate.html)

---

### `DateUtils.LocalTimeToUniversal` · `DateUtils.UniversalTimeToLocal`

```pascal
Function LocalTimeToUniversal(LT: TDateTime): TDateTime;
Function LocalTimeToUniversal(LT: TDateTime; TZOffset: Integer): TDateTime;
Function UniversalTimeToLocal(UT: TDateTime): TDateTime;
Function UniversalTimeToLocal(UT: TDateTime; TZOffset : Integer): TDateTime;
```

Shift between local and UTC time. With no offset the machine's current local
offset is used. In the port, `TZOffset` is expressed as **minutes east of UTC**
(`+180` = UTC+3) or as an ISO `±hh:mm` / `Z` string.

**kcl:** `dateutils.localTimeToUniversal <kdt> [offset]` · `dateutils.universalTimeToLocal <kdt> [offset]` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/localtimetouniversal.html)

---

### `DateUtils.EncodeTimeInterval` · `DateUtils.TryEncodeTimeInterval`

```pascal
function EncodeTimeInterval(Hour, Minute, Second, MilliSecond:word): TDateTime;
function TryEncodeTimeInterval(Hour, Min, Sec, MSec:word; Out Time : TDateTime) : boolean;
```

Encode a **duration** (not a time-of-day) from H/M/S/ms — here the hour count may
exceed 24. The port echoes the total as milliseconds.

**kcl:** `dateutils.encodeTimeInterval <h> <n> <s> <ms>` · `dateutils.tryEncodeTimeInterval …` — ms (hours may exceed 24)

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/encodetimeinterval.html)

---

### `DateUtils.DateToISO8601`

```pascal
function DateToISO8601(const ADate: TDateTime; AInputIsUTC: Boolean = True): string;
```

Format a KDT as an ISO-8601 string `YYYY-MM-DDThh:mm:ss.zzz` with a trailing `Z`
(when treated as UTC) or a `±hh:mm` offset.

**kcl:** `dateutils.dateToISO8601 <kdt> [inputIsUTC=true]` — `YYYY-MM-DDThh:mm:ss.zzzZ`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/datetoiso8601.html)

---

### `DateUtils.ISO8601ToDate` · `TryISO8601ToDate` · `ISO8601ToDateDef`

```pascal
Function ISO8601ToDate(const DateString: string; ReturnUTC : Boolean = True): TDateTime;
Function TryISO8601ToDate(const DateString: string; out ADateTime: TDateTime; ReturnUTC : Boolean = True) : Boolean;
Function ISO8601ToDateDef(const DateString: string; ReturnUTC : Boolean; aDefault : TDateTime ): TDateTime; deprecated;
Function ISO8601ToDateDef(const DateString: string; aDefault : TDateTime; ReturnUTC : Boolean = True ): TDateTime;
```

Parse a full ISO-8601 timestamp. `ISO8601ToDate` returns 1 on a malformed string;
`TryISO8601ToDate` reports success/failure; `ISO8601ToDateDef` returns a supplied
default on failure (the port follows the non-deprecated `<str> <default>
[returnUTC]` argument order). `ReturnUTC` (default true) controls whether any
offset in the string is normalised to UTC.

**kcl:** `dateutils.iso8601ToDate <str> [returnUTC=true]` · `dateutils.tryISO8601ToDate …` · `dateutils.iso8601ToDateDef <str> <default> [returnUTC]` — KDT · e.g. `dateutils.iso8601ToDate 2010-03-22T09:00:00.000+03:00` → 2010-03-22 06:00 UTC

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/iso8601todate.html)

---

### `DateUtils.TryISOStrToDate` · `TryISOStrToTime` · `TryISOStrToDateTime`

```pascal
function TryISOStrToDate(const aString: string; out outDate: TDateTime): Boolean;
function TryISOStrToTime(const aString: string; Out outTime: TDateTime): Boolean;
function TryISOStrToDateTime(const aString: string; out outDateTime: TDateTime): Boolean;
```

Parse **partial** ISO strings. `TryISOStrToDate` accepts `YYYY`, `YYYYMM`,
`YYYY-MM`, `YYYYMMDD`, or `YYYY-MM-DD` and yields a date at 00:00.
`TryISOStrToTime` accepts `HH` / `HH:NN` / `HH:NN:SS` / `HH:NN:SS.ZZZ` (and the
separator-less variants) and yields a ms-of-day. `TryISOStrToDateTime` combines
the two and returns the value naively, as written (no timezone normalisation).

**kcl:** `dateutils.tryISOStrToDate <str>` — KDT (00:00) · `dateutils.tryISOStrToTime <str>` — ms-of-day · `dateutils.tryISOStrToDateTime <str>` — KDT

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/tryisostrtodate.html)

---

### `DateUtils.ISOTZStrToTZOffset` · `DateUtils.TryISOTZStrToTZOffset`

```pascal
Function ISOTZStrToTZOffset(TZ : String) : Integer;
Function TryISOTZStrToTZOffset(const TZ : String; Out TZOffset : Integer) : boolean;
```

Parse an ISO timezone designator — `Z`, `+hh:nn`, or `-hh:nn` (also the
compact `±hhnn` / `±hh` forms) — into a minute offset. `TryISOTZStrToTZOffset` is
the public interface routine; `ISOTZStrToTZOffset` is its non-`Try` wrapper
(present in the unit's implementation, raising on a bad string). **FPC-sign
quirk:** the port keeps FPC's sign convention here, so `+03:00` → **`-180`** and
`-05:30` → `+330` (opposite of the "minutes east" convention used elsewhere).

**kcl:** `dateutils.isoTZStrToTZOffset <tz>` · `dateutils.tryISOTZStrToTZOffset <tz>` — minutes (FPC sign) · e.g. `dateutils.isoTZStrToTZOffset +03:00` → `-180`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/tryisotzstrtotzoffset.html)

---

## Parsing (scanDateTime)

### `DateUtils.ScanDateTime`

```pascal
function ScanDateTime(const Pattern:String;const s:string;const fmt:TFormatSettings;startpos:integer=1) : tdatetime; overload;
function ScanDateTime(const Pattern:string;const s:string;startpos:integer=1) : tdatetime; overload;
```

A limited inverse of `FormatDateTime`: read fields out of `s` under the control of
`Pattern`, returning a KDT (status 1 on mismatch). Recognised, case-insensitive
tokens are `yyyy`/`yy` (year), `mm` (month), `dd` (day), `hh` (hour), **`nn`
(minute)**, `ss` (second), `zzz` (millisecond). `'literals'` / `"literals"` match
verbatim, whitespace is elastic, and any other character must match exactly.
Two-digit years pivot at 50; fields absent from the pattern default to the epoch.
The port implements the core matcher only — month/day names, am/pm, and `[]`
optionals are out of scope.

| Token | Field |
| --- | --- |
| `yyyy` / `yy` | year (2-digit pivots at 50) |
| `mm` | month |
| `dd` | day |
| `hh` | hour |
| `nn` | **minute** |
| `ss` | second |
| `zzz` | millisecond |

**kcl:** `dateutils.scanDateTime <pattern> <input>` — KDT (status 1 on mismatch) · e.g. `dateutils.scanDateTime 'YYYY.MM.DD HH:NN:SS:ZZZ' '2011.03.29 16:46:56:777'`

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/scandatetime.html)

---

## Constants (getters)

These getters echo the fixed unit constants backing the port's arithmetic. They
mirror the FPC `SysUtils` time constants (`MSecsPerSec`, `MSecsPerDay`, …) and the
`DateUtils` approximations `ApproxDaysPerMonth` / `ApproxDaysPerYear`. The backing
`__KDT_*` globals are `readonly`.

| kcl getter | Echoes | FPC constant / derivation |
| --- | --- | --- |
| `dateutils.msPerSecond` | `1000` | `MSecsPerSec` |
| `dateutils.msPerMinute` | `60000` | `SecsPerMin × MSecsPerSec` |
| `dateutils.msPerHour` | `3600000` | `SecsPerHour × MSecsPerSec` |
| `dateutils.msPerDay` | `86400000` | `MSecsPerDay` |
| `dateutils.msPerWeek` | `604800000` | `DaysPerWeek × MSecsPerDay` |
| `dateutils.approxMsPerMonth` | `2629800000` | `ApproxDaysPerMonth × MSecsPerDay` (30.4375 days) |
| `dateutils.approxMsPerYear` | `31557600000` | `ApproxDaysPerYear × MSecsPerDay` (365.25 days) |
| `dateutils.approxDaysPerMonth` | `30.4375` | `ApproxDaysPerMonth` |
| `dateutils.approxDaysPerYear` | `365.25` | `ApproxDaysPerYear` |

[FPC docs](https://www.freepascal.org/docs-html/rtl/dateutils/index-5.html)
