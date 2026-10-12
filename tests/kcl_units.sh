#!/bin/bash
# kcl_units.sh — the table of kcl units that carry the unit header, and the
# checks the kcl-level unit tests share (kklass/USES_PLAN.md phase U4; pattern:
# kklass/uses_ledger.json phases.U4.pattern). Not a test file: the ktests
# runner picks up NNN_*.sh only.
#
# Why a kcl-level suite (kcl/tests) and not a helper called from every unit's
# own suite: being a unit is a property of the FILE, the same for all kcl
# units; checked here once per unit (one row each) instead of once per suite
# run, the unit suites keep their totals and their own concerns, and the master
# sweep finds kcl/tests/tests.sh like any other suite.
#
# Files: 001_UnitFiles.sh checks every row statically (one process); each row
# has its own runtime file NNN_<UNIT>.sh (a 3-line stub calling kclt_unit_tests)
# because loading a unit builds its classes — seconds per process (dateutils
# ~20 s) — and one file per unit lets the threaded runner load units in
# parallel. 001 checks that rows and stubs match.
#
# KCL_UNITS — one row per MIGRATED unit file, "UNIT|NAMESPACES|FLAGS|DIR":
#   UNIT        the unit name = the file stem (U33); the file is kcl/DIR/UNIT.sh
#   NAMESPACES  the extra function namespaces the unit declares with
#               `kk.namespace` (U40), space-separated; its own name is declared
#               by its header (kk.unit) and is not listed. A namespace several
#               files of one package define (thttpserver's ths) is listed in the
#               row of EVERY file that defines X.* (pattern rule 4)
#   FLAGS       space-separated:
#                 rundir    the unit keeps a runtime copy of its folder in
#                           <UNIT>_DIR (C19, pattern rule 5)
#                 readonly  the unit assigns readonly globals once per process
#                           (pattern rule 10): `kk.unit --forget UNIT` + a
#                           re-source under `set -e` must be clean
#   DIR         the unit's folder under kcl/ (default: UNIT)
KCL_UNITS=(
    # G1
    "tstopwatch|||"
    "tpath||readonly|"
    "tarray|||"
    "tregex|||"
    "tqueuestack|TQueueStack||"
    "thashset|TSet||"
    "tdictionary|TDict||"
)

# kclt_row ROW — split a row into KU (unit), KNS (namespaces), KFL (flags),
# KD (folder), KF (the file, absolute in the real tree).
kclt_row() {
    IFS='|' read -r KU KNS KFL KD <<<"$1"
    KD=${KD:-$KU}
    KF="$KCL_DIR/$KD/$KU.sh"
}

# kclt_find UNIT — set the K* variables of UNIT's row; rc 1 when it has none.
kclt_find() {
    local r
    for r in "${KCL_UNITS[@]}"; do
        if [[ ${r%%|*} == "$1" ]]; then kclt_row "$r"; return 0; fi
    done
    return 1
}

