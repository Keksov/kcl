#!/bin/bash

# ===========================================================================
# thashset — a bash port of FPC rtl-generics THashSet<T> (one class).
#
# Source of truth: packages/rtl-generics/src/generics.collections.pas —
# TCustomSet<T> (:513, the abstract set surface + set-algebra impls
# AddRange :2815 / UnionWith :2853 / IntersectWith :2861 / ExceptWith :2878 /
# SymmetricExceptWith :2886), THashSet<T> (:570, impl :2986-3041). FPC's own
# THashSet IS a dictionary with empty values (:2988: FInternalDictionary =
# TOpenAddressingLP<T, TEmptyRecord>) — so this port is the tdictionary storage
# layer minus the value dimension, plus the set algebra (the actual reason to
# want a set in bash). FPC fpcunit seed (P0-verified): tests.generics.sets.pas
# Test_Set_General (:86) — a full algebra truth-table with hand-computed
# results (mined at P2). Plan/ledger: kcl/thashset/{PLAN.md,thashset_ledger.json}.
#
# ---- Storage = tdictionary minus values (idioms REUSED verbatim) ------------
# ${inst}_items assoc; membership = items["k$item"]=1 (the value is a dummy).
# All four pinned tdictionary idioms carry over unchanged:
#   * k-prefix subscript (items["k$item"]) — never an empty subscript;
#   * existence via ${ref["k$item"]+x};
#   * deletion via pk="k$item"; unset 'ref[$pk]' (single-quoted, expanded once);
#   * iteration strips the prefix: for pk in "${!ref[@]}"; item="${pk#k}".
# count == ${#items[@]} (computed, tdictionary principle).
#
# NB (review 2026-09-06, findings G2-01/G2-06): "verbatim" was a CLAIM, not a
# fact, until P2 — the deletion idiom was written with DOUBLE quotes here, so
# `unset` re-parsed the already-substituted subscript: every element containing
# ] [ $ ' " \ or a backtick survived Remove/Extract with rc 0, and $( ) content
# was executed. The single-quoted form is now really used in both places, and
# tests/002 exercises Remove and Extract on the exotic set (the old torture
# covered only Add/Contains/ToArray, which is why the suite stayed green).
#
# ---- The LOUD difference from TDictionary (S1/S2) ---------------------------
# Set Add/Remove return BOOLEANS (FPC :3002/:3009), NOT the dictionary's
# raise-on-dup / always-true. Here the Boolean IS the exit status and rc=1 is
# a SILENT ANSWER, never an error (no debug msg): Add -> rc 0 added / rc 1
# already-present; Remove -> rc 0 removed / rc 1 absent; Contains -> rc 0/1;
# AddRange -> rc 0 iff ALL were newly added (FPC AND-fold :2821). README
# carries a TDictionary-vs-THashSet comparison box.
#
# ---- Set algebra (FPC :2853-2903, snapshot-safe) ----------------------------
# UnionWith: Add each of other's elements. IntersectWith: two-pass (collect
# self's non-members-of-other, then Remove them) -> self-op = no-op.
# ExceptWith: Remove each of other's elements -> self-op = full drain.
# SymmetricExceptWith: two-pass (for each of other: contained -> mark, else
# Add; then Remove the marked) -> self-op = empty (a XOR a = empty). Every op
# SNAPSHOTS the other set's keys BEFORE mutating self (bash cannot iterate an
# assoc while modifying it); the operand must be a live THashSet.
#
# ---- Return contract ---------------------------------------------------------
# Boolean members are `proc` (rc-only; the tdictionary contract). Extract/Count/
# ToArray are `func` (RESULT; kk._return on explicit-return paths). Extract miss
# -> RESULT='' rc 0 (FPC Default(T) :3025 — indistinguishable from extracting
# the ''-element; disambiguate with Contains). ToArray fills a caller nameref
# (lossless) + RESULT=count — CALL DIRECTLY. RESERVED NAMES: never pass caller
# arrays named __ts_* (nameref shadowing, the tinifile P2 lesson) — the name is
# VALIDATED, and a reserved, malformed or associative output name is rc 2 +
# RESULT='' with the storage untouched (kcl/README.md 1.2/1.7, finding G2-02).
# ===========================================================================

