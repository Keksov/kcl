#!/bin/bash

# ===========================================================================
# tqueuestack — a bash port of FPC rtl-generics TQueue/TStack and their
#               owning variants TObjectQueue/TObjectStack (ONE unit, 4 classes).
#
# Source of truth: packages/rtl-generics/src/generics.collections.pas —
# TQueue<T> (:386, impl :2404-2559: DoRemove :2449 head-advance, Enqueue :2521,
# Dequeue/Extract/Peek/Clear :2530-2554, Destroy->Clear :2515), TStack<T>
# (:434, impl :2591-2652), TObjectQueue<T> (:477: Notify :2696 =
# inherited-then-free-on-cnRemoved, ctor default AOwnsObjects=True,
# **procedure Dequeue** :2726), TObjectStack<T> (:492: Notify :2733,
# **function Pop** :2763 returns the just-freed value), TCustomList<T>
# (:197: Notify :1639, DoRemove :1645 — Notify fires AFTER the physical
# removal with the removed value, ToArray :1629 via the enumerator — queue's
# starts at FLow :2397-2402 -> front-to-back). FPC fpcunit seeds (P0-verified):
# tests.generics.queue.pas + tests.generics.stack.pas (Simple* core +
# SingleObject* ownership) and tests.generics.stdcollections.pas
# (Test_T{Queue,Stack,ObjectQueue,ObjectStack}_Notification) — mined per phase.
# Plan/ledger: kcl/tqueuestack/{PLAN.md,tqueuestack_ledger.json}.
#
# ---- Storage (P0-frozen; probes Q1-Q7 green on 5.2.37 + 5.3.9) --------------
# One indexed array per instance: ${inst}_items.
#   Stack: dense by construction — top == count-1; push appends, pop unsets
#          the top. All O(1).
#   Queue: ${inst}_qhead marks the front (FPC FLow). Enqueue appends (`+=`
#          lands at max_index+1 even over holes — Q2); Dequeue reads + unsets
#          items[qhead] and advances — consumed slots stay as HOLES.
#   count == ${#items[@]} for BOTH (set elements only — holes don't count, Q1)
#          -> live count with zero bookkeeping.
#   Auto-reset: when a removal empties the queue, qhead:=0 (mirrors FPC
#          DoRemove :2457-2461 FLow/FLength reset; `+=` then restarts at 0, Q7).
#   Amortized compaction (internal policy, NOT an API — replaces FPC's
#          MoveToFront/capacity machinery): when qhead >= 64 AND qhead >= live
#          count, reindex `items=("${items[@]}"); qhead=0` — O(live) rarely =
#          amortized O(1) per op; order/values byte-exact (Q3/Q4); flatness
#          proven by the P5 bench.
# qhead lives NEXT TO the storage array (declare -g at ctor), not as a kklass
# var — it is internal layout, not API.
#
# ---- Return contract ---------------------------------------------------------
# funcs return via RESULT (kk._return on EVERY explicit-return path — the
# trailer trap); procs are rc-only. Dequeue/Pop/Extract/Peek on empty -> FPC
# raises EArgumentOutOfRange -> here rc 1 + RESULT='' + debug-only msg.
# TryDequeue/TryPop (bash extras) -> rc 1 SILENTLY (an answer, not an error).
# ToArray fills a caller-named nameref (queue: front->back; stack: bottom->top,
# S9) and RESULTs the count — CALL DIRECTLY ($() discards the fill).
# RESERVED NAMES: never pass caller arrays named __tqs_* (nameref shadowing,
# the tinifile P2 lesson).
#
# ---- The two FPC quirks are PRESERVED, not fixed (S8) ------------------------
# * TObjectQueue.Dequeue is a PROCEDURE: the dequeued (and, when owning,
#   already-freed) object is NOT returned — RESULT is meaningless after it.
#   Use Extract to take ownership.
# * TObjectStack.Pop RETURNS the handle of an instance that ownership just
#   freed (FPC hands back a dangling pointer; bash hands back a dead handle
#   string — safe to hold, dead to call). Use Extract to keep it alive.
# ===========================================================================

# Re-source guard.
if [[ -n "$_TQUEUESTACK_SOURCED" ]]; then
    return
fi
declare -g _TQUEUESTACK_SOURCED=1

TQUEUESTACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TQUEUESTACK_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Member surface frozen at P0; bodies land per phase:
#   P1 TQueue core, P2 TStack core, P3 events (on_notify + Notify seam),
#   P4 TObjectQueue/TObjectStack (ownership + the S8 quirks).
# ---------------------------------------------------------------------------
class TQueue
    public
        constructor Create
        destructor  Destroy
        var on_notify            # P3: callback fn name; '' = off
        func Count               # RESULT = live count (fork-free; no property)
        proc Enqueue             # P1  v         (write, then notify added)
        func Dequeue             # P1  -> RESULT (front; empty -> rc1 '')
        func Extract             # P1  -> RESULT (front, 'extracted' action)
        func Peek                # P1  -> RESULT (no removal; empty -> rc1 '')
        func TryDequeue          # P1  -> RESULT + rc (silent on empty)
        proc Clear               # P1  (P3: fires per-item removed, FIFO)
        func ToArray             # P1  outArr -> RESULT=count (front->back)
        proc Notify              # P3  virtual seam: <value> <action>
end

class TStack
    public
        constructor Create
        destructor  Destroy
        var on_notify
        func Count
        proc Push                # P2
        func Pop                 # P2  -> RESULT (top; empty -> rc1 '')
        func Extract             # P2
        func Peek                # P2
        func TryPop              # P2
        proc Clear               # P2  (P3: per-item removed, LIFO)
        func ToArray             # P2  outArr -> RESULT=count (bottom->top)
        proc Notify              # P3
end

class TObjectQueue : TQueue
    public
        constructor Create       # [true|false] — FPC default OWNS=TRUE (:483)
        var owns_objects         # writable mid-life (S10, :489)
        override proc Notify     # P4: inherited first, free on removed (:2696)
        override proc Dequeue    # P4: the PROCEDURE quirk (:2726) — no value
end

class TObjectStack : TStack
    public
        constructor Create       # [true|false] — owns default TRUE (:498)
        var owns_objects
        override proc Notify     # P4 (:2733)
        override func Pop        # P4: returns the freed handle (:2763)
end

# ---- plain helpers (survive `build`; the safe cross-member mechanism) --------

# Shared ctor core for the two base classes: storage + defaults.
TQueueStack._init() {
    on_notify=""
    declare -ga "${__inst__}_items=()"
    declare -g  "${__inst__}_qhead=0"      # unused by stacks; harmless
    declare -g  "${__inst__}_nhook=0"      # 1 = a TObject* subclass needs Notify
}

# Shared dtor core: tear the storage down (Destroy Clears first — S6).
TQueueStack._teardown() {
    unset "${__inst__}_items" "${__inst__}_qhead" "${__inst__}_nhook"
}

# The event gate (tdictionary P5 hot-path guard): dispatch the VIRTUAL Notify
# only when someone listens — a user callback (on_notify) or an owning
# TObject* subclass (nhook, armed at its ctor). Everything else pays one
# [[ ]] per mutation, no kklass dispatch. $1=value $2=added|removed|extracted.
TQueueStack._notify() {
    local __tqs_nh="${__inst__}_nhook"
    if [[ -n "$on_notify" || "${!__tqs_nh}" == "1" ]]; then
        $this.Notify "$1" "$2"
    fi
    return 0
}

# Free helper for the owning variants (P4): live kklass instances only —
# the tobjectlist liveness guard (double-free / non-instance = silent no-op).
TQueueStack._free() {
    if [[ -n "$1" ]] && declare -F "$1.delete" >/dev/null 2>&1; then
        "$1".delete
    fi
    return 0
}

# Shared member bodies — TQueue and TStack expose identically-shaped Count/
# ToArray/Notify; both delegate here (the same thin-wrapper-over-`_`-helper
# pattern as Create->_init), so the logic lives in ONE place. kk._return in a
# helper propagates through the caller's func frame (the tinifile _get pattern).

# count == ${#items[@]} (set elements only — Q1): one nameref, zero math.
TQueueStack._count() {
    local -n __tqs_it="${__inst__}_items"
    kk._return "${#__tqs_it[@]}"
    return 0
}

# Fill a caller nameref in ascending index order (queue: front->back over the
# live region; stack: bottom->top over the dense array — S9) + RESULT=count.
TQueueStack._toArray() {
    local -n __tqs_out="$1"; __tqs_out=()
    local -n __tqs_it="${__inst__}_items"
    local __tqs_i
    for __tqs_i in "${!__tqs_it[@]}"; do
        __tqs_out+=( "${__tqs_it[__tqs_i]}" )
    done
    kk._return "${#__tqs_out[@]}"
    return 0
}

