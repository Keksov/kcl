#!/usr/bin/env bash
# 016_Reader.sh - the reader process (D13): on Cygwin-family runtimes (and
# with FV_TTY_READER=1 anywhere) initVideo starts a background process that
# reads the terminal one byte at a time and forwards each byte through a
# pipe; FV_KEY_FD is the pipe's read end.
#   * without a terminal (every runtime, a fifo stands in for the terminal):
#     every byte forwarded unchanged (NUL included) and the end at end of
#     file, also under set -eEuxT / pipefail / ERR DEBUG RETURN traps / a
#     UTF-8 locale; the end when the owner is gone (timed reads; with
#     blocking reads at the next byte); INT QUIT TSTP WINCH ignored, TERM,
#     HUP and a failed write end it; _rstart / _rstop and FV_TTY_READER
#     (0, 1, auto by OSTYPE, a junk value), __FV_VI_POLL '' and junk; a
#     reader that does not start leaves the terminal read directly;
#   * on a real pty under util-linux script(1) (SKIP with reason ENV
#     elsewhere): the reader is alive while on, one per TUI; keys, NUL, a
#     burst, UTF-8 and mouse reports flow through it; Esc alone vs an Esc
#     sequence (timing); it is gone after doneVideo, exit without done, a set
#     -e failure, Ctrl+C typed, SIGTERM, SIGHUP and kill -9 of the main shell
#     (within 3 s; with blocking reads at the next byte); re-init leaves one
#     reader; a subshell's init/done under an active parent leaves the
#     parent's reader alone; FV_TTY_READER=0 / 1 on this runtime; signals sent
#     to the reader alone; the reader killed -> end of input.
# Every reader pid is recorded and reaped if it survives (a failure).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVV_TESTS_DIR/.." && pwd)/fv.video.sh"
KBOOL="$(cd "$FVV_TESTS_DIR/../../.." && pwd)/kbool.sh"
T=$FVV_TMP

kt_test_section "016: the reader process (D13)"

