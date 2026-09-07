#!/bin/bash
# 063_TSH04_Locale.sh — finding TSH-04 (X-LOCALE) and decision D6.
#
# TStringHelper's whole API is defined on CHARACTERS: `length`, `chars`,
# `substring`, `indexOf`, `padLeft`, `toLower` all count and slice characters,
# and docs/TStringHelper.md documents 0-based *character* indexing. bash gives
# character semantics only in a multi-byte locale: with LANG/LC_ALL/LC_CTYPE
# unset the shell runs in C, where `${#s}` counts BYTES, `${s:i:1}` cuts a lone
# byte out of a multi-byte character and `${s,,}` corrupts UTF-8 on 5.2
# (`ÄÖ` -> two replacement bytes). The review found the whole corpus running
# that way: `length 日本` answered 6, `indexOf 'мир' 'р'` answered 4.
#
# D6: the test runners pin LC_ALL=C.UTF-8 (ktests/ktest.sh) and every unit
# self-heals a BARE environment at load time (kcl/README.md 1.6). This file
# pins both halves, and — the gap the review named — puts non-ASCII BEFORE the
# searched character in every member that counts or slices, so a byte-counting
# regression cannot hide behind an ASCII prefix.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TSH04_Locale" "$SCRIPT_DIR" "$@"

UNIT="$SCRIPT_DIR/../tstringhelper.sh"
source "$UNIT"

# --- 1. the unit self-heals a bare environment (D6) -------------------------
kt_test_start "the unit exports a UTF-8 LC_CTYPE into a bare environment [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
string.length '日本'
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\$RESULT\"" 2>&1)"
if [[ "$out" == "C.UTF-8|2" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|2'"
fi

kt_test_start "the self-heal does not override an explicit locale [D6]"
out="$(env -u LC_CTYPE -u LANG bash -c "
export LC_ALL=C.UTF-8
source '$UNIT'
printf '%s' \"\${LC_CTYPE:-unset}\"" 2>&1)"
if [[ "$out" == "unset" ]]; then
    kt_test_pass "LC_CTYPE left alone when LC_ALL is set"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "case conversion is not corrupted in a bare environment [TSH-04]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
string.toLower 'ÄÖ'; printf '%s ' \"\$RESULT\"
string.toUpper 'café'; printf '%s' \"\$RESULT\"" 2>&1)"
if [[ "$out" == "äö CAFÉ" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'äö CAFÉ'"
fi

# --- 2. non-ASCII BEFORE the searched character -----------------------------
# Every one of these answers differs between byte and character semantics.
eq() {   # TITLE EXPECTED MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$RESULT')"
    fi
}

eq "length counts characters, not bytes [TSH-04]"            "2"   string.length "日本"
eq "length of a Cyrillic word [TSH-04]"                      "3"   string.length "мир"
eq "indexOf: the separator after Cyrillic [TSH-04]"          "3"   string.indexOf "мир,дом" ","
eq "indexOf: an ASCII letter after Cyrillic [TSH-04]"        "4"   string.indexOf "мир dom" "d"
eq "indexOf: a Cyrillic letter after Cyrillic [TSH-04]"      "2"   string.indexOf "мир" "р"
eq "indexOfAny after Cyrillic [TSH-04]"                      "3"   string.indexOfAny "мир,дом" ",;"
eq "lastIndexOf after Cyrillic [TSH-04]"                     "7"   string.lastIndexOf "мир,дом,сад" ","
eq "lastIndexOfAny after Cyrillic [TSH-04]"                  "7"   string.lastIndexOfAny "мир,дом,сад" ",;"
eq "lastDelimiter after Cyrillic [TSH-04]"                   "7"   string.lastDelimiter "мир,дом,сад" ","
eq "chars indexes characters [TSH-04]"                       "и"   string.chars "мир" 1
eq "substring starts on a character boundary [TSH-04]"       "дом" string.substring "мир дом" 4
eq "substring length is in characters [TSH-04]"              "ир"  string.substring "мир" 1 2
eq "remove works in characters [TSH-04]"                     "дом" string.remove "мир дом" 0 4
eq "insert works in characters [TSH-04]"                     "мXир" string.insert "мир" 1 "X"
eq "countChar counts characters [TSH-04]"                    "2"   string.countChar "мир мир" "м"
eq "padLeft pads to a character width [TSH-04]"              "  мир" string.padLeft "мир" 5
eq "trim strips around non-ASCII [TSH-04]"                   "мир" string.trim "  мир  "
eq "replace after Cyrillic [TSH-04]"                         "мир+дом" string.replace "мир-дом" "-" "+"
eq "toCharArray splits into characters [TSH-04]"             $'м\nи\nр' string.toCharArray "мир"
eq "quotedString doubles the quote after Cyrillic [TSH-04]"  "'мир''дом'" string.quotedString "мир'дом"

kt_test_start "isDelimiter indexes characters [TSH-04]"
if string.isDelimiter "мир,дом" 3 "," >/dev/null 2>&1; then
    kt_test_pass "the comma at character index 3 is a delimiter"
else
    kt_test_fail "isDelimiter said no (RESULT='$RESULT')"
fi

kt_test_start "split works on characters [TSH-04]"
declare -a parts=()
string.split "мир,дом" "," parts >/dev/null 2>&1 || :
if [[ "$RESULT" == "2" && "${parts[0]}" == "мир" && "${parts[1]}" == "дом" ]]; then
    kt_test_pass "2 parts: мир / дом"
else
    kt_test_fail "RESULT='$RESULT' parts=(${parts[*]})"
fi

kt_test_start "getHashCode is defined on code points, not bytes [TSH-19]"
# Documented deviation: FPC's fphash runs over BYTES, this port over code
# points, so the two agree on ASCII and differ on anything else. What must
# hold here is that the answer does not depend on how many bytes the
# characters occupy - the same text always hashes the same, and one
# character is one round of the hash.
string.getHashCode "мир" >/dev/null 2>&1 || :
h1="$RESULT"
string.getHashCode "мир" >/dev/null 2>&1 || :
h2="$RESULT"
string.getHashCode "ми" >/dev/null 2>&1 || :
h3="$RESULT"
if [[ "$h1" == "$h2" && "$h1" != "$h3" && "$h1" =~ ^-?[0-9]+$ ]]; then
    kt_test_pass "stable ($h1) and character-sensitive"
else
    kt_test_fail "h(мир)=$h1 h(мир)=$h2 h(ми)=$h3"
fi
