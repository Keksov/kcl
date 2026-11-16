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
# setups bar FV_ASCII. A third block (L-1) starts fresh shells whose locale
# bash cannot restore (LANG / LC_ALL / LC_CTYPE naming a missing locale; LANG
# missing or empty beside a working LC_CTYPE and a missing LC_MESSAGES /
# LC_NUMERIC / LC_TIME; a shell left in UTF-8 under a missing name, before
# and after the load; a case-variant name under nocasematch): every entry
# point, the load and _drain (also from a real trap) keep the caller's
# locale variables (declare -p) and probe, checked after each call, and give
# the results of a C caller.

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


# --- a caller locale name that does not exist (L-1) ---------------------------------
# bash cannot restore a `local LC_ALL` to a name setlocale rejects (LANG /
# LC_ALL / LC_CTYPE = an uninstalled locale): the locale of the scope just
# left stays. Each run starts a fresh bash with the names in its environment
# (so its locale is what bash made of them), loads the unit, and runs every
# entry point; after EACH call the caller's ${#p} is recorded. Wanted: the
# load and the scene leave the caller's names and ${#p} as they were, every
# call sees the same ${#p}, the results (RESULT, rc, the class cache, the
# frame, the rows) equal those of a plain LC_ALL=C caller, nothing on stderr.
read -r -d '' SCENE3 <<'EOF' || :
FV_SCREEN_W=20 FV_SCREEN_H=3
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r='' k=''
c() { local rc=0; "$@" || rc=$?; r+="$rc:$RESULT,"; k+=${#p}; }
c fv.video.initScreen
c fv.video.strWidth $'\xe6\xbc\xa2'
c fv.video.strWidth $'\xe6\xbc\xa2'
c fv.video.strWidth $'\xe6\xbc\xa2'
c fv.video.writeStr 0 0 $'ab \xd0\xb6\xd1\x83\xd0\xba \xe2\x94\x80\xe2\x94\x90' 1
c fv.video.writeStr 0 1 $'\xe6\xbc\xa2\xe5\xad\x97x\xf0\x9f\x98\x80\xc3\xa9' 2
c fv.video.writeBuf 10 0 $'\xd0\x81\xd0\xb6\xe6\xbc\xa2' 1234
c fv.video.writeCStr 0 2 $'~\xd0\x9b~\xd0\xb5\xd0\xb2\xd0\xbe \xe2\x94\x80' 1 2
c fv.video.writeChar 15 2 $'\xe2\x95\x91' 3 2
c fv.video.fillRect 17 0 2 2 4 $'\xe2\x95\x90'
c fv.video.setClip 1 0 19 3
c fv.video.writeStr 0 2 $'[\xd0\xb6]' 5
c fv.video.resetClip
c fv.video.setCursorPos 3 1
c fv.video.setCursorType 1
c fv.video.definePalette 7 1 2
c fv.video.setColorDepth 16
c fv.video.updateScreen
c fv.video.writeStr x 0 a 1
c fv.video.writeBuf 0 0 ab 1
c fv.video.strWidth $'\xd0\x81\xd0\xbb\xd0\xba\xd0\xb0 \xe6\xbc\xa2 \xf0\x9f\x98\x80'
FV_SCREEN_W=12 FV_SCREEN_H=2 c fv.video.resizeScreen
c fv.video.writeStr 0 0 $'\xd0\x9f\xd1\x80\xd0\xb8 \xe6\xbc\xa2' 1
c fv.video.updateScreen
c fv.video.clearScreen
c fv.video.updateScreen
FV_TTY=$TMPF.none/tty c fv.video.initVideo
c fv.video.doneVideo
exec {dfd}</dev/null
trap 'fv.video._drain "$dfd"' USR1
kill -USR1 "$BASHPID"
r+="trap," k+=${#p}
trap - USR1
c fv.video._drain "$dfd" 2>/dev/null
exec {dfd}<&-
c fv.video.strWidth $'\xe6\xbc\xa2'
exec {fd}>&-
cc=$(LC_ALL=C; n=0; for x in "${!__FV_VS_CC[@]}"; do if [[ ${#x} == 1 && $x == [![:ascii:]] ]]; then n=$(( n + 1 )); fi; done; printf %s "$n")
( LC_ALL=C; printf 'R=%s cut-keys=%s' "$r" "$cc"; for y in 0 1; do printf ' [%q|%s]' "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done; printf '|K=%s' "$k" )
EOF
STATE3='printf "%s|" "$(for v in LC_ALL LANG LC_CTYPE LC_MESSAGES LC_NUMERIC LC_TIME; do declare -p "$v" 2>/dev/null || printf "%s-unset " "$v"; done)" "${#p}" "$(shopt -p nocasematch)"'
run3() {   # ENV PRE POST TAG -> OUT = state0^state1^state2^scene^state3 (startup warnings
    # dropped); the frame in $FVV_TMP/cs3_TAG.out (compared with cmp: printf %q
    # renders bytes by the locale, and Cygwin's C differs by how it was reached)
    local -a envs=()
    read -r -a envs <<< "$1"
    OUT=$(env -u LC_ALL -u LC_CTYPE -u LANG -u LC_MESSAGES -u LC_NUMERIC -u LC_TIME -u LC_COLLATE -u LC_MONETARY "${envs[@]}" "$BASH" -c "
TMPF='$FVV_TMP/cs3_$4.out'
p=\$'\\xd0\\xb6'
$2
printf '^'; $STATE3; printf '^'
source '$UNIT'
$STATE3; printf '^'
$3
$STATE3; printf '^'
$SCENE3
printf '^'
$STATE3" 2>&1)
    OUT=${OUT#*^}
}
run3 'LC_ALL=C' '' '' ref
IFS='^' read -r -d '' s0 s1 s2 ref3 s3 <<< "$OUT" || :
s3=${s3%$'\n'}
ref3=${ref3%%|K=*}
kt_test_start "missing-locale reference: a plain LC_ALL=C caller (strWidth of a CJK character 2, three times; no cut byte in the class cache)"
if [[ $ref3 == 'R=0:,0:2,0:2,0:2,'* && $ref3 == *' cut-keys=0 '* && $s0 == "$s3" && -s $FVV_TMP/cs3_ref.out ]]; then kt_test_pass "ok"; else kt_test_fail "[$OUT]"; fi

xx=xx_YY.UTF-8 i=0
# ENV/BEFORE-LOAD/AFTER-LOAD; "LC_ALL=C.UTF-8; unset LC_ALL" with LANG missing
# leaves the shell in UTF-8 under a missing name (bash keeps the locale). A
# restore with LC_ALL empty is setlocale(LC_ALL, LANG or "") first: a missing
# LANG, or with LANG empty any exported LC_* naming a missing locale, fails it
# even when LC_CTYPE works. c.utf-8 differs from the UTF-8 locale name only in
# case (nocasematch must not make them equal; rejected on some runtimes).
for cfg in "LANG=$xx//" "LC_ALL=$xx//" "LC_CTYPE=$xx//" "LC_CTYPE=$xx LANG=C.UTF-8//" \
    "LANG=$xx/LC_ALL=C.UTF-8; unset LC_ALL/" "LANG=$xx//LC_ALL=C.UTF-8; unset LC_ALL" \
    "LC_ALL=$xx//shopt -s nocasematch" "LANG=$xx LC_CTYPE=$xx//" "LC_ALL= LANG=$xx//" \
    "LANG=$xx LC_CTYPE=C.UTF-8//" "LANG=$xx LC_CTYPE=C//" "LC_CTYPE=C.UTF-8 LC_MESSAGES=$xx//" "LC_CTYPE=C LC_NUMERIC=$xx//" \
    "LANG= LC_CTYPE=C.UTF-8 LC_TIME=$xx//" "LC_ALL=c.utf-8/shopt -s nocasematch/" "LC_ALL=C.UTF-8//" "LANG=C.UTF-8//"; do
    IFS=/ read -r env pre post <<< "$cfg"
    kt_test_start "missing caller locale: env [$env] before load [$pre] after load [$post]: results of a C caller, the caller's locale kept by the load and by every call"
    i=$(( i + 1 ))
    run3 "$env" "$pre" "$post" "$i"
    fr=same; cmp -s "$FVV_TMP/cs3_ref.out" "$FVV_TMP/cs3_$i.out" || fr=differs
    IFS='^' read -r -d '' s0 s1 s2 got s3 <<< "$OUT" || :
    s3=${s3%$'\n'}
    k=${got##*|K=} got=${got%%|K=*}
    pr=${s2%|*|} pr=${pr##*|}
    printf -v kw '%*s' "${#k}" ''; kw=${kw// /$pr}
    if [[ $got == "$ref3" && $fr == same && $s0 == "$s1" && $s2 == "$s3" && $k == "$kw" && -n $k ]]; then kt_test_pass "ok (\${#p} $pr)"
    else kt_test_fail "out [$got] vs ref [$ref3]; frame $fr; state start [$s0] loaded [$s1] scene before [$s2] after [$s3]; \${#p} per call [$k]"; fi
done

kt_test_log "013_CallerState.sh completed"
