# kcl/fv.drivers — the event of the fv.* text UI

Layer L0 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It turns keys,
mouse reports, a terminal resize and idle time into one Free Vision event,
held in `FV_EV_*` globals with FV names as string values. It is a port in
spirit of the FV `Drivers` unit (`TEvent`, `GetMouseEvent` with its double and
triple clicks) and of `TProgram.GetEvent` / `PutEvent`: **plain functions, no
classes, no fork on the event path**.

It loads [`fv.keyboard`](../fv.keyboard/README.md) (the bytes → key names),
[`fv.mouse`](../fv.mouse/README.md) (the reports) and
[`fv.video`](../fv.video/README.md) (the terminal, the size, the resize flag).

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.drivers

fv.video.initVideo || exit 1
fv.drivers.initEvents                         # mouse on
while fv.drivers.getEvent; do                 # every 0.05 s at the latest
    case $FV_EV_WHAT in
        evKeyDown)    [[ $FV_EV_KEY == kbF10 ]] && break ;;
        evMouseDown)  (( FV_EV_MOUSE_DOUBLE )) && echo "double at $FV_EV_MOUSE_X,$FV_EV_MOUSE_Y" >&2 ;;
        evCommand)    [[ $FV_EV_COMMAND == cmResizeApp ]] && echo "now ${FV_EV_ID}x$FV_EV_INFO" >&2 ;;
        evNothing)    : idle ;;
    esac
