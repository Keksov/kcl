#!/bin/bash
# 040_G6_SymLink.sh — review 2026-09-06, phase P3.
#
#   G6-05  createSymLink handed POSIX paths to `cmd /c mklink`, so it never
#          worked on MSYS: it answered `false`, rc 1, and created nothing.
#          Nobody noticed because tests 005/010/012/019 probed symlink support
#          with `ln -s <nonexistent>`, which fails in MSYS copy mode — all 12
#          symlink assertions reported "PASS (skipped)".
#   G6-16  the same body ran `$(uname -s)` on every call.
#
# This file uses a probe that CANNOT silently skip: if native symlinks are
# unavailable the tests fail, they do not pass.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/symlink_helper.sh"

TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

kt_test_init "G6_SymLink" "$SCRIPT_DIR" "$@"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_start "the test box can create a native symlink [G6-05 probe]"
if kt_symlinks_supported "$W"; then
    kt_test_pass "MSYS=winsymlinks:native ln -s produces a real link"
else
    kt_test_fail "native symlinks unavailable — enable Developer Mode or run elevated"
fi

# --- G6-05: createSymLink on a FILE ----------------------------------------
kt_test_start "createSymLink creates a real link to a file [G6-05]"
printf 'target content\n' > "$W/tgt.txt"
rm -f -- "$W/lnk.txt"
rc=0
tfile.createSymLink "$W/lnk.txt" "$W/tgt.txt" >/dev/null || rc=$?
if (( rc == 0 )) && [[ -L "$W/lnk.txt" ]] && [[ "$(cat "$W/lnk.txt")" == "target content" ]]; then
    kt_test_pass "rc 0, -L, contents readable"
else
    kt_test_fail "rc=$rc -L=$([[ -L "$W/lnk.txt" ]] && echo yes || echo no) exists=$([[ -e "$W/lnk.txt" ]] && echo yes || echo no)"
fi

kt_test_start "createSymLink answers 'true' under \$( ) [G6-05, D3]"
rm -f -- "$W/lnk2.txt"
answer="$(tfile.createSymLink "$W/lnk2.txt" "$W/tgt.txt")"
if [[ "$answer" == "true" && -L "$W/lnk2.txt" ]]; then
    kt_test_pass "true"
else
    kt_test_fail "answer='$answer' -L=$([[ -L "$W/lnk2.txt" ]] && echo yes || echo no)"
fi

# --- G6-05: createSymLink on a DIRECTORY -----------------------------------
kt_test_start "createSymLink creates a real link to a directory [G6-05]"
mkdir -p "$W/tgtdir"
: > "$W/tgtdir/inside.txt"
rm -rf -- "$W/dlnk"
rc=0
tfile.createSymLink "$W/dlnk" "$W/tgtdir" >/dev/null || rc=$?
if (( rc == 0 )) && [[ -L "$W/dlnk" && -d "$W/dlnk" && -f "$W/dlnk/inside.txt" ]]; then
    kt_test_pass "rc 0, directory link usable"
else
    kt_test_fail "rc=$rc -L=$([[ -L "$W/dlnk" ]] && echo yes || echo no) -d=$([[ -d "$W/dlnk" ]] && echo yes || echo no)"
fi

# --- the failure paths -----------------------------------------------------
kt_test_start "createSymLink refuses a missing target [G6-05]"
rc=0
answer="$(tfile.createSymLink "$W/broken.txt" "$W/nosuch.txt")" || rc=$?
if (( rc != 0 )) && [[ "$answer" == "false" && ! -e "$W/broken.txt" && ! -L "$W/broken.txt" ]]; then
    kt_test_pass "rc $rc, false, nothing created"
else
    kt_test_fail "rc=$rc answer='$answer' created=$([[ -L "$W/broken.txt" ]] && echo yes || echo no)"
fi

kt_test_start "createSymLink never deletes an existing path at the link name [G6-05]"
mkdir -p "$W/occupied"
: > "$W/occupied/keep.txt"
rc=0
answer="$(tfile.createSymLink "$W/occupied" "$W/tgt.txt")" || rc=$?
if (( rc != 0 )) && [[ "$answer" == "false" ]] \
   && [[ -d "$W/occupied" && -f "$W/occupied/keep.txt" ]]; then
    kt_test_pass "rc $rc, false, the directory is untouched"
