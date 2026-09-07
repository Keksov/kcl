#!/bin/bash
# 004_RunOperations.sh - Run / DoRun / Terminate.
#
# FPC: `Run` is `Repeat Try DoRun except HandleException(Self) Until Terminated`.
# Before P4 there was no DoRun at all and Run was a `$( )`-per-10ms busy loop
# that could not be stopped from a background job (finding TCA-10); every test
# here was written as "start Run in the background, kill it, pass either way".
# The loop is now observable and fork-free, so the tests assert on it directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# A descendant that overrides DoRun, which is the FPC way to give an
# application a body. It counts its passes and terminates on the third.
class TCountingApp : TCustomApplication
    public
        override proc DoRun
end

TCountingApp.DoRun() {
    TCA_RUNS=$(( TCA_RUNS + 1 ))
    TCA_RUN_PIDS+=("$BASHPID")
    if (( TCA_RUNS >= 3 )); then
        $this.Terminate 0
    fi
    return 0
}

build TCountingApp

# A descendant whose DoRun fails, to reach Run's exception path.
class TFailingApp : TCustomApplication
    public
        override proc DoRun
end

TFailingApp.DoRun() {
    TCA_RUNS=$(( TCA_RUNS + 1 ))
    return 1
}

build TFailingApp

kt_test_section "004: TCustomApplication Run Operations"

kt_test_start "the base DoRun exists and terminates the application"
TCustomApplication.new myapp
myapp.Initialize
myapp.DoRun
rc=$?
terminated=$(myapp.Terminated)
if [[ $rc -eq 0 && "$terminated" == "true" ]]; then
    kt_test_pass "the default DoRun terminates, so the base Run is not an infinite loop"
else
    kt_test_fail "DoRun rc=$rc terminated=$terminated (expected 0 / true)"
fi
myapp.delete

kt_test_start "Run calls DoRun until Terminated [TCA-10]"
TCountingApp.new counter
counter.Initialize
declare -g TCA_RUNS=0
declare -ga TCA_RUN_PIDS=()
counter.Run
rc=$?
terminated=$(counter.Terminated)
if [[ $rc -eq 0 && "$TCA_RUNS" == "3" && "$terminated" == "true" ]]; then
    kt_test_pass "DoRun ran three times and the loop stopped on Terminate"
else
    kt_test_fail "Run loop: rc=$rc runs=$TCA_RUNS terminated=$terminated (expected 0/3/true)"
fi
counter.delete

kt_test_start "Run does not fork [TCA-10, kcl README 1.8]"
TCountingApp.new counter
counter.Initialize
declare -g TCA_RUNS=0
declare -ga TCA_RUN_PIDS=()
caller_pid=$BASHPID
counter.Run
same=1
for p in "${TCA_RUN_PIDS[@]}"; do
    [[ "$p" == "$caller_pid" ]] || same=0
done
if [[ "$same" == "1" && ${#TCA_RUN_PIDS[@]} -eq 3 ]]; then
    kt_test_pass "every DoRun ran in the caller's own process (BASHPID unchanged)"
else
    kt_test_fail "Run forked: caller=$caller_pid pids=(${TCA_RUN_PIDS[*]:-})"
fi
counter.delete

kt_test_start "Run returns immediately when DoRun terminates on the first pass"
TCountingApp.new counter
counter.Initialize
declare -g TCA_RUNS=2      # the next pass is the third
declare -ga TCA_RUN_PIDS=()
counter.Run
if [[ "$TCA_RUNS" == "3" ]]; then
    kt_test_pass "one DoRun call, then the loop ends"
else
    kt_test_fail "Run made $((TCA_RUNS - 2)) passes, expected 1"
fi
counter.delete

kt_test_start "Run hands a failing DoRun to HandleException"
TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TMPD"
TFailingApp.new failing
failing.Initialize
failing.property StopOnException = "true"
failing.property ExceptionExitCode = 5
declare -g TCA_RUNS=0
# NOT `$(failing.Run)`: a subshell would throw away every mutation the loop makes.
failing.Run 2>"$TMPD/run.err"
err="$(<"$TMPD/run.err")"
terminated=$(failing.Terminated)
if [[ "$TCA_RUNS" == "1" && "$terminated" == "true" && "$err" == Exception:* && "${EXITCODE:-}" == "5" ]]; then
    kt_test_pass "the failing pass became an exception, which terminated the loop"
else
    kt_test_fail "exception path: runs=$TCA_RUNS terminated=$terminated exitcode=${EXITCODE:-} stderr='$err'"
fi
failing.delete

kt_test_start "Run stops at once when Terminated was already set"
TCountingApp.new counter
counter.Initialize
counter.Terminate
declare -g TCA_RUNS=0
declare -ga TCA_RUN_PIDS=()
counter.Run
# FPC's Run is a REPEAT loop: DoRun always runs at least once.
if [[ "$TCA_RUNS" == "1" ]]; then
    kt_test_pass "one pass, as FPC's repeat/until requires"
else
    kt_test_fail "Run made $TCA_RUNS passes with Terminated already true, expected 1"
fi
counter.delete

kt_test_start "Terminate from outside the loop is visible to Run"
TCountingApp.new counter
counter.Initialize
declare -g TCA_RUNS=0
declare -ga TCA_RUN_PIDS=()
counter.property Terminated = "true"
counter.Run
if [[ "$TCA_RUNS" == "1" ]]; then
    kt_test_pass "Run reads the live property, not a copy"
else
    kt_test_fail "Run made $TCA_RUNS passes, expected 1"
fi
counter.delete

rm -rf "$TMPD"

kt_test_log "004_RunOperations.sh completed"
