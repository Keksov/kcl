#!/bin/bash

# Re-source guard: constants below are readonly, and the class only needs to
# be built once per process.
if [[ -n "$_TPATH_SOURCED" ]]; then
    return
fi
declare -g _TPATH_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TPATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TPATH_DIR/../../kklass/kklass_pascal.sh"

# Define platform-specific constants.
# NOTE: these are deliberately top-level variables, NOT `static var`s: a class
# with static variables gets the capturing static dispatcher (funsub on bash
# 5.3, scratch file on 5.2); a class WITHOUT them gets the thin, zero-overhead
# dispatcher on every bash. Bash has no file scope, so top-level variables are
# process-wide globals — hence the __TPATH_ prefix and `readonly` below; the
# public way to read them is the tpath.get*() methods.
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        __TPATH_DIRECTORY_SEPARATOR_CHAR=$'\\'
        __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_PATH_SEPARATOR=';'
        __TPATH_VOLUME_SEPARATOR_CHAR=':'
        ;;
    *)
        __TPATH_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR='/'
        __TPATH_PATH_SEPARATOR=':'
        __TPATH_VOLUME_SEPARATOR_CHAR='/'
        ;;
esac

__TPATH_EXTENSION_SEPARATOR_CHAR='.'

readonly __TPATH_DIRECTORY_SEPARATOR_CHAR __TPATH_ALT_DIRECTORY_SEPARATOR_CHAR \
         __TPATH_PATH_SEPARATOR __TPATH_VOLUME_SEPARATOR_CHAR \
         __TPATH_EXTENSION_SEPARATOR_CHAR

# ---------------------------------------------------------------------------
# TPath: a static utility namespace (Free Pascal's TPath / .NET System.IO.Path).
#
# Pascal DSL form: the class STRUCTURE (interface) is declared first, the method
# BODIES follow as real bash functions, and `build tpath` finalizes the class.
# Every member is `static` — there is no per-instance state — so all methods are
# called as `tpath.<Method>` (the public API, unchanged from before).
#
# `proc`, not `func`: these helpers return their result by `echo`ing it (the
# established tpath.* convention), not via RESULT. Methods may also cross-call
# each other with `$(tpath.getFileName ...)` — after build those names are the
# generated dispatchers, so the calls resolve normally.
#
# The class declares NO static variables, so every method gets the thin,
# capture-free dispatcher — as fast as the previous kk.register_static_methods
# wrappers on bash 5.2 and 5.3 alike.
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

# ---- method bodies (real bash functions; extracted by `build`) --------------

# ============================================================================
# Property accessor methods
# ============================================================================

tpath.getAltDirectorySeparatorChar() {
    echo "$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getDirectorySeparatorChar() {
    echo "$__TPATH_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getExtensionSeparatorChar() {
    echo "$__TPATH_EXTENSION_SEPARATOR_CHAR"
}

tpath.getPathSeparator() {
    echo "$__TPATH_PATH_SEPARATOR"
}

tpath.getVolumeSeparatorChar() {
    echo "$__TPATH_VOLUME_SEPARATOR_CHAR"
}

# ============================================================================
# Path combination and analysis
# ============================================================================

tpath.combine() {
    local path1="$1"
    local path2="$2"

    if [[ "$path2" =~ ^[/\\\\] ]] || [[ "$path2" =~ ^[A-Za-z]: ]]; then
        echo "$path2"
        return 0
    fi

    if [[ -z "$path1" ]]; then
        echo "$path2"
    elif [[ -z "$path2" ]]; then
        echo "$path1"
    else
        path1="${path1%$__TPATH_DIRECTORY_SEPARATOR_CHAR}"
        path1="${path1%$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR}"
        echo "${path1}${__TPATH_DIRECTORY_SEPARATOR_CHAR}${path2}"
    fi
}

tpath.getFileName() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    local filename="${path##*[$__TPATH_DIRECTORY_SEPARATOR_CHAR$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR]}"
    echo "$filename"
}

tpath.getDirectoryName() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    # Remove trailing separators
    path="${path%/}"
    path="${path%\\}"

    # Get directory part
    local dir_path="${path%/*}"
    if [[ "$dir_path" == "$path" ]]; then
        dir_path="${path%\\*}"
    fi

    if [[ "$dir_path" == "$path" ]]; then
        echo ""
    else
        echo "$dir_path"
    fi
}

tpath.getExtension() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    local filename="${path##*[$__TPATH_DIRECTORY_SEPARATOR_CHAR$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR]}"
    local extension="${filename##*.}"

    if [[ "$extension" == "$filename" ]]; then
        echo ""
    else
        echo ".$extension"
    fi
}

tpath.getFileNameWithoutExtension() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    local filename
    filename="$(tpath.getFileName "$path")"

    if [[ -z "$filename" ]]; then
        echo ""
        return 0
    fi

    local name_without_ext="${filename%.*}"
    echo "$name_without_ext"
}

