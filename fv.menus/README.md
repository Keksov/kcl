# kcl/fv.menus — the status line and the menus of the fv.* text UI

Layer L2 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P2_DESIGN.md](../docs/dev/fv/P2_DESIGN.md)). Free Vision's `TStatusLine`
(FV `menus.inc`: `TStatusDef` / `TStatusItem`, `NewStatusDef` /
`NewStatusKey`, `Draw` / `DrawSelect`, `FindItems`, `HandleEvent` with the
mouse press tracking, `Hint`, `Update`) as a [kklass](../../kklass/README.md)
class on [`fv.views`](../fv.views/README.md)' `TView`; since P3 stage 3f
the menus: `TMenuView`, `TMenuBar`, `TMenuBox`, `TMenuPopup`, the bar on
request (`fv.menus.menuBar`, D23) and the status line's hint table
(`fv.menus.setHint`, D22) — ["Menus"](#menus-p3-stage-3f).

The unit loads `kklass_pascal` and `fv.views`.

**Status: P2 complete (stage 2g; `TStatusLine` since 2e); P3 done (stage 3f: the
menus; the speed work deferred, "Cost").** The application ([`fv.app`](../fv.app/README.md),
stage 2f) makes the status line in its `InitStatusLine`, holds it in
`FV_STATUSLINE` and calls its `Update` from `Idle`; without an application
a script inserts it itself.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.menus

# FV:  New(PStatusLine, Init(R,
#        NewStatusDef(0, 99,
#          NewStatusKey('~Alt+X~ Exit', kbAltX, cmQuit,
#          NewStatusKey('~F10~ Menu', kbF10, cmMenu,
#          NewStatusKey('', kbF6, cmNext, nil))),
#        NewStatusDef(100, 199,
#          NewStatusKey('~F1~ Help', kbF1, cmHelp, nil), nil))))
TStatusLine.new st 0 23 80 24 \
    def 0 99    '~Alt+X~ Exit' kbAltX cmQuit  '~F10~ Menu' kbF10 cmMenu  '' kbF6 cmNext \
    def 100 199 '~F1~ Help' kbF1 cmHelp

st.AddDef 200 299                     # = fv.menus.addDef st 200 299
st.AddItem '~F2~ Save' kbF2 cmSave    # into the last def
fv.views.insert app st                # app: the root (fv.app from stage 2f)

fv.menus.update st                    # FV Update (fv.app's Idle does it)
```

A class of yours shows a hint for the focused view's help context:

```bash
class TMyStatus : TStatusLine
    public
        override func Hint
end
TMyStatus.Hint() { if (( $1 == 100 )); then RESULT='Edit the file'; else RESULT=''; fi; }
build TMyStatus
```

## The class

| class | fields |
|---|---|
| `TStatusLine : TView` | TView's 13 (`HelpCtx` is the context the items were found for). FV's `Items` and `Defs` pointers are per-instance arrays (below) |

* **`TStatusLine.new NAME AX AY BX BY [def MIN MAX] [TEXT KEY CMD]...`** is FV's
  `Init(Bounds, ADefs)`: TView's constructor (corners, B exclusive), then
  `Options` += `ofPreProcess`, `EventMask` += `evBroadcast` (785),
  `GrowMode` = `gfGrowLoY + gfGrowHiX + gfGrowHiY`, the defs, `FindItems`.
* **The list after the bounds is FV's `NewStatusDef` / `NewStatusKey` chain
  written flat** ("constructor triples"): `def MIN MAX` opens a def
  (`NewStatusDef(MIN, MAX, …)`), each triple `TEXT KEY CMD` is an item of the
  def above it (`NewStatusKey(TEXT, KEY, CMD, …)`). Triples before any `def`
  go into an implicit `def 0 65535`. A word `def` is a def only when two
  numbers follow it; an item whose text is `def` has a key name or `''`
  second, so it never reads as one.
  * `TEXT`: FV's text with `~` around the highlighted part; `''` = a
    key-only binding (FV's `NewStatusKey('', kbF10, cmMenu, …)`): not drawn,
    not clickable.
  * `KEY`: an [fv.keyboard](../fv.keyboard/README.md) key name (`kbF10`,
    `kbAltX`, `kbCtrlF5`: `kb` + letters and digits, case-sensitive), or `''`
    for a click-only item.
  * `CMD`: a command name (letters, digits, `_`).
  * `MIN`, `MAX`: help-context numbers (digits).
* A malformed list is refused **before anything is made**, as TView refuses
  bad bounds: rc 2, one `Error: fv.menus: TStatusLine.Create: …` line (silent
  under `VERBOSE_KKLASS=quiet`); NAME is then no view (`NAME.delete` frees the
  bare instance). TView's own refusals (re-creating a live view, a reserved
  name, bad bounds) are fv.views'; re-creating a live status line also frees
  its arrays.
* `NAME.delete` (FV `Done`) frees the line's arrays, then TView's part.

### Virtual methods

| method | kind | FV |
|---|---|---|
| `Draw` | proc | `DrawSelect(nil)`: "Drawing" below |
| `HandleEvent` | proc | keys, the press tracking, `cmCommandSetChanged`: "Events" below |
| `GetPalette` | func | `2 3 4 5 6 7` (FV `CStatusLine`) |
| `Hint HELPCTX` | func | the line's hint table's text for HELPCTX (`fv.menus.setHint`, stage 3f; FV: `''`), `''` without one; a class of yours answers the text shown after the items |
| `Update` | proc | the items for the top view's help context: "Update" below |

All five are built-in bodies in fv.views' elision table (`__FV_VW_IMPL`), so
the framework runs them without a kklass dispatch unless your class overrides
them ([fv.views README, "Virtual elision"](../fv.views/README.md#virtual-elision));
`Hint` answers in `RESULT` on both paths (fv.views' RESULT rule). `Update` is
virtual in FV too; the design's list (§1.3) leaves it out (a deviation
in FV's favour).

### The plain API

Every function: the line first; rc 2 for a malformed call (not a status line,
a wrong argument count, a bad key, command or number), `RESULT=''` and one
debug line under `VERBOSE_KKLASS=debug`. Procedures leave `RESULT` alone.

| Function | FV | Answer |
|---|---|---|
| `fv.menus.addDef SL MIN MAX` | `NewStatusDef` | a def appended after the line's defs; the items added next go into it. Redrawn when the def shown changed |
| `fv.menus.addItem SL TEXT KEY CMD` | `NewStatusKey` | an item appended to the **last** def (an implicit `def 0 65535` on a line without defs). Redrawn when it shows in the def drawn |
| `fv.menus.update SL` | `Update` | the line's `Update` through the elision (an override of yours runs); rc 0 |

The aliases `AddDef` and `AddItem` (decision D16: set-up code) call the first
two with `$this`.

### Defs, items and the key map

FV keeps a chain of defs, each with a chain of items. Here they are arrays of
the instance (kcl §1.9), items contiguous per def because items are only
appended to the last def:

| array | content |
|---|---|
| `${SL}_sdmin`, `${SL}_sdmax`, `${SL}_sdfirst` | def i's range and its first item (its items end where def i+1's begin) |
| `${SL}_sitext`, `${SL}_sikey`, `${SL}_sicmd` | item j's text, key, command |
| `${SL}_skey` (assoc) | **the key map**: `"DEF:KEY"` → the first item of the def with that key; `${SL}_sinext[j]` = the next item of the same def with the same key (-1 none). Built as items are added, once per def |
| `${SL}_siplain`, `${SL}_sipat` | item j as drawn (`' TEXT '` without the `~`) and its cell pattern (`+` Lo, `-` Hi per display cell), made at the first draw for the screen's ASCII mode |

A key press costs one associative lookup plus a walk of that key's chain
(FV walks every item). `FindItems` (FV: the first def with `Min <= HelpCtx <=
Max`) keeps the def's index; read these arrays, change them only through the
functions.

## Drawing

FV `DrawSelect` in **one** `fv.views.writeLine` (design §1.5): the current
def's items that have a text, each `' TEXT '` with the `~` parts in the Hi
colour, then — when `Hint(HelpCtx)` is not `''` — `│` (ASCII mode: `|`), a
blank and the hint, then blanks to the width:

| item | colours (CStatusLine entry: Lo / Hi) | default symbols |
|---|---|---|
| enabled | CNormal 1 / 3 | `2` / `4` (black / red on grey) |
| disabled (`commandEnabled` says no) | CNormDisabled 2 / 2 | `3` |
| pressed, enabled | CSelect 4 / 6 | `5` / `7` |
| pressed, disabled | CSelDisabled 5 / 5 | `6` |
| hint, bar, blanks | 1 | `2` |

* Widths are display cells (fv.video's width table: a CJK character takes 2,
  `~` none; in ASCII mode each non-ASCII character is one `?`). An item whose
  `~` cuts a character cluster is drawn in Lo only.
* **"Draw must cover its rect"**: the row is padded to the line's width; a
  line taller than one row gets the rows below blanked by one `fill` (FV
  writes row 0 only). Items wider than the line are clipped to it.
* The press tracking draws through `fv.views.drawPart` with the plain painter
  `fv.menus._paintSel` (no dispatch).

## Events

`HandleEvent` (FV `TStatusLine.HandleEvent`):

* **`evKeyDown`**: the first item of the current def with that key whose
  command is enabled → `evCommand CMD` posted with `__FV_VW_PUTEVENT` (FV
  `PutEvent`; the posted record has the key and mouse fields cleared and
  `FV_EV_INFO` `''`, FV's `InfoPtr := nil`), and the key handled
  (`clearEvent`: `evNothing`, `FV_EV_INFO` = the line). The line has
  `ofPreProcess`, so it sees a key **before** the focused view; a key it does
  not take goes on.
* **`evMouseDown`** (TView's click-to-focus first; a status line is not
  selectable): **the press tracking** — repeat: the item under the pointer
  (cells of `' TEXT '` from the left, the point inside the line), drawn
  pressed when it changed; until `fv.views.mouseEvent "$SL" "$FV_EM_MOUSEMOVE"`
  says the button is up. The event record is saved before the loop and put
  back after it (design §2.2; the inner loop's events are its own). A release
  on an item whose command is enabled posts that command; the event is
  handled; the line is drawn plain again when an item was shown pressed. The
  end of input ends the loop (fv.views' latch) and posts nothing.
* **`evBroadcast cmCommandSetChanged`**: redrawn when the greyed state of
  its items changed (FV redraws always; the pixels are the same). Not
  handled: the broadcast goes on. `fv.views._quiet` answers "not quiet" for
  the line (its handler is not TView's or TGroup's), so the broadcast reaches
  it; every broadcast into the line's owner is dispatched to it for the same
  reason.

### Update

FV `Update`: `H` := the top view's `GetHelpCtx` (`fv.views._topView`: the
view `execView` runs, else the first owner with `sfModal`; `hcNoContext`
without one); when `H` differs from the line's `HelpCtx`: `HelpCtx := H`,
`FindItems`, `DrawView`. fv.app's `Idle` calls it on every idle tick, so the
unchanged case is a few reads plus the `GetHelpCtx` chain (elided: no
dispatch unless a class on it overrides `GetHelpCtx`). **D17**: a changed
`HelpCtx` redraws only when the built-in Draw would show something else
(another def, another `Hint`); a class that overrides `Draw` is redrawn on
every change, as in FV.

### What fv.app does with it (stage 2f)

* `InitStatusLine` makes the line under the reserved name
  `fv.views._newReserved "$app" status TStatusLine AX AY BX BY LIST…`
  (`app__fvstatus`) on the last row, inserts it **after** the desktop (in
  front, as FV's `TProgram.Init`) and sets `FV_STATUSLINE`. FV's
  `StdStatusKeys` (Alt+X, F10, Alt+F3, F5, Ctrl+F5, F6, Shift+F6) belongs to
  fv.app (FV `app.pas`): key-only triples `'' kbAltX cmQuit '' kbF10 cmMenu …`.
* `Idle`: `fv.views._virt "$FV_STATUSLINE" Update` (or `fv.menus.update`),
  then the `cmCommandSetChanged` broadcast when `FV_COMMANDSETCHANGED` is set.
* The posted commands go through `__FV_VW_PUTEVENT`; fv.app's `PutEvent`
  replaces it like fv.views' other hooks.

## Performance

Git-bash 5.3.15, 80 × 24, headless (frames to `/dev/null`), an
application-like scene (an app group with a `TMyApp`-like `HandleEvent`
override, a desktop, two `TWindow`s side by side, the status line), median of 5 × 20 actions
in one process, quiet machine, 2026-11-17 (stage 2e):

| action | dispatches | fv.video writes | ms |
|---|---|---|---|
| a status line draw (`fv.views.drawView st`, with the terminal update) | 0 | 1 | 1.24 |
| `Update`, no change (an idle tick) | 0 | 0 | 0.42 |
| `Update` after a `HelpCtx` change (another def) | 0 | 1 | 1.98 |
| a key mapped to a command, through the app's dispatch | 2 (the app's override + `inherited`) | 0 | 0.87 |
| a press + release on an item (the tracking loop, two drawParts) | 2 | 2 (pressed, plain) | 4.71 |

The counts are pinned by the tests (`fvw_budget`, the write counter); the
times are early-warning numbers.

**Stage 2g** (the design's scene through the application, fv.app's
`014_CallBudget.sh`): the line draws with 1 write and no dispatch; Tab as F6
→ the line (pre-process) → `cmNext` costs 5 dispatches side by side, of
which the key's own pass is 2 (TMyApp + `inherited`; the line is elided).
Inside `app.Run` (the `fvviews` bench, [fv.views "Cost"](../fv.views/README.md#cost))
the line's pre-process look-up of a key nobody takes is ~0.2 ms of the
~5.8 ms a key event costs on that (~1.9× slow) machine.

## Menus (P3 stage 3f)

Free Vision's menus (FV `menus.inc`: `TMenuView` with `Execute`, `FindItem`,
`HotKey`, `GetHelpCtx`, `NewSubView`, `HandleEvent` / `DoSelect`;
`TMenuBar`, `TMenuBox`, `TMenuPopup`; `NewItem` / `NewLine` /
`NewSubMenu`), decisions **D22** (menus in v1, full) and **D23** (the bar
only on request), design [P3_DESIGN.md §7](../docs/dev/fv/P3_DESIGN.md).

```bash
kk.uses fv.app

class TMyApp : TApplication
    public
        override proc InitMenuBar
end
TMyApp.InitMenuBar() {
    fv.menus.menuBar \
        sub '~F~ile' \
            item '~O~pen...' F3 kbF3 cmOpen 1001 \
            item '~S~ave' F2 kbF2 cmSave 1002 \
            line \
            item 'E~x~it' Alt+X kbAltX cmQuit 1003 \
        end \
        sub '~W~indow' 1100 \
            item '~N~ext' F6 kbF6 cmNext 1101 \
            sub '~L~ayout' item '~T~ile' '' '' cmTile 0 item '~C~ascade' '' '' cmCascade 0 end \
        end
}
build TMyApp
TMyApp.new app
fv.menus.setHint "$FV_STATUSLINE" 1001 'Open a file'    # the hint table (D22)
app.Run           # F10 / Alt+F / a click opens the bar; cmOpen ... reach HandleEvent
```

### The classes

| class | fields | FV |
|---|---|---|
| `TMenuView : TView` | TView's + `ParentMenu` (the parent menu view, `''` none), `Menu` (`OWNER:S`: submenu `S` of the items `OWNER` holds; `''` = FV nil), `Current`, `OldItem` (item indices, `-1` = nil) | `TMenuView` |
| `TMenuBar : TMenuView` | — | `TMenuBar`: `GrowMode` `gfGrowHiX`, `ofPreProcess`; `Draw`, `GetItemRect` |
| `TMenuBox : TMenuView` | — | `TMenuBox`: sized by its items, `sfShadow`, `ofFramed` + `ofPreProcess`; `Draw`, `GetItemRect` |
| `TMenuPopup : TMenuBox` | — | `TMenuPopup`: no parent, its own items; `HandleEvent` |

* **`TMenuView.new NAME AX AY BX BY [LIST]`** (FV `Init(Bounds)`: TView's +
  `evBroadcast`), **`TMenuBar.new NAME AX AY BX BY [LIST]`** (FV
  `Init(Bounds, AMenu)`), **`TMenuBox.new NAME AX AY BX BY [LIST]`** (FV
  `Init(Bounds, AMenu, nil)`: width 5 + the widest `' NAME '` [+ `' - '
  PARAM`], height 2 + the items, shortened from the top-left corner of the
  bounds or moved left / up to fit, as FV), **`TMenuPopup.new NAME AX AY BX
  BY LIST`** (FV `Init(Bounds, AMenu)`).
* **LIST** is FV's chain written flat (as the status line's items):

  | words | FV |
  |---|---|
  | `item TEXT PARAM KEY CMD HELPCTX` | `NewItem(Name, Param, KeyCode, Command, HelpCtx)`; `KEY` `''` or a key name (`kbF3`, `kbAltX`), `CMD` a command name, `HELPCTX` digits (`''` = 0, hcNoContext) |
  | `line` | `NewLine` |
  | `sub TEXT [HELPCTX] … end` | `NewSubMenu(Name, HelpCtx, NewMenu(…))`, nested freely |

  A view made with a LIST owns its items (`Menu` = `NAME:0`, freed by its
  destructor). A malformed list is refused **before anything is made**: rc 2,
  one `Error: fv.menus: CLASS.Create: 'NAME': …` line (an item without its
  five fields or with an empty `TEXT`, a bad key / command / `HELPCTX`, a
  `sub` without `end` or an `end` without `sub`, an unknown word). The
  re-creation guard and the bounds are TView's.
* **`fv.menus.newSubView V AX AY BX BY MENU PARENT`** (FV `NewSubView`, not
  virtual there either): a `TMenuBox` named `PARENT__fvbox` for `MENU`
  (`OWNER:S`, borrowed: the box frees nothing of it) with `ParentMenu`
  `PARENT`, sized inside the bounds; `RESULT` = its name; not inserted. rc 2
  for a malformed call.

### Virtual methods

| method | kind | FV |
|---|---|---|
| `HandleEvent` | proc | TMenuView's: "Events" below; `TMenuPopup` adds its keys |
| `GetPalette` | func | `2 3 4 5 6 7` (FV `CMenuView`, the status line's entries) |
| `GetHelpCtx` | func | the current item's `HelpCtx`, walking up the parent menus: below |
| `Execute` | func | FV's loop: below; `RESULT` = the command, `''` for none |
| `GetItemRect ITEM` | proc | FV `GetItemRectX`: the item's local rect in `FV_RECT_*`; TMenuView's an empty rect, `TMenuBar`'s and `TMenuBox`'s FV's |
| `Draw` | proc | `TMenuBar`, `TMenuBox` |

All are built-in bodies in fv.views' elision table (no dispatch unless a
class of yours overrides one); the broadcast table lists TMenuView's and
TMenuPopup's handlers for `cmCommandSetChanged` only.

### The model

FV's `TMenuItem` / `TMenu` records are arrays of the owner `O` (kcl §1.9),
each submenu's items contiguous, submenu 0 the top menu:

| array | content |
|---|---|
| `${O}_mtext`, `_mparam`, `_mkey`, `_mcmd`, `_mhelp` | item i's Name (`''` = a separator), Param, KeyCode, Command (`''` for a submenu or a separator), HelpCtx |
| `${O}_msub` | the submenu of a `sub` item |
| `${O}_mdis` | FV's `Disabled` (0 / 1): from the command set when made (FV `NewItem`), then by `cmCommandSetChanged` (FV `UpdateMenu`) |
| `${O}_mfirst`, `_mlast`, `_mdef` | submenu s's first / last item and its `Default` (FV `TMenu.Default`: the first item, then the last one chosen) |
| `${O}_mkmap` (assoc) + `_mknext` | **the key map**: `KEY` → the first item of the tree with that key in FV `HotKey`'s depth-first order; a chain to the next one. FV walks every item on every key the bar pre-processes; here one lookup |
| `${O}_mhot` (assoc) + `_mhnext` | **the hot letters**: `S:L` → the first item of submenu S whose hot letter (the character after its first `~`, folded — Cyrillic, Greek, …) is L; a chain |
| `${O}_mpl`, `_mpp`, `_mqpl`, `_mqpp` | `' NAME '` and the Param as drawn, their cell patterns (made for the screen's ASCII mode at the first draw) |

Read them; change items only by making the view again.

### Execute (FV TMenuView.Execute)

`Execute` reads its own events from the application's event source
(`__FV_VW_GETEVENT`: the resizes and `Idle` run while a menu is open) and
does what FV's loop does:

* **mouse**: a press in the view or on the parent bar's current item tracks
  the item under the pointer (a bar then auto-selects: its box drops), a drag
  over a parent menu returns to it (the event goes up), a release on an item
  chooses it, on the parent bar's item keeps the box with its Default, a press
  outside every menu closes them all;
* **keys** (through `CtrlToArrow`): Up / Down move with wrapping and skip
  separators (on a bar Down drops the box), Left / Right move on the top menu
  and return from a box (the key goes up: the neighbouring submenu drops),
  Home / End, Enter selects (a bar: drops), **Esc** closes (below), a plain typed
  character selects the item with that hot letter, Alt+letter selects the
  TOP menu's item (from a box: the event goes up), any other key asks the top
  menu's **HotKey** (an F-key …: its enabled command ends the menu). **F10
  inside an open menu does nothing** (FV: it falls to HotKey, which finds no
  item with F10);
* a submenu item selected: its box made by `newSubView` under the item (from
  the item's left edge, below it, to the owner's size), **executed by the
  view's owner** (`fv.views.execView`: for the bar's boxes the application,
  so a box sits beside the desktop, never in a window) and destroyed after
  its run; a command it answers ends this level too;
* **Esc**: in a box under the bar it closes the box **and the bar** (FV,
  menus.inc 673-676: the box leaves the Esc in the event, the loop puts it
  back and the bar reads it); in a nested box it closes only that box (FV
  clears it there: the parent box shows again); on the bar alone it leaves
  the bar;
* the **end of input** (the latch) closes every level with no command; a
  failing event source counts as the end of input; **in a subshell** the
  loop refuses (rc 2, the BASHPID rule, as execView);
* the event record is saved and put back (FV's local `E`); an event that
  ends a nested level is put back (`PutEvent`) for its parent; at the end the
  current item becomes the submenu's Default and the view is drawn plain.

A highlight move in a box repaints the old and the new row (two one-row
`drawPart`s, FV's `OldItem` trick); the bar is drawn whole (one write).

### Events (TMenuView.HandleEvent: the bar)

The bar has `ofPreProcess`, so the application hands it every key first:

* a key with Alt whose hot letter names a top item → **DoSelect**: the event
  put back, the bar run modal by its owner (`fv.views.execView`), a command it
  answers posted as `evCommand` (FV `DoSelect`); the event handled;
* any other key in the **key map** whose command is enabled → that command
  posted (FV `HotKey`), the key handled; else the key goes on;
* `evMouseDown` (the application's positional dispatch) and `evCommand
  cmMenu` (F10: the status line's StdStatusKeys post it) → DoSelect;
* `evBroadcast cmCommandSetChanged` → `Disabled` from the command set (FV
  `UpdateMenu`, the whole tree below its menu); the view redrawn only when
  what it drew changed (D17; FV redraws when any item changed).

**Hot letters and the layout** (D30, §14.4): the typed character
(`FV_EV_CHAR`, folded) first; then — for a typed character that is not
ASCII, or none — the base-layout key (`FV_EV_BASE`; for a plain character
the layout tables, `fv.keyboard.layoutBase`): the order of
`fv.views.hotKeyIs` applied to the hot-letter map. So `~Ф~айл` opens on its
own key, a Latin `~F~ile` with a Russian layout (Alt+а on the US f key), and
an AZERTY Alt+A never counts as the US `q`.

**TMenuPopup.HandleEvent** (when the popup sits in a group): a Ctrl+letter
key → the item with that hot letter (FV `GetCtrlChar`), else the key map; an
enabled command posted; an Alt+letter / digit key swallowed; then
TMenuView's. A popup is normally executed: `fv.views.execView OWNER POPUP`
→ `RESULT` the command (`cmCancel` when nothing was chosen: execView's rule
for an empty answer — give popup items commands other than `cmCancel`).

**Focus broadcasts reach the application**: the bar and each box are made
current in the application by `execView`, so FV's `cmReleasedFocus` /
`cmReceivedFocus` go through the application's `HandleEvent`: with a
`TMyApp` override every menu open costs those dispatches (~0.2 ms each).
Measured (stage 3f): the open + drop + close of §8.4 counts **22**
dispatches: 2 for F10 and 2 for `cmMenu` (each `TMyApp.HandleEvent` + its
`inherited`), **14 for the 7 focus broadcasts**, 3 for the box (kklass's
constructor, its `Done` and the `inherited` in it: a box is made and
destroyed per drop) and 1 user `Draw` of the window below the box. The
design's revision 2 counted 19 (it left out the box's 3); `014_MenuBudget`
logs 23 because it also counts its own `app.Run` call.

### GetHelpCtx and the status line (D22)

While a menu runs it is the top view, so fv.app's `Idle` (between events)
makes the status line ask its `GetHelpCtx`: FV's — from the view up the
parent menus, the first whose current item has a name and a `HelpCtx`
other than hcNoContext (`Undo` with 0 in Edit's box → Edit's context) — and
show that context's def and **hint**.

* **The hint table**: **`fv.menus.setHint SL HELPCTX TEXT`** — the built-in
  `Hint` answers `TEXT` for `HELPCTX` (digits); `TEXT` `''` removes the
  entry; the line is redrawn when it shows that context and the hint
  changed; a class that overrides `Hint` still wins. The table is
  `${SL}_hints` (assoc), freed with the line. rc 2 for a malformed call;
  `RESULT` is kept.

### The bar on request (D23)

**`fv.menus.menuBar [LIST]`** — the application's bar from LIST: a
`TMenuBar` on row 0 of `FV_APP`, named `APP__fvmenubar`, `FV_MENUBAR` = it,
the desktop from row 1 (`fv.views.locate`, its other edges kept). In the
application's `InitMenuBar` it only makes the bar (Init inserts it in FV's
order and `InitDesktop` leaves row 0 to it); after Init the bar is inserted
in front and the desktop moved, as one terminal update. Called again it
replaces the bar (the old one destroyed); with no LIST it removes the bar
and the desktop gets row 0 back. A malformed list changes nothing (rc 2,
the Error line); no application: rc 2. While a menu runs (the bar's or any
menu view's `Execute`: a hook of the event source, `Idle`) it is refused —
rc 2, one debug line, nothing changed (the running loop would go on with
the new bar); call it after the menu closes. `RESULT` is kept. Without it (and
without an `InitMenuBar` override) there is no bar at all: [fv.app, "The
menu bar on request"](../fv.app/README.md).

### Cost

Git-bash 5.3.15, the laptop (noisy: CI decides), `tools/bench`
`views-menu-80` (FV's layout with a bar, two stand-in windows, `TMyApp`;
F9 stands for an idle tick), 2026-11-22; the same machine's
`80x24.down` (the stand-in) 6.1 ms:

| action | dispatches | writes | ms | §8.4 laptop |
|---|---|---|---|---|
| F10 → the bar → Down drops the 28 × 12 box → Esc closes both (3 idle ticks included, ~5.7 ms) | 22 | 11 | 60–73 | 52 (limit §8.1: 24 / 28) |
| a highlight move, the hint changes (an idle tick included) | 0 | 3 | 8.4–10.5 | 6.05 |
| a highlight move, no hint (an idle tick included) | 0 | 2 | 6.0–7.1 | 4.55 |
| an idle tick alone (the key, Idle, Update without a change) | 0 | 0 | 1.9 | |

The tests pin the counts (`014_MenuBudget`); the times are early-warning
numbers. CI (run 44976117811, the 3f commit, ratios to the same run's
`80x24.standin.down`): open + drop + close 11.4–12.3× (debian 61.1 ms,
fedora 61.5, the ubuntu host 43.1, Git-bash 97.9, Cygwin 72.3; §8.4 planned
8.8×), a move with a hint change 1.60–1.66× (debian 8.53 ms; planned
1.02×), without a hint 1.07–1.12× (debian 5.77; planned 0.77×), an idle
tick alone 0.26–0.28×: about 30–50 % over §8.4. (An earlier run on the
ubuntu host, the stand-in 5.23 ms: 63.9 / 8.62 / 5.81 ms.) The speed work
(stages 3v-2…3v-5) is deferred by the owner; its starting point, a
same-process split of a move on the laptop (rough; per call, the loop
overhead taken off):

| part of a highlight move | ms |
|---|---|
| each of the two one-row `drawPart`s of the box (FV's OldItem rows: the painter's row + `drawPart`'s clip, views in front, end; not split further) | ~1.1 (+ ~0.3 terminal update) |
| the status line on a hint change (the idle tick's Update): topView + GetHelpCtx ~0.2, FindItems + Hint ~0.1, its `drawView` (`_compose` + writeLine + the painter) ~1.7, the terminal update ~0.5 | ~2.6 |
| the status line's Update without a change (every idle tick) | ~0.23 |
| Execute's per-event tail: `_resetCursor` of the root ~0.11 + `_showNow` ~0.03 | ~0.15 |
| (the whole box drawn instead, for comparison: `drawView` of the 4-item box) | ~2.9 |

So the box's two row repaints and the status line's redraw are ~85 % of a
move with a hint; the per-event tail is ~2 %. A lever on either big part
changes fv.views' `drawPart` / `drawView` machinery or the counts (one
two-row `drawPart` for adjacent rows: 1 write instead of 2), so it waits for
that stage. Taken in the 3f review: FV's TrackMouse works out the built-in
box's and bar's item rects in one pass instead of one `GetItemRect` per
item (the bar's sums the widths from the first item on every call): a mouse
event over File's box ~0.15 ms instead of ~0.6 (grows with the items before),
the same dispatches and writes (no dispatch either way: the built-ins are
elided), the same item for every cell (a 240-point comparison).

## Contract (kcl README §1) and deviations

§1; deviations:

* an instance class with FV's field names (TView's); fields of other
  instances read and written under the kklass friend contract (D19);
* **friend uses of fv.views' private parts** (the same framework): reads of
  `__FV_VW_LIVE`, `__FV_VW_CRC`, `__FV_VW_ERRSYM`, the disabled-command set
  `__FV_VW_CMDOFF` (one array read per item instead of a call) and the event
  hooks `__FV_VW_PUTEVENT` / `__FV_VW_EOF`; its entries in the elision table
  `__FV_VW_IMPL`; calls of `fv.views._virt`, `fv.views._topView` and
  `fv.views._viewEvent` (fv.views' README lists these friend entries).
  The menus (stage 3f) add: the event source `__FV_VW_GETEVENT` (the menus'
  own loop, as fv.views' loops read it), the per-event holds `__FV_VW_LSU` /
  `__FV_VW_EH`, the absolute origins `__FV_VW_AX` / `__FV_VW_AY` (the mouse
  tests), the blanks `__FV_VW_PAD`, the CtrlToArrow table `__FV_VW_C2A`,
  entries in `__FV_VW_BCAST`; calls of `_evSave` / `_evRestore`, `_ownerOk`,
  `_showNow`, `_resetCursor`, `_release`, `_newReserved`; fv.video's `_g`;
  fv.keyboard's `layoutBase`; a read of fv.app's `__FV_AP_ININIT` (when
  fv.app is loaded: `menuBar` leaves the insert to the application's Init). A
  re-source of fv.views (`kk.unit --forget fv.views`) merges its elision
  table, so these entries stay; the constructor registers them again only if
  they are missing;
* the malformed constructor list prints one `Error:` line (the loud refusal of
  fv.views' constructors);
* from Free Vision: the help contexts and commands are names / numbers as in
  fv.views (commands are names); keys are fv.keyboard's names; no `Hint`
  field (the design's §1.2 table lists one, but a kklass field named like the
  `Hint` method would clash; FV has none either: `Items` and `Defs` are the
  arrays); `Update` is a virtual method (FV) although the design's §1.3 list
  leaves it out; the hit test accepts only points inside the line (FV takes
  any X and the rows 0..1); the redraws only when something changed
  (`cmCommandSetChanged`, `Update`: D17) and the plain redraw after a press
  only when an item was shown pressed; the end of input during a press posts
  nothing; the posted command's other event fields are cleared (FV's record
  overlays them); a line taller than one row is blanked below row 0.
* **the menus (stage 3f), with the reasons**:
  * **D23: no bar unless the application asks** (FV always makes an empty
    one: an empty top row in every program);
  * the items are **flat per-instance arrays** (FV's pointer chains: bash
    has none); `Menu` is `OWNER:S`, `Current` / `OldItem` / `Default` are
    item indices (`-1` = nil); `HotKey` and `FindItem` are map lookups (FV
    walks every item; the key map starts at the top menu, so a view whose
    `Menu` is another submenu — a box from `newSubView` inserted by hand —
    walks its own subtree as FV does); `FindItem`'s second path is the
    base-layout key of §14.4 (terminals give no scan code), in
    `fv.views.hotKeyIs`' order;
  * `Execute` answers `''` for "no command" (FV 0); `fv.views.execView` turns
    an empty answer into `cmCancel` (its rule), so a popup's caller cannot
    tell a `cmCancel` item from nothing; the menus themselves read the private
    `__FV_MN_RES` right after their execView calls;
  * the loop does nothing on an idle tick (`evNothing`), as fv.views' loops
    (FV runs its selection code then too; with FV's flow an event is always
    put back when a box returns, so no case differs);
  * a box made by `newSubView` shows its Default highlighted from its first
    draw (FV sets `Current` when `Execute` starts and draws after the first
    event: the same picture one event earlier), and it is not drawn plain
    before it is removed (FV does: the writes only); a highlight move repaints
    two rows by `drawPart` (FV's Draw writes them through `OldItem`: the same
    cells);
  * FV's raw-key comparisons are kept: Ctrl+F (CtrlToArrow End) in a box goes
    Home (FV tests `E.KeyCode = kbEnd`), Ctrl+X on the bar does not drop the
    box (FV tests `kbDown`);
  * a redraw on `cmCommandSetChanged` only when the view's own items show
    another state (D17; FV: when any item of its tree changed);
  * an `item` / `sub` with an empty `TEXT` is refused with the other
    malformed lists (FV's `NewItem` drops it silently); `HELPCTX` is a number
    (as the status line's defs); a bar taller than one row has its other rows
    blanked (FV writes row 0 only); `TMenuBox.GetItemRect` gives the local row
    (FV adds its owner's origin, a quirk of its absolute origins); the key
    walk on a submenu of separators only stops (FV's `TrackKey` loops
    forever there);
  * kklass's `.new` / `.delete` of the boxes and the bar run with a local
    default IFS (a caller's IFS can break kklass, K-3); the caller's IFS is
    untouched;
  * the built-in `Hint` reads the hint table (FV answers `''` and leaves the
    texts to a subclass): an extension, an override still wins.

## Tests

`bash kcl/fv.menus/tests/tests.sh` — headless (no terminal, no `initVideo`).
`tests/fvm_testlib.sh` reuses fv.views' test lib (the headless screen, the
buffer reader, both counters, `fvw_budget`, the scripted event source, the
scene classes) and adds the test status line (`fvm_mkst`) and the
application-like scene (`fvm_scene`); the menu tests (009-017) run in an
application through fv.app's test lib (`fva_testlib.sh`: `fva_app`, the
scripted terminal with `key K CHAR BASE`) and add the test menu bar
(`fvm_menu`), `fvm_box`, `fvm_rows`, `fvm_cells`, `fvm_nobox`. Each test
file's stderr is captured: anything on it fails one test.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API and the elision entries; loads, re-loads, `kk.uses` by name and the main path under `set -eu`; `kk.unit --forget fv.menus` + re-source keeps a live line; `kk.unit --forget fv.views` + re-source (dispatched, re-registered by the next `.new`); failing calls under `set -e`; nothing on stdout; no stray names |
| 002_Items | the constructor's defaults, the list (implicit def, a `def` text), the arrays, the key map and its chains, addDef / addItem and the aliases, FindItems, refusals, the malformed list (rc 2, Error, no view), the destructor, the re-creation guard |
| 003_Keys | keys through the app's dispatch (pre-process before the focused leaf, the posted record, disabled commands, a key twice in a def, another def's keys, a key-only item, case-sensitive names also under nocasematch), F6 → cmNext through the modal loop, the counts of a key mapped to a command |
| 004_Mouse | the press tracking (pressed colours, moving between items / off the items / off the row, a press on the blank part, a disabled item, the end of input, the record put back (`FV_EV_BASE` too), the writes per press, the dispatches), a click through the modal loop, == a full repaint |
| 005_Draw | one write per draw, no dispatch; the colours, greyed commands, the Hint, wide labels and a `~` between wide characters, two rows high, ASCII mode, clipped to a narrow line, an unexposed tree, a GetPalette override, cmCommandSetChanged (0 / 1 write), `_quiet` |
| 006_Hint | Hint's default; Update: no change / same def / another def (the counts), sfDragging, the top view of a modal dialog, no top view, a GetHelpCtx override, a Hint override (redrawn when the hint changes), a Draw override (every change), an Update override |
| 007_ZeroFork | the unit's whole path with `PATH=''` (stage 3f: the menus' too — a bar, Alt+F, a nested drop, F3, a press + release, a popup, the hint table, cmCommandSetChanged, the destructors); the static scan of `fv.menus.sh` |
| 008_CallerState | one scene under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept; stage 3f: a menu scene (the bar's draw, Alt+F → DoSelect → the box → Down / Enter, a plain Cyrillic hot letter, cmMenu + F3, a press + release, Alt+Cyrillic to another top item, a popup) under the same setups and IFS `$'\x1f'`, `RESULT` kept |
| 009_MenuItems | stage 3f, the model: the flat list laid out per submenu (first / last / Default, the sub index), Disabled from the command set, the key map in HotKey's depth-first order with its chain, hot letters per submenu (folded, Cyrillic, a `~` at the end), the classes' options / state / grow mode, the box's size (FV's formula; shortened, moved left / up), newSubView and its refusals, the malformed lists (rc 2, one Error line, nothing made), the destructor (a borrowed menu stays), the re-creation guard |
| 010_MenuBar | the bar in an application: its draw (one write, the colours), pre-processed keys (a mapped key posts, a disabled one goes on, Alt+X → HotKey, an unknown key goes on), F10 → cmMenu → the bar modal (Default, Left / Right / Ctrl+S / Ctrl+D with wrapping, Esc, the Default remembered), Enter drops the box (owned by the application) and a nested one, a command posted after the menu, Alt+F at once, cmCommandSetChanged (1 / 0 writes), == a full repaint after every close |
| 011_MenuBox | the box in FV's flow: its draw (frame, separator, Param, the submenu mark, the current bar, a disabled item), Down / Up / Ctrl+X / Ctrl+E / Home / End, F10 inside does nothing, a plain hot letter, F3 (HotKey), Left / Right / Alt+W to other submenus, Enter / hot letter on a disabled item do nothing, Esc in a box under the bar closes both, in a nested box one level, the nested box's place, TMenuPopup run by an owner (a command, cmCancel, removed), == a full repaint after every close |
| 012_MenuMouse | a press on a bar item opens its box, a drag into it and a release choose; a release on the bar item keeps the box; a press outside closes all; a drag along the bar switches boxes; a release on a separator closes (FV's MouseActive); moves without a button and a wheel change nothing; a popup by press + release, a press outside it |
| 013_MenuStatus | the hint table (answers, removal, a redraw only for the shown context, refusals, an override wins, freed with the line); the status line follows the open menu (Open / Save hints, Undo (0) → Edit's context, Cascade (0) → Layout's), back after the menu; GetHelpCtx outside a run |
| 014_MenuBudget | §8.1: open + drop + close ≤ 24 dispatches / 28 writes (with `TMyApp`), a highlight move 0 / 3 with a hint change, 0 / 2 without, the same in a 40-item box, the box's draw 1 writeLines + 2 shadow writes, the bar's 1; no leak after 100 open / drop / close cycles |
| 015_MenuLoop | the end of input closes every level (one box, two nested) with no command; a failing source; a subshell refuses (execView and Execute rc 2, nothing posted or drawn); the event record put back through execView and a direct Execute; a resize while a box is open (the bar's width, the desktop's row 1, the box stays) |
| 016_MenuLayout | Cyrillic hot letters (typed, upper case), the base key for a Latin title with a Russian layout, the typed character first with titles in two scripts, an ASCII typed character never as its base key, plain letters in a box (typed, `FV_EV_BASE`, the layout tables), Alt+Cyrillic inside a box goes to the top menu |
| 017_MenuHotKeys | item search by behaviour: HotKey skips a Disabled item (the bar's pre-process, TopMenu's HotKey in an open box), FindItem skips a Disabled hot letter; HotKey's depth-first order (File > Recent before later File and Edit items), a repeated hot letter (the first wins, also typed upper case); a box from newSubView over a submenu inserted by hand answers only its subtree's keys; menuBar while the bar or a box runs (rc 2, one debug line, nothing changed), again after the close |
