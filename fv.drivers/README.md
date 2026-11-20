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
| `fv.drivers.getEvent [TIMEOUT]` | the next event, in this order: the put event (once) → **a resize** (`FV_VIDEO_RESIZED` set: `fv.video.updateSize`, then `evCommand`, `FV_EV_COMMAND=cmResizeApp`, `FV_EV_ID` = width, `FV_EV_INFO` = height) → a key or mouse report via `fv.keyboard.getKeyEvent TIMEOUT` → `evMouseAuto` when none came and a button is held (the mouse rules below) → `evNothing` when none came within TIMEOUT seconds (default `FV_IDLE_TIMEOUT`, **0.05**; `0` = only what is already there; at most 6 decimals). **Never blocks without a timeout.** rc 0 for every event, `evNothing` included; **rc 1 only at end of input** (end of file, a hung-up terminal: `FV_EV_EOF=1`, `evNothing`), so `while fv.drivers.getEvent` ends instead of spinning on a dead terminal; rc 2 = a bad TIMEOUT or fv.keyboard's rc 2 (a bad `FV_KEY_FD`) |
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
| `FV_EV_WHAT` | `evNothing evKeyDown evMouseDown evMouseUp evMouseMove evMouseAuto evMouseWheel evCommand evBroadcast` (the last two only from `putEvent` for now) |
| `FV_EV_KEY`, `FV_EV_CHAR` | `evKeyDown`: fv.keyboard's `FV_KEY` (`kbUp`, `kbChar`, `kbUnknown` …) and `FV_KEY_CHAR`; the raw bytes stay in `FV_KEY_SEQ` |
| `FV_EV_COMMAND` | `evCommand` / `evBroadcast`: a command **name** (`cmResizeApp`, `cmQuit`, …), not a number |
| `FV_EV_ID`, `FV_EV_INFO` | the message fields (`cmResizeApp`: width and height); `''` otherwise |
| `FV_EV_MOUSE_X`, `FV_EV_MOUSE_Y` | the cell, 0-based (`evMouseAuto`: the last report's) |
| `FV_EV_MOUSE_BUTTONS` | the FV mask of the buttons **held after the event**: `mbLeftButton` 1, `mbRightButton` 2, `mbMiddleButton` 4 (FPC Mouse: "the button state after the button was released") |
| `FV_EV_MOUSE_MODS` | fv.mouse's modifiers: 1 Shift, 2 Alt, 4 Ctrl |
| `FV_EV_MOUSE_DOUBLE`, `FV_EV_MOUSE_TRIPLE` | 0/1 on `evMouseDown` (and `FV_EV_MOUSE_DOUBLE` on `evMouseWheel`) |
| `FV_EV_WHEEL` | `mwUp` 1, `mwDown` 2 |
| `FV_EV_EOF` | 1 after rc 1 |
| `FV_EV_BASE` | `evKeyDown`: fv.keyboard's `FV_KEY_BASE`, the base-layout key (the US key at that position: `f` for Alt+F typed `а` in a Russian layout, from the kitty protocol or the layout tables; P3 3L); `''` for a key without one and for **every other event** (mouse, resize, `evNothing`, `evMouseAuto`, `clearEvent`); `putEvent` keeps it. A reply to fv.video's keyboard query is no event: the key after it is (fv.keyboard README, Layout-independent keys) |

Inputs: `FV_IDLE_TIMEOUT` (seconds, default 0.05; also the auto-repeat's period, at least 0.01 s),
`FV_REPEAT_DELAY` (seconds, default **0.44**, FV's RepeatDelay of 8 ticks:
the first `evMouseAuto` after a press) and `FV_DOUBLE_DELAY`
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
* **Auto-repeat, `evMouseAuto`** (P3 design 10.6, FV `GetMouseEvent`'s
  `AutoTicks` / `AutoDelay`): while a button is held since a press and
  nothing arrives, `getEvent` answers `evMouseAuto` — the first
  `FV_REPEAT_DELAY` (default **0.44 s**, FV's `RepeatDelay` of 8 ticks)
  after the press, then one per `FV_IDLE_TIMEOUT` (0.05 s, FV's one tick;
  **at least 0.01 s**, so that a tiny timeout does not make every idle
  read an `evMouseAuto`),
  on a schedule: a late caller gets one, never a burst — at the **last
  report's cell** (a drag moves it) with the held buttons and that report's
  modifiers (`FV_EV_MOUSE_DOUBLE` / `_TRIPLE` 0). While it is armed the read
  waits no longer than the next one is due (a `TIMEOUT` of 1 s is cut to the
  time left), so it comes on time. The clock is wall time
  (`EPOCHREALTIME`): when it goes back by more than a delay and a period,
  the next one is due one period from the new time (the repeat goes on
  instead of stalling until the clock catches up). A loop that reads
  `getEvent 0` until `evNothing` must stop at `evMouseAuto` too (it comes
  instead of `evNothing` while a button is held): fv.views' drag drain
  does. **It never runs away (L2: a lost
  release)**: a key event, any release (also of one button while another is
  held, as FV) and any report with no button held (a move in `any` mode, an
  X10 release) end it; a new press starts the delay again, so does a wheel
  event with a button held (FV); a drag or a wheel alone never starts it.
  A view gets it only with `evMouseAuto` (`FV_EM_MOUSEAUTO`, `$0008`) in its
  `EventMask` or the mask given to `fv.views.mouseEvent`; TView's default
  mask lacks it, as FV's. Users (P3): scroll bar arrows and page areas
  held, a list dragged past its edge, an input line's drag-scroll.

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
* **`evMouseAuto` ends on a key, and a report with no button held** (L2):
  FV keeps `AutoTicks` running until a release, which a terminal can lose;
  a wheel event with no button held does not start it (FV sets `AutoTicks`
  on every wheel event and would repeat with no button). Its times are
  seconds (`FV_REPEAT_DELAY`, `FV_IDLE_TIMEOUT`, the period at least
  0.01 s), not ticks of 54.945 ms, and a wall clock gone back does not stall
  it.

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

The auto-repeat (P3 stage 3a-2) costs an idle `getEvent` one arithmetic test
while no button is held; while one is held since a press it reads the clock
before the read (the timeout cut) and after an idle one: an idle `getEvent 0`
with the read stubbed, Git-bash, laptop: ~85–90 µs unarmed, ~170–190 µs
armed (2 × 2000 calls, 3 rounds) — only between a press and its release.

In the application (fv P2 stage 2g, the `fvviews` bench of `tools/bench`:
every action inside [`fv.app`](../fv.app/README.md)'s `Run`, keys from a
file): reading a 5-byte key sequence (F12) costs ~1.2 ms of the ~5.8 ms a
whole key event takes on that machine (~1.9× slower than the one above);
the rest is the views' routing ([fv.views "Cost"](../fv.views/README.md#cost)).
The application layer is complete for P2: [`fv.views`](../fv.views/README.md),
[`fv.menus`](../fv.menus/README.md), `fv.app`.

## Tests

`bash kcl/fv.drivers/tests/tests.sh` — 178 tests; all but `005` run without a
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
| 009_Auto | P3 3a-2, `evMouseAuto` through `__FV_DR_NOW` (idle reads stubbed): the delay (inclusive), the rate on its schedule (a late caller gets one), the last report's cell and modifiers, every ending condition (a release, a second button's release, a key, a buttonless move, an X10 release; a new press or a wheel with a button held restarts the delay; a drag or a wheel alone never arms it), the read cut to the time left, the period's floor of 0.01 s (a tiny `FV_IDLE_TIMEOUT`; a drain at one instant ends after one), the wall clock going back (a small step changes nothing, a big one: due one period from the new time, the read's timeout cut to it), `FV_REPEAT_DELAY` / `FV_IDLE_TIMEOUT` and a bad value, `initEvents` / `doneEvents`, FV's constants (fv.views' `FV_EM_MOUSEAUTO` = `$0008`), `fv.views.mouseEvent` without the bit skipping them, the real clock on a live pipe (the first not before 0.44 s) |
| 010_Base | P3 3L, `FV_EV_BASE`: copied from `FV_KEY_BASE` (kitty reports, legacy ESC + non-ASCII through the tables), `''` without one, cleared by mouse / resize / `evNothing` / `evMouseAuto` / `clearEvent`, carried by `putEvent`; replies are no events (the key after them; a reply alone on a live pipe: `evNothing` at once, no block), the reply hook run once from `getEvent` |

Run on Git-bash 5.3.15, MSYS2 5.3.9, Cygwin 5.2.21 and Debian (bash 5.1.16 and
5.2.37) in the lab VM (2026-11-09); 005 SKIPs on Git-bash only. P3 stage 3a-2
(evMouseAuto, 009): Git-bash 5.3.15, MSYS2 5.3.9, Cygwin 5.2.21 (2026-11-20).
