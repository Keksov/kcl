#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
tstringhelper_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$tstringhelper_DIR/../../kklass/kklass.sh"

# Define the string class with methods from TStringHelper
defineClass "string" ""

string.equals() {
    local str1="$1"
    local str2="$2"
    if [[ "$str1" == "$str2" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.trimStart() {
    local str="$1"
    local trimChars="$2"
    local result="$str"
    while [[ ${#result} -gt 0 ]] && [[ "$trimChars" == *"${result:0:1}"* ]]; do
        result="${result:1}"
    done
    echo "$result"
}

string.trimEnd() {
    local str="$1"
    local trimChars="$2"
    local result="$str"
    while [[ ${#result} -gt 0 ]] && [[ "$trimChars" == *"${result: -1}"* ]]; do
        result="${result:0:${#result}-1}"
    done
    echo "$result"
}

string.startsText() {
    local subText="$1"
    local text="$2"
    local sub_lower="${subText,,}"
    local text_lower="${text,,}"
    if [[ "$text_lower" == "$sub_lower"* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.split() {
    local str="$1"
    local sep="$2"
    local count="$3"
    if [[ -z "$sep" ]]; then
        echo "$str"
        return
    fi
    local IFS="$sep"
    local -a parts
    read -ra parts <<< "$str"
    if [[ -n "$count" ]] && (( ${#parts[@]} > count )); then
        parts=("${parts[@]:0:count}")
    fi
    echo "${parts[*]}"
}

string.replace() {
    local str="$1"
    local old="$2"
    local new="$3"
    local flags="$4"
    if [[ "$flags" == *"rfReplaceAll"* ]]; then
        if [[ "$flags" == *"rfIgnoreCase"* ]]; then
            echo "$str" | sed "s/$old/$new/gi"
        else
            echo "${str//$old/$new}"
        fi
    else
        if [[ "$flags" == *"rfIgnoreCase"* ]]; then
            echo "$str" | sed "s/$old/$new/i"
        else
            echo "${str/$old/$new}"
        fi
    fi
}

string.remove() {
    local str="$1"
    local start="$2"
    local count="$3"
    if [[ -z "$count" ]]; then
        echo "${str:0:$start}"
    else
        echo "${str:0:$start}${str:$start+$count}"
    fi
}

string.quotedString() {
    local str="$1"
    local quote="$2"
    if [[ -z "$quote" ]]; then
        quote="'"
        # Double internal single quotes
        local escaped=$(echo "$str" | sed "s/'/''/g")
        echo "$quote$escaped$quote"
    else
        echo "$quote$str$quote"
    fi
}

string.parse() {
    echo "$1"
}

string.padLeft() {
    local str="$1"
    local width="$2"
    local padChar="$3"
    if [[ -z "$padChar" ]]; then
        padChar=" "
    fi
    local len=${#str}
    if [[ $len -ge $width ]]; then
        echo "$str"
    else
        local padLen=$((width - len))
        local padding=""
        for ((i=0; i<padLen; i++)); do
            padding+="$padChar"
        done
        echo "$padding$str"
    fi
}

string.padRight() {
    local str="$1"
    local width="$2"
    local padChar="$3"
    if [[ -z "$padChar" ]]; then
        padChar=" "
    fi
    local len=${#str}
    if [[ $len -ge $width ]]; then
        echo "$str"
    else
        local padLen=$((width - len))
        local padding=""
        for ((i=0; i<padLen; i++)); do
            padding+="$padChar"
        done
        echo "$str$padding"
    fi
}

string.join() {
    local sep="$1"
    shift
    local result=""
    local first=true
    for arg in "$@"; do
        if [[ "$first" == true ]]; then
            result="$arg"
            first=false
        else
            result="$result$sep$arg"
        fi
    done
    echo "$result"
}

string.isNullOrWhiteSpace() {
    local str="$1"
    if [[ -z "$str" ]]; then
        echo "true"
    elif [[ "$str" =~ ^[[:space:]]*$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.isNullOrEmpty() {
    local str="$1"
    if [[ -z "$str" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.isEmpty() {
    string.isNullOrEmpty "$1"
}

string.isDelimiter() {
    local str="$1"
    local index="$2"
    local delims="$3"
    if [[ $index -lt 0 || $index -ge ${#str} ]]; then
        echo "false"
    else
        local char="${str:$index:1}"
        if [[ "$delims" == *"$char"* ]]; then
            echo "true"
        else
            echo "false"
        fi
    fi
}

string.insert() {
    local str="$1"
    local index="$2"
    local value="$3"
    if [[ $index -le 0 ]]; then
        echo "$value$str"
    elif [[ $index -ge ${#str} ]]; then
        echo "$str$value"
    else
        echo "${str:0:$index}$value${str:$index}"
    fi
}

string.indexOfAnyUnquoted() {
    local str="$1"
    local anyOf="$2"
    local quoteStart="$3"
    local quoteEnd="$4"
    local startIndex="${5:-0}"
    local count="$6"
    local len=${#str}
    local inQuote=false
    local quoteChar=""
    local i=$startIndex
    if [[ -n "$count" ]]; then
        len=$((startIndex + count))
        if [[ $len -gt ${#str} ]]; then len=${#str}; fi
    fi
    while [[ $i -lt $len ]]; do
        local char="${str:i:1}"
        if [[ "$inQuote" == false ]]; then
            if [[ "$char" == "$quoteStart" ]]; then
                inQuote=true
                quoteChar="$quoteStart"
            elif [[ "$anyOf" == *"$char"* ]]; then
                echo "$i"
                return
            fi
        else
            if [[ "$char" == "$quoteEnd" ]]; then
                inQuote=false
            fi
        fi
        ((i++))
    done
    echo "-1"
}

string.indexOfAny() {
    local str="$1"
    local anyOf="$2"
    local startIndex="${3:-0}"
    local count="$4"
    local len=${#str}
    local i=$startIndex
    if [[ -n "$count" ]]; then
        len=$((startIndex + count))
        if [[ $len -gt ${#str} ]]; then len=${#str}; fi
    fi
    while [[ $i -lt $len ]]; do
        local char="${str:i:1}"
        if [[ "$anyOf" == *"$char"* ]]; then
            echo "$i"
            return
        fi
        ((i++))
    done
    echo "-1"
}

string.indexOf() {
    local str="$1"
    local value="$2"
    local startIndex="${3:-0}"
    local count="$4"
    local len=${#str}
    local val_len=${#value}
    if [[ $val_len -eq 0 ]]; then
        echo "$startIndex"
        return
    fi
    local i=$startIndex
    if [[ -n "$count" ]]; then
        len=$((startIndex + count))
        if [[ $len -gt ${#str} ]]; then len=${#str}; fi
    fi
    while [[ $((i + val_len)) -le $len ]]; do
        if [[ "${str:i:val_len}" == "$value" ]]; then
            echo "$i"
            return
        fi
        ((i++))
    done
    echo "-1"
}

string.getHashCode() {
    local str="$1"
    local hash=0
    local i=0
    while [[ $i -lt ${#str} ]]; do
        local char="${str:i:1}"
        hash=$((hash + $(printf '%d' "'$char")))
        hash=$((hash * 31))
        ((i++))
    done
    echo "$hash"
}

string.lastDelimiter() {
    local str="$1"
    local delim="$2"
    local last_index=-1
    local i=0
    while [[ $i -lt ${#str} ]]; do
        local char="${str:i:1}"
        if [[ "$delim" == *"$char"* ]]; then
            last_index=$i
        fi
        ((i++))
    done
    echo "$last_index"
}

string.lastIndexOf() {
    local str="$1"
    local value="$2"
    local startIndex="$3"
    local count="$4"
    local len=${#str}
    local val_len=${#value}
    if [[ -n "$startIndex" ]]; then
        len=$startIndex
    fi
    if [[ -n "$count" ]]; then
        len=$((startIndex - count + 1))
        if [[ $len -lt 0 ]]; then len=0; fi
    fi
    local last_index=-1
    local i=$((len - val_len))
    if [[ $i -lt 0 ]]; then i=0; fi
    while [[ $i -ge 0 ]]; do
        if [[ "${str:i:val_len}" == "$value" ]]; then
            last_index=$i
            break
        fi
        ((i--))
    done
    echo "$last_index"
}

string.lastIndexOfAny() {
    local str="$1"
    local anyOf="$2"
    local startIndex="$3"
    local count="$4"
    local len=${#str}
    if [[ -n "$startIndex" ]]; then
        len=$startIndex
    fi
    if [[ -n "$count" ]]; then
        len=$((startIndex - count + 1))
        if [[ $len -lt 0 ]]; then len=0; fi
    fi
    local last_index=-1
    local i=$((len - 1))
    while [[ $i -ge 0 ]]; do
        if [[ "$anyOf" == *"${str:i:1}"* ]]; then
            last_index=$i
            break
        fi
        ((i--))
    done
    echo "$last_index"
}

string.format() {
    local format="$1"
    shift
    printf "$format" "$@"
}

string.lowerCase() {
    string.toLower "$1"
}

string.compare() {
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
}

string.compareOrdinal() {
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
}

string.compareText() {
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
}

string.compareTo() {
    local self="$1"
    local strB="$2"

    string.compare "$self" "$strB"
}

string.contains() {
    local self="$1"
    local value="$2"

    if [[ "$self" == *"$value"* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.copy() {
    local str="$1"
    echo "$str"
}

string.copyTo() {
    echo "Not implemented"
}

string.countChar() {
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
}

string.create() {
    # Simplified, assume char and count
    local char="$1"
    local count="$2"
    local result=""
    for ((i=0; i<count; i++)); do
        result+="$char"
    done
    echo "$result"
}

string.deQuotedString() {
    local self="$1"
    # Simple remove quotes
    echo "${self//\"/}"
}

string.endsText() {
    local subText="$1"
    local text="$2"
    local sub_lower="${subText,,}"
    local text_lower="${text,,}"
    if [[ "$text_lower" == *"$sub_lower" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.startsWith() {
    local self="$1"
    local value="$2"
    if [[ "$self" == "$value"* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.substring() {
    local self="$1"
    local startIndex="$2"
    local length="$3"
    if [[ -z "$length" ]]; then
        echo "${self:$startIndex}"
    else
        echo "${self:$startIndex:$length}"
    fi
}

string.toBoolean() {
    local self="$1"
    if [[ "$self" == "true" || "$self" == "1" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

string.toCharArray() {
    local self="$1"
    # Simple, echo each char
    for ((i=0; i<${#self}; i++)); do
        echo "${self:i:1}"
    done
}

string.toDouble() {
    local self="$1"
    local num="${self%% *}"
    echo "$num"
}

string.toInt64() {
    local self="$1"
    echo "$(( ${self%%.*} ))"
}

string.toInteger() {
    local self="$1"
    echo "$(( ${self%%.*} ))"
}

string.toLower() {
    local self="$1"
    echo "${self,,}"
}

string.toLowerInvariant() {
    local self="$1"
    echo "${self,,}"
}

string.toSingle() {
    local self="$1"
    local num="${self%% *}"
    echo "$num"
}

string.toUpper() {
    local self="$1"
    echo "${self^^}"
}

string.toUpperInvariant() {
    local self="$1"
    echo "${self^^}"
}

string.trim() {
    local self="$1"
    # Trim spaces
    local trimmed="${self#"${self%%[![:space:]]*}"}"
    echo "${trimmed%"${trimmed##*[![:space:]]}"}"
}

string.trimLeft() {
    local self="$1"
    echo "${self#"${self%%[![:space:]]*}"}"
}

string.trimRight() {
    local self="$1"
    echo "${self%"${self##*[![:space:]]}"}"
}

string.upperCase() {
    local s="$1"
    echo "${s^^}"
}

string.length() {
    local self="$1"
    echo "${#self}"
}

string.chars() {
    local self="$1"
    local index="$2"
    if [[ $index -ge 0 && $index -lt ${#self} ]]; then
        echo "${self:$index:1}"
    else
        echo "undefined"
    fi
}

string.endsWith() {
    local self="$1"
    local value="$2"
    local ignoreCase="$3"
    if [[ "$ignoreCase" == "true" ]]; then
        local self_lower="${self,,}"
        local value_lower="${value,,}"
        if [[ "$self_lower" == *"$value_lower" ]]; then
            echo "true"
        else
            echo "false"
        fi
    else
        if [[ "$self" == *"$value" ]]; then
            echo "true"
        else
            echo "false"
        fi
    fi
}
