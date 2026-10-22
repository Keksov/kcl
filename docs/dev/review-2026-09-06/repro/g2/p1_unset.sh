# Probe: double-quoted unset "arr[$pk]" vs single-quoted unset 'arr[$pk]' on assoc arrays
echo "bash $BASH_VERSION"
declare -A a
for k in 'k$(echo INJ >&2; echo INJ)' 'k]' 'k*' 'k@' "k'" 'k"' 'k\' 'ka b' $'k\nx' 'k$HOME' 'k!' 'k[' 'k`echo BT >&2`'; do
  a=(); a["$k"]=1; a[kother]=1
  pk="$k"
  unset "a[$pk]"
  if [[ -n ${a["$k"]+x} ]]; then echo "DQ FAIL  key=${k@Q} still present (count=${#a[@]})"; else echo "DQ ok    key=${k@Q} (count=${#a[@]})"; fi
  a=(); a["$k"]=1; a[kother]=1
  unset 'a[$pk]'
  if [[ -n ${a["$k"]+x} ]]; then echo "SQ FAIL  key=${k@Q} still present (count=${#a[@]})"; else echo "SQ ok    key=${k@Q} (count=${#a[@]})"; fi
done
echo "--- nameref assignment/read double-expansion"
declare -A b; declare -n r=b
for k in 'k$(echo INJ2 >&2; echo INJ2)' 'k]' 'k*' 'k@' "k'" 'k"' 'k\' 'k$HOME' 'k`echo BT2 >&2`'; do
  b=()
  r[$k]=1
  got="${!b[*]}"
  [[ "$got" == "$k" ]] && echo "NR-assign ok ${k@Q}" || echo "NR-assign FAIL ${k@Q} -> stored ${got@Q}"
  b=(); b["$k"]=v
  v="${r[$k]}"
  [[ "$v" == v ]] && echo "NR-read ok ${k@Q}" || echo "NR-read FAIL ${k@Q} -> ${v@Q}"
  [[ -n ${r["$k"]+x} ]] && echo "NR-exist ok" || echo "NR-exist FAIL ${k@Q}"
done
