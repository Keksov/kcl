echo "bash $BASH_VERSION"
for loc in de_DE.UTF-8 ru_RU.UTF-8 C; do
  LC_ALL=$loc bash -c 'echo "LC_ALL=$LC_ALL EPOCHREALTIME=$EPOCHREALTIME"' 2>&1
done
export LC_ALL=de_DE.UTF-8
source /c/projects/kkbot/kbool/kcl/tstopwatch/tstopwatch.sh
source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
echo "under LC_ALL=de_DE.UTF-8: EPOCHREALTIME=$EPOCHREALTIME"
TStopwatch.getTimeStamp; echo "getTimeStamp=$RESULT"
TStopwatch.new s startnew; s.GetElapsedMicroseconds; echo "elapsed=$RESULT"; s.delete
echo "nowUTC=$(dateutils.nowUTC) now=$(dateutils.now) (vs EPOCHSECONDS*1000=$((EPOCHSECONDS*1000)))"
printf -v z '%(%z)T' -1; echo "%z=$z"
echo "daySpan output under de locale: $(dateutils.daySpan 43200000 0)  JD: $(dateutils.dateTimeToJulianDate 0)"
