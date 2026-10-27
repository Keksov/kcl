#!/usr/bin/env bash
# 021_L35_Portable.sh — launch L3.5-1: the shared filesystem helpers work on
# GNU, busybox and BSD userlands. Every case shadows the tool whose other
# flavour it targets, so each fallback runs on every platform.
#
#   R1  stat flavour: a `stat` that rejects -c (BSD) is answered via -f.
#   R2  no birth time: `W` (busybox), 0 (GNU, BSD), -1 (cygwin, BSD) falls
#       back to the write time; the formatting needs no `date`.
#   R3  setters: `touch -t STAMP` under TZ=UTC0 (POSIX), not `touch -d @E`;
#       a date string goes through BSD `date -j -f` when `date -d` fails.
#   R5  getFullPath without `realpath -m` / `readlink -m`: lexical normaliser.
#   Round 2: the epochs -1 and -2 (printf's "now" / "shell start") round-trip;
#       an epoch with leading zeros is decimal; a stamp touch -t cannot
#       express is refused.
#
# The zone is pinned to a non-UTC one, so local and UTC answers differ on
# every host (a swap of the two would pass on a UTC VM otherwise).
export TZ=JST-9

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "L35_Portable" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
source "$TPATH_DIR/tpath.sh"
source "$SCRIPT_DIR/_fsoracle.sh"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
LOG="$TMP/argv.log"

eq() {   # TITLE EXPECTED ACTUAL
    kt_test_start "$1"
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1 (expected: '$2', got: '$3')"
    fi
}

# --- R5: getFullPath's last fallback ----------------------------------------
realpath() { return 1; }
readlink() { return 1; }
cd "$TMP" || exit 1
eq "getFullPath fallback: . is the working directory [R5]" "$TMP" "$(tpath.getFullPath ".")"
eq "getFullPath fallback: .. is the parent [R5]" "${TMP%/*}" "$(tpath.getFullPath "..")"
eq "getFullPath fallback: a .. in a missing path collapses [R5]" "/nosuch_g613/b" \
   "$(tpath.getFullPath "/nosuch_g613/a/../b")"
eq "getFullPath fallback: ./d/./../d [R5]" "$TMP/d" "$(tpath.getFullPath "./d/./../d")"
eq "getFullPath fallback: never above / [R5]" "/" "$(tpath.getFullPath "/a/../../..")"
eq "getFullPath fallback: a drive-rooted path is answered as given [R5]" "C:/x/../y"    "$(tpath.getFullPath "C:/x/../y")"
eq "getFullPath fallback: a UNC path is answered as given [R5]" "//srv/share/../x"    "$(tpath.getFullPath "//srv/share/../x")"
unset -f realpath readlink

# --- R1: the BSD stat flavour -----------------------------------------------
f="$TMP/r1.txt"
: > "$f"
touch -m -t 202311142213.20 -- "$f" 2>/dev/null
chmod 444 "$f"
want_y="$(fso_stat Y "$f")"
want_x="$(fso_stat X "$f")"
want_a="$(fso_stat a "$f")"
want_attrs="$(tpath.getAttributes "$f")"
date() {   # the getters call no date (R2)
    echo "date $*" >> "$TMP/date.canary"
    return 1
}
stat() {   # a BSD stat: no -c; -f with %a %m %B %Lp from the oracle's values
    printf '%s\n' "$*" >> "$LOG"
    [[ "$1" == "-L" ]] && shift
    if [[ "$1" != "-f" ]]; then
        echo "stat: illegal option -- c" >&2
        return 1
    fi
    case "$2" in
        %a) echo "$want_x" ;;
        %m) echo "$want_y" ;;
        %B) echo 0 ;;
        %Lp) echo "$want_a" ;;
        *) return 1 ;;
    esac
}
: > "$LOG"
__TP_STAT=''
__tp_r=''
tpath._statTime "$f" "%Y" "true"
eq "stat flavour: a stat without -c is probed as bsd [R1]" "bsd" "$__TP_STAT"
eq "stat flavour bsd: write time via stat -f %m [R1]" "$(fso_fmt "$want_y" utc)" "$__tp_r"
tpath._statTime "$f" "%X"
eq "stat flavour bsd: access time via stat -f %a [R1]" "$(fso_fmt "$want_x")" "$__tp_r"
tpath._statTime "$f" "%W"
eq "stat flavour bsd: birth time 0 falls back to %m [R1, R2]" "$(fso_fmt "$want_y")" "$__tp_r"
eq "stat flavour bsd: getAttributes via stat -L -f %Lp [R1]" "$want_attrs" \
   "$(tpath.getAttributes "$f")"
