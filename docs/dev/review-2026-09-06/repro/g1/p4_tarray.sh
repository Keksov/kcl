source /c/projects/kkbot/kbool/kcl/tarray/tarray.sh
echo "--- P4a: undefined comparator name silently falls back to byte order"
a=(10 9 100); TArray.sort a myUndefinedCmp; echo "rc=$? -> ${a[*]} (expected: error, not byte-sorted)"
echo "--- P4b: undefined cmp name in binarySearch treated as start index"
a=(1 3 5); TArray.binarySearch a 3 noSuchFn; echo "rc=$? RESULT=$RESULT CAND=$RESULT_CANDIDATE"
echo "--- P4c: arithmetic injection via start/count"
a=(3 1 2); rm -f ~/kcl_pwned; TArray.sort a 'x[$(touch ~/kcl_pwned)]'; [[ -e ~/kcl_pwned ]] && echo "INJECTION sort start" || echo none; rm -f ~/kcl_pwned
TArray.binarySearch a 1 0 'x[$(touch ~/kcl_pwned)]'; [[ -e ~/kcl_pwned ]] && echo "INJECTION binarySearch count" || echo none; rm -f ~/kcl_pwned
echo "--- P4d: binarySearch range not clamped (start+count > n)"
a=(1 3 5 7); TArray.binarySearch a 9 2 10; echo "rc=$? RESULT=$RESULT CAND=$RESULT_CANDIDATE CMP=$RESULT_COMPARE (imax beyond array)"
echo "--- P4e: reverse into a NEW (undeclared) dst variable — scope?"
unset newdst; src=(1 2 3); f(){ TArray.reverse src newdst; }; f; declare -p newdst 2>&1 | head -1
unset newdst2; TArray.reverse src newdst2; declare -p newdst2 2>&1 | head -1
echo "--- P4f: concat into new dst"
unset cc; TArray.concat cc src src; declare -p cc 2>&1 | head -1
echo "--- P4g: sort -n with '+5' and ' 5'"
a=(+5 3); TArray.sort a -n; echo "rc=$? ${a[*]}"
echo "--- P4h: sort of sparse array (documented undefined) -- what happens"
unset s; s=([0]=b [2]=a [5]=c); TArray.sort s; echo "rc=$? ${!s[*]} -> ${s[*]}"
echo "--- P4i: min/max default arg equal to function name, e.g. default 'f'"
a=(); TArray.min a f; echo "min default 'f' -> RESULT=[$RESULT] (expected f)"
echo "--- P4j: element named like -n"
a=(-n b a); TArray.sort a; echo "${a[*]}"
echo "--- P4k: item equal to '-n' in indexOf"
TArray.indexOf a -n; echo "indexOf -n -> $RESULT"
echo "--- P4l: sort start negative + count"
a=(5 4 3 2 1); TArray.sort a -5 3; echo "${a[*]}"
echo "--- P4m: sort with cmp that returns 3 (out-of-protocol) treated as a<=b"
bad(){ return 3; }; a=(2 1); TArray.sort a bad; echo "${a[*]}"
echo "--- P4n: caller var named __ta_arr"
__ta_arr=(3 1 2); TArray.sort __ta_arr 2>&1 | head -1; echo "rc=$? ${__ta_arr[*]}"
echo "--- P4o: copy with dstidx beyond dn and count 0"
d=(1 2); TArray.copy src d 0 5 0; echo "copy count0 dstidx5 rc=$?"
echo "--- P4p: locale check for str sort"
a=(b B a A); TArray.sort a; echo "${a[*]} (byte: A B a b)"
echo "--- P4q: IFS leak / word split in reverse with element containing spaces & IFS set"
IFS=:; a=("x y" "p:q"); TArray.reverse a a; echo "${a[0]}|${a[1]}"; unset IFS
