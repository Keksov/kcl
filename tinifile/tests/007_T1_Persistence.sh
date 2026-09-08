#!/bin/bash
# 007_T1_Persistence.sh - review 2026-09-06, phase P8: the persistence edges.
#
#   T1  UpdateFile onto a path that IS a directory must fail (rc 1), keep the
#       in-memory state and `dirty`, and leave no junk behind. FPC's UpdateFile
#       (inifiles.pp:1358-1375) calls slLines.SaveToFile LAST and only then
#       does FillSectionList + FDirty:=false, so a failing save raises and
#       leaves both the memory and the dirty flag untouched.
#   T5  the eager class flushes inside DeleteKey/EraseSection (FPC :1331/:1318
#       call MaybeUpdateFile); when that flush fails the caller must see it.
#       In FPC the SaveToFile exception propagates out of DeleteKey; here the
#       equivalent is the flush rc.
#   T7  `--` before every user path (a file named `-x.ini` is a file, not a
#       switch) and the temp file removed on EVERY failure branch, including
#       the printf branch that the P1 sweep did not touch.
#   T8  an existing read-only target is NOT replaced: FPC SaveToFile fails on
#       it, while `mv` over a 0444 file succeeds and silently resets the mode.
#   T12 a `\`-separated path gets the ForceDirectories treatment too.
#
# Every case also asserts that no `*.tmp.*` file survives anywhere under the
# fixture directory - that is the observable form of "the tmp is removed on
# every failure branch".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "007_T1_Persistence" "$SCRIPT_DIR" "$@"

kt_test_section "007: persistence edges (T1, T5, T7, T8, T12)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# Count leftover temp files under the fixture dir (the unit's tmp is
# "<file_name>.tmp.<pid>"). Fork-free enough: one glob, no external command.
tmp_leftovers() {
    local -a hits=()
    local f
    shopt -s nullglob dotglob globstar
    for f in "$D"/**/*.tmp.*; do hits+=( "$f" ); done
    shopt -u nullglob dotglob globstar
    printf '%s' "${#hits[@]}"
}