# Re-source guard.
if [[ -n "${_THASHSET_SOURCED:-}" ]]; then
    return
fi
declare -g _THASHSET_SOURCED=1

THASHSET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THASHSET_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Member surface frozen at P0; bodies land per phase:
#   P1 membership core, P2 set algebra, P3 events.
# ---------------------------------------------------------------------------
class THashSet
    public
        constructor Create
        destructor  Destroy
        var on_notify              # P3: callback fn name; '' = off
        func Count                 # RESULT = live count (fork-free)
        proc Add                   # P1  item -> rc 0 added / 1 dup (silent)
        proc Remove                # P1  item -> rc 0 removed / 1 absent
        proc Contains              # P1  item -> rc 0/1
        func Extract               # P1  item -> RESULT (hit item / '' miss), rc 0
        proc Clear                 # P1  (empty-first-then-notify, S4)
        func ToArray               # P1  outArr -> RESULT=count (lossless)
        proc ForEach               # P1  cb — snapshot semantics
        proc Assign                # P1  src — copy from another THashSet
        proc AddRange              # P2  i1 [i2 ...] -> rc 0 iff all added
        proc AddRangeFromArray     # P2  arrName — bulk from a caller array
        proc UnionWith             # P2  other
        proc IntersectWith         # P2  other
        proc ExceptWith            # P2  other
        proc SymmetricExceptWith   # P2  other
        proc Notify                # P3  virtual seam: <item> <action>
end

# ---- plain helpers (survive `build`; the safe cross-member mechanism) --------

TSet._init() {
    on_notify=""
    declare -gA "${__inst__}_items=()"
}

TSet._teardown() {
    unset "${__inst__}_items"
}

# The event gate (tdictionary P5 hot-path guard): dispatch the virtual Notify
# only when a listener is set — otherwise one [[ ]] per mutation, no dispatch.
# Threaded NOW at every mutation (Add/Remove/Extract/Clear); P3 only fills the
# Notify body (the tqueuestack lesson: wire the tail once, events come free).
# $1=item $2=added|removed|extracted.
TSet._notify() {
    if [[ -n "$on_notify" ]]; then
        $this.Notify "$1" "$2"
    fi
    return 0
}

# Validate that $1 names a live THashSet (or a descendant) BEFORE any mutation
# — the Assign/operand-validation atomicity lesson. rc 0 ok / 1 not.
#
# G2-04 / decision R5: the CLASS decides, not the mere presence of an `_items`
# array. The old `declare -p ${1}_items` check accepted a TQueue (`A.Assign Q`
# rewrote the storage to `([0]=1 [1]=1)` — subscripts without the `k` prefix, so
# `Contains` missed everything the set now claimed to hold) and a TDictionary.
TSet._isSet() {
    local __ts_c="${1:-}" __ts_cv
    [[ -n "$__ts_c" ]] || return 1
    __ts_cv="${__ts_c}_class"
    __ts_c="${!__ts_cv:-}"
    while [[ -n "$__ts_c" ]]; do
        if [[ "$__ts_c" == "THashSet" ]]; then return 0; fi
        __ts_cv="${__ts_c}_parent_class"
        __ts_c="${!__ts_cv:-}"
    done
    return 1
}

