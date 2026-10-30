#!/usr/bin/env bash
# ktests round 5, E1 / DE1 (2026-10-16) — the fallback program file of a KILLED
# process.
#
# Where awk cannot read the program through process substitution, the engine
# writes it to <dir>/.math_fe_<pid>.awk and removes it from an EXIT trap. A
# process killed by a signal runs no EXIT trap on bash 5.2 (5.3 mostly does),
# so the file stayed (5 such files were found in a machine /tmp). Now an engine
# start on the fallback path first removes the .math_fe_<pid>.awk files of
# DEAD processes in the folder it writes to — only a regular file named with an
# all-digit pid that is not this process and not alive (R14: a live process's
# file, another name shape and a symlink are left alone).
#
# The fallback is forced with `awk`/`gawk` functions that refuse /dev/fd programs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "DE1ProgfileSweep" "$SCRIPT_DIR" "$@"

MATH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$MATH_DIR/math.sh"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
P="$TMP/progdir"
mkdir -p "$P"

# the children force the fallback path. The engine prefers `gawk` and gives
# another awk `-W interactive` first (L2.7-M), so both names are shadowed and
# every argument is checked, not only $2. `gawk` only where one exists: the
# function alone would make `command -v gawk` succeed on a mawk-only system.
SHIM='_kt018_awk() { local a; for a in "${@:2}"; do case "$a" in /dev/fd/*|/proc/*) return 1 ;; esac; done; command "$@"; }
awk() { _kt018_awk awk "$@"; }
if command -v gawk >/dev/null 2>&1; then gawk() { _kt018_awk gawk "$@"; }; fi'

dead="$(bash -c 'echo $$')"          # a pid that has just exited
fresh="$(bash -c 'echo $$')"         # another one, its file just written
live=$$                              # this test file's shell: alive
: > "$P/.math_fe_${dead}.awk"
: > "$P/.math_fe_${fresh}.awk"
: > "$P/.math_fe_${live}.awk"
: > "$P/.math_fe_abc.awk"
: > "$P/.math_fe_${dead}.awk.keep"
# review R3: only a file older than 5 minutes is a dead process's leftover — a
# younger one may belong to an engine starting right now in another MSYS
# runtime (whose pids `kill -0` cannot see)
printf -v _st '%(%Y%m%d%H%M.%S)T' $(( EPOCHSECONDS - 600 ))
touch -t "$_st" "$P/.math_fe_${dead}.awk" "$P/.math_fe_${live}.awk" \
    "$P/.math_fe_abc.awk" "$P/.math_fe_${dead}.awk.keep"
ln -s "$P/.math_fe_abc.awk" "$P/.math_fe_9.awk" 2>/dev/null
# MSYS `ln -s` may make a COPY: a regular .math_fe_9.awk would be judged by
# whether pid 9 is alive here — no symlink case then (review R7)
[[ -L "$P/.math_fe_9.awk" ]] || rm -f -- "$P/.math_fe_9.awk"
keep=( ".math_fe_${dead}.awk.keep" ".math_fe_${fresh}.awk" ".math_fe_${live}.awk" .math_fe_abc.awk )
[[ -L "$P/.math_fe_9.awk" ]] && keep+=( .math_fe_9.awk )

# kt018_sorted NAME... / kt018_ls — sorted, space-separated (the .math_fe* in $P)
kt018_sorted() { printf '%s\n' "$@" | sort | tr '\n' ' '; }
kt018_ls() { (cd "$P" && ls -A | grep '^\.math_fe' | sort | tr '\n' ' '); }
want="$(kt018_sorted "${keep[@]}")"

kt_test_start "the fallback path is in use and leaves nothing of its own [DE1]"
out="$(TMPDIR="$P" bash -c "$SHIM
source '$UNIT'
math.sin 1 >/dev/null
printf '%s|%s' \"\$RESULT\" \"\${__MATH_FE_PROGFILE##*/}\"" 2>&1)"
mine="${out#*|}"
if [[ "${out%%|*}" == 0.84147* && "$mine" == .math_fe_*.awk && ! -e "$P/$mine" ]]; then
    kt_test_pass "used $mine, removed at exit"
