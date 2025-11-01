#!/bin/bash
# kcl/tpath_simple.sh - Simple TPath with minimal methods

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

# Define the tpath class with minimal methods
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
    '

echo "tpath class created successfully"
