#!/usr/bin/env bash
# 014_Paste.sh - bracketed paste (design P3 §4.5, row 10.8): the frame
# ESC [ 200 ~ TEXT ESC [ 201 ~ is ONE key, kbPaste, TEXT in FV_KEY_CHAR (raw:
# newlines, CR, Tab and escape sequences inside stay text, never keys), the
# whole frame consumed (FV_KEY_SEQ / FV_KEY_LEN), the next key after it.
#   * decode, the queue (feed), a file fd, the queue + the fd (a frame split
#     between them), a delayed writer (a frame in two pieces, the end marker
#     itself split), a frame whose end never comes (it ends after the paste
#     wait __FV_KB_PT with the text so far; F7: what comes later is keys),
#     an incomplete frame in decode;
#   * FV_PASTE_MAX (default 65536 bytes): the rest read and dropped (one
#     debug line), an incomplete UTF-8 sequence at the cut dropped, the key
#     after it intact, head and tail of a cut never forge the end (F6); a
#     NUL byte inside is dropped; pollKeyEvent peeks it;
#     an ESC in front of the frame is a lone kbEsc, then the paste.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "014: bracketed paste"

E=$'\e' P0=$'\e[200~' P1=$'\e[201~'
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
# fvk_writer FIRST GAP_US [REST] — FV_KEY_FD = a pipe that gets FIRST at once,
# REST after GAP_US (no REST: the pipe stays open until the writer ends)
fvk_writer() {
    if [[ -n ${FVK_WFD-} ]]; then exec {FVK_WFD}<&-; fvk_reap; fi
    exec {FVK_WFD}< <({ printf '%s' "$1"; fvk_busy "$2"; printf '%s' "${3-}"; } 2>/dev/null)
    FVK_PIDS+=("$!")
    FV_KEY_FD=$FVK_WFD
    fv.keyboard.flush
}
fvk_done() { exec {FVK_WFD}<&-; FVK_WFD=''; fvk_reap; }
# keys VAR — every key of the queue + fd (getKeyEvent 0): "name:char|..."
keys() {
    local -n __k_out=$1
    __k_out=''
    while fv.keyboard.getKeyEvent 0; do __k_out+="$FV_KEY:$FV_KEY_CHAR|"; done
    __k_out=${__k_out%|}
}

kt_test_start "decode: one kbPaste, the text in FV_KEY_CHAR, the whole frame consumed (LEN, SEQ)"
b="${P0}hello world${P1}"
fv.keyboard.decode "$b"
fvk_len "$b"
if [[ $FV_KEY == kbPaste && $FV_KEY_CHAR == 'hello world' && $FV_KEY_LEN == "$REPLY" && $FV_KEY_SEQ == "$b" && $RESULT == kbPaste ]]; then kt_test_pass "ok"
else kt_test_fail "key=$FV_KEY char=[$FV_KEY_CHAR] len=$FV_KEY_LEN"; fi

kt_test_start "newline, CR, Tab and an escape sequence inside the frame are text, not keys"
fv.keyboard.decode "${P0}a"$'\n'"b"$'\r'"c"$'\t'"d${E}[Ae${P1}"
if [[ $FV_KEY == kbPaste && $FV_KEY_CHAR == "a"$'\n'"b"$'\r'"c"$'\t'"d${E}[Ae" ]]; then kt_test_pass "ok"; else fvk_vis "$FV_KEY_CHAR"; kt_test_fail "$FV_KEY $REPLY"; fi

