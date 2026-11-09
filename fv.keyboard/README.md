# kcl/fv.keyboard — terminal keys as Free Vision key names

Layer L0 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It turns the
bytes a terminal sends for one key into a Free Vision key name (`kbUp`, `kbF5`,
`kbCtrlLeft`, `kbAltX`, …), a printable character, a raw mouse report or
`kbUnknown`. It is a port in spirit of the FPC rtl-console `Keyboard` unit
(`GetKeyEvent`, `PollKeyEvent`): **plain functions, no classes, no forks**.

The unit reads bytes; it does not set the terminal up. Raw mode, echo and the
alternate screen belong to `fv.video` (P0b; its duties toward this unit are
listed under "What the terminal setup must do"). Mouse reports are recognised
and handed over whole; [`fv.mouse`](../fv.mouse/README.md) decodes them, and this
unit does not load it.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.keyboard

fv.keyboard.decode $'\e[1;5D'; echo "$FV_KEY"        # -> kbCtrlLeft
while fv.keyboard.getKeyEvent; do                    # reads FV_KEY_FD (default 0)
    case $FV_KEY in
        kbChar)  printf 'char %s\n' "$FV_KEY_CHAR" ;;
        kbMouse) fv.mouse.decode "$FV_KEY_SEQ" ;;    # needs kk.uses fv.mouse
        kbF10)   break ;;
        *)       printf 'key %s\n' "$FV_KEY" ;;
    esac
