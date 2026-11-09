#!/usr/bin/env bash
# 004_ZeroFork.sh - no fork in fv.mouse (PLAN.md rule 1): every entry point
# with PATH='' (no external command can run), and no command substitution,
# process substitution, backtick, pipe, bare ( ) subshell, background & or
# coproc in its code lines (the forks
# PATH='' cannot see; the same scan as fv.keyboard's 007).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
source "$SCRIPT_DIR/../fv.mouse.sh"
kt_test_init "$(basename "$0" .sh)" "$SCRIPT_DIR" "$@"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "004: fork-free"

kt_test_start "decode (SGR, X10, malformed), enable, disable with PATH=''"
exec {fd}> "$TMP/seq"
saved=$PATH
PATH=''
r=''
fv.mouse.decode $'\e[<34;100;50M'; r+="$?:$FV_MOUSE_WHAT:$FV_MOUSE_BUTTON:$FV_MOUSE_X "
fv.mouse.decode $'\e[M`\xff\xff'; r+="$?:$FV_MOUSE_WHAT:$FV_MOUSE_X "
fv.mouse.decode $'\e[<0;0;1M'; r+="$? "
fv.mouse.decode junk; r+="$? "
VERBOSE_KKLASS=debug fv.mouse.decode junk 2>/dev/null; r+="$? "
fv.mouse.enable "$fd" any; r+="$? "
fv.mouse.disable "$fd"; r+="$? "
fv.mouse.enable x 2>/dev/null; r+="$?"
PATH=$saved
exec {fd}>&-
if [[ $r == '0:move:3:99 0:wheel:222 1 1 1 0 0 2' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

fvm_forks() {
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
for s in 'x=$(cmd)' 'x="$(cmd)"' 'x=`cmd`' 'a < <(cmd)' 'printf x | read y' '( cd x; y )' \
         'cmd &' 'coproc cat'; do
    fvm_forks "$s" || bad+=" missed:[$s]"
done
for s in '(( a | b ))' '[[ a || b ]] || c' 'x="a|b"' '# x=$(cmd) | y' 'f() {' 'a=( 1 2 )' \
         'if [[ ( $a ) && $b ]]; then x; fi' 'printf x >&$1 2>/dev/null' 'a && b'; do
    if fvm_forks "$s"; then bad+=" false:[$s]"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.mouse.sh: no \$( ), backtick, <( ), >( ), pipe, ( ) subshell, & or coproc in any code line"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvm_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$SCRIPT_DIR/../fv.mouse.sh"
if [[ -z $bad ]]; then kt_test_pass "$n lines clean"; else kt_test_fail "$bad"; fi

kt_test_log "004_ZeroFork.sh completed"
