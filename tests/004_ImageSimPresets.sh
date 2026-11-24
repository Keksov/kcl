#!/usr/bin/env bash
# ImageSimPresets — the settings hooks of the fv units under caller presets
# (kklass/docs/dev/IMAGE_PLAN.md §5, image stage I1a):
#   * the simulated image start (kcl/tests/image_sim.sh) of each fv unit alone
#     under (c) FV_* presets in the environment, LANG=ru_RU.UTF-8 and the
#     array presets FV_MSGBOX_TITLES / FV_DLG_TAGS set before the load;
#   * a normal load of all of them (fv.dlg fv.msgbox): every public VAR a hook
#     sets keeps its default when unset and a caller's preset when set (the
#     move into the hooks changed no behaviour);
#   * the harness's negative fixtures, which must FAIL it: a unit whose load
#     (outside its hook) writes another unit's hook VAR (the H1 registry
#     case), a hook that is not idempotent (appends twice), a hook that sets
#     a variable it does not list (also LC_CTYPE through kk.localeDefault,
#     I1b); and a well-formed pair that passes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageSimPresets" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup

KCLT_SIM_UNITS=(fv.keyboard fv.mouse fv.video fv.drivers fv.views fv.app fv.histlist fv.dialogs fv.msgbox fv.dlg)

cat > "$KCLT_TMP/sim.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
source "$KCL_DIR/tests/image_sim.sh" || exit 2
if [[ -n ${KCLT_SIM_PRE-} ]]; then eval "$KCLT_SIM_PRE"; fi
KCLT_SIM_DIR=$KCLT_TMP/sim.$BASHPID
kclt_sim "$@"
EOF

# the public scalars the fv hooks set, with their defaults ('' = empty);
# FV_VIDEO_ASCII is decided by the load (FV_ASCII, the locale), not preset
KCLT_PUB=(FV_KEY_FD=0 FV_SCREEN_W=80 FV_SCREEN_H=24 FV_VIDEO_ON=0 FV_VIDEO_RESIZED=0
    FV_TTY_FD= FV_VIDEO_COLORS=256 FV_VIDEO_OUT_FD= FV_HISTORY_SIZE=65536
    FV_MINWINSIZE_X=16 FV_MINWINSIZE_Y=6 FV_DRAW_VIEW= FV_DRAW_X=0 FV_DRAW_Y=0 FV_DRAW_PAL=
    FV_CLIP_X1=0 FV_CLIP_Y1=0 FV_CLIP_X2=0 FV_CLIP_Y2=0 FV_COMMANDSETCHANGED=0
    FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=0 FV_RECT_BY=0 FV_POINT_X=0 FV_POINT_Y=0
    FV_MIN_X=0 FV_MIN_Y=0 FV_MAX_X=0 FV_MAX_Y=0
    FV_APP= FV_DESKTOP= FV_STATUSLINE= FV_MENUBAR= FV_CLIPBOARD= FV_DLG_CMD=)
# (c): every one of them preset (101, 102, ...), the locale and the arrays
KCLT_PRESET=(LANG=ru_RU.UTF-8 FV_ASCII=1 __FV_VW_OWNER=4242)
i=100
for p in "${KCLT_PUB[@]}"; do (( ++i )); KCLT_PRESET+=("${p%%=*}=$i"); done
KCLT_ARRPRE="FV_MSGBOX_TITLES=(T0 'T 1' T2 T3); FV_MSGBOX_BUTTONS=(B0 B1 B2 B3 B4 B5); FV_DLG_TAGS=(t1 't 2')"

KCLT_SIM_PRE=$KCLT_ARRPRE
for u in "${KCLT_SIM_UNITS[@]}"; do
    kclt_simrun "${KCLT_PRESET[@]}" -- "$KCLT_TMP/sim.sh" "$u"
    kclt_expect "$u, FV_* presets + LANG=ru_RU.UTF-8 + array presets: the simulated image start equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1a]" "sim:ok"
done
KCLT_SIM_PRE=""

