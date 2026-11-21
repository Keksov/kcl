# kcl/fv.dialogs — the dialogs of the fv.* text UI

Layer L3 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P3_DESIGN.md](../docs/dev/fv/P3_DESIGN.md) §1–§3, §4.6). Free Vision's
`Dialogs` unit (FV `dialogs.inc`, FPC 2025) as [kklass](../../kklass/README.md)
classes on [fv.views](../fv.views/README.md)' `TView` / `TWindow`, with FV's
field names and fv.views' virtual elision: every built-in virtual runs as a
plain function unless a class of yours overrides it.

**Status: P3 stage 3c** — `TDialog`, `TButton`, `TStaticText`, `TParamText`,
`TLabel`, `TCluster`, `TCheckBoxes`, `TRadioButtons`, the data transfer, the
setters and FV's `NewButton` / `NewLabel`; hot keys through fv.views' hot-key
map (any keyboard layout, design §14). `TInputLine` and `TListBox` come with
stage 3d, `THistory` / `THistoryViewer` / `THistoryWindow` with 3h.

The unit loads `kklass_pascal` and `fv.views`.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.app fv.dialogs

TDialog.new dlg 10 4 70 18 'Find'                       # FV Init(R, ATitle)
TStaticText.new st 3 1 57 3 $'\x03''Search options'     # ^C: centred
TLabel.new l1 2 3 14 4 '~T~ext' opts                    # Init(R, AText, ALink)
TCheckBoxes.new opts 3 4 30 7 '~C~ase sensitive' '~W~hole words'
TRadioButtons.new dir 32 4 56 6 '~F~orward' '~B~ackward'
TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"  # Init(R, ATitle, ACommand, AFlags)
TButton.new cn 26 10 38 12 'Cancel' cmCancel
for v in st l1 opts dir ok cn; do fv.views.insert dlg "$v"; done
fv.views.select opts                                    # the first control (FV programs: SelectNext)

REC=(1 0); fv.dialogs.setData dlg REC                   # opts' Value 1, dir's 0
fv.views.execView "$FV_DESKTOP" dlg
if [[ $RESULT == cmOK ]]; then fv.dialogs.getData dlg REC; echo "options ${REC[0]}, direction ${REC[1]}"; fi
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

* Corners, B exclusive, as every fv.views constructor (D1). FV's `NewSItem`
  chain is the items written flat after the bounds.
* **Refused before anything is made** (rc 2, one `Error: fv.dialogs:` line on
  stderr, `VERBOSE_KKLASS=quiet` silences it; `.delete` the bare instance):
  a `TButton` without a TITLE and a COMMAND, a COMMAND that is not a command
  name (letters, digits, `_`), FLAGS that are not digits; a `TParamText`
  PARAMCOUNT that is not digits. fv.views' own refusals (a live name, a
  reserved name, bounds) apply too.
* Constants (readonly): `FV_BF_NORMAL DEFAULT LEFTJUST BROADCAST GRABFOCUS`
  (0 1 2 4 8, FV `bf*`), `FV_DP_BLUEDIALOG CYANDIALOG GRAYDIALOG` (0 1 2).
