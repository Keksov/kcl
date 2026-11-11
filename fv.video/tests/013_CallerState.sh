#!/usr/bin/env bash
# 013_CallerState.sh - the caller's shell state neither changes what the
# buffer stores and emits nor is changed by a call (B4, D11): one scripted
# scene (glob-like text `*[a]?`, symbols differing only in case, failing
# calls on every return path, frames to a file) runs in a child shell under
# each setup - nocasematch, failglob, nullglob, noglob, extglob on and off,
# globasciiranges off, odd IFS values, set -eu with pipefail, a C locale,
# LC_CTYPE only, all at once - and must give the reference output; the
# setup's options, IFS and locale are the same after the scene as before. A
# second scene with wide characters, emoji and clusters (P1b: the walk, the
# fast path's byte ranges, the class letters x / y) runs under the same
# setups bar FV_ASCII.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: the caller's shell state"

UNIT="$FVV_TESTS_DIR/../fv.video.sh"
# the state a setup may change, printed before and after the scene
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}" "${LC_CTYPE-unset}" "${#p}"'
SCENE='
FV_SCREEN_W=12 FV_SCREEN_H=3
o="$TMPF"
exec {fd}>"$o"
FV_VIDEO_OUT_FD=$fd
r=""
fv.video.initScreen; r+="$?."
fv.video.definePalette a 1 2; fv.video.definePalette A 3 4 1
fv.video.writeStr 0 0 "*[a]?" a; r+="$RESULT."
fv.video.writeBuf 5 0 "aAaA*?" "aAaAaA"; r+="$RESULT."
fv.video.writeCStr 0 1 "~*~[a]~?~" A a; r+="$RESULT."
fv.video.writeChar 6 1 "*" A 3; r+="$RESULT."
fv.video.fillRect 0 2 4 1 a "?"; r+="$RESULT."
fv.video.strWidth "*[a]? ж"; r+="$RESULT."
fv.video.setClip 1 0 11 3; fv.video.writeStr 0 2 "[!a]*" A; fv.video.resetClip
fv.video.setCursorPos 3 2; fv.video.setCursorType 1
fv.video.updateScreen; r+="$?."
fv.video.writeStr x 0 a a || r+="$?."
fv.video.writeStr 0 0 a "*" || r+="$?."
fv.video.setCursorType 9 || r+="$?."
fv.video.setColorDepth 16; fv.video.updateScreen; r+="$?."
FV_VIDEO_OUT_FD="" fv.video.updateScreen || r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$o" || :
printf "%s %q" "$r" "$frame"
for y in 0 1 2; do printf " [%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done
fv.video.definePalette "**" 1 1 || printf " rc%s" "$?"
'
run() {   # SETUP -> OUT = before-state / scene output / after-state
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/cs.out'
source '$UNIT'
p=\$'\\xd0\\xb6'
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}

run ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "reference run: the scene as expected"
want='0.5.6.5.3.4.7.0.2.2.2.0.1. '
if [[ $ref == "$want"* && $ref == *'[*[a]?aAaA*? |aaaaaaAaAaA0]'* && $ref == *' rc2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$ref]"; fi

for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'IFS=' 'set -eu -o pipefail' 'export LC_ALL=C' \
    'unset LC_ALL; export LC_CTYPE=C.UTF-8' "export FV_ASCII=1; IFS='0123456789abcdefx'" "shopt -s nocasematch; IFS='0123456789'" \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C"; do
    kt_test_start "same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done

# --- wide characters (P1b): the walk, the table lookups and the fast path -----------
# the fast path's byte patterns hold bracket ranges (globasciiranges, the C
# locale), the cluster rules compare class letters (nocasematch: x vs y)
SCENE2='
FV_SCREEN_W=16 FV_SCREEN_H=2
o="$TMPF"
exec {fd}>"$o"
FV_VIDEO_OUT_FD=$fd
r=""
fv.video.initScreen
fv.video.writeStr 0 0 $'"'"'\xe6\xbc\xa2x\xf0\x9f\x98\x80\xd0\xb6*[a]'"'"' a; r+="$RESULT."
fv.video.writeStr 3 0 "?" A; r+="$RESULT."
fv.video.writeStr 0 1 $'"'"'e\xcc\x81 \xc2\xa9 \xc2\xa9\xef\xb8\x8f \xe2\x8c\x9a \xe2\x9d\xa4'"'"' A; r+="$RESULT."
fv.video.writeStr 12 1 "Ёж─║" a; r+="$RESULT."
fv.video.strWidth $'"'"'\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbd\xf0\x9f\x87\xa9\xf0\x9f\x87\xaa\xe2\x84\x96'"'"'; r+="$RESULT."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$o" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1; do c=${__FV_VS_CH[y]}; c=${c//$'"'"'\x01'"'"'/"<"}; c=${c//$'"'"'\x02'"'"'/"#"}; printf " [%s|%s]" "$c" "${__FV_VS_AT[y]}"; done
for k in "0 3" "1 0"; do ( LC_ALL=C; printf " %q" "${__FV_VS_X[$k]-none}" ); done
'
run2() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/cs2.out'
source '$UNIT'
p=\$'\\xd0\\xb6'
$1
$STATE
printf '#'
$SCENE2
printf '#'
$STATE" 2>&1)
}
run2 ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "wide reference run: CJK, emoji, a cluster, x vs y classes, VS16, the fast path, a half-overwrite"
if [[ $ref == '10.1.11.4.5.0. '* && $ref == *'[漢<x? ж*[a]      |aaaAaaaaaa000000]'* && $ref == *' none '* ]]; then kt_test_pass "ok"; else kt_test_fail "[$ref]"; fi
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'set -eu -o pipefail' 'export LC_ALL=C' \
    'unset LC_ALL; export LC_CTYPE=C.UTF-8' "shopt -s nocasematch; shopt -u globasciiranges; IFS='xy'" \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C"; do
    kt_test_start "wide scene: same output and the state kept: $setup"
    run2 "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done

kt_test_log "013_CallerState.sh completed"