else
    kt_test_fail "out='$out'"
fi

kt_test_start "an engine start removes a DEAD pid's file older than 5 min only (a fresh one, a live pid's, other names, a symlink kept) [DE1, R14, R3]"
left="$(kt018_ls)"
if [[ "$left" == "$want" ]]; then
    kt_test_pass "left: $left"
else
    kt_test_fail "left '$left' want '$want'"
fi

kt_test_start "a process killed after its engine started: the next engine start removes its file [DE1]"
# `exec sleep`: the same pid, and no EXIT trap will ever run (bash 5.2 on a
# SIGTERM); the kill does not depend on the box's load
TMPDIR="$P" bash -c "$SHIM
source '$UNIT'
math.sin 1 >/dev/null
printf '%s' \"\$\$\" > '$TMP/killed.pid'
exec sleep 120" >/dev/null 2>&1 &
cpid=$!
for (( i = 0; i < 1200; i++ )); do [[ -s "$TMP/killed.pid" ]] && break; sleep 0.1; done
# the pid file is written just BEFORE the exec: a TERM that lands while cygwin
# execs is lost and the wait used to sit out the whole sleep 120 (found by the
# ktests gate G4: ~1 run in 3 threaded on 5.2). So: TERM only once the process
# IS the sleep, then a bounded wait, KILL if it is still there
for (( i = 0; i < 100; i++ )); do
    c=""; { read -r -d '' c < "/proc/$cpid/cmdline"; } 2>/dev/null
    [[ "${c##*/}" == sleep* || -z "$c" ]] && break
    sleep 0.05
done
kill -TERM "$cpid" 2>/dev/null
for (( i = 0; i < 50; i++ )); do kill -0 "$cpid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$cpid" 2>/dev/null && kill -KILL "$cpid" 2>/dev/null
wait "$cpid" 2>/dev/null
kpid="$(<"$TMP/killed.pid")"
leaked=no; [[ -n "$kpid" && -e "$P/.math_fe_${kpid}.awk" ]] && leaked=yes
# ... and some minutes pass (the age guard, R3)
[[ $leaked == yes ]] && { printf -v _st '%(%Y%m%d%H%M.%S)T' $(( EPOCHSECONDS - 600 )); touch -t "$_st" "$P/.math_fe_${kpid}.awk"; }
TMPDIR="$P" bash -c "$SHIM
source '$UNIT'
math.cos 0 >/dev/null" >/dev/null 2>&1
if [[ $leaked == yes && ! -e "$P/.math_fe_${kpid}.awk" && "$(kt018_ls)" == "$want" ]]; then
    kt_test_pass "killed pid $kpid left its file; the next start removed it"
else
    kt_test_fail "killed pid '$kpid' leaked=$leaked, left '$(kt018_ls)' want '$want'"
fi

