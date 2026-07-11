# dateutils — test coverage notes (non-FPC cases)

This is the review artifact mandated by the **New-coverage protocol** in
[PLAN.md](PLAN.md). FPC's own DateUtils tests are thin (the primary seed,
`tw16040.pp`, has 17 assertions vs ~160 functions), so most of our fixtures are
of our own design. **Every test case not traceable to an FPC test file gets a
row here** — for later analysis and potential upstreaming to FPC.

Cases that ARE ported from FPC live in `tests/002_FpcParity.sh` and are **not**
listed here (they carry the FPC value verbatim).

## Row format

| field | meaning |
|---|---|
| **id** | test file + check label |
| **functions** | function(s) the check covers |
| **case** | the concrete scenario |
| **why FPC lacks it** | `boundary` (edge not exercised) / `bash-convention` (echo formats, `-` sentinel, status codes, perf shape) / `representation` (KDT negatives, ms, internal helpers) / `cross-check` (vs GNU date) |
| **basis** | source of the expected value: FPC source reading, independent calculation, ISO/RFC citation, or GNU `date` output |

## Summary statistics — FINAL (P7.2)

All phases P0–P7 have landed. **~107 non-FPC test cases** are documented below
(the FPC-parity cases are in `tests/002_FpcParity.sh` and excluded here). Class
breakdown:

| class | count | what it captures |
|---|---|---|
| boundary | 51 | leap centuries, ISO week edges, month ends, period-start/end instants, out-of-range rejections |
| bash-convention | 36 | echo/return-status contracts, `-` sentinel, getter API, thin-dispatch shape, ISO string forms |
| representation | 21 | KDT negatives & round-trips, internal split/join helpers, overflow-free spans, JD 6-dp resolution |
| cross-check | 2 | `now` vs EPOCHREALTIME; `unixToDateTime` vs GNU `date -u` |

**Spot-audit (3 random files, P7.2):** `001_Core.sh` (19 checks ↔ 19 P0 rows),
`006_OfTheFamilies.sh` (5 ↔ 5 P2.2 rows), `011_CompareRange.sh` (6 ↔ 6 P4.3
rows) — every non-FPC check has a matching row. ✔

**Three plan inaccuracies** were surfaced and corrected (see the table below);
all are candidates for upstreaming clarity to the PLAN, not FPC bugs.

### Corrections to the plan surfaced by testing

| where | plan said | correct value | basis |
|---|---|---|---|
| ISO week of 2004-01-01 (PLAN.md §2, ledger P2.1 acceptance) | W53 of 2003 | **W01 of 2004** | 2004-01-01 is a Thursday; ISO-8601 week 1 is the week containing the year's first Thursday, and a Thursday is always in its own year's week. The FPC-ported `DecodeDateWeek` agrees. |
| `periodBetween(2004-02-29, 2005-02-28)` (PLAN.md §5 risk 2, ledger P4.2 acceptance) | 0y 11m 30d | **0y 11m 28d** | Tracing FPC `PeriodBetween` (dateutil.inc line 1643): earlier=2004-02-29, later=2005-02-28 → Years 1→0 (D1>D2 borrow), Months 0→11, Days = (DaysInAMonth(2004,2)=29 − 29) + 28 = 28. The port reproduces this exactly. |
| `encodeDayOfWeekInMonth` negative Nth / "last Friday" (ledger P5.2 acceptance) | test a negative Nth | **no such form in FPC** | FPC `TryEncodeDayOfWeekInMonth` (line 2278) takes `ANthDayOfWeek: Word` (unsigned, ≥1); the formula is `1 + dow − SOM + 7·(Nth−1)`. There is no negative/"last" semantics — the Nth occurrence simply fails validation when the month lacks it. The port matches FPC; negative Nth is not implemented. |

---

