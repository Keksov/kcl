#!/bin/bash
# kcl/tpath_minimal.sh - TPath with essential methods only

# Source kklass system (don't override SCRIPT_DIR)
TPATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TPATH_DIR/../../kklass/kklass.sh"

# Define platform-specific constants
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        DIRECTORY_SEPARATOR_CHAR='\\'
        ALT_DIRECTORY_SEPARATOR_CHAR='/'
        PATH_SEPARATOR=';'
        VOLUME_SEPARATOR_CHAR=':'
        ;;
    *)
        DIRECTORY_SEPARATOR_CHAR='/'
        ALT_DIRECTORY_SEPARATOR_CHAR='/'
        PATH_SEPARATOR=':'
        VOLUME_SEPARATOR_CHAR='/'
        ;;
esac

EXTENSION_SEPARATOR_CHAR='.'

# Define the tpath class with essential methods only
defineClass "tpath" "" \
    "static_method" "combine" '
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
            path1="${path1%\"$DIRECTORY_SEPARATOR_CHAR\"}"
            path1="${path1%\"$ALT_DIRECTORY_SEPARATOR_CHAR\"}"
            echo "${path1}${DIRECTORY_SEPARATOR_CHAR}${path2}"
        fi
    ' \
    "static_method" "getFileName" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        local filename="${path##*[\"$DIRECTORY_SEPARATOR_CHAR\"\"$ALT_DIRECTORY_SEPARATOR_CHAR\"]}"
        echo "$filename"
    ' \
    "static_method" "hasExtension" '
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
    '

# Add additional methods as functions
tpath.getAltDirectorySeparatorChar() {
    echo "$ALT_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getDirectorySeparatorChar() {
    echo "$DIRECTORY_SEPARATOR_CHAR"
}

tpath.getExtensionSeparatorChar() {
    echo "$EXTENSION_SEPARATOR_CHAR"
}

tpath.getPathSeparator() {
    echo "$PATH_SEPARATOR"
}

tpath.getVolumeSeparatorChar() {
    echo "$VOLUME_SEPARATOR_CHAR"
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
                local drive="${path:0:2}"
                if ls "$drive" >/dev/null 2>&1; then
                    echo "true"
                else
                    echo "false"
                fi
            else
                echo "false"
            fi
            ;;
        *)
            echo "false"
            ;;
    esac
}

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
                attrs="${attrs}faDirectory"
            fi
            if [[ ! -w "$path" ]]; then
                attrs="${attrs},faReadOnly"
            fi
            if [[ "$(basename "$path")" =~ ^\. ]]; then
                attrs="${attrs},faHidden"
            fi
            if [[ "$mode" =~ ^[0-7][0-7][0-7]$ ]] && [[ "$((8#${mode:0:1} & 4))" -eq 0 ]]; then
                attrs="${attrs},faSystem"
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
            fi
            echo "$attrs"
        else
            return 1
        fi
    fi
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

tpath.matchesPattern() {
    local filename="$1"
    local pattern="$2"
    local case_sensitive="${3:-true}"

    if [[ -z "$filename" ]] || [[ -z "$pattern" ]]; then
        echo "false"
        return 0
    fi

    local flags=""
    if [[ "$case_sensitive" == "false" ]]; then
        flags="nocasematch"
    fi

    shopt -s $flags
    if [[ "$filename" == $pattern ]]; then
        echo "true"
    else
        echo "false"
    fi
    shopt -u $flags
}

# Add additional methods as functions
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
        if [[ "$extension" != \".\"* ]]; then
            extension=".$extension"
        fi
        echo "${base_path}${extension}"
    else
        echo "$base_path"
    fi
}

tpath.getDirectoryName() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    path="${path%\"$DIRECTORY_SEPARATOR_CHAR\"}"
    path="${path%\"$ALT_DIRECTORY_SEPARATOR_CHAR\"}"

    local dir_path="${path%[\"$DIRECTORY_SEPARATOR_CHAR\"\"$ALT_DIRECTORY_SEPARATOR_CHAR\"]*}"

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

    local filename="${path##*[\"$DIRECTORY_SEPARATOR_CHAR\"\"$ALT_DIRECTORY_SEPARATOR_CHAR\"]}"
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

tpath.getPathRoot() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi

    if [[ "$path" =~ ^[/\\\\][/\\\\] ]]; then
        local rest="${path#??}"
        local server_part="${rest%%[\"$DIRECTORY_SEPARATOR_CHAR\"\"$ALT_DIRECTORY_SEPARATOR_CHAR\"]*}"
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

tpath.getAltDirectorySeparatorChar() {
    echo "$ALT_DIRECTORY_SEPARATOR_CHAR"
}

tpath.getDirectorySeparatorChar() {
    echo "$DIRECTORY_SEPARATOR_CHAR"
}

tpath.getExtensionSeparatorChar() {
    echo "$EXTENSION_SEPARATOR_CHAR"
}

tpath.getPathSeparator() {
    echo "$PATH_SEPARATOR"
}

tpath.getVolumeSeparatorChar() {
    echo "$VOLUME_SEPARATOR_CHAR"
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
                local drive="${path:0:2}"
                if ls "$drive" >/dev/null 2>&1; then
                    echo "true"
                else
                    echo "false"
                fi
            else
                echo "false"
            fi
            ;;
        *)
            echo "false"
            ;;
    esac
}

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
                attrs="${attrs}faDirectory"
            fi
            if [[ ! -w "$path" ]]; then
                attrs="${attrs},faReadOnly"
            fi
            if [[ "$(basename "$path")" =~ ^\. ]]; then
                attrs="${attrs},faHidden"
            fi
            if [[ "$mode" =~ ^[0-7][0-7][0-7]$ ]] && [[ "$((8#${mode:0:1} & 4))" -eq 0 ]]; then
                attrs="${attrs},faSystem"
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
            fi
            echo "$attrs"
        else
            return 1
        fi
    fi
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

tpath.matchesPattern() {
    local filename="$1"
    local pattern="$2"
    local case_sensitive="${3:-true}"

    if [[ -z "$filename" ]] || [[ -z "$pattern" ]]; then
        echo "false"
        return 0
    fi

    local flags=""
    if [[ "$case_sensitive" == "false" ]]; then
        flags="nocasematch"
    fi

    shopt -s $flags
    if [[ "$filename" == $pattern ]]; then
        echo "true"
    else
        echo "false"
    fi
    shopt -u $flags
}

echo "tpath class created successfully"
