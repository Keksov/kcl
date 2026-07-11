#!/bin/bash
# P5.1 — recode* family (own-design). '-' = RecodeLeaveFieldAsIs.
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Recode" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }
D=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)

# --- single-field recode keeps the other fields -----------------------------
kt_test_start "recodeYear/Month/Day/Hour/Minute/Second/MilliSecond change one field only"
ok=true
[[ "$(fmt "$(dateutils.recodeYear $D 2020)")"        == "2020-03-26 19:15:30.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeMonth $D 12)")"         == "2011-12-26 19:15:30.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeDay $D 1)")"            == "2011-03-01 19:15:30.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeHour $D 0)")"           == "2011-03-26 00:15:30.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeMinute $D 45)")"        == "2011-03-26 19:45:30.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeSecond $D 0)")"         == "2011-03-26 19:15:00.555" ]] || ok=false
[[ "$(fmt "$(dateutils.recodeMilliSecond $D 0)")"    == "2011-03-26 19:15:30.000" ]] || ok=false
$ok && kt_test_pass "recodeYear/Month/Day/Hour/Minute/Second/MilliSecond change one field only" \
     || kt_test_fail "single-field recode wrong"

# --- recodeDate / recodeTime / recodeDateTime -------------------------------
kt_test_start "recodeDate/recodeTime/recodeDateTime replace groups, keep the rest"
ok=true
[[ "$(fmt "$(dateutils.recodeDate $D 2000 1 15)")"          == "2000-01-15 19:15:30.555" ]] || ok=false  # time kept
[[ "$(fmt "$(dateutils.recodeTime $D 8 5 1 2)")"            == "2011-03-26 08:05:01.002" ]] || ok=false  # date kept
[[ "$(fmt "$(dateutils.recodeDateTime $D 1999 12 31 23 59 59 999)")" == "1999-12-31 23:59:59.999" ]] || ok=false
$ok && kt_test_pass "recodeDate/recodeTime/recodeDateTime replace groups, keep the rest" \
     || kt_test_fail "group recode wrong"

# --- '-' sentinel leaves a field as is --------------------------------------
kt_test_start "recodeDateTime with '-' leaves those fields untouched"
# change only month and second, keep the rest
if [[ "$(fmt "$(dateutils.recodeDateTime $D - 6 - - - 0 -)")" == "2011-06-26 19:15:00.555" ]] \
   && [[ "$(fmt "$(dateutils.recodeDateTime $D - - - - - - -)")" == "2011-03-26 19:15:30.555" ]]; then
    kt_test_pass "recodeDateTime with '-' leaves those fields untouched"
else
    kt_test_fail "'-' sentinel handling wrong"
fi

# --- invalid recombination fails with status 1 ------------------------------
kt_test_start "recode* reject an invalid recombination (status 1)"
ok=true
# Jan 31 -> month 2 : Feb has no 31
dateutils.recodeMonth "$(dateutils.encodeDate 2011 1 31)" 2 2>/dev/null && ok=false
# day 30 in February
dateutils.recodeDay "$(dateutils.encodeDate 2011 2 1)" 30 2>/dev/null && ok=false
# out-of-range hour
dateutils.recodeHour $D 25 2>/dev/null && ok=false
# tryRecodeDateTime is status-only too
dateutils.tryRecodeDateTime $D - 2 30 - - - - 2>/dev/null && ok=false
$ok && kt_test_pass "recode* reject an invalid recombination (status 1)" \
     || kt_test_fail "invalid recode not rejected"

# --- tryRecodeDateTime success path -----------------------------------------
kt_test_start "tryRecodeDateTime echoes the value and returns 0 on success"
if v=$(dateutils.tryRecodeDateTime $D 2015 - - - - - -) && [[ "$(fmt "$v")" == "2015-03-26 19:15:30.555" ]]; then
    kt_test_pass "tryRecodeDateTime echoes the value and returns 0 on success"
else
    kt_test_fail "tryRecodeDateTime success path wrong"
fi
