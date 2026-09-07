#!/bin/bash
# 042_G6_IO.sh — review 2026-09-06, phase P3.
#
#   G6-18  readAllText/readAllBytes/readAllLines piped `cat` through `$( )`,
#          which forks a shell AND strips every trailing newline; there was no
#          way to get a byte-faithful read at all. R13 adds `readAllTextVar`
#          (fill a caller variable, fork-free, trailing newlines preserved)
#          and gives readAllLines an optional output ARRAY (kcl/README.md 1.7).
#   G6-19  replace copied the source over the destination and LEFT the source
#          behind; .NET File.Replace / FPC consume it.
#   G6-26  _crypt_file worked out the temp directory with `${file%/*}`, which
#          only understands `/`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

kt_test_init "G6_IO" "$SCRIPT_DIR" "$@"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- G6-18: readAllTextVar keeps every byte --------------------------------
kt_test_start "readAllTextVar preserves trailing newlines [G6-18, R13]"
F="$W/trail.txt"
printf 'a\nb\n\n\n' > "$F"
text=""
rc=0
tfile.readAllTextVar "$F" text || rc=$?
if (( rc == 0 )) && [[ "$text" == $'a\nb\n\n\n' ]]; then
    kt_test_pass "${#text} chars, trailing newlines intact"
else
    kt_test_fail "rc=$rc got ${#text} chars: $(printf '%q' "$text")"
fi

kt_test_start "\$( ) of the same file loses them — that is why the Var form exists [G6-18]"
captured="$(tfile.readAllText "$F")"
if [[ "$captured" == $'a\nb' ]]; then
    kt_test_pass "\$( ) stripped the trailing newlines, as bash always does"
else
    kt_test_fail "got $(printf '%q' "$captured")"
fi

kt_test_start "readAllText leaves the byte-faithful text in RESULT [G6-18, D3]"
RESULT="__unset__"
tfile.readAllText "$F" >/dev/null
if [[ "$RESULT" == $'a\nb\n\n\n' ]]; then
    kt_test_pass "RESULT is byte-faithful"
else
    kt_test_fail "RESULT=$(printf '%q' "$RESULT")"
fi

kt_test_start "readAllTextVar is fork-free [G6-18, 1.8]"
canary="$W/cat_called"
rm -f -- "$canary"
cat() { : > "$canary"; command cat "$@"; }
text=""
tfile.readAllTextVar "$F" text || :
unset -f cat
if [[ -e "$canary" ]]; then
    kt_test_fail "readAllTextVar shelled out to cat"
else
    kt_test_pass "no cat"
fi

kt_test_start "readAllTextVar rejects a reserved output name [1.7]"
rc=0
tfile.readAllTextVar "$F" RESULT >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc (wanted 2)"
fi

kt_test_start "readAllTextVar rejects a malformed output name [1.7]"
rc=0
tfile.readAllTextVar "$F" "not a name" >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc (wanted 2)"
fi

kt_test_start "readAllTextVar on a missing file is rc 1 [1.2]"
rc=0
tfile.readAllTextVar "$W/nosuch.txt" text >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "readAllTextVar reads a file whose name starts with a dash [G6-11]"
cd "$W" || exit 1
printf 'dashy' > -weird
text=""
tfile.readAllTextVar -weird text || :
rm -f -- -weird
if [[ "$text" == "dashy" ]]; then
    kt_test_pass "read './-weird', not stdin"
else
    kt_test_fail "got '$text'"
fi
cd "$SCRIPT_DIR" || exit 1

