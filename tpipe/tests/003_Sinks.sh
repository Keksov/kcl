#!/bin/bash
# 003_Sinks.sh — tpipe P1: toArray / toList / first / count and the -0 / -c flags.
#
# No upstream: TPipe is a kcl addition (PLAN.md §1.2). The oracle is bash
# itself — every sink is compared with what a bare `mapfile` / `head -n1` /
# `wc -l` / `while read` over the SAME producer would give.
#
# Pinned facts (PLAN.md §3), by section:
#   A      toArray vs a bare `mapfile` oracle; the array is REPLACED; the exotic
#          matrix byte-exact; F8 (mapfile delivers an unterminated last record
#          on both bashes) and the final-empty-record rule
#   B  F15 toArray refuses an ASSOCIATIVE or READONLY target with rc 2 and NO
#          stderr (mapfile into either prints a bash diagnostic and returns 1)
#      F14 every rc 2 path runs NOTHING: the producer never starts and stdin is
#          left fully readable
#   C      toList vs a `while read` oracle, through a kklass class AND a real
#          TStringList; a REJECTING `.Add` (THashSet duplicates) neither aborts
#          under `set -e` nor miscounts — RESULT counts records OFFERED
#   D      first vs `head -n1`: one record, the stop path, RESULT '' + rc 1 on an
#          empty producer, an unterminated single record. F4/F5 in the `first`
#          shape live in 002_Stop.sh, next to their each+stop twins.
#   E      count vs `wc -l`, including the unterminated tail
#   F  F7  -0 with `find -print0` over names containing a space and a NEWLINE
#      F11 the delimiter survives IFS=':' (it is passed as a VALUE)
#      -c  strips EXACTLY one trailing CR, through every sink
#   G  F16 the producer inherits the CALLER's stdin (`-- cat` with `<<<`)
#   H      the rc 1 + non-empty RESULT deviation (PLAN §2.4) for the new sinks
#   I      nesting: a toArray inside an `each` callback; the outer keeps counting
#   J      the P0 `tpipe._pending` stub is GONE: no member answers the sentinel
#          and a valid call to each of the four is silent under
#          VERBOSE_KKLASS=debug
#   K      zero forks per record
#
# Producers on the stop path (`first`, and `toList` with a stopping `.Add`) get
# `2>/dev/null`: a closed pipe routinely makes them print "write error: Broken
# pipe", which is the PRODUCER's stderr, not TPipe's (PLAN §4).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$SCRIPT_DIR/.."
source "$TP_DIR/tpipe.sh"
source "$TP_DIR/../tstringlist/tstringlist.sh"
source "$TP_DIR/../thashset/thashset.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "003: the four collecting sinks + the -0 / -c flags (P1)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# arr_is ARRNAME expected... — rc 0 iff the array holds exactly these elements
# in this order. Fork-free and byte-exact, so exotic records compare correctly.
arr_is() {
    local -n __a="$1"; shift
    local __i=0 __e
    if (( ${#__a[@]} != $# )); then
        return 1
    fi
    for __e in "$@"; do
        if [[ "${__a[$__i]}" != "$__e" ]]; then
            return 1
        fi
        __i=$(( __i + 1 ))
    done
    return 0
}

# arr_eq A B — rc 0 iff the two named arrays are element-for-element identical.
arr_eq() {
    local -n __x="$1"
    local -n __y="$2"
    local __i
    if (( ${#__x[@]} != ${#__y[@]} )); then
        return 1
    fi
    for (( __i = 0; __i < ${#__x[@]}; __i++ )); do
        if [[ "${__x[$__i]}" != "${__y[$__i]}" ]]; then
            return 1
        fi
    done
    return 0
}

# producers
p3()     { printf 'a\nb\nc\n'; }
p4()     { printf 'a\nb\nc\nd\n'; }
pfail6() { printf 'a\nb\n'; return 6; }
pcr()    { printf 'x\r\r\ny\r\nz\n'; }
pz()     { printf 'a\0b\0'; }
pzc()    { printf 'x\r\r\0y\r\0'; }
# a producer whose OWN stderr is discarded, for the "TPipe says nothing" cases
# that also take the stop path (§J)
p3q()    { p3 2>/dev/null; }
STARTED="$TMP/started.flag"
pmark()  { : > "$STARTED"; printf 'a\n'; }
# one line per record carrying the PRODUCER's own pid (the zero-fork probe)
ppid5()  { local __i; for __i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }

noop_cb_003() { return 0; }

# the exotic matrix — records are DATA and must round-trip byte-exact.
# NUL is the documented carve-out (no bash variable can hold one).
printf -v BIG64 '%0*d' 65536 7
EXOTIC=( "" "-e" "-n" "-neE" 'back\slash' '$(echo pwned)' '`id`' "*" "]" \
         "a b" $'ta\tb' $'cr\r' "café" "日本語" "$BIG64" )
pexotic() { printf '%s\n' "${EXOTIC[@]}"; }

# a kklass collector whose Add appends to a global array (the duck-typed
# `.Add` contract toList relies on)
LADD=()
class TCollector
    public
        var         N
        constructor Create
        proc        Add
end
TCollector.Create() { N=0; return 0; }
TCollector.Add()    { LADD+=( "$1" ); N=$(( N + 1 )); return 0; }
build TCollector

# a collector whose Add stops the sink on the 2nd record (a stop from inside
# `.Add` is legal)
SADD=()
class TStopper
    public
        var         N
        constructor Create
        proc        Add
end
TStopper.Create() { N=0; return 0; }
TStopper.Add()    {
    SADD+=( "$1" )
    N=$(( N + 1 ))
    if (( N == 2 )); then
        TPipe.stop
    fi
    return 0
}
build TStopper

# a class without an Add member at all (the rc 2 operand path)
class TNoAdd
    public
        constructor Create
        proc        Push
end
TNoAdd.Create() { return 0; }
TNoAdd.Push()   { return 0; }
build TNoAdd

# a collector whose Add runs a NESTED toArray (§I)
NADD=()
NEST_ARR=()
class TNest
    public
        constructor Create
        proc        Add
end
TNest.Create() { return 0; }
TNest.Add()    {
    NADD+=( "$1" )
    TPipe.toArray NEST_ARR -- printf '%s-1\n%s-2\n' "$1" "$1"
    NADD+=( "inner=$RESULT" )
    return 0
}
build TNest

# a collector that records the pid its Add runs in (§K)
FORKPIDS=()
class TForkProbe
    public
        constructor Create
        proc        Add
end
TForkProbe.Create() { return 0; }
TForkProbe.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TForkProbe

# ===========================================================================
kt_test_section "A. toArray vs a bare mapfile"
# ===========================================================================

kt_test_start "toArray fills the caller array and RESULT is the element count"
GOT=(); RESULT="sentinel"
TPipe.toArray GOT -- p3; rc=$?
res="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 ]] && arr_is GOT "a" "b" "c"; then
    kt_test_pass "3 elements, rc 0"
else
    kt_test_fail "RESULT='$res' rc=$rc GOT=(${GOT[*]})"
fi

kt_test_start "toArray equals a bare \`mapfile\` over the same producer (exotic matrix)"
ORACLE=()
exec {ofd}< <(pexotic)
mapfile -t -u "$ofd" ORACLE
exec {ofd}<&-
GOT=()
TPipe.toArray GOT -- pexotic; rc=$?
if [[ "$RESULT" == "${#EXOTIC[@]}" && $rc -eq 0 ]] && arr_eq GOT ORACLE && arr_is GOT "${EXOTIC[@]}"; then
    kt_test_pass "${#EXOTIC[@]} records byte-exact, identical to mapfile (64 KiB record included)"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc got=${#GOT[@]} oracle=${#ORACLE[@]}"
fi

kt_test_start "the 64 KiB record survives toArray byte-exact"
GOT=()
TPipe.toArray GOT -- printf '%s\n' "$BIG64"
if [[ "$RESULT" == "1" && "${#GOT[0]}" == "65536" && "${GOT[0]}" == "$BIG64" ]]; then
    kt_test_pass "65536 characters verbatim"
else
    kt_test_fail "RESULT='$RESULT' len=${#GOT[0]}"
fi

kt_test_start "the target array is REPLACED, not appended to (mapfile clears it)"
GOT=( old1 old2 old3 old4 old5 )
TPipe.toArray GOT -- p3
if [[ "$RESULT" == "3" ]] && arr_is GOT "a" "b" "c"; then
    kt_test_pass "the five old elements are gone"
else
    kt_test_fail "RESULT='$RESULT' GOT=(${GOT[*]})"
fi

kt_test_start "an EMPTY producer empties the target array: RESULT 0, rc 0"
GOT=( old1 old2 )
TPipe.toArray GOT -- printf ''; rc=$?
if [[ "$RESULT" == "0" && $rc -eq 0 && "${#GOT[@]}" == "0" ]]; then
    kt_test_pass "0 elements, rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc count=${#GOT[@]}"
fi

kt_test_start "F8: mapfile delivers an unterminated last record (printf 'a\\nb')"
GOT=()
TPipe.toArray GOT -- printf 'a\nb'; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 ]] && arr_is GOT "a" "b"; then
    kt_test_pass "2 elements, the tail without a terminator included"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc GOT=(${GOT[*]})"
fi

kt_test_start "a final EMPTY record after the terminator is delivered (printf 'a\\n\\n')"
GOT=()
TPipe.toArray GOT -- printf 'a\n\n'
if [[ "$RESULT" == "2" ]] && arr_is GOT "a" ""; then
    kt_test_pass "2 elements, the second empty"
else
    kt_test_fail "RESULT='$RESULT' GOT=(${GOT[*]})"
fi

kt_test_start "toArray converts an existing SCALAR target into the output array"
SCAL="i am a scalar"
TPipe.toArray SCAL -- p3
if [[ "$RESULT" == "3" ]] && arr_is SCAL "a" "b" "c"; then
    kt_test_pass "the scalar became a 3-element array"
else
    kt_test_fail "RESULT='$RESULT' SCAL=$(declare -p SCAL 2>&1)"
fi
unset SCAL

kt_test_start "toArray accepts a declared-but-unset array and a brand new name"
declare -a DECLONLY
unset BRANDNEW_003
TPipe.toArray DECLONLY -- p3; r1="$RESULT"
TPipe.toArray BRANDNEW_003 -- p3; r2="$RESULT"
if [[ "$r1" == "3" && "$r2" == "3" ]] && arr_is DECLONLY "a" "b" "c" && arr_is BRANDNEW_003 "a" "b" "c"; then
    kt_test_pass "both filled with 3 elements"
else
    kt_test_fail "declonly=$r1 (${DECLONLY[*]}) brandnew=$r2 (${BRANDNEW_003[*]})"
fi

kt_test_start "the stdin form of toArray works outside a subshell"
GOT=()
TPipe.toArray GOT <<< $'x\ny\nz'; rc=$?
if [[ "$RESULT" == "3" && $rc -eq 0 ]] && arr_is GOT "x" "y" "z"; then
    kt_test_pass "3 records from a here-string"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc GOT=(${GOT[*]})"
fi

kt_test_start "after a stdin-form toArray lastRc is -1 (there was no producer of ours)"
TPipe.toArray GOT -- p3          # lastRc 0 going in
TPipe.toArray GOT <<< $'x\ny'
TPipe.lastRc; lr="$RESULT"
if [[ "$lr" == "-1" ]]; then
    kt_test_pass "lastRc reset to -1"
else
    kt_test_fail "lastRc='$lr'"
fi

# ===========================================================================
kt_test_section "B. F15 / F14 — toArray refuses a target it cannot fill"
# ===========================================================================

declare -A ASSOC_T=( [k]=1 )
declare -ra RO_ARR_T=( 1 2 )
declare -r  RO_SCAL_T="frozen"

kt_test_start "F15: an ASSOCIATIVE target is rc 2, RESULT='', NO stderr, storage untouched"
ERRF="$TMP/f15a.err"
: > "$ERRF"
RESULT="sentinel"
TPipe.toArray ASSOC_T -- p3 2>"$ERRF"; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -s "$ERRF" \
      && "${#ASSOC_T[@]}" == "1" && "${ASSOC_T[k]}" == "1" ]]; then
    kt_test_pass "rc 2, silent, the associative array is intact"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' err='$(cat "$ERRF")' assoc=$(declare -p ASSOC_T 2>&1)"
fi

kt_test_start "F15: a READONLY array target is rc 2, RESULT='', NO stderr"
: > "$ERRF"
RESULT="sentinel"
TPipe.toArray RO_ARR_T -- p3 2>"$ERRF"; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -s "$ERRF" ]] && arr_is RO_ARR_T "1" "2"; then
    kt_test_pass "rc 2, silent, the readonly array is intact"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' err='$(cat "$ERRF")'"
fi

kt_test_start "F15: a READONLY scalar target is rc 2, RESULT='', NO stderr"
: > "$ERRF"
RESULT="sentinel"
TPipe.toArray RO_SCAL_T -- p3 2>"$ERRF"; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -s "$ERRF" && "$RO_SCAL_T" == "frozen" ]]; then
    kt_test_pass "rc 2, silent, the readonly scalar is intact"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' err='$(cat "$ERRF")'"
fi

kt_test_start "F15: an INTEGER-attributed target is rc 2, RESULT='', NO stderr, value intact"
: > "$ERRF"
declare -i INT_T=0
RESULT="sentinel"
TPipe.toArray INT_T -- printf 'abc\ndef\n' 2>"$ERRF"; rc=$?
intdecl="$(declare -p INT_T 2>&1)"
if [[ $rc -eq 2 && -z "$RESULT" && ! -s "$ERRF" && "$intdecl" == "declare -i INT_T="* ]]; then
    kt_test_pass "rc 2, silent; mapfile would have made it declare -ai with EVERY record evaluated to 0"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' err='$(cat "$ERRF")' INT_T=$intdecl"
fi

kt_test_start "a malformed or RESERVED output name is rc 2 (kk._outName + the unit's own prefixes)"
bad_ok=1
bad_detail=""
for badname in "" "1bad" "has space" "has-dash" "RESULT" "REPLY" "IFS" "state" \
               "this" "__inst__" "__class__" "__kk_x" "__KK_X" \
               "__tpi_line" "__TPIPE_RC" "TPIPE_INDEX"; do
    RESULT="sentinel"
    TPipe.toArray "$badname" -- p3 2>/dev/null; brc=$?
    if [[ $brc -ne 2 || -n "$RESULT" ]]; then
        bad_ok=0
        bad_detail="$bad_detail '$badname'->rc$brc/RESULT='$RESULT'"
    fi
done
if (( bad_ok )); then
    kt_test_pass "all 16 reserved/malformed names answered rc 2 with RESULT=''"
else
    kt_test_fail "accepted:$bad_detail"
fi

kt_test_start "F14: a rc 2 toArray never starts the producer and leaves stdin FULLY readable"
rm -f "$STARTED"
l1=""; l2=""; l3=""; rc=99
{
    TPipe.toArray ASSOC_T -- pmark 2>/dev/null; rc=$?
    IFS= read -r l1
    IFS= read -r l2
    IFS= read -r l3 || :
} <<< $'p\nq\nr'
if [[ $rc -eq 2 && ! -e "$STARTED" && "$l1" == "p" && "$l2" == "q" && "$l3" == "r" ]]; then
    kt_test_pass "rc 2, producer never ran, all three stdin lines still there"
else
    kt_test_fail "rc=$rc started=$( [[ -e "$STARTED" ]] && echo yes || echo no ) lines='$l1/$l2/$l3'"
fi

kt_test_start "F14: the same for toList, first and count (bad operand / bad flag)"
rm -f "$STARTED"
f14ok=1
f14detail=""
l1=""; l2=""; l3=""; rc1=0; rc2=0; rc3=0
{
    TPipe.toList tpipe_no_such_inst_003 -- pmark 2>/dev/null || rc1=$?
    IFS= read -r l1
    TPipe.first -x -- pmark 2>/dev/null || rc2=$?
    IFS= read -r l2
    TPipe.count -x -- pmark 2>/dev/null || rc3=$?
    IFS= read -r l3 || :
} <<< $'p\nq\nr'
if [[ "$rc1" != "2" || "$rc2" != "2" || "$rc3" != "2" ]]; then
    f14ok=0; f14detail="rc=$rc1/$rc2/$rc3"
fi
if [[ "$l1" != "p" || "$l2" != "q" || "$l3" != "r" ]]; then
    f14ok=0; f14detail="$f14detail lines='$l1/$l2/$l3'"
fi
if [[ -e "$STARTED" ]]; then
    f14ok=0; f14detail="$f14detail producer-ran"
fi
if (( f14ok )); then
    kt_test_pass "three rc 2 paths, no producer, stdin consumed only by the reads"
else
    kt_test_fail "$f14detail"
fi

kt_test_start "a flag written AFTER the operand is rc 2 for toArray and toList"
GOT=(); RESULT="sentinel"
TPipe.toArray GOT -c -- p3 2>/dev/null; rc=$?
res1="$RESULT"
TCollector.new CBAD
RESULT="sentinel"
TPipe.toList CBAD -c -- p3 2>/dev/null; rc2=$?
res2="$RESULT"
CBAD.delete
if [[ $rc -eq 2 && -z "$res1" && $rc2 -eq 2 && -z "$res2" ]]; then
    kt_test_pass "the late flag is caught, not taken as the producer"
else
    kt_test_fail "toArray rc=$rc RESULT='$res1' / toList rc=$rc2 RESULT='$res2'"
fi

kt_test_start "\`--\` with an EMPTY producer argv is rc 2 for all four sinks"
empty_ok=1
empty_detail=""
TCollector.new CEMPTY
GOT=(); RESULT="sentinel"; TPipe.toArray GOT -- 2>/dev/null <<< $'a\nb'; erc=$?
if [[ $erc -ne 2 || -n "$RESULT" ]]; then empty_ok=0; empty_detail="toArray:$erc/'$RESULT'"; fi
RESULT="sentinel"; TPipe.toList CEMPTY -- 2>/dev/null <<< $'a\nb'; erc=$?
if [[ $erc -ne 2 || -n "$RESULT" ]]; then empty_ok=0; empty_detail="$empty_detail toList:$erc/'$RESULT'"; fi
RESULT="sentinel"; TPipe.first -- 2>/dev/null <<< $'a\nb'; erc=$?
if [[ $erc -ne 2 || -n "$RESULT" ]]; then empty_ok=0; empty_detail="$empty_detail first:$erc/'$RESULT'"; fi
RESULT="sentinel"; TPipe.count -- 2>/dev/null <<< $'a\nb'; erc=$?
if [[ $erc -ne 2 || -n "$RESULT" ]]; then empty_ok=0; empty_detail="$empty_detail count:$erc/'$RESULT'"; fi
CEMPTY.delete
if (( empty_ok )); then
    kt_test_pass "all four answer rc 2, not 'read stdin'"
else
    kt_test_fail "$empty_detail"
fi

kt_test_start "a missing operand is rc 2 for toArray and toList (first/count take none)"
RESULT="sentinel"
TPipe.toArray 2>/dev/null; rc=$?
res1="$RESULT"
RESULT="sentinel"
TPipe.toList 2>/dev/null; rc2=$?
res2="$RESULT"
if [[ $rc -eq 2 && -z "$res1" && $rc2 -eq 2 && -z "$res2" ]]; then
    kt_test_pass "rc 2, RESULT=''"
else
    kt_test_fail "toArray rc=$rc RESULT='$res1' / toList rc=$rc2 RESULT='$res2'"
fi

# ===========================================================================
kt_test_section "C. toList — records OFFERED to INST.Add"
# ===========================================================================

kt_test_start "toList calls INST.Add once per record; RESULT is the number offered"
TCollector.new C1
LADD=(); RESULT="sentinel"
TPipe.toList C1 -- p3; rc=$?
if [[ "$RESULT" == "3" && $rc -eq 0 && "$(C1.N)" == "3" ]] && arr_is LADD "a" "b" "c"; then
    kt_test_pass "3 records offered and stored, rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc N='$(C1.N)' LADD=(${LADD[*]})"
fi
C1.delete

kt_test_start "toList equals a bare \`while read\` oracle on the exotic matrix (byte-exact)"
ORACLE=()
while IFS= read -r ln || [[ -n "$ln" ]]; do ORACLE+=( "$ln" ); done < <(pexotic)
TCollector.new C2
LADD=()
TPipe.toList C2 -- pexotic
if [[ "$RESULT" == "${#EXOTIC[@]}" ]] && arr_eq LADD ORACLE && arr_is LADD "${EXOTIC[@]}"; then
    kt_test_pass "${#EXOTIC[@]} records identical to the read-loop oracle"
else
    kt_test_fail "RESULT='$RESULT' got=${#LADD[@]} oracle=${#ORACLE[@]}"
fi
C2.delete

kt_test_start "toList into a real TStringList round-trips the exotic matrix byte-exact"
TStringList.new SL
TPipe.toList SL -- pexotic; rc=$?
res="$RESULT"
slcount="$(SL.count)"
slok=1
slbad=-1
for (( i = 0; i < ${#EXOTIC[@]}; i++ )); do
    SL.Get "$i"
    if [[ "$RESULT" != "${EXOTIC[$i]}" ]]; then
        slok=0
        slbad=$i
        break
    fi
done
if [[ "$res" == "${#EXOTIC[@]}" && $rc -eq 0 && "$slcount" == "${#EXOTIC[@]}" ]] && (( slok )); then
    kt_test_pass "TStringList holds all ${#EXOTIC[@]} records verbatim"
else
    kt_test_fail "RESULT='$res' rc=$rc count='$slcount' byte-exact=$slok (first mismatch at index $slbad)"
fi
SL.delete

kt_test_start "a REJECTING .Add (THashSet duplicates) does not abort and RESULT counts records OFFERED"
THashSet.new HS
TPipe.toList HS -- printf 'a\nb\na\nb\nc\n'; rc=$?
res="$RESULT"
HS.Count; hc="$RESULT"
if [[ "$res" == "5" && $rc -eq 0 && "$hc" == "3" ]]; then
    kt_test_pass "5 offered, 3 stored, the two rc-1 duplicates ignored"
else
    kt_test_fail "RESULT='$res' rc=$rc Count='$hc'"
fi
HS.delete

kt_test_start "the same rejecting .Add under \`set -eu\` in a child does not tear the frame down"
RJCHILD="$TMP/reject_child.sh"
cat > "$RJCHILD" <<'RJ_EOF'
#!/bin/bash
set -eu
source "$1/tpipe.sh"
source "$1/../thashset/thashset.sh"
THashSet.new H
TPipe.toList H -- printf 'a\nb\na\nb\nc\n'
offered="$RESULT"
H.Count
printf 'offered=%s stored=%s\n' "$offered" "$RESULT"
RJ_EOF
rjout="$(timeout 30 "$BASH" "$RJCHILD" "$TP_DIR" 2>"$TMP/reject.err")"; rjrc=$?
if [[ $rjrc -eq 0 && "$rjout" == "offered=5 stored=3" && ! -s "$TMP/reject.err" ]]; then
    kt_test_pass "child exited 0: $rjout"
else
    kt_test_fail "rc=$rjrc out='$rjout' err='$(cat "$TMP/reject.err")'"
fi

kt_test_start "TPipe.stop from inside .Add stops the sink after that record (rc 0)"
TStopper.new ST
SADD=()
TPipe.toList ST -- p4 2>/dev/null; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 && "$(ST.N)" == "2" ]] && arr_is SADD "a" "b"; then
    kt_test_pass "2 of 4 records offered, rc 0 — the consumer's success"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc N='$(ST.N)' SADD=(${SADD[*]})"
fi
ST.delete

kt_test_start "an instance with no .Add member is rc 2 and the producer never starts"
TNoAdd.new NA
rm -f "$STARTED"
RESULT="sentinel"
TPipe.toList NA -- pmark 2>/dev/null; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" && ! -e "$STARTED" ]]; then
    kt_test_pass "rc 2, RESULT='', producer never ran"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' started=$( [[ -e "$STARTED" ]] && echo yes || echo no )"
fi
NA.delete

kt_test_start "a dangling instance name is rc 2 (duck-typed on \`declare -F INST.Add\`)"
RESULT="sentinel"
TPipe.toList tpipe_dangling_inst_003 -- p3 2>/dev/null; rc=$?
if [[ $rc -eq 2 && -z "$RESULT" ]]; then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "the stdin form of toList works outside a subshell"
TCollector.new C3
LADD=()
TPipe.toList C3 <<< $'x\ny'; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 ]] && arr_is LADD "x" "y"; then
    kt_test_pass "2 records from a here-string"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc LADD=(${LADD[*]})"
fi
C3.delete

# ===========================================================================
kt_test_section "D. first — one record, then the stop path"
# ===========================================================================

kt_test_start "first equals \`head -n1\`: RESULT is the first record, rc 0"
ORACLE_FIRST="$(p3 | head -n1)"
RESULT="sentinel"
TPipe.first -- p3 2>/dev/null; rc=$?
if [[ "$RESULT" == "$ORACLE_FIRST" && "$RESULT" == "a" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT='a', identical to head -n1"
else
    kt_test_fail "RESULT='$RESULT' oracle='$ORACLE_FIRST' rc=$rc"
fi

kt_test_start "first on an EMPTY producer is RESULT='' and rc 1"
RESULT="sentinel"
TPipe.first -- printf '' 2>/dev/null; rc=$?
if [[ -z "$RESULT" && $rc -eq 1 ]]; then
    kt_test_pass "RESULT='', rc 1"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "first on a producer with exactly ONE UNTERMINATED record delivers it"
RESULT="sentinel"
TPipe.first -- printf 'solo' 2>/dev/null; rc=$?
if [[ "$RESULT" == "solo" && $rc -eq 0 ]]; then
    kt_test_pass "the tail without a terminator is a record"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "first on a single EMPTY terminated record is RESULT='' with rc 0 (a record exists)"
RESULT="sentinel"
TPipe.first -- printf '\n' 2>/dev/null; rc=$?
if [[ -z "$RESULT" && $rc -eq 0 ]]; then
    kt_test_pass "rc 0 distinguishes an empty record from no record"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "first ignores the producer's rc once a record has been read"
RESULT="sentinel"
TPipe.first -- pfail6 2>/dev/null; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "a" && $rc -eq 0 && "$lr" != "-1" ]]; then
    kt_test_pass "RESULT='a', rc 0, lastRc='$lr' (the producer's own, via the stop path)"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr'"
fi

kt_test_start "first returns an exotic record byte-exact"
RESULT="sentinel"
TPipe.first -- printf '%s\n' $'ta\tb' 'x' 2>/dev/null; rc=$?
if [[ "$RESULT" == $'ta\tb' && $rc -eq 0 ]]; then
    kt_test_pass "a tab-bearing record verbatim"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "the stdin form of first reads exactly ONE record and leaves the rest"
l1=""; l2=""; fr=""
{
    TPipe.first
    fr="$RESULT"
    IFS= read -r l1
    IFS= read -r l2 || :
} <<< $'one\ntwo\nthree'
if [[ "$fr" == "one" && "$l1" == "two" && "$l2" == "three" ]]; then
    kt_test_pass "one record consumed, 'two' and 'three' still on stdin"
else
    kt_test_fail "first='$fr' rest='$l1'/'$l2'"
fi

# F4 and F5 in the `first` shape live in 002_Stop.sh next to their each+stop
# twins (PLAN §3 re-points them at `first` here): they need a child under
# `timeout` and 002 already owns that harness.

# ===========================================================================
kt_test_section "E. count — records, nothing stored"
# ===========================================================================

kt_test_start "count equals \`wc -l\` over the same producer"
oracle="$(p4 | wc -l)"
oracle="${oracle// /}"
RESULT="sentinel"
TPipe.count -- p4; rc=$?
if [[ "$RESULT" == "$oracle" && "$RESULT" == "4" && $rc -eq 0 ]]; then
    kt_test_pass "4 records, identical to wc -l"
else
    kt_test_fail "RESULT='$RESULT' oracle='$oracle' rc=$rc"
fi

kt_test_start "count counts the exotic matrix exactly (a read-loop oracle)"
n=0
while IFS= read -r ln || [[ -n "$ln" ]]; do n=$(( n + 1 )); done < <(pexotic)
TPipe.count -- pexotic
if [[ "$RESULT" == "$n" && "$RESULT" == "${#EXOTIC[@]}" ]]; then
    kt_test_pass "${#EXOTIC[@]} records"
else
    kt_test_fail "RESULT='$RESULT' oracle='$n' expected='${#EXOTIC[@]}'"
fi

kt_test_start "count includes an unterminated last record (wc -l would miss it)"
wcn="$(printf 'a\nb' | wc -l)"
wcn="${wcn// /}"
TPipe.count -- printf 'a\nb'
if [[ "$RESULT" == "2" && "$wcn" == "1" ]]; then
    kt_test_pass "count 2 where wc -l says 1 — the unterminated tail is a record"
else
    kt_test_fail "RESULT='$RESULT' wc='$wcn'"
fi

kt_test_start "count on an empty producer is 0 with rc 0"
RESULT="sentinel"
TPipe.count -- printf ''; rc=$?
if [[ "$RESULT" == "0" && $rc -eq 0 ]]; then
    kt_test_pass "RESULT 0, rc 0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

kt_test_start "the stdin form of count works outside a subshell"
TPipe.count <<< $'a\nb\nc\nd'; rc=$?
if [[ "$RESULT" == "4" && $rc -eq 0 ]]; then
    kt_test_pass "4 records from a here-string"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc"
fi

# ===========================================================================
kt_test_section "F. the -0 and -c flags"
# ===========================================================================

FXDIR="$(kt_fixture_tmpdir_create "f7_fixture")"
: > "$FXDIR/plain.txt"
: > "$FXDIR/a b.txt"
: > "$FXDIR/new"$'\n'"line.txt"

kt_test_start "F7: -0 over \`find -print0\` on names with a space and a NEWLINE"
Z_ORACLE=()
exec {ofd}< <(find "$FXDIR" -type f -print0)
mapfile -t -d '' -u "$ofd" Z_ORACLE
exec {ofd}<&-
GOT=()
TPipe.toArray -0 GOT -- find "$FXDIR" -type f -print0; rc=$?
zres="$RESULT"
# the newline-delimited form OVER-counts, which is why -print0 exists
TPipe.count -- find "$FXDIR" -type f -print
nlcount="$RESULT"
if [[ "$zres" == "3" && $rc -eq 0 && "${#GOT[@]}" == "3" && "$nlcount" == "4" ]] \
   && arr_eq GOT Z_ORACLE; then
    kt_test_pass "3 NUL records (identical to a bare mapfile -d ''), 4 newline records"
else
    kt_test_fail "toArray rc=$rc RESULT='$zres' got=${#GOT[@]} oracle=${#Z_ORACLE[@]} newline-count='$nlcount'"
fi

kt_test_start "F7: the NUL records carry the newline inside the name byte-exact"
hit=0
for e in "${GOT[@]}"; do
    if [[ "$e" == "$FXDIR/new"$'\n'"line.txt" ]]; then
        hit=1
    fi
done
if (( hit )); then
    kt_test_pass "the embedded newline survived the -0 record"
else
    kt_test_fail "no element equals the newline-bearing path; GOT=($(printf '<%s>' "${GOT[@]}"))"
fi

kt_test_start "F7: -0 through count / first / toList agrees with the -0 toArray"
TPipe.count -0 -- find "$FXDIR" -type f -print0; zc="$RESULT"
TPipe.first -0 -- find "$FXDIR" -type f -print0 2>/dev/null; zf="$RESULT"
TCollector.new CZ
LADD=()
TPipe.toList -0 CZ -- find "$FXDIR" -type f -print0; zl="$RESULT"
CZ.delete
if [[ "$zc" == "3" && "$zl" == "3" && "$zf" == "${Z_ORACLE[0]}" ]] && arr_eq LADD Z_ORACLE; then
    kt_test_pass "count 3, toList 3 byte-exact, first = the oracle's first record"
else
    kt_test_fail "count='$zc' toList='$zl' first='$zf' vs oracle[0]='${Z_ORACLE[0]}'"
fi

kt_test_start "F11: IFS=':' around a -0 call still yields the right records"
GOT=()
oldifs="${IFS-}"
IFS=':'
TPipe.toArray -0 GOT -- pz; rc=$?
r1="$RESULT"
TPipe.count -0 -- pz
r2="$RESULT"
IFS="$oldifs"
if [[ "$r1" == "2" && $rc -eq 0 && "$r2" == "2" ]] && arr_is GOT "a" "b"; then
    kt_test_pass "the delimiter is a VALUE, not an expansion-built option word"
else
    kt_test_fail "toArray RESULT='$r1' rc=$rc count='$r2' GOT=(${GOT[*]})"
fi

kt_test_start "-c strips EXACTLY one trailing CR through toArray (and none without it)"
RAW=(); GOT=()
TPipe.toArray RAW -- pcr
TPipe.toArray -c GOT -- pcr
if arr_is RAW $'x\r\r' $'y\r' "z" && arr_is GOT $'x\r' "y" "z"; then
    kt_test_pass "one CR removed per record, embedded CRs kept"
else
    kt_test_fail "raw=($(printf '<%q>' "${RAW[@]}")) stripped=($(printf '<%q>' "${GOT[@]}"))"
fi

kt_test_start "-c strips EXACTLY one trailing CR through toList and first"
TCollector.new CC
LADD=()
TPipe.toList -c CC -- pcr
lres="$RESULT"
TPipe.first -c -- pcr 2>/dev/null
fres="$RESULT"
CC.delete
if [[ "$lres" == "3" && "$fres" == $'x\r' ]] && arr_is LADD $'x\r' "y" "z"; then
    kt_test_pass "toList and first strip one CR each"
else
    kt_test_fail "toList RESULT='$lres' LADD=($(printf '<%q>' "${LADD[@]}")) first='$(printf '%q' "$fres")'"
fi

# P1 finding: `build` re-creates every member body from `declare -f` through
# `eval`, and a LITERAL `$'\r'` written inside the body does not survive that
# round trip — the rebuilt body reads `${x%''}` and strips nothing, silently.
# `each -c` (a P0 member) was affected too, so it is pinned here as well; the
# unit now keeps the pattern in __TPIPE_CR.
kt_test_start "-c strips EXACTLY one trailing CR through each (the P0 member too)"
CREC=()
crcb() { CREC+=( "$1" ); return 0; }
TPipe.each -c crcb -- pcr
cres="$RESULT"
CRAW=()
rawcb() { CRAW+=( "$1" ); return 0; }
TPipe.each rawcb -- pcr
if [[ "$cres" == "3" ]] && arr_is CREC $'x\r' "y" "z" && arr_is CRAW $'x\r\r' $'y\r' "z"; then
    kt_test_pass "each -c removed one CR per record; without it the records are verbatim"
else
    kt_test_fail "with -c=($(printf '<%q>' "${CREC[@]}")) without=($(printf '<%q>' "${CRAW[@]}"))"
fi

kt_test_start "the -c pattern survived the kklass declare -f/eval round trip"
if [[ "${#__TPIPE_CR}" == "1" && "$__TPIPE_CR" == $'\r' ]]; then
    kt_test_pass "__TPIPE_CR holds exactly one carriage return"
else
    kt_test_fail "__TPIPE_CR=$(printf '%q' "${__TPIPE_CR-<unset>}") len=${#__TPIPE_CR}"
fi

kt_test_start "-c does not change what count counts"
TPipe.count -- pcr; c1="$RESULT"
TPipe.count -c -- pcr; c2="$RESULT"
if [[ "$c1" == "3" && "$c2" == "3" ]]; then
    kt_test_pass "3 records either way"
else
    kt_test_fail "without -c='$c1' with -c='$c2'"
fi

kt_test_start "-0 and -c combine: one CR stripped from each NUL record"
GOT=()
TPipe.toArray -0 -c GOT -- pzc
if [[ "$RESULT" == "2" ]] && arr_is GOT $'x\r' "y"; then
    kt_test_pass "both flags applied"
else
    kt_test_fail "RESULT='$RESULT' GOT=($(printf '<%q>' "${GOT[@]}"))"
fi

kt_test_start "an unknown flag is rc 2 for all four sinks and starts nothing"
rm -f "$STARTED"
flag_ok=1
flag_detail=""
TCollector.new CF
GOT=(); RESULT="sentinel"; TPipe.toArray -q GOT -- pmark 2>/dev/null; frc=$?
if [[ $frc -ne 2 || -n "$RESULT" ]]; then flag_ok=0; flag_detail="toArray:$frc"; fi
RESULT="sentinel"; TPipe.toList -q CF -- pmark 2>/dev/null; frc=$?
if [[ $frc -ne 2 || -n "$RESULT" ]]; then flag_ok=0; flag_detail="$flag_detail toList:$frc"; fi
RESULT="sentinel"; TPipe.first -q -- pmark 2>/dev/null; frc=$?
if [[ $frc -ne 2 || -n "$RESULT" ]]; then flag_ok=0; flag_detail="$flag_detail first:$frc"; fi
RESULT="sentinel"; TPipe.count -q -- pmark 2>/dev/null; frc=$?
if [[ $frc -ne 2 || -n "$RESULT" ]]; then flag_ok=0; flag_detail="$flag_detail count:$frc"; fi
CF.delete
if [[ -e "$STARTED" ]]; then flag_ok=0; flag_detail="$flag_detail producer-ran"; fi
if (( flag_ok )); then
    kt_test_pass "four rc 2 refusals, no producer started"
else
    kt_test_fail "$flag_detail"
fi

# ===========================================================================
kt_test_section "G. F16 — the producer inherits the CALLER's stdin"
# ===========================================================================

kt_test_start "F16: \`-- cat\` reads the here-string given to the SINK call (toArray)"
GOT=()
TPipe.toArray GOT -- cat <<< $'alpha\nbeta'; rc=$?
if [[ "$RESULT" == "2" && $rc -eq 0 ]] && arr_is GOT "alpha" "beta"; then
    kt_test_pass "the process substitution inherited the caller's stdin"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc GOT=(${GOT[*]})"
fi

kt_test_start "F16: the same for count, first and toList"
TPipe.count -- cat <<< $'alpha\nbeta\ngamma'; c="$RESULT"
TPipe.first -- cat <<< $'alpha\nbeta' 2>/dev/null; f="$RESULT"
TCollector.new C16
LADD=()
TPipe.toList C16 -- cat <<< $'alpha\nbeta'; l="$RESULT"
C16.delete
if [[ "$c" == "3" && "$f" == "alpha" && "$l" == "2" ]] && arr_is LADD "alpha" "beta"; then
    kt_test_pass "count 3, first 'alpha', toList 2"
else
    kt_test_fail "count='$c' first='$f' toList='$l' LADD=(${LADD[*]})"
fi

# ===========================================================================
kt_test_section "H. the rc 1 + non-empty RESULT deviation (PLAN §2.4)"
# ===========================================================================

kt_test_start "toArray on a failing producer: rc 1, the array KEPT, lastRc 6"
GOT=()
TPipe.toArray GOT -- pfail6; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "2" && $rc -eq 1 && "$lr" == "6" ]] && arr_is GOT "a" "b"; then
    kt_test_pass "rc 1 with 2 elements still in the array (named deviation)"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' GOT=(${GOT[*]})"
