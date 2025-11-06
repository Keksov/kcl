#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
# TDIRECTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "$TDIRECTORY_DIR/../../kklass/kklass.sh"



# Define tfile functions
tfile.appendAllText() {
local file="$1"
local text="$2"
echo -n "$text" >> "$file"
}

tfile.appendText() {
local file="$1"
if ! : >> "$file" 2>/dev/null; then
return 1
fi
echo "$1"
}

# Additional functions
tfile.exists() { [[ -e "$1" ]] && echo "true" || echo "false" ; }
tfile.delete() { rm "$1" 2>/dev/null ; }
tfile.copy() { local src="$1" dest="$2" overwrite="${3:-false}"; if [[ "$overwrite" == "false" && -e "$dest" ]]; then return 1; fi; cp "$src" "$dest" 2>/dev/null ; }
tfile.move() { mv "$1" "$2" 2>/dev/null ; }
tfile.create() { : > "$1" 2>/dev/null ; }
tfile.createSymLink() {
local link="$1"
local target="$2"
if [[ ! -e "$target" ]]; then
echo "false"
return
fi
local link_dir="$(dirname "$link")"
if [[ ! -d "$link_dir" ]]; then
echo "false"
return 1
fi
case "$(uname -s)" in
MINGW*|CYGWIN*|MSYS*)
    local dirflag=""
    if [[ -d "$target" ]]; then
        dirflag="/d"
    fi
    if cmd /c mklink $dirflag "$link" "$target" > /dev/null 2>&1; then
    echo "true"
    else
    echo "false"
return 1
fi
;;
*)
if ln -s "$target" "$link" 2>/dev/null; then
    echo "true"
        else
                echo "false"
                return 1
            fi
            ;;
    esac
}
tfile.createText() { if ! : > "$1" 2>/dev/null; then return 1; fi; echo "$1" ; }
tfile.decrypt() { cp "$1" "$2" 2>/dev/null ; }
tfile.encrypt() { cp "$1" "$2" 2>/dev/null ; }
tfile.fileAttributesToInteger() { echo "0" ; }
tfile.getAttributes() { echo "faNormal" ; }
tfile.getCreationTime() { stat -c "%w" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getCreationTimeUtc() { echo "2023-10-01 12:00:00" ; }
tfile.getLastAccessTime() { stat -c "%x" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getLastAccessTimeUtc() { echo "2023-10-01 12:00:00" ; }
tfile.getLastWriteTime() { stat -c "%y" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getLastWriteTimeUtc() { echo "2023-10-01 12:00:00" ; }
tfile.getSymLinkTarget() { readlink "$1" 2>/dev/null ; }
tfile.integerToFileAttributes() { echo "" ; }
tfile.open() { echo "$1" ; }
tfile.openRead() { echo "$1" ; }
tfile.openText() { echo "$1" ; }
tfile.openWrite() { echo "$1" ; }
tfile.readAllBytes() { cat "$1" 2>/dev/null ; }
tfile.readAllLines() { cat "$1" 2>/dev/null ; }
tfile.readAllText() { cat "$1" 2>/dev/null ; }
tfile.replace() { cp "$2" "$1" 2>/dev/null ; }
tfile.setAttributes() { : ; }
tfile.setCreationTime() { touch -t $(date -d "$2" +%Y%m%d%H%M 2>/dev/null) "$1" 2>/dev/null ; }
tfile.setCreationTimeUtc() { : ; }
tfile.setLastAccessTime() { touch -a -t $(date -d "$2" +%Y%m%d%H%M 2>/dev/null) "$1" 2>/dev/null ; }
tfile.setLastAccessTimeUtc() { : ; }
tfile.setLastWriteTime() { touch -m -t $(date -d "$2" +%Y%m%d%H%M 2>/dev/null) "$1" 2>/dev/null ; }
tfile.setLastWriteTimeUtc() { : ; }
tfile.writeAllBytes() { printf "%s" "$2" > "$1" ; }


#echo "tfile class created successfully"
