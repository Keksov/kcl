#!/bin/bash
# 005_Run.sh — tfind P0: TFind against the real tool on a real tree
# (tfind/PLAN.md §1.1, §2.1–§2.5, §3, §4; pinned facts F6–F11).
#
# The ORACLE is the bare GNU tool run on the same fixture with the same
# expression — never a second call into the code under test. The fixture tree is
# built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`, so the framework
# tears it down; this file installs NO `trap … EXIT` of its own, which would
# replace ktests' trap and swallow the `__COUNTS__` line the runner parses.
#
# THE GATE IS THE FIRST CASE. D4 pins the GNU dialect, not a binary: if
# `find --version` does not begin with `find (GNU findutils) `, every
# behavioural case below is a loud `SKIP`, so the suite stays honest.
#
# THE COMPARISON PRIMITIVE (PLAN §4). find's traversal order is not pinned, and
# the fixture holds a file whose NAME contains a newline — a line-based sort
# turns that one record into two elements and a `sort` would then interleave
# them anywhere. So both sides are NUL framed and sorted with `sort -z`:
#
#   wrapper  print0 = 1  ->  toArray  ->  sortz
#   oracle   find … -print0  ->  mapfile -d ''  ->  sortz
#
# The one deliberate exception is F7's split-name case, which is about the
# `-print` stream itself.
#
# Sections:
#   Z        the GNU banner gate, and the fixture tree
#   A  F6    every typed option against the bare tool on the tree
#   B  F6    symlinks: `-L` descends a real directory symlink and the default
#            `-P` does not; `-L` + `type = l` matches only BROKEN links
#   C  F7    exotic names: the newline name is TWO records under `-print` and
#            ONE under `print0 = 1`; a space survives; `./-weird` works as a
#            start point while `-weird` is rc 2
#   D  F8a   a missing start point among good ones — records KEPT, RESULT = the
#            real count, rc 1, `lastRc` 1, ONE line of ours, `first` still rc 0
#      F8b   `newer` = a missing file — FATAL: zero records, rc 1, `lastRc` 1
#   E  F9    the empty start-point list is find's own `.` — the `cd` happens in
#            THIS file's shell (D6), never in a subshell, and is undone
#   F  F10   actions through `addArg`: with `print0 = 0` the extra's output IS
#            the record stream; `-exec … {} \;` failures leave rc 0 (deviation
#            (c)) while `{} +` propagates rc 1; `print0 = 1` + `-size +0` keeps
#            NUL framing
#   G  F11   `TFind.byName PATTERN START...` in three positions, refused with no
#            start point, propagating rc 2, nested inside an outer `each`
#   H  F3    `type = f,f` passes the wrapper's regex and is the TOOL's rc 1
#
# Calls that make find itself write to stderr get `2>/dev/null`; where the count
# matters, `tf_dbg` separates OUR lines (`Error:`/`Warning:`) from the tool's
# (`find: …`), which is matched by PREFIX because its quoting follows the locale.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../../tdirectory/tests/symlink_helper.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tfind.sh"
source "$UNIT"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/tf.err"

kt_test_section "005: TFind against GNU find on a real tree (P0)"

# ===========================================================================
kt_test_section "Z. the GNU banner gate, and the fixture tree"
# ===========================================================================

GNU_OK=0
kt_test_start "the \`find\` on PATH is GNU findutils (D4 pins the DIALECT, not a binary)"
FIND_BIN="$(command -v find 2>/dev/null || printf '(none)')"
FIND_VER="$(find --version 2>/dev/null | head -1 || :)"
if [[ "$FIND_VER" == "find (GNU findutils) "* ]]; then
    GNU_OK=1
    kt_test_pass "$FIND_BIN — $FIND_VER"
else
    kt_test_pass "SKIP: non-GNU find ($FIND_BIN — '${FIND_VER:-no banner}'); every behavioural case below is skipped"
fi

# tcase TITLE — start a case; rc 1 (already passed as a SKIP) when the gate is
# closed, so a case body reads `if tcase "…"; then … fi` and the case COUNT is
# the same on a GNU box and on one without.
tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU find"
        return 1
    fi
    return 0
}

# --- the tree (PLAN §4) ----------------------------------------------------
# depth 3, every file holding `x\n` so `-size +0` has something to match.
FX="$(cd "$(kt_fixture_tmpdir_create tree)" && pwd)"
mkdir -p "$FX/sub/deep" "$FX/-weird"
NLNAME=$'nl\nname.txt'
printf 'x\n' > "$FX/a.txt"
printf 'x\n' > "$FX/sub/b.TXT"
printf 'x\n' > "$FX/sub/deep/c.txt"
printf 'x\n' > "$FX/with space.txt"
printf 'x\n' > "$FX/$NLNAME"
printf 'x\n' > "$FX/-weird/inside.txt"

SYMOK=0
if kt_symlinks_supported "$FX"; then
    if kt_make_symlink "$FX/link" "$FX/sub" && kt_make_symlink "$FX/broken" "$FX/nowhere"; then
        SYMOK=1
    fi
fi

kt_test_start "the fixture tree is in place (6 files, a \`-weird\` directory, a newline name)"
need_ok=1
for f in a.txt sub/b.TXT sub/deep/c.txt 'with space.txt' -weird/inside.txt; do
    [[ -f "$FX/$f" ]] || need_ok=0
