#!/usr/bin/env bash
# fvu_testlib.sh — what the fv.unicode test files share. Not a test file: the
# ktests runner picks up NNN_*.sh only.
#
#   fvu_init NAME "$@"     ktest init + the unit + a scratch folder ($FVU_TMP)
#   fvu_page P             FVU_PAGE = the 256 class letters of page P (from
#                          __FV_UC_P, or the unit's own expansion of __FV_UC_M)

FVU_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVU_TESTS_DIR/../../../ktests/ktest.sh"

fvu_init() {
    local name=$1
    shift
    source "$FVU_TESTS_DIR/../fv.unicode.sh"
    kt_test_init "$name" "$FVU_TESTS_DIR" "$@"
    FVU_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVU_UNIT="$(cd "$FVU_TESTS_DIR/.." && pwd)/fv.unicode.sh"
    FVU_KBOOL="$(cd "$FVU_TESTS_DIR/../../.." && pwd)/kbool.sh"
}

fvu_page() {
    local k=${__FV_UC_P[$1 >> 6]:$1 % 64:1} s i
    if [[ $k == '*' ]]; then
        fv.unicode._expand "$1"
        FVU_PAGE=''
        for (( i = 0; i < 16; i++ )); do FVU_PAGE+=${__FV_UC_E[$1 * 16 + i]}; done
    else
        printf -v s '%256s' ''
        FVU_PAGE=${s// /$k}
    fi
}
