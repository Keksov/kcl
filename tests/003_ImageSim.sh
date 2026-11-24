#!/usr/bin/env bash
# ImageSim — the simulated image start (kklass/docs/dev/IMAGE_PLAN.md §5.2,
# the subshell form; helper kcl/tests/image_sim.sh) over every kcl unit that
# has its settings hooks (image stage I1a: the fv units; I1b adds the rest):
# each unit ALONE in a fresh hermetic bash (no prior set) — fv.dlg pulls the
# whole fv closure but fv.msgbox —, under (a) no locale variable at all and
# (b) LANG=C.UTF-8: after the load, the hook VARs put back to their state
# before it and every hook run in load order (and once more) leave exactly
# the end-of-load state, and every variable a hook assigns is one its unit
# lists; and the same for two units under a caller with set -eu, and with
# nocasematch + extglob under set -u. The FV_* presets case, the preset /
# default checks of every public
# VAR and the harness's negative fixtures are 004_ImageSimPresets.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageSim" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup

# the units with settings hooks (image I1a)
KCLT_SIM_UNITS=(fv.keyboard fv.mouse fv.video fv.drivers fv.views fv.app fv.histlist fv.dialogs fv.msgbox fv.dlg)

cat > "$KCLT_TMP/sim.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
source "$KCL_DIR/tests/image_sim.sh" || exit 2
if [[ -n ${KCLT_SIM_PRE-} ]]; then eval "$KCLT_SIM_PRE"; fi
KCLT_SIM_DIR=$KCLT_TMP/sim.$BASHPID
kclt_sim "$@"
EOF

for u in "${KCLT_SIM_UNITS[@]}"; do
    kclt_simrun -- "$KCLT_TMP/sim.sh" "$u"
    kclt_expect "$u, no locale variable: the simulated image start (hook VARs put back, the hooks run once and twice) equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1a]" "sim:ok"
done
for u in "${KCLT_SIM_UNITS[@]}"; do
    kclt_simrun LANG=C.UTF-8 -- "$KCLT_TMP/sim.sh" "$u"
    kclt_expect "$u, LANG=C.UTF-8: the simulated image start equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1a]" "sim:ok"
done
# the caller's shell options do not break the harness (critic I1a M1): a
# caller under set -eu, and one with nocasematch + extglob under set -u
for pre in "set -eu" "shopt -s nocasematch extglob; set -u"; do
    for u in fv.keyboard fv.dlg; do
        KCLT_SIM_PRE=$pre
        kclt_simrun -- "$KCLT_TMP/sim.sh" "$u"
        KCLT_SIM_PRE=""
        kclt_expect "$u, a caller with '$pre': the harness runs to its verdict (load and hooks under the caller's nounset / nocasematch) and the simulated image start equals the end-of-load state [IMAGE_PLAN §5.2, I1a critic M1]" "sim:ok"
    done
done
