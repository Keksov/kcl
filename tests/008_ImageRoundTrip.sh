#!/usr/bin/env bash
# ImageRoundTrip — kk.image on real units (kklass/docs/dev/IMAGE_PLAN.md, stage
# I2a-1): `kk.image tstringlist` and `kk.image fv.dlg` (the fv closure with
# kklass, CR functions rewritten by kk._fn_text_cr) in fresh hermetic bashes:
# the first start writes the image, the second is a hit, and its state equals
# a normal load's (kkore's dump, canon; the allow-list below). The image
# folder is this test's own (KBOOL_IMAGE_DIR). The kkore contract tests are
# kkore/tests/021_Image.sh / 022_ImageStart.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageRoundTrip" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
mkdir -p "$KCLT_TMP/img"
declare -A r=()

# rt.sh MODE UNIT DUMP — load UNIT (MODE plain: KBOOL_IMAGE=off), say whether
# it came from an image (a hit leaves no __KK_UNIT_PID entry), dump the state
cat > "$KCLT_TMP/rt.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$2"; else kk.image "$2"; fi
r=$?
if [[ -n ${__KK_UNIT_PID[$2]+x} ]]; then echo "$1 rc=$r loaded"; else echo "$1 rc=$r image"; fi
kk._image_lib || exit 2
kk._img_state "$3" canon
EOF
# cmp.sh A B — the allow-list (IMAGE_PLAN §4, M6): the loader's frame index
# of each unit (inert once loaded), pid state (__KK_UNIT_PID, PPID, fv.views'
# owner pid), the name index and the caller-keyed tables, the hash table;
# CR function texts compare with ''<CR>'' as <CR> (kk._fn_text_cr's round trip)
cat > "$KCLT_TMP/cmp.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
kk._image_lib || exit 2
__KK_IMG_CMPV=(__KK_UNIT_BOT __KK_UNIT_PID __KK_UNIT_IDX __KK_UNIT_CAND __KK_UNIT_IDX_OK __KK_UNIT_RES
    __KK_UNIT_HIT __KK_FILE_PWD BASH_CMDS PPID __FV_VW_OWNER)
__KK_IMG_CMPCR=1
kk._img_cmp "$1" "$2" set
echo "cmp rc=$? $__KK_IMG_DIFF"
EOF

for u in tstringlist fv.dlg; do
    for m in miss hit plain; do
        kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" "$m" "$u" "$KCLT_TMP/$u.$m.d"
        r[$m]=$OUT
    done
    kt_test_start "$u: the first start writes an image (a normal load), the second is a hit [§6.2, §9]"
    if [[ ${r[miss]} == "miss rc=0 loaded" && ${r[hit]} == "hit rc=0 image" && ${r[plain]} == "plain rc=0 loaded" ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "miss='${r[miss]}' hit='${r[hit]}' plain='${r[plain]}' err='${ERR//$'\n'/|}'"
    fi
    kclt_simrun -- "$KCLT_TMP/cmp.sh" "$KCLT_TMP/$u.plain.d" "$KCLT_TMP/$u.hit.d"
    kclt_expect "$u: the state after the image start equals a normal load's (allow-list: frame indices, pid state, name index, caller-keyed tables, hash table; CR texts) [§4, M6]" "cmp rc=0 "
done
