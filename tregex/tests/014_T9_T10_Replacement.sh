#!/bin/bash
# P7 — the replacement grammar and the $( ) capture caveat.
#
#   T9   `$(TRegEx.replace …)` / `$(TRegEx.escape …)` lose the result's TRAILING
#        newlines — that is command substitution, not the unit — while RESULT
#        keeps them byte for byte. Documented in README; pinned here so the
#        difference between the two access paths is a test, not a promise.
#
#   T10  `$10` was read as `$1` followed by a literal `0` even when group 10
#        existed. .NET takes the LONGEST digit run that names an existing
#        group, so `$10` is group 10 when there are >= 10 groups and `$1`+`0`
#        otherwise. Both branches are pinned.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

kt_test_init "T9T10Replacement" "$SCRIPT_DIR" "$@"
kt_test_section "014: trailing-newline capture (T9), two-digit group refs (T10)"

# ---------------------------------------------------------------------------
# 1. T9 — RESULT is byte-exact, $( ) is not (and cannot be).
# ---------------------------------------------------------------------------
kt_test_start "RESULT keeps trailing newlines that \$( ) strips [T9]"
ok=true; why=""
src=$'a\n\n'
TRegEx.replace "$src" "a" "b" >/dev/null
[[ "$RESULT" == $'b\n\n' ]] || { ok=false; why+=" [RESULT=$(printf '%q' "$RESULT") want $(printf '%q' $'b\n\n')]"; }
cap="$(TRegEx.replace "$src" "a" "b")"
[[ "$cap" == "b" ]] || { ok=false; why+=" [capture=$(printf '%q' "$cap") want 'b']"; }
TRegEx.escape $'a.b\n\n' >/dev/null
[[ "$RESULT" == $'a\\.b\n\n' ]] || { ok=false; why+=" [escape RESULT=$(printf '%q' "$RESULT")]"; }
cape="$(TRegEx.escape $'a.b\n\n')"
[[ "$cape" == 'a\.b' ]] || { ok=false; why+=" [escape capture=$(printf '%q' "$cape")]"; }
$ok && kt_test_pass "RESULT byte-exact, capture trimmed by the shell" || kt_test_fail "$why"

kt_test_start "an interior newline survives both paths [T9]"
ok=true; why=""
src=$'x\ny'
TRegEx.replace "$src" "x" "X" >/dev/null
[[ "$RESULT" == $'X\ny' ]] || { ok=false; why+=" [RESULT=$(printf '%q' "$RESULT")]"; }
cap="$(TRegEx.replace "$src" "x" "X")"
[[ "$cap" == $'X\ny' ]] || { ok=false; why+=" [capture=$(printf '%q' "$cap")]"; }
$ok && kt_test_pass "only TRAILING newlines are lost" || kt_test_fail "$why"

kt_test_start "README documents the trailing-newline capture caveat [T9]"
if grep -q "trailing newline" "$SCRIPT_DIR/../README.md"; then
    kt_test_pass "documented"
else
    kt_test_fail "README does not mention the trailing-newline caveat"
fi

# ---------------------------------------------------------------------------
# 2. T10 — two-digit group references.
# ---------------------------------------------------------------------------
ELEVEN='(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)'

kt_test_start "with 11 groups, \$10 and \$11 name groups 10 and 11 [T10]"
TRegEx.replace "abcdefghijk" "$ELEVEN" '[$10][$11]' >/dev/null
if [[ "$RESULT" == "[j][k]" ]]; then
    kt_test_pass "[j][k]"
else
    kt_test_fail "got '$RESULT' want '[j][k]'"
fi

kt_test_start "with 2 groups, \$10 is still group 1 followed by a literal 0 [T10]"
TRegEx.replace "ab" '(a)(b)' '[$10][$21][$3]' >/dev/null
if [[ "$RESULT" == "[a0][b1][\$3]" ]]; then
    kt_test_pass "[a0][b1][\$3]"
else
    kt_test_fail "got '$RESULT' want '[a0][b1][\$3]'"
