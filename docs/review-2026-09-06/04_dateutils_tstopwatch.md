# Reviewer report G3 — dateutils / tstopwatch (2026-09-06)

Repro scripts: `repro/g3/r1_octal.sh … r8_misc.sh` (`r3_isoweek.sh` = perl sweep of 15 006 days, ~40 s).

### Summary
Both units are in good shape algorithmically: dateutils 123/123 on bash 5.2.37 and 5.3.9 (≈2 min per run), tstopwatch 34/34 on both. Calendar core cross-checked independently: ISO year/week/weekday and day-of-year for **all 15 006 days 1995–2035 vs perl `%G %V %u %j` → 0 mismatches**; `weeksInAYear` 1900–2100 vs perl → 0; `encodeDateWeek∘decodeDateWeek`, `encodeDateMonthWeek∘decodeDateMonthWeek`, `encodeDayOfWeekInMonth` round-trip every day 2000–2012 with 0 errors; leap 1900/2000/2100/1600, 1899-12-29 23:59:59.999, 0001-01-01 (Monday), 9999-12-31, IncMonth clamping, `*Between` truncation, `DateTimeToUnix` flooring all match FPC. KDT is integer ms, so no float precision loss; the locale decimal-comma trap in `EPOCHREALTIME` (5.2 prints `1788676658,546051` under de_DE/ru_RU; 5.3 too on this box) is handled in both units.

### Findings

`G3-01 | HIGH | dateutils.sh:480 (_valid_date), 492 (_valid_time), 296 (_days_from_civil), 564 (_encode_date_week) | Zero-padded numeric fields (08/09) crash or yield wrong results`
`(( y >= 1 … ))` on `08`/`09` hits bash's octal parse. Repro: `dateutils.encodeDate 2011 08 09` → `((: 08: value too great for base`, rc 1; `dateutils.isValidDate 2011 08 15` → prints **`false`** (wrong, rc 0); `encodeTime 09 05 08 000`, `recodeMonth 0 09`, `encodeDateWeek 2011 09 1`, `startOfAMonth 2011 08`, `incMonth 0 08` all error. Trigger is the common `IFS=- read y m d <<< 2011-08-09` pattern. `_parse_iso`/`tryISOStrToDate` already use `10#`; the numeric-argument entry points don't. Fix: normalize every numeric arg once at the public boundary (`x=$((10#$x))` after a `^[+-]?[0-9]+$` check).

`G3-02 | HIGH | dateutils.sh:395 (_parse_iso range check) | iso8601ToDate / tryISO8601ToDate / tryISOStrToDateTime accept impossible dates and year 0`
Only `d<=31` is checked, then `_join_kdt` rolls over. Repro: `tryISO8601ToDate 2011-02-31` → `2011-03-03 00:00:00.000` (rc 0); `2011-02-29` → 2011-03-01; `2011-04-31` → 2011-05-01; `2011-02-30T12:00:00Z` → 2011-03-02; `0000-01-01` accepted. FPC `TryISOStrToDateTime → TryISOStrToDate → TryEncodeDate` returns False. `tryISOStrToDate` (date-only) is correct — inconsistent within the unit. Fix: `dateutils._valid_date "$y" "$mo" "$d"` in `_parse_iso`.

`G3-03 | MED | dateutils.sh:1158 (dateTimeToModifiedJulianDate), 597 (_span_fixed) | Negative MJD (dates before 1858-11-17) is printed malformed and cannot round-trip`
Repro: `dateTimeToModifiedJulianDate $(encodeDateTime 1858 11 16 12 0 0 0)` → `0.-500000` (expected `-0.500000`); 1800-01-01 06:00 → `-21503.-750000`; feeding that back crashes at line 655. Fix: in `_span_fixed` take `sign` out first and printf `'%s%d.%06d'`.

`G3-04 | MED | all public bodies (e.g. 1018 incDay, 1025 milliSecondsBetween, 480 _valid_date) | Unvalidated arguments in `$(( ))` = command execution; empty/garbage silently becomes the epoch`
Repro: `dateutils.incDay 'x[$(echo INJECTED>&2)]'` prints `INJECTED` then `86400000` rc 0; `isValidDate 'x[$(…)]' 1 1`, `compareDateTime 'a[$(…)]' 0` likewise. `dayOf ""` → `1`, `decodeDateTime ""` → `1970 1 1 0 0 0 0`, `incDay abc` → `86400000`, all rc 0; `daysBetween "" ""` → syntax error pointing at kklass.sh:972. Fix: `kk.isInt` guard at each public entry (D1).

