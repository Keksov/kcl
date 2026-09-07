#!/bin/bash
# 066_TSH09_Performance.sh — finding TSH-09: O(n*m) character loops.
#
# Before P5 replace/indexOf/countChar walked the string one character at a
# time, extracting a fresh substring on every step. On a 10 KB input that cost
# 520-600 ms per call on bash 5.2.37 and 213 ms on 5.3.9, while the bash
# expansion that does the same job — `${big//X/Y}` — costs about 0.36 ms.
# Nothing in the suite went above a handful of characters, so the wall was
# invisible.
#
# The gate is RELATIVE (kcl/PLAN.md section 4: perf walls are closed with
# relative gates, not milliseconds): each member must stay within 20x of the
# bare bash expansion doing the same work on the same input, measured in the
# same process. A generous absolute ceiling is asserted as well, because a
# relative gate alone would pass if the baseline itself regressed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TSH09_Performance" "$SCRIPT_DIR" "$@"

UNIT="$SCRIPT_DIR/../tstringhelper.sh"
source "$UNIT"

N=20                      # iterations per measurement
LIMIT_FACTOR=20           # relative gate: <= 20x the bare expansion
ABS_MS=1000               # absolute ceiling for N calls (50 ms per call)

# A 10 KB haystack with the needle in the middle and at the end, so a scan
# cannot win by finding the answer in the first bytes.
block="abcdefghij"
big=""
for ((i = 0; i < 512; i++)); do big+="$block"; done      # 5120 chars
big+="X"
for ((i = 0; i < 512; i++)); do big+="$block"; done      # 10241 chars total
big+="X"

