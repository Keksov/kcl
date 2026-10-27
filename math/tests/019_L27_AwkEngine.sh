#!/usr/bin/env bash
# L2.7-M (launch plan, 2026-10-22) — the engine on any awk, and why it failed.
#
#   C1  On Debian/Ubuntu `awk` is mawk 1.3.4, and the engine failed SILENTLY:
#       mawk's parser overflowed on the 81-link `else if` dispatch chain; mawk
#       answers a pipe only under `-W interactive`; mawk's `nan == 0` is true.
#       Now: a flat dispatch, `gawk` preferred when present, any other awk
#       started with `-W interactive` first (then without it), NaN-guarded
#       compares, and MATH_FE_ERROR + a kk.debug line when no awk can run it.
#   C1b mawk 20240123 -W interactive never answers a request line of 4096+
#       characters, the newline not counted (and blocks every call after
#       it): math._fe refuses such a request (rc 1) under __MATH_FE_LINEMAX
#       instead of hanging. mawk 20250131 answers it and gets no limit
#       (L2.7-M2: the limit is set for a mawk dated before 20250131, or with
#       a date that cannot be read).
#   N1  gawk 5.0 orders NaN ABOVE every number, so `_ipow(b, nan)` looped
#       forever (the host crash of 2026-10-22); `inf` looped on every gawk.
#       futureValue/presentValue/payment pass `n` to it unchecked: a
#       non-finite n now answers nan, promptly.
#   N2  mawk 1.3.4 20250131 (Debian 13) reads the unit's `+nan` `-nan` `+inf`
#       `-inf` operands as 0 and `-0` as +0: the engine rewrites them itself.
#
# L2.7-M2 (the L2.7-M critic's follow-up):
#   P1  the co-process IS the awk (exec), so math._fe_drop kills a wedged awk.
#   F4  the line limit applies to mawk only (`-W version`, cached), not to any
#       awk that merely accepts -W — and only to a mawk dated before 20250131
#       or of an unreadable date (owner decision).
#   F1  the C1b row now goes red without the guard on mawk too: a long
#       timeout, a short time bound and the same engine pid before and after.
#   F6  the request is joined with a space whatever the caller's IFS.
#   F8  a failed start is not retried by every Tier-B call; math.feStart
#       retries, and a success clears MATH_FE_ERROR.
#   F10 every spelling of -0 reaches the engine as a negative zero.
#   ldexp: a huge |p| is clamped (gawk 5.2.1 never returned for p = INT64_MIN).
#
# The awk is forced with small wrapper SCRIPTS in a private PATH directory
# (that hides `gawk`), or with `awk`/`gawk` FUNCTIONS; each child that may
# meet a broken engine runs with __MATH_FE_STRICT=1 and a short timeout, so a
# regression is a bounded red row, not a hung (or memory-eating) cell.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "L27AwkEngine" "$SCRIPT_DIR" "$@"

MATH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$MATH_DIR/math.sh"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

