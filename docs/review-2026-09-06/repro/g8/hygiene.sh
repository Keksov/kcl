#!/bin/bash
# Load-hygiene probe: snapshot shell state, source every unit, diff.
KCL=/c/projects/kkbot/kbool/kcl
snap() { set -o > "$1.seto"; shopt -p > "$1.shopt"; printf '%q\n' "$IFS" > "$1.ifs"; pwd > "$1.pwd"; trap -p > "$1.trap"; jobs -l > "$1.jobs"; compgen -v | sort > "$1.vars"; compgen -A function | sort > "$1.funcs"; }
G8=$(dirname "$0")
snap $G8/before
for u in "$@"; do
  # capture anything the source prints
  out=$(source "$KCL/$u/$u.sh" 2>&1 >/dev/null; echo "RC=$?")
  source "$KCL/$u/$u.sh" >$G8/src_$u.out 2>&1; rc=$?
  echo "## source $u rc=$rc stdout+stderr bytes=$(wc -c < $G8/src_$u.out)"
  [[ -s $G8/src_$u.out ]] && sed 's/^/   | /' $G8/src_$u.out | head -20
done
snap $G8/after
echo "## set -o diff"; diff $G8/before.seto $G8/after.seto
echo "## shopt diff"; diff $G8/before.shopt $G8/after.shopt
echo "## IFS before/after"; cat $G8/before.ifs $G8/after.ifs
echo "## pwd before/after"; cat $G8/before.pwd $G8/after.pwd
echo "## traps after"; cat $G8/after.trap
echo "## jobs after"; cat $G8/after.jobs
echo "## coproc fds"; ls -la /proc/$$/fd 2>/dev/null | grep -c pipe
echo "## new global vars (non-kklass class tables, non _DIR)"; comm -13 $G8/before.vars $G8/after.vars | grep -vE '^(__kk|kk_|KK_|_KK)' | grep -viE '_(data|class|items)$' | head -80
echo "## new global var count"; comm -13 $G8/before.vars $G8/after.vars | wc -l
echo "## new function count"; comm -13 $G8/before.funcs $G8/after.funcs | wc -l
echo "## lowercase/odd new globals"; comm -13 $G8/before.vars $G8/after.vars | grep -E '^[a-z]' | head -40
