#!/bin/bash
G8=$(dirname "$0"); KB=/c/projects/kkbot/kbool
snap() { (cd $KB && git status --porcelain --ignored=no) > $G8/gs_kbool_$1.txt; (cd $KB/kcl && git status --porcelain) > $G8/gs_kcl_$1.txt; (cd $KB/kklass && git status --porcelain) > $G8/gs_kklass_$1.txt; find $KB -name '.ckk' -type d | sort > $G8/ckk_$1.txt; ls /tmp | sort > $G8/tmp_$1.txt; }
snap before
echo "=== 5.2 sweep start $(date +%T)"; t0=$SECONDS
cd $KB && bash tests/tests.sh --verbosity info > $G8/sweep52.log 2>&1; echo "rc=$? took=$((SECONDS-t0))s"
snap after52
echo "=== 5.3 sweep start $(date +%T)"; t0=$SECONDS
cd $KB && PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tests/tests.sh --verbosity info > $G8/sweep53.log 2>&1; echo "rc=$? took=$((SECONDS-t0))s"
snap after53
echo DONE
