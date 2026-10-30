#!/usr/bin/env bash
# P7 — the two documentation defects that were also behaviour claims.
#
#   T3 (X-LOCALE)  `tregex.sh` S9 and `docs/ERE-vs-PCRE.md` §5 claimed that
#       under an empty/C locale bash `${#}` byte-counts "while the regex engine
#       char-counts". Both byte-count: `TRegEx.match "héllo wörld" "w.rld"`
#       MISSES under LC_ALL=C and matches under C.UTF-8. The unit therefore
#       self-heals a bare environment (D6) and the docs say what happens.
#
#   T4 / R12 (anchored zero-length)  the S6 note claimed "match CORRECTNESS is
#       unaffected — only the reported numeric index". It is not: a zero-length
#       match carries NO position information through prefix-strip
#       (`${rem%%""*}` is always ''), so `$`, `\b`, `\<`, `\>` and `^` report
#       offset 0 in every remainder and the scan yields len+1 matches.
#       R12: pin the real behaviour now and fix the docs; detection is not
#       trivial (bash exposes no match offset), so it stays a documented delta.
#
# Every row below is what the unit ACTUALLY does, with the .NET answer named in
# the message, so the delta is visible in the test output and not only in prose.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
UNIT="$SCRIPT_DIR/../tregex.sh"
source "$UNIT"

kt_test_init "T3T4LocaleAndAnchors" "$SCRIPT_DIR" "$@"
kt_test_section "011: locale semantics (T3) and anchored zero-length scans (T4/R12)"

# platform probe (launch L3.5-b): how this C library's ERE treats \b
__re='\b'; TRE_WB=0; [[ x =~ $__re ]] 2>/dev/null && TRE_WB=1          # 0: FreeBSD/macOS libc reject \b
TRE_WB_END=0; (( TRE_WB )) && [[ '' =~ $__re ]] && TRE_WB_END=1        # 1: musl matches \b on ''

# ---------------------------------------------------------------------------
# 1. T3 — `.` over a multibyte character, under both locales, in a CHILD shell
#    (the runner pins LC_ALL=C.UTF-8, so the C case has to be constructed).
# ---------------------------------------------------------------------------
_locale_probe() {   # TITLE  ENV  EXPECT-rc|match|index|length
    kt_test_start "$1 [T3]"
    local out
    out="$(bash -c "$2
source '$UNIT'
TRegEx.match 'héllo wörld' 'w.rld'; rc=\$?
printf '%s|%s|%s|%s' \"\$rc\" \"\$RESULT\" \"\$RESULT_INDEX\" \"\$RESULT_LENGTH\"" 2>&1)"
    if [[ "$out" == "$3" ]]; then kt_test_pass "$out"; else kt_test_fail "got '$out' want '$3'"; fi
}
# A full UTF-8 locale: `.` is one CHARACTER, ${#} counts characters.
_locale_probe "under LC_ALL=C.UTF-8 '.' matches one multibyte character" \
    "export LC_ALL=C.UTF-8" "0|wörld|6|5"
# The C locale: the engine matches BYTES, so `w.rld` cannot cover w + 2 bytes.
_locale_probe "under LC_ALL=C the engine matches BYTES and w.rld MISSES" \
    "export LC_ALL=C; unset LC_CTYPE LANG" "1||-1|0"
# ... and the two-dot form does match there, which is what "bytes" means.
kt_test_start "under LC_ALL=C 'w..rld' matches the same text (byte semantics) [T3]"
out="$(bash -c "export LC_ALL=C; unset LC_CTYPE LANG
source '$UNIT'
TRegEx.match 'héllo wörld' 'w..rld'; printf '%s|%s|%s' \"\$?\" \"\$RESULT\" \"\$RESULT_LENGTH\"" 2>&1)"
[[ "$out" == "0|wörld|6" ]] && kt_test_pass "$out" || kt_test_fail "got '$out' want '0|wörld|6'"

