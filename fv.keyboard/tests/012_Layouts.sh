#!/usr/bin/env bash
# 012_Layouts.sh - the layout tables (design P3 §14.4, §14.5): a legacy ESC +
# non-ASCII character (Alt + a letter in a non-Latin layout) -> kbAlt + the
# US key at that position, FV_KEY_CHAR the typed character, FV_KEY_BASE the
# US key; and fv.keyboard.layoutBase:
#   * the design's rows: Russian / Greek / Hebrew / Arabic Alt+F, Russian
#     Alt+X and Alt+Shift+F, Ukrainian / Georgian / Armenian / Thai / Persian
#     letters, a character in no table (kbAltChar stays);
#   * the lazy load: not on plain typing (ASCII, non-ASCII, CSI keys, legacy
#     Alt + ASCII), once at the first legacy Alt + non-ASCII key (a second key
#     and an FV_KBD_LAYOUT change rebuild from memory, never re-read the file);
#   * resolution: FV_KBD_LAYOUT (a comma list, first wins; bg_phonetic and
#     bg(phonetic); an unknown name skipped with one debug line), then the
#     locale's layout (LC_ALL, LC_CTYPE, LANG: the first naming one, read at
#     load), then the per-script default order; the Bulgarian phonetic
#     example of §14.6;
#   * layoutBase: rc 0 / 1 / 2, $( ) prints, the caller's locale and
#     nocasematch do not matter;
#   * the file: missing -> kbAltChar and one debug line, never an error;
#     loads under set -eu; holds only comments, declarations, assignments and
#     the variants' guard; the whole path fork-free (PATH='').

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVK_TESTS_DIR/.." && pwd)/fv.keyboard.sh"
DATA="$(cd "$FVK_TESTS_DIR/.." && pwd)/fv.keyboard.layouts.sh"

kt_test_section "012: the layout tables"

E=$'\e'
# reset — the tables forgotten (as before the first need)
reset() { __FV_KB_LTOK=0 __FV_KB_LRAW='' __FV_KB_LBAD=' '; __FV_KB_LT=(); unset __FV_KL_ORDER __FV_KL_D __FV_KL_S __FV_KL_V __FV_KL_VERSION __FV_KL_NOTAB __FV_KL_VX; }
chk() {   # BYTES KEY CHAR BASE [NOTE]
    fvk_vis "$1"
    kt_test_start "decode $REPLY -> $2 char='$3' base='$4'${5:+ ($5)}"
    fv.keyboard.decode "$1"
    if [[ $FV_KEY == "$2" && $FV_KEY_CHAR == "$3" && $FV_KEY_BASE == "$4" && $FV_KEY_SEQ == "$1" ]]; then kt_test_pass "ok"
    else kt_test_fail "got $FV_KEY char='$FV_KEY_CHAR' base='$FV_KEY_BASE'"; fi
}

# --- the lazy load ------------------------------------------------------------------
reset
kt_test_start "plain typing never loads the tables: ASCII, Cyrillic, CJK, emoji, CSI keys, Alt + ASCII, Ctrl, a CSI u report with its base"
for s in a Z ' ' 'ж' 'Ж' '中' $'\xf0\x9f\x98\x80' "${E}[A" "${E}[1;5D" "${E}f" "${E}F" "${E}1" "${E};" $'\x06' "${E}[1072::102;3u" "${E}[102;5u"; do
    fv.keyboard.decode "$s"
done
if (( ! __FV_KB_LTOK )) && [[ -z ${__FV_KL_ORDER-} ]]; then kt_test_pass "not loaded"; else kt_test_fail "loaded (LTOK=$__FV_KB_LTOK)"; fi

