#!/bin/bash
# 007_Bench.sh — ttail P1: the PLAN.md §4 P1 performance gate, as assertions
# (the shared gate text is ../../thead/PLAN.md §5 P1).
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   gate: `TTail.take N FILE` <= **1.5x** a bare `tail -n N -- FILE` over the
#   same corpus, from the MEDIANS of 21 INTERLEAVED runs. Those are the numbers
#   README.md §9 publishes.
#
#   THIS FILE asserts the same shapes with a ceiling of **10x** — because ktests
#   runs test files THREADED, 8 workers by default, and the two sides of that
#   ratio do NOT inflate together under that load: the bare `tail` is its own
#   process and roughly doubles, while the wrapper's share is bash work in the
#   contended shell and has been seen to grow tenfold (the tgrep 007 header
#   records a threaded run at 4.18x and the next at 1.16x on identical code). A
#   ceiling set at 3x the idle measurement would flake for a reason that has
#   nothing to do with this unit; 10x still catches every regression the gate
#   exists for — an instance constructed per RECORD instead of per call, a
#   `$( )` around the producer, a second `tail` process per call — each of which
#   costs orders of magnitude, not tens of percent.
#
# MEDIANS. Every number here is one PROCESS START plus a scan, and on this
# platform a process start occasionally takes several hundred milliseconds for
# reasons outside this repo. One such outlier moves a mean by more than the
# whole head-room, and it lands on a random side. So the two shapes are timed
# INTERLEAVED, one of each per iteration, and the ratio is taken between the
# MEDIANS — the same treatment `../bench.sh` gives them, and the reason it
# exists there (thead PLAN §8 finding 7: a non-interleaved loop read 2.4x on
# code that interleaved medians put at 1.07-1.30x).
#
# WHY CORPUS SIZE IS NOT THE KNOB. A whole `tail` run — one msys process start
# plus the scan — costs 32-36 ms here at 10 000 lines; the wrapper's entire
# fixed delta (`new` + `argv` + `delete`) is 3.2-3.4 ms and is paid once per
# CALL. The ratio is therefore ~(34 + 3.3)/34 — it sits near 1.1x and can only
# fall as the corpus grows. This file uses 2000 lines, not bench.sh's 10 000,
# purely to stay under a few seconds; the ratio does not care.
#
# `follow` IS NOT TIMED HERE, and cannot be: `tail -f` never ends on its own, so
# nothing about it is a per-call cost. Only its REFUSING path is touched below
# (section D), which is bash-only and starts no process — so this file, unlike
# `005_Run.sh`, never creates a follower and has nothing to clean up.
#
# The corpus is built with `kt_fixture_tmpdir_create` and torn down by the
# framework. This file installs NO `trap … EXIT` of its own — it would replace
# ktests' trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GNU BANNER GATE IS THE FIRST CASE, as in 005/006: D4 pins the DIALECT
# (GNU coreutils 8.32), not a binary. Without the banner every timed case is a
# loud SKIP and the case COUNT is unchanged.
#
# Sections:
#   Z  the GNU banner gate and the corpus
#   A  the take gate — `TTail.take` against a bare `tail -n` in the two shapes
#      that bracket the tool's own work (`-n 1` and `-n 1000`), plus the
#      wrapper's fixed delta (`new` + `argv` + `delete`) measured on its own
#   B  the argv model: typed options into a command line, running NOTHING —
#      `-f` included, because `-f` reaches the argv even where sinks refuse it
#   C  counting — the `count` sink against the `wc -l` equivalent
#   D  zero forks, for every member of the surface, the three `follow = 1`
#      refusals, and `take`
#
# Timing primitive: TStopwatch.getTimeStamp — the shared fork-free us clock.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TT_DIR/ttail.sh"
source "$TT_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: the PLAN §4 P1 performance gate (P1)"

