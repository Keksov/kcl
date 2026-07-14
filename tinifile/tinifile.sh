#!/bin/bash

# ===========================================================================
# tinifile — a bash port of FPC fcl-base inifiles.pp:
#            TIniFile (eager persist) + TMemIniFile : TIniFile (cached).
#
# Source of truth: packages/fcl-base/src/inifiles.pp — TCustomIniFile
# (:159-218, FOLDED into TIniFile here: an abstract bash base would be pure
# dispatch tax), TIniFile (:222-259), TMemIniFile (:261-269), constants
# (:279-283: [ ] / '=' / ';' / '\'), CharToBool :285. The FILE-FORMAT SPEC is
# the FPC READER (FillSectionList :1033) — S1-S12 pinned at P0 in PLAN.md §3.
# FPC fpcunit seed: packages/fcl-base/tests/utcinifile.pp (2 Bool tests,
# mined at P3). Plan/ledger: kcl/tinifile/{PLAN.md,tinifile_ledger.json}.
#
# ---- The class split (FPC-verbatim) ----------------------------------------
# BOTH classes are memory-backed. TIniFile has cache_updates=false: EVERY
# Write*/Delete(hit)/Erase(hit) flushes to disk (MaybeUpdateFile :1397).
# TMemIniFile sets cache_updates=true: changes only mark dirty; the file is
# written on UpdateFile — or on DESTROY while dirty (FPC :1024 flushes
# dirty+cached destructors, eating errors — D7 compat). Also FPC-verbatim:
# TIniFile.Create AUTO-ADDS ifoStripQuotes; TMemIniFile does NOT (:967-970).
#
# ---- Storage (P0-frozen; PLAN §2.2 REVISED) ---------------------------------
# A direct mirror of FPC's TIniFileSectionList as parallel SPARSE indexed
# arrays (FPC's own lookups are linear for-loops; config scale):
#   ${inst}_secnames  slot -> section name IN ORDER; may be a comment-section
#                     (text starts ';') or the empty name ([]).
#   ${inst}_kident /  row  -> key ident / value / owning section SLOT, in
#   ${inst}_kvalue /          order; comment-keys (ident ';…', value ''),
#   ${inst}_kowner            invalid rows (ident '', value = raw line).
# Deletion = unset the slot/row (order-preserving sparse holes; iteration via
# ${!arr[@]}). Duplicates/order/comments/[]-section come free; first-match
# lookups mirror FPC's Break. Lookup case: ${x,,}-normalized unless
# ifoCaseSensitive; slots keep ORIGINAL first-appearance case.
#
# ---- Options (ctor tokens + later via option members) -----------------------
# Supported: ifoStripComments ifoStripInvalid ifoEscapeLineFeeds
# ifoCaseSensitive ifoStripQuotes ifoStringBoolean (alias
# ifoWriteStringBoolean, FPC :272 — normalized to ifoStringBoolean).
# ifoFormatSettingsActive follows the date family -> NOT supported (rc 1,
# debug msg). Unknown token -> rc 1 (instance still valid with the tokens
# accepted so far; house token convention).
#
# ---- Return contract ---------------------------------------------------------
# Instance funcs return via RESULT (kk._return on every explicit-return path —
# the tdictionary trailer trap); instance procs are rc-only (a proc body's
# RESULT does NOT survive dispatch — kklass _invoke rollback, pinned at
# tobjectlist P1). Array-filling members are FUNCs (RESULT=count) that fill
# caller-named namerefs — CALL THEM DIRECTLY ($() discards the fills).
# Read* NEVER fail (default-based, rc 0); failures are structural only
# (PLAN §2.7 validation hardening: rc 1 + debug msg).
# RESERVED NAMES: never pass caller arrays named __tif_* (nameref shadowing:
# a callee-local of the same name would shadow the caller's array — the exact
# bug class fixed at P2, where _fill's internal line buffer shadowed
# _updateNow's; internals now use per-function names __tif_fl/__tif_ul/__tif_gl).
# ===========================================================================

# Re-source guard.
if [[ -n "$_TINIFILE_SOURCED" ]]; then
    return
fi
declare -g _TINIFILE_SOURCED=1

TINIFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TINIFILE_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# TIniFile — member surface frozen at P0; bodies land per phase:
#   P1 load+read core, P2 write core+persistence, P3 typed accessors+options.
# ---------------------------------------------------------------------------
class TIniFile
    public
        constructor Create
        destructor  Destroy
        var file_name
        var options
        var cache_updates
        var dirty
        func ReadString          # P1  sec id default -> RESULT
        func SectionExists       # P1  sec            -> rc 0/1
        func ValueExists         # P1  sec id         -> rc 0/1
        func ReadSection         # P1  sec outArr     -> RESULT=count (idents)
        func ReadSections        # P1  outArr         -> RESULT=count (names)
        func ReadSectionValues   # P1  sec outArr [svo...] -> RESULT=count
        func ReadSectionRaw      # P1  sec outArr     -> RESULT=count
        proc WriteString         # P2  sec id value
        proc DeleteKey           # P2  sec id
        proc EraseSection        # P2  sec
        proc UpdateFile          # P2
        func ReadInteger         # P3  sec id default -> RESULT
        proc WriteInteger        # P3
        func ReadInt64           # P3  (= ReadInteger; bash arith is 64-bit)
        proc WriteInt64          # P3
        func ReadBool            # P3  sec id default(0/1) -> RESULT 0/1
        proc WriteBool           # P3
        func ReadFloat           # P3  string-preserving (PLAN §2.6)
        proc WriteFloat          # P3
        proc SetBoolStringValues # P3  true|false v1 [v2 ...]
end