## P0 — Core representation (`tests/001_Core.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 001 · KDT join/split roundtrip over the sampled grid | `_join_kdt`, `_split_kdt`, `_days_from_civil`, `_civil_from_days` | (year∈{1899,1900,1970,1999,2000,2004,2100,2400}) × (7 months) × (days 1,15,28) × (3 times) + leap edges (2000-02-29, 2004-02-29, 1996-02-29) — encode→decode is a bijection | representation | independent calc (Hinnant algorithms are a bijection on valid civil dates) |
| 001 · KDT 0 == 1970-01-01 00:00:00.000 | `_split_kdt` | the KDT origin decodes to the Unix epoch | representation | Unix epoch definition |
| 001 · 1970-01-01 is a Thursday (ISO weekday 4) | `_weekday_iso` | day 0 weekday | boundary | known calendar fact / ISO-8601 (Mon=1) |
| 001 · KDT -1 == 1969-12-31 23:59:59.999 | `_split_kdt` | 1 ms before the epoch uses floor (not truncating) division | representation | independent calc |
| 001 · Pascal epoch 1899-12-30 == KDT -2209161600000 | `_join_kdt`, `_days_from_civil` | the FPC TDateTime origin as a KDT value | representation | independent calc (25569 days × 86400000) |
| 001 · _fmt_datetime anchors | `_fmt_datetime` | KDT 0, -1, and 2011-03-26 19:15:30.555 format to canonical ISO strings | bash-convention | ISO-8601 canonical form `YYYY-MM-DD hh:mm:ss.zzz` |
| 001 · parse(fmt(kdt)) == kdt roundtrip | `_fmt_datetime`, `_parse_iso` | format/parse identity over a KDT grid incl. negatives and ms boundaries | bash-convention | roundtrip identity |
| 001 · _parse_iso accepts T-separator, date-only, seconds-only forms | `_parse_iso` | `T`/space separators, omitted seconds/ms default to 0 | bash-convention | ISO-8601 |
| 001 · _parse_iso captures the trailing zone (Z / +hh:mm) | `_parse_iso` | `Z`→0, `+03:00`→180, `-0530`→-330 minutes; no zone→has_tz=0 | bash-convention | ISO-8601 zone designators |
| 001 · _parse_iso rejects malformed input | `_parse_iso` | month 13, hour 25, minute 60, `/`-separators, non-dates, empty → status 1 | bash-convention | design (light P0 range check; full validity is P1) |
| 001 · now() within 2s of independent EPOCHREALTIME+offset | `now` | wall clock matches an independent builtin computation | cross-check | `EPOCHREALTIME` + `printf '%(%z)T'` |
| 001 · now() - nowUTC() == local offset | `now`, `nowUTC` | naive-local minus naive-UTC equals the system offset | representation | naive-KDT definition |
| 001 · today() == dateOf(now()); yesterday/tomorrow ±1 day | `today`, `dateOf`, `now`, `yesterday`, `tomorrow` | day-flooring and ±86400000 ms neighbours | bash-convention | definition |
| 001 · dateOf(kdt) + timeOf(kdt) == kdt, timeOf in [0, MS_PER_DAY) | `dateOf`, `timeOf` | date/time split is exact and complementary incl. negatives | representation | identity |
| 001 · constant getters return the __KDT_* values | `msPerSecond`..`approxDaysPerYear` | the 9 public constant getters | bash-convention | FPC constants (`MSecsPerDay`=86400000, `ApproxDaysPerYear`=365.25, `ApproxDaysPerMonth`=30.4375) |
| 001 · __KDT_* constants are readonly | (constants) | writing `__KDT_MS_PER_DAY` fails | bash-convention | collision-safety hardening (same as tpath/tfile) |
| 001 · dateutils dispatchers are thin | `now` (shape) | no capturing dispatcher (no static var) | bash-convention | kklass thin-dispatch perf contract |
| 001 · hot paths make zero forks (empty PATH) | `nowUTC`, `dateOf`, `today` | run with `PATH=''` — only builtins survive | bash-convention | zero-fork design goal |
| 001 · kklass metadata lists the P0 static methods | (metadata) | `dateutils_class_static_methods` populated | bash-convention | kklass static-class registration |

