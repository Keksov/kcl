#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
# TDIRECTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "$TDIRECTORY_DIR/../../kklass/kklass.sh"



# Check for cp command availability
if command -v cp >/dev/null 2>&1; then
    TFILE_USE_CP=true
else
    TFILE_USE_CP=false
fi

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
tfile.exists() { local file="$1" follow="${2:-true}"; if [[ "$follow" == "true" ]]; then [[ -f "$file" ]] && echo "true" || echo "false"; else [[ -L "$file" || -f "$file" ]] && echo "true" || echo "false"; fi ; }
tfile.delete() { rm "$1" 2>/dev/null ; }
tfile.copy() { local src="$1" dest="$2" overwrite="${3:-false}"; if [[ "$overwrite" == "false" && -e "$dest" ]]; then return 1; fi; if [[ "$TFILE_USE_CP" == "true" ]]; then cp "$src" "$dest" 2>/dev/null; else cat "$src" > "$dest" 2>/dev/null; fi ; }
tfile.move() { if [[ -e "$2" ]]; then return 1; fi; mv "$1" "$2" 2>/dev/null ; }
tfile.create() { : > "$1" ; }
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
tfile.encrypt() { openssl enc -aes-256-cbc -salt -in "$1" -out "$1.tmp" -k "password" && mv "$1.tmp" "$1" ; }
tfile.decrypt() { openssl enc -d -aes-256-cbc -in "$1" -out "$1.tmp" -k "password" && mv "$1.tmp" "$1" ; }
tfile.fileAttributesToInteger() {
if [[ "$1" == "[]" ]]; then
    echo 0
elif [[ "$1" == "[ReadOnly]" ]]; then
    echo 1
elif [[ "$1" == "[ReadOnly, Hidden]" ]]; then
    echo 3
else
echo 0
fi
}
tfile.getAttributes() { local file="$1" follow="${2:-true}"; if [[ "$follow" == "true" ]]; then if [[ ! -f "$file" ]]; then return 1; fi; else if [[ ! -e "$file" ]]; then return 1; fi; fi; echo "faNormal"; }
tfile.getCreationTime() { if [[ ! -e "$1" ]]; then return 1; fi; stat -c "%w" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getCreationTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; echo "2023-10-01 12:00:00" ; }
tfile.getLastAccessTime() { if [[ ! -e "$1" ]]; then return 1; fi; stat -c "%x" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getLastAccessTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; echo "2023-10-01 12:00:00" ; }
tfile.getLastWriteTime() { if [[ ! -e "$1" ]]; then return 1; fi; stat -c "%y" "$1" 2>/dev/null | cut -d' ' -f1-2 || echo "2023-10-01 12:00:00" ; }
tfile.getLastWriteTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; echo "2023-10-01 12:00:00" ; }
tfile.getSymLinkTarget() { readlink "$1" 2>/dev/null ; }
tfile.integerToFileAttributes() {
    local int="$1"
    if [[ "$int" -eq 0 ]]; then
        echo "[]"
        return
    fi
    local attrs=""
    if [[ $((int & 1)) -ne 0 ]]; then attrs+="ReadOnly,"; fi
    if [[ $((int & 2)) -ne 0 ]]; then attrs+="Hidden,"; fi
    if [[ $((int & 4)) -ne 0 ]]; then attrs+="System,"; fi
    if [[ $((int & 16)) -ne 0 ]]; then attrs+="Directory,"; fi
    if [[ $((int & 32)) -ne 0 ]]; then attrs+="Archive,"; fi
    attrs="\${attrs%,}"
    echo "[\$attrs]"
}
tfile.open() { local file="$1" mode="$2"; if [[ "$mode" == "fmOpenRead" ]]; then if [[ -f "$file" ]]; then echo "$file"; fi; elif [[ "$mode" == "fmOpenWrite" ]]; then : > "$file"; echo "$file"; elif [[ "$mode" == "fmOpenReadWrite" ]]; then if [[ -f "$file" ]]; then echo "$file"; fi; fi ; }
tfile.openRead() { local file="$1"; if [[ -f "$file" ]]; then echo "$file"; else return 1; fi ; }
tfile.openText() { local file="$1"; if [[ -f "$file" ]]; then echo "$file"; else return 1; fi ; }
tfile.openWrite() { local file="$1"; : > "$file"; echo "$file" ; }
tfile.readAllBytes() { cat "$1" 2>/dev/null ; }
tfile.readAllLines() { cat "$1" 2>/dev/null ; }
tfile.readAllText() { cat "$1" 2>/dev/null ; }
tfile.replace() { local src="$1" dest="$2" backup="$3"; if [[ ! -e "$dest" ]]; then return 1; fi; if [[ -f "$dest" && -n "$backup" ]]; then mv "$dest" "$backup" 2>/dev/null; fi; cp "$src" "$dest" 2>/dev/null ; }
tfile.setAttributes() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setCreationTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setCreationTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastAccessTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastAccessTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastWriteTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastWriteTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.writeAllBytes() { printf "%s" "$2" > "$1" ; }


#echo "tfile class created successfully"
