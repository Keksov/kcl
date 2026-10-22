source /c/projects/kkbot/kbool/kcl/tqueuestack/tqueuestack.sh
source /c/projects/kkbot/kbool/kcl/tlist/tlist.sh
echo "bash $BASH_VERSION"
echo "--- ToArray with bad/empty names"
TQueue.new Q; Q.Enqueue a; Q.Enqueue b
Q.ToArray ""; echo "ToArray '' rc=$? RESULT=$RESULT"
Q.ToArray "bad name"; echo "ToArray 'bad name' rc=$? RESULT=$RESULT"
Q.ToArray "__tqs_it"; echo "ToArray __tqs_it rc=$? RESULT=$RESULT"; Q.Count; echo "count after=$RESULT"
Q.ToArray "__tqs_i"; echo "ToArray __tqs_i rc=$? RESULT=$RESULT"
declare -A AS; Q.ToArray AS; echo "ToArray assoc rc=$? RESULT=$RESULT"; declare -p AS
echo "--- TObjectQueue.Dequeue nonempty rc + RESULT"
TObjectQueue.new OQ false
OQ.Enqueue "plain"
RESULT=SENT; OQ.Dequeue; echo "rc=$? RESULT=$RESULT"
OQ.Count; echo "count=$RESULT"
OQ.delete
echo "--- TObjectQueue owning with duplicate handle: Dequeue frees at first removal, then second entry dead"
TList.new L1; TObjectQueue.new OQ2
OQ2.Enqueue L1; OQ2.Enqueue L1
OQ2.Dequeue; declare -F L1.delete >/dev/null && echo "L1 alive" || echo "L1 dead after first dequeue"
OQ2.Peek; echo "Peek=$RESULT (dead handle still queued)"
OQ2.delete
echo "--- ctor bad token: instance state"
TObjectQueue.new BQ bogus 2>&1; echo "new rc=$?"; echo "owns=$(BQ.owns_objects)"; BQ.delete
echo "--- fuzz queue vs reference (interleaved, crossing compaction)"
TQueue.new F; ref=(); rh=0; bad=0
RANDOM=42
for ((i=0;i<4000;i++)); do
  r=$((RANDOM%3))
  if (( r < 2 )); then F.Enqueue "v$i"; ref+=("v$i")
  else
    F.Dequeue 2>/dev/null; rc=$?; got=$RESULT
    if (( rh < ${#ref[@]} )); then exp="${ref[rh]}"; ((rh++)); erc=0; else exp=""; erc=1; fi
    if [[ "$got" != "$exp" || $rc -ne $erc ]]; then echo "MISMATCH at $i got=$got exp=$exp rc=$rc erc=$erc"; bad=1; break; fi
    if (( rh == ${#ref[@]} )); then ref=(); rh=0; fi
  fi
  F.Count; if (( RESULT != ${#ref[@]} - rh )); then echo "COUNT MISMATCH at $i"; bad=1; break; fi
done
hv=F_qhead; echo "fuzz done bad=$bad final count=$RESULT qhead=${!hv} maxidx=$(( $(printf '%s\n' "${!F_items[@]}" | tail -1) ))"
T=(); F.ToArray T; ok=1; for ((j=0;j<${#T[@]};j++)); do [[ "${T[j]}" == "${ref[rh+j]}" ]] || ok=0; done; echo "ToArray matches ref: $ok"
F.delete
echo "--- set -e smoke"
( set -e
  TQueue.new E; E.Enqueue 1; E.Dequeue; E.TryDequeue || true; E.Clear; E.Count; E.delete
  TStack.new ES; ES.Push 1; ES.Pop; ES.Peek 2>/dev/null || true; ES.Clear; ES.delete
  echo "set -e smoke ok"
)
echo "--- Peek/Dequeue in \$() lose state?"
TQueue.new P; P.Enqueue z
x="$(P.Dequeue)"; P.Count; echo "captured=$x count-after=$RESULT (expected 1: \$() loses mutation)"
P.delete
