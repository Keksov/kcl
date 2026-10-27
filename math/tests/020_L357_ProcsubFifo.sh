#!/usr/bin/env bash
# L3.5-7 (launch plan, 2026-10-27) — an engine start leaves no
# process-substitution FIFO behind.
#
# The program reaches awk through `<(printf …)`, opened by the co-process's
# own shell, which then `exec`s the awk (L3.5, PORTING H44). Where `<( )` is a
# FIFO in TMPDIR (FreeBSD's pkg bash, `sh-np.XXXXXX`) bash unlinks it only
# after its writer ended — never, in a shell that `exec`ed: every spawn
# attempt left one `sh-np.*` (2 per start where the awk rejects -W, ledger
# L3.5-a-o5). math._fe_pfopen now unlinks such a FIFO right after its open.
# N/A where `<( )` is /dev/fd: the same checks run, nothing can be left.
#
# The children run with a private TMPDIR. The kind of `<( )` is read by
# OPENING the path — a bare `echo <(:)` would leave the writer blocked in
# open() for ever on a FIFO bash.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "L357ProcsubFifo" "$SCRIPT_DIR" "$@"

MATH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$MATH_DIR/math.sh"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt020_kind() { KT020_PS="$1"; : < "$1"; }
kt020_kind <(:)
if [[ $KT020_PS == /dev/fd/* ]]; then NA=" (N/A: <( ) is $KT020_PS)"; else NA=" (<( ) is a FIFO: ${KT020_PS##*/})"; fi

REAL_AWK="$(command -v awk)"
RM="$(command -v rm)"
# a line-wise awk without any flag (as in 019): gawk, else mawk with
# -W interactive, else the system awk as it is (BWK, busybox)
real_id="$(LC_ALL=C "$REAL_AWK" -W version </dev/null 2>&1)"; real_id=${real_id%%$'\n'*}
if command -v gawk >/dev/null 2>&1; then LINEWISE="\"$(command -v gawk)\""
elif [[ $real_id == mawk* ]]; then LINEWISE="\"$REAL_AWK\" -W interactive"
else LINEWISE="\"$REAL_AWK\""; fi
# an awk that rejects -W (the start then spawns twice), alone on its PATH with
# `rm` (the unlink of a FIFO; the fallback's own file)
W="$TMP/w_noW"
mkdir -p "$W"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/argv"\n[ "$1" = -W ] && exit 2\nexec %s "$@"\n' "$W" "$LINEWISE" > "$W/awk"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$RM" > "$W/rm"
chmod +x "$W/awk" "$W/rm"

# run TMPDIR PRE — a bounded child: PRE, the unit, then 3 x (feStart, a call,
# the sh-np.* entries of TMPDIR while the engine runs, feStop); prints
# "RESULTS|ENTRIES_WHILE_UP"
run() {
    mkdir -p "$1"
    TMPDIR="$1" timeout -k 5 60 "$BASH" -c "$2
source '$UNIT'
__MATH_FE_TIMEOUT=5
r='' m=''
for i in 1 2 3; do
    math.feStart
    math.sin 1 >/dev/null; r+=\" \$RESULT\"
    for f in \"\$TMPDIR\"/sh-np.*; do [[ -e \$f || -p \$f ]] && m+=\" \${f##*/}\"; done
    math.feStop
done
printf '%s|%s' \"\$r\" \"\$m\"" 2>&1
}
# fifos DIR — the sh-np.* entries of DIR into F; rc 0 = none
fifos() { local f; F=""; for f in "$1"/sh-np.*; do [[ -e $f || -p $f ]] && F+=" ${f##*/}"; done; [[ -z $F ]]; }
want=" 0.8414709848078965 0.8414709848078965 0.8414709848078965|"

kt_test_start "feStart + a call + feStop, 3 times: no sh-np.* in TMPDIR while the engine runs or after [L3.5-7]"
out="$(run "$TMP/t1" "")"
if [[ $out == "$want" ]] && fifos "$TMP/t1"; then
    kt_test_pass "3 starts, nothing left$NA"
else
    fifos "$TMP/t1" || :
    kt_test_fail "out='$out' left='$F' ls='$(ls -A "$TMP/t1" | tr '\n' ' ')'$NA"
fi

kt_test_start "an awk that rejects -W (two spawn attempts per start, like BWK awk): 3 starts leave no sh-np.* [L3.5-7, L3.5-a-o5]"
out="$(run "$TMP/t2" "PATH='$W'")"
spawns=$(grep -c . "$W/argv" 2>/dev/null) || :
if [[ $out == "$want" && $spawns == 6 ]] && fifos "$TMP/t2"; then
    kt_test_pass "3 starts, $spawns spawns, nothing left$NA"
else
    fifos "$TMP/t2" || :
    kt_test_fail "out='$out' spawns=$spawns left='$F' ls='$(ls -A "$TMP/t2" | tr '\n' ' ')'$NA"
fi
