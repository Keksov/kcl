#!/usr/bin/env bash
# 010_CountCapture.sh — `$(q.Count)` / `$(s.Count)` print the count ONCE
# (kklass round 7, fv ledger K-2).
#
# TQueue.Count / TStack.Count end with the helper TQueueStack._count, which
# answers with kk._return. Before kklass round 7 the func trailer
# `kk._return "$RESULT"` then ran as the body's last command and printed the
# same value a second time inside a command substitution: `$(q.Count)` on a
# 3-element queue gave "33" (the direct call was right). Since round 7 the
# dispatcher answers after the body, and an explicit kk._return is final.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "010: \$(x.Count) prints the count once"

for cls in TQueue TStack; do
    case "$cls" in
        TQueue) push=Enqueue ;;
        TStack) push=Push ;;
    esac
    $cls.new C
    kt_test_start "$cls: \$(C.Count) of an empty, then a 3-element and a 12-element container prints the count once; the direct call answers it in RESULT"
    out="$(C.Count)|"
    C.$push a; C.$push b; C.$push c
    out+="$(C.Count)|"
    C.Count; out+="$RESULT|"
    for v in d e f g h i j k l; do C.$push "$v"; done
    out+="$(C.Count)|"
    out+="$(C.Peek)"
    if [[ $out == "0|3|3|12|$([[ $cls == TQueue ]] && echo a || echo l)" ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "got [$out]"
    fi
    C.delete
done

kt_test_log "010_CountCapture.sh completed"
