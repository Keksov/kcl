#!/usr/bin/env bash
# 006_ZeroFork.sh - fv.video forks only where the plan allows it (PLAN.md rule
# 1: at start, on resize, at the end):
#   * with PATH='' (no external command can run): the WINCH trap, updateSize
#     over an overridden querySize, doneVideo while off and the failing
#     initVideo calls work; the reader (D13) forwards bytes, _rstart, a key
#     through its pipe and _rstop work;
#   * the static scan: a $( ), backtick, process substitution, pipe, ( )
#     subshell, & or coproc only inside initVideo, its trap setup and
#     querySize and the subshell trap drop, the reader start (_rstart: one
#     process substitution, D13) and the colour-depth detection (_depth:
#     `tput colors`); stty only in initVideo, querySize and the restore; tput
#     only in _depth; taskkill only in the reader stop (_rstop);
#   * the screen buffer with PATH='': initScreen, every write, updateScreen
#     (incremental and force), palette and depth changes, resizeScreen,
#     strWidth, ASCII mode, detectColorDepth when TERM tells (rule R1: every
#     write and every frame fork-free).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: forks only at init, resize and done"

kt_test_start "PATH='': the WINCH trap, updateSize over an overridden querySize, doneVideo off, failing initVideo"
out=$("$BASH" -c "
source '$FVV_TESTS_DIR/../fv.video.sh'
fv.video.querySize() { RESULT='33 111'; }
trap 'echo caller-winch' WINCH
fv.video._trap
PATH=''
r=''
FV_VIDEO_RESIZED=0
kill -WINCH \$BASHPID; r+=\"\$FV_VIDEO_RESIZED \"
fv.video.updateSize; r+=\"\$? \${FV_SCREEN_W}x\$FV_SCREEN_H \$FV_VIDEO_RESIZED \"
fv.video.querySize() { return 1; }
COLUMNS=70 LINES=20 fv.video.updateSize; r+=\"\${FV_SCREEN_W}x\$FV_SCREEN_H \"
fv.video.doneVideo; r+=\"\$? \"
fv.video.initVideo bad; r+=\"\$? \"
FV_TTY=/nonexistent/tty fv.video.initVideo; r+=\"\$?\"
fv.video._untrap
printf '%s' \"\$r\"" 2>&1)
want=$'caller-winch\n1 0 111x33 0 70x20 0 2 1'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

for setup in 'export LC_ALL=C.UTF-8' 'export LC_ALL=C' 'export LC_ALL=C.UTF-8; shopt -s nocasematch'; do
kt_test_start "PATH='': the screen buffer (init, writes, updates, palette, depth, resize, ASCII mode, invalid UTF-8) works and emits ($setup)"
out=$("$BASH" -c "
$setup
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>'$FVV_TMP/pathless.out'
PATH=''
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=20 FV_SCREEN_H=5
r=''
fv.video.initScreen; r+=\$?
fv.video.writeStr 1 1 'Привет ─│' A; r+=\$?
fv.video.writeBuf 0 2 'ab' 'Bc'; r+=\$?
fv.video.writeCStr 0 3 '~F~ile' 1 2; r+=\$?
fv.video.writeStr 12 3 \$'\\xff\\xe2\\x94a\\xc2\\x85' 1; r+=\$RESULT
fv.video.writeChar 0 4 '═' 3 5; r+=\$?
fv.video.fillRect 10 0 5 5 4 '░'; r+=\$?
fv.video.setClip 2 2 8 4; fv.video.writeStr 0 2 'clipped text' 5; fv.video.resetClip
fv.video.definePalette x 202 17 1; r+=\$?
fv.video.setCursorPos 3 3; fv.video.setCursorType 1
fv.video.updateScreen; r+=\$?
fv.video.setColorDepth 16; fv.video.updateScreen; r+=\$?
fv.video.updateScreen force; r+=\$?
fv.video.strWidth 'жук'; r+=\$RESULT
FV_SCREEN_W=10 FV_SCREEN_H=3 fv.video.resizeScreen; fv.video.clearScreen 1; fv.video.updateScreen; r+=\$?
TERM=xterm-256color fv.video.detectColorDepth; r+=\$RESULT
FV_ASCII=1 fv.video.initScreen; fv.video.writeStr 0 0 '╔═╗ж' 1; fv.video.updateScreen; r+=\${__FV_VS_CH[0]:0:4}
exec {fd}>&-
printf '%s' \"\$r\"" 2>&1)
size=$(wc -c < "$FVV_TMP/pathless.out" 2>/dev/null || echo 0)
if [[ $out == '0000400000030256+=+?' && $size -gt 500 ]]; then kt_test_pass "ok ($size bytes emitted)"; else kt_test_fail "got [$out] ($size bytes)"; fi
done

