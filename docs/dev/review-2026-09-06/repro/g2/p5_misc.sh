source /c/projects/kkbot/kbool/kcl/tdictionary/tdictionary.sh
source /c/projects/kkbot/kbool/kcl/tqueuestack/tqueuestack.sh
source /c/projects/kkbot/kbool/kcl/thashset/thashset.sh
echo "--- direct func call prints? (docs claim 'echo AND RESULT')"
TDictionary.new D; D.Add a val
out=$(D.GetItem a 2>&1 | cat); echo "piped(subshell)=[$out]"
exec 3>$S/direct.out; D.GetItem a >&3; exec 3>&-; echo "direct stdout bytes=$(wc -c < $S/direct.out) RESULT=$RESULT"
echo "--- echo -n option-eating in \$() (kk._return) via queue"
TQueue.new Q; Q.Enqueue "-e"; Q.Enqueue "-n"; Q.Enqueue "-E"
for i in 1 2 3; do v="$(Q.Peek)"; Q.Dequeue; echo "captured=[$v] direct=[$RESULT]"; done
Q.delete
echo "--- TStack.ToArray with reserved name corrupts storage"
TStack.new ST; ST.Push a; ST.Push b
ST.ToArray __tqs_it; ST.Count; echo "count after ToArray __tqs_it = $RESULT (expect 2)"
ST.delete
echo "--- THashSet self-assign"
THashSet.new H; H.Add x; H.Add y; H.Assign H; H.Count; echo "self-assign count=$RESULT"; H.delete
echo "--- THashSet Assign from TDictionary (values ignored, keys copied) "
THashSet.new H2; D.Add b 2; H2.Assign D; echo "rc=$?"; H2.Count; echo "count=$RESULT"; H2.Contains a; echo "contains a rc=$?"; H2.delete
D.delete
echo "--- unused sources in tdictionary: does kklass already source klib?"
grep -n "source.*klib\|source.*kerr" /c/projects/kkbot/kbool/kklass/kklass.sh /c/projects/kkbot/kbool/kklass/kklass_pascal.sh | head
