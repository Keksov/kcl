#!/bin/bash
# 007_Bench.sh — tawk P1: the PLAN.md §5 P1 performance gate, as assertions.
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   PLAN §5 P1 gate: `TAwk.apply '{print $2}' FILE` <= **1.5x** a bare
#   `gawk --sandbox -e '{print $2}' -- FILE` over the same corpus, from the
#   MEDIANS of 21 INTERLEAVED runs. Those are the numbers README.md §10
#   publishes, one column per bash (gawk 5.0.0 under 5.2.37, 5.4.0 under 5.3.9).
#
#   THIS FILE asserts the same shapes with a ceiling of **10x** — because ktests
#   runs test files THREADED, 8 workers by default, and the two sides of that
#   ratio do NOT inflate together under that load: the bare `gawk` is its own
#   process and roughly doubles, while the wrapper's share is bash work in the
#   contended shell and has been seen to grow tenfold (the same effect the
#   tgrep, tfind and tsed 007 headers record: a threaded run read 4.18x and the
#   next 1.16x on identical code). A ceiling set at 3x the idle measurement would
#   flake for a reason that has nothing to do with this unit; 10x still catches
#   every regression the gate exists for — an instance constructed per RECORD
#   instead of per call, a `$( )` around the producer, a second process per call
#   (an encoder shelled out to `sed`, say) — each of which costs orders of
#   magnitude, not tens of percent.
#
# MEDIANS, AND WHY THEY ARE NOT NEGOTIABLE. Every number here is one PROCESS
# START plus the work, and on this platform a process start occasionally takes
# several hundred milliseconds for reasons outside this repo. One such outlier
# moves a mean by more than the whole head-room, and it lands on a random side.
# While tfind was planned, the WORST SINGLE PAIRING read **1.64x** on code whose
# interleaved medians are 1.13-1.16x (tfind PLAN §8 finding 17) — a one-shot
# comparison would have failed a 1.5x gate on code that is fine. So the two
# shapes are timed INTERLEAVED, one of each per iteration, and the ratio is taken
# between the MEDIANS — the same treatment `../bench.sh` gives them.
#
# THE CLOCK IS `TStopwatch.getTimeStamp`, never `date +%s%N`: on msys the latter
# is its own process and costs ~20 ms per call — about half of the `gawk` run
# being measured, paid twice per sample.
#
# WHY CORPUS SIZE IS NOT THE KNOB. A whole `gawk` run — one msys process start
# plus the work — costs ~35-45 ms here; the wrapper's entire fixed delta (`new`
# with the program + `sandbox =` + the build + `delete`, NINE properties assigned
# and FOUR arrays declared by the constructor) is ~5 ms and is paid once per
# CALL. The ratio is therefore ~(40 + 5)/40 — it sits near 1.15x and can only
# fall as the file grows. This file uses a 200-line file, not bench.sh's
# 10 000, purely to stay under a few seconds; the ratio does not care, and the
# ONE-line shape below is here to show exactly that.
#
# STDIN IS CLOSED for the whole file (`exec </dev/null`, as in 005/006): gawk
# with no program, or with a path it takes for the program, reads stdin and
# would hang. Every gawk below has a program and a path anyway.
#
# The corpus is built with `kt_fixture_tmpdir_create` and torn down by the
# framework. This file installs NO `trap … EXIT` of its own — it would replace
# ktests' trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GNU BANNER GATE IS THE FIRST CASE, as in 005/006: D4 pins the DIALECT
# (GNU Awk), not a binary. Without the banner every timed case is a loud SKIP
# and the case COUNT is unchanged.
#
# Sections:
#   Z  the GNU banner gate and the corpus
#   A  the apply gate — `TAwk.apply` against a bare `gawk --sandbox -e … --` in
#      the two shapes that bracket the tool's own work (a 200-line file and a
#      ONE-line file), plus the wrapper's fixed delta measured on its own
#   B  the argv model: typed options into a command line, running NOTHING; the
#      rc 2 path (a `-W` deny-list hit), which runs nothing either; and the
#      `setVar` encoding of a 1 KiB value, fork-free and cheap
#   C  counting — the `count` sink against `gawk … | wc -l`
#   D  zero forks, for every member of the surface plus `apply` and the five
#      rc 2 paths a caller reaches by accident

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TA_DIR/tawk.sh"
source "$TA_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

kt_test_section "007: the PLAN §5 P1 performance gate (P1)"

