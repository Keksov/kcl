#!/usr/bin/env bash
# 011_CallerState.sh - the caller's shell state (fv.msgbox 006's model)
# neither changes what the bash face does nor is changed by it: a child
# scene (every widget headless with key files through the real fv.drivers —
# a box, yesno, inputbox, a checklist with quoting, a menu letter jump, a
# Cyrillic letter jump, a radiolist, a scrolling text, a CJK scrolling
# prompt (its frames compared byte for byte), a session with an infobox, a
# refusal) runs under IFS ' \t\n' / $'\x1f' / '', nocasematch, extglob,
# LC_ALL=C (M2: fv.video's D11 scope — the Cyrillic jump and the CJK rows
# as under UTF-8), set -u, set -e (the calls that answer 0 as plain
# commands), nullglob, failglob, globstar + dotglob, set -f + nocaseglob
# and all at once, and must give the same answers (rc, RESULT,
# FV_DLG_TAGS, FV_DLG_CMD) and frames as without a setup, with the setup's
# IFS, options, flags and locale unchanged after it. An IFS holding \x01 is
# unsupported (fv.views / fv.dialogs README, "Contract"). Over 100 calls
# (plain and in a session) leave no view, variable or function and grow no
# table.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVDL_TESTS_DIR/.." && pwd)/fv.dlg.sh"
K=$FVW_TMP
printf '\r' > "$K/enter.keys"
printf '\t\r' > "$K/tab.keys"
printf 'abc\r' > "$K/abc.keys"
printf ' \e[B \r' > "$K/sds.keys"
printf 'b\r' > "$K/b.keys"
printf '\e[6~\r' > "$K/pgdn.keys"
printf 'x\r' > "$K/x.keys"
printf 'б\r' > "$K/cyr.keys"

# (call ! ARG...: a call that answers non-zero, run in || so that set -e
# lets the scene go on; every other call is a plain command)
cat > "$FVW_TMP/scene.sh" <<EOF
source '$UNIT' || exit 9
eval "\$SETUP"
st() { printf 'IFS=%q|%s|LC_ALL=%s|flags=%s\n' "\$IFS" "\$(shopt -p nocasematch extglob nullglob failglob globstar dotglob nocaseglob)" "\${LC_ALL-unset}" "\$-"; }
s0=\$(st)
out=''
call() {
    local r=0
    if [ "\$1" = '!' ]; then shift; fv.dlg.run "\$@" || r=\$?; else fv.dlg.run "\$@"; r=\$?; fi
    local IFS=' '
    out+="\$r|\$RESULT|\${#FV_DLG_TAGS[@]}:\${FV_DLG_TAGS[*]-}|\$FV_DLG_CMD;"
}
call --fv-headless --fv-keys '$K/enter.keys' --title T --msgbox 'Hello\\nworld' 0 0
call ! --fv-headless --fv-keys '$K/tab.keys' --yesno 'Sure?' 0 0
call --fv-headless --fv-keys '$K/abc.keys' --inputbox 'Name:' 0 0 old
call --fv-headless --fv-keys '$K/sds.keys' --checklist 'Pick' 0 0 0 'my app' A off "it's" B off c C on
call --fv-headless --fv-keys '$K/sds.keys' --single-quoted --checklist 'Pick' 0 0 0 'my app' A off "it's" B off c C on
call --fv-headless --fv-keys '$K/b.keys' --menu 'Pick' 0 0 0 apple A banana B blue C
call --fv-headless --fv-keys '$K/cyr.keys' --menu 'М' 0 0 0 а A б B в C
call --fv-headless --fv-keys '$K/sds.keys' --radiolist 'Pick' 0 0 0 a A on b B off
call --fv-headless --fv-keys '$K/pgdn.keys' --msgbox "\$(printf 'l%d\\\\n' {1..30})" 8 30
call --fv-headless --fv-keys '$K/pgdn.keys' --fv-out '$K/cjk.out' --msgbox '漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字漢字 éé\\n2\\n3\\n4\\n5\\n6\\n7' 7 21
call ! --fv-headless --fv-keys '$K/none.keys' --msgbox x 0 0 2>/dev/null
call ! --bogus --msgbox x 0 0 2>/dev/null
fv.dlg.begin --fv-headless --fv-keys '$K/x.keys' --backtitle S
call --inputbox 'Host:' 0 0
call --infobox 'wait' 0 0
fv.dlg.end
printf '%s\n' "\$out"
printf 'frames %s\n' "\$(<'$K/cjk.out')"
s1=\$(st)
if [[ \$s0 == "\$s1" ]]; then echo state-kept; else echo "state changed: [\$s0] -> [\$s1]"; fi
EOF

