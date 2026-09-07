#!/bin/bash
# 019_G6_Platform.sh — review 2026-09-06, phase P3.
#
#   G6-14  getAttributes added `stat -L` when FollowLink was FALSE — the flag
#          was inverted, so both answers described the target.
#   G6-16  avoidable forks in cheap members: `$(uname -s)` on every
#          driveExists (45 ms / 200 calls), a nested `$(tpath.isPathRooted)`
#          inside isRelativePath (21 ms / 200), `$(tpath.getFileName)` inside
#          getFileNameWithoutExtension and hasExtension, `$(basename)` inside
#          getAttributes.
#   G6-20  driveExists checked SYNTAX only (every `X:` was true); `~` was
#          rejected in a file name; Windows-invalid characters were accepted.
#   G6-21  matchesPattern cleared the CALLER's nocasematch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G6_Platform" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
source "$TPATH_DIR/tpath.sh"

TMP="$(kt_fixture_tmpdir)"
BS='\'

eq() {
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# A native Windows symlink; plain `ln -s` is in copy mode on MSYS and silently
# produces a COPY (that is why the review found 12 tests "passing as skipped").
mklink_probe() {   # LINK TARGET [--dir]
    rm -rf -- "$1" 2>/dev/null
    MSYS=winsymlinks:native CYGWIN=winsymlinks:native ln -s -- "$2" "$1" 2>/dev/null
    [[ -L "$1" ]]
}

# --- G6-14: FollowLink ------------------------------------------------------
kt_test_start "getAttributes FollowLink=false describes the LINK, true the TARGET [G6-14]"
tgt="$TMP/g614_target.txt"
lnk="$TMP/g614_link.txt"
: > "$tgt"; chmod 444 "$tgt"
if mklink_probe "$lnk" "$tgt"; then
    follow_true="$(tpath.getAttributes "$lnk" "true")"
    follow_false="$(tpath.getAttributes "$lnk" "false")"
    on_target="$(tpath.getAttributes "$tgt" "true")"
    chmod u+w "$tgt"
    if [[ "$follow_true" == "$on_target" && "$follow_true" != "$follow_false" \
       && "$follow_true" == *faReadOnly* && "$follow_false" != *faReadOnly* ]]; then
        kt_test_pass "true='$follow_true' false='$follow_false'"
    else
        kt_test_fail "true='$follow_true' false='$follow_false' target='$on_target'"
    fi
else
    chmod u+w "$tgt" 2>/dev/null
    kt_test_fail "could not create a native symlink for the FollowLink test"
fi
rm -f -- "$lnk" "$tgt"

kt_test_start "getAttributes of a read-only file reports faReadOnly [G6-14]"
ro="$TMP/g614_ro.txt"; : > "$ro"; chmod 444 "$ro"
attrs="$(tpath.getAttributes "$ro")"
chmod u+w "$ro"
if [[ "$attrs" == *faReadOnly* && "$attrs" == faNormal* ]]; then
    kt_test_pass "$attrs"
else
    kt_test_fail "got '$attrs'"
fi
rm -f -- "$ro"

# --- G6-16: no forks in the cheap members ----------------------------------
# A canary that survives a subshell: the shadow writes a FILE, so it records
# the call even when the member ran it inside $( ).
canary="$TMP/g616_canary"
uname()    { : > "$canary.uname"; command uname "$@"; }
basename() { : > "$canary.basename"; command basename "$@"; }
ls()       { : > "$canary.ls"; command ls "$@"; }

kt_test_start "driveExists does not run uname [G6-16]"
rm -f -- "$canary.uname"
tpath.driveExists "C:" || :
if [[ -e "$canary.uname" ]]; then
    kt_test_fail "uname was called"
else
    kt_test_pass "no uname"
fi

kt_test_start "getAttributes does not run basename [G6-16]"
rm -f -- "$canary.basename"
probe="$TMP/g616_probe.txt"; : > "$probe"
tpath.getAttributes "$probe" >/dev/null || :
if [[ -e "$canary.basename" ]]; then
    kt_test_fail "basename was called"
else
    kt_test_pass "no basename"
fi
rm -f -- "$probe"

unset -f uname basename ls

# A fork gives the child a different BASHPID and throws its variable writes
# away. A DIRECT call must leave BASHPID alone AND its RESULT must reach the
# caller; `$( )` must show the opposite on both counts.
kt_test_start "a direct call runs in THIS shell — BASHPID unchanged, RESULT visible [G6-16, 1.8]"
before="$BASHPID"
RESULT="__unset__"
tpath.combine "/a" "b"
after="$BASHPID"
if [[ "$after" == "$before" && "$RESULT" == "/a/b" ]]; then
    kt_test_pass "BASHPID $before throughout, RESULT=$RESULT"
else
    kt_test_fail "before=$before after=$after RESULT='$RESULT'"
fi

kt_test_start "\$( ) forks: a different BASHPID and the mutation is lost [G6-16, 1.8]"
RESULT="__unset__"
sub_pid="$(tpath.combine "/x" "y" >/dev/null; printf '%s' "$BASHPID")"
if [[ -n "$sub_pid" && "$sub_pid" != "$BASHPID" && "$RESULT" == "__unset__" ]]; then
    kt_test_pass "\$( ) ran in $sub_pid, parent is $BASHPID, RESULT untouched"
else
    kt_test_fail "sub=$sub_pid parent=$BASHPID RESULT='$RESULT'"
fi

# The structural half: these member bodies must contain no command
# substitution at all (a nested $(tpath.x) is invisible to a shadowed builtin).
for m in getFileName getDirectoryName getExtension getFileNameWithoutExtension \
         hasExtension combine isPathRooted isRelativePath isUNCPath \
         isDriveRooted driveExists matchesPattern changeExtension; do
    kt_test_start "tpath.$m body is free of command substitution [G6-16]"
    body="$(declare -f "tpath.__static_$m")"
    if [[ "$body" == *'$('* ]] || [[ "$body" == *'`'* ]]; then
        kt_test_fail "tpath.$m still forks: $(printf '%s' "$body" | grep -n '\$(' | head -2 | tr '\n' ' ')"
    else
        kt_test_pass "no \$( ) in tpath.$m"
    fi
done

# --- G6-20: driveExists asks the filesystem --------------------------------
case "$(command uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        kt_test_start "driveExists is true for a mounted drive [G6-20]"
        if tpath.driveExists "C:"; then
            kt_test_pass "C: exists, RESULT='$RESULT'"
        else
            kt_test_fail "C: reported missing (RESULT='$RESULT')"
        fi

        kt_test_start "driveExists is false for an unmounted drive letter [G6-20]"
        missing=""
        for letter in Q R S T U V W X Y Z; do
            if [[ ! -d "/${letter,}" ]]; then missing="$letter"; break; fi
        done
        if [[ -z "$missing" ]]; then
            kt_test_fail "no unmounted drive letter available to test with"
        elif tpath.driveExists "$missing:"; then
            kt_test_fail "$missing: reported as existing (RESULT='$RESULT')"
        else
            kt_test_pass "$missing: reported missing"
        fi
        ;;
    *)
        kt_test_start "driveExists is false on POSIX [G6-20]"
        if tpath.driveExists "C:"; then
            kt_test_fail "reported true on POSIX"
        else
            kt_test_pass "false on POSIX"
        fi
        kt_test_start "driveExists rejects a non-drive path [G6-20]"
        if tpath.driveExists "/path/to/file"; then
            kt_test_fail "reported true"
        else
            kt_test_pass "false"
        fi
        ;;
