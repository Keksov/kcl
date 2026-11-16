#!/usr/bin/env bash
# 011_ZeroFork.sh - fv.views never forks (PLAN.md rule 1; design §1.3: every
# plain function is fork-free):
#   * with PATH='' (no external command can run): the whole stage's path —
#     construction, the tree, navigation, geometry with GrowMode, the
#     elision through a user override, the guard and its repair, .delete —
#     works and prints no "command not found";
#   * the static scan (fv.video's 006 scanner): no $( ), backtick, process
#     substitution, pipe, ( ) subshell, & or coproc on any code line of
#     fv.views.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: no forks"

kt_test_start "PATH='': the stage's whole path works, no external command is looked for"
out=$("$BASH" -c "
source '$FVW_TESTS_DIR/../fv.views.sh'
class TU : TView
    public
        override proc SizeLimits
end
TU.SizeLimits() { inherited SizeLimits; FV_MIN_X=4; }
build TU
PATH=''
r=''
TGroup.new desk 0 1 80 24; r+=\$?
TGroup.new w1 0 0 40 20; TU.new u 1 1 2 2; TView.new v 0 0 3 3
w1_data[GrowMode]=\$FV_GF_GROWALL u_data[GrowMode]=\$(( FV_GF_GROWHIX | FV_GF_GROWREL ))
fv.views.insert desk w1; fv.views.insert w1 u; fv.views.insertBefore w1 v ''; r+=\$?
fv.views.makeFirst v; fv.views.putInFrontOf v ''; fv.views.first w1; r+=\$RESULT
fv.views.next u; fv.views.prev u; fv.views.nextView u; fv.views.prevView u || :
fv.views.locate u 0 0 1 1; fv.views.getBounds u; r+=\"|\$RESULT\"
fv.views.moveTo w1 5 5; fv.views.growTo w1 30 15; fv.views.changeBounds desk 0 1 100 30
fv.views.getBounds w1; r+=\"|\$RESULT\"
fv.views.makeLocal u 9 9; fv.views.makeGlobal u 0 0; fv.views.mouseInView u 0 0 || :
w1.GetHelpCtx; fv.views.delete w1 v
TView.new u 0 0 1 1 2>/dev/null || r+=\"|guard\$?\"
TView.new x__fvy 0 0 1 1 2>/dev/null || r+=\"|res\$?\"
fv.views._newReserved w1 frame TView 0 0 1 1; r+=\"|\$RESULT\"
u.delete; v.delete; x__fvy.delete; desk.delete
printf '%s' \"\$r\"" 2>&1)
want='00u|0 0 4 1|25 11 55 26|guard1|res2|w1__fvframe'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "the scanner flags a fork construct in a sample line and passes the safe ones"
bad=''
for s in 'x=$(cmd)' 'x=`cmd`' 'a | b' '( cd x )' 'cmd &' 'coproc cat'; do fvw_forks "$s" || bad+=" missed:[$s]"; done
for s in '(( a | b ))' 'x="$(( 1 + 2 ))"' '[[ a || b ]]' 'f() {' 'a=( 1 2 )' 'x >&2'; do if fvw_forks "$s"; then bad+=" false:[$s]"; fi; done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "fv.views.sh: no fork construct on any code line"
bad='' n=0 fn=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$FVW_TESTS_DIR/../fv.views.sh"
if [[ -z $bad ]] && (( n > 300 )); then kt_test_pass "$n lines clean"; else kt_test_fail "${bad:-only $n lines}"; fi

kt_test_log "011_ZeroFork.sh completed"
