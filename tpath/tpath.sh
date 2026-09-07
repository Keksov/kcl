#!/bin/bash

# Re-source guard: constants below are readonly, and the class only needs to
# be built once per process (X-SETU / decision D7).
if [[ -n "${_TPATH_SOURCED:-}" ]]; then
    return
fi
declare -g _TPATH_SOURCED=1

# Locale self-heal (decision D6, kcl/README.md 1.6). Character semantics are
# part of this unit's contract: ${#s} must count characters and ${s,,} must not
# corrupt multi-byte text. An empty environment means the C locale.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TPATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TPATH_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Platform constants (decision D5).
#
# On MSYS/cygwin the shell, every external tool and every path the caller ever
# types use `/`, so DirectorySeparatorChar is `/` on EVERY platform; `\` is the
# ALTERNATE separator that the parsers still accept on input, because Windows
# paths (C:\Users\me\f.txt, \\srv\share) reach a bash script all the time.
# Only the DIRECTORY separator is POSIX-ised: PathSeparator and
# VolumeSeparatorChar keep their Windows values, they name different things.
#
# These are deliberately top-level variables, NOT `static var`s: a class with
# static variables gets the capturing static dispatcher (funsub on bash 5.3,
# scratch file on 5.2); a class WITHOUT them gets the thin, zero-overhead
# dispatcher on every bash. Bash has no file scope, so top-level variables are
# process-wide globals - hence the __TPATH_ prefix and `readonly` below; the
# public way to read them is the tpath.get*() methods.
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        __TPATH_IS_WINDOWS=1
        __TPATH_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR='\'
        __TPATH_PATH_SEPARATOR=';'
        __TPATH_VOLUME_SEPARATOR_CHAR=':'
        ;;
    *)
        __TPATH_IS_WINDOWS=0
        __TPATH_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_PATH_SEPARATOR=':'
        __TPATH_VOLUME_SEPARATOR_CHAR='/'
        ;;
esac

__TPATH_EXTENSION_SEPARATOR_CHAR='.'

# A literal backslash in its own variable. A bracket expression cannot carry
# one: inside [...] bash reads `\` as an escape, so `${p##*[/\\]}` and
# `[[ $p == [/\\]* ]]` match NEITHER `/` nor `\` (that is the mechanism behind
# finding G6-01 - the class silently collapsed to `/` only, and on 5.2/5.3 it
# does not even match that). `${p##*"$__TPATH_BS"}` and
# `[[ $p == *"$__TPATH_BS"* ]]` are the forms that do work.
__TPATH_BS='\'

readonly __TPATH_IS_WINDOWS __TPATH_DIRECTORY_SEPARATOR_CHAR \
         __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR __TPATH_PATH_SEPARATOR \
         __TPATH_VOLUME_SEPARATOR_CHAR __TPATH_EXTENSION_SEPARATOR_CHAR \
         __TPATH_BS

