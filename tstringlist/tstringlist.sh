#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TSTRINGLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TSTRINGLIST_DIR/../../kklass/kklass.sh"
source "$TSTRINGLIST_DIR/../tlist/tlist.sh"

# Define TStringList class inheriting from TList
defineClass TStringList TList \
    property case_sensitive \
    property sorted \
    property duplicates \
    constructor '{
          # Call parent constructor
          parent.constructor "$@"
          
          # Initialize TStringList-specific properties
          case_sensitive=false
          sorted=false
          duplicates="dupAccept"
      }' \
    function Get '{
        local index="$1"
        local current_count="$count"
        if (( index < 0 || index >= current_count )); then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Index out of bounds" >&2
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        RESULT="${items_ref[$index]}"
        echo "$RESULT"
    }' \
    function IndexOf '{
        local item="$1"
        local items_var="${__inst__}_items"
        local current_count="$count"
        declare -n items_ref="$items_var"
        for (( i = 0; i < current_count; i++ )); do
            local current_item="${items_ref[$i]}"
            $this.CompareStrings "$current_item" "$item"
            if (( RESULT == 0 )); then
                RESULT="$i"
                echo "$RESULT"
                return 0
            fi
        done
        RESULT="-1"
        echo "$RESULT"
    }' \
    method Sort '{
        local items_var="${this}_items"
        declare -n items_ref="$items_var"
        # Optimized bubble sort with early exit
        local swapped
        for (( i = 0; i < count; i++ )); do
            swapped=0
            for (( j = 0; j < count - i - 1; j++ )); do
                local item1="${items_ref[$j]}"
                local item2="${items_ref[$((j+1))]}"
                $this.CompareStrings "$item1" "$item2"
                if (( RESULT == 2 )); then  # item1 > item2, swap
                    items_ref[$j]="$item2"
                    items_ref[$((j+1))]="$item1"
                    swapped=1
                fi
            done
            (( swapped == 0 )) && break  # Early exit if already sorted
        done
        sorted=true
    }' \
    function Find '{
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
            mid_item=$($this.Get "$mid")
            $this.CompareStrings "$mid_item" "$item"
            local cmp_result="$RESULT"
            if (( cmp_result == 0 )); then
                RESULT="$mid"
                return 0
            elif (( cmp_result == 1 )); then  # mid_item < item, search right
                left=$((mid + 1))
            else  # mid_item > item, search left
                right=$((mid - 1))
            fi
        done
        # Return insertion point (negative)
        RESULT=$(( -left - 1 ))
    }' \
    procedure Assign '{
        local source="$1"
        $this.Clear
        # Get source count by accessing the _count variable 
        # Use typeset to list all vars matching the pattern and extract count
        local i=0
        while true; do
            local source_items_var="${source}_items"
            local current_item_var="${source_items_var}[$i]"
            # We cannot use indirect expansion in procedure context
            # So we will use a workaround - iterate until we hit an empty slot
            # by trying to access via eval in command substitution
            local item
            item=$(echo "${!current_item_var}" 2>/dev/null || echo "")
            if [[ -z "$item" ]]; then
                break
            fi
            $this.Add "$item"
            ((i++))
        done
        }' \
        procedure AddStrings '{
         local source="$1"
         if [[ -z "$source" ]]; then
             return 0
         fi
         local add_i=0
         while true; do
            local add_source_items_var="${source}_items"
            declare -n add_items_ref="$add_source_items_var" 2>/dev/null || break
            if [[ -z "${add_items_ref[$add_i]}" ]]; then
                break
            fi
            local add_item="${add_items_ref[$add_i]}"
            $this.Add "$add_item"
            ((add_i++))
         done
        }' \
    method Put '{
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
     }' \
     function Remove '{
         local item="$1"
         local index
         index=$($this.IndexOf "$item")
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
     function Add '{
         local item="$1"
         local current_count="$count"
         
         # Check for duplicates if dupIgnore is set
         if [[ "$duplicates" == "dupIgnore" ]]; then
             local dup_index
             dup_index=$($__inst__.call IndexOf "$item")
             if [[ "$dup_index" != "-1" ]]; then
                 RESULT="$dup_index"
                 return 0
             fi
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
                 $__inst__.call CompareStrings "$mid_item" "$item"
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
         }' \
     method Insert '{
         local index="$1"
         local item="$2"
         if [[ "$sorted" == "true" ]]; then
             [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: Cannot insert into sorted list" >&2
             return 1
         fi
         # Call parent Insert for unsorted lists
         $__inst__.call Insert "$index" "$item"
     }' \
     procedure CompareStrings '{
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
     }'