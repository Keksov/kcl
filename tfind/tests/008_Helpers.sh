#!/usr/bin/env bash
# 008_Helpers.sh — tfind H2: `TFind.quoteGlob` (kcl/docs/dev/tutil/HELPERS_PLAN.md
# §3; launch task L6.0). The pattern is H1's (`tsed/tests/008_Helpers.sh`).
#
# `TFind.quoteGlob TEXT` answers TEXT as a LITERAL `-name` / `-iname` pattern:
# `\` first, then `*`, `?`, `[`, each preceded by a backslash; nothing else.
#
# The PROOF is the tool itself (GNU find, the one TFind resolves everywhere):
# for each of `a*b`, `a?b`, `a[b]`, `a\b` and a mixed name the file is created
# together with decoys the RAW pattern would match, and
# `TFind.byName "$(TFind.quoteGlob NAME)" DIR` must find exactly the literal
# file. A file system that cannot hold a name (Windows forbids `\` in a name; the
# msys layer maps `*` and `?`, which this run measures) turns that case into
# `SKIP: <reason>` for that character only, and the Linux/macOS/FreeBSD CI rows
# cover it. No BSD find probe: TFind never runs BSD find.
#
# THE GATE IS THE FIRST CASE, as in 005 (`kt_gnu_gate find FIND_BIN`, ktool): with
# no GNU find the cases that run find are a loud `SKIP: <ktool's reason>` so the
# case COUNT is the same either way. The pure-string cases (A) never run find.
# The fixture dirs are built under `$_KT_TMPDIR` with `kt_fixture_tmpdir_create`;
# this file installs NO `trap … EXIT` of its own.
#
# Sections:
#   Z  the ktool gate and the fixture root
#   A  the escape set, byte-exact (`od -c`): each escaped char, `]` `!` `^` `{`
#      `}` left alone, a newline kept, empty -> '' rc 0, direct call silent +
#      RESULT, `$( )` prints once, a second argument is rc 2 (one line, RESULT '')
#   B  the proof against find: `-name` on `a*b` `a?b` `a[b]` `a\b` and a mixed
#      name (+ decoys), `-iname`, a newline in the name, and the raw pattern as
#      the counter-oracle (it matches a decoy)
#   C  composition: an instance (`f.name = "$(TFind.quoteGlob …)"`), nested from
#      inside an outer sink's callback, a child under `set -eu`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tfind.sh"
source "$UNIT"
source "$UNIT_DIR/../tutil/tests/gnu_helper.sh" || exit 1

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
ERRF="$TMP/h.err"

kt_test_section "008: TFind — the helpers (H2): quoteGlob"

# ===========================================================================
kt_test_section "Z. the ktool gate, and the fixture root"
# ===========================================================================

kt_gnu_gate find FIND_BIN

tcase() {
    kt_test_start "$1"
    if [[ "$GNU_OK" != "1" ]]; then
        kt_test_pass "SKIP: $GNU_WHY"
        return 1
    fi
    return 0
}

# tcaseT TITLE — tcase, and the case also needs timeout(1): without
# timeout/gtimeout it passes as `SKIP: $KT_TIMEOUT_WHY` (launch L5.4-9).
tcaseT() {
    tcase "$1" || return 1
    if ! kt_need_timeout; then
        kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
        return 1
    fi
    return 0
}

printf -v NL '\n'
BS='\'

# ---------------------------------------------------------------------------
# helpers — every local uses a `__z` prefix so none can shadow the unit's
# `__tfd_*` scratch namerefs.
# ---------------------------------------------------------------------------

odf() { od -c < "$1"; }
ods() { printf '%s' "$1" | od -c; }

# tf_dbg COMMAND... — the switch ON, stderr SPLIT: TF_N/TF_1 are OUR lines
# (`Error:`/`Warning:`), TOOL_N find's own. stdout is discarded.
TF_RC=0; TF_N=0; TF_1=''; TOOL_N=0
tf_dbg() {
    : > "$ERRF"
    VERBOSE_KKLASS=debug
    "$@" >/dev/null 2>"$ERRF"
    TF_RC=$?
    VERBOSE_KKLASS=
    TF_N=0; TOOL_N=0; TF_1=''
    local __zl
    while IFS= read -r __zl || [[ -n "$__zl" ]]; do
        case "$__zl" in
            Error:*|Warning:*)
                TF_N=$(( TF_N + 1 ))
                if [[ -z "$TF_1" ]]; then TF_1="$__zl"; fi
                ;;
            *)  TOOL_N=$(( TOOL_N + 1 )) ;;
        esac
    done < "$ERRF"
    return 0
}

