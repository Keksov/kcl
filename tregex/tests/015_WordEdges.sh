#!/usr/bin/env bash
# 015_WordEdges.sh - launch L5.4-12 (owner OG14 = b): `\<` `\>` `\b` give
# word-boundary semantics on every C library. Where the library spells them
# natively nothing changes; where it does not, TRegEx rewrites the pattern
# once (cached) to the spelling it accepts and drops the groups it inserted.
#
#   1. the rewriter table, per forced mode (KCL_TREGEX_WB + TRegEx._wbReset);
#   2. the cache: keys with ] $ @ * space, a lookup that really hits, the bound;
#   3. the probe and the seam (auto picks the mode of this platform's libc);
#   4. the API through every forced mode: isMatch / match / matches / split /
#      replace / replaceCb with \b and groups — the group numbering is the
#      user's. A mode whose spelling this C library lacks is N/A (named).
#
# Measured (L5.4-12): matches("ab cd", '\b') is 5 matches at 0..4 in every
# mode that works on newlib (native/ltgt/class) and FreeBSD libc (ltgt/class)
# — the T4/R12 zero-length delta of tests/011; musl native gives one more at 5
# (its \b also matches an EMPTY subject). Library facts the N/A rows name:
# FreeBSD libc has no ERE back-references at all ((a)\1 misses "aa"); newlib
# loses one after an alternation ((x|y)(a)\2 misses "xaa"); musl tries only the
# first branch of (\<|\>) and rejects [[:<:]].

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

kt_test_init "WordEdges" "$SCRIPT_DIR" "$@"
kt_test_section "015: word edges \\< \\> \\b on every C library (L5.4-12)"

unset KCL_TREGEX_WB

# _mode M -> force mode M for the next pattern (the documented seam)
_mode() { KCL_TREGEX_WB=$1; TRegEx._wbReset; }

# what this C library spells natively (raw [[ =~ ]], no TRegEx)
_raw_ok() {   # PATTERN -> rc 0 when it matches "a foo b" and misses "afoob"
    local __r=$1
    [[ 'a foo b' =~ $__r ]] 2>/dev/null && ! [[ 'afoob' =~ $__r ]] 2>/dev/null
}
LIB_LT=0; _raw_ok '\<foo\>' && LIB_LT=1
LIB_B=0;  _raw_ok '\bfoo\b' && LIB_B=1
LIB_CL=0; _raw_ok '[[:<:]]foo[[:>:]]' && LIB_CL=1
# ... and the spelling each rewriting mode hands it for \b: musl tries only the
# FIRST branch of an alternation of two word edges, so `foo(\<|\>)` misses
# "a foo b" there (measured on kb-alpine, L5.4-12); auto never picks ltgt on
# musl (it is native), so only a FORCED ltgt meets it
LIB_LTGT=0; _raw_ok '(\<|\>)foo(\<|\>)' && LIB_LTGT=1
LIB_CLB=0;  _raw_ok '([[:<:]]|[[:>:]])foo([[:<:]]|[[:>:]])' && LIB_CLB=1
# the prerequisites of each mode on this library
MODE_OK_native=$(( LIB_LT && LIB_B ))
MODE_OK_ltgt=$(( LIB_LT && LIB_LTGT ))
MODE_OK_class=$(( LIB_CL && LIB_CLB ))
kt_test_log "this C library: \\< \\> native=$LIB_LT, \\b native=$LIB_B, [[:<:]] [[:>:]]=$LIB_CL, (\\<|\\>)=$LIB_LTGT, ([[:<:]]|[[:>:]])=$LIB_CLB (OSTYPE=$OSTYPE)"

# ---------------------------------------------------------------------------
# 1. The rewriter table
# ---------------------------------------------------------------------------
# _rw MODE PATTERN WANT-RE WANT-DROP
_rw() {
    local __tre_wbre __tre_wbdrop
    _mode "$1"
    TRegEx._wbRewrite "$2"
    if [[ "$__tre_wbre" != "$3" || "$__tre_wbdrop" != "$4" ]]; then
        RW_OK=false; RW_WHY+=$'\n'"  [$1] '$2' -> '$__tre_wbre' drop='$__tre_wbdrop'; want '$3' drop='$4'"
    fi
}

