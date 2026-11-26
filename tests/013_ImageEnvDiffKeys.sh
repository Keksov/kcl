#!/usr/bin/env bash
# ImageEnvDiffKeys — the load image's env-diff over the settings that ARE
# key rows or decide whether an image applies (kklass/docs/dev/IMAGE_PLAN.md
# §3, §7.1, §7.6, §7.7, §8.1, §10; stage I3), each asserting WHICH outcome
# a start under B has — never just "equal" — and that its state equals a
# normal load's under the same B (image_rt.sh, the allow-list there):
#   key     a KBOOL_CONFIG that adds a define (the merged config is keyed): a
#           miss that writes another image
#   b2      a KBOOL_CONFIG whose merged effect is the default one (with
#           LC_ALL=C, FV_ASCII, TERM=dumb): a hit
#   mode    KBOOL_IMAGE_CHECK=hash (the effective mode is keyed): a miss
#   modex   KBOOL_IMAGE_CHECK=bogus (an invalid value runs as the default
#           mode, the same key): a hit
#   vk      VERBOSE_KKLASS empty instead of debug (keyed): a miss
#   clash   a caller global named like a scalar the image creates: a plain
#           kk.uses (nothing written)
#   clashx  the same name as an exported preset in the environment: a plain
#           kk.uses
#   off     (chained) KBOOL_IMAGE_CHAIN=off: a plain kk.uses
# on tstringlist (unchained) and on `kk.uses tutil; kk.image tfind`
# (chained). The same cases run per unit in 010 / 011 / 012 under
# KCLT_IMAGE_FULL=1 (key and clash); this file always runs them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageEnvDiffKeys" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
kclt_imgscript

kclt_imgenv "" tstringlist key b2 mode modex vk clash clashx
kclt_imgenv tutil tfind key mode vk off clash

kt_test_log "013_ImageEnvDiffKeys.sh completed"
