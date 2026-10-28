#!/usr/bin/env bash
# 009_encrypt.sh - Test TFile.Encrypt method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# Set up temp directory for this test

# Test 1: Encrypt file
kt_test_start "Encrypt file"
echo "content" > "$_KT_TMPDIR/encrypt.tmp"
if result=$(tfile.encrypt "$_KT_TMPDIR/encrypt.tmp" "test-password"); then
    if [[ "$(cat "$_KT_TMPDIR/encrypt.tmp")" != "content" ]]; then
    kt_test_pass "Encrypt file"
    else
        kt_test_fail "Encrypt file (content remained plaintext)"
    fi
else
    kt_test_fail "Encrypt file"
fi

# Test 2: Encrypt already encrypted file
kt_test_start "Encrypt already encrypted file"
if result=$(tfile.encrypt "$_KT_TMPDIR/encrypt.tmp" "test-password"); then
    kt_test_pass "Encrypt already encrypted file"
else
    kt_test_fail "Encrypt already encrypted file"
fi

# Test 3: Encrypt without password
kt_test_start "Encrypt without password"
echo "content" > "$_KT_TMPDIR/no_password.tmp"
if ! result=$(tfile.encrypt "$_KT_TMPDIR/no_password.tmp" 2>&1); then
    if [[ "$(cat "$_KT_TMPDIR/no_password.tmp")" == "content" ]]; then
        kt_test_pass "Encrypt without password (correctly failed)"
    else
        kt_test_fail "Encrypt without password mutated file"
    fi
else
    kt_test_fail "Encrypt without password (should have failed)"
fi

# Test 4: Encrypt non-existing file
kt_test_start "Encrypt non-existing file"
if ! result=$(tfile.encrypt "$_KT_TMPDIR/nonexist.tmp" "test-password" 2>&1); then
    kt_test_pass "Encrypt non-existing file (correctly failed)"
else
    kt_test_fail "Encrypt non-existing file (should have failed)"
fi

# ---------------------------------------------------------------------------
# The KBTF1 format (launch L34-F2, owner decision OG9; README "Encryption"):
#   "KBTF1" (5) | MAC salt (8) | MAC (32) | openssl enc output ("Salted__" ...)
# ---------------------------------------------------------------------------
kt_test_start "Encrypted file starts with KBTF1 and carries openssl's Salted__ at offset 45 [L34-F2]"
printf '0123456789abcdef0123' > "$_KT_TMPDIR/format.tmp"       # 20 bytes
tfile.encrypt "$_KT_TMPDIR/format.tmp" "test-password"
magic=$(head -c 5 "$_KT_TMPDIR/format.tmp")
salted=$(od -A n -t x1 -v -j 45 -N 8 < "$_KT_TMPDIR/format.tmp")
salted="${salted//[!0-9a-f]/}"
size=$(wc -c < "$_KT_TMPDIR/format.tmp"); size="${size//[!0-9]/}"
# 45 header + 16 (Salted__ + salt) + 32 (20 bytes padded to two blocks)
if [[ "$magic" == KBTF1 && "$salted" == 53616c7465645f5f && "$size" == 93 ]]; then
    kt_test_pass "KBTF1, Salted__ at 45, size 93"
else
    kt_test_fail "magic='$magic' at45=$salted size=$size (want KBTF1, 53616c7465645f5f, 93)"
fi

