#!/usr/bin/env bash
# fvk_testlib.sh — what the fv.keyboard test files share. Not a test file:
# the ktests runner picks up NNN_*.sh only.
#
#   fvk_init NAME "$@"     ktest init + the unit + a scratch folder ($FVK_TMP)
#   fvk_len BYTES          REPLY = the byte length of BYTES
#   fvk_vis BYTES          REPLY = BYTES printed with %q (for titles)
#   fvk_chk BYTES KEY [CHAR] [NOTE]
#                          one test: decode BYTES -> FV_KEY == KEY, every byte
#                          consumed, FV_KEY_SEQ == BYTES, FV_KEY_CHAR == CHAR
#                          (default: BYTES for kbChar, else empty)
#   fvk_keys VAR           decode every key of the queue+fd with
#                          getKeyEvent 0 until rc 1; VAR = "name|kbChar:c|..."
#   fvk_fdfile BYTES       FV_KEY_FD = a fresh read fd on a file holding BYTES
#                          (the queue is flushed)

FVK_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVK_TESTS_DIR/../../../ktests/ktest.sh"

fvk_init() {
    local name=$1
    shift
    source "$FVK_TESTS_DIR/../fv.keyboard.sh"
    kt_test_init "$name" "$FVK_TESTS_DIR" "$@"
    FVK_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
}

fvk_len() { local LC_ALL=C; REPLY=${#1}; }
fvk_vis() { printf -v REPLY '%q' "$1"; }

fvk_chk() {
    local bytes=$1 key=$2 note=${4-} want_c n
    if (( $# >= 3 )); then want_c=$3; elif [[ $key == kbChar ]]; then want_c=$bytes; else want_c=''; fi
    fvk_vis "$bytes"
    kt_test_start "decode $REPLY -> $key${want_c:+ '$want_c'}${note:+ ($note)}"
    fvk_len "$bytes"; n=$REPLY
    fv.keyboard.decode "$bytes"
    if [[ $FV_KEY == "$key" && $FV_KEY_LEN == "$n" && $FV_KEY_SEQ == "$bytes" && $FV_KEY_CHAR == "$want_c" && $RESULT == "$key" ]]; then
        kt_test_pass "ok"
    else
        fvk_vis "$FV_KEY_SEQ"
        kt_test_fail "got key=$FV_KEY char='$FV_KEY_CHAR' len=$FV_KEY_LEN of $n seq=$REPLY RESULT=$RESULT"
    fi
}

fvk_keys() {
    local -n __fvk_out=$1
    __fvk_out=''
    while fv.keyboard.getKeyEvent 0; do
        if [[ $FV_KEY == kbChar || $FV_KEY == kbAltChar ]]; then __fvk_out+="$FV_KEY:$FV_KEY_CHAR|"
        else __fvk_out+="$FV_KEY|"; fi
    done
    __fvk_out=${__fvk_out%|}
}

fvk_fdfile() {
    if [[ -n ${FVK_FD-} ]]; then exec {FVK_FD}<&-; fi
    printf '%s' "$1" > "$FVK_TMP/in.bin"
    exec {FVK_FD}< "$FVK_TMP/in.bin"
    FV_KEY_FD=$FVK_FD
    fv.keyboard.flush
}