## P1.1 — Encode / decode (`tests/003_EncodeDecode.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 003 · encodeDateTime/decodeDateTime roundtrip over a grid | `encodeDateTime`, `decodeDateTime` | 9 specs incl. 1-1-1, 9999-12-31, 1899-12-30, leap 2000/2004/2400-02-29 — encode→decode identity | representation | independent calc (KDT join/split are exact inverses) |
| 003 · encodeDate == encodeDateTime at midnight; decodeDate agrees | `encodeDate`, `encodeDateTime`, `decodeDate` | date-only encode equals datetime encode with zero time | bash-convention | definition |
| 003 · encodeTime numeric contract + 24:00:00.000 whole-day | `encodeTime`, `encodeDateTime` | time-of-day in ms; `encodeTime(24,0,0,0)=86400000`; `encodeDateTime(...,24,0,0,0)` rolls to next midnight | boundary | FPC source (`IsValidTime` line 719: 24:00:00.000 valid; `ComposeDateTime(date,1.0)`) |
| 003 · decodeTime splits time-of-day fields | `decodeTime` | h/m/s/ms extraction echo format | bash-convention | definition |
| 003 · encode*/tryEncode* reject invalid inputs | `encodeDate/Time/DateTime`, `tryEncode*` | invalid date/time → status 1, echoes nothing (FPC raises; we return 1) | bash-convention | design (no bash exceptions) |
| 003 · tryEncode* echo the value and return 0 on success | `tryEncodeDate`, `tryEncodeDateTime` | success path echoes value + status 0 | bash-convention | design (Try* convention) |
| 003 · encodeDateDay/decodeDateDay roundtrip + anchors | `encodeDateDay`, `decodeDateDay` | 2011 day 1/85/365, 2000 day 60(Feb29)/366(Dec31) → calendar dates | boundary | independent calc (day-of-year) |
| 003 · encodeDateDay rejects day-of-year past year length | `encodeDateDay`, `tryEncodeDateDay` | 2011 day 366 invalid, 2000 day 366 valid, day 0/367 invalid | boundary | FPC source (`TryEncodeDateDay` line 1974: `doy<=DaysPerYear[leap]`) |

## P1.2 — Validity & calendar sizes (`tests/004_Validity.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 004 · isValidDate leap-century + bounds | `isValidDate` | 1900/2100-02-29 false, 2000/2004-02-29 true; month/day/year(0, 10000, 9999, 1) bounds | boundary | FPC source (`IsValidDate` line 709) |
| 004 · isValidTime field ranges + 24:00:00.000 | `isValidTime` | 24:00:00.000 true, 24:00:00.001 / 24:01:00.000 false, ms 1000 false | boundary | FPC source (`IsValidTime` line 717) |
| 004 · isValidDateTime = isValidDate AND isValidTime | `isValidDateTime` | composed validity incl. the 24:00 pass-through | bash-convention | FPC source (line 726) |
| 004 · isValidDateDay bounds honor leap length | `isValidDateDay` | doy 365/366 vs leap; year 0 invalid | boundary | FPC source (`IsValidDateDay` line 733) |
| 004 · isValidDateWeek week bound = WeeksInAYear | `isValidDateWeek`, `weeksInAYear` | 2004 W53 valid, 2005 W53 invalid; week 0 / dow 0,8 invalid | boundary | FPC source (line 740) + ISO week counts |
| 004 · isValidDateMonthWeek bounds | `isValidDateMonthWeek` | month 1..12, weekOfMonth 1..5, dow 1..7 | boundary | FPC source (line 751) |
| 004 · isInLeapYear takes a DATE | `isInLeapYear` | date argument's year is leap-tested (1900/2000/2004/2100/2011/2024) | bash-convention | FPC source (line 692: `IsLeapYear(YearOf(x))`) |
| 004 · daysInAMonth full table + invalid month | `daysInAMonth` | 12-month non-leap table + Feb 2000/1900/2004; month 13 → status 1 | boundary | FPC `MonthDays` table |
| 004 · daysInMonth / daysInAYear / daysInYear | `daysInMonth`, `daysInAYear`, `daysInYear` | month/year sizes from a date or year, leap-aware | boundary | FPC source (lines 795, 789, 783) |
| 004 · weeksInAYear / weeksInYear ISO fixtures | `weeksInAYear`, `weeksInYear` | 2004/2009/2015/2020/2026→53, 2005/2021→52 | boundary | ISO-8601 week counts + FPC `WeeksInAYear` (line 770) |