# --- presets win, defaults are set (a normal load of every fv unit) ---------
cat > "$KCLT_TMP/vals.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
if [[ -n ${KCLT_SIM_PRE-} ]]; then eval "$KCLT_SIM_PRE"; fi
kk.uses fv.dlg fv.msgbox || { echo "load rc=$?"; exit 1; }
for n in "$@"; do printf '%s=%s\n' "$n" "${!n-<unset>}"; done
for n in FV_MSGBOX_TITLES FV_MSGBOX_BUTTONS FV_DLG_TAGS; do
    eval "x=(\"\${$n[@]}\")"
    printf '%s=(%s)\n' "$n" "${x[*]@Q}"
done
o=$__FV_VW_OWNER; [[ $o == "$BASHPID" ]] && o=pid
a=bad; [[ $FV_VIDEO_ASCII == 1 || ( $FV_VIDEO_ASCII == 0 && -n $__FV_VS_LOC ) ]] && a=$FV_VIDEO_ASCII
x=-; [[ ${LC_CTYPE@a} == *x* ]] && x=x
printf 'owner=%s ascii=%s kbloc=%s lc_ctype=%s%s\n' "$o" "$a" "$__FV_KB_LOC" "${LC_CTYPE-<unset>}" "$x"
EOF
names=() wdef="" wpre="" i=100
for p in "${KCLT_PUB[@]}"; do
    (( ++i ))
    names+=("${p%%=*}")
    wdef+="$p"$'\n'
    wpre+="${p%%=*}=$i"$'\n'
done
wdef+="FV_MSGBOX_TITLES=('Warning' 'Error' 'Information' 'Confirm')
FV_MSGBOX_BUTTONS=('~Y~es' '~N~o' 'O~k~' 'Cancel' 'O~K~' 'Cancel')
FV_DLG_TAGS=()
owner=pid ascii=0 kbloc= lc_ctype=C.UTF-8x"
wpre+="FV_MSGBOX_TITLES=('T0' 'T 1' 'T2' 'T3')
FV_MSGBOX_BUTTONS=('B0' 'B1' 'B2' 'B3' 'B4' 'B5')
FV_DLG_TAGS=('t1' 't 2')
owner=4242 ascii=1 kbloc=ru lc_ctype=<unset>-"
# (a stray FV_* and LC_ALL in the test process's environment must not reach
# the child: kclt_simrun clears them — I1a critic L12)
KCLT_LCALL=${LC_ALL-}
export FV_SCREEN_W=99 FV_CLIPBOARD=stray LC_ALL=C
kclt_simrun -- "$KCLT_TMP/vals.sh" "${names[@]}"
unset FV_SCREEN_W FV_CLIPBOARD
if [[ -n $KCLT_LCALL ]]; then export LC_ALL=$KCLT_LCALL; else unset LC_ALL; fi
kclt_expect "fv.dlg + fv.msgbox, nothing preset (a stray FV_SCREEN_W / FV_CLIPBOARD / LC_ALL of the test process cleared), no locale: every public VAR of the fv hooks has its default (${#KCLT_PUB[@]} scalars, FV_MSGBOX_TITLES / _BUTTONS, FV_DLG_TAGS), __FV_VW_OWNER is the loading shell, LC_CTYPE=C.UTF-8 exported, no layout from the locale [IMAGE_PLAN §5, I1a: no behaviour change]" "${wdef%$'\n'}"
KCLT_SIM_PRE=$KCLT_ARRPRE
kclt_simrun "${KCLT_PRESET[@]}" -- "$KCLT_TMP/vals.sh" "${names[@]}"
KCLT_SIM_PRE=""
kclt_expect "fv.dlg + fv.msgbox, every public VAR preset (env scalars, arrays before the load), LANG=ru_RU.UTF-8, FV_ASCII=1: every preset wins, FV_VIDEO_ASCII=1, the ru layout, LC_CTYPE left unset [IMAGE_PLAN §5, I1a: no behaviour change]" "${wpre%$'\n'}"