# --- G6-18: readAllLines into an array -------------------------------------
kt_test_start "readAllLines fills a caller array and RESULTs the count [G6-18, 1.7]"
L="$W/lines.txt"
printf 'one\ntwo\nthree\n' > "$L"
declare -a lines=()
rc=0
tfile.readAllLines "$L" lines || rc=$?
if (( rc == 0 )) && (( ${#lines[@]} == 3 )) \
   && [[ "${lines[0]}" == "one" && "${lines[2]}" == "three" && "$RESULT" == "3" ]]; then
    kt_test_pass "3 lines, RESULT=3"
else
    kt_test_fail "rc=$rc n=${#lines[@]} RESULT='$RESULT' lines=(${lines[*]})"
fi

kt_test_start "readAllLines keeps a line that looks like an echo option [X-ECHO]"
printf -- '-n\n-e\n' > "$L"
declare -a lines2=()
tfile.readAllLines "$L" lines2 || :
if (( ${#lines2[@]} == 2 )) && [[ "${lines2[0]}" == "-n" && "${lines2[1]}" == "-e" ]]; then
    kt_test_pass "-n and -e survived"
else
    kt_test_fail "n=${#lines2[@]} lines=(${lines2[*]})"
fi

kt_test_start "readAllLines rejects a reserved output array name [1.7]"
rc=0
tfile.readAllLines "$L" IFS >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc"
fi

# --- G6-19: replace consumes the source ------------------------------------
kt_test_start "replace removes the source file [G6-19, .NET File.Replace]"
src="$W/r_src.txt"; dst="$W/r_dst.txt"; bak="$W/r_bak.txt"
printf 'new content\n' > "$src"
printf 'old content\n' > "$dst"
rm -f -- "$bak"
rc=0
tfile.replace "$src" "$dst" "$bak" || rc=$?
if (( rc == 0 )) && [[ ! -e "$src" ]] \
   && [[ "$(cat "$dst")" == "new content" ]] && [[ "$(cat "$bak")" == "old content" ]]; then
    kt_test_pass "source gone, destination replaced, backup holds the old content"
else
    kt_test_fail "rc=$rc src_left=$([[ -e "$src" ]] && echo yes || echo no) dst='$(cat "$dst" 2>/dev/null)' bak='$(cat "$bak" 2>/dev/null)'"
fi

kt_test_start "replace without a backup name still consumes the source [G6-19]"
printf 'newer\n' > "$src"
printf 'older\n' > "$dst"
rc=0
tfile.replace "$src" "$dst" "" || rc=$?
if (( rc == 0 )) && [[ ! -e "$src" && "$(cat "$dst")" == "newer" ]]; then
    kt_test_pass "source gone, destination replaced"
else
    kt_test_fail "rc=$rc src_left=$([[ -e "$src" ]] && echo yes || echo no) dst='$(cat "$dst" 2>/dev/null)'"
fi

kt_test_start "a failed replace leaves BOTH files alone [G6-19, 1.2]"
printf 'stable\n' > "$dst"
rc=0
tfile.replace "$W/nosuch_src.txt" "$dst" "$W/never.txt" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ "$(cat "$dst")" == "stable" && ! -e "$W/never.txt" ]]; then
    kt_test_pass "rc 1, nothing touched"
else
    kt_test_fail "rc=$rc dst='$(cat "$dst")' backup=$([[ -e "$W/never.txt" ]] && echo made || echo absent)"
fi

# --- G6-26: the crypt temp file lands next to the file, not in $PWD --------
if command -v openssl >/dev/null 2>&1; then
    kt_test_start "encrypt/decrypt round-trips and leaves no temp file behind [G6-26]"
    sub="$W/crypt sub"
    mkdir -p "$sub"
    C="$sub/secret.txt"
    printf 'top secret\n' > "$C"
    before="$(cd "$SCRIPT_DIR" && ls -A | wc -l)"
    tfile.encrypt "$C" "pw123" || :
    enc_ok=no
    [[ "$(cat "$C")" != "top secret" ]] && enc_ok=yes
    tfile.decrypt "$C" "pw123" || :
    after="$(cd "$SCRIPT_DIR" && ls -A | wc -l)"
    leftovers="$(ls -A "$sub" | grep -c '^\.tfile_crypt' || true)"
    if [[ "$enc_ok" == "yes" && "$(cat "$C")" == "top secret" \
       && "$before" == "$after" && "$leftovers" == "0" ]]; then
        kt_test_pass "round trip clean, no temp left"
    else
        kt_test_fail "enc=$enc_ok text='$(cat "$C")' cwd $before->$after leftovers=$leftovers"
    fi

    # The finding itself: `dir="${file%/*}"` only understood `/`, so a path
    # addressed with a BACKSLASH separator (which the MSYS runtime resolves)
    # produced dir="." and the temp file was written into $PWD instead of next
    # to the file. Run it from a directory we can inspect afterwards.
    kt_test_start "encrypt of a backslash-addressed path keeps its temp file next to the file [G6-26]"
    bsdir="$W/bs sub"
    mkdir -p "$bsdir"
    printf 'secret2\n' > "$bsdir/bs.txt"
    win_style="${bsdir}\\bs.txt"
    cwd_probe="$W/cwd probe"
    mkdir -p "$cwd_probe"
    cd "$cwd_probe" || exit 1
    rc=0
    tfile.encrypt "$win_style" "pw123" >/dev/null 2>&1 || rc=$?
    cwd_left="$(ls -A . | wc -l)"
    cd "$SCRIPT_DIR" || exit 1
    if (( rc == 0 )) && [[ "$(cat "$bsdir/bs.txt")" != "secret2" ]] && (( cwd_left == 0 )); then
        tfile.decrypt "$win_style" "pw123" || :
        if [[ "$(cat "$bsdir/bs.txt")" == "secret2" ]]; then
            kt_test_pass "round trip, nothing left in \$PWD"
        else
            kt_test_fail "decrypt did not restore the text"
        fi
    else
        kt_test_fail "rc=$rc cwd_left=$cwd_left text='$(cat "$bsdir/bs.txt")'"
    fi
else
    kt_test_start "openssl is available for the crypt tests [G6-26]"
    kt_test_fail "openssl not found — the encrypt/decrypt path cannot be tested"
fi

# --- writeAllBytes: what it can and cannot do ------------------------------
kt_test_start "writeAllBytes writes text that looks like an echo option [X-ECHO]"
B="$W/bytes.bin"
tfile.writeAllBytes "$B" "-neE" || :
if [[ "$(wc -c < "$B")" == "4" ]]; then
    kt_test_pass "4 bytes"
else
    kt_test_fail "$(wc -c < "$B") bytes"
fi

kt_test_start "writeAllBytes writes a multi-line payload verbatim [G6-18]"
tfile.writeAllBytes "$B" $'a\nb\n' || :
if [[ "$(wc -c < "$B")" == "4" ]]; then
    kt_test_pass "4 bytes"
else
    kt_test_fail "$(wc -c < "$B") bytes"
fi
