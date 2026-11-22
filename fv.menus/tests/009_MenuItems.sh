#!/usr/bin/env bash
# 009_MenuItems.sh - the menu model (P3 §7.2, FV TMenuItem / TMenu, NewItem /
# NewLine / NewSubMenu, TMenuView.Init, TMenuBar.Init, TMenuBox.Init,
# TMenuPopup.Init): the flat item list (item / line / sub … end, nested
# submenus) laid out per submenu (first / last / Default, the submenu index
# of a sub item), Disabled from the command set, the key map in FV
# HotKey's depth-first order with its chain, the hot letters per submenu
# (case-folded, Cyrillic, a `~` at the end), the classes' FV options /
# state / grow mode, the box's size from its items (FV: 5 + the widest
# ' NAME ' [+ ' - ' PARAM], 2 + the items) shortened or moved inside its
# bounds, fv.menus.newSubView, the refusals (a malformed list: rc 2, one
# Error line, nothing made; newSubView's arguments), the destructor freeing
# the arrays (a borrowed menu stays), the re-creation guard.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: the menu model"

fvw_screen 80 24

TMenuBar.new mb 0 0 80 1 \
    sub '~F~ile' item '~O~pen' F3 kbF3 cmOpen 11 line item 'E~x~it' '' kbAltX cmQuit 12 end \
    item '~H~elp' F1 kbF1 cmHelp 20 \
    sub '~W~in' 30 item '~N~ext' F6 kbF6 cmNext 31 sub '~L~ay' item '~T~ile' '' kbF6 cmTile 0 end item 'x~' '' kbF3 cmX 0 end
fvw_check "TMenuBar: FV's options (ofPreProcess), mask (+ evBroadcast), grow mode (gfGrowHiX), fields" \
    "16 785 4|mb:0||-1|-1" "${mb_data[Options]} ${mb_data[EventMask]} ${mb_data[GrowMode]}|${mb_data[Menu]}|${mb_data[ParentMenu]}|${mb_data[Current]}|${mb_data[OldItem]}"
fvw_check "the items laid out per submenu (top, File, Win, Lay): texts" \
    "~F~ile,~H~elp,~W~in,~O~pen,,E~x~it,~N~ext,~L~ay,x~,~T~ile" "$(IFS=,; printf '%s' "${mb_mtext[*]}")"
fvw_check "first / last / Default per submenu; the submenu of each sub item" \
    "0 3 6 9|2 5 8 9|0 3 6 9|1,,2,,,,,3,," "${mb_mfirst[*]}|${mb_mlast[*]}|${mb_mdef[*]}|$(IFS=,; printf '%s' "${mb_msub[*]}")"
fvw_check "params, keys, commands, help contexts (a sub's HELPCTX optional)" \
    ",F1,,F3,,,F6,,,|,kbF1,,kbF3,,kbAltX,kbF6,,kbF3,kbF6|,cmHelp,,cmOpen,,cmQuit,cmNext,,cmX,cmTile|0 20 30 11 0 12 31 0 0 0" \
    "$(IFS=,; printf '%s' "${mb_mparam[*]}")|$(IFS=,; printf '%s' "${mb_mkey[*]}")|$(IFS=,; printf '%s' "${mb_mcmd[*]}")|${mb_mhelp[*]}"
# (FV's default command set disables cmNext / cmPrev / cmZoom / cmClose / cmResize)
fvw_check "Disabled from the command set at the start (FV NewItem): cmNext is off" "0 0 0 0 0 0 1 0 0 0" "${mb_mdis[*]}"
km=''
for k in kbF3 kbF1 kbAltX kbF6 kbF9; do km+="$k=${mb_mkmap[$k]-none},"; done
fvw_check "the key map: FV HotKey's depth-first order (File's Open before Win's x; Next before Lay's Tile)" \
    "kbF3=3,kbF1=1,kbAltX=5,kbF6=6,kbF9=none,|8 9" "$km|${mb_mknext[3]} ${mb_mknext[6]}"
hm=''
for k in 0:f 0:h 0:w 1:o 1:x 2:n 2:l 3:t 2:x 0:o; do hm+="$k=${mb_mhot[$k]-none},"; done
fvw_check "the hot letters per submenu (folded); a '~' at the end has none" \
    "0:f=0,0:h=1,0:w=2,1:o=3,1:x=5,2:n=6,2:l=7,3:t=9,2:x=none,0:o=none," "$hm"

# a Cyrillic hot letter, upper case, folded; two items with one letter chain
TMenuPopup.new pp 10 5 60 20 item '~Ф~айл' '' kbF2 cmA 0 item '~ф~орма' '' '' cmB 0 item 'Ok' 'Ctrl+K' '' cmC 0
fvw_check "TMenuPopup: Cyrillic hot letters folded (Ф -> ф), a letter twice chains; an item without a '~' has none" \
    "0|1|-1|1 1" "${pp_mhot[0:ф]-none}|${pp_mhnext[0]}|${pp_mhnext[1]}|${#pp_mhot[@]} ${#pp_mkmap[@]}"
fvw_check "TMenuBox / TMenuPopup: sfShadow, ofFramed + ofPreProcess, no parent, Current = the Default" \
    "$(( FV_SF_VISIBLE | FV_SF_SHADOW )) 24||0|pop" "${pp_data[State]} ${pp_data[Options]}|${pp_data[ParentMenu]}|${pp_data[Current]}|${__FV_MN_MV[pp]}"