kt_test_start "TZ is pinned: local and UTC answers differ"
if [[ "$(fso_fmt 0)" != "$(fso_fmt 0 utc)" ]]; then
    kt_test_pass "local $(fso_fmt 0), utc $(fso_fmt 0 utc)"
else
    kt_test_fail "local and UTC both '$(fso_fmt 0)'"
fi
kt_test_start "stat flavour bsd: the argv is the BSD one [R1]"
if grep -qxF -- "-f %m -- $f" "$LOG" && grep -qxF -- "-L -f %Lp -- $f" "$LOG"; then
    kt_test_pass "stat flavour bsd argv"
else
    kt_test_fail "argv log: $(tr '\n' '|' < "$LOG")"
fi
unset -f stat
__TP_STAT=''
chmod u+w "$f"

# --- R2: no birth time falls back to the write time -------------------------
f="$TMP/r2.txt"
: > "$f"
touch -m -t 202311142213.20 -- "$f" 2>/dev/null
want="$(fso_fmt "$(fso_stat Y "$f")")"
for wval in W 0 -1; do
    stat() {   # the real stat, except that the birth time answers $wval
        local a
        for a in "$@"; do
            if [[ "$a" == "%W" || "$a" == "%B" ]]; then
                echo "$wval"
                return 0
            fi
        done
        command stat "$@"
    }
    __tp_r=''
    tpath._statTime "$f" "%W"
    eq "creation time: birth time '$wval' falls back to the write time [R2]" "$want" "$__tp_r"
done
unset -f stat
kt_test_start "getters: no date call is left [R2]"
if [[ ! -e "$TMP/date.canary" ]]; then
    kt_test_pass "no date call"
else
    kt_test_fail "date was called: $(tr '
' '|' < "$TMP/date.canary")"
fi
unset -f date

# --- R3: the setter's touch argv --------------------------------------------
got=''
touch() { got="TZ=${TZ-unset} $*"; }
function /usr/bin/touch { got="TZ=${TZ-unset} $*"; }
f="$TMP/r3.txt"
: > "$f"
tpath._touchTime "$f" 1700000000 -m
eq "setter: an epoch goes to touch -t under TZ=UTC0 [R3]" \
   "TZ=UTC0 -m -t 202311142213.20 -- $f" "$got"
got=''
tpath._touchTime "$f" "2023-11-14 22:13:20" -a true
eq "setter: a UTC date string goes to touch -t under TZ=UTC0 [R3]" \
   "TZ=UTC0 -a -t 202311142213.20 -- $f" "$got"

# BSD date: no -d, the canonical string through -j -f.
want_e="$(fso_epoch "2023-11-14 22:13:20" utc)"
date() {
    printf '%s\n' "$*" >> "$LOG"
    local a
    for a in "$@"; do
        if [[ "$a" == "-d" ]]; then
            echo "date: illegal option -- d" >&2
            return 1
        fi
    done
    echo "$want_e"
}
: > "$LOG"
got=''
tpath._touchTime "$f" "2023-11-14 22:13:20" -m true
eq "setter: date -d fails, BSD date -j -f answers [R3]" \
   "TZ=UTC0 -m -t 202311142213.20 -- $f" "$got"
kt_test_start "setter: the BSD date argv [R3]"
if grep -qxF -- "-u -j -f %Y-%m-%d %H:%M:%S 2023-11-14 22:13:20 +%s" "$LOG"; then
    kt_test_pass "BSD date argv"
else
    kt_test_fail "argv log: $(tr '\n' '|' < "$LOG")"
