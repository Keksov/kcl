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
            if (( $? == 0 )); then
                RESULT="$i"
                return 0
            fi
        done
        RESULT="-1"
    }' \
    method Sort '{
        local items_var="${this}_items"
        declare -n items_ref="$items_var"
        # Simple bubble sort for now
        for (( i = 0; i < count; i++ )); do
            for (( j = 0; j < count - i - 1; j++ )); do
                local item1="${items_ref[$j]}"
                local item2="${items_ref[$((j+1))]}"
                $this.CompareStrings "$item1" "$item2"
                local cmp_result=$?
                if (( cmp_result == 2 )); then  # item1 > item2, swap
                    items_ref[$j]="$item2"
                    items_ref[$((j+1))]="$item1"
                fi
            done
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
            local cmp_result=$?
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
        # Handle both TList and TStringList sources
        local source_items_var="${source}_items"
        declare -n source_items_ref="$source_items_var"
        local source_count
        source_count=$($source.Count)
        for (( i = 0; i < source_count; i++ )); do
            local item="${source_items_ref[$i]}"
            $this.Add "$item"
        done
    }' \
    procedure AddStrings '{
        local source="$1"
        # Add all strings from source list
        local source_items_var="${source}_items"
        declare -n source_items_ref="$source_items_var"
        local source_count
        source_count=$($source.Count)
        for (( i = 0; i < source_count; i++ )); do
            local item="${source_items_ref[$i]}"
            $this.Add "$item"
        done
    }' \
    procedure Put '{
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
     function CompareStrings '{
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
         return $RESULT
     }'