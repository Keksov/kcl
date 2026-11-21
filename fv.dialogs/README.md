# kcl/fv.dialogs — the dialogs of the fv.* text UI

Layer L3 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P3_DESIGN.md](../docs/dev/fv/P3_DESIGN.md) §1–§5, §15). Free Vision's
`Dialogs` unit (FV `dialogs.inc`, FPC 2025) as [kklass](../../kklass/README.md)
classes on [fv.views](../fv.views/README.md)' `TView` / `TWindow`, with FV's
field names and fv.views' virtual elision: every built-in virtual runs as a
plain function unless a class of yours overrides it.

**Status: P3 stage 3h** — `TDialog`, `TButton`, `TStaticText`, `TParamText`,
`TLabel`, `TCluster`, `TCheckBoxes`, `TRadioButtons` (3c), `TInputLine` (the
text as clusters, FV's keys, selection, scrolling, the mouse, overwrite,
password mode, the clipboard keys and bracketed paste) and `TListBox` (3d),
`THistory` / `THistoryViewer` / `THistoryWindow` (3h: the input history over
[fv.histlist](../fv.histlist/README.md), D28), the data transfer, the
setters and FV's `NewButton` / `NewLabel`; hot keys through fv.views'
hot-key map (any keyboard layout, design §14).

The unit loads `kklass_pascal`, `fv.views` and `fv.histlist`.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.app fv.dialogs

TDialog.new dlg 10 4 70 18 'Find'                       # FV Init(R, ATitle)
TStaticText.new st 3 1 57 2 $'\x03''Search options'     # ^C: centred
TInputLine.new find 15 2 57 3 255                       # Init(R, AMaxLen)
TLabel.new lf 2 2 14 3 '~F~ind' find                    # Init(R, AText, ALink)
TLabel.new l1 2 3 14 4 '~T~ext' opts
TCheckBoxes.new opts 3 4 30 7 '~C~ase sensitive' '~W~hole words'
TRadioButtons.new dir 32 4 56 6 '~F~orward' '~B~ackward'
TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"  # Init(R, ATitle, ACommand, AFlags)
TButton.new cn 26 10 38 12 'Cancel' cmCancel
for v in st find lf l1 opts dir ok cn; do fv.views.insert dlg "$v"; done
fv.views.select find                                    # the first control (FV programs: SelectNext)

