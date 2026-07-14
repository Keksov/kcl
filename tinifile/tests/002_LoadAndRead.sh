#!/bin/bash
# 002_LoadAndRead.sh - tinifile P1: the file parser (FillSectionList verbatim)
# + the read core. Every case is an S-pin from PLAN.md section 3 (anchors into
# inifiles.pp): S1 missing file, S2 comments/blank lines, S3 duplicates
# first-wins, S4 orphan keys/[]-section/]-in-name, S8 trim + quotes (and the
# TIniFile-vs-TMemIniFile auto-StripQuotes asymmetry), S12 values with =/;,
# invalid rows, plus CRLF/BOM/no-final-newline reality, ifoEscapeLineFeeds,
# ifoStripComments/StripInvalid, ifoCaseSensitive, empty-value vs absent-key,
# and the zero-fork read path.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TIF_DIR="$SCRIPT_DIR/.."
source "$TIF_DIR/tinifile.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: TIniFile load + read core (P1)"

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# The torture fixture: BOM+CRLF, top comment, orphan key, blank line, section
# comment, padded key, value with '='/';', quoted value, invalid line,
# duplicate section, ]-in-name, [] section, duplicate key (case), no final NL.
{
    printf '\xef\xbb\xbf; top comment\r\n'
    printf 'orphan=dropped\r\n'
    printf '\r\n'
    printf '[main]\r\n'
    printf '; sec comment\r\n'
    printf '  key1  =  v1  \r\n'
    printf 'url=http://x/?a=1;b=2\r\n'
    printf 'q="quoted val"\r\n'
    printf 'bareline\r\n'
    printf '[main]\r\n'
    printf 'key1=dup-section-second\r\n'
    printf '[a]b]\r\n'
    printf 'inner=1\r\n'
    printf '[]\r\n'
    printf 'empty=e\r\n'
    printf '[Café]\r\n'
    printf 'naïve=Привет мир é\r\n'
    printf 'Größe=42\r\n'
    printf '[end]\r\n'
    printf 'key1=v1\r\n'
    printf 'KEY1=second\r\n'
    printf 'blank=\r\n'
    printf 'last=nonl'
} > "$D/t.ini"

TIniFile.new I "$D/t.ini"

kt_test_start "S8: line/ident/value trimmed; CRLF stripped"
I.ReadString main key1 DEF
[[ "$RESULT" == "v1" ]] && kt_test_pass "v1" || kt_test_fail "got '$RESULT'"

