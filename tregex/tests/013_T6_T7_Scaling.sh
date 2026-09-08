#!/bin/bash
# P7 — the two performance findings, closed with RELATIVE gates (kcl PLAN §4:
# perf walls are pinned by ratios, never by milliseconds).
#
#   T6  `escape` walked the string one character at a time and rebuilt the
#       output with `+=`, i.e. O(n^2): 50 000 characters took 14.3 s. It is now
#       14 `${s//x/\x}` substitutions (BACKSLASH FIRST, so nothing is escaped
#       twice) and scales linearly.
#
#   T7  the global scans copy the remainder once per match, so a scan is
#       O(n*k). That is inherent — bash has no way to match from an offset —
#       so this is DOCUMENTED with a measured note, and the test pins the
#       shape of the curve so a future change cannot make it worse silently.
#
# Timing primitive: TStopwatch.getTimeStamp (fork-free µs clock), the same one
# both bench.sh scripts use.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"
source "$SCRIPT_DIR/../../tstopwatch/tstopwatch.sh"

kt_test_init "T6T7Scaling" "$SCRIPT_DIR" "$@"
kt_test_section "013: escape scaling (T6) and scan scaling (T7)"

_us() { TStopwatch.getTimeStamp; }

# ---------------------------------------------------------------------------
# 1. T6 — escape correctness first, then the shape of the curve.
# ---------------------------------------------------------------------------
kt_test_start "escape quotes every metacharacter exactly once [T6]"
ok=true; why=""
_esc() {  # INPUT EXPECTED
    TRegEx.escape "$1" >/dev/null
    [[ "$RESULT" == "$2" ]] || { ok=false; why+=" [escape('$1')='$RESULT' want '$2']"; }
}
_esc 'a.c'       'a\.c'
_esc 'a\c'       'a\\c'
_esc '\'         '\\'
_esc '\\'        '\\\\'
_esc '\.'        '\\\.'
_esc '.\'        '\.\\'
_esc 'a^b$c'     'a\^b\$c'
_esc 'a*b+c?'    'a\*b\+c\?'
_esc '(a)[b]{c}' '\(a\)\[b\]\{c\}'
_esc 'a|b'       'a\|b'
_esc '.^$*+?()[]{}|\' '\.\^\$\*\+\?\(\)\[\]\{\}\|\\'
_esc ''          ''
_esc 'plain'     'plain'
_esc 'a-b/c#d~e&f' 'a-b/c#d~e&f'
$ok && kt_test_pass "14 rows, backslash handled first" || kt_test_fail "$why"

kt_test_start "escaped text matches itself literally, including backslashes [T6]"
ok=true; why=""
for t in '\' 'a\' '\a' '\.' '.\' 'a.b' 'a*b' 'x[y]z' '{1,2}' 'a|b' '$' '^' '()' \
         'a\\b' '\\\\' 'é.ü' "$(printf 'a\nb')"; do
    TRegEx.escape "$t" >/dev/null; e="$RESULT"
    TRegEx.match "x${t}y" "$e"
    [[ $? -eq 0 && "$RESULT" == "$t" ]] || { ok=false; why+=" [round-trip failed for '$t' (esc='$e' got='$RESULT')]"; }
done
$ok && kt_test_pass "17 literals round-trip" || kt_test_fail "$why"

