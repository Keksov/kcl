#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TDIRECTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TDIRECTORY_DIR/../../kklass/kklass.sh"

# Source tpath module (required by several tdirectory functions)
source "$TDIRECTORY_DIR/../tpath/tpath.sh"

# Define the tdirectory class
#defineClass "tdirectory" ""

# Define tdirectory.createDirectory function
tdirectory.createDirectory() {
    local dir_path="$1"
    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi
    mkdir -p "$dir_path"
}

# Define tdirectory.delete function
tdirectory.delete() {
    local dir_path="$1"
    local recursive="${2:-true}"

    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$dir_path" ]]; then
        echo "Error: Directory does not exist: $dir_path" >&2
        return 1
    fi

    if [[ "$recursive" == "true" ]]; then
        rm -rf "$dir_path"
    else
        # Check if directory is empty
        if [[ -z "$(ls -A "$dir_path" 2>/dev/null)" ]]; then
            rmdir "$dir_path"
        else
            echo "Error: Directory is not empty: $dir_path" >&2
            return 1
        fi
    fi
}

# Define tdirectory.exists function
tdirectory.exists() {
    local dir_path="$1"
    if [[ -d "$dir_path" ]]; then
        echo -n "true"
    else
        echo -n "false"
    fi
}

# Define tdirectory.copy function
tdirectory.copy() {
    local source_dir="$1"
    local dest_dir="$2"

    if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
        echo "Error: Source and destination paths cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$source_dir" ]]; then
        echo "Error: Source directory does not exist: $source_dir" >&2
        return 1
    fi

    cp -r "$source_dir" "$dest_dir"
}

# Define tdirectory.isEmpty function
tdirectory.isEmpty() {
    local dir_path="$1"
    if [[ -z "$dir_path" || ! -d "$dir_path" ]]; then
    echo -n "false"
    else
    if [[ -z "$(ls -A "$dir_path" 2>/dev/null)" ]]; then
    echo -n "true"
    else
    echo -n "false"
    fi
    fi
}

# Define tdirectory.move function
tdirectory.move() {
    local source_dir="$1"
    local dest_dir="$2"

    if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
        echo "Error: Source and destination paths cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$source_dir" ]]; then
        echo "Error: Source directory does not exist: $source_dir" >&2
        return 1
    fi

    mv "$source_dir" "$dest_dir"
}

# Define tdirectory.isRelativePath function
tdirectory.isRelativePath() {
    local path="$1"
    tpath.isRelativePath "$path"
}

# Define tdirectory.getDirectoryRoot function
tdirectory.getDirectoryRoot() {
    local path="$1"
    tpath.getPathRoot "$path"
}

# Define tdirectory.getParent function
tdirectory.getParent() {
    local path="$1"
    if [[ "$path" == "." ]]; then
        path="$(pwd)"
    fi
    tpath.getDirectoryName "$path"
}

# Define tdirectory.getCurrentDirectory function
tdirectory.getCurrentDirectory() {
    pwd
}

# Define tdirectory.setCurrentDirectory function
tdirectory.setCurrentDirectory() {
    local dir_path="$1"
    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi
    cd "$dir_path"
}

# Define tdirectory.getLogicalDrives function
tdirectory.getLogicalDrives() {
    case "$(uname -s)" in
        MINGW*|CYGWIN*|MSYS*)
            # Windows: return available drives
            local drives=""
            for letter in {C..Z}; do
                if [[ -d "/${letter,,}" ]]; then
                    drives="${drives}${letter}: "
                fi
            done
            echo "${drives% }"
            ;;
        *)
            # Unix: return root
            echo "/"
            ;;
    esac
}

# Helper function for recursive directory listing
get_dirs_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    for d in "$dir"/*/; do
        if [[ -d "$d" ]]; then
            local base
            base=$(basename "$d")
            if [[ "$base" == $pattern ]]; then
                echo "${d%/}"
            fi
            get_dirs_recursive "${d%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Helper function for recursive file listing
get_files_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    for f in "$dir"/*; do
        if [[ -f "$f" ]]; then
            local base
            base=$(basename "$f")
            if [[ "$base" == $pattern ]]; then
                echo "$f"
            fi
        elif [[ -d "$f" ]]; then
            get_files_recursive "${f%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Helper function for recursive filesystem entries listing
get_entries_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    for e in "$dir"/*; do
        if [[ -f "$e" || -d "$e" ]]; then
            local base
            base=$(basename "$e")
            if [[ "$base" == $pattern ]]; then
                echo "$e"
            fi
        fi
        if [[ -d "$e" ]]; then
            get_entries_recursive "${e%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Define tdirectory.getDirectories function
tdirectory.getDirectories() {
    local dir_path="$1"
    local pattern="${2:-*}"
    local search_option="${3:-TopDirectoryOnly}"

    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$dir_path" ]]; then
        echo "Error: Directory does not exist: $dir_path" >&2
        return 1
    fi

    # Enable extglob for pattern matching
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob

    if [[ "$search_option" == "TopDirectoryOnly" ]]; then
        # Top level only
        for d in "$dir_path"/*/; do
            if [[ -d "$d" ]]; then
                local base
                base=$(basename "$d")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "${d%/}"
                fi
            fi
        done
    else
        # Recursive
        get_dirs_recursive "$dir_path" "$pattern"
    fi

    # Restore extglob
    eval "$old_extglob"
}

