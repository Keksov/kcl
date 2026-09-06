#!/bin/bash
ms() { local s0=$EPOCHREALTIME; "$@"; local e0=$EPOCHREALTIME; awk -v s=$s0 -v e=$e0 'BEGIN{printf "  %.1f ms\n", (e-s)*1000}'; }
j='{"users":['; for ((i=0;i<300;i++)); do j+="{\"id\":$i,\"name\":\"user $i\",\"tags\":[\"a\",\"b\"],\"ok\":true,\"x\":null},"; done; j="${j%,}]}"
J=$j; for k in 1 2 3 4; do J+="$j"; done   # ~96KB
echo "small=${#j}B big=${#J}B"
byteloop() { local s; s=$1; local n=${#s} i c cnt=0; for ((i=0;i<n;i++)); do c=${s:i:1}; case $c in '{'|'}'|'['|']'|','|':') ((cnt++));; esac; done; echo -n "byte-loop tokens=$cnt"; }
RE='^[[:space:]]*([][{},:]|"([^"\]|\.)*"|-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)'
regextok() { local s; s=$1; local cnt=0 n=${#s} p=0 chunk; while ((p<n)); do chunk=${s:p:300}; [[ $chunk =~ $RE ]] || { echo -n "STOP at $p"; break; }; p=$((p+${#BASH_REMATCH[0]})); ((cnt++)); done; echo -n "regex-window tokens=$cnt"; }
for sz in small big; do [[ $sz == small ]] && s=$j || s=$J; echo "--- $sz (${#s}B)"; ms byteloop "$s"; ms regextok "$s"; echo -n "  awk fork tokenize"; ms bash -c 'printf %s "$1" | awk "{n+=gsub(/[][{},:]/,\"\")}END{printf \" tokens=%d\", n}"' _ "$s"; done
echo "--- 5.3 same:"; 
