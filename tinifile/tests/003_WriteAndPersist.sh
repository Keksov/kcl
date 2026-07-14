#!/bin/bash
# 003_WriteAndPersist.sh - tinifile P2: the write core + the persistence split.
# Pins: eager TIniFile (every Write flushes) vs cached TMemIniFile (dirty until
# UpdateFile / DESTROY-flush per FPC :1024); WriteString first-match update in
# place with ORIGINAL ident case; UpdateFile compose rules (comments verbatim,
# blank line between sections not after comment-sections, the '=value' invalid
# row quirk :1372) + idempotence; DeleteKey/EraseSection S7 silent-miss;
# S9 ForceDirectories; unwritable -> rc1 memory kept; PLAN 2.7 validation;
# GetStrings/SetStrings closure (+ the blank-after-every divergence);
# Rename S11; UTF-8 write->read round-trip; zero-fork in-memory paths.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: TIniFile write core + persistence (P2)"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

kt_test_start "eager TIniFile: WriteString hits the disk immediately"
TIniFile.new E "$D/e.ini"
E.WriteString app name kkbot
ok1=$([[ "$(cat "$D/e.ini")" == $'[app]\nname=kkbot' ]] && echo y)
E.WriteString app ver 2
ok2=$([[ "$(cat "$D/e.ini")" == $'[app]\nname=kkbot\nver=2' ]] && echo y)
[[ "$ok1$ok2" == "yy" ]] && kt_test_pass "both writes flushed" || kt_test_fail "$ok1/$ok2: $(cat "$D/e.ini")"
E.delete

kt_test_start "cached TMemIniFile: dirty until UpdateFile; then clean"
TMemIniFile.new M "$D/m.ini"
M.WriteString s k v
a=$([[ ! -f "$D/m.ini" ]] && echo nofile)
b="$(M.dirty)"
M.UpdateFile
c="$(cat "$D/m.ini")"; d2="$(M.dirty)"
[[ "$a" == "nofile" && "$b" == "true" && "$c" == $'[s]\nk=v' && "$d2" == "false" ]] \
    && kt_test_pass "cached split proven" || kt_test_fail "a=$a b=$b c=$c d=$d2"
M.delete

kt_test_start "FPC :1024 destroy-flush: dirty+cached saves; clean does not"
TMemIniFile.new DF "$D/df.ini"; DF.WriteString a b c; DF.delete
x=$([[ "$(cat "$D/df.ini" 2>/dev/null)" == $'[a]\nb=c' ]] && echo saved)
TMemIniFile.new ND "$D/nd.ini"; ND.delete
y=$([[ ! -f "$D/nd.ini" ]] && echo nofile)
[[ "$x$y" == "savednofile" ]] && kt_test_pass "flush-on-dirty only" || kt_test_fail "$x/$y"

kt_test_start "update-in-place: FIRST match, position + ORIGINAL ident case kept"
TMemIniFile.new U "$D/u.ini"
U.WriteString sec keyOne 1; U.WriteString sec keyTwo 2
U.WriteString SEC KEYONE updated
G=(); U.GetStrings G
[[ "${G[0]}" == "[sec]" && "${G[1]}" == "keyOne=updated" && "${G[2]}" == "keyTwo=2" ]] \
    && kt_test_pass "keyOne kept its case+slot" || kt_test_fail "[${G[0]}][${G[1]}][${G[2]}]"
U.dirty = "false"; U.delete

kt_test_start "UpdateFile compose: comments verbatim, blank rule, '=value' quirk; idempotent"
{ echo "; top"; echo "[a]"; echo "; inside"; echo "k=1"; echo "bare"; echo "[b]"; echo "x=y"; } > "$D/r.ini"
TMemIniFile.new R "$D/r.ini"
R.UpdateFile
first="$(cat "$D/r.ini")"
want=$'; top\n[a]\n; inside\nk=1\n=bare\n\n[b]\nx=y'
R.UpdateFile
second="$(cat "$D/r.ini")"
R.ReadString a k DEF; post="$RESULT"
if [[ "$first" == "$want" && "$second" == "$first" && "$post" == "1" ]]; then
    kt_test_pass "compose exact + idempotent + memory intact"
else
    kt_test_fail "first-ok=$([[ "$first" == "$want" ]] && echo y) idem=$([[ "$second" == "$first" ]] && echo y) post=$post"
fi
R.delete

kt_test_start "S7: DeleteKey/EraseSection silent on miss; erase kills comments too"
TIniFile.new DK "$D/dk.ini"
DK.WriteString s a 1; DK.WriteString s b 2
DK.DeleteKey s nope; r1=$?
DK.DeleteKey s a
DK.ReadString s b DEF; keep="$RESULT"
DK.EraseSection ghost; r2=$?
DK.EraseSection s
DK.SectionExists s; gone=$?
[[ $r1 -eq 0 && "$keep" == "2" && $r2 -eq 0 && $gone -eq 1 && "$(cat "$D/dk.ini")" == "" ]] \
    && kt_test_pass "silent misses; erase flushed empty file" \
    || kt_test_fail "r1=$r1 keep=$keep r2=$r2 gone=$gone file='$(cat "$D/dk.ini")'"
DK.delete

kt_test_start "GetStrings: blank line after EVERY section (pinned divergence)"
TMemIniFile.new SRC "$D/src.ini"
SRC.WriteString one k1 v1; SRC.WriteString two k2 v2
L=(); SRC.GetStrings L
[[ "${L[0]}" == "[one]" && "${L[1]}" == "k1=v1" && "${L[2]}" == "" && "${L[3]}" == "[two]" ]] \
    && kt_test_pass "blank after [one]" || kt_test_fail "[${L[0]}][${L[1]}][${L[2]}][${L[3]}]"

kt_test_start "SetStrings closure into a fresh instance; dirty untouched"
TMemIniFile.new DST "$D/dst.ini"
DST.SetStrings L
DST.ReadString two k2 DEF; v="$RESULT"
[[ "$v" == "v2" && "$(DST.dirty)" == "false" ]] && kt_test_pass "closure + clean" \
    || kt_test_fail "v=$v dirty=$(DST.dirty)"
SRC.dirty = "false"; SRC.delete; DST.delete

kt_test_start "TMemIniFile.Clear: content gone, dirty untouched"
TMemIniFile.new CL "$D/cl.ini"
CL.WriteString s k v
CL.Clear
CL.SectionExists s; gone=$?
[[ $gone -eq 1 && "$(CL.dirty)" == "true" ]] && kt_test_pass "cleared; dirty still true" \
    || kt_test_fail "gone=$gone dirty=$(CL.dirty)"
CL.dirty = "false"; CL.delete

kt_test_start "S11 Rename: false keeps memory for new target; true reloads"
TMemIniFile.new RN "$D/rn1.ini"
RN.WriteString s k old
RN.Rename "$D/rn2.ini" false
RN.UpdateFile
a=$([[ "$(cat "$D/rn2.ini")" == $'[s]\nk=old' ]] && echo y)
printf '[s]\nk=fresh\n' > "$D/rn3.ini"
RN.Rename "$D/rn3.ini" true
RN.ReadString s k DEF; b="$RESULT"
[[ "$a" == "y" && "$b" == "fresh" ]] && kt_test_pass "both modes" || kt_test_fail "a=$a b=$b"
RN.dirty = "false"; RN.delete

kt_test_start "S9: UpdateFile creates missing directories"
TMemIniFile.new MD "$D/new/sub/deep.ini"
MD.WriteString a b c
MD.UpdateFile; rc=$?
[[ $rc -eq 0 && -f "$D/new/sub/deep.ini" ]] && kt_test_pass "path created" || kt_test_fail "rc=$rc"
MD.delete

kt_test_start "unwritable target: rc 1, memory kept, dirty stays"
touch "$D/blockfile"
TMemIniFile.new UW "$D/blockfile/x.ini"
UW.WriteString s k v
UW.UpdateFile 2>/dev/null; rc=$?
UW.ReadString s k DEF; mem="$RESULT"
[[ $rc -eq 1 && "$mem" == "v" && "$(UW.dirty)" == "true" ]] \
    && kt_test_pass "refused; state intact" || kt_test_fail "rc=$rc mem=$mem dirty=$(UW.dirty)"
UW.dirty = "false"; UW.delete

kt_test_start "PLAN 2.7 validation: rc 1, nothing stored, no dirty"
TMemIniFile.new V "$D/v.ini"
V.WriteString "" id v 2>/dev/null;        r1=$?
V.WriteString ";sec" id v 2>/dev/null;    r2=$?
V.WriteString sec "a=b" v 2>/dev/null;    r3=$?
V.WriteString sec id $'a\nb' 2>/dev/null; r4=$?
[[ "$r1$r2$r3$r4" == "1111" && "$(V.dirty)" == "false" ]] \
    && kt_test_pass "all rejected, clean" || kt_test_fail "$r1$r2$r3$r4 dirty=$(V.dirty)"
V.delete

kt_test_start "UTF-8 write->read round-trip through a real file"
TMemIniFile.new UT "$D/ut.ini"
UT.WriteString "Café" "naïve" "Привет мир é"
UT.UpdateFile
UT.delete
TMemIniFile.new UT2 "$D/ut.ini"
UT2.ReadString "Café" "naïve" DEF
[[ "$RESULT" == "Привет мир é" ]] && kt_test_pass "byte-lossless through disk" || kt_test_fail "got '$RESULT'"
UT2.delete

kt_test_start "PATH='' : in-memory write paths fork-free (cached, no flush)"
zf="$(
    PATH=''
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    TMemIniFile.new Z "$D/z.ini"
    Z.WriteString s k v
    Z.WriteString s k2 w
    Z.DeleteKey s k
    Z.ReadString s k2 X >/dev/null; a="$RESULT"
    Z.ReadString s k GONE >/dev/null; b="$RESULT"
    Z.dirty = "false"
    Z.delete
    printf '%s|%s' "$a" "$b"
)"
[[ "$zf" == "w|GONE" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "003_WriteAndPersist.sh completed"
