#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TLIST_SOURCED:-}" ]]; then
    return
fi
declare -g _TLIST_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TLIST_DIR/../../kklass/kklass_pascal.sh"
# TArray.sort/binarySearch — the delegation target for CustomSort here and for
# TStringList.Sort (composition, exactly as FPC generics TList<T>.Sort delegates
# to TArrayHelper.Sort(FItems, cmp, 0, Count)). Re-source-guarded + fork-free.
source "$TLIST_DIR/../tarray/tarray.sh"

# ---------------------------------------------------------------------------
# TList: a dynamic list (Free Pascal's Classes.TList), an INSTANTIABLE class.
#
# Pascal DSL form: the class STRUCTURE (interface) first, then the method
# BODIES as real bash functions, then `build TList`.
#
# The items live in a per-instance bash array `${instance}_items`, accessed in
# the bodies through `declare -n items_ref="${__inst__}_items"`.
#
# capacity/count are properties with a STORED read and a COMPUTED setter:
#   `property capacity read capacity write _setCapacity`
# reads return the stored value directly; external writes
# (`lst.capacity = N`) go through the _setCapacity/_setCount methods, which
# truncate/pad the items array. Bodies write the raw stored value with
# `$__inst__.property capacity = ...` to BYPASS the computed setter (verbatim
# from the original implementation).
#
# `func` methods return via RESULT; `proc` methods return nothing (or only an
# exit status). Get/Put/Sort/Find/CustomSort/Assign are subclass stubs.
# ---------------------------------------------------------------------------
class TList
    public
        constructor Create
        destructor  Destroy
        property capacity read capacity write _setCapacity
        property count    read count    write _setCount
        proc _setCapacity
        proc _setCount
        proc Grow
        proc Expand
        func Add
        proc Insert
        proc Delete
        proc Exchange
        proc Move
        proc Clear
        proc Pack
        func First
        func Last
        func Get
        proc Put
        func IndexOf
        func Remove
        proc Sort
        proc CustomSort
        proc Find
        proc Assign
        proc BatchInsert
        proc BatchDelete
end

# ---- method bodies (real bash functions; extracted by `build`) --------------

TList.Create() {
    # Initialize properties
    capacity="0"
    count="0"
    # Initialize items array
    declare -n items_ref="${__inst__}_items"
    items_ref=()
}

TList.Destroy() {
    # LIFECYCLE (kcl/README.md section 1.9, finding G1-01): kklass's `.delete`
    # frees `<inst>_data`, `<inst>_class` and the wrappers — an extra
    # per-instance array the unit creates is the unit's own responsibility.
    # Without this, every deleted list left a global `<inst>_items` behind with
    # its full contents, and a new instance reusing the name started out
    # pre-populated. Inherited by TStringList; TObjectList frees the owned
    # elements first and then chains here with `inherited`.
    unset "${__inst__}_items"
}

