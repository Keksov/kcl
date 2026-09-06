#!/bin/bash
# fpjson feasibility probes (rough numbers; run while idle-ish)
KCL=/c/projects/kkbot/kbool/kcl
ms() { local s=$EPOCHREALTIME; "$@"; local e=$EPOCHREALTIME; awk -v s=$s -v e=$e 'BEGIN{printf "%.1f ms", (e-s)*1000}'; }
# build ~20KB json
j='{"users":['; for ((i=0;i<300;i++)); do j+="{\"id\":$i,\"name\":\"user $i\",\"tags\":[\"a\",\"b\"],\"ok\":true,\"x\":null},"; done; j="${j%,}]}"
echo "json bytes=${#j}"
byteloop() { local s=$1 n=${#s} i c cnt=0; for ((i=0;i<n;i++)); do c=${s:i:1}; case $c in '{'|'}'|'['|']'|','|':') ((cnt++));; esac; done; echo -n "tokens=$cnt "; }
echo -n "byte-loop \${s:i:1} over ${#j}B: "; ms byteloop "$j"; echo
regextok() { local s=$1 cnt=0 re='^[[:space:]]*([{}\[\],:]|"([^"\]|\.)*"|-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)'; while [[ -n $s && $s =~ $re ]]; do s=${s:${#BASH_REMATCH[0]}}; ((cnt++)); done; echo -n "tokens=$cnt rest=${#s} "; }
echo -n "regex tokenizer (=~ + substring shift) over ${#j}B: "; ms regextok "$j"; echo
regextok2() { local s=$1 cnt=0 p=0 n=${#s} re='^[[:space:]]*([{}\[\],:]|"([^"\]|\.)*"|-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)'; local chunk; while ((p<n)); do chunk=${s:p:200}; [[ $chunk =~ $re ]] || break; p=$((p+${#BASH_REMATCH[0]})); ((cnt++)); done; echo -n "tokens=$cnt "; }
echo -n "regex tokenizer (200B window, no string copy) over ${#j}B: "; ms regextok2 "$j"; echo
echo -n "awk tokenizer fork+parse of ${#j}B: "; ms bash -c 'printf %s "$1" | awk "BEGIN{RS=\"\"}{n+=gsub(/[{}\[\],:]/,\"\")}END{print \"tokens=\" n}"' _ "$j"; echo
echo -n "jq -c (fork) of ${#j}B: "; command -v jq >/dev/null && ms bash -c 'printf %s "$1" | jq -c . >/dev/null' _ "$j" || echo -n "jq not installed"; echo
# flat-array node store cost: 10k nodes
flat() { local -a T V C; local i; for ((i=0;i<10000;i++)); do T[i]=s; V[i]="v$i"; C[i]=""; done; echo -n "10k nodes in 3 indexed arrays "; }
ms flat; echo
flatA() { local -A T V; local i; for ((i=0;i<10000;i++)); do T[$i]=s; V[$i]="v$i"; done; echo -n "10k nodes in 2 assoc arrays "; }
ms flatA; echo
source $KCL/tdictionary/tdictionary.sh
inst() { local i; for ((i=0;i<200;i++)); do TDictionary.new "n$i"; done; echo -n "200 TDictionary.new "; }
ms inst; echo
call() { local i; for ((i=0;i<2000;i++)); do n1.Add "k$i" v; done; echo -n "2000 n1.Add "; }
ms call; echo
echo -n "u-escape via printf %b on '\u00e9\u4e2d': "; printf '%b' 'é中'; echo "  LANG=[$LANG] LC_CTYPE=[$LC_CTYPE]"
echo -n "under LC_ALL=C.UTF-8: "; LC_ALL=C.UTF-8 bash -c "printf '%b' 'é中\U0001F600'; s=\$(printf 'é'); echo \" len(é)=\${#s}\"" 2>&1
echo "func count now: $(compgen -A function | wc -l)"
