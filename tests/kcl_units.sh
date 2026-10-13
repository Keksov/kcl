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
# parallel; each stub loads its unit ONCE (kclt_unit_tests; a unit that uses
# another unit of the table once more, behind that dependency). 001 checks that
# rows and stubs match. A stub may add checks of its own unit after the call
# (202_math.sh: the float engine across `kk.unit --forget math`).
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
    # G2
    "dateutils||readonly|"
    "math||rundir readonly|"
    "tinifile|||"
    "tstringhelper|||"
    # G3 (kcl dependencies by name: tfile/tdirectory -> tpath, tlist -> tarray,
    # tobjectlist/tstringlist -> tlist)
    "tfile||readonly|"
    "tdirectory|||"
    "tlist|||"
    "tobjectlist|||"
    "tstringlist|||"
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

# kclt_scan FILE — read FILE statically: KFNS the file-scope functions in order
# (newline-terminated; sentinel candidates), KBUILDS the classes of its
# file-scope `build X` lines (" X Y"), KLASTFN the last function defined AFTER
# the last build (completeness markers; a build consumes the Pascal method
# bodies before it, its registration is the marker for them).
kclt_scan() {
    local l n
    KFNS="" KBUILDS="" KLASTFN=""
    while IFS= read -r l || [[ -n $l ]]; do
        l=${l%$'\r'}
        n=""
        if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*\(\) ]]; then n=${BASH_REMATCH[1]}
        elif [[ $l =~ ^function[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*(\(\))?[[:space:]]*(\{|$) ]]; then n=${BASH_REMATCH[1]}; fi
        if [[ -n $n ]]; then KFNS+=$n$'\n'; KLASTFN=$n; fi
        if [[ $l =~ ^build[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*$ ]]; then KBUILDS+=" ${BASH_REMATCH[1]}"; KLASTFN=""; fi
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
        KBOOL_ROOT="$KBOOL_ROOT" KCL_DIR="$KCL_DIR" KCLT_TMP="$KCLT_TMP" KDEPS="${KDEPS-}" \
        KCLT_FORGET_PRE="${KCLT_FORGET_PRE-}" KCLT_FORGET_POST="${KCLT_FORGET_POST-}" \
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
# kclt_unit_tests UNIT — the runtime checks of one row (3 to 5 tests). ONE
# full load of the unit (a fresh bash in the REAL tree, a neutral cwd) gives
# the first three; mixed (rows with a kcl dependency) is a second full load
# behind its dependencies; nsbad is a short process (its load stops at the
# refused kk.namespace).
#   once   under `set -eu`: a bare absolute `source` bootstraps kbool and
#          registers the unit (U19', P7) and runs its body completely — every
#          class of a file-scope `build X` line is filed under the unit and the
#          last file-scope function defined after the last build (if any) is
#          defined; then a SENTINEL replaces the first file-scope function that
#          survived the load (a Pascal method body is consumed by `build`;
#          a helper or static method is not; when none survives — tlist — the
#          sentinel is defined under the first one's NAME: a re-run defines
#          that body again and the build or the same-site sink consumes it);
#          `./U.sh` from its folder,
#          `../kcl/D/U.sh` from kkore/, `kk.uses U` by NAME after a cd to a
#          neutral folder (it resolves the name and compares the file, U12-U14,
#          R3 of U1a) and the absolute source again leave the sentinel in place
#          = the body did not run again (U27, D7). Rows flagged `readonly`: then
#          `kk.unit --forget U` + a re-source runs the body a second time (the
#          sentinel is the unit's own function again) and a kk.uses after it is
#          a no-op, still clean under set -e (pattern rule 10). A stub may set
#          KCLT_FORGET_PRE / KCLT_FORGET_POST (shell text eval'd in that
#          process, under set -eu, right before the --forget and after the
#          reload; 202_math.sh checks its float engine across the reload) —
#          no second load of the unit for it.
#   name   the same shell, `set +eu`: RUNTIME census — every function prefix X
#          (of X.y) in the shell is a class some unit registered
#          (__KK_UNIT_CLASSES) or a namespace somebody declared
#          (__KK_NAMESPACES: kbool's kk kl ke kv kc, unit names, kk.namespace);
#          the unit name and the row's namespaces are owned by the unit (U40);
#          no old guard variable (`*_<U>_SOURCED`, any prefix) and no `<U>_DIR` /
#          `<unit>_DIR` (unless rundir: then it names the folder).
#   taken  the same shell: the unit name and each row namespace N are TAKEN
#          (U22/U40): `<Class>.new N` and `defineClass N` are refused and N's
#          first file-scope function is unchanged.
#   mixed  rows whose `kk.uses` lines name another unit of the table (U4-G3:
#          tfile/tdirectory -> tpath, tlist -> tarray, tobjectlist/tstringlist ->
#          tlist): a second process plain-sources those dependencies FIRST by
#          the path the old header-less unit formed (kcl/D/../E/N.sh — the
#          mixed order of P7 / pattern rule 8, a caller that still sources a
#          dependency by path), puts a sentinel over each one's first surviving
#          function, then sources the unit bare under set -eu: the unit registers
#          and runs completely, every dependency stays registered to its file
#          and is not loaded again (the sentinel stays), and `kk.uses N` of each
#          is a silent no-op.
#   nsbad  rows with namespaces: a class named like the first one exists BEFORE
#          the unit loads -> its plain source is rc 2 and so are the next
#          kk.uses and the next source (the refused kk.namespace taints the unit,
#          U34/U42; review R1 of G1).
# Until U4-G2 `once` ran in a second process, in a private copy of the tree
# whose unit file counted its complete body runs; the sentinel and the
# registered classes prove the same in the real tree with one load (G2 fold).
kclt_unit_tests() {
    local u=$1 n fn fs l args=() wtaken="" fns="" lastfn="" builds="" d mdeps=() mwant=""
    if ! kclt_find "$u"; then
        kt_test_start "$u: has a row in kcl_units.sh"
        kt_test_fail "no row for '$u'"
        return
    fi
    local U=${KU^^} f=$KF ns=$KNS fl=$KFL dir=$KD
    kclt_uses "$f"
    KDEPS="${KUSES[*]}"

    # read statically: the sentinel candidates and the completeness markers
    kclt_scan "$f"
    fns=$KFNS builds=$KBUILDS lastfn=$KLASTFN

    # --- once + name + taken (one process, the real tree) ----------------
    for n in "$u" $ns; do
        fn=""
        while IFS= read -r l || [[ -n $l ]]; do
            if [[ $l =~ ^($n\.[A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*\(\) ]]; then fn=${BASH_REMATCH[1]}; break; fi
        done < "$f"
        args+=("$n:$fn")
        [[ -n $fn ]] && fs=same || fs=nofn
        wtaken+=$'\n'"$n new=refused class=refused fn=$fs"
    done
    printf '%s' "$fns" > "$KCLT_TMP/fns.txt"
    cat > "$KCLT_TMP/unit.sh" <<'EOF'
KC_u=$1 KC_f=$2 KC_d=$3 KC_fl=$4 KC_builds=$5 KC_lastfn=$6; shift 6; KC_names=("$@"); set --
KC_U=${KC_u^^}
set -eu
# once: bootstrap through the header, complete body, sentinel, no-op re-sources
source "$KC_f"
KC_o=noreg; [[ ${__KK_UNITS[$KC_u]-} -ef $KC_f ]] && KC_o=reg
KC_body=complete
for KC_x in $KC_builds; do
    [[ " ${__KK_UNIT_CLASSES[$KC_u]-} " == *" $KC_x "* ]] || KC_body+=" no-build:$KC_x"
done
if [[ -n $KC_lastfn ]] && ! declare -F "$KC_lastfn" >/dev/null; then KC_body+=" no-fn:$KC_lastfn"; fi
KC_s=""
while IFS= read -r KC_x; do
    if declare -F "$KC_x" >/dev/null; then KC_s=$KC_x; break; fi
done < "$KCLT_TMP/fns.txt"
# no file-scope function survived (all are Pascal method bodies its build
# consumed: tlist) -> the sentinel takes the first one's NAME: a body re-run
# defines it again and its build (or the same-site sink) consumes it
[[ -n $KC_s ]] || IFS= read -r KC_s < "$KCLT_TMP/fns.txt" || :
KC_orig="" KC_sent=""
# put the unit's own function back (or drop the sentinel of a consumed name)
KC_restore() { if [[ -n $KC_orig ]]; then eval "$KC_orig"; else unset -f "$KC_s"; fi; }
if [[ -n $KC_s ]]; then
    KC_orig="$(declare -f "$KC_s" || :)"
    eval "$KC_s() { : kclt-sentinel; }"
    KC_sent="$(declare -f "$KC_s")"
fi
cd "$KCL_DIR/$KC_d"; source "./$KC_u.sh"
cd "$KBOOL_ROOT/kkore"; source "../kcl/$KC_d/$KC_u.sh"
cd "$KCLT_TMP/neutral"; kk.uses "$KC_u"
source "$KC_f"
if [[ -z $KC_s ]]; then KC_n=nosentinel
elif [[ "$(declare -f "$KC_s")" == "$KC_sent" ]]; then KC_n=1
else KC_n=rerun:$KC_s; fi
KC_o+=" body=${KC_body// /,} n=$KC_n"
if [[ " $KC_fl " == *" readonly "* ]]; then
    # the unit's own function while a stub's hook runs, then the sentinel again
    [[ -z $KC_s ]] || KC_restore
    if [[ -n ${KCLT_FORGET_PRE-} ]]; then eval "$KCLT_FORGET_PRE"; fi
    [[ -z $KC_s ]] || eval "$KC_s() { : kclt-sentinel; }"
    kk.unit --forget "$KC_u"
    source "$KC_f"
    kk.uses "$KC_u"
    if [[ -n $KC_s && "$(declare -f "$KC_s" || :)" == "$KC_orig" ]]; then KC_o+=" forget n=2"; else KC_o+=" forget not-reloaded"; fi
    if [[ -n ${KCLT_FORGET_POST-} ]]; then eval "$KCLT_FORGET_POST"; fi
fi
[[ -z $KC_s ]] || KC_restore
echo "$KC_o"
set +eu
# name: runtime census, owners, old variables
KC_cls=" ${__KK_UNIT_CLASSES[*]} " KC_bad=""
declare -A KC_seen=()
while IFS= read -r KC_l; do
    [[ $KC_l == *.* ]] || continue
    KC_x=${KC_l%%.*}
    [[ -n ${KC_seen[$KC_x]+x} ]] && continue
    KC_seen[$KC_x]=1
    [[ $KC_cls == *" $KC_x "* || -n ${__KK_NAMESPACES[$KC_x]-} ]] || KC_bad+=" $KC_x"
done < <(compgen -A function)
KC_o="census:${KC_bad:-ok}"
KC_bad=""
for KC_p in "${KC_names[@]}"; do
    KC_x=${KC_p%%:*} KC_w=${__KK_NAMESPACES[${KC_p%%:*}]-}; KC_w=${KC_w%%$__KK_SEP*}
    [[ $KC_w == "$KC_u" ]] || KC_bad+=" $KC_x:${KC_w:-none}"
done
KC_o+=" owners:${KC_bad:-ok}"
KC_bad=""
while IFS= read -r KC_l; do
    [[ $KC_l == *_${KC_U}_SOURCED ]] && KC_bad+=" $KC_l"
done < <(compgen -v)
for KC_v in "${KC_U}_DIR" "${KC_u}_DIR"; do
    if [[ " $KC_fl " == *" rundir "* && $KC_v == "${KC_U}_DIR" ]]; then
        [[ ${!KC_v-} -ef ${KC_f%/*} ]] || KC_bad+=" $KC_v=${!KC_v-unset}"
    elif [[ -n ${!KC_v+x} ]]; then
        KC_bad+=" $KC_v"
    fi
done
echo "$KC_o old:${KC_bad:-none}"
# taken
defineClass TKclZz "" property a || { echo "TKclZz rc=$?"; exit 1; }
for KC_p in "${KC_names[@]}"; do
    KC_x=${KC_p%%:*} KC_fn=${KC_p#*:}
    KC_before=""; [[ -n $KC_fn ]] && KC_before="$(declare -f "$KC_fn")"
    TKclZz.new "$KC_x" 2>"$KCLT_TMP/n.err"; KC_i=$?
    if (( KC_i != 0 )) && grep -qF "Invalid instance name: $KC_x (" "$KCLT_TMP/n.err"; then KC_i=refused; else KC_i="ACCEPTED($KC_i):$(<"$KCLT_TMP/n.err")"; fi
    defineClass "$KC_x" "" property zz 2>"$KCLT_TMP/c.err"; KC_c=$?
    if (( KC_c != 0 )) && grep -q "Duplicate identifier" "$KCLT_TMP/c.err"; then KC_c=refused; else KC_c="ACCEPTED($KC_c):$(<"$KCLT_TMP/c.err")"; fi
    if [[ -z $KC_fn ]]; then KC_fs=nofn; elif [[ -n $KC_before && "$(declare -f "$KC_fn")" == "$KC_before" ]]; then KC_fs=same; else KC_fs=changed; fi
    printf '%s new=%s class=%s fn=%s\n' "$KC_x" "$KC_i" "$KC_c" "$KC_fs"
done
EOF
    kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/unit.sh" "$u" "$f" "$dir" "$fl" "$builds" "$lastfn" "${args[@]}"
    local once=${OUT%%$'\n'*} name="" taken=""
    [[ $OUT == *$'\n'* ]] && name=${OUT#*$'\n'}
    [[ $name == *$'\n'* ]] && taken=${name#*$'\n'}
    name=${name%%$'\n'*}
    local want="reg body=complete n=1"
    [[ " $fl " == *" readonly "* ]] && want+=" forget n=2"
    OUT=$once
    kclt_expect "$u once: under set -eu a bare absolute source bootstraps kbool, registers $u and runs its body completely; ./$u.sh, ../kcl/$dir/$u.sh, kk.uses $u by name from a neutral cwd and the source again are silent no-ops (a sentinel function stays)${fl:+ [flags: $fl]} [U19', U27, P7, D7, U12-U14, rule 10]" "$want"
    OUT=$name
    kclt_expect "$u name: every function prefix in the shell is a registered class or a declared namespace; $u${ns:+ $ns} owned by $u; no old guard / dir variable [U19', U26, U40]" \
        "census:ok owners:ok old:none"
    kt_test_start "$u taken: {$u${ns:+ $ns}}: .new and defineClass refused, the helpers intact [U22, U40, found_in_U2b]"
    if [[ "$taken" == "${wtaken#$'\n'}" && $RC -eq 0 ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "out='${taken//$'\n'/|}' want='${wtaken//$'\n'/|}' rc=$RC"
    fi

    # --- mixed (rows that kk.uses another kcl unit of the table) ----------
    for d in $KDEPS; do
        kclt_find "$d" || continue
        kclt_scan "$KF"
        printf '%s' "$KFNS" > "$KCLT_TMP/fns_$d.txt"
        mdeps+=("$d|$KCL_DIR/$dir/../$KD/$d.sh|$KCLT_TMP/fns_$d.txt|$KF")
        mwant+=" $d=reg,1"
    done
    if (( ${#mdeps[@]} )); then
        cat > "$KCLT_TMP/mixed.sh" <<'EOF'
KC_u=$1 KC_f=$2 KC_builds=$3 KC_lastfn=$4; shift 4; KC_deps=("$@"); set --
set -eu
declare -A KC_sent=() KC_def=()
# the dependencies first, plain-sourced by the path the old header-less unit
# formed (its folder + ../D/N.sh), each with a sentinel over its first
# surviving file-scope function (else the first one's name, as in once)
for KC_p in "${KC_deps[@]}"; do
    IFS='|' read -r KC_dn KC_dp KC_df KC_dfile <<<"$KC_p"
    source "$KC_dp"
    KC_s=""
    while IFS= read -r KC_x; do
        if declare -F "$KC_x" >/dev/null; then KC_s=$KC_x; break; fi
    done < "$KC_df"
    [[ -n $KC_s ]] || IFS= read -r KC_s < "$KC_df" || :
    KC_sent[$KC_dn]=$KC_s KC_def[$KC_dn]=""
    if [[ -n $KC_s ]]; then
        eval "$KC_s() { : kclt-sentinel-$KC_dn; }"
        KC_def[$KC_dn]="$(declare -f "$KC_s")"
    fi
done
source "$KC_f"
KC_o=noreg; [[ ${__KK_UNITS[$KC_u]-} -ef $KC_f ]] && KC_o=reg
KC_body=complete
for KC_x in $KC_builds; do
    [[ " ${__KK_UNIT_CLASSES[$KC_u]-} " == *" $KC_x "* ]] || KC_body+=" no-build:$KC_x"
done
if [[ -n $KC_lastfn ]] && ! declare -F "$KC_lastfn" >/dev/null; then KC_body+=" no-fn:$KC_lastfn"; fi
KC_o+=" body=${KC_body// /,}"
for KC_p in "${KC_deps[@]}"; do
    IFS='|' read -r KC_dn KC_dp KC_df KC_dfile <<<"$KC_p"
    kk.uses "$KC_dn"
    KC_s=${KC_sent[$KC_dn]}
    KC_r=noreg; [[ ${__KK_UNITS[$KC_dn]-} -ef $KC_dfile ]] && KC_r=reg
    if [[ -z $KC_s ]]; then KC_r+=",nosentinel"
    elif [[ "$(declare -f "$KC_s" || :)" == "${KC_def[$KC_dn]}" ]]; then KC_r+=",1"
    else KC_r+=",rerun:$KC_s"; fi
    KC_o+=" $KC_dn=$KC_r"
done
echo "$KC_o"
EOF
        kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/mixed.sh" "$u" "$f" "$builds" "$lastfn" "${mdeps[@]}"
        kclt_expect "$u mixed: its kcl dependencies plain-sourced FIRST by the old path (kcl/$dir/../D/N.sh), then a bare source of $u under set -eu: $u registers and runs completely, no dependency loads again (a sentinel stays) and kk.uses of each is a no-op [P7, rule 8, U27]" \
            "reg body=complete$mwant"
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