fi

kt_test_start "count on a failing producer: rc 1 with the count KEPT"
TPipe.count -- pfail6; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "2" && $rc -eq 1 && "$lr" == "6" ]]; then
    kt_test_pass "rc 1, RESULT 2, lastRc 6"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr'"
fi

kt_test_start "toList on a failing producer: rc 1 with the records already offered"
TCollector.new C4
LADD=()
TPipe.toList C4 -- pfail6; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "2" && $rc -eq 1 && "$lr" == "6" && "$(C4.N)" == "2" ]] && arr_is LADD "a" "b"; then
    kt_test_pass "rc 1, 2 records already in the list"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr' N='$(C4.N)' LADD=(${LADD[*]})"
fi
C4.delete

kt_test_start "a missing producer command is rc 1 with lastRc 127 for all four sinks"
GOT=()
TPipe.toArray GOT -- tpipe_no_such_command_003 2>/dev/null; a_rc=$?
TPipe.lastRc; a_lr="$RESULT"
TPipe.count -- tpipe_no_such_command_003 2>/dev/null; c_rc=$?
c_res="$RESULT"
TPipe.lastRc; c_lr="$RESULT"
TPipe.first -- tpipe_no_such_command_003 2>/dev/null; f_rc=$?
f_res="$RESULT"
TPipe.lastRc; f_lr="$RESULT"
if [[ $a_rc -eq 1 && "$a_lr" == "127" && "${#GOT[@]}" == "0" \
      && $c_rc -eq 1 && "$c_res" == "0" && "$c_lr" == "127" \
      && $f_rc -eq 1 && -z "$f_res" && "$f_lr" == "127" ]]; then
    kt_test_pass "no pre-check; the procsub reports 127 through wait"
