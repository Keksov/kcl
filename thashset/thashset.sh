#!/bin/bash

# ===========================================================================
# thashset — a bash port of FPC rtl-generics THashSet<T> (one class).
#
# Source of truth: packages/rtl-generics/src/generics.collections.pas at the
# **release_3_2_2** tag — TCustomSet<T> (the abstract set surface + the
# set-algebra implementations AddRange :2379 / UnionWith :2417 /
# IntersectWith :2425 / ExceptWith :2442 / SymmetricExceptWith :2450) and
# THashSet<T> (Destroy :2554, Add :2559, Remove :2566, Extract :2576,
# Clear :2588, Contains :2593). FPC's own THashSet IS a dictionary with empty
# values (FInternalDictionary = TOpenAddressingLP<T, TEmptyRecord>) — so this
# port is the tdictionary storage layer minus the value dimension, plus the set
# algebra (the actual reason to want a set in bash). FPC fpcunit seed
# (P0-verified, mined at P2): tests.generics.sets.pas Test_Set_General :86-152 —
# a full algebra truth-table with hand-computed results.
# Plan/ledger: kcl/thashset/{PLAN.md,thashset_ledger.json}.
#
# NB on line numbers: P0 recorded :2815/:2853/:2861/:2878/:2886 and
# :3002/:3009/:3019/:3031 from a DIFFERENT revision of the same file. The code
# is identical word for word; only the line numbers moved. Everything quoted
# here and in the P2 ledger entry is the release_3_2_2 tag.
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
# Set Add/Remove return BOOLEANS (FPC :2559/:2566), NOT the dictionary's
# raise-on-dup / always-true. Here the Boolean IS the exit status and rc=1 is
# a SILENT ANSWER, never an error (no debug msg): Add -> rc 0 added / rc 1
# already-present; Remove -> rc 0 removed / rc 1 absent; Contains -> rc 0/1;
# AddRange/AddRangeFromArray -> rc 0 iff ALL were newly added (the FPC AND-fold
# :2379-2385, so zero items = rc 0 and a duplicate INSIDE the argument list is
# rc 1 too). README carries a TDictionary-vs-THashSet comparison box.
#
# ---- Set algebra (FPC :2417-2467, snapshot-safe) ----------------------------
# UnionWith: Add each of other's elements. IntersectWith: two-pass (collect
# self's non-members-of-other, then Remove them) -> self-op = no-op.
# ExceptWith: Remove each of other's elements -> self-op = full drain.
# SymmetricExceptWith: two-pass (for each of other: contained -> mark, else
# Add; then Remove the marked) -> self-op = empty (a XOR a = empty). Every op
# SNAPSHOTS the other set's keys BEFORE mutating self (bash cannot iterate an
# assoc while modifying it); the operand must be a live THashSet, checked by
# CLASS before ANY mutation, so a rejected operand leaves the set byte-identical
# (rc 1 + kk.debug — the four ops are procedures in FPC and carry no Boolean).
# The loops drive the public $this.Add / $this.Remove / $this.Contains, exactly
# as TCustomSet drives THashSet's Booleans, so the event stream is identical to
# the same calls made by hand.
#
# ---- Return contract ---------------------------------------------------------
# Boolean members are `proc` (rc-only; the tdictionary contract). Extract/Count/
# ToArray are `func` (RESULT; kk._return on explicit-return paths). Extract miss
# -> RESULT='' rc 0 (FPC Default(T) :2582 — indistinguishable from extracting
# the ''-element; disambiguate with Contains). ToArray fills a caller nameref
# (lossless) + RESULT=count — CALL DIRECTLY. RESERVED NAMES: never pass caller
# arrays named __ts_* (nameref shadowing, the tinifile P2 lesson) — the name is
# VALIDATED, and a reserved, malformed or associative output name is rc 2 +
# RESULT='' with the storage untouched (kcl/README.md 1.2/1.7, finding G2-02).
# The same validation guards AddRangeFromArray's INPUT name, and a non-array or
# associative source is rc 2 as well.
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
    # P2-F1: the operand name is fed to an INDIRECT expansion two lines below,
    # and `${!x}` on a name that is not an identifier makes bash print
    # `not a name_class: invalid variable name` on stderr. rc and atomicity were
    # already right; the SILENCE of kcl/README.md 1.2 was not (`A.Assign 'a[0]'`
    # answered rc 1 with a bash diagnostic). Shape first, then the class walk.
    case "$__ts_c" in
        *[!A-Za-z0-9_]*|[0-9]*) return 1 ;;
    esac
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
#
# The rule is `kk._outName` in kkore/klib.sh (P9, P8-F1): identifier shape, the
# README §1.7 reserved set, the `__kk_`/`__KK_` space, the `__ts_` prefix and the
# instance's own `_data`/`_class`/`_items`.
TSet._outName() {
    kk._outName "${1:-}" __ts_ || return 1
    return 0
}

