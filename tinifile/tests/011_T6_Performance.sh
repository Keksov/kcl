#!/bin/bash
# 011_T6_Performance.sh - review 2026-09-06, phase P8, finding T6.
#
# Key lookup used to call a helper FUNCTION per candidate row and to walk the
# rows of EVERY section, and WriteString learned the index of a freshly
# appended row by materialising `"${!arr[@]}"` - so appending N keys cost
# O(N^2) (200/400/800 appends measured at 3.96 / 8.34 / 16.4 ms per write) and
# a read in the 20th section cost 3.3x a read in the first.
#
# The gates are RELATIVE (PLAN.md section 4: "perf walls are closed by relative
# gates, not by milliseconds"), so they survive a slower or busier machine:
#   * 800 appends take less than 10x the time of 200 appends (a quadratic cost
#     is 16x by construction; a linear one is 4x);
#   * a lookup in section 20 of a 20x50 file costs less than 3x a lookup in
#     section 1.
# Both are measured in the same process, back to back, so only the shape of the
# curve matters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

kt_test_init "011_T6_Performance" "$SCRIPT_DIR" "$@"

kt_test_section "011: lookup and append cost (T6)"

D="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# Microseconds since the epoch, decimal separator agnostic (D6: a bare
# environment can leave EPOCHREALTIME with a comma).
now_us() { local t="${EPOCHREALTIME}"; printf '%s' "${t/[.,]/}"; }

append_ms() {   # N -> elapsed microseconds for N cached appends
    local n="$1" i t0 t1
    TMemIniFile.new PERF "$D/perf$n.ini"
    t0=$(now_us)
    for (( i = 0; i < n; i++ )); do PERF.WriteString s "key$i" "v$i"; done
    t1=$(now_us)
    PERF.dirty = "false"; PERF.delete
    printf '%s' $(( t1 - t0 ))
}

# The suite runner starts eight files in parallel, so a single measurement can
# be inflated by a neighbour. Both sizes are measured three times, alternating,
# and the BEST of each is compared: contention can only make a run slower, so
# the minimum is the closest thing to the cost of the code itself.
kt_test_start "T6: 800 cached appends cost less than 10x 200 cached appends"
small=0; big=0
for rep in 1 2 3; do
    v=$(append_ms 200); if (( small == 0 || v < small )); then small=$v; fi
    v=$(append_ms 800); if (( big   == 0 || v < big   )); then big=$v;   fi
done
# integer ratio in tenths, guarding against a zero baseline on a fast box
(( small < 1 )) && small=1
ratio10=$(( big * 10 / small ))
if (( ratio10 < 100 )); then
    kt_test_pass "best-of-3: 200 appends ${small} us, 800 appends ${big} us -> ${ratio10}/10x (< 10x)"
else
    kt_test_fail "quadratic: 200 appends ${small} us, 800 appends ${big} us -> ${ratio10}/10x"
fi

# The two structural halves of the finding, asserted directly on the bodies so
# that a later edit cannot quietly bring either cost back while the timings stay
# inside the (deliberately generous) relative walls.
kt_test_start "T6: _findKey calls no helper per row and does not walk every row"
body="$(declare -f TIniFile._findKey)"
bad=""
[[ "$body" == *"TIniFile._norm"* ]] && bad+="[calls _norm per row] "
[[ "$body" == *'${!__tif_ki[@]}'* ]] && bad+="[iterates the whole ident table] "
[[ "$body" == *'${!__tif_ko[@]}'* ]] && bad+="[iterates the whole owner table] "
[[ -z "$bad" ]] && kt_test_pass "per-section row list, inline comparison" || kt_test_fail "$bad"

kt_test_start "T6: a read in section 20 costs less than 3x a read in section 1"
{
    for (( s = 1; s <= 20; s++ )); do
        printf '[sec%d]\n' "$s"
        for (( k = 1; k <= 50; k++ )); do printf 'k%d=v%d_%d\n' "$k" "$s" "$k"; done
    done
} > "$D/big.ini"
TMemIniFile.new B "$D/big.ini"
read_us() {   # SECTION -> microseconds for 50 lookups of its last key
    local sec="$1" i t0 t1
    t0=$(now_us)
    for (( i = 0; i < 50; i++ )); do B.ReadString "$sec" k50 X >/dev/null; done
    t1=$(now_us)
    printf '%s' $(( t1 - t0 ))
}
B.ReadString sec1 k50 X          # warm-up, and a correctness anchor below
first=0; last=0
for rep in 1 2 3; do
    v=$(read_us sec1);  if (( first == 0 || v < first )); then first=$v; fi
    v=$(read_us sec20); if (( last  == 0 || v < last  )); then last=$v;  fi
