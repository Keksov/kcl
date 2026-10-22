source /c/projects/kkbot/kbool/kcl/tregex/tregex.sh
echo "bash $BASH_VERSION"
re='\'; [[ 'xx\yy' =~ $re ]]; echo "raw \\ rc=$? m=[${BASH_REMATCH[0]}]"
re='[\]'; [[ 'xx\yy' =~ $re ]]; echo "raw [\] rc=$? m=[${BASH_REMATCH[0]}]"
TRegEx.match 'xx\yy' '\'; echo "TRegEx \\ rc=$? idx=$RESULT_INDEX m=[$RESULT]"
TRegEx.match 'xx\yy' '[\]'; echo "TRegEx [\] rc=$? idx=$RESULT_INDEX m=[$RESULT]"
e=$(TRegEx.escape 'a\b'); echo "escape a\b -> [$e]"; TRegEx.match 'xa\by' "$e"; echo "  match rc=$? m=[$RESULT] idx=$RESULT_INDEX"
for n in 1000 2000 4000 8000; do s=$(printf 'x%.0s' $(seq $n)); t0=$EPOCHREALTIME; TRegEx.escape "$s" >/dev/null; t1=$EPOCHREALTIME; echo "escape $n: $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.3f", b-a}')s"; done
s=$(printf 'ab,%.0s' $(seq 4000)); t0=$EPOCHREALTIME; TRegEx.replace "$s" "," ";" >/dev/null; t1=$EPOCHREALTIME; echo "replace 4000 matches: $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.3f", b-a}')s"
echo "--- 5.3-relevant: nocasematch restore, invalid pattern stderr, failed match clears BASH_REMATCH"
shopt -s nocasematch; TRegEx.isMatch a A i; shopt -q nocasematch && echo "restored on" || echo "LEAK off"; shopt -u nocasematch
TRegEx.isMatch "a" "(" ; echo "invalid rc=$?"
TRegEx.match "abc" "b"; TRegEx.isMatch "abc" "z"; echo "RESULT after later no-match=[$RESULT] groups=${#RESULT_GROUPS[@]}"
