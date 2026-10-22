source /c/projects/kkbot/kbool/kcl/dateutils/dateutils.sh
echo "--- caller-side cost of the proc API: \$(dateutils.yearOf) x50"
k=1301166930555
t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do y=$(dateutils.yearOf $k); done; t1=$EPOCHREALTIME
perl -e "printf('\$(dateutils.yearOf): %.2f ms/call\n', ($t1-$t0)*1000/50)"
t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do dateutils.yearOf $k >/dev/null; done; t1=$EPOCHREALTIME
perl -e "printf('direct (stdout discarded): %.2f ms/call\n', ($t1-$t0)*1000/50)"
echo "--- local offset is the CURRENT offset for every date (code: printf %(%z)T -1)"
printf -v z1 '%(%z)T' 1736942400; printf -v z2 '%(%z)T' 1752580800; echo "printf %z for 2025-01-15=$z1  2025-07-15=$z2 (this host zone; DST zones differ)"
echo "--- isoTZStrToTZOffset garbage: '+ab:cd'"; dateutils.isoTZStrToTZOffset '+ab:cd'; echo " rc=$?"
echo "--- incYear out of FPC range: $(dateutils.decodeDate "$(dateutils.incYear "$(dateutils.encodeDate 9999 6 1)" 1)")"
