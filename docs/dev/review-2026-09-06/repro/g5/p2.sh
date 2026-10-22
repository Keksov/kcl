source /c/projects/kkbot/kbool/kcl/tinifile/tinifile.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
echo "== D2: ifoEscapeLineFeeds trailing backslash on LAST line (clean fixture)"
printf '%s\n' '[s]' 'k=a\' > "$D/e.ini"; od -c "$D/e.ini" | head -2
TIniFile.new E "$D/e.ini" ifoEscapeLineFeeds; E.ReadString s k DEF; echo "got='$RESULT' expect(FPC RemoveBackslashes keeps last)='a\'"; E.delete
echo "== D3: escape join middle + a\ on middle line then blank"
printf '%s\n' '[s]' 'k=a\' '' 'n=1' > "$D/e2.ini"
TIniFile.new E2 "$D/e2.ini" ifoEscapeLineFeeds; E2.ReadString s k DEF; a=$RESULT; E2.ReadString s n DEF; echo "k='$a' n='$RESULT' (FPC: k='a' n='1')"; E2.delete

echo "== H: ifoEscapeLineFeeds + write of value ending in backslash -> silently joins after flush"
TMemIniFile.new W "$D/w.ini" ifoEscapeLineFeeds; W.WriteString p dir 'C:\App\'; W.WriteString p name x; W.UpdateFile
W.ReadString p dir DEF; echo "dir='$RESULT' (was 'C:\App\')"; W.ReadString p name DEF; echo "name='$RESULT' (was x)"; W.delete

echo "== I: eager DeleteKey/EraseSection flush failure -> rc?"
touch "$D/blk"; TIniFile.new EG "$D/blk/x.ini"; EG.WriteString s k v; echo "WriteString rc=$? (1 expected)"; EG.ReadString s k DEF; echo "memory kept: $RESULT"
EG.DeleteKey s k; echo "DeleteKey rc=$? (flush failed; WriteString said 1)"; EG.WriteString s k2 v2 2>/dev/null; EG.EraseSection s; echo "EraseSection rc=$?"; EG.delete

echo "== J: read-only existing target"
printf '[s]\nk=1\n' > "$D/ro.ini"; chmod 444 "$D/ro.ini"; ls -l "$D/ro.ini" | cut -c1-10
TIniFile.new RO "$D/ro.ini"; RO.WriteString s k 2; echo "rc=$?"; cat "$D/ro.ini"; ls -l "$D/ro.ini" | cut -c1-10; ls "$D" | grep tmp; RO.delete

echo "== K: backslash windows path to a missing dir"
TMemIniFile.new BS "$D\newdir\x.ini"; BS.WriteString a b c; BS.UpdateFile; echo "rc=$? exists=$([[ -f "$D/newdir/x.ini" ]] && echo y || echo n)"; BS.dirty = false; BS.delete

echo "== L: empty out-array name"
TIniFile.new EA "$D/none.ini"; EA.ReadSections ""; echo "rc=$? RESULT=$RESULT"; EA.delete

echo "== M: ident/value with spaces: pre-flush vs post-flush lookups"
TMemIniFile.new SP "$D/sp.ini"; SP.WriteString s "k " " v "; SP.ReadString s "k " DEF; a="[$RESULT]"; SP.ReadString s k DEF; b="[$RESULT]"; SP.UpdateFile; SP.ReadString s "k " DEF; c="[$RESULT]"; SP.ReadString s k DEF; d="[$RESULT]"; echo "pre: 'k '=$a k=$b | post: 'k '=$c k=$d"; SP.delete

echo "== N: dup section + EraseSection"
printf '[a]\nk=1\n[a]\nk=2\n' > "$D/dup.ini"; TMemIniFile.new DU "$D/dup.ini"; DU.EraseSection a; DU.SectionExists a; echo "after erase exists rc=$? (FPC parity: 0)"; DU.ReadString a k DEF; echo "k=$RESULT"; DU.dirty = false; DU.delete

echo "== O: unreadable file at Create"
printf '[s]\nk=1\n' > "$D/unr.ini"; chmod 000 "$D/unr.ini"; TIniFile.new UR "$D/unr.ini"; echo "rc=$?"; UR.SectionExists s; echo "exists rc=$?"; UR.delete; chmod 644 "$D/unr.ini"

echo "== P: quoted-space integer / bare x hex / trailing space"
TMemIniFile.new Q "$D/q.ini" ifoStripQuotes; Q.WriteString n a '" 5"'; Q.WriteString n b 'x1F'; Q.WriteString n c '"5 "'
Q.ReadInteger n a 0; echo "' 5'->$RESULT (FPC val skips leading blanks: 5)"; Q.ReadInteger n b 0; echo "'x1F'->$RESULT (FPC: 31)"; Q.ReadInteger n c 0; echo "'5 '->$RESULT (FPC: 0/default)"; Q.delete

echo "== R: caller out-array named like an instance var"
TMemIniFile.new NV "$D/nv.ini"; NV.WriteString s k v; dirty=(); NV.ReadSections dirty; echo "dirty via getter='$(NV.dirty)' arr=${dirty[*]}"; NV.dirty = false; NV.delete
