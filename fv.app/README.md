# kcl/fv.app — the application of the fv.* text UI

Layer L2 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P2_DESIGN.md](../docs/dev/fv/P2_DESIGN.md) §2). Free Vision's `app.inc`:
`TBackground`, `TDesktop`, `TProgram` and `TApplication` as
[kklass](../../kklass/README.md) classes on [`fv.views`](../fv.views/README.md)
(`TView`, `TGroup`, `TWindow`) and [`fv.menus`](../fv.menus/README.md)
(`TStatusLine`): the application object, its event source (FV
`TProgram.GetEvent`: the put event, the terminal, a resize handled at once,
`Idle`), `Run`, the desktop with `Tile` / `Cascade` / `cmNext` / `cmPrev`,
and the app palette.

The unit loads `kklass_pascal`, `fv.views`, `fv.menus` and
[`fv.drivers`](../fv.drivers/README.md).

**Status: P2 stage 2f.** No menu bar yet (`TMenuBar` is P3): the desktop
takes row 0 too.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.app

trap 'echo bye >&2' EXIT                 # your traps: BEFORE the application (fv.video's rule)

class TMyApp : TApplication
    public
        override proc HandleEvent
        override proc InitStatusLine
end
TMyApp.InitStatusLine() {                # FV: StatusLine := New(PStatusLine, Init(R, ...))
    TStatusLine.new mystatus 0 $(( SizeY - 1 )) "$SizeX" "$SizeY" \
        '~Alt+X~ Exit' kbAltX cmQuit  '~F3~ Open' kbF3 cmOpen  '' kbF6 cmNext
    FV_STATUSLINE=mystatus
}
TMyApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmOpen ]; then
        TWindow.new "win$(( ++N ))" 5 2 45 15 "File $N" "$N"
        fv.views.insert "$FV_DESKTOP" "win$N"
        fv.views.clearEvent "$this"
    fi
}
build TMyApp

TMyApp.new app || exit 1                 # the terminal on (initVideo, initEvents), the views made, nothing drawn
app.Run                                  # the first paint, then the loop until cmQuit (Alt+X)
app.delete                               # the views gone, the terminal restored
```

Headless (tests, the bench): `FV_APP_HEADLESS=1 FV_SCREEN_W=80 FV_SCREEN_H=24
FV_VIDEO_OUT_FD=$fd FV_KEY_FD=$keys TApplication.new app` — no terminal: the
frames go to `FV_VIDEO_OUT_FD`, the keys come from `FV_KEY_FD`.

## Classes and fields

| class | fields | FV |
|---|---|---|
| `TBackground : TView` | + `Pattern` | `TBackground` |
| `TDesktop : TGroup` | + `Background TileColumnsFirst` | `TDesktop` |
| `TProgram : TGroup` | TGroup's | `TProgram` |
| `TApplication : TProgram` | TGroup's | `TApplication` |

* **`TBackground.new NAME AX AY BX BY [PATTERN]`** (FV `Init(Bounds,
  APattern)`): `GrowMode` = `gfGrowHiX + gfGrowHiY`, `Pattern` (default `░`,
  FV's `#$2591`). `Draw`: one fill of its rect with `Pattern` in colour 1
  (`CBackground` `#1`: CAppColor entry 1, blue on light grey); in ASCII mode a
  non-ASCII pattern is drawn as `#` (fv.video would show `?`).
* **`TDesktop.new NAME AX AY BX BY`** (FV `Init(Bounds)`): `GrowMode` =
  `gfGrowHiX + gfGrowHiY`, then the virtual `InitBackground` (the built-in
  makes the `TBackground` `NAME__fvbg` over the whole desktop and sets
  `Background`), inserted when it is a view without an owner.
* **`TProgram.new NAME`** (FV `TProgram.Init`): the TGroup part over the
  screen (`0 0 FV_SCREEN_W FV_SCREEN_H`, the width at most 1024), FV's
  `Application := @Self` (`FV_APP`), fv.views' event hooks (below), the
  virtual `InitScreen`, `State` = `sfVisible + sfSelected + sfFocused +
  sfModal` (`sfExposed` comes with the first paint), `Options` 0, then
  the virtuals `InitStatusLine`, `InitMenuBar`, `InitDesktop` and the views
  they made (`FV_DESKTOP`, `FV_STATUSLINE`, `FV_MENUBAR`) inserted in FV's
  order: the desktop, then the status line, then the menu bar (in front).
  **Draws nothing.** No terminal: that is `TApplication`'s.
