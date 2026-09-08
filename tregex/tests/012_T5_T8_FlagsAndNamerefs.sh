#!/bin/bash
# P7 — malformed CALLS answer rc 2 (kcl/README.md §1.2, §1.7).
#
#   T5  flags were tested with `*i*`, so any flag word containing an `i` turned
#       case-insensitivity on: `isMatch "ABC" "abc" Multiline` matched. Every
#       other flag word was silently ignored. Flags are now parsed strictly:
#       only `i` (and the `-`/empty placeholders) are accepted, anything else
#       is rc 2 and the call does nothing.
#
#   T8  an invalid or reserved output-array name produced a bash `local -n`
#       diagnostic on stderr, rc 0 and RESULT=1; `__tre_g`/`__trx_texts` bound
#       the caller's array to the unit's own scratch. Now: rc 2, silent,
#       nothing written, and the reserved list is complete.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
UNIT="$SCRIPT_DIR/../tregex.sh"
source "$UNIT"

kt_test_init "T5T8FlagsAndNamerefs" "$SCRIPT_DIR" "$@"
kt_test_section "012: strict flag parsing (T5) and output-array validation (T8)"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# ---------------------------------------------------------------------------
# 1. T5 — only `i` is a flag.
# ---------------------------------------------------------------------------
kt_test_start "an unknown flag word is rc 2 on every member that takes flags [T5]"
ok=true; why=""
for f in Multiline m x s g IgnoreCase I "i " " i" "ii" "-i"; do
    a=(); p=(); rc=0
    TRegEx.isMatch "ABC" "abc" "$f" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [isMatch flags='$f' rc=$rc]"; }
    rc=0; TRegEx.match "ABC" "abc" "$f" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [match flags='$f' rc=$rc]"; }
    rc=0; TRegEx.matches "ABC" "abc" a - "$f" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [matches flags='$f' rc=$rc]"; }
    rc=0; TRegEx.split "ABC" "abc" p - "$f" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [split flags='$f' rc=$rc]"; }
    rc=0; TRegEx.replace "ABC" "abc" "#" - "$f" >/dev/null || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [replace flags='$f' rc=$rc]"; }
done
$ok && kt_test_pass "11 flag words x 5 members = rc 2" || kt_test_fail "$why"

kt_test_start "an unknown flag does not perform the operation [T5]"
ok=true; why=""
a=(9 9 9); RESULT="pre"
TRegEx.matches "a1b2" "[0-9]" a - Multiline
[[ "${#a[@]}" == 3 ]] || { ok=false; why+=" [matches wrote the array: ${a[*]}]"; }
r="$(TRegEx.replace "a1b2" "[0-9]" "#" - Multiline 2>&1)"
[[ "$r" == "a1b2" ]] || { ok=false; why+=" [replace changed the text: '$r']"; }
$ok && kt_test_pass "arrays untouched, text unchanged" || kt_test_fail "$why"

kt_test_start "an unknown flag is silent unless VERBOSE_KKLASS=debug [contract 1.2]"
errf="$TMP/flag.err"
TRegEx.isMatch "ABC" "abc" Multiline 2>"$errf"
quiet="$(<"$errf")"
VERBOSE_KKLASS=debug TRegEx.isMatch "ABC" "abc" Multiline 2>"$errf"
loud="$(<"$errf")"
if [[ -z "$quiet" && -n "$loud" ]]; then
    kt_test_pass "silent by default, speaks under debug"
else
    kt_test_fail "quiet='$quiet' loud='$loud'"
fi

kt_test_start "the accepted flag spellings still work [T5]"
ok=true; why=""
TRegEx.isMatch "ABC" "abc" i   || { ok=false; why+=" [i]"; }
TRegEx.isMatch "ABC" "abc" ""  && { ok=false; why+=" ['' should be case-sensitive]"; }
TRegEx.isMatch "ABC" "abc" "-" && { ok=false; why+=" ['-' should be case-sensitive]"; }
TRegEx.isMatch "ABC" "ABC" "-" || { ok=false; why+=" ['-' placeholder rejected a real match]"; }
TRegEx.isMatch "ABC" "abc"     && { ok=false; why+=" [absent should be case-sensitive]"; }
a=(); TRegEx.matches "aAa" "a" a - i; [[ "$RESULT" == 3 ]] || { ok=false; why+=" [matches i -> $RESULT]"; }
r="$(TRegEx.replace "aAa" "a" "#" - i)"; [[ "$r" == "###" ]] || { ok=false; why+=" [replace i -> '$r']"; }
p=(); TRegEx.split "aXbxc" "x" p - i; [[ "${#p[@]}" == 3 ]] || { ok=false; why+=" [split i -> ${#p[@]}]"; }
$ok && kt_test_pass "i / '' / '-' / absent" || kt_test_fail "$why"

kt_test_start "the ambient nocasematch is restored after a rejected flag [T5]"
shopt -u nocasematch
TRegEx.isMatch "ABC" "abc" Multiline 2>/dev/null
off=$(shopt -q nocasematch && echo on || echo off)
shopt -s nocasematch
TRegEx.isMatch "ABC" "abc" Multiline 2>/dev/null
on=$(shopt -q nocasematch && echo on || echo off)
shopt -u nocasematch
[[ "$off" == off && "$on" == on ]] && kt_test_pass "restored on both sides" \
    || kt_test_fail "off-case=$off on-case=$on"

# ---------------------------------------------------------------------------
# 2. T8 — output-array names.
# ---------------------------------------------------------------------------
kt_test_start "an invalid output-array name is rc 2, silent, nothing written [T8]"
ok=true; why=""
errf="$TMP/nameref.err"
for bad in "1bad" "a-b" "a b" "" "a.b" "a[0]" 'x$(touch "'"$TMP"'/pwn")' "a;b"; do
    rc=0
    TRegEx.matches "abc" "b" "$bad" 2>"$errf" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [matches name='$bad' rc=$rc]"; }
    [[ -z "$(<"$errf")" ]] || { ok=false; why+=" [matches name='$bad' stderr='$(<"$errf")']"; }
    rc=0
    TRegEx.split "a,b" "," "$bad" 2>"$errf" || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [split name='$bad' rc=$rc]"; }
    [[ -z "$(<"$errf")" ]] || { ok=false; why+=" [split name='$bad' stderr]"; }
done
[[ -e "$TMP/pwn" ]] && { ok=false; why+=" [INJECTION: the canary was created]"; }
$ok && kt_test_pass "8 bad names x 2 members" || kt_test_fail "$why"

kt_test_start "reserved output-array names are refused [T8, contract 1.7]"
ok=true; why=""
for r in __tre_g __tre_m __tre_rc __trx_texts __trx_offs __trx_out __trx_rem \
         __trx_limit __trx_flags RESULT RESULT_INDEX RESULT_LENGTH RESULT_GROUPS \
         REPLY IFS this __inst__ __class__ __kk_x __KK_INT; do
    rc=0; TRegEx.matches "abc" "b" "$r" 2>/dev/null || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [matches '$r' rc=$rc]"; }
    rc=0; TRegEx.split "a,b" "," "$r" 2>/dev/null || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [split '$r' rc=$rc]"; }
done
$ok && kt_test_pass "20 reserved names refused by both" || kt_test_fail "$why"

kt_test_start "the reserved offsets-array name is validated too [T8]"
ok=true; why=""
good=(); rc=0
TRegEx.matches "a1b2" "[0-9]" good "__trx_texts" 2>/dev/null || rc=$?
(( rc == 2 )) || { ok=false; why+=" [reserved offsets name rc=$rc]"; }
[[ "${#good[@]}" == 0 ]] || { ok=false; why+=" [texts array was filled anyway: ${good[*]}]"; }
rc=0; TRegEx.matches "a1b2" "[0-9]" good "1bad" 2>/dev/null || rc=$?
(( rc == 2 )) || { ok=false; why+=" [invalid offsets name rc=$rc]"; }
$ok && kt_test_pass "arg 4 validated like arg 3" || kt_test_fail "$why"

kt_test_start "a rejected name leaves RESULT at 0 and the storage intact [T8]"
ok=true; why=""
declare -a keep=(x y z)
RESULT="pre"
TRegEx.matches "abc" "b" "RESULT" 2>/dev/null
[[ "$RESULT" == 0 ]] || { ok=false; why+=" [RESULT='$RESULT' want 0]"; }
[[ "${keep[*]}" == "x y z" ]] || { ok=false; why+=" [caller array clobbered: ${keep[*]}]"; }
$ok && kt_test_pass "RESULT=0, no collateral writes" || kt_test_fail "$why"

kt_test_start "valid names still work, including one that only LOOKS reserved [T8]"
ok=true; why=""
__tregex_ok=(); TRegEx.matches "a1b2" "[0-9]" __tregex_ok
[[ "$RESULT" == 2 && "${__tregex_ok[*]}" == "1 2" ]] || { ok=false; why+=" [__tregex_ok -> n=$RESULT '${__tregex_ok[*]}']"; }
_result=(); TRegEx.matches "a1b2" "[0-9]" _result
[[ "${_result[*]}" == "1 2" ]] || { ok=false; why+=" [_result -> '${_result[*]}']"; }
o=(); m=(); TRegEx.matches "a1b2" "[0-9]" m o
[[ "${m[*]}" == "1 2" && "${o[*]}" == "1 3" ]] || { ok=false; why+=" [m='${m[*]}' o='${o[*]}']"; }
$ok && kt_test_pass "normal identifiers unaffected" || kt_test_fail "$why"

kt_test_start "maxCount validation still answers rc 2, not rc 1 [T2, contract 1.2]"
ok=true; why=""
for bad in "abc" "1.5" 'x[$(touch "'"$TMP"'/pwn2")]' "1 2"; do
    p=(); rc=0; TRegEx.split "a,b,c" "," p "$bad" 2>/dev/null || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [split maxCount='$bad' rc=$rc]"; }
    rc=0; TRegEx.replace "a,b" "," ";" "$bad" >/dev/null 2>&1 || rc=$?
    (( rc == 2 )) || { ok=false; why+=" [replace maxCount='$bad' rc=$rc]"; }
done
[[ -e "$TMP/pwn2" ]] && { ok=false; why+=" [INJECTION]"; }
$ok && kt_test_pass "4 shapes x 2 members" || kt_test_fail "$why"

kt_test_log "012_T5_T8_FlagsAndNamerefs.sh completed"
