#!/usr/bin/env bash
# 003_EnableDisable.sh - fv.mouse.enable / fv.mouse.disable PRINT the DEC
# private-mode sequences to a file descriptor (default 1) and leave them in
# RESULT; they never touch a terminal. Enable: 1000 (buttons), 1002 (drag),
# [1003 (all motion) with `any`], 1006 (SGR encoding) last; disable: the
# reverse, 1003 always included. A bad fd or mode is rc 2 with nothing printed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
source "$SCRIPT_DIR/../fv.mouse.sh"
kt_test_init "$(basename "$0" .sh)" "$SCRIPT_DIR" "$@"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "003: enable / disable sequences"

ON=$'\e[?1000h\e[?1002h\e[?1006h'
ON_ANY=$'\e[?1000h\e[?1002h\e[?1003h\e[?1006h'
OFF=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l'

# same TITLE WANT FILE RC WANT_RC — the file's bytes == WANT, RESULT == WANT
same() {
    local got v w
    got=$(<"$3")
    printf -v v '%q' "$got"; printf -v w '%q' "$2"
    kt_test_start "$1"
    if [[ $got == "$2" && $RESULT == "$2" && $4 == "$5" ]]; then kt_test_pass "$v"; else kt_test_fail "got $v want $w RESULT-ok=$([[ $RESULT == "$2" ]] && echo y || echo n) rc=$4"; fi
}

fv.mouse.enable > "$TMP/o"; rc=$?
same "enable prints 1000h 1002h 1006h to stdout by default" "$ON" "$TMP/o" "$rc" 0
fv.mouse.enable 1 any > "$TMP/o"; rc=$?
same "enable 1 any adds 1003h before 1006h" "$ON_ANY" "$TMP/o" "$rc" 0
fv.mouse.disable > "$TMP/o"; rc=$?
same "disable prints 1006l 1003l 1002l 1000l" "$OFF" "$TMP/o" "$rc" 0
fv.mouse.enable 2 2> "$TMP/o" >/dev/null; rc=$?
same "enable 2 writes to stderr" "$ON" "$TMP/o" "$rc" 0
exec {fd}> "$TMP/o"
fv.mouse.enable "$fd"; rc1=$?
fv.mouse.disable "$fd"; rc2=$?
exec {fd}>&-
RESULT=$ON$OFF   # each call's RESULT is its own sequence; the file holds both
same "enable + disable to an opened fd (the order a program uses)" "$ON$OFF" "$TMP/o" "$rc1$rc2" 00

kt_test_start "an fd that is closed or read-only: rc 2, RESULT='', nothing printed anywhere (fix round F7a)"
: > "$TMP/ro"
exec 77< "$TMP/ro"
RESULT=old
fv.mouse.enable 77 > "$TMP/o1" 2> "$TMP/e1"; r="$?:${RESULT:-e}"
exec 77<&-
RESULT=old
fv.mouse.disable 77 > "$TMP/o2" 2> "$TMP/e2"; r+=" $?:${RESULT:-e}"
RESULT=old
fv.mouse.enable 76 any > "$TMP/o3" 2> "$TMP/e3"; r+=" $?:${RESULT:-e}"
# (BSD / macOS wc pads the count with blanks)
n=$(cat "$TMP/o1" "$TMP/e1" "$TMP/o2" "$TMP/e2" "$TMP/o3" "$TMP/e3" "$TMP/ro" | wc -c); n=${n//[!0-9]/}
if [[ $r == '2:e 2:e 2:e' && $n == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "$r bytes=$n: $(cat "$TMP/e1" "$TMP/e2" "$TMP/e3")"; fi

kt_test_start "a bad fd or mode: rc 2, nothing printed, RESULT=''"
r=''
for a in x -1 '1;2' ' '; do
    out=$(fv.mouse.enable "$a" 2>&1); fv.mouse.enable "$a" >/dev/null 2>&1; rc=$?
    r+="[$a]=$rc,${#out},${RESULT:-e} "
    out=$(fv.mouse.disable "$a" 2>&1); fv.mouse.disable "$a" >/dev/null 2>&1; rc=$?
    r+="$rc,${#out} "
done
out=$(fv.mouse.enable 1 all 2>&1); fv.mouse.enable 1 all >/dev/null 2>&1; rc=$?
r+="[all]=$rc,${#out},${RESULT:-e}"
if [[ $r == '[x]=2,0,e 2,0 [-1]=2,0,e 2,0 [1;2]=2,0,e 2,0 [ ]=2,0,e 2,0 [all]=2,0,e' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "the sequences parse back as what they say (CSI ? N h / l)"
ok=1
for s in "$ON_ANY" "$OFF"; do
    rest=$s
    while [[ -n $rest ]]; do
        if [[ $rest =~ ^$'\e'\[\?(1000|1002|1003|1006)[hl] ]]; then rest=${rest:${#BASH_REMATCH[0]}}; else ok=0; break; fi
    done
done
if (( ok )); then kt_test_pass "ok"; else kt_test_fail "unparsed tail"; fi

kt_test_start "a caller IFS holding digits: enable / disable to fd N still print (the fd must not split)"
exec {fd}> "$TMP/ifs"
r=''
IFS=0123456789 fv.mouse.enable "$fd"; r+=$?
IFS=0123456789 fv.mouse.disable "$fd"; r+=$?
exec {fd}>&-
got=$(<"$TMP/ifs")
if [[ $r == 00 && $got == "$ON$OFF" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r got $(printf '%q' "$got")"; fi

kt_test_log "003_EnableDisable.sh completed"
