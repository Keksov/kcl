#!/bin/bash
# kcl/tpath_extra.sh - Additional TPath methods as simple functions

# Create simple functions instead of classes to avoid eval issues
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

    # On POSIX, drives do not exist
    case "$(uname -s)" in
        MINGW*|CYGWIN*|MSYS*)
            # Windows: check if drive letter exists
            if [[ "$path" =~ ^[A-Za-z]: ]]; then
                local drive="${path:0:2}"
                # Try to access the drive
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
            # POSIX: always false
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

    # Use stat to get attributes
    if command -v stat >/dev/null 2>&1; then
        local stat_flags=""
        if [[ "$follow_link" == "false" ]]; then
            stat_flags="-L"
        fi

        # Get file mode in octal
        local mode
        mode="$(stat $stat_flags -c "%a" "$path" 2>/dev/null)"
        if [[ $? -eq 0 ]]; then
            # Convert to TFileAttributes-like format (simplified)
            local attrs=""
            # Check if directory
            if [[ -d "$path" ]]; then
                attrs="${attrs}faDirectory"
            fi
            # Check if read-only
            if [[ ! -w "$path" ]]; then
                attrs="${attrs},faReadOnly"
            fi
            # Check if hidden (starts with .)
            if [[ "$(basename "$path")" =~ ^\. ]]; then
                attrs="${attrs},faHidden"
            fi
            # Check if system (simplified)
            if [[ "$mode" =~ ^[0-7][0-7][0-7]$ ]] && [[ "$((8#${mode:0:1} & 4))" -eq 0 ]]; then
                attrs="${attrs},faSystem"
            fi
            echo "$attrs"
        else
            return 1
        fi
    else
        # Fallback without stat
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

    # Invalid characters for filenames (POSIX)
    local invalid_chars="/"
    if [[ "$use_wildcards" == "false" ]]; then
        invalid_chars="$invalid_chars*?"
    fi

    # Check for invalid characters
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

    # Invalid characters for paths (POSIX)
    local invalid_chars=""
    if [[ "$use_wildcards" == "false" ]]; then
        invalid_chars="*?"
    fi

    # Check for invalid characters
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

    # Invalid characters: control chars (0-31), /, and ~ on some systems
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

    # Invalid characters: control chars and wildcards
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

    # Use bash pattern matching
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

echo "tpath_extra functions loaded successfully"
