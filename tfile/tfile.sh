#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TFILE_DIR/../../kklass/kklass.sh"

# Public tfile.* functions are registered as kklass static methods at the end
# of this file, after all implementations have been defined.



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
tfile._crypto_password() {
local password="${1:-${TFILE_CRYPTO_PASSWORD:-}}"
[[ -n "$password" ]] || return 1
REPLY="$password"
}

tfile._crypt_file() {
local mode="$1" file="$2" password_arg="$3"
local password tmp_file dir
[[ -f "$file" ]] || return 1
tfile._crypto_password "$password_arg" || return 1
password="$REPLY"
# Unpredictable temp file in the SAME directory (so the final mv is atomic on
# the same filesystem). The old "${file}.tmp.$$" name was predictable and
# racy: an attacker could pre-create/symlink it before openssl wrote.
dir="${file%/*}"; [[ "$dir" == "$file" ]] && dir="."
tmp_file=$(mktemp "$dir/.tfile_crypt.XXXXXXXX") || return 1
if TFILE_CRYPTO_PASSWORD="$password" openssl enc $mode -aes-256-cbc -salt -pbkdf2 -in "$file" -out "$tmp_file" -pass env:TFILE_CRYPTO_PASSWORD 2>/dev/null; then
    mv "$tmp_file" "$file"
else
    rm -f "$tmp_file"
    return 1
fi
}

tfile.encrypt() { tfile._crypt_file "" "$1" "$2" ; }
tfile.decrypt() { tfile._crypt_file "-d" "$1" "$2" ; }
tfile.fileAttributesToInteger() {
local attrs="$1"
local value=0
local attr_name
attrs="${attrs#[}"
attrs="${attrs%]}"
attrs="${attrs// /}"
if [[ -z "$attrs" ]]; then
    echo 0
    return
fi
IFS=',' read -ra attr_parts <<< "$attrs"
for attr_name in "${attr_parts[@]}"; do
    attr_name="${attr_name#fa}"
    case "$attr_name" in
        ReadOnly) value=$((value | 1)) ;;
        Hidden) value=$((value | 2)) ;;
        System) value=$((value | 4)) ;;
        Directory) value=$((value | 16)) ;;
        Archive) value=$((value | 32)) ;;
    esac
done
echo "$value"
}
tfile.getAttributes() { local file="$1" follow="${2:-true}"; if [[ "$follow" == "true" ]]; then if [[ ! -f "$file" ]]; then return 1; fi; else if [[ ! -e "$file" ]]; then return 1; fi; fi; echo "faNormal"; }
tfile._format_time() {
local file="$1" stat_field="$2" utc="${3:-false}"
local epoch date_arg
[[ -e "$file" ]] || return 1
epoch=$(stat -c "$stat_field" "$file" 2>/dev/null) || return 1
[[ "$epoch" =~ ^-?[0-9]+$ ]] || return 1
if [[ "$utc" == "true" ]]; then
    date_arg="-u"
else
    date_arg=""
fi
date $date_arg -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || return 1
}

tfile.getCreationTime() { tfile._format_time "$1" "%W" false ; }
tfile.getCreationTimeUtc() { tfile._format_time "$1" "%W" true ; }
tfile.getLastAccessTime() { tfile._format_time "$1" "%X" false ; }
tfile.getLastAccessTimeUtc() { tfile._format_time "$1" "%X" true ; }
tfile.getLastWriteTime() { tfile._format_time "$1" "%Y" false ; }
tfile.getLastWriteTimeUtc() { tfile._format_time "$1" "%Y" true ; }
tfile.getSymLinkTarget() { readlink "$1" 2>/dev/null ; }
tfile.integerToFileAttributes() {
    local int="$1"
    if [[ "$int" -eq 0 ]]; then
        echo "[]"
        return
    fi
    local attrs=""
    if [[ $((int & 1)) -ne 0 ]]; then attrs+="ReadOnly, "; fi
    if [[ $((int & 2)) -ne 0 ]]; then attrs+="Hidden, "; fi
    if [[ $((int & 4)) -ne 0 ]]; then attrs+="System, "; fi
    if [[ $((int & 16)) -ne 0 ]]; then attrs+="Directory, "; fi
    if [[ $((int & 32)) -ne 0 ]]; then attrs+="Archive, "; fi
    attrs="${attrs%, }"
    echo "[$attrs]"
}
tfile.open() {
local file="$1" mode="$2"
case "$mode" in
    fmOpenRead)
        [[ -f "$file" ]] || return 1
        echo "$file"
        ;;
    fmOpenWrite)
        : > "$file" || return 1
        echo "$file"
        ;;
    fmOpenReadWrite)
        [[ -f "$file" ]] || return 1
        echo "$file"
        ;;
    *)
        return 1
        ;;
esac
}
tfile.openRead() { local file="$1"; if [[ -f "$file" ]]; then echo "$file"; else return 1; fi ; }
tfile.openText() { local file="$1"; if [[ -f "$file" ]]; then echo "$file"; else return 1; fi ; }
tfile.openWrite() { local file="$1"; : > "$file" || return 1; echo "$file" ; }
tfile.readAllBytes() { cat "$1" 2>/dev/null ; }
tfile.readAllLines() { cat "$1" 2>/dev/null ; }
tfile.readAllText() { cat "$1" 2>/dev/null ; }
tfile.replace() {
local src="$1" dest="$2" backup="$3"
[[ -f "$src" ]] || return 1
[[ -f "$dest" ]] || return 1
if [[ -n "$backup" ]]; then
    cp "$dest" "$backup" 2>/dev/null || return 1
fi
cp "$src" "$dest" 2>/dev/null
}
tfile.setAttributes() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setCreationTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setCreationTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastAccessTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastAccessTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastWriteTime() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.setLastWriteTimeUtc() { if [[ ! -e "$1" ]]; then return 1; fi; : ; }
tfile.writeAllBytes() { printf "%s" "$2" > "$1" ; }


tfile._register_kklass_class() {
    local -a tfile_methods=(
        appendAllText appendText exists delete copy move create createSymLink createText
        encrypt decrypt fileAttributesToInteger getAttributes getCreationTime
        getCreationTimeUtc getLastAccessTime getLastAccessTimeUtc getLastWriteTime
        getLastWriteTimeUtc getSymLinkTarget integerToFileAttributes open openRead
        openText openWrite readAllBytes readAllLines readAllText replace setAttributes
        setCreationTime setCreationTimeUtc setLastAccessTime setLastAccessTimeUtc
        setLastWriteTime setLastWriteTimeUtc writeAllBytes
    )
    kk.register_static_methods "tfile" "tfile" "TFile" "${tfile_methods[@]}"
}

tfile._register_kklass_class
unset -f tfile._register_kklass_class


#echo "tfile class created successfully"
