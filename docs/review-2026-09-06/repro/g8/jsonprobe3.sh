#!/bin/bash
ms() { local s0=$EPOCHREALTIME; "$@"; local e0=$EPOCHREALTIME; awk -v s=$s0 -v e=$e0 'BEGIN{printf "  %.1f ms\n", (e-s)*1000}'; }
j='{"users":['; for ((i=0;i<300;i++)); do j+="{\"id\":$i,\"name\":\"user $i\",\"tags\":[\"a\",\"b\"],\"ok\":true,\"x\":null},"; done; j="${j%,}]}"
J=$j; for k in 1 2 3 4; do J+="$j"; done
win() { local s; s=$1; local n=${#s} p=0 w cnt=0 i c m; while ((p<n)); do w=${s:p:2048}; m=${#w}; for ((i=0;i<m;i++)); do c=${w:i:1}; case $c in '{'|'}'|'['|']'|','|':') ((cnt++));; esac; done; p=$((p+m)); done; echo -n "windowed(2048) byte-loop tokens=$cnt"; }
plain() { local s; s=$1; local n=${#s} i c cnt=0; for ((i=0;i<n;i++)); do c=${s:i:1}; case $c in '{'|'}'|'['|']'|','|':') ((cnt++));; esac; done; echo -n "plain byte-loop tokens=$cnt"; }
echo "small ${#j}B:"; ms plain "$j"; ms win "$j"
echo "big ${#J}B:"; ms win "$J"
# per-char cost of substring on big string
t() { local s; s=$1; local i c; for ((i=0;i<2000;i++)); do c=${s:50000:1}; done; echo -n "2000x \${s:50000:1} on ${#s}B"; }
ms t "$J"; t2() { local s; s=$1; local i c; for ((i=0;i<2000;i++)); do c=${s:5:1}; done; echo -n "2000x \${s:5:1} on ${#s}B"; }; ms t2 "$J"
