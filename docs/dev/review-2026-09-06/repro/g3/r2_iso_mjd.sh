source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
f() { dateutils._fmt_datetime "$1"; echo "$REPLY"; }
echo "--- _parse_iso accepts impossible day-of-month (FPC TryISOStrToDate -> TryEncodeDate rejects)"
for s in "2011-02-31" "2011-02-30T12:00:00Z" "2011-04-31" "0000-01-01" "2011-02-29"; do
  echo -n "tryISO8601ToDate $s -> "; if r=$(dateutils.tryISO8601ToDate "$s"); then f "$r"; else echo "REJECT rc=$?"; fi
done
echo -n "tryISOStrToDateTime 2011-02-31T00:00:00 -> "; r=$(dateutils.tryISOStrToDateTime 2011-02-31T00:00:00) && f "$r" || echo REJECT
echo -n "tryISOStrToDate 2011-02-31 -> "; dateutils.tryISOStrToDate 2011-02-31 || echo "REJECT (correct)"
echo "--- FPC forms not accepted"
echo -n "tryISOStrToTime 1915 -> "; dateutils.tryISOStrToTime 1915 || echo REJECT
echo -n "tryISOStrToTime 19 -> "; dateutils.tryISOStrToTime 19 || echo REJECT
echo -n "tryISOStrToTime 191530.555 -> "; dateutils.tryISOStrToTime 191530.555 || echo REJECT
echo -n "tryISOStrToDateTime 2011 -> "; dateutils.tryISOStrToDateTime 2011 || echo REJECT
echo -n "tryISOStrToDateTime 20110326 -> "; dateutils.tryISOStrToDateTime 20110326 || echo REJECT
echo -n "tryISOStrToDateTime T19:15 -> "; dateutils.tryISOStrToDateTime T19:15 || echo REJECT
echo -n "tryISOStrToTime 19:15:30+03:00 -> "; dateutils.tryISOStrToTime 19:15:30+03:00; echo
echo "--- MJD for dates before the MJD epoch (1858-11-17)"
k=$(dateutils.encodeDateTime 1858 11 16 12 0 0 0)
echo -n "dateTimeToModifiedJulianDate 1858-11-16 12:00 -> "; dateutils.dateTimeToModifiedJulianDate "$k"; echo " (expected -0.500000)"
k=$(dateutils.encodeDateTime 1800 1 1 6 0 0 0)
echo -n "dateTimeToModifiedJulianDate 1800-01-01 06:00 -> "; mj=$(dateutils.dateTimeToModifiedJulianDate "$k"); echo "$mj (perl: $(perl -e 'printf "%.6f", -21504+0.25-0'))"
echo -n "  roundtrip modifiedJulianDateToDateTime -> "; r=$(dateutils.modifiedJulianDateToDateTime "$mj") && f "$r" || echo "REJECT rc=$?"
echo -n "modifiedJulianDateToDateTime -0.5 -> "; r=$(dateutils.modifiedJulianDateToDateTime -0.5) && f "$r"
echo -n "modifiedJulianDateToDateTime -21503.75 -> "; r=$(dateutils.modifiedJulianDateToDateTime -21503.75) && f "$r"
echo "--- JD of year 1 (positive, sanity)"
echo -n "dateTimeToJulianDate 0001-01-01 -> "; dateutils.dateTimeToJulianDate "$(dateutils.encodeDate 1 1 1)"; echo " (expected 1721425.500000)"
echo "--- _jd_str_to_ms on bad input"
echo -n "julianDateToDateTime abc -> "; dateutils.julianDateToDateTime abc; echo " rc=$?"
echo -n "julianDateToDateTime '' -> "; dateutils.julianDateToDateTime ''; echo " rc=$?"
echo -n "julianDateToDateTime 2455277.5e3 -> "; dateutils.julianDateToDateTime 2455277.5e3; echo " rc=$?"
echo "--- tryEncodeTimeInterval negatives"
echo -n "tryEncodeTimeInterval -5 0 0 0 -> "; dateutils.tryEncodeTimeInterval -5 0 0 0; echo " rc=$?"
echo -n "tryEncodeTimeInterval 1 -30 0 0 -> "; dateutils.tryEncodeTimeInterval 1 -30 0 0; echo " rc=$?"
echo "--- scanDateTime trailing garbage / edge"
echo -n "scanDateTime yyyy-mm-dd 2011-03-26junk -> "; r=$(dateutils.scanDateTime yyyy-mm-dd 2011-03-26junk) && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy-mm-dd' '2011-03-2' -> "; r=$(dateutils.scanDateTime yyyy-mm-dd 2011-03-2) && f "$r" || echo REJECT
echo -n "scanDateTime 'hh:nn' '' -> "; r=$(dateutils.scanDateTime hh:nn '') && f "$r" || echo REJECT
echo -n "scanDateTime '' '' -> "; r=$(dateutils.scanDateTime '' '') && f "$r" || echo REJECT
echo -n "scanDateTime \"yyyy'abc\" 2011abc (unterminated quote) -> "; r=$(dateutils.scanDateTime "yyyy'abc" 2011abc) && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy mm' '2011 03' (space in pattern matches zero spaces?) 'yyyy mm' '201103' -> "; r=$(dateutils.scanDateTime 'yyyy mm' '201103') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy-mm-dd' '2011-03-26 ' (trailing space) -> "; r=$(dateutils.scanDateTime 'yyyy-mm-dd' '2011-03-26 ') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy-mm-dd hh:nn' '2011-03-26' (input shorter: elastic ws then hh) -> "; r=$(dateutils.scanDateTime 'yyyy-mm-dd hh:nn' '2011-03-26') && f "$r" || echo REJECT
echo -n "scanDateTime 'YYYY-MM-DD' uppercase glob char in input '2011-03-2*' -> "; r=$(dateutils.scanDateTime 'YYYY-MM-DD' '2011-03-2*') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy-mm-dd' '2011-03-*6' -> "; r=$(dateutils.scanDateTime 'yyyy-mm-dd' '2011-03-*6') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy-mm-dd' '2011-03-[6' -> "; r=$(dateutils.scanDateTime 'yyyy-mm-dd' '2011-03-[6') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy?mm' '2011-03' -> "; r=$(dateutils.scanDateTime 'yyyy?mm' '2011-03') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy*mm' '2011-03' -> "; r=$(dateutils.scanDateTime 'yyyy*mm' '2011-03') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy[-]mm' '2011-03' -> "; r=$(dateutils.scanDateTime 'yyyy[-]mm' '2011-03') && f "$r" || echo REJECT
echo -n "scanDateTime 'yyyy[-]mm' '2011[-]03' -> "; r=$(dateutils.scanDateTime 'yyyy[-]mm' '2011[-]03') && f "$r" || echo REJECT
