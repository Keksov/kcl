source /c/projects/kkbot/kbool/kcl/tregex/tregex.sh
echo "bash $BASH_VERSION"
for re in '\' 'a\' '\b' 'a\b' '\$' '^\' '\\' 'x\\' '\+' '\*' '(\)'; do
  [[ 'xa\b\c' =~ $re ]] 2>/dev/null; rc=$?; printf 're=%-8s rc=%s m=[%s]\n' "$re" "$rc" "${BASH_REMATCH[0]}"
done
echo "--- escape roundtrip on backslash-terminal / standalone"
for t in '\' 'a\' '\a' '\' 'a\' '\.' '.\'; do
  e=$(TRegEx.escape "$t"); TRegEx.match "x${t}y" "$e"; rc=$?; printf 'text=%-4s esc=%-6s rc=%s m=[%s] %s\n' "$t" "$e" "$rc" "$RESULT" "$([[ $rc == 0 && $RESULT == "$t" ]] && echo OK || echo FAIL)"
done
