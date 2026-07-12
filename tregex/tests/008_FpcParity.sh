#!/bin/bash
# 008_FpcParity.sh - FPC-TRACEABLE cross-checks. The ONLY tregex tests sourced
# from an external oracle: FPC's Delphi-compatible TRegEx
#   packages/vcl-compat/src/system.regularexpressions.pp
# with fpcunit tests
#   packages/vcl-compat/tests/utcregexapi.pas  (the TRegEx API)
#   packages/vcl-compat/tests/utcregex.pas     (the TPerlRegEx engine)
# Each case cites its FPC procedure. TWO adaptations are load-bearing because
# FPC's engine is PCRE2, not POSIX ERE (see docs/ERE-vs-PCRE.md):
#   (1) FPC/Delphi TMatch.Index is 1-BASED; ours is 0-based (.NET) -> my = fpc-1
#       (e.g. 'abba' in the fixture is FPC index 5 -> our RESULT_INDEX 4).
#   (2) PCRE shorthand \s is translated to POSIX [[:space:]].
# The fixture is FPC's own: TestStr / TestExpr below. Cases that DO NOT port
# (named groups, \1-in-replacement, per-group offsets, Escape wildcard mode,
# Match/Matches start-pos) are catalogued as deltas in docs/ERE-vs-PCRE.md, not
# here. Replace cross-checks are appended in P3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "008: FPC TRegEx parity (dialect-compatible subset)"

# FPC's own fixture (utcregexapi.pas / utcregex.pas)
TestStr='xyz abba abbba abbbba zyx'
TestExpr='a(b*)a'

# --- isMatch (utcregexapi TestClassIsMatch / TestClassIsMatchOptions) ---
kt_test_start "FPC TestClassIsMatch: match true, +'xyz' false"
TRegEx.isMatch "$TestStr" "$TestExpr"; a=$?
TRegEx.isMatch "$TestStr" "${TestExpr}xyz"; b=$?
[[ "$a" == "0" && "$b" == "1" ]] && kt_test_pass "true/false" || kt_test_fail "$a/$b"

kt_test_start "FPC TestClassIsMatchOptions: roIgnoreCase on UPPER subject"
TRegEx.isMatch "${TestStr^^}" "$TestExpr" i; a=$?
TRegEx.isMatch "${TestStr^^}" "${TestExpr}xyz" i; b=$?
[[ "$a" == "0" && "$b" == "1" ]] && kt_test_pass "true/false under i" || kt_test_fail "$a/$b"

# --- match (utcregexapi TestMatch): value/index/length/group1 ---
# FPC: M.value='abba' index=5 length=4 groups.count=2 group1='bb' index=6 len=2.
# Adapt: our RESULT_INDEX = 5-1 = 4; RESULT_GROUPS holds sub-groups only -> ('bb').
kt_test_start "FPC TestMatch: first match value/index(0-based)/length/group1"
TRegEx.match "$TestStr" "$TestExpr"
if [[ "$RESULT" == "abba" && "$RESULT_INDEX" == "4" && "$RESULT_LENGTH" == "4" \
      && "${#RESULT_GROUPS[@]}" == "1" && "${RESULT_GROUPS[0]}" == "bb" ]]; then
    kt_test_pass "value=abba idx=4(=fpc5-1) len=4 g1=bb"
else
    kt_test_fail "RESULT='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH groups=(${RESULT_GROUPS[*]})"
fi

# FPC TestMatchNoMatch: value='' (FPC index/length 0; ours index -1, our convention)
kt_test_start "FPC TestMatchNoMatch: no match -> empty value"
TRegEx.match "$TestStr" "${TestExpr}xyz"; rc=$?
[[ $rc -eq 1 && -z "$RESULT" && "$RESULT_LENGTH" == "0" ]] && kt_test_pass "no match, empty" \
    || kt_test_fail "rc=$rc RESULT='$RESULT' len=$RESULT_LENGTH"

# FPC TestClassMatchOptions: roIgnoreCase -> matched text is UPPER 'ABBA'
kt_test_start "FPC TestClassMatchOptions: i-flag returns actual (upper) text"
TRegEx.match "${TestStr^^}" "$TestExpr" i
[[ "$RESULT" == "ABBA" ]] && kt_test_pass "value=ABBA" || kt_test_fail "RESULT='$RESULT'"