kt_test_start "the first legacy Alt + non-ASCII key loads them (default order, the default tables only, no variants)"
fv.keyboard.decode "${E}а"
if (( __FV_KB_LTOK )) && [[ $FV_KEY == kbAltF && -n ${__FV_KL_ORDER-} && -z ${__FV_KL_V[*]+x} ]] && (( ${#__FV_KB_LT[@]} > 400 )); then
    kt_test_pass "${#__FV_KB_LT[@]} characters, order: $__FV_KL_ORDER"
else
    kt_test_fail "LTOK=$__FV_KB_LTOK key=$FV_KEY order=${__FV_KL_ORDER-} variants=${__FV_KL_V[*]+yes}"
fi

kt_test_start "loaded once: the next keys and an FV_KBD_LAYOUT change rebuild from memory (the file is not read again)"
__FV_KL_D[gr]=${__FV_KL_D[gr]//'[φ]=f'/'[φ]=q'}       # a mark only memory holds
fv.keyboard.decode "${E}φ"; r=$FV_KEY
FV_KBD_LAYOUT=gr fv.keyboard.decode "${E}φ"; r+=" $FV_KEY"
if [[ $r == 'kbAltF kbAltQ' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi
reset

# --- the design's rows ---------------------------------------------------------------
chk "${E}а" kbAltF 'а' f 'Alt+F, Russian'
chk "${E}А" kbAltF 'А' f 'Alt+Shift+F, Russian'
chk "${E}φ" kbAltF 'φ' f 'Alt+F, Greek'
chk "${E}Φ" kbAltF 'Φ' f 'Alt+Shift+F, Greek'
chk "${E}כ" kbAltF 'כ' f 'Alt+F, Hebrew'
chk "${E}ب" kbAltF 'ب' f 'Alt+F, Arabic'
chk "${E}ч" kbAltX 'ч' x 'Alt+X, Russian: the status line kbAltX'
chk "${E}Ч" kbAltX 'Ч' x 'Alt+Shift+X, Russian'
chk "${E}ж" kbAltSemiCol 'ж' ';' 'the ; key, Russian'
chk "${E}э" kbAltQuote 'э' "'" "the ' key, Russian"
chk "${E}ё" kbAltOpQuote 'ё' '`' 'the ` key, Russian'
chk "${E}х" kbAltLftBrack 'х' '[' 'the [ key, Russian'
chk "${E}б" kbAltComma 'б' ',' 'the , key, Russian'
chk "${E}ю" kbAltPeriod 'ю' '.' 'the . key, Russian'
chk "${E}ї" kbAltRgtBrack 'ї' ']' 'Ukrainian ї (not in ru: from ua)'
chk "${E}і" kbAltS 'і' s 'Ukrainian і (ua before by and kz)'
chk "${E}ა" kbAltA 'ა' a 'Georgian'
chk "${E}ե" kbAltF 'ե' f 'Armenian'
chk "${E}ด" kbAltF 'ด' f 'Thai'
chk "${E}پ" kbAltM 'پ' m 'Persian پ (not in ara: from ir)'
chk "${E}ء" kbAltX 'ء' x 'Arabic ء: ara before ir'
chk "${E}é" kbAltChar 'é' '' 'a Latin letter: in no default table'
chk "${E}中" kbAltChar '中' '' 'CJK: in no table'

# --- resolution -------------------------------------------------------------------------
kt_test_start "the Bulgarian phonetic example (§14.6): ф is A by the Cyrillic default, F with FV_KBD_LAYOUT=bg_phonetic"
reset
fv.keyboard.decode "${E}ф"; r=$FV_KEY
FV_KBD_LAYOUT=bg_phonetic fv.keyboard.decode "${E}ф"; r+=" $FV_KEY"
FV_KBD_LAYOUT='bg(phonetic)' fv.keyboard.decode "${E}ф"; r+=" $FV_KEY"
fv.keyboard.decode "${E}ф"; r+=" $FV_KEY"
if [[ $r == 'kbAltA kbAltF kbAltF kbAltA' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "FV_KBD_LAYOUT is a list, first wins; a default-set name needs no variant; spaces ignored"
reset
r=''
FV_KBD_LAYOUT='bg,ru' fv.keyboard.decode "${E}а"; r+="$FV_KEY "             # bg (BDS): а is d
FV_KBD_LAYOUT='ru, bg' fv.keyboard.decode "${E}а"; r+="$FV_KEY "
FV_KBD_LAYOUT='rs' fv.keyboard.decode "${E}а"; r+="$FV_KEY "                # Serbian: а is a
FV_KBD_LAYOUT='ru(phonetic)' fv.keyboard.decode "${E}в"; r+="$FV_KEY"      # phonetic: в is w
if [[ $r == 'kbAltD kbAltF kbAltA kbAltW' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "an unknown FV_KBD_LAYOUT name is skipped (the rest apply) with one debug line per name"
reset
err="$(VERBOSE_KKLASS=debug; FV_KBD_LAYOUT='nosuch,bg_phonetic' fv.keyboard.decode "${E}ф" 2>&1 >/dev/null; printf '|%s' "$FV_KEY")"
n=$(grep -c "FV_KBD_LAYOUT names 'nosuch'" <<<"$err")
if [[ $err == *'|kbAltF' && $n == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "got [$err] n=$n"; fi

# locale CASE...: a child bash per case, the unit loaded under that locale
loc() {   # TITLE ENV-ASSIGNMENTS BYTES WANT
    local got
    kt_test_start "$1"
    got="$(env -u LC_ALL -u LC_CTYPE -u LANG $2 bash -c "source '$UNIT' 2>/dev/null; fv.keyboard.decode \$'$3'; printf '%s %s' \"\$__FV_KB_LOC\" \"\$FV_KEY\"")"
    if [[ $got == "$4" ]]; then kt_test_pass "$got"; else kt_test_fail "got [$got] want [$4]"; fi
}
loc "the locale bg_BG -> bg (BDS): ф is B" 'LANG=bg_BG.UTF-8' '\eф' 'bg kbAltB'
loc "the locale sr_RS (LC_ALL) -> rs: а is A" 'LC_ALL=sr_RS.UTF-8' '\eа' 'rs kbAltA'
loc "the locale fa_IR -> ir: ء is M (the default ara says X)" 'LANG=fa_IR.UTF-8' '\eء' 'ir kbAltM'
loc "the locale uk_UA -> ua: Ukrainian ч is X" 'LANG=uk_UA.UTF-8' '\eч' 'ua kbAltX'
loc "a Latin-script locale (sr_RS@latin) has no table: the per-script default (ru: а is F)" 'LANG=sr_RS.UTF-8@latin' '\eа' ' kbAltF'
loc "mk_MK@latin: no table" 'LANG=mk_MK@latin' '\eа' ' kbAltF'
loc "LC_CTYPE=bg_BG names a layout, LANG=en_US does not: bg" 'LANG=en_US.UTF-8 LC_CTYPE=bg_BG.UTF-8' '\eф' 'bg kbAltB'
loc "LC_ALL=C.UTF-8 is set: it decides (POSIX), LANG=bg_BG is not read" 'LC_ALL=C.UTF-8 LANG=bg_BG.UTF-8' '\eф' ' kbAltA'
loc "LC_CTYPE=en_US is set: it decides over LANG=bg_BG" 'LC_CTYPE=en_US.UTF-8 LANG=bg_BG.UTF-8' '\eф' ' kbAltA'
loc "LC_ALL=uk_UA over LC_CTYPE=bg_BG and LANG=bg_BG" 'LC_ALL=uk_UA.UTF-8 LC_CTYPE=bg_BG.UTF-8 LANG=bg_BG.UTF-8' '\eф' 'ua kbAltA'
loc "an empty LC_ALL counts as not set: LANG=bg_BG" 'LC_ALL= LANG=bg_BG.UTF-8' '\eф' 'bg kbAltB'
loc "no locale variable: the per-script default (ru): ф is A" '' '\eф' ' kbAltA'
loc "the locale en_US: the per-script default" 'LANG=en_US.UTF-8' '\eф' ' kbAltA'

# --- symbols, Greek capital sigma, Latin layout names (the 3L review) -----------------------
chk "${E}§" kbAltChar '§' '' 'a symbol Latin-layout typists type (German Shift+3): not in the default tables'
chk "${E}€" kbAltChar '€' '' 'the euro sign (bg has it on the = key): not by default'
chk "${E}№" kbAltChar '№' '' 'the numero sign (ru Shift+3): not by default'
chk "${E}×" kbAltChar '×' '' 'the multiplication sign (ara): not by default'
chk "${E}“" kbAltChar '“' '' 'a quotation mark (ge, bg, mk): not by default'
chk "${E}Σ" kbAltS 'Σ' s 'Greek capital sigma: the key of small sigma (S), not of final sigma (W)'
chk "${E}ς" kbAltW 'ς' w 'Greek final sigma: W'

kt_test_start "a layout FV_KBD_LAYOUT names brings its symbols: bg ESC € = the = key, ru ESC № = 3; the locale's layout does not"
reset
r=''
FV_KBD_LAYOUT=bg fv.keyboard.decode "${E}€"; r+="$FV_KEY:$FV_KEY_BASE "
FV_KBD_LAYOUT=ru fv.keyboard.decode "${E}№"; r+="$FV_KEY:$FV_KEY_BASE "
FV_KBD_LAYOUT=ru fv.keyboard.decode "${E}€"; r+="$FV_KEY "
fv.keyboard.decode "${E}№"; r+="$FV_KEY "
fv.keyboard.layoutBase '€' >/dev/null; r+="$?"
got="$(env -u LC_ALL -u LC_CTYPE LANG=bg_BG.UTF-8 bash -c "source '$UNIT' 2>/dev/null; fv.keyboard.decode \$'\\e€'; printf '%s %s' \"\$__FV_KB_LOC\" \"\$FV_KEY\"")"
if [[ $r == 'kbAltEqual:= kbAlt3:3 kbAltChar kbAltChar 1' && $got == 'bg kbAltChar' ]]; then kt_test_pass "$r / $got"; else kt_test_fail "got $r / $got"; fi

kt_test_start "Latin layout names in FV_KBD_LAYOUT (us, de_nodeadkeys, fr(azerty)) are skipped without a word and without loading the variants"
reset
err="$(VERBOSE_KKLASS=debug; FV_KBD_LAYOUT='us,de_nodeadkeys,fr(azerty),ru' fv.keyboard.decode "${E}ф" 2>&1 >/dev/null
       printf '|%s|%s' "$FV_KEY" "${__FV_KL_V[*]+loaded}")"
if [[ $err == '|kbAltA|' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$err]"; fi

kt_test_start "a variant with a table inside a Latin layout's file (us_rus) still loads; a name of no file at all still says so"
reset
err="$(VERBOSE_KKLASS=debug; FV_KBD_LAYOUT='us_rus' fv.keyboard.decode "${E}в" 2>&1 >/dev/null; printf '|%s' "$FV_KEY"
       FV_KBD_LAYOUT='xx' fv.keyboard.decode "${E}в" 2>&1 >/dev/null)"
if [[ $err == '|kbAltW'*"FV_KBD_LAYOUT names 'xx'"* ]]; then kt_test_pass "ok"; else kt_test_fail "got [$err]"; fi

kt_test_start "FV_KBD_LAYOUT wins over the locale"
got="$(env -u LC_ALL -u LC_CTYPE LANG=bg_BG.UTF-8 FV_KBD_LAYOUT=ru bash -c "source '$UNIT' 2>/dev/null; fv.keyboard.decode \$'\\eф'; printf '%s' \"\$FV_KEY\"")"
if [[ $got == kbAltA ]]; then kt_test_pass "$got"; else kt_test_fail "got $got"; fi

# --- layoutBase ----------------------------------------------------------------------------
kt_test_start "layoutBase: rc 0 + RESULT, rc 1 + '' for a character in no table, rc 2 for no argument"
reset
r=''
fv.keyboard.layoutBase 'ф'; r+="$?:$RESULT "
fv.keyboard.layoutBase 'Ч'; r+="$?:$RESULT "
fv.keyboard.layoutBase 'é'; r+="$?:$RESULT "
fv.keyboard.layoutBase 'q'; r+="$?:$RESULT "
fv.keyboard.layoutBase 2>/dev/null; r+="$?:$RESULT "
fv.keyboard.layoutBase '' 2>/dev/null; r+="$?:$RESULT "
fv.keyboard.layoutBase a b 2>/dev/null; r+="$?"
if [[ $r == '0:a 0:x 1: 1: 2: 2: 2' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "layoutBase inside \$( ) prints its answer; a C-locale and a nocasematch caller get the same"
r="$(fv.keyboard.layoutBase 'ш')"
r+=" $(LC_ALL=C; fv.keyboard.layoutBase 'ш')"
r+=" $(shopt -s nocasematch; fv.keyboard.layoutBase 'Ш'; shopt -q nocasematch && printf ':nc')"
if [[ $r == 'i i i:nc' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "the first layoutBase loads the tables (no key needed)"
reset
fv.keyboard.layoutBase 'ψ' >/dev/null
if (( __FV_KB_LTOK )) && [[ $RESULT == c ]]; then kt_test_pass "ok"; else kt_test_fail "LTOK=$__FV_KB_LTOK RESULT=$RESULT"; fi

# --- the file -------------------------------------------------------------------------------
kt_test_start "a missing tables file: kbAltChar, layoutBase rc 1, one debug line; nothing fails"
reset
saved=$__FV_KB_DIR
__FV_KB_DIR=$FVK_TMP/none
err="$(VERBOSE_KKLASS=debug; fv.keyboard.decode "${E}а" 2>&1 >/dev/null; printf '|%s|%s' "$FV_KEY" "$FV_KEY_CHAR"
       fv.keyboard.layoutBase 'а' 2>/dev/null >/dev/null; printf '|%s' "$?")"
__FV_KB_DIR=$saved
reset
if [[ $err == *'no layout tables'*'|kbAltChar|а|1' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$err]"; fi

kt_test_start "the tables and their variants load under set -eu"
out="$(bash -c "set -eu
source '$UNIT'
fv.keyboard.decode \$'\\eа'; [[ \$FV_KEY == kbAltF ]]
FV_KBD_LAYOUT=bg_phonetic,nosuch fv.keyboard.layoutBase \$'\\xd1\\x84' >/dev/null; [[ \$RESULT == f ]]
fv.keyboard.decode \$'\\e[1072;3u'; [[ \$FV_KEY == kbAltF ]]
printf OK" 2>&1)"
if [[ $out == OK ]]; then kt_test_pass "ok"; else kt_test_fail "out=[$out]"; fi

kt_test_start "the whole path is fork-free: load, variants, lookups, a CSI u table lookup with PATH=''"
reset
saved=$PATH
PATH=''
r=''
fv.keyboard.decode "${E}а"; r+="$FV_KEY "
FV_KBD_LAYOUT=bg_phonetic fv.keyboard.decode "${E}ф"; r+="$FV_KEY "
fv.keyboard.layoutBase 'ч'; r+="$RESULT "
fv.keyboard.decode "${E}[1072;5u"; r+="$FV_KEY"
PATH=$saved
if [[ $r == 'kbAltF kbAltF x kbCtrlF' ]]; then kt_test_pass "$r"; else kt_test_fail "got $r"; fi

kt_test_start "fv.keyboard.layouts.sh: only comments, declare -g / -gA, table assignments, the two name lists and the variants' guard; bash -n clean"
bad='' n=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    case $l in
        '#'*|'') ;;
        "declare -g __FV_KL_VERSION='"*"'"|"declare -g __FV_KL_ORDER='"*"'"|'declare -gA __FV_KL_D=() __FV_KL_S=()'|'declare -gA __FV_KL_V=()') ;;
        "__FV_KL_D["[a-z]*"]=\$'"*"'"|"__FV_KL_S["[a-z]*"]=\$'"*"'"|"__FV_KL_V['"*"']=\$'"*"'") ;;
        "__FV_KL_NOTAB=' "*" '"|"__FV_KL_VX=' "*" '") ;;
        'if [[ ${__FV_KL_ALL-} != 1 ]]; then return 0; fi') ;;
        *) bad+=" $n" ;;
    esac
done < "$DATA"
if [[ -z $bad ]] && bash -n "$DATA" 2>/dev/null; then kt_test_pass "$n lines"; else kt_test_fail "lines:$bad"; fi

kt_test_start "the default tables hold every letter of the Russian, Greek and Hebrew main block, both cases"
reset
miss=''
for c in й ц у к е н г ш щ з х ъ ф ы в а п р о л д ж э я ч с м и т ь б ю ё Й Ц У К Е Н Г Ш Щ З Х Ъ Ф Ы В А П Р О Л Д Ж Э Я Ч С М И Т Ь Б Ю Ё \
         ς ε ρ τ υ θ ι ο π α σ δ φ γ η ξ κ λ ζ χ ψ ω β ν μ Ε Ρ Τ Υ Θ Ι Ο Π Α Σ Δ Φ Γ Η Ξ Κ Λ Ζ Χ Ψ Ω Β Ν Μ \
         ק ר א ט ו ן ם פ ש ד ג כ ע י ח ל ך ף ז ס ב ה נ מ צ ת ץ; do
    fv.keyboard.layoutBase "$c" >/dev/null || miss+=" $c"
done
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

reset
kt_test_log "012_Layouts.sh completed"