esac

# --- G6-20: the character validators ---------------------------------------
kt_test_start "'~' is a valid file-name character [G6-20]"
if tpath.isValidFileNameChar "~"; then
    kt_test_pass "true"
else
    kt_test_fail "rejected (RESULT='$RESULT')"
fi

for bad in '<' '>' '|' '"' ':'; do
    kt_test_start "'$bad' is not a valid file-name character [G6-20]"
    if tpath.isValidFileNameChar "$bad"; then
        kt_test_fail "accepted '$bad'"
    else
        kt_test_pass "rejected"
    fi
done

kt_test_start "a backslash is not a valid file-name character [G6-20]"
if tpath.isValidFileNameChar "$BS"; then
    kt_test_fail "accepted the backslash"
else
    kt_test_pass "rejected"
fi

eq "hasValidFileNameChars rejects a Windows-invalid name [G6-20]" \
   "false" "$(tpath.hasValidFileNameChars 'a<b.txt')"
eq "hasValidFileNameChars accepts a tilde [G6-20]" \
   "true" "$(tpath.hasValidFileNameChars '~backup.txt')"
eq "hasValidPathChars rejects a pipe [G6-20]" \
   "false" "$(tpath.hasValidPathChars '/a/b|c')"
eq "hasValidPathChars accepts a drive colon [G6-20]" \
   "true" "$(tpath.hasValidPathChars "C:${BS}dir${BS}f.txt")"

# --- G6-21: nocasematch is restored ----------------------------------------
kt_test_start "matchesPattern preserves a caller's nocasematch=on [G6-21]"
shopt -s nocasematch
tpath.matchesPattern "File.txt" "file.txt" "false" >/dev/null || :
if shopt -q nocasematch; then
    kt_test_pass "still on"
    shopt -u nocasematch
else
    kt_test_fail "matchesPattern cleared the caller's nocasematch"
fi

kt_test_start "matchesPattern preserves a caller's nocasematch=off [G6-21]"
shopt -u nocasematch
tpath.matchesPattern "File.txt" "file.txt" "false" >/dev/null || :
if shopt -q nocasematch; then
    kt_test_fail "matchesPattern left nocasematch on"
    shopt -u nocasematch
else
    kt_test_pass "still off"
fi
