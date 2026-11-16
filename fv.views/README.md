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

**Status: P2 stage 2c-2** — the tree and the geometry (2c-1); palettes,
the drawing context and writers, the painter with shadows, both lock
counters and the minimal `TFrame` (2c-2). Events, focus, commands, modal
views and the basic `TWindow` come with stage 2c-3; the section that belongs
to them says so.

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
  class has one): TWindow's fields from stage 2c-3; any group works (without
  them: a bare frame).
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

FV's procedures with `var` parameters answer in globals, because a proc
leaves `RESULT` alone (below): `FV_RECT_AX FV_RECT_AY FV_RECT_BX FV_RECT_BY`
(a `TRect`), `FV_MIN_X FV_MIN_Y FV_MAX_X FV_MAX_Y` (SizeLimits' `Min`, `Max`),
`FV_POINT_X FV_POINT_Y` (a `TPoint`).

The aliases (D16) — `TView`: `MakeFirst PutInFrontOf Locate MoveTo GrowTo
DrawView Show Hide`; `TGroup`: `Insert InsertBefore Lock Unlock` — call the
plain functions with `$this`.
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
one line calling it, so `inherited` from your override reaches it. Wherever
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

**One RESULT / rc rule for both paths**, for the body forms that are
supported in an override:

* a `proc` leaves the caller's `RESULT`; its rc is the body's;
* a `func` (FV's functions: `GetHelpCtx GetPalette`; later `Valid Execute
  GetTitle Hint GetEvent`) **answers by setting `RESULT` and ending without
  an explicit `return`**;
* a `func` **fails with an explicit `return N` (N ≠ 0)**, which leaves the
  caller's `RESULT`;
* **not supported in a `func` override**: an explicit `return 0` (kklass
  drops the `RESULT`: the caller's stays — so `TGroup.GetHelpCtx` through such
  a Current answers the group's own) and a failing last command without
  `return` (kklass drops the rc: rc 0, the `RESULT` kept). Both come from
  kklass's `kk._return` trailer, which runs only when the body ends without
  `return`; `013_Elision` pins them as they behave today.

Every built-in body follows the supported forms; the plain path answers for
a `func` with rc 0 and leaves the caller's `RESULT` for a failing `func` and
for every `proc`.

Tested in `013_Elision`, with every built-in of stages 2c-1 and 2c-2 overridden with
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
| `fv.views.drawPart V FN Y1 Y2 [ARGS]` | — (rule 4) | partial redraw of a **leaf** without a dispatch: your plain painter function runs as `FN V ARGS` with V's drawing context, its writes clipped to V's local rows `Y1 <= y < Y2`; then the views in front of V that overlap those rows are painted again, and the terminal is updated. A group is refused (rc 2, one debug line): a painter of a group would write over its own subviews (redraw a group with `drawView`). Nested inside a Draw, the part under a covering view in that Draw is left out, so FN may run once per remaining piece (below). rc = FN's (the last non-zero; 0 when V cannot be drawn now: FN does not run). For a list's cursor move (P3 `FocusItem`) |
| `fv.views.show V` / `hide V` | `Show` / `Hide` | the `sfVisible` bit, then (V in a group) FV's DrawShow (V drawn with its shadow) / DrawHide (its area, shadow included, repainted from below), then the owner's `ResetCurrent` for a selectable V. A no-op when the bit already is so. (The virtual-aware `setState` is stage 2c-3) |
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
  TWindow's blue / cyan / gray from stage 2c-3: `8 … 15`, `16 … 23`, `24 …
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
* **The border-only redraw** (`fv.views._frameBorder F`, which stage 2c-3
  calls when `sfActive` or `sfDragging` changes) writes the top and bottom
  rows and the two side columns (4 writes) and never touches the interior.
  The parts of the ring that a covering view in front of the frame (or of an
  owner) holds are left out first, so a window in front is neither
  overwritten nor painted again (one more write per extra piece of a ring
  cut by it); the views in front over what was written (scroll bars on the
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
  differ from a full repaint, so the screen rows that hold (or held) wide
  cells are repainted across the whole width (read from fv.video's per-row
  flag `__FV_VS_WIDE`, a friend read). Rows without wide cells cost nothing
  extra.
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
  (FV's three window palettes give both states the same background there).
* **Not in this stage**: FV's frame junctions with `ofFramed` subviews;
  `sfExposed` on the views below the root (only the root's bit is read).

## Events, focus, commands, modal views — P2 stage 2c-3

`HandleEvent` and the phases, the focus chain, `select` / `setState`,
command sets, `execView` / `endModal`, the basic `TWindow`. Today
`fv.views._setCurrent` only moves `Current` and the `sfSelected` bits.

## Contract (kcl README §1) and deviations

§1; deviations:

* **instance classes with FV field names**, and fields of other instances
  read and written directly under the kklass friend contract;
* **loud refusals**: re-creating a live view, a reserved name and a
  constructor that skipped `inherited` print one `Error:` line on stderr (not
  only under `VERBOSE_KKLASS=debug`; `quiet` silences them) — a silent rc
  would leave a corrupt tree behind in a loop that ignores it;
* the `var` parameters of FV's geometry answer in the `FV_RECT_*`,
  `FV_POINT_*`, `FV_MIN_*` / `FV_MAX_*` globals (also `RESULT` for the
  getters);
* from Free Vision: `makeLocal` uses the cached absolute origin (FPC's
  `MakeLocal` stops its owner walk at a negative coordinate; this one does
  not); `insert` does not yet pass `sfActive` to the view (2c-3); only the
  root's `sfExposed` is read (FV keeps the bit on every view of the
  application's tree); the writers do not update the terminal (the drawing
  entry does, once); `V.Draw` outside the painter draws nothing;
  `unlockScreenUpdate` updates the terminal at 0 (FV leaves that to a
  separate `DrawScreenBuf`); the redraw model above.

Known kklass limits met by the tests (not this unit's): building a class or
calling `.new` under an `IFS` holding digits or letters fails (with letters
`.new` crashes bash), and `inherited` fails under an `IFS` holding letters.
The tests set such an `IFS` after the classes and instances exist.

## Tests

`bash kcl/fv.views/tests/tests.sh` — headless (no terminal, no `initVideo`).
`tests/fvw_testlib.sh` holds the headless screen, the buffer reader
(`fv.video.getRow`), the dispatch counter (shims around `kk._exec`,
`kk._call`, `kk._parent`, `kk._constructor_exec`), the fv.video write counter,
`fvw_budget`, and the desktop-like scene of the drawing tests (a background,
two framed windows with shadows and a list stand-in each: `TTWin`, `TTList`,
`fvw_scene`) and `fvw_full` (the screen against a full repaint from
garbage). Each test file's stderr is captured: anything on it fails one test.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the public API exists; loads, re-loads and the main path (drawing included) under `set -eu`; `kk.unit --forget` + re-source keeps the live tree; failing calls return under `set -e`; nothing on stdout; no stray globals or functions; the test lib itself (both counters keep rc and RESULT and unwrap, the buffer reader, `fvw_budget`) |
| 002_Tree | insert / insertBefore / delete / makeFirst / putInFrontOf, the navigation (rings and nil), Owner, Current per FV `ResetCurrent`, the sfSelected bits, refusals (rc, RESULT, unchanged tree), a cycle, `V.delete` of a group, names differing in case under nocasematch, the hook's calls |
| 003_Geometry | the constructors' corners and defaults, MaxViewWidth, getBounds / getExtent, the cache and the clip, centring, locate / moveTo / growTo with SizeLimits, an owner resize by every GrowMode flag (gfGrowRel, the S = D guard), CalcBounds / SizeLimits answers, makeLocal / makeGlobal / mouseInView, GetHelpCtx, bad numbers; a group moved and resized at once (each subview's old rect in its redraw hook), a CalcBounds override that sets nothing, a subview destroyed during the resize |
| 004_Draw | the writers in local coordinates (palette index → symbol, ErrorAttr outside, `writeLine`'s repeat count), their answers and refusals (outside a Draw, bad arguments); the context and `FV_CLIP_*` inside a Draw; the owner's clip; the caller's clip and RESULT kept; a `drawView` nested inside a Draw (the outer context and clip intact); TView.Draw; a group override that decorates after `inherited Draw`; nothing drawn when hidden / in a hidden group / without an exposed root; `V.Draw` outside the painter; `getColor`; `drawPart` (clipped rows, the front view over them, no dispatch, rc, refusals); `redraw`'s forced frame, also deferred while held; re-entrancy (a Draw redrawing a view behind it with drawView + drawPart: once, no recursion, == a full repaint, also after a move; a list redrawing scroll bars beside and behind it); a Draw ending non-zero under `set -e` (insert, drawView, moveTo, unlock); drawPart on a group refused |
| 005_Overlap | the desktop-like scene: painter's order and FV's cells, 4 dispatches for the first paint, shadows (2 × 1, characters kept, over a sibling, clipped by the owner); move, resize, a group resize, makeFirst / putInFrontOf, a reorder without overlap, delete / insert, hide / show: each leaves exactly a full repaint's screen and draws each list at most once; the covering skip (framed group and leaf cover; frameless group, hidden frame, shadow do not); a frameless group's subview hidden / shown / moved / deleted (repainted from below the group); wide characters at a repaint edge; randomized wide-character scenes (seeded, 2 × 30 operations: every redraw == a full repaint) |
| 006_Lock | lockScreenUpdate (nested, the update held, sent once, RESULT kept); lock / unlock: draws and the hooks' redraws held, redrawn once at 0 (also FV's "Lock; change fields; Unlock"), nested counts, an inner group inside a locked owner, both counters together, refusals, the aliases, a group destroyed while locked; destroying a locked window, or one holding a locked group, sends the removal at once |
| 011_ZeroFork | both stages (drawing included: frames, shadows, locks, drawPart with every writer) with `PATH=''`; the static scan of `fv.views.sh` (no fork construct) |
| 012_CallerState | one scene (tree, geometry, and the drawing: a frame with a Cyrillic title cut to its room, a shadowed window, locks, the border-only redraw, drawPart, screen cells read back) under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept; the constructor guard in the scene (not under the IFS of letters, where kklass's `.new` itself crashes) |
| 013_Elision | every built-in virtual of both stages (incl. `Draw`, `GetPalette` of TView / TGroup / TFrame) overridden with `inherited`: dispatch counts (0 / 2), results, user fields named like locals; the RESULT / rc rule both ways (also failing bodies, under `set -e`); overrides inside the painter; `kk.class --forget` + redefinition; a scene under `set -eu`, nocasematch and odd IFS; the unsupported func shapes (`return 0`, a failing last command) pinned as kklass behaves today |
| 015_Frame | TFrame's constructor; FV's look inactive / active / dragging, `☼` / `↕`, a bare frame in a plain group; a wide and a long title; small sizes; 3 writes full, 4 border-only, no dispatch; the string cache; through fv.video's VT model: the terminal shows the buffer, border-only == a full repaint (a window overlapping the ring in front); the covered parts of the ring left out (4 pieces, no repaint of the window in front); the cache across ASCII mode (initScreen with FV_ASCII); a frame class overriding Draw |
| 019_Palette | the app palette = CAppColor's 127 bytes through fv.video's default table; the resolution chain (root, `''`, TFrame in blue / cyan / gray windows), ErrorAttr; the cache (one GetPalette dispatch per view, RESULT kept), `resetPalette` V / all, delete / insert into another owner; refusals |
| 018_Names | reserved names (also under nocasematch), `_newReserved`, the constructor guard (a leaf, a group with subviews, through subclass constructors), the dialog loop and the anti-pattern, a constructor that skipped `inherited`, `VERBOSE_KKLASS=quiet`; every rc-2 refusal: one debug line under the switch, none without |
