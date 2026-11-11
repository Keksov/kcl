#!/usr/bin/env bash
# 002_Contract.sh - the kcl contract for fv.unicode (kcl/README.md §1) and its
# promises:
#   source integrity  bash -n, no single-quoted string left open;
#   set -eu (1.4)      loads, re-loads, loads by name, runs its main path and
#                      its error paths under `set -eu`; a reload after
#                      `kk.unit --forget` is clean;
#   no stray names     only __FV_UC_*, RESULT (KK_UNIT_DIR is the loader's)
#                      and fv.unicode.* functions are left behind;
#   never prints       nothing on stdout or stderr, also inside $( );
#   fork-free          PATH='' changes no answer; no subshell construct in a
#                      code line (the static scan of fv.keyboard's 007);
#   caller state       nocasematch, the C locale, globasciiranges off, an IFS
#                      of digits, failglob / nullglob change no answer;
#   cost (INFO)        load time and the per-lookup cost, with generous limits.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvu_testlib.sh"
fvu_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: the kcl contract"
UNIT=$FVU_UNIT KBOOL=$FVU_KBOOL

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then kt_test_fail "${bad//$'\n'/ | }"; else kt_test_pass "none"; fi

# expect_clean TITLE SNIPPET — a child `bash -c` under set -eu: rc 0, prints OK only
expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$FVU_TMP/setu.err")"; rc=$?
    err="$(<"$FVU_TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}

