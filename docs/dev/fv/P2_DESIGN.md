# fv P2 Stage 0: design of the views core and the application (L2)

2026-11-16, **revision 2** (after the supervisor review and the independent critic; the
change list is §R). Design only: nothing in any repo changed.

Inputs:
* PLAN.md (§1 D1–D15, §2.2 rules, §4 P2/P3, §5, §6, §7) and fv_ledger.json (F-1, L-2, T-2);
* the READMEs of fv.video, fv.drivers, fv.keyboard, fv.mouse and fv.unicode;
* the kklass book (Pascal DSL, dispatch, isolation, nameref trap) and PERF_PLAN (round K);
* the spike (`scratchpad/tui_spike/`) and tools/bench `fvcases.sh`;
* the Free Vision sources (`views.inc`, `app.inc`, `menus.inc`).

To check the numbers I built a **scratch prototype** of the model (`p2/proto.sh` +
`p2/proto_el.sh`): a real kklass view tree on the real fv.video, headless, whose frame renders
correctly through fv.video's VT model (`p2/view_frame.sh`). All probes are in `p2/`; the critic's
probes are in `p2/critic/`. Numbers are in §3 and Appendix A.

---

## R. Revision 2: what changed, per review finding

| # | Finding | Change (section) |
|---|---|---|
| 1 | FV `Unlock` redraws the locked group; terminal-update holding is FV's `LockScreenUpdate` | Two counters: `lockScreenUpdate`/`unlockScreenUpdate` (flush) and `lock`/`unlock` with FV's meaning (each marked group redrawn once at 0). Internal sequences (select, putInFrontOf, changeBounds) redraw minimally. FV-faithful internals measured: Tab 25.3 ms against 12.0 ms. Owner question **Q2**. (§1.7, §7) |
| 2 | Drawing context and fv.video clip are unsaved globals | The paint step saves and restores `FV_DRAW_*`, the restriction and the fv.video clip (2a `getClip`); a nested `drawView` inside a Draw is safe; test in 004. (§1.5, §1.7) |
| 3 | `FV_EV_*` shared across a nested `execView` | `execView` (and every inner loop: mouseEvent, dragView, status press tracking) saves and restores `FV_EV_*` and the owner's `Phase`. (§2.2) |
| 4 | EOF spin through `Valid` opening a box | EOF **latches**: loops end without asking `Valid`; a new `execView` returns `cmCancel` at once. (§2.1) |
| 5 | The elision cache gains nothing and goes stale; RESULT differs between paths | **No cache**: the owner table is read on every elided call (~20 µs). One RESULT/rc rule for both paths, tested in 013. (§1.4) |
| 6 | Four kklass internals used | The kklass friend contract: the four internals named, the set -u rules (`${d[X]-}`), a guard against a constructor that skips `inherited`. Owner question **Q4**: document plus pinning test, or helper functions. (§1.11, §7) |
| 7 | Shadows (FV `TWindow.Init` sets `sfShadow`) | Shadows **in P2**: a `fv.video.shadeRect` primitive (attribute-only) in 2a, ~0.35 ms per window measured by emulation; clip, union rect and covered test widened by the shadow. (§1.10, §6) |
| 8 | kklass re-creates a live instance silently | Reserved names for framework-made views (`${owner}__fv<role>`) and a constructor guard (live-name check with tree repair). (§1.6) |
| 9 | CAppColor 127 entries vs 62 symbols | The palette model: app palette = 127-entry symbol string by fv.video's first-appearance rule; `setAppPalette` allocates a symbol for a changed entry; view palettes through GetPalette elision. (§1.9) |
| 10 | Painter details | Covered skip only by views that paint their whole rect; `drawPart` takes the written rows' rectangle; a resize ends a drag (accepted, clamped); skipping HandleEvent on `evNothing` stated as a deviation. (§1.7, §2.1, §2.2) |
| 11 | EventMask facts reversed | FV defaults now: TView `evMouseDown+evKeyDown+evCommand`, TGroup `$FFFF`, TFrame / TStatusLine / scrollers add `evBroadcast` (scrollers also the wheel). Budget re-checked: the focus broadcasts cost 0 dispatches in the P2 scene. (§1.2, §1.8, §3.2) |
| 12 | Stage split | A minimal TFrame draw moves into 2c-2 and basic TWindow into 2c-3; 2d keeps drag, zoom, icons and mouse; 2b becomes docs plus a pinning test (if Q4 = a); the test lib counts fv.video writes (a border redraw ≤ 4 writes). (§6) |
| 13 | Budget not modelled inside a Run frame | Re-measured with getEvent inside an app method frame: Down 3.1 ms, **PgDn 9.3 ms (over 8)**. What can bring PgDn to 8 ms, and why P2 alone does not. (§3.3) |
| 14 | Subshell guard | Compares `BASHPID` with the owner recorded at Init, as fv.video does. (§2.2) |

Owner questions now: **Q1** the non-virtual API spelling; **Q2** Lock/redraw semantics; **Q3** the
first-paint metric; **Q4** the kklass friend contract. The old Q2 (bounds) is dropped: D1
decides FV corners (§1.6).

---

## 0. Summary of the decisions

| # | Decision | Why |
|---|---|---|
| P2-1 | Views are kklass classes (Pascal DSL). FV fields are **kklass vars** with FV names (`OriginX`, `SizeY`, `State`, …). **Derived state** (absolute origin, clip, z-order, resolved palette, frame strings) lives in private arrays keyed by the view name. | FV code reads `Size.X`/`State` inside methods; a field costs ~2.1 µs bind + ~1.4 µs shadow per nested call (§1.2). |
| P2-2 | **Virtual elision**: each built-in virtual has a plain implementation. The framework calls it directly unless the view's class overrides the method; it dispatches through kklass only for user code. No cache: the decision costs ~20 µs and is never stale. One RESULT/rc rule for both paths. | Down 6 → 3 dispatches, repaint 10 → 2, Tab 6 → 3 (each saved dispatch ~0.2 ms). |
| P2-3 | **No call per row or cell; no per-character frame drawing.** TFrame takes 3 writes for a full draw and 4 for a border-only redraw; the test lib counts fv.video writes to keep it so. | F-1: 84 one-character side writes cost 5.7 ms. |
| P2-4 | **Painter's algorithm with an overlap test** (no FV z-order clip walk). Shadows extend the rectangles. Move/hide/close redraw the union rectangle. A view entirely covered by a front view that paints its whole rect is skipped. | Rule 3; the tests are array reads. |
| P2-5 | **Cached absolute bounds**; mouse routing is a front-to-back hit test per group (D8). | No owner-chain walk per write or click. |
| P2-6 | **Two counters, as in FV**: `lockScreenUpdate` holds the terminal flush; `lock`/`unlock` keep FV's meaning (each locked group that got marked is redrawn once when its counter reaches 0). The framework's own focus/z-order/bounds changes redraw only what changed (Q2). | FV-faithful internals redraw the desktop on every window switch (Tab 25 ms vs 12 ms). |
| P2-7 | **Events stay FV**: names in `FV_EV_*` (P0); focused events through preprocess → Current → postprocess; positional events to the front-most view under the pointer; broadcasts to all subviews, filtered by FV's default `EventMask` without a call. **Commands are names**; command sets are a name set. | D1 and fv.drivers. |
| P2-8 | **Modal = nested loop, as in FV**. One app-level `getEvent` handles `cmResizeApp` at once (FPC "system events handled right away"). Each loop saves and restores the event globals. EOF latches and ends every loop. `Run`/`ExecView` refuse to run in a subshell (BASHPID). | §2.2. |
| P2-9 | **fv.video additions (2a)**: `writeBuf … [H]` (FV WriteLine with H rows), `shadeRect`, `getRow`, `getClip`, a cheaper entry/argument check, the default palette's SGR cached per process. | A frame body becomes one write; shadows; validation is 27 µs of a ~90 µs short write; initScreen −2–3 ms. |
| P2-10 | **The call-budget test counts dispatches with a test-side shim** around `kk._exec`, `kk._call`, `kk._parent` and `kk._constructor_exec`, and counts fv.video writes with a second shim. | `p2/probe_count.sh`: exact, rc/RESULT/`set -e` unchanged, removable. |
| P2-11 | **Reserved names** `${owner}__fv<role>` for framework-made views; a constructor guard against re-creating a live view. | kklass re-creates a live instance silently (`critic/c_recreate.sh`). |
| P2-12 | **Palette model**: the 127-entry app palette as a symbol string; `setAppPalette` per entry; view palettes resolved once per view. | fv.video README hands this to P2. |