NL=200           # lines in the small "big" file
NR=7             # interleaved runs per timed shape (odd, so the median is real)
PROG='{print $2}'

# median NAME -> MED (us). The `sort` fork is outside every timed region.
MED=0
median() {
    local -n __m_a="$1"
    local -a __m_s=()
    mapfile -t __m_s < <( printf '%s\n' "${__m_a[@]}" | sort -n )
    MED="${__m_s[ ${#__m_s[@]} / 2 ]}"
}

# ===========================================================================
kt_test_section "Z. the GNU banner gate and the corpus"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`gawk\` on PATH is GNU Awk (D4 pins the DIALECT, not a binary)"
AWK_BIN="$(command -v gawk 2>/dev/null || printf '(none)')"
AWK_VER="$(timeout 20 gawk --version 2>/dev/null </dev/null | head -1 || :)"
if [[ "$AWK_VER" == "GNU Awk "* ]]; then
    GNU_OK=1
    kt_test_pass "$AWK_BIN — $AWK_VER"
else
    kt_test_pass "SKIP: non-GNU awk ($AWK_BIN — '${AWK_VER:-no banner}'); every timed case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so the case COUNT is the same on a box without GNU Awk.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU awk"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create corpus)" && pwd)"
BIG="$FX/big.txt"
ONE="$FX/one.txt"
declare -a LNS=()
for (( i = 1; i <= NL; i++ )); do
    LNS+=( "$i" )
done
printf 'a%05d xyz\n' "${LNS[@]}" > "$BIG"      # two fields on every line
printf 'a%05d xyz\n' 1 > "$ONE"
unset -v LNS

# ===========================================================================
kt_test_section "A. the apply gate — TAwk.apply vs a bare \`gawk --sandbox -e … --\`"
# ===========================================================================

# gate_case FILE LABEL EXPECTED_RECORDS — the interleaved-median assertion with
# a 10x ceiling.
gate_case() {
    local __file="$1" __label="$2" __want="$3"
    if ! tcase "TAwk.apply over $__label costs at most 10x a bare \`gawk --sandbox -e … --\` (PLAN gate 1.5x)"; then
        return 0
    fi
    # Warm both sides — the file cache and the first bind of the member
    # wrappers — and compare their BYTES here, once. Comparing inside the timed
    # loop would add a `$( )` and a `cmp` fork to both sides and dilute the very
    # ratio the gate is about.
    local __ob="$FX/bare.out" __oa="$FX/apply.out" __same=0 __nb
    gawk --sandbox -e "$PROG" -- "$__file" > "$__ob" 2>/dev/null || :
    TAwk.apply "$PROG" "$__file" > "$__oa" 2>/dev/null || :
    if cmp -s "$__ob" "$__oa"; then
        __same=1
    fi
    __nb="$( wc -l < "$__oa" )"; __nb="${__nb//[[:space:]]/}"

    local -a __t_bare=() __t_ap=()
    local __i __a0 __a1
    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        gawk --sandbox -e "$PROG" -- "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) )

        TStopwatch.getTimeStamp; __a0=$RESULT
        TAwk.apply "$PROG" "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_ap+=( $(( __a1 - __a0 )) )
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_ap;   local __m_ap="$MED"
    local __lim=$(( __m_bare * 10 ))
    local __r100=$(( __m_ap * 100 / __m_bare ))
    if [[ "$__same" == "1" && "$__nb" == "$__want" ]] && (( __m_ap <= __lim )); then
        kt_test_pass "byte-identical, $__want records; gawk median ${__m_bare}us, apply median ${__m_ap}us — ${__r100}% (ceiling ${__lim}us), $NR runs"
    else
        kt_test_fail "same=$__same records='$__nb' (want $__want); gawk=${__m_bare}us apply=${__m_ap}us (${__r100}%) ceiling=${__lim}us"
    fi
}

gate_case "$BIG" "a $NL-line file" "$NL"
gate_case "$ONE" "a ONE-line file" 1

if tcase "the apply delta IS one instance: new PROGRAM + sandbox + buildArgv + delete under 50 ms"; then
    ND=20
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i = 0; i < ND; i++ )); do
        TAwk.new "BC_$i" "$PROG" "$ONE"
        "BC_$i".sandbox = 1
        "BC_$i".buildArgv
        "BC_$i".delete
    done
    TStopwatch.getTimeStamp; t1=$RESULT
    per=$(( (t1 - t0) / ND ))
    # the argv of one more such instance, built the same way, for the assert
    declare -a BV=()
    TAwk.new BCx "$PROG" "$ONE"
    BCx.sandbox = 1
    BCx.argv BV
    BCx.delete
    # Idle: ~4.7 ms on both bashes — nine properties assigned and four arrays
    # declared by the constructor, the rc 2 list walked by the build. The
    # ceiling is an order of magnitude above that, for the same reason as the
    # ratios above; what it catches is a construction that grew an ORDER of
    # magnitude — a fork, or a re-`build` of the class per instance.
    if (( per <= 50000 )) && [[ "${BV[*]}" == "gawk --sandbox -e $PROG -- $ONE" ]]; then
        kt_test_pass "new + sandbox + buildArgv + delete ${per}us/call over $ND calls (ceiling 50000us; ~4700us idle)"
    else
        kt_test_fail "new + sandbox + buildArgv + delete ${per}us/call over $ND calls (ceiling 50000us) argv=(${BV[*]})"
    fi
fi

# ===========================================================================
kt_test_section "B. the argv model runs NOTHING and forks nothing"
# ===========================================================================

ND=100
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }

kt_test_start "$(( ND * 2 )) buildArgv/argv calls never invoke the cmd and never fork"
TAwk.new BF "$PROG" "$BIG"
BF.addProgram 'END{print NR}'
BF.setVar lim 5
BF.addArg --lint
BF.cmd = bench_counted
declare -a BW=()
p0="$BASHPID"
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
n_build="$RESULT"
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
n_argv="$RESULT"
declare -a WANT=( bench_counted --sandbox --lint -v lim=5 -e "$PROG" -e 'END{print NR}' -- "$BIG" )
same=1
if (( ${#BW[@]} != ${#WANT[@]} )); then
    same=0
else
    for (( k = 0; k < ${#WANT[@]}; k++ )); do
        [[ "${BW[$k]}" == "${WANT[$k]}" ]] || same=0
    done
fi
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$n_build" == "11" && "$n_argv" == "11" && "$same" == "1" ]]; then
    kt_test_pass "cmd invoked 0 times in $(( ND * 2 )) builds, BASHPID $p0 unchanged, 11 words in the pinned order"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID buildArgv='$n_build' argv='$n_argv' words=(${BW[*]})"
fi

kt_test_start "the build stays constant-cost: $ND more rebuilds do not accumulate words"
declare -a BW2=()
BF.argv BW2
same=1
if (( ${#BW2[@]} != ${#WANT[@]} )); then
    same=0
else
    for (( k = 0; k < ${#WANT[@]}; k++ )); do
        [[ "${BW2[$k]}" == "${WANT[$k]}" ]] || same=0
    done
fi
if [[ "$same" == "1" && "$RESULT" == "11" ]]; then
    kt_test_pass "still 11 words after $(( ND * 2 + 1 )) rebuilds"
else
    kt_test_fail "n=${#BW2[@]} RESULT='$RESULT' words=(${BW2[*]})"
fi
BF.delete

kt_test_start "a REFUSED build runs nothing and forks nothing either ($ND deny-list rc 2 calls, \`-Wsandbox\` last)"
# The rc 2 path is the one a caller reaches by accident (an extra that gawk's
# getopt reads as a modelled or dangerous option), and it must be the CHEAP
# path: no fork, no command. The denied word comes LAST among three and uses the
# `-W` spelling, so the whole scan runs, the long-name table included.
BENCH_RAN=0
TAwk.new BR "$PROG" "$BIG"
BR.addArg -n --lint -Wsandbox
BR.cmd = bench_counted
p0="$BASHPID"
rc2_all=1
for (( i = 0; i < ND; i++ )); do
    rc=0
    BR.buildArgv >/dev/null 2>&1 || rc=$?
    [[ "$rc" == "2" ]] || rc2_all=0
done
declare -n RV=BR_argv
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$rc2_all" == "1" && "${#RV[@]}" == "0" ]]; then
    kt_test_pass "$ND refusals, all rc 2, cmd invoked 0 times, BASHPID $p0 unchanged, \${inst}_argv empty"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID allRc2=$rc2_all instArgv=${#RV[@]}"
fi
unset -n RV
BR.delete

kt_test_start "the setVar ENCODING of a 1 KiB value is fork-free and cheap ($ND builds under 20 ms each)"
# PLAN §2.3: every backslash doubled, every newline `\n`, a leading `@` `\100` —
# all in bash parameter expansion, no `$( )`, no `sed`. A 16-byte segment with
# two backslashes, a newline and an `@`, 64 times, the first byte turned into
# `@`: the encoded word is 64 x 19 + 3 = 1219 bytes after `x=`. Idle: ~1.9 ms
# per build against ~1.3 ms without the variable.
BS='\'
SEG="abc${BS}def"$'\n'"ghij${BS}kl@"
V1K=''
for (( i = 0; i < 64; i++ )); do V1K+="$SEG"; done
V1K="@${V1K:1}"
TAwk.new BE 'BEGIN{printf "%s", x}' "$ONE"
BE.setVar x "$V1K"
BE.cmd = bench_counted
BENCH_RAN=0
p0="$BASHPID"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BE.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
per=$(( (t1 - t0) / ND ))
declare -n EV=BE_argv
w="${EV[3]:-}"
unset -n EV
vv0="${BE_vvals[0]:-}"
if (( BENCH_RAN == 0 && per <= 20000 )) && [[ "$BASHPID" == "$p0" && ${#V1K} -eq 1024 \
      && "${w:0:6}" == "x=${BS}100" && ${#w} -eq $(( 2 + 64 * 19 + 3 )) && "$vv0" == "$V1K" ]]; then
    kt_test_pass "${per}us/build (ceiling 20000us), BASHPID unchanged, the -v word ${#w} bytes, the stored value still verbatim"
else
    kt_test_fail "ran=$BENCH_RAN per=${per}us pid $p0 -> $BASHPID len(V)=${#V1K} word=${#w} bytes head='${w:0:8}'"
fi
BE.delete

# ===========================================================================
kt_test_section "C. counting — the \`count\` sink vs \`gawk … | wc -l\`"
# ===========================================================================

# The shell equivalent needs TWO processes where the sink needs one; the sink
# pays a bash `read` per record instead. What this case is for is catching a
# per-record path that grew an ORDER of magnitude — a fork per record, a
# re-`build` per record — not a known constant, so the ceiling is 10x and
# `../bench.sh` publishes the real numbers.
if tcase "a.count over $NL records costs at most 10x \`gawk --sandbox -e … -- FILE | wc -l\` (published, not the gate)"; then
    TAwk.new BQ "$PROG" "$BIG"
    declare -a T_WC=() T_CNT=()
    n_wc="$( gawk --sandbox -e "$PROG" -- "$BIG" | wc -l )"
    n_wc="${n_wc//[[:space:]]/}"
    BQ.count >/dev/null 2>&1 || :
    n_cnt=''
    for (( i = 0; i < NR; i++ )); do
        TStopwatch.getTimeStamp; t0=$RESULT
        gawk --sandbox -e "$PROG" -- "$BIG" | wc -l >/dev/null || :
        TStopwatch.getTimeStamp; t1=$RESULT
        T_WC+=( $(( t1 - t0 )) )

        TStopwatch.getTimeStamp; t0=$RESULT
        BQ.count || :
        n_cnt="$RESULT"
        TStopwatch.getTimeStamp; t1=$RESULT
        T_CNT+=( $(( t1 - t0 )) )
    done
    median T_WC;  m_wc="$MED"; (( m_wc > 0 )) || m_wc=1
    median T_CNT; m_cnt="$MED"
    lim=$(( m_wc * 10 ))
    r100=$(( m_cnt * 100 / m_wc ))
    if [[ "$n_wc" == "$NL" && "$n_cnt" == "$NL" ]] && (( m_cnt <= lim )); then
        kt_test_pass "both counted $NL; pipeline median ${m_wc}us, a.count median ${m_cnt}us — ${r100}% (ceiling ${lim}us)"
    else
        kt_test_fail "pipeline='$n_wc' count='$n_cnt' (want $NL) pipeline=${m_wc}us count=${m_cnt}us (${r100}%) ceiling=${lim}us"
    fi
    BQ.delete
fi

# ===========================================================================
kt_test_section "D. zero forks — every member, \`apply\`, the rc 2 paths, the callback and .Add"
# ===========================================================================

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TForkTA007
    public
        var         N
        constructor Create
        proc        Add
end
TForkTA007.Create() { N=0; return 0; }
TForkTA007.Add()    { N=$(( N + 1 )); ADDPIDS+=( "$BASHPID" ); return 0; }
build TForkTA007
TForkTA007.new F7

if tcase "the five sinks: the callback and \`.Add\` run in THIS process"; then
    TAwk.new FH "$PROG" "$ONE"
    p0=$BASHPID
    CBPIDS=(); ADDPIDS=()
    declare -a FARR=()
    FH.each    pid_cb; rc1=$?
    FH.toList  F7;     rc2=$?; n_list="$RESULT"
    FH.toArray FARR;   rc3=$?; n_arr="$RESULT"
    FH.count;          rc4=$?; n_cnt="$RESULT"
    FH.first;          rc5=$?; first="$RESULT"
    ok=1
    for pid in "${CBPIDS[@]}" "${ADDPIDS[@]}"; do
        [[ "$pid" == "$p0" ]] || ok=0
    done
    if (( ok == 1 && ${#CBPIDS[@]} == 1 && ${#ADDPIDS[@]} == 1 )) \
       && [[ "$BASHPID" == "$p0" && $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 && $rc5 -eq 0 \
             && "$n_list" == "1" && "$n_arr" == "1" && "$n_cnt" == "1" && "$first" == "xyz" ]]; then
        kt_test_pass "1 record per sink, callback and .Add both in pid $p0"
    else
        kt_test_fail "ok=$ok rc=$rc1/$rc2/$rc3/$rc4/$rc5 list='$n_list' arr='$n_arr' cnt='$n_cnt' first='$first' cb=(${CBPIDS[*]}) add=(${ADDPIDS[*]})"
    fi
    FH.delete
fi

if tcase "the ONLY fork per call is gawk: every property, every builder member, \`run\` and \`apply\` fork nothing"; then
    TAwk.new FB "$PROG" "$ONE"
    p0=$BASHPID
    declare -a FW=()
    ok=1
    FB.program = "$PROG"          ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.programFile = ''           ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.fieldSep = ''              ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.nullData = 0               ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.binary = 0                 ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.sandbox = 1                ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.inPlace = 0                ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.backupSuffix = ''          ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.paths "$ONE"               ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.addProgram 'END{}'         ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearPrograms              ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.setVar x 1                 ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearVars                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.addArg --lint              ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearArgs                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.buildArgv                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.argv FW                    ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.mapRc 2 2>/dev/null        ; m2="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.mapRc 7                    ; m7="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.lastRc                     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.run >/dev/null; rcr=$?     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    TAwk.apply "$PROG" "$ONE" >/dev/null; rca=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    if (( ok == 1 )) && [[ "$m2" == "1" && "$m7" == "1" && $rcr -eq 0 && $rca -eq 0 \
          && "${FW[*]}" == "gawk --sandbox -e $PROG -- $ONE" ]]; then
        kt_test_pass "BASHPID $p0 unchanged across eight property writes, ten builder members (mapRc twice), lastRc, run and apply"
    else
        kt_test_fail "ok=$ok mapRc2='$m2' mapRc7='$m7' run rc=$rcr apply rc=$rca argv=(${FW[*]}) ours=$p0 now=$BASHPID"
    fi
    FB.delete
fi

if tcase "the rc 2 paths fork nothing: a deny-list hit, an in-place sink, a path-less and an empty-program \`apply\`, an illegal \`setVar\`"; then
    TAwk.new FR "$PROG" "$ONE"
    p0=$BASHPID
    ok=1
    FR.addArg --so=x
    rca=0; FR.count 2>/dev/null || rca=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    FR.clearArgs
    FR.sandbox = 0
    FR.inPlace = 1
    rcb=0; FR.first 2>/dev/null || rcb=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    rcc=0; TAwk.apply "$PROG" 2>/dev/null || rcc=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    rcd=0; TAwk.apply '' "$ONE" 2>/dev/null || rcd=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    rce=0; FR.setVar ENVIRON 1 2>/dev/null || rce=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    FR.lastRc; lr="$RESULT"
    if (( ok == 1 )) && [[ $rca -eq 2 && $rcb -eq 2 && $rcc -eq 2 && $rcd -eq 2 && $rce -eq 2 && "$lr" == "-1" ]]; then
        kt_test_pass "five refusals, all rc 2, BASHPID $p0 unchanged, lastRc still -1 (gawk never ran)"
    else
        kt_test_fail "ok=$ok rc=$rca/$rcb/$rcc/$rcd/$rce lastRc='$lr' ours=$p0 now=$BASHPID"
    fi
    FR.delete
fi

F7.delete

kt_test_log "007_Bench.sh completed"
