#!/usr/bin/env bash
# 015_Demo.sh - examples/demo.sh run headless as a user (or CI) runs it (the
# live mode is the owner's: never run here):
#   * --headless with the built-in script (every window key, a mouse drag,
#     Alt+X): rc 0, nothing on stderr, frames written to --out, the final
#     screen printed (the status line's items, a window's frame and text);
#   * --keys FILE: F2 (tile) then Alt+X: both windows side by side with their
#     titles; a key file without Alt+X ends at its end (rc 0); --size;
#     FV_APP_HEADLESS=1 in the environment is --headless;
#   * the refusals: an unknown option, a bad --size, --keys without
#     --headless (rc 2, one line on stderr, no terminal touched).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "015: the headless demo"

DEMO=$FVA_TESTS_DIR/../examples/demo.sh
T=$FVW_TMP

kt_test_start "--headless, the built-in script: rc 0, no stderr, frames in --out, the final screen on stdout (24 rows, the status line, a window)"
timeout -k 5 120 bash "$DEMO" --headless --out "$T/frames" > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
fs=$(wc -c < "$T/frames"); fs=${fs//[!0-9]/}
if [[ $rc == 0 && ! -s $T/err && ${#s[@]} == 24 && ${s[23]} == ' Alt+X Exit  F6 Next  F5 Zoom  Ctrl+F5 Move  F2 Tile  F3 Cascade'* && ${s[0]} == '╔═[■]'*'Notes'* && ${s[2]} == '║ The units under this demo:'* ]] && (( fs > 1000 )); then
    kt_test_pass "ok ($fs bytes of frames)"
else
    kt_test_fail "rc $rc rows ${#s[@]} frames $fs err [$(head -c 300 "$T/err")] [${s[0]-}] [${s[23]-}]"
fi

kt_test_start "--keys FILE: F2 (tile) and Alt+X: the two windows tiled (FV: one above the other at 80x23), each with its title and text"
printf '\033[12~\033x' > "$T/k1"
timeout -k 5 120 bash "$DEMO" --headless --keys "$T/k1" > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
if [[ $rc == 0 && ! -s $T/err && ${s[0]} == *About* && ${s[2]} == *"This is Free Vision"* && ${s[11]} == *Notes* && ${s[13]} == *"The units"* ]]; then kt_test_pass "ok"; else kt_test_fail "rc $rc err [$(head -c 300 "$T/err")] [${s[0]-}] [${s[2]-}]"; fi

kt_test_start "a key file without Alt+X ends at its end (rc 0); --size 100x30; FV_APP_HEADLESS=1 is --headless"
printf '\033[17~' > "$T/k2"
FV_APP_HEADLESS=1 timeout -k 5 120 bash "$DEMO" --keys "$T/k2" --size 100x30 > "$T/screen" 2> "$T/err"; rc=$?
mapfile -t s < "$T/screen"
if [[ $rc == 0 && ! -s $T/err && ${#s[@]} == 30 && ${#s[29]} == 100 && ${s[29]} == ' Alt+X Exit'* ]]; then kt_test_pass "ok"; else kt_test_fail "rc $rc rows ${#s[@]} err [$(head -c 300 "$T/err")] [${s[29]-}]"; fi

kt_test_start "the refusals: an unknown option, a bad --size, --keys without --headless: rc 2, one line on stderr"
r=''
for a in '--bogus' '--headless --size 80' '--keys x'; do
    # shellcheck disable=SC2086
    FV_APP_HEADLESS='' timeout -k 5 60 bash "$DEMO" $a > "$T/screen" 2> "$T/err" < /dev/null; rc=$?
    mapfile -t el < "$T/err"
    r+="$rc/${#el[@]}/$(wc -c < "$T/screen" | tr -d ' ') "
done
if [[ $r == '2/1/0 2/1/0 2/1/0 ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "015_Demo.sh completed"
