#!/usr/bin/env bash
# 024_Demo.sh - examples/widgets.sh (the P3 showcase, stage 3g) run headless
# as a user (or CI) runs it (the live mode is the owner's: never run here;
# fv.app's 015_Demo.sh is the model):
#   * --headless with the built-in script (marks in both panels, File > Find:
#     the dialog filled in — a copy, a paste, a password, a check box, a
#     radio button — and confirmed, the result's message box, F2: the input
#     box renames the focused file, Help > About, Alt+X): rc 0, nothing on
#     stderr, the final screen (the menu bar, both panels' titles and names,
#     the renamed file, the status line) and the frames (the dialog's
#     values, the masked password, the result, the About box were drawn);
#   * --keys FILE: F2, a new name, Enter, Alt+X: the left panel's first file
#     renamed; a key file without Alt+X ends at its end (rc 0); --size;
#     FV_APP_HEADLESS=1 in the environment is --headless;
#   * the refusals: an unknown option, a bad --size, --keys without
#     --headless (rc 2, one line on stderr, no terminal touched).
# Each run is under timeout(1) (ktest's KT_TIMEOUT); without one the cases
# are SKIP: ENV.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "024: the headless widgets demo"

DEMO=$FVG_TESTS_DIR/../examples/widgets.sh
T=$FVW_TMP
# demo SECONDS ARG... — the demo under the test's bash, killed after SECONDS
demo() { TMPDIR=$T "$KT_TIMEOUT" -k 5 "$1" "$BASH" "$DEMO" "${@:2}"; }

kt_test_start "--headless, the built-in script: rc 0, no stderr, the final screen (menu bar, panels, the renamed file, status line), the frames (dialog values, password mask, the result, About)"
if ! kt_need_timeout; then kt_test_pass "SKIP: ENV: $KT_TIMEOUT_WHY"; else
demo 300 --headless --out "$T/frames" > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
f=$(< "$T/frames")
bad=''
[[ $rc == 0 && ! -s $T/err && ${#s[@]} == 24 ]] || bad+=" [rc $rc, ${#s[@]} rows, err $(head -c 300 "$T/err")]"
[[ ${s[0]-} == ' File  Edit  Window  Help '* ]] || bad+=" [bar: ${s[0]-}]"
[[ ${s[1]-} == *' Files '*' Отчёты '* ]] || bad+=" [titles: ${s[1]-}]"
[[ ${s[2]-} == *'report_001.txt'*'Отчёт_001.txt'* ]] || bad+=" [row 2: ${s[2]-}]"
[[ ${s[3]-} == *'report_002.txt'*'Итоги_2026.txt'* ]] || bad+=" [row 3: ${s[3]-}]"
[[ ${s[23]-} == ' Alt+X Exit  F10 Menu  F3 Find  F2 Rename  F6 Next'* ]] || bad+=" [status: ${s[23]-}]"
for w in 'Find files' 'notes/2026' '******' 'whole words, regex, UTF-8' 'a password of 6 characters' 'kcl fv: Free Vision in bash'; do
    [[ $f == *"$w"* ]] || bad+=" [frames lack '$w']"
done
if [[ -z $bad ]]; then kt_test_pass "ok (${#f} bytes of frames)"; else kt_test_fail "$bad"; fi
fi

kt_test_start "--keys FILE: F2, a new name, Enter, Alt+X: the left panel's first file renamed"
if ! kt_need_timeout; then kt_test_pass "SKIP: ENV: $KT_TIMEOUT_WHY"; else
printf '\033[12~new_name.txt\r\033x' > "$T/k1"
demo 120 --headless --keys "$T/k1" > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
if [[ $rc == 0 && ! -s $T/err && ${s[2]-} == '║ new_name.txt '*'Отчёт_001.txt'* ]]; then kt_test_pass "ok"; else kt_test_fail "rc $rc err [$(head -c 300 "$T/err")] [${s[2]-}]"; fi
fi

kt_test_start "a key file without Alt+X ends at its end (rc 0); --size 100x30; FV_APP_HEADLESS=1 is --headless"
if ! kt_need_timeout; then kt_test_pass "SKIP: ENV: $KT_TIMEOUT_WHY"; else
printf '\033[17~' > "$T/k2"
FV_APP_HEADLESS=1 demo 120 --keys "$T/k2" --size 100x30 > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
if [[ $rc == 0 && ! -s $T/err && ${#s[@]} == 30 && ${#s[29]} == 100 && ${s[29]} == ' Alt+X Exit'* && ${s[0]} == ' File  Edit'* ]]; then kt_test_pass "ok"; else kt_test_fail "rc $rc rows ${#s[@]} err [$(head -c 300 "$T/err")] [${s[29]-}]"; fi
fi

kt_test_start "the refusals: an unknown option, a bad --size, --keys without --headless: rc 2, one line on stderr"
if ! kt_need_timeout; then kt_test_pass "SKIP: ENV: $KT_TIMEOUT_WHY"; else
r=''
for a in '--bogus' '--headless --size 80' '--keys x'; do
    # shellcheck disable=SC2086
    FV_APP_HEADLESS='' demo 60 $a > "$T/screen" 2> "$T/err" < /dev/null; rc=$?
    mapfile -t el < "$T/err"
    r+="$rc/${#el[@]}/$(wc -c < "$T/screen" | tr -d ' ') "
done
if [[ $r == '2/1/0 2/1/0 2/1/0 ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
fi

kt_test_log "024_Demo.sh completed"