class TMemIniFile : TIniFile
    public
        constructor Create
        proc Clear               # P2
        func GetStrings          # P2  outArr -> RESULT=count
        proc SetStrings          # P2  inArr
        proc Rename              # P2  newName [reload]
end

# ---- plain helpers (no kklass dispatch; dynamic scope) -----------------------

# Trim leading/trailing whitespace (fork-free) -> __tif_trim.
TIniFile._trim() {
    local __s="$1"
    __s="${__s#"${__s%%[![:space:]]*}"}"
    __s="${__s%"${__s##*[![:space:]]}"}"
    __tif_trim="$__s"
}

# Lookup normalization: identity under ifoCaseSensitive, else ${x,,}
# (ASCII-guaranteed; unicode follows the locale — documented). Reads the
# in-scope instance var `options`. -> __tif_norm
TIniFile._norm() {
    if [[ " $options " == *" ifoCaseSensitive "* ]]; then
        __tif_norm="$1"
    else
        __tif_norm="${1,,}"
    fi
}

# First-wins section lookup (FPC SectionByName :536 verbatim, incl. the guard:
# empty and comment names NEVER match). -> __tif_slot (-1 = not found).
# Caller declares: local __tif_slot __tif_norm __tif_n2
TIniFile._findSection() {
    __tif_slot=-1
    local __tif_name="$1"
    [[ -z "$__tif_name" || "${__tif_name:0:1}" == ";" ]] && return 1
    TIniFile._norm "$__tif_name"; local __tif_want="$__tif_norm"
    local -n __tif_sn="${__inst__}_secnames"
    local __tif_i
    for __tif_i in "${!__tif_sn[@]}"; do
        local __tif_cand="${__tif_sn[__tif_i]}"
        [[ -z "$__tif_cand" || "${__tif_cand:0:1}" == ";" ]] && continue
        TIniFile._norm "$__tif_cand"
        if [[ "$__tif_norm" == "$__tif_want" ]]; then
            __tif_slot=$__tif_i
            return 0
        fi
    done
    return 1
}

# First-wins key lookup within a section slot (FPC KeyByName :460 verbatim,
# same guard). -> __tif_row (-1 = not found).
TIniFile._findKey() {
    __tif_row=-1
    local __tif_slotwant="$1" __tif_id="$2"
    [[ -z "$__tif_id" || "${__tif_id:0:1}" == ";" ]] && return 1
    TIniFile._norm "$__tif_id"; local __tif_want="$__tif_norm"
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_ko="${__inst__}_kowner"
    local __tif_j
    for __tif_j in "${!__tif_ki[@]}"; do
        [[ "${__tif_ko[__tif_j]}" != "$__tif_slotwant" ]] && continue
        local __tif_cand="${__tif_ki[__tif_j]}"
        [[ -z "$__tif_cand" || "${__tif_cand:0:1}" == ";" ]] && continue
        TIniFile._norm "$__tif_cand"
        if [[ "$__tif_norm" == "$__tif_want" ]]; then
            __tif_row=$__tif_j
            return 0
        fi
    done
    return 1
}

# Strip matching quotes per FPC ReadString :1136 (len>1, "..." or '...').
# -> __tif_unq
TIniFile._unquote() {
    local __v="$1" __l=${#1}
    __tif_unq="$__v"
    if (( __l > 1 )); then
        local __c="${__v:0:1}"
        if [[ ( "$__c" == '"' || "$__c" == "'" ) && "${__v: -1}" == "$__c" ]]; then
            __tif_unq="${__v:1:__l-2}"
        fi
    fi
}

# Parse a list of RAW lines (array name in $1) into the instance storage —
# FPC FillSectionList :1033 verbatim: optional \-join (ifoEscapeLineFeeds),
# per-line Trim, comment-sections/comment-keys, [] sections, invalid rows,
# keys-before-section dropped, StripComments/StripInvalid honored.
# Assumes storage arrays exist and are EMPTY (caller clears).
TIniFile._fill() {
    local -n __tif_in="$1"
    local -n __tif_sn="${__inst__}_secnames"
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_kv="${__inst__}_kvalue"
    local -n __tif_ko="${__inst__}_kowner"
    local __tif_strip_c=0 __tif_strip_i=0
    [[ " $options " == *" ifoStripComments "* ]] && __tif_strip_c=1
    [[ " $options " == *" ifoStripInvalid "* ]] && __tif_strip_i=1

    # ifoEscapeLineFeeds: join '\'-terminated RAW lines (FPC RemoveBackslashes
    # :1039 — forward-accumulator equivalent; a trailing '\' on the LAST line
    # stays, as in FPC).
    local -a __tif_fl=()
    if [[ " $options " == *" ifoEscapeLineFeeds "* ]]; then
        local __tif_acc="" __tif_have=0 __tif_l
        for __tif_l in "${__tif_in[@]}"; do
            if (( __tif_have )); then
                __tif_acc+="$__tif_l"
            else
                __tif_acc="$__tif_l"; __tif_have=1
            fi
            if [[ "${__tif_acc: -1}" == "\\" && ${#__tif_acc} -gt 0 ]]; then
                __tif_acc="${__tif_acc%\\}"
                continue
            fi
            __tif_fl+=( "$__tif_acc" ); __tif_have=0; __tif_acc=""
        done
        (( __tif_have )) && __tif_fl+=( "$__tif_acc" )
    else
        __tif_fl=( "${__tif_in[@]}" )
    fi

    local __tif_cursec=-1 __tif_nextsec=${#__tif_sn[@]} __tif_nextrow=${#__tif_ki[@]}
    local __tif_trim __tif_line __tif_len
    for __tif_line in "${__tif_fl[@]}"; do
        TIniFile._trim "$__tif_line"; __tif_line="$__tif_trim"
        __tif_len=${#__tif_line}
        (( __tif_len == 0 )) && continue                    # blank: dropped (S2)
        if [[ "${__tif_line:0:1}" == ";" && $__tif_cursec -lt 0 ]]; then
            # comment before any section -> comment-SECTION (S2)
            if (( ! __tif_strip_c )); then
                __tif_sn[__tif_nextsec]="$__tif_line"
                (( __tif_nextsec++ ))
            fi
            continue
        fi
        if [[ "${__tif_line:0:1}" == "[" && "${__tif_line: -1}" == "]" ]]; then
            # regular section: name = inside brackets, verbatim (S4)
            __tif_sn[__tif_nextsec]="${__tif_line:1:__tif_len-2}"
            __tif_cursec=$__tif_nextsec
            (( __tif_nextsec++ ))
            continue
        fi
        (( __tif_cursec < 0 )) && continue                   # key before section: dropped (S4)
        if [[ "${__tif_line:0:1}" == ";" ]]; then
            # comment within a section -> comment-KEY (S2)
            if (( ! __tif_strip_c )); then
                __tif_ki[__tif_nextrow]="$__tif_line"
                __tif_kv[__tif_nextrow]=""
                __tif_ko[__tif_nextrow]=$__tif_cursec
                (( __tif_nextrow++ ))
            fi
            continue
        fi
        if [[ "$__tif_line" != *"="* ]]; then
            # invalid line (no '='): ident='', value=line (S12)
            if (( ! __tif_strip_i )); then
                __tif_ki[__tif_nextrow]=""
                __tif_kv[__tif_nextrow]="$__tif_line"
                __tif_ko[__tif_nextrow]=$__tif_cursec
                (( __tif_nextrow++ ))
            fi
            continue
        fi
        # regular key: split at the FIRST '=', trim both parts (S8)
        TIniFile._trim "${__tif_line%%=*}"; local __tif_id="$__tif_trim"
        TIniFile._trim "${__tif_line#*=}";  local __tif_val="$__tif_trim"
        __tif_ki[__tif_nextrow]="$__tif_id"
        __tif_kv[__tif_nextrow]="$__tif_val"
        __tif_ko[__tif_nextrow]=$__tif_cursec
        (( __tif_nextrow++ ))
    done
}

# Load the instance's file into storage (S1: missing file -> empty, rc 0).
# Fork-free read: while IFS= read -r || [[ -n ]] handles a missing final
# newline; one trailing CR stripped per line (Windows reality); UTF-8 BOM
# stripped from line 1 (tolerated, never written).
TIniFile._load() {
    [[ -z "$file_name" || ! -f "$file_name" ]] && return 0
    local -a __tif_raw=()
    local __tif_line __tif_first=1
    while IFS= read -r __tif_line || [[ -n "$__tif_line" ]]; do
        __tif_line="${__tif_line%$'\r'}"
        if (( __tif_first )); then
            __tif_line="${__tif_line#$'\xef\xbb\xbf'}"
            __tif_first=0
        fi
        __tif_raw+=( "$__tif_line" )
    done < "$file_name"
    TIniFile._fill __tif_raw
}

# ---- P2 plain helpers ---------------------------------------------------------

# Compose the file lines from storage into nameref $1 (FPC UpdateFile
# :1358-1375 / GetStrings :1465-1492). $2 = mode: 'updatefile' inserts a blank
# line between sections EXCEPT after comment-sections; 'getstrings' inserts it
# after EVERY section (the one-detail FPC divergence, pinned). Writer quirk
# pinned verbatim: an invalid row (ident='') emits '=value' (:1372).
TIniFile._compose() {
    local -n __tif_out="$1"; __tif_out=()
    local __tif_mode="$2"
    local -n __tif_sn="${__inst__}_secnames"
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_kv="${__inst__}_kvalue"
    local -n __tif_ko="${__inst__}_kowner"
    local -a __tif_slots=( "${!__tif_sn[@]}" )
    local __tif_n=${#__tif_slots[@]} __tif_x __tif_i __tif_j
    for (( __tif_x = 0; __tif_x < __tif_n; __tif_x++ )); do
        __tif_i=${__tif_slots[__tif_x]}
        local __tif_name="${__tif_sn[__tif_i]}"
        if [[ "${__tif_name:0:1}" == ";" ]]; then
            __tif_out+=( "$__tif_name" )                 # comment-section
        else
            __tif_out+=( "[${__tif_name}]" )
        fi
        for __tif_j in "${!__tif_ki[@]}"; do
            [[ "${__tif_ko[__tif_j]}" != "$__tif_i" ]] && continue
            local __tif_id="${__tif_ki[__tif_j]}"
            if [[ "${__tif_id:0:1}" == ";" ]]; then
                __tif_out+=( "$__tif_id" )               # comment-key
            else
                __tif_out+=( "${__tif_id}=${__tif_kv[__tif_j]}" )
            fi
        done
        if (( __tif_x < __tif_n - 1 )); then
            if [[ "$__tif_mode" == "getstrings" || "${__tif_name:0:1}" != ";" ]]; then
                __tif_out+=( "" )
            fi
        fi
    done
}

# Perform the actual write (FPC UpdateFile :1349): compose -> ensure target
# dir exists (S9; mkdir -p only when missing — a fork only then) -> printf to
# a tmp in the SAME dir -> mv over the target (the one regular fork). On any
# failure: rc 1, MEMORY KEPT, dirty unchanged (FPC raises; we refuse quietly,
# PLAN 2.7). Success: re-parse the composed lines (FPC :1390 normalization)
# and clear dirty. Empty file_name: normalize + clear dirty, no file touched.
TIniFile._updateNow() {
    local -a __tif_ul
    TIniFile._compose __tif_ul updatefile
    if [[ -n "$file_name" ]]; then
        local __tif_dir="${file_name%/*}"
        if [[ "$__tif_dir" != "$file_name" && -n "$__tif_dir" && ! -d "$__tif_dir" ]]; then
            mkdir -p "$__tif_dir" 2>/dev/null || {
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot create '$__tif_dir'" >&2
                return 1
            }
        fi
        local __tif_tmp="${file_name}.tmp.$$"
        if (( ${#__tif_ul[@]} > 0 )); then
            printf '%s\n' "${__tif_ul[@]}" > "$__tif_tmp" 2>/dev/null || {
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot write '$__tif_tmp'" >&2
                return 1
            }
        else
            : > "$__tif_tmp" 2>/dev/null || {
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot write '$__tif_tmp'" >&2
                return 1
            }
        fi
        mv -f "$__tif_tmp" "$file_name" 2>/dev/null || {
            rm -f "$__tif_tmp" 2>/dev/null
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot replace '$file_name'" >&2
            return 1
        }
    fi
    # normalization re-parse (clears comment-of-invalid asymmetries exactly as
    # FPC does after SaveToFile)
    local -n __tif_sn="${__inst__}_secnames"; __tif_sn=()
    local -n __tif_ki="${__inst__}_kident";  __tif_ki=()
    local -n __tif_kv="${__inst__}_kvalue";  __tif_kv=()
    local -n __tif_ko="${__inst__}_kowner";  __tif_ko=()
    TIniFile._fill __tif_ul
    dirty=false
    return 0
}

# MaybeUpdateFile (:1397): cached -> mark dirty; eager -> write now.
TIniFile._maybeUpdate() {
    if [[ "$cache_updates" == "true" ]]; then
        dirty=true
        return 0
    fi
    TIniFile._updateNow
}

# Write-path validation (PLAN 2.7 hardening — refuse what FPC would corrupt):
# $1 kind (sec|ident|value), $2 text. rc 0 ok / 1 reject.
TIniFile._validate() {
    local __tif_v="$2"
    case "$1" in
        sec|ident)
            [[ -z "$__tif_v" ]] && return 1                      # FPC no-ops; we say why
            [[ "${__tif_v:0:1}" == ";" ]] && return 1            # would round-trip as comment
            [[ "$1" == "ident" && "$__tif_v" == *"="* ]] && return 1
            ;;&
        *)
            [[ "$__tif_v" == *$'\n'* || "$__tif_v" == *$'\r'* ]] && return 1
            ;;
    esac
    return 0
}

# ---- plain helpers (no kklass dispatch) --------------------------------------

# Parse ctor option tokens into a normalized space-joined list. Dynamic-scope
# OUT: __tif_opts (normalized), __tif_bad (first bad token or ''). Accepts the
# 6 supported options; ifoWriteStringBoolean normalizes to ifoStringBoolean.
TIniFile._parseOptions() {
    __tif_opts=""; __tif_bad=""
    local __tif_t
    for __tif_t in "$@"; do
        case "$__tif_t" in
            ifoStripComments|ifoStripInvalid|ifoEscapeLineFeeds|ifoCaseSensitive|ifoStripQuotes|ifoStringBoolean)
                [[ " $__tif_opts " == *" $__tif_t "* ]] || __tif_opts+="${__tif_opts:+ }$__tif_t" ;;
            ifoWriteStringBoolean)   # FPC alias (:272)
                [[ " $__tif_opts " == *" ifoStringBoolean "* ]] || __tif_opts+="${__tif_opts:+ }ifoStringBoolean" ;;
            *)
                __tif_bad="$__tif_t"; return 1 ;;
        esac
    done
    return 0
}

# ---- method bodies -----------------------------------------------------------

TIniFile.Create() {
    # Create <fileName> [optionToken ...]. FPC :967: TIniFile (and ONLY
    # TIniFile — `if not (self is TMemIniFile)`) auto-adds ifoStripQuotes;
    # cache_updates=false (eager). Missing file at Create = empty ini (S1);
    # the actual file LOAD lands in P1 — storage starts empty either way.
    local __tif_class_var="${__inst__}_class"
    file_name="${1:-}"
    shift 2>/dev/null || :
    cache_updates=false
    dirty=false
    local __tif_opts __tif_bad
    TIniFile._parseOptions "$@"
    local __tif_rc=$?
    options="$__tif_opts"
    if [[ "${!__tif_class_var}" != "TMemIniFile" ]]; then
        [[ " $options " == *" ifoStripQuotes "* ]] || options+="${options:+ }ifoStripQuotes"
    fi
    # per-instance storage (PLAN §2.2): sparse parallel arrays
    declare -ga "${__inst__}_secnames=()"
    declare -ga "${__inst__}_kident=()"
    declare -ga "${__inst__}_kvalue=()"
    declare -ga "${__inst__}_kowner=()"
    declare -ga "${__inst__}_booltrue=()"
    declare -ga "${__inst__}_boolfalse=()"
    # S1: load the file if it exists (missing -> empty ini, rc untouched);
    # runs even after a bad token — the instance is valid with the accepted
    # options (house convention: token error != broken object).
    TIniFile._load
    if (( __tif_rc != 0 )); then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.Create: unknown option token '$__tif_bad'" >&2
        return 1
    fi
    return 0
}

TIniFile.Destroy() {
    # FPC :1024: flush when Dirty AND CacheUpdates, EATING errors (D7 compat,
    # bug 19046) — so a dirty TMemIniFile auto-saves on destroy. Then tear
    # down the per-instance storage (kklass only removes ${inst}_data).
    if [[ "$dirty" == "true" && "$cache_updates" == "true" ]]; then
        TIniFile._updateNow || :
    fi
    unset "${__inst__}_secnames" "${__inst__}_kident" "${__inst__}_kvalue" \
          "${__inst__}_kowner" "${__inst__}_booltrue" "${__inst__}_boolfalse"
    return 0
}

TMemIniFile.Create() {
    # FPC :1447: inherited (WITHOUT the StripQuotes auto-add — the parent body
    # checks the instance class), then CacheUpdates := True.
    inherited
    local __tif_rc=$?
    cache_updates=true
    return $__tif_rc
}

# ---- P3 plain helpers ---------------------------------------------------------

# Fetch the resolved string value for sec/id -> __tif_get (rc 0 found / 1 miss).
# Applies StripQuotes exactly like ReadString — FPC's typed accessors
# (ReadInteger/ReadBool/ReadFloat) all read THROUGH ReadString, so they inherit
# quote stripping. Single source of truth for both ReadString and the typed
# family. Caller declares: local __tif_get __tif_slot __tif_row __tif_norm __tif_unq
TIniFile._get() {
    if TIniFile._findSection "$1" && TIniFile._findKey "$__tif_slot" "$2"; then
        local -n __tif_kv="${__inst__}_kvalue"
        local __tif_v="${__tif_kv[__tif_row]}"
        if [[ " $options " == *" ifoStripQuotes "* ]]; then
            TIniFile._unquote "$__tif_v"; __tif_v="$__tif_unq"
        fi
        __tif_get="$__tif_v"
        return 0
    fi
    __tif_get=""
    return 1
}

# Parse a value string per FPC StrToIntDef/val() -> __tif_int (rc 0 valid /
# 1 invalid). Grammar (S5): optional +/- sign, then decimal | $hex | 0x/0X hex |
# &octal | %binary. Leading-zero decimal stays DECIMAL (10# guard — NOT bash
# C-octal). Digit classes validated by regex BEFORE the arithmetic so base#N is
# always well-formed. NB: no 32-bit clamp (Integer==Int64 here, documented);
# >63-bit magnitudes wrap like bash — a documented edge, not FPC's overflow->Default.
TIniFile._toInt() {
    local __s="$1" __neg=0
    __tif_int=0
    [[ -z "$__s" ]] && return 1
    case "${__s:0:1}" in
        +) __s="${__s:1}" ;;
        -) __neg=1; __s="${__s:1}" ;;
    esac
    [[ -z "$__s" ]] && return 1
    local __lit
    if [[ "${__s:0:1}" == '$' ]]; then
        [[ "${__s:1}" =~ ^[0-9A-Fa-f]+$ ]] || return 1
        __lit="16#${__s:1}"
    elif [[ "${__s:0:2}" == "0x" || "${__s:0:2}" == "0X" ]]; then
        [[ "${__s:2}" =~ ^[0-9A-Fa-f]+$ ]] || return 1
        __lit="16#${__s:2}"
    elif [[ "${__s:0:1}" == '&' ]]; then
        [[ "${__s:1}" =~ ^[0-7]+$ ]] || return 1
        __lit="8#${__s:1}"
    elif [[ "${__s:0:1}" == '%' ]]; then
        [[ "${__s:1}" =~ ^[01]+$ ]] || return 1
        __lit="2#${__s:1}"
    else
        [[ "$__s" =~ ^[0-9]+$ ]] || return 1
        __lit="10#${__s}"
    fi
    if (( __neg )); then __tif_int=$(( -1 * (__lit) )); else __tif_int=$(( __lit )); fi
    return 0
}

# ---- P1 members: read core ----------------------------------------------------

TIniFile.ReadString() {
    # sec id default -> RESULT (rc 0 always — Read* never fails, S: default-
    # based API). StripQuotes strips matching "..."/'...' at READ time only
    # (FPC :1136; TIniFile has the option auto-added, TMemIniFile not).
    local __tif_get __tif_slot __tif_row __tif_norm __tif_unq
    if TIniFile._get "$1" "$2"; then
        kk._return "$__tif_get"
    else
        kk._return "${3:-}"
    fi
    return 0
}

TIniFile.SectionExists() {
    # rc 0 exists / 1 not; RESULT mirrors as 1/0 (FPC Boolean).
    local __tif_slot __tif_norm
    if TIniFile._findSection "$1"; then
        kk._return "1"; return 0
    fi
    kk._return "0"; return 1
}

TIniFile.ValueExists() {
    # rc 0 exists / 1 not; RESULT 1/0 (FPC :844 — section then key).
    local __tif_slot __tif_row __tif_norm
    if TIniFile._findSection "$1" && TIniFile._findKey "$__tif_slot" "$2"; then
        kk._return "1"; return 0
    fi
    kk._return "0"; return 1
}

TIniFile.ReadSection() {
    # sec outArr -> fills idents of the section IN ORDER, comments excluded;
    # invalid rows contribute '' entries (FPC :1211: IsComment('') is false).
    # RESULT=count; rc 0. CALL DIRECTLY ($() discards the fill).
    local __tif_sec="$1"
    local -n __tif_out="$2"; __tif_out=()
    local __tif_slot __tif_norm
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_ko="${__inst__}_kowner"
        local __tif_j
        for __tif_j in "${!__tif_ki[@]}"; do
            [[ "${__tif_ko[__tif_j]}" != "$__tif_slot" ]] && continue
            [[ "${__tif_ki[__tif_j]:0:1}" == ";" ]] && continue
            __tif_out+=( "${__tif_ki[__tif_j]}" )
        done
    fi
    kk._return "${#__tif_out[@]}"
    return 0
}

TIniFile.ReadSections() {
    # outArr -> all section names IN ORDER, comment-sections excluded; the
    # []-section contributes '' (FPC :1248). RESULT=count; rc 0.
    local -n __tif_out="$1"; __tif_out=()
    local -n __tif_sn="${__inst__}_secnames"
    local __tif_i
    for __tif_i in "${!__tif_sn[@]}"; do
        [[ "${__tif_sn[__tif_i]:0:1}" == ";" ]] && continue
        __tif_out+=( "${__tif_sn[__tif_i]}" )
    done
    kk._return "${#__tif_out[@]}"
    return 0
}

TIniFile.ReadSectionValues() {
    # sec outArr [svoIncludeComments] [svoIncludeInvalid] [svoIncludeQuotes]
    # FPC :1255 (default AOptions=[svoIncludeInvalid] — pass tokens to change):
    # comments included if svoIncludeComments OR ifoStripComments; invalid if
    # svoIncludeInvalid OR ifoStripInvalid; quotes stripped when StripQuotes
    # and NOT svoIncludeQuotes. Lines: comment -> the comment text; invalid ->
    # the raw value; normal -> Ident=Value. RESULT=count; rc 0.
    local __tif_sec="$1"
    local -n __tif_out="$2"; __tif_out=()
    shift 2
    local __tif_inc_c=0 __tif_inc_i=0 __tif_inc_q=0 __tif_t
    for __tif_t in "$@"; do
        case "$__tif_t" in
            svoIncludeComments) __tif_inc_c=1 ;;
            svoIncludeInvalid)  __tif_inc_i=1 ;;
            svoIncludeQuotes)   __tif_inc_q=1 ;;
        esac
    done
    (( $# == 0 )) && __tif_inc_i=1                      # FPC default
    [[ " $options " == *" ifoStripComments "* ]] && __tif_inc_c=1
    [[ " $options " == *" ifoStripInvalid "* ]] && __tif_inc_i=1
    local __tif_do_q=0
    [[ " $options " == *" ifoStripQuotes "* ]] && (( ! __tif_inc_q )) && __tif_do_q=1
    local __tif_slot __tif_norm __tif_unq
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_kv="${__inst__}_kvalue"
        local -n __tif_ko="${__inst__}_kowner"
        local __tif_j
        for __tif_j in "${!__tif_ki[@]}"; do
            [[ "${__tif_ko[__tif_j]}" != "$__tif_slot" ]] && continue
            local __tif_id="${__tif_ki[__tif_j]}" __tif_val="${__tif_kv[__tif_j]}"
            if [[ -z "$__tif_id" ]]; then
                (( __tif_inc_i )) || continue
            fi
            if [[ "${__tif_id:0:1}" == ";" ]]; then
                (( __tif_inc_c )) || continue
                __tif_out+=( "$__tif_id" )
                continue
            fi
            if (( __tif_do_q )); then
                TIniFile._unquote "$__tif_val"; __tif_val="$__tif_unq"
            fi
            if [[ -n "$__tif_id" ]]; then
                __tif_out+=( "${__tif_id}=${__tif_val}" )
            else
                __tif_out+=( "$__tif_val" )
            fi
        done
    fi
    kk._return "${#__tif_out[@]}"
    return 0
}

TIniFile.ReadSectionRaw() {
    # sec outArr -> Ident=Value per row, bare value for invalid rows, comments
    # INCLUDED as their text (FPC :1218: rows with Ident<>'' -> Ident=Value —
    # comment rows have Ident=';…' so they emit ';…='? NO: FPC emits
    # Ident+Separator+Value for ANY non-empty ident INCLUDING comment idents,
    # i.e. ';c=' — pinned verbatim, quirk and all). RESULT=count; rc 0.
    local __tif_sec="$1"
    local -n __tif_out="$2"; __tif_out=()
    local __tif_slot __tif_norm
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_kv="${__inst__}_kvalue"
        local -n __tif_ko="${__inst__}_kowner"
        local __tif_j
        for __tif_j in "${!__tif_ki[@]}"; do
            [[ "${__tif_ko[__tif_j]}" != "$__tif_slot" ]] && continue
            if [[ -n "${__tif_ki[__tif_j]}" ]]; then
                __tif_out+=( "${__tif_ki[__tif_j]}=${__tif_kv[__tif_j]}" )
            else
                __tif_out+=( "${__tif_kv[__tif_j]}" )
            fi
        done
    fi
    kk._return "${#__tif_out[@]}"
    return 0
}
# ---- P2 members: write core + persistence ------------------------------------

TIniFile.WriteString() {
    # sec id value. FPC :1174: update the FIRST matching key IN PLACE (stored
    # ident keeps its ORIGINAL first-appearance case) or append a new key to
    # the section; a missing section is appended at the END. Validation per
    # PLAN 2.7 (rc 1, nothing stored, no flush — divergence: FPC silently
    # no-ops empty names yet still calls MaybeUpdateFile). Then MaybeUpdate.
    local __tif_sec="$1" __tif_id="$2" __tif_val="$3"
    if ! TIniFile._validate sec "$__tif_sec" || ! TIniFile._validate ident "$__tif_id" \
       || ! TIniFile._validate value "$__tif_val"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.WriteString: invalid section/ident/value" >&2
        return 1
    fi
    local __tif_slot __tif_row __tif_norm
    local -n __tif_sn="${__inst__}_secnames"
    if ! TIniFile._findSection "$__tif_sec"; then
        __tif_sn+=( "$__tif_sec" )
        local -a __tif_idxs=( "${!__tif_sn[@]}" )
        __tif_slot=${__tif_idxs[-1]}
    fi
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_kv="${__inst__}_kvalue"
    local -n __tif_ko="${__inst__}_kowner"
    if TIniFile._findKey "$__tif_slot" "$__tif_id"; then
        __tif_kv[__tif_row]="$__tif_val"
    else
        __tif_ki+=( "$__tif_id" )
        local -a __tif_kidxs=( "${!__tif_ki[@]}" )
        local __tif_new=${__tif_kidxs[-1]}
        __tif_kv[__tif_new]="$__tif_val"
        __tif_ko[__tif_new]=$__tif_slot
    fi
    TIniFile._maybeUpdate
}

TIniFile.DeleteKey() {
    # S7: silent when section/key missing; flush(Maybe) ONLY on an actual
    # deletion (FPC :1331-1347).
    local __tif_slot __tif_row __tif_norm
    if TIniFile._findSection "$1" && TIniFile._findKey "$__tif_slot" "$2"; then
        unset "${__inst__}_kident[$__tif_row]" \
              "${__inst__}_kvalue[$__tif_row]" \
              "${__inst__}_kowner[$__tif_row]"
        TIniFile._maybeUpdate
    fi
    return 0
}

TIniFile.EraseSection() {
    # S7: silent when missing; found -> the whole section object dies (its
    # comment-keys and invalid rows with it) + MaybeUpdate (FPC :1318-1329).
    local __tif_slot __tif_norm
    if TIniFile._findSection "$1"; then
        local -n __tif_ko="${__inst__}_kowner"
        local __tif_j
        for __tif_j in "${!__tif_ko[@]}"; do
            if [[ "${__tif_ko[__tif_j]}" == "$__tif_slot" ]]; then
                unset "${__inst__}_kident[$__tif_j]" \
                      "${__inst__}_kvalue[$__tif_j]" \
                      "${__inst__}_kowner[$__tif_j]"
            fi
        done
        unset "${__inst__}_secnames[$__tif_slot]"
        TIniFile._maybeUpdate
    fi
    return 0
}

TIniFile.UpdateFile() {
    # Explicit flush (works for both classes; TMemIniFile's normal way out).
    TIniFile._updateNow
}
# ---- P3 members: typed accessors + options -----------------------------------

TIniFile.ReadInteger() {
    # sec id default -> RESULT. FPC :690 = StrToIntDef(ReadString(...),Default):
    # value read THROUGH ReadString (quotes stripped), parsed by val() grammar;
    # any non-conforming value -> Default. rc 0 always.
    local __tif_get __tif_slot __tif_row __tif_norm __tif_unq __tif_int
    if TIniFile._get "$1" "$2" && TIniFile._toInt "$__tif_get"; then
        kk._return "$__tif_int"
    else
        kk._return "${3:-0}"
    fi
    return 0
}

# ReadInt64 == ReadInteger here — bash arithmetic is 64-bit, so the two FPC
# paths (Longint 32-bit / Int64 64-bit) collapse to one (documented: no 32-bit
# clamp). Self-contained via the plain helpers (a member can't call a sibling
# MEMBER by name — build unsets the global; and dispatching a func loses the
# return value, kklass _invoke rollback). Reuses _get/_toInt = the shared path.
TIniFile.ReadInt64() {
    local __tif_get __tif_slot __tif_row __tif_norm __tif_unq __tif_int
    if TIniFile._get "$1" "$2" && TIniFile._toInt "$__tif_get"; then
        kk._return "$__tif_int"
    else
        kk._return "${3:-0}"
    fi
    return 0
}

TIniFile.WriteInteger() {
    # sec id value -> WriteString(IntToStr(value)) (FPC :696). We normalize
    # through _toInt so the STORED form is canonical decimal (matches
    # IntToStr): WriteInteger sec id '$FF' stores '255'. Non-integer value
    # rejected (rc 1) rather than silently storing garbage.
    local __tif_int
    if ! TIniFile._toInt "$3"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.WriteInteger: '$3' is not an integer" >&2
        return 1
    fi
    $this.WriteString "$1" "$2" "$__tif_int"
}

# WriteInt64 == WriteInteger (proc: no return-value concern). Self-contained
# for the same build-unsets-siblings reason; WriteString via $this DISPATCH.
TIniFile.WriteInt64() {
    local __tif_int
    if ! TIniFile._toInt "$3"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.WriteInt64: '$3' is not an integer" >&2
        return 1
    fi
    $this.WriteString "$1" "$2" "$__tif_int"
}

TIniFile.SetBoolStringValues() {
    # true|false v1 [v2 ...]  (FPC :654 SetBoolStringValues(ABoolValue,Values)):
    # REPLACE the whole true- or false-strings list. Empty list clears it.
    local __tif_which="$1"; shift
    local __tif_arr
    case "$__tif_which" in
        true)  __tif_arr="${__inst__}_booltrue" ;;
        false) __tif_arr="${__inst__}_boolfalse" ;;
        *)
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.SetBoolStringValues: first arg must be true|false" >&2
            return 1 ;;
    esac
    local -n __tif_bs="$__tif_arr"
    __tif_bs=( "$@" )
    return 0
}

