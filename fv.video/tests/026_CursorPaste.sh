#!/usr/bin/env bash
# 026_CursorPaste.sh - P3 stage 3d's terminal parts (design P3 §2.5, §4.5;
# rows 10.7, 10.8, 10.9):
#   * 10.7 the cursor shape: updateScreen sends DECSCUSR (ESC [ 4 SP q
#     underline for type 1, ESC [ 2 SP q block for 2 and 3, D27) when the
#     shape it sent last differs (a forced frame and a new screen send it
#     again); the restore sends ESC [ 0 SP q (the terminal's default shape)
#     only when a shape was sent since initVideo;
#   * 10.8 bracketed paste: initVideo sends ESC [ ? 2004 h after the screen
#     is cleared, every exit path ESC [ ? 2004 l (fvv_pty's restore check
#     holds it for every pty test of the suites); a paste typed into the pty
#     is ONE event, evCommand cmPasteText with the text (a newline in it is
#     no kbEnter), also when its frame comes in two pieces;
#   * 10.9 fv.video.setClipboard: OSC 52 (ESC ] 52 ; c ; BASE64 BEL) with
#     RFC 4648's vectors, UTF-8 and raw bytes; no fd: rc 1, nothing sent;
#     a wrong count: rc 2.
#   Exit paths on a real pty under util-linux script(1) (SKIP with reason ENV
#   elsewhere): doneVideo, exit without doneVideo (the EXIT trap), an error
#   under set -e, SIGTERM, Ctrl+C.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

E=$'\e'
kt_test_section "026: the cursor shape, bracketed paste, OSC 52"

