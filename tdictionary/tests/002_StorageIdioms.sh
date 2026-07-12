#!/bin/bash
# 002_StorageIdioms.sh - P0.2 gate: the prefixed-assoc storage design and its
# pinned idioms must be safe for ARBITRARY bash-string keys on this bash.
#
# Idioms under test (exactly what tdictionary.sh methods use):
#   store:   ref["k$key"]=$value
#   exists:  [[ -n ${ref["k$key"]+x} ]]
#   fetch:   ${ref["k$key"]}
#   delete:  pk="k$key"; unset 'ref[$pk]'   (single-quoted, expanded once;
#            prefix guarantees pk is never empty/@/*)
#   iterate: for k in "${!ref[@]}"; do key=${k#k}; ...
#
# Why the prefix: bash 5.2 rejects the empty subscript (a['']=x -> "bad array
# subscript") while '' IS a valid FPC key.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: Storage idioms torture (prefixed assoc array)"

# The torture key set: empty, bracket/braces/glob chars, quotes, whitespace
# (incl. newline and tab), expansion-looking strings, prefix-collision
# candidates ('' vs 'k' vs 'kk'), unicode.
keys=(
    ''
    ']' '[' 'a]b[c' '}' '{' '(' ')'
    '*' '?' '[a-z]' '!' '@' '#' '~' '-' '=' '+' ';' '&' '|'
    'a b' $'a\nb' $'a\tb'
    '"dq"' "'sq'" 'back\slash'
    '$(echo pwned)' '`echo pwned`' '$HOME' '${PATH}'
    'k' 'kk'
    'ключ-юникод'
)

declare -A store

kt_test_start "store all ${#keys[@]} torture keys"
for key in "${keys[@]}"; do
    store["k$key"]="val:[$key]"
done
if [[ ${#store[@]} -eq ${#keys[@]} ]]; then
    kt_test_pass "${#store[@]} entries stored, no collisions"
else
    kt_test_fail "stored ${#store[@]} entries, expected ${#keys[@]}"
fi

kt_test_start "exists + fetch every key byte-exact"
bad=""
for key in "${keys[@]}"; do
    if [[ -z ${store["k$key"]+x} ]]; then
        bad="exists-miss for key <$key>"
        break
    fi
    if [[ "${store["k$key"]}" != "val:[$key]" ]]; then
        bad="fetch mismatch for key <$key>: got <${store["k$key"]}>"
        break
    fi
done
if [[ -z "$bad" ]]; then
    kt_test_pass "all keys retrieved byte-exact"
else
    kt_test_fail "$bad"
fi

kt_test_start "prefix-collision guard: '', 'k', 'kk' stay distinct"
if [[ "${store[k]}" == "val:[]" && "${store[kk]}" == "val:[k]" && "${store[kkk]}" == "val:[kk]" ]]; then
    kt_test_pass "'' -> [k], 'k' -> [kk], 'kk' -> [kkk] all distinct"
else
    kt_test_fail "collision: [k]=<${store[k]}> [kk]=<${store[kk]}> [kkk]=<${store[kkk]}>"
fi

kt_test_start "negative exists for absent keys"
if [[ -z ${store["kmissing"]+x} && -z ${store["kkey with space"]+x} ]]; then
    kt_test_pass "absent keys report not-set"
else
    kt_test_fail "phantom entry reported as existing"
fi

kt_test_start "empty VALUE is distinguishable from missing key"
store["kempty-val"]=""
if [[ -n ${store["kempty-val"]+x} && -z "${store["kempty-val"]}" ]]; then
    kt_test_pass "empty value: exists=yes, fetch=''"
else
    kt_test_fail "empty value handling broken"
fi
pk="kempty-val"; unset 'store[$pk]'

kt_test_start "iteration round-trip: prefix strip recovers the exact key set"
declare -A seen
for k in "${!store[@]}"; do
    seen["x${k#k}"]=1
done
bad=""
for key in "${keys[@]}"; do
    [[ -n ${seen["x$key"]+x} ]] || { bad="key <$key> lost in iteration"; break; }
done
if [[ -z "$bad" && ${#seen[@]} -eq ${#keys[@]} ]]; then
    kt_test_pass "all ${#keys[@]} keys recovered via \${k#k}"
else
    kt_test_fail "${bad:-count mismatch: ${#seen[@]} vs ${#keys[@]}}"
fi

kt_test_start "delete every key via unset 'ref[\$pk]' (count returns to 0)"
for key in "${keys[@]}"; do
    pk="k$key"
    unset 'store[$pk]'
done
if [[ ${#store[@]} -eq 0 ]]; then
    kt_test_pass "all entries deleted, store empty"
else
    kt_test_fail "${#store[@]} entries survived deletion: $(printf '<%q> ' "${!store[@]}")"
fi

kt_test_start "full cycle through a NAMEREF (the class access path)"
declare -A store2
declare -n ref=store2
ok=1
for key in "${keys[@]}"; do
    ref["k$key"]="v($key)"
done
[[ ${#store2[@]} -eq ${#keys[@]} ]] || ok=0
for key in "${keys[@]}"; do
    [[ "${ref["k$key"]}" == "v($key)" ]] || { ok=0; break; }
done
for key in "${keys[@]}"; do
    pk="k$key"
    unset 'ref[$pk]'
done
[[ ${#store2[@]} -eq 0 ]] || ok=0
unset -n ref
if [[ $ok -eq 1 ]]; then
    kt_test_pass "nameref store/fetch/delete cycle clean"
else
    kt_test_fail "nameref cycle broke (left ${#store2[@]} entries)"
fi

kt_test_start "trailing-newline value survives direct-variable round-trip"
declare -A store3
v=$'line1\nline2\n\n'
store3["kx"]=$v
got="${store3[kx]}"
if [[ "$got" == "$v" ]]; then
    kt_test_pass "trailing newlines preserved (direct access; \$() would strip them)"
else
    kt_test_fail "value corrupted: $(printf '%q' "$got")"
fi

kt_test_start "zero-fork: full cycle with empty PATH"
if ( PATH=''
     declare -A s
     k=']'
     s["k$k"]="v"
     [[ -n ${s["k$k"]+x} ]] || exit 1
     [[ "${s["k$k"]}" == "v" ]] || exit 1
     pk="k$k"
     unset 's[$pk]'
     [[ ${#s[@]} -eq 0 ]] || exit 1
   ); then
    kt_test_pass "store/exists/fetch/delete spawned no external process"
else
    kt_test_fail "a storage idiom forked or failed under PATH=''"
fi

kt_test_log "002_StorageIdioms.sh completed"
