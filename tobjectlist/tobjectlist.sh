#!/bin/bash

# ===========================================================================
# tobjectlist — a bash port of FPC contnrs.TObjectList: the OWNING list.
#
# Source of truth: packages/fcl-base/src/contnrs.pp, TObjectList = class(TList)
# (:82-102). Parity oracle: packages/fcl-base/tests/utcobjectlist.pp (9 fpcunit
# tests, mined in tests/ at P1). Plan/ledger: kcl/tobjectlist/PLAN.md,
# tobjectlist_ledger.json.
#
# ---- Model -----------------------------------------------------------------
# An element is a kklass instance HANDLE (the instance name string); "free" is
# `$handle.delete`. `owns_objects` (FPC OwnsObjects, default TRUE) decides
# whether REMOVAL paths also free the instance. FPC routes ownership through
# one seam — Notify(Ptr, lnDeleted); bash TList has no notification seam, so
# TObjectList overrides each removal path instead and composes via kklass
# `inherited` (probed: `inherited MethodName args` works in ANY method body —
# rewritten to $this.parent — so every override is `<free>; inherited X "$@"`,
# zero duplication).
#
# Ownership fires on: Delete, Clear, Remove, Put (replacement frees the OLD
# item unless it is the same handle), the destructor, BatchDelete (bash extra).
# NOT on: Add/Insert/Extract/Exchange/Move/Sort (FPC fires no lnDeleted there).
# Extract = remove WITHOUT freeing (release of ownership).
#
# ---- The _free guard --------------------------------------------------------
# TObjectList._free frees a handle ONLY if it is a LIVE kklass instance: the
# per-instance dispatcher function `<handle>.delete` exists exactly while the
# instance is alive (probed on both bashes). Consequences, documented:
#   * double-free is a SILENT NO-OP (dispatcher gone after the first delete);
#   * a non-instance string in an owning list is a SILENT NO-OP.
# This is a deliberate bash-side softening of FPC, where nil.Free is safe but
# TObject(garbage).Free crashes — the guard generalizes the nil case.
#
# FindInstanceOf(Class [exact=true|false] [startAt]) is fully ported: a live
# instance knows its class (${handle}_class) and kklass exposes the ancestor
# chain (${class}_parent_class) for the non-exact IS-A walk.
# ===========================================================================

# Re-source guard.
if [[ -n "$_TOBJECTLIST_SOURCED" ]]; then
    return
fi
declare -g _TOBJECTLIST_SOURCED=1

# Parent class (transitively: kklass front-end, klib/kerr, tarray).
TOBJECTLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOBJECTLIST_DIR/../tlist/tlist.sh"

# ---------------------------------------------------------------------------
# Class structure (P1-complete). Removal paths override the TList members and
# compose as `<free if owns>; inherited X "$@"`. Extract and FindInstanceOf
# are new members (FPC :93/:96). Everything else (Add/Insert/First/Last/Get/
# IndexOf/Sort/CustomSort/Exchange/Move/Pack/Assign) is inherited unchanged —
# FPC fires no lnDeleted on those paths.
# ---------------------------------------------------------------------------
class TObjectList : TList
    public
        constructor Create
        destructor  Destroy
        var owns_objects
        override proc Delete
        override proc Clear
        override func Remove
        override proc Put
        override proc BatchDelete
        func Extract
        func FindInstanceOf
end

# ---- plain helper (no kklass dispatch) --------------------------------------

# TObjectList._free <handle> — free a LIVE kklass instance; anything else is a
# silent no-op (see header). Always returns 0.
TObjectList._free() {
    if [[ -n "$1" ]] && declare -F "$1.delete" >/dev/null 2>&1; then
        "$1".delete
    fi
    return 0
}

# ---- method bodies -----------------------------------------------------------

TObjectList.Create() {
    # FPC: Create -> OwnsObjects=True; Create(FreeObjects) -> as given.
    # Token mirrors the Boolean: `TObjectList.new L [true|false]`. Unknown
    # token -> rc 1 (list is still a valid OWNING list), message under
    # VERBOSE_KKLASS=debug — the house token convention (TStopwatch startnew).
    inherited
    owns_objects=true
    if [[ -n "${1:-}" ]]; then
        case "$1" in
            true)  owns_objects=true ;;
            false) owns_objects=false ;;
            *)
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
                    echo "Error: TObjectList.Create: unknown token '$1' (expected 'true' or 'false')" >&2
                return 1 ;;
        esac
    fi
}

TObjectList.Destroy() {
    # FPC: destroying the list Clears it; with OwnsObjects=True every element
    # is freed (Notify lnDeleted). Here: free owned elements [0,count), then
    # kklass tears the instance down as usual. Dynamic scope provides $count
    # and the items array (probed M4).
    if [[ "$owns_objects" == "true" ]]; then
        local __tol_i __tol_items_var="${__inst__}_items"
        declare -n __tol_items_ref="$__tol_items_var"
        for (( __tol_i = 0; __tol_i < count; __tol_i++ )); do
            TObjectList._free "${__tol_items_ref[__tol_i]}"
        done
    fi
}

# ---- removal-path overrides: <free if owns> ; inherited X "$@" ---------------
# Bounds are validated BEFORE freeing (an invalid index must free nothing);
# the inherited call then enforces/errors exactly as TList always did.

TObjectList.Delete() {
    # FPC: Delete -> Notify(old, lnDeleted) -> freed when OwnsObjects.
    if [[ "$owns_objects" == "true" ]]; then
        local __tol_index="$1"
        if (( __tol_index >= 0 && __tol_index < count )); then
            local __tol_items_var="${__inst__}_items"
            declare -n __tol_items_ref="$__tol_items_var"
            TObjectList._free "${__tol_items_ref[__tol_index]}"
        fi
    fi
    inherited Delete "$@"
}

