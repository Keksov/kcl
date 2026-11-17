#!/usr/bin/env bash
# 005_Draw.sh - TStatusLine.Draw (FV DrawSelect(nil)): ONE fv.video write per
# draw (design §1.5) and no dispatch; FV's colours through CStatusLine
# (normal text 1, disabled 2, shortcut 3: CAppColor 2 / 3 / 4 -> symbols
# 2 3 4); a disabled command greyed; the Hint after the items (`│`, a blank,
# the text in colour 1; `|` in ASCII mode); wide characters in a label and a
# hint (cells and symbols aligned, a `~` between wide characters); blanks to
# the width; a line two rows high (one more fill); "Draw must cover its
# rect" (== a full repaint from garbage); a line narrower than its items
# (clipped to it); not drawn without an exposed root; a GetPalette override;
# cmCommandSetChanged: redrawn only when the greyed state changed (0 / 1
# write), and fv.views._quiet answers "not quiet" for the line and its root.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: drawing"

fvw_screen 80 24
TGroup.new root 0 0 80 24
TView.new bg 0 0 80 24
fv.views.insert root bg
fvm_mkst st 0 23 80 24
fv.views.insert root st
fvw_expose root
fv.views.drawView root

fvm_st
fvw_check "the line: items, cmZoom greyed (FV's default set), blanks to the width in colour 1" \
    " Alt+X Exit  F10 Menu  F5 Zoom |244444222222244422222233333333322222222" "${RESULT:0:31}|${REPLY:0:39}"
fvw_check "  the whole width" 80 "${#REPLY}"

FVW_WRITES=0; fvw_writes_on
fvw_budget "status draw" 0 fv.views.drawView st
fvw_writes_off
kt_test_log "# writes status draw $FVW_WRITES"
fvw_check "one draw = one fv.video write" 1 "$FVW_WRITES"

kt_test_start "Draw covers its rect: after garbage the screen equals a full repaint"
fv.video.fillRect 0 23 80 1 Z '#'
fv.views.drawView st
if fvw_full root; then kt_test_pass "ok"; else kt_test_fail "$FVW_DIFF"; fi

# cmCommandSetChanged: redrawn only when the greyed state changed
FVW_WRITES=0; fvw_writes_on
fv.views.message root evBroadcast cmCommandSetChanged; a=$?
w1=$FVW_WRITES
fv.views.enableCommands cmZoom
fv.views.message root evBroadcast cmCommandSetChanged
w2=$FVW_WRITES
fv.views.disableCommands cmCancel
fv.views.message root evBroadcast cmCommandSetChanged
w3=$FVW_WRITES
fvw_writes_off
fvm_st
fvw_check "cmCommandSetChanged: not handled (rc 1); unchanged 0 writes; cmZoom enabled 1 write; another def's command 0" \
    "1|0|1|1|244222222" "$a|$w1|$w2|$w3|${REPLY:22:9}"
fv.views.enableCommands cmCancel
fvw_check "fv.views._quiet: the line and its root are not quiet for the broadcast" "1 1" \
    "$(fv.views._quiet st cmCommandSetChanged; printf '%s ' "$?"; fv.views._quiet root cmCommandSetChanged; printf '%s' "$?")"

# the hint
class THintLine : TStatusLine
    public
        override func Hint
end
THintLine.Hint() { RESULT="Ctx $1 帮助"; }
build THintLine
TView.new bg2 0 0 80 2
THintLine.new hl 0 21 80 23 '~F1~ 帮~助~' kbF1 cmHelp 'x' '' cmX
fv.views.insert root hl
fv.views.drawView hl
fv.video.getRow 21; r1=$RESULT s1=$REPLY
fv.video.getRow 22; r2=$RESULT s2=$REPLY
# ' F1 帮助 ' = 1 + 2 + 1 + 2 + 2 + 1 cells (帮 in Lo, 助 in Hi), ' x ', then
# '│ Ctx 0 帮助'
fvw_check "a wide label with a ~ between wide characters, the Hint (bar, blank, text in colour 1), two rows high" \
    " F1 帮助  x │ Ctx 0 帮助 |244222442222222222222222|80" \
    "${r1:0:21}|${s1:0:24}|${#s1}"
fvw_check "  the second row blanked in colour 1" "$(printf '%80s' '')|$(printf '2%.0s' {1..80})" "$r2|$s2"

kt_test_start "the hinted two-row line equals a full repaint"
if fvw_full root; then kt_test_pass "ok"; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete root hl; hl.delete

# a two-row line of narrow text: two writes (the row, one fill below)
TStatusLine.new tw 0 17 80 19 'a' kbF2 cmA
fv.views.insert root tw
FVW_WRITES=0; fvw_writes_on
fv.views.drawView tw
fvw_writes_off
fvw_check "a line two rows high: 2 writes (the row + one fill)" 2 "$FVW_WRITES"
fv.views.delete root tw; tw.delete

# ASCII mode: the bar is '|', wide characters '?'
FV_ASCII=1 fv.video.initScreen
THintLine.new ha 0 22 40 23 '帮' kbF1 cmHelp
fv.views.insert root ha
fv.views.drawView root
fv.video.getRow 22
fvw_check "ASCII mode: '?' for a non-ASCII character (one cell, fv.video's ASCII mode), the bar '|'" " ? | Ctx 0 ??  |2222222222222222" "${RESULT:0:15}|${REPLY:0:16}"
fv.views.delete root ha; ha.delete
unset FV_ASCII; fv.video.initScreen
fv.views.drawView root
fvm_st
fvw_check "back in UTF-8 mode: the patterns follow" " Alt+X Exit " "${RESULT:0:12}"

# a line narrower than its items: clipped to its own width
TStatusLine.new nar 0 20 15 21 '~Alt+X~ Exit' kbAltX cmQuit '~F10~ Menu' kbF10 cmMenu
fv.views.insert root nar
fv.views.drawView root
fv.video.getRow 20
fvw_check "a 15-cell line shows 15 cells of its items, the rest of the row is the background's" \
    " Alt+X Exit  F1                    |244444222222244111111111111111111111" "${RESULT:0:35}|${REPLY:0:36}"
fv.views.delete root nar; nar.delete

# not drawn without an exposed root
TGroup.new root2 0 0 80 24
TStatusLine.new s2 0 0 80 1 'a' kbF2 cmA
fv.views.insert root2 s2
FVW_WRITES=0; fvw_writes_on
fv.views.drawView s2
fvw_writes_off
fvw_check "not drawn in a tree without an exposed root" 0 "$FVW_WRITES"
root2.delete

# a GetPalette override (CStatusLine reversed): one dispatch to resolve it
class TPalLine : TStatusLine
    public
        override func GetPalette
end
TPalLine.GetPalette() { RESULT='7 6 5 4 3 2'; }
build TPalLine
TPalLine.new pl 0 19 80 20 '~A~b' '' cmA
fv.views.insert root pl
fvw_budget "palette override draw" 1 fv.views.drawView pl
fv.video.getRow 19
fvw_check "the palette override's colours (normal 7, shortcut 5)" " Ab |7577" "${RESULT:0:4}|${REPLY:0:4}"
fv.views.delete root pl; pl.delete

root.delete
kt_test_log "005_Draw.sh completed"