kt_test_start "an empty paste is kbPaste with no text; UTF-8 text comes as its bytes"
fv.keyboard.decode "${P0}${P1}"; a="$FV_KEY:[$FV_KEY_CHAR]"
fv.keyboard.decode "${P0}жи中🇺🇸${P1}"; b="$FV_KEY:[$FV_KEY_CHAR]"
if [[ $a == 'kbPaste:[]' && $b == 'kbPaste:[жи中🇺🇸]' ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b"; fi

kt_test_start "decode of a frame without its end: kbPaste with the text so far"
fv.keyboard.decode "${P0}abc"
if [[ $FV_KEY == kbPaste && $FV_KEY_CHAR == abc ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY [$FV_KEY_CHAR]"; fi

kt_test_start "the queue: a key before, the paste, keys after (the next key after the frame)"
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed "x${P0}a b${P1}y${E}[B"
keys got
if [[ $got == 'kbChar:x|kbPaste:a b|kbChar:y|kbDown:' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "a file fd: two pastes in a row, then a key"
fvk_fdfile "${P0}one${P1}${P0}two${P1}z"
keys got
if [[ $got == 'kbPaste:one|kbPaste:two|kbChar:z' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "a frame split between the queue and the fd: one kbPaste"
fvk_fdfile "cd${P1}z"
fv.keyboard.feed "${P0}ab"
keys got
if [[ $got == 'kbPaste:abcd|kbChar:z' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "the end marker split between the queue and the fd"
fvk_fdfile "01~q"
fv.keyboard.feed "${P0}ab${E}[2"
keys got
if [[ $got == 'kbPaste:ab|kbChar:q' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "a delayed writer: the frame in two pieces 0.3 s apart -> one kbPaste (getKeyEvent blocking)"
fvk_writer "${P0}ab" 300000 "cd${P1}x"
fv.keyboard.getKeyEvent; a="$FV_KEY:$FV_KEY_CHAR"
fv.keyboard.getKeyEvent; b="$FV_KEY:$FV_KEY_CHAR"
fvk_done
if [[ $a == kbPaste:abcd && $b == kbChar:x ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b"; fi

kt_test_start "a delayed writer: the end marker itself split (ESC [ 20 | 1 ~) -> one kbPaste, the next key"
fvk_writer "${P0}ab${E}[20" 300000 "1~q"
fv.keyboard.getKeyEvent; a="$FV_KEY:$FV_KEY_CHAR"
fv.keyboard.getKeyEvent; b="$FV_KEY:$FV_KEY_CHAR"
fvk_done
if [[ $a == kbPaste:ab && $b == kbChar:q ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b"; fi

kt_test_start "an ESC inside the text, then the rest: still one kbPaste"
fvk_writer "${P0}a${E}x" 200000 "b${P1}"
fv.keyboard.getKeyEvent; a="$FV_KEY:$FV_KEY_CHAR"
fvk_done
if [[ $a == "kbPaste:a${E}xb" ]]; then kt_test_pass "ok"; else fvk_vis "$a"; kt_test_fail "$REPLY"; fi

kt_test_start "a frame whose end never comes: kbPaste with the text so far after the paste wait (__FV_KB_PT 0.2 s), well before the writer ends"
fvk_writer "${P0}ab" 3000000
fvk_now; t0=$REPLY
__FV_KB_PT=0.2 fv.keyboard.getKeyEvent; a="$FV_KEY:$FV_KEY_CHAR"
fvk_now; ms=$(( (REPLY - t0) / 1000 ))
fvk_done
if [[ $a == kbPaste:ab ]] && (( ms < 2500 )); then kt_test_pass "$ms ms"; else kt_test_fail "$a in $ms ms"; fi

kt_test_start "F7: a frame that stalls past __FV_KB_PT (0.2 s; the rest 1.5 s later: margin for a loaded runner): kbPaste with the text so far, its tail then comes as keys (documented)"
fvk_writer "${P0}ab" 1500000 "cd${P1}x"
__FV_KB_PT=0.2 fv.keyboard.getKeyEvent; got="$FV_KEY:$FV_KEY_CHAR"
for _ in 1 2 3 4; do fv.keyboard.getKeyEvent 2 || break; got+="|$FV_KEY:$FV_KEY_CHAR"; done
fvk_done
if [[ $got == 'kbPaste:ab|kbChar:c|kbChar:d|kbUnknown:|kbChar:x' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "FV_PASTE_MAX: the text cut to its bytes, the rest dropped, one debug line, the next key intact"
fvk_fdfile "${P0}abcdefghijkl${P1}x"
err=$( VERBOSE_KKLASS=debug; FV_PASTE_MAX=8 fv.keyboard.getKeyEvent 0 2>&1 >/dev/null; printf '|%s' "$FV_KEY:$FV_KEY_CHAR" )
fvk_fdfile "${P0}abcdefghijkl${P1}x"
FV_PASTE_MAX=8 keys got
if [[ $got == 'kbPaste:abcdefgh|kbChar:x' && $err == *'cut to 8 (FV_PASTE_MAX)'*'|kbPaste:abcdefgh' ]]; then kt_test_pass "ok"; else kt_test_fail "$got / $err"; fi

kt_test_start "F6: past the cap the kept head (ending ESC [ 2 0) and a later read's last bytes (1 ~ ...) never forge the end: one kbPaste, the key after the real end"
printf -v f '%70s' ''; f=${f// /f}
fvk_fdfile "${P0}abcd${E}[20${f}1~zzz${E}[0m${P1}k"
FV_PASTE_MAX=8 keys got 2>/dev/null
if [[ $got == "kbPaste:abcd${E}[20|kbChar:k" ]]; then kt_test_pass "ok"; else fvk_vis "$got"; kt_test_fail "$REPLY"; fi

kt_test_start "the cut inside a UTF-8 character drops its incomplete bytes (7 bytes of жжжжж -> жжж)"
fv.keyboard.flush
FV_PASTE_MAX=7 fv.keyboard.decode "${P0}жжжжж${P1}" 2>/dev/null
if [[ $FV_KEY == kbPaste && $FV_KEY_CHAR == жжж ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY [$FV_KEY_CHAR]"; fi

kt_test_start "a paste past the default cap through a file: 65536 bytes kept, the key after it intact"
printf -v big '%70000s' ''
big=${big// /a}
fvk_fdfile "${P0}${big}${P1}k"
fv.keyboard.getKeyEvent 0 2>/dev/null; a=${#FV_KEY_CHAR}
fv.keyboard.getKeyEvent 0; b="$FV_KEY:$FV_KEY_CHAR"
if [[ $a == 65536 && $b == kbChar:k ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b"; fi
unset big

kt_test_start "a NUL byte inside a paste (from the fd) is dropped"
printf '\e[200~a\0b\e[201~z' > "$FVK_TMP/nul.bin"
exec {nf}< "$FVK_TMP/nul.bin"; FV_KEY_FD=$nf
fv.keyboard.flush
keys got
exec {nf}<&-
if [[ $got == 'kbPaste:ab|kbChar:z' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "pollKeyEvent peeks the paste (it stays queued); getKeyEvent then takes it"
fvk_fdfile "${P0}peek${P1}"
fv.keyboard.pollKeyEvent; a="$?:$FV_KEY:$FV_KEY_CHAR"
fv.keyboard.getKeyEvent 0; b="$?:$FV_KEY:$FV_KEY_CHAR"
fv.keyboard.getKeyEvent 0; c=$?
if [[ $a == 0:kbPaste:peek && $b == 0:kbPaste:peek && $c == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b $c"; fi

kt_test_start "an ESC in front of the frame: a lone kbEsc, then the paste whole"
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed "${E}${P0}ab${P1}"
keys got
if [[ $got == 'kbEsc:|kbPaste:ab' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "a caller's nocasematch and an IFS of digits change nothing"
FV_KEY_FD=$nullfd
fv.keyboard.flush
shopt -s nocasematch
IFS=0123456789 fv.keyboard.decode "${P0}AbC 201${P1}"
shopt -u nocasematch
if [[ $FV_KEY == kbPaste && $FV_KEY_CHAR == 'AbC 201' ]]; then kt_test_pass "ok"; else kt_test_fail "$FV_KEY [$FV_KEY_CHAR]"; fi
exec {nullfd}<&-

kt_test_log "014_Paste.sh completed"
