#!/bin/bash
# 004_TypedAccessors.sh - tinifile P3: the typed Read/Write family + options.
# Pins from PLAN.md section 3: S5 integer val() grammar (decimal / $hex / 0x /
# &octal / %binary / leading-zero-is-DECIMAL / sign / invalid->default), the
# Integer==Int64 collapse, WriteInteger canonicalization, S6 ReadBool cascade
# (first-char / ifoStringBoolean SameText / BoolStrings case-insensitive
# membership) + WriteBool output modes, ReadFloat/WriteFloat STRING-PRESERVING
# (PLAN 2.6 — no canonicalization), and that typed reads go THROUGH ReadString
# (StripQuotes applies). The dense FPC Bool seed is 005_FpcBoolParity.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: TIniFile typed accessors + options (P3)"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

TMemIniFile.new M "$D/m.ini"

# ---- integers: S5 val() grammar ----
kt_test_start "S5: decimal / \$hex / 0x / &octal / %binary all parse"
M.WriteString n dec 42; M.WriteString n h1 '$FF'; M.WriteString n h2 '0x1A'
M.WriteString n o '&17'; M.WriteString n b '%1010'
M.ReadInteger n dec 0; a=$RESULT
M.ReadInteger n h1 0;  b=$RESULT
M.ReadInteger n h2 0;  c=$RESULT
M.ReadInteger n o 0;   d=$RESULT
M.ReadInteger n b 0;   e=$RESULT
[[ "$a/$b/$c/$d/$e" == "42/255/26/15/10" ]] && kt_test_pass "$a/$b/$c/$d/$e" || kt_test_fail "$a/$b/$c/$d/$e"

kt_test_start "S5: sign + leading-zero-is-DECIMAL (not C-octal)"
M.WriteString n neg '-7'; M.WriteString n pos '+9'; M.WriteString n lead '0123'
M.ReadInteger n neg 0;  a=$RESULT
M.ReadInteger n pos 0;  b=$RESULT
M.ReadInteger n lead 0; c=$RESULT
[[ "$a/$b/$c" == "-7/9/123" ]] && kt_test_pass "$a/$b/$c" || kt_test_fail "$a/$b/$c"

kt_test_start "S5: invalid / absent -> Default (rc 0)"
M.WriteString n bad 'x9'; M.WriteString n bad2 '12x'
M.ReadInteger n bad 99;    a=$RESULT
M.ReadInteger n bad2 99;   b=$RESULT
M.ReadInteger n absent 77; c=$RESULT
[[ "$a/$b/$c" == "99/99/77" ]] && kt_test_pass "$a/$b/$c" || kt_test_fail "$a/$b/$c"

kt_test_start "ReadInt64 == ReadInteger path; large 64-bit value"
M.WriteString n big '9000000000'
M.ReadInt64 n big 0; a=$RESULT
M.ReadInteger n big 0; b=$RESULT
[[ "$a" == "9000000000" && "$b" == "9000000000" ]] && kt_test_pass "no 32-bit clamp" || kt_test_fail "i64=$a int=$b"

kt_test_start "WriteInteger canonicalizes to decimal; rejects non-int"
M.WriteInteger n canon '$FF'
M.ReadString n canon RAW; a=$RESULT
M.WriteInteger n bad 'nope' 2>/dev/null; rc=$?
[[ "$a" == "255" && $rc -eq 1 ]] && kt_test_pass "canonical '255', bad rc1" || kt_test_fail "a=$a rc=$rc"

# ---- bool: cascade branches (dense FPC seed lives in 005) ----
kt_test_start "S6: default cascade — first char == '1'"
M.WriteString bl t 1; M.WriteString bl f 0; M.WriteString bl weird '1abc'; M.WriteString bl no 'x'
M.ReadBool bl t 0;     a=$RESULT
M.ReadBool bl f 1;     b=$RESULT
M.ReadBool bl weird 0; c=$RESULT
M.ReadBool bl no 1;    d=$RESULT
[[ "$a/$b/$c/$d" == "1/0/1/0" ]] && kt_test_pass "$a/$b/$c/$d" || kt_test_fail "$a/$b/$c/$d"

kt_test_start "S6: empty value and absent both -> Default"
M.WriteString bl empty ""
M.ReadBool bl empty 1;  a=$RESULT
M.ReadBool bl gone 0;   b=$RESULT
[[ "$a/$b" == "1/0" ]] && kt_test_pass "$a/$b" || kt_test_fail "$a/$b"

kt_test_start "S6: ifoStringBoolean branch — case-insensitive true/false, else Default"
M.options = "ifoStringBoolean"
M.WriteString bl st TRUE; M.WriteString bl sf False; M.WriteString bl sx maybe
M.ReadBool bl st 0;  a=$RESULT
M.ReadBool bl sf 1;  b=$RESULT
M.ReadBool bl sx 1;  c=$RESULT
M.options = ""
[[ "$a/$b/$c" == "1/0/1" ]] && kt_test_pass "$a/$b/$c" || kt_test_fail "$a/$b/$c"

