source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
f() { dateutils._fmt_datetime "$1"; echo "$REPLY"; }
# decodeDateMonthWeek / encodeDateMonthWeek roundtrip over all days 2000-2012
bad=0; n=0
dateutils._days_from_civil 2000 1 1; s=$REPLY; dateutils._days_from_civil 2013 1 1; e=$REPLY
for (( day=s; day<e; day++ )); do
  kdt=$(( day*86400000 ))
  dateutils._decode_date_month_week "$kdt"; n=$((n+1))
  dateutils._encode_date_month_week "$__kdt_mw_year" "$__kdt_mw_month" "$__kdt_mw_week" "$__kdt_mw_dow" || { echo "ENC FAIL $__kdt_mw_year $__kdt_mw_month $__kdt_mw_week $__kdt_mw_dow"; bad=$((bad+1)); continue; }
  (( REPLY == kdt )) || { (( bad < 5 )) && { echo -n "MW RT MISMATCH "; f "$kdt"; echo "   -> $__kdt_mw_year $__kdt_mw_month $__kdt_mw_week $__kdt_mw_dow -> $(f "$REPLY")"; }; bad=$((bad+1)); }
  # nth weekday roundtrip
  dateutils._split_kdt "$kdt"; dateutils._weekday_iso "$kdt"; dow=$REPLY; nth=$(( (__kdt_d-1)/7+1 ))
  dateutils._encode_dow_in_month "$__kdt_y" "$__kdt_mo" "$nth" "$dow" || { echo "DOWIM FAIL"; bad=$((bad+1)); continue; }
  (( REPLY == kdt )) || { echo "DOWIM MISMATCH day=$day"; bad=$((bad+1)); }
done
echo "monthweek+dowInMonth roundtrip over $n days: mismatches=$bad"
echo "--- weekOfTheMonth samples (FPC semantics: week containing the 1st is week 1 only if 1st is Mon..Thu)"
for spec in "2011 5 1" "2011 5 31" "2010 1 1" "2010 1 31" "2012 9 30" "2012 12 31"; do read -r y m d <<< "$spec"; k=$(dateutils.encodeDate $y $m $d); echo "$spec -> $(dateutils.decodeDateMonthWeek $k)"; done
echo "--- incMonth edges"
for spec in "2011 3 31 -1" "2011 1 31 1" "2012 1 31 1" "2011 1 31 13" "2011 1 31 -11" "2000 2 29 12" "2011 5 31 0" "1 1 31 -1" "9999 12 31 1"; do read -r y m d n <<< "$spec"; k=$(dateutils.encodeDateTime $y $m $d 23 59 59 999); echo "$spec -> $(f "$(dateutils.incMonth $k $n)")"; done
echo "--- incYear edges"; for spec in "2000 2 29 100" "2000 2 29 -100" "2000 2 29 400"; do read -r y m d n <<< "$spec"; k=$(dateutils.encodeDate $y $m $d); echo "$spec -> $(f "$(dateutils.incYear $k $n)")"; done
echo "--- boundaries: 23:59:59.999, midnight, negatives"
k=$(dateutils.encodeDateTime 1899 12 29 23 59 59 999); echo "1899-12-29 23:59:59.999 -> $(dateutils.decodeDateTime $k) dow=$(dateutils.dayOfTheWeek $k) timeOf=$(dateutils.timeOf $k) endOfTheDay=$(f "$(dateutils.endOfTheDay $k)") startOfTheDay=$(f "$(dateutils.startOfTheDay $k)")"
k=$(dateutils.encodeDateTime 1 1 1 0 0 0 0); echo "0001-01-01 -> kdt=$k $(dateutils.decodeDateTime $k) dow=$(dateutils.dayOfTheWeek $k) (perl: Monday=1) week=$(dateutils.decodeDateWeek $k)"
k=$(dateutils.encodeDateTime 9999 12 31 23 59 59 999); echo "9999-12-31 23:59:59.999 -> kdt=$k $(dateutils.decodeDateTime $k) dow=$(dateutils.dayOfTheWeek $k) week=$(dateutils.decodeDateWeek $k)"
echo "isLeap 1900=$(dateutils.daysInAYear 1900) 2000=$(dateutils.daysInAYear 2000) 2100=$(dateutils.daysInAYear 2100) 1600=$(dateutils.daysInAYear 1600)"
echo "--- between truncation"
a=$(dateutils.encodeDateTime 2011 3 26 0 0 0 0); b=$(dateutils.encodeDateTime 2011 3 27 23 59 59 999)
echo "daysBetween(26 00:00, 27 23:59:59.999)=$(dateutils.daysBetween $a $b) hoursBetween=$(dateutils.hoursBetween $a $b) (FPC trunc: 1 / 47)"
echo "--- sameTime / compareTime negatives"; a=$(dateutils.encodeDateTime 1899 12 29 12 0 0 0); b=$(dateutils.encodeDateTime 2011 3 26 12 0 0 0); echo "sameTime=$(dateutils.sameTime $a $b) compareTime=$(dateutils.compareTime $a $b) compareDate=$(dateutils.compareDate $a $b)"
echo "--- previousDayOfWeek 0 / 8"; dateutils.previousDayOfWeek 0; echo "rc=$?"; dateutils.previousDayOfWeek 8; echo "rc=$?"
echo "--- withinPastDays negative range / dateTimeInRange inclusive=false variants"; echo "inclusive 'false': $(dateutils.dateTimeInRange 5 5 10 false) ; inclusive '0': $(dateutils.dateTimeInRange 5 5 10 0) ; inclusive 'no': $(dateutils.dateTimeInRange 5 5 10 no)"
echo "--- yearsBetween exact with 3rd arg 'false': $(dateutils.yearsBetween $(dateutils.encodeDate 2001 1 1) $(dateutils.encodeDate 2002 1 1) false)"
echo "--- dateTimeToUnix negative ms floor: $(dateutils.dateTimeToUnix -1500) (FPC RecodeMillisecond->-2)"
echo "--- encodeDateTime 24:00:00.000 on 9999-12-31: $(dateutils.encodeDateTime 9999 12 31 24 0 0 0) -> $(dateutils.decodeDateTime "$(dateutils.encodeDateTime 9999 12 31 24 0 0 0)")"
echo "--- recodeDateTime with fewer args: "; dateutils.recodeDateTime 0 2011; echo "rc=$?"
echo "--- recodeHour to 24 (valid time 24:00:00.000): $(dateutils.recodeHour 0 24) -> $(f "$(dateutils.recodeHour 0 24)")"
echo "--- encodeDateDay 2000 60.5 / 2000 '1 1'"; dateutils.encodeDateDay 2000 '1 1'; echo "rc=$?"
echo "--- startOfADay 2-arg with 3rd empty: startOfADay 2011 85 '' -> "; dateutils.startOfADay 2011 85 ''; echo "rc=$?"
echo "--- weekOf/isValidDateWeek 9999 52 7 (FPC comment): $(dateutils.isValidDateWeek 9999 52 7) -> encodeDateWeek 9999 52 7 = $(f "$(dateutils.encodeDateWeek 9999 52 7)")"
