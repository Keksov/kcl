# kcl/fv.dlg — one-shot dialogs for shell scripts

Part of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P4_DESIGN.md](../docs/dev/fv/P4_DESIGN.md), D32–D39). whiptail- and
dialog-compatible flags on Free Vision's classes
([fv.app](../fv.app/README.md), [fv.dialogs](../fv.dialogs/README.md)):
one parser, two faces — the command `fvdlg` (`bin/fvdlg` at the kbool
root, which calls `fv.dlg.main`) and `fv.dlg.run` for bash scripts that
load kbool, with sessions (`fv.dlg.begin` / `fv.dlg.end`) and a
host-application mode.

**Status: P4 stages 4a-1 + 4a-2 + 4b** — the parser (D32's flag set in both
tools' spellings, §4.5's rules), `--msgbox`, `--yesno`, `--infobox`,
`--inputbox`, `--passwordbox`, `--menu`, `--checklist`, `--radiolist`, the
results and exit codes (D37's list answers), P4-6's buffering, `NO_COLOR`,
the sizes and the minimum (P4-8), the scrolling text (P4-9), resize,
sessions and the host application; the command `bin/fvdlg` (its guards
before the load, no terminal: D36), the screen modes (D34). Next: 4d
(gauge, textbox), 4e (bench, docs). The unit loads `kklass_pascal`,
`fv.app` and `fv.dialogs`.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.dlg

fv.dlg.run --title Disk --yesno 'Format /dev/sdb1?' 0 0 && format_it
fv.dlg.run --inputbox 'Your name:' 0 0 "$USER" && name=$RESULT
fv.dlg.run --checklist 'Packages' 0 0 0 git Git on vim Vim off curl curl on
case $? in 0) printf 'chosen: %s\n' "${FV_DLG_TAGS[@]}" ;; 1) echo cancelled ;; 255) echo 'Esc, or an error' ;; esac

fv.dlg.begin --backtitle 'Setup'           # one screen for several questions
fv.dlg.run --inputbox 'Host:' 0 0 localhost && host=$RESULT
fv.dlg.run --passwordbox 'Password:' 0 0 && pass=$RESULT
fv.dlg.run --infobox 'Installing…' 0 0     # returns at once; stays until the next call
fv.dlg.end
```

The command, from any script in any language (nothing is installed: put
kbool's `bin/` on `PATH`, or call the file by its path):

```bash
export PATH=/path/to/kbool/bin:$PATH        # or call /path/to/kbool/bin/fvdlg

fvdlg --title Disk --yesno 'Format /dev/sdb1?' 0 0 && format_it
name=$(fvdlg --stdout --inputbox 'Your name:' 0 0 "$USER") || exit
pick=$(fvdlg --menu 'Pick' 0 0 0 a Apple b Banana 3>&1 1>&2 2>&3)   # whiptail's idiom
fvdlg --infobox 'Installing…' 0 0; long_job   # stays on the screen while long_job runs
```

## The command `bin/fvdlg`

A short script at the kbool root (D33); `fvdlg ARG…` is `fv.dlg.main ARG…`
in a fresh bash, then `exit` with its status. In order (design §7.1):

1. **The bash check, in POSIX syntax** — macOS's `/bin/bash` 3.2 (what
   `#!/usr/bin/env bash` finds there without Homebrew's bash), `sh` or an
   old bash get one line and **255**, never a syntax error: `fvdlg: needs
   bash 5.1 or later (this is 3.2.57)` (`… (this shell is not bash)` under
   dash); bash in POSIX mode (`sh`, `--posix`, `POSIXLY_CORRECT`) is refused
   the same way (kbool does not run there).
2. **kbool's root from the file's own path** (`${BASH_SOURCE[0]%/*}/..`): a
   PATH lookup, `bash fvdlg` in `bin/`, `./bin/fvdlg`, `../bin/fvdlg` all
   work; a symlink to the file is followed with one `readlink -f` (the only
   fork of the command's own), a symlinked folder (`~/bin → kbool/bin`)
   needs nothing. A file missing is named (`fvdlg: cannot find kbool next
   to … (no …/kcl/fv.dlg/fv.dlg.usage.sh; kcl/ is a git submodule: run git
   submodule update --init in …)` — the usual cause is a clone made
   without `--recurse-submodules`); 255.
3. **`--help` / `--version` as the first argument**: printed without loading
   kbool (the text lives in `fv.dlg.usage.sh`, the one copy the unit's
   `fv.dlg.main --help` prints too); a write that fails (stdout closed, a
   full disk) gives printf's status (1), not 0.
4. **No terminal, before the load** (P4-5): `FV_TTY` (default `/dev/tty`)
   that does not exist or does not open read-write, or `TERM` unset or
   `dumb` (unless `FVDLG_FORCE=1`) → **255** and `fvdlg: no terminal
   (/dev/tty)` / `fvdlg: no terminal (TERM is dumb; FVDLG_FORCE=1
   overrides)`, at the cost of bash's start (the load is ~0.7 s) — unless
   the call opted in to default answers (below). The guard refuses only a
   call it is sure of: it is skipped when a `--no-tty` word stands anywhere
   in the line (also after `--`, also as an option's value), for
   `FVDLG_NOTTY=default`, for `--fv-headless` (and the caller's
   `FV_APP_HEADLESS=1`), and when `--help` / `--version` stands anywhere —
   the unit's parser then decides, and `fv.dlg.main` refuses a call without
   a terminal with the same words (its test: the path exists and opens,
   `TERM`, then that it is a terminal). A path that opens but is no
   terminal (a file, `/dev/null`) passes the guard and is refused that way
   after the load (255, `no terminal (/dev/null)`).
5. **The load and the call**: `source kbool.sh`, `kk.uses fv.dlg`,
   `fv.dlg.main "$@"` (`FVDLG_NOTTY`'s value first, as `--no-tty=VALUE`, so
   a `--no-tty` on the call wins). No fork on these paths beyond the load's.

### No terminal (D36)

CI jobs, cron, `ssh` without `-t`, an editor's shell buffer: by default the
call **refuses** (255, one line, nothing else). A job that wants the
dialogs answered for it opts in:

* **`--no-tty=default`** on the call, or **`FVDLG_NOTTY=default`** in the
  environment: without a terminal the call answers **what Enter on the
  dialog would answer**, with no UI, printed exactly as the UI path prints
  (the same fd, format, no newline): msgbox 0; yesno 0 (`--defaultno`: 1);
  infobox 0 (nothing drawn); inputbox / passwordbox 0 and INIT (as the input
  line keeps it: control characters dropped, at most 1024 clusters); menu
  its `--default-item` (the first item with that tag), else the first tag;
  checklist its `on` tags (D37's forms); radiolist its `on` tag (two `on`:
  the last), or `''` when none is on — Enter answers the marks, not the
  focused row. With a terminal the option changes nothing.
* **`--no-tty=refuse`** (the default) on a call wins over an inherited
  `FVDLG_NOTTY=default` (the call is loaded and `fv.dlg.main` refuses it:
  the same line). `FVDLG_NOTTY` other than `default` / `refuse`: 255 and
  one line, before the load — ignored when the call carries a `--no-tty`
  word or `--fv-headless` (the call says it itself).
* **The inheritance warning**: an exported `FVDLG_NOTTY=default` reaches
  every child script, so every `fvdlg` below it answers by itself — set it
  in the CI job's definition, not in a script others call; the per-call
  flag does not leak. `fv.dlg.run --no-tty=default …` is the bash face's
  same opt-in (the unit never reads `FVDLG_NOTTY`; only the command does).
* **`TERM`** unset or `dumb` counts as no terminal (cron and many service
  managers run without `TERM`; a full-screen program there cannot know the
  terminal's sequences): `FVDLG_FORCE=1` lifts that rule (the dialog then
  runs on whatever `/dev/tty` is). bash itself sets `TERM=dumb` when the
  environment has none, so an unset `TERM` reads `TERM is dumb` (an empty
  one: `TERM is empty`). The `TERM` rule is the command's (`fvdlg`,
  `fv.dlg.main`): `fv.dlg.run` — with or without `--no-tty=default` —
  tests only `FV_TTY` (it exists, opens and is a terminal).

### Signals, background, output fds

* **Ctrl+C → 130, SIGTERM → 143, SIGHUP → 129**, the terminal restored
  first and the caller's handlers run (fv.video's exit path, P4-13); Esc →
  255.
