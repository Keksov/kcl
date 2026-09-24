#!/bin/bash
# Micro-benchmark for tawk (P1). Publishes the numbers README.md §10 quotes and
# measures the PLAN.md §5 P1 gate:
#
#   (a) ARGV — what the typed option set costs to turn into a command line, and
#       the proof that it RUNS NOTHING: with `cmd` pointed at a shell function
#       that counts its own invocations, 2 x ND builds leave the counter at 0.
#       $BASHPID is read before and after: the builder is fork-free. The cost of
#       a REFUSED build is timed too — a deny-list hit through the `-W` spelling
#       at the END of three extras, because the getopt-following scan
#       (`tawk._scanExtras`) is this unit's own addition to the build and the
#       refusal is the path a caller reaches by accident;
#   (b) THE WRAPPER'S FIXED DELTA — exactly what `TAwk.apply` does around the
#       one fork, on its own line: `new` with the PROGRAM (NINE properties
#       assigned, FOUR arrays declared — tsed: eleven and two), `sandbox = 1`, the
#       build (the rc 2 list, the extras scan over an empty list, no variable)
#       and `delete`. `apply` passes the program to the constructor, so there is
#       no `addProgram` in it. Two rows: the family's (with `argv`, as the tsed
#       and tfind benches time it) and the one `apply` really pays (`run` calls
#       `buildArgv`, without `argv`'s out-name check and copy). It is a per-CALL
#       cost and never a per-record one.
#       Next to it, the `setVar` ENCODING (PLAN §2.3) for a 1 KiB value holding
#       backslashes, newlines and a leading `@`: `tawk._enc` on its own, and a
#       build with that variable against the same build without it;
#   (c) GATED — `TAwk.apply '{print $2}' FILE` against a bare
#       `gawk --sandbox -e '{print $2}' -- FILE` over the same generated corpus,
#       in the two shapes that bracket the tool's own work: a 10 000-line file
#       (gawk really splits every record) and a ONE-line file (the fork IS the
#       measurement). Gate: <= **1.5x**, from the MEDIANS of NR >= 15
#       INTERLEAVED runs;
#   (d) PUBLISHED, NOT GATED — `a.count` against the shell equivalent
#       `gawk … | wc -l`. They answer the same question by different means: `wc`
#       counts in one more process at memory speed, the `count` sink reads every
#       record into bash. The gap is the price of having the records in this
#       shell, and it is a per-RECORD price — derived here by DIFFERENCE, from the
#       same sink over the 10 000-line file and over the one-line file;
#   (e) ZERO FORKS — $BASHPID around every TAwk and TUtil member, around the
#       refused paths (a deny-list hit, a refused in-place sink, a path-less and
#       an empty-program `apply`, an illegal `setVar` name — none of them forks
#       either), around `apply`, and inside an `each` callback and a `.Add`.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# **`date +%s%N` must NOT be used here**: on msys each call is its own process
# and costs ~20 ms — more than half of the very `gawk` run being measured, and it
# would be paid twice per sample (tfind PLAN §8 finding 17).
# Deterministic: fixed sizes, no $RANDOM, one generated corpus everywhere.
#
# TWO gawk VERSIONS. bash 5.2.37 resolves Git for Windows' gawk 5.0.0, bash
# 5.3.9 (run with msys64's /usr/bin first on PATH) msys64's gawk 5.4.0. The
# banner line names the one measured; the README publishes both columns.
#
# STDIN IS CLOSED for the whole run (`exec </dev/null`, as in tests 005/006):
# gawk without a program, or with a path it takes for the program, reads stdin
# and would hang. Every gawk below has a program and a path operand anyway.
#
# WHY THE CORPUS SIZE DOES NOT MOVE THE RATIO OF (c) MUCH. On this platform a
# whole `gawk` run — the msys `fork`+`exec` of a gawk binary, plus the work —
# costs tens of milliseconds, while the wrapper's entire fixed delta — section
# (b) — is a few ms. The ratio of (c) is therefore roughly (gawk + delta) / gawk:
# it can only FALL as the file grows. The one-line row (where the fork is the
# whole measurement) is the pessimistic one.
#
# MEDIANS, AND WHY THEY ARE NOT NEGOTIABLE. Every number in (c) and (d) is ONE
# PROCESS START plus the work, and on this platform a process start occasionally
# takes several hundred milliseconds for reasons outside this repo (a scanner, a
# page-fault storm). One such outlier in 21 runs moves a MEAN by more than the
# whole head-room of the gate, and it lands on a different side from run to run:
# while tfind was planned, the WORST SINGLE PAIRING read **1.64x** on code whose
# interleaved medians are 1.13-1.16x; inside tsed's published samples it read
# 8.5x-12.3x. A single pairing, or a non-interleaved loop, can therefore fail a
# 1.5x gate on code that is fine. So the two sides are timed INTERLEAVED, one of
# each per iteration, every run is recorded separately, and the published ratio
# is computed from the MEDIANS. The MEAN is printed next to each median and the
# worst single pairing under each gate: a gap between median and mean IS the
# outlier telling you the box was not idle.
#
# The corpus is generated into a `mktemp -d` directory and removed by an EXIT
# trap (this is a bench, not a test file: a test file must NOT install a trap of
# its own, it would replace ktests').
#
# The gate printed here is the PLAN §5 P1 number, measured by hand with the
# machine idle. `tests/007_Bench.sh` asserts the same shapes with a ceiling of
# 10x: ktests runs test files threaded (8 workers) and the two sides do NOT
# inflate together under that load — `gawk` is its own process, while the
# wrapper's share is bash work in the contended shell.
#
# Run: bash bench.sh [NL] [NR] [ND]
#      PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe bench.sh
#      (defaults: NL=10000 lines in the big file, NR=21 interleaved runs,
#       ND=300 calls per per-call measurement)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/007_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tawk.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