done
(( first < 1 )) && first=1
pos10=$(( last * 10 / first ))
if (( pos10 < 30 )); then
    kt_test_pass "best-of-3: sec1 ${first} us / 50 reads, sec20 ${last} us -> ${pos10}/10x (< 3x)"
else
    kt_test_fail "position-dependent: sec1 ${first} us, sec20 ${last} us -> ${pos10}/10x"
fi

kt_test_start "T6: the faster lookup still returns the right values"
B.ReadString sec1 k50 X;  a="$RESULT"
B.ReadString sec20 k50 X; b="$RESULT"
B.ReadString sec20 k1 X;  c="$RESULT"
B.ReadString sec20 nope DEF; d="$RESULT"
if [[ "$a" == "v1_50" && "$b" == "v20_50" && "$c" == "v20_1" && "$d" == "DEF" ]]; then
    kt_test_pass "first/last/miss all correct"
else
    kt_test_fail "sec1.k50='$a' sec20.k50='$b' sec20.k1='$c' miss='$d'"
fi
B.delete

kt_test_start "T6: appends after a DELETION still land in the right section"
# The append path now tracks the next free row itself; a hole in the middle
# must not make it overwrite a live row.
TMemIniFile.new H "$D/h.ini"
H.WriteString a k1 1; H.WriteString a k2 2; H.WriteString b k3 3
H.DeleteKey a k1
H.WriteString a k4 4
H.WriteString b k5 5
KA=(); H.ReadSection a KA
KB=(); H.ReadSection b KB
ja=""; for x in "${KA[@]}"; do ja+="[$x]"; done
jb=""; for x in "${KB[@]}"; do jb+="[$x]"; done
H.ReadString a k2 X; v2="$RESULT"
H.ReadString a k4 X; v4="$RESULT"
H.ReadString b k5 X; v5="$RESULT"
if [[ "$ja" == "[k2][k4]" && "$jb" == "[k3][k5]" && "$v2" == "2" && "$v4" == "4" && "$v5" == "5" ]]; then
    kt_test_pass "holes respected: a=$ja b=$jb"
else
    kt_test_fail "a=$ja b=$jb k2='$v2' k4='$v4' k5='$v5'"
fi
H.dirty = "false"; H.delete

kt_test_start "T6: EraseSection then a re-add reuses neither rows nor slots wrongly"
TMemIniFile.new E "$D/e.ini"
E.WriteString a k 1; E.WriteString b k 2
E.EraseSection a
E.WriteString a k 3
E.WriteString b k2 4
E.UpdateFile
body="$(cat "$D/e.ini")"
E.ReadString a k X;  x="$RESULT"
E.ReadString b k X;  y="$RESULT"
E.ReadString b k2 X; z="$RESULT"
if [[ "$body" == $'[b]\nk=2\nk2=4\n\n[a]\nk=3' && "$x" == "3" && "$y" == "2" && "$z" == "4" ]]; then
    kt_test_pass "compose and lookups agree after an erase"
else
    kt_test_fail "file='${body//$'\n'/\\n}' a.k='$x' b.k='$y' b.k2='$z'"
fi
E.delete

kt_test_start "T6: a 800-key instance still composes and reloads intact"
TMemIniFile.new F "$D/f.ini"
for (( i = 0; i < 800; i++ )); do F.WriteString "s$(( i / 100 ))" "key$i" "v$i"; done
F.UpdateFile
F.delete
TMemIniFile.new G "$D/f.ini"
G.ReadString s0 key0 X;     a="$RESULT"
G.ReadString s7 key799 X;   b="$RESULT"
S=(); G.ReadSections S
K=(); G.ReadSection s7 K
if [[ "$a" == "v0" && "$b" == "v799" && ${#S[@]} -eq 8 && ${#K[@]} -eq 100 ]]; then
    kt_test_pass "800 keys / 8 sections round-tripped"
else
    kt_test_fail "first='$a' last='$b' sections=${#S[@]} s7keys=${#K[@]}"
fi
G.delete

kt_test_log "011_T6_Performance.sh completed"
