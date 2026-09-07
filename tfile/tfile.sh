#!/bin/bash

# Re-source guard: the constant below is readonly, and the class only needs to
# be built once per process (X-SETU / decision D7).
if [[ -n "${_TFILE_SOURCED:-}" ]]; then
    return
fi
declare -g _TFILE_SOURCED=1

# Locale self-heal (decision D6, kcl/README.md 1.6). Character semantics are
# part of this unit's contract: ${#s} must count characters and a slurped file
# must not be mangled. An empty environment means the C locale.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TFILE_DIR/../../kklass/kklass_pascal.sh"

# tpath carries the SHARED filesystem helpers (R13) - _statTime, _touchTime,
# _chmodAttrs, _attrs - so tfile and tdirectory implement timestamps and
# attributes exactly once, and the path parsers (_fileName, _dirName) that
# understand both separators (decision D5). It also carries the return helper
# _ret / _retBool that both units answer through.
source "$TFILE_DIR/../tpath/tpath.sh"

# Check for cp command availability.
# NOTE: a top-level (process-wide) global, NOT a `static var` - a class without
# static variables gets the thin, capture-free dispatcher on every bash (see
# tpath.sh). readonly: computed once, never mutated.
if command -v cp >/dev/null 2>&1; then
    TFILE_USE_CP=true
else
    TFILE_USE_CP=false
fi
readonly TFILE_USE_CP

# ---------------------------------------------------------------------------
# TFile: a static utility namespace (Free Pascal's TFile / .NET System.IO.File).
#
# ---- Return contract (decision D3, kcl/README.md 1.1) ----------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )`
# the value is printed exactly once, so every `v=$(tfile.x ...)` caller keeps
# working. Predicates answer with their exit status as well (R8), with
# true/false still in RESULT:
#
#     tfile.readAllText "$f"; use "$RESULT"        # no fork
#     text="$(tfile.readAllText "$f")"             # still works, forks
#     if tfile.exists "$f"; then ...               # rc; RESULT is true/false
#
# Errors are rc 1 + RESULT='' and print nothing (kcl/README.md 1.2); a
# malformed CALL - a bad output-variable name - is rc 2 (1.7).
#
# Members are `static proc` and answer through tpath._ret rather than being
# `static func` + kk._return, because kklass's THIN static dispatcher re-prints
# kk._return's value on a DIRECT call too; see the note in tpath.sh.
#
# ---- Reading a file byte-faithfully ---------------------------------------
# `$(tfile.readAllText f)` strips trailing newlines - that is bash's `$( )`,
# not this unit. readAllText leaves the faithful text in RESULT, and
# `readAllTextVar FILE NAME` fills a caller variable directly, fork-free
# (R13 / finding G6-18). A NUL byte cannot be held in a bash variable at all;
# readAllText/readAllBytes stop there, which is documented in README.md.
#
# ---- Internal helpers ------------------------------------------------------
# tfile._* are NOT class members: plain functions, so members share logic
# without a nested `$( )`. They answer in the caller's local `__tf_r`; the
# `__tf_*` prefix is reserved for this unit, as `__tp_*` is for tpath.
# ---------------------------------------------------------------------------
class tfile
    public
        # writing / creation
        static proc appendAllText
        static proc appendText
        static proc create
        static proc createSymLink
        static proc createText
        static proc writeAllBytes
        # existence / lifecycle
        static proc exists
        static proc delete
        static proc copy
        static proc move
        static proc replace
        # encryption
        static proc encrypt
        static proc decrypt
        # attributes
        static proc fileAttributesToInteger
        static proc integerToFileAttributes
        static proc getAttributes
        static proc setAttributes
        # timestamps
        static proc getCreationTime
        static proc getCreationTimeUtc
        static proc getLastAccessTime
        static proc getLastAccessTimeUtc
        static proc getLastWriteTime
        static proc getLastWriteTimeUtc
        static proc setCreationTime
        static proc setCreationTimeUtc
        static proc setLastAccessTime
        static proc setLastAccessTimeUtc
        static proc setLastWriteTime
        static proc setLastWriteTimeUtc
        # links
        static proc getSymLinkTarget
        # opening / reading
        static proc open
        static proc openRead
        static proc openText
        static proc openWrite
        static proc readAllBytes
        static proc readAllLines
        static proc readAllText
        static proc readAllTextVar
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# -> __tf_r = the whole content of file $1, fork-free and byte-faithful up to
#    the first NUL. `read -d ''` returns 1 at EOF while still having filled the
#    variable, which is why its status is discarded and the file is checked
#    first (finding G6-18: the old body was `$(cat -- "$1")`, a fork that also
#    ate every trailing newline).
tfile._slurp() {
    __tf_r=""
    if [[ ! -f "$1" ]]; then
        return 1
    fi
    IFS= read -r -d '' __tf_r < "$1" || :
    return 0
}

