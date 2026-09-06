source /c/projects/kkbot/kbool/kcl/tlist/tlist.sh
echo "--- P1a: items array leak after delete"
TList.new L; L.Add x; L.Add y; L.delete
declare -p L_items 2>&1 | head -1
echo "--- P1b: Add RESULT (FPC returns index of added item => 0 for first Add)"
TList.new L; L.Add first; echo "RESULT after first Add = $RESULT (FPC: 0)"; v=$(L.Add second); echo "\$(Add second) = $v (FPC: 1)"; L.delete
echo "--- P1c: global loop var clobber"
TList.new L; L.Add a; L.Add b; L.Add c
i=777; L.IndexOf c; echo "i after IndexOf = $i (expected 777)"
i=777; L.Delete 0; echo "i after Delete = $i"
i=777; L.Insert 0 z; echo "i after Insert = $i"
L.delete
echo "--- P1d: arithmetic injection via index"
TList.new L; L.Add a
rm -f $HOME/kcl_pwned; L.Get 'x[$(touch ~/kcl_pwned)]'; echo "Get rc=$? RESULT=$RESULT"; [[ -e ~/kcl_pwned ]] && echo "INJECTION: file created by Get index" || echo "no injection"
rm -f ~/kcl_pwned; L.Delete 'x[$(touch ~/kcl_pwned)]' ; [[ -e ~/kcl_pwned ]] && echo "INJECTION via Delete" || echo "no injection Delete"
rm -f ~/kcl_pwned; L.capacity = 'x[$(touch ~/kcl_pwned)]' ; [[ -e ~/kcl_pwned ]] && echo "INJECTION via capacity setter" || echo "no injection capacity"
rm -f ~/kcl_pwned
echo "--- P1e: non-numeric index silently = 0"
L.Get abc; echo "Get abc rc=$? RESULT=$RESULT (expected rc 1)"
L.delete
echo "--- P1f: negative capacity"
TList.new L; L.Add a; L.Add b; L.capacity = -3 2>&1; echo "count=$(L.count) capacity=$(L.capacity)"; declare -p L_items; L.delete
echo "--- P1g: capacity < count truncates silently (FPC: EListError)"
TList.new L; for x in a b c d e; do L.Add $x; done; L.capacity = 2; echo "count=$(L.count) items=${L_items[*]}"; L.delete
echo "--- P1h: count grow then Get padded"
TList.new L; L.count = 3; L.Get 2; echo "rc=$? RESULT=[$RESULT] count=$(L.count) cap=$(L.capacity)"; L.delete
echo "--- P1i: Insert error leaves RESULT?"
TList.new L; RESULT=keep; L.Insert 5 x; echo "rc=$? RESULT=[$RESULT]"; L.delete
echo "--- P1j: Assign on TList clears then fails"
TList.new L; L.Add a; TList.new M; L.Assign M; echo "rc=$? count after failed Assign=$(L.count) (data lost?)"; L.delete; M.delete
echo "--- P1k: Move/Exchange with count untouched but index string"
TList.new L; L.Add a; L.Add b; L.Move 1 0; echo "${L_items[*]}"; L.delete
echo "--- P1l: leading-dash item Add / IndexOf / Remove"
TList.new L; L.Add "-n"; L.Add "-e"; L.IndexOf "-e"; echo "idx(-e)=$RESULT"; L.Remove "-n"; echo "rm=$RESULT count=$(L.count) first=$(L.First)"; L.delete
echo "--- P1m: BatchDelete count non-numeric / negative"
TList.new L; for x in a b c; do L.Add $x; done; L.BatchDelete 0 -1; echo "rc=$? RESULT=$RESULT count=$(L.count)"; L.delete
echo "--- P1n: set -u compatibility"
( set -u; TList.new U; U.Add a; U.IndexOf zz; echo "set -u ok RESULT=$RESULT"; U.delete ) 2>&1 | tail -2