---

## 1. Object model

### 1.1 Classes and units (D7)

| unit | classes (kklass) | FV origin |
|---|---|---|
| `fv.views` | `TView`, `TGroup`, `TFrame`, `TWindow` (P3: `TScrollBar`, `TListViewer`) | views.pas |
| `fv.menus` | `TStatusLine` (P3/O3: `TMenuBar`, `TMenuBox`) | menus.pas |
| `fv.app` | `TBackground`, `TDesktop`, `TProgram`, `TApplication` | app.pas |

Inheritance follows FV: `TView ← TGroup ← TWindow`; `TView ← TFrame`, `TBackground`,
`TStatusLine`; `TGroup ← TDesktop`, `TProgram ← TApplication`.

### 1.2 Fields, derived state, constants

**Fields** are FV's public fields, flattened (`Origin.X` → `OriginX`); P2 adds none FV lacks:

| class | own fields | total |
|---|---|---|
| TView | `Owner OriginX OriginY SizeX SizeY CursorX CursorY State Options EventMask GrowMode DragMode HelpCtx` | 13 |
| TGroup | `Current Phase EndState LockFlag` | 17 |
| TWindow | `Flags Title Number Palette Frame ZoomRect` (ZoomRect = `"x1 y1 x2 y2"`) | 23 |
| TFrame | `FrameMode` | 14 |
| TBackground | `Pattern` | 14 |
| TDesktop | `Background TileColumnsFirst` | 19 |
| TStatusLine | `Hint` (items in per-instance arrays) | 14 |

FV's `Next`/`Last`/`First` become the owner's subview array; `Buffer` is dropped (spike);
`Clip` is derived.

**Derived state** in private arrays keyed by the view name (no bind cost):