# -> __tf_r = the directory holding file $1 ("." when it has none). Understands
#    both separators (G6-26: `${file%/*}` only understood `/`).
tfile._parentDir() {
    local __tp_r
    tpath._dirName "$1"
    __tf_r="$__tp_r"
    if [[ -z "$__tf_r" ]]; then
        __tf_r="."
    fi
}

tfile._crypto_password() {
    local password="${1:-${TFILE_CRYPTO_PASSWORD:-}}"
    [[ -n "$password" ]] || return 1
    REPLY="$password"
}

tfile._crypt_file() {
    local mode="$1" file="$2" password_arg="${3:-}"
    local password tmp_file __tf_r
    [[ -f "$file" ]] || return 1
    tfile._crypto_password "$password_arg" || return 1
    password="$REPLY"
    # Unpredictable temp file in the SAME directory (so the final mv is atomic
    # on the same filesystem). The old "${file}.tmp.$$" name was predictable
    # and racy: an attacker could pre-create/symlink it before openssl wrote.
    tfile._parentDir "$file"
    tmp_file=$(mktemp "$__tf_r/.tfile_crypt.XXXXXXXX") || return 1
    if TFILE_CRYPTO_PASSWORD="$password" openssl enc $mode -aes-256-cbc -salt -pbkdf2 \
        -in "$file" -out "$tmp_file" -pass env:TFILE_CRYPTO_PASSWORD 2>/dev/null; then
        mv -- "$tmp_file" "$file"
    else
        rm -f -- "$tmp_file"
        return 1
    fi
}

# ===========================================================================
# Method bodies (real bash functions; extracted by `build`)
# ===========================================================================

# ---- writing / creation ---------------------------------------------------

tfile.appendAllText() {
    local file="${1:-}" text="${2:-}"
    if [[ -z "$file" ]]; then
        tpath._ret "" 1
        return 1
    fi
    # printf, never echo: `-n`/`-e`/`-neE` are DATA (X-ECHO, G6-03).
    printf '%s' "$text" >> "$file" || { tpath._ret "" 1; return 1; }
    tpath._ret ""
}

tfile.appendText() {
    local file="${1:-}"
    if ! : >> "$file" 2>/dev/null; then
        tpath._ret "" 1
        return 1
    fi
    tpath._ret "$file"
}

tfile.create() {
    local file="${1:-}"
    if ! : > "$file" 2>/dev/null; then
        tpath._ret "" 1
        return 1
    fi
    tpath._ret ""
}

tfile.createText() {
    local file="${1:-}"
    if ! : > "$file" 2>/dev/null; then
        tpath._ret "" 1
        return 1
    fi
    tpath._ret "$file"
}

