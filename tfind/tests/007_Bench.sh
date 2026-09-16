#!/bin/bash
# 007_Bench.sh — tfind P1: the PLAN.md §5 P1 performance gate, as assertions.
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   PLAN §5 P1 gate: `TFind.byName '*.txt' TREE` <= **1.5x** a bare
#   `find TREE -name '*.txt'` over the same corpus, from the MEDIANS of 21
#   INTERLEAVED runs. Those are the numbers README.md §10 publishes.
#
#   THIS FILE asserts the same shapes with a ceiling of **10x** — because ktests
#   runs test files THREADED, 8 workers by default, and the two sides of that
#   ratio do NOT inflate together under that load: the bare `find` is its own
#   process and roughly doubles, while the wrapper's share is bash work in the
#   contended shell and has been seen to grow tenfold (the same effect the tgrep
#   007 header records, where a threaded run read 4.18x and the next 1.16x on
#   identical code). A ceiling set at 3x the idle measurement would flake for a
#   reason that has nothing to do with this unit; 10x still catches every
#   regression the gate exists for — an instance constructed per RECORD instead
#   of per call, a `$( )` around the producer, a second `find` process per call
#   — each of which costs orders of magnitude, not tens of percent.
#
# MEDIANS, AND WHY THEY ARE NOT NEGOTIABLE. Every number here is one PROCESS
# START plus a walk, and on this platform a process start occasionally takes
# several hundred milliseconds for reasons outside this repo. One such outlier
# moves a mean by more than the whole head-room, and it lands on a random side.
# The WORST SINGLE PAIRING measured while this unit was planned read **1.64x**
# on code whose interleaved medians are 1.13-1.16x (PLAN §8 finding 17) — a
# one-shot comparison would have failed a 1.5x gate on code that is fine. So the
# two shapes are timed INTERLEAVED, one of each per iteration, and the ratio is
# taken between the MEDIANS — the same treatment `../bench.sh` gives them.
#
# THE CLOCK IS `TStopwatch.getTimeStamp`, never `date +%s%N`: on msys the latter
# is its own process and costs ~20 ms per call — more than half of the `find`
# run being measured, paid twice per sample.
#
# WHY CORPUS SIZE IS NOT THE KNOB. A whole `find` run — one msys process start
# plus the walk — costs ~32 ms here; the wrapper's entire fixed delta
# (`new` + `name =` + `argv` + `delete`, NINE properties assigned by the
# constructor) is ~4.7 ms and is paid once per CALL. The ratio is therefore
# ~(32 + 4.7)/32 — it sits near 1.15x and can only fall as the walk grows. This
# file uses a 20-file tree, not bench.sh's 400, purely to stay under a few
# seconds; the ratio does not care, and the ONE-file shape below is here to show
# exactly that.
#
# The corpus is built with `kt_fixture_tmpdir_create` and torn down by the
# framework. This file installs NO `trap … EXIT` of its own — it would replace
# ktests' trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GNU BANNER GATE IS THE FIRST CASE, as in 005/006: D4 pins the DIALECT
# (GNU findutils 4.10.0), not a binary. Without the banner every timed case is a
# loud SKIP and the case COUNT is unchanged.
#
# Sections:
#   Z  the GNU banner gate and the corpus
#   A  the byName gate — `TFind.byName` against a bare `find … -name` in the two
#      shapes that bracket the tool's own work (a 20-file tree and a ONE-file
#      tree), plus the wrapper's fixed delta measured on its own
#   B  the argv model: typed options into a command line, running NOTHING — and
#      the rc 2 path, which runs nothing either
#   C  counting — the `count` sink against the `tr -dc '\0' | wc -c` equivalent
#   D  zero forks, for every member of the surface plus `byName` and a refusal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TF_DIR/tfind.sh"
source "$TF_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: the PLAN §5 P1 performance gate (P1)"