done
[[ -f "$FX/$NLNAME" ]] || need_ok=0
[[ -d "$FX/-weird" ]]  || need_ok=0
if [[ "$need_ok" == "1" ]]; then
    kt_test_pass "tree under $FX; symlinks: $( [[ "$SYMOK" == "1" ]] && echo available || echo unavailable )"
else
    kt_test_fail "a fixture entry is missing under $FX"
fi

# ---------------------------------------------------------------------------
# helpers — all locals use a `__z` prefix so none of them can dynamically
# shadow the unit's own `__tfd_*` scratch namerefs.
# ---------------------------------------------------------------------------

arr_is() {
    local -n __za="$1"; shift
    local __zi=0 __ze
    if (( ${#__za[@]} != $# )); then
        return 1
    fi
    for __ze in "$@"; do
        if [[ "${__za[$__zi]}" != "$__ze" ]]; then
            return 1
        fi
        __zi=$(( __zi + 1 ))
    done
    return 0
}

arr_eq() {
    local -n __zx="$1"
    local -n __zy="$2"
    local __zi
    if (( ${#__zx[@]} != ${#__zy[@]} )); then
        return 1
    fi
    for (( __zi = 0; __zi < ${#__zx[@]}; __zi++ )); do
        if [[ "${__zx[$__zi]}" != "${__zy[$__zi]}" ]]; then
            return 1
        fi
    done
    return 0
}

arr_show() {
    local -n __za="$1"
    if (( ${#__za[@]} == 0 )); then
        printf '(empty)'
        return 0
    fi
    printf '%q ' "${__za[@]}"
}

# sortz ARRNAME — sort the array IN PLACE through `sort -z`. The traversal order
# is not pinned and a record may contain a newline, so this is the only sort
# that can compare the two sides (PLAN §4, critic finding 6).
sortz() {
    local -n __zs="$1"
    if (( ${#__zs[@]} == 0 )); then
        return 0
    fi
    local -a __zt=()
    mapfile -d '' -t __zt < <( printf '%s\0' "${__zs[@]}" | sort -z )
    __zs=( "${__zt[@]}" )
    return 0
}

# oracle0 ARRNAME CMD... — fill ARRNAME from a NUL-framed stdout.
oracle0() {
    local -n __zo="$1"; shift
    __zo=()
    mapfile -d '' -t __zo < <( "$@" 2>/dev/null )
    return 0
}

# oracleL ARRNAME CMD... — fill ARRNAME from a newline-framed stdout, the
# unterminated tail included (used only where the `-print` framing is the point).
oracleL() {
    local -n __zo="$1"; shift
    __zo=()
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        __zo+=( "$__zl" )
    done < <( "$@" 2>/dev/null )
    return 0
}

# tf_dbg COMMAND... — run it with the debug switch on and SPLIT stderr:
# TF_N/TF_1 are OUR lines (`Error:`/`Warning:` — kk.debug's shape), TOOL_N is
# everything else and TOOL_1 the first of those (find's own diagnostics are
# unconditional and locale-quoted, so they are matched by PREFIX).
TF_RC=0; TF_N=0; TF_1=''; TOOL_N=0; TOOL_1=''
tf_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TF_RC=$?
    VERBOSE_KKLASS=
    TF_N=0; TOOL_N=0; TF_1=''; TOOL_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TF_N=$(( TF_N + 1 ))
                if [[ -z "$TF_1" ]]; then TF_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 ))
                if [[ -z "$TOOL_1" ]]; then TOOL_1="$__zl"; fi
                ;;
        esac
    done < "$ERRF"
    return 0
}

# SGOT / SWANT are the two arrays every comparison uses; globals, so no nameref
# of ours can ever alias a caller's local.
declare -a SGOT=()
declare -a SWANT=()

CB_RECS=()
cb_collect() { CB_RECS+=( "$1" ); return 0; }

# A minimal list for `toList`, duck-typed by TPipe (anything with an `.Add`).
class TFTestList
    public
        var         N
        constructor Create
        proc        Add
end
TFTestList.Create() { N=0; return 0; }
TFTestList.Add()    { N=$(( N + 1 )); return 0; }
build TFTestList

# same_as_bare TITLE INST BAREARGV... — `INST.toArray` (NUL framed, so the
# instance must carry `print0 = 1`) must equal the bare tool's `-print0` stream,
# both sides sorted with `sort -z`.
same_as_bare() {
    local __zt="$1" __zi="$2"; shift 2
    if ! tcase "$__zt"; then
        return 0
    fi
    SGOT=()
    local __zrc=0
    "$__zi".toArray SGOT 2>/dev/null || __zrc=$?
    oracle0 SWANT "$@"
    sortz SGOT
    sortz SWANT
    if [[ $__zrc -eq 0 ]] && (( ${#SWANT[@]} > 0 )) && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool"
    else
        kt_test_fail "rc=$__zrc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
}

# ===========================================================================
kt_test_section "A. F6 — every typed option against the bare tool"
# ===========================================================================

# opt TITLE PROP VALUE BAREEXPR... — one instance, `print0 = 1`, one property.
opt() {
    local __zt="$1" __zp="$2" __zv="$3"; shift 3
    TFind.new fO "$FX"
    fO.print0 = 1
    fO."$__zp" = "$__zv"
    same_as_bare "$__zt" fO find "$FX" "$@" -print0
    fO.delete
}

if tcase "F6: no option at all — every entry of the tree, NUL framed"; then
    TFind.new fO "$FX"
    fO.print0 = 1
    SGOT=()
    rc=0; fO.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX" -print0
    sortz SGOT; sortz SWANT
    fO.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && "$lr" == "0" && ${#SGOT[@]} -ge 10 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, rc 0, lastRc 0 — identical to \`find $FX -print0\`"
    else
        kt_test_fail "rc=$rc lastRc='$lr' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fO.delete
fi

opt "F6: \`name = '*.txt'\`"            name     '*.txt'  -name '*.txt'
opt "F6: \`iname = '*.txt'\` also takes \`b.TXT\` (case-insensitive)" \
                                        iname    '*.txt'  -iname '*.txt'
opt "F6: \`type = f\`"                  type     f        -type f
opt "F6: \`type = d\`"                  type     d        -type d
opt "F6: \`type = f,d\` (a comma list)" type     f,d      -type f,d
opt "F6: \`maxDepth = 1\`"              maxDepth 1        -maxdepth 1
opt "F6: \`maxDepth = 0\` is the start point itself" \
                                        maxDepth 0        -maxdepth 0
opt "F6: \`minDepth = 2\`"              minDepth 2        -mindepth 2
opt "F6: \`newer = \$FX/a.txt\`"        newer    "$FX/a.txt" -newer "$FX/a.txt"

if tcase "F6: \`-name\` is case-SENSITIVE on NTFS — \`b.txt\` finds nothing, \`b.TXT\` finds one"; then
    TFind.new fS "$FX"
    fS.print0 = 1
    fS.name = 'b.txt'
    SGOT=()
    rc=0; fS.toArray SGOT || rc=$?
    n_lower="$RESULT"
    TFind.new fS2 "$FX"
    fS2.print0 = 1
    fS2.name = 'b.TXT'
    SWANT=()
    rc2=0; fS2.toArray SWANT || rc2=$?
    n_upper="$RESULT"
    if [[ $rc -eq 0 && $rc2 -eq 0 && "$n_lower" == "0" && "$n_upper" == "1" \
          && "${SWANT[0]}" == "$FX/sub/b.TXT" ]]; then
        kt_test_pass "-name b.txt: 0 records; -name b.TXT: 1 record (${SWANT[0]})"
    else
        kt_test_fail "lower rc=$rc n=$n_lower; upper rc=$rc2 n=$n_upper got=$(arr_show SWANT)"
    fi
    fS.delete
    fS2.delete
fi

if tcase "F6: \`iname = 'B.TXT'\` matches it whatever the case"; then
    TFind.new fS "$FX"
    fS.print0 = 1
    fS.iname = 'B.txt'
    SGOT=()
    rc=0; fS.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "$FX/sub/b.TXT"; then
        kt_test_pass "one record: $FX/sub/b.TXT"
    else
        kt_test_fail "rc=$rc SGOT=$(arr_show SGOT)"
    fi
    fS.delete
fi

if tcase "F6: \`maxDepth\` + \`minDepth\` + \`type\` together == the same bare expression"; then
    TFind.new fO "$FX"
    fO.print0 = 1
    fO.maxDepth = 2
    fO.minDepth = 1
    fO.type = f
    SGOT=()
    rc=0; fO.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX" -maxdepth 2 -mindepth 1 -type f -print0
    sortz SGOT; sortz SWANT
    if [[ $rc -eq 0 ]] && (( ${#SWANT[@]} > 0 )) && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records identical to the bare tool"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fO.delete
fi

# ===========================================================================
kt_test_section "B. F6 — symlinks: \`-L\` vs the default \`-P\`"
# ===========================================================================

# scase TITLE — like tcase, but also skips when this box cannot make a real
# symlink (`kt_make_symlink` from tdirectory's helper; plain `ln -s` runs in
# COPY mode on MSYS and would silently make a directory copy).
scase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: non-GNU find"
        return 1
    fi
    if [[ "$SYMOK" != "1" ]]; then
        kt_test_pass "SKIP: this box cannot create a real symlink"
        return 1
    fi
    return 0
}

if scase "F6: the DEFAULT (-P) does NOT descend the directory symlink"; then
    TFind.new fL "$FX"
    fL.print0 = 1
    fL.type = f
    SGOT=()
    rc=0; fL.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX" -type f -print0
    sortz SGOT; sortz SWANT
    through_link=0
    for r in "${SGOT[@]}"; do
        [[ "$r" == "$FX/link/"* ]] && through_link=1
    done
    if [[ $rc -eq 0 && "$through_link" == "0" ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} files, none of them under \`link/\` — identical to the bare tool"
    else
        kt_test_fail "rc=$rc throughLink=$through_link got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fL.delete
fi

if scase "F6: \`followSymlinks = 1\` (-L) DOES descend it — the same files plus \`link/…\`"; then
    TFind.new fL "$FX"
    fL.print0 = 1
    fL.type = f
    fL.followSymlinks = 1
    SGOT=()
    rc=0; fL.toArray SGOT || rc=$?
    oracle0 SWANT find -L "$FX" -type f -print0
    sortz SGOT; sortz SWANT
    through_link=0
    for r in "${SGOT[@]}"; do
        [[ "$r" == "$FX/link/"* ]] && through_link=$(( through_link + 1 ))
    done
    if [[ $rc -eq 0 && "$through_link" -eq 2 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} files incl. 2 under \`link/\` — identical to \`find -L\`"
    else
        kt_test_fail "rc=$rc throughLink=$through_link got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fL.delete
fi

if scase "F6: \`type = l\` under -P is BOTH links; under \`followSymlinks = 1\` only the BROKEN one"; then
    TFind.new fL "$FX"
    fL.print0 = 1
    fL.type = l
    SGOT=()
    rc=0; fL.toArray SGOT || rc=$?
    sortz SGOT
    TFind.new fL2 "$FX"
    fL2.print0 = 1
    fL2.type = l
    fL2.followSymlinks = 1
    SWANT=()
    rc2=0; fL2.toArray SWANT || rc2=$?
    sortz SWANT
    if [[ $rc -eq 0 && $rc2 -eq 0 ]] \
       && arr_is SGOT "$FX/broken" "$FX/link" \
       && arr_is SWANT "$FX/broken"; then
        kt_test_pass "-P: broken + link; -L: broken only (the documented near no-op)"
    else
        kt_test_fail "P rc=$rc got=$(arr_show SGOT); L rc=$rc2 got=$(arr_show SWANT)"
    fi
    fL.delete
    fL2.delete
fi

# ===========================================================================
kt_test_section "C. F7 — exotic names and the \`-print\` framing"
# ===========================================================================

if tcase "F7: the newline name is TWO records under \`-print\` (print0 = 0)"; then
    TFind.new fW "$FX"
    fW.name = 'nl*'
    SGOT=()
    rc=0; fW.toArray SGOT || rc=$?
    oracleL SWANT find "$FX" -name 'nl*' -print
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 2 && "${SGOT[1]}" == "name.txt" ]] \
       && arr_eq SGOT SWANT; then
        kt_test_pass "2 records — '\${FX}/nl' and 'name.txt', exactly as the bare \`-print\` splits it"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fW.delete
fi

if tcase "F7: the SAME name is ONE record under \`print0 = 1\` (this is why the README leads with it)"; then
    TFind.new fW "$FX"
    fW.name = 'nl*'
    fW.print0 = 1
    SGOT=()
    rc=0; fW.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "$FX/$NLNAME"; then
        kt_test_pass "1 record, the newline intact inside it"
    else
        kt_test_fail "rc=$rc n=${#SGOT[@]} got=$(arr_show SGOT)"
    fi
    fW.delete
fi

if tcase "F7: a name with a SPACE arrives as one record, intact"; then
    TFind.new fW "$FX"
    fW.name = 'with space.txt'
    fW.print0 = 1
    SGOT=()
    rc=0; fW.toArray SGOT || rc=$?
    if [[ $rc -eq 0 ]] && arr_is SGOT "$FX/with space.txt"; then
        kt_test_pass "1 record: $FX/with space.txt"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT)"
    fi
    fW.delete
fi

if tcase "F7: a start point that is an absolute path INTO \`-weird\` works (it does not begin with \`-\`)"; then
    TFind.new fW "$FX/-weird"
    fW.print0 = 1
    SGOT=()
    rc=0; fW.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX/-weird" -print0
    sortz SGOT; sortz SWANT
    if [[ $rc -eq 0 && ${#SGOT[@]} -eq 2 ]] && arr_eq SGOT SWANT; then
        kt_test_pass "2 records — the directory and the file inside it"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fW.delete
fi

# ===========================================================================
kt_test_section "D. F8 — a missing start point (partial) vs a missing \`newer\` (fatal)"
# ===========================================================================

if tcase "F8a: good + MISSING start point — records KEPT, RESULT = the real count, rc 1, lastRc 1"; then
    TFind.new fM "$FX" "$FX/no_such_dir"
    fM.print0 = 1
    fM.type = f
    SGOT=()
    rc=0; fM.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    fM.lastRc; lr="$RESULT"
    oracle0 SWANT find "$FX" "$FX/no_such_dir" -type f -print0
    sortz SGOT; sortz SWANT
    if [[ $rc -eq 1 && "$lr" == "1" && "$n" == "${#SGOT[@]}" && ${#SGOT[@]} -gt 0 ]] \
       && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records kept, RESULT $n, rc 1, lastRc 1 — identical to the bare tool"
    else
        kt_test_fail "rc=$rc lastRc='$lr' RESULT='$n' got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fM.delete
fi

if tcase "F8a: the partial-failure path emits exactly ONE line of ours; find's own passes through"; then
    TFind.new fM "$FX" "$FX/no_such_dir"
    fM.type = f
    tf_dbg fM.count
    if [[ "$TF_RC" == "1" && "$TF_N" == "1" && "$TOOL_N" -ge 1 \
          && "$TF_1" == *"TFind"* && "$TF_1" == *"find exited 1"* \
          && "$TOOL_1" == "find: "* ]]; then
        kt_test_pass "ours: ${TF_1:0:56}… | find's: '${TOOL_1:0:46}…'"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N first='$TF_1' toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
    fM.delete
fi

if tcase "F8a: \`count\` and \`each\` keep everything too, and \`first\` is still rc 0"; then
    TFind.new fM "$FX" "$FX/no_such_dir"
    fM.print0 = 1
    fM.type = f
    rc=0; fM.count 2>/dev/null || rc=$?
    cnt="$RESULT"
    CB_RECS=()
    rc2=0; fM.each cb_collect 2>/dev/null || rc2=$?
    frc=0; fM.first 2>/dev/null || frc=$?
    fv="$RESULT"
    if [[ $rc -eq 1 && $rc2 -eq 1 && "$cnt" == "${#CB_RECS[@]}" && ${#CB_RECS[@]} -gt 0 \
          && $frc -eq 0 && -n "$fv" ]]; then
        kt_test_pass "count rc 1 / $cnt; each rc 1 / ${#CB_RECS[@]} calls; first rc 0 with a record"
    else
        kt_test_fail "count rc=$rc RESULT='$cnt'; each rc=$rc2 recs=${#CB_RECS[@]}; first rc=$frc RESULT='$fv'"
    fi
    fM.delete
fi

if tcase "F8b: \`newer\` = a MISSING file is FATAL — zero records, rc 1, lastRc 1 (not partial)"; then
    TFind.new fB "$FX"
    fB.print0 = 1
    fB.newer = "$FX/no_such_ref"
    SGOT=( stale )
    rc=0; fB.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    fB.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "0" && ${#SGOT[@]} -eq 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, RESULT 0, the array emptied, lastRc 1 — no traversal happened at all"
    else
        kt_test_fail "rc=$rc RESULT='$n' SGOT=$(arr_show SGOT) lastRc='$lr'"
    fi
    fB.delete
fi

if tcase "F8b: a MISSING start point ALONE — zero records, rc 1, lastRc 1"; then
    TFind.new fB "$FX/no_such_dir"
    fB.print0 = 1
    SGOT=( stale )
    rc=0; fB.toArray SGOT 2>/dev/null || rc=$?
    n="$RESULT"
    fB.lastRc; lr="$RESULT"
    if [[ $rc -eq 1 && "$n" == "0" && ${#SGOT[@]} -eq 0 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, RESULT 0, lastRc 1"
    else
        kt_test_fail "rc=$rc RESULT='$n' SGOT=$(arr_show SGOT) lastRc='$lr'"
    fi
    fB.delete
fi

# ===========================================================================
kt_test_section "E. F9 — the empty start-point list is find's own \`.\`"
# ===========================================================================

# The `cd` happens in THIS file's own shell and is undone straight afterwards.
# In a subshell the sink would fill its array where the assertion cannot see it
# and TPipe's D6 warning would fire (PLAN §4, §6; critic finding 5).
F9_RC=0; F9_N=0; F9_EQ=0; F9_DOT=0
F9W_RC=0; F9W_N=0
F9D_RC=0; F9D_N=0; F9D_EQ=0
PWD_BEFORE="$PWD"
if [[ "$GNU_OK" == "1" ]]; then
    cd "$FX" || :

    TFind.new f9
    f9.print0 = 1
    SGOT=()
    F9_RC=0; f9.toArray SGOT || F9_RC=$?
    F9_N=${#SGOT[@]}
    oracle0 SWANT find -print0
    sortz SGOT; sortz SWANT
    arr_eq SGOT SWANT && F9_EQ=1
    F9_DOT=1
    for r in "${SGOT[@]}"; do
        [[ "$r" == "." || "$r" == "./"* ]] || F9_DOT=0
    done
    f9.delete

    # `./-weird` is a legal start point; the bare `-weird` is the wrapper's rc 2
    TFind.new f9d './-weird'
    f9d.print0 = 1
    SGOT=()
    F9D_RC=0; f9d.toArray SGOT || F9D_RC=$?
    F9D_N=${#SGOT[@]}
    oracle0 SWANT find './-weird' -print0
    sortz SGOT; sortz SWANT
    arr_eq SGOT SWANT && F9D_EQ=1
    f9d.delete

    TFind.new f9w '-weird'
    declare -a F9W_ARR=( stale )
    F9W_RC=0; f9w.toArray F9W_ARR 2>/dev/null || F9W_RC=$?
    F9W_N=${#F9W_ARR[@]}
    f9w.delete

    cd "$PWD_BEFORE" || :
fi

if tcase "F9: no start point at all — every record begins \`.\` / \`./…\`, identical to bare \`find -print0\`"; then
    if [[ $F9_RC -eq 0 && $F9_N -ge 10 && "$F9_EQ" == "1" && "$F9_DOT" == "1" ]]; then
        kt_test_pass "$F9_N records, all relative to \`.\` — the tool's own default start point"
    else
        kt_test_fail "rc=$F9_RC n=$F9_N equalToBare=$F9_EQ allDotPrefixed=$F9_DOT"
    fi
fi

if tcase "F9/F7: \`./-weird\` IS a legal start point (2 records, identical to the bare tool)"; then
    if [[ $F9D_RC -eq 0 && $F9D_N -eq 2 && "$F9D_EQ" == "1" ]]; then
        kt_test_pass "2 records from \`./-weird\`"
    else
        kt_test_fail "rc=$F9D_RC n=$F9D_N equalToBare=$F9D_EQ"
    fi
fi

if tcase "F9/F7: the bare \`-weird\` is the wrapper's rc 2 — nothing ran, the array untouched"; then
    if [[ $F9W_RC -eq 2 && $F9W_N -eq 1 ]]; then
        kt_test_pass "rc 2 before find was ever started (the tool would say \`unknown predicate\`)"
    else
        kt_test_fail "rc=$F9W_RC n=$F9W_N"
    fi
fi

kt_test_start "F9: the \`cd\` was undone in THIS file's shell (never in a subshell, D6)"
if [[ "$PWD" == "$PWD_BEFORE" ]]; then
    kt_test_pass "PWD = $PWD_BEFORE"
else
    kt_test_fail "PWD = $PWD (expected $PWD_BEFORE)"
fi

# ===========================================================================
kt_test_section "F. F10 — actions through \`addArg\` (§1.3 item 3, §2.4 (c))"
# ===========================================================================

if tcase "F10a: \`print0 = 0\` + \`-exec printf …\` — the exec output IS the record stream"; then
    TFind.new fX "$FX"
    fX.name = 'a.txt'
    fX.addArg -exec printf 'X:%s\n' '{}' ';'
    SGOT=()
    rc=0; fX.toArray SGOT || rc=$?
    oracleL SWANT find "$FX" -name 'a.txt' -exec printf 'X:%s\n' '{}' ';'
    if [[ $rc -eq 0 ]] && arr_is SGOT "X:$FX/a.txt" && arr_eq SGOT SWANT; then
        kt_test_pass "1 record 'X:…/a.txt' — the implied \`-print\` was suppressed by the action"
    else
        kt_test_fail "rc=$rc got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fX.delete
fi

if tcase "F10a: \`-exec false {} \\;\` is rc 0 with ZERO records — deviation (c)"; then
    TFind.new fX "$FX"
    fX.name = 'a.txt'
    fX.addArg -exec false '{}' ';'
    SGOT=( stale )
    tf_dbg fX.toArray SGOT
    fX.lastRc; lr="$RESULT"
    if [[ "$TF_RC" == "0" && ${#SGOT[@]} -eq 0 && "$TF_N" == "0" && "$lr" == "0" ]]; then
        kt_test_pass "rc 0, 0 records, not one diagnostic — the \`\\;\` form swallows the child's status"
    else
        kt_test_fail "rc=$TF_RC n=${#SGOT[@]} ourLines=$TF_N lastRc='$lr'"
    fi
    fX.delete
fi

if tcase "F10a: the SAME command as \`-exec false {} +\` propagates — rc 1, one line of ours"; then
    TFind.new fX "$FX"
    fX.name = 'a.txt'
    fX.addArg -exec false '{}' '+'
    tf_dbg fX.count
    fX.lastRc; lr="$RESULT"
    if [[ "$TF_RC" == "1" && "$TF_N" == "1" && "$lr" == "1" && "$TF_1" == *"find exited 1"* ]]; then
        kt_test_pass "rc 1, lastRc 1 — use \`{} +\` when the child's status must reach lastRc"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N first='$TF_1' lastRc='$lr'"
    fi
    fX.delete
fi

if tcase "F10b: \`print0 = 1\` + \`addArg -size +0\` keeps the NUL framing (the fixture files hold \`x\\n\`)"; then
    TFind.new fX "$FX"
    fX.print0 = 1
    fX.addArg -size +0
    SGOT=()
    rc=0; fX.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX" -size +0 -print0
    sortz SGOT; sortz SWANT
    has_nl=0
    for r in "${SGOT[@]}"; do
        [[ "$r" == *$'\n'* ]] && has_nl=1
    done
    if [[ $rc -eq 0 && "$(fX.nul)" == "1" && "$has_nl" == "1" ]] \
       && (( ${#SWANT[@]} > 0 )) && arr_eq SGOT SWANT; then
        kt_test_pass "${#SGOT[@]} records, the newline name still ONE of them — identical to the bare tool"
    else
        kt_test_fail "rc=$rc nul='$(fX.nul)' newlineRecord=$has_nl got=$(arr_show SGOT) want=$(arr_show SWANT)"
    fi
    fX.delete
fi

# ===========================================================================
kt_test_section "G. F11 — \`TFind.byName PATTERN START...\`, the static one-liner (§2.5)"
# ===========================================================================

if tcase "F11: \`TFind.byName '*.txt' DIR\` == \`find DIR -name '*.txt'\`, DIRECT"; then
    got="$(TFind.byName '*.txt' "$FX" 2>/dev/null)"; rc=$?
    want="$(find "$FX" -name '*.txt' 2>/dev/null)"; wrc=$?
    if [[ $rc -eq 0 && $wrc -eq 0 && "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "rc 0 and the same bytes as the bare tool"
    else
        kt_test_fail "rc=$rc/$wrc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "F11: the same through a PIPE (\`| od -c\`) — byte-identical"; then
    got="$(TFind.byName '*.txt' "$FX" 2>/dev/null | od -c)"
    want="$(find "$FX" -name '*.txt' 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "F11: the same through \`< <( )\` — byte-identical"; then
    got="$(cat < <(TFind.byName '*.txt' "$FX" 2>/dev/null) | od -c)"
    want="$(find "$FX" -name '*.txt' 2>/dev/null | od -c)"
    if [[ "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "the same byte stream"
    else
        kt_test_fail "got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "F11: \`byName\` with TWO start points searches both"; then
    got="$(TFind.byName '*.txt' "$FX/sub" "$FX/-weird" 2>/dev/null)"; rc=$?
    want="$(find "$FX/sub" "$FX/-weird" -name '*.txt' 2>/dev/null)"
    if [[ $rc -eq 0 && "$got" == "$want" && -n "$got" ]]; then
        kt_test_pass "identical to the bare tool over both trees"
    else
        kt_test_fail "rc=$rc got='${got//$'\n'/|}' want='${want//$'\n'/|}'"
    fi
fi

if tcase "F11: \`TFind.byName\` with NO start point is rc 2, prints nothing, one line"; then
    tf_dbg TFind.byName '*.txt'
    out="$(TFind.byName '*.txt' 2>/dev/null </dev/null)"
    if [[ "$TF_RC" == "2" && "$TF_N" == "1" && -z "$out" && "$TF_1" == *"byName"* ]]; then
        kt_test_pass "rc 2 (with none find would search the CALLER's cwd): ${TF_1:0:56}"
    else
        kt_test_fail "rc=$TF_RC lines=$TF_N out='$out' first='$TF_1'"
    fi
fi

if tcase "F11: a REFUSED start point propagates rc 2 out of \`byName\` through \`run\`"; then
    tf_dbg TFind.byName '*.txt' '-weird'
    out="$(TFind.byName '*.txt' '-weird' 2>/dev/null </dev/null)"
    if [[ "$TF_RC" == "2" && "$TF_N" == "1" && -z "$out" && "$TF_1" == *"start point"* ]]; then
        kt_test_pass "rc 2 from buildArgv, straight through run: ${TF_1:0:56}"
    else
        kt_test_fail "rc=$TF_RC lines=$TF_N out='$out' first='$TF_1'"
    fi
fi

if tcase "F11: \`byName\` on a MISSING start point is rc 1 (find's own status, mapped)"; then
    tf_dbg TFind.byName '*.txt' "$FX/no_such_dir"
    if [[ "$TF_RC" == "1" && "$TF_N" == "1" && "$TOOL_N" -ge 1 && "$TOOL_1" == "find: "* ]]; then
        kt_test_pass "rc 1, one line of ours, find's own passed through"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N toolLines=$TOOL_N toolFirst='$TOOL_1'"
    fi
fi

if tcase "F11: \`byName\` deletes its throw-away instance and bumps \`__TFD_SEQ\`"; then
    before="$__TFD_SEQ"
    TFind.byName '*.txt' "$FX" >/dev/null 2>&1
    TFind.byName '*.txt' "$FX" >/dev/null 2>&1
    after="$__TFD_SEQ"
    left=""
    for s in "$before" "$(( before + 1 ))" "$after"; do
        nm="__tfd_b_${BASHPID}_${s}"
        declare -p "${nm}_data" >/dev/null 2>&1 && left+=" ${nm}_data"
        declare -F "${nm}.delete" >/dev/null 2>&1 && left+=" ${nm}.delete"
    done
    if [[ $(( after - before )) -eq 2 && -z "$left" ]]; then
        kt_test_pass "__TFD_SEQ $before -> $after, no instance left behind"
    else
        kt_test_fail "seq $before -> $after; left:$left"
    fi
fi

NEST_OUT=()
NEST_IN=()
cb_nest() {
    NEST_OUT+=( "$1" )
    local inner
    inner="$(TFind.byName 'b.TXT' "$FX/sub" 2>/dev/null)"
    NEST_IN+=( "$inner" )
    return 0
}

if tcase "F11: a nested \`byName\` inside an outer \`each\` — both complete, the outer instance survives"; then
    TFind.new fT "$FX"
    fT.print0 = 1
    fT.name = '*.txt'
    fT.type = f
    NEST_OUT=(); NEST_IN=()
    rc=0; fT.each cb_nest 2>/dev/null || rc=$?
    SGOT=()
    arc=0; fT.argv SGOT || arc=$?
    fT.lastRc; lr="$RESULT"
    inner_ok=1
    for x in "${NEST_IN[@]}"; do
        [[ "$x" == "$FX/sub/b.TXT" ]] || inner_ok=0
    done
    if [[ $rc -eq 0 && ${#NEST_OUT[@]} -gt 0 && ${#NEST_IN[@]} -eq ${#NEST_OUT[@]} \
          && "$inner_ok" == "1" && $arc -eq 0 && "$lr" == "0" ]] \
       && arr_is SGOT find "$FX" -name '*.txt' -type f -print0; then
        kt_test_pass "${#NEST_OUT[@]} outer records, as many nested byName calls, the outer argv untouched"
    else
        kt_test_fail "rc=$rc outer=${#NEST_OUT[@]} inner=${#NEST_IN[@]} ok=$inner_ok argvRc=$arc lastRc='$lr' argv=$(arr_show SGOT)"
    fi
    fT.delete
fi

if tcase "F11: \`byName\` composes with both TPipe forms"; then
    N1=0
    cb1() { N1=$(( N1 + 1 )); return 0; }
    rc=0
    TPipe.each cb1 -- TFind.byName 'a.txt' "$FX" 2>/dev/null || rc=$?
    out="$(FX="$FX" UNIT="$UNIT" timeout 20 "$BASH" -c '
set -u
shopt -s lastpipe
source "$UNIT"
N=0
cb() { N=$(( N + 1 )); return 0; }
TFind.byName "a.txt" "$FX" | TPipe.each cb
printf "%s" "$N"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $rc -eq 0 && "$N1" == "1" && $crc -eq 0 && "$out" == "1" ]]; then
        kt_test_pass "the \`--\` form: 1 record; the lastpipe form: 1 record"
    else
        kt_test_fail "-- form rc=$rc N1=$N1; lastpipe rc=$crc out='$out'"
    fi
fi

# ===========================================================================
kt_test_section "H. F3 — the values the wrapper passes through to the tool"
# ===========================================================================

if tcase "F3: \`type = f,f\` builds and is the TOOL's rc 1 (the duplicate, parity)"; then
    TFind.new fV "$FX"
    fV.type = f,f
    tf_dbg fV.count
    fV.lastRc; lr="$RESULT"
    if [[ "$TF_RC" == "1" && "$TF_N" == "1" && "$TOOL_N" -ge 1 && "$lr" == "1" \
          && "$TOOL_1" == "find: "* ]]; then
        kt_test_pass "rc 1, lastRc 1, one line of ours, find's: '${TOOL_1:0:52}…'"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N toolLines=$TOOL_N lastRc='$lr' toolFirst='$TOOL_1'"
    fi
    fV.delete
fi

if tcase "F3: \`maxDepth = 08\` is DEPTH 8 and \`= +1\` is DEPTH 1 (the \$__KK_INT normalisation)"; then
    TFind.new fV "$FX"
    fV.print0 = 1
    fV.maxDepth = +1
    SGOT=()
    rc=0; fV.toArray SGOT || rc=$?
    oracle0 SWANT find "$FX" -maxdepth 1 -print0
    sortz SGOT; sortz SWANT
    eq1=0
    arr_eq SGOT SWANT && eq1=1
    TFind.new fV2 "$FX"
    fV2.print0 = 1
    fV2.maxDepth = 08
    SGOT=()
    rc2=0; fV2.toArray SGOT || rc2=$?
    oracle0 SWANT find "$FX" -maxdepth 8 -print0
    sortz SGOT; sortz SWANT
    eq2=0
    arr_eq SGOT SWANT && eq2=1
    if [[ $rc -eq 0 && $rc2 -eq 0 && "$eq1" == "1" && "$eq2" == "1" ]]; then
        kt_test_pass "both ran (a verbatim \`+1\` would have been the tool's rc 1) and matched the bare tool"
    else
        kt_test_fail "+1 rc=$rc eq=$eq1; 08 rc=$rc2 eq=$eq2"
    fi
    fV.delete
    fV2.delete
fi

if tcase "F3: a depth above INT_MAX reaches find and is its OWN rc 1"; then
    TFind.new fV "$FX"
    fV.maxDepth = 2147483648
    tf_dbg fV.count
    fV.lastRc; lr="$RESULT"
    if [[ "$TF_RC" == "1" && "$TF_N" == "1" && "$TOOL_N" -ge 1 && "$lr" == "1" ]]; then
        kt_test_pass "rc 1, lastRc 1 — the wrapper built it, the tool refused it"
    else
        kt_test_fail "rc=$TF_RC ourLines=$TF_N toolLines=$TOOL_N lastRc='$lr'"
    fi
    fV.delete
fi

if tcase "F6: every sink agrees on the same instance — each / count / toArray / first / toList / run"; then
    TFind.new fK "$FX"
    fK.print0 = 1
    fK.type = f
    CB_RECS=()
    rc=0; fK.each cb_collect || rc=$?
    crc=0; fK.count || crc=$?
    cnt="$RESULT"
    SGOT=()
    arc=0; fK.toArray SGOT || arc=$?
    nn="$RESULT"
    frc=0; fK.first || frc=$?
    TFTestList.new fKL
    lrc=0; fK.toList fKL || lrc=$?
    nl="$RESULT"
    rrc=0; fK.run >/dev/null 2>&1 || rrc=$?
    if [[ $rc -eq 0 && $crc -eq 0 && $arc -eq 0 && $frc -eq 0 && $lrc -eq 0 && $rrc -eq 0 \
          && "$cnt" == "${#CB_RECS[@]}" && "$nn" == "$cnt" && "$nl" == "$cnt" \
          && "$(fKL.N)" == "$cnt" && "$cnt" -ge 6 ]]; then
        kt_test_pass "all six agree on $cnt records"
    else
        kt_test_fail "each rc=$rc n=${#CB_RECS[@]}; count rc=$crc n=$cnt; toArray rc=$arc n=$nn; first rc=$frc; toList rc=$lrc n=$nl stored=$(fKL.N); run rc=$rrc"
    fi
    fKL.delete
    fK.delete
fi
