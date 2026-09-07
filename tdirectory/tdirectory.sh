#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TDIRECTORY_SOURCED:-}" ]]; then
    return
fi
declare -g _TDIRECTORY_SOURCED=1

# Locale self-heal (decision D6, kcl/README.md 1.6). Listings sort and match
# in the ambient locale; an empty environment means the C locale, where a
# multi-byte name is a string of bytes.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TDIRECTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TDIRECTORY_DIR/../../kklass/kklass_pascal.sh"

# tpath carries the path parsers that understand both separators (decision D5),
# the SHARED filesystem helpers (R13: _statTime, _touchTime, _chmodAttrs,
# _attrs — the same code tfile uses) and the return helper _ret / _retBool.
source "$TDIRECTORY_DIR/../tpath/tpath.sh"

# ---------------------------------------------------------------------------
# TDirectory: a static utility namespace (Free Pascal's TDirectory).
#
# ---- Return contract (decision D3, kcl/README.md 1.1) ----------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )`
# the value is printed exactly once, so every `v=$(tdirectory.x ...)` caller
# keeps working. Predicates answer with their exit status as well (R8), with
# true/false still in RESULT:
#
#     tdirectory.getFiles "$d"; use "$RESULT"      # no fork
#     if tdirectory.exists "$d"; then ...          # rc; RESULT is true/false
#
# Errors are rc 1 + RESULT='' and print nothing unless VERBOSE_KKLASS=debug is
# set (kcl/README.md 1.2 — the old bodies wrote "Error: ..." to stderr on every
# miss); a bad output-array name is rc 2 (1.7).
#
# Members are `static proc` and answer through tpath._ret rather than being
# `static func` + kk._return, because kklass's THIN static dispatcher re-prints
# kk._return's value on a DIRECT call too; see the note in tpath.sh.
#
# ---- Listings --------------------------------------------------------------
# getFiles / getDirectories / getFileSystemEntries take an optional FOURTH
# argument: the name of a caller array to fill, with the entry COUNT in RESULT
# (kcl/README.md 1.7). That is the only newline-safe form — without it the
# entries come back newline-joined in RESULT, exactly as they used to be
# printed. Listings INCLUDE dot-entries (R13, FPC/.NET parity) and recursion
# does NOT descend into a directory symlink (R13, finding G6-17).
#
# ---- Internal helpers ------------------------------------------------------
# tdirectory._* are NOT class members: plain functions, so members share logic
# without a nested `$( )`. `__td_*` is this unit's reserved variable prefix.
# ---------------------------------------------------------------------------
class tdirectory
    public
        # lifecycle
        static proc createDirectory
        static proc delete
        static proc exists
        static proc copy
        static proc isEmpty
        static proc move
        # path analysis (delegates to tpath)
        static proc isRelativePath
        static proc getDirectoryRoot
        static proc getParent
        # current directory / drives
        static proc getCurrentDirectory
        static proc setCurrentDirectory
        static proc getLogicalDrives
        # listing
        static proc getDirectories
        static proc getFiles
        static proc getFileSystemEntries
        # attributes
        static proc getAttributes
        static proc setAttributes
        # timestamps
        static proc getCreationTime
        static proc setCreationTime
        static proc getCreationTimeUtc
        static proc setCreationTimeUtc
        static proc getLastAccessTime
        static proc setLastAccessTime
        static proc getLastAccessTimeUtc
        static proc setLastAccessTimeUtc
        static proc getLastWriteTime
        static proc setLastWriteTime
        static proc getLastWriteTimeUtc
        static proc setLastWriteTimeUtc
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# A diagnostic goes to stderr ONLY under VERBOSE_KKLASS=debug (kcl/README 1.2).
tdirectory._debug() {
    if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
        printf '%s\n' "$1" >&2
    fi
}

# -> __td_r = $1 without its trailing separators of either kind. A path that is
#    nothing BUT separators comes back empty, which every caller treats as a
#    refusal — deleting or listing "/" by accident is not a service.
tdirectory._trimSeps() {
    __td_r="$1"
    while [[ "$__td_r" == */ ]] || [[ "$__td_r" == *"$__TPATH_BS" ]]; do
        __td_r="${__td_r%?}"
    done
}

