#!/usr/bin/env bash
# ImageRoundTrip — kk.image on real units (kklass/docs/dev/IMAGE_PLAN.md, stage
# I2a-1): a damaged image of tstringlist (cut in the final block / in the
# kkore registration, under set -e / set -u: undone, a normal load, the state
# a normal load's — kkore's dump, canon; the allow-list of image_rt.sh), and
# the M1 probe's false-refusal guard over kklass and every kcl unit in ONE
# request. The plain round trips of tstringlist and fv.dlg it had (I2a) are
# 010 / 011's B1 cases since image I3 (fix round 1: not run twice). The image
# folder is this test's own (KBOOL_IMAGE_DIR). The kkore contract tests are
# kkore/tests/021_Image.sh / 022_ImageStart.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageRoundTrip" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
( umask 077 && mkdir -p "$KCLT_TMP/img" )     # (as kk.image makes it: a umask 002 folder is refused in stat mode)
declare -A r=()

# rt.sh MODE UNIT DUMP — load UNIT (MODE plain: KBOOL_IMAGE=off), say whether
# it came from an image (a hit leaves no __KK_UNIT_PID entry), dump the state
# (its pid values as <pid>: image_rt.sh's pid rule)
cat > "$KCLT_TMP/rt.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$2"; else kk.image "$2"; fi
r=$?
if [[ -n ${__KK_UNIT_PID[$2]+x} ]]; then echo "$1 rc=$r loaded"; else echo "$1 rc=$r image"; fi
kk._image_lib || exit 2
source "$KCLT_TMP/pid.sh" || exit 2
__KK_IMG_XV=('__rt_*') __KK_IMG_XF=('__rt_*')
__rt_pid "$3"
EOF
# cmp.sh A B — the compare with THE allow-list of the image tests
# (image_rt.sh KCLT_IMG_ALLOW, each entry's reason there; image I3 moved it
# there from here); pid.sh — the pid rule
kclt_imgcmpscript
kclt_imgpidscript

# the image the damage cases cut, and the normal load they compare with
for m in miss plain; do
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/rt.sh" "$m" tstringlist "$KCLT_TMP/tstringlist.$m.d"
    r[$m]=$OUT
done
kt_test_start "(tstringlist: the first start writes the image the damage cases cut)"
if [[ ${r[miss]} == "miss rc=0 loaded" && ${r[plain]} == "plain rc=0 loaded" ]] && compgen -G "$KCLT_TMP/img/tstringlist-*.img" >/dev/null; then
    kt_test_pass "ok"
else
    kt_test_fail "miss='${r[miss]}' plain='${r[plain]}' err='${ERR//$'\n'/|}'"
fi

# a damaged image of a unit with classes (tstringlist): cut inside the final
# block (kklass's tables), started under set -e and under set -u — the undo
# forgets the classes, so the normal load after it declares them without a
# "declared again; ignored" message; the state equals a normal load's
cat > "$KCLT_TMP/dm.sh" <<'EOS'
source "$KBOOL_ROOT/kbool.sh" || exit 2
set "$1"
kk.image tstringlist; r=$?
echo "survived rc=$r ${__KK_UNIT_PID[tstringlist]+normal}"
set +eu
kk._image_lib || exit 2
source "$KCLT_TMP/pid.sh" || exit 2
__KK_IMG_XV=('__rt_*') __KK_IMG_XF=('__rt_*')
__rt_pid "$2"
EOS
for f in "$KCLT_TMP"/img/tstringlist-*.img; do IMG=$f; done
for REFN in "${IMG%.img}".*.ref; do :; done
cp "$IMG" "$KCLT_TMP/tsl.full"; cp "$REFN" "$KCLT_TMP/tsl.ref"
IFS= read -r -d '' z < "$KCLT_TMP/tsl.full" || :
blen() { local LC_ALL=C; n=${#p}; }
# the cuts: inside kklass's tables (classes not yet registered), and inside
# the kkore registration after them (classes registered: the undo must
# forget them, or the normal load says "declared again; ignored" — critic
# mutation undocls)
for cut in tables:-e registration:-e registration:-u; do
    opt=${cut#*:} cut=${cut%%:*}
    if [[ $cut == tables ]]; then p=${z%%$'\n'declare -gA _KKLASS_*}; else p=${z%%$'\n'__KK_UNITS\[*}; fi
    blen
    cp "$KCLT_TMP/tsl.full" "$IMG"; cp "$KCLT_TMP/tsl.ref" "$REFN"; rm -f "$KCLT_TMP"/img/*.hold
    head -c $(( n + 40 )) "$KCLT_TMP/tsl.full" > "$IMG"
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/dm.sh" "$opt" "$KCLT_TMP/tsl.dm.d"
    r=$OUT e=$ERR
    kclt_simrun -- "$KCLT_TMP/cmp.sh" "$KCLT_TMP/tstringlist.plain.d" "$KCLT_TMP/tsl.dm.d"
    kt_test_start "tstringlist, an image cut in the $cut, set $opt: undone, a normal load without 'declared again', the state a normal load's [§8.3]"
    if [[ $r == "survived rc=0 normal" && $e != *"declared again"* && $OUT == "cmp rc=0 " && $n -gt 100 && $n -lt ${#z} ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "run='$r' err='${e//$'\n'/|}' cmp='$OUT' cut=$n"
    fi
done

# the M1 probe's false-refusal guard (critic): ONE kk.image of kklass and every
# kcl unit (KCL_UNITS, in table order — a new row is covered without editing
# this test) from a caller that has ordinary globals value / rc / y / i: an
# image is written (the units do not set those names: no refusal). One
# combined request, not one per unit: a writer per unit would cost minutes.
kclt_simscript
cat > "$KCLT_TMP/m1g.sh" <<'EOS'
source "$KBOOL_ROOT/kbool.sh" || exit 2
value=1 rc=2 y=3 i=4
VERBOSE_KKLASS=debug kk.image "$@" 2>"$KCLT_TMP/m1g.err" >/dev/null
r=$?
while IFS= read -r l; do [[ $l == *"no image written"* || $l == *"wrote "* ]] && echo "${l%% /*}"; done < "$KCLT_TMP/m1g.err"
echo "rc=$r value=$value rc_=$rc y=$y i=$i"
EOS
# (on a bash whose declare -f prints `1<> FILE` as `<> FILE` — 5.2 — the
# units of image_rt.sh's KCLT_IMG_RWUNITS get no image at all: left out here,
# where the M1 guard is the point; image I3)
M1U=()
for u in kklass "${KCLT_SIM_REST[@]}" "${KCLT_SIM_FV[@]}"; do
    if [[ $KCLT_IMG_RWUNITS == *" $u "* ]] && kclt_rwbug; then continue; fi
    M1U+=("$u")
done
kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/m1g.sh" "${M1U[@]}"
kclt_expect "kklass and $(( ${#M1U[@]} - 1 )) kcl units (all of them, but those this bash cannot image: KCLT_IMG_RWUNITS) in ONE kk.image from a caller with globals value rc y i: the image is written (no false M1 refusal), the globals untouched" \
    "kbool: image: wrote"$'\n'"rc=0 value=1 rc_=2 y=3 i=4"
