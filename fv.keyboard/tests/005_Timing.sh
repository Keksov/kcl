#!/usr/bin/env bash
# 005_Timing.sh - the Esc timeout across a delayed writer: a lone Esc vs an
# Esc-prefixed Alt key vs Esc + a sequence (rxvt Alt-arrow), a sequence split
# across writes within the timeout (reassembled) and cut by it (kbUnknown, the
# rest decoded), getKeyEvent TIMEOUT and the poll forms on a live pipe with no
# data, and the default 0.02 s being applied at all.
#
# Bounds are generous (Windows `read -t` waits in 15.6 ms steps, runners are
# loaded): an upper bound is ~10x the expected time, never near the writer's
# gap. Writers are process substitutions that wait by busy-looping on
# EPOCHREALTIME — one process each, no `sleep` child that could outlive them;
# every writer's pid is recorded, waited for, and killed by the EXIT/INT/TERM
# trap if the file stops early.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: the Esc timeout across delayed writers"

FVK_PIDS=()
fvk_reap() {
    local p
    for p in "${FVK_PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
    FVK_PIDS=()
}
trap 'fvk_reap' EXIT
trap 'fvk_reap; exit 130' INT
trap 'fvk_reap; exit 143' TERM

fvk_now() { local e=$EPOCHREALTIME; REPLY=$(( ${e%[.,]*} * 1000000 + 10#${e##*[.,]} )); }
fvk_busy() {        # US — wait US microseconds without a child process
    local t0
    fvk_now; t0=$REPLY
    while fvk_now; (( REPLY - t0 < $1 )); do :; done
}
# fvk_writer FIRST GAP_US REST — FV_KEY_FD = a pipe that gets FIRST at once,
# REST after GAP_US (no REST: the pipe stays open until the writer ends)
fvk_writer() {
    if [[ -n ${FVK_WFD-} ]]; then exec {FVK_WFD}<&-; fvk_reap; fi
    # its stderr is dropped: a TERM from fvk_reap can land inside an expansion,
    # and bash then reports the cut-short arithmetic before it dies
    exec {FVK_WFD}< <({ printf '%s' "$1"; fvk_busy "$2"; printf '%s' "${3-}"; } 2>/dev/null)
    FVK_PIDS+=("$!")
    FV_KEY_FD=$FVK_WFD
    fv.keyboard.flush
}
fvk_done() { exec {FVK_WFD}<&-; FVK_WFD=''; fvk_reap; }
# fvk_get [ARGS] — getKeyEvent ARGS; R = "rc:key", MS = elapsed ms
fvk_get() {
    local t0 rc
    fvk_now; t0=$REPLY
    fv.keyboard.getKeyEvent "$@"; rc=$?
    fvk_now; MS=$(( (REPLY - t0) / 1000 ))
    R="$rc:$FV_KEY"
}

FV_ESC_TIMEOUT=0.05
kt_test_start "lone Esc: ESC, then nothing for 0.8 s -> kbEsc after the timeout (< 500 ms), then the late key"
fvk_writer $'\e' 800000 x
fvk_get; r1=$R m1=$MS
fvk_get; r2="$R:$FV_KEY_CHAR"
fvk_done
if [[ $r1 == 0:kbEsc && $r2 == 0:kbChar:x ]] && (( m1 < 500 )); then
    kt_test_pass "kbEsc after $m1 ms, then x"
else
    kt_test_fail "$r1 ($m1 ms) / $r2"
fi

kt_test_start "ESC x in one write is kbAltX, not Esc + x"
fvk_writer $'\ex' 0
fvk_get; r1="$R:$FV_KEY_CHAR"
fvk_done
if [[ $r1 == 0:kbAltX:x ]]; then kt_test_pass "$r1"; else kt_test_fail "$r1"; fi

kt_test_start "ESC ESC [ A in one write is kbAltUp (rxvt); ESC, a pause, ESC [ A is kbEsc + kbUp"
fvk_writer $'\e\e[A' 0
fvk_get; r1=$R
fvk_writer $'\e' 800000 $'\e[A'
fvk_get; r2=$R
fvk_get; r3=$R
fvk_done
if [[ $r1 == 0:kbAltUp && $r2 == 0:kbEsc && $r3 == 0:kbUp ]]; then kt_test_pass "ok"; else kt_test_fail "$r1 / $r2 / $r3"; fi

FV_ESC_TIMEOUT=3
kt_test_start "a CSI split across writes 0.2 s apart is reassembled (FV_ESC_TIMEOUT=3)"
fvk_writer $'\e[1;' 200000 5D
fvk_get; r1=$R
fvk_done
if [[ $r1 == 0:kbCtrlLeft ]]; then kt_test_pass "$r1"; else kt_test_fail "$r1"; fi

kt_test_start "an ESC and its [A written 0.2 s apart is kbUp, not kbEsc (FV_ESC_TIMEOUT=3)"
fvk_writer $'\e' 200000 '[A'
fvk_get; r1=$R
fvk_done
if [[ $r1 == 0:kbUp ]]; then kt_test_pass "$r1"; else kt_test_fail "$r1"; fi

kt_test_start "a UTF-8 character split across writes 0.2 s apart (FV_ESC_TIMEOUT=3)"
fvk_writer $'\xd0' 200000 $'\xb6'
fvk_get; r1="$R:$FV_KEY_CHAR"
fvk_done
if [[ $r1 == 0:kbChar:ж ]]; then kt_test_pass "ok"; else kt_test_fail "$r1"; fi

FV_ESC_TIMEOUT=0.05
kt_test_start "a CSI cut by the timeout: kbUnknown for ESC [ 1 ;, then the late bytes as keys"
fvk_writer $'\e[1;' 800000 5D
fvk_get; r1="$R:$FV_KEY_LEN" m1=$MS
fvk_get; r2="$R:$FV_KEY_CHAR"
fvk_get; r3="$R:$FV_KEY_CHAR"
fvk_done
if [[ $r1 == 0:kbUnknown:4 && $r2 == 0:kbChar:5 && $r3 == 0:kbChar:D ]] && (( m1 < 500 )); then
    kt_test_pass "ok ($m1 ms)"
else
    kt_test_fail "$r1 ($m1 ms) / $r2 / $r3"
fi

kt_test_start "getKeyEvent 0.1 on a live pipe with no data: rc 1 after ~0.1 s, FV_KEY_EOF=0; the key comes later"
fvk_writer '' 900000 q
fvk_get 0.1; r1="$R:$FV_KEY_EOF" m1=$MS
fvk_get; r2="$R:$FV_KEY_CHAR"
fvk_done
if [[ $r1 == 1:kbNoKey:0 && $r2 == 0:kbChar:q ]] && (( m1 >= 50 && m1 < 700 )); then
    kt_test_pass "rc 1 after $m1 ms, then q"
else
    kt_test_fail "$r1 ($m1 ms) / $r2"
fi

kt_test_start "getKeyEvent 0 and pollKeyEvent on a live pipe with no data: rc 1 at once, FV_KEY_EOF=0"
fvk_writer '' 900000
fvk_get 0; r1="$R:$FV_KEY_EOF" m1=$MS
fvk_now; t0=$REPLY
fv.keyboard.pollKeyEvent; r2="$?:$FV_KEY:$FV_KEY_EOF"
fvk_now; m2=$(( (REPLY - t0) / 1000 ))
fvk_done
if [[ $r1 == 1:kbNoKey:0 && $r2 == 1:kbNoKey:0 ]] && (( m1 < 300 && m2 < 300 )); then
    kt_test_pass "$m1 ms / $m2 ms"
else
    kt_test_fail "$r1 ($m1 ms) / $r2 ($m2 ms)"
fi

unset FV_ESC_TIMEOUT
kt_test_start "the default Esc timeout (0.02 s) is applied: a lone Esc takes >= 10 ms and < 500 ms"
fvk_writer $'\e' 800000 x
fvk_get; r1=$R m1=$MS
fvk_done
if [[ $r1 == 0:kbEsc ]] && (( m1 >= 10 && m1 < 500 )); then kt_test_pass "kbEsc after $m1 ms"; else kt_test_fail "$r1 ($m1 ms)"; fi

kt_test_log "005_Timing.sh completed"