kt_test_start "S6: BoolStrings membership is case-insensitive (CompareText)"
M.SetBoolStringValues true yes on
M.SetBoolStringValues false no off
M.WriteString bl y1 YES; M.WriteString bl n1 Off; M.WriteString bl z1 huh
M.ReadBool bl y1 0; a=$RESULT
M.ReadBool bl n1 1; b=$RESULT
M.ReadBool bl z1 1; c=$RESULT
[[ "$a/$b/$c" == "1/0/1" ]] && kt_test_pass "$a/$b/$c" || kt_test_fail "$a/$b/$c"
M.SetBoolStringValues true; M.SetBoolStringValues false

kt_test_start "WriteBool output: '1'/'0' default; rejects non-bool"
M.WriteBool bl w1 true;  M.ReadString bl w1 X; a=$RESULT
M.WriteBool bl w0 false; M.ReadString bl w0 X; b=$RESULT
M.WriteBool bl w2 2 2>/dev/null; rc=$?
[[ "$a/$b" == "1/0" && $rc -eq 1 ]] && kt_test_pass "1/0, non-bool rc1" || kt_test_fail "a=$a b=$b rc=$rc"

kt_test_start "WriteBool + ifoStringBoolean: 'true'/'false' then BoolStrings[0]"
M.options = "ifoStringBoolean"
M.WriteBool bl s1 true;  M.ReadString bl s1 X; a=$RESULT
M.SetBoolStringValues true T yes
M.SetBoolStringValues false F no
M.WriteBool bl s2 true;  M.ReadString bl s2 X; b=$RESULT
M.WriteBool bl s3 false; M.ReadString bl s3 X; c=$RESULT
M.options = ""; M.SetBoolStringValues true; M.SetBoolStringValues false
[[ "$a/$b/$c" == "true/T/F" ]] && kt_test_pass "$a/$b/$c" || kt_test_fail "$a/$b/$c"

# ---- float: string-preserving (PLAN 2.6) ----
kt_test_start "PLAN 2.6: ReadFloat preserves the LITERAL (no canonicalization)"
M.WriteFloat fl a '1.50'; M.WriteFloat fl b '-3.14e-2'; M.WriteFloat fl c '.5'; M.WriteFloat fl d '42'
M.ReadFloat fl a 0; a=$RESULT
M.ReadFloat fl b 0; b=$RESULT
M.ReadFloat fl c 0; c=$RESULT
M.ReadFloat fl d 0; d=$RESULT
[[ "$a/$b/$c/$d" == "1.50/-3.14e-2/.5/42" ]] && kt_test_pass "$a/$b/$c/$d" || kt_test_fail "$a/$b/$c/$d"

kt_test_start "ReadFloat/WriteFloat reject non-floats -> Default / rc 1"
M.WriteString fl notf hello
M.ReadFloat fl notf 9.9; a=$RESULT
M.ReadFloat fl gone 1.1; b=$RESULT
M.WriteFloat fl bad 'abc' 2>/dev/null; rc=$?
M.WriteFloat fl bad2 '1.2.3' 2>/dev/null; rc2=$?
[[ "$a/$b" == "9.9/1.1" && $rc -eq 1 && $rc2 -eq 1 ]] && kt_test_pass "defaults + rc1" || kt_test_fail "a=$a b=$b rc=$rc/$rc2"

# ---- typed reads go THROUGH ReadString (StripQuotes) ----
kt_test_start "typed accessors inherit StripQuotes (TIniFile auto-strips)"
TIniFile.new I "$D/i.ini"
I.WriteString s qi '"7"'
I.WriteString s qf '"1.5"'
I.ReadInteger s qi 0; a=$RESULT
I.ReadFloat s qf 0;   b=$RESULT
[[ "$a" == "7" && "$b" == "1.5" ]] && kt_test_pass "quotes stripped before parse" || kt_test_fail "a=$a b=$b"
I.dirty = "false"; I.delete

# ---- zero-fork ----
kt_test_start "PATH='' : typed read/write fork-free"
zf="$(
    PATH=''
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    TMemIniFile.new Z "$D/z.ini"
    Z.WriteInteger n k '0x10'
    Z.ReadInteger n k 0 >/dev/null; a="$RESULT"
    Z.WriteBool n b true
    Z.ReadBool n b 0 >/dev/null; bb="$RESULT"
    Z.WriteFloat n f 2.5
    Z.ReadFloat n f 0 >/dev/null; c="$RESULT"
    Z.dirty = "false"; Z.delete
    printf '%s|%s|%s' "$a" "$bb" "$c"
)"
[[ "$zf" == "16|1|2.5" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

M.dirty = "false"; M.delete
kt_test_log "004_TypedAccessors.sh completed"
