#!/bin/bash
# Micro-benchmark for thashset (P4.2). Publishes the honest-positioning numbers:
#   (a) per-op Add and Contains (hit and miss) at n=1000 and n=5000;
#   (b) per-op Remove at the same sizes;
#   (c) the SET ALGEBRA at 1k x 1k — UnionWith (disjoint), IntersectWith (50%
#       overlap), ExceptWith and SymmetricExceptWith — each printed as a ratio
#       to the 1k-Add baseline against the PLAN's 3x relative gate (the same
#       gate tests/005 section J asserts, here widened to all four ops);
#   (d) THE O(1) PROOF: Contains per-op at 100 vs 10 000 elements. `declare -A`
#       is a real hash table, so the two must be FLAT — ratio < 2.0 (a linear
#       scan would show ~100x). "Flat" is that number, not an adjective;
#   (e) the event gate: 1k Add unhooked vs the same loop with a do-nothing
#       listener attached (one `[[ ]]` per mutation vs a virtual dispatch);
#   (f) the zero-fork check: $BASHPID across a sequence of all 17 methods, plus
#       a membership-and-algebra sequence run under PATH=''.
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Deterministic: fixed sizes, no $RANDOM. Boolean members are called with
# `|| :` (the tests/005 shape) so the file also runs clean under `bash -eu`.
# Run: bash bench.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/thashset.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-46s %6d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

gate() {    # label value_us baseline_us limit_multiple
    local r10=$(( $2 * 10 / $3 )) lim=$(( $3 * $4 )) verdict
    if (( $2 <= lim )); then verdict="PASS"; else verdict="FAIL"; fi
    printf '  %-46s %6d ms  ratio %d.%dx of the 1k-Add baseline (gate %dx) %s\n' \
        "$1" $(( $2/1000 )) $(( r10/10 )) $(( r10%10 )) "$4" "$verdict"
}

echo "thashset micro-benchmark  (bash ${BASH_VERSION})"
echo

# --- (a) per-op Add / Contains ----------------------------------------------
echo "membership per-op (fresh set, unique elements):"
for n in 1000 5000; do
    THashSet.new H
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do H.Add "v$i" || :; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Add n=$n" $(( t1-t0 )) "$n" "op"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do H.Contains "v$i" || :; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Contains n=$n (hit)" $(( t1-t0 )) "$n" "op"
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do H.Contains "no$i" || :; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Contains n=$n (miss)" $(( t1-t0 )) "$n" "op"

    # --- (b) per-op Remove, on the set the loop above filled ----------------
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<n; i++ )); do H.Remove "v$i" || :; done
    TStopwatch.getTimeStamp; t1=$RESULT
    report "Remove n=$n" $(( t1-t0 )) "$n" "op"
    H.Count; left="$RESULT"
    [[ "$left" == "0" ]] || echo "  WARNING - the drain left $left elements behind"
    H.delete
done

# --- (c) set algebra at 1k x 1k, against the 3x relative gate ----------------
echo
echo "set algebra 1k x 1k (PLAN gate: no op may cost more than 3x a 1k Add loop):"
THashSet.new BASE
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<1000; i++ )); do BASE.Add "b$i" || :; done
TStopwatch.getTimeStamp; t1=$RESULT
base=$(( t1-t0 )); (( base > 0 )) || base=1
BASE.delete
report "baseline: 1k Add loop" "$base" 1000 "op"

THashSet.new U1; THashSet.new U2                  # disjoint 1k / 1k
for (( i=0; i<1000; i++ )); do U1.Add "u$i" || :; U2.Add "w$i" || :; done
TStopwatch.getTimeStamp; t0=$RESULT; U1.UnionWith U2; TStopwatch.getTimeStamp; t1=$RESULT
union=$(( t1-t0 )); U1.Count; nu="$RESULT"; U1.delete; U2.delete

