#!/usr/bin/env bash
# 004_Glibc.sh - the external reference: charWidth against glibc's wcwidth() for
# every code point glibc knows. The table follows the glibc 2.41 width rules, so
# per code point there must be no difference at all (the RI-pair and VS16 rules
# of fv.video are cluster rules, not code point widths). Runs only where the
# reference exists: Linux with glibc whose UTF-8 charmap says "Unicode 16.0.0"
# (glibc 2.41, e.g. Debian 13 / the lab VM), python3 (ctypes calls wcwidth) and
# a C.UTF-8 locale; anywhere else SKIP: ENV.
#
# Not compared (counted in the log): code points where wcwidth() is -1 (glibc
# does not list them: unassigned code points, controls, surrogates; the table
# gives unassigned ones the width East_Asian_Width / Default_Ignorable_Code_Point
# assign) and U+0000 (wcwidth 0; a bash string cannot hold a NUL).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvu_testlib.sh"
fvu_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: glibc wcwidth"

why=''
cm=/usr/share/i18n/charmaps/UTF-8.gz
if [[ $OSTYPE != linux-gnu* ]]; then why="not Linux with glibc (OSTYPE $OSTYPE)"
elif [[ ! -r $cm ]]; then why="no $cm"
else
    ver="$(gzip -dc "$cm" 2>/dev/null | grep -m1 'Character width according to Unicode')"
    if [[ $ver != *'Unicode 16.0.0.'* ]]; then why="glibc's width data is not Unicode 16.0.0 (${ver:-no width line})"
    elif ! command -v python3 >/dev/null 2>&1; then why="no python3 (it calls wcwidth through ctypes)"
    fi
fi

kt_test_start "charWidth == glibc wcwidth for every code point glibc knows (Unicode 16.0.0)"
if [[ -n $why ]]; then
    kt_test_pass "SKIP: ENV: $why"
else
    # runs "START END WIDTH" of wcwidth over 0..10FFFF in C.UTF-8
    py='
import ctypes, locale, sys
locale.setlocale(locale.LC_CTYPE, "C.UTF-8")
f = ctypes.CDLL(None).wcwidth
f.argtypes = [ctypes.c_int]
f.restype = ctypes.c_int
s = 0
p = f(0)
for c in range(1, 0x110000):
    w = f(c)
    if w != p:
        print(s, c - 1, p)
        s, p = c, w
print(s, 0x10FFFF, p)
'
    if ! python3 -c "$py" > "$FVU_TMP/runs" 2> "$FVU_TMP/py.err"; then
        kt_test_pass "SKIP: ENV: the python3 probe failed: $(head -c 200 "$FVU_TMP/py.err")"
    else
        n=0 unk=0 bad='' nb=0
        while read -r s e w; do
            if (( w < 0 )); then unk=$(( unk + e - s + 1 )); continue; fi
            for (( c = s; c <= e; c++ )); do
                (( c == 0 )) && continue
                fv.unicode.charWidth "$c"
                if [[ $RESULT != "$w" ]]; then
                    nb=$(( nb + 1 ))
                    if (( nb <= 20 )); then printf -v bad '%s U+%04X=%s(glibc %s)' "$bad" "$c" "$RESULT" "$w"; fi
                fi
                n=$(( n + 1 ))
            done
        done < "$FVU_TMP/runs"
        if (( nb == 0 && n > 100000 )); then
            kt_test_pass "$n code points equal; $unk where wcwidth is -1 not compared"
        else
            kt_test_fail "$nb of $n differ:$bad"
        fi
    fi
fi

kt_test_log "004_Glibc.sh completed"
