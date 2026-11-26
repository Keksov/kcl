#!/usr/bin/env bash
# ImageEnvDiff — the load image's env-diff over every unit that is not an
# fv.* unit, unchained (kklass/docs/dev/IMAGE_PLAN.md §10 rows "env-diff" and
# "round trip, lazy data, behaviour"; stage I3): for kklass and each kcl
# unit of the table (KCL_UNITS; a new row is covered without editing this
# test) ONE image is written under the environment A (kclt_simrun's
# hermetic default: no locale, no FV_*, the neutral folder, the script by
# its absolute path) and started under B1 (image_rt.sh KCLT_IMG_B1: another
# locale, NO_COLOR / TERM / COLUMNS, hook VARs preset in the environment
# and as caller globals, a relative caller after a cd) — a hit whose state
# equals a normal load's under B1 but for the allow-list (image_rt.sh);
# the units with lazy data (KCLT_IMG_LAZY: tregex, tpath, math, tutil) then
# use it, and the state after that and its output equal a normal load's too.
# HALF of them: 010 runs the first half of that list (kklass and the
# first units of the table), 015 the second (I3 fix 1: two files the
# threaded runner runs side by side). The fv.* units are 011, chained
# images 012, key / setting cases 013, the
# demos 014.
#
# Default vs full: by default B1 only. KCLT_IMAGE_FULL=1 adds, per unit, B2
# (LC_ALL=C, FV_ASCII, TERM=dumb, a config without a merged effect: a hit),
# a config that adds a define (a key row: a miss that writes another image)
# and a caller global named like a scalar the image creates (a plain
# kk.uses). Every case runs on every runtime: no GNU-only tool, the image
# folder made under umask 077, image paths from kk.image's own debug lines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageEnvDiff" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
kclt_imgscript

CASES=(b1)
if [[ ${KCLT_IMAGE_FULL-} == 1 ]]; then CASES=(b1 b2 key clash); fi
U=(kklass)
for r in "${KCL_UNITS[@]}"; do r=${r%%|*}; [[ $r == fv.* ]] || U+=("$r"); done
HALF=1
if (( HALF == 1 )); then U=("${U[@]:0:$(( (${#U[@]} + 1) / 2 ))}"); else U=("${U[@]:$(( (${#U[@]} + 1) / 2 ))}"); fi
if [[ -n ${KCLT_IMAGE_UNITS-} ]]; then U=($KCLT_IMAGE_UNITS); fi     # (a developer's subset)
for u in "${U[@]}"; do
    kclt_imgenv "" "$u" "${CASES[@]}"
done

kt_test_log "010_ImageEnvDiff.sh completed"
