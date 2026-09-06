source /c/projects/kkbot/kbool/kcl/math/math.sh
echo "--- no awk: rc and output"
( PATH=; math.sin 1; echo "rc=$?" ; math.feStart; echo "feStart rc=$?" )
echo "--- user coproc + engine (bash $BASH_VERSION)"
coproc MYCP { cat; }
math.feStart; echo "feStart rc=$? active=$(math.feActive)"
echo hello >&"${MYCP[1]}"; read -t 2 -u "${MYCP[0]}" l; echo "user coproc still works: [$l]"
r=$(math.sin 0); echo "sin 0 -> [$r]"
echo "--- kill awk externally then call"
kill "$__MATH_FE_PID"; sleep 0.2
r=$(math.sin 0 2>&1); echo "after kill: sin 0 -> [$r]"
r=$(math.cos 0 2>&1); echo "after kill: cos 0 -> [$r]"
echo "--- echo -n / -e leaks"
r=$(math.ifThen true -n); echo "ifThen true -n -> [$r]"
r=$(math.randomFrom -n); echo "randomFrom -n -> [$r]"
r=$(math.min -e -e); echo "min -e -e -> [$r]"
r=$(math.ifThen false x ""); echo "ifThen false x '' -> [$r] (expected empty)"
echo "--- big stats array"
args=(); for ((i=0;i<20000;i++)); do args+=($i); done
r=$(math.mean "${args[@]}"); echo "mean 0..19999 -> [$r]"
echo "--- set -e"
bash -c 'set -e; source /c/projects/kkbot/kbool/kcl/math/math.sh; math.min 1 2; math.min 2 1; math.divMod 5 0 || true; math.max 3 3; echo "set -e survived"' 2>&1
bash -c 'set -e; source /c/projects/kkbot/kbool/kcl/math/math.sh; math.sign 0; math.inRange 5 1 3; math.ceil 0.5; math.floor -0.5; math.isZero 0; echo "set -e survived 2"' 2>&1
echo "--- locale"
bash -c 'export LC_ALL=de_DE.UTF-8; source /c/projects/kkbot/kbool/kcl/math/math.sh; echo "de: sin1=$(math.sin 1) roundTo=$(math.roundTo 2.5 0) mean=$(math.mean 1.5 2.5)"' 2>&1
bash -c 'export LC_ALL=de_DE.UTF-8 POSIXLY_CORRECT=1; source /c/projects/kkbot/kbool/kcl/math/math.sh; echo "de+posix: sin1=$(math.sin 1) mean=$(math.mean 1.5 2.5)"' 2>&1
bash -c 'export LC_NUMERIC=de_DE.UTF-8 AWKPATH=; source /c/projects/kkbot/kbool/kcl/math/math.sh; echo "LC_NUMERIC de: sin1=$(math.sin 1)"' 2>&1
echo "--- dec_cmp edge"
math._dec_cmp "1.5" "1.5.0"; echo "dec_cmp 1.5 vs 1.5.0 -> $REPLY"
math._num_cmp "+0" "-0"; echo "+0 -0 -> $REPLY"
math._num_cmp "" ""; echo "'' '' -> $REPLY"
math._num_cmp "12345678901234567890" "2"; echo "20digit vs 2 -> $REPLY"
math._num_cmp "-12345678901234567890" "-2"; echo "-20digit vs -2 -> $REPLY"
math._num_cmp "0.1" ".1"; echo "0.1 vs .1 -> $REPLY"
math._num_cmp "1." "1"; echo "1. vs 1 -> $REPLY"