kt_test_start "Two encryptions of the same content differ (fresh salts) [L34-F2]"
printf 'same\n' > "$_KT_TMPDIR/salt_a.tmp"
printf 'same\n' > "$_KT_TMPDIR/salt_b.tmp"
tfile.encrypt "$_KT_TMPDIR/salt_a.tmp" "test-password"
tfile.encrypt "$_KT_TMPDIR/salt_b.tmp" "test-password"
msalt_a=$(od -A n -t x1 -v -j 5 -N 8 < "$_KT_TMPDIR/salt_a.tmp"); msalt_a="${msalt_a//[!0-9a-f]/}"
msalt_b=$(od -A n -t x1 -v -j 5 -N 8 < "$_KT_TMPDIR/salt_b.tmp"); msalt_b="${msalt_b//[!0-9a-f]/}"
if ! cmp -s "$_KT_TMPDIR/salt_a.tmp" "$_KT_TMPDIR/salt_b.tmp" \
   && [[ ${#msalt_a} == 16 && "$msalt_a" != "$msalt_b" ]]; then
    kt_test_pass "different ciphertexts and different MAC salts (bytes 5-12)"
else
    kt_test_fail "salts not fresh: MAC salt a=$msalt_a b=$msalt_b"
fi

kt_test_start "Binary payload with NULs and a trailing newline round-trips byte-exactly [L34-F2]"
B="$_KT_TMPDIR/binary.tmp"
printf 'a\000b\000\000\377\001\r\n\000tail\n\n' > "$B"
head -c 3000 /dev/urandom >> "$B"
printf '\000\n' >> "$B"
cp "$B" "$B.orig"
rc_e=0 rc_d=0
tfile.encrypt "$B" "bin-pw" || rc_e=$?
encrypted_differs=no
cmp -s "$B" "$B.orig" || encrypted_differs=yes
tfile.decrypt "$B" "bin-pw" || rc_d=$?
if (( rc_e == 0 && rc_d == 0 )) && [[ "$encrypted_differs" == yes ]] && cmp -s "$B" "$B.orig"; then
    kt_test_pass "byte-exact round trip"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d encrypted_differs=$encrypted_differs identical=$(cmp -s "$B" "$B.orig" && echo yes || echo no)"
fi

kt_test_start "Empty file round-trips [L34-F2]"
: > "$_KT_TMPDIR/empty_rt.tmp"
rc_e=0 rc_d=0
tfile.encrypt "$_KT_TMPDIR/empty_rt.tmp" "test-password" || rc_e=$?
size=$(wc -c < "$_KT_TMPDIR/empty_rt.tmp"); size="${size//[!0-9]/}"
tfile.decrypt "$_KT_TMPDIR/empty_rt.tmp" "test-password" || rc_d=$?
size2=$(wc -c < "$_KT_TMPDIR/empty_rt.tmp"); size2="${size2//[!0-9]/}"
if (( rc_e == 0 && rc_d == 0 )) && [[ "$size" == 77 && "$size2" == 0 ]]; then
    kt_test_pass "77 bytes encrypted, 0 after decrypt"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d encrypted_size=$size decrypted_size=$size2"
fi

kt_test_start "The password does not stay behind in REPLY [L34-F2]"
REPLY="before"
printf 'x\n' > "$_KT_TMPDIR/reply.tmp"
tfile.encrypt "$_KT_TMPDIR/reply.tmp" "reply-secret-pw"
tfile.decrypt "$_KT_TMPDIR/reply.tmp" "reply-secret-pw"
if [[ "$REPLY" == before ]]; then
    kt_test_pass "REPLY untouched"
else
    kt_test_fail "REPLY='$REPLY'"
fi

kt_test_start "Password from TFILE_CRYPTO_PASSWORD round-trips [L34-F2]"
printf 'env pw\n' > "$_KT_TMPDIR/envpw.tmp"
rc_e=0 rc_d=0
TFILE_CRYPTO_PASSWORD="env-secret" tfile.encrypt "$_KT_TMPDIR/envpw.tmp" || rc_e=$?
TFILE_CRYPTO_PASSWORD="env-secret" tfile.decrypt "$_KT_TMPDIR/envpw.tmp" || rc_d=$?
if (( rc_e == 0 && rc_d == 0 )) && [[ "$(cat "$_KT_TMPDIR/envpw.tmp")" == "env pw" ]]; then
    kt_test_pass "round trip through the environment"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d text='$(cat "$_KT_TMPDIR/envpw.tmp")'"
fi

# An independent oracle: re-derive K_mac here and let openssl's own HMAC check
# the stored MAC over bytes 0-12 + 45..end (a key on the argv is fine in a
# test); the ciphertext part is plain `openssl enc` output.
kt_test_start "Stored MAC equals openssl dgst -mac HMAC over header + CT; CT is plain openssl enc [L34-F2]"
O="$_KT_TMPDIR/oracle.tmp"
head -c 2000 /dev/urandom > "$O"
cp "$O" "$O.orig"
tfile.encrypt "$O" "oracle-pw"
o_salt=$(od -A n -t x1 -v -j 5 -N 8 < "$O"); o_salt="${o_salt//[!0-9a-f]/}"
o_mac=$(od -A n -t x1 -v -j 13 -N 32 < "$O"); o_mac="${o_mac//[!0-9a-f]/}"
o_key=$(TFILE_CRYPTO_PASSWORD="oracle-pw" openssl enc -aes-256-cbc -pbkdf2 -iter 10000 \
    -md sha256 -S "$o_salt" -pass env:TFILE_CRYPTO_PASSWORD -P < /dev/null 2>/dev/null)
o_key="${o_key#*key=}"
o_key="${o_key%%[!0-9A-Fa-f]*}"
o_ref=$( { head -c 13 "$O"; tail -c +46 "$O"; } \
    | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$o_key" 2>/dev/null )
o_ref="${o_ref%$'\r'}"
o_ref="${o_ref##*[[:space:]]}"
o_ref="${o_ref,,}"
o_ct=no
tail -c +46 "$O" | TFILE_CRYPTO_PASSWORD="oracle-pw" openssl enc -d -aes-256-cbc -pbkdf2 \
    -iter 10000 -md sha256 -pass env:TFILE_CRYPTO_PASSWORD 2>/dev/null > "$O.plain" \
    && cmp -s "$O.plain" "$O.orig" && o_ct=yes
if [[ ${#o_key} == 64 && ${#o_ref} == 64 && "$o_ref" == "$o_mac" && "$o_ct" == yes ]]; then
    kt_test_pass "MAC matches the openssl oracle; CT decrypts with plain openssl"
else
    kt_test_fail "keylen=${#o_key} stored=$o_mac oracle=$o_ref ct_plain=$o_ct"
fi

kt_test_start "encrypt + decrypt under the caller's set -C (noclobber): rc 0, no stderr [L34-F2]"
NC="$_KT_TMPDIR/noclobber.tmp"
printf 'noclobber\n' > "$NC"
rc_e=0 rc_d=0
err_e=$( set -C; tfile.encrypt "$NC" "nc-pw" 2>&1 ) || rc_e=$?
magic=$(head -c 5 "$NC")
err_d=$( set -C; tfile.decrypt "$NC" "nc-pw" 2>&1 ) || rc_d=$?
if (( rc_e == 0 && rc_d == 0 )) && [[ -z "$err_e$err_d" && "$magic" == KBTF1 \
      && "$(cat "$NC")" == noclobber ]]; then
    kt_test_pass "round trip under set -C, silent"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d magic='$magic' err_e='$err_e' err_d='$err_d'"
fi

kt_test_start "A file literally named '-' round-trips byte-exactly (openssl reads < FILE) [L34-F2]"
DD="$_KT_TMPDIR/dash dir"
mkdir -p "$DD"
printf 'precious\000data\n' > "$DD/-"
cp "$DD/-" "$DD/dash.orig"
rc_e=0 rc_d=0
( cd "$DD" && tfile.encrypt - "dash-pw" < /dev/null ) || rc_e=$?
magic=$(head -c 5 "$DD/-")
( cd "$DD" && tfile.decrypt - "dash-pw" < /dev/null ) || rc_d=$?
if (( rc_e == 0 && rc_d == 0 )) && [[ "$magic" == KBTF1 ]] && cmp -s "$DD/-" "$DD/dash.orig"; then
    kt_test_pass "encrypted (KBTF1) and restored byte-exactly"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d magic='$magic' identical=$(cmp -s "$DD/-" "$DD/dash.orig" && echo yes || echo no)"
fi

kt_test_start "A directory part starting with '-' (-d/f): no stderr, round trip [L34-F2]"
rc=0
( cd "$DD" && mkdir -p -- -d && printf 'in dir\n' > ./-d/f \
  && tfile.encrypt -d/f "dash-pw" && head -c 5 ./-d/f > ./magic.txt \
  && tfile.decrypt -d/f "dash-pw" ) 2> "$DD/err.txt" || rc=$?
if (( rc == 0 )) && [[ ! -s "$DD/err.txt" && "$(cat "$DD/magic.txt")" == KBTF1 \
      && "$(cat "$DD/-d/f")" == "in dir" ]]; then
    kt_test_pass "rc 0, silent, restored"
else
    kt_test_fail "rc=$rc stderr='$(cat "$DD/err.txt")' magic='$(cat "$DD/magic.txt" 2>/dev/null)'"
fi

kt_test_start "A READONLY TFILE_CRYPTO_PASSWORD works as the default and beside an explicit password [L34-F2]"
rc=0
out=$( readonly TFILE_CRYPTO_PASSWORD="ro-env-pw"
       f="$_KT_TMPDIR/readonly.tmp"
       printf 'ro\n' > "$f"
       tfile.encrypt "$f" || exit 11
       [[ "$(head -c 5 "$f")" == KBTF1 ]] || exit 12
       tfile.decrypt "$f" || exit 13
       [[ "$(cat "$f")" == ro ]] || exit 14
       tfile.encrypt "$f" "explicit-pw" || exit 15
       tfile.decrypt "$f" "ro-env-pw" && exit 16     # the explicit one was used
       tfile.decrypt "$f" "explicit-pw" || exit 17
       [[ "$(cat "$f")" == ro ]] || exit 18
       printf ok ) 2>&1 || rc=$?
if (( rc == 0 )) && [[ "$out" == ok ]]; then
    kt_test_pass "env default and explicit password both work"
else
    kt_test_fail "step rc=$rc out='$out'"
fi

# Under the caller's `set -a` every variable a function assigns is exported to
# its children. A `mv` shim first on PATH dumps the environment it gets: no
# password, no MAC key; `set -a` is still on afterwards.
kt_test_start "Under set -a no secret reaches a child's environment, and set -a stays on [L34-F2]"
AE="$_KT_TMPDIR/allexport"
mkdir -p "$AE/bin"
cat > "$AE/bin/mv" <<'SHIM'
#!/bin/sh
env >> "$KBTF1_ENV_LOG"
exec "$KBTF1_REAL_MV" "$@"
SHIM
chmod +x "$AE/bin/mv"
real_mv="$(command -v mv)"
printf 'allexport\n' > "$AE/f.tmp"
: > "$AE/env_enc.log"
: > "$AE/env_dec.log"
rc_e=0 rc_d=0
flags_e=$( export KBTF1_REAL_MV="$real_mv" KBTF1_ENV_LOG="$AE/env_enc.log"
           PATH="$AE/bin:$PATH"
           set -a
           tfile.encrypt "$AE/f.tmp" "allexport-secret-pw" || exit 1
           printf '%s' "$-" ) || rc_e=$?
ae_salt=$(od -A n -t x1 -v -j 5 -N 8 < "$AE/f.tmp"); ae_salt="${ae_salt//[!0-9a-f]/}"
ae_key=$(TFILE_CRYPTO_PASSWORD="allexport-secret-pw" openssl enc -aes-256-cbc -pbkdf2 -iter 10000 \
    -md sha256 -S "$ae_salt" -pass env:TFILE_CRYPTO_PASSWORD -P < /dev/null 2>/dev/null)
ae_key="${ae_key#*key=}"
ae_key="${ae_key%%[!0-9A-Fa-f]*}"
ae_key="${ae_key,,}"
flags_d=$( export KBTF1_REAL_MV="$real_mv" KBTF1_ENV_LOG="$AE/env_dec.log"
           PATH="$AE/bin:$PATH"
           set -a
           tfile.decrypt "$AE/f.tmp" "allexport-secret-pw" || exit 1
           printf '%s' "$-" ) || rc_d=$?
ae_bad=""
for op in enc dec; do
    envdump="$(< "$AE/env_$op.log")"
    envdump="${envdump,,}"
    [[ "$envdump" == *kbtf1_real_mv=* ]] || ae_bad+=" $op:shim-not-run"
    [[ "$envdump" == *allexport-secret-pw* ]] && ae_bad+=" $op:PASSWORD-EXPORTED"
    [[ ${#ae_key} == 64 && "$envdump" == *"$ae_key"* ]] && ae_bad+=" $op:KEY-EXPORTED"
done
if (( rc_e == 0 && rc_d == 0 && ${#ae_key} == 64 )) && [[ -z "$ae_bad" \
      && "$flags_e" == *a* && "$flags_d" == *a* && "$(cat "$AE/f.tmp")" == allexport ]]; then
    kt_test_pass "nothing secret exported; \$- keeps 'a'"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d flags_e='$flags_e' flags_d='$flags_d' keylen=${#ae_key} problems:${ae_bad:- none}"
fi

kt_test_start "Encrypt of an unreadable file: rc 1, one line naming it, file unchanged [L34-F2]"
U="$_KT_TMPDIR/unreadable_enc.tmp"
printf 'unreadable\n' > "$U"
chmod 000 "$U"
if [[ -r "$U" ]]; then
    kt_test_pass "N/A: chmod 000 still leaves the file readable here (root, or Windows)"
else
    rc=0
    err=$(VERBOSE_KKLASS=debug tfile.encrypt "$U" "pw" 2>&1 >/dev/null) || rc=$?
    chmod 600 "$U"
    left=$(ls -A "$_KT_TMPDIR" | grep -c '^\.tfile_crypt' || true)
    if (( rc == 1 )) && [[ "$left" == 0 && "$(cat "$U")" == unreadable \
          && "$err" == *"Error: TFile.encrypt: cannot read '"*"unreadable_enc.tmp'" && "$err" != *$'\n'* ]]; then
        kt_test_pass "rc 1: $err"
    else
        kt_test_fail "rc=$rc temp_left=$left err='$err'"
    fi
fi
chmod 600 "$U"
