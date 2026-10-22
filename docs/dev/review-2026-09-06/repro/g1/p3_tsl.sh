source /c/projects/kkbot/kbool/kcl/tstringlist/tstringlist.sh
items(){ local -n a="${1}_items"; local IFS='|'; echo "${a[*]}"; }
echo "--- P3a: dupIgnore on UNSORTED list (FPC: Duplicates does nothing unless Sorted)"
TStringList.new L; L.duplicates = dupIgnore; L.Add a; L.Add a; echo "count=$(L.count) (FPC: 2)"; L.delete
TStringList.new L; L.duplicates = dupError; L.Add a; L.Add a; echo "dupError unsorted rc=$? count=$(L.count) (FPC: rc0, 2)"; L.delete
echo "--- P3b: sorted=true on populated unsorted list does not sort (FPC SetSorted sorts)"
TStringList.new L; L.Add banana; L.Add apple; L.Add cherry; L.sorted = true; L.Find apple; echo "Find apple -> $RESULT (FPC: 0 after auto-sort); items=$(items L)"; L.Add aardvark; echo "after Add aardvark: $(items L)"; L.delete
echo "--- P3c: items array leak after delete"
TStringList.new L; L.Add x; L.delete; declare -p L_items 2>&1 | head -1
echo "--- P3d: Assign does not copy sorted/case/dup flags; sorted dst gets unsorted content"
TStringList.new S; S.Add b; S.Add a; TStringList.new D; D.sorted = true; D.Assign S; echo "D sorted=$(D.sorted) items=$(items D) ; Find a -> $(D.Find a; echo $RESULT)"; S.delete; D.delete
echo "--- P3e: Assign/AddStrings fork count"
TStringList.new S; S.Add a; TStringList.new D
before=$(grep -c . /proc/self/status 2>/dev/null)  # not reliable; use bash trick instead
cnt=0; D.Assign S; echo "(see strace-less check below)"
S.delete; D.delete
echo "--- P3f: global i/j clobber"
TStringList.new L; L.Add a; L.Add b; i=5; j=6; L.IndexOf b; echo "i=$i"; L.sorted = true; L.Add c; echo "j=$j i=$i (expected 6 5)"; L.delete
echo "--- P3g: Find on empty sorted list"
TStringList.new L; L.sorted = true; L.Find x; echo "rc=$? RESULT=$RESULT"; L.delete
echo "--- P3h: case-insensitive compare uses locale collation: [[ < ]] order of 'a' vs 'B' with LANG"
TStringList.new L; L.case_sensitive = true; for x in b B a A; do L.Add $x; done; L.Sort; echo "LANG=$LANG LC_ALL=$LC_ALL sorted cs: $(items L)"; L.delete
echo "--- P3i: dupIgnore sorted returns existing index; dupError sorted RESULT preserved"
TStringList.new L; L.sorted=true; L.sorted = true; L.duplicates = dupIgnore; L.Add b; L.Add a; L.Add b; echo "RESULT=$RESULT (expected 1) count=$(L.count)"; L.delete
echo "--- P3j: leading dash / glob items"
TStringList.new L; L.Add '*'; L.Add '-n'; L.Add '[a]'; L.IndexOf '[a]'; echo "idx([a])=$RESULT"; L.IndexOf 'a'; echo "idx(a)=$RESULT (expected -1)"; L.Sort; echo "$(items L)"; L.delete
echo "--- P3k: dead test: 015 pattern present?"
grep -c "method Assign '{" /c/projects/kkbot/kbool/kcl/tstringlist/tstringlist.sh
echo "--- P3l: AddStrings with nonexistent source"
TStringList.new L; L.AddStrings nosuch 2>&1 | head -2; echo "rc=$?"; L.delete
echo "--- P3m: Sort sets sorted=true but subsequent Insert refused; Delete OK"
