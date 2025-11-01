#!/bin/bash
# kcl/tpath.sh - Path manipulation utilities for kcl
# Inspired by Delphi's System.IOUtils.TPath

# Source kklass system for class support
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../kklass/kklass.sh"

# Define platform-specific constants
# POSIX systems (Linux/macOS) use '/' as separator
# Windows uses '\' as primary, '/' as alt
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        # Windows
        DIRECTORY_SEPARATOR_CHAR='\'
        ALT_DIRECTORY_SEPARATOR_CHAR='/'
        PATH_SEPARATOR=';'
        VOLUME_SEPARATOR_CHAR=':'
        ;;
    *)
        # POSIX (Linux/macOS)
        DIRECTORY_SEPARATOR_CHAR='/'
        ALT_DIRECTORY_SEPARATOR_CHAR='/'
        PATH_SEPARATOR=':'
        VOLUME_SEPARATOR_CHAR='/'
        ;;
esac

EXTENSION_SEPARATOR_CHAR='.'

# Define the tpath class with static methods
defineClass "tpath" "" \
    "static_method" "combine" '
        local path1="$1"
        local path2="$2"

        # If path2 is absolute/UNC, return it directly
        if [[ "$path2" =~ ^[/\\] ]] || [[ "$path2" =~ ^[A-Za-z]: ]]; then
            echo "$path2"
            return 0
        fi

        # Combine paths
        if [[ -z "$path1" ]]; then
            echo "$path2"
        elif [[ -z "$path2" ]]; then
            echo "$path1"
        else
            # Remove trailing separator from path1 if present
            path1="${path1%"$DIRECTORY_SEPARATOR_CHAR"}"
            path1="${path1%"$ALT_DIRECTORY_SEPARATOR_CHAR"}"

            # Add separator and path2
            echo "${path1}${DIRECTORY_SEPARATOR_CHAR}${path2}"
        fi
    ' \
    "static_method" "changeExtension" '
        local path="$1"
        local extension="$2"

        # Validate inputs
        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Find last extension separator
        local last_dot="${path##*.}"
        local base_path="${path%.*}"

        if [[ "$last_dot" == "$path" ]]; then
            # No extension found
            base_path="$path"
        fi

        # Add new extension if provided
        if [[ -n "$extension" ]]; then
            # Ensure extension starts with dot
            if [[ "$extension" != "."* ]]; then
                extension=".$extension"
            fi
            echo "${base_path}${extension}"
        else
            echo "$base_path"
        fi
    ' \
    "static_method" "getDirectoryName" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Remove trailing separators
        path="${path%"$DIRECTORY_SEPARATOR_CHAR"}"
        path="${path%"$ALT_DIRECTORY_SEPARATOR_CHAR"}"

        # Find last separator
        local dir_path="${path%["$DIRECTORY_SEPARATOR_CHAR""$ALT_DIRECTORY_SEPARATOR_CHAR"]*}"

        if [[ "$dir_path" == "$path" ]]; then
            # No directory part
            echo ""
        else
            echo "$dir_path"
        fi
    ' \
    "static_method" "getExtension" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Find last dot
        local filename="${path##*["$DIRECTORY_SEPARATOR_CHAR""$ALT_DIRECTORY_SEPARATOR_CHAR"]}"
        local extension="${filename##*.}"

        if [[ "$extension" == "$filename" ]]; then
            # No extension
            echo ""
        else
            echo ".$extension"
        fi
    ' \
    "static_method" "getFileName" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Extract filename after last separator
        local filename="${path##*["$DIRECTORY_SEPARATOR_CHAR""$ALT_DIRECTORY_SEPARATOR_CHAR"]}"
        echo "$filename"
    ' \
    "static_method" "getFileNameWithoutExtension" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Get filename first
        local filename
        filename="$(tpath.getFileName "$path")"

        if [[ -z "$filename" ]]; then
            echo ""
            return 0
        fi

        # Remove extension
        local name_without_ext="${filename%.*}"
        echo "$name_without_ext"
    ' \
    "static_method" "getFullPath" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Use readlink/realpath if available, otherwise basic resolution
        if command -v realpath >/dev/null 2>&1; then
            realpath "$path" 2>/dev/null || echo "$path"
        elif command -v readlink >/dev/null 2>&1; then
            readlink -f "$path" 2>/dev/null || echo "$path"
        else
            # Basic resolution for current directory
            if [[ "$path" != /* ]]; then
                echo "$(pwd)/$path"
            else
                echo "$path"
            fi
        fi
    ' \
    "static_method" "getPathRoot" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo ""
            return 0
        fi

        # Check for UNC path
        if [[ "$path" =~ ^[/\\][/\\] ]]; then
            # Find second separator
            local rest="${path#??}"
            local server_part="${rest%%["$DIRECTORY_SEPARATOR_CHAR""$ALT_DIRECTORY_SEPARATOR_CHAR"]*}"
            echo "//$server_part"
            return 0
        fi

        # Check for drive letter (Windows)
        if [[ "$path" =~ ^[A-Za-z]: ]]; then
            echo "${path:0:2}"
            return 0
        fi

        # Check for root directory
        if [[ "$path" =~ ^[/\\] ]]; then
            echo "/"
            return 0
        fi

        # No root
        echo ""
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
    ' \
    "static_method" "isPathRooted" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo "false"
            return 0
        fi

        # Check for absolute path indicators
        if [[ "$path" =~ ^[/\\] ]] || [[ "$path" =~ ^[A-Za-z]: ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "static_method" "isRelativePath" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo "true"  # Empty path is relative
            return 0
        fi

        local rooted
        rooted="$(tpath.isPathRooted "$path")"

        if [[ "$rooted" == "true" ]]; then
            echo "false"
        else
            echo "true"
        fi
    ' \
    "static_method" "isUNCPath" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo "false"
            return 0
        fi

        if [[ "$path" =~ ^[/\\][/\\] ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "static_method" "isUNCRooted" '
        local path="$1"

        # Same as isUNCPath for basic implementation
        tpath.isUNCPath "$path"
    ' \
    "static_method" "isDriveRooted" '
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
    ' \
    "static_method" "isExtendedPrefixed" '
        local path="$1"

        if [[ -z "$path" ]]; then
            echo "false"
            return 0
        fi

        # Windows extended prefix (\\?\)
        if [[ "$path" =~ ^[/\\][/\\]\? ]]; then
            echo "true"
        else
            echo "false"
        fi
    ' \
    "static_method" "getTempPath" '
        # Return system temp directory
        if [[ -n "$TMPDIR" ]]; then
            echo "$TMPDIR"
        elif [[ -n "$TEMP" ]]; then
            echo "$TEMP"
        elif [[ -n "$TMP" ]]; then
            echo "$TMP"
        else
            echo "/tmp"
        fi
    ' \
    "static_method" "getHomePath" '
        # Return user home directory
        echo "$HOME"
    ' \
    "static_method" "getDocumentsPath" '
        # Return documents directory (basic implementation)
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
    ' \
    "static_method" "getDownloadsPath" '
        # Return downloads directory
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
    ' \
    "static_method" "getTempFileName" '
        # Create a unique temporary file and return its path
        local temp_dir
        temp_dir="$(tpath.getTempPath)"

        local temp_file
        temp_file="$(mktemp "$temp_dir/tmp.XXXXXXXXXX" 2>/dev/null)"

        if [[ -z "$temp_file" ]]; then
            # Fallback if mktemp fails
            local timestamp
            timestamp="$(date +%s%N 2>/dev/null || date +%s)"
            temp_file="$temp_dir/tmp_$timestamp"
            touch "$temp_file" 2>/dev/null
        fi

        echo "$temp_file"
    ' \
    "static_method" "getGUIDFileName" '
        local use_separator="${1:-false}"

        # Generate a GUID-like string
        if command -v uuidgen >/dev/null 2>&1; then
            local guid
            guid="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]')"
            if [[ "$use_separator" == "false" ]]; then
                guid="${guid//-/}"
            fi
            echo "$guid"
        else
            # Fallback: generate pseudo-GUID
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
    ' \
    "static_method" "getRandomFileName" '
    # Generate a random filename
    local timestamp
    timestamp="$(date +%s%N 2>/dev/null || date +%s)"
    printf "tmp_%x_%04x" "$timestamp" "$RANDOM"
    ' 
    "static_method" "getAltDirectorySeparatorChar" '
        echo "$ALT_DIRECTORY_SEPARATOR_CHAR"
    ' 
    "static_method" "getDirectorySeparatorChar" '
        echo "$DIRECTORY_SEPARATOR_CHAR"
    ' 
    "static_method" "getExtensionSeparatorChar" '
        echo "$EXTENSION_SEPARATOR_CHAR"
    ' 
    "static_method" "getPathSeparator" '
        echo "$PATH_SEPARATOR"
    ' 
    "static_method" "getVolumeSeparatorChar" '
        echo "$VOLUME_SEPARATOR_CHAR"
    ' 
    "static_method" "driveExists" '
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
    ' 
    "static_method" "getAttributes" '
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
    ' 
    "static_method" "hasValidFileNameChars" '
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
    ' 
    "static_method" "hasValidPathChars" '
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
    ' 
    "static_method" "isValidFileNameChar" '
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
    ' 
    "static_method" "isValidPathChar" '
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
    ' 
    "static_method" "matchesPattern" '
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
    '

echo "tpath class created successfully"