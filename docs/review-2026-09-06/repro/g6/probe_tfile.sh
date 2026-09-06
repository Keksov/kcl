#!/bin/bash
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /c/projects/kkbot/kbool/kcl/tfile/tfile.sh
W="$S/w_tfile"; rm -rf "$W"; mkdir -p "$W"; cd "$W"
echo "## F1 appendAllText swallows echo options"
: > a.txt; tfile.appendAllText a.txt "-n"; tfile.appendAllText a.txt "-e"; tfile.appendAllText a.txt "-neE"; tfile.appendAllText a.txt "-n foo"
printf 'size=%s content=[%s]\n' "$(stat -c %s a.txt)" "$(cat a.txt)"
echo "## F1b appendAllText backslash handling (xpg_echo off)"; : > b.txt; tfile.appendAllText b.txt 'a\nb'; printf '[%s]\n' "$(cat b.txt)"
echo "## F2 delete/copy/move without -- (leading dash names)"
echo x > ./-f; tfile.delete "-f"; echo "delete -f rc=$? still-exists=$([[ -e ./-f ]] && echo yes || echo no)"
echo x > ./-r; tfile.delete "-r" 2>&1; echo "delete -r rc=$?"
echo src > ./-s; tfile.copy "-s" "out.txt" 2>&1; echo "copy -s rc=$? out=$([[ -e out.txt ]] && echo yes || echo no)"
echo "## F3 readAllText of '-' reads stdin"; echo "STDIN-DATA" | { r=$(tfile.readAllText "-"); echo "got=[$r]"; }
echo "## F4 round-trip trailing newlines / NUL"
printf 'line1\n\n\n' > t.txt; r=$(tfile.readAllText t.txt); printf 'bytes=%s read_len=%s\n' "$(stat -c %s t.txt)" "${#r}"
printf 'a\0b' > n.bin; r=$(tfile.readAllBytes n.bin 2>&1); printf 'nul read=[%s] len=%s\n' "$r" "${#r}"
tfile.writeAllBytes w.bin $'x\0y'; printf 'writeAllBytes NUL size=%s\n' "$(stat -c %s w.bin)"
printf 'crlf\r\nx' > c.txt; r=$(tfile.readAllText c.txt); printf 'crlf len=%s (expect 7)\n' "${#r}"
echo "## F5 integerToFileAttributes arithmetic injection"
rm -f pwned; tfile.integerToFileAttributes 'x[$(touch pwned)]' ; echo "pwned exists: $([[ -e pwned ]] && echo YES || echo no)"
echo "## F5b fileAttributesToInteger leaks global attr_parts"; unset attr_parts; tfile.fileAttributesToInteger "[ReadOnly, Hidden]" >/dev/null; declare -p attr_parts 2>&1 | head -1
echo "## F6 replace keeps source (FPC/.NET delete source)"
echo new > rs.txt; echo old > rd.txt; tfile.replace rs.txt rd.txt rb.txt; echo "rc=$? src_exists=$([[ -e rs.txt ]] && echo yes || echo no) dest=$(cat rd.txt) backup=$(cat rb.txt)"
echo "## F7 set*Time / setAttributes are no-ops"
echo x > st.txt; touch -d '2000-01-01 00:00:00' st.txt; before=$(stat -c %Y st.txt)
tfile.setLastWriteTime st.txt "2020-06-15 12:00:00"; echo "rc=$? mtime changed: $([[ $(stat -c %Y st.txt) != $before ]] && echo yes || echo NO)"
tfile.setAttributes st.txt "[faReadOnly]"; echo "setAttributes rc=$? writable: $([[ -w st.txt ]] && echo yes || echo no)"
chmod 444 st.txt; echo "getAttributes on chmod444 file: $(tfile.getAttributes st.txt)"
echo "## F8 copy with overwrite=true onto a directory"
mkdir d; echo z > z.txt; tfile.copy z.txt d true; echo "rc=$? d/z.txt exists: $([[ -e d/z.txt ]] && echo yes || echo no)"
echo "## F9 getCreationTime raw %W value"; stat -c '%W' z.txt; tfile.getCreationTime z.txt
echo "## F10 nasty names: space, glob, unicode, newline"
mkdir nasty; cd nasty
for n in 'sp ace.txt' 'gl*ob?.txt' 'br[ack]et.txt' 'юникод.txt' $'new\nline.txt'; do tfile.create "$n"; tfile.appendAllText "$n" "data"; done
for n in 'sp ace.txt' 'gl*ob?.txt' 'br[ack]et.txt' 'юникод.txt' $'new\nline.txt'; do printf '%q exists=%s read=[%s]\n' "$n" "$(tfile.exists "$n")" "$(tfile.readAllText "$n")"; done
tfile.copy 'gl*ob?.txt' 'copy.txt'; tfile.move 'copy.txt' 'br[ack]et2.txt'; ls -1 | wc -l
cd ..
echo "## F11 createSymLink on MSYS (mklink path conversion)"
echo tgt > tgt.txt; r=$(tfile.createSymLink "$W/lnk.txt" "$W/tgt.txt" 2>&1); echo "result=[$r] rc=$? is-symlink=$([[ -L lnk.txt ]] && echo yes || echo no) exists=$([[ -e lnk.txt ]] && echo yes || echo no) target=[$(tfile.getSymLinkTarget lnk.txt)]"
cmd //c "dir /a $(cygpath -w "$W") | findstr lnk" 2>/dev/null | head -2
echo "## F12 encrypt of backslash path picks wrong temp dir"
echo secret > enc.txt; tfile.encrypt "$(cygpath -w "$W/enc.txt")" pw; echo "rc=$? enc.txt changed: $([[ $(cat enc.txt 2>/dev/null) != secret ]] && echo yes || echo no)"; ls -a "$W" | grep tfile_crypt
echo "## F13 tfile.exists on file named -f"; echo "exists(-f)=$(tfile.exists "-f")"
cd "$S"; rm -rf "$W"