# Is the named variable an ASSOCIATIVE array? It would silently collect the keys
# 0,1,2… instead of the elements, so it is refused like a bad name.
#
# P9-F3: `${ref@a}` aborts under `set -u` whenever the target has no value yet,
# and `declare -a out=()` — the normal way to prepare a receiving array — is
# exactly that shape, so `h.ToArray out` killed the caller. The option is
# switched off for this one expansion; `local -` makes `$-` local to THIS
# function and bash restores it on return, so there is no fork and nothing
# leaks to the caller (the tinifile P8 shape).
TSet._isAssoc() {
    local -
    set +u
    local -n __ts_probe="$1" 2>/dev/null || return 1
    [[ "${__ts_probe@a}" == *A* ]]
}

# Is the named variable a usable INPUT array for AddRangeFromArray, i.e. an
# INDEXED array that actually exists? An associative array would contribute its
# VALUES in hash order under an interface that promises "the array's elements",
# a scalar would contribute one element that is not an array member at all, and
# an unset name would silently contribute nothing — all three are malformed
# CALLS (rc 2), not values a caller may legitimately try.
#
# `${ref@a}` answers `a` for an indexed array (declared-but-never-assigned
# included), `A` for an associative one and '' for a scalar or an unset name;
# the `local -; set +u` wrapper is the P9-F3 shape (the expansion aborts a
# `set -u` caller when the target has no value yet), fork-free and restored on
# return.
TSet._isIndexed() {
    local -
    set +u
    local -n __ts_probe="$1" 2>/dev/null || return 1
    [[ "${__ts_probe@a}" == *a* ]]
}

# ---- method bodies (P0: ctor/dtor/Count real; the rest arrive per phase) -----

THashSet.Create() {
    TSet._init
    return 0
}

THashSet.Destroy() {
    # FPC :2554: Free the internal dictionary -> its Clear fires removed events
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
    kk.debug "thashset: $1 arrives in $2"
    kk._return "__ths_pending__:$1"
    return 0
}

# ---- P1 members: membership core ---------------------------------------------

THashSet.Add() {
    # item -> rc 0 added / rc 1 already-present (SILENT — a Boolean answer, not
    # an error; FPC :2559 = `not ContainsKey; if new: dict.Add`). No event, no
    # mutation on a duplicate. Notify fires AFTER the write (added).
    local __ts_pk="k$1"
    declare -n __ts_it="${__inst__}_items"
    [[ -n ${__ts_it[$__ts_pk]+x} ]] && return 1
    __ts_it[$__ts_pk]=1
    TSet._notify "$1" added
    return 0
}

THashSet.Remove() {
    # item -> rc 0 removed / rc 1 absent (SILENT; FPC :2566 Boolean). Notify
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
    # item -> rc 0 present / rc 1 absent (FPC :2593 Boolean).
    local -n __ts_it="${__inst__}_items"
    [[ -n ${__ts_it["k$1"]+x} ]]
}

