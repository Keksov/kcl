#!/usr/bin/env bash
# 007_decrypt.sh - Test TFile.Decrypt method
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

# Test 1: Decrypt encrypted file
kt_test_start "Decrypt encrypted file"
echo "content" > "$_KT_TMPDIR/encrypt.tmp"
tfile.encrypt "$_KT_TMPDIR/encrypt.tmp" "test-password"  # Assume this works
if result=$(tfile.decrypt "$_KT_TMPDIR/encrypt.tmp" "test-password"); then
    if [[ "$(cat "$_KT_TMPDIR/encrypt.tmp")" == "content" ]]; then
    kt_test_pass "Decrypt encrypted file"
    else
        kt_test_fail "Decrypt encrypted file (content was not restored)"
    fi
else
    kt_test_fail "Decrypt encrypted file"
fi

# Test 2: Decrypt non-encrypted file
kt_test_start "Decrypt non-encrypted file"
echo "plain" > "$_KT_TMPDIR/plain.tmp"
result=$(tfile.decrypt "$_KT_TMPDIR/plain.tmp" "test-password")
if [[ $? -ne 0 ]]; then
kt_test_pass "Decrypt non-encrypted file"
else
kt_test_fail "Decrypt non-encrypted file"
fi

# Test 3: Decrypt without password
kt_test_start "Decrypt without password"
echo "content" > "$_KT_TMPDIR/no_password_decrypt.tmp"
tfile.encrypt "$_KT_TMPDIR/no_password_decrypt.tmp" "test-password"
if ! result=$(tfile.decrypt "$_KT_TMPDIR/no_password_decrypt.tmp" 2>&1); then
    kt_test_pass "Decrypt without password (correctly failed)"
else
    kt_test_fail "Decrypt without password (should have failed)"
fi

# Test 4: Decrypt with wrong password (launch L34-F2). The old CBC-only format
# let a wrong password through about 1 time in 256 (openssl's padding check
# passed by chance) and replaced the file with garbage; the KBTF1 MAC is
# checked first. 30 FRESH encryptions, so every round draws new salts; the
# refusal cases below prove the MAC path deterministically (300 rounds cost
# ~140 s per Windows runtime; the 2000-round run is in the L34-F2 report).
kt_test_start "Decrypt with wrong password: 30 fresh encryptions, none accepted [L34-F2]"
wp="$_KT_TMPDIR/wrong_password.tmp"
accepted=0 changed=0 enc_failed=0
for (( i = 1; i <= 30; i++ )); do
    printf 'secret %d\n' "$i" > "$wp"
    if ! tfile.encrypt "$wp" "right-password"; then
        enc_failed=$(( enc_failed + 1 ))
        continue
    fi
    cp "$wp" "$wp.enc"
    if tfile.decrypt "$wp" "wrong-password"; then
        accepted=$(( accepted + 1 ))
    fi
    cmp -s "$wp" "$wp.enc" || changed=$(( changed + 1 ))
done
if (( accepted == 0 && changed == 0 && enc_failed == 0 )); then
    kt_test_pass "Decrypt with wrong password: 0 of 30 accepted, file byte-identical each time"
else
    kt_test_fail "Decrypt with wrong password: accepted=$accepted changed=$changed encrypt_failed=$enc_failed of 30"
fi

# Test 5: Decrypt non-existing file
kt_test_start "Decrypt non-existing file"
if ! result=$(tfile.decrypt "$_KT_TMPDIR/nonexist.tmp" "test-password" 2>&1); then
    kt_test_pass "Decrypt non-existing file (correctly failed)"
else
    kt_test_fail "Decrypt non-existing file (should have failed)"
fi

# ---------------------------------------------------------------------------
# KBTF1 refusals (launch L34-F2, owner decision OG9). Layout by offset:
#   0 "KBTF1" | 5 MAC salt (8) | 13 MAC (32) | 45 "Salted__" |
#   53 openssl's own salt (8) | 61 the cipher blocks
# Every case: rc 1, the file byte-identical, no temp file left, and exactly one
# error line under VERBOSE_KKLASS=debug naming the reason.
# ---------------------------------------------------------------------------
TD="$_KT_TMPDIR/kbtf1"
mkdir -p "$TD"