# The gate is RELATIVE, against the algorithm that was replaced: bash's own
# `${s//pat/rep}` turns out to be quadratic too on both bashes here (10k=11ms,
# 20k=48ms, 40k=183ms, 80k=712ms for ONE substitution), so "linear" is not
# available to any pure-bash implementation. What T6 buys is the constant: 14
# whole-string substitutions instead of one `+=` per character.
_escape_charloop() {   # the pre-P7 body, verbatim, as the reference
    local __s="$1" __out="" __c __i __meta='\.^$*+?()[]{}|'
    for (( __i = 0; __i < ${#__s}; __i++ )); do
        __c="${__s:__i:1}"
        [[ "$__meta" == *"$__c"* ]] && __out+="\\"
        __out+="$__c"
    done
    REPLY="$__out"
}

kt_test_start "escape is >= 8x faster than the char loop it replaced [T6]"
mid=""; for (( i = 0; i < 4000; i++ )); do mid+="a.b*c"; done       # 20 000 chars
# NB: _us writes RESULT, so the answer is captured BEFORE the second reading.
_us; t0=$RESULT; TRegEx.escape "$mid" >/dev/null; newout="$RESULT"; _us; t1=$RESULT
new=$(( t1 - t0 ))
_us; t2=$RESULT; _escape_charloop "$mid"; oldout="$REPLY"; _us; t3=$RESULT
old=$(( t3 - t2 ))
(( new < 1 )) && new=1
speedup=$(( old * 10 / new ))
if [[ "$newout" != "$oldout" ]]; then
    kt_test_fail "the two implementations disagree on a 20 000-char input"
elif (( speedup >= 80 )); then
    kt_test_pass "20k chars: new=${new}us old=${old}us -> $(( speedup/10 )).$(( speedup%10 ))x"
else
    kt_test_fail "only $(( speedup/10 )).$(( speedup%10 ))x faster (new=${new}us old=${old}us)"
fi

kt_test_start "escape of 50 000 characters stays well under 2 s [T6]"
huge=""; for (( i = 0; i < 10000; i++ )); do huge+="ab.c*"; done
_us; t0=$RESULT; TRegEx.escape "$huge" >/dev/null; hugeout="$RESULT"; _us; t1=$RESULT
el=$(( t1 - t0 ))
[[ "${#hugeout}" == 70000 ]] || kt_test_info "escaped length ${#hugeout}"
if (( el < 2000000 )); then
    kt_test_pass "${el}us for 50 000 chars (was 14.3 s)"
else
    kt_test_fail "${el}us for 50 000 chars"
fi

kt_test_start "escape has no fork and no command substitution [T6, 1.8]"
p0=$BASHPID
TRegEx.escape "a.b*c" >/dev/null
# The real body is TRegEx.__static_escape; `declare -f TRegEx.escape` returns
# kklass's dispatcher and would make this assertion vacuous (kklass.sh:982).
body="$(declare -f TRegEx.__static_escape)"
[[ -n "$body" ]] || body='$( MISSING BODY )'
if [[ $BASHPID == "$p0" && "$body" != *'$('* && "$body" != *'`'* ]]; then
    kt_test_pass "fork-free"
else
    kt_test_fail "escape forked or substitutes a command"
fi

# ---------------------------------------------------------------------------
# 2. T7 — scan scaling. The per-match cost grows with the remainder length,
#    which is the documented consequence of copying it. Pin the curve.
# ---------------------------------------------------------------------------
kt_test_start "replace scales no worse than quadratically in the match count [T7]"
s500=""; for (( i = 0; i < 500;  i++ )); do s500+="ab,"; done
s2000=""; for (( i = 0; i < 2000; i++ )); do s2000+="ab,"; done
_us; t0=$RESULT; TRegEx.replace "$s500"  "," ";" >/dev/null; _us; t1=$RESULT
_us; t2=$RESULT; TRegEx.replace "$s2000" "," ";" >/dev/null; _us; t3=$RESULT
a=$(( t1 - t0 )); b=$(( t3 - t2 ))
(( a < 1 )) && a=1
r=$(( b * 10 / a ))
# 4x the matches on 4x the text: linear would be 4x, the remainder copy makes it
# up to 16x. Anything past 24x means a new cost was added on top.
if (( r <= 240 )); then
    kt_test_pass "500=${a}us 2000=${b}us ratio=$(( r/10 )).$(( r%10 ))x (<= n^2 in the match count)"
else
    kt_test_fail "500=${a}us 2000=${b}us ratio=$(( r/10 )).$(( r%10 ))x"
fi

kt_test_start "matches() over 2000 occurrences is correct and terminates [T7]"
m=()
_us; t0=$RESULT; TRegEx.matches "$s2000" "ab" m; n="$RESULT"; _us; t1=$RESULT
if [[ "$n" == 2000 && "${#m[@]}" == 2000 && "${m[0]}" == "ab" && "${m[1999]}" == "ab" ]]; then
    kt_test_pass "2000 matches in $(( (t1-t0)/1000 ))ms"
else
    kt_test_fail "n=$n array=${#m[@]}"
fi

kt_test_start "split of 2000 pieces keeps every piece [T7]"
p=()
TRegEx.split "$s2000" "," p
if [[ "${#p[@]}" == 2001 && "${p[0]}" == "ab" && "${p[2000]}" == "" ]]; then
    kt_test_pass "2001 pieces"
else
    kt_test_fail "${#p[@]} pieces, first='${p[0]}' last='${p[2000]}'"
fi

kt_test_start "the scans copy the remainder at most once per match [T7]"
# Structural: `_replaceScan` used to take the output prefix with a SECOND slice
# (`${rem:0:loff}`) on top of the prefix-strip it had already computed. One
# slice per match is inherent, two is not.
body="$(declare -f TRegEx._replaceScan)"
n=0
[[ "$body" == *'${__trx_rem:0:__trx_loff}'* ]] && n=1
if (( n == 0 )); then
    kt_test_pass "the prefix-strip result is reused, not recomputed"
else
    kt_test_fail "_replaceScan still slices the remainder twice per match"
fi

kt_test_log "013_T6_T7_Scaling.sh completed"
