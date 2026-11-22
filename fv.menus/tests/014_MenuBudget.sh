#!/usr/bin/env bash
# 014_MenuBudget.sh - the menus' call budget (P3 §8.1, §8.4; counting shims of
# fv.views' test lib, an application with the design's TMyApp — a
# HandleEvent override with `inherited`): F10 -> the bar -> Down drops the
# box -> Esc closes both (FV's flow: the focus broadcasts reach TMyApp) at
# most 24 dispatches / 28 writes; a highlight move in the box with the
# status line's hint changing 0 dispatches / 3 writes (2 one-row drawParts
# + the status line), without a hint change 2 writes; the same move in a
# 40-item box (item independence); the bar's draw and the box's draw one
# write each; no leak: 100 open / drop / close cycles leave no instance,
# no array and no entry behind.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "014: the menus' call budget"

fva_app 80 24 TMyApp
fvm_menu
fv.menus.setHint "$FV_STATUSLINE" 1001 'Open a file'
fv.menus.setHint "$FV_STATUSLINE" 1002 'Save the file'
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0

runit() { app.Run; __FV_VW_EOF=0; }
fva_events 'key kbF10' 'nothing' 'key kbDown' 'nothing' 'key kbEsc' 'nothing'
fvw_budgetw menu.open-drop-close 24 runit
kt_test_start "menu.open-drop-close: at most 28 writes (§8.1)"
if (( FVW_LASTW <= 28 )); then kt_test_pass "$FVW_LASTW writes"; else kt_test_fail "$FVW_LASTW writes"; fi

M=''
mark() { fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0; }
done_() { M+="$FVW_CALLS/$FVW_WRITES;"; fvw_count_off; fvw_writes_off; }
fva_events 'key kbF10' 'nothing' 'key kbDown' 'nothing' 'run mark' 'key kbDown' 'nothing' 'run done_' \
    'run mark' 'key kbUp' 'nothing' 'run done_' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fva_events 'key kbAltW w' 'nothing' 'run mark' 'key kbDown' 'nothing' 'run done_' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fvw_check "a highlight move in the box: with the hint changing 0 dispatches / 3 writes (Down, Up); without (Next -> Layout) 0 / 2" \
    "0/3;0/3;0/2;" "$M"
kt_test_log "# calls menu.down $(( ${M%%/*} ))"
kt_test_log "# writes menu.down 3"

BD=''
bdraw() { fvm_box; fvw_writes_on; FVW_WRITES=0; fv.views.drawView "$REPLY"; BD+="$FVW_WRITES,"; fvw_writes_off; fvw_writes_on; FVW_WRITES=0; fv.views.drawView "$FV_MENUBAR"; BD+="$FVW_WRITES"; fvw_writes_off; }
fva_events 'key kbF10' 'key kbDown' 'run bdraw' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fvw_check "the box's draw: its Draw one writeLines + the painter's two shadow writes; the bar's: one write" "3,1" "$BD"

# 40 items: the move costs the same
L=()
for (( i = 0; i < 40; i++ )); do L+=(item "Item ~$(( i % 10 ))~ $i" '' '' "cmI$i" 0); done
fv.menus.menuBar sub '~L~ong' "${L[@]}" end
M=''
fva_events 'key kbF10' 'key kbDown' 'key kbEnd' 'nothing' 'run mark' 'key kbUp' 'nothing' 'run done_' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fvw_check "the same move in a 40-item box (moved up to fit, FV; End then Up): 0 dispatches / 2 writes" "0/2;" "$M"
fvw_check "the screen == a full repaint" "0" "$(fvm_nobox && fvw_full app && echo 0)"
fvm_menu

kt_test_start "no leak: 100 open / drop / close cycles leave no instance, array or entry"
q=() v0='' v1='' e0='' e1=''
for (( i = 0; i < 100; i++ )); do q+=('key kbF10' 'key kbDown' 'key kbRight' 'key kbEsc'); done
v0=$(compgen -v | LC_ALL=C sort | tr '\n' ' ')
e0="${#__FV_MN_MV[@]} ${#__FV_MN_SH[@]} ${#__FV_MN_MG[@]} ${#__FV_VW_LIVE[@]} ${#app_views[@]}"
fva_events "${q[@]}"
app.Run; __FV_VW_EOF=0
v1=$(compgen -v | LC_ALL=C sort | tr '\n' ' ')
e1="${#__FV_MN_MV[@]} ${#__FV_MN_SH[@]} ${#__FV_MN_MG[@]} ${#__FV_VW_LIVE[@]} ${#app_views[@]}"
if [[ $v0 == "$v1" && $e0 == "$e1" ]] && fvm_nobox; then kt_test_pass "$e1"
else kt_test_fail "entries [$e0] -> [$e1]; vars [${#v0}] -> [${#v1}]"; fi
fvw_check "after the cycles: == a full repaint" "0" "$(fvw_full app && echo 0)"

fva_unapp
kt_test_log "014_MenuBudget.sh completed"