# Define tdirectory.getFiles function
tdirectory.getFiles() {
    local dir_path="$1"
    local pattern="${2:-*}"
    local search_option="${3:-TopDirectoryOnly}"

    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$dir_path" ]]; then
        echo "Error: Directory does not exist: $dir_path" >&2
        return 1
    fi

    # Enable extglob for pattern matching
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob

    if [[ "$search_option" == "TopDirectoryOnly" ]]; then
        # Top level only
        for f in "$dir_path"/*; do
            if [[ -f "$f" ]]; then
                local base
                base=$(basename "$f")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "$f"
                fi
            fi
        done
    else
        # Recursive
        get_files_recursive "$dir_path" "$pattern"
    fi

    # Restore extglob
    eval "$old_extglob"
}

# Define tdirectory.getFileSystemEntries function
tdirectory.getFileSystemEntries() {
    local dir_path="$1"
    local pattern="${2:-*}"
    local search_option="${3:-TopDirectoryOnly}"

    if [[ -z "$dir_path" ]]; then
        echo "Error: Directory path cannot be empty" >&2
        return 1
    fi

    if [[ ! -d "$dir_path" ]]; then
        echo "Error: Directory does not exist: $dir_path" >&2
        return 1
    fi

    # Enable extglob for pattern matching
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob

    if [[ "$search_option" == "TopDirectoryOnly" ]]; then
        # Top level only
        for e in "$dir_path"/*; do
            if [[ -e "$e" ]]; then
                local base
                base=$(basename "$e")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "$e"
                fi
            fi
        done
    else
        # Recursive
        get_entries_recursive "$dir_path" "$pattern"
    fi

    # Restore extglob
    eval "$old_extglob"
}

# Define tdirectory.getAttributes function
tdirectory.getAttributes() {
    local path="$1"
    local follow_link="${2:-true}"
    tpath.getAttributes "$path" "$follow_link"
}

# Define tdirectory.setAttributes function
tdirectory.setAttributes() {
    local path="$1"
    local attributes="$2"
    # Stub: not implemented
    echo "setAttributes not implemented"
}

# Define tdirectory.getCreationTime function
tdirectory.getCreationTime() {
    local path="$1"
    # Use modification time as proxy for creation time
    if command -v stat >/dev/null 2>&1; then
        local mtime
        mtime=$(stat -c %Y "$path" 2>/dev/null)
        if [[ -n "$mtime" ]]; then
            date -d "@$mtime"
        else
            date
        fi
    else
        date
    fi
}

# Define tdirectory.setCreationTime function
tdirectory.setCreationTime() {
    local path="$1"
    local time="$2"
    # Use touch to set modification time
    touch -t "$(date -d "$time" +%Y%m%d%H%M.%S 2>/dev/null || date +%Y%m%d%H%M.%S)" "$path" 2>/dev/null || true
}

# Define tdirectory.getCreationTimeUtc function
tdirectory.getCreationTimeUtc() {
    local path="$1"
    # Use modification time as proxy
    if command -v stat >/dev/null 2>&1; then
        local mtime
        mtime=$(stat -c %Y "$path" 2>/dev/null)
        if [[ -n "$mtime" ]]; then
            date -u -d "@$mtime"
        else
            date -u
        fi
    else
        date -u
    fi
}

# Define tdirectory.setCreationTimeUtc function
tdirectory.setCreationTimeUtc() {
    local path="$1"
    local time="$2"
    # Same as setCreationTime
    tdirectory.setCreationTime "$path" "$time"
}

# Define tdirectory.getLastAccessTime function
tdirectory.getLastAccessTime() {
    local path="$1"
    if command -v stat >/dev/null 2>&1; then
        local atime
        atime=$(stat -c %X "$path" 2>/dev/null)
        if [[ -n "$atime" ]]; then
            date -d "@$atime"
        else
            date
        fi
    else
        date
    fi
}

# Define tdirectory.setLastAccessTime function
tdirectory.setLastAccessTime() {
    local path="$1"
    local time="$2"
    touch -a -t "$(date -d "$time" +%Y%m%d%H%M.%S 2>/dev/null || date +%Y%m%d%H%M.%S)" "$path" 2>/dev/null || true
}

# Define tdirectory.getLastAccessTimeUtc function
tdirectory.getLastAccessTimeUtc() {
    local path="$1"
    if command -v stat >/dev/null 2>&1; then
        local atime
        atime=$(stat -c %X "$path" 2>/dev/null)
        if [[ -n "$atime" ]]; then
            date -u -d "@$atime"
        else
            date -u
        fi
    else
        date -u
    fi
}

# Define tdirectory.setLastAccessTimeUtc function
tdirectory.setLastAccessTimeUtc() {
    local path="$1"
    local time="$2"
    tdirectory.setLastAccessTime "$path" "$time"
}

# Define tdirectory.getLastWriteTime function
tdirectory.getLastWriteTime() {
    local path="$1"
    if command -v stat >/dev/null 2>&1; then
        local mtime
        mtime=$(stat -c %Y "$path" 2>/dev/null)
        if [[ -n "$mtime" ]]; then
            date -d "@$mtime"
        else
            date
        fi
    else
        date
    fi
}

# Define tdirectory.setLastWriteTime function
tdirectory.setLastWriteTime() {
    local path="$1"
    local time="$2"
    touch -t "$(date -d "$time" +%Y%m%d%H%M.%S 2>/dev/null || date +%Y%m%d%H%M.%S)" "$path" 2>/dev/null || true
}

# Define tdirectory.getLastWriteTimeUtc function
tdirectory.getLastWriteTimeUtc() {
    local path="$1"
    if command -v stat >/dev/null 2>&1; then
        local mtime
        mtime=$(stat -c %Y "$path" 2>/dev/null)
        if [[ -n "$mtime" ]]; then
            date -u -d "@$mtime"
        else
            date -u
        fi
    else
        date -u
    fi
}

# Define tdirectory.setLastWriteTimeUtc function
tdirectory.setLastWriteTimeUtc() {
    local path="$1"
    local time="$2"
    tdirectory.setLastWriteTime "$path" "$time"
}

#echo "tdirectory class created successfully"