# child BODY — run BODY in a fresh bash (kbool + fv.drivers loaded, a fifo
# open read-write on $a as the "terminal"), at most 20 s; REPLY = its stdout,
# CHILD_ERR = its stderr. BODY puts reader pids into $T/pids (reaped after).
child() {
    local d=$T/c$RANDOM$RANDOM
    mkdir -p "$d"
    REPLY=$("$KT_TIMEOUT" -k 2 20 "$BASH" -c "
cd '$d' || exit 89
source '$KBOOL'
kk.uses fv.drivers || exit 90
mkfifo '$d/f' || exit 88
exec {a}<>'$d/f'
pids() { printf '%s\n' \"\$@\" >> '$T/pids'; }
gone() { local i; for (( i = 0; i < \${2:-40}; i++ )); do kill -0 \"\$1\" 2>/dev/null || return 0; sleep 0.05; done; return 1; }
$1" 2> "$d/err")
    CHILD_ERR=$(<"$d/err")
    reap_all
}

# reap_all — every pid in $T/pids still alive is killed (and noted in SURV)
reap_all() {
    local p
    if [[ ! -s $T/pids ]]; then return 0; fi
    while IFS= read -r p; do
        if [[ -n $p && $p != *[!0-9]* ]] && kill -0 "$p" 2>/dev/null; then
            fvp_reap "$p"
            SURV+=" $p"
        fi
    done < "$T/pids"
    : > "$T/pids"
}
SURV=''
: > "$T/pids"
kt_need_timeout || :

# check TITLE WANT GOT — one test: GOT == WANT, no survivor since the last check
check() {
    kt_test_start "$1"
    if [[ $3 == "$2" && -z $SURV ]]; then kt_test_pass "ok"
    else kt_test_fail "got [$3] want [$2]${SURV:+ survivors:$SURV}"; fi
    SURV=''
}

if [[ -z ${KT_TIMEOUT-} ]]; then
    for t in "bytes unchanged" "owner gone" "signals" "_rstart/_rstop" "FV_TTY_READER auto" "a junk FV_TTY_READER" "blocking reads" "a bad __FV_VI_POLL" "no start" "TERM ignored" "TERM obeyed" "fds closed" "ppid check"; do
        kt_test_start "$t"; kt_test_pass "SKIP: ENV: ${KT_TIMEOUT_WHY:-no timeout(1)}"
    done
else

# --- without a terminal ----------------------------------------------------

for (( i = 0; i < 256; i++ )); do printf -v h '%03o' "$i"; printf "\\$h"; done > "$T/all.bin"
child '
set -eEuxT -o pipefail
export LC_ALL=C.UTF-8
trap "echo ERR-TRAP >&2" ERR
trap ":" DEBUG
trap ":" RETURN
exec {t}<'"'$T/all.bin'"'
( fv.video._reader "$t" $$ 0.5 500000 ) > out.bin
r="eof "
cmp -s out.bin '"'$T/all.bin'"' && r+="same "
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
pids "$__FV_VI_RPID"
printf "a\0\377" >&$a
fv.keyboard.getKeyEvent 2; r+="$FV_KEY_CHAR,"
fv.keyboard.getKeyEvent 2; r+="$FV_KEY,"
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
fv.video._rstop
echo "$r"'
e=$CHILD_ERR
if [[ $e == *$'\n'ERR-TRAP* || $e == *'-t 0.5 -u'* ]]; then REPLY+=" stderr:[$e]"; fi
check "the reader forwards all 256 byte values unchanged (NUL too) and ends at end of file; _rstart works under set -eEuxT, pipefail, ERR/DEBUG/RETURN traps and a UTF-8 locale; no reader trace or ERR on stderr" \
    "eof same a,kbCtrlSpace,kbUnknown " "$REPLY"

child '
: & dead=$!; wait "$dead"
fv.video._reader "$a" "$dead" 0.2 200000 > /dev/null & r1=$!; pids "$r1"
r=""
gone "$r1" 60 && r+="timed-gone "
fv.video._reader "$a" "$dead" "" 200000 > b.out & r2=$!; pids "$r2"
sleep 0.6
kill -0 "$r2" 2>/dev/null && r+="blocking-alive "
printf q >&$a
gone "$r2" 60 && r+="gone-at-byte "
echo "$r[$(<b.out)]"'
check "the owner gone: the reader ends by itself (timed reads: within 3 s; blocking reads: at the next byte, which it still forwards)" \
    "timed-gone blocking-alive gone-at-byte [q]" "$REPLY"

child '
fv.video._reader "$a" $$ 0.2 200000 > s.out & r=$!; pids "$r"
sleep 0.3
kill -INT "$r"; kill -QUIT "$r"; kill -TSTP "$r"; kill -WINCH "$r"
sleep 0.3; printf x >&$a; sleep 0.3
o=""
kill -0 "$r" 2>/dev/null && o+="alive "
o+="[$(<s.out)] "
kill -TERM "$r"; gone "$r" && o+="term "
fv.video._reader "$a" $$ 0.2 200000 > /dev/null & r=$!; pids "$r"
sleep 0.2
kill -HUP "$r"; gone "$r" && o+="hup "
exec {p}< <(fv.video._reader "$a" $$ 0.2 200000); r=$!; pids "$r"
exec {p}<&-
sleep 0.2
printf yz >&$a
gone "$r" && o+="pipe"
echo "$o"'
check "signals: INT, QUIT, TSTP and WINCH are ignored (alive, still forwarding); TERM and HUP end it; a write to a closed pipe ends it" \
    "alive [x] term hup pipe" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart; r="$? "
rp=$__FV_VI_RPID rf=$__FV_VI_RFD; pids "$rp"
if [[ -n $rp && $FV_KEY_FD == "$rf" && $rf != "$a" ]] && kill -0 "$rp"; then r+="on "; fi
printf "k\033[B" >&$a
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
t0=$EPOCHREALTIME
fv.video._rstop; r+="$? "
t1=$EPOCHREALTIME
kill -0 "$rp" 2>/dev/null || r+="gone "
if [[ ! -e /dev/fd/$rf && -z $__FV_VI_RPID$__FV_VI_RFD ]]; then r+="closed "; fi
(( (${t1/[.,]/} - ${t0/[.,]/}) < 1000000 )) && r+="fast "
FV_KEY_FD=$a
FV_TTY_READER=0 fv.video._rstart
if [[ -z $__FV_VI_RPID && $FV_KEY_FD == "$a" ]]; then r+="off"; fi
echo "$r"'
check "_rstart / _rstop with a fifo as the terminal: FV_TTY_READER=1 starts it (FV_KEY_FD = the pipe, keys read through it); _rstop ends it within 1 s, clears the globals and closes the pipe; FV_TTY_READER=0 starts none" \
    "0 on kbChar kbDown 0 gone closed fast off" "$REPLY"

child '
r=""
for o in linux-gnu darwin23 freebsd14.1 msys cygwin; do
    FV_KEY_FD=$a __FV_VI_FD=$a
    OSTYPE=$o FV_TTY_READER= fv.video._rstart
    if [[ -n $__FV_VI_RPID ]]; then pids "$__FV_VI_RPID"; r+="$o:on "; fv.video._rstop; else r+="$o:off "; fi
done
echo "$r"'
check "FV_TTY_READER empty = auto: a reader on OSTYPE msys* and cygwin*, none on linux, darwin, freebsd" \
    "linux-gnu:off darwin23:off freebsd14.1:off msys:on cygwin:on " "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
VERBOSE_KKLASS=debug OSTYPE=linux-gnu FV_TTY_READER=yes fv.video._rstart
[[ -z $__FV_VI_RPID ]] && echo -n "auto-off "
VERBOSE_KKLASS=debug OSTYPE=msys FV_TTY_READER=" 1" fv.video._rstart
[[ -n $__FV_VI_RPID ]] && echo "auto-on"
pids "$__FV_VI_RPID"; fv.video._rstop'
e=${CHILD_ERR//$'\n'/|}
[[ $e == "Error: fv.video.initVideo: FV_TTY_READER='yes' is not 0, 1 or empty; using auto|Error: fv.video.initVideo: FV_TTY_READER=' 1' is not 0, 1 or empty; using auto" ]] || REPLY+=" stderr:[$e]"
check "a junk FV_TTY_READER: one debug line, then auto" "auto-off auto-on" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
__FV_VI_POLL="" FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; pids "$rp"
sleep 0.7
printf m >&$a
fv.keyboard.getKeyEvent 2; r="$FV_KEY_CHAR "
t0=$EPOCHREALTIME
fv.video._rstop; r+="$? "
t1=$EPOCHREALTIME
kill -0 "$rp" 2>/dev/null || r+="gone "
(( (${t1/[.,]/} - ${t0/[.,]/}) < 1000000 )) && r+="fast"
echo "$r"'
check "__FV_VI_POLL='' (blocking reads): keys flow; _rstop ends it within 1 s (SIGTERM interrupts the blocking read)" "m 0 gone fast" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
__FV_VI_POLL=fast VERBOSE_KKLASS=debug FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; pids "$rp"
printf n >&$a
fv.keyboard.getKeyEvent 2; r="$FV_KEY_CHAR "
fv.video._rstop; kill -0 "$rp" 2>/dev/null || r+="gone"
echo "$r"'
[[ $CHILD_ERR == "Error: fv.video.initVideo: __FV_VI_POLL='fast' is not a positive number of seconds; using 0.5" ]] || REPLY+=" stderr:[$CHILD_ERR]"
check "a bad __FV_VI_POLL: one debug line, 0.5 s" "n gone" "$REPLY"

child '
M=$BASHPID
kill() { if [[ $1 == -0 && $BASHPID == "$M" ]]; then return 1; fi; builtin kill "$@"; }
FV_KEY_FD=$a __FV_VI_FD=$a
VERBOSE_KKLASS=debug FV_TTY_READER=1 fv.video._rstart; r="$? "
rp=$!; pids "$rp"
r+="[$__FV_VI_RPID$__FV_VI_RFD] "
[[ $FV_KEY_FD == "$a" ]] && r+="direct "
unset -f kill
gone "$rp" 20 && r+="gone"
echo "$r"'
[[ $CHILD_ERR == "Error: fv.video.initVideo: the terminal reader did not start (pid '"*"'); reading the terminal directly" ]] || REPLY+=" stderr:[$CHILD_ERR]"
check "a reader that does not start (kill -0 fails in the owner only; the reader itself would live on): rc 0, the terminal read directly, one debug line, the started process stopped within 1 s" "0 [] direct gone" "$REPLY"

child '
cat > inner.sh <<"IN"
source "$1"; kk.uses fv.drivers || exit 90
exec {a}<>"$2"
kill -TERM $BASHPID
r="term-ignored "
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; printf "%s\n" "$rp" >> "$3"
t0=$EPOCHREALTIME; fv.video._rstop; rc=$?; t1=$EPOCHREALTIME
ms=$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))
r+="rc=$rc "
kill -0 "$rp" 2>/dev/null || r+="gone "
(( ms < 1000 )) && r+="fast"
echo "$r|$ms"
IN
( trap "" TERM; exec "$BASH" inner.sh '"'$KBOOL'"' "$PWD/f" '"'$T/pids'"' )'
MS=${REPLY##*|}; REPLY=${REPLY%|*}
check "TERM ignored when the shell started (bash cannot reset it in the reader): _rstop still ends the reader (KILL after 0.1 s) within 1 s (${MS} ms)" "term-ignored rc=0 gone fast" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; pids "$rp"
t0=$EPOCHREALTIME; fv.video._rstop; t1=$EPOCHREALTIME
echo "$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"'
check "_rstop of a reader that obeys TERM (timing: ${REPLY} ms)" "1" "$(( REPLY < 100 ))"

rm -f "$T/f2"; mkfifo "$T/f2"
child '
exec {x}</dev/null
exec {y}<>'"'$T/f2'"'
exec {z}> >(read -r v)
pids "$!"
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; pids "$rp"
sleep 0.3
if [[ ! -d /proc/$rp/fd ]]; then echo "n/a"; fv.video._rstop; exit 0; fi
bad="" seen=""
for f in /proc/"$rp"/fd/*; do
    n=${f##*/}
    case $n in 0|1|2|255) ;; "$a") seen=1 ;; *) bad+=" $n" ;; esac
