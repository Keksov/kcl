#!/usr/bin/env bash
# ImageDemos — behaviour from an image start (kklass/docs/dev/IMAGE_PLAN.md
# §10 row "round trip, lazy data, behaviour"; stage I3): the two headless fv
# demos — kcl/fv.app/examples/demo.sh (on fv.app) and
# kcl/fv.dialogs/examples/widgets.sh (on fv.app and fv.msgbox), each of which
# builds a class of its own (TDemoApp) at run time — run from an image start
# and from a normal load print the same final screen and write the same
# frames. A child (dm.sh) starts the demo's units through `kk.image` (or
# `KBOOL_IMAGE=off kk.image`: a normal load), then sources the demo with
# --headless --keys FILE --out FILE: its own `source kbool.sh` and `kk.uses`
# lines are no-ops then. The first run writes the image (under A: no
# locale); the image start and the normal load run under B (LANG=C.UTF-8,
# NO_COLOR, TERM). fv.dlg's headless widgets from an image start are 011's
# (KCLT_IMG_LAZY[fv.dlg]).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageDemos" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
source "$SCRIPT_DIR/image_rt.sh"
kclt_setup
kclt_imgscript

# dm.sh MODE DEMO "UNITS" OUT KEYS — the units through kk.image (MODE image
# / miss) or a normal load (plain); OUT.st = image | the loading pid; the
# demo sourced headless (its final screen on stdout, its frames in
# OUT.frames, the keys from KEYS)
cat > "$KCLT_TMP/dm.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image $3 || exit 3; else kk.image $3 || exit 3; fi
echo "${__KK_UNIT_PID[fv.app]-image}" > "$4.st"
__dm_d=$2 __dm_o=$4 __dm_k=$5
set -- --headless --keys "$__dm_k" --out "$__dm_o.frames"
source "$__dm_d"
EOF
printf '\033[17~\033[12~\033x' > "$KCLT_TMP/k.demo"            # F6, F2 (tile), Alt+X
printf '\033[12~new_name.txt\r\033x' > "$KCLT_TMP/k.widgets"   # F2, a new name, Enter, Alt+X
B=(LANG=C.UTF-8 NO_COLOR=1 TERM=xterm-256color)

for c in "demo|$KCL_DIR/fv.app/examples/demo.sh|fv.app" "widgets|$KCL_DIR/fv.dialogs/examples/widgets.sh|fv.app fv.msgbox"; do
    IFS='|' read -r n d u <<< "$c"
    O=$KCLT_TMP/d/$n
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" -- "$KCLT_TMP/dm.sh" miss "$d" "$u" "$O.w" "$KCLT_TMP/k.$n"
    W=$OUT WR=$RC
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" "${B[@]}" -- "$KCLT_TMP/dm.sh" image "$d" "$u" "$O.h" "$KCLT_TMP/k.$n"
    H=$OUT HR=$RC HE=$ERR
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" "${B[@]}" -- "$KCLT_TMP/dm.sh" plain "$d" "$u" "$O.r" "$KCLT_TMP/k.$n"
    R=$OUT RR=$RC RE=$ERR
    st="" sr="" fh="" fr=""
    IFS= read -r st < "$O.h.st" || :
    IFS= read -r sr < "$O.r.st" || :
    IFS= read -r -d '' fh < "$O.h.frames" || :
    IFS= read -r -d '' fr < "$O.r.frames" || :
    mapfile -t rows <<< "$H"
    kt_test_start "the headless $n demo (kk.image $u, its own class TDemoApp built at run time): from an image start under B it prints the same final screen and writes the same frames as from a normal load, rc 0 [§10 behaviour]"
    if [[ $WR == 0 && $HR == 0 && $RR == 0 && $st == image && $sr == [0-9]* && ${#rows[@]} == 24 && $H == "$R" \
          && ${#fh} -gt 1000 && $fh == "$fr" ]] && compgen -G "$KCLT_TMP/img/fv.app-*.img" >/dev/null; then
        kt_test_pass "ok (${#fh} bytes of frames)"
    else
        kt_test_fail "rc $WR/$HR/$RR start='$st' normal='$sr' rows=${#rows[@]} screen-equal=$([[ $H == "$R" ]] && echo y || echo n) frames ${#fh}/${#fr} err='${HE:0:300}' vs '${RE:0:300}'"
    fi
done

kt_test_log "014_ImageDemos.sh completed"
