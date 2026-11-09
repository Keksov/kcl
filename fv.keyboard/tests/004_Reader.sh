#!/usr/bin/env bash
# 004_Reader.sh - the reader without timing: getKeyEvent / pollKeyEvent over
# a file descriptor (files and here-strings, no terminal), the queue (feed,
# flush, a sequence split between the queue and the fd), peek semantics, end
# of file, NUL bytes (kbCtrlSpace, xterm's NUL coordinate in an X10 report),
# the call checks (rc 2) and FV_ESC_TIMEOUT validation. Timing cases (delayed
# writers) are 005_Timing.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: the reader (fd, queue, peek, EOF, NUL)"

# a paste of mixed keys arriving in one chunk
PASTE=$'ab\e[A\e[1;5D\xd0\xb6\e[<0;10;5M\e[M #!\eOP\r\x7f\e\e[B\xf0\x9f\x98\x80z'
WANT=$'kbChar:a|kbChar:b|kbUp|kbCtrlLeft|kbChar:\xd0\xb6|kbMouse|kbMouse|kbF1|kbEnter|kbBack|kbAltDown|kbChar:\xf0\x9f\x98\x80|kbChar:z'

kt_test_start "a paste of 13 mixed keys in one file decodes one key per getKeyEvent"
fvk_fdfile "$PASTE"
fvk_keys got
if [[ $got == "$WANT" ]]; then kt_test_pass "13 keys"; else kt_test_fail "$got"; fi

kt_test_start "the same paste through a here-string (+ its newline = kbEnter)"
exec {hs}<<<"$PASTE"
FV_KEY_FD=$hs
fv.keyboard.flush
fvk_keys got
exec {hs}<&-
if [[ $got == "$WANT|kbEnter" ]]; then kt_test_pass "14 keys"; else kt_test_fail "$got"; fi

kt_test_start "the same paste fed to the queue (no fd input) decodes the same"
exec {nullfd}</dev/null
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.feed "$PASTE"
fvk_keys got
if [[ $got == "$WANT" ]]; then kt_test_pass "13 keys"; else kt_test_fail "$got"; fi

kt_test_start "the blocking form (no timeout) reads the same paste and then reports EOF"
fvk_fdfile "$PASTE"
got=''
while fv.keyboard.getKeyEvent; do got+="$FV_KEY|"; done
fv.keyboard.getKeyEvent   # once more at EOF
rc=$?
if [[ $got == 'kbChar|kbChar|kbUp|kbCtrlLeft|kbChar|kbMouse|kbMouse|kbF1|kbEnter|kbBack|kbAltDown|kbChar|kbChar|' \
      && $rc == 1 && $FV_KEY == kbNoKey && $FV_KEY_EOF == 1 && -z $RESULT ]]; then
    kt_test_pass "13 keys, then rc 1 + FV_KEY_EOF=1"
else
    kt_test_fail "got=$got rc=$rc key=$FV_KEY eof=$FV_KEY_EOF RESULT=$RESULT"
fi