# Turn on the globbing options a listing needs and remember what was there:
# dotglob ON (R13 — dot-entries belong to the listing, G6-09), failglob OFF
# (a caller's failglob used to abort the listing, G6-25), extglob ON (patterns).
# The saved state lands in the caller's __td_g_dot / __td_g_fail / __td_g_ext.
tdirectory._globOn() {
    __td_g_dot=1; shopt -q dotglob  || __td_g_dot=0
    __td_g_fail=1; shopt -q failglob || __td_g_fail=0
    __td_g_ext=1; shopt -q extglob  || __td_g_ext=0
    shopt -s dotglob extglob
    shopt -u failglob
}

tdirectory._globOff() {
    if (( __td_g_dot == 0 )); then shopt -u dotglob; fi
    if (( __td_g_fail == 1 )); then shopt -s failglob; fi
    if (( __td_g_ext == 0 )); then shopt -u extglob; fi
}

# The one walker behind all three listings. $1 dir, $2 pattern, $3 kind
# (d = directories, f = files, e = both), $4 = 1 for AllDirectories.
# Appends to the caller's __td_acc array.
#
# G6-17: `[[ -L ]]` is what stops the recursion at a directory symlink. With
# `loop/a/back -> loop` the old helpers walked the cycle and returned 21
# entries for one real subdirectory.
tdirectory._walk() {
    local __td_d="$1" __td_pat="$2" __td_kind="$3" __td_rec="$4"
    local __td_p __td_base
    for __td_p in "$__td_d"/*; do
        if [[ ! -e "$__td_p" && ! -L "$__td_p" ]]; then
            continue
        fi
        __td_base="${__td_p##*/}"
        if [[ -d "$__td_p" ]]; then
            if [[ "$__td_kind" != "f" ]] && [[ "$__td_base" == $__td_pat ]]; then
                __td_acc+=( "$__td_p" )
            fi
            if (( __td_rec )) && [[ ! -L "$__td_p" ]]; then
                tdirectory._walk "$__td_p" "$__td_pat" "$__td_kind" 1
            fi
        elif [[ -f "$__td_p" ]]; then
            if [[ "$__td_kind" != "d" ]] && [[ "$__td_base" == $__td_pat ]]; then
                __td_acc+=( "$__td_p" )
            fi
        fi
    done
}

# The shared body of getDirectories / getFiles / getFileSystemEntries.
# KIND DIR PATTERN SEARCH-OPTION [OUTARRAY]
tdirectory._list() {
    local __td_kind="$1" __td_dir="${2:-}" __td_pat="${3:-*}"
    local __td_opt="${4:-TopDirectoryOnly}" __td_out="${5:-}"
    local __td_r __td_rec=0
    local __td_g_dot __td_g_fail __td_g_ext
    local -a __td_acc=()

    if [[ -z "$__td_dir" ]]; then
        tdirectory._debug "Error: Directory path cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    if [[ -n "$__td_out" ]] && tpath._badOutName "$__td_out"; then
        tdirectory._debug "Error: bad output array name '$__td_out'"
        tpath._ret "" 2
        return 2
    fi
    # G6-24: a trailing separator used to come out DOUBLED in every path.
    tdirectory._trimSeps "$__td_dir"
    if [[ -n "$__td_r" ]]; then
        __td_dir="$__td_r"
    fi
    if [[ ! -d "$__td_dir" ]]; then
        tdirectory._debug "Error: Directory does not exist: $__td_dir"
        tpath._ret "" 1
        return 1
    fi
    if [[ "$__td_opt" != "TopDirectoryOnly" ]]; then
        __td_rec=1
    fi

    tdirectory._globOn
    tdirectory._walk "$__td_dir" "$__td_pat" "$__td_kind" "$__td_rec"
    tdirectory._globOff

    if [[ -n "$__td_out" ]]; then
        local -n __td_ref="$__td_out"
        __td_ref=( ${__td_acc[@]+"${__td_acc[@]}"} )
        tpath._ret "${#__td_acc[@]}"
        return 0
    fi
    local IFS=$'\n'
    tpath._ret "${__td_acc[*]}"
}

