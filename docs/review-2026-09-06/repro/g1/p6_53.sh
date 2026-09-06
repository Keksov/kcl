echo "bash $BASH_VERSION"
source /c/projects/kkbot/kbool/kcl/tstringlist/tstringlist.sh
TStringList.new L; L.Add "-e" >/dev/null; c=$(L.Get 0); echo "captured -e = [$c]"
L.sorted = true; L.duplicates = dupIgnore; L.Add b >/dev/null; RESULT=S; L.Add b; echo "dupIgnore RESULT=$RESULT"
L.delete; declare -p L_items 2>&1 | head -1
( set -u; TList.new U; U.delete; echo "set -u delete rc=$?" ) 2>&1 | tail -1