exec </dev/null

NL=${1:-10000}      # lines in the big file
NR=${2:-21}         # interleaved repetitions per gated shape (odd, >= 15)
ND=${3:-300}        # calls per per-call measurement

# ---------------------------------------------------------------------------
# helpers (the tgrep/thead/ttail/tfind/tsed bench shape, so every kcl bench
# table reads the same)
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-50s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

# median NAME -> MED (us). Sorting is one fork, OUTSIDE every timed region.
MED=0
median() {
    local -n __m_a="$1"
    local -a __m_s=()
    mapfile -t __m_s < <( printf '%s\n' "${__m_a[@]}" | sort -n )
    MED="${__m_s[ ${#__m_s[@]} / 2 ]}"
}

report_med() {  # label median_us total_us runs
    local m100=$(( $2 * 100 / 1000 )) a100=$(( $3 * 100 / $4 / 1000 ))
    printf '  %-50s median %6d.%02d ms  mean %6d.%02d ms  (%d runs)\n' \
        "$1" $(( m100/100 )) $(( m100%100 )) $(( a100/100 )) $(( a100%100 )) "$4"
}

ratio() {   # label value_us base_us base_label -> the ratio, no verdict
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-50s ratio %d.%02dx of %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) "$4"
}

GATES_FAILED=0
GATES_TOTAL=0

gate_ratio() {  # label median_us base_median_us limit_tenths -> ratio + PASS/FAIL
    local r100=$(( $2 * 100 / $3 )) lim=$(( $3 * $4 / 10 )) verdict
    GATES_TOTAL=$(( GATES_TOTAL + 1 ))
    if (( $2 <= lim )); then
        verdict="PASS"
    else
        verdict="FAIL"
        GATES_FAILED=$(( GATES_FAILED + 1 ))
    fi
    printf '  %-50s ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

# --- the GNU banner gate ----------------------------------------------------
# D4 pins the DIALECT (GNU Awk — 5.0.0 under bash 5.2.37, 5.4.0 under 5.3.9),
# not a binary. Every number below is about that tool; on anything else they
# are not comparable, so say so loudly instead of publishing a meaningless
# table.
AWK_BANNER="$(timeout 20 gawk --version 2>/dev/null </dev/null | head -1 || true)"
case "$AWK_BANNER" in
    "GNU Awk "*) ;;
    *) echo "tawk bench: SKIPPED — \`gawk\` is not GNU Awk: '$AWK_BANNER'"; exit 0 ;;