kt_test_start "rewriter, mode ltgt (FreeBSD): \\b -> (\\<|\\>), \\< \\> kept, brackets and \\\\ untouched, back-references renumbered"
RW_OK=true; RW_WHY=""
_rw ltgt '\<foo\>'          '\<foo\>'                 ''
_rw ltgt '\bfoo\b'          '(\<|\>)foo(\<|\>)'       '1 2'
_rw ltgt '\\<'              '\\<'                     ''
_rw ltgt '\\\<x'            '\\\<x'                   ''
_rw ltgt '\\b'              '\\b'                     ''
_rw ltgt '\\\b'             '\\(\<|\>)'               '1'
_rw ltgt '[\<]'             '[\<]'                    ''
_rw ltgt '[^\b]'            '[^\b]'                   ''
_rw ltgt '[]\b]'            '[]\b]'                   ''
_rw ltgt '[^]\b]x\b'        '[^]\b]x(\<|\>)'          '1'
_rw ltgt '[[:alpha:]\b]x\b' '[[:alpha:]\b]x(\<|\>)'   '1'
_rw ltgt '(x\b)(y)'         '(x(\<|\>))(y)'           '2'
_rw ltgt '\b(a)\1'          '(\<|\>)(a)\2'            '1'
_rw ltgt '(a)\b\1'          '(a)(\<|\>)\1'            '2'
_rw ltgt '\bx'              '(\<|\>)x'                '1'
_rw ltgt 'x\b'              'x(\<|\>)'                '1'
_rw ltgt '\b'               '(\<|\>)'                 '1'
_rw ltgt '\.\b\('           '\.(\<|\>)\('             '1'
_rw ltgt ''                 ''                        ''
_rw ltgt 'a(b)c'            'a(b)c'                   ''
_rw ltgt '(a)(b)(c)(d)(e)(f)(g)(h)(i)\b\9' '(a)(b)(c)(d)(e)(f)(g)(h)(i)(\<|\>)\9' '10'
# \9 would become \10, which ERE reads as \1 + '0': unspellable -> '' -> rc 2
_rw ltgt '\b(a)(b)(c)(d)(e)(f)(g)(h)(i)\9' '' '1'
# a reference to a group not opened yet is invalid as written; next to an
# inserted group it would become valid (\1 = the edge): '' -> rc 2 (SV R4)
_rw ltgt '\1\b(a)'          ''                        '1'
_rw ltgt '\1\<(a)'          '\1\<(a)'                 ''
$RW_OK && kt_test_pass "24 rows" || kt_test_fail "$RW_WHY"

kt_test_start "rewriter, mode class (macOS): \\< -> [[:<:]], \\> -> [[:>:]], \\b -> ([[:<:]]|[[:>:]])"
RW_OK=true; RW_WHY=""
_rw class '\<foo\>'          '[[:<:]]foo[[:>:]]'                       ''
_rw class '\bfoo\b'          '([[:<:]]|[[:>:]])foo([[:<:]]|[[:>:]])'   '1 2'
_rw class '\\<'              '\\<'                                     ''
_rw class '\\\<x'            '\\[[:<:]]x'                              ''
_rw class '[\<]'             '[\<]'                                    ''
_rw class '[^\>]'            '[^\>]'                                   ''
_rw class '[^\b]'            '[^\b]'                                   ''
_rw class '[]\b]'            '[]\b]'                                   ''
_rw class '[[:alpha:]\b]x\>' '[[:alpha:]\b]x[[:>:]]'                   ''
_rw class '(x\b)(y)'         '(x([[:<:]]|[[:>:]]))(y)'                 '2'
_rw class '\b(a)\1'          '([[:<:]]|[[:>:]])(a)\2'                  '1'
_rw class '\bx'              '([[:<:]]|[[:>:]])x'                      '1'
_rw class 'x\b'              'x([[:<:]]|[[:>:]])'                      '1'
_rw class '\<'               '[[:<:]]'                                 ''
_rw class ''                 ''                                        ''
_rw class 'a(b)c'            'a(b)c'                                   ''
_rw class '\1\b(a)'          ''                                        '1'
_rw class '\1\<(a)'          '\1[[:<:]](a)'                            ''
$RW_OK && kt_test_pass "18 rows" || kt_test_fail "$RW_WHY"

