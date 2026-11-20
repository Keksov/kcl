#!/usr/bin/env bash
# 011_Replies.sh - the replies to fv.video's queries are no keys (design P3
# §14.4): the kitty reply CSI ? FLAGS u and the DA1 reply CSI ? ... c
#   * produce no key on any entry point (decode, getKeyEvent blocking / with
#     a timeout / 0, pollKeyEvent), the key after them comes in their place;
#   * set __FV_KB_KITTY (the flags; 0 counts) and __FV_KB_DA1;
#   * a reader runs the hook __FV_KB_ONKITTY on each kitty reply, decode
#     never; no hook set: nothing runs;
#   * a reply alone: getKeyEvent with a timeout answers rc 1 (no key, not end
#     of file) without waiting a second time; a blocking getKeyEvent waits
#     for the key after it;
#   * replies arriving between typed keys (mid-typing) keep the keys' order;
#   * malformed replies are kbUnknown, consumed exactly;
#   * long DA1 replies (Windows Terminal 33 / 36 parameter bytes, xterm
#     decTerminalID 525 37: past the decoder's 32-byte cap) are replies on
#     every reader path (decode, getKeyEvent 0, pollKeyEvent, blocking, timed,
#     split across reads within the Esc timeout, before and past the cap);
#     long CSIs that are no reply are kbUnknown, consumed exactly; a run of
#     256 bytes with no final byte ends there.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: replies are not keys"

E=$'\e'
HOOKS=0
hook() { HOOKS=$(( HOOKS + 1 )); }
fresh() { __FV_KB_KITTY=-1 __FV_KB_DA1=0 HOOKS=0; fv.keyboard.flush; }
keys() {
    local -n __o=$1
    __o=''
    while fv.keyboard.getKeyEvent 0; do __o+="$FV_KEY:$FV_KEY_CHAR|"; done
    __o=${__o%|}
}
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd

kt_test_start "decode: a kitty reply alone is no key (rc 1, kbNoKey) and sets __FV_KB_KITTY; the hook does not run"
fresh; __FV_KB_ONKITTY=hook
fv.keyboard.decode "${E}[?5u"; r="$?:$FV_KEY:$__FV_KB_KITTY:$__FV_KB_DA1:$HOOKS"
if [[ $r == 1:kbNoKey:5:0:0 ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "decode: flags 0 count as a kitty reply; the DA1 reply sets __FV_KB_DA1"
fresh
fv.keyboard.decode "${E}[?0u"; r="$__FV_KB_KITTY"
fv.keyboard.decode "${E}[?62;22c"; r+=":$?:$FV_KEY:$__FV_KB_DA1"
fv.keyboard.decode "${E}[?1;2c"; r+=":$?:$__FV_KB_DA1"
fv.keyboard.decode "${E}[?6c"; r+=":$?"
if [[ $r == 0:1:kbNoKey:1:1:1:1 ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "decode: the key after the replies, FV_KEY_SEQ / FV_KEY_LEN its own"
fresh
fv.keyboard.decode "${E}[?5u${E}[?62;22c${E}[1;5D"; r="$?:$FV_KEY:$FV_KEY_LEN:$__FV_KB_KITTY:$__FV_KB_DA1"
fvk_vis "$FV_KEY_SEQ"; r+=":$REPLY"
if [[ $r == "0:kbCtrlLeft:6:5:1:\$'\\E[1;5D'" ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "getKeyEvent 0 / pollKeyEvent: replies between typed keys produce nothing, the keys keep their order"
fresh; __FV_KB_ONKITTY=hook
fv.keyboard.feed "a${E}[?5ub${E}[?62;22c${E}[?5uc"
keys got
r="$got|$__FV_KB_KITTY|$__FV_KB_DA1|$HOOKS"
if [[ $r == 'kbChar:a|kbChar:b|kbChar:c|5|1|2' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "pollKeyEvent peeks past a reply (consumed), the next getKeyEvent returns the peeked key"
fresh; __FV_KB_ONKITTY=hook
fv.keyboard.feed "${E}[?1uq"
fv.keyboard.pollKeyEvent; r="$?:$FV_KEY:$FV_KEY_CHAR:$HOOKS"
fv.keyboard.getKeyEvent 0; r+=" $?:$FV_KEY:$FV_KEY_CHAR:$HOOKS"
fv.keyboard.getKeyEvent 0; r+=" $?"
if [[ $r == '0:kbChar:q:1 0:kbChar:q:1 1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "pollKeyEvent with only a reply waiting: rc 1, the reply consumed, the hook ran once"
fresh; __FV_KB_ONKITTY=hook
fv.keyboard.feed "${E}[?5u"
fv.keyboard.pollKeyEvent; r="$?:$FV_KEY:$HOOKS"
fv.keyboard.pollKeyEvent; r+=" $?:$HOOKS"
if [[ $r == '1:kbNoKey:1 1:1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "no hook set: a kitty reply runs nothing and is still no key"
fresh; __FV_KB_ONKITTY=''
fv.keyboard.feed "${E}[?5ux"
keys got
if [[ $got == kbChar:x && $__FV_KB_KITTY == 5 ]]; then kt_test_pass "$got"; else kt_test_fail "got $got kitty=$__FV_KB_KITTY"; fi

kt_test_start "getKeyEvent T with only a reply: rc 1 (no key, FV_KEY_EOF 0), no second wait"
fresh; __FV_KB_ONKITTY=hook
mkfifo "$FVK_TMP/fifo" 2>/dev/null || :
if [[ -p $FVK_TMP/fifo ]]; then
    exec {wfd}<>"$FVK_TMP/fifo"
    printf '%s' "${E}[?5u" >&$wfd
    FV_KEY_FD=$wfd
    b=$EPOCHREALTIME
    fv.keyboard.getKeyEvent 0.3; r="$?:$FV_KEY:$FV_KEY_EOF:$HOOKS"
    e=$EPOCHREALTIME
    ms=$(( ( ${e%[.,]*} * 1000000 + 10#${e##*[.,]} - ${b%[.,]*} * 1000000 - 10#${b##*[.,]} ) / 1000 ))
    exec {wfd}>&-
    FV_KEY_FD=$nullfd
    if [[ $r == 1:kbNoKey:0:1 ]] && (( ms < 290 )); then kt_test_pass "$r in $ms ms"; else kt_test_fail "got $r in $ms ms"; fi
else
    kt_test_pass "SKIP: no mkfifo here"
fi

kt_test_start "a reply alone on a live pipe: getKeyEvent 0 and pollKeyEvent answer rc 1 at once, never block"
if [[ -p $FVK_TMP/fifo ]] && kt_need_timeout; then
    out="$("$KT_TIMEOUT" -k 2 20 bash -c "
source '$FVK_TESTS_DIR/../fv.keyboard.sh' 2>/dev/null
exec {w}<>'$FVK_TMP/fifo'
FV_KEY_FD=\$w
printf '%s' \$'\\e[?5u' >&\$w
fv.keyboard.getKeyEvent 0; r=\"\$?:\$FV_KEY:\$__FV_KB_KITTY\"
printf '%s' \$'\\e[?3u' >&\$w
fv.keyboard.pollKeyEvent; r+=\" \$?:\$FV_KEY:\$__FV_KB_KITTY\"
printf '%s' \$'\\e[?2ux' >&\$w
fv.keyboard.getKeyEvent 0; r+=\" \$?:\$FV_KEY:\$FV_KEY_CHAR:\$__FV_KB_KITTY\"
printf '%s' \"\$r\"" 2>&1)"
    if [[ $out == '1:kbNoKey:5 1:kbNoKey:3 0:kbChar:x:2' ]]; then kt_test_pass "$out"; else kt_test_fail "got [$out] (rc 124 = it blocked)"; fi
else
    kt_test_pass "SKIP: no mkfifo / timeout here"
fi

kt_test_start "a blocking getKeyEvent after a reply waits for the key after it (a file fd: reply, then the key)"
fresh; __FV_KB_ONKITTY=hook
fvk_fdfile "${E}[?5u${E}[?62;1c${E}[102;3u"
fv.keyboard.getKeyEvent; r="$?:$FV_KEY:$FV_KEY_BASE:$HOOKS:$__FV_KB_DA1"
fv.keyboard.getKeyEvent; r+=" $?:$FV_KEY_EOF"
FV_KEY_FD=$nullfd
if [[ $r == '0:kbAltF:f:1:1 1:1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "the hook runs in the reader's own shell (it can set the caller's state)"
fresh; __FV_KB_ONKITTY=hook
fv.keyboard.feed "${E}[?7u"
fv.keyboard.getKeyEvent 0
if (( HOOKS == 1 )) && [[ $__FV_KB_KITTY == 7 ]]; then kt_test_pass "ok"; else kt_test_fail "hooks=$HOOKS kitty=$__FV_KB_KITTY"; fi
__FV_KB_ONKITTY=''

# --- malformed replies ----------------------------------------------------------------------
kt_test_start "malformed replies are kbUnknown, consumed exactly, __FV_KB_KITTY untouched (an empty CSI ? c counts as DA1)"
fresh
fv.keyboard.feed "${E}[?5;1u${E}[?u${E}[?123456u${E}[?6:2c${E}[?ck"
keys got
r="$got|$__FV_KB_KITTY|$__FV_KB_DA1"
if [[ $r == 'kbUnknown:|kbUnknown:|kbUnknown:|kbUnknown:|kbChar:k|-1|1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "DA2-looking CSI > ... c stays a key (kbUnknown): only the replies to what fv.video asks are swallowed"
fresh
fv.keyboard.decode "${E}[>1;10;0c"; r="$?:$FV_KEY:$__FV_KB_DA1"
if [[ $r == 0:kbUnknown:0 ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi


# --- long DA1 replies (more than _csi's 32 parameter bytes) --------------------------------
# Windows Terminal (33 and 36 parameter bytes), xterm with decTerminalID 525 (37)
LONG=('?61;4;6;7;14;21;22;23;24;28;32;42c' '?61;4;6;7;14;21;22;23;24;28;32;42;52c'
    '?65;1;2;6;9;15;16;17;18;21;22;28;29c')
LONGIN="a${E}[${LONG[0]}b${E}[${LONG[1]}c${E}[${LONG[2]}d"

kt_test_start "decode: each long DA1 reply is no key, the key after it in its place (FV_KEY_SEQ its own)"
r=''
for l in "${LONG[@]}"; do
    fresh
    fv.keyboard.decode "${E}[${l}"; r+="[$?:$FV_KEY:$__FV_KB_DA1"
    fresh
    fv.keyboard.decode "${E}[${l}${E}[1;5D"; r+=" $?:$FV_KEY:$FV_KEY_LEN:$__FV_KB_DA1]"
done
want='[1:kbNoKey:1 0:kbCtrlLeft:6:1][1:kbNoKey:1 0:kbCtrlLeft:6:1][1:kbNoKey:1 0:kbCtrlLeft:6:1]'
if [[ $r == "$want" ]]; then kt_test_pass "$r"; else kt_test_fail "got  $r"$'\n'"want $want"; fi

kt_test_start "getKeyEvent 0: the three long replies between typed keys produce nothing (no key leaks out of them)"
fresh
fv.keyboard.feed "$LONGIN"
keys got
if [[ $got == 'kbChar:a|kbChar:b|kbChar:c|kbChar:d' && $__FV_KB_DA1 == 1 ]]; then kt_test_pass "$got"; else kt_test_fail "got $got da1=$__FV_KB_DA1"; fi

kt_test_start "pollKeyEvent peeks past a long reply (consumed), getKeyEvent returns the peeked key"
r=''
for l in "${LONG[@]}"; do
    fresh
    fv.keyboard.feed "${E}[${l}q"
    fv.keyboard.pollKeyEvent; r+="[$?:$FV_KEY_CHAR"
    fv.keyboard.getKeyEvent 0; r+=" $?:$FV_KEY_CHAR"
    fv.keyboard.getKeyEvent 0; r+=" $?]"
done
if [[ $r == '[0:q 0:q 1][0:q 0:q 1][0:q 0:q 1]' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a blocking getKeyEvent on a file fd: the long replies and the keys around them, then end of file"
fresh
fvk_fdfile "$LONGIN"
got=''
while fv.keyboard.getKeyEvent; do got+="$FV_KEY_CHAR"; done
r="$got:$FV_KEY_EOF:$__FV_KB_DA1"
FV_KEY_FD=$nullfd
if [[ $r == 'abcd:1:1' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a timed getKeyEvent on a pipe: a long reply then a key: the key, at once"
if [[ -p $FVK_TMP/fifo ]]; then
    fresh
    exec {wfd}<>"$FVK_TMP/fifo"
    FV_KEY_FD=$wfd
    r=''
    for l in "${LONG[@]}"; do
        printf '%s' "${E}[${l}k" >&$wfd
        fv.keyboard.getKeyEvent 0.5; r+="[$?:$FV_KEY_CHAR]"
    done
    fv.keyboard.getKeyEvent 0.05; r+="[$?]"
    exec {wfd}>&-
    FV_KEY_FD=$nullfd
    if [[ $r == '[0:k][0:k][0:k][1]' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi
else
    kt_test_pass "SKIP: no mkfifo here"
fi

kt_test_start "a long reply split across reads (the rest within the Esc timeout): no key, the key after it"
if [[ -p $FVK_TMP/fifo ]]; then
    fresh
    exec {wfd}<>"$FVK_TMP/fifo"
    FV_KEY_FD=$wfd
    r=''
    for l in "${LONG[@]}" "${LONG[@]}"; do
        # a cut before the 32-byte cap, then one inside the long part; the rest
        # 50 ms later (the Esc timeout 1 s here)
        if (( ${#r} < 30 )); then n=18; else n=$(( ${#l} - 2 )); fi
        printf '%s' "x${E}[${l:0:n}" >&$wfd
        ( sleep 0.05; printf '%s' "${l:n}y" >&$wfd ) &
        sp=$!
        FV_ESC_TIMEOUT=1 fv.keyboard.getKeyEvent; r+="[$?:$FV_KEY_CHAR"
        FV_ESC_TIMEOUT=1 fv.keyboard.getKeyEvent; r+=" $?:$FV_KEY_CHAR:$__FV_KB_DA1]"
        wait "$sp" 2>/dev/null
        __FV_KB_DA1=0
    done
    exec {wfd}>&-
    FV_KEY_FD=$nullfd
    if [[ $r == '[0:x 0:y:1][0:x 0:y:1][0:x 0:y:1][0:x 0:y:1][0:x 0:y:1][0:x 0:y:1]' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi
else
    kt_test_pass "SKIP: no mkfifo here"
fi

kt_test_start "long CSIs that are no reply: kbUnknown, consumed exactly (a long ? ... u, a non-digit in a long ? ... c, another final byte, no ?)"
fresh
fv.keyboard.feed "${E}[?1234567890123456789012345678901234u${E}[?61;4;6;7;14;21;22;23;24;28;32:42c${E}[61;4;6;7;14;21;22;23;24;28;32;42c${E}[?61;4;6;7;14;21;22;23;24;28;32;42mk"
keys got
r="$got|$__FV_KB_KITTY|$__FV_KB_DA1"
if [[ $r == 'kbUnknown:|kbUnknown:|kbUnknown:|kbUnknown:|kbChar:k|-1|0' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "a long CSI cut by a byte outside the grammar: kbUnknown, the byte and the rest are keys; 256 bytes with no final byte: kbUnknown there"
fresh
p=''; for (( i = 0; i < 40; i++ )); do p+='1'; done
q=''; for (( i = 0; i < 300; i++ )); do q+='2'; done
fv.keyboard.feed "${E}[?${p}"$'\xd0\xb6'"k"
keys got
fv.keyboard.decode "${E}[${q}c"; r="$FV_KEY:$FV_KEY_LEN"
if [[ $got == 'kbUnknown:|kbChar:ж|kbChar:k' && $r == kbUnknown:258 ]]; then kt_test_pass "$got / $r"; else kt_test_fail "got $got / $r"; fi

__FV_KB_KITTY=-1 __FV_KB_DA1=0 __FV_KB_ONKITTY=''
kt_test_log "011_Replies.sh completed"
