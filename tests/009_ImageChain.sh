#!/usr/bin/env bash
# ImageChain — chained load images on real units (kklass/docs/dev/IMAGE_PLAN.md
# §7.7, stage I2b): `kk.uses tstringlist; kk.image fv.dlg` and a kklass + kcl
# chain (`kk.uses kklass tutil; kk.image tfind`) in fresh hermetic bashes:
# the first start writes the chained image (its fresh-process simulation
# passes), the second is a hit, and its state equals `kk.uses P… REQ`
# loaded normally (kkore's dump, canon; the allow-list of 008). The base
# check on a kklass table: a name the delta writes into P's _KKLASS_TAKEN
# set before kk.image — a plain kk.uses (the same output and state as
# without images), nothing written. The writer's simulation: a P class
# changed by the script (defineMethod) before kk.image — no image, a hold.
# The kkore contract of chaining is kkore/tests/028_ImageChain.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageChain" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
( umask 077 && mkdir -p "$KCLT_TMP/img" )     # (as kk.image makes it: a umask 002 folder is refused in stat mode)
declare -A r=()

# rt.sh MODE "P…" UNIT DUMP [PRE] — kk.uses P…, then PRE (shell text), then
# kk.image UNIT (MODE plain: KBOOL_IMAGE=off); says whether it came from an
# image (a hit leaves no __KK_UNIT_PID entry) and what kk.image said (debug,
# its last line); the state dump
cat > "$KCLT_TMP/rt.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
VERBOSE_KKLASS=debug
kk.uses $2 >/dev/null 2>&1 || exit 3
if [[ -n ${5-} ]]; then eval "$5"; fi
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$3" >/dev/null 2>"$KCLT_TMP/rt.err"; else kk.image "$3" >/dev/null 2>"$KCLT_TMP/rt.err"; fi
r=$?
l=""; while IFS= read -r x; do x=${x#kbool: image: }; case $x in wrote*|"no image written"*|"loaded from"*|*"differs from the image"*|KBOOL_IMAGE=off*) l=$x; break ;; esac; done < "$KCLT_TMP/rt.err"
if [[ -n ${__KK_UNIT_PID[$3]+x} ]]; then echo "$1 rc=$r loaded"; else echo "$1 rc=$r image"; fi
echo "${l%% /*}"
unset r l x
kk._image_lib || exit 2
kk._img_state "$4" canon
EOF
cat > "$KCLT_TMP/cmp.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
kk._image_lib || exit 2
__KK_IMG_CMPV=(__KK_UNIT_BOT __KK_UNIT_PID __KK_UNIT_IDX __KK_UNIT_CAND __KK_UNIT_IDX_OK __KK_UNIT_RES
    __KK_UNIT_HIT __KK_FILE_PWD BASH_CMDS PPID __FV_VW_OWNER)
__KK_IMG_CMPCR=1
kk._img_cmp "$1" "$2" set
echo "cmp rc=$? $__KK_IMG_DIFF"
EOF

for c in "tstringlist|fv.dlg" "kklass tutil|tfind"; do
    p=${c%%|*} u=${c#*|}
    for m in miss hit plain; do
        kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" "$m" "$p" "$u" "$KCLT_TMP/$u.$m.d"
        r[$m]=${OUT//$'\n'/ | }
    done
    kt_test_start "kk.uses $p; kk.image $u: the first start writes a chained image (its fresh-process simulation passes), the second is a hit [§7.7]"
    if [[ ${r[miss]} == "miss rc=0 loaded | wrote" && ${r[hit]} == "hit rc=0 image | loaded from" && ${r[plain]} == "plain rc=0 loaded | "* ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "miss='${r[miss]}' hit='${r[hit]}' plain='${r[plain]}' err='${ERR//$'\n'/|}'"
    fi
    kclt_simrun -- "$KCLT_TMP/cmp.sh" "$KCLT_TMP/$u.plain.d" "$KCLT_TMP/$u.hit.d"
    kclt_expect "kk.uses $p; kk.image $u: the hit's state equals \`kk.uses $p $u\` loaded normally (allow-list of 008) [§10 chained starts]" "cmp rc=0 "
done

# the base check on P's kklass table: a name the delta of `kk.image tdictionary`
# writes into _KKLASS_TAKEN (P = tstringlist) set first — a plain kk.uses: the
# same output and state as without images, nothing written
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" miss tstringlist tdictionary "$KCLT_TMP/td.miss.d"
A=${OUT//$'\n'/ | }
for f in "$KCLT_TMP"/img/tdictionary-*.img; do TDI=$f; done
IFS= read -r -d '' z < "$TDI" || :
kt_test_start "(the chained image of tdictionary holds _KKLASS_TAKEN[TDictionary] in its base list)"
if [[ $A == "miss rc=0 loaded | wrote" && $z == *"__kk_img_base=("*"_KKLASS_TAKEN"*"TDictionary"* ]]; then kt_test_pass "ok"; else kt_test_fail "miss='$A'"; fi
PRE='_KKLASS_TAKEN[TDictionary]=class'
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" hit tstringlist tdictionary "$KCLT_TMP/td.pre.d" "$PRE"
A=${OUT//$'\n'/ | } AE=$ERR
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" plain tstringlist tdictionary "$KCLT_TMP/td.pre0.d" "$PRE"
B=${OUT//$'\n'/ | } BE=$ERR
kclt_simrun -- "$KCLT_TMP/cmp.sh" "$KCLT_TMP/td.pre0.d" "$KCLT_TMP/td.pre.d"
C=$OUT
IFS= read -r -d '' z2 < "$TDI" || :
kt_test_start "a _KKLASS_TAKEN name the delta writes, set before kk.image: a plain kk.uses (the base differs), nothing written; output and state as without images"
if [[ $A == "hit rc="*" loaded | _KKLASS_TAKEN[TDictionary] differs from the image's base; a normal load (kk.uses tdictionary)" \
      && ${B%% |*} == "plain rc=0 loaded" && $C == "cmp rc=0 " && $z2 == "$z" && $AE == "$BE" ]] \
   && ! compgen -G "$KCLT_TMP/img/tdictionary-*.hold" >/dev/null; then
    kt_test_pass "ok"
else
    kt_test_fail "image='$A' plain='$B' cmp='$C' err='${AE//$'\n'/|}' vs '${BE//$'\n'/|}'"
fi

# the writer's simulation (R13, the writer's side): the script changes a P
# class (defineMethod on tlist's TList) before `kk.image tobjectlist`
# (TObjectList extends TList) — the fresh process loads P as its own load
# leaves it: its base (kklass's METHOD_BODY, left by defineMethod) or its state
# differs, no image, a hold
PRE='defineMethod TList chainExtra '"'"'echo extra'"'"''
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" miss tlist tobjectlist "$KCLT_TMP/to.d" "$PRE"
A=${OUT//$'\n'/ | }
kt_test_start "a P class changed by the script (defineMethod TList …) before kk.image tobjectlist: no image (the fresh-process simulation differs), a hold [§5.2, R13]"
if [[ $A == "miss rc=0 loaded | no image written: the simulated image start "* ]] && compgen -G "$KCLT_TMP/img/tobjectlist-*.hold" >/dev/null \
   && ! compgen -G "$KCLT_TMP/img/tobjectlist-*.img" >/dev/null; then
    kt_test_pass "ok"
else
    kt_test_fail "run='$A' err='${ERR//$'\n'/|}'"
fi

kt_test_log "009_ImageChain.sh completed"
