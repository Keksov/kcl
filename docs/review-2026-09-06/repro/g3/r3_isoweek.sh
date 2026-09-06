# Cross-check ISO week/year/dow and day-of-week vs perl over all days 1995..2035 (internal helpers, no forks per call)
source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
perl -MPOSIX -e 'for($d=0;$d<41*366;$d++){ @t=gmtime(($d+9131)*86400); $iso=strftime("%G %V %u %Y %j",@t); print(($d+9131)," $iso\n"); }' > "$1/perl_week.txt"
bad=0; n=0
while read -r day gy gw gu y j; do
  kdt=$(( day*86400000 + 13*3600000 ))
  dateutils._decode_date_week "$kdt"; n=$((n+1))
  if (( __kdt_wy_year != 10#$gy || __kdt_wy_week != 10#$gw || __kdt_wy_dow != 10#$gu )); then bad=$((bad+1)); (( bad<=5 )) && echo "MISMATCH day=$day want $gy $gw $gu got $__kdt_wy_year $__kdt_wy_week $__kdt_wy_dow"; fi
  dateutils._weekday_iso "$kdt"; [[ "$REPLY" == "$gu" ]] || { echo "DOW MISMATCH day=$day"; bad=$((bad+1)); }
  # roundtrip encode
  dateutils._encode_date_week "$__kdt_wy_year" "$__kdt_wy_week" "$__kdt_wy_dow" || { echo "ENCODE FAIL $gy $gw $gu"; bad=$((bad+1)); continue; }
  (( REPLY == day*86400000 )) || { echo "RT MISMATCH day=$day"; bad=$((bad+1)); }
  # day of year
  dateutils._split_kdt "$kdt"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY; doy=$(( day - ys + 1 ))
  (( doy == 10#$j )) || { echo "DOY MISMATCH day=$day"; bad=$((bad+1)); }
done < "$1/perl_week.txt"
echo "checked $n days, mismatches=$bad"
# weeksInAYear vs perl (Dec 28 always in last week)
bad=0
for y in $(seq 1900 2100); do
  w=$(perl -MPOSIX -e 'my @t=(0,0,12,28,11,'"$y"'-1900); print strftime("%V", @t)'); dateutils._weeks_in_year "$y"; [[ "${REPLY}" == "$((10#$w))" ]] || { echo "WIY $y want $w got $REPLY"; bad=$((bad+1)); }
done; echo "weeksInAYear 1900..2100 mismatches=$bad"