TIniFile.ReadBool() {
    # sec id default(0|1) -> RESULT 0/1 (FPC :720). Cascade over the value read
    # THROUGH ReadString (empty when absent):
    #   (1) if either BoolStrings list is non-empty -> case-INSENSITIVE
    #       membership (FPC IndexOfString uses CompareText); true-list wins,
    #       then false-list, else Default.
    #   (2) elif ifoStringBoolean -> case-insensitive 'true'/'false' (SameText),
    #       else Default.
    #   (3) else CharToBool: first char == '1'.
    #   empty value -> Default (the whole cascade is guarded by s>'' ).
    local __tif_get __tif_slot __tif_row __tif_norm __tif_unq
    local __tif_def="${3:-0}"
    TIniFile._get "$1" "$2" || __tif_get=""
    local __tif_s="$__tif_get"
    if [[ -z "$__tif_s" ]]; then
        kk._return "$__tif_def"; return 0
    fi
    local -n __tif_bt="${__inst__}_booltrue"
    local -n __tif_bf="${__inst__}_boolfalse"
    if (( ${#__tif_bt[@]} > 0 || ${#__tif_bf[@]} > 0 )); then
        local __tif_x
        for __tif_x in "${__tif_bt[@]}"; do
            [[ "${__tif_x,,}" == "${__tif_s,,}" ]] && { kk._return "1"; return 0; }
        done
        for __tif_x in "${__tif_bf[@]}"; do
            [[ "${__tif_x,,}" == "${__tif_s,,}" ]] && { kk._return "0"; return 0; }
        done
        kk._return "$__tif_def"; return 0
    fi
    if [[ " $options " == *" ifoStringBoolean "* ]]; then
        if [[ "${__tif_s,,}" == "true" ]]; then kk._return "1"; return 0; fi
        if [[ "${__tif_s,,}" == "false" ]]; then kk._return "0"; return 0; fi
        kk._return "$__tif_def"; return 0
    fi
    if [[ "${__tif_s:0:1}" == "1" ]]; then kk._return "1"; else kk._return "0"; fi
    return 0
}

TIniFile.WriteBool() {
    # sec id value(truthy) (FPC :746). value: accept 1/true/yes/on (any case)
    # and 0/false/no/off/'' as the two poles; anything else -> rc 1. Output
    # string: ifoStringBoolean -> BoolTrueStrings[0]//'true' / BoolFalseStrings
    # [0]//'false'; else '1'/'0' (BoolToChar).
    local __tif_sec="$1" __tif_id="$2" __tif_raw="$3" __tif_b
    case "${__tif_raw,,}" in
        1|true|yes|on)   __tif_b=1 ;;
        0|false|no|off|"") __tif_b=0 ;;
        *)
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.WriteBool: '$3' is not a boolean" >&2
            return 1 ;;
    esac
    local __tif_out
    if [[ " $options " == *" ifoStringBoolean "* ]]; then
        if (( __tif_b )); then
            local -n __tif_bt="${__inst__}_booltrue"
            __tif_out="${__tif_bt[0]:-true}"
        else
            local -n __tif_bf="${__inst__}_boolfalse"
            __tif_out="${__tif_bf[0]:-false}"
        fi
    else
        (( __tif_b )) && __tif_out="1" || __tif_out="0"
    fi
    $this.WriteString "$__tif_sec" "$__tif_id" "$__tif_out"
}