# G6-05: the old body handed POSIX paths to `cmd /c mklink`, which cannot read
# them, so this NEVER worked on MSYS - and `$(uname -s)` forked on every call
# (G6-16). MSYS/cygwin `ln -s` defaults to COPY mode: it reports success while
# producing a copy, so the result is verified with `-L` and a copy is undone.
# `MSYS=winsymlinks:native` asks the runtime for a real NTFS symlink, which
# needs Developer Mode or an elevated shell; `cmd mklink` needs the same
# privilege and does NOT accept the unprivileged-create flag, so it is not
# used as a fallback (measured on this box: mklink answers "insufficient
# privileges" where `ln -s` succeeds).
tfile.createSymLink() {
    local link="${1:-}" target="${2:-}" link_dir __tf_r
    if [[ -z "$link" ]]; then
        tpath._retBool 1
        return $?
    fi
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        tpath._retBool 1
        return $?
    fi
    # The link path must be free. Without this `ln -s tgt DIR` puts the link
    # INSIDE the directory and reports success, and the copy-mode cleanup
    # below would then delete that directory.
    if [[ -e "$link" || -L "$link" ]]; then
        tpath._retBool 1
        return $?
    fi
    tfile._parentDir "$link"
    link_dir="$__tf_r"
    if [[ ! -d "$link_dir" ]]; then
        tpath._retBool 1
        return $?
    fi
    if (( __TPATH_IS_WINDOWS )); then
        if MSYS=winsymlinks:native CYGWIN=winsymlinks:native \
             ln -s -- "$target" "$link" 2>/dev/null; then
            if [[ -L "$link" ]]; then
                tpath._retBool 0
                return $?
            fi
            # copy mode: `ln` reported success and produced a COPY. Only this
            # branch may delete, and only what this call has just created —
            # `ln -s` never overwrites, so an existing path at $link made the
            # command fail above and is left alone.
            rm -rf -- "$link" 2>/dev/null || :
        fi
        tpath._retBool 1
        return $?
    fi
    if ln -s -- "$target" "$link" 2>/dev/null; then
        tpath._retBool 0
    else
        tpath._retBool 1
    fi
}

# A bash variable cannot hold a NUL byte, so "bytes" here means "the string the
# caller passed" - documented in README.md. printf '%s', never echo (X-ECHO).
tfile.writeAllBytes() {
    local file="${1:-}" data="${2:-}"
    if ! printf '%s' "$data" > "$file" 2>/dev/null; then
        tpath._ret "" 1
        return 1
    fi
    tpath._ret ""
}

# ---- existence / lifecycle ------------------------------------------------

tfile.exists() {
    local file="${1:-}" follow="${2:-true}"
    if [[ "$follow" == "true" ]]; then
        if [[ -f "$file" ]]; then
            tpath._retBool 0
        else
            tpath._retBool 1
        fi
    else
        if [[ -L "$file" || -f "$file" ]]; then
            tpath._retBool 0
        else
            tpath._retBool 1
        fi
    fi
}