kt_test_start "an empty environment self-heals to a UTF-8 ctype [T3, D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG -u LC_COLLATE bash -c "
source '$UNIT'
TRegEx.match 'héllo wörld' 'w.rld'; printf '%s|%s|%s|%s' \"\$?\" \"\$RESULT\" \"\$RESULT_INDEX\" \"\$LC_CTYPE\"" 2>&1)"
if [[ "$out" == "0|wörld|6|C.UTF-8" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out' want '0|wörld|6|C.UTF-8'"
fi

kt_test_start "the unit does not override a locale the caller chose [T3, D6]"
out="$(env -u LC_CTYPE -u LANG bash -c "export LC_ALL=C
source '$UNIT'
printf '%s|%s' \"\$LC_ALL\" \"\${LC_CTYPE:-unset}\"" 2>&1)"
[[ "$out" == "C|unset" ]] && kt_test_pass "$out" || kt_test_fail "got '$out'"

kt_test_start "offsets and lengths are CHARACTERS under a UTF-8 locale [T3]"
ok=true; why=""
TRegEx.match "αβγdef" "def"
[[ "$RESULT_INDEX" == 3 && "$RESULT_LENGTH" == 3 ]] || { ok=false; why+=" [idx=$RESULT_INDEX len=$RESULT_LENGTH want 3/3]"; }
o=(); a=(); TRegEx.matches "αXβXγ" "X" a o
[[ "$RESULT" == 2 && "${o[*]}" == "1 3" ]] || { ok=false; why+=" [matches n=$RESULT offs='${o[*]}' want 2 / '1 3']"; }
$ok && kt_test_pass "character offsets" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 2. T4 / R12 — the anchored zero-length scans, pinned exactly as they behave.
# ---------------------------------------------------------------------------
_scan() {   # PATTERN TEXT EXPECT-n EXPECT-offsets DOTNET-NOTE
    kt_test_start "matches($2, $1) = $3 matches at [$4]; .NET: $5 [T4/R12]"
    local a=() o=()
    TRegEx.matches "$2" "$1" a o
    if [[ "$RESULT" == "$3" && "${o[*]}" == "$4" ]]; then
        kt_test_pass "n=$RESULT offs=${o[*]}"
    else
        kt_test_fail "n=$RESULT offs='${o[*]}' want n=$3 offs='$4'"
    fi
}
# Every match is EMPTY, and prefix-strip of an empty string is always '' — so
# every reported offset is the head of its remainder, and the scan walks the
# whole string one character at a time.
_scan '$'  "abc"   4 "0 1 2 3" "1 match at 3"
_scan '^'  "abc"   4 "0 1 2 3" "1 match at 0"
if (( ! TRE_WB )); then
    kt_test_start "matches(ab cd, \b) = 5 matches at [0 1 2 3 4]; .NET: 4 matches at 0,2,3,5 [T4/R12]"
    kt_test_pass "N/A: this C library's ERE has no \b (rc 2); use \< \>"
elif (( TRE_WB_END )); then   # musl also matches \b on the empty remainder: one more offset
    _scan '\b' "ab cd" 6 "0 1 2 3 4 5" "4 matches at 0,2,3,5"
else
    _scan '\b' "ab cd" 5 "0 1 2 3 4" "4 matches at 0,2,3,5"
fi
_scan '\<' "ab cd" 5 "0 1 2 3 4" "2 matches at 0,3"
_scan '\>' "ab cd" 5 "0 1 2 3 4" "2 matches at 2,5"
# An UNANCHORED empty-match pattern is exact — the empty match really is at the
# head of each remainder. This is the line that separates T4 from normal use.
_scan 'x*' "abc"   4 "0 1 2 3" "4 matches at 0,1,2,3 (agrees)"

kt_test_start "replace with an anchored zero-length pattern [T4/R12]"
ok=true; why=""
_rep() {   # TEXT PATTERN REPL EXPECT DOTNET
    local r; TRegEx.replace "$1" "$2" "$3" >/dev/null; r="$RESULT"
    [[ "$r" == "$4" ]] || { ok=false; why+=" [replace($1,$2,$3)='$r' want '$4']"; }
}
_rep "abc"   '$'  "!" "!a!b!c!" "abc!"
_rep "abc"   '^'  ">" ">a>b>c>" ">abc"
if (( TRE_WB_END )); then _rep "ab cd" '\b' "|" "|a|b| |c|d|" "|ab| |cd|"
elif (( TRE_WB )); then _rep "ab cd" '\b' "|" "|a|b| |c|d" "|ab| |cd|"
fi   # TRE_WB=0: not called (rc 2)
_rep "abc"   'x*' "-" "-a-b-c-"   "-a-b-c- (agrees)"
$ok && kt_test_pass "4 rows pinned" || kt_test_fail "$why"

kt_test_start "split with an anchored zero-length pattern [T4/R12]"
ok=true; why=""
p=(); TRegEx.split "abc" '$' p
[[ "$(printf '[%s]' "${p[@]}")" == "[][a][b][c][]" ]] || { ok=false; why+=" [split \$ -> $(printf '[%s]' "${p[@]}")]"; }
if (( TRE_WB )); then
    want_wb="[][a][b][ ][c][d]"; (( TRE_WB_END )) && want_wb="[][a][b][ ][c][d][]"
    p=(); TRegEx.split "ab cd" '\b' p
    [[ "$(printf '[%s]' "${p[@]}")" == "$want_wb" ]] || { ok=false; why+=" [split \\b -> $(printf '[%s]' "${p[@]}") want $want_wb]"; }
fi   # TRE_WB=0: not checked (rc 2)
$ok && kt_test_pass "pinned" || kt_test_fail "$why"

kt_test_start "the S6 offset caveat: an anchored match whose text recurs earlier [T4]"
# `match` (single, not a scan) with `$`-anchored text that also occurs earlier:
# prefix-strip reports the EARLIER position. This is the original S6 caveat and
# it is still true; the point of the row is that the value is pinned, not prose.
TRegEx.match "ab ab" 'ab$'
if [[ "$RESULT" == "ab" && "$RESULT_INDEX" == 0 ]]; then
    kt_test_pass "index 0 (the true match is at 3) — prefix-strip caveat pinned"
else
    kt_test_fail "RESULT='$RESULT' index=$RESULT_INDEX"
fi

kt_test_start "unanchored patterns report EXACT offsets [T4, the other half]"
ok=true; why=""
TRegEx.match "xxabcxx" "abc"; [[ "$RESULT_INDEX" == 2 ]] || { ok=false; why+=" [abc idx=$RESULT_INDEX]"; }
a=(); o=(); TRegEx.matches "a1b22c333" "[0-9]+" a o
[[ "$RESULT" == 3 && "${o[*]}" == "1 3 6" ]] || { ok=false; why+=" [n=$RESULT offs='${o[*]}']"; }
a=(); o=(); TRegEx.matches "aaa" "a" a o
[[ "${o[*]}" == "0 1 2" ]] || { ok=false; why+=" [aaa offs='${o[*]}']"; }
$ok && kt_test_pass "exact for the unanchored majority" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 3. The documentation itself: the two false claims must be gone.
# ---------------------------------------------------------------------------
kt_test_start "the S6 header note no longer claims correctness is unaffected [T4]"
if grep -q "CORRECTNESS is unaffected" "$UNIT"; then
    kt_test_fail "tregex.sh still says 'match CORRECTNESS is unaffected'"
else
    kt_test_pass "claim removed"
fi

kt_test_start "the S9 header note says the ENGINE byte-matches under C [T3]"
# The old text claimed bash byte-counts "while the regex engine char-counts",
# i.e. that only the reported number was affected. Both byte-count, and the
# match itself changes. Assert the corrected statement is present in both
# places, not merely that the old wording is gone.
ok=true; why=""
grep -q "matches BYTES" "$UNIT" || { ok=false; why+=" [tregex.sh S9]"; }
grep -q "matches BYTES" "$SCRIPT_DIR/../docs/ERE-vs-PCRE.md" || { ok=false; why+=" [docs/ERE-vs-PCRE.md §5]"; }
grep -q "char-counts" "$UNIT" && { ok=false; why+=" [tregex.sh still says char-counts]"; }
$ok && kt_test_pass "both say the engine matches bytes under C" || kt_test_fail "missing:$why"

kt_test_start "docs and README name the zero-length anchor delta [T4/R12]"
ok=true; why=""
grep -q "zero-length" "$SCRIPT_DIR/../docs/ERE-vs-PCRE.md" || { ok=false; why+=" [ERE-vs-PCRE.md]"; }
grep -q "zero-length" "$SCRIPT_DIR/../README.md" || { ok=false; why+=" [README.md]"; }
$ok && kt_test_pass "documented in both" || kt_test_fail "missing in:$why"

kt_test_log "011_T3_T4_LocaleAndAnchors.sh completed"
