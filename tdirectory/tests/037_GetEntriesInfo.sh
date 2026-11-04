#!/usr/bin/env bash
# 037_GetEntriesInfo.sh — tdirectory.getEntriesInfo (a kcl extension).
#
#   getEntriesInfo DIR PREFIX [PATTERN] fills PREFIX_name / _kind / _size /
#   _mtime / _mode for every entry of DIR, from ONE `stat` call per chunk of
#   paths. The oracles here are the per-entry tpath._stat (mode, write time)
#   and the byte counts the fixture writes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/symlink_helper.sh"

kt_test_init "GetEntriesInfo" "$SCRIPT_DIR" "$@"

TDIRECTORY_DIR="$SCRIPT_DIR/.."
UNIT="$TDIRECTORY_DIR/tdirectory.sh"
source "$UNIT"

W="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$W/stdout.txt"
CALLS="$W/stat_calls.txt"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# index of NAME in the e_name array, or -1
idx() {
    local i
    for (( i = 0; i < ${#e_name[@]}; i++ )); do
        if [[ "${e_name[i]}" == "$1" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo -1
}

# --- the fixture: distinct sizes, so a misaligned answer cannot pass --------
D="$W/d"
mkdir -p "$D/sub" "$D/.hiddendir"
printf 'a'      > "$D/one"
printf 'bb'     > "$D/two words"
printf 'ccc'    > "$D/"$'line\nbreak'
printf 'dddd'   > "$D/-dash"
printf 'eeeee'  > "$D/.hidden"
printf 'é'      > "$D/utf8"            # two bytes in UTF-8
printf 'x\r\n'  > "$D/crlf"            # the CR counts
: > "$D/empty"

kt_test_start "lists every entry, dot-entries included, and RESULT is the count"
tdirectory.getEntriesInfo "$D" e > "$OUT" 2>&1
rc=$?
printed="$(<"$OUT")"
if (( rc == 0 )) && [[ -z "$printed" ]] && (( RESULT == 10 )) && (( ${#e_name[@]} == 10 )); then
    kt_test_pass "10 entries, silent"
else
    kt_test_fail "rc $rc, RESULT '$RESULT', ${#e_name[@]} names, printed '$printed'"
fi

kt_test_start "the five arrays are parallel and the same length"
if (( ${#e_kind[@]} == 10 && ${#e_size[@]} == 10 && ${#e_mtime[@]} == 10 && ${#e_mode[@]} == 10 )); then
    kt_test_pass "5 x 10"
else
    kt_test_fail "kind ${#e_kind[@]} size ${#e_size[@]} mtime ${#e_mtime[@]} mode ${#e_mode[@]}"
fi

kt_test_start "names are bare names in the order of getFileSystemEntries"
tdirectory.getFileSystemEntries "$D" "*" TopDirectoryOnly full
bare=( "${full[@]##*/}" )
if [[ "${bare[*]}" == "${e_name[*]}" ]]; then
    kt_test_pass "same order"
else
    kt_test_fail "got (${e_name[*]}), listing (${bare[*]})"
fi

kt_test_start "sizes are byte counts, matched to the right names"
bad=""
for pair in one:1 "two words:2" $'line\nbreak:3' -dash:4 .hidden:5 utf8:2 crlf:3 empty:0; do
    n="${pair%:*}"; want="${pair##*:}"
    i=$(idx "$n")
    if (( i < 0 )) || [[ "${e_size[i]}" != "$want" ]]; then
        bad+=" $(printf '%q' "$n")=${e_size[i]:-missing}"
    fi
done
if [[ -z "$bad" ]]; then kt_test_pass "8 files"; else kt_test_fail "wrong:$bad"; fi

kt_test_start "kinds: f for files, d for directories"
bad=""
for n in one "two words" -dash .hidden empty; do
    i=$(idx "$n"); [[ "${e_kind[i]}" == f ]] || bad+=" $n=${e_kind[i]}"
done
for n in sub .hiddendir; do
    i=$(idx "$n"); [[ "${e_kind[i]}" == d ]] || bad+=" $n=${e_kind[i]}"
done
if [[ -z "$bad" ]]; then kt_test_pass "kinds"; else kt_test_fail "wrong:$bad"; fi

kt_test_start "mtime and mode agree with the per-entry stat"
bad=""
for (( i = 0; i < ${#e_name[@]}; i++ )); do
    tpath._stat Y "$D/${e_name[i]}"; t=$__tp_e
    tpath._stat a "$D/${e_name[i]}"; m=$__tp_e
    m=$(( 8#$m )); printf -v m '%o' "$m"
    if [[ "${e_mtime[i]}" != "$t" || "${e_mode[i]}" != "$m" ]]; then
        bad+=" $(printf '%q' "${e_name[i]}"):${e_mtime[i]}/$t,${e_mode[i]}/$m"
    fi
done
if [[ -z "$bad" ]]; then kt_test_pass "all entries"; else kt_test_fail "differ:$bad"; fi

kt_test_start "a set write time comes back as the same epoch"
touch -d '@1700000000' "$D/one" 2>/dev/null || touch -t 202311142213.20 "$D/one"
tpath._stat Y "$D/one"; want=$__tp_e
tdirectory.getEntriesInfo "$D" e
i=$(idx one)
if [[ "${e_mtime[i]}" == "$want" && "$want" =~ ^[0-9]+$ ]]; then
    kt_test_pass "epoch $want"
else
    kt_test_fail "got '${e_mtime[i]}', stat says '$want'"
fi

# --- pattern ---------------------------------------------------------------
tdirectory.getEntriesInfo "$D" p '*o*'
eq "PATTERN filters by name" "one two words" "${p_name[*]}"
tdirectory.getEntriesInfo "$D" p '@(one|empty)'
eq "an extglob PATTERN works" "empty one" "${p_name[*]}"
tdirectory.getEntriesInfo "$D" p 'nomatch*'
eq "a PATTERN with no match gives 0" "0:0" "$RESULT:${#p_name[@]}"

# --- separators, the root, an empty directory -------------------------------
tdirectory.getEntriesInfo "$D/" s
eq "a trailing separator lists the same entries" "${e_name[*]}" "${s_name[*]}"

kt_test_start "the root lists bare names, none with a slash"
tdirectory.getEntriesInfo / r
bad=0
for n in ${r_name[@]+"${r_name[@]}"}; do [[ "$n" == */* || -z "$n" ]] && bad=1; done
if (( RESULT > 0 && bad == 0 )) && [[ -e "/${r_name[0]}" || -L "/${r_name[0]}" ]]; then
    kt_test_pass "$RESULT entries"
else
    kt_test_fail "RESULT '$RESULT', first '${r_name[0]:-}'"
fi

mkdir -p "$W/emptydir"
e2_name=(stale); e2_kind=(stale); e2_size=(1); e2_mtime=(1); e2_mode=(1)
tdirectory.getEntriesInfo "$W/emptydir" e2
eq "an empty directory: count 0 and the arrays are emptied" "0:0:0:0:0:0" \
   "$RESULT:${#e2_name[@]}:${#e2_kind[@]}:${#e2_size[@]}:${#e2_mtime[@]}:${#e2_mode[@]}"

# --- symlinks and other kinds ----------------------------------------------
L="$W/links"
mkdir -p "$L/realdir"
printf '1234567890' > "$L/target"     # 10 bytes; the link text "target" is 6
if kt_make_symlink "$L/tolink" target && kt_make_symlink "$L/broken" nowhere \
    && kt_make_symlink "$L/todir" realdir; then
    tdirectory.getEntriesInfo "$L" e
    kt_test_start "a symlink is kind l, a broken one is listed too"
    a=$(idx tolink); b=$(idx broken); c=$(idx todir)
    if (( a >= 0 && b >= 0 && c >= 0 )) && [[ "${e_kind[a]}${e_kind[b]}${e_kind[c]}" == lll ]]; then
        kt_test_pass "lll"
    else
        kt_test_fail "tolink=${e_kind[a]:-?} broken=${e_kind[b]:-?} todir=${e_kind[c]:-?} (${e_name[*]})"
    fi
    t=$(idx target)
    eq "a link's size is its own (the link text), not its target's" \
       "6:10" "${e_size[a]}:${e_size[t]}"
    kt_test_start "[[ -d ]] on a listed link tells a directory link, no fork"
    if [[ -d "$L/${e_name[c]}" && ! -d "$L/${e_name[a]}" ]]; then
        kt_test_pass "todir is a directory link"
    else
        kt_test_fail "todir/tolink"
    fi
else
    kt_test_fail "could not create native symlinks"
fi

F="$W/fifo"
mkdir -p "$F"
if mkfifo "$F/pipe" 2>/dev/null; then
    tdirectory.getEntriesInfo "$F" e
    eq "a FIFO is kind o" "pipe:o" "${e_name[0]:-}:${e_kind[0]:-}"
else
    kt_test_start "a FIFO is kind o"
    kt_test_pass "mkfifo not available here (skipped)"
fi

# --- cost: one stat per directory -------------------------------------------
# A function named stat shadows the external one inside the member's $( ),
# and counts its calls in a file (a subshell cannot count in a variable).
stat() { printf 'x' >> "$CALLS"; command stat "$@"; }

: > "$CALLS"
tdirectory.getEntriesInfo "$D" e
calls="$(<"$CALLS")"
eq "a ten-entry directory costs ONE stat call" "1:10" "${#calls}:$RESULT"

: > "$CALLS"
tdirectory.getEntriesInfo "$W/emptydir" z
calls="$(<"$CALLS")"
eq "an empty directory costs no stat call" "0" "${#calls}"

: > "$CALLS"
__TD_STAT_CHUNK=1
tdirectory.getEntriesInfo "$D" c
__TD_STAT_CHUNK=65536
calls="$(<"$CALLS")"
eq "a chunk limit of 1 byte: one call per entry" "10" "${#calls}"
eq "chunked: the same names" "${e_name[*]}" "${c_name[*]}"
eq "chunked: the same sizes" "${e_size[*]}" "${c_size[*]}"
eq "chunked: the same modes" "${e_mode[*]}" "${c_mode[*]}"

# --- an entry that vanishes between the glob and the stat --------------------
V="$W/vanish"
mkdir -p "$V"
printf 'a' > "$V/a1"; printf 'bb' > "$V/b2"; printf 'ccc' > "$V/c3"; printf 'dddd' > "$V/d4"
stat() {
    if [[ -e "$V/b2" ]]; then rm -f -- "$V/b2"; fi
    command stat "$@"
}
tdirectory.getEntriesInfo "$V" v
unset -f stat
eq "a vanished entry is dropped and the rest stay aligned" \
   "3:a1=1 c3=3 d4=4" "$RESULT:${v_name[0]:-}=${v_size[0]:-} ${v_name[1]:-}=${v_size[1]:-} ${v_name[2]:-}=${v_size[2]:-}"

# --- refusals ----------------------------------------------------------------
rc_is() {   # TITLE EXPECTED-RC ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    local rc=0
    tdirectory.getEntriesInfo "$@" > "$OUT" 2>&1 || rc=$?
    local printed; printed="$(<"$OUT")"
    if (( rc == want )) && [[ -z "$printed" && -z "$RESULT" ]]; then
        kt_test_pass "$title (rc $rc)"
    else
        kt_test_fail "$title (rc $rc, expected $want; RESULT '$RESULT', printed '$printed')"
    fi
}
rc_is "an empty DIR is rc 1, silent" 1 "" e
rc_is "a missing DIR is rc 1, silent" 1 "$W/nosuch" e
rc_is "a FILE as DIR is rc 1" 1 "$D/one" e
rc_is "no PREFIX is rc 2" 2 "$D"
rc_is "a malformed PREFIX is rc 2" 2 "$D" 'a-b'
rc_is "a PREFIX starting with a digit is rc 2" 2 "$D" '1x'
rc_is "a reserved PREFIX is rc 2" 2 "$D" '__td'

kt_test_start "an error is reported under VERBOSE_KKLASS=debug"
msg="$(VERBOSE_KKLASS=debug tdirectory.getEntriesInfo "$W/nosuch" e 2>&1)" || :
if [[ "$msg" == *"does not exist"* ]]; then kt_test_pass "message"; else kt_test_fail "got '$msg'"; fi

# --- the contract --------------------------------------------------------------
eq "inside \$( ) the count is printed once" "10" "$(tdirectory.getEntriesInfo "$D" e)"

kt_test_start "the caller's glob options and IFS are left as they were"
shopt -u dotglob extglob nullglob; shopt -s failglob
IFS=':'
tdirectory.getEntriesInfo "$D" e
n=$RESULT
IFS=$' \t\n'
st="$(shopt -p dotglob extglob nullglob failglob | tr '\n' ' ')"
shopt -u failglob
if (( n == 10 )) && [[ "$st" == "shopt -u dotglob shopt -u extglob shopt -u nullglob shopt -s failglob " ]]; then
    kt_test_pass "options restored, IFS=':' did not matter"
else
    kt_test_fail "count $n, options: $st"
fi

kt_test_start "works under set -eu"
out="$(bash -c "set -eu
source '$UNIT'
tdirectory.getEntriesInfo '$D' q
echo \"\$RESULT \${q_size[0]}\"" 2>&1)"
if [[ "$out" =~ ^10\ [0-9]+$ ]]; then kt_test_pass "$out"; else kt_test_fail "got '$out'"; fi
