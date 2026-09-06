#!/bin/bash
KCL=/c/projects/kkbot/kbool/kcl
G8=$(dirname "$0")
units="dateutils math tarray tcustomapplication tdictionary tdirectory tfile thashset tinifile tlist tobjectlist tpath tqueuestack tregex tstopwatch tstringhelper tstringlist"
set -o > $G8/b.seto; shopt -p > $G8/b.shopt; compgen -v | sort > $G8/b.vars; trap -p > $G8/b.trap
for __u in $units; do
  source "$KCL/$__u/$__u.sh" >$G8/all_src_$__u.out 2>&1; __rc=$?
  [[ $__rc -ne 0 || -s $G8/all_src_$__u.out ]] && { echo "## source $__u rc=$__rc"; sed 's/^/   | /' $G8/all_src_$__u.out | head -10; }
done
echo "## set -o diff"; set -o | diff $G8/b.seto -
echo "## shopt diff"; shopt -p | diff $G8/b.shopt -
echo "## IFS"; printf '%q\n' "$IFS"
echo "## pwd"; pwd
echo "## traps"; trap -p
echo "## jobs"; jobs -l
echo "## coproc vars"; compgen -v | grep -iE 'coproc|_PID|MATH_' 
echo "## fds"; ls -la /proc/$$/fd 2>/dev/null | awk '{print $NF}' | grep -v '^/dev' | head
echo "## new non-class globals"
compgen -v | sort | comm -13 $G8/b.vars - | grep -vE '^(T[A-Za-z]+|kk|KK|__kk|_KK)' | grep -vE '^__(u|rc)$' | tr '\n' ' '; echo
echo "## new T* non-class-table globals (heuristic: no _decl_/_class_/_method_/_static_/_property_/_computed_/_abstract/_constructor/_instance_/_has_/__pascal)"
compgen -v | sort | comm -13 $G8/b.vars - | grep -E '^T' | grep -vE '_(decl|class|method|static|property|computed|abstract|constructor|instance|has|destructor|field|properties|methods)_?|__pascal|_abstract_methods$|_class_abstract$|_has_nonpublic$|_class_methods$|_class_properties$' | tr '\n' ' '; echo
