#!/bin/bash
# Micro-benchmark for tdictionary hot paths (P7.2).
# Thin-wrapper claims to prove:
#   - every operation is fork-free on the direct-call path;
#   - per-op cost is O(1) in the dictionary size (bash assoc = native hash);
#   - kklass instance dispatch dominates the cost (compare tlist.Add).
# Events are left unset — this measures the guard-off fast path.
# Uses the EPOCHREALTIME builtin (itself fork-free). Run: bash bench.sh [iters]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tdictionary.sh"
source "$DIR/../tlist/tlist.sh"             # reference point for instance-dispatch cost
source "$DIR/../tstopwatch/tstopwatch.sh"   # shared, tested µs clock (fork-free)

N=${1:-300}
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe µs clock shared by every kcl bench; RESULT-only, no fork.
report() {  # label total_us iters
    local us_per=$(( $2 / $3 ))
    printf '  %-28s %6d us/call  (%d.%03d ms)\n' "$1" "$us_per" $(( us_per/1000 )) $(( us_per%1000 ))
}

echo "tdictionary micro-benchmark  (bash ${BASH_VERSION}, N=$N)"
echo

echo "Core ops (fresh dict, unique keys; instance dispatch included):"
TDictionary.new d

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.Add "k$i" "v$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "Add (insert)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.TryGetValue "k$i" >/dev/null; done; TStopwatch.getTimeStamp; t1=$RESULT
report "TryGetValue (hit)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.GetItem "k$i" >/dev/null; done; TStopwatch.getTimeStamp; t1=$RESULT
report "GetItem (direct call)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.ContainsKey "k$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "ContainsKey (hit)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.ContainsKey "missing$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "ContainsKey (miss)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.AddOrSetValue "k5" "w$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "AddOrSetValue (overwrite)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.SetItem "k5" "u$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "SetItem (update)" $(( t1-t0 )) "$N"

TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do d.Remove "k$i"; done; TStopwatch.getTimeStamp; t1=$RESULT
report "Remove" $(( t1-t0 )) "$N"
d.delete

echo
echo "  informational — \$() capture adds a subshell fork per call:"
TDictionary.new dcap; dcap.Add x y
TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do v=$(dcap.GetItem x); done; TStopwatch.getTimeStamp; t1=$RESULT
report "GetItem via \$()" $(( t1-t0 )) "$N"
dcap.delete

echo
echo "ForEach (1000 pairs, no-op callback):"
TDictionary.new fe
for (( i=0; i<1000; i++ )); do fe_items["kx$i"]="v$i"; done   # direct seed (setup only)
_noop() { :; }
TStopwatch.getTimeStamp; t0=$RESULT; fe.ForEach _noop; TStopwatch.getTimeStamp; t1=$RESULT
report "ForEach per pair" $(( t1-t0 )) 1000
fe.delete

echo
echo "O(1) scaling check — same op at 1k vs 10k pairs (must be flat):"
TDictionary.new s1k;  for (( i=0; i<1000;  i++ )); do s1k_items["kx$i"]="v";  done
TDictionary.new s10k; for (( i=0; i<10000; i++ )); do s10k_items["kx$i"]="v"; done
TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do s1k.TryGetValue "kx$(( i % 1000 ))" >/dev/null; done; TStopwatch.getTimeStamp; t1=$RESULT
p1k=$(( (t1-t0) / N ))
report "TryGetValue @ 1k pairs" $(( t1-t0 )) "$N"
TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do s10k.TryGetValue "kx$(( i % 10000 ))" >/dev/null; done; TStopwatch.getTimeStamp; t1=$RESULT
p10k=$(( (t1-t0) / N ))
report "TryGetValue @ 10k pairs" $(( t1-t0 )) "$N"
if (( p10k <= p1k * 2 + 50 )); then
    echo "  OK — flat within noise (${p1k} vs ${p10k} us/call): O(1) confirmed"
else
    echo "  WARNING — per-op cost grew with dict size (${p1k} -> ${p10k} us/call)"
fi
s1k.delete; s10k.delete

echo
echo "zero-fork check (direct-call ops with empty PATH):"
TDictionary.new zf
if ( PATH=''
     zf.Add zk zv               || exit 1
     zf.TryGetValue zk >/dev/null || exit 1
     [[ "$RESULT" == "zv" ]]    || exit 1
     zf.ContainsKey zk          || exit 1
     zf.AddOrSetValue zk z2     || exit 1
     zf.Remove zk               || exit 1
     [[ "$(zf.count)" == "0" ]] || exit 1
   ); then
    echo "  OK — Add/TryGetValue/ContainsKey/AddOrSetValue/Remove/count spawned no external process"
else
    echo "  FAIL — an operation forked or failed under PATH=''"
fi
zf.delete

echo
echo "reference point — tlist instance dispatch (same kklass machinery):"
TList.new reflist
TStopwatch.getTimeStamp; t0=$RESULT; for (( i=0; i<N; i++ )); do reflist.Add "item$i" >/dev/null; done; TStopwatch.getTimeStamp; t1=$RESULT
report "tlist.Add" $(( t1-t0 )) "$N"
reflist.delete