# The VIRTUAL Notify seam (FPC TCustomList.Notify :1639): fire the user event
# if assigned. A dangling callback name is a silent no-op (debug msg) — a bad
# listener must not corrupt collection ops; the callback rc is ignored (FPC
# events return nothing). $1=value $2=action.
TQueueStack._fireNotify() {
    if [[ -n "$on_notify" ]]; then
        if declare -F "$on_notify" >/dev/null 2>&1; then
            "$on_notify" "$this" "${1-}" "${2-}" || :
        else
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
                echo "Warning: tqueuestack Notify: callback '$on_notify' not found" >&2
        fi
    fi
    return 0
}

# The owning-variant Notify tail (FPC TObjectQueue/Stack.Notify :2696/:2733):
# after the inherited user event, free the value on 'removed' ONLY when owning
# ('extracted' hands ownership back; 'added' never frees). owns read AT EVENT
# TIME (S10). The `inherited Notify` call itself must stay in each override
# body — `inherited` is a per-method keyword a plain helper cannot carry.
TQueueStack._freeOnRemoved() {
    if [[ "$owns_objects" == "true" && "${2-}" == "removed" ]]; then
        TQueueStack._free "${1-}"
    fi
    return 0
}

# ---- method bodies (P0: ctors/dtors/Count real; the rest arrive per phase) ---

TQueue.Create() {
    TQueueStack._init
    return 0
}

TQueue.Destroy() {
    # FPC :2515: Destroy -> Clear -> inherited: per-item removed events (and,
    # in TObject* subclasses, ownership frees) fire during delete (S6).
    $this.Clear
    TQueueStack._teardown
    return 0
}

TStack.Create() {
    TQueueStack._init
    return 0
}

TStack.Destroy() {
    # FPC :2602: Destroy -> Clear -> inherited (S6).
    $this.Clear
    TQueueStack._teardown
    return 0
}

TQueue.Count() { TQueueStack._count; }
TStack.Count() { TQueueStack._count; }

TObjectQueue.Create() {
    # FPC :2703: inherited Create; FObjectsOwner := AOwnsObjects (DEFAULT TRUE
    # :483 — kept verbatim, documented loudly; disable with `... false`).
    # nhook is armed UNCONDITIONALLY (not only when owning): owns_objects is
    # writable mid-life (S10 — the FPC seed itself flips it: TestNoFreeOnDeQueue
    # sets OwnsObjects:=False after Create(True)), so the virtual Notify must
    # always dispatch and check owns AT EVENT TIME.
    inherited
    owns_objects=true
    declare -g "${__inst__}_nhook=1"
    case "${1:-}" in
        ""|true) : ;;
        false)   owns_objects=false ;;
        *)
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
                echo "Error: TObjectQueue.Create: unknown token '$1' (want true|false)" >&2
            return 1 ;;
    esac
    return 0
}

TObjectStack.Create() {
    inherited
    owns_objects=true
    declare -g "${__inst__}_nhook=1"
    case "${1:-}" in
        ""|true) : ;;
        false)   owns_objects=false ;;
        *)
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
                echo "Error: TObjectStack.Create: unknown token '$1' (want true|false)" >&2
            return 1 ;;
    esac
    return 0
}

# ---- P1 queue plain helpers ---------------------------------------------------