kt_test_start "S12: value keeps '=' and ';'"
I.ReadString main url DEF
[[ "$RESULT" == "http://x/?a=1;b=2" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "S8: TIniFile strips quotes at read (auto option)"
I.ReadString main q DEF
[[ "$RESULT" == "quoted val" ]] && kt_test_pass "stripped" || kt_test_fail "got '$RESULT'"

kt_test_start "S4: orphan key before any section is dropped"
I.SectionExists orphan; a=$?
I.ReadString "" orphan DEF; b="$RESULT"
[[ $a -eq 1 && "$b" == "DEF" ]] && kt_test_pass "dropped" || kt_test_fail "a=$a b=$b"

kt_test_start "S3: duplicate section — first wins for lookups"
I.ReadString main key1 DEF
[[ "$RESULT" == "v1" ]] && kt_test_pass "first section's key1" || kt_test_fail "got '$RESULT'"

kt_test_start "S3: duplicate key — first wins; case-insensitive default"
I.ReadString end key1 DEF; a="$RESULT"
I.ReadString END KEY1 DEF; b="$RESULT"
[[ "$a" == "v1" && "$b" == "v1" ]] && kt_test_pass "first + ci" || kt_test_fail "a=$a b=$b"

kt_test_start "S4: ']' legal inside a section name"
I.ReadString "a]b" inner DEF
[[ "$RESULT" == "1" ]] && kt_test_pass "a]b addressable" || kt_test_fail "got '$RESULT'"

kt_test_start "no-final-newline line is kept"
I.ReadString end last DEF
[[ "$RESULT" == "nonl" ]] && kt_test_pass "nonl" || kt_test_fail "got '$RESULT'"

kt_test_start "empty value vs absent key are DIFFERENT"
I.ReadString end blank FALLBACK; a="$RESULT"
I.ReadString end missing FALLBACK; b="$RESULT"
[[ "$a" == "" && "$b" == "FALLBACK" ]] && kt_test_pass "'' vs default" || kt_test_fail "a='$a' b='$b'"

kt_test_start "S4: [] listed as '' by ReadSections but NOT addressable"
S=(); I.ReadSections S
joined=""; for x in "${S[@]}"; do joined+="[$x]"; done
I.ReadString "" empty DEF; b="$RESULT"
[[ "$joined" == "[main][main][a]b][][Café][end]" && "$b" == "DEF" ]] \
    && kt_test_pass "$joined ; unreachable" || kt_test_fail "j=$joined b=$b"

kt_test_start "ReadSection: idents in order, comments excluded, '' for invalid"
K=(); I.ReadSection main K
j=""; for x in "${K[@]}"; do j+="[$x]"; done
[[ "$j" == "[key1][url][q][]" ]] && kt_test_pass "$j" || kt_test_fail "got $j"

kt_test_start "ReadSectionValues default: invalid in, comments out, quotes stripped"
V=(); I.ReadSectionValues main V
j=""; for x in "${V[@]}"; do j+="[$x]"; done
[[ "$j" == "[key1=v1][url=http://x/?a=1;b=2][q=quoted val][bareline]" ]] \
    && kt_test_pass "default shape" || kt_test_fail "got $j"

kt_test_start "ReadSectionValues +comments +quotes"
V2=(); I.ReadSectionValues main V2 svoIncludeComments svoIncludeInvalid svoIncludeQuotes
[[ "${V2[0]}" == "; sec comment" && "${V2[3]}" == 'q="quoted val"' ]] \
    && kt_test_pass "comment first, quotes kept" || kt_test_fail "v0='${V2[0]}' v3='${V2[3]}'"

kt_test_start "ReadSectionRaw: Ident=Value rows + bare invalid (FPC quirk verbatim)"
R=(); I.ReadSectionRaw main R
[[ "${R[0]}" == "; sec comment=" && "${R[1]}" == "key1=v1" && "${R[4]}" == "bareline" ]] \
    && kt_test_pass "raw incl. ';c=' quirk" || kt_test_fail "r0='${R[0]}' r1='${R[1]}' r4='${R[4]}'"

kt_test_start "SectionExists/ValueExists: hits, misses, case-insensitive"
I.SectionExists MAIN; a=$?
I.ValueExists main url; b=$?
I.ValueExists main nope; c=$?
[[ $a -eq 0 && $b -eq 0 && $c -eq 1 ]] && kt_test_pass "0/0/1" || kt_test_fail "$a/$b/$c"

# --- UTF-8: bash strings are BYTE strings — multibyte content must pass
# through LOSSLESSLY wherever we don't fold/measure/slice. Deterministic
# contract: EXACT-case unicode names always work (byte equality); values
# round-trip byte-exact. Non-ASCII case-FOLDING is locale-dependent
# (${x,,} folds É only under a UTF-8 locale) — documented observation below.
kt_test_start "UTF-8: exact-case unicode section/ident + lossless value"
I.ReadString "Café" "naïve" DEF; a="$RESULT"
I.ReadString "Café" "Größe" DEF; b="$RESULT"
I.SectionExists "Café"; c=$?
[[ "$a" == "Привет мир é" && "$b" == "42" && $c -eq 0 ]] \
    && kt_test_pass "cyrillic+accents lossless; exact-case addressable" \
    || kt_test_fail "a='$a' b='$b' c=$c"

kt_test_start "UTF-8: unicode names lossless in ReadSection fill"
KU=(); I.ReadSection "Café" KU
[[ "${KU[0]}" == "naïve" && "${KU[1]}" == "Größe" ]] \
    && kt_test_pass "idents byte-exact" || kt_test_fail "[${KU[0]}][${KU[1]}]"

kt_test_start "UTF-8 fold: ASCII part folds deterministically; non-ASCII = locale observation"
# 'cafÉ' vs 'Café': the ASCII letters c/a/f fold reliably; É<->é folds ONLY if
# the ambient locale does. Contract (PLAN §2.3): ASCII guaranteed, unicode
# follows the locale. Accept BOTH outcomes for the É-case, but REQUIRE the
# ASCII-only-different lookup ('cAFé' — same bytes for é) to hit.
I.ReadString "cAFé" "naïve" DEF; b="$RESULT"     # section ASCII-case-only diff, ident exact
I.ReadString "CAFÉ" "naïve" DEF; c="$RESULT"     # É needs locale folding — observation
if [[ "$b" == "Привет мир é" ]]; then
    obs="folded-É=$( [[ "$c" == "Привет мир é" ]] && echo yes || echo no )"
    kt_test_pass "ASCII-fold hit; É-fold observation: $obs (locale-dependent, documented)"
else
    kt_test_fail "ASCII-case-only lookup missed (b='$b')"
fi
I.delete

kt_test_start "TMemIniFile: quotes KEPT (no auto StripQuotes)"
TMemIniFile.new M "$D/t.ini"
M.ReadString main q DEF
[[ "$RESULT" == '"quoted val"' ]] && kt_test_pass "kept" || kt_test_fail "got '$RESULT'"
M.delete

kt_test_start "ifoCaseSensitive: exact-only lookups; dup-key exact hit"
TIniFile.new C "$D/t.ini" ifoCaseSensitive
C.ReadString END key1 DEF; a="$RESULT"
C.ReadString end KEY1 DEF; b="$RESULT"
[[ "$a" == "DEF" && "$b" == "second" ]] && kt_test_pass "miss + exact second" || kt_test_fail "a=$a b=$b"
C.delete

kt_test_start "ifoStripComments + ifoStripInvalid drop those rows at load"
TIniFile.new SC "$D/t.ini" ifoStripComments ifoStripInvalid
K2=(); SC.ReadSection main K2; n1=${#K2[@]}
S2=(); SC.ReadSections S2; n2=${#S2[@]}
[[ $n1 -eq 3 && $n2 -eq 6 ]] && kt_test_pass "idents 3 (no ''), sections 6 (no top comment)" \
    || kt_test_fail "n1=$n1 n2=$n2"
SC.delete

kt_test_start "ifoEscapeLineFeeds: '\\'-join on read; literal without it"
{ echo "[s]"; echo "k=a\\"; echo "b"; echo "n=1"; } > "$D/e.ini"
TIniFile.new E "$D/e.ini" ifoEscapeLineFeeds
E.ReadString s k DEF; a="$RESULT"
E.ReadString s n DEF; b="$RESULT"
E.delete
TIniFile.new E2 "$D/e.ini"
E2.ReadString s k DEF; c="$RESULT"
E2.delete
[[ "$a" == "ab" && "$b" == "1" && "$c" == 'a\' ]] && kt_test_pass "join/next-ok/literal" \
    || kt_test_fail "a=$a b=$b c=$c"

kt_test_start "S1: missing file -> empty ini, rc 0"
TIniFile.new MISS "$D/absent.ini"; rc=$?
MISS.SectionExists x; e=$?
[[ $rc -eq 0 && $e -eq 1 ]] && kt_test_pass "empty, no error" || kt_test_fail "rc=$rc e=$e"
MISS.delete

kt_test_start "PATH='' : parse + all read members fork-free"
zf="$(
    PATH=''
    source "$TIF_DIR/tinifile.sh" 2>/dev/null
    TIniFile.new Z "$D/t.ini"
    Z.ReadString main key1 X >/dev/null; a="$RESULT"
    Z.SectionExists main >/dev/null; b=$?
    K=(); Z.ReadSection main K >/dev/null
    V=(); Z.ReadSectionValues end V >/dev/null
    Z.delete
    printf '%s|%s|%s|%s' "$a" "$b" "${#K[@]}" "${#V[@]}"
)"
[[ "$zf" == "v1|0|4|4" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "002_LoadAndRead.sh completed"
