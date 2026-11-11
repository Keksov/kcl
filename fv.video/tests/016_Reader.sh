#!/usr/bin/env bash
# 016_Reader.sh - the reader process and its watchdog (D13 + amendment): on
# Cygwin-family runtimes (and with FV_TTY_READER=1 anywhere) initVideo starts
# a reader that reads the terminal one byte at a time with BLOCKING reads and
# forwards each byte through a pipe (FV_KEY_FD), and a watchdog that does
# timed reads on a pipe from the owner (never the terminal) and stops the
# reader when that pipe ends or the owner is gone.
#   * without a terminal (every runtime, a fifo stands in for the terminal):
#     every byte forwarded unchanged (NUL included) and the end at end of
#     file, also under set -eEuxT / pipefail / ERR DEBUG RETURN traps / a
#     UTF-8 locale; the owner killed (no byte typed): both gone, also when a
#     child of the owner holds the watchdog pipe; the reader alone blocks and
#     ends at the next byte; signals (INT QUIT TSTP WINCH ignored by both);
#     _rstart / _rstop; FV_TTY_READER (0, 1, auto by OSTYPE, junk);
#     __FV_VI_POLL '' and junk; a reader or a watchdog that does not start;
#     TERM ignored at shell start; the stop's timing; the fds each keeps; no
#     signal to a pid that is not ours; the watchdog killed alone; data on
#     the watchdog pipe; the reader dying alone (the watchdog exits, nothing
#     is signalled); the stop while a child holds the watchdog pipe;
#   * on a real pty under util-linux script(1) (SKIP with reason ENV
#     elsewhere): both alive while on (two children); keys, NUL, a burst,
#     UTF-8 and mouse reports flow through the reader; Esc alone vs an Esc
#     sequence; both gone after doneVideo, exit without done, a set -e
#     failure, Ctrl+C typed, SIGTERM, SIGHUP and kill -9 of the main shell
#     (no byte typed; also with a child holding the watchdog pipe); re-init;
#     a subshell under an active parent; FV_TTY_READER=0 and auto; signals
#     to the reader alone; the reader killed -> end of input; the restore
#     drains through the pipe, never the terminal; TERM ignored at start; a
#     restore re-entered mid-stop drains only the pipe; an interactive
#     shell's fd 255 (the terminal) is held by neither child.
# Every reader / watchdog pid is recorded and reaped if it survives (a failure).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVV_TESTS_DIR/.." && pwd)/fv.video.sh"
KBOOL="$(cd "$FVV_TESTS_DIR/../../.." && pwd)/kbool.sh"
T=$FVV_TMP

kt_test_section "016: the reader process (D13)"

