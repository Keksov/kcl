#!/bin/bash
# 007_Bench.sh — tgrep P3: the PLAN.md §5 P3.1 performance gates, as assertions.
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   PLAN §5 gate: `TGrep.search PATTERN DIR` <= **1.3x** a bare
#   `grep -r -e PATTERN -- DIR` over the same corpus. Measured 2026-09-11 on a
#   10 000-line corpus: **1.17x** on bash 5.2.37 and **1.23x** on bash 5.3.9,
#   with `g.count` at 1.47x / 1.50x of `grep -c` and the `countOnly` shortcut at
#   1.09x / 1.10x. Those are the numbers README.md §9 publishes.
#
#   THIS FILE asserts the same shapes with a ceiling of **10x** — because ktests
#   runs test files THREADED, 8 workers by default, and the two sides of these
#   ratios do NOT inflate together under that load: the bare `grep` is its own
#   process and roughly doubles, while the wrapper's share is bash work in the
#   contended shell and has been seen to grow tenfold. A first threaded run of
#   this file measured the search ratio at **4.18x** (grep median 57 ms, search
#   median 238 ms) and passed at **1.16x** on the next, with the same code. A
#   ceiling set at 3x the idle measurement would therefore flake for a reason
#   that has nothing to do with this unit; 10x still catches every regression
#   the gate exists for — an instance constructed per LINE instead of per call,
#   a `$( )` around the producer, a second grep process per call — each of which
#   costs orders of magnitude, not tens of percent.
#
# MEDIANS. Every number here is one PROCESS START plus a scan (~28 ms idle), and
# on this platform a process start occasionally takes 200 ms for reasons outside
# this repo. One such outlier moves a mean by a third of the head-room, and it
# lands on a random side. So the two shapes are timed INTERLEAVED, one of each
# per iteration, and the ratio is taken between the MEDIANS — the same treatment
# `../bench.sh` gives them, and the reason it exists there.
#
# The corpus is 2000 lines, not bench.sh's 10 000, so the file stays under a few
# seconds; it is built with `kt_fixture_tmpdir_create` and torn down by the
# framework. This file installs NO `trap … EXIT` of its own — it would replace
# ktests' trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GNU BANNER GATE IS THE FIRST CASE, as in 005/006: this machine carries a
# non-GNU `grep` (Embarcadero) on PATH after the msys ones, and every number
# below is about GNU grep 3.0. Without the banner every timed case is a loud
# SKIP and the case COUNT is unchanged.
#
# Sections:
#   Z  the GNU banner gate and the corpus
#   A  the search gate — TGrep.search against a bare `grep -r`, and the
#      construction cost that IS the delta, measured on its own
#   B  the argv model: 22 typed options into a command line, running NOTHING
#   C  counting — the `count` sink and the `countOnly` shortcut against `grep -c`
#   D  zero forks, for every member of the surface plus `search`
#
# Timing primitive: TStopwatch.getTimeStamp — the shared fork-free us clock.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TG_DIR/tgrep.sh"
source "$TG_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: the PLAN §5 P3.1 performance gates (P3)"

NL=2000          # corpus lines
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
kt_test_start "the \`grep\` on PATH is GNU grep (D4 pins the DIALECT, not a binary)"
GREP_BIN="$(command -v grep 2>/dev/null || printf '(none)')"
GREP_VER="$(grep --version 2>/dev/null | head -1 || :)"
if [[ "$GREP_VER" == "grep (GNU grep) "* ]]; then
    GNU_OK=1
    kt_test_pass "$GREP_BIN — $GREP_VER"
else
    kt_test_pass "SKIP: non-GNU grep ($GREP_BIN — '${GREP_VER:-no banner}'); every timed case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so the case COUNT is the same on a box without GNU grep.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU grep"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create corpus)" && pwd)"
