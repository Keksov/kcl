# kcl/fv.views — the view tree of the fv.* text UI

Layer L2 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P2_DESIGN.md](../docs/dev/fv/P2_DESIGN.md)). Free Vision's `TView` and
`TGroup` (FV `views.inc`) as [kklass](../../kklass/README.md) classes with
FV's field names: the subview lists, FV corner bounds, `GrowMode`, and the
**virtual elision** that runs a built-in virtual as a plain function unless
your class overrides it. FV's non-virtual methods are plain functions
`fv.views.*`; the set-up ones also have thin method aliases (decision D16).

The unit loads `kklass_pascal`, [`fv.video`](../fv.video/README.md) and
[`fv.drivers`](../fv.drivers/README.md).

**Status: P2 complete (stage 2g)** — the tree and the geometry (2c-1); palettes,
the drawing context and writers, the painter with shadows, both lock
counters and the minimal `TFrame` (2c-2); the event dispatch, the focus
chain, command sets, the cursor, modal views and the basic `TWindow` (2c-3);
window zoom, `dragView` (keyboard and mouse) and the frame's mouse (2d); the
final call budget and the `fvviews` bench (2g, "Cost" below). The
application (`TProgram` / `TApplication`, `Run`, the real event source) is
[`fv.app`](../fv.app/README.md) (stage 2f), which uses the hooks below; the
status line is [`fv.menus`](../fv.menus/README.md).

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.views

TGroup.new desk 0 1 80 24            # FV R.Assign(0, 1, 80, 24): corners, B exclusive
TGroup.new win1 10 5 50 20           # 40 x 15
TView.new label 2 1 20 2
fv.views.insert desk win1            # FV Insert: in front, Owner set, Current = win1
win1.Insert label                    # the alias (D16) of fv.views.insert win1 label

win1_data[GrowMode]=$FV_GF_GROWALL   # grows with its owner
fv.views.changeBounds desk 0 1 100 30
fv.views.getBounds win1; echo "$RESULT"     # 30 11 70 26 (also FV_RECT_AX ... FV_RECT_BY)
fv.views.moveTo win1 0 0
fv.views.makeGlobal label 0 0; echo "$RESULT"  # 2 2: the label's origin on the screen

fv.views.delete desk win1            # out of the tree (still a live view)
win1.delete                          # destroyed, with the label inside it
desk.delete
```

A class of yours overrides FV's virtuals and calls the built-in with
`inherited NAME "$@"` (a bare `inherited` in a method forwards no
arguments):

```bash
class TMyWin : TGroup
    public
        override proc SizeLimits
end
TMyWin.SizeLimits() { inherited SizeLimits; FV_MIN_X=20 FV_MIN_Y=6; }   # FV MinWinSize
build TMyWin
```

Drawing (headless here: frames go to a file; a program draws on the terminal
after `fv.video.initVideo` + `initScreen`, and from P2 stage 2f fv.app does
all of that):

```bash
FV_SCREEN_W=80 FV_SCREEN_H=24 fv.video.initScreen
exec {out}>frame.txt; FV_VIDEO_OUT_FD=$out

class TClock : TView                 # a leaf of yours: its Draw covers its rect
    public
        override proc Draw
end
TClock.Draw() { fv.views.fill 0 0 "$SizeX" "$SizeY" ' ' 1; fv.views.writeStr 0 0 '12:00' 1; }
build TClock

