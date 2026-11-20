#!/usr/bin/env bash
# 003_Utf8.sh - printable characters: UTF-8 of 2, 3 and 4 bytes (Cyrillic,
# CJK, emoji) assembled byte by byte, the same in a C-locale caller, Alt + a
# UTF-8 character, a Cyrillic word typed in one chunk, and the malformed
# cases: a bad lead byte, a lone continuation byte, a character cut short by
# the next key (the cutting byte is NOT eaten) or by the end of the input.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: UTF-8 characters"

fvk_chk 'é' kbChar 'é' 'Latin-1 supplement, 2 bytes'
fvk_chk 'ж' kbChar 'ж' 'Cyrillic, 2 bytes'
fvk_chk 'Ё' kbChar 'Ё' 'Cyrillic capital, 2 bytes'
fvk_chk '€' kbChar '€' '3 bytes'
fvk_chk '中' kbChar '中' 'CJK, 3 bytes'
fvk_chk '│' kbChar '│' 'box drawing, 3 bytes'
fvk_chk $'\xf0\x9f\x98\x80' kbChar $'\xf0\x9f\x98\x80' 'emoji U+1F600, 4 bytes'
fvk_chk $'\xf4\x8f\xbf\xbf' kbChar $'\xf4\x8f\xbf\xbf' 'U+10FFFF, 4 bytes'
fvk_chk $'\eж' kbAltSemiCol 'ж' 'Alt + Cyrillic: the ; key of the Russian layout (the P3 3L tables)'
fvk_chk $'\eé' kbAltChar 'é' 'Alt + a character in no default table'
fvk_chk $'\e\xf0\x9f\x98\x80' kbAltChar $'\xf0\x9f\x98\x80' 'Alt + emoji'

# the same characters decoded by a caller in the C locale (the unit pins its
# own byte semantics; the caller's locale must not matter)
kt_test_start "a C-locale caller gets the same answers (ж, €, emoji, Alt+ж)"
got=$(
    export LC_ALL=C
    for s in 'ж' '€' $'\xf0\x9f\x98\x80' $'\eж'; do
        fv.keyboard.decode "$s" >/dev/null
        printf '%s:%s:%s|' "$FV_KEY" "$FV_KEY_CHAR" "$FV_KEY_LEN"
    done
)
want="kbChar:ж:2|kbChar:€:3|kbChar:"$'\xf0\x9f\x98\x80'":4|kbAltSemiCol:ж:3|"
if [[ $got == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got '$got'"; fi

kt_test_start "a Cyrillic word with an emoji in one chunk decodes one character per key"
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed $'привет\xf0\x9f\x98\x80!'
fvk_keys got
if [[ $got == $'kbChar:п|kbChar:р|kbChar:и|kbChar:в|kbChar:е|kbChar:т|kbChar:\xf0\x9f\x98\x80|kbChar:!' ]]; then
    kt_test_pass "8 keys"
else
    kt_test_fail "$got"
fi

# --- malformed ------------------------------------------------------------------
fvk_chk $'\xff' kbUnknown '' 'not a UTF-8 byte'
fvk_chk $'\xc0' kbUnknown '' 'overlong lead C0'
fvk_chk $'\xf5' kbUnknown '' 'lead beyond U+10FFFF'
fvk_chk $'\x80' kbUnknown '' 'a lone continuation byte'
fvk_chk $'\xd0' kbUnknown '' 'a 2-byte lead and the end of the input'
fvk_chk $'\xe2\x82' kbUnknown '' 'a 3-byte character cut short'
fvk_chk $'\xf0\x9f\x98' kbUnknown '' 'a 4-byte character cut short'

kt_test_start "a character cut by the next key: kbUnknown for the lead, the next key intact"
fv.keyboard.flush
fv.keyboard.feed $'\xd0\e[Ax\xe2\x82\xd0\xb6'
fvk_keys got
if [[ $got == $'kbUnknown|kbUp|kbChar:x|kbUnknown|kbChar:ж' ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "$got"
fi

kt_test_start "the cut lead's FV_KEY_SEQ is that byte alone (1 byte)"
fv.keyboard.decode $'\xd0a'
fvk_len "$FV_KEY_SEQ"
if [[ $FV_KEY == kbUnknown && $FV_KEY_LEN == 1 && $REPLY == 1 && $FV_KEY_SEQ == $'\xd0' ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "key=$FV_KEY len=$FV_KEY_LEN"
fi

# --- strictness (fix round F6): overlong forms, surrogates, > U+10FFFF ---------------
# the bad second byte is left unread, so each byte after the lead is a key of its own
fvk_chk $'\xe0\xa0\x80' kbChar $'\xe0\xa0\x80' 'U+0800, the first 3-byte'
fvk_chk $'\xed\x9f\xbf' kbChar $'\xed\x9f\xbf' 'U+D7FF, below the surrogates'
fvk_chk $'\xee\x80\x80' kbChar $'\xee\x80\x80' 'U+E000, above the surrogates'
fvk_chk $'\xf0\x90\x80\x80' kbChar $'\xf0\x90\x80\x80' 'U+10000, the first 4-byte'
strict() {
    local v
    printf -v v '%q' "$1"
    kt_test_start "$v is not a character ($2): kbUnknown for the lead, the rest decoded after it"
    fv.keyboard.flush
    fv.keyboard.feed "$1x"
    fvk_keys got
    if [[ $got == "$3" ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi
}
strict $'\xe0\x80\x80' 'overlong U+0000' 'kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xe0\x9f\xbf' 'overlong U+07FF' 'kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xed\xa0\x80' 'surrogate U+D800' 'kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xed\xbf\xbf' 'surrogate U+DFFF' 'kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xf0\x80\x80\x80' 'overlong 4-byte' 'kbUnknown|kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xf0\x8f\xbf\xbf' 'overlong U+FFFF' 'kbUnknown|kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xf4\x90\x80\x80' 'U+110000' 'kbUnknown|kbUnknown|kbUnknown|kbUnknown|kbChar:x'
strict $'\xe2\x82\xff' 'a bad third byte' 'kbUnknown|kbUnknown|kbChar:x'

kt_test_start "ESC + a bad byte is a lone Esc; the byte is decoded next"
fv.keyboard.flush
fv.keyboard.feed $'\e\xffa'
fvk_keys got
if [[ $got == 'kbEsc|kbUnknown|kbChar:a' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi
exec {nullfd}<&-

kt_test_log "003_Utf8.sh completed"
