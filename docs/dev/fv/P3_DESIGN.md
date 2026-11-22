# fv P3 Stage 0: design of the widgets (L3)

2026-11-20, **revision 2** (after the critic's review and the owner's answers of 2026-11-20; the
change list is §R; the layout-independent hot-key research is §14). The owner answered Q7 and Q8
the same day: **D30** (option (c) for layouts) and **D31** (one list speed target for every kind
of text, a fv.video speed stage 3v) — §0.1; the sections below that still say "per-kind target"
or "Q8 proposes" are superseded by D31.

Inputs:
* PLAN.md (D1–D21, §2.2 rules, §4 P3, §5, §6 O3, §7) and fv_ledger.json (P2 stages, D21, F-1,
  R8/R9, K-2, K-8);
* P2_DESIGN.md (the model: elision, painter, events, budgets) and the READMEs of fv.views,
  fv.menus, fv.app, fv.video, fv.drivers, fv.keyboard, fv.unicode; the kklass book ("What a func
  answers", "Field-free bodies: nofields", the friend tables);
* Free Vision (FPC trunk, `packages/fv/src`): `views.inc` (TScrollBar, TScroller, TListViewer,
  TWindow.HandleEvent), `dialogs.inc` (TDialog, TInputLine, TButton, TCluster, TRadioButtons,
  TCheckBoxes, TListBox, TStaticText, TLabel), `msgbox.inc`, `menus.inc` (TMenuView, TMenuBar,
  TMenuBox, TMenuPopup), `drivers.inc` (evMouseAuto, RepeatDelay);
* tools/bench `fvviewcases.sh` (the stand-in `TTestList`, the Run-frame harness).

To check the numbers I built a **scratch prototype** (`p3/proto_w.sh`): built-in-like classes on
the real kcl (`TPScrollBar`, `TPListViewer`, `TPDialog`, `TPButton`, `TPLabel`, `TPCheckBoxes`,
`TPInputLine`, `TPMenuBox`) whose virtual bodies are plain functions registered in fv.views'
elision table `__FV_VW_IMPL` exactly as P3's built-ins will be, and a probe harness
(`p3/probe_p3.sh`) built like the `fvviews` bench: **every action runs inside `app.Run` with keys
from a file through `fv.drivers.getEvent`**, headless, frames to `/dev/null`, counts from an
untimed pass with the bench's shims. Numbers are in §8 and Appendix A.

Revision 2 adds `p3/proto_r2.sh` (the list painter for cell-padded wide rows, a `TPMenuBar` with
FV's flow, a messageBox stand-in, dialog build / destroy) and `p3/probe_r2.sh` (the critic's M1
method fixes, fresh pages, same-process stand-in, the menu flow through the bar's owner),
`p3/probe_keys.sh` (the key reports of the layout protocols through today's fv.keyboard); outputs
`p3/out_r2_*.txt`, `p3/out_keys_*.txt`.

**How to read the times (revision 2, M1).**
* **Method.** Every timed action runs 5 rounds of (empty Run, Run with N keys, empty Run); a
  round's value is (keys − the smaller of the two adjacent empty Runs) / N; the tables give the
  **median (min–max)** of the rounds. One-shot actions (open + close, build + destroy) the same
  way with one unit per Run. Dialog and menu cases now run their 5 rounds too (revision 1 ran them
  once). Revision 1's `timed` compared one Run with the minimum of 3 baselines
  (`probe_p3.sh:135-142`), which biased it up; its numbers stay only where marked.
* **Same-process calibration.** Every probe process also measures the bench's stand-in
  (`standin.down`, `standin.pgdn`: tools/bench `fvviewcases.sh`, D21 stage E) in the same scene
  shape, so each number has a **ratio** to the stand-in action of its kind: 2-row actions to
  `standin.down`, whole-view redraws (PgDn, a scroll, the wheel) to `standin.pgdn`.
* **CI ranges, not one factor.** The revision 1 factor ×0.82 came from CI run 44482144631, which
  predates K-8 (K-8 made Down 0.92–0.96 and PgDn ~0.96, run 44538735494), and per-action ratios
  differ. The stand-in on CI ubuntu 22.04 after K-8 spans **Down 3.7–5.0 ms, PgDn 6.3–8.0 ms**
  (run 44482144631 × the K-8 ratios; run 44538735494 measured directly: a ±25 % runner spread,
  D21). A CI estimate here = the laptop ratio × that range, e.g. a list PgDn with ratio 1.00 →
  6.3–8.0 ms. **Targets are ranges until a same-run CI A/B in stage 3b** (lists against the
  stand-in in one CI run) fixes them; 3g re-checks all of them.
* **The machine.** Laptop, Git-bash 5.3.15 and Cygwin 5.2.21 (bash < 5.3: fv.video's listed-char
  text check, D21); CPU sampled before each batch (`p3/cpu.ps1`): one VS Code process at ~20 % of
  a core, nothing else above 3 %. This session's laptop ran ~15 % slower than revision 1's
  (`standin.down` 5.5–6.0 against 4.8–5.0 ms): ratios stay comparable, absolute numbers do not.
  bash 5.1 was not run (a VM stage; it takes the same pre-5.3 path as 5.2).

---

## R. Revision 2: what changed, per finding

### R.1 Critic findings

| # | Finding | Change (section) |
|---|---|---|
| H1 | List budgets hold only for ASCII names | Re-measured on **fresh pages** (rows fv.video's text cache never saw) with ASCII, Cyrillic and CJK names, on bash 5.3 and 5.2: list PgDn ratio to the stand-in 1.00 (ASCII), **1.89 (Cyrillic)**, **9.3 (CJK)**; a fresh non-ASCII row costs ~260 µs (Cyrillic) / ~2.2 ms (CJK) in fv.video. Two fv.video levers (new **10.11** fresh narrow rows inside `_wrows` with one batched text check: 99 → 20 µs per row measured for the check; **10.12** a wide fast path for CJK rows) and per-kind targets as ranges. The prototype's CJK rows now have the right cells (cell-padded test data). Bench and tests get fresh Cyrillic and CJK pages. (§2.2, §8.2, §9, §10, §11, §12 R14) |
| H2 | O3 = yes silently gives every app an empty top row | Decided by the owner: **the bar only on request** (D23). (§0, §7, §10.10) |
| M1 | The ×0.82 calibration and the `timed` method | Method rewritten (rounds, medians, same-process stand-in, per-action ratios), CI estimates as ranges, targets as ranges until the 3b same-run CI A/B. (header, §8) |
| M2 | Emulated savings attributed to the wrong lever | `emul/coal.txt` also dropped the input line's sfFocused draw (that is P3-12, and the draw is needed when focus changes without a selection change); `nopp` removed pre/post-processing altogether, so it bounds the hot-key map from above. **10.4 is dropped from 3a**: ~3 ms per open + close, revisited only if the 3c A/B misses the dialog range. (§3.4, §8.3, §10.4) |
| M3 | Dialog budget omits build and destroy | Measured end to end: a messageBox stand-in built, run and destroyed **52 ms** laptop; the 8-control dialog built + opened + closed + destroyed **102 ms** (build 22.7, insert 36.7, delete 26.0, destroy 13.6 ms). Budgets and bench cases for both. (§6, §8.3, §9.2) |
| M4 | TListViewer.SetState's ShowSBar; TWindow.StandardScrollBar missing | Both added as FV does them (views.inc:3817-3834, 4091-4103); ShowSBar also cuts the two-panel first paint (one bar drawn instead of two: 1.31 → 1.15× the stand-in scene). (§1.3, §2.2, §8.5) |
| M5 | Hot-key map gaps | The map keeps FV's Z order and merges unmapped pre/post views in it; the owner's `Phase` set before every call (dialogs.inc:2473, 2854, 3733); setters keep it current, a direct field write is documented and caught by a cheap stamp check; the map moves to 3c with its users; test 025 compares map vs full scan with interleaved user views. (§3.1, §10.3, §11) |
| M6 | "prev-cluster + char" breaks with ZWJ / VS16 / RI | After every non-ASCII insert and every delete next to a non-ASCII cluster, the window [previous cluster … next cluster] is re-split, widened over a regional-indicator run; 008 covers joiners mid-line. (§4.1) |
| M7 | FV steps CurPos by one UTF-16 unit; FirstPos rule | Cluster stepping stated as a **deviation** (FV: `Dec(CurPos)` / `Inc(CurPos)`, dialogs.inc:2028-2032, 2071-2092); FirstPos keeps the text in **Size.X − 3** cells (2164-2171). (§4.1, §4.2) |
| M8 | ASCII mode wrong / incomplete | A widget glyph table per mode (FV LowAscii keeps ▒ ■ ▓, views.inc:3110-3114, which fv.video's ASCII mode would show as `?`); the input line counts one cell per character in ASCII mode, as fv.video does. (§2.7) |
| M9 | Hot keys with a Russian layout | The owner's research item: §14 (options, examples, recommendation; Q7). |
| M10 | P4 needs password mode and long checklists | Decided: both in P3 (D29). (§4.8, §5) |
| M11 | `ESC [ 0 q`; Shift+Ins / Ctrl+Ins taken by terminals | Stated: `ESC [ 0 q` restores the terminal's default shape, not a shape the shell set; which clipboard keys reach the program in WT / mintty / xterm / VTE / kitty, and that a terminal's Shift+Ins under bracketed paste is one paste event. (§2.5, §4.5) |
| L1 | Menu probe not FV's flow | Re-done with FV's flow: F10 → status line → `cmMenu` → the bar (pre-process) → `execView` by the bar's owner (the application), the box dropped by the **bar's owner** (menus.inc:766) and disposed; Esc closes (F10 inside Execute falls to `HotKey`, menus.inc:731, and closes nothing); the status line's hint redrawn per move. open + drop + close **52 ms**, a move **6.05 ms** (4.55 without a hint change). (§7, §8.4) |
| L2 | evMouseAuto runs away after a lost release | Any key event (and any press) ends the held state. (§3.3, §10.6) |
| L3 | Missing FV behaviours | Added: CtrlToArrow WordStar keys everywhere FV uses them; Space → SelectItem and Ctrl+PgUp / Ctrl+PgDn in lists; `cmRecordHistory` from TButton.Press; no focus on click without `bfGrabFocus`; a button disabled at Init when its command is; Enter on a focused button; TCluster's hardware cursor on `Sel`; `TCluster.Id`. (§3.1, §3.2, §2.4, §1.2) |
| L4 | Inconsistencies | Radio mark ` (*) `; the §1.4 label link; messageBox OPTIONS = one integer; GetData / SetData / DataSize are virtuals (no alias); the P3_SBPART row; boolean virtuals answer by rc. (§1.3, §1.4, §2.4, §6, §8.2) |
| L5 | Name clashes with fv.drivers | fv.dialogs `__fvg_` / `fvg_testlib.sh`, fv.msgbox `__fvx_` / `fvx_testlib.sh`, fv.histlist `__fvh_`. (§1.3, §9.1) |
| L6 | Row caches | Button cache keyed by state, palette, title and width; cluster rows composed per draw (no per-Value cache); every widget cache dropped in fv.views' delete hook (fv.views.sh:856-860). (§2.1) |
| L7 | P3-4's self-skip | The direct list → bar link and the skip apply only when the list's HandleEvent is the built-in; an override gets the broadcast. (§0 P3-4, §2.3) |
| L8 | Stage split | Hot-key map moves to 3c (its users); 3e and 3f run one after the other (shared README / KCL_UNITS / ledger); F-1 measured and routed (§8.5, Q8); a 200×50 list target. (§11) |
| L9 | Test gaps | Added: resize during a modal dialog, `$(fv.msgbox.messageBox …)` refused by the BASHPID rule, EOF and a subshell inside the menu loop, `?2004l` / kitty pop / DECSCUSR restore on every exit path, widgets in ASCII mode, hot-key map invalidation. (§9.1) |
| L10 | "D21 met the targets" vs "Down 4.01 at the edge" | Wording follows the ledger. (§13) |

### R.2 Owner answers (2026-11-20) → D22–D29

O3 and the revision 1 questions Q1–Q6 are answered; they are decisions now (§0): **D22** menus in
v1, full; **D23** the bar only on request; **D24** bracketed paste + internal clipboard + OSC 52;
**D25** friendly list colours in a plain window; **D26** a `Marks` field; **D27** the cursor
shape by mode; **D28** input history in v1; **D29** password mode and long checklists in P3. The
sections that described the options now describe the decided design (§2.5, §2.6, §4.5, §4.8, §5,
§7, §15 history).

### R.3 Research item: layout-independent hot keys

§14: the protocols (kitty keyboard protocol, win32-input-mode, modifyOtherKeys / formatOtherKeys),
what FPC's own keyboard unit already does with them (`rtl-console/src/unix/keyboard.pp`), a
table fallback generated from xkeyboard-config, how fv.keyboard exposes the base key and the one
hot-key helper; owner options with examples per script and terminal; recommendation; owner
question **Q7**. Headless parser probes: `p3/out_keys_*.txt`.

---

## 0. Summary of the decisions

### 0.1 Owner decisions (2026-11-20; for PLAN.md §1)

| # | Decision | Design |
|---|---|---|
| D22 | **Menus in v1, full** (O3 closed): TMenuBar + TMenuBox + submenus (+ TMenuPopup), F10 / Alt+letter, the status line shows the current item's hint. | §7, stage 3f |
| D23 | **The menu bar only on request.** Without a menu nothing changes: no top row; P2's tests, the bench scenes and the first-paint baselines stay as they are. An application that wants a menu overrides `InitMenuBar` (or calls the one-call helper `fv.menus.menuBar`, which describes the items) and then row 0 is the bar and the desktop starts at row 1. Documented deviation from FV, whose `TProgram.InitMenuBar` always creates an (empty) bar (app.inc:958-964). | §7.1, 10.10 |
| D24 | **Paste and clipboard: bracketed paste + an internal clipboard + copy to the system clipboard via OSC 52.** Which keys the program uses and what each terminal does with them: §4.5. | §4.5, 10.8, 10.9 |
| D25 | **Lists in a plain window get a friendly built-in default** (the window's scroller colours: yellow on blue, the focused row blue on grey); in a dialog CListViewer as FV. Documented deviation (FV shows ErrorAttr there). Marked rows: window entry 2, bright white on blue (owner 2026-11-21). | §2.6 |
| D26 | **A `Marks` field for multi-select**: the name of an associative array the built-in Draw reads inline; no per-row `IsSelected` dispatch (an override still works and wins). | §5 |
| D27 | **Cursor shape by mode**: underline while inserting, block while overwriting (DECSCUSR); at exit `ESC [ 0 q`, which restores **the terminal's default shape** for the session, not a shape the user's shell had set (no query exists that works everywhere). | §2.5, 10.7 |
| D28 | **Input history (FV THistory) in v1**: the `▐↓▌` button after an input line, the history window with its list, `cmRecordHistory`, the per-id history store. Its own stage (3h). | §15, stage 3h |
| D29 | **For P4, in P3: password mode** (a mask character field in TInputLine) **and long checklists through a list with `Marks`** (instead of TCheckBoxes' 32-item limit). | §4.8, §5 |
| D30 | **Hot keys with any keyboard layout: option (c)** (Q7, 2026-11-20): match the typed character first, then the base-layout key from the kitty keyboard protocol when the terminal has it, then the layout tables generated from xkeyboard-config (`FV_KBD_LAYOUT` / the locale / a per-script default resolve ambiguity). win32-input-mode (option d) stays a later opt-in after a live check in Windows Terminal. | §14, 10.14, stage 3L |
| D31 | **One speed target for every kind of list text** (Q8 = (a), 2026-11-20): PgDn ≤ 8 ms CI Linux 80×24 on fresh pages for ASCII, narrow non-ASCII (Cyrillic, Greek, Latin-1) **and wide (CJK)** names; the two-panel list scene's first paint (F-1) ≤ 15 ms CI with real lists. This needs an extra fv.video speed stage (**3v**, after 3b's CI A/B shows the real gap; size set by its own probe), which delays the dialog stages. | §8.2, §8.5, 10.13, 10.15, stage 3v |

### 0.2 Design decisions

| # | Decision | Why |
|---|---|---|
| P3-1 | All P3 classes are **kklass classes with FV's field names**, every built-in virtual a one-line **`nofields`** wrapper over a plain body registered in `__FV_VW_IMPL` (P2-2 + K-8). A class that overrides nothing costs no dispatch anywhere. | Measured: a list Down, a Tab between dialog controls, a typed character and a menu move cost **0 dispatches** in the prototype beyond the application's own `TMyApp` + `inherited` (§8.1). |
| P3-2 | **Units as FV**: `TScrollBar`, `TListViewer` in fv.views (FV views.pas); `TDialog TButton TStaticText TLabel TParamText TCluster TCheckBoxes TRadioButtons TInputLine TListBox THistory THistoryViewer THistoryWindow` in a new **fv.dialogs**; the history store in a new **fv.histlist** (FV histlist.pas); `MessageBox InputBox` in a new **fv.msgbox**; `TMenuView TMenuBar TMenuBox TMenuPopup` in fv.menus. | D7, PLAN §3, FV's unit split, D22, D28. |
| P3-3 | **Lists draw with one `writeLines` per paint** and FocusItem repaints the old and the new row with two `drawPart`s of one `writeLine` each when the top item does not move (rule 4); data = **the name of an indexed array** plus an optional **plain formatter function** `FMT INDEX WIDTH` → `RESULT` (rule 2: no call per row); rows with wide characters through `writeRows` (10.2). | ASCII: list Down 0.90× the stand-in's Down, PgDn 1.00× the stand-in's PgDn on fresh pages (§8.2). |
| P3-4 | **A scroll bar draws only a changed picture**: a value change that leaves the thumb cell where it was draws nothing; a moved thumb repaints its old and new cell (two one-row `drawPart`s); a range change draws the bar whole. **A built-in list tells its own bar directly** (no `cmScrollBarChanged` walk back to itself) — only while the list's `HandleEvent` is the built-in one; a list class that overrides `HandleEvent` gets FV's broadcast. The broadcast still goes out when anybody else listens (the broadcast table, P3-7). | FV redraws the whole bar on every value change: PgDn 13.9 → 8.8 ms, a scroll 13.1 → 9.1 ms here (§8.2). |
| P3-5 | **TInputLine keeps its text as clusters**: two per-instance arrays (`${v}_cl` cluster strings, `${v}_cw` their cells), `CurPos FirstPos SelStart SelEnd` count **clusters** (a documented deviation: FV steps one UTF-16 unit). The split is fv.video's (`fv.video.clusters`, 10.1), re-run over the neighbourhood of every non-ASCII edit (§4.1), so the line agrees cell for cell with the screen on every runtime (Cygwin's two-unit astral characters included) and in ASCII mode. ASCII input takes a fast path. | D5 + D14 (VS16), the Cygwin surrogate halves (fv.video P1b); typing a character = one `writeLine`, 0 dispatches. |
| P3-6 | **Modal dialogs are FV's**: `TDialog` = TWindow + gray palette, Esc / Ctrl+F4 → `cmCancel`, Enter → the `cmDefault` broadcast, `cmOK cmCancel cmYes cmNo` end the modal state; buttons are FV's (default button, `cmGrabDefault` / `cmReleaseDefault`, Alt+hot key, Space / Enter on the focused button, press tracking by the mouse, `cmRecordHistory` before the command). | D1. |
| P3-7 | **fv.views gets two P3 hooks** (§10): a **broadcast table** (which built-in handler reacts to which broadcast: the quiet walk and the dispatch skip the rest without a call) in 3a, and a **hot-key map** per group (pre/post-process views that only react to their hot keys are found by one lookup, merged in Z order with the views that have no map entry) in 3c. Coalesced child redraws (10.4) are **dropped** for now. | Pre/post scan: up to 1.5 ms of a keystroke in a dialog (an upper bound, §8.3). |
| P3-8 | **Mouse auto-repeat** (`evMouseAuto`) comes from fv.drivers: while a button is held and nothing arrives, the first after `FV_REPEAT_DELAY` (0.44 s, FV's 8 ticks), then one per idle timeout (0.05 s); any key or press ends the held state. | fv.drivers README: "comes with the scroll bars (P3)"; L2. |
| P3-9 | **fv.msgbox = plain functions returning the command in `RESULT`**: `fv.msgbox.messageBox MSG OPTIONS [-- PARAMS…]`, `messageBoxRect`, `inputBox TITLE LABEL VARNAME LIMIT` (the value comes back in the named variable, FV's `var S`). Each call builds and destroys its dialog (FV). | FV's API, bash idiom (§6); end to end ~52 ms laptop. |
| P3-10 | **Menus as FV** (D22): TMenuView's model, items flat in per-instance arrays (as the status line), a **key map** for item hot keys; the bar runs modal in its owner and drops each box through the **bar's owner** (menus.inc:766), created and disposed per drop; a cursor move repaints 2 rows + the status line's hint (FV's Idle); **the bar only on request** (D23). | open + drop + close 52 ms laptop (19 dispatches with a `TMyApp` override: FV's focus broadcasts reach it; measured in stage 3f: 22, §7.2), a move 6.05 ms with 0 dispatches (§8.4). |
| P3-11 | **Palettes FV's** in dialogs: CDialog (gray / blue / cyan, 32 entries into CAppColor 32–127), CButton, CCluster, CInputLine, CLabel, CStaticText, CListViewer, CScrollBar, CHistory, CMenuView mapped through the owner chain as P2 does. **A list in a plain window: the friendly default** (D25). | D1, D25. |
| P3-12 | **Redraw only what changed (D17) for widgets**: a state change redraws a control only when its picture changes (a label whose `Light` stays, a button whose colours stay); the input line's sfSelected + sfFocused sequence draws **once at its end** (never skipped: focus can change without a selection change). | Tab between controls: 4.7 drawViews per hop with FV's eager redraws (§8.3). |
| P3-13 | **Hot keys independent of the keyboard layout** (owner's research item): fv.keyboard reports the base-layout key next to the typed character (`FV_KEY_BASE`; protocol when the terminal has one, a generated layout table otherwise) and one helper matches every hot key (status line, menus, buttons, labels, clusters) by the typed character first, then by the base key — FPC's own order. Options and recommendation: §14, **Q7**. | Today Alt+F with a Russian layout arrives as `ESC а` → `kbAltChar`, and no Latin hot key fires (`p3/out_keys_gb.txt`). |
| P3-14 | **Fresh non-ASCII rows are fv.video's job** (10.11, 10.12): `_wrows` converts a missed narrow row itself with one batched text check over the page instead of one public `writeBuf` per row, and wide (CJK) rows get a fast path without the per-character walk. | Fresh Cyrillic PgDn 1.89× and CJK 9.3× the ASCII cost today (§8.2). |


---

## 1. Object model

### 1.1 Classes and units

| unit | classes (kklass, Pascal DSL) | FV origin | new lines (est.) |
|---|---|---|---|
| `fv.views` (+) | `TScrollBar : TView`, `TListViewer : TView`; `fv.views.standardScrollBar` (FV `TWindow.StandardScrollBar`) | views.inc | ~550 |
| `fv.dialogs` (new) | `TDialog : TWindow`, `TButton : TView`, `TStaticText : TView`, `TLabel : TStaticText`, `TParamText : TStaticText` (FormatStr = `printf -v`), `TCluster : TView`, `TCheckBoxes : TCluster`, `TRadioButtons : TCluster`, `TInputLine : TView` (+ password mask), `TListBox : TListViewer` (+ `Marks`), `THistory : TView`, `THistoryViewer : TListViewer`, `THistoryWindow : TWindow` | dialogs.inc | ~1350 |
| `fv.histlist` (new) | plain functions: `historyAdd ID TEXT`, `historyCount ID`, `historyStr ID INDEX`, `clearHistory` (FV HistList) | histlist.inc | ~80 |
| `fv.msgbox` (new) | plain functions | msgbox.inc | ~200 |
| `fv.menus` (+) | `TMenuView : TView`, `TMenuBar : TMenuView`, `TMenuBox : TMenuView`, `TMenuPopup : TMenuBox`, the helper `fv.menus.menuBar` (D23), the hint table `fv.menus.setHint SL HELPCTX TEXT` | menus.inc | ~650 |
| `fv.app` (+) | `InitMenuBar` unchanged by default (no bar, D23); when an override or the helper made a bar: row 0 is the bar, the desktop starts at row 1, resize keeps it | app.inc | ~40 |
| `fv.keyboard` / `fv.video` / `fv.drivers` (+) | layout-independent hot keys (§14), bracketed paste, cursor shape, OSC 52, evMouseAuto, fresh-row levers (§10) | — | §10 |

Not in P3: `TMultiCheckBoxes`, validators (`validate.pas`: FV's `TValidator` hierarchy; the
`Valid` hook is there, see §4.7), `TScroller` (no P3 widget needs it; the editor is after v1),
history saved to disk (FV keeps it in memory too).

### 1.2 Fields (FV's public fields, flattened)

| class | own fields | notes |
|---|---|---|
| TScrollBar | `Value Min Max PgStep ArStep Id` | `Chars` comes from the per-mode glyph table (§2.7); `Id` 0 = no `cmIdCommunicate` |
| TListViewer | `NumCols TopItem Focused Range HScrollBar VScrollBar List Formatter Marks` | `List` / `Formatter` replace FV's abstract `GetText` (P3-3); `Marks` (D26) = the name of an associative array or `''`; `LastY` is derived state |
| TDialog | — (TWindow's: `Palette` = `dpGrayDialog` 2 … with FV's values `dpBlueDialog 0 dpCyanDialog 1 dpGrayDialog 2`) | |
| TButton | `Title Command Flags AmDefault DownFlag` | `Flags`: `bfNormal 0 bfDefault 1 bfLeftJust 2 bfBroadcast 4 bfGrabFocus 8`; `sfDisabled` at Init when `Command` is disabled (dialogs.inc:2237-2238) |
| TStaticText | `Text` | `^C` centre / `^B` right justify per line as FV (`$'\x03'`, `$'\x02'`) |
| TLabel | + `Link Light` | `Link` = a view name |
| TCluster | `Id Value Sel EnableMask` (+ the items in `${v}_items`) | FV's `Strings` collection → per-instance array (kcl §1.9); `Id` ≠ 0 sends `cmIdCommunicate` on a value change (dialogs.inc:2640) |
| TInputLine | `MaxLen CurPos FirstPos SelStart SelEnd PasswordChar` (+ `${v}_cl`, `${v}_cw`) | FV's `Data` is the clusters; `fv.dialogs.getText IL` answers the string; `PasswordChar` (D29): `''` = plain, else every cluster drawn as that character |
| TListBox | — (`List`, `Marks` from TListViewer) | FV's `NewList` = `fv.dialogs.newList LB ARRAY [FMT]` |
| THistory | `Link HistoryId` | FV dialogs.inc:3873-3880 |
| THistoryViewer | `HistoryId` | a TListViewer over the history store |
| TMenuView | `ParentMenu Current OldItem` (+ the menu arrays, §7.2) | `Current` is a menu item index (TMenuView is a leaf: no clash with TGroup's `Current`) |

All counts stay within K-8's reach: the wrappers are `nofields`, so TButton's 18 or TListViewer's
22 fields cost nothing per call; only a user override binds them (P2 §1.2: ~3.5 µs per field per
nested call).

### 1.3 Virtuals (kklass, elided) and plain functions

* **Virtual** (one-line `nofields` wrappers; bodies in `__FV_VW_IMPL`; funcs in `__FV_VW_FUNC`):
  * TScrollBar: `Draw HandleEvent GetPalette ScrollStep (func) ScrollDraw`;
  * TListViewer: `Draw HandleEvent GetPalette SetState ChangeBounds FocusItem SelectItem IsSelected (func)`;
    FV's `GetText` is **not** virtual here (rule 2): the formatter is a
    plain function; a class that wants FV's virtual GetText per row pays it knowingly by giving
    `Formatter` a function that calls `$this.GetText` (documented, 3× cost, PLAN §2.1);
    `SetState` is FV's: a change of `sfSelected`, `sfActive` or `sfVisible` redraws the list and
    **shows its bars when the list is active and visible, hides them otherwise** (ShowSBar,
    views.inc:3817-3834);
  * TDialog: `HandleEvent GetPalette Valid CalcBounds`;
  * TButton: `Draw HandleEvent GetPalette SetState Press`;
  * TStaticText / TLabel: `Draw GetPalette GetText (func)`, TLabel `HandleEvent`;
  * TCluster: `Draw HandleEvent GetPalette SetState GetHelpCtx Mark (func) Press
    MovedTo`; TCheckBoxes / TRadioButtons override `Draw Mark Press (MovedTo)`;
  * TInputLine: `Draw HandleEvent GetPalette SetState Valid`;
  * every data-bearing view: `GetData SetData DataSize` (funcs; FV's virtuals, §4.6);
  * THistory: `Draw HandleEvent GetPalette InitHistoryWindow (func) RecordHistory`;
  * TMenuView: `Draw HandleEvent Execute (func) GetHelpCtx GetPalette NewSubView (func)`.
* **Answers of boolean virtuals** (`IsSelected`, `Mark`, `Valid`, `ButtonState`): **by rc**
  (0 = true), P2's func-by-rc rule; `RESULT` is not used by them.
* **Elision of per-item virtuals**: `Mark`, `IsSelected`, `GetItemColor` are called per item by
  FV's Draw. The built-in Draw tests the class's owner table once per Draw (one `_virt`-style
  lookup, ~20 µs) and runs a plain inline loop (reading `Marks` for the selected colour, D26) when
  the method is the built-in; only an override makes it dispatch per item (documented as "an
  override costs a dispatch per item").
* **Plain functions** (non-virtual FV methods + the data API), the view first; locals
  `__fvg_` (fv.dialogs), `__fvx_` (fv.msgbox), `__fvh_` (fv.histlist) — `__fvd_` and
  `fvd_testlib.sh` belong to fv.drivers (L5):
  `fv.views.scrollBarSet SB VALUE [MIN MAX PG AR]` (FV `SetParams`; `setValue setRange setStep`
  forms), `fv.views.listFocusItem LV I` (the num-checked FocusItemNum), `listSetRange`,
  `listSetTopItem`, `standardScrollBar W OPTIONS` → `RESULT` = the bar's name;
  `fv.dialogs.newList LB ARRAY [FMT]`, `getText IL`, `setText IL TEXT`, `selectAll IL 1|0`,
  `getData G ARRAY`, `setData G ARRAY` (walk the subviews and call each one's elided
  `GetData` / `SetData`), `setTitle BTN TEXT`, `setLabel LB TEXT`, `setItems CLUSTER ITEM…`
  (the setters keep the hot-key map current, §3.1), `setButtonState CLUSTER MASK 1|0`,
  `makeDefault BTN 1|0`, `newButton G X Y W H TITLE CMD HELPCTX FLAGS` … (FV's TDialog helpers
  `NewButton NewInputLine NewLabel`). Thin kklass aliases (D16) only for set-up code: `NewList`,
  `SelectAll` — **no** `GetData` / `SetData` alias, those names are the virtuals (L4).

### 1.4 Constructors (FV corners, FV argument order)

```bash
TDialog.new dlg 10 4 70 18 'Find'                      # FV Init(R, ATitle)
TInputLine.new find 14 2 56 3 255                      # Init(R, AMaxLen)   (user names: no __fv)
TLabel.new lfind 2 2 13 3 '~T~ext to find' find        # Init(R, AText, ALink)
THistory.new hfind 56 2 59 3 find 1                    # Init(R, ALink, AHistoryId)
TCheckBoxes.new opts 3 6 30 9 '~C~ase sensitive' '~W~hole words'   # Init(R, NewSItem(...))
TRadioButtons.new dir 32 6 56 8 '~F~orward' '~B~ackward'
TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"          # Init(R, ATitle, ACommand, AFlags)
TScrollBar.new sb 39 1 40 22                           # vertical when 1 wide (FV)
TListBox.new files 1 1 39 22 1 sb                      # Init(R, ANumCols, AScrollBar)
fv.dialogs.newList files FILES fmtFile                 # FV NewList(PCollection)
TStaticText.new msg 3 2 37 6 $'\x03'"Overwrite the file?"
TInputLine.new pw 14 6 40 7 64; pw_data[PasswordChar]='*'         # D29
```

FV's linked lists of items (`NewSItem`) are written flat after the bounds, as the status line
does. Each constructor refuses a malformed list before anything is made (rc 2, one `Error:`
line, fv.views' loud refusal).

### 1.5 Elision entries and the broadcast table

Each unit registers its built-in bodies (`fv.dialogs._register`, as `fv.menus._register`) and
its **broadcast reactions** in the new table (10.3):

| handler | reacts to broadcasts |
|---|---|
| TScrollBar | none (its `cmIdCommunicate` is a command) |
| TListViewer | `cmScrollBarChanged cmScrollBarClicked` |
| TButton | `cmDefault cmGrabDefault cmReleaseDefault cmCommandSetChanged` |
| TLabel | `cmReceivedFocus cmReleasedFocus` |
| THistory | `cmReleasedFocus cmRecordHistory` |
| TDialog | TWindow's (`cmSelectWindowNum`) |
| TCluster, TInputLine, TStaticText | none (TView's mask lacks evBroadcast: never reached) |
| TMenuView | `cmCommandSetChanged` |

A class that overrides `HandleEvent` is always called (the table only skips built-in handlers).

---

## 2. Drawing

### 2.1 The rules for every widget

1. **One composed write per row, one `writeLines` per paint.** Every Draw builds its rows as text
   + resolved symbols and writes them with `fv.views.writeLines` (several rows), `writeLine`
   (one row) or `writeRows` (rows in one symbol each, wide text: 10.2) — never a write per cell or
   per item part. Measured: a 21-row list costs ~3.7 ms per full draw at 80×24 here (same page;
   a fresh ASCII page 4.5 ms with its terminal output), a 1×21 bar ~3.5 ms; a one-row repaint
   ~0.85 ms through `drawPart`.
2. **Cache composed rows only where the inputs are few** (L6): a button's two rows keyed by
   (state colour, `DownFlag`, palette, `Title`, `SizeX`); a label's row by (`Light`, palette,
   `Text`, `SizeX`); the scroll bar's column by (palette, `SizeY`, thumb cell). Cluster rows are
   composed per draw (a draw happens on a key that changed them; a per-`Value` cache would grow
   without bound). Every widget cache entry of a view is dropped in fv.views' delete hook
   (fv.views.sh:856-860, next to the structure caches), so a name reused by a new view never
   sees old rows.
3. **Rule 4 everywhere a cursor moves**: list FocusItem, cluster Sel, menu box Current: the two
   changed rows through `drawPart` with the view's plain painter (the painter reads
   `FV_CLIP_Y1..Y2` and draws only those rows: one `writeLine`).
4. **Redraw only a changed picture** (P3-12, D17): a `SetState` side effect compares the inputs of
   the picture (the colour index chosen, `Light`, `AmDefault`, `Sel`) before and after and draws
   only when they differ. A framework sequence that changes two states of one view (the input
   line's sfSelected then sfFocused) draws **once at its end** — never skips the draw, because
   focus can change without a selection change (the dialog activated from outside).
5. **"Draw must cover its rect"** (P2): every row of the view is written (padding in the normal
   colour).

### 2.2 Lists (TListViewer, TListBox)

* Row text = FV's: column `J` at `J*ColWidth`, the item text from cell 1, cut to the column, the
  marker cells (`ShowMarkers` is false by default in FV: not drawn), the column divider `│` in
  colour 5 at the column's last cell (for `NumCols > 1`).
* Colours: `GetItemColor` as FPC 2025: focused and the list `sfSelected + sfActive` → 3,
  selected (`IsSelected`: the focused item, or `${Marks}[i]` set, D26) → 4, else 2; divider 5.
* **Narrow non-ASCII rows** (Cyrillic, Greek, Latin-1 names) keep the plain `writeLines` path:
  their cells equal their characters. What costs is fv.video meeting a row it never saw: today
  `_wrows` hands each such row to a full public `writeBuf` (guard, checks, text check, put):
  ~260 µs per fresh Cyrillic row, so a fresh Cyrillic page costs ~5.4 ms more than an ASCII one
  (§8.2). Lever **10.11** (fv.video): `_wrows` converts missed narrow rows itself, with **one
  text check over all missed rows of the call** (joined): measured 99 → 20 µs per row for the
  check (`p3/out_r2_*_san_x.txt`, both bashes), and no public entry per row.
* **Wide rows** (CJK, emoji): one composed row needs one symbol per *cell*, which a plain
  `${s:0:w}` cut cannot give. P3 adds a **uniform-symbol row writer** (10.2):
  `fv.views.writeRows X Y W TEXTS SYMS` — row k is `TEXTS[k]` in the single symbol `SYMS[k]`, cut
  or padded to W cells by fv.video's own cell walk (a wide character at the cut becomes a blank).
  The list picks it per paint when its rows hold any character outside the narrow set (one
  `__FV_VS_PNA`-style test over the joined rows). Without it a list would need `strWidth` per
  row (rule 2). Today a fresh CJK row costs **~2.2 ms** in fv.video's per-character walk and a
  cached one ~0.5 ms (the wide put path): lever **10.12** (a wide fast path, §10) is required for
  CJK pages to come near their target (§8.2).
* The vertical bar's value is `TopItem` (FPC 2025: `SetTopItem` moves the bar), its range
  `0 … Range − SizeY` (multi-column: FV's "last NumCols stay in view").
* **Bars follow the list's activity** (FV ShowSBar, views.inc:3817-3834): an inactive list hides
  its bars. In the two-panel scene only the active panel's bar is drawn; a panel switch shows one
  bar and hides the other (two bar draws, ~2 × 2.6 ms here, plus the hidden bar's repaint from
  below). The whole-scene repaint measured 1.31× the stand-in scene with both bars and 1.15× with
  the inactive one hidden (§8.5).

### 2.3 TScrollBar

* FV's look: `▲ ▒ ■ ▼` (`◄ ►` horizontal), `▓` when `Max = Min`; ASCII mode from the glyph table
  (§2.7). Colours CScrollBar `4 5 5` (page area 1, arrows 2, indicator 3).
* A vertical bar is a 1-cell column: one `writeLines` of 1-cell rows (measured 3.5 ms for a full
  21-row bar here; a fill + 3 writes measured 2.8 ms; the fixed `drawView` cost dominates, so the
  win is P3-4: draw it rarely). A horizontal bar is one `writeLine`.
* **P3-4 in numbers**: with 10 000 items the thumb moves one cell every ~500 items, so a list
  scroll almost never redraws its bar; when it moves: 2 one-row `drawPart`s (1.7 ms). The direct
  list → bar link (no `cmScrollBarChanged` walk back) holds only while the list's class keeps the
  built-in `HandleEvent` (one owner-table read); a list class with its own `HandleEvent` gets the
  broadcast as in FV (L7).
* `TWindow.StandardScrollBar` (views.inc:4091-4103) = `fv.views.standardScrollBar W OPTIONS`:
  `sbVertical` → the window's right frame column rows 1 … SizeY−2, else the bottom frame row
  columns 2 … SizeX−3; `sbHandleKeyboard` sets `ofPostProcess`; inserted; `RESULT` = its name.

### 2.4 Dialog controls

| control | FV look | writes per full draw |
|---|---|---|
| TButton | title centred (or `bfLeftJust`), `~` hot letter in the shortcut colour, a `▄` shadow cell and a `▀▀▀` row below (FV_UNICODE), pressed: shifted one cell right, no shadow | 1 (`writeLines`, 2 rows) |
| TStaticText | word-wrapped lines, `^C` / `^B` justification (FV_UNICODE algorithm: clusters and widths from fv.video) | 1 (`writeLines`) |
| TLabel | ` ~T~ext` with the light colours when the link is focused | 1 |
| TCheckBoxes / TRadioButtons | ` [X] Item` / ` (*) Item` per row (FV: `' [ ] '` + `' X'`, `' ( ) '` + `' *'`, dialogs.inc:2953-2956), FV's columns (`Column` / `Row`), the selected item in colour 2 when focused; **the hardware cursor on the selected item's mark** (`SetCursor(Column(Sel)+2, Row(Sel))`, dialogs.inc:2533-2535, 2715) | 1 (`writeLines`) |
| TInputLine | ` text…` with FV's `<` / `>` scroll arrows (dialogs.inc:1107) in colour 4, the selection in colour 3, the cursor at the cluster after `CurPos`; password mode: every cluster drawn as `PasswordChar` (one cell each) | 1 (`writeLine`) |
| THistory | `▐v▌` with `v` in colour 2 (FV `#222'~v~'#221`, dialogs.inc:3917; CHistory `22 23`) | 1 |
| TDialog | TWindow's frame (gray palette: CFrame through CGrayDialog) | 3 + shadow |

### 2.5 The cursor for TInputLine (D27)

* `sfCursorVis` set (FV). `CursorX` = 1 + the cells from `FirstPos` to `CurPos`; fv.views'
  `resetCursor` shows it when the line is focused and not covered (P2).
* **Insert / overwrite**: FV toggles `sfCursorIns` with Ins (dialogs.inc:2096-2097; overwrite =
  block cursor). fv.video's `setCursorType` sends only `?25h` today; P3 adds DECSCUSR: `ESC [ 4 q`
  (steady underline) for insert, `ESC [ 2 q` (steady block) for overwrite, sent only when the
  shape changes. At `doneVideo` and on every exit path (the traps that already restore the mouse
  and the alternate screen) `ESC [ 0 q`.
* **What `ESC [ 0 q` restores (M11):** the terminal's **default** shape (its configured cursor),
  for the rest of the session — not a shape the user's shell had set before (a vi-mode bar, a
  prompt's custom shape). Reading the current shape needs DECRQSS (`ESC P $ q SP q ESC \`) and a
  reply read, which xterm answers and many terminals do not; the design does not ask. Shells that
  set a shape per prompt (zsh / fish vi modes) set it again at the next prompt; a user who set
  one once by hand sees the terminal default after the program. Documented in fv.video's README.
* Terminals that do not know DECSCUSR ignore it (the Linux text console keeps its shape); xterm,
  Windows Terminal, mintty, VS Code, kitty, VTE and the new conhost know it.
* The cursor follows the cluster grid: after a wide character it stands on the cell after both
  halves.

### 2.6 Palettes (mapped to the app palette)

| class | FV palette (indices into the owner's) | in a gray dialog → CAppColor entries |
|---|---|---|
| TDialog | CGrayDialog `32 … 63` (blue 64–95, cyan 96–127) | — |
| TStaticText | `6 7 8 9` | 37 … 40 |
| TLabel | `7 8 9 9` | 38 39 40 40 |
| TButton | `10 11 12 13 14 14 14 15` | 41 … 46 |
| TCluster | `16 17 18 18 31 6` | 47 48 49 49 62 37 |
| TInputLine | `19 19 20 21 14` | 50 50 51 52 45 |
| THistory | `22 23` | 53 54 |
| TListViewer | `26 26 27 28 29` | 57 57 58 59 60 |
| THistoryViewer | `6 6 7 6 6` (in THistoryWindow `19 19 21 24 25 19 20`) | via the window |
| TScrollBar | `4 5 5` | 35 36 36 (in a dialog), 11 12 12 (in a blue window: CBlueWindow 8–15) |
| TMenuView | `2 3 4 5 6 7` | 2 … 7 (into the application directly) |

**A list in a plain window (D25).** FV's CListViewer points at entries 26–29, which a TWindow (8
entries) does not have, so FV shows ErrorAttr there. The built-in `GetPalette` of TListViewer
answers CListViewer when the owner's palette is long enough (a dialog) and the window's scroller
entries `6 6 7 2 6` (FV's CScroller `6 7`, as THistoryViewer uses: yellow on blue, the focused
row blue on grey in a blue window) otherwise. One test per owner kind; a subclass can answer
anything. Documented deviation.

The resolution walk and the cache are P2's (`__FV_VW_PAL`); a test compares each built-in's
resolved string with the FV bytes of CAppColor (as P2's 019 does for the frame).

### 2.7 ASCII mode: the widget glyph table (M8)

FV's LowAscii keeps the CP437 shades (views.inc:3110-3114: `('^','V', ▒, ■, ▓)`), which a DOS
console can show. fv.video's ASCII mode exists because the terminal cannot show non-ASCII at all,
and it maps only `▲^ ▼v ◄< ►> ■*`, box drawing to `- | + =`, everything else to `?` (fv.video
README "ASCII mode"). So every widget takes its glyphs from one per-mode table, chosen once per
screen (fv.video's mode is per screen, never per call):

| glyph | UTF-8 mode | ASCII mode |
|---|---|---|
| scroll arrows | `▲ ▼ ◄ ►` | `^ v < >` |
| scroll track / thumb / no range | `▒ ■ ▓` | `: # #` |
| button shadow cell / row | `▄` / `▀` | ` ` / ` ` (no shadow: FV's monochrome look) |
| check / radio marks | `[X]` / `(*)` | the same |
| input line arrows | `<` `>` | the same |
| history button | `▐v▌` | `[v]` |
| list divider, menu frames | `│`, box drawing | fv.video's `|`, `- | +` |
| password mask default | `*` | `*` |

**The input line in ASCII mode** counts cells as fv.video does there: every non-ASCII *character*
(one UTF-8 sequence) is one cluster of one cell shown as `?` — no width table, no joining —
`fv.video.clusters` answers exactly that in ASCII mode (10.1), so cursor, scrolling and the
screen agree. Tests run the widget suites once in ASCII mode (`FV_ASCII=1`).

---

## 3. Events

### 3.1 Focus between controls and hot keys

* **Tab / Shift+Tab, Up/Down/Left/Right**: TWindow's handler already does FV's `FocusNext`
  (P2 2c-3); TDialog inherits it. A control that uses arrows (cluster, list, input line) takes them
  first in the focused phase. **WordStar keys** go through FV's `CtrlToArrow` (drivers.inc:1282-
  1298: Ctrl+S/D/E/X/A/F/G/V/R/C/H → Left/Right/Up/Down/Home/End/Del/Ins/PgUp/PgDn/Back) wherever
  FV calls it: lists (views.inc:3878), scroll bar keys (3309, 3319), the input line (dialogs.inc:1994), clusters (2821), the menu loop (menus.inc:658-663), THistory's Down (3949) —
  one table read (`fv.views.ctrlToArrow`), no call per key.
* **Hot keys** (FV): a TLabel / TButton / TCluster in **pre-process** reacts to Alt + its letter;
  in **post-process** — when the owner's `Phase` is `phPostProcess` — to the plain letter
  (TButton dialogs.inc:2472-2474, TCluster 2853-2856, TLabel 3732-3734); **a focused cluster**
  also takes the plain letter in its own focused phase (2854-2855). Every such check goes through
  **one helper**, `fv.views.hotKeyIs LETTER` (rc 0 = the current key event is that hot key: Alt +
  letter, or the plain letter when the caller allows it), which matches by the typed character
  first and then by the base-layout key (§14, P3-13).
* **The hot-key map** (stage 3c, 10.3): each group keeps `${g}_hot[KEY]` → the views that declared
  that hot key, where KEY is the case-folded hot letter (Latin or not: `f`, `ф`). The pre/post
  scan of `_groupEvent` then calls:
  * the views the map names for the event's typed character and for its base key (§14), and
  * every pre/post-process view **without** a map entry (user classes, built-ins with pre/post
    work that is not a hot key: the status line, a menu bar, THistory),
  **in FV's order** — the group's Z order (pre-process from the front-most down, as FV's
  `ForEach`) — by walking the group's cached pre/post list once and skipping the mapped views the
  key does not name (an array read each). Before every call the owner's `Phase` is set
  (`phPreProcess` / `phPostProcess`), as FV does, because the widgets read it.
* **Keeping the map current (M5).** The map is built at `insert` and dropped at `delete` (with the
  structure caches); the setters `fv.dialogs.setTitle`, `setLabel`, `setItems` rebuild the
  entries of their view. A script that writes `${btn}_data[Title]` directly is caught by a
  stamp: each map entry keeps the text it was built from, and the walk, before it skips a
  mapped view, compares that text with the view's current field (one string comparison per
  mapped view per key, ~1 µs) and rebuilds the entry when they differ. `__FV_VW_OEX` (shape
  only) is not used for this. Documented: "set titles with the setters; a direct write costs
  one rebuild on the next key".
* **Measured (upper bound, M2)**: removing pre/post-processing from the six labelled controls
  altogether (`emul/nopp.txt`) took a typed character from 5.93 to 4.44 ms and a Tab from 14.96 to
  13.86 ms (revision 1, laptop). The map keeps the hot-key work for the views a key names, so its
  saving is somewhat below that: "up to ~1.5 ms per key in an 8-control dialog".
* **Mouse**: click to focus (P2) + each control's own tracking. **A click does not focus a
  TButton** unless it has `bfGrabFocus` (FV calls the inherited focus handling only then,
  dialogs.inc:2447-2448): pressing OK with the mouse leaves the focus in the input line.

### 3.2 Default and cancel buttons, the modal loop

* Enter in a dialog → `evBroadcast cmDefault` posted; the button with `AmDefault` presses. **A
  focused button presses on Enter or Space directly** (dialogs.inc:2475-2477), before the dialog
  sees Enter. `Press` = FV's (dialogs.inc:2290-2300): first `cmRecordHistory` to the owner (every
  THistory records its line, D28), then `evCommand Command` posted with `FV_EV_INFO` = the button,
  or a broadcast of `Command` with `bfBroadcast`. A focused non-default button grabs the default
  while focused (FV MakeDefault: `cmGrabDefault` / `cmReleaseDefault`).
* **Disabled commands**: a button whose command is disabled at Init starts `sfDisabled`
  (dialogs.inc:2237-2238) and follows `cmCommandSetChanged`.
* Esc / Ctrl+F4 → `cmCancel` posted; `cmOK cmCancel cmYes cmNo` → `endModal` when modal (TDialog).
  `Valid(cmCancel)` is always true (FV), other commands ask the subviews (TInputLine's validator
  hook, §4.7).
* **The modal loop** is P2's `execView` + TGroup.Execute (event record saved, EOF latch, BASHPID
  rule). The pattern: `TDialog.new dlg …; fv.views.execView "$FV_DESKTOP" dlg; [[ $RESULT == cmOK
  ]] && fv.dialogs.getData dlg REC; dlg.delete`. A resize during the modal loop is handled inside
  `getEvent` as in P2 (fv.app 004 "mid-modal") and gets a widget test (§9.1).
* **Ctrl+F5** in a modal dialog → `cmResize` (keyboard move), FV.

### 3.3 Mouse: clicks, wheel, auto-repeat

* **Wheel** (evMouseWheel, FV's EventMask bit): lists scroll their top item by 1 (a double wheel
  event — fv.drivers' `FV_EV_MOUSE_DOUBLE` — by 4: FV), multi-column by a column; a scroll bar by
  `ArStep` (double: 6, FV). The positional routing (P2) gives the wheel to the front-most view under
  the pointer whose mask has the bit.
* **Clicks**: a list row focuses that item (double click → `SelectItem` → `cmListItemSelected`
  broadcast); a button tracks the press (pressed look while the pointer is on it, `Press` on a
  release on it); a cluster item selects on the release on it; a label focuses its link; the input
  line places the cursor (double click → select all) and drag-selects; THistory opens its window.
* **Keys in lists** (views.inc:3874-3890): **Space → `SelectItem(Focused)`**; Up / Down / PgUp /
  PgDn (by `Size.Y * NumCols`) / Home / End; Left / Right by a column when `NumCols > 1`;
  **Ctrl+PgUp → the top item of the page, Ctrl+PgDn → its bottom item**; through `CtrlToArrow`.
* **Auto-repeat** (P3-8): fv.drivers' `getEvent`, on its idle timeout while a button is held
  (`__FV_DR_*` held buttons ≠ 0) and the last mouse event is older than the delay, answers
  `evMouseAuto` at the last position (`FV_EV_MOUSE_*` copied). `fv.views.mouseEvent V MASK` with
  `FV_EM_MOUSEAUTO` then sees it (P2's loop already filters by mask). Users: TScrollBar (arrows /
  page area repeat while held; FV `Until NOT MouseEvent(Event, evMouseAuto)`), TListViewer (drag
  past the edge scrolls every 4th auto, FV `MouseAutosToSkip`), TInputLine (drag-scroll).
  **A lost release cannot run away (L2):** any key event, any press and any report with no button
  held end the held state, so the next idle tick produces no `evMouseAuto`.

### 3.4 Broadcast traffic (measured)

A Tab between two dialog controls costs ~3.3 `message` calls (the two focus broadcasts, the
button's grab/release default) and ~4.7 `drawView`s with FV's eager redraws (revision 1, 12 hops
counted). The broadcast table (§1.5) keeps broadcasts nobody reacts to from being dispatched;
rule 4 of §2.1 removes the redraws whose picture did not change (a label whose link did not change
focus, a button that keeps its colours, the input line drawn once at the end of its sequence).

**Coalesced child redraws (10.4) are dropped from 3a (M2).** Revision 1 credited them with
−0.9 ms per Tab and −3 ms per open + close, but `emul/coal.txt` also removed the input line's
sfFocused draw (that is P3-12's "once at the end", and the draw itself is needed). What 10.4
alone buys is the sfActive redraws of the controls during a dialog's activation, ~3 ms per open +
close (critic's estimate), ~5 % of it. It returns only if the 3c CI A/B misses the dialog range.

---

## 4. TInputLine

### 4.1 The text model

* **Clusters, not characters.** `${v}_cl[i]` = cluster i (a base character with its zero-width
  followers, a ZWJ sequence, a flag pair, a VS16 emoji), `${v}_cw[i]` = its cells (1 or 2). The
  split comes from **`fv.video.clusters TEXT CL CW`** (10.1), the same walk fv.video's writes use,
  so the line and the screen agree on every cell — including D14 (VS16 after a narrow
  pictographic base = 2), Cygwin-family bash, where a character past U+FFFF is two bash
  characters (fv.video already walks those on bytes), and ASCII mode (one cluster of one cell per
  character, §2.7).
* `CurPos FirstPos SelStart SelEnd` are **cluster indices**. **Deviation (M7):** FV moves `CurPos`
  by one character — one UTF-16 unit in the FV_UNICODE build (`kbLeft: Dec(CurPos)`, `kbRight:
  Inc(CurPos)`, dialogs.inc:2028-2032; Backspace / Delete take one unit, 2077-2094), so FV can
  stop inside a surrogate pair or a cluster. Here the cursor never splits a cluster; the
  behaviour differs only for text with clusters. `MaxLen` counts clusters (FV: UTF-16 units;
  bash has no such unit). Documented in fv.dialogs' README.
* **Fast path**: an ASCII printable key (`[ -~]`) between two ASCII clusters inserts a 1-cell
  cluster without any call.
* **Re-split after non-ASCII edits (M6).** Joining is not local to "the previous cluster + the new
  character": a ZWJ, VS16 or a skin-tone modifier typed in the middle joins the clusters on both
  sides; a regional indicator re-pairs the whole run of regional indicators after it; deleting a
  ZWJ or one indicator splits or re-pairs its neighbours. So after **every insert of a non-ASCII
  character and every delete next to a non-ASCII cluster**, the line takes the window
  [the cluster before the edit … the cluster after it], widens it to the whole run when either
  end is a regional indicator (the run is bounded by its own length), joins the window's text and
  re-splits it with one `fv.video.clusters` call, replacing the window's entries in both arrays.
  One call per such edit (~40–200 µs for a few characters; `charClass` alone 36 µs, a CJK
  `strWidth` of 12 characters 200 µs, revision 1 direct timings). `CurPos` moves to the end of
  the cluster that holds the inserted character. `008_InputWide` covers joiners, VS16, modifiers
  and flags typed and deleted mid-line, against a whole-line re-split after every step.
* `fv.dialogs.getText IL` / `setText IL TEXT` (FV `GetData` / `SetData` for a string): the join of
  `${v}_cl` / a new split. The array form costs an O(n) splice per edit (bash re-copies the array);
  measured: typing into a 70-character line 8.18 ms against 6.68 ms into an empty one (laptop,
  this run) — accepted (MaxLen is usually ≤ 255), a gap buffer is not worth it in bash.

### 4.2 Editing (FV's key set)

| key | action (FV) |
|---|---|
| printable / `kbChar` | delete the selection, then insert (insert mode) or replace the cluster at the cursor (overwrite, `sfCursorIns`); `MaxLen` respected |
| `kbLeft kbRight kbHome kbEnd` (+ WordStar Ctrl+S/D/A/F through `CtrlToArrow`, dialogs.inc:1994) | move by one cluster / to the ends |
| `kbCtrlLeft kbCtrlRight` | FPC 2025's word moves (its delimiter set) |
| `kbShift…` of the above | extend the selection from the anchor (FV: pad keys with Shift); fv.keyboard names them `kbShiftLeft` … `kbCtrlShiftLeft` |
| `kbBack kbDel` (+ Ctrl+H / Ctrl+G) | delete the selection, else the cluster before / at the cursor |
| `kbIns` (+ Ctrl+V through `CtrlToArrow`) | toggle `sfCursorIns` (the cursor shape: D27) |
| `Ctrl+Y` | clear (FV `^Y`) |
| `kbCtrlIns kbShiftDel kbShiftIns` | copy / cut / paste (§4.5) |
| `evCommand cmPasteText` | insert the pasted text (bracketed paste, §4.5) |
| mouse | click = cursor, double click = select all, drag = select (auto-repeat scrolls past the edges), a click on an arrow cell scrolls |

Note: FV's `CtrlToArrow` turns **Ctrl+V into Ins** (drivers.inc:1285-1288), so Ctrl+V cannot be a
paste key in an FV input line; §4.5 says what pastes instead.

After each key: the selection collapses (or follows the anchor), `FirstPos` follows FV's rule —
**the text from `FirstPos` to `CurPos` fits in `Size.X − 3` cells** (FV: `TextWidth(OldData) >
Size.X − Delta − TextWidth(LeftArr) − TextWidth(RightArr)` with `Delta = 1` and one-cell arrows,
dialogs.inc:2164-2171; revision 1 wrote "− 2") — computed from `${v}_cw` cumulatively: O(visible),
not FV's O(n²) `TextWidth` loop; then one `drawView` (one `writeLine`) and the cursor placed.

### 4.3 SelectAll and focus

FV's `SetState`: `sfSelected` (or `sfActive` while selected) → `SelectAll(Enable)`; `sfFocused` →
redraw. P3 draws once per change sequence (P3-12): the framework sequence that sets sfSelected then
sfFocused draws the line once at its end; a focus change alone (sfFocused without sfSelected, the
dialog activated from outside) draws it too.

### 4.4 Scrolling and wide characters

* The visible part starts at cluster `FirstPos`; a wide cluster never straddles the right edge
  (the row stops one cell early and pads; FV_UNICODE does the same: `break` when it does not fit).
* `<` in cell 0 when `FirstPos > 0` and focused, `>` in the last cell when clusters remain (FV's
  `LeftArr` / `RightArr`, dialogs.inc:1107).
* **The wide-row repaint cost**: fv.views repaints a screen row with wide cells across the whole
  width on a rectangle repaint (P2 "Wide characters and repaint edges"). Typing CJK into a dialog
  over two windows: **11.22 ms against 6.68 ms** for ASCII and 7.03 ms for Cyrillic (this run;
  ratio 1.68 to ASCII; revision 1 12.2 against 5.9). The same effect doubles the stand-in's PgDn
  beside a CJK list (15.1 against 8.8 ms, `out_r2_gb_list_cjk.txt`). Lever (10.5): repaint widely
  only when a wide pair straddles the repainted rectangle's edge (two cell reads per row edge);
  the typed line itself never cuts one.

### 4.5 Clipboard and paste (D24)

* **Internal clipboard** (FV's `Clipboard` when no system one): a process-wide string
  `FV_CLIPBOARD`. Ctrl+Ins copies the selection, Shift+Del cuts, Shift+Ins pastes it (FV maps
  Shift+Ins to `cmPaste`, dialogs.inc:1941-1957).
* **System clipboard out (OSC 52)**: every copy and cut also sends `ESC ] 52 ; c ; BASE64 BEL`
  through fv.video (`fv.video.setClipboard TEXT`, pure-bash base64 of at most `FV_PASTE_MAX` bytes,
  linear — 3dfix F3; FPC's fvclip.inc does the
  same). Windows Terminal, mintty, kitty, WezTerm, foot, iTerm2 and VS Code accept it (some ask
  once); xterm accepts it only with `allowWindowOps` / `disallowedWindowOps` changed (off by
  default); VTE (GNOME Terminal) ignores it; tmux passes it with `set-clipboard on`. A terminal
  that ignores it leaves the internal clipboard as the only one.
* **Paste in = what the terminal types, framed by bracketed paste.** `ESC [ ? 2004 h` at
  `initVideo`, `ESC [ ? 2004 l` at `doneVideo` and on every exit path; the frame `ESC [ 200 ~` …
  `ESC [ 201 ~` is decoded by fv.keyboard into **one** event, FV's `evCommand cmPasteText` with the
  text (FPC 2025 has exactly this, dialogs.inc:1953 / drivers.inc:1526), and the input line
  inserts it with newlines dropped (FV). Without a frame (a terminal without bracketed paste) a
  pasted newline is `kbEnter` and would press the default button mid-paste: those terminals are
  rare today (all of the above, xterm and the Linux console support it).
* **Which keys reach the program (M11)** — the terminals take some of FV's keys for themselves:

  | key | Windows Terminal | mintty (Git-bash) | xterm | GNOME Terminal (VTE) | kitty | Linux console |
  |---|---|---|---|---|---|---|
  | Shift+Ins | its own paste (system clipboard) → one `cmPasteText` | its own paste → one `cmPasteText` | pastes PRIMARY → one `cmPasteText` | its own paste → one `cmPasteText` | pastes the selection → one `cmPasteText` | reaches the program: `cmPaste` (internal) |
  | Ctrl+Ins | copies the terminal's selection when there is one (believed to pass the key on otherwise — to confirm live) | copies the terminal's selection | reaches the program: copy | reaches the program: copy | reaches the program: copy | reaches the program: copy |
  | Shift+Del | reaches the program: cut | reaches the program: cut | reaches the program: cut | reaches the program: cut | reaches the program: cut | reaches the program: cut |
  | Ctrl+Shift+V / right click | paste → one `cmPasteText` | paste (right click: config) → one `cmPasteText` | — / middle click PRIMARY | paste → one `cmPasteText` | paste → one `cmPasteText` | — |

  So in practice: **copy** = Ctrl+Ins where it arrives (and the terminal's own copy of a
  shift-drag selection everywhere), and every copy also goes to the system clipboard by OSC 52;
  **cut** = Shift+Del everywhere; **paste** = the terminal's paste (Shift+Ins, Ctrl+Shift+V,
  right click), which brings the system clipboard — and so also what the program copied by OSC
  52 — as one bracketed paste event. The internal clipboard's own paste (`cmPaste`) is reached by
  Shift+Ins only where the terminal does not take it (the Linux console), and through the menu's
  `Edit → Paste` item (FV's standard Edit menu binds `cmPaste`, app.inc:1375-1377). Under
  bracketed paste, WT's Shift+Ins is one paste event, never key presses. The README documents
  the table; the 3d live check confirms the WT Ctrl+Ins case.
* Sizes: fv.video enable / disable + restore on every exit path ~15 lines; fv.keyboard frame
  decoding with a size cap (default 64 KiB, the rest dropped with a debug line) ~60 lines; OSC 52
  ~40 lines.

### 4.6 Data transfer

`fv.dialogs.getData G ARRAY` / `setData G ARRAY` (FV `TGroup.GetData` / `SetData`): an indexed
array, one element per data-bearing subview **in FV's order** (insertion order): an input line →
its text, a cluster → `Value`, a list box → `Focused` (its `List` stays the caller's array), a
static text → nothing (FV `DataSize` 0). The plain functions walk the subviews and call each one's
`GetData` / `SetData` / `DataSize` — FV's virtuals, elided for built-ins; a user class takes part by
overriding them (`DataSize`: 0 = none, 1 = one element). There is no kklass alias named `GetData`
or `SetData` (L4). Named access stays direct: `fv.dialogs.getText find`, `${opts_data[Value]}`.

### 4.7 Validation

`Valid(CMD)` keeps FV's shape (P2's func-by-rc rule). P3 ships no `TValidator` classes; a user
validator is a TInputLine subclass overriding `Valid` (or a plain function name in an optional
`Validator` field called as `FN TEXT` → rc, documented). FV's `TPXPictureValidator` & co. are after
v1.

### 4.8 Password mode (D29)

* A field `PasswordChar` (`''` = plain). When set, Draw shows every cluster as that one-cell
  character (the cells count one per cluster, so wide input does not reveal its shape), the
  selection colour still shows, and the cursor stands after `CurPos` masked clusters.
* Copy and cut are refused in password mode (no clipboard, no OSC 52); paste in is allowed.
* `getText` answers the real text; THistory does not record a password line (its
  `RecordHistory` skips a link with `PasswordChar` set).
* P4's one-shot `password` dialog is an inputBox with the mask (`fv.msgbox.inputBox … -p`, §6).
* Cost: one branch in Draw (~20 lines + tests in 007).

---

## 5. Lists: the data model

* `List` = the **name of an indexed array** the caller owns (`FILES`), `Range` = its length at
  `newList` / `setRange` (the caller calls `fv.views.listSetRange LV N` or `newList` again after
  changing it — FV's `SetRange`). Sparse indices are not supported (documented).
* `Formatter` = an optional **plain function** `FMT INDEX WIDTH` → `RESULT` = the row text (FV's
  `GetText(Item, MaxLen)` as a plain call: ~5 µs + its body per visible row, no dispatch). Without
  one, the element itself is the text.
* **`Marks` (D26)** = the name of an associative (or indexed) array the caller owns, or `''`:
  `MARKED[17]=1` shows item 17 in the selected colour (4). The built-in Draw reads `${Marks}[i]`
  inline per visible row (an array read, no call), so PgDn costs what it costs without marks
  (the 3b bench checks it: `list.pgdn` with 50 % of the rows marked ≤ 1.05× unmarked). FV's
  `IsSelected` stays a virtual: a class that overrides it is asked per row (one dispatch per drawn
  row, documented) and wins over `Marks`. Changing marks: the caller sets the array and calls
  `fv.views.drawView LV` (or `fv.views.listDrawItem LV I` for one row: rule 4).
* **A long checklist (D29)** is a TListBox with `Marks` and a key binding: Space toggles
  `${Marks}[Focused]` and redraws that row (FV's Space → `SelectItem`, views.inc:3874-3877; the
  built-in `SelectItem` toggles the mark when `Marks` is set and then broadcasts
  `cmListItemSelected` as FV), Insert toggles and moves down (the file-manager habit; documented
  addition). Any number of items (TCheckBoxes holds 32: `Value` is a 32-bit mask). P4's
  `checklist` face uses it; `fv.dialogs.getData` of such a list answers `Focused`, the marks stay
  in the caller's array.
* 10 000 items cost nothing extra: the Draw touches only the visible rows; `End` / `Home` jump in
  one `FocusItem` (measured `end-home` 11.3 ms here on cached pages, a full redraw each way).

---

## 6. fv.msgbox

```bash
fv.msgbox.messageBox 'File not found: %s' $(( FV_MF_ERROR | FV_MF_OKBUTTON )) -- "$f"
[[ $RESULT == cmOK ]]
fv.msgbox.messageBox 'Save changes?' $(( FV_MF_CONFIRMATION | FV_MF_YESNOCANCEL ))
case $RESULT in cmYes) save ;; cmNo) ;; cmCancel) return ;; esac
name='untitled.txt'
fv.msgbox.inputBox 'Save as' '~N~ame' name 80 && [[ $RESULT != cmCancel ]] && save "$name"
fv.msgbox.inputBox -p 'Login' '~P~assword' pass 64        # password mode (D29)
```

* `messageBox MSG OPTIONS [-- PARAMS…]`: FV's `MessageBox(Msg, Params, AOptions)`; **OPTIONS is
  one integer**, the flags OR'd (L4): a 40×9 TDialog centred on the desktop (on the application
  with `mfInsertInApp`), titled Warning / Error / Information / Confirm (`mfWarning 0 …
  mfConfirmation 3`), a TStaticText (`Msg` through `printf -v` with PARAMS: FV's `FormatStr`), the
  buttons for `mfYesButton $100 mfNoButton $200 mfOKButton $400 mfCancelButton $800`
  (`mfYesNoCancel`, `mfOKCancel`) placed as FV does, the first selected; `RESULT` = the command
  (`cmCancel` on Esc or at the end of input).
* `messageBoxRect AX AY BX BY MSG OPTIONS [-- PARAMS…]`: an explicit rectangle.
* `inputBox [-p] TITLE LABEL VARNAME LIMIT` / `inputBoxRect …`: FV's 60×8 dialog with a TLabel, a
  TInputLine (`LIMIT` clusters; `-p`: `PasswordChar='*'`), OK (default) and Cancel; the variable
  named VARNAME is read as the initial text and set to the result unless cancelled (FV's
  `var S`); `RESULT` = the command. VARNAME is checked like fv.views' array names (no `__fv*`, not
  `RESULT`).
* Button labels and titles are variables (`FV_MSGBOX_TITLES`, `FV_MSGBOX_BUTTONS`) so a script can
  translate them (FV's resourcestrings).
* **Each call builds, runs and destroys its dialog** (FV) under a reserved name
  (`${desktop}__fvmsgbox`, nested boxes get a depth suffix), so a box opened from a `Valid`
  handler works (P2's EOF latch makes a box at the end of input answer `cmCancel` at once).
  **Measured end to end (M3)** with a stand-in (dialog + text + OK: 3 objects built, `execView`,
  Ctrl+F4, 3 destroyed) inside a Run over two windows: **52.2 ms** laptop on both bashes
  (10 dispatches: the app's `TMyApp` + inherited for the key and the focus broadcasts; 13
  writes); ratio 9.3 to `standin.down` → **~34–46 ms CI** (§8.3).
* `$(fv.msgbox.messageBox …)` is refused by the BASHPID rule (P2: `execView` in a subshell),
  rc 2 with one `Error:` line; tested (§9.1).
* Before an application runs (no `FV_DESKTOP`): rc 2 and a debug line. Face C (P4) is the
  "no application" form.

---

## 7. Menus (D22, D23)

### 7.1 The bar only on request (D23)

* **Default: no bar.** `TProgram.InitMenuBar` keeps making nothing, `FV_MENUBAR` stays `''`, the
  desktop keeps row 0. P2's tests, the bench scenes and the first-paint baselines do not change.
  Documented deviation: FV's `InitMenuBar` always makes a one-row `TMenuBar` with no items
  (app.inc:958-964), which shows as an empty top row.
* **An application that wants a menu** either overrides `InitMenuBar` (FV's way: make a
  `TMenuBar` on the extent's first row and set `FV_MENUBAR`) or calls the **one-call helper** in its
  `InitMenuBar` or before `Run`:

  ```bash
  fv.menus.menuBar \
      sub '~F~ile' \
          item '~O~pen…' F3 kbF3 cmOpen hcOpen \
          item '~S~ave' F2 kbF2 cmSave hcSave \
          line \
          item 'E~x~it' Alt+X kbAltX cmQuit hcExit \
      end \
      sub '~W~indow' \
          item '~N~ext' F6 kbF6 cmNext hcNext \
          sub '~L~ayout' item '~T~ile' '' '' cmTile 0 item '~C~ascade' '' '' cmCascade 0 end \
      end
  fv.menus.setHint "$FV_STATUSLINE" hcOpen 'Open a file'     # the hint table (D22)
  ```

  (FV's `NewSubMenu` / `NewItem` / `NewLine` written flat, as the status line's items.) Then row 0
  is the bar, the desktop is moved to row 1 (`fv.views.locate`), and a resize keeps that layout.
  Calling it twice replaces the bar; `fv.menus.menuBar` with no items removes it and gives row 0
  back.
* Cost when not used: none (no view, no row, no event pre-processing).

### 7.2 Model

* **Items flat in per-instance arrays** (like TStatusLine): `${m}_mtext ${m}_mparam ${m}_mkey
  ${m}_mcmd ${m}_mhelp ${m}_msub ${m}_mdis` per item, `${m}_mfirst/_mlast` per (sub)menu, a
  submenu = an index range in the same arrays; `Default` per submenu.
* **Key map**: `${m}_mkeymap["kbF3"]` → the item (FV's `HotKey` walks every item recursively on
  every key the bar pre-processes, menus.inc:873-898: here one lookup); `${m}_mhot["sub:f"]` →
  the item with hot letter `f` in that submenu (FindItem), keyed by the case-folded hot letter so a
  Cyrillic `~Ф~айл` is found too.
* **Hot letters and the layout** follow FPC 2025 (menus.inc:680-735, 995-1024): with Alt, first
  the typed character, then the scan-code letter (`GetAltChar(ScanCode)`, "fallback for EN hotkeys
  in RU layout"); here the second step is the base-layout key of §14 (`FV_KEY_BASE`), through the
  same helper as every other hot key. Without Alt, inside an open menu, the typed character (and
  §14's base key).
* **TMenuBar** (`ofPreProcess`, `gfGrowHiX`): Alt+letter → the submenu; a mapped key → its
  command posted; **`cmMenu`** (F10 through the status line, fv.app's StdStatusKeys) → FV's
  `DoSelect` (menus.inc:977-987): the event is put back, the bar runs modal through **its owner's
  `execView`** (the application), and a command it answers is posted. `cmCommandSetChanged` →
  items greyed, redrawn only if a greyed state changed. Draw = 1 write (as the status line).
* **TMenuBox** (`sfShadow`, `ofPreProcess`): sized by its items (FV), placed under the bar item,
  clipped to the owner; **created by `NewSubView`, executed by the bar's owner and disposed per
  drop** (menus.inc:757-768: `Owner^.ExecView(Target)`, `Dispose(Target, Done)`), so the box lives
  in the application, beside the desktop, never inside a window. Draw = one `writeLines`; a
  highlight move = 2 one-row `drawPart`s (FV's OldItem trick); submenus nest the same way (each
  level saves / restores the event record).
* **Execute** = FV's TMenuView.Execute loop (menus.inc:538-780): mouse tracking across the bar and
  the boxes, arrows (through `CtrlToArrow`), Home / End, Enter, **Esc**: in a box under the bar
  it closes the box **and the bar** (menus.inc:673-676: a box whose parent is the bar leaves the
  Esc in the event, the loop puts it back and the bar reads it), in a nested box it closes only
  that box (its parent is a box: the Esc is cleared), on the bar alone it leaves the bar (stage 3f
  review: revision 2 said "a box returns to the bar, Esc again leaves the bar", which is not
  FV), hot letters, Alt+letter to the top menu, the
  F-key fallback (`TopMenu^.HotKey`, menus.inc:731). **F10 inside an open menu does nothing** in
  FPC — it falls to `HotKey`, which finds no item with F10 — and so here (revision 1's prototype
  closed on F10, `proto_w.sh:808`: wrong). Reads through `__FV_VW_GETEVENT` (sees resizes and the
  EOF latch: the EOF closes every level with no command; a subshell refuses by the BASHPID rule).
* **The status line interplay (D22)**: while a menu runs it is the top view; FV's `Idle` runs
  between keys (no event) → `fv.menus.update` asks `GetHelpCtx` → TMenuView's (the current item's
  `HelpCtx`, walking up the parent menus, menus.inc:790-800) → the status line shows that
  context's def and **hint**. The hint comes from a **built-in hint table**,
  `fv.menus.setHint SL HELPCTX TEXT` (the built-in `Hint` reads `${sl}_hints[ctx]`; no subclass,
  no dispatch); a `Hint` override still works. Measured: a highlight move with a hint change
  6.05 ms, without 4.55 ms (laptop, §8.4).
* **Focus broadcasts reach the application.** The bar and each box are made current in the
  application by `execView`, so FV's `cmReleasedFocus` / `cmReceivedFocus` go to the
  application's `HandleEvent`: with a `TMyApp` override, open + drop + close costs **22
  dispatches**, 14 of them these broadcasts (7 broadcasts, each `TMyApp.HandleEvent` + its
  `inherited`), measured in stage 3f (bench `menu.80x24.open-drop-close`; the test
  `014_MenuBudget` logs 23 because it also counts its own `app.Run` call). Revision 2 counted 19:
  it left out the box's 3 kklass dispatches (its constructor, its `Done` and the `inherited` in
  `Done`: the box is made and destroyed per drop). The 22: 2 F10 + 2 `cmMenu` + 14 broadcasts + 3
  the box + 1 user `Draw` below the box. FV does the same; the README says that an application
  `HandleEvent` override sees every menu open (a cost of ~0.2 ms per dispatch).
* **TMenuPopup** (FV): a box without a parent for context menus (right click in the file manager),
  executed by the view's owner.

### 7.3 Size

fv.menus +~600 lines (TMenuView model and Execute ~250, TMenuBar ~80, TMenuBox ~120, TMenuPopup
~40, the key map ~60, the helper and the hint table ~50), fv.app +~40 (row 0 when a bar exists,
resize), tests ~500 lines (8 files, §9.1). Risk: the menu's own Execute loop is a fourth inner
loop (after execView, mouseEvent, dragView): it saves / restores the event record and honours the
EOF latch and the BASHPID rule like the others (P2 §2.2).

**Measured (stage 3f with its review fixes, 2026-11-22):** the menus part of `fv.menus.sh` is
1235 lines, 946 of them code (blank and comment lines left out), against ~600 estimated: FV's
Execute with all its mouse cases, the layout-aware hot letters (§14.4), the item-list parser with
its refusals, the one-pass mouse tracking and the caller-state guards (IFS, `RESULT`) were larger
than planned. fv.app +9 / -2 lines (not ~40: the row-0 work sits in `fv.menus.menuBar`, and
`InitDesktop` already left row 0 to a bar). Tests 904 lines in 10 files (fv.menus 009-017, fv.app
016).

---

## 8. Call budget and time

Prototype scenes (Appendix A): **list** = the application, a gray-palette panel (TDialog used
non-modally) with a 60 000-item TListViewer and its vertical bar on the left half, the bench's
stand-in window on the right half; rows ASCII (`file_report_N.txt   SIZE`), Cyrillic
(`Отчёт_квартал_N.txt   SIZE`) or CJK (4 CJK characters + `_N.txt   SIZE`, padded to the row's
cells); **every Run starts on a fresh page** (400 items further), so fv.video's text cache never
saw the rows (H1). **dialog** = two windows side by side and a modal 60×14 dialog (2 labels, 2
input lines, 3 check boxes, OK (default) / Cancel / Help) opened by F2 in `TMyApp`. **msgbox** =
the same two windows; F3 builds + runs + destroys a messageBox stand-in, F4 the 8-control dialog.
**menu** = FV's layout with a bar (D23): the desktop from row 1 with two stand-in panels, a
`TPMenuBar` on row 0 in the application, a 28×12 box with a shadow dropped under "File"; F10 →
status line → `cmMenu` → the bar → Down drops the box → (Esc, Esc: the probe sends Ctrl+F4 as the
Esc stand-in, because a lone ESC costs the Esc timeout and two decode as `kbAltEsc`). `TMyApp`
overrides `HandleEvent` with `inherited` (the bench's 2 dispatches per event that reaches the
application). Method and calibration: the header.

### 8.1 Dispatches and writes per action (exact, counting shims)

| action | dispatches | fv.video writes | proposed test limit (dispatches / writes) |
|---|---|---|---|
| list Down, inside the page (2 rows) | **2** (TMyApp + inherited) | 2 | 6 / 2 |
| list scroll by Down at the bottom, P3-4 bar: ASCII / fresh Cyrillic, CJK today | 2 | 1 / **22** (one `writeBuf` per fresh non-ASCII row inside `_wrows`) | 6 / 3 (after 10.11 / 10.12 for every kind) |
| list PgDn, FV-exact bar: ASCII / Cyrillic / CJK | 2 | 2 / 23 / 45 | — |
| list PgDn, P3-4: ASCII / Cyrillic / CJK | 2 | 1 / 22 / 22 | 8 / 3 (after the levers) |
| list wheel (1 row) | 2 | 1 | 6 / 3 |
| list click on a row | 2 | 2 | 8 / 2 |
| list End (10 000 items) | 2 | 1–3 | 6 / 3 |
| (stand-in Down / PgDn, for comparison) | 3 / 4 | 2 / 1 | |
| Tab between two dialog controls (modal dialog) | **0** | 6 (4.7 `drawView`s, 3.3 `message`s per hop) | 4 / 8 |
| typing a character into an input line | **0** | 1 | 2 / 2 |
| Shift+Left (extend the selection) | 0 | 1 | 2 / 2 |
| dialog open + close, pre-built (F2 … Ctrl+F4) | 2 | 23 | 6 / 30 |
| messageBox stand-in end to end (build, run, close, destroy) | 10 | 13 | 16 / 20 |
| 8-control dialog end to end (build, open, close, destroy) | 22 | 19 | 30 / 26 |
| the dialog's full draw (`drawView dlg`) | 0 | 21 | 2 / 24 |
| menu: F10, drop the box, close both (FV flow, `TMyApp` override) | 19 (2 F10 + 2 `cmMenu` + 14 focus broadcasts + 1 user Draw below; measured in stage 3f: 22, the box's constructor and `Done` + `inherited` add 3, §7.2) | 22 | 24 / 28 |
| menu highlight move (with the status line's hint) | **0** | 3 (2 rows + the status line) | 2 / 3 |

A user subclass of any widget that overrides a virtual adds one dispatch per use of that virtual
(the elision rule); the limits leave room for one. The "writes" column counts public fv.video
writer calls, so the per-row `writeBuf` fallback of `_wrows` shows up (it is the H1 cost).

### 8.2 Times, lists (fresh pages; laptop ms, median (min–max) of 5 rounds; CI range = ratio × stand-in range)

Git-bash 5.3.15 (`out_r2_gb_list_*.txt`); the stand-in in the same process: ASCII process
Down 5.61 / PgDn 8.84, Cyrillic process 5.48 / 8.68 (the CJK process's stand-in is slowed by the
wide rows beside it, 15.1 ms PgDn, so CJK is calibrated by the ASCII process).

| action | ASCII | Cyrillic | CJK | ratio A / C / J | CI range ASCII | CI range Cyrillic | target (CI Linux 80×24) |
|---|---|---|---|---|---|---|---|
| Down inside the page | 5.04 (4.92–5.09) | 5.34 | 8.29 | 0.90 / 0.97 / 1.48 | 3.3–4.5 | 3.6–4.9 | ≤ 4 (PLAN), at the edge as P2's stand-in |
| scroll by Down, FV-exact bar | 13.14 | 14.26 | 56.63 | 1.49 / 1.64 / 6.4 | 9.4–11.9 | — | — |
| scroll by Down, **P3-4** | **9.09** (8.73–9.13) | 10.56 | 33.31 | 1.03 / 1.22 / 3.77 | 6.5–8.2 | 7.7–9.7 | ≤ 8 |
| PgDn, FV-exact bar | 13.90 | 21.34 | 105.26 | 1.57 / 2.46 / 11.9 | 9.9–12.6 | 15.5–19.7 | — |
| PgDn, **P3-4** | **8.83** (8.70–9.70) | **16.43** (15.83–17.02) | **82.58** | 1.00 / 1.89 / 9.34 | **6.3–8.0** | **11.9–15.1** | ≤ 8 (PLAN) |
| wheel, P3-4 | 9.71 | 11.13 | 34.52 | 1.10 / 1.28 / 3.90 | 6.9–8.8 | 8.1–10.3 | ≤ 8 |
| End / Home alternately (cached pages) | 11.30 | 11.50 | 31.71 | 1.28 / 1.32 / 3.6 | 8.1–10.2 | 8.4–10.6 | ≤ 10 |
| click on a row (revision 1, ASCII) | 7.1–7.5 | | | 1.5 | 5.6–7.5 | | ≤ 8 |

Cygwin 5.2.21 (bash < 5.3: the listed-char text check; `out_r2_cyg_list_*.txt`) gives the same
shape: PgDn P3-4 ratios 1.03 / 1.83 / 9.31, Down 0.89 / 0.91 / 1.45 — the pre-5.3 check is not
where the time goes. (bash 5.1: not run; same path as 5.2.)

**Where a fresh non-ASCII page goes** (`out_r2_*_direct_*.txt`, `out_r2_*_san_x.txt`): a list
`drawView` (21 rows, with its terminal output) costs, fresh / same page, **ASCII 4.5 / 3.7 ms,
Cyrillic 9.9 / 4.0 ms, CJK 61.3 / 14.5 ms** (Cygwin 4.8 / 4.0, 10.4 / 4.2, 63.9 / 14.9). So a
fresh Cyrillic row costs ~0.26 ms more than an ASCII one: `_wrows` hands it to a public
`writeBuf` (guard, checks) whose `_text` misses the cache (126 µs, 99 of them the validity check
`_san`). A fresh CJK row costs ~2.2 ms: the per-character walk `_textw` (~90 µs a character); a
cached CJK row still ~0.5 ms (the wide put path, one `writeBuf` per row).

**Levers and estimates** (to be measured in 3a; the targets fixed in 3b):
* **10.11** (narrow fresh rows inside `_wrows`, one batched check): the check measured 99 → 20 µs
  per row when 21 rows are checked as one text (both bashes), the public entry per row gone.
  Estimate: a fresh Cyrillic row ~0.05 ms over ASCII → **PgDn ≈ ASCII + 1 ms**, ratio ~1.11 →
  **CI 7.0–8.9**.
* **10.12** (wide fast path): rows whose non-ASCII characters all lie in ranges that are wide and
  never join (CJK Unified and Extension A, Hiragana, Katakana, Hangul syllables, CJK
  compatibility, full-width forms) get their cells by one pattern substitution (`&` + the
  continuation mark: bash ≥ 5.2 `patsub_replacement`; a byte-pattern form in the C locale on
  bash < 5.3; a loop on 5.1), and cached wide rows go through `_wrows`' own splice instead of a
  `writeBuf` per row. Estimate: ~0.3 ms per fresh CJK row → **CJK PgDn ≈ 15 ms laptop, ratio ~1.7,
  CI 11–14** — above 8; Q8 proposes a CJK target relative to ASCII.
* **10.5** (the wide-row edge test) removes the CJK list's effect on its neighbours (the stand-in
  beside it: PgDn 15.1 against 8.8 ms).

### 8.3 Times, dialogs (laptop ms; ratio to `standin.down` of the same process; CI range = ratio × 3.7–5.0)

| action | Git-bash 5.3 | Cygwin 5.2 | ratio (Git-bash) | CI range | target |
|---|---|---|---|---|---|
| Tab between controls | 17.38 (16.84–18.27) | 18.55 | 2.91 | 10.8–14.6 | ≤ 12 (range 11–14 until 3c's A/B) |
| typing `a` / `b` (ASCII) | 6.68 (6.45–6.93) | 7.26 | 1.12 | 4.1–5.6 (map: up to −1.5 laptop) | ≤ 5 with the map |
| typing `ж` / `ы` (Cyrillic) | 7.03 | 7.13 | 1.18 | 4.4–5.9 | ≤ 5.5 with the map |
| typing `中` / `文` (CJK) | 11.22 (10.77–13.95) | 11.46 | 1.88 | 7.0–9.4 | ≤ 8 with 10.5 |
| typing then Backspace | 6.73 | 7.14 | 1.13 | 4.2–5.6 | ≤ 5 with the map |
| typing into a scrolled 70-character line | 8.18 | 8.35 | 1.37 | 5.1–6.9 | ≤ 8 |
| Shift+Left in a scrolled line | 7.99 | 8.52 | 1.34 | 5.0–6.7 | ≤ 8 |
| dialog open + close (pre-built) | 62.06 (60.48–65.38) | 59.72 | 10.4 | 38–52 | ≤ 50 |
| **messageBox end to end** (build 3 objects, run, close, destroy) | **52.24** (49.72–55.81) | 52.21 | 9.26 | **34–46** | ≤ 50 |
| **8-control dialog end to end** (build, open, close, destroy) | **102.49** (96.18–105.82) | 105.03 | 18.2 | **67–91** | ≤ 100 |
| the dialog's draw alone (`drawView`, 21 writes; revision 1) | 8.6–14.0 | | | 7–11.5 | ≤ 15 (first paint) |

**The 8-control dialog's pieces** (outside a Run, each with its terminal update; mean of 5):
build (9 objects + 8 inserts) **22.7 ms**, insert into the desktop 36.7, delete from it 26.0,
destroy (9 `.delete`) **13.6 ms** (Cygwin 23.3 / 38.5 / 28.3 / 14.8). Build and destroy are ~35 %
of the end-to-end time: ~2.5 ms per kklass object made and ~1.5 ms per object destroyed on this
laptop. A messageBox (3 objects) pays ~10 ms of it. FV builds each box per call too; no reuse is
proposed (a reused, hidden box would differ from FV in `Valid`, nesting and translation). A modal
dialog appearing ~50 ms after the key and a full form ~100 ms are under the perceptual 100 ms.

Per Tab (revision 1, 12 hops counted): 4.7 `drawView`s (~1.1 ms each for a one-row control),
3.3 `message`s (~0.55 ms each in an 8-control dialog), the key event ~3 ms, the setState chain.
The hot-key map takes the pre/post-process scan off most keys (up to −1.5 ms laptop, an upper
bound, M2); 10.4 is dropped (§3.4). Neither changes the dispatch count (already 0).

### 8.4 Times, menus (FV's flow; laptop ms)

| action | Git-bash 5.3 | Cygwin 5.2 | ratio to `standin.down` | CI range | target |
|---|---|---|---|---|---|
| F10 → bar → drop the box → close the box → close the bar (box 28×12 with a shadow over two panels) | 51.98 (50.57–58.53) | 51.50 | 8.8 | 33–44 | ≤ 50 |
| highlight move, the status line's hint changes | 6.05 (5.78–6.53) | 5.90 | 1.02 | 3.8–5.1 | ≤ 5 |
| highlight move, no hint | 4.55 (3.76–5.78) | 4.26 | 0.77 | 2.9–3.9 | ≤ 4 |

Revision 1's 23 ms "open + close" executed a box inside the desktop with no bar and closed on F10
(L1); FV's flow adds the bar's modal run in the application, the focus broadcasts to `TMyApp`
(14 dispatches), the bar's draws, the box's create / dispose and the status line's two context
changes. The move is cheaper than a list Down: the box's Execute loop reads its events itself.

### 8.5 200×50, first paint (F-1)

* **Whole-scene repaint** (drawView of the application + a forced update, mean of 20,
  `out_r2_gb_paint.txt`): the bench's stand-in two-panel scene 16.4–16.9 ms; the same scene with
  P3 lists and both bars 21.7–21.8 ms (**1.31×**); with the inactive panel's bar hidden, as FV's
  ShowSBar does (§2.2), 18.9–19.2 ms (**1.15×**). The bar's draw (~2.6 ms here) is the rest.
* **F-1** (the two-panel list scene's first paint, 18.7–19.7 ms CI today with stand-ins against
  15, D18 routes it to P3): with real lists it becomes ~21.5–22.7 ms CI (one bar) — P3 does not
  reach 15. Levers: a cheaper vertical bar draw (a column write in fv.video: ~40 lines, 10.13),
  and fv.video's whole-screen write path (R9, later). Stage 3b measures the real scene on CI and
  the owner sets the P3 number (**Q8**).
* **200×50**: stage 3b adds `views-list-200` with fresh ASCII and Cyrillic pages; target as P2's
  stand-in PgDn at 200×50 on the same run (×1.0–1.1; the stand-in measured 14.1–14.5 ms CI after
  K-8), decided after the 3b A/B.

---

## 9. Units, files, tests, bench

### 9.1 Files

```
kcl/fv.views/fv.views.sh     + TScrollBar TListViewer (Marks, ShowSBar), standardScrollBar,
                               the broadcast table, the hot-key map + hotKeyIs, ctrlToArrow,
                               writeRows, the wide-row edge test
kcl/fv.views/tests/          + 022_ScrollBar 023_ListViewer (keys incl. Space / Ctrl+PgUp /
                               Ctrl+PgDn / WordStar, Marks, ShowSBar, fresh Cyrillic and CJK
                               pages == a full repaint) 024_ListMouse (wheel, click, drag,
                               auto-repeat, a lost release ended by a key) 025_Quiet (broadcast
                               table; hot-key map == a full scan with user pre/post views
                               interleaved in Z order, Phase seen by each view, a direct Title
                               write caught on the next key, setters) 026_WideEdge 027_Ascii
                               (widgets in ASCII mode: the glyph table, cells == fv.video's);
                               010/011/012/013 extended
kcl/fv.dialogs/fv.dialogs.sh TDialog TButton TStaticText TLabel TParamText TCluster TCheckBoxes
                               TRadioButtons TInputLine TListBox THistory THistoryViewer
                               THistoryWindow, getData/setData, setters, helpers
kcl/fv.dialogs/tests/        001_Contract 002_Dialog (modal loop, Esc / Ctrl+F4 / Enter / default,
                               Valid, Ctrl+F5, **a resize during the modal loop**) 003_Button
                               (look, default grab/release, hot keys, Enter / Space when focused,
                               no focus on click without bfGrabFocus, disabled at Init,
                               cmRecordHistory, press tracking, bfBroadcast, cmCommandSetChanged)
                               004_StaticText (wrapping, ^C / ^B, wide) 005_Label (hot keys incl.
                               Cyrillic and the base key, Light, link) 006_Cluster (check / radio,
                               columns, keys, focused plain letters, mouse, EnableMask, Id,
                               the hardware cursor) 007_InputLine (editing, selection, scrolling,
                               FirstPos = Size.X − 3, MaxLen, overwrite + cursor shape, password)
                               008_InputWide (clusters == fv.video's cells: seeded random text,
                               joiners / VS16 / modifiers / flags typed and deleted mid-line ==
                               a whole-line re-split, VT model; astral characters on Cygwin)
                               009_InputMouse 010_ListBox (+ Marks checklist) 011_Data (getData /
                               setData order, DataSize overrides) 012_Focus (Tab order, phases,
                               broadcasts) 013_CallBudget 014_ZeroFork 015_CallerState
                               016_Elision 017_Palette (incl. D25's window default) 018_Clipboard
                               (internal, OSC 52 bytes, cmPasteText, password refuses copy)
                               019_History (THistory / window / viewer, cmRecordHistory, dedupe,
                               order, MaxLen cut) 020_Exit (`?2004l`, kitty pop, `ESC [ 0 q` on
                               every exit path: normal end, EOF, an error trap, Ctrl+C) 021_Ascii,
                               fvg_testlib.sh, tests.sh
kcl/fv.histlist/fv.histlist.sh historyAdd historyCount historyStr clearHistory (+ tests 001-004)
kcl/fv.msgbox/fv.msgbox.sh   messageBox messageBoxRect inputBox inputBoxRect
kcl/fv.msgbox/tests/         001_Contract 002_MessageBox 003_InputBox (+ -p) 004_Nested (from a
                               Valid, the EOF latch, two levels) 005_ZeroFork 006_CallerState
                               007_Subshell (`$(fv.msgbox.messageBox …)` refused by BASHPID, rc 2,
                               the terminal untouched) 008_Budget (end to end ≤ §8.1),
                               fvx_testlib.sh
kcl/fv.menus/                + TMenuView TMenuBar TMenuBox TMenuPopup, menuBar, setHint; tests
                               009_MenuItems 010_MenuBar 011_MenuBox (FV flow: boxes dropped by
                               the bar's owner, Esc per level, F10 inside does nothing)
                               012_MenuMouse 013_MenuStatus (hints, the hint table, GetHelpCtx up
                               the parents) 014_MenuBudget 015_MenuLoop (EOF inside the menu
                               loop closes every level, a subshell refuses, the event record
                               restored) 016_MenuLayout (base-key and Cyrillic hot letters);
                               007 / 008 extended
kcl/fv.app/                  bar on request (none by default: P2's 002 unchanged), resize with a
                               bar; 016_MenuBar
kcl/fv.video, fv.drivers,    §10's additions with their tests (fv.keyboard: CSI u and the
fv.keyboard                    replies, bracketed paste frames incl. a split frame, the layout
                               table; fv.video: push/pop and restore on every exit path)
tools/kbdlayout/             the layout-table generator (xkeyboard-config → bash data), §14
```

Dependencies: fv.dialogs → `kklass_pascal fv.views fv.histlist`; fv.msgbox → `fv.dialogs` (it
reads `FV_DESKTOP` / `FV_APP`; called without an application it refuses). Registration:
`KCL_UNITS` rows `fv.dialogs`, `fv.histlist`, `fv.msgbox` (G6), stubs. Locals and test libs:
`__fvg_` / `fvg_testlib.sh` (fv.dialogs), `__fvx_` / `fvx_testlib.sh` (fv.msgbox), `__fvh_`
(fv.histlist) — not fv.drivers' `__fvd_` / `fvd_testlib.sh` (L5).

### 9.2 Bench additions (`fvviews` suite, Run frame, `# calls` / `# writes` notes)

* `views-list-80`, `views-list-200`: `list.down`, `list.down-edge`, `list.pgdn`, `list.wheel`,
  `list.click`, `list.end-home`, each on **fresh pages** in three kinds — `ascii`, `cyr`, `cjk`
  (the bench's PRE moves the start 400 items per Run; 60 000 rows) — plus `list.pgdn-marks` (50 %
  marked); the stand-in window beside it keeps the D21 cases comparable in the same run;
* `views-dialog-80`: `dlg.open-close`, `dlg.paint`, `dlg.tab`, `dlg.type`, `dlg.type-cyr`,
  `dlg.type-cjk`, `dlg.shift-left`, **`dlg.build-run-destroy`** (the 8-control dialog end to end),
  **`msgbox.e2e`** (a real `fv.msgbox.messageBox` end to end);
* `views-menu-80`: `menu.open-drop-close` (FV flow, with a bar), `menu.down` (with a hint);
* `views-paint`: the two-panel scene with real lists (one bar shown) — F-1's P3 number.

`p3/probe_r2.sh` is the template (rounds, fresh pages, same-process stand-in). `ci.conf`
unchanged by default.

---

## 10. Lower-layer changes P3 needs

| # | where | what | why | size | stage |
|---|---|---|---|---|---|
| 10.1 | fv.video | **`fv.video.clusters TEXT CL CW`**: the clusters of TEXT as fv.video's writes cut them (CL = cluster strings, CW = cells), one guard, the narrow fast path; ASCII mode: one cluster of one cell per character | TInputLine's model (P3-5), TStaticText's wrapping, widths of wide button / menu titles; one source of truth with the screen | ~60 + a random test against `writeBuf` cells | 3a-1 |
| 10.2 | fv.video + fv.views | **uniform-symbol rows**: `fv.video._wrowsu X Y W TEXTS SYMS` and `fv.views.writeRows X Y W TEXTS SYMS` — row k in one symbol, cut / padded to W cells by fv.video's own walk | wide list / menu items without `strWidth` per row (rule 2) | ~80 + ~30, test vs `writeBuf` per row (as 021) | 3a-1 |
| 10.11 | fv.video | **fresh narrow rows inside `_wrows`**: a cache miss on a narrow candidate row is converted by `_wrows` itself (no public `writeBuf`), with **one** validity check (`_san`) over all missed rows of the call joined, then split; wide results fall back to the per-row path | fresh Cyrillic / Greek / Latin-1 pages (H1): check 99 → 20 µs per row measured; est. PgDn ≈ ASCII + 1 ms | ~50 + 021 extended (fresh pages, invalid UTF-8 in one row of many, a row with a control) | 3a-1 |
| 10.12 | fv.video | **wide fast path**: text whose non-ASCII characters all lie in wide, never-joining ranges gets its cells by one substitution (bash ≥ 5.2 `patsub_replacement`; byte patterns in the C locale before 5.3; a loop on 5.1); cached wide rows spliced by `_wrows` itself | fresh CJK rows 2.2 ms → est. ~0.3 ms (H1) | ~70 + 018 / 021 random wide cases == the walk | 3a-1 |
| 10.3 | fv.views | **broadcast table** `__FV_VW_BCAST[handler]="cmA cmB …"` used by `_quiet` and `_dispatch` (skip without a call when a built-in handler does not react; replaces the hard-coded TView / TFrame / TWindow rules) | broadcast traffic of dialogs (§3.4) | ~40 + tests (025) | 3a-2 |
| 10.3b | fv.views | **hot-key map** `${g}_hot` + `fv.views.hotKeyIs`, merged in Z order with unmapped pre/post views, `Phase` set per call, text stamps (§3.1) | up to −1.5 ms per key in dialogs (an upper bound) | ~70 + 025 | 3c (with its users) |
| 10.4 | fv.views | coalesced child redraws in `_groupActive` | ~3 ms per dialog open + close (M2) | ~50 | **dropped**; only if 3c misses |
| 10.5 | fv.views | **wide-row edge test**: repaint a wide row across the screen only when a wide pair straddles the repainted rectangle's edge | CJK typing 11.2 → ~6–7 ms in a dialog over windows; a CJK list's neighbours (stand-in PgDn 15.1 → 8.8) | ~40 + 005's randomized wide scenes extended | 3a-2 |
| 10.6 | fv.drivers | **`evMouseAuto`**: on the idle timeout with a button held, after `FV_REPEAT_DELAY` (0.44 s) then every timeout, the last position; any key / press / buttonless report ends the held state; `__FV_DR_NOW` drives the test | scroll bar arrows, list drag past the edge, input drag-scroll (FV); L2 | ~35 + 009_Auto | 3a-2 |
| 10.7 | fv.video (D27) | `setCursorType` sends DECSCUSR (`ESC [ 4 q` / `ESC [ 2 q`) when the shape changes, `ESC [ 0 q` on `doneVideo` and every exit path | insert / overwrite look of TInputLine (FV sfCursorIns) | ~20 + restore test | 3d |
| 10.8 | fv.video + fv.keyboard + fv.drivers (D24) | **bracketed paste**: `?2004h` on / `?2004l` off on every exit path; the frame decoded into one `evCommand cmPasteText` (text in `FV_EV_INFO`, a 64 KiB cap) | a pasted newline must not press the default button | ~15 + ~60 + ~10, tests incl. a split frame | 3d |
| 10.9 | fv.video (D24) | `fv.video.setClipboard TEXT` (OSC 52, pure-bash base64) | copy to the system clipboard | ~40 | 3d |
| 10.10 | fv.app + fv.menus (D23) | no bar by default; with a bar (override or `fv.menus.menuBar`): row 0, the desktop from row 1, resize | FV's layout only on request | ~40 | 3f |
| 10.13 | fv.video | a vertical column write (one call for a 1-cell-wide text column) for scroll bars | F-1: the bar's draw ~2.6 ms of a two-panel paint | ~40 | 3v (D31) |
| 10.15 | fv.video (+ fv.views if needed) | **the D31 speed round**: whatever 3v's probe finds between the 3b numbers and the targets — candidates: a cheaper wide put path (cached CJK rows ~0.5 ms each today, one `writeBuf` per row), the per-character width walk for wide text that 10.12 does not cover, the whole-screen write path (R9: one build of the terminal bytes for a full repaint) | CJK PgDn ≤ 8, F-1 ≤ 15 (D31) | set by the 3v probe | 3v |
| 10.14 | fv.keyboard + fv.video + fv.drivers | **layout-independent keys** (§14): CSI-u decoding (kitty protocol), the reply-driven push / pop of the flags, `FV_KEY_BASE` → `FV_EV_BASE`, the generated layout table with its lazy load | Alt+F / Alt+X / hot letters with any layout (owner's research item) | ~180 + ~200 (option c) + tests | 3L |
| — | kklass | **nothing**: K-2 (func answers) and K-8 (`nofields`) cover the widgets | | 0 | |

fv.views grows to ~5.0–5.2 k lines. P2's lesson stands (bash copies a function body on every call):
the new hot paths (list FocusItem, input line key, the hot-key lookup) keep their rare branches in
helpers.

---

## 11. Stage split (Stage 1), in order

Each stage: Opus worker → supervisor review → critic where marked → fixes → suites + `gate.sh` →
commit; the hygiene block in every brief; Windows gate (Git-bash, MSYS2, Cygwin) + the VMs on the
core stages (bash 5.1 on the VMs: the pre-5.3 paths of 10.11 / 10.12); perf A/B on the CI bench
through the perf branches (D20). **Stages run one after another** (shared README rows,
`KCL_UNITS`, PLAN / ledger: L8).

| stage | content | size | review |
|---|---|---|---|
| **3a-1** fv.video | 10.1 clusters, 10.2 uniform rows, **10.11** fresh narrow rows, **10.12** wide fast path; random tests against the existing walk on all three bashes + 5.1 / 5.2 VMs | ~260 + tests | Windows + VM; **critic** (the write path's correctness) |
| **3a-2** fv.views / fv.drivers | 10.3 broadcast table, 10.5 wide-row edge test, 10.6 evMouseAuto; the widget test-lib scene helpers | ~120 + tests | Windows + VM; **critic** (10.5 touches the painter) |
| **3L** layouts | 10.14 per the owner's answer to Q7: fv.keyboard CSI u + replies, push / pop on every exit path, `FV_KEY_BASE`, the table generator and data, `fv.views.hotKeyIs` used by the status line | ~380 + tests (option c) | Windows + VM; **critic**; a live check in the owner's terminals when allowed |
| **3b** lists | TScrollBar (P3-4 with L7's rule, Id / cmIdCommunicate, keys, mouse, auto), TListViewer (rule 4, data array + formatter + **Marks**, multi-column, wheel, click / drag / double click, Space / Ctrl+PgUp / Ctrl+PgDn / WordStar, SelectItem, ShowSBar, the direct bar link + broadcast), `standardScrollBar`, `listSetRange` etc.; **the same-run CI A/B** (fresh ASCII / Cyrillic / CJK, 80×24 and 200×50, the real two-panel paint) → **the list targets fixed** (and 10.13 if F-1's number asks) | ~550 | Windows + VM; **critic** |
| **3v** fv.video speed (D31) | a probe on the 3b CI numbers (where a fresh / cached CJK page and the two-panel first paint go), a short design note with levers and sizes (the supervisor reviews it; an owner question only if a lever changes behaviour), then 10.13 + 10.15 until the same-run CI A/B shows **PgDn ≤ 8 ms for ASCII, Cyrillic and CJK fresh pages and F-1 ≤ 15 ms** on CI Linux 80×24 (Windows as ratios) | probe + ~150–400 (unknown until the probe) | Windows + VM; **critic** (the write path) |
| **3c** fv.dialogs I | TDialog, TButton, TStaticText / TParamText, TLabel, TCluster / TCheckBoxes / TRadioButtons, getData / setData (virtuals), setters, helpers, the **hot-key map** (10.3b) with its users, P3-12; CI A/B → the dialog targets fixed (10.4 only if missed) | ~650 | Windows + VM; **critic** |
| **3d** fv.dialogs II | TInputLine (clusters + M6 re-split, editing, selection, scrolling, mouse, overwrite + 10.7, **password**, clipboard 10.8 / 10.9), TListBox (+ the Marks checklist) | ~550 | Windows + VM; **critic**; live check of the clipboard keys (§4.5) when allowed |
| **3h** history | fv.histlist, THistory, THistoryViewer, THistoryWindow, `cmRecordHistory` (§15) | ~280 | Windows + VM; supervisor-read |
| **3e** fv.msgbox | messageBox / messageBoxRect / inputBox (+ `-p`) / inputBoxRect, nesting, translations, the subshell refusal | ~200 | supervisor-read |
| **3f** menus | TMenuView model + Execute, TMenuBar, TMenuBox, TMenuPopup, key map, the hint table, the bar on request (10.10) + `fv.menus.menuBar` | ~650 (may split: model + box / bar + app) | Windows + VM; **critic** |
| **3g** budget, bench, docs | 013 / 014 budgets with §8.1's limits (row / item independence: 21 vs 42 rows, 1 000 vs 60 000 items), the bench cases (§9.2), READMEs (fv.dialogs, fv.histlist, fv.msgbox, the additions incl. the deviations: D23, D25, cluster stepping, the clipboard key table), kcl README rows, PLAN / ledger, a headless demo (a dialog and a menu over the two-panel scene) for the owner's live run | ~300 + docs | `gate.sh all` host + VM; supervisor-read; CI bench run |

Order: **3a-1 → 3a-2 → 3L → 3b → 3v → 3c → 3d → 3h → 3e → 3f → 3g**. 3L implements option (c)
(D30). 3b fixes the ASCII / Cyrillic list numbers and measures CJK and F-1 on CI; 3v brings CJK
and F-1 to the D31 targets before the dialog stages.

---

## 12. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | Pre / post-process scans grow with the controls in a dialog | the hot-key map (10.3b); 3g measures a 20-control dialog |
| R2 | Broadcast fan-out: each Tab sends 2–4 broadcasts to every listening control | the broadcast table; picture-change redraws (P3-12); Tab budget test with a 20-control dialog |
| R3 | Dialog open + close ≈ 38–52 ms CI, end to end with build / destroy up to ~90 ms; mostly P2's window switch, `drawUnder` and kklass object creation | targets 50 / 100 ms; a later P2-machinery or kklass step if the owner wants faster |
| R4 | CJK typing and CJK lists through P2's full-width wide-row repaint | 10.5; critic on 3a-2; 005's randomized wide scenes |
| R5 | The input line's clusters and the screen disagree | one splitter (10.1), the M6 re-split, 008's random test (whole-line re-split as the oracle) on all runtimes (Cygwin astral) |
| R6 | Paste without bracketed paste presses the default button at a newline | bracketed paste (D24); only terminals without it remain exposed (documented) |
| R7 | The menu's own Execute loop (a 4th inner loop): event record, EOF latch, BASHPID | the P2 §2.2 rules + 015_MenuLoop |
| R8 | (closed by D25: the friendly window default) | — |
| R9 | A user `GetText`-style formatter calling a kklass method per row costs 3× (PLAN §2.1) | documented; the formatter is a plain function |
| R10 | fv.views body growth slows hot functions (body copy per call) | rare branches in helpers (2c-p lesson); 3a/3b A/B on the CI bench |
| R11 | Auto-repeat on Windows: `read -t` waits in 15.6 ms steps; repeat jitter | harmless (FV's own tick is 55 ms); the delay is a variable |
| R12 | List PgDn meets 8 ms only at the top of the CI range for ASCII (6.3–8.0) | P3-4 is required; 3b's same-run A/B fixes the target; levers: cheaper row padding, 10.2's fast path |
| R13 | Only laptop ratios so far, ±25 % between CI runs | CI A/B in 3b (lists), 3c (dialogs), 3g (all), each comparing sides within one run |
| R14 | **Fresh non-ASCII pages**: Cyrillic PgDn 1.89×, CJK 9.3× the ASCII cost (H1) | 10.11 and 10.12 in 3a-1, fresh-page bench and tests in all kinds; CJK to ≤ 8 ms in 3v (D31) |
| R18 | **3v's size is unknown** (D31): the CJK and F-1 gaps may need more than one fv.video step | 3v starts with a probe and a design note; if the levers found cannot reach the targets in one stage, the supervisor brings the owner the measured gap with options before more stages are added |
| R15 | **Layout protocols**: a terminal that misreads `CSI > 5 u` / `CSI < u`; replies arriving mid-typing; a table that maps a character to the wrong key for a user's layout | push only after the terminal answered the query (§14.4); replies decoded and swallowed; the typed character always matched first; `FV_KBD_LAYOUT` and `FV_KBD_PROTO=off` overrides; generator reports every ambiguity |
| R16 | Terminals take FV's clipboard keys (Shift+Ins, Ctrl+Ins) | the key table (§4.5): paste through the terminal + bracketed paste, copy through OSC 52; documented |
| R17 | F-1: the real list scene paints ~21.5–22.7 ms CI, over 15 | ShowSBar (one bar); 10.13 + 10.15 in 3v to reach 15 (D31) |

---

## 13. Owner questions

**Answered on 2026-11-20** (now D22–D29, §0.1): revision 1's Q1 menus (O3: yes, full; the bar
only on request), Q2 input history (in v1), Q3 clipboard (bracketed paste + internal + OSC 52),
Q4 cursor shape (yes), Q5 list colours in a window (friendly default), Q6 multi-select (`Marks`);
plus password mode and long checklists for P4. For the record (L10): revision 1's Q1 said "P2
landed within budget (D21 met the targets)"; the ledger's words are "down 4.01 (4: at the edge),
tab 19.65 (20: met), pgdn 6.61, 200x50 redraw 29.13 (30: met), P2 paint 14.52 (15: met)" (CI run
44482144631, before K-8).

**Answered on 2026-11-20 (later the same day): Q7 = (c) → D30; Q8 = (a) one target for every
kind → D31 (stage 3v).** The question texts stay below for the record.

### Q7 — Hot keys with non-Latin keyboard layouts

The full research is §14; the options with examples are §14.6. In short: with a Russian, Greek,
Hebrew or Arabic layout a terminal sends Alt+F as Alt + the local letter (`ESC а`), so today no
Latin hot key fires (`~F~ile`, `O~K~`, Alt+X in the status line).

* **(a) Typed character only** — hot letters may be written in any script (`~Ф~айл`); Latin hot
  keys do not fire with a non-Latin layout. ~30 lines, no stage.
* **(b) (a) + the kitty keyboard protocol** — exact in kitty, foot, WezTerm, Ghostty, Alacritty,
  iTerm2; elsewhere as (a). ~180 lines + tests.
* **(c) (b) + generated layout tables** — also Windows Terminal, mintty, xterm, GNOME Terminal,
  Konsole, tmux, for the main layout of each script (overridable). ~380 lines + ~12 KB data, one
  stage (3L).
* **(d) (c) + win32-input-mode in Windows Terminal** — exact virtual keys there, at ~+1.3 ms per
  typed character; needs a live check first.

**Recommendation: (c)** — the only option that works in the terminals most users have, exact
where the terminal can tell, one stage; (d) later as an opt-in after a live check.

### Q8 — Targets for lists with non-ASCII names, and the list scene's first paint

Fresh pages with Cyrillic names cost 1.89× and with CJK names 9.3× the ASCII cost today (§8.2);
10.11 brings Cyrillic near ASCII (est. PgDn 7.0–8.9 ms CI), 10.12 brings CJK to an estimated
11–14 ms CI, not 8. The two-panel scene's first paint with real lists is ~21.5–22.7 ms CI (F-1's
target 15).

* **(a) One target for every kind** (PgDn ≤ 8 ms CI for CJK too; first paint ≤ 15). What you
  see: the same speed for every script — after an extra fv.video stage of unknown size (the wide
  write path and the whole-screen write path, R9), which delays the widgets.
* **(b) Per-kind targets** (recommended): ASCII and narrow scripts (Cyrillic, Greek, Latin-1) PgDn
  ≤ 8 ms CI after 10.11; CJK PgDn ≤ 2× the ASCII PgDn of the same CI run (~13–16 ms); the list
  scene's first paint = the 3b CI number with one bar shown (~21–23 ms), F-1 kept open for a
  later fv.video step. What you see: paging through a folder of Chinese file names takes ~12–15
  ms per page on CI Linux (~20–28 ms on Git-bash) — still well under what the eye notices
  (~50–100 ms); the panel scene appears ~7 ms later than the P2 scene.
* **(c) (b), but F-1 reaches 15 ms in P3**: adds 10.13 (column writes) and a whole-screen write
  step to P3 (~1 stage). What you see: the first screen ~6 ms sooner; P3 one stage longer.

**Recommendation: (b).**

Not asked (decided by D1 / D16 / D17 / rules): FV's class set and fields; plain functions + thin
aliases (D16); redraw only what changed (D17) applied to widgets (P3-12) and to the scroll bar
(P3-4); clusters as the input line's unit (P3-5, forced by D5 + Cygwin; a documented deviation
from FV's unit stepping); data transfer as an indexed array in FV's order through the virtuals
(§4.6); `GetText` replaced by a plain formatter (rule 2); FV's menu flow (boxes executed by the
bar's owner, Esc per level); the clipboard key table (§4.5).

---

## 14. Layout-independent hot keys (research item)

The owner (2026-11-20): "a universal way is needed: there are very many layouts in the world, it
must work everywhere". Evidence: FPC trunk sources (file:line), terminal behaviour from the
protocols' documentation as I know it (marked "from memory" where a version matters: to be
confirmed in the 3L live check), and headless probes of today's parser (`p3/probe_keys.sh`,
`p3/out_keys_gb.txt`, `out_keys_cyg.txt`: Git-bash 5.3.15 and Cygwin 5.2.21 agree).

### 14.1 The problem, measured

| what the terminal sends | today's fv.keyboard (`decode`) |
|---|---|
| Alt+F, US layout: `ESC f` | `kbAltF`, char `f` |
| Alt+F, Russian: `ESC а` · Greek: `ESC φ` · Hebrew: `ESC כ` · Arabic: `ESC ب` | `kbAltChar`, char `а` / `φ` / `כ` / `ب` |
| Alt+X, Russian: `ESC ч` | `kbAltChar`, char `ч` (the status line's `kbAltX` never matches) |
| Ctrl+F, any layout: `0x06` | `kbCtrlF` (terminals send the Latin control code for Ctrl chords: Ctrl is not the problem) |
| kitty protocol Alt+F Russian `CSI 1072::102;3u`, US `CSI 102;3u`, Ctrl+F `CSI 1072::102;5u`, Esc `CSI 27u` | `kbUnknown`, consumed exactly (14 / 8 / 14 / 5 bytes) |
| kitty reply `CSI ?5u`, DA1 reply `CSI ?62;22c` | `kbUnknown`, consumed exactly |
| win32-input Alt+F Russian, key down `CSI 70;33;1072;1;2;1_` and up `…;0;2;1_` | `kbUnknown`, consumed exactly |
| xterm modifyOtherKeys=2 `CSI 27;3;1072~`, formatOtherKeys=1 `CSI 1072;3u` | `kbUnknown` |
| bracketed paste start `CSI 200~` | `kbUnknown` |

So hot keys break only for **Alt + letter** (and plain-letter hot keys) in non-Latin layouts, and
every protocol report already parses as one key: decoders can be added without touching what
works. Decode cost today (best of 5 × 400): `a` 119 µs, `ESC а` 231, `CSI 1072::102;3u` 581,
`CSI 70;33;1072;1;2;1_` 722 µs.

### 14.2 What Free Vision and FPC do

* **FV on DOS / the Windows console** reads scan codes: Alt+F is `kbAltF` whatever the layout, so
  FV's dialogs only compare `GetAltCode(C)` and `UpCase(CharCode)` (TButton dialogs.inc:2472-2474,
  TCluster 2853-2856, TLabel 3732-3734). On Unix terminals there is no scan code.
* **FPC 2025's menus** are layout-aware (menus.inc:680-702, 995-1013): with Alt, "Path 1:
  character-based search (for correct layouts like Russian)", then "Path 2: scancode-based search
  (fallback for EN hotkeys in RU layout)" via `GetAltChar(ScanCode)`.
* **FPC's Unix keyboard unit** (`packages/rtl-console/src/unix/keyboard.pp`) gets that scan code
  from the terminal protocols:
  * at init (`SysInitKeyboard`, 2948-3018, `TV_INPUT` read at 2986): `TV_INPUT=win32` → `CSI ? 9001 h`; `TV_INPUT=kitty` → `CSI > 31 u` and the
    query; `legacy` → nothing; default → push `CSI > 31 u`, query, and if no kitty, xterm's
    `CSI > 4 ; 2 m` (modifyOtherKeys), and always try `CSI ? 9001 h`;
  * the query (2896-2930): `CSI ? u` followed by DA1 `CSI c`, then a blocking read of the answer;
  * kitty decoding (2409-2575): for Ctrl / Alt / Shift chords it builds the key from the
    **base-layout key** field — "shortcut keys not tied to localized keyboard layout"
    (2556-2558);
  * win32-input decoding (2276-2404): the scan code, else the virtual key code;
  * at done (`SysDoneKeyboard`, 3021-3040): `CSI ? 9001 l`, `CSI > 4 m`, `CSI < u` (when kitty was on).

  So the FPC route is exactly "typed character first, then the layout-independent key from the
  protocol". It blocks on the query reply; fv cannot (the ConPTY read hang on Windows consoles,
  and D13's reader process) — §14.4 does it without waiting.

### 14.3 The protocols

* **kitty keyboard protocol** (progressive enhancement). A key: `CSI code[:shifted[:base]] ;
  mods[:event] [; text] u`, `mods` = 1 + Shift 1 + Alt 2 + Ctrl 4 + …; flags 1 disambiguate, 2
  event types, 4 **alternate keys** (the shifted key and the **base-layout key**: the key at that
  position on a US PC-101 layout), 8 all keys as escape codes, 16 associated text. Query
  `CSI ? u` → `CSI ? FLAGS u`; push `CSI > FLAGS u`; pop `CSI < u`. Flag 4 only adds fields to keys
  that are already sent as escape codes — with flag 1 that is Esc, Alt / Ctrl chords and modified
  Enter / Tab / Backspace; **plain typed letters stay plain text** unless flag 8 (which turns all
  typing into CSI sequences: 5× the decode cost per character, not proposed). Examples, Alt+F:
  Russian `CSI 1072::102;3u` (а, base f), Greek `CSI 966::102;3u` (φ), Hebrew
  `CSI 1499::102;3u` (כ), Arabic `CSI 1576::102;3u` (ب); Alt+Shift+F Russian
  `CSI 1072:1040:102;4u`. Side gain: Esc arrives as `CSI 27 u` — no Esc timeout (31 ms on
  Windows).
  **Terminals (from memory, as of mid-2025):** kitty, foot, WezTerm (with
  `enable_kitty_keyboard`), Ghostty, Alacritty ≥ 0.13, iTerm2 ≥ 3.5, rio; VS Code's terminal behind
  an experimental setting. **Not:** xterm, GNOME Terminal / VTE, mintty, conhost, the Linux
  console, screen; Windows Terminal not to my knowledge (work was reported in progress); Konsole
  unknown; tmux passes extended keys in its own CSI-u form without the base key.
* **win32-input-mode** (`CSI ? 9001 h`, Windows Terminal; ConPTY's own input format). Every key
  **down and up**, modifiers alone too, as `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _`. `Vk` is the
  virtual key: for non-Latin layouts the US letter of the position (Russian F key → `VK_F`), for
  Latin layouts the layout's letter (AZERTY's A key → `VK_A`) — what users expect; `Sc` is the
  physical scan code. Cost: Alt+F = 4 sequences of ~19 bytes; typing a letter = 2 (0.72 ms decode
  each, measured, against 0.12 for a plain byte) → ~+1.3 ms per typed character. **Under
  Git-bash / MSYS2 / Cygwin in Windows Terminal** the program reads the console through the
  Cygwin runtime (fv.video's reader process, D13), which reads console input records and makes its
  own bytes (`ESC а` for Alt+F Russian); whether `?9001h` written by the program makes conhost
  deliver win32 sequences through that path is **unknown** — a live probe, only when the owner
  allows live tests. **mintty** is a pty terminal: no 9001, no kitty.
* **xterm `modifyOtherKeys` / `formatOtherKeys`** (`CSI > 4 ; 2 m`): Alt+а becomes
  `CSI 27 ; 3 ; 1072 ~` (or `CSI 1072 ; 3 u` with formatOtherKeys=1): the code is the **typed**
  character — they disambiguate chords, they carry **no base key**. Not useful for layouts.
* **Terminals with none of these** (Windows Terminal today, mintty, xterm, VTE, conhost, tmux,
  screen, macOS Terminal.app): the base key must come from knowledge of the layouts — §14.5.

### 14.4 Design: the base key in fv.keyboard, one helper for every hot key

* **`FV_KEY_BASE`** (new fv.keyboard global; fv.drivers copies it to **`FV_EV_BASE`**): the
  base-layout key of this key as one lower-case ASCII character (`f`, `x`, `1`, `;`) when known,
  else `''`.
* **CSI u** is decoded (flags 1|4 forms): Alt / Ctrl / Ctrl+Alt + a key with a base key → FV's
  name from the base key (`kbAltF`, `kbCtrlF`, `kbCtrlAltF`), `FV_KEY_CHAR` = the typed character,
  `FV_KEY_BASE` = the base; without a base field (a US layout) the base is the code when ASCII;
  `CSI 27 u` → `kbEsc`, modified Enter / Tab / Backspace / Space → FV's names; keypad and other
  functional codes → their names or `kbUnknown`. Key-release reports never come (flag 2 is not
  pushed).
* **Legacy `ESC` + non-ASCII** (all other terminals): when the layout table has the character,
  `FV_KEY=kbAlt<BASE>`, `FV_KEY_CHAR` = the typed character, `FV_KEY_BASE` = the base — so the
  status line's `kbAltX` matches Alt+ч with no change in fv.menus, and so does every application
  that tests `kbAltX`. Plain non-ASCII typing keeps `kbChar` with `FV_KEY_BASE=''` (no cost on
  the typing path); the hot-key helper asks the table lazily for plain letters.
* **Detection without waiting, restore on every exit path.** `initVideo` writes the query
  `CSI ? u` and DA1 `CSI c` (every terminal answers DA1) and goes on; nothing waits for a reply
  (no timed read on the console). fv.keyboard decodes `CSI ? N u` and `CSI ? … c` as **replies**,
  not keys (no event; `__FV_KB_KITTY=N`, the DA1 seen). On the kitty reply fv.drivers asks fv.video
  to push `CSI > 5 u` (flags 1|4) once; `doneVideo` and every exit path (the traps that restore
  the mouse, `?2004l` and the cursor shape) pop `CSI < u` — only when pushed. A terminal without
  the protocol answers DA1 only: nothing is pushed and no unknown sequence is sent to it. Keys
  typed before the reply arrive in the legacy form (and work through the table). Overrides:
  `FV_KBD_PROTO=auto|kitty|off` (`kitty` pushes at once, `off` sends nothing); `FV_KBD_PROTO=win32`
  only with option (d).
* **Fork-free hot path**: plain ASCII and plain non-ASCII typing unchanged; a legacy Alt +
  non-ASCII key: one table read (3.1–3.3 µs measured) after a one-time lazy load at the first such
  key (a 2 400-entry table literal loads in 6.9–8.5 ms, measured; the default tables, ~700 entries,
  ~2–3 ms); a CSI-u key decodes in ~0.58 ms (today's byte loop, measured), as `ESC [ 1 ; 5 D`.
* **One helper**, `fv.views.hotKeyIs HOT [plain]` (rc 0 = the current key event is that hot key):
  with Alt — the folded typed character equals the folded hot letter, **or** `FV_EV_BASE` equals
  it; plain (when the caller allows plain letters) — the folded typed character, or the table's
  base for it. **Typed character first**, then the base key: a title written in the user's script
  (`~Ф~айл`) wins on its own key, and Latin alternative layouts (AZERTY, QWERTZ, Dvorak, Colemak)
  get the letter they typed, never the US position — FPC's own order. Used by TButton, TLabel,
  TCluster, TMenuBar / TMenuBox (FindItem) and the hot-key map (10.3b: the typed character's entry
  first, then the base key's); the status line needs nothing (the rewritten `FV_KEY`). Folding:
  `${c,,}` under fv.video's UTF-8 locale name (bash folds Cyrillic, Greek, Armenian, Georgian).

### 14.5 The fallback: layout tables generated from xkeyboard-config

* **Source**: xkeyboard-config (`/usr/share/X11/xkb/symbols/*`, the layout data of every Linux
  desktop; MIT / X11-style licence, attribution in the generated file). A generator
  (`tools/kbdlayout/gen.sh`, run on a Linux VM like fv.unicode's UCD generator) reads each layout
  and variant, takes the main block (TLDE, AE01–AE12, AD01–AD12, AC01–AC11, AB01–AB10, BKSL),
  levels 1 and 2, and writes "character → the US key at that position" for every non-ASCII
  character; output committed as data (`kcl/fv.keyboard/fv.keyboard.layouts.sh`).
* **Ambiguity** — a character at different keys in different layouts (Cyrillic `а` is F in
  ЙЦУКЕН and A in the phonetic layouts; `у` differs between the Russian and Bulgarian BDS
  layouts). Resolution, first that applies:
  1. `FV_KBD_LAYOUT=bg_phonetic,ru` (environment, a comma list, first wins);
  2. the language of `LC_ALL` / `LC_CTYPE` / `LANG` when it names a layout (`uk_UA` → ua,
     `bg_BG` → bg, `el_GR` → gr, `he_IL` → il, `ar_*` → ara, `fa_IR` → ir, `ka_GE` → ge,
     `hy_AM` → am, `sr_RS` → rs, `th_TH` → th, `be_BY` → by, `kk_KZ` → kz, `mk_MK` → mk);
  3. a per-script default — the most used layout: Cyrillic ЙЦУКЕН (ru), Greek (gr), Hebrew
     (il), Arabic (ara), Persian (ir), Georgian (ge), Armenian (am), Thai (th).
  The generator prints every conflict per script, so the defaults are a reviewed list, and the
  protocol's base key (when present) always wins over the table.
* **Scope and limits**: scripts typed key-for-key. CJK through an IME produce composed text; Alt
  chords pass the IME (Windows IMEs, ibus, fcitx do not take Alt+letter), so they arrive as Latin
  already. macOS: Option without "Option as Meta" types `ƒ` for F (a different layer): documented
  — set "Use Option as Meta" (Terminal.app) / "Esc+" (iTerm2), as PLAN §7 already says for Alt.
* **Size**: default tables ~700 entries (~12 KB), all variants ~3 000 (~50 KB) loaded only for a
  layout named in `FV_KBD_LAYOUT` or by the locale.

### 14.6 Owner options with examples (Q7)

What a user sees in a dialog **Find** (`~T~ext to find`, `O~K~`, a status line `Alt+X Exit`) and
a menu bar `~F~ile`:

| user (layout) | terminal | (a) typed char | (b) + kitty | (c) + tables | (d) + win32 |
|---|---|---|---|---|---|
| Russian (ЙЦУКЕН) | kitty, foot, WezTerm, Ghostty, Alacritty, iTerm2 | Alt+F, Alt+T, Alt+K, Alt+X do nothing (F10, F-keys, Tab, Ctrl, the mouse work) | all work | all work | all work |
| Russian | Windows Terminal (Git-bash / MSYS2 / Cygwin / WSL) | do nothing | do nothing | **all work** | all work (exact VK; if the live check passes) |
| Russian | mintty (Git-bash's own window) | do nothing | do nothing | **all work** | as (c) |
| Russian | xterm, GNOME Terminal, Konsole, tmux | do nothing | do nothing | **all work** | as (c) |
| Greek: Alt+F types `φ` | GNOME Terminal | nothing | nothing | File opens | as (c) |
| Hebrew: Alt+F types `כ` | kitty | nothing | File opens | File opens | File opens |
| Arabic: Alt+F types `ب` | mintty | nothing | nothing | File opens | as (c) |
| Ukrainian: Alt+X types `ч` | Windows Terminal | nothing | nothing | exits (locale `uk_UA` or the Cyrillic default agree here) | exits |
| Bulgarian phonetic: Alt+F types `ф` | xterm | nothing | nothing | **Alt+A's action** with the Cyrillic default (ф is A in ЙЦУКЕН); right with `FV_KBD_LAYOUT=bg_phonetic` | as (c) |
| Bulgarian phonetic | kitty | nothing | right | right (protocol wins) | right |
| Japanese with an IME (Mozc / MS-IME) | any | Alt+F arrives as `ESC f`: works; plain hot letters while composing go to the IME | same | same | same |
| French AZERTY, German QWERTZ, Dvorak | any | the typed letter: works | works | works (typed char first) | works |
| A program written with Russian hot letters (`~Ф~айл`) | any | works for Russian typists | works | works for Russian typists (a Latin-layout typist types `a` and is not mapped back: documented) | works |

Greek, Hebrew, Arabic, Persian, Georgian, Armenian and Ukrainian typists see exactly what the
Russian rows show, terminal by terminal (one row per script above only to keep the table short);
Hebrew and Arabic are right-to-left scripts, but the hot keys are key positions, so direction
plays no part.

Cost: **(a)** ~30 lines (the helper + folded map keys; in 3c, no stage); **(b)** +~180 lines
(CSI-u decoding ~120, replies + push / pop on every exit path ~40, `FV_EV_BASE` ~10, the status
line rewrite ~10) + ~250 test lines — half of 3L; **(c)** (b) + ~200 lines (generator ~150 in
tools, lookup + lazy load + locale default ~50) + ~12 KB data + ~120 test lines — stage 3L;
**(d)** (c) + ~120 lines (win32 decoder, dropping key-ups and modifier-only reports, the opt-in)
+ tests + a live check in Windows Terminal under the three runtimes.

**Recommendation: (c)**, matching typed character → protocol base key → table. It is the one
option that makes Alt+F, Alt+X and every `~X~` hot key work in the terminals most users have
(Windows Terminal, mintty, xterm, GNOME Terminal), exact in the kitty-protocol terminals, with a
documented override for the rare layout that disagrees with its script's default. (d) stays a
later opt-in once a live check shows what Cygwin-family programs see in Windows Terminal.

---

## 15. Input history (D28)

* **fv.histlist** (FV histlist.pas): `historyAdd ID TEXT`, `historyCount ID`, `historyStr ID
  INDEX`, `clearHistory`; ids 0–255 (FV: Byte); per process, not saved; **newest first**, a
  repeated string moves to the front (FV's InsertString removes the old copy); a total size cap
  (FV `HistorySize` 64 KiB) dropping the oldest. Plain arrays per id, no fork.
* **THistory** (FV dialogs.inc:3873-3990): a 3-cell view after the input line (`▐v▌`, CHistory),
  `ofPostProcess`, broadcasts. **Down** on its focused link (through `CtrlToArrow`) or a click
  on it: focus the link, `RecordHistory` (the link's text), open a **THistoryWindow** (a TWindow
  with a THistoryViewer and its two bars as FV InitViewer; CHistoryWindow) placed as FV: one cell left and right of the
  link, 7 rows down, cut to the owner (dialogs.inc:3955-3964), executed by the owner (`execView`,
  modal); the viewer starts on item 1 (item 0 is the text just recorded, dialogs.inc:3760-3761);
  Enter / double click → `cmOK`, Esc → `cmCancel` (3801-3814); on `cmOK` the line gets the
  selection cut to `MaxLen`, `SelectAll`, redraw.
* **Recording** (FV): on `cmReleasedFocus` of its link and on **`cmRecordHistory`**, which every
  `TButton.Press` broadcasts first (dialogs.inc:2293) — so pressing OK records every history line
  of the dialog. A line in password mode is never recorded (D29).
* Cost: opening the history window builds a small window + list + bar and runs it modal: about a
  messageBox's cost (est. ~35–45 ms CI); a list move inside it as a list Down. Tests: 019_History
  + fv.histlist's 001–004. Size ~200 (fv.dialogs) + ~80 (fv.histlist). Stage 3h.

---

## Appendix A. Probes and prototype (`scratchpad/p3/`)

| file | what |
|---|---|
| `proto_w.sh` | revision 1's prototype classes (built-in-like: bodies in `__FV_VW_IMPL`): TPScrollBar (`P3_SBPART`: the thumb's two rows on a value change, the broadcast still walking; `P3_SBQUIET`: the direct list link; `P3_SBSMART` + `P3_SBQUIET`: P3-4 as designed), TPListViewer, TPDialog, TPButton, TPLabel, TPCheckBoxes, TPInputLine (cluster arrays), TPMenuBox |
| `proto_r2.sh` | revision 2 additions: the list painter for cell-padded rows (`P3_PREPAD`), `TPMenuBar` (FV's flow: execView by the bar's owner, the box dropped by the bar's owner, Esc per level, the status line's Update per move with a built-in-like hint table), `p3.msgbox` (a messageBox stand-in built / run / destroyed), `p3.buildDlg` / `p3.killDlg` |
| `proto_ascii.sh`, `sbfill.sh` | revision 1 variants: an ASCII scroll bar; a bar drawn as a fill + 3 writes |
| `probe_p3.sh ROOT CASE [N]` | revision 1's harness (one Run vs the minimum of 3 baselines: biased, M1) |
| `probe_r2.sh ROOT CASE [KIND] [N]` | revision 2's harness: 5 rounds of (empty, keys, empty) with medians, fresh pages, a same-process stand-in; CASE `list` (KIND ascii / cyr / cjk), `dialog`, `msgbox`, `menu`, `paint` (KIND standin / p3 / p3hide), `direct` (fresh vs same-page drawView), `san` (the text check per row vs batched); `P3_DBG=FILE` logs every dispatch with its event |
| `run_r2.sh BASH ROOT TAG` | the batch for one bash (each case under `timeout -k 10 60`) |
| `probe_keys.sh ROOT` | today's fv.keyboard on the layout protocols' reports; decode costs; a layout-table lookup; a 2 400-entry table load |
| `out_r2_gb_*.txt`, `out_r2_cyg_*.txt`, `out_r2_gb_paint.txt`, `out_keys_gb.txt`, `out_keys_cyg.txt` | revision 2's raw outputs (Git-bash 5.3.15, Cygwin 5.2.21) |
| `out_list.txt`, `out_list2.txt`, `out_dialog.txt`, `out_menu.txt` | revision 1's raw outputs (µs per action) |
| `emul/*.txt` | revision 1's emulation snippets for `probe_p3.sh`'s dialog case: `nopp` (no pre/post processing at all: an upper bound for the hot-key map), `coal` (coalescing + the input line's sfFocused draw dropped: mixes 10.4 and P3-12, M2), `tabcnt` / `occnt` (per-Tab / per-open call counts), `pieces` (insert / delete / drawUnder split); `probe_dbg.sh` = the last such splice |
| `cpu.ps1` | the per-process CPU sample taken before each timing batch |

Raw numbers not in the tables (revision 1, direct, N = 20): list `drawView` 3267 µs, bar
`drawView` 3485, bar thumb pair (2 `drawPart`s) 1693, list 2 rows 1733, `message
cmScrollBarChanged` 649, `message cmReceivedFocus` (8 controls) 537, input line `drawView` 1132
(CJK 2132), cluster insert (ASCII array splice) 95, `fv.unicode.charClass` 36, `fv.video.strWidth`
(12 CJK) 201, a plain call 2.6, `updateScreen` with nothing changed 94. Counts per 12 Tab hops: 56
`drawView`, 8 public + 32 internal `message`s. Revision 2 (Git-bash / Cygwin): `_san` per fresh
Cyrillic row 99 / 115 µs, batched over 21 rows 20 / 21 µs per row, `_text` miss 126 / 129 µs;
list `drawView` fresh / same ASCII 4481 / 3670, Cyrillic 9899 / 4001, CJK 61341 / 14468 µs
(Cygwin 4804 / 3987, 10395 / 4208, 63934 / 14894).

Prototype limits (not product behaviour): ASCII hot letters only; cluster rules simplified (z / m
join, w / y = 2; no ZWJ / flag / VS16 rules — 10.1 brings fv.video's); CJK rows padded to cells in
the test data (the real cut is 10.2's); no validators, no auto-repeat (10.6 does not exist yet),
the menu bar with one box (no submenus, no mouse); Ctrl+F4 stands in for Esc in the menu loops;
the bar overlaps nothing because the probe moves the desktop to row 1 (D23's layout).