kt_test_start "rewriter with __TRE_WB_B=0 (the probe found the rewritten \\b broken): \\< \\> translated, \\b copied for the library"
RW_OK=true; RW_WHY=""
for m in ltgt class; do
    _mode "$m"; TRegEx._wbProbe; __TRE_WB_B=0
    TRegEx._wbRewrite '\bfoo\<(a)\1'
    want='\bfoo\<(a)\1'; [[ $m == class ]] && want='\bfoo[[:<:]](a)\1'
    [[ "$__tre_wbre" == "$want" && -z "$__tre_wbdrop" ]] || { RW_OK=false; RW_WHY+=" [$m -> '$__tre_wbre' drop='$__tre_wbdrop' want '$want']"; }
done
$RW_OK && kt_test_pass "2 rows" || kt_test_fail "$RW_WHY"

kt_test_start "rewriter, modes native and none: the identity, nothing cached"
RW_OK=true; RW_WHY=""
for m in native none; do
    for p in '\<foo\>' '\bfoo\b' '\b(a)\1' '(x\b)(y)' '[\<]' '\\<'; do
        _rw "$m" "$p" "$p" ''
    done
    (( ${#__TRE_WB_CACHE[@]} == 0 )) || { RW_OK=false; RW_WHY+=" [$m cached ${#__TRE_WB_CACHE[@]}]"; }
done
$RW_OK && kt_test_pass "identity" || kt_test_fail "$RW_WHY"

# ---------------------------------------------------------------------------
# 2. The cache
# ---------------------------------------------------------------------------
kt_test_start "a pattern without \\< \\> \\b gets no cache entry (empty pattern and \\. included)"
_mode ltgt; TRegEx._wbProbe
ok=true; why=""
for p in 'abc' '' 'a\.c' 'a\1' '[[:<:]]x'; do
    TRegEx._wbRewrite "$p"
    [[ "$__tre_wbre" == "$p" && -z "$__tre_wbdrop" ]] || { ok=false; why+=" ['$p' -> '$__tre_wbre']"; }
done
(( ${#__TRE_WB_CACHE[@]} == 0 )) || { ok=false; why+=" [cache has ${#__TRE_WB_CACHE[@]} entries]"; }
$ok && kt_test_pass "0 entries" || kt_test_fail "$why"

kt_test_start "cache keys with ] \$ @ * and a space: stored under the pattern, and a lookup really hits"
_mode ltgt; TRegEx._wbProbe
ok=true; why=""
keys=('a]\b' '\b$' '@\b' '*' 'x*\b' 'a b\b' '\b[]]' '\b(@)' '[$]\<')
for k in "${keys[@]}"; do
    TRegEx._wbRewrite "$k"; first=$__tre_wbre
    if [[ "$k" == *'\'[\<\>b]* ]]; then
        [[ -n "${__TRE_WB_CACHE[$k]+x}" && "${__TRE_WB_CACHE[$k]}" == "$first" ]] \
            || { ok=false; why+=" [no entry for '$k']"; continue; }
        # poison the entry: a rewrite that returns the poison read the cache
        __TRE_WB_CACHE[$k]=POISON; __TRE_WB_DROPC[$k]=9
        TRegEx._wbRewrite "$k"
        [[ "$__tre_wbre" == POISON && "$__tre_wbdrop" == 9 ]] || { ok=false; why+=" [no hit for '$k': '$__tre_wbre']"; }
    else
        [[ -z "${__TRE_WB_CACHE[$k]+x}" ]] || { ok=false; why+=" [entry for '$k']"; }
    fi
done
# every key is its own entry (none of them emptied or aliased the array)
(( ${#__TRE_WB_CACHE[@]} == ${#keys[@]} - 1 )) || { ok=false; why+=" [size ${#__TRE_WB_CACHE[@]} want $(( ${#keys[@]} - 1 ))]"; }
$ok && kt_test_pass "${#__TRE_WB_CACHE[@]} entries, each one hit" || kt_test_fail "$why"

kt_test_start "the cache is bounded: cleared when it would exceed 256 entries"
_mode ltgt; TRegEx._wbProbe
ok=true; why=""; max=0
for (( i = 0; i < 300; i++ )); do
    TRegEx._wbRewrite "x$i\\b"
    (( ${#__TRE_WB_CACHE[@]} > max )) && max=${#__TRE_WB_CACHE[@]}
done
(( max == 256 )) || { ok=false; why+=" [max $max want 256]"; }
(( ${#__TRE_WB_CACHE[@]} == ${#__TRE_WB_DROPC[@]} )) || { ok=false; why+=" [cache ${#__TRE_WB_CACHE[@]} != drop ${#__TRE_WB_DROPC[@]}]"; }
[[ "${__TRE_WB_CACHE['x299\b']-}" == 'x299(\<|\>)' ]] || { ok=false; why+=" [newest entry missing]"; }
$ok && kt_test_pass "max 256, now ${#__TRE_WB_CACHE[@]}" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 3. The probe and the seam
# ---------------------------------------------------------------------------
kt_test_start "auto: the probe picks this C library's mode (macOS class, FreeBSD ltgt, else native)"
case "$OSTYPE" in
    darwin*)  want=class ;;
    freebsd*) want=ltgt ;;
    *)        want=native ;;
esac
_mode auto; TRegEx.isMatch "a foo b" '\<foo\>' >/dev/null
AUTO_MODE=${__TRE_WB_MODE-}; AUTO_B=${__TRE_WB_B-}
# the rewritten \b works on every platform we know (musl, where it would not,
# is native), so auto must translate \b wherever it picks ltgt/class
[[ "$AUTO_MODE" == "$want" && "$AUTO_B" == 1 ]] && kt_test_pass "auto -> $AUTO_MODE, \\b rewrite=$AUTO_B" \
    || kt_test_fail "auto -> '$AUTO_MODE' __TRE_WB_B='$AUTO_B', want '$want' and 1 (OSTYPE=$OSTYPE)"

kt_test_start "auto keeps the \\b rewrite only if the rewritten \\b works on this library (__TRE_WB_B)"
case "$AUTO_MODE" in
    ltgt)  __r='(\<|\>)foo(\<|\>)' ;;
    class) __r='([[:<:]]|[[:>:]])foo([[:<:]]|[[:>:]])' ;;
    *)     __r='' ;;
esac
if [[ -z $__r ]]; then
    [[ "$AUTO_B" == 1 ]] && kt_test_pass "mode $AUTO_MODE: nothing rewritten, __TRE_WB_B=1" || kt_test_fail "mode $AUTO_MODE: __TRE_WB_B=$AUTO_B"
else
    raw=0; _raw_ok "$__r" && raw=1
    [[ "$AUTO_B" == "$raw" ]] && kt_test_pass "mode $AUTO_MODE: rewritten \\b works=$raw = __TRE_WB_B" \
        || kt_test_fail "mode $AUTO_MODE: rewritten \\b works=$raw, __TRE_WB_B=$AUTO_B"
fi

kt_test_start "the seam: KCL_TREGEX_WB forces each mode (\\b rewrite on, off for none); unset and an unknown value mean auto"
ok=true; why=""
for m in native ltgt class none; do
    _mode "$m"; TRegEx._wbProbe
    wb=1; [[ $m == none ]] && wb=0
    [[ "$__TRE_WB_MODE" == "$m" && "$__TRE_WB_B" == "$wb" ]] || { ok=false; why+=" [$m -> $__TRE_WB_MODE B=$__TRE_WB_B]"; }
done
_mode bogus; TRegEx._wbProbe
[[ "$__TRE_WB_MODE" == "$want" ]] || { ok=false; why+=" [bogus -> $__TRE_WB_MODE want $want]"; }
unset KCL_TREGEX_WB; TRegEx._wbReset; TRegEx._wbProbe
[[ "$__TRE_WB_MODE" == "$want" ]] || { ok=false; why+=" [unset -> $__TRE_WB_MODE want $want]"; }
$ok && kt_test_pass "forced and auto" || kt_test_fail "$why"

kt_test_start "TRegEx._wbReset forgets the mode and the cache; the next pattern probes again"
ok=true; why=""
_mode ltgt; TRegEx.isMatch "a foo b" '\bfoo\b' >/dev/null
[[ "${__TRE_WB_MODE-}" == ltgt && ${#__TRE_WB_CACHE[@]} == 1 ]] || { ok=false; why+=" [before: mode=${__TRE_WB_MODE-} n=${#__TRE_WB_CACHE[@]}]"; }
TRegEx._wbReset
[[ -z "${__TRE_WB_MODE+x}" ]] || { ok=false; why+=" [mode still set]"; }
declare -p __TRE_WB_CACHE >/dev/null 2>&1 && { ok=false; why+=" [cache still declared]"; }
declare -p __TRE_WB_DROPC >/dev/null 2>&1 && { ok=false; why+=" [drop cache still declared]"; }
KCL_TREGEX_WB=class; TRegEx.isMatch "a foo b" '\bfoo\b' >/dev/null
[[ "${__TRE_WB_MODE-}" == class ]] || { ok=false; why+=" [after: mode=${__TRE_WB_MODE-}]"; }
$ok && kt_test_pass "reset, then class" || kt_test_fail "$why"
unset KCL_TREGEX_WB; TRegEx._wbReset

# ---------------------------------------------------------------------------
# 4. The API through each forced mode
# ---------------------------------------------------------------------------
# _cbn: replaceCb callback — REPLY = the argument count and the arguments
_cbn() { REPLY="$#:$*"; }

# _api MODE -> one kt row: every member with \b \< \> and groups
_api() {
    local m=$1 ok=true why="" rc a=() o=() p=() r want_n want_o na="" eff
    kt_test_start "API in mode $m: isMatch/match/matches/split/replace/replaceCb see word edges and the user's group numbers"
    case "$m" in
        native) (( MODE_OK_native )) || na="this C library has no native \\b or \\< \\> (mode native rewrites nothing)" ;;
        ltgt)   (( MODE_OK_ltgt ))   || na="this C library lacks \\< \\> or mishandles (\\<|\\>) (musl: only the first branch), which mode ltgt needs" ;;
        class)  (( MODE_OK_class ))  || na="this C library rejects [[:<:]] [[:>:]] or their alternation, which mode class needs" ;;
    esac
    if [[ -n $na ]]; then
        # N/A only for a FORCED mode this library cannot do; the mode auto
        # picked must work (SV R1)
        if [[ $m == "$AUTO_MODE" ]]; then kt_test_fail "mode $m is the one auto picked, yet: $na"
        else kt_test_pass "N/A: $na"; fi
        return
    fi
    _mode "$m"
    eff=$m; [[ $m == auto ]] && eff=$AUTO_MODE
    TRegEx.isMatch "the cat sat" '\bcat\b'; rc=$?;  [[ $rc == 0 ]] || { ok=false; why+=" [isMatch \\bcat\\b rc=$rc]"; }
    TRegEx.isMatch "concatenate" '\bcat\b'; rc=$?;  [[ $rc == 1 ]] || { ok=false; why+=" [isMatch partial rc=$rc]"; }
    TRegEx.isMatch "a foo b" '\<foo\>'; rc=$?;      [[ $rc == 0 ]] || { ok=false; why+=" [isMatch \\<foo\\> rc=$rc]"; }
    TRegEx.isMatch "afoob" '\<foo\>'; rc=$?;        [[ $rc == 1 ]] || { ok=false; why+=" [isMatch \\<foo\\> partial rc=$rc]"; }
    TRegEx.isMatch "x foo y" 'foo\>'; rc=$?;       [[ $rc == 0 ]] || { ok=false; why+=" [isMatch foo\\> rc=$rc]"; }
    TRegEx.isMatch "x fooy" 'foo\>'; rc=$?;         [[ $rc == 1 ]] || { ok=false; why+=" [isMatch foo\\> partial rc=$rc]"; }
    TRegEx.match "the cat sat" '\b(c)(a)t\b'; rc=$?
    [[ $rc == 0 && "$RESULT" == cat && "$RESULT_INDEX" == 4 && "${#RESULT_GROUPS[@]}" == 2 \
       && "${RESULT_GROUPS[0]}" == c && "${RESULT_GROUPS[1]}" == a ]] \
        || { ok=false; why+=" [match rc=$rc R=$RESULT idx=$RESULT_INDEX g=(${RESULT_GROUPS[*]}) n=${#RESULT_GROUPS[@]}]"; }
    TRegEx.match "ab c d" '(c)\b'; rc=$?
    [[ $rc == 0 && "$RESULT_INDEX" == 3 && "${#RESULT_GROUPS[@]}" == 1 && "${RESULT_GROUPS[0]}" == c ]] \
        || { ok=false; why+=" [match (c)\\b: rc=$rc idx=$RESULT_INDEX g=(${RESULT_GROUPS[*]}) want one group]"; }
    # \b counts: 5 at 0..4 (T4/R12); 6 only where the LIBRARY's own \b
    # matches '' (musl) and the mode hands \b to it unchanged (native) —
    # derived from the raw engine, not from TRegEx (SV R2)
    want_n=5; want_o="0 1 2 3 4"
    if [[ $eff == native ]] && (( RAW_WB_EMPTY )); then want_n=6; want_o="0 1 2 3 4 5"; fi
    TRegEx.matches "ab cd" '\b' a o
    [[ "$RESULT" == "$want_n" && "${o[*]}" == "$want_o" ]] || { ok=false; why+=" [matches \\b n=$RESULT offs='${o[*]}' want $want_n '$want_o']"; }
    a=(); o=(); TRegEx.matches "ab, cd e" '\b[a-z]+\b' a o
    [[ "$RESULT" == 3 && "${a[*]}" == "ab cd e" && "${o[*]}" == "0 4 7" ]] || { ok=false; why+=" [matches words n=$RESULT a=(${a[*]}) o=(${o[*]})]"; }
    p=(); TRegEx.split "a-b c" '\b(-)\b' p
    r=$(printf '[%s]' "${p[@]}")
    [[ "$RESULT" == 3 && "$r" == "[a][-][b c]" ]] || { ok=false; why+=" [split $r n=$RESULT]"; }
    TRegEx.replace "foo bar" '\b([a-z])([a-z]*)\b' '$2$1' >/dev/null
    [[ "$RESULT" == "oof arb" ]] || { ok=false; why+=" [replace \$2\$1 -> '$RESULT']"; }
    TRegEx.replace "x foo y" '\b(f)(o+)\b' '${2}-$1-$3' >/dev/null
    [[ "$RESULT" == 'x oo-f-$3 y' ]] || { ok=false; why+=" [replace \${2}-\$1-\$3 -> '$RESULT' (\$3 is no group)]"; }
    TRegEx.replaceCb "go foo" '\b(f)(o*)\b' _cbn >/dev/null
    [[ "$RESULT" == "go 3:foo f oo" ]] || { ok=false; why+=" [replaceCb -> '$RESULT']"; }
    $ok && kt_test_pass "all members" || kt_test_fail "$why"
}
__r='\b'; RAW_WB_EMPTY=0; [[ '' =~ $__r ]] 2>/dev/null && RAW_WB_EMPTY=1
_api auto
_api native
_api ltgt
_api class

kt_test_start "back-reference after \\b keeps pointing at the user's group, in every mode"
ok=true; why=""; na=""
# mode native keeps the pattern: needs plain ERE back-references; ltgt/class
# insert an alternation group before them: needs a back-reference that
# survives one (newlib loses it: `(x|y)(a)\2` misses "xaa")
__r='(a)\1';      RAW_BR=0;  [[ 'aa'  =~ $__r ]] 2>/dev/null && RAW_BR=1
__r='(x|y)(a)\2'; RAW_BRA=0; [[ 'xaa' =~ $__r ]] 2>/dev/null && RAW_BRA=1
for m in native ltgt class; do
    case "$m" in
        native) (( MODE_OK_native && RAW_BR )) || { na+=" $m"; continue; } ;;
        ltgt)   (( MODE_OK_ltgt && RAW_BRA ))  || { na+=" $m"; continue; } ;;
        class)  (( MODE_OK_class && RAW_BRA )) || { na+=" $m"; continue; } ;;
    esac
    _mode "$m"
    TRegEx.match "x aa" '\b(a)\1'; rc=$?
    [[ $rc == 0 && "$RESULT" == aa && "${RESULT_GROUPS[*]}" == a ]] || { ok=false; why+=" [$m rc=$rc R=$RESULT g=(${RESULT_GROUPS[*]})]"; }
    TRegEx.isMatch "x ab" '\b(a)\1'; rc=$?
    [[ $rc == 1 ]] || { ok=false; why+=" [$m no-match rc=$rc]"; }
done
if [[ -n $na ]]; then
    msg="N/A in:$na — this C library lacks the mode's spelling, or its ERE loses a back-reference (raw (a)\\1=$RAW_BR, (x|y)(a)\\2=$RAW_BRA)"
    $ok && kt_test_pass "$msg" || kt_test_fail "$why; $msg"
else
    $ok && kt_test_pass "native ltgt class" || kt_test_fail "$why"
fi

kt_test_start "an unspellable back-reference (would be \\10) is rc 2, not a silent \\1 + '0'"
_mode ltgt
TRegEx.isMatch "aabcdefghii" '\b(a)(b)(c)(d)(e)(f)(g)(h)(i)\9'; rc=$?
[[ $rc == 2 ]] && kt_test_pass "rc 2" || kt_test_fail "rc=$rc"

kt_test_start "mode none: patterns pass unchanged, the result is the library's own rc"
ok=true; why=""
_mode none
for p in '\<foo\>' '\bfoo\b' '\b(a)\1'; do
    for t in "a foo b" "afoob" "x aa"; do
        __r=$p; [[ "$t" =~ $__r ]] 2>/dev/null; want=$?
        TRegEx.isMatch "$t" "$p"; rc=$?
        [[ $rc == "$want" ]] || { ok=false; why+=" ['$t' '$p' rc=$rc want $want]"; }
    done
done
(( ${#__TRE_WB_CACHE[@]} == 0 )) || { ok=false; why+=" [cache has ${#__TRE_WB_CACHE[@]} entries]"; }
$ok && kt_test_pass "unchanged" || kt_test_fail "$why"

kt_test_start "the i-flag and the rewrite together (case-insensitive \\b with groups)"
ok=true; why=""
for m in native ltgt class; do
    v=MODE_OK_$m; (( ${!v} )) || continue
    _mode "$m"
    TRegEx.match "THE Cat" '\b(c)(a)t\b' i; rc=$?
    [[ $rc == 0 && "$RESULT" == Cat && "${RESULT_GROUPS[*]}" == "C a" ]] || { ok=false; why+=" [$m rc=$rc R=$RESULT g=(${RESULT_GROUPS[*]})]"; }
done
$ok && kt_test_pass "groups C a" || kt_test_fail "$why"

unset KCL_TREGEX_WB; TRegEx._wbReset

kt_test_log "015_WordEdges.sh completed"
