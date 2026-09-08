#!/bin/bash
# 012_D6_Locale.sh - decision D6 (kcl/PLAN.md section 1, kcl/README.md 1.6).
#
# Character semantics are part of this unit's contract: the case-insensitive
# lookup is `${x,,}`, which under the C locale leaves a multi-byte letter alone
# (and, on other operations, corrupts it). The test runners pin LC_ALL=C.UTF-8,
# but a caller who sources the unit from a bare environment - cron, a service
# manager, `env -i` - gets the C locale, so the unit self-heals at load time.
#
# Every case runs in a CHILD bash with LC_ALL, LC_CTYPE and LANG cleared: that
# is the only way to see the load-time behaviour, since the runner has already
# pinned the locale in this process.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "012_D6_Locale" "$SCRIPT_DIR" "$@"

kt_test_section "012: locale self-heal (D6)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"
printf '[Caf\xc3\xa9]\nna\xc3\xafve=1\n[plain]\nKEY=2\n' > "$D/u.ini"

bare() {   # SNIPPET -> stdout of a child bash with the three locale vars cleared
    env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$TIF_DIR/tinifile.sh'
$1" 2>&1
}

kt_test_start "D6: a bare environment gets LC_CTYPE=C.UTF-8 at load time"
out="$(bare 'printf "%s" "${LC_CTYPE:-<unset>}"')"
[[ "$out" == "C.UTF-8" ]] && kt_test_pass "LC_CTYPE=$out" || kt_test_fail "got '$out'"

kt_test_start "D6: the non-ASCII fold works in a bare environment (section name)"
out="$(bare "TMemIniFile.new U '$D/u.ini'
U.ReadString \$'CAF\xc3\x89' \$'na\xc3\xafve' MISS
printf '%s' \"\$RESULT\"
U.delete")"
[[ "$out" == "1" ]] && kt_test_pass "CAFE-with-accent found Cafe-with-accent" \
    || kt_test_fail "got '$out' (want 1; the C locale leaves the accent unfolded)"

kt_test_start "D6: the non-ASCII fold works in a bare environment (ident)"
out="$(bare "TMemIniFile.new U '$D/u.ini'
U.ReadString \$'caf\xc3\xa9' \$'NA\xc3\x8fVE' MISS
printf '%s' \"\$RESULT\"
U.delete")"
[[ "$out" == "1" ]] && kt_test_pass "ident folded too" \
    || kt_test_fail "got '$out' (want 1)"

kt_test_start "D6: values still round-trip byte-exact in a bare environment"
out="$(bare "TMemIniFile.new U '$D/w.ini'
U.WriteString s k 'Привет мир é'
U.UpdateFile
U.delete
TMemIniFile.new V '$D/w.ini'
V.ReadString s k MISS
printf '%s' \"\$RESULT\"
V.delete")"
[[ "$out" == "Привет мир é" ]] && kt_test_pass "lossless" || kt_test_fail "got '$out'"

kt_test_start "D6: an EXPLICIT locale is never overridden"
out="$(env -u LC_CTYPE -u LANG LC_ALL=C bash -c "
source '$TIF_DIR/tinifile.sh'
printf '%s|%s' \"\$LC_ALL\" \"\${LC_CTYPE:-<unset>}\"" 2>&1)"
[[ "$out" == "C|<unset>" ]] && kt_test_pass "$out" || kt_test_fail "got '$out'"

kt_test_start "D6: ASCII folding works regardless of the locale"
out="$(env -u LC_CTYPE -u LANG LC_ALL=C bash -c "
source '$TIF_DIR/tinifile.sh'
TMemIniFile.new U '$D/u.ini'
U.ReadString PLAIN key MISS
printf '%s' \"\$RESULT\"
U.delete" 2>&1)"
[[ "$out" == "2" ]] && kt_test_pass "ASCII case is locale-independent" || kt_test_fail "got '$out'"

kt_test_log "012_D6_Locale.sh completed"