done
fv.video._rstop
exec {z}>&-
if [[ -z $bad && -n $seen ]]; then echo "only 0 1 2 tty"; else echo "extra:$bad x=$x y=$y z=$z a=$a"; fi'
if [[ $REPLY == n/a ]]; then kt_test_start "the reader holds only fds 0, 1, 2 and the terminal"; kt_test_pass "SKIP: no /proc/PID/fd"; SURV=''
else check "the reader holds only fds 0, 1, 2 and the terminal: the owner's other fds (a file, a fifo, a process-substitution pipe) are closed in it" "only 0 1 2 tty" "$REPLY"; fi

child '
( sleep 5 > /dev/null 2>&1 & echo $! > sp )
v=$(<sp); pids "$v"
if [[ ! -r /proc/$v/ppid ]]; then echo "n/a"; exit 0; fi
exec {q}</dev/null
__FV_VI_RPID=$v __FV_VI_RFD=$q
fv.video._rstop; r="$? "
kill -0 "$v" 2>/dev/null && r+="alive "
[[ ! -e /dev/fd/$q && -z $__FV_VI_RPID$__FV_VI_RFD ]] && r+="closed"
kill "$v" 2>/dev/null
echo "$r"'
if [[ $REPLY == n/a ]]; then kt_test_start "_rstop never signals a pid that is not its child (/proc/PID/ppid)"; kt_test_pass "SKIP: no /proc/PID/ppid"; SURV=''
else check "_rstop never signals a pid whose /proc/PID/ppid is not this shell (a reused pid): no signal, the pipe still closed" "0 alive closed" "$REPLY"; fi

