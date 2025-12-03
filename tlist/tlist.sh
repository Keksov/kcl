#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TLIST_DIR/../../kklass/kklass.sh"
source "$TLIST_DIR/../../kkore/klib.sh"

# Define TList class
defineClass TList "" \
    property capacity _setCapacity \
    property count _setCount \
    constructor '{
         # Initialize properties
        capacity="0"
        count="0"
        # Initialize items array
        declare -n items_ref="${__inst__}_items"
        items_ref=()
    }' \
    method _setCapacity '{
         local new_capacity="$1"
         local items_var="${__inst__}_items"
         local current_count="$count"
         declare -n items_ref="$items_var"
         if (( new_capacity < current_count )); then
             # Truncate items to new capacity using unset instead of array copy
             for (( i = new_capacity; i < current_count; i++ )); do
                 unset "items_ref[$i]"
             done
             count="$new_capacity"
         fi
         capacity="$new_capacity"
         # Resize the array if needed
         local len=${#items_ref[@]}
         while (( len < new_capacity )); do
             items_ref[$len]=""
             ((len++))
         done
     }' \
    method _setCount '{
         local new_count="$1"
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
                 ((len++))
             done
         fi
         count="$new_count"
         # Note: Capacity should be managed separately, not automatically adjusted here
         # This was causing infinite loops in capacity growth
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
         
         $__inst__.property capacity = "$new_capacity"
         local items_var="${__inst__}_items"
         declare -n items_ref="$items_var"
         local len=${#items_ref[@]}
         while (( len < new_capacity )); do
             items_ref[$len]=""
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
        $__inst__.property count = "$new_count" >/dev/null
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
          declare -n items_ref="$items_var"
          items_ref=()
      }' \
    method Pack '{
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
                ((write_index++))
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
    }' \
    method BatchInsert '{
        local index="$1"
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
    }' \
    method BatchDelete '{
        local index="$1"
        local count_to_delete="$2"
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
    }'
