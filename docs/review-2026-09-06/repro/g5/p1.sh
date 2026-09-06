source /c/projects/kkbot/kbool/kcl/tinifile/tinifile.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
echo "== A: dirty after typed writes on cached instance"
TMemIniFile.new M "$D/m.ini"
M.WriteInteger s k 5;  echo "after WriteInteger dirty=$(M.dirty) (expect true)"
M.dirty = false
M.WriteBool s b 1;     echo "after WriteBool dirty=$(M.dirty) (expect true)"
M.dirty = false
M.WriteFloat s f 1.5;  echo "after WriteFloat dirty=$(M.dirty) (expect true)"
M.dirty = false
M.WriteString s z 1;   echo "after WriteString dirty=$(M.dirty) (expect true)"
M.delete
echo "file exists after delete? $([[ -f $D/m.ini ]] && echo yes || echo no)"
echo "== A2: destroy-flush after only WriteInteger"
TMemIniFile.new M2 "$D/m2.ini"; M2.WriteInteger s k 5; M2.delete
echo "m2.ini exists: $([[ -f $D/m2.ini ]] && echo yes || echo NO-DATA-LOST)"

echo "== B: file_name is a directory"
mkdir "$D/adir"
TIniFile.new X "$D/adir"; X.WriteString a b c; echo "rc=$? dirty=$(X.dirty)"; ls -la "$D/adir"; X.delete

echo "== C: filename starting with dash (relative)"
cd "$D"; TIniFile.new Y "-x.ini"; Y.WriteString a b c; echo "rc=$? exists=$([[ -f ./-x.ini ]] && echo y || echo n)"; Y.delete; ls; cd /

echo "== D: ifoEscapeLineFeeds trailing backslash on LAST line"
printf '[s]\nk=a\\n' > "$D/e.ini"
TIniFile.new E "$D/e.ini" ifoEscapeLineFeeds; E.ReadString s k DEF; echo "got='$RESULT' expect(FPC)='a\'"; E.delete

echo "== E: [;x] section round trip"
printf '[;x]\nk=v\n[y]\nz=1\n' > "$D/c.ini"
TMemIniFile.new C "$D/c.ini"; C.UpdateFile; cat "$D/c.ini"; echo "---"; C.SectionExists ';x'; echo "exists rc=$?"; C.delete
TMemIniFile.new C2 "$D/c.ini"; S=(); C2.ReadSections S; echo "sections after roundtrip: ${S[*]}"; C2.delete

echo "== F: ident starting [ + value ending ] becomes a section after flush"
TMemIniFile.new F "$D/f.ini"; F.WriteString s "[list" "1,2]"; F.WriteString s other 9; F.UpdateFile
F.ReadString s "[list" DEF; echo "after flush ReadString=[$RESULT] expect 1,2]"; F.SectionExists "list=1,2"; echo "section 'list=1,2' exists rc=$? (0=corruption)"; cat "$D/f.ini"; F.delete

echo "== G: integer overflow handling"
TMemIniFile.new I "$D/i.ini"; I.WriteString n big '99999999999999999999'; I.WriteString n hx '$FFFFFFFFFFFFFFFFFFFF'
I.ReadInteger n big 7; echo "big=$RESULT"; I.ReadInteger n hx 7; echo "hx=$RESULT"; I.delete
