#!/bin/bash
# 005_FpcBoolParity.sh - the COMPLETE fpcunit seed
#   packages/fcl-base/tests/utcinifile.pp
# mined verbatim: TIniFile_TestWriteBoolean + TIniFile_TestReadBoolean, all 16
# AssertEquals adapted to bash. Mapping: TMemIniFile.Create('tmp.ini') (fresh
# per FPC Setup) -> a fresh TMemIniFile per block (in-memory, cached; no file);
# `Options := Options + [ifoWriteStringBoolean]` -> append the ifoStringBoolean
# token to the `options` var (FPC :272 alias); SetBoolStringValues(bool,[...])
# -> same call; ReadBool default is a Boolean -> 0/1. Each case cites its seed
# line. This is the ONLY FPC test that exists for tinifile (P0 finding).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: FPC utcinifile.pp Bool parity (16 assertions)"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
opt_add() { local cur; cur="$($1.options)"; $1.options = "${cur:+$cur }ifoStringBoolean"; }

# ================= TIniFile_TestWriteBoolean (seed :43-64) =================
TMemIniFile.new W "$D/w.ini"       # cached, never flushed (dirty cleared)

kt_test_start "TestWriteBoolean :50 — default true -> '1'"
W.WriteBool a b true; W.ReadString a b ""
[[ "$RESULT" == "1" ]] && kt_test_pass "1" || kt_test_fail "got '$RESULT'"

kt_test_start "TestWriteBoolean :52 — default false -> '0'"
W.WriteBool a b false; W.ReadString a b ""
[[ "$RESULT" == "0" ]] && kt_test_pass "0" || kt_test_fail "got '$RESULT'"

opt_add W                          # :53 Options += ifoWriteStringBoolean

kt_test_start "TestWriteBoolean :55 — string true -> 'true'"
W.WriteBool a b true; W.ReadString a b ""
[[ "$RESULT" == "true" ]] && kt_test_pass "true" || kt_test_fail "got '$RESULT'"

kt_test_start "TestWriteBoolean :57 — string false -> 'false'"
W.WriteBool a b false; W.ReadString a b ""
[[ "$RESULT" == "false" ]] && kt_test_pass "false" || kt_test_fail "got '$RESULT'"

kt_test_start "TestWriteBoolean :60 — true from BoolTrueStrings[0] -> 't'"
W.SetBoolStringValues true t true
W.WriteBool a b true; W.ReadString a b ""
[[ "$RESULT" == "t" ]] && kt_test_pass "t" || kt_test_fail "got '$RESULT'"

kt_test_start "TestWriteBoolean :63 — false from BoolFalseStrings[0] -> 'f'"
W.SetBoolStringValues false f false
W.WriteBool a b false; W.ReadString a b ""
[[ "$RESULT" == "f" ]] && kt_test_pass "f" || kt_test_fail "got '$RESULT'"
W.dirty = "false"; W.delete

# ================= TIniFile_TestReadBoolean (seed :66-104) =================
TMemIniFile.new R "$D/r.ini"

kt_test_start "TestReadBoolean :73 — '1' -> true"
R.WriteString a b 1; R.ReadBool a b 0
[[ "$RESULT" == "1" ]] && kt_test_pass "true" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :75 — '0' -> false"
R.WriteString a b 0; R.ReadBool a b 1
[[ "$RESULT" == "0" ]] && kt_test_pass "false" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :77 — empty returns Default"
R.WriteString a b ""; R.ReadBool a b 1
[[ "$RESULT" == "1" ]] && kt_test_pass "default true" || kt_test_fail "got '$RESULT'"

R.SetBoolStringValues true t true      # :78

kt_test_start "TestReadBoolean :80 — first string match ('t') -> true"
R.WriteString a b t; R.ReadBool a b 0
[[ "$RESULT" == "1" ]] && kt_test_pass "true" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :82 — second string match ('true') -> true"
R.WriteString a b true; R.ReadBool a b 0
[[ "$RESULT" == "1" ]] && kt_test_pass "true" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :84 — no match -> default true"
R.WriteString a b d; R.ReadBool a b 1
[[ "$RESULT" == "1" ]] && kt_test_pass "default" || kt_test_fail "got '$RESULT'"

R.SetBoolStringValues true            # :85 clear true
R.SetBoolStringValues false f false   # :86

kt_test_start "TestReadBoolean :88 — first false match ('f') -> false"
R.WriteString a b f; R.ReadBool a b 1
[[ "$RESULT" == "0" ]] && kt_test_pass "false" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :90 — second false match ('false') -> false"
R.WriteString a b false; R.ReadBool a b 1
[[ "$RESULT" == "0" ]] && kt_test_pass "false" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :92 — no match -> default false"
R.WriteString a b d; R.ReadBool a b 0
[[ "$RESULT" == "0" ]] && kt_test_pass "default false" || kt_test_fail "got '$RESULT'"

R.SetBoolStringValues true t true     # :93 (bt+bf both set, value still 'd')

kt_test_start "TestReadBoolean :94 — both lists set, no match -> default false"
R.ReadBool a b 0
[[ "$RESULT" == "0" ]] && kt_test_pass "default false 2" || kt_test_fail "got '$RESULT'"

R.SetBoolStringValues true            # :95 clear both
R.SetBoolStringValues false           # :96
opt_add R                             # :97 Options += ifoWriteStringBoolean

kt_test_start "TestReadBoolean :99 — ifoStringBoolean 'true' string -> true"
R.WriteString a b true; R.ReadBool a b 0
[[ "$RESULT" == "1" ]] && kt_test_pass "true" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :101 — ifoStringBoolean 'false' string -> false"
R.WriteString a b false; R.ReadBool a b 1
[[ "$RESULT" == "0" ]] && kt_test_pass "false" || kt_test_fail "got '$RESULT'"

kt_test_start "TestReadBoolean :103 — ifoStringBoolean no match -> default"
R.WriteString a b soso; R.ReadBool a b 1
[[ "$RESULT" == "1" ]] && kt_test_pass "default" || kt_test_fail "got '$RESULT'"
R.dirty = "false"; R.delete

kt_test_log "005_FpcBoolParity.sh completed"
