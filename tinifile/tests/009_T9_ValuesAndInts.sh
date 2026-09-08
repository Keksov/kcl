#!/bin/bash
# 009_T9_ValuesAndInts.sh - review 2026-09-06, phase P8.
#
#   T9  ifoEscapeLineFeeds: FPC RemoveBackslashes (inifiles.pp:1022-1044) walks
#       `For I:=AStrings.Count-2 downto 0`, so the LAST line is never a join
#       source and a trailing `\` on it survives verbatim. The port stripped it.
#   T10 with ifoEscapeLineFeeds set, a value ending in `\` (every Windows
#       directory path does) makes the reader swallow the NEXT key on the way
#       back in. R6: refuse on write what the reader would reinterpret.
#   T11 ReadInteger is FPC StrToIntDef -> val() -> InitVal
#       (rtl/inc/sstrings.inc:1086-1137): leading spaces and TABs are skipped,
#       a bare `x`/`X` is a hex prefix just like `$` and `0x`, leading zeros are
#       stripped, and an out-of-range literal is an ERROR (Code<>0), which
#       StrToIntDef turns into the Default - it does not wrap.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "009_T9_ValuesAndInts" "$SCRIPT_DIR" "$@"

kt_test_section "009: escape-line-feeds + StrToIntDef grammar (T9, T10, T11)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- T9: the trailing backslash of the LAST line ------------------------------
kt_test_start "T9: a trailing '\\' on the last line is KEPT (FPC never joins it)"
printf '%s\n' '[s]' 'k=a\' > "$D/e1.ini"
TIniFile.new E1 "$D/e1.ini" ifoEscapeLineFeeds
E1.ReadString s k DEF
[[ "$RESULT" == 'a\' ]] && kt_test_pass 'a\' || kt_test_fail "got '$RESULT'"
E1.delete

kt_test_start "T9: same with NO final newline"
printf '%s\n%s' '[s]' 'k=a\' > "$D/e2.ini"
TIniFile.new E2 "$D/e2.ini" ifoEscapeLineFeeds
E2.ReadString s k DEF
[[ "$RESULT" == 'a\' ]] && kt_test_pass 'a\' || kt_test_fail "got '$RESULT'"
E2.delete

kt_test_start "T9: a DOUBLE backslash on the last line keeps both characters"
printf '%s\n' '[s]' 'k=a\\' > "$D/e3.ini"
TIniFile.new E3 "$D/e3.ini" ifoEscapeLineFeeds
E3.ReadString s k DEF
[[ "$RESULT" == 'a\\' ]] && kt_test_pass 'a\\' || kt_test_fail "got '$RESULT'"
E3.delete

kt_test_start "T9: a bare '\\' as the last line stays an invalid row, not an empty one"
printf '%s\n' '[s]' 'k=1' '\' > "$D/e4.ini"
TIniFile.new E4 "$D/e4.ini" ifoEscapeLineFeeds
R=(); E4.ReadSectionRaw s R
[[ ${#R[@]} -eq 2 && "${R[1]}" == '\' ]] && kt_test_pass "rows: ${#R[@]}, last '${R[1]}'" \
    || kt_test_fail "rows=${#R[@]} [${R[*]}]"
E4.delete

kt_test_start "T9: a MIDDLE '\\' still joins, and the joined chain still ends open"
printf '%s\n' '[s]' 'k=a\' 'b\' 'c' 'n=1' > "$D/e5.ini"
TIniFile.new E5 "$D/e5.ini" ifoEscapeLineFeeds
E5.ReadString s k DEF; a="$RESULT"
E5.ReadString s n DEF; b="$RESULT"
E5.delete
printf '%s\n' '[s]' 'k=a\' 'b\' > "$D/e6.ini"
TIniFile.new E6 "$D/e6.ini" ifoEscapeLineFeeds
E6.ReadString s k DEF; c="$RESULT"
E6.delete
if [[ "$a" == "abc" && "$b" == "1" && "$c" == 'ab\' ]]; then
    kt_test_pass "join ok; open chain keeps the final backslash"
else
    kt_test_fail "a='$a' b='$b' c='$c'"
fi

kt_test_start "T9: an empty line after a '\\' line joins to nothing (FPC delete-next)"
printf '%s\n' '[s]' 'k=a\' '' 'n=1' > "$D/e7.ini"
TIniFile.new E7 "$D/e7.ini" ifoEscapeLineFeeds
E7.ReadString s k DEF; a="$RESULT"
E7.ReadString s n DEF; b="$RESULT"
[[ "$a" == "a" && "$b" == "1" ]] && kt_test_pass "k='a' n='1'" || kt_test_fail "a='$a' b='$b'"
E7.delete

# --- T10: writing a value that ends in a backslash ----------------------------
kt_test_start "T10: with ifoEscapeLineFeeds a value ending in '\\' is refused"
TMemIniFile.new W "$D/w.ini" ifoEscapeLineFeeds
W.WriteString p dir 'C:\App\' 2>/dev/null; rc=$?
W.WriteString p name x
W.UpdateFile
W.ReadString p dir MISSING; a="$RESULT"
W.ReadString p name MISSING; b="$RESULT"
if [[ $rc -eq 1 && "$a" == "MISSING" && "$b" == "x" ]]; then
    kt_test_pass "rejected; the following key is intact"
else
    kt_test_fail "rc=$rc dir='$a' name='$b'"
fi
W.delete

kt_test_start "T10: an interior backslash is fine, only the LAST character matters"
TMemIniFile.new W2 "$D/w2.ini" ifoEscapeLineFeeds
W2.WriteString p dir 'C:\App\bin'; rc=$?
W2.WriteString p name x
W2.UpdateFile
W2.ReadString p dir MISSING; a="$RESULT"
W2.ReadString p name MISSING; b="$RESULT"
if [[ $rc -eq 0 && "$a" == 'C:\App\bin' && "$b" == "x" ]]; then
    kt_test_pass "stored and read back verbatim"
else
    kt_test_fail "rc=$rc dir='$a' name='$b'"
fi
W2.delete

kt_test_start "T10: WITHOUT the option the same value is accepted and round-trips"
TMemIniFile.new W3 "$D/w3.ini"
W3.WriteString p dir 'C:\App\'; rc=$?
W3.WriteString p name x
W3.UpdateFile
W3.ReadString p dir MISSING; a="$RESULT"
W3.ReadString p name MISSING; b="$RESULT"
if [[ $rc -eq 0 && "$a" == 'C:\App\' && "$b" == "x" ]]; then
    kt_test_pass "no join without the option"
else
    kt_test_fail "rc=$rc dir='$a' name='$b'"
fi
W3.delete

kt_test_start "T10: the guard covers WriteFloat/WriteInteger's shared write path only"
# A section name or ident ending in '\' is NOT at end of line after compose, so
# it stays legal - the rule is about the VALUE, and only under the option.
TMemIniFile.new W4 "$D/w4.ini" ifoEscapeLineFeeds
W4.WriteString 'sec\' 'id\' v; rc=$?
W4.UpdateFile
W4.ReadString 'sec\' 'id\' MISSING; a="$RESULT"
[[ $rc -eq 0 && "$a" == "v" ]] && kt_test_pass "names with a trailing backslash are legal" \
    || kt_test_fail "rc=$rc value='$a'"
W4.delete

# --- T11: the FPC val() grammar -----------------------------------------------
# One instance, one table: value written verbatim, ReadInteger with default -999
# (so that a genuine -1 answer stays distinguishable from the Default).
TMemIniFile.new I "$D/i.ini"
int_case() {  # LABEL RAW EXPECTED
    kt_test_start "T11: $1"
    I.WriteString n key "$2"
    I.ReadInteger n key -999
    if [[ "$RESULT" == "$3" ]]; then
        kt_test_pass "'$2' -> $3"
    else
        kt_test_fail "'$2' -> $RESULT, want $3"
    fi
}

int_case "leading blank skipped (InitVal ' ')"        ' 5'            5
int_case "leading TAB skipped (InitVal #9)"           $'\t7'          7
int_case "blanks then sign"                           '  -12'         -12
int_case "bare 'x' is a hex prefix"                   'x1F'           31
int_case "bare 'X' is a hex prefix"                   'X1f'           31
int_case "sign before the 'x' prefix"                 '-x10'          -16
int_case "\$ hex still works"                         '$FF'           255
int_case "0x hex still works"                         '0x1A'          26
int_case "& octal still works"                        '&17'           15
int_case "% binary still works"                       '%1010'         10
int_case "leading zeros stripped, base 10 kept"       '0123'          123
int_case "leading zeros inside a hex literal"         '$00FF'         255
int_case "trailing blank is an ERROR -> Default"      "5 "            -999
int_case "'12x' is an error -> Default"               '12x'           -999
int_case "bare 'x' alone -> Default"                  'x'             -999
int_case "bare '\$' alone -> Default"                 '$'             -999
int_case "'0x' alone -> Default"                      '0x'            -999
int_case "empty value -> Default"                     ''              -999
int_case "'&8' is not octal -> Default"               '&8'            -999
int_case "'%2' is not binary -> Default"              '%2'            -999
int_case "int64 max is exact"                         '9223372036854775807'  9223372036854775807
int_case "int64 max + 1 overflows -> Default"         '9223372036854775808'  -999
int_case "int64 min is exact"                         '-9223372036854775808' -9223372036854775808
int_case "int64 min - 1 overflows -> Default"         '-9223372036854775809' -999
int_case "20 decimal digits overflow -> Default"      '99999999999999999999' -999
int_case "16 hex digits fit ValUInt, sign-extended"   '$FFFFFFFFFFFFFFFF'    -1
int_case "17 hex digits overflow -> Default"          '$10000000000000000'   -999
int_case "20 hex digits overflow -> Default"          '$FFFFFFFFFFFFFFFFFFFF' -999
int_case "leading zeros do NOT count toward overflow" '000000000000000000000042' 42
int_case "64 binary digits fit (ValUInt max)"          "%$(printf '1%.0s' {1..64})" -1
int_case "65 binary digits overflow -> Default"       "%$(printf '1%.0s' {1..65})" -999
int_case "octal at the ValUInt ceiling"               '&1777777777777777777777' -1
int_case "octal past the ceiling -> Default"          '&2000000000000000000000' -999

kt_test_start "T11: ReadInt64 follows exactly the same grammar"
I.WriteString n k64 ' x20'
I.ReadInt64 n k64 -1; a="$RESULT"
I.WriteString n k65 '99999999999999999999'
I.ReadInt64 n k65 -1; b="$RESULT"
[[ "$a" == "32" && "$b" == "-1" ]] && kt_test_pass "32 / Default" || kt_test_fail "a=$a b=$b"

kt_test_start "T11: WriteInteger canonicalises the new forms and refuses overflow"
I.WriteInteger n c1 ' x1F'; r1=$?
I.ReadString n c1 RAW; v1="$RESULT"
I.WriteInteger n c2 '99999999999999999999' 2>/dev/null; r2=$?
I.ReadString n c2 ABSENT; v2="$RESULT"
if [[ $r1 -eq 0 && "$v1" == "31" && $r2 -eq 1 && "$v2" == "ABSENT" ]]; then
    kt_test_pass "' x1F' -> 31 stored; overflow rejected, nothing stored"
else
    kt_test_fail "r1=$r1 v1='$v1' r2=$r2 v2='$v2'"
fi

kt_test_start "T11: quoted numbers keep working through StripQuotes"
I.delete
TIniFile.new Q "$D/q.ini"
Q.WriteString n a '" 5"'
Q.WriteString n b '"x1F"'
Q.ReadInteger n a 0; x="$RESULT"
Q.ReadInteger n b 0; y="$RESULT"
[[ "$x" == "5" && "$y" == "31" ]] && kt_test_pass "5 / 31" || kt_test_fail "x=$x y=$y"
Q.delete

kt_test_log "009_T9_ValuesAndInts.sh completed"