# FV TMenuBox.Init: W = 5 + max(' Форма ' 7, ' Ok ' 4 + 3 + 6 = 13) = 18, H = 2 + 3
fv.views.getBounds pp
fvw_check "TMenuBox's size from its items (W 5 + 13: ' Ok ' + ' - ' + Ctrl+K; H 5), shortened from the corner" "10 5 28 10" "$RESULT"
TMenuBox.new bx 70 20 80 24 item '~L~ong item name' '' '' cmA 0 item 'b' '' '' cmB 0
fv.views.getBounds bx
fvw_check "too little room: moved left / up to fit (FV: A := B - W), still its own size" "59 20 80 24" "$RESULT"
TMenuBox.new by 0 0 30 3 item 'a' '' '' cmA 0 item 'b' '' '' cmB 0 item 'c' '' '' cmC 0
fv.views.getBounds by
fvw_check "taller than the bounds: moved up past the top (FV)" "0 -2 8 3" "$RESULT"
TMenuBox.new be 5 5 40 20
fv.views.getBounds be
fvw_check "a box without items: 5 x 2 (FV), Menu nil" "5 5 10 7|" "$RESULT|${be_data[Menu]}"
TMenuView.new mv 0 0 10 1
fvw_check "TMenuView alone: TView's options, evBroadcast, no menu, its kind" "0 785||view" "${mv_data[Options]} ${mv_data[EventMask]}|${mv_data[Menu]}|${__FV_MN_MV[mv]}"

# fv.menus.newSubView: a box over the bar's submenu 2 (Win), parent mb
fv.menus.newSubView mb 3 1 80 24 mb:2 mb
nb=$RESULT
fv.views.getBounds "$nb"
fvw_check "newSubView: a TMenuBox named PARENT__fvbox, the borrowed menu, the parent, sized by the submenu" \
    "mb__fvbox|mb:2|mb|1|3 1 19 6" "$nb|${mb__fvbox_data[Menu]}|${mb__fvbox_data[ParentMenu]}|${__FV_MN_SUB[$nb]}|$RESULT"
mb__fvbox.delete
fvw_check "a borrowed menu stays when the box goes; the box's entries are freed" "10|" "${#mb_mtext[@]}|${__FV_MN_MV[mb__fvbox]-}"

kt_test_start "newSubView refusals: not a menu view, a bad menu, a dead parent, the count (rc 2, nothing made)"
r=''
fv.menus.newSubView nosuch 0 0 9 9 mb:1 mb 2>/dev/null; r+=$?
fv.menus.newSubView mb 0 0 9 9 zz:1 mb; r+=$?
fv.menus.newSubView mb 0 0 9 9 mb:x mb; r+=$?
fv.menus.newSubView mb 0 0 9 9 mb:1 nosuch; r+=$?
fv.menus.newSubView mb 0 0 9 9 mb:1; r+=$?
if [[ $r == 22222 ]] && fvm_nobox; then kt_test_pass "ok"; else kt_test_fail "rc $r"; fi

malformed() {   # TITLE CLASS ARGS...
    local t=$1 c=$2 e rc=0
    shift 2
    kt_test_start "a malformed list is refused before anything is made: $t"
    "$c.new" bad 0 0 40 10 "$@" 2>"$FVW_TMP/err.txt" || rc=$?
    e=$(<"$FVW_TMP/err.txt")
    if (( rc == 2 )) && [[ $e == "Error: fv.menus: $c.Create: 'bad': "* && -z ${__FV_VW_LIVE[bad]-} && -z ${bad_mtext+x} ]]; then kt_test_pass "$e"
    else kt_test_fail "rc $rc err [$e]"; fi
    if declare -F bad.delete >/dev/null; then bad.delete; fi
}
malformed "item without its fields" TMenuBar item '~A~' '' kbF2 cmA
malformed "item with an empty text" TMenuBox item '' '' '' cmA 0
malformed "a bad key name" TMenuBar item 'a' '' F2 cmA 0
malformed "a bad command" TMenuPopup item 'a' '' kbF2 'cm A' 0
malformed "a bad HELPCTX" TMenuBar item 'a' '' kbF2 cmA hcA
malformed "sub without a text" TMenuBar sub
malformed "end without a sub" TMenuBar item 'a' '' '' cmA 0 end
malformed "sub without its end" TMenuBar sub 'a' item 'b' '' '' cmB 0
malformed "an unknown word" TMenuBar sub 'a' items end

# the destructor frees the owner's arrays and entries
mb.delete
left=$(compgen -v | grep -E '^mb_m' | tr '\n' ' ')
fvw_check "the destructor frees the item arrays and the entries" "|||" "$left|${__FV_MN_MV[mb]-}|${__FV_MN_OWN[mb]-}|${__FV_MN_MG[mb]-}"
# the re-creation guard: .new over a live menu view is refused, its arrays freed
TMenuPopup.new pp 0 0 9 9 2>/dev/null; rc=$?
fvw_check "re-creating a live menu view: TView's guard refuses (rc 1); its arrays are freed" "1|" "$rc|${pp_mtext+set}"
pp.delete; bx.delete; by.delete; be.delete; mv.delete
fvw_check "no menu entries left" "0 0" "${#__FV_MN_MV[@]} ${#__FV_MN_OWN[@]}"

kt_test_log "009_MenuItems.sh completed"