fi

# --- on a real pty (script(1)) ---------------------------------------------

# the child helpers: rec [N] = the reader's pid to rpidN; alive PID; kids =
# REPLY = the number of this process's children (fork-free, /proc/*/stat)
RPRE='
rec() { printf "%s" "$__FV_VI_RPID" > "$D/rpid${1-}"; }
alive() { [[ -n $1 ]] && kill -0 "$1" 2>/dev/null; }
kids() { local f s n=0; for f in /proc/[0-9]*/stat; do s=""; read -r s 2>/dev/null < "$f" || continue; s=${s##*) }; s=${s#* }; s=${s%% *}; if [[ $s == "$BASHPID" ]]; then n=$(( n + 1 )); fi; done; REPLY=$n; }
'
# what auto (FV_TTY_READER unset) gives on this runtime
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then AUTO=on; else AUTO=off; fi

PTY_TITLES=("the reader is alive while on, the only child; FV_KEY_FD = its pipe, FV_TTY_FD the tty"
    "keys through the reader: chars, NUL, a CSI key, an SGR mouse report, UTF-8, a 300-byte burst in order"
    "doneVideo: the reader gone, its pipe closed, FV_KEY_FD back, no child left"
    "Esc alone -> kbEsc after the Esc timeout (10-500 ms); an Esc sequence in one write -> kbUp"
    "exit paths (doneVideo, exit 3, set -e, Ctrl+C typed, SIGTERM, SIGHUP): the reader alive while on, gone after, statuses 0/3/1/130/143/129, terminal restored, SIGTERM / SIGHUP end the child within 1 s"
    "kill -9 of the main shell: the reader ends by itself within 3 s (pty held open)"
    "kill -9 with blocking reads (__FV_VI_POLL=''): the reader lives until the next byte, then ends"
    "re-init: done stops the first reader, init starts one new reader (one child), keys flow, done stops it"
    "a subshell's initVideo / doneVideo under an active parent leave the parent's reader alone"
    "FV_TTY_READER=0: no reader, FV_KEY_FD = FV_TTY_FD, keys read directly; empty: auto ($AUTO here)"
    "INT QUIT TSTP WINCH sent to the reader alone: ignored, keys still flow; HUP kills it: getEvent -> end of input, doneVideo still restores"
    "the restore drains through the reader's pipe and never reads the terminal (FV_TTY_READER=1); without a reader it drains the terminal (=0); nothing left over either way"
    "TERM ignored when the TUI's shell started: doneVideo still stops the reader (KILL) and restores, within 1.5 s")

k9watch() {
    local d=$1 p i t0 t1
    p=$(<"$d/rpid")
    for (( i = 0; i < 100; i++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.05; done
    t1=$EPOCHREALTIME t0=$(<"$d/t_mark")
    if kill -0 "$p" 2>/dev/null; then echo alive > "$d/k9"; else echo "$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))" > "$d/k9"; fi
    : > "$d/release"
}
k9block() {
    local d=$1 p i r=''
    p=$(<"$d/rpid")
    sleep 1.2
    if kill -0 "$p" 2>/dev/null; then r+='alive1 '; fi
    printf z
    for (( i = 0; i < 60; i++ )); do kill -0 "$p" 2>/dev/null || break; sleep 0.05; done
    if kill -0 "$p" 2>/dev/null; then r+='alive2'; else r+='gone'; fi
    echo "$r" > "$d/k9"
    : > "$d/release"
}

run_pty() {
    local l X300 p rc ok
    X300=$(printf 'x%.0s' {1..300})

    fvp_case keys "$RPRE"'
export FV_TTY_READER=1
FV_KEY_FD=0
fv.video.initVideo || exit 91
rec; rp=$__FV_VI_RPID rf=$__FV_VI_RFD
kids
note "on $(alive "$rp" && echo alive) $([[ $FV_KEY_FD == "$rf" && ! -t $FV_KEY_FD && -t $FV_TTY_FD ]] && echo pipe) kids=$REPLY"
: > "$D/ready"
s="" n=0
while fv.keyboard.getKeyEvent 3; do
    if [[ $FV_KEY == kbChar && $FV_KEY_CHAR == x ]]; then n=$(( n + 1 )); continue; fi
    s+="$FV_KEY:$FV_KEY_CHAR|"
    if [[ $FV_KEY_CHAR == Z ]]; then break; fi
done
note "keys ${s}x=$n"
fv.video.doneVideo
kids
note "after $(alive "$rp" || echo gone) $([[ ! -e /dev/fd/$rf ]] && echo closed) key=$FV_KEY_FD kids=$REPLY"
exit 0'
    fvp_run keys ready sleep:0.3 'type:ab\0\e[A\e[<0;3;4M\xd0\xb6' sleep:0.2 "type:${X300}Z"
    fvp_file keys log; l=$REPLY
    kt_test_start "${PTY_TITLES[0]}"
    if [[ $l == *'on alive pipe kids=1'* && -s $FVP_ROOT/keys/rpid ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
    kt_test_start "${PTY_TITLES[1]}"
    if [[ $l == *'keys kbChar:a|kbChar:b|kbCtrlSpace:|kbUp:|kbMouse:|kbChar:'$'\xd0\xb6''|kbChar:Z|x=300'* ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
    kt_test_start "${PTY_TITLES[2]}"
    if [[ $l == *'after gone closed key=0 kids=0'* ]] && fvp_restored keys; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    fvp_case esc "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec
: > "$D/ready"
r=""
for k in 1 2; do
    e=$(( ${EPOCHREALTIME//[.,]/} + 10000000 ))
    until read -t 0 -u "$FV_KEY_FD" || (( ${EPOCHREALTIME//[.,]/} > e )); do :; done
    t0=$EPOCHREALTIME; fv.keyboard.getKeyEvent 3; t1=$EPOCHREALTIME
    r+="$FV_KEY:$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 )) "
done
note "esc $r"
fv.video.doneVideo
exit 0'
    fvp_run esc ready sleep:0.3 'type:\e' sleep:0.5 'type:\e[A'
    fvp_file esc log; l=$REPLY
    kt_test_start "${PTY_TITLES[3]}"
    ok=0
    if [[ $l =~ ^esc\ kbEsc:([0-9]+)\ kbUp:([0-9]+)\ $ ]] && (( BASH_REMATCH[1] >= 10 && BASH_REMATCH[1] < 500 )); then ok=1; fi
    if (( ok )) && fvp_restored esc; then kt_test_pass "ok ($l)"; else kt_test_fail "log=[$l] $REPLY"; fi

    local PRE="$RPRE"'
export FV_TTY_READER=1
trap "note EXIT" EXIT
trap "note INT" INT
trap "note TERM" TERM
fv.video.initVideo || exit 91
rec
alive "$__FV_VI_RPID" && note alive
'
    local LOOP='
: > "$D/ready"
while fv.drivers.getEvent; do :; done
note "loop ended"
'
    local bad='' c t0 ms
    fvp_case p_done "$PRE"'
fv.video.doneVideo
exit 0'
    fvp_run p_done
    fvp_case p_exit "$PRE"'
exit 3'
    fvp_run p_exit
    fvp_case p_sete "set -e
$PRE"'
false'
    fvp_run p_sete
    fvp_case p_int "$PRE$LOOP"
    fvp_run p_int ready sleep:0.3 'type:\x03'
    fvp_case p_term "$PRE$LOOP"
    fvp_run p_term ready sleep:0.3 sig:TERM
    fvp_case p_hup "$PRE$LOOP"
    fvp_run p_hup ready sleep:0.3 sig:HUP
    for c in p_done:0 p_exit:3 p_sete:1 p_int:130 p_term:143 p_hup:129; do
        fvp_file "${c%:*}" log; l=$REPLY
        fvp_file "${c%:*}" rc; rc=$REPLY
        if [[ $l != alive$'\n'* || $rc != "${c#*:}" || ! -s $FVP_ROOT/${c%:*}/rpid ]] || ! fvp_restored "${c%:*}"; then
            bad+=" ${c%:*}: rc=$rc log=[${l//$'\n'/|}] $REPLY;"
        fi
        # a signal: the reader is stopped inside the trap handler (where bash
        # reaps no child): the child still ends within 1 s of the signal
        if [[ -s $FVP_ROOT/${c%:*}/t_mark && -s $FVP_ROOT/${c%:*}/t_end ]]; then
            fvp_file "${c%:*}" t_mark; t0=$REPLY
            fvp_file "${c%:*}" t_end
            ms=$(( (${REPLY//[.,]/} - ${t0//[.,]/}) / 1000 ))
            if (( ms > 1000 )); then bad+=" ${c%:*}: ended ${ms} ms after the signal;"; fi
        fi
    done
    kt_test_start "${PTY_TITLES[4]}"
    if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

    fvp_case k9 "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec
: > "$D/hold"
: > "$D/ready"
while fv.drivers.getEvent; do :; done'
    fvp_run k9 ready sleep:0.3 sig:KILL call:k9watch
    fvp_file k9 k9; l=$REPLY
    fvp_file k9 rc; rc=$REPLY
    kt_test_start "${PTY_TITLES[5]}"
    if [[ $rc == 137 && $l != *[!0-9]* && -n $l ]] && (( l <= 3000 )) && [[ ! -e $FVP_ROOT/k9/survivors ]]; then
        kt_test_pass "gone ${l} ms after the kill"
    else
        kt_test_fail "rc=$rc k9=[$l] $(cat "$FVP_ROOT/k9/survivors" 2>/dev/null)"
    fi

    fvp_case k9b "$RPRE"'
export FV_TTY_READER=1
__FV_VI_POLL=""
fv.video.initVideo || exit 91
rec
: > "$D/hold"
: > "$D/ready"
while fv.drivers.getEvent; do :; done'
    fvp_run k9b ready sleep:0.3 sig:KILL call:k9block
    fvp_file k9b k9; l=$REPLY
    kt_test_start "${PTY_TITLES[6]}"
    if [[ $l == 'alive1 gone' && ! -e $FVP_ROOT/k9b/survivors ]]; then kt_test_pass "ok"; else kt_test_fail "k9=[$l] $(cat "$FVP_ROOT/k9b/survivors" 2>/dev/null)"; fi

    fvp_case reinit "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec 1; p1=$__FV_VI_RPID
fv.video.doneVideo
r=""; alive "$p1" || r+="old-gone "
fv.video.initVideo || exit 92
rec 2; p2=$__FV_VI_RPID
kids
alive "$p2" && r+="new-alive "
note "reinit ${r}kids=$REPLY"
: > "$D/ready"
fv.keyboard.getKeyEvent 3; note "key $FV_KEY_CHAR"
fv.video.doneVideo
kids
note "end $(alive "$p2" || echo gone) kids=$REPLY"
exit 0'
    fvp_run reinit ready sleep:0.2 type:q
    fvp_file reinit log; l=$REPLY
    kt_test_start "${PTY_TITLES[7]}"
    if [[ $l == $'reinit old-gone new-alive kids=1\nkey q\nend gone kids=0' ]] && fvp_restored reinit; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    fvp_case sub "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec; p=$__FV_VI_RPID
x=$(fv.video.initVideo; fv.video.doneVideo; printf v)
( fv.video.doneVideo; exit 0 )
note "sub x=$x $(alive "$p" && echo alive) $([[ $__FV_VI_RPID == "$p" && $FV_KEY_FD == "$__FV_VI_RFD" ]] && echo same)"
: > "$D/ready"
fv.keyboard.getKeyEvent 3; note "key $FV_KEY_CHAR"
fv.video.doneVideo
exit 0'
    fvp_run sub ready sleep:0.2 type:s
    fvp_file sub log; l=$REPLY
    kt_test_start "${PTY_TITLES[8]}"
    if [[ $l == $'sub x=v alive same\nkey s' ]] && fvp_restored sub; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    fvp_case r0 "$RPRE"'
export FV_TTY_READER=0
fv.video.initVideo || exit 91
kids
note "r0 $([[ -z $__FV_VI_RPID && $FV_KEY_FD == "$FV_TTY_FD" ]] && echo direct) kids=$REPLY"
: > "$D/ready"
fv.keyboard.getKeyEvent 3; note "key $FV_KEY_CHAR"
fv.video.doneVideo
unset FV_TTY_READER
fv.video.initVideo || exit 92
rec
if [[ -n $__FV_VI_RPID ]]; then note "auto on"; else note "auto off"; fi
fv.video.doneVideo
exit 0'
    fvp_run r0 ready sleep:0.2 type:d
    fvp_file r0 log; l=$REPLY
    kt_test_start "${PTY_TITLES[9]}"
    if [[ $l == $'r0 direct kids=0\nkey d\nauto '"$AUTO" ]] && fvp_restored r0; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    fvp_case rsig "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec; p=$__FV_VI_RPID
kill -INT "$p"; kill -QUIT "$p"; kill -TSTP "$p"; kill -WINCH "$p"
: > "$D/ready"
fv.keyboard.getKeyEvent 3; note "ignored $(alive "$p" && echo alive) key=$FV_KEY_CHAR"
kill -HUP "$p"
for (( i = 0; i < 40; i++ )); do alive "$p" || break; sleep 0.05; done
fv.drivers.getEvent 1; r=$?
note "hup $(alive "$p" || echo gone) rc=$r eof=$FV_EV_EOF"
fv.video.doneVideo; note "done rc=$?"
exit 0'
    fvp_run rsig ready sleep:0.2 type:g
    fvp_file rsig log; l=$REPLY
    kt_test_start "${PTY_TITLES[10]}"
    if [[ $l == $'ignored alive key=g\nhup gone rc=1 eof=1\ndone rc=0' ]] && fvp_restored rsig; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    # R2: the restore drains through the reader's pipe, never the terminal
    for m in 1 0; do
        fvp_case "dfd$m" "$RPRE"'
eval "$(declare -f fv.video._drain | sed "1s/^fv\.video\._drain/__o_drain/")"
fv.video._drain() { printf "%s\n" "$1" >> "$D/drainfd"; __o_drain "$@"; }
export FV_TTY_READER='"$m"'
fv.video.initVideo || exit 91
rec
fv.drivers.initEvents
note "fds tty=$FV_TTY_FD rfd=${__FV_VI_RFD:-none}"
: > "$D/ready"
for (( i = 0; i < 100; i++ )); do if read -t 0 -u "$FV_KEY_FD"; then break; fi; sleep 0.05; done
: > "$D/wantleft"
fv.video.doneVideo
note "drained $(tr "\n" " " < "$D/drainfd")"
exit 0'
        fvp_run "dfd$m" ready 'type:\e[<35;10;5M\e[<35;11;5Mabc'
    done
    kt_test_start "${PTY_TITLES[11]}"
    bad=''
    for m in 1 0; do
        fvp_file "dfd$m" log; l=$REPLY
        fvp_file "dfd$m" leftover; left=$REPLY
        if [[ $l =~ fds\ tty=([0-9]+)\ rfd=([0-9a-z]+)$'\n'drained\ (.*)$ ]]; then
            if [[ $m == 1 && ${BASH_REMATCH[3]} != "${BASH_REMATCH[2]} " ]]; then bad+=" reader: drained [${BASH_REMATCH[3]}] want the pipe ${BASH_REMATCH[2]};"; fi
            if [[ $m == 0 && ${BASH_REMATCH[3]} != "${BASH_REMATCH[1]} " ]]; then bad+=" direct: drained [${BASH_REMATCH[3]}] want the tty ${BASH_REMATCH[1]};"; fi
        else
            bad+=" $m: log=[${l//$'\n'/|}];"
        fi
        if [[ ! -e $FVP_ROOT/dfd$m/leftover || -n $left ]] || ! fvp_restored "dfd$m"; then bad+=" $m: leftover=$(printf '%q' "$left") $REPLY;"; fi
    done
    if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

    # R1: TERM ignored when the TUI's shell started
    fvp_case termign "$RPRE"'
cat > "$D/inner.sh" <<"IN"
D=$1; cd "$D" || exit 89
source "$2"; kk.uses fv.drivers || exit 90
note() { printf "%s\n" "$*" >> "$D/log"; }
kill -TERM $BASHPID
note "term-ignored"
export FV_TTY_READER=1
fv.video.initVideo || exit 91
printf "%s" "$__FV_VI_RPID" > "$D/rpid"; rp=$__FV_VI_RPID
t0=$EPOCHREALTIME; fv.video.doneVideo; t1=$EPOCHREALTIME
note "done $(kill -0 "$rp" 2>/dev/null || echo gone) ms=$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"
IN
( trap "" TERM; exec "$BASH" "$D/inner.sh" "$D" '"'$KBOOL'"' )
exit $?'
    fvp_run termign
    fvp_file termign log; l=$REPLY
    kt_test_start "${PTY_TITLES[12]}"
    if [[ $l =~ ^term-ignored$'\n'done\ gone\ ms=([0-9]+)$ ]] && (( BASH_REMATCH[1] < 1500 )) && fvp_restored termign; then
        kt_test_pass "doneVideo ${BASH_REMATCH[1]} ms"
    else
        kt_test_fail "log=[${l//$'\n'/|}] $REPLY"
    fi
}

if fvp_detect; then run_pty; else fvv_skip "${PTY_TITLES[@]}"; fi

kt_test_log "016_Reader.sh completed"
