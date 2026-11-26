#!/usr/bin/env bash
# 013_Image.sh - bin/fvdlg through kkore's load image (kk.image --background
# fv.dlg; kklass/docs/dev/IMAGE_PLAN.md stage I5, owner decision IMG-D10).
# The other fv.dlg test files run bin/fvdlg with KBOOL_IMAGE=off
# (fvdlg_testlib.sh fvdl_init); this one turns it on, with its own image
# folder under the test's temp folder (never the real per-user cache):
#   * the guards before the load write nothing (no terminal, --version);
#   * the first call (a miss) answers at once — `$(fvdlg …)` returns while
#     the background writer still runs (paused by the seam
#     __KK_IMG_BGPAUSE), also with fd 3 as the substitution's pipe
#     (`3>&1 1>&2 2>&3`); a second call meanwhile starts no second writer;
#   * the writer ends by itself and leaves the image the next start uses;
#   * then every call is a hit (the image not rewritten, no writer) with the
#     same status, stdout, stderr and — headless — the same frames as the
#     plain load (KBOOL_IMAGE=off) for the cases of 001-009 that matter: the
#     no-terminal default answers, headless widgets with keys, an error;
#   * no writer outlives the file (the EXIT trap kills a leftover writer
#     group and fails the file).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"
TMP=$FVW_TMP
ROOT="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)"
CMD=$ROOT/bin/fvdlg
D=$TMP/img
export FV_TTY=$TMP/none/tty
kt_test_start "fvdl_init exports KBOOL_IMAGE=off (every other fv.dlg test file runs bin/fvdlg without images or writers)"
if [[ ${KBOOL_IMAGE-} == off && ${KBOOL_IMAGE@a} == *x* ]]; then kt_test_pass ok; else kt_test_fail "KBOOL_IMAGE=[${KBOOL_IMAGE-unset}] attrs=[${KBOOL_IMAGE@a}]"; fi
unset -v KBOOL_IMAGE
printf '\r' > "$TMP/enter.keys"
printf '\033[B\r' > "$TMP/down.keys"
printf 'xy\r' > "$TMP/xy.keys"
# the children's image settings: on, the test's folder, the default check
# mode, no debug (VERBOSE_KKLASS is keyed: one key for every call here)
IENV=(-u KBOOL_IMAGE -u KBOOL_IMAGE_CHECK -u KBOOL_IMAGE_CHAIN -u VERBOSE_KKLASS -u KBOOL_CONFIG "KBOOL_IMAGE_DIR=$D")

