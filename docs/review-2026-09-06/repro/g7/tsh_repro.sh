#!/bin/bash
source /c/projects/kkbot/kbool/kcl/tstringhelper/tstringhelper.sh
echo "locale: $(locale 2>/dev/null | grep LC_CTYPE)"
echo "--- S1 arithmetic injection via numeric params (marker file created = RCE)"
M=$PWD/.inj_marker_$$; rm -f "$M"
INJ='a[$(touch '"$M"')]'
chk() { if [[ -e $M ]]; then echo "$1: RCE (marker created)"; else echo "$1: safe"; fi; rm -f "$M"; }
r=$(string.substring "hello" "$INJ" 2>&1); chk substring
r=$(string.remove "hello" "$INJ" 2>&1); chk remove
r=$(string.insert "hello" "$INJ" x 2>&1); chk insert
r=$(string.chars "hello" "$INJ" 2>&1); chk chars
r=$(string.padLeft "hi" "$INJ" 2>&1); chk padLeft
r=$(string.indexOf "hello" "l" "$INJ" 2>&1); chk "indexOf startIndex"
r=$(string.create "x" "$INJ" 2>&1); chk "create count"
r=$(string.isDelimiter "hello" "$INJ" "l" 2>&1); chk isDelimiter
r=$(string.lastIndexOf "hello" "l" "$INJ" 2>&1); chk "lastIndexOf startIndex"
r=$(string.toCharArray "hello" "$INJ" 2>&1); chk "toCharArray (validated)"
echo "--- S2 substring edge args"
echo "substring hello -3      -> [$(string.substring hello -3)]   (FPC: 'hello', Copy clamps start)"
echo "substring hello 1 -1    -> [$(string.substring hello 1 -1)] (FPC: '')"
echo "substring hello ''      -> [$(string.substring hello '' 2>&1)]"
echo "substring hello 2 ''    -> [$(string.substring hello 2 '')]"
echo "remove hello ''         -> [$(string.remove hello '' 2>&1)]"
echo "insert hello '' X       -> [$(string.insert hello '' X 2>&1)]"
echo "--- S3 split output"
echo "split 'a,b,c' ','       -> [$(string.split 'a,b,c' ',')]"
echo "split 'a b,c' ','       -> [$(string.split 'a b,c' ',')]"
echo "split 'a,b,' ','        -> [$(string.split 'a,b,' ',')]"
echo "split 'a,b<NL>c,d' ','  -> [$(string.split $'a,b\nc,d' ',')]  (expect c,d preserved)"
echo "split 'a, b' ', '       -> [$(string.split 'a, b' ', ')]  (sep chars each)"
echo "split 'a,b,c,d' ',' 2   -> [$(string.split 'a,b,c,d' ',' 2)]"
echo "split ' a , b ' ' '     -> [$(string.split ' a , b ' ' ')]"
echo "--- S4 empty char-set semantics"
echo "trimStart abc ''        -> [$(string.trimStart abc '')]  (FPC: abc)"
echo "trimEnd abc ''          -> [$(string.trimEnd abc '')]  (FPC: abc)"
echo "isDelimiter abc 1 ''    -> [$(string.isDelimiter abc 1 '')]  (FPC: false)"
echo "indexOfAny abc ''       -> [$(string.indexOfAny abc '')]  (FPC: -1)"
echo "lastIndexOfAny abc ''   -> [$(string.lastIndexOfAny abc '')]  (FPC: -1)"
echo "lastDelimiter abc ''    -> [$(string.lastDelimiter abc '')]  (FPC: -1)"
echo "indexOfAnyUnquoted abc '' '\"' '\"' -> [$(string.indexOfAnyUnquoted abc '' '"' '"')]"
echo "--- S5 replace default flags"
echo "replace 'a-b-c' '-' '+' -> [$(string.replace 'a-b-c' '-' '+')]  (FPC Replace(Old,New) = rfReplaceAll -> a+b+c)"
echo "--- S6 quoting"
echo "quotedString 'say \"hi\"' '\"' -> [$(string.quotedString 'say "hi"' '"')]  (FPC: \"say \"\"hi\"\"\")"
echo "deQuotedString \"'it''s'\"    -> [$(string.deQuotedString "'it''s'")]  (FPC default quote ' -> it's)"
echo "deQuotedString 'a\"b\"c'      -> [$(string.deQuotedString 'a"b"c')]  (FPC: unchanged, not quoted)"
printf 'quotedString multi-line: [%q]  (input a NL NL)\n' "$(string.quotedString $'a\n\n')"
echo "--- S7 toBoolean"
for v in True TRUE -1 2 0 yes; do printf '%s -> %s; ' "$v" "$(string.toBoolean "$v")"; done; echo "  (FPC TryStrToBool: True/TRUE/-1/2 -> true, 0 -> false)"
echo "--- S8 lastIndexOf startIndex/count"
echo "lastIndexOf hello lo 4      -> [$(string.lastIndexOf hello lo 4)]  (FPC: 3, match may start at StartIndex)"
echo "lastIndexOf hello l 3       -> [$(string.lastIndexOf hello l 3)]   (FPC: 3)"
echo "lastIndexOf hello l 4 5     -> [$(string.lastIndexOf hello l 4 5)] (FPC: 3)"
echo "lastIndexOfAny hello lo 3   -> [$(string.lastIndexOfAny hello lo 3)] (FPC: 3)"
echo "--- S9 global var leaks (direct call, no subshell)"
i=99; arg=keep; string.padLeft x 3 >/dev/null; echo "after padLeft: i=$i (expect 99)"
i=99; string.create x 2 >/dev/null; echo "after create: i=$i"
string.join , a b >/dev/null; echo "after join: arg=$arg (expect keep)"
echo "--- S10 indexOf empty / FPC"
echo "indexOf hello '' 2 -> [$(string.indexOf hello '' 2)]  (FPC Pos('')=0 -> -1; Delphi: 2)"
echo "--- S11 trim control chars"
printf 'trim <x01>hi<x02> -> [%q]  (FPC Trim: chars<=#32 removed -> hi)\n' "$(string.trim $'\x01hi\x02')"
echo "--- S12 case conversion non-ASCII under current locale"
echo "toUpper café -> [$(string.toUpper 'café')] ; toLower ÄÖ -> [$(string.toLower 'ÄÖ')] ; length 日本 -> $(string.length '日本')"
echo "LC_ALL=C: toUpper café -> [$(LC_ALL=C string.toUpper 'café')] ; length 日本 -> $(LC_ALL=C string.length '日本')"
echo "--- S13 toInteger"
for v in "08" "+5" " 5" "1_000" "3.9" "0x10" "\$10" "5 "; do o=$(string.toInteger "$v"); printf '[%s]->%s(rc=%s) ' "$v" "$o" "$?"; done; echo
echo "--- S14 format"
echo "format '%d' abc -> [$(string.format '%d' abc 2>&1)]"
echo "format '%5.2f' -> [$(string.format '%5.2f' 3.14159)]"
echo "--- S15 replace perf (10KB string, 1 replacement at end)"
big=$(printf 'a%.0s' {1..10000})X
t0=$EPOCHREALTIME; r=$(string.replace "$big" "X" "Y"); t1=$EPOCHREALTIME; echo "replace 10KB: $(awk "BEGIN{print ($t1-$t0)*1000}") ms"
t0=$EPOCHREALTIME; r=$(string.replace "$big" "X" "Y" rfReplaceAll); t1=$EPOCHREALTIME; echo "replace 10KB all: $(awk "BEGIN{print ($t1-$t0)*1000}") ms"
t0=$EPOCHREALTIME; r=$(string.indexOf "$big" "X"); t1=$EPOCHREALTIME; echo "indexOf 10KB: $(awk "BEGIN{print ($t1-$t0)*1000}") ms (result $r)"
t0=$EPOCHREALTIME; r=$(string.countChar "$big" "a"); t1=$EPOCHREALTIME; echo "countChar 10KB: $(awk "BEGIN{print ($t1-$t0)*1000}") ms"
t0=$EPOCHREALTIME; r="${big//X/Y}"; t1=$EPOCHREALTIME; echo "builtin \${//} 10KB: $(awk "BEGIN{print ($t1-$t0)*1000}") ms"
echo "--- S16 chars negative"
echo "chars hello -1 -> [$(string.chars hello -1)]"
echo "--- S17 glob chars"
echo "contains 'a*b' '*' -> $(string.contains 'a*b' '*'); startsWith '[x]' '[' -> $(string.startsWith '[x]' '['); endsWith 'a?' '?' -> $(string.endsWith 'a?' '?'); equals 'a' '?' -> $(string.equals a '?')"
echo "--- S18 static-method REPLY/RESULT contract"
string.length abc; echo "direct call printed above; RESULT=[$RESULT] REPLY=[$REPLY]"
echo "--- S19 copyTo nameref collision"
declare -a self; string.copyTo hello 0 self 0 2 2>&1; echo "copyTo dest named 'self': rc=$? self=[${self[*]}]"
declare -a dest; string.copyTo hello 0 dest 0 2; echo "copyTo dest: [${dest[*]}]"
echo "--- S20 toDouble/parse"
echo "toDouble '3.14abc' -> [$(string.toDouble '3.14abc')]; toDouble 'abc' -> [$(string.toDouble abc)]"
echo "--- S21 padLeft width negative"
echo "padLeft x -5 -> [$(string.padLeft x -5)]"
echo "--- S22 getHashCode locale-dependent"
echo "hash 'aé' -> $(string.getHashCode 'aé'); C: $(LC_ALL=C string.getHashCode 'aé')"
echo "--- S23 echo -n/-e data"
echo "copy '-n' -> [$(string.copy -n)]; toUpper '-e' -> [$(string.toUpper -e)]; trim '-n' -> [$(string.trim ' -n ')]"

