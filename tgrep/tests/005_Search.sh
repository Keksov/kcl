#!/bin/bash
# 005_Search.sh — tgrep P2: TGrep against the real tool on a real tree
# (tutil/PLAN.md §2.4, §2.5, §2.6, §2.7, §4, §5 P2; pinned facts G5–G12).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same argv —
# never a second call into the code under test. The fixture tree is built under
# `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework tears it down;
# this file installs NO `trap … EXIT` of its own, which would replace ktests'
# trap and swallow the `__COUNTS__` line the runner parses (PLAN §4).
#
# THE GATE IS THE FIRST CASE. This machine carries a non-GNU `grep` (Embarcadero)
# on PATH after the msys ones, and D4 pins the GNU dialect, not a binary: if
# `grep --version` does not begin with `grep (GNU grep) `, every behavioural case
# below is a loud `SKIP`, so the suite stays honest instead of red.
#
# Sections:
#   Z        the GNU banner gate, and the fixture tree
#   A  G5    no match: every runner is rc 1 with `lastRc` 1 and says NOTHING
#   B  G6    the regex dialect: `extended = 1` + `(` is rc 1 / `lastRc` 2 / one
#            line; the same pattern with `extended` off is a LITERAL `(`
#   C  G7    `-Z` framing: `filesOnly` + `nullOut` derives `-0` and a name with a
#            space or a NEWLINE survives; `countOnly` + `nullOut` does NOT
#   D  G8    a directory operand without `recursive` is rc 1 / `lastRc` 2 / zero
#            records; `TGrep.search` implies `-r` and REFUSES zero paths
#   E  G9    the three forms deliver the same records in the same order
#   F  G10   one missing file among good ones: the records are KEPT, RESULT is
#            the real count, rc 1, `lastRc` 2 — the family's named deviation
#   G  G11   a nested `search` from inside an outer sink's callback
#   H  G12   `-r` does not descend a real directory symlink; one named on the
#            command line IS followed
#   I        CRLF: grep strips the CR in text mode, `binary = 1` (-U) shows it
#   J        every remaining typed option, each against the bare tool
#   K        binary files: `Binary file X matches` is a stdout RECORD, and
#            `addArg -a` turns it back into text
#
# Calls that make grep itself write to stderr (a missing operand, a directory
# without `-r`, a bad regex) get `2>/dev/null`; where the diagnostic count
# matters, `tg_dbg` separates OUR lines (`Error:`/`Warning:`) from the tool's
# (`grep: …`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tgrep.sh"
source "$UNIT"

# Real NTFS symlinks: plain `ln -s` runs in COPY mode on this box and produces a
# DIRECTORY COPY, which `-r` then descends for entirely the wrong reason (PLAN
# §4, critic finding 7). The tdirectory helper asks for `winsymlinks:native` and
# verifies with `[[ -L ]]`.
source "$UNIT_DIR/../tdirectory/tests/symlink_helper.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/tg.err"

kt_test_section "005: TGrep against GNU grep on a real tree (P2)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`grep\` on PATH is GNU grep (D4 pins the DIALECT, not a binary)"
GREP_BIN="$(command -v grep 2>/dev/null || printf '(none)')"
GREP_VER="$(grep --version 2>/dev/null | head -1 || :)"
if [[ "$GREP_VER" == "grep (GNU grep) "* ]]; then
    GNU_OK=1
    kt_test_pass "$GREP_BIN — $GREP_VER"
else
    kt_test_pass "SKIP: non-GNU grep ($GREP_BIN — '${GREP_VER:-no banner}'); every behavioural case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so a case body reads `if tcase "…"; then … fi` and the case COUNT is
# the same on a GNU box and on one without.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU grep"
        return 1
    fi
    return 0
}

# --- the tree --------------------------------------------------------------
FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
printf 'alpha needle here\nbeta\nneedle again\n'  > "$FX/plain.txt"
printf 'gamma\nneedle in spaced\n'                > "$FX/with space.txt"
printf 'needle dash\n'                            > "$FX/-dash.txt"
printf 'needle caf\xc3\xa9 \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\n' > "$FX/utf.txt"
printf 'needle crlf\r\nsecond\r\n'                > "$FX/crlf.txt"
printf 'nothing here at all\n'                    > "$FX/other.txt"
printf 'has ( paren\nNeedle capital\n'            > "$FX/paren.txt"
printf 'needle bin\n\000\001binary\n'             > "$FX/bin.dat"
printf 'aaa\000needle zzz\000'                    > "$FX/z.dat"
mkdir -p "$FX/sub" "$FX/realdir"
printf 'needle deep\n'                            > "$FX/sub/deep.txt"
printf 'needle logged\n'                          > "$FX/sub/note.log"
printf 'needle linked\n'                          > "$FX/realdir/linked.txt"