# --- 10.7 headless: what updateScreen sends ----------------------------------------
# frame -> REPLY = what one updateScreen wrote
frame() {
    local f=$FVV_TMP/frame.out fd
    exec {fd}>"$f"
    FV_VIDEO_OUT_FD=$fd fv.video.updateScreen
    exec {fd}>&-
    REPLY=$(<"$f")
}
fv.video.initScreen 10 3
frame
kt_test_start "a hidden cursor sends no shape"
if [[ $REPLY != *' q'* ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
kt_test_start "type 1 shown: ESC [ 4 SP q (underline, insert), then the position and ?25h; the shape kept as sent"
fv.video.setCursorPos 2 1; fv.video.setCursorType 1; frame
if [[ $REPLY == "${E}[4 q${E}[2;3H${E}[?25h" && $__FV_VS_SSHP == 4 && $__FV_VI_CSHP == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY") sshp=$__FV_VS_SSHP"; fi
kt_test_start "the same type again, the cursor moved: no shape, the position only"
fv.video.setCursorPos 3 1; frame
if [[ $REPLY == "${E}[2;4H" ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
kt_test_start "type 2 (block, overwrite): ESC [ 2 SP q once; type 3 (half block) is a block: nothing more"
fv.video.setCursorType 2; frame; a=$REPLY
fv.video.setCursorType 3; frame; b=$REPLY
if [[ $a == "${E}[2 q${E}[2;4H" && -z $b ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$a") / $(printf '%q' "$b")"; fi
kt_test_start "hidden, then shown with the shape it had: no shape sequence"
fv.video.setCursorType 0; frame; a=$REPLY
fv.video.setCursorType 2; frame; b=$REPLY
if [[ $a == "${E}[?25l" && $b == "${E}[2;4H${E}[?25h" ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$a") / $(printf '%q' "$b")"; fi
kt_test_start "a forced frame sends the shape again (the terminal is not known then)"
fv.video.setCursorType 1; frame
fv.video.writeStr 0 0 'x' 0
f=$FVV_TMP/frame.out; exec {fd}>"$f"; FV_VIDEO_OUT_FD=$fd fv.video.updateScreen force; exec {fd}>&-; REPLY=$(<"$f")
if [[ $REPLY == *"${E}[4 q${E}[2;4H${E}[?25h" ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
kt_test_start "a new screen (initScreen) forgets the shape sent: the next shown cursor sends it"
fv.video.initScreen 10 3
fv.video.setCursorPos 0 0; fv.video.setCursorType 1; frame
if [[ $REPLY == *"${E}[4 q"* ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
kt_test_start "the VT model reads DECSCUSR (VT_SHP) and the frame still compares equal"
vt_init 10 3
fv.video.setCursorType 2; fv.video.writeStr 1 1 'ab' 0
f=$FVV_TMP/frame.out; exec {fd}>"$f"; FV_VIDEO_OUT_FD=$fd fv.video.updateScreen force; exec {fd}>&-; REPLY=$(<"$f")
if vt_feed "$REPLY" && [[ $VT_SHP == 2 && $VT_VIS == h ]]; then kt_test_pass "ok"; else kt_test_fail "shp=$VT_SHP vis=$VT_VIS $VT_ERR"; fi

# --- the restore's sequence (headless: a fake TUI of this process on a file) ---------
# restore CSHP -> REPLY = what fv.video._restore wrote
restore() {
    local f=$FVV_TMP/restore.out pf
    : > "$f"
    exec {pf}<>"$f"
    __FV_VI_ACT=1 __FV_VI_PID=$BASHPID __FV_VI_FD=$pf __FV_VI_SAVED='' __FV_VI_KPUSH=0 __FV_VI_CSHP=$1 __FV_VI_ALT=1
    __FV_VI_KSET=1 __FV_VI_KFD=0 __FV_VI_RMODE=0 __FV_VI_RPID='' __FV_VI_RFD='' __FV_VI_WPID='' __FV_VI_WFD=''
    fv.video._restore
    REPLY=$(<"$f")
}
kt_test_start "the restore after a shape: ?2004l with the mouse off, then ESC [ 0 SP q; the state cleared"
restore 1
if [[ $REPLY == *"${E}[?1000l${E}[?2004l${E}[0 q" && $__FV_VI_CSHP == 0 && -z $__FV_VS_SSHP ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
kt_test_start "the restore with no shape sent: ?2004l, no ESC [ 0 SP q"
restore 0
if [[ $REPLY == *"${E}[?1000l${E}[?2004l" && $REPLY != *' q'* ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$REPLY")"; fi
FV_KEY_FD=0

# --- 10.9 OSC 52 ------------------------------------------------------------------------
# osc TEXT -> REPLY = what setClipboard wrote, R = its rc
osc() {
    local f=$FVV_TMP/osc.out fd
    exec {fd}>"$f"
    R=0
    FV_VIDEO_OUT_FD=$fd fv.video.setClipboard "$1" || R=$?
    exec {fd}>&-
    REPLY=$(<"$f")
}
kt_test_start "OSC 52 with RFC 4648's base64 vectors ('' f fo foo foob fooba foobar)"
bad=''
for v in ':' 'f:Zg==' 'fo:Zm8=' 'foo:Zm9v' 'foob:Zm9vYg==' 'fooba:Zm9vYmE=' 'foobar:Zm9vYmFy'; do
    osc "${v%%:*}"
    [[ $R == 0 && $REPLY == "${E}]52;c;${v#*:}"$'\a' ]] || bad+=" [${v%%:*}]=$(printf '%q' "$REPLY")"
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi
kt_test_start "OSC 52 of UTF-8 text (Cyrillic, CJK, a flag) and of raw bytes: their bytes"
bad=''
osc 'Привет'; [[ $REPLY == "${E}]52;c;0J/RgNC40LLQtdGC"$'\a' ]] || bad+=" cyr=$(printf '%q' "$REPLY")"
osc '中文 🇺🇸 x'; [[ $REPLY == "${E}]52;c;5Lit5paHIPCfh7rwn4e4IHg="$'\a' ]] || bad+=" cjk=$(printf '%q' "$REPLY")"
osc $'\xff\x80'; [[ $REPLY == "${E}]52;c;/4A="$'\a' ]] || bad+=" bytes=$(printf '%q' "$REPLY")"
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi
# ref TEXT -> REPLY = TEXT's base64 the plain way (a byte at a time, the C
# locale): the reference for _b64's pieces
ref() {
    local LC_ALL=C t=$1 i=0 n x y z v o='' k=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
    n=${#t}
    while (( i < n )); do
        printf -v x '%d' "'${t:i:1}"; y=0 z=0
        if (( i + 1 < n )); then printf -v y '%d' "'${t:i+1:1}"; fi
        if (( i + 2 < n )); then printf -v z '%d' "'${t:i+2:1}"; fi
        v=$(( (x & 255) << 16 | (y & 255) << 8 | (z & 255) ))
        o+=${k:v>>18:1}${k:v>>12&63:1}
        if (( i + 1 < n )); then o+=${k:v>>6&63:1}; else o+='='; fi
        if (( i + 2 < n )); then o+=${k:v&63:1}; else o+='='; fi
        i=$(( i + 3 ))
    done
    REPLY=$o
}
kt_test_start "F3: _b64 walks in pieces (3072 / 96 bytes): mixed texts of 95..6200 bytes == the byte-at-a-time reference, padding included"
bad=''
mix=$'aж中🇺🇸\xff\x80 é'
printf -v blk '%800s' ''; blk=${blk// /"$mix"}
bslice() { local LC_ALL=C; u=${blk:0:$1}; }
for n in 95 96 97 3071 3072 3073 3074 3168 6200; do
    bslice "$n"
    fv.video._b64 "$u"; got=$__fvv_b
    ref "$u"
    [[ $got == "$REPLY" ]] || bad+=" n=$n"
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi
kt_test_start "F3: OSC 52 capped at FV_PASTE_MAX bytes, an incomplete UTF-8 sequence at the cut dropped (7 of жжжж -> жжж); default 65536"
osc_cap() { local FV_PASTE_MAX=$1; osc "$2"; }
osc_cap 7 'жжжж'; a=$REPLY
printf -v big '%70000s' ''; big=${big// /a}
osc "$big"; b=${#REPLY}
if [[ $a == "${E}]52;c;0LbQttC2"$'\a' && $b == $(( 87384 + 8 )) ]]; then kt_test_pass "ok"; else kt_test_fail "$(printf '%q' "$a") $b"; fi
kt_test_start "F3: linear: a 128 KB text (65536 Cyrillic letters; the default cap encodes its first 64 KiB) in under 3 s (0.6 s on an idle Git-bash laptop, 1.1-1.4 s throttled; the old walk: 64 KiB ~12 s, 128 KB 48 s)"
printf -v big '%65536s' ''; big=${big// /ж}
fvv_t0=$EPOCHREALTIME
fv.video._b64 "$big"
fvv_t1=$EPOCHREALTIME
ms=$(( ( ${fvv_t1%[.,]*} * 1000000 + 10#${fvv_t1##*[.,]} - ${fvv_t0%[.,]*} * 1000000 - 10#${fvv_t0##*[.,]} ) / 1000 ))
if (( ${#__fvv_b} == 87384 && ms < 3000 )); then kt_test_pass "$ms ms"; else kt_test_fail "${#__fvv_b} chars in $ms ms"; fi
unset big blk
kt_test_start "setClipboard: no output fd -> rc 1 and nothing; a wrong count -> rc 2; RESULT ''"
r=0; RESULT=x; FV_VIDEO_OUT_FD='' FV_TTY_FD='' fv.video.setClipboard 'a' 2>/dev/null || r=$?; a="$r:$RESULT"
r=0; RESULT=x; fv.video.setClipboard 2>/dev/null || r=$?; b="$r:$RESULT"
r=0; RESULT=x; fv.video.setClipboard a b 2>/dev/null || r=$?; c="$r:$RESULT"
if [[ $a == '1:' && $b == '2:' && $c == '2:' ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b $c"; fi

# --- on a pty --------------------------------------------------------------------------
# count NAME TEXT — REPLY = how many times TEXT occurs in the typescript
count() {
    local ts n=0
    fvp_ts "$1"; ts=$REPLY
    while [[ $ts == *"$2"* ]]; do ts=${ts#*"$2"}; n=$(( n + 1 )); done
    REPLY=$n
}
REC='printf "%s" "$__FV_VI_RPID" > "$D/rpid"; printf "%s" "$__FV_VI_WPID" > "$D/rpidw"'
# (a screen and a shown cursor: underline, then block)
SHAPE='fv.video.initScreen
fv.video.setCursorPos 1 1; fv.video.setCursorType 1; fv.video.updateScreen
fv.video.setCursorType 2; fv.video.updateScreen'
LOOP='
: > "$D/ready"
while fv.drivers.getEvent; do
    if [[ $FV_EV_WHAT == evKeyDown && $FV_EV_CHAR == q ]]; then break; fi
    if [[ $FV_EV_WHAT == evKeyDown ]]; then note "key $FV_EV_KEY"; fi
    if [[ $FV_EV_WHAT == evCommand ]]; then note "cmd $FV_EV_COMMAND $FV_EV_ID [${FV_EV_INFO//$'"'\n'"'/|}]"; fi
done'
DONE='
fv.video.doneVideo
exit 0'

TITLES=("doneVideo: ?2004h after the screen is cleared, the shapes underline then block, then ?2004l and ESC [ 0 SP q; restored"
    "doneVideo with no cursor shape sent: ?2004l, no ESC [ 0 SP q"
    "exit without doneVideo after a shape: the EXIT trap sends ?2004l and ESC [ 0 SP q (status 3)"
    "an error under set -e after a shape: the EXIT trap restores (status 1)"
    "SIGTERM after a shape: restored (status 143)"
    "Ctrl+C typed after a shape: restored (status 130)"
    "a paste typed into the pty: ONE evCommand cmPasteText with the text, its newline no kbEnter; then a key"
    "a paste whose frame comes in two pieces: still one cmPasteText")

run_pty() {
ptycheck() {
    local bad=''
    fvp_file "$1" rc
    [[ $REPLY == "$2" ]] || bad+=" rc=$REPLY"
    fvp_restored "$1" || bad+=" $REPLY"
    fvp_file "$1" log
    BAD=$bad
}
fvp_case done "fv.video.initVideo || exit 91
$REC
$SHAPE
$LOOP
$DONE"
fvp_run done ready sleep:0.2 'type:q'
kt_test_start "${TITLES[0]}"
ptycheck done 0
fvp_ts done; ts=$REPLY
count done "${E}[?2004h"; nh=$REPLY; count done "${E}[0 q"; nz=$REPLY
if [[ -z $BAD && $nh == 1 && $nz == 1 && $ts == *"${E}[2J${E}[?2004h"*"${E}[4 q"*"${E}[2 q"*"${E}[?2004l${E}[0 q"* ]]; then kt_test_pass "ok"
else kt_test_fail "$BAD ?2004h=$nh [0 q=$nz"; fi

fvp_case noshape "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run noshape ready sleep:0.2 'type:q'
kt_test_start "${TITLES[1]}"
ptycheck noshape 0
count noshape "${E}[0 q"; nz=$REPLY
if [[ -z $BAD && $nz == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD [0 q=$nz"; fi

fvp_case exit3 "fv.video.initVideo || exit 91
$REC
$SHAPE
: > \"\$D/ready\"
exit 3"
fvp_run exit3 ready
kt_test_start "${TITLES[2]}"
ptycheck exit3 3
fvp_ts exit3; ts=$REPLY
if [[ -z $BAD && $ts == *"${E}[?2004l${E}[0 q"* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD"; fi

fvp_case err "set -e
fv.video.initVideo || exit 91
$REC
$SHAPE
: > \"\$D/ready\"
false
note 'not reached'"
fvp_run err ready
kt_test_start "${TITLES[3]}"
ptycheck err 1; l=$REPLY
fvp_ts err; ts=$REPLY
if [[ -z $BAD && $ts == *"${E}[?2004l${E}[0 q"* && $l != *'not reached'* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD log=[$l]"; fi

fvp_case term "fv.video.initVideo || exit 91
$REC
$SHAPE
$LOOP
$DONE"
fvp_run term ready sleep:0.3 sig:TERM
kt_test_start "${TITLES[4]}"
ptycheck term 143
fvp_ts term; ts=$REPLY
if [[ -z $BAD && $ts == *"${E}[?2004l${E}[0 q"* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD"; fi

fvp_case int "fv.video.initVideo || exit 91
$REC
$SHAPE
$LOOP
$DONE"
fvp_run int ready sleep:0.3 'type:\x03'
kt_test_start "${TITLES[5]}"
ptycheck int 130
fvp_ts int; ts=$REPLY
if [[ -z $BAD && $ts == *"${E}[?2004l${E}[0 q"* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD"; fi

fvp_case paste "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run paste ready sleep:0.2 'type:\e[200~ab\rcd\e[201~' sleep:0.3 'type:x' sleep:0.2 'type:q'
kt_test_start "${TITLES[6]}"
ptycheck paste 0; l=$REPLY
if [[ -z $BAD && $l == *'cmd cmPasteText 5 [ab'?'cd]'*'key kbChar'* && $l != *kbEnter* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD log=[${l//$'\n'/|}]"; fi

fvp_case split "fv.video.initVideo || exit 91
$REC
$LOOP
$DONE"
fvp_run split ready sleep:0.2 'type:\e[200~ab' sleep:0.4 'type:cd\e[201~' sleep:0.3 'type:q'
kt_test_start "${TITLES[7]}"
ptycheck split 0; l=$REPLY
if [[ -z $BAD && $l == *'cmd cmPasteText 4 [abcd]'* && $l != *'key '* ]]; then kt_test_pass "ok"; else kt_test_fail "$BAD log=[${l//$'\n'/|}]"; fi
}

if fvp_detect; then run_pty; else fvv_skip "${TITLES[@]}"; fi

kt_test_log "026_CursorPaste.sh completed"
