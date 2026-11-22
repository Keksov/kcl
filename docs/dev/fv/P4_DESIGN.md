# fv P4 Stage 0: one-shot dialogs (face C)

> **Status (2026-11-22): design, revision 2 — ACCEPTED.** The owner answered §10 the same day
> with every recommendation: **Q1 c, Q2 `fvdlg`, Q3 c, Q4 b, Q5 b, Q6 c, Q7 c, Q8 a** — recorded
> as PLAN.md D32–D39. So the stage order is 4a-1 → 4a-2 → 4b → 4b-L → the image plan (§11) → 4d
> → 4e. Where the text below says "per Q*n*" or "if Q*n* wants it", read the answer above.
> (Revision 2 came after the independent critic and the supervisor's decisions; the change list
> is §R.) Owner questions: §10 (Q1–Q8). The decisions taken without a question: §0.2. Probes and the
> prototype: Appendix A (the scratch folder `p4/`); the critic's reproducers: `p4/critic/`.

Inputs:
* PLAN.md (D1–D31, §3 the `fv.dlg` row, §4 P4, §6 open item O2) and fv_ledger.json (P3 stages
  3a-1 … 3g, the CI numbers of 3e / 3g);
* P3_DESIGN.md (the structure followed here; §6 fv.msgbox, §8 budgets, §11, §13);
* the READMEs of fv.msgbox, fv.dialogs, fv.app, fv.video (the terminal, exit paths, the reader),
  fv.drivers, fv.keyboard, the kklass book ("Units and uses", "Compiled Caches and Units"),
  kcl/README.md, `fv.app/examples/demo.sh` and `fv.dialogs/examples/widgets.sh` (the headless
  conventions), `fv.msgbox/fv.msgbox.sh`;
* whiptail and dialog: **neither is installed** on the host's Git-bash, MSYS2 or Cygwin (no
  binary, no man page; nothing was installed, VMs were not allowed). Their flags and behaviour in
  §4 are **from knowledge** and marked so; stage 4a-1 checks them on a lab VM that has both
  (Debian ships `whiptail` by default, `dialog` is one package) and turns them into a golden
  table.

To check the numbers I built a **scratch prototype** `p4/proto/fvdlg.sh` (~250 lines): a
one-shot command on the real kcl units with whiptail / dialog-style flags (`--msgbox`,
`--yesno`, `--infobox`, `--inputbox`, `--passwordbox`, `--menu`, `--checklist`, `--radiolist`,
`--title`, `--backtitle`, `--stdout`, `--output-fd`, `--defaultno`, `--default-item`,
`--separate-output`, the button-label flags of both tools), exit 0 / 1 / 255, the result on
stderr / stdout / a chosen fd, and probe hooks (marks with `EPOCHREALTIME`, a fork-free
first-frame hook through fv.views' `__FV_VW_GETEVENT`, dispatch / write counters as fv.views'
test lib has them, a headless mode as the demos have it). Probe drivers: `p4/probe/*.sh`.

**How to read the times.** Laptop on AC power (Windows 11, battery state 2 = mains), CPU sampled
before the runs (VS Code 12 % + 7 % of a core, nothing else above 3 %). Git-bash 5.3.15, MSYS2
5.3.9, Cygwin 5.2.21. Every number is the **median (min–max) of 5 runs** unless marked (the pty
runs: 3 rounds), each run a fresh process. The critic re-ran the Git-bash split (5 runs: msgbox
816 (800–822), input 848 ms) and reproduced it. Laptop numbers are estimates: the absolute
values move with the machine, the **splits and ratios** are what the design uses. CI estimates
use the P3 calibration: the bench stand-in `standin.down` is 5.5–6.0 ms on this laptop
(P3_DESIGN header) and 3.5–5.3 ms on the CI Linux rows (ledger 3e–3g), so **CI Linux ≈ 0.6–0.95 ×
laptop Git-bash** for bash-bound work, and the CI Windows rows ≈ 2.5–2.8 × CI Linux
(msgbox.e2e: Git-bash 122, debian 43 ms, 3e). Forks are the exception: ~15–25 ms each on the
Windows runtimes, ~1 ms on Linux.

---

## R. Revision 2: what changed, per finding

| # | Finding (critic) | Change (section) |
|---|---|---|
| H1 | **The state image freezes the environment**: a real load vs the image under `LANG=ru_RU.UTF-8 FV_HISTORY_SIZE=10 FV_MINWINSIZE_X=20` differ in `__FV_KB_LOC` (ru vs ''), `__FV_VS_LOC`, `FV_HISTORY_SIZE`, `FV_MINWINSIZE_X`, and the image exports `LC_CTYPE=C.UTF-8` (fv.keyboard's load-time export) into every later shell; rev 1's "identical except pids" held only in the same environment | §0.1 corrected; the image is no longer a fv.dlg stage but a **general kbool image** (Q4 (b)) whose first requirement is a per-unit load-time settings hook (§11.2) and an env-diff test (§11.5) |
| H2 | The cache key missed inputs: kkore's config files read at `kbool.sh` load (`KBOOL_CONFIG`, the project file, `~/.kbool/config` / `$USERPROFILE`, `/etc/kbool/config` / `$ProgramData`: kkore/kuse.sh 1066–1075), the root path, `$BASH`, lazily sourced data (fv.keyboard.layouts.sh), `__KK_UNIT_RES` keyed by the calling script's folder | §11.3 (what the image holds and what it never holds: kbool.sh itself is always sourced fresh), §11.4 (the key) |
| M1 | Trust on Windows: rev 1's "mode 0600 + owner check" is POSIX-only; `noacl` mounts store no mode | §11.4: `$LOCALAPPDATA` (per-user ACL) on the Windows runtimes, `-L` refused for the folder and the file, the folder checked to be a directory owned by the user (`-O`), mode checks only where modes exist |
| M2 | A cache inside fv.dlg is the wrong owner (the same need exists for every kcl-heavy program) | **Stage 4c dropped**; Q4 rewritten: (a) no cache in P4, (b) a general `kk.image` plan + critic right after 4b, fvdlg its first user (§11) |
| M3 | P4-6's first reason is false: the reader and the watchdog already close the owner's other fds and point 0 / 2 at `/dev/null` (fv.video.sh 176–185 `_fdclose`, 238–246, 271–279) | P4-6 rewritten: only "no stray output over the dialog"; stderr is **buffered and replayed** after the restore, and only when it is the terminal (§3.2) |
| M4 | `initVideo noalt` still clears the screen (`ESC [ H ESC [ 2 J`, fv.video.sh 667): rev 1's "the infobox stays" was half true; `FV_KBD_PROTO=auto` sends a query + DA1 and an infobox exits without a loop, so a slow reply (ssh) lands on the shell | §5.4: the infobox specified (the clear is kept and said, the cursor's final row, `FV_KBD_PROTO=off` for the infobox) |
| M5 | The alternate screen per call flashes in a loop of calls; dialog by default suppresses the alternate screen on xterm (`--keep-tite` re-enables it) | **owner question Q3** (screen mode) with what a loop of calls looks like under each answer |
| M6 | Parser rules undefined: options after the positionals, `--`, text / tags starting with `-` | §4.5: whiptail-compatible rules decided (no question), golden-table rows listed |
| M7 | The list output format is a real choice (whiptail / dialog quoting, radiolist bare or quoted) | **owner question Q6**; checked on the VM in 4a-2 |
| M8 | Radiolist exclusivity through a dialog `HandleEvent` override would dispatch on every key; menu first-letter jumps and double click unaccounted | §5.1: `TDlgList : TListBox` with a `SelectItem` override (not the dialog: built-in `_lvSelectItem` toggles, fv.views.sh 5852–5863) and a `HandleEvent` override for the letters, **counted** in §6.1 |
| M9 | Stage 4a too large; 4d without a critic; no owner live check; §1.4 (first frame) and §6.2 (exit) measure different things | §8: 4a split into 4a-1 / 4a-2, critic on 4d, an owner live-check step after 4b (English checklist); §1.4 / §6.2 both name "launch → first frame" (target) and "launch → exit" (logged) |
| LOW | `FV_TTY` in the pre-check; SIGTTOU for a backgrounded call; bash 3.2 parse-safety of `bin/fvdlg` (macOS) and BSD `script(1)`; password echo; gauge partial lines; `-1` and `TERM` unset documented; infobox in a session; `FVDLG_NOTTY` inheritance; §1.1's unlisted rows | §3.4, §3.5, §7.1, Q7, §5.1, §4.3, §3.6, §5.4, §3.4, §1.1 footnote |
| corr. | Lever ranking numbers | §1.3: lazy build saves **~43 %** (not 55–60 %); the existing `.ckk` route measured **~300 ms** (ckk source 105 + `kk.uses` 190); the image path **~180 ms real** with TDlgApp inside; the critic's `build()` split (460 of 650 ms inside `build`, class headers 30, declaration verbs ~95, parse ~32) |

