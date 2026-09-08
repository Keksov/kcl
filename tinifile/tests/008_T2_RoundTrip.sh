#!/bin/bash
# 008_T2_RoundTrip.sh - review 2026-09-06, phase P8: the two round-trip
# corruptions and the SectionExists divergence.
#
#   T2  a key whose ident starts with `[` and whose value ends with `]`
#       composes to a line that the reader takes for a SECTION header
#       (inifiles.pp:1069 `(sLine[1]=Brackets[0]) and (sLine[sLen]=Brackets[1])`),
#       so the key disappears and the following keys migrate into the bogus
#       section. FPC has the same hole; R6 (hybrid validation) says the WRITE
#       side refuses what the FPC reader would reinterpret.
#   T3  a `[;name]` line loads - FPC-verbatim - as a section literally named
#       `;name` (:1072 Copy(sLine,2,sLen-2)), and UpdateFile then emits it
#       through the IsComment branch (:1345) WITHOUT brackets, so the next read
#       turns it into a comment and orphans every key that followed it. The
#       loader stays verbatim; the composer keeps the brackets.
#   T4  SectionExists in FPC is `Assigned(S) and not S.Empty` (:670-676), and
#       Empty (:483-497) is "every key row is a comment" - so an empty or
#       comment-only section does NOT exist, while a section holding only an
#       INVALID row does (IsComment('') is False).
#
# Also pinned here, because both belong to the same reader/composer pair:
# a leading comment adopts the keys that follow it (FPC :1059-1066 assigns
# oSection), and EraseSection removes only the FIRST of two same-named
# sections (FPC first-match parity).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "008_T2_RoundTrip" "$SCRIPT_DIR" "$@"