fi
got=''
: > "$LOG"
tpath._touchTime "$f" "2023-11-14 22:13:20" -m
kt_test_start "setter: the local BSD date argv (no -u) [R3]"
if [[ "$got" == "TZ=UTC0 -m -t "* ]]    && grep -qxF -- "-j -f %Y-%m-%d %H:%M:%S 2023-11-14 22:13:20 +%s" "$LOG"; then
    kt_test_pass "local BSD date argv"
else
    kt_test_fail "touch '$got', argv log: $(tr '
' '|' < "$LOG")"
fi
unset -f date touch /usr/bin/touch

# --- round 2: epochs -1 / -2, decimal epochs, the stamp range ---------------
f="$TMP/r4.txt"
: > "$f"
# Epoch -1 cannot be STORED everywhere: FreeBSD's VFS reads -1 as "no
# change" (VNOVAL; touch then stores "now"), busybox touch refuses it and
# busybox date neither parses a string that means it nor formats @-1. So -1
# is checked on the argv (a `date` that answers -1) and through a stat that
# answers it; -2 round-trips on the real filesystem.
got=''
touch() { got="TZ=${TZ-unset} $*"; }
function /usr/bin/touch { got="TZ=${TZ-unset} $*"; }
date() { echo -1; }
tpath._touchTime "$f" "1969-12-31 23:59:59" -m true
eq "setter: epoch -1 (UTC 1969-12-31 23:59:59) is stamp 196912312359.59 [round 2]"    "TZ=UTC0 -m -t 196912312359.59 -- $f" "$got"
unset -f touch /usr/bin/touch date
for e in -1 -2; do
    stat() {   # the real stat, except that the write time answers $e
        local a
        for a in "$@"; do
            if [[ "$a" == "%Y" || "$a" == "%m" ]]; then
                echo "$e"
                return 0
            fi
        done
        command stat "$@"
    }
    s=$(( 60 + e ))
    __tp_r=''; tpath._statTime "$f" "%Y" "true"
    eq "getter: epoch $e in UTC [round 2]" "1969-12-31 23:59:$s" "$__tp_r"
    __tp_r=''; tpath._statTime "$f" "%Y"
    eq "getter: epoch $e in local time (JST) [round 2]" "1970-01-01 08:59:$s" "$__tp_r"
    date() { return 1; }   # busybox: no date formats @-1
    __tp_r=''; tpath._statTime "$f" "%Y"
    eq "getter: epoch $e in local time (JST) without date [round 2]" "1970-01-01 08:59:$s" "$__tp_r"
    unset -f date
done
unset -f stat
rc=0; tpath._touchTime "$f" "1969-12-31 23:59:58" -m true || rc=$?
eq "setter: UTC 1969-12-31 23:59:58 stores epoch -2 [round 2]" "0 -2" "$rc $(fso_stat Y "$f")"
__tp_r=''; tpath._statTime "$f" "%Y" "true"
eq "round trip: epoch -2 read back in UTC [round 2]" "1969-12-31 23:59:58" "$__tp_r"
: > "$f"
rc=0; tpath._touchTime "$f" "1970-01-01 08:59:58" -m || rc=$?
eq "setter: local 1970-01-01 08:59:58 (JST) stores epoch -2 [round 2]" "0 -2" "$rc $(fso_stat Y "$f")"
__tp_r=''; tpath._statTime "$f" "%Y"
eq "round trip: epoch -2 read back in local time (JST) [round 2]" "1970-01-01 08:59:58" "$__tp_r"
rc=0; tpath._touchTime "$f" 0100 -m || rc=$?
eq "setter: epoch 0100 is decimal 100 [round 2]" "0 100" "$rc $(fso_stat Y "$f")"
rc=0; tpath._touchTime "$f" 08 -m || rc=$?
eq "setter: epoch 08 is decimal 8 [round 2]" "0 8" "$rc $(fso_stat Y "$f")"
rc=0; tpath._touchTime "$f" 253402300800 -m || rc=$?
eq "setter: an epoch past 9999-12-31 23:59:59 UTC is refused [round 2]" "1 8" "$rc $(fso_stat Y "$f")"
rc=0; tpath._touchTime "$f" 9999999999999 -m || rc=$?
eq "setter: an epoch of 13 digits is refused [round 2]" "1 8" "$rc $(fso_stat Y "$f")"
