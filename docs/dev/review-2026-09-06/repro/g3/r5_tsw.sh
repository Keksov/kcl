source /c/projects/kkbot/kbool/kcl/tstopwatch/tstopwatch.sh
echo "bash $BASH_VERSION  EPOCHREALTIME=$EPOCHREALTIME  LC_ALL=$LC_ALL LC_NUMERIC=$LC_NUMERIC"
TStopwatch.new sw
echo "--- D1 contract: direct property read silent + RESULT"
RESULT=xx; out=$(sw.elapsedMilliseconds 2>&1); echo "captured=[$out]"
RESULT=xx; sw.elapsedMilliseconds > "$1/direct.out"; echo "direct stdout bytes=$(wc -c < "$1/direct.out") RESULT=[$RESULT]"
RESULT=xx; sw.isHighResolution > "$1/direct.out"; echo "isHighResolution direct bytes=$(wc -c < "$1/direct.out") RESULT=[$RESULT]"
echo "--- accumulation Start/Stop/Start/Stop with white-box seeded clock"
sw.Start; sw.Stop; sw_data[_accum]=5000; sw.Start; sw.Stop; sw.GetElapsedMicroseconds; echo "accum after seed 5000 + tiny segment: $RESULT (>=5000 expected)"
sw.Reset; sw.GetElapsedMicroseconds; echo "after Reset: $RESULT running=$(sw.isRunning)"
sw.Restart; echo "after Restart running=$(sw.isRunning)"; sw.Stop
echo "--- ctor bad token rc via .new"; TStopwatch.new b2 bogus; echo "rc=$?"; declare -p b2_data 2>/dev/null | head -c 120; echo; b2.delete
echo "--- delete frees data/class"; TStopwatch.new d1; d1.delete; declare -p d1_data d1_class 2>&1 | head -2; declare -F d1.Start || echo "d1.Start wrapper gone"
echo "--- elapsed while running with seeded _t0 in the past (exactness of parse)"
TStopwatch.new r startnew; r_data[_t0]=$(( r_data[_t0] - 1234567 )); r.GetElapsedMilliseconds; echo "ms=$RESULT (>=1234)"; r.GetElapsedSeconds; echo "s=$RESULT (>=1)"; r.delete
echo "--- negative elapsed if clock steps back (documented)"; TStopwatch.new n startnew; n_data[_t0]=$(( n_data[_t0] + 10000000 )); n.GetElapsedMilliseconds; echo "ms=$RESULT"; n.delete
echo "--- timing: property vs func read cost (N=50)"
TStopwatch.new p
t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do p.elapsedMicroseconds; done; t1=$EPOCHREALTIME
perl -e "printf('property direct: %.2f ms/call\n', ($t1-$t0)*1000/50)"
t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do p.GetElapsedMicroseconds; done; t1=$EPOCHREALTIME
perl -e "printf('func direct: %.2f ms/call\n', ($t1-$t0)*1000/50)"
t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do TStopwatch.getTimeStamp; done; t1=$EPOCHREALTIME
perl -e "printf('getTimeStamp: %.4f ms/call\n', ($t1-$t0)*1000/50)"
p.delete
echo "--- re-source"; source /c/projects/kkbot/kbool/kcl/tstopwatch/tstopwatch.sh; echo "re-source rc=$?"
echo "--- fresh watch Start then Stop within same µs => 0; Stop sets _t0=0 then Start again"; TStopwatch.new z; z.Start; z.Stop; z.Start; z.Stop; z.GetElapsedMicroseconds; echo "us=$RESULT"; z.delete