# review round 2, N2: a drive-letter folder (TMPDIR=C:/…, or MATH_DIR when the
# unit is sourced by a C:/ path) is absolute — it used to become ./C:/… and
# the sweep found nothing there
kt_test_start "the sweep works in a drive-letter TMPDIR (C:/…) [N2]"
P2="$TMP/drive"; mkdir -p "$P2"
P2M="$(cygpath -m "$P2" 2>/dev/null)"
if [[ "$P2M" != [A-Za-z]:/* ]]; then
    kt_test_pass "no drive-letter paths on this system (not checked)"
else
    d2="$(bash -c 'echo $$')"
    : > "$P2/.math_fe_${d2}.awk"
    printf -v _st '%(%Y%m%d%H%M.%S)T' $(( EPOCHSECONDS - 600 ))
    touch -t "$_st" "$P2/.math_fe_${d2}.awk"
    TMPDIR="$P2M" bash -c "$SHIM
source '$UNIT'
math.sin 1 >/dev/null" >/dev/null 2>&1
    if [[ ! -e "$P2/.math_fe_${d2}.awk" && -z "$(cd "$P2" && ls -A)" ]]; then
        kt_test_pass "stale .math_fe_${d2}.awk removed from $P2M"
    else
        kt_test_fail "left in $P2M: [$(cd "$P2" && ls -A | tr '\n' ' ')]"
    fi
fi

# launch L5.4-4, C2: a CI runner starts its steps with SIGPIPE IGNORED, and a
# bash can never restore it. The program writer of the process substitution
# then got EPIPE instead of dying silently when the shimmed awk refused the
# program, and printed `math.sh: line 850: printf: Broken pipe` (twice) into
# the caller's stderr. The engine start must stay silent under such a parent.
kt_test_start "the parent ignores SIGPIPE: the engine start prints nothing into the caller's stderr [L5.4-4, C2]"
P3="$TMP/pipeign"; mkdir -p "$P3"
out="$(trap '' PIPE; TMPDIR="$P3" bash -c "$SHIM
source '$UNIT'
math.sin 1 >/dev/null
printf '%s' \"\$RESULT\"" 2>&1)"; rc=$?
if (( rc == 0 )) && [[ "$out" =~ ^0\.84147[0-9]*$ ]]; then
    kt_test_pass "rc 0, out '$out' and nothing else"
else
    kt_test_fail "rc=$rc out='$out'"
fi

# launch L5.4-4, C7: the start probe (`pi`) is written right after `coproc`.
# When the co-process has ALREADY exited (here: the shimmed awk refused the
# /dev/fd program), the write has no reader left; it used to run in the
# calling shell, whose default SIGPIPE killed the whole caller before the
# fallback (rc 141, no output — the CI shape `out=''`). The race is made
# deterministic with test shims (functions, like `awk` above): the refusing
# awk HOLDS until the file $GONE_GO exists (else bash may reap the co-process
# before math._fe_spawn reads its fds, and no probe is written at all), and a
# `printf` function, on the process-substitution start probe, creates
# $GONE_GO, waits until the pipe has no reader — a 1-byte write in a subshell
# that ignores SIGPIPE fails with EPIPE — removes $GONE_GO and only then
# writes `pi`. It logs `gone` (no reader left) or `alive` (still a reader
# after 10 s: the case could not be set up) per probe; no log line = no probe
# was written (not set up either).
kt_test_start "the co-process is gone before the start probe: the caller survives and the fallback engine answers [L5.4-4, C7]"
P4="$TMP/gone"; mkdir -p "$P4"
GONE_LOG="$TMP/gone.log"; : > "$GONE_LOG"
GONE_GO="$TMP/gone.go"; rm -f -- "$GONE_GO"
GONE='_kt018_awk() {
    local a n=0
    for a in "${@:2}"; do
        case "$a" in /dev/fd/*|/proc/*)
            while [[ ! -e $GONE_GO ]] && (( n++ < 200 )); do sleep 0.05; done
            return 1 ;;
        esac
    done
    command "$@"
}
printf() {
    if [[ ${1-} == "pi\n" && -z ${__MATH_FE_PROGFILE-} ]]; then
        local _kt018_n=0 _kt018_st=alive
        : > "$GONE_GO"
        while (( _kt018_n++ < 200 )); do
            ( trap "" PIPE; builtin printf x ) 2>/dev/null || { _kt018_st=gone; break; }
            sleep 0.05
        done
        rm -f -- "$GONE_GO"
        builtin printf "%s\n" "$_kt018_st" >> "$GONE_LOG"
    fi
    builtin printf "$@"
}'
out="$(TMPDIR="$P4" GONE_LOG="$GONE_LOG" GONE_GO="$GONE_GO" bash -c "$SHIM
$GONE
source '$UNIT'
math.sin 1 >/dev/null
builtin printf '%s|%s' \"\$RESULT\" \"\${__MATH_FE_PROGFILE##*/}\"" 2>&1)"; rc=$?
glog="$(tr '\n' ' ' < "$GONE_LOG")"
mine="${out#*|}"
if (( rc == 0 )) && [[ "${out%%|*}" == 0.84147* && "$mine" == .math_fe_*.awk && "$glog" == gone* && "$glog" != *alive* ]]; then
    kt_test_pass "probes [${glog% }]: caller alive, fallback $mine answered"
else
    kt_test_fail "rc=$rc out='$out' probes [${glog% }]"
fi

kt_test_log "018_DE1_ProgfileSweep.sh completed"