# q_is TITLE WANT TEXT... — a DIRECT call: rc 0, RESULT == WANT byte for byte
# (`od -c`), nothing on stdout or stderr (redirected to files, no subshell).
q_is() {
    local __zt="$1" __zw="$2"; shift 2
    kt_test_start "$__zt"
    RESULT="sentinel"
    local __zrc=0
    TFind.quoteGlob "$@" > "$TMP/q.out" 2>"$TMP/q.err" || __zrc=$?
    local __zg="$RESULT"
    if [[ $__zrc -eq 0 && "$(ods "$__zg")" == "$(ods "$__zw")" && ! -s "$TMP/q.out" && ! -s "$TMP/q.err" ]]; then
        kt_test_pass "RESULT=$(printf '%q' "$__zg"), silent"
    else
        kt_test_fail "rc=$__zrc RESULT=$(printf '%q' "$__zg") want=$(printf '%q' "$__zw") stdout=$(wc -c < "$TMP/q.out") stderr=$(wc -c < "$TMP/q.err")"
    fi
}

# ===========================================================================
kt_test_section "A. quoteGlob — the escape set, byte-exact"
# ===========================================================================

q_is "A: \`*\` is escaped: a*b -> a\\*b" 'a\*b' 'a*b'
q_is "A: \`?\` is escaped: a?b -> a\\?b" 'a\?b' 'a?b'
q_is "A: \`[\` is escaped, the closing \`]\` is NOT: a[b] -> a\\[b]" 'a\[b]' 'a[b]'
q_is "A: the backslash is doubled: a\\b -> a\\\\b" 'a\\b' 'a\b'
q_is "A: the backslash goes FIRST (no double escaping): \`a*?[\\b\` -> \`a\\*\\?\\[\\\\b\`" 'a\*\?\[\\b' 'a*?[\b'
q_is "A: a backslash BEFORE a metacharacter: \`\\*\` -> \`\\\\\\*\`" '\\\*' '\*'
q_is "A: \`] ! ^ { } . + ( ) | & \$ / ,\` are LITERAL to fnmatch outside a bracket: nothing else is escaped" \
    'x]!^{y}.+()|&$/,z' 'x]!^{y}.+()|&$/,z'
q_is "A: a newline stays as it is" "a${NL}b\\*" "a${NL}b*"
q_is "A: empty TEXT -> RESULT '' rc 0" '' ''
q_is "A: plain text is unchanged" 'readme.txt' 'readme.txt'
printf -v TABV 'a b\tc'
q_is "A: a space and a tab are not touched" "$TABV" "$TABV"

kt_test_start "A: under \`\$( )\` the value is printed EXACTLY ONCE (and the empty TEXT prints nothing)"
c1="$(TFind.quoteGlob 'a*?[\b')"
c2="$(TFind.quoteGlob '')"
c3="$(TFind.quoteGlob "a${NL}b*")"
if [[ "$c1" == 'a\*\?\[\\b' && -z "$c2" && "$c3" == "a${NL}b\\*" ]]; then
    kt_test_pass "once each: $(printf '%q' "$c1") / '' / $(printf '%q' "$c3")"
else
    kt_test_fail "c1=$(printf '%q' "$c1") c2='$c2' c3=$(printf '%q' "$c3")"
fi

kt_test_start "A: a direct call REPLACES the caller's RESULT, and prints nothing (a DIRECT call has no subshell)"
RESULT=old-value
out="$(TFind.quoteGlob 'x*'; echo "|$RESULT")"
RESULT=old-value
TFind.quoteGlob 'x*' >/dev/null 2>&1
if [[ "$RESULT" == 'x\*' && "$out" == 'x\*|x\*' ]]; then
    kt_test_pass "RESULT 'x\\*'; inside \$( ) it also holds the value (and printed it once)"
else
    kt_test_fail "RESULT='$RESULT' out='$out'"
fi