NDIR=5           # sub-directories in the small tree
NF=4             # .txt files each -> NTXT matches
NTXT=$(( NDIR * NF ))
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
kt_test_start "the \`find\` on PATH is GNU findutils (D4 pins the DIALECT, not a binary)"
FIND_BIN="$(command -v find 2>/dev/null || printf '(none)')"
FIND_VER="$(find --version 2>/dev/null | sed -n 1p || :)"
if [[ "$FIND_VER" == "find (GNU findutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$FIND_BIN — $FIND_VER"
else
    kt_test_pass "SKIP: non-GNU find ($FIND_BIN — '${FIND_VER:-no banner}'); every timed case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so the case COUNT is the same on a box without GNU findutils.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU find"
        return 1
    fi
    return 0
}

FX="$(cd "$(kt_fixture_tmpdir_create corpus)" && pwd)"
BIG="$FX/tree"
ONE="$FX/one"
mkdir -p "$BIG" "$ONE"
for (( d = 0; d < NDIR; d++ )); do
    printf -v dn '%s/d%02d' "$BIG" "$d"
    mkdir -p "$dn"
    for (( f = 0; f < NF; f++ )); do
        printf -v fn '%s/f%02d.txt' "$dn" "$f"
        printf 'x\n' > "$fn"
    done
    printf 'x\n' > "$dn/skip.dat"        # so `-name '*.txt'` really filters
done
printf 'x\n' > "$ONE/only.txt"

# ===========================================================================
kt_test_section "A. the byName gate — TFind.byName vs a bare \`find … -name\`"
# ===========================================================================

# gate_case TREE LABEL EXPECTED_RECORDS — the interleaved-median assertion with
# a 10x ceiling.
gate_case() {
    local __tree="$1" __label="$2" __want="$3"
    if ! tcase "TFind.byName over $__label costs at most 10x a bare \`find … -name\` (PLAN gate 1.5x)"; then
        return 0
    fi
    # Warm both sides — the directory cache and the first bind of the member
    # wrappers — and take the record counts HERE, once. Counting inside the
    # timed loop would add a `$( )` and a `wc` fork to both sides and dilute the
    # very ratio the gate is about.
    local __nb __nw
    __nb="$( find "$__tree" -name '*.txt' | wc -l )"; __nb="${__nb//[[:space:]]/}"
    __nw="$( TFind.byName '*.txt' "$__tree" | wc -l )"; __nw="${__nw//[[:space:]]/}"

    local -a __t_bare=() __t_by=()
    local __i __a0 __a1
    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        find "$__tree" -name '*.txt' >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) )

        TStopwatch.getTimeStamp; __a0=$RESULT
        TFind.byName '*.txt' "$__tree" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_by+=( $(( __a1 - __a0 )) )
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_by;   local __m_by="$MED"
    local __lim=$(( __m_bare * 10 ))
    local __r100=$(( __m_by * 100 / __m_bare ))
    if [[ "$__nb" == "$__want" && "$__nw" == "$__want" ]] && (( __m_by <= __lim )); then
        kt_test_pass "both delivered $__want records; find median ${__m_bare}us, byName median ${__m_by}us — ${__r100}% (ceiling ${__lim}us), $NR runs"
    else
        kt_test_fail "find records='$__nb' byName records='$__nw' (want $__want); find=${__m_bare}us byName=${__m_by}us (${__r100}%) ceiling=${__lim}us"
    fi
}

gate_case "$BIG" "a $NTXT-file tree" "$NTXT"
gate_case "$ONE" "a ONE-file tree"   1

if tcase "the byName delta IS one instance: new + name + argv + delete under 50 ms"; then
    ND=20
    declare -a BV=()
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i = 0; i < ND; i++ )); do
        TFind.new BC "$BIG"
        BC.name = '*.txt'
        BC.argv BV
        BC.delete
    done
    TStopwatch.getTimeStamp; t1=$RESULT
    per=$(( (t1 - t0) / ND ))
    # Idle: ~4.7 ms on both bashes — nine properties assigned by the constructor
    # where thead's assigns six (3.1-3.3 ms). The ceiling is an order of
    # magnitude above that, for the same reason as the ratios above; what it
    # catches is a construction that grew an ORDER of magnitude — a fork, or a
    # re-`build` of the class per instance.
    if (( per <= 50000 )); then
        kt_test_pass "new + name + argv + delete ${per}us/call over $ND calls (ceiling 50000us; ~4700us idle)"
    else
        kt_test_fail "new + name + argv + delete ${per}us/call over $ND calls (ceiling 50000us)"
    fi
fi

# ===========================================================================
kt_test_section "B. the argv model runs NOTHING and forks nothing"
# ===========================================================================

ND=100
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }

