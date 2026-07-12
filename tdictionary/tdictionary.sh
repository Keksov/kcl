#!/bin/bash

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TDICTIONARY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TDICTIONARY_DIR/../../kklass/kklass_pascal.sh"
source "$TDICTIONARY_DIR/../../kkore/klib.sh"
source "$TDICTIONARY_DIR/../../kkore/kerr.sh"

# ---------------------------------------------------------------------------
# TDictionary: a string->string hash dictionary, an INSTANTIABLE class.
# Port of FPC Generics.Collections TDictionary<TKey,TValue>
# (= TOpenAddressingLP, generics.dictionariesh.inc:668).
#
# SCOPE (see PLAN.md): a THIN WRAPPER around a native bash associative array,
# keeping the FPC API surface and its exact observable DATA semantics. Not
# ported: the FPC hashing machinery (open addressing, probe sequences,
# tombstones, cuckoo maps, hash factories, equality comparers) AND its memory
# knobs (Capacity/SetCapacity/TrimExcess/LoadFactor/MaxLoadFactor) — bash
# `declare -A` is already a hash table and manages its own storage; keys
# compare as exact byte strings. The constructor's ACapacity argument is
# accepted for FPC signature compatibility and ignored.
#
# STORAGE: pairs live in a per-instance assoc array `${instance}_items`; every
# key is stored under a one-char prefix (items["k$key"]) because bash rejects
# the empty subscript (a['']=x -> "bad array subscript") while the empty
# string IS a valid FPC key. Iteration strips the prefix with ${k#k}.
# NOTE: `${instance}_data` is kklass's OWN per-instance property store — never
# touch it.
#
# Pinned safe idioms for ARBITRARY keys (validated by tests/002_StorageIdioms):
#   exists:  [[ -n ${ref["k$key"]+x} ]]     one parameter expansion, never
#                                           re-parsed, safe on 5.2 and 5.3
#   delete:  pk="k$key"; unset 'ref[$pk]'   single-quoted: unset expands the
#            subscript exactly once; the prefix guarantees pk is never
#            empty / '@' / '*', so no shopt (assoc_expand_once) is needed
#
# count is COMPUTED from ${#items[@]} (one entry per pair by construction),
# so it can never drift from the storage.
#
# `func` methods echo the result AND set RESULT (direct call + $RESULT is the
# lossless path for values with trailing newlines); FPC exceptions map to
# `return 1` with a message only under VERBOSE_KKLASS=debug (tlist style).
# ---------------------------------------------------------------------------
class TDictionary
    public
        constructor Create
        destructor  Destroy
        property count read GetCount
        func GetCount
        proc Add
        proc TryAdd
        proc AddOrSetValue
        func GetItem
        proc SetItem
        func TryGetValue
        proc ContainsKey
        proc Remove
        proc Clear
        func ExtractPair
        proc ContainsValue
        func GetValueDef
        proc Assign
        proc AddPairs
        proc Keys
        proc Values
        proc KeysToArray
        proc ValuesToArray
        proc ToArrays
        proc ForEach
        property onKeyNotify   read onKeyNotify   write onKeyNotify
        property onValueNotify read onValueNotify write onValueNotify
        var  _notifyHook
        proc KeyNotify
        proc ValueNotify
end

# ---- method bodies (real bash functions; extracted by `build`) --------------

TDictionary.Create() {
    # FPC Create(ACapacity) pre-sizes the hash table; bash assoc arrays size
    # themselves, so any argument is accepted and ignored (capacity family is
    # not ported — thin-wrapper decision, see PLAN.md).
    onKeyNotify=""
    onValueNotify=""
    _notifyHook=""
    local dv="${__inst__}_items"
    declare -gA "$dv"
    declare -n items_ref="$dv"
    items_ref=()
}

TDictionary.Destroy() {
    # FPC Destroy calls Clear first (notifications fire once P5 wires them),
    # then tears the storage down.
    $this.Clear
    unset -v "${__inst__}_items"
}