THashSet.new I1; THashSet.new I2                  # 50% overlap
for (( i=0; i<1000; i++ )); do I1.Add "o$i" || :; done
for (( i=500; i<1500; i++ )); do I2.Add "o$i" || :; done
TStopwatch.getTimeStamp; t0=$RESULT; I1.IntersectWith I2; TStopwatch.getTimeStamp; t1=$RESULT
inter=$(( t1-t0 )); I1.Count; ni="$RESULT"; I1.delete; I2.delete

THashSet.new E1; THashSet.new E2                  # 50% overlap
for (( i=0; i<1000; i++ )); do E1.Add "o$i" || :; done
for (( i=500; i<1500; i++ )); do E2.Add "o$i" || :; done
TStopwatch.getTimeStamp; t0=$RESULT; E1.ExceptWith E2; TStopwatch.getTimeStamp; t1=$RESULT
except=$(( t1-t0 )); E1.Count; ne="$RESULT"; E1.delete; E2.delete

THashSet.new S1; THashSet.new S2                  # 50% overlap
for (( i=0; i<1000; i++ )); do S1.Add "o$i" || :; done
for (( i=500; i<1500; i++ )); do S2.Add "o$i" || :; done
TStopwatch.getTimeStamp; t0=$RESULT; S1.SymmetricExceptWith S2; TStopwatch.getTimeStamp; t1=$RESULT
symex=$(( t1-t0 )); S1.Count; ns="$RESULT"; S1.delete; S2.delete

gate "UnionWith 1k into a disjoint 1k"        "$union"  "$base" 3
gate "IntersectWith 1k x 1k (50% overlap)"    "$inter"  "$base" 3
gate "ExceptWith 1k x 1k (50% overlap)"       "$except" "$base" 3
gate "SymmetricExceptWith 1k x 1k (50%)"      "$symex"  "$base" 3
echo "  result sizes: union $nu (want 2000), intersect $ni (500), except $ne (500), symex $ns (1000)"
if [[ "$nu" == "2000" && "$ni" == "500" && "$ne" == "500" && "$ns" == "1000" ]]; then
    echo "  the four truth tables hold at this size"
else
    echo "  WARNING - an algebra result size is wrong; the timings above are meaningless"
fi

# --- (d) the O(1) flat check ------------------------------------------------
echo
echo "O(1) proof — Contains per-op at 100 vs 10 000 elements (must be FLAT):"
THashSet.new F100
for (( i=0; i<100; i++ )); do F100.Add "e$i" || :; done
THashSet.new F10K
for (( i=0; i<10000; i++ )); do F10K.Add "e$i" || :; done
P=2000
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<P; i++ )); do F100.Contains "e$(( i % 100 ))" || :; done
TStopwatch.getTimeStamp; t1=$RESULT
small=$(( t1-t0 )); report "Contains @ 100 elements" "$small" "$P" "op"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<P; i++ )); do F10K.Contains "e$(( i % 10000 ))" || :; done
TStopwatch.getTimeStamp; t1=$RESULT
big=$(( t1-t0 )); report "Contains @ 10 000 elements" "$big" "$P" "op"
(( small > 0 )) || small=1
f10=$(( big * 10 / small ))
printf '  ratio %d.%dx over a 100x larger set — FLAT means < 2.0x  ... %s\n' \
    $(( f10/10 )) $(( f10%10 )) "$( (( f10 < 20 )) && echo PASS || echo FAIL )"
echo "  (a linear scan would show ~100x here; declare -A is a real hash table)"
F100.delete; F10K.delete

