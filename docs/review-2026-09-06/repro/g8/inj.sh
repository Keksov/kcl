#!/bin/bash
KCL=/c/projects/kkbot/kbool/kcl
for u in tlist tstringlist tobjectlist tdictionary thashset tqueuestack tarray tstringhelper dateutils math tinifile; do source $KCL/$u/$u.sh; done
M='/tmp/g8_inj_marker'
t() { rm -f $M; local l=$1; shift; "$@" >/dev/null 2>&1; local rc=$?; printf '%-40s rc=%s injected=%s\n' "$l" $rc "$([[ -e $M ]] && echo YES || echo no)"; }
P='a[$(touch /tmp/g8_inj_marker)]'
TList.new L; L.Add x >/dev/null; L.Add y >/dev/null
t "TList.Get \$P" L.Get "$P"
t "TList.Delete \$P" L.Delete "$P"
t "TList.Insert \$P v" L.Insert "$P" v
t "TList.Exchange \$P 0" L.Exchange "$P" 0
t "TList.Move 0 \$P" L.Move 0 "$P"
t "TList.Put \$P v" L.Put "$P" v
t "TList.Capacity=\$P" L.Capacity= "$P"
t "TList.Count=\$P" L.Count= "$P"
TStringList.new S; S.Add x >/dev/null
t "TStringList.Get \$P" S.Get "$P"
t "TStringList.Insert \$P v" S.Insert "$P" v
arr=(a b c)
t "TArray.indexOf arr x \$P (start)" TArray.indexOf arr x "$P"
t "TArray.copy arr \$P" TArray.copy arr "$P"
t "TArray.sort arr \$P" TArray.sort arr "$P"
t "string.substring abc \$P" string.substring abc "$P"
t "string.substring abc 0 \$P" string.substring abc 0 "$P"
t "string.chars abc \$P" string.chars abc "$P"
t "string.padLeft abc \$P" string.padLeft abc "$P"
t "string.insert abc \$P x" string.insert abc "$P" x
t "string.remove abc \$P" string.remove abc "$P"
t "dateutils.encodeDate \$P 1 1" dateutils.encodeDate "$P" 1 1
t "dateutils.incDay 0 \$P" dateutils.incDay 0 "$P"
t "dateutils.isInLeapYear \$P" dateutils.isInLeapYear "$P"
t "math.max \$P 1" math.max "$P" 1
t "math.sqrt \$P" math.sqrt "$P"
t "math.inRange \$P 0 1" math.inRange "$P" 0 1
t "math.isZero \$P" math.isZero "$P"
t "math.ceil \$P" math.ceil "$P"
t "math.minIntValue \$P" math.minIntValue "$P"
TQueue.new Q; Q.Enqueue a; 
t "TQueue.Create cap \$P" TQueue.new Q2 "$P"
TIniFile.new I /tmp/g8_test.ini; I.WriteString s k "$P"
t "I.ReadInteger s k \$P (default)" I.ReadInteger s k "$P"
t "I.ReadInteger s k 0 (value=\$P)" I.ReadInteger s k 0
t "I.ReadFloat s k 0" I.ReadFloat s k 0
t "I.ReadBool s k \$P" I.ReadBool s k "$P"
rm -f /tmp/g8_test.ini $M
