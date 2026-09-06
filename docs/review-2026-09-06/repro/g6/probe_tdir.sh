#!/bin/bash
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /c/projects/kkbot/kbool/kcl/tdirectory/tdirectory.sh
W="$S/w_tdir"; rm -rf "$W"; mkdir -p "$W"; cd "$W"
echo "## D1 delete safety"
for p in "" "/" "." ".." "sub/.." "-rf" "*" "~"; do mkdir -p sub; r=$(tdirectory.delete "$p" 2>&1); echo "delete [$p] rc=$? msg=[${r:0:70}]"; done
mkdir -p ./-rf; tdirectory.delete "-rf"; echo "delete dir named -rf: rc=$? still exists: $([[ -d ./-rf ]] && echo YES || echo no)"
mkdir -p "sub2/x"; tdirectory.delete "sub2/.." 2>&1; echo "delete sub2/.. rc=$? cwd still exists: $([[ -d "$W" ]] && echo yes || echo NO)"
echo "## D2 hidden entries never listed"
mkdir -p h; touch h/.hidden h/visible; mkdir h/.hdir h/vdir
echo "getFiles: $(tdirectory.getFiles h | tr '\n' ' ')"; echo "getDirectories: $(tdirectory.getDirectories h | tr '\n' ' ')"; echo "getFileSystemEntries: $(tdirectory.getFileSystemEntries h | tr '\n' ' ')"
echo "isEmpty of dir with only dotfile: $(mkdir -p oh; touch oh/.x; tdirectory.isEmpty oh)"
echo "## D3 trailing slash / nasty names in listing"
mkdir -p n; touch n/'sp ace' n/'gl*ob' n/'br[a]' n/'-dash' n/'юни' n/$'nl\nx'; mkdir n/'d*ir'
echo "getFiles n/ ->"; tdirectory.getFiles "n/" | cat -A | head -8
echo "getFiles n 'gl*ob' ->"; tdirectory.getFiles n 'gl*ob'
echo "getFiles n '*[a]*' ->"; tdirectory.getFiles n '*[a]*'
echo "getDirectories n '*' ->"; tdirectory.getDirectories n
echo "count top-level via getFiles: $(tdirectory.getFiles n | wc -l) (6 files, one has newline)"
echo "## D4 copy/move into existing dest nests"
mkdir -p src dst; echo a > src/a.txt; tdirectory.copy src dst; echo "copy rc=$? dst/a.txt=$([[ -e dst/a.txt ]] && echo yes || echo NO) dst/src/a.txt=$([[ -e dst/src/a.txt ]] && echo YES || echo no)"
mkdir -p msrc mdst; echo a > msrc/a.txt; tdirectory.move msrc mdst; echo "move rc=$? mdst/a.txt=$([[ -e mdst/a.txt ]] && echo yes || echo NO) mdst/msrc/a.txt=$([[ -e mdst/msrc/a.txt ]] && echo YES || echo no) msrc gone=$([[ ! -e msrc ]] && echo yes || echo no)"
echo "## D5 Utc setters use local touch -t"
mkdir -p tz; echo "TZ offset now: $(date +%z)"
tdirectory.setLastWriteTimeUtc tz "2024-01-01 12:00:00"; echo "setUtc rc=$? getLastWriteTimeUtc=[$(tdirectory.getLastWriteTimeUtc tz)] getLastWriteTime=[$(tdirectory.getLastWriteTime tz)] (expected Utc 2024-01-01 12:00:00)"
tdirectory.setLastWriteTime tz "2024-01-01 12:00:00"; echo "setLocal rc=$? getLastWriteTime=[$(tdirectory.getLastWriteTime tz)]"
tdirectory.setLastWriteTimeUtc tz "1704110400"; echo "setUtc epoch rc=$? getLastWriteTimeUtc=[$(tdirectory.getLastWriteTimeUtc tz)] (expected 2024-01-01 12:00:00)"
tdirectory.setCreationTime tz "2020-01-01 00:00:00"; echo "setCreationTime rc=$? getCreationTime=[$(tdirectory.getCreationTime tz)] getLastWriteTime=[$(tdirectory.getLastWriteTime tz)]"
echo "## D6 exists FollowLink ignored / echo -n"
echo "exists(nonexist,false)=[$(tdirectory.exists nope false)]"; tdirectory.exists h; echo "<-no newline"
echo "## D7 setCurrentDirectory in caller shell + '-'"
tdirectory.setCurrentDirectory h; echo "pwd after set: ${PWD##*/}"; cd "$W"; mkdir -p ./-; tdirectory.setCurrentDirectory "-" ; echo "after cd '-': ${PWD##*/} (expected '-')"; cd "$W"
echo "## D8 getLogicalDrives leaks global 'letter'"; unset letter; tdirectory.getLogicalDrives >/dev/null; declare -p letter 2>&1 | head -1
echo "## D9 symlink loop in recursion (MSYS winsymlinks)"
mkdir -p loop/a; ( cd loop/a && MSYS=winsymlinks:nativestrict ln -s .. back 2>/dev/null ) ; [[ -L loop/a/back ]] && echo "symlink made" || echo "no real symlink (skip)"
if [[ -L loop/a/back ]]; then timeout 10 bash -c 'source /c/projects/kkbot/kbool/kcl/tdirectory/tdirectory.sh; tdirectory.getDirectories "'"$W"'/loop" "*" AllDirectories | wc -l' ; echo "rc=$? (124 = hang/timeout)"; fi
echo "## D10 delete of symlink-to-dir with trailing slash"
mkdir -p tgt; touch tgt/keep; ( MSYS=winsymlinks:nativestrict ln -s tgt lnk 2>/dev/null ); if [[ -L lnk ]]; then tdirectory.delete "lnk/" 2>&1; echo "rc=$? tgt/keep exists: $([[ -e tgt/keep ]] && echo yes || echo NO-DELETED-TARGET) lnk exists: $([[ -L lnk ]] && echo yes || echo no)"; else echo skip; fi
echo "## D11 failglob interaction"; ( shopt -s failglob; mkdir -p emp; tdirectory.getFiles emp; echo "failglob rc=$?" ) 2>&1
echo "## D12 re-source guard"; source /c/projects/kkbot/kbool/kcl/tdirectory/tdirectory.sh 2>&1 | head -2; echo "re-source rc=$?"; tdirectory.exists h; echo
echo "## D13 collation dependence"; mkdir -p col; touch col/a-b col/a.b col/a_b; echo "default: $(tdirectory.getFiles col | xargs -n1 basename | tr '\n' ' ')"; echo "TDIRECTORY_COLLATE=C: $(TDIRECTORY_COLLATE=C tdirectory.getFiles col | xargs -n1 basename | tr '\n' ' ')"
cd "$S"; rm -rf "$W"
