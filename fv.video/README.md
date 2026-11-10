# kcl/fv.video — the terminal and the screen buffer for the fv.* text UI

Layers L0 and L1 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It sets the
terminal up for a full-screen program and puts it back on **every** exit path:
raw mode, alternate screen, hidden cursor, autowrap off, the screen size and a
resize flag. Over it, the [screen buffer](#screen-buffer): writes, a 256-colour
palette and a damage diff that sends only what changed, in one `printf` per
frame. It is a port in spirit of the FPC rtl-console `Video` unit
(`InitVideo`, `DoneVideo`, `ScreenWidth` / `ScreenHeight`, `VideoBuf`,
`UpdateScreen`) and FV's `TDrawBuffer` writes: **plain functions, no
classes**. Wide characters come with P1b.

The unit loads no other `fv.*` unit. [`fv.drivers`](../fv.drivers/README.md)
builds the event loop on it; [`fv.keyboard`](../fv.keyboard/README.md) reads the
keys from the fd it opens.

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
| `fv.video.initVideo [noalt]` | opens the terminal, saves its `stty -g` and the caller's traps, installs the traps below, sets raw mode, then starts [the reader and its watchdog](#the-reader-process-git-bash-msys2-cygwin) where `FV_TTY_READER` says so (default: Git-bash, MSYS2, Cygwin), then prints: alternate screen `ESC[?1049h` (not with `noalt`), cursor hidden `?25l`, autowrap off `?7l`, SGR reset, clear; reads the size. Typed-ahead input is kept. rc 0 = on (also when it already was — here or in the parent of this subshell: a no-op); rc 1 = no terminal / stty failed — nothing printed to any terminal, nothing left open, one debug line; rc 2 = a mode other than `noalt` |
| `fv.video.doneVideo` | SGR reset, `?7h`, `?25h`, `?1049l` (if used), mouse reporting off (`?1006l ?1003l ?1002l ?1000l`, always), the pending input drained (below), the reader and its watchdog stopped, `stty` back to the saved state, the fd closed, `FV_KEY_FD` put back, the caller's traps put back **exactly**. Idempotent: done twice, or done and then the EXIT trap, restores once. In a subshell of the process that called `initVideo`: a no-op (below). rc 0 |
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
  arrives while the TUI runs); `susp`, `quit` and `lnext` are undefined, and so
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
* **P1a: one character = one cell.** P1b adds wide characters: a wide
  character's second cell will hold the continuation placeholder `$'\x01'`
  (reserved now; writes can never store it, see control characters), which
  updates never send; a per-row "has wide" flag (`__FV_VS_WIDE`, 0 for now)
  keeps rows without them on the fast path.
* **P1a: characters past U+FFFF (emoji, …) are stored as one `?`.** On
  Cygwin-based bash (Git-bash, MSYS2, Cygwin) such a character counts as
  **two** characters in `${#}` and in substrings (a UTF-16 surrogate pair):
  it would take two buffer cells, and an overwrite of one of them would leave
  half a UTF-8 sequence that the terminal shows as garbage. Storing `?`
  keeps every platform alike and no cut sequence can ever be sent. P1b
  designs real support (width 2, the continuation cell).
* **Re-init:** `initVideo` clears the screen, so after it (also after a
  `doneVideo` → `initVideo` shell-out) the next `updateScreen` repaints
  every cell and re-sends the cursor state, as FPC does with a fresh
  `OldVideoBuf`. `doneVideo` does the same.

### API

Every write sets `RESULT` to the cells it advances along its row (the
unclipped width, so the next write goes at X+RESULT). Bad arguments: rc 2,
`RESULT=''`, nothing written, one debug line. Before `initScreen`: rc 1.