# ---------------------------------------------------------------------------
# TPath: a static utility namespace (Free Pascal's TPath / .NET System.IO.Path).
#
# ---- Return contract (decision D3, kcl/README.md 1.1) ----------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )`
# the value is printed exactly once, so every `v=$(tpath.x ...)` caller keeps
# working. Booleans additionally answer with their exit status (R8):
#
#     tpath.getFileName "$p"; use "$RESULT"        # no fork
#     name="$(tpath.getFileName "$p")"             # still works, forks
#     if tpath.isPathRooted "$p"; then ...         # rc; RESULT is true/false
#
# Members are `static proc`, not `static func`, and the value goes out through
# tpath._ret. That is NOT a deviation from D3's semantics, it is the only way
# to get them: kklass's THIN static dispatcher (the one a class without static
# variables receives) re-prints kk._return's value UNCONDITIONALLY, i.e. on a
# direct call too - `static func` would make every member echo on every call
# (the same measurement tregex.sh records in its header). tpath._ret is
# kk._return's contract with the subshell test kept and the dispatcher's
# unconditional printf avoided.
#
# Errors are rc 1 + RESULT='' and print nothing (kcl/README.md 1.2).
#
# ---- Internal helpers ------------------------------------------------------
# The tpath._* helpers below are NOT class members: they are plain functions,
# so members can share logic WITHOUT a nested `$( )` (finding G6-16) and
# without double-printing under `$( )`. They answer in the caller's local
# `__tp_r` / `__tp_rootlen` (bash scopes locals dynamically) - a member that
# calls one MUST declare `local __tp_r` first. Those two names, and the
# `__tp_*` prefix, are reserved for this unit.
#
# tpath._statTime / _touchTime / _chmodAttrs / _attrs are the SHARED filesystem
# helpers (R13): tfile and tdirectory both source this unit and call them, so
# the timestamp and attribute logic exists exactly once.
# ---------------------------------------------------------------------------
class tpath
    public
        # separator/property accessors
        static proc getAltDirectorySeparatorChar
        static proc getDirectorySeparatorChar
        static proc getExtensionSeparatorChar
        static proc getPathSeparator
        static proc getVolumeSeparatorChar
        # path combination and analysis
        static proc combine
        static proc getFileName
        static proc getDirectoryName
        static proc getExtension
        static proc getFileNameWithoutExtension
        static proc changeExtension
        static proc hasExtension
        # root / rooted / relative
        static proc getPathRoot
        static proc isPathRooted
        static proc isRelativePath
        static proc getFullPath
        # path type detection
        static proc isUNCPath
        static proc isUNCRooted
        static proc isDriveRooted
        static proc isExtendedPrefixed
        static proc driveExists
        # system paths
        static proc getTempPath
        static proc getHomePath
        static proc getDocumentsPath
        static proc getDownloadsPath
        # temporary and random file names
        static proc getTempFileName
        static proc getGUIDFileName
        static proc getRandomFileName
        # character and path validation
        static proc isValidFileNameChar
        static proc isValidPathChar
        static proc hasValidFileNameChars
        static proc hasValidPathChars
        static proc matchesPattern
        # file attributes
        static proc getAttributes
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# The return contract of every member (see the header note).
# $1 = value, $2 = exit status (default 0).
tpath._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# Boolean answer: RESULT/stdout carry true|false and the exit status carries
# the same answer (R8). $1 = 0 for true, anything else for false.
tpath._retBool() {
    if [[ "$1" == "0" ]]; then
        tpath._ret "true" 0
    else
        tpath._ret "false" 1
    fi
}

# -> __tp_r = the part of $1 after the last `/` or `\` (FPC ExtractFileName).
tpath._fileName() {
    __tp_r="${1##*/}"
    __tp_r="${__tp_r##*"$__TPATH_BS"}"
}

