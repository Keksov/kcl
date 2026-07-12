#!/bin/bash
# 001_CreationAndDestruction.sh - TStopwatch skeleton: ctor (plain + startnew
# token), field initialization, token validation, destruction. P0.2 gate.
# Spec basis: Delphi DocWiki TStopwatch.Create (S1: created STOPPED, elapsed
# 0) / TStopwatch.StartNew (S2: created RUNNING); no FPC tests exist
# (Delphi-only API) — every case has a TEST_COVERAGE_NOTES.md row.
# WHITE-BOX NOTE: getters land in P1; until then state is asserted straight
# from the kklass per-instance store ${inst}_data[_accum|_t0|_running].

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSW_DIR="$SCRIPT_DIR/.."
source "$TSW_DIR/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TStopwatch creation and destruction (P0 skeleton)"

# helper: current µs with the same pinned parse idiom the unit uses
_t_now_us() { local er=$EPOCHREALTIME; echo $(( ${er%[.,]*} * 1000000 + 10#${er##*[.,]} )); }

# Test: default constructor -> stopped watch, elapsed 0 (S1)
kt_test_start "Create: stopped watch, all fields zero (S1)"
TStopwatch.new sw
rc=$?
if [[ $rc -eq 0 && "${sw_data[_running]}" == "0" && "${sw_data[_accum]}" == "0" && "${sw_data[_t0]}" == "0" ]]; then
    kt_test_pass "rc 0; _running=0 _accum=0 _t0=0"
else
    kt_test_fail "rc=$rc running=${sw_data[_running]} accum=${sw_data[_accum]} t0=${sw_data[_t0]}"
fi

# Test: state lives in the kklass store (exactly the three declared fields)
kt_test_start "Field store: declare -A with exactly _accum/_t0/_running"
decl="$(declare -p sw_data 2>/dev/null)"
if [[ "$decl" == "declare -A"* && ${#sw_data[@]} -eq 3 \
      && -n "${sw_data[_accum]+x}" && -n "${sw_data[_t0]+x}" && -n "${sw_data[_running]+x}" ]]; then
    kt_test_pass "3 fields present in ${decl%%=*}"
else
    kt_test_fail "unexpected store: $decl"
fi

# Test: startnew ctor token -> running watch, t0 stamped now (S2).
# Exact-by-construction: t0 must fall inside the [before, after] window read
# with the same clock.
kt_test_start "Create startnew: running, _t0 inside the call window (S2)"
before=$(_t_now_us)
TStopwatch.new swr startnew
rc=$?
after=$(_t_now_us)
t0=${swr_data[_t0]}
if [[ $rc -eq 0 && "${swr_data[_running]}" == "1" && "${swr_data[_accum]}" == "0" ]] \
   && (( t0 >= before && t0 <= after )); then
    kt_test_pass "rc 0; running=1 accum=0; before<=t0<=after ($before <= $t0 <= $after)"
else
    kt_test_fail "rc=$rc running=${swr_data[_running]} accum=${swr_data[_accum]} t0=$t0 window=[$before,$after]"
fi

# Test: unknown ctor token -> rc 1, instance left as a valid STOPPED watch
# (fields are initialized before token validation — defensive shape).
kt_test_start "Create with unknown token: rc 1, instance = valid stopped watch"
TRAP_ERRORS_ENABLED=false
TStopwatch.new bad bogus 2>/dev/null
rc=$?
TRAP_ERRORS_ENABLED=true
if [[ $rc -ne 0 && "${bad_data[_running]}" == "0" && "${bad_data[_accum]}" == "0" && "${bad_data[_t0]}" == "0" ]]; then
    kt_test_pass "rc=$rc; fields at stopped defaults"
else
    kt_test_fail "rc=$rc running=${bad_data[_running]} accum=${bad_data[_accum]} t0=${bad_data[_t0]}"
fi
bad.delete

# Test: token is exact lowercase 'startnew' (documented pin — 'StartNew' is
# the Delphi identifier, the bash token is lowercase like doOwnsKeys is
# FPC-cased: exactly one spelling accepted)
kt_test_start "Token is exact: 'StartNew' (wrong case) rejected rc 1"
TRAP_ERRORS_ENABLED=false
TStopwatch.new badcase StartNew 2>/dev/null
rc=$?
TRAP_ERRORS_ENABLED=true
if [[ $rc -ne 0 && "${badcase_data[_running]}" == "0" ]]; then
    kt_test_pass "wrong-case token rejected, watch stopped"
else
    kt_test_fail "rc=$rc running=${badcase_data[_running]}"
fi
badcase.delete

# Test: rejection is SILENT by default, message only under VERBOSE_KKLASS=debug
kt_test_start "Unknown token: silent by default, message under VERBOSE_KKLASS=debug"
errfile="${TMPDIR:-/tmp}/tsw001_err.$$"
TRAP_ERRORS_ENABLED=false
TStopwatch.new q1 bogus 2>"$errfile"
quiet_size=$(wc -c <"$errfile")
VERBOSE_KKLASS=debug TStopwatch.new q2 bogus 2>"$errfile"
TRAP_ERRORS_ENABLED=true
if [[ "$quiet_size" -eq 0 ]] && grep -q "unknown token 'bogus'" "$errfile"; then
    kt_test_pass "quiet by default (0 bytes), debug message present"
else
    kt_test_fail "quiet_size=$quiet_size debug_msg='$(cat "$errfile")'"
fi
rm -f "$errfile"
q1.delete; q2.delete

# Test: instances are independent (stopped and running coexist)
kt_test_start "Instances independent: sw stopped while swr runs"
if [[ "${sw_data[_running]}" == "0" && "${swr_data[_running]}" == "1" ]]; then
    kt_test_pass "sw running=0, swr running=1 — no cross-talk"
else
    kt_test_fail "sw=${sw_data[_running]} swr=${swr_data[_running]}"
fi

# Test: destruction removes the field store
kt_test_start "delete: rc 0 and field store unset"
sw.delete
rc=$?
if [[ $rc -eq 0 ]] && ! declare -p sw_data >/dev/null 2>&1; then
    kt_test_pass "sw deleted, sw_data gone"
else
    kt_test_fail "rc=$rc store=$(declare -p sw_data 2>&1)"
fi

# Test: destroyed instance inaccessible
kt_test_start "delete: destroyed instance inaccessible"
TRAP_ERRORS_ENABLED=false
sw.delete >/dev/null 2>&1
rc=$?
TRAP_ERRORS_ENABLED=true
if [[ $rc -ne 0 ]]; then
    kt_test_pass "second delete fails (rc=$rc)"
else
    kt_test_fail "destroyed instance still accessible"
fi

# Test: recreate under the same name after delete -> fresh stopped watch
kt_test_start "Recreate under the same name after delete"
TStopwatch.new phoenix startnew
phoenix.delete
TStopwatch.new phoenix
if [[ "${phoenix_data[_running]}" == "0" && "${phoenix_data[_accum]}" == "0" && "${phoenix_data[_t0]}" == "0" ]]; then
    kt_test_pass "phoenix recreated as a fresh stopped watch"
else
    kt_test_fail "running=${phoenix_data[_running]} accum=${phoenix_data[_accum]} t0=${phoenix_data[_t0]}"
fi
phoenix.delete

# Test: zero-fork lifecycle — new (both forms) + delete under PATH=''
kt_test_start "Zero-fork: new/new-startnew/delete lifecycle under PATH=''"
_saved_path=$PATH
PATH=''
TStopwatch.new zf1        ; rc1=$?
TStopwatch.new zf2 startnew; rc2=$?
zf1.delete                 ; rc3=$?
zf2.delete                 ; rc4=$?
PATH=$_saved_path
if [[ $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 ]]; then
    kt_test_pass "full lifecycle fork-free (rcs 0/0/0/0)"
else
    kt_test_fail "rcs: new=$rc1 startnew=$rc2 del1=$rc3 del2=$rc4"
fi

# cleanup
swr.delete

kt_test_log "001_CreationAndDestruction.sh completed"