TList._setCapacity() {
    local new_capacity="$1"
    kk.isInt "$new_capacity" new_capacity || return 1
    # FPC Classes.TList.SetCapacity raises EListError (SListCapacityError) for
    # a capacity below Count or below zero — it never silently drops elements.
    # Here (decision R2, finding G1-09) that is rc 1 with the list UNCHANGED:
    # the old code truncated to `new_capacity` (losing data) and, for a
    # negative value, left count = capacity = -3 with the storage wiped by
    # bash's own "bad array subscript" error.
    if (( new_capacity < 0 || new_capacity < count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TList.capacity: $new_capacity is below count ($count) or negative" >&2
        return 1
    fi
    capacity="$new_capacity"
    # No physical pre-fill: capacity is a logical reservation; the sparse
    # bash array grows on demand as elements are actually added.
}

TList._setCount() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local new_count="$1"
    kk.isInt "$new_count" new_count || return 1
    local items_var="${__inst__}_items"
    local current_count="$count"
    local current_capacity="$capacity"
    declare -n items_ref="$items_var"
    if (( new_count < current_count )); then
        # Truncate items using unset instead of array copy
        for (( i = new_count; i < current_count; i++ )); do
            unset "items_ref[$i]"
        done
    elif (( new_count > current_count )); then
        # Ensure capacity is sufficient
        if (( new_count > current_capacity )); then
            $__inst__.property capacity = "$new_count"
        fi
        # Pad with nil elements
        local len=${#items_ref[@]}
        while (( len < new_count )); do
            items_ref[$len]=""
            (( len += 1 )) || :
        done
    fi
    count="$new_count"
    # Note: Capacity should be managed separately, not automatically adjusted here
    # This was causing infinite loops in capacity growth
}

TList.Grow() {
    local current_capacity="$capacity"
    local new_capacity

    # OPTIMIZATION: Adaptive capacity growth strategy
    # Small arrays: fixed growth (better for small lists)
    # Medium arrays: 2x multiplier (exponential growth)
    # Large arrays: 1.5x multiplier (better memory efficiency)
    if (( current_capacity < 4 )); then
        new_capacity=4
    elif (( current_capacity < 16 )); then
        # Medium arrays: 2x multiplier
        new_capacity=$((current_capacity * 2))
    else
        # Large arrays: 1.5x multiplier (better memory efficiency)
        # Using integer arithmetic: capacity + capacity/2
        new_capacity=$((current_capacity + current_capacity / 2))
    fi

    # Capacity is a logical reservation tracked by the property; bash arrays
    # are sparse and grow on demand, so there is no need to physically
    # pre-fill new_capacity empty slots (that was O(capacity) writes per Grow).
    $__inst__.property capacity = "$new_capacity"
}

TList.Expand() {
    $this.Grow
}

TList.Add() {
    local item="$1"
    local current_count="$count"
    # Grow capacity if needed
    if (( current_count >= capacity )); then
        $__inst__.call Grow
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    items_ref[$current_count]="$item"
    local new_count=$((current_count + 1))
    $__inst__.property count = "$new_count" >/dev/null
    # FPC `TList.Add: Integer` returns the INDEX of the new element, which is
    # the count BEFORE the insertion (decision R1, finding G1-06). docs/TList.md
    # and TStringList.Add already said index; only this body said count.
    RESULT="$current_count"
}

TList.Insert() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local index="$1"
    kk.isInt "$index" index || return 1
    local item="${2:-}"
    local current_count=$count
    if (( index < 0 || index > current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        RESULT=""
        return 1
    fi
    if (( current_count >= capacity )); then
        $this.Grow
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    # Shift elements right from index
    for (( i = current_count; i > index; i-- )); do
        items_ref[$i]="${items_ref[$((i-1))]}"
    done
    items_ref[$index]="$item"
    local new_count=$((current_count + 1))
    $__inst__.property count = "$new_count"
}

TList.Delete() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local index="$1"
    kk.isInt "$index" index || return 1
    local current_count=$count
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    # Shift elements left from index+1
    for (( i = index; i < current_count - 1; i++ )); do
        items_ref[$i]="${items_ref[$((i+1))]}"
    done
    # Clear the last element
    unset "items_ref[$((current_count-1))]"
    local new_count=$((current_count - 1))
    $__inst__.property count = "$new_count"
}

TList.Exchange() {
    local index1="$1"
    local index2="${2:-}"
    kk.isInt "$index1" index1 || return 1
    kk.isInt "$index2" index2 || return 1
    if (( index1 < 0 || index1 >= count || index2 < 0 || index2 >= count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    local temp="${items_ref[$index1]}"
    items_ref[$index1]="${items_ref[$index2]}"
    items_ref[$index2]="$temp"
}

TList.Move() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local from_index="$1"
    local to_index="${2:-}"
    kk.isInt "$from_index" from_index || return 1
    kk.isInt "$to_index" to_index || return 1
    if (( from_index < 0 || from_index >= count || to_index < 0 || to_index >= count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    if (( from_index == to_index )); then
        return 0
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    local item="${items_ref[$from_index]}"
    # OPTIMIZATION: Direct shifting instead of cascading Delete+Insert operations
    # Reduces 2 O(n) passes to 1 O(n) pass
    if (( from_index < to_index )); then
        for (( i = from_index; i < to_index; i++ )); do
            items_ref[$i]="${items_ref[$((i+1))]}"
        done
    else
        for (( i = from_index; i > to_index; i-- )); do
            items_ref[$i]="${items_ref[$((i-1))]}"
        done
    fi
    items_ref[$to_index]="$item"
}

TList.Clear() {
    $__inst__.property count = "0"
    $__inst__.property capacity = "0"
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    items_ref=()
}

TList.Pack() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    local new_count=0
    local current_count=$count
    local write_index=0

    # In-place filtering: move non-empty items to beginning
    for (( i = 0; i < current_count; i++ )); do
        local item="${items_ref[$i]}"
        if [[ -n "$item" ]]; then
            items_ref[$write_index]="$item"
            (( write_index += 1 )) || :
        fi
    done

    new_count=$write_index

    # Clear removed indices
    for (( i = new_count; i < current_count; i++ )); do
        unset "items_ref[$i]"
    done

    $__inst__.property count = "$new_count"
    local current_capacity="$capacity"
    if (( current_capacity > new_count * 2 )); then
        $__inst__.property capacity = "$new_count"
    fi
}

TList.First() {
    local current_count="$count"
    if (( current_count == 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: List is empty" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    RESULT="${items_ref[0]}"
}

TList.Last() {
    local current_count="$count"
    if (( current_count == 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: List is empty" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    RESULT="${items_ref[$((current_count-1))]}"
}

TList.Get() {
    # Real indexed read (bash TList holds strings, so unlike FPC's pointer TList
    # this is meaningful here). Bounds are [0,count); out of range -> rc 1,
    # RESULT untouched. Same pattern as the already-real First/Last.
    local index="$1" current_count="$count"
    kk.isInt "$index" index || return 1
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    RESULT="${items_ref[$index]}"
}

TList.Put() {
    # Real indexed write; bounds [0,count); out of range -> rc 1, no change.
    local index="$1" item="$2" current_count="$count"
    kk.isInt "$index" index || return 1
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    items_ref[$index]="$item"
}

TList.IndexOf() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local item="$1"
    local items_var="${__inst__}_items"
    local current_count="$count"
    # OPTIMIZATION: Use nameref instead of eval in loop (significant perf gain)
    declare -n items_ref="$items_var"
    RESULT="-1"
    for (( i = 0; i < current_count; i++ )); do
        if [[ "${items_ref[$i]}" == "$item" ]]; then
            RESULT="$i"
            break
        fi
    done
}

TList.Remove() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local item="$1"
    $this.IndexOf "$item" >/dev/null
    local index="$RESULT"
    if [[ "$index" != "-1" ]]; then
        local current_count=$count
        if (( index < 0 || index >= current_count )); then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        # Shift elements left from index+1
        for (( i = index; i < current_count - 1; i++ )); do
            items_ref[$i]="${items_ref[$((i+1))]}"
        done
        # Clear the last element
        unset "items_ref[$((current_count-1))]"
        local new_count=$((current_count - 1))
        $__inst__.property count = "$new_count"
        RESULT="$index"
    else
        RESULT="-1"
    fi
}

TList.Sort() {
    # Bash convenience (NOT in FPC Classes.TList — that sorts pointers and always
    # needs a comparator): a raw TList holds STRINGS, so the parameterless Sort
    # does a default BYTE-order sort of [0,count) via TArray.sort, symmetric with
    # TArray.sort's own no-argument default. For another order use CustomSort;
    # TStringList overrides this with its case-fold Sort.
    TArray.sort "${__inst__}_items" 0 "$count"
}

TList.CustomSort() {
    # FPC Classes.TList.Sort(Compare: TListSortCompare) equivalent — sort the
    # [0,count) range in place with a caller-supplied comparator, delegated to
    # TArray.sort (stable bottom-up mergesort, fork-free). The comparator uses
    # the TArray cmpFn protocol: `cmp a b` -> rc 0 (a<b) / 1 (a==b) / 2 (a>b).
    local compare_func="$1"
    [[ -z "$compare_func" ]] && return 1
    TArray.sort "${__inst__}_items" "$compare_func" 0 "$count"
}

TList.Find() {
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Find method not implemented in TList - use in subclasses" >&2
    return 1
}

TList.Assign() {
    # Subclass stub. It FAILS BEFORE touching this list (finding G1-07c): the
    # old body called the virtual `$this.Clear` first, so on a TObjectList it
    # freed every owned element and only then reported "not implemented" —
    # rc 1 with the caller's data destroyed. An unimplemented operation must
    # leave the instance exactly as it was (kcl/README.md section 1.2).
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Assign method not implemented in TList - use in subclasses" >&2
    return 1
}

TList.BatchInsert() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local index="$1"
    kk.isInt "$index" index || return 1
    shift
    local items=("$@")
    local items_to_add=${#items[@]}
    local current_count=$count

    # Validate index
    if (( index < 0 || index > current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        RESULT="$current_count"
        return 1
    fi

    # No items to add - return current count
    if (( items_to_add == 0 )); then
        RESULT="$current_count"
        return 0
    fi

    # Ensure sufficient capacity - simplified approach
    local required_capacity=$((current_count + items_to_add))
    local current_capacity=$capacity
    if (( required_capacity > current_capacity )); then
        # Calculate how many times we need to grow
        while (( current_capacity < required_capacity )); do
            local new_capacity
            if (( current_capacity < 4 )); then
                new_capacity=4
            elif (( current_capacity < 16 )); then
                new_capacity=$((current_capacity * 2))
            else
                new_capacity=$((current_capacity + current_capacity / 2))
            fi
            current_capacity=$new_capacity
        done
        # Set capacity directly
        $__inst__.property capacity = "$current_capacity"
    fi

    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"

    # Shift existing elements right
    for (( i = current_count + items_to_add - 1; i >= index + items_to_add; i-- )); do
        items_ref[$i]="${items_ref[$((i - items_to_add))]}"
    done

    # Insert new items
    for (( i = 0; i < items_to_add; i++ )); do
        items_ref[$((index + i))]="${items[$i]}"
    done

    local new_count=$((current_count + items_to_add))
    $__inst__.property count = "$new_count"
    RESULT="$new_count"
}

TList.BatchDelete() {
    local i                     # X-LOCALS (G1-08): loop counter, never the caller's
    local index="$1"
    local count_to_delete="${2:-}"
    kk.isInt "$index" index || return 1
    kk.isInt "$count_to_delete" count_to_delete || return 1
    local current_count=$count

    # Validate index
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        RESULT="$current_count"
        return 1
    fi

    # Clamp count_to_delete to available items
    if (( index + count_to_delete > current_count )); then
        count_to_delete=$((current_count - index))
    fi

    # No items to delete - return current count
    if (( count_to_delete <= 0 )); then
        RESULT="$current_count"
        return 0
    fi

    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"

    # Shift elements left
    for (( i = index; i < current_count - count_to_delete; i++ )); do
        items_ref[$i]="${items_ref[$((i + count_to_delete))]}"
    done

    # Clear removed elements
    for (( i = current_count - count_to_delete; i < current_count; i++ )); do
        unset "items_ref[$i]"
    done

    local new_count=$((current_count - count_to_delete))
    $__inst__.property count = "$new_count"
    RESULT="$new_count"
}

# Finalize: extract the bodies above into the TList class. The class keeps the
# exact runtime shape the old defineClass call produced (same method kinds,
# same property accessors), so subclasses — TStringList in particular —
# inherit from it unchanged.
build TList
