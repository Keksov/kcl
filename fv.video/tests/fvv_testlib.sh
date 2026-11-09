#!/usr/bin/env bash
# fvv_testlib.sh — what the fv.video test files share. Not a test file: the
# ktests runner picks up NNN_*.sh only.
#
#   fvv_init NAME "$@"   ktest init + the unit + a scratch folder ($FVV_TMP)
#                        + the pty harness (fvv_pty.sh, FVP_ROOT under it)
#   fvv_forks LINE       rc 0 when a code line holds a construct that forks
#                        (the scan of fv.keyboard's 007)
#   fvv_skip_pty         rc 0 (and the remaining titles pass as SKIP) when
#                        this runtime has no util-linux script(1)

FVV_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVV_TESTS_DIR/../../../ktests/ktest.sh"

fvv_init() {
    local name=$1
    shift
    source "$FVV_TESTS_DIR/../fv.video.sh"
    kt_test_init "$name" "$FVV_TESTS_DIR" "$@"
    FVV_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    source "$FVV_TESTS_DIR/fvv_pty.sh"
    FVP_ROOT=$FVV_TMP/pty
    mkdir -p "$FVP_ROOT"
}

# fvv_skip TITLE... — one passing "SKIP: $FVP_WHY" test per title
fvv_skip() {
    local t
    for t; do
        kt_test_start "$t"
        kt_test_pass "SKIP: $FVP_WHY"
    done
}

fvv_forks() {
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
