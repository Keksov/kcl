echo "bash $BASH_VERSION LANG=$LANG LC_ALL=$LC_ALL"
printf 'u00e9=[%b] ' 'é'; printf 'U0001F600=[%b] ' '\U0001F600'; printf 'lone-surrogate uD83D=[%b] rc=%s\n' '\uD83D' $?
s=$(printf 'é'); echo "len(e-acute) default=${#s}"; ( LC_ALL=C; echo "len under LC_ALL=C subshell=${#s}"; t=$(printf 'é'); echo "printf \u under C=[$t] len=${#t}" ); 
f() { local LC_ALL=C; echo "local LC_ALL=C in func: len=${#s} byte0=${s:0:1}"; }; f; echo "after func LC_ALL=[$LC_ALL] len=${#s}"
x='"aAb"'; [[ $x =~ \u([0-9A-Fa-f]{4}) ]] && printf 'regex \u hex=%s -> %b\n' "${BASH_REMATCH[1]}" "\u${BASH_REMATCH[1]}"
# NUL
n=$'a\x00b'; echo "NUL len=${#n}"