# Flip every bit of the byte at 0-based offset $2 of file $1, in place.
flip_byte() {
    local hex esc
    hex=$(od -A n -t x1 -v -j "$2" -N 1 < "$1")
    hex="${hex//[!0-9a-f]/}"
    printf -v esc '\\x%02x' $(( 16#$hex ^ 0xff ))
    printf "$esc" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null
}

# A fresh encryption of a fixed text in $TD/$1.
fresh_kbtf1() {
    printf 'line one\nline two\n' > "$TD/$1"
    tfile.encrypt "$TD/$1" "pw-kbtf1"
}

# expect_refused LABEL FILE WANT: decrypting FILE with pw-kbtf1 is refused.
expect_refused() {
    local label="$1" f="$2" want="$3" err rc=0 left same=no
    kt_test_start "$label [L34-F2]"
    cp "$f" "$f.before"
    err=$(VERBOSE_KKLASS=debug tfile.decrypt "$f" "pw-kbtf1" 2>&1 >/dev/null) || rc=$?
    left=$(ls -A "$TD" | grep -c '^\.tfile_crypt' || true)
    cmp -s "$f" "$f.before" && same=yes
    if (( rc == 1 )) && [[ "$same" == yes && "$left" == 0 ]] \
       && [[ -n "$err" && "$err" != *$'\n'* && "$err" == *"$want"* ]]; then
        kt_test_pass "$label: rc 1, file unchanged, one line: $err"
    else
        kt_test_fail "$label: rc=$rc unchanged=$same temp_left=$left err='$err'"
    fi
}

mac_msg="wrong password or a changed file (KBTF1 MAC mismatch)"
hdr_msg="not a tfile-encrypted file (no KBTF1 header"

fresh_kbtf1 ct_first.tmp && flip_byte "$TD/ct_first.tmp" 61
expect_refused "Flipped byte in the first cipher block" "$TD/ct_first.tmp" "$mac_msg"

fresh_kbtf1 ct_last.tmp
size=$(wc -c < "$TD/ct_last.tmp"); size="${size//[!0-9]/}"
flip_byte "$TD/ct_last.tmp" $(( size - 1 ))
expect_refused "Flipped last byte (the padding block)" "$TD/ct_last.tmp" "$mac_msg"

fresh_kbtf1 ct_salt.tmp && flip_byte "$TD/ct_salt.tmp" 55
expect_refused "Flipped byte in openssl's own salt" "$TD/ct_salt.tmp" "$mac_msg"

fresh_kbtf1 mac.tmp && flip_byte "$TD/mac.tmp" 20
expect_refused "Flipped byte in the MAC" "$TD/mac.tmp" "$mac_msg"

fresh_kbtf1 salt.tmp && flip_byte "$TD/salt.tmp" 7
expect_refused "Flipped byte in the MAC salt" "$TD/salt.tmp" "$mac_msg"

fresh_kbtf1 magic.tmp && flip_byte "$TD/magic.tmp" 4
expect_refused "Flipped byte in the magic" "$TD/magic.tmp" "$hdr_msg"

fresh_kbtf1 trunc_src.tmp
size=$(wc -c < "$TD/trunc_src.tmp"); size="${size//[!0-9]/}"
head -c $(( size - 1 )) "$TD/trunc_src.tmp" > "$TD/trunc_ct.tmp"
expect_refused "Truncated file (last byte cut)" "$TD/trunc_ct.tmp" "$mac_msg"
head -c $(( size - 16 )) "$TD/trunc_src.tmp" > "$TD/trunc_block.tmp"
expect_refused "Truncated file (last cipher block cut)" "$TD/trunc_block.tmp" "$mac_msg"
head -c 30 "$TD/trunc_src.tmp" > "$TD/trunc_hdr.tmp"
expect_refused "Truncated file (cut inside the header)" "$TD/trunc_hdr.tmp" "$hdr_msg"

: > "$TD/empty.tmp"
expect_refused "Empty file" "$TD/empty.tmp" "$hdr_msg"

# The pre-KBTF1 format: exactly the command line the old tfile.encrypt ran.
printf 'old secret\n' > "$TD/old_src.tmp"
TFILE_CRYPTO_PASSWORD="pw-kbtf1" openssl enc -aes-256-cbc -salt -pbkdf2 \
    -in "$TD/old_src.tmp" -out "$TD/old.tmp" -pass env:TFILE_CRYPTO_PASSWORD 2>/dev/null
expect_refused "File in the old (pre-KBTF1) format, right password" "$TD/old.tmp" "$hdr_msg"

# Wrong password: one line too, and it is the MAC that says no.
fresh_kbtf1 wrongpw.tmp
kt_test_start "Wrong password names the reason in one line [L34-F2]"
cp "$TD/wrongpw.tmp" "$TD/wrongpw.before"
rc=0
err=$(VERBOSE_KKLASS=debug tfile.decrypt "$TD/wrongpw.tmp" "not-the-password" 2>&1 >/dev/null) || rc=$?
if (( rc == 1 )) && cmp -s "$TD/wrongpw.tmp" "$TD/wrongpw.before" \
   && [[ "$err" == *"$mac_msg"* && "$err" != *$'\n'* ]]; then
    kt_test_pass "rc 1, unchanged: $err"
else
    kt_test_fail "rc=$rc err='$err'"
fi

kt_test_start "Without VERBOSE_KKLASS=debug a refusal prints nothing [L34-F2]"
rc=0
err=$(VERBOSE_KKLASS= tfile.decrypt "$TD/wrongpw.tmp" "not-the-password" 2>&1) || rc=$?
if (( rc == 1 )) && [[ -z "$err" ]]; then
    kt_test_pass "rc 1, silent"
else
    kt_test_fail "rc=$rc out='$err'"
fi

# Unreadable file: its own one line, not "not a tfile-encrypted file".
fresh_kbtf1 unreadable.tmp
chmod 000 "$TD/unreadable.tmp"
kt_test_start "Unreadable file: rc 1, one line naming it [L34-F2]"
if [[ -r "$TD/unreadable.tmp" ]]; then
    kt_test_pass "N/A: chmod 000 still leaves the file readable here (root, or Windows)"
else
    rc=0
    err=$(VERBOSE_KKLASS=debug tfile.decrypt "$TD/unreadable.tmp" "pw-kbtf1" 2>&1 >/dev/null) || rc=$?
    left=$(ls -A "$TD" | grep -c '^\.tfile_crypt' || true)
    if (( rc == 1 )) && [[ "$left" == 0 && "$err" == *"Error: TFile.decrypt: cannot read '"*"unreadable.tmp'" \
          && "$err" != *$'\n'* ]]; then
        kt_test_pass "rc 1: $err"
    else
        kt_test_fail "rc=$rc temp_left=$left err='$err'"
    fi
fi
chmod 600 "$TD/unreadable.tmp"

# ---------------------------------------------------------------------------
# No secret on any argv (SV rule 1), deterministically: an `openssl` shim first
# on PATH logs every argv it is started with and execs the real openssl. Each
# operation must go through it (>= 1 enc, >= 2 dgst), and neither the password
# nor the MAC key (hex, either case; derived here from the stored salt) may be
# in the log. Every platform, Windows included.
# ---------------------------------------------------------------------------
kt_test_start "Neither the password nor the MAC key reaches an openssl argv (PATH shim) [L34-F2, SV1]"
real_openssl="$(command -v openssl)"
shim_dir="$TD/argv shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/openssl" <<'SHIM'
#!/bin/sh
{ printf '== %s\n' "$1"; for a in "$@"; do printf '%s\n' "$a"; done; } >> "$KBTF1_ARGV_LOG"
exec "$KBTF1_REAL_OPENSSL" "$@"
SHIM
chmod +x "$shim_dir/openssl"
export KBTF1_REAL_OPENSSL="$real_openssl"
probe_pw="argv-probe-pw-7Q2x"
printf 'argv probe\n' > "$TD/argv.tmp"
: > "$TD/argv_enc.log"
: > "$TD/argv_dec.log"
rc_e=0 rc_d=0
( PATH="$shim_dir:$PATH"; export KBTF1_ARGV_LOG="$TD/argv_enc.log"
  tfile.encrypt "$TD/argv.tmp" "argv-probe-pw-7Q2x" ) || rc_e=$?
probe_salt=$(od -A n -t x1 -v -j 5 -N 8 < "$TD/argv.tmp")
probe_salt="${probe_salt//[!0-9a-f]/}"
probe_key=$(TFILE_CRYPTO_PASSWORD="$probe_pw" openssl enc -aes-256-cbc -pbkdf2 -iter 10000 \
    -md sha256 -S "$probe_salt" -pass env:TFILE_CRYPTO_PASSWORD -P < /dev/null 2>/dev/null)
probe_key="${probe_key#*key=}"
probe_key="${probe_key%%[!0-9A-Fa-f]*}"
probe_key="${probe_key,,}"
( PATH="$shim_dir:$PATH"; export KBTF1_ARGV_LOG="$TD/argv_dec.log"
  tfile.decrypt "$TD/argv.tmp" "argv-probe-pw-7Q2x" ) || rc_d=$?
probe_bad=""
for op in enc dec; do
    log="$(< "$TD/argv_$op.log")"
    log="${log,,}"
    n_enc=0 n_dgst=0
    while IFS= read -r l; do
        [[ "$l" == "== enc"* ]] && n_enc=$(( n_enc + 1 ))
        [[ "$l" == "== dgst"* ]] && n_dgst=$(( n_dgst + 1 ))
    done < "$TD/argv_$op.log"
    (( n_enc >= 1 && n_dgst >= 2 )) || probe_bad+=" $op:enc=$n_enc,dgst=$n_dgst"
    [[ "$log" == *"${probe_pw,,}"* ]] && probe_bad+=" $op:PASSWORD-IN-ARGV"
    [[ ${#probe_key} == 64 && "$log" == *"$probe_key"* ]] && probe_bad+=" $op:KEY-IN-ARGV"
done
if (( rc_e == 0 && rc_d == 0 && ${#probe_key} == 64 )) && [[ -z "$probe_bad" ]] \
   && [[ "$(cat "$TD/argv.tmp")" == "argv probe" ]]; then
    kt_test_pass "round trip through the shim; no password, no key in any argv"
else
    kt_test_fail "rc_e=$rc_e rc_d=$rc_d keylen=${#probe_key} problems:${probe_bad:- none}"
fi