| Function | FPC / FV | Answer |
|---|---|---|
| `fv.video.initScreen` | `InitVideo` (buffer part) | allocates `FV_SCREEN_W` × `FV_SCREEN_H` blanks (a bad size: 80 × 24; W at most 1024, FV's `FVMaxWidth`) in the default symbol `0`; the default palette; the colour depth (below); the ASCII-mode decision; the clip reset; the cursor hidden at 0,0; everything damaged. Usable without `initVideo`. Call it again after `initVideo` to detect the depth. **It resets the palette, the clip, the cursor and the contents**: a palette defined before `initScreen` is lost (define it after); `detectColorDepth` changes only the depth and keeps all of them |
| `fv.video.resizeScreen` | — | after `updateSize` / on `cmResizeApp`: reallocates at the new size, clears, resets the clip, damages everything; palette, depth, cursor kept (`updateSize` itself does not reallocate) |
| `fv.video.writeStr X Y TEXT ATTR` | `MoveStr` + `WriteLine` | TEXT in the symbol ATTR |
| `fv.video.writeChar X Y CH ATTR [COUNT]` | `MoveChar` | CH (its first character; `''` = blank) COUNT times (default 1); RESULT = COUNT |
| `fv.video.writeBuf X Y TEXT ATTRS` | `MoveBuf` | one symbol per cell; ATTRS as long as TEXT (in cells), else rc 2 |
| `fv.video.writeCStr X Y TEXT ATTR1 ATTR2` | `MoveCStr` | each `~` switches between ATTR1 and ATTR2 and takes no cell |
| `fv.video.fillRect X Y W H ATTR [CH]` | — | the rectangle filled with CH (default blank); RESULT = W (0 when negative) |
| `fv.video.clearScreen [ATTR]` | `ClearScreen` | the whole screen blank in ATTR (default `0`), **whatever the clip**; nothing is sent until `updateScreen` (FPC's ClearScreen updates at once) |
| `fv.video.setClip X1 Y1 X2 Y2` | `TRect` | writes go only into [X1,X2) × [Y1,Y2), intersected with the screen; an empty rectangle writes nothing; reallocation resets it |
| `fv.video.resetClip` | — | the clip = the whole screen |
| `fv.video.setCursorPos X Y` | `SetCursorPos` | where the cursor stands after the next update (clamped to the screen there); X, Y ≥ 0 |
| `fv.video.setCursorType 0..3` | `SetCursorType` | `crHidden` 0 → `ESC[?25l`; `crUnderLine`, `crBlock`, `crHalfBlock` 1–3 → `ESC[?25h` (no shape sequence) |
| `fv.video.updateScreen [force]` | `UpdateScreen(Force)` | the frame (above) to `FV_VIDEO_OUT_FD`, else `FV_TTY_FD`. The cursor: when visible, its position after any text or when it moved; `?25h`/`?25l` only on a change. `force`: every cell of every row (no `ESC[2J`) and the cursor state re-sent. rc 1: no fd (nothing sent, the damage kept), or the `printf` failed (the next frame is forced) |
| `fv.video.strWidth TEXT` | `StringDisplayWidth` | RESULT = the cells TEXT takes as a write stores it (P1a: characters; P1b: display width) |
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
  appearance. FV bytes are $BF (B = background, F = foreground) in DOS colour
  order, mapped to ANSI with 0 4 2 6 1 5 3 7 8 12 10 14 9 13 11 15:

  | sym | byte | sym | byte | sym | byte | sym | byte |
  |---|---|---|---|---|---|---|---|
  | `0` | $07 | `8` | $17 | `G` | $13 | `O` | $2E |
  | `1` | $71 | `9` | $1F | `H` | $3E | `P` | $30 |
  | `2` | $70 | `A` | $1A | `I` | $21 | `Q` | $72 |
  | `3` | $78 | `B` | $31 | `J` | $7F | `R` | $38 |
  | `4` | $74 | `C` | $1E | `K` | $7A | `S` | $10 |
  | `5` | $20 | `D` | $37 | `L` | $7E | `T` | $12 |
  | `6` | $28 | `E` | $3F | `M` | $2B | `U` | $32 |
  | `7` | $24 | `F` | $3A | `N` | $2F | | |

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
  `ed a0 80`) is stored as **one** `?`, and so is a character past U+FFFF
  (above). The check runs on bytes in the C locale (no collation, no
  platform `mbrtowc` quirk) and only for text with a non-ASCII byte: valid
  text is confirmed by removing its valid 2- and 3-byte sequences with four
  pattern substitutions; only text that still has a non-ASCII byte takes the
  byte-by-byte pass. Results are cached (at most 512 texts; `initScreen`
  empties the cache).
* **Locale:** every entry point needs UTF-8 character semantics. Each call
  first tests the caller's locale: two probes, a 2-byte (`ж`) and a 3-byte
  (`─`) character, must each count as one character (legacy CJK locales —
  eucJP, GBK, Big5, eucKR — pass the first alone). Only when it is not UTF-8
  does the call run with `local LC_ALL=` a UTF-8 locale found once at load:
  the caller's own locale name if it is UTF-8, then `C.UTF-8`, `C.utf8`,
  `en_US.UTF-8`, `en_US.utf8` (silent probes). The caller's locale is
  unchanged after every call. When no locale variable is set at all, loading
  exports `LC_CTYPE=C.UTF-8`, the kcl-wide convention (kcl README §1.6).
* **ASCII mode** (`FV_VIDEO_ASCII=1`): when no UTF-8 locale exists, or with
  `FV_ASCII=1`. Calls then run in the C locale where needed, and every
  non-ASCII character (one UTF-8 sequence, not one byte) is stored as: box
  drawing horizontals `-` (double `=`), verticals `|`, corners and junctions
  `+`; `↑▲` `^`, `↓▼` `v`, `→►` `>`, `←◄` `<`, `■` `*`; anything else `?`.
* **Caller state:** every entry point clears `nocasematch` for the call and
  puts it back on every return path; `failglob`, `nullglob`, `noglob`,
  `extglob`, `globasciiranges`, `IFS` and `set -eu` change nothing
  (`tests/013`). Every function with a bare fd redirect (`>&$fd`, the form
  bash 5.1 prints correctly) sets `local IFS=`, so a caller IFS holding
  digits cannot split the fd (`tests/015`, on a pty).

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
  (FV's `MoveStr` family returns nothing); attributes are palette symbols,
  not FV attribute bytes; colours are 256-colour indices (D10), and with 16
  colours bright colours are SGR 90–97 / 100–107, not blink/bold as in FPC;
  bold is a separate flag; cursor types 1–3 all just show the cursor (no
  shape sequence); `clearScreen` sends nothing until `updateScreen` and
  ignores the clip; the buffer is at most 1024 columns wide (FVMaxWidth).

## Tests

`bash kcl/fv.video/tests/tests.sh` — 255 tests. `initVideo` runs only under
`script(1)`'s pty (the harness is `tests/fvv_pty.sh`, shared with
fv.drivers), never on the terminal the tests were started from; without a
util-linux `script` in the runtime (Git-bash, BSD, macOS) those cases pass as
`SKIP: ENV: …`.

| file | what |
|---|---|
| 001_NoTerminal | bad mode, a missing / plain-file / `/dev/null` `FV_TTY`, `/dev/tty` without a controlling terminal (setsid): rc 1, nothing printed, nothing left |
| 002_Size | `updateSize` over a stubbed `querySize`, the fallbacks, the default `querySize` without a terminal |
| 003_Traps | the trap chain in child shells: verbatim save/restore, ignored signals, WINCH, INT/TERM/HUP order and statuses, `set -e` / `set -eE` handlers against plain bash, subshells chain only their own traps |
| 004_Restore | `script(1)`: every exit path restores the terminal (stty, `?1049l ?25h ?7h`, mouse off), statuses 0/3/1/1/130/143/129, the caller's handlers once, SIGTERM ends an idle loop within 1 s; `set -e` + a false `&&` WINCH handler; SIGTERM during the restore's `stty`; the drain (as the runtime runs and with `FV_TTY_READER=0`) |
| 005_Terminal | `script(1)`: the stty state while on, the fds, the size, the traps, SIGWINCH → `cmResizeApp`, init/done twice, `noalt`, `x=$(…)`, `FV_TTY`, raw mode refused (rc 1, nothing printed) |
| 006_ZeroFork | `PATH=''` (the terminal part, the reader and the whole screen buffer) and the static scan (forks only in init, trap setup, `querySize`, the reader start, the depth detection; `tput` only there; `taskkill` only in the reader stop) |
| 007_Contract | `set -eu` (also the buffer), reload (the buffer state kept), no stdout, no stray globals or functions |
| 008_Subshells | `script(1)`: parent traps never chained in a subshell's TUI, the owner rule (a subshell's init/done under an active parent are no-ops; a subshell's own TUI) |
| 009_Buffer | allocation, every write and its RESULT, clipping, `setClip`, bad arguments, the shown copy, damaged columns, SGR on change, `force`, the cursor, the output-fd rules, a failed `printf` |
| 010_Palette | the default palette, `definePalette`, SGR with 256 / 16 colours, nearest-16 for all 256 indices against the VT model, repaints on depth and palette changes, the detection chain (FV_COLORS, TERM, COLORTERM, a `tput` stub, no `tput`) |
| 011_Locale | silent load, a C caller (UTF-8 inside, locale back), ASCII mode (candidates stubbed to none; `FV_ASCII=1`), the maps, one `?` per sequence, control characters, invalid / cut / overlong / surrogate / 4-byte UTF-8, C1 with `globasciiranges` off, legacy CJK caller locales, the caller's own locale as candidate, the text cache |
| 012_VtModel | every frame replayed through the pure-bash VT model (`tests/fvv_vt.sh`, grid starting as garbage): scripted scenes, resize, and a seeded random property test (`FVV_SEED`, `FVV_FRAMES`): VT grid = buffer = a per-cell shadow model after every update, incremental = one forced repaint |
| 013_CallerState | nocasematch, failglob, nullglob, noglob, extglob, globasciiranges, odd IFS, `set -eu`, C locale: same output, state kept |
| 014_Perf | repaint and partial-update cost against 3× the targets (numbers in the log) |
| 015_ShellState | `script(1)`: init / done / the EXIT trap under an IFS holding digits, init under `IFS=$'\n\t'` and `$'\n'`, done → init → a full repaint |
| 016_Reader | the reader and its watchdog (D13 + amendment). Without a terminal (a fifo stands in, every runtime): all 256 byte values forwarded unchanged and the end at end of file (under `set -eEuxT`, pipefail, ERR/DEBUG/RETURN traps, a UTF-8 locale); the owner killed with no byte typed (both gone within 1 s; with a child holding the watchdog pipe within 2 s); the reader alone blocks and ends at the next byte; INT/QUIT/TSTP/WINCH ignored by both, TERM/HUP/a failed write end the reader; `_rstart` / `_rstop`; `FV_TTY_READER` 0 / 1 / auto by `OSTYPE` / junk; `__FV_VI_POLL` '' and junk; a reader or a watchdog that does not start (both stopped); `TERM` ignored at shell start (stopped by `KILL`); the stop's timing; the reader keeps only fds 0/1/2/tty, the watchdog 0/1/2; `_rstop` never signals a pid that is not its child; the watchdog killed alone; data on the watchdog pipe; the reader dying alone (the watchdog exits without a signal, the stop signals nothing); the stop while a background child holds the watchdog pipe (no wait). `script(1)`: both alive while on (two children), keys / NUL / CSI / SGR mouse / UTF-8 / a 300-byte burst through the reader, Esc alone vs a sequence, both gone after doneVideo, exit, `set -e`, Ctrl+C, SIGTERM, SIGHUP (within 1 s) and `kill -9` of the main shell (no byte typed: within 1 s; a child holding the watchdog pipe: within 2 s), re-init, a subshell under an active parent, `FV_TTY_READER=0` and auto, signals to the reader alone, the reader killed → end of input, the restore drains through the pipe and never reads the terminal (with a reader) / drains the terminal (without), `TERM` ignored at shell start, a restore re-entered mid-stop drains only the pipe, an interactive shell's fd 255 (the terminal) is held by neither. Every reader / watchdog pid is reaped if it survives |

Run on Git-bash 5.3.15 (pty cases SKIP), MSYS2 5.3.9, Cygwin 5.2.21 and Debian
(bash 5.1.16 and 5.2.37, util-linux script 2.41.5) in the lab VM (2026-11-09; the
screen buffer, 009-014, the same day; the reader, 016, on 2026-11-10, in the VM also with
`FV_TTY_READER=1` for every fv suite).