fi

kt_test_start "\${n} braces still take any width and win over the bare form [T10]"
ok=true; why=""
TRegEx.replace "abcdefghijk" "$ELEVEN" '[${10}][${11}][${1}][${0}]' >/dev/null
[[ "$RESULT" == "[j][k][a][abcdefghijk]" ]] || { ok=false; why+=" [braces -> '$RESULT']"; }
TRegEx.replace "ab" '(a)(b)' '[${10}]' >/dev/null
[[ "$RESULT" == '[${10}]' ]] || { ok=false; why+=" [out-of-range brace -> '$RESULT']"; }
TRegEx.replace "ab" '(a)(b)' '[${012}]' >/dev/null
[[ "$RESULT" == '[${012}]' ]] || { ok=false; why+=" [leading-zero brace -> '$RESULT']"; }
$ok && kt_test_pass "brace form unchanged" || kt_test_fail "$why"

kt_test_start "the rest of the \$-grammar is unchanged [T10, regression]"
ok=true; why=""
_r() {  # TEXT PATTERN TEMPLATE EXPECT
    TRegEx.replace "$1" "$2" "$3" >/dev/null
    [[ "$RESULT" == "$4" ]] || { ok=false; why+=" [repl('$3')='$RESULT' want '$4']"; }
}
_r "ab" '(a)(b)' '$2$1'   "ba"
_r "ab" '(a)(b)' '$&'     "ab"
_r "ab" '(a)(b)' '$0'     "ab"
_r "ab" '(a)(b)' '$$'     '$'
_r "ab" '(a)(b)' '$x'     '$x'
_r "a"  'a'      '$'      '$'
_r "ab" '(a)(b)' '\1&'    '\1&'
_r "abcdefghijk" "$ELEVEN" '$9$10' "ij"
# 99 > 11 groups, so the two-digit reading fails and it falls back to one
# digit: group 9 ("i") followed by a literal 9.
_r "abcdefghijk" "$ELEVEN" '$99'   'i9'
$ok && kt_test_pass "9 grammar rows" || kt_test_fail "$why"

kt_test_start "a group index past the group count stays literal, never empty [T10]"
ok=true; why=""
TRegEx.replace "ab" '(a)(b)' '[$4]' >/dev/null
[[ "$RESULT" == '[$4]' ]] || { ok=false; why+=" ['\$4' -> '$RESULT']"; }
# 12 > 11 groups: the two-digit reading fails, so it is group 1 ("a") plus a
# literal 2 — never an empty string, and never an out-of-range index.
TRegEx.replace "abcdefghijk" "$ELEVEN" '[$12]' >/dev/null
[[ "$RESULT" == '[a2]' ]] || { ok=false; why+=" ['\$12' with 11 groups -> '$RESULT' want '[a2]']"; }
TRegEx.replace "abcdefghijk" "$ELEVEN" '[$11]' >/dev/null
[[ "$RESULT" == '[k]' ]] || { ok=false; why+=" ['\$11' with 11 groups -> '$RESULT' want '[k]']"; }
$ok && kt_test_pass "falls back one digit at a time" || kt_test_fail "$why"

kt_test_start "replaceCb still receives the whole match and every group [T10, regression]"
cb() { REPLY="<$1:$2:${11:-}>"; }
TRegEx.replace "abcdefghijk" "$ELEVEN" 'x' >/dev/null   # warm the group scratch
TRegEx.replaceCb "abcdefghijk" "$ELEVEN" cb >/dev/null
if [[ "$RESULT" == "<abcdefghijk:a:j>" ]]; then
    kt_test_pass "$RESULT"
else
    kt_test_fail "got '$RESULT' want '<abcdefghijk:a:j>'"
fi

kt_test_start "README documents the two-digit group rule [T10]"
if grep -qi 'two-digit\|\$10' "$SCRIPT_DIR/../README.md"; then
    kt_test_pass "documented"
else
    kt_test_fail "README does not document \$10"
fi

kt_test_log "014_T9_T10_Replacement.sh completed"