* **A backgrounded call** (`fvdlg … &` in an interactive shell) stops with
  SIGTTOU at its first `stty` ("Stopped (tty output)"), as any full-screen
  program; `fg` resumes it and the dialog appears (P4-12). Not worked
  around: ignoring SIGTTOU would draw over the foreground job.
* **The answer's fd**: an fd that is not open (`--stdout` with stdout
  closed) or a write that fails (a full disk, `/dev/full`): 255 and
  `fvdlg: cannot write the result to fd N`. `x=$(fvdlg --stdout …)` and the
  swap idiom work as is (the UI draws and reads on `/dev/tty`, never on
  stdin / stdout); stderr / stdout that are the terminal are buffered while
  the UI runs (P4-6, below).

The functions themselves (what `bin/fvdlg` runs):

```bash
fv.dlg.main --title Disk --yesno 'Format /dev/sdb1?' 0 0; echo $?
name=$(fv.dlg.main --stdout --inputbox 'Your name:' 0 0 "$USER")
```

## The screen (D34)

| flags | where the dialog draws | after the exit |
|---|---|---|
| (none), `--fv-screen alt`, `--keep-tite` | **the alternate screen** (one `ESC [ ? 1049 h` / `l` per call) | the terminal shows exactly what it showed before |
| `--fv-screen main` | the screen itself (fv.video's `initVideo noalt`: not cleared — the first frame paints every cell with the desktop and the dialog) | **the last dialog stays**, as drawn when it ended (its focus, the typed text, the list), the cursor on the **last row, column 0**, shown — dialog's `endwin` does the same (golden: `ESC [ 24 ; 1 H`), so the shell's next output starts below the dialog and scrolls it up. The move is fv.video's restore, so it holds on **every exit path**: Esc, Ctrl+C / SIGTERM / SIGHUP, a script that exits inside a session without `fv.dlg.end` |
| `--erase-on-exit`, `--fv-screen main --clear` | the screen itself | **cleared** (`ESC [ 0 m ESC [ H ESC [ 2 J`), then the cursor on the last row (dialog's order: golden `ESC [ H ESC [ J`, then `ESC [ 24 ; 1 H`) |

A call refused on the main screen before a dialog was built (the terminal
too small) leaves the screen as it found it: nothing painted, nothing
cleared; the refusal's line follows on the last row.

**Precedence**: `--fv-screen` wins; else `--keep-tite` (alternate) beats
`--erase-on-exit` (main); else the alternate screen. `--clear` and
`--erase-on-exit` clear only the main screen (on the alternate screen the
clear has nothing to show: the screen found comes back). **The infobox**
always draws on the main screen and is **never cleared** (`--clear` /
`--erase-on-exit` ignored for it: the box is meant to stay; P4-10). A
**session** (`fv.dlg.begin [--fv-screen alt|main] [--keep-tite]
[--erase-on-exit] [--clear]`) takes the mode once: one terminal start for
all its dialogs (on the main screen by begin, `noalt`), and `fv.dlg.end`
leaves what the session shows (its desktop, the background title, an
infobox still up) with the cursor on the last row — or clears it; nothing
flashes between its dialogs. Inside a session or a host application a
run's `--fv-screen` is refused (255: the screen belongs to begin / the
host) and `--keep-tite` / `--erase-on-exit` / `--clear` are accepted and
ignored. A terminal the caller turned on itself (`fv.video.initVideo`)
keeps its own screen: the mode is not applied. A loop of calls on the main
screen paints each dialog over the last (no flash: fv.video's `noalt`
start does not clear the screen, the first frame paints every cell); on the alternate
screen the shell's screen shows between them — scripts with loops pass
`--fv-screen main` or, in bash, use a session.

## The faces

| Function | Answer |
|---|---|
| `fv.dlg.main ARG…` | the command: the answer **on stderr** by default, stdout with `--stdout`, fd N with `--output-fd N`; written once, after the terminal is restored, **without a trailing newline** (`--separate-output`: each tag and a newline), only for status 0; stderr and stdout buffered while the UI runs when they are the terminal (P4-6, below); `--help` / `--version` on stdout (status 0). **Returns** the status (bin/fvdlg exits with it). Refusals: one line `fvdlg: …` on stderr |
| `fv.dlg.run ARG…` | the same argv and rules; the answer in **`RESULT`** (the input text, the menu's / radiolist's tag, the checklist's answer in its output form; `''` for 1 / 255 and the boxes), **`FV_DLG_TAGS`** the chosen tags as an array (a list widget and status 0; else empty), **`FV_DLG_CMD`** the FV command that ended the dialog (`cmOK cmYes cmNo cmCancel`, `''` after a refusal); prints nothing unless `--stdout`, `--stderr` or `--output-fd` asks; the same status. Refusals: `fv.dlg.run: …` (the same words); `--help` / `--version` are refused (the command's) |
| `fv.dlg.begin [OPTION…]` | **a session** (design §2.2): one application and one screen for the `fv.dlg.run` calls until `fv.dlg.end` — no terminal start / stop per dialog, nothing flashes between them, the desktop and the background title painted at once. Options: `--backtitle T`, `--fv-ascii` / `--ascii-lines`, `--fv-mouse on\|off`, `--fv-screen alt\|main`, `--keep-tite`, `--erase-on-exit`, `--clear`, `--fv-headless [--fv-keys F] [--fv-size WxH] [--fv-out F]`; `NO_COLOR` applied once. Status 0; 255 and one line `fv.dlg.begin: …` for a session already running, an fv application already running, a dialog's option, no terminal |
| `fv.dlg.end` | the session's application deleted (fv.video gives the terminal back), its key / frame files closed, the caller's terminal settings back. In a host application: the infobox `fv.dlg.run` left there removed. Without either: nothing. Status 0 |

Where a dialog runs:

* **Alone** (no fv application in the shell): each call makes a headless
  or real application (`TDlgApp`), runs the dialog modal and deletes the
  application; fv.video turns the terminal on and gives it back exactly as
  found (fv.video README, "The terminal"); the answer is printed after that.
* **In a session**: on the session's desktop; a run's `--backtitle`
  replaces the session's title text. An **infobox** returns at once and
  stays on the desktop until the next call (or `fv.dlg.end`). The terminal
  options (`--fv-headless`, `--fv-keys`, `--fv-size`, `--fv-out`,
  `--fv-ascii` / `--ascii-lines`, `--fv-mouse`, `--fv-screen`) belong to
  `fv.dlg.begin`: given to `fv.dlg.run` inside the session they are refused
  (255); `--clear`, `--keep-tite`, `--erase-on-exit` are accepted and the
  session's screen stays. A script that exits without `fv.dlg.end` still
  gets its terminal back (fv.video restores it on every exit path).
* **Inside a running fv application** (`FV_APP` live, not a session — the
  host): on the host's desktop (its menu bar and status line stay; the
  minimum is checked against the desktop: `the desktop is too small (need
  …)`); the host's palette is left alone (`NO_COLOR` is the host's
  business), `--backtitle` is ignored, the terminal options are refused; an
  infobox stays until the next call or `fv.dlg.end` and is inserted **not
  selectable**: the host's current window keeps its focus and its state (a
  session's infobox is not the desktop's current view either). **The host
  owns the layout on a resize** (L1): fv.dlg lays nothing out again and
  checks no minimum there — the host's desktop moves the dialog by
  TDialog's own `CalcBounds` and the controls follow by their `GrowMode`; a
  dialog wider than the new desktop is clipped, as any host window.
