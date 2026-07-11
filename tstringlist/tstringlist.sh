#!/bin/bash

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TSTRINGLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TSTRINGLIST_DIR/../../kklass/kklass_pascal.sh"
source "$TSTRINGLIST_DIR/../tlist/tlist.sh"

# ---------------------------------------------------------------------------
# TStringList: a string list with sorting, duplicate policies and
# case-(in)sensitive comparison (Free Pascal's Classes.TStringList).
# Inherits TList — `class TStringList : TList`.
#
# Pascal DSL form: the class STRUCTURE (interface) first, then the method
# BODIES as real bash functions, then `build TStringList`.
#
# - `override` marks every method that replaces a TList implementation
#   (build errors if the ancestor doesn't actually define it — typo guard).
# - The constructor chains to the parent with `inherited` (rewritten to
#   `parent.constructor "$@"`), then sets the TStringList-specific fields.
# - Insert delegates to the parent for unsorted lists via `inherited Insert`.
# - CompareStrings returns 0 (equal) / 1 (str1 < str2) / 2 (str1 > str2) via
#   RESULT; duplicates policy is one of dupAccept | dupIgnore | dupError.
# ---------------------------------------------------------------------------
class TStringList : TList
    public
        constructor Create
        var case_sensitive
        var sorted
        var duplicates
        override func  Get
        override func  IndexOf
        override proc  Sort
        override func  Find
        override proc  Assign
        proc           AddStrings
        override proc  Put
        override func  Remove
        override func  Add
        override proc  Insert
        func           CompareStrings
end

# ---- method bodies (real bash functions; extracted by `build`) --------------

TStringList.Create() {
    # Call parent constructor
    inherited

    # Initialize TStringList-specific properties
    case_sensitive=false
    sorted=false
    duplicates="dupAccept"
}

TStringList.Get() {
    local index="$1"
    local current_count="$count"
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    RESULT="${items_ref[$index]}"
}

TStringList.IndexOf() {
    local item="$1"
    local items_var="${__inst__}_items"
    local current_count="$count"
    declare -n items_ref="$items_var"
    for (( i = 0; i < current_count; i++ )); do
        local current_item="${items_ref[$i]}"
        $this.CompareStrings "$current_item" "$item" >/dev/null
        if (( RESULT == 0 )); then
            RESULT="$i"
            break
        fi
    done
    if (( i >= current_count )); then
        RESULT="-1"
    fi
}

TStringList.Sort() {
    local items_var="${this}_items"
    declare -n items_ref="$items_var"
    # Optimized bubble sort with early exit
    local swapped
    for (( i = 0; i < count; i++ )); do
        swapped=0
        for (( j = 0; j < count - i - 1; j++ )); do
            local item1="${items_ref[$j]}"
            local item2="${items_ref[$((j+1))]}"
            $this.CompareStrings "$item1" "$item2" >/dev/null
            if (( RESULT == 2 )); then  # item1 > item2, swap
                items_ref[$j]="$item2"
                items_ref[$((j+1))]="$item1"
                swapped=1
            fi
        done
        (( swapped == 0 )) && break  # Early exit if already sorted
    done
    sorted=true
}