TDictionary.GetCount() {
    local dv="${__inst__}_items"
    declare -n items_ref="$dv"
    RESULT=${#items_ref[@]}
}

TDictionary.Add() {
    # FPC (impl:399 InternalDoAdd): adding an existing key raises EListError
    # SDuplicatesNotAllowed — mapped to rc=1, dictionary NOT mutated (and no
    # notification: the raise precedes any notify). Insert notifies AFTER the
    # write (AddItem, impl:420), key first (PairNotify order, impl:43).
    local key="$1" value="$2"
    declare -n items_ref="${__inst__}_items"
    if [[ -n ${items_ref["k$key"]+x} ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.Add: duplicates not allowed" >&2
        return 1
    fi
    items_ref["k$key"]=$value
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
        $this.KeyNotify "$key" added
        $this.ValueNotify "$value" added
    fi
    return 0
}

TDictionary.TryAdd() {
    # FPC (impl:718): adds only if the key is absent; boolean result -> exit
    # status. The duplicate case is a negative ANSWER, not an error: silent.
    local key="$1" value="$2"
    declare -n items_ref="${__inst__}_items"
    [[ -n ${items_ref["k$key"]+x} ]] && return 1
    items_ref["k$key"]=$value
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
        $this.KeyNotify "$key" added
        $this.ValueNotify "$value" added
    fi
    return 0
}

TDictionary.AddOrSetValue() {
    # FPC (impl:729): upsert. Insert -> pair added; overwrite -> SetValue
    # semantics (impl:54): the NEW value is stored FIRST, then
    # ValueNotify(old, removed) + ValueNotify(new, added); the key is silent.
    local key="$1" value="$2" pk had="" oldv=""
    declare -n items_ref="${__inst__}_items"
    pk="k$key"
    if [[ -n ${items_ref[$pk]+x} ]]; then
        had=1
        oldv="${items_ref[$pk]}"
    fi
    items_ref[$pk]=$value
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
        if [[ -n $had ]]; then
            $this.ValueNotify "$oldv" removed
            $this.ValueNotify "$value" added
        else
            $this.KeyNotify "$key" added
            $this.ValueNotify "$value" added
        fi
    fi
    return 0
}

TDictionary.GetItem() {
    # Items[key] read. FPC (impl:640): missing key raises EListError
    # SDictionaryKeyDoesNotExist -> rc=1, RESULT=''.
    local key="$1"
    declare -n items_ref="${__inst__}_items"
    if [[ -z ${items_ref["k$key"]+x} ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.GetItem: key does not exist" >&2
        # kk._return (not a bare RESULT=) so the '' reaches the caller on this
        # early-return path — the auto-appended func trailer only runs at the
        # end of the body, and _invoke restores the caller's RESULT otherwise.
        kk._return ""
        return 1
    fi
    RESULT="${items_ref["k$key"]}"
}

TDictionary.SetItem() {
    # Items[key] write. FPC (impl:662) is UPDATE-ONLY: missing key raises
    # EListError SItemNotFound (unlike Delphi, where dict[k]:=v upserts).
    local key="$1" value="$2" oldv
    declare -n items_ref="${__inst__}_items"
    if [[ -z ${items_ref["k$key"]+x} ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.SetItem: key does not exist (FPC Items[] write is update-only)" >&2
        return 1
    fi
    # SetValue (impl:54): assign FIRST, then old-removed + new-added; key silent.
    oldv="${items_ref["k$key"]}"
    items_ref["k$key"]=$value
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
        $this.ValueNotify "$oldv" removed
        $this.ValueNotify "$value" added
    fi
    return 0
}

TDictionary.TryGetValue() {
    # FPC (impl:705): miss -> AValue := Default(TValue) ('') and False.
    local key="$1"
    declare -n items_ref="${__inst__}_items"
    if [[ -z ${items_ref["k$key"]+x} ]]; then
        kk._return "" # FPC assigns Default(TValue) to the out param on miss
        return 1
    fi
    RESULT="${items_ref["k$key"]}"
}

TDictionary.ContainsKey() {
    # FPC (impl:742); boolean -> exit status.
    local key="$1"
    declare -n items_ref="${__inst__}_items"
    [[ -n ${items_ref["k$key"]+x} ]]
}

TDictionary.Remove() {
    # FPC (impl:492): removing an absent key is a SILENT no-op (rc=0).
    # Hit: notify AFTER the pair is gone (DoRemove, impl:477).
    local key="$1" pk oldv
    declare -n items_ref="${__inst__}_items"
    pk="k$key"
    [[ -n ${items_ref[$pk]+x} ]] || return 0
    oldv="${items_ref[$pk]}"
    unset 'items_ref[$pk]'
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
        $this.KeyNotify "$key" removed
        $this.ValueNotify "$oldv" removed
    fi
    return 0
}

TDictionary.Clear() {
    # FPC (impl:515): the storage is emptied FIRST (FItems := nil), THEN every
    # old pair is notified 'removed' — callbacks observe an already-empty dict.
    local dv="${__inst__}_items"
    declare -gA "$dv"
    declare -n items_ref="$dv"
    if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]] && (( ${#items_ref[@]} > 0 )); then
        local -a __td_ks=("${!items_ref[@]}")
        local -A __td_old=()
        local __td_k
        for __td_k in "${__td_ks[@]}"; do
            __td_old[$__td_k]="${items_ref[$__td_k]}"
        done
        items_ref=()
        for __td_k in "${__td_ks[@]}"; do
            $this.KeyNotify "${__td_k#k}" removed
            $this.ValueNotify "${__td_old[$__td_k]}" removed
        done
    else
        items_ref=()
    fi
    return 0
}

TDictionary.ExtractPair() {
    # FPC (impl:503): hit -> Result = (AKey, value), pair removed (cnExtracted
    # once P5 wires notifications); miss -> Default(TPair) = ('','') with rc=0
    # — NOT an error. NB: FPC's miss shape is indistinguishable from extracting
    # the ''-keyed pair (Default(TKey) = ''); same ambiguity here, resolve with
    # ContainsKey beforehand. RESULT_KEY only reaches the caller on a DIRECT
    # call ($() gets just the value via echo).
    local key="$1" pk evalue
    declare -n items_ref="${__inst__}_items"
    pk="k$key"
    if [[ -z ${items_ref[$pk]+x} ]]; then
        RESULT_KEY=""
        RESULT=""
    else
        evalue="${items_ref[$pk]}"
        unset 'items_ref[$pk]'
        # notify AFTER removal (DoRemove with cnExtracted, impl:477/:512)
        if [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]]; then
            $this.KeyNotify "$key" extracted
            $this.ValueNotify "$evalue" extracted
        fi
        RESULT_KEY="$key"
        RESULT="$evalue"
    fi
}

TDictionary.ContainsValue() {
    # FPC (impl:750): linear scan with the default equality comparer — here,
    # exact bash string comparison. Boolean -> exit status.
    local value="$1" v
    declare -n items_ref="${__inst__}_items"
    for v in "${items_ref[@]}"; do
        [[ "$v" == "$value" ]] && return 0
    done
    return 1
}

TDictionary.GetValueDef() {
    # bash convenience (NOT in FPC TDictionary): TryGetValue sugar — the
    # stored value when the key exists (even ''), else the supplied default.
    local key="$1" default="${2:-}"
    declare -n items_ref="${__inst__}_items"
    if [[ -n ${items_ref["k$key"]+x} ]]; then
        RESULT="${items_ref["k$key"]}"
    else
        RESULT="$default"
    fi
}

TDictionary.Assign() {
    # Create(ACollection) analog (impl:106-114: Create + Add each pair):
    # replace this dictionary's content with a copy of another TDictionary's
    # pairs. Self-assign is a no-op; a non-dictionary source -> rc=1, this
    # dictionary untouched.
    local src="$1" k
    if [[ "$src" == "$__inst__" ]]; then
        return 0
    fi
    local srcvar="${src}_items"
    declare -n src_ref="$srcvar" 2>/dev/null || return 1
    if [[ ${src_ref@a} != *A* ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.Assign: '$src' is not a TDictionary instance" >&2
        return 1
    fi
    # Clear notifies the removals; each copied pair then notifies 'added'
    # (Create(ACollection) = Create + Add each, impl:106-114).
    $this.Clear
    declare -n items_ref="${__inst__}_items"
    local notify=""
    [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]] && notify=1
    for k in "${!src_ref[@]}"; do
        items_ref[$k]="${src_ref[$k]}"
        if [[ -n $notify ]]; then
            $this.KeyNotify "${k#k}" added
            $this.ValueNotify "${src_ref[$k]}" added
        fi
    done
    return 0
}

TDictionary.AddPairs() {
    # Bulk Add: k v [k v ...]. Mirrors FPC Create(ACollection)'s sequential
    # Add loop, where a raise ABORTS mid-way: a duplicate stops at that pair
    # (earlier pairs stay, later ones are not attempted). An odd argument
    # count is rejected up front — nothing added.
    if (( $# % 2 != 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.AddPairs: odd argument count" >&2
        return 1
    fi
    declare -n items_ref="${__inst__}_items"
    local key value notify=""
    [[ -n "$onKeyNotify" || -n "$onValueNotify" || -n "$_notifyHook" ]] && notify=1
    while (( $# )); do
        key="$1" value="$2"
        shift 2
        if [[ -n ${items_ref["k$key"]+x} ]]; then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.AddPairs: duplicate key" >&2
            return 1
        fi
        items_ref["k$key"]=$value
        if [[ -n $notify ]]; then
            $this.KeyNotify "$key" added
            $this.ValueNotify "$value" added
        fi
    done
    return 0
}

# ---- iteration (P3) ---------------------------------------------------------
# Order is UNSPECIFIED (bash's internal hash order) — same contract as FPC,
# where enumeration follows bucket order and changes on rehash.
# The echo forms (Keys/Values) are line-oriented and therefore ambiguous for
# keys/values containing newlines; the nameref fills (KeysToArray/
# ValuesToArray/ToArrays) and ForEach are the LOSSLESS paths.
# Internal locals in the nameref methods use the __td_ prefix so a caller's
# output-variable name cannot collide with them (do not pass __td_* names).

TDictionary.Keys() {
    # KeyCollection analog: one key per line.
    declare -n __td_items="${__inst__}_items"
    local __td_k
    for __td_k in "${!__td_items[@]}"; do
        printf '%s\n' "${__td_k#k}"
    done
}

TDictionary.Values() {
    # ValueCollection analog: one value per line.
    declare -n __td_items="${__inst__}_items"
    local __td_v
    for __td_v in "${__td_items[@]}"; do
        printf '%s\n' "$__td_v"
    done
}

TDictionary.KeysToArray() {
    # Keys.ToArray analog: fill the named indexed array with the keys, exact.
    local __td_out="$1"
    if [[ -z "$__td_out" ]] || ! declare -n __td_oref="$__td_out" 2>/dev/null; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.KeysToArray: bad output variable name '$__td_out'" >&2
        return 1
    fi
    declare -n __td_items="${__inst__}_items"
    __td_oref=()
    local __td_k
    for __td_k in "${!__td_items[@]}"; do
        __td_oref+=("${__td_k#k}")
    done
}

TDictionary.ValuesToArray() {
    # Values.ToArray analog: fill the named indexed array with the values.
    local __td_out="$1"
    if [[ -z "$__td_out" ]] || ! declare -n __td_oref="$__td_out" 2>/dev/null; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.ValuesToArray: bad output variable name '$__td_out'" >&2
        return 1
    fi
    declare -n __td_items="${__inst__}_items"
    __td_oref=()
    local __td_v
    for __td_v in "${__td_items[@]}"; do
        __td_oref+=("$__td_v")
    done
}

TDictionary.ToArrays() {
    # ToArray (array of TPair) analog: fill TWO named indexed arrays,
    # index-aligned — keys[i] maps to values[i].
    local __td_kout="$1" __td_vout="$2"
    if [[ -z "$__td_kout" || -z "$__td_vout" || "$__td_kout" == "$__td_vout" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.ToArrays: two DISTINCT output variable names required" >&2
        return 1
    fi
    if ! declare -n __td_kref="$__td_kout" 2>/dev/null || ! declare -n __td_vref="$__td_vout" 2>/dev/null; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.ToArrays: bad output variable name" >&2
        return 1
    fi
    declare -n __td_items="${__inst__}_items"
    __td_kref=()
    __td_vref=()
    local __td_k
    for __td_k in "${!__td_items[@]}"; do
        __td_kref+=("${__td_k#k}")
        __td_vref+=("${__td_items[$__td_k]}")
    done
}

# ---- notifications (P5) -----------------------------------------------------
# Callback contract: cb <dict> <item> <added|removed|extracted>. An empty hook
# is off; mutation methods guard with one [[ -n ]] before dispatching, so a
# dictionary without hooks pays (almost) nothing. _notifyHook is set by
# subclasses that OVERRIDE KeyNotify/ValueNotify (TObjectDictionary, P6) so
# the virtual dispatch happens even with no user callbacks attached.

TDictionary.KeyNotify() {
    # key action — fires the user event if assigned (FPC impl:47-52).
    if [[ -n "$onKeyNotify" ]]; then
        if declare -F "$onKeyNotify" >/dev/null 2>&1; then
            "$onKeyNotify" "$__inst__" "$1" "$2"
        else
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.KeyNotify: '$onKeyNotify' is not a function" >&2
        fi
    fi
    return 0
}

TDictionary.ValueNotify() {
    # value action — fires the user event if assigned (FPC impl:65-70).
    if [[ -n "$onValueNotify" ]]; then
        if declare -F "$onValueNotify" >/dev/null 2>&1; then
            "$onValueNotify" "$__inst__" "$1" "$2"
        else
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.ValueNotify: '$onValueNotify' is not a function" >&2
        fi
    fi
    return 0
}

TDictionary.ForEach() {
    # Pair-enumerator analog: invoke `callback key value` once per pair.
    # Iterates a SNAPSHOT of the keys, so the callback may freely Remove/Add:
    # pairs deleted mid-iteration are skipped (existence re-checked), pairs
    # added mid-iteration are NOT visited in this pass. (FPC enumeration over
    # a mutating dictionary is undefined; this is defined-safe.) The
    # callback's exit status is ignored; ForEach returns 0.
    local __td_cb="$1"
    if ! declare -F "$__td_cb" >/dev/null 2>&1; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TDictionary.ForEach: '$__td_cb' is not a function" >&2
        return 1
    fi
    declare -n __td_items="${__inst__}_items"
    local -a __td_snapshot=("${!__td_items[@]}")
    local __td_k
    for __td_k in "${__td_snapshot[@]}"; do
        [[ -n ${__td_items[$__td_k]+x} ]] || continue
        "$__td_cb" "${__td_k#k}" "${__td_items[$__td_k]}"
    done
    return 0
}

# Finalize: extract the bodies above into the TDictionary class.
build TDictionary

# ============================================================================
# TObjectDictionary: a TDictionary that OWNS its keys and/or values.
# Port of FPC TObjectDictionary (= TObjectOpenAddressingLP,
# generics.dictionariesh.inc:669; overrides at generics.dictionaries.inc:
# 2389-2405): after `inherited`, an owned item is FREED when the notification
# action is 'removed' — and ONLY then. Consequences (all FPC-pinned):
#   Remove/Clear/Destroy        -> owned items freed
#   AddOrSetValue/SetItem over an existing key
#                               -> the REPLACED value freed (doOwnsValues)
#   ExtractPair                 -> 'extracted', NOT freed (ownership handed back)
#   failed duplicate Add        -> nothing freed (the raise precedes notify)
#
# "Freeing" a bash item: owned keys/values must be kklass INSTANCE NAMES;
# freeing calls `$item.delete`. Items that do not name a live instance are
# skipped silently (checked via the instance's `.delete` dispatcher), so
# plain-string values under doOwnsValues are harmless.
#
# Constructor: TObjectDictionary.new od "doOwnsKeys doOwnsValues" [ACapacity]
# — ownership tokens space- or comma-separated ('' = none); unknown tokens
# reject the whole ownership set (rc=1, none applied); ACapacity is accepted
# and ignored (API v2, same as TDictionary). Setting any ownership arms the
# inherited _notifyHook so the virtual KeyNotify/ValueNotify dispatch happens
# even with no user callbacks attached.
# ============================================================================
class TObjectDictionary : TDictionary
    public
        constructor Create
        var _ownsKeys
        var _ownsValues
        override proc KeyNotify
        override proc ValueNotify
end

# ---- plain helper -----------------------------------------------------------

# Free one owned item: call `$1.delete` iff $1 names a live kklass instance
# (its `.delete` dispatcher function exists). Anything else is skipped.
TObjectDictionary._free() {
    if declare -F "$1.delete" >/dev/null 2>&1; then
        "$1.delete"
    fi
    return 0
}

# ---- method bodies -----------------------------------------------------------

TObjectDictionary.Create() {
    # FPC: Create(AOwnerships[, ACapacity]) -> inherited Create + FOwnerships.
    inherited
    _ownsKeys=""
    _ownsValues=""
    local -a toks=()
    local tok ok="" ov=""
    if [[ -n "${1:-}" ]]; then
        read -ra toks <<< "${1//,/ }"
    fi
    for tok in "${toks[@]}"; do
        case "$tok" in
            doOwnsKeys)   ok=1 ;;
            doOwnsValues) ov=1 ;;
            *)
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TObjectDictionary.Create: unknown ownership token '$tok'" >&2
                return 1
                ;;
        esac
    done
    _ownsKeys="$ok"
    _ownsValues="$ov"
    if [[ -n "$ok" || -n "$ov" ]]; then
        _notifyHook=1
    fi
}

TObjectDictionary.KeyNotify() {
    # key action (FPC impl:2389): inherited FIRST (user event), then free the
    # key on 'removed' — never on 'extracted'.
    inherited KeyNotify "$1" "$2"
    if [[ -n "$_ownsKeys" && "$2" == "removed" ]]; then
        TObjectDictionary._free "$1"
    fi
    return 0
}

TObjectDictionary.ValueNotify() {
    # value action (FPC impl:2398): inherited FIRST, then free on 'removed'.
    inherited ValueNotify "$1" "$2"
    if [[ -n "$_ownsValues" && "$2" == "removed" ]]; then
        TObjectDictionary._free "$1"
    fi
    return 0
}

# Finalize the subclass.
build TObjectDictionary
