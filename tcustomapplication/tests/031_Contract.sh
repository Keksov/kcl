#!/bin/bash
# Contract — the kcl-wide contract for this unit (kcl/README.md section 1),
# written for phase P1 of the 2026-09-06 review. What it pins:
#
#   X-SETU (G8-01)   the unit loads, and RE-loads, under `set -eu` (decision D7).
#   X-INJ  (D1)      a caller-supplied index/count never reaches `(( ))` raw.
#   X-ECHO (G1-13)   values that look like echo options round-trip verbatim.
#   source integrity a sweeping mechanical edit must not silently mangle the
#                    file. In P1 an echo->printf sweep put a REAL newline inside
#                    the format string; the output was byte-identical, so every
#                    behavioural test stayed green while 534 statements were cut
#                    in half. `bash -n` plus "no single-quoted string left open"
#                    catches that whole class for the price of two greps.
#
# These files are deliberately near-identical across the suites: a change to the
# contract should be a mechanical sweep, not a re-reading of 17 dialects.

KTESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../ktests" && pwd)"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Contract" "$(dirname "$0")" "$@"

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$UNIT_DIR/tcustomapplication.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- 0. source integrity ---------------------------------------------------
kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then
    kt_test_pass "bash -n clean"
else
    kt_test_fail "bash -n: $err"
fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then
    kt_test_fail "unterminated format string(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

# --- 1. set -eu ------------------------------------------------------------
# Each check runs in a child shell so a failure cannot abort this file, and
# asserts on stderr too: `set -u` exists to turn a silent typo into a message.
expect_clean() {   # TITLE SNIPPET
    local title="$1" snippet="$2" out rc err
    local errf="$TMP/setu.err"
    kt_test_start "$title"
    out="$(bash -c "set -eu
source '$UNIT'
$snippet
printf OK" 2>"$errf")"; rc=$?
    err="$(<"$errf")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "rc=$rc out='$out' stderr='$err'"
    fi
}

expect_clean "the unit loads under set -eu [X-SETU, D7]" ":"
expect_clean "loading the unit TWICE under set -eu is a no-op [X-SETU]" "source '$UNIT'"
expect_clean "main path under set -eu [X-SETU, D7]" '
TCustomApplication.new a
a.SetArgs -v input.txt
a.HasOption v "" >/dev/null || :
a.GetOptionValue v "" >/dev/null
a.FindOptionIndex v "" 0 >/dev/null
a.delete'

# The whole FPC parser under set -eu, including the paths that answer with rc:
# an empty argv, an empty output array, a false predicate and a failing
# GetNonOptions all have to return control to the caller.
expect_clean "the option parser under set -eu [P4, D7]" '
TCustomApplication.new a
declare -a opts=() non=() vals=()
a.SetArgs --config=x.ini -c v -h rest -- -
a.CheckOptions "c:h" "config:" opts non true >/dev/null
a.GetOptionValues c config vals >/dev/null
a.GetNonOptions "c:h" "config:" non >/dev/null || :
a.HasOption zz "" >/dev/null || :
a.GetOptionAtIndex 1 false >/dev/null
a.ParamCount >/dev/null
a.Params 0 >/dev/null
a.Location >/dev/null
a.GetEnvironmentList vals true >/dev/null
a.Log etInfo "x=%s" y 2>/dev/null
a.SetArgs
a.CheckOptions "" "" opts non >/dev/null
a.GetOptionValues c config vals >/dev/null
a.delete'

# NB: reading a STORED property (`a.Terminated`) under `set -u` still dies in
# kklass (`kk._property` / `kk._prop_plain` read `$4` without `:-`) — recorded
# as found_in_P4 in kcl_ledger.json, out of this phase's scope. The loop itself
# is exercised here; 004 asserts the flag through the method path.
expect_clean "Run/DoRun/Terminate under set -eu [TCA-10, D7]" '
TCustomApplication.new a
a.Initialize
a.Run
a.Run
a.Terminate 0
a.delete'

# --- 2. numeric / name arguments (D1) --------------------------------------
kt_test_start "EnvironmentVariable and start_at reject an injection shape [TCA-05]"
canary="$TMP/pwn"; rm -f "$canary"
bad="x[\$(touch '$canary')]"
TCustomApplication.new A
A.SetArgs -v x
accepted=""
A.EnvironmentVariable "$bad" >/dev/null 2>&1 && accepted+="EnvironmentVariable "
A.FindOptionIndex v "" "$bad" >/dev/null 2>&1 && accepted+="FindOptionIndex "
if [[ ! -e "$canary" && -z "$accepted" ]]; then
    kt_test_pass "rejected, nothing executed"
