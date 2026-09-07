#!/bin/bash
# 034_G6_Lifecycle.sh — review 2026-09-06, phase P3.
#
#   G6-04  `tdirectory.delete "lnk/"` ran `rm -rf -- "lnk/"`, and a trailing
#          slash makes rm follow the link: the TARGET's contents were deleted
#          and the link stayed. R13: strip trailing separators, and on a
#          symlink remove only the link.
#   G6-10  copy/move into an EXISTING destination nested the source inside it
#          (`copy src dst` produced `dst/src/a.txt`). R13: copy merges the
#          CONTENTS, move refuses with rc 1.
#   G6-16  isEmpty forked `$(ls -A)` on every call (73 ms per 200);
#          getLogicalDrives forked `$(uname -s)`.
#   G6-24  exists ignored its FollowLink argument.
#   G6-11  `--` before user paths (verified again here for the new bodies).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/symlink_helper.sh"

kt_test_init "G6_Lifecycle" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
source "$TDIRECTORY_DIR/tdirectory.sh"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- G6-04: delete on a directory symlink ----------------------------------
kt_test_start "delete on a directory symlink with a TRAILING SLASH removes only the link [G6-04, R13]"
S="$W/g604a"
mkdir -p "$S/tgt"
: > "$S/tgt/keep.txt"
if kt_make_symlink "$S/lnk" "$S/tgt"; then
    rc=0
    tdirectory.delete "$S/lnk/" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ ! -L "$S/lnk" && ! -e "$S/lnk" ]] && [[ -f "$S/tgt/keep.txt" ]]; then
        kt_test_pass "link gone, target contents intact"
    else
        kt_test_fail "rc=$rc link=$([[ -L "$S/lnk" ]] && echo present || echo gone) keep=$([[ -f "$S/tgt/keep.txt" ]] && echo intact || echo DELETED)"
    fi
else
    kt_test_fail "could not create a directory symlink"
fi

kt_test_start "delete on a directory symlink WITHOUT a slash removes only the link [G6-04]"
S="$W/g604b"
mkdir -p "$S/tgt"
: > "$S/tgt/keep.txt"
if kt_make_symlink "$S/lnk" "$S/tgt"; then
    tdirectory.delete "$S/lnk" >/dev/null 2>&1 || :
    if [[ ! -L "$S/lnk" ]] && [[ -f "$S/tgt/keep.txt" ]]; then
        kt_test_pass "link gone, target intact"
    else
        kt_test_fail "link=$([[ -L "$S/lnk" ]] && echo present || echo gone) keep=$([[ -f "$S/tgt/keep.txt" ]] && echo intact || echo DELETED)"
    fi
else
    kt_test_fail "could not create a directory symlink"
fi

kt_test_start "delete strips trailing separators on a REAL directory [R13]"
R="$W/g604c/real"
mkdir -p "$R/inner"
tdirectory.delete "$R//" >/dev/null 2>&1 || :
if [[ ! -e "$R" ]]; then
    kt_test_pass "removed"
else
    kt_test_fail "still there"
fi

kt_test_start "non-recursive delete refuses a non-empty directory [FPC]"
NE="$W/g604d"
mkdir -p "$NE"
: > "$NE/f.txt"
rc=0
tdirectory.delete "$NE" false >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -d "$NE" && -f "$NE/f.txt" ]]; then
    kt_test_pass "rc 1, untouched"
else
    kt_test_fail "rc=$rc dir=$([[ -d "$NE" ]] && echo there || echo gone)"
fi

kt_test_start "non-recursive delete removes an EMPTY directory [FPC]"
EM="$W/g604e"
mkdir -p "$EM"
rc=0
tdirectory.delete "$EM" false >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ ! -e "$EM" ]]; then
    kt_test_pass "removed"
else
    kt_test_fail "rc=$rc exists=$([[ -e "$EM" ]] && echo yes || echo no)"
fi

kt_test_start "non-recursive delete sees a dot-entry as content [G6-09]"
DE="$W/g604f"
mkdir -p "$DE"
: > "$DE/.hidden"
rc=0
tdirectory.delete "$DE" false >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -d "$DE" ]]; then
    kt_test_pass "rc 1, untouched"
else
    kt_test_fail "rc=$rc dir=$([[ -d "$DE" ]] && echo there || echo gone)"
fi

kt_test_start "delete does not read a leading-dash path as an option [G6-11]"
cd "$W" || exit 1
mkdir -p -- "-rf"
: > "-rf/inner.txt"
tdirectory.delete "-rf" >/dev/null 2>&1 || :
left=$([[ -d "$W/-rf" ]] && echo yes || echo no)
rm -rf -- "$W/-rf"
cd "$SCRIPT_DIR" || exit 1
if [[ "$left" == "no" ]]; then
    kt_test_pass "'./-rf' was removed"
else
    kt_test_fail "'./-rf' survived"
fi

kt_test_start "setCurrentDirectory '-' means the DIRECTORY named '-' [G6-11]"
here="$PWD"
mkdir -p "$W/dashhome"
mkdir -p -- "$W/dashhome/-"
cd "$W/dashhome" || exit 1
cd "$W" && cd "$W/dashhome" || exit 1      # give OLDPWD a different value
rc=0
tdirectory.setCurrentDirectory "-" >/dev/null 2>&1 || rc=$?
landed="${PWD##*/}"
cd "$here" || exit 1
rm -rf -- "$W/dashhome"
if (( rc == 0 )) && [[ "$landed" == "-" ]]; then
    kt_test_pass "landed in './-', not \$OLDPWD"
else
    kt_test_fail "rc=$rc landed in '$landed' (bash's cd reads a lone '-' as \$OLDPWD even after --)"
fi