# ===========================================================================
# Method bodies (real bash functions; extracted by `build`)
# ===========================================================================

# ---- lifecycle ------------------------------------------------------------

tdirectory.createDirectory() {
    local dir_path="${1:-}"
    if [[ -z "$dir_path" ]]; then
        tdirectory._debug "Error: Directory path cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    if ! mkdir -p -- "$dir_path" 2>/dev/null; then
        tdirectory._debug "Error: cannot create directory: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    tpath._ret ""
}

# G6-04: `rm -rf -- "lnk/"` on a DIRECTORY SYMLINK deletes the TARGET's
# contents and leaves the link — a trailing slash makes rm follow the link.
# R13: strip the trailing separators first, and if what is left is a symlink,
# remove the LINK and nothing else.
tdirectory.delete() {
    local dir_path="${1:-}" recursive="${2:-true}" __td_r
    local __td_g_dot __td_g_fail __td_g_ext __td_p __td_empty=0
    if [[ -z "$dir_path" ]]; then
        tdirectory._debug "Error: Directory path cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    tdirectory._trimSeps "$dir_path"
    if [[ -z "$__td_r" ]]; then
        # the argument was nothing but separators - refuse, do not delete /
        tdirectory._debug "Error: refusing to delete the root: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    dir_path="$__td_r"
    if [[ -L "$dir_path" ]]; then
        if rm -- "$dir_path" 2>/dev/null; then
            tpath._ret ""
            return 0
        fi
        tdirectory._debug "Error: cannot remove link: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    if [[ ! -d "$dir_path" ]]; then
        tdirectory._debug "Error: Directory does not exist: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    if [[ "$recursive" == "true" ]]; then
        if rm -rf -- "$dir_path" 2>/dev/null; then
            tpath._ret ""
            return 0
        fi
        tdirectory._debug "Error: cannot remove directory: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    # non-recursive: the directory must be empty, dot-entries included (G6-09)
    tdirectory._globOn
    for __td_p in "$dir_path"/*; do
        if [[ -e "$__td_p" || -L "$__td_p" ]]; then
            __td_empty=1
            break
        fi
    done
    tdirectory._globOff
    if (( __td_empty )); then
        tdirectory._debug "Error: Directory is not empty: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    if rmdir -- "$dir_path" 2>/dev/null; then
        tpath._ret ""
        return 0
    fi
    tdirectory._debug "Error: cannot remove directory: $dir_path"
    tpath._ret "" 1
    return 1
}

# exists PATH [FOLLOWLINK=true]
# G6-24: the FollowLink argument was accepted and ignored. `[[ -d ]]` always
# follows, so "do not follow" has to exclude a symlink itself.
tdirectory.exists() {
    local dir_path="${1:-}" follow="${2:-true}"
    if [[ -z "$dir_path" ]]; then
        tpath._retBool 1
        return $?
    fi
    if [[ "$follow" == "false" ]] && [[ -L "$dir_path" ]]; then
        tpath._retBool 1
        return $?
    fi
    if [[ -d "$dir_path" ]]; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# G6-10: `cp -r -- src dst` NESTS the source when dst already exists
# (dst/src/a.txt). R13: an existing destination receives the CONTENTS.
tdirectory.copy() {
    local source_dir="${1:-}" dest_dir="${2:-}"
    if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
        tdirectory._debug "Error: Source and destination paths cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    if [[ ! -d "$source_dir" ]]; then
        tdirectory._debug "Error: Source directory does not exist: $source_dir"
        tpath._ret "" 1
        return 1
    fi
    if [[ -e "$dest_dir" ]]; then
        if [[ ! -d "$dest_dir" ]]; then
            tdirectory._debug "Error: Destination is not a directory: $dest_dir"
            tpath._ret "" 1
            return 1
        fi
        # `src/.` copies the CONTENTS, dot-entries included
        if ! cp -r -- "$source_dir/." "$dest_dir" 2>/dev/null; then
            tdirectory._debug "Error: copy failed: $source_dir -> $dest_dir"
            tpath._ret "" 1
            return 1
        fi
        tpath._ret ""
        return 0
    fi
    if ! cp -r -- "$source_dir" "$dest_dir" 2>/dev/null; then
        tdirectory._debug "Error: copy failed: $source_dir -> $dest_dir"
        tpath._ret "" 1
        return 1
    fi
    tpath._ret ""
}

# G6-16: `$(ls -A "$dir")` forked on every call — 73 ms per 200. A glob loop
# with dotglob answers the same question with no process at all, and agrees
# with the listings about dot-entries (G6-09).
tdirectory.isEmpty() {
    local dir_path="${1:-}" __td_p __td_empty=0
    local __td_g_dot __td_g_fail __td_g_ext
    if [[ -z "$dir_path" || ! -d "$dir_path" ]]; then
        tpath._retBool 1
        return $?
    fi
    tdirectory._globOn
    for __td_p in "$dir_path"/*; do
        if [[ -e "$__td_p" || -L "$__td_p" ]]; then
            __td_empty=1
            break
        fi
    done
    tdirectory._globOff
    if (( __td_empty )); then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

# G6-10: an existing destination made `mv` nest the source inside it. R13: an
# existing destination is rc 1, the source is left alone.
tdirectory.move() {
    local source_dir="${1:-}" dest_dir="${2:-}"
    if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
        tdirectory._debug "Error: Source and destination paths cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    if [[ ! -d "$source_dir" ]]; then
        tdirectory._debug "Error: Source directory does not exist: $source_dir"
        tpath._ret "" 1
        return 1
    fi
    if [[ -e "$dest_dir" ]]; then
        tdirectory._debug "Error: Destination already exists: $dest_dir"
        tpath._ret "" 1
        return 1
    fi
    if ! mv -- "$source_dir" "$dest_dir" 2>/dev/null; then
        tdirectory._debug "Error: move failed: $source_dir -> $dest_dir"
        tpath._ret "" 1
        return 1
    fi
    tpath._ret ""
}

# ---- path analysis (delegates to the tpath helpers, not to its members, so
#      nothing forks and nothing prints twice under $( ) — G6-16) ------------

tdirectory.isRelativePath() {
    if tpath._rooted "${1:-}"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

tdirectory.getDirectoryRoot() {
    local __tp_r
    tpath._pathRoot "${1:-}"
    tpath._ret "$__tp_r"
}

tdirectory.getParent() {
    local path="${1:-}" __tp_r
    if [[ "$path" == "." ]]; then
        path="$PWD"
    fi
    tpath._dirName "$path"
    tpath._ret "$__tp_r"
}

# ---- current directory / drives -------------------------------------------

tdirectory.getCurrentDirectory() {
    tpath._ret "$PWD"
}

# The thin static dispatcher does not run the body in a subshell, so this `cd`
# still takes effect in the CALLER's shell. `--`, so a leading-dash path is a
# path and not an option (G6-11: `setCurrentDirectory -` used to mean $OLDPWD).
tdirectory.setCurrentDirectory() {
    local dir_path="${1:-}"
    if [[ -z "$dir_path" ]]; then
        tdirectory._debug "Error: Directory path cannot be empty"
        tpath._ret "" 1
        return 1
    fi
    # `cd -- -` still means $OLDPWD: unlike rm/cp/mv, bash's cd reads a lone
    # `-` as the previous directory even after `--` (measured on 5.2 and 5.3).
    # A path API must mean the DIRECTORY named `-`, so spell it out. This is
    # the half of G6-11 that adding `--` in P1 could not fix.
    if [[ "$dir_path" == "-" ]]; then
        dir_path="./-"
    fi
    if ! cd -- "$dir_path" >/dev/null 2>&1; then
        tdirectory._debug "Error: cannot change directory: $dir_path"
        tpath._ret "" 1
        return 1
    fi
    tpath._ret "$PWD"
}

# G6-16: `$(uname -s)` forked on every call; the platform is a load-time
# constant that tpath already computed.
tdirectory.getLogicalDrives() {
    local drives="" letter
    if (( __TPATH_IS_WINDOWS == 0 )); then
        tpath._ret "/"
        return 0
    fi
    for letter in {C..Z}; do
        if [[ -d "/${letter,}" ]]; then
            drives="${drives}${letter}: "
        fi
    done
    tpath._ret "${drives% }"
}

# ---- listing ---------------------------------------------------------------
# DIR [PATTERN] [TopDirectoryOnly|AllDirectories] [OUTARRAY]

tdirectory.getDirectories() {
    tdirectory._list d "${1:-}" "${2:-*}" "${3:-TopDirectoryOnly}" "${4:-}"
}

tdirectory.getFiles() {
    tdirectory._list f "${1:-}" "${2:-*}" "${3:-TopDirectoryOnly}" "${4:-}"
}

tdirectory.getFileSystemEntries() {
    tdirectory._list e "${1:-}" "${2:-*}" "${3:-TopDirectoryOnly}" "${4:-}"
}

# ---- attributes ------------------------------------------------------------

tdirectory.getAttributes() {
    local path="${1:-}" follow="${2:-true}" __tp_r
    if [[ -z "$path" ]] || [[ ! -e "$path" && ! -L "$path" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._attrs "$path" "$follow"; then
        tpath._ret "$__tp_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

tdirectory.setAttributes() {
    local path="${1:-}"
    if [[ ! -d "$path" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._chmodAttrs "$path" "${2:-}"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

# ---- timestamps ------------------------------------------------------------
# The getters and the two settable setters go through the SHARED tpath helpers
# (R13) — the same code tfile uses, so a fix lands in both units at once.
# Creation time is NOT settable (R13): POSIX has no API and Windows' is not
# reachable through touch, so it answers rc 1 the way .NET does on Unix. The
# old body mapped it to `touch -m`, i.e. it silently set the WRITE time.

tdirectory._getTime() {   # STAT-FIELD UTC PATH
    local __tp_r
    if [[ ! -d "$3" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._statTime "$3" "$1" "$2"; then
        tpath._ret "$__tp_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

tdirectory._setTime() {   # TOUCH-FLAG UTC PATH VALUE
    if [[ ! -d "$3" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._touchTime "$3" "$4" "$1" "$2"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

tdirectory.getCreationTime()      { tdirectory._getTime "%W" false "${1:-}"; }
tdirectory.getCreationTimeUtc()   { tdirectory._getTime "%W" true  "${1:-}"; }
tdirectory.getLastAccessTime()    { tdirectory._getTime "%X" false "${1:-}"; }
tdirectory.getLastAccessTimeUtc() { tdirectory._getTime "%X" true  "${1:-}"; }
tdirectory.getLastWriteTime()     { tdirectory._getTime "%Y" false "${1:-}"; }
tdirectory.getLastWriteTimeUtc()  { tdirectory._getTime "%Y" true  "${1:-}"; }

tdirectory.setCreationTime()      { tpath._ret "" 1; return 1; }
tdirectory.setCreationTimeUtc()   { tpath._ret "" 1; return 1; }
tdirectory.setLastAccessTime()    { tdirectory._setTime "-a" false "${1:-}" "${2:-}"; }
tdirectory.setLastAccessTimeUtc() { tdirectory._setTime "-a" true  "${1:-}" "${2:-}"; }
tdirectory.setLastWriteTime()     { tdirectory._setTime "-m" false "${1:-}" "${2:-}"; }
tdirectory.setLastWriteTimeUtc()  { tdirectory._setTime "-m" true  "${1:-}" "${2:-}"; }

# Remove helper names leaked by older sourced versions of this module.
unset -f get_dirs_recursive get_files_recursive get_entries_recursive 2>/dev/null || true
unset -f tdirectory._get_dirs_recursive tdirectory._get_files_recursive \
         tdirectory._get_entries_recursive 2>/dev/null || true

# Finalize: extract the bodies above into the `tdirectory` class and generate
# the thin static dispatchers (see the header note). The class is named
# `tdirectory`, so the public API stays `tdirectory.<Method>` and the kklass
# metadata array `tdirectory_class_static_methods` is populated as before.
build tdirectory
