#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tfile.sh}../../kbool.sh" || return
kk.unit tfile || return $__kk_unit_rc

# Locale self-heal (decision D6, kcl/README.md 1.6). Character semantics are
# part of this unit's contract: ${#s} must count characters and a slurped file
# must not be mangled. An empty environment means the C locale.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# A unit (kklass/USES_PLAN.md §7.4, phase U4): the two header lines at the
# top load kbool.sh when needed and make a repeated `source` a no-op, also
# under `set -eu` (they replaced the D7 re-source guard). Dependencies come
# through kk.uses.
kk.uses kklass_pascal || return

# tpath carries the SHARED filesystem helpers (R13) - _statTime, _touchTime,
# _chmodAttrs, _attrs - so tfile and tdirectory implement timestamps and
# attributes exactly once, and the path parsers (_fileName, _dirName) that
# understand both separators (decision D5). It also carries the return helper
# _ret / _retBool that both units answer through.
kk.uses tpath || return

# Check for cp command availability.
# NOTE: a top-level (process-wide) global, NOT a `static var` - a class without
# static variables gets the thin, capture-free dispatcher on every bash (see
# tpath.sh). readonly: computed once, never mutated.
# Assigned once per process (uses U4, pattern rule 10): a reload after
# `kk.unit --forget tfile` (U24') keeps the readonly constant instead of failing
# on `readonly variable` (under `set -e` that exited the caller). `${x@a}` is
# guarded by `${x+x}`: under `set -u` it is unbound for an unset name.
if [[ -z ${TFILE_USE_CP+x} || ${TFILE_USE_CP@a} != *r* ]]; then
    if command -v cp >/dev/null 2>&1; then
        TFILE_USE_CP=true
    else
        TFILE_USE_CP=false
    fi
    readonly TFILE_USE_CP
fi

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

# ---- encryption: the KBTF1 format (launch L34-F2, owner decision OG9) -----
# An encrypted file is, byte for byte (README.md "Encryption"):
#
#     "KBTF1" (5) | MAC salt (8) | MAC (32) | CT
#
#   CT    exactly what `openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000
#         -md sha256` writes: "Salted__", its own random 8-byte salt, blocks.
#   MAC   HMAC-SHA256(K_mac, "KBTF1" | MAC salt | CT) - encrypt-then-MAC.
#   K_mac the 32-byte key PBKDF2-HMAC-SHA256(password, MAC salt, 10000) that
#         `openssl enc ... -S SALT -P` prints; the MAC salt is random and
#         independent of CT's salt, so K_mac is independent of the cipher key.
#
# decrypt checks the MAC BEFORE it runs `openssl enc -d`: a wrong password and
# every changed byte are rc 1 with FILE untouched (the old CBC-only format let
# a wrong password through ~1 time in 256 and replaced FILE with garbage). A
# file without the header - also one written by the old tfile.encrypt - is
# refused; there is no legacy path.
#
# No secret ever reaches an argv: the password goes to openssl through
# `-pass env:`, the MAC key comes back on openssl's stdout into a variable, and
# HMAC is done by hand (RFC 2104) with the padded key written by the BUILTIN
# printf into the pipe of `openssl dgst` (`-hmac KEY` / `-macopt` would show
# it in `ps`). No `$( )` ever holds ciphertext or MAC bytes: binary data only
# travels through files and pipes; od turns the header into hex.
#
# The parameters are pinned (-iter, -md) so decrypt never depends on an
# openssl default; the one place they live is tfile._crypt_openssl_enc.
#
# Caller shell options are respected: `set -C` (the temp file mktemp made is
# overwritten with `>|`), `set -a` (switched off for the call, so no secret is
# exported to mv/od/tail/mktemp, then restored), and a FILE named `-` or `-x`
# (openssl reads `< FILE`, never `-in FILE`).

# openssl enc with the pinned cipher and KDF; the password comes from the
# caller's local __tf_pw through the environment of the openssl process only.
# The variable name is private: a prefix assignment to a READONLY
# TFILE_CRYPTO_PASSWORD (the documented default source) would not run openssl.
tfile._crypt_openssl_enc() {   # EXTRA_OPENSSL_ARGS...
    __TFILE_KBTF1_PW="$__tf_pw" openssl enc -aes-256-cbc -pbkdf2 \
        -iter 10000 -md sha256 -pass env:__TFILE_KBTF1_PW "$@"
}

