#!/bin/bash
KCL=/c/projects/kkbot/kbool/kcl
for u in dateutils math tarray tdirectory tfile tpath tregex tstringhelper tlist tdictionary thashset tqueuestack tinifile tstopwatch tcustomapplication; do source $KCL/$u/$u.sh; done
c() { local l=$1; shift; RESULT="<unset>"; REPLY="<unset>"; "$@" >"$G8/c.out" 2>/dev/null; local rc=$?; printf '%-38s rc=%s stdout=[%s] RESULT=[%s] REPLY=[%s]\n' "$l" $rc "$(head -c30 $G8/c.out|tr '\n' '~')" "${RESULT:0:30}" "${REPLY:0:20}"; }
G8=$(dirname "$0"); arr=(3 1 2)
c "dateutils.isInLeapYear 2024" dateutils.isInLeapYear 2024
c "math.max 1 2" math.max 1 2
c "TArray.min arr" TArray.min arr
c "TArray.indexOf arr 2" TArray.indexOf arr 2
c "tdirectory.exists /tmp" tdirectory.exists /tmp
c "tfile.exists /etc/passwd" tfile.exists /etc/passwd
c "tpath.combine a b" tpath.combine a b
c "TRegEx.isMatch 'a.' abc" TRegEx.isMatch 'a.' abc
c "TRegEx.match 'a.' abc" TRegEx.match 'a.' abc
c "TRegEx.escape 'a.b'" TRegEx.escape 'a.b'
c "string.toUpper abc" string.toUpper abc
c "string.contains abc b" string.contains abc b
TList.new L; L.Add x >/dev/null
c "L.Add y (func)" L.Add y
c "L.Get 0 (func)" L.Get 0
c "L.IndexOf y" L.IndexOf y
TDictionary.new D; D.Add k v
c "D.GetItem k" D.GetItem k
c "D.ContainsKey k (proc bool)" D.ContainsKey k
c "D.ContainsKey zz" D.ContainsKey zz
c "D.TryGetValue k" D.TryGetValue k
THashSet.new H; H.Add a
c "H.Contains a" H.Contains a
c "H.Extract a" H.Extract a
TQueue.new Q; Q.Enqueue a
c "Q.Peek" Q.Peek
c "Q.Count" Q.Count
TIniFile.new I /tmp/g8_c.ini; I.WriteString s k v
c "I.ReadString s k d" I.ReadString s k d
c "I.ValueExists s k" I.ValueExists s k
TStopwatch.new W; W.Start
c "W.GetElapsedTicks" W.GetElapsedTicks
c "W.GetIsRunning" W.GetIsRunning
TCustomApplication.new A; A.SetArgs --name=bob
c "A.HasOption n name" A.HasOption n name
c "A.GetOptionValue n name" A.GetOptionValue n name
rm -f /tmp/g8_c.ini
echo "=== set -u / set -e compatibility"