THashSet.Extract() {
    # item -> RESULT (FPC :2576). Hit: RESULT=item, remove, 'extracted' event.
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
    # FPC :2588 -> internal dict Clear = empty the storage FIRST, THEN notify
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
        kk.debug "Error: THashSet.ToArray: bad output array name '${1:-}'"
        kk._return ""
        return 2
    fi
    if TSet._isAssoc "$1"; then                # it would get 0,1,2… keys
        kk.debug "Error: THashSet.ToArray: '$1' is an associative array"
        kk._return ""
        return 2
    fi
    local -n __ts_out="$1" 2>/dev/null || { kk._return ""; return 2; }
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
        kk.debug "Error: THashSet.ForEach: callback '$__ts_cb' is not a function"
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
        kk.debug "Error: THashSet.Assign: '$1' is not a THashSet"
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

# ---- P2 members: the AddRange forms and the set algebra -----------------------
#
# All six drive the P1 Booleans through `$this.Add` / `$this.Remove` /
# `$this.Contains` rather than touching the storage themselves. That is what FPC
# does — TCustomSet's four procedures are written against the ABSTRACT Add and
# Remove (TCustomSet is declared :474-527 with `Add` abstract at :505), which
# THashSet supplies (:2559/:2566) — and it is what keeps the event stream
# identical to a hand-written loop of the same calls: one `added`/`removed` per
# element that really changed, through the same `_notify` gate, with no second
# copy of the storage idioms to keep in sync. It costs one member dispatch per
# element (measured: 40 ms per 1000 internal `$this.Add` against 27 ms for the
# same loop inlined, in a shell where 1000 `Add` calls made from OUTSIDE the
# object cost 217 ms), so the plan's relative gate — an algebra op over 1k
# elements within 3x a 1k `Add` loop — is met with room to spare (P2 gate
# numbers are in thashset_ledger.json).

THashSet.AddRange() {
    # i1 [i2 …] -> rc 0 iff EVERY item was newly added.
    #
    # FPC :2379 (release_3_2_2):
    #     Result := True;
    #     for i in AValues do
    #       Result := Add(i) and Result;
    # — an AND-fold in which Add runs for EVERY item (the `and` is on the right
    # of the assignment, so nothing is short-circuited away), and an empty
    # `array of T` leaves Result True. Hence: zero arguments -> rc 0; a value
    # already in the set -> rc 1 with the other items still added; a duplicate
    # WITHIN the argument list -> rc 1, because the second occurrence is no
    # longer "newly added" when the fold reaches it.
    #
    # rc 1 is a Boolean ANSWER, not an error: silent, never kk.debug'd (S2.2).
    local __ts_rc=0 __ts_i
    for __ts_i in "$@"; do
        $this.Add "$__ts_i" || __ts_rc=1
    done
    return $__ts_rc
}

THashSet.AddRangeFromArray() {
    # arrName -> the bash sibling of AddRange: the same AND-fold over the
    # elements of a caller INDEXED array. A sparse array contributes the
    # elements that exist (the holes are not elements); an empty array is the
    # empty `array of T` above, i.e. rc 0 and no change.
    #
    # The name is validated BEFORE the nameref is bound (kcl/README.md 1.7):
    # `local -n src="$1"` on a bad name prints a bash diagnostic and carries on
    # with rc 0, and on a reserved name it would alias this unit's own scratch.
    # A malformed or reserved name, an associative array, and a scalar or unset
    # variable are all a malformed CALL -> rc 2, nothing added.
    #
    # kk._outName was written for OUTPUT names, but every rule it applies —
    # identifier shape, the framework's reserved set, this unit's `__ts_` local
    # prefix, the instance's own `_data`/`_class`/`_items` — is exactly what
    # makes an INPUT name safe to bind here too, and it refuses nothing a
    # legitimate input array could be called. tinifile's TMemIniFile.SetStrings
    # (tinifile.sh:1263) already uses it for an input name for the same reason.
    if ! TSet._outName "${1:-}"; then
        kk.debug "Error: THashSet.AddRangeFromArray: bad input array name '${1:-}'"
        return 2
    fi
    if ! TSet._isIndexed "$1"; then
        kk.debug "Error: THashSet.AddRangeFromArray: '$1' is not an indexed array"
        return 2
    fi
    local -n __ts_src="$1"
    local __ts_rc=0 __ts_i
    for __ts_i in "${__ts_src[@]}"; do
        $this.Add "$__ts_i" || __ts_rc=1
    done
    return $__ts_rc
}

THashSet.UnionWith() {
    # other -> add every element of the OPERAND. FPC :2417:
    #     for i in AHashSet.Ptr^ do
    #       Add(i^);
    # Add skips the duplicates silently, so only genuinely-new elements fire
    # `added`, and `a.UnionWith a` is a no-op.
    #
    # The operand's keys are SNAPSHOT before self is touched (PLAN 6.2): bash
    # cannot iterate an associative array that is being modified, and in the
    # self-case the operand's storage IS self's.
    if ! TSet._isSet "${1:-}"; then
        kk.debug "Error: THashSet.UnionWith: '${1:-}' is not a THashSet"
        return 1
    fi
    local -n __ts_o="${1}_items"
    local -a __ts_ks=( "${!__ts_o[@]}" )
    local __ts_k
    for __ts_k in "${__ts_ks[@]}"; do
        $this.Add "${__ts_k#k}" || :
    done
    return 0
}

THashSet.IntersectWith() {
    # other -> keep only what the operand also holds. FPC :2425 is a TWO-PASS
    # walk through a scratch list:
    #     for i in Ptr^ do                       // SELF's elements
    #       if not AHashSet.Contains(i^) then
    #         LList.Add(i);
    #     for i in LList do
    #       Remove(i^);
    # Nothing is deleted while the storage is being iterated — which is also
    # what makes `a.IntersectWith a` a DEFINED no-op: pass 1 collects nothing.
    if ! TSet._isSet "${1:-}"; then
        kk.debug "Error: THashSet.IntersectWith: '${1:-}' is not a THashSet"
        return 1
    fi
    local -n __ts_o="${1}_items"
    local -n __ts_it="${__inst__}_items"
    local -a __ts_vic=()
    local __ts_k
    for __ts_k in "${!__ts_it[@]}"; do              # pass 1 — collect victims
        [[ -n ${__ts_o[$__ts_k]+x} ]] || __ts_vic+=( "$__ts_k" )
    done
    for __ts_k in "${__ts_vic[@]}"; do              # pass 2 — remove them
        $this.Remove "${__ts_k#k}" || :
    done
    return 0
}

THashSet.ExceptWith() {
    # other -> remove every element of the OPERAND. FPC :2442:
    #     for i in AHashSet.Ptr^ do
    #       Remove(i^);
    # Misses are silent (Remove's rc 1 is an answer). `a.ExceptWith a` is a full
    # drain: FPC walks the ARGUMENT's storage while removing from self, and in
    # the self-case that is the same storage — the snapshot below turns that
    # into a defined "remove all" instead of a hash walk over a shrinking table.
    if ! TSet._isSet "${1:-}"; then
        kk.debug "Error: THashSet.ExceptWith: '${1:-}' is not a THashSet"
        return 1
    fi
    local -n __ts_o="${1}_items"
    local -a __ts_ks=( "${!__ts_o[@]}" )
    local __ts_k
    for __ts_k in "${__ts_ks[@]}"; do
        $this.Remove "${__ts_k#k}" || :
    done
    return 0
}

THashSet.SymmetricExceptWith() {
    # other -> keep what is in exactly ONE of the two sets. FPC :2450, again
    # two-pass, and the walk is over the OPERAND:
    #     for i in AHashSet.Ptr^ do
    #       if Contains(i^) then
    #         LList.Add(i)
    #       else
    #         Add(i^);
    #     for i in LList do
    #       Remove(i^);
    # An element both sets hold is marked and removed at the end; an element
    # only the operand holds is added immediately. `a.SymmetricExceptWith a`
    # therefore marks everything and ends empty (S3).
    if ! TSet._isSet "${1:-}"; then
        kk.debug "Error: THashSet.SymmetricExceptWith: '${1:-}' is not a THashSet"
        return 1
    fi
    local -n __ts_o="${1}_items"
    local -a __ts_ks=( "${!__ts_o[@]}" )    # snapshot BEFORE self is mutated
    local -a __ts_vic=()
    local __ts_k
    for __ts_k in "${__ts_ks[@]}"; do               # pass 1 — mark or add
        if $this.Contains "${__ts_k#k}"; then
            __ts_vic+=( "$__ts_k" )
        else
            $this.Add "${__ts_k#k}" || :
        fi
    done
    for __ts_k in "${__ts_vic[@]}"; do              # pass 2 — remove the marked
        $this.Remove "${__ts_k#k}" || :
    done
    return 0
}

THashSet.Notify()              { TSet._pending Notify              P3; }

# Finalize.
build THashSet