else
    kt_test_fail "rc=$rc answer='$answer' dir=$([[ -d "$W/occupied" ]] && echo there || echo DELETED) keep=$([[ -f "$W/occupied/keep.txt" ]] && echo intact || echo DELETED)"
fi

kt_test_start "createSymLink refuses a link path in a missing directory [G6-05]"
rc=0
answer="$(tfile.createSymLink "$W/nosuchdir/lnk.txt" "$W/tgt.txt")" || rc=$?
if (( rc != 0 )) && [[ "$answer" == "false" ]]; then
    kt_test_pass "rc $rc, false"
else
    kt_test_fail "rc=$rc answer='$answer'"
fi

# --- G6-16: no uname fork --------------------------------------------------
kt_test_start "createSymLink does not run uname [G6-16]"
canary="$W/uname_called"
rm -f -- "$canary"
uname() { : > "$canary"; command uname "$@"; }
rm -f -- "$W/lnk3.txt"
tfile.createSymLink "$W/lnk3.txt" "$W/tgt.txt" >/dev/null 2>&1 || :
unset -f uname
if [[ -e "$canary" ]]; then
    kt_test_fail "uname was called"
else
    kt_test_pass "no uname"
fi

# --- getSymLinkTarget ------------------------------------------------------
kt_test_start "getSymLinkTarget returns the stored target [G6-05]"
rm -f -- "$W/lnk4.txt"
kt_make_symlink "$W/lnk4.txt" "$W/tgt.txt" || :
target="$(tfile.getSymLinkTarget "$W/lnk4.txt")"
if [[ "$target" == "$W/tgt.txt" ]]; then
    kt_test_pass "$target"
else
    kt_test_fail "got '$target', expected '$W/tgt.txt'"
fi

kt_test_start "getSymLinkTarget of a regular file is rc 1 and empty [1.2]"
rc=0
target="$(tfile.getSymLinkTarget "$W/tgt.txt" 2>&1)" || rc=$?
if (( rc == 1 )) && [[ -z "$target" ]]; then
    kt_test_pass "rc 1, empty"
else
    kt_test_fail "rc=$rc target='$target'"
fi

kt_test_start "getSymLinkTarget of a BROKEN link still answers [G6-05]"
rm -f -- "$W/dangling"
MSYS=winsymlinks:native CYGWIN=winsymlinks:native ln -s -- "$W/nosuch.txt" "$W/dangling" 2>/dev/null || :
if [[ -L "$W/dangling" ]]; then
    target="$(tfile.getSymLinkTarget "$W/dangling")"
    if [[ "$target" == "$W/nosuch.txt" ]]; then
        kt_test_pass "$target"
    else
        kt_test_fail "got '$target'"
    fi
else
    kt_test_fail "could not create a dangling symlink"
fi

# --- exists() and the FollowLink flag on real links -------------------------
kt_test_start "exists follows a link by default and sees the target [G6-05]"
if tfile.exists "$W/lnk4.txt"; then
    kt_test_pass "true"
else
    kt_test_fail "rc $? RESULT='$RESULT'"
fi

kt_test_start "exists is false for a BROKEN link when following [G6-05]"
if tfile.exists "$W/dangling" true; then
    kt_test_fail "reported the broken link as existing"
else
    kt_test_pass "false"
fi

kt_test_start "exists is true for a BROKEN link when NOT following [G6-05]"
if tfile.exists "$W/dangling" false; then
    kt_test_pass "true"
else
    kt_test_fail "rc $? RESULT='$RESULT'"
fi

# --- delete removes the LINK, never the target (R13) ------------------------
kt_test_start "delete on a symlink removes only the link [R13]"
rm -f -- "$W/lnk5.txt"
kt_make_symlink "$W/lnk5.txt" "$W/tgt.txt" || :
tfile.delete "$W/lnk5.txt" || :
if [[ ! -L "$W/lnk5.txt" && -f "$W/tgt.txt" && "$(cat "$W/tgt.txt")" == "target content" ]]; then
    kt_test_pass "link gone, target intact"
else
    kt_test_fail "link=$([[ -L "$W/lnk5.txt" ]] && echo yes || echo no) target=$([[ -f "$W/tgt.txt" ]] && echo yes || echo no)"
fi
