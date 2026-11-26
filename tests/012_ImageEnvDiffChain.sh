#!/usr/bin/env bash
# ImageEnvDiffChain — the load image's env-diff of CHAINED images on real
# units (kklass/docs/dev/IMAGE_PLAN.md §7.7, §10; stage I3): `kk.uses P;
# kk.image UNIT` with P = tstringlist (classes: kklass, tarray, tlist) and
# P = tutil (the wrapper family's registries TUTIL_OUT_*, which tfind / tawk
# / tsed append to in their hooks; tpipe, kklass). ONE chained image per
# (P, UNIT) is written under A (P loaded there too: kclt_simrun's hermetic
# default) and started under B1 (image_rt.sh: P loaded under B1's locale,
# hook VARs preset, a relative caller after a cd) — a hit whose state equals
# `kk.uses P; KBOOL_IMAGE=off kk.image UNIT` under B1 but for the allow-list
# (image_rt.sh); `bp`: B1 with its caller presets set BEFORE P loads (P's
# hooks keep TUTIL_OUT_PREFIXES with an extra prefix, the delta's hooks
# append to it): a hit too; `off`: KBOOL_IMAGE_CHAIN=off — a plain kk.uses.
# The units of P's own closure (kclt_closure) cannot sit on top of P (a
# kk.image of a loaded unit is a plain kk.uses): skipped.
#
# Default vs full: by default a representative set — on tstringlist:
# tobjectlist (a class whose parent is P's), tinifile, tutil (registries on
# a P with classes), dateutils (readonly constants); on tutil: tfind, tawk,
# tsed (registry appenders), thead, tpath (a function kklass defines from a
# CR-rewritten text: the cross-process compare, image I3) — with b1 for
# each, bp for tobjectlist,
# tutil, tfind and tawk, off for tinifile and tsed. KCLT_IMAGE_FULL=1: every
# unit of the table outside P's closure, on both P, with b1, bp and off.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageEnvDiffChain" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
kclt_imgscript

declare -A C=()
if [[ ${KCLT_IMAGE_FULL-} == 1 ]]; then
    for p in tstringlist tutil; do
        kclt_closure "$p"
        for r in "${KCL_UNITS[@]}"; do
            r=${r%%|*}
            [[ $KCLOSURE == *" $r "* ]] || C["$p|$r"]="b1 bp off"
        done
    done
else
    C=([tstringlist|tobjectlist]="b1 bp" [tstringlist|tinifile]="b1 off" [tstringlist|tutil]="b1 bp"
       [tstringlist|dateutils]="b1" [tutil|tfind]="b1 bp" [tutil|tawk]="b1 bp" [tutil|tsed]="b1 off"
       [tutil|thead]="b1" [tutil|tpath]="b1")
fi
if [[ -n ${KCLT_IMAGE_UNITS-} ]]; then         # (a developer's subset: "P|UNIT …")
    C=()
    for r in $KCLT_IMAGE_UNITS; do C[$r]="b1 bp off"; done
fi
# (a stable order: P, then the table's order)
for p in tstringlist tutil; do
    for r in kklass "${KCL_UNITS[@]}"; do
        r=${r%%|*}
        [[ -n ${C["$p|$r"]-} ]] || continue
        kclt_imgenv "$p" "$r" ${C["$p|$r"]}
    done
done

kt_test_log "012_ImageEnvDiffChain.sh completed"