# --- the harness's negative fixtures ------------------------------------------
FX="$KCLT_TMP/simfx"
mkdir -p "$FX"
H='[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2'
# kclt_fx NAME BODY-LINE... — a fixture unit NAME.sh: the header lines, then the body
kclt_fx() {
    local n=$1; shift
    printf '%s\n' "$H" "kk.unit $n || return \$__kk_unit_rc" "$@" > "$FX/$n.sh"
}
kclt_fx fxreg 'fxreg._settings() {' '    if [[ -z ${FXREG_LIST[*]+x} ]]; then declare -ga FXREG_LIST=(a); fi' '    return 0' '}' \
    'kk.settings fxreg._settings FXREG_LIST || return'
kclt_fx fxh1 'kk.uses fxreg || return' 'FXREG_LIST+=(h1)'
kclt_fx fxdup 'kk.uses fxreg || return' 'fxdup._settings() {' '    FXREG_LIST+=(dup)' '    return 0' '}' \
    'kk.settings fxdup._settings FXREG_LIST || return'
kclt_fx fxunl 'fxunl._settings() {' '    declare -g FXUNL_MODE=${FXUNL_ENV:-plain}' '    return 0' '}' 'kk.settings fxunl._settings || return'
kclt_fx fxgood 'kk.uses fxreg || return' 'fxgood._settings() {' \
    '    [[ " ${FXREG_LIST[*]} " == *" good "* ]] || FXREG_LIST+=(good)' '    return 0' '}' \
    'kk.settings fxgood._settings FXREG_LIST || return'
# (I1a critic: load-only context, a state the load sets after its hook)
kclt_fx fxdir 'fxdir._settings() {' '    declare -g FXDIR_D=${KK_UNIT_DIR-}/data' '    return 0' '}' 'kk.settings fxdir._settings FXDIR_D || return'
kclt_fx fxkloc 'fxkloc._settings() {' '    declare -g FXKLOC_U=${__kk_u-none}' '    return 0' '}' 'kk.settings fxkloc._settings FXKLOC_U || return'
kclt_fx fxlocal 'local fxlocal_seed=7' 'fxlocal._settings() {' '    declare -g FXLOCAL_S=${fxlocal_seed-}' '    return 0' '}' \
    'kk.settings fxlocal._settings FXLOCAL_S || return'
kclt_fx fxlater 'fxlater._settings() {' '    declare -g FXLATER_V=${__FXLATER_SEEN:-first}' '    return 0' '}' \
    'kk.settings fxlater._settings FXLATER_V || return' 'declare -g __FXLATER_SEEN=second'
# (I1a critic: unlisted writes the static scan cannot see, a temporary
# environment it must not count)
kclt_fx fxprv 'fxprv._set() { printf -v "$1" %s "$2"; }' 'fxprv._settings() {' '    fxprv._set FXPRV_V "${FXPRV_V:-dflt}"' \
    '    return 0' '}' 'kk.settings fxprv._settings || return'
kclt_fx fxmap 'fxmap._settings() {' '    [[ -n ${FXMAP_L[*]+x} ]] || mapfile -t FXMAP_L <<< "a"' '    return 0' '}' 'kk.settings fxmap._settings || return'
kclt_fx fxnref 'fxnref._settings() {' '    declare -n __fxr=FXNREF_V' '    __fxr=${__fxr:-d}' '    return 0' '}' 'kk.settings fxnref._settings || return'
kclt_fx fxind 'fxind._h() { declare -g FXIND_V=${FXIND_V:-d}; }' 'fxind._settings() {' '    local f=fxind._h' '    "$f"' '    return 0' '}' \
    'kk.settings fxind._settings || return'