kt_test_start "the fixture is a 10 KB string [TSH-09]"
if (( ${#big} >= 10240 )); then
    kt_test_pass "${#big} characters"
else
    kt_test_fail "fixture is only ${#big} characters"
fi

# Inline clock reads: a $( ) here would add a fork (1-16 ms) to every
# measurement and the budget floor is only 60 ms.

# --- the baseline: what bash itself costs for the same work -----------------
t0=${EPOCHREALTIME/./}; t0=$(( t0 / 1000 ))
for ((i = 0; i < N; i++)); do
    tmp="${big//X/Y}"
    tmp="${big%%X*}"
    tmp="${big//X/}"
done
t1=${EPOCHREALTIME/./}; t1=$(( t1 / 1000 ))
baseline=$(( t1 - t0 ))
(( baseline < 1 )) && baseline=1
budget=$(( baseline * LIMIT_FACTOR ))
(( budget < 60 )) && budget=60      # do not gate on measurement noise

gate() {   # TITLE MEMBER ARGS...
    local title="$1"; shift
    kt_test_start "$title"
    local a b spent
    a=${EPOCHREALTIME/./}; a=$(( a / 1000 ))
    local i
    for ((i = 0; i < N; i++)); do "$@" >/dev/null 2>&1 || :; done
    b=${EPOCHREALTIME/./}; b=$(( b / 1000 ))
    spent=$(( b - a ))
    if (( spent <= budget && spent <= ABS_MS )); then
        kt_test_pass "$title: ${spent} ms for $N calls (budget ${budget} ms, baseline ${baseline} ms)"
    else
        kt_test_fail "$title: ${spent} ms for $N calls exceeds budget ${budget} ms / ceiling ${ABS_MS} ms (baseline ${baseline} ms)"
    fi
}

gate "replace over 10 KB stays within 20x of \${s//old/new} [TSH-09]" \
    string.replace "$big" "X" "Y"
gate "replace with an explicit rfReplaceAll stays within budget [TSH-09]" \
    string.replace "$big" "X" "Y" "rfReplaceAll"
gate "replace of the FIRST occurrence stays within budget [TSH-09]" \
    string.replace "$big" "X" "Y" ""
gate "indexOf over 10 KB stays within budget [TSH-09]" \
    string.indexOf "$big" "X"
gate "indexOf of a missing needle stays within budget [TSH-09]" \
    string.indexOf "$big" "ZZZ"
gate "lastIndexOf over 10 KB stays within budget [TSH-09]" \
    string.lastIndexOf "$big" "X"
gate "countChar over 10 KB stays within budget [TSH-09]" \
    string.countChar "$big" "X"
gate "indexOfAny over 10 KB stays within budget [TSH-09]" \
    string.indexOfAny "$big" "XZ"
gate "lastIndexOfAny over 10 KB stays within budget [TSH-09]" \
    string.lastIndexOfAny "$big" "XZ"
gate "lastDelimiter over 10 KB stays within budget [TSH-09]" \
    string.lastDelimiter "$big" "X"
gate "contains over 10 KB stays within budget [TSH-09]" \
    string.contains "$big" "X"
gate "quotedString over 10 KB stays within budget [TSH-08, TSH-09]" \
    string.quotedString "$big"
gate "split of a 10 KB string stays within budget [TSH-03, TSH-09]" \
    string.split "$big" "X" perf_parts

# --- the answers are still right on the big input ---------------------------
kt_test_start "the fast paths return the same answers on 10 KB [TSH-09]"
bad=""
string.indexOf "$big" "X" >/dev/null 2>&1 || :
[[ "$RESULT" == "5120" ]] || bad+="indexOf=$RESULT "
string.lastIndexOf "$big" "X" >/dev/null 2>&1 || :
[[ "$RESULT" == "10241" ]] || bad+="lastIndexOf=$RESULT "
string.countChar "$big" "X" >/dev/null 2>&1 || :
[[ "$RESULT" == "2" ]] || bad+="countChar=$RESULT "
string.replace "$big" "X" "Y" >/dev/null 2>&1 || :
[[ "${#RESULT}" == "${#big}" && "$RESULT" != *X* ]] || bad+="replace "
string.split "$big" "X" perf_parts >/dev/null 2>&1 || :
[[ "$RESULT" == "3" ]] || bad+="split=$RESULT "
if [[ -z "$bad" ]]; then
    kt_test_pass "indexOf 5120, lastIndexOf 10241, countChar 2, replace clean, split 3"
else
    kt_test_fail "wrong answers: $bad"
fi

# --- a DENSE needle: the same work, measured against the same work ----------
# `${s//"$c"/}` costs what bash costs for that many replacements, so a needle
# that occurs 1024 times in the 10 KB fixture is measured against the bare
# expansion doing exactly that, not against the two-occurrence baseline above.
t0=${EPOCHREALTIME/./}; t0=$(( t0 / 1000 ))
for ((i = 0; i < N; i++)); do tmp="${big//a/}"; done
t1=${EPOCHREALTIME/./}; t1=$(( t1 / 1000 ))
dense_baseline=$(( t1 - t0 ))
(( dense_baseline < 1 )) && dense_baseline=1
dense_budget=$(( dense_baseline * 3 ))
(( dense_budget < 60 )) && dense_budget=60

kt_test_start "countChar of a needle that occurs 1024 times stays within 3x of \${s//a/} [TSH-09]"
t0=${EPOCHREALTIME/./}; t0=$(( t0 / 1000 ))
for ((i = 0; i < N; i++)); do string.countChar "$big" "a" >/dev/null 2>&1 || :; done
t1=${EPOCHREALTIME/./}; t1=$(( t1 / 1000 ))
spent=$(( t1 - t0 ))
if (( spent <= dense_budget )) && [[ "$RESULT" == "1024" ]]; then
    kt_test_pass "${spent} ms for $N calls (budget ${dense_budget} ms, baseline ${dense_baseline} ms), count 1024"
else
    kt_test_fail "${spent} ms for $N calls, budget ${dense_budget} ms (baseline ${dense_baseline} ms), RESULT='$RESULT'"
fi

kt_test_start "replace of a needle that occurs 1024 times stays within 3x [TSH-09]"
t0=${EPOCHREALTIME/./}; t0=$(( t0 / 1000 ))
for ((i = 0; i < N; i++)); do string.replace "$big" "a" "z" >/dev/null 2>&1 || :; done
t1=${EPOCHREALTIME/./}; t1=$(( t1 / 1000 ))
spent=$(( t1 - t0 ))
if (( spent <= dense_budget )) && [[ "$RESULT" != *a* && "${#RESULT}" == "${#big}" ]]; then
    kt_test_pass "${spent} ms for $N calls (budget ${dense_budget} ms)"
else
    kt_test_fail "${spent} ms for $N calls, budget ${dense_budget} ms"
fi
