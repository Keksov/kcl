#!/bin/bash
# Micro-benchmark for tqueuestack (P5). Publishes the honest-positioning numbers:
#   - per-op Enqueue/Dequeue and Push/Pop cost at a few sizes;
#   - THE COMPACTION PROOF: a 10k interleaved-then-drained queue must show flat
#     per-op cost (amortized O(1)) — if the reindex were O(n) per op the drain
#     would be quadratic; we print per-op over the whole drain to show it isn't;
#   - the review-#2 measurement: Clear of a large queue with vs without the
#     mid-drain reindex (informational — is the wasted copy measurable?);
#   - the review-#4 measurement: non-owning TObjectQueue per-op overhead (the
#     unconditional-nhook no-op Notify dispatch) vs a plain TQueue;
#   - vs tlist.Add as a same-family reference point;
#   - the zero-fork check on every in-memory op.
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Run: bash bench.sh   (sizes fixed; deterministic, no $RANDOM)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tqueuestack.sh"
source "$DIR/../tlist/tlist.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-46s %6d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

echo "tqueuestack micro-benchmark  (bash ${BASH_VERSION})"
echo

# --- per-op Enqueue / Dequeue ------------------------------------------------
echo "TQueue per-op (fill then drain):"
for n in 1000 5000; do
    TQueue.new Q
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do Q.Enqueue "v$i"; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Enqueue n=$n" $(( t1-t0 )) "$n" "op"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do Q.Dequeue >/dev/null; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Dequeue n=$n" $(( t1-t0 )) "$n" "op"
    Q.delete
done

# --- per-op Push / Pop -------------------------------------------------------
echo
echo "TStack per-op (fill then drain):"
for n in 1000 5000; do
    TStack.new S
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do S.Push "v$i"; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Push n=$n" $(( t1-t0 )) "$n" "op"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do S.Pop >/dev/null; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Pop n=$n" $(( t1-t0 )) "$n" "op"
    S.delete
done

# --- THE COMPACTION PROOF: 10k interleaved drain, flat per-op ----------------
# Enqueue 10k, then dequeue 10k. The head walks 0..10k with periodic reindex.
# If per-op cost is flat (not rising with n), the reindex is truly amortized.
echo
echo "compaction proof (10k enqueue + 10k dequeue, per-op must stay flat):"
TQueue.new C
for (( i=0; i<10000; i++ )); do C.Enqueue "v$i"; done
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<10000; i++ )); do C.Dequeue >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "10k drain (amortized O(1) if flat vs n=1000)" $(( t1-t0 )) 10000 "op"
C.delete
echo "  ^ compare this us/op to Dequeue n=1000 above: near-equal => amortized flat"

# --- review-#2: Clear cost on a large queue (the mid-drain reindex) ----------
echo
echo "review-#2 (Clear of a 4000-element queue — mid-drain reindex cost):"
TQueue.new K
for (( i=0; i<4000; i++ )); do K.Enqueue "v$i"; done
TStopwatch.getTimeStamp; t0=$RESULT
K.Clear
TStopwatch.getTimeStamp; t1=$RESULT
report "Clear 4000 (one wasted O(n/2) copy at midpoint)" $(( t1-t0 )) 4000 "el"
K.delete
echo "  ^ informational: the reindex adds ~one 2000-element array copy to Clear"

# --- review-#4: non-owning TObjectQueue overhead (unconditional nhook) -------
echo
echo "review-#4 (non-owning TObjectQueue no-op Notify dispatch per op):"
TQueue.new PQ
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<2000; i++ )); do PQ.Enqueue "v$i"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "plain TQueue.Enqueue (gate skips dispatch)" $(( t1-t0 )) 2000 "op"
PQ.delete
TObjectQueue.new OQ false
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<2000; i++ )); do OQ.Enqueue "v$i"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "non-owning TObjectQueue.Enqueue (nhook dispatch)" $(( t1-t0 )) 2000 "op"
OQ.delete
echo "  ^ the delta is the no-op virtual Notify dispatch (S10 flip needs nhook armed)"

# --- vs tlist.Add reference --------------------------------------------------
echo
echo "reference: tlist.Add (same kklass instance-method family):"
TList.new L
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<2000; i++ )); do L.Add "v$i"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "TList.Add n=2000" $(( t1-t0 )) 2000 "op"
L.delete

# --- zero-fork check ---------------------------------------------------------
echo
echo "zero-fork check (in-memory ops under PATH=''):"
zf="$(
    PATH=''
    source "$DIR/tqueuestack.sh" 2>/dev/null
    TQueue.new Z; TStack.new ZS
    Z.Enqueue a; Z.Enqueue b
    Z.Dequeue >/dev/null; a="$RESULT"
    Z.Peek >/dev/null; b="$RESULT"
    ZS.Push x; ZS.Pop >/dev/null; c="$RESULT"
    O=(); Z.ToArray O >/dev/null
    Z.Clear; ZS.Clear
    Z.delete; ZS.delete
    printf '%s/%s/%s/%s' "$a" "$b" "$c" "${#O[@]}"
)"
if [[ "$zf" == "a/b/x/1" ]]; then
    echo "  Enqueue/Dequeue/Peek/Push/Pop/ToArray/Clear need NO external commands (ok: $zf)"
else
    echo "  ZERO-FORK VIOLATION: got '$zf' (want a/b/x/1)"
fi
