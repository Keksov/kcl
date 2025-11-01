#!/bin/bash
# kcl/tpath_minimal.sh - TPath with essential methods only

# Source kklass system
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../kklass/kklass.sh"

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

echo "tpath class created successfully"