# A newline in a file name is creatable on this NTFS/msys box (PLAN §4) — it is
# the whole reason `-Z` exists. If the platform ever refuses it, the two cases
# that need it degrade to the space-in-the-name half.
NL_OK=0
NLNAME="$FX/nl"$'\n'"name.txt"
if printf 'needle nl\n' > "$NLNAME" 2>/dev/null && [[ -f "$NLNAME" ]]; then
    NL_OK=1
fi

SYM_OK=0
if kt_make_symlink "$FX/dirlink" "$FX/realdir" \
   && kt_make_symlink "$FX/filelink.txt" "$FX/plain.txt"; then
    SYM_OK=1
fi

kt_test_start "the fixture tree is in place"
need_ok=1
for f in plain.txt 'with space.txt' -dash.txt utf.txt crlf.txt other.txt \
         paren.txt bin.dat z.dat sub/deep.txt sub/note.log realdir/linked.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
if [[ "$need_ok" == "1" ]]; then
    kt_test_pass "12 files, sub/ and realdir/; newline-in-name: $NL_OK; real symlinks: $SYM_OK"
else
    kt_test_fail "a fixture file is missing under $FX"
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

arr_is() {
    local -n __a="$1"; shift
    local __i=0 __e
    if (( ${#__a[@]} != $# )); then
        return 1
    fi
    for __e in "$@"; do
        if [[ "${__a[$__i]}" != "$__e" ]]; then
            return 1
        fi
        __i=$(( __i + 1 ))
    done
    return 0
}

arr_eq() {
    local -n __x="$1"
    local -n __y="$2"
    local __i
    if (( ${#__x[@]} != ${#__y[@]} )); then
        return 1
    fi
    for (( __i = 0; __i < ${#__x[@]}; __i++ )); do
        if [[ "${__x[$__i]}" != "${__y[$__i]}" ]]; then
            return 1
        fi
    done
    return 0
}

arr_show() {
    local -n __a="$1"
    if (( ${#__a[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__a[@]}"
}

# SGOT / SWANT are the two arrays every comparison uses; globals, so no nameref
# of ours can ever alias a caller's local.
declare -a SGOT=()
declare -a SWANT=()

# oracle ARRNAME CMD... — fill ARRNAME with the command's stdout, one element
# per `\n`-terminated record, the unterminated tail included.
oracle() {
    local -n __o="$1"; shift
    __o=()
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        __o+=( "$__l" )
    done < <( "$@" 2>/dev/null )
}

# tg_dbg COMMAND... — run it with the debug switch on and split stderr:
# TG_N/TG_1 are OUR lines (`Error:`/`Warning:` — kk.debug's shape), TOOL_N is
# everything else (grep writes `grep: …` of its own on the very paths where the
# count matters).
TG_RC=0; TG_N=0; TG_1=''; TOOL_N=0
tg_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TG_RC=$?
    VERBOSE_KKLASS=
    TG_N=0; TOOL_N=0; TG_1=''
    local __l
    while IFS= read -r __l || [[ -n "$__l" ]]; do
        case "$__l" in
            Error:*|Warning:*)
                TG_N=$(( TG_N + 1 ))
                if [[ -z "$TG_1" ]]; then TG_1="$__l"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

printf -v CR '\r'

# same_as_bare TITLE INST BAREARGV... — `INST.toArray` must equal the bare tool.
same_as_bare() {
    local __t="$1" __i="$2"; shift 2
    if ! tcase "$__t"; then
        return 0
    fi
    SGOT=()
    "$__i".toArray SGOT 2>/dev/null || :
    oracle SWANT "$@"
    if (( ${#SWANT[@]} > 0 )) && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool"
    else
        kt_test_fail "got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
}

# ===========================================================================
kt_test_section "A. G5 — no match is an ANSWER: rc 1, lastRc 1, complete silence"
# ===========================================================================

TGrep.new gA zzz_no_such_token "$FX/plain.txt"

if tcase "G5: \`count\` on no match is rc 1 with RESULT 0 and \`lastRc\` 1"; then
    RESULT=sentinel
    rc=0; gA.count || rc=$?
    n="$RESULT"                     # saved BEFORE `lastRc` overwrites RESULT
    gA.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "0" && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, RESULT 0, lastRc 1"
    else
        kt_test_fail "rc=$rc RESULT='$n' lastRc='$lr'"
    fi
fi

if tcase "G5: \`each\` on no match is rc 1 and the callback is never called"; then
    CB_RECS=()
    rc=0; gA.each cb_collect || rc=$?
    gA.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && ${#CB_RECS[@]} -eq 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, 0 records, lastRc 1"
    else
        kt_test_fail "rc=$rc records=${#CB_RECS[@]} lastRc='$lr'"
    fi
fi

if tcase "G5: \`toArray\` on no match is rc 1, RESULT 0, the array EMPTIED"; then
    SGOT=( stale1 stale2 )
    rc=0; gA.toArray SGOT || rc=$?
    if [[ $rc -eq 1 && "$RESULT" == "0" && ${#SGOT[@]} -eq 0 ]]; then
        kt_test_pass "rc 1, RESULT 0, array empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT' SGOT=$(arr_show SGOT)"
    fi
fi

if tcase "G5: \`first\` on no match is rc 1 with RESULT ''"; then
    RESULT=sentinel
    rc=0; gA.first || rc=$?
    if [[ $rc -eq 1 && "$RESULT" == "" ]]; then
        kt_test_pass "rc 1, RESULT ''"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
fi

if tcase "G5: no match says NOTHING, switch on or off (raw 1 is an answer, not an error)"; then
    tg_dbg gA.count
    a_n="$TG_N"; a_tool="$TOOL_N"
    tg_dbg gA.each cb_collect
    b_n="$TG_N"
    tg_dbg gA.first
    c_n="$TG_N"
    if [[ "$a_n" == "0" && "$b_n" == "0" && "$c_n" == "0" && "$a_tool" == "0" ]]; then
        kt_test_pass "count/each/first: not one diagnostic line"
    else
        kt_test_fail "count=$a_n each=$b_n first=$c_n tool=$a_tool ('$TG_1')"
    fi
fi

if tcase "G5: \`run\` on no match is rc 1 and prints nothing"; then
    out="$(gA.run 2>/dev/null)"; rc=$?
    if [[ $rc -eq 1 && -z "$out" ]]; then
        kt_test_pass "rc 1, no output"
    else
        kt_test_fail "rc=$rc out='$out'"
    fi
fi
gA.delete

# ===========================================================================
kt_test_section "B. G6 — the regex dialect: -E is opt-in, \`(\` is literal without it"
# ===========================================================================

if tcase "G6: \`extended = 1\` with pattern \`(\` is rc 1, \`lastRc\` 2 and ONE line"; then
    TGrep.new gB '(' "$FX/paren.txt"
    gB.extended = 1
    CB_RECS=()
    tg_dbg gB.each cb_collect
    rc="$TG_RC"; n="$TG_N"; line="$TG_1"; tool="$TOOL_N"
    gB.lastRc; lr="$RESULT"
    if [[ "$rc" == "1" && "$lr" == "2" && "$n" == "1" && ${#CB_RECS[@]} -eq 0 \
          && "$line" == *"TGrep"* && "$line" == *"2"* && "$tool" -ge 1 ]]; then
        kt_test_pass "rc 1, lastRc 2, one line: ${line:0:70} (grep's own '$tool' line(s) passed through)"
    else
        kt_test_fail "rc=$rc lastRc='$lr' ourLines=$n toolLines=$tool first='$line' recs=${#CB_RECS[@]}"
    fi
    gB.delete
fi

if tcase "G6: the SAME pattern with \`extended\` off is a LITERAL \`(\` — rc 0, one hit"; then
    TGrep.new gB '(' "$FX/paren.txt"
    tg_dbg gB.count
    rc="$TG_RC"; n="$TG_N"
    gB.count; cnt="$RESULT"
    gB.lastRc; lr="$RESULT"
    if [[ "$rc" == "0" && "$cnt" == "1" && "$lr" == "0" && "$n" == "0" ]]; then
        kt_test_pass "BRE: \`(\` matches itself — 1 record, rc 0, no diagnostic"
    else
        kt_test_fail "rc=$rc count='$cnt' lastRc='$lr' lines=$n"
    fi
    gB.delete
fi

if tcase "G6: \`fixed = 1\` (-F) makes \`(\` literal too"; then
    TGrep.new gB '(' "$FX/paren.txt"
    gB.fixed = 1
    SGOT=()
    rc=0; gB.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT 'has ( paren'; then
        kt_test_pass "one literal hit"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gB.delete
fi

if tcase "G6: \`extended = 1\` with a VALID ERE (\`(needle|zebra)\`) matches"; then
    TGrep.new gB '(needle|zebra)' "$FX/plain.txt"
    gB.extended = 1
    SGOT=()
    rc=0; gB.toArray SGOT 2>/dev/null || rc=$?
    oracle SWANT grep -E -e '(needle|zebra)' -- "$FX/plain.txt"
    if [[ $rc -eq 0 ]] && arr_eq SGOT SWANT && (( ${#SWANT[@]} == 2 )); then
        kt_test_pass "2 records, identical to \`grep -E\`"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    gB.delete
fi

# ===========================================================================
kt_test_section "C. G7 — \`-Z\` framing: derived \`-0\` with -l/-L, \\n with -c"
# ===========================================================================

if tcase "G7: \`filesOnly\` + \`nullOut\` — a name with a SPACE and one with a NEWLINE survive"; then
    TGrep.new gC needle "$FX/with space.txt"
    if [[ "$NL_OK" == "1" ]]; then
        gC.paths "$FX/with space.txt" "$NLNAME"
    fi
    gC.filesOnly = 1
    gC.nullOut = 1
    SGOT=()
    rc=0; gC.toArray SGOT 2>/dev/null || rc=$?
    ok=0
    if [[ "$NL_OK" == "1" ]]; then
        msg="2 records, the space and the NEWLINE intact"
        if [[ $rc -eq 0 ]] && arr_is SGOT "$FX/with space.txt" "$NLNAME"; then ok=1; fi
    else
        msg="1 record, the space intact (no newline-in-name on this platform)"
        if [[ $rc -eq 0 ]] && arr_is SGOT "$FX/with space.txt"; then ok=1; fi
    fi
    if [[ "$ok" == "1" && "$(gC.nul)" == "1" ]]; then
        kt_test_pass "$msg; the sinks' -0 was DERIVED (nul = 1)"
    else
        kt_test_fail "rc=$rc nul='$(gC.nul)' SGOT=$(arr_show SGOT)"
    fi
    gC.delete
fi

if tcase "G7: \`filesOnly\` WITHOUT \`nullOut\` splits the newline name — why -Z exists"; then
    if [[ "$NL_OK" != "1" ]]; then
        kt_test_pass "SKIP: no newline-in-name on this platform"
    else
        TGrep.new gC needle "$FX/with space.txt" "$NLNAME"
        gC.filesOnly = 1
        SGOT=()
        rc=0; gC.toArray SGOT 2>/dev/null || rc=$?
        if [[ $rc -eq 0 && ${#SGOT[@]} -eq 3 ]]; then
            kt_test_pass "3 records for 2 files — the newline name was torn in two"
        else
            kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
        fi
        gC.delete
    fi
fi

if tcase "G7: \`countOnly\` + \`nullOut\` does NOT derive -0 (records stay \\n-framed)"; then
    TGrep.new gC needle "$FX/plain.txt" "$FX/other.txt"
    gC.countOnly = 1
    gC.nullOut = 1
    SGOT=()
    rc=0; gC.toArray SGOT 2>/dev/null || rc=$?
    # `-c -Z` writes `NAME\0COUNT\n`: two \n-framed records here, three if the
    # sink had wrongly split on NUL (measured on grep 3.0).
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 2 && "$(gC.nul)" == "0" ]]; then
        kt_test_pass "2 records (one per file), nul untouched"
    else
        kt_test_fail "rc=$rc nul='$(gC.nul)' SGOT=$(arr_show SGOT)"
    fi
    gC.delete
fi

if tcase "G7: \`filesWithoutMatch\` + \`nullOut\` derives -0 too and names the MISS"; then
    TGrep.new gC needle "$FX/plain.txt" "$FX/other.txt"
    gC.filesWithoutMatch = 1
    gC.nullOut = 1
    SGOT=()
    rc=0; gC.toArray SGOT 2>/dev/null || rc=$?
    if [[ "$(gC.nul)" == "1" ]] && arr_is SGOT "$FX/other.txt"; then
        kt_test_pass "the one file WITHOUT a match, NUL-framed"
    else
        kt_test_fail "rc=$rc nul='$(gC.nul)' SGOT=$(arr_show SGOT)"
    fi
    gC.delete
fi

# ===========================================================================
kt_test_section "D. G8 — recursion: an instance never implies -r, \`search\` always does"
# ===========================================================================

if tcase "G8: a DIRECTORY operand without \`recursive\` is rc 1, \`lastRc\` 2, zero records"; then
    TGrep.new gD needle "$FX/sub"
    CB_RECS=()
    tg_dbg gD.each cb_collect
    rc="$TG_RC"; n="$TG_N"; line="$TG_1"
    gD.lastRc; lr="$RESULT"
    if [[ "$rc" == "1" && "$lr" == "2" && ${#CB_RECS[@]} -eq 0 && "$n" == "1" ]]; then
        kt_test_pass "rc 1, lastRc 2, 0 records, one line: ${line:0:66}"
    else
        kt_test_fail "rc=$rc lastRc='$lr' recs=${#CB_RECS[@]} ourLines=$n first='$line'"
    fi
    gD.delete
fi

if tcase "G8: the SAME instance with \`recursive = 1\` finds the tree"; then
    TGrep.new gD needle "$FX/sub"
    gD.recursive = 1
    SGOT=()
    rc=0; gD.toArray SGOT 2>/dev/null || rc=$?
    oracle SWANT grep -r -e needle -- "$FX/sub"
    if [[ $rc -eq 0 ]] && arr_eq SGOT SWANT && (( ${#SWANT[@]} == 2 )); then
        kt_test_pass "2 records (deep.txt, note.log), identical to \`grep -r\`"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    gD.delete
fi

if tcase "G8: \`TGrep.search PATTERN DIR\` implies -r — byte-identical to \`grep -r -e P -- DIR\`"; then
    got="$(TGrep.search needle "$FX/sub" 2>/dev/null)"; rc=$?
    want="$(grep -r -e needle -- "$FX/sub" 2>/dev/null)"; wrc=$?
    if [[ $rc -eq 0 && $wrc -eq 0 && "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc/$wrc got='${got:0:120}' want='${want:0:120}'"
    fi
fi

if tcase "G8: \`TGrep.search\` with NO path is rc 2, prints nothing, one line"; then
    tg_dbg TGrep.search needle
    out="$(TGrep.search needle 2>/dev/null)"
    if [[ "$TG_RC" == "2" && "$TG_N" == "1" && -z "$out" && "$TG_1" == *"search"* ]]; then
        kt_test_pass "rc 2 (\`grep -r\` with no path would have searched \$PWD): ${TG_1:0:64}"
    else
        kt_test_fail "rc=$TG_RC lines=$TG_N out='$out' first='$TG_1'"
    fi
fi

if tcase "G8: \`TGrep.search\` with an EMPTY pattern is rc 2 and runs nothing"; then
    tg_dbg TGrep.search '' "$FX/sub"
    out="$(TGrep.search '' "$FX/sub" 2>/dev/null)"
    if [[ "$TG_RC" == "2" && "$TG_N" == "1" && -z "$out" ]]; then
        kt_test_pass "rc 2 from buildArgv, nothing executed: ${TG_1:0:64}"
    else
        kt_test_fail "rc=$TG_RC lines=$TG_N out='$out' first='$TG_1'"
    fi
fi

if tcase "G8: \`TGrep.search\` on a pattern nothing matches is rc 1 and silent"; then
    tg_dbg TGrep.search zzz_no_such_token "$FX/sub"
    if [[ "$TG_RC" == "1" && "$TG_N" == "0" && "$TOOL_N" == "0" ]]; then
        kt_test_pass "rc 1, no diagnostic"
    else
        kt_test_fail "rc=$TG_RC ourLines=$TG_N toolLines=$TOOL_N first='$TG_1'"
    fi
fi

if tcase "G8: \`search\` deletes its throw-away instance and bumps \`__TG_SEQ\`"; then
    before="$__TG_SEQ"
    TGrep.search needle "$FX/sub" >/dev/null 2>&1
    TGrep.search needle "$FX/sub" >/dev/null 2>&1
    after="$__TG_SEQ"
    left=""
    for s in "$before" "$(( before + 1 ))" "$after"; do
        nm="__tg_s_${BASHPID}_${s}"
        declare -p "${nm}_data" >/dev/null 2>&1 && left+=" ${nm}_data"
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TG_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

# ===========================================================================
kt_test_section "E. G9 — the three forms deliver the same records in the same order"
# ===========================================================================

if tcase "G9: \`search | TPipe.each\` (lastpipe) == \`TPipe.each -- search\` == \`g.each\`"; then
    : > "$ERRF"
    out="$(FX="$FX" UNIT="$UNIT" timeout 30 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
R1=(); R2=(); R3=()
cb1() { R1+=( "$1" ); return 0; }
cb2() { R2+=( "$1" ); return 0; }
cb3() { R3+=( "$1" ); return 0; }
TGrep.search needle "$FX/sub" | TPipe.each cb1
TPipe.each cb2 -- TGrep.search needle "$FX/sub"
TGrep.new g needle "$FX/sub"
g.recursive = 1
g.each cb3
same=1
if (( ${#R1[@]} != ${#R2[@]} || ${#R2[@]} != ${#R3[@]} || ${#R1[@]} == 0 )); then
    same=0
else
    for (( i = 0; i < ${#R1[@]}; i++ )); do
        if [[ "${R1[i]}" != "${R2[i]}" || "${R2[i]}" != "${R3[i]}" ]]; then same=0; fi
    done
fi
printf "n=%s/%s/%s same=%s\n" "${#R1[@]}" "${#R2[@]}" "${#R3[@]}" "$same"
g.delete' 2>"$ERRF")"; rc=$?
    err="$(<"$ERRF")"
    if [[ $rc -eq 0 && "$out" == "n=2/2/2 same=1" ]]; then
        kt_test_pass "all three forms: 2 records, same order"
    else
        kt_test_fail "rc=$rc out='$out' stderr='${err:0:200}'"
    fi
fi

# ===========================================================================
kt_test_section "F. G10 — one missing file among good ones: the records are KEPT"
# ===========================================================================

# grep answers 2 while still writing the other files' hits to stdout. mapRc maps
# that to rc 1 (the call was not fully successful) but the sinks keep every
# record and RESULT is the REAL count — the one place in this family where rc 1
# does not imply RESULT '' (PLAN §2.4).

if tcase "G10: \`toArray\` over good+MISSING+good — rc 1, RESULT = the real count, lastRc 2"; then
    TGrep.new gF needle "$FX/plain.txt" "$FX/no_such_file.txt" "$FX/utf.txt"
    SGOT=()
    rc=0; gF.toArray SGOT 2>/dev/null || rc=$?
    gF.lastRc; lr="$RESULT"
    gF.toArray SGOT 2>/dev/null || :
    n="$RESULT"
    oracle SWANT grep -e needle -- "$FX/plain.txt" "$FX/no_such_file.txt" "$FX/utf.txt"
    if [[ $rc -eq 1 && "$lr" == "2" && "$n" == "3" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "3 records kept, RESULT 3, rc 1, lastRc 2"
    else
        kt_test_fail "rc=$rc lastRc='$lr' RESULT='$n' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    gF.delete
fi

if tcase "G10: \`count\` and \`each\` on the same operands keep everything too"; then
    TGrep.new gF needle "$FX/plain.txt" "$FX/no_such_file.txt" "$FX/utf.txt"
    rc=0; gF.count 2>/dev/null || rc=$?
    cnt="$RESULT"
    CB_RECS=()
    rc2=0; gF.each cb_collect 2>/dev/null || rc2=$?
    if [[ $rc -eq 1 && "$cnt" == "3" && $rc2 -eq 1 && ${#CB_RECS[@]} -eq 3 ]]; then
        kt_test_pass "count: rc 1 RESULT 3; each: rc 1, 3 callback calls"
    else
        kt_test_fail "count rc=$rc RESULT='$cnt'; each rc=$rc2 recs=${#CB_RECS[@]}"
    fi
    gF.delete
fi

if tcase "G10: the partial-failure path emits exactly ONE line of ours (grep's own passes through)"; then
    TGrep.new gF needle "$FX/plain.txt" "$FX/no_such_file.txt" "$FX/utf.txt"
    tg_dbg gF.count
    if [[ "$TG_RC" == "1" && "$TG_N" == "1" && "$TOOL_N" -ge 1 && "$TG_1" == *"TGrep"* ]]; then
        kt_test_pass "one \`$(printf '%s' "${TG_1:0:52}")…\`, $TOOL_N from grep itself"
    else
        kt_test_fail "rc=$TG_RC ourLines=$TG_N toolLines=$TOOL_N first='$TG_1'"
    fi
    gF.delete
fi

# ===========================================================================
kt_test_section "G. G11 — a nested \`search\` inside an outer sink's callback"
# ===========================================================================

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(TGrep.search needle "$FX/plain.txt" 2>/dev/null)"
    NEST_IN+=( "${inner//$'\n'/|}" )
    return 0
}

if tcase "G11: \`g.each\` whose callback runs \`TGrep.search\` — both complete, \`g\` survives"; then
    TGrep.new gG needle "$FX/sub"
    gG.recursive = 1
    NEST_OUT=(); NEST_IN=()
    rc=0; gG.each cb_nest 2>/dev/null || rc=$?
    # the outer instance must be entirely intact afterwards
    SGOT=()
    arc=0; gG.argv SGOT || arc=$?
    gG.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == *"needle"* ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_OUT[@]} -eq 2 && ${#NEST_IN[@]} -eq 2 && "$inner_ok" == "1" \
          && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is SGOT grep -r -e needle -- "$FX/sub"; then
        kt_test_pass "2 outer records, 2 nested searches, the outer instance untouched"
    else
        kt_test_fail "rc=$rc outer=${#NEST_OUT[@]} inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    gG.delete
fi

if tcase "G11: a nested \`search\` inside a \`TGrep.search\`-fed \`TPipe.each\` callback"; then
    NEST_OUT=(); NEST_IN=()
    rc=0
    TPipe.each cb_nest -- TGrep.search needle "$FX/sub" 2>/dev/null || rc=$?
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == *"needle"* ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_OUT[@]} -eq 2 && "$inner_ok" == "1" ]]; then
        kt_test_pass "the outer producer and both nested searches completed"
    else
        kt_test_fail "rc=$rc outer=${#NEST_OUT[@]} inner=${#NEST_IN[@]} ok=$inner_ok"
    fi
fi

# ===========================================================================
kt_test_section "H. G12 — \`-r\` and a REAL directory symlink"
# ===========================================================================

if tcase "G12: \`-r\` does NOT descend a directory symlink (that is why it is never -R)"; then
    if [[ "$SYM_OK" != "1" ]]; then
        kt_test_pass "SKIP: real symlinks unavailable here (kt_make_symlink failed — plain \`ln -s\` copies on this box)"
    else
        TGrep.new gH needle "$FX"
        gH.recursive = 1
        gH.filesOnly = 1
        SGOT=()
        gH.toArray SGOT 2>/dev/null || :
        saw_link=0; saw_real=0
        for x in "${SGOT[@]}"; do
            [[ "$x" == "$FX/dirlink/"* ]] && saw_link=1
            [[ "$x" == "$FX/realdir/linked.txt" ]] && saw_real=1
        done
        # the oracle: -R WOULD descend it
        oracle SWANT grep -R -l -e needle -- "$FX"
        want_link=0
        for x in "${SWANT[@]}"; do
            [[ "$x" == "$FX/dirlink/"* ]] && want_link=1
        done
        if [[ "$saw_link" == "0" && "$saw_real" == "1" && "$want_link" == "1" ]]; then
            kt_test_pass "-r skipped dirlink/ while reaching realdir/; -R would have descended it"
        else
            kt_test_fail "saw_link=$saw_link saw_real=$saw_real (-R would: $want_link) SGOT=$(arr_show SGOT)"
        fi
        gH.delete
    fi
fi

if tcase "G12: a directory symlink NAMED on the command line is followed even under -r"; then
    if [[ "$SYM_OK" != "1" ]]; then
        kt_test_pass "SKIP: real symlinks unavailable here"
    else
        TGrep.new gH needle "$FX/dirlink"
        gH.recursive = 1
        SGOT=()
        rc=0; gH.toArray SGOT 2>/dev/null || rc=$?
        oracle SWANT grep -r -e needle -- "$FX/dirlink"
        if [[ $rc -eq 0 && ${#SGOT[@]} -eq 1 ]] && arr_eq SGOT SWANT; then
            kt_test_pass "1 record through the link, identical to the bare tool"
        else
            kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
        fi
        gH.delete
    fi
fi

if tcase "G12: a FILE symlink named on the command line is read through"; then
    if [[ "$SYM_OK" != "1" ]]; then
        kt_test_pass "SKIP: real symlinks unavailable here"
    else
        TGrep.new gH needle "$FX/filelink.txt"
        SGOT=()
        rc=0; gH.toArray SGOT 2>/dev/null || rc=$?
        if [[ $rc -eq 0 ]] && arr_is SGOT 'alpha needle here' 'needle again'; then
            kt_test_pass "2 records from the link's target"
        else
            kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
        fi
        gH.delete
    fi
fi

# ===========================================================================
kt_test_section "I. CRLF — grep opens input in TEXT mode; \`binary\` (-U) is the way back"
# ===========================================================================

if tcase "§2.6: a record from a CRLF file carries NO CR (grep stripped it, not us)"; then
    TGrep.new gI needle "$FX/crlf.txt"
    SGOT=()
    rc=0; gI.toArray SGOT 2>/dev/null || rc=$?
    rec="${SGOT[0]:-}"
    if [[ $rc -eq 0 && "$rec" == "needle crlf" && ${#rec} -eq 11 ]]; then
        kt_test_pass "'needle crlf', 11 characters — \`crlf = 1\` would have nothing to strip"
    else
        kt_test_fail "rc=$rc len=${#rec} SGOT=$(arr_show SGOT)"
    fi
    gI.delete
fi

if tcase "§2.6: \`binary = 1\` (-U) shows the CR"; then
    TGrep.new gI needle "$FX/crlf.txt"
    gI.binary = 1
    SGOT=()
    rc=0; gI.toArray SGOT 2>/dev/null || rc=$?
    rec="${SGOT[0]:-}"
    if [[ $rc -eq 0 && "$rec" == "needle crlf$CR" ]]; then
        kt_test_pass "'needle crlf\\r', ${#rec} characters"
    else
        kt_test_fail "rc=$rc len=${#rec} SGOT=$(arr_show SGOT)"
    fi
    gI.delete
fi

if tcase "§2.6: \`binary = 1\` + \`crlf = 1\` is the byte-faithful pass that still trims"; then
    TGrep.new gI needle "$FX/crlf.txt"
    gI.binary = 1
    gI.crlf = 1
    SGOT=()
    rc=0; gI.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && "${SGOT[0]:-}" == "needle crlf" ]]; then
        kt_test_pass "the sink's -c took the CR back off"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gI.delete
fi

# ===========================================================================
kt_test_section "J. every remaining typed option, against the bare tool"
# ===========================================================================

TGrep.new gJ Needle "$FX/paren.txt"
gJ.ignoreCase = 1
same_as_bare "J: \`ignoreCase\` -> -i" gJ grep -i -e Needle -- "$FX/paren.txt"
gJ.delete

TGrep.new gJ needle "$FX/plain.txt"
gJ.invert = 1
same_as_bare "J: \`invert\` -> -v (the lines that do NOT match)" gJ \
    grep -v -e needle -- "$FX/plain.txt"
gJ.delete

TGrep.new gJ needl "$FX/plain.txt"
gJ.wordRegexp = 1
if tcase "J: \`wordRegexp\` -> -w (a partial word does not match)"; then
    rc=0; gJ.count 2>/dev/null || rc=$?
    if [[ $rc -eq 1 && "$RESULT" == "0" ]]; then
        kt_test_pass "'needl' is not a word in 'needle' — rc 1, 0 records"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
fi
gJ.delete

TGrep.new gJ 'needle again' "$FX/plain.txt"
gJ.lineRegexp = 1
same_as_bare "J: \`lineRegexp\` -> -x (the WHOLE line must match)" gJ \
    grep -x -e 'needle again' -- "$FX/plain.txt"
gJ.delete

TGrep.new gJ needle "$FX/plain.txt"
gJ.lineNumber = 1
same_as_bare "J: \`lineNumber\` -> -n (\`1:alpha needle here\`)" gJ \
    grep -n -e needle -- "$FX/plain.txt"
gJ.delete

TGrep.new gJ 'need[a-z]*' "$FX/plain.txt"
gJ.onlyMatching = 1
same_as_bare "J: \`onlyMatching\` -> -o (one record per MATCH, not per line)" gJ \
    grep -o -e 'need[a-z]*' -- "$FX/plain.txt"
gJ.delete

TGrep.new gJ needle "$FX/plain.txt"
gJ.maxCount = 1
same_as_bare "J: \`maxCount = 1\` -> -m 1 (one hit, then grep stops)" gJ \
    grep -m 1 -e needle -- "$FX/plain.txt"
gJ.delete

TGrep.new gJ needle "$FX/sub"
gJ.recursive = 1
gJ.include = '*.txt'
same_as_bare "J: \`include\` -> --include=*.txt (note.log is skipped)" gJ \
    grep -r --include='*.txt' -e needle -- "$FX/sub"
gJ.delete

TGrep.new gJ needle "$FX/sub"
gJ.recursive = 1
gJ.exclude = '*.log'
same_as_bare "J: \`exclude\` -> --exclude=*.log" gJ \
    grep -r --exclude='*.log' -e needle -- "$FX/sub"
gJ.delete

TGrep.new gJ needle "$FX"
gJ.recursive = 1
gJ.filesOnly = 1
gJ.excludeDir = 'sub'
if tcase "J: \`excludeDir\` -> --exclude-dir=sub (nothing under sub/ is listed)"; then
    SGOT=()
    gJ.toArray SGOT 2>/dev/null || :
    saw_sub=0
    for x in "${SGOT[@]}"; do
        [[ "$x" == "$FX/sub/"* ]] && saw_sub=1
    done
    oracle SWANT grep -r -l --exclude-dir='sub' -e needle -- "$FX"
    if [[ "$saw_sub" == "0" && ${#SGOT[@]} -gt 0 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} files, none under sub/, identical to the bare tool"
    else
        kt_test_fail "saw_sub=$saw_sub got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
fi
gJ.delete

TGrep.new gJ needle "$FX/plain.txt" "$FX/utf.txt"
gJ.noFilename = 1
same_as_bare "J: \`noFilename\` -> -h (two operands, no \`FILE:\` prefix)" gJ \
    grep -h -e needle -- "$FX/plain.txt" "$FX/utf.txt"
gJ.delete

TGrep.new gJ needle "$FX/plain.txt"
gJ.withFilename = 1
same_as_bare "J: \`withFilename\` -> -H (ONE operand, the prefix forced on)" gJ \
    grep -H -e needle -- "$FX/plain.txt"
gJ.delete

if tcase "J: \`nullData\` -> -z, with a MANUAL \`nul = 1\` for the sink (§2.7)"; then
    TGrep.new gJ needle "$FX/z.dat"
    gJ.nullData = 1
    gJ.nul = 1
    SGOT=()
    rc=0; gJ.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT 'needle zzz'; then
        kt_test_pass "one NUL-framed record from a NUL-framed file"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gJ.delete
fi

if tcase "J: an \`addArg\` extra reaches grep verbatim (the un-modelled-option hatch)"; then
    TGrep.new gJ needle "$FX/plain.txt"
    gJ.addArg --max-count=1
    SGOT=()
    rc=0; gJ.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT 'alpha needle here'; then
        kt_test_pass "\`--max-count=1\` was honoured by grep"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gJ.delete
fi

if tcase "J: an instance with NO path reads STDIN (documented, not a bug)"; then
    TGrep.new gJ needle
    out="$(printf 'one needle\ntwo\n' | gJ.run 2>/dev/null)"; rc=$?
    if [[ $rc -eq 0 && "$out" == "one needle" ]]; then
        kt_test_pass "\`grep -e needle\` with no operand read the pipe"
    else
        kt_test_fail "rc=$rc out='$out'"
    fi
    gJ.delete
fi

# ===========================================================================
kt_test_section "K. binary files — \`Binary file X matches\` is a stdout RECORD"
# ===========================================================================

if tcase "K: a file with a NUL yields the \`Binary file … matches\` RECORD, rc 0"; then
    TGrep.new gK needle "$FX/bin.dat"
    SGOT=()
    rc=0; gK.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 1 && "${SGOT[0]}" == "Binary file "*" matches" ]]; then
        kt_test_pass "one record: ${SGOT[0]}"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gK.delete
fi

if tcase "K: \`addArg -a\` turns it back into text (the documented escape hatch)"; then
    TGrep.new gK needle "$FX/bin.dat"
    gK.addArg -a
    SGOT=()
    rc=0; gK.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT 'needle bin'; then
        kt_test_pass "the matching LINE, not the summary"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gK.delete
fi

if tcase "K: \`addArg --binary-files=text\` does the same"; then
    TGrep.new gK needle "$FX/bin.dat"
    gK.addArg --binary-files=text
    SGOT=()
    rc=0; gK.toArray SGOT 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT 'needle bin'; then
        kt_test_pass "same as -a"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    gK.delete
fi
