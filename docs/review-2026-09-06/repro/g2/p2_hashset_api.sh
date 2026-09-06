source /c/projects/kkbot/kbool/kcl/thashset/thashset.sh
echo "bash $BASH_VERSION"
THashSet.new H
for e in ']' "it's" 'a"b' 'back\slash' '$HOME' '[x' '$(echo INJECTED-BY-REMOVE >&2)'; do
  H.Add "$e"
  H.Remove "$e"; rc=$?
  H.Contains "$e"; c=$?
  H.Count; n=$RESULT
  printf 'Remove %-40s rc=%d contains-after=%d count=%d\n' "${e@Q}" "$rc" "$c" "$n"
  H.Clear
done
echo "--- Extract"
for e in ']' '$(echo INJECTED-BY-EXTRACT >&2)'; do
  H.Add "$e"
  H.Extract "$e"; r="$RESULT"
  H.Contains "$e"; c=$?
  printf 'Extract %-40s RESULT=%s contains-after=%d\n' "${e@Q}" "${r@Q}" "$c"
  H.Clear
done
echo "--- injection proof: file creation"
rm -f "$1/pwned.txt"
H.Add "\$(touch $1/pwned.txt)"
H.Remove "\$(touch $1/pwned.txt)"
[[ -f "$1/pwned.txt" ]] && echo "INJECTION: pwned.txt created" || echo "no file"
H.delete
echo "--- ForEach with missing cb"
THashSet.new F; F.Add a; F.Add b
F.ForEach no_such_cb; echo "rc=$?"
F.ForEach ""; echo "rc=$?"
F.delete
echo "--- Assign from a non-set with _items (TQueue)"
source /c/projects/kkbot/kbool/kcl/tqueuestack/tqueuestack.sh
TQueue.new Q; Q.Enqueue alpha; Q.Enqueue beta
THashSet.new A; A.Add keep
A.Assign Q; echo "Assign(Q) rc=$?"
A.Count; echo "count=$RESULT"
declare -p A_items
A.Contains 0; echo "Contains 0 rc=$?"
A.Contains ""; echo "Contains '' rc=$?"
O=(); A.ToArray O; declare -p O
A.delete; Q.delete
echo "--- Destroy does not Clear (P3 pending) - events on delete"
THashSet.new D; D.Add x
D.on_notify = rec; rec() { echo "EV $2 $3"; }
D.delete
echo "(no EV lines expected until P3)"