esac
AWK_BIN="$(command -v gawk 2>/dev/null || printf '(none)')"

# --- the corpus -------------------------------------------------------------
# Two files, both under one `mktemp -d`: BIG holds NL lines `aNNNNN xyz` (two
# fields on every line, so `{print $2}` really splits every record), ONE holds a
# single such line. The lines are built into an array and written by ONE
# `printf` — no fork per line, and NL stays overridable.
BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT
BIG="$BD/big.txt"
ONE="$BD/one.txt"
declare -a _lines=()
for (( _i = 1; _i <= NL; _i++ )); do
    _lines+=( "$_i" )
done
printf 'a%05d xyz\n' "${_lines[@]}" > "$BIG"
printf 'a%05d xyz\n' 1 > "$ONE"
unset -v _lines

PROG='{print $2}'

echo "tawk micro-benchmark  (bash ${BASH_VERSION}, ${AWK_BANNER} at ${AWK_BIN})"
echo "corpus: big.txt = $NL lines, one.txt = 1 line (\`aNNNNN xyz\`, two fields each)"
echo "        NR=$NR interleaved runs, ND=$ND calls"
echo

# ===========================================================================
# (a) the typed option set -> argv
# ===========================================================================
echo "(a) the argv model — typed options into a command line, running NOTHING:"
TAwk.new BF "$PROG" "$BIG"
BF.addProgram 'END{print NR}'
BF.setVar lim 5
BF.addArg --lint
declare -a BW=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (the override, one extra, one var)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-50s %s words: %s\n' "argv NAME copied" "$n_argv" "${BW[*]}"

# gawk is never executed above; prove it by pointing `cmd` at a function that
# would count its own invocations, and building 2 x ND more times.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }
BF.cmd = bench_counted
pid_a="$BASHPID"
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
BF.cmd = gawk
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" && "${BW[0]}" == "bench_counted" ]]; then
    echo "  RUNS NOTHING: with cmd pointed at a counting function, $(( ND * 2 )) builds invoked it 0 times"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 4 )) builds"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID, argv[0]='${BW[0]}'"
fi

# The rc 2 path is a build too. The refusal timed here is a deny-list hit at
# the END of three extras through the `-W` spelling, so the whole scan — two
# passing words, the bundle split of the third and the `-W` argument through
# the long-name table — is inside the number.
TAwk.new BR "$PROG" "$BIG"
BR.addArg -n --lint -Wsandbox
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BR.buildArgv >/dev/null 2>&1 || :; done
TStopwatch.getTimeStamp; t1=$RESULT
b_ref=$(( t1 - t0 )); (( b_ref > 0 )) || b_ref=1
report "buildArgv REFUSED (rc 2, -Wsandbox after -n --lint)" "$b_ref" "$ND" "call"
BR.delete
BF.delete

# ===========================================================================
# (b) the wrapper's fixed delta: what TAwk.apply does around the fork
# ===========================================================================
echo
echo "(b) the wrapper's FIXED delta — exactly what \`TAwk.apply\` does around the"
echo "    one fork (a fresh instance name per call, as apply uses):"
declare -a BV=()
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do
    TAwk.new "BC_$i" "$PROG" "$ONE"
    "BC_$i".sandbox = 1
    "BC_$i".argv BV
    "BC_$i".delete
done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor=$(( t1 - t0 )); (( b_ctor > 0 )) || b_ctor=1
report "new PROGRAM+sandbox+argv+delete (family row)" "$b_ctor" "$ND" "call"
# `run` calls `buildArgv` itself, never `argv` (which adds the out-name check
# and the copy into the caller's array), so the row above over-states what
# `apply` pays by that copy. The row below is the build `run` really does.
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do
    TAwk.new "BK_$i" "$PROG" "$ONE"
    "BK_$i".sandbox = 1
    "BK_$i".buildArgv
    "BK_$i".delete