tpath.changeExtension() {
    local path="$1"
    local extension="$2"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    local last_dot="${path##*.}"
    local base_path="${path%.*}"

    if [[ "$last_dot" == "$path" ]]; then
        base_path="$path"
    fi

    if [[ -n "$extension" ]]; then
        if [[ "$extension" != .* ]]; then
            extension=".$extension"
        fi
        echo "${base_path}${extension}"
    else
        echo "$base_path"
    fi
}

tpath.hasExtension() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    local filename
    filename="$(tpath.getFileName "$path")"

    if [[ "$filename" == *.* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# ============================================================================
# Path analysis - root, rooted, relative
# ============================================================================

tpath.getPathRoot() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\][/\\\\] ]]; then
        local rest="${path#??}"
        local server_part="${rest%%[$__TPATH_DIRECTORY_SEPARATOR_CHAR$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR]*}"
        echo "//$server_part"
        return 0
    fi

    if [[ "$path" =~ ^[A-Za-z]: ]]; then
        echo "${path:0:2}"
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\] ]]; then
        echo "/"
        return 0
    fi

    echo ""
}

tpath.isPathRooted() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\] ]] || [[ "$path" =~ ^[A-Za-z]: ]]; then
        echo "true"
    else
        echo "false"
    fi
}

tpath.isRelativePath() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "true"
        return 0
    fi

    local rooted
    rooted="$(tpath.isPathRooted "$path")"

    if [[ "$rooted" == "true" ]]; then
        echo "false"
    else
        echo "true"
    fi
}