done
```

## API

| Function | Answer |
|---|---|
| `fv.keyboard.getKeyEvent [TIMEOUT]` | the next key. Blocks for its first byte, or waits at most TIMEOUT seconds for it (`0` = only what is already there; at most 6 decimals — bash would run a finer value as `-t 0`). rc 0 = a key; rc 1 = none (timeout, or end of file: `FV_KEY_EOF=1`); rc 2 = TIMEOUT is not such a number, or `FV_KEY_FD` is not an open fd |
| `fv.keyboard.pollKeyEvent` | FPC's `PollKeyEvent`: rc 0 = a key is ready; the globals describe it and it **stays queued**, so the next `getKeyEvent` returns it at once. rc 1 = nothing waiting; rc 2 as above |
| `fv.keyboard.decode BYTES` | the first key of BYTES, without any fd. rc 1 = BYTES is empty. Inside `$( )` it prints the key name once (kcl README §1.1) |
| `fv.keyboard.feed BYTES` | queue BYTES **after everything already read from the fd** (a pending NUL included) and before what the fd has not delivered yet (tests, injected input) |
| `fv.keyboard.flush` | drop the queue and a peeked key |

**TIMEOUT and the polls wait for the first byte only.** Once a key has started,
each missing byte of it is awaited `FV_ESC_TIMEOUT`, so `getKeyEvent 0` and
`pollKeyEvent` can wait that long for every missing byte of an incomplete
sequence, and a lone ESC costs one Esc timeout even through them.

| Global | Meaning |
|---|---|
| `FV_KEY` | the key name; `kbNoKey` after rc 1. `RESULT` holds the same (`''` after rc 1/2) |
| `FV_KEY_CHAR` | the character of `kbChar`, and of an Alt + printable key (`kbAltX` → `x` or `X`, `kbAltChar` → the character); else empty — also for `kbAltLftBrack`, and for `kbAltO` when it is `ESC O` (`ESC o` gives `o`) |
| `FV_KEY_SEQ` | the raw bytes of the key, ESC included (a mouse report whole) |
| `FV_KEY_LEN` | the number of bytes consumed (a NUL byte counts 1 but cannot be held by `FV_KEY_SEQ`) |
| `FV_KEY_EOF` | 1 when rc 1 came from end of file, else 0 |
| `FV_KEY_FD` | *input*: the fd to read (default 0; [fv.video](../fv.video/README.md)`.initVideo` sets it to the terminal, or on Git-bash, MSYS2 and Cygwin to the pipe of its [reader process](../fv.video/README.md#the-reader-process-git-bash-msys2-cygwin), D13 — a pipe reads the same: NUL, the Esc timeout and the `read -t 0` fast path behave as on the terminal). Checked once per value: ≤ 4 digits and `/dev/fd/N` exists (bash stats it, fork-free). Closed later: bash prints its own read error and the reader answers rc 2 (`FV_KEY_EOF=0`) on every path. A **write-only** fd passes the check — no fork-free probe tells it apart (`read -t 0` reports it readable on Git-bash, MSYS2 and Cygwin) — and reading it makes bash print a read error; the reader answers rc 1 with `FV_KEY_EOF=1` |
| `FV_ESC_TIMEOUT` | *input, environment*: how long each next byte of a started key is awaited, seconds; default **0.02** (plan item O1; 0.1 suits ssh). Not a positive number with at most 6 decimals → 0.02 (and a debug line) |

The unit's internal state is `__FV_KB_*`; it defines nothing else. A caller's
`shopt -s nocasematch` is cleared for each call and restored afterwards, and the
caller's locale is untouched (`LC_ALL=C` is local to each call).

## Key names

Names are `kb` + modifiers in the order **Ctrl, Alt, Shift** + a base name.

**Free Vision names the decoder produces** (`drivers.inc`):

* `kbEsc kbAltEsc kbEnter kbTab kbShiftTab kbAltTab kbBack kbAltBack kbAltSpace`
* `kbCtrlA` … `kbCtrlZ` except `kbCtrlH`/`I`/`J`/`M`, which arrive as `kbBack`, `kbTab`, `kbEnter`, `kbEnter`
* `kbAltA` … `kbAltZ`, `kbAlt0` … `kbAlt9`, `kbAltMinus kbAltEqual kbAltLftBrack kbAltRgtBrack kbAltSemiCol kbAltQuote kbAltOpQuote kbAltBkSlash kbAltComma kbAltPeriod kbAltSlash`
* `kbUp kbDown kbLeft kbRight kbHome kbEnd kbPgUp kbPgDn kbIns kbDel kbCenter` and their `kbCtrl…` / `kbAlt…` forms (`kbCtrlLeft`, `kbAltPgDn`, …), `kbShiftIns kbShiftDel`
* `kbF1` … `kbF12` and `kbShiftF1` …, `kbCtrlF1` …, `kbAltF1` … `kbAltF12`
* `kbNoKey` (rc 1)

**Names the decoder adds** (FV has none):

* `kbChar` — a printable character, UTF-8 of 1–4 bytes (`FV_KEY_CHAR`); space is `kbChar`, not FV's `kbSpaceBar`
* `kbAltChar` — Alt + a printable character FV does not name (`ESC !`, `ESC ж`)
* `kbMouse` — a mouse report, raw in `FV_KEY_SEQ`; `kbUnknown` — anything else, raw in `FV_KEY_SEQ`
* `kbCtrlSpace` (NUL), `kbAltEnter`, `kbCtrlAltA` … `kbCtrlAltZ` (ESC + Ctrl-letter) **except H, I, J and M** — ESC + 0x08 / 0x09 / 0x0A / 0x0D are `kbAltBack`, `kbAltTab`, `kbAltEnter`, `kbAltEnter` — and `kbCtrlBackslash kbCtrlRBracket kbCtrlCaret kbCtrlUnderscore`
* `kbF13` … `kbF20` (rxvt / Linux Shift-F, ambiguous) and every modifier combination FV lacks (`kbShiftUp`, `kbCtrlShiftHome`, `kbCtrlAltDel`, `kbCtrlShiftTab`, …)

**FV names never produced:** `kbCtrlEnter` and `kbCtrlBack` (DOS codes: LF and DEL
— here LF is `kbEnter` and DEL is `kbBack`, as the spike's terminals send them;
0x08 is `kbBack` too), `kbSpaceBar`, `kbAltShiftBack`, `kbCtrlTab`,
`kbCtrlPrtSc`, the keypad names (`kbGrayMinus`, `kbGrayPlus`, `kbAltGrayPlus`,
`kbCtrlMinus`, `kbCtrlGreyPlus`, `kbAltGreyAst`) and FV's character keys
(`kbComma`, `kbPlus`, …: characters are `kbChar`).

## Decoding rules

* **Sequences:** CSI `ESC [` (parameter/intermediate bytes 0x20–0x3F, one final
  0x40–0x7E; xterm modifiers `1;mX` and `N;m~`, m = 1 + Shift 1 + Alt 2 + Ctrl 4,
  Meta 8 read as Alt; rxvt's `N$` `N^` `N@`), SS3 `ESC O` (application keys,
  VT100 PF keys, terminfo vt100 `kf5`–`kf12`) with optional parameters read by
  the same modifier rule (`ESC O 5 P` old xterm, `ESC O 1 ; 5 P` old VTE /
  konsole), the Linux console's `ESC [ [ A`–`E`, and rxvt's Alt + sequence
  `ESC ESC [ A`. The tables cover xterm, mintty, ConPTY, the Linux console, rxvt
  and VT220 (the spike's 67 checks are `tests/001`).
* **Lone Esc:** after ESC the next byte is awaited `FV_ESC_TIMEOUT`; none → `kbEsc`.
  The same wait applies to every later byte of a sequence or a UTF-8 character.
  On Windows `read -t` waits in 15.6 ms steps, so the default 0.02 s is ~31 ms
  there (spike REPORT). A `read -t` that times out may still have read a byte;
  that byte is kept.
* **Malformed input ends and eats nothing that is not its own:** a byte outside
  the grammar (ESC, a control, DEL, a byte ≥ 0x80) ends the sequence unread
  (`kbUnknown`, or `kbAltLftBrack` / `kbAltO` right after `ESC [` / `ESC O`); a
  CSI or SS3 longer than 32 parameter bytes is `kbUnknown` at the 33rd; a timeout
  inside a sequence is `kbUnknown`. `ESC ESC` + a mouse report or a malformed
  sequence is a lone `kbEsc` followed by that.
* **UTF-8 is strict:** a bad lead byte, a missing continuation byte, an overlong
  form, a surrogate or a code point above U+10FFFF (the second byte after E0 must
  be A0–BF, after ED 80–9F, after F0 90–BF, after F4 80–8F) is `kbUnknown`, the
  offending byte left for the next key.
* **Mouse reports** are consumed exactly: SGR `ESC [ < … M|m` as a CSI, X10
  `ESC [ M` + exactly 3 bytes whatever they are (ESC, controls, UTF-8 leads).
* **Bytes, not characters:** every entry point pins `LC_ALL=C` locally (kcl
  README §1.6) and clears `nocasematch` for the call, so neither the caller's
  locale nor its shell options change an answer.
* **NUL** cannot live in a bash string: a NUL read from the fd is `kbCtrlSpace`
  (`FV_KEY_SEQ` empty, `FV_KEY_LEN` 1) at its place in the byte order (bytes fed
  afterwards come after it) and ends a sequence it interrupts. Inside an X10
  report it is xterm's past-the-end coordinate and is stored as `\xff` (column
  223, the X10 clamp, which is how `fv.mouse` reads it).
* **One byte per read, nothing read ahead:** the fd is read one byte at a time
  and only while a key needs more, so several keys in one chunk (a paste) come
  out one per call and a key split across writes is reassembled; bytes read but
  not used stay queued.

## What the terminal setup must do (fv.video, P0b)

* **Never send DECKPAM (`ESC =`, part of xterm's `smkx`).** In keypad
  application mode the keypad sends `ESC O p` … `ESC O y`, which collide with
  the terminfo vt100 F5–F12 entries (`ESC O t` is decoded as `kbF5`).
* **A cursor-position query needs its own reader.** The reply `ESC [ r ; c R`
  decodes here as a modified F3 (`ESC [ 1 ; 5 R` is `kbCtrlF3`); a future CPR
  request must read its reply itself, not through `getKeyEvent`.
* **Signals and CR on a tty.** Per bash's read builtin, `read -n1` on a terminal
  puts it into a one-character mode for each read, and that mode (bash's
  `tt_setonechar`) turns ISIG, ICRNL and IEXTEN back on. So Ctrl+C, Ctrl+Z and
  Ctrl+\ reach the decoder as keys only when the terminal's `intr`, `susp` and
  `quit` characters are undefined, and CR arrives as LF — one more reason both
  map to `kbEnter`. [fv.video](../fv.video/README.md) **keeps `intr`** (Ctrl+C
  stays an interrupt that restores the terminal, so `kbCtrlC` does not arrive
  in a TUI) and **undefines `susp`, `quit` and `lnext`** (plus `dsusp`,
  `discard`, `status`, `swtch` where they exist), so Ctrl+Z, Ctrl+\ and Ctrl+V
  arrive as `kbCtrlZ`, `kbCtrlBackslash`, `kbCtrlV`. The mode switch costs
  ~15–20 µs per byte on a pty (measured in P0b, fv.video README "Cost").

## Cost

Per key, median of 5 × 500 keys, Git-bash 5.3.15, 2026-11-09 under outside load,
interleaved with the code before the P0a fix round (in brackets; the P0a figures
from a quieter run were 0.09 / 0.23 / 0.34 / 0.13 ms for `decode`):

| key | `decode` | `getKeyEvent` from a file fd |
|---|---|---|
| `a` | 0.09 (0.08) ms | 0.15 (0.14) ms |
| `ESC [ A` | 0.23 (0.23) ms | 0.32 (0.32) ms |
| `ESC [ 1 ; 5 D` | 0.54 (0.53) ms | 0.76 (0.77) ms |
| `ж` | 0.24 (0.21) ms | 0.37 (0.33) ms |

No path forks (`tests/007`: the whole API under `PATH=''`, and no `$( )`,
backtick, process substitution, pipe, `( )` subshell, `&` or `coproc` in the
code).

## Contract (kcl README §1) and deviations

§1; deviations:

* **plain functions, not a class** — the FPC `Keyboard` unit is procedural;
* **the answer is several globals** (`FV_KEY`, `FV_KEY_CHAR`, `FV_KEY_SEQ`,
  `FV_KEY_LEN`, `FV_KEY_EOF`); `RESULT` holds the key name;
* **`getKeyEvent` and `pollKeyEvent` never print**, also inside `$( )` or a
  pipeline: a reader in a subshell loses its queue anyway, and `… | while
  fv.keyboard.getKeyEvent` must not write key names into the loop's output.
  `decode` follows §1.1;
* **rc 1 of the readers means "no key"** (timeout, nothing waiting, end of file) —
  an answer, not an error: no debug line;
* **a bad `FV_ESC_TIMEOUT` is not an error** (it is the environment, not an
  argument): the default is used and a debug line says so;
* **`FV_KEY_FD` is checked once per value**: an fd closed after it was found open
  makes bash print its own read error (the reader then answers rc 2), and a
  write-only fd is found out only by reading it (bash's read error, rc 1,
  `FV_KEY_EOF=1`).

## Tests

`bash kcl/fv.keyboard/tests/tests.sh` — 430 tests, no terminal (here-strings,
files, pipes; `005` uses delayed writers with generous bounds):

| file | what |
|---|---|
| 001_SpikeTable | the spike's 67 checks |
| 002_KeyNames | every name above from the bytes a terminal sends; SS3 with parameters |
| 003_Utf8 | 2/3/4-byte characters, Cyrillic, emoji, a C-locale caller, malformed and non-strict UTF-8 |
| 004_Reader | fd / here-string / queue, peek, EOF, NUL (and feed after it), rc 2, timeouts finer than 1 µs, a closed fd, `FV_ESC_TIMEOUT` |
| 005_Timing | lone Esc vs Alt vs Esc + sequence, split and cut sequences, timeouts |
| 006_Malformed | overlong / cut sequences, mouse reports consumed exactly |
| 007_ZeroFork | `PATH=''` and the static fork scan |
| 008_Contract | `set -eu`, reload, no stray globals or functions |
| 009_CallerState | the caller's nocasematch and locale |

Run on Git-bash 5.3.15, MSYS2 5.3.9 and Cygwin 5.2.21 (2026-11-09).
