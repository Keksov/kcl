#!/bin/bash
# P5-F1 (owner decision 2026-09-09): compareTo is FPC's StrComp — an ORDINAL,
# byte-wise comparison independent of the caller's locale. compare and
# compareOrdinal keep comparing the WHOLE strings (a documented difference from
# FPC's prefix comparison) and are pinned here so nobody "fixes" them to FPC.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
kt_test_init "P5F1_CompareTo" "$SCRIPT_DIR" "$@"
UNIT="$SCRIPT_DIR/../tstringhelper.sh"
source "$UNIT"

kt_test_start "compareTo is byte order under a locale whose collation differs (de_DE: a < B) [P5-F1]"
got="$(LC_ALL=de_DE.UTF-8 bash -c "source '$UNIT'; string.compareTo a B >/dev/null; printf %s \"\$RESULT\"")"
[[ "$got" == "1" ]] && kt_test_pass "compareTo a B = 1 (byte 97 > 66)" || kt_test_fail "compareTo a B = '$got' under de_DE (collation leaked)"

kt_test_start "compareTo does not change the caller's locale [P5-F1]"
before="${LC_ALL:-}"; string.compareTo x y >/dev/null; [[ "${LC_ALL:-}" == "$before" ]] && kt_test_pass "LC_ALL intact" || kt_test_fail "LC_ALL=${LC_ALL:-}"

kt_test_start "compareTo equal / less / greater [P5-F1]"
string.compareTo abc abc >/dev/null; e="$RESULT"; string.compareTo abc abd >/dev/null; l="$RESULT"; string.compareTo b a >/dev/null; g="$RESULT"
[[ "$e" == 0 && "$l" == -1 && "$g" == 1 ]] && kt_test_pass "0 / -1 / 1" || kt_test_fail "e=$e l=$l g=$g"

kt_test_start "compare / compareOrdinal compare the WHOLE strings (documented FPC difference) [P5-F1]"
string.compare abc ab >/dev/null; c1="$RESULT"; string.compareOrdinal abc ab >/dev/null; c2="$RESULT"
[[ "$c1" == 1 && "$c2" == 1 ]] && kt_test_pass "compare('abc','ab') = 1 (FPC would say 0)" || kt_test_fail "c1=$c1 c2=$c2"
kt_test_log "067 completed"
