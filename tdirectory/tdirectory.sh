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
tdirectory._get_dirs_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    local directory_path
    for directory_path in "$dir"/*/; do
        if [[ -d "$directory_path" ]]; then
            local base
            base=$(basename "$directory_path")
            if [[ "$base" == $pattern ]]; then
                echo "${directory_path%/}"
            fi
            tdirectory._get_dirs_recursive "${directory_path%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Helper function for recursive file listing
tdirectory._get_files_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    local file_path
    for file_path in "$dir"/*; do
        if [[ -f "$file_path" ]]; then
            local base
            base=$(basename "$file_path")
            if [[ "$base" == $pattern ]]; then
                echo "$file_path"
            fi
        elif [[ -d "$file_path" ]]; then
            tdirectory._get_files_recursive "${file_path%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Helper function for recursive filesystem entries listing
tdirectory._get_entries_recursive() {
    local dir="$1"
    local pattern="$2"
    local old_extglob
    old_extglob=$(shopt -p extglob)
    shopt -s extglob
    local entry_path
    for entry_path in "$dir"/*; do
        if [[ -f "$entry_path" || -d "$entry_path" ]]; then
            local base
            base=$(basename "$entry_path")
            if [[ "$base" == $pattern ]]; then
                echo "$entry_path"
            fi
        fi
        if [[ -d "$entry_path" ]]; then
            tdirectory._get_entries_recursive "${entry_path%/}" "$pattern"
        fi
    done
    eval "$old_extglob"
}

# Remove helper names leaked by older sourced versions of this module.
unset -f get_dirs_recursive get_files_recursive get_entries_recursive 2>/dev/null || true

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
        local directory_path
        for directory_path in "$dir_path"/*/; do
            if [[ -d "$directory_path" ]]; then
                local base
                base=$(basename "$directory_path")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "${directory_path%/}"
                fi
            fi
        done
    else
        # Recursive
        tdirectory._get_dirs_recursive "$dir_path" "$pattern"
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
        local file_path
        for file_path in "$dir_path"/*; do
            if [[ -f "$file_path" ]]; then
                local base
                base=$(basename "$file_path")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "$file_path"
                fi
            fi
        done
    else
        # Recursive
        tdirectory._get_files_recursive "$dir_path" "$pattern"
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
        local entry_path
        for entry_path in "$dir_path"/*; do
            if [[ -e "$entry_path" ]]; then
                local base
                base=$(basename "$entry_path")
                # Pattern match
                if [[ "$base" == $pattern ]]; then
                    echo "$entry_path"
                fi
            fi
        done
    else
        # Recursive
        tdirectory._get_entries_recursive "$dir_path" "$pattern"
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

    if [[ ! -d "$path" ]]; then
        return 1
    fi

    if [[ "$attributes" == *"faReadOnly"* ]]; then
        chmod a-w "$path" 2>/dev/null || return 1
    else
        chmod u+w "$path" 2>/dev/null || return 1
    fi
}

tdirectory._format_time() {
    local path="$1"
    local stat_field="$2"
    local utc="${3:-false}"
    local epoch date_arg

    [[ -d "$path" ]] || return 1
    epoch=$(stat -c "$stat_field" "$path" 2>/dev/null) || return 1
    if [[ "$stat_field" == "%W" && "$epoch" == "-1" ]]; then
        epoch=$(stat -c "%Y" "$path" 2>/dev/null) || return 1
    fi
    [[ "$epoch" =~ ^-?[0-9]+$ ]] || return 1

    if [[ "$utc" == "true" ]]; then
        date_arg="-u"
    else
        date_arg=""
    fi

    date $date_arg -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || return 1
}

tdirectory._touch_time() {
    local path="$1"
    local time_value="$2"
    local touch_flag="$3"
    local utc="${4:-false}"
    local date_arg timestamp

    [[ -d "$path" ]] || return 1
    [[ -n "$time_value" ]] || return 1

    if [[ "$utc" == "true" ]]; then
        date_arg="-u"
    else
        date_arg=""
    fi

    if [[ "$time_value" =~ ^[0-9]+$ ]]; then
        timestamp=$(date $date_arg -d "@$time_value" +%Y%m%d%H%M.%S 2>/dev/null) || return 1
    else
        timestamp=$(date $date_arg -d "$time_value" +%Y%m%d%H%M.%S 2>/dev/null) || return 1
    fi

    touch "$touch_flag" -t "$timestamp" "$path" 2>/dev/null
}

# Define tdirectory.getCreationTime function
tdirectory.getCreationTime() {
    local path="$1"
    tdirectory._format_time "$path" "%W" false
}

# Define tdirectory.setCreationTime function
tdirectory.setCreationTime() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-m" false
}

# Define tdirectory.getCreationTimeUtc function
tdirectory.getCreationTimeUtc() {
    local path="$1"
    tdirectory._format_time "$path" "%W" true
}

# Define tdirectory.setCreationTimeUtc function
tdirectory.setCreationTimeUtc() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-m" true
}

# Define tdirectory.getLastAccessTime function
tdirectory.getLastAccessTime() {
    local path="$1"
    tdirectory._format_time "$path" "%X" false
}

# Define tdirectory.setLastAccessTime function
tdirectory.setLastAccessTime() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-a" false
}

# Define tdirectory.getLastAccessTimeUtc function
tdirectory.getLastAccessTimeUtc() {
    local path="$1"
    tdirectory._format_time "$path" "%X" true
}

# Define tdirectory.setLastAccessTimeUtc function
tdirectory.setLastAccessTimeUtc() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-a" true
}

# Define tdirectory.getLastWriteTime function
tdirectory.getLastWriteTime() {
    local path="$1"
    tdirectory._format_time "$path" "%Y" false
}

# Define tdirectory.setLastWriteTime function
tdirectory.setLastWriteTime() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-m" false
}

# Define tdirectory.getLastWriteTimeUtc function
tdirectory.getLastWriteTimeUtc() {
    local path="$1"
    tdirectory._format_time "$path" "%Y" true
}

# Define tdirectory.setLastWriteTimeUtc function
tdirectory.setLastWriteTimeUtc() {
    local path="$1"
    local time="$2"
    tdirectory._touch_time "$path" "$time" "-m" true
}

tdirectory._register_kklass_class() {
    local -a tdirectory_methods=(
        createDirectory delete exists copy isEmpty move isRelativePath getDirectoryRoot
        getParent getCurrentDirectory setCurrentDirectory getLogicalDrives getDirectories
        getFiles getFileSystemEntries getAttributes setAttributes getCreationTime
        setCreationTime getCreationTimeUtc setCreationTimeUtc getLastAccessTime
        setLastAccessTime getLastAccessTimeUtc setLastAccessTimeUtc getLastWriteTime
        setLastWriteTime getLastWriteTimeUtc setLastWriteTimeUtc
    )
    kk.register_static_methods "tdirectory" "tdirectory" "TDirectory" "${tdirectory_methods[@]}"
}

tdirectory._register_kklass_class
unset -f tdirectory._register_kklass_class