TObjectList.Clear() {
    # FPC: Clear deletes every element -> all freed when OwnsObjects.
    if [[ "$owns_objects" == "true" ]]; then
        local __tol_i __tol_items_var="${__inst__}_items"
        declare -n __tol_items_ref="$__tol_items_var"
        for (( __tol_i = 0; __tol_i < count; __tol_i++ )); do
            TObjectList._free "${__tol_items_ref[__tol_i]}"
        done
    fi
    inherited Clear "$@"
}

TObjectList.Remove() {
    # FPC: Remove finds the item and Deletes it -> freed when OwnsObjects.
    # The handle is freed BEFORE the inherited removal: the parent only does
    # string comparisons on the handle, so instance liveness is irrelevant to
    # it. RESULT (found index / -1) comes from the inherited call.
    if [[ "$owns_objects" == "true" ]]; then
        $this.IndexOf "$1"
        if [[ "$RESULT" != "-1" ]]; then
            TObjectList._free "$1"
        fi
    fi
    inherited Remove "$@"
}

TObjectList.Put() {
    # FPC SetItem -> Put -> the OLD item gets Notify(lnDeleted) — freed when
    # OwnsObjects, UNLESS the new item IS the old one (FPC TList.Put only
    # notifies when the pointer actually changes).
    if [[ "$owns_objects" == "true" ]]; then
        local __tol_index="$1" __tol_new="$2"
        if (( __tol_index >= 0 && __tol_index < count )); then
            local __tol_items_var="${__inst__}_items"
            declare -n __tol_items_ref="$__tol_items_var"
            local __tol_old="${__tol_items_ref[__tol_index]}"
            if [[ "$__tol_old" != "$__tol_new" ]]; then
                TObjectList._free "$__tol_old"
            fi
        fi
    fi
    inherited Put "$@"
}

TObjectList.BatchDelete() {
    # bash extra in TList (a removal path — an owning list must not leak
    # through it). Mirror the parent's validation + clamping to decide WHAT
    # gets freed, then let the parent do the actual work.
    if [[ "$owns_objects" == "true" ]]; then
        local __tol_index="$1" __tol_cnt="$2"
        if (( __tol_index >= 0 && __tol_index < count )); then
            (( __tol_index + __tol_cnt > count )) && __tol_cnt=$(( count - __tol_index ))
            if (( __tol_cnt > 0 )); then
                local __tol_i __tol_items_var="${__inst__}_items"
                declare -n __tol_items_ref="$__tol_items_var"
                for (( __tol_i = __tol_index; __tol_i < __tol_index + __tol_cnt; __tol_i++ )); do
                    TObjectList._free "${__tol_items_ref[__tol_i]}"
                done
            fi
        fi
    fi
    inherited BatchDelete "$@"
}

# ---- new members (FPC :93 / :96) ---------------------------------------------

TObjectList.Extract() {
    # FPC: Extract removes the item WITHOUT freeing it (Notify lnExtracted —
    # ownership released to the caller) and returns it. `inherited Delete`
    # resolves PAST our own freeing Delete override straight to TList.Delete
    # (probed M2) — exactly the no-free removal we need.
    # RESULT = the handle (rc 0) / "" (rc 1 when not present).
    local __tol_item="$1"
    $this.IndexOf "$__tol_item"
    local __tol_idx="$RESULT"
    if [[ "$__tol_idx" == "-1" ]]; then
        # kk._return, not bare RESULT=: an explicit return skips the auto-
        # appended func trailer, and _invoke would restore the caller's RESULT
        # (the tdictionary "trailer trap").
        kk._return ""
        return 1
    fi
    inherited Delete "$__tol_idx"
    kk._return "$__tol_item"
    return 0
}

TObjectList.FindInstanceOf() {
    # FPC: FindInstanceOf(AClass, AExact, AStartAt) -> index of the first
    # element that IS the class (exact) or DESCENDS from it (non-exact), or -1.
    # Bash: FindInstanceOf ClassName [exact=true|false] [startAt=0]. A live
    # kklass instance knows its class (${handle}_class); the ancestor walk uses
    # kklass's ${class}_parent_class chain. Non-instance elements never match.
    # Every exit is an explicit return -> every exit needs kk._return (the
    # func trailer only fires on fall-through; see Extract).
    local __tol_cls="$1" __tol_exact="${2:-true}" __tol_start="${3:-0}"
    if [[ -z "$__tol_cls" ]]; then kk._return "-1"; return 2; fi
    (( __tol_start < 0 )) && __tol_start=0
    local __tol_i __tol_h __tol_c __tol_cvar __tol_pvar
    local __tol_items_var="${__inst__}_items"
    declare -n __tol_items_ref="$__tol_items_var"
    for (( __tol_i = __tol_start; __tol_i < count; __tol_i++ )); do
        __tol_h="${__tol_items_ref[__tol_i]}"
        [[ -n "$__tol_h" ]] && declare -F "${__tol_h}.delete" >/dev/null 2>&1 || continue
        __tol_cvar="${__tol_h}_class"
        __tol_c="${!__tol_cvar:-}"
        if [[ "$__tol_exact" == "false" ]]; then
            while [[ -n "$__tol_c" ]]; do
                if [[ "$__tol_c" == "$__tol_cls" ]]; then kk._return "$__tol_i"; return 0; fi
                __tol_pvar="${__tol_c}_parent_class"
                __tol_c="${!__tol_pvar:-}"
            done
        else
            if [[ "$__tol_c" == "$__tol_cls" ]]; then kk._return "$__tol_i"; return 0; fi
        fi
    done
    kk._return "-1"
    return 1
}

# Finalize the class.
build TObjectList
