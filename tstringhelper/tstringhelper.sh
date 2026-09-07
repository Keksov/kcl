#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TSTRINGHELPER_SOURCED:-}" ]]; then
    return
fi
declare -g _TSTRINGHELPER_SOURCED=1

# Locale self-heal (decision D6, kcl/README.md 1.6, finding TSH-04). Character
# semantics are this unit's whole contract: `length`, `chars`, `substring`,
# `indexOf` and `padLeft` are defined on CHARACTERS, and `toLower`/`toUpper`
# must not corrupt multi-byte text. An empty environment means the C locale,
# where `${#s}` counts bytes, `${s:i:1}` cuts a lone byte out of a character
# and `${s,,}` mangles UTF-8 on bash 5.2.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
tstringhelper_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$tstringhelper_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# TStringHelper: a static utility namespace (Free Pascal's TStringHelper).
#
# Upstream reference: FPC 3.2.2, rtl/objpas/sysutils/syshelph.inc (declaration)
# and syshelp.inc (implementation), plus sysstr.inc for the SysUtils routines
# the helper delegates to (Trim, AnsiQuotedStr, TryStrToBool, StrToInt,
# StringReplace) and rtl/inc/astrings.inc for Copy/Delete/Insert clamping.
# See tstringhelper/README.md for the member table and the differences.
#
# ---- Return contract (decision D3, kcl/README.md 1.1) ----------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )`
# the value is printed exactly once, so every `v=$(string.x ...)` caller keeps
# working. Predicates additionally answer with their exit status (R8):
#
#     string.trim "$s"; use "$RESULT"            # no fork
#     t="$(string.trim "$s")"                    # still works, forks
#     if string.contains "$s" x; then ...        # rc; RESULT is true/false
#
# Members are `static proc`, not `static func`, and the value goes out through
# string._ret. That is NOT a deviation from D3's semantics, it is the only way
# to get them: kklass's THIN static dispatcher (the one a class without static
# variables receives) re-prints kk._return's value UNCONDITIONALLY, i.e. on a
# direct call too — `static func` would make every member echo on every call.
# string._ret is kk._return's contract with the subshell test kept and the
# dispatcher's unconditional printf avoided (kcl/README.md 1.1, P3 pattern).
#
# Errors are rc 1 + RESULT='' and print nothing; rc 2 marks a malformed CALL —
# a reserved or non-identifier output-array name, an unknown option token
# (kcl/README.md 1.2 and 1.7). Numeric arguments go through kk.isInt/kk.isNum
# (decision D1) before they reach `(( ))`.
#
# ---- Internal helpers ------------------------------------------------------
# The string._* helpers below are NOT class members: they are plain functions,
# so members can share logic without a nested `$( )`. `__tsh_r` is the shared
# return channel — a member that calls one MUST declare `local __tsh_r` first.
# `__tsh_*` is this unit's reserved variable prefix and is refused as an
# output-array name; the three members that bind a caller nameref
# (split, toCharArray, copyTo) name ALL of their locals with it, because bash
# scopes locals dynamically and an unprefixed local would be silently aliased
# by a caller array of the same name (finding TSH-16).
#
# ---- Performance -----------------------------------------------------------
# The search and edit members use bash's own string operators — `${s//"$old"/…}`
# for replace, `${t%%"$v"*}` for indexOf, `${s//"$c"/}` for countChar — instead
# of a per-character loop: 10 KB replace/indexOf/countChar cost 520-600 ms per
# call before, and a small multiple of `${big//X/Y}` now (finding TSH-09,
# gated by tests/066_TSH09_Performance.sh). A quoted pattern is LITERAL, which
# is also what makes glob metacharacters in the needle safe; the replacement
# must be quoted too, because bash reads an unquoted `&` in it as "the matched
# text".
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

# ---------------------------------------------------------------------------
# Internal helpers (plain functions, not class members)
# ---------------------------------------------------------------------------

# The return channel (kcl/README.md 1.1). $1 = value, $2 = exit status.
string._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# A boolean answer: RESULT/stdout carry true|false and the exit status carries
# the same answer (R8). $1 = 0 for true, anything else for false.
string._retBool() {
    if [[ "$1" == "0" ]]; then
        string._ret "true" 0
    else
        string._ret "false" 1
    fi
}

# The error path: rc 1 (or $1), RESULT empty, nothing printed anywhere.
string._fail() {
    RESULT=""
    return "${1:-1}"
}

# A diagnostic, only under the one debug switch (kcl/README.md 1.2).
string._debug() {
    if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
        printf '%s\n' "string: $1" >&2
    fi
}

# A negative index or count in the SEARCH family is a rejected VALUE, not a
# semantic to reproduce (P5 review remark 1, kcl/README.md 1.2 and 1.5). FPC's
# own arithmetic there is undefined by accident: IndexOf clamps the window with
# Copy but still adds the RAW StartIndex to the result, so
# `indexOf 'hello world' o -3` would answer 1 and, with an explicit ACount, can
# even land on -1 — indistinguishable from "not found". Where FPC genuinely
# DEFINES the clamping — Copy and Delete, i.e. substring and remove — it is
# kept. rc 1 = reject.
string._nonNeg() {   # VALUE MEMBER ARGNAME
    if (( $1 < 0 )); then
        string._debug "$2: $3 must not be negative ($1)"
        RESULT=""
        return 1
    fi
    return 0
}

# rc 0 = the name may NOT be used as an output array (kcl/README.md 1.7).
string._badOutName() {
    case "${1:-}" in
        ""|RESULT|REPLY|IFS|this|__inst__|__class__) return 0 ;;
        __kk_*|__KK_*|__tsh_*) return 0 ;;
    esac
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]]; then
        return 0
    fi
    return 1
}

