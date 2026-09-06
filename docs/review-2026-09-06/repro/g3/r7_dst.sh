source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
f() { dateutils._fmt_datetime "$1"; echo "$REPLY"; }
echo "TZ=$TZ now %z=$(printf '%(%z)T' -1)"
jan=$(dateutils.encodeDateTime 2026 1 15 12 0 0 0); jul=$(dateutils.encodeDateTime 2026 7 15 12 0 0 0)
echo "dateToISO8601 jan local -> $(dateutils.dateToISO8601 $jan false)   (perl: $(TZ=$TZ perl -MPOSIX -e 'print strftime("%z", localtime(mktime(0,0,12,15,0,126)))'))"
echo "dateToISO8601 jul local -> $(dateutils.dateToISO8601 $jul false)   (perl: $(TZ=$TZ perl -MPOSIX -e 'print strftime("%z", localtime(mktime(0,0,12,15,6,126)))'))"
echo "universalTimeToLocal jan 12:00Z -> $(f "$(dateutils.universalTimeToLocal $jan)")  (Berlin winter: 13:00)"
echo "unixToDateTime jan local -> $(f "$(dateutils.unixToDateTime $(( jan/1000 )) false)")  (Berlin winter: 13:00)"
echo "--- scanDateTime 'hh:mm:ss' (FPC: mm after hh = minutes)"
dateutils.scanDateTime 'yyyy-mm-dd hh:mm:ss' '2011-03-26 19:15:30'; echo " rc=$?"
dateutils.scanDateTime 'hh:mm' '19:15'; echo " rc=$?"
echo "--- scanDateTime pattern-space vs input-without-space & mm/dd swap"
echo "--- count public methods: $(grep -c 'static proc' /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh)"
