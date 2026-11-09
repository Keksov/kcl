# kcl/fv.video — the terminal for the fv.* text UI

Layer L0 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It sets the
terminal up for a full-screen program and puts it back on **every** exit path:
raw mode, alternate screen, hidden cursor, autowrap off, the screen size and a
resize flag. It is a port in spirit of the FPC rtl-console `Video` unit
(`InitVideo`, `DoneVideo`, `ScreenWidth` / `ScreenHeight`): **plain functions,
no classes**. The screen buffer (writes, palette, damage diff, wide
characters) is P1 and will live in this unit too.

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
| `fv.video.initVideo [noalt]` | opens the terminal, saves its `stty -g` and the caller's traps, installs the traps below, sets raw mode, then prints: alternate screen `ESC[?1049h` (not with `noalt`), cursor hidden `?25l`, autowrap off `?7l`, SGR reset, clear; reads the size. Typed-ahead input is kept. rc 0 = on (also when it already was — here or in the parent of this subshell: a no-op); rc 1 = no terminal / stty failed — nothing printed to any terminal, nothing left open, one debug line; rc 2 = a mode other than `noalt` |
| `fv.video.doneVideo` | SGR reset, `?7h`, `?25h`, `?1049l` (if used), mouse reporting off (`?1006l ?1003l ?1002l ?1000l`, always), the pending input drained (below), `stty` back to the saved state, the fd closed, `FV_KEY_FD` put back, the caller's traps put back **exactly**. Idempotent: done twice, or done and then the EXIT trap, restores once. In a subshell of the process that called `initVideo`: a no-op (below). rc 0 |
| `fv.video.updateSize` | `FV_SCREEN_W` / `FV_SCREEN_H` from `querySize`; a dimension that is 0, missing, not a number or longer than 5 digits comes from `COLUMNS` / `LINES`, else 80 × 24, with one debug line. Clears `FV_VIDEO_RESIZED` first. rc 0, `RESULT=''` |
| `fv.video.querySize` | the size source: `RESULT="ROWS COLS"`, rc 0; rc 1 when it cannot tell. Default: `stty size` on `FV_TTY_FD` (a fork). **Override it** to take the size from elsewhere; the tests stub it |

| Global | Meaning |
|---|---|
| `FV_SCREEN_W`, `FV_SCREEN_H` | the screen size in cells (80 × 24 until known) |
| `FV_VIDEO_ON` | 1 between a successful `initVideo` and the restore |
| `FV_VIDEO_RESIZED` | 1 after a SIGWINCH; `updateSize` (and so `fv.drivers.getEvent`) clears it |
| `FV_TTY_FD` | the terminal's fd while on, else `''`. **All terminal output goes here**, never to stdout |
| `FV_TTY` | *input*: the terminal's path, default `/dev/tty` |
| `FV_KEY_FD` | fv.keyboard's input fd: set to `FV_TTY_FD` by `initVideo`, its old value (or unset state) put back by the restore |

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
without a byte, at most ~0.3 s or 64 KiB, fork-free — so it never lands on the
shell prompt after the program. It costs one idle wait (~0.05 s, ~0.06 s on
Windows) per restore. Nothing is drained at init. `kill` uses `$BASHPID`, so a TUI running
inside `x=$(…)` kills its own subshell, not the script around it. A trapped
signal does not interrupt bash's `read`, so the event loop must read with a
timeout (`fv.drivers.getEvent` always does); SIGTERM during an idle loop ends
the process in ~0.1 s (the read timeout plus the drain).

## Cost

Forks happen at init (`stty -g`, `stty -a` once per process, the raw-mode
`stty`, `stty size`, five `trap -p`), at done (`stty`) and per resize (`stty
size` in the default `querySize`). The WINCH trap, `updateSize` over an
overridden `querySize` and everything on the event path are fork-free
(`tests/006`).

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
* `initVideo` forks (`stty`, `trap -p`) — once per start, not per key.

## Tests

`bash kcl/fv.video/tests/tests.sh` — 102 tests. `initVideo` runs only under
`script(1)`'s pty (the harness is `tests/fvv_pty.sh`, shared with
fv.drivers), never on the terminal the tests were started from; without a
util-linux `script` in the runtime (Git-bash, BSD, macOS) those cases pass as
`SKIP: ENV: …`.

| file | what |
|---|---|
| 001_NoTerminal | bad mode, a missing / plain-file / `/dev/null` `FV_TTY`, `/dev/tty` without a controlling terminal (setsid): rc 1, nothing printed, nothing left |
| 002_Size | `updateSize` over a stubbed `querySize`, the fallbacks, the default `querySize` without a terminal |
| 003_Traps | the trap chain in child shells: verbatim save/restore, ignored signals, WINCH, INT/TERM/HUP order and statuses, `set -e` / `set -eE` handlers against plain bash, subshells chain only their own traps |
| 004_Restore | `script(1)`: every exit path restores the terminal (stty, `?1049l ?25h ?7h`, mouse off), statuses 0/3/1/1/130/143/129, the caller's handlers once, SIGTERM ends an idle loop within 1 s; `set -e` + a false `&&` WINCH handler; SIGTERM during the restore's `stty`; the drain |
| 005_Terminal | `script(1)`: the stty state while on, the fds, the size, the traps, SIGWINCH → `cmResizeApp`, init/done twice, `noalt`, `x=$(…)`, `FV_TTY`, raw mode refused (rc 1, nothing printed) |
| 006_ZeroFork | `PATH=''` and the static scan (forks only in init, trap setup, `querySize`) |
| 007_Contract | `set -eu`, reload, no stdout, no stray globals or functions |
| 008_Subshells | `script(1)`: parent traps never chained in a subshell's TUI, the owner rule (a subshell's init/done under an active parent are no-ops; a subshell's own TUI) |

Run on Git-bash 5.3.15 (pty cases SKIP), MSYS2 5.3.9, Cygwin 5.2.21 and Debian
(bash 5.1.16 and 5.2.37, util-linux script 2.41.5) in the lab VM (2026-11-09).