# ---------------------------------------------------------------------------
# P5 (2026-09-07): the API of `split` changed while closing TSH-03 — it now
# fills a caller array by nameref and returns the count in RESULT, so the S3
# block above (which uses the pre-P5 signature) prints nothing and answers
# rc 2. The section below is the same evidence in the new shape; the original
# lines are left untouched on purpose.
# ---------------------------------------------------------------------------
echo "--- S3b split output (P5 API: split STR SEP ARRAY [COUNT] [OPTIONS])"
show() { local -a a=(); string.split "$1" "$2" a "${3:-0}" "${4:-None}"; printf "%-28s -> %s parts:" "split '$1' '$2'" "$RESULT"; local e; for e in "${a[@]}"; do printf " [%s]" "$e"; done; echo; }
show 'a,b,c' ','
show 'a b,c' ','
show 'a,b,' ','
show $'a,b\nc,d' ','
show 'a, b' ', '
show 'a,b,c,d' ',' 2
show 'a,,c' ',' 0 ExcludeEmpty
show 'a,b,' ',' 0 ExcludeLastEmpty
echo "--- S24 (P5) direct calls are silent and answer in RESULT"
out=$(string.trim '  hi  ' ; printf '|%s' "$RESULT")
echo "trim direct: printed+RESULT = [$out]  (inside \$( ) the member prints the value once AND sets RESULT, so [hi|hi])"
string.length abc; echo "length direct: RESULT=[$RESULT] (nothing printed above)"
echo "--- S25 (P5) booleans answer with rc"
if string.contains abc b; then echo "contains abc b: rc 0, RESULT=$RESULT"; fi
string.contains abc z || echo "contains abc z: rc 1, RESULT=$RESULT"
