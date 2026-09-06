#!/bin/bash
KCL=/c/projects/kkbot/kbool/kcl
probe() { # label, command...
  local label=$1; shift
  local out err rc
  RESULT="<unset>"; REPLY="<unset>"
  { out=$( { "$@" ; } 2>"$G8/err.tmp" ); rc=$?; } 
  err=$(cat "$G8/err.tmp")
  printf '%-45s rc=%-3s stdout=[%s] stderr=[%s]\n' "$label" "$rc" "${out:0:60}" "${err:0:80}"
}
probe2() { # direct call in current shell to see RESULT
  local label=$1; shift; RESULT="<unset>"; REPLY="<unset>"
  "$@" >"$G8/out.tmp" 2>"$G8/err.tmp"; local rc=$?
  printf '%-45s rc=%-3s RESULT=[%s] stdout=[%s] stderr=[%s]\n' "$label" "$rc" "${RESULT:0:40}" "$(head -c60 $G8/out.tmp)" "$(head -c80 $G8/err.tmp)"
}
G8=$(dirname "$0")
for u in tlist tdictionary thashset tqueuestack tinifile tstringlist tobjectlist tstopwatch tcustomapplication tarray tfile tdirectory tpath tregex tstringhelper dateutils math; do source $KCL/$u/$u.sh; done
echo "--- tlist"; TList.new L; L.Add a >/dev/null; probe2 "TList.Get 5 (OOR)" L.Get 5; probe2 "TList.Delete 5 (OOR)" L.Delete 5; probe2 "TList.Get -1" L.Get -1; probe2 "TList.Get abc" L.Get abc
echo "--- tstringlist"; TStringList.new S; S.Add x >/dev/null; probe2 "TStringList.Get 9 (OOR)" S.Get 9; probe2 "TStringList.Delete 9" S.Delete 9
echo "--- tdictionary"; TDictionary.new D; D.Add k v; probe2 "TDictionary.GetItem missing" D.GetItem nokey; probe2 "TDictionary.Add dup" D.Add k v2; probe2 "TDictionary.Remove missing" D.Remove zz
echo "--- thashset"; THashSet.new H; probe2 "THashSet.Extract missing" H.Extract zz; probe2 "THashSet.Remove missing" H.Remove zz
echo "--- tqueuestack"; TQueue.new Q; probe2 "TQueue.Dequeue empty" Q.Dequeue; probe2 "TQueue.Peek empty" Q.Peek; TStack.new St; probe2 "TStack.Pop empty" St.Pop
echo "--- tobjectlist"; TObjectList.new O; probe2 "TObjectList.Extract missing" O.Extract nothing; probe2 "TObjectList.Get 3 OOR" O.Get 3
echo "--- tinifile"; probe2 "TIniFile.new on /nonexist/dir/x.ini" TIniFile.new I /nonexistent_dir_g8/x.ini; probe2 "I.ReadString missing" I.ReadString sec key dflt; probe2 "I.WriteString+UpdateFile bad dir" I.WriteString s k v; probe2 "I.UpdateFile" I.UpdateFile
echo "--- tstopwatch"; probe2 "TStopwatch.new bad token" TStopwatch.new W bogus
echo "--- tarray"; probe2 "TArray.indexOf on empty arr" TArray.indexOf emptyarr x; probe2 "TArray.sort undefined var" TArray.sort nosucharr
echo "--- tfile"; probe2 "tfile.readAllText missing" tfile.readAllText /nonexistent_g8.txt; probe2 "tfile.delete missing" tfile.delete /nonexistent_g8.txt; probe2 "tfile.copy missing" tfile.copy /nonexistent_g8.txt /tmp/g8x
echo "--- tdirectory"; probe2 "tdirectory.getFiles missing" tdirectory.getFiles /nonexistent_g8; probe2 "tdirectory.delete missing" tdirectory.delete /nonexistent_g8
echo "--- tpath"; probe2 "tpath.combine '' ''" tpath.combine "" ""; probe2 "tpath.getFullPath ''" tpath.getFullPath ""
echo "--- tregex"; probe2 "TRegEx.isMatch bad pattern" TRegEx.isMatch 'a(' abc; probe2 "TRegEx.match bad pattern" TRegEx.match 'a(' abc
echo "--- tstringhelper"; probe2 "string.substring OOR" string.substring abc 10 2; probe2 "string.substring neg" string.substring abc -1 2; probe2 "string.chars OOR" string.chars abc 10
echo "--- dateutils"; probe2 "dateutils.encodeDate 2024 13 1" dateutils.encodeDate 2024 13 1; probe2 "dateutils.decodeDate abc" dateutils.decodeDate abc
echo "--- math"; probe2 "math.sqrt -1" math.sqrt -1; probe2 "math.ln 0" math.ln 0; probe2 "math.max abc 1" math.max abc 1; probe2 "math.sqrt ''" math.sqrt ""; probe2 "math.power 2 abc" math.power 2 abc
echo "--- tcustomapplication"; TCustomApplication.new A; probe2 "A.GetOptionValue missing" A.GetOptionValue x missing; probe2 "A.SetArgs --bogus" A.SetArgs --bogus; probe2 "A.CheckOptions" A.CheckOptions "h" "help"
echo "SHELL STILL ALIVE"
