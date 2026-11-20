#!/usr/bin/env bash
# 013_Generator.sh - the generator behind the layout tables (kbool
# tools/kbdlayout): its selftest runs here, so every gate runtime checks it
# with the awk it has (Debian's default is mawk): the fixtures give the
# committed golden output, a second run is byte-identical, the fixture entries
# read back from the output are the written-down ones, --out, the error paths
# (incl. an archive that is not the pinned one). With KBDLAYOUT_SRC set (the
# folder of the two pinned archives) it also regenerates the committed
# fv.keyboard.layouts.sh and compares it byte for byte. Outside a kbool tree
# (kcl alone) there is no tools/kbdlayout: SKIP: ENV.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: the layout-table generator"

ST="$(cd "$FVK_TESTS_DIR/../../.." && pwd)/tools/kbdlayout/tests/selftest.sh"
kt_test_start "tools/kbdlayout/tests/selftest.sh: every case passes with the awks of this runtime"
if [[ ! -f $ST ]]; then
    kt_test_pass "SKIP: ENV: no tools/kbdlayout here (kcl outside a kbool tree)"
else
    out="$(bash "$ST" 2>&1)"; rc=$?
    sum=${out##*$'\n'}
    if [[ $rc == 0 && $sum == *' passed, 0 failed, '*' skipped' ]]; then kt_test_pass "$sum"
    else kt_test_fail "rc=$rc: $(grep '^FAIL' <<<"$out" | head -5 | tr '\n' ' ') $sum"; fi
fi

kt_test_log "013_Generator.sh completed"