`G3-05 | MED | dateutils.sh:427 (_local_offset_ms) | Local offset is always the *current* offset — not the offset at the converted date (DST)`
`printf '%(%z)T' -1` is used for every date. `dateToISO8601 … false`, `universalTimeToLocal`/`localTimeToUniversal`, `unixToDateTime … false`, `dateTimeToUnix … false`, `tryISO8601ToDate … false` all get today's offset for a January date in any DST zone. FPC is date-aware (`GetLocalTimeOffset(AValue, AInputIsUTC)`). SUSPECTED-by-inspection only: the host zone is +0300 without DST and no tzdata under MSYS2/cygwin. Fix: `printf '%(%z)T' "$(( kdt/1000 ))"` (zero forks) with `-1` fallback for `now` (decision R7).

`G3-06 | LOW | dateutils.sh:1189-1191 (tryEncodeTimeInterval) | Negative fields accepted` — `tryEncodeTimeInterval -5 0 0 0` → `-18000000` rc 0. FPC params are `word`.

`G3-07 | LOW | dateutils.sh:649-655 (_jd_str_to_ms) | try*JulianDateToDateTime crash instead of returning 1 on non-numeric input` — `julianDateToDateTime abc` → `10#abc: value too great for base`. Fix: regex-validate and `return 1`.

`G3-08 | LOW | dateutils.sh:1266/1273 (scanDateTime), README.md:215 | `mm` after `hh` is month, not minutes`
`scanDateTime 'yyyy-mm-dd hh:mm:ss' '2011-03-26 19:15:30'` → rc 1. FPC applies "M after H = minutes" (dateutil.inc:2680). Unterminated quote silently accepted. Fix: track `lasttoken`; reject unterminated quotes.

`G3-09 | LOW | tryISOStrToTime (≈1229), tryISOStrToDateTime (≈1238) | FPC ISO forms not accepted`
Rejected but valid in FPC: `tryISOStrToTime 19`, `1915`, `191530.555`; `tryISOStrToDateTime 2011`, `20110326`, `20110326T19:15`, `T19:15`. Fix: add the compact forms or state the subset in README.

`G3-10 | LOW | incYear/incMonth (≈995-1010), encodeDateTime 24:00 | No 1..9999 range on results` — `incYear (9999-06-01) 1` → `10000 6 1`; `incMonth (0001-01-31) -1` → `0000-12-31`; `encodeDateTime 9999 12 31 24 0 0 0` → year 10000.

`G3-11 | LOW | tstopwatch README.md:44-48, 85, 122; docs/TStopwatch.md | Property-read cost claims are stale (kklass D1 landed)`
README says property reads fork via `RESULT="$($__inst__.call Getter)"` "~17.7 ms". Current kklass_decl.sh:304-306 generates `RESULT=""; $__inst__.call Getter` (no fork); measured: `sw.elapsedMicroseconds` direct 0.87 ms (5.2) / 0.72 ms (5.3) vs func form 0.37/0.33 ms, `TStopwatch.getTimeStamp` 18-19 µs. Fix: rewrite the box and cost table.

`G3-12 | LOW | tstopwatch.sh:197-218 | Boolean convention differs from dateutils` — tstopwatch `0/1`, dateutils `true/false` (decision D2/R8).

Verified non-issues: locale comma handled in `_now_utc_ms`, `_nowUs`, `_elapsedUs`, `getTimeStamp` (LC_ALL=de_DE.UTF-8 on 5.2 and 5.3); Stop/Start accumulation, Reset, Restart, double-Start/Stop no-ops, negative elapsed on clock step-back (documented), `.new x bogus` rc 1 with valid stopped instance, `delete` frees `_data`/`_class`/wrappers, re-source rc 0, both units under `PATH=''`; `DayOfTheWeek` ISO Mon=1 is the correct FPC DateUtils convention; `weekOfTheMonth` spill semantics match FPC; `periodBetween(2004-02-29, 2005-02-28)` = 0y 11m 28d matches FPC source.

Perf note: all 185 members are `proc` (echo), so every caller pays a fork: `$(dateutils.yearOf k)` = **15 ms/call** on MSYS2 vs 0.17 ms direct (decision D3: convert to func + RESULT).

### Test gaps
- No test passes zero-padded fields (`08`, `09`) to any numeric entry point; no test passes `""`, non-numeric, or shell-meta strings.
- No negative-branch test for `_parse_iso`/`tryISO8601ToDate` with a syntactically valid but impossible date (Feb 30/31, Apr 31, year 0000).
- Julian tests never go below 1858-11-17 (MJD); no malformed JD string case.
- ISO week coverage is 6 hand-picked fixtures; a perl-`%G/%V` sweep (`r3_isoweek.sh`) would pin the whole algorithm cheaply.
- No DST-related test; `scanDateTime`: no `hh:mm`, unterminated quote, trailing input.
- tstopwatch: locale-comma parse has no test (`LC_ALL=de_DE.UTF-8` is available); no test that the property form is fork-free/silent under `PATH=''`; 003 uses "+10 s" upper bounds.