Owner questions rev 1 → rev 2: Q1 (flags), Q2 (name), Q3 (no terminal → now Q5) kept; Q4
rewritten; Q5 (gauge / textbox → now Q8) kept; **Q6 (command location) and Q7 (look) decided**
(§0.2: `bin/fvdlg`, FV's look); new: Q3 screen mode, Q6 list output, Q7 password echo.

---

## 0. Summary

### 0.1 What the probes say (details §1, Appendix A)

1. **A one-shot call today costs ~0.75 s headless on every Windows runtime, ~1.3 s on a real
   pty there, and is load-bound.** Of it, **~650 ms is `kk.uses fv.app fv.dialogs`**: parsing
   ~32 ms, the rest is class construction (the critic's split: 460 ms inside `build`, ~95 ms in
   the declaration verbs, ~30 ms in the class headers). The dialog itself (application made,
   built, first frame, Enter, destroyed, application gone) is **~60–80 ms** — about 11–14× the
   stand-in's Down, the same share as fv.msgbox's end-to-end box in P3.
2. **On a real terminal (pty, MSYS2 / Cygwin)** two more pieces appear, both in fv.video:
   `initVideo` ≈ **280–320 ms** (≈ 11 forks) and `doneVideo` ≈ **150–170 ms** (the 0.05 s drain
   and the reader stop). On Linux these are ~15 ms + the 50 ms drain. **P4 does not touch them**
   (finding F-P4-1, §1.4, for the deferred speed work).
3. **A state image cuts the load 7–8×, but not as rev 1 claimed.** Sourcing a snapshot of the
   loaded state takes **77–93 ms instead of ~650 ms** on all three runtimes and every widget
   runs from it. Rev 1 said the image equals a real load except two pids: **that holds only in
   the environment the image was made in.** The critic showed that a real load under another
   locale or with other `FV_*` settings differs from the image (H1): ~40 globals take their
   default from the environment at load (`X=${X:-default}`, among them `FV_KEY_FD`,
   `FV_VIDEO_OUT_FD`, `FV_HISTORY_SIZE`, `FV_MINWINSIZE_X/Y`), fv.keyboard and fv.video derive
   locale state at load, and fv.keyboard exports `LC_CTYPE=C.UTF-8` when no locale is set. A
   correct image needs the units' cooperation — the reason it becomes a **general kbool
   feature** (Q4, §11), not a part of fv.dlg.
4. **The terminal plumbing already holds** (pty probe, 15 runs per runtime, 30 in all):
   `x=$(fvdlg --stdout --inputbox …)` and whiptail's `x=$(fvdlg --inputbox … 3>&1 1>&2 2>&3)`
   both capture the text; Esc → 255, Ctrl+C → 130; `stty -g` equal before and after **every**
   case; `?1049h` / `?1049l`, `?2004l`, `?7h`, mouse off once per run, Ctrl+C included.
5. Counts per one-shot (application made … deleted, headless, the prototype): **15–23
   dispatches, 8–15 writes** (§6; the design's list class adds 2 per key on a list, counted).

### 0.2 Decisions (proposed in this design; the owner sees them here, questions are §10)

| # | Decision | Why |
|---|---|---|
| P4-1 | **One new unit `fv.dlg`** (PLAN §3's row) holding everything one-shot: the argument parser, the widgets, the run / result logic and its small classes (`TDlgApp`, `TDlgList`, `TDlgText`, `TDlgGauge` if Q8 wants it), all built at load. **The command is a short script `bin/fvdlg` at the kbool root** (rev 1's Q6, decided: one folder on `PATH` for this and P5's command; next to the unit it would be a second folder). | One code path for both faces (§2). |
| P4-2 | **Two faces, one parser**: the command takes argv; bash scripts call `fv.dlg.run ARGS…` (the same argv) and get the answer in `RESULT` (+ `FV_DLG_TAGS`) and the same rc; `fv.dlg.begin` / `fv.dlg.end` keep one screen across several dialogs; inside a running fv application `fv.dlg.run` uses its desktop. | §2: per call in one process 67–70 ms headless, 42 ms in a session; on a Windows terminal a session also saves ~450 ms of init / done per dialog. **The session face is the fast path for bash scripts whatever Q4 says.** |
| P4-3 | **Free Vision's look** (rev 1's Q7, decided): a grey dialog with a shadow over the `░` desktop; `--fv-palette gray|blue|cyan` picks FV's dialog palettes. A whiptail-like blue screen can be one more palette value later. | It is what the library is; no behaviour depends on it. |
| P4-4 | **Widgets on P3 classes** (§5): msgbox / yesno / infobox on TDialog + TStaticText + TButton, input / password on TInputLine, the lists on **`TDlgList : TListBox`** with a formatter drawing `[X]` / `(*)` from `Marks`. **Cancel / No send `cmNo`**, so Esc (`cmCancel`) stays distinguishable: Cancel / No → 1, Esc → 255. | Measured on the prototype; long lists are the list (no 32-item TCheckBoxes limit). |
| P4-5 | **The command guards before it loads**, in bash-3.2-safe syntax: bash ≥ 5.1 (`BASH_VERSINFO`), the terminal (`{ : <>"${FV_TTY:-/dev/tty}"; } 2>/dev/null`, fork-free), `TERM` unset / `dumb` = no terminal. A refusal costs bash's start, not the load (today 731 ms). | §3.4, §7.1. |
| P4-6 | **No stray output over the dialog**: while the UI runs, **stderr is buffered and replayed after the restore, only when fd 2 is the terminal** (a file, a pipe or the capture of the swap idiom are left alone); the same for stdout when it is the terminal. The result fd is written after the restore. | M3: the reader / watchdog already close fds; what remains is output landing on the dialog. Buffering keeps every message (parking to `/dev/null` would lose them). |
| P4-7 | **Option placement: whiptail's rules** (§4.5, decided — no trade-off): options anywhere before `--`, the widget's fixed positionals taken literally (text starting with `-` is text), list items in groups, `--` ends options. | Scripts written for whiptail work; dialog's stricter order is a subset. |
| P4-8 | **Size rules**: `0` = fit the text, `-1` = the whole screen (dialog's meaning, documented), a number = clamped to the screen; below a minimum **rc 255 "terminal too small (need W × H, have W × H)"**; a resize re-centres the dialog. | §3.7, §5.3; the 20 × 5 probe. |
| P4-9 | **Text**: `\n` (two characters) → a newline; text that does not fit becomes a scrolling text view (`TDlgText`) — which also gives `--scrolltext` and most of `--textbox`; dialog's `\Z` escapes are stripped (`--colors` accepted). | §4.3. |
| P4-10 | **The infobox** (§5.4): drawn once, no loop, the main screen in every screen mode, **`FV_KBD_PROTO=off`** for it (no reply can arrive after the exit), the cursor left on the screen's last row; the screen is cleared first (fv.video's init clear, whiptail does the same). In a session: drawn on the session's desktop, returns at once. | M4. |
| P4-11 | **The keyboard protocol for the other one-shots stays `auto`** (D30's layout-independent hot keys); `FV_KBD_PROTO` in the environment still wins. | A reply arrives within one round trip; a dialog lives for seconds, so only the loop-less infobox and type-ahead answers are exposed, and the restore's drain covers the local case. |
| P4-12 | **Background jobs**: `fvdlg … &` stops with SIGTTOU at its first `stty` (fv.video; "Stopped (tty output)"), as any full-screen program; `fg` resumes it. Documented, not worked around (ignoring SIGTTOU would draw over the foreground job). | LOW item. |
| P4-13 | **Signals and Esc as fv.video has them**: Ctrl+C → 130, TERM 143, HUP 129, all restored; a lone Esc → 255. | §3.5. |

### 0.3 Owner questions (§10, each with examples)

Q1 the flag set (O2) · Q2 the name · Q3 the screen mode · Q4 the start-up (no cache in P4 / a
general kbool image) · Q5 no terminal · Q6 the list output format · Q7 the password echo · Q8
gauge and textbox in P4 or later.

---

## 1. What a one-shot call costs (question 1, probes)

### 1.1 Headless, a fresh process per call (median (min–max) ms, 5 runs)

The prototype with `FVDLG_HEADLESS=1` (keys from a file, frames to `/dev/null`, as the demos'
`--headless`), launched through `timeout` (in `top`: ~35 ms of the 62 are `timeout`'s own start;
a bare `bash empty.sh` is 27–29 ms). Two probe forks (`forkpre`, `fork1`) are inside the total
and taken out in the "real" line.

| step | Git-bash 5.3.15 msgbox | input | menu | MSYS2 5.3.9 msgbox | input | Cygwin 5.2.21 msgbox | input |
|---|---|---|---|---|---|---|---|
| launch → first line (`timeout` + bash) | 64.7 | 62.3 | 63.3 | 63.3 | 66.1 | 66.0 | 64.2 |
| `source kbool.sh` | 7.7 | 8.6 | 7.9 | 7.2 | 7.4 | 8.2 | 8.0 |
| `kk.uses fv.app` | **387.6** (382–397) | 393.4 | 390.2 | 394.9 | 383.9 | 391.8 | 393.6 |
| `kk.uses fv.dialogs` | **246.9** (240–250) | 240.0 | 246.0 | 241.6 | 242.4 | 250.3 | 240.5 |
| `kk.uses fv.msgbox` | 2.8 | 2.9 | 2.8 | 2.8 | 2.8 | 3.2 | 3.2 |
| the command's class `TDlgApp` built | 10.4 | 10.5 | 11.4 | 10.3 | 10.6 | 10.9 | 10.7 |
| `TDlgApp.new` (InitScreen, desktop; no terminal) | 12.6 | 13.7 | 13.2 | 12.7 | 12.8 | 14.1 | 14.6 |
| the dialog built | 8.2 | 13.6 | 15.9 | 8.3 | 13.3 | 7.7 | 13.3 |
| execView → the first frame | 16.2 | 21.7 | 26.2 | 17.3 | 22.0 | 17.4 | 23.3 |
| the keys → the modal state ends | 14.4 (Enter) | 23.7 (`abc` Enter) | 13.8 (Enter) | 13.6 | 24.2 | 14.3 | 24.2 |
| the dialog destroyed | 3.4 | 5.2 | 5.8 | 3.5 | 6.1 | 3.6 | 5.4 |
| `app.delete` | 4.7 | 4.4 | 4.5 | 4.8 | 4.4 | 4.6 | 4.5 |
| exit (launcher sees it) | 4.0 | 3.9 | 3.9 | 5.1 | 3.7 | 2.9 | 3.0 |
| **total** | **817.8** (810–843) | 857.3 | 851.3 | 827.2 | 838.3 | 831.8 | 855.0 |
| **real** (− `timeout`'s ~35 − the two probe forks ~39) | **~745** | ~785 | ~780 | ~755 | ~765 | ~760 | ~785 |
| of it: load (kbool + units + class) | 655 | 655 | 658 | 656 | 645 | 664 | 656 |
| of it: the dialog (app … delete) | 60 | 83 | 79 | 60 | 83 | 62 | 85 |

Rows not listed (each ≤ 0.3 ms, in the total): the argument parse (`args`), the hook install
(`hook`), the probe fork's own start mark (`fork0`) and the result write (`out`). The checklist
(Space, Down, Space, Enter) and the yes/no box land between these rows (Git-bash checklist total
857 (847–866), 3 runs). The three runtimes agree within 2–3 % headless: the cost is bash work,
not forks.

**Where the load goes** (`probe/load_split.sh`, one process, Git-bash, 2 runs; the critic's
`critic/build_time.sh` splits the same 650 ms into `build` 460, the declaration verbs ~95, the
class headers ~30, parsing ~32):

| unit | `kk.uses` ms | parse only (eval inside `if false`) | classes built |
|---|---|---|---|
| kbool.sh | 6.3 | — | — |
| kklass + kklass_pascal | 15.2 | 4.8 | — |
| fv.unicode, fv.keyboard, fv.mouse, fv.video, fv.drivers | 18.9 | 6.5 | — |
| fv.views | **193** | 9.7–11.8 | 6 (TView TGroup TFrame TScrollBar TListViewer TWindow) |
| fv.menus | 80 | 2.6 | 5 (TStatusLine TMenuView TMenuBar TMenuBox TMenuPopup) |
| fv.app | 80 | 1.2 | 4 (TBackground TDesktop TProgram TApplication) |
| fv.histlist | 6.5 | — | — |
| fv.dialogs | **248** | 4.6 | 13 (TDialog … THistoryWindow) |
| fv.msgbox | 3.0 | — | — |

### 1.2 On a real pty (MSYS2 and Cygwin; script(1)'s own pty, never this terminal)

`probe/pty_run.sh`: 3 rounds × 5 cases in one `script -qec` session per runtime, each case
synchronised by a ready file the prototype makes at its first frame; the feeder waits 0.3 s, then
types. Git-bash has no `script(1)`: not measured there (headless only, same as MSYS2's).

| step (ms, 12 timed runs per runtime) | MSYS2 5.3.9 | Cygwin 5.2.21 |
|---|---|---|
| load (kbool + units + class) | 665–700 (one 880) | 655–700 |
| `TDlgApp.new` **with `initVideo`** (stty ×4, `trap -p` ×5, the reader and the watchdog) | **281–305** (outliers 543, 600) | **285–321** (outliers 543, 580) |
| build + first frame | 25–40 | 25–37 |
| keys → end (incl. the feeder's 0.3 s pause and ≤ 50 ms poll) | 361–450 | 361–437 |
| destroy | 4–7 | 4–6 |
| `app.delete` **with `doneVideo`** (the drain, the reader stopped) | **150–180** (one 390) | **152–170** |
| **launch → first frame** | **~1.0 s** | **~1.0 s** |
| **launch → exit, without the feeder's pause** | **~1.25–1.35 s** | **~1.25–1.35 s** |

Behaviour, every one of the 15 runs per runtime (30 in all): rc 0 for Enter, `abc` captured by
`x=$(fvdlg --stdout --inputbox …)`, `xy` captured through whiptail's swap `3>&1 1>&2 2>&3`, rc 255
for Esc, rc 130 for Ctrl+C; `stty -g` identical before and after every case; both typescripts
hold 15 × `?1049h`, 15 × `?1049l`, 15 × `?2004l`, 15 × `?7h` and the mouse-off sequence on every
exit (Ctrl+C runs included).

### 1.3 Load levers — measured, and how they rank

| lever | measured | load (Git-bash) | headless total | notes |
|---|---|---|---|---|
| none (today) | yes | ~650 ms | ~745 ms | |
| **state image** (`probe/snap_make.sh`: every variable the load made, arrays element by element with `printf %q`, declared-but-unset variables from `declare -p` (`compgen -v` misses them), `declare -f`, `shopt -p`; 1.6 MB; written in 1.8 s) | yes (all three runtimes; critic re-measured 80 ms) | **77–93 ms** | 294–330 ms with the command's class built at run time (42–46 ms: kklass's first capture setup forks an `rm`); **~180 ms real** with `TDlgApp` inside the image and without `timeout` (critic) | correct **only in the environment it was made in** (H1, §11.2) |
| existing kklass `.ckk` caches (`kklass_compiler` on fv.app + fv.dialogs, then the normal `kk.uses`, which runs the unit bodies and skips the cached classes) | yes (critic, `critic/ckk_load.sh`) | **~300 ms** (ckk source 105 + `kk.uses` 190) | ~400 ms (est.) | overlap warnings; still runs every unit body |
| lazy class build (build a class at its first `.new`; a msgbox uses 11 of 28 classes, a menu 14) | no (critic's estimate from the build split) | ~370 ms (**−43 %**) | ~470 ms (est.) | a kklass change with a critic |
| smaller unit set | — | — | — | nothing to drop without splitting units (fv.app needs fv.menus; fv.dialogs carries THistory*) |
| a resident server | — | — | — | that is face B (P5) |

**The image is the strongest lever by far, and the hardest to get right**: §11 lists what it
needs (H1 / H2 / M1). Rev 1 put it into fv.dlg as stage 4c; revision 2 moves it out (M2): the
same need exists for every program that loads many kcl classes, the fix for H1 belongs in each
unit, and the trust and staleness rules belong in kkore. Q4 asks whether P4 waits for it.

### 1.4 What is acceptable (proposal) and finding F-P4-1

A person answers a dialog in seconds, so what matters is **launch → first frame**; **launch →
exit** delays the script's next step and is logged next to it.

| launch → first frame | feels | today | with a general image (Q4 (b)) |
|---|---|---|---|
| ≤ 0.3 s | immediate | — | headless all runtimes (~0.15 s); CI Linux real terminal (est. ~0.15–0.2 s) |
| 0.3–0.8 s | a visible pause, acceptable for one question | headless all runtimes (~0.7 s); CI Linux real terminal (est. 0.45–0.7 s) | Windows real terminal (~0.45 s; exit + ~0.16 s) |
| > 0.8 s | sluggish | **Windows real terminal ~1.0 s to the frame, ~1.3 s to the exit** | — |

For scale: whiptail and dialog (C, newt / ncurses) start in tens of milliseconds; they are not
on this machine to measure. **Proposed targets** (CI Linux, headless, launch → first frame):
**≤ 0.8 s without an image, ≤ 0.3 s with it**; launch → exit logged (≈ the first frame + the
keys + ~10 ms + the restore); the Windows rows tracked as ratios to Linux, not blocking (D20).

**F-P4-1 (for the owner's deferred speed work, not planned in P4):** on the Windows runtimes
`initVideo` + `doneVideo` cost ~450 ms per terminal session — ~11 forks at init (5 of them `trap
-p`, one per saved signal; `stty -a` once per process), the reader's two process substitutions,
the 0.05 s drain and the reader stop (~70–95 ms) at done. A one-shot pays it per call; the
session face (P4-2) pays it once. Folding the five `trap -p` into one and the `stty` calls into
fewer would roughly halve the init; that is fv.video work and stays with stages 3v-2…3v-5.

---

## 2. Two faces of one feature (question 2)

### 2.1 The command (any script, any language)

```sh
fvdlg --title 'Disk' --yesno 'Format /dev/sdb1?' 0 0 && format_it
name=$(fvdlg --stdout --inputbox 'Your name:' 0 0 "$USER") || exit
pick=$(fvdlg --menu 'Pick a fruit' 0 0 0 a Apple b Banana 3>&1 1>&2 2>&3)   # whiptail's idiom
```

`bin/fvdlg` = the guards of P4-5 (before any load), `source "$KBOOL/kbool.sh"`, `kk.uses fv.dlg`
(or the general image, Q4), `fv.dlg.main "$@"; exit $?`. Answers: the exit status (§3.3) and the
result (input text, menu tag, the checked tags) on stderr by default, stdout with `--stdout`, fd N
with `--output-fd N`.

### 2.2 Sourced functions (bash scripts that use kbool)

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.dlg

fv.dlg.run --title Disk --yesno 'Format /dev/sdb1?' 0 0 && format_it
fv.dlg.run --inputbox 'Your name:' 0 0 "$USER" && name=$RESULT
fv.dlg.run --checklist 'Packages' 0 0 0 git Git on vim Vim off curl curl on
case $? in 0) printf 'chosen: %s\n' "${FV_DLG_TAGS[@]}" ;; 1) echo cancelled ;; 255) echo 'Esc or no terminal' ;; esac

fv.dlg.begin --backtitle 'Setup'           # one screen for several questions
fv.dlg.run --inputbox 'Host:' 0 0 localhost && host=$RESULT
fv.dlg.run --passwordbox 'Password:' 0 0 && pass=$RESULT
fv.dlg.end
```

* **`fv.dlg.run ARGS…`** takes the command's argv exactly (one parser, one set of rules); the
  answer goes to `RESULT` (and `FV_DLG_TAGS` for the list widgets, `FV_DLG_CMD` the FV command
  that ended it), **nothing is printed** unless `--stdout` / `--output-fd` is given; the rc is
  the command's exit status.
* **No session, no application** (the plain case): the call makes the application, runs the
  dialog and deletes the application — **67–70 ms per call headless after the load** (probe
  `session.sh`), plus the terminal's init / done on a real terminal (~450 ms on Windows, ~65 ms
  on Linux).
* **`fv.dlg.begin [--backtitle T] [screen-mode flags]` / `fv.dlg.end`**: the application is made
  once and kept; each `run` is then **~42 ms headless** and the screen does not change mode
  between questions. A script that exits without `end` still gets its terminal back (fv.video
  restores it on every exit path).
* **Inside a running fv application** (`FV_APP` live): `run` builds its dialog on the existing
  desktop (as fv.msgbox does; a background title is ignored), so an application can ask a
  checklist in one line.
* **`$( fv.dlg.run … )`**: works without a session (the subshell owns its own terminal, fv.video
  "owned by the process that called initVideo") but costs the whole init; inside a session it is
  refused by the owner rule (rc 2, one `Error:` line, fv.msgbox's wording) — the answer is in
  `RESULT` anyway.

### 2.3 How they share code

```
bin/fvdlg ──(guards, load)──► fv.dlg.main argv ─┐
                                                 ├─► fv.dlg._parse argv  → the call record
fv.dlg.run argv ─────────────────────────────────┘   fv.dlg._screen      → app / session / host app
                                                      fv.dlg._W_<widget>  → build on fv.dialogs
                                                      fv.dlg._exec        → execView, result, rc
                                                      fv.dlg._emit        → fd (command) or RESULT
```

`main` differs from `run` only in: P4-6's buffering, printing the result, `exit` instead of
`return`, and the usage / version flags. Both refuse in the same words.

---

## 3. Terminal handling (question 3, probed on a pty)

### 3.1 Where the UI draws and reads

fv.video opens `FV_TTY` (default `/dev/tty`) and draws and reads there, never on stdin / stdout
(README "The terminal"). So **`x=$(fvdlg …)` works as is**, with stdin redirected too (the probe
captured through both idioms). The reader and the watchdog close the owner's other fds and
point their own 0 / 2 at `/dev/null` (fv.video.sh 176–185, 238–246, 271–279), so a capture pipe
reaches its end of file when the command exits.

### 3.2 Where the result goes, and P4-6

| flag | result written to | the idiom |
|---|---|---|
| (none) | **stderr** (fd 2), as whiptail and dialog | `x=$(fvdlg --inputbox … 3>&1 1>&2 2>&3)` |
| `--stdout` | stdout | `x=$(fvdlg --stdout --inputbox …)` (dialog's flag) |
| `--stderr` | stderr (dialog's explicit default) | — |
| `--output-fd N` | fd N (both tools) | `fvdlg --output-fd 3 --inputbox … 3> answer.txt` |

Written once, after the terminal is restored, without a trailing newline (as both tools, from
knowledge; the list widgets with `--separate-output`: one tag per line, each line ending in a
newline). Nothing is written for Cancel / No / Esc / errors (whiptail writes nothing then;
dialog may write the input text on Cancel — not copied).

**P4-6, output during the UI**: a message written to the terminal while the dialog is shown
(a `kk.debug` line with `VERBOSE_KKLASS=debug`, a bash error, a script's background job) would
land on the dialog. The command therefore points **fd 2 — and fd 1 — at a private buffer file
while the UI runs, but only when that fd is the terminal** (`[[ -t 2 ]]`); after `doneVideo` it
copies the buffer to the real fd (fork-free: `mapfile` from a read fd opened on the same file)
and removes it (one `rm`, ~20 ms on Windows — only when the buffer was made). A fd that is a
file, a pipe or a capture (the swap idiom's fd 2) is never touched. The buffer lives in the
user's temp folder, created under `umask 077` and noclobber (kklass's `kk._fn_text_open`
pattern). Alternative considered: parking to `/dev/null` (simpler, loses messages) — rejected.

### 3.3 Exit codes

| code | when | whiptail | dialog |
|---|---|---|---|
| 0 | OK, Yes, an item chosen | same | same |
| 1 | Cancel, No | same | same |
| 255 | Esc, the end of input, **no terminal / too small / bad arguments** | same (−1) | same (−1) |
| 130 / 143 / 129 | Ctrl+C, SIGTERM, SIGHUP (fv.video's exit path: restore, then die of the signal) | (newt: dies) | (dialog: its own handling) |

dialog's 2 (Help), 3 (Extra), 5 (timeout) and the `DIALOG_*` environment overrides are not in
the subset (§4.2); `--help-button` / `--extra-button` are refused with rc 255 (one line), not
ignored, so a script that relies on them notices.

### 3.4 No terminal (CI, cron, ssh without `-t`, Emacs `M-x shell`)

* The command tests **before loading**, in bash-3.2-safe syntax: `{ : <>"${FV_TTY:-/dev/tty}";
  } 2>/dev/null` (fork-free; opening is harmless, nothing is written; the same path fv.video
  will open), and `TERM` unset / `dumb` (§3.6). Today the prototype refuses only after the full
  load: **731 ms** for an rc 255; the pre-check costs microseconds.
* What then — **owner question Q5**: refuse (dialog's behaviour), refuse + an opt-in default
  answer, or a line-mode fallback. Recommended: refuse + opt-in.
* **Inheritance warning** (documented next to the opt-in): an exported `FVDLG_NOTTY=default`
  reaches every child script, so every `fvdlg` below it answers by itself; the per-call flag
  `--no-tty=default` does not leak. CI job definitions are the intended place for the variable.

### 3.5 Signals, resize, Esc, background

* **Ctrl+C**: `intr` stays on (fv.video), the restore runs, rc 130 (probe: 6 / 6, terminal
  restored). Under the kitty keyboard protocol the same (fv.keyboard raises SIGINT).
* **SIGTERM / SIGHUP**: fv.video's rows (143 / 129, restored).
* **SIGWINCH**: fv.app's `TProgram.GetEvent` hands `cmResizeApp` to the application's
  `HandleEvent` at once (fv.app.sh 733), so **`TDlgApp.HandleEvent` re-centres the dialog**
  (`fv.views.locate` to the new centre, clamped) and checks P4-8's minimum again — a resize
  below the minimum ends the dialog with rc 255 and the message after the restore. That
  override sees only what reaches the application (resizes, unhandled commands), not the keys of
  the modal dialog: no per-key dispatch.
* **Esc**: fv.keyboard's timeout (`FV_ESC_TIMEOUT`, 0.02 s; ≥ 15.6 ms on Windows) — a lone Esc
  is `cmCancel` → **255**. At the end of a key file (headless tests) a trailing Esc is resolved by
  the end of file.
* **A backgrounded call** (`fvdlg … &`): stopped by SIGTTOU at its first `stty` (P4-12).

### 3.6 `NO_COLOR`, `TERM`, colours

* **`TERM` unset or `dumb`** → treated as "no terminal" (Q5's answer applies); `FVDLG_FORCE=1`
  overrides. Why unset counts too: cron and many service managers run without `TERM`, and a
  full-screen program there cannot know the terminal's sequences; a real terminal always sets
  it. Documented. `TERM=linux` → 16 colours (fv.video), `*256color` / `COLORTERM` → 256, other
  values → one `tput colors` fork (fv.video; ~20 ms on Windows — `FV_COLORS=16|256` skips it).
* **`NO_COLOR`** (any non-empty value, no-color.org) → the command switches the application to
  a **black-and-white palette** (FV's `apBlackWhite` idea: the dialog entries mapped to grey /
  white / black, the focused button and the list's focused row in reverse) before the first
  paint, through `fv.app.setAppPalette` on the ~32 dialog entries. fv.app itself does not read
  `NO_COLOR` (unchanged); the cost is measured in 4a-1.
* A non-UTF-8 locale → fv.video's D11 rule (local `C.UTF-8`, else ASCII mode).

### 3.7 A small terminal

P4-8: clamp to the screen, refuse below the minimum with rc 255 and `fvdlg: terminal too small
(need 24x7, have 20x5)`. The probe at 20 × 5 shows why: a yes/no box drew its buttons over the
frame, a menu lost its list and still answered the focused tag.

### 3.8 "Restored exactly as found"

fv.video already restores, on every exit path: `stty`, the alternate screen, the cursor
(visible, default shape `ESC [ 0 SP q` when a shape was sent), autowrap, mouse reporting,
bracketed paste, the kitty keyboard flags (popped only when pushed), the caller's traps, and
drains late input (probe: 30 / 30 runs, both typescripts: 15 × each sequence). **The command
adds**: P4-6's buffering, the screen mode of Q3, the infobox rules (P4-10), the pre-load guards
(P4-5), and its own exit codes. Known limits, documented (fv.video's): the cursor shape returns
to the terminal's default, not one the shell set; with the main screen (Q3 (b)) the screen's
earlier contents are **not** brought back — that is the point of that mode; `--clear` (both
tools) clears the screen at exit in that mode.

---

## 4. O2: the flag set (question 4, owner question Q1)

### 4.1 whiptail and dialog (from knowledge — neither is installed here; checked on a VM in 4a-1)

| | whiptail (newt 0.52) | dialog (1.3) |
|---|---|---|
| widgets | `--msgbox --yesno --infobox --inputbox --passwordbox --textbox --menu --checklist --radiolist --gauge` | all of whiptail's + `--buildlist --calendar --dselect --editbox --form --fselect --inputmenu --mixedform --mixedgauge --passwordform --pause --prgbox --programbox --progressbox --rangebox --tailbox --tailboxbg --timebox --treeview` |
| numbers | `TEXT HEIGHT WIDTH` (+ `LIST-HEIGHT` for the lists); auto size (0) not documented | the same; `0` = auto size, `-1` = maximum |
| list items | `TAG ITEM` (menu), `TAG ITEM STATUS` (`on` / `off`) | the same (+ `--item-help`: one more column) |
| common options | `--title --backtitle --defaultno --default-item --nocancel --yes-button --no-button --ok-button --cancel-button --noitem --notags --separate-output --output-fd --scrolltext --fb/--fullbuttons --topleft --clear` | `--title --backtitle --defaultno --default-item --nocancel/--no-cancel --yes-label --no-label --ok-label --cancel-label --no-items --no-tags --separate-output --output-fd --stdout --stderr --clear --colors --no-collapse --cr-wrap --trim --insecure --ascii-lines --no-shadow --timeout --aspect --and-widget --keep-window --keep-tite --erase-on-exit --extra-button --help-button --single-quoted --separator` |
| screen | newt / slang; uses the terminal's alternate screen where its terminfo has one | ncurses; **on xterm-like terminals suppresses the alternate screen by default**, `--keep-tite` re-enables it |
| result | stderr (or `--output-fd`) | stderr (or `--stdout`, `--output-fd`) |
| checklist result | `"tag1" "tag2"` (double-quoted, space-separated); `--separate-output`: one per line | double-quoted by default (`--single-quoted`: only as needed); `--separate-output` the same |
| radiolist result | the tag (believed bare) | the tag (believed bare) — both checked on the VM (Q6) |
| exit | 0 / 1 / 255 (Esc) | 0 / 1 / 2 Help / 3 Extra / 4 Item-help / 5 timeout / 255 Esc or error; `DIALOG_OK` … env overrides |
| text | `\n` in TEXT is a newline; lines wrapped | `\n` a newline; whitespace collapsed and text re-wrapped unless `--no-collapse` / `--cr-wrap`; `\Z0`…`\Z7`, `\Zb`, `\Zr`, `\Zu`, `\Zn` colours with `--colors` |
| password | shows `*` per character | shows nothing unless `--insecure` (then `*`) |
| `--gauge` | reads lines from stdin: a number = the percentage; `XXX` / percentage / text / `XXX` replaces the text | the same |
| option placement | popt: options may come anywhere, also after the widget's arguments; `--` ends them | common options before the widget option (and between widgets with `--and-widget`) |

### 4.2 Options (what a user writes and sees) — Q1

* **(a) A compatible subset** — only flags both tools have, with their spellings; nothing of
  fv's own. `fvdlg --title Disk --yesno 'Format /dev/sdb1?' 10 40` after `whiptail …`: one word
  changed; an option outside the subset (`--colors`, `--extra-button`) → rc 255 with one line.
* **(b) Own syntax** — `fvdlg yesno --title Disk 'Format /dev/sdb1?'`; shorter and sized
  automatically, but every whiptail / dialog script has to be rewritten.
* **(c) Compatible flags + a few extras (recommended)** — (a), both tools' spellings of the same
  option (`--yes-button` and `--yes-label`, `--nocancel` and `--no-cancel`, `--notags` and
  `--no-tags`), dialog's `0` / `-1` sizes for both, plus fv's own flags under one prefix so they
  never clash with a future whiptail / dialog flag: `--fv-palette gray|blue|cyan`,
  `--fv-ascii`, `--fv-mouse off`, `--fv-size WxH` + `--fv-keys FILE` + `--fv-out FILE` +
  `--fv-times FILE` (headless, for tests and the bench), `--version`, `--help`.

### 4.3 What is hard to match, and the proposal for each

| item | proposal |
|---|---|
| dialog's `\Z` colour escapes | `--colors` accepted, the escapes **stripped** in v1 (a later stage could map `\Zb`/`\Zr`/`\Z0-7` onto palette entries) |
| dialog's whitespace collapse + re-wrap by default | **whiptail's rule** (keep the text's newlines, wrap long lines at blanks — TStaticText's own rule); `--no-collapse` / `--cr-wrap` / `--trim` accepted as no-ops (documented) |
| auto sizing (0) | fit the wrapped text, at most 2/3 of the screen width for the text, at least the buttons' width; dialog's exact `--aspect` rule is not copied (documented) |
| `-1` = maximum | dialog's meaning: the screen minus the background title row (documented; whiptail has no `-1`) |
| `--gauge` reading stdin while the UI runs | a progress view and a stdin poll from `Idle` — Q8; **partial lines**: the poll reads with `read -t 0.01 -r` and keeps what a timed-out read returned (fv.keyboard's partial-read rule), so a writer that flushes `4` and later `2\n` gives 42, never a lost digit; stdin a terminal → refused |
| `--textbox FILE` | the scrolling text view of P4-9 over the file's lines — Q8 |
| `--and-widget`, forms, calendars, file selectors | not in P4 (the plan's widget list); refused with rc 255 |
| dialog's exit codes 2 / 3 / 5, `DIALOG_*` env | not in the subset; refused flags rather than silent differences |
| password echo | Q7 (whiptail `*` / dialog nothing) |
| whiptail's `--fb` (full buttons), `--topleft`, `--scrolltext` | `--fb` no-op (FV buttons are always full), `--topleft` places the box at (0, 0) (+ the backtitle row), `--scrolltext` = P4-9's text view |
| dialog's `--keep-tite` / `--erase-on-exit` | mapped onto Q3's screen modes (§10 Q3) |

### 4.4 The name (owner question Q2)

Names to avoid (they exist): `dialog` (cdialog), `whiptail` (newt), `Xdialog`, `gdialog`,
`kdialog` (KDE), `zenity`, `yad`, `qarma`, `lxdialog` (Linux kernel tree), `gum` (Charm),
`fdialog` (a Go GUI tool), `fvdemo` (fv-go's Turbo-Vision demo). A web search found **no package
or command `fvdlg` or `fvdialog`**.

### 4.5 Parser rules (P4-7, decided: whiptail-compatible)

1. **Options are recognised anywhere before `--`**, also after the widget's arguments
   (`fvdlg --msgbox 'Hi' 10 40 --title T` = `fvdlg --title T --msgbox 'Hi' 10 40`, as popt does
   for whiptail). dialog's order (options first) is a subset of this.
2. **The widget flag takes its fixed positionals literally**: `--msgbox TEXT H W`,
   `--inputbox TEXT H W`, `--menu TEXT H W LH` — TEXT may start with `-` (`--msgbox '-5 °C'
   0 0`) or even look like an option; H, W, LH must be integers (`-1` allowed) or the call is
   refused (255, one line naming the argument).
3. **Optional positionals** (`--inputbox`'s INIT, `--gauge`'s PERCENT): the next argument is
   taken as the positional unless it is exactly a known option of the subset; `--` before it
   forces the positional (`fvdlg --inputbox 'Name:' 0 0 -- --weird-default`).
4. **List items** (`TAG ITEM [STATUS]`, groups of 2 or 3): taken group by group; an argument
   that is exactly a known option **at a group boundary** is an option (so trailing options
   work), inside a group it is data; `--` makes everything after it data (tags such as `-` or
   `--all`). A STATUS must be `on` / `off` (any case; `1` / `0` and `yes` / `no` refused — to be
   checked against whiptail on the VM).
5. **One widget per call**; a second widget flag → 255 ("one widget per call; --and-widget is
   not supported").
6. `--option=value` and `--option value` both accepted for valued options.

Golden-table rows (4a-1, each run through whiptail and dialog on the VM and through `fvdlg`,
the argv parse and the rc compared): options before / after / between the positionals; TEXT
`-5`, `--title`, an empty TEXT; H W `0 0`, `-1 -1`, `x 10`; INIT omitted / `-x` / after `--`;
menu tags `-`, `--`, `--title` inside and after `--`; checklist STATUS `ON`, `1`; a missing ITEM
at the end; two widgets.

---

## 5. Widgets on P3 classes (question 5)

### 5.1 Mapping

| widget | built from | answer | notes |
|---|---|---|---|
| `--msgbox TEXT H W` | `TDialog` + `TStaticText` (or `TDlgText` when the text does not fit) + one `TButton` OK (`cmOK`, default) | rc 0 / 255 | fv.msgbox's look; **not** `fv.msgbox.messageBox` itself (fixed 40 × 9, fixed titles, no H W) — its placement rules reused |
| `--yesno` | + `TButton` Yes (`cmYes`) / No (`cmNo`); `--defaultno`: No selected and default | 0 / 1 / 255 | |
| `--infobox` | §5.4 | 0 | |
| `--inputbox TEXT H W [INIT]` | + `TInputLine` (MaxLen 1024 clusters; INIT through `fv.dialogs.setText`: selected, the first key replaces it — FV / fv.msgbox's rule) + OK / Cancel (`cmNo`) | 0 + text / 1 / 255 | the clipboard keys, bracketed paste, history off |
| `--passwordbox` | the same with `PasswordChar` per Q7 | 0 + text / 1 / 255 | |
| `--menu TEXT H W LH TAG ITEM…` | **`TDlgList : TListBox`** + `TScrollBar` (shown only when the items do not fit) over the tags, a formatter drawing `tag  item`; Enter = OK (the default button); `--default-item` = `listFocusItem`; `--notags` / `--noitem` drop a column | 0 + tag / 1 / 255 | **first-letter jump** and **double click → OK**: below |
| `--checklist … TAG ITEM STATUS…` | `TDlgList` with `Marks` (D26; `on` → set), the formatter drawing `[X]` / `[ ]` from `Marks`; Space / Ins toggle (fv.views' built-in) | 0 + tags (Q6's format) / 1 / 255; `FV_DLG_TAGS` in the sourced face | 10 000 items are fine (fv.dialogs 010) |
| `--radiolist` | the same with `(*)` / `( )`; **exactly one mark** through `TDlgList.SelectItem` (below) | 0 + tag / 1 / 255 | the prototype lacked this |
| `--gauge TEXT H W [PCT]` (Q8) | `TDlgGauge : TView` (a bar `███░░░ 42%`), `TDlgApp.Idle` polls stdin (§4.3's partial-line rule) | 0 at stdin's end | missing today: the view and the poll |
| `--textbox FILE H W` (Q8) | `TDlgText` (P4-9) over the file's lines + OK | 0 / 255 | `mapfile` the file (≤ a size cap) |

**`TDlgList : TListBox`** (built at the unit's load) carries the list behaviour whiptail /
dialog users expect, with the dispatches counted (§6.1):
* **`SelectItem ITEM` override** (virtual; called by Space, Ins and a double click only — not
  per key): for a **radiolist** it does *not* call the built-in (fv.views' `_lvSelectItem`
  toggles the mark, fv.views.sh 5852–5863, so a second Space would clear the only mark): it
  sets `Marks` to ITEM alone, repaints the old and the new marked rows (`listDrawItem`) and
  sends the same `cmListItemSelected` broadcast; for a **checklist** it calls `inherited`
  (the toggle); for a **menu** a double click ends the dialog with `cmOK` (`EndModal` on the
  owner), Space does nothing (whiptail). Cost: one dispatch per Space / Ins / double click.
* **`HandleEvent` override**: a printable character jumps to the next tag starting with it
  (case-insensitive, wrapping; whiptail / dialog), everything else goes to `inherited`. Cost:
  **2 dispatches per key that reaches the list** (the override + `inherited`; P3's counting) —
  ~0.25–0.5 ms per key. The alternative without a per-key dispatch (registering every tag's
  first letter in fv.views' hot-key map as the list's keys) touches fv.views and is not taken.

The other classes: `TDlgApp : TApplication` (no status line; `HandleEvent` for `cmResizeApp`
only, §3.5; `Idle` for the gauge), `TDlgText : TListViewer` (read-only: its focused row drawn
like the others through a `GetPalette` override, arrows / PgUp / PgDn scroll), `TDlgGauge :
TView`. **No override of a control's per-key virtual except `TDlgList.HandleEvent`**, so the
boxes and the input line keep fv.dialogs' 0 dispatches per key.

Prototype screens (headless, 80 × 24, the desktop pattern `░` shown as `.`):

```
......................╔═[■]═════════ Hello ═════════════╗.......................
......................║ Hello, world!                   ║.......................
......................║ This is a one-shot message      ║.......................
......................║  box.                           ║.......................
......................║               OK  ▄             ║.......................
......................║             ▀▀▀▀▀▀▀             ║.......................
......................╚═════════════════════════════════╝.......................

........................╔═[■]═══════ Pick ════════════╗.........................
........................║ Choose some:                ║.........................
........................║                             ║.........................
........................║   [ ] a  Apple            ▲ ║.........................
........................║   [X] b  Banana           ▓ ║.........................
........................║   [ ] c  Cherry           ▼ ║.........................
........................║                             ║.........................
........................║       OK  ▄    Cancel ▄     ║.........................
........................║     ▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀     ║.........................
........................╚═════════════════════════════╝.........................
```

(The prototype's auto width was 2 cells too narrow for the first text — "box." wrapped; and it
shows the bar when the items fit: both are 4a's sizing rules, P4-8.)

### 5.2 The background

* With the alternate screen (Q3 (a)): the caller's screen comes back after the dialog; during
  it the screen shows the application's desktop (FV's `░` pattern) and the dialog centred.
* With the main screen (Q3 (b)): the same picture is drawn over the caller's screen, which
  scrolls away; after the exit the last dialog stays visible above the shell's next output
  (`--clear` / `--erase-on-exit` clear it).
* `--backtitle T`: a one-row `TStaticText` at row 0 over the desktop (the prototype does this).
* No status line (TDlgApp; D23 already gives no menu bar).
* Inside a host application (P4-2), the host's screen is the background.

### 5.3 Sizes: FV's auto size vs the H W numbers

`0` → the fit (P4-8), a number → that size clamped, `-1` → the maximum. For the lists, LH `0` →
as many rows as items up to the room left. The text area wraps (TStaticText) and becomes
`TDlgText` when it needs more rows than the box has.

### 5.4 The infobox (P4-10)

* **The main screen in every screen mode**: `fv.video.initVideo noalt` before the application
  is made (fv.app then finds the terminal on and leaves it to the command), so the box stays
  visible after the exit — the whole point of a "please wait" box.
* **The clear stays**: fv.video's init clears the screen (`ESC [ H ESC [ 2 J`, fv.video.sh 667)
  in `noalt` mode too; whiptail's infobox clears too, so the behaviour matches; documented. Not
  changed (fv.video).
* **No loop**: built, drawn once (the first paint), the application deleted, the terminal
  restored; rc 0.
* **`FV_KBD_PROTO=off` for the infobox** (unless the environment sets it): `auto` sends the
  kitty query and DA1, and a loop-less exit leaves no time for the reply — over ssh it would
  arrive after the restore and land on the shell as text. With `off` nothing is asked.
* **The cursor**: before `doneVideo` the command puts the hardware cursor on the screen's last
  row, column 0, and shows it, so the script's next output starts below the box (and scrolls it
  up) instead of writing into it.
* **In a session** (`fv.dlg.begin`): drawn on the session's desktop, returns at once; it stays
  until the next `run` replaces it — the session owns the screen mode.
* **Cost per call on a Windows terminal**: the whole init / done (~450 ms) for one picture;
  scripts that show several infoboxes use a session.

---

## 6. Budgets (question 6)

### 6.1 Dispatches and writes (application made … deleted, headless)

| widget, keys | prototype dispatches | design: + `TDlgList` | writes | proposed limit (dispatches / writes) |
|---|---|---|---|---|
| msgbox, Enter | 17 | — | 11 | 22 / 16 |
| yesno, Enter | 19 | — | 12 | 24 / 16 |
| infobox (no loop) | 15 | — | 8 | 20 / 12 |
| inputbox / passwordbox, `abc` Enter | 21 | — | 14 | 26 / 20 |
| menu, Down Down Enter | 23 | + 6 (3 keys reach the list × 2) | 14 | 36 / 20 |
| checklist, Space Down Space Enter | 23 | + 8 (4 keys × 2) + 4 (two Spaces: the `SelectItem` override + its `inherited` toggle) = 35 | 15 | 40 / 20 |
| radiolist, Space Down Space Enter | 23 | + 8 + 2 (two Spaces: the override alone, no `inherited`) = 33 | 15 | 40 / 20 |
| **per key on a list** (in the loop) | 0 | **2** | 1–2 | 3 / 3 |
| per key in a box or the input line | 0 | 0 | 1 | 2 / 2 |

The dispatches outside the keys are the constructors' (application, desktop, background,
dialog, frame, the controls: `.new` and their `inherited` chains) and the destructors'. The
numbers marked "design" are counts of the planned overrides, measured in 4a-2.

### 6.2 Time targets (CI, Linux rows; Windows as ratios, D20)

| row | what | measured points | target | estimate from the probes |
|---|---|---|---|---|
| `dlg1.80x24.<widget>.inproc` | in one bench process: application made + the dialog + the keys + destroyed (the sourced face without a session) | the whole action | **≤ 14× `standin.down`** of the same run (msgbox), ≤ 17× (input, lists) | laptop 60–85 ms ≈ 10.5–14.5× its stand-in (5.5–6.0) |
| `dlg1.80x24.<widget>.session` | the same inside a session | the whole action | ≤ 9× / ≤ 12× | laptop 42 ms ≈ 7.5× |
| `dlg1.proc.<widget>` | a spawned `bin/fvdlg` headless (`--fv-size 80x24 --fv-keys K --fv-out /dev/null --fv-times T`) | **launch → first frame** (the command's `--fv-times` mark) and **launch → exit** | **first frame ≤ 0.8 s**; exit logged | first frame ~0.4–0.65 s, exit ~0.45–0.7 s (0.6–0.95 × laptop) |
| `dlg1.proc.<widget>.image` (with Q4 (b)) | the same through the image | both | **first frame ≤ 0.3 s**; exit logged | ~0.1–0.17 s |
| `dlg1.proc.load` | `kk.uses fv.dlg` alone | — | logged | ~0.4–0.6 s |

**How CI measures a process start**: the bench gets an `fvdlg` suite whose process rows spawn
the command N times (`EPOCHREALTIME` before the spawn, the command's own first-frame mark
through `--fv-times`, and the launcher's mark after `wait`), interleaved with a `bash empty.sh`
row and the load-only row in the same run, so the ratios hold across runners (±25 %). The
in-process rows use the `fvviews` harness (stand-in in the same process). Windows rows run the
same suite and are reported as ratios.

---

## 7. Units, files, tests (question 7)

### 7.1 Files

| path | content | est. lines |
|---|---|---|
| `kcl/fv.dlg/fv.dlg.sh` | the unit: parser, widgets, run / result, session, host-app mode, `TDlgApp TDlgList TDlgText` (+ `TDlgGauge` with Q8) | ~750 (+150 Q8) |
| `kbool/bin/fvdlg` | the command (below) | ~70 |
| `kcl/fv.dlg/README.md`, `docs/` | the flag table (whiptail / dialog / fvdlg columns, what differs), the two faces, exit codes, the terminal rules, the screen modes, Cost | docs |
| `kcl/fv.dlg/examples/setup.sh` | a script asking host, password, a package checklist, a confirmation — headless-runnable (`--fv-keys`) like the demos | ~80 |
| `kcl/fv.dlg/tests/` | below | ~1 000 |
| `kcl/tests/kcl_units.sh` | row `"fv.dlg||readonly|"` (readonly constants: the exit codes) | 1 |
| `kcl/tests/612_fv.dlg.sh` | the runtime stub | ~10 |
| `kcl/README.md`, kbool `README.md` | the unit row; "bin/ on your PATH" (one line: `export PATH=/path/to/kbool/bin:$PATH`, or call `/path/to/kbool/bin/fvdlg`) | docs |
| `tools/bench` | the `fvdlg` suite (§6.2) | ~120 |

**`bin/fvdlg`** in order: (1) a **bash-3.2-safe prologue** — macOS's `/bin/bash` 3.2 is what
`#!/usr/bin/env bash` finds there without Homebrew's bash: only POSIX-ish syntax until the
version check (no `{fd}` redirections, no `${x,,}`, no `[[ -v ]]`, no `local -n`), then
`BASH_VERSINFO` ≥ 5.1 or rc 255 with `fvdlg: needs bash 5.1 or later (this is 3.2.57)`; (2)
`--help` / `--version` without a load; (3) the terminal and `TERM` guards (P4-5); (4) P4-6's
buffering; (5) `source kbool.sh`, `kk.uses fv.dlg`; (6) `fv.dlg.main "$@"`. **The PATH story**:
nothing is installed (kbool's rule). `bin/fvdlg` finds kbool from its own path
(`${BASH_SOURCE[0]%/*}/..`; a symlink on PATH is resolved with one `readlink -f` fork only when
`-L` says it is a link). Called as `bash /path/to/kbool/bin/fvdlg` it works on every runtime.

### 7.2 Tests (headless first, as the demos; pty only where a terminal is the point)

| file | stage | what |
|---|---|---|
| 001_Contract | 4a-1 | `bash -n`; the API; loads under `set -eu` (twice, by name); fork-free per key; no stray names; the refusals' words |
| 002_Parse | 4a-1 | §4.5's rules; every flag in both tools' spellings; sizes; refused flags → 255 + one line; **the golden table** from the VM |
| 003_Boxes | 4a-1 | msgbox / yesno / infobox: layout cells, `--defaultno`, labels, Enter / Space / Tab / hot letters / clicks / Esc / Ctrl+F4 / the end of input → the codes; the infobox's `noalt`, `FV_KBD_PROTO=off`, cursor row |
| 004_Input | 4a-1 | input / password: INIT selected, typing over it, wide and Cyrillic text, paste, the echo of Q7, Cancel keeps nothing, Esc |
| 005_Output | 4a-1 | stderr / `--stdout` / `--output-fd N`; nothing written on 1 / 255; no trailing newline; P4-6 (a message during the UI replayed after it when fd 2 is the terminal — a fake tty via `FV_TTY` + a pty in 010; untouched when fd 2 is a file) |
| 006_Lists | 4a-2 | menu / checklist / radiolist: `--default-item`, first-letter jumps, double click, `--notags` / `--noitem`, statuses, radio exclusivity (Space twice keeps the mark), Q6's format, `--separate-output`, tags with blanks and quotes, 10 000 items |
| 007_Sizes | 4a-2 | auto size per widget, `-1`, clamping, the minimum (20 × 5 → 255 + the message), the scrolling text view, resize re-centring and a resize below the minimum |
| 008_Sourced | 4a-2 | `fv.dlg.run` → `RESULT` / `FV_DLG_TAGS` / rc; a session (`begin` / `end`: one screen-mode switch), an infobox in a session, inside a host application, `$( )` with and without a session |
| 009_NoTty | 4b | no terminal (`FV_TTY=/nonexistent`; this tool shell has none): rc 255 **before the load** (time bound), Q5's policy, `TERM` unset / `dumb`, `FVDLG_FORCE`, the bash 3.2 prologue parsed by `bash --posix` and (where present) a 3.2 binary |
| 010_Pty | 4b | script(1) on MSYS2 / Cygwin / Linux — util-linux only: macOS and FreeBSD ship a BSD `script(1)` with other options → ENV there (fvv_pty's detection): `x=$(fvdlg --stdout …)`, the swap idiom, exit 0 / 1 / 255 / 130 / 143, stty equal, the restore sequences, Q3's modes (one `?1049h` per call / none), the infobox on the main screen with its cursor row, NO_COLOR, P4-6's replay; no survivor |
| 011_CallerState | 4a-2 | the sourced face under IFS variants, nocasematch, extglob, `LC_ALL=C`, `set -u` (fv.msgbox 006's model) |
| 012_Budget | 4a-1 / 4a-2 | §6.1's limits, each logged |
| 013_Gauge / 014_Textbox | 4d | stdin percentages and `XXX` blocks, partial lines, the end of stdin, stdin a terminal refused; a file viewer's keys |

`tests/fvdlg_testlib.sh` reuses fv.app's test lib (the headless application) and fv.video's
`fvv_pty.sh`.

---

## 8. Stage split (Stage 1), in order

Each stage: Opus worker → supervisor review → critic where marked → fixes → suites + `gate.sh` →
commit; hygiene block in every brief; Windows gate (Git-bash, MSYS2, Cygwin) + the VMs (bash 5.1;
**whiptail and dialog on the Debian VM** for the golden table); perf on the CI bench via the perf
branches (D20).

| stage | content | size | review |
|---|---|---|---|
| **4a-1** parser, boxes, input, results | the unit skeleton, the parser (Q1's set, §4.5's rules, the golden table from the VM), msgbox / yesno / infobox (§5.4) / inputbox / passwordbox (Q7), `TDlgApp`, the result / exit matrix, P4-6, `NO_COLOR`; tests 001–005, 012 (boxes) | ~450 + tests | Windows + VM; **critic** (compatibility against the real tools, the result / exit matrix) |
| **4a-2** lists, sizes, text view, faces | `TDlgList` (menu / checklist / radiolist, jumps, double click, exclusivity, Q6's format), sizes and the minimum, resize, `TDlgText` (long text, `--scrolltext`), the sourced face (`run`, session, host-app mode); tests 006–008, 011, 012 (lists) | ~450 + tests | Windows + VM; **critic** (list semantics, budgets, the session's state) |
| **4b** the command + terminal | `bin/fvdlg` (the 3.2 prologue, guards before the load, Q5's policy, `--fv-*` headless options, `--help` / `--version`), Q3's screen modes, the kbool README PATH line; tests 009, 010 on the pty runtimes and the Linux VM | ~250 + tests | Windows + VM; **critic** (terminal paths, signals, `$( )`) |
| **4b-L** owner live check | an English checklist (as P3's): each widget in Windows Terminal, mintty, conhost (and a Linux terminal over ssh when convenient): Enter / Esc / Ctrl+C, resize, a loop of five calls in each screen mode, an infobox followed by script output, NO_COLOR, a non-Latin layout's hot keys; the owner runs it when allowed | checklist | owner |
| *(image plan)* | **only with Q4 = (b)**: the general kbool image (§11) as **its own plan + critic** in kkore / kklass with per-unit settings hooks; its last step wires `bin/fvdlg` to it and adds the `.image` bench rows | §11.6 | its own plan |
| **4d** gauge + textbox (Q8 = a) | `TDlgGauge`, the stdin poll in `Idle` (partial lines), `--textbox`; tests 013, 014 | ~300 + tests | Windows + VM; **critic** (stdin while the UI runs) |
| **4e** budget, bench, docs | the `fvdlg` bench suite (§6.2), README (flag table with whiptail / dialog columns, the screen modes), kcl / kbool README rows, the example, PLAN / ledger; CI bench run on the perf branches → the targets fixed | ~150 + docs | supervisor-read; CI bench |

Order: **4a-1 → 4a-2 → 4b → 4b-L (when the owner can) → (image plan) → (4d) → 4e**. Without
the image and 4d: three implementation stages, the live check and the docs stage.

---

## 9. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | **Start-up ~0.75 s headless / ~1.3 s on a Windows terminal** makes the command feel slow next to whiptail | Q4 (b) (~0.15–0.3 s); the session face for bash scripts now; F-P4-1 for the owner's speed work |
| R2 | (image) a stale, planted or environment-frozen image | §11: settings hooks, the key, the location and checks, the env-diff test; any doubt → a normal load |
| R3 | whiptail / dialog nuances (auto size, text collapse, `\Z`, quoting, option placement) surprise migrating scripts | the golden table checked against the real tools on the VM (4a-1 / 4a-2); the README's "differences" table; refused flags instead of silent ones |
| R4 | Output during the UI scribbles on the dialog, or is lost | P4-6: buffered and replayed, only when the fd is the terminal |
| R5 | The infobox on terminals where the main screen behaves differently (tmux status line, scrollback) or a kitty reply after the exit | P4-10: `noalt`, `FV_KBD_PROTO=off`, the cursor row; documented |
| R6 | A loop of calls flashes (alternate screen) or leaves screens behind (main screen) | Q3; the session face for bash loops |
| R7 | `--gauge` reading stdin while the keys come from the tty | stdin must not be a terminal (refused); the poll reads a pipe only (D13 untouched); partial lines kept |
| R8 | A small or resized terminal | P4-8's minimum + re-centring; 007 |
| R9 | Fork costs grow with the process image on Windows | measured: a fork 13–28 ms before the load, 15–29 ms after (no real growth at this size); the command adds no fork of its own on its paths (P4-6's `rm` only when a buffer was made) |
| R10 | The per-key dispatch of `TDlgList` | 2 dispatches ≈ 0.25–0.5 ms per key, counted in 012 |
| R11 | macOS `/bin/bash` 3.2 runs `bin/fvdlg` | the 3.2-safe prologue and a clean rc 255 + message; 009 parses it |
| R12 | Name clash appears later | `fvdlg` checked 2026-11-22; the unit name `fv.dlg` keeps the command a thin wrapper |

---

## 10. Owner questions

### Q1 — The flag set (open item O2)

What a user writes to show a yes/no question, and what happens with an existing whiptail script:

* **(a) whiptail / dialog-compatible subset only.**
  `fvdlg --title Disk --yesno 'Format /dev/sdb1?' 10 40` — an existing `whiptail …` line works
  after changing one word; options outside the subset (`--colors`, `--extra-button`) are refused
  with rc 255. No fv-specific options at all (no headless test flags, no palette choice).
* **(b) Own syntax.**
  `fvdlg yesno --title Disk 'Format /dev/sdb1?'` — shorter, sizes always automatic, but every
  whiptail / dialog script must be rewritten by hand.
* **(c) Compatible flags + extras under `--fv-` (recommended).**
  `fvdlg --title Disk --yesno 'Format /dev/sdb1?' 0 0` works as in dialog (0 = auto size) and
  whiptail lines work unchanged after the one-word switch; both tools' spellings are accepted
  (`--yes-button` or `--yes-label`); fv adds `--fv-palette blue`, `--fv-ascii`, `--fv-mouse off`
  and the headless test options (`--fv-keys keys.bin --fv-size 80x24`).

**Recommendation: (c).** Migrating scripts switch with one word; the extras can never clash
with a future whiptail / dialog flag.

### Q2 — The command's name

* **`fvdlg`** (unit `fv.dlg`): `x=$(fvdlg --stdout --inputbox 'Name:' 0 0)`.
* **`fvdialog`**: `x=$(fvdialog --stdout --inputbox 'Name:' 0 0)`.
* **`kbdialog`**: `x=$(kbdialog --stdout --inputbox 'Name:' 0 0)`.

No package or command with any of these names was found. **Recommendation: `fvdlg`** (short,
the unit's name, the `fv.` family).

### Q3 — The screen mode: where a dialog draws

A script asks five questions in a row with five separate calls:
`for f in a b c d e; do fvdlg --yesno "Delete $f?" 0 0 && rm "$f"; done`

* **(a) The alternate screen per call** (rev 1's design; whiptail where newt uses it, dialog
  with `--keep-tite`). Each call switches to a clean screen with the dialog and back at its
  exit: the user sees the dialog, then for a moment the shell's screen, then the next dialog —
  **a flash between questions**; after the script the terminal shows exactly what it showed
  before (the questions leave no trace).
* **(b) The main screen** (dialog's default on xterm-like terminals). Each call draws its
  dialog over what is on the terminal; between calls nothing flashes back (the next dialog
  paints over the previous one); **after the script the last dialog stays visible** above the
  shell's next output and the earlier terminal contents have scrolled away or been painted over.
  `--clear` (both tools) clears it at the exit.
* **(c) A flag, (a) by default**: `--fv-screen alt|main` (and dialog's `--keep-tite` = alt,
  `--erase-on-exit` = main + clear at exit); default (a). Same choice with (b) as the default:
  (c′).

In every mode the infobox uses the main screen (P4-10), and the session face (`fv.dlg.begin`)
never flashes. **Recommendation: (c)** with the alternate screen as default — "restored exactly
as found" is the plan's wording for P4 and scripts that run one dialog (the common case) leave
no trace; scripts with loops either pass `--fv-screen main` or, in bash, use a session.

### Q4 — The start-up cost: no cache in P4, or a general kbool image

Measured on this laptop: a message box **~0.75 s** from launch to exit headless, **~1.3 s** on
a Windows terminal (load ~0.65 s; on a terminal also init ~0.3 s + done ~0.16 s, fv.video's).
CI Linux estimate: first frame ~0.4–0.65 s headless.

* **(a) No cache in P4.** `fvdlg --yesno …` shows its box after ~0.6 s on Linux CI rows (est.)
  and ~1 s on a Windows terminal. Bash scripts that load kbool use the session face: the load
  once per script, then 40–70 ms per dialog. Simplest; nothing to keep fresh or trust.
* **(b) A general kbool image** (`kk.image` or similar in kkore / kklass, §11) as **its own
  small plan + critic right after 4b**, `fvdlg` its first user. What a user sees: the first
  `fvdlg` after installing or updating kbool is as slow as today (it writes the image, ~2 s
  once); later calls show the box after **~0.15–0.3 s** headless (the prototype's image: 77–93
  ms to source instead of ~650 ms; ~180 ms real end to end), ~0.6 s on a Windows terminal (the
  rest is fv.video's init / done). The image lives in `~/.cache/kbool/` (Linux / macOS) or
  `%LOCALAPPDATA%\kbool\` (Windows runtimes), readable by you only, rebuilt by itself when a unit
  file, your kbool config or the bash version changes; your locale and `FV_*` settings are read
  fresh on every start (the units' settings hooks), so the image never answers with the
  settings of the shell that made it. Every other kbool program can use it too: the TUI demos
  (`widgets.sh` loads in ~650 ms today), `thttpserver` start-up, any script that loads many kcl
  classes. Size: ~300–400 lines in kkore / kklass + a settings hook in each unit that reads the
  environment at load (~5–15 lines each; ~10 units today) + ~400 lines of tests.
* **(c) The image inside fv.dlg only** (rev 1's stage 4c). Faster to do, but it would need the
  same per-unit settings hooks and trust rules anyway, for one user — not offered.

**Recommendation: (b)** — it cuts the start-up 3–4× where every kcl-heavy program can use it,
and the environment problem (H1) is fixed in the units that cause it instead of being worked
around in one command; P4 itself is complete without it (the command works, only slower).

### Q5 — No terminal (CI, cron, `ssh` without `-t`)

A CI job runs `fvdlg --yesno 'Deploy?' 0 0 && deploy`:

* **(a) Refuse.** rc 255 at once, stderr `fvdlg: no terminal (/dev/tty)`; `deploy` does not run.
* **(b) Refuse, plus an opt-in default answer (recommended).** As (a) by default; with
  `--no-tty=default` on the call, or `FVDLG_NOTTY=default` in the job's environment, the dialog
  answers what Enter would have answered: here rc 0 and `deploy` runs; an input box answers its
  INIT text, a menu its `--default-item`, a checklist its `on` items — printed as usual. (The
  variable reaches child scripts too — documented; the flag does not.)
* **(c) A text fallback.** Without a terminal the question is asked on stderr and read from
  stdin: `Deploy? [Y/n]` — works in a pipe, but a script that feeds stdin with data gets its data
  eaten as answers.

**Recommendation: (b)** — nothing answers for a person unless the job asked for it, and scripts
stay testable in CI without a pty.

### Q6 — The list output format

A checklist where the user ticks `git` and `curl`, and a radiolist where the user picks `vim`:
`fvdlg --checklist 'Packages' 0 0 0 git Git on vim Vim off curl curl on`

* **(a) whiptail's** (believed the same as dialog's default; checked on the VM): checklist
  `"git" "curl"` (each tag double-quoted, space-separated), radiolist `vim` (bare);
  `--separate-output`: `git⏎curl⏎` (one tag per line, no quotes). A script reads it with
  `eval "set -- $out"` or `--separate-output` + `while read`.
* **(b) Bare words**: checklist `git curl`, radiolist `vim` — simple for tags without blanks,
  ambiguous for a tag like `my app`.
* **(c) (a) plus dialog's `--single-quoted`** (quotes only where needed: `git curl`, `'my app'`)
  and an fv extra `--fv-output lines|quoted|single` for scripts that want to choose.

In every case the sourced face gives the tags in the array `FV_DLG_TAGS` (no parsing).
**Recommendation: (c)** — whiptail scripts work unchanged, dialog's `--single-quoted` scripts
too, and the extra costs a few lines.

### Q7 — The password echo

`pass=$(fvdlg --stdout --passwordbox 'Password:' 0 0)`, the user types `secret`:

* **(a) `*` per character** (whiptail; FV's `PasswordChar`; P3's fv.msgbox `-p`): the line
  shows `******`; dialog's `--insecure` accepted and changes nothing.
* **(b) Nothing** (dialog's default): the line stays empty while typing (the cursor does not
  move); `--insecure` shows `*`.
* **(c) (a) by default + `--fv-echo none`** for users who do not want the length shown.

**Recommendation: (c)** — whiptail's visible feedback by default (users see that keys arrive),
and the stricter choice is one flag away.

### Q8 — `--gauge` and `--textbox`

The plan's list is message, yes/no, input, password, menu, checklist, radio list (+ infobox,
nearly free). A script that shows progress writes:

```sh
for i in 10 40 70 100; do echo "$i"; sleep 1; done | fvdlg --gauge 'Copying...' 0 0 0
fvdlg --textbox /etc/os-release 0 0
```

* **(a) In P4** as stage 4d (~300 lines: a progress view, reading stdin while the dialog runs,
  the file viewer; with a critic).
* **(b) After v1**, with the other dialog widgets (forms, calendar, file selector). Until then
  both are refused with rc 255 and a line.

**Recommendation: (a)** — `--gauge` and `--textbox` are in most whiptail scripts; the text view
is needed anyway for long messages (P4-9), so `--textbox` costs little.

---

## 11. A general kbool image (Q4 (b)): requirements

This section is the input for the image's own plan (if Q4 = (b)); it is not a P4 stage.

### 11.1 Contract (proposal)

```bash
source /path/to/kbool/kbool.sh            # always fresh: config, root path, $BASH, kkore state
kk.image fv.dlg || exit                   # = kk.uses fv.dlg, through an image when one is valid
```

* `kk.image UNIT…` behaves like `kk.uses UNIT…` (rc 0 / 2, the same units loaded), except
  that it first looks for a valid image of exactly that unit closure; valid → source it, run
  the units' settings hooks (§11.2), re-pin the process-bound state; else → a normal `kk.uses`,
  then write the image for the next start (atomically; a failure to write is silent but for a
  debug line).
* `kk.image --rebuild UNIT…`, `kk.image --forget UNIT…`, `kk.image --path UNIT…` for users and
  tests. `KBOOL_IMAGE=off` disables it (every call a normal load).

### 11.2 Units declare their load-time environment reads (fixes H1 at the source)

Each unit whose load reads the environment, the locale or a config moves those reads into one
function, **`UNIT._settings`** (registered with `kk.unit --settings FN` or found by name), run
at the end of the normal load **and** after an image is sourced — one code path, so the image
cannot freeze them. For the fv units (critic's diff + a scan of `X=${X:-default}` lines):
* the ~40 environment-defaulted globals, among them `FV_KEY_FD`, `FV_VIDEO_OUT_FD`,
  `FV_SCREEN_W/H`, `FV_HISTORY_SIZE`, `FV_MINWINSIZE_X/Y`, `FV_CLIPBOARD`, `FV_APP` / `FV_DESKTOP`
  and the internal `__FV_*` ones that take a caller's value;
* fv.keyboard's locale (`__FV_KB_LOC` from `LC_ALL` / `LC_CTYPE` / `LANG`) and **its export
  `LC_CTYPE=C.UTF-8` when no locale is set** — the image must not carry an export made in
  another shell;
* fv.video's `__FV_VS_LOC` (the locale triple) and its colour depth inputs;
* `__FV_VW_OWNER=$BASHPID` (fv.views records the loading process);
* lazily sourced data (fv.keyboard.layouts.sh): either never in an image (the lazy load runs
  as usual after it) or in it together with its guard — the plan picks one and tests it.
Units without load-time reads need no hook. A unit without a hook that reads the environment at
load is a bug the env-diff test (§11.5) finds.

### 11.3 What the image holds and never holds (H2)

* **Never**: kbool.sh's own state — it is always sourced fresh (7 ms), so kkore's config levels
  (`KBOOL_CONFIG`, the project file, `~/.kbool/config` / `$USERPROFILE/.kbool/config`,
  `/etc/kbool/config` / `$ProgramData/kbool/config`: kkore/kuse.sh 1066–1075), the root path,
  `$BASH` and the debug level are current; `__KK_UNIT_RES` / `__KK_FILE_PWD` entries keyed by
  the calling script's folder (re-made by the loader for the caller); kklass's capture state
  `__kk_ft` (pid-keyed, it resets itself); traps; open fds.
* **Holds**: the units' functions, classes (the kklass tables), variables after their load
  minus the settings hooks' outputs (recomputed), the units' registration entries (so a later
  `kk.uses` of the same unit is a no-op), `shopt` changes the units made.

### 11.4 Key, location, trust (H2, M1)

* **Key**: the unit closure (names and resolved paths), each unit file's size and mtime, the
  kbool version, `BASH_VERSION`, `OSTYPE`, and the config files that changed the unit search
  path. **Reading the stamps**: one `stat` fork for all files (GNU `-c '%s %Y'` / BSD `-f`,
  the flavour probed as kcl TPath does; ~20 ms on Windows, ~1 ms on Linux) — exact; a
  fork-free fallback with bash's `-nt` (no file newer than the image, the same file list) where
  `stat` is unknown, documented as blind to an older file copied in with its mtime (`cp -p`).
* **Location**: Linux / macOS / BSD `${XDG_CACHE_HOME:-$HOME/.cache}/kbool/image/`; the
  Windows runtimes (Git-bash, MSYS2, Cygwin) `$LOCALAPPDATA/kbool/image/` (a per-user folder
  whose ACL admits only the user, unlike `%TEMP%` subfolders created elsewhere or MSYS2's
  `/tmp`, which every user may write); kkore's configured `ckkdir` may override.
* **Checks before sourcing**: the folder and the file are not symlinks (`-L` refused), the
  folder is a directory owned by the user (`-d`, `-O`), the file is owned by the user (`-O`);
  **on POSIX file systems** also neither group- nor world-writable (the mode from the same
  `stat` call); on `noacl` Windows mounts no mode exists — the location's ACL is the guard
  (documented). Any failed check → a normal load and a debug line, never a source.
* **Writing**: under `umask 077` into a temp name in the same folder, then `mv` (one fork) over
  the old image; the folder created with `mkdir -p` under the same umask.

### 11.5 Tests the plan needs

* **The env-diff test** (the critic's reproducer made a test): make the image under
  environment A, start under environment B (`LANG`, `LC_ALL` unset / set, `FV_HISTORY_SIZE`,
  `FV_MINWINSIZE_X`, `FV_KEY_FD`, `FV_VIDEO_OUT_FD`, `KBOOL_CONFIG`, another calling folder) →
  the state after `kk.image` equals a real `kk.uses` under B (the snap_diff method: every
  variable element, functions, `shopt`, exports), for every unit in the image.
* Staleness (an edited unit, a new bash, a changed config search path → rebuilt), the trust
  checks (a symlinked folder, a foreign-owned or group-writable file refused, not sourced), an
  unwritable folder (works, no image), concurrent first starts (two writers → one valid image),
  the process-bound state re-pinned, `KBOOL_IMAGE=off`.

### 11.6 Size and risks

~300–400 lines in kkore / kklass, settings hooks in ~10 units (~5–15 lines each), ~400 lines of
tests; its own plan, a critic, the Windows gate and the VMs. Risks: state that is not a variable
(traps, fds, `set -o`), functions a unit defines differently by environment at load (they belong
in the hook or in the key), a 1.6 MB image's memory and source time on slow machines
(measured 77–93 ms on this laptop), and new load-time reads added to a unit later (caught by the
env-diff test in the unit's own suite).

---

## Appendix A. Probes and prototype (`scratchpad/p4/`)

| file | what |
|---|---|
| `proto/fvdlg.sh` | the prototype command (§0 intro); hooks: `FVDLG_HEADLESS / KEYS / SIZE / OUT / SCREEN / TIMES / T0 / READY / FORKS / COUNT / SNAP / MSGBOX` |
| `proto/count.inc` | the dispatch / write counters (fvw_testlib's shim) |
| `probe/run_split.sh ROUNDS OUT CASE…` | §1.1: a fresh process per run, the marks' medians |
| `probe/load_split.sh [parse]` | §1.1's per-unit load and parse times |
| `probe/snap_make.sh OUT`, `probe/snap_diff.sh` | §1.3: the state image and its comparison with a real load |
| `probe/pty_run.sh ROUNDS OUT` | §1.2: script(1) runs (capture, swap, Esc, Ctrl+C, restore checks) |
| `probe/session.sh N` | §2.2: per call vs in a session, one process |
| `run/…` | outputs (`gb5`, `msys`, `cyg`, `gbs`, `msyss`, `cygs`, `pty_msys`, `pty_cyg`, the images) |
| `critic/` | the critic's reproducers: `build_time.sh` (the build split), `ckk_load.sh` (the `.ckk` route), `img_time.sh`, `diff/` (H1: a real load vs the image under another environment), `rs1/` (the split re-run) |
| `P4_DESIGN.rev1.md` | revision 1, for comparison |

Raw numbers not in the tables: fork cost `$(:)` before the load 13–28 ms, after 15–29 ms (all
three runtimes); a bare `bash empty.sh` 26–29 ms; the no-terminal refusal after a full load 731
ms; per call in one process (headless): Git-bash 67.5 (64–74) / session 41.6 (40–49) ms, Cygwin
70.2 / 42.5 ms; the prototype's screen at 20 × 5 (buttons over the frame, a menu without its
list) motivated P4-8.