# Validate a caller-supplied OUTPUT ARRAY name (kcl/README.md 1.7) BEFORE the
# nameref is bound, so a rejected name cannot touch anything. rc 0 ok / 1 not
# (the CALLER maps a rejection to rc 2, see THashSet.ToArray).
#
# G2-02: `h.ToArray __ts_it` aliased the unit's own nameref and the fill loop
# appended the set's storage to itself; an empty or malformed name produced a
# bash error on stderr, filled a throwaway local and still returned rc 0.
TSet._outName() {
    local __ts_n="${1:-}"
    case "$__ts_n" in
        ""|__ts_*|__kk_*|__KK_*|RESULT|REPLY|IFS|this|__inst__|__class__) return 1 ;;
    esac
    [[ "$__ts_n" == "${__inst__}_items" ]] && return 1
    [[ "$__ts_n" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || return 1
    return 0
}

# ---- method bodies (P0: ctor/dtor/Count real; the rest arrive per phase) -----

THashSet.Create() {
    TSet._init
    return 0
}

THashSet.Destroy() {
    # FPC :2996: Free the internal dictionary -> its Clear fires removed events
    # during delete (S5). P3 wires $this.Clear here; P0 just tears storage down.
    TSet._teardown
    return 0
}

# count == ${#items[@]} (set elements only): one nameref, zero math.
THashSet.Count() {
    local -n __ts_it="${__inst__}_items"
    kk._return "${#__ts_it[@]}"
    return 0
}

# ---- per-phase pending members (thin sentinels; removed as phases land) ------
TSet._pending() {
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "thashset: $1 arrives in $2" >&2
    kk._return "__ths_pending__:$1"
    return 0
}

# ---- P1 members: membership core ---------------------------------------------

THashSet.Add() {
    # item -> rc 0 added / rc 1 already-present (SILENT — a Boolean answer, not
    # an error; FPC :3002 = `not ContainsKey; if new: dict.Add`). No event, no
    # mutation on a duplicate. Notify fires AFTER the write (added).
    local __ts_pk="k$1"
    declare -n __ts_it="${__inst__}_items"
    [[ -n ${__ts_it[$__ts_pk]+x} ]] && return 1
    __ts_it[$__ts_pk]=1
    TSet._notify "$1" added
    return 0
}

THashSet.Remove() {
    # item -> rc 0 removed / rc 1 absent (SILENT; FPC :3009 Boolean). Notify
    # fires AFTER the element is gone (removed).
    local __ts_pk="k$1"
    declare -n __ts_it="${__inst__}_items"
    [[ -n ${__ts_it[$__ts_pk]+x} ]] || return 1
    # SINGLE quotes (G2-01): `unset` expands its argument, so the DOUBLE-quoted
    # form `unset "${__inst__}_items[$__ts_pk]"` handed bash a subscript that
    # had already been substituted and was then parsed AGAIN — every element
    # containing ] [ $ ' " \ or a backtick survived the Remove with rc 0, and
    # `$( )` / backtick content was EXECUTED. This is the tdictionary idiom
    # (tdictionary.sh:223/270) that this unit's header claims to reuse verbatim.
    unset '__ts_it[$__ts_pk]'
    TSet._notify "$1" removed
    return 0
}

THashSet.Contains() {
    # item -> rc 0 present / rc 1 absent (FPC :3036 Boolean).
    local -n __ts_it="${__inst__}_items"
    [[ -n ${__ts_it["k$1"]+x} ]]
}

THashSet.Extract() {
    # item -> RESULT (FPC :3019). Hit: RESULT=item, remove, 'extracted' event.
    # Miss: RESULT='' (Default(T)), NO removal, NO event. rc 0 BOTH ways (it is
    # a function, not an error path) — the miss is indistinguishable from
    # extracting the ''-element; disambiguate with Contains first.
    local __ts_pk="k$1"
    declare -n __ts_it="${__inst__}_items"
    if [[ -z ${__ts_it[$__ts_pk]+x} ]]; then
        kk._return ""
        return 0
    fi
    unset '__ts_it[$__ts_pk]'          # single-quoted, see Remove (G2-01)
    TSet._notify "$1" extracted
    kk._return "$1"
    return 0
}

THashSet.Clear() {
    # FPC :3031 -> internal dict Clear = empty the storage FIRST, THEN notify
    # every old element 'removed' (S4 — callbacks observe an already-empty set;
    # the tdictionary Clear model verbatim).
    local __ts_dv="${__inst__}_items"
    declare -n __ts_it="$__ts_dv"
    if [[ -n "$on_notify" ]] && (( ${#__ts_it[@]} > 0 )); then
        local -a __ts_ks=( "${!__ts_it[@]}" )
        __ts_it=()
        local __ts_k
        for __ts_k in "${__ts_ks[@]}"; do
            TSet._notify "${__ts_k#k}" removed
        done
    else
        __ts_it=()
    fi
    return 0
}

THashSet.ToArray() {
    # outArr -> the elements (k-prefix stripped), RESULT=count. Order is hash
    # iteration order (UNSPECIFIED, like all assoc iteration). CALL DIRECTLY
    # ($() discards the fill). Lossless: exotic elements round-trip byte-exact.
    # The name is validated BEFORE the nameref is bound (G2-02): a reserved or
    # malformed name is **rc 2** with the storage untouched, never a self-alias
    # — a name that cannot receive the fill is a malformed CALL, not a value the
    # caller may legitimately try (kcl/README.md 1.2 and 1.7; owner decision
    # 2026-09-07 over the rc 1 the review report had suggested).
    if ! TSet._outName "${1:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: THashSet.ToArray: bad output array name '${1:-}'" >&2
        kk._return ""
        return 2
    fi
    local -n __ts_out="$1" 2>/dev/null || { kk._return ""; return 2; }
    if [[ "${__ts_out@a}" == *A* ]]; then      # an assoc target would get 0,1,2… keys
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: THashSet.ToArray: '$1' is an associative array" >&2
        kk._return ""
        return 2
    fi
    __ts_out=()
    local -n __ts_it="${__inst__}_items"
    local __ts_k
    for __ts_k in "${!__ts_it[@]}"; do
        __ts_out+=( "${__ts_k#k}" )
    done
    kk._return "${#__ts_out[@]}"
    return 0
}

THashSet.ForEach() {
    # cb — invoke `cb <item>` for each element. SNAPSHOT semantics (the keys are
    # captured first, so a cb that mutates the set sees a stable iteration; the
    # tdictionary ForEach clone). cb rc is ignored. Order UNSPECIFIED.
    # G2-05: a dangling callback used to produce one "command not found" per
    # element and rc 0. Validate it once, up front, like tdictionary.ForEach.
    local __ts_cb="${1:-}"
    if [[ -z "$__ts_cb" ]] || ! declare -F "$__ts_cb" >/dev/null 2>&1; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: THashSet.ForEach: callback '$__ts_cb' is not a function" >&2
        return 1
    fi
    local -n __ts_it="${__inst__}_items"
    local -a __ts_ks=( "${!__ts_it[@]}" )
    local __ts_k
    for __ts_k in "${__ts_ks[@]}"; do
        "$__ts_cb" "${__ts_k#k}" || :
    done
    return 0
}

THashSet.Assign() {
    # src — replace this set's contents with a COPY of src's (another live
    # THashSet). Operand validated BEFORE any mutation (atomicity). Fires
    # removed (old) then added (new) when a listener is set. Self-assign is a
    # no-op-ish rebuild (snapshot first).
    if ! TSet._isSet "$1"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: THashSet.Assign: '$1' is not a THashSet" >&2
        return 1
    fi
    local -n __ts_src="${1}_items"
    local -a __ts_srcks=( "${!__ts_src[@]}" )   # snapshot BEFORE clearing self
    $this.Clear
    local -n __ts_it="${__inst__}_items"
    local __ts_k
    for __ts_k in "${__ts_srcks[@]}"; do
        __ts_it[$__ts_k]=1
        TSet._notify "${__ts_k#k}" added
    done
    return 0
}

THashSet.AddRange()            { TSet._pending AddRange            P2; }
THashSet.AddRangeFromArray()   { TSet._pending AddRangeFromArray   P2; }
THashSet.UnionWith()           { TSet._pending UnionWith           P2; }
THashSet.IntersectWith()       { TSet._pending IntersectWith       P2; }
THashSet.ExceptWith()          { TSet._pending ExceptWith          P2; }
THashSet.SymmetricExceptWith() { TSet._pending SymmetricExceptWith P2; }
THashSet.Notify()              { TSet._pending Notify              P3; }

# Finalize.
build THashSet
