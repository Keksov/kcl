#!/usr/bin/env bash
# 012_Palette.sh - the app palette (design §1.9, R12):
#   * InitScreen: the app palette is CAppColor's default string; FV's
#     ErrorAttr gets the first free symbol (W, white on bright red), so an
#     index outside a palette resolves to it;
#   * fv.app.setAppPalette ENTRY FG BG [BOLD]: a symbol only that entry uses
#     is redefined in place; a shared one is left to the other entries and
#     the entry takes a symbol with the same colours (reuse) or a free one
#     (allocation, never 0, V or ErrorAttr's); every resolved palette dropped
#     and the application redrawn (the status line's cells take the new
#     symbol; == a full repaint); RESULT kept;
#   * all symbols in use: rc 1, one Error line, nothing changed (59 symbols
#     for the palette: 62 less 0, V and ErrorAttr's);
#   * refusals (rc 2), no screen (rc 1).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "012: the app palette"

# count SYM -> REPLY = how many entries of the app palette use SYM
count() { local i n=0; for (( i = 0; i < ${#__FV_VW_APAL}; i++ )); do [ "${__FV_VW_APAL:i:1}" = "$1" ] && n=$(( n + 1 )); done; REPLY=$n; }
distinct() { local -A u=(); local i; for (( i = 0; i < ${#__FV_VW_APAL}; i++ )); do u[${__FV_VW_APAL:i:1}]=1; done; REPLY=${#u[@]}; }

kt_test_start "InitScreen: CAppColor's string, ErrorAttr = W (15 on 9); an index outside a palette resolves to W"
fva_app
TView.new pv 0 0 1 1
fv.views.insert app__fvdesktop pv
fv.views.getColor pv 200; e=$RESULT
fv.views.getColor pv 1; o=$RESULT
r="$e|$o|$__FV_VW_ERRSYM|${__FV_VS_PAL[W]}"
pv.delete
[[ $__FV_VW_APAL == "$__FV_AP_DEFPAL" ]] && r+='|def'
if [[ $r == 'W|1|W|15 9 0|def' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "an entry whose symbol only it uses: redefined in place (the string unchanged, fv.video's colours changed); RESULT kept"
for (( u = 1; u <= 127; u++ )); do count "${__FV_VW_APAL:u-1:1}"; (( REPLY == 1 )) && break; done
s=${__FV_VW_APAL:u-1:1}
p0=$__FV_VW_APAL
RESULT=keep
fv.app.setAppPalette "$u" 200 17 1; rc=$?
r="$rc|$RESULT|${__FV_VS_PAL[$s]}"
[[ $__FV_VW_APAL == "$p0" ]] && r+='|same'
if [[ $r == '0|keep|200 17 1|same' ]]; then kt_test_pass "ok (entry $u, symbol $s)"; else kt_test_fail "[$r] entry $u symbol $s"; fi

kt_test_start "a shared entry with the colours of another symbol: that symbol reused (entry 1 <- 7's colours 1 2 0); the others sharing 1 keep it"
count 1; n1=$REPLY
fv.app.setAppPalette 1 1 2; rc=$?
count 1
r="$rc|${__FV_VW_APAL:0:1}|$(( n1 - REPLY ))|${__FV_VS_PAL[1]}"
if [[ $r == "0|7|1|${__FV_VS_PAL[1]}" && ${__FV_VS_PAL[1]} != '1 2 0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "a shared entry with new colours: a free symbol allocated (X: W is ErrorAttr's); the application redrawn: the status line's normal cells take it; == a full repaint"
fva_paint
fv.app.setAppPalette 2 9 4 0; rc=$?
s=${__FV_VW_APAL:1:1}
fv.video.getRow 23
r="$rc|$s|${__FV_VS_PAL[$s]}|${REPLY:7:4}"
if [[ $r == "0|X|9 4 0|XXXX" ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "all symbols in use: rc 1, one Error line, nothing changed (59 distinct symbols in the palette); 0, V and W never handed out"
k=0 rc=0
for (( e = 1; e <= 127; e++ )); do
    fv.app.setAppPalette "$e" "$(( (e * 3) % 256 ))" "$(( (e * 7 + 100) % 256 ))" 0 2>>"$FVW_TMP/e12"; rc=$?
    if (( rc )); then break; fi
    k=$(( k + 1 ))
done
p1=$__FV_VW_APAL
fv.app.setAppPalette "$e" 250 250 0 2>>"$FVW_TMP/e12"; rc2=$?
distinct; d=$REPLY
mapfile -t el < "$FVW_TMP/e12"
r="$rc|$rc2|$d|${#el[@]}"
[[ $p1 == "$__FV_VW_APAL" ]] && r+='|same'
[[ $__FV_VW_APAL != *[0VW]* ]] && r+='|nores'
if [[ $r == '1|1|59|2|same|nores' && ${el[0]} == 'Error: fv.app: setAppPalette: entry '*'every symbol of the pool is in use (59 for the palette)'* ]]; then kt_test_pass "ok (failed at entry $e after $k)"; else kt_test_fail "[$r] at $e [${el[*]}]"; fi
fva_unapp

kt_test_start "refusals: rc 2 for a bad call (count, entry 0 / 128 / x, fg 256, bold 2), RESULT ''; rc 1 without a screen"
fva_app
q=''
fv.app.setAppPalette 1 1 || q+="$?,"; fv.app.setAppPalette 0 1 1 || q+="$?,"; fv.app.setAppPalette 128 1 1 || q+="$?,"
fv.app.setAppPalette x 1 1 || q+="$?,"; fv.app.setAppPalette 1 256 1 || q+="$?,"; fv.app.setAppPalette 1 1 1 2 || q+="$?,"
q+="[$RESULT]"
fva_unapp
x=$("$BASH" -c "source '$FVA_TESTS_DIR/../fv.app.sh'; fv.app.setAppPalette 1 1 1; echo \$?")
if [[ $q == '2,2,2,2,2,2,[]' && $x == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "[$q] [$x]"; fi

kt_test_log "012_Palette.sh completed"
