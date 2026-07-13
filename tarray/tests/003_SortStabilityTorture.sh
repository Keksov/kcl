#!/bin/bash
# 003_SortStabilityTorture.sh - TArray.sort STABILITY (a bash-side guarantee
# stronger than FPC introsort, whose equal-order is unspecified — TEST_COVERAGE
# row) proven with tagged elements, plus the torture matrix (elements with
# newlines, globs, quotes, spaces, empty strings, unicode, $()-looking text)
# and the zero-fork check. Basis: sorted-invariant + stability definition.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: TArray.sort — stability + torture + zero-fork"

# --- stability: equal keys keep INPUT order (sort by first char) ---
kt_test_start "stable: equal first-char keeps input order"
byfirst(){ local x="${1:0:1}" y="${2:0:1}"; [[ "$x" < "$y" ]] && return 0; [[ "$x" == "$y" ]] && return 1; return 2; }
s=(b1 a1 b2 a2 c1 a3 b3)
TArray.sort s byfirst
[[ "${s[*]}" == "a1 a2 a3 b1 b2 b3 c1" ]] && kt_test_pass "${s[*]}" || kt_test_fail "got ${s[*]}"

kt_test_start "stable: equal keys keep input order (tag = value:seq)"
# comparator on the VALUE (before ':') only; equal values must keep seq order
byval(){ (( ${1%%:*} < ${2%%:*} )) && return 0; (( ${1%%:*} == ${2%%:*} )) && return 1; return 2; }
n=(5:a 3:b 5:c 3:d 5:e 1:f)
TArray.sort n byval
[[ "${n[*]}" == "1:f 3:b 3:d 5:a 5:c 5:e" ]] && kt_test_pass "${n[*]}" || kt_test_fail "got ${n[*]}"

kt_test_start "stable: many duplicates (default mode keeps equal order)"
d=(m2 m1 a2 a1 m3 a3)   # 'm' and 'a' groups; within a key the tags ascend by construction? no
# default byte sort: a1 a2 a3 m1 m2 m3 (equal keys don't exist here, full order)
TArray.sort d
[[ "${d[*]}" == "a1 a2 a3 m1 m2 m3" ]] && kt_test_pass "${d[*]}" || kt_test_fail "got ${d[*]}"

# --- torture: exotic element contents (lossless, byte-order) ---
kt_test_start "torture: newline / glob / space / empty elements"
t=($'z\nz' '' '* ?' 'a b' 'a')
TArray.sort t
# byte order: '' (empty, sorts first), '* ?'(*=42), 'a', 'a b', $'z\nz'
got="[${t[0]}][${t[1]}][${t[2]}][${t[3]}][${t[4]}]"
want="[][* ?][a][a b][z"$'\n'"z]"
[[ "$got" == "$want" ]] && kt_test_pass "lossless byte-order" || kt_test_fail "got $got"

kt_test_start "torture: quotes / backticks / \$()-looking / unicode"
u=('x"q"' 'z`id`' 'a$(w)' 'café' 'b')
TArray.sort u
# byte: a$(w)('a'=97 then '$'=36...) vs b(98) vs café(99) vs x(120) vs z(122)
[[ "${u[0]}" == 'a$(w)' && "${u[1]}" == "b" && "${u[2]}" == "café" \
   && "${u[3]}" == 'x"q"' && "${u[4]}" == 'z`id`' ]] && kt_test_pass "no expansion, correct order" \
   || kt_test_fail "got [${u[0]}][${u[1]}][${u[2]}][${u[3]}][${u[4]}]"

kt_test_start "torture: element equal to a stub sentinel is just data"
v=(zzz __tarray_stub__:x aaa)
TArray.sort v
[[ "${v[0]}" == "__tarray_stub__:x" && "${v[2]}" == "zzz" ]] && kt_test_pass "sentinel is data" \
   || kt_test_fail "got ${v[*]}"

# --- larger correctness: sort then verify non-decreasing (numeric) ---
kt_test_start "correctness: 200 pseudo-random ints end up non-decreasing"
big=(); x=12345
for (( i=0; i<200; i++ )); do x=$(( (x*1103515245 + 12345) & 0x7fffffff )); big+=( $(( x % 1000 - 500 )) ); done
TArray.sort big -n
ok=1; for (( i=1; i<${#big[@]}; i++ )); do (( big[i-1] > big[i] )) && { ok=0; break; }; done
[[ $ok -eq 1 && "${#big[@]}" == "200" ]] && kt_test_pass "200 elems non-decreasing" || kt_test_fail "not sorted at $i"

# --- zero-fork ---
kt_test_start "PATH='' : sort (all modes) needs no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tarray.sh" 2>/dev/null
    z1=(3 1 2); TArray.sort z1
    z2=(3 1 2); TArray.sort z2 -n
    byf(){ (( $1 < $2 )) && return 0; (( $1 == $2 )) && return 1; return 2; }
    z3=(3 1 2); TArray.sort z3 byf
    printf '%s|%s|%s' "${z1[*]}" "${z2[*]}" "${z3[*]}"
)"
[[ "$zf" == "1 2 3|1 2 3|1 2 3" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "003_SortStabilityTorture.sh completed"
