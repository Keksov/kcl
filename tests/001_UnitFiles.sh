#!/bin/bash
# UnitFiles — the FILE of every migrated kcl unit (KCL_UNITS, kcl_units.sh) has
# the unit shape of kklass/USES_PLAN.md phase U4 (pattern: kklass/uses_ledger.json
# phases.U4.pattern; §7.4, U19', U26, U40, C11):
#
#   * the two §7.4 header lines in the relative form (`../../kbool.sh`) on
#     lines 2-3, right after `#!/bin/bash`;
#   * no hand-written re-source guard (`*_<UNIT>_SOURCED`, any prefix), no
#     `<UNIT>_DIR` / `<unit>_DIR` assignment unless the row keeps a runtime copy
#     (`rundir`, C19), no hard-coded `../../kklass` / `../kkore` path, no
#     `$(cd ...)` / dirname fork, no `source` statement — dependencies come
#     through `kk.uses NAME... || return` lines;
#   * the helper namespaces: every `kk.namespace` is `kk.namespace X... || return`
#     on the code lines right after the last kk.uses line (comments may sit in
#     between); every `X.name()` / `function X.name` defined at file scope has an
#     X that is a class of the unit, the unit name or a declared namespace, and
#     the declared set is exactly the row's NAMESPACES (U40);
#   * every row has its runtime stub NNN_<UNIT>.sh and every stub a row;
#   * the lint (kkore/tests/unit_lint.sh): no file-scope `local` / `declare`
#     without -g (a unit loaded by kk.uses runs inside a function, C11);
#   * U43 for ONE row (the first): `bash -s` with the cwd in a folder holding a
#     headered stand-in <UNIT>.sh — no calling file, not interactive: the cwd is
#     never searched, kk.uses finds the kcl unit. (A script FILE caller searches
#     its own folder, never the cwd, so only a file-less caller can show this;
#     the loader rule itself is kkore 014's.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "UnitFiles" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
source "$KBOOL_ROOT/kkore/tests/unit_lint.sh"