mkdir -p "$FX/tree/sub"
{
    for (( i = 0; i < NL; i++ )); do
        if (( i % 100 == 0 )); then
            printf 'line %d needle here\n' "$i"
        else
            printf 'line %d nothing here\n' "$i"
        fi
    done
} > "$FX/tree/big.txt"
printf 'line a needle here\nline b nothing here\n' > "$FX/tree/sub/small.txt"
TREE="$FX/tree"
SPARSE=$(( NL / 100 + 1 ))      # 21 hits: every 100th line, plus small.txt

# ===========================================================================
kt_test_section "A. the search gate — TGrep.search vs a bare \`grep -r\`"
# ===========================================================================

if tcase "TGrep.search costs at most 10x a bare \`grep -r\` (PLAN gate 1.3x)"; then
    # Warm both sides — the page cache and the first bind of the member wrappers
    # — and take the hit counts HERE, once. Counting inside the timed loop would
    # add a `$( )` and a `wc` fork to both sides and dilute the very ratio the
    # gate is about.
    nb="$(grep -r -e needle -- "$TREE" | wc -l)"
    nw="$(TGrep.search needle "$TREE" | wc -l)"

    declare -a T_GREP=() T_SEARCH=()
    for (( i = 0; i < NR; i++ )); do
        TStopwatch.getTimeStamp; t0=$RESULT
        grep -r -e needle -- "$TREE" >/dev/null || :
        TStopwatch.getTimeStamp; t1=$RESULT
        T_GREP+=( $(( t1 - t0 )) )

        TStopwatch.getTimeStamp; t0=$RESULT
        TGrep.search needle "$TREE" >/dev/null || :
        TStopwatch.getTimeStamp; t1=$RESULT
        T_SEARCH+=( $(( t1 - t0 )) )
    done
    median T_GREP;   m_grep="$MED";   (( m_grep > 0 )) || m_grep=1
    median T_SEARCH; m_search="$MED"
    lim=$(( m_grep * 10 ))
    r100=$(( m_search * 100 / m_grep ))
    if [[ "$nb" == "$SPARSE" && "$nw" == "$SPARSE" ]] && (( m_search <= lim )); then
        kt_test_pass "both found $SPARSE hits; grep median ${m_grep}us, search median ${m_search}us — ${r100}% (ceiling ${lim}us), $NR runs"
    else
        kt_test_fail "grep hits='$nb' search hits='$nw' (want $SPARSE); grep=${m_grep}us search=${m_search}us (${r100}%) ceiling=${lim}us"
    fi
fi

if tcase "the search delta IS one instance construction: new + delete under 50 ms"; then
    ND=20
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i = 0; i < ND; i++ )); do TGrep.new BC needle "$TREE"; BC.delete; done
    TStopwatch.getTimeStamp; t1=$RESULT
    per=$(( (t1 - t0) / ND ))
    # Idle: ~2.5 ms on both bashes; ~3.0 ms measured under the threaded runner.
    # The ceiling is 20x the idle figure for the same reason as the ratios above;
    # what it catches is a construction that grew an ORDER of magnitude — a fork,
    # or a re-`build` of the class per instance.
    if (( per <= 50000 )); then
        kt_test_pass "TGrep.new + .delete ${per}us/call over $ND calls (ceiling 50000us; ~2500us idle)"
    else
        kt_test_fail "TGrep.new + .delete ${per}us/call over $ND calls (ceiling 50000us)"
    fi
fi

# ===========================================================================
kt_test_section "B. the argv model runs NOTHING and forks nothing"
# ===========================================================================

ND=100
BENCH_RAN=0
BENCH_CMD_PID=''
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); BENCH_CMD_PID="$BASHPID"; return 0; }