else
    kt_test_fail "toArray rc=$a_rc lastRc=$a_lr n=${#GOT[@]} / count rc=$c_rc RESULT=$c_res lastRc=$c_lr / first rc=$f_rc RESULT='$f_res' lastRc=$f_lr"
fi

# ===========================================================================
kt_test_section "I. nesting"
# ===========================================================================

NEST_OUT=()
NEST_COUNTS=()
nest_cb() {
    NEST_OUT+=( "$TPIPE_INDEX:$1" )
    if [[ "$TPIPE_INDEX" == "1" ]]; then
        TPipe.toArray NEST_ARR -- printf 'x\ny\n'
        NEST_COUNTS+=( "toArray=$RESULT" )
        TPipe.count -- printf 'p\nq\nr\n'
        NEST_COUNTS+=( "count=$RESULT" )
        TPipe.first -- printf 'solo\n' 2>/dev/null
        NEST_COUNTS+=( "first=$RESULT" )
    fi
    return 0
}

kt_test_start "a toArray / count / first nested inside an \`each\` callback works"
NEST_OUT=(); NEST_ARR=(); NEST_COUNTS=()
TPipe.each nest_cb -- p3; rc=$?
res="$RESULT"
if [[ "$res" == "3" && $rc -eq 0 ]] \
   && arr_is NEST_OUT "1:a" "2:b" "3:c" \
   && arr_is NEST_ARR "x" "y" \
   && arr_is NEST_COUNTS "toArray=2" "count=3" "first=solo"; then
    kt_test_pass "the outer sink still delivered 3 records with its own TPIPE_INDEX"
