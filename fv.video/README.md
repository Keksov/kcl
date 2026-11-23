# kcl/fv.video — the terminal and the screen buffer for the fv.* text UI

Layers L0 and L1 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It sets the
terminal up for a full-screen program and puts it back on **every** exit path:
raw mode, alternate screen, hidden cursor, autowrap off, the screen size and a
resize flag. Over it, the [screen buffer](#screen-buffer): writes, a 256-colour
palette and a damage diff that sends only what changed, in one `printf` per
frame. It is a port in spirit of the FPC rtl-console `Video` unit
(`InitVideo`, `DoneVideo`, `ScreenWidth` / `ScreenHeight`, `VideoBuf`,
`UpdateScreen`) and FV's `TDrawBuffer` writes: **plain functions, no
classes**. [Wide characters](#wide-characters-emoji-and-clusters) — CJK and
emoji 2 columns, combining marks 0 (decision D5) — are part of the buffer.

The unit loads [`fv.unicode`](../fv.unicode/README.md) (the width and
cluster class of every code point) and no other `fv.*` unit.
[`fv.drivers`](../fv.drivers/README.md) builds the event loop on it;
[`fv.keyboard`](../fv.keyboard/README.md) reads the keys from the fd it opens.
The views and the application above it ([`fv.views`](../fv.views/README.md),
[`fv.menus`](../fv.menus/README.md), [`fv.app`](../fv.app/README.md)) are complete
for P2 (stage 2g), P3's widgets ([`fv.dialogs`](../fv.dialogs/README.md),
[`fv.msgbox`](../fv.msgbox/README.md)) build on them; they all write through
this buffer only.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.drivers                        # loads fv.video, fv.keyboard, fv.mouse

trap 'echo bye' EXIT                      # your traps: set them BEFORE initVideo
fv.video.initVideo || exit 1              # rc 1: no terminal
printf 'hello %sx%s' "$FV_SCREEN_W" "$FV_SCREEN_H" >&"$FV_TTY_FD"
while fv.drivers.getEvent; do
    [[ $FV_EV_KEY == kbF10 ]] && break
done
fv.video.doneVideo                        # also done by the traps if you forget
```

## API

| Function | Answer |
|---|---|
| `fv.video.initVideo [noalt]` | opens the terminal (a missing `FV_TTY` path is no terminal: never opened, so never created), saves its `stty -g` and the caller's traps, installs the traps below, sets raw mode, then starts [the reader and its watchdog](#the-reader-process-git-bash-msys2-cygwin) where `FV_TTY_READER` says so (default: Git-bash, MSYS2, Cygwin), then prints: alternate screen `ESC[?1049h` (not with `noalt`), the keyboard protocol's query or push by `FV_KBD_PROTO` ([P3 3L](#the-keyboard-protocol-p3-3l)), cursor hidden `?25l`, autowrap off `?7l`, SGR reset, clear `ESC[H ESC[2J` (not with `noalt`: the main screen is left as it is — the first frame paints every cell of a buffer of the size read here, so a main-screen TUI shows no blank flash; cleared after all when that size is a guess or wider than the buffer's 1024 columns), bracketed paste on `?2004h` (P3 10.8); reads the size. Typed-ahead input is kept. rc 0 = on (also when it already was — here or in the parent of this subshell: a no-op); rc 1 = no terminal / stty failed — nothing printed to any terminal, nothing left open, one debug line; rc 2 = a mode other than `noalt` |
| `fv.video.doneVideo` | the kitty keyboard flags popped `CSI < u` when they were pushed (first, while the alternate screen is on), SGR reset, `?7h`, `?25h`, `?1049l` (if used), mouse reporting off (`?1006l ?1003l ?1002l ?1000l`, always), bracketed paste off `?2004l` (always), the terminal's default cursor shape `ESC [ 0 SP q` (when a shape was sent, P3 10.7), with `noalt` last the cursor to the last row, column 1 `ESC[<FV_SCREEN_H>;1H` (the picture stays, the shell's next output starts below it — dialog's endwin; on every exit path), the pending input drained (below), the reader and its watchdog stopped, `stty` back to the saved state, the fd closed, `FV_KEY_FD` put back, the caller's traps put back **exactly**. Idempotent: done twice, or done and then the EXIT trap, restores once. In a subshell of the process that called `initVideo`: a no-op (below). rc 0 |
| `fv.video.updateSize` | `FV_SCREEN_W` / `FV_SCREEN_H` from `querySize`; a dimension that is 0, missing, not a number or longer than 5 digits comes from `COLUMNS` / `LINES`, else 80 × 24, with one debug line. Clears `FV_VIDEO_RESIZED` first. rc 0, `RESULT=''` |
| `fv.video.querySize` | the size source: `RESULT="ROWS COLS"`, rc 0; rc 1 when it cannot tell. Default: `stty size` on `FV_TTY_FD` (a fork). **Override it** to take the size from elsewhere; the tests stub it |

| Global | Meaning |
|---|---|
| `FV_SCREEN_W`, `FV_SCREEN_H` | the screen size in cells (80 × 24 until known) |
| `FV_VIDEO_ON` | 1 between a successful `initVideo` and the restore |
| `FV_VIDEO_RESIZED` | 1 after a SIGWINCH; `updateSize` (and so `fv.drivers.getEvent`) clears it |
| `FV_TTY_FD` | the terminal's fd while on, else `''`. **All terminal output goes here**, never to stdout |
| `FV_TTY` | *input*: the terminal's path, default `/dev/tty` |
| `FV_KEY_FD` | fv.keyboard's input fd: set to `FV_TTY_FD` by `initVideo` — or to the reader's pipe where the reader runs — its old value (or unset state) put back by the restore |
| `FV_TTY_READER` | *input*: `1` / `0` force [the reader](#the-reader-process-git-bash-msys2-cygwin) on / off; empty = auto (on for `OSTYPE` `msys*`, `cygwin*`) |

Internal state is `__FV_VI_*`.

## The terminal

* **`/dev/tty`, not stdin/stdout.** `initVideo` opens `FV_TTY` read-write on a
  bash-allocated fd (`exec {fd}<>/dev/tty`); `stty` runs on it and every byte the
  unit prints goes to it. A TUI therefore works inside `x=$(…)` (the dialog
  draws on the terminal, the value goes to `x`) and with stdin or stdout
  redirected.
* **Raw mode:** `-echo -icanon -ixon min 1 time 0`; **`intr` is kept**, so
  Ctrl+C stays an interrupt that restores the terminal (and `kbCtrlC` never
  arrives while the TUI runs — also under the kitty keyboard protocol, which
  sends Ctrl+C as `CSI 99;5u` instead of 0x03: fv.keyboard's readers raise
  SIGINT for that report while the TUI is on, [below](#the-keyboard-protocol-p3-3l));
  `susp`, `quit` and `lnext` are undefined, and so
  are `dsusp`, `discard`, `status` and `swtch` where the platform's `stty -a`
  lists them (probed once per process), so Ctrl+Z, Ctrl+\ and Ctrl+V arrive as
  `kbCtrlZ`, `kbCtrlBackslash`, `kbCtrlV` and nothing stops the process. ICRNL
  and IEXTEN are left as they are: bash's `read -n1` turns ISIG, ICRNL and
  IEXTEN on for each read anyway (CR arrives as LF; both are `kbEnter`).
* **Never DECKPAM (`ESC =`) nor DECKPNM (`ESC >`):** in keypad application mode
  the keypad sends `ESC O p…y`, which fv.keyboard reads as the vt100 F5–F12.
* **A cursor-position query** (`ESC [ 6 n`, a later wide-character probe) must
  read its reply with its own reader: `ESC [ r ; c R` decodes as a modified F3.

## The TUI is owned by the process that called initVideo

A subshell (`x=$(…)`, `( … )`, a pipeline element) inherits the state but not
the ownership:

* parent on → in the subshell `initVideo` is rc 0 and a no-op (the subshell
  draws on the parent's terminal through the inherited `FV_TTY_FD`,
  `FV_VIDEO_ON` reads 1), and `doneVideo` and the restore are no-ops: the
  parent's screen, stty and traps stay as they are;
* parent off → a subshell that calls `initVideo` owns its own TUI: its
  `doneVideo` or its exit restores the terminal, and the parent is untouched.

The owner is recorded as `$BASHPID` at init.

## The keyboard protocol (P3 3L)

Layout-independent hot keys (design P3 §14.4, D30): a terminal with the
**kitty keyboard protocol** reports Alt / Ctrl chords with the base-layout key,
so Alt+F is `kbAltF` whatever the layout ([fv.keyboard](../fv.keyboard/README.md#layout-independent-keys-p3-3l)).
`FV_KBD_PROTO` (environment, read by `initVideo`):

| value | `initVideo` sends (right after `?1049h`: the protocol keeps one flag stack per screen) | later |
|---|---|---|
| `auto` (default, also empty) | the query `CSI ? u` and DA1 `CSI c`; **nothing waits for a reply** (no timed read of the terminal: D13) | fv.keyboard decodes `CSI ? N u` as a reply, not a key, and runs `fv.video._kpush`: the push `CSI > 5 u` (flags 1 disambiguate + 4 alternate keys), once. A terminal without the protocol answers DA1 only: nothing is pushed, no unknown sequence goes to it |
| `kitty` | the push `CSI > 5 u` at once | — |
| `off` | nothing | — |
| anything else | as `auto`, one debug line | |

**Every exit path pops `CSI < u` only when pushed** — `doneVideo`, `exit`
without it (the EXIT trap), INT / TERM / HUP — first in the restore, while the
alternate screen is still on (a pop after `?1049l` would hit the main screen's
stack). A reply that arrives late (after the restore) or is read in a subshell
pushes nothing; a second reply pushes nothing more. The restore's drain drops a
reply still on its way. Keys typed before the reply arrive in the legacy form
and work through fv.keyboard's layout tables. `initVideo` resets fv.keyboard's
reply state (`__FV_KB_KITTY`, `__FV_KB_DA1`), sets its hook
`__FV_KB_ONKITTY` and `__FV_KB_ISIG=1`; the restore clears both (internal
state shared by the two units, like `FV_KEY_FD`). Which terminals answer:
fv.keyboard README (to be confirmed in a live check).

**Ctrl+C stays the interrupt under the protocol.** With the flags pushed the
terminal sends Ctrl+C as `CSI 99;5u`, no 0x03, so the tty raises no SIGINT.
While `__FV_KB_ISIG` is 1, fv.keyboard's readers answer no key for that report
and raise SIGINT with `kill -INT 0` — to the process group, as the tty sends
it to the foreground process group for 0x03 — so the INT row of the exit
table below applies unchanged (the pop, the restore, status 130); the reader
process and its watchdog ignore INT as for a typed Ctrl+C. After the restore
the report is the key `kbCtrlC`. The same holds with `FV_KBD_PROTO=off` or
`kitty`.

## Cursor shape, bracketed paste, OSC 52 (P3 3d)

Design P3 §2.5 / §4.5, rows 10.7–10.9:

* **The cursor shape (D27).** `updateScreen` sends DECSCUSR when the shape it
  last sent differs: type 1 (FV `crUnderLine`, an input line inserting) →
  `ESC [ 4 SP q` (steady underline), types 2 and 3 (`crBlock`,
  `crHalfBlock`: overwriting) → `ESC [ 2 SP q` (steady block). A forced frame,
  a new screen (`initScreen`), a failed write and the restore forget the
  shape sent, so the next shown cursor sends it again. Every exit path (the
  table below) sends `ESC [ 0 SP q` when a shape was sent since `initVideo`:
  **the terminal's default shape** (its configured cursor) for the rest of
  the session — not a shape the user's shell had set before (reading the
  current shape needs DECRQSS and a reply that many terminals do not give;
  shells that set a shape per prompt set it again). Terminals without
  DECSCUSR ignore it (the Linux text console keeps its shape).
* **Bracketed paste (D24).** `initVideo` sends `ESC [ ? 2004 h`, every exit
  path `ESC [ ? 2004 l`. A paste then arrives framed `ESC [ 200 ~ … ESC [ 201
  ~`, which fv.keyboard decodes into one key `kbPaste` and fv.drivers into
  one `evCommand cmPasteText` (the text in `FV_EV_INFO`): a pasted newline
  never presses a dialog's default button. A terminal without bracketed
  paste types the text as keys (a newline is then Enter).
* **`fv.video.setClipboard TEXT`** sends OSC 52 — `ESC ] 52 ; c ; BASE64 BEL`,
  FPC fvclip.inc's form — at once to `FV_VIDEO_OUT_FD`, else `FV_TTY_FD`;
  TEXT's bytes in base64 (pure bash, RFC 4648 with padding; at most
  `FV_PASTE_MAX` bytes, default 65536 — a longer TEXT is cut there, an
  incomplete UTF-8 sequence at the cut dropped; linear: 64 KiB in about
  0.6 s on Git-bash). Windows
  Terminal, mintty, kitty, WezTerm, foot, iTerm2 and VS Code take it (some
  ask once); xterm only with `allowWindowOps` / `disallowedWindowOps`
  changed; VTE (GNOME Terminal) ignores it; tmux passes it with
  `set-clipboard on`. rc 1 with no output fd (nothing sent), rc 2 for a
  wrong count; `RESULT=''`; fork-free. fv.dialogs' input line calls it for
  every copy and cut.

## Exit paths and traps

`initVideo` saves the caller's EXIT, INT, TERM, HUP and WINCH traps (`trap -p`,
one fork each) and installs its own; `doneVideo` puts the caller's back exactly
as they were. **Set your traps before `initVideo`**: a trap set afterwards
replaces the unit's (then call `doneVideo` from it).

| Exit | What happens |
|---|---|
| `doneVideo` | restore; the caller's traps are back, so the caller's EXIT handler runs at exit as usual |
| `exit N`, a `set -e` failure, a fatal error (`${X:?}`) | EXIT trap: restore, then the caller's EXIT handler **once**, seeing `$?` = N; status N |
| INT (Ctrl+C), TERM, HUP | restore → the caller's handler for that signal, if any → the caller's EXIT handler once → `trap - SIG; kill -SIG $BASHPID`: the process dies of the signal (status 130 / 143 / 129). **If the caller's handler exits, that exit wins** (the caller's EXIT handler still runs once). A signal the caller ignores (`trap '' SIG`) stays ignored |
| WINCH | `FV_VIDEO_RESIZED=1`, then the caller's WINCH handler; nothing else (no fork, no output) |

The caller's handlers run with no positional parameters and with the `$?` they
would have seen without the unit. Under `set -e` (and `set -E` with an ERR
trap) a handler that ends in a false `a && b` is no error, as in a plain trap;
a real failure inside it and its own `exit` still act as in plain bash (bash
5.2 then prints a harmless `pop_var_context` warning while unwinding; 5.3 does
not).

**Only the traps active in this process are chained.** In a subshell bash still
shows the parent's trap texts (inactive there) until the subshell's first
`trap` command; `initVideo` first re-sets an unused signal (SYS, else XFSZ,
VTALRM, PROF, URG) to what it is, which drops those texts, so a parent's EXIT
handler never runs inside a subshell's TUI. **Run the event loop in the shell
that called `initVideo`:** in `… | while fv.drivers.getEvent` the loop is a
subshell whose traps are reset — no resize events there, and a SIGTERM waits
for the loop to end. Feed a loop with `while …; done < <(…)` instead.

**The restore is safe against a signal in its middle:** it marks itself done
only after its `stty`, so a signal arriving during it restores again (twice is
harmless, the fd is closed once).

**The drain:** after mouse reporting goes off, input already on its way (mouse
reports, keys typed during the exit) is read and dropped until 0.05 s pass
without a byte, at most ~0.3 s or 64 KiB, fork-free (from the terminal, or
with [the reader](#the-reader-process-git-bash-msys2-cygwin) through its pipe) — so it never lands on the
shell prompt after the program. It costs one idle wait (~0.05 s, ~0.06 s on
Windows) per restore. Nothing is drained at init. `kill` uses `$BASHPID`, so a TUI running
inside `x=$(…)` kills its own subshell, not the script around it. A trapped
signal does not interrupt bash's `read`, so the event loop must read with a
timeout (`fv.drivers.getEvent` always does); SIGTERM during an idle loop ends
the process in ~0.1 s (the read timeout plus the drain).

## The reader process (Git-bash, MSYS2, Cygwin)

**Why.** Under ConPTY (Windows Terminal, the classic console) a Cygwin-based
bash that does a timed `read -t` on the terminal can hang for good when the
window is resized. It was first seen with a `WINCH` trap (4 of 7 runs, Git-bash
5.3.15); the live check of 2026-11-10 showed it also hangs in a process that
**ignores** `WINCH` (a timed reader hung in 5 of 5 runs under 30 rapid
resizes in Windows Terminal). A hung process ignores even `kill -9` from its
own runtime. The event loop needs timed reads for the idle timeout, so on
these runtimes **no timed read ever touches the terminal** (decision D13 and
its amendment): a reader blocks on the terminal, and the timed reads happen on
pipes. With that design the same check ran clean: 5 of 5 in Windows Terminal,
3 of 3 in the classic console, every `WINCH` delivered.

**When.** `initVideo` starts the **reader** and its **watchdog** when
`FV_TTY_READER` says so, decided at each `initVideo`:

| `FV_TTY_READER` | reader |
|---|---|
| empty or unset (default) | auto: on where `OSTYPE` is `msys*` or `cygwin*` (Git-bash, MSYS2, Cygwin); off on Linux, macOS, BSD |
| `1` | on, on any system |
| `0` | off: the terminal is read directly, as on Linux |
| anything else | one debug line, then auto |

**How.** Two bash processes, process substitutions started right after raw
mode is set, in the process that owns the TUI:

* the **reader** reads the terminal **one byte at a time with blocking
  reads** (never `read -t`) and forwards each byte at once with its own
  `printf` (a NUL as a NUL), so nothing is buffered or delayed. `FV_KEY_FD`
  is the read end of its pipe; [fv.keyboard](../fv.keyboard/README.md) reads
  it as before (same API; the Esc timeout and the "byte already waiting" fast
  path behave the same on a pipe). Output still goes to `FV_TTY_FD`;
* the **watchdog** never touches the terminal: it does timed reads (every
  `__FV_VI_POLL` s, default 0.5) on a pipe whose write end only the owner
  holds, and checks that the owner still runs. End of file on that pipe (the
  owner died), any data on it, or the owner gone → it stops the reader
  (`KILL`, then `taskkill`; only while that pid still runs and its parent is
  the owner, or 1 once the owner is gone) and exits. If the reader ends by
  itself, the watchdog exits without a signal. A blocked reader cannot notice
  anything by itself; the watchdog is what ends it when the owner is killed.
  There is never a reader without a watchdog.

**What the caller sees while the TUI is on:**

* **two extra processes**, children of the shell that called `initVideo`;
* `FV_KEY_FD` is a pipe, not a terminal (`[[ -t $FV_KEY_FD ]]` is false);
  `FV_TTY_FD` is the terminal for output and `stty`. **Never read
  `FV_TTY_FD` yourself:** the reader takes every byte that arrives there. A
  cursor-position reply (`ESC [ 6 n`) arrives on `FV_KEY_FD`;
* **`$!` changes** at `initVideo` (it is the watchdog's pid);
* **a bare `wait` never returns while the TUI is on** — bash also waits for
  its last process substitution, which ends only at the restore: a deadlock
  (`wait -n` with no other child likewise). Wait for your own jobs by pid;
* the programs the TUI starts inherit the read end of the reader's pipe and
  the write end of the watchdog's (bash sets no close-on-exec on them); the
  reader keeps only fds 0, 1, 2 and the terminal, the watchdog only its pipe
  (stdout and stderr go to `/dev/null`) — bash's own fd 255 too, unless it is
  the terminal (an interactive shell), which both close — so a pipe or coproc
  fd the caller closes still reaches its end of file;
* `exec` of another program while the TUI is on is **unsupported**: the pid
  lives on, so the watchdog would not notice that its owner is gone.

**Lifecycle and signals.**

* **Stop:** the restore (`doneVideo`, the EXIT trap, INT / TERM / HUP — every
  exit path of [the table above](#exit-paths-and-traps)) first drains the
  input still on its way **through the reader's pipe** (the same quiet-period
  rule as the drain below; the shell never does a timed read of the
  terminal — not even when a signal re-enters the restore in the middle of
  the stop), then, before the `stty`, stops the reader — `SIGTERM` and up to
  0.1 s, then `SIGKILL` (a `TERM` ignored when the shell started stays
  ignored: bash cannot reset it) and up to 1 s, then, where
  `/proc/PID/winpid` exists, `taskkill` on the Windows side and 0.5 s more —
  and then kills the watchdog outright (`SIGKILL` + `wait`: it only ever reads
  a pipe, so that always works; no spin, no `/proc` needed). An exited reader
  is recognised by `/proc/PID/stat` (a zombie: inside a trap handler bash
  reaps no child, so `kill -0` would still find it) or the end of file on its
  pipe, and reaped with `wait`. A process that no longer runs is only reaped;
  one whose parent (from `/proc/PID/ppid`, else `/proc/PID/stat`) is not this
  shell is no longer ours: no signal. A signal that re-enters the restore
  during the stop runs the whole stop itself first. One debug line if the
  reader still lives (the terminal fd is then left open, never closed under a
  live reader). Both pipes are closed. The stop takes ~70–95 ms on Windows (a
  blocking read is interrupted in ~25 ms there), ~190–240 ms with `TERM`
  ignored at shell start, the same when a background child of the owner
  holds the watchdog's pipe.
* **Signals:** both ignore `INT` (Ctrl+C goes to the whole foreground process
  group: the owner restores the terminal and then stops them), `QUIT`, `TSTP`
  and `WINCH`; `HUP`, `TERM` and `PIPE` kill them (unless the shell started
  with them ignored; the stop then uses `KILL`). If the reader dies early (a
  hung-up terminal, a stray `kill`), its pipe reaches end of file and
  `fv.drivers.getEvent` answers end of input (rc 1, `FV_EV_EOF=1`), as a
  hung-up terminal does without a reader, and the watchdog exits by itself
  within one interval. If the watchdog dies alone, the reader goes on and the
  restore still stops it.
* **The owner dies without a restore** (`kill -9`): its end of the watchdog's
  pipe closes, the watchdog stops the blocked reader and exits — both gone
  within ~0.1–0.2 s, no key needed. When a child of the owner still holds
  that pipe (no end of file), the watchdog's owner check acts within one
  interval: gone within ~0.6 s. One window remains: a `SIGKILL` to the owner
  between the two forks of `initVideo` leaves a reader without a watchdog; it
  ends at the next byte (its write fails).
* **A subshell** of the owner (`x=$(…)`, `( … )`) inherits the state, not the
  ownership: its `initVideo` / `doneVideo` and its exit leave both alone. A
  re-init (`doneVideo` → `initVideo`) starts a new pair.
* **No reader or no watchdog starts** (no new numeric `$!`, or the process is
  already gone): whatever started is killed (`SIGKILL`) and reaped, and the
  terminal is read directly, with one debug line; rc 0.

**The poll interval** is the internal `__FV_VI_POLL` (seconds, default `0.5`;
empty also means 0.5; anything that is not a positive number: one debug line,
0.5): the watchdog's timed read on its pipe, and the reader's owner check
between bytes. A shorter interval ends an orphan sooner when a child holds the
watchdog's pipe; the idle cost is one wake-up of the watchdog per interval.

## Screen buffer

FPC Video's `VideoBuf` + `UpdateScreen`, with FV `TDrawBuffer` writes. The
program writes into the buffer; `updateScreen` sends the terminal only what
changed. It works headless (no `initVideo`, frames to any fd), which is how
the tests check it.

```bash
FV_SCREEN_W=40 FV_SCREEN_H=10 fv.video.initScreen      # or after initVideo: its size
exec {out}>frame.txt; FV_VIDEO_OUT_FD=$out             # headless; with initVideo: FV_TTY_FD
fv.video.fillRect 0 0 40 10 1 '░'                      # desktop
fv.video.writeStr 5 2 '╔══ Hello ══╗' 9
fv.video.writeCStr 7 4 '~F~ile  ~E~dit' 8 C            # ~ switches between the two attributes
fv.video.setCursorPos 7 4; fv.video.setCursorType 2
fv.video.updateScreen                                  # one printf; again: only the changes
```

### Model

* **One row = a character string + an attribute string of equal length in
  cells.** An attribute is one symbol of `[0-9A-Za-z]` (62) that indexes the
  palette, as FV's `GetColor` does. 62 symbols are enough for v1; revisit if
  P2 palettes need more.
* **Coordinates are 0-based**, X a column, Y a row. Every write is clipped to
  the screen and to the clip rectangle.
* **Damage:** each write records the leftmost and rightmost cell it wrote per
  row. **The shown copy:** per row, what the terminal shows. A damaged row
  equal to its copy sends nothing; otherwise its damaged columns are sent.
  Allocation, `resizeScreen`, `force`, `setColorDepth` and a palette change
  forget the copy of the rows they affect.
* **A frame** = per sent row one cursor move (CUP), then colour runs: an SGR
  only where the look changes (two symbols with the same colours share one;
  the SGR state is unknown at the start of every frame), then the cursor.
  **One `printf` per frame**; nothing at all when nothing changed.
* **One bash character per display cell**, on every runtime — see
  [wide characters](#wide-characters-emoji-and-clusters) for the second
  half of a wide character (`\x01`) and the marker cell (`\x02`).
* **Re-init:** `initVideo` clears the screen, so after it (also after a
  `doneVideo` → `initVideo` shell-out) the next `updateScreen` repaints
  every cell and re-sends the cursor state, as FPC does with a fresh
  `OldVideoBuf`. `doneVideo` does the same.

### API

Every write sets `RESULT` to the display cells it advances along its row (the
unclipped width, so the next write goes at X+RESULT; `writeBuf` with a repeat
count too, whatever H). Bad arguments: rc 2, `RESULT=''`, nothing written, one
debug line. Before `initScreen`: rc 1. Coordinates and sizes are integers of
1–7 digits, an optional `-` and leading zeros (decimal) allowed; anything else
is a bad argument.

| Function | FPC / FV | Answer |
|---|---|---|
| `fv.video.initScreen` | `InitVideo` (buffer part) | allocates `FV_SCREEN_W` × `FV_SCREEN_H` blanks (a bad size: 80 × 24; W at most 1024, FV's `FVMaxWidth`) in the default symbol `0`; the default palette; the colour depth (below); the ASCII-mode decision; the clip reset; the cursor hidden at 0,0; everything damaged. Usable without `initVideo`. Call it again after `initVideo` to detect the depth. **It resets the palette, the clip, the cursor and the contents**: a palette defined before `initScreen` is lost (define it after); `detectColorDepth` changes only the depth and keeps all of them |
| `fv.video.resizeScreen` | — | after `updateSize` / on `cmResizeApp`: reallocates at the new size, clears, resets the clip, damages everything; palette, depth, cursor kept (`updateSize` itself does not reallocate) |
| `fv.video.writeStr X Y TEXT ATTR` | `MoveStr` + `WriteLine` | TEXT in the symbol ATTR; RESULT = its display width |
| `fv.video.writeChar X Y CH ATTR [COUNT]` | `MoveChar` | the first character of CH — its first cluster (`''` = blank) — COUNT times (default 1); RESULT = its width × COUNT |
| `fv.video.writeBuf X Y TEXT ATTRS [H]` | `MoveBuf` + `WriteLine(X, Y, W, H, Buf)` | one symbol per display cell; ATTRS as long as TEXT's display width, else rc 2; the symbol under the second half of a wide character is replaced by its first half's. H (default 1; `''` = 1): the same row on rows Y … Y+H−1, each clipped like a single write (rows outside the clip cost nothing); H 0 writes nothing; H not an integer ≥ 0: rc 2, nothing written. RESULT = TEXT's display width for any H. H 1 or omitted is exactly the one-row write |
| `fv.video.writeCStr X Y TEXT ATTR1 ATTR2` | `MoveCStr` | each `~` switches between ATTR1 and ATTR2, takes no cell and splits no cluster (a mark after it joins the cell before it); a cell takes the symbol of its base character |
| `fv.video.fillRect X Y W H ATTR [CH]` | — | the rectangle filled with the first cluster of CH (default blank); a wide CH fills whole pairs and a space when W is odd; RESULT = W (0 when negative) |
| `fv.video.fillColumns Y H ATTR CH X [X …]` | — | the columns X (one cell wide each) on the rows Y … Y+H−1 filled with the first cluster of CH (`''` a blank) in ATTR, clipped: the same cells, damage and wide-character rules as one `fillRect X Y 1 H ATTR CH` per column (a wide CH leaves a space in a one-cell column), in one call — a frame's two sides (stage 2c-p). Columns in any order, a column given twice is filled once. RESULT = 1 (the cells a column advances, as fillRect's W 1) |
| `fv.video.shadeRect X Y W H [ATTR]` | FV shadows (`sfShadow`, `ShadowAttr`) | attribute only: the cells of the rectangle keep their characters (wide halves, markers and the side map untouched) and take the symbol ATTR, default `V`, the [reserved shadow symbol](#palette-and-colour-depth-d10) (FV `ShadowAttr` $08, dark grey on black). Clipped like a write. **A wide character of which the clipped rectangle covers only one half is shaded whole**, also its half outside the rectangle or the clip (a terminal draws a wide character in its first half's colours; the buffer keeps both halves alike). The damage covers the shaded cells (widened pairs included). RESULT = W (0 when negative) |
| `fv.video.clearScreen [ATTR]` | `ClearScreen` | the whole screen blank in ATTR (default `0`), **whatever the clip**; nothing is sent until `updateScreen` (FPC's ClearScreen updates at once) |
| `fv.video.setClip X1 Y1 X2 Y2` | `TRect` | writes go only into [X1,X2) × [Y1,Y2), intersected with the screen; an empty rectangle writes nothing; reallocation resets it |
| `fv.video.resetClip` | — | the clip = the whole screen |
| `fv.video.getClip` | — | `RESULT="X1 Y1 X2 Y2"`, the clip in `setClip`'s form, as it stands (already intersected with the screen; after `resetClip` / allocation `0 0 W H`), so that a caller can save and restore it: `fv.video.getClip; saved=$RESULT; …; IFS=' ' read -r a b c d <<< "$saved"; fv.video.setClip "$a" "$b" "$c" "$d"`. Any argument: rc 2. Reads four integers, so it has no locale or option guard (the cheapest call of the unit) |
| `fv.video.getRow Y` | — | read-only. `RESULT` = row Y as display text: each cell's character, a [marker](#wide-characters-emoji-and-clusters)'s content from the side map, the continuation half of a wide character dropped (so a row of CJK text has fewer characters than cells; `strWidth "$RESULT"` gives W). `REPLY` = the row's symbols, one per cell (`${#REPLY}` = W, both halves of a wide character). Y 0 … H−1 (plain digits, no sign, no leading zero), one argument, else rc 2 with `RESULT` and `REPLY` `''`. For tests, captures and P2's buffer reader; it changes nothing (cells, symbols, damage, side map) |
| `fv.video.setCursorPos X Y` | `SetCursorPos` | where the cursor stands after the next update (clamped to the screen there); X, Y ≥ 0 |
| `fv.video.setCursorType 0..3` | `SetCursorType` | `crHidden` 0 → `ESC[?25l`; `crUnderLine`, `crBlock`, `crHalfBlock` 1–3 → `ESC[?25h` and the shape by DECSCUSR when it changed: 1 underline `ESC[4 q`, 2 and 3 block `ESC[2 q` (P3 10.7, [above](#cursor-shape-bracketed-paste-osc-52-p3-3d)) |
| `fv.video.setClipboard TEXT` | (FPC fvclip.inc) | OSC 52 to the system clipboard ([above](#cursor-shape-bracketed-paste-osc-52-p3-3d)) |
| `fv.video.updateScreen [force]` | `UpdateScreen(Force)` | the frame (above) to `FV_VIDEO_OUT_FD`, else `FV_TTY_FD`. The cursor: when visible, its position after any text or when it moved; `?25h`/`?25l` only on a change. `force`: every cell of every row (no `ESC[2J`) and the cursor state re-sent. rc 1: no fd (nothing sent, the damage kept), or the `printf` failed (the next frame is forced) |
| `fv.video.strWidth TEXT` | `StringDisplayWidth` | RESULT = the display cells TEXT takes as a write stores it (wide characters 2, a cluster its base's width, a control or invalid sequence 1 as its `?`) |
| `fv.video.clusters TEXT CL CW` | — (P3 10.1, for TInputLine's cluster model) | TEXT cut into clusters exactly where the writes cut it into cells: the indexed array named CL gets the cluster strings, the one named CW their cells (1 or 2); RESULT = the count; both arrays replaced (an empty TEXT: two empty arrays, RESULT 0). UTF-8 mode: a cluster is one cell's content — a character, a wide character, a base with its zero-width followers, a ZWJ sequence, a flag, a VS16 emoji (D14), a character past U+FFFF; valid TEXT without control characters comes back whole (CL joined = TEXT; a zero-width character at TEXT's start is its own cluster, without the space the screen shows before it); a control character or an invalid sequence is the cluster `?` (as stored). ASCII mode: every character — one UTF-8 sequence as the writes count them, or one byte below 0x80 — is one cluster of one cell holding TEXT's own bytes (the screen shows `?` or the map's letter). Printable ASCII takes a fast path (no text check); no screen needed (the mode of the load or the last `initScreen`). Bad names (no identifier, `__fv*`, `RESULT`, CL = CW, an associative array) or another argument count: rc 2, RESULT `''`, the arrays untouched |
| `fv.video.definePalette SYM FG BG [BOLD]` | palette entry | SYM one symbol, FG / BG 0–255, BOLD 0 / 1 (default 0). A change of a symbol in use repaints the rows holding it (the default symbol: every row) |
| `fv.video.setColorDepth 16\|256` | — | rebuilds every symbol's SGR and repaints everything |
| `fv.video.detectColorDepth` | — | the detection below on demand, applied like `setColorDepth`; RESULT = 16 / 256 |

| Global | Meaning |
|---|---|
| `FV_VIDEO_OUT_FD` | *input*: the fd frames go to; wins over `FV_TTY_FD`; `''` by default |
| `FV_VIDEO_COLORS` | the colour depth in use, 16 or 256 |
| `FV_VIDEO_ASCII` | 1 in ASCII mode (below) |
| `FV_COLORS` | *input*: `16` or `256` overrides the detection (any other value: ignored, one debug line) |
| `FV_ASCII` | *input*: `1` forces ASCII mode (replaces the spike's `TUI_ASCII`); read by `initScreen` |

Internal state is `__FV_VS_*`.

### Palette and colour depth (D10)

* **An entry** maps a symbol to a foreground and a background index 0–255
  and an optional bold. Its SGR is precomputed whole: `ESC[0;38;5;FG;48;5;BGm`
  (with `1;` after the `0` for bold). Bold is SGR 1 only and never derived
  from a bright index.
* **16 colours:** every index maps to the nearest of xterm's 16 default
  colours (squared RGB distance; cube levels 0, 95, 135, 175, 215, 255; greys
  8 + 10k; ties to the lower index; 0–15 are themselves), memoised per index
  when `definePalette` first uses it. fg 0–7 → 30–37, 8–15 → 90–97; bg 0–7 →
  40–47, 8–15 → 100–107.
* **An undefined symbol** shows as the default symbol `0`.
* **The default palette** (`initScreen`): FV's classic colours as ANSI
  indices. Symbol `0` is FPC's `DefaultAttr` $07; `1`–`9`, `A`–`U` are the 30
  distinct attribute bytes of FV's `CAppColor` (app.inc) in order of first
  appearance; `V` is FV's `ShadowAttr` $08 (below). FV bytes are $BF (B =
  background, F = foreground) in DOS colour order, mapped to ANSI with 0 4 2
  6 1 5 3 7 8 12 10 14 9 13 11 15:

  | sym | byte | sym | byte | sym | byte | sym | byte |
  |---|---|---|---|---|---|---|---|
  | `0` | $07 | `8` | $17 | `G` | $13 | `O` | $2E |
  | `1` | $71 | `9` | $1F | `H` | $3E | `P` | $30 |
  | `2` | $70 | `A` | $1A | `I` | $21 | `Q` | $72 |
  | `3` | $78 | `B` | $31 | `J` | $7F | `R` | $38 |
  | `4` | $74 | `C` | $1E | `K` | $7A | `S` | $10 |
  | `5` | $20 | `D` | $37 | `L` | $7E | `T` | $12 |
  | `6` | $28 | `E` | $3F | `M` | $2B | `U` | $32 |
  | `7` | $24 | `F` | $3A | `N` | $2F | `V` | $08 |

* **The reserved shadow symbol `V`** (P2): FV's `ShadowAttr` $08, dark grey
  (8) on black (0) — the next byte "in order of first appearance" after
  CAppColor's 30. `shadeRect` uses it by default. It is part of the default
  palette, so `definePalette V …` re-themes every shadow; P2's app palette
  never allocates it (the free symbols are `W`–`Z`, `a`–`z`).
* **Kept per process** (decision D18): the first `initScreen` at a colour
  depth builds the default palette (32 entries, their SGR strings) and keeps
  a copy; a later `initScreen` at that depth takes the copy (~0.1 ms instead
  of ~2.5 ms). The copy is the default palette only, taken before any
  `definePalette`, so a palette changed later never leaks into the next
  `initScreen`; `setColorDepth` rebuilds every SGR as before (the 16-colour
  map is filled on demand). The first `initScreen` of a process pays the
  full build. Loading the unit empties the copy, so it never comes from the
  environment (an exported or `set -a` value) or an earlier load.

* **The depth:** `FV_COLORS` when it is 16 or 256. Otherwise headless
  `initScreen` takes 256 without asking anything; with the terminal on
  (`initScreen` after `initVideo`, or `detectColorDepth`): `TERM` matching
  `*256color*` or `COLORTERM` set → 256 (no fork); `TERM=linux` → 16; else one
  `tput colors` fork: ≥ 256 → 256 (any length, e.g. xterm-direct's
  16777216), anything else, a failure or no `tput` → 16.

### Text, locale and ASCII mode (D11)

* **Control characters:** every C0, DEL and C1 character in written text is
  stored as `?`.
* **Invalid UTF-8:** every invalid or cut sequence (a lone `\xff`, `e2 94`
  without its last byte, a stray `0x9b`, an overlong `c0 80`, a surrogate
  `ed a0 80`, anything above U+10FFFF) is stored as **one** `?`; valid 2-, 3-
  and 4-byte sequences stay. The check runs on bytes in the C locale (no
  collation, no platform `mbrtowc` quirk) and only for text with a non-ASCII
  byte: valid text is confirmed by removing its valid sequences with pattern
  substitutions (the common 2- and 3-byte forms first); only text that still
  has a non-ASCII byte takes the byte-by-byte pass. Results — the cells, see
  below — are cached (at most 512 texts; `initScreen` empties the cache).
* **Locale:** every entry point needs UTF-8 character semantics. Each call
  first tests the caller's locale: two probes, a 2-byte (`ж`) and a 3-byte
  (`─`) character, must each count as one character (legacy CJK locales —
  eucJP, GBK, Big5, eucKR — pass the first alone). Only when it is not UTF-8
  does the call run with `local LC_ALL=` a UTF-8 locale found once at load:
  the caller's own locale name if it is UTF-8, then `C.UTF-8`, `C.utf8`,
  `en_US.UTF-8`, `en_US.utf8` (silent probes). The caller's locale is
  unchanged after every call (for setups bash cannot restore see L-1
  below). When no locale variable is set at all, loading exports
  `LC_CTYPE=C.UTF-8`, the kcl-wide convention (kcl README §1.6).
* **A caller locale bash cannot restore** (L-1): when a `local LC_ALL`
  ends, bash sets the caller's `LC_ALL` again or, when it is empty, does
  `setlocale(LC_ALL, LANG or "")` before the `LC_*` variables; when that
  fails (`LANG` or `LC_ALL` naming an uninstalled locale, or with `LANG`
  empty any exported `LC_*` that does, even when `LC_CTYPE` works) the
  locale of the scope just left stays. The unit models no names: after each
  such scope that can be the outermost one it compares the caller's probe
  with the one taken before, and on a difference sets the caller's locale
  (C, or the UTF-8 one) in a scope whose restore fails the same way, so that
  it stays. The calls of such a caller give what a C caller gets, and its
  locale (variables, export attributes, character handling) is the same
  after every call and after the load. A non-empty `LC_ALL` is checked once
  per value (cached) and, when rejected, swapped and put back by hand, so
  bash's warning about restoring it stays off the caller's stderr; a shell
  left in UTF-8 under such an `LC_ALL` (by assigning it over a UTF-8 one,
  and on macOS also by starting with it) runs the byte scopes of a
  text-cache miss with stderr off for the same reason. Only the paths
  that change the locale check anything (a non-UTF-8 caller's call, a
  text-cache miss, the load, the restore); a cached or ASCII write checks
  nothing. Name compares are case-sensitive whatever `nocasematch` says.
  Limits (all three behave the same before L-1; character widths and cells
  stay right in each): the repair restores a whole locale, C or the UTF-8
  one, so in such a broken setup (a) a caller that assigned a valid
  single-byte `LC_CTYPE` (Latin-1, a legacy CJK charset) in the shell ends
  up in C, (b) categories other than `LC_CTYPE` that the caller set in the
  shell (`LC_NUMERIC`, `LC_COLLATE`, `LC_TIME`) end up as C or the UTF-8
  locale, and (c) with `LANG` a valid UTF-8 locale and `LC_CTYPE` assigned an
  uninstalled name in the shell, the caller stays in UTF-8 after the load
  (bash's own restore applies `LANG` and then fails, so no restore can put
  it back to C).
* **The mode is decided per screen, never per call** (`initScreen`, and
  once at load): UTF-8 mode needs a named UTF-8 locale for the calls of a
  non-UTF-8 caller, so when the load found none but `initScreen` runs in a
  UTF-8 locale, that locale's name is taken; with no name at all the screen
  is in ASCII mode. A call can thus never store (and cache) a text in the
  other mode's form.
* **ASCII mode** (`FV_VIDEO_ASCII=1`): when no UTF-8 locale exists, or with
  `FV_ASCII=1`. Calls then run in the C locale where needed, and every
  non-ASCII character — **one UTF-8 sequence, not one byte, one cell of width
  1, whatever its width elsewhere** — is stored as: box drawing horizontals
  `-` (double `=`), verticals `|`, corners and junctions `+`; `↑▲` `^`, `↓▼`
  `v`, `→►` `>`, `←◄` `<`, `■` `*`; anything else `?`. The width table is
  never consulted: `漢` is one `?`, `e` + U+0301 is `e?` (two cells), an
  emoji one `?`; `strWidth` counts the same cells. ASCII mode means "no
  Unicode knowledge": a terminal without a UTF-8 locale cannot show them.
* **Caller state:** every entry point (bar `getClip`, which only reads four
  integers) clears `nocasematch` and sets `globasciiranges` (the text
  checks are range globs, D21) for the call and puts both back on every
  return path; `failglob`, `nullglob`, `noglob`, `extglob`, `IFS` and
  `set -eu` change nothing (`tests/013`, also `globasciiranges` off under a
  collation that is not the code order). A caller IFS holding `\x01` —
  bash's internal quoting byte: such an IFS drops that byte from a pattern
  substitution over the wide cells and breaks `initScreen`'s palette
  arithmetic — sends the call through the same guard, which runs it under
  an empty IFS of its own (P3 3v-1 F4; `tests/025`). Every function with a bare fd redirect (`>&$fd`, the form
  bash 5.1 prints correctly) sets `local IFS=`, so a caller IFS holding
  digits cannot split the fd (`tests/015`, on a pty).
* **Platform notes (PORT-1):** an integer argument is checked against
  `[0123456789]`, never `[[:digit:]]`: on macOS and FreeBSD that class also
  matches other scripts' digits in a UTF-8 locale (`٣`, U+0663), which
  bash arithmetic rejects. The byte pass takes a byte's value as
  `printf %d "'B"` `& 255`: in musl's C locale (Alpine) that gives a byte
  ≥ 0x80 as 0xDF00 + the byte. musl takes every locale name as a UTF-8
  locale, so the candidates never fail there and L-1 does not arise; on
  macOS a shell started with `LC_ALL` naming a missing locale is already in
  UTF-8 (the case above, handled the same way).

### Wide characters, emoji and clusters

Decisions D5 (P1b), D14 (VS16) and D15 (the frame's resync, P1c).
Widths and cluster roles come from [`fv.unicode`](../fv.unicode/README.md)
(Unicode 16.0.0, the glibc 2.41 width rules).

* **The cells.** A write turns its text into cells, one bash character per
  display cell, so substring arithmetic stays the same on every runtime:
  * a narrow character is its cell;
  * a **wide** character (CJK, fullwidth forms, …) is its character + the
    continuation `\x01` in the next cell;
  * a cell whose content is not exactly one BMP character is a **marker**:
    `\x02` in the row (+ `\x01` when wide) and its content in the side map
    `__FV_VS_X["Y X"]`. That is every cluster (a base + marks), every orphan
    zero-width character, **every character past U+FFFF on every runtime**
    — Cygwin-based bash holds such a character as two bash characters, which
    a substring can cut into 3 + 1 bytes, so it never enters a row string —
    and every class-y character (wide Extended_Pictographic, e.g. `⌚`), so
    that the frame pre-blanks it.
  * `\x01`, `\x02` (and the list separator `\x1f`) are control characters: a
    caller's text can never store them (they become `?`).
* **Clusters** (small, not full UAX #29): a cell is a base character plus
  * every following zero-width character (marks, ZWJ, variation selectors,
    tags, Hangul V/T jamo after an L jamo);
  * VS16 U+FE0F turns an Extended_Pictographic narrow base (`©` `❤` `☺`) or a
    keycap base (`0`–`9` `#` `*`) **2 wide** (decision D14; `1️⃣` is 2 wide);
    after any other base (a letter) it changes nothing, and VS15 never does;
  * an emoji modifier (`🏽`) after an Extended_Pictographic base (`👍🏽`, 2
    wide); after any other base the modifier is a cell of its own (2 wide);
  * after a ZWJ, the next character when both it and the cell's base are
    Extended_Pictographic (`👨‍👩‍👧` is one cell, 2 wide);
  * regional indicators pair from the left into a flag (`🇩🇪`, 2 wide); a
    lone one is 1 wide;
  * a zero-width character with no cell before it **in the same write** is
    an orphan: a cell of its own, a space + it, 1 wide (a mark written by a
    later call next to an `e` never joins it).
  A cluster's width is its base's unless a rule above says otherwise.
* **Edges** (as ncurses): a wide character of the text cut by the right
  screen edge or by the clip leaves a space (in the write's symbol) in its
  visible half; RESULT is still the unclipped width.
* **Half-overwrites:** a write that covers one half of a wide character in
  the row blanks the other half — a space in that half's old symbol — also
  when that half lies outside the clip (no half character can remain). The
  damage covers the blanked half, so a frame always sends whole characters.
* **Symbols:** both halves of a wide character have its first half's symbol
  (`writeBuf` replaces the symbol given for the second half; `writeCStr`
  gives a cell its base character's segment symbol).
* **Units** (`writeChar`, `fillRect`): the first cluster of CH; a wide unit
  fills whole pairs (`writeChar … 漢 … 3` writes 6 cells, RESULT 6;
  `fillRect` with an odd W ends in a space); a pair cut by the clip leaves a
  space in its visible half.
* **The cursor** on the second half of a wide character stays where it was
  set (FPC and ncurses do not move it); the terminal shows it there.
* **Rows and the shown copy:** `__FV_VS_WIDE[y]` = 1 when the row holds
  `\x01`, + 2 when it holds `\x02` (exact: rescanned after each write into
  such a row); rows at 0 take the P1a paths unchanged. `__FV_VS_WNEW[y]`
  = 1 once a write through the wide path put a wide character into row y
  (also one the clip cut or a later write covered, so the row may show
  none) or wrote into a row that held one; it stays until its reader
  clears it (fv.views, below); the narrow paths never touch it, and
  allocation empties it. A side-map change in
  a row bumps its version `__FV_VS_XV[y]`; `updateScreen` skips a row only
  when its characters, symbols **and** version equal the shown copy's
  (`__FV_VS_OXV`), so a cluster replaced by another one in the same cell is
  sent. Everything that forgets the shown copy forgets the versions too;
  `clearScreen`, `resizeScreen` and allocation empty the side map; every
  write removes the entries of the markers it overwrites (`tests/017` checks
  after every operation of a random mix that no entry is stale).
* **The frame** (decision D15): a plain character goes as itself, a marker
  sends its content, a `\x01` nothing (the terminal fills that cell with the
  wide character before it). Rows without wide cells are sent exactly as in
  P1a; in a row with them:
  * **resync:** after every wide cell and every marker cell (narrow clusters
    too) that another cell of the row's sent range follows, `ESC[nG` (CHA)
    puts the cursor in the column the buffer says (`__FV_VS_CHA[x]`, a
    string per column built with the screen), except right before a wide
    marker, whose pre-blank starts with such a move anyway (also across a
    colour change). After the range's last cell nothing is sent: the next
    row starts with its own cursor move, and the cursor's final place comes
    from the CUP that follows any text when the cursor is shown (a hidden
    cursor's place does not matter);
  * **after a narrow marker:** a damaged range that ends on a narrow marker
    also sends the cell after it (and that cell's second half): a terminal
    that draws the marker 2 wide (a newer width table, a lone regional
    indicator) covers that cell, which would otherwise never be sent again.
    A range that starts right after a narrow marker is not widened: in such
    a terminal writing the next cell erases the marker either way;
  * **pre-blank:** a **wide marker** — every 2-wide cluster (flags, keycaps,
    ZWJ sequences, modifier sequences, `©️` widened by VS16, a CJK character
    with a mark), every 2-wide character past U+FFFF (emoji) and every
    character of class y (wide Extended_Pictographic in the BMP, such as `⌚`,
    which the walk therefore always stores as a marker) — is sent as
    `ESC[x+2G`, a space (in the cell's colours), `ESC[x+1G`, the content, then
    the resync. Plain wide characters (CJK, fullwidth forms: widths terminals
    agree on) get the resync only;
  * **what a disagreeing terminal shows:** one that draws a wide marker
    narrow shows it in the first cell and a blank in the second (never stale
    text); one that draws a plain CJK character narrow shows it and leaves the
    second cell as it was; one that draws a narrow marker wide loses the
    marker to the cell after it; in every case every other cell of the row is
    right (`tests/018` replays such terminals, and fails with the resync
    turned off). Newly wide BMP symbols of Unicode 16 (`☰` U+2630–2637, `⚊`
    U+268A–268F, `䷀` U+4DC0–4DFF) are class w, plain wide characters: an
    older terminal that draws them narrow leaves their second cell as it was.
  `__FV_VS_RSYNC=0` (internal, for the tests) sends the row without resync
  and pre-blank.
* **The walk:** text that neither fast path (below) takes is walked character
  by character in the call's UTF-8 locale (one `printf %d` per new
  character, its class from `fv.unicode.charClass`, kept in a per-character
  cache of at most 4096 entries); on Cygwin-based bash a text holding
  characters past U+FFFF is walked on bytes in the C locale instead, because
  `printf %d` of half such a character leaves the conversion state broken for
  the next one. The cells and the marker list are cached with the text
  (`writeCStr` has caches of its own — cells, markers and the per-cell
  symbol string — so its texts never meet `writeStr`'s; all of them are
  emptied together when one is full and by `initScreen`).
* **The wide fast path** (P3 10.12): text the fast path below does not
  take, without a 4-byte sequence, whose every non-ASCII character is a
  **plain wide character** — CJK Unified + Extension A + Yijing
  U+3400–9FFF, Hiragana U+3041–3096 and U+309B–309F (not the combining
  U+3099–309A), Katakana U+30A0–30FF, CJK punctuation U+3000–3029, Hangul
  syllables U+AC00–D7A3, CJK compatibility ideographs U+F900–FAFF,
  fullwidth forms U+FF01–FF60 and U+FFE0–FFE6: the runs of class `w` in
  those blocks, each 2 wide and never joined to anything — gets its cells
  without the walk: the accepted sequences are removed pattern by pattern
  (C-locale byte patterns `__FV_VS_WB`, the common first) until no
  non-ASCII byte is left, then one substitution adds the continuation after
  each (`&`, bash ≥ 5.2 with `patsub_replacement` on; a loop on bash 5.1 or
  with the option off). A VS16, a ZWJ, a combining mark, a modifier or an
  emoji anywhere in the text refuses it, and the walk runs as before;
  `tests/022` checks every code point U+3000–U+FFFF against the runs and
  fv.unicode, `tests/023` the cells against the walk.
* **The fast path:** text whose bytes show only ASCII, Latin-1 (bar U+00AD),
  Latin extended, IPA, spacing modifiers, Greek, Cyrillic (bar the combining
  U+0483–0489), general punctuation (bar the zero-width, bidi and invisible
  controls), arrows, box drawing, blocks and geometric shapes (bar
  U+25FC–25FF) is all width-1 single characters and skips the table: seven
  C-locale byte patterns (`__FV_VS_FP`) after the validity check, on a cache
  miss only. `tests/017` checks that every code point the patterns accept has
  class n or x.

### Cost of the buffer

Every write and every `updateScreen` is fork-free (`tests/006`); the only
fork is `tput colors` in the depth detection. Git-bash 5.3.15, two-panel
scene (~10 colour runs per row, Cyrillic and box drawing), median of 5 × N
in one process (N = 10), frames to a file fd, 2026-11-09, the machine in use
(an unloaded run gave 9.4–9.9 ms at 80 × 24 and 24–26 ms at 200 × 50; MSYS2
5.3.9 within 5 %; an independent review run on a loaded machine gave
200 × 50 32 / 32 ms); `tests/014` checks 3× limits. The repaint time is the
colour-run loop (~25 cycles of slicing per run); the `printf` is ~1 %.

The text check (invalid UTF-8) per 80-character `writeStr`, Git-bash, median
µs, before → after: ASCII 133–149 → 138–143 (no change beyond noise);
Cyrillic + box drawing, the same text again (cached) 144–162 → 188–190;
every text new 153–169 → 227–260. `strWidth` ASCII 24 → 30.

| measure | 256 colours | 16 colours | plain `printf` of the frame |
|---|---|---|---|
| 80 × 24 full repaint (`force`) | 10.5 ms | 10.8 ms | 0.10 / 0.08 ms (8.5 / 5.6 K chars) |
| 80 × 24, 2 rows (2 `writeBuf` + update) | 0.65 ms | 0.63 ms | 0.02 ms |
| 80 × 24, 24 whole-row `writeBuf` (no update) | 3.8 ms | 3.6 ms | — |
| 200 × 50 full repaint (`force`) | 27.6 ms | 30.9 ms | 0.26 / 0.22 ms (24 / 18 K chars) |

**P1b (wide characters), A/B against P1a** (2026-11-11): the P1a unit from
git (`HEAD`) against the new one, the scene above, frames to `/dev/null`;
per process median of 5 × 10, rounds alternated A1 B A2 × 5, the table gives
the median over rounds; A2/A1 is the A/A spread. A process outside the tests
kept one core busy the whole time on the host (and the lab VM is noisy), so
spreads up to ±10–20 % appear; a direct one-process comparison on Cygwin
(7 × 2000 calls) put writeStr ASCII / Cyrillic cached / writeBuf at +2–4 %.

| measure (µs) | MSYS2 5.3.9 A → B (B/A; A/A) | Cygwin 5.2.21 | VM 5.2.37 | VM 5.1.16 |
|---|---|---|---|---|
| 80 × 24 full repaint | 10219 → 10393 (1.02; 1.03) | 10368 → 10500 (1.01; 1.01) | 12371 → 12830 (1.04; 0.99) | 13794 → 13903 (1.01; 1.04) |
| 80 × 24, 24 whole-row writeBuf | 4408 → 4421 (1.00; 0.98) | 4190 → 4501 (1.07; 1.03) | 6125 → 6458 (1.05; 1.06) | 6890 → 7145 (1.04; 1.02) |
| 80 × 24, 2 rows + update | 659 → 697 (1.06; 0.91) | 660 → 719 (1.09; 1.00) | 870 → 871 (1.00; 1.06) | 985 → 1089 (1.11; 0.90) |
| writeStr, 80 ASCII | 123 → 133 (1.09; 1.01) | 128 → 138 (1.07; 1.00) | 184 → 191 (1.04; 1.20) | 224 → 193 (0.86; 0.82) |
| writeStr, Cyrillic + box, cached | 152 → 162 (1.07; 1.02) | 154 → 166 (1.07; 0.96) | 271 → 314 (1.16; 1.14) | 303 → 259 (0.86; 0.97) |
| writeStr, Cyrillic + box, a new text each time | 216 → 236 (1.09; 0.91) | 208 → 244 (1.17; 1.00) | 365 → 422 (1.16; 1.01) | 306 → 412 (1.35; 0.94) |
| strWidth, 80 ASCII | 38 → 38 (1.02; 1.25) | 37 → 36 (0.97; 1.12) | 45 → 56 (1.25; 0.97) | 63 → 62 (0.99; 1.00) |
| 200 × 50 full repaint | 27094 → 26778 (0.99; 1.01) | 26973 → 27203 (1.01; 1.01) | 33280 → 34725 (1.04; 1.02) | 36843 → 36950 (1.00; 1.03) |

A new non-ASCII text pays the fast-path test (seven byte patterns, ~20–40 µs
per 40-character text) once; the cache then serves it.

Wide text (B only, µs per call; 80 × 24):

| measure | MSYS2 | Cygwin | VM 5.2 | VM 5.1 |
|---|---|---|---|---|
| writeStr, 40 CJK characters (+ 1 ASCII), cached | 268 | 272 | 467 | 464 |
| writeStr, 10 emoji / clusters (ZWJ family, flag, keycap, ❤️, 👍🏽), cached | 598 | 605 | 812 | 1047 |
| writeStr, 7 combining clusters + a Hangul L V T, cached | 523 | 739 | 792 | 868 |
| the same three, a new text each time (the walk) | 2570 / 3580 / 2695 | 3692 / 3785 / 2787 | 3520 / 3064 / 2687 | 3662 / 3589 / 2679 |
| full repaint, every row 20 CJK characters + 40 ASCII | 7398 | 7498 | 7882 | 8308 |
| full repaint, every row 20 emoji (markers) + 40 blanks | 16360 | 17702 | 15055 | 17096 |

A row of wide characters repaints faster than the scene (fewer colour runs);
a row of 20 emoji is ~1.6–1.7 × the scene's full repaint (each marker is a
side-map lookup), inside the 2 × limit of the plan. The walk costs ~60–90 µs
per new character (a `printf %d` and a table lookup, then cached per
character); a cached wide text costs about twice an ASCII one. (These
repaint times are P1b's, without the resync.)

**P1c, the resync** (2026-11-11). Bytes, counted: a CHA is `ESC[nG`, 4–6
bytes (n = the column); a pre-blanked wide marker costs a space and two CHA,
~11 bytes (no resync between two wide markers). An 80 × 24 full repaint
with 40 ASCII cells per row on the right:

| left half of every row | bytes with the resync | without | per row |
|---|---|---|---|
| 40 ASCII cells | 3329 | 3329 | +0 |
| 20 CJK characters | 6113 | 3809 | +96 (20 CHA) |
| 20 emoji (wide markers) | 9473 | 4289 | +216 (20 pre-blanks, 2 CHA) |

Time, the same full repaints (left half: 20 CJK, 20 emoji, or 10 × CJK +
emoji; right half 40 ASCII) against the P1a two-panel scene's full repaint;
median of 9 repaints per process, processes of P1b (`git show HEAD`) and
P1c alternated × 5, the median of those (on the host a process outside the
tests kept one core busy throughout):

| µs | Git-bash 5.3.15 | MSYS2 5.3.9 | VM bash 5.2.37 |
|---|---|---|---|
| two-panel scene (plain) | 9742 | 9843 | 16364 |
| CJK: P1b → P1c (P1c without resync) | 4423 → 10582 (6419) | 4506 → 10822 (6479) | 8647 → 17043 (11045) |
| emoji: P1b → P1c (without) | 11744 → 15948 (13054) | 11693 → 15258 (12827) | 17119 → 23535 (18857) |
| mixed: P1b → P1c (without) | 8930 → 14800 (10555) | 9002 → 14404 (10172) | 14191 → 21299 (14528) |
| P1c / scene: CJK, emoji, mixed | 1.09, 1.64, 1.52 | 1.10, 1.55, 1.46 | 1.04, 1.44, 1.30 |

The resync costs ~9–13 µs per wide cell (a CJK run takes one step per
character; a run with markers one per piece); the CJK frame stays within
1.5 × and the emoji frame within 1.8 × the plain repaint.

**P2 stage 2a, the entry and the writes** (2026-11-16). Where a short write
went: bash copies a function's body on every call and each simple command
costs ~2–3 µs on Windows, and an assignment inside `(( ))` costs more than a
separate `$(( ))`. So the coordinate check is inline (one `[[ ]]` for plain
digits; signs and leading zeros fall to the old `_xy`), the narrow text-cache
hit is inline, the rare cases of `_put` (outside the clip, wide cells, a fill
string not built yet, columns cut by the clip) share one test and live in
helpers, and `writeCStr`'s cache miss, `fillRect`'s wide-unit line and
`writeBuf`'s less common cases moved out of the hot bodies. Validation is
unchanged (the same arguments are rc 2, `tests/019`). A/B of the P1c unit
(`git show HEAD`, A) against this one (B): rounds A1 B A2 × 5, each a fresh
process, median of 5 × N per measure (N 10 for the scene, 400 for single
calls), frames to `/dev/null`; spread = the largest per-round A2/A1 − 1:

| µs | Git-bash 5.3.15 A → B (B/A; spread) | MSYS2 5.3.9 | Cygwin 5.2.21 |
|---|---|---|---|
| 80 × 24 full repaint | 9844 → 9704 (0.99; 0.06) | 9864 → 9836 (1.00; 0.04) | 10298 → 10131 (0.98; 0.07) |
| 80 × 24, 24 whole-row `writeBuf` | 4146 → 3404 (0.82; 0.07) | 4287 → 3530 (0.82; 0.08) | 4201 → 3637 (0.87; 0.09) |
| 80 × 24, 2 rows + update | 689 → 590 (0.86; 0.18) | 701 → 642 (0.92; 0.07) | 698 → 651 (0.93; 0.04) |
| `writeStr` 80 ASCII | 134 → 111 (0.83; 0.10) | 135 → 117 (0.86; 0.04) | 136 → 116 (0.85; 0.04) |
| `writeStr` Cyrillic + box, cached | 164 → 128 (0.78; 0.13) | 162 → 125 (0.77; 0.05) | 166 → 131 (0.79; 0.06) |
| `writeStr` a new text each time | 256 → 237 (0.92; 0.09) | 262 → 243 (0.93; 0.05) | 267 → 248 (0.93; 0.08) |
| `writeStr` 1 ASCII character | 128 → 99 (0.77; 0.11) | 121 → 107 (0.88; 0.12) | 129 → 103 (0.80; 0.07) |
| `writeStr '║'` (cached) | 147 → 107 (0.73; 0.19) | 142 → 109 (0.76; 0.11) | 153 → 113 (0.74; 0.05) |
| `writeStr` 5 digits | 134 → 109 (0.82; 0.20) | 128 → 105 (0.82; 0.04) | 136 → 110 (0.81; 0.11) |
| `writeBuf` 20 cells | 143 → 121 (0.85; 0.22) | 137 → 122 (0.89; 0.06) | 139 → 121 (0.88; 0.11) |
| `writeCStr` status line (cached) | 198 → 129 (0.65; 0.17) | 200 → 130 (0.65; 0.05) | 206 → 132 (0.64; 0.10) |
| `writeChar '═'` × 30 | 269 → 200 (0.75; 0.25) | 265 → 198 (0.75; 0.09) | 277 → 206 (0.74; 0.07) |
| `fillRect` 1 × 21 | 973 → 786 (0.81; 0.35) | 972 → 787 (0.81; 0.06) | 992 → 811 (0.82; 0.07) |
| `setClip` / `resetClip` | 84 → 49 / 15 → 14 | 86 → 49 / 15 → 14 | 86 → 50 / 15 → 14 |
| a write cut by the clip | 136 → 122 (0.90; 0.25) | 136 → 124 (0.92; 0.11) | 144 → 129 (0.90; 0.13) |
| `initScreen` 80 × 24 (the palette kept, D18) | 3446 → 525 (0.15) | 3491 → 559 (0.16) | 3521 → 581 (0.17) |
| frame body: 21 × `writeBuf` (A) / one `writeBuf … 21` (B) | 3694 → 1503 | 3668 → 1561 | 3774 → 1586 |
| 200 × 50 full repaint | 26490 → 27716 (1.05; 0.13) | 27455 → 27276 (0.99; 0.12) | 28251 → 27455 (0.97; 0.35) |

New calls (B only; Git-bash / MSYS2 / Cygwin): `getClip` 10.5 / 10.3 / 10.5
µs, `getRow` 47 / 48 / 49 µs, a window's shadow (`shadeRect` 2 × 21 + 40 × 1,
the same rectangles shaded again) 0.62 / 0.64 / 0.63 ms. That is **not below**
the design's 0.35 ms, an emulation by direct row splices with no entry, timed
the same way (where its damage tests no longer assign). With fresh damage and
an update after each shadow, the emulation takes 1224 / 1242 / 1345 µs and
`shadeRect` 1516 / 1519 / 1622 µs: the rows cost about the same (~20 µs
each), the difference is the two entries (guard, the 4-number check, the
clip: ~70 µs a call) and the per-row wide-cell test. No measure is slower
beyond its spread (`full200` on Git-bash, 1.05 with a spread of 0.13, is the
unchanged frame emitter).

**P2 stage 2c-p, the views' performance pass** (2026-11-17). On these
runtimes **bash copies a function's whole body on every call** (an 80-line
body costs ~50 µs per call before a line runs), so a hot function keeps its
rare cases in helpers, and the views call unchecked twins of the writes
(friend entries above). Changes: `writeBuf … H` splices its narrow rows in
place (one clipped piece, no `_put` call per row); `writeStr` holds
`_put`'s body; the frame's colour runs cut the text at the running column
and compare each run's SGR with the last one sent (consecutive runs always
differ in symbol); `updateScreen`'s refusals, visible cursor and the wide
path's variables moved out of its body; `fillColumns` is new (a frame's two
sides in one call, one splice of each row string for both). A/B of
the 2c-3 unit (`git show HEAD`, A) against this one (B), method as above
(A1 B A2 × 5, median of 5 × N):

| µs | Git-bash 5.3.15 A → B (B/A; spread) | MSYS2 5.3.9 | Cygwin 5.2.21 |
|---|---|---|---|
| 80 × 24 full repaint | 9939 → 8402 (0.85; 0.08) | 9549 → 8398 (0.88; 0.06) | 9940 → 8678 (0.87; 0.02) |
| 80 × 24, 24 whole-row `writeBuf` | 3741 → 3548 (0.95; 0.07) | 3523 → 3563 (1.01; 0.03) | 3625 → 3530 (0.97; 0.09) |
| 80 × 24, 2 rows + update | 619 → 609 (0.98; 0.09) | 622 → 590 (0.95; 0.08) | 629 → 594 (0.94; 0.05) |
| `writeStr` 80 ASCII | 113 → 103 (0.91; 0.12) | 110 → 105 (0.95; 0.03) | 113 → 105 (0.93; 0.02) |
| `writeStr` 1 ASCII character | 102 → 91 (0.89; 0.09) | 100 → 91 (0.91; 0.06) | 104 → 93 (0.90; 0.03) |
| `fillRect` 1 × 21 | 861 → 802 (0.93; 0.27) | 751 → 748 (1.00; 0.01) | 774 → 779 (1.01; 0.03) |
| frame body `writeBuf … 21` | 1714 → 842 (0.49; 0.23) | 1492 → 762 (0.51; 0.02) | 1513 → 776 (0.51; 0.12) |
| a write cut by the clip | 140 → 111 (0.79; 0.26) | 121 → 109 (0.90; 0.11) | 124 → 115 (0.93; 0.06) |
| 200 × 50 full repaint | 27852 → 25563 (0.92; 0.16) | 26187 → 22929 (0.88; 0.02) | 26725 → 23390 (0.88; 0.04) |

No measure of that bench is slower beyond its spread on any runtime; the
fv bench suite (`tools/bench`, `fv`, Git-bash, 3 rounds) gives 0.90–1.00 for
every action (80 × 24 paint 29.7 → 28.9 ms, resize 0.93).

## Cost

Forks happen at init (`stty -g`, `stty -a` once per process, the raw-mode
`stty`, `stty size`, five `trap -p`, the reader and its watchdog where they run), at done (`stty`) and per resize (`stty
size` in the default `querySize`), and at most one `tput colors` in the
colour-depth detection. The WINCH trap, `updateSize` over an overridden
`querySize`, every buffer write, `updateScreen` and everything on the event
path are fork-free (`tests/006`).

`read -n1` on a real pty against a file fd, per byte (median of 5 × 500 bytes
pre-written into the pty under `script(1)`, 2026-11-09):

| runtime | pty | file fd | `fv.keyboard.getKeyEvent` pty / file |
|---|---|---|---|
| MSYS2, bash 5.3.9 | 24 µs | 7 µs | 183 / 161 µs |
| Cygwin, bash 5.2.21 | 23 µs | 8 µs | 231 / 193 µs |
| Debian 13 (lab VM), bash 5.2.37 | 22 µs | 11 µs | 202 / 192 µs |
| Debian 13 (lab VM), bash 5.1.16 | 19 µs | 12 µs | 223 / 220 µs |

So the per-read terminal mode switch costs ~15–20 µs per byte: no workaround
is needed.

**With the reader and its watchdog** (blocking reader; median of 5 × 500,
`script(1)` pty, 2026-11-10; `FV_TTY_READER=1` vs `0` in the same runtime):

| runtime | `read -n1` per byte, pipe / pty | `getKeyEvent` per key, pipe / pty | `initVideo` with / without | `doneVideo` with / without |
|---|---|---|---|---|
| MSYS2, bash 5.3.9 | 10 / 24 µs | 163 / 181 µs | 197 / 222 ms | 141 / 83 ms |
| Cygwin, bash 5.2.21 | 13 / 24 µs | 194 / 215 µs | 185 / 230 ms | 147 / 80 ms |

Reading the pipe is cheaper than reading the terminal (no mode switch per
read). `initVideo` varies by ±40 ms between runs (its forks); the two process
substitutions are a small part of it. `doneVideo` is ~60 ms longer with the
reader: the stop (~70–95 ms on Windows; ~190–240 ms when `TERM` was ignored at
shell start) on top of the drain. **Latency**, a key written to the terminal →
`getKeyEvent` returns in an idle loop of 0.05 s polls, through `script(1)`, 5
× 100 keys: **with the reader ~2 ms** (MSYS2 1.8 ms, Cygwin 2.3 ms), without
it ~17 ms (the timed read of the pty wakes late on Windows). A **fifo** standing
in for the terminal is not a fair stand-in: a blocking read of a fifo on the
Cygwin runtimes wakes in timer steps (~15.5 ms per byte).

**In the application** (fv P2 stage 2g, the `fvviews` bench of
`tools/bench`, every action inside `fv.app`'s `Run`; Git-bash 5.3.15 on a
machine ~1.9× slower than the tables above): the terminal update is 0.8 ms
of a kbDown (12.1 ms), 3.6 of a kbPgDn (23.3), 11.1 of a Tab between two
side-by-side windows (60.1: one damaged range per row sends each changed row
whole, design R2) and 8.8 of a forced 80 × 24 redraw (54.8). The rest is
the views' work ([fv.views "Cost"](../fv.views/README.md#cost)).

**D21 (the deep performance round, stage B)**: the write path pays less per
row. The text check `[[ $t == *[![:print:]]* || $t == *[![:ascii:]]* ]]`
became one pattern, `__FV_VS_PNA` (a character class walks every cell
through the locale: ~27 µs on a 200-cell row against ~2 µs for a range): on
bash 5.3+ the range glob `*[!\ -~]*`, taken in code order with
`globasciiranges` on (the caller-state guard of every entry sends a shell
with it off to `fv.video._g`, which turns it on for the call); before 5.3
`globasciiranges` orders only characters up to U+00FF by code and collates
the rest (en_US.UTF-8 puts U+FF0C, U+3002, U+200B inside ` -~`), so there
the bracket lists the 95 printable ASCII characters, no range. writeBuf's
symbol check is `*[!$__FV_VS_SYMS]*`, a list (`tests/013`: a tab, é and CJK
under en_US.UTF-8's collation with the option off; fullwidth, zero-width
and a U+0101 symbol under every installed UTF-8 locale). `writeBuf` and the friend `_wbf` carry
`_put`'s body inline (one call and return less per row; the names the bench
counts are unchanged). New numbers come from the CI bench after the stage.

**D21 stage E**: the friend `_wrows` (under fv.views' `writeLines`) writes
the rows of a list in one call — one guard, one `__FV_VS_PNA` test over all
texts and one symbol test over all symbol strings (each array joined with
`0`), then per row the narrow splice of writeBuf's body; the bench counts it
as one write per list (it is in the bench's and the tests' writer lists).

**P3 stage 3a-1, fresh non-ASCII rows** (2026-11-20; design P3 §8.2 / §10:
10.11, 10.12, 10.2). A list page whose names fv.video's text cache never saw
used to cost one public `writeBuf` per row (guard, checks, its own validity
check: one C-locale scope per row) and, for CJK, the per-character walk
(~40–90 µs a character); a cached CJK row went through `writeBuf` as well
(the lead-symbol walk over the multibyte cells, then `_putw`). Now `_wrows`
converts every fresh row of the call in one C-locale scope with one
validity check over the rows joined, CJK / kana / Hangul / fullwidth rows
take the wide fast path (two pattern passes instead of the walk), wide rows
are spliced by `_wrows` itself, and `_lead` does nothing for symbols all
alike (a list row). Local estimate, Git-bash 5.3.15 on the laptop (CI
decides: D20 / D31): one 21-row page of the list stand-in's rows (38 cells)
by `_wrows` + `updateScreen`, the median of 5 × 20 pages, kcl before (git
HEAD) → after, as a ratio to the ASCII page of the same process (5.5 ms both):

| page | before | after | after / before |
|---|---|---|---|
| ASCII, fresh | 1.00 | 1.00 | 1.00 |
| Cyrillic, fresh | 2.7 | 1.5 | 0.55 |
| Cyrillic, cached | 1.3 | 1.3 | 1.0 |
| CJK, fresh | 21 | 4.8 | 0.23 |
| CJK, cached | 6.2 | 4.0 | 0.65 |

What is left of a CJK page is the wide put path (`_putw`: ~0.25 ms a row,
substrings of the multibyte cells) and the wide frame (`updateScreen`: ~11
ms of the page against ~3 ms for the Cyrillic one, the resync after every
CJK character): the D31 speed stage 3v (design 10.15; 3v-1 below, 3v-2 …
3v-5 deferred by the owner).

**P3 stage 3v-1, the wide write paths** (2026-11-21; the 3v design note's
levers V1, V2, V5). Three per-row costs of a CJK page that 3a-1 left, and
the cost a panel pays for standing beside one:

* **V1** (`_wrb1`): after the batch's one validity check, when every
  non-ASCII character of the batch is a plain wide one, the wide fast path
  (`_wfb`) runs **once over the rows joined** instead of once per row — it is
  a per-character substitution, so each row gets exactly its own answer; per
  row only "holds `\x01`" picks the wide or the narrow cache entry. Without
  the substitution (bash 5.1, or `patsub_replacement` off) `_wfb`'s loop
  over the rows joined would be quadratic in the batch (CI, bash 5.1: the
  CJK stand-in scene 47.1 → 55.7 ms): there the batch runs only `_wfb`'s
  test over the rows joined, then the loop (`_wfbl`) per row of the
  batch — still no `_fast` and no second test per row (3v-1 fix F1). A
  batch with any other class (Cyrillic, emoji, a mark, a 4-byte character)
  takes the per-row classes as before.
* **V2** (`_wrowsu`): a wide cache hit is read inline (no `_wrx` per row), a
  short row is padded inline from the screen's blanks (`_wrcut` only for a
  row that is cut or a pad wider than the screen), and a
  **plain wide row** — no marker in the text or in the row (`WIDE` bit 2
  clear), inside the clip, no wide pair of the row cut at X or X+W — is
  spliced in place with exactly `_putw`'s effects (the cells, the symbol's
  fill, `WNEW` as `_putw` sets it, `WIDE` from one test, the damage X..X+W)
  instead of a `_putw` call.
* **V5** (`_wrows`' per-row helper `_wrw`): a narrow text written into a
  row whose wide cells are plain (`WIDE` 1: a panel beside a CJK list),
  inside the clip, with no wide pair cut at its edges, is spliced in place
  (`WNEW` 1, `WIDE` 0 when no wide cell is left, the damage) instead of
  `_wrw → _putw`, by the helper `_wrw5` behind a one-line guard in `_wrw`.

Every other row with wide cells (a marker in the text or the row, a pair
cut at an edge or by the clip, a wide text in `_wrows`) still takes
`_putw`. Cost notes: bash copies a function's body on every call. V2's
splice sits inline in `_wrowsu` (the non-ASCII pages' entry, called once
per draw: its extra lines cost once per list, a helper call would cost once
per CJK row); V5's sits in `_wrw5`, called from a one-line guard in `_wrw`,
which every row with wide cells already called, so `_wrows` — the ASCII
pages' and the stand-in's entry — keeps its body (inline there it cost ~25
µs a call, 2 %, in a laptop microbench of a 21-row ASCII page; against that
inline form the helper costs a beside-CJK page one call per row, ~0.4 ms on
the laptop, and still saves the `_putw` call each such row made before),
and so does `_wrw` but for the guard (with the splice inline its body was
ten times longer, and a 21-row page of wide texts paid ~8 % for it; with
the guard 1–2 %). No fork, no new state. `tests/025` compares the batch
entries (and `_wrw`) with kcl c3ed3a2's (kept
verbatim in the test) over seeded random scenes: every buffer, the side
map, the versions, `WNEW`, the damage, the terminal rows, the cache answers,
rc / RESULT and the frame bytes. Laptop, same-process interleaved A/B
(c3ed3a2's four functions against these, median of 9 rounds × 10
actions; CI decides), ms per action of
the list scene (bench `views-list-80`):

| action | Git-bash 5.3 before → after | Cygwin 5.2 before → after |
|---|---|---|
| list PgDn, ASCII | 9.09 → 8.84 (noise: the path is unchanged) | 9.89 → 9.68 (noise) |
| list PgDn, Cyrillic | 11.23 → 11.23 | 11.69 → 11.63 |
| list PgDn, CJK | **20.91 → 17.01** | **21.72 → 18.01** |
| stand-in PgDn | 8.11 → 7.90 (noise) | 8.48 → 8.61 (noise) |
| stand-in PgDn beside the CJK list | **14.26 → 12.52** | **15.06 → 13.63** |

(The last row is the kbool bench row `W.standin.pgdn-cjk` added with this
stage.)

**The CI numbers** (the `fvviews` bench, same-run A/B, ubuntu host, 80 × 24,
fresh pages). Stage 3a-1 (run 44769599343, the P2 stand-in scenes, before →
after): PgDn Cyrillic 15.23 → 10.76 ms (0.71), CJK 73.50 → 21.30 (0.29);
200 × 50 CJK 336.6 → 46.7 (0.14); ASCII and the other actions 0.95–1.06.
Stage 3v-1 (run 44872443494, ratios after / before): the list's CJK PgDn
0.81–0.84 at 80 × 24 and 0.77–0.81 at 200 × 50 on every runner (Alpine's
bash 5.1 0.86 / 0.83), the stand-in beside a CJK list 0.86–0.92, ASCII and
Cyrillic 0.97–1.02; F-1 (the two-panel first paint) 1.02 on Linux, 1.04 on
Cygwin (the `\x01` IFS guard, ~0.4 ms). After it the list PgDn is ASCII 7.99
/ Cyrillic 9.12 / CJK 14.12 ms against the stand-in's 6.45, and F-1 20.79
against 15.26 ([fv.views "Cost"](../fv.views/README.md#cost)). **D31's
targets (PgDn ≤ 8 ms for every kind of text, F-1 ≤ 15 ms) are not met**; the
rest of the speed work (3v-2 … 3v-5, design 10.13 / 10.15) is deferred by
the owner.

## Contract (kcl README §1) and deviations

§1; deviations:

* **plain functions, not a class** — the FPC `Video` unit is procedural;
* **the answer is the globals** (`FV_SCREEN_*`, `FV_VIDEO_*`, `FV_TTY_FD`);
  `RESULT` is `''` except for `querySize`;
* **nothing is ever printed to stdout, also inside `$( )`** — terminal output
  goes to `FV_TTY_FD`, and `querySize` does not print its answer (a TUI inside
  `x=$(…)` must not write the size into `x`);
* **the unit sets traps** (EXIT INT TERM HUP WINCH) between init and done, and
  chains the caller's (above);
* `initVideo` forks (`stty`, `trap -p`) — once per start, not per key;
* **screen buffer:** the answer of a write is `RESULT` = cells advanced
  (FV's `MoveStr` family returns nothing); `getRow` answers in `RESULT` and
  `REPLY` (the one entry point that sets `REPLY`); attributes are palette symbols,
  not FV attribute bytes; colours are 256-colour indices (D10), and with 16
  colours bright colours are SGR 90–97 / 100–107, not blink/bold as in FPC;
  bold is a separate flag; cursor types 2 and 3 show the same block
  (DECSCUSR has no half block), and every exit path's `ESC [ 0 SP q`
  restores **the terminal's default cursor shape**, not the one the shell
  had before (D27); `clearScreen` sends nothing until `updateScreen` and
  ignores the clip; the buffer is at most 1024 columns wide (FVMaxWidth).
* **additions FV's Video unit does not have** (P3): bracketed paste
  (`?2004h` / `?2004l`), `setClipboard` (OSC 52, cut at `FV_PASTE_MAX`), the
  kitty keyboard protocol's push / pop (`FV_KBD_PROTO`), `clusters`, and a
  caller `IFS` holding `\x01` handled by the guard (3v-1).
* **friend entries for fv.\* units:** `fv.video._g CMD [ARGS…]` runs `CMD`
  under this unit's caller-state guard (nocasematch off, globasciiranges on,
  a UTF-8 character locale for a non-UTF-8 caller, all restored as above;
  rc = CMD's).
  fv.views uses it to cut a frame title by characters for a C-locale caller.
  fv.views also reads the per-row flag `__FV_VS_WIDE[y]` (non-zero = the row
  holds wide cells or markers) and reads and clears the per-row flag
  `__FV_VS_WNEW[y]` (a wide character written since its last look) to
  give such rows its repaint-edge test (P3 stage 3a-2; its README),
  the cursor state `__FV_VS_CURX` / `CURY` / `CURT`, and (stage 2c-p) the
  clip `__FV_VS_CX1 CY1 CX2 CY2` (meaningful while a screen exists) to save
  and restore a caller's clip without a call. **Unchecked twins** (stage
  2c-p) for a caller that passes integers and symbols it computed itself —
  the same cells, damage and RESULT as their public twin, without the
  argument check (bash copies a function's whole body on every call and
  each check costs; the views call these on every draw): `fv.video._clipf
  X1 Y1 X2 Y2` (setClip, RESULT `''` as setClip; no guard: four numbers), `fv.video._wstr X Y TEXT
  ATTR` (writeStr), `fv.video._wbf X Y TEXT ATTRS [H]` (writeBuf; ATTRS of
  another length or a bad H still refused), `fv.video._fcf Y H ATTR CH X1
  [X2]` (fillColumns with one or two ascending columns) and
  `fv.video._shadef X Y W H` (shadeRect in the shadow symbol; RESULT left
  alone); all but `_clipf` keep the caller-state guard. **The batch row
  entry** (D21 stage E, under `fv.views.writeLines`): `fv.video._wrows X Y
  TEXTS ATTRS` — X and Y integers the caller computed (no check); TEXTS and
  ATTRS names of two indexed arrays, checked here: a name that is no
  identifier, starts with `__fv` (any case) or is `RESULT`, or an
  associative array is rc 3, RESULT `''`, nothing written and no message (the
  caller reports it: fv.views' refusal; no key of an associative array is
  ever evaluated);
  for every index k of TEXTS, in order, exactly `writeBuf X Y+k TEXTS[k]
  ATTRS[k]` (a missing `ATTRS[k]` is `''`), in one call: one guard, every
  text and every symbol checked at once (the elements joined with `0`), a
  narrow splice per row. **Fresh rows** (P3 10.11): at the first text the
  text cache does not hold, every such text from that row on (at most 256
  at a time) is converted at once and cached — one C-locale scope, the
  control characters per row, **one** validity check over the rows joined
  with `\x1f`, split back, then per row the fast set, the wide fast path
  or the walk, exactly what `_text` gives row by row — so no row goes
  through a public `writeBuf` for its text any more (a batch of plain wide
  rows takes the wide fast path once, 3v V1). A row with wide cells
  (a wide text, or a narrow one over a row with wide cells) goes through
  `_putw` with writeBuf's lead-symbol rule (10.12) — a narrow one over
  plain wide cells (`WIDE` 1), inside the clip, no pair cut at its edges,
  is spliced in place with `_putw`'s effects (3v V5); a row with bad symbols
  or ATTRS of another length goes through `writeBuf` itself (its refusal).
  RESULT = the widest row's cells (writeBuf's answer, the maximum; 0 for no
  rows); a row writeBuf refuses leaves RESULT `''` and rc 2 after the other
  rows are written; no screen rc 1. **The uniform-symbol row entry** (P3
  10.2, under `fv.views.writeRows`): `fv.video._wrowsu X Y W TEXTS SYMS` —
  X, Y, W integers the caller computed; TEXTS and SYMS names of two indexed
  arrays, refused as `_wrows`' (rc 3, no message); for every index k of
  TEXTS, in order, the row `TEXTS[k]` in the **one** symbol `SYMS[k]` at
  (X, Y+k), cut or padded to W cells by the unit's own cells: the same
  cells, symbols, side map and damage as a `writeBuf` of the text clipped
  to [X, X+W) plus blanks in the symbol up to X+W (a wide character the cut
  halves becomes a blank, writeBuf's edge rule); W < 1 writes nothing;
  fresh texts batched as in `_wrows`; a plain wide row (no marker in the
  text or the row, inside the clip, no pair of the row cut at X or X+W)
  spliced in place with `_putw`'s effects (3v V2). A `SYMS[k]` that is not one symbol
  refuses that row (rc 2, RESULT `''` after the other rows); else RESULT =
  W (0 for no rows or W < 1); no screen rc 1. All of these are
  private to the fv.\* units (not for scripts); a change to them is a
  versioned change that fv.views' tests pin (`tests/020` compares each
  twin with its public one; `tests/021` compares `_wrows` with writeBuf per
  row; `tests/023` `_wrows` on fresh pages with writeBuf per row and the
  walk, and `_wrowsu` with the clipped writeBuf; `tests/025` the
  batch entries with kcl c3ed3a2's, the `_putw` path).

## Tests

`bash kcl/fv.video/tests/tests.sh` — 591 tests (Git-bash, 2026-11-22). `initVideo` runs only under
`script(1)`'s pty (the harness is `tests/fvv_pty.sh`, shared with
fv.drivers), never on the terminal the tests were started from; without a
util-linux `script` in the runtime (Git-bash, BSD, macOS) those cases pass as
`SKIP: ENV: …`.

| file | what |
|---|---|
| 001_NoTerminal | bad mode, a missing (never created) / plain-file / `/dev/null` `FV_TTY`, `/dev/tty` without a controlling terminal (setsid): rc 1, nothing printed, nothing left |
| 002_Size | `updateSize` over a stubbed `querySize`, the fallbacks, the default `querySize` without a terminal |
| 003_Traps | the trap chain in child shells: verbatim save/restore, ignored signals, WINCH, INT/TERM/HUP order and statuses, `set -e` / `set -eE` handlers against plain bash, subshells chain only their own traps |
| 004_Restore | `script(1)`: every exit path restores the terminal (stty, `?1049l ?25h ?7h`, mouse off), statuses 0/3/1/1/130/143/129, the caller's handlers once, SIGTERM ends an idle loop within 1 s; `set -e` + a false `&&` WINCH handler; SIGTERM during the restore's `stty`; the drain (as the runtime runs and with `FV_TTY_READER=0`) |
| 005_Terminal | `script(1)`: the stty state while on, the fds, the size, the traps, SIGWINCH → `cmResizeApp`, init/done twice, `noalt` (no clear, the restore ends with the last-row move), `x=$(…)`, `FV_TTY`, raw mode refused (rc 1, nothing printed) |
| 006_ZeroFork | `PATH=''` (the terminal part, the reader and the whole screen buffer, wide characters, emoji and clusters included) and the static scan (forks only in init, trap setup, `querySize`, the reader start, the depth detection; `tput` only there; `taskkill` only in the reader stop; none at all in `fv.unicode.sh`) |
| 007_Contract | `set -eu` (also the buffer and the P2 additions), reload (the buffer state kept), no stdout, no stray globals or functions (fv.unicode's `__FV_UC_*` and `fv.unicode.*` allowed; `REPLY` from `getRow`) |
| 008_Subshells | `script(1)`: parent traps never chained in a subshell's TUI, the owner rule (a subshell's init/done under an active parent are no-ops; a subshell's own TUI) |
| 009_Buffer | allocation, every write and its RESULT, clipping, `setClip`, bad arguments, the shown copy, damaged columns, SGR on change, `force`, the cursor, the output-fd rules, a failed `printf` |
| 010_Palette | the default palette (32 symbols, `V` the shadow), `definePalette`, SGR with 256 / 16 colours, nearest-16 for all 256 indices against the VT model, repaints on depth and palette changes, the detection chain (FV_COLORS, TERM, COLORTERM, a `tput` stub, no `tput`) |
| 011_Locale | silent load, a C caller (UTF-8 inside, locale back), ASCII mode (candidates stubbed to none; `FV_ASCII=1`), the maps, one `?` per sequence, control characters, invalid / cut / overlong / surrogate UTF-8 one `?` each while 4-byte characters and clusters become marker cells, C1 with `globasciiranges` off, legacy CJK caller locales, the caller's own locale as candidate, the text cache |
| 012_VtModel | every frame replayed through the pure-bash VT model (`tests/fvv_vt.sh`, grid starting as garbage): scripted scenes, resize, and a seeded random property test (`FVV_SEED`, `FVV_FRAMES`): VT grid = buffer = a per-cell shadow model after every update, incremental = one forced repaint. Narrow text; the wide frames are 018's |
| 013_CallerState | nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS, `set -eu`, C locale: same output, state kept; a second scene with wide characters, emoji, clusters, classes x / y and the fast path under the same setups; D21: globasciiranges off under an installed locale whose collation is not the code order (en_US.UTF-8 and the like; a tab, é and CJK keep a C.UTF-8 caller's cells; a skip where there is none); a caller locale bash cannot restore (LANG / LC_ALL / LC_CTYPE missing; LANG missing or empty beside a working LC_CTYPE and a missing LC_MESSAGES / LC_NUMERIC / LC_TIME; a shell left in UTF-8 under a missing name, before and after the load; a case-variant name under nocasematch): every entry point, the load, `_drain` (also from a real trap) keep the caller's locale variables and probe (after each call) and give a C caller's results (L-1); the P2 additions (`writeBuf` with H, `shadeRect`, `getRow`, `getClip`) are part of that scene |
| 014_Perf | repaint and partial-update cost against 3× the targets (numbers in the log) |
| 015_ShellState | `script(1)`: init / done / the EXIT trap under an IFS holding digits, init under `IFS=$'\n\t'` and `$'\n'`, done → init → a full repaint |
| 016_Reader | the reader and its watchdog (D13 + amendment). Without a terminal (a fifo stands in, every runtime): all 256 byte values forwarded unchanged and the end at end of file (under `set -eEuxT`, pipefail, ERR/DEBUG/RETURN traps, a UTF-8 locale); the owner killed with no byte typed (both gone within 1 s; with a child holding the watchdog pipe within 2 s); the reader alone blocks and ends at the next byte; INT/QUIT/TSTP/WINCH ignored by both, TERM/HUP/a failed write end the reader; `_rstart` / `_rstop`; `FV_TTY_READER` 0 / 1 / auto by `OSTYPE` / junk; `__FV_VI_POLL` '' and junk; a reader or a watchdog that does not start (both stopped); `TERM` ignored at shell start (stopped by `KILL`); the stop's timing; the reader keeps only fds 0/1/2/tty, the watchdog 0/1/2; `_rstop` never signals a pid that is not its child; the watchdog killed alone; data on the watchdog pipe; the reader dying alone (the watchdog exits without a signal, the stop signals nothing); the stop while a background child holds the watchdog pipe (no wait). `script(1)`: both alive while on (two children), keys / NUL / CSI / SGR mouse / UTF-8 / a 300-byte burst through the reader, Esc alone vs a sequence, both gone after doneVideo, exit, `set -e`, Ctrl+C, SIGTERM, SIGHUP (within 1 s) and `kill -9` of the main shell (no byte typed: within 1 s; a child holding the watchdog pipe: within 2 s), re-init, a subshell under an active parent, `FV_TTY_READER=0` and auto, signals to the reader alone, the reader killed → end of input, the restore drains through the pipe and never reads the terminal (with a reader) / drains the terminal (without), `TERM` ignored at shell start, a restore re-entered mid-stop drains only the pipe, an interactive shell's fd 255 (the terminal) is held by neither. Every reader / watchdog pid is reaped if it survives; every child shell too (its pid recorded, its stdout a file, the calling line in its command line and in `current`); the fds counted are those in three snapshots 50 ms apart |
| 017_Wide | wide characters (D5): the fast path (every accepted code point has class n / x, the refused ones), the cell grammar and RESULT / strWidth, 24 cluster widths (VS16 after © ❤ and keycaps 2, D14; ZWJ sequences; modifiers; flags from the left; orphans, also across calls), the screen and clip edges, half-overwrites (also of a half outside the clip; the damage), writeBuf / writeCStr / writeChar / fillRect units and symbols, frames (a marker's content, never a placeholder; cluster A -> B in one cell is sent; force, depth and palette changes repaint markers), the cursor on a second half, the side map after fill / clear / resize and through 250 random operations (the grammar, also markers = side entries per row, checked after each), fillRect W 1..12 and writeChar COUNT 1..6 with four kinds of unit, the text cache and writeCStr's separate one, the screen's mode decided once, ASCII mode with the table stubbed, a C caller, nocasematch, `set -eu`; the per-row flag `__FV_VS_WNEW` (P3 3a-2: set by a wide write, also cut or overwritten at once, and a write into a row holding one; not by narrow writes; emptied by allocation) |
| 018_WideVt | wide frames through the VT model (`fvv_vt.sh` with the test's own width table: CHA, 2-wide cells, half-overwrites, marks, ZWJ / modifier / flag / VS16 joins): scripted scenes (CJK, emoji, clusters, a flag, a keycap, ⌚, ©️, orphans; half-overwrites; a cluster replaced in the same cell; the cursor after a resync), the bytes of a row (CHA after a wide cell, the pre-blank, nothing after the range's last cell), three disagreeing terminals (emoji, a CJK character, VS16 drawn narrow: every other cell right with the resync, a blank after a narrow-drawn marker, a failure with `__FV_VS_RSYNC=0`), a narrow marker drawn wide (the cell after it re-sent), three seeded random runs of `FVV_FRAMES` (200) frames, one wide-heavy, most frames with a wide write: VT grid = buffer and the grammar after every update, incremental = forced repaint, a minimum share of frames with a resync and a pre-blank; and an incremental random run against a disagreeing terminal (every cell but the deviating ones equals the buffer after every frame) |
| 021_Rows | D21 stage E: the batch row entry `_wrows` = one `writeBuf` per index (240 seeded random cases: narrow, Cyrillic, box, wide, emoji, combining and control text, empty rows; sparse arrays, missing / short / long / bad symbol strings; rows with wide cells and markers; X and Y off every edge; four clips; a cold and a warm text cache; ASCII mode; 30×10 and 200×50; cells, symbols, side map, wide flags, versions, damage, rc and RESULT); the names refused rc 3 (no identifier, `__fv*`, `RESULT`, associative: no key evaluated, nothing written); no rows (empty, unset) RESULT 0; RESULT = the widest row; a refused row rc 2 / RESULT `''` with the other rows written; a sparse TEXTS; no screen rc 1; VT-model frames (incremental = forced); a scene under 11 caller setups; `PATH=''` |
| 020_P2p | the stage 2c-p additions: `fillColumns` = one `fillRect X Y 1 H` per column (150 seeded random cases: narrow, wide and marker units, rows with wide cells, clips, columns and rows off the screen, duplicates, any order), RESULT, bad arguments rc 2 with nothing written, no screen rc 1, VT-model frames (incremental = forced); the friend twins `_clipf`, `_shadef`, `_wstr`, `_wbf`, `_fcf` against their public ones (random cases, rows with wide cells); `writeBuf … H` = H single-row writes (random cases, wide rows, clips); a scene under 11 caller setups; `PATH=''`; critic round: a column repeated after a larger one and the clip leaving two equal columns, `_fcf X X`, RESULT 1 on a fresh wide CH (the text walk's cache miss), `_clipf` RESULT `''` |
| 019_P2 | the P2 additions (stage 2a): `writeBuf … H` (H 1 / omitted / `''` identical to P1, H 0, bad H rc 2 with nothing written (also before `initScreen`), the clip on every row, wide text over rows with wide cells, a marker per row, a huge H clamped, ASCII mode); `shadeRect` (characters kept, `V` / ATTR, screen and clip edges, negative and empty rectangles, a half-covered wide character shaded whole also outside the clip, side map and versions untouched, the damage, bad arguments, frames through the VT model incl. 16 colours, incremental = forced); `getRow` (display text, `REPLY`, read-only, bad Y, ASCII mode); `getClip` (after init / setClip / resetClip, a save-restore round trip); the default palette kept per process (a cached `initScreen` equals a fresh build at 256 and 16 colours, after `definePalette`, `setColorDepth`, an emptied 16-colour map, ASCII mode; values in the environment ignored); the fast argument check (every coordinate form: 1–7-digit integers incl. leading zeros and `-` pass with their value, the rest rc 2, in every write and `setClip`); a P2 scene under 12 caller setups; `PATH=''` |
| 022_Clusters | P3 stage 3a-1: the wide fast path's table (every code point U+3000–U+FFFF it takes is one of the design's runs and class w in fv.unicode; Latin-1, Cyrillic, U+0800–2FFF, VS16 and 4-byte characters refused); `clusters` = the walk's cells (CL the cells' contents, CW their widths, an orphan's screen space dropped; RESULT; widths sum to strWidth; valid text joined back) over 300 seeded random texts (ASCII, Cyrillic, Greek, Latin-1, CJK, Hangul, kana, fullwidth, emoji, ZWJ, VS16, keycaps, flags, marks, controls, C1, invalid UTF-8), again with the 5.1 loops forced (`__FV_VS_AMP=0`) and with `patsub_replacement` off; ASCII mode (one cluster of one cell per UTF-8 sequence, TEXT's own bytes); the answers (empty, the fast path, a caller's local arrays, no screen) and the refusals (rc 2, the arrays untouched); a scene under 11 caller setups; `PATH=''` |
| 023_Fresh | P3 stage 3a-1: `_text` with the wide fast path = the walk alone (400 random texts incl. the joins that must refuse it, the loop, the option off); `_wrows` on fresh pages = one `writeBuf` per row with the walk alone (160 seeded random pages of every kind of text, one invalid row among valid ones, controls incl. `\x1f`, refused rows, clips, X / Y off the edges, ASCII mode, 30×10 / 80×24 / 200×50; cells, symbols, side map, flags, versions, damage, rc, RESULT; the same page again from the cache), with the loops forced, with a nearly full text cache, 300 rows (two batches); the calls (a fresh Cyrillic / CJK page: one validity check, no `writeBuf`, no walk; cached: none; emoji: one walk per row); `_wrowsu` = a `writeBuf` clipped to [X, X+W) + blanks (a wide pair and a wide marker at the edge at every W −1..10, 160 random cases, refused symbols, the names rc 3, no screen rc 1); VT-model frames; every installed UTF-8 locale (also with `globasciiranges` off) against C.UTF-8; a scene under 12 caller setups (`patsub_replacement` off too); `PATH=''` |
| 025_WidePaths | P3 stage 3v-1: the batch entries `_wrows` (with its helper `_wrw`) / `_wrb1` / `_wrowsu` against kcl c3ed3a2's (kept verbatim in the test, swapped in for the reference run: the `_putw` path) — 200 seeded random scenes (rows with and without wide cells, wide pairs at every edge, marker / emoji rows, Cyrillic, controls, invalid UTF-8, five clip kinds incl. edges on wide pairs, cuts, pads, refused rows, ASCII mode, fresh / warm texts, narrow rows over plain-wide rows), each written, shown, written again from the cache and shown: CH AT WIDE X XV WNEW DX, OCH OAT OXV, XSEQ, the cache answers, rc / RESULT and both frames' bytes equal, fewer `_putw` calls asserted; again with the 5.1 loop (`__FV_VS_AMP=0`) and `patsub_replacement` off; an edge sweep (W 1..10, X 0..4, pairs of the text and the row at both parities, a clip at the write); a narrow sweep (one `_wrows` of N 1..10 at X 0..4 into CJK rows at both parities, no earlier write at X, `WNEW` cleared before) and a narrow write over every pair (`WIDE` 0, `WNEW` 1, the damage); the calls (a fresh CJK page: one `_wfb`, no `_putw`; cached: no `_wrx`; a narrow page beside it: `_wrw` and `_wrw5` but no `_putw`; an emoji page: one `_putw` per row; with `__FV_VS_AMP=0` and with `patsub_replacement` off: one `_wfb`, the loop `_wfbl` per row, never over the rows joined); 19 caller setups (a caller IFS holding `\x01` before the screen and around the writes, `unset IFS` under `set -u`); the four single-row writes of fresh wide texts and `initScreen` (the palette built afresh) under such an IFS; `PATH=''` |
| 026_CursorPaste | P3 3d: DECSCUSR on a shape change only (underline / block, hidden and shown again, forced frames, a new screen, the VT model's `VT_SHP`), the restore's `?2004l` and `ESC [ 0 SP q` (only after a shape), a noalt restore's last-row move (alt: none), OSC 52 with RFC 4648's vectors, UTF-8 and raw bytes, the 3072 / 96-byte pieces against a byte-at-a-time reference, the `FV_PASTE_MAX` cap (an incomplete UTF-8 sequence dropped), 128 KB in under 3 s (F3), the refusals; on a pty: `?2004h` at init, `?2004l` + `ESC [ 0 SP q` on doneVideo, exit 3, an error under `set -e`, SIGTERM, Ctrl+C; a typed paste = one `cmPasteText` (its newline no Enter), also split in two pieces. `fvv_pty`'s restore check now holds `?2004l` for every pty test |
| 024_KbdProto | P3 3L, the keyboard protocol: `_kproto` per `FV_KBD_PROTO` value (auto / empty / kitty / off / a bad one + its debug line; `__FV_KB_ISIG` set for every value), `_kpush` on a fake state (once; nothing with the TUI off, in a subshell, without a fd). `script(1)`: auto without a reply (the query after `?1049h`, no push, no pop), auto + a kitty reply typed twice (one push after it, the pop before `?1049l`, the reply no key), a DA1 reply only (no push), kitty (push at once, no query), kitty + noalt, off (nothing), a bad value (as auto); the pop on `exit` without doneVideo (3), SIGTERM after a reply-driven push (143), Ctrl+C (130); a late reply after doneVideo and a push from a subshell push nothing, after doneVideo the report `CSI 99;5u` is the key `kbCtrlC`; Ctrl+C typed as that report under the push (no 0x03): SIGINT all the same, popped, restored, 130 |

Run on Git-bash 5.3.15 (pty cases SKIP), MSYS2 5.3.9, Cygwin 5.2.21 and Debian
(bash 5.1.16 and 5.2.37, util-linux script 2.41.5) in the lab VM (2026-11-09; the
screen buffer, 009-014, the same day; the reader, 016, on 2026-11-10, in the VM also with
`FV_TTY_READER=1` for every fv suite).