kt_test_start "PATH='': the reader (D13) forwards bytes and ends at end of file; _rstart, a key through the pipe, _rstop"
printf 'ab\001\377c' > "$FVV_TMP/rd.in"
rm -f "$FVV_TMP/rd.fifo"; mkfifo "$FVV_TMP/rd.fifo"
out=$("$KT_TIMEOUT" -k 2 20 "$BASH" -c "
source '$FVV_TESTS_DIR/../../../kbool.sh'
kk.uses fv.drivers || exit 90
exec {a}<>'$FVV_TMP/rd.fifo'
exec {t}<'$FVV_TMP/rd.in'
PATH=''
x=\$( ( fv.video._reader \$t \$\$ 0.5 500000 ) | { IFS= read -r -d '' -n 9 v; printf '%s' \"\${#v}\"; } )
FV_KEY_FD=\$a __FV_VI_FD=\$a
FV_TTY_READER=1 fv.video._rstart
p=\$__FV_VI_RPID
printf 'k' >&\$a
fv.keyboard.getKeyEvent 2; k=\$FV_KEY_CHAR
fv.video._rstop
kill -0 \"\$p\" 2>/dev/null && k+=alive
printf '%s %s' \"\$x\" \"\$k\"" 2>&1)
if [[ $out == '5 k' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [5 k]"; fi

kt_test_start "the scan flags each construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x="$(cmd)"' 'x=`cmd`' 'a > >(cmd)' 'printf x | read y' '( cd x; y )' 'cmd &' 'coproc cat'; do
    fvv_forks "$s" || bad+=" missed:[$s]"
done
for s in '(( a | b ))' '[[ a || b ]] || c' 'x="a|b"' '# x=$(cmd) | y' 'f() {' 'a=( 1 2 )' 'x >&2' 'a && b' '{ exec {f}>&-; } 2>/dev/null || :'; do
    if fvv_forks "$s"; then bad+=" false:[$s]"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.video.sh: fork constructs only in initVideo, _trap, _drop, querySize, _rstart, _depth; stty only in initVideo, querySize, _restore; tput only in _depth; taskkill only in _rstop"
bad='' n=0 fn='' forks='' sttys='' tputs='' tks=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^(fv\.video\.[A-Za-z_]+)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if [[ $l == '}' ]]; then fn=''; fi
    if fvv_forks "$l"; then
        forks+=" ${fn:-file}"
        case $fn in fv.video.initVideo|fv.video._trap|fv.video._drop|fv.video.querySize|fv.video._rstart|fv.video._depth) ;; *) bad+=" fork@$n(${fn:-file}):[$l]" ;; esac
    fi
    c=${l%%#*}
    if [[ $c =~ (^|[^A-Za-z0-9_.-])stty([^A-Za-z0-9_]|$) ]]; then
        sttys+=" ${fn:-file}"
        case $fn in fv.video.initVideo|fv.video.querySize|fv.video._restore) ;; *) bad+=" stty@$n(${fn:-file}):[$l]" ;; esac
    fi
    if [[ $c =~ (^|[^A-Za-z0-9_.-])tput([^A-Za-z0-9_]|$) ]]; then
        tputs+=" ${fn:-file}"
        if [[ $fn != fv.video._depth ]]; then bad+=" tput@$n(${fn:-file}):[$l]"; fi
    fi
    if [[ $c =~ (^|[^A-Za-z0-9_.-])taskkill([^A-Za-z0-9_]|$) ]]; then
        tks+=" ${fn:-file}"
        if [[ $fn != fv.video._rstop ]]; then bad+=" taskkill@$n(${fn:-file}):[$l]"; fi
    fi
done < "$FVV_TESTS_DIR/../fv.video.sh"
if [[ -z $bad && -n $forks && -n $sttys && -n $tputs && -n $tks ]]; then kt_test_pass "$n lines; forks in:$forks; stty in:$sttys; tput in:$tputs; taskkill in:$tks"; else kt_test_fail "${bad:-nothing found}"; fi

kt_test_log "006_ZeroFork.sh completed"