REC=('needle' 1 0); fv.dialogs.setData dlg REC          # find's text, opts' Value 1, dir's 0
fv.views.execView "$FV_DESKTOP" dlg
if [[ $RESULT == cmOK ]]; then fv.dialogs.getData dlg REC; echo "find '${REC[0]}', options ${REC[1]}, direction ${REC[2]}"; fi
dlg.delete                                              # with its controls
```

The modal loop is fv.views' `execView` (FV `ExecView`): Esc or Ctrl+F4 ends
it with `cmCancel`, Enter presses the default button (`cmOK` here), the end of
input answers `cmCancel`. A dialog in a subshell (`$( … )`) is refused by
fv.views' owner-process rule.

## Classes and fields

| class | fields (FV's public fields) | constructor (FV argument order) |
|---|---|---|
| `TDialog : TWindow` | TWindow's (`Palette` = `FV_DP_GRAYDIALOG`) | `TDialog.new NAME AX AY BX BY TITLE` |
| `TButton : TView` | `Title Command Flags AmDefault DownFlag` | `TButton.new NAME AX AY BX BY TITLE COMMAND [FLAGS]` |
| `TStaticText : TView` | `Text` | `TStaticText.new NAME AX AY BX BY TEXT` |
| `TParamText : TStaticText` | `ParamCount` (+ the parameters in `NAME_params`) | `TParamText.new NAME AX AY BX BY TEXT [PARAMCOUNT]` |
| `TLabel : TStaticText` | `Link Light` | `TLabel.new NAME AX AY BX BY TEXT LINK` |
| `TCluster : TView` | `Id Value Sel EnableMask` (+ the items in `NAME_items`) | `TCluster.new NAME AX AY BX BY [ITEM]...` |
| `TCheckBoxes`, `TRadioButtons : TCluster` | TCluster's | as TCluster |
| `TInputLine : TView` | `MaxLen CurPos FirstPos SelStart SelEnd PasswordChar Validator` (+ the text's clusters in `NAME_cl`, their cells in `NAME_cw`) | `TInputLine.new NAME AX AY BX BY MAXLEN` |
| `TListBox : TListViewer` | TListViewer's (`List Formatter Marks` …) | `TListBox.new NAME AX AY BX BY [NUMCOLS [SCROLLBAR]]` |
| `THistory : TView` | `Link HistoryId` | `THistory.new NAME AX AY BX BY LINK HISTORYID` (FV `Init(R, ALink, AHistoryId)`) |
| `THistoryViewer : TListViewer` | `HistoryId` (+ TListViewer's; its items in `NAME_hist`) | `THistoryViewer.new NAME AX AY BX BY HSCROLLBAR VSCROLLBAR HISTORYID` |
| `THistoryWindow : TWindow` | `Viewer` (+ TWindow's) | `THistoryWindow.new NAME AX AY BX BY HISTORYID` |

* Corners, B exclusive, as every fv.views constructor (D1). FV's `NewSItem`
  chain is the items written flat after the bounds.
* **Refused before anything is made** (rc 2, one `Error: fv.dialogs:` line on
  stderr, `VERBOSE_KKLASS=quiet` silences it; `.delete` the bare instance):
  a `TButton` without a TITLE and a COMMAND, a COMMAND that is not a command
  name (letters, digits, `_`), FLAGS that are not digits; a `TParamText`
  PARAMCOUNT that is not digits; a `TInputLine` without MAXLEN or with
  MAXLEN not digits; a `THistory` without exactly LINK and HISTORYID, a LINK
  that is not an identifier (or `''`), a HISTORYID that is not 0–255; a
  `THistoryWindow` / `THistoryViewer` HISTORYID that is not 0–255. fv.views'
  own refusals (a live name, a reserved name, bounds, TListViewer's NUMCOLS
  and bar) apply too.
* Constants (readonly): `FV_BF_NORMAL DEFAULT LEFTJUST BROADCAST GRABFOCUS`
  (0 1 2 4 8, FV `bf*`), `FV_DP_BLUEDIALOG CYANDIALOG GRAYDIALOG` (0 1 2).
* Defaults (FV's Init): **TDialog** `GrowMode` 0, `Flags` `wfMove + wfClose`,
  no number; **TButton** `EventMask` + `evBroadcast`, `ofSelectable +
  ofFirstClick + ofPreProcess + ofPostProcess`, `sfDisabled` when COMMAND is
  disabled (fv.views' command set), `AmDefault` 1 with `bfDefault`;
  **TLabel** `ofPreProcess + ofPostProcess`, `EventMask` + `evBroadcast`,
  `Light` 0; **TCluster** `ofSelectable + ofFirstClick + ofPreProcess +
  ofPostProcess`, `Sel` 0, the cursor at (2, 0) shown, `EnableMask`
  `$FFFFFFFF`, `Value` and `Id` 0; **TInputLine** `sfCursorVis`,
  `ofSelectable + ofFirstClick`, an empty text, all positions 0, the cursor
  at cell 1; **TListBox** TListViewer's with no horizontal bar, `Range` 0
  (FV `SetRange(0)`); **THistory** `ofPostProcess`, `EventMask` +
  `evBroadcast` (not selectable); **THistoryWindow** no title, no number,
  `Flags` `wfClose`, the viewer selected; **THistoryViewer** one column, the
  range the list's count, item 1 focused with two strings or more.

### Virtual methods

| class | method | kind | FV |
|---|---|---|---|
| `TDialog` | `HandleEvent` | proc | TWindow's, then Esc / Ctrl+F4 → `evCommand cmCancel` posted, Ctrl+F5 (modal) → `cmResize` posted (the keyboard move), Enter → `evBroadcast cmDefault` posted (each handled); `cmOK cmCancel cmYes cmNo` while modal → `EndModal`, handled |
| `TDialog` | `GetPalette` | func | CBlueDialog / CCyanDialog / CGrayDialog by `Palette`: CAppColor 64–95 (FV's 30th entry is 92: kept), 96–127, 32–63 |
| `TDialog` | `Valid CMD` | func (rc) | `cmCancel` always valid, else TGroup's |
| `TDialog` | `CalcBounds DX DY` | proc | FPC 2025: `GrowMode` set → TWindow's; else the margins kept in proportion (FV's `MoveRel`: a one-cell growth moves toward the larger margin, else the margins scale with Pascal's `Round`, a half to the even number) |
| `TButton` | `Draw` | proc | the title centred (`bfLeftJust`: from cell 1) with its `~` letter in the shortcut colour, the shadow `▄` / `▀` in colour 8; pressed (`DownFlag`): one cell right, no shadow; colours FV's: normal 1 / 5, default 2 / 6, selected 3 / 7, disabled 4 / 4 |
| `TButton` | `HandleEvent` | proc | below ("Events") |
| `TButton` | `GetPalette` | func | CButton `10 11 12 13 14 14 14 15` |
| `TButton` | `SetState BIT ENABLE` | proc | TView's; `sfSelected` / `sfActive` → redrawn when its colours change; `sfFocused` → FV `MakeDefault` |
| `TButton` | `Press` | proc | `cmRecordHistory` broadcast to the owner, then `evCommand Command` posted (`FV_EV_INFO` = the button), or with `bfBroadcast` the broadcast of `Command` to the owner |
| `TStaticText` | `Draw` | proc | FV_UNICODE's `TStaticText.Draw` over `GetText` (below) |
| `TStaticText` | `GetPalette` / `GetText` | func | CStaticText `6 7 8 9` / the `Text` field |
| `TParamText` | `GetText` | func | `printf -v` of `Text` with the first `ParamCount` parameters (FV `FormatStr`), never more than the format's conversions take (printf would repeat the format for the surplus; FormatStr ignores it; the count kept per text); a bad format answers what printf made, without its message |
| `TLabel` | `Draw` | proc | a blank, then `Text` with its `~` letter: colours 1 / 3, or 2 / 4 while `Light` |
| `TLabel` | `GetPalette` / `HandleEvent` | | CLabel `7 8 9 9` / "Events" |
| `TCluster` | `Draw` | proc | FV's is empty; here blanks in colour 1 (it covers its rect) |
| `TCheckBoxes` / `TRadioButtons` | `Draw` | proc | FV `DrawMultiBox`: ` [X] Item` / ` (*) Item` per item in FV's columns (the next column at the widest item + 6), CDis (5) for a disabled item, CSel (2 / 4) for `Sel` while focused, else CNorm (1 / 3), the hardware cursor on `Sel`'s mark |
| `TCluster` | `HandleEvent` / `SetState` / `GetPalette` / `GetHelpCtx` | | "Events"; `sfFocused` → `Sel`'s row redrawn; CCluster `16 17 18 18 31 6`; `HelpCtx + Sel` (hcNoContext stays) |
| `TCluster` | `Mark ITEM` | func (rc) | false; TCheckBoxes: ITEM's bit of `Value`; TRadioButtons: ITEM = `Value` |
| `TCluster` | `Press ITEM` | proc | `Id` ≠ 0 → `cmIdCommunicate` (`evCommand`) to the top view (`FV_EV_ID` = `Id`, `FV_EV_INFO` = the cluster; FV's `Data` = its `Value`); TCheckBoxes toggles ITEM's bit first, TRadioButtons sets `Value` first |
| `TCluster` | `MovedTo ITEM` | proc | nothing; TRadioButtons: `Value` := ITEM, `Id` → `cmIdCommunicate` to the owner |
| `TInputLine` | `Draw` | proc | FV_UNICODE's: the clusters from `FirstPos` in cells 1 … SizeX−2 in colour 1 (2 focused, 5 not selectable; a wide cluster that does not fit ends the row: no half cell), `>` in colour 4 in the last cell while text lies past it; focused: `<` in colour 4 in cell 0 when `FirstPos` > 0, the selection in colour 3, the cursor after `CurPos` (`CursorX`); password mode: one `PasswordChar` cell per cluster; the row on every row of the view (FV's WriteLine over Size.Y), one `writeLine` |
| `TInputLine` | `HandleEvent` | proc | "The input line" below |
| `TInputLine` | `GetPalette` | func | CInputLine `19 19 20 21 14` |
| `TInputLine` | `SetState BIT ENABLE` | proc | TView's; `sfSelected` (or `sfActive` while selected) → FV `SelectAll(ENABLE)`; `sfFocused` → drawn; P3-12: the select-then-focus sequence draws once |
| `TInputLine` | `Valid CMD` | func (rc) | TView's; with a `Validator` function, a text and the line enabled: `cmValid` / `cmCancel` valid, any other command asks `FN TEXT` (rc 0 = valid); a "no" selects the line (FV `Select`) |
| `TListBox` | `HandleEvent`, `Draw`, … | | TListViewer's (fv.views: keys, mouse, Marks) |
| `THistory` | `Draw` | proc | `▐v▌` (FV `#222'~v~'#221`): the `v` in colour 2, the rest in colour 1; ASCII mode `[v]`; a wider view's other cells blank; one `writeLine` |
| `THistory` | `HandleEvent` | proc | "The input history" below |
| `THistory` | `GetPalette` | func | CHistory `22 23` |
| `THistory` | `InitHistoryWindow AX AY BX BY` | func | a `THistoryWindow` over the bounds with `HistoryId` (the reserved name `NAME__fvhwN`), its `HelpCtx` the link's; `RESULT` = its name (`''`: nothing opens) |
| `THistory` | `RecordHistory TEXT` | proc | `fv.histlist.historyAdd HistoryId TEXT`; nothing while the link is in password mode (D29) |
| `THistoryWindow` | `GetPalette` | func | CHistoryWindow `19 19 21 24 25 19 20` |
| `THistoryWindow` | `GetSelection` | func | the viewer's focused item: its `List` element (or its `Formatter`'s answer); `''` without a viewer |
| `THistoryWindow` | `InitViewer HISTORYID` | proc | the horizontal and the vertical bar (`fv.views.standardScrollBar`, `sbHandleKeyboard`), then the viewer over the window's inside (`NAME__fvviewer`) on them, inserted; `Viewer` := its name |
| `THistoryViewer` | `GetPalette` | func | CHistoryViewer `6 6 7 6 6` |
| `THistoryViewer` | `HandleEvent` | proc | a double click or Enter → `EndModal(cmOK)`, Esc or the command `cmCancel` → `EndModal(cmCancel)` (handled); anything else TListViewer's |
| data-bearing views | `DataSize` (func), `GetData ARRAY INDEX`, `SetData ARRAY INDEX` (procs) | | "Data" below |

