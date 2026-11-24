#!/usr/bin/env bash
# UnitFiles — the FILE of every migrated kcl unit (KCL_UNITS, kcl_units.sh) has
# the unit shape of kklass/USES_PLAN.md phase U4 (pattern: kklass/uses_ledger.json
# phases.U4.pattern; §7.4, U19', U26, U40, C11):
#
#   * the two §7.4 header lines in the relative form (`../../kbool.sh`) on
#     lines 2-3, right after `#!/bin/bash`;
#   * no hand-written re-source guard (`*_<UNIT>_SOURCED`, any prefix), no
#     `<UNIT>_DIR` / `<unit>_DIR` assignment unless the row keeps a runtime copy
#     (`rundir`, C19), no hard-coded `../../kklass` / `../kkore` path, no
#     `$(cd ...)` / dirname fork, no `source` statement (anywhere on a line,
#     also `if ! source F` / `|| . F`) — dependencies come through
#     `kk.uses NAME... || return` lines; a data file a unit reads is listed
#     by its exact statement in KCLT_DATASRC (fv.keyboard's layout tables);
#   * the helper namespaces: every `kk.namespace` is `kk.namespace X... || return`
#     on the code lines right after the last kk.uses line (comments may sit in
#     between); every `X.name()` / `function X.name` defined at file scope has an
#     X that is a class of the unit, the unit name or a declared namespace, and
#     the declared set is exactly the row's NAMESPACES (U40);
#   * every row has its runtime stub NNN_<UNIT>.sh and every stub a row;
#   * the lint (kkore/tests/unit_lint.sh): no file-scope `local` / `declare`
#     without -g (a unit loaded by kk.uses runs inside a function, C11);
#   * `kk.uses --optional X || ...` only in a row flagged `optional` (none is);
#   * dependencies: another unit's name / class / namespace referenced in a
#     unit's code lines is in that unit's kk.uses closure (U4 final review R4);
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

# `source` / `.` as a command: at the line start or after ; & | ! ( or a
# keyword (if ! source F, cond || . F)
KCLT_SRC_RE='(^|[;&|!(]|(^|[[:space:]])(if|then|do|else|elif|while|until))[[:space:]]*(source|\.)[[:space:]]'
# the data files units may source (not units: no kk.uses), by unit: the
# exact text of the statement's start. fv.keyboard's generated layout tables
# (P3 3L, tools/kbdlayout), sourced at the first need and again for the variants;
# fv.dlg's --help / --version text (P4 4b), shared with bin/fvdlg
declare -A KCLT_DATASRC=([fv.keyboard]='source "$__FV_KB_DIR/fv.keyboard.layouts.sh"'
    [fv.dlg]='source "$__FV_DL_DIR/fv.dlg.usage.sh"')

