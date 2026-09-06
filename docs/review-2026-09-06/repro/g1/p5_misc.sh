source /c/projects/kkbot/kbool/kcl/tstringlist/tstringlist.sh
echo "--- P5a: dupIgnore returns stale caller RESULT instead of existing index"
TStringList.new L; L.sorted = true; L.duplicates = dupIgnore
L.Add b >/dev/null; L.Add a >/dev/null      # list = a b ; existing index of b = 1
RESULT=SENTINEL; L.Add b; echo "rc=$? RESULT=$RESULT (expected 1)"
v=$(L.Add b); echo "\$(Add b) = [$v] (expected 1)"
L.delete
echo "--- P5b: kk._return echo -n: values starting with -e/-n/-E vanish under \$()"
TStringList.new L; for x in -e -n -E -en "-e x" "--" "-x"; do L.Add "$x" >/dev/null; done
n=$(L.count); for ((k=0;k<n;k++)); do L.Get $k; d=$RESULT; c=$(L.Get $k); printf 'direct=[%s] captured=[%s]\n' "$d" "$c"; done
L.delete
echo "--- P5c: unsorted-list IndexOf double-fold cost: perf of Add (unsorted, dupAccept) TStringList vs TList, n=300"
source /c/projects/kkbot/kbool/kcl/tlist/tlist.sh
TList.new A; t0=$EPOCHREALTIME; for ((k=0;k<300;k++)); do A.Add "item$k"; done; t1=$EPOCHREALTIME
TStringList.new B; for ((k=0;k<300;k++)); do B.Add "item$k"; done; t2=$EPOCHREALTIME
awk -v a="$t0" -v b="$t1" -v c="$t2" 'BEGIN{printf "TList 300 Adds: %.0f ms ; TStringList 300 Adds: %.0f ms\n",(b-a)*1000,(c-b)*1000}'
echo "--- P5d: sorted TStringList IndexOf is linear (n=300): time 20 lookups of last item"
B.Sort; t0=$EPOCHREALTIME; for ((k=0;k<20;k++)); do B.IndexOf "item99"; done; t1=$EPOCHREALTIME
awk -v a="$t0" -v b="$t1" 'BEGIN{printf "20 IndexOf on sorted n=300: %.0f ms (%.1f ms each)\n",(b-a)*1000,(b-a)*50}'
t0=$EPOCHREALTIME; for ((k=0;k<20;k++)); do B.Find "item99"; done; t1=$EPOCHREALTIME
awk -v a="$t0" -v b="$t1" 'BEGIN{printf "20 Find   on sorted n=300: %.0f ms\n",(b-a)*1000}'
A.delete; B.delete
echo "--- P5e: Assign/AddStrings fork: BASHPID inside \$source.count is a child"
TStringList.new S; S.Add a; TStringList.new D
# instrument: wrap S.count to record BASHPID seen
orig=$(declare -f S.count); eval "${orig/S.count ()/S_count_orig ()}"
S.count(){ echo "$BASHPID" >> "$HOME/.kcl_pid_probe"; S_count_orig "$@"; }
rm -f ~/.kcl_pid_probe; D.Assign S; D.AddStrings S
echo "parent=$$ pids-seen: $(tr '\n' ' ' < ~/.kcl_pid_probe)"; rm -f ~/.kcl_pid_probe
S.delete; D.delete
echo "--- P5f: TStringList IndexOf/Find on sorted list with dupAccept: FPC IndexOf uses Find; both find SOME index"