NL=2000          # corpus lines
HALF=1000        # the second gated shape
NR=7             # interleaved runs per timed shape (odd, so the median is real)

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
kt_test_start "the \`tail\` on PATH is GNU coreutils (D4 pins the DIALECT, not a binary)"
TAIL_BIN="$(command -v tail 2>/dev/null || printf '(none)')"
TAIL_VER="$(tail --version 2>/dev/null | sed -n 1p || :)"
if [[ "$TAIL_VER" == "tail (GNU coreutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$TAIL_BIN — $TAIL_VER"
else
    kt_test_pass "SKIP: non-GNU tail ($TAIL_BIN — '${TAIL_VER:-no banner}'); every timed case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so the case COUNT is the same on a box without GNU coreutils.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU tail"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create corpus)" && pwd)"
{
    for (( i = 0; i < NL; i++ )); do
        printf 'line %d of the bench corpus, some payload here\n' "$i"
    done
} > "$FX/big.txt"
printf 'one\ntwo\n' > "$FX/two.txt"
BIG="$FX/big.txt"

# ===========================================================================
kt_test_section "A. the take gate — TTail.take vs a bare \`tail -n\`"
# ===========================================================================

# gate_case N EXPECTED_RECORDS — the interleaved-median assertion, 10x ceiling.
gate_case() {
    local __n="$1" __want="$2"
    if ! tcase "TTail.take $__n costs at most 10x a bare \`tail -n $__n\` (PLAN gate 1.5x)"; then
        return 0
    fi
    # Warm both sides — the page cache and the first bind of the member wrappers
    # — and take the record counts HERE, once. Counting inside the timed loop
    # would add a `$( )` and a `wc` fork to both sides and dilute the very ratio
    # the gate is about.
    local __nb __nw
    __nb="$( tail -n "$__n" -- "$BIG" | wc -l )"; __nb="${__nb//[[:space:]]/}"
    __nw="$( TTail.take "$__n" "$BIG" | wc -l )"; __nw="${__nw//[[:space:]]/}"

    local -a __t_bare=() __t_take=()
    local __i __a0 __a1
    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        tail -n "$__n" -- "$BIG" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) )

        TStopwatch.getTimeStamp; __a0=$RESULT
        TTail.take "$__n" "$BIG" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_take+=( $(( __a1 - __a0 )) )
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_take; local __m_take="$MED"
    local __lim=$(( __m_bare * 10 ))
    local __r100=$(( __m_take * 100 / __m_bare ))
    if [[ "$__nb" == "$__want" && "$__nw" == "$__want" ]] && (( __m_take <= __lim )); then
        kt_test_pass "both delivered $__want records; tail median ${__m_bare}us, take median ${__m_take}us — ${__r100}% (ceiling ${__lim}us), $NR runs"
    else
        kt_test_fail "tail records='$__nb' take records='$__nw' (want $__want); tail=${__m_bare}us take=${__m_take}us (${__r100}%) ceiling=${__lim}us"
    fi
}

gate_case 1 1
gate_case "$HALF" "$HALF"

if tcase "the take delta IS one instance: new + argv + delete under 50 ms"; then
    ND=20
    declare -a BV=()
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i = 0; i < ND; i++ )); do
        TTail.new BC "$HALF" "$BIG"
        BC.argv BV
        BC.delete
    done
    TStopwatch.getTimeStamp; t1=$RESULT
    per=$(( (t1 - t0) / ND ))
    # Idle: 3.2-3.4 ms on both bashes (the plan estimated ~3.9 ms). The ceiling
    # is an order of magnitude above
    # that, for the same reason as the ratios above; what it catches is a
    # construction that grew an ORDER of magnitude — a fork, or a re-`build` of
    # the class per instance.
    if (( per <= 50000 )); then
        kt_test_pass "new + argv + delete ${per}us/call over $ND calls (ceiling 50000us; 3200-3400us idle)"
    else
        kt_test_fail "new + argv + delete ${per}us/call over $ND calls (ceiling 50000us)"
    fi
fi

# ===========================================================================
kt_test_section "B. the argv model runs NOTHING and forks nothing"
# ===========================================================================

ND=100
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }

kt_test_start "$(( ND * 2 )) buildArgv/argv calls never invoke the cmd and never fork (-f included)"
TTail.new BT 5 "$BIG"
BT.quiet  = 1
BT.follow = 1
BT.cmd    = bench_counted
declare -a BW=()
p0="$BASHPID"
for (( i = 0; i < ND; i++ )); do BT.buildArgv; done
n_build="$RESULT"
for (( i = 0; i < ND; i++ )); do BT.argv BW; done
n_argv="$RESULT"
want="bench_counted -q -f -n 5 -- $BIG"
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$n_build" == "7" && "$n_argv" == "7" \
      && "${BW[*]}" == "$want" && "${#BW[@]}" == "7" ]]; then
    kt_test_pass "cmd invoked 0 times in $(( ND * 2 )) builds, BASHPID $p0 unchanged, 7 words with -f in its slot"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID buildArgv='$n_build' argv='$n_argv' words=(${BW[*]})"
fi

kt_test_start "the build stays constant-cost: $ND rebuilds do not accumulate words"
declare -a BW2=()
BT.argv BW2
if [[ "${#BW2[@]}" == "7" && "${BW2[*]}" == "$want" && "$RESULT" == "7" ]]; then
    kt_test_pass "still 7 words after $(( ND * 2 + 1 )) rebuilds"
else
    kt_test_fail "n=${#BW2[@]} RESULT='$RESULT' words=(${BW2[*]})"
fi
BT.delete

# ===========================================================================
kt_test_section "C. counting — the \`count\` sink vs the \`wc -l\` equivalent"
# ===========================================================================

# The `count` sink's cost is PER RECORD (~134 us of bash `read` each), while the
# `wc -l` equivalent's is two process starts and then memory speed. So this
# comparison is the one place where N really does move the ratio, and it is run
# over a DELIBERATELY SMALL number of records: `../bench.sh` publishes the real
# 5000-record figure, and what this case is for is catching a per-record path
# that grew an ORDER of magnitude — a fork per record, a re-`build` per record —
# not the known constant.
CNT_N=200

if tcase "t.count over $CNT_N records costs at most 10x \`tail -n $CNT_N | wc -l\` (published, not the gate)"; then
    TTail.new BQ "$CNT_N" "$BIG"
    declare -a T_WC=() T_CNT=()
    n_wc="$( tail -n "$CNT_N" -- "$BIG" | wc -l )"; n_wc="${n_wc//[[:space:]]/}"
    BQ.count >/dev/null 2>&1 || :
    n_cnt=''
    for (( i = 0; i < NR; i++ )); do
        TStopwatch.getTimeStamp; t0=$RESULT
        tail -n "$CNT_N" -- "$BIG" | wc -l >/dev/null || :
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
    if [[ "$n_wc" == "$CNT_N" && "$n_cnt" == "$CNT_N" ]] && (( m_cnt <= lim )); then
        kt_test_pass "both counted $CNT_N; wc median ${m_wc}us, t.count median ${m_cnt}us — ${r100}% (ceiling ${lim}us)"
    else
        kt_test_fail "wc='$n_wc' count='$n_cnt' (want $CNT_N) wc=${m_wc}us count=${m_cnt}us (${r100}%) ceiling=${lim}us"
    fi
    BQ.delete
fi

# ===========================================================================
kt_test_section "D. zero forks — every member, the follow refusals, \`take\`"
# ===========================================================================

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TForkTT007
    public
        constructor Create
        proc        Add
end
TForkTT007.Create() { return 0; }
TForkTT007.Add()    { ADDPIDS+=( "$BASHPID" ); return 0; }
build TForkTT007
TForkTT007.new F7

if tcase "the five sinks: the callback and \`.Add\` run in THIS process"; then
    TTail.new FT 2 "$FX/two.txt"
    p0=$BASHPID
    CBPIDS=(); ADDPIDS=()
    declare -a FARR=()
    FT.each    pid_cb; rc1=$?
    FT.toList  F7;     rc2=$?; n_list="$RESULT"
    FT.toArray FARR;   rc3=$?; n_arr="$RESULT"
    FT.count;          rc4=$?; n_cnt="$RESULT"
    FT.first;          rc5=$?; first="$RESULT"
    ok=1
    for pid in "${CBPIDS[@]}" "${ADDPIDS[@]}"; do
        [[ "$pid" == "$p0" ]] || ok=0
    done
    if (( ok == 1 && ${#CBPIDS[@]} == 2 && ${#ADDPIDS[@]} == 2 )) \
       && [[ "$BASHPID" == "$p0" && $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 && $rc5 -eq 0 \
             && "$n_list" == "2" && "$n_arr" == "2" && "$n_cnt" == "2" && "$first" == "one" ]]; then
        kt_test_pass "2 records per sink (the three OVERRIDDEN ones included), callback and .Add in pid $p0"
    else
        kt_test_fail "ok=$ok rc=$rc1/$rc2/$rc3/$rc4/$rc5 list='$n_list' arr='$n_arr' cnt='$n_cnt' first='$first' cb=(${CBPIDS[*]}) add=(${ADDPIDS[*]})"
    fi
    FT.delete
fi

if tcase "the ONLY fork per call is tail: the builder members and \`take\` fork nothing"; then
    TTail.new FB 2 "$FX/two.txt"
    p0=$BASHPID
    declare -a FW=()
    ok=1
    FB.buildArgv                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.argv FW                    ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.paths "$FX/two.txt"        ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.addArg                     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearArgs                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.mapRc 1 2>/dev/null        ; m1="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.lastRc                     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.run >/dev/null; rcr=$?     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    TTail.take 2 "$FX/two.txt" >/dev/null; rct=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    if (( ok == 1 )) && [[ "$m1" == "1" && $rcr -eq 0 && $rct -eq 0 ]]; then
        kt_test_pass "BASHPID $p0 unchanged across seven builder members, run and take"
    else
        kt_test_fail "ok=$ok mapRc1='$m1' run rc=$rcr take rc=$rct ours=$p0 now=$BASHPID"
    fi
    FB.delete
fi

kt_test_start "the three \`follow = 1\` refusals are bash-only: rc 2, no process, no fork"
TTail.new FF 1 "$FX/two.txt"
FF.follow = 1
p0=$BASHPID
declare -a FFA=()
ok=1
FF.toArray FFA 2>/dev/null; rc_a=$?; r_a="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
FF.toList  F7  2>/dev/null; rc_l=$?; r_l="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
FF.count       2>/dev/null; rc_c=$?; r_c="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
FF.lastRc;                           r_last="$RESULT"
if (( ok == 1 )) && [[ $rc_a -eq 2 && $rc_l -eq 2 && $rc_c -eq 2 \
      && "$r_a" == "" && "$r_l" == "" && "$r_c" == "" && "$r_last" == "-1" && "${#FFA[@]}" == "0" ]]; then
    kt_test_pass "rc 2 from all three, RESULT '', lastRc still -1 (nothing ran), BASHPID $p0 unchanged"
else
    kt_test_fail "ok=$ok rc=$rc_a/$rc_l/$rc_c RESULT='$r_a'/'$r_l'/'$r_c' lastRc='$r_last' arr=${#FFA[@]}"
fi
FF.delete

F7.delete

kt_test_log "007_Bench.sh completed"