* **`$( … )`**: without a session it works — the subshell owns its own
  terminal and pays the whole terminal start; capture the answer with
  `--stdout` (the subshell's `RESULT` does not reach the caller). Inside a
  session or a host application it is **refused** (255, `refused in a
  subshell (…): call it in the shell that owns the screen, the answer is in
  RESULT`; design §2.2 said rc 2 — 255 keeps the unit's status set, so a
  `case $?` with 0 / 1 / 255 covers it). A session begun inside a subshell
  is that subshell's.

Printing to a terminal fd (`--stdout` when stdout is the terminal) inside a
session or a host writes onto the dialog screen; read `RESULT` there.

### Exit status

| status | constant (readonly) | when |
|---|---|---|
| 0 | `FV_DLG_OK` | OK, Yes; a list's OK (also with nothing checked); the infobox |
| 1 | `FV_DLG_CANCEL` | Cancel, No (the buttons send `cmNo`, P4-4) |
| 255 | `FV_DLG_ESC` | Esc, Ctrl+F4, the close icon, the end of input; no terminal (without `--no-tty=default`); too small (also after a resize); bad arguments; a result fd that cannot be written; a call refused in a subshell (one line on stderr); the command on a bash below 5.1 |
| 130 / 143 / 129 | — | Ctrl+C, SIGTERM, SIGHUP: fv.video's exit path (the terminal restored, then the signal's status) |

## Widgets

