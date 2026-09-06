#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TSTRINGHELPER_SOURCED:-}" ]]; then
    return
fi
declare -g _TSTRINGHELPER_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
tstringhelper_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$tstringhelper_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# TStringHelper: a static utility namespace (Free Pascal's TStringHelper).
#
# Pascal DSL form: declare the class STRUCTURE (interface) first, then the
# method BODIES as real bash functions below, then `build string` finalizes it.
# Every member is `static` — there is no per-instance state — so all methods are
# called as `string.<Method>` (the public API, unchanged from before).
#
# Why `proc` and not `func`: these helpers return their result by `echo`ing it
# (the long-standing string.* convention every caller and test depends on), NOT
# via RESULT. `func` would append `kk._return "$RESULT"` (which is empty here);
# `proc` appends nothing, so it is the faithful verb for an echo-style body.
#
# Because the class declares NO static variables, `build` gives each method a
# thin, capture-free dispatcher (no funsub, no scratch file) — the same
# zero-overhead dispatch as the previous kk.register_static_methods wrappers,
# fast on bash 5.2 and 5.3 alike.
# ---------------------------------------------------------------------------
class string
    public
        # comparison / equality
        static proc equals
        static proc compare
        static proc compareOrdinal
        static proc compareText
        static proc compareTo
        static proc contains
        # searching / indexing
        static proc indexOf
        static proc indexOfAny
        static proc indexOfAnyUnquoted
        static proc lastIndexOf
        static proc lastIndexOfAny
        static proc lastDelimiter
        static proc isDelimiter
        # trimming / padding
        static proc trim
        static proc trimLeft
        static proc trimRight
        static proc trimStart
        static proc trimEnd
        static proc padLeft
        static proc padRight
        # case conversion
        static proc toLower
        static proc toLowerInvariant
        static proc toUpper
        static proc toUpperInvariant
        static proc lowerCase
        static proc upperCase
        # predicates
        static proc isEmpty
        static proc isNullOrEmpty
        static proc isNullOrWhiteSpace
        static proc startsWith
        static proc startsText
        static proc endsWith
        static proc endsText
        # editing / building
        static proc replace
        static proc remove
        static proc insert
        static proc split
        static proc join
        static proc substring
        static proc copy
        static proc copyTo
        static proc quotedString
        static proc deQuotedString
        static proc create
        static proc countChar
        # conversion
        static proc toBoolean
        static proc toCharArray
        static proc toDouble
        static proc toExtended
        static proc toInt64
        static proc toInteger
        static proc toSingle
        static proc parse
        # misc
        static proc length
        static proc chars
        static proc getHashCode
        static proc format
end

# ---- method bodies (real bash functions; extracted by `build`) -------------
# Internal helpers string._replace_literal / string._parse_int are NOT declared
# in the class above — they stay as plain functions used by the methods.