else
    kt_test_fail "canary=$([[ -e "$canary" ]] && echo CREATED || echo absent) accepted: ${accepted:-none}"
fi
A.delete

kt_test_start "every output-array name is validated [kcl README 1.7]"
TCustomApplication.new A
A.SetArgs -f one -f two
declare -a ok=()
bad_rcs=""
for name in "" "not a name" "1abc" "RESULT" "IFS" "__kk_x" "__tca_vals" "A_data"; do
    A.GetOptionValues f "" "$name" >/dev/null 2>&1
    rc=$?
    # An EMPTY name means "no output array", which is allowed (rc 0).
    if [[ -z "$name" ]]; then
        [[ $rc -eq 0 ]] || bad_rcs+="empty:$rc "
    else
        [[ $rc -eq 2 ]] || bad_rcs+="$name:$rc "
    fi
done
A.GetOptionValues f "" ok >/dev/null 2>&1 || bad_rcs+="ok:$? "
if [[ -z "$bad_rcs" && "${#ok[@]}" -eq 2 ]]; then
    kt_test_pass "rc 2 for seven reserved/malformed names, rc 0 for a real one"
else
    kt_test_fail "output-name validation: ${bad_rcs:-none}; ok=(${ok[*]:-})"
fi
A.delete

kt_test_start "the option parser contains no command substitution [kcl README 1.8]"
# Structural, and cheap: a fork in FindOptionIndex/CheckOptions costs 1-16 ms
# per call on a large shell. `declare -f` prints the parsed body, so a `$(`
# here is a real subshell, not a string in a comment.
forky=""
for fn in tca._findIndex tca._optionAt tca._checkOptions tca._findLongOpt \
          tca._longOpts tca._addErr tca._isName tca._outName; do
    body="$(declare -f "$fn" 2>/dev/null)"
    if [[ -z "$body" ]]; then
        forky+="$fn:missing "
        continue
    fi
    # `$(( ))` is arithmetic, not a subshell — remove it before looking for `$(`.
    body="${body//\$((/ }"
    if [[ "$body" == *'$('* || "$body" == *'`'* ]]; then
        forky+="$fn:substitution "
    fi
done
if [[ -z "$forky" ]]; then
    kt_test_pass "all eight parser helpers are fork-free"
else
    kt_test_fail "$forky"
fi

kt_test_start "a direct option call does not fork [kcl README 1.8]"
TCustomApplication.new A
A.SetArgs -c cfg.ini -v rest
caller_pid=$BASHPID
declare -a opts=() non=()
A.CheckOptions "c:v" "" opts non
A.GetOptionValue c ""
value_pid=$BASHPID
if [[ "$caller_pid" == "$value_pid" && "$RESULT" == "cfg.ini" && "${opts[*]}" == "c=cfg.ini" ]]; then
    kt_test_pass "BASHPID unchanged and RESULT reached the caller"
else
    kt_test_fail "fork: caller=$caller_pid after=$value_pid RESULT='$RESULT' opts=(${opts[*]:-})"
fi
A.delete

kt_test_start "an option value that looks like an echo flag round-trips [X-ECHO]"
TCustomApplication.new A
A.SetArgs -c -- --name=-neE
A.GetOptionValue "" name
direct="$RESULT"
captured="$(A.GetOptionValue "" name)"
A.Params 2
p2="$RESULT"
if [[ "$direct" == "-neE" && "$captured" == "-neE" && "$p2" == "--" ]]; then
    kt_test_pass "-neE survives both the direct call and \$( )"
else
    kt_test_fail "direct='$direct' captured='$captured' Params2='$p2'"
fi
A.delete

kt_test_start "delete frees every variable of the instance [kcl README 1.9]"
TCustomApplication.new Zapp
Zapp.SetArgs -v x --long=y
Zapp.CheckOptions v "long:" >/dev/null
Zapp.delete
left="$(compgen -v | grep -c '^Zapp_' || true)"
if [[ "$left" == "0" ]]; then
    kt_test_pass "no Zapp_* variable is left behind"
else
    kt_test_fail "$left variables left after delete: $(compgen -v | grep '^Zapp_' | tr '\n' ' ')"
fi

# --- 5. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. This runs the documented failure path and checks the caller
# still gets control — verified on 5.2.37 and 5.3.9.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
TCustomApplication.new a; a.EnvironmentVariable 'bad name' >/dev/null || printf 'reached rc=%s' \0
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc="* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi
