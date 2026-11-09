#!/usr/bin/env bash
# 011_Locale.sh - the locale (D11) and the text a write stores:
#   * loading is silent in a C caller, with no locale variable, and while
#     probing bad candidate names;
#   * a C (non-UTF-8) caller: each entry point runs in the cached UTF-8
#     locale (Cyrillic and box drawing take one cell each) and the caller's
#     locale is back after the call;
#   * no UTF-8 locale at all (the candidate list stubbed to none): ASCII
#     mode, one '?' per UTF-8 sequence, box drawing / arrows / square mapped;
#     FV_ASCII=1 forces the same in a UTF-8 caller;
#   * every C0, DEL and C1 character becomes '?' in both modes, so the
#     continuation placeholder $'\x01' can never be stored; the per-row wide
#     flag is 0.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: locale, ASCII mode, control characters"

UNIT="$FVV_TESTS_DIR/../fv.video.sh"
check() {
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
# child SETUP BODY — BODY after SETUP and the unit in a fresh bash, stderr kept
child() {
    "$BASH" -c "unset LC_ALL LC_CTYPE LANG
$1
source '$UNIT'
FV_SCREEN_W=\${W:-40} FV_SCREEN_H=2
$2" 2>&1
}

r=$(child 'export LC_ALL=C' ':')
r+=$(child '' ':')
r+=$(child 'export LC_ALL=C' "__FV_VS_LOCS=(xx_YY.UTF-8 zz.utf8 C.UTF-8); fv.video._findloc; printf %s \"\$__FV_VS_LOC\"")
check "loading is silent (C caller, no locale variable); probing bad names is silent" "C.UTF-8" "$r"
r=$(child '' "printf '%s %s' \"\${LC_CTYPE-unset}\" \"\${LC_ALL-unset}\"")
check "no locale variable at all: the kcl-wide LC_CTYPE=C.UTF-8 at load (README §1.6)" "C.UTF-8 unset" "$r"

# --- a C caller -------------------------------------------------------------------
r=$(child 'export LC_ALL=C' "
p=\$'\\xd0\\xb6'
fv.video.initScreen; s=\"\$FV_VIDEO_ASCII \${#p} \"
fv.video.writeStr 1 0 'жук─┐' 7; s+=\"\$RESULT \${#p} \"
fv.video.strWidth 'ёж'; s+=\"\$RESULT \${#p} \$LC_ALL \"
printf '%s[%s|%s]' \"\$s\" \"\${__FV_VS_CH[0]}\" \"\${__FV_VS_AT[0]}\"")
printf -v pad '%34s' ''
check "a C caller: UTF-8 semantics inside each call (one cell per character), the caller's C locale back" \
    "0 2 5 2 2 2 C [ жук─┐$pad|077777${pad// /0}]" "$r"

# --- ASCII mode -------------------------------------------------------------------
text='┌─┐│└┘ ╔═╗║╚╝ ├┼┤ ╭╮ ╱ ━┃ ┄┆ ╴╵ ↑▲↓▼→►←◄■ жé漢😀 x'
want='+-+|++ +=+|++ +++ ++ ? -| -| -| ^^vv>><<* ???? x'
r=$(child 'export LC_ALL=C W=60' "__FV_VS_LOCS=(); fv.video._findloc
fv.video.initScreen; printf '%s %s ' \"\$FV_VIDEO_ASCII\" \"\${__FV_VS_LOC:-none}\"
fv.video.writeStr 0 0 '$text' 1; printf '%s ' \"\$RESULT\"
printf '[%s]' \"\${__FV_VS_CH[0]:0:${#want}}\"")
check "no UTF-8 locale (candidates stubbed to none), C caller: ASCII mode, the maps, one '?' per sequence" \
    "1 none ${#want} [$want]" "$r"
r=$(child 'export LC_ALL=C' "__FV_VS_LOCS=(); fv.video._findloc; fv.video.initScreen
fv.video.writeStr 0 0 \$'a\\x80b\\xe2\\x94c\\xf0\\x9f\\x98\\x80d\\xc3' 1; printf '%s ' \"\$RESULT\"
fv.video.strWidth \$'\\xd0\\xb6\\xd0\\xb6'; printf '%s ' \"\$RESULT\"
fv.video.writeChar 0 1 '─' 1 3; fv.video.fillRect 3 1 2 1 1 '║'
printf '[%s][%s]' \"\${__FV_VS_CH[0]:0:10}\" \"\${__FV_VS_CH[1]:0:6}\"")
check "ASCII mode: a stray continuation byte, a cut sequence and a trailing lead byte are one '?' each; writeChar / fillRect map CH" \
    "8 2 [a?b?c?d?  ][---|| ]" "$r"
r=$(child 'export LC_ALL=C.UTF-8 FV_ASCII=1 W=60' "fv.video.initScreen; printf '%s ' \"\$FV_VIDEO_ASCII\"
fv.video.writeStr 0 0 '$text' 1; printf '%s ' \"\$RESULT\"; printf '[%s]' \"\${__FV_VS_CH[0]:0:${#want}}\"")
check "FV_ASCII=1 forces ASCII mode in a UTF-8 caller (per character)" "1 ${#want} [$want]" "$r"
r=$(child 'export LC_ALL=C.UTF-8 FV_ASCII=1' "W=6; fv.video.initScreen; exec {fd}>'$FVV_TMP/ascii.out'; FV_VIDEO_OUT_FD=\$fd
fv.video.writeStr 0 0 '═ж' 1; fv.video.updateScreen; exec {fd}>&-; LC_ALL=C; IFS= read -r -d '' o < '$FVV_TMP/ascii.out'
[[ \$o == *[![:ascii:]]* ]] && printf non-ascii; [[ \$o == *'=?'* ]] && printf ok")
check "ASCII mode: the frame is pure ASCII" "ok" "$r"

# --- control characters -----------------------------------------------------------
for setup in 'export LC_ALL=C.UTF-8' 'export LC_ALL=C' 'export LC_ALL=C; __FV_VS_LOCS=()'; do
    r=$(child "$setup" "fv.video._findloc || :; fv.video.initScreen
c=\$'a\\x01b\\x1bc\\td\\ne\\x7ff\\xc2\\x85g\\xc2\\x9fh\\x7f'
fv.video.writeStr 0 0 \"\$c\" 1; printf '%s ' \"\$RESULT\"
fv.video.writeBuf 0 1 \$'\\x01\\x01' 12; printf '%s ' \"\$RESULT\"
fv.video.strWidth \"\$c\"; printf '%s ' \"\$RESULT\"
[[ \${__FV_VS_CH[*]} == *\$'\\x01'* ]] && printf HAS-CONT
printf '[%s][%s] %s' \"\${__FV_VS_CH[0]:0:16}\" \"\${__FV_VS_CH[1]:0:2}\" \"\${__FV_VS_WIDE[*]}\"")
    check "C0, DEL and C1 -> '?', never the placeholder \\x01 ($setup)" "16 2 16 [a?b?c?d?e?f?g?h?][??] 0 0" "$r"
done
check "the reserved continuation placeholder is \\x01" "01" "$(printf '%02x' "'$__FV_VS_CONT")"

# --- invalid UTF-8 and characters past U+FFFF (UTF-8 mode) -------------------------
E1=$'\xcc\x81'                        # U+0301, a combining mark
# a lone \xff, a cut sequence (e2 94 then 'a'), a raw 0x9b, an overlong c0 80,
# a surrogate ed a0 80, a 4-byte emoji, the highest 4-byte f4 8f bf bf: one
# '?' each; valid 2- and 3-byte characters and a combining mark are kept
for setup in 'export LC_ALL=C.UTF-8' 'export LC_ALL=C' 'export LC_ALL=C.UTF-8; shopt -u globasciiranges'; do
    r=$(child "$setup" "fv.video.initScreen
t=\$'<\\xff|\\xe2\\x94a|\\x9b|\\xc0\\x80|\\xed\\xa0\\x80|\\xf0\\x9f\\x98\\x80|\\xf4\\x8f\\xbf\\xbf|\\xd0\\xb6\\xe2\\x94\\x80e\\xcc\\x81|\\xc3\\xa9\\xc2\\x85\\xc3\\x80>'
fv.video.writeStr 0 0 \"\$t\" 1; printf '%s ' \"\$RESULT\"
fv.video.strWidth \"\$t\"; printf '%s ' \"\$RESULT\"
LC_ALL=C.UTF-8; printf '[%s]' \"\${__FV_VS_CH[0]:0:25}\"")
    check "invalid, cut, overlong, surrogate and 4-byte sequences -> one '?' each; valid text kept ($setup)" \
        "25 25 [<?|?a|?|?|?|?|?|ж─e${E1}|é?À>]" "$r"
done

# glibc collates bracket ranges by locale when globasciiranges is off: the C1
# check works on bytes, so letters near U+0080-009F (é À ÿ Ā) are never hit
kt_test_start "en_US.UTF-8 with globasciiranges off: only C1 becomes '?', the Latin letters around it stay"
if [[ $("$BASH" -c 'export LC_ALL=en_US.UTF-8; p=$'"'"'\xd0\xb6'"'"'; printf %s ${#p}' 2>&1) == 1 ]]; then
    r=$(child 'export LC_ALL=en_US.UTF-8; shopt -u globasciiranges' "fv.video.initScreen
t=\$'\\xc2\\x80a\\xc3\\xa9\\xc3\\x80\\xc3\\xbf\\xc4\\x80\\xc2\\x9fz\\xc2\\xa0'
fv.video.writeStr 0 0 \"\$t\" 1; printf '%s [%s]' \"\$RESULT\" \"\${__FV_VS_CH[0]:0:9}\"")
    if [[ $r == "9 [?aéÀÿĀ?z"$'\xc2\xa0'"]" ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
else
    kt_test_pass "SKIP: ENV: no en_US.UTF-8 here (the collation case needs glibc; the lab VM runs it)"
fi

kt_test_start "a long Cyrillic and box-drawing row stays as it is (the valid-text fast path)"
r=$(child 'export LC_ALL=C.UTF-8' "W=60; fv.video.initScreen
t='╔══ Привет, мир! Ёлка ══╗ │ данные │'
fv.video.writeStr 0 0 \"\$t\" 1; (( RESULT == \${#t} )) && printf 'n-ok '
[[ \${__FV_VS_CH[0]} == \"\$t\"* ]] && printf same")
if [[ $r == 'n-ok same' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

r=$(child 'export LC_ALL=C.UTF-8' "fv.video.initScreen
fv.video.writeStr 0 0 '═ж' 1; a=\${__FV_VS_CH[0]:0:2}
FV_ASCII=1 fv.video.initScreen; fv.video.writeStr 0 0 '═ж' 1; b=\${__FV_VS_CH[0]:0:2}
unset FV_ASCII; fv.video.initScreen; fv.video.writeStr 0 0 '═ж' 1; c=\${__FV_VS_CH[0]:0:2}
for (( i = 0; i < 600; i++ )); do fv.video.strWidth \"ж\$i\"; done
printf '%s %s %s %s' \"\$a\" \"\$b\" \"\$c\" \$(( \${#__FV_VS_TC[@]} <= 512 ))")
check "the text cache: a mode change (initScreen) empties it; it never holds more than 512 texts" "═ж =? ═ж 1" "$r"

# --- the locale probes --------------------------------------------------------------
# legacy CJK locales (eucJP, GBK, Big5, eucKR) count the 2-byte ж as one
# character; only the 3-byte ─ tells them from UTF-8. Cygwin-based runtimes
# ship them; on others they are tried when installed.
kt_test_start "a legacy CJK caller locale (\${#ж} = 1, \${#─} != 1) is not taken for UTF-8: the call runs in the UTF-8 locale"
done1='' notes=''
for loc in ja_JP.eucJP zh_CN.GBK zh_TW.Big5 ko_KR.eucKR; do
    probe=$("$BASH" -c "export LC_ALL=$loc; p=\$'\\xd0\\xb6' b=\$'\\xe2\\x94\\x80'; printf '%s/%s' \${#p} \${#b}" 2>/dev/null)
    if [[ $probe != 1/1 && $probe == 1/* ]]; then
        r=$(child "export LC_ALL=$loc" "fv.video.initScreen; printf '%s ' \"\$FV_VIDEO_ASCII\"
fv.video.writeStr 0 0 'жук─┐' 1; printf '%s %s ' \"\$RESULT\" \"\$LC_ALL\"
LC_ALL=C.UTF-8; printf '[%s]' \"\${__FV_VS_CH[0]:0:6}\"")
        if [[ $r != "0 5 $loc [жук─┐ ]" ]]; then notes+=" $loc:[$r]"; fi
        done1+=" $loc"
    fi
done
if [[ -n $notes ]]; then kt_test_fail "$notes"
elif [[ -n $done1 ]]; then kt_test_pass "checked:$done1"
else kt_test_pass "no legacy CJK locale that fools the 2-byte probe is installed here; the 3-byte probe is what rejects them (Cygwin-based runtimes test it for real)"; fi

r=$(child 'export LC_ALL=C.UTF-8' "__FV_VS_LOCS=(); fv.video._findloc; printf '%s ' \"\$__FV_VS_LOC\"
LC_ALL=C fv.video.initScreen; printf '%s ' \"\$FV_VIDEO_ASCII\"
LC_ALL=C fv.video.strWidth 'жук'; printf '%s' \"\$RESULT\"")
check "no fixed candidate: the caller's own UTF-8 locale (here C.UTF-8) is recorded at load and used for a later C call" "C.UTF-8 0 3" "$r"

kt_test_log "011_Locale.sh completed"