# Remove the front element (FPC TQueue.DoRemove :2449 verbatim in the hole
# model): empty -> rc 1; else capture -> __tqs_val, clear the slot, advance
# qhead; drain-to-empty resets qhead (FPC FLow/FLength reset :2457); the
# amortized reindex (qhead>=64 AND qhead>=live, frozen at P0) replaces FPC's
# MoveToFront/capacity machinery. $1 = action (removed|extracted) — threaded
# now so P3 only appends the Notify call at the tail (the FPC tail position).
# Caller declares: local __tqs_val
TQueueStack._qremove() {
    local -n __tqs_it="${__inst__}_items"
    local -n __tqs_h="${__inst__}_qhead"
    if (( ${#__tqs_it[@]} == 0 )); then
        __tqs_val=""
        return 1
    fi
    __tqs_val="${__tqs_it[__tqs_h]}"
    unset "${__inst__}_items[$__tqs_h]"
    (( ++__tqs_h ))     # pre-increment: new value >=1 -> rc 0 (set -e safe;
                        # post-increment `h++` returns rc 1 when h was 0)
    if (( ${#__tqs_it[@]} == 0 )); then
        __tqs_h=0                                   # drain-to-empty reset (Q7)
    elif (( __tqs_h >= 64 && __tqs_h >= ${#__tqs_it[@]} )); then
        __tqs_it=( "${__tqs_it[@]}" )               # reindex (Q3/Q4 byte-exact)
        __tqs_h=0
    fi
    # Notify is the TAIL of the removal (FPC DoRemove :2462) — value passed,
    # AFTER the physical mutation. One call here covers Dequeue/Extract/
    # TryDequeue/Clear/Destroy for free.
    TQueueStack._notify "$__tqs_val" "$1"
    return 0
}

# ---- P1 members: TQueue core ---------------------------------------------------

TQueue.Enqueue() {
    # v — append at the tail (`+=` lands at max_index+1 even over head holes,
    # Q2). FPC :2521: write, then notify added (P3 appends the Notify).
    local -n __tqs_it="${__inst__}_items"
    __tqs_it+=( "${1-}" )
    TQueueStack._notify "${1-}" added      # FPC :2527: write, THEN cnAdded
    return 0
}

TQueue.Dequeue() {
    # -> RESULT = front (FPC :2530 = DoRemove(FLow, cnRemoved)); empty -> the
    # EArgumentOutOfRange analog: rc 1, RESULT '', debug-only msg.
    local __tqs_val
    if TQueueStack._qremove removed; then
        kk._return "$__tqs_val"
        return 0
    fi
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "Error: TQueue.Dequeue: queue is empty" >&2
    kk._return ""
    return 1
}

TQueue.Extract() {
    # -> RESULT = front, 'extracted' action (FPC :2535) — same removal, the
    # action difference matters from P3/P4 on (no free, callback sees it).
    local __tqs_val
    if TQueueStack._qremove extracted; then
        kk._return "$__tqs_val"
        return 0
    fi
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "Error: TQueue.Extract: queue is empty" >&2
    kk._return ""
    return 1
}

TQueue.Peek() {
    # -> RESULT = front WITHOUT removal (FPC :2540); empty -> rc 1.
    local -n __tqs_it="${__inst__}_items"
    local -n __tqs_h="${__inst__}_qhead"
    if (( ${#__tqs_it[@]} == 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TQueue.Peek: queue is empty" >&2
        kk._return ""
        return 1
    fi
    kk._return "${__tqs_it[__tqs_h]}"
    return 0
}

TQueue.TryDequeue() {
    # bash extra (house Try* pattern): like Dequeue but SILENT on empty —
    # rc 1 is an answer, not an error.
    local __tqs_val
    if TQueueStack._qremove removed; then
        kk._return "$__tqs_val"
        return 0
    fi
    kk._return ""
    return 1
}

TQueue.Clear() {
    # FPC :2548: a Dequeue LOOP (per-item removed events in FIFO order from
    # P3 on) + head/length reset — NOT a bulk wipe.
    local __tqs_val
    while TQueueStack._qremove removed; do :; done
    local -n __tqs_h="${__inst__}_qhead"
    __tqs_h=0
    return 0
}

# outArr -> front->back (S9: FPC queue enumerator starts at FLow); RESULT=count.
# CALL DIRECTLY ($() discards the fill). ${!items[@]} ascends over the live
# region = front->back.
TQueue.ToArray() { TQueueStack._toArray "$1"; }

# ---- P2 stack plain helpers ---------------------------------------------------

# Remove the TOP element (FPC TStack.DoRemove :2591 — capture, clear slot,
# Dec(FLength), Notify tail). The stack array is DENSE by construction (only
# push/pop touch it) -> top == count-1; never generalize this to the queue
# side (holes live there by design). $1 = action (removed|extracted), threaded
# for the P3 Notify tail. Caller declares: local __tqs_val
TQueueStack._sremove() {
    local -n __tqs_it="${__inst__}_items"
    local __tqs_top=$(( ${#__tqs_it[@]} - 1 ))
    if (( __tqs_top < 0 )); then
        __tqs_val=""
        return 1
    fi
    __tqs_val="${__tqs_it[__tqs_top]}"
    unset "${__inst__}_items[$__tqs_top]"
    # Notify tail (FPC TStack.DoRemove :2599) — covers Pop/Extract/TryPop/
    # Clear/Destroy.
    TQueueStack._notify "$__tqs_val" "$1"
    return 0
}

# ---- P2 members: TStack core ---------------------------------------------------

TStack.Push() {
    # v — append at the top (FPC :2622: write, then notify added — P3 appends
    # the Notify). Dense array: += lands at count.
    local -n __tqs_it="${__inst__}_items"
    __tqs_it+=( "${1-}" )
    TQueueStack._notify "${1-}" added      # FPC :2628
    return 0
}

TStack.Pop() {
    # -> RESULT = top (FPC :2631 = DoRemove(FLength-1, cnRemoved)); empty ->
    # rc 1, RESULT '', debug-only msg (EArgumentOutOfRange analog).
    local __tqs_val
    if TQueueStack._sremove removed; then
        kk._return "$__tqs_val"
        return 0
    fi
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "Error: TStack.Pop: stack is empty" >&2
    kk._return ""
    return 1
}

TStack.Extract() {
    # -> RESULT = top, 'extracted' action (FPC :2644).
    local __tqs_val
    if TQueueStack._sremove extracted; then
        kk._return "$__tqs_val"
        return 0
    fi
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "Error: TStack.Extract: stack is empty" >&2
    kk._return ""
    return 1
}

TStack.Peek() {
    # -> RESULT = top WITHOUT removal (FPC :2636); empty -> rc 1.
    local -n __tqs_it="${__inst__}_items"
    local __tqs_top=$(( ${#__tqs_it[@]} - 1 ))
    if (( __tqs_top < 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TStack.Peek: stack is empty" >&2
        kk._return ""
        return 1
    fi
    kk._return "${__tqs_it[__tqs_top]}"
    return 0
}

TStack.TryPop() {
    # bash extra: like Pop but SILENT on empty (rc 1 is an answer).
    local __tqs_val
    if TQueueStack._sremove removed; then
        kk._return "$__tqs_val"
        return 0
    fi
    kk._return ""
    return 1
}

TStack.Clear() {
    # FPC :2608: a Pop LOOP — per-item removed events in LIFO order from P3 on.
    local __tqs_val
    while TQueueStack._sremove removed; do :; done
    return 0
}

# outArr -> bottom->top (S9; seed TestToArray: A[i-1]==IntToStr(i)); RESULT=count.
TStack.ToArray() { TQueueStack._toArray "$1"; }

# The virtual Notify seam — the base classes just fire the user event.
# Callback signature: <inst> <item> <added|removed|extracted>.
TQueue.Notify() { TQueueStack._fireNotify "$@"; }
TStack.Notify() { TQueueStack._fireNotify "$@"; }

# ---- P4: the owning overrides --------------------------------------------------

TObjectQueue.Notify() {
    # FPC :2696 verbatim: INHERITED FIRST (the user callback observes the
    # instance ALIVE — out of storage, not yet freed), then free on removed
    # when owning. The two lines are the whole override; the free logic is
    # shared (_freeOnRemoved), the inherited call must stay per-body.
    inherited Notify "$@"
    TQueueStack._freeOnRemoved "$@"
}

TObjectQueue.Dequeue() {
    # S8 QUIRK PRESERVED (FPC :2726: `procedure Dequeue`): the dequeued — and,
    # when owning, ALREADY FREED — object is NOT returned. This override is a
    # PROC, so the caller's RESULT is untouched (dispatch rollback); rc passes
    # through (empty queue -> rc 1). Use Extract to take ownership.
    inherited Dequeue
}

TObjectStack.Notify() {
    # FPC :2733 — same shape as the queue side.
    inherited Notify "$@"
    TQueueStack._freeOnRemoved "$@"
}

TObjectStack.Pop() {
    # S8 QUIRK PRESERVED (FPC :2763: `Result := inherited Pop`): returns the
    # handle of an instance that ownership JUST FREED — FPC hands back a
    # dangling pointer, bash hands back a dead handle string (safe to hold,
    # dead to dispatch on). Use Extract to keep it alive.
    inherited Pop
    local __tqs_rc=$?
    kk._return "$RESULT"
    return $__tqs_rc
}

# Finalize (parents before children).
build TQueue
build TStack
build TObjectQueue
build TObjectStack