want=$(SETUP=: "$BASH" "$FVW_TMP/scene.sh" 2>&1)
kt_test_start "the reference run (no setup): the answers, the CJK prompt's frames"
w1=$'0||0:|cmOK;1||0:|cmNo;0|abc|0:|cmOK;0|"my app" "it\'s" "c"|3:my app it\'s c|cmOK;0|\'my app\' \'it\\\'s\' c|3:my app it\'s c|cmOK;'
w1+='0|banana|1:banana|cmOK;0|б|1:б|cmOK;0|b|1:b|cmOK;0||0:|cmOK;0||0:|cmOK;255||0:|;255||0:|;0|x|0:|cmOK;0||0:|cmOK;'
if [[ $want == "$w1"$'\nframes '*'漢'*$'\nstate-kept' ]]; then kt_test_pass ok; else kt_test_fail "got [${want:0:400} ... ${want: -300}] want [$w1]"; fi

kt_test_section "011: the caller's shell state"
for setup in "IFS=\$' \\t\\n'" "IFS=\$'\\x1f'" "IFS=" "shopt -s nocasematch" "shopt -s extglob" "LC_ALL=C" "set -u" "set -e" \
             "shopt -s nullglob" "shopt -s failglob" "shopt -s globstar dotglob" "set -f; shopt -s nocaseglob" \
             "shopt -s nocasematch extglob nullglob globstar dotglob nocaseglob; IFS=\$'\\x1f'; LC_ALL=C; set -euf"; do
    kt_test_start "the caller's state: $setup"
    out=$(SETUP=$setup "$BASH" "$FVW_TMP/scene.sh" 2>&1)
    if [[ $out == "$want" ]]; then kt_test_pass ok; else kt_test_fail "got [${out:0:600}] want [${want:0:600}]"; fi
done


kt_test_section "011: over 100 calls leave nothing"
sizes() {
    local v out=''
    for v in $(compgen -v); do
        case $v in FVW_*|FVA_*|FVDL_*|RESULT|REPLY|BASH_*|FUNCNAME|PIPESTATUS|_|v|out|COLUMNS|LINES|RANDOM|SECONDS|EPOCH*|SRANDOM|LINENO|BASHPID|i|SZ|s0|s1|d|w) continue ;; esac
        local -n __t_a=$v
        out+="$v:${#__t_a[@]} "
        unset -n __t_a
    done
    SZ="$out|$(( $(compgen -A function | wc -l) ))"
}
cycle() {
    fvdl_run 'char b' 'key kbEnter' -- --menu 'Pick' 0 0 0 apple A banana B
    fvdl_run 'char _' 'key kbDown' 'char _' 'key kbEnter' -- --checklist 'C' 0 0 3 a A off b B off c C off d D off
    fvdl_run 'char _' 'key kbEnter' -- --radiolist 'R' 0 0 0 a A off b B on
    fvdl_run 'key kbPgDn' 'key kbEnter' -- --msgbox "$(printf 'l%d\\n' {1..20})" 8 30
    fv.dlg.begin --fv-headless
    fvdl_events 'char x' 'key kbEnter'
    fv.dlg.run --inputbox 'Host:' 0 0
    fv.dlg.run --infobox 'wait' 0 0
    fvdl_events 'resize 100 30' 'key kbEnter'
    fv.dlg.run --yesno 'Sure?' 0 0
    fv.dlg.end
    fva_noevents; __FV_VW_EOF=0
}
cycle
sizes; s0=$SZ
for (( i = 0; i < 15; i++ )); do cycle; done
sizes; s1=$SZ
fvdl_live
kt_test_start "105 calls (15 cycles of 4 plain calls and a session with 3): no view, array, variable or function left; no table grew"
if [[ $s0 == "$s1" && -z $REPLY && -z $FV_APP ]]; then kt_test_pass "${#s0} chars of sizes equal"
else
    d=''
    for w in $s1; do [[ " $s0 " == *" $w "* ]] || d+=" $w"; done
    kt_test_fail "changed: [$d] (functions ${s0##*|} -> ${s1##*|}) live [$REPLY] app [$FV_APP]"
fi

kt_test_log "011_CallerState.sh completed"
