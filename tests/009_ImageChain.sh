#!/usr/bin/env bash
# ImageChain — chained load images on real units (kklass/docs/dev/IMAGE_PLAN.md
# §7.7, stage I2b): `kk.uses tstringlist; kk.image fv.dlg` and a kklass + kcl
# chain (`kk.uses kklass tutil; kk.image tfind`) in fresh hermetic bashes:
# the first start writes the chained image (its fresh-process simulation
# passes), the second is a hit, and its state equals `kk.uses P… REQ`
# loaded normally (kkore's dump, canon; the allow-list of image_rt.sh). The base
# check on a kklass table: a name the delta writes into P's _KKLASS_TAKEN
# set before kk.image — a plain kk.uses (the same output and state as
# without images), nothing written. The writer's simulation: a P class
# changed by the script (defineMethod) before kk.image — no image, a hold;
# after a clean image, before its start — a plain kk.uses (_KKLASS_GEN).
# Environment names (NO_COLOR, T, C) exported in the writer: no read base.
# The kkore contract of chaining is kkore/tests/028_ImageChain.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageChain" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
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
l=""; while IFS= read -r x; do x=${x#kbool: image: }; case $x in wrote*|"no image written"*|"loaded from"*|*"differs from the image"*|*"which this call's load reads"*|KBOOL_IMAGE=off*) l=$x; break ;; esac; done < "$KCLT_TMP/rt.err"
if [[ -n ${__KK_UNIT_PID[$3]+x} ]]; then echo "$1 rc=$r loaded"; else echo "$1 rc=$r image"; fi
echo "${l%% /*}"
unset r l x
kk._image_lib || exit 2
source "$KCLT_TMP/pid.sh" || exit 2
__KK_IMG_XV=('__rt_*') __KK_IMG_XF=('__rt_*')
__rt_pid "$4"
EOF
# cmp.sh A B — the compare with THE allow-list (image_rt.sh KCLT_IMG_ALLOW)
kclt_imgcmpscript
kclt_imgpidscript     # (pid.sh: the pid rule of image_rt.sh, I3 fix 1)

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
    kclt_expect "kk.uses $p; kk.image $u: the hit's state equals \`kk.uses $p $u\` loaded normally (the allow-list of image_rt.sh) [§10 chained starts]" "cmp rc=0 "
done

# environment names are no read base unless P's files assign them (critic
# N2, I2b fix round 2): fv.dlg written with NO_COLOR, T and C exported (fv.dlg
# reads NO_COLOR in a function; T and C are words of P's files, which never
# assign them), then started without them and with other values: hits
( umask 077 && mkdir -p "$KCLT_TMP/img2" )
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img2" -- "$KCLT_TMP/rt.sh" miss tstringlist fv.dlg "$KCLT_TMP/nc0.d" 'export NO_COLOR=1 T=1 C=1'
A=${OUT//$'\n'/ | }
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img2" -- "$KCLT_TMP/rt.sh" hit tstringlist fv.dlg "$KCLT_TMP/nc1.d"
B=${OUT//$'\n'/ | }
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img2" -- "$KCLT_TMP/rt.sh" hit tstringlist fv.dlg "$KCLT_TMP/nc2.d" 'export NO_COLOR=yes T=2 C=2'
C=${OUT//$'\n'/ | }
kt_test_start "fv.dlg on tstringlist written with NO_COLOR, T, C exported: starts without them and with other values hit (no read base of the request's own environment names) [I2b G3]"
if [[ $A == "miss rc=0 loaded | wrote" && $B == "hit rc=0 image | loaded from" && $C == "hit rc=0 image | loaded from" ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "miss='$A' start='$B' other='$C' err='${ERR//$'\n'/|}'"
fi

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

# R13 at a start (I2b fix round F3): the load of tobjectlist builds a class,
# so kklass's class generation _KKLASS_GEN is a base slot of its chained image
# (and kklass's METHOD_BODY / METHOD_WRAPPER, its builders' locals now, are
# not); a clean image, then a start in a script that changed P's TList first
# (defineMethod) — a plain kk.uses, nothing written, no hold
PRE='defineMethod TList chainExtra '"'"'echo extra'"'"''
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" miss tlist tobjectlist "$KCLT_TMP/to0.d"
A=${OUT//$'\n'/ | }
for f in "$KCLT_TMP"/img/tobjectlist-*.img; do TOI=$f; done
IFS= read -r -d '' z < "$TOI" || :
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" hit tlist tobjectlist "$KCLT_TMP/to1.d" "$PRE"
B=${OUT//$'\n'/ | }
IFS= read -r -d '' z2 < "$TOI" || :
kt_test_start "a P class changed by the script (defineMethod TList …) before the start of a clean chained image of tobjectlist: a plain kk.uses (_KKLASS_GEN, a base slot, differs), nothing written [R13, I2b F3]"
zb=${z#*$'\n'__kk_img_base=\(}; zb=${zb%%$'\n'*}      # (the base list line)
if [[ $A == "miss rc=0 loaded | wrote" && $zb == *"_KKLASS_GEN"* && $zb != *METHOD_BODY* && $zb != *METHOD_WRAPPER* \
      && $B == "hit rc=0 loaded | _KKLASS_GEN differs from the image's base; a normal load (kk.uses tobjectlist)" && $z2 == "$z" ]] \
   && ! compgen -G "$KCLT_TMP/img/tobjectlist-*.hold" >/dev/null; then
    kt_test_pass "ok"
else
    kt_test_fail "miss='$A' start='$B' err='${ERR//$'\n'/|}'"
fi
# (the next case writes the image of the same key again)
for f in "$KCLT_TMP"/img/tobjectlist-*; do [[ -e $f ]] && rm -f -- "$f"; done

# the writer's simulation (R13, the writer's side): the script changes a P
# class (defineMethod on tlist's TList) before `kk.image tobjectlist`
# (TObjectList extends TList) — the fresh process loads P as its own load
# leaves it: its base (kklass's _KKLASS_GEN, bumped by defineMethod) or its state
# differs, no image, a hold
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
