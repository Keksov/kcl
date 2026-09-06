#!/bin/bash
# 009_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2.
#
#   G2-02  ToArray had no output-name validation: `q.ToArray __tqs_it` aliased
#          the unit's own nameref and the fill loop appended the storage to
#          itself (Count 2 -> 4, rc 0), an empty or malformed name printed a
#          bash error, filled a throwaway local and returned rc 0 with a count,
#          and an associative target silently got 0,1,2… keys.
#          A rejected output-array name answers **rc 2** — it is a malformed
#          CALL, not a value the caller may legitimately try (kcl/README.md
#          sections 1.2 and 1.7; owner decision 2026-09-07 over the rc 1 the
#          review report had suggested).
#   G2-10 / R3  a rejected ctor token must leave an instance with the class
#          DEFAULTS and return rc 1 — the same in tqueuestack and tdictionary.
#          Both already do; nothing pinned it, and tqueuestack's own default
#          (owning) is the one that costs memory if it ever drifts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "009: review 2026-09-06 P2 — ToArray output names, rejected ctor token"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }

# --- G2-02: ToArray output-name validation ---------------------------------
for cls in TQueue TStack; do
    case "$cls" in
        TQueue) push=Enqueue ;;
        TStack) push=Push ;;
    esac

    kt_test_start "$cls.ToArray refuses the unit's own local name, storage untouched [G2-02]"
    $cls.new C
    C.$push a; C.$push b
    C.ToArray __tqs_it 2>/dev/null; rc=$?
    C.Count; n=$RESULT
    [[ $rc -eq 2 && "$n" == "2" ]] && kt_test_pass "rc 2, count still 2" \
        || kt_test_fail "rc=$rc count=$n (the storage was appended to itself)"

    kt_test_start "$cls.ToArray refuses the instance's own storage name [G2-02]"
    C.ToArray "C_items" 2>/dev/null; rc=$?
    C.Count; n=$RESULT
    [[ $rc -eq 2 && "$n" == "2" ]] && kt_test_pass "rc 2, count still 2" || kt_test_fail "rc=$rc count=$n"

    kt_test_start "$cls.ToArray refuses an empty or malformed name, silently [G2-02]"
    bad=""
    for name in "" "bad name" "1abc" "a-b" "RESULT" "IFS" "__kk_x"; do
        err="$(C.ToArray "$name" 2>&1)"; rc=$?
        [[ $rc -eq 2 ]] || bad+="rc[$name]=$rc "
        [[ -z "$err" ]] || bad+="noise[$name] "
    done
    C.Count; n=$RESULT
    [[ -z "$bad" && "$n" == "2" ]] && kt_test_pass "7 bad names rejected silently" \
        || kt_test_fail "$bad count=$n"

    kt_test_start "$cls.ToArray refuses an associative target [G2-02]"
    unset assoc_target; declare -A assoc_target=()
    C.ToArray assoc_target 2>/dev/null; rc=$?
    [[ $rc -eq 2 && "${#assoc_target[@]}" == "0" ]] \
        && kt_test_pass "rc 2, target untouched" || kt_test_fail "rc=$rc keys='${!assoc_target[*]}'"

    kt_test_start "$cls.ToArray still fills a normal array and returns the count [G2-02]"
    unset out; declare -a out=(stale)
    C.ToArray out; rc=$?
    [[ $rc -eq 0 && "$RESULT" == "2" && "${#out[@]}" == "2" && "${out[0]}" == "a" ]] \
        && kt_test_pass "rc 0, RESULT 2, a first" || kt_test_fail "rc=$rc RESULT=$RESULT out='${out[*]}'"
    C.delete
done

# --- G2-10 / R3: a rejected ctor token -------------------------------------
kt_test_start "TObjectQueue.new q bogus -> rc 1 and an OWNING queue (the default) [G2-10, R3]"
TObjectQueue.new Q bogus 2>/dev/null; rc=$?
o="$(Q.owns_objects)"
TQueue.new payload
Q.Enqueue payload
Q.Count; n=$RESULT
Q.delete
[[ $rc -eq 1 && "$o" == "true" && "$n" == "1" ]] && ! alive payload \
    && kt_test_pass "rc 1, owns=true, usable, element freed on delete" \
    || kt_test_fail "rc=$rc owns=$o count=$n payload=$(alive payload && echo alive || echo freed)"
alive payload && payload.delete

kt_test_start "TObjectStack.new s bogus -> rc 1 and an OWNING stack (the default) [G2-10, R3]"
TObjectStack.new S bogus 2>/dev/null; rc=$?
o="$(S.owns_objects)"
TQueue.new payload2
S.Push payload2
S.Count; n=$RESULT
S.delete
[[ $rc -eq 1 && "$o" == "true" && "$n" == "1" ]] && ! alive payload2 \
    && kt_test_pass "rc 1, owns=true, usable, element freed on delete" \
    || kt_test_fail "rc=$rc owns=$o count=$n payload2=$(alive payload2 && echo alive || echo freed)"
alive payload2 && payload2.delete

kt_test_start "a rejected token is silent unless VERBOSE_KKLASS=debug [G2-10, D2]"
# The instance must be created in THIS shell (a $( ) capture would build it in
# a subshell and lose it), so stderr goes to a file.
errf="$(kt_fixture_tmpdir)/ctor.err"
TObjectQueue.new QQ bogus 2>"$errf"; rc=$?
err="$(<"$errf")"
QQ.delete
VERBOSE_KKLASS=debug TObjectQueue.new QD bogus 2>"$errf"
dbg="$(<"$errf")"
QD.delete
[[ $rc -eq 1 && -z "$err" && "$dbg" == *"unknown token"* ]] \
    && kt_test_pass "silent by default, explained under debug" \
    || kt_test_fail "rc=$rc stderr='$err' debug='$dbg'"

kt_test_log "009_ReviewP2.sh completed"