kt_test_start "$(( ND * 2 )) buildArgv/argv calls never invoke the cmd and never fork"
TFind.new BF "$BIG"
BF.name = '*.txt'
BF.type = f
BF.maxDepth = 9
BF.cmd = bench_counted
declare -a BW=()
p0="$BASHPID"
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
n_build="$RESULT"
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
n_argv="$RESULT"
want="bench_counted $BIG -maxdepth 9 -name *.txt -type f"
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$n_build" == "8" && "$n_argv" == "8" \
      && "${BW[*]}" == "$want" && "${#BW[@]}" == "8" ]]; then
    kt_test_pass "cmd invoked 0 times in $(( ND * 2 )) builds, BASHPID $p0 unchanged, 8 words in the pinned order"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID buildArgv='$n_build' argv='$n_argv' words=(${BW[*]})"
fi

kt_test_start "the build stays constant-cost: $ND rebuilds do not accumulate words"
declare -a BW2=()
BF.argv BW2
if [[ "${#BW2[@]}" == "8" && "${BW2[*]}" == "$want" && "$RESULT" == "8" ]]; then
    kt_test_pass "still 8 words after $(( ND * 2 + 1 )) rebuilds"
else
    kt_test_fail "n=${#BW2[@]} RESULT='$RESULT' words=(${BW2[*]})"
fi
BF.delete

kt_test_start "a REFUSED build runs nothing and forks nothing either ($ND rc 2 calls)"
# The rc 2 path is the one a caller reaches by accident (a start point find would
# read as a predicate), and it must be the CHEAP path: no fork, no command.
BENCH_RAN=0
TFind.new BR '-weird'
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

# ===========================================================================
kt_test_section "C. counting — the \`count\` sink vs the \`tr -dc '\\0' | wc -c\` equivalent"
# ===========================================================================

# `tr -dc '\0' | wc -c` is the NUL-framed equivalent of `wc -l`: it counts the
# record TERMINATORS, so a name containing a newline still counts once. The
# comparison is not one-sided the way thead's `wc -l` row is: the shell
# equivalent needs THREE processes where the sink needs one, so at a small
# record count the SINK is the faster of the two and the ratio is well under 1.
# What this case is for is catching a per-record path that grew an ORDER of
# magnitude — a fork per record, a re-`build` per record — not a known constant,
# so the ceiling is 10x either way and `../bench.sh` publishes the real numbers.
if tcase "f.count over $NTXT records costs at most 10x \`find … -print0 | tr -dc '\\0' | wc -c\` (published, not the gate)"; then
    TFind.new BQ "$BIG"
    BQ.name = '*.txt'
    BQ.print0 = 1
    declare -a T_WC=() T_CNT=()
    n_wc="$( find "$BIG" -name '*.txt' -print0 | tr -dc '\0' | wc -c )"
    n_wc="${n_wc//[[:space:]]/}"
    BQ.count >/dev/null 2>&1 || :
    n_cnt=''
    for (( i = 0; i < NR; i++ )); do
        TStopwatch.getTimeStamp; t0=$RESULT
        find "$BIG" -name '*.txt' -print0 | tr -dc '\0' | wc -c >/dev/null || :
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
    if [[ "$n_wc" == "$NTXT" && "$n_cnt" == "$NTXT" ]] && (( m_cnt <= lim )); then
        kt_test_pass "both counted $NTXT; pipeline median ${m_wc}us, f.count median ${m_cnt}us — ${r100}% (ceiling ${lim}us)"
    else
        kt_test_fail "pipeline='$n_wc' count='$n_cnt' (want $NTXT) pipeline=${m_wc}us count=${m_cnt}us (${r100}%) ceiling=${lim}us"
    fi
    BQ.delete
fi

# ===========================================================================
kt_test_section "D. zero forks — every member, \`byName\`, a refusal, the callback and .Add"
# ===========================================================================

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TForkTF007
    public
        var         N
        constructor Create
        proc        Add
end
TForkTF007.Create() { N=0; return 0; }
TForkTF007.Add()    { N=$(( N + 1 )); ADDPIDS+=( "$BASHPID" ); return 0; }
build TForkTF007
TForkTF007.new F7

if tcase "the five sinks: the callback and \`.Add\` run in THIS process"; then
    TFind.new FH "$ONE"
    FH.print0 = 1
    FH.type = f
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
             && "$n_list" == "1" && "$n_arr" == "1" && "$n_cnt" == "1" && "$first" == "$ONE/only.txt" ]]; then
        kt_test_pass "1 record per sink, callback and .Add both in pid $p0"
    else
        kt_test_fail "ok=$ok rc=$rc1/$rc2/$rc3/$rc4/$rc5 list='$n_list' arr='$n_arr' cnt='$n_cnt' first='$first' cb=(${CBPIDS[*]}) add=(${ADDPIDS[*]})"
    fi
    FH.delete
fi

if tcase "the ONLY fork per call is find: every builder member, \`byName\` and a refusal fork nothing"; then
    TFind.new FB "$ONE"
    p0=$BASHPID
    declare -a FW=()
    ok=1
    FB.name = '*.txt'             ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.type = f                   ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.maxDepth = 9               ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.minDepth = 0               ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.followSymlinks = 0         ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.buildArgv                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.argv FW                    ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.paths "$ONE"               ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.addArg                     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.clearArgs                  ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.mapRc 1 2>/dev/null        ; m1="$RESULT"; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.lastRc                     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    FB.run >/dev/null; rcr=$?     ; [[ "$BASHPID" == "$p0" ]] || ok=0
    TFind.byName '*.txt' "$ONE" >/dev/null; rct=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    TFind.new FR '-weird'
    rcx=0; FR.count 2>/dev/null || rcx=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    rcy=0; TFind.byName '*.txt' 2>/dev/null || rcy=$?
    [[ "$BASHPID" == "$p0" ]] || ok=0
    if (( ok == 1 )) && [[ "$m1" == "1" && $rcr -eq 0 && $rct -eq 0 && $rcx -eq 2 && $rcy -eq 2 ]]; then
        kt_test_pass "BASHPID $p0 unchanged across twelve builder members, run, byName and both rc 2 paths"
    else
        kt_test_fail "ok=$ok mapRc1='$m1' run rc=$rcr byName rc=$rct refusedCount rc=$rcx refusedByName rc=$rcy ours=$p0 now=$BASHPID"
    fi
    FR.delete
    FB.delete
fi

F7.delete

kt_test_log "007_Bench.sh completed"