# -> __tf_r = hex string $1 as printf \xHH escapes (for the builtin printf).
tfile._crypt_hexEsc() {
    local hex="$1" i
    __tf_r=""
    for (( i = 0; i < ${#hex}; i += 2 )); do
        __tf_r+="\\x${hex:i:2}"
    done
}

# -> __tf_r = MAC salt (16 hex digits) followed by K_mac (64 hex digits),
#    lowercase. $1 = the salt in hex, or "" for a fresh random one (openssl
#    draws it, as for its own -salt). -S puts only the salt on the argv - it is
#    stored in the clear anyway; the key comes back on stdout.
tfile._crypt_kdf() {
    local out salt key
    __tf_r=""
    if [[ -n "$1" ]]; then
        out=$(tfile._crypt_openssl_enc -S "$1" -P < /dev/null 2>/dev/null) || return 1
    else
        out=$(tfile._crypt_openssl_enc -P < /dev/null 2>/dev/null) || return 1
    fi
    # "salt=HEX\nkey=HEX\niv =HEX", uppercase, CRLF from a native Windows build.
    [[ "$out" == *salt=* && "$out" == *key=* ]] || return 1
    salt="${out#*salt=}"
    salt="${salt%%[!0-9A-Fa-f]*}"
    key="${out#*key=}"
    key="${key%%[!0-9A-Fa-f]*}"
    (( ${#salt} == 16 && ${#key} == 64 )) || return 1
    __tf_r="${salt,,}${key,,}"
}

# -> __tf_r = lowercase hex HMAC-SHA256(key $1, PREFIX $2 | the bytes of file
#    $3 from 1-based offset $4 on). $1 = 64 hex digits, $2 = \xHH escapes.
#    The inner digest is -binary and goes straight into the outer openssl's
#    stdin behind K^opad, so the 32 raw bytes never pass through a variable.
tfile._crypt_hmac() {
    local key="$1" prefix="$2" file="$3" from="$4" ipad="" opad="" i b h out
    __tf_r=""
    for (( i = 0; i < 64; i += 2 )); do
        b=$(( 16#${key:i:2} ))
        printf -v h '%02x' $(( b ^ 0x36 ))
        ipad+="\\x$h"
        printf -v h '%02x' $(( b ^ 0x5c ))
        opad+="\\x$h"
    done
    # The key is 32 bytes; the SHA-256 block is 64: zero-padded key bytes.
    for (( i = 32; i < 64; i++ )); do
        ipad+='\x36'
        opad+='\x5c'
    done
    out=$({ set -o pipefail
            { builtin printf "$opad"
              { builtin printf "$ipad$prefix"; tail -c "+$from" < "$file"; } \
                  | openssl dgst -sha256 -binary
            } | openssl dgst -sha256
          } 2>/dev/null) || return 1
    # "SHA2-256(stdin)= HEX" / "(stdin)= HEX", maybe CRLF: the last word.
    out="${out%$'\r'}"
    out="${out##*[[:space:]]}"
    out="${out,,}"
    [[ ${#out} -eq 64 && "$out" != *[!0-9a-f]* ]] || return 1
    __tf_r="$out"
}

# Unpredictable temp file in the SAME directory as FILE (so the final mv is
# atomic on the same filesystem). The old "${file}.tmp.$$" name was predictable
# and racy: an attacker could pre-create/symlink it before openssl wrote.
# -> __tf_r = the temp file's path. A directory part starting with `-` gets
# a `./` so mktemp cannot take it for an option.
tfile._crypt_tmp() {
    tfile._parentDir "$1"
    [[ "$__tf_r" == -* ]] && __tf_r="./$__tf_r"
    __tf_r=$(mktemp "$__tf_r/.tfile_crypt.XXXXXXXX" 2>/dev/null) || { __tf_r=""; return 1; }
}

# $1 = FILE; needs __tf_pw and __tf_magic from tfile._crypt_file.
tfile._crypt_encrypt() {
    local file="$1" tmp_file key prefix __tf_r
    if ! tfile._crypt_kdf ""; then
        kk.debug "Error: TFile.encrypt: openssl could not derive the MAC key (openssl 1.1.1+ with -pbkdf2 is needed)"
        return 1
    fi
    key="${__tf_r:16}"
    tfile._crypt_hexEsc "$__tf_magic${__tf_r:0:16}"
    prefix="$__tf_r"
    tfile._crypt_tmp "$file" || return 1
    tmp_file="$__tf_r"
    # The header goes in first with 32 spaces where the MAC belongs; the MAC is
    # computed over the finished file and written over them in place (`1<>`
    # opens without truncating, so the ciphertext behind it stays).
    if builtin printf "$prefix%32s" "" >| "$tmp_file" \
        && tfile._crypt_openssl_enc -e -salt < "$file" >> "$tmp_file" 2>/dev/null \
        && tfile._crypt_hmac "$key" "$prefix" "$tmp_file" 46 \
        && tfile._crypt_hexEsc "$__tf_r" \
        && builtin printf "$prefix$__tf_r" 1<> "$tmp_file" \
        && mv -- "$tmp_file" "$file"; then
        return 0
    fi
    rm -f -- "$tmp_file"
    kk.debug "Error: TFile.encrypt: openssl or the temp file next to the file failed; the file is unchanged"
    return 1
}

# $1 = FILE; needs __tf_pw and __tf_magic from tfile._crypt_file.
tfile._crypt_decrypt() {
    local file="$1" hex key prefix tmp_file __tf_r
    local -a st
    hex=$(od -A n -t x1 -v -N 45 < "$file" 2>/dev/null) || hex=""
    hex="${hex//[!0-9a-f]/}"
    if (( ${#hex} != 90 )) || [[ "${hex:0:10}" != "$__tf_magic" ]]; then
        kk.debug "Error: TFile.decrypt: not a tfile-encrypted file (no KBTF1 header; the pre-KBTF1 format is refused)"
        return 1
    fi
    if ! tfile._crypt_kdf "${hex:10:16}"; then
        kk.debug "Error: TFile.decrypt: openssl could not derive the MAC key (openssl 1.1.1+ with -pbkdf2 is needed)"
        return 1
    fi
    key="${__tf_r:16}"
    tfile._crypt_hexEsc "${hex:0:26}"
    prefix="$__tf_r"
    if ! tfile._crypt_hmac "$key" "$prefix" "$file" 46; then
        kk.debug "Error: TFile.decrypt: openssl could not compute the MAC"
        return 1
    fi
    # Not constant-time (bash cannot be); a non-goal for a local tool.
    if [[ "$__tf_r" != "${hex:26:64}" ]]; then
        kk.debug "Error: TFile.decrypt: wrong password or a changed file (KBTF1 MAC mismatch)"
        return 1
    fi
    tfile._crypt_tmp "$file" || return 1
    tmp_file="$__tf_r"
    tail -c +46 < "$file" 2>/dev/null \
        | tfile._crypt_openssl_enc -d -out "$tmp_file" 2>/dev/null
    st=( "${PIPESTATUS[@]}" )
    if (( st[0] == 0 && st[1] == 0 )) && mv -- "$tmp_file" "$file"; then
        return 0
    fi
    rm -f -- "$tmp_file"
    kk.debug "Error: TFile.decrypt: openssl or the temp file next to the file failed; the file is unchanged"
    return 1
}

# $1 = encrypt | decrypt, $2 = FILE, $3 = password ("" = $TFILE_CRYPTO_PASSWORD).
# Every failure is rc 1 with FILE byte-identical and no temp file left.
# Under the caller's `set -a` every local of the work (the password, the MAC
# key) would be EXPORTED to each child process; allexport is switched off
# BEFORE any local exists (a local declared under `set -a` keeps its export
# attribute) and restored afterwards, the rc kept.
tfile._crypt_file() {
    if [[ $- == *a* ]]; then
        set +a
        tfile._crypt_run "$@"
        set -- "$?"
        set -a
        return "$1"
    fi
    tfile._crypt_run "$@"
}

tfile._crypt_run() {
    local mode="$1" file="$2" password_arg="${3:-}"
    # REPLY is local: the password must not stay behind in the caller's REPLY.
    local REPLY __tf_pw __tf_magic=4b42544631   # "KBTF1"
    [[ -f "$file" ]] || return 1
    tfile._crypto_password "$password_arg" || return 1
    __tf_pw="$REPLY"
    if ! command -v openssl >/dev/null 2>&1; then
        kk.debug "Error: TFile.$mode: openssl not found"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        kk.debug "Error: TFile.$mode: cannot read '$file'"
        return 1
    fi
    if [[ "$mode" == encrypt ]]; then
        tfile._crypt_encrypt "$file"
    else
        tfile._crypt_decrypt "$file"
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
    if tfile._crypt_file encrypt "${1:-}" "${2:-}"; then
        tpath._ret ""
    else
        tpath._ret "" 1
        return 1
    fi
}

tfile.decrypt() {
    if tfile._crypt_file decrypt "${1:-}" "${2:-}"; then
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
# tpath._touchTime, which uses `touch -t` under TZ=UTC0 so a *Utc value is
# stored as the instant it names (G6-08, launch L3.5-1). Creation time is NOT
# settable: POSIX has no API and Windows' is not reachable through touch, so
# it answers rc 1 the way .NET does on Unix (R13).

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
