#!/usr/bin/env bash
# ImageEnvDiffFv — the load image's env-diff over every fv.* unit, unchained
# (kklass/docs/dev/IMAGE_PLAN.md §10; stage I3): as 010, for the fv.* rows of
# KCL_UNITS, each started under B1 and fv.keyboard, fv.video and fv.dlg also
# under B2 (image_rt.sh: the locale decides fv.keyboard's layout and
# fv.video's ASCII mode, so both a UTF-8 locale of another language and
# LC_ALL=C with FV_ASCII=1 are started from an image written without a
# locale). The units with lazy data or behaviour
# (KCLT_IMG_LAZY: fv.unicode's width cache, fv.video's ASCII map,
# fv.keyboard's layout tables, fv.dlg's usage text and headless widgets —
# msgbox, checklist, inputbox, yesno through fv.dlg's own test lib, the
# screen's rows and palette symbols) use them after the start and after the
# normal load: outputs and states equal.
# fv.keyboard and fv.drivers alone (no kklass in their closure) hold a raw CR
# function: on a CR-dropping parser (Git-bash, MSYS2; kclt_crdrop) no image
# is written (plan §6.3) and their starts are plain loads — pinned
# (image_rt.sh KCLT_IMG_CRUNITS); elsewhere they are hits.
#
# Default vs full: by default B1 (B2 for the three above). KCLT_IMAGE_FULL=1:
# B2 for every fv unit, the key case (a config that adds a define: a miss)
# and the clash case (a caller global named like an image scalar: a plain
# kk.uses) per unit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageEnvDiffFv" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
kclt_imgscript

# (B2 by default for the units whose state follows the locale: fv.keyboard,
# fv.video, and fv.dlg, whose closure holds both and most fv units; the
# other fv units get B2 under FULL)
B2=" fv.keyboard fv.video fv.dlg "
FULL=0
if [[ ${KCLT_IMAGE_FULL-} == 1 ]]; then FULL=1; fi
U=()
for r in "${KCL_UNITS[@]}"; do r=${r%%|*}; [[ $r == fv.* ]] && U+=("$r"); done
if [[ -n ${KCLT_IMAGE_UNITS-} ]]; then U=($KCLT_IMAGE_UNITS); fi     # (a developer's subset)
for u in "${U[@]}"; do
    if (( FULL )); then kclt_imgenv "" "$u" b1 b2 key clash
    elif [[ $B2 == *" $u "* ]]; then kclt_imgenv "" "$u" b1 b2
    else kclt_imgenv "" "$u" b1; fi
done

kt_test_log "011_ImageEnvDiffFv.sh completed"
