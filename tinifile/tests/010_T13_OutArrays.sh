#!/bin/bash
# 010_T13_OutArrays.sh - review 2026-09-06, phase P8, finding T13.
#
# The six members that fill (or read) a caller-named array - ReadSection,
# ReadSections, ReadSectionValues, ReadSectionRaw, TMemIniFile.GetStrings and
# TMemIniFile.SetStrings - bound the nameref without looking at the name first:
#   I.ReadSections ""              -> `local: `': not a valid identifier`, rc 0
#   dirty=(); I.ReadSections dirty -> the nameref resolved to the INSTANCE
#                                     variable that is in scope inside the body
# kcl/README.md 1.7: the name must be a plain identifier and must not be one of
# the framework's or the unit's reserved names; a bad name is a malformed CALL,
# so rc 2 (owner decision 2026-09-07, same as tqueuestack/thashset/tdictionary),
# nothing written, nothing printed.
#
# Each sweep runs in a CHILD shell: before the fix a name like `IFS` or `this`
# does not just misbehave, it corrupts the shell that made the call, and a
# corrupted runner cannot report anything. One child per member, not per name.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "010_T13_OutArrays" "$SCRIPT_DIR" "$@"

kt_test_section "010: output-array name validation (T13)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERR="$D/err.txt"

printf '[s]\nk=1\n; c\nbare\n[t]\nz=2\n' > "$D/a.ini"

# 21 names: malformed identifiers, the framework's reserved set, the unit's own
# internals, the four instance variables and the instance's storage arrays.
read -r -d '' PROBE <<'CHILD' || :
source "$1/tinifile.sh"
D="$2"; M="$3"
TMemIniFile.new I "$D/a.ini"
names=( "" "1bad" "a-b" "a b" "with.dot" "RESULT" "REPLY" "IFS" "this" "__inst__"
        "__class__" "__kk_x" "__tif_out" "file_name" "options" "cache_updates"
        "dirty" "I_secnames" "I_kident" "I_kvalue" "I_kowner" )
bad=""
for n in "${names[@]}"; do
    case "$M" in
        ReadSection)       I.ReadSection s "$n" ;;
        ReadSections)      I.ReadSections "$n" ;;
        ReadSectionValues) I.ReadSectionValues s "$n" ;;
        ReadSectionRaw)    I.ReadSectionRaw s "$n" ;;
        GetStrings)        I.GetStrings "$n" ;;
        SetStrings)        I.SetStrings "$n" ;;
    esac
    rc=$?
    if [[ $rc -ne 2 ]]; then bad="${bad}[${n:-<empty>} rc=$rc]"; fi
done
# the instance must still be intact after 21 refused calls
I.ReadString s k DEF; a="$RESULT"
I.ReadString t z DEF; b="$RESULT"
S=(); I.ReadSections S
if [[ "$a" != "1" || "$b" != "2" || ${#S[@]} -ne 2 ]]; then
    bad="${bad}[state k=$a z=$b sections=${#S[@]}]"
fi
printf '%s' "${bad:-OK}"
CHILD

for m in ReadSection ReadSections ReadSectionValues ReadSectionRaw GetStrings SetStrings; do
    kt_test_start "T13: $m refuses 21 malformed/reserved names with rc 2, silently"
    out="$(bash -c "$PROBE" _ "$TIF_DIR" "$D" "$m" 2>"$ERR")"
    err="$(<"$ERR")"
    if [[ "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "all refused, instance intact, stderr clean"
    else
        kt_test_fail "out='$out' stderr='${err//$'\n'/ | }'"
    fi
done

kt_test_start "T13: a caller array literally named 'dirty' is NOT touched"
out="$(bash -c '
source "$1/tinifile.sh"
TMemIniFile.new I "$2/a.ini"
dirty=( untouched )
I.ReadSections dirty; rc=$?
printf "rc=%s arr=[%s] n=%s inst=%s" "$rc" "${dirty[*]}" "${#dirty[@]}" "$(I.dirty)"
' _ "$TIF_DIR" "$D" 2>"$ERR")"
err="$(<"$ERR")"
if [[ "$out" == "rc=2 arr=[untouched] n=1 inst=false" && -z "$err" ]]; then
    kt_test_pass "refused; caller array and instance var both intact"
else
    kt_test_fail "out='$out' stderr='${err//$'\n'/ | }'"
fi

kt_test_start "T13: an ASSOCIATIVE target is refused (it would get 0,1,2 keys)"
out="$(bash -c '
source "$1/tinifile.sh"
TMemIniFile.new I "$2/a.ini"
declare -A assoc=()
I.ReadSections assoc; rc=$?
printf "rc=%s n=%s" "$rc" "${#assoc[@]}"
' _ "$TIF_DIR" "$D" 2>"$ERR")"
err="$(<"$ERR")"
[[ "$out" == "rc=2 n=0" && -z "$err" ]] && kt_test_pass "$out" \
    || kt_test_fail "out='$out' stderr='${err//$'\n'/ | }'"

# --- the good path is unchanged ---------------------------------------------
TMemIniFile.new I "$D/a.ini"

kt_test_start "T13: good names still fill all six members"
good=""
A1=(); I.ReadSection s A1        || good+="[ReadSection rc=$?] "
[[ ${#A1[@]} -eq 2 ]]            || good+="[ReadSection n=${#A1[@]}] "
A2=(); I.ReadSections A2         || good+="[ReadSections rc=$?] "
[[ ${#A2[@]} -eq 2 ]]            || good+="[ReadSections n=${#A2[@]}] "
A3=(); I.ReadSectionValues s A3  || good+="[ReadSectionValues rc=$?] "
[[ ${#A3[@]} -eq 2 ]]            || good+="[ReadSectionValues n=${#A3[@]}] "
A4=(); I.ReadSectionRaw s A4     || good+="[ReadSectionRaw rc=$?] "
[[ ${#A4[@]} -eq 3 ]]            || good+="[ReadSectionRaw n=${#A4[@]}] "
A5=(); I.GetStrings A5           || good+="[GetStrings rc=$?] "
[[ ${#A5[@]} -eq 7 ]]            || good+="[GetStrings n=${#A5[@]}] "
I.SetStrings A5                  || good+="[SetStrings rc=$?] "
I.ReadString t z DEF
[[ "$RESULT" == "2" ]]           || good+="[SetStrings value='$RESULT'] "
[[ -z "$good" ]] && kt_test_pass "all six fill correctly" || kt_test_fail "$good"

kt_test_start "T13: RESULT holds the count on success and is cleared on rc 2"
A6=(); I.ReadSection s A6; n="$RESULT"
I.ReadSection s "%%" 2>/dev/null; after="$RESULT"
[[ "$n" == "2" && -z "$after" ]] && kt_test_pass "count 2, then empty" \
    || kt_test_fail "count='$n' after-reject='$after'"
I.delete

kt_test_start "T13: the refusal is clean under set -eu"
out="$(bash -c "set -eu
source '$TIF_DIR/tinifile.sh'
TMemIniFile.new Z '$D/a.ini'
Z.ReadSections '%%' && printf 'NOFAIL' || printf 'rc=%s' \$?
Z.delete" 2>&1)"
[[ "$out" == "rc=2" ]] && kt_test_pass "$out" || kt_test_fail "got '$out'"

kt_test_log "010_T13_OutArrays.sh completed"
