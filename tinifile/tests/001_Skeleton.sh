#!/bin/bash
# 001_Skeleton.sh - tinifile P0 skeleton gate. Pins the CTOR CORE (the part
# that is real at P0): the FPC class split — TIniFile auto-adds ifoStripQuotes
# and is eager (cache_updates=false), TMemIniFile does NOT auto-add and is
# cached (cache_updates=true) — plus option-token parsing (incl. the
# ifoWriteStringBoolean alias), storage initialization/teardown, inheritance
# wiring, stub sentinels, re-source guard, zero-fork. File I/O arrives P1/P2.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TIniFile/TMemIniFile skeleton (P0 ctor core)"

# --- TIniFile defaults: eager + AUTO ifoStripQuotes (FPC :967) ---
kt_test_start "TIniFile: file_name, cache_updates=false, dirty=false, AUTO StripQuotes"
TIniFile.new I "/tmp/a.ini"
if [[ "$(I.file_name)" == "/tmp/a.ini" && "$(I.cache_updates)" == "false" \
      && "$(I.dirty)" == "false" && " $(I.options) " == *" ifoStripQuotes "* ]]; then
    kt_test_pass "eager + auto-quotes"
else
    kt_test_fail "fn=$(I.file_name) cu=$(I.cache_updates) d=$(I.dirty) opts='$(I.options)'"
fi

# --- TMemIniFile: cached + NO auto StripQuotes (FPC :969 self-is check) ---
kt_test_start "TMemIniFile: cache_updates=true, NO auto StripQuotes"
TMemIniFile.new M "/tmp/b.ini"
if [[ "$(M.cache_updates)" == "true" && " $(M.options) " != *" ifoStripQuotes "* \
      && "$(M.file_name)" == "/tmp/b.ini" ]]; then
    kt_test_pass "cached, no auto-quotes"
else
    kt_test_fail "cu=$(M.cache_updates) opts='$(M.options)'"
fi

# --- option tokens: parsed, deduped, alias normalized ---
kt_test_start "tokens: CaseSensitive kept; alias ifoWriteStringBoolean -> ifoStringBoolean"
TIniFile.new T "/tmp/c.ini" ifoCaseSensitive ifoWriteStringBoolean
o=" $(T.options) "
if [[ "$o" == *" ifoCaseSensitive "* && "$o" == *" ifoStringBoolean "* \
      && "$o" != *"ifoWriteStringBoolean"* && "$o" == *" ifoStripQuotes "* ]]; then
    kt_test_pass "parsed + normalized + auto-quotes: $(T.options)"
else
    kt_test_fail "opts='$(T.options)'"
fi
T.delete

# --- TMemIniFile CAN opt in to StripQuotes explicitly ---
kt_test_start "TMemIniFile with explicit ifoStripQuotes keeps it"
TMemIniFile.new M2 "/tmp/d.ini" ifoStripQuotes
[[ " $(M2.options) " == *" ifoStripQuotes "* ]] && kt_test_pass "explicit opt-in ok" \
    || kt_test_fail "opts='$(M2.options)'"
M2.delete

# --- bogus token -> rc 1, instance still valid (accepted tokens kept) ---
kt_test_start "unknown token -> rc 1; instance valid; ifoFormatSettingsActive rejected"
TIniFile.new B "/tmp/e.ini" ifoCaseSensitive ifoFormatSettingsActive 2>/dev/null
rc=$?
if [[ $rc -ne 0 && "$(B.file_name)" == "/tmp/e.ini" && " $(B.options) " == *" ifoCaseSensitive "* ]]; then
    kt_test_pass "rc=$rc, instance usable, prior tokens kept"
else
    kt_test_fail "rc=$rc fn=$(B.file_name) opts='$(B.options)'"
fi
B.delete

# --- storage arrays exist and are empty ---
kt_test_start "storage: secnames/kident/kvalue/kowner exist, empty"
ok=1
for a in I_secnames I_kident I_kvalue I_kowner; do
    declare -p "$a" >/dev/null 2>&1 || ok=0
done
declare -n __chk=I_secnames
[[ $ok -eq 1 && "${#__chk[@]}" == "0" ]] && kt_test_pass "4 arrays, empty" \
    || kt_test_fail "ok=$ok n=${#__chk[@]}"
unset -n __chk

# --- inheritance wiring ---
kt_test_start "inheritance: M is TMemIniFile, parent chain reaches TIniFile"
mc_var="M_class"; pc_var="TMemIniFile_parent_class"
[[ "${!mc_var}" == "TMemIniFile" && "${!pc_var}" == "TIniFile" ]] \
    && kt_test_pass "class + parent chain ok" || kt_test_fail "class=${!mc_var} parent=${!pc_var}"

# --- all members real (no stubs remain post-P3): typed read on empty ini ---
kt_test_start "typed accessors dispatch: empty ini -> defaults, rc 0"
I.ReadInteger a b 42
r1="$RESULT"
I.ReadBool a b 1
r2="$RESULT"
[[ "$r1" == "42" && "$r2" == "1" ]] \
    && kt_test_pass "ReadInteger/ReadBool return defaults" || kt_test_fail "r1='$r1' r2='$r2'"

# --- destroy tears down the storage arrays ---
kt_test_start "delete: storage arrays are unset"
I.delete
declare -p I_secnames >/dev/null 2>&1 && kt_test_fail "I_secnames survived delete" \
    || kt_test_pass "storage gone"
M.delete

# --- re-source guard ---
kt_test_start "re-source is a clean no-op"
source "$TIF_DIR/tinifile.sh"
rc=$?
[[ $rc -eq 0 ]] && kt_test_pass "second source rc 0" || kt_test_fail "rc=$rc"

# --- zero-fork: ctor/dtor + stubs under PATH='' ---
kt_test_start "PATH='' : ctor/dtor/stub dispatch need no external commands"
zf="$(
    PATH=''
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    TIniFile.new Z "/tmp/z.ini" ifoCaseSensitive
    a="$(Z.cache_updates)"
    TMemIniFile.new ZM "/tmp/zm.ini"
    b="$(ZM.cache_updates)"
    Z.ReadString s k d >/dev/null; c="$RESULT"   # real now: empty ini -> default
    Z.delete; ZM.delete
    printf '%s|%s|%s' "$a" "$b" "$c"
)"
[[ "$zf" == "false|true|d" ]] && kt_test_pass "$zf" \
    || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "001_Skeleton.sh completed"
