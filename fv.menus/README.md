# kcl/fv.menus — the status line of the fv.* text UI

Layer L2 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P2_DESIGN.md](../docs/dev/fv/P2_DESIGN.md)). Free Vision's `TStatusLine`
(FV `menus.inc`: `TStatusDef` / `TStatusItem`, `NewStatusDef` /
`NewStatusKey`, `Draw` / `DrawSelect`, `FindItems`, `HandleEvent` with the
mouse press tracking, `Hint`, `Update`) as a [kklass](../../kklass/README.md)
class on [`fv.views`](../fv.views/README.md)' `TView`. `TMenuBar` and
`TMenuBox` come with P3.

The unit loads `kklass_pascal` and `fv.views`.

**Status: P2 stage 2e.** The application ([`fv.app`](../fv.app/README.md),
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
| `Hint HELPCTX` | func | `''`; a class of yours answers the text shown after the items |
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

### What fv.app does with it (stage 2f, as planned here)

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
times are early-warning numbers (no target before stage 2g).

## Contract (kcl README §1) and deviations

§1; deviations:

* an instance class with FV's field names (TView's); fields of other
  instances read and written under the kklass friend contract (D19);
* **friend uses of fv.views' private parts** (the same framework): reads of
  `__FV_VW_LIVE`, `__FV_VW_CRC`, `__FV_VW_ERRSYM`, the disabled-command set
  `__FV_VW_CMDOFF` (one array read per item instead of a call) and the event
  hooks `__FV_VW_PUTEVENT` / `__FV_VW_EOF`; its entries in the elision table
  `__FV_VW_IMPL`; calls of `fv.views._virt`, `fv.views._topView` and
  `fv.views._viewEvent` (fv.views' README lists these friend entries). A
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

## Tests

`bash kcl/fv.menus/tests/tests.sh` — headless (no terminal, no `initVideo`).
`tests/fvm_testlib.sh` reuses fv.views' test lib (the headless screen, the
buffer reader, both counters, `fvw_budget`, the scripted event source, the
scene classes) and adds the test status line (`fvm_mkst`) and the
application-like scene (`fvm_scene`). Each test file's stderr is captured:
anything on it fails one test.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API and the elision entries; loads, re-loads, `kk.uses` by name and the main path under `set -eu`; `kk.unit --forget fv.menus` + re-source keeps a live line; `kk.unit --forget fv.views` + re-source (dispatched, re-registered by the next `.new`); failing calls under `set -e`; nothing on stdout; no stray names |
| 002_Items | the constructor's defaults, the list (implicit def, a `def` text), the arrays, the key map and its chains, addDef / addItem and the aliases, FindItems, refusals, the malformed list (rc 2, Error, no view), the destructor, the re-creation guard |
| 003_Keys | keys through the app's dispatch (pre-process before the focused leaf, the posted record, disabled commands, a key twice in a def, another def's keys, a key-only item, case-sensitive names also under nocasematch), F6 → cmNext through the modal loop, the counts of a key mapped to a command |
| 004_Mouse | the press tracking (pressed colours, moving between items / off the items / off the row, a press on the blank part, a disabled item, the end of input, the record put back, the writes per press, the dispatches), a click through the modal loop, == a full repaint |
| 005_Draw | one write per draw, no dispatch; the colours, greyed commands, the Hint, wide labels and a `~` between wide characters, two rows high, ASCII mode, clipped to a narrow line, an unexposed tree, a GetPalette override, cmCommandSetChanged (0 / 1 write), `_quiet` |
| 006_Hint | Hint's default; Update: no change / same def / another def (the counts), sfDragging, the top view of a modal dialog, no top view, a GetHelpCtx override, a Hint override (redrawn when the hint changes), a Draw override (every change), an Update override |
| 007_ZeroFork | the unit's whole path with `PATH=''`; the static scan of `fv.menus.sh` |
| 008_CallerState | one scene under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept |
