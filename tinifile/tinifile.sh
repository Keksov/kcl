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
# ---- Storage (P0-frozen; PLAN §2.2 REVISED; P8 indexes added for T6) --------
# A direct mirror of FPC's TIniFileSectionList as parallel SPARSE indexed
# arrays (FPC's own lookups are linear for-loops; config scale):
#   ${inst}_secnames  slot -> section name IN ORDER; may be a comment-section
#                     (text starts ';') or the empty name ([]).
#   ${inst}_kident /  row  -> key ident / value / owning section SLOT, in
#   ${inst}_kvalue /          order; comment-keys (ident ';…', value ''),
#   ${inst}_kowner            invalid rows (ident '', value = raw line).
# Deletion = unset the slot/row (order-preserving sparse holes; iteration via
# ${!arr[@]}). Duplicates/order/comments/[]-section come free; first-match
# lookups mirror FPC's Break. Slots keep ORIGINAL first-appearance case.
#
# Four derived structures make the lookups linear instead of quadratic (review
# finding T6) WITHOUT changing the model — every one of them is a cache of what
# the four arrays above already say, rebuilt wholesale by _fill/_reset:
#   ${inst}_snorm   slot -> ${name,,}   the case-insensitive section key
#   ${inst}_knorm   row  -> ${ident,,}  the case-insensitive key ident
#   ${inst}_srows   slot -> " r1 r2 … " the section's OWN rows, in order, so a
#                   lookup never walks the rows of other sections
#   ${inst}_sblob   slot -> "\nid\nid\n…" the same idents as one string: a MISS
#                   (the append path) is one substring test instead of a loop
#   ${inst}_secbrk  slot -> 1 when the section came from a `[name]` line, so a
#                   `[;x]` section composes back WITH its brackets (T3)
#   ${inst}_ctr     (next free row, next free slot) — appending must not
#                   materialise "${!arr[@]}" to learn the new index
# The folds are stored UNCONDITIONALLY lowercase; ifoCaseSensitive is honoured
# by comparing the raw arrays instead, so flipping `options` after load cannot
# leave a stale cache behind.
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
# RESERVED NAMES for an output/input array (validated since P8 — rc 2, nothing
# written): __tif_* (nameref shadowing: a callee-local of the same name would
# shadow the caller's array — the exact bug class fixed at P2, where _fill's
# internal line buffer shadowed _updateNow's), __kk_*/__KK_*, RESULT, REPLY,
# IFS, this, __inst__, __class__, state, the four INSTANCE VARIABLES
# (file_name, options, cache_updates, dirty — inside a body they are namerefs
# into ${inst}_data), the instance's own storage arrays, and any name that is
# not a plain identifier or is an associative array.
# ===========================================================================

# Re-source guard.
if [[ -n "${_TINIFILE_SOURCED:-}" ]]; then
    return
fi
declare -g _TINIFILE_SOURCED=1

# Character semantics are part of this unit's contract (D6, kcl/README.md §1.6):
# the case-insensitive section/key lookup is `${x,,}`, and under the C locale
# that leaves a multi-byte letter alone, so `[Café]` would not answer to `CAFÉ`.
# An empty environment means the C locale; an explicit one is never overridden.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

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

# Validate the name of a caller array before any nameref is bound (T13).
# kcl/README.md §1.7: a plain identifier, outside the framework's reserved set,
# outside this unit's `__tif_*` space, and never one of the four INSTANCE
# VARIABLES — inside a member body `dirty`/`options`/`file_name`/`cache_updates`
# are namerefs into `${inst}_data`, so `I.ReadSections dirty` used to bind the
# output to the instance's own state. rc 1 here, rc 2 at the call site.
TIniFile._outName() {
    local __tif_n="${1:-}"
    case "$__tif_n" in
        ""|__tif_*|__kk_*|__KK_*|RESULT|REPLY|IFS|this|__inst__|__class__) return 1 ;;
        file_name|options|cache_updates|dirty|state)                       return 1 ;;
    esac
    case "$__tif_n" in
        "${__inst__}_secnames"|"${__inst__}_snorm"|"${__inst__}_secbrk"| \
        "${__inst__}_srows"|"${__inst__}_sblob"| \
        "${__inst__}_kident"|"${__inst__}_knorm"|"${__inst__}_kvalue"|"${__inst__}_kowner"| \
        "${__inst__}_booltrue"|"${__inst__}_boolfalse"|"${__inst__}_ctr"| \
        "${__inst__}_data"|"${__inst__}_class") return 1 ;;
    esac
    [[ "$__tif_n" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || return 1
    # An ASSOCIATIVE target would silently receive the keys 0,1,2… — refuse it.
    # `${ref@a}` aborts under `set -u` whenever the target has no value yet (a
    # fresh name, or the empty `declare -A m=()` this check exists for), so the
    # option is switched off for this one expansion. `local -` makes $- local to
    # the function, restored on return — no fork, no leak into the caller.
    local -
    set +u
    local -n __tif_probe="$__tif_n" 2>/dev/null || return 1
    [[ "${__tif_probe@a}" == *A* ]] && return 1
    return 0
}

# Clear the whole per-instance store (both counters back to 0). Used by every
# caller that used to clear the four arrays by hand.
TIniFile._reset() {
    local -n __tif_r1="${__inst__}_secnames"; __tif_r1=()
    local -n __tif_r2="${__inst__}_snorm";    __tif_r2=()
    local -n __tif_r3="${__inst__}_secbrk";   __tif_r3=()
    local -n __tif_r4="${__inst__}_srows";    __tif_r4=()
    local -n __tif_rb="${__inst__}_sblob";   __tif_rb=()
    local -n __tif_r5="${__inst__}_kident";   __tif_r5=()
    local -n __tif_r6="${__inst__}_knorm";    __tif_r6=()
    local -n __tif_r7="${__inst__}_kvalue";   __tif_r7=()
    local -n __tif_r8="${__inst__}_kowner";   __tif_r8=()
    local -n __tif_r9="${__inst__}_ctr";      __tif_r9=( 0 0 )
}

# First-wins section lookup (FPC SectionByName :521-540 verbatim, incl. the
# guard: empty and comment names NEVER match). -> __tif_slot (-1 = not found).
# Caller declares: local __tif_slot
#
# T6: the ${x,,} fold used to run through a helper FUNCTION per candidate. The
# case-insensitive form is now precomputed in ${inst}_snorm (ALWAYS lowercase,
# never conditional, so that flipping `options` after load cannot make the cache
# lie), and the case-sensitive form compares the stored name directly.
TIniFile._findSection() {
    __tif_slot=-1
    local __tif_name="$1"
    [[ -z "$__tif_name" || "${__tif_name:0:1}" == ";" ]] && return 1
    local __tif_i __tif_cand
    if [[ " $options " == *" ifoCaseSensitive "* ]]; then
        local -n __tif_sn="${__inst__}_secnames"
        for __tif_i in "${!__tif_sn[@]}"; do
            __tif_cand="${__tif_sn[__tif_i]}"
            [[ -z "$__tif_cand" || "${__tif_cand:0:1}" == ";" ]] && continue
            if [[ "$__tif_cand" == "$__tif_name" ]]; then
                __tif_slot=$__tif_i
                return 0
            fi
        done
    else
        local -n __tif_sq="${__inst__}_snorm"
        local __tif_want="${__tif_name,,}"
        for __tif_i in "${!__tif_sq[@]}"; do
            __tif_cand="${__tif_sq[__tif_i]}"
            [[ -z "$__tif_cand" || "${__tif_cand:0:1}" == ";" ]] && continue
            if [[ "$__tif_cand" == "$__tif_want" ]]; then
                __tif_slot=$__tif_i
                return 0
            fi
        done
    fi
    return 1
}

# First-wins key lookup within a section slot (FPC KeyByName :445-469 verbatim,
# same guard). -> __tif_row (-1 = not found).
#
# T6: this used to walk the rows of EVERY section and call a helper per row, so
# a lookup cost O(all keys) and appending N keys cost O(N^2). It now walks only
# ${inst}_srows[slot] — the section's own row numbers, in insertion order — and
# compares against the precomputed fold. Empty and comment idents cannot match
# (the argument is guarded above), so no per-row guard is needed.
TIniFile._findKey() {
    __tif_row=-1
    local __tif_slotwant="$1" __tif_id="$2"
    [[ -z "$__tif_id" || "${__tif_id:0:1}" == ";" ]] && return 1
    (( __tif_slotwant < 0 )) && return 1
    # Fast NEGATIVE, and it comes FIRST: ${inst}_sblob[slot] holds the section's
    # folded idents as "\nid\nid\n…", and one anchored substring test settles a
    # miss in C instead of one shell iteration per row. A miss is the case that
    # made appending quadratic — every WriteString of a NEW key scans the whole
    # section before appending — so nothing O(rows) may happen above this line,
    # not even copying the row list out of the array. Folding is a function, so
    # a folded miss implies a raw miss: the probe is valid for the
    # case-SENSITIVE branch too, and a hit still goes through the loop, which is
    # what decides first-match.
    local -n __tif_sx="${__inst__}_sblob"
    local __tif_lc="${__tif_id,,}"
    [[ "${__tif_sx[__tif_slotwant]:-}" == *$'\n'"$__tif_lc"$'\n'* ]] || return 1
    local -n __tif_sr="${__inst__}_srows"
    local __tif_list="${__tif_sr[__tif_slotwant]:-}"
    local IFS=' '
    local __tif_j
    if [[ " $options " == *" ifoCaseSensitive "* ]]; then
        local -n __tif_ki="${__inst__}_kident"
        for __tif_j in $__tif_list; do
            if [[ "${__tif_ki[__tif_j]}" == "$__tif_id" ]]; then
                __tif_row=$__tif_j
                return 0
            fi
        done
    else
        local -n __tif_kn="${__inst__}_knorm"
        local __tif_want="$__tif_lc"
        for __tif_j in $__tif_list; do
            if [[ "${__tif_kn[__tif_j]}" == "$__tif_want" ]]; then
                __tif_row=$__tif_j
                return 0
            fi
        done
    fi
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
    local -n __tif_sq="${__inst__}_snorm"
    local -n __tif_sb="${__inst__}_secbrk"
    local -n __tif_sr="${__inst__}_srows"
    local -n __tif_sx="${__inst__}_sblob"
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_kn="${__inst__}_knorm"
    local -n __tif_kv="${__inst__}_kvalue"
    local -n __tif_ko="${__inst__}_kowner"
    local -n __tif_ct="${__inst__}_ctr"
    local __tif_strip_c=0 __tif_strip_i=0
    [[ " $options " == *" ifoStripComments "* ]] && __tif_strip_c=1
    [[ " $options " == *" ifoStripInvalid "* ]] && __tif_strip_i=1

    # ifoEscapeLineFeeds: join '\'-terminated RAW lines (FPC RemoveBackslashes
    # :1022-1044 — forward-accumulator equivalent of FPC's `downto` walk).
    # T9: FPC starts at Count-2, so the LAST line is never a join SOURCE and its
    # trailing '\' survives verbatim. The accumulator strips the backslash
    # before continuing, so an unterminated chain has to put it back.
    local -a __tif_fl=()
    if [[ " $options " == *" ifoEscapeLineFeeds "* ]]; then
        local __tif_acc="" __tif_have=0 __tif_l
        for __tif_l in "${__tif_in[@]}"; do
            if (( __tif_have )); then
                __tif_acc+="$__tif_l"
            else
                __tif_acc="$__tif_l"; __tif_have=1
            fi
            if [[ "${__tif_acc: -1}" == "\\" ]]; then
                __tif_acc="${__tif_acc%\\}"
                continue
            fi
            __tif_fl+=( "$__tif_acc" ); __tif_have=0; __tif_acc=""
        done
        if (( __tif_have )); then __tif_fl+=( "${__tif_acc}\\" ); fi
    else
        __tif_fl=( "${__tif_in[@]}" )
    fi

    local __tif_cursec=-1 __tif_nextsec=${__tif_ct[1]} __tif_nextrow=${__tif_ct[0]} __tif_lc
    local __tif_trim __tif_line __tif_len
    for __tif_line in "${__tif_fl[@]}"; do
        TIniFile._trim "$__tif_line"; __tif_line="$__tif_trim"
        __tif_len=${#__tif_line}
        if (( __tif_len == 0 )); then continue; fi                    # blank: dropped (S2)
        if [[ "${__tif_line:0:1}" == ";" && $__tif_cursec -lt 0 ]]; then
            # comment before any section -> comment-SECTION (S2). FPC :1059-1066
            # assigns oSection here, so the keys that follow BELONG to the
            # comment-section instead of being dropped; with ifoStripComments no
            # section is created and they are dropped, exactly as here.
            if (( ! __tif_strip_c )); then
                __tif_sn[__tif_nextsec]="$__tif_line"
                __tif_sq[__tif_nextsec]="${__tif_line,,}"
                __tif_sb[__tif_nextsec]=0
                __tif_sr[__tif_nextsec]=" "
                __tif_sx[__tif_nextsec]=$'\n'
                __tif_cursec=$__tif_nextsec
                (( __tif_nextsec += 1 )) || :
            fi
            continue
        fi
        if [[ "${__tif_line:0:1}" == "[" && "${__tif_line: -1}" == "]" ]]; then
            # regular section: name = inside brackets, verbatim (S4). The
            # bracketed origin is remembered (T3) so that a `[;x]` line composes
            # back as `[;x]` and does not turn into a comment that orphans its
            # keys on the next read.
            __tif_line="${__tif_line:1:__tif_len-2}"
            __tif_sn[__tif_nextsec]="$__tif_line"
            __tif_sq[__tif_nextsec]="${__tif_line,,}"
            __tif_sb[__tif_nextsec]=1
            __tif_sr[__tif_nextsec]=" "
            __tif_sx[__tif_nextsec]=$'\n'
            __tif_cursec=$__tif_nextsec
            (( __tif_nextsec += 1 )) || :
            continue
        fi
        if (( __tif_cursec < 0 )); then continue; fi                   # key before section: dropped (S4)
        if [[ "${__tif_line:0:1}" == ";" ]]; then
            # comment within a section -> comment-KEY (S2)
            if (( ! __tif_strip_c )); then
                __tif_lc="${__tif_line,,}"
                __tif_ki[__tif_nextrow]="$__tif_line"
                __tif_kn[__tif_nextrow]="$__tif_lc"
                __tif_kv[__tif_nextrow]=""
                __tif_ko[__tif_nextrow]=$__tif_cursec
                __tif_sr[__tif_cursec]+="$__tif_nextrow "
                __tif_sx[__tif_cursec]+="$__tif_lc"$'\n'
                (( __tif_nextrow += 1 )) || :
            fi
            continue
        fi
        if [[ "$__tif_line" != *"="* ]]; then
            # invalid line (no '='): ident='', value=line (S12)
            if (( ! __tif_strip_i )); then
                __tif_ki[__tif_nextrow]=""
                __tif_kn[__tif_nextrow]=""
                __tif_kv[__tif_nextrow]="$__tif_line"
                __tif_ko[__tif_nextrow]=$__tif_cursec
                __tif_sr[__tif_cursec]+="$__tif_nextrow "
                __tif_sx[__tif_cursec]+=$'\n'
                (( __tif_nextrow += 1 )) || :
            fi
            continue
        fi
        # regular key: split at the FIRST '=', trim both parts (S8)
        TIniFile._trim "${__tif_line%%=*}"; local __tif_id="$__tif_trim"
        TIniFile._trim "${__tif_line#*=}";  local __tif_val="$__tif_trim"
        __tif_lc="${__tif_id,,}"
        __tif_ki[__tif_nextrow]="$__tif_id"
        __tif_kn[__tif_nextrow]="$__tif_lc"
        __tif_kv[__tif_nextrow]="$__tif_val"
        __tif_ko[__tif_nextrow]=$__tif_cursec
        __tif_sr[__tif_cursec]+="$__tif_nextrow "
        __tif_sx[__tif_cursec]+="$__tif_lc"$'\n'
        (( __tif_nextrow += 1 )) || :
    done
    __tif_ct[0]=$__tif_nextrow
    __tif_ct[1]=$__tif_nextsec
}

# Load the instance's file into storage (S1: missing file -> empty, rc 0).
# Fork-free read: while IFS= read -r || [[ -n ]] handles a missing final
# newline; one trailing CR stripped per line (Windows reality); UTF-8 BOM
# stripped from line 1 (tolerated, never written).
TIniFile._load() {
    local __tif_fn="${file_name//\\//}"        # T12, same rule as _updateNow
    [[ -z "$__tif_fn" || ! -f "$__tif_fn" ]] && return 0
    local -a __tif_raw=()
    local __tif_line __tif_first=1
    while IFS= read -r __tif_line || [[ -n "$__tif_line" ]]; do
        __tif_line="${__tif_line%$'\r'}"
        if (( __tif_first )); then
            __tif_line="${__tif_line#$'\xef\xbb\xbf'}"
            __tif_first=0
        fi
        __tif_raw+=( "$__tif_line" )
    done < "$__tif_fn"
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
    local __tif_mode="${2:-}"
    local -n __tif_sn="${__inst__}_secnames"
    local -n __tif_sb="${__inst__}_secbrk"
    local -n __tif_sr="${__inst__}_srows"
    local -n __tif_ki="${__inst__}_kident"
    local -n __tif_kv="${__inst__}_kvalue"
    local -a __tif_slots=( "${!__tif_sn[@]}" )
    local __tif_n=${#__tif_slots[@]} __tif_x __tif_i __tif_j
    local IFS=' '
    for (( __tif_x = 0; __tif_x < __tif_n; __tif_x++ )); do
        __tif_i=${__tif_slots[__tif_x]}
        local __tif_name="${__tif_sn[__tif_i]}"
        # T3: only a section that really CAME from a comment line composes back
        # as one; `[;x]` keeps its brackets, so its keys are not orphaned.
        if [[ "${__tif_name:0:1}" == ";" && "${__tif_sb[__tif_i]:-1}" != "1" ]]; then
            __tif_out+=( "$__tif_name" )                 # comment-section
        else
            __tif_out+=( "[${__tif_name}]" )
        fi
        for __tif_j in ${__tif_sr[__tif_i]:-}; do
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
        # T12: `\` is a directory separator here (D5 — the tpath parsers accept
        # both on input). The instance variable keeps the caller's text; every
        # filesystem operation below uses the normalised copy, because cygwin
        # bash does NOT translate `\` inside a POSIX path and would otherwise
        # create the directory and then fail to write into it.
        local __tif_fn="${file_name//\\//}"
        # T1: a directory is not a target. `mv tmp DIR` moves the temp file INTO
        # it and reports success, so the flush "succeeded" with no ini written.
        # FPC's SaveToFile raises here, leaving memory and Dirty untouched.
        if [[ -d "$__tif_fn" ]]; then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: '$file_name' is a directory" >&2
            return 1
        fi
        # T8: FPC's SaveToFile fails on a read-only target; `mv` over it happily
        # succeeds and resets the mode to the temp file's.
        if [[ -e "$__tif_fn" && ! -w "$__tif_fn" ]]; then
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: '$file_name' is not writable" >&2
            return 1
        fi
        local __tif_dir="${__tif_fn%/*}"
        if [[ "$__tif_dir" != "$__tif_fn" && -n "$__tif_dir" && ! -d "$__tif_dir" ]]; then
            mkdir -p -- "$__tif_dir" 2>/dev/null || {
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot create '$__tif_dir'" >&2
                return 1
            }
        fi
        # T7: the redirection creates the temp file BEFORE printf runs, so every
        # failure branch below has to remove it, not just the mv one.
        local __tif_tmp="${__tif_fn}.tmp.$$"
        if (( ${#__tif_ul[@]} > 0 )); then
            printf '%s\n' "${__tif_ul[@]}" > "$__tif_tmp" 2>/dev/null || {
                rm -f -- "$__tif_tmp" 2>/dev/null
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot write '$__tif_tmp'" >&2
                return 1
            }
        else
            : > "$__tif_tmp" 2>/dev/null || {
                rm -f -- "$__tif_tmp" 2>/dev/null
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot write '$__tif_tmp'" >&2
                return 1
            }
        fi
        mv -f -- "$__tif_tmp" "$__tif_fn" 2>/dev/null || {
            rm -f -- "$__tif_tmp" 2>/dev/null
            [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "Error: TIniFile.UpdateFile: cannot replace '$file_name'" >&2
            return 1
        }
    fi
    # normalization re-parse (clears comment-of-invalid asymmetries exactly as
    # FPC does after SaveToFile)
    TIniFile._reset
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

# Write-path validation (PLAN 2.7 / R6 hybrid hardening — refuse on WRITE what
# the FPC READER would reinterpret): $1 kind (sec|ident|value|pair), $2 text,
# $3 the value when $1 is `pair`. rc 0 ok / 1 reject.
TIniFile._validate() {
    local __tif_v="${2:-}"
    case "$1" in
        sec|ident)
            [[ -z "$__tif_v" ]] && return 1                      # FPC no-ops; we say why
            [[ "${__tif_v:0:1}" == ";" ]] && return 1            # would round-trip as comment
            [[ "$1" == "ident" && "$__tif_v" == *"="* ]] && return 1
            ;;&
        value)
            # T10: with ifoEscapeLineFeeds the reader joins a line that ends in
            # `\` with the next one (FPC RemoveBackslashes), so `C:\App\` would
            # swallow the following key. FPC keeps such a value only when it
            # happens to land on the LAST line, which the composer never
            # guarantees.
            if [[ " $options " == *" ifoEscapeLineFeeds "* && "${__tif_v: -1}" == "\\" ]]; then
                return 1
            fi
            ;;&
        pair)
            # T2: the composed line is `ident=value`; if it starts with `[` and
            # ends with `]` the reader (inifiles.pp:1069) takes it for a SECTION
            # header — the key disappears and the keys after it migrate into the
            # bogus section. An empty value ends the line in `=`, which is safe.
            [[ "${__tif_v:0:1}" == "[" && "${3:-}" == *"]" ]] && return 1
            return 0
            ;;
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
    declare -ga "${__inst__}_snorm=()"
    declare -ga "${__inst__}_secbrk=()"
    declare -ga "${__inst__}_srows=()"
    declare -ga "${__inst__}_sblob=()"
    declare -ga "${__inst__}_kident=()"
    declare -ga "${__inst__}_knorm=()"
    declare -ga "${__inst__}_kvalue=()"
    declare -ga "${__inst__}_kowner=()"
    declare -ga "${__inst__}_ctr=(0 0)"
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
    unset "${__inst__}_secnames" "${__inst__}_snorm" "${__inst__}_secbrk" \
          "${__inst__}_srows" "${__inst__}_sblob" "${__inst__}_kident" \
          "${__inst__}_knorm" "${__inst__}_kvalue" "${__inst__}_kowner" \
          "${__inst__}_ctr" "${__inst__}_booltrue" "${__inst__}_boolfalse"
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
# family. Caller declares: local __tif_get __tif_slot __tif_row __tif_unq
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
    # InitVal step 1: skip leading blanks and TABs (`s[code] in [' ',#9]`).
    while [[ "${__s:0:1}" == " " || "${__s:0:1}" == $'\t' ]]; do __s="${__s:1}"; done
    # step 2: sign.
    case "${__s:0:1}" in
        +) __s="${__s:1}" ;;
        -) __neg=1; __s="${__s:1}" ;;
    esac
    [[ -z "$__s" ]] && return 1
    # step 3: base prefix. `x`/`X` is a prefix in its OWN right, not only after
    # a `0` — that is the InitVal case list, and it is why `x1F` is 31.
    local __base=10
    case "${__s:0:1}" in
        '$'|x|X) __base=16; __s="${__s:1}" ;;
        '%')     __base=2;  __s="${__s:1}" ;;
        '&')     __base=8;  __s="${__s:1}" ;;
        0)  if [[ "${__s:1:1}" == "x" || "${__s:1:1}" == "X" ]]; then
                __base=16; __s="${__s:2}"
            fi ;;
    esac
    [[ -z "$__s" ]] && return 1
    # step 4: strip leading zeros, but never the last character (FPC's
    # `while (code < length(s))`), so "0" and "000" stay a valid zero.
    while [[ ${#__s} -gt 1 && "${__s:0:1}" == "0" ]]; do __s="${__s:1}"; done
    # Digit classes are validated BEFORE the arithmetic, so base#N is always
    # well-formed, and the MAGNITUDE is validated too: fpc_Val_SInt_ShortStr
    # (sstrings.inc:1141-1195) reports Code<>0 on overflow and StrToIntDef then
    # returns the Default — it does not wrap. Equal-length digit strings compare
    # numerically under a plain string comparison, so no bignum is needed.
    local __over=0
    case $__base in
        16) [[ "$__s" =~ ^[0-9A-Fa-f]+$ ]] || return 1
            (( ${#__s} > 16 )) && __over=1 ;;
        8)  [[ "$__s" =~ ^[0-7]+$ ]] || return 1
            if (( ${#__s} > 22 )) || { (( ${#__s} == 22 )) && [[ "$__s" > "1777777777777777777777" ]]; }; then
                __over=1
            fi ;;
        2)  [[ "$__s" =~ ^[01]+$ ]] || return 1
            (( ${#__s} > 64 )) && __over=1 ;;
        *)  [[ "$__s" =~ ^[0-9]+$ ]] || return 1
            local __lim="9223372036854775807"
            (( __neg )) && __lim="9223372036854775808"
            if (( ${#__s} > 19 )) || { (( ${#__s} == 19 )) && [[ "$__s" > "$__lim" ]]; }; then
                __over=1
            fi ;;
    esac
    if (( __over )); then return 1; fi
    if (( __base == 10 )); then
        if (( __neg )); then
            # -2^63 has no positive counterpart; assign the literal.
            if [[ "$__s" == "9223372036854775808" ]]; then
                __tif_int="-9223372036854775808"
            else
                __tif_int=$(( -1 * 10#$__s ))
            fi
        else
            __tif_int=$(( 10#$__s ))
        fi
    else
        # Non-decimal literals are accepted up to MaxUIntValue and reinterpreted
        # as a signed Int64 (`ValSInt(Temp)`), which is exactly what bash's
        # 64-bit arithmetic does: $FFFFFFFFFFFFFFFF is -1.
        __tif_int=$(( ${__base}#$__s ))
        if (( __neg )); then __tif_int=$(( -1 * __tif_int )); fi
    fi
    return 0
}

# ---- P1 members: read core ----------------------------------------------------

TIniFile.ReadString() {
    # sec id default -> RESULT (rc 0 always — Read* never fails, S: default-
    # based API). StripQuotes strips matching "..."/'...' at READ time only
    # (FPC :1136; TIniFile has the option auto-added, TMemIniFile not).
    local __tif_get __tif_slot __tif_row __tif_unq
    if TIniFile._get "$1" "$2"; then
        kk._return "$__tif_get"
    else
        kk._return "${3:-}"
    fi
    return 0
}

TIniFile.SectionExists() {
    # rc 0 exists / 1 not; RESULT mirrors as 1/0 (FPC Boolean).
    #
    # T4: FPC is `Assigned(S) and not S.Empty` (:670-676) and Empty (:483-497)
    # walks the key list asking IsComment(Ident) — so a section with no keys, or
    # with comment keys ONLY, does not exist, while a section holding an INVALID
    # row does (IsComment('') is False, :288). The section is still listed by
    # ReadSections and still readable; only this predicate changes.
    local __tif_slot
    if TIniFile._findSection "$1"; then
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_ki="${__inst__}_kident"
        local IFS=' ' __tif_j __tif_id
        for __tif_j in ${__tif_sr[__tif_slot]:-}; do
            __tif_id="${__tif_ki[__tif_j]}"
            if [[ -z "$__tif_id" || "${__tif_id:0:1}" != ";" ]]; then
                kk._return "1"; return 0
            fi
        done
    fi
    kk._return "0"; return 1
}

TIniFile.ValueExists() {
    # rc 0 exists / 1 not; RESULT 1/0 (FPC :827-835 — section then key).
    local __tif_slot __tif_row
    if TIniFile._findSection "$1" && TIniFile._findKey "$__tif_slot" "$2"; then
        kk._return "1"; return 0
    fi
    kk._return "0"; return 1
}

TIniFile.ReadSection() {
    # sec outArr -> fills idents of the section IN ORDER, comments excluded;
    # invalid rows contribute '' entries (FPC :1211: IsComment('') is false).
    # RESULT=count; rc 0. CALL DIRECTLY ($() discards the fill).
    if ! TIniFile._outName "${2:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.ReadSection: bad output array name '${2:-}'" >&2
        kk._return ""
        return 2
    fi
    local __tif_sec="$1"
    local -n __tif_out="$2"; __tif_out=()
    local __tif_slot
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_ki="${__inst__}_kident"
        local IFS=' ' __tif_j
        for __tif_j in ${__tif_sr[__tif_slot]:-}; do
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
    if ! TIniFile._outName "${1:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.ReadSections: bad output array name '${1:-}'" >&2
        kk._return ""
        return 2
    fi
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
    if ! TIniFile._outName "${2:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.ReadSectionValues: bad output array name '${2:-}'" >&2
        kk._return ""
        return 2
    fi
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
    if (( $# == 0 )); then __tif_inc_i=1; fi                      # FPC default
    [[ " $options " == *" ifoStripComments "* ]] && __tif_inc_c=1
    [[ " $options " == *" ifoStripInvalid "* ]] && __tif_inc_i=1
    local __tif_do_q=0
    [[ " $options " == *" ifoStripQuotes "* ]] && (( ! __tif_inc_q )) && __tif_do_q=1
    local __tif_slot __tif_unq
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_kv="${__inst__}_kvalue"
        local IFS=' ' __tif_j
        for __tif_j in ${__tif_sr[__tif_slot]:-}; do
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
    if ! TIniFile._outName "${2:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.ReadSectionRaw: bad output array name '${2:-}'" >&2
        kk._return ""
        return 2
    fi
    local __tif_sec="$1"
    local -n __tif_out="$2"; __tif_out=()
    local __tif_slot
    if TIniFile._findSection "$__tif_sec"; then
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_kv="${__inst__}_kvalue"
        local IFS=' ' __tif_j
        for __tif_j in ${__tif_sr[__tif_slot]:-}; do
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
    local __tif_sec="${1:-}" __tif_id="${2:-}" __tif_val="${3:-}"
    if ! TIniFile._validate sec "$__tif_sec" || ! TIniFile._validate ident "$__tif_id" \
       || ! TIniFile._validate value "$__tif_val" \
       || ! TIniFile._validate pair "$__tif_id" "$__tif_val"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TIniFile.WriteString: invalid section/ident/value" >&2
        return 1
    fi
    local __tif_slot __tif_row
    local -n __tif_ct="${__inst__}_ctr"
    if ! TIniFile._findSection "$__tif_sec"; then
        # T6: the new slot index is TRACKED, not recovered by materialising
        # "${!arr[@]}" — that expansion is what made appending quadratic.
        local -n __tif_sn="${__inst__}_secnames"
        local -n __tif_sq="${__inst__}_snorm"
        local -n __tif_sb="${__inst__}_secbrk"
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_sx="${__inst__}_sblob"
        __tif_slot=${__tif_ct[1]}
        __tif_sn[__tif_slot]="$__tif_sec"
        __tif_sq[__tif_slot]="${__tif_sec,,}"
        __tif_sb[__tif_slot]=1
        __tif_sr[__tif_slot]=" "
        __tif_sx[__tif_slot]=$'\n'
        (( __tif_ct[1] += 1 )) || :
    fi
    local -n __tif_kv="${__inst__}_kvalue"
    if TIniFile._findKey "$__tif_slot" "$__tif_id"; then
        __tif_kv[__tif_row]="$__tif_val"
    else
        local -n __tif_ki="${__inst__}_kident"
        local -n __tif_kn="${__inst__}_knorm"
        local -n __tif_ko="${__inst__}_kowner"
        local -n __tif_rows="${__inst__}_srows"
        local -n __tif_blob="${__inst__}_sblob"
        local __tif_new=${__tif_ct[0]} __tif_lc="${__tif_id,,}"
        __tif_ki[__tif_new]="$__tif_id"
        __tif_kn[__tif_new]="$__tif_lc"
        __tif_kv[__tif_new]="$__tif_val"
        __tif_ko[__tif_new]=$__tif_slot
        __tif_rows[__tif_slot]+="$__tif_new "
        __tif_blob[__tif_slot]+="$__tif_lc"$'\n'
        (( __tif_ct[0] += 1 )) || :
    fi
    TIniFile._maybeUpdate
}

TIniFile.DeleteKey() {
    # S7: silent when section/key missing; flush(Maybe) ONLY on an actual
    # deletion (FPC :1313-1327). T5: the flush rc is the member's rc — in FPC
    # the SaveToFile exception propagates out of DeleteKey, so an eager instance
    # that could not write must not report success.
    local __tif_slot __tif_row
    if TIniFile._findSection "$1" && TIniFile._findKey "$__tif_slot" "$2"; then
        local -n __tif_sr="${__inst__}_srows"
        local -n __tif_sx="${__inst__}_sblob"
        local -n __tif_kn="${__inst__}_knorm"
        __tif_sr[__tif_slot]="${__tif_sr[__tif_slot]/ $__tif_row / }"
        # One occurrence out of the membership blob; the ident is quoted inside
        # the pattern so a value containing glob characters stays literal.
        __tif_sx[__tif_slot]="${__tif_sx[__tif_slot]/$'\n'"${__tif_kn[__tif_row]}"$'\n'/$'\n'}"
        unset "${__inst__}_kident[$__tif_row]" \
              "${__inst__}_knorm[$__tif_row]" \
              "${__inst__}_kvalue[$__tif_row]" \
              "${__inst__}_kowner[$__tif_row]"
        TIniFile._maybeUpdate
        return $?
    fi
    return 0
}

TIniFile.EraseSection() {
    # S7: silent when missing; found -> the whole section object dies (its
    # comment-keys and invalid rows with it) + MaybeUpdate (FPC :1300-1311).
    # T5: same rc rule as DeleteKey.
    local __tif_slot
    if TIniFile._findSection "$1"; then
        local -n __tif_sr="${__inst__}_srows"
        local IFS=' ' __tif_j
        for __tif_j in ${__tif_sr[__tif_slot]:-}; do
            unset "${__inst__}_kident[$__tif_j]" \
                  "${__inst__}_knorm[$__tif_j]" \
                  "${__inst__}_kvalue[$__tif_j]" \
                  "${__inst__}_kowner[$__tif_j]"
        done
        unset "${__inst__}_secnames[$__tif_slot]" \
              "${__inst__}_snorm[$__tif_slot]" \
              "${__inst__}_secbrk[$__tif_slot]" \
              "${__inst__}_srows[$__tif_slot]" \
              "${__inst__}_sblob[$__tif_slot]"
        TIniFile._maybeUpdate
        return $?
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
    local __tif_get __tif_slot __tif_row __tif_unq __tif_int
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
    local __tif_get __tif_slot __tif_row __tif_unq __tif_int
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
    local __tif_get __tif_slot __tif_row __tif_unq
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
    local __tif_get __tif_slot __tif_row __tif_unq
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
    # FPC :1441: section list cleared; dirty NOT touched (pinned).
    TIniFile._reset
    return 0
}

TMemIniFile.GetStrings() {
    # outArr -> the composed lines, GetStrings flavor (blank line after EVERY
    # section — the pinned one-detail divergence from UpdateFile, FPC :1486).
    # RESULT=count. CALL DIRECTLY.
    if ! TIniFile._outName "${1:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TMemIniFile.GetStrings: bad output array name '${1:-}'" >&2
        kk._return ""
        return 2
    fi
    local -n __tif_gout="$1"
    local -a __tif_gl
    TIniFile._compose __tif_gl getstrings
    __tif_gout=( "${__tif_gl[@]}" )
    kk._return "${#__tif_gout[@]}"
    return 0
}

TMemIniFile.SetStrings() {
    # inArr -> replace the content by re-parsing the lines (FPC :1483
    # FillSectionList); dirty NOT touched (pinned). T13: the INPUT array name is
    # bound by nameref inside _fill, so it needs the same validation.
    if ! TIniFile._outName "${1:-}"; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
            echo "Error: TMemIniFile.SetStrings: bad input array name '${1:-}'" >&2
        return 2
    fi
    TIniFile._reset
    TIniFile._fill "$1"
    return 0
}

TMemIniFile.Rename() {
    # newName [true|false] (FPC :1494: FFileName:=new; Reload -> re-read from
    # the NEW file, missing -> empty; no write happens).
    file_name="$1"
    if [[ "${2:-false}" == "true" ]]; then
        TIniFile._reset
        TIniFile._load
    fi
    return 0
}

# Finalize the classes (parent first).
build TIniFile
build TMemIniFile
