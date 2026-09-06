#!/bin/bash
source /c/projects/kkbot/kbool/kcl/tpath/tpath.sh
p() { printf '%-46s -> [%s]\n' "$1" "$2"; }
u=$'\\srv\share\f'; printf 'input bytes: %s\n' "$(printf %s "$u" | od -c | head -1)"
p "getPathRoot $u" "$(tpath.getPathRoot "$u")"
p "isUNCPath $u" "$(tpath.isUNCPath "$u")"
p "getDirectoryName $u" "$(tpath.getDirectoryName "$u")"
p "getFileName $u" "$(tpath.getFileName "$u")"
x=$'\\?\C:\x'; p "isExtendedPrefixed $x" "$(tpath.isExtendedPrefixed "$x")"
w=$'C:\Users\me\f.txt'
p "getFileName $w" "$(tpath.getFileName "$w")"
p "getExtension $w" "$(tpath.getExtension "$w")"
p "getFileNameWithoutExtension $w" "$(tpath.getFileNameWithoutExtension "$w")"
p "hasExtension C:\dir.d\file" "$(tpath.hasExtension $'C:\dir.d\file')"
p "getExtension C:\dir.d\file" "$(tpath.getExtension $'C:\dir.d\file')"
echo "## round trip combine -> getFileName / getExtension"
c=$(tpath.combine /c/tmp file.txt); p "combine /c/tmp file.txt" "$c"
p "getFileName(combine)" "$(tpath.getFileName "$c")"
p "getExtension(combine)" "$(tpath.getExtension "$c")"
p "getDirectoryName(combine)" "$(tpath.getDirectoryName "$c")"
c2=$(tpath.combine "$(tpath.combine /c/tmp sub)" file.txt); p "nested combine" "$c2"; p "getDirectoryName(nested)" "$(tpath.getDirectoryName "$c2")"
echo "## changeExtension on dotted directory"
p "changeExtension /home/u/.config/app/file .bak" "$(tpath.changeExtension /home/u/.config/app/file .bak)"
p "changeExtension /home/u/.config/app/file ''" "$(tpath.changeExtension /home/u/.config/app/file '')"
p "changeExtension ./file .txt" "$(tpath.changeExtension ./file .txt)"
p "changeExtension ../file .txt" "$(tpath.changeExtension ../file .txt)"
echo "## getFullPath -- and realpath -m"
cd "$(dirname "${BASH_SOURCE[0]}")"; p "getFullPath -e" "$(tpath.getFullPath -e)"; p "realpath -m ./nope/../x" "$(realpath -m ./nope/../x)"
echo "## getAttributes follow flag semantics (code)"; grep -n 'stat_flags="-L"' -B2 /c/projects/kkbot/kbool/kcl/tpath/tpath.sh