done
fv.video.doneVideo                            # mouse off too
```

## API

| Function | Answer |
|---|---|
| `fv.drivers.getEvent [TIMEOUT]` | the next event, in this order: the put event (once) → **a resize** (`FV_VIDEO_RESIZED` set: `fv.video.updateSize`, then `evCommand`, `FV_EV_COMMAND=cmResizeApp`, `FV_EV_ID` = width, `FV_EV_INFO` = height) → a key or mouse report via `fv.keyboard.getKeyEvent TIMEOUT` → `evNothing` when none came within TIMEOUT seconds (default `FV_IDLE_TIMEOUT`, **0.05**; `0` = only what is already there; at most 6 decimals). **Never blocks without a timeout.** rc 0 for every event, `evNothing` included; **rc 1 only at end of input** (end of file, a hung-up terminal: `FV_EV_EOF=1`, `evNothing`), so `while fv.drivers.getEvent` ends instead of spinning on a dead terminal; rc 2 = a bad TIMEOUT or fv.keyboard's rc 2 (a bad `FV_KEY_FD`) |
| `fv.drivers.putEvent` | keeps a copy of every `FV_EV_*` field in one slot; the next `getEvent` returns it before anything else. A second put overwrites the first (FV: `Pending := Event`); putting `evNothing` empties the slot |
| `fv.drivers.clearEvent` | every `FV_EV_*` field back to its default (`evNothing`) |
| `fv.drivers.initEvents [any]` | mouse reporting on, through `fv.mouse.enable` to `FV_TTY_FD` (`any` adds motion without a button); the held buttons, the click memory and fv.keyboard's queue (`fv.keyboard.flush`) are reset. rc 1 = no terminal (`fv.video.initVideo` first); rc 2 = a mode other than `any` |
| `fv.drivers.doneEvents` | mouse reporting off, the same reset; rc 0, also without a terminal (`fv.video`'s restore turns it off anyway) |

`RESULT` = `FV_EV_WHAT` after `getEvent` (`''` after rc 1/2), `''` after the
others. `getEvent` never prints, also inside `$( )` or a pipeline.

**Run the loop in the shell that called `fv.video.initVideo`.** In `… | while
fv.drivers.getEvent` the loop runs in a subshell whose traps are reset: no
resize events reach it, and a SIGTERM waits for the loop to end. Use `while
fv.drivers.getEvent; do …; done < <(…)` when the loop needs an input of its own.

### The event

| Global | Values |
|---|---|
| `FV_EV_WHAT` | `evNothing evKeyDown evMouseDown evMouseUp evMouseMove evMouseWheel evCommand evBroadcast` (the last two only from `putEvent` for now) |
| `FV_EV_KEY`, `FV_EV_CHAR` | `evKeyDown`: fv.keyboard's `FV_KEY` (`kbUp`, `kbChar`, `kbUnknown` …) and `FV_KEY_CHAR`; the raw bytes stay in `FV_KEY_SEQ` |
| `FV_EV_COMMAND` | `evCommand` / `evBroadcast`: a command **name** (`cmResizeApp`, `cmQuit`, …), not a number |
| `FV_EV_ID`, `FV_EV_INFO` | the message fields (`cmResizeApp`: width and height); `''` otherwise |
| `FV_EV_MOUSE_X`, `FV_EV_MOUSE_Y` | the cell, 0-based |
| `FV_EV_MOUSE_BUTTONS` | the FV mask of the buttons **held after the event**: `mbLeftButton` 1, `mbRightButton` 2, `mbMiddleButton` 4 (FPC Mouse: "the button state after the button was released") |
| `FV_EV_MOUSE_MODS` | fv.mouse's modifiers: 1 Shift, 2 Alt, 4 Ctrl |
| `FV_EV_MOUSE_DOUBLE`, `FV_EV_MOUSE_TRIPLE` | 0/1 on `evMouseDown` (and `FV_EV_MOUSE_DOUBLE` on `evMouseWheel`) |
| `FV_EV_WHEEL` | `mwUp` 1, `mwDown` 2 |
| `FV_EV_EOF` | 1 after rc 1 |

Inputs: `FV_IDLE_TIMEOUT` (seconds, default 0.05) and `FV_DOUBLE_DELAY`
(seconds, default **0.44** = FV's DoubleDelay of 8 ticks × 54.945 ms) — each a
positive number with at most 6 decimals, else the default and one debug line
(checked once per value); fv.keyboard's `FV_KEY_FD` and `FV_ESC_TIMEOUT`.
Internal state is `__FV_DR_*`; `__FV_DR_NOW` is the clock hook of the tests
(seconds like `EPOCHREALTIME`, `.` or `,` as the separator; empty = the real
clock).

## Mouse rules

* **Held buttons** are tracked by the unit, because an X10 release names no
  button: a press adds its button; an SGR release removes the one it names, an
  **X10 release releases every button**; a drag adds the button it reports; a
  move that names no button (only in `any` mode) means none is held.
* **Double and triple clicks** follow FV's `GetMouseEvent` (`drivers.inc`): a
  mouse-down whose button mask (held buttons after the press) and cell equal
  the previous mouse-down's, at most `FV_DOUBLE_DELAY` later (inclusive), is a
  double; one more is a triple; after a triple the next press is single again.
  The clock is `EPOCHREALTIME`, its decimal separator stripped for integer
  maths.
* **The wheel** (FV's evMouseWheel, after magiblot/tvision): `FV_EV_WHEEL` 1 or
  2, the held buttons unchanged. As in FV, a wheel event takes part in the
  click memory: consecutive wheel events at one cell are doubles, never
  triples, and a wheel event breaks a click series.
* `evNothing` (rc 0): a report fv.mouse rejects, a horizontal wheel (FV marks
  `mwLeft`/`mwRight` not implemented), a wheel release, buttons 8–11.
* **Not produced:** `evMouseAuto` (repeat while a button is held) — it comes with
  the scroll bars (P3).

## Deviations from Free Vision

* **Resize before keys:** FV reads a key, then the mouse, then the system event
  (`app.inc` `TProgram.GetEvent`); here the resize flag is checked first, so a
  burst of typing cannot delay a redraw for the new size.
* **The command is `cmResizeApp`** (FV's system event, `fvconsts.pas`), not
  `cmResize` (the window command).
* **Keys and mouse come through one reader** (fv.keyboard), so there is no
  separate `GetMouseEvent` / `GetKeyEvent` order.
* **`clearEvent` resets every field**; FV sets `What := evNothing` and
  `InfoPtr := @Self`.

## Contract (kcl README §1) and deviations

§1; deviations:

* **plain functions, not a class**;
* **the answer is the `FV_EV_*` globals**; `RESULT` holds `FV_EV_WHAT`;
* **`getEvent` never prints**, also inside `$( )` (like fv.keyboard's readers);
* **rc 1 of `getEvent` means "end of input"** and `evNothing` is rc 0: a loop
  `while fv.drivers.getEvent` runs until the input ends;
* **a bad `FV_IDLE_TIMEOUT` / `FV_DOUBLE_DELAY` is not an error** (the
  environment): the default is used and a debug line says so.

## Cost

No fork on any path except the resize event (`fv.video.updateSize` → `stty
size`; fork-free over an overridden `querySize`): `tests/006` runs the whole
API with `PATH=''` and scans the code for `$( )`, backticks, process
substitution, pipes, `( )` subshells, `&` and `coproc`.

Per event from a file fd, median of 5 × 500, Git-bash 5.3.15, 2026-11-09 (a
loaded machine, ±10%):

| input | `fv.keyboard.getKeyEvent` | `getKeyEvent 0.05` (what getEvent calls) | `fv.drivers.getEvent` |
|---|---|---|---|
| key `a` | 160 µs | 190 µs | 245–255 µs |
| SGR mouse press / release | 570–590 µs | 620–630 µs | 895–940 µs |

So the event layer adds ~55–65 µs to a key and ~270–300 µs to a mouse report
(fv.mouse's decode, the held buttons, the clock for double clicks). Inlining
`clearEvent` was tried and measured no difference (kept as a call).

## Tests

`bash kcl/fv.drivers/tests/tests.sh` — 141 tests; all but `005` run without a
terminal (bytes on a file or pipe fd, `FV_KEY_FD` set directly).

| file | what |
|---|---|
| 001_Keys | key events and their fields, `kbUnknown`, NUL, fed input |
| 002_Mouse | SGR and X10 press / release / drag / move / wheel, held buttons, modifiers, what stays `evNothing` |
| 003_Clicks | double / triple timing through `__FV_DR_NOW`, `FV_DOUBLE_DELAY`, the wheel, the real clock |
| 004_Events | put / clear, the resize path (`querySize` stubbed), timeouts, end of input, rc 2, `FV_IDLE_TIMEOUT`, initEvents / doneEvents (and their queue reset) |
| 005_Pty | `script(1)` (SKIP: ENV without util-linux script): Ctrl+Z, Ctrl+\, Ctrl+V as keys, a 60-key burst, mouse on / off (doneEvents before doneVideo) and a typed report |
| 006_ZeroFork | `PATH=''` and the static fork scan |
| 007_Contract | `set -eu`, reload, never prints, no stray globals or functions |
| 008_CallerState | the caller's nocasematch, locale and IFS |

Run on Git-bash 5.3.15, MSYS2 5.3.9, Cygwin 5.2.21 and Debian (bash 5.1.16 and
5.2.37) in the lab VM (2026-11-09); 005 SKIPs on Git-bash only.