# run img|off [ENV=V...] -- ARG... : bin/fvdlg in a child; R_RC, R_OUT, R_ERR, R_US
run() {
    local m=$1 t0 t1
    local -a env=("${IENV[@]}")
    shift
    [[ $m == off ]] && env+=(KBOOL_IMAGE=off)
    while (( $# )) && [ "$1" != -- ]; do env+=("$1"); shift; done
    shift
    t0=$EPOCHREALTIME
    env "${env[@]}" "$BASH" "$CMD" "$@" >"$TMP/r.out" 2>"$TMP/r.err" </dev/null
    R_RC=$?
    t1=$EPOCHREALTIME
    R_US=$(( 10#${t1/./} - 10#${t0/./} ))
    R_OUT='' R_ERR=''
    { IFS= read -r -d '' R_OUT || :; } < "$TMP/r.out"
    { IFS= read -r -d '' R_ERR || :; } < "$TMP/r.err"
}
# probe -> rc 0 when a start of fv.dlg would hit (kk.image --path from a
# script beside the test: the caller's folder holds no fv.dlg, as bin/ does
# not — the same request files, the same key)
printf '%s\n' 'source "$1/kbool.sh" || exit 9' 'kk.image --path fv.dlg >/dev/null' > "$TMP/probe.sh"
probe() { env "${IENV[@]}" "$BASH" "$TMP/probe.sh" "$ROOT" </dev/null >/dev/null 2>&1; }
# img_nonce -> NONCE: the image's nonce (its plain line's field 7; '' none)
img_nonce() {
    local f l1 l2 IFS=$'\x1f'
    local -a a=()
    NONCE='' IMG=''
    for f in "$D"/fv.dlg-*.img; do [[ -e $f ]] && IMG=$f; done
    [[ -n $IMG ]] || return 0
    { IFS= read -r l1; IFS= read -r l2; } < "$IMG"
    a=(${l2#"#P"$'\x1f'})
    NONCE=${a[7]-}
}

# ---- the writers (as kkore 029): found by their markers, never left behind ----
BG_SEEN=() BG_LEFT=""
bg_read() {
    BG_T="" BG_O="" BG_P="" BG_G="" BG_Q=""
    [[ -f $1 ]] || return 1
    { IFS=' ' read -r BG_T BG_O BG_P BG_G BG_Q < "$1"; } 2>/dev/null || :
    return 0
}
bg_marker() { local f; BG_M=""; for f in "$D"/*.bg; do [[ -e $f ]] && BG_M=$f; done; }
bg_started() {
    local n=$(( ${2:-30} * 10 ))
    while (( n-- > 0 )); do
        if bg_read "$1" && [[ -n $BG_P && $BG_P != *[!0-9]* ]]; then BG_SEEN+=("$BG_P ${BG_Q:--}"); return 0; fi
        [[ -f $1 ]] || return 1
        sleep 0.1
    done
    return 1
}
bg_kill() {
    if [[ -n $2 && $2 != *[!0-9]* && $2 != 0 ]]; then kill "-$3" -- "-$2" 2>/dev/null; fi
    kill "-$3" "$1" 2>/dev/null
}
bg_guard() {
    local e p q f n
    local -a all=("${BG_SEEN[@]}")
    for f in "$D"/*.bg; do
        [[ -e $f ]] || continue
        bg_read "$f" && [[ -n $BG_P && $BG_P != *[!0-9]* ]] && all+=("$BG_P ${BG_Q:--}")
    done
    for e in "${all[@]}"; do
        p=${e%% *} q=${e#* }
        kill -0 "$p" 2>/dev/null || continue
        BG_LEFT+=" $p"
        bg_kill "$p" "$q" TERM
        for (( n = 0; n < 30; n++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
        bg_kill "$p" "$q" KILL
    done
}
bg_exitcheck() {
    bg_guard
    if [[ -n $BG_LEFT ]]; then
        kt_test_start "no background writer outlives the test file"
        kt_test_fail "leftover writer(s):$BG_LEFT"
    fi
}
t=$(trap -p EXIT)
eval "set -- $t"
trap "bg_exitcheck; ${3-}" EXIT

kt_test_section "013: the guards before the load write nothing"

run img -- --yesno Sure 0 0
kt_test_start "no terminal: 255 before the load, no image folder made"
if [[ $R_RC == 255 && $R_ERR == "fvdlg: no terminal ($FV_TTY)"$'\n' && ! -e $D ]]; then kt_test_pass ok
else kt_test_fail "rc=$R_RC err=[$R_ERR] folder=$([[ -e $D ]] && echo yes || echo no)"; fi
run img -- --version
kt_test_start "--version: no load, no image folder"
if [[ $R_RC == 0 && $R_OUT == 'fvdlg 0.1 (kbool fv.dlg)'* && ! -e $D ]]; then kt_test_pass ok; else kt_test_fail "rc=$R_RC [$R_OUT]"; fi

kt_test_section "013: the first call: a plain load at once, the writer in the background"

t0=$EPOCHREALTIME
pick=$(env "${IENV[@]}" __KK_IMG_BGPAUSE=10 "$BASH" "$CMD" --no-tty=default --menu Pick 0 0 0 a A b B 3>&1 1>&2 2>&3 </dev/null)
r=$?
t1=$EPOCHREALTIME
us=$(( 10#${t1/./} - 10#${t0/./} ))
bg_marker; M=$BG_M
kt_test_start "the first call (a miss; fd 3 = the substitution's pipe, 3>&1 1>&2 2>&3): the answer at once — \$(fvdlg …) returned in $(( us / 1000 )) ms while its writer waits 10 s; status 0"
if [[ $r == 0 && $pick == a && -n $M ]] && (( us < 8000000 )); then kt_test_pass ok
else kt_test_fail "rc=$r pick=[$pick] marker=[$M] us=$us"; fi
bg_started "$M"
kt_test_start "the background writer started (its pid in the marker)"
if [[ -n $BG_P && $BG_P != - ]]; then kt_test_pass ok; else kt_test_fail "marker=[$(cat "$M" 2>/dev/null)]"; fi
O=$BG_O P=$BG_P
t0=$EPOCHREALTIME
a=$(env "${IENV[@]}" FVDLG_NOTTY=default "$BASH" "$CMD" --stdout --inputbox N 0 0 first 2>"$TMP/m.err" </dev/null)
r=$?
t1=$EPOCHREALTIME
us=$(( 10#${t1/./} - 10#${t0/./} ))
bg_read "$M"
kt_test_start "a second call meanwhile (--stdout into \$(…)): answered at once ($(( us / 1000 )) ms), stderr empty, no second writer (the marker unchanged)"
if [[ $r == 0 && $a == first && ! -s $TMP/m.err && $BG_O == "$O" && $BG_P == "$P" ]] && (( us < 8000000 )); then kt_test_pass ok
else kt_test_fail "rc=$r out=[$a] err=[$(head -c 300 "$TMP/m.err")] marker=[$BG_O $BG_P] was [$O $P] us=$us"; fi
n=1200
while (( n-- > 0 )) && [[ -e $M ]]; do sleep 0.1; done
kill -0 "$P" 2>/dev/null; alive=$?
img_nonce
kt_test_start "the writer ended by itself (marker gone, pid gone) and left the image; the next start would hit"
if [[ ! -e $M && $alive != 0 && -n $IMG ]] && probe; then kt_test_pass ok
else kt_test_fail "marker=$([[ -e $M ]] && echo left || echo gone) alive=$alive img=[$IMG]"; fi
N0=$NONCE

kt_test_section "013: hits answer as the plain load does"

# same CASE-TITLE [ENV=V...] -- ARG... : the call through the image, then
# with KBOOL_IMAGE=off; status, stdout, stderr equal (FRAMES: the headless
# frame file is compared too)
same() {
    local title=$1 ri oi ei fi="" fo=""
    shift
    local -a pre=()
    while (( $# )) && [ "$1" != -- ]; do pre+=("$1"); shift; done
    shift
    local -a args=("$@")
    run img "${pre[@]}" -- "${args[@]//@FRAMES@/$TMP/f.img}"
    ri=$R_RC oi=$R_OUT ei=$R_ERR
    run off "${pre[@]}" -- "${args[@]//@FRAMES@/$TMP/f.off}"
    if [[ " ${args[*]} " == *@FRAMES@* ]]; then
        { IFS= read -r -d '' fi || :; } < "$TMP/f.img"
        { IFS= read -r -d '' fo || :; } < "$TMP/f.off"
    fi
    kt_test_start "$title: the image start answers as the plain load (status $R_RC)"
    if [[ $ri == "$R_RC" && $oi == "$R_OUT" && $ei == "$R_ERR" && $fi == "$fo" ]] && [[ " ${args[*]} " != *@FRAMES@* || -n $fi ]]; then kt_test_pass ok
    else kt_test_fail "img: rc=$ri out=[$oi] err=[${ei:0:200}] | off: rc=$R_RC out=[$R_OUT] err=[${R_ERR:0:200}] | frames $([[ $fi == "$fo" ]] && echo equal || echo differ)"; fi
}
same "inputbox, no terminal, FVDLG_NOTTY=default, --stdout" FVDLG_NOTTY=default -- --stdout --inputbox N 0 0 val
same "yesno, --no-tty=default" -- --no-tty=default --yesno Sure 0 0
same "yesno --defaultno, --no-tty=default (status 1)" -- --no-tty=default --defaultno --yesno Sure 0 0
same "checklist, --no-tty=default (whiptail's quoted form on stderr)" -- --no-tty=default --checklist Pick 0 0 0 a A on b B off 'my app' M on
same "menu --default-item b, --output-fd 1" -- --no-tty=default --output-fd 1 --menu Pick 0 0 0 a A b B --default-item b
same "msgbox headless, Enter, the frames" -- --fv-headless --fv-keys "$TMP/enter.keys" --fv-out @FRAMES@ --title T --msgbox 'Hello\nworld' 0 0
same "menu headless, Down Enter, the frames" -- --fv-headless --fv-keys "$TMP/down.keys" --fv-out @FRAMES@ --menu Pick 0 0 0 a A b B c C
same "inputbox headless, typed text, the frames" -- --fv-headless --fv-keys "$TMP/xy.keys" --fv-out @FRAMES@ --inputbox Name 0 0 ab
same "a usage error (inputbox without its size): 255 and one line" -- --no-tty=default --inputbox Name
img_nonce
bg_marker
kt_test_start "every call above was a hit: the image not written again (its nonce), no writer started"
if [[ -n $N0 && $NONCE == "$N0" && -z $BG_M ]]; then kt_test_pass ok; else kt_test_fail "nonce [$N0] -> [$NONCE] marker=[$BG_M]"; fi

kt_test_section "013: no writer left"
bg_guard
kt_test_start "every background writer of this file ended (none killed by the guard)"
if [[ -z $BG_LEFT ]]; then kt_test_pass ok; else kt_test_fail "leftover writer(s):$BG_LEFT"; fi
BG_LEFT="" BG_SEEN=()

kt_test_log "013_Image.sh completed"