# `--`, so a leading-dash path is a path and not an option (G6-11). On a
# symlink this removes the LINK, never the target (R13).
tfile.delete() {
    if rm -- "${1:-}" 2>/dev/null; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.copy() {
    local src="${1:-}" dest="${2:-}" overwrite="${3:-false}"
    if [[ "$overwrite" == "false" && -e "$dest" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if [[ "$TFILE_USE_CP" == "true" ]]; then
        cp -- "$src" "$dest" 2>/dev/null || { tpath._ret "" 1; return 1; }
    else
        cat -- "$src" > "$dest" 2>/dev/null || { tpath._ret "" 1; return 1; }
    fi
    tpath._ret ""
}

tfile.move() {
    local src="${1:-}" dest="${2:-}"
    if [[ -e "$dest" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if mv -- "$src" "$dest" 2>/dev/null; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

# .NET File.Replace / FPC: the destination is REPLACED BY the source, the old
# destination becomes the backup and the SOURCE IS CONSUMED. G6-19: the old
# body copied and left the source in place, so a "replace" loop kept both.
tfile.replace() {
    local src="${1:-}" dest="${2:-}" backup="${3:-}"
    if [[ ! -f "$src" ]] || [[ ! -f "$dest" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if [[ -n "$backup" ]]; then
        if ! cp -- "$dest" "$backup" 2>/dev/null; then
            tpath._ret "" 1
            return 1
        fi
    fi
    if mv -f -- "$src" "$dest" 2>/dev/null; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

# ---- encryption -----------------------------------------------------------

tfile.encrypt() {
    if tfile._crypt_file "" "${1:-}" "${2:-}"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.decrypt() {
    if tfile._crypt_file "-d" "${1:-}" "${2:-}"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

# ---- attributes -----------------------------------------------------------

tfile.fileAttributesToInteger() {
    local attrs="${1:-}" value=0 attr_name
    attrs="${attrs#[}"
    attrs="${attrs%]}"
    attrs="${attrs// /}"
    if [[ -z "$attrs" ]]; then
        tpath._ret "0"
        return 0
    fi
    local attr_parts               # X-LOCALS (G6-23)
    IFS=',' read -ra attr_parts <<< "$attrs"
    for attr_name in "${attr_parts[@]}"; do
        attr_name="${attr_name#fa}"
        case "$attr_name" in
            ReadOnly)  value=$((value | 1)) ;;
            Hidden)    value=$((value | 2)) ;;
            System)    value=$((value | 4)) ;;
            Directory) value=$((value | 16)) ;;
            Archive)   value=$((value | 32)) ;;
        esac
    done
    tpath._ret "$value"
}

tfile.integerToFileAttributes() {
    # G6-06 (X-INJ, decision D1): `int` reaches `-eq` and `$(( ))` below, both
    # of which evaluate arithmetically - integerToFileAttributes
    # 'x[$(touch pwn)]' ran the command.
    local int attrs=""
    if ! kk.isInt "${1:-}" int; then
        tpath._ret "" 1
        return 1
    fi
    if (( int == 0 )); then
        tpath._ret "[]"
        return 0
    fi
    if (( int & 1 ));  then attrs+="ReadOnly, ";  fi
    if (( int & 2 ));  then attrs+="Hidden, ";    fi
    if (( int & 4 ));  then attrs+="System, ";    fi
    if (( int & 16 )); then attrs+="Directory, "; fi
    if (( int & 32 )); then attrs+="Archive, ";   fi
    attrs="${attrs%, }"
    tpath._ret "[$attrs]"
}

# G6-07: this used to answer the literal "faNormal" for every file, including
# a chmod 444 one. The real work is tpath._attrs, shared with tdirectory (R13).
tfile.getAttributes() {
    local file="${1:-}" follow="${2:-true}" __tp_r
    if [[ "$follow" == "true" ]]; then
        if [[ ! -f "$file" ]]; then
            tpath._ret "" 1
            return 1
        fi
    else
        if [[ ! -e "$file" && ! -L "$file" ]]; then
            tpath._ret "" 1
            return 1
        fi
    fi
    if tpath._attrs "$file" "$follow"; then
        tpath._ret "$__tp_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

# G6-07: a silent no-op (`: ;`) that answered rc 0. tdirectory did this for
# real; R13 makes both go through the same helper.
tfile.setAttributes() {
    local file="${1:-}"
    if [[ ! -f "$file" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._chmodAttrs "$file" "${2:-}"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

# ---- timestamps -----------------------------------------------------------
# All six getters go through tpath._statTime (%W falls back to %Y when the
# filesystem has no birth time - G6-26); the four settable ones go through
# tpath._touchTime, which uses `touch -d @epoch` so a *Utc value is stored as
# the instant it names (G6-08). Creation time is NOT settable: POSIX has no
# API and Windows' is not reachable through touch, so it answers rc 1 the way
# .NET does on Unix (R13).

tfile._getTime() {   # STAT-FIELD UTC PATH
    local __tp_r
    # No existence probe: tpath._statTime answers rc 1 for a missing path on
    # its own, and every extra access rewrites a stale NTFS access time (see
    # the note there). The getters answer for a directory too — test 013 pins
    # that — so a `-f` guard would be wrong here anyway; only the SETTERS are
    # file-shaped.
    if tpath._statTime "$3" "$1" "$2"; then
        tpath._ret "$__tp_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile._setTime() {   # TOUCH-FLAG UTC PATH VALUE
    if [[ ! -f "$3" && ! -L "$3" ]]; then
        tpath._ret "" 1
        return 1
    fi
    if tpath._touchTime "$3" "$4" "$1" "$2"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.getCreationTime()       { tfile._getTime "%W" false "${1:-}"; }
tfile.getCreationTimeUtc()    { tfile._getTime "%W" true  "${1:-}"; }
tfile.getLastAccessTime()     { tfile._getTime "%X" false "${1:-}"; }
tfile.getLastAccessTimeUtc()  { tfile._getTime "%X" true  "${1:-}"; }
tfile.getLastWriteTime()      { tfile._getTime "%Y" false "${1:-}"; }
tfile.getLastWriteTimeUtc()   { tfile._getTime "%Y" true  "${1:-}"; }

tfile.setCreationTime()       { tpath._ret "" 1; return 1; }
tfile.setCreationTimeUtc()    { tpath._ret "" 1; return 1; }
tfile.setLastAccessTime()     { tfile._setTime "-a" false "${1:-}" "${2:-}"; }
tfile.setLastAccessTimeUtc()  { tfile._setTime "-a" true  "${1:-}" "${2:-}"; }
tfile.setLastWriteTime()      { tfile._setTime "-m" false "${1:-}" "${2:-}"; }
tfile.setLastWriteTimeUtc()   { tfile._setTime "-m" true  "${1:-}" "${2:-}"; }

# ---- links ----------------------------------------------------------------

tfile.getSymLinkTarget() {
    local target
    if target="$(readlink -- "${1:-}" 2>/dev/null)"; then
        tpath._ret "$target"
    else
        tpath._ret "" 1
        return 1
    fi
}

# ---- opening / reading ----------------------------------------------------

tfile.open() {
    local file="${1:-}" mode="${2:-}"
    case "$mode" in
        fmOpenRead|fmOpenReadWrite)
            if [[ ! -f "$file" ]]; then
                tpath._ret "" 1
                return 1
            fi
            tpath._ret "$file"
            ;;
        fmOpenWrite)
            if ! : > "$file" 2>/dev/null; then
                tpath._ret "" 1
                return 1
            fi
            tpath._ret "$file"
            ;;
        *)
            tpath._ret "" 1
            return 1
            ;;
    esac
}

tfile.openRead() {
    if [[ -f "${1:-}" ]]; then
        tpath._ret "$1"
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.openText() {
    if [[ -f "${1:-}" ]]; then
        tpath._ret "$1"
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.openWrite() {
    local file="${1:-}"
    if ! : > "$file" 2>/dev/null; then
        tpath._ret "" 1
        return 1
    fi
    tpath._ret "$file"
}

tfile.readAllBytes() {
    local __tf_r
    if tfile._slurp "${1:-}"; then
        tpath._ret "$__tf_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.readAllText() {
    local __tf_r
    if tfile._slurp "${1:-}"; then
        tpath._ret "$__tf_r"
    else
        tpath._ret "" 1
        return 1
    fi
}

# readAllLines FILE [OUTARRAY]
# Without OUTARRAY: the whole text in RESULT (as readAllText).
# With OUTARRAY: the caller's array is filled line by line and RESULT is the
# line COUNT (kcl/README.md 1.7) - call it DIRECTLY, `$( )` throws the fill
# away. A bad output name is rc 2.
tfile.readAllLines() {
    local file="${1:-}" out="${2:-}" __tf_r
    if [[ -z "$out" ]]; then
        if tfile._slurp "$file"; then
            tpath._ret "$__tf_r"
        else
            tpath._ret "" 1
            return 1
        fi
        return 0
    fi
    if tpath._badOutName "$out"; then
        if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
            printf '%s\n' "Error: tfile.readAllLines: bad output array name '$out'" >&2
        fi
        tpath._ret "" 2
        return 2
    fi
    if [[ ! -f "$file" ]]; then
        tpath._ret "" 1
        return 1
    fi
    mapfile -t "$out" < "$file" || { tpath._ret "" 1; return 1; }
    local -n __tf_out="$out"
    tpath._ret "${#__tf_out[@]}"
}

# readAllTextVar FILE NAME (R13 / G6-18): the byte-faithful read, fork-free,
# trailing newlines preserved. RESULT is the character count; the text itself
# goes into NAME, so nothing large travels through a command substitution.
tfile.readAllTextVar() {
    local file="${1:-}" out="${2:-}"
    if tpath._badOutName "$out"; then
        if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
            printf '%s\n' "Error: tfile.readAllTextVar: bad output variable name '$out'" >&2
        fi
        tpath._ret "" 2
        return 2
    fi
    if [[ ! -f "$file" ]]; then
        tpath._ret "" 1
        return 1
    fi
    IFS= read -r -d '' "$out" < "$file" || :
    local -n __tf_out="$out"
    tpath._ret "${#__tf_out}"
}

# Finalize: extract the bodies above into the `tfile` class and generate the
# thin static dispatchers (see the header note). The class is named `tfile`,
# so the public API stays `tfile.<Method>` and the kklass metadata array
# `tfile_class_static_methods` is populated as before.
build tfile
