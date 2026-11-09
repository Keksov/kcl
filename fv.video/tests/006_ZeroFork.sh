#!/usr/bin/env bash
# 006_ZeroFork.sh - fv.video forks only where the plan allows it (PLAN.md rule
# 1: at start, on resize, at the end):
#   * with PATH='' (no external command can run): the WINCH trap, updateSize
#     over an overridden querySize, doneVideo while off and the failing
#     initVideo calls work;
#   * the static scan: a $( ), backtick, process substitution, pipe, ( )
#     subshell, & or coproc only inside initVideo, its trap setup and
#     querySize and the subshell trap drop; stty only in initVideo, querySize
#     and the restore.

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

kt_test_start "the scan flags each construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x="$(cmd)"' 'x=`cmd`' 'a > >(cmd)' 'printf x | read y' '( cd x; y )' 'cmd &' 'coproc cat'; do
    fvv_forks "$s" || bad+=" missed:[$s]"
done
for s in '(( a | b ))' '[[ a || b ]] || c' 'x="a|b"' '# x=$(cmd) | y' 'f() {' 'a=( 1 2 )' 'x >&2' 'a && b' '{ exec {f}>&-; } 2>/dev/null || :'; do
    if fvv_forks "$s"; then bad+=" false:[$s]"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.video.sh: fork constructs only in initVideo, _trap, _drop, querySize; stty only in initVideo, querySize, _restore"
bad='' n=0 fn='' forks='' sttys=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^(fv\.video\.[A-Za-z_]+)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if [[ $l == '}' ]]; then fn=''; fi
    if fvv_forks "$l"; then
        forks+=" ${fn:-file}"
        case $fn in fv.video.initVideo|fv.video._trap|fv.video._drop|fv.video.querySize) ;; *) bad+=" fork@$n(${fn:-file}):[$l]" ;; esac
    fi
    c=${l%%#*}
    if [[ $c =~ (^|[^A-Za-z0-9_.-])stty([^A-Za-z0-9_]|$) ]]; then
        sttys+=" ${fn:-file}"
        case $fn in fv.video.initVideo|fv.video.querySize|fv.video._restore) ;; *) bad+=" stty@$n(${fn:-file}):[$l]" ;; esac
    fi
done < "$FVV_TESTS_DIR/../fv.video.sh"
if [[ -z $bad && -n $forks && -n $sttys ]]; then kt_test_pass "$n lines; forks in:$forks; stty in:$sttys"; else kt_test_fail "${bad:-nothing found}"; fi

kt_test_log "006_ZeroFork.sh completed"