files=() rows=" "
declare -A KDEFS=()
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
        [[ "${h[0]}" == '#!/usr/bin/env bash' ]] || bad+=" line1='${h[0]}'"
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
            # a source statement anywhere on a line (also after if / ! / || / &&;
            # the header, lines 1-3, is checked above); a data file a unit reads
            # is listed in KCLT_DATASRC, by its exact source text
            if (( ${c%%:*} > 3 )) && [[ $t =~ $KCLT_SRC_RE ]] \
               && [[ -z ${KCLT_DATASRC[$KU]-} || $t != *"${KCLT_DATASRC[$KU]}"* ]]; then bad+=" source@${c%%:*}"; fi
            # a unit name may be dotted (fv.keyboard, D7)
            if [[ $t =~ ^kk\.uses[[:space:]] && ! $t =~ ^kk\.uses(\ [A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)+\ \|\|\ return$ \
                  && ! $t =~ ^kk\.uses\ --optional(\ [A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*)+\ \|\|\  ]]; then bad+=" uses-form@${c%%:*}"; fi
            # `kk.uses --optional X || <fallback>` only where the row says so
            # (flag optional; none does today) — the fallback is not checked (R5)
            if [[ $t =~ ^kk\.uses[[:space:]]+--optional && " $KFL " != *" optional "* ]]; then bad+=" optional-without-flag@${c%%:*}"; fi
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
            # a dotted unit (fv.keyboard) owns its `UNIT.*` functions (K-1)
            if [[ $KU == *.* && $l =~ ^(function[[:space:]]+)?([A-Za-z0-9_.]*) && ${BASH_REMATCH[2]} == "$KU".* ]]; then continue; fi
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
    # what this unit defines, for the dependency check (5.)
    KDEFS[$KU]="$KU $KNS ${!cls[*]}"
    unset cls pre decl want
    if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "${KF#$KBOOL_ROOT/}:$bad"; fi
done

# --- 3. rows <-> runtime stubs -----------------------------------------------
kt_test_start "every row has its runtime stub NNN_<UNIT>.sh and every stub a row (${#KCL_UNITS[@]} rows)"
bad=""
declare -A stub=()
for s in "$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sh; do
    s=${s##*/}
    # 0NN_*: repo-wide checks (this file, 002_Bash51Hazards), not unit stubs
    [[ $s == 0* ]] && continue
    s=${s#[0-9][0-9][0-9]_}; s=${s%.sh}
    stub[$s]=1
    [[ $rows == *" $s "* ]] || bad+=" stub-without-row:$s"
done
for r in $rows; do [[ -n ${stub[$r]+x} ]] || bad+=" row-without-stub:$r"; done
if [[ -z "$bad" ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

# --- 4. lint -----------------------------------------------------------------
kt_test_start "lint: no file-scope 'local' / 'declare' without -g in the migrated kcl units (${#files[@]} files) [U4, C11]"
lint="$(kk_unit_lint "${files[@]}" 2>&1)"; lrc=$?
if (( lrc == 0 )) && [[ -z "$lint" ]]; then kt_test_pass "clean"; else kt_test_fail "rc=$lrc ${lint//$'\n'/ | }"; fi

# --- 5. dependency completeness ------------------------------------------------
# Every OTHER unit's namespace a unit's code refers to — `P.name` on a code line
# (not a `#` line) or the parent of `class X : P`, where P is a unit name, a
# class or a row namespace of another row — must come through the unit's own
# kk.uses closure (its kk.uses names, transitively over the table; a namespace
# several units define, ths, through any of them). A deleted `kk.uses tpath`
# in tfile.sh or a `tstopwatch` dropped from thttpserver's line would otherwise
# stay green: every once/name check loads the unit with whatever the process
# already holds (U4 final review R4, critic_u4 C2 / xref.sh). One awk over all
# files lists the (file, prefix) references.
kt_test_start "dependencies: every other unit's class / unit name / namespace referenced in a unit's code lines (P.name, class X : P) is in that unit's kk.uses closure (${#KCL_UNITS[@]} rows) [U4 final review R4, critic_u4 C2]"
cat > "$KCLT_TMP/xref.awk" <<'EOF'
FNR == 1 { delete seen }
/^[ \t]*#/ { next }
{
    l = $0
    if (match(l, /^[ \t]*class[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
        p = substr(l, RSTART, RLENGTH); sub(/.*:[ \t]*/, "", p)
        if (!((FILENAME, p) in seen)) { seen[FILENAME, p] = 1; print FILENAME "\t" p }
    }
    l = " " l
    # a dotted chain a.b.c names the prefixes a and a.b (a dotted unit,
    # fv.keyboard.getKeyEvent -> fv.keyboard); a.b names a, as before
    while (match(l, /[^A-Za-z0-9_.][A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+/)) {
        n = split(substr(l, RSTART + 1, RLENGTH - 1), w, ".")
        l = substr(l, RSTART + RLENGTH)
        p = ""
        for (k = 1; k < n; k++) {
            p = (k == 1) ? w[1] : p "." w[k]
            if (!((FILENAME, p) in seen)) { seen[FILENAME, p] = 1; print FILENAME "\t" p }
        }
    }
}
EOF
declare -A KBY=() KDEP=() KUNIT_OF=()
for row in "${KCL_UNITS[@]}"; do
    kclt_row "$row"
    KUNIT_OF[$KF]=$KU
    for w in ${KDEFS[$KU]-}; do [[ ${KBY[$w]-} == *" $KU "* ]] || KBY[$w]+=" $KU "; done
    kclt_uses "$KF"
    KDEP[$KU]="${KUSES[*]}"
done
# kclt_closure U -> KCLOS: " U d1 d2 ... " (U and its kk.uses names, transitively)
kclt_closure() {
    local q=("$1") x d
    KCLOS=" "
    while (( ${#q[@]} )); do
        x=${q[0]}; q=("${q[@]:1}")
        [[ $KCLOS == *" $x "* ]] && continue
        KCLOS+="$x "
        for d in ${KDEP[$x]-}; do q+=("$d"); done
    done
}
bad="" nx=0
xr="$(awk -f "$KCLT_TMP/xref.awk" "${files[@]}" 2>&1)"; xrc=$?
(( xrc == 0 )) || bad+=" awk-rc=$xrc:${xr//$'\n'/|}"
while IFS=$'\t' read -r f p; do
    [[ -n $f && -n ${KBY[$p]+x} ]] || continue
    u=${KUNIT_OF[$f]-}
    [[ -n $u && ${KBY[$p]} != *" $u "* ]] || continue
    kclt_closure "$u"; (( ++nx ))
    ok=""
    for v in ${KBY[$p]}; do [[ $KCLOS == *" $v "* ]] && ok=1; done
    if [[ -z $ok ]]; then vs=(${KBY[$p]}); bad+=" $u:$p(of ${vs[*]})"; fi
done <<<"$xr"
if [[ -z "$bad" ]]; then kt_test_pass "ok ($nx cross-unit references)"; else kt_test_fail "not in the kk.uses closure:$bad"; fi

# --- 6. U43 with a file-less caller (one row) ---------------------------------
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
# kclt_run: the same hermetic environment as every runtime check (no
# VERBOSE_KKLASS / KKLASS_CKK_DIR / BASH_ENV from the caller — R6)
kclt_run "$DECOY" -s "$KU" "$KF" < "$KCLT_TMP/decoy.sh"
kclt_expect "$KU: bash -s (no calling file) with the cwd in a folder holding a headered stand-in $KU.sh: kk.uses $KU loads kcl/$KD/$KU.sh, the cwd is not searched [U43, found_in_U3]" "r=0 kcl"

# --- 7. settings hooks lint (kklass/docs/dev/IMAGE_PLAN.md §5.5, image I1a) ---
# The rules R1-R5 and the scan: kcl/tests/hook_lint.sh (kclt_hooklint).
source "$SCRIPT_DIR/hook_lint.sh"

kt_test_start "settings hooks lint over the ${#files[@]} unit files + kklass/kklass.sh: on a load-time line outside a kk.settings hook no public self-default / :+ / preset guard / -v test / \${!X} / append, locale read or export, PATH probe, \$\$ / \$BASHPID, clock or random value, terminal test, environment name (R1), no write of a VAR another unit lists (R2), no expansion of a VAR any unit lists (R5); every hook ends with 'return 0' or an assignment (R3); the ${#KCLT_HOOK_PENDING[@]} files not hooked yet are on KCLT_HOOK_PENDING, each existing and without kk.settings (R4; image I1b empties it) [IMAGE_PLAN §5.5]"
lint="$(kclt_hooklint "${files[@]}" "$KBOOL_ROOT/kklass/kklass.sh" 2>&1)"
bad=""
for r in "${KCLT_HOOK_PENDING[@]}"; do [[ -f $KBOOL_ROOT/$r ]] || bad+=" pending-without-file:$r"; done
if [[ -z "$lint$bad" ]]; then kt_test_pass "clean"; else kt_test_fail "${lint//$'\n'/ | }$bad"; fi

# the lint fails on a fixture for each rule (fixture files under KCLT_TMP)
FXL="$KCLT_TMP/hooklint"
mkdir -p "$FXL"
cat > "$FXL/fxr1.sh" <<'EOF'
#!/usr/bin/env bash
kk.unit fxr1 || return $__kk_unit_rc
fxr1._settings() {
    declare -g FXR1_OK=${FXR1_OK:-1}
    kk.localeDefault
    return 0
}
kk.settings fxr1._settings FXR1_OK LC_CTYPE || return
fxr1._init() {
    local n=${1:-0} m
    m=${n:-2}
    declare -g FXR1_RUN=${FXR1_RUN:-3}
}
declare -g FXR1_A=${FXR1_A:-1}
: "${FXR1_B:=2}"
if [[ -z ${FXR1_C[*]+x} ]]; then FXR1_C=(c); fi
FXR1_D+=(d)
v=${LANG-}
export LC_CTYPE=C.UTF-8
kk.localeDefault
p=$(command -v cp)
fxr1_pid=$$
fxr1_bpid=$BASHPID
fxr1._init
if [[ -z ${FXR1_RO+x} || ${FXR1_RO@a} != *r* ]]; then FXR1_RO=1; readonly FXR1_RO; fi
declare -g __FXR1_INT=${__FXR1_INT:-0}
EOF
cat > "$FXL/fxown.sh" <<'EOF'
#!/usr/bin/env bash
kk.unit fxown || return $__kk_unit_rc
fxown._settings() {
    if [[ -z ${FXOWN_REG[*]+x} ]]; then declare -ga FXOWN_REG=(a); fi
    return 0
}
kk.settings fxown._settings FXOWN_REG || return
EOF
cat > "$FXL/fxr2.sh" <<'EOF'
#!/usr/bin/env bash
kk.unit fxr2 || return $__kk_unit_rc
kk.uses fxown || return
FXOWN_REG[1]=b
fxr2._settings() {
    [[ " ${FXOWN_REG[*]} " == *" c "* ]] || FXOWN_REG+=(c)
    return 0
}
kk.settings fxr2._settings FXOWN_REG || return
EOF
cat > "$FXL/fxr3.sh" <<'EOF'
#!/usr/bin/env bash
kk.unit fxr3 || return $__kk_unit_rc
fxr3._a() {
    declare -g FXR3_X=${FXR3_X-}
    [[ -n ${FXR3_X} ]] && FXR3_Y=1
}
fxr3._b() { declare -g FXR3_Z=${FXR3_Z:-1}; }
fxr3._c() { declare -g FXR3_W=${FXR3_W:-1}; kk.localeDefault; }
fxr3._d() {
    declare -g FXR3_V=${FXR3_V:-1}
    return 0
}
fxr3._f() {
    FXR3_S=$(fxr3._probe)
}
fxr3._g() {
    declare -g FXR3_G1=1 FXR3_G2=2
}
fxr3._h() {
    declare -ga FXR3_H
}
kk.settings fxr3._a FXR3_X FXR3_Y || return
kk.settings fxr3._b FXR3_Z || return
kk.settings fxr3._c FXR3_W LC_CTYPE || return
kk.settings fxr3._d FXR3_V || return
kk.settings fxr3._e FXR3_U || return
kk.settings fxr3._f FXR3_S || return
kk.settings fxr3._g FXR3_G1 FXR3_G2 || return
kk.settings fxr3._h FXR3_H || return
EOF
# R1's newer sub-rules, R5, and the scan's scoping (calls after && { $( ;
# a ( ) body; a brace on the next line; here-documents; quoted text)
cat > "$FXL/fxr5.sh" <<'EOF'
#!/usr/bin/env bash
kk.unit fxr5 || return $__kk_unit_rc
fxr5._settings() {
    declare -g FXR5_W=${FXR5_W:-80}
    return 0
}
kk.settings fxr5._settings FXR5_W || return
declare -g __FXR5_HALF=$(( FXR5_W / 2 ))
declare -g __FXR5_COPY="$FXR5_W"
declare -g __FXR5_H=${FXR5_HEIGHT:+set}
if [[ -v FXR5_MODE ]]; then declare -g __FXR5_M=1; fi
declare -g __FXR5_HOME=$HOME __FXR5_TERM=$TERM
declare -g __FXR5_T0=$EPOCHSECONDS __FXR5_R=$RANDOM
if [[ -t 1 ]]; then declare -g __FXR5_TTY=1; fi
printf -v __FXR5_NOW '%(%s)T' -1
declare -g __FXR5_IND=${!FXR5_REF}
fxr5._p2() {
    declare -g FXR5_P2=${FXR5_P2:-2}
}
fxr5._p3() {
    declare -g FXR5_P3=${FXR5_P3:-3}
}
fxr5._p4() {
    declare -g FXR5_P4=${FXR5_P4:-4}
}
[[ -n ${BASH_VERSION} ]] && fxr5._p2
{ fxr5._p3; }
x=$(fxr5._p4)
fxr5._p6()
{
    declare -g FXR5_P6=${FXR5_P6:-6}
}
fxr5._p6
fxr5._p7() (
    declare -g FXR5_P7=${FXR5_P7:-7}
)
declare -g FXR5_AFTER=${FXR5_AFTER:-8}
cat <<EOF2 >/dev/null
}
EOF2
fxr5._p8() {
    cat <<EOF3
}
EOF3
    declare -g FXR5_P8=${FXR5_P8:-8}
}
fxr5._p8
trap 'echo "${FXR5_TRAP:-x}"' EXIT
cat <<'EOF4' >/dev/null
${FXR5_DOC:-literal}
EOF4
fxr5_text='
${FXR5_INSTR:-literal}
'
declare -g FXR5_LAST=${FXR5_LAST:-9}  # don't
EOF
lint="$(kclt_hooklint "$FXL/fxr1.sh" "$FXL/fxown.sh" "$FXL/fxr2.sh" "$FXL/fxr3.sh" "$FXL/fxr5.sh" 2>&1)"
lint=${lint//"$FXL/"/}; lint=${lint//"${FXL#"$KBOOL_ROOT"/}/"/}
want="fxr1.sh:14: R1: self-default:FXR1_A
fxr1.sh:15: R1: self-default:FXR1_B
fxr1.sh:16: R1: guard:FXR1_C
fxr1.sh:17: R1: append:FXR1_D
fxr1.sh:18: R1: locale-read:LANG
fxr1.sh:19: R1: locale-export:LC_CTYPE
fxr1.sh:19: R2: writes LC_CTYPE, listed by $FXL/fxr3.sh's kk.settings
fxr1.sh:20: R1: locale-export:kk.localeDefault
fxr1.sh:21: R1: path-probe:command
fxr1.sh:22: R1: pid
fxr1.sh:23: R1: pid
fxr1.sh:12: R1: self-default:FXR1_RUN (in fxr1._init, run at load)
fxr2.sh:4: R2: writes FXOWN_REG, listed by $FXL/fxown.sh's kk.settings
fxr3.sh:6: R3: hook fxr3._a ends with '[[ -n \${FXR3_X} ]] && FXR3_Y=1', not 'return 0' or an assignment
fxr3.sh:8: R3: hook fxr3._c ends with 'kk.localeDefault', not 'return 0' or an assignment
fxr3.sh:1: R3: hook fxr3._e is not a file-scope function of this file
fxr3.sh:15: R3: hook fxr3._f ends with 'FXR3_S=\$(fxr3._probe)', not 'return 0' or an assignment
fxr5.sh:8: R5: reads FXR5_W (listed by a kk.settings)
fxr5.sh:9: R5: reads FXR5_W (listed by a kk.settings)
fxr5.sh:10: R1: alt:FXR5_HEIGHT
fxr5.sh:11: R1: is-set:FXR5_MODE
fxr5.sh:12: R1: env:HOME env:TERM
fxr5.sh:13: R1: volatile:EPOCHSECONDS volatile:RANDOM
fxr5.sh:14: R1: tty
fxr5.sh:15: R1: time
fxr5.sh:16: R1: indirect:FXR5_REF
fxr5.sh:37: R1: self-default:FXR5_AFTER
fxr5.sh:55: R1: self-default:FXR5_LAST
fxr5.sh:18: R1: self-default:FXR5_P2 (in fxr5._p2, run at load)
fxr5.sh:21: R1: self-default:FXR5_P3 (in fxr5._p3, run at load)
fxr5.sh:24: R1: self-default:FXR5_P4 (in fxr5._p4, run at load)
fxr5.sh:31: R1: self-default:FXR5_P6 (in fxr5._p6, run at load)
fxr5.sh:45: R1: self-default:FXR5_P8 (in fxr5._p8, run at load)"
want=${want//"$FXL/"/}
kt_test_start "settings hooks lint fixtures: each rule fails where it should — R1 (self-defaults :- / := also in a function run at load — called after && / { / \$( / a brace on the next line / past here-documents —, :+, a preset guard, -v, \${!X}, an append, a locale read and export, kk.localeDefault, command -v, \$\$, \$BASHPID, \$EPOCHSECONDS / \$RANDOM, printf %()T, [[ -t, \$HOME / \$TERM; not in a hook body, a readonly reload guard, an internal __ default, a local, single-quoted text, a here-document, a multi-line string, a ( ) body not run), R2 (a load-time write of another unit's hook VAR; not the owner's own), R3 (a hook ending with '&& Y=1', a command or X=\$(...), a hook not defined; not 'return 0', an assignment, declare -g A=1 B=2, declare -ga X, a one-line body ending in one), R5 (a value derived from a listed VAR, \$(( )) and \"\$X\") [IMAGE_PLAN §5.5]"
if [[ "$lint" == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got='${lint//$'\n'/ | }' want='${want//$'\n'/ | }'"; fi

# R4: a pending file that has a hook must leave the list
lint="$(KCLT_HOOK_PENDING=("$FXL/fxown.sh"); kclt_hooklint "$FXL/fxown.sh" 2>&1)"
lint=${lint//"$FXL/"/}; lint=${lint//"${FXL#"$KBOOL_ROOT"/}/"/}
kt_test_start "settings hooks lint R4: a file on KCLT_HOOK_PENDING that has a kk.settings line is reported (a hooked unit leaves the list) [IMAGE_PLAN §5.5]"
if [[ "$lint" == "fxown.sh:1: R4: on KCLT_HOOK_PENDING but has kk.settings (hooked: remove it from the list)" ]]; then kt_test_pass "ok"; else kt_test_fail "got='${lint//$'\n'/ | }'"; fi
