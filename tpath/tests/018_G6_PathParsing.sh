#!/bin/bash
# 018_G6_PathParsing.sh — review 2026-09-06, phase P3.
#
#   G6-02  changeExtension cut at the last dot of the WHOLE path, so a dotted
#          directory name was rewritten:
#            /home/u/.config/app/file .bak -> /home/u/.bak
#            dir.d/file .txt               -> dir.txt
#          FPC ChangeFileExt scans back and STOPS at a directory or drive
#          separator, so only the file name can lose its extension.
#   G6-12  getDirectoryName: the root was dropped (/file.txt -> ''), only ONE
#          trailing separator was stripped (/home/user/ -> /home instead of
#          ExtractFileDir's /home/user) and a mixed-separator path was cut at
#          the wrong place (C:/Users/me\f.txt -> C:/Users).
#   G6-13  getFullPath ran plain `realpath`, which fails as soon as an
#          intermediate component is missing and then answered the RAW
#          relative input.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_PathParsing" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
source "$TPATH_DIR/tpath.sh"

BS='\'

eq() {
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- G6-02: changeExtension works on the FILE NAME -------------------------
eq "changeExtension keeps a dotted directory prefix [G6-02, FPC]" \
   "/home/u/.config/app/file.bak" "$(tpath.changeExtension "/home/u/.config/app/file" ".bak")"
eq "changeExtension keeps './' [G6-02, FPC]" \
   "./file.txt" "$(tpath.changeExtension "./file" ".txt")"
eq "changeExtension keeps '../' [G6-02, FPC]" \
   "../file.txt" "$(tpath.changeExtension "../file" ".txt")"
eq "changeExtension keeps a dotted directory [G6-02, FPC]" \
   "dir.d/file.txt" "$(tpath.changeExtension "dir.d/file" ".txt")"
eq "changeExtension keeps a dotted Windows directory [G6-02, FPC]" \
   "C:${BS}dir.d${BS}file.txt" "$(tpath.changeExtension "C:${BS}dir.d${BS}file" ".txt")"
eq "changeExtension replaces the last extension of the NAME [G6-02]" \
   "dir.d/file.tar.zip" "$(tpath.changeExtension "dir.d/file.tar.gz" ".zip")"
eq "changeExtension with an empty extension drops only the name's extension [G6-02]" \
   "dir.d/file" "$(tpath.changeExtension "dir.d/file.txt" "")"

# --- G6-12: getDirectoryName parity ---------------------------------------
eq "getDirectoryName keeps the root [G6-12, .NET/FPC]" \
   "/" "$(tpath.getDirectoryName "/file.txt")"
eq "getDirectoryName strips the trailing separator, not a component [G6-12]" \
   "/home/user" "$(tpath.getDirectoryName "/home/user/")"
eq "getDirectoryName strips ALL trailing separators [G6-12]" \
   "/home/user" "$(tpath.getDirectoryName "/home/user//")"
eq "getDirectoryName cuts at the LAST separator of either kind [G6-12]" \
   "C:/Users/me" "$(tpath.getDirectoryName "C:/Users/me${BS}f.txt")"
eq "getDirectoryName keeps a drive root [G6-12, .NET]" \
   "C:${BS}" "$(tpath.getDirectoryName "C:${BS}file.txt")"
eq "getDirectoryName of a drive-relative path is the drive [G6-12]" \
   "C:" "$(tpath.getDirectoryName "C:file.txt")"
eq "getDirectoryName of the root itself is empty [G6-12]" \
   "" "$(tpath.getDirectoryName "/")"
eq "getDirectoryName of a bare name is empty [G6-12]" \
   "" "$(tpath.getDirectoryName "file.txt")"
eq "getDirectoryName of a relative path" \
   "folder" "$(tpath.getDirectoryName "folder/file.txt")"
eq "getDirectoryName of a deep path" \
   "/var/log/application/debug" "$(tpath.getDirectoryName "/var/log/application/debug/app.log")"
eq "getDirectoryName does not cut into a UNC root [G6-12]" \
   "//server/share" "$(tpath.getDirectoryName "//server/share/file.txt")"

# --- G6-13: getFullPath ----------------------------------------------------
kt_test_start "getFullPath resolves a path whose components do not exist [G6-13]"
got="$(tpath.getFullPath "nosuch_dir_g613/rel/x")"
want="$PWD/nosuch_dir_g613/rel/x"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "expected '$want', got '$got'"
fi

kt_test_start "getFullPath normalises .. in a non-existent path [G6-13]"
got="$(tpath.getFullPath "/nosuch_g613/a/../b")"
if [[ "$got" == "/nosuch_g613/b" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "expected '/nosuch_g613/b', got '$got'"
fi

eq "getFullPath leaves an existing absolute path alone [G6-13]" \
   "/tmp" "$(tpath.getFullPath "/tmp")"
eq "getFullPath of an empty path is empty [G6-13]" "" "$(tpath.getFullPath "")"

kt_test_start "getFullPath of '.' is the working directory [G6-13]"
got="$(tpath.getFullPath ".")"
if [[ "$got" == "$PWD" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "expected '$PWD', got '$got'"
fi
