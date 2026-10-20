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
# The fallback is forced with an `awk` function that refuses /dev/fd programs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "DE1ProgfileSweep" "$SCRIPT_DIR" "$@"

MATH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$MATH_DIR/math.sh"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
P="$TMP/progdir"
mkdir -p "$P"

# the children force the fallback path
SHIM='awk() { case "$2" in /dev/fd/*|/proc/*) return 1 ;; esac; command awk "$@"; }'

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
touch -d '10 minutes ago' "$P/.math_fe_${dead}.awk" "$P/.math_fe_${live}.awk" \
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
[[ $leaked == yes ]] && touch -d '10 minutes ago' "$P/.math_fe_${kpid}.awk"
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
    touch -d '10 minutes ago' "$P2/.math_fe_${d2}.awk"
    TMPDIR="$P2M" bash -c "$SHIM
source '$UNIT'
math.sin 1 >/dev/null" >/dev/null 2>&1
    if [[ ! -e "$P2/.math_fe_${d2}.awk" && -z "$(cd "$P2" && ls -A)" ]]; then
        kt_test_pass "stale .math_fe_${d2}.awk removed from $P2M"
    else
        kt_test_fail "left in $P2M: [$(cd "$P2" && ls -A | tr '\n' ' ')]"
    fi
fi

kt_test_log "018_DE1_ProgfileSweep.sh completed"