A class of yours overrides any of them and calls the built-in with
`inherited NAME "$@"`; an override costs one dispatch per use (fv.views
README, "Virtual elision"). `Mark` and `Valid` answer by their rc. The thin
aliases (D16) `il.SelectAll 1|0` and `lb.NewList ARRAY [FMT]` call the plain
functions below.

## Drawing

* Every Draw writes its rows in one call (`writeLines`, one row: `writeLine`)
  and covers its rect (rows FV leaves alone are blank in the view's normal
  colour). Cells come from fv.video (`fv.video.clusters`): wide characters
  take two cells, ASCII mode one `?` per character (design §2.7).
* **Cached pictures** (design §2.1 rule 2): a button's rows by its colours,
  palette, `DownFlag`, `Flags`, size, ASCII mode and `Title`; a label's by
  its colours, size, mode and `Text`; a static text's by its colour, size,
  mode and text. A cluster's rows are composed per draw from per-item cell
  patterns kept until the items or the mode change. Every cache of a view is
  dropped by its destructor and by a constructor that takes the name again.
* **Redraw only a changed picture** (P3-12, D17): a button whose colours stay
  (a focus change between two other controls, `cmCommandSetChanged` with its
  command unchanged, `cmGrabDefault` when it is selected) is not redrawn; a
  label redraws only when `Light` changes; a cluster redraws only the rows
  that change (rule 4: `Sel`'s old and new row, the changed marks — one
  `drawPart`, or two; a `Draw` or `Mark` of yours: the whole cluster).
* **TStaticText** follows FV_UNICODE's algorithm exactly: a line breaks when
  its cells reach the width — at the last blank, which the next line keeps
  at its start, else at the last cluster that fits (a line that fills the
  width exactly breaks too) — or at CR, LF, CRLF; a line starting with `^C`
  (`$'\x03'`) is centred, with `^B` (`$'\x02'`) right-justified; another
  control character shows as fv.video's `?`.
