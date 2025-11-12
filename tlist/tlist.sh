#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TLIST_DIR/../../kklass/kklass.sh"
source "$TLIST_DIR/../../kklass/kklib.sh"

# Define TList class
defineClass TList "" \
    property capacity \
    property item_count \
    constructor '{
        # Initialize properties
        capacity="0"
        item_count="0"
        # Initialize items array
        eval "${__inst__}_items=()"
    }' \
    method Capacity '{
        kk.write "$capacity"
    }' \
    method SetCapacity '{
        local new_capacity="$1"
        local items_var="${__inst__}_items"
        local current_count="$item_count"
        if (( new_capacity < current_count )); then
            # Truncate items to new capacity
            eval "${items_var}=(\"\${${items_var}[@]:0:$new_capacity}\")"
            eval "${__inst__}_data[item_count]=\"$new_capacity\""
        fi
        eval "${__inst__}_data[capacity]=\"$new_capacity\""
        # Resize the array if needed
        eval "local len=\${#${items_var}[@]}"
        while (( len < new_capacity )); do
            eval "${items_var}[$len]=\"\""
            ((len++))
        done
    }' \
    method Count '{
        kk.write "$item_count"
    }' \
    method SetCount '{
        local new_count="$1"
        local items_var="${__inst__}_items"
        local current_count="$item_count"
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
        eval "${__inst__}_data[item_count]=\"$new_count\""
        # Ensure capacity is at least count
        if (( current_capacity < new_count )); then
            eval "${__inst__}_data[capacity]=\"$new_count\""
        fi
    }' \
    method Grow '{
        local current_capacity="$capacity"
        local new_capacity
        if (( current_capacity < 4 )); then
            new_capacity=4
        elif (( current_capacity < 8 )); then
            new_capacity=8
        else
            new_capacity=$((current_capacity + 16))
        fi
        $this.SetCapacity "$new_capacity"
    }' \
    method Expand '{
        $this.Grow
    }' \
    method Add '{
        local item="$1"
        local current_count="$item_count"
        # Grow capacity if needed
        if (( current_count >= capacity )); then
            $__inst__.call Grow
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        items_ref[$current_count]="$item"
        local new_count=$((current_count + 1))
        $__inst__.property item_count = "$new_count"
        echo "$current_count"
    }' \
    method AddUsingExistingAdd '{
        $__inst__.call Add "$1" >/dev/null
        # Refresh local property mirrors from instance data without eval
        #local -n __data_ref="${__inst__}_data"
        #item_count="${__data_ref[item_count]}"
        #capacity="${__data_ref[capacity]}"
        }' \
    method Insert '{
        local index="$1"
        local item="$2"
        local current_count=$item_count
        if (( index < 0 || index > current_count )); then
            echo "Error: Index out of bounds" >&2
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
        $__inst__.property item_count = "$new_count"
    }' \
    method Delete '{
        local index="$1"
        local current_count=$item_count
        if (( index < 0 || index >= current_count )); then
            echo "Error: Index out of bounds" >&2
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
        $__inst__.property item_count = "$new_count"
    }' \
    method Exchange '{
        local index1="$1"
        local index2="$2"
        if (( index1 < 0 || index1 >= item_count || index2 < 0 || index2 >= item_count )); then
            echo "Error: Index out of bounds" >&2
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
        if (( from_index < 0 || from_index >= item_count || to_index < 0 || to_index >= item_count )); then
            echo "Error: Index out of bounds" >&2
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
        $__inst__.property item_count = "0"
        $__inst__.property capacity = "0"
         local items_var="${__inst__}_items"
         eval "${items_var}=()"
     }' \
    method Pack '{
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        local packed_items=()
        local new_count=0
        local current_count=$item_count
        for (( i = 0; i < current_count; i++ )); do
            local item="${items_ref[$i]}"
            if [[ -n "$item" ]]; then
                packed_items[$new_count]="$item"
                ((new_count++))
            fi
        done
        items_ref=("${packed_items[@]}")
        $__inst__.property item_count = "$new_count"
        local current_capacity="$capacity"
        if (( current_capacity > new_count * 2 )); then
            $__inst__.property capacity = "$new_count"
        fi
    }' \
    method First '{
        local current_count="$item_count"
        if (( current_count == 0 )); then
            echo "Error: List is empty" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        echo "${items_ref[0]}"
    }' \
    method Last '{
        local current_count="$item_count"
        if (( current_count == 0 )); then
            echo "Error: List is empty" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        echo "${items_ref[$((current_count-1))]}"
    }' \
    method Get '{
        echo "Error: Get method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method Put '{
        echo "Error: Put method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method IndexOf '{
        local item="$1"
        local items_var="${__inst__}_items"
        local current_count="$item_count"
        # OPTIMIZATION: Use nameref instead of eval in loop (significant perf gain)
        declare -n items_ref="$items_var"
        for (( i = 0; i < current_count; i++ )); do
            if [[ "${items_ref[$i]}" == "$item" ]]; then
                echo "$i"
                return 0
            fi
        done
        echo "-1"
    }' \
    method Remove '{
        local item="$1"
        local index=$($this.IndexOf "$item")
        if [[ "$index" != "-1" ]]; then
            $this.Delete "$index"
            echo "$index"
        else
            echo "-1"
        fi
    }' \
    method Sort '{
        echo "Error: Sort method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method CustomSort '{
        local compare_func="$1"
        # Implementation would need to be provided - for now just error
        echo "Error: CustomSort not implemented" >&2
        return 1
    }' \
    method Find '{
        echo "Error: Find method not implemented in TList - use in subclasses" >&2
        return 1
    }' \
    method Assign '{
        local source="$1"
        $this.Clear
        # Basic assignment - would need to be overridden in subclasses
        echo "Error: Assign method not implemented in TList - use in subclasses" >&2
        return 1
    }'
