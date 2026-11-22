# kcl/fv.dlg — one-shot dialogs for shell scripts

Part of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P4_DESIGN.md](../docs/dev/fv/P4_DESIGN.md), D32–D39). whiptail- and
dialog-compatible flags on Free Vision's classes
([fv.app](../fv.app/README.md), [fv.dialogs](../fv.dialogs/README.md)):
one parser, two faces — the command `fvdlg` (stage 4b ships `bin/fvdlg`,
which calls `fv.dlg.main`) and `fv.dlg.run` for bash scripts that load
kbool.

**Status: P4 stage 4a-1** — the parser (D32's flag set in both tools'
spellings, §4.5's rules), `--msgbox`, `--yesno`, `--infobox`, `--inputbox`,
`--passwordbox`, the results and exit codes, P4-6's buffering, `NO_COLOR`.
Next: 4a-2 (menu / checklist / radiolist, exact sizes and the minimum,
the scrolling text, the session face `fv.dlg.begin` / `end`, the host
application), 4b (`bin/fvdlg`, the screen modes, no terminal), 4d (gauge,
textbox), 4e (bench, docs). The unit loads `kklass_pascal`, `fv.app` and
`fv.dialogs`.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.dlg

fv.dlg.run --title Disk --yesno 'Format /dev/sdb1?' 0 0 && format_it
fv.dlg.run --inputbox 'Your name:' 0 0 "$USER" && name=$RESULT
fv.dlg.run --passwordbox 'Password:' 0 0 && pass=$RESULT
case $? in 0) ;; 1) echo cancelled ;; 255) echo 'Esc, or an error' ;; esac
```

The command's face (what `bin/fvdlg` runs, stage 4b):

```bash
fv.dlg.main --title Disk --yesno 'Format /dev/sdb1?' 0 0; echo $?
name=$(fv.dlg.main --stdout --inputbox 'Your name:' 0 0 "$USER")
name=$(fv.dlg.main --inputbox 'Your name:' 0 0 3>&1 1>&2 2>&3)   # whiptail's idiom
```

## The two faces

| Function | Answer |
|---|---|
| `fv.dlg.main ARG…` | the command: the answer (input text) **on stderr** by default, stdout with `--stdout`, fd N with `--output-fd N`; written once, after the terminal is restored, **without a trailing newline**, only for status 0; stderr and stdout buffered while the UI runs when they are the terminal (P4-6, below); `--help` / `--version` on stdout (status 0). **Returns** the status (bin/fvdlg exits with it). Refusals: one line `fvdlg: …` on stderr |
| `fv.dlg.run ARG…` | the same argv and rules; the answer in **`RESULT`** (`''` for 1 / 255 and for the boxes without an answer), **`FV_DLG_CMD`** the FV command that ended the dialog (`cmOK cmYes cmNo cmCancel`, `''` after a refusal); prints nothing unless `--stdout`, `--stderr` or `--output-fd` asks; the same status. Refusals: `fv.dlg.run: …` (the same words); `--help` / `--version` are refused (the command's) |

Each call makes a headless or real application (`TDlgApp`), runs the
dialog modal, and deletes the application: fv.video turns the terminal on
and gives it back exactly as found (fv.video README, "The terminal"); the
answer is printed after that. Inside a running fv application (`FV_APP`
live) a call is refused for now (the host-application mode is 4a-2's).
Inside `$( )` a call works (the subshell owns its own terminal) but pays
the whole terminal start.

### Exit status

| status | constant (readonly) | when |
|---|---|---|
| 0 | `FV_DLG_OK` | OK, Yes; the infobox |
| 1 | `FV_DLG_CANCEL` | Cancel, No (the buttons send `cmNo`, P4-4) |
| 255 | `FV_DLG_ESC` | Esc, Ctrl+F4, the close icon, the end of input; no terminal; bad arguments (one line on stderr) |
| 130 / 143 / 129 | — | Ctrl+C, SIGTERM, SIGHUP: fv.video's exit path (the terminal restored, then the signal's status) |

## Widgets (stage 4a-1)

| widget | built from | answer |
|---|---|---|
| `--msgbox TEXT H W` | `TDialog` (gray, FV's frame, close icon, shadow) + `TStaticText` + `O~K~` (`cmOK`, default) | 0 / 255 |
| `--yesno TEXT H W` | + `~Y~es` (`cmYes`) / `~N~o` (`cmNo`); `--defaultno`: No selected and default | 0 / 1 / 255 |
| `--infobox TEXT H W` | the dialog without buttons, **drawn once, no loop** (P4-10): the main screen (`initVideo noalt`, so the box stays visible after the exit), `FV_KBD_PROTO=off` unless the environment sets it (no keyboard query whose reply could land on the shell), the cursor left on the screen's last row; fv.video's init clears the screen first | 0 |
| `--inputbox TEXT H W [INIT]` | + `TInputLine` (1024 clusters; INIT shown **selected**: the first typed key replaces it, FV's rule; End keeps it) + `O~K~` / `Cancel` (`cmNo`); wide and joined characters, the clipboard keys and bracketed paste are the input line's | 0 + the text / 1 / 255 |
| `--passwordbox TEXT H W [INIT]` | the same with `*` per character (D38); `--fv-echo none`: blanks and no cursor | 0 + the text / 1 / 255 |

**Layout.** The text from cell 2 of row 1 (`\n` written as two characters is
a newline; long lines wrap at blanks, TStaticText's rule), the input line
two rows below it, the buttons centred on the row `H − 3` (each the
label's cells + 4, at least FV's 10, two cells apart). **Sizes** (P4-8): `0`
= fit the text (the widest line + 5 columns, at most 2/3 of the screen for
the text, at least the title + 12 — at most the screen — and the buttons;
its rows + 5, + 7 with the input line, + 2 for the infobox), `-1` = the
whole screen (below the background title), a number = that size, clamped
to the screen. The box is centred (`--topleft`: at the top left). A size
below the box's minimum (the buttons across; one text row, the input line,
the buttons and the frame down) grows to it; a screen below it: 255 and
`terminal too small (need WxH, have WxH)` — only for the geometry, never
for text: a title wider than the box is cut by the frame, and button labels
wider than the screen allows are clipped (a short one keeps its cells, the
other gets the rest; a `~` letter that survives the cut still works). The
exact rule and a resize below it come with 4a-2. A resize re-centres
the box through TDialog's own `CalcBounds` (FPC 2025: the margins kept in
proportion). **Background**: FV's desktop (`░`); `--backtitle T`: row 0 in
the background's colours (`TDlgTitle`), the box below it. No status line,
no menu bar.

**Keys.** FV's: Enter presses the default button, Tab / Shift+Tab and the
arrows move between the controls, Space presses the focused button, the
button's `~` letter (Alt + it, or the plain letter: `y` / `n` / `k`), a click
on a button; Esc and Ctrl+F4 and the close icon answer `cmCancel` (255).
Labels given with `--yes-button` and the like have no hot letter (a `~` in
them marks one).

## Results and the terminal

| flag | the answer goes to | idiom |
|---|---|---|
| (none) | stderr (fd 2) — the command; nothing — `fv.dlg.run` | `x=$(fvdlg --inputbox … 3>&1 1>&2 2>&3)` |
| `--stdout` | stdout | `x=$(fvdlg --stdout --inputbox …)` |
| `--stderr` | stderr | |
| `--output-fd N` | fd N (an fd that is not open: 255, one line, `RESULT` and `FV_DLG_CMD` `''` as for every 255) | `fvdlg --output-fd 3 --inputbox … 3>answer.txt` |

**P4-6, output during the UI.** In the command's face, while the dialog is
shown, stderr — and stdout — **when that fd is the terminal** go to a
private file (`$TMPDIR`, mode 0600 under `umask 077`, `noclobber`, a name
that cannot be predicted); after the terminal is restored the file is
copied to the terminal (stderr's when it was buffered, else stdout's) and
removed, then the answer is written. A file, a pipe or a capture (the swap
idiom's fd 2) is never touched. The caller's EXIT trap is set aside while
the UI runs (the one active in this process: inside `$( )` or `( )` the
parent's trap texts that `trap -p` still shows there are dropped first, so
the parent's handler never runs in the subshell) and put back after. If the
process dies during the UI (`exit`, or Ctrl+C / SIGTERM / SIGHUP through
fv.video's handlers), the EXIT trap still restores the fds, replays and
removes the buffer, then runs the caller's EXIT handler once, with the
status kept. The buffer costs one `rm` and one `trap -p` (in a subshell one
more, fv.video's `_drop`) — the unit's only processes — and is made only
when an fd is the terminal.

**`NO_COLOR`** (any non-empty value, no-color.org): the app palette's
entries a dialog uses become light grey / white on black, the focused
button, the input field and the selection in reverse (FV's black-and-white
idea), through one `fv.app.setAppPalettes` call before the first paint; the
palette is the default again after the call. Under `NO_COLOR` the dialog
keeps the gray palette even with `--fv-palette blue` / `cyan` (those
entries are not mapped).

## The flags (stage 4a-1)

`w` = whiptail 0.52.25, `d` = dialog 1.3-20250116 (both checked on Debian
13, the golden table below); fvdlg accepts both tools' spellings. Unknown
flags are refused (255, one line), never ignored.

| flag | w | d | fvdlg |
|---|---|---|---|
| `--msgbox --yesno --infobox --inputbox --passwordbox` | ✓ | ✓ | ✓ |
| `--menu --checklist --radiolist` | ✓ | ✓ | refused "not supported yet" (4a-2) |
| `--gauge --textbox` | ✓ | ✓ | refused "not supported yet" (4d) |
| `--title T`, `--backtitle T` | ✓ | ✓ | ✓ |
| `--ok-button L` / `--ok-label L` | button only | both | both |
| `--cancel-button` / `--cancel-label`, `--yes-button` / `--yes-label`, `--no-button` / `--no-label` | button only | both (the last wins) | both (the last wins) |
| `--defaultno` | ✓ | ✓ | ✓ (yesno) |
| `--nocancel` / `--no-cancel` | nocancel | both | both (no Cancel button) |
| `--stdout`, `--stderr` | — | ✓ | ✓ |
| `--output-fd N` | ✓ | ✓ | ✓ |
| `--default-item T`, `--separate-output`, `--notags` / `--no-tags`, `--noitem` / `--no-items` | ✓ (`no-` forms: d) | ✓ | parsed (the lists, 4a-2) |
| `--single-quoted` | — | ✓ | parsed (4a-2) |
| `--colors` | — | ✓ | `\Z0`–`\Z7`, `\Zb \ZB \Zr \ZR \Zu \ZU \Zn` stripped (no colours in v1); without it they are text, as in both tools |
| `--clear`, `--keep-tite`, `--erase-on-exit` | clear only | ✓ | parsed; the screen modes are 4b's |
| `--scrolltext` | ✓ | ✓ | parsed (the scrolling text is 4a-2's) |
| `--fb` / `--fullbuttons`, `--no-collapse`, `--cr-wrap`, `--trim`, `--insecure` | fb, fullbuttons | ✓ (not fullbuttons) | accepted, no effect (FV buttons are full; whiptail's text rule; `*` always) |
| `--topleft` | ✓ | ✓ | the box at the top left |
| `--ascii-lines` | — | ✓ | = `--fv-ascii` |
| `--no-shadow` | — | ✓ | the box without FV's shadow |
| `--help`, `--version` | ✓ | ✓ | the command only |
| `--help-button --extra-button --and-widget --item-help --timeout`, dialog's other widgets | — | ✓ | refused (outside the subset) |
| `--fv-palette gray\|blue\|cyan` | | | FV's dialog palettes |
| `--fv-ascii` | | | ASCII mode (`FV_ASCII=1` for the call) |
| `--fv-mouse on\|off` | | | off: mouse reporting switched off right after the start (the keys already typed are kept) |
| `--fv-echo star\|none` | | | the password echo (D38) |
| `--fv-screen alt\|main` | | | parsed and kept; the switch is 4b's (D34) |
| `--fv-output lines\|quoted\|single` | | | parsed; the list output is 4a-2's (D37) |
| `--fv-headless`, `--fv-keys FILE`, `--fv-size WxH`, `--fv-out FILE` | | | no terminal: the keys from FILE (the bytes a terminal sends; the end of the file is the end of input), the frames to FILE (default `/dev/null`), the size (default 80x24, 1–1000 per side) — tests and the bench. A caller's own `FV_APP_HEADLESS=1` (with its `FV_KEY_FD`, `FV_VIDEO_OUT_FD`, `FV_SCREEN_W` / `_H`: fv.app's convention) is honoured without these flags |

**Parser rules** (P4-7, design §4.5): options anywhere before `--`, also
after the widget's arguments (`--msgbox Hi 10 40 --title T`); the widget's
fixed positionals are taken literally (TEXT may be `-5` or `--title`); H and
W must be integers, checked as soon as the three are taken (the refusal
names the word that stood there); an fv extra's value is one of its words,
exactly (no pattern, whatever `nocasematch` says); an optional positional (INIT) is taken unless it is
exactly a known option (`--inputbox N 0 0 -x` → INIT `-x`); `--` ends the
options (`--inputbox N 0 0 -- --weird`); `--opt=value` or `--opt value`; one
widget per call; anything left over is refused.

## What differs from whiptail / dialog

From the golden table (`whiptail` / `dialog` under `script(1)` with scripted
keys; rows in `tests/002_Parse.sh` and `tests/005_Output.sh`):

* **INIT is selected**: the first key replaces it (FV). Both tools put the
  cursor after it and append (`init` + `x` → `initx`); End first gives
  their result.
* **Unknown options**: 255 and `fvdlg: unknown option '--x'`. whiptail
  answers **1** ("--x: unknown option"), dialog 255.
* **Extra arguments are refused** (`--msgbox t 0 0 extra`); whiptail ignores
  them, dialog refuses.
* **Options after the positionals** work (whiptail); dialog refuses them.
  `--title=T` works (whiptail); dialog refuses it.
* **Options between the positionals are refused**: the three fixed ones are
  taken literally, so `--msgbox Hi --title T 10 40` answers 255 and
  `HEIGHT must be an integer (got '--title')` (golden `msg_between`).
  whiptail accepts them (the title shown); dialog refuses them.
* **`-1` sizes and TEXT starting with `-`** work (dialog); whiptail takes
  them for options (rc 1).
* **TEXT that looks like an option** (`--msgbox --title 8 30`) is text;
  both tools refuse it.
* **Two widgets** are refused (whiptail too); dialog runs them one after
  the other.
* **Yes / No hot letters** `y` / `n` answer (dialog); whiptail ignores them.
* **The password echo** is `*` (whiptail); dialog shows nothing unless
  `--insecure`; `--fv-echo none` shows nothing.
* **The screen**: the alternate screen per call (whiptail; D34, 4b adds
  `--fv-screen main`); dialog draws on the main screen by default. The
  **infobox** stays on the main screen (dialog); whiptail's vanishes on
  xterm (it uses the alternate screen).
* **The look** is Free Vision's (grey dialog, shadow, `░` desktop; P4-3).
* dialog's `--help-button`, `--extra-button`, `--and-widget`, its exit
  codes 2 / 3 / 5 and the `DIALOG_*` environment are not in the subset
  (refused, not ignored).

Unchanged in both tools and here: the exit codes 0 / 1 / 255 of Enter /
Tab-Enter / Esc / `--defaultno`, the answer without a trailing newline,
nothing written for 1 / 255, `0 0` auto size, `\n` in TEXT, INIT after `--`.

## Contract (kcl README §1) and deviations

§1; deviations: classes (`TDlgApp : TApplication`, `TDlgTitle : TView`)
built at load; friend uses of the same framework: fv.views'
`__FV_VW_LIVE` and `_newReserved` (the reserved names
`__fvdlgapp`, `…__fvdlg`, `…__fvdlg__fvinput`), fv.app's `_firstPaint` (the
infobox's one paint without a loop), fv.video's `_drop` (P4-6 in a
subshell), fv.mouse's `disable` (`--fv-mouse off` without fv.drivers'
flush of the keys); the instance fields read and written
through `${v}_data` (kklass friend contract). The call's terminal settings
(`FV_APP_HEADLESS`, `FV_SCREEN_W/H`, `FV_VIDEO_OUT_FD`, `FV_KEY_FD`,
`FV_ASCII`, `FV_VIDEO_ASCII`, `FV_KBD_PROTO`) are locals of the call (they
start as the caller's: its `FV_APP_HEADLESS=1` is honoured): the
caller's come back at the return. Fork-free but P4-6's buffer (one `rm`, one
`trap -p`, in a subshell one more for fv.video's `_drop`).

## Cost

Counts (`tests/012_Budget.sh`, 80 × 24, the application made … deleted,
headless; design §6.1's limits):

| widget, keys | dispatches | writes | limit |
|---|---|---|---|
| msgbox, Enter | 17 | 11 | 22 / 16 |
| yesno, Enter | 19 | 12 | 24 / 16 |
| infobox (no loop) | 15 | 7 | 20 / 12 |
| inputbox / passwordbox, `abc` Enter | 21 | 14 | 26 / 20 |
| a typed key in the input line | 0 | 1 | 2 / 2 |
| a cursor key in the input line | 0 | 0 | 2 / 2 |
| a key nobody takes in a box | 0 | 0 | 2 / 2 |
| Tab between Yes and No (both buttons, the default mark) | 0 | 3 | 2 / 4 |
| msgbox with `--backtitle` | 20 | 12 | (logged) |

Times: the CI bench (stage 4e, design §6.2). Laptop estimates (Git-bash
5.3, one process): `kk.uses fv.dlg` ≈ fv.app + fv.dialogs (~0.7 s) + 26 ms
for the unit; a headless msgbox call ~65 ms, inputbox ~100 ms, infobox ~58
ms; `NO_COLOR` adds ~20 ms (one `fv.app.setAppPalettes` call for its 32
entries; 32 `setAppPalette` calls took ~60 ms, ~3.7× the batch in the same
process); `--backtitle` ~8 ms.

## Tests

`bash kcl/fv.dlg/tests/tests.sh` — headless (no terminal is touched).
`tests/fvdlg_testlib.sh` builds on fv.app's test lib (the scripted terminal,
the counters).

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API, the readonly constants, the classes; loads, re-loads, `kk.unit --forget` and the main path (every widget, keys from files) under `set -eu`; failing calls under `set -e`; nothing on stdout; no stray names; `PATH=''` and the static fork scan; the refusals' words |
| 002_Parse | every flag in both spellings, the fv extras (exact words: no substring, `nocasematch`), `--fv-size`'s cap, §4.5's rules (H / W checked at once), the refusals, **the golden table's parse rows** (the `f_*` flag rows by ID), `\n` / `\Z`, the fit of a text |
| 003_Boxes | msgbox / yesno / infobox: layout, sizes, `--topleft`, `--backtitle`, `--no-shadow`, `--fv-palette`, labels; Enter / Space / Tab / hot letters / Alt / clicks / Esc / Ctrl+F4 / the close icon / the end of input → 0 / 1 / 255; the infobox's one paint, `noalt`, `FV_KBD_PROTO=off`, the cursor row (fv.video stubbed); `NO_COLOR` (one setAppPalettes call, gray even with `--fv-palette blue` / `cyan`); long titles and labels (clipped, never "terminal too small"); `--fv-mouse off` (fv.video stubbed: the disable after the enable, a key already read kept) |
| 004_Input | input / password: layout, INIT selected and replaced, the golden rows (Tab orders, Esc, blanks, Cyrillic, wide), paste, MaxLen, `--nocancel`, labels, the echo (`*`, `--fv-echo none`) |
| 005_Output | **the golden table's output rows** (stderr / `--stdout` / `--output-fd` / `--stderr`, no newline, nothing on 1 / 255); the bash face; a closed fd (`RESULT` / `FV_DLG_CMD` `''`); the caller's `FV_APP_HEADLESS=1`; the command in a child bash (the swap idiom); P4-6 (buffered and replayed when the fd is the terminal, untouched when it is a file, the EXIT trap, a death during the UI by `exit` / INT / TERM / HUP running the caller's EXIT handler once, inside `$( )` the parent's handler run once by the parent only) |
| 012_Budget | §6.1's limits for the boxes, per key, logged |

The golden table itself (the real tools' runs, the typescripts) is kept in
the stage's scratch folder; its rows are in 002 and 005 with what each
tool did.
