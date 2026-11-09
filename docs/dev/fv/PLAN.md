# fv — a Free Vision-style text UI library for bash (kcl/fv.*)

**Status:** PLANNED 2026-11-09. P0 next. **Ledger:** [`fv_ledger.json`](fv_ledger.json)
(single source of truth for status).

Owner request (2026-11-07): a set of windowing classes that other scripts can use, with
the API modelled on Free Vision. Before the plan, the owner asked for measurements on a
prototype. The spike (2026-11-08) answered GO under five design rules. Then kklass round K
made a method call 1.8× faster (kklass 0.1.1). This plan uses the numbers from both.

Sources:

* Free Vision: `C:/projects/fpc-trunk/packages/fv/src` (code in the `.inc` files).
* FPC console RTL (Video, Keyboard, Mouse): `C:/projects/fpc-trunk/packages/rtl-console/src/inc`.
* Spike: session scratchpad `tui_spike/`, which holds REPORT.md, the prototype layers, the
  bench and the key table. Copy whatever a phase needs into the repository; the scratchpad
  is temporary.

## 1. Owner decisions

| # | Date | Decision |
|---|---|---|
| D1 | 2026-11-08 | **API model = Free Vision**: TView/TGroup/TWindow/TProgram, `HandleEvent` with phases, commands, `Draw`/`DrawView`, `Execute` for modal views. FV has both loop styles: `TProgram.Run` with overridden `HandleEvent`, and a public `GetEvent`. Both are kept. |
| D2 | 2026-11-08 | **Measure on a prototype before the plan.** Done: the spike, then kklass round K. |
| D3 | 2026-11-08 | **Lives in kcl units.** |
| D4 | 2026-11-08 | **v1** = L0–L3 + one-shot dialogs (face C) + the protocol utility (face B). The file manager comes after v1. |
| D5 | 2026-11-08 | **Wide characters are supported in v1**: CJK and emoji take 2 columns, combining marks 0. |
| D6 | 2026-11-08 | kklass call-path round first (K0–K4 done, K5 dropped, K6 rejected). It ran in parallel; L2 waited for it. Merged and released in 0.1.1. |
| D7 | 2026-11-09 | **Unit names carry the prefix `fv.`**: `uses fv.views, fv.dialogs`. Generic names such as `app` or `views` stay free for user units. |
| D8 | 2026-11-09 | **Mouse in v1**: a click focuses a window, selects a list row or presses a button; the wheel scrolls. |
| D9 | 2026-11-09 | **P0 starts without the owner's real-terminal runs.** A ready terminal-check script with English instructions is part of P0; the owner runs it when convenient. |

## 2. What the measurements say

### 2.1 Numbers (Git-bash 5.3.15, the spike's two-panel scene, median ms)

| action, 80×24 | spike, old kklass | old → new kklass, A/B ratio | expected now |
|---|---|---|---|
| Down, whole list redrawn | 7.0 | 0.74 | ~5.2 |
| Down, 2 rows redrawn (partial) | 4.4 | 0.67 | ~3.0 |
| Down, virtual `GetText` per row | 17.3 | 0.58 | ~10 |
| PgDn | 8.6 | 0.68 | ~5.9 |
| Tab (two windows repainted) | 22.5 | 0.74 | ~17 |
| first paint | 17.6 | 0.87 | ~15 |
| plain functions, Down partial | 0.9 | — | 0.9 |

How these were measured:

* The A/B ran on 2026-11-08 with sides interleaved, 4 rounds, on a machine under outside load.
  The plain-function control came out at 0.88–1.05, which is the noise.
* "Expected now" = the spike's absolute number × the ratio. These are estimates.
* kklass calls per action did not change: 8 per Down, 8 per PgDn, 18 per Tab, 9 per first paint.
* The 200×50 repaints (Tab, first paint, resize) take 35–50 ms, more than the 30 ms target.
  Plain rendering dominates there: plain functions alone take ~28 ms. This is an L1 problem,
  not a kklass one.
* The only Linux numbers come from a VirtualBox guest, about 2× slower than the host. Native
  Linux is measured by the bench workflow (§5.3).