TIniFile.ReadFloat() {
    # sec id default -> RESULT. STRING-PRESERVING (PLAN §2.6): the value is
    # shape-validated as a float literal and passed through VERBATIM (no Double
    # round-trip — FPC would canonicalize '1.50'->'1.5'; we keep '1.50', a
    # documented divergence). Non-float or absent -> Default. Shape: optional
    # sign, digits with optional single '.', optional exponent e/E[+/-]digits;
    # a bare '.' or empty mantissa is invalid.
    local __tif_get __tif_slot __tif_row __tif_norm __tif_unq
    local __tif_def="${3:-0}"
    if TIniFile._get "$1" "$2" \
       && [[ "$__tif_get" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]; then
        kk._return "$__tif_get"
    else
        kk._return "$__tif_def"
    fi
    return 0
}

TIniFile.WriteFloat() {
    # sec id value -> WriteString(value) string-preserving: shape-validate,
    # store the LITERAL (no canonicalization). Non-float -> rc 1.
    if [[ ! "$3" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.WriteFloat: '$3' is not a float" >&2
        return 1
    fi
    $this.WriteString "$1" "$2" "$3"
}

# ---- P2 TMemIniFile members ---------------------------------------------------

TMemIniFile.Clear() {
    # FPC :1460: section list cleared; dirty NOT touched (pinned).
    local -n __tif_sn="${__inst__}_secnames"; __tif_sn=()
    local -n __tif_ki="${__inst__}_kident";  __tif_ki=()
    local -n __tif_kv="${__inst__}_kvalue";  __tif_kv=()
    local -n __tif_ko="${__inst__}_kowner";  __tif_ko=()
    return 0
}

TMemIniFile.GetStrings() {
    # outArr -> the composed lines, GetStrings flavor (blank line after EVERY
    # section — the pinned one-detail divergence from UpdateFile, FPC :1486).
    # RESULT=count. CALL DIRECTLY.
    local -n __tif_gout="$1"
    local -a __tif_gl
    TIniFile._compose __tif_gl getstrings
    __tif_gout=( "${__tif_gl[@]}" )
    kk._return "${#__tif_gout[@]}"
    return 0
}

TMemIniFile.SetStrings() {
    # inArr -> replace the content by re-parsing the lines (FPC :1502
    # FillSectionList); dirty NOT touched (pinned).
    local -n __tif_sn="${__inst__}_secnames"; __tif_sn=()
    local -n __tif_ki="${__inst__}_kident";  __tif_ki=()
    local -n __tif_kv="${__inst__}_kvalue";  __tif_kv=()
    local -n __tif_ko="${__inst__}_kowner";  __tif_ko=()
    TIniFile._fill "$1"
    return 0
}

TMemIniFile.Rename() {
    # newName [true|false] (FPC :1494: FFileName:=new; Reload -> re-read from
    # the NEW file, missing -> empty; no write happens).
    file_name="$1"
    if [[ "${2:-false}" == "true" ]]; then
        local -n __tif_sn="${__inst__}_secnames"; __tif_sn=()
        local -n __tif_ki="${__inst__}_kident";  __tif_ki=()
        local -n __tif_kv="${__inst__}_kvalue";  __tif_kv=()
        local -n __tif_ko="${__inst__}_kowner";  __tif_ko=()
        TIniFile._load
    fi
    return 0
}

# Finalize the classes (parent first).
build TIniFile
build TMemIniFile