tpath.getFullPath() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$path" 2>/dev/null || echo "$path"
    else
        if [[ "$path" != /* ]]; then
            echo "$(pwd)/$path"
        else
            echo "$path"
        fi
    fi
}

# ============================================================================
# Path type detection
# ============================================================================

tpath.isUNCPath() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\][/\\\\] ]]; then
        echo "true"
    else
        echo "false"
    fi
}

tpath.isUNCRooted() {
    local path="$1"
    tpath.isUNCPath "$path"
}

tpath.isDriveRooted() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    if [[ "$path" =~ ^[A-Za-z]: ]]; then
        echo "true"
    else
        echo "false"
    fi
}

tpath.isExtendedPrefixed() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\][/\\\\]\\? ]]; then
        echo "true"
    else
        echo "false"
    fi
}

tpath.driveExists() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "false"
        return 0
    fi

    case "$(uname -s)" in
        MINGW*|CYGWIN*|MSYS*)
            if [[ "$path" =~ ^[A-Za-z]: ]]; then
                echo "true"
            else
                echo "false"
            fi
            ;;
        *)
            echo "false"
            ;;
    esac
}

# ============================================================================
# System paths
# ============================================================================

tpath.getTempPath() {
    if [[ -n "$TMPDIR" ]]; then
        echo "$TMPDIR"
    elif [[ -n "$TEMP" ]]; then
        echo "$TEMP"
    elif [[ -n "$TMP" ]]; then
        echo "$TMP"
    else
        echo "/tmp"
    fi
}

tpath.getHomePath() {
    echo "$HOME"
}

tpath.getDocumentsPath() {
    local home
    home="$(tpath.getHomePath)"

    case "$(uname -s)" in
        Darwin)
            echo "$home/Documents"
            ;;
        MINGW*|CYGWIN*|MSYS*)
            echo "$home/Documents"
            ;;
        *)
            echo "$home/Documents"
            ;;
    esac
}

tpath.getDownloadsPath() {
    local home
    home="$(tpath.getHomePath)"

    case "$(uname -s)" in
        Darwin)
            echo "$home/Downloads"
            ;;
        MINGW*|CYGWIN*|MSYS*)
            echo "$home/Downloads"
            ;;
        *)
            echo "$home/Downloads"
            ;;
    esac
}

# ============================================================================
# Temporary and random file names
# ============================================================================

tpath.getTempFileName() {
    local temp_dir
    temp_dir="$(tpath.getTempPath)"

    local temp_file
    temp_file="$(mktemp "$temp_dir/tmp.XXXXXXXXXX" 2>/dev/null)"

    if [[ -z "$temp_file" ]]; then
        local timestamp
        timestamp="$(date +%s%N 2>/dev/null || date +%s)"
        temp_file="$temp_dir/tmp_$timestamp"
        touch "$temp_file" 2>/dev/null
    fi

    echo "$temp_file"
}

tpath.getGUIDFileName() {
    local use_separator="${1:-false}"

    if command -v uuidgen >/dev/null 2>&1; then
        local guid
        guid="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        if [[ "$use_separator" == "false" ]]; then
            guid="${guid//-/}"
        fi
        echo "$guid"
    else
        local timestamp
        timestamp="$(date +%s%N 2>/dev/null || date +%s)"
        local random_part
        random_part="$(od -An -tx1 /dev/urandom 2>/dev/null | head -1 | tr -d ' ' || echo "random")"

        if [[ "$use_separator" == "false" ]]; then
            printf "%x%s" "$timestamp" "$random_part"
        else
            printf "%08x-%04x-%04x-%04x-%012x" \
                "$((timestamp >> 32))" \
                "$(( (timestamp >> 16) & 0xFFFF ))" \
                "$(( timestamp & 0xFFFF ))" \
                "$(( RANDOM & 0xFFFF ))" \
                "$(( RANDOM << 16 | RANDOM ))"
        fi
    fi
}

tpath.getRandomFileName() {
    local timestamp
    timestamp="$(date +%s%N 2>/dev/null || date +%s)"
    printf "tmp_%x_%04x" "$timestamp" "$RANDOM"
}

# ============================================================================
# Character and path validation
# ============================================================================

tpath.isValidFileNameChar() {
    local char="$1"

    if [[ -z "$char" ]] || [[ ${#char} -ne 1 ]]; then
        echo "false"
        return 0
    fi

    case "$char" in
        [[:cntrl:]] | "/" | "~")
            echo "false"
            ;;
        *)
            echo "true"
            ;;
    esac
}

tpath.isValidPathChar() {
    local char="$1"

    if [[ -z "$char" ]] || [[ ${#char} -ne 1 ]]; then
        echo "false"
        return 0
    fi

    case "$char" in
        [[:cntrl:]])
            echo "false"
            ;;
        *)
            echo "true"
            ;;
    esac
}

tpath.hasValidFileNameChars() {
    local filename="$1"
    local use_wildcards="${2:-false}"

    if [[ -z "$filename" ]]; then
        echo "true"
        return 0
    fi

    local invalid_chars="/"
    if [[ "$use_wildcards" == "false" ]]; then
        invalid_chars="$invalid_chars*?"
    fi

    if [[ "$filename" =~ [$invalid_chars] ]]; then
        echo "false"
    else
        echo "true"
    fi
}

tpath.hasValidPathChars() {
    local path="$1"
    local use_wildcards="${2:-false}"

    if [[ -z "$path" ]]; then
        echo "true"
        return 0
    fi

    local invalid_chars=""
    if [[ "$use_wildcards" == "false" ]]; then
        invalid_chars="*?"
    fi

    if [[ "$path" =~ [$invalid_chars] ]]; then
        echo "false"
    else
        echo "true"
    fi
}

tpath.matchesPattern() {
    local filename="$1"
    local pattern="$2"
    local case_sensitive="${3:-true}"

    if [[ -z "$filename" ]] || [[ -z "$pattern" ]]; then
        echo "false"
        return 0
    fi

    if [[ "$case_sensitive" == "false" ]]; then
        shopt -s nocasematch
    fi

    if [[ "$filename" == $pattern ]]; then
        echo "true"
    else
        echo "false"
    fi

    if [[ "$case_sensitive" == "false" ]]; then
        shopt -u nocasematch
    fi
}

# ============================================================================
# File attributes
# ============================================================================

tpath.getAttributes() {
    local path="$1"
    local follow_link="${2:-true}"

    if [[ -z "$path" ]]; then
        echo ""
        return 1
    fi

    if command -v stat >/dev/null 2>&1; then
        local stat_flags=""
        if [[ "$follow_link" == "false" ]]; then
            stat_flags="-L"
        fi

        local mode
        mode="$(stat $stat_flags -c "%a" "$path" 2>/dev/null)"
        if [[ $? -eq 0 ]]; then
            local attrs=""

            if [[ -d "$path" ]]; then
                attrs="faDirectory"
            else
                attrs="faNormal"
            fi

            if [[ ! -w "$path" ]]; then
                if [[ -n "$attrs" ]]; then
                    attrs="${attrs},faReadOnly"
                else
                    attrs="faReadOnly"
                fi
            fi

            if [[ "$(basename "$path")" =~ ^\. ]]; then
                if [[ -n "$attrs" ]]; then
                    attrs="${attrs},faHidden"
                else
                    attrs="faHidden"
                fi
            fi

            if [[ "$mode" =~ ^[0-7][0-7][0-7]$ ]] && [[ "$((8#${mode:0:1} & 4))" -eq 0 ]]; then
                if [[ -n "$attrs" ]]; then
                    attrs="${attrs},faSystem"
                else
                    attrs="faSystem"
                fi
            fi

            echo "$attrs"
        else
            return 1
        fi
    else
        if [[ -e "$path" ]]; then
            local attrs=""

            if [[ -d "$path" ]]; then
                attrs="faDirectory"
            else
                attrs="faNormal"
            fi

            echo "$attrs"
        else
            return 1
        fi
    fi
}

# Finalize: extract the bodies above into the `tpath` class and generate the
# thin static dispatchers (see the header note). The class is named `tpath`,
# so the public API stays `tpath.<Method>` and the kklass metadata array
# `tpath_class_static_methods` is populated as before.
build tpath