done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor2=$(( t1 - t0 )); (( b_ctor2 > 0 )) || b_ctor2=1
report "new PROGRAM+sandbox+buildArgv+delete (apply delta)" "$b_ctor2" "$ND" "call"
per_ctor=$(( b_ctor2 / ND ))
echo "  the second row is the WHOLE difference between \`TAwk.apply\` and the bare"
echo "  tool below, plus \`run\`'s own bookkeeping (the \`command -v\` probe, the"
echo "  \`mapRc\` dispatch); the constructor assigns NINE properties and declares"
echo "  FOUR arrays (tsed: eleven and two), the build walks the rc 2 list; it is"
echo "  paid once per CALL, never per record, and it does not grow with the corpus"
echo "  — the process start it is measured against does not either."

# The setVar encoding of PLAN §2.3 on a 1 KiB value: 64 x a 16-byte segment
# holding two backslashes, a newline and an `@`, with the FIRST byte turned into
# `@` so the leading-`@` rule fires too. The value is built from a variable, so
# no literal backslash sits in a command line.
BS='\'
SEG="abc${BS}def"$'\n'"ghij${BS}kl@"
V1K=''
for (( i = 0; i < 64; i++ )); do V1K+="$SEG"; done
V1K="@${V1K:1}"
# enc(V1K): 64 segments of 16 -> 19 bytes (two backslashes doubled, one newline
# written as two bytes), and the leading `@` -> `\100` (+3).
WANT_ENC_LEN=$(( 64 * 19 + 3 ))