# FPC Copy(S, INDEX, SIZE) -> __tsh_r, with fpc_ansistr_copy's clamping
# (rtl/inc/astrings.inc): a 1-based index below 1 reads from the start, a size
# past the end is shortened, and a non-positive size gives ''.
string._copy() {   # STR INDEX1 SIZE
    local __tsh_s="$1" __tsh_i=$(( $2 - 1 )) __tsh_sz="$3" __tsh_len
    __tsh_len=${#__tsh_s}
    if (( __tsh_i < 0 )); then __tsh_i=0; fi
    if (( __tsh_sz > __tsh_len || __tsh_i + __tsh_sz > __tsh_len )); then
        __tsh_sz=$(( __tsh_len - __tsh_i ))
    fi
    if (( __tsh_sz > 0 )); then
        __tsh_r="${__tsh_s:__tsh_i:__tsh_sz}"
    else
        __tsh_r=""
    fi
}

# The index of the FIRST character of SET inside STR, or -1 (both 0-based).
# One `${t%%"$c"*}` per set member instead of one comparison per character of
# the haystack (finding TSH-09).
string._firstOfSet() {   # STR SET -> __tsh_r
    local __tsh_t="$1" __tsh_set="$2" __tsh_i __tsh_c __tsh_pre __tsh_best=-1
    for (( __tsh_i = 0; __tsh_i < ${#__tsh_set}; __tsh_i++ )); do
        __tsh_c="${__tsh_set:__tsh_i:1}"
        if [[ "$__tsh_t" == *"$__tsh_c"* ]]; then
            __tsh_pre="${__tsh_t%%"$__tsh_c"*}"
            if (( __tsh_best < 0 || ${#__tsh_pre} < __tsh_best )); then
                __tsh_best=${#__tsh_pre}
            fi
        fi
    done
    __tsh_r=$__tsh_best
}

# The index of the LAST character of SET inside STR, or -1 (both 0-based).
string._lastOfSet() {   # STR SET -> __tsh_r
    local __tsh_t="$1" __tsh_set="$2" __tsh_i __tsh_c __tsh_pre __tsh_best=-1
    for (( __tsh_i = 0; __tsh_i < ${#__tsh_set}; __tsh_i++ )); do
        __tsh_c="${__tsh_set:__tsh_i:1}"
        if [[ "$__tsh_t" == *"$__tsh_c"* ]]; then
            __tsh_pre="${__tsh_t%"$__tsh_c"*}"
            if (( ${#__tsh_pre} > __tsh_best )); then
                __tsh_best=${#__tsh_pre}
            fi
        fi
    done
    __tsh_r=$__tsh_best
}

# FPC's SysUtils whitespace set is [#0..' '] (sysstr.inc:624) — every code
# point up to and including the space, NOT [[:space:]] and not [[:cntrl:]],
# which would also sweep up DEL (#127). A bash string cannot hold #0, so the
# live range is #1..#32 (finding TSH-12).
string._trimWs() {   # STR MODE(left|right|both) -> __tsh_r
    local __tsh_s="$1" __tsh_cut
    if [[ "$2" != "right" ]]; then
        __tsh_cut="${__tsh_s%%[!$'\001'-$'\040']*}"
        __tsh_s="${__tsh_s#"$__tsh_cut"}"
    fi
    if [[ "$2" != "left" ]]; then
        __tsh_cut="${__tsh_s##*[!$'\001'-$'\040']}"
        __tsh_s="${__tsh_s%"$__tsh_cut"}"
    fi
    __tsh_r="$__tsh_s"
}

# FPC Val for integers (rtl/inc/sstrings.inc, InitVal + fpc_Val_SInt_ShortStr):
# leading spaces/TABs, an optional sign, an optional base prefix
# ($ x X 0x 0X = 16, % = 2, & = 8), leading zeros, then digits of that base and
# nothing else. -> __tsh_r; rc 1 = the conversion fails (FPC raises).
string._parseInt() {   # VALUE BITS -> __tsh_r
    local __tsh_s="${1:-}" __tsh_bits="$2" __tsh_neg=0 __tsh_base=10
    local __tsh_cut __tsh_v __tsh_maxdig

    # InitVal: skip spaces and TABs.
    __tsh_cut="${__tsh_s%%[!$' \t']*}"
    __tsh_s="${__tsh_s#"$__tsh_cut"}"

    case "$__tsh_s" in
        -*) __tsh_neg=1; __tsh_s="${__tsh_s#-}" ;;
        +*) __tsh_s="${__tsh_s#+}" ;;
    esac
    case "$__tsh_s" in
        '$'*) __tsh_base=16; __tsh_s="${__tsh_s:1}" ;;
        [xX]*) __tsh_base=16; __tsh_s="${__tsh_s:1}" ;;
        '%'*) __tsh_base=2;  __tsh_s="${__tsh_s:1}" ;;
        '&'*) __tsh_base=8;  __tsh_s="${__tsh_s:1}" ;;
        0[xX]*) __tsh_base=16; __tsh_s="${__tsh_s:2}" ;;
    esac

    # InitVal strips leading zeros but always keeps one digit.
    while (( ${#__tsh_s} > 1 )) && [[ "$__tsh_s" == 0* ]]; do
        __tsh_s="${__tsh_s:1}"
    done
    [[ -n "$__tsh_s" ]] || return 1

    case $__tsh_base in
        10) [[ "$__tsh_s" != *[!0-9]* ]] || return 1 ;;
        16) [[ "$__tsh_s" != *[!0-9a-fA-F]* ]] || return 1
            __tsh_maxdig=$(( __tsh_bits / 4 )) ;;
        8)  [[ "$__tsh_s" != *[!0-7]* ]] || return 1
            __tsh_maxdig=$(( __tsh_bits / 3 )) ;;
        2)  [[ "$__tsh_s" != *[!01]* ]] || return 1
            __tsh_maxdig=$__tsh_bits ;;
    esac

    if (( __tsh_base == 10 )); then
        # kk.isInt carries the int64 range check (D1). The sign goes with the
        # digits, so -9223372036854775808 is inside the range and its positive
        # twin is not.
        if (( __tsh_neg )); then
            kk.isInt "-$__tsh_s" || return 1
        else
            kk.isInt "$__tsh_s" || return 1
        fi
        __tsh_v="$__KK_INT"
        if (( __tsh_bits == 32 )) && (( __tsh_v > 2147483647 || __tsh_v < -2147483648 )); then
            return 1
        fi
    else
        # A literal wider than the destination is refused rather than
        # truncated from 64 bits the way FPC's Val does (see README).
        (( ${#__tsh_s} <= __tsh_maxdig )) || return 1
        # The base must be a literal in an arithmetic base prefix, and the
        # digits have already been validated for that base above.
        case $__tsh_base in
            16) __tsh_v=$(( 16#$__tsh_s )) ;;
            8)  __tsh_v=$(( 8#$__tsh_s )) ;;
            *)  __tsh_v=$(( 2#$__tsh_s )) ;;
        esac
        if (( __tsh_neg )); then
            __tsh_v=$(( -__tsh_v ))
        elif (( __tsh_bits == 32 && __tsh_v > 2147483647 )); then
            # FPC sign-extends a non-decimal literal to the destination size.
            __tsh_v=$(( __tsh_v - 4294967296 ))
        fi
    fi
    __tsh_r="$__tsh_v"
    return 0
}

# ---- method bodies (real bash functions; extracted by `build`) -------------

string.equals() {
    local str1="${1:-}" str2="${2:-}"
    if [[ "$str1" == "$str2" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# FPC Compare(A,B) = Compare(A,0,B,0,Length(B),[]) — a PREFIX comparison over
# min(Length(A),Length(B)) characters. This port compares the whole strings,
# which is what every caller and test in the corpus expects; see the README's
# "Differences from FPC".
string.compare() {
    local strA="${1:-}" strB="${2:-}"
    if [[ "$strA" < "$strB" ]]; then
        string._ret -1
    elif [[ "$strA" > "$strB" ]]; then
        string._ret 1
    else
        string._ret 0
    fi
}

string.compareOrdinal() {
    string.compare "${1:-}" "${2:-}"
}

string.compareText() {
    local a_lower="${1:-}" b_lower="${2:-}"
    a_lower="${a_lower,,}"; b_lower="${b_lower,,}"
    if [[ "$a_lower" < "$b_lower" ]]; then
        string._ret -1
    elif [[ "$a_lower" > "$b_lower" ]]; then
        string._ret 1
    else
        string._ret 0
    fi
}

string.compareTo() {
    string.compare "${1:-}" "${2:-}"
}

string.contains() {
    local self="${1:-}" value="${2:-}"
    if [[ "$self" == *"$value"* ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# FPC: S := Copy(Self,StartIndex+1,ACount); Result := Pos(AValue,S)-1;
#      if Result<>-1 then Result := Result+StartIndex;
# Pos of an EMPTY substring is 0, so indexOf('') is -1 (FPC 3.2, TSH-13), and
# the `+StartIndex` correction is applied to the raw argument.
string.indexOf() {
    local self="${1:-}" value="${2:-}" startIndex="${3:-0}" count="${4:-}"
    kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
    string._nonNeg "$startIndex" indexOf StartIndex || return 1
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
        string._nonNeg "$count" indexOf Count || return 1
    else
        count=${#self}
    fi
    if [[ -z "$value" ]]; then
        string._ret -1
        return 0
    fi
    local pre
    # The whole-string case is the common one and needs no window copy at all.
    if (( startIndex == 0 && count >= ${#self} )); then
        if [[ "$self" != *"$value"* ]]; then
            string._ret -1
            return 0
        fi
        pre="${self%%"$value"*}"
        string._ret "${#pre}"
        return 0
    fi
    local __tsh_r
    string._copy "$self" $(( startIndex + 1 )) "$count"
    local window="$__tsh_r"
    if [[ "$window" != *"$value"* ]]; then
        string._ret -1
        return 0
    fi
    pre="${window%%"$value"*}"
    string._ret $(( ${#pre} + startIndex ))
}

# FPC: I := StartIndex+1; L := I+ACount-1; if L>Length then L:=Length; scan.
# AnyOf is a SET of characters; an empty set never matches.
string.indexOfAny() {
    local self="${1:-}" anyOf="${2:-}" startIndex="${3:-0}" count="${4:-}"
    kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
    string._nonNeg "$startIndex" indexOfAny StartIndex || return 1
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
        string._nonNeg "$count" indexOfAny Count || return 1
    else
        count=${#self}
    fi
    local from=$startIndex to=$(( startIndex + count )) len=${#self}
    if (( to > len )); then to=$len; fi
    if (( from >= to )) || [[ -z "$anyOf" ]]; then
        string._ret -1
        return 0
    fi
    local __tsh_r
    if (( from == 0 && to == len )); then
        string._firstOfSet "$self" "$anyOf"      # no window copy
    else
        string._firstOfSet "${self:from:to-from}" "$anyOf"
    fi
    if (( __tsh_r < 0 )); then
        string._ret -1
    else
        string._ret $(( __tsh_r + from ))
    fi
}

# The quote state machine has to see every character, so this one stays a
# loop. FPC computes its scan limit as StartIndex+ACount-1, one character
# short of IndexOfAny's — with the default ACount that drops the LAST
# character of the string. This port scans ACount characters (see README).
string.indexOfAnyUnquoted() {
    local self="${1:-}" anyOf="${2:-}" quoteStart="${3:-}" quoteEnd="${4:-}"
    local startIndex="${5:-0}" count="${6:-}"
    kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
    string._nonNeg "$startIndex" indexOfAnyUnquoted StartIndex || return 1
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
        string._nonNeg "$count" indexOfAnyUnquoted Count || return 1
    else
        count=${#self}
    fi
    local len=${#self} to=$(( startIndex + count )) i=$startIndex
    if (( to > len )); then to=$len; fi
    local depth=0 char same=0
    if [[ "$quoteStart" == "$quoteEnd" ]]; then same=1; fi
    while (( i < to )); do
        char="${self:i:1}"
        if (( same )); then
            if [[ -n "$quoteStart" && "$char" == "$quoteStart" ]]; then
                depth=$(( 1 - depth ))
            fi
        else
            if [[ -n "$quoteStart" && "$char" == "$quoteStart" ]]; then
                (( depth += 1 )) || :
            elif [[ -n "$quoteEnd" && "$char" == "$quoteEnd" ]] && (( depth > 0 )); then
                (( depth -= 1 )) || :
            fi
        fi
        if (( depth == 0 )) && [[ -n "$anyOf" && "$anyOf" == *"$char"* ]]; then
            string._ret "$i"
            return 0
        fi
        (( i += 1 )) || :
    done
    string._ret -1
}

# FPC (LastIndexOf with a string needle):
#   if (L=0) or (L>LS) then Exit(-1);
#   I := AStartIndex+1; if I>LS then I:=LS; I := I-L+1;
#   M := AStartIndex-ACount+2; if M<1 then M:=1;
#   while (Result=-1) and (I>=M) do  ... Dec(I);
# so AStartIndex is the inclusive index of the last character a match may END
# on and ACount is a lower bound counted back from it (finding TSH-06).
string.lastIndexOf() {
    local self="${1:-}" value="${2:-}" startIndex="${3:-}" count="${4:-}"
    local ls=${#self} lv=${#value}
    if [[ -n "$startIndex" ]]; then
        kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
        string._nonNeg "$startIndex" lastIndexOf StartIndex || return 1
    else
        startIndex=$(( ls - 1 ))          # a computed default, may be -1
    fi
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
        string._nonNeg "$count" lastIndexOf Count || return 1
    else
        count=$ls
    fi
    if (( lv == 0 || lv > ls )); then
        string._ret -1
        return 0
    fi
    local i=$(( startIndex + 1 ))
    if (( i > ls )); then i=$ls; fi
    i=$(( i - lv + 1 ))
    local m=$(( startIndex - count + 2 ))
    if (( m < 1 )); then m=1; fi
    if (( i < m )); then
        string._ret -1
        return 0
    fi
    # Everything a match starting at or before i-1 can cover; when that is the
    # whole string (the default StartIndex) no copy is made.
    local window pre
    if (( i - 1 + lv >= ls )); then
        window="$self"
    else
        window="${self:0:i - 1 + lv}"
    fi
    if [[ "$window" != *"$value"* ]]; then
        string._ret -1
        return 0
    fi
    pre="${window%"$value"*}"
    if (( ${#pre} >= m - 1 )); then
        string._ret "${#pre}"
    else
        string._ret -1
    fi
}

# FPC: Result := AStartIndex+1; Min := Result-ACount+1; if Min<1 then Min:=1;
# scanning down while the character is not in AnyOf. FPC does not clamp the
# scan position to the end of the string (Pascal reads out of bounds there);
# this port clamps to the last character.
string.lastIndexOfAny() {
    local self="${1:-}" anyOf="${2:-}" startIndex="${3:-}" count="${4:-}"
    local ls=${#self}
    if [[ -n "$startIndex" ]]; then
        kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
        string._nonNeg "$startIndex" lastIndexOfAny StartIndex || return 1
    else
        startIndex=$(( ls - 1 ))          # a computed default, may be -1
    fi
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
        string._nonNeg "$count" lastIndexOfAny Count || return 1
    else
        count=$ls
    fi
    local pos=$(( startIndex + 1 )) m=$(( startIndex - count + 2 ))
    if (( pos > ls )); then pos=$ls; fi
    if (( m < 1 )); then m=1; fi
    if (( pos < m )) || [[ -z "$anyOf" ]]; then
        string._ret -1
        return 0
    fi
    local __tsh_r
    if (( m == 1 && pos == ls )); then
        string._lastOfSet "$self" "$anyOf"       # no window copy
    else
        string._lastOfSet "${self:m - 1:pos - m + 1}" "$anyOf"
    fi
    if (( __tsh_r < 0 )); then
        string._ret -1
    else
        string._ret $(( __tsh_r + m - 1 ))
    fi
}

# FPC: SysUtils.LastDelimiter(Delims,Self)-1 — the whole string, no window.
string.lastDelimiter() {
    local self="${1:-}" delim="${2:-}"
    if [[ -z "$delim" || -z "$self" ]]; then
        string._ret -1
        return 0
    fi
    local __tsh_r
    string._lastOfSet "$self" "$delim"
    string._ret "$__tsh_r"
}

# FPC: SysUtils.IsDelimiter(Delimiters,Self,Index+1) — False outside [1..Length]
# and False for an empty delimiter set.
string.isDelimiter() {
    local self="${1:-}" index="${2:-}" delims="${3:-}"
    kk.isInt "$index" index || { RESULT=""; return 1; }
    if (( index < 0 || index >= ${#self} )) || [[ -z "$delims" ]]; then
        string._retBool 1
        return $?
    fi
    local char="${self:index:1}"
    if [[ "$delims" == *"$char"* ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

string.trim() {
    local __tsh_r
    string._trimWs "${1:-}" both
    string._ret "$__tsh_r"
}

string.trimLeft() {
    local __tsh_r
    string._trimWs "${1:-}" left
    string._ret "$__tsh_r"
}

string.trimRight() {
    local __tsh_r
    string._trimWs "${1:-}" right
    string._ret "$__tsh_r"
}

# FPC TrimStart(ATrimChars) = TrimLeft(ATrimChars): a character SET, not the
# whitespace set. An empty set strips nothing (HaveChar over an empty array).
string.trimStart() {
    local result="${1:-}" trimChars="${2:-}"
    if [[ -n "$trimChars" ]]; then
        while [[ -n "$result" && "$trimChars" == *"${result:0:1}"* ]]; do
            result="${result:1}"
        done
    fi
    string._ret "$result"
}

string.trimEnd() {
    local result="${1:-}" trimChars="${2:-}"
    if [[ -n "$trimChars" ]]; then
        while [[ -n "$result" && "$trimChars" == *"${result: -1}"* ]]; do
            result="${result:0:${#result}-1}"
        done
    fi
    string._ret "$result"
}

# FPC: L := ATotalWidth-Length; if L>0 then StringOfChar(PaddingChar,L)+Self.
# `printf -v` plus one substitution instead of a per-character loop.
string.padLeft() {
    local str="${1:-}" width="${2:-}" padChar="${3:-}"
    kk.isInt "$width" width || { RESULT=""; return 1; }
    if [[ -z "$padChar" ]]; then padChar=" "; fi
    local padLen=$(( width - ${#str} ))
    if (( padLen <= 0 )); then
        string._ret "$str"
        return 0
    fi
    local padding
    printf -v padding '%*s' "$padLen" ''
    string._ret "${padding// /"$padChar"}$str"
}

string.padRight() {
    local str="${1:-}" width="${2:-}" padChar="${3:-}"
    kk.isInt "$width" width || { RESULT=""; return 1; }
    if [[ -z "$padChar" ]]; then padChar=" "; fi
    local padLen=$(( width - ${#str} ))
    if (( padLen <= 0 )); then
        string._ret "$str"
        return 0
    fi
    local padding
    printf -v padding '%*s' "$padLen" ''
    string._ret "$str${padding// /"$padChar"}"
}

string.toLower() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s,,}"
}

string.toLowerInvariant() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s,,}"
}

string.toUpper() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s^^}"
}

string.toUpperInvariant() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s^^}"
}

string.lowerCase() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s,,}"
}

string.upperCase() {
    local __tsh_s="${1:-}"
    string._ret "${__tsh_s^^}"
}

string.isEmpty() {
    if [[ -z "${1:-}" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

string.isNullOrEmpty() {
    if [[ -z "${1:-}" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# FPC: Length(SysUtils.Trim(AValue))=0 — the [#0..' '] set again, not
# [[:space:]] (finding TSH-12).
string.isNullOrWhiteSpace() {
    local __tsh_r
    string._trimWs "${1:-}" both
    if [[ -z "$__tsh_r" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

string.startsWith() {
    local self="${1:-}" value="${2:-}" ignoreCase="${3:-}"
    if [[ "$ignoreCase" == "true" ]]; then
        self="${self,,}"; value="${value,,}"
    fi
    if [[ "$self" == "$value"* ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# TStringHelper has no StartsText member (only the EndsText class function),
# and StrUtils.AnsiStartsText answers TRUE for an empty subtext. This unit
# ports TStringHelper, so startsText follows its sibling EndsText instead: an
# EMPTY subtext is FALSE, and the two Text predicates agree with each other.
# startsWith/endsWith are TStringHelper members and keep their own rule
# (`Result := L<=0`, an empty value is TRUE) — the asymmetry is upstream's.
string.startsText() {
    local subText="${1:-}" text="${2:-}"
    if [[ -n "$subText" && "${text,,}" == "${subText,,}"* ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

string.endsWith() {
    local self="${1:-}" value="${2:-}" ignoreCase="${3:-}"
    if [[ "$ignoreCase" == "true" ]]; then
        self="${self,,}"; value="${value,,}"
    fi
    if [[ "$self" == *"$value" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# FPC TStringHelper.EndsText (syshelp.inc):
#     Result := (ASubText<>'') and (CompareText(Copy(...),ASubText)=0);
# so an EMPTY subtext is FALSE. StrUtils.AnsiEndsText says the opposite
# (`(ASubText='') or ...`); this unit ports the class function.
string.endsText() {
    local subText="${1:-}" text="${2:-}"
    if [[ -n "$subText" && "${text,,}" == *"${subText,,}" ]]; then
        string._retBool 0
    else
        string._retBool 1
    fi
}

# FPC: Replace(Old,New) = StringReplace(...,[rfReplaceAll]) — ALL occurrences
# by default (finding TSH-05); Replace(Old,New,Flags) uses the given set, so
# an EMPTY flag argument means "the first occurrence only". The difference is
# the argument COUNT, not emptiness. StringReplace with an empty OldPattern
# returns the string unchanged (syssr.inc), and its rfIgnoreCase path upcases
# both sides and never rescans the replacement.
string.replace() {
    local str="${1:-}" old="${2:-}" new="${3:-}"
    local replace_all=1 ignore_case=0
    if (( $# >= 4 )); then
        replace_all=0
        case "${4:-}" in *rfReplaceAll*) replace_all=1 ;; esac
        case "${4:-}" in *rfIgnoreCase*) ignore_case=1 ;; esac
    fi
    if [[ -z "$old" ]]; then
        string._ret "$str"
        return 0
    fi
    if (( ! ignore_case )); then
        # A quoted pattern is literal; the replacement must be quoted too,
        # because bash reads an unquoted `&` as "the matched text".
        if (( replace_all )); then
            string._ret "${str//"$old"/"$new"}"
        else
            string._ret "${str/"$old"/"$new"}"
        fi
        return 0
    fi
    # rfIgnoreCase: walk the upper-cased copy, cut from the original.
    local up="${str^^}" oldUp="${old^^}" out="" pre cut
    local oldLen=${#old}
    while [[ "$up" == *"$oldUp"* ]]; do
        pre="${up%%"$oldUp"*}"
        cut=${#pre}
        out+="${str:0:cut}$new"
        str="${str:cut + oldLen}"
        up="${up:cut + oldLen}"
        if (( ! replace_all )); then
            break
        fi
    done
    string._ret "$out$str"
}

# FPC: Remove(I) = Remove(I,Length-I); Remove(I,C) = Delete(Result,I+1,C), and
# Delete does NOTHING when the 1-based index is outside [1..Length] or the
# count is <= 0 (rtl/inc/astrings.inc) — finding TSH-11.
string.remove() {
    local str="${1:-}" start="${2:-}" count="${3:-}"
    kk.isInt "$start" start || { RESULT=""; return 1; }
    if [[ -n "$count" ]]; then
        kk.isInt "$count" count || { RESULT=""; return 1; }
    else
        count=$(( ${#str} - start ))
    fi
    local len=${#str} index=$(( start + 1 ))
    if (( index > len || index <= 0 || count <= 0 )); then
        string._ret "$str"
        return 0
    fi
    if (( count > len - index )); then
        count=$(( len - index + 1 ))
    fi
    string._ret "${str:0:start}${str:start + count}"
}

# FPC: system.Insert(AValue,Self,StartIndex+1) — an index below 1 prepends and
# an index past the end appends (rtl/inc/astrings.inc).
string.insert() {
    local str="${1:-}" index="${2:-}" value="${3:-}"
    kk.isInt "$index" index || { RESULT=""; return 1; }
    if (( index <= 0 )); then
        string._ret "$value$str"
    elif (( index >= ${#str} )); then
        string._ret "$str$value"
    else
        string._ret "${str:0:index}$value${str:index}"
    fi
}

# string.split STR SEP ARRAY [COUNT] [OPTIONS]  (R9, kcl/README.md 1.7)
#
# Fills the caller's ARRAY by nameref and returns the part COUNT in RESULT.
# SEP is one literal STRING (FPC's `array of string` overload with a single
# element), COUNT is FPC's ACount — 0 means unlimited and the parts beyond the
# limit are DISCARDED — and OPTIONS is TStringSplitOptions: None,
# ExcludeEmpty, ExcludeLastEmpty. Every local carries the reserved __tsh_
# prefix because ARRAY is a caller-supplied name (finding TSH-16).
string.split() {
    local __tsh_str="${1:-}" __tsh_sep="${2:-}" __tsh_name="${3:-}"
    local __tsh_count="${4:-0}" __tsh_opt="${5:-None}"
    if string._badOutName "$__tsh_name"; then
        string._debug "split: bad output array name '$__tsh_name'"
        RESULT=""
        return 2
    fi
    case "$__tsh_opt" in
        None|ExcludeEmpty|ExcludeLastEmpty) ;;
        *) string._debug "split: unknown option '$__tsh_opt'"; RESULT=""; return 2 ;;
    esac
    if [[ -z "$__tsh_count" ]]; then __tsh_count=0; fi
    kk.isInt "$__tsh_count" __tsh_count || { RESULT=""; return 1; }
    local -n __tsh_out="$__tsh_name"
    __tsh_out=()
    local __tsh_n=0 __tsh_rest="$__tsh_str" __tsh_part __tsh_tail=1
    if [[ -z "$__tsh_sep" ]]; then
        __tsh_out[0]="$__tsh_str"
        string._ret 1
        return 0
    fi
    while :; do
        if (( __tsh_count != 0 && __tsh_n >= __tsh_count )); then
            __tsh_tail=0
            break
        fi
        if [[ "$__tsh_rest" != *"$__tsh_sep"* ]]; then
            break
        fi
        __tsh_part="${__tsh_rest%%"$__tsh_sep"*}"
        __tsh_rest="${__tsh_rest:${#__tsh_part} + ${#__tsh_sep}}"
        if [[ -n "$__tsh_part" || "$__tsh_opt" != "ExcludeEmpty" ]]; then
            __tsh_out[__tsh_n]="$__tsh_part"
            (( __tsh_n += 1 )) || :
        fi
    done
    if (( __tsh_tail )); then
        if [[ -n "$__tsh_rest" || "$__tsh_opt" != "ExcludeEmpty" ]]; then
            __tsh_out[__tsh_n]="$__tsh_rest"
            (( __tsh_n += 1 )) || :
        fi
    fi
    if [[ "$__tsh_opt" == "ExcludeLastEmpty" ]] && (( __tsh_n > 0 )) \
       && [[ -z "${__tsh_out[__tsh_n - 1]}" ]]; then
        unset '__tsh_out[__tsh_n - 1]'
        (( __tsh_n -= 1 )) || :
    fi
    string._ret "$__tsh_n"
}

string.join() {
    local sep="${1:-}"
    if (( $# > 0 )); then shift; fi
    local result="" arg first=1
    for arg in "$@"; do
        if (( first )); then
            result="$arg"
            first=0
        else
            result="$result$sep$arg"
        fi
    done
    string._ret "$result"
}

# FPC: Substring(I) = Substring(I,Length-I); Substring(I,L) = Copy(Self,I+1,L),
# with fpc_ansistr_copy's clamping (finding TSH-11).
string.substring() {
    local self="${1:-}" startIndex="${2:-}" length="${3:-}"
    kk.isInt "$startIndex" startIndex || { RESULT=""; return 1; }
    if [[ -n "$length" ]]; then
        kk.isInt "$length" length || { RESULT=""; return 1; }
    else
        length=$(( ${#self} - startIndex ))
    fi
    local __tsh_r
    string._copy "$self" $(( startIndex + 1 )) "$length"
    string._ret "$__tsh_r"
}

string.copy() {
    string._ret "${1:-}"
}

# string.copyTo SELF SOURCEINDEX DESTARRAY DESTINDEX COUNT
# Every local carries the reserved __tsh_ prefix: DESTARRAY is a caller name,
# and bash scopes locals dynamically, so an unprefixed local of the same name
# would silently swallow the writes (finding TSH-16).
string.copyTo() {
    local __tsh_self="${1:-}" __tsh_si="${2:-}" __tsh_name="${3:-}"
    local __tsh_di="${4:-}" __tsh_cnt="${5:-}" __tsh_i
    if string._badOutName "$__tsh_name"; then
        string._debug "copyTo: bad destination array name '$__tsh_name'"
        RESULT=""
        return 2
    fi
    kk.isInt "$__tsh_si" __tsh_si || { RESULT=""; return 1; }
    kk.isInt "$__tsh_di" __tsh_di || { RESULT=""; return 1; }
    kk.isInt "$__tsh_cnt" __tsh_cnt || { RESULT=""; return 1; }
    if (( __tsh_si < 0 || __tsh_di < 0 || __tsh_cnt < 0 )); then
        string._debug "copyTo: indexes and count must be non-negative"
        RESULT=""; return 1
    fi
    if (( __tsh_si + __tsh_cnt > ${#__tsh_self} )); then
        string._debug "copyTo: source range is out of bounds"
        RESULT=""; return 1
    fi
    local -n __tsh_dest="$__tsh_name"
    for (( __tsh_i = 0; __tsh_i < __tsh_cnt; __tsh_i++ )); do
        __tsh_dest[__tsh_di + __tsh_i]="${__tsh_self:__tsh_si + __tsh_i:1}"
    done
    return 0
}

# FPC AnsiQuotedStr (sysstr.inc:672): the string between two quote characters,
# every occurrence of the quote character doubled. The default quote is the
# apostrophe (QuotedStr). No fork, no lost trailing newlines (finding TSH-08).
string.quotedString() {
    local str="${1:-}" quote="${2:-}"
    if [[ -z "$quote" ]]; then
        quote="'"
    else
        quote="${quote:0:1}"
    fi
    string._ret "$quote${str//"$quote"/"$quote$quote"}$quote"
}

# FPC DeQuotedString (syshelp.inc): unchanged unless the string is at least
# two characters long AND starts and ends with the quote character; inside,
# a doubled quote collapses to one and a lone quote disappears.
string.deQuotedString() {
    local self="${1:-}" quote="${2:-}"
    if [[ -z "$quote" ]]; then
        quote="'"
    else
        quote="${quote:0:1}"
    fi
    if (( ${#self} < 2 )) || [[ "${self:0:1}" != "$quote" || "${self: -1}" != "$quote" ]]; then
        string._ret "$self"
        return 0
    fi
    local inner="${self:1:${#self}-2}"
    if [[ "$inner" != *"$quote"* ]]; then
        string._ret "$inner"
        return 0
    fi
    # Fast path: if every quote inside is part of a doubled pair, one
    # substitution is the whole answer.
    local stripped="${inner//"$quote$quote"/}"
    if [[ "$stripped" != *"$quote"* ]]; then
        string._ret "${inner//"$quote$quote"/"$quote"}"
        return 0
    fi
    # Otherwise FPC's IsQuote toggle, character by character.
    local out="" i char isQuote=0
    for (( i = 0; i < ${#inner}; i++ )); do
        char="${inner:i:1}"
        if [[ "$char" == "$quote" ]]; then
            if (( isQuote )); then
                isQuote=0
                out+="$char"
            else
                isQuote=1
            fi
        else
            isQuote=0
            out+="$char"
        fi
    done
    string._ret "$out"
}

# FPC Create(AChar,ACount) = StringOfChar — empty for a non-positive count.
string.create() {
    local char="${1:-}" count="${2:-}"
    kk.isInt "$count" count || { RESULT=""; return 1; }
    if (( count <= 0 )) || [[ -z "$char" ]]; then
        string._ret ""
        return 0
    fi
    local filler
    printf -v filler '%*s' "$count" ''
    string._ret "${filler// /"$char"}"
}

# FPC CountChar counts one Char; `${s//"$c"/}` does it in one expansion
# instead of one comparison per character (finding TSH-09).
string.countChar() {
    local self="${1:-}" char="${2:-}"
    if [[ -z "$char" ]]; then
        string._ret 0
        return 0
    fi
    local without="${self//"$char"/}"
    string._ret $(( (${#self} - ${#without}) / ${#char} ))
}

# FPC ToBoolean is StrToBool -> TryStrToBool (sysstr.inc:2075): a number is
# true when it is non-zero, otherwise the text is compared case-insensitively
# with 'True'/'False', and anything else is a conversion FAILURE (finding
# TSH-07). Failure is rc 1 + RESULT='' — distinguishable from the answer
# "false", which is rc 1 + RESULT='false'.
string.toBoolean() {
    local self="${1:-}" mantissa
    if kk.isNum "$self"; then
        mantissa="${__KK_NUM%%[eE]*}"
        if [[ -z "${mantissa//[-+.0]/}" ]]; then
            string._retBool 1
        else
            string._retBool 0
        fi
        return $?
    fi
    case "${self^^}" in
        TRUE)  string._retBool 0 ;;
        FALSE) string._retBool 1 ;;
        *)     string._debug "toBoolean: '$self' is not a boolean"
               string._fail ;;
    esac
}

# string.toCharArray STR [STARTINDEX] [LENGTH] [ARRAY]
# With ARRAY the characters go into the caller's array and RESULT holds the
# count (kcl/README.md 1.7); without it they are joined with newlines, which
# is what `$(string.toCharArray abc)` printed before P5.
string.toCharArray() {
    local __tsh_self="${1:-}" __tsh_start="${2:-0}" __tsh_len="${3:-}"
    local __tsh_name="${4:-}" __tsh_i __tsh_end __tsh_n=0 __tsh_joined=""
    kk.isInt "$__tsh_start" __tsh_start || { RESULT=""; return 1; }
    if [[ -n "$__tsh_len" ]]; then
        kk.isInt "$__tsh_len" __tsh_len || { RESULT=""; return 1; }
    else
        __tsh_len=$(( ${#__tsh_self} - __tsh_start ))
    fi
    if (( __tsh_start < 0 || __tsh_start > ${#__tsh_self} )); then
        RESULT=""; return 1
    fi
    __tsh_end=$(( __tsh_start + __tsh_len ))
    if (( __tsh_end > ${#__tsh_self} )); then __tsh_end=${#__tsh_self}; fi
    if [[ -n "$__tsh_name" ]]; then
        if string._badOutName "$__tsh_name"; then
            string._debug "toCharArray: bad output array name '$__tsh_name'"
            RESULT=""
            return 2
        fi
        local -n __tsh_out="$__tsh_name"
        __tsh_out=()
        for (( __tsh_i = __tsh_start; __tsh_i < __tsh_end; __tsh_i++ )); do
            __tsh_out[__tsh_n]="${__tsh_self:__tsh_i:1}"
            (( __tsh_n += 1 )) || :
        done
        string._ret "$__tsh_n"
        return 0
    fi
    for (( __tsh_i = __tsh_start; __tsh_i < __tsh_end; __tsh_i++ )); do
        if (( __tsh_n )); then __tsh_joined+=$'\n'; fi
        __tsh_joined+="${__tsh_self:__tsh_i:1}"
        (( __tsh_n += 1 )) || :
    done
    string._ret "$__tsh_joined"
}

# FPC ToDouble/ToExtended/ToSingle are StrToFloat = Val(trim(S)), which raises
# on anything that is not a number (finding TSH-18). The shared kk.isNum guard
# is the same grammar minus hex, and it normalises away a leading '+'.
string.toDouble() {
    local __tsh_r
    string._trimWs "${1:-}" both
    if ! kk.isNum "$__tsh_r"; then
        string._debug "toDouble: '${1:-}' is not a number"
        string._fail
        return $?
    fi
    string._ret "$__KK_NUM"
}

string.toExtended() {
    string.toDouble "${1:-}"
}

string.toSingle() {
    string.toDouble "${1:-}"
}

# FPC ToInt64 is StrToInt64, ToInteger is StrToInt (a Longint conversion).
string.toInt64() {
    local __tsh_r
    if ! string._parseInt "${1:-}" 64; then
        string._debug "toInt64: '${1:-}' is not an integer"
        string._fail
        return $?
    fi
    string._ret "$__tsh_r"
}

string.toInteger() {
    local __tsh_r
    if ! string._parseInt "${1:-}" 32; then
        string._debug "toInteger: '${1:-}' is not an integer"
        string._fail
        return $?
    fi
    string._ret "$__tsh_r"
}

# FPC's Parse overloads turn a Pascal Boolean/Integer/Extended into its string
# form. In bash the argument already IS that string, so this is the identity;
# see the README.
string.parse() {
    string._ret "${1:-}"
}

string.length() {
    local __tsh_s="${1:-}"
    string._ret "${#__tsh_s}"
}

# FPC's Chars[] property has no bounds check (Self[AIndex+1]); reading past
# the end is an error here: rc 1 + RESULT='' (kcl/README.md 1.2).
string.chars() {
    local self="${1:-}" index="${2:-}"
    kk.isInt "$index" index || { RESULT=""; return 1; }
    if (( index < 0 || index >= ${#self} )); then
        string._debug "chars: index $index is outside '$self'"
        string._fail
        return $?
    fi
    string._ret "${self:index:1}"
}

# FPC GetHashCode is fphash (syshelp.inc): h := int32((h shl 5) - h) xor c,
# signed 32-bit, over the BYTES of the string. This port walks CODE POINTS, so
# it agrees with FPC on ASCII and differs on anything else — a deliberate,
# documented deviation (finding TSH-19): the alternative would make the hash
# depend on the encoding of the same text.
string.getHashCode() {
    local str="${1:-}" hash=0 i ord
    for (( i = 0; i < ${#str}; i++ )); do
        printf -v ord '%d' "'${str:i:1}"
        hash=$(( (((hash << 5) - hash) ^ ord) & 0xFFFFFFFF ))
        if (( hash > 2147483647 )); then
            hash=$(( hash - 4294967296 ))
        fi
    done
    string._ret "$hash"
}

# BASH printf semantics, not Pascal Format(): the directives are printf's,
# Pascal's argument indices (%0:s) are not supported, and printf REUSES the
# format while arguments remain. printf's own diagnostic is captured rather
# than leaked with a kklass line number, and a rejected format or argument is
# rc 1 + RESULT='' (finding TSH-15).
#
# SECURITY / trust boundary: the format is interpreted for directives and
# width. Do NOT pass untrusted input as the format — bash printf has no %n, so
# it cannot corrupt memory, but a hostile format can still spin on a huge width.
string.format() {
    local __tsh_fmt="${1:-}" __tsh_out
    if (( $# > 0 )); then shift; fi
    if printf -v __tsh_out -- "$__tsh_fmt" "$@" 2>/dev/null; then
        string._ret "$__tsh_out"
    else
        string._debug "format: printf rejected the format or an argument"
        string._fail
        return $?
    fi
}

# Finalize: extract the bodies above into the `string` class and generate the
# static dispatchers (thin, capture-free — a class without static variables).
# The class is named `string`, so the public API stays `string.<Method>` and
# the kklass metadata array `string_class_static_methods` is populated.
build string