else
    kt_test_fail "outer RESULT='$res' rc=$rc OUT=(${NEST_OUT[*]}) ARR=(${NEST_ARR[*]}) COUNTS=(${NEST_COUNTS[*]})"
fi

kt_test_start "a nested sink leaves the outer lastRc as the OUTER producer's"
NEST_OUT=(); NEST_ARR=(); NEST_COUNTS=()
TPipe.each nest_cb -- pfail6; rc=$?
res="$RESULT"
TPipe.lastRc; lr="$RESULT"
if [[ "$res" == "2" && $rc -eq 1 && "$lr" == "6" ]]; then
    kt_test_pass "outer rc 1, lastRc 6 after three inner sinks"
else
    kt_test_fail "RESULT='$res' rc=$rc lastRc='$lr'"
fi

kt_test_start "toArray nested inside a toList .Add keeps both frames straight"
NADD=(); NEST_ARR=()
TNest.new NN
TPipe.toList NN -- printf 'k\n'; rc=$?
NN.delete
if [[ "$RESULT" == "1" && $rc -eq 0 ]] \
   && arr_is NADD "k" "inner=2" && arr_is NEST_ARR "k-1" "k-2"; then
    kt_test_pass "outer toList 1 record, inner toArray 2 elements"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc NADD=(${NADD[*]}) NEST_ARR=(${NEST_ARR[*]})"