### 2.2 Design rules (spike rules, revised after round K)

1. **No fork on the per-key path.** Forks happen only at start, on resize (`stty size`) and in
   actions that need one, such as a directory listing.
2. **About 15–20 kklass calls per key at most. No call per row or per cell.** A call now costs
   ~0.1 ms alone and ~0.25 ms in a real chain. A virtual call per row still makes a list key 3×
   dearer than without kklass. Lists take a data array plus an optional plain formatter
   function, not a virtual `GetText`.
3. **One screen buffer of row strings with damage tracking.**
   * Per row: a character string and an attribute string of equal length. Each attribute is
     one ASCII symbol indexing a palette, as FV's `GetColor` does.
   * Per row, the leftmost and rightmost written column are recorded.
   * The update emits only damaged ranges, as colour runs, in one `printf` per frame.
   * No FV z-order clip walk and no per-group buffers: views are drawn back to front and
     clipped to their bounds.
4. **Partial redraw for lists and editors.** When the top item does not move, `FocusItem`
   redraws only the old and the new focused row. This is the biggest measured win.
5. **~~Loops in plain helpers~~ — dropped.** Since round K a body is a real function and its
   fields are bound once per call, so a `Draw` with a loop inside is an ordinary method.
   What remains: copy fields that a hot loop reads into locals, because every field access
   goes through a nameref.

### 2.3 What the spike settled

* **Key decoding**
  * One key costs 0.1–0.3 ms.
  * 67 sequences are covered: xterm, mintty, ConPTY, Linux console, rxvt, VT220.
  * The Esc timeout is 0.02 s. On Windows `read -t` waits in 15.6 ms steps, so a lone Esc takes
    ≥ 15.6 ms there.
  * Bug fixed in the spike: a `read -t` that times out may still have read a byte. The byte is
    kept.
* **Diff strategy**: the damage diff beats FV's per-cell binary search by 2× on a scroll, and
  whole-row writes by 2.5× in bytes.
* **Locale**: a UTF-8 locale is needed. In the C locale Cyrillic column counting breaks. The
  cost is +5–10% on Windows and +30–45% in the Linux VM.
* **Free Vision mechanisms**
  * Kept: the view tree, `Insert`, `Current`, the focus chain, `HandleEvent` phases,
    `ClearEvent`, commands, `Draw`/`DrawView`/`Lock`/`Unlock`.
  * Cached: absolute coordinates.
  * Dropped: per-span clipping and group buffers.

## 3. Units (D7)

Each unit is a folder `kcl/fv.NAME/` with `fv.NAME.sh`, `tests/`, `README.md` and `docs/`, the
same shape as every kcl unit. The loader finds `kcl/*/NAME.sh` by stem, and a dotted stem works.
This was checked 2026-11-09: `kk.uses fv.views` loads the unit, its classes build, and
`fv.views.*` functions run.

**Finding K-1 (kkore):** for a dotted unit name, kk.unit declares no namespace. The kklass
guard against a class or instance named like a unit is therefore not applied to `fv.*` names.
This is harmless (a class name cannot contain a dot), but it is undocumented. P0 records it in
the kkore README, or extends the guard if that is cheap.

