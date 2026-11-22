#!/usr/bin/env bash
# 016_MenuLayout.sh - the menus' hot letters with any keyboard layout (P3
# §7.2 / §14.4, D30; FPC 2025's menus.inc: "Path 1" the typed character,
# "Path 2" the scan code -> here the base-layout key, fv.views.hotKeyIs'
# order): a Cyrillic hot letter (~Ф~айл) found by its typed character, also
# typed upper case; a Latin hot letter (~F~ile) found by the base key of a
# Russian Alt+а (kbAltF, typed а, base f) — the typed character first, so
# with titles in two scripts (~Ф~айл and ~A~bout) Russian Alt+Ф (typed ф on
# the US a key) opens Файл and US Alt+A opens About; an ASCII typed
# character never also counts as its base key (AZERTY Alt+A on the US q
# key finds no ~Q~); plain letters in an open box: the typed character,
# then FV_EV_BASE, then the layout tables (fv.keyboard.layoutBase).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "016: hot letters and layouts"

fva_app 80 24 TMyApp
fv.menus.menuBar \
    sub '~Ф~айл' item '~О~ткрыть' F3 kbF3 cmOpen 0 item '~Z~oom' '' '' cmZoomIt 0 end \
    sub '~A~bout' item '~I~nfo' '' '' cmInfo 0 end \
    sub '~F~ile' item '~O~pen' '' '' cmOpenL 0 item '~Q~uit' '' '' cmQuitL 0 end
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0
closed() { fvm_nobox && fvw_full app && echo 0; }
OPEN=''
op() { fvm_box; local m="${REPLY}_data[Menu]"; OPEN+="${!m-none};"; }
cmds() { REPLY=''; local x=$FVA_GOT; while [[ $x == *evCommand:* ]]; do x=${x#*evCommand:}; REPLY+="${x%%;*},"; done; REPLY=${REPLY//cmMenu,/}; }
runq() { FVA_GOT=''; OPEN=''; fva_events "$@"; app.Run; __FV_VW_EOF=0; cmds; }

runq 'key kbAltA ф a' 'run op' 'key kbEsc'
fvw_check "Russian Alt+Ф (typed ф on the US a key): the typed character wins -> Файл, not About" "app__fvmenubar:1;|0" "$OPEN|$(closed)"
runq 'key kbAltA Ф a' 'run op' 'key kbEsc'
fvw_check "typed upper case (Alt+Shift+Ф): folded -> Файл" "app__fvmenubar:1;" "$OPEN"
runq 'key kbAltA a' 'run op' 'key kbEsc'
fvw_check "US Alt+A (typed a): About" "app__fvmenubar:2;" "$OPEN"
runq 'key kbAltF а f' 'run op' 'key kbEsc'
fvw_check "Russian Alt+а on the US f key (kbAltF, typed а, base f): no Cyrillic а title -> the base key -> File" "app__fvmenubar:3;" "$OPEN"
runq 'key kbAltA a q' 'run op'
fvw_check "AZERTY Alt+A (typed a, base q): an ASCII typed character never counts as its base key — About, not ~Q~" "app__fvmenubar:2;" "$OPEN"
fvw_check "closed: == a full repaint" "0" "$(closed)"

# plain letters inside an open box
runq 'key kbAltF f' 'key kbChar щ o'
fvw_check "a plain Russian щ (on the US o key, FV_EV_BASE o) in File's box: Open by the base key" "cmOpenL," "$REPLY"
runq 'key kbAltA ф a' 'key kbChar о'
fvw_check "a plain Cyrillic о in Файл's box: Открыть by the typed character" "cmOpen," "$REPLY"
FV_KBD_LAYOUT=ru
runq 'key kbAltF f' 'key kbChar й'
fvw_check "a plain й without FV_EV_BASE: the layout tables (ru: й on the US q key) -> Quit" "cmQuitL," "$REPLY"
unset FV_KBD_LAYOUT
runq 'key kbAltF f' 'key kbChar z q'
fvw_check "a plain ASCII z with FV_EV_BASE q in File's box: nothing (no ~Z~; an ASCII typed character never counts as its base: not Quit)" "|0" "$REPLY|$(closed)"

# Alt + a Cyrillic letter inside a box goes to the top menu
runq 'key kbAltF f' 'key kbAltA ф a' 'run op' 'key kbEsc'
fvw_check "Alt+Ф inside File's box: Файл's box (the event goes up to the bar)" "app__fvmenubar:1;|0" "$OPEN|$(closed)"

fva_unapp
kt_test_log "016_MenuLayout.sh completed"
