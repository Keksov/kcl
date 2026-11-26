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
#   local   a script in another folder holding a copy of the request's file
#           (the caller's folder is searched first): a miss, another image
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

kclt_imgenv "" tstringlist key b2 mode modex vk clash clashx local
kclt_imgenv tutil tfind key mode vk off clash

# the harness itself (I3 fix 1, critic L2): a lazy output that differs from
# the normal load's by one empty line only is a difference (`out rc=1`)
L='echo a; if [[ $1 == image ]]; then echo; fi; echo b'
kclt_img tsl.nl RT_LAZY="$L" -- image "" tstringlist
A=$OUT
kclt_img tsl.nl.r RT_LAZY="$L" RT_REF="$KCLT_TMP/d/tsl.nl" -- plain "" tstringlist
kt_test_start "(the harness: an output that differs only by an empty line is a difference — out rc=1)"
if [[ $A == "image rc=0 image imgs=+0 | hit" && $IMG_OUT == "out rc=1 "* ]]; then kt_test_pass "ok"; else kt_test_fail "start='$A' out='$IMG_OUT'"; fi

# the pid rule needs both sides (I3 fix 2): a plain global that holds the
# start's pid there and the same NUMBER in the normal load (a constant that
# met one child's pid by chance) compares equal as the number it is
P='if [[ $1 == image ]]; then I3_PIDC=$BASHPID; else IFS= read -r I3_PIDC < "$RT_REF.pidn"; fi'
kclt_img tsl.pc RT_PRE="$P" -- image "" tstringlist
A=$OUT
kclt_img tsl.pc.r RT_PRE="$P" RT_REF="$KCLT_TMP/d/tsl.pc" -- plain "" tstringlist
kt_test_start "(the harness: a value equal to ONE child's pid only is no pid state — compared as it is, equal)"
if [[ $A == "image rc=0 image imgs=+0 | hit" && $IMG_CMP == "cmp rc=0 " ]]; then kt_test_pass "ok"; else kt_test_fail "start='$A' cmp='$IMG_CMP'"; fi

kt_test_log "013_ImageEnvDiffKeys.sh completed"