| widget | built from | answer |
|---|---|---|
| `--msgbox TEXT H W` | `TDialog` (gray, FV's frame, close icon, shadow) + `TStaticText` (or `TDlgText`, below) + `O~K~` (`cmOK`, default) | 0 / 255 |
| `--yesno TEXT H W` | + `~Y~es` (`cmYes`) / `~N~o` (`cmNo`); `--defaultno`: No selected and default | 0 / 1 / 255 |
| `--infobox TEXT H W` | the dialog without buttons, **drawn once, no loop** (P4-10): alone on the main screen (`initVideo noalt`, so the box stays visible after the exit), `FV_KBD_PROTO=off` unless the environment sets it (no keyboard query whose reply could land on the shell), the cursor left on the screen's last row; fv.video's init clears the screen first. In a session / a host: drawn on the desktop, returns at once, left there until the next call | 0 |
| `--inputbox TEXT H W [INIT]` | + `TInputLine` (1024 clusters; INIT shown **selected**: the first typed key replaces it, FV's rule; End keeps it) + `O~K~` / `Cancel` (`cmNo`); wide and joined characters, the clipboard keys and bracketed paste are the input line's | 0 + the text / 1 / 255 |
| `--passwordbox TEXT H W [INIT]` | the same with `*` per character (D38); `--fv-echo none`: blanks and no cursor | 0 + the text / 1 / 255 |
| `--menu TEXT H W LH TAG ITEM…` | + **`TDlgList : TListBox`** (+ a `TScrollBar` only when the items do not fit), rows `tag  item` (the tags padded to the widest) + `O~K~` / `Cancel` | 0 + the focused tag / 1 / 255 |
| `--checklist TEXT H W LH TAG ITEM STATUS…` | the list with `[X]` / `[ ]` from its marks (STATUS `on` / `off`, any case) | 0 + the checked tags (D37) / 1 / 255 |
| `--radiolist TEXT H W LH TAG ITEM STATUS…` | the same with `(*)` / `( )`; **exactly one mark** at most | 0 + the marked tag / 1 / 255 |

**The lists** (design §5.1). `LH` = the list's rows (`0`: every item, as
far as the box allows); `--default-item TAG` focuses the first item with
that tag (also in a checklist / radiolist: dialog's behaviour; whiptail
ignores it there); `--notags` shows the items only, `--noitem` the tags only
(both: the tags); `--nocancel` drops Cancel. Keys: Up / Down, PgUp / PgDn
(by the list's rows), Home / End; **Enter** answers OK with the focused
(menu) / marked (checklist, radiolist) tags; Tab moves to OK / Cancel (Tab
Enter = OK, Tab Tab Enter = Cancel, as whiptail). **Space** toggles a
checklist item and marks a radiolist item — the radiolist keeps exactly one
mark (Space on another moves it, Space on the marked one keeps it); **Ins**
does the same and moves down (FV's D29); Space in a menu does nothing.
**A printable character** jumps to the next item after the focused one
whose tag (with `--notags`: the shown item) starts with it,
case-insensitive both ways, wrapping (dialog's rule, in every list, digits
and non-Latin letters too); a character no item starts with does nothing
(it never reaches the buttons' hot keys). **The mouse**: a click focuses an
item, a double click answers OK with it (menu) / toggles it (checklist) /
marks it (radiolist); the wheel and the bar scroll. **Two `on` items** in a
radiolist: the last one is marked (whiptail; dialog marks the first).
Validation: an empty list, an incomplete group, a STATUS other than `on` /
`off`, a negative or non-integer LH → 255 and one line.

**The list answers** (D37, the golden table):

| widget, flag | answer (written / `RESULT`) |
|---|---|
| `--menu`, `--radiolist` | the tag bare (`my app`; `--separate-output` and `--single-quoted` change nothing: whiptail / dialog); nothing chosen in a radiolist: `''`, status 0 |
| `--checklist` (default; `--fv-output quoted`) | **whiptail's form**: each tag in double quotes, one blank between, **nothing escaped** (`"git" "my app" "it's" "x"y" "a\b" ""`) |
| `--checklist --separate-output` (`--fv-output lines`) | each tag and a newline (`git⏎my app⏎`), no quotes |
| `--checklist --single-quoted` (`--fv-output single`) | **dialog's form**: a tag quoted only when it is empty or holds a blank, a tab, a newline, `'`, `\` or one of `[ ] { } ? * ; `` ` `` ~ # $ ^ & ( ) \| < >`; inside the quotes `'`, `\` and a newline get a backslash (`git 'my app' 'it\'s' x"y 'a\\b' 'a*b' ''`) |
| `--fv-output` | wins over `--separate-output` / `--single-quoted`; `--separate-output` wins over `--single-quoted` |

Nothing checked: `''` with status 0. `FV_DLG_TAGS` holds the tags whatever
the form; duplicates are kept (both tools write them twice).

**Layout.** The text from cell 2 of row 1 (`\n` written as two characters is
a newline; long lines wrap at blanks, TStaticText's rule); the input line
below it; a list's rows below the text and a blank, from column 2 (the bar
right of them), a blank under them; the buttons centred on the row `H − 3`
(each the label's cells + 4, at least FV's 10, two cells apart). The box is
centred on the desktop (`--topleft`: at the top left); `--backtitle T`:
row 0 in the background's colours (`TDlgTitle`), the box below it. No
status line, no menu bar. FV's desktop (`░`) is the background.

**Sizes** (P4-8, design §5.3): `0` = fit — the width: the text's widest
line + 5 columns (the text at most 2/3 of the desktop), a list's widest row
+ 6 (+ 1 for the bar), at least the title + 16 (FV TFrame's room for a title beside the close icon: W - 16) and the buttons, at most the
desktop; the height: the text's rows + 5 (msgbox, yesno), + 7 (input), + 2
(infobox), a list's text + LH rows + 6, at most the desktop (a list gets its
rows first; the text at most half the room when both do not fit) — `-1` =
the desktop (below the background title; dialog's meaning), a number = that
size, clamped. **Spare rows go to the list** (L7, dialog's behaviour): an
explicit `H` (or `-1`) taller than the text and LH rows need keeps the text
at its rows and gives every other row to the list, past LH (blank rows
below the last item when there are fewer items). **The minimum** of each widget, exactly: across, the buttons
+ 4 (the frame and a blank each side), at least 16 (the frame's icon and a
title); down, msgbox / yesno **5**, inputbox / passwordbox **7**, the lists
**8**, the infobox **3** (+ 1 with a background title). A smaller `H` /
`W` grows to it; a desktop below it: 255 and `terminal too small (need WxH,
have WxH)` — only for the geometry: a title wider than the box is cut by
the frame, button labels wider than the desktop allows are clipped (a
short one keeps its cells, the other gets the rest; a `~` letter that
survives the cut still works), long text scrolls.

**Resize** (§3.5): a terminal resize re-lays the running dialog out — it
takes its size again (`-1`: the new desktop; a number or the fit: as
built, at most the desktop, at least the minimum), centred again, and a
new size **lays the controls out as a build at that size would** (H1):
the same text / list split (the text at most half the room when both do
not fit), the text made again in its place — a static text that no longer
fits becomes the scrolling view (wrapped at the new width, its bar), a
scrolling one that fits again goes back to static — the list moved to its
rows with its bar made or dropped, the focused item kept on screen, the
input line and the buttons on their rows. What the user did stays: the
focused control (a msgbox's / yesno's text takes the focus when it starts
to scroll and the default button had it, as a build gives it), the input
text and cursor, the list's focus and marks. At or above the minimum
every control keeps one row at least; growing back restores the layout as
built. **Below the minimum the dialog ends**: status 255 and the
`terminal too small (…)` line after the terminal is restored (§3.7's rule:
no clipped dialog keeps running). In a host application the host owns the
layout (above).

**The scrolling text** (`TDlgText : TListViewer`, P4-9). Text that needs
more rows than the box has (an explicit H, or the desktop's height) — the
msgbox's / yesno's text, the prompt above an input line or a list — becomes
a read-only view of its wrapped lines with a bar: the rows in the static
text's colour (no highlighted focus row), Up / Down by a row, PgUp / PgDn
by the view's rows, Home / End, the wheel and the bar scroll it. In a
msgbox / yesno it takes the focus, Enter still presses the default button
(whiptail's `--scrolltext` needs Tab first); Tab reaches the buttons; the
input line / the list keep the focus otherwise. `--scrolltext` (msgbox,
yesno) uses the view even for text that fits (no bar then). Text that fits
stays a `TStaticText` (4a-1's layout unchanged).

**Keys.** FV's: Enter presses the default button, Tab / Shift+Tab and the
arrows move between the controls, Space presses the focused button, the
button's `~` letter (Alt + it, or the plain letter: `y` / `n` / `k` — not
while a list has the focus), a click on a button; Esc and Ctrl+F4 and the
close icon answer `cmCancel` (255). Labels given with `--yes-button` and
the like have no hot letter (a `~` in them marks one); an empty label
(`--ok-button ''`, any of them) is a blank button of FV's minimum width
(L3).

## Results and the terminal

| flag | the answer goes to | idiom |
|---|---|---|
| (none) | stderr (fd 2) — the command; nothing — `fv.dlg.run` | `x=$(fvdlg --inputbox … 3>&1 1>&2 2>&3)` |
| `--stdout` | stdout | `x=$(fvdlg --stdout --inputbox …)` |
| `--stderr` | stderr | |
| `--output-fd N` | fd N (an fd that is not open: 255, one line, `RESULT`, `FV_DLG_TAGS` and `FV_DLG_CMD` empty as for every 255) | `fvdlg --output-fd 3 --inputbox … 3>answer.txt` |

**P4-6, output during the UI.** In the command's face (a call alone), while
the dialog is shown, stderr — and stdout — **when that fd is the terminal**
go to a private file (`$TMPDIR`, mode 0600 under `umask 077`, `noclobber`,
a name that cannot be predicted); after the terminal is restored the file
is copied to the terminal (stderr's when it was buffered, else stdout's)
and removed, then the answer is written. A file, a pipe or a capture (the
swap idiom's fd 2) is never touched. The caller's EXIT trap is set aside
while the UI runs (the one active in this process: inside `$( )` or `( )`
the parent's trap texts that `trap -p` still shows there are dropped
first, so the parent's handler never runs in the subshell) and put back
after. If the process dies during the UI (`exit`, or Ctrl+C / SIGTERM /
SIGHUP through fv.video's handlers), the EXIT trap still restores the fds,
replays and removes the buffer, then runs the caller's EXIT handler once,
with the status kept. The buffer costs one `rm` and one `trap -p` (in a
subshell one more, fv.video's `_drop`) — the unit's only processes — and is
made only when an fd is the terminal. In a session or a host there is no
buffer (the screen stays the session's).

**`NO_COLOR`** (any non-empty value, no-color.org): the app palette's
entries a dialog uses become light grey / white on black, the focused
button, the input field and the selection in reverse (FV's black-and-white
idea), through one `fv.app.setAppPalettes` call before the first paint (a
session: at `fv.dlg.begin`); the palette is the default again after the
call. Under `NO_COLOR` the dialog keeps the gray palette even with
`--fv-palette blue` / `cyan` (those entries are not mapped). A host
application's palette is not touched.

## The flags

`w` = whiptail 0.52.25, `d` = dialog 1.3-20250116 (both checked on Debian
13, the golden table below); fvdlg accepts both tools' spellings. Unknown
flags are refused (255, one line), never ignored.

| flag | w | d | fvdlg |
|---|---|---|---|
| `--msgbox --yesno --infobox --inputbox --passwordbox` | ✓ | ✓ | ✓ |
| `--menu --checklist --radiolist` | ✓ | ✓ | ✓ (`TDlgList`; empty lists refused: dialog; whiptail answers an empty checklist with 0 and crashes on an empty radiolist) |
| `--gauge --textbox` | ✓ | ✓ | refused "not supported yet" (4d) |
| `--title T`, `--backtitle T` | ✓ | ✓ | ✓ (a session: the session's title, a run's replaces its text; a host: ignored) |
| `--ok-button L` / `--ok-label L` | button only | both | both |
| `--cancel-button` / `--cancel-label`, `--yes-button` / `--yes-label`, `--no-button` / `--no-label` | button only | both (the last wins) | both (the last wins) |
| `--defaultno` | ✓ | ✓ | ✓ (yesno) |
| `--nocancel` / `--no-cancel` | nocancel | both | both (no Cancel button: input, lists) |
| `--stdout`, `--stderr` | — | ✓ | ✓ |
| `--output-fd N` | ✓ | ✓ | ✓ |
| `--default-item T` | ✓ (menu only) | ✓ | ✓ (every list) |
| `--separate-output` | ✓ | ✓ (not radiolist: 255) | ✓ (checklist; menu / radiolist bare) |
| `--single-quoted` | — | ✓ | ✓ (checklist; dialog's form) |
| `--notags` / `--no-tags`, `--noitem` / `--no-items` | ✓ (`no-` forms: d) | ✓ | ✓ |
| `--colors` | — | ✓ | `\Z0`–`\Z7`, `\Zb \ZB \Zr \ZR \Zu \ZU \Zn` stripped (no colours in v1); without it they are text, as in both tools |
| `--clear`, `--keep-tite`, `--erase-on-exit` | clear only | ✓ | the screen modes ([The screen](#the-screen-d34)): `--keep-tite` the alternate screen, `--erase-on-exit` the main screen cleared at the exit, `--clear` the main screen cleared (the infobox: never); a session takes them at `fv.dlg.begin` |
| `--scrolltext` | ✓ | ✓ | the scrolling text view (msgbox, yesno) |
| `--fb` / `--fullbuttons`, `--no-collapse`, `--cr-wrap`, `--trim`, `--insecure` | fb, fullbuttons | ✓ (not fullbuttons) | accepted, no effect (FV buttons are full; whiptail's text rule; `*` always) |
| `--topleft` | ✓ | ✓ | the box at the top left |
| `--ascii-lines` | — | ✓ | = `--fv-ascii` |
| `--no-shadow` | — | ✓ | the box without FV's shadow |
| `--help`, `--version` | ✓ | ✓ | the command only |
| `--help-button --extra-button --and-widget --item-help --timeout`, dialog's other widgets | — | ✓ | refused (outside the subset) |
| `--fv-palette gray\|blue\|cyan` | | | FV's dialog palettes |
| `--fv-ascii` | | | ASCII mode (`FV_ASCII=1` for the call / the session) |
| `--fv-mouse on\|off` | | | off: mouse reporting switched off right after the start (the keys already typed are kept) |
| `--fv-echo star\|none` | | | the password echo (D38) |
| `--fv-screen alt\|main` | | | where the dialog draws (D34; the alternate screen by default); wins over `--keep-tite` / `--erase-on-exit` |
| `--no-tty=default\|refuse` | | | no terminal: answer what Enter would (default) or 255 (refuse, the default); `FVDLG_NOTTY` is the command's environment twin (D36, [No terminal](#no-terminal-d36)) |
| `--fv-output lines\|quoted\|single` | | | the checklist's answer form (D37) |
| `--fv-headless`, `--fv-keys FILE`, `--fv-size WxH`, `--fv-out FILE` | | | no terminal: the keys from FILE (the bytes a terminal sends; the end of the file is the end of input), the frames to FILE (default `/dev/null`), the size (default 80x24, 1–1000 per side) — tests and the bench. A caller's own `FV_APP_HEADLESS=1` (with its `FV_KEY_FD`, `FV_VIDEO_OUT_FD`, `FV_SCREEN_W` / `_H`: fv.app's convention) is honoured without these flags |

**Parser rules** (P4-7, design §4.5): options anywhere before `--`, also
after the widget's arguments (`--msgbox Hi 10 40 --title T`); the widget's
fixed positionals are taken literally (TEXT may be `-5` or `--title`); H, W
and a list's LH must be integers (LH ≥ 0), checked as soon as they are
taken (the refusal names the word that stood there); an fv extra's value is
one of its words, exactly (no pattern, whatever `nocasematch` says); an
optional positional (INIT) is taken unless it is exactly a known option
(`--inputbox N 0 0 -x` → INIT `-x`); **list items** come in groups (`TAG
ITEM` / `TAG ITEM STATUS`): inside a group every word is data, at a group
boundary `--` and a known option are what they are (so trailing options
work) and any other word starts a group (`-x` is a tag); `--` ends the
options (`--inputbox N 0 0 -- --weird`, `--menu T 0 0 0 -- - Dash`);
`--opt=value` or `--opt value`; one widget per call; anything left over is
refused.

## What differs from whiptail / dialog

From the golden table (`whiptail` / `dialog` under `script(1)` with scripted
keys; rows in `tests/002_Parse.sh`, `tests/005_Output.sh` and
`tests/006_Lists.sh`):

* **INIT is selected**: the first key replaces it (FV). Both tools put the
  cursor after it and append (`init` + `x` → `initx`); End first gives
  their result.
* **Unknown options**: 255 and `fvdlg: unknown option '--x'`. whiptail
  answers **1** ("--x: unknown option"), dialog 255.
* **Extra arguments are refused** (`--msgbox t 0 0 extra`); whiptail ignores
  them, dialog refuses.
* **Options after the positionals** work (whiptail); dialog refuses them.
  `--title=T` works (whiptail); dialog refuses it.
* **Options between the positionals are refused**: the fixed ones are
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
* **The checklist's default answer** is whiptail's (every tag quoted,
  nothing escaped); dialog's default quotes only as needed and escapes —
  its form is `--single-quoted`'s here (dialog's own `--single-quoted`).
* **STATUS** must be `on` / `off` (any case); whiptail takes anything but
  `off` (any case) for on, dialog anything but `on` for off — `1`, `yes`
  are refused here (255).
* **Letter jumps** follow dialog: every list, any printable character, the
  next match after the focused item. whiptail jumps only in a menu, only
  on ASCII letters, and searches from the top unless the focused tag
  already starts with the letter (golden2 `menu_wrap`: from `cherry`, `a` →
  whiptail `apple`, dialog and fvdlg `avocado`).
* **`--default-item`** works in every list (dialog); whiptail ignores it in
  a checklist / radiolist.
* **Two `on` in a radiolist**: the last (whiptail); dialog the first.
* **Ins** toggles and moves down in a checklist (FV D29); both tools ignore
  it.
* **Empty lists** are refused (dialog, and whiptail's menu); whiptail
  answers an empty checklist with 0 and crashes (signal 11) on an empty
  radiolist.
* **`--separate-output` with a radiolist** answers the bare tag
  (whiptail); dialog refuses it.
* **Tab in a list**: Tab Enter = OK, Tab Tab Enter = Cancel (whiptail);
  dialog's list is no tab stop (Tab Enter = Cancel).
* **`--scrolltext`**: Enter presses OK at once; whiptail's focus stays on
  the text (Tab Enter).
* **The screen**: the alternate screen per call by default (whiptail; D34;
  `--fv-screen main` or `--erase-on-exit` for the main screen); dialog
  draws on the main screen by default (`--keep-tite` for the alternate
  one). The **infobox** stays on the main screen (dialog); whiptail's
  vanishes on xterm (it uses the alternate screen). `--clear` /
  `--erase-on-exit` leave the cursor home on a blank screen; dialog clears
  (`--clear`: its dialog's area only) and puts the cursor on the last row.
  `--clear --infobox`: the box stays (dialog erases it at once).
* **No terminal**: 255 and one line, at once (before the load); neither
  tool runs without a terminal either (not in the golden table).
  `--no-tty=default` / `FVDLG_NOTTY=default` are fvdlg's own (D36).
* **The look** is Free Vision's (grey dialog, shadow, `░` desktop; P4-3).
* dialog's `--help-button`, `--extra-button`, `--and-widget`, its exit
  codes 2 / 3 / 5 and the `DIALOG_*` environment are not in the subset
  (refused, not ignored).

Unchanged in both tools and here: the exit codes 0 / 1 / 255 of Enter /
Tab-Enter / Esc / `--defaultno`, the answer without a trailing newline,
nothing written for 1 / 255, `0 0` auto size, `\n` in TEXT, INIT after
`--`, a menu's tag and a radiolist's tag bare, `--separate-output`'s lines,
Space in a menu doing nothing, Space on the marked radio item keeping it,
PgDn by the list's rows, duplicate tags written twice.

## Contract (kcl README §1) and deviations

§1; deviations: classes (`TDlgApp : TApplication`, `TDlgTitle : TView`,
`TDlgList : TListBox`, `TDlgText : TListViewer`) built at load. **The
elision table**: `TDlgList.HandleEvent` / `SelectItem`, `TDlgText.GetPalette`
/ `HandleEvent` and `TDlgApp.HandleEvent` register their plain bodies in
fv.views' `__FV_VW_IMPL` (as fv.dialogs does for its classes), so the
lists' keys cost no kklass dispatch (design §5.1 counted 2 per key) and
`TDlgText`'s func override prints nothing inside `$( )`. Friend uses of
the same framework: fv.views' `__FV_VW_LIVE`, `__FV_VW_OWNER`,
`__FV_VW_C2A`, `_newReserved` (the reserved names `__fvdlgapp`,
`…__fvdlg` / `…__fvdlg2`, `…__fvbacktitle`, `…__fvdlg__fv{text,input,list,
listbar,textbar,b1,b2}`), `_showNow`, `_message`, `_lvEvent` /
`_lvSelectItem` (the inherited bodies), `__FV_VW_LY` (a list bar made on a
resize gets its steps); fv.video's `__FV_VS_PNA` (printable ASCII), `_g`
(below) and `_drop` (P4-6 in a subshell); fv.app's `_firstPaint` (the
infobox's one paint without a loop; a session's first paint) and
`_appEvent` (TApplication's HandleEvent body); fv.mouse's `disable`
(`--fv-mouse off` without fv.drivers' flush of the keys); fv.dialogs'
`_ilPre` and `__FV_DG_CC` (D36's INIT kept as the input line keeps it);
fv.video's `FV_VIDEO_OUT_FD` / `FV_TTY_FD` written directly once (the
main screen's clear at the exit); the instance
fields read and written through `${v}_data` (kklass friend contract). **A
data file**: `fv.dlg.usage.sh` (the `--help` / `--version` text, shared
with `bin/fvdlg`) is sourced by `fv.dlg._usage` only for those flags. The
list's and the text view's data live in `__DLFV_TAGS`, `__DLFV_ROWS`,
`__DLFV_MARKS`, `__DLFV_FIRST`, `__DLFV_NEXT`, `__DLFV_TEXT` (fv.views
refuses List / Marks names that start with `_fv` / `__fv`). **The locale**
(fv.video's D11, M2): a caller whose locale is not UTF-8 (`LC_ALL=C`), or
with `nocasematch`, or without `globasciiranges`, runs `fv.dlg.run` /
`fv.dlg.main` / `fv.dlg.begin` whole through `fv.video._g` — a UTF-8 locale
of its own and the caller's state put back by fv.video's L-1 rules — so
the letter jumps fold and match characters (Cyrillic, CJK) and the wrap
never cuts inside a UTF-8 sequence; the answers and the screen are the
same as under a UTF-8 locale. A call's terminal settings
(`FV_APP_HEADLESS`, `FV_SCREEN_W/H`, `FV_VIDEO_OUT_FD`, `FV_KEY_FD`,
`FV_ASCII`, `FV_VIDEO_ASCII`, `FV_KBD_PROTO`) are locals of the call (they
start as the caller's: its `FV_APP_HEADLESS=1` is honoured); a session's
are set by `fv.dlg.begin` and the caller's come back at `fv.dlg.end`.
Fork-free but P4-6's buffer (one `rm`, one `trap -p`, in a subshell one
more for fv.video's `_drop`). `bin/fvdlg` adds none but one `readlink -f`
when it is called through a symlink.

## Cost

Counts (`tests/012_Budget.sh`, 80 × 24, the application made … deleted,
headless; design §6.1's limits):

| widget, keys | dispatches | writes | limit |
|---|---|---|---|
| msgbox, Enter | 17 | 11 | 22 / 16 |
| yesno, Enter | 19 | 12 | 24 / 16 |
| infobox (no loop) | 15 | 7 | 20 / 12 |
| inputbox / passwordbox, `abc` Enter | 21 | 14 | 26 / 20 |
| menu (8 items), Down Down Enter | 21 | 13 | 36 / 20 |
| checklist (5), Space Down Space Enter | 21 | 14 | 40 / 20 |
| radiolist (5), Space Down Space Enter | 21 | 15 | 40 / 20 |
| menu, a double click on an item | 21 | 13 | 36 / 20 |
| checklist of 10 000 items, End Space Enter | 23 | 14 | 40 / 20 |
| msgbox with scrolling text, PgDn Enter | 19 | 11 | 36 / 20 |
| a key on a list (Down, PgDn, Space; a radio Space, a letter jump) | 0 | 1 (1.25, 1.5) | 1 / 3 |
| a scrolling text key | 0 | 1 | 1 / 3 |
| a typed key in the input line | 0 | 1 | 2 / 2 |
| a cursor key in the input line | 0 | 0 | 2 / 2 |
| a key nobody takes in a box | 0 | 0 | 2 / 2 |
| Tab between Yes and No (both buttons, the default mark) | 0 | 3 | 2 / 4 |
| msgbox with `--backtitle` | 20 | 12 | (logged) |

Times: the CI bench (stage 4e, design §6.2). Laptop estimates (Git-bash
5.3, one process; labelled estimates, not targets): `kk.uses fv.dlg` ≈
fv.app + fv.dialogs (~0.7 s) + the unit; a headless msgbox call ~65 ms,
inputbox ~100 ms, infobox ~58 ms; `NO_COLOR` adds ~20 ms; `--backtitle`
~8 ms. A session saves the application's construction per dialog and, on
a terminal, fv.video's start / stop (design §1: ~450 ms on Windows, ~65 ms
on Linux). **Big inputs** (L2, M3; laptop, Git-bash): a list of 10 000
items is split by `printf` over the argv and word splitting (no loop per
row; the list's part ~0.5–0.7 s of a ~1.5 s call, most of the rest the
parser), its letter jumps use an index built on the first letter (a
character no item starts with: one lookup); the text wrap is linear (a
line split into its words once, printable ASCII counted by characters, a
long word cut in pieces): a 200 KB one-line msgbox ~3 s headless (4a-2:
quadratic, 40 KB took 9 s).

## Tests

`bash kcl/fv.dlg/tests/tests.sh` — headless (no terminal is touched).
`tests/fvdlg_testlib.sh` builds on fv.app's test lib (the scripted terminal,
the counters; `dbl X Y` a double click).

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API (+ `begin` / `end`), the readonly constants, the classes; loads, re-loads, `kk.unit --forget` and the main path (every widget, a session, keys from files) under `set -eu`; failing calls under `set -e`; nothing on stdout; no stray names; `PATH=''` and the static fork scan; the refusals' words; the elision registrations and each override's owner, a lost registration restored by the next dialog |
| 002_Parse | every flag in both spellings, the fv extras (exact words: no substring, `nocasematch`), `--fv-size`'s cap, §4.5's rules (H / W / LH checked at once, list groups, options at a group boundary, `--` before tags), the refusals, **the golden table's parse rows**, `\n` / `\Z`, the fit of a text |
| 003_Boxes | msgbox / yesno / infobox: layout, sizes, `--topleft`, `--backtitle`, `--no-shadow`, `--fv-palette`, labels; Enter / Space / Tab / hot letters / Alt / clicks / Esc / Ctrl+F4 / the close icon / the end of input → 0 / 1 / 255; the infobox's one paint, `noalt`, `FV_KBD_PROTO=off`, the cursor row (fv.video stubbed); `NO_COLOR`; long titles and labels; `--fv-mouse off`; **the screen modes** (D34: the last picture through fv.video's VT model — alternate: the dialog gone; main: kept, the cursor at the last row; `--erase-on-exit` / `--clear`: blank, cursor home; the precedence table; the infobox never cleared; on a stubbed terminal `initVideo noalt` vs the application's) |
| 004_Input | input / password: layout, INIT selected and replaced, the golden rows, paste, MaxLen, `--nocancel`, labels, the echo |
| 005_Output | **the golden table's output rows**; the bash face; a closed fd; the caller's `FV_APP_HEADLESS=1`; the command in a child bash (the swap idiom); P4-6 |
| 006_Lists | menu / checklist / radiolist: the layout (marks, padding, the bar only when needed, `--notags` / `--noitem` / `--nocancel`), the keys, `--default-item`, radio exclusivity, the letter jumps and the golden2 rows with both tools' answers, the mouse (click, double click), D37's answers and escaping rows, `FV_DLG_TAGS`, the command's face, 10 000 items |
| 007_Sizes | the auto size per widget, `-1`, clamping, the exact minimum per widget (one cell less refused), the scrolling text (rows, colour, keys, prompts, `--scrolltext`), resize (re-centred, shrunk, `-1` following, `--topleft`, below the minimum → 255 after the restore, the text re-wrapped; H1: the controls laid out again — a list keeps its rows and bar, the focused item on screen, a static text turned scrolling, the focus / marks / input text kept, grown back = as built); L7 (spare rows to the list); L3 (empty labels); M3 (the wrap's rows as 4a-2's, long words, a 200 KB line within 60 s) |
| 008_Sourced | `fv.dlg.run` → `RESULT` / `FV_DLG_TAGS` / `FV_DLG_CMD`; a session (one application, the title, the infobox left until the next run, the settings back, the refusals, one `initVideo` / `doneVideo` per session with fv.video stubbed); the host application (its desktop, palette, minimum, refusals, infobox, not selectable: the host's current window and its state kept — M1); begin leaves RESULT '' (L4); `$( )` with and without a session; the session's screen mode (one `initVideo noalt` / `doneVideo` for main, a run's `--fv-screen` refused, the end's cursor row / clear) |
| 009_NoTty | the command without a terminal: the guards before the load (a fake kbool tree's marker), the messages, `TERM` unset / dumb, `FVDLG_FORCE`, D36's default answer per widget (both faces, every output fd and form), `--no-tty=refuse` over `FVDLG_NOTTY`, a closed / full result fd, `--help` / `--version` without the load (the unit's bytes), the root from relative / `./` / PATH / symlinked calls, the bash-3.2-safe prologue (`bash --posix -n`, no 3.2-missing construct, the refusal's words, `sh`, a real `/bin/bash` 3.2 on macOS) |
| 010_Pty | the command on script(1)'s pty (util-linux only; SKIP elsewhere): `x=$(… --stdout …)`, the swap idiom, `--output-fd 3`, the exit codes 0 / 1 / 255 / 130 / 143 / 129, stty equal, the restore sequences, no process or buffer file left, one `?1049h` per call / none on the main screen with the cursor to the last row, `--erase-on-exit`'s clear, the infobox, `NO_COLOR`, `TERM=dumb` (+ `FVDLG_FORCE=1`), P4-6 through the command, a backgrounded call stopped and resumed by `fg` |
| 011_CallerState | a child scene (every widget, a session) under IFS variants, `nocasematch`, `extglob`, `LC_ALL=C` (a Cyrillic jump, a CJK scrolling prompt's frames — M2), `set -u`, `set -e`, the glob options (nullglob, failglob, globstar, dotglob, `set -f` + nocaseglob): the same answers, the caller's state kept; 105 calls leave nothing and grow no table |
| 012_Budget | §6.1's limits for the boxes and the lists, per key (a list key at most 1 dispatch: measured 0), logged |

The golden table itself (the real tools' runs, the typescripts) is kept in
the stages' scratch folders (`p4/golden`, `p4/golden2`); its rows are in
002, 005 and 006 with what each tool did.
