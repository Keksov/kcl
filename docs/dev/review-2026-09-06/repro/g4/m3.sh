source /c/projects/kkbot/kbool/kcl/math/math.sh
p() { local r; r=$(math.$1 "${@:2}" 2>&1); echo "math.$* -> [$r]"; }
echo "--- inf tokens into engine"
p max +inf 1; p max inf 1; p min -inf 1; p ceil +inf; p sign +inf; p sign inf; p isZero inf; p sameValue inf inf; p compareValue inf 1 0.5; p ceil "$(math.exp 1000)"; p max "$(math.infinity)" 1
echo "--- frexp inf (hang?)"
timeout 5 bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; math.frexp +inf; echo done-inf'; echo "rc=$?"
timeout 5 bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; math.frexp nan; echo done-nan'; echo "rc=$?"
timeout 5 bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; math.frexp 1e308; echo done-big'; echo "rc=$?"
echo "--- temp file leak"
ls -la "${TMPDIR:-/tmp}"/.math_fe_*.awk 2>/dev/null | wc -l
bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; math.sin 1 >/dev/null; echo "progfile=$__MATH_FE_PROGFILE"; ls -la "$__MATH_FE_PROGFILE"' 
echo "after exit:"; ls "${TMPDIR:-/tmp}"/.math_fe_*.awk 2>/dev/null
echo "leaked count:"; ls "${TMPDIR:-/tmp}"/.math_fe_*.awk 2>/dev/null | wc -l
echo "--- \$() first call: coproc in subshell"
bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; x=$(math.sin 1); echo "x=$x active_in_parent=$(math.feActive) up=[$__MATH_FE_UP]"; y=$(math.cos 0); echo "y=$y"; pgrep -c awk'
echo "--- parent-started engine reused in \$()"
bash -c 'source /c/projects/kkbot/kbool/kcl/math/math.sh; math.feStart; x=$(math.sin 1); echo "x=$x"; y=$(math.cos 0); echo "y=$y"; pgrep -c awk'