fi

# ===========================================================================
kt_test_section "J. the P0 stub is gone"
# ===========================================================================

kt_test_start "tpipe._pending no longer exists as a function"
if declare -F -- tpipe._pending >/dev/null 2>&1; then
    kt_test_fail "tpipe._pending is still defined"
else
    kt_test_pass "the P0 placeholder was removed"
fi

kt_test_start "the unit source contains no reference to the pending sentinel"
if grep -q '_pending' "$TP_DIR/tpipe.sh"; then
    kt_test_fail "tpipe.sh still mentions _pending"
else
    kt_test_pass "no '_pending' anywhere in tpipe.sh"
fi

kt_test_start "under VERBOSE_KKLASS=debug a VALID call to each of the five sinks is silent"
SILF="$TMP/silent.err"
: > "$SILF"
TCollector.new CS
GOT=()
VERBOSE_KKLASS=debug
{
    TPipe.toArray GOT -- p3
    TPipe.toList CS -- p3
    TPipe.first -- p3q
    TPipe.count -- p3
    TPipe.each noop_cb_003 -- p3
} 2>"$SILF" || :
VERBOSE_KKLASS=
CS.delete
if [[ ! -s "$SILF" ]]; then
    kt_test_pass "no diagnostic on any rc 0 path"
else
    kt_test_fail "stderr: $(cat "$SILF")"
