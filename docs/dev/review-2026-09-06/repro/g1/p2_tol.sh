source /c/projects/kkbot/kbool/kcl/tobjectlist/tobjectlist.sh
alive() { declare -F "$1.delete" >/dev/null 2>&1 && echo alive || echo freed; }
echo "--- P2a: items array leak after owning delete"
TList.new o1; TObjectList.new L; L.Add o1; L.delete; declare -p L_items 2>&1 | head -1
echo "--- P2b: count shrink does not free (FPC SetCount -> Delete -> Notify)"
TList.new o2; TList.new o3; TObjectList.new L; L.Add o2; L.Add o3; L.count = 1; echo "o3: $(alive o3) (FPC: freed); count=$(L.count)"; L.delete; declare -F o3.delete >/dev/null && o3.delete
echo "--- P2c: capacity shrink below count drops without free"
TList.new o4; TList.new o5; TObjectList.new L; L.Add o4; L.Add o5; L.capacity = 1; echo "o5: $(alive o5) count=$(L.count)"; L.delete; declare -F o5.delete >/dev/null && o5.delete
echo "--- P2d: Assign (stub) on owning list frees everything then fails"
TList.new o6; TObjectList.new L; L.Add o6; TList.new src; L.Assign src; echo "rc=$? o6: $(alive o6) count=$(L.count)"; L.delete; src.delete
echo "--- P2e: Exchange/Move keep alive (expected), Sort ok"
TList.new o7; TList.new o8; TObjectList.new L; L.Add o7; L.Add o8; L.Exchange 0 1; L.Move 0 1; L.Sort; echo "$(alive o7) $(alive o8)"; L.delete
echo "--- P2f: Extract of duplicate handle removes first only"
TList.new o9; TObjectList.new L; L.Add o9; L.Add o9; L.Extract o9; echo "rc=$? RESULT=$RESULT count=$(L.count) $(alive o9)"; L.delete
echo "--- P2g: Remove double IndexOf -> count dispatches (perf) ; Remove when owns + item absent"
TObjectList.new L; L.Remove nothere; echo "RESULT=$RESULT rc=$?"; L.delete
echo "--- P2h: Delete index injection"
TObjectList.new L; L.Add zz; rm -f ~/kcl_pwned; L.Delete 'x[$(touch ~/kcl_pwned)]'; [[ -e ~/kcl_pwned ]] && echo INJECTION || echo none; rm -f ~/kcl_pwned; L.delete
echo "--- P2i: element handle whose destructor touches list (re-entrancy) — skip"
echo "--- P2j: FindInstanceOf startAt non-numeric / exact token 'no'"
TList.new o10; TObjectList.new L false; L.Add o10; L.FindInstanceOf TList no; echo "exact='no' -> $RESULT (treated as exact=true)"; L.FindInstanceOf TList true abc; echo "startAt=abc -> $RESULT"; L.delete; o10.delete
echo "--- P2k: Put where new item == old but old is dead handle"
TList.new o11; TObjectList.new L; L.Add o11; o11.delete; L.Put 0 other; echo "rc=$? ${L_items[*]}"; L.delete
echo "--- P2l: owns_objects set to garbage"
TList.new o12; TObjectList.new L; L.Add o12; L.owns_objects = "yes"; L.delete; echo "o12 after owns=yes delete: $(alive o12) (FPC bool; here anything != 'true' = non-owning)"; declare -F o12.delete >/dev/null && o12.delete