kt_test_start "$(( ND * 2 )) buildArgv/argv calls never invoke the cmd and never fork"
TGrep.new BG needle "$TREE"
BG.ignoreCase = 1
BG.recursive  = 1
BG.lineNumber = 1
BG.maxCount   = 8
BG.include    = '*.txt'
BG.cmd        = bench_counted
declare -a BW=()
p0="$BASHPID"
for (( i = 0; i < ND; i++ )); do BG.buildArgv; done
n_build="$RESULT"
for (( i = 0; i < ND; i++ )); do BG.argv BW; done
n_argv="$RESULT"
want="bench_counted -i -r -n -m 8 --include=*.txt -e needle -- $TREE"
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$n_build" == "11" && "$n_argv" == "11" \
      && "${BW[*]}" == "$want" && "${#BW[@]}" == "11" ]]; then
    kt_test_pass "cmd invoked 0 times in $(( ND * 2 )) builds, BASHPID $p0 unchanged, 11 words in the pinned order"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID buildArgv='$n_build' argv='$n_argv' words=(${BW[*]})"
fi

kt_test_start "the 22-option build stays constant-cost: $ND rebuilds do not accumulate words"
declare -a BW2=()
BG.argv BW2
if [[ "${#BW2[@]}" == "11" && "${BW2[*]}" == "$want" && "$RESULT" == "11" ]]; then
    kt_test_pass "still 11 words after $(( ND * 2 + 1 )) rebuilds"
else
    kt_test_fail "n=${#BW2[@]} RESULT='$RESULT' words=(${BW2[*]})"
fi
BG.delete

# ===========================================================================
kt_test_section "C. counting — the sink and the countOnly shortcut vs \`grep -c\`"
# ===========================================================================

if tcase "g.count costs at most 10x \`grep -c\` on the same tree (measured 1.47x)"; then
    TGrep.new BQ  needle "$TREE"; BQ.recursive  = 1
    TGrep.new BQC needle "$TREE"; BQC.recursive = 1; BQC.countOnly = 1
    declare -a BCARR=() T_GC=() T_CNT=() T_CO=()

    grep -c -r -e needle -- "$TREE" >/dev/null 2>&1 || :
    BQ.count          >/dev/null 2>&1 || :
    BQC.toArray BCARR >/dev/null 2>&1 || :

    n_sparse=''; n_conly=''
    for (( i = 0; i < NR; i++ )); do
        TStopwatch.getTimeStamp; t0=$RESULT
        grep -c -r -e needle -- "$TREE" >/dev/null || :
        TStopwatch.getTimeStamp; t1=$RESULT
        T_GC+=( $(( t1 - t0 )) )

        TStopwatch.getTimeStamp; t0=$RESULT
        BQ.count || :
        n_sparse="$RESULT"
        TStopwatch.getTimeStamp; t1=$RESULT
        T_CNT+=( $(( t1 - t0 )) )

        TStopwatch.getTimeStamp; t0=$RESULT
        BQC.toArray BCARR || :
        n_conly="$RESULT"
        TStopwatch.getTimeStamp; t1=$RESULT
        T_CO+=( $(( t1 - t0 )) )
    done
    median T_GC;  m_gc="$MED"; (( m_gc > 0 )) || m_gc=1
    median T_CNT; m_cnt="$MED"
    median T_CO;  m_co="$MED"
    lim=$(( m_gc * 10 ))
    r100=$(( m_cnt * 100 / m_gc ))
    if [[ "$n_sparse" == "$SPARSE" ]] && (( m_cnt <= lim )); then
        kt_test_pass "count $n_sparse records; grep -c median ${m_gc}us, g.count median ${m_cnt}us — ${r100}% (ceiling ${lim}us)"
    else
        kt_test_fail "RESULT='$n_sparse' (want $SPARSE) grep -c=${m_gc}us g.count=${m_cnt}us (${r100}%) ceiling=${lim}us"
    fi

    kt_test_start "countOnly=1 delivers grep's OWN numbers in 2 records, at most 10x \`grep -c\`"
    lim=$(( m_gc * 10 ))
    r100=$(( m_co * 100 / m_gc ))
    # grep's walk order over a directory is not ours to pin, so the two records
    # are compared as a SET.
    declare -a CO_SORT=()
    mapfile -t CO_SORT < <( printf '%s\n' "${BCARR[@]}" | sort )
    ok=0
    if [[ "$n_conly" == "2" && "${CO_SORT[0]}" == "$TREE/big.txt:$(( NL / 100 ))" \
          && "${CO_SORT[1]}" == "$TREE/sub/small.txt:1" ]]; then
        ok=1
    fi
    if (( ok == 1 )) && (( m_co <= lim )); then
        kt_test_pass "2 records (${BCARR[*]}); median ${m_co}us — ${r100}% of grep -c (ceiling ${lim}us)"
    else
        kt_test_fail "RESULT='$n_conly' records=(${BCARR[*]}) median=${m_co}us (${r100}%) ceiling=${lim}us"
    fi
    BQ.delete; BQC.delete
else
    # the gate is closed: keep the case count identical
    kt_test_start "countOnly=1 delivers grep's OWN numbers in 2 records, at most 10x \`grep -c\`"
    kt_test_pass "SKIP: non-GNU grep"
fi

# ===========================================================================
kt_test_section "D. zero forks — every member, \`search\`, the callback and .Add"
# ===========================================================================

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TFork007
    public
        constructor Create
        proc        Add
end
TFork007.Create() { return 0; }
TFork007.Add()    { ADDPIDS+=( "$BASHPID" ); return 0; }
build TFork007
TFork007.new F7

if tcase "the five sinks: the callback and \`.Add\` run in THIS process"; then
    TGrep.new FG needle "$TREE/sub/small.txt"
    p0=$BASHPID
    CBPIDS=(); ADDPIDS=()
    declare -a FARR=()
    FG.each    pid_cb; rc1=$?
    FG.toList  F7;     rc2=$?; n_list="$RESULT"
    FG.toArray FARR;   rc3=$?; n_arr="$RESULT"
    FG.count;          rc4=$?; n_cnt="$RESULT"
    FG.first 2>/dev/null; rc5=$?; first="$RESULT"
    ok=1
    for pid in "${CBPIDS[@]}" "${ADDPIDS[@]}"; do
        [[ "$pid" == "$p0" ]] || ok=0
    done
    if (( ok == 1 && ${#CBPIDS[@]} == 1 && ${#ADDPIDS[@]} == 1 )) \
       && [[ "$BASHPID" == "$p0" && $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 && $rc5 -eq 0 \
             && "$n_list" == "1" && "$n_arr" == "1" && "$n_cnt" == "1" && "$first" == "line a needle here" ]]; then
        kt_test_pass "1 record per sink, callback and .Add both in pid $p0"
    else
        kt_test_fail "ok=$ok rc=$rc1/$rc2/$rc3/$rc4/$rc5 list='$n_list' arr='$n_arr' cnt='$n_cnt' first='$first' cb=(${CBPIDS[*]}) add=(${ADDPIDS[*]})"
    fi
    FG.delete
fi

if tcase "the ONLY fork per call is grep: the seven builder members fork nothing"; then
    TGrep.new FB needle "$TREE/sub/small.txt"
    p0=$BASHPID
    declare -a FW=()
    ok=1
    FB.buildArgv                       ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.argv FW                         ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.paths "$TREE/sub/small.txt"     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.addArg                          ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearArgs                       ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.mapRc 2 2>/dev/null             ; m2="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.lastRc                          ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.run >/dev/null; rcr=$?          ; [[ "$BASHPID" == "$p0" ]] || ok=0
    TGrep.search needle "$TREE/sub/small.txt" >/dev/null; rcs=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    if (( ok == 1 )) && [[ "$m2" == "1" && $rcr -eq 0 && $rcs -eq 0 ]]; then
        kt_test_pass "BASHPID $p0 unchanged across seven builder members, run and search"
    else
        kt_test_fail "ok=$ok mapRc2='$m2' run rc=$rcr search rc=$rcs ours=$p0 now=$BASHPID"
    fi
    FB.delete
fi

F7.delete

kt_test_log "007_Bench.sh completed"
