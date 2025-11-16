#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TLIST_DIR/../../kklass/kklass.sh"
source "$TLIST_DIR/../../kklass/kklib.sh"

# Define TList class
defineClass TList "" \
    property capacity _setCapacity \
    property count _setCount \
    constructor '{
         # Initialize properties
        capacity="0"
        count="0"
        # Initialize items array
        eval "${__inst__}_items=()"
    }' \
    method _setCapacity '{
         local new_capacity="$1"
         local items_var="${__inst__}_items"
         local current_count="$count"
         if (( new_capacity < current_count )); then
             # Truncate items to new capacity
             eval "${items_var}=(\"\${${items_var}[@]:0:$new_capacity}\")"
             count="$new_capacity"
        fi
        capacity="$new_capacity"
        # Resize the array if needed
        eval "local len=\${#${items_var}[@]}"
        while (( len < new_capacity )); do
            eval "${items_var}[$len]=\"\""
            ((len++))
        done
    }' \
    method _setCount '{
        local new_count="$1"
        local items_var="${__inst__}_items"
        local current_count="$count"
        local current_capacity="$capacity"
        if (( new_count < current_count )); then
            # Truncate items
            eval "${items_var}=(\"\${${items_var}[@]:0:$new_count}\")"
        elif (( new_count > current_count )); then
            # Pad with nil elements
            eval "local len=\${#${items_var}[@]}"
            while (( len < new_count )); do
                eval "${items_var}[$len]=\"\""
                ((len++))
            done
        fi
        eval "${__inst__}_data[count]=\"$new_count\""
        # Ensure capacity is at least count
        if (( current_capacity < new_count )); then
            eval "${__inst__}_data[capacity]=\"$new_count\""
        fi
    }' \
    method Grow '{
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
         
         capacity="$new_capacity"
         local items_var="${__inst__}_items"
         eval "local len=\${#${items_var}[@]}"
         while (( len < new_capacity )); do
             eval "${items_var}[$len]=\"\""
             ((len++))
         done
    }' \
    method Expand '{
        $this.Grow
    }' \
    function Add '{
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
        #$__inst__.property count = "$new_count"
        $__inst__.property count = "$new_count"
        RESULT="$new_count"
    }' \
    method Insert '{
        local index="$1"
        local item="$2"
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
    }' \
    method Delete '{
        local index="$1"
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
    }' \
    method Exchange '{
        local index1="$1"
        local index2="$2"
        if (( index1 < 0 || index1 >= count || index2 < 0 || index2 >= count )); then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        local temp="${items_ref[$index1]}"
        items_ref[$index1]="${items_ref[$index2]}"
        items_ref[$index2]="$temp"
    }' \
    method Move '{
        local from_index="$1"
        local to_index="$2"
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
    }' \
    method Clear '{
        $__inst__.property count = "0"
        $__inst__.property capacity = "0"
         local items_var="${__inst__}_items"
         eval "${items_var}=()"
     }' \
    method Pack '{
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        local packed_items=()
        local new_count=0
        local current_count=$count
        for (( i = 0; i < current_count; i++ )); do
            local item="${items_ref[$i]}"
            if [[ -n "$item" ]]; then
                packed_items[$new_count]="$item"
                ((new_count++))
            fi
        done
        items_ref=("${packed_items[@]}")
        $__inst__.property count = "$new_count"
        local current_capacity="$capacity"
        if (( current_capacity > new_count * 2 )); then
            $__inst__.property capacity = "$new_count"
        fi
    }' \
    function First '{
        local current_count="$count"
        if (( current_count == 0 )); then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: List is empty" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        RESULT="${items_ref[0]}"
        #echo "$RESULT"
    }' \
    function Last '{
         local current_count="$count"
         if (( current_count == 0 )); then
             [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: List is empty" >&2
             return 1
         fi
         local items_var="${__inst__}_items"
         declare -n items_ref="$items_var"
         RESULT="${items_ref[$((current_count-1))]}"
         #echo "$RESULT"
     }' \
    method Get '{
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Get method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method Put '{
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Put method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    function IndexOf '{
        local item="$1"
        local items_var="${__inst__}_items"
        local current_count="$count"
        # OPTIMIZATION: Use nameref instead of eval in loop (significant perf gain)
        declare -n items_ref="$items_var"
        for (( i = 0; i < current_count; i++ )); do
            if [[ "${items_ref[$i]}" == "$item" ]]; then
                RESULT="$i"
                return 0
            fi
        done
        RESULT="-1"
    }' \
    function Remove '{
        local item="$1"
        $this.IndexOf "$item"
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
    }' \
    method Sort '{
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Sort method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method CustomSort '{
        local compare_func="$1"
        # Implementation would need to be provided - for now just error
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: CustomSort not implemented" >&2
        return 1
    }' \
    method Find '{
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Find method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method Assign '{
        local source="$1"
        $this.Clear
        # Basic assignment - would need to be overridden in subclasses
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Assign method not implemented in TList - use in subclasses" >&2
        return 1
    }'