TGroup.new desk 0 0 80 24
TView.new bg 0 0 80 24               # TView.Draw: blanks in palette colour 1
TGroup.new win 10 3 50 18
TFrame.new frame 0 0 40 15           # FV's frame look, drawn from win's fields
TClock.new clock 1 1 39 2
win_data[State]=$(( win_data[State] | FV_SF_SHADOW ))
fv.views.insert desk bg; fv.views.insert desk win
fv.views.insert win frame; fv.views.insert win clock
desk_data[State]=$(( desk_data[State] | FV_SF_EXPOSED ))   # the root that is drawn (fv.app: the application)
fv.views.drawView desk               # everything, back to front, one terminal update
fv.views.moveTo win 12 4             # redraws the old and the new place once
fv.views.lock win; …; fv.views.unlock win    # FV Lock / Unlock: win redrawn once at the end
```

A constructor of yours calls `inherited` first and checks that it worked:

```bash
TMyDlg.Create() { inherited; fv.views.isView "$this" || return 1; Title=$5; }
```

## Classes and fields

| class | fields (FV's public fields, flattened: `Origin.X` → `OriginX`) |
|---|---|
| `TView` | `Owner OriginX OriginY SizeX SizeY CursorX CursorY State Options EventMask GrowMode DragMode HelpCtx` |
| `TGroup : TView` | + `Current Phase EndState LockFlag` |
| `TFrame : TView` | + `FrameMode` |
| `TWindow : TGroup` | + `Flags Title Number Palette Frame ZoomRect` (`ZoomRect` = `"AX AY BX BY"`) |

* `CLASS.new NAME AX AY BX BY` is FV's `Init(R)` with `R.Assign(AX, AY, BX, BY)`:
  corners, B exclusive (D1). The width is capped at FV's `MaxViewWidth`
  (1024, fv.video's widest row); a negative size is kept as given.
* `TView` defaults (FV `TView.Init`): `State` = `sfVisible`, `Options` 0,
  `EventMask` = `evMouseDown + evKeyDown + evCommand` (273), `GrowMode` 0,
  `DragMode` = `dmLimitLoY`, `HelpCtx` = `hcNoContext`, `Owner` and `Current` `''`.
* `TGroup` (FV `TGroup.Init`): `Options` += `ofSelectable + ofBuffered`,
  `EventMask` = `$FFFF`, `Phase` = `phFocused`, `EndState` `''`, `LockFlag` 0,
  an empty subview list.
* `TFrame` (FV `TFrame.Init`): `GrowMode` = `gfGrowHiX + gfGrowHiY`,
  `EventMask` += `evBroadcast`, `FrameMode` 0. It reads its owner's
  `Flags`, `Number` and `Title` (or the owner's `GetTitle`, a func, when its
  class has one): TWindow's fields; any group works (without them: a bare
  frame). Its `HandleEvent` takes the mouse on the frame ("TWindow" below).
* `TWindow.new NAME AX AY BX BY [TITLE [NUMBER]]` (FV `TWindow.Init`):
  TGroup's, then `sfShadow`, `ofSelectable + ofTopSelect`, `GrowMode` =
  `gfGrowAll + gfGrowRel`, `Flags` = `wfMove + wfGrow + wfClose + wfZoom`,
  `Palette` = `wpBlueWindow`, `Number` (1–9 is shown on the frame; not an
  integer: `wnNoNumber` 0), `ZoomRect` = the bounds, and `Frame` from the
  virtual `InitFrame`: the built-in makes the `TFrame` `NAME__fvframe` over
  the whole window, which the constructor inserts (an override that leaves
  `Frame` empty makes a frameless window). See "TWindow" below.
* `Owner` and `Current` hold view names; `''` is FV's `nil`.
* FV's `Next` / `Last` / `First` are the owner's subview list
  `${group}_views`, **back to front**: its last element is FV's `First` (the
  front). Read it; change it only through the functions below.
* Fields are kklass `var`s: a method body reads `$SizeX`, `$State`; outside,
  `${v}_data[SizeX]`. A field your constructor never assigned is unset: read
  it `${d[X]-}` under `set -u`.
* **`OriginX OriginY SizeX SizeY` change only through `fv.views.locate`,
  `moveTo`, `growTo` and `changeBounds`** (and an owner resize). The bounds
  cache below is updated there; a direct write (`v_data[OriginX]=7`, or
  `OriginX=7` in a body) leaves it stale, so `makeGlobal`, `mouseInView` and
  the drawing use the old place. Likewise **a `ChangeBounds`
  override of yours must call `inherited ChangeBounds "$@"`**: the built-in
  sets the fields *and* the cache. (An owner resize recomputes its whole
  subtree's cache at the end, but nothing else does.) Setting them in your
  constructor after `inherited`, before the view is inserted, is fine:
  `insert` computes the cache.

### Constants

FV values, readonly, named by upper-casing FV's identifier behind a prefix:
`sfCursorVis` → `FV_SF_CURSORVIS`.

| family | names |
|---|---|
| `State` | `FV_SF_VISIBLE CURSORVIS CURSORINS SHADOW ACTIVE SELECTED FOCUSED DRAGGING DISABLED MODAL DEFAULT EXPOSED` ($1 … $800) |
| `Options` | `FV_OF_SELECTABLE TOPSELECT FIRSTCLICK FRAMED PREPROCESS POSTPROCESS BUFFERED TILEABLE CENTERX CENTERY CENTERED VALIDATE` ($400) |
| `GrowMode` | `FV_GF_GROWLOX GROWLOY GROWHIX GROWHIY GROWALL GROWREL` |
| `DragMode` | `FV_DM_DRAGMOVE DRAGGROW LIMITLOX LIMITLOY LIMITHIX LIMITHIY LIMITALL` |
| `HelpCtx` | `FV_HC_NOCONTEXT` (0), `FV_HC_DRAGGING` (1) |
| TWindow `Flags` / `Palette` / `Number` | `FV_WF_MOVE GROW CLOSE ZOOM` ($1 … $8), `FV_WP_BLUEWINDOW CYANWINDOW GRAYWINDOW` (0 … 2), `FV_WN_NONUMBER` (0) |
| TFrame `FrameMode` | `FV_FM_CLOSECLICKED` ($1), `FV_FM_ZOOMCLICKED` ($2) |
| FV's `MinWinSize` | `FV_MINWINSIZE_X` (16), `FV_MINWINSIZE_Y` (6): TWindow's `SizeLimits` minimum. Not readonly (FV's typed constant, which programs change); a value that is not 1–9 plain digits counts as 16 / 6 |
| `EventMask` | `FV_EM_MOUSEDOWN MOUSEUP MOUSEMOVE MOUSEAUTO KEYDOWN MOUSEWHEEL COMMAND BROADCAST MOUSE KEYBOARD MESSAGE` (FPC drivers.inc values; `FV_EM_`, not `FV_EV_`: those are [fv.drivers' event](../fv.drivers/README.md#the-event)) |

Phases and commands are names (`phFocused`, `cmClose`), not numbers.

### Virtual methods

| class | method | kind | FV |
|---|---|---|---|
| `TView` | `ChangeBounds AX AY BX BY` | proc | SetBounds, then the redraw of old ∪ new (held inside `locate` and an owner resize, which redraw once) |
| `TView` | `CalcBounds DX DY` | proc | the bounds after the owner grew by (DX, DY): by `GrowMode` (`gfGrowLoX/HiX/LoY/HiY` move the edge by the delta, `gfGrowRel` scales it: `I := (I*S + (S−D) shr 1) div (S−D)`, 1 when the old size is 0), the width capped at `MaxViewWidth`, the size clamped by `SizeLimits`. Answer: `FV_RECT_AX/_AY/_BX/_BY`. GrowMode 0 or no owner: the bounds as they are |
| `TView` | `SizeLimits` | proc | `FV_MIN_X/_Y` = 0, `FV_MAX_X/_Y` = the owner's size (FV `TGroup.ClipChilds` is true); without an owner `high(Sw_Integer)` (2147483647) |
| `TView` | `GetHelpCtx` | func | `hcDragging` while `sfDragging`, else `HelpCtx` |
| `TGroup` | `ChangeBounds AX AY BX BY` | proc | no size change: SetBounds + the redraw; else SetBounds, then each subview, front to back (FV `ForEach`), takes `CalcBounds DX DY` (`FV_RECT_*` holds its current bounds first: an override that sets nothing keeps it in place) and `ChangeBounds` with that rect (each subview still sees its old absolute place, so its redraw covers old ∪ new; one destroyed or removed meanwhile is skipped), then the subtree's cache and the group's redraw |
| `TGroup` | `GetHelpCtx` | func | `Current`'s `GetHelpCtx`, else TView's |
| `TView` | `Draw` | proc | blanks in palette colour 1 over the whole view (one fill). Runs only inside the painter (below); `V.Draw` called elsewhere draws nothing: draw with `fv.views.drawView` |
| `TGroup` | `Draw` | proc | FV `DrawSubViews`: the visible subviews back to front, each clipped to the paint rectangle, the covered skip, the shadows. An override that calls `inherited Draw` and then writes gets the group's clip back |
| `TFrame` | `Draw` | proc | FV's frame (below, "TFrame"): 3 writes |
| `TView` | `GetPalette` | func | `''` (FV `nil`: the view maps as its owner does) |
| `TFrame` | `GetPalette` | func | `1 1 2 2 3` (FV `CFrame`) |
| `TView` | destructor `Done` (`V.delete`) | | V out of its owner, a group's subviews destroyed, V's entries freed |
| `TView` | `HandleEvent` | proc | the click to focus (D8); "Events" below |
| `TGroup` | `HandleEvent` | proc | FV's dispatch: phases, positional, broadcasts ("Events") |
| `TView` / `TGroup` | `SetState BIT ENABLE` | proc | the bit and FV's side effects ("The focus chain") |
| `TView` / `TGroup` | `Valid CMD` | func | rc 0 = valid; TGroup asks its subviews ("Modal views") |
| `TView` / `TGroup` | `Execute` | func | `cmCancel` / FV's modal loop ("Modal views") |
| `TView` / `TGroup` | `EndModal CMD` | proc | the top view's / a modal group's `EndState` |
| `TWindow` | `HandleEvent SetState GetPalette GetTitle InitFrame Close` | | "TWindow" below |
| `TWindow` | `SizeLimits` | proc | TView's, then `FV_MIN_X/_Y` = MinWinSize (`FV_MINWINSIZE_X/_Y`, 16 × 6) |
| `TWindow` | `CalcBounds DX DY` | proc | FV (FPC 2026): TView's on the `ZoomRect` (kept as the new `ZoomRect`), then TView's on the bounds (the answer) |
| `TWindow` | `Zoom` | proc | FV: below its `SizeLimits` maximum → `ZoomRect` = the bounds, then `locate` to `0 0 MAX_X MAX_Y`; at the maximum → `locate` to `ZoomRect` |
| `TFrame` | `HandleEvent` | proc | the mouse on the frame: the close / zoom icons, dragging the owner ("TWindow" below) |

FV's procedures with `var` parameters answer in globals, because a proc
leaves `RESULT` alone (below): `FV_RECT_AX FV_RECT_AY FV_RECT_BX FV_RECT_BY`
(a `TRect`), `FV_MIN_X FV_MIN_Y FV_MAX_X FV_MAX_Y` (SizeLimits' `Min`, `Max`),
`FV_POINT_X FV_POINT_Y` (a `TPoint`).

The aliases (D16) — `TView`: `MakeFirst PutInFrontOf Locate MoveTo GrowTo
DrawView Show Hide Select`; `TGroup`: `Insert InsertBefore Lock Unlock
SelectNext ExecView` (a func) — call the plain functions with `$this`.
There is **no `Delete` alias**: FV's `Delete` (remove a subview) would differ
from kklass's `.delete` (destroy) in the case of one letter. Removal is
`fv.views.delete G V`.

## Plain API: the tree and the geometry

Every function: the view name first; rc 0 = done; rc 1 = a value the call
may legitimately meet (already owned, not a subview, FV's `nil`); rc 2 = a
malformed call (not a view or group, a coordinate that is not an integer,
a wrong argument count). A refusal sets `RESULT=''`, changes nothing and
gives one `Error: fv.views.NAME: …` line under `VERBOSE_KKLASS=debug` (the
loud cases below print theirs always).
**Procedures leave `RESULT` as it was** (as kklass procs do); getters answer
in `RESULT`. Coordinates: an optional `-` and 1–9 digits (leading zeros are
decimal).

| Function | FV | Answer |
|---|---|---|
| `fv.views.insert G V` | `Insert` | V in front of G's subviews. V must be a live view without an owner and not G or an owner of G (rc 1). Centring by `ofCenterX` / `ofCenterY` (FV `div`), `Owner` set, the bounds cache of V's subtree, and — V visible and selectable — FV's `ResetCurrent` (Current := the front-most visible selectable subview, so normally V) |
| `fv.views.insertBefore G V TARGET` | `InsertBefore` | V directly in front of TARGET (a subview of G, else rc 1); `''` = behind all (FV `Target = nil`). Otherwise as `insert` |
| `fv.views.delete G V` | `Delete` | V out of G; `Owner` `''`; Current reset as FV does (a visible selectable V, or V being Current → `ResetCurrent`); V keeps its `State` and stays a live view (insert it again or `V.delete`). rc 1: V is not a subview of G |
| `fv.views.makeFirst V` | `MakeFirst` | V in front of its siblings. No owner: a no-op |
| `fv.views.putInFrontOf V TARGET` | `PutInFrontOf` | V directly in front of TARGET (a sibling, else rc 1); `''` = behind all. A no-op without an owner, for TARGET = V, or when V already is directly in front of TARGET. A visible selectable V: `ResetCurrent`. An invisible V is only moved |
| `fv.views.first G` / `last G` | `First` / `Last` | RESULT = the front / back subview; rc 1 for an empty group |
| `fv.views.next V` / `prev V` | `Next` / `Prev` | the view behind / in front of V; a ring (the back one's `next` is the front one); rc 1 without an owner |
| `fv.views.nextView V` / `prevView V` | `NextView` / `PrevView` | the same without the wrap: rc 1 at the back / front |
| `fv.views.getBounds V` | `GetBounds` | RESULT=`"AX AY BX BY"` (owner-relative corners) and `FV_RECT_*` |
| `fv.views.getExtent V` | `GetExtent` | RESULT=`"0 0 SizeX SizeY"` and `FV_RECT_*` |
| `fv.views.locate V AX AY BX BY` | `Locate` | the size clamped by V's `SizeLimits` (virtual); when the bounds differ, V's `ChangeBounds` (virtual) and the redraw of old ∪ new |
| `fv.views.moveTo V X Y` | `MoveTo` | `locate` at (X, Y) with V's size |
| `fv.views.growTo V W H` | `GrowTo` | `locate` at V's origin with W × H |
| `fv.views.changeBounds V AX AY BX BY` | `ChangeBounds` | V's ChangeBounds through the elision (no SizeLimits clamp: FV calls it directly); a group: the owner resize by GrowMode above |
| `fv.views.makeLocal V X Y` / `makeGlobal V X Y` | `MakeLocal` / `MakeGlobal` | a screen point to V's coordinates and back: RESULT=`"X Y"` and `FV_POINT_X/_Y` |
| `fv.views.mouseInView V X Y` | `MouseInView` | rc 0 when the screen point lies in V's rect |
| `fv.views.isView V` | — | rc 0 for a live view (constructed through `TView.Create`, not destroyed or re-created) |

The bounds cache keeps every view's absolute origin and its clip (its rect ∩
its owner's clip; a view without an owner: its own rect) in private arrays,
so nothing walks the owner chain on a draw or a click. It is updated by
`insert`, `delete`, every `ChangeBounds` and an owner resize.

## Virtual elision

Every built-in virtual has its body in a plain function; the kklass method is
one line calling it, so `inherited` from your override reaches it. These
one-line methods are declared `nofields` (kklass book, "Field-free bodies"):
a call of one, an `inherited` into it included, binds none of the class's
fields (TView's 13, TWindow's 23). Wherever
FV would call a virtual, the framework calls `fv.views._virt V METHOD ARGS`:
it reads V's class and the class's kklass owner table (`TView_class_method_owner`
and so on, the [friend contract](../../kklass/docs/kklass_book.md#friend-tables-for-framework-units))
and runs the plain body **directly** when the defining class is a built-in
one, a kklass dispatch otherwise. **An override costs a dispatch (~0.1–0.2 ms)
each time the framework uses that method; a class that overrides nothing
costs none.** The decision is read on every call (~20 µs, no cache): it is
right after `kk.class --forget` and a redefinition too (for instances made
after the redefinition; what an older instance's methods do then is
kklass's, not promised).

**One RESULT / rc rule for both paths**, for every body form (kklass's
rule, "What a func answers" in the kklass book):

* a `proc` leaves the caller's `RESULT`; its rc is the body's;
* a `func` (FV's functions: `GetHelpCtx GetPalette Valid Execute GetTitle`;
  later `Hint GetEvent`) **answers with what `RESULT` holds when its body
  ends with rc 0**, however it ends: falling off the end, `return 0`, a last
  `inherited …` (`Valid` answers by its rc: "Modal views");
* a `func` **fails with its body's rc (N ≠ 0)** — an explicit `return N` or a
  failing last command — which leaves the caller's `RESULT`.

Before kklass round 7 (fv ledger K-2) an explicit `return 0` lost a func's
`RESULT` (so `TGroup.GetHelpCtx` through such a Current answered the group's
own) and a failing last command lost its rc; `013_Elision` pins the fixed
behaviour. The plain path answers for a `func` with rc 0 and leaves the
caller's `RESULT` for a failing `func` and for every `proc`.

Tested in `013_Elision`, with every built-in of stages 2c-1, 2c-2, 2c-3 and 2d overridden with
`inherited`, fields named like common locals, `kk.class --forget` +
redefinition, and the caller setups.

## Reserved names and the constructor guard

* Views the framework makes get names `${owner}__fv<role>` (`win1__fvframe`,
  `app__fvdesktop`). **A name of yours must not contain `__fv`**: TView's
  constructor refuses it (rc 2, one `Error:` line). The check is
  case-sensitive.
* kklass's `.new` over a live name re-creates the instance without its
  destructor. TView's constructor catches that: it **repairs the tree** (the
  stale name out of its owner's list, Current reset, the redraw of its area;
  a group's old subviews destroyed; its private entries freed), prints one
  `Error:` line and returns 1. The name stays a bare kklass instance outside
  the tree: `insert` refuses it, `name.delete` frees it. The pattern for a
  dialog made over and over is therefore
  `TDlg.new dlg …; …; fv.views.delete "$G" dlg; dlg.delete`.
* A constructor of yours that skips `inherited` leaves TView's fields unset:
  `insert` refuses such a view (and such a group as the target) with one
  `Error:` line, rc 2.
* A subclass constructor continues after a refused `inherited` unless it
  checks: `inherited; fv.views.isView "$this" || return 1`.

The `Error:` lines go to stderr unless `VERBOSE_KKLASS=quiet`; they are the
loud exception to kcl §1.2 (below).

## Drawing

### What is drawn, and when

* **A tree is drawn only when its root has `sfExposed`** (FV: a view is
  drawn only inside the application's tree; `TProgram.Init` sets the bit,
  fv.app does from stage 2f). A desktop-less user or a test sets it on its
  root group: `desk_data[State]=$(( desk_data[State] | FV_SF_EXPOSED ))`.
  So a dialog built outside the tree paints nothing until it is inserted.
* Nothing is drawn for a hidden view or one inside a hidden or **locked**
  group (below).
* The tree changes redraw by themselves (`insert`, `delete`, `makeFirst` /
  `putInFrontOf`, `locate` / `moveTo` / `growTo` / `changeBounds`, an owner
  resize, `show` / `hide`, `V.delete`): see "The redraw model".
* **Each drawing entry ends with one terminal update**
  (`fv.video.updateScreen`), unless `lockScreenUpdate` or a user lock holds
  it, or it runs inside another drawing entry (the outermost updates).

### The plain API

| Function | FV | Answer |
|---|---|---|
| `fv.views.drawView V` | `DrawView` | V drawn in place (with its shadow), the views in front of it painted again over it, the terminal updated. Nothing (rc 0) for a view that cannot be drawn now (above). `RESULT` kept |
| `fv.views.redraw V` | `Redraw` | as `drawView`, with a forced terminal update (every cell sent again); while the update is held (`lockScreenUpdate`, a user lock, inside another drawing entry) the force waits for the release |
| `fv.views.drawPart V FN Y1 Y2 [ARGS]` | — (rule 4) | partial redraw of a **leaf** without a dispatch: your plain painter function runs as `FN V ARGS` with V's drawing context, its writes clipped to V's local rows `Y1 <= y < Y2`; then the views in front of V that overlap those rows are painted again, and the terminal is updated. A group is refused (rc 2, one debug line): a painter of a group would write over its own subviews (redraw a group with `drawView`). Nested inside a Draw, the part under a covering view in that Draw is left out, so FN may run once per remaining piece (below). rc = FN's (the last non-zero; 0 when V cannot be drawn now: FN does not run). For a list's cursor move (P3 `FocusItem`). FN is checked (`declare -F`) on its first use only (D21): a painter unset after that fails as bash does, rc 127 and "command not found" on stderr |
| `fv.views.show V` / `hide V` | `Show` / `Hide` | the `sfVisible` bit, then (V in a group) FV's DrawShow (V drawn with its shadow) / DrawHide (its area, shadow included, repainted from below), then the owner's `ResetCurrent` for a selectable V. A no-op when the bit already is so; otherwise it is V's `SetState(sfVisible, …)` through the elision (an override of yours sees it) |
| `fv.views.lock G` / `unlock G` | `TGroup.Lock` / `Unlock` | `LockFlag` counts. While G is locked no `drawView` of G or of a view inside it is drawn (the tree changes' redraws included) and the terminal update is held. When the count returns to 0, **G is redrawn once** (FV `Unlock` → `DrawView`; also after `Lock; change fields; Unlock` with no draw at all). An inner group unlocked inside its locked owner draws nothing: the owner's unlock draws both. `unlock` of an unlocked group: a no-op. A group destroyed while locked (or holding a locked group) no longer holds the update, and what was drawn meanwhile (its removal) is sent at once |
| `fv.views.lockScreenUpdate` / `unlockScreenUpdate` | `LockScreenUpdate` / `UnlockScreenUpdate` | a count that holds the terminal update; the drawing into the buffer goes on. Back at 0, `unlockScreenUpdate` updates the terminal (FV calls `DrawScreenBuf` after it; here it is part of the call) unless a user lock still holds it. At 0 already: a no-op |
| `fv.views.getColor V I` | `GetColor` | `RESULT` = the fv.video symbol of V's palette entry I (1-based); ErrorAttr's symbol (below) for an index outside it; rc 2 for a non-index |
| `fv.views.resetPalette [V]` | — | forget the resolved palettes of V's subtree (every view without V): after a `GetPalette` answer changed (a window's `Palette` field, an override of yours) or the app palette did. Resolved again at the next draw; nothing is redrawn here |

### The drawing context

A `Draw` (and a `drawPart` painter) runs with these globals set, and every
paint saves and restores them, so a `drawView` or `drawPart` nested inside a
`Draw` (a scroll bar redrawn during a list's Draw, a group override that
decorates after `inherited Draw`) leaves the outer `Draw`'s context intact:

| Global | Meaning |
|---|---|
| `FV_DRAW_VIEW` | the view being drawn (`''` outside a Draw) |
| `FV_DRAW_X`, `FV_DRAW_Y` | its absolute origin |
| `FV_DRAW_PAL` | its resolved palette: entry I is `${FV_DRAW_PAL:I-1:1}` |
| `FV_CLIP_X1 FV_CLIP_Y1 FV_CLIP_X2 FV_CLIP_Y2` | the part of the view this paint may change, **in the view's own coordinates**, X2 / Y2 exclusive. A Draw that writes rows may limit its loop to `FV_CLIP_Y1 … FV_CLIP_Y2-1` (the painter often repaints a strip of a view only) |

The fv.video clip is set to that part for the Draw and put back after it:
the outermost drawing entry restores the caller's clip.

**"Draw must cover its rect"** (FV's rule): a `Draw` writes every cell of its
view (in the clip). A leaf, and a group whose back-most subview is a frame of
its full size, are treated as covering: a view entirely behind one is not
drawn at all. A leaf whose Draw leaves cells unwritten shows stale cells
there.

### The writers

View-local coordinates, one fv.video call each; only inside a Draw or a
`drawPart` painter (rc 2 outside one); `COLOR` is an index into the view's
palette (FV's `Color` byte); `RESULT` = fv.video's answer (the cells the
write advances), rc = its rc. The writes are clipped to what the paint may
change. FV's writers update the terminal at once; these leave it to the
drawing entry.

| Function | FV |
|---|---|
| `fv.views.writeStr X Y TEXT COLOR` | `WriteStr` |
| `fv.views.writeChar X Y CH COLOR [COUNT]` | `WriteChar` (COUNT default 1) |
| `fv.views.writeCStr X Y TEXT C1 C2` | `MoveCStr` + `WriteLine`: each `~` switches between the entries C1 and C2 (FV's Lo / Hi) |
| `fv.views.writeLine X Y H TEXT ATTRS` | `WriteLine(X, Y, W, H, Buf)`: the row TEXT with **resolved** symbols ATTRS (one per display cell, as FV's `TDrawBuffer` holds resolved attributes: build them from `FV_DRAW_PAL` / `getColor`) on the H rows Y … Y+H−1 (fv.video's repeat count) |
| `fv.views.writeLines X Y TEXTS ATTRS` | `WriteLine` per row, in one call (D21 stage E; for lists: P3's `TListViewer`): TEXTS and ATTRS are the **names** of two indexed arrays; for every index k of TEXTS, in order, the row `TEXTS[k]` with the resolved symbols `ATTRS[k]` at row Y+k — exactly `writeLine X Y+k 1 TEXTS[k] ATTRS[k]` (a sparse TEXTS skips rows, a missing `ATTRS[k]` is `''`), one fv.video call for all rows. RESULT = the widest row's cells (writeLine's answer, the maximum over the rows; 0 for no rows or an unset name). rc 2 with RESULT `''` and nothing written for a malformed call (also a name that is no identifier, starts with `__fv` in any case or is `RESULT`, or an associative array); a row writeLine would refuse (symbols, length) makes rc 2 with RESULT `''` after the other rows are written |
| `fv.views.writeRows X Y W TEXTS SYMS` | `WriteLine` per row of one colour, in one call (P3 10.2, for list rows with wide text): TEXTS and SYMS are the **names** of two indexed arrays; for every index k of TEXTS, in order, the row `TEXTS[k]` in the ONE resolved symbol `SYMS[k]` at row Y+k, **cut or padded to W cells by fv.video's own cells** (a wide character the cut halves becomes a blank, as at a clip edge; a short row is padded with blanks), so a list needs no width call per row (rule 2). One fv.video call (`fv.video._wrowsu`). RESULT = W (0 for no rows or W 0). rc 2 with RESULT `''` and nothing written for a malformed call (the count, outside a Draw, X / Y not integers, W not an integer ≥ 0, the names as `writeLines`'); a `SYMS[k]` that is not one symbol makes rc 2 with RESULT `''` after the other rows are written |
| `fv.views.fill X Y W H CH COLOR` | `MoveChar` + `WriteLine` with H rows |

A write with X and Y plain digits and COLOR 1–99 inside the palette takes a
fast path (one arithmetic step on top of fv.video's call); anything else is
checked (negative coordinates are allowed; an index outside the palette
writes in ErrorAttr's symbol; a malformed argument is rc 2).

### Palettes

* **The app palette** is FV's `CAppColor` as a 127-character string of
  fv.video symbols (`__FV_VW_APAL`): fv.video's default palette gives
  CAppColor's distinct bytes the symbols `1`–`9`, `A`–`U` in order of first
  appearance, so entry i is the symbol of byte i (`019_Palette` checks all
  127 against fv.video's table). **A stub until fv.app (stage 2f)**: its
  `setAppPalette` changes this string and calls `fv.views.resetPalette`.
* **A view's palette** is its `GetPalette` (a func: an override of yours is
  dispatched, `inherited GetPalette` works): FV's index list as
  space-separated numbers into its owner's palette (`TFrame` `1 1 2 2 3`;
  TWindow's blue / cyan / gray: `8 … 15`, `16 … 23`, `24 …
  31`); `''` (TView's) means the view maps as its owner does. The root maps
  into the app palette.
* **Resolved once per view** (FV's owner walk, done at the first draw or
  `getColor`) into a symbol string, dropped for the subtree on `insert` /
  `delete` and by `resetPalette`.
* **ErrorAttr**: FV's `$CF` has no symbol in fv.video's default palette; an
  index 0, past the palette below or not a number resolves to the default
  symbol `0` until fv.app allocates one.

### TFrame

FV `TFrame.Draw` in `CFrame`'s colours through the owner's palette:

| state | line | colours (CFrame entry) | icons |
|---|---|---|---|
| not `sfActive` | single `┌─┐│└┘` | frame and number 1, title 2 | — |
| `sfActive` | double `╔═╗║╚╝` | frame 3, title 4, icons 5 | `[■]` at 2 (`wfClose`; `☼` while `FrameMode` has `fmCloseClicked`), `[↑]` at W−5 (`wfZoom`; `↕` when the owner is at its `SizeLimits` maximum, `☼` with `fmZoomClicked`), the grow corner `─┘` at W−2 (`wfGrow`) |
| `sfDragging` | single | everything 5 | as active when active |

The owner's `Number` (1–9) at W−3 (W−7 with `wfZoom`), the title centred
with a blank either side, cut to the room FV leaves it (W−10, −6 with close
or zoom, −4 with a number; in cells: wide characters count 2).

* **A full draw is 3 writes**: the top row, the body row (`║` blanks `║`)
  on the H−2 rows between through the repeat count, the bottom row.
* **The border-only redraw** (`fv.views._frameBorder F`, which a group's
  `SetState` calls when a subview frame's `sfActive` or `sfDragging` changes) writes the top and bottom
  rows and the two side columns (3 writes: both sides in one
  `fv.video.fillColumns`, stage 2c-p) and never touches the interior.
  The parts of the ring that a covering view in front of the frame (or of an
  owner) holds are left out first, so a window in front is neither
  overwritten nor painted again (a ring cut by it: one write per piece,
  sides of different heights each their own); the views in front over what was written (scroll bars on the
  ring, shadows) are painted again. A frame class that overrides `Draw` is
  drawn whole instead (its Draw runs).
* The row strings are cached per frame and state (rebuilt when the state,
  size, title, owner fields, palette or the screen's ASCII mode,
  `FV_VIDEO_ASCII`, change). The title's width comes from fv.video's width
  table, which is fixed per process; the cut runs through `fv.video._g`
  (fv.video's locale guard, a friend entry: see fv.video's README), so a
  caller in a non-UTF-8 locale cuts a UTF-8 title by characters, not bytes.
* A view in front that does not cover (a frameless group, a scroll bar on the
  ring) and meets several ring pieces is painted once per piece.

## The redraw model and deviations from FV

* **No z-order clip: the painter's algorithm.** FV draws each view through
  its exposed parts; here a view is painted in z-order and the views in
  front of it are painted again over the changed rectangle (`over`). A view
  entirely behind a covering front sibling is skipped (covering: a leaf, or
  a framed group; a frameless group is not covering, a shadow never covers).
* **Shadows** (FV `ShadowSize` 2 × 1, `ShadowAttr` through fv.video's
  reserved symbol `V`): after a view with `sfShadow` is painted, its shadow
  cells (the two columns right of it from its second row, the row below it
  from its third column), clipped to the owner, take the shadow symbol and
  keep their characters (`fv.video.shadeRect`). Every rectangle that is
  redrawn because of a view is widened by its shadow: S(V).
* **What each change redraws** (the hook `fv.views._changed`):

  | change | redraw |
  |---|---|
  | `insert` | the view (`drawView`) |
  | `delete`, `hide`, `V.delete` | its old S(V) repainted from below (`drawUnder` of the owner) |
  | `locate` / `moveTo` / `growTo` / `changeBounds` | S(A) ∪ S(B) once, in z-order; ChangeBounds' own redraw is held meanwhile, and a group resize does not redraw per subview (its subviews' redraws are held: NODRAW) |
  | `makeFirst` / `putInFrontOf` | moved in front of a view that overlapped it: the view whole; moved behind one: the views now in front, over S(V); otherwise nothing (FV's `LastView` test) |

  A view without an owner (a root) is drawn whole on a bounds change. The
  cells of a group that no subview covers are nobody's: a frameless root
  group keeps stale cells there (as in FV); give it a background view.
* **Frameless groups**: a group that does not cover its rect (no full-size
  frame) leaves its uncovered cells to the views behind it. So a change
  inside it (a subview hidden, moved, deleted) is repainted from the first
  owner that covers (a framed group) or from the root, clipped to the
  changed rectangle — not from the frameless group itself.
* **Re-entrancy**: a `drawView` or `drawPart` called inside a `Draw` (a
  scroll bar redrawn from a list's Draw) never paints again a view whose
  Draw is running — that view and the groups painting it (the paint stack).
  When the view drawn lies behind a covering view of that stack, the part
  under it is left out, so the outer Draw's view stays on top. One nested
  draw, no recursion; the screen equals a full repaint as long as the outer
  Draw covers its rect. (Tree changes from inside a Draw — a `moveTo` in a
  Draw — are not repainted on the stack's views: avoid them.)
* **Wide characters and repaint edges**: fv.video blanks the visible half of
  a wide character that a clip edge cuts, and the other half of one a write
  covers by half. A rectangle repaint whose edge cut such a character would
  differ from a full repaint. The screen rows that hold (or held) wide cells
  (marked from fv.video's per-row flag `__FV_VS_WIDE`, a friend read), and
  those a wide character was written into since the last look (fv.video's
  per-row flag `__FV_VS_WNEW`, a friend field this unit reads and clears:
  a row whose only pair a view in front hides by half at the first paint
  holds no continuation cell, yet the move that uncovers the pair needs the
  test), get
  **the edge test** (P3 stage 3a-2, design 10.5; before it every such row
  was repainted across the whole width): a row is repainted across the
  whole width only when a wide pair straddles the left or right edge of the
  repainted rectangle — fv.video's row (another friend read) holds a
  continuation cell at its first column or just right of its last — or when
  two rectangles on the row meet; otherwise the rectangle alone gives the
  full repaint's cells (outside it the screen already is the full repaint,
  so a pair across its edge is in the new picture too, and a pair cut at a
  view's own clip edge is cut the same way by both). After a view left
  cells it covered (a move, a resize, a delete or hide, a view sent behind
  others) the picture can change one cell beyond the rectangle (the pair
  whose half the view had blanked shows whole again): there a side whose
  edge has a blank beside it on a wide row is widened by one cell first and
  the test runs on the new edge. The test reads the screen before anything
  is written. A caller whose locale is not UTF-8 (the read indexes
  characters) and a repaint nested inside a Draw band every such row as
  before. Rows without wide cells cost nothing extra. Typing a CJK
  character in a dialog over windows or a CJK list's page thus repaints its
  rectangle, not the rows across the screen (the views beside it on those
  rows are not painted again). A shadow strip whose first or last column
  cuts a wide character is shaded even when views in front cover it (the
  shade marks the character's other half outside the strip, which stays
  visible): the covered-shadow skip applies to the other strips.
* **Locked groups are still painted by an owner's repaint** (`lock desk;
  lock w1; unlock desk` draws w1 at desk's unlock and again at w1's): not
  painting them would let a view behind repaint over their area and leave
  a hole until the unlock, which FV does not show (FPC's `Lock` does not stop
  drawing; its `Unlock` draws).
* **A Draw's rc is ignored** (FV's Draw is a procedure): a Draw of yours that
  ends in a false test does not stop a caller under `set -e`; a failing
  command inside it does not stop it either.
* **Two lock counters** (decision D17): `lockScreenUpdate` only holds the
  terminal update; `lock` / `unlock` keep FV's meaning (the group redrawn
  once at the end). **The framework's own sequences do not lock**: they hold
  the terminal update and redraw only what changed (a focus change redraws
  two frame borders, not the desktop: FV's `SetCurrent` locks the desktop and
  its `Unlock` redraws all of it). The pixels are the same; your views'
  `Draw` runs less often than in FV.
* **Border-only frames**: a state change of a frame redraws its ring only;
  its interior keeps the previous state's colour where no view covers it
  (FV's three window palettes give both states the same background there:
  only the foreground of blank cells differs, which shows nothing). There
  is no `TFrame.SetState` (FPC has none either): the group's `SetState`
  redraws the border of each subview frame whose `sfActive` / `sfDragging`
  changed (FV redraws the whole window at its `Unlock`).
* **Not in this stage**: FV's frame junctions with `ofFramed` subviews;
  `sfExposed` on the views below the root (only the root's bit is read).

## Events, focus, commands

### The event and the dispatch

The event is [fv.drivers'](../fv.drivers/README.md#the-event) record, the
`FV_EV_*` globals: `FV_EV_WHAT` names it (`evKeyDown`, `evMouseDown`,
`evCommand`, `evBroadcast`, …), `FV_EV_KEY` the key, `FV_EV_COMMAND` a
command **name**, `FV_EV_INFO` FV's `InfoPtr` / `InfoInt` (a view name or a
number; `''` = nil). A handler marks an event handled with
`fv.views.clearEvent "$this"` (FV `ClearEvent`: `FV_EV_WHAT=evNothing`,
`FV_EV_INFO` = the handler).

`TGroup.HandleEvent` (FV's, the built-in of every group) runs TView's first
(click to focus, below) and then, unless the event was handled:

| event | goes to |
|---|---|
| focused (`evKeyDown`, `evCommand`) | `Phase=phPreProcess`: each subview with `ofPreProcess`, front to back; `phFocused`: `Current`; `phPostProcess`: each subview with `ofPostProcess` |
| positional (`evMouseDown` / `Up` / `Move` / `Auto` / `Wheel`) | the front-most visible subview whose rect holds the point (D8). A disabled one there swallows it, as in FV |
| `evBroadcast` | every subview, front to back |
| any other name | nobody: it has no `EventMask` bit, so every subview skips it |

* Each subview is reached through the elision; it is **skipped without a
  call** when its `EventMask` lacks the event's bit, or (positional and
  focused events) when it has `sfDisabled`. TView's own handler does nothing
  but the click to focus, so it is not even called for any other event.
* The loop stops as soon as the event is handled (`evNothing`); it runs over
  the subview list as it was when the event came, and skips a view that an
  earlier handler removed or destroyed.
* The group's `Phase` is set before each call (a handler may read it).
* A handler's rc is ignored (FV procedure): a handler that ends in a false
  test does not stop a caller under `set -e`.

**`EventMask` defaults are FV's**: TView `evMouseDown + evKeyDown +
evCommand` (273: a plain view sees no broadcast), TGroup `$FFFF`, TFrame
TView's + `evBroadcast`. So a focus broadcast into a desktop costs no
dispatch while every view in it is built-in or a plain user leaf; only a
user class that listens (P3: labels, buttons) pays one dispatch.

**Quiet broadcasts** (stage 2c-p): a broadcast that would reach no handler
that reacts to it is not delivered at all — `message` (the focus broadcasts
go through it) and the dispatch into a built-in subgroup first walk the
subtree: TView's handler reacts to `evMouseDown` only, TGroup's forwards,
TWindow's reacts to `cmSelectWindowNum`; a subview the dispatch would skip
(its EventMask lacks `evBroadcast`, removed meanwhile) is skipped by the
walk too, and any user `HandleEvent` on the way (or a built-in handler that
reacts) makes the delivery happen as before. `TFrame`'s handler (stage 2d)
reacts to `evMouseDown` only: it is quiet for every broadcast, so the focus
broadcasts into windows stay a walk, and the dispatch skips it without a
call for anything but a mouse-down, as it skips TView's. A skipped delivery leaves what
a delivery leaves: no handler ran, the event is unhandled (`message`: rc 1,
`RESULT=''`), and each group whose dispatch would have called a subview has
`Phase` = `phFocused` (set only when the walk ends quiet: a walk that finds a
listener leaves no Phase behind). A window switch among built-in windows thus walks the
tree instead of dispatching it (a desktop with two windows, Git-bash:
~0.4–0.5 ms instead of ~0.8–1.1 ms per broadcast, four broadcasts per
switch). Stage 2f: the units above this one
list their built-in group handlers that react to no broadcast and pass one
on as TGroup's does in `__FV_VW_QGRP` (fv.app's TDesktop, TProgram and
TApplication handlers): the walk goes into them as into TGroup's.

**The broadcast table** (P3 stage 3a-2, design 10.3) is where these rules
live: `__FV_VW_BCAST[BODY]="cmA cmB …"` names, for each built-in
`HandleEvent` body (the plain function of the elision table), the
broadcasts it reacts to (`''`: none). fv.views' rows:

| body | reacts to |
|---|---|
| `fv.views._viewEvent` (TView), `fv.views._frameEvent` (TFrame), `fv.views._groupEvent` (TGroup) | none |
| `fv.views._windowEvent` (TWindow) | `cmSelectWindowNum` |

The dispatch skips, **without a call**, a subview whose handler is a body
with a row that does not list the command (a group: when the walk finds its
subtree quiet too, `Phase` set as a delivery sets it), and the walk counts
such a leaf as quiet; a body without a row gets every broadcast its
EventMask lets through, as before, and **a user override is always called**
(also one of a class whose ancestor's body has a row; a subclass that
inherits the body follows the row). A `__FV_VW_QGRP` entry counts as the row
`''`. The table is merged on a reload (`+=`), like the elision table: the
units above this one add the rows of their own bodies (P3's widgets: a list
reacts to `cmScrollBarChanged cmScrollBarClicked`, a button to `cmDefault
cmGrabDefault cmReleaseDefault cmCommandSetChanged`, …). The rows of
fv.views give exactly the rules they replaced (the quiet-walk tests and the
call budgets are unchanged). The command is matched as a word of the row; a
caller's `nocasematch` can only make more handlers called, never fewer.

**Click to focus** (TView's `HandleEvent`, D8): a mouse-down on a selectable
view that is neither selected nor disabled focuses it (`fv.views.focus`) and
is consumed, unless the view took the focus and has `ofFirstClick`. A root
group should have `sfSelected` (fv.app makes the application with
`sfVisible + sfSelected + sfFocused + sfModal + sfExposed`), or it eats the
first click as FV does.

### The focus chain

`sfSelected` marks a group's `Current`; `sfFocused` the views on the chain
from the focused root (`Current` of `Current` …); `sfActive` the selected
window, its frame and contents; `sfModal` the view `execView` runs. Every
bit changes through the **virtual-aware `setState`** (an override of
`SetState` sees each change; `inherited SetState "$@"` keeps the behaviour),
with FV's side effects inline:

| bit | TView | TGroup adds | TWindow adds |
|---|---|---|---|
| `sfVisible` | DrawShow / DrawHide, the owner's ResetCurrent for a selectable view | | |
| `sfFocused` | resetCursor; the broadcast `cmReceivedFocus` / `cmReleasedFocus` to the owner (`FV_EV_INFO` = the view) | then `Current`'s `SetState` (the chain) | |
| `sfCursorVis`, `sfCursorIns` | resetCursor when focused | | |
| `sfShadow` | the area with the shadow repainted from below | | |
| `sfActive`, `sfDragging` | the bit | each subview's `SetState`, then the **border-only redraw** of each subview frame whose bit changed (3 writes) | |
| `sfSelected` | the bit | | `SetState(sfActive)`; the window commands |

`select` / `setCurrent` follow FV's `SetCurrent` (the old Current loses
`sfFocused`, then `sfSelected`; the new one gains `sfSelected`, then
`sfFocused`), so the broadcasts come in FV's order: each view's to its owner
before its Current's, released before received; a broadcast to the desktop
goes on into each window. **Decision D17**: no `Lock` of the group (FV's
`SetCurrent` locks the desktop, and its `Unlock` redraws all of it); the
terminal update is held to the end of the sequence, and only what changed
is redrawn: the two frame borders, the window brought to the front where it
was covered (with its shadow), the shadow alone when only the shadow meets
another window. A focus change of a group whose Current is not a window
redraws nothing (FV's leaves that change look on `sfActive` / `sfFocused`
redraw themselves in their own `SetState`: P3's lists and buttons).

The cursor: **`fv.views.resetCursor V`** (FV `ResetCursor` for V's tree)
shows the hardware cursor of the focused leaf (the end of the chain) at its
`CursorX` / `CursorY` when it has `sfVisible + sfCursorVis + sfFocused`,
the cell lies inside it and every owner, no visible view in front of it or
of an owner holds the cell, and every owner is visible: underline, block
with `sfCursorIns`; otherwise it hides it. The modal loop calls it after each
event; `setState` calls it for `sfFocused` / `sfCursorVis` / `sfCursorIns`
(once at the end of a framework sequence). It reads fv.video's cursor state
(`__FV_VS_CURX` / `_CURY` / `_CURT`) as a friend, and updates the terminal
only when the cursor changed.

### Commands

Commands are **names** (`cmClose`, `cmMyThing`: letters, digits, `_`). The
set kept is the **disabled** one: FV's `CurCommandSet` (all of 0..255 but
`cmZoom cmClose cmResize cmNext cmPrev` at the start) is its complement, so
a name never disabled is enabled, as FV's commands above 255 always are. A
change sets `FV_COMMANDSETCHANGED=1` (FV `CommandSetChanged`; fv.app's
`Idle` broadcasts `cmCommandSetChanged` and clears it). A selected `TWindow`
enables `cmNext cmPrev`, `cmResize` (wfGrow or wfMove), `cmClose` (wfClose)
and `cmZoom` (wfZoom), and disables them when deselected. `execView` puts
the set back after its modal view.

### The plain API

| Function | FV | Answer |
|---|---|---|
| `fv.views.message V WHAT COMMAND [INFO]` | `Message` | a new event (`FV_EV_WHAT=WHAT`, `FV_EV_COMMAND=COMMAND`, `FV_EV_INFO=INFO`, the rest empty) to V's `HandleEvent`; the caller's whole event record is put back afterwards. rc 0 and `RESULT` = the handler when it was handled; rc 1, `RESULT=''` when not, or for V `''` |
| `fv.views.clearEvent V` | `ClearEvent` | `FV_EV_WHAT=evNothing`, `FV_EV_INFO=V` |
| `fv.views.setState V BIT ENABLE` | `SetState` | V's `SetState` through the elision (BIT one `FV_SF_*` value, ENABLE 1 / 0); `RESULT` kept |
| `fv.views.select V` | `Select` | a selectable V becomes its owner's `Current`; with `ofTopSelect` it is brought to the front first. Not selectable or no owner: nothing |
| `fv.views.focus V` | `Focus` | rc 0 when V is (or now is) on the focus chain: its owner is focused first, then V selected, unless the owner's `Current` has `ofValidate` and its `Valid(cmReleasedFocus)` says no (rc 1) |
| `fv.views.focusNext G FORWARDS` / `selectNext G FORWARDS` | `FocusNext` / `SelectNext` | focus / select the next visible, enabled, selectable subview after `Current` (FORWARDS 1: FV's `Next`, the view behind; 0: FV's `Prev`, the one in front; a ring). focusNext: rc of the focus, 0 when there is none |
| `fv.views.enableCommands CMD…` / `disableCommands CMD…` | `EnableCommands` / `DisableCommands` | |
| `fv.views.commandEnabled CMD` | `CommandEnabled` | rc 0 when enabled |
| `fv.views.getCommands` / `setCommands [CMD…]` | `GetCommands` / `SetCommands` | **the disabled names**: `RESULT` = them sorted, space-separated / exactly these disabled (the pair saves and restores a set) |
| `fv.views.resetCursor V` | `ResetCursor` | above |
| `fv.views.setCursor V X Y` | `SetCursor` | `CursorX` / `CursorY`, then resetCursor when V is focused |
| `fv.views.showCursor V` / `hideCursor` / `blockCursor` / `normalCursor` | `ShowCursor` … | `SetState(sfCursorVis / sfCursorIns, …)` |
| `fv.views.execView G P` / `endModal V CMD` / `mouseEvent V MASK` | | "Modal views" below |
| `fv.views.dragView V MODE AX AY BX BY MINX MINY MAXX MAXY` | `DragView` | "Dragging" below |

rc 2 (one debug line, `RESULT=''`) for a malformed call: not a view or
group, a wrong argument count, a bad number, a name with other characters.

## Modal views

* **`fv.views.execView G P`** (FV `ExecView`; `RESULT` = the command): saves
  the event record, G's `Phase`, P's `Options` and owner, the top view, G's
  `Current` and the command set; clears P's `ofSelectable`, sets `sfModal`,
  makes P G's `Current` (EnterSelect: the old Current stays selected),
  inserts P when it has no owner; runs P's `Execute` (through the elision);
  then puts `Current` back (LeaveSelect), removes P when it was inserted
  there, and restores everything, **the event record included**: the caller's
  dispatch goes on with its own event (FV has a local `Event` per loop). P
  `''`: `cmCancel`. The pattern: `TDlg.new dlg …; fv.views.execView
  "$FV_DESKTOP" dlg; [[ $RESULT == cmOK ]] && …; dlg.delete`.
* **`TGroup.Execute`** (a func) is FV's loop: `EndState=''`; read an event
  from the event source and hand it to the group's `HandleEvent`, then
  resetCursor, until `EndState` is set; repeat while `Valid(EndState)` says
  no; `RESULT` = `EndState`. **No `HandleEvent` for `evNothing`** (FV calls
  it every idle tick; an override would pay a dispatch each time): periodic
  work belongs in fv.app's `Idle`. `TView.Execute` answers `cmCancel`.
* **One terminal update per event**: while a handler runs, the loop holds
  the terminal update (the handler's drawing entries go to the buffer) and
  sends it once afterwards, with the cursor. A nested modal view, and what a
  handler drew before a mouse tracking loop (`mouseEvent`), are shown at
  once all the same; a hold of yours (`lockScreenUpdate`, a user lock) keeps
  everything back as usual.
* **`fv.views.endModal V CMD`** (FV `EndModal`): the top view's `EndModal`
  (the view `execView` runs, else the first of V and its owners with
  `sfModal`: the application); TGroup's sets its `EndState`. rc 1 when no
  view is modal.
* **`fv.views.topView V`** (FV `TopView`): `RESULT` = that top view (the
  view `execView` runs while it is live, else the first of V and its owners
  with `sfModal`), `''` when none; rc 2 for a malformed call.
* **`Valid CMD`** (a func) answers by its **rc**: 0 = valid (RESULT 1), non-zero
  = not. `TView.Valid` agrees; `TGroup.Valid` asks every subview (front to
  back), or for `cmReleasedFocus` only a `Current` with `ofValidate`. **An
  override says no with an explicit `return 1`, and passes a built-in's no
  on with `inherited Valid "$@" || return`** — or with a bare
  `inherited Valid "$@"` as its last line: since kklass round 7 (K-2) a func
  fails with its body's rc, so the refusal passes either way (013 pins it;
  before, the bare form answered rc 0). `|| return` is no longer required
  but stays good style when more lines follow; every built-in body here
  passes its rc on that way.
* **The end of input latches** (`__FV_VW_EOF`): when the event source says
  "end of input" (rc 1; any other non-zero rc is taken for it too, with a
  debug line, so a broken source cannot spin), the running loop and every
  loop around it end after the current event **without asking `Valid`**,
  with `cmCancel` (`cmQuit` for a group without an owner: the application);
  a new `execView` answers `cmCancel` at once without a loop. So a
  `Valid(cmQuit)` that opens a "save?" box at the end of input cannot spin:
  the box answers `cmCancel` at once.
* **The owner-process rule**: `execView` and `Execute` refuse to run in a
  subshell (`$( … )`, a pipeline: `BASHPID` is not the screen's owner): rc 2
  and one debug line. A modal loop there would draw through the parent's
  screen while the parent's buffer goes stale.
* **`fv.views.mouseEvent V MASK`** (FV `MouseEvent`): reads events, dropping
  the others, until one whose bit is in MASK (`FV_EM_*`) or a mouse-up;
  **that event stays in `FV_EV_*`** (FV's `var Event`: the caller tracks a
  drag with it, `while fv.views.mouseEvent "$this" "$FV_EM_MOUSEMOVE"; do …;
  done`). rc 0 for a MASK event, 1 for the mouse-up, and 1 at the end of
  input (latched, `FV_EV_WHAT=evNothing`): the tracking loop ends.
* Nesting: each modal level adds a few bash frames; a dialog that destroys
  itself in its handler ends its loop with `cmCancel`.
* **The hooks fv.app sets** (stage 2f; private, documented for it):
  `__FV_VW_GETEVENT` (the event source, default `fv.drivers.getEvent`: fills
  `FV_EV_*`, rc 0 for every event including `evNothing`, rc 1 at the end of
  input; **it takes fv.drivers' optional TIMEOUT argument**: `dragView`
  drains the waiting mouse moves with `TIMEOUT` 0, "only what is already
  there", so fv.app's `_getEvent` must pass it on), `__FV_VW_PUTEVENT` (FV
  `PutEvent`, default `fv.drivers.putEvent`), `__FV_VW_EOF` (the latch;
  reset by whoever starts a new input), `__FV_VW_OWNER` (the screen's
  owner, `BASHPID` when the unit was loaded) and `__FV_VW_RESIZES` (stage
  2f: the event source adds 1 for each `cmResizeApp` it handled itself).
* A terminal resize while a modal view runs is handled inside fv.app's
  event source (FV's system event, handled at once and cleared: the loop
  sees `evNothing`); one during a drag ends the drag ("Dragging").

## TWindow

FV's `TWindow` (views.inc):

* the constructor above; the frame `NAME__fvframe` (a reserved name, made
  by `InitFrame`);
* `SizeLimits` (stage 2d): TView's maximum (the owner's size), FV's
  `MinWinSize` as the minimum (`FV_MINWINSIZE_X/_Y`, 16 × 6): `locate`,
  `growTo`, an owner resize and a drag keep a window at least that big (the
  constructor does not, as in FV);
* `Zoom` (stage 2d, a proc): below its `SizeLimits` maximum the bounds go
  into `ZoomRect` and the window takes its owner's whole extent; at the
  maximum it goes back to `ZoomRect`. One `locate`: the old ∪ new area
  redrawn once. The frame's zoom icon shows `↕` at the maximum. A `ZoomRect`
  that is not four integers, or a maximum that is not an integer of at most
  9 digits (no owner: FV's `high(Sw_Integer)`), makes it do nothing;
* `CalcBounds` (stage 2d; FPC's TWindow.CalcBounds of 2026): an owner
  resize moves the `ZoomRect` by the same `GrowMode` rules as the bounds, so
  an unzoom after a terminal resize lands in proportion (fv.app's resize
  flow, 2f);
* `GetPalette` (func): FV's `CBlueWindow` / `CCyanWindow` / `CGrayWindow` by
  `Palette` (`FV_WP_BLUEWINDOW` 0, `CYANWINDOW` 1, `GRAYWINDOW` 2: CAppColor
  8–15, 16–23, 24–31). After changing `Palette`: `fv.views.resetPalette W`
  and a redraw;
* `GetTitle MAXSIZE` (func): `Title` cut to MAXSIZE characters (the frame
  asks for it);
* `SetState`: TGroup's; `sfSelected` → `SetState(sfActive)` (the frame's
  border changes look) and the window commands;
* `HandleEvent`: TGroup's, then `evCommand cmClose` for this window
  (`FV_EV_INFO` `''` or the window) with `wfClose`: handled; not modal →
  `Close`; modal → `cmCancel` posted (`PutEvent`). `evBroadcast
  cmSelectWindowNum` with `FV_EV_INFO` = `Number` on a selectable window:
  select it, handled. `evKeyDown kbTab`, `kbDown`, `kbRight` → the next
  control (FV `FocusNext(False)`), `kbShiftTab`, `kbUp`, `kbLeft` → the
  previous one, handled (FPC's TWindow takes the arrows too; a control that
  uses them handles them first, in the focused phase). Stage 2d: `evCommand
  cmZoom` for this window (`FV_EV_INFO` `''` or the window) with `wfZoom`:
  `Zoom` (virtual), handled; `evCommand cmResize` with `wfMove` or `wfGrow`
  and an owner: the keyboard drag (below) with `DragMode` + those bits
  (`wfMove` / `wfGrow` are `dmDragMove` / `dmDragGrow`), handled;
* `Close`: when `Valid(cmClose)` agrees, the window is destroyed (FV
  `Free`: `W.delete` — out of its owner, the focus moves on, its area
  repainted).

### The frame's mouse (stage 2d; FPC `TFrame.HandleEvent`)

A mouse-down that the window's dispatch hands to its frame (the frame is
the back-most subview, so: a click on the border):

| where (frame coordinates) | when | does |
|---|---|---|
| top row, X 2–4 | `sfActive`, owner `wfClose` | the close icon's press tracking: `☼` (`FrameMode` `fmCloseClicked`) while the mouse is on it, `■` off it (through `mouseEvent`, moves and auto); released on it → `evCommand cmClose` posted (`PutEvent`, `FV_EV_INFO` = the window), which closes it at the next event |
| top row, X W−5 – W−3, or a double click anywhere on the top row | `sfActive`, owner `wfZoom` | the zoom icon likewise (`fmZoomClicked`) → `cmZoom` posted; a double click posts it at once, without tracking |
| top row otherwise | owner `wfMove` | the window dragged by the mouse (move) |
| X ≥ W−2, Y ≥ H−1 (the grow corner) | `sfActive`, owner `wfGrow` | the window dragged by the mouse (grow) |

Each handles the event (`FV_EV_INFO` = the frame). The first click on an
inactive window selects it (click to focus) and is consumed there, so the
icons work from the second click, as in FV. The press tracking redraws the
frame's top row only when `FrameMode` changes (one write; FV draws the
whole frame on every mouse event; a frame class with its own `Draw` is
drawn whole through it). The event record is put back after the tracking.
The tracking ends at once when the event source destroys the frame or its
window (nothing drawn or posted), and in a subshell it reads and posts
nothing (the owner-process rule, as the drags; the event is handled).

## Dragging

**`fv.views.dragView V MODE AX AY BX BY MINX MINY MAXX MAXY`** (FV
`DragView(Event, Mode, Limits, MinSize, MaxSize)`; the event is the
current `FV_EV_*`): `MODE` holds `FV_DM_DRAGMOVE` / `FV_DM_DRAGGROW` and the
`FV_DM_LIMIT*` bits; the limits are in V's owner's coordinates (B
exclusive); `MAXX` / `MAXY` may be FV's `high(Sw_Integer)` (2147483647).
Procedure: `RESULT` kept, rc 0; rc 2 for a malformed call or in a subshell
(the owner-process rule: it reads events).

* **A mouse-down** drags by the mouse until the mouse-up: with
  `dmDragMove` the origin follows the mouse at the offset of the
  mouse-down, else (`dmDragGrow`) the size does. One step at the
  mouse-down's place (FV), one per move, the last at the mouse-up's place
  (FV: "not all terminals send drag events"). Other events meanwhile are
  dropped (FV `MouseEvent`).
* **Anything else** drags by the keyboard until Enter (kept) or Esc (the
  start bounds back): the arrows move one cell (`dmDragMove`), Shift +
  arrows grow (`dmDragGrow`; `kbShiftLeft` …: a `Shift` in the key's name is
  FV's shift state), `kbCtrlLeft` / `kbCtrlRight` by 8 (with Shift: grow by
  8; Ctrl+Up / Ctrl+Down do nothing, as in FV), `kbHome` / `kbEnd` /
  `kbPgUp` / `kbPgDn` to the limits' left / right / top / bottom edge
  (move; with Shift the same); `kbShiftEnter` / `kbShiftEsc` end it as
  Enter / Esc (FV compares the KeyCode). Non-key events are dropped (FV
  `KeyEvent`).
* **Each step is FV's `MoveGrow`**: the size clamped to MIN..MAX, the
  origin kept so that a column and a row stay inside the limits, then the
  `dmLimitLoX/LoY/HiX/HiY` bits (`dmLimitAll`: wholly inside); then
  `locate` (its own `SizeLimits` clamp, the old ∪ new area redrawn once;
  FV locks the owner, whose unlock redraws all of it: D17). Each step is
  shown at once, also inside a modal handler (the loop's per-event hold is
  released before the next event is read, as `mouseEvent` does).
* **`sfDragging`** is set on V for the drag (through the virtual-aware
  `setState`): a window's frame is redrawn border-only in its dragging look
  (single line, colour 5) and back after; `GetHelpCtx` answers
  `hcDragging` meanwhile.
* **Motion coalescing** (design R10): after each mouse move the events
  already waiting are read with `"$__FV_VW_GETEVENT" 0` (fv.drivers' "only
  what is there"); each further move replaces the position, so one step
  draws the last of them; a mouse-up, a resize or the end of input met there
  is kept for the end; anything else is dropped.
* **The end of input** (the latch, as the modal loops): a keyboard drag
  ends as Esc (the start bounds back; the modal loops end with `cmCancel`
  too), a mouse drag where it is (FV's mouse drag has no undo).
* **A resize mid-drag** (design §2.3): an `evCommand cmResizeApp` from the
  event source ends the drag at once, with V's bounds clamped into its
  owner's new extent by `MoveGrow` (limits = the owner's extent, the size
  limits asked again) and no undo; the drag does not post it again. The
  same happens when the event source handled the resize itself and
  answered something else (fv.app's GetEvent: FV's `TProgram.GetEvent`
  handles the system event at once and clears it): the drag compares
  `__FV_VW_RESIZES` around each read, the step loop's and the drain's
  (stage 2f). Events after it stay unread.
* The event record is put back afterwards (FV passes `Event` by value).

The framework's own drags (FV's `DragWindow`): `cmResize` in
`TWindow.HandleEvent` (keyboard) and the frame's top row and grow corner
(mouse) drag the window inside its owner's extent, within its
`SizeLimits`, with `DragMode` + the move / grow bit. TView's default
`DragMode` is `dmLimitLoY`: a window cannot be dragged above its owner's
top edge.

## Cost

Measured in the test lib's scenes, 80 × 24, frames to `/dev/null`, median of
5 × 10 actions per process, processes of the 2c-3 units (`git show HEAD`, A)
and of these (B) alternated A1 B A2 × 5 (the median over rounds; the spread,
the largest per-round A2/A1 − 1, stays within 0.16), 2026-11-17, stage 2c-p:

| ms | Git-bash 5.3.15 A → B | MSYS2 5.3.9 | Cygwin 5.2.21 |
|---|---|---|---|
| Tab via the event path, overlapping windows (each way) | 26.2 → 21.0 | 26.3 → 21.1 | 26.9 → 21.4 |
| Tab, side by side | 28.5 → 21.9 | 28.3 → 21.4 | 29.1 → 21.7 |
| click to focus the back window, overlapping / side by side | 27.4 → 22.0 / 29.1 → 22.0 | 27.3 → 22.1 / 29.2 → 22.3 | 28.1 → 22.3 / 30.0 → 22.7 |
| kbDown to the focused leaf (2 `drawPart`) | 5.09 → 4.12 | 5.08 → 4.31 | 5.11 → 4.25 |
| first paint of the P2 scene (plain leaves), from an initialised screen | 17.0 → 14.0 | 17.2 → 14.1 | 17.7 → 14.6 |
| the same, palette and frame caches cold | 20.4 → 17.8 | 20.5 → 17.4 | 21.1 → 17.8 |
| the same with the list stand-ins | 22.3 → 18.3 | 22.6 → 18.3 | 23.2 → 18.8 |
| two border-only frame redraws + flush | 9.9 → 8.1 | 10.0 → 8.0 | 10.3 → 8.4 |
| move a window by one cell | 14.3 → 11.7 | 14.3 → 11.9 | 14.8 → 12.4 |

Against P2's targets: the first paint (≤ 15 ms) is met; Tab (≤ 20 ms) and kbDown
(≤ 4 ms) are not (≈ 21–22 ms and 4.1–4.3 ms on all three runtimes).

Where a Tab goes now (overlapping, Git-bash, 21.0 ms; parts stubbed out one
after another, so each figure is what remains of it given the ones before,
±0.5 ms): the terminal update 3.9 (one colour run costs ~20 µs whatever its
length; ~20 rows of ~6 runs); the four quiet focus broadcasts 1.3; the list
stand-in's own Draw (18 rows of `printf` + `writeStr`, test code) 2.6; the
frame string cache hits 0.5; the frame writes (the new front window's frame,
the old one's border sides and rows) 2.2; the covered-ring cut and the views
in front ~1.0; the rest of the border-only redraw 1.2; the shadows 1.0; the
cursor 0.8 (noisy); the order redraw's machinery (paint, group draw, the
leaf's Draw dispatch) 1.9; the routing down the tree with `inherited` 1.5;
the rest (the application's dispatch, the focus chain's `SetState` calls,
`putInFrontOf`) 3.2. What made the difference against 2c-3: **bash copies a function's
whole body on every call** (an 80-line function costs ~50 µs per call before
its first line runs), so the hot functions keep their rare cases in helpers
(the frame's string cache hit vs. its build, the border's checks vs. its
drawing, `SetState`'s drawing bits, TWindow's `cmClose` /
`cmSelectWindowNum`, the cursor's coverage walk, `_over`'s per-level loop);
fv.video's unchecked twins of the writes (`_wstr`, `_wbf`, `_fcf`,
`_shadef`, `_clipf`; fv.video's README); quiet broadcasts (above); a frame's
two sides in one `fillColumns`; one-test skips of views in front that miss
the repainted pieces; TWindow's `GetTitle` and TView's `SizeLimits` run
inline when the class has not overridden them.

**Stage 2d** (Git-bash 5.3.15, 80 × 24, frames to `/dev/null`, the events
scene of the tests: two TWindows with a list stand-in each that writes its
rows, median of 5 runs, 2026-11-17; a quiet machine):

| action | ms | dispatches / writes |
|---|---|---|
| move the front window by one cell (`moveTo`; same scene, for comparison; HEAD and stage 2d alike) | 15.2 | — |
| one keyboard drag step (an arrow under `cmResize`; 20 steps, minus a drag of none) | 17.4 | 2 / 40 (the two stand-ins' Draws, their rows) |
| one mouse drag step (a move, the drain, the step) | 19.0 | 2 / 40 |
| entering and leaving a drag (`sfDragging`: two border-only frame redraws) | 14.4 | 3 + 3 writes |
| `cmZoom` and back (whole desktop each way) | 43.3 (≈ 21.7 each) | 4 + 5 / 27 + 43 |

A drag step costs ~2–4 ms more than a bare `moveTo`: it runs deep in the
handler's call stack (the application's and the window's dispatch frames),
where every global lookup walks more bash frames, plus the event read and
`MoveGrow`. The reads here are scripted (a real
`fv.drivers.getEvent` adds ~0.9 ms per mouse report and ~0.2 ms per drain
poll).

**Stage 2g: the call budget and the `fvviews` bench.** The design's scene
(§3.1): `TMyApp` (a `TApplication` whose `HandleEvent` override calls
`inherited`), the desktop, two windows side by side (half the screen wide,
the desktop's height) with a list stand-in `TTestList` each (TView's default
`EventMask`; `Draw` = one `writeBuf` per visible row — since D21 stage E
one `writeLines` call; kbDown = two `drawPart`s; kbPgDn = a new page +
`drawView`), the status line.

The dispatch budget (`tests/010_CallBudget.sh` here, `fv.app`'s
`014_CallBudget.sh` through the application; the limits are the design's
§3.2 test limits; the counts are the same for a 21-row and a 42-row stand-in):

| action | dispatches | limit | fv.video writes (21 / 42 rows) |
|---|---|---|---|
| kbDown (TMyApp, `inherited`, the stand-in) | 3 | 6 | 2 / 2 |
| kbPgDn (+ the stand-in's `Draw`) | 4 | 8 | 21 / 42 |
| Tab side by side: `cmNext` / F6 → the status line → `cmNext` | 3 / 5 | 8 | 10 / 11 |
| the same back (the window in front repainted under the other's shadow) | 4 / 6 | 8 | 28 / 49 |
| Tab overlapping, each way: `cmNext` / F6 | 4 / 6 | 10 | 29–30 / 50–51 |
| click on the inactive window / on the covered one | 2 / 3 | 8 | 10–11 / 30 (51) |
| repaint (`redraw`, forced update) | 2 | 6 | 51–52 / 93–94 |
| resize 80 × 24 → 200 × 50 / back | 5 / 5 | 8 | 103 / 51 |
| idle tick | 0 | 1 | 0 |
| the first idle tick after a window switch (FV's `Idle` broadcasts `cmCommandSetChanged`: TMyApp + `inherited`) | 2 | (logged) | 0 |
| first paint (`Run`) | 2 | (6) | 51 / 93 |

The drawing shape: a full frame draw 3 writes, a window's shadow 2 shade
calls, a border-only frame redraw 3 writes, the status line 1 write.

Times: `tools/bench` suite `fvviews` (every action inside `app.Run`, keys
from a file through `fv.drivers.getEvent`; tools/bench/README.md), median of
5 rounds × 10 actions, 2026-11-17, **on a machine running ~1.9× slower than
the stage 2c-p table above**: the 2c-p reference (the test lib's events
scene, `cmNext` side by side) took 41.9 ms here against 21.9 ms then, a
plain call 8.8 µs against 4.9 µs, the CPU held at 2.5 of 3.8 GHz. The last
column divides the Git-bash median by 1.91; compare it with the targets
(PLAN §5.4, design §3.3 / §4):

| ms | Git-bash 5.3.15 | MSYS2 5.3.9 | Cygwin 5.2.21 | Git-bash ÷ 1.91 | target |
|---|---|---|---|---|---|
| 80×24 kbDown | 12.9 | 12.7 | 12.8 | 6.7 | ≤ 4: missed |
| 80×24 kbPgDn | 23.5 | 23.0 | 22.9 | 12.3 | 8 (R8 → P3): missed |
| 80×24 Tab (F6), side by side, both ways | 61.7 | 59.7 | 60.2 | 32.3 | ≤ 20: missed |
| 80×24 Tab (F6), overlapping | 62.9 | 62.8 | 63.6 | 32.9 | ≤ 20: missed |
| 80×24 kbTab inside a window (two controls) | 9.2 | 9.4 | 8.8 | 4.8 | — |
| 80×24 click on the other window (press + release) | 66.2 | 62.8 | 64.8 | 34.6 | — |
| 80×24 one keyboard drag step: move / grow | 37.1 / 41.1 | 36.2 / 39.8 | 38.1 / 41.3 | 19.4 / 21.5 | R10 |
| 80×24 overlapping: click / drag step | 69.7 / 51.7 | 68.2 / 50.7 | 68.8 / 51.9 | 36.5 / 27.1 | R10 |
| 80×24 Ctrl+L redraw (forced) | 57.1 | 55.2 | 56.8 | 29.9 | — |
| 80×24 first paint from `Run`, P2 scene (D18 gate) / `+init` | 40.4 / 53.4 | 40.5 / 51.4 | 41.8 / 52.4 | 21.1 / 28.0 | ≤ 15 (F-1): missed |
| 80×24 first paint from `Run`, list scene / `+init` | 60.9 / 69.5 | 57.4 / 70.3 | 57.6 / 68.8 | 31.9 / 36.4 | F-1 open |
| 200×50 redraw / first paint | 106.2 / 104.9 | 103.7 / 107.1 | 106.0 / 106.7 | 55.6 / 54.9 | 30 (R9): missed |
| 200×50 Tab (F6) | 96.5 | 86.4 | 90.7 | 50.5 | R2 |
| 200×50 kbDown / kbPgDn | 12.8 / 43.1 | 13.4 / 43.0 | 12.0 / 42.7 | 6.7 / 22.6 | — |
| 200×50 click / drag step move / grow | 93.8 / 68.1 / 69.4 | 91.3 / 64.1 / 68.9 | 94.6 / 67.0 / 69.2 | 49.1 / 35.7 / 36.3 | R10 |
| resize 80×24 → 200×50 / back | 143.4 / 93.5 | 139.7 / 88.3 | 138.5 / 89.2 | 75.1 / 49.0 | — |

The `Run` frame itself costs little: the same keys read and dispatched at
top level take 0.5–2 ms less (kbDown 11.4 against 12.0, Tab 55.6 against
57.8, Git-bash). Where the time goes (Git-bash, this machine; ÷ 1.91 for the
quiet machine; each part with the ones above it stubbed out):

* **One key event, whatever it does, ~5.8 ms (≈ 3.0)**: F12, taken by
  nobody: the key read (`fv.drivers.getEvent`, a 5-byte sequence) 1.2,
  `TProgram.GetEvent` through the elision 0.2, the application's
  `HandleEvent` 4.1 (the status line's pre-process look-up 0.2; the desktop
  → window → stand-in routing 2.0, of which the stand-in's own dispatch
  0.7; TMyApp's dispatch + `inherited` + the built-in TApplication /
  TProgram / TGroup bodies ~1.8), the cursor and the (empty) terminal update
  0.3. Every action below pays it once per event (Tab through F6: twice).
* **kbDown 12.1**: the key event 6.2, the two `drawPart`s' machinery 4.1,
  the stand-in's two rows 1.0, the terminal update 0.8.
* **kbPgDn 23.3**: the key event 6.2, the stand-in's 21 rows (`printf` +
  `writeLine`, test code) 10.9, the terminal update 3.6, `drawView` 2.6.
* **Tab (F6) 60.1**: two events ~12 (the key, then `cmNext` from the put
  slot), the terminal update 11.1, the stand-in's rows 5.6 (every other Tab
  repaints the window that comes back to the front under the other's
  shadow), the window switch itself ~31 (setState chain, two border-only
  frames, shadows, putInFrontOf, the window commands disabled / enabled).
* **The drag step 36.5**: the key event ~6, the terminal update 8.0, the
  two stand-ins' rows 10.5, `locate` and the redraw of old ∪ new ~12.
* **The redraw 54.8**: the terminal update 8.8, the rows 18.3, the
  rest (frames, shadows, background, status line, the key event) 27.8.

Levers (no optimisation in 2g; the supervisor's plan decides): the fixed
per-event cost (an application that does not override `HandleEvent` saves
two dispatches, ~0.8 ms here; the kklass K-2 stage's call cost; a cheaper
routing walk); the terminal update of whole rows (R2: one damaged range per
row; a split at a long unchanged middle); P3's one write per visible row
for the lists; fv.video's per-write cost for the 200 × 50 repaints (R9).

**D21, the deep performance round (stages A–C).** The profile found no hot
spot: every action is bash's per-command and per-call cost spread over the
drawing entries, the covering walks and the routing. What changed (the
numbers come from the CI bench run after the stage; the dispatch counts are
the same as before in every case):

* *Structure caches* (fv.views.sh, the state block; one helper,
  `fv.views._restruct`, drops them wherever a subview list or an `Owner`
  changes). They hold the tree's shape, never a field's value, so State,
  Options and the bounds are read live and need no invalidation:
  `__FV_VW_DEX[v]` is "v and every owner visible, the root exposed" as one
  arithmetic test over the live `State` fields (`fv.views._drawable` without
  the owner walk; the walk still runs under a lock or `SKIP`), dropped at
  insert / delete / destruction; `__FV_VW_FRL[v]` lists the views in front of
  v or of an owner (`_over`, the frame ring's `_uncover`), dropped at insert /
  delete / destruction / putInFrontOf; `__FV_VW_OEX[g]` is "a subview of g
  has ofPreProcess or ofPostProcess" over their live `Options`
  (`_groupEvent` skips its pre / post scan with one test), dropped at insert
  / delete / destruction.
* *drawPart's fast path*: one test for the common call (a live leaf, a
  painter seen before, rows of plain digits, no nesting, no wide rows), then
  an inline body (`_begin` and the held flush inline, no argument helpers);
  every other call takes the checked path. The painter is checked on its
  first use only (`__FV_VW_PNT`): one unset after that fails with bash's
  rc 127.
* *Covered paints skipped*: a subview the visible covering views in front
  hold **together** (the desktop's background behind two windows side by
  side) and a shadow they hold (the back window's, under the front one) are
  not drawn — `_ucover`, a rectangle subtraction, runs only when a view in
  front holds the part's (or the strip's) top-left cell, so a scene where it
  cannot succeed pays one test per view in front. A window's paint and the
  order redraw's shadow strips are cut to the owner's clip: a shadow row
  below the desktop no longer repaints the status line. The `# writes` notes
  drop accordingly: paint / redraw / resize −2 (the background fill and the
  covered shade), Tab / click −2, grow −1, overlap Tab / click / move −1.
