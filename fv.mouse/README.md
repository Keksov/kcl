# kcl/fv.mouse — terminal mouse reports

Layer L0 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md)). It decodes
one mouse report into what happened, which button, where and with which
modifiers, and prints the sequences that turn reporting on and off. It is a
port in spirit of the FPC rtl-console `Mouse` unit: **plain functions, no
classes, no forks**. It does not read the terminal: the report comes from
[`fv.keyboard`](../fv.keyboard/README.md) as the `FV_KEY_SEQ` of a `kbMouse`
key, and the two units do not load each other.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.keyboard fv.mouse

fv.mouse.enable 1                 # fv.drivers.initEvents / doneEvents call these; fv.video turns it off on exit
while fv.keyboard.getKeyEvent; do
    if [[ $FV_KEY == kbMouse ]] && fv.mouse.decode "$FV_KEY_SEQ"; then
        printf '%s button %s at %s,%s\n' "$FV_MOUSE_WHAT" "$FV_MOUSE_BUTTON" "$FV_MOUSE_X" "$FV_MOUSE_Y"
    fi
done
fv.mouse.disable 1
```

## API

| Function | Answer |
|---|---|
| `fv.mouse.decode RAW` | rc 0 = RAW is an SGR 1006 report `ESC [ < b ; x ; y M` (press, motion) / `m` (release) or an X10 report `ESC [ M Cb Cx Cy`; rc 1 = anything else (every `FV_MOUSE_*` reset, `RESULT=''`, nothing printed; one `Error:` line under `VERBOSE_KKLASS=debug`). Inside `$( )` it prints `FV_MOUSE_WHAT` once |
| `fv.mouse.enable [FD] [any]` | **prints** `ESC[?1000h ESC[?1002h ESC[?1006h` (buttons, drag, SGR encoding) to FD (default 1); `any` adds `ESC[?1003h` (all motion) before 1006. `RESULT` = the sequence |
| `fv.mouse.disable [FD]` | **prints** `ESC[?1006l ESC[?1003l ESC[?1002l ESC[?1000l`. `RESULT` = the sequence |

FD must be a number that is an fd open for writing: otherwise (not a number,
closed, read-only) the call is rc 2 with `RESULT=''` and nothing printed — the
open check is a fork-free stat of `/dev/fd/N`, a read-only fd is caught by the
failed write, whose message is dropped. `RESULT` is set only after the write
succeeded. A mode other than `any` is rc 2.

| Global (set by `decode`) | Meaning |
|---|---|
| `FV_MOUSE_WHAT` | `down`, `up`, `move` (motion: with a button held = drag, or with none under `any`) or `wheel`; also in `RESULT` |
| `FV_MOUSE_BUTTON` | X11 numbering: 1 left, 2 middle, 3 right, 4/5 wheel up/down, 6/7 wheel left/right, 8–11 extra buttons; 0 = no button (motion without one) or not named (an X10 release) |
| `FV_MOUSE_X`, `FV_MOUSE_Y` | the cell, **0-based** (the reports are 1-based) |
| `FV_MOUSE_MODS` | 1 Shift, 2 Alt (Meta), 4 Ctrl — the same bits as `fv.keyboard`'s modifiers |

For Free Vision's `TEvent`: buttons 1/3/2 are `mbLeftButton`/`mbRightButton`/
`mbMiddleButton`, a `wheel` with button 4/5 is `evMouseWheel` with `mwUp`/
`mwDown` (`fv.drivers`, P0b, keeps the button state).

## Notes

* **X10 cannot say a coordinate beyond 223.** Each value is one byte (value +
  32, 1-based), so byte 255 is column/row 223 (0-based 222), the largest. xterm
  sends a NUL for a position past it; `fv.keyboard` stores that NUL as `\xff`, so
  it decodes as 222 — the clamp. SGR has no such limit (`decode` reads up to 5
  digits). `enable` asks for SGR, so X10 only appears on terminals without 1006.
* An X10 release does not name its button (`up`, button 0). An SGR release does.
* SGR `m` with a wheel button (some terminals send one) is `up` with button 4–7.
* The urxvt 1015 encoding (`ESC [ b ; x ; y M` without `<`) and UTF-8 1005 are
  not decoded (rc 1); `enable` does not ask for them.
* Every entry point pins `LC_ALL=C` locally and clears a caller's `nocasematch`
  for the call: X10 bytes ≥ 0x80 are bytes, and `M` is never read as `m`. X10
  byte values come from a byte → value table built once at load (`printf %d
  "'c"` goes through mbtowc, and musl's C locale maps 0x80–0xFF to U+DF80…).

Cost (Git-bash 5.3.15, median of 5 × 500, 2026-11-09 under outside load): `decode`
of an SGR press 0.15 ms, of an X10 press 0.14 ms (the code before the P0a fix
round, same run: 0.15 and 0.14). No path forks (`tests/004`).

## Contract (kcl README §1) and deviations

§1; deviations: **plain functions, not a class**; **the answer of `decode` is
the `FV_MOUSE_*` globals** (`RESULT` = `FV_MOUSE_WHAT`; the byte table is
`__FV_MS_ORD`); **`enable` and
`disable` print by definition** — their output is the terminal command, to the
fd the caller names — and leave it in `RESULT` as well.

## Tests

`bash kcl/fv.mouse/tests/tests.sh` — 104 tests, no terminal: `001_Decode`
(SGR and X10 tables, reports handed over by `fv.keyboard`), `002_Malformed`,
`003_EnableDisable`, `004_ZeroFork`, `005_Contract`. Run on Git-bash 5.3.15,
MSYS2 5.3.9 and Cygwin 5.2.21 (2026-11-09).
