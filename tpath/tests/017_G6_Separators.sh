#!/bin/bash
# 017_G6_Separators.sh — review 2026-09-06, phase P3: the separator findings.
#
#   G6-01  `${path##*[$SEP$ALT]}` expands to a bracket expression containing a
#          backslash, and inside [...] bash reads `\` as an escape — the class
#          matched neither `\` nor (on 5.2/5.3) `/`. getFileName/getExtension/
#          getFileNameWithoutExtension/hasExtension/getPathRoot never split a
#          Windows path.
#   G6-15  combine emitted DirectorySeparatorChar = `\` on MSYS, so its own
#          parsers could not read the result back (decision D5: the separator
#          is `/`, both are accepted on input).
#   G6-22  combine stripped only ONE trailing separator; getPathRoot answered
#          `//server` for a UNC path instead of `//server/share` (FPC
#          ExtractFileDrive skips the server AND the share).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_Separators" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
source "$TPATH_DIR/tpath.sh"

BS='\'

# eq TITLE EXPECTED ACTUAL
eq() {
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- D5: the separator constants -------------------------------------------
eq "DirectorySeparatorChar is '/' on every platform [D5]" \
   "/" "$(tpath.getDirectorySeparatorChar)"

case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        eq "AltDirectorySeparatorChar is the backslash on Windows [D5]" \
           "$BS" "$(tpath.getAltDirectorySeparatorChar)"
        ;;
    *)
        eq "AltDirectorySeparatorChar is '/' on POSIX [D5]" \
           "/" "$(tpath.getAltDirectorySeparatorChar)"
        ;;
esac

# --- G6-01: both separators are recognised on input ------------------------
eq "getFileName splits a Windows path [G6-01]" \
   "f.txt" "$(tpath.getFileName "C:${BS}Users${BS}me${BS}f.txt")"
eq "getFileName splits a MIXED path [G6-01]" \
   "c.txt" "$(tpath.getFileName "/a/b${BS}c.txt")"
eq "getFileName still splits a POSIX path [G6-01]" \
   "c.txt" "$(tpath.getFileName "/a/b/c.txt")"
eq "getFileName of a path ending in a separator is empty [G6-01]" \
   "" "$(tpath.getFileName "/a/b/")"

eq "getExtension does not look into the directory part [G6-01]" \
   "" "$(tpath.getExtension "C:${BS}dir.d${BS}file")"
eq "getExtension of a Windows path [G6-01]" \
   ".txt" "$(tpath.getExtension "C:${BS}dir${BS}f.txt")"

eq "getFileNameWithoutExtension splits a Windows path [G6-01]" \
   "f" "$(tpath.getFileNameWithoutExtension "C:${BS}dir${BS}f.txt")"

kt_test_start "hasExtension is false for a dotted DIRECTORY name [G6-01]"
if tpath.hasExtension "C:${BS}dir.d${BS}file"; then
    kt_test_fail "hasExtension said true (RESULT='$RESULT')"
else
    kt_test_pass "rc 1 / RESULT='$RESULT'"
fi

# --- G6-22: UNC root is server + share -------------------------------------
eq "getPathRoot of a POSIX UNC path is //server/share [G6-22, FPC]" \
   "//server/share" "$(tpath.getPathRoot "//server/share/file.txt")"
eq "getPathRoot of a Windows UNC path keeps the input characters [G6-22]" \
   "${BS}${BS}srv${BS}share" "$(tpath.getPathRoot "${BS}${BS}srv${BS}share${BS}f.txt")"
eq "getPathRoot of a UNC path with no share is the whole path [G6-22]" \
   "//server" "$(tpath.getPathRoot "//server")"
eq "getPathRoot of a drive path [G6-01]" \
   "C:" "$(tpath.getPathRoot "C:${BS}Users${BS}f.txt")"
eq "getPathRoot of a rooted POSIX path" "/" "$(tpath.getPathRoot "/home/user/f")"
eq "getPathRoot of a relative path is empty" "" "$(tpath.getPathRoot "folder/f")"

# --- G6-15 / G6-22: combine ------------------------------------------------
eq "combine joins with '/' [G6-15, D5]" \
   "/c/tmp/file.txt" "$(tpath.combine "/c/tmp" "file.txt")"
eq "combine strips ALL trailing separators [G6-22]" \
   "p1/p2" "$(tpath.combine "p1//" "p2")"
eq "combine strips a trailing backslash too [G6-22]" \
   "p1/p2" "$(tpath.combine "p1${BS}" "p2")"
eq "combine keeps the root when path1 is '/'" "/p2" "$(tpath.combine "/" "p2")"
eq "combine returns an absolute path2 unchanged" \
   "/absolute/path" "$(tpath.combine "path1" "/absolute/path")"
eq "combine returns a drive-rooted path2 unchanged" \
   "C:/x" "$(tpath.combine "path1" "C:/x")"

# The round trip the review used as the headline symptom.
combined="$(tpath.combine "/c/tmp" "file.txt")"
eq "tpath can parse back what tpath.combine produced [G6-01+G6-15]" \
   "file.txt" "$(tpath.getFileName "$combined")"
eq "... and its directory [G6-01+G6-15]" \
   "/c/tmp" "$(tpath.getDirectoryName "$combined")"
