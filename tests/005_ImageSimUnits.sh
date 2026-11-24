#!/usr/bin/env bash
# ImageSimUnits — the simulated image start (kklass/docs/dev/IMAGE_PLAN.md
# §5.2, the subshell form; helper kcl/tests/image_sim.sh) of kklass and of
# every kcl unit that is not an fv.* unit (image stage I1b; the fv units are
# 003_ImageSim.sh), each ALONE in a fresh hermetic bash (no prior set) with
# no locale variable at all: after the load, the hook VARs put back to their
# state before it and every hook run in load order (and once more) leave
# exactly the end-of-load state, and every variable a hook assigns is one its
# unit lists. The same under LANG=C.UTF-8 is 006_ImageSimUnitsUtf8.sh (one
# file each: the threaded runner runs them side by side). The units come from
# kcl_units.sh's KCL_UNITS (kclt_simscript): a new row is simulated here
# unedited.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageSimUnits" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
kclt_simscript

for u in kklass "${KCLT_SIM_REST[@]}"; do
    kclt_simrun -- "$KCLT_TMP/sim.sh" "$u"
    kclt_expect "$u, no locale variable: the simulated image start (hook VARs put back, the hooks run once and twice) equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1b]" "sim:ok"
done