* *Smaller steps*: the dispatch loop's skip tests merged into one
  arithmetic test and one compare, the class lookup one simple command;
  `_pal` splits a palette without a here-string (80–280 µs each on Windows);
  fv.video's text and symbol checks are range globs and `writeBuf` / `_wbf`
  carry `_put`'s body inline (fv.video's README, "Cost").

**D21 stage E, the batch row writer.** `fv.views.writeLines` (the writers'
table) draws all the rows of a list's Draw in one call over fv.video's friend
entry `_wrows`: one call, one caller-state guard, every text and every symbol
checked at once (the elements joined), then a splice per row — instead of the
call, the argument checks and the guard per row of one `writeLine` each
(~180 µs per row at 80 columns, ~270 µs at 200 on the profiling laptop). A
row that needs more (wide text, a text outside the narrow cache, a refused
row) goes through writeBuf itself; a narrow row over a row with wide cells
through fv.video's wide splice. The bench's list stand-in (`TTestList`, in
the tests and in `tools/bench/fvviewcases.sh`) draws through it as P3's lists
will: the `# writes` notes count one write per painted list (paint / redraw
at 80×24 49 → 9, PgDn 21 → 1; the dispatch counts unchanged). Local A/B
(Git-bash, paired, ratios only): redraw 80×24 0.85, 200×50 0.79, first paint
0.85 / 0.79, PgDn 0.82. A ONE-row paint costs more through writeLines than
through writeLine (the two names checked, ~50 µs), so a one-row repaint (a
list's FocusItem, the stand-in's kbDown drawPart) uses writeLine: Down is
unchanged.