# --- (e) event overhead -----------------------------------------------------
echo
echo "event gate — 1k Add unhooked vs the same loop with a do-nothing listener:"
_bench_noop() { :; }
THashSet.new NH
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<1000; i++ )); do NH.Add "n$i" || :; done
TStopwatch.getTimeStamp; t1=$RESULT
unhooked=$(( t1-t0 )); report "1k Add, no listener (gate skips dispatch)" "$unhooked" 1000 "op"
NH.delete
THashSet.new WH
WH.onNotify _bench_noop
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<1000; i++ )); do WH.Add "n$i" || :; done
TStopwatch.getTimeStamp; t1=$RESULT
hooked=$(( t1-t0 )); report "1k Add, do-nothing listener attached" "$hooked" 1000 "op"
WH.delete
(( unhooked > 0 )) || unhooked=1
e10=$(( hooked * 10 / unhooked ))
printf '  overhead %d.%dx — one virtual Notify dispatch plus the callback per element\n' \
    $(( e10/10 )) $(( e10%10 ))

# --- (f) zero-fork check ----------------------------------------------------
echo
echo "zero-fork check:"
THashSet.new ZA; THashSet.new ZB; THashSet.new ZC
declare -a zin=(p q) zout=()
_bench_each() { :; }
p0=$BASHPID; forked=0
ZA.Add a          || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.Add b          || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.Contains a     || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.Count            ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.Remove b       || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.Extract a        ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.AddRange c d e || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.AddRangeFromArray zin || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.ToArray zout     ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.ForEach _bench_each; [[ $BASHPID == "$p0" ]] || forked=1
ZB.Add e          || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.UnionWith ZB     ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.IntersectWith ZB ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.ExceptWith ZB    ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.AddRange f g   || :; [[ $BASHPID == "$p0" ]] || forked=1
ZA.SymmetricExceptWith ZB; [[ $BASHPID == "$p0" ]] || forked=1
ZC.Assign ZA        ;   [[ $BASHPID == "$p0" ]] || forked=1
ZC.onNotify _bench_noop; [[ $BASHPID == "$p0" ]] || forked=1
ZC.Notify x added   ;   [[ $BASHPID == "$p0" ]] || forked=1
ZC.Clear            ;   [[ $BASHPID == "$p0" ]] || forked=1
ZA.delete; ZB.delete; ZC.delete
[[ $BASHPID == "$p0" ]] || forked=1
if (( forked == 0 )); then
    echo "  BASHPID $p0 unchanged across all 17 methods + new/delete"
else
    echo "  ZERO-FORK VIOLATION: BASHPID changed during the member sequence"
fi

zf="$(
    PATH=''
    source "$DIR/thashset.sh" 2>/dev/null
    THashSet.new P; THashSet.new Q
    P.AddRange a b c || :
    declare -a inp=(d e) out=()
    P.AddRangeFromArray inp || :
    Q.AddRange c d f || :
    # NB: this whole block IS a $( ), so a `func` prints its value here (the
    # kklass return contract) — every func call is redirected away and read
    # from RESULT, exactly as tests/005 section I does it.
    P.UnionWith Q;        P.Count >/dev/null; u="$RESULT"     # a b c d e f = 6
    P.IntersectWith Q;    P.Count >/dev/null; n="$RESULT"     # c d f = 3
    P.ExceptWith Q;       P.Count >/dev/null; x="$RESULT"     # 0
    P.AddRange a b || :
    P.SymmetricExceptWith Q; P.Count >/dev/null; s="$RESULT"  # a b c d f = 5
    P.ToArray out >/dev/null;  t="$RESULT"
    P.Extract a  >/dev/null;   e="$RESULT"
    P.Clear;              P.Count >/dev/null; c="$RESULT"
    P.delete; Q.delete
    printf '%s|%s|%s|%s|%s|%s|%s' "$u" "$n" "$x" "$s" "$t" "$e" "$c"
)"
if [[ "$zf" == "6|3|0|5|5|a|0" ]]; then
    echo "  every member runs with an empty PATH — no external command anywhere (ok: $zf)"
else
    echo "  ZERO-FORK VIOLATION under PATH='': got '$zf' (want 6|3|0|5|5|a|0)"
fi

exit 0