* **`TApplication.new NAME`** (FV `TApplication.Init`): `fv.video.initVideo`
  (rc 1: the constructor fails with rc 1 and a debug line, nothing is made)
  and `fv.drivers.initEvents`, unless `FV_APP_HEADLESS=1`; then TProgram's.
* **One application at a time**: a second `TProgram` / `TApplication` while
  `FV_APP` is live is refused (rc 1, one `Error:` line), before anything is
  touched. Re-creating the live application by name goes through TView's
  guard (the tree repaired, rc 1, one `Error:` line); its hooks, globals and
  terminal then go as at `Done`. When the name was taken over by a view of
  another class (no TProgram code ran), the next application releases the
  dead one's state first.
* **`app.delete`** (FV `Done`): `sfExposed` off (nothing is drawn while the
  views go), the desktop, menu bar and status line destroyed, the rest of
  the subviews (TGroup's), fv.views' hooks, the owner and the end-of-input
  latch put back as they were before `Init`, `FV_APP FV_DESKTOP
  FV_STATUSLINE FV_MENUBAR` `''`, the app palette, ErrorAttr and the colours
  `setAppPalette` redefined back to the defaults; `TApplication` then does
  `doneEvents` when its Init called `initEvents` and `doneVideo` **when its
  Init turned the terminal on** (a terminal the caller turned on before
  stays on; the event driver is turned off either way).

`FV_APP`, `FV_DESKTOP`, `FV_STATUSLINE`, `FV_MENUBAR` are FV's globals
`Application`, `Desktop`, `StatusLine`, `MenuBar`: instance names, `''` =
nil.

### Virtual methods

Every built-in is elided (fv.views README, "Virtual elision"): an override
of yours costs a dispatch each time the framework uses it, a class that
overrides nothing costs none.

| class | method | kind | FV |
|---|---|---|---|
| `TBackground` | `Draw` / `GetPalette` | proc / func | one fill / `1` |
| `TDesktop` | `HandleEvent` | proc | TGroup's, then `evCommand cmNext` → `FocusNext(False)`; `cmPrev` → with a `Background`: `Current` put in front of the background (behind every window) when `Valid(cmReleasedFocus)` agrees; without one `FocusNext(True)`; handled |
| `TDesktop` | `InitBackground` | proc | the background (`Background` = it) |
| `TDesktop` | `TileError` | proc | nothing (FV: abstract); called when `Tile` / `Cascade` cannot lay out |
| `TProgram` | `HandleEvent` | proc | `Alt+1` … `Alt+9` → the broadcast `cmSelectWindowNum` (`FV_EV_INFO` = the digit) to the desktop, the key handled when a window took it; TGroup's; `evCommand cmQuit` → `EndModal(cmQuit)` of the program, handled |
| `TProgram` | `Run` | proc | the first paint (below), then `Execute` (fv.views' modal loop) |
| `TProgram` | `GetEvent [TIMEOUT]` | func | below ("The event source"); answers `FV_EV_WHAT` in `RESULT`, rc 1 at the end of input |
| `TProgram` | `PutEvent` | proc | FV `Pending := Event`: fv.drivers' one slot (`FV_EV_*` is the event) |
| `TProgram` | `Idle` | proc | the status line's `Update`; when `FV_COMMANDSETCHANGED`: the broadcast `cmCommandSetChanged` to the program, then the flag cleared |
| `TProgram` | `InitScreen` | proc | `fv.video.initScreen` (the default palette, the shadow symbol `V`), the app palette back to CAppColor, ErrorAttr's symbol |
| `TProgram` | `InitStatusLine` | proc | the last row: FV's default `def 0 65535` `'~Alt-X~ Exit' kbAltX cmQuit` + `StdStatusKeys` (`kbAltX cmQuit`, `kbF10 cmMenu`, `kbAltF3 cmClose`, `kbF5 cmZoom`, `kbCtrlF5 cmResize`, `kbF6 cmNext`, `kbShiftF6 cmPrev`, key-only): `NAME__fvstatus`; `FV_STATUSLINE` = it |
| `TProgram` | `InitMenuBar` | proc | nothing in P2 |
| `TProgram` | `InitDesktop` | proc | the extent less the menu bar's row and the status line's: `NAME__fvdesktop`; `FV_DESKTOP` = it |
| `TProgram` | `GetPalette` | func | `''`: the program maps into the app palette as it is (an override answers an index list into it) |
| `TApplication` | `HandleEvent` | proc | TProgram's, then `evCommand cmTile` (`Tile`), `cmCascade` (`Cascade`), `cmResizeApp` (the resize, below), handled |
| `TApplication` | `GetTileRect` | proc | the desktop's extent (else the application's) in `FV_RECT_*` (FV's `var` parameter) |

An `Init…` override of yours sets the global itself, as FV's does
(`FV_STATUSLINE=mystatus`); a view it leaves without an owner is inserted
by `Init`.

### The plain API

| Function | FV | Answer |
|---|---|---|
| `fv.app.tile V [AX AY BX BY]` | `TDesktop.Tile(R)` / `TApplication.Tile` | V a desktop (any group) and a rect in its coordinates, or V the application (`FV_APP`) without one (its `GetTileRect`, then its desktop). FV's layout below; `RESULT` kept; rc 2 for a malformed call |
| `fv.app.cascade V [AX AY BX BY]` | `TDesktop.Cascade(R)` / `TApplication.Cascade` | likewise |
| `fv.app.setAppPalette ENTRY FG BG [BOLD]` | — | below ("The app palette") |

The aliases (D16): `TDesktop.Tile AX AY BX BY`, `TDesktop.Cascade …`,
`TApplication.Tile`, `TApplication.Cascade`.

**Tile** (FV `TDesktop.Tile`): the views with `ofTileable` and `sfVisible`
(FV's `Tileable`; a `TWindow` is not tileable until you set the option, as in
FV), counted front to back; FV's `MostEqualDivisors(N, NumCols, NumRows, NOT
TileColumnsFirst)` and `DividerLoc` place the back-most view first (top
left) and the front-most last; a rect where a column or a row would get 0
cells calls `TileError` and moves nothing. Each view is `locate`d (its
`SizeLimits` apply) with the drawing held, then the desktop is drawn once
(FV hides each view during its `Locate` and draws the desktop at the end).
**Cascade**: the back-most view at R's corner, each next one a cell further
in, each up to R's bottom-right; `TileError` when the back-most view's
`SizeLimits` minimum does not fit (FV's `LastView`).

## Run and the event source

* **`app.Run`** (FV `Run` → `Execute`): refused (rc 2, a debug line) in a
  process other than the one that made the application (inside `$( )`, a
  pipeline: the owner-process rule). The first time: `sfExposed` set, the
  whole application drawn once and the cursor placed (**the first paint**,
  D18; a modal view executed before `Run` — a startup dialog — gets it from
  the first `GetEvent` instead), then fv.views' `TGroup.Execute` — FV's loop, without `HandleEvent`
  for `evNothing` — until `EndModal` (`cmQuit`, also at the end of input).
  `RESULT` kept (FV's `Run` is a procedure); the end of input shows as
  `__FV_VW_EOF` = 1.
* **The hooks**: `Init` sets fv.views' `__FV_VW_GETEVENT` to
  `fv.app._getEvent` and `__FV_VW_PUTEVENT` to `fv.app._putEvent` (the
  application's `GetEvent` / `PutEvent` through the elision: an override is
  dispatched), `__FV_VW_OWNER` to its process, and resets the end-of-input
  latch `__FV_VW_EOF`; `Done` puts the hooks and the owner back. Every loop
  of fv.views (`Execute`, `execView`, `mouseEvent`, `dragView`, the status
  line's press tracking) reads through them.
* **`TProgram.GetEvent [TIMEOUT]`** (FV `TProgram.GetEvent`; first the
  application's first paint when it had none yet):
  1. after the end of input: rc 1 at once (nothing read);
  2. the put event, as it is (no `Idle`, no resize handling);
  3. else `fv.drivers.getEvent TIMEOUT` (default `FV_IDLE_TIMEOUT`, 0.05 s;
     `0` = only what is there: dragView's drain passes it);
  4. **`cmResizeApp`** (FV's system event) is handed to the application's
     `HandleEvent` **at once** and counted in fv.views' `__FV_VW_RESIZES`;
     what is left of the event goes on (normally nothing: TApplication
     handled it, so the loop sees `evNothing` and `Idle` runs, as in FV);
  5. **`evNothing` → `Idle`** (virtual). With built-in views an idle tick
     costs **0 dispatches**;
  6. **the end of input** (fv.drivers' rc 1) latches `__FV_VW_EOF`: every
     running loop ends without asking `Valid` (the modal ones with
     `cmCancel`, the application with `cmQuit`) and a new `execView` answers
     `cmCancel` at once — so a `Valid(cmQuit)` that opens a "save?" box
     cannot spin. fv.drivers' rc 2 (a bad fd or TIMEOUT) goes on as it is
     (the loops take it for the end of input).
  What a resize or `Idle` drew is shown at once (also inside a handler's
  nested loop).

### Resize (design §2.3)

A SIGWINCH sets `FV_VIDEO_RESIZED`; `fv.drivers.getEvent` runs
`fv.video.updateSize` (the `stty size` fork, the only fork on an event path)
and answers `evCommand cmResizeApp` (`FV_EV_ID` = width, `FV_EV_INFO` =
height); GetEvent hands it to the application at once. TApplication's
resize (FV `ResizeApplication`), when the size differs (W, H 1–5 digits,
else ignored with a debug line; the width at most 1024): the drawing held,
`fv.video.resizeScreen`, `ChangeBounds 0 0 W H` through the elision (each
subview by its `GrowMode`: the desktop `gfGrowHiX + HiY`, the status line
`gfGrowLoY + HiX + HiY`, windows `gfGrowAll + gfGrowRel` with their
`ZoomRect`), then one forced full redraw and the cursor. A resize during a
modal view resizes it too; one during a drag ends the drag (fv.views
README, "Dragging": `__FV_VW_RESIZES`).

### Ctrl+C, traps, the terminal

fv.video owns the traps and restores the terminal on every exit path;
**fv.app sets no trap** — set yours before `TApplication.new`. Ctrl+C
(`intr` stays on) is the emergency exit: the terminal restored, status 130,
`Done` not run. The orderly exit is `cmQuit` (Alt+X).

## The app palette (design §1.9)

* The app palette is FV's `CAppColor` as a 127-symbol string
  (`__FV_VW_APAL`): fv.video's default palette gives CAppColor's distinct
  bytes the symbols `1`–`9`, `A`–`U` (fv.views README, "Palettes").
  `InitScreen` puts it back to that string.
* **ErrorAttr** (FV `$CF`, an index outside a palette): `InitScreen` gives it
  the first free symbol, `W`, white (15) on bright red (9); before an
  application exists it is the default symbol `0`.
* **`fv.app.setAppPalette ENTRY FG BG [BOLD]`**: entry ENTRY (1–127) gets FG
  / BG (0–255, D10) and BOLD (0 / 1, default 0) without changing the other
  entries that share its symbol:
  1. a symbol only this entry uses is redefined in place
     (`fv.video.definePalette`);
  2. else a symbol the palette already uses with these colours is taken;
  3. else a free one is allocated: `1`–`9`, `A`–`U`, `W`–`Z`, `a`–`z` that the
     palette no longer uses, never `0` (the default), `V` (the shadow) or
     ErrorAttr's;
  then every resolved palette is dropped (`fv.views.resetPalette`) and the
  application redrawn. **All symbols in use** (59 for the palette): rc 1, one
  `Error:` line, nothing changed. rc 2 for a malformed call, rc 1 without a
  screen. `RESULT` kept. The application's `Done` gives every symbol it
  redefined its colours back (one that was undefined before stays defined,
  unused). **The pool belongs to the app palette** (design §1.9, fv.video's
  README): a pool symbol you define for your own fv.video drawing may be
  taken over by `setAppPalette`; use it only while no application runs, or
  not at all.
* The shadow attribute is fv.video's symbol `V` (`definePalette V …`
  re-themes every shadow); fv.app does not define it.

## Performance

Dispatches and fv.video writes (the test lib's shims; 80 × 24, the test
scene: two `TWindow`s with a list stand-in each, the default status line):

| action | dispatches | writes |
|---|---|---|
| an idle tick (steady state) | 0 | 0 |
| `Alt+1` selecting the covered window (TMyApp + inherited + its leaf's Draw) | 3 | 24 |
| `kbDown` to the focused leaf through TMyApp | 3 | 2 |
| `cmTile`, two windows (the leaves' Draws) | 3 | 29 |
| one resize 120 × 40 → 80 × 24 (TMyApp + inherited + the leaves' Draws) | 5 | 44 |
| the first paint of the small app (status line, desktop, 2 windows) | 2 | 44 |

Times: stage 2f, Git-bash 5.3.15, headless, scripted terminal, frames to
`/dev/null`, median of 5 × 20, **on a machine running ~3–4× slower than the
fv.views "Cost" table** (a plain function call 17–22 µs against 4.9 µs
there; the CPU at 2.5 of 3.8 GHz); compare ratios, not the absolute values,
until 2g's bench: idle tick 3.7 ms (scripted source ~1 ms of it), `kbDown`
through TMyApp 13.8 ms, F6 → `cmNext` 50 ms, resize 82 ms, `cmTile` /
`cmCascade` 52 ms, the first paint 49 ms. The 2g bench (`fvviews`) measures
them on a quiet machine against the design §3 / §4 targets.

## Contract (kcl README §1) and deviations

§1; deviations:

* **instance classes with FV field names**; fields of other instances read
  and written under the kklass friend contract;
* **friend uses of fv.views and fv.video** (the same framework, versioned
  together): fv.views' `__FV_VW_LIVE`, `__FV_VW_CRC`, `__FV_VW_GRP`, the hooks
  `__FV_VW_GETEVENT` / `__FV_VW_PUTEVENT` / `__FV_VW_OWNER` / `__FV_VW_EOF` /
  `__FV_VW_RESIZES`, `__FV_VW_NODRAW`, `__FV_VW_APAL` / `__FV_VW_ERRSYM`,
  entries added to `__FV_VW_IMPL` and
  `__FV_VW_QGRP` (TDesktop's, TProgram's and TApplication's handlers react to
  no broadcast and pass one on as TGroup's: the quiet-broadcast walk goes
  into them); calls of `fv.views._virt`, `_message`, `_groupEvent`,
  `_newReserved`, `_showNow`; fv.drivers' `__FV_DR_PEND`; fv.video's
  `__FV_VS_PAL`, `__FV_VS_DOS`, `__FV_VS_H`, `__FV_VS_SHADOW`;
* **loud refusals**: a second application prints one `Error:` line (not
  only under `VERBOSE_KKLASS=debug`); so does a full palette;
* from Free Vision: **no menu bar in P2** (`InitMenuBar` makes none; the
  desktop takes row 0; P3 restores FV's row 0); **`Init` draws nothing** and
  `sfExposed` comes with the first paint (`Run`, or the first `GetEvent` of
  a modal view executed before it; FV draws each view as it is inserted;
  D18 counts the first paint from `Run`); `Run` and
  `TProgram.Done` refuse / draw nothing as above; **`Done` draws nothing**
  (FV hides each view); `TApplication` turns the terminal off at `Done` only
  when its `Init` turned it on; one application at a time (FV has one
  `Application` but does not check); the owner-process rule; `GetEvent`'s
  order (the put event, the terminal with the resize before keys —
  fv.drivers' deviation —, the resize handled at once, `Idle`) and its
  `TIMEOUT` argument; `cmResizeApp` handed to the application at once is
  counted in `__FV_VW_RESIZES` so that a drag can end on it; `Alt+F12`'s
  redraw (FV `GetEvent`) is not there; `TProgram.GetPalette` answers `''`
  (the app palette as it is), FV's black-and-white and monochrome palettes
  are not in v1 (D10); ErrorAttr gets its own symbol; a non-ASCII background
  pattern is `#` in ASCII mode; `ExecuteDialog`, `InsertWindow`,
  `ValidView`, `CanMoveFocus`, `DosShell`, `SetScreenMode` are not in P2.

Known kklass limits met by the tests (not this unit's, K-3): `.new` and
`inherited` under an `IFS` holding letters; the tests set such an `IFS`
after the classes and instances exist and replace `inherited` by the
built-in body there.

## Tests

`bash kcl/fv.app/tests/tests.sh` — headless except 008 (a pty through
script(1)). `tests/fva_testlib.sh` builds on fv.menus' and fv.views' test
libs: the scripted terminal (`fva_events`: fv.drivers.getEvent replaced by a
queue, `resize W H` included; the TIMEOUT arguments logged), `TMyApp` (the
design's application with a `HandleEvent` override), `fva_app` (a headless
application with two windows). Each test file's stderr is captured: anything
on it fails one test.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API, the classes, the elision and QGRP entries; the default app palette = fv.views' string; loads, re-loads and the main path under `set -eu`; `kk.unit --forget` + re-source of fv.app (a live application keeps working) and of fv.views (the merged tables); failing calls under `set -e`; nothing on stdout; no stray names |
| 002_Run | Init (the tree, Current, the globals, State, the hooks, nothing drawn, ErrorAttr); the first paint at Run (== a full repaint) with keys from a file through fv.drivers; the event source (TIMEOUT passed on, the put event first without Idle, a GetEvent override); Idle (the status line's HelpCtx, cmCommandSetChanged); the budgets (idle tick, Alt+1, a key to the leaf, the first paint) and Alt+digit; user InitStatusLine / InitMenuBar / InitDesktop; TProgram alone; one application at a time; re-creation by name; no terminal |
| 003_Modal | dialogs executed by a handler inside Run read through GetEvent (Idle meanwhile), endModal, a modal cmClose (cmCancel posted through PutEvent), a dialog inside a dialog; == a full repaint |
| 004_Resize | cmResizeApp handled inside GetEvent (all bounds by GrowMode, one full redraw, evNothing for the loop, Idle, the override sees it once); the same size / a bad size; the budget; mid-modal; mid-drag (keyboard and mouse: the drag ends clamped, no undo) |
| 005_Desktop | Tile for 2 / 3 / 5 windows and TileColumnsFirst, untileable and hidden views, Cascade, TileError (Tile and Cascade), cmTile / cmCascade / cmNext / cmPrev through the application, cmPrev without a background, a GetTileRect override, the budget of cmTile, TBackground (one fill, its colour and pattern, ASCII mode), refusals |
| 006_Quit | Alt+X through the status line, cmQuit put and sent; a window whose Valid refuses cmQuit; Done (nothing drawn, every view destroyed, hooks / owner / globals / palette back); the caller's hooks put back; a new application after Done |
| 007_Eof | the end of input ends Run without Valid, the latch, GetEvent after it; execView after the latch; the "save?" box (Valid asked once, nothing spins); a failing source; a new application resets the latch; a real end of file through fv.drivers |
| 008_Pty | `script(1)` (SKIP: ENV on Git-bash): init → Run → Alt+X → Done restores the terminal; a real SIGWINCH resize (the pty set to 120 × 40) handled by the application; Ctrl+C: status 130, restored, Done not run |
| 009_ZeroFork | `PATH=''`: the whole path (Init, the first paint, Run with idle ticks, keys, Alt+1, tile, cascade, next, prev, a resize, a modal dialog, a drag, the end of input, setAppPalette, Done), a real fv.drivers.getEvent from a file; the static fork scan of `fv.app.sh` |
| 010_CallerState | one application scene under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept |
| 011_Subshell | Run in `$( )` and in a pipeline refused (rc 2, nothing read or drawn), execView in `$( )` refused, the parent's application untouched, an application made inside a subshell owns its loop there |
| 012_Palette | the default string and ErrorAttr's symbol; setAppPalette in place, by reuse, by allocation (the application redrawn, == a full repaint); all symbols in use (rc 1, one Error line, nothing changed, 0 / V / W never handed out); refusals |
| 013_Edges | the critic round's edges: a dialog executed before Run drawn by the first GetEvent; doneEvents at Done whoever turned the terminal on; tile / cascade of a plain TGroup without TileError; setAppPalette's colours back at Done; the name re-created as a TWindow (the next application releases it); the end-of-input latch put back at Done; Alt+digit does not leak the window into RESULT |

Run on Git-bash 5.3.15 (008 SKIP), MSYS2 5.3.9, Cygwin 5.2.21 (2026-11-17).