# kclt_code FILE — KCODE: the file's code lines (not blank, not `#` lines) as
# "LINE:TEXT", in order.
kclt_code() {
    local n=0 l
    KCODE=()
    while IFS= read -r l || [[ -n $l ]]; do
        (( ++n ))
        [[ $l =~ ^[[:space:]]*(#|$) ]] && continue
        KCODE+=("$n:$l")
    done < "$1"
}

files=() rows=" "
for row in "${KCL_UNITS[@]}"; do
    kclt_row "$row"
    files+=("$KF")
    rows+="$KU "
    U=${KU^^}

    # --- 1. header and the old mechanism ---------------------------------
    kt_test_start "$KU: the §7.4 relative header on lines 2-3; no *_${U}_SOURCED guard, no ${U}_DIR / ${KU}_DIR (unless rundir), no ../../kklass or ../kkore path, no \$(cd ...) / dirname fork, no source statement [U4 rules 1-3, §7.4, U19', U26, C19]"
    bad=""
    if [[ ! -f $KF ]]; then
        bad=" no file $KF"
    else
        mapfile -t -n 3 h < "$KF"
        [[ "${h[0]}" == '#!/bin/bash' ]] || bad+=" line1='${h[0]}'"
        [[ "${h[1]}" == '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%'"$KU"'.sh}../../kbool.sh" || return' ]] \
            || bad+=" line2='${h[1]}'"
        [[ "${h[2]}" == "kk.unit $KU || return \$__kk_unit_rc" ]] || bad+=" line3='${h[2]}'"
        kclt_code "$KF"
        for c in "${KCODE[@]}"; do
            t=${c#*:}
            if [[ $t == *_${U}_SOURCED* ]]; then bad+=" guard@${c%%:*}"; fi
            if [[ " $KFL " != *" rundir "* && $t =~ (^|[^A-Za-z0-9_])(${U}|${KU})_DIR= ]]; then bad+=" ${BASH_REMATCH[2]}_DIR@${c%%:*}"; fi
            if [[ $t == *../../kklass* || $t == *../kkore* ]]; then bad+=" path@${c%%:*}"; fi
            if [[ $t == *'$(cd '* || $t =~ dirname[[:space:]]+\"?\$\{?BASH_SOURCE ]]; then bad+=" fork@${c%%:*}"; fi
            if [[ $t =~ ^[[:space:]]*(source|\.)[[:space:]] ]]; then bad+=" source@${c%%:*}"; fi
            if [[ $t =~ ^kk\.uses[[:space:]] && ! $t =~ ^kk\.uses(\ [A-Za-z_][A-Za-z0-9_]*)+\ \|\|\ return$ \
                  && ! $t =~ ^kk\.uses\ --optional(\ [A-Za-z_][A-Za-z0-9_]*)+\ \|\|\  ]]; then bad+=" uses-form@${c%%:*}"; fi
        done
    fi
    if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "${KF#$KBOOL_ROOT/}:$bad"; fi

    # --- 2. helper namespaces --------------------------------------------
    kt_test_start "$KU: kk.namespace lines are 'kk.namespace X... || return' right after the kk.uses lines; every file-scope X.name() / function X.name is a class of the unit, the unit name or a declared namespace; declared = {${KNS}} [U4 rule 4, U40]"
    bad=""
    declare -A cls=() pre=() decl=() want=()
    if [[ -f $KF ]]; then
        while IFS= read -r l || [[ -n $l ]]; do
            if [[ $l =~ ^[[:space:]]*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then cls[${BASH_REMATCH[1]}]=1; fi
            if [[ $l =~ ^[[:space:]]*(defineClass|declareClass|defineSerializableClass)[[:space:]]+\"?([A-Za-z_][A-Za-z0-9_]*) ]]; then cls[${BASH_REMATCH[2]}]=1; fi
            if [[ $l =~ ^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(\(\)|\{|$) ]]; then pre[${BASH_REMATCH[2]}]=1; fi
        done < "$KF"
        # the kk.namespace lines: their form and their place (code lines right
        # after the last kk.uses line, else right after the header)
        last=-1 first_ns=-1 nns=0
        for (( i = 0; i < ${#KCODE[@]}; i++ )); do
            t=${KCODE[i]#*:}
            [[ $t =~ ^kk\.(uses|unit)[[:space:]] ]] && last=$i
            if [[ $t == *kk.namespace* ]]; then
                if [[ $t =~ ^kk\.namespace((\ [A-Za-z_][A-Za-z0-9_]*)+)\ \|\|\ return$ ]]; then
                    for w in ${BASH_REMATCH[1]}; do decl[$w]=1; done
                else
                    bad+=" ns-form@${KCODE[i]%%:*}"
                fi
                (( first_ns < 0 )) && first_ns=$i
                (( ++nns ))
            fi
        done
        if (( nns > 0 )); then
            (( first_ns == last + 1 )) || bad+=" ns-not-after-uses@${KCODE[first_ns]%%:*}"
            for (( i = first_ns; i < first_ns + nns && i < ${#KCODE[@]}; i++ )); do
                [[ ${KCODE[i]#*:} == kk.namespace\ * ]] || bad+=" ns-not-contiguous@${KCODE[i]%%:*}"
            done
        fi
    fi
    for w in $KNS; do want[$w]=1; done
    for p in "${!pre[@]}"; do
        [[ -n ${cls[$p]+x} || $p == "$KU" || -n ${decl[$p]+x} ]] || bad+=" undeclared:$p"
    done
    for w in "${!decl[@]}"; do [[ -n ${want[$w]+x} ]] || bad+=" not-in-row:$w"; done
    for w in "${!want[@]}"; do [[ -n ${decl[$w]+x} ]] || bad+=" not-declared:$w"; done
    unset cls pre decl want
    if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "${KF#$KBOOL_ROOT/}:$bad"; fi
done

# --- 3. rows <-> runtime stubs -----------------------------------------------
kt_test_start "every row has its runtime stub NNN_<UNIT>.sh and every stub a row (${#KCL_UNITS[@]} rows)"
bad=""
declare -A stub=()
for s in "$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sh; do
    s=${s##*/}; s=${s#[0-9][0-9][0-9]_}; s=${s%.sh}
    [[ $s == UnitFiles ]] && continue
    stub[$s]=1
    [[ $rows == *" $s "* ]] || bad+=" stub-without-row:$s"
done
for r in $rows; do [[ -n ${stub[$r]+x} ]] || bad+=" row-without-stub:$r"; done
if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

# --- 4. lint -----------------------------------------------------------------
kt_test_start "lint: no file-scope 'local' / 'declare' without -g in the migrated kcl units (${#files[@]} files) [U4, C11]"
lint="$(kk_unit_lint "${files[@]}" 2>&1)"; lrc=$?
if (( lrc == 0 )) && [[ -z "$lint" ]]; then kt_test_pass "clean"; else kt_test_fail "rc=$lrc ${lint//$'\n'/ | }"; fi

# --- 5. U43 with a file-less caller (one row) ---------------------------------
kclt_row "${KCL_UNITS[0]}"
DECOY="$KCLT_TMP/decoy"
mkdir -p "$DECOY"
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
    "kk.unit $KU || return \$__kk_unit_rc" "echo DECOY-$KU" > "$DECOY/$KU.sh"
cat > "$KCLT_TMP/decoy.sh" <<'EOF'
u=$1 f=$2; set --
source "$KBOOL_ROOT/kbool.sh"
kk.uses "$u"; r=$?
[[ ${__KK_UNITS[$u]-} -ef $f ]] && echo "r=$r kcl" || echo "r=$r other:${__KK_UNITS[$u]-}"
EOF
( cd "$DECOY" && env -u KBOOL_CONFIG -u KBOOL_HOME -u USERPROFILE -u ProgramData -u PROGRAMDATA -u KK_UNIT_DIR \
    HOME="$KCLT_TMP/home" __KK_CFG_ETC="$KCLT_TMP/etc" KBOOL_ROOT="$KBOOL_ROOT" \
    "$BASH" -s "$KU" "$KF" < "$KCLT_TMP/decoy.sh" >"$KCLT_TMP/run.out" 2>"$KCLT_TMP/run.err" ); RC=$?
OUT="$(<"$KCLT_TMP/run.out")"; ERR="$(<"$KCLT_TMP/run.err")"
kclt_expect "$KU: bash -s (no calling file) with the cwd in a folder holding a headered stand-in $KU.sh: kk.uses $KU loads kcl/$KD/$KU.sh, the cwd is not searched [U43, found_in_U3]" "r=0 kcl"
