source /c/projects/kkbot/kbool/kcl/tinifile/tinifile.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
echo "== S: SectionExists on an EMPTY section (FPC: Assigned(S) and not S.Empty -> False)"
printf '[empty]\n[c]\n; only a comment\n[full]\nk=1\n' > "$D/s.ini"
TMemIniFile.new S "$D/s.ini"; S.SectionExists empty; a=$?; S.SectionExists c; b=$?; S.SectionExists full; c=$?
echo "empty rc=$a  comment-only rc=$b  full rc=$c   (FPC: 1 / ? / 0)"
S.WriteString n k v; S.DeleteKey n k; S.SectionExists n; echo "after write+delete: rc=$? (FPC: 1 = not exists)"; S.dirty=false; S.dirty = false; S.delete

echo "== T: O(N^2) append: WriteString N new keys, cached (no flush)"
for N in 200 400 800; do
  TMemIniFile.new A "$D/a$N.ini"
  t0=$EPOCHREALTIME
  for ((i=0;i<N;i++)); do A.WriteString s "key$i" "v$i"; done
  t1=$EPOCHREALTIME
  A.dirty = false; A.delete
  printf 'N=%d  total=%.0f ms  per-write=%.2f ms\n' $N "$(( (${t1/./}-${t0/./}) ))e-3" "$(( (${t1/./}-${t0/./}) / N ))e-3"
done

echo "== U: ReadString cost vs position — key in LAST section (findKey scans ALL rows)"
{ for s in $(seq 1 20); do echo "[sec$s]"; for k in $(seq 1 50); do echo "k$k=v"; done; done; } > "$D/big.ini"
TMemIniFile.new B "$D/big.ini"
for sec in sec1 sec20; do t0=$EPOCHREALTIME; for ((i=0;i<50;i++)); do B.ReadString $sec k50 X; done; t1=$EPOCHREALTIME
  printf '%s k50: %.2f ms/lookup\n' $sec "$(( (${t1/./}-${t0/./}) / 50 ))e-3"; done
B.delete

echo "== V: eager UpdateFile cost per write at 1000 keys (compose+mv+reparse)"
TIniFile.new EG "$D/big.ini"; t0=$EPOCHREALTIME; for ((i=0;i<5;i++)); do EG.WriteString sec1 k1 $i; done; t1=$EPOCHREALTIME
printf 'eager WriteString @1000 keys: %.1f ms/write\n' "$(( (${t1/./}-${t0/./}) / 5 ))e-3"; EG.delete

echo "== W: temp file left behind when the target replace fails (dash name already shown); also check tmp naming collision across instances"
cd "$D"; TIniFile.new DN "-y.ini"; DN.WriteString a b c 2>/dev/null; echo "rc=$?"; ls -1 "$D" | grep -- '-y' ; cd /

echo "== X: section name with leading/trailing spaces + name ' '"
TMemIniFile.new SS "$D/ss.ini"; SS.WriteString " s " k v; SS.UpdateFile; cat "$D/ss.ini"; SS.ReadString " s " k DEF; echo "lookup ' s '=$RESULT"; SS.ReadString s k DEF; echo "lookup 's'=$RESULT (FPC: DEF too)"; SS.delete

echo "== Y: ident containing ']' with value; ident '[x]' "
TMemIniFile.new BR "$D/br.ini"; BR.WriteString s "[x]" v; BR.WriteString s "[y]" ""; BR.UpdateFile; cat "$D/br.ini"; BR.ReadString s "[y]" DEF; echo "[y] after flush -> '$RESULT' (expected '')"; BR.delete

echo "== Z: Create with a value line '=bare' vs bare, ReadSection idents"
printf '[s]\n=bare\nbare2\n' > "$D/z.ini"; TMemIniFile.new ZZ "$D/z.ini"; K=(); ZZ.ReadSection s K; echo "count=${#K[@]} idents=[${K[0]}][${K[1]}]"; ZZ.delete
