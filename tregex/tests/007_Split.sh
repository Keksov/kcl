#!/bin/bash
# 007_Split.sh - TRegEx.split: pieces BETWEEN matches (.NET Regex.Split, S12) —
# captured groups INTERLEAVED, leading/trailing/consecutive empties KEPT, no
# match -> whole text, empty-match patterns split by absolute position, invalid
# -> rc2, i-flag, multichar/regex delimiters, direct-call-required, torture.
# Basis: DocWiki TRegEx.Split + .NET Regex.Split documented semantics + P0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: TRegEx.split"

# sarr <name> <text> <re> <expCount> <expBracketed> [flags]
# pieces are compared bracket-delimited ([p0][p1]...) so embedded spaces/empties
# are unambiguous.
sarr() {
    kt_test_start "$1"
    local -a arr=()
    TRegEx.split "$2" "$3" arr "-" "${6:-}"
    local got="" x
    for x in "${arr[@]}"; do got+="[$x]"; done
    if [[ "$RESULT" == "$4" && "$got" == "$5" ]]; then
        kt_test_pass "count=$RESULT $got"
    else
        kt_test_fail "count=$RESULT $got ; want $4 $5"
    fi
}

# --- core .NET Split semantics ---
sarr "comma split"           "a,b,c"    ","        3 "[a][b][c]"
sarr "captured groups kept"  "a1b2c"    "([0-9])"  5 "[a][1][b][2][c]"
sarr "empties kept L/T/mid"  ",a,,b,"   ","        5 "[][a][][b][]"
sarr "no match -> whole"     "nodelim"  ","        1 "[nodelim]"
sarr "single leading delim"  ",abc"     ","        2 "[][abc]"
sarr "single trailing delim" "abc,"     ","        2 "[abc][]"

# --- empty-match pattern splits by absolute position (.NET parity) ---
sarr "empty-match x* char split" "abc"  "x*"       5 "[][a][b][c][]"

# --- delimiters: multichar, regex class, whitespace runs ---
sarr "multichar delimiter"   "aXXbXXc"  "XX"       3 "[a][b][c]"
sarr "regex class delimiter" "a,b;c:d"  "[,;:]"    4 "[a][b][c][d]"
sarr "whitespace run split"  "a  b   c" "[[:space:]]+" 3 "[a][b][c]"

# --- i-flag ---
sarr "i-flag delimiter"      "aXbxc"    "x"        3 "[a][b][c]" "i"

# --- rc semantics: 0 ok / 2 invalid ---
kt_test_start "rc: valid=0, invalid=2 (empty out on invalid)"
s0=(); TRegEx.split "a,b" "," s0; r0=$?
s2=(x y); TRegEx.split "a,b" "[" s2; r2=$?
[[ "$r0" == "0" && "$r2" == "2" && "${#s2[@]}" == "0" ]] && kt_test_pass "0/2, invalid cleared" \
    || kt_test_fail "r0=$r0 r2=$r2 n2=${#s2[@]}"

# --- direct-call-required: $() subshell discards the fill ---
kt_test_start "split under \$(): silent + parent array NOT filled"
Z=(sentinel)
out="$(TRegEx.split "a,b,c" "," Z)"
[[ -z "$out" && "${Z[*]}" == "sentinel" ]] && kt_test_pass "\$() empty, Z unchanged" \
    || kt_test_fail "leak: out='$out' Z=[${Z[*]}]"

# --- torture ---
sarr "newline delimiter"     $'a\nb\nc'  $'\n'     3 "[a][b][c]"
sarr "unicode pieces"        "café,thé"  ","       2 "[café][thé]"
sarr "quotes in pieces"      'x="a",y="b"' ","     2 "[x=\"a\"][y=\"b\"]"

# --- round-trip: pieces (no capture) rejoined by a literal delim reconstruct ---
kt_test_start "round-trip: join(split(text,',')) == text"
rt=(); TRegEx.split "one,two,three" "," rt
joined=""; for i in "${!rt[@]}"; do (( i > 0 )) && joined+=","; joined+="${rt[i]}"; done
[[ "$joined" == "one,two,three" ]] && kt_test_pass "reconstructed" || kt_test_fail "got '$joined'"

# --- zero-fork ---
kt_test_start "PATH='' : split needs no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
    z=(); TRegEx.split "p,q,r" "," z
    printf '%s:%s|%s|%s' "$RESULT" "${z[0]}" "${z[1]}" "${z[2]}"
)"
[[ "$zf" == "3:p|q|r" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "007_Split.sh completed"