| unit | FPC/FV source | content | layer |
|---|---|---|---|
| fv.video | rtl-console Video | terminal init/done (raw mode, alternate screen, cursor, autowrap, restore on every exit path), screen size, resize flag; the screen buffer, palette, `UpdateScreen` damage diff, wide characters | L0 + L1 |
| fv.keyboard | rtl-console Keyboard | byte reader with the Esc timeout; sequence → FV key code (`kbUp`, `kbF5`, `kbCtrlLeft`, `kbAltX`, …) and UTF-8 characters | L0 |
| fv.mouse | rtl-console Mouse | SGR 1006 (and X10 fallback) reports → button, wheel, position; enable/disable sequences | L0 |
| fv.drivers | FV Drivers | the event (`FV_EV_WHAT FV_EV_KEY FV_EV_CHAR FV_EV_COMMAND FV_EV_MOUSE_*` globals, string values with FV names, as the spike did with `EV_*`), `GetEvent` = keyboard + mouse + idle + resize; commands are names (`cmQuit`, `cmResizeApp`), no constants table | L0/L2 |
| fv.views | FV Views | TView, TGroup, TFrame, TScrollBar, TListViewer, TWindow | L2/L3 |
| fv.menus | FV Menus | TStatusLine (key table, hints); TMenuBar/TMenuBox per open item O3 | L3 |
| fv.dialogs | FV Dialogs | TDialog, TButton, TStaticText, TLabel, TInputLine, TCheckBoxes, TRadioButtons, TListBox | L3 |
| fv.app | FV App | TProgram, TApplication, TDesktop, TBackground; `Run`, `Execute`, `EndModal`, `cmQuit` | L2 |
| fv.msgbox | FV MsgBox | `MessageBox`, `InputBox` inside a running application | L3 |
| fv.dlg (name per O2) | — (kcl addition) | face C: one-shot dialogs from any script — message, yes/no, input, menu, checklist, radio list | face C |
| fv.serve (name per O5) | — (kcl addition) | face B: a utility that reads commands and writes UI events, the same event stream as `GetEvent` | face B |

Rules for every unit:

* the kcl contract (`kcl/README.md` §1);
* a fork-free per-key path (rule 1);
* every global under the unit's own prefix;
* hot loops in method bodies follow rule 5's remainder.

## 4. Phases

A phase runs as: Opus worker → I review against the live tree → independent critic for
P0–P3 → fixes → local gate → commit. CI runs on the push the owner allows. Nothing is pushed
without the owner's word. The hygiene block (no stray processes, `ktests/tools/strays.sh list --all` in Git-bash and MSYS2 after every
agent) goes into every brief.

### P0 — terminal, keys, mouse, events (L0)

* **fv.video, terminal part:**
  * save `stty -g` once and restore it from EXIT/INT/TERM/HUP, and on `TProgram.Done`;
  * Ctrl-C keeps working;
  * alternate screen, hidden cursor and autowrap off, each undone on exit;
  * size from `stty size` at init and on the resize flag (SIGWINCH sets a flag, the idle
    loop polls it);
  * ASCII frames (`TUI_ASCII=1` in the spike) belong to drawing and move to P1.
* **fv.keyboard:**
  * the spike decoder made a unit, its 67 checks (66 byte strings + one stream case) extended;
  * the Esc timeout and its environment override (open item O1);
  * the partial-read fix.
* **fv.mouse:**
  * SGR 1006 press/release/wheel with modifiers;
  * X10 parsed; it cannot express a column past 223, and xterm's NUL for a past-the-end
    position is read as that clamp;
  * mouse reporting is enabled at init and disabled on every exit path.
* **fv.drivers:** the event globals, `GetEvent` (key, mouse, resize, idle); commands are names,
  not constants.
* **Tests:**
  * decoder tables (byte strings in, codes out, no tty);
  * terminal restore under `script(1)` on every exit path, on Linux, MSYS2 and Cygwin; a
    runtime without `script` is reported as ENV.
* **`tools/fv_termcheck.sh`** + `docs/TERMINAL_CHECK.md` in English (D9). The owner opens the
  script in each terminal (Windows Terminal, mintty, VS Code, conhost) and presses the listed
  keys and mouse actions. The script writes a log the owner sends back. The decoder table grows
  from those logs.
* **Finding K-1** handled (§3).
* **Gate:** the new suites green on bash 5.1/5.2/5.3 (local gate on Git-bash, MSYS2, Cygwin,
  and the lab VMs for 5.1 and Linux); no strays.
* **Task split** (delegation rules: one subsystem × one concern, ~≤300 lines, own gate):
  * P0a: fv.keyboard + fv.mouse decoders, pure, table tests;
  * P0b: fv.video terminal part + fv.drivers `GetEvent`, `script(1)` restore tests;
  * P0c: `tools/fv_termcheck.sh` + TERMINAL_CHECK.md + finding K-1.