# --- T1: file_name is a directory -------------------------------------------
kt_test_start "T1: eager WriteString onto a DIRECTORY -> rc 1, memory kept, no junk"
mkdir -p "$D/adir"
TIniFile.new X "$D/adir"
X.WriteString a b c 2>/dev/null; rc=$?
X.ReadString a b MISSING; mem="$RESULT"
left="$(tmp_leftovers)"
inside=0
for f in "$D/adir"/*; do [[ -e "$f" ]] && inside=$(( inside + 1 )); done
if [[ $rc -eq 1 && "$mem" == "c" && "$left" == "0" && $inside -eq 0 ]]; then
    kt_test_pass "rc 1, memory kept, directory untouched"
else
    kt_test_fail "rc=$rc mem='$mem' tmp_left=$left files_in_dir=$inside"
fi
X.delete

kt_test_start "T1: cached UpdateFile onto a DIRECTORY -> rc 1, dirty STAYS true"
TMemIniFile.new XM "$D/adir"
XM.WriteString a b c
XM.UpdateFile 2>/dev/null; rc=$?
d="$(XM.dirty)"
XM.ReadString a b MISSING; mem="$RESULT"
left="$(tmp_leftovers)"
if [[ $rc -eq 1 && "$d" == "true" && "$mem" == "c" && "$left" == "0" ]]; then
    kt_test_pass "rc 1, dirty still true, memory kept"
else
    kt_test_fail "rc=$rc dirty=$d mem='$mem' tmp_left=$left"
fi
XM.dirty = "false"; XM.delete

# --- T7: a leading `-` in the file name is a NAME, not a switch --------------
kt_test_start "T7: relative file name '-x.ini' is written and read back"
mkdir -p "$D/dash"
(
    cd "$D/dash" || exit 9
    TIniFile.new Y "-x.ini"
    Y.WriteString a b c 2>/dev/null; rc=$?
    Y.delete
    printf '%s|' "$rc"
    if [[ -f "./-x.ini" ]]; then printf 'file|%s' "$(cat -- ./-x.ini)"; else printf 'nofile|'; fi
) > "$D/dash.out"
got="$(<"$D/dash.out")"
left="$(tmp_leftovers)"
if [[ "$got" == "0|file|[a]"$'\n'"b=c" && "$left" == "0" ]]; then
    kt_test_pass "'-x.ini' written verbatim, no tmp left"
else
    kt_test_fail "got '${got//$'\n'/\\n}' tmp_left=$left"
fi

# --- T7: the tmp file is removed when the WRITE fails ------------------------
# The redirection creates the tmp and only then does printf run, so a failing
# printf is the one branch that can leave a half-written temp file behind. A
# child shell shadows printf for exactly one call (a canary, as in P3) so the
# branch is reached without a full disk.
kt_test_start "T7: tmp removed when the printf into it fails"
out="$(
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    cd "$D" || exit 9
    mkdir -p pf
    TMemIniFile.new PF "$D/pf/x.ini"
    PF.WriteString s k v
    printf() { return 1; }
    PF.UpdateFile 2>/dev/null; rc=$?
    unset -f printf
    n=0; for f in "$D"/pf/*; do [[ -e "$f" ]] && n=$(( n + 1 )); done
    PF.dirty = "false"; PF.delete
    echo "rc=$rc leftover=$n"
)"
[[ "$out" == "rc=1 leftover=0" ]] && kt_test_pass "$out" || kt_test_fail "$out"

kt_test_start "T7: tmp removed when the mv over the target fails"
out="$(
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    cd "$D" || exit 9
    mkdir -p mv1
    TMemIniFile.new MV "$D/mv1/x.ini"
    MV.WriteString s k v
    mv() { return 1; }
    MV.UpdateFile 2>/dev/null; rc=$?
    unset -f mv
    n=0; for f in "$D"/mv1/*; do [[ -e "$f" ]] && n=$(( n + 1 )); done
    d="$(MV.dirty)"
    MV.dirty = "false"; MV.delete
    echo "rc=$rc leftover=$n dirty=$d"
)"
[[ "$out" == "rc=1 leftover=0 dirty=true" ]] && kt_test_pass "$out" || kt_test_fail "$out"

# --- T8: a read-only target is refused, its mode preserved -------------------
kt_test_start "T8: read-only target -> rc 1, content AND mode untouched"
printf '[s]\nk=1\n' > "$D/ro.ini"
chmod 444 "$D/ro.ini"
if [[ -w "$D/ro.ini" ]]; then
    kt_test_fail "fixture invalid: 0444 file is still writable on this filesystem"
else
    TIniFile.new RO "$D/ro.ini"
    RO.WriteString s k 2 2>/dev/null; rc=$?
    body="$(cat "$D/ro.ini")"
    mode_ro=$([[ -w "$D/ro.ini" ]] && echo writable || echo readonly)
    RO.ReadString s k DEF; mem="$RESULT"
    left="$(tmp_leftovers)"
    if [[ $rc -eq 1 && "$body" == $'[s]\nk=1' && "$mode_ro" == "readonly" \
          && "$mem" == "2" && "$left" == "0" ]]; then
        kt_test_pass "refused; file and mode intact; memory holds the new value"
    else
        kt_test_fail "rc=$rc body='${body//$'\n'/\\n}' mode=$mode_ro mem='$mem' tmp_left=$left"
    fi
    RO.delete
fi
chmod 644 "$D/ro.ini" 2>/dev/null

# --- T5: the eager flush rc reaches DeleteKey / EraseSection -----------------
kt_test_start "T5: DeleteKey and EraseSection return the failed eager flush rc"
touch "$D/blk"
TIniFile.new EG "$D/blk/x.ini"
EG.WriteString s k v 2>/dev/null;  w1=$?
EG.WriteString s k2 v2 2>/dev/null
EG.ReadString s k DEF; mem="$RESULT"
EG.DeleteKey s k 2>/dev/null;      d1=$?
EG.EraseSection s 2>/dev/null;     e1=$?
left="$(tmp_leftovers)"
if [[ $w1 -eq 1 && "$mem" == "v" && $d1 -eq 1 && $e1 -eq 1 && "$left" == "0" ]]; then
    kt_test_pass "WriteString/DeleteKey/EraseSection all rc 1"
else
    kt_test_fail "write=$w1 mem='$mem' delete=$d1 erase=$e1 tmp_left=$left"
fi
EG.delete

kt_test_start "T5: a MISS still returns rc 0 even when a flush would fail (FPC S7)"
TIniFile.new EG2 "$D/blk/y.ini"
EG2.DeleteKey nosuch nokey;  d2=$?
EG2.EraseSection nosuch;     e2=$?
if [[ $d2 -eq 0 && $e2 -eq 0 ]]; then
    kt_test_pass "silent miss, no flush attempted"
else
    kt_test_fail "delete=$d2 erase=$e2"
fi
EG2.delete

kt_test_start "T5: a successful eager DeleteKey/EraseSection still returns rc 0"
TIniFile.new OK1 "$D/ok.ini"
OK1.WriteString s a 1; OK1.WriteString s b 2
OK1.DeleteKey s a;   d3=$?
OK1.EraseSection s;  e3=$?
if [[ $d3 -eq 0 && $e3 -eq 0 && "$(cat "$D/ok.ini")" == "" ]]; then
    kt_test_pass "rc 0 on the happy path, file flushed"
else
    kt_test_fail "delete=$d3 erase=$e3 file='$(cat "$D/ok.ini")'"
fi
OK1.delete

# --- T12: a backslash path gets ForceDirectories + a clean write -------------
kt_test_start "T12: '\\'-separated path creates the directory, writes, no stderr"
errf="$D/t12.err"
TMemIniFile.new BS "$D\\newdir\\x.ini"
BS.WriteString a b c
BS.UpdateFile 2>"$errf"; rc=$?
err="$(<"$errf")"
d="$(BS.dirty)"
if [[ $rc -eq 0 && -d "$D/newdir" && -f "$D/newdir/x.ini" && -z "$err" \
      && "$(cat "$D/newdir/x.ini")" == $'[a]\nb=c' && "$d" == "false" ]]; then
    kt_test_pass "directory created, file written, silent"
else
    kt_test_fail "rc=$rc dir=$([[ -d "$D/newdir" ]] && echo y || echo n) file=$([[ -f "$D/newdir/x.ini" ]] && echo y || echo n) stderr='$err' dirty=$d"
fi
BS.dirty = "false"; BS.delete

kt_test_start "T12: a '\\'-path also LOADS back through the same normalisation"
TMemIniFile.new BS2 "$D\\newdir\\x.ini"
BS2.ReadString a b DEF
[[ "$RESULT" == "c" ]] && kt_test_pass "read back through the backslash name" \
    || kt_test_fail "got '$RESULT'"
BS2.delete

kt_test_start "T12: file_name keeps the caller's text verbatim"
TMemIniFile.new BS3 "$D\\newdir\\x.ini"
fn="$(BS3.file_name)"
[[ "$fn" == "$D\\newdir\\x.ini" ]] && kt_test_pass "not rewritten" || kt_test_fail "got '$fn'"
BS3.delete

# --- the whole fixture tree is clean -----------------------------------------
kt_test_start "no temp file survived any of the failure paths"
left="$(tmp_leftovers)"
[[ "$left" == "0" ]] && kt_test_pass "0 leftovers" || kt_test_fail "$left leftover tmp file(s)"

kt_test_log "007_T1_Persistence.sh completed"