fi

# ===========================================================================
kt_test_section "K. zero forks per record"
# ===========================================================================

kt_test_start "toList: \`.Add\` runs in THIS process for every record (zero forks per record)"
TForkProbe.new FP
FORKPIDS=()
TPipe.toList FP -- p4
FP.delete
same=1
for pid in "${FORKPIDS[@]}"; do
    if [[ "$pid" != "$BASHPID" ]]; then
        same=0
    fi
done
if [[ "$RESULT" == "4" && "${#FORKPIDS[@]}" == "4" ]] && (( same )); then
    kt_test_pass "4 Add calls, all at BASHPID=$BASHPID"
else
    kt_test_fail "RESULT='$RESULT' pids=(${FORKPIDS[*]}) mine=$BASHPID"
fi

kt_test_start "toArray: the ONLY fork per call is the producer (5 records, one producer pid)"
GOT=()
TPipe.toArray GOT -- ppid5
uniq_ok=1
for e in "${GOT[@]}"; do
    if [[ "$e" != "${GOT[0]}" ]]; then
        uniq_ok=0
    fi
done
if [[ "$RESULT" == "5" && "${#GOT[@]}" == "5" && "${GOT[0]}" != "$BASHPID" ]] && (( uniq_ok )); then
    kt_test_pass "5 records all tagged with the single producer pid ${GOT[0]} (ours is $BASHPID)"
else
    kt_test_fail "RESULT='$RESULT' GOT=(${GOT[*]}) mine=$BASHPID"
fi

kt_test_start "count and first see the same single producer pid"
TPipe.count -- ppid5; cn="$RESULT"
TPipe.first -- ppid5 2>/dev/null; fp="$RESULT"
if [[ "$cn" == "5" && "$fp" =~ ^[0-9]+$ && "$fp" != "$BASHPID" ]]; then
    kt_test_pass "count 5, first returned the producer pid $fp (ours is $BASHPID)"
else
    kt_test_fail "count='$cn' first='$fp' mine=$BASHPID"
fi
