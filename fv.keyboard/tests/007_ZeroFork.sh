#!/usr/bin/env bash
# 007_ZeroFork.sh - no fork on any decode or read path (PLAN.md rule 1):
#   * every entry point works with PATH='' (no external command can run), on
#     the queue, a file fd, the timeout and the poll forms, the error paths;
#   * the unit's code has no command substitution, process substitution,
#     backtick, pipe, bare ( ) subshell, background & or coproc (the forks
#     PATH='' cannot see).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: fork-free"

printf '%s' $'a\e[A\e[1;5D\xd0\xb6\e[<0;3;4M' > "$FVK_TMP/in.bin"
printf 'x\0y' > "$FVK_TMP/nul.bin"

kt_test_start "the whole API with PATH='' (decode, feed, flush, getKeyEvent [T|0], pollKeyEvent, NUL, EOF, rc 2)"
exec {f1}< "$FVK_TMP/in.bin" {f2}< "$FVK_TMP/nul.bin" {f3}</dev/null
saved=$PATH
PATH=''
r=''
fv.keyboard.decode $'\e[15;2~'; r+="$FV_KEY "
fv.keyboard.decode $'\e'; r+="$FV_KEY "
fv.keyboard.decode $'\e[M\xc3\xa9!'; r+="$FV_KEY "
fv.keyboard.decode $'\xf0\x9f\x98\x80'; r+="$FV_KEY "
FV_KEY_FD=$f1
fv.keyboard.flush
fv.keyboard.pollKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent 0.5; r+="$FV_KEY "
fv.keyboard.getKeyEvent 0; r+="$FV_KEY "
fv.keyboard.getKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent; r+="$?:$FV_KEY:$FV_KEY_EOF "
FV_KEY_FD=$f2
fv.keyboard.getKeyEvent; fv.keyboard.getKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent; fv.keyboard.getKeyEvent; r+="$?:$FV_KEY "
FV_KEY_FD=$f3
fv.keyboard.feed $'\e'
FV_ESC_TIMEOUT=0.05 fv.keyboard.getKeyEvent; r+="$FV_KEY "
fv.keyboard.getKeyEvent 0.05; r+="$? "
fv.keyboard.getKeyEvent bad; r+="$? "
FV_KEY_FD=x fv.keyboard.pollKeyEvent; r+="$? "
VERBOSE_KKLASS=debug fv.keyboard.getKeyEvent bad 2>/dev/null; r+="$?"
PATH=$saved
exec {f1}<&- {f2}<&- {f3}<&-
want='kbShiftF5 kbEsc kbMouse kbChar kbChar kbChar kbUp kbCtrlLeft kbChar kbMouse 1:kbNoKey:1 kbCtrlSpace 1:kbNoKey kbEsc 1 2 2 2'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got  $r"$'\n'"want $want"; fi

# --- static: no subshell constructs in the code lines --------------------------------
# fvk_forks LINE — rc 0 when a code line holds a construct that forks: $( (not
# $(( arithmetic), a backtick, <( or >( or coproc outside comments and single
# quotes (a double-quoted $( still runs); or, once quoted text, (( )), [[ ]],
# fn(), arr=( and the operators || && >& <& &> are gone, a pipe, a bare ( )
# subshell or a background &.
fvk_forks() {
    local l=$1 q
    [[ $l =~ ^[[:space:]]*(#|$) ]] && return 1
    l=${l%%[[:space:]]#*}
    l=${l//'$(('/'(('}
    # double-quoted text: a $( or backtick inside it still runs
    while [[ $l =~ \"[^\"]*\" ]]; do
        q=${BASH_REMATCH[0]}
        if [[ $q == *'$('* || $q == *'`'* ]]; then return 0; fi
        l=${l/"$q"/D}
    done
    while [[ $l =~ \'[^\']*\' ]]; do l=${l/"${BASH_REMATCH[0]}"/Q}; done
    if [[ $l == *'$('* || $l == *'`'* || $l == *'<('* || $l == *'>('* ]]; then return 0; fi
    if [[ $l =~ (^|[^A-Za-z0-9_.])coproc([^A-Za-z0-9_]|$) ]]; then return 0; fi
    while [[ $l =~ \(\(.*\)\) ]]; do l=${l/"${BASH_REMATCH[0]}"/A}; done
    # [[ ]] (its ( ) group, its && and ||), function definitions, array values
    while [[ $l =~ \[\[([^]]|\][^]])*\]\] ]]; do l=${l/"${BASH_REMATCH[0]}"/T}; done
    l=${l//'()'/ } l=${l//'=('/=}
    l=${l//'||'/ OR } l=${l//'&&'/ AND } l=${l//'>&'/ } l=${l//'<&'/ } l=${l//'&>'/ }
    # what is left: a pipe, a bare ( ) subshell, a background &
    [[ $l == *'|'* || $l == *'('* || $l == *'&'* ]]
}

kt_test_start "the scan flags each construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x="$(cmd)"' 'x=`cmd`' 'while read l; do :; done < <(cmd)' 'a > >(cmd)' \
         'printf x | read y' "a 'q' | b" '  f "|" | g  # c' '( cd x; y )' 'a=1; (b)' 'cmd &' \
         'cmd & wait' 'coproc cat' 'coproc W { cat; }' 'if [[ a ]]; then (b); fi'; do
    fvk_forks "$s" || bad+=" missed:[$s]"
done
for s in '(( a | b ))' 'x=$(( a | (b & 1) ))' '[[ a || b ]] || c' "case \$x in 'a|b') ;; esac" \
         'x="a|b"' '# x=$(cmd) | y' 'f  # $(not code)' 'f() {' 'a=( 1 2 )' \
         'if [[ ( $a == 1 || $b ) && $c ]]; then x; fi' 'x >&2' 'y 2>&1' 'a && b' 'z <&$fd' \
         'declare -A x=( [k]=v )' "case \$c in '\$') ;; esac" 'coprocess=1'; do
    if fvk_forks "$s"; then bad+=" false:[$s]"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.keyboard.sh: no \$( ), backtick, <( ), >( ), pipe, ( ) subshell, & or coproc in any code line"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvk_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$FVK_TESTS_DIR/../fv.keyboard.sh"
if [[ -z $bad ]]; then kt_test_pass "$n lines clean"; else kt_test_fail "$bad"; fi

kt_test_log "007_ZeroFork.sh completed"
