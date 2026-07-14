#!/bin/bash
# Micro-benchmark for tinifile (P4). Publishes the honest-positioning numbers:
#   - load: parse an N-key file (fork-free while-read + FillSectionList);
#   - ReadString hot path: per-lookup cost (linear first-match scan — FPC's own
#     model; config scale) at a few section/key counts;
#   - WriteString: update-in-place vs append, on a CACHED instance (no flush);
#   - UpdateFile: the one-flush cost (compose + tmp + mv + re-parse) at N keys;
#   - ReadInteger/ReadBool: the typed-parse overhead over ReadString;
#   - the zero-fork check on the in-memory paths (file I/O excepted by design).
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe µs clock shared by every kcl bench; RESULT-only, no fork.
# Run: bash bench.sh   (sizes fixed; deterministic, no $RANDOM)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tinifile.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-44s %6d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

# Build an ini file with S sections x K keys -> $BD/gen.ini ; echoes path.
mkini() {  # sections keys -> path
    local s k f="$BD/gen_$1x$2.ini"
    [[ -f "$f" ]] && { echo "$f"; return; }
    {
        for (( s=0; s<$1; s++ )); do
            echo "[section$s]"
            for (( k=0; k<$2; k++ )); do echo "key$k=value_${s}_${k}"; done
        done
    } > "$f"
    echo "$f"
}

echo "tinifile micro-benchmark  (bash ${BASH_VERSION})"
echo

# --- load: parse an N-key file ----------------------------------------------
echo "load (parse whole file at Create):"
for spec in "1 100" "10 100" "1 1000"; do
    set -- $spec
    f="$(mkini "$1" "$2")"; total=$(( $1 * $2 ))
    TStopwatch.getTimeStamp; t0=$RESULT
    TMemIniFile.new LD "$f"
    TStopwatch.getTimeStamp; t1=$RESULT
    LD.delete
    report "load ${1}sec x ${2}key = $total keys" $(( t1-t0 )) "$total" "key"
done

# --- ReadString hot path -----------------------------------------------------
echo
echo "ReadString (linear first-match lookup):"
for spec in "1 100" "10 100" "1 1000"; do
    set -- $spec
    f="$(mkini "$1" "$2")"
    TMemIniFile.new RD "$f"
    local_iters=500
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<local_iters; i++ )); do
        RD.ReadString "section0" "key$(( i % $2 ))" X >/dev/null
    done
    TStopwatch.getTimeStamp; t1=$RESULT
    RD.delete
    report "ReadString in ${1}sec x ${2}key" $(( t1-t0 )) "$local_iters" "read"
done

# --- WriteString: update vs append (cached, no flush) ------------------------
echo
echo "WriteString on a cached instance (no flush):"
TMemIniFile.new WR "$BD/wr.ini"
for (( k=0; k<200; k++ )); do WR.WriteString s "key$k" "v$k"; done   # warm 200 keys
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<200; i++ )); do WR.WriteString s "key$(( i % 200 ))" "u$i"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "update-in-place (200 keys present)" $(( t1-t0 )) 200 "write"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<200; i++ )); do WR.WriteString s "new$i" "v$i"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "append (new keys)" $(( t1-t0 )) 200 "write"
WR.dirty = "false"; WR.delete

# --- UpdateFile: the one-flush cost ------------------------------------------
echo
echo "UpdateFile (compose + tmp + mv + re-parse):"
for keys in 100 1000; do
    TMemIniFile.new UF "$BD/uf_$keys.ini"
    for (( k=0; k<keys; k++ )); do UF.WriteString s "key$k" "v$k"; done
    TStopwatch.getTimeStamp; t0=$RESULT
    UF.UpdateFile
    TStopwatch.getTimeStamp; t1=$RESULT
    UF.delete
    report "UpdateFile $keys keys" $(( t1-t0 )) "$keys" "key"
done

# --- typed-parse overhead over ReadString ------------------------------------
echo
echo "typed accessors (parse overhead over ReadString):"
TMemIniFile.new TY "$BD/ty.ini"
TY.WriteString n num 12345
TY.WriteString n flag 1
iters=500
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<iters; i++ )); do TY.ReadString n num X >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "ReadString baseline" $(( t1-t0 )) "$iters" "read"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<iters; i++ )); do TY.ReadInteger n num 0 >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "ReadInteger (+val parse)" $(( t1-t0 )) "$iters" "read"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<iters; i++ )); do TY.ReadBool n flag 0 >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "ReadBool (+cascade)" $(( t1-t0 )) "$iters" "read"
TY.dirty = "false"; TY.delete

# --- zero-fork check on the in-memory paths ----------------------------------
echo
echo "zero-fork check (in-memory paths under PATH=''):"
zf="$(
    PATH=''
    source "$DIR/tinifile.sh" 2>/dev/null
    TMemIniFile.new Z "$BD/z.ini"
    Z.WriteString s k v
    Z.WriteInteger s n 42
    Z.WriteBool s b true
    Z.ReadString s k X >/dev/null; a="$RESULT"
    Z.ReadInteger s n 0 >/dev/null; b="$RESULT"
    Z.ReadBool s b 0 >/dev/null; c="$RESULT"
    Z.DeleteKey s k
    Z.dirty = "false"; Z.delete
    printf '%s/%s/%s' "$a" "$b" "$c"
)"
if [[ "$zf" == "v/42/1" ]]; then
    echo "  in-memory Write*/Read*/DeleteKey need NO external commands (ok: $zf)"
else
    echo "  ZERO-FORK VIOLATION: got '$zf' (want v/42/1)"
fi
echo
echo "note: UpdateFile forks exactly once (mv), plus mkdir only when the target"
echo "      directory is missing — by design; every other path is fork-free."
