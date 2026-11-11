#!/usr/bin/env bash
# 003_Generator.sh - the generator behind the table (kbool tools/unicode): its
# selftest runs here, so every gate runtime checks it with the awk it has
# (Debian's default is mawk): the fixtures give the committed golden block, a
# second run is byte-identical, the fixture classes read back from the block are
# the written-down ones, --unit splices only the block, and the error paths.
# Outside a kbool tree (kcl alone) there is no tools/unicode: SKIP: ENV.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvu_testlib.sh"
fvu_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: the generator"

ST="$(cd "$FVU_TESTS_DIR/../../.." && pwd)/tools/unicode/tests/selftest.sh"
kt_test_start "tools/unicode/tests/selftest.sh: every case passes with the awks of this runtime"
if [[ ! -f $ST ]]; then
    kt_test_pass "SKIP: ENV: no tools/unicode here (kcl outside a kbool tree)"
else
    out="$(bash "$ST" 2>&1)"; rc=$?
    sum=${out##*$'\n'}
    if [[ $rc == 0 && $sum == 'selftest: '*' 0 FAIL'* ]]; then kt_test_pass "${sum#selftest: }"
    else kt_test_fail "rc=$rc: $(grep '^FAIL' <<<"$out" | head -5 | tr '\n' ' ') $sum"; fi
fi

kt_test_log "003_Generator.sh completed"
