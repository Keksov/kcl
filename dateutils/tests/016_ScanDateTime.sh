#!/bin/bash
# P7.1 — scanDateTime practical subset (own-design). The tw16040 anchor lives in
# 002_FpcParity.sh. Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ScanDateTime" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- pattern/input -> KDT fixture table -------------------------------------
kt_test_start "scanDateTime parses the common patterns to the right KDT"
ok=true
check() {  # pattern input  expected(y m d h n s ms)
    local got exp; got=$(dateutils.scanDateTime "$1" "$2") || { ok=false; echo "  [$1] [$2] failed" >&2; return; }
    exp=$(dateutils.encodeDateTime $3 $4 $5 $6 $7 $8 $9)
    [[ "$got" == "$exp" ]] || { ok=false; echo "  [$1] [$2] -> got $got want $exp" >&2; }
}
check "YYYY.MM.DD HH:NN:SS:ZZZ" "2011.03.29 16:46:56:777"  2011 3 29 16 46 56 777
check "yyyy-mm-dd hh:nn:ss"     "2011-03-26 19:15:30"      2011 3 26 19 15 30 0
check "dd/mm/yyyy"              "26/03/2011"               2011 3 26 0 0 0 0
check "yyyy-m-d h:n:s"          "2011-3-6 9:5:1"           2011 3 6 9 5 1 0     # single-digit fields
check "yyyymmdd"               "20110326"                 2011 3 26 0 0 0 0     # no separators
check "hh:nn"                  "23:59"                    1970 1 1 23 59 0 0     # time only (date defaults to the epoch)
$ok && kt_test_pass "scanDateTime parses the common patterns to the right KDT" \
     || kt_test_fail "scanDateTime pattern parsing wrong"

# --- quoted literals + elastic whitespace -----------------------------------
kt_test_start "scanDateTime handles quoted literals and elastic whitespace"
ok=true
[[ "$(dateutils.scanDateTime 'yyyy"T"hh' '2011T09')" == "$(dateutils.encodeDateTime 2011 1 1 9 0 0 0)" ]] || ok=false
[[ "$(dateutils.scanDateTime "yyyy'x'mm" "2011x03")"  == "$(dateutils.encodeDate 2011 3 1)" ]] || ok=false
# one pattern space matches a run of input spaces
[[ "$(dateutils.scanDateTime "yyyy mm dd" "2011   03    26")" == "$(dateutils.encodeDate 2011 3 26)" ]] || ok=false
$ok && kt_test_pass "scanDateTime handles quoted literals and elastic whitespace" \
     || kt_test_fail "scanDateTime literal/whitespace wrong"

# --- 2-digit year pivots at 50 ----------------------------------------------
kt_test_start "scanDateTime: 2-digit year pivots at 50 (00-49 -> 20xx, 50-99 -> 19xx)"
ok=true
[[ "$(dateutils.scanDateTime "yy-mm-dd" "23-03-26")" == "$(dateutils.encodeDate 2023 3 26)" ]] || ok=false
[[ "$(dateutils.scanDateTime "yy-mm-dd" "49-01-01")" == "$(dateutils.encodeDate 2049 1 1)" ]] || ok=false
[[ "$(dateutils.scanDateTime "yy-mm-dd" "50-01-01")" == "$(dateutils.encodeDate 1950 1 1)" ]] || ok=false
[[ "$(dateutils.scanDateTime "yy-mm-dd" "76-03-26")" == "$(dateutils.encodeDate 1976 3 26)" ]] || ok=false
$ok && kt_test_pass "scanDateTime: 2-digit year pivots at 50 (00-49 -> 20xx, 50-99 -> 19xx)" \
     || kt_test_fail "scanDateTime year pivot wrong"

# --- mismatches -> status 1 -------------------------------------------------
kt_test_start "scanDateTime rejects separator/field mismatches and invalid dates"
ok=true
dateutils.scanDateTime "yyyy-mm-dd" "2011/03/26" 2>/dev/null && ok=false   # wrong separator
dateutils.scanDateTime "yyyy-mm-dd" "abcd-03-26" 2>/dev/null && ok=false   # non-digit where a number is expected
dateutils.scanDateTime "yyyy-mm-dd" "2011-13-01" 2>/dev/null && ok=false   # invalid month
dateutils.scanDateTime "yyyy-mm-dd" "2011-02-30" 2>/dev/null && ok=false   # invalid day
dateutils.scanDateTime "hh:nn"      "25:00"      2>/dev/null && ok=false   # invalid hour
$ok && kt_test_pass "scanDateTime rejects separator/field mismatches and invalid dates" \
     || kt_test_fail "scanDateTime rejection wrong"

# --- roundtrip: scan(format) ------------------------------------------------
kt_test_start "scanDateTime inverts the canonical ISO format"
dt=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
dateutils._fmt_datetime "$dt"; s=$REPLY   # "2011-03-26 19:15:30.555"
if [[ "$(dateutils.scanDateTime 'yyyy-mm-dd hh:nn:ss.zzz' "$s")" == "$dt" ]]; then
    kt_test_pass "scanDateTime inverts the canonical ISO format"
else
    kt_test_fail "scanDateTime did not invert _fmt_datetime"
fi
