#!/usr/bin/env bash
# ImageSimUnitsUtf8 — 005_ImageSimUnits.sh under LANG=C.UTF-8: the simulated
# image start (kklass/docs/dev/IMAGE_PLAN.md §5.2; kcl/tests/image_sim.sh) of
# kklass and of every kcl unit that is not an fv.* unit, each ALONE in a
# fresh hermetic bash, with a locale the caller chose (the hooks' locale
# default is then a no-op) — image stage I1b.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageSimUnitsUtf8" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
kclt_simscript

for u in kklass "${KCLT_SIM_REST[@]}"; do
    kclt_simrun LANG=C.UTF-8 -- "$KCLT_TMP/sim.sh" "$u"
    kclt_expect "$u, LANG=C.UTF-8: the simulated image start equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1b]" "sim:ok"
done