kt_test_start "A: more than one argument is rc 2, RESULT '', ONE usage line, nothing printed, \`\$( )\` prints nothing, stdin UNREAD"
bad=""
for form in 2 3; do
    if [[ $form -eq 2 ]]; then
        tf_dbg TFind.quoteGlob 'a*b' 'c'
        RESULT=sentinel; TFind.quoteGlob 'a*b' 'c' >/dev/null 2>&1; res="$RESULT"
        cap="$(TFind.quoteGlob 'a*b' 'c' 2>/dev/null)"
        sk="$( { TFind.quoteGlob 'a*b' 'c' 2>/dev/null; printf 'rc=%s|' "$?"; IFS= read -r __zl; printf '%s' "$__zl"; } <<< 'stdin-kept' )"
    else
        tf_dbg TFind.quoteGlob a b c
        RESULT=sentinel; TFind.quoteGlob a b c >/dev/null 2>&1; res="$RESULT"
        cap="$(TFind.quoteGlob a b c 2>/dev/null)"
        sk="$( { TFind.quoteGlob a b c 2>/dev/null; printf 'rc=%s|' "$?"; IFS= read -r __zl; printf '%s' "$__zl"; } <<< 'stdin-kept' )"
    fi
    if [[ $TF_RC -eq 2 && $TF_N -eq 1 && $TOOL_N -eq 0 && "$TF_1" == *"usage"* && -z "$res" && -z "$cap" \
          && "$sk" == "rc=2|stdin-kept" ]]; then
        :
    else
        bad+=" args$form:rc=$TF_RC,ours=$TF_N,tool=$TOOL_N,RESULT='$res',cap='$cap',stdin='$sk'"
    fi
done
if [[ -z "$bad" ]]; then
    kt_test_pass "rc 2 for 2 and for 3 arguments, one 'usage' line each"
else
    kt_test_fail "$bad"
fi

kt_test_start "A: rc 0 and rc 0-with-empty emit NO line even with the debug switch on"
tf_dbg TFind.quoteGlob 'a*b'
n1=$TF_N; r1=$TF_RC
tf_dbg TFind.quoteGlob ''
if [[ $r1 -eq 0 && $n1 -eq 0 && $TF_RC -eq 0 && $TF_N -eq 0 && $TOOL_N -eq 0 ]]; then
    kt_test_pass "silent on the success paths"
else
    kt_test_fail "a*b rc=$r1 lines=$n1; '' rc=$TF_RC lines=$TF_N"
fi

kt_test_start "A: \`quoteGlob\` builds NO instance: \`__TFD_SEQ\` is untouched"
before="$__TFD_SEQ"
TFind.quoteGlob 'a*b' >/dev/null
TFind.quoteGlob '' >/dev/null
TFind.quoteGlob a b >/dev/null 2>&1
if [[ "$__TFD_SEQ" == "$before" ]]; then
    kt_test_pass "__TFD_SEQ stays $before"
else
    kt_test_fail "__TFD_SEQ $before -> $__TFD_SEQ"
fi

# ===========================================================================
kt_test_section "B. the proof against GNU find — the quoted pattern finds exactly the literal file"
# ===========================================================================

# mk DIR NAME — create an empty file NAME in DIR and prove the file system holds
# exactly that name (listing it back). rc 0 only then.
mk() {
    local __zd="$1" __zn="$2" __ze
    : > "$__zd/$__zn" 2>/dev/null || return 1
    for __ze in "$__zd"/*; do
        if [[ "${__ze##*/}" == "$__zn" ]]; then
            return 0
        fi
    done
    return 1
}

