#!/bin/bash
# 008_CopyTo.sh — extended in P5 for finding TSH-16.
#
# The old file had one assertion and wrote its capture file into the system
# temp directory with `mktemp`. TSH-16: because the member's own locals were
# called `self`, `count`, `source_index`, `destination_index` and
# `char_index`, a caller whose array had one of those names silently got
# NOTHING — bash scopes locals dynamically, so `declare -n
# destination_ref=count` bound the member's own local and the writes went
# there, with rc 0. The unit's locals now all carry the reserved `__tsh_`
# prefix and the destination name is validated (kcl/README.md 1.7): a
# reserved or malformed name is rc 2 and nothing is written.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CopyTo" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

source "$SCRIPT_DIR/../tstringhelper.sh"

TMP="$PRIVTMP"
mkdir -p "$TMP"
OUT="$TMP/stdout.txt"

kt_test_start "CopyTo writes the characters into the destination array"
destination=(x x x x x)
: > "$OUT"
rc=0
string.copyTo "abcdef" 2 destination 1 3 > "$OUT" 2>&1 || rc=$?
printed="$(<"$OUT")"
if (( rc == 0 )) && [[ -z "$printed" && "${destination[*]}" == "x c d e x" ]]; then
    kt_test_pass "x c d e x"
else
    kt_test_fail "rc=$rc printed='$printed' destination='${destination[*]}'"
fi

kt_test_start "CopyTo starts at the destination index, not at 0"
destination=()
string.copyTo "abcdef" 0 destination 3 2 >/dev/null 2>&1 || :
if [[ "${destination[3]}" == "a" && "${destination[4]}" == "b" && -z "${destination[0]:-}" ]]; then
    kt_test_pass "elements 3 and 4 written"
else
    kt_test_fail "destination=(${destination[*]})"
fi

kt_test_start "CopyTo of zero characters writes nothing and succeeds"
destination=(k)
rc=0
string.copyTo "abc" 0 destination 0 0 >/dev/null 2>&1 || rc=$?
if (( rc == 0 )) && [[ "${destination[0]}" == "k" ]]; then
    kt_test_pass "rc 0, destination untouched"
else
    kt_test_fail "rc=$rc destination=(${destination[*]})"
fi

# --- TSH-16: a destination named like one of the member's own locals --------
locals_ok() {   # NAME
    local name="$1"
    kt_test_start "a destination array named '$name' really receives the data [TSH-16]"
    unset "$name"
    declare -ga "$name=()"
    local rc=0
    string.copyTo "abcdef" 1 "$name" 0 3 >/dev/null 2>&1 || rc=$?
    local -n ref="$name"
    if (( rc == 0 )) && [[ "${ref[0]}" == "b" && "${ref[1]}" == "c" && "${ref[2]}" == "d" ]]; then
        kt_test_pass "bcd"
    else
        kt_test_fail "rc=$rc array=(${ref[*]})"
    fi
    unset -n ref
    unset "$name"
}

locals_ok self
locals_ok count
locals_ok source_index
locals_ok destination_index
locals_ok char_index
locals_ok destination_name
locals_ok str
locals_ok i

# --- reserved and malformed names are rc 2 (kcl/README.md 1.7) --------------
bad_dest() {   # NAME
    kt_test_start "a destination named '$1' is rc 2 [1.7, TSH-16]"
    local rc=0
    string.copyTo "abcdef" 0 "$1" 0 3 >/dev/null 2>&1 || rc=$?
    if (( rc == 2 )); then
        kt_test_pass "rc 2"
    else
        kt_test_fail "rc=$rc, expected 2"
    fi
}

bad_dest ""
bad_dest RESULT
bad_dest REPLY
bad_dest IFS
bad_dest __kk_x
bad_dest __tsh_x
bad_dest "not valid"
bad_dest "1bad"
bad_dest 'a[$(touch pwn008)]'

kt_test_start "a rejected destination executes nothing [X-INJ]"
if [[ ! -e "$SCRIPT_DIR/pwn008" && ! -e "pwn008" ]]; then
    kt_test_pass "no canary file"
else
    rm -f "$SCRIPT_DIR/pwn008" "pwn008"
    kt_test_fail "the injected command ran"
fi

# --- out-of-range arguments are rc 1 ----------------------------------------
bad_range() {   # TITLE ARGS...
    local title="$1"; shift
    kt_test_start "$title"
    dest_range=()
    local rc=0
    string.copyTo "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && (( ${#dest_range[@]} == 0 )); then
        kt_test_pass "rc 1, destination untouched"
    else
        kt_test_fail "rc=$rc destination=(${dest_range[*]})"
    fi
}

bad_range "a source range past the end is rc 1"        "abc" 1 dest_range 0 5
bad_range "a negative source index is rc 1 [D1]"       "abc" -1 dest_range 0 1
bad_range "a negative destination index is rc 1 [D1]"  "abc" 0 dest_range -1 1
bad_range "a negative count is rc 1 [D1]"              "abc" 0 dest_range 0 -1
bad_range "a non-numeric count is rc 1 [D1]"           "abc" 0 dest_range 0 zz