**P3 stage 3a-2.** *The edge test* (wide rows repainted across the screen
only when a pair straddles the rectangle's edge): a scene of CJK rows — a
background, two list windows side by side (the right one in front) and a
dialog in front with a one-row CJK "input line" — local same-process A/B
against the old banding (Git-bash, laptop, median of 5 × 30; ratios only:
CI decides): a PgDn of the back list's page 0.71–0.73, a Down (two
drawParts) 0.72–0.73 (the window in front on those rows is not painted
again), a typed character in the input line 0.87–0.91 (nothing in front of
it: only the checked path and the bands' bookkeeping saved). *The broadcast
table*: a Tab in the dialog scene (8 controls, 4 label-like leaves with a
built-in body listening to broadcasts) 0.72 with the body's row than
without (8 calls saved per Tab); fv.views' own rows change no count. The
`fvviews` bench (ASCII scenes, `views-80`, 2 × 10 per side) is unchanged
within its noise. *The marking of hidden pairs* (fv.video's `__FV_VS_WNEW`,
after the critic round): one arithmetic test per write on fv.video's wide
path and a walk over the flagged rows after a repaint; the ASCII paths are
untouched. Same scene, same-process A/B against the marking before (the
flag's line taken out of `_putw`; median of 5 × 30): a PgDn of either list's
page 1.00–1.01, a Down and a typed character within the noise.

## Contract (kcl README §1) and deviations

§1; deviations:

* **instance classes with FV field names**, and fields of other instances
  read and written directly under the kklass friend contract;
* **friend entries for the fv.\* units above this one** (fv.menus,
  fv.app — the same framework, versioned together; not for scripts): the
  elision tables `__FV_VW_IMPL` / `__FV_VW_FUNC` (a unit adds its classes'
  built-in bodies; a reload of this unit merges, so they survive), the
  quiet-broadcast table `__FV_VW_QGRP` and the broadcast table
  `__FV_VW_BCAST` (P3; both merged likewise), calls of
  `fv.views._virt` (the elision entry), `fv.views._topView V` (topView into
  the caller's `__fvw_t`, no checks), `fv.views._viewEvent` (TView's
  HandleEvent body), reads of `__FV_VW_LIVE` (a live view), `__FV_VW_CRC` (a
  refused TView part's rc), `__FV_VW_ERRSYM`, the disabled-command set
  `__FV_VW_CMDOFF` and the event hooks `__FV_VW_PUTEVENT` / `__FV_VW_EOF`.
  fv.menus' and fv.app's READMEs list what they use;
* **loud refusals**: re-creating a live view, a reserved name and a
  constructor that skipped `inherited` print one `Error:` line on stderr (not
  only under `VERBOSE_KKLASS=debug`; `quiet` silences them) — a silent rc
  would leave a corrupt tree behind in a loop that ignores it;
* the `var` parameters of FV's geometry answer in the `FV_RECT_*`,
  `FV_POINT_*`, `FV_MIN_*` / `FV_MAX_*` globals (also `RESULT` for the
  getters);
* from Free Vision: `makeLocal` uses the cached absolute origin (FPC's
  `MakeLocal` stops its owner walk at a negative coordinate; this one does
  not); only the root's `sfExposed` is read (FV keeps the bit on every view
  of the application's tree); the writers do not update the terminal (the
  drawing entry does, once); `V.Draw` outside the painter draws nothing;
  `unlockScreenUpdate` updates the terminal at 0 (FV leaves that to a
  separate `DrawScreenBuf`); the redraw model above;
* from Free Vision, stage 2c-3: no `HandleEvent` for `evNothing` in the
  modal loop; the focus changes redraw only what changed (D17); `select` of
  an `ofTopSelect` view already in front makes it `Current` (FV's
  `MakeFirst` is a no-op there and leaves another view Current); commands
  are names and the set kept is the disabled one (`getCommands` /
  `setCommands` work on it); `Valid` answers by its rc; the end-of-input
  latch and the owner-process rule are additions; `execView` puts G's
  `Current` back (LeaveSelect) before it removes a P it inserted (FV removes
  P first), so G gets a `cmReleasedFocus` for P without a matching
  `cmReceivedFocus` for it; `execView` refuses P = G or an owner of G (rc
  2); a hidden or disabled view is never made Current by `select`'s
  in-front case, and a hidden window does not answer `cmSelectWindowNum`;
  destroying a group deselects its `Current` first (FV `TGroup.Done` hides
  every subview), without drawing; an empty `FV_EV_WHAT` from the event
  source is `evNothing`; an `unlockScreenUpdate` without its lock inside a
  modal handler is ignored (one debug line); `insert` into an active
  group sets `sfActive` on the view without drawing it twice (FV draws it,
  then redraws it active); `fv.views.delete` of the Current view resets
  `Current` while the view is still in the group but hidden (FV's order), so
  its `cmReleasedFocus` reaches the owner; `mouseEvent` returns its event in
  `FV_EV_*` (FV's var parameter; the design's "inner loops save and restore
  the event record" holds for `execView` and `message`, whose callers keep
  their own event).
* from Free Vision, stage 2d: a drag step does not lock the owner (FV's
  `MoveGrow` does, and its unlock redraws the whole owner per step): one
  `locate`, the old ∪ new area redrawn (D17); the frame's press tracking
  redraws only the top row and only when `FrameMode` changes, and the
  **release's own place** decides whether the icon's command is posted (FV
  decides by the last place before the mouse-up, so a terminal that reports
  no motion while a button is held would close a window on a release
  outside the icon); the end of input ends a keyboard drag as Esc and a
  mouse drag where it is, and an icon's tracking without its command; a
  `cmResizeApp` ends a drag (design §2.3); queued mouse moves are coalesced;
  `Zoom` does nothing without a usable maximum or `ZoomRect` (FV would
  locate to `high(Sw_Integer)` without an owner); `MinWinSize` is the pair
  `FV_MINWINSIZE_X/_Y`; after a drag that grew a window, interior cells no
  view covers keep the dragging colour of the frame's body (border-only
  frames, above: the same background, nothing visible).

Known kklass limits met by the tests (not this unit's): building a class or
calling `.new` under an `IFS` holding digits or letters fails (with letters
`.new` crashes bash), and `inherited` fails under an `IFS` holding letters.
The tests set such an `IFS` after the classes and instances exist.

## Tests

`bash kcl/fv.views/tests/tests.sh` — headless (no terminal, no `initVideo`).
`tests/fvw_testlib.sh` holds the headless screen, the buffer reader
(`fv.video.getRow`), the dispatch counter (shims around `kk._exec`,
`kk._call`, `kk._parent`, `kk._constructor_exec`), the fv.video write counter,
`fvw_budget` / `fvw_budgetw` (the dispatches, and the writes of the same run), and the desktop-like scene of the drawing tests
two framed windows with shadows and a list stand-in each: `TTWin`, `TTList`,
`fvw_scene`) and `fvw_full` (the screen against a full repaint from
garbage); for stage 2c-3 the scripted event source (`fvw_events`: no
terminal), `fvw_root` and the events scene (`fvw_tscene`: an application-like
root with a TMyApp-like override, a desktop, two `TWindow`s with a list
stand-in each that handles keys); for stage 2g the design's list stand-in
`TTestList` (TView's default EventMask, one `writeLines` per Draw (D21 stage E; one `writeBuf` per row before), `drawPart`
on kbDown, a new page on kbPgDn; `fvw_classes3`, `fvw_mklwin`); for P3 the
dialog scene (`fvw_dscene`: the events scene plus a dialog-like gray window
in front with N selectable one-row controls). Each test file's stderr is captured:
anything on it fails one test.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the public API of stages 2c-1 to 2d exists; loads, re-loads and the main path (drawing and the events included: a window, focus, message, commands, the cursor, a modal view at the end of input) under `set -eu`; `kk.unit --forget` + re-source keeps the live tree; failing calls return under `set -e`; nothing on stdout; no stray globals or functions; the test lib itself (both counters keep rc and RESULT and unwrap, the buffer reader, `fvw_budget`) |
| 002_Tree | insert / insertBefore / delete / makeFirst / putInFrontOf, the navigation (rings and nil), Owner, Current per FV `ResetCurrent`, the sfSelected bits, refusals (rc, RESULT, unchanged tree), a cycle, `V.delete` of a group, names differing in case under nocasematch, the hook's calls |
| 003_Geometry | the constructors' corners and defaults, MaxViewWidth, getBounds / getExtent, the cache and the clip, centring, locate / moveTo / growTo with SizeLimits, an owner resize by every GrowMode flag (gfGrowRel, the S = D guard), CalcBounds / SizeLimits answers, makeLocal / makeGlobal / mouseInView, GetHelpCtx, bad numbers; a group moved and resized at once (each subview's old rect in its redraw hook), a CalcBounds override that sets nothing, a subview destroyed during the resize |
| 004_Draw | the writers in local coordinates (palette index → symbol, ErrorAttr outside, `writeLine`'s repeat count), their answers and refusals (outside a Draw, bad arguments); the context and `FV_CLIP_*` inside a Draw; the owner's clip; the caller's clip and RESULT kept; a `drawView` nested inside a Draw (the outer context and clip intact); TView.Draw; a group override that decorates after `inherited Draw`; nothing drawn when hidden / in a hidden group / without an exposed root; `V.Draw` outside the painter; `getColor`; `drawPart` (clipped rows, the front view over them, no dispatch, rc, refusals); `redraw`'s forced frame, also deferred while held; re-entrancy (a Draw redrawing a view behind it with drawView + drawPart: once, no recursion, == a full repaint, also after a move; a list redrawing scroll bars beside and behind it); a Draw ending non-zero under `set -e` (insert, drawView, moveTo, unlock); drawPart on a group refused |
| 005_Overlap | the desktop-like scene: painter's order and FV's cells, 4 dispatches for the first paint, shadows (2 × 1, characters kept, over a sibling, clipped by the owner); move, resize, a group resize, makeFirst / putInFrontOf, a reorder without overlap, delete / insert, hide / show: each leaves exactly a full repaint's screen and draws each list at most once; the covering skip (framed group and leaf cover; frameless group, hidden frame, shadow do not); a frameless group's subview hidden / shown / moved / deleted (repainted from below the group); wide characters at a repaint edge; randomized wide-character scenes (seeded, 2 × 30 operations: every redraw == a full repaint) |
| 006_Lock | lockScreenUpdate (nested, the update held, sent once, RESULT kept); lock / unlock: draws and the hooks' redraws held, redrawn once at 0 (also FV's "Lock; change fields; Unlock"), nested counts, an inner group inside a locked owner, both counters together, refusals, the aliases, a group destroyed while locked; destroying a locked window, or one holding a locked group, sends the removal at once |
| 007_Events | the phases (pre / focused / post, the Phase each handler sees), positional events (the front-most visible view, hidden skipped, a disabled one swallows), broadcasts, the EventMask skip without a call (dispatch counts; built-in views 0), disabled views, the stop at evNothing, views removed / destroyed meanwhile, unknown names, click to focus and ofFirstClick, a nested group's Current, message (the handler, rc, the caller's record restored), RESULT kept, a handler's rc under `set -e`, refusals |
| 008_Focus | the chain's bits, select of a covered window (== a full repaint, its list drawn once), the focus broadcasts in FV's order, sfActive propagation (a frame border = 3 writes, no leaf redraw), side by side (borders + shadow only), Tab in a window (arrows too; unselectable / disabled skipped), focusNext / selectNext, focus with an ofValidate Current, click to focus through the chain, resetCursor (position, shape, outside, covered, unfocused), a SetState override, hide / show / sfShadow, delete of the focused window, insert into an active group, select of a front window that is not Current, refusals; quiet broadcasts (stage 2c-p: no dispatch, the Phase a delivery sets, a listening leaf breaks the quiet and hears what it heard, the dispatch's skips in the walk; a walk that ends not quiet leaves no Phase behind); stage 2f: a built-in group handler of another unit is quiet only when listed in `__FV_VW_QGRP` |
| 009_Commands | FV's default set at load (and across a re-source), enable / disable / commandEnabled, the changed flag, getCommands / setCommands, the window commands by Flags, execView restoring the set, refusals |
| 010_CallBudget | stage 2g, the design's §3.1 scene built from fv.views' classes (a TMyApp-like root with `inherited`, a desktop, two 40 × 23 `TWindow`s side by side with a `TTestList` stand-in each, and the overlap scene) through TGroup's Execute with the scripted event source: the dispatch budgets with §3.2's limits (Down 6, PgDn 8, Tab side by side 8, Tab overlapping 10, click 8, repaint 6) and the writes, logged; a 42-row stand-in costs the dispatches of a 21-row one, action by action, and the same writes (D21 stage E: the stand-in draws with one writeLines, one write per painted list); the drawing shape (a full frame 3 writes, a window's shadow 2 shade calls, a border-only redraw 3 writes)
| 011_ZeroFork | the three stages (drawing included: frames, shadows, locks, drawPart with every writer; stage 2c-3: a TWindow, the focus chain, message, a key through the dispatch, commands, the cursor, a modal view with a scripted event source, mouseEvent, endModal, cmClose; stage 2d: cmZoom, a keyboard drag, a mouse drag with the drain, the close icon, dragView) with `PATH=''`; the static scan of `fv.views.sh` (no fork construct) |
| 012_CallerState | one scene (tree, geometry, and the drawing: a frame with a Cyrillic title cut to its room, a shadowed window, locks, the border-only redraw, drawPart, screen cells read back) under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept; the constructor guard in the scene (not under the IFS of letters, where kklass's `.new` itself crashes); a second scene (stage 2c-3: windows whose names differ only in case, the focus chain, select, message, Tab, a click, commands, the cursor, two modal views, cmZoom and back, a keyboard and a mouse drag, the close icon, cmClose) under the same setups (`inherited` replaced by the built-in body under the IFS of letters, a kklass limit) |
| 013_Elision | every built-in virtual of the three stages (incl. `Draw`, `GetPalette` of TView / TGroup / TFrame) overridden with `inherited`: dispatch counts (0 / 2), results, user fields named like locals; the RESULT / rc rule both ways (also failing bodies, under `set -e`); overrides inside the painter; `kk.class --forget` + redefinition; a scene under `set -eu`, nocasematch and odd IFS; the unsupported func shapes (`return 0`, a failing last command) pinned as kklass behaves today; stage 2c-3: HandleEvent / SetState / Valid / Execute / EndModal of TView / TGroup and TWindow's HandleEvent / SetState / GetPalette / GetTitle / InitFrame / Close overridden with `inherited` (0 / 2 dispatches, the RESULT rule, through the dispatch, a select and execView); stage 2d: TFrame's HandleEvent and TWindow's SizeLimits / CalcBounds / Zoom (0 / 2, CalcBounds 6; through locate, cmZoom, an owner resize, a click on the close icon) |
| 014_Modal | execView (RESULT, inserted / removed, == a full repaint, sfModal and the top view while it runs; topView; the event record, Phase, Options, Current put back; EnterSelect), Valid refusals, endModal from a leaf, modal in modal, no HandleEvent for evNothing, the end of input (no Valid asked), the latch, the "save?" box at the end of input, a failing event source, a root's Execute (cmQuit), the owner-process rule in `$( )`, a dialog destroying itself, a modal cmClose (cmCancel posted), endModal without a modal view, mouseEvent (tracking, the mouse-up, the end of input), refusals; stage 2d: drags inside a modal view (cmResize's keyboard drag, a mouse drag by the frame), each step shown at once; a resize mid-modal is 2f (mid-drag: 017) |
| 015_Frame | TFrame's constructor; FV's look inactive / active / dragging, `☼` / `↕`, a bare frame in a plain group; a wide and a long title; small sizes; 3 writes full, 3 border-only (both sides one `fillColumns`), no dispatch; the string cache; through fv.video's VT model: the terminal shows the buffer, border-only == a full repaint (a window overlapping the ring in front); the covered parts of the ring left out (4 pieces, no repaint of the window in front); the cache across ASCII mode (initScreen with FV_ASCII); a frame class overriding Draw; stage 2d, the frame's mouse: the close icon's press tracking (one top-row write per change, cmClose posted on a release on it, nothing off it or at the end of input, the posted event closing the window), the zoom icon, a double click, an inactive frame (no icons: drags), the grow corner, a frame class with its own Draw, quiet for broadcasts |
| 016_Window | the constructor (FV's defaults, the frame from InitFrame, a bad number, the guard), an InitFrame override without a frame, GetTitle, the frame's title and number, the three palettes, cmClose (Valid no / yes, another window, without wfClose), cmSelectWindowNum through message, an unselectable window, Tab, unknown keys / commands; stage 2d: SizeLimits (MinWinSize, FV_MINWINSIZE_X/_Y), Zoom and back (ZoomRect, the zoom icon), a bad ZoomRect, cmZoom, CalcBounds (the ZoomRect follows an owner resize), cmResize |
| 017_Drag | stage 2f: a resize the event source handled itself (`__FV_VW_RESIZES`, evNothing answered) ends a keyboard and a mouse drag (the step loop's read and the drain's); stage 2d (+ critic round: Shift+Enter / Shift+Esc end a drag, icon tracking in a subshell and with the window destroyed by the source): the keyboard drag through `cmResize` (arrows, Shift + arrows, Ctrl ± 8, Home / End / PgUp / PgDn, Enter, Esc, a grow-only window), the limits (a column / row inside, `dmLimitLoY`, `dmLimitAll`, MinWinSize and the owner's size), `sfDragging` (border-only frame redraws: 3 writes in, 3 out), the mouse drag by the frame's top row and grow corner, motion coalescing (the drain's timeout 0, the last move wins, a key dropped, the mouse-up kept; P3 3a-2: the drain stops at an `evMouseAuto` as at `evNothing`), the end of input (keyboard as Esc, mouse where it is), a `cmResizeApp` ending a drag (clamped into the new extent, no undo), the event record put back, the owner-process rule in `$( )`, `dragView`'s refusals; the counts of one keyboard step, one mouse step and a zoom (logged) |
| 018_Names | reserved names (also under nocasematch), `_newReserved`, the constructor guard (a leaf, a group with subviews, through subclass constructors), the dialog loop and the anti-pattern, a constructor that skipped `inherited`, `VERBOSE_KKLASS=quiet`; every rc-2 refusal: one debug line under the switch, none without |
| 019_Palette | the app palette = CAppColor's 127 bytes through fv.video's default table; the resolution chain (root, `''`, TFrame in blue / cyan / gray windows), ErrorAttr; the cache (one GetPalette dispatch per view, RESULT kept), `resetPalette` V / all, delete / insert into another owner; refusals; D21: the answer split without a here-string (the first line, at blanks only, no globbing in a folder with files named like indices, the caller's `set -f` kept) |
| 020_Caches | D21: each structure cache's drop (DEX at insert / delete, FRL at insert / delete / putInFrontOf, OEX at insert: each test fails with its drop removed) and what is read live (hide / show, a State or Options field written by hand, the root's sfExposed, a lock, a bounds change); drawPart's fast path (the painter's rc and RESULT, rows with leading zeros, a redefined painter, the rc 127 of an unset one); the union cover (two windows side by side: the background not drawn, the shadow under the front window not shaded; a gap, a hidden window, a frameless group: drawn; each == a full repaint); drawView and the order redraw's shadow strips cut to the owner's clip (the status line in front of the desktop not repainted) |
| 021_Rows | D21 stage E: `writeLines` = one `writeLine` per index inside a drawPart (160 seeded random cases: narrow, Cyrillic, wide, emoji, combining and control text, empty rows, sparse arrays, missing / short / long / bad symbol strings; views past their owner and off the screen, negative X / Y, painted row ranges, rows with wide cells, ASCII mode, 40×12 and 200×50; rc and RESULT too); a Draw override with one writeLines == the per-row Draw; refusals rc 2 / RESULT `''` / nothing written (count, X / Y, outside a Draw, bad names, `__fv*`, `RESULT`, associative arrays: no key evaluated); a refused row (the others written), no rows (RESULT 0); under set -eu. 010's write counts follow the stand-in (one write per painted list); 011 and 012 call it too. P3 3a-1: `writeRows` = `fv.video._wrowsu` at the view's origin inside a drawPart (60 random cases), its refusals (count, X, W negative / not digits / empty, names, outside a Draw), a refused row, a wide pair cut at W |
| 025_Quiet | P3 3a-2, the broadcast table: fv.views' rows (TView, TFrame, TGroup none; TWindow `cmSelectWindowNum`) give the replaced rules, a QGRP entry counts as `''`; the table against a full dispatch (the table emptied) on seeded random trees of plain views, frames, windows, groups, built-in bodies of the test (a leaf reacting to cmA cmB, a group reacting to cmC) with user listeners (some handle a broadcast), a user group and a user override of a built-in body interleaved — through `message` and through the group's `HandleEvent`: the same reactions in order, each seeing its owner's `Phase`, the same handler / rc, never more handler calls; adding a row and removing it; an override always called, a subclass inheriting the body following its row; the Phase stamp of a skipped quiet subgroup (its owner and the subgroup hold the Phase a full dispatch leaves); the dialog scene: a Tab reaches a listening label-like leaf with both focus broadcasts, never a built-in leaf whose row lacks them |
| 026_WideEdge | P3 3a-2, the wide-row edge test: the rule on `fv.views._bands` (kept / banded / widened rectangles, two that meet, rows without wide cells, the C-locale and nested-Draw fallbacks); a static CJK scene under shadowed windows: every rectangle with its left edge at every column (widths 1 2 3 5 and to the edge) == a full repaint; a shadowed window and a plain leaf moved across CJK rows one column at a time, hide / show / reorders at every few columns, drawPart of each row with a window in front at every column, a frame border over CJK rows at every column: each == a full repaint; the narrowing (a drawPart on a CJK row no pair straddles leaves a window in front elsewhere on the row unpainted, no dispatch); seeded random CJK scenes (3 × 40 steps: moves, nudges, resizes, reorders, hide / show, drawView, drawPart, frame borders) == a full repaint after every step; drawPart through its checked path (a painter not seen, each row with a window in front at every column); the marking from fv.video's `__FV_VS_WNEW` (a row whose only pair a view in front hides by half at the first paint: a move uncovering it, a hide, the view sent behind a CJK leaf, the pair cut by the view's right edge) and seeded random scenes of one-pair rows with the views in front starting on a pair's half (4 × 30 steps, nothing marked by hand) == a full repaint; fv.video's VT model after moves over CJK rows |