kclt_fx fxread 'fxread._settings() {' '    IFS=, read -r FXREAD_A FXREAD_B <<< "${FXREAD_A:-x},y"' '    return 0' '}' 'kk.settings fxread._settings || return'
# (I1a critic: shell state, a pid-valued constant, a readonly hook VAR, attributes)
kclt_fx fxtrap 'fxtrap._settings() {' '    trap ":" USR1' '    alias fxtrap_al=true' '    return 0' '}' 'kk.settings fxtrap._settings || return'
kclt_fx fxpid 'fxpid._settings() {' '    declare -g FXPID_N=${FXPID_N:-256}' '    return 0' '}' 'kk.settings fxpid._settings FXPID_N || return'
kclt_fx fxro 'fxro._settings() {' '    declare -g FXRO_V=${FXRO_V:-1}' '    return 0' '}' 'kk.settings fxro._settings FXRO_V || return' 'readonly FXRO_V'
kclt_fx fxattr 'fxattr._settings() {' '    declare -g FXATTR_V=${FXATTR_V:-1}' '    return 0' '}' 'kk.settings fxattr._settings FXATTR_V || return'

# kclt_fxrun FIXTURE [PRE] — the harness on one fixture unit (PRE: shell text
# eval'd before the load)
kclt_fxrun() {
    KCLT_SIM_PRE=${2-}
    kclt_simrun -- "$KCLT_TMP/sim.sh" "$FX/$1.sh"
    KCLT_SIM_PRE=""
}
# kclt_fxfirst TITLE WANT-PREFIX — rc 1, stderr empty, the first line starts with WANT-PREFIX
kclt_fxfirst() {
    kt_test_start "$1"
    if (( RC == 1 )) && [[ ${OUT%%$'\n'*} == "$2"* && -z $ERR ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out='${OUT//$'\n'/ | }' err='$ERR'"; fi
}

kclt_fxrun fxh1
kclt_fxfirst "harness negative fixture (H1): a unit whose load, outside its hook, appends to another unit's hook VAR fails the simulation, naming the VAR [IMAGE_PLAN §5.2, R H1]" "sim:diff V:FXREG_LIST "

kclt_fxrun fxdup
kt_test_start "harness negative fixture: a hook that appends to its listed registry without checking for its entry (not idempotent) fails the second run [IMAGE_PLAN §5.2, kkore 'Writing a hook']"
if (( RC == 1 )) && [[ $OUT == "sim:rerun V:FXREG_LIST "*'[2]="dup"'* && -z $ERR ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$RC out='${OUT//$'\n'/ | }' err='$ERR'"; fi

kclt_fxrun fxunl
kclt_expect "harness negative fixture: a hook that sets a variable it does not list fails, statically and in the dynamic probe, naming the hook and the variable [IMAGE_PLAN §5.2]" \
    "sim:unlisted fxunl._settings FXUNL_MODE"$'\n'"sim:unlisted-dyn fxunl._settings FXUNL_MODE"
kt_test_start "the same: rc 1"
if (( RC == 1 )); then kt_test_pass "ok"; else kt_test_fail "rc=$RC"; fi

for f in fxdir:FXDIR_D fxkloc:FXKLOC_U fxlocal:FXLOCAL_S fxlater:FXLATER_V; do
    kclt_fxrun "${f%%:*}"
    kclt_fxfirst "harness negative fixture ${f%%:*}: a hook that reads load-only context (KK_UNIT_DIR, kk.settings' own local, a file-scope local) or a state the load sets after it gives another value outside the load: the simulation names ${f#*:} [IMAGE_PLAN §5.2, kkore 'Writing a hook', I1a critic L6]" "sim:diff V:${f#*:} "
done

kclt_fxrun fxprv
kclt_expect "harness negative fixture fxprv: a hook writing an unlisted variable through a helper's printf -v \"\$1\" is caught by the dynamic probe [IMAGE_PLAN §5.2, I1a critic M3]" "sim:unlisted-dyn fxprv._settings FXPRV_V"
kclt_fxrun fxnref
kclt_expect "harness negative fixture fxnref: a hook writing an unlisted variable through a nameref is caught by the dynamic probe [I1a critic M3]" "sim:unlisted-dyn fxnref._settings FXNREF_V"
kclt_fxrun fxind
kclt_expect "harness negative fixture fxind: a hook calling its writer through \"\$f\" is caught by the dynamic probe [I1a critic M3]" "sim:unlisted-dyn fxind._settings FXIND_V"
kclt_fxrun fxmap
kclt_expect "harness negative fixture fxmap: a hook filling an unlisted array by mapfile is caught (mapfile's name operand; the dynamic probe) [I1a critic M3]" \
    "sim:unlisted fxmap._settings FXMAP_L"$'\n'"sim:unlisted-dyn fxmap._settings FXMAP_L"
kclt_fxrun fxread
kclt_expect "harness negative fixture fxread: \`IFS=, read -r A B\` reports A and B (read's name operands), not the temporary IFS [I1a critic M3]" \
    "sim:unlisted fxread._settings FXREAD_A"$'\n'"sim:unlisted fxread._settings FXREAD_B"$'\n'"sim:unlisted-dyn fxread._settings FXREAD_A"$'\n'"sim:unlisted-dyn fxread._settings FXREAD_B"

kclt_fxrun fxtrap
kclt_fxfirst "harness negative fixture fxtrap: a load that sets a trap and an alias fails (sim:shell-state; an image never holds traps / aliases / umask / options, plan §4, §6.3) [I1a critic L2]" "sim:shell-state trap alias"

kclt_fxrun fxro
kclt_fxfirst "harness negative fixture fxro: a hook VAR made readonly by the load cannot be put back: sim:readonly [I1a critic L6]" "sim:readonly FXRO_V"

kclt_fxrun fxpid 'FXPID_N=$BASHPID'
kclt_expect "harness control fixture fxpid: a hook VAR whose preset value happens to equal the loader's pid is compared as it is (the pid pair rule: loader pid at the end AND the subshell's pid in the simulation) [I1a critic L1]" "sim:ok"

kclt_fxrun fxattr 'declare -ix FXATTR_V=5'
kclt_expect "harness control fixture fxattr: a hook VAR preset with attributes (-ix) is put back with them [IMAGE_PLAN §5.2]" "sim:ok"

kclt_fxrun fxgood
kclt_expect "harness control fixture: a unit that appends to another unit's registry in its own hook, listing the VAR and checking for its entry, passes [IMAGE_PLAN §5.2, §5.4 tawk / tfind / tsed pattern]" "sim:ok"

# (I1b critic L1) a hook that calls kk.localeDefault without listing LC_CTYPE,
# loaded with a unit that lists it (the dynamic probe skips a listed VAR; the
# static scan counts kk.localeDefault as a write of LC_CTYPE)
kclt_fx fxlocown 'fxlocown._settings() {' '    kk.localeDefault' '    return 0' '}' 'kk.settings fxlocown._settings LC_CTYPE || return'
kclt_fx fxloc 'kk.uses fxlocown || return' 'fxloc._settings() {' '    kk.localeDefault' '    return 0' '}' 'kk.settings fxloc._settings || return'
kclt_fxrun fxloc
kclt_expect "harness negative fixture fxloc: a hook calling kk.localeDefault without listing LC_CTYPE fails (statically: kk.localeDefault writes LC_CTYPE), also when another unit of the load lists LC_CTYPE [IMAGE_PLAN §5.2, I1b critic L1]" "sim:unlisted fxloc._settings LC_CTYPE"
kt_test_start "the same: rc 1"
if (( RC == 1 )); then kt_test_pass "ok"; else kt_test_fail "rc=$RC"; fi

kclt_fx fxnr 'fxnr._settings() {' '    declare -g FXNR_V=${FXNR_V:-d}' '    return 0' '}' 'kk.settings fxnr._settings FXNR_V || return'
kclt_fxrun fxnr 'declare -n FXNR_V=FXNR_T; FXNR_T=t'
kclt_expect "harness control fixture fxnr: a hook VAR that the caller made a nameref is put back with unset -n (its target keeps its value) [I1a critic L8]" "sim:ok"
