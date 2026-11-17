#!/usr/bin/env bash
# 005_Desktop.sh - TDesktop and TBackground (FV app.inc), headless:
#   * Tile: FV's MostEqualDivisors / DividerLoc layout for 2, 3 and 5
#     windows, TileColumnsFirst, the front-most view last; views without
#     ofTileable or hidden are left alone; TileError (an override counts) for
#     too small a rect, nothing moved; one redraw (== a full repaint);
#   * Cascade: the offsets (the back-most at the corner), TileError when the
#     back-most one's minimum does not fit;
#   * cmTile / cmCascade through the application (GetTileRect, also an
#     override); cmNext / cmPrev through the desktop (with and without a
#     background); the plain API's refusals;
#   * TBackground: one fill in CBackground's colour, its pattern, '#' for a
#     non-ASCII pattern in ASCII mode;
#   * the counts (logged): cmTile with two windows.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: the desktop"

mkw() {   # NAME AX AY BX BY: a tileable TWindow in the desktop
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$1" 0
    local -n __d=${1}_data
    __d[Options]=$(( __d[Options] | FV_OF_TILEABLE ))
    fv.views.insert "${6:-$FV_DESKTOP}" "$1"
}
bnds() { local v; REPLY=''; for v; do fv.views.getBounds "$v"; REPLY+="$RESULT;"; done; }