* **ASCII mode** (the screen's): the button's shadow cells are blanks (FV's
  monochrome look); marks and arrows as in UTF-8 mode; an input line counts
  one cell per non-ASCII character (fv.video's `?` there).
* **The input line** draws only a changed picture (P3-12): a cursor move
  inside the text with no selection only places the cursor (no write); a
  typed character is one `writeLine`.

## Events

* **Focus** between the controls is TWindow's (fv.views): Tab / Shift+Tab and
  the arrows a control does not take move it in FV's order (insertion order);
  labels and static texts are not selectable.
* **Hot keys** (FV): Alt + a control's `~` letter in any phase; the plain
  letter when the owner's `Phase` is `phPostProcess`; a focused cluster also
  takes its plain letters. Every test goes through fv.views' helper
  (`fv.views.hotKeyIs` rules, design §14): the typed character first, then
  the base-layout key (`FV_EV_BASE`; for a plain character the layout
  tables), so a Latin `~F~` works with a Russian layout and a Cyrillic
  `~Ф~` on its own key. The owner's **hot-key map** (fv.views README) calls a
  control's built-in handler in the pre / post phase only when the key names
  it (or the control is focused); a typed match wins over a base match
  when its control can react (enabled, and a cluster's item with that
  letter on in `EnableMask`), else the base match counts.
* **TButton**: a mouse-down tracks the press (the pressed look while the
  mouse is on the button or its shadow, FV's `ButRect`; the release's own
  place decides, as fv.views' frame icons; a key or the end of input ends the
  tracking); **a click does not focus a button** unless it has `bfGrabFocus`
  (FV); Alt + its letter, the plain letter in post-process, Space / Enter
  while focused → the pressed look, `Press`, the look back;
  `cmDefault` (AmDefault, enabled) → `Press`; `cmGrabDefault` /
  `cmReleaseDefault` (bfDefault) → `AmDefault`; `cmCommandSetChanged` →
  `sfDisabled` follows `Command`.
* **TLabel**: a click, Alt + its letter or the plain letter in post-process
  focus `Link` (when it is a selectable view); `cmReceivedFocus` /
  `cmReleasedFocus` set `Light` to "the link is focused".
* **TCluster**: a click selects the item under it (enabled) and presses it on
  a release over it; while focused Up / Down / Right / Left (WordStar Ctrl
  keys through `CtrlToArrow`) move `Sel` to the next enabled item (wrapping,
  Right / Left by a column with FV's formulas) and call `MovedTo`; Space
  presses `Sel`; a hot letter focuses the cluster, moves `Sel` there and
  presses it (a disabled item: the key is not handled, FV).
* **TListBox**: TListViewer's keys and mouse (fv.views README): Up / Down,
  PgUp / PgDn, Home / End, Ctrl+PgUp / Ctrl+PgDn, the wheel, a click, a
  double click (SelectItem → `cmListItemSelected`); with `Marks` (a long
  checklist, D29) Space toggles the focused item's mark and Ins toggles and
  moves down.
* **THistory**: "The input history" below.
* The broadcast table rows (fv.views' `__FV_VW_BCAST`): TButton `cmDefault
  cmGrabDefault cmReleaseDefault cmCommandSetChanged`, TLabel
  `cmReceivedFocus cmReleasedFocus`, TDialog `cmSelectWindowNum`, THistory
  `cmReleasedFocus cmRecordHistory`, THistoryViewer TListViewer's
  (`cmScrollBarChanged cmScrollBarClicked`), TCluster and TInputLine none.

## The input history

FV's `THistory` (dialogs.inc 3740-3990, design P3 §15, D28) over the store of
[fv.histlist](../fv.histlist/README.md) (per process, newest first, a
repeated string moves to the front, 64 KiB for all lists):

```bash
TInputLine.new find 14 2 56 3 255
THistory.new hfind 56 2 59 3 find 1        # after the line; list 1 of fv.histlist
fv.views.insert dlg find; fv.views.insert dlg hfind
```

* **Open**: Down (or Ctrl+X, FV's `CtrlToArrow`) while the link is focused,
  or a click on the view: the link is focused (a refusal — its owner's
  `Valid` — handles the event and opens nothing), its text recorded, and
  `InitHistoryWindow` makes the window over FV's rect: the link's bounds one
  cell wider on each side, from the row above it to 7 rows below it, cut to
  the owner's extent, then one row shorter (dialogs.inc 3955-3964). The
  owner runs it modal (`fv.views.execView`); the viewer starts on item 1
  (item 0 is the text just recorded), item 0 when there is one string.
* **Inside**: TListViewer's keys and mouse (Up / Down, PgUp / PgDn, Home /
  End, the wheel, a click); Enter or a double click → `cmOK`, Esc, the
  `cmCancel` command or the window's close icon → `cmCancel`.
* **cmOK**: the line's text := `GetSelection`, through TInputLine's own
  `setText` path (control characters dropped, cut to `MaxLen` clusters, so
  wide characters and joined clusters stay whole), all of it selected, drawn.
  Then (every answer) the window, its frame, bars and viewer are destroyed.
* **Recording** (FV): on `cmReleasedFocus` from the link (Tab away, the
  dialog closing with the line focused) and on `cmRecordHistory`, which
  `TButton.Press` broadcasts to its owner first — so pressing OK records
  every history line of the dialog. `''` is never recorded (FV). **A line in
  password mode is never recorded** (D29): its text does not even reach
  `RecordHistory`.
* **The hot-key map** (fv.views README): THistory is mapped by its `Link`
  (no hot letter) and named by the keys `kbDown` / `kbCtrlX` (fv.views'
  `__FV_VW_HKK`): the pre / post scan calls its built-in handler for those
  two keys only — a key nobody takes costs nothing more (`013`'s typing
  budgets hold with a history view in the dialog).

## The input line

The text is kept as **clusters** (design P3-5, §4.1): `NAME_cl` holds the
cluster strings, `NAME_cw` their cells (1 or 2), both from
`fv.video.clusters`, so the line and the screen agree cell for cell — wide
characters, ZWJ sequences, flags, VS16, combining marks, Cygwin-family
characters past U+FFFF, ASCII mode. `CurPos FirstPos SelStart SelEnd` and
`MaxLen` count clusters. A printable ASCII character typed in insert mode
between two ASCII clusters takes a fast path (no fv.video call); after any
other edit the clusters around it are split again (one `fv.video.clusters`
call over the cluster before, the edit and the cluster after, widened over a
run of regional indicators and over following clusters that now join — a
modifier or pictograph after a ZWJ, a mark), so the line always equals
fv.video's split of the whole text (`008_InputWide`'s oracle). A replace
(overwrite, typing or pasting over a selection) is FV's Delete, then Insert
at that same offset: the clusters taken out are spliced out as they are and
the new text split with the neighbours, so a dangling ZWJ or a lone regional
indicator next to the edit never pulls the new text past its neighbour. A
paste or `setText` clusters only as much of its text as `MaxLen` leaves
room for (a 20 000-character paste into `MaxLen` 255 costs what 255
clusters cost); control characters are C0, DEL and C1 on every platform
(not the C library's `[[:cntrl:]]`, which on FreeBSD and macOS holds ZWJ).

Keys while the line is selected (FV's key set through `CtrlToArrow`):

| key | action |
|---|---|
| a character | the selection deleted (overwrite: the cluster at the cursor), then inserted while `MaxLen` allows; the cursor after the cluster that holds it |
| Left / Right / Home / End (Ctrl+S / D / A / F) | by a cluster / to the ends |
| Ctrl+Left / Ctrl+Right | FPC 2025's word moves (its delimiter set) |
| Shift + those | extend the selection from its anchor |
| Back / Del (Ctrl+H / Ctrl+G) | the selection, else the cluster before / at the cursor |
| Ins (Ctrl+V) | overwrite on / off (`sfCursorIns`: the block cursor; insert: underline, D27) |
| Ctrl+Y | clear |
| Ctrl+Ins / Shift+Del / Shift+Ins | copy / cut / paste (the clipboard, below) |
| any other key | not handled (FV: Exit) — Enter, Tab, Up, Down go on to the dialog |

After each key the selection collapses to the cursor (or follows its anchor)
and FV's FirstPos rule keeps the text from `FirstPos` to `CurPos` within
`SizeX − 3` cells. **SelectAll on focus** (FV): selecting the line (Tab into
it, opening its dialog) selects its whole text, so the first typed key
replaces it.

**The mouse** (FV): a click places the cursor in front of the cluster under
it (FV `MousePos`: from cell 1, counted past the shown text too); a double
click selects all; a drag selects from the press (moves coalesced), and an
`evMouseAuto` while the mouse is past an edge scrolls a cluster; a press on
the `<` / `>` cell while the text can scroll there scrolls a cluster per
`evMouseAuto` until the release. A click on an unfocused line focuses it
first (its SelectAll collapses at the click).

**Password mode** (D29): `PasswordChar` set (one one-cell character, e.g.
`*`, used as it is — whatever the caller's locale —) shows every cluster as one
cell of it — wide input does not reveal its shape —, the selection colour
still shows, `getText` answers the real text;
copy and cut do nothing (no clipboard, no OSC 52); paste works.

**The clipboard** (D24, design §4.5): Ctrl+Ins copies the selection to the
internal clipboard `FV_CLIPBOARD` and to the system clipboard by OSC 52
(`fv.video.setClipboard`); Shift+Del cuts (the same, then deletes);
Shift+Ins — and an `evCommand cmPaste`, an Edit menu's — pastes
`FV_CLIPBOARD`; an `evCommand cmPasteText` (fv.drivers' **bracketed paste**:
what the terminal pastes, in `FV_EV_INFO`) goes in as typed. A paste drops
control characters (FV inserts each character as a key: a newline or a Tab
goes nowhere) and is one event, so **a pasted newline never presses the
default button**. As FV, a copy collapses the selection afterwards. Which
keys reach the program depends on the terminal:

| key | Windows Terminal | mintty (Git-bash) | xterm | GNOME Terminal (VTE) | kitty | Linux console |
|---|---|---|---|---|---|---|
| Shift+Ins | its own paste → one `cmPasteText` | its own paste → one `cmPasteText` | pastes PRIMARY → one `cmPasteText` | its own paste → one `cmPasteText` | pastes the selection → one `cmPasteText` | reaches the program: `cmPaste` (internal) |
| Ctrl+Ins | copies the terminal's selection when there is one (to confirm live otherwise) | copies the terminal's selection | copy | copy | copy | copy |
| Shift+Del | cut | cut | cut | cut | cut | cut |
| Ctrl+Shift+V / right click | paste → one `cmPasteText` | paste (right click: config) → one `cmPasteText` | — / middle click PRIMARY | paste → one `cmPasteText` | paste → one `cmPasteText` | — |

So: copy = Ctrl+Ins where it arrives (and the terminal's own copy of a
shift-drag selection everywhere), every copy also by OSC 52 (Windows
Terminal, mintty, kitty, WezTerm, foot, iTerm2, VS Code take it; xterm only
with `allowWindowOps`; VTE ignores it; tmux with `set-clipboard on`); cut =
Shift+Del; paste = the terminal's paste, which brings the system clipboard
(and so what the program copied by OSC 52) as one bracketed paste. Ctrl+V
is FV's Ins (`CtrlToArrow`), never a paste key.

**Validation** (design §4.7): `Validator` = a plain function `FN TEXT`, rc 0
= valid, asked by `Valid` (a dialog's `cmOK`) — FV's `TValidator` classes
are after v1.

## Data

| Function | FV | Answer |
|---|---|---|
| `fv.dialogs.getData G ARRAY` | `TGroup.GetData` | the indexed array ARRAY (replaced) gets each data-bearing subview's elements in FV's order — insertion order, the back of `${G}_views` first: a cluster its `Value`, a TParamText its `ParamCount` parameters, a subgroup its subviews' in place, a view of yours what its `GetData` writes; a button, a label, a static text nothing. `RESULT` kept |
| `fv.dialogs.setData G ARRAY` | `TGroup.SetData` | each data-bearing subview takes its elements from ARRAY in the same order and redraws (a radio button's `Sel` follows its `Value`, FV; a value that is no number: 0) |
| `fv.dialogs.dataSize V` | `DataSize` | `RESULT` = the elements V's data takes |

The elements: an input line → its text (one element; `SetData` selects it
all, FV); a list box → `Focused` (its `List` stays the caller's array, the
marks in the caller's `Marks` array; `SetData` keeps the item in the range);
a cluster → `Value`; a TParamText → its parameters.

A view of yours takes part by declaring `func DataSize` (`RESULT` = its
element count), `proc GetData` and `proc SetData`, which receive the array's
**name** and the index of its first element (FV's `var Rec`):

```bash
class TPair : TView
    public
        var A
        var B
        func DataSize
        proc GetData
        proc SetData
end
TPair.DataSize() { RESULT=2; }
TPair.GetData() { local -n r=$1; r[$2]=$A r[$2+1]=$B; }
TPair.SetData() { local -n r=$1; A=${r[$2]} B=${r[$2+1]}; }
build TPair
```

ARRAY must be an identifier that is not `RESULT` and does not start with
`_fv` / `__fv` (any case: this framework's names, which a nameref would
reach instead), and not a (non-empty) associative array: rc 2, `RESULT=''`.

## Setters and helpers

| Function | FV | Answer |
|---|---|---|
| `fv.dialogs.setTitle BTN TEXT` | — | the button's `Title`, redrawn; its hot key at once (the hot-key map rebuilt) |
| `fv.dialogs.setLabel LB TEXT` | — | a label's (or static text's) `Text`, likewise |
| `fv.dialogs.setItems CLUSTER [ITEM]...` | — | the items replaced, `Sel` kept inside them, likewise |
| `fv.dialogs.setButtonState CLUSTER MASK 1\|0` | `SetButtonState` | `EnableMask` bits set / cleared; with at most 32 items the cluster is selectable while one item is enabled (FV); redrawn when the mask changed |
| `fv.dialogs.makeDefault BTN 1\|0` | `MakeDefault` | a button without `bfDefault` takes / gives back the default look (`cmGrabDefault` / `cmReleaseDefault` to the owner) |
| `fv.dialogs.newButton G X Y W H TITLE CMD HELPCTX FLAGS` | `TDialog.NewButton` | a TButton `(X, Y)–(X+W, Y+H)` with `HelpCtx`, inserted into G; `RESULT` = its reserved name `G__fvbtnN` |
| `fv.dialogs.newLabel G X Y TEXT LINK` | `TDialog.NewLabel` | a TLabel `(X, Y)–(X + the text's cells + 1, Y + 1)` inserted into G; `RESULT` = `G__fvlblN` |
| `fv.dialogs.getText IL` | `Data` | `RESULT` = the input line's text (its clusters joined) |
| `fv.dialogs.setText IL TEXT` | `SetData` | the text replaced (control characters dropped, invalid UTF-8 as fv.video's `?`, cut to `MaxLen` clusters), all of it selected (FV), drawn |
| `fv.dialogs.selectAll IL 1\|0` | `SelectAll` | the cursor and the first shown cluster at the start, the whole text selected (1) or nothing (0), drawn |
| `fv.dialogs.newList LB ARRAY [FMT]` | `NewList` | `List` := ARRAY (the caller's indexed array, `''` = none), `Formatter` := FMT (`FMT INDEX WIDTH` → `RESULT`), the range its length, item 0 focused (FV `FocusItem`), drawn; ARRAY checked as for `getData` |

Procedures leave `RESULT` as it was; a refused call is rc 2 with `RESULT=''`
and one debug line (`VERBOSE_KKLASS=debug`). **Set texts with the setters**:
a direct write of `Title`, `Text` or the items works too, and costs one
rebuild of the hot-key map at the next key (its stamp check).

## Deviations from FV

* kklass classes with FV's field names; other instances' fields under the
  kklass friend contract; FV's linked items (`NewSItem`) written flat;
  `TParamText`'s parameters in `NAME_params`, its format `printf -v`'s.
* FV's `var Rec` of `GetData` / `SetData` is an array name and an index;
  `DataSize` counts elements, not bytes; the walk recurses into subgroups
  that have no `DataSize` of their own (FV's TGroup does the same).
* P3-12: the widgets redraw only a changed picture (above); FV redraws on
  every state change. The pixels are the same.
* `TCluster.Draw` covers its rect with blanks (FV's draws nothing).
* A button's title wider than the button starts at its first cell (FV
  writes before its buffer); the press tracking's release place decides; a
  key ends the tracking (fv.views' `_track`: a lost release never holds the
  loop).
* `fv.dialogs.setButtonState` redraws; the setters `setTitle` / `setLabel` /
  `setItems` and the helpers' reserved names are additions.
* The widgets' destructors call TView's `Done` body directly (one dispatch
  per object less when a dialog is destroyed: design §8.1's budget).
* **TInputLine** (design P3-5, M7): the cursor, the selection and `MaxLen`
  count clusters (FV: UTF-16 units; FV can stop inside a surrogate pair or a
  cluster, this line never splits one); `setText` drops control characters
  and cuts to `MaxLen` (FV keeps the raw string); a paste drops control
  characters (FV inserts each character as a key, where Ctrl+Y would clear);
  a key the line does not take is passed on unchanged (FV's CtrlToArrow
  rewrites the event's key code first: an unhandled Ctrl+E goes on as Up
  there); `Validator` is a plain function instead of FV's TValidator; P3-12:
  a cursor move without a picture change writes nothing (FV redraws).
* **TListBox**: `List` is the caller's array (FV's PCollection, disposed by
  NewList); `GetData` answers `Focused` only (FV's record also holds the
  list); `SetData` keeps the item in the range (FV focuses it as given);
  FV's `Insert`, `DeleteItem`, `FreeItem` … are the caller's array
  operations followed by `fv.views.listSetRange`.
* **The history** (3h): `THistoryViewer`'s items are a copy of its list taken
  when it is made (`NAME_hist`, its `List`) — FV's `GetText` reads the store
  on every row, which cannot change while the window runs modal (an override
  that records into the same list from inside it sees the copy); `GetText`
  is not a virtual of the viewer (fv.views' TListViewer model: `List` /
  `Formatter`), `GetSelection` reads `List` (or asks `Formatter`);
  `HistoryWidth` (the horizontal bar's range) counts characters, as the
  viewer's indent does; `LINK` is a view name checked at use (a name that is
  not a live TInputLine acts as FV's nil link); the window's name is
  reserved (`NAME__fvhwN`); a password line is never recorded (FV has no
  password mode); FV's `Load` / `Store` (streams) are not ported.
* Not yet: FV's `ShowMarkers`, `TMultiCheckBoxes`, validators.

## Contract (kcl README §1)

As fv.views': locals `__fvg_*`, painters' arrays `_fvg_*`; fork-free (a
static scan in `014`), `set -eu` clean, the caller's `nocasematch`,
`extglob`, `failglob`, `nullglob`, `noglob`, `globasciiranges`, IFS (digits,
letters, `-`, empty), `pipefail` and locale neither change the answers nor
are changed (`015`). An IFS holding `\x01` (bash's internal quoting byte)
is not supported in fv.views / fv.dialogs (an open item, for a pass of its
own): bash misreads such an IFS in `[[ ]]` and array expansions throughout
fv.views' tree code and garbles `"${@:N}"` slices. fv.dialogs' own code has
no `"${@:N}"` / `"${*:N}"` slice (it shifts); fv.views keeps them in its
elision entry `fv.views._virt` (which every virtual call of this unit goes
through), `drawPart` with painter arguments, `TListViewer.Create` and
`_newReserved` (fv.views README, "Contract"). The input line splices its
cluster arrays with `"${a[@]:I:N}"` slices (bash's own array splice; the same
unsupported IFS case).

**Friend uses of fv.views** (the same framework): reads of `__FV_VW_LIVE`,
`__FV_VW_GRP`, `__FV_VW_CRC`, `__FV_VW_ERRSYM`, `__FV_VW_PAD`, `__FV_VW_MAXW`,
`__FV_VW_C2A`, `__FV_VW_CMDOFF`, the hooks `__FV_VW_PUTEVENT` and
`__FV_VW_TRK`; entries in `__FV_VW_IMPL`, `__FV_VW_FUNC`, `__FV_VW_BCAST`,
`__FV_VW_HKS`, `__FV_VW_HKE` and `__FV_VW_HKK`; calls of `fv.views._virt`, `_message`, `_viewEvent`,
`_viewSetState`, `_windowEvent`, `_windowCalcBounds`, `_groupValid`,
`_topView`, `_track`, `_hk`, `_hkDirty`, `_done`, `_newReserved`, `_ints`,
`_focus`, and for TListBox / THistoryViewer `_lvSetRange`, `_lvFocusNum`,
`_lvEvent`, `_lvName`. fv.histlist: THistoryViewer copies its list from the
store's `__FV_HL_T<ID>` (read only). fv.video: `fv.video._g` (its
locale guard), `fv.video.clusters`, `fv.video.setClipboard` and the read of
`__FV_VS_PNA`, `__FV_VS_P`, `__FV_VS_B`, `__FV_VS_PB`.

**Friend uses of this unit** (stage 3e): [fv.msgbox](../fv.msgbox/README.md)
calls `fv.dialogs._ptCount` (the arguments a `printf` format takes: its
FormatStr, as TParamText's) and `fv.dialogs._aname` (inputBox's VARNAME
check, the rule of `getData`'s ARRAY); it builds its boxes from the public
classes and `getText` / `setText`.

## Cost

Exact counts (`tests/013_CallBudget.sh`, design §8.1's scene: an application
whose `HandleEvent` override calls `inherited`, two windows side by side;
the same in the `fvviews` bench, `views-dialog-80`):

| action | dispatches (limit) | writes (limit) |
|---|---|---|
| Tab between two controls of the modal dialog | 0 (4) | 4 (8) |
| Tab between two buttons | 0 (4) | 2 (8) |
| Space on a check box / Down on radio buttons | 0 (2) | 1 (2) |
| Alt + a hot letter pressing OK (the dialog closes) | 0 (6) | 2 (30) |
| the pre-built dialog opened and closed (F2 … Ctrl+F4) | 5 (6) | 21 (30) |
| the 8-control dialog built, run, closed, destroyed | 25 (30) | 21 (26) |
| the dialog's full draw (`drawView`) | 0 (2) | 13 (24) |
| typing a character into an input line (ASCII, Cyrillic, CJK; Backspace; into a scrolled 70-character line) | 0 (2) | 1 (2) |
| Shift+Left in a scrolled line | 0 (2) | 1 (2) |
| (3h) the typing rows above with a `THistory` after the line | the same | the same |
| (3h) the history window opened by Down on the line (10 strings) and closed by Esc | 10 (14) | 19 (26) |

The dispatches of an open + close are the application's override and
`inherited` for F2 and the windows' list stand-ins redrawn when the dialog
leaves; the end-to-end ones and the history window's are the constructors
(`.new` and `inherited`: the window, its frame, two bars and the viewer).
The times are the CI bench's (design §8.3: the same-run A/B decides the
dialog targets).

## Tests

`bash kcl/fv.dialogs/tests/tests.sh` — headless; `tests/fvg_testlib.sh`
reuses fv.views' test lib and adds the test dialog (`fvg_mkdlg`: 60 × 14, a
static text, two labels, check boxes, radio buttons, OK / Cancel / Help),
the scene, the modal run (`fvg_run`) and the scripted `char` / `alt` keys.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API, the classes' methods, the elision entries (every built-in virtual a body of this unit), the funcs, the broadcast rows, the hot-key texts, the readonly constants; loads under set -eu (twice, by name); the main path under set -eu; `kk.unit --forget` of fv.dialogs / fv.views + re-source; a failing call under set -e; nothing on stdout; no stray names |
| 002_Dialog | the constructor's fields, the three palettes; the modal loop: Esc, Ctrl+F4, the end of input, Enter → the default button, cmYes / cmNo, cmClose, a modeless dialog, Valid refusing then agreeing, Ctrl+F5 → the keyboard move; CalcBounds (FPC 2025's MoveRel: the one-cell rule, scaling, Pascal's Round, GrowMode → TWindow's); a desktop resize during the modal loop |
| 003_Button | the look (colours by state, default, selected, disabled, pressed, a wide and a cut title, bfLeftJust); the default look moving with the focus, makeDefault; hot keys (Alt, post-process plain, Enter / Space when focused, a Cyrillic layout's base key); the modal run (Alt+K, Enter, Enter on Cancel); the mouse (a click presses without focusing, released off / on the shadow, bfGrabFocus); Press (cmRecordHistory first, bfBroadcast); disabled at Init, cmCommandSetChanged redrawn once; setTitle, a direct Title write caught by the map; newButton; refusals |
| 004_StaticText | the wrap (FV_UNICODE: the blank starts the next line, a long word cut, an exactly full line, CR / LF / CRLF, more lines than rows), ^C / ^B per line, wide characters, controls as `?`, the rows cached (one write), a GetText override; TParamText (printf, setData / getData through a group, a bad format, the refusal) |
| 005_Label | the look and Light; P3-12 (a focus change between two buttons draws no label); hot keys (Alt, post-process plain, a focused cluster first, a Cyrillic hot letter, a Latin one through the base key and the layout tables, typed wins over base); clicks; a cut text |
| 006_Cluster | the look (Sel focused, the hot letter, radio mark, the cursor); keys (Down / Up wrapping with one write, Space, WordStar, plain letters when focused, Alt from elsewhere, a radio's MovedTo, post-process plain letters, EnableMask skipped and drawn in 5, a disabled hot letter, setButtonState and ofSelectable); FV's columns and Right / Left; the mouse (press, released off, focusing); Id → cmIdCommunicate; GetHelpCtx; setItems; a Mark override |
| 007_InputLine | the constructor, the look (colours 1 / 2 / 5, `<` / `>`, selection, cursor); editing and selection against a model: seeded random keys over ASCII / Cyrillic / CJK / emoji clusters (moves, Shift selection, word moves, Back, Del, overwrite, Ctrl+Y, MaxLen) — text, positions, cursor and the row's cells and colours after every key, now and then == a full repaint; FV's rules one by one (FirstPos = SizeX − 3, MaxLen with overwrite, the block cursor, keys passed on, P3-12's write counts, a wide cluster at the edge); password mode; SelectAll on focus, the API, Valid with a Validator |
| 008_InputWide | the clusters == fv.video's split of the whole text after every edit: seeded random edits with ZWJ, VS16, modifiers, combining marks, flags (re-pairing) typed, deleted, overwritten and pasted over a selection mid-line, the text, cursor and selection == a text model (FV's Delete then Insert at the same offset); the cases one by one; replace next to a dangling ZWJ / a lone indicator (F2); a 2-cell line with an orphan first cluster (F5) |
| 009_InputMouse | clicks (wide halves, past the text), double click, drags both ways, a key / the end of input ending a drag, drag-scroll by `evMouseAuto` past both edges, the `<` / `>` cells, a click focusing an unfocused line |
| 010_ListBox | the constructor, newList (formatter, replacement, `''`, the alias, refusals), DataSize / GetData / SetData and through a dialog, the long checklist (Space / Ins marks over 10 000 items, `cmListItemSelected`, colour 4) |
| 011_Data | dataSize, getData / setData order and redraw, a non-number, a view of yours with DataSize 2 behind the frame, a subgroup, TParamText; refusals |
| 012_Focus | Tab / Shift+Tab order (each == a full repaint), arrows on buttons and clusters, a disabled button skipped; user pre / post views interleaved with the widgets (the Phase each sees, a hot key handled in pre stops them); the focus broadcasts (default look, Light) |
| 013_CallBudget | design §8.1's budgets (the table above), each logged; == a full repaint after open + close and after the end-to-end dialog; the dialog's draw == a full repaint (3d: typing ASCII / Cyrillic / CJK, Backspace, a scrolled line, Shift+Left; 3h: the same with a THistory after the line, the history window open + close) |
| 014_ZeroFork | the whole path with `PATH=''`; the static scan of `fv.dialogs.sh` (3d: an input line and a list box through every path) |
| 015_CallerState | one dialog scene under every caller setup: the same output, the state kept (3d: an input line — drawn with a non-ASCII `PasswordChar` too — and a list box in the scene) |
| 016_Elision | a dialog of subclasses overriding every virtual with `inherited` == the built-in dialog (result, data, picture); 0 dispatches of the built-ins; an overridden HandleEvent never skipped by the map; the func answers and the rc answers through overrides (3d: TInputLine / TListBox subclasses overriding every virtual) |
| 017_Palette | every widget's palette through CGrayDialog / CBlueDialog / CCyanDialog == CAppColor's entries (3d: CInputLine, CListViewer in a dialog) |
| 018_HotKeyMap | the hot-key map with the real widgets, each scene == a full scan and the expected reaction: a typed letter on a disabled button, a masked cluster item or a button without pre / post options next to a base match (the base view reacts), an enabled typed match winning (the designed difference); nested groups with pre / post in both orders (the inner pass does not leak; an outer typed match wins over an inner base match); a subclass overriding HandleEvent (asks in the typed pass, else without one: the differential's seed 54 and 76 shapes); a typed letter written away directly (the map rebuilt before the pass); the focus moved to a button during the key (pressed in the post phase); the Phase a full scan leaves; direct writes of a cluster's `_items` element and a label's `Text` while unfocused |
| 019_History | (3h) THistory / THistoryViewer / THistoryWindow: the constructors and their refusals; the look `▐v▌` and its colours, a wider view, ASCII `[v]`, the palettes through CHistoryWindow; Down on the focused line (the text recorded, FV's rect, modal, item 1), Esc / the close icon (the text kept, the window destroyed, == a full repaint), Down Down Enter (the chosen text, all selected, drawn), Ctrl+X, a click and a double click on a row, a click on the view, Down on an unfocused line (nothing), one string (item 0); CJK / emoji texts cut to MaxLen clusters; the rect at the owner's edges; recording on Tab, on OK by the mouse and by Enter (both lines), Esc (only the focused line), never in password mode; the hot-key map calls THistory for kbDown / kbCtrlX only |
| 021_Ascii | ASCII mode: no shadow characters, the pressed look, marks, a Cyrillic label and a CJK static text one `?` per character, cluster columns from those cells; each == a full repaint (3d: an input line: one cell per non-ASCII character, FirstPos by those cells) |
| 022_Clipboard | Ctrl+Ins (FV_CLIPBOARD + the OSC 52 bytes), Shift+Del, Shift+Ins / cmPaste, cmPasteText (control characters dropped, over a selection, overwrite, MaxLen, non-ASCII == fv.video's split), a paste in a modal dialog never pressing the default button, password mode refusing copy and cut, an unselected line taking nothing; a 20 000-character paste / `setText` (Cyrillic, mixed CJK / ZWJ / flags) into `MaxLen` 255 / 253: its first clusters, under 1 s (F1) |
| 023_HistoryState | (3h) the history path with `PATH=''` (the reference answers); the same scene under IFS default / `\x1f` / empty, nocasematch, extglob, a C locale, set -u and all at once (answers and state kept; the windows made under the setup); 100 open / close cycles leave no view, array or function and no table grows; a subclass overriding every virtual with `inherited` == the built-in; overrides of `InitHistoryWindow` (a window class of yours) and `RecordHistory` used |