TStringList.Find() {
    local item="$1"
    if [[ "$sorted" != "true" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: List must be sorted for Find operation" >&2
        return 1
    fi
    # Binary search
    local left=0
    local right=$((count - 1))
    while (( left <= right )); do
        local mid=$(( (left + right) / 2 ))
        local mid_item
        $this.Get "$mid" >/dev/null
        mid_item=$RESULT
        $this.CompareStrings "$mid_item" "$item" >/dev/null
        local cmp_result="$RESULT"
        if (( cmp_result == 0 )); then
            RESULT="$mid"
            break
        elif (( cmp_result == 1 )); then  # mid_item < item, search right
            left=$((mid + 1))
        else  # mid_item > item, search left
            right=$((mid - 1))
        fi
    done
    # Return insertion point (negative)
    if (( left > right )); then
        RESULT=$(( -left - 1 ))
    fi
}

TStringList.Assign() {
    local source="$1"
    local source_count=$($source.count)

    local source_items_var="${source}_items"
    local items_var="${__inst__}_items"
    declare -n source_items_ref="$source_items_var"
    local assign_temp=()
    local idx
    for (( idx = 0; idx < source_count; idx++ )); do
        assign_temp[$idx]="${source_items_ref[$idx]}"
    done

    $this.Clear

    declare -n items_ref="$items_var"
    for (( idx = 0; idx < source_count; idx++ )); do
        items_ref[$idx]="${assign_temp[$idx]}"
    done

    # Set destination count
    $this.property count = "$source_count"
}

TStringList.AddStrings() {
    local source="$1"
    if [[ -z "$source" ]]; then
        return 0
    fi
    local source_count=$($source.count)
    if (( source_count == 0 )); then
        return 0
    fi

    local source_items_var="${source}_items"
    local items_var="${__inst__}_items"
    declare -n source_items_ref="$source_items_var"
    declare -n items_ref="$items_var"

    if [[ "$sorted" != "true" && "$duplicates" == "dupAccept" ]]; then
        local current_count="$count"
        local new_count=$((current_count + source_count))
        if (( new_count > capacity )); then
            $__inst__.property capacity = "$new_count" >/dev/null
        fi

        local copied_items=()
        local idx
        for (( idx = 0; idx < source_count; idx++ )); do
            copied_items[$idx]="${source_items_ref[$idx]}"
        done
        for (( idx = 0; idx < source_count; idx++ )); do
            items_ref[$((current_count + idx))]="${copied_items[$idx]}"
        done

        $__inst__.property count = "$new_count" >/dev/null
        return 0
    fi

    # Add each item through Add when sorting or duplicate policy must be enforced
    local idx
    for (( idx = 0; idx < source_count; idx++ )); do
        local item_to_add
        item_to_add="${source_items_ref[$idx]}"
        $this.Add "$item_to_add" >/dev/null
    done
}

TStringList.Put() {
    local index="$1"
    local item="$2"
    local current_count="$count"
    if (( index < 0 || index >= current_count )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
        return 1
    fi
    local items_var="${this}_items"
    declare -n items_ref="$items_var"
    items_ref[$index]="$item"
}

TStringList.Remove() {
    local item="$1"
    local index
    $this.IndexOf "$item" >/dev/null
    index=$RESULT
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

TStringList.Add() {
    local item="$1"
    local current_count="$count"

    # Check for duplicates
    local dup_index
    $__inst__.call IndexOf "$item" >/dev/null
    dup_index=$RESULT

    if [[ "$dup_index" != "-1" ]]; then
        # Found duplicate
        if [[ "$duplicates" == "dupIgnore" ]]; then
            RESULT="$dup_index"
            return
        elif [[ "$duplicates" == "dupError" ]]; then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Duplicate item not allowed" >&2
            return 1
        fi
        # else dupAccept - allow duplicates
    fi

    # Grow capacity if needed
    if (( current_count >= capacity )); then
        $__inst__.call Grow
    fi

    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    local insert_index=$current_count

    # If sorted, find correct insertion position using binary search
    if [[ "$sorted" == "true" ]]; then
        local left=0
        local right=$current_count
        while (( left < right )); do
            local mid=$(( (left + right) / 2 ))
            local mid_item="${items_ref[$mid]}"
            $__inst__.call CompareStrings "$mid_item" "$item" >/dev/null
            if (( RESULT == 2 )); then  # mid_item > item, search left
                right=$mid
            else  # mid_item <= item, search right
                left=$((mid + 1))
            fi
        done
        insert_index=$left
        # Shift elements to the right to make room
        for (( j = current_count; j > insert_index; j-- )); do
            items_ref[$j]="${items_ref[$((j-1))]}"
        done
    fi

    items_ref[$insert_index]="$item"
    local new_count=$((current_count + 1))
    $__inst__.property count = "$new_count"
    RESULT="$insert_index"
}

TStringList.Insert() {
    local index="$1"
    local item="$2"
    if [[ "$sorted" == "true" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Cannot insert into sorted list" >&2
        return 1
    fi
    # Call parent Insert for unsorted lists
    inherited Insert "$index" "$item"
}

TStringList.CompareStrings() {
    local str1="$1"
    local str2="$2"
    local cmp_str1 cmp_str2
    if [[ "$case_sensitive" == "true" ]]; then
        cmp_str1="$str1"
        cmp_str2="$str2"
    else
        cmp_str1="${str1,,}"
        cmp_str2="${str2,,}"
    fi
    if [[ "$cmp_str1" < "$cmp_str2" ]]; then
        RESULT=1 # str1 < str2
    elif [[ "$cmp_str1" > "$cmp_str2" ]]; then
        RESULT=2 # str1 > str2
    else
        RESULT=0 # equal
    fi
}

# Finalize: extract the bodies above into the TStringList class (the override
# guard verifies each `override` against TList) and finalize the runtime.
build TStringList