kt_test_start "Tile, 2 windows (FV: 1 column x 2 rows, the back-most on top), then TileColumnsFirst (2 columns); == a full repaint"
fva_app
fva_paint
fv.app.tile app; bnds w1 w2; r1=$REPLY
app__fvdesktop_data[TileColumnsFirst]=1
fv.app.tile app; bnds w1 w2; r2=$REPLY
app__fvdesktop_data[TileColumnsFirst]=0
if [[ $r1 == '0 0 80 11;0 11 80 23;' && $r2 == '0 0 40 23;40 0 80 23;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] diff [$FVW_DIFF]"; fi

kt_test_start "Tile, 3 windows (1 x 3: rows 0-7, 7-15, 15-23) and 5 windows (2 columns, the left over in the last one: 2 + 3 rows)"
mkw w3 5 5 30 15
fv.app.tile app; bnds w1 w2 w3; r1=$REPLY
mkw w4 1 1 20 10; mkw w5 2 2 22 12
fv.app.tile app; bnds w1 w2 w3 w4 w5; r2=$REPLY
if [[ $r1 == '0 0 80 7;0 7 80 15;0 15 80 23;' && $r2 == '0 0 40 11;0 11 40 23;40 0 80 7;40 7 80 15;40 15 80 23;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r1] [$r2] diff [$FVW_DIFF]"; fi
w3.delete; w4.delete; w5.delete

kt_test_start "Tile leaves a view without ofTileable and a hidden one alone (where they are; the one left takes the whole rect)"
mkw w3 5 5 30 15
w3_data[Options]=$(( w3_data[Options] & ~FV_OF_TILEABLE ))
fv.views.hide w1
fv.app.tile app; bnds w1 w2 w3; r=$REPLY
fv.views.show w1
w3.delete
if [[ $r == '0 0 40 11;0 0 80 23;5 5 30 15;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "Cascade (the back-most at the corner, each next one a cell in, all to the bottom-right); == a full repaint"
fv.app.cascade app; bnds w1 w2; r=$REPLY
if [[ $r == '0 0 80 23;1 1 80 23;' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "budget (logged): cmTile with two windows through the application"
fvw_writes_on; FVW_WRITES=0; FVW_CALLS=0
tile() { fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmTile; fv.views._virt app HandleEvent; }
fvw_count_on; tile; n=$FVW_CALLS; fvw_count_off
kt_test_log "# calls cmTile $n"; kt_test_log "# writes cmTile $FVW_WRITES"
fvw_writes_off
bnds w1 w2
if (( n <= 4 )) && [[ $REPLY == '0 0 80 11;0 11 80 23;' && $FV_EV_WHAT == evNothing ]]; then kt_test_pass "$n dispatches, $FVW_WRITES writes"; else kt_test_fail "$n [$REPLY] $FV_EV_WHAT"; fi

kt_test_start "cmCascade through the application; cmNext / cmPrev through the desktop (Current to the front / behind the others, FV); == a full repaint"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmCascade; fv.views._virt app HandleEvent
bnds w1 w2; r="$REPLY|$FV_EV_WHAT"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmNext; fv.views._virt app HandleEvent
fvw_tree app__fvdesktop; r+="|$FV_EV_WHAT|${REPLY//\{*\}/}"
r+="|${app__fvdesktop_data[Current]}"
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPrev; fv.views._virt app HandleEvent
r+="|$FV_EV_WHAT|${app__fvdesktop_data[Current]}"
local_order() { local -n l=app__fvdesktop_views; REPLY="${l[*]}"; }
local_order; r+="|$REPLY"
if [[ $r == '0 0 80 23;1 1 80 23;|evNothing|evNothing|app__fvdesktop[app__fvdesktop__fvbg ]*w1|w1|evNothing|w2|app__fvdesktop__fvbg w1 w2' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_start "TileError (an override counts): too small a rect for Tile and for Cascade, nothing moved; the plain API's refusals (rc 2)"
class TMyDesk : TDesktop
    public
        override proc TileError
        override proc InitBackground
end
TMyDesk.TileError() { TERR=$(( TERR + 1 )); }
TMyDesk.InitBackground() { :; }
build TMyDesk
TERR=0
fvw_screen 80 24
TMyDesk.new dk 0 0 80 23
fvw_expose dk
mkw a1 2 2 30 12 dk; mkw a2 10 5 50 20 dk
fv.app.tile dk 0 0 1 1; fv.app.cascade dk 0 0 17 7; bnds a1 a2; r="$TERR|$REPLY"
fv.app.cascade dk 0 0 18 8; bnds a1 a2; r+="|$TERR|$REPLY"
q=''
fv.app.tile || q+="$?,"; fv.app.tile dk 1 2 || q+="$?,"; fv.app.tile nosuch || q+="$?,"; fv.app.tile dk a 0 1 1 || q+="$?,"
fv.app.tile a1l 0 0 1 1 2>/dev/null || q+="$?,"; fv.app.cascade dk || q+="$?,"
r+="|$q"
if [[ $r == '2|2 2 30 12;10 5 50 20;|2|0 0 18 8;1 1 18 8;|2,2,2,2,2,2,' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "cmPrev without a background: FocusNext(True): the view in front of Current selected"
fv.views.select a1
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPrev; fv.views._virt dk HandleEvent
r="$FV_EV_WHAT|${dk_data[Current]}|${dk_data[Background]}"
dk.delete
if [[ $r == 'evNothing|a2|' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "a GetTileRect override: cmTile lays out inside its rect"
class TGT : TApplication
    public
        override proc GetTileRect
end
TGT.GetTileRect() { inherited GetTileRect; FV_RECT_BX=40; }
build TGT
fva_app 80 24 TGT
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmTile; fv.views._virt app HandleEvent
bnds w1 w2
if [[ $REPLY == '0 0 40 11;0 11 40 23;' ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY]"; fi
fva_unapp

kt_test_start "TBackground: one fill of its rect in CBackground's colour (app palette entry 1) with its pattern; ASCII mode draws a non-ASCII pattern as '#'"
fvw_screen 80 24
TGroup.new bgg 0 0 10 3
fvw_expose bgg
TBackground.new pb2 0 0 10 3
fvw_writes_on; FVW_WRITES=0
fv.views.insert bgg pb2
n=$FVW_WRITES
fvw_writes_off
fv.video.getRow 0; r="$n|${RESULT:0:2}|${REPLY:0:2}"
bgg.delete
fva_app
TBackground.new pb 0 0 4 1 x
fv.views.insert app__fvdesktop pb
fva_paint
fv.video.getRow 0; r+="|${RESULT:0:5}"
fva_unapp
FV_ASCII=1 fva_app
fva_paint
fv.video.getRow 0; r+="|${RESULT:0:2}|$FV_VIDEO_ASCII"
fva_unapp
FV_ASCII=''
if [[ $r == '1|░░|11|xxxx░|##|1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_start "fv.app.tile / cascade of a TProgram (no GetTileRect): the desktop's extent"
FV_APP_HEADLESS=1 TProgram.new prog
mkw p1 2 2 30 12; mkw p2 10 5 50 20
fv.app.tile prog; bnds p1 p2; r=$REPLY
prog.delete
if [[ $r == '0 0 80 11;0 11 80 23;' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "005_Desktop.sh completed"