kt_test_section "008: round-trip corruptions + SectionExists (T2, T3, T4)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- T2: `[`-ident + `]`-value ----------------------------------------------
kt_test_start "T2: WriteString '[list' -> '1,2]' is refused (rc 1, nothing stored)"
TMemIniFile.new F "$D/f.ini"
F.WriteString s other 9
F.WriteString s "[list" "1,2]" 2>/dev/null; rc=$?
K=(); F.ReadSection s K
n=${#K[@]}
if [[ $rc -eq 1 && $n -eq 1 && "${K[0]}" == "other" ]]; then
    kt_test_pass "rejected, section untouched"
else
    kt_test_fail "rc=$rc idents=$n [${K[*]}]"
fi

kt_test_start "T2: the same pair survives a flush when it CANNOT read back as a section"
# `[list=1,2` does not end in `]`, so the reader keeps it as a key: allowed.
F.WriteString s "[list" "1,2"; rc=$?
F.UpdateFile
F.ReadString s "[list" DEF; v="$RESULT"
if [[ $rc -eq 0 && "$v" == "1,2" ]]; then
    kt_test_pass "accepted and round-tripped verbatim"
else
    kt_test_fail "rc=$rc value='$v'"
fi

kt_test_start "T2: no bogus section was ever created"
S=(); F.ReadSections S
joined=""; for x in "${S[@]}"; do joined+="[$x]"; done
[[ "$joined" == "[s]" ]] && kt_test_pass "sections: $joined" || kt_test_fail "sections: $joined"
F.dirty = "false"; F.delete

kt_test_start "T2: an ident ending in ']' with a ']'-value is still fine"
TMemIniFile.new F2 "$D/f2.ini"
F2.WriteString s "x]" "y]"; a=$?
F2.WriteString s "[x]" ""; b=$?
F2.UpdateFile
F2.ReadString s "x]" DEF; v1="$RESULT"
F2.ReadString s "[x]" DEF; v2="$RESULT"
if [[ $a -eq 0 && $b -eq 0 && "$v1" == "y]" && "$v2" == "" ]]; then
    kt_test_pass "both keys survive the flush"
else
    kt_test_fail "a=$a b=$b v1='$v1' v2='$v2'"
fi
F2.delete

# --- T3: [;name] --------------------------------------------------------------
kt_test_start "T3: a '[;x]' section keeps its keys across UpdateFile"
printf '[;x]\nk=v\n[y]\nz=1\n' > "$D/c.ini"
TMemIniFile.new C "$D/c.ini"
C.UpdateFile
body="$(cat "$D/c.ini")"
want=$'[;x]\nk=v\n[y]\nz=1'
if [[ "$body" == "$want" ]]; then
    kt_test_pass "brackets kept, keys kept"
else
    kt_test_fail "got '${body//$'\n'/\\n}' want '${want//$'\n'/\\n}'"
fi

kt_test_start "T3: the flush is idempotent and the reopened file is identical"
C.UpdateFile
second="$(cat "$D/c.ini")"
C.delete
TMemIniFile.new C2 "$D/c.ini"
C2.UpdateFile
third="$(cat "$D/c.ini")"
C2.ReadString y z DEF; z="$RESULT"
S2=(); C2.ReadSections S2
j=""; for x in "${S2[@]}"; do j+="[$x]"; done
if [[ "$second" == "$body" && "$third" == "$body" && "$z" == "1" && "$j" == "[y]" ]]; then
    kt_test_pass "stable across two instances; ';x' stays unlisted (FPC)"
else
    kt_test_fail "second=$([[ "$second" == "$body" ]] && echo ok || echo drift) third=$([[ "$third" == "$body" ]] && echo ok || echo drift) z='$z' sections=$j"
fi

kt_test_start "T3: '[;x]' is NOT addressable, exactly as in FPC SectionByName"
C2.SectionExists ";x"; a=$?
C2.ReadString ";x" k DEF; b="$RESULT"
[[ $a -eq 1 && "$b" == "DEF" ]] && kt_test_pass "unaddressable, as FPC" || kt_test_fail "exists=$a read='$b'"
C2.delete

kt_test_start "a real comment-section still composes WITHOUT brackets"
printf '; top\n[y]\nz=1\n' > "$D/cm.ini"
TMemIniFile.new CM "$D/cm.ini"
CM.UpdateFile
body="$(cat "$D/cm.ini")"
[[ "$body" == $'; top\n[y]\nz=1' ]] && kt_test_pass "comment verbatim" \
    || kt_test_fail "got '${body//$'\n'/\\n}'"
CM.delete

kt_test_start "FPC :1059-1066: a leading comment ADOPTS the keys that follow it"
printf '; top\norphan=1\n[y]\nz=2\n' > "$D/ad.ini"
TMemIniFile.new AD "$D/ad.ini"
AD.UpdateFile
body="$(cat "$D/ad.ini")"
AD.UpdateFile
again="$(cat "$D/ad.ini")"
if [[ "$body" == $'; top\norphan=1\n[y]\nz=2' && "$again" == "$body" ]]; then
    kt_test_pass "orphan key kept by the comment-section, stable"
else
    kt_test_fail "got '${body//$'\n'/\\n}' second '${again//$'\n'/\\n}'"
fi
AD.delete

kt_test_start "ifoStripComments: no comment-section, so the key IS dropped (FPC)"
TMemIniFile.new AS "$D/ad.ini" ifoStripComments
AS.UpdateFile
body="$(cat "$D/ad.ini")"
[[ "$body" == $'[y]\nz=2' ]] && kt_test_pass "comment and its key gone" \
    || kt_test_fail "got '${body//$'\n'/\\n}'"
AS.delete

# --- T4: SectionExists = FPC ---------------------------------------------------
kt_test_start "T4: empty and comment-only sections do NOT exist; a full one does"
printf '[empty]\n[c]\n; only a comment\n[inv]\nbareline\n[full]\nk=1\n' > "$D/s.ini"
TMemIniFile.new S "$D/s.ini"
S.SectionExists empty; a=$?
S.SectionExists c;     b=$?
S.SectionExists inv;   c=$?
S.SectionExists full;  d=$?
S.SectionExists nosuch; e=$?
if [[ $a -eq 1 && $b -eq 1 && $c -eq 0 && $d -eq 0 && $e -eq 1 ]]; then
    kt_test_pass "empty=no comment-only=no invalid-row=YES full=yes absent=no"
else
    kt_test_fail "empty=$a comment=$b invalid=$c full=$d absent=$e"
fi

kt_test_start "T4: RESULT mirrors the rc (1/0) on every branch"
S.SectionExists empty >/dev/null; r1="$RESULT"
S.SectionExists full >/dev/null;  r2="$RESULT"
[[ "$r1" == "0" && "$r2" == "1" ]] && kt_test_pass "RESULT 0/1" || kt_test_fail "r1='$r1' r2='$r2'"

kt_test_start "T4: the sections are still LISTED and readable, only 'exists' is false"
SS=(); S.ReadSections SS
j=""; for x in "${SS[@]}"; do j+="[$x]"; done
S.ValueExists full k; ve=$?
[[ "$j" == "[empty][c][inv][full]" && $ve -eq 0 ]] \
    && kt_test_pass "ReadSections unaffected: $j" || kt_test_fail "sections=$j valueExists=$ve"
S.delete

kt_test_start "T4: WriteString then DeleteKey leaves a section that does NOT exist"
TMemIniFile.new N "$D/n.ini"
N.SectionExists n; before=$?
N.WriteString n k v
N.SectionExists n; mid=$?
N.DeleteKey n k
N.SectionExists n; after=$?
NS=(); N.ReadSections NS
if [[ $before -eq 1 && $mid -eq 0 && $after -eq 1 && ${#NS[@]} -eq 1 && "${NS[0]}" == "n" ]]; then
    kt_test_pass "absent -> exists -> empty-so-not-exists, still listed"
else
    kt_test_fail "before=$before mid=$mid after=$after listed=${#NS[@]} [${NS[*]}]"
fi
N.dirty = "false"; N.delete

kt_test_start "T4: a section whose only key is a comment does not exist, ValueExists agrees"
printf '[co]\n; c\n' > "$D/co.ini"
TMemIniFile.new CO "$D/co.ini"
CO.SectionExists co; a=$?
CO.ValueExists co "; c"; b=$?
[[ $a -eq 1 && $b -eq 1 ]] && kt_test_pass "comment key is not a key (FPC KeyByName guard)" \
    || kt_test_fail "exists=$a valueExists=$b"
CO.delete

kt_test_start "duplicate sections: EraseSection removes the FIRST only (FPC parity)"
printf '[a]\nk=1\n[a]\nk=2\n' > "$D/dup.ini"
TMemIniFile.new DU "$D/dup.ini"
DU.EraseSection a; rc=$?
DU.SectionExists a; still=$?
DU.ReadString a k DEF; v="$RESULT"
if [[ $rc -eq 0 && $still -eq 0 && "$v" == "2" ]]; then
    kt_test_pass "second copy survives and is now first-match"
else
    kt_test_fail "rc=$rc exists=$still value='$v'"
fi
DU.dirty = "false"; DU.delete

kt_test_log "008_T2_RoundTrip.sh completed"