kt_test_start "each key's FV_KEY_SEQ is its own bytes (mouse report exact)"
fvk_fdfile $'\e[<35;100;200Mq\e[M\x60\xff\xa0r'
seqs=''
while fv.keyboard.getKeyEvent 0; do printf -v v '%q' "$FV_KEY_SEQ"; seqs+="$FV_KEY=$v=$FV_KEY_LEN "; done
want="kbMouse=\$'\\E[<35;100;200M'=14 kbChar=q=1 kbMouse=\$'\\E[M\`\\377\\240'=6 kbChar=r=1 "
if [[ $seqs == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got  $seqs"$'\n'"want $want"; fi

# --- the queue ------------------------------------------------------------------
kt_test_start "a CSI split between the queue and the fd is reassembled"
fvk_fdfile '5Dx'
fv.keyboard.feed $'\e[1;'
fvk_keys got
if [[ $got == 'kbCtrlLeft|kbChar:x' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "an ESC in the queue + the rest on the fd is the sequence, not a lone Esc"
fvk_fdfile '[A'
fv.keyboard.feed $'\e'
fvk_keys got
if [[ $got == 'kbUp' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "a UTF-8 character split between the queue and the fd"
fvk_fdfile $'\x98\x80.'
fv.keyboard.feed $'\xf0\x9f'
fvk_keys got
if [[ $got == $'kbChar:\xf0\x9f\x98\x80|kbChar:.' ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

kt_test_start "the queue is read before the fd"
fvk_fdfile 'fd'
fv.keyboard.feed 'q'
fvk_keys got
if [[ $got == 'kbChar:q|kbChar:f|kbChar:d' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "flush drops the queue and a peeked key"
fvk_fdfile 'z'
fv.keyboard.feed 'abc'
fv.keyboard.pollKeyEvent
fv.keyboard.flush
fvk_keys got
if [[ $got == 'kbChar:z' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "a large paste (6000 keys, past the 4096-byte compaction) decodes every key"
FV_KEY_FD=$nullfd
fv.keyboard.flush
big=''
for (( i = 0; i < 2000; i++ )); do big+=$'x\e[Bж'; done
fv.keyboard.feed "$big"
n=0 bad=0
while fv.keyboard.getKeyEvent 0; do
    case $(( n % 3 )) in
        0) [[ $FV_KEY_CHAR == x ]] || bad=$(( bad + 1 )) ;;
        1) [[ $FV_KEY == kbDown ]] || bad=$(( bad + 1 )) ;;
        2) [[ $FV_KEY_CHAR == ж ]] || bad=$(( bad + 1 )) ;;
    esac
    n=$(( n + 1 ))
done
if (( n == 6000 && bad == 0 )); then kt_test_pass "6000 keys"; else kt_test_fail "n=$n bad=$bad"; fi

# --- peek -------------------------------------------------------------------------
kt_test_start "pollKeyEvent peeks: twice the same key, then getKeyEvent returns it, then the next"
fvk_fdfile $'\e[Ax'
r=''
fv.keyboard.pollKeyEvent; r+="$?:$FV_KEY:$RESULT "
fv.keyboard.pollKeyEvent; r+="$?:$FV_KEY:$RESULT "
fv.keyboard.decode 'q' >/dev/null       # decode between does not disturb the peeked key
fv.keyboard.getKeyEvent; r+="$?:$FV_KEY:$FV_KEY_LEN "
fv.keyboard.pollKeyEvent; r+="$?:$FV_KEY "
fv.keyboard.getKeyEvent; r+="$?:$FV_KEY "
fv.keyboard.pollKeyEvent; r+="$?:$FV_KEY:$FV_KEY_EOF"
if [[ $r == '0:kbUp:kbUp 0:kbUp:kbUp 0:kbUp:3 0:kbChar 0:kbChar 1:kbNoKey:1' ]]; then kt_test_pass "$r"; else kt_test_fail "$r"; fi

kt_test_start "getKeyEvent 0 / pollKeyEvent on an empty queue at EOF: rc 1, kbNoKey, FV_KEY_EOF=1"
FV_KEY_FD=$nullfd
fv.keyboard.flush
fv.keyboard.getKeyEvent 0; r="$?:$FV_KEY:$FV_KEY_EOF"
fv.keyboard.pollKeyEvent; r+=" $?:$FV_KEY:$FV_KEY_EOF"
if [[ $r == '1:kbNoKey:1 1:kbNoKey:1' ]]; then kt_test_pass "$r"; else kt_test_fail "$r"; fi

kt_test_start "getKeyEvent 5 with input ready returns the key at once (< 2 s, not after the 5 s timeout)"
fvk_fdfile $'\eOQ'
e=$EPOCHREALTIME; t0=$(( ${e%[.,]*} * 1000000 + 10#${e##*[.,]} ))
fv.keyboard.getKeyEvent 5; r="$?:$FV_KEY"
e=$EPOCHREALTIME; ms=$(( (${e%[.,]*} * 1000000 + 10#${e##*[.,]} - t0) / 1000 ))
if [[ $r == '0:kbF2' ]] && (( ms < 2000 )); then kt_test_pass "$r in $ms ms"; else kt_test_fail "$r in $ms ms"; fi

# --- NUL bytes ----------------------------------------------------------------------
kt_test_start "a NUL byte is kbCtrlSpace (FV_KEY_SEQ '' and FV_KEY_LEN 1), in order"
fvk_fdfile ''
printf 'a\0b\0\0' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
r=''
while fv.keyboard.getKeyEvent 0; do r+="$FV_KEY:${#FV_KEY_SEQ}:$FV_KEY_LEN|"; done
exec {nfd}<&-
if [[ $r == 'kbChar:1:1|kbCtrlSpace:0:1|kbChar:1:1|kbCtrlSpace:0:1|kbCtrlSpace:0:1|' ]]; then kt_test_pass "$r"; else kt_test_fail "$r"; fi

kt_test_start "a NUL cuts a sequence: ESC NUL = Esc + kbCtrlSpace; CSI 1; NUL = kbUnknown + kbCtrlSpace"
printf '\033\000\033[1;\000x' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fvk_keys got
exec {nfd}<&-
if [[ $got == 'kbEsc|kbCtrlSpace|kbUnknown|kbCtrlSpace|kbChar:x' ]]; then kt_test_pass "$got"; else kt_test_fail "$got"; fi

kt_test_start "xterm's NUL coordinate in an X10 report is kept as \\xff (the clamp); the report is exact"
printf '\033[M \000!y' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fv.keyboard.getKeyEvent; r="$FV_KEY:$FV_KEY_LEN"; s=$FV_KEY_SEQ
fv.keyboard.getKeyEvent; r+=" $FV_KEY:$FV_KEY_CHAR"
exec {nfd}<&-
if [[ $r == 'kbMouse:6 kbChar:y' && $s == $'\e[M \xff!' ]]; then kt_test_pass "$r"; else printf -v v '%q' "$s"; kt_test_fail "$r seq=$v"; fi

kt_test_start "a peeked kbCtrlSpace is consumed once"
printf '\000z' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fv.keyboard.pollKeyEvent; r="$FV_KEY"
fv.keyboard.pollKeyEvent; r+=" $FV_KEY"
fv.keyboard.getKeyEvent; r+=" $FV_KEY"
fv.keyboard.getKeyEvent; r+=" $FV_KEY"
exec {nfd}<&-
if [[ $r == 'kbCtrlSpace kbCtrlSpace kbCtrlSpace kbChar' ]]; then kt_test_pass "$r"; else kt_test_fail "$r"; fi

# --- the call checks ------------------------------------------------------------------
FV_KEY_FD=$nullfd
kt_test_start "getKeyEvent with a timeout that is not a number: rc 2, RESULT='', silent"
r=''
for t in abc -1 1e3 '' . 1.2.3 '$(echo x)'; do
    out=$(fv.keyboard.getKeyEvent "$t" 2>&1); rc=$?
    fv.keyboard.getKeyEvent "$t" 2>/dev/null; rc2=$?
    r+="[$t]=$rc,$rc2,${#out} "
done
if [[ $r == '[abc]=2,2,0 [-1]=2,2,0 [1e3]=2,2,0 []=2,2,0 [.]=2,2,0 [1.2.3]=2,2,0 [$(echo x)]=2,2,0 ' ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "$r"
fi

kt_test_start "FV_KEY_FD that is not an open fd: rc 2 from getKeyEvent and pollKeyEvent, silent"
r=''
for v in '' x 0x1 '1;2' -1 987 12345; do
    FV_KEY_FD=$v
    out=$(fv.keyboard.getKeyEvent 2>&1; fv.keyboard.pollKeyEvent 2>&1)
    FV_KEY_FD=$v fv.keyboard.getKeyEvent 0; a=$?
    FV_KEY_FD=$v fv.keyboard.pollKeyEvent; b=$?
    r+="[$v]=$a,$b,${#out} "
done
FV_KEY_FD=$nullfd
if [[ $r == '[]=2,2,0 [x]=2,2,0 [0x1]=2,2,0 [1;2]=2,2,0 [-1]=2,2,0 [987]=2,2,0 [12345]=2,2,0 ' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "under VERBOSE_KKLASS=debug a bad call prints one Error line on stderr"
err=$(VERBOSE_KKLASS=debug fv.keyboard.getKeyEvent x 2>&1 >/dev/null)
if [[ $err == 'Error: fv.keyboard.getKeyEvent: timeout '"'x'"' is not a number of seconds (at most 6 decimals)' ]]; then kt_test_pass "ok"; else kt_test_fail "err='$err'"; fi

kt_test_start "FV_ESC_TIMEOUT: a positive number is used; 0, negative or text fall back to 0.02 (silent; a debug line)"
r=''
for v in 0.5 2 .1 0 0.000 -1 abc '1;2' 0.02; do
    FV_ESC_TIMEOUT=$v
    fv.keyboard.decode a >/dev/null      # decode does not read FV_ESC_TIMEOUT
    out=$(fv.keyboard.getKeyEvent 0 2>&1)
    fv.keyboard.getKeyEvent 0
    r+="[$v]=$__FV_KB_T,${#out} "
done
d=$(FV_ESC_TIMEOUT=zz VERBOSE_KKLASS=debug fv.keyboard.pollKeyEvent 2>&1 >/dev/null)
unset FV_ESC_TIMEOUT
fv.keyboard.getKeyEvent 0
r+="[unset]=$__FV_KB_T"
if [[ $r == '[0.5]=0.5,0 [2]=2,0 [.1]=.1,0 [0]=0.02,0 [0.000]=0.02,0 [-1]=0.02,0 [abc]=0.02,0 [1;2]=0.02,0 [0.02]=0.02,0 [unset]=0.02' \
      && $d == *"FV_ESC_TIMEOUT 'zz' is not a positive number of seconds (at most 6 decimals); using 0.02" ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "$r | debug='$d'"
fi

kt_test_start "direct calls print nothing; RESULT is the key name"
fvk_fdfile $'x\e[A'
r=''
{
    fv.keyboard.pollKeyEvent; r+="$RESULT "
    fv.keyboard.getKeyEvent; r+="$RESULT "
    fv.keyboard.getKeyEvent 0; r+="$RESULT "
    fv.keyboard.getKeyEvent 0; r+="[$RESULT] "
    fv.keyboard.feed y; fv.keyboard.flush
    fv.keyboard.decode $'\eOP'; r+="$RESULT"
} >"$FVK_TMP/direct.out" 2>&1
fvk_len "$(<"$FVK_TMP/direct.out")"
if [[ $REPLY == 0 && $r == 'kbChar kbChar kbUp [] kbF1' ]]; then kt_test_pass "ok"; else kt_test_fail "out=$REPLY bytes r='$r'"; fi

kt_test_start "decode inside \$( ) prints the key name once (kcl README 1.1)"
v=$(fv.keyboard.decode $'\e[1;5D')
if [[ $v == kbCtrlLeft ]]; then kt_test_pass "ok"; else kt_test_fail "'$v'"; fi

# --- feed while a NUL is pending (fix round F2) ------------------------------------
# feed queues bytes after everything already read from the fd (a pending NUL
# included) and before what the fd has not delivered yet
kt_test_start "feed after ESC NUL was read: the NUL comes first, then the fed bytes, then the fd's rest"
printf '\033\000z' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fv.keyboard.getKeyEvent; r="$FV_KEY"         # ESC, then the NUL is read: kbEsc
fv.keyboard.feed FED
fvk_keys got
exec {nfd}<&-
if [[ $r == kbEsc && $got == 'kbCtrlSpace|kbChar:F|kbChar:E|kbChar:D|kbChar:z' ]]; then kt_test_pass "$r|$got"; else kt_test_fail "$r|$got"; fi

kt_test_start "fed bytes ending in a partial X10 report do not take the NUL read before them"
printf '\033\000 !!' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fv.keyboard.getKeyEvent; r="$FV_KEY"
fv.keyboard.feed $'\e[M'
fv.keyboard.getKeyEvent; r+=" $FV_KEY"
fv.keyboard.getKeyEvent; r+=" $FV_KEY"; s=$FV_KEY_SEQ
exec {nfd}<&-
if [[ $r == 'kbEsc kbCtrlSpace kbMouse' && $s == $'\e[M !!' ]]; then kt_test_pass "$r"; else printf -v v '%q' "$s"; kt_test_fail "$r seq=$v"; fi

kt_test_start "a peeked key, then feed, then the NUL: order kept across poll / feed / get"
printf 'a\000' > "$FVK_TMP/nul.bin"
exec {nfd}< "$FVK_TMP/nul.bin"
FV_KEY_FD=$nfd
fv.keyboard.flush
fv.keyboard.getKeyEvent; r="$FV_KEY_CHAR"
fv.keyboard.pollKeyEvent; r+=" $FV_KEY"
fv.keyboard.feed b
fvk_keys got
exec {nfd}<&-
if [[ $r == 'a kbCtrlSpace' && $got == 'kbCtrlSpace|kbChar:b' ]]; then kt_test_pass "$r|$got"; else kt_test_fail "$r|$got"; fi

# --- sub-microsecond timeouts (fix round F3) -----------------------------------------
kt_test_start "a timeout finer than 1 us (bash would run it as -t 0) is rc 2 for getKeyEvent"
FV_KEY_FD=$nullfd
r=''
for t in 0.0000001 1.1234567 .0000005 0.000001 2.5; do
    fv.keyboard.getKeyEvent "$t" 2>/dev/null; r+="[$t]=$? "
done
if [[ $r == '[0.0000001]=2 [1.1234567]=2 [.0000005]=2 [0.000001]=1 [2.5]=1 ' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "FV_ESC_TIMEOUT finer than 1 us falls back to 0.02 (a lone ESC then waits, no phantom byte)"
fvk_fdfile 'q'
fv.keyboard.feed $'\e'
FV_ESC_TIMEOUT=0.0000001
VERBOSE_KKLASS=debug fv.keyboard.getKeyEvent 2>"$FVK_TMP/d.err"; r="$FV_KEY:$__FV_KB_T"
d=$(<"$FVK_TMP/d.err")
fv.keyboard.getKeyEvent; r+=" $FV_KEY"
unset FV_ESC_TIMEOUT
if [[ $r == 'kbAltQ:0.02 kbNoKey' && $d == *"(at most 6 decimals); using 0.02" ]]; then kt_test_pass "$r"; else kt_test_fail "$r | $d"; fi

# --- an fd closed after it was found open (fix round F7c) ---------------------------
kt_test_start "an fd closed after its check: getKeyEvent 0, getKeyEvent and pollKeyEvent all answer rc 2, FV_KEY_EOF=0"
# fd 77, not a {var} fd: `2>/dev/null` on the call saves stderr on the lowest
# free fd >= 10, which would make a just-closed fd 10 open again
r=''
for call in 'fv.keyboard.getKeyEvent 0' 'fv.keyboard.getKeyEvent' 'fv.keyboard.pollKeyEvent'; do
    exec 77< "$FVK_TMP/nul.bin"
    FV_KEY_FD=77
    fv.keyboard.flush
    fv.keyboard.pollKeyEvent; fv.keyboard.flush          # the fd is checked and cached
    exec 77<&-
    $call 2>/dev/null; r+="$?:$FV_KEY_EOF "
done
FV_KEY_FD=$nullfd
if [[ $r == '2:0 2:0 2:0 ' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi
exec {nullfd}<&-

kt_test_log "004_Reader.sh completed"