# --- matches (utcregexapi TestMatches / TestClassMatches) ---
# FPC: count 3, values abba/abbba/abbbba, indices 5/10/16 -> ours 4/9/15.
kt_test_start "FPC TestMatches: count 3, values + 0-based offsets"
T=(); O=()
TRegEx.matches "$TestStr" "$TestExpr" T O
if [[ "$RESULT" == "3" && "${T[*]}" == "abba abbba abbbba" && "${O[*]}" == "4 9 15" ]]; then
    kt_test_pass "3 matches, offs [4 9 15] (=fpc[5 10 16]-1)"
else
    kt_test_fail "count=$RESULT texts=[${T[*]}] offs=[${O[*]}]"
fi

# FPC TestClassMatchesOptions: UpperCase(TestExpr) + roIgnoreCase on TestStr
kt_test_start "FPC TestClassMatchesOptions: i-flag, count 3"
T2=()
TRegEx.matches "$TestStr" "${TestExpr^^}" T2 - i
[[ "$RESULT" == "3" && "${T2[*]}" == "abba abbba abbbba" ]] && kt_test_pass "3 under i" \
    || kt_test_fail "count=$RESULT [${T2[*]}]"

# --- split (utcregex TestSplitAll / TestSplitLimit) — \s -> [[:space:]] ---
kt_test_start "FPC TestSplitAll: split on whitespace -> 5 pieces"
S=()
TRegEx.split "$TestStr" "[[:space:]]" S
if [[ "$RESULT" == "5" && "${S[0]}" == "xyz" && "${S[1]}" == "abba" \
      && "${S[2]}" == "abbba" && "${S[3]}" == "abbbba" && "${S[4]}" == "zyx" ]]; then
    kt_test_pass "[xyz][abba][abbba][abbbba][zyx]"
else
    kt_test_fail "count=$RESULT [${S[*]}]"
fi

kt_test_start "FPC TestSplitLimit: limit 2 -> ['xyz','rest unsplit']"
SL=()
TRegEx.split "$TestStr" "[[:space:]]" SL 2
if [[ "$RESULT" == "2" && "${SL[0]}" == "xyz" && "${SL[1]}" == "abba abbba abbbba zyx" ]]; then
    kt_test_pass "[xyz][abba abbba abbbba zyx]"
else
    kt_test_fail "count=$RESULT [${SL[0]}]|[${SL[1]}]"
fi

# --- replace (utcregexapi TestReplace/TestReplaceCount/TestClassReplaceOptions) ---
kt_test_start "FPC TestReplace/TestClassReplace: replace-all -> 'xyz c c c zyx'"
TRegEx.replace "$TestStr" "$TestExpr" "c" >/dev/null
[[ "$RESULT" == "xyz c c c zyx" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "FPC TestReplaceCount: maxCount 2 -> 'xyz c c abbbba zyx'"
TRegEx.replace "$TestStr" "$TestExpr" "c" 2 >/dev/null
[[ "$RESULT" == "xyz c c abbbba zyx" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "FPC TestClassReplaceOptions: roIgnoreCase (upper pattern, lower subject)"
TRegEx.replace "$TestStr" "${TestExpr^^}" "c" - i >/dev/null
[[ "$RESULT" == "xyz c c c zyx" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

# FPC utcregex TestReplaceGroupDollar: '*abba*' / '$1' -> '*bb*'
kt_test_start "FPC TestReplaceGroupDollar: \$1 group substitution"
TRegEx.replace "*abba*" "$TestExpr" '$1' >/dev/null
[[ "$RESULT" == "*bb*" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

# --- replaceCb / evaluator (utcregexapi TestReplaceEval / TestReplaceEvalCount) ---
_fpc_wrap() { REPLY="<$1>"; }   # DoReplacer: Result := '<' + Match.Value + '>'
kt_test_start "FPC TestReplaceEval: callback wraps each match"
TRegEx.replaceCb "$TestStr" "$TestExpr" _fpc_wrap >/dev/null
[[ "$RESULT" == "xyz <abba> <abbba> <abbbba> zyx" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "FPC TestReplaceEvalCount: callback + maxCount 2"
TRegEx.replaceCb "$TestStr" "$TestExpr" _fpc_wrap 2 >/dev/null
[[ "$RESULT" == "xyz <abba> <abbba> abbbba zyx" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_log "008_FpcParity.sh completed"
