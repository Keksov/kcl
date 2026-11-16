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

**Status: P2 stage 2c-1** — the tree and the geometry. Drawing (palettes,
writers, the painter, shadows, the lock counters, `TFrame`) comes with stage
2c-2; events, focus, commands, modal views and the basic `TWindow` with
stage 2c-3. The sections below that belong to them say so.

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

A constructor of yours calls `inherited` first and checks that it worked:

```bash
TMyDlg.Create() { inherited; fv.views.isView "$this" || return 1; Title=$5; }
```

## Classes and fields

| class | fields (FV's public fields, flattened: `Origin.X` → `OriginX`) |
|---|---|
| `TView` | `Owner OriginX OriginY SizeX SizeY CursorX CursorY State Options EventMask GrowMode DragMode HelpCtx` |
| `TGroup : TView` | + `Current Phase EndState LockFlag` |

* `CLASS.new NAME AX AY BX BY` is FV's `Init(R)` with `R.Assign(AX, AY, BX, BY)`:
  corners, B exclusive (D1). The width is capped at FV's `MaxViewWidth`
  (1024, fv.video's widest row); a negative size is kept as given.
* `TView` defaults (FV `TView.Init`): `State` = `sfVisible`, `Options` 0,
  `EventMask` = `evMouseDown + evKeyDown + evCommand` (273), `GrowMode` 0,
  `DragMode` = `dmLimitLoY`, `HelpCtx` = `hcNoContext`, `Owner` and `Current` `''`.
* `TGroup` (FV `TGroup.Init`): `Options` += `ofSelectable + ofBuffered`,
  `EventMask` = `$FFFF`, `Phase` = `phFocused`, `EndState` `''`, `LockFlag` 0,
  an empty subview list.
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
  (from 2c-2) the drawing use the old place. Likewise **a `ChangeBounds`
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
| `EventMask` | `FV_EM_MOUSEDOWN MOUSEUP MOUSEMOVE MOUSEAUTO KEYDOWN MOUSEWHEEL COMMAND BROADCAST MOUSE KEYBOARD MESSAGE` (FPC drivers.inc values; `FV_EM_`, not `FV_EV_`: those are [fv.drivers' event](../fv.drivers/README.md#the-event)) |

Phases and commands are names (`phFocused`, `cmClose`), not numbers.

### Virtual methods (this stage)

| class | method | kind | FV |
|---|---|---|---|
| `TView` | `ChangeBounds AX AY BX BY` | proc | SetBounds, then the redraw (2c-2) |
| `TView` | `CalcBounds DX DY` | proc | the bounds after the owner grew by (DX, DY): by `GrowMode` (`gfGrowLoX/HiX/LoY/HiY` move the edge by the delta, `gfGrowRel` scales it: `I := (I*S + (S−D) shr 1) div (S−D)`, 1 when the old size is 0), the width capped at `MaxViewWidth`, the size clamped by `SizeLimits`. Answer: `FV_RECT_AX/_AY/_BX/_BY`. GrowMode 0 or no owner: the bounds as they are |
| `TView` | `SizeLimits` | proc | `FV_MIN_X/_Y` = 0, `FV_MAX_X/_Y` = the owner's size (FV `TGroup.ClipChilds` is true); without an owner `high(Sw_Integer)` (2147483647) |
| `TView` | `GetHelpCtx` | func | `hcDragging` while `sfDragging`, else `HelpCtx` |
| `TGroup` | `ChangeBounds AX AY BX BY` | proc | no size change: SetBounds + the redraw; else SetBounds, then each subview, front to back (FV `ForEach`), takes `CalcBounds DX DY` (`FV_RECT_*` holds its current bounds first: an override that sets nothing keeps it in place) and `ChangeBounds` with that rect (each subview still sees its old absolute place, so its redraw covers old ∪ new; one destroyed or removed meanwhile is skipped), then the subtree's cache and the group's redraw |
| `TGroup` | `GetHelpCtx` | func | `Current`'s `GetHelpCtx`, else TView's |
| `TView` | destructor `Done` (`V.delete`) | | V out of its owner, a group's subviews destroyed, V's entries freed |

FV's procedures with `var` parameters answer in globals, because a proc
leaves `RESULT` alone (below): `FV_RECT_AX FV_RECT_AY FV_RECT_BX FV_RECT_BY`
(a `TRect`), `FV_MIN_X FV_MIN_Y FV_MAX_X FV_MAX_Y` (SizeLimits' `Min`, `Max`),
`FV_POINT_X FV_POINT_Y` (a `TPoint`).

The aliases (D16) — `TView`: `MakeFirst PutInFrontOf Locate MoveTo GrowTo`;
`TGroup`: `Insert InsertBefore` — call the plain functions with `$this`.
There is **no `Delete` alias**: FV's `Delete` (remove a subview) would differ
from kklass's `.delete` (destroy) in the case of one letter. Removal is
`fv.views.delete G V`.

## Plain API (this stage)

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
* a `func` (FV's functions: `GetHelpCtx`; later `GetPalette Valid Execute
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

Tested in `013_Elision`, with every built-in of this stage overridden with
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

## Drawing — P2 stage 2c-2

Palettes and `getColor`, the drawing context, the writers, the painter,
shadows, `lockScreenUpdate` and `lock` / `unlock`, `drawView` / `drawPart` /
`redraw`, `show` / `hide`, the minimal `TFrame`. Until then nothing in this
unit draws: every place that will redraw calls the hook
`fv.views._changed WHY V G AX1 AY1 AX2 AY2` (a no-op today; `WHY` is
`insert`, `delete`, `order`, `bounds` or `move`, the rectangle absolute and
unclipped).

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
  not); `insert` does not yet pass `sfActive` to the view (2c-3); there is no
  `sfExposed` bookkeeping (the redraw model of 2c-2 does not need it).

Known kklass limits met by the tests (not this unit's): building a class or
calling `.new` under an `IFS` holding digits or letters fails (with letters
`.new` crashes bash), and `inherited` fails under an `IFS` holding letters.
The tests set such an `IFS` after the classes and instances exist.

## Tests

`bash kcl/fv.views/tests/tests.sh` — headless (no terminal, no `initVideo`).
`tests/fvw_testlib.sh` holds the headless screen, the buffer reader
(`fv.video.getRow`), the dispatch counter (shims around `kk._exec`,
`kk._call`, `kk._parent`, `kk._constructor_exec`), the fv.video write counter
and `fvw_budget`.

| file | what |
|---|---|
| 001_Contract | `bash -n`; the public API exists; loads, re-loads and the main path under `set -eu`; `kk.unit --forget` + re-source keeps the live tree; failing calls return under `set -e`; nothing on stdout; no stray globals or functions; the test lib itself (both counters keep rc and RESULT and unwrap, the buffer reader, `fvw_budget`) |
| 002_Tree | insert / insertBefore / delete / makeFirst / putInFrontOf, the navigation (rings and nil), Owner, Current per FV `ResetCurrent`, the sfSelected bits, refusals (rc, RESULT, unchanged tree), a cycle, `V.delete` of a group, names differing in case under nocasematch, the hook's calls |
| 003_Geometry | the constructors' corners and defaults, MaxViewWidth, getBounds / getExtent, the cache and the clip, centring, locate / moveTo / growTo with SizeLimits, an owner resize by every GrowMode flag (gfGrowRel, the S = D guard), CalcBounds / SizeLimits answers, makeLocal / makeGlobal / mouseInView, GetHelpCtx, bad numbers; a group moved and resized at once (each subview's old rect in its redraw hook), a CalcBounds override that sets nothing, a subview destroyed during the resize |
| 011_ZeroFork | the whole stage with `PATH=''`; the static scan of `fv.views.sh` (no fork construct) |
| 012_CallerState | one scene under nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS (digits, `-`, letters, empty), `set -eu` + pipefail, a C locale, all at once: same output, state kept; the constructor guard in the scene (not under the IFS of letters, where kklass's `.new` itself crashes) |
| 013_Elision | every built-in virtual of this stage overridden with `inherited`: dispatch counts (0 / 2), results, user fields named like locals; the RESULT / rc rule both ways (also failing bodies, under `set -e`); `kk.class --forget` + redefinition; a scene under `set -eu`, nocasematch and odd IFS; the unsupported func shapes (`return 0`, a failing last command) pinned as kklass behaves today |
| 018_Names | reserved names (also under nocasematch), `_newReserved`, the constructor guard (a leaf, a group with subviews, through subclass constructors), the dialog loop and the anti-pattern, a constructor that skipped `inherited`, `VERBOSE_KKLASS=quiet`; every rc-2 refusal: one debug line under the switch, none without |