# proof TITLE WHY MODE NAME DECOY... — MODE is `name` or `iname`. In a fresh dir:
# the file NAME (if the file system cannot hold it: `SKIP: WHY`) plus every decoy
# it can hold. `TFind.byName` is the `name` form; `iname` goes through an
# instance. The quoted pattern must find exactly DIR/NAME. The RAW pattern is the
# counter-oracle: when it matches a decoy, the case says so (proof that the decoys
# are live).
PROOF_N=0
proof() {
    local __zt="$1" __zwhy="$2" __zmode="$3" __zname="$4"; shift 4
    local -a __zdecoys=( "$@" )
    PROOF_N=$(( PROOF_N + 1 ))
    if ! tcase "$__zt"; then
        return 0
    fi
    local __zd __zx
    __zd="$(cd "$(kt_fixture_tmpdir_create "proof$PROOF_N")" && pwd)"
    if ! mk "$__zd" "$__zname"; then
        # remove the case's own start line's pass: tcase has started it, so the
        # SKIP is this case's pass.
        kt_test_pass "SKIP: $__zwhy"
        return 0
    fi
    local -a __zmade=()
    for __zx in "${__zdecoys[@]}"; do
        if mk "$__zd" "$__zx"; then __zmade+=( "$__zx" ); fi
    done
    local __zq __zgot __zraw __zrc=0
    # `iname` gets the LOWER-CASE spelling of the name, so the case-folding is
    # part of the proof; `name` gets the name itself.
    local __zpat="$__zname"
    if [[ "$__zmode" == "iname" ]]; then __zpat="${__zname,,}"; fi
    __zq="$(TFind.quoteGlob "$__zpat")"
    if [[ "$__zmode" == "name" ]]; then
        __zgot="$(TFind.byName "$__zq" "$__zd" 2>/dev/null)" || __zrc=$?
        __zraw="$(TFind.byName "$__zpat" "$__zd" 2>/dev/null)" || :
    else
        TFind.new fPR "$__zd"
        fPR.iname = "$__zq"
        __zgot="$(fPR.run 2>/dev/null)" || __zrc=$?
        fPR.iname = "$__zpat"
        __zraw="$(fPR.run 2>/dev/null)" || :
        fPR.delete
    fi
    local __zwant="$__zd/$__zname" __zextra=''
    # does the raw pattern pick up a decoy? (documents that the decoys are live)
    for __zx in "${__zmade[@]}"; do
        if [[ "$__zraw" == *"$__zd/$__zx"* ]]; then __zextra+=" $__zx"; fi
    done
    if [[ $__zrc -eq 0 && "$__zgot" == "$__zwant" ]]; then
        kt_test_pass "quoted $(printf '%q' "$__zq") -> exactly the literal file; ${#__zmade[@]} decoys made; the raw pattern also matched:${__zextra:- (none)}"
    else
        kt_test_fail "rc=$__zrc quoted $(printf '%q' "$__zq") got='${__zgot//$'\n'/|}' want='$__zwant' decoys=${__zmade[*]}"
    fi
}

WHY_BS="this file system cannot hold a name containing a backslash (measured: the create failed or the name did not list back)"
WHY_MD="this file system cannot hold this name (measured: the create failed or the name did not list back)"

proof "B: \`-name\` with \`*\`: a*b finds the file a*b and NOT aXb, ab, aXXb" "$WHY_MD" name 'a*b' aXb ab aXXb
proof "B: \`-name\` with \`?\`: a?b finds the file a?b and NOT aXb, aYb" "$WHY_MD" name 'a?b' aXb aYb
proof "B: \`-name\` with \`[\`: a[b] finds the file a[b] and NOT ab (the raw pattern is the class [b])" "$WHY_MD" name 'a[b]' ab 'a[b' 'ab]'
proof "B: \`-name\` with a backslash: a\\b finds the file a\\b and NOT ab (the raw pattern is an escaped b)" "$WHY_BS" name 'a\b' ab 'a\\b' aXb
proof "B: \`-name\`, a mixed name without a backslash: m*x?y[z]!^{q} finds only itself (the raw pattern matches the DECOY mAAxByz!^{q})" "$WHY_MD" name 'm*x?y[z]!^{q}' 'mAAxByz!^{q}' 'mx1yz!^{q}' 'm*x?y[z]'
proof "B: \`-name\`, a mixed name WITH a backslash: m\\*x?y[z]\\w finds only itself" "$WHY_BS" name 'm\*x?y[z]\w' 'mQx1yzw' 'm*x?y[z]w' 'm\Qx?y[z]\w'
proof "B: \`-iname\` with \`*\`: the pattern a*b (lower case) finds the file A*B and NOT AXB, axb" "$WHY_MD" iname 'A*B' AXB axb
proof "B: \`-iname\` with \`[\`: the pattern a[b] (lower case) finds the file A[B] and NOT ab, AB" "$WHY_MD" iname 'A[B]' ab AB 'a[b'

if tcase "B: a NEWLINE in the name stays as it is: n<NL>*m finds only the literal file (NOT n<NL>Xm)"; then
    D="$(cd "$(kt_fixture_tmpdir_create proofnl)" && pwd)"
    NLNAME="n${NL}*m"
    if mk "$D" "$NLNAME"; then
        mk "$D" "n${NL}Xm" || :
        mk "$D" "nXm" || :
        q="$(TFind.quoteGlob "$NLNAME")"
        rc=0
        got="$(TFind.byName "$q" "$D" 2>/dev/null)" || rc=$?
        if [[ $rc -eq 0 && "$got" == "$D/$NLNAME" && "$q" == "n${NL}\\*m" ]]; then
            kt_test_pass "the pattern is $(printf '%q' "$q"); exactly the literal file came back"
        else
            kt_test_fail "rc=$rc q=$(printf '%q' "$q") got=$(printf '%q' "$got")"
        fi
    else
        kt_test_pass "SKIP: $WHY_MD (a newline or an asterisk in the name)"
    fi
