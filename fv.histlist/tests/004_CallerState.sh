#!/usr/bin/env bash
# 004_CallerState.sh - fv.histlist never forks and leaves the caller's state
# alone:
#   * PATH='' (no external command can run): every entry point, the cap's
#     drops, a non-ASCII byte count, the refusals: no "command not found";
#   * the static scan (fv.video's 006 scanner): no $( ), backtick, process
#     substitution, pipe, ( ) subshell, & or coproc on any code line;
#   * the same calls under a caller IFS of ' \t\n', $'\x1f' and '',
#     nocasematch, extglob, a C locale, set -u: the same lists and answers,
#     and IFS / the shell options / the locale (${#ж}) / RESULT (procedures)
#     as they were; a C-locale caller's strings are its bytes (one store);
#   * an IFS holding \x01 is not supported (README), not tested.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvh_testlib.sh"
fvh_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: forks and the caller's state"

# one pass over every entry point; REPLY = the answers
pass() {
    local r='' s
    fv.histlist.clearHistory
    FV_HISTORY_SIZE=40
    fv.histlist.historyAdd 1 'one two'; fv.histlist.historyAdd 1 'жук жук'; fv.histlist.historyAdd 2 '中文'
    fv.histlist.historyAdd 1 'one two'; fv.histlist.historyAdd 3 '*?[a]'; fv.histlist.historyAdd 1 'x'
    fv.histlist.historyAdd 1 "$(printf 'L%.0s' {1..20})"
    fv.histlist.historyCount 1; r+="$RESULT|"
    for s in 0 1 2; do fv.histlist.historyStr 1 "$s" && r+="$RESULT|" || r+="rc$?|"; done
    fv.histlist.historyStr 3 0 && r+="$RESULT|" || r+="rc$?|"
    fv.histlist.historyAdd 999 x 2>/dev/null || r+="rc$?|"
    fv.histlist.historyStr 1 x 2>/dev/null || r+="rc$?|"
    r+=$__FV_HL_USED
    FV_HISTORY_SIZE=65536
    REPLY=$r
}

kt_test_start "PATH='': every entry point, no external command"
saved=$PATH
PATH=''
pass 2>"$FVH_TMP/p.err"
PATH=$saved
want=$REPLY err=$(<"$FVH_TMP/p.err")
if [[ -z $err && $want == 2'|'LLLLLLLLLLLLLLLLLLLL'|'x'|rc1|'*'|rc2|rc2|'* ]]; then kt_test_pass "$want"; else kt_test_fail "[$want] [$err]"; fi

kt_test_start "fv.histlist.sh: no \$( ), backtick, <( ), >( ), pipe, ( ) subshell, & or coproc in any code line"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvh_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$FVH_TESTS_DIR/../fv.histlist.sh"
if [[ -z $bad ]]; then kt_test_pass "$n lines clean"; else kt_test_fail "$bad"; fi

# state STATE-NAME SETUP RESTORE : the pass under SETUP, compared with $want;
# the caller's state checked after it
state() {
    local name=$1 got st0 st1
    kt_test_start "caller state: $name"
    eval "$2"
    st0="[$IFS]$-|${BASHOPTS}|${#ZH}"
    RESULT=mine; fv.histlist.historyAdd 9 keep; fv.histlist.clearHistory; local rr=$RESULT
    pass
    got=$REPLY
    st1="[$IFS]$-|${BASHOPTS}|${#ZH}"
    eval "$3"
    if [ "$got" = "$want" ] && [ "$st0" = "$st1" ] && [ "$rr" = mine ]; then kt_test_pass ok; else kt_test_fail "[$got] want [$want]; state [$st0] -> [$st1]; RESULT [$rr]"; fi
}
ZH=ж
state "IFS default" "IFS=$' \t\n'" ":"
state "IFS \\x1f" "OIFS=\$IFS; IFS=\$'\\x1f'" "IFS=\$OIFS"
state "IFS empty" "OIFS=\$IFS; IFS=" "IFS=\$OIFS"
state "nocasematch" "shopt -s nocasematch" "shopt -u nocasematch"
state "extglob" "shopt -s extglob" "shopt -u extglob"
state "set -u" "set -u" "set +u"

kt_test_start "a C-locale caller: its strings are bytes, the same store and answers; its locale stays C"
out="$(LC_ALL=C bash -c "
source '$FVH_TESTS_DIR/../fv.histlist.sh'
w=\$'\\xd0\\xb6'
fv.histlist.historyAdd 1 \"\$w\"; u=\$__FV_HL_USED
fv.histlist.historyAdd 1 abc; fv.histlist.historyAdd 1 \"\$w\"
fv.histlist.historyStr 1 0
[ \"\$RESULT\" = \"\$w\" ] && printf 'same|'
printf '%s|%s|%s' \"\$u\" \"\${#w}\" \"\$LC_ALL\"" 2>&1)"
if [[ $out == 'same|6|2|C' ]]; then kt_test_pass "$out"; else kt_test_fail "'$out'"; fi

kt_test_start "a UTF-8 caller: the byte count (a local LC_ALL=C) leaves its locale (\${#ж} stays 1)"
out="$(LC_ALL=C.UTF-8 bash -c "
source '$FVH_TESTS_DIR/../fv.histlist.sh'
w=ж; fv.histlist.historyAdd 1 жжж; r=\${#w}
LANG=C.UTF-8; unset LC_ALL; fv.histlist.historyAdd 1 中文; r+=\${#w}
printf '%s|%s' \"\$r\" \"\$__FV_HL_USED\"" 2>&1)"
if [[ $out == '11|19' ]]; then kt_test_pass "$out"; else kt_test_fail "'$out'"; fi

kt_test_log "004_CallerState.sh completed"
