#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
tstringhelper_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$tstringhelper_DIR/../../kklass/kklass.sh"

# Define the string class with methods from TStringHelper
defineClass "string" "" \
    "static_method" "compare" '
        local strA="$1"
        local strB="$2"
        local options="${3:-}"
        local locale="${4:-}"

        # Simple implementation: use bash string comparison
        if [[ "$strA" < "$strB" ]]; then
            echo -1
        elif [[ "$strA" > "$strB" ]]; then
            echo 1
        else
            echo 0
        fi
    ' \
    "static_method" "compareOrdinal" '
        local strA="$1"
        local strB="$2"

        # Ordinal comparison
        if [[ "$strA" < "$strB" ]]; then
            echo -1
        elif [[ "$strA" > "$strB" ]]; then
            echo 1
        else
            echo 0
        fi
    ' \
    "static_method" "compareText" '
        local strA="$1"
        local strB="$2"

        # Case insensitive
        local a_lower="${strA,,}"
        local b_lower="${strB,,}"
        if [[ "$a_lower" < "$b_lower" ]]; then
            echo -1
        elif [[ "$a_lower" > "$b_lower" ]]; then
            echo 1
        else
            echo 0
        fi
    ' \
    "method" "compareTo" '
        local self="$1"
        local strB="$2"

        string.compare "$self" "$strB"
    ' \
    "method" "contains" '
        local self="$1"
        local value="$2"

        if [[ "$self" == *"$value"* ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "static_method" "copy" '
        local str="$1"
        echo "$str"
    ' \
    "method" "copyTo" '
        echo "Not implemented"
    ' \
    "method" "countChar" '
        local self="$1"
        local char="$2"
        local count=0
        local i
        for ((i=0; i<${#self}; i++)); do
            if [[ "${self:i:1}" == "$char" ]]; then
                ((count++))
            fi
        done
        echo "$count"
    ' \
    "static_method" "create" '
        # Simplified, assume char and count
        local char="$1"
        local count="$2"
        local result=""
        for ((i=0; i<count; i++)); do
            result+="$char"
        done
        echo "$result"
    ' \
    "method" "deQuotedString" '
        local self="$1"
        # Simple remove quotes
        echo "${self//\"/}"
    ' \
    "static_method" "endsText" '
        local subText="$1"
        local text="$2"
        local sub_lower="${subText,,}"
        local text_lower="${text,,}"
        if [[ "$text_lower" == *"$sub_lower" ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "static_method" "startsWith" '
        local self="$1"
        local value="$2"
        if [[ "$self" == "$value"* ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "method" "substring" '
        local self="$1"
        local startIndex="$2"
        local length="$3"
        if [[ -z "$length" ]]; then
            echo "${self:startIndex}"
        else
            echo "${self:startIndex:length}"
        fi
    ' \
    "static_method" "toBoolean" '
        local s="$1"
        if [[ "$s" == "true" || "$s" == "1" ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "method" "toBoolean" '
        local self="$1"
        string.toBoolean "$self"
    ' \
    "method" "toCharArray" '
        local self="$1"
        # Simple, echo each char
        for ((i=0; i<${#self}; i++)); do
            echo "${self:i:1}"
        done
    ' \
    "static_method" "toDouble" '
    local s="$1"
    echo "$s" | awk ''{print $1 + 0.0}''
    ' \
    "method" "toDouble" '
        local self="$1"
        string.toDouble "$self"
    ' \
    "static_method" "toInt64" '
    local s="$1"
    echo "$s" | awk ''{print int($1)}''
    ' \
    "method" "toInt64" '
        local self="$1"
        string.toInt64 "$self"
    ' \
    "static_method" "toInteger" '
    local s="$1"
    echo "$s" | awk ''{print int($1)}''
    ' \
    "method" "toInteger" '
        local self="$1"
        string.toInteger "$self"
    ' \
    "method" "toLower" '
        local self="$1"
        echo "${self,,}"
    ' \
    "method" "toLowerInvariant" '
        local self="$1"
        echo "${self,,}"
    ' \
    "static_method" "toSingle" '
        local s="$1"
        echo "$s" | awk "{print \$1 + 0.0}"
    ' \
    "method" "toSingle" '
        local self="$1"
        string.toSingle "$self"
    ' \
    "method" "toUpper" '
        local self="$1"
        echo "${self^^}"
    ' \
    "method" "toUpperInvariant" '
        local self="$1"
        echo "${self^^}"
    ' \
    "method" "trim" '
        local self="$1"
        # Trim spaces
        echo "${self#"${self%%[![:space:]]*}"}"
    ' \
    "method" "trimLeft" '
        local self="$1"
        echo "${self#"${self%%[![:space:]]*}"}"
    ' \
    "method" "trimRight" '
        local self="$1"
        echo "${self%"${self##*[![:space:]]}"}"
    ' \
    "static_method" "upperCase" '
        local s="$1"
        echo "${s^^}"
    ' \
    "property" "length" '
        local self="$1"
        echo "${#self}"
    ' \
    "property" "chars" '
        local self="$1"
        local index="$2"
        if [[ $index -ge 0 && $index -lt ${#self} ]]; then
            echo "${self:index:1}"
        else
            echo "undefined"
        fi
    '
