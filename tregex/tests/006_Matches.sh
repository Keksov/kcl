#!/bin/bash
# 006_Matches.sh - TRegEx.matches: global leftmost-longest scan -> count in
# RESULT + lossless nameref array of match texts (+ optional offsets); empty-
# match advance-by-one (.NET parity), greedy, no-match, invalid, i-flag, the
# anchor caveat (^ $ \b re-anchor per remainder), direct-call-required, torture.
# Basis: DocWiki TRegEx.Matches + .NET Regex.Matches empty-match rule + P0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "006: TRegEx.matches"

# marr <name> <text> <re> <expCount> <expJoined(space)> [flags]
marr() {
    kt_test_start "$1"
    local -a arr=()
    TRegEx.matches "$2" "$3" arr "-" "${6:-}"
    if [[ "$RESULT" == "$4" && "${arr[*]}" == "$5" ]]; then
        kt_test_pass "count=$RESULT [${arr[*]}]"
    else
        kt_test_fail "count=$RESULT [${arr[*]}] ; want $4 [$5]"
    fi
}

# --- basic global scan ---
marr "digits"          "a1b2c3" "[0-9]"  3 "1 2 3"
marr "words"           "the cat sat" "[a-z]+" 3 "the cat sat"
marr "greedy one run"  "aaa"    "a+"     1 "aaa"
marr "no match"        "xyz"    "[0-9]"  0 ""

# --- empty-match advance-by-one (.NET parity) ---
marr "empty-match x* over abc" "abc" "x*" 4 "   "   # 4 empty pieces -> 3 spaces
marr "empty+nonempty y* "  "aYYb" "Y*" 4 " YY  "    # ''@0 'YY'@1 ''@3 ''@4

# --- rc semantics: 0 found / 1 none / 2 invalid ---
kt_test_start "rc: found=0, none=1, invalid=2"
a1=(); TRegEx.matches "a1" "[0-9]" a1; r0=$?
TRegEx.matches "aa" "[0-9]" a1; r1=$?
TRegEx.matches "aa" "[" a1; r2=$?
[[ "$r0" == "0" && "$r1" == "1" && "$r2" == "2" ]] && kt_test_pass "0/1/2" || kt_test_fail "got $r0/$r1/$r2"

# --- offsets fill (absolute, prefix-strip units) ---
kt_test_start "offsets array: absolute positions"
T=(); O=()
TRegEx.matches "a1b22c333" "[0-9]+" T O
if [[ "${T[*]}" == "1 22 333" && "${O[*]}" == "1 3 6" ]]; then
    kt_test_pass "texts=[${T[*]}] offs=[${O[*]}]"
else
    kt_test_fail "texts=[${T[*]}] offs=[${O[*]}] ; want [1 22 333] [1 3 6]"
fi

# --- flags: '-' placeholder lets i-flag be passed without offsets ---
marr "i-flag counts case-insensitively" "aAaB" "a" 3 "a A a" "i"

# --- anchor CAVEAT: ^ re-anchors to each remainder (documented delta) ---
# '^.' on "abc": matches "a"@0, then remainder "bc" re-anchors -> "b", then "c".
kt_test_start "anchor caveat: ^. re-anchors per remainder (delta)"
AC=()
TRegEx.matches "abc" "^." AC
[[ "$RESULT" == "3" && "${AC[*]}" == "a b c" ]] && kt_test_pass "remainder-relative ^ -> [${AC[*]}]" \
    || kt_test_fail "got count=$RESULT [${AC[*]}]"

# --- direct-call-required: $() subshell discards the nameref fill ---
kt_test_start "matches under \$(): silent + parent array NOT filled"
Q=(sentinel)
out="$(TRegEx.matches "a1b2" "[0-9]" Q)"
[[ -z "$out" && "${Q[*]}" == "sentinel" ]] && kt_test_pass "\$() empty, Q unchanged" \
    || kt_test_fail "leak: out='$out' Q=[${Q[*]}]"

# --- torture subjects ---
marr "newline-separated"  $'a\nb\nc' "[a-z]" 3 "a b c"
marr "quotes in subject"  'say "hi" "yo"' "\"[a-z]+\"" 2 "\"hi\" \"yo\""
marr "unicode tokens"     "café thé" "[a-zé]+" 2 "café thé"
kt_test_start "empty subject -> 0 (non-empty-match re) / 1 (empty-match re)"
E1=(); E2=()
TRegEx.matches "" "a" E1; c1=$RESULT
TRegEx.matches "" "a*" E2; c2=$RESULT
[[ "$c1" == "0" && "$c2" == "1" ]] && kt_test_pass "0 and 1" || kt_test_fail "got $c1 / $c2"

# --- zero-fork ---
kt_test_start "PATH='' : matches needs no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
    z=(); TRegEx.matches "p1q2r3" "[0-9]" z
    printf '%s:%s' "$RESULT" "${z[*]}"
)"
[[ "$zf" == "3:1 2 3" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "006_Matches.sh completed"