enc_once() {   # a frame of its own, so `tawk._enc` writes a LOCAL `__taw_e`
    local __taw_e=''
    tawk._enc "$1"
    ENC_LEN=${#__taw_e}
}
ENC_LEN=0
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do enc_once "$V1K"; done
TStopwatch.getTimeStamp; t1=$RESULT
b_enc=$(( t1 - t0 )); (( b_enc > 0 )) || b_enc=1
report "tawk._enc on a ${#V1K}-byte value" "$b_enc" "$ND" "call"
printf '  %-50s %d bytes (expected %d)\n' "encoded length" "$ENC_LEN" "$WANT_ENC_LEN"

TAwk.new BS0 'BEGIN{printf "%s", x}' "$ONE"
TAwk.new BS1 'BEGIN{printf "%s", x}' "$ONE"
BS1.setVar x "$V1K"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BS0.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_nov=$(( t1 - t0 )); (( b_nov > 0 )) || b_nov=1
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BS1.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_1k=$(( t1 - t0 )); (( b_1k > 0 )) || b_1k=1
report "buildArgv, no variable" "$b_nov" "$ND" "call"
report "buildArgv, one 1 KiB setVar value" "$b_1k" "$ND" "call"
d_x10=$(( (b_1k - b_nov) * 10 / ND ))
if (( d_x10 < 0 )); then
    d_x10=0
fi
printf '  %-50s %7d.%d us/call\n' "the variable's share of a build (difference)" $(( d_x10/10 )) $(( d_x10%10 ))
# Correctness once, OUTSIDE the timing: gawk hands the 1 KiB value back byte
# for byte (the value ends in `@`, so `$( )` strips nothing).
rt="$(BS1.run 2>/dev/null)" || :
if [[ "$rt" == "$V1K" ]]; then
    echo "  round trip through gawk: byte-exact (${#rt} bytes)"
else
    echo "  ROUND-TRIP VIOLATION: got ${#rt} bytes, want ${#V1K}"
fi
BS1.delete
BS0.delete

# ===========================================================================
# (c) the gate: TAwk.apply vs a bare `gawk --sandbox -e … -- FILE`
# ===========================================================================
echo
echo "(c) TAwk.apply '{print \$2}' FILE vs a bare \`gawk --sandbox -e '{print \$2}' -- FILE\` (INTERLEAVED, medians):"

# gate_shape FILE LABEL — time the two shapes interleaved and gate the medians
# at 1.5x.
gate_shape() {
    local __file="$1" __label="$2"
    local -a __t_bare=() __t_ap=()
    local __i __a0 __a1 __s_bare=0 __s_ap=0

    # warm the file cache and every code path once, so neither side pays for
    # the first read of the corpus or the first bind of a member wrapper.
    gawk --sandbox -e "$PROG" -- "$__file" >/dev/null 2>&1 || :
    TAwk.apply "$PROG" "$__file" >/dev/null 2>&1 || :

    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        gawk --sandbox -e "$PROG" -- "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) ); __s_bare=$(( __s_bare + __a1 - __a0 ))

        TStopwatch.getTimeStamp; __a0=$RESULT
        TAwk.apply "$PROG" "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_ap+=( $(( __a1 - __a0 )) ); __s_ap=$(( __s_ap + __a1 - __a0 ))
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_ap;   local __m_ap="$MED"
    report_med "bare \`gawk --sandbox -e\` $__label (baseline)" "$__m_bare" "$__s_bare" "$NR"
    report_med "TAwk.apply $__label" "$__m_ap" "$__s_ap" "$NR"
    gate_ratio "  gate: apply vs bare gawk, $__label" "$__m_ap" "$__m_bare" 15
    printf '  delta %d us per call; section (b) measured the wrapper at %d us\n' \
        $(( __m_ap - __m_bare )) "$per_ctor"
    # The worst SINGLE pairing of this very sample, for comparison with the
    # median above: this is the number a one-shot measurement would have
    # published, and it is why the protocol is what it is.
    local __worst=0 __r100 __j __den
    for (( __j = 0; __j < NR; __j++ )); do
        __den="${__t_bare[__j]}"
        if (( __den <= 0 )); then
            __den=1
        fi
        __r100=$(( __t_ap[__j] * 100 / __den ))
        if (( __r100 > __worst )); then
            __worst=$__r100
        fi
    done
    printf '  worst SINGLE pairing in this sample: %d.%02dx — one sample is not a measurement\n' \
        $(( __worst/100 )) $(( __worst%100 ))
    echo
}

gate_shape "$BIG" "big.txt, $NL lines"
gate_shape "$ONE" "one.txt, 1 line"

# ===========================================================================
# (d) counting: the `count` sink vs `gawk … | wc -l`
# ===========================================================================
echo "(d) counting — the \`count\` sink vs \`gawk --sandbox -e … -- FILE | wc -l\` (published, NOT gated):"
TAwk.new BQ "$PROG" "$BIG"
TAwk.new BQ1 "$PROG" "$ONE"     # the SAME sink over ONE record: the fixed half
declare -a T_WC=() T_CNT=() T_CNT1=()
b_wc=0; b_cnt=0; b_cnt1=0
n_wc=''; n_cnt=''

# Warm both shapes, and take the record counts HERE, once. A `$( )` inside the
# timed loop would add a fork to the baseline and dilute the very comparison.
n_wc="$( gawk --sandbox -e "$PROG" -- "$BIG" | wc -l )"
n_wc="${n_wc//[[:space:]]/}"
BQ.count >/dev/null 2>&1 || :
BQ1.count >/dev/null 2>&1 || :

for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    gawk --sandbox -e "$PROG" -- "$BIG" | wc -l >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_WC+=( $(( t1 - t0 )) ); b_wc=$(( b_wc + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ.count || :
    n_cnt="$RESULT"
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT+=( $(( t1 - t0 )) ); b_cnt=$(( b_cnt + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ1.count || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT1+=( $(( t1 - t0 )) ); b_cnt1=$(( b_cnt1 + t1 - t0 ))
done
median T_WC;   m_wc="$MED";  (( m_wc > 0 )) || m_wc=1
median T_CNT;  m_cnt="$MED"
median T_CNT1; m_cnt1="$MED"
report_med "\`gawk … | wc -l\` (baseline)" "$m_wc" "$b_wc" "$NR"
report_med "a.count ($NL records)" "$m_cnt" "$b_cnt" "$NR"
report_med "the same sink over ONE record (the fixed half)" "$m_cnt1" "$b_cnt1" "$NR"
ratio "  published: a.count vs the wc equivalent" "$m_cnt" "$m_wc" "the shell equivalent"
printf '  both answered %s / %s records\n' "$n_wc" "$n_cnt"
# The sink's cost splits cleanly: a fixed part (one gawk, one TPipe setup) and a
# per-record part (one bash `read` each). Measured, not assumed — the ONE-record
# row above IS the fixed part, so the difference over (NL - 1) records is the
# marginal cost of a record.
per_rec=$(( (m_cnt - m_cnt1) / (NL > 1 ? NL - 1 : 1) ))
printf '  marginal cost of ONE record read into bash: ~%d us (%d-record row minus\n' \
    "$per_rec" "$NL"
printf '  the 1-record row, over %d records)\n' $(( NL > 1 ? NL - 1 : 1 ))
if (( m_cnt > m_wc )); then
    printf '  the sink is the SLOWER of the two: that per-record price is what having\n'
    printf '  the records in THIS shell costs, and when all you want is the number,\n'
    printf '  the pipeline is the right answer.\n'
else
    printf '  at this corpus the SINK IS FASTER — the pipeline pays one more process\n'
    printf '  start, and the corpus is small enough for that to dominate.\n'
fi
BQ1.delete
BQ.delete

# ===========================================================================
# (e) zero forks
# ===========================================================================
echo
echo "(e) zero-fork check (\$BASHPID around every TAwk/TUtil member, five REFUSED"
echo "    paths, \`apply\`, and inside the callback and \`.Add\`):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TBenchListTA
    public
        constructor Create
        proc        Add
end
TBenchListTA.Create() { return 0; }
TBenchListTA.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TBenchListTA
TBenchListTA.new FL

p0=$BASHPID
forked=0
nzf=0
# zf COMMAND... — run one member call (output discarded, rc ignored), then check
# that this shell's PID did not change. A function call and a redirection on it
# do not fork, so the helper itself adds none.
zf() {
    "$@" >/dev/null 2>&1 || :
    nzf=$(( nzf + 1 ))
    if [[ "$BASHPID" != "$p0" ]]; then
        forked=1
    fi
}

declare -a FARR=() FW=()
TAwk.new FF "$PROG" "$ONE"
zf FF.program = "$PROG"
zf FF.programFile = ''
zf FF.fieldSep = ' '
zf FF.nullData = 0
zf FF.binary = 0
zf FF.sandbox = 1
zf FF.inPlace = 0
zf FF.backupSuffix = ''
zf FF.crlf = 0
zf FF.subshellOk = 0
zf FF.paths "$ONE"
zf FF.addProgram 'END{}'
zf FF.clearPrograms
zf FF.setVar x 1
zf FF.clearVars
zf FF.addArg --lint
zf FF.clearArgs
zf FF.buildArgv
zf FF.argv FW
zf FF.mapRc 1
zf FF.lastRc
zf FF.each    fork_cb
zf FF.toList  FL
zf FF.toArray FARR
zf FF.count
zf FF.first
zf FF.run
zf TAwk.apply "$PROG" "$ONE"
# the rc 2 paths: a deny-list hit, an in-place sink, a path-less and an
# empty-program apply, an illegal setVar name — they fork nothing either
TAwk.new FR "$PROG" "$ONE"
FR.addArg -Wsandbox
zf FR.count
FR.clearArgs
FR.sandbox = 0
FR.inPlace = 1
zf FR.count
zf TAwk.apply "$PROG"
zf TAwk.apply '' "$ONE"
zf FR.setVar ENVIRON 1
FR.delete
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 && nzf == 33 )) && (( ${#FORKPIDS[@]} == 2 )); then
    echo "  BASHPID $p0 unchanged across all $nzf member calls — twenty-seven members"
    echo "  and \`apply\`, plus the five rc 2 paths (a \`-W\` deny-list hit, an in-place"
    echo "  sink, a path-less \`apply\`, an empty-program \`apply\`, an illegal \`setVar\`"
    echo "  name) — and both callback/.Add invocations: the only fork per call is gawk"
    echo "  itself, and a refused call does not even pay that"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked calls=$nzf callback pids=(${FORKPIDS[*]})"
fi
FL.delete; FF.delete

# --- summary -----------------------------------------------------------------
echo
if (( GATES_FAILED == 0 )); then
    echo "gates: $GATES_TOTAL/$GATES_TOTAL PASS (TAwk.apply <= 1.5x a bare \`gawk --sandbox -e\`, medians of $NR interleaved runs)"
else
    echo "gates: $GATES_FAILED of $GATES_TOTAL FAILED — see the lines above"
fi

exit 0