# kclt_uses FILE — KUSES: the unit names of FILE's file-scope `kk.uses` lines
# (`--optional` dropped), in order.
kclt_uses() {
    local l w
    KUSES=()
    while IFS= read -r l || [[ -n $l ]]; do
        [[ $l =~ ^kk\.uses[[:space:]]+([^|#]*)\|\| ]] || continue
        for w in ${BASH_REMATCH[1]}; do [[ $w == --optional ]] || KUSES+=("$w"); done
    done < "$1"
}

# kclt_setup — KCL_DIR, KBOOL_ROOT, KCLT_TMP (absolute), a neutral empty cwd
# folder ($KCLT_TMP/neutral) and an empty HOME / /etc hook for the children.
kclt_setup() {
    KCL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    KBOOL_ROOT="$(cd "$KCL_DIR/.." && pwd)"
    KCLT_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    mkdir -p "$KCLT_TMP/home" "$KCLT_TMP/etc" "$KCLT_TMP/neutral"
}

# kclt_run CWD SCRIPT [ARG...] — run SCRIPT in a fresh "$BASH" with cwd CWD and
# a hermetic loader environment (no config, no KBOOL_HOME / KK_UNIT_DIR from
# the caller; found_in_U3: fixture shells start in a chosen folder). Sets OUT,
# ERR, RC.
kclt_run() {
    local cwd=$1
    shift
    ( cd "$cwd" && env -u KBOOL_CONFIG -u KBOOL_HOME -u USERPROFILE -u ProgramData -u PROGRAMDATA \
        -u KKLASS_CKK_DIR -u KK_UNIT_DIR -u VERBOSE_KKLASS \
        HOME="$KCLT_TMP/home" __KK_CFG_ETC="$KCLT_TMP/etc" \
        KBOOL_ROOT="$KBOOL_ROOT" KCL_DIR="$KCL_DIR" KCLT_TMP="$KCLT_TMP" T="${T-}" KDEPS="${KDEPS-}" \
        "$BASH" "$@" >"$KCLT_TMP/run.out" 2>"$KCLT_TMP/run.err" ); RC=$?
    OUT="$(<"$KCLT_TMP/run.out")"
    ERR="$(<"$KCLT_TMP/run.err")"
}

# kclt_expect TITLE WANT — pass when OUT == WANT and stderr is empty.
kclt_expect() {
    kt_test_start "$1"
    if [[ "$OUT" == "$2" && -z "$ERR" ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "out='${OUT//$'\n'/|}' want='${2//$'\n'/|}' err='${ERR//$'\n'/|}' rc=$RC"
    fi
}

# ---------------------------------------------------------------------------
# kclt_unit_tests UNIT — the runtime checks of one row (3 or 4 tests):
#   once   a private copy of the tree (kbool.sh, kkore, kklass, the unit's and
#          its kcl dependencies' folders) whose unit file counts its COMPLETE body
#          runs; one fresh `set -eu` bash: a bare absolute `source` bootstraps
#          kbool and registers the unit, then `./U.sh` from its folder,
#          `../kcl/D/U.sh` from kkore/, kk.uses after a cd and the absolute source
#          again are silent no-ops — one run (U19', U27, P7, X-SETU/D7). Rows
#          flagged `readonly`: then `kk.unit --forget U` + a re-source runs it a
#          second time, still clean under set -e (pattern rule 10).
#   name   the REAL tree, a neutral cwd: `source kbool.sh`, the unit's own
#          kk.uses dependencies, then `kk.uses U` by NAME (U12-U14) -> the file;
#          RUNTIME census: every function prefix X (of X.y) the load added is a
#          class of the unit (__KK_UNIT_CLASSES), the unit name, or a namespace
#          __KK_NAMESPACES says this unit owns; the unit name and the row's
#          namespaces are owned by the unit (U40); no old guard variable
#          (`*_<U>_SOURCED`, any prefix) and no `<U>_DIR` / `<unit>_DIR` (unless
#          rundir: then it names the folder); a repeated kk.uses and a plain
#          source are silent no-ops.
#   taken  in the same shell: the unit name and each row namespace N are TAKEN
#          (U22/U40): `<Class>.new N` and `defineClass N` are refused and N's
#          first file-scope function is unchanged.
#   nsbad  rows with namespaces: a class named like the first one exists BEFORE
#          the unit loads -> its plain source is rc 2 and so are the next
#          kk.uses and the next source (the refused kk.namespace taints the unit,
#          U34/U42; review R1 of G1).
kclt_unit_tests() {
    local u=$1 d n fn fs l args=() wtaken="" deps=() seen=" " q i
    if ! kclt_find "$u"; then
        kt_test_start "$u: has a row in kcl_units.sh"
        kt_test_fail "no row for '$u'"
        return
    fi
    local U=${KU^^} f=$KF ns=$KNS fl=$KFL dir=$KD

    # kcl dependencies, transitively (their folders go into the private tree)
    q=("$u")
    for (( i = 0; i < ${#q[@]}; i++ )); do
        kclt_find "${q[i]}" || continue
        deps+=("$KD")
        kclt_uses "$KF"
        for n in "${KUSES[@]}"; do
            [[ $seen == *" $n "* ]] && continue
            seen+="$n "
            q+=("$n")
        done
    done
    kclt_find "$u"
    kclt_uses "$f"
    KDEPS="${KUSES[*]}"

    # --- once (private counting tree) ------------------------------------
    T="$KCLT_TMP/tree"
    rm -rf "$T"
    mkdir -p "$T/kkore" "$T/kklass" "$T/kcl"
    cp "$KBOOL_ROOT/kbool.sh" "$T/"
    cp "$KBOOL_ROOT"/kkore/*.sh "$T/kkore/"
    cp "$KBOOL_ROOT"/kklass/*.sh "$T/kklass/"
    for d in "${deps[@]}"; do
        [[ -d $T/kcl/$d ]] && continue
        mkdir -p "$T/kcl/$d"
        local -a srcs=()    # the folder's files (a unit may read data files next to it)
        for l in "$KCL_DIR/$d"/*; do [[ -f $l ]] && srcs+=("$l"); done
        cp "${srcs[@]}" "$T/kcl/$d/"
    done
    printf '\n__KCLT_N=$(( ${__KCLT_N:-0} + 1 ))\n' >> "$T/kcl/$dir/$u.sh"
    cat > "$KCLT_TMP/once.sh" <<'EOF'
set -eu
u=$1 d=$2 fl=$3; set --
f=$T/kcl/$d/$u.sh
source "$f"
reg=noreg; [[ ${__KK_UNITS[$u]-} -ef $f ]] && reg=reg
cd "$T/kcl/$d"; source "./$u.sh"
cd "$T/kkore"; source "../kcl/$d/$u.sh"
cd "$KCLT_TMP/neutral"; kk.uses "$u"
source "$f"
out="$reg n=${__KCLT_N:-0}"
if [[ " $fl " == *" readonly "* ]]; then
    kk.unit --forget "$u"
    source "$f"
    kk.uses "$u"
    out+=" forget n=${__KCLT_N:-0}"
fi
echo "$out"
EOF
    local want="reg n=1"
    [[ " $fl " == *" readonly "* ]] && want+=" forget n=2"
    kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/once.sh" "$u" "$dir" "$fl"
    kclt_expect "$u once: under set -eu a bare absolute source bootstraps kbool and runs $u once; ./$u.sh, ../kcl/$dir/$u.sh, kk.uses after a cd and the source again are silent no-ops${fl:+ [flags: $fl]} [U19', U27, P7, D7, rule 10]" "$want"

    # --- name + taken (real tree) ----------------------------------------
    for n in "$u" $ns; do
        fn=""
        while IFS= read -r l || [[ -n $l ]]; do
            if [[ $l =~ ^($n\.[A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*\(\) ]]; then fn=${BASH_REMATCH[1]}; break; fi
        done < "$f"
        args+=("$n:$fn")
        [[ -n $fn ]] && fs=same || fs=nofn
        wtaken+=$'\n'"$n new=refused class=refused fn=$fs"
    done
    cat > "$KCLT_TMP/name.sh" <<'EOF'
u=$1 f=$2 fl=$3; shift 3; names=("$@"); set --
U=${u^^}
source "$KBOOL_ROOT/kbool.sh" || { echo "kbool rc=$?"; exit 1; }
for d in $KDEPS; do [[ $d == "$u" ]] || kk.uses "$d" || { echo "dep $d rc=$?"; exit 1; }; done
declare -A pre=()
while IFS= read -r l; do [[ $l == *.* ]] && pre[${l%%.*}]=1; done < <(compgen -A function)
kk.uses "$u"; r1=$?
[[ ${__KK_UNITS[$u]-} -ef $f ]] && out="reg" || out="noreg:${__KK_UNITS[$u]-}"
cls=" ${__KK_UNIT_CLASSES[$u]-} " bad=""
declare -A seen=()
while IFS= read -r l; do
    [[ $l == *.* ]] || continue
    x=${l%%.*}
    [[ -n ${pre[$x]+x} || -n ${seen[$x]+x} ]] && continue
    seen[$x]=1
    o=${__KK_NAMESPACES[$x]-}; o=${o%%$__KK_SEP*}
    [[ $cls == *" $x "* || $x == "$u" || $o == "$u" ]] || bad+=" $x"
done < <(compgen -A function)
out+=" census:${bad:-ok}"
bad=""
for p in "${names[@]}"; do
    n=${p%%:*}; o=${__KK_NAMESPACES[$n]-}; o=${o%%$__KK_SEP*}
    [[ $o == "$u" ]] || bad+=" $n:${o:-none}"
done
out+=" owners:${bad:-ok}"
bad=""
while IFS= read -r l; do
    [[ $l == *_${U}_SOURCED ]] && bad+=" $l"
done < <(compgen -v)
for v in "${U}_DIR" "${u}_DIR"; do
    if [[ " $fl " == *" rundir "* && $v == "${U}_DIR" ]]; then
        [[ ${!v-} -ef ${f%/*} ]] || bad+=" $v=${!v-unset}"
    elif [[ -n ${!v+x} ]]; then
        bad+=" $v"
    fi
done
out+=" old:${bad:-none}"
kk.uses "$u"; r2=$?
source "$f"; r3=$?
echo "r=$r1$r2$r3 $out"
defineClass TKclZz "" property a || { echo "TKclZz rc=$?"; exit 1; }
for p in "${names[@]}"; do
    n=${p%%:*} fn=${p#*:}
    before=""; [[ -n $fn ]] && before="$(declare -f "$fn")"
    TKclZz.new "$n" 2>"$KCLT_TMP/n.err"; i=$?
    if (( i != 0 )) && grep -qF "Invalid instance name: $n (" "$KCLT_TMP/n.err"; then i=refused; else i="ACCEPTED($i):$(<"$KCLT_TMP/n.err")"; fi
    defineClass "$n" "" property zz 2>"$KCLT_TMP/c.err"; c=$?
    if (( c != 0 )) && grep -q "Duplicate identifier" "$KCLT_TMP/c.err"; then c=refused; else c="ACCEPTED($c):$(<"$KCLT_TMP/c.err")"; fi
    if [[ -z $fn ]]; then fs=nofn; elif [[ -n $before && "$(declare -f "$fn")" == "$before" ]]; then fs=same; else fs=changed; fi
    printf '%s new=%s class=%s fn=%s\n' "$n" "$i" "$c" "$fs"
done
EOF
    kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/name.sh" "$u" "$f" "$fl" "${args[@]}"
    local taken=""
    [[ $OUT == *$'\n'* ]] && taken=${OUT#*$'\n'}
    OUT=${OUT%%$'\n'*}
    kclt_expect "$u name: kk.uses $u from a neutral cwd loads kcl/$dir/$u.sh; every function prefix it adds is a class of the unit, $u or a namespace it owns; $u${ns:+ $ns} owned by $u; no old guard / dir variable; repeats silent [U12-U14, U19', U26, U40]" \
        "r=000 reg census:ok owners:ok old:none"
    kt_test_start "$u taken: {$u${ns:+ $ns}}: .new and defineClass refused, the helpers intact [U22, U40, found_in_U2b]"
    if [[ "$taken" == "${wtaken#$'\n'}" && $RC -eq 0 ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "out='${taken//$'\n'/|}' want='${wtaken//$'\n'/|}' rc=$RC"
    fi

    # --- nsbad (rows with namespaces) ------------------------------------
    [[ -n $ns ]] || return 0
    set -- $ns
    cat > "$KCLT_TMP/nsbad.sh" <<'EOF'
u=$1 f=$2 n=$3; set --
source "$KBOOL_ROOT/kbool.sh"
for d in $KDEPS; do kk.uses "$d"; done
defineClass "$n" "" property a || { echo "class $n rc=$?"; exit 1; }
source "$f" 2>/dev/null; a=$?
kk.uses "$u" 2>/dev/null; b=$?
source "$f" 2>/dev/null; c=$?
echo "rc=$a$b$c"
EOF
    kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/nsbad.sh" "$u" "$f" "$1"
    kclt_expect "$u nsbad: a class '$1' exists before $u loads -> its plain source, the next kk.uses and the next source are all rc 2 (the refused kk.namespace taints the unit) [U40, U34/U42, G1 R1]" "rc=222"
}