REAL_AWK="$(command -v awk)"      # mawk on Debian/Ubuntu, gawk elsewhere
CAT="$(command -v cat)"
RM="$(command -v rm)"
HAVE_GAWK=""; command -v gawk >/dev/null 2>&1 && HAVE_GAWK=1
real_id="$(LC_ALL=C "$REAL_AWK" -W version </dev/null 2>&1)"; real_id=${real_id%%$'\n'*}
# a line-wise awk without any flag from the engine: gawk, else the system awk
# with -W interactive when it is mawk, else the system awk as it is (BWK and
# busybox answer a pipe line by line without a flag; BWK takes `-W` for an
# unknown option and `interactive` for its program — launch L3.5-5) — what an
# awk that rejects -W must be to answer
if [[ -n $HAVE_GAWK ]]; then LINEWISE="\"$(command -v gawk)\""
elif [[ $real_id == mawk* ]]; then LINEWISE="\"$REAL_AWK\" -W interactive"
else LINEWISE="\"$REAL_AWK\""; fi
# is the system awk a mawk older than 20250131 (or of an unreadable date)?
# then an engine on it has the 4095-character limit
REAL_LIMITED=""
if [[ $real_id == mawk* ]]; then
    re='^mawk [0-9.]+ ([0-9]{8})'
    if [[ $real_id =~ $re ]] && (( 10#${BASH_REMATCH[1]} >= 20250131 )); then :; else REAL_LIMITED=1; fi
fi

# mkwrap DIR BODY — DIR/awk: logs its argv to DIR/argv, then runs BODY
mkwrap() {
    mkdir -p "$1"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/argv"\n%s\n' "$1" "$2" > "$1/awk"
    # `rm` too: on the fallback path the unit removes its own program file,
    # and these directories are the whole PATH of the child
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$RM" > "$1/rm"
    chmod +x "$1/awk" "$1/rm"
}
mkwrap "$TMP/w_plain"  "exec \"$REAL_AWK\" \"\$@\""
mkwrap "$TMP/w_noW"    "[ \"\$1\" = -W ] && exit 2; exec $LINEWISE \"\$@\""
mkwrap "$TMP/w_dead"   "exit 3"
# silent but ALIVE, like mawk without -W interactive: it keeps the answer pipe
# open on fd 3 (the engine execs the awk, so no shell holds it open for it)
mkwrap "$TMP/w_silent" "exec 3>&1; exec \"$CAT\" >/dev/null"
# awks that accept -W and say who they are: an old mawk (the limit applies,
# also where the awk underneath is gawk), a new mawk and a mawk of no
# readable date (unknown -> limited), and some other awk (no limit)
mkwrap "$TMP/w_fakemawk" "if [ \"\$1 \$2\" = \"-W version\" ]; then echo 'mawk 1.3.4 20240123 (kt019 wrapper)'; exit 0; fi
[ \"\$1\" = -W ] && shift 2; exec $LINEWISE \"\$@\""
mkwrap "$TMP/w_newmawk" "if [ \"\$1 \$2\" = \"-W version\" ]; then echo 'mawk 1.3.4 20250131 (kt019 wrapper)'; exit 0; fi
[ \"\$1\" = -W ] && shift 2; exec $LINEWISE \"\$@\""
mkwrap "$TMP/w_nodatemawk" "if [ \"\$1 \$2\" = \"-W version\" ]; then echo 'mawk 1.3.4 (kt019 wrapper)'; exit 0; fi
[ \"\$1\" = -W ] && shift 2; exec $LINEWISE \"\$@\""
mkwrap "$TMP/w_otherawk" "if [ \"\$1 \$2\" = \"-W version\" ]; then echo 'otherawk 1.0 (kt019 wrapper)'; exit 0; fi
[ \"\$1\" = -W ] && shift 2; exec $LINEWISE \"\$@\""

# child PRE_SOURCE POST_SOURCE — a bounded bash child that sources the unit
child() {
    bash -c "$1
source '$UNIT'
__MATH_FE_STRICT=1 __MATH_FE_TIMEOUT=\${KT019_TO:-5}
$2" 2>&1
}

# ---------------------------------------------------------------------------
# 1. B — gawk is preferred when it is on PATH, and gets no -W flag
# ---------------------------------------------------------------------------
kt_test_start "gawk on PATH: the engine runs on gawk, without -W interactive [L2.7-M B]"
if [[ -z $HAVE_GAWK ]]; then
    kt_test_pass "N/A: no gawk on this system"
else
    : > "$TMP/mark_b"
    out="$(child "" "
gawk() { printf 'gawk %s\n' \"\$*\" >> '$TMP/mark_b'; command gawk \"\$@\"; }
awk()  { printf 'awk %s\n' \"\$*\" >> '$TMP/mark_b'; command awk \"\$@\"; }
math.sin 1 >/dev/null; printf '%s|%s|%s' \"\$RESULT\" \"\$MATH_FE_ERROR\" \"\${__MATH_FE_LINEMAX}\"
math.feStop")"
    marks="$(<"$TMP/mark_b")"
    if [[ $out == "0.8414709848078965||" && $marks == "gawk -f "* && $marks != *$'\n'* ]]; then
        kt_test_pass "one gawk start ($marks)"
    else
        kt_test_fail "out='$out' starts='$marks'"
    fi
fi

# ---------------------------------------------------------------------------
# 2. A — another awk is started with -W interactive first
# ---------------------------------------------------------------------------
kt_test_start "no gawk: awk is started with -W interactive and answers [L2.7-M A3]"
out="$(child "" "PATH='$TMP/w_plain'
math.sin 1 >/dev/null; printf '%s|%s|%s' \"\$RESULT\" \"\$MATH_FE_ERROR\" \"\${__MATH_FE_LINEMAX}\"
math.feStop")"
argv="$(head -n 1 "$TMP/w_plain/argv" 2>/dev/null)"
want_lm=""; [[ -n $REAL_LIMITED ]] && want_lm=4095
if [[ $out == "0.8414709848078965||$want_lm" && $argv == "-W interactive -f "* ]]; then
    kt_test_pass "first start: '$argv'"
else
    kt_test_fail "out='$out' argv='$argv'"
fi

kt_test_start "the line limit is old mawk's: mawk 20240123 and an undated mawk get 4095; mawk 20250131 and another awk none; one -W version per PATH [L2.7-M2 F4]"
out="$(child "" "PATH='$TMP/w_fakemawk'
math.sin 1 >/dev/null; printf '%s|%s|' \"\$RESULT\" \"\${__MATH_FE_LINEMAX}\"
math.feStop; math.feStart; printf '%s|' \"\${__MATH_FE_LINEMAX}\"
math.feStop
PATH='$TMP/w_newmawk'
math.sin 1 >/dev/null; printf 'new:%s|%s|' \"\$RESULT\" \"\${__MATH_FE_LINEMAX}\"
math.feStop
PATH='$TMP/w_nodatemawk'
math.sin 1 >/dev/null; printf 'nodate:%s|%s|' \"\$RESULT\" \"\${__MATH_FE_LINEMAX}\"
math.feStop
PATH='$TMP/w_otherawk'
math.sin 1 >/dev/null; printf 'other:%s|%s' \"\$RESULT\" \"\${__MATH_FE_LINEMAX}\"
math.feStop")"
nv_m=$(grep -c '^-W version' "$TMP/w_fakemawk/argv"); nv_o=$(grep -c '^-W version' "$TMP/w_otherawk/argv")
want="0.8414709848078965|4095|4095|new:0.8414709848078965||nodate:0.8414709848078965|4095|other:0.8414709848078965|"
if [[ $out == "$want" && $nv_m == 1 && $nv_o == 1 ]]; then
    kt_test_pass "$out (-W version: $nv_m + $nv_o)"
else
    kt_test_fail "out='$out' -W version calls: fakemawk=$nv_m otherawk=$nv_o"
fi

kt_test_start "an awk that rejects -W is restarted without it [L2.7-M A3]"
out="$(child "" "PATH='$TMP/w_noW'
math.sin 1 >/dev/null; printf '%s|%s|%s' \"\$RESULT\" \"\$MATH_FE_ERROR\" \"\${__MATH_FE_LINEMAX}\"
math.feStop")"
mapfile -t argv < "$TMP/w_noW/argv"
if [[ $out == "0.8414709848078965||" && ${#argv[@]} == 2 && ${argv[0]} == "-W interactive -f "* \
      && ${argv[1]} == "-f "* ]]; then
    kt_test_pass "starts: '${argv[0]}' then '${argv[1]}'"
else
    kt_test_fail "out='$out' starts=(${argv[*]})"
fi

# ---------------------------------------------------------------------------
# 3. A5 — a failed start says why
# ---------------------------------------------------------------------------
kt_test_start "no awk at all: rc 1 and MATH_FE_ERROR names it [L2.7-M A5]"
out="$(child "" "PATH=
math.feStart; printf 'rc=%s|%s' \"\$?\" \"\$MATH_FE_ERROR\"")"
if [[ $out == "rc=1|no awk: neither gawk nor awk is on PATH" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "an awk that dies at once: MATH_FE_ERROR names the awk and both tries, no program file is left [L2.7-M A5]"
# it dies on the process-substitution path too, so the start walks the
# fallback folders: TMPDIR, MATH_DIR (the unit's own folder!) and /tmp
mkdir -p "$TMP/pd"
out="$(TMPDIR="$TMP/pd" child "" "PATH='$TMP/w_dead'
math.feStart; printf 'rc=%s|%s|%s' \"\$?\" \"\$MATH_FE_ERROR\" \"\$\$\"")"
cpid=${out##*|}; out=${out%|*}
left=""
for d in "$TMP/pd" "$MATH_DIR" /tmp; do [[ -e $d/.math_fe_$cpid.awk ]] && left+=" $d/.math_fe_$cpid.awk"; done
want="rc=1|awk ($TMP/w_dead/awk) cannot run the engine: with -W interactive exited before answering; without it exited before answering"
if [[ $out == "$want" && -n $cpid && -z $left ]]; then
    kt_test_pass "${out#rc=1|}"
else
    kt_test_fail "got '$out' want '$want'; left:${left:- none}"
fi

kt_test_start "a silent awk (mawk without -W interactive): named, and bounded by the timeout [L2.7-M A5]"
t0=$SECONDS
out="$(KT019_TO=1 child "" "PATH='$TMP/w_silent'
math.feStart; printf 'rc=%s|%s' \"\$?\" \"\$MATH_FE_ERROR\"")"
dt=$(( SECONDS - t0 ))
want="rc=1|awk ($TMP/w_silent/awk) cannot run the engine: with -W interactive no answer within 1 s; without it no answer within 1 s"
if [[ $out == "$want" ]] && (( dt <= 8 )); then
    kt_test_pass "${out#rc=1|} (${dt}s)"
else
    kt_test_fail "got '$out' in ${dt}s; want '$want'"
fi

kt_test_start "the failed start prints one kk.debug line under VERBOSE_KKLASS=debug, nothing without [L2.7-M A5]"
dbg="$(child "unset VERBOSE_KKLASS" "VERBOSE_KKLASS=debug PATH=
math.feStart")"   # switched on after the source: kklass talks while loading
quiet="$(child "unset VERBOSE_KKLASS" "PATH=
math.feStart")"
if [[ $dbg == "math: float engine not started: no awk: neither gawk nor awk is on PATH" && -z $quiet ]]; then
    kt_test_pass "$dbg"
else
    kt_test_fail "debug='$dbg' quiet='$quiet'"
fi

# ---------------------------------------------------------------------------
# 4. C1b — under -W interactive a request longer than the line buffer is
#    refused at once; the engine stays in step
# ---------------------------------------------------------------------------
long=(); for ((i=0;i<300;i++)); do long+=(1.123456789012345); done      # ~5.4 KB
short=(); for ((i=0;i<200;i++)); do short+=(1.123456789012345); done    # ~3.6 KB
# The awk is a "mawk" (on Debian/Ubuntu the real one underneath). The timeout
# is long and the time bound short, and the engine must be the SAME process
# before and after (L2.7-M2 F1): without the guard, real mawk blocks on the
# long line until the 30 s timeout, gawk underneath answers it — both red.
kt_test_start "mawk engine: a 5.4 KB request is rc 1 at once, a 3.6 KB one answers, the engine stays in step [L2.7-M C1b, L2.7-M2 F1]"
t0=$SECONDS
out="$(KT019_TO=30 child "" "PATH='$TMP/w_fakemawk'
math.feStart; p0=\$__MATH_FE_PID
math.mean ${long[*]} >/dev/null; printf 'long=%s:%s|' \"\$?\" \"\$RESULT\"
math.mean ${short[*]} >/dev/null; printf 'short=%s:%s|' \"\$?\" \"\$RESULT\"
math.cos 0 >/dev/null; printf 'cos=%s|' \"\$RESULT\"
[[ -n \$p0 && \$p0 == \"\$__MATH_FE_PID\" ]] && printf 'same' || printf 'pid %s -> %s' \"\$p0\" \"\$__MATH_FE_PID\"
math.feStop")"
dt=$(( SECONDS - t0 ))
if [[ $out == "long=1:|short=0:1.12345678901234"*"|cos=1|same" ]] && (( dt <= 3 )); then
    kt_test_pass "$out (${dt}s)"
else
    kt_test_fail "got '$out' in ${dt}s"
fi

kt_test_start "gawk engine: the same 5.4 KB request answers (no line limit) [L2.7-M C1b]"
if [[ -z $HAVE_GAWK ]]; then
    kt_test_pass "N/A: no gawk on this system"
else
    out="$(child "" "math.mean ${long[*]} >/dev/null; printf '%s:%s' \"\$?\" \"\$RESULT\"
math.feStop")"
    if [[ $out == "0:1.12345678901234"* ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "got '$out'"
    fi
fi

# ---------------------------------------------------------------------------
# 5. N1 — non-finite inputs answer promptly, with the IEEE/FPC result, on
#    whichever awk runs the engine (each call is bounded: STRICT + 5 s)
# ---------------------------------------------------------------------------
NAN_ROWS='
r() { local want=$1; shift; RESULT="<unset>"; "$@" >/dev/null; [[ $RESULT == "$want" ]] || printf "[%s -> %s want %s] " "$*" "$RESULT" "$want"; }
r nan math.futureValue 0.05 nan -100 0 0
r nan math.futureValue 0.05 inf -100 0 0
r nan math.futureValue 0.05 -inf -100 0 1
r nan math.presentValue 0.05 nan -100 0
r nan math.presentValue 0.05 inf -100 0
r nan math.payment 0.05 nan 1000 0
r nan math.payment 0.05 inf 1000 0
r nan math.interestRate nan -100 1000 0
r nan math.interestRate inf -100 1000 0
r nan math.numberOfPeriods 0.05 -100 nan 0
r nan math.numberOfPeriods nan -100 1000 0
r nan math.tanh nan
r nan math.hypot 0 nan
r nan math.hypot nan 0
r nan math.logN 1 -1
r nan math.power 2 nan
r 1   math.power nan 0
r nan math.arcCot nan
r nan math.fmod 5 nan
r false math.isZero 0 nan
r false math.sameValue 1 1 nan
r -1  math.compareValue 1 2 nan
r 1   math.compareValue nan 1 0.5
r 1   math.compareValue 1 nan 0.5
r 3.1415926535897931 math.arcTan2 0 -0
r 3.1415926535897931 math.arcTan2 0 -0.0
r 3.1415926535897931 math.arcTan2 0 -.0
r 3.1415926535897931 math.arcTan2 0 -0.
r 3.1415926535897931 math.arcTan2 0 -0e0
r 3.1415926535897931 math.arcTan2 0 -00
r 0   math.ldexp 1 -9223372036854775808
r inf math.ldexp 1 9223372036854775807
r -inf math.ldexp -1 9223372036854775807
math.feActive >/dev/null || printf "[engine down at the end]"
math.feStop'
_nan_row() {   # TITLE PRE
    kt_test_start "non-finite inputs answer promptly with nan/false/... on $1 [L2.7-M N1]"
    local t0=$SECONDS out dt
    out="$(child "$2" "$3
$NAN_ROWS")"
    dt=$(( SECONDS - t0 ))
    if [[ -z $out ]] && (( dt <= 20 )); then
        kt_test_pass "33 rows (${dt}s)"
    else
        kt_test_fail "${out:0:600} (${dt}s)"
    fi
}
_nan_row "the default engine" "" ""
_nan_row "an engine reached as plain awk (-W interactive first)" "" "PATH='$TMP/w_plain'"
_nan_row "a mawk engine (fakemawk wrapper)" "" "PATH='$TMP/w_fakemawk'"

# ---------------------------------------------------------------------------
# 6. L2.7-M2 — the co-process is the awk; IFS; no retry after a failed start
# ---------------------------------------------------------------------------
kt_test_start "the engine pid is the awk itself, and feStop leaves no awk behind [L2.7-M2 P1]"
out="$(child "" "math.feStart; p=\$__MATH_FE_PID
if [[ -r /proc/\$p/cmdline ]]; then
    IFS= read -r -d '' a0 < /proc/\$p/cmdline; printf 'argv0=%s|' \"\${a0##*/}\"
else
    printf 'argv0=N/A|'
fi
math.feStop
kill -0 \"\$p\" 2>/dev/null && printf 'alive' || printf 'gone'")"
case $out in
    "argv0=N/A|gone")                    kt_test_pass "N/A: no /proc here; the pid is gone after feStop" ;;
    argv0=*awk"|gone"|argv0=*awk.exe"|gone") kt_test_pass "$out" ;;
    *)                                   kt_test_fail "got '$out'" ;;
esac

kt_test_start "the request is joined with a space whatever IFS the caller has [L2.7-M2 F6]"
out="$(child "" "IFS=,
math.hypot 3 4 >/dev/null; printf '%s|' \"\$RESULT\"
math.mean 1 2 3 >/dev/null; printf '%s' \"\$RESULT\"
math.feStop")"
if [[ $out == "5|2" ]]; then kt_test_pass "$out"; else kt_test_fail "got '$out'"; fi

kt_test_start "after a failed start a Tier-B call does not retry; math.feStart does and clears MATH_FE_ERROR [L2.7-M2 F8/F10]"
t0=$SECONDS
out="$(child "" "op=\$PATH; PATH=
math.feStart; printf 'start=%s|' \"\$?\"
PATH=\$op
math.sin 1 >/dev/null; printf 'sin=%s:%s|' \"\$?\" \"\$RESULT\"
math.feActive >/dev/null; printf 'active=%s|err=%s|' \"\$RESULT\" \"\$MATH_FE_ERROR\"
math.feStart; printf 'start=%s|err=%s|' \"\$?\" \"\$MATH_FE_ERROR\"
math.sin 1 >/dev/null; printf 'sin=%s:%s' \"\$?\" \"\$RESULT\"
math.feStop")"
dt=$(( SECONDS - t0 ))
want="start=1|sin=1:|active=false|err=no awk: neither gawk nor awk is on PATH|start=0|err=|sin=0:0.8414709848078965"
if [[ $out == "$want" ]] && (( dt <= 8 )); then
    kt_test_pass "$out (${dt}s)"
else
    kt_test_fail "got '$out' in ${dt}s; want '$want'"
fi