## P2.1 — Simple extractors, ISO weeks, isAM/isPM (`tests/005_Extraction.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 005 · yearOf..milliSecondOf match decodeDateTime | `yearOf`,`monthOf`,`dayOf`,`hourOf`,`minuteOf`,`secondOf`,`milliSecondOf` | field extractors equal the decode fields over 4 datetimes incl. pre-1970 | bash-convention | definition (FPC extractors call Decode*) |
| 005 · monthOfTheYear/dayOfTheMonth/hourOfTheDay aliases | `monthOfTheYear`,`dayOfTheMonth`,`hourOfTheDay` | same-unit aliases agree | bash-convention | FPC source (inline aliases, lines 1113/1214/1328) |
| 005 · dayOfTheWeek is ISO across a full week | `dayOfTheWeek` | Mon 2011-03-21→1 .. Sun 2011-03-27→7; 1970-01-01→4 | boundary | ISO-8601 + FPC `DowMAP` |
| 005 · dayOfTheYear anchors | `dayOfTheYear` | Jan1→1, Mar26(non-leap)→85, Dec31→365, leap Dec31→366 | boundary | independent calc |
| 005 · weekOfTheYear ISO boundary fixtures | `weekOfTheYear`,`weekOf`,`_decode_date_week` | 2004-01-01→W01/2004, 2003-12-31→W01/2004, 2005-01-01→W53/2004, 2008-12-29→W01/2009, 2010-01-03→W53/2009, 2009-12-31→W53/2009 | boundary | ISO-8601 + FPC `DecodeDateWeek`. **Corrects the plan's 2004-01-01→W53/2003** (see corrections table above) |
| 005 · weekOfTheMonth over a month | `weekOfTheMonth`,`_decode_date_month_week` | 2011-03-01→1, 2011-03-26→4 | boundary | FPC `DecodeDateMonthWeek` |
| 005 · isAM/isPM split at noon | `isAM`,`isPM` | 11:59:59.999→AM, 12:00→PM, 00:00→AM | boundary | FPC source (`IsPM = HourOf>=12`, line 698) |

## P2.2 — OfThe* families + nth-day (`tests/006_OfTheFamilies.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 006 · OfThe* internal consistency | all 24 `*OfThe*` | nested reconstruction (`msOfDay==((h*60+m)*60+s)*1000+ms`, week/month/year analogues) over 4 datetimes | representation | FPC formulas (dateutil.inc lines 1145–1420) |
| 006 · period starts are zero | `*OfTheYear/Month/Day/Week` | at start-of-period every OfThe* = 0 | boundary | independent calc |
| 006 · period ends saturate | `milliSecondOfTheWeek`,`hourOfTheWeek` | Sun 23:59:59.999 → 604799999 (= 7·86400000−1) | boundary | independent calc |
| 006 · nthDayOfWeek table | `nthDayOfWeek` | day-of-month 1..31 → occurrence 1..5 via `(D-1) div 7 + 1` | boundary | FPC `InternalNthDayOfWeek` |
| 006 · decodeDayOfWeekInMonth echo | `decodeDayOfWeekInMonth` | 2011-03-26 → "2011 3 4 6" (4th Saturday) | bash-convention | FPC source (line 2259) |

## P3 — Start/End & day predicates (`tests/007_StartEnd.sh`, `008_Predicates.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 007 · startOf/endOf year|month|day instants | `startOfThe*`,`endOfThe*`,`endOfAMonth` | canonical instants incl. leap-Feb end (2000-02-29, 2011-02-28) 23:59:59.999 | boundary | FPC source (lines 956–1080) |
| 007 · week boundaries Monday..Sunday | `startOfTheWeek`,`endOfTheWeek` | Sat 2011-03-26 → Mon 2011-03-21 / Sun 2011-03-27; Mon/Sun map to themselves | boundary | FPC source (lines 1025/1031) + ISO |
| 007 · The/A twins agree | `startOfA*`,`endOfA*` vs `*OfThe*` | A-forms equal The-forms on matching inputs | bash-convention | FPC source (twin definitions) |
| 007 · startOfADay/endOfADay day-of-year overload | `startOfADay`,`endOfADay` | (year, dayOfYear) 2-arg form equals (y,m,d) 3-arg; 2000 day 60 = Feb 29 | bash-convention | FPC overloads (lines 1089/1101); bash dispatches on `$#` |
| 007 · endOfTheX == startOfNext(X) − 1ms | all start/end | day/month/year/week each: next-start minus end = 1 | boundary | independent calc (ms resolution: .999 end = next − 1ms) |
| 007 · startOfAWeek/endOfAWeek ISO week-date | `startOfAWeek`,`endOfAWeek`,`_encode_date_week` | ISO W1/2009 → Mon 2008-12-29 / Sun 2009-01-04; invalid week → status 1 | boundary | FPC `TryEncodeDateWeek` (line 1925) + ISO |
| 008 · isSameDay same/neighbour/boundary | `isSameDay` | same calendar day true; ±1 day false; exact next-midnight excluded | boundary | FPC source (line 841) |
| 008 · isSameDay truncates only the basis | `isSameDay` | value kept, basis truncated (asymmetric FPC form) | bash-convention | FPC source (line 847: `D:=AValue-Trunc(ABasis)`) |
| 008 · isSameMonth compares year AND month | `isSameMonth` | same month different year → false | bash-convention | FPC source (line 851) |
| 008 · isToday now vs past | `isToday` | now/start-of-today true, fixed 2011 date false | bash-convention | FPC source (`IsSameDay(x, Date())`) |
| 008 · previousDayOfWeek wrap + reject | `previousDayOfWeek` | ISO weekday number 1..7 → prior (Mon→Sun); 0/8 → status 1 | boundary | FPC `DOWMap` (line 858); takes a weekday NUMBER not a date |

