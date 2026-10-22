source /c/projects/kkbot/kbool/kcl/tdictionary/tdictionary.sh
echo "bash $BASH_VERSION"
echo "--- exotic keys through every mutating path"
TDictionary.new D
bad=0
for k in '' ']' '[' '*' '@' "it's" 'a"b' 'back\slash' '$(echo INJ >&2)' '`echo BT >&2`' '$HOME' 'a b' $'n\nl' 'k' 'kk'; do
  D.Add "$k" "v1" || { echo "Add fail ${k@Q}"; bad=1; }
  D.AddOrSetValue "$k" "v2"
  D.SetItem "$k" "v3"
  D.GetItem "$k"; [[ "$RESULT" == v3 ]] || { echo "GetItem ${k@Q} -> $RESULT"; bad=1; }
  D.TryGetValue "$k" || { echo "TryGet miss ${k@Q}"; bad=1; }
  D.ExtractPair "$k"; [[ "$RESULT" == v3 && "$RESULT_KEY" == "$k" ]] || { echo "Extract ${k@Q} -> ${RESULT@Q} key=${RESULT_KEY@Q}"; bad=1; }
  D.ContainsKey "$k" && { echo "still present ${k@Q}"; bad=1; }
  D.Add "$k" "v4"; D.Remove "$k"; D.ContainsKey "$k" && { echo "Remove failed ${k@Q}"; bad=1; }
  D.Add "$k" "v5"
done
D.Count >/dev/null 2>&1; D.count; echo "count=$RESULT (expect 15) bad=$bad"
echo "--- Clear with hooks over exotic keys"
LOG=(); kcb() { LOG+=("$2"); }
D.onKeyNotify = kcb
D.Clear; echo "clear events=${#LOG[@]} count=$(d=0; D.count; echo $RESULT)"
D.onKeyNotify = ""
echo "--- Assign with hooks over exotic keys + Assign from THashSet instance"
TDictionary.new S2; S2.Add ']' x; S2.Add '$(echo INJ3 >&2)' y
D.Assign S2; D.count; echo "assign count=$RESULT"; D.GetItem ']'; echo "val=$RESULT"
source /c/projects/kkbot/kbool/kcl/thashset/thashset.sh
THashSet.new HS; HS.Add q
D.Assign HS; echo "Assign(THashSet) rc=$? (accepted? values:)"; D.Values
HS.delete; S2.delete
echo "--- ForEach over exotic keys"
D.Clear; D.AddPairs ']' a '$(echo INJ4 >&2)' b '' c
cb() { printf '  [%s]=[%s]\n' "$1" "$2"; }; D.ForEach cb
echo "--- Keys/Values echo forms with leading -n / -e values"
D.Clear; D.Add -n -e; D.Keys; D.Values
echo "--- kk._return of leading-dash value via \$()"
x="$(D.GetItem -n)"; echo "captured=${x@Q}"
echo "--- ctor bad token state"
TObjectDictionary.new BD doOwnsNothing 2>&1; echo "new rc=$?"; declare -p BD_items 2>&1 | head -1; echo "notifyHook='$(BD._notifyHook)' ownsK='$(BD._ownsKeys)'"; BD.delete; declare -p BD_items 2>&1 | head -1
echo "--- TObjectDictionary self-overwrite frees the live value (FPC parity check)"
TObjectDictionary.new OD doOwnsValues; TDictionary.new V
OD.Add k V; OD.AddOrSetValue k V
declare -F V.delete >/dev/null && echo "V alive" || echo "V FREED by self-overwrite (dict now holds a dead handle)"
OD.GetItem k; echo "stored=$RESULT"; OD.delete
echo "--- Assign into owning dict: double ownership"
TObjectDictionary.new O1 doOwnsValues; TObjectDictionary.new O2 doOwnsValues; TDictionary.new W
O1.Add k W; O2.Assign O1; O1.delete
declare -F W.delete >/dev/null && echo "W alive after O1 delete" || echo "W freed by O1 delete; O2 holds dead handle"
O2.delete
echo "--- set -e smoke"
( set -e; TDictionary.new E; E.Add a 1; E.TryAdd a 2 || true; E.GetItem a; E.Remove zz; E.Clear; E.delete; echo "set -e ok" )
echo "--- leftover globals"
declare -p RESULT_KEY 2>&1 | head -1
D.delete