| array | content | recomputed |
|---|---|---|
| `__FV_VW_AX/AY[v]` | absolute origin | Insert, move/resize (subtree), app resize |
| `__FV_VW_C1..C4[v]` | absolute clip = own rect ∩ owner's clip | same |
| `${g}_views` (per group) | subviews **back to front** (the last = FV's `First`, the front) | Insert/Delete/MakeFirst/PutInFrontOf |
| `__FV_VW_PAL[v]` | the view's palette resolved to symbols (§1.9) | Insert, owner change, `Palette` change, `setAppPalette` |
| `__FV_VW_FT/FB/FV[f]` | a frame's top row, bottom row and side char for its state | state/size/title change |
| `__FV_VW_LIVE[v]` | 1 from construction to destruction (§1.6) | constructor/destructor |

`${g}_views` follows kcl §1.9 (instance-prefixed, freed by the destructor); the others lose their
entries in the destructor.

**Constants**: readonly once per process (kcl §1.10 rule 7), FV values, unit prefix:
`FV_SF_VISIBLE 0x1 … FV_SF_EXPOSED 0x800`, `FV_OF_SELECTABLE 0x1 … FV_OF_CENTERED 0x300`,
`FV_GF_*`, `FV_DM_*`, `FV_WF_*`. Event bits for `EventMask` use FV values (`evMouseDown 0x1`,
`evKeyDown 0x10`, `evCommand 0x100`, `evBroadcast 0x200`, the wheel's FPC bit), mapped from the
event name by one associative lookup. Phases and commands are **names** (`phFocused`,
`cmClose`); `EndState` is a command name, `''` = none.

**EventMask defaults are FV's** (finding 11):

| class | default `EventMask` |
|---|---|
| TView | `evMouseDown + evKeyDown + evCommand` (views.inc ~1003) |
| TGroup | `$FFFF` |
| TFrame, TStatusLine, TMenuView | TView's + `evBroadcast` |
| P3 scrollers/lists | TView's + `evBroadcast + evMouseWheel` |

FV's globals `Application`, `Desktop`, `StatusLine`, `MenuBar` become `FV_APP`, `FV_DESKTOP`,
`FV_STATUSLINE`, `FV_MENUBAR` (instance names, set by `fv.app`).

**Why fields, not a view table** (measured, Git-bash; MSYS2 within 5%):

| call | µs |
|---|---|
| `obj.M`, top level, 1 / 15 / 30 fields | 100 / 125 / 163 |
| nested call into another class, 30 → 25 fields (inner part) | ~225 |
| `$this.M` with 30 fields (inner part) | ~205 |
| `inherited` with 25 fields (inner part) | ~207 |
| field read via `local -n d=${v}_data`, 1 / 5 fields | 8 / 12–16 |

A field costs ~3.5 µs per nested call. With elision 2–4 dispatches happen per key, so FV's ~20
fields cost ~0.2 ms per key. That does not justify a non-FV API (`$SizeX` → `${FV_VX[$this]}`).
The framework's loops never call; they read fields through `${v}_data` under the friend
contract (§1.11).

### 1.3 Methods: virtual (kklass) and non-virtual (plain)

* **Virtual FV methods are kklass methods**, overridden with `override proc` and `inherited`:
  * TView: `Draw HandleEvent SetState ChangeBounds CalcBounds SizeLimits GetPalette GetHelpCtx Valid Execute EndModal Awaken`, `destructor Done`;
  * TGroup overrides `Draw HandleEvent SetState ChangeBounds Execute EndModal Valid GetHelpCtx`;
  * TFrame: `Draw HandleEvent SetState GetPalette`;
  * TWindow: `HandleEvent SetState SizeLimits GetPalette GetTitle InitFrame Zoom Close`;
  * TBackground: `Draw GetPalette`; TDesktop: `HandleEvent InitBackground`;
  * TProgram: `Run HandleEvent GetEvent PutEvent Idle InitScreen InitStatusLine InitMenuBar InitDesktop GetPalette`;
  * TApplication: `HandleEvent GetTileRect`; TStatusLine: `Draw HandleEvent Hint GetPalette`.
* **Non-virtual FV methods are plain functions `fv.views.*`**, the view name first
  (`fv.views.drawView "$this"`): the tree (`insert delete insertBefore makeFirst putInFrontOf
  first next prev`), focus and state (`select focus selectNext focusNext show hide`, the
  virtual-aware `setState`), geometry (`locate moveTo growTo getBounds getExtent makeLocal
  makeGlobal mouseInView`), drawing (`drawView drawPart redraw lock unlock lockScreenUpdate
  unlockScreenUpdate`), events (`message mouseEvent dragView execView endModal`), colour and
  cursor (`getColor setCursor showCursor hideCursor normalCursor blockCursor`), commands
  (`enableCommands disableCommands commandEnabled getCommands setCommands`), the writers (§1.5).
  Q1 asks whether thin method aliases are added for the user-facing ones.

All plain functions are fork-free and `set -eu`-clean, use `__fvw_` locals, and read fields only
through `${v}_data` with `${d[X]-}` (a field never assigned is unset). They are often called from
a member body, whose field namerefs are visible through bash's dynamic scope (kklass book,
isolation rule).

### 1.4 Virtual elision (P2-2)

Every built-in virtual has its body in a plain function registered in `__FV_VW_IMPL`
(`[TFrame.Draw]=fv.views._frameDraw`). The kklass method body is one line calling it
(`TFrame.Draw() { fv.views._frameDraw "$this"; }`), so `inherited` from a user override works.
Wherever the framework would dispatch, it calls `fv.views._virt V METHOD ARGS`:

```bash
fv.views._virt() {                    # V METHOD ARGS...
    local __fvw_c=${1}_class __fvw_f __fvw_r=$RESULT __fvw_s
    __fvw_c=${!__fvw_c}
    __fvw_f=${__fvw_c}_class_method_owner[$2]        # kklass friend table (§1.11)
    __fvw_f=${__FV_VW_IMPL[${!__fvw_f-}.$2]-}
    if [[ -z $__fvw_f ]]; then "$1.$2" "${@:3}"; return; fi   # user code: a real dispatch
    "$__fvw_f" "$1" "${@:3}"; __fvw_s=$?
    [[ -n ${__FV_VW_FUNC[$2]-} ]] || RESULT=$__fvw_r          # a proc leaves the caller's RESULT
    return "$__fvw_s"
}
```

* **No cache** (finding 5). The critic measured cached 20–21 µs against uncached 19–21 µs
  (`critic/c_virt.sh`), and the cache went stale after `kk.class --forget` + a redefinition with an
  override (the user's Draw was skipped). Reading the owner table each time is as fast and always
  right, also after `defineMethod` or a re-source.
* **One RESULT/rc rule for both paths**: kklass restores the caller's RESULT after a `proc` and
  passes a `func`'s RESULT (`critic/c_result.sh`). `_virt` does the same for the plain path: the
  virtuals that FV declares as functions (`GetPalette GetHelpCtx Valid Execute GetTitle Hint
  GetEvent`, listed in `__FV_VW_FUNC`) answer in RESULT on both paths; all others leave the
  caller's RESULT unchanged on both paths. The rc is the body's rc on both. 013_Elision checks
  each virtual both ways (overridden and not).
* The owner table answers for inherited methods too (`p2/probe_owner.sh`: TWindow.Draw → TGroup,
  TMyApp.HandleEvent → TMyApp).

### 1.5 Drawing without a call per row or cell (P2-3)

* **Drawing context**: before a `Draw`, the paint step sets globals (no call): `FV_DRAW_VIEW`,
  `FV_DRAW_X`, `FV_DRAW_Y` (absolute origin), `FV_DRAW_PAL` (resolved palette), `FV_CLIP_Y1/Y2`,
  and the fv.video clip = the view's clip ∩ the current restriction. **The paint step saves all of
  them and the fv.video clip (2a `getClip`) and restores them after the Draw** (finding 2), so a
  `drawView`/`drawPart` nested inside a Draw (a group override that calls `inherited` and then
  decorates; a scroll bar redrawn during a list's Draw) leaves the outer Draw's context intact.
  004_Draw has that case.
* **The writers** are plain functions in view-local coordinates, one fv.video call each:
  `fv.views.writeStr X Y TEXT COLOR` (FV `WriteStr`; COLOR = palette index →
  `${FV_DRAW_PAL:COLOR-1:1}`), `writeChar X Y CH COLOR [COUNT]`, `writeCStr X Y TEXT C1 C2`,
  `writeLine X Y H TEXT ATTRS` (FV `WriteLine(X,Y,W,H,Buf)`: one row repeated on H rows through the
  2a repeat count; ATTRS are resolved symbols, as FV's `TDrawBuffer` holds resolved attributes),
  `fill X Y W H CH COLOR`, `getColor I` (RESULT = symbol). `TDrawBuffer` move helpers come with P3.
* **Partial redraw** (rule 4): `fv.views.drawPart V FN Y1 Y2 ARGS` runs the plain painter FN with
  V's drawing context, then redraws the front views that overlap **the written rows' rectangle**
  (local rows Y1..Y2 of V; finding 10), then flushes. No dispatch. P3's `FocusItem` uses it.
* **TFrame** (FV look and CFrame colours: double line active, single inactive, title centred,
  `[■]`, `[↑]`, a number, the grow corner):
  * full draw = top row (title and icons composed: 1 write) + body `║ … ║` on H−2 rows (1 write with
    the repeat count) + bottom row (1 write);
  * border-only redraw (sfActive/sfDragging change) = top + bottom + the two side columns (4
    writes, or 3 with the optional two-column fill). The interior is never touched (FV relies on
    z-clipping there; we have none). Front subviews that overlap the border ring (P3 scroll bars
    sit on it) are redrawn after it;
  * the strings are cached per frame and state.
* **TBackground**: one `fill`. **TStatusLine**: one composed `writeLine`. TWindow and other
  groups draw nothing of their own; the frame covers a window.

### 1.6 Tree, names, constructor guard

* **Bounds are FV corners** (D1): `TWindow.new win1 10 5 50 20 'Files' 1` is FV's
  `R.Assign(10, 5, 50, 20)`, 40×15; `getBounds`, `locate`, `changeBounds` use corners. The writers
  keep X Y (FV's `WriteStr(X, Y, …)` does too).
* `fv.views.insert G V` (FV `Insert`): V to the front of `${g}_views`, `Owner` set, centring by
  `ofCenterX/Y`, the subtree's bounds cache, its palette resolved, a selectable V becomes
  `Current`, a visible V drawn (unless drawing is held).
* `fv.views.delete G V`: hides V (redraws the union under it, shadow included), removes it, resets
  `Current`. `makeFirst`/`putInFrontOf` move V and redraw only what became exposed (§1.7).
* `V.delete` (FV `Done`) deletes a group's subviews first, removes V from its owner, frees its
  entries and arrays.
* **Framework-made views get reserved names** (finding 8): `${owner}__fv<role>`, for example
  `win1__fvframe`, `app__fvdesktop`, `app__fvstatus`, `app__fvdesktop__fvbg`. User view names must
  not contain `__fv` (the constructor refuses them, rc 2).
* **Constructor guard**: kklass's `.new` over a live name re-creates the instance without running
  its destructor (`critic/c_recreate.sh`). TView's constructor checks `__FV_VW_LIVE[$this]`:
  * if set, it repairs the tree first: it removes the stale name from its owner's array, deletes
    the old subviews (still listed in `${name}_views`) and frees the private entries;
  * it then prints one `Error:` line and returns 1.

  A dialog re-created in a loop therefore fails loudly instead of corrupting the tree. The
  README's pattern is `TDialog.new dlg …; fv.views.execView "$FV_DESKTOP" dlg; dlg.delete`.
  The guard also catches a user constructor that skipped `inherited`: Insert refuses a view whose
  `State` is unset (§1.11).

### 1.7 Redraw: back to front, overlap test, locks (P2-4, P2-6)

```
paint(V, R):  save context + clip; clip := C(V) ∩ R; V's Draw (via _virt); a group paints its
              subviews back to front, each with clip = C(k) ∩ parent's, skipping a child whose
              clip ∩ R is empty or that a COVERING front sibling hides entirely; after a child
              with sfShadow, shadeRect on its shadow cells ∩ parent's clip; restore context + clip
drawView V:   [skip if V or an owner is hidden, or drawing is held]
              paint(V, screen); over(V, S(V)); resetCursor; flush unless lockScreenUpdate > 0
over(V, rect): each owner level: every visible sibling in front of the path node whose
              shadow-extended rect meets rect -> paint(sibling, overlap)
drawUnder(G, rect): paint(G's subviews meeting rect, back to front, R = rect); over(G, rect)
```

S(V) is V's rect, extended by its shadow when `sfShadow` is set (FV `ShadowSize` 2×1).

* **Covering** (finding 10): only a view that paints its whole rect can hide a sibling. That means
  a leaf view (FV: "Draw must cover the whole view") or a group with a frame (TWindow). A frameless
  TGroup is not covering, and a shadow never covers.
* **Move or resize** of V from A to B = `drawUnder(owner, S(A) ∪ S(B))`: one pass in z-order.
* **MakeFirst / Select** of a window first tests whether a visible sibling in front overlapped
  it. If one did, the whole window is redrawn; otherwise only its frame border changes look.
* **Two counters** (finding 1, FV's model):
  * `fv.views.lockScreenUpdate` / `unlockScreenUpdate` (FV `LockScreenUpdate`) hold the terminal
    flush. `drawView` flushes only at 0.
  * `fv.views.lock G` / `unlock G` (FV `TGroup.Lock/Unlock`, the `LockFlag` field) keep FV's
    meaning: while G is locked, a `drawView` of G or of a view inside it is not drawn; G is marked
    instead. At the outermost `unlock`, each marked group is redrawn once (a marked group inside
    another marked group is covered by the outer one). It also holds the flush.
  * The framework's own sequences (setCurrent/select, putInFrontOf, changeBounds, show/hide) do
    **not** go through `lock`/`unlock`. They use `lockScreenUpdate` and redraw only what changed:
    the border of the old and new window, the exposed part, the union rectangle. This is a
    deviation from FV, where `TGroup.SetCurrent` locks the desktop and its `Unlock` redraws the
    whole desktop on every window switch. The pixels are the same; the difference is speed and how
    often user Draws run. Measured: Tab 12.0 ms with minimal redraws, **25.3 ms** with FV's
    desktop redraw (`p2/proto_lockfv.sh`). Q2 asks the owner.
* **Bulk layout** (tile, cascade, app resize, execView setup) holds drawing
  (`__FV_VW_NODRAW`) and redraws the owner once.
* **Damage below view level** is fv.video's (per-row damaged columns plus the shown copy).

### 1.8 Focus chain, phases, commands

* **Focus chain** `FV_APP.Current → FV_DESKTOP.Current → window.Current → …`; `sfSelected`
  (Current in its owner), `sfFocused` (on the chain), `sfActive` (window and contents), `sfModal`.
  `fv.views.select V` = `makeFirst` (with `ofTopSelect`) + setCurrent. State bits go through the
  virtual-aware `fv.views.setState`: a dispatch only when the class overrides SetState. FV's side
  effects run inline: sfVisible → show/hide drawing; sfFocused → the `cmReceivedFocus` /
  `cmReleasedFocus` broadcast to the owner; sfActive → propagated to subviews, and the frame's
  border redraw.
* **Dispatch** (`fv.views._groupEvent G`, TGroup's HandleEvent implementation):
  1. TView's default: a mouse-down on a selectable, unselected group selects it and is consumed
     unless `ofFirstClick`;
  2. **focused events** (evKeyDown, evCommand): `Phase=phPreProcess` → each subview with
     `ofPreProcess`; `phFocused` → Current; `phPostProcess` → each with `ofPostProcess`;
  3. **positional events** (evMouse*): the front-most visible view whose cached rect holds the
     point (D8: click to focus). The wheel reaches only views whose EventMask holds it (FV: lists
     and scroll bars), as in FV;
  4. **broadcasts and the rest**: every subview.

  The loop skips disabled views and views whose `EventMask` lacks the event without a call. It
  reaches each view through `_virt` and stops when `FV_EV_WHAT == evNothing`.
* **Broadcast cost with FV's masks**: the focus broadcasts go to the desktop's windows (TGroup,
  `$FFFF`, built-in: no dispatch). Inside a window: the frame (built-in) and plain user views with
  TView's mask, which are skipped without a call. Only user subclasses of broadcast listeners (P3
  lists, buttons, labels) cost a dispatch each.
* **Commands** are names (P0 / PLAN §3): `cmValid cmQuit cmError cmMenu cmClose cmZoom cmResize
  cmNext cmPrev cmHelp cmOK cmCancel cmYes cmNo cmDefault cmTile cmCascade cmReceivedFocus
  cmReleasedFocus cmCommandSetChanged cmSelectWindowNum cmResizeApp` + any user `cm*` name.
  **Command sets** = the set of disabled names (`__FV_VW_CMDOFF`). The FV default disables
  `cmZoom cmClose cmResize cmNext cmPrev`; TWindow enables them while selected; a change raises
  `CommandSetChanged`, and Idle then broadcasts `cmCommandSetChanged`.
* **Cursor**: after each handled event, `resetCursor` (plain) places the hardware cursor for the
  focused leaf with `sfCursorVis` when its cell is not covered; otherwise it hides it.

### 1.9 Palette model (finding 9)

* **App palette** = a 127-character symbol string `__FV_AP_PAL`, entry i (1-based) = the symbol of
  CAppColor's i-th byte. fv.video assigned symbols `1`–`9`, `A`–`U` to CAppColor's 30 distinct
  bytes in order of first appearance and `0` to DefaultAttr $07, so the string follows by
  construction. A test compares it with fv.video's default table.
* **View palettes** are FV's index strings per class as space-separated numbers (`TFrame "1 1 2 2 3"`,
  TWindow by its `Palette` field: blue/cyan/gray = CAppColor 8–15 / 16–23 / 24–31, `TBackground
  "1"`, `TStatusLine "2 3 4 5 6 7"`). `GetPalette` is a virtual `func` answering that string, so
  user classes override it or inherit it through the elision. Resolution walks owner palettes up
  to the app palette once per view (Insert, owner/palette change) into `__FV_VW_PAL[v]`.
  `getColor I` is then one substring.
* **`fv.app.setAppPalette ENTRY FG BG [BOLD]`** (256-colour indices, D10) changes one entry
  without touching the other entries that share its symbol:
  1. if the entry's symbol is used only by it, `fv.video.definePalette` changes it in place;
  2. otherwise it reuses a symbol with the same colours, or allocates a free one (31 free:
     `V`–`Z`, `a`–`z`);
  3. it re-resolves every live view's cached palette and redraws.

  With all 62 symbols in use, the call is rc 1 with one `Error:` line. FV's black-and-white and
  monochrome palettes are not in v1 (D10).
* **Shadow attribute**: FV `ShadowAttr $08` (dark grey on black). fv.app defines it once on a
  reserved symbol at Init.

### 1.10 Shadows (finding 7)

* FV's TWindow sets `sfShadow` (views.inc ~4007), and so do menu boxes (P3). A shadow is 2 columns
  to the right and 1 row below (FV `ShadowSize`). Its cells keep their characters and take the
  shadow attribute.
* **fv.video 2a gets `shadeRect X Y W H ATTR`**: an attribute-only rectangle that keeps the
  characters, so wide halves and markers are untouched, with damage tracking and clipping.
  Emulated cost (`p2/probe_shade.sh`, direct symbol-row splices): **0.35 ms** for a window's
  shadow (2×21 + 40×1). A `fillRect` 2×21 costs 0.89 ms. With the entry cost, ~0.5 ms per window
  draw.
* **In the painter**:
  * `paint` shades after drawing a shadowed child, clipped to the owner's clip, so the shadow may
    lie outside the view's bounds;
  * `over` and `drawUnder` use S(V);
  * a shadow never covers;
  * move/close redraw S(A) ∪ S(B), so the cells under a removed shadow are repainted.
* This is in P2 because it changes what users see (FV windows have shadows). No owner question:
  keeping FV's look is the default under D1.

### 1.11 The kklass friend contract (finding 6, Q4)

fv.* uses four kklass internals that no kcl unit used before:

| internal | use | hot path? |
|---|---|---|
| `${inst}_class` | the instance's class (elision) | yes, every `_virt` |
| `${inst}_data[F]` | reading **and writing** another instance's fields (State bits, Owner, Current, bounds) | yes, every loop |
| `${CLASS}_class_method_owner[M]` | the defining class of M (elision) | yes, every `_virt` |
| `kk._exec`, `kk._call`, `kk._parent`, `kk._constructor_exec` | the count shim (tests only) | no |

Rules that come with it:
* a field never assigned is unset: friend reads use `${d[X]-}`;
* writes go only to plain FV `var` fields, never to computed properties (none in fv.*);
* a user constructor that skips `inherited` leaves TView's fields unset, so Insert refuses such a
  view with one `Error:` line ("constructor did not call inherited").

Q4 asks whether kklass documents these as friend tables with a pinning test, or exposes them
through helper functions.

---

## 2. Event loop (fv.app)

### 2.1 Init, Run, GetEvent, Idle, Done

* `TApplication.new app` (FV `Init`):
  1. records `__FV_AP_OWNER=$BASHPID`;
  2. `fv.video.initVideo` (rc 1 → the constructor fails), `fv.drivers.initEvents`,
     `fv.video.initScreen`, the shadow symbol;
  3. calls the virtuals `InitStatusLine`, `InitMenuBar` and `InitDesktop` through `$this.`;
  4. sets `FV_APP`, `FV_DESKTOP`, `FV_STATUSLINE`; draws nothing yet.
  
  P2's `InitMenuBar` creates nothing (O3 is P3), and the desktop then takes row 0 too. This is a
  documented deviation; P3 restores FV's row 0.
* **Headless mode** (tests, bench): `FV_APP_HEADLESS=1` skips `initVideo`/`initEvents`, takes the
  size from `FV_SCREEN_W/H`, sends frames to `FV_VIDEO_OUT_FD` and reads events from `FV_KEY_FD`.
* `app.Run` → `Execute` (TGroup's, elided) = the FV loop:

```
repeat
  EndState := ''
  repeat  fv.app._getEvent
          [FV_EV_WHAT != evNothing] _virt G HandleEvent
  until EndState != ''
until __FV_AP_EOF or Valid(EndState)       # Valid elided unless overridden
RESULT := EndState
```

* **Deviation: no HandleEvent on `evNothing`** (finding 10). FV's Execute calls HandleEvent
  every idle tick, and TGroup's returns at once. A user override of the app's HandleEvent would
  cost a dispatch per 50 ms tick, so the loop skips it. Periodic work belongs in `Idle` (the FV
  idiom anyway).
* `fv.app._getEvent` (FV `TProgram.GetEvent`; a user override of `GetEvent` is dispatched instead):
  1. the pending event (`putEvent`);
  2. `fv.drivers.getEvent` (0.05 s timeout);
  3. **cmResizeApp handled at once**: `_virt FV_APP HandleEvent` → TApplication's resize (§2.3);
  4. on `evNothing`: `Idle` (elided default: status line `Update`, the `cmCommandSetChanged`
     broadcast). An idle tick costs 0 dispatches;
  5. **end of input** (rc 1, `FV_EV_EOF=1`) **latches** `__FV_AP_EOF=1` (finding 4). From then on:
     * every running loop ends after the current event without asking `Valid` (the modal one with
       `cmCancel`, the application with `cmQuit`);
     * a new `execView` returns `cmCancel` at once without running a loop.
     
     So a `Valid(cmQuit)` that opens a "save?" box cannot spin: the box returns `cmCancel`
     immediately, and the application loop ends without asking `Valid` again.
* `TProgram.HandleEvent` (elided default): Alt+1…9 broadcasts `cmSelectWindowNum` to the
  desktop; TGroup dispatch; `cmQuit` → `endModal cmQuit`. TApplication adds `cmTile`,
  `cmCascade` and `cmResizeApp`. TDesktop handles `cmNext` (FocusNext) and `cmPrev` (Current
  behind the others).
* `app.delete` (FV `Done`): the desktop, status line and menu bar deleted, `doneEvents`,
  `doneVideo`.

### 2.2 Modal views and inner loops

* `fv.views.execView G P` (RESULT = the command):
  1. **saves the event globals** (`FV_EV_*`), G's `Phase`, `Options`, the owner, the top modal
     view, Current and the command set;
  2. clears `ofSelectable`, sets `sfModal`, makes P current, inserts it if it has no owner;
  3. runs `_virt P Execute`;
  4. deletes P if inserted and restores everything, **the event globals included** (finding 3).
     The outer `_groupEvent` then continues with its own event: FV has a local `Event` per loop.
* `fv.views.endModal CMD` → the top modal view's `EndState` (else `FV_APP`'s).
* **Inner loops** save and restore the event globals the same way: `mouseEvent` (FV
  `MouseEvent`), `dragView`, the status line's press tracking. They read events through
  `fv.app._getEvent`, so they see resizes and EOF.
* **dragView and a resize mid-drag** (finding 10): a `cmResizeApp` during a drag **ends the drag**.
  The resize is handled first, then the view is accepted at its current bounds clamped into the
  new owner extent, and the saved bounds (Esc's undo) are dropped. Drags also **coalesce motion**:
  before each repaint they drain the waiting events (`getEvent 0`) and keep the last motion.
* **Nesting in bash**:
  * Each modal level adds ~6–10 frames, which is harmless for a few levels (FUNCNEST is unlimited
    by default).
  * The loops are plain functions with `__fvw_` locals.
  * kklass isolates user bodies inside nested loops; the shadow covers only the nearest frame's
    fields, so it does not add up with depth.
  * `execView` answers in RESULT.
* **Owner-process rule** (finding 14): `Run` and `execView` compare `BASHPID` with
  `__FV_AP_OWNER` (fv.video records its owner the same way). Inside `$( … )` they refuse (rc 2,
  one debug line): a modal loop in a subshell would draw through the parent's fd while the
  parent's buffer and shown copy go stale. Face C creates the whole application inside the
  subshell, where fv.video lets the subshell own its TUI.

### 2.3 Resize (cmResizeApp)

1. A WINCH sets `FV_VIDEO_RESIZED`.
2. `fv.drivers.getEvent` runs `updateSize` (the `stty size` fork, the only fork on any event path)
   and returns `evCommand cmResizeApp` (`FV_EV_ID=W`, `FV_EV_INFO=H`).
3. `fv.app._getEvent` hands it to the app's HandleEvent at once.
4. TApplication (elided), when the size changed:
   * holds drawing;
   * `fv.video.resizeScreen`;
   * `ChangeBounds app 0 0 W H` (elided): each subview takes `CalcBounds` by `GrowMode`, as in FV
     (desktop `gfGrowHiX|HiY`, status line `gfGrowLoY|HiX|HiY`, windows `gfGrowAll|Rel`);
   * the bounds cache;
   * one full redraw and the flush.

The cost is a full repaint plus one fork (~20 ms at 80×24 in the prototype), with 2–4 dispatches.

### 2.4 Ctrl+C, traps, terminal restore

* fv.video owns the traps and restores the terminal on every exit path. fv.app sets **no trap**.
  Callers set theirs before `TApplication.new`.
* Ctrl+C (P0: `intr` stays) is an **emergency exit**: terminal restored, status 130, `app.Done`
  not run. The orderly exit is `cmQuit` (Alt+X).
* A `set -e` failure or `exit` in a handler: fv.video's EXIT trap restores the terminal.

---

## 3. Call budget

### 3.1 The actions in P2

P2 has no list views. The test and bench scenes use a **list stand-in** `TTestList`, a user class
in the test lib and the bench with **TView's default EventMask**. It overrides `Draw` (one
`writeBuf` per visible row) and `HandleEvent`: kbDown → `drawPart` of the old and new row
(rule 4); kbPgDn → a new page and `drawView`.

The scene: `TMyApp` (a TApplication subclass overriding HandleEvent with `inherited`, as FV
programs do), a desktop, two windows of 40×23 side by side (each a frame + a stand-in) and the
status line. The **overlap scene** puts the second window over the first.

| action | definition |
|---|---|
| Down | kbDown to the focused stand-in: 2 rows redrawn |
| PgDn | kbPgDn: every row of the stand-in rewritten with new texts |
| Tab | F6 → status line → `cmNext` → the desktop selects the other window: both frames change look; in the overlap scene the new front window is redrawn whole. (kbTab between controls inside a window is P3's; the bench measures it as `tab-in`.) |
| click | mouse-down on the inactive window |
| repaint | `fv.views.redraw $FV_APP` + forced flush |
| resize | cmResizeApp 80×24 → 200×50 |
| idle | one `evNothing` tick |

### 3.2 Counts (prototype, with the shim)

| action | without elision | **with elision** | test limit |
|---|---|---|---|
| Down | 6 | **3** (TMyApp, `inherited`, the stand-in) | 6 |
| PgDn | 7 | **4** (+ the stand-in's Draw) | 8 |
| Tab, side by side | 6 | **3** (focus broadcasts: 0, finding 11) | 8 |
| Tab, overlapping | 8 | ~4 (+ the stand-in's Draw) | 10 |
| click | 4 | **2** | 8 |
| repaint | 10 | **2** (the stand-in Draws) | 6 |
| resize | — | ~4 | 8 |
| idle tick | — | 0 | 1 |

* The counts are independent of rows and cells; the test checks this with a 21-row and a 42-row
  stand-in.
* The prototype sent no focus broadcasts and used EventMask 65535. Under FV's masks the
  broadcasts reach only the built-in windows and frames (no dispatch), and the stand-in is skipped
  without a call, so the counts stand.
* **The write counter** (fv.video shim in the test lib) pins the drawing shape: a border-only
  frame redraw ≤ 4 writes, a full frame ≤ 3 writes plus 2 shade calls, a status line 1 write. That
  keeps per-character frame drawing from coming back.

### 3.3 Time (Git-bash 5.3.15, 80×24, quiet machine; MSYS2 5.3.9 within ~5%)

**Inside a Run frame** (finding 13; `p2/proto_run.sh`). Keys come from a file through
`fv.drivers.getEvent`, and the app's HandleEvent is dispatched from inside an app method, as
`Execute` will run inside `app.Run`'s frame. The harness's own `.call` (~0.2 ms, measured) is
subtracted:

| action | at top level, no getEvent (rev. 1) | **inside a Run frame, with getEvent** | target |
|---|---|---|---|
| Down | 2.4 ms | **3.1 ms** | 4 ms: met |
| PgDn | 8.5 ms | **9.3 ms** | 8 ms: **not met** |

PgDn split (`p2/proto_pg.sh`):

| part | ms |
|---|---|
| 21 `writeBuf` of new row texts | 3.4 |
| the flush of 21 rows | 1.8 |
| 4 dispatches, the stand-in's Draw loop, clip and over | ~3 |
| getEvent and the Run-frame isolation | ~0.5 |
| **total** | ~9.3 |

What would bring PgDn to 8 ms:

| lever | effect |
|---|---|
| 2a fast entry (−25…30 µs × 21 writes, cheaper `setClip`) | −0.7 ms → ~8.6 |
| an application that does not override `HandleEvent` (2 fewer dispatches) | −0.4 ms → ~8.2 |
| P3: exactly one write per visible row and the clip-limited row range | — |
| fv.video work outside P2: a faster colour-run flush, or a write path for pre-validated rows | needed for the last ~0.2–0.5 ms |

So **P2 alone does not bring PgDn under 8 ms**. P2's perf test keeps 2–3× limits (§5.2 of the
plan), and the PgDn target moves to P3 with risk R8.

The other actions (prototype at top level; the Run frame adds ~0.3–0.5 ms each):

| action | dispatches | measured | target | status |
|---|---|---|---|---|
| Tab, side by side | 3 | 12.0–12.4 ms (MSYS2 13.2) | 20 ms | met |
| Tab, overlapping (no lists) | 8 unelided | 10.8 ms | 20 ms | met |
| Tab with FV's desktop redraw at Unlock | — | 25.3 ms | 20 ms | not met (Q2) |
| click | 2 | 12.4 ms | — | |
| full repaint (forced) | 2 | 19.6 ms | — | |
| first paint, list scene (with initScreen) | 2 | 23.9 ms (F-1 bench: 32) | 15 ms | not met (§4, Q3) |
| first paint, P2 scene (desktop + 2 overlapping windows + status line) | 8 unelided | 14.6 ms (MSYS2 15.3) | 15 ms | at the edge |

Shadows add ~0.5 ms per full window draw (not on Tab's border-only path).

Where Tab goes (side by side):
* 2 border-only redraws, ~2.4 ms each (each side column is a 1×21 fill at ~0.8 ms);
* a near-full flush, ~4 ms: fv.video keeps one damaged range per row, so changes at x = 0, 39,
  40 and 79 send each row whole;
* routing.

Optional cuts: a two-column fill (−0.8 ms per frame); a flush that splits a range at a long
unchanged middle.

### 3.4 How the counts are taken (P2-10)

`fvw_testlib.sh`:
* `fvw_count_on`/`off` wrap `kk._exec` (`obj.M`, `$this.M`), `kk._call` (`.call`), `kk._parent`
  (`inherited`) and `kk._constructor_exec` (`.new`) in counting shims, using `declare -f` copies
  (`p2/probe_count.sh`: exact, rc/RESULT/`set -e`/`$( )` unchanged, removable);
* `fvw_writes_on`/`off` count fv.video writes (`writeStr writeBuf writeCStr writeChar fillRect
  shadeRect`) the same way;
* `fvw_budget LABEL LIMIT CMD…` fails above the limit and logs the count.

Timing runs never use the shims. A missing dispatcher name fails loudly; Q4 (a) adds a kklass
pinning test for the names.

### 3.5 The measured costs behind the estimates (Git-bash / MSYS2, µs)

| operation | Git-bash | MSYS2 |
|---|---|---|
| plain function call | 4.9 | 4.9 |
| kklass `obj.M`, 1 / 15 / 30 fields | 100 / 125 / 163 | 103 / 133 / 157 |
| nested call into another class (30 → 25 fields), total | 388 | 396 |
| `inherited` (25 fields), outer + inner | 352 | 378 |
| `app.call` of an empty method (13 fields) | 202 | — |
| field read via `${v}_data` (1 / 5 fields) | 7.9 / 12.4 | 8.0 / 16.4 |
| elision decision `_virt`, uncached (critic) | 19–21 | — |
| `writeBuf` 80 cells, ASCII / Cyrillic + box, cached | 130 / 161 | 128 / 156 |
| `writeStr` 1 character / Cyrillic new text | 125 / 249 | 130 / 267 |
| `writeCStr` status line 80 | 183 | 173 |
| `fillRect` 1×21 / 78×21 / 80×22 | 832 / 788 / 901 | 824 / 799 / 960 |
| shade emulation 2×21 + 40×1 | 345 | — |
| `setClip` / `resetClip` | 79 / 15 | 76 / 13 |
| `updateScreen` nothing changed / force 80×24 | 92 / 1933 | 101 / 1922 |
| `initScreen` 80×24 | 3103 | 3183 |

The fixed ~90 µs of a short write breaks down as: entry guard 9, `_xy` 27 (a cheaper form
costs 5–9, `probe_xy.sh`), symbol check 5, non-ASCII test 10, `_text` cache hit 25, and the row
splice ~30 (~38 µs per row in fills).

---

## 4. First paint ≤ 15 ms (F-1)

**What P2 changes against the bench scene** (`fv-80` paint 32 ms = initScreen 3.3 + composition
22.5 + flush 6):

| change | effect |
|---|---|
| batched frames | 84 one-character writes (5.7 ms) become 3 writes per frame (~1.8 ms per frame including dispatch and strings in the prototype) |
| skip views covered by a covering front view | the background fill (1.3 ms) in the two-panel layout |
| elision | group/frame Draws cost no dispatch (−1.6 ms against 10 dispatches) |
| 2a fast entry | −1.5 ms over ~50 writes |
| 2a palette SGR cached per process | −2–3 ms of initScreen |
| shadows | +~1 ms for two windows |

**Estimates:**

| scene | estimate |
|---|---|
| list scene (F-1 through the P2 model): 23.9 measured, −1.3 −1.5 +1, palette caching −2.5 | **≈ 19–20 ms with initScreen, ≈ 16–17 ms without** |
| P2 scene (no lists) | ≈ 12–13 ms with initScreen, ≈ 9–10 ms without |

Remainder in the list scene: 42 rows at ~140–180 µs (cold texts, P3), the full flush ~4 ms (the
colour-run emitter), initScreen's allocation.

**F-1 stays open under every option of Q3.** No variant brings the two-panel list scene to
15 ms in P2. The native CI rows miss it too: per the bench.yml fv rows, the bench scene's first
paint is 18–50 ms on Linux and 43 ms on Git-bash runners. Q3 decides what the P2 gate measures
and what stays recorded as open.

---

## 5. Units, files, dependencies, tests, docs, bench

### 5.1 Files

```
kcl/fv.views/fv.views.sh     TView TGroup TFrame TWindow, constants, plain API, elision, writers,
                             redraw machinery, shadows, palettes, dispatch, focus, commands,
                             modal loop, drag
kcl/fv.views/tests/          001_Contract 002_Tree 003_Geometry 004_Draw (incl. nested drawView
                             context) 005_Overlap (incl. shadows) 006_Lock (both counters)
                             007_Events 008_Focus 009_Commands 010_CallBudget (+ write counts)
                             011_ZeroFork 012_CallerState 013_Elision (RESULT/rc rule, every
                             built-in overridden with inherited, kk.class --forget + redefine)
                             014_Modal (event globals restored, modal in modal, EOF latch with a
                             Valid box, resize mid-modal/drag) 015_Frame 016_Window 017_Drag
                             018_Names (reserved names, re-creation guard, skipped inherited)
                             019_Palette 020_Perf, fvw_testlib.sh, tests.sh
kcl/fv.menus/fv.menus.sh     TStatusLine (P3: TMenuBar TMenuBox)
kcl/fv.menus/tests/          001_Contract 002_Items 003_Keys 004_Mouse 005_Draw 006_Hint
                             007_ZeroFork 008_CallerState, tests.sh
kcl/fv.app/fv.app.sh         TBackground TDesktop TProgram TApplication, _getEvent, tile/cascade,
                             setAppPalette
kcl/fv.app/tests/            001_Contract 002_Run 003_Modal 004_Resize 005_Desktop 006_Quit
                             007_Eof 008_Pty (script(1) init → run → done restore on MSYS2/
                             Cygwin/VM; SKIP ENV on Git-bash) 009_ZeroFork 010_CallerState
                             011_Subshell (BASHPID), tests.sh
```

Size: fv.views ~1400–1600 lines, fv.menus ~250, fv.app ~450.

### 5.2 Dependencies (`kk.uses`, kcl §1.10)

* `fv.views`: `kklass_pascal`, `fv.video`, `fv.drivers`. It does not load fv.app: inner loops get
  events through `__FV_VW_GETEVENT`, which fv.app sets at Init (default `fv.drivers.getEvent`).
* `fv.menus`: `kklass_pascal`, `fv.views`.
* `fv.app`: `kklass_pascal`, `fv.views`, `fv.menus`, `fv.drivers`.

Functions are `fv.views.*`, `fv.menus.*`, `fv.app.*` (unit names; K-1). Private globals:
`__FV_VW_*`, `__FV_MN_*`, `__FV_AP_*`. Public: `FV_APP FV_DESKTOP FV_STATUSLINE FV_MENUBAR
FV_DRAW_* FV_CLIP_* FV_APP_HEADLESS` and the constants.

### 5.3 kcl/tests registration

* `KCL_UNITS` rows `fv.views||readonly|`, `fv.menus|||`, `fv.app|||` (G6, after fv.drivers).
* Stubs `606_fv.views.sh`, `607_fv.menus.sh`, `608_fv.app.sh`.
* These are the first dotted units with classes; the stub's "classes filed under it" check covers
  them.

### 5.4 README sections (each unit)

1. Quick start.
2. Classes and fields, virtuals, plain API.
3. Drawing: context, writers, palettes, `drawPart`, "Draw must cover its rect".
4. Redraw model and deviations from FV: no z-clip, painter's algorithm, border-only frames,
   the two lock counters and minimal internal redraws, shadows.
5. Events: phases, routing, EventMask defaults, commands.
6. Modal views: EOF latch, the subshell rule, Ctrl+C, no HandleEvent on `evNothing`.
7. Performance: elision ("an override costs a dispatch per use"), the budget table, timings.
8. Contract and deviations; the kklass friend contract; reserved names.
9. Tests.

### 5.5 Bench (tools/bench)

* A new suite `fvviews` (`fvviewcases.sh`), headless.
* Cases:
  * `views-80` / `views-200`: paint (from Run, plus `paint+init` for F-1 continuity), redraw,
    down, pgdn, tab, tab-in, click, move, grow;
  * `views-overlap-80`: tab, click, move;
  * `views-resize`: 80×24 ↔ 200×50.
* Actions **run inside the app's Run frame with getEvent from a key file**, as `proto_run.sh`.
* `# calls ACTION N` and `# writes ACTION N` notes come from an untimed pass.
* `ci.conf` is unchanged by default.

---

## 6. Stage split (Stage 1), in order

Each stage: Opus worker → supervisor review → critic where marked → fixes → suites + `gate.sh` →
commit; the hygiene block in every brief. Windows gate: Git-bash 5.3.15, MSYS2 5.3.9, Cygwin
5.2.21; the VM gate (5.1.16 / 5.2.37) on the core stages.

| stage | content | size | gate / review |
|---|---|---|---|
| **2a** fv.video for P2 | `writeBuf … [H]`; `shadeRect`; `getRow Y` (RESULT text, REPLY symbols); `getClip`; cheaper entry/argument checks (−25 µs per short write); default palette SGR cached per process; optional two-column fill | ~250 + tests | fv.video suite all runtimes + VM; bench A/B `fv` (no case slower than the A/A spread); light critic |
| **2b** kklass friend contract (Q4 = a) | the four internals documented as friend tables in the kklass book (incl. set -u, write rules); one pinning test (names, owner table for inherited methods, `_data`/`_class` shape, dispatcher names) | docs + ~60-line test | kklass suite + `gate.sh all`; supervisor-read |
| **2c-1** fv.views core I: tree and geometry | constants, TView/TGroup, FV-corner constructors, reserved names + constructor guard, subview arrays, insert/delete/makeFirst/putInFrontOf, bounds cache, GrowMode, locate/moveTo/growTo, makeLocal/Global, `_virt` + the RESULT rule, test lib (headless screen, both shims, buffer reader via `getRow`) | ~350 | Windows + VM; critic |
| **2c-2** fv.views core II: drawing | palettes + getColor, drawing context with save/restore, writers, paint/drawView/over/drawUnder/covered skip, shadows, both lock counters, nodraw, show/hide, drawPart, redraw, **minimal TFrame draw** (full + border-only, cached strings) | ~400 | Windows + VM; **critic** |
| **2c-3** fv.views core III: events, focus, modal | `_groupEvent` (phases, positional, broadcast, FV masks), `message`, select/setCurrent/focus chain/selectNext/focusNext, setState + side effects, command sets, resetCursor, Execute/execView/endModal with event save/restore and the EOF latch hook, mouseEvent, **basic TWindow** (Flags, Number, Palette, Frame via InitFrame, GetTitle, SetState → commands, kbTab, cmSelectWindowNum, cmClose) | ~400 | Windows + VM; **critic** |
| **2d** TWindow/TFrame rest | Zoom/ZoomRect/SizeLimits, cmZoom/cmResize, keyboard DragView (move/resize, Enter/Esc), frame mouse (close/zoom icons, drag move, grow corner), motion coalescing, a resize ending a drag | ~300 (may split keyboard / mouse) | Windows + VM; light critic |
| **2e** fv.menus TStatusLine | defs by HelpCtx, AddDef/AddItem (+ constructor triples), key map per def, one-write draw (disabled greyed), key → command, press tracking (event save/restore), Hint, Update on idle, cmCommandSetChanged | ~250 | Windows; supervisor-read (parallel with 2d) |
| **2f** fv.app | TBackground, TDesktop (cmNext/cmPrev, tile/cascade, InitBackground), TProgram/TApplication (Init/Done, headless, Run, `_getEvent` with immediate cmResizeApp and the EOF latch, Idle, PutEvent, Alt+digit, cmQuit, resize flow, BASHPID guard, setAppPalette, shadow symbol), 008_Pty | ~450 | Windows + VM (pty on MSYS2/Cygwin/VM); **critic** |
| **2g** budget, bench, docs | 010_CallBudget final limits + row/cell independence + write counts; `fvviews` bench suite (Run frame) + README; unit READMEs; kcl README §2 rows; PLAN/ledger; a headless demo for the owner's later live run | ~300 + docs | `gate.sh all` host + VM; supervisor-read |

Order: **2a ∥ 2b → 2c-1 → 2c-2 → 2c-3 → (2d ∥ 2e) → 2f → 2g**. If Q4 = b, 2b becomes the helper
functions (~40 lines + test) and `_virt` costs one more call per use.

---

## 7. Owner questions

### Q1 — How a script calls FV's non-virtual methods

FV has methods that are never overridden: `Insert`, `Delete`, `DrawView`, `Select`, `Hide`,
`ExecView`, `EndModal`. Inside fv.* they are plain functions either way (5 µs against ~200 µs for
a kklass method). The question is what **your** scripts write:

* **(a) plain functions only:** `fv.views.insert "$FV_DESKTOP" win1`, `fv.views.drawView "$this"`,
  `fv.views.execView "$FV_DESKTOP" dlg; [[ $RESULT == cmOK ]]`. Fastest; reads less like FV.
* **(b) kklass methods only:** `desk.Insert win1`, `$this.DrawView`, `desk.ExecView dlg`. Reads
  like FV. Each use is one dispatch (~0.2 ms): a list that calls `$this.DrawView` on every Down
  pays +0.2 ms per key. Note: `desk.Delete win1` (remove a subview, FV's `Delete`) sits next to
  kklass's `win1.delete` (destroy the object); the two differ only in the case of one letter.
* **(c) both:** the plain functions are the implementation, and TView/TGroup get thin method
  aliases for set-up code (`Insert DrawView Select Show Hide MakeFirst Locate ExecView EndModal
  SelectNext Lock Unlock`). Cost: ~12 more wrapper functions per instance (`.new` ~30 % slower)
  and two spellings in the docs. To avoid the case-only clash, (c) adds **no** `Delete` alias:
  removal is `fv.views.delete G V` only.

**Recommendation: (c) without a `Delete` alias.** If you prefer one spelling, (a).

### Q2 — When a group is redrawn: FV-exact or only what changed

In FV, focusing another window locks the desktop, and unlocking it redraws the **whole desktop**:
the background and every window. The redraw design here redraws only what changed (the two frame
borders, or the window brought to the front). The pixels on screen are identical either way. What
differs is speed and how often your views' `Draw` runs.

* **(a) FV-exact:** the framework's own focus, z-order and bounds changes go through
  `Lock`/`Unlock` like FV, and every window switch redraws the desktop. Measured: Tab **25.3 ms**
  at 80×24 (target 20; 200×50 roughly 2–3× that). A view that counts its Draw calls sees FV's
  numbers.
* **(b) minimal internal redraws, FV `Lock`/`Unlock` for your code:** your own
  `fv.views.lock win1; …; fv.views.unlock win1` behaves as in FV (the group is redrawn once at the
  end). The framework's own changes redraw only what changed. Measured: Tab **12.0 ms**. A window
  whose content was not covered is not redrawn on a focus switch, so its Draw does not run then.
* **(c) Lock/Unlock only hold the terminal flush** (revision 1). Cheapest, but an FV port that does
  `Lock; change fields; Unlock` and expects the redraw would show stale content.

**Recommendation: (b).**

### Q3 — First paint: what the P2 gate measures (F-1)

Today the bench's "first paint" includes `initScreen` (3–4 ms). In a program it runs once in
`TApplication.Init`, next to `initVideo` (~200 ms of forks on Windows): the screen appears ~0.2 s
after start either way. **F-1 stays open under every option.** Even the best option leaves the
two-panel list scene at ≈ 16–17 ms, and the native CI rows miss 15 ms too (18–50 ms on Linux,
43 ms on Git-bash runners, bench scene).

* **(a) count from `Run`** (draw + flush; `initScreen` belongs to start-up). P2's gate: P2's own
  scene ≤ 15 ms (≈ 9–10 ms projected). The list scene (≈ 16–17 ms) and the native rows stay
  recorded under F-1 for P3 and a later fv.video step. The bench prints `paint` and `paint+init`.
* **(b) keep counting `initScreen`, keep 15 ms as P2's gate for the list scene.** This needs
  fv.video work outside P2 (a faster colour-run flush, a pre-validated row write), not yet
  measured: ≈ 19–20 ms after P2 today.
* **(c) keep counting `initScreen`, set the gate to 20 ms** for the list scene at 80×24 on
  Git-bash; F-1 records 15 ms as the goal.

**Recommendation: (a)**, with the palette caching in 2a either way.

### Q4 — The kklass internals fv.* relies on (friend contract)

fv.* reads and writes four kklass internals (§1.11): `${inst}_class`, `${inst}_data[F]` (also
**writing** another object's fields; no kcl unit does that today, and tdictionary's docs say
"never touch"), `${CLASS}_class_method_owner`, and the dispatcher names (for the test shim; today
pinned only by chance through perf test 150). Two of them sit on the hot path of every key.

* **(a) a documented friend contract:** the kklass book names these four as friend tables (format,
  set -u behaviour, which writes are allowed), and one kklass test pins them. No runtime cost.
  kklass changes to them then become visible, deliberate changes.
* **(b) helper functions in kklass:** `kk.methodOwner CLASS M`, `kk.instanceClass I`,
  `kk.field I F [VALUE]`. Each is a call (~5–10 µs; `_virt` and the group loops would make 3–10
  of them per key, +0.1–0.5 ms per key), and they need care not to clobber the caller's RESULT.

**Recommendation: (a).**

Not asked: bounds are FV corners (D1); window move and resize stay in P2 (PLAN §4); modal views
are FV's synchronous ExecView (D1); commands are names (P0); shadows are in, keeping FV's look
(§1.10).

---

## 8. Risks and what to probe first

| # | Risk | Mitigation / probe |
|---|---|---|
| R1 | fv.video's fixed per-write cost (~90 µs) and row splice (~38 µs) dominate drawing | 2a A/B first on all runtimes; P3 keeps one write per visible row |
| R2 | One damaged range per row sends whole rows on border changes (Tab ~4 ms of flush at 80×24; 200×50 ~3×) | Tab at 200×50 in the 2g bench; optional flush splitting |
| R3 | Elision correctness: a missed override, a leak through dynamic scope, the RESULT rule | no cache; 013 overrides every built-in virtual with `inherited`, uses fields named like common locals, does `kk.class --forget` + redefine, checks RESULT/rc both ways |
| R4 | Focus broadcasts into dialogs with many listening user controls | FV masks; P3 measures dialogs |
| R5 | Nested loops with resize and EOF | 014: modal in modal, resize mid-modal/drag, EOF with a Valid box, event globals restored |
| R6 | `Run`/`execView` inside `$( … )` | BASHPID guard + 011 |
| R7 | kklass internals change (§1.11) | Q4 (a): book + pinning test |
| R8 | **PgDn over target** (9.3 ms vs 8 in a Run frame) | 2a (−0.7); P3 one write per row; an fv.video flush or row-write step if still over |
| R9 | 200×50 repaints over 30 ms (PLAN §7) | measured in 2g |
| R10 | Drag repaint rate | motion coalescing; bench `move` |
| R11 | Live-name re-creation in user code | constructor guard + 018 |
| R12 | Shadow symbol or palette symbols exhausted (62) | `setAppPalette` reuse/allocation, rc 1 when full; 019 |
| R13 | Only Windows numbers | bench.yml native rows after an owner-allowed perf push |

**Probe first** (before 2c-1):
1. 2a's fast entry A/B on all runtimes and the VM;
2. `_virt` with user subclasses of each built-in (correctness under `set -eu`, nocasematch, IFS);
3. the prototype at 200×50 (Tab, paint).

---

## Appendix A. Probes and prototype (`scratchpad/p2/`)

| file | what |
|---|---|
| `probe_kk.sh` | kklass call costs by field count, nested, `$this.M`, `inherited`, field reads |
| `probe_fv.sh` | fv.video write/fill/clip/flush/initScreen costs |
| `probe_entry.sh`, `probe_xy.sh` | the fixed cost of a short write; a cheaper coordinate check |
| `probe_count.sh` | the dispatch-counting shim |
| `probe_owner.sh` | kklass's owner table for inherited methods |
| `probe_shade.sh` | the cost of an attribute-only shade (emulated) |
| `proto.sh`, `proto_el.sh` | the prototype, without and with elision |
| `proto_split.sh`, `proto_nolist.sh` | the paint/Tab breakdown; the P2-only scene |
| `proto_run.sh` | Down/PgDn inside an app Run frame with getEvent from a key file (rev. 2) |
| `proto_pg.sh` | the PgDn split (rev. 2) |
| `proto_lockfv.sh` | Tab with FV's desktop redraw at Unlock (rev. 2) |
| `critic/` | the critic's probes: `c_virt.sh` (cache gain and staleness), `c_result.sh` (RESULT by path), `c_recreate.sh` (live re-creation) |
| `proto_frame*.txt`, `view_frame.sh` | frames through fv.video's VT model |

CPU was checked before each timing batch (Get-Process twice 5 s apart, 16 logical CPUs; timing
only with no foreign process above 5 %). Rounds: median of 5 × N in one process.