fi

if tcase "B: the counter-oracle: WITHOUT quoteGlob the raw \`a*b\` DOES find the decoys (so the proofs above are not vacuous)"; then
    D="$(cd "$(kt_fixture_tmpdir_create proofraw)" && pwd)"
    : > "$D/aXb"; : > "$D/ab"; : > "$D/aXXb"
    got="$(TFind.byName 'a*b' "$D" 2>/dev/null | sort)"
    if [[ "$got" == "$D/aXXb${NL}$D/aXb${NL}$D/ab" ]]; then
        kt_test_pass "the raw pattern matched all three decoys"
    else
        kt_test_fail "got='${got//$NL/|}'"
    fi
fi

# ===========================================================================
kt_test_section "C. composition — an instance, a nested call, a child under set -eu"
# ===========================================================================

if tcase "C: \`f.name = \"\$(TFind.quoteGlob NAME)\"\` on an instance finds the literal name (a*b in a dir holding aXb, ab)"; then
    D="$(cd "$(kt_fixture_tmpdir_create inst)" && pwd)"
    : > "$D/aXb"; : > "$D/ab"; : > "$D/a b.txt"
    NAMEQ='a*b'
    if mk "$D" "$NAMEQ"; then
        TFind.new fC "$D"
        fC.name = "$(TFind.quoteGlob "$NAMEQ")"
        fC.type = f
        fC.print0 = 1
        declare -a GOT=()
        rc=0; fC.toArray GOT || rc=$?
        if [[ $rc -eq 0 && ${#GOT[@]} -eq 1 && "${GOT[0]}" == "$D/$NAMEQ" ]]; then
            kt_test_pass "1 record: the literal file, via toArray"
        else
            kt_test_fail "rc=$rc n=${#GOT[@]} got=$(printf '%q ' "${GOT[@]}")"
        fi
        fC.delete
    else
        kt_test_pass "SKIP: $WHY_MD"
    fi
fi

NEST_Q=()
NEST_F=()
cb_nest() {
    NEST_Q+=( "$(TFind.quoteGlob 'a*b')" )
    NEST_F+=( "$(TFind.byName "$(TFind.quoteGlob 'aXb')" "$ND" 2>/dev/null)" )
    return 0
}

if tcase "C: \`quoteGlob\` and \`byName\` nested inside an outer \`each\` callback — all complete, the outer instance survives"; then
    ND="$(cd "$(kt_fixture_tmpdir_create nest)" && pwd)"
    : > "$ND/aXb"; : > "$ND/other"
    TFind.new fN "$ND"
    fN.name = 'other'
    fN.print0 = 1
    NEST_Q=(); NEST_F=()
    rc=0; fN.each cb_nest 2>/dev/null || rc=$?
    declare -a GOT=()
    arc=0; fN.argv GOT || arc=$?
    fN.lastRc; lr="$RESULT"
    if [[ $rc -eq 0 && ${#NEST_Q[@]} -eq 1 && "${NEST_Q[0]}" == 'a\*b' && "${NEST_F[0]}" == "$ND/aXb" \
          && $arc -eq 0 && "$lr" == "0" && "${GOT[*]}" == "$FIND_BIN $ND -name other -print0" ]]; then
        kt_test_pass "1 outer record; nested quote 'a\\*b' and nested byName found aXb; the outer argv untouched"
    else
        kt_test_fail "rc=$rc q=${NEST_Q[*]} f=${NEST_F[*]} argvRc=$arc lastRc='$lr' argv=${GOT[*]}"
    fi
    fN.delete
fi

if tcaseT "C: in a CHILD script under \`set -eu\`: \`x=\$(TFind.quoteGlob …)\` is rc 0 (empty too), the extra argument is rc 2 and no abort"; then
    out="$(UNIT="$UNIT" "$KT_TIMEOUT" 30 "$BASH" -c '
set -eu
source "$UNIT"
x=$(TFind.quoteGlob "a*?[\\b")
printf "x=%s;" "$x"
y=$(TFind.quoteGlob "")
printf "y=[%s];" "$y"
r=0; TFind.quoteGlob a b || r=$?
printf "r=%s/[%s]" "$r" "$RESULT"' 2>/dev/null </dev/null)"; crc=$?
    if [[ $crc -eq 0 && "$out" == 'x=a\*\?\[\\b;y=[];r=2/[]' ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "rc=$crc out='$out'"
    fi
fi