# -> __tp_rootlen = length of the root of $1, following FPC ExtractFileDrive
#    plus the POSIX root: //server/share (UNC), C: / C:/ (drive), / .
tpath._rootLen() {
    local __tp_p="$1" __tp_n=${#1} __tp_i __tp_c
    __tp_rootlen=0
    if [[ -z "$__tp_p" ]]; then
        return 0
    fi
    if tpath._unc "$__tp_p"; then
        __tp_i=2
        while (( __tp_i < __tp_n )); do
            __tp_c="${__tp_p:__tp_i:1}"
            if [[ "$__tp_c" == "/" || "$__tp_c" == "$__TPATH_BS" ]]; then
                break
            fi
            (( __tp_i++ )) || :
        done
        (( __tp_i++ )) || :
        while (( __tp_i < __tp_n )); do
            __tp_c="${__tp_p:__tp_i:1}"
            if [[ "$__tp_c" == "/" || "$__tp_c" == "$__TPATH_BS" ]]; then
                break
            fi
            (( __tp_i++ )) || :
        done
        if (( __tp_i > __tp_n )); then
            __tp_i=$__tp_n
        fi
        __tp_rootlen=$__tp_i
        return 0
    fi
    if [[ "$__tp_p" == [A-Za-z]:* ]]; then
        __tp_rootlen=2
        __tp_c="${__tp_p:2:1}"
        if [[ "$__tp_c" == "/" || "$__tp_c" == "$__TPATH_BS" ]]; then
            __tp_rootlen=3
        fi
        return 0
    fi
    if [[ "$__tp_p" == /* ]] || [[ "$__tp_p" == "$__TPATH_BS"* ]]; then
        __tp_rootlen=1
    fi
    return 0
}

# -> __tp_r = the directory part of $1 (.NET Path.GetDirectoryName / FPC
#    ExtractFileDir): all trailing separators stripped, cut at the LAST
#    separator of EITHER kind, the root kept when nothing else is left, ""
#    when the path has no directory part. Input characters are preserved
#    (C:\f.txt -> C:\), FPC-style. This is finding G6-12.
tpath._dirName() {
    local __tp_p="$1" __tp_n=${#1} __tp_i __tp_c
    local __tp_rootlen
    tpath._rootLen "$__tp_p"
    if (( __tp_n <= __tp_rootlen )); then
        __tp_r=""
        return 0
    fi
    __tp_i=$__tp_n
    while (( __tp_i > __tp_rootlen )); do
        (( __tp_i-- )) || :
        __tp_c="${__tp_p:__tp_i:1}"
        if [[ "$__tp_c" == "/" || "$__tp_c" == "$__TPATH_BS" ]]; then
            break
        fi
    done
    while (( __tp_i > __tp_rootlen )); do
        __tp_c="${__tp_p:__tp_i-1:1}"
        if [[ "$__tp_c" != "/" && "$__tp_c" != "$__TPATH_BS" ]]; then
            break
        fi
        (( __tp_i-- )) || :
    done
    __tp_r="${__tp_p:0:__tp_i}"
    return 0
}

# -> __tp_r = the root of $1 (FPC ExtractFileDrive plus the POSIX root), with
#    the input characters preserved; "" when the path is relative.
tpath._pathRoot() {
    local __tp_rootlen
    __tp_r=""
    if [[ -z "$1" ]]; then
        return 0
    fi
    tpath._rootLen "$1"
    if (( __tp_rootlen == 0 )); then
        return 0
    fi
    if tpath._unc "$1"; then
        __tp_r="${1:0:__tp_rootlen}"
        return 0
    fi
    if [[ "$1" == [A-Za-z]:* ]]; then
        __tp_r="${1:0:2}"
        return 0
    fi
    __tp_r="${1:0:1}"
    return 0
}

# rc 0 when $1 is rooted (absolute or drive-relative), rc 1 otherwise.
tpath._rooted() {
    if [[ -z "$1" ]]; then
        return 1
    fi
    if [[ "$1" == /* ]] || [[ "$1" == "$__TPATH_BS"* ]] || [[ "$1" == [A-Za-z]:* ]]; then
        return 0
    fi
    return 1
}

# rc 0 when $1 starts with two separators of either kind (UNC).
tpath._unc() {
    local __tp_c1="${1:0:1}" __tp_c2="${1:1:1}"
    if [[ "$__tp_c1" != "/" && "$__tp_c1" != "$__TPATH_BS" ]]; then
        return 1
    fi
    if [[ "$__tp_c2" != "/" && "$__tp_c2" != "$__TPATH_BS" ]]; then
        return 1
    fi
    return 0
}

# -> __tp_r = the home directory (fork-free).
tpath._home() {
    __tp_r="${HOME:-}"
}

# -> __tp_r = the temp directory (fork-free).
tpath._tempPath() {
    if [[ -n "${TMPDIR:-}" ]]; then
        __tp_r="$TMPDIR"
    elif [[ -n "${TEMP:-}" ]]; then
        __tp_r="$TEMP"
    elif [[ -n "${TMP:-}" ]]; then
        __tp_r="$TMP"
    else
        __tp_r="/tmp"
    fi
}

# rc 0 when the name contains a character Windows forbids in a FILE name.
# $2 == "true" allows the wildcards * and ?. `~` is legal (G6-20).
tpath._badFileNameChars() {
    if [[ "$1" == *[[:cntrl:]]* ]]; then
        return 0
    fi
    if [[ "$1" == */* ]] || [[ "$1" == *"$__TPATH_BS"* ]]; then
        return 0
    fi
    if [[ "$1" == *[\<\>\|\":]* ]]; then
        return 0
    fi
    if [[ "${2:-false}" != "true" ]] && [[ "$1" == *[\*\?]* ]]; then
        return 0
    fi
    return 1
}

# rc 0 when the path contains a character Windows forbids in a PATH.
# Separators and the drive colon are legal here; wildcards depend on $2.
tpath._badPathChars() {
    if [[ "$1" == *[[:cntrl:]]* ]]; then
        return 0
    fi
    if [[ "$1" == *[\<\>\|\"]* ]]; then
        return 0
    fi
    if [[ "${2:-false}" != "true" ]] && [[ "$1" == *[\*\?]* ]]; then
        return 0
    fi
    return 1
}

# rc 0 when $1 is NOT usable as the name of a caller output variable or array
# (kcl/README.md 1.7). Shared by every member of the three filesystem units
# that fills a caller-named variable; a rejected name is rc 2 at the member.
tpath._badOutName() {
    case "${1:-}" in
        ""|RESULT|REPLY|IFS|this|__inst__|__class__) return 0 ;;
        __kk_*|__KK_*|__tp_*|__tf_*|__td_*) return 0 ;;
    esac
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]]; then
        return 0
    fi
    return 1
}

# ---- shared filesystem helpers (R13; used by tfile and tdirectory) --------

# -> __tp_r = "YYYY-MM-DD HH:MM:SS" of stat format $2 for path $1.
# $3 == "true" formats in UTC. %W (birth time) falls back to %Y when the
# filesystem answers -1 (G6-26). rc 1 = no such path / no such timestamp.
tpath._statTime() {
    local __tp_p="$1" __tp_f="$2" __tp_utc="${3:-false}" __tp_e
    __tp_r=""
    # No `[[ -e ]]` probe first: `stat` already fails for a missing path, and
    # on NTFS an ACCESS-time read is destroyed by the extra access — Windows
    # rewrites a stored access time that is far in the past on the next
    # access, so the probe made getLastAccessTime answer "now" instead of the
    # value the setter had just stored. One syscall, one answer.
    __tp_e=$(stat -c "$__tp_f" -- "$__tp_p" 2>/dev/null) || return 1
    if [[ "$__tp_f" == "%W" && "$__tp_e" == "-1" ]]; then
        __tp_e=$(stat -c "%Y" -- "$__tp_p" 2>/dev/null) || return 1
    fi
    if [[ ! "$__tp_e" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi
    if [[ "$__tp_utc" == "true" ]]; then
        __tp_r=$(date -u -d "@$__tp_e" "+%Y-%m-%d %H:%M:%S" 2>/dev/null) || return 1
    else
        __tp_r=$(date -d "@$__tp_e" "+%Y-%m-%d %H:%M:%S" 2>/dev/null) || return 1
    fi
    return 0
}

# Set a timestamp of $1. $2 = epoch seconds or a date string, $3 = touch flag
# (-a or -m), $4 == "true" reads a date STRING as UTC (an epoch is absolute
# and never shifts).
#
# G6-08: the old code went through `date +%Y%m%d%H%M.%S` and `touch -t`, and
# `touch -t` reads LOCAL time - so every *Utc setter stored a value shifted by
# the local offset (three hours on this box). Everything now goes through an
# EPOCH and `touch -d @epoch`, which is absolute, so set/get round-trips
# exactly in both zones.
tpath._touchTime() {
    local __tp_p="$1" __tp_v="${2:-}" __tp_flag="${3:-}" __tp_utc="${4:-false}"
    local __tp_e __tp_touch
    if [[ ! -e "$__tp_p" && ! -L "$__tp_p" ]]; then
        return 1
    fi
    if [[ -z "$__tp_v" ]]; then
        return 1
    fi
    if [[ "$__tp_v" =~ ^[0-9]+$ ]]; then
        __tp_e="$__tp_v"
    elif [[ "$__tp_utc" == "true" ]]; then
        __tp_e=$(date -u -d "$__tp_v" +%s 2>/dev/null) || return 1
    else
        __tp_e=$(date -d "$__tp_v" +%s 2>/dev/null) || return 1
    fi
    if [[ ! "$__tp_e" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi
    # Prefer POSIX/GNU touch over a vendor touch.exe earlier in PATH.
    __tp_touch="/usr/bin/touch"
    if [[ ! -x "$__tp_touch" ]]; then
        __tp_touch="$(command -v touch 2>/dev/null)" || return 1
    fi
    "$__tp_touch" "$__tp_flag" -d "@$__tp_e" -- "$__tp_p" 2>/dev/null
}

# Apply an FPC attribute token list to $1 with chmod. faReadOnly is the only
# token a POSIX filesystem has; every other list clears the read-only bit.
tpath._chmodAttrs() {
    local __tp_p="$1" __tp_a="${2:-}"
    if [[ ! -e "$__tp_p" ]]; then
        return 1
    fi
    if [[ "$__tp_a" == *faReadOnly* ]]; then
        chmod a-w -- "$__tp_p" 2>/dev/null || return 1
    else
        chmod u+w -- "$__tp_p" 2>/dev/null || return 1
    fi
    return 0
}

# -> __tp_r = the FPC attribute token list of $1. $2 == "false" describes the
#    LINK instead of its target: `stat -L` FOLLOWS, so it belongs to the
#    follow_link == "true" branch, where the old code had it backwards
#    (G6-14). rc 1 = no such path.
tpath._attrs() {
    local __tp_p="$1" __tp_follow="${2:-true}" __tp_mode __tp_name
    __tp_r=""
    if [[ -z "$__tp_p" ]]; then
        return 1
    fi
    if [[ "$__tp_follow" == "false" ]]; then
        __tp_mode="$(stat -c "%a" -- "$__tp_p" 2>/dev/null)" || return 1
    else
        __tp_mode="$(stat -L -c "%a" -- "$__tp_p" 2>/dev/null)" || return 1
    fi
    if [[ -z "$__tp_mode" ]]; then
        return 1
    fi
    tpath._fileName "$__tp_p"
    __tp_name="$__tp_r"
    # A symlink is a directory only when we FOLLOW it: `[[ -d ]]` always
    # follows, so the not-follow branch has to exclude links itself.
    if [[ -d "$__tp_p" ]] && { [[ "$__tp_follow" != "false" ]] || [[ ! -L "$__tp_p" ]]; }; then
        __tp_r="faDirectory"
    else
        __tp_r="faNormal"
    fi
    # Read-only comes from the MODE that was just read, not from `-w`: `-w`
    # follows a symlink unconditionally, which is what made the FollowLink
    # answers identical (G6-14). Owner write bit clear = faReadOnly.
    if [[ "$__tp_mode" =~ ^[0-7]?[0-7][0-7][0-7]$ ]]; then
        if (( (8#${__tp_mode: -3:1} & 2) == 0 )); then
            __tp_r="${__tp_r},faReadOnly"
        fi
    elif [[ ! -w "$__tp_p" ]]; then
        __tp_r="${__tp_r},faReadOnly"
    fi
    if [[ "$__tp_name" == .* ]]; then
        __tp_r="${__tp_r},faHidden"
    fi
    if [[ "$__tp_mode" =~ ^[0-7]?[0-7][0-7][0-7]$ ]] && (( (8#${__tp_mode: -3:1} & 4) == 0 )); then
        __tp_r="${__tp_r},faSystem"
    fi
    return 0
}

# ===========================================================================
# Method bodies (real bash functions; extracted by `build`)
# ===========================================================================

# ---- property accessors ---------------------------------------------------

tpath.getAltDirectorySeparatorChar() {
    tpath._ret "$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getDirectorySeparatorChar() {
    tpath._ret "$__TPATH_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getExtensionSeparatorChar() {
    tpath._ret "$__TPATH_EXTENSION_SEPARATOR_CHAR"
}

tpath.getPathSeparator() {
    tpath._ret "$__TPATH_PATH_SEPARATOR"
}

tpath.getVolumeSeparatorChar() {
    tpath._ret "$__TPATH_VOLUME_SEPARATOR_CHAR"
}

# ---- combination and analysis ---------------------------------------------

tpath.combine() {
    local path1="${1:-}" path2="${2:-}"

    if [[ -n "$path2" ]] && tpath._rooted "$path2"; then
        tpath._ret "$path2"
        return 0
    fi
    if [[ -z "$path1" ]]; then
        tpath._ret "$path2"
        return 0
    fi
    if [[ -z "$path2" ]]; then
        tpath._ret "$path1"
        return 0
    fi
    # ALL trailing separators of either kind, not just one (G6-22), and the
    # joint is DirectorySeparatorChar = `/` (D5, G6-15) - the old body emitted
    # `\`, and its own parsers could not read the result back.
    while [[ "$path1" == */ ]] || [[ "$path1" == *"$__TPATH_BS" ]]; do
        path1="${path1%?}"
    done
    tpath._ret "${path1}${__TPATH_DIRECTORY_SEPARATOR_CHAR}${path2}"
}

tpath.getFileName() {
    local __tp_r
    if [[ -z "${1:-}" ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._fileName "$1"
    tpath._ret "$__tp_r"
}

tpath.getDirectoryName() {
    local __tp_r
    if [[ -z "${1:-}" ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._dirName "$1"
    tpath._ret "$__tp_r"
}

tpath.getExtension() {
    local __tp_r name
    if [[ -z "${1:-}" ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._fileName "$1"
    name="$__tp_r"
    if [[ "$name" != *.* ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._ret ".${name##*.}"
}

tpath.getFileNameWithoutExtension() {
    local __tp_r name
    if [[ -z "${1:-}" ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._fileName "$1"
    name="$__tp_r"
    if [[ "$name" != *.* ]]; then
        tpath._ret "$name"
        return 0
    fi
    tpath._ret "${name%.*}"
}

# FPC ChangeFileExt: the scan for the extension separator stops at the first
# directory or drive separator, so a dot in a DIRECTORY name is never touched
# (G6-02: `changeExtension dir.d/file .txt` used to answer `dir.txt`, and
# `changeExtension /home/u/.config/app/file .bak` answered `/home/u/.bak`).
tpath.changeExtension() {
    local __tp_r path extension dir name base
    path="${1:-}"
    extension="${2:-}"
    if [[ -z "$path" ]]; then
        tpath._ret ""
        return 0
    fi
    tpath._fileName "$path"
    name="$__tp_r"
    dir="${path%"$name"}"
    if [[ "$name" == *.* ]]; then
        base="${name%.*}"
    else
        base="$name"
    fi
    if [[ -n "$extension" ]]; then
        if [[ "$extension" != .* ]]; then
            extension=".$extension"
        fi
        tpath._ret "${dir}${base}${extension}"
    else
        tpath._ret "${dir}${base}"
    fi
}

tpath.hasExtension() {
    local __tp_r
    if [[ -z "${1:-}" ]]; then
        tpath._retBool 1
        return $?
    fi
    tpath._fileName "$1"
    if [[ "$__tp_r" == *.* ]]; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# ---- root / rooted / relative ---------------------------------------------

# FPC ExtractFileDrive semantics with the input characters preserved:
# //server/share for UNC (G6-22 - the old body stopped after the server),
# C: for a drive, the leading separator otherwise.
tpath.getPathRoot() {
    local __tp_r
    tpath._pathRoot "${1:-}"
    tpath._ret "$__tp_r"
}

tpath.isPathRooted() {
    if tpath._rooted "${1:-}"; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# G6-16: the old body ran `$(tpath.isPathRooted "$path")` - a fork per call
# (21 ms per 200 calls). The sibling logic is a plain helper now.
tpath.isRelativePath() {
    if tpath._rooted "${1:-}"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

# G6-13: `realpath` without -m answered the RAW relative input as soon as an
# intermediate component was missing, and -e answered nothing at all. -m
# resolves a path whose components need not exist.
tpath.getFullPath() {
    local path full
    path="${1:-}"
    if [[ -z "$path" ]]; then
        tpath._ret ""
        return 0
    fi
    if command -v realpath >/dev/null 2>&1; then
        full="$(realpath -m -- "$path" 2>/dev/null)" || full=""
        if [[ -n "$full" ]]; then
            tpath._ret "$full"
            return 0
        fi
    fi
    if command -v readlink >/dev/null 2>&1; then
        full="$(readlink -m -- "$path" 2>/dev/null)" || full=""
        if [[ -n "$full" ]]; then
            tpath._ret "$full"
            return 0
        fi
    fi
    if tpath._rooted "$path"; then
        tpath._ret "$path"
    else
        tpath._ret "$PWD/$path"
    fi
}

# ---- path type detection --------------------------------------------------

tpath.isUNCPath() {
    if [[ -n "${1:-}" ]] && tpath._unc "$1"; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

tpath.isUNCRooted() {
    if [[ -n "${1:-}" ]] && tpath._unc "$1"; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

tpath.isDriveRooted() {
    if [[ "${1:-}" == [A-Za-z]:* ]]; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

tpath.isExtendedPrefixed() {
    local path="${1:-}"
    if [[ -n "$path" ]] && tpath._unc "$path" && [[ "${path:2:1}" == "?" ]]; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# G6-16: `$(uname -s)` on EVERY call cost 45 ms per 200 calls; the platform is
# a load-time constant. G6-20: the answer used to be pure syntax - every `X:`
# was "true". A drive exists when its mount point does.
tpath.driveExists() {
    local path="${1:-}" letter
    if [[ -z "$path" ]] || (( __TPATH_IS_WINDOWS == 0 )); then
        tpath._retBool 1
        return $?
    fi
    if [[ "$path" != [A-Za-z]:* ]]; then
        tpath._retBool 1
        return $?
    fi
    letter="${path:0:1}"
    if [[ -d "/${letter,}" ]]; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# ---- system paths ---------------------------------------------------------

tpath.getTempPath() {
    local __tp_r
    tpath._tempPath
    tpath._ret "$__tp_r"
}

tpath.getHomePath() {
    local __tp_r
    tpath._home
    tpath._ret "$__tp_r"
}

tpath.getDocumentsPath() {
    local __tp_r
    tpath._home
    tpath._ret "$__tp_r/Documents"
}

tpath.getDownloadsPath() {
    local __tp_r
    tpath._home
    tpath._ret "$__tp_r/Downloads"
}

# ---- temporary and random names -------------------------------------------

tpath.getTempFileName() {
    local __tp_r temp_dir temp_file stamp
    tpath._tempPath
    temp_dir="$__tp_r"
    temp_file="$(mktemp "$temp_dir/tmp.XXXXXXXXXX" 2>/dev/null)" || temp_file=""
    if [[ -z "$temp_file" ]]; then
        printf -v stamp '%(%s)T' -1
        temp_file="$temp_dir/tmp_${stamp}_$RANDOM"
        if ! : > "$temp_file" 2>/dev/null; then
            tpath._ret "" 1
            return 1
        fi
    fi
    tpath._ret "$temp_file"
}

tpath.getGUIDFileName() {
    local use_separator="${1:-false}" guid stamp
    if command -v uuidgen >/dev/null 2>&1; then
        guid="$(uuidgen 2>/dev/null)"
        guid="${guid,,}"
        guid="${guid%$'\r'}"
        if [[ "$use_separator" == "false" ]]; then
            guid="${guid//-/}"
        fi
        tpath._ret "$guid"
        return 0
    fi
    printf -v stamp '%(%s)T' -1
    if [[ "$use_separator" == "false" ]]; then
        printf -v guid "%08x%04x%04x%04x%08x" \
            "$(( stamp ))" "$(( RANDOM & 0xFFFF ))" "$(( RANDOM & 0xFFFF ))" \
            "$(( RANDOM & 0xFFFF ))" "$(( (RANDOM << 16) | RANDOM ))"
    else
        printf -v guid "%08x-%04x-%04x-%04x-%012x" \
            "$(( stamp ))" "$(( RANDOM & 0xFFFF ))" "$(( RANDOM & 0xFFFF ))" \
            "$(( RANDOM & 0xFFFF ))" "$(( (RANDOM << 16) | RANDOM ))"
    fi
    tpath._ret "$guid"
}

tpath.getRandomFileName() {
    local stamp name
    printf -v stamp '%(%s)T' -1
    printf -v name "tmp_%x_%04x" "$(( stamp ))" "$RANDOM"
    tpath._ret "$name"
}

# ---- character and path validation ----------------------------------------

tpath.isValidFileNameChar() {
    local char="${1:-}"
    if [[ -z "$char" ]] || (( ${#char} != 1 )); then
        tpath._retBool 1
        return $?
    fi
    if tpath._badFileNameChars "$char" "false"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

tpath.isValidPathChar() {
    local char="${1:-}"
    if [[ -z "$char" ]] || (( ${#char} != 1 )); then
        tpath._retBool 1
        return $?
    fi
    if tpath._badPathChars "$char" "false"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

tpath.hasValidFileNameChars() {
    local filename="${1:-}" use_wildcards="${2:-false}"
    if [[ -z "$filename" ]]; then
        tpath._retBool 0
        return $?
    fi
    if tpath._badFileNameChars "$filename" "$use_wildcards"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

tpath.hasValidPathChars() {
    local path="${1:-}" use_wildcards="${2:-false}"
    if [[ -z "$path" ]]; then
        tpath._retBool 0
        return $?
    fi
    if tpath._badPathChars "$path" "$use_wildcards"; then
        tpath._retBool 1
    else
        tpath._retBool 0
    fi
}

# G6-21: the old body turned nocasematch OFF afterwards unconditionally, so a
# caller that had it ON lost it. Save what was there and put it back.
tpath.matchesPattern() {
    local filename="${1:-}" pattern="${2:-}" case_sensitive="${3:-true}"
    local had_nocase=1 matched=1
    if [[ -z "$filename" ]] || [[ -z "$pattern" ]]; then
        tpath._retBool 1
        return $?
    fi
    shopt -q nocasematch || had_nocase=0
    if [[ "$case_sensitive" == "false" ]]; then
        shopt -s nocasematch
    fi
    if [[ "$filename" == $pattern ]]; then
        matched=0
    fi
    if (( had_nocase )); then
        shopt -s nocasematch
    else
        shopt -u nocasematch
    fi
    tpath._retBool "$matched"
}

# ---- file attributes ------------------------------------------------------

tpath.getAttributes() {
    local __tp_r
    if tpath._attrs "${1:-}" "${2:-true}"; then
        tpath._ret "$__tp_r"
    else
        tpath._ret "" 1
    fi
}

# Finalize: extract the bodies above into the `tpath` class and generate the
# thin static dispatchers (see the header note). The class is named `tpath`,
# so the public API stays `tpath.<Method>` and the kklass metadata array
# `tpath_class_static_methods` is populated as before.
build tpath