string.equals() {
    local str1="$1"
    local str2="${2:-}"
    if [[ "$str1" == "$str2" ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.trimStart() {
    local str="$1"
    local trimChars="${2:-}"
    local result="$str"
    while [[ ${#result} -gt 0 ]] && [[ "$trimChars" == *"${result:0:1}"* ]]; do
        result="${result:1}"
    done
    printf '%s\n' "$result"
}

string.trimEnd() {
    local str="$1"
    local trimChars="${2:-}"
    local result="$str"
    while [[ ${#result} -gt 0 ]] && [[ "$trimChars" == *"${result: -1}"* ]]; do
        result="${result:0:${#result}-1}"
    done
    printf '%s\n' "$result"
}

string.startsText() {
    local subText="$1"
    local text="${2:-}"
    local sub_lower="${subText,,}"
    local text_lower="${text,,}"
    if [[ "$text_lower" == "$sub_lower"* ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.split() {
    local str="$1"
    local sep="${2:-}"
    local count="${3:-}"
    if [[ -z "$sep" ]]; then
        printf '%s\n' "$str"
        return
    fi
    local IFS="$sep"
    local -a parts
    read -ra parts <<< "$str"
    if [[ -n "$count" ]] && (( ${#parts[@]} > count )); then
        parts=("${parts[@]:0:count}")
    fi
    printf '%s\n' "${parts[*]}"
}

string._replace_literal() {
    local str="$1"
    local old="${2:-}"
    local new="${3:-}"
    local replace_all="${4:-}"
    local ignore_case="${5:-}"

    if [[ -z "$old" ]]; then
        printf '%s\n' "$str"
        return
    fi

    local old_length=${#old}
    local result=""
    local offset=0
    local remaining remaining_cmp old_cmp match_index search_index

    old_cmp="$old"
    if [[ "$ignore_case" == "true" ]]; then
        old_cmp="${old,,}"
    fi

    while (( offset <= ${#str} )); do
        remaining="${str:offset}"
        remaining_cmp="$remaining"
        if [[ "$ignore_case" == "true" ]]; then
            remaining_cmp="${remaining,,}"
        fi

        match_index=-1
        for (( search_index = 0; search_index + old_length <= ${#remaining_cmp}; search_index++ )); do
            if [[ "${remaining_cmp:search_index:old_length}" == "$old_cmp" ]]; then
                match_index=$search_index
                break
            fi
        done

        if (( match_index < 0 )); then
            result+="$remaining"
            break
        fi

        result+="${remaining:0:match_index}$new"
        offset=$((offset + match_index + old_length))

        if [[ "$replace_all" != "true" ]]; then
            result+="${str:offset}"
            break
        fi
    done

    printf '%s\n' "$result"
}

string.replace() {
    local str="$1"
    local old="${2:-}"
    local new="${3:-}"
    local flags="${4:-}"
    local replace_all=false
    local ignore_case=false
    [[ "$flags" == *"rfReplaceAll"* ]] && replace_all=true
    [[ "$flags" == *"rfIgnoreCase"* ]] && ignore_case=true
    string._replace_literal "$str" "$old" "$new" "$replace_all" "$ignore_case"
}

string.remove() {
    local str="$1"
    local start="${2:-}"
    local count="${3:-}"
    kk.isInt "$start" start || return 1
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
    if [[ -z "$count" ]]; then
        printf '%s\n' "${str:0:$start}"
    else
        printf '%s\n' "${str:0:$start}${str:$start+$count}"
    fi
}

string.quotedString() {
    local str="$1"
    local quote="${2:-}"
    if [[ -z "$quote" ]]; then
        quote="'"
        # Double internal single quotes
        local escaped=$(printf '%s\n' "$str" | sed "s/'/''/g")
        printf '%s\n' "$quote$escaped$quote"
    else
        printf '%s\n' "$quote$str$quote"
    fi
}

string.parse() {
    printf '%s\n' "$1"
}

string.padLeft() {
    local str="$1"
    local width="${2:-}"
    local padChar="${3:-}"
    kk.isInt "$width" width || return 1
    if [[ -z "$padChar" ]]; then
        padChar=" "
    fi
    local len=${#str}
    if [[ $len -ge $width ]]; then
        printf '%s\n' "$str"
    else
        local padLen=$((width - len))
        local padding=""
        local i
        for ((i = 0; i < padLen; i += 1)); do
            padding+="$padChar"
        done
        printf '%s\n' "$padding$str"
    fi
}

string.padRight() {
    local str="$1"
    local width="${2:-}"
    local padChar="${3:-}"
    kk.isInt "$width" width || return 1
    if [[ -z "$padChar" ]]; then
        padChar=" "
    fi
    local len=${#str}
    if [[ $len -ge $width ]]; then
        printf '%s\n' "$str"
    else
        local padLen=$((width - len))
        local padding=""
        local i
        for ((i = 0; i < padLen; i += 1)); do
            padding+="$padChar"
        done
        printf '%s\n' "$str$padding"
    fi
}

string.join() {
    local sep="$1"
    shift
    local result="" arg          # X-LOCALS (TSH-10): join left $arg behind
    local first=true
    for arg in "$@"; do
        if [[ "$first" == true ]]; then
            result="$arg"
            first=false
        else
            result="$result$sep$arg"
        fi
    done
    printf '%s\n' "$result"
}

string.isNullOrWhiteSpace() {
    local str="$1"
    if [[ -z "$str" ]]; then
        printf '%s\n' "true"
    elif [[ "$str" =~ ^[[:space:]]*$ ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.isNullOrEmpty() {
    local str="$1"
    if [[ -z "$str" ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.isEmpty() {
    string.isNullOrEmpty "$1"
}

string.isDelimiter() {
    local str="$1"
    local index="${2:-}"
    local delims="${3:-}"
    kk.isInt "$index" index || return 1
    if [[ $index -lt 0 || $index -ge ${#str} ]]; then
        printf '%s\n' "false"
    else
        local char="${str:$index:1}"
        if [[ "$delims" == *"$char"* ]]; then
            printf '%s\n' "true"
        else
            printf '%s\n' "false"
        fi
    fi
}

string.insert() {
    local str="$1"
    local index="${2:-}"
    local value="${3:-}"
    kk.isInt "$index" index || return 1
    if [[ $index -le 0 ]]; then
        printf '%s\n' "$value$str"
    elif [[ $index -ge ${#str} ]]; then
        printf '%s\n' "$str$value"
    else
        printf '%s\n' "${str:0:$index}$value${str:$index}"
    fi
}

string.indexOfAnyUnquoted() {
    local str="$1"
    local anyOf="${2:-}"
    local quoteStart="${3:-}"
    local quoteEnd="${4:-}"
    local startIndex="${5:-0}"
    local count="${6:-}"
    kk.isInt "$startIndex" startIndex || return 1
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
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
                printf '%s\n' "$i"
                return
            fi
        else
            if [[ "$char" == "$quoteEnd" ]]; then
                inQuote=false
            fi
        fi
        (( i += 1 )) || :
    done
    printf '%s\n' "-1"
}

string.indexOfAny() {
    local str="$1"
    local anyOf="${2:-}"
    local startIndex="${3:-0}"
    local count="${4:-}"
    kk.isInt "$startIndex" startIndex || return 1
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
    local len=${#str}
    local i=$startIndex
    if [[ -n "$count" ]]; then
        len=$((startIndex + count))
        if [[ $len -gt ${#str} ]]; then len=${#str}; fi
    fi
    while [[ $i -lt $len ]]; do
        local char="${str:i:1}"
        if [[ "$anyOf" == *"$char"* ]]; then
            printf '%s\n' "$i"
            return
        fi
        (( i += 1 )) || :
    done
    printf '%s\n' "-1"
}

string.indexOf() {
    local str="$1"
    local value="${2:-}"
    local startIndex="${3:-0}"
    local count="${4:-}"
    kk.isInt "$startIndex" startIndex || return 1
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
    local len=${#str}
    local val_len=${#value}
    if [[ $val_len -eq 0 ]]; then
        printf '%s\n' "$startIndex"
        return
    fi
    local i=$startIndex
    if [[ -n "$count" ]]; then
        len=$((startIndex + count))
        if [[ $len -gt ${#str} ]]; then len=${#str}; fi
    fi
    while [[ $((i + val_len)) -le $len ]]; do
        if [[ "${str:i:val_len}" == "$value" ]]; then
            printf '%s\n' "$i"
            return
        fi
        (( i += 1 )) || :
    done
    printf '%s\n' "-1"
}

string.getHashCode() {
    local str="$1"
    local hash=0
    local i=0
    local ord
    while [[ $i -lt ${#str} ]]; do
        # printf -v (no subshell) instead of $(printf ...) per character —
        # the old form forked a process for every character in the string.
        printf -v ord '%d' "'${str:i:1}"
        hash=$(( (hash + ord) * 31 ))
        (( i += 1 )) || :
    done
    printf '%s\n' "$hash"
}

string.lastDelimiter() {
    local str="$1"
    local delim="${2:-}"
    local last_index=-1
    local i=0
    while [[ $i -lt ${#str} ]]; do
        local char="${str:i:1}"
        if [[ "$delim" == *"$char"* ]]; then
            last_index=$i
        fi
        (( i += 1 )) || :
    done
    printf '%s\n' "$last_index"
}

string.lastIndexOf() {
    local str="$1"
    local value="${2:-}"
    local startIndex="${3:-}"
    local count="${4:-}"
    if [[ -n "$startIndex" ]]; then kk.isInt "$startIndex" startIndex || return 1; fi
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
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
        (( i -= 1 )) || :
    done
    printf '%s\n' "$last_index"
}

string.lastIndexOfAny() {
    local str="$1"
    local anyOf="${2:-}"
    local startIndex="${3:-}"
    local count="${4:-}"
    if [[ -n "$startIndex" ]]; then kk.isInt "$startIndex" startIndex || return 1; fi
    if [[ -n "$count" ]]; then kk.isInt "$count" count || return 1; fi
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
        (( i -= 1 )) || :
    done
    printf '%s\n' "$last_index"
}

# SECURITY / trust boundary: $format is a caller-supplied printf format string
# (Pascal Format semantics). Do NOT pass untrusted input as the format — it is
# interpreted for directives/width. Bash printf has no %n, so this cannot corrupt
# memory, but an untrusted format can still mis-format or spin on a huge width.
string.format() {
    local format="$1"
    shift
    printf -- "$format" "$@"
}

string.lowerCase() {
    string.toLower "$1"
}

string.compare() {
    local strA="$1"
    local strB="${2:-}"
    local options="${3:-}"
    local locale="${4:-}"

    # Simple implementation: use bash string comparison
    if [[ "$strA" < "$strB" ]]; then
        printf '%s\n' -1
    elif [[ "$strA" > "$strB" ]]; then
        printf '%s\n' 1
    else
        printf '%s\n' 0
    fi
}

string.compareOrdinal() {
    local strA="$1"
    local strB="${2:-}"

    # Ordinal comparison
    if [[ "$strA" < "$strB" ]]; then
        printf '%s\n' -1
    elif [[ "$strA" > "$strB" ]]; then
        printf '%s\n' 1
    else
        printf '%s\n' 0
    fi
}

string.compareText() {
    local strA="$1"
    local strB="${2:-}"

    # Case insensitive
    local a_lower="${strA,,}"
    local b_lower="${strB,,}"
    if [[ "$a_lower" < "$b_lower" ]]; then
        printf '%s\n' -1
    elif [[ "$a_lower" > "$b_lower" ]]; then
        printf '%s\n' 1
    else
        printf '%s\n' 0
    fi
}

string.compareTo() {
    local self="$1"
    local strB="${2:-}"

    string.compare "$self" "$strB"
}

string.contains() {
    local self="$1"
    local value="${2:-}"

    if [[ "$self" == *"$value"* ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.copy() {
    local str="$1"
    printf '%s\n' "$str"
}

string.copyTo() {
    local self="$1"
    local source_index="${2:-}"
    local destination_name="${3:-}"
    local destination_index="${4:-}"
    local count="${5:-}"

    if [[ ! "$source_index" =~ ^[0-9]+$ || ! "$destination_index" =~ ^[0-9]+$ || ! "$count" =~ ^[0-9]+$ ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && printf '%s\n' "Error: CopyTo indexes and count must be non-negative integers" >&2
        return 1
    fi

    if [[ ! "$destination_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && printf '%s\n' "Error: CopyTo destination must be a valid array variable name" >&2
        return 1
    fi

    if (( source_index + count > ${#self} )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && printf '%s\n' "Error: CopyTo source range is out of bounds" >&2
        return 1
    fi

    declare -n destination_ref="$destination_name"
    local char_index
    for (( char_index = 0; char_index < count; char_index++ )); do
        destination_ref[$((destination_index + char_index))]="${self:source_index + char_index:1}"
    done
}

string.countChar() {
    local self="$1"
    local char="${2:-}"
    local count=0
    local i
    for ((i=0; i<${#self}; i++)); do
        if [[ "${self:i:1}" == "$char" ]]; then
            (( count += 1 )) || :
        fi
    done
    printf '%s\n' "$count"
}

string.create() {
    # Simplified, assume char and count
    local char="$1"
    local count="${2:-}"
    local result="" i
    kk.isInt "$count" count || return 1
    for ((i=0; i<count; i++)); do
        result+="$char"
    done
    printf '%s\n' "$result"
}

string.deQuotedString() {
    local self="$1"
    # Simple remove quotes
    printf '%s\n' "${self//\"/}"
}

string.endsText() {
    local subText="$1"
    local text="${2:-}"
    local sub_lower="${subText,,}"
    local text_lower="${text,,}"
    if [[ "$text_lower" == *"$sub_lower" ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.startsWith() {
    local self="$1"
    local value="${2:-}"
    if [[ "$self" == "$value"* ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.substring() {
    local self="$1"
    local startIndex="${2:-}"
    local length="${3:-}"
    kk.isInt "$startIndex" startIndex || return 1
    if [[ -n "$length" ]]; then kk.isInt "$length" length || return 1; fi
    if [[ -z "$length" ]]; then
        printf '%s\n' "${self:$startIndex}"
    else
        printf '%s\n' "${self:$startIndex:$length}"
    fi
}

string.toBoolean() {
    local self="$1"
    if [[ "$self" == "true" || "$self" == "1" ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "false"
    fi
}

string.toCharArray() {
    local self="$1"
    local start_index="${2:-0}"
    local length="${3:-}"

    if [[ ! "$start_index" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [[ -z "$length" ]]; then
        length=$((${#self} - start_index))
    elif [[ ! "$length" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if (( start_index > ${#self} )); then
        return 1
    fi

    local end_index=$((start_index + length))
    if (( end_index > ${#self} )); then
        end_index=${#self}
    fi

    local char_index
    for (( char_index = start_index; char_index < end_index; char_index++ )); do
        printf '%s\n' "${self:char_index:1}"
    done
}

string.toDouble() {
    local self="$1"
    local num="${self%% *}"
    printf '%s\n' "$num"
}

string.toExtended() {
    local self="$1"
    local num="${self%% *}"
    printf '%s\n' "$num"
}

string.toInt64() {
    string._parse_int "$1"
}

string.toInteger() {
    string._parse_int "$1"
}

# Parse the integer part of a decimal string safely.
# SECURITY: never feed raw input to $(( )) — bash evaluates array subscripts
# there, so input like 'a[$(cmd)]' would execute cmd (RCE). Validate as a
# decimal integer FIRST, then normalize via base-10 arithmetic on digits only.
string._parse_int() {
    local self="$1"
    local int_part="${self%%.*}"
    # Trim surrounding whitespace.
    int_part="${int_part#"${int_part%%[![:space:]]*}"}"
    int_part="${int_part%"${int_part##*[![:space:]]}"}"
    if [[ "$int_part" =~ ^([+-]?)([0-9]+)$ ]]; then
        local sign="${BASH_REMATCH[1]}"
        [[ "$sign" == "+" ]] && sign=""
        printf '%s\n' "$(( ${sign}10#${BASH_REMATCH[2]} ))"
        return 0
    fi
    printf '%s\n' 0
    return 1
}

string.toLower() {
    local self="$1"
    printf '%s\n' "${self,,}"
}

string.toLowerInvariant() {
    local self="$1"
    printf '%s\n' "${self,,}"
}

string.toSingle() {
    local self="$1"
    local num="${self%% *}"
    printf '%s\n' "$num"
}

string.toUpper() {
    local self="$1"
    printf '%s\n' "${self^^}"
}

string.toUpperInvariant() {
    local self="$1"
    printf '%s\n' "${self^^}"
}

string.trim() {
    local self="$1"
    # Trim spaces
    local trimmed="${self#"${self%%[![:space:]]*}"}"
    printf '%s\n' "${trimmed%"${trimmed##*[![:space:]]}"}"
}

string.trimLeft() {
    local self="$1"
    printf '%s\n' "${self#"${self%%[![:space:]]*}"}"
}

string.trimRight() {
    local self="$1"
    printf '%s\n' "${self%"${self##*[![:space:]]}"}"
}

string.upperCase() {
    local s="$1"
    printf '%s\n' "${s^^}"
}

string.length() {
    local self="$1"
    printf '%s\n' "${#self}"
}

string.chars() {
    local self="$1"
    local index="${2:-}"
    kk.isInt "$index" index || return 1
    if [[ $index -ge 0 && $index -lt ${#self} ]]; then
        printf '%s\n' "${self:$index:1}"
    else
        printf '%s\n' "undefined"
    fi
}

string.endsWith() {
    local self="$1"
    local value="${2:-}"
    local ignoreCase="${3:-}"
    if [[ "$ignoreCase" == "true" ]]; then
        local self_lower="${self,,}"
        local value_lower="${value,,}"
        if [[ "$self_lower" == *"$value_lower" ]]; then
            printf '%s\n' "true"
        else
            printf '%s\n' "false"
        fi
    else
        if [[ "$self" == *"$value" ]]; then
            printf '%s\n' "true"
        else
            printf '%s\n' "false"
        fi
    fi
}

# Finalize: extract the bodies above into the `string` class and generate the
# static dispatchers (thin, capture-free — see the header note). The class is
# named `string`, so the public API stays `string.<Method>` and the kklass
# metadata array `string_class_static_methods` is populated as before.
build string