* **Requirements on P0b from the P0a review (2026-11-09):**
  * on a tty, bash's `read -n1` puts the terminal into "one char" mode for each read and turns
    ISIG, ICRNL and IEXTEN back on (bash `tt_setonechar`), so `stty raw` alone does not make
    Ctrl+Z / Ctrl+\ arrive as keys: fv.video undefines `susp`, `quit`, `lnext` (and `dsusp`,
    `discard`, `status` where they exist) at init and restores them on every exit path; `intr`
    stays, so Ctrl+C remains an interrupt that restores the terminal (decided 2026-11-09, "Ctrl-C
    keeps working"); CR arrives as LF (both are kbEnter);
  * measure the per-byte cost of `read -n1` on a real pty (`script(1)` on Linux, MSYS2,
    Cygwin) and put it next to the file-fd numbers; if the mode switch costs too much on the
    hot path, report before working around it;
  * fv.video never sends DECKPAM (`ESC =`): keypad application keys `ESC O p..y` clash with
    the vt100 F5–F12 entries (`ESC O t` = F5);
  * a cursor-position query (`ESC [ 6 n`, a later wide-character probe) must read its reply
    with its own reader: `ESC [ r ; c R` decodes as a modified F3;
  * the idle / SIGWINCH loop uses `getKeyEvent 0.05`-style timeouts, not `pollKeyEvent`
    (which peeks, as in FPC); a trap handler only sets a flag.

### P1 — screen buffer (L1)

* **Buffer** (rule 3): row strings plus palette symbols, `SCR_DX1/DX2` damage, colour runs,
  one `printf` per frame. FV's 16-colour palette, with open item O6.
* **Writes:** `fv.video` writes (`WriteStr`, `WriteChar`, `FillRect` equivalents of
  `TDrawBuffer` + `WriteLine`) with clipping to a rectangle.
* **Wide characters (D5):**
  * a built-in width table generated from Unicode `EastAsianWidth.txt` + `emoji-data.txt` +
    general categories Mn/Me/Cf, as range lists in a generated file;
  * the generator lives under `tools/` and its output is committed;
  * fast path: a string with only ASCII, Latin-1, Cyrillic and box drawing skips the table;
  * a wide character takes its cell plus a continuation cell that the update never emits;
  * a write that covers half of a wide character blanks both halves, as ncurses does.
* **Locale:** at init, check that the locale is UTF-8. Behaviour without UTF-8 per open item O4.
* **Tests:** a pure-bash VT model of exactly the sequences fv.video emits (cursor moves, SGR,
  text) replays every frame and compares with the buffer. The spike used Python for this; CI
  rows do not all have Python.
* **Bench:** `tools/bench` gets an `fv` suite: first paint, Down, Down+scroll, Tab and resize at
  80×24 and 200×50. bench.yml then gives the native numbers on all 11 rows (§5.3).
* **Target:**
  * a full 80×24 repaint ≤ 15 ms on Git-bash;
  * 200×50 ≤ 30 ms (today ~28 plain), the stretch goal of this phase.

### P2 — views core and application (L2)

* **Classes:**
  * TView: bounds, state, options, `Draw`, `DrawView`, `HandleEvent`, `GetColor`, `MakeLocal`;
  * TGroup: `Insert`, `Delete`, `Current`, `SelectNext`, phases, `Lock`/`Unlock`, back-to-front
    redraw with an overlap test;
  * TFrame, TWindow (move and resize by keyboard and mouse drag), TDesktop, TBackground;
  * TProgram/TApplication: `Run`, `GetEvent`, `Idle`, `Execute` and `EndModal` for modal views;
  * TStatusLine with a key table.
* **Mouse routing (D8):** hit test by cached absolute bounds, front to back; click to focus;
  wheel to the view under the pointer.
* **Call budget:** a test counts kklass dispatches per Down, PgDn, Tab, click and repaint, and
  fails above the budget (rule 2).

### P3 — widgets (L3)

* **Lists:**
  * TScrollBar;
  * TListViewer/TListBox with partial redraw (rule 4), a data array plus an optional plain
    formatter (rule 2), mouse selection and the wheel.
* **Dialog widgets:**
  * TButton (default, cancel, keyboard and mouse);
  * TStaticText, TLabel (hot key);
  * TInputLine (editing, wide characters, scrolling, selection);
  * TCheckBoxes, TRadioButtons, TDialog.
* **fv.msgbox**: `MessageBox` and `InputBox`.
* **Menus:** TMenuBar/TMenuBox if O3 says v1.

### P4 — one-shot dialogs (face C)

A command that any script can call without writing a class:

* message, yes/no, input, password, menu, checklist, radio list;
* the result in an exit status plus stdout or a chosen fd;
* the terminal restored exactly as found.

Flag compatibility with whiptail/dialog per open item O2.

### P5 — protocol utility (face B)

A long-running process:

* commands on stdin (create a window, add a widget, set a value, show, close);
* UI events on stdout (`key`, `click`, `command`, `value-changed`);
* the event stream is the one `GetEvent` produces.

Line format per open item O5. Tests drive it with scripted command files.

### P6 — release work

* docs (units' README and docs, a tutorial in the kcl README, the kbool README platform note);
* examples: a two-panel viewer, a form, and a one-shot dialog script;
* the bench report;
* CHANGELOG entries.

After v1, the file manager gets its own plan (on `tdirectory.getEntriesInfo`).

## 5. Testing and performance

### 5.1 Headless first

* Every layer above L0 is tested without a terminal:
  * events are injected as globals or byte strings;
  * frames go to a file descriptor;
  * the VT model checks them.
* Only the terminal-restore tests need a pty (`script(1)`).

### 5.2 Limits in tests

Limits in tests are generous, about 2–3× the target, so CI runner noise cannot fail them. The
real targets are read from the bench reports.

### 5.3 Native numbers

Native numbers come from `tools/bench` (fv suite, from P1) on bench.yml's 11 rows: Linux with
bash 5.1/5.2/5.3 on musl and glibc, macOS, Git-bash, MSYS2 and Cygwin. This replaces the VM-only
Linux numbers of the spike.

### 5.4 Targets (Git-bash, 80×24, from §2.1)

| action | target |
|---|---|
| Down (partial) | ≤ 4 ms |
| PgDn | ≤ 8 ms |
| Tab | ≤ 20 ms |
| first paint | ≤ 15 ms |

Linux targets are set after the first native numbers.

## 6. Open items (asked at the phase that needs them, with examples and a recommendation)

| # | Phase | Question | Recommendation |
|---|---|---|---|
| O1 | P0 | Esc timeout default | 0.02 s, override `FV_ESC_TIMEOUT` (0.1 over ssh) |
| O2 | P4 | One-shot dialogs: whiptail/dialog-compatible flags (`--msgbox TEXT H W`) or own syntax? Also the command name | compatible subset: scripts can switch with one word |
| O3 | P3 | TMenuBar/TMenuBox in v1? | yes if P2 lands within budget; the file manager needs them |
| O4 | P1 | Not a UTF-8 locale | try `C.UTF-8` locally in the unit's functions; else ASCII mode with `?` for non-ASCII |
| O5 | P5 | Protocol line format: words with shell quoting, `key=value`, or JSON lines | words with `%q` quoting: bash reads them with `read -a`, no parser needed |
| O6 | P1 | Colours: FV's 16-colour palette only, or 256/true colour too | 16 in v1; the palette symbol leaves room for more |

## 7. Risks

* **Terminals:**
  * Alt needs "Alt as Meta";
  * some terminals capture F10/F11/Alt-Enter;
  * classic conhost needs a TrueType font for box characters (`TUI_ASCII=1`);
  * these are answered by the terminal check (D9).
* **Windows timer:** Esc latency ≥ 15.6 ms.
* **Whole-screen repaints** at 200×50 are over target until P1's work lands.
* **bash 5.1** was not run in the spike; P0's gate includes it.
* **Wide characters:** the width table must match the terminal's. Terminals differ on emoji and
  some symbols. The table follows Unicode 15, and the terminal check logs a sample line so the
  differences can be seen.