expect_clean "the unit loads under set -eu" "source '$UNIT'"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.unicode by name under set -eu" "source '$KBOOL'; kk.uses fv.unicode; declare -F fv.unicode.charClass >/dev/null"
expect_clean "the main path and the error paths under set -eu" "
source '$UNIT'
fv.unicode.charClass 19968; [[ \$RESULT == w ]]
fv.unicode.charClass 128512; [[ \$RESULT == y ]]
fv.unicode.charWidth 769; [[ \$RESULT == 0 ]]
fv.unicode.version; [[ \$RESULT == 16.0.0 ]]
fv.unicode.charClass x || [[ \$? == 2 ]]
fv.unicode.charWidth 1114112 || [[ \$? == 1 ]]
if fv.unicode.charClass ''; then exit 9; fi"
expect_clean "kk.unit --forget + re-source under set -e: same table version -> the expansion cache is kept" "
source '$UNIT'
fv.unicode.charClass 128512
kk.unit --forget fv.unicode
source '$UNIT'
[[ \${#__FV_UC_E[8032]} == 16 && \$__FV_UC_EV == 16.0.0 ]]
fv.unicode.charClass 128512; [[ \$RESULT == y ]]"
expect_clean "kk.unit --forget + re-source: a cache built from another table version is dropped" "
source '$UNIT'
fv.unicode.charClass 128512
__FV_UC_EV=15.1.0
__FV_UC_E[8032]=zzzzzzzzzzzzzzzz
kk.unit --forget fv.unicode
source '$UNIT'
[[ \${#__FV_UC_E[@]} == 0 && \$__FV_UC_EV == 16.0.0 ]]
fv.unicode.charClass 128512; [[ \$RESULT == y ]]"

kt_test_start "loading and using the unit leaves only __FV_UC_*, RESULT and fv.unicode.* behind"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$FVU_TMP/v0'
compgen -A function | LC_ALL=C sort > '$FVU_TMP/f0'
source '$UNIT'
fv.unicode.charClass 65; fv.unicode.charClass 128512; fv.unicode.charWidth 4352
fv.unicode.charClass x; fv.unicode.charClass 9999999; fv.unicode.version
compgen -v | LC_ALL=C sort > '$FVU_TMP/v1'
compgen -A function | LC_ALL=C sort > '$FVU_TMP/f1'
" 2>&1)"
newv="$(comm -13 "$FVU_TMP/v0" "$FVU_TMP/v1" | grep -vE '^(__FV_UC_[A-Z]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$FVU_TMP/f0" "$FVU_TMP/f1" | grep -v '^fv\.unicode\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_start "nothing is printed, also inside \$( ) and on the error paths (debug off)"
out=$( fv.unicode.charClass 65; fv.unicode.charWidth 19968; fv.unicode.version; fv.unicode.charClass x; fv.unicode.charClass 1114112 ) 2>&1
if [[ -z $out ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "VERBOSE_KKLASS=debug: one line per error on stderr, none on stdout"
out=$(VERBOSE_KKLASS=debug fv.unicode.charClass x 2>/dev/null; VERBOSE_KKLASS=debug fv.unicode.charClass 1114112 2>/dev/null)
err=$( { VERBOSE_KKLASS=debug fv.unicode.charClass x; VERBOSE_KKLASS=debug fv.unicode.charWidth 1114112; } 2>&1 >/dev/null )
if [[ -z $out && $err == *'not a code point'*$'\n'*'above U+10FFFF'* ]]; then kt_test_pass "ok"; else kt_test_fail "out=[$out] err=[$err]"; fi

# --- fork-free -----------------------------------------------------------------------
# incl. class x (169 ©, 10084 ❤) next to class y (8986 ⌚, 128512 😀): a caller's
# nocasematch must not make one letter match another
CPS=(0 65 169 769 4352 8986 10084 12872 19968 44032 65039 127462 127995 128512 131072 917505 1114111)
fvu_answers() { local c; ANS=''; for c in "${CPS[@]}"; do fv.unicode.charClass "$c"; ANS+=$RESULT; fv.unicode.charWidth "$c"; ANS+=$RESULT; done; }
fvu_answers; REF=$ANS
kt_test_start "the reference answers (class and width of ${#CPS[@]} code points)"
want=n1n1x1z0w2y2x1w2w2w2z0r1m2y2w2z0n1
if [[ $REF == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $REF want $want"; fi

kt_test_start "every answer is the same with PATH='' (and the error paths still work)"
unset '__FV_UC_E[*]' 2>/dev/null || __FV_UC_E=()
saved=$PATH
PATH=''
fvu_answers; got=$ANS
fv.unicode.charClass x; r1=$?
VERBOSE_KKLASS=debug fv.unicode.charClass 9999999 2>/dev/null; r2=$?
PATH=$saved
if [[ $got == "$REF" && $r1 == 2 && $r2 == 1 ]]; then kt_test_pass "$got"; else kt_test_fail "got $got want $REF rc $r1 $r2"; fi

# fvu_forks LINE — rc 0 when a code line holds a construct that forks (fv.keyboard 007)
fvu_forks() {
    local l=$1 q
    [[ $l =~ ^[[:space:]]*(#|$) ]] && return 1
    l=${l%%[[:space:]]#*}
    l=${l//'$(('/'(('}
    while [[ $l =~ \"[^\"]*\" ]]; do
        q=${BASH_REMATCH[0]}
        if [[ $q == *'$('* || $q == *'`'* ]]; then return 0; fi
        l=${l/"$q"/D}
    done
    while [[ $l =~ \'[^\']*\' ]]; do l=${l/"${BASH_REMATCH[0]}"/Q}; done
    if [[ $l == *'$('* || $l == *'`'* || $l == *'<('* || $l == *'>('* ]]; then return 0; fi
    if [[ $l =~ (^|[^A-Za-z0-9_.])coproc([^A-Za-z0-9_]|$) ]]; then return 0; fi
    while [[ $l =~ \(\(.*\)\) ]]; do l=${l/"${BASH_REMATCH[0]}"/A}; done
    while [[ $l =~ \[\[([^]]|\][^]])*\]\] ]]; do l=${l/"${BASH_REMATCH[0]}"/T}; done
    l=${l//'()'/ } l=${l//'=('/=}
    l=${l//'||'/ OR } l=${l//'&&'/ AND } l=${l//'>&'/ } l=${l//'<&'/ } l=${l//'&>'/ }
    [[ $l == *'|'* || $l == *'('* || $l == *'&'* ]]
}
kt_test_start "the scan flags each fork construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x="$(cmd)"' 'x=`cmd`' 'a > >(cmd)' 'printf x | read y' '( cd x; y )' 'cmd &' 'coproc cat'; do
    fvu_forks "$s" || bad+=" missed:[$s]"
done
for s in '(( a | b ))' 'x=$(( c >> 8 ))' '[[ a || b ]] || c' '# x=$(cmd)' 'f() {' 'a=( 1 2 )' '    [3]=z112n144' "__FV_UC_P+='*nn*'"; do
    if fvu_forks "$s"; then bad+=" false:[$s]"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.unicode.sh: no \$( ), backtick, <( ), >( ), pipe, ( ) subshell, & or coproc in any code line"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if fvu_forks "$l"; then bad+=" $n:[$l]"; fi
done < "$UNIT"
if [[ -z $bad ]]; then kt_test_pass "$n lines clean"; else kt_test_fail "$bad"; fi

# --- caller state ------------------------------------------------------------------------
kt_test_start "nocasematch, LC_ALL=C, globasciiranges off, IFS=0123456789, failglob + nullglob: same answers"
got=$(
    shopt -s nocasematch failglob nullglob
    shopt -u globasciiranges 2>/dev/null
    export LC_ALL=C
    IFS=0123456789
    __FV_UC_E=()
    fvu_answers
    printf '%s' "$ANS"
)
if [[ $got == "$REF" ]]; then kt_test_pass "ok"; else kt_test_fail "got $got want $REF"; fi

# --- cost (INFO, generous limits) -------------------------------------------------------
us() { T=${EPOCHREALTIME//[.,]/}; }
kt_test_start "load: kk.uses fv.unicode in a fresh shell (median of 5) <= 500 ms"
a=()
for i in 1 2 3 4 5; do
    a+=("$(bash -c "source '$KBOOL'; t0=\${EPOCHREALTIME//[.,]/}; kk.uses fv.unicode; t1=\${EPOCHREALTIME//[.,]/}; printf '%s' \$(( t1 - t0 ))")")
done
IFS=$'\n' read -r -d '' -a s < <(printf '%s\n' "${a[@]}" | sort -n) || :
med=${s[2]:-999999}
if (( med <= 500000 )); then kt_test_pass "$(( med / 1000 )).$(( med % 1000 / 100 )) ms"; else kt_test_fail "$med us"; fi

kt_test_start "lookup: median us per charClass (uniform page / expanded mixed page) <= 1000"
N=400
fv.unicode.charClass 128512
m=()
for c in 19968 128512; do
    r=()
    for k in 1 2 3 4 5; do
        us; t0=$T
        for (( i = 0; i < N; i++ )); do fv.unicode.charClass "$c"; done
        us; r+=($(( (T - t0) * 10 / N )))
    done
    IFS=$'\n' read -r -d '' -a s < <(printf '%s\n' "${r[@]}" | sort -n) || :
    m+=("${s[2]}")
done
us; t0=$T; unset '__FV_UC_E[3]'; fv.unicode.charClass 769; us; first=$(( T - t0 ))
if (( m[0] <= 10000 && m[1] <= 10000 )); then
    kt_test_pass "uniform $(( m[0] / 10 )).$(( m[0] % 10 )) us, mixed $(( m[1] / 10 )).$(( m[1] % 10 )) us, a page's first lookup $first us"
else kt_test_fail "${m[*]} (tenths of us)"; fi

kt_test_log "002_Contract.sh completed"