# --- G6-10: copy into an existing destination ------------------------------
kt_test_start "copy into an EXISTING destination merges the contents [G6-10, R13]"
C="$W/g610"
mkdir -p "$C/src/sub" "$C/dst"
: > "$C/src/a.txt"
: > "$C/src/sub/b.txt"
: > "$C/dst/existing.txt"
rc=0
tdirectory.copy "$C/src" "$C/dst" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ -f "$C/dst/a.txt" && -f "$C/dst/sub/b.txt" && -f "$C/dst/existing.txt" ]] \
   && [[ ! -d "$C/dst/src" ]]; then
    kt_test_pass "contents merged, no nested src/"
else
    kt_test_fail "rc=$rc nested=$([[ -d "$C/dst/src" ]] && echo yes || echo no) a=$([[ -f "$C/dst/a.txt" ]] && echo yes || echo no)"
fi

kt_test_start "copy into a NEW destination still creates it [G6-10]"
rc=0
tdirectory.copy "$C/src" "$C/fresh" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ -f "$C/fresh/a.txt" && -f "$C/fresh/sub/b.txt" ]] && [[ ! -d "$C/fresh/src" ]]; then
    kt_test_pass "created with the contents"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "copy also carries dot-entries [G6-09]"
: > "$C/src/.dotfile"
tdirectory.copy "$C/src" "$C/fresh2" >/dev/null 2>&1 || :
if [[ -f "$C/fresh2/.dotfile" ]]; then
    kt_test_pass "dot-file copied"
else
    kt_test_fail "dot-file missing"
fi

kt_test_start "copy onto an existing FILE is rc 1 [G6-10]"
: > "$C/plainfile"
rc=0
tdirectory.copy "$C/src" "$C/plainfile" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -f "$C/plainfile" && ! -d "$C/plainfile" ]]; then
    kt_test_pass "rc 1, the file is untouched"
else
    kt_test_fail "rc=$rc"
fi

# --- G6-10: move into an existing destination ------------------------------
kt_test_start "move into an EXISTING destination is rc 1 [G6-10, R13]"
M="$W/g610m"
mkdir -p "$M/src" "$M/dst"
: > "$M/src/a.txt"
rc=0
tdirectory.move "$M/src" "$M/dst" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -d "$M/src" && -f "$M/src/a.txt" ]] && [[ ! -d "$M/dst/src" ]]; then
    kt_test_pass "rc 1, source untouched, nothing nested"
else
    kt_test_fail "rc=$rc src=$([[ -d "$M/src" ]] && echo there || echo gone) nested=$([[ -d "$M/dst/src" ]] && echo yes || echo no)"
fi

kt_test_start "move into a NEW destination still works [G6-10]"
rc=0
tdirectory.move "$M/src" "$M/moved" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ ! -d "$M/src" && -f "$M/moved/a.txt" ]]; then
    kt_test_pass "moved"
else
    kt_test_fail "rc=$rc"
fi

# --- G6-16: no forks in isEmpty / getLogicalDrives -------------------------
kt_test_start "isEmpty does not shell out to ls [G6-16]"
canary="$W/ls_called"
rm -f -- "$canary"
ls() { : > "$canary"; command ls "$@"; }
tdirectory.isEmpty "$W" >/dev/null || :
unset -f ls
if [[ -e "$canary" ]]; then
    kt_test_fail "isEmpty called ls"
else
    kt_test_pass "no ls"
fi

kt_test_start "getLogicalDrives does not run uname [G6-16]"
canary="$W/uname_called"
rm -f -- "$canary"
uname() { : > "$canary"; command uname "$@"; }
tdirectory.getLogicalDrives >/dev/null || :
unset -f uname
if [[ -e "$canary" ]]; then
    kt_test_fail "getLogicalDrives called uname"
else
    kt_test_pass "no uname"
fi

for m in isEmpty exists getLogicalDrives delete getParent getDirectoryRoot isRelativePath; do
    kt_test_start "tdirectory.$m body is free of command substitution [G6-16]"
    body="$(declare -f "tdirectory.__static_$m")"
    if [[ "$body" == *'$('* ]] || [[ "$body" == *'`'* ]]; then
        kt_test_fail "tdirectory.$m still forks"
    else
        kt_test_pass "no \$( ) in tdirectory.$m"
    fi
done

# --- G6-24: exists and its FollowLink argument -----------------------------
kt_test_start "exists follows a directory link by default [G6-24]"
X="$W/g624"
mkdir -p "$X/real"
kt_make_symlink "$X/link" "$X/real" || :
if tdirectory.exists "$X/link"; then
    kt_test_pass "true"
else
    kt_test_fail "rc $? RESULT='$RESULT'"
fi

kt_test_start "exists with FollowLink=false does not accept a link [G6-24]"
if tdirectory.exists "$X/link" false; then
    kt_test_fail "the link was reported as a directory (RESULT='$RESULT')"
else
    kt_test_pass "false"
fi

kt_test_start "exists with FollowLink=false still accepts a real directory [G6-24]"
if tdirectory.exists "$X/real" false; then
    kt_test_pass "true"
else
    kt_test_fail "rc $? RESULT='$RESULT'"
fi

# --- isEmpty counts dot-entries (G6-09) ------------------------------------
kt_test_start "isEmpty is false for a directory holding only a dot-entry [G6-09]"
I="$W/g609i"
mkdir -p "$I"
: > "$I/.only"
if tdirectory.isEmpty "$I"; then
    kt_test_fail "reported empty"
else
    kt_test_pass "not empty"
fi

kt_test_start "isEmpty is true for a really empty directory [G6-09]"
mkdir -p "$W/g609e"
if tdirectory.isEmpty "$W/g609e"; then
    kt_test_pass "empty"
else
    kt_test_fail "rc $? RESULT='$RESULT'"
fi