* Defaults (FV's Init): **TDialog** `GrowMode` 0, `Flags` `wfMove + wfClose`,
  no number; **TButton** `EventMask` + `evBroadcast`, `ofSelectable +
  ofFirstClick + ofPreProcess + ofPostProcess`, `sfDisabled` when COMMAND is
  disabled (fv.views' command set), `AmDefault` 1 with `bfDefault`;
  **TLabel** `ofPreProcess + ofPostProcess`, `EventMask` + `evBroadcast`,
  `Light` 0; **TCluster** `ofSelectable + ofFirstClick + ofPreProcess +
  ofPostProcess`, `Sel` 0, the cursor at (2, 0) shown, `EnableMask`
  `$FFFFFFFF`, `Value` and `Id` 0.

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
| data-bearing views | `DataSize` (func), `GetData ARRAY INDEX`, `SetData ARRAY INDEX` (procs) | | "Data" below |

A class of yours overrides any of them and calls the built-in with
`inherited NAME "$@"`; an override costs one dispatch per use (fv.views
README, "Virtual elision"). `Mark` and `Valid` answer by their rc.

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
  monochrome look); marks and arrows as in UTF-8 mode.

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
* The broadcast table rows (fv.views' `__FV_VW_BCAST`): TButton `cmDefault
  cmGrabDefault cmReleaseDefault cmCommandSetChanged`, TLabel
  `cmReceivedFocus cmReleasedFocus`, TDialog `cmSelectWindowNum`, TCluster
  none.

## Data

| Function | FV | Answer |
|---|---|---|
| `fv.dialogs.getData G ARRAY` | `TGroup.GetData` | the indexed array ARRAY (replaced) gets each data-bearing subview's elements in FV's order — insertion order, the back of `${G}_views` first: a cluster its `Value`, a TParamText its `ParamCount` parameters, a subgroup its subviews' in place, a view of yours what its `GetData` writes; a button, a label, a static text nothing. `RESULT` kept |
| `fv.dialogs.setData G ARRAY` | `TGroup.SetData` | each data-bearing subview takes its elements from ARRAY in the same order and redraws (a radio button's `Sel` follows its `Value`, FV; a value that is no number: 0) |
| `fv.dialogs.dataSize V` | `DataSize` | `RESULT` = the elements V's data takes |

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
* Not in 3c: `TInputLine`, `TListBox` (3d), history (3h); FV's
  `ShowMarkers`, `TMultiCheckBoxes`.

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
`_newReserved` (fv.views README, "Contract").

**Friend uses of fv.views** (the same framework): reads of `__FV_VW_LIVE`,
`__FV_VW_GRP`, `__FV_VW_CRC`, `__FV_VW_ERRSYM`, `__FV_VW_PAD`, `__FV_VW_MAXW`,
`__FV_VW_C2A`, `__FV_VW_CMDOFF`, the hooks `__FV_VW_PUTEVENT` and
`__FV_VW_TRK`; entries in `__FV_VW_IMPL`, `__FV_VW_FUNC`, `__FV_VW_BCAST`,
`__FV_VW_HKS` and `__FV_VW_HKE`; calls of `fv.views._virt`, `_message`, `_viewEvent`,
`_viewSetState`, `_windowEvent`, `_windowCalcBounds`, `_groupValid`,
`_topView`, `_track`, `_hk`, `_hkDirty`, `_done`, `_newReserved`, `_ints`.
fv.video: `fv.video._g` (its locale guard) and the read of `__FV_VS_PNA`,
`__FV_VS_P`, `__FV_VS_B`, `__FV_VS_PB`.

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

The dispatches of an open + close are the application's override and
`inherited` for F2 and the windows' list stand-ins redrawn when the dialog
leaves; the end-to-end ones are the constructors (`.new` and `inherited`).
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
| 011_Data | dataSize, getData / setData order and redraw, a non-number, a view of yours with DataSize 2 behind the frame, a subgroup, TParamText; refusals |
| 012_Focus | Tab / Shift+Tab order (each == a full repaint), arrows on buttons and clusters, a disabled button skipped; user pre / post views interleaved with the widgets (the Phase each sees, a hot key handled in pre stops them); the focus broadcasts (default look, Light) |
| 013_CallBudget | design §8.1's budgets (the table above), each logged; == a full repaint after open + close and after the end-to-end dialog; the dialog's draw == a full repaint |
| 014_ZeroFork | the whole path with `PATH=''`; the static scan of `fv.dialogs.sh` |
| 015_CallerState | one dialog scene under every caller setup: the same output, the state kept |
| 016_Elision | a dialog of subclasses overriding every virtual with `inherited` == the built-in dialog (result, data, picture); 0 dispatches of the built-ins; an overridden HandleEvent never skipped by the map; the func answers and the rc answers through overrides |
| 018_HotKeyMap | the hot-key map with the real widgets, each scene == a full scan and the expected reaction: a typed letter on a disabled button, a masked cluster item or a button without pre / post options next to a base match (the base view reacts), an enabled typed match winning (the designed difference); nested groups with pre / post in both orders (the inner pass does not leak; an outer typed match wins over an inner base match); a subclass overriding HandleEvent (asks in the typed pass, else without one: the differential's seed 54 and 76 shapes); a typed letter written away directly (the map rebuilt before the pass); the focus moved to a button during the key (pressed in the post phase); the Phase a full scan leaves; direct writes of a cluster's `_items` element and a label's `Text` while unfocused |
| 017_Palette | every widget's palette through CGrayDialog / CBlueDialog / CCyanDialog == CAppColor's entries |
| 021_Ascii | ASCII mode: no shadow characters, the pressed look, marks, a Cyrillic label and a CJK static text one `?` per character, cluster columns from those cells; each == a full repaint |