## P4.1 — Increment (`tests/009_Increment.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 009 · incMonth clamps to target month | `incMonth` | Jan31+1m→Feb28/29, Dec+1m→next Jan, negative & year-roll-back | boundary | FPC/SysUtils IncMonth day-clamp |
| 009 · incMonth/incYear preserve time-of-day | `incMonth`,`incYear` | h:m:s.ms carried through | bash-convention | FPC re-encode with same time |
| 009 · incYear Feb-29 → Feb-28 non-leap | `incYear` | 2004-02-29 +1y→2005-02-28, +4y→2008-02-29, −1y | boundary | FPC source (line 1738) |
| 009 · inc*/exact ms shifts | `incWeek/Day/Hour/Minute/Second/MilliSecond` | fixed ms deltas + default step 1 | representation | FPC `NumberToDateTime(+n·unit)` |
| 009 · inc +n then −n round-trips | all `inc*` | symmetry on a day-26 base (no clamp) | representation | independent calc |

## P4.2 — Between / period / span / diff (`tests/010_BetweenSpan.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 010 · fine-grained *Between | `milliSeconds..weeksBetween` | known offset 19:15:30.555; order-independent; 4102 days / 586 weeks | representation | `|now−then|/unit` (FPC formulas, exact ms) |
| 010 · approx vs exact between | `yearsBetween`,`monthsBetween` | 2001→2002 (365 d): approx 0y/11m vs exact 1y/12m | boundary | FPC `AExact` flag + `ApproxDaysPer*` |
| 010 · periodBetween borrow logic | `periodBetween` | 0y11m28d, 0y2m5d, 0y1m1d, 11y2m25d; symmetric | boundary | FPC `PeriodBetween` (line 1643). **Corrects plan's 30d→28d** (corrections table) |
| 010 · Span 6-dp fixed-point | `daySpan/hourSpan/secondSpan/milliSecondSpan/weekSpan` | 0.500000, 1.500000, 250.000000 | bash-convention | fractional ratio, 6 dp integer scaling |
| 010 · Span overflow-free full range | `milliSecondSpan` | 0001-01-01..9999-12-31 whole=|d|, .000000 | representation | whole/remainder split avoids `|d|·10⁶` overflow (plan risk #3) |
| 010 · dateTimeDiff signed | `dateTimeDiff` | now−then and then−now (±69330555) | bash-convention | signed ms (KDT is the number) |

## P4.3 — Compare / same / within-past / range (`tests/011_CompareRange.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 011 · compare* echo -1/0/1 | `compareDateTime/Date/Time` | ordering; compareDate ignores time; compareTime ignores date | bash-convention | FPC `TValueRelationship`; KDT sign(a−b) |
| 011 · same* | `sameDateTime/Date/Time` | equality, same-day, same-time-of-day-across-days | bash-convention | FPC source (lines 2214–2242) |
| 011 · withinPast* == (between ≤ range) | `withinPast*` | days/hours/weeks/years incl. approx years | representation | FPC source (lines 1432+) |
| 011 · dateTimeInRange incl/excl | `dateTimeInRange` | boundary inclusive (default) vs exclusive | boundary | FPC source (line 1481) |
| 011 · dateInRange day granularity | `dateInRange` | time component ignored; boundary day inclusive | boundary | FPC source (line 1513) |
| 011 · timeInRange overnight wrap | `timeInRange` | same-day range + wrap (end<start) OR-logic | boundary | FPC source (line 1491) |

## P5.1 — Recode (`tests/012_Recode.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 012 · single-field recode | `recodeYear..recodeMilliSecond` | change one field, keep the rest | bash-convention | FPC `RecodeDateTime` via LFAI |
| 012 · recodeDate/Time/DateTime groups | `recodeDate`,`recodeTime`,`recodeDateTime` | replace date-group / time-group / all | bash-convention | FPC source (lines 2122–2138) |
| 012 · '-' sentinel leaves fields | `recodeDateTime` | `-` = RecodeLeaveFieldAsIs; all-`-` is a no-op | bash-convention | FPC LFAI + kcl `-` convention |
| 012 · reject invalid recombination | `recode*`,`tryRecodeDateTime` | Jan31→Feb, Feb30, hour 25 → status 1 | boundary | FPC (RecodeDateTime raises; Try* returns false) |
| 012 · tryRecodeDateTime success | `tryRecodeDateTime` | echoes value + status 0 | bash-convention | FPC `TryRecodeDateTime` |

## P5.2 — Week-date / day-of-week-in-month encodings (`tests/013_WeekDayEncodings.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 013 · decodeDateWeek ISO fixtures | `decodeDateWeek` | 2011-03-26→2011/12/6, 2004-01-01→2004/1/4, 2005-01-01→2004/53/6, 2008-12-29→2009/1/1, 2010-01-03→2009/53/7 | boundary | ISO-8601 + FPC `DecodeDateWeek` |
| 013 · encodeDateWeek fixtures/default/reject | `encodeDateWeek`,`tryEncodeDateWeek` | W1/2009→2008-12-29, default dow=1, invalid week→status 1 | boundary | FPC `TryEncodeDateWeek` |
| 013 · encodeDateWeek∘decodeDateWeek roundtrip | `encodeDateWeek`,`decodeDateWeek` | encode(decode(dt))==dateOf(dt) over 7 ISO boundaries incl. leap | representation | roundtrip identity |
| 013 · month-week anchors | `decodeDateMonthWeek`,`encodeDateMonthWeek` | 2011-03-26↔(2011,3,4,6), 2011-03-01↔(2011,3,1,2); month 13→status 1 | boundary | FPC `DecodeDateMonthWeek`/`TryEncodeDateMonthWeek` |
| 013 · encodeDayOfWeekInMonth nth + 5th-fails | `encodeDayOfWeekInMonth`,`tryEncodeDayOfWeekInMonth` | 4th Sat→03-26, 1st Sat→03-05, 5th Thu→03-31, no 5th Sat/Mon→status 1 | boundary | FPC `TryEncodeDayOfWeekInMonth`; **no negative-Nth form** (corrections table) |

## P6.1/6.2 — Unix + Julian/MJD (`tests/014_UnixJulian.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 014 · Unix anchors | `unixToDateTime`,`dateTimeToUnix` | 0/86400/−1 s; ms truncated to the second | boundary | Unix epoch = KDT 0 |
| 014 · Unix round-trips | `unixToDateTime`,`dateTimeToUnix` | 7 epochs incl. far-future 15796372693 | representation | round-trip identity |
| 014 · Julian anchors | `dateTimeToJulianDate`,`julianDateToDateTime` | epoch JD 2440587.5, J2000 JD 2451545.0, 6-dp format | boundary | astronomical JD constants |
| 014 · Julian exact at midnight/noon | `dateTimeToJulianDate`,`julianDateToDateTime` | 00:00→X.5 / 12:00→X.0 round-trip exactly | representation | JD = 2440587.5 + KDT/86400000 |
| 014 · Julian intraday within 6-dp | `julianDateToDateTime`,`dateTimeToJulianDate` | 09:18:13 round-trips within 87ms | representation | 6-dp JD resolution = 86.4ms (documented limit) |
| 014 · Modified Julian | `dateTimeToModifiedJulianDate`,`modifiedJulianDateToDateTime` | MJD=JD−2400000.5, epoch MJD 40587, roundtrip | boundary | MJD definition |
| 014 · GNU date cross-check | `unixToDateTime` | 4 epochs vs `date -u` (skipped if absent) | cross-check | GNU `date -u` output |

## P6 — ISO 8601 / TZ / local↔UTC / interval (`tests/015_ISO8601.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 015 · dateToISO8601/iso8601ToDate UTC roundtrip | `dateToISO8601`,`iso8601ToDate` | `...Z` emitted and parsed back to the same KDT | bash-convention | ISO-8601 + FPC `DateToISO8601` |
| 015 · iso8601ToDate zone→UTC | `iso8601ToDate` | +03:00 / −05:00 / Z all resolve to the same UTC instant | boundary | FPC `TryISO8601ToDate` (`IncMinute(dt, tzoffset)`) |
| 015 · try/Def ISO handling | `tryISO8601ToDate`,`iso8601ToDateDef` | malformed → status 1 / default | bash-convention | FPC source |
| 015 · tryISOStrToDate 5 forms | `tryISOStrToDate` | YYYY / YYYYMM / YYYY-MM / YYYYMMDD / YYYY-MM-DD | boundary | FPC `TryISOStrToDate` (by length) |
| 015 · tryISOStrToTime/DateTime | `tryISOStrToTime`,`tryISOStrToDateTime` | ms-of-day; trailing Z; naive datetime | bash-convention | FPC source |
| 015 · isoTZStrToTZOffset FPC sign | `isoTZStrToTZOffset`,`tryISOTZStrToTZOffset` | +03:00→−180, −0530→+330, +05→−300, Z→0 | boundary | FPC `TryISOTZStrToTZOffset` (negates '+') |
| 015 · local↔universal explicit offset | `universalTimeToLocal`,`localTimeToUniversal` | minutes-east & '±hh:mm' forms; system-offset roundtrip | representation | SysUtils semantics (offset = minutes east) |
| 015 · encodeTimeInterval | `encodeTimeInterval`,`tryEncodeTimeInterval` | hours>24 (30h15m, 100h); ms==1000 allowed; m/s≥60 → status 1 | boundary | FPC `TryEncodeTimeInterval` (line 2051) |

## P7.1 — scanDateTime subset (`tests/016_ScanDateTime.sh`)

| id | functions | case | why FPC lacks it | basis |
|---|---|---|---|---|
| 016 · common patterns → KDT | `scanDateTime` | `YYYY.MM.DD HH:NN:SS:ZZZ`, ISO, `dd/mm/yyyy`, single-digit fields, `yyyymmdd`, time-only | boundary | FPC `ScanDateTime` subset (NN=minute, MM=month) |
| 016 · quoted literals + elastic whitespace | `scanDateTime` | `"T"`/`'x'` verbatim; one pattern space matches a run | bash-convention | FPC quoting + subset whitespace elasticity |
| 016 · 2-digit year pivot at 50 | `scanDateTime` | 23→2023, 49→2049, 50→1950, 76→1976 | boundary | subset design (fixed pivot 50; FPC uses a now-relative window) |
| 016 · mismatches → status 1 | `scanDateTime` | wrong separator, non-digit, invalid month/day/hour | boundary | FPC (raises) → we return 1 |
| 016 · scan∘format roundtrip | `scanDateTime`,`_fmt_datetime` | `scanDateTime('yyyy-mm-dd hh:nn:ss.zzz', fmt(dt)) == dt` | representation | round-trip identity |

## Notes for further analysis / potential upstreaming

- **JD 6-dp resolution (~86ms).** `dateTimeToJulianDate` emits 6 decimal places
  (1e-6 day = 86.4 ms). Midnight/noon are exact (X.5 / X.0); arbitrary times
  round-trip within one ulp. A wider-precision variant could be added if
  sub-86ms Julian fidelity is ever needed.
- **scanDateTime year pivot.** The subset fixes the two-digit-year pivot at 50
  for determinism; FPC uses `TwoDigitYearCenturyWindow` relative to the current
  date. Documented divergence (a pattern with `yyyy` avoids it entirely).
- **scanDateTime unset fields default to the epoch (1970-01-01 00:00),** so any
  partial pattern yields a valid KDT and a time-only pattern gives the ms-of-day.