# child BODY — run BODY in a fresh bash (kbool + fv.drivers loaded, a fifo
# open read-write on $a as the "terminal"), at most 20 s; REPLY = its stdout,
# CHILD_ERR = its stderr. BODY puts reader pids into $T/pids (reaped after).
# Hardening (a child once hung past its timeout on MSYS2 with an empty log):
# the child's stdout goes to a file, not $( ), so the parent never waits on a
# pipe a leftover process inherited; the caller's line is the first word of
# the child's command line (a stray report shows it) and the breadcrumb
# $T/current; the child records its pid, and a child still alive after the
# timeout is reaped (fvp_reap: KILL, then taskkill) and counted in SURV.
child() {
    local d=$T/c$RANDOM$RANDOM cp=''
    mkdir -p "$d"
    printf '016_Reader: child of line %s\n' "${BASH_LINENO[0]}" > "$T/current"
    "$KT_TIMEOUT" -k 2 20 "$BASH" -c ": child-of-line-${BASH_LINENO[0]}
echo \$\$ > '$d/pid'
cd '$d' || exit 89
source '$KBOOL'
kk.uses fv.drivers || exit 90
mkfifo '$d/f' || exit 88
exec {a}<>'$d/f'
pids() { printf '%s\n' \"\$@\" >> '$T/pids'; }
gone() { local i; for (( i = 0; i < \${2:-40}; i++ )); do kill -0 \"\$1\" 2>/dev/null || return 0; sleep 0.05; done; return 1; }
$1" > "$d/out" 2> "$d/err"
    REPLY=$(<"$d/out")
    CHILD_ERR=$(<"$d/err")
    if [[ -r $d/pid ]]; then read -r cp < "$d/pid" || :; fi
    if [[ -n $cp && $cp != *[!0-9]* ]] && kill -0 "$cp" 2>/dev/null; then
        fvp_reap "$cp"
        SURV+=" child:$cp"
    fi
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

PURE_TITLES=("bytes unchanged" "owner killed" "owner killed, a child holds the watchdog pipe" "reader alone: blocking" "signals"
    "_rstart/_rstop" "FV_TTY_READER auto" "a junk FV_TTY_READER" "__FV_VI_POLL empty" "a bad __FV_VI_POLL" "no reader start"
    "no watchdog start" "TERM ignored" "TERM obeyed" "fds closed" "ppid check" "watchdog killed alone" "data on the watchdog pipe" "reader dies alone" "stop with a pipe holder")
if [[ -z ${KT_TIMEOUT-} ]]; then
    for t in "${PURE_TITLES[@]}"; do
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
( fv.video._reader "$t" $$ 500000 ) > out.bin
r="eof "
cmp -s out.bin '"'$T/all.bin'"' && r+="same "
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
pids "$__FV_VI_RPID" "$__FV_VI_WPID"
printf "a\0\377" >&$a
fv.keyboard.getKeyEvent 2; r+="$FV_KEY_CHAR,"
fv.keyboard.getKeyEvent 2; r+="$FV_KEY,"
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
fv.video._rstop
echo "$r"'
e=$CHILD_ERR
re="read -r -n1 -d '' (-t [0-9.]+ )?-u [0-9]+ __fvv_c"
while IFS= read -r l; do
    if [[ $l == ERR-TRAP || $l =~ $re ]]; then REPLY+=" stderr:[$l]"; fi
done <<< "$e"
check "the reader forwards all 256 byte values unchanged (NUL too) and ends at end of file; _rstart works under set -eEuxT, pipefail, ERR/DEBUG/RETURN traps and a UTF-8 locale; no reader / watchdog trace or ERR on stderr" \
    "eof same a,kbCtrlSpace,kbUnknown " "$REPLY"

# owner — an inner bash (the owner) starts the reader + watchdog on the fifo,
# records the pids, then kills itself with SIGKILL (no byte is ever typed);
# with HOLD a child of the owner holds the watchdog pipe (no end of file:
# the watchdog's owner check acts). REPLY = "gone MS" or "alive"
owner() {
    child '
cat > inner.sh <<"IN"
source "$1"; kk.uses fv.drivers || exit 90
exec {a}<>"$2"
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
printf "%s\n" "$__FV_VI_RPID" "$__FV_VI_WPID" >> "$3"
printf "%s %s\n" "$__FV_VI_RPID" "$__FV_VI_WPID" > pr
if [[ $4 == hold ]]; then sleep 4 & printf "%s" "$!" > sp; fi
printf "%s" "$EPOCHREALTIME" > t0
kill -KILL $BASHPID
IN
"$BASH" inner.sh '"'$KBOOL'"' "$PWD/f" '"'$T/pids'"' '"$1"'
read -r rp wp < pr
for (( i = 0; i < 80; i++ )); do kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null || break; sleep 0.05; done
t1=$EPOCHREALTIME t0=$(<t0)
if [[ -s sp ]]; then kill "$(<sp)" 2>/dev/null; fi
if kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null; then echo alive; else echo "gone $(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"; fi'
}
owner nohold; r=$REPLY
kt_test_start "the owner killed (SIGKILL), no byte typed: the watchdog (end of file on its pipe) stops the blocked reader; both gone within 3 s (~0.1 s here)"
if [[ $r == gone\ * ]] && (( ${r#gone } <= 3000 )) && [[ -z $SURV ]]; then kt_test_pass "${r#gone } ms"; else kt_test_fail "[$r]${SURV:+ survivors:$SURV}"; fi
SURV=''
owner hold; r=$REPLY
kt_test_start "the owner killed while its child holds the watchdog pipe: the watchdog's owner check (every 0.5 s) stops the reader; both gone within 4 s (~0.6 s here)"
if [[ $r == gone\ * ]] && (( ${r#gone } <= 4000 )) && [[ -z $SURV ]]; then kt_test_pass "${r#gone } ms"; else kt_test_fail "[$r]${SURV:+ survivors:$SURV}"; fi
SURV=''

child '
: "a pid that cannot run (above any pid_max): never a reaped pid that might be reused"
dead=2147483646
fv.video._reader "$a" "$dead" 200000 > b.out & r2=$!; pids "$r2"
r=""
sleep 0.6
kill -0 "$r2" 2>/dev/null && r+="blocking-alive "
printf q >&$a
gone "$r2" 60 && r+="gone-at-byte "
echo "$r[$(<b.out)]"'
check "the reader alone, its owner gone: it blocks (no timed read) and ends at the next byte, which it still forwards" \
    "blocking-alive gone-at-byte [q]" "$REPLY"

child '
fv.video._reader "$a" $$ 200000 > s.out & r=$!; pids "$r"
sleep 0.3
kill -INT "$r"; kill -QUIT "$r"; kill -TSTP "$r"; kill -WINCH "$r"
sleep 0.3; printf x >&$a; sleep 0.3
o=""
kill -0 "$r" 2>/dev/null && o+="alive "
o+="[$(<s.out)] "
kill -TERM "$r"; gone "$r" && o+="term "
fv.video._reader "$a" $$ 200000 > /dev/null & r=$!; pids "$r"
sleep 0.2
kill -HUP "$r"; gone "$r" && o+="hup "
exec {p}< <(fv.video._reader "$a" $$ 200000); r=$!; pids "$r"
exec {p}<&-
sleep 0.2
printf yz >&$a
gone "$r" && o+="pipe "
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
w=$__FV_VI_WPID; pids "$__FV_VI_RPID" "$w"
sleep 0.3
kill -INT "$w"; kill -QUIT "$w"; kill -TSTP "$w"; kill -WINCH "$w"
sleep 0.8
st=""; if [[ -r /proc/$w/stat ]]; then read -r st < "/proc/$w/stat"; st=${st##*) }; fi
kill -0 "$w" 2>/dev/null && kill -0 "$__FV_VI_RPID" 2>/dev/null && [[ $st != T* ]] && o+="wd-alive"
fv.video._rstop
echo "$o"'
check "signals: the reader ignores INT, QUIT, TSTP and WINCH (alive, still forwarding), TERM / HUP / a write to a closed pipe end it; the watchdog ignores INT, QUIT, TSTP and WINCH too" \
    "alive [x] term hup pipe wd-alive" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart; r="$? "
rp=$__FV_VI_RPID rf=$__FV_VI_RFD wp=$__FV_VI_WPID wf=$__FV_VI_WFD; pids "$rp" "$wp"
if [[ -n $rp && -n $wp && $FV_KEY_FD == "$rf" && $rf != "$a" && -n $wf ]] && kill -0 "$rp" && kill -0 "$wp"; then r+="on "; fi
printf "k\033[B" >&$a
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
fv.keyboard.getKeyEvent 2; r+="$FV_KEY "
t0=$EPOCHREALTIME
fv.video._rstop; r+="$? "
t1=$EPOCHREALTIME
kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null || r+="gone "
if [[ ! -e /dev/fd/$rf && ! -e /dev/fd/$wf && -z $__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD ]]; then r+="closed "; fi
(( (${t1//[.,]/} - ${t0//[.,]/}) < 1000000 )) && r+="fast "
FV_KEY_FD=$a
FV_TTY_READER=0 fv.video._rstart
if [[ -z $__FV_VI_RPID$__FV_VI_WPID && $FV_KEY_FD == "$a" ]]; then r+="off"; fi
echo "$r"'
check "_rstart / _rstop with a fifo as the terminal: FV_TTY_READER=1 starts the reader and its watchdog (FV_KEY_FD = the pipe, keys read through it); _rstop ends both within 1 s, clears the globals, closes both pipes; FV_TTY_READER=0 starts none" \
    "0 on kbChar kbDown 0 gone closed fast off" "$REPLY"

child '
r=""
for o in linux-gnu darwin23 freebsd14.1 msys cygwin; do
    FV_KEY_FD=$a __FV_VI_FD=$a
    OSTYPE=$o FV_TTY_READER= fv.video._rstart
    if [[ -n $__FV_VI_RPID ]]; then pids "$__FV_VI_RPID" "$__FV_VI_WPID"; r+="$o:on "; fv.video._rstop; else r+="$o:off "; fi
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
pids "$__FV_VI_RPID" "$__FV_VI_WPID"; fv.video._rstop'
e=${CHILD_ERR//$'\n'/|}
[[ $e == "Error: fv.video.initVideo: FV_TTY_READER='yes' is not 0, 1 or empty; using auto|Error: fv.video.initVideo: FV_TTY_READER=' 1' is not 0, 1 or empty; using auto" ]] || REPLY+=" stderr:[$e]"
check "a junk FV_TTY_READER: one debug line, then auto" "auto-off auto-on" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
VERBOSE_KKLASS=debug __FV_VI_POLL="" FV_TTY_READER=1 fv.video._rstart
pids "$__FV_VI_RPID" "$__FV_VI_WPID"
printf m >&$a
fv.keyboard.getKeyEvent 2; r="$FV_KEY_CHAR "
fv.video._rstop; r+="$?"
echo "$r"'
[[ -z $CHILD_ERR ]] || REPLY+=" stderr:[$CHILD_ERR]"
check "__FV_VI_POLL='' means 0.5 s (no debug line): keys flow, the stop works" "m 0" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
__FV_VI_POLL=fast VERBOSE_KKLASS=debug FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID; pids "$rp" "$__FV_VI_WPID"
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
r+="[$__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD] "
[[ $FV_KEY_FD == "$a" ]] && r+="direct "
unset -f kill
gone "$rp" 20 && r+="gone"
echo "$r"'
[[ $CHILD_ERR == "Error: fv.video.initVideo: the terminal reader did not start; reading the terminal directly" ]] || REPLY+=" stderr:[$CHILD_ERR]"
check "a reader that does not start (kill -0 fails in the owner only; the reader itself would live on): rc 0, no watchdog, the terminal read directly, one debug line, the started process killed (SIGKILL, no TERM needed) and gone within 1 s" "0 [] direct gone" "$REPLY"

child '
M=$BASHPID
kill() { if [[ $1 == -0 && $BASHPID == "$M" && -n $__FV_VI_RPID && $2 != "$__FV_VI_RPID" ]]; then printf "%s" "$__FV_VI_RPID" > rp; return 1; fi; builtin kill "$@"; }
FV_KEY_FD=$a __FV_VI_FD=$a
VERBOSE_KKLASS=debug FV_TTY_READER=1 fv.video._rstart; r="$? "
wp=$!; pids "$wp"
rp=$(<rp); pids "$rp"
r+="[$__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD] "
[[ $FV_KEY_FD == "$a" ]] && r+="direct "
unset -f kill
gone "$wp" 30 && gone "$rp" 30 && r+="gone"
echo "$r"'
[[ $CHILD_ERR == "Error: fv.video.initVideo: the terminal reader's watchdog did not start; reading the terminal directly" ]] || REPLY+=" stderr:[$CHILD_ERR]"
check "a watchdog that does not start (kill -0 fails for it): the reader is stopped too (never a reader without a watchdog), the terminal read directly, one debug line, both gone" "0 [] direct gone" "$REPLY"

child '
cat > inner.sh <<"IN"
source "$1"; kk.uses fv.drivers || exit 90
exec {a}<>"$2"
kill -TERM $BASHPID
r="term-ignored "
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID; printf "%s\n" "$rp" "$wp" >> "$3"
t0=$EPOCHREALTIME; fv.video._rstop; rc=$?; t1=$EPOCHREALTIME
ms=$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))
r+="rc=$rc "
kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null || r+="gone "
(( ms < 2000 )) && r+="fast"
echo "$r|$ms"
IN
( trap "" TERM; exec "$BASH" inner.sh '"'$KBOOL'"' "$PWD/f" '"'$T/pids'"' )'
MS=${REPLY##*|}; REPLY=${REPLY%|*}
check "TERM ignored when the shell started (bash cannot reset it in the reader or the watchdog): _rstop still ends both (KILL after 0.1 s) within 2 s (${MS} ms)" "term-ignored rc=0 gone fast" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
pids "$__FV_VI_RPID" "$__FV_VI_WPID"
sleep 0.3
t0=$EPOCHREALTIME; fv.video._rstop; t1=$EPOCHREALTIME
echo "$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"'
check "_rstop of a reader and watchdog that obey TERM: under 1.5 s (timing: ${REPLY} ms)" "1" "$(( REPLY < 1500 ))"

rm -f "$T/f2"; mkfifo "$T/f2"
child '
exec {x}</dev/null
exec {y}<>'"'$T/f2'"'
exec {z}> >(read -r v)
pids "$!"
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID rf=$__FV_VI_RFD; pids "$rp" "$wp"
sleep 0.3
if [[ ! -d /proc/$rp/fd ]]; then echo "n/a"; fv.video._rstop; exit 0; fi
# three snapshots ~50 ms apart, only the fds in all three count: the
# watchdog reading /proc/PID/stat holds that file and the saved stdin for a
# moment
fds() { local f s=" "; for f in /proc/"$1"/fd/*; do s+="${f##*/} "; done; FDS=$s; }
fds "$rp"; r1=$FDS; fds "$wp"; w1=$FDS; sleep 0.05
fds "$rp"; r2=$FDS; fds "$wp"; w2=$FDS; sleep 0.05
fds "$rp"; r3=$FDS; fds "$wp"; w3=$FDS
bad="" seen=""
for n in $r1; do
    [[ $r2 == *" $n "* && $r3 == *" $n "* ]] || continue
    case $n in 0|1|2|255) ;; "$a") seen=1 ;; *) bad+=" r$n" ;; esac
done
for n in $w1; do
    [[ $w2 == *" $n "* && $w3 == *" $n "* ]] || continue
    case $n in 0|1|2|255) ;; *) bad+=" w$n" ;; esac
done
fv.video._rstop
exec {z}>&-
if [[ -z $bad && -n $seen ]]; then echo "only 0 1 2 tty / 0 1 2"; else echo "extra:$bad x=$x y=$y z=$z a=$a rf=$rf"; fi'
if [[ $REPLY == n/a ]]; then kt_test_start "the reader holds only fds 0, 1, 2 and the terminal; the watchdog only 0, 1, 2"; kt_test_pass "SKIP: no /proc/PID/fd"; SURV=''
else check "the reader holds only fds 0, 1, 2 and the terminal; the watchdog only 0, 1, 2 (never the reader's pipe nor the terminal); the owner's other fds (a file, a fifo, a process-substitution pipe) are closed in both" "only 0 1 2 tty / 0 1 2" "$REPLY"; fi

child '
( sleep 5 > /dev/null 2>&1 & echo $! > sp )
v=$(<sp)
( sleep 5 > /dev/null 2>&1 & echo $! > sp2 )
w=$(<sp2)
if [[ ! -r /proc/$v/ppid ]]; then kill "$v" "$w"; echo "n/a"; exit 0; fi
exec {q}</dev/null
exec {q2}>/dev/null
__FV_VI_RPID=$v __FV_VI_RFD=$q __FV_VI_WPID=$w __FV_VI_WFD=$q2
fv.video._rstop; r="$? "
kill -0 "$v" 2>/dev/null && kill -0 "$w" 2>/dev/null && r+="alive "
[[ ! -e /dev/fd/$q && ! -e /dev/fd/$q2 && -z $__FV_VI_RPID$__FV_VI_RFD$__FV_VI_WPID$__FV_VI_WFD ]] && r+="closed"
kill "$v" "$w" 2>/dev/null
echo "$r"'
if [[ $REPLY == n/a ]]; then kt_test_start "_rstop never signals a pid that is not its child (/proc/PID/ppid)"; kt_test_pass "SKIP: no /proc/PID/ppid"; SURV=''
else check "_rstop never signals a reader or watchdog pid whose /proc/PID/ppid is not this shell (a reused pid): no signal, both pipes still closed" "0 alive closed" "$REPLY"; fi

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID; pids "$rp" "$wp"
kill -KILL "$wp"
sleep 0.3
r=""; kill -0 "$rp" 2>/dev/null && r+="reader-alive "
printf "j" >&$a
fv.keyboard.getKeyEvent 2; r+="$FV_KEY_CHAR "
fv.video._rstop; r+="$? "
kill -0 "$rp" 2>/dev/null || r+="gone"
echo "$r"'
check "the watchdog killed alone: the reader still forwards, and _rstop still stops it" "reader-alive j 0 gone" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID; pids "$rp" "$wp"
printf x >&"$__FV_VI_WFD"
r=""
gone "$rp" 30 && r+="reader-gone "
gone "$wp" 30 && r+="wd-gone "
fv.video._rstop; r+="$?"
echo "$r"'
check "data on the watchdog's pipe (only the owner writes there): the watchdog stops the reader and exits; _rstop afterwards is clean" "reader-gone wd-gone 0" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID; pids "$rp" "$wp"
sleep 0.3
kill -HUP "$rp"
r=""
gone "$rp" 20 && r+="reader-gone "
gone "$wp" 30 && r+="wd-exited "
: > klog
kill() { if [[ $1 != -0 ]]; then printf "%s\n" "$*" >> klog; fi; builtin kill "$@"; }
fv.video._rstop; r+="$? "
unset -f kill
[[ -s klog ]] && r+="signalled:$(tr "\n" " " < klog)" || r+="no-signal"
echo "$r"'
check "the reader dies by itself (HUP): the watchdog exits by itself within ~0.5 s without a signal, and _rstop then signals nothing" "reader-gone wd-exited 0 no-signal" "$REPLY"

child '
FV_KEY_FD=$a __FV_VI_FD=$a
FV_TTY_READER=1 fv.video._rstart
rp=$__FV_VI_RPID wp=$__FV_VI_WPID; pids "$rp" "$wp"
sleep 3 & h=$!
sleep 0.3
t0=$EPOCHREALTIME; fv.video._rstop; rc=$?; t1=$EPOCHREALTIME
kill "$h" 2>/dev/null
r="$rc "
kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null || r+="gone"
echo "$r|$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"'
MS=${REPLY##*|}; REPLY=${REPLY%|*}
if [[ $MS == *[!0-9]* || -z $MS ]] || (( MS >= 1500 )); then REPLY+=" slow:${MS}"; fi
check "_rstop while a background child of the owner holds the watchdog pipe: no wait for the watchdog (SIGKILL + wait), under 1.5 s (${MS} ms)" "0 gone" "$REPLY"

fi

# --- on a real pty (script(1)) ---------------------------------------------

# the child helpers: rec [N] = the reader's pid to rpidN, the watchdog's to
# rpidwN (fvp_run reaps both); alive PID; kids = REPLY = the number of this
# process's children (fork-free, /proc/*/stat)
RPRE='
rec() { printf "%s" "$__FV_VI_RPID" > "$D/rpid${1-}"; printf "%s" "$__FV_VI_WPID" > "$D/rpidw${1-}"; }
alive() { [[ -n $1 ]] && kill -0 "$1" 2>/dev/null; }
kids() { local f s n=0; for f in /proc/[0-9]*/stat; do s=""; read -r s 2>/dev/null < "$f" || continue; s=${s##*) }; s=${s#* }; s=${s%% *}; if [[ $s == "$BASHPID" ]]; then n=$(( n + 1 )); fi; done; REPLY=$n; }
'
# what auto (FV_TTY_READER unset) gives on this runtime
if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then AUTO=on; else AUTO=off; fi

PTY_TITLES=("the reader and its watchdog are alive while on, the only two children; FV_KEY_FD = the reader's pipe, FV_TTY_FD the tty"
    "keys through the reader: chars, NUL, a CSI key, an SGR mouse report, UTF-8, a 300-byte burst in order"
    "doneVideo: the reader and the watchdog gone, the pipes closed, FV_KEY_FD back, no child left"
    "Esc alone -> kbEsc after the Esc timeout (10-500 ms); an Esc sequence in one write -> kbUp"
    "exit paths (doneVideo, exit 3, set -e, Ctrl+C typed, SIGTERM, SIGHUP): the reader and the watchdog alive while on, both gone after, statuses 0/3/1/130/143/129, terminal restored, SIGTERM / SIGHUP end the child within 3 s"
    "kill -9 of the main shell, no byte typed (pty held open): the watchdog stops the blocked reader; both gone within 3 s"
    "kill -9 of the main shell while its child holds the watchdog pipe, no byte typed: the watchdog's owner check stops the reader; both gone within 4 s"
    "re-init: done stops the first reader and watchdog, init starts one new pair (two children), keys flow, done stops them"
    "a subshell's initVideo / doneVideo under an active parent leave the parent's reader alone"
    "FV_TTY_READER=0: no reader, FV_KEY_FD = FV_TTY_FD, keys read directly; empty: auto ($AUTO here)"
    "INT QUIT TSTP WINCH sent to the reader alone: ignored, keys still flow; HUP kills it: getEvent -> end of input, doneVideo still restores"
    "the restore drains through the reader's pipe and never reads the terminal (FV_TTY_READER=1); without a reader it drains the terminal (=0); nothing left over either way"
    "TERM ignored when the TUI's shell started: doneVideo still stops the reader and the watchdog (KILL) and restores, within 3 s"
    "a restore re-entered in the middle of the stop (a signal) drains only the reader's pipe, never the terminal; the terminal is restored"
    "an interactive shell (bash -i: fd 255 is the terminal): neither the reader nor the watchdog holds fd 255")

# k9watch DIR — after the kill: wait (<= 5 s, nothing typed) until the reader
# and the watchdog are gone; DIR/k9 = the ms since the kill, or "alive"
k9watch() {
    local d=$1 p w i t0 t1
    p=$(<"$d/rpid") w=$(<"$d/rpidw")
    for (( i = 0; i < 100; i++ )); do kill -0 "$p" 2>/dev/null || kill -0 "$w" 2>/dev/null || break; sleep 0.05; done
    t1=$EPOCHREALTIME t0=$(<"$d/t_mark")
    if kill -0 "$p" 2>/dev/null || kill -0 "$w" 2>/dev/null; then echo alive > "$d/k9"; else echo "$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))" > "$d/k9"; fi
    if [[ -s $d/hk ]]; then kill "$(<"$d/hk")" 2>/dev/null; fi
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
wp=$__FV_VI_WPID wf=$__FV_VI_WFD
note "on $(alive "$rp" && alive "$wp" && echo alive) $([[ $FV_KEY_FD == "$rf" && ! -t $FV_KEY_FD && -t $FV_TTY_FD ]] && echo pipe) kids=$REPLY"
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
note "after $(alive "$rp" || alive "$wp" || echo gone) $([[ ! -e /dev/fd/$rf && ! -e /dev/fd/$wf ]] && echo closed) key=$FV_KEY_FD kids=$REPLY"
exit 0'
    fvp_run keys ready sleep:0.3 'type:ab\0\e[A\e[<0;3;4M\xd0\xb6' sleep:0.2 "type:${X300}Z"
    fvp_file keys log; l=$REPLY
    kt_test_start "${PTY_TITLES[0]}"
    if [[ $l == *'on alive pipe kids=2'* && -s $FVP_ROOT/keys/rpid && -s $FVP_ROOT/keys/rpidw ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}]"; fi
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
alive "$__FV_VI_RPID" && alive "$__FV_VI_WPID" && note alive
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
        # reaps no child): the child still ends within 3 s of the signal
        if [[ -s $FVP_ROOT/${c%:*}/t_mark && -s $FVP_ROOT/${c%:*}/t_end ]]; then
            fvp_file "${c%:*}" t_mark; t0=$REPLY
            fvp_file "${c%:*}" t_end
            ms=$(( (${REPLY//[.,]/} - ${t0//[.,]/}) / 1000 ))
            if (( ms > 3000 )); then bad+=" ${c%:*}: ended ${ms} ms after the signal;"; fi
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
fv.video.initVideo || exit 91
rec
sleep 6 & printf "%s" "$!" > "$D/hk"
: > "$D/hold"
: > "$D/ready"
while fv.drivers.getEvent; do :; done'
    fvp_run k9b ready sleep:0.3 sig:KILL call:k9watch
    fvp_file k9b k9; l=$REPLY
    kt_test_start "${PTY_TITLES[6]}"
    if [[ $l != *[!0-9]* && -n $l ]] && (( l <= 4000 )) && [[ ! -e $FVP_ROOT/k9b/survivors ]]; then
        kt_test_pass "gone ${l} ms after the kill"
    else
        kt_test_fail "k9=[$l] $(cat "$FVP_ROOT/k9b/survivors" 2>/dev/null)"
    fi

    fvp_case reinit "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec 1; p1=$__FV_VI_RPID w1=$__FV_VI_WPID
fv.video.doneVideo
r=""; alive "$p1" || alive "$w1" || r+="old-gone "
fv.video.initVideo || exit 92
rec 2; p2=$__FV_VI_RPID w2=$__FV_VI_WPID
kids
alive "$p2" && alive "$w2" && r+="new-alive "
note "reinit ${r}kids=$REPLY"
: > "$D/ready"
fv.keyboard.getKeyEvent 3; note "key $FV_KEY_CHAR"
fv.video.doneVideo
kids
note "end $(alive "$p2" || alive "$w2" || echo gone) kids=$REPLY"
exit 0'
    fvp_run reinit ready sleep:0.2 type:q
    fvp_file reinit log; l=$REPLY
    kt_test_start "${PTY_TITLES[7]}"
    if [[ $l == $'reinit old-gone new-alive kids=2\nkey q\nend gone kids=0' ]] && fvp_restored reinit; then kt_test_pass "ok"; else kt_test_fail "log=[${l//$'\n'/|}] $REPLY"; fi

    fvp_case sub "$RPRE"'
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec; p=$__FV_VI_RPID w=$__FV_VI_WPID
x=$(fv.video.initVideo; fv.video.doneVideo; printf v)
( fv.video.doneVideo; exit 0 )
note "sub x=$x $(alive "$p" && alive "$w" && echo alive) $([[ $__FV_VI_RPID == "$p" && $FV_KEY_FD == "$__FV_VI_RFD" ]] && echo same)"
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
printf "%s" "$__FV_VI_RPID" > "$D/rpid"; printf "%s" "$__FV_VI_WPID" > "$D/rpidw"; rp=$__FV_VI_RPID wp=$__FV_VI_WPID
t0=$EPOCHREALTIME; fv.video.doneVideo; t1=$EPOCHREALTIME
note "done $(kill -0 "$rp" 2>/dev/null || kill -0 "$wp" 2>/dev/null || echo gone) ms=$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))"
IN
( trap "" TERM; exec "$BASH" "$D/inner.sh" "$D" '"'$KBOOL'"' )
exit $?'
    fvp_run termign
    fvp_file termign log; l=$REPLY
    kt_test_start "${PTY_TITLES[12]}"
    if [[ $l =~ ^term-ignored$'\n'done\ gone\ ms=([0-9]+)$ ]] && (( BASH_REMATCH[1] < 3000 )) && fvp_restored termign; then
        kt_test_pass "doneVideo ${BASH_REMATCH[1]} ms"
    else
        kt_test_fail "log=[${l//$'\n'/|}] $REPLY"
    fi

    # R12: a restore re-entered in the middle of the stop never reads the terminal
    fvp_case reent "$RPRE"'
eval "$(declare -f fv.video._drain | sed "1s/^fv\.video\._drain/__o_drain/")"
fv.video._drain() { printf "%s\n" "$1" >> "$D/drainfd"; __o_drain "$@"; }
eval "$(declare -f fv.video._rkill | sed "1s/^fv\.video\._rkill/__o_rkill/")"
fv.video._rkill() { if [[ ! -e $D/nested ]]; then : > "$D/nested"; fv.video._restore; note "nested done act=$__FV_VI_ACT"; fi; __o_rkill "$@"; }
export FV_TTY_READER=1
fv.video.initVideo || exit 91
rec
note "fds tty=$FV_TTY_FD rfd=$__FV_VI_RFD"
: > "$D/ready"
fv.video.doneVideo
note "drained $(tr "\n" " " < "$D/drainfd")"
exit 0'
    fvp_run reent
    fvp_file reent log; l=$REPLY
    kt_test_start "${PTY_TITLES[13]}"
    if [[ $l =~ ^fds\ tty=([0-9]+)\ rfd=([0-9]+)$'\n'nested\ done\ act=0$'\n'drained\ (.*)$ ]] && [[ " ${BASH_REMATCH[3]}" != *" ${BASH_REMATCH[1]} "* ]] && fvp_restored reent; then
        kt_test_pass "ok (drained: ${BASH_REMATCH[3]}; tty ${BASH_REMATCH[1]})"
    else
        kt_test_fail "log=[${l//$'\n'/|}] $REPLY"
    fi

    # R16: an interactive shell keeps the terminal on fd 255; the reader and
    # the watchdog must not hold it there
    fvp_case inter "$RPRE"'
cat > "$D/inner.sh" <<"IN"
D=$1; cd "$D" || exit 89
source "$2"; kk.uses fv.drivers || exit 90
note() { printf "%s\n" "$*" >> "$D/log"; }
export FV_TTY_READER=1
fv.video.initVideo || exit 91
printf "%s" "$__FV_VI_RPID" > "$D/rpid"; printf "%s" "$__FV_VI_WPID" > "$D/rpidw"
sleep 0.3
t=no; [[ -t 255 ]] && t=yes
r=""
for p in "$__FV_VI_RPID" "$__FV_VI_WPID"; do
    if [[ ! -d /proc/$p/fd ]]; then r+="n/a "; elif [[ -e /proc/$p/fd/255 ]]; then r+="255 "; else r+="none "; fi
done
note "owner255=$t children: $r"
fv.video.doneVideo
IN
"$BASH" -i "$D/inner.sh" "$D" '"'$KBOOL'"'
exit $?'
    fvp_run inter
    fvp_file inter log; l=$REPLY
    kt_test_start "${PTY_TITLES[14]}"
    if [[ $l == 'owner255=yes children: none none ' || $l == 'owner255=yes children: n/a n/a ' ]] && fvp_restored inter; then
        kt_test_pass "ok ($l)"
    elif [[ $l == owner255=no* ]] && fvp_restored inter; then
        kt_test_pass "SKIP: fd 255 of bash -i is not the terminal here ($l)"
    else
        kt_test_fail "log=[$l] $REPLY"
    fi
}

if fvp_detect; then run_pty; else fvv_skip "${PTY_TITLES[@]}"; fi

kt_test_log "016_Reader.sh completed"
