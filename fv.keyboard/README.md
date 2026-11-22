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
| `fv.keyboard.layoutBase CHAR` | `RESULT` = the US key at CHAR's position in the [layout tables](#layout-independent-keys-p3-3l) (`ф` → `a`); rc 1 = CHAR is in no table (`RESULT` `''`), rc 2 = no CHAR (a debug line). Loads the tables at its first call. Inside `$( )` it prints `RESULT` (kcl README §1.1). For hot keys: `fv.views.hotKeyIs` uses it for plain hot letters |

**TIMEOUT and the polls wait for the first byte only.** Once a key has started,
each missing byte of it is awaited `FV_ESC_TIMEOUT`, so `getKeyEvent 0` and
`pollKeyEvent` can wait that long for every missing byte of an incomplete
sequence, and a lone ESC costs one Esc timeout even through them.

| Global | Meaning |
|---|---|
| `FV_KEY` | the key name; `kbNoKey` after rc 1. `RESULT` holds the same (`''` after rc 1/2) |
| `FV_KEY_CHAR` | the character of `kbChar`, and of an Alt + printable key (`kbAltX` → `x` or `X`, `kbAltChar` → the character); else empty — also for `kbAltLftBrack`, and for `kbAltO` when it is `ESC O` (`ESC o` gives `o`). A CSI u report and a table-mapped legacy Alt key give the **typed** character (`kbAltF` → `а` with a Russian layout; the shifted key under Shift: `А`), Ctrl chords included (except Ctrl + M / J / I / H / `[`, which are `kbEnter` / `kbTab` / `kbBack` / `kbEsc` with no character, as from a legacy terminal) |
| `FV_KEY_BASE` | the **base-layout key**: the US key at that position, one lower-case ASCII character (`f`, `x`, `1`, `;`), from a CSI u report (its base field, else its code when ASCII, else the tables) or from the layout tables for a legacy ESC + non-ASCII key; `''` when not known — every other key (plain typing, legacy Alt + ASCII, Ctrl codes, sequences) and after rc 1 |
| `FV_KEY_SEQ` | the raw bytes of the key, ESC included (a mouse report whole, a bracketed paste's frame whole) |
| `FV_KEY_LEN` | the number of bytes consumed (a NUL byte counts 1 but cannot be held by `FV_KEY_SEQ`) |
| `FV_KEY_EOF` | 1 when rc 1 came from end of file, else 0 |
| `FV_KEY_FD` | *input*: the fd to read (default 0; [fv.video](../fv.video/README.md)`.initVideo` sets it to the terminal, or on Git-bash, MSYS2 and Cygwin to the pipe of its [reader process](../fv.video/README.md#the-reader-process-git-bash-msys2-cygwin), D13 — a pipe reads the same: NUL, the Esc timeout and the `read -t 0` fast path behave as on the terminal). Checked once per value: ≤ 4 digits and `/dev/fd/N` exists (bash stats it, fork-free). Closed later: bash prints its own read error and the reader answers rc 2 (`FV_KEY_EOF=0`) on every path. A **write-only** fd passes the check — no fork-free probe tells it apart (`read -t 0` reports it readable on Git-bash, MSYS2 and Cygwin) — and reading it makes bash print a read error; the reader answers rc 1 with `FV_KEY_EOF=1` |
| `FV_ESC_TIMEOUT` | *input, environment*: how long each next byte of a started key is awaited, seconds; default **0.02** (plan item O1; 0.1 suits ssh). Not a positive number with at most 6 decimals → 0.02 (and a debug line) |
| `FV_PASTE_MAX` | *input, environment*: the bytes a bracketed paste keeps (default **65536**); the rest is read and dropped with one debug line, an incomplete UTF-8 sequence at the cut dropped too. Not 1–9 digits → the default |
| `FV_KBD_LAYOUT` | *input, environment*: the layouts that win in the tables, a comma list, first wins (`bg_phonetic,ru`; `bg_phonetic` = xkeyboard-config's `bg(phonetic)`, both spellings work). A named default layout brings its symbols too (`bg`: `ESC €` → `kbAltEqual`). A Latin layout (`us`, `de`, `fr(azerty)`) is skipped quietly, without loading the variants; another unknown name with one debug line. Read at each lookup: a change rebuilds the table from memory |

The unit's internal state is `__FV_KB_*` (and the tables' `__FV_KL_*`, once
they are loaded); it defines nothing else. A caller's
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
* `kbAltChar` — Alt + a printable character FV does not name (`ESC !`, `ESC é`); a non-ASCII character the [layout tables](#layout-independent-keys-p3-3l) know is named by its key instead (`ESC ж` → `kbAltSemiCol`, `ESC а` → `kbAltF`)
* `kbMouse` — a mouse report, raw in `FV_KEY_SEQ`; `kbUnknown` — anything else, raw in `FV_KEY_SEQ`
* `kbPaste` — a [bracketed paste](#decoding-rules) (P3 3d), the text in `FV_KEY_CHAR`; fv.drivers makes it FV's `evCommand cmPasteText`
* `kbCtrlSpace` (NUL), `kbAltEnter`, `kbCtrlAltA` … `kbCtrlAltZ` (ESC + Ctrl-letter) **except H, I, J and M** — ESC + 0x08 / 0x09 / 0x0A / 0x0D are `kbAltBack`, `kbAltTab`, `kbAltEnter`, `kbAltEnter` — and `kbCtrlBackslash kbCtrlRBracket kbCtrlCaret kbCtrlUnderscore`
* `kbF13` … `kbF20` (rxvt / Linux Shift-F, ambiguous) and every modifier combination FV lacks (`kbShiftUp`, `kbCtrlShiftHome`, `kbCtrlAltDel`, `kbCtrlShiftTab`, …)
* from the kitty protocol only (a legacy terminal cannot tell these keys apart):
  `kbCtrlEsc`, `kbShiftEnter`, `kbCtrlI` / `kbCtrlM` / `kbCtrlH` / `kbCtrlJ`
  (Ctrl + those letters, legacy Tab / Enter / Back), `kbCtrlLftBrack`,
  `kbCtrl0` … `kbCtrl9`, `kbF21` … `kbF35`

**FV names never produced** by a legacy terminal: `kbCtrlEnter` and `kbCtrlBack`
(DOS codes: LF and DEL — here LF is `kbEnter` and DEL is `kbBack`, as the
spike's terminals send them; 0x08 is `kbBack` too) and `kbCtrlTab` — all three
**do** come from the kitty protocol (`CSI 13;5u`, `CSI 127;5u`, `CSI 9;5u`) —;
never at all: `kbSpaceBar`, `kbAltShiftBack`, `kbCtrlPrtSc`, the keypad names
(`kbGrayMinus`, `kbGrayPlus`, `kbAltGrayPlus`, `kbCtrlMinus`, `kbCtrlGreyPlus`,
`kbAltGreyAst`) and FV's character keys (`kbComma`, `kbPlus`, …: characters
are `kbChar`).

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
  (`kbUnknown`, or `kbAltLftBrack` / `kbAltO` right after `ESC [` / `ESC O`); an
  SS3 longer than 32 parameter bytes is `kbUnknown` at the 33rd; a CSI longer
  than that is read on to its final byte (at most 256 bytes in all, else
  `kbUnknown` there), so a long DA1 reply (Windows Terminal's `CSI ?61;4;6;7;14;
  21;22;23;24;28;32;42c`, 33 parameter bytes) is still a reply and anything else
  that long is one `kbUnknown`, consumed exactly; a timeout inside a sequence is
  `kbUnknown`. `ESC ESC` + a mouse report, a malformed sequence, a reply or a
  CSI u report that is no Alt key is a lone `kbEsc` (no character, no base)
  followed by that.
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
* **CSI u and the replies** ([below](#layout-independent-keys-p3-3l)) are CSI
  sequences like any other: consumed exactly, a malformed one is `kbUnknown`
  and leaves the next key intact. win32-input-mode's `CSI … _` (design
  option d, not taken) stays `kbUnknown`.
* **Bracketed paste** (P3 3d, design §4.5, 10.8; fv.video turns it on):
  `ESC [ 200 ~ TEXT ESC [ 201 ~` is **one key, `kbPaste`**, TEXT in
  `FV_KEY_CHAR` exactly as it came (newlines, CR, Tab, escape sequences
  inside are text, never keys), `FV_KEY_SEQ` the frame; the next key comes
  after it. The frame may come in pieces: what is queued is taken first,
  then the fd is read up to the next ESC (and after an ESC that may begin the
  end, the bytes the end still needs) — larger reads than one byte, never
  past the frame's end — each read waiting at most 1 s for more
  (`__FV_KB_PT`); a read that brings bytes goes on, one that brings none, the
  end of input or decode's bytes ending inside the frame end it with the
  text so far — what of the frame comes later is read as keys (its end
  marker alone is `kbUnknown`). A NUL inside is dropped. Through a pipe (Git-bash, MSYS2,
  Cygwin: D13's reader) bash reads a byte per system call: a 64 KiB paste
  takes ~1.5 s there. fv.drivers makes `kbPaste` FV's `evCommand
  cmPasteText`. An `ESC` in front of the frame is a lone `kbEsc`, then the
  paste.

## Layout-independent keys (P3 3L)

Design: [P3_DESIGN.md §14](../docs/dev/fv/P3_DESIGN.md) (D30, option c). With a
non-Latin keyboard layout, Alt+F types `ESC а` (Russian), `ESC φ` (Greek),
`ESC כ` (Hebrew), `ESC ب` (Arabic): the character, not the key. The unit gives
such a key its FV name from the **key position**, and reports that position
in `FV_KEY_BASE`:

| the terminal sends | `FV_KEY` | `FV_KEY_CHAR` | `FV_KEY_BASE` |
|---|---|---|---|
| `ESC f` (Alt+F, US) | `kbAltF` | `f` | `''` |
| `ESC а` (Alt+F, Russian; legacy terminal) | `kbAltF` | `а` | `f` (tables) |
| `ESC ч` (Alt+X, Russian) | `kbAltX` | `ч` | `x` |
| `ESC ж` (Alt + the `;` key, Russian) | `kbAltSemiCol` | `ж` | `;` |
| `CSI 1072::102;3u` (Alt+F, Russian; kitty protocol) | `kbAltF` | `а` | `f` (the report) |
| `CSI 1072:1040:102;4u` (Alt+Shift+F) | `kbAltF` | `А` | `f` |
| `CSI 1072::102;5u` (Ctrl+F) | `kbCtrlF` | `а` | `f` |
| `CSI 97::113;3u` (AZERTY Alt+A, the US q key) | `kbAltA` | `a` | `q` |
| `CSI 27u` (Esc) | `kbEsc` | | |
| `ж` (plain typing) | `kbChar` | `ж` | `''` (no table read) |

**The kitty keyboard protocol** (flags 1 disambiguate + 4 alternate keys):
`CSI code[:shifted[:base]][;mods[:event][;text]]u`, mods = 1 + Shift 1 + Alt
2 + Ctrl 4 (+ Super 8, Hyper 16: `kbUnknown`; Meta 32 read as Alt; Caps /
Num Lock 64 / 128 ignored). The name comes from the **typed character when it
is ASCII** (a Latin layout's typed letter: AZERTY's Alt+A is `kbAltA`, as every
legacy terminal says; Alt+Shift+1 types `!`: `kbAltChar`, as `ESC !`), else
from the code when it is ASCII, else from the base key; Shift is in the
character for character keys (Alt+Shift+F is `kbAltF`, as `ESC F`). A shifted
field that is a control code is `kbUnknown`. Esc 27, Enter 13, Tab
9, Backspace 127 / 8 with their modifiers (`kbShiftTab`, `kbAltEnter`,
`kbCtrlEnter`, `kbCtrlBack`, `kbCtrlTab`, `kbAltEsc`), Space (`kbAltSpace`,
`kbCtrlSpace`), Ctrl + `\` `]` (`kbCtrlBackslash`, `kbCtrlRBracket`), the
keypad codes (57399–57427: Enter, arrows, PgUp …, digits and operators as
characters) and F13–F35 (57376–57398) get FV's names; other functional codes
are `kbUnknown`; a release report (event 3; flag 2 is never pushed) is no key.
No base field and a non-ASCII code (xterm's `formatOtherKeys`
`CSI 1072;3u`, its `modifyOtherKeys` `CSI 27;3;1072~`, tmux): the tables.

**Ctrl alone + M, J, I, H, `[`** (`CSI 109;5u` …; a non-Latin layout's key at
those positions too) get the names a legacy terminal gives the bytes it sends
for them (0x0D 0x0A 0x09 0x08 0x1B): `kbEnter`, `kbEnter`, `kbTab`, `kbBack`,
`kbEsc`, `FV_KEY_CHAR` and `FV_KEY_BASE` empty — so an application sees the
same key in every terminal (FV applications and fv's own views are written
against those names; `kbCtrlM` etc. would never come from a legacy terminal).

**Ctrl+C stays the interrupt.** With the protocol's flag 1 the terminal sends
Ctrl+C as `CSI 99;5u` — no 0x03 byte, so the tty raises no SIGINT. While
fv.video's TUI is on (`__FV_KB_ISIG=1`, set by `initVideo`, cleared by the
restore) a reader that consumes that report (Ctrl alone, the C key: code 99,
or a non-ASCII code with base key c; press or repeat) answers no key and
raises SIGINT with `kill -INT 0`: to its process group, which is what the tty
does for a typed 0x03 (to the foreground process group — the TUI's shell,
whose INT trap restores the terminal and dies of the signal, status 130; its
children; D13's reader and watchdog, which ignore INT; without job control
the shell that started it). `kill $$` / `$BASHPID` would reach one shell
only. `decode` never raises, and outside a TUI the report is the key
`kbCtrlC` (`FV_KEY_CHAR` `c`).

**Other differences between kitty and legacy names** (the same key, two
terminals): Shift+Enter and Shift+Backspace — `CSI 13;2u` is `kbShiftEnter`,
`CSI 127;2u` `kbShiftBack`, where a legacy terminal sends 0x0D / 0x7F
(`kbEnter`, `kbBack`); Ctrl+Shift+M / J / I / H / `[` keep their own names
(`kbCtrlM` …: only Ctrl alone is mapped); Ctrl + a digit or `/` is `kbCtrl1` …, `kbCtrlSlash`
(legacy: often nothing, NUL `kbCtrlSpace` for Ctrl+2, 0x1E `kbCtrlCaret` for
Ctrl+6, 0x1F `kbCtrlUnderscore` for Ctrl+/); a shifted symbol on a Latin key
(German Alt+Shift+3, `§`) is named from the code (`kbAlt3`) where `ESC §` is
`kbAltChar`; and the chords carry `FV_KEY_CHAR` (the typed character: `c` for
`kbCtrlC`, `а` for a Russian `kbCtrlF`) where the legacy control byte has
none. Code that tests `FV_KEY` against FV's names is not affected by the
last point; code that reads `FV_KEY_CHAR` should look at it only for `kbChar`
and the Alt keys.

**Replies are not keys.** fv.video's `initVideo` sends the query `CSI ? u` and
DA1 `CSI c` and waits for nothing (no timed read of the terminal: PLAN D13).
`CSI ? FLAGS u` (the kitty protocol is there; flags 0 count) sets
`__FV_KB_KITTY`, `CSI ? … c` (DA1, every terminal) sets `__FV_KB_DA1`; neither
is a key: `getKeyEvent` returns the key after it (a timed or polling call only
when bytes are already there: a reply never makes it wait twice or block),
`pollKeyEvent` peeks past it, `decode` skips it. On a kitty reply a reader
(not `decode`) runs the hook `__FV_KB_ONKITTY` — fv.video's push of the flags
(`CSI > 5 u`, once; popped on every exit path; `FV_KBD_PROTO=auto|kitty|off`:
[fv.video](../fv.video/README.md#the-keyboard-protocol-p3-3l)). Keys typed
before the reply arrive in the legacy form and work through the tables.

Two hazards of replies that arrive while the user types, both left as they
are (no timed read of the terminal may wait for them, D13):

* **A reply split by more than the Esc timeout.** A reply is decoded like any
  sequence: each byte after the first is awaited `FV_ESC_TIMEOUT` (0.02 s,
  ~31 ms on Windows). Terminals write a reply in one piece, so it arrives
  whole; if a slow link (ssh, a loaded ConPTY) ever splits it by more than
  that, the first part ends as `kbUnknown` (or `kbAltLftBrack` right after
  `ESC [`) and the rest — `?62;22c` — arrives as typed characters (a
  `kbChar` each). Raising `FV_ESC_TIMEOUT` (e.g. 0.1 over ssh) narrows it.
* **The init / done windows.** The query goes out in `initVideo`; the replies
  come back within a round trip, normally before the first key is read, and
  are consumed by the first reader call. A reply that arrives after
  `doneVideo` (the query sent just before an early exit) is drained by the
  restore with the rest of the pending input, or, if it comes later still,
  is read by whatever reads the terminal next (a shell prompt then shows
  `^[[?62;22c`; fv.keyboard itself still takes it as a reply). Keys typed
  between `initVideo` and the reply's arrival come in the legacy form.

**The layout tables** (`fv.keyboard.layouts.sh`, generated by
[tools/kbdlayout](../../tools/kbdlayout/README.md) from xkeyboard-config 2.48;
data, not a unit): for each layout every non-ASCII character of the main block
(levels 1 and 2) → the US key at that position. The default tables (860
entries: ru gr il ara ir ge am th, then ua bg by kz mk rs) hold **script
letters only**: the symbols those layouts also type (`№ € × ÷ – “ „ §`,
Latin letters; everything below U+0370 and in the General Punctuation,
Currency, Letterlike and mathematical blocks: 24 entries) are kept apart and
used only for a layout `FV_KBD_LAYOUT` names, so a Latin-layout typist's
`ESC §` (German Alt+Shift+3) or `ESC €` stays `kbAltChar` (`FV_KBD_LAYOUT=bg`
makes `ESC €` `kbAltEqual`, `FV_KBD_LAYOUT=ru` makes `ESC №` `kbAlt3`). They
are sourced at the **first legacy Alt + non-ASCII key** (or the first
`layoutBase`, or the first CSI u report that needs them) — never on plain
typing; the 252 variant tables (`bg(phonetic)`, `ru(phonetic)`, …, 15 902
entries, every script typed key for key) are sourced only for a layout named
in `FV_KBD_LAYOUT`. A Latin layout named there (`us,ru`, `de_nodeadkeys`,
`fr(azerty)`: a symbols file whose own layout has no table, the generator's
`__FV_KL_NOTAB`) is skipped without a word and without loading the variants
(a variant with a table in such a file, `us_rus`, still loads); another
unknown name gives one debug line. A character found in several layouts
takes the key of the first of:

1. `FV_KBD_LAYOUT` (a comma list, first wins);
2. the layout of the locale's language — the locale's character type as
   POSIX says: the first of `LC_ALL`, `LC_CTYPE`, `LANG` that is set and not
   empty decides (`LC_ALL=C.UTF-8 LANG=bg_BG.UTF-8` names no layout), a
   Latin-script locale (`sr_RS@latin`, any `@latin`) none; **read once, when
   the unit loads** (inside the readers `LC_ALL` is C; a later change of the
   variables is not seen): `ru` ru, `uk` ua, `bg` bg, `el` gr, `he` il, `ar`
   ara, `fa` ir, `ka` ge, `hy` am, `sr` rs, `th` th, `be` by, `kk` kz, `mk` mk;
3. the default order `ru gr il ara ir ge am th ua bg by kz mk rs` (per script
   the most used layout first; the reviewed conflict list:
   [tools/kbdlayout](../../tools/kbdlayout/README.md#the-default-order-and-its-conflicts)).

Inside one layout a character on two keys takes the first, except a capital
whose small letter is on a key of its own: Greek `Σ` (level 2 of both the
final-sigma W key and the sigma S key) is S.

The protocol's base key, when the report has one, always wins over the
tables. Example (§14.6): Bulgarian phonetic Alt+F types `ф`; by the Cyrillic
default `ф` is the A key (`kbAltA`); with `FV_KBD_LAYOUT=bg_phonetic` it is
`kbAltF`; in a kitty-protocol terminal it is `kbAltF` without any setting.
Scope: scripts typed key for key; CJK through an IME composes text and its
Alt chords arrive Latin already; macOS Option without "Option as Meta" types
`ƒ` (PLAN §7: set "Use Option as Meta" / "Esc+"). A missing tables file: the
keys stay `kbAltChar`, one debug line.

**Terminals with the kitty protocol** (from the design, as known mid-2025 —
**to be confirmed in a live check**): kitty, foot, WezTerm (with
`enable_kitty_keyboard`), Ghostty, Alacritty ≥ 0.13, iTerm2 ≥ 3.5, rio, VS
Code's terminal (experimental setting). Without it (the tables apply): xterm,
GNOME Terminal / VTE, mintty, conhost, Windows Terminal, the Linux console,
screen, tmux (its extended keys carry no base key), macOS Terminal.app;
Konsole unknown.

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
  in a TUI — under the kitty protocol too, where the readers raise SIGINT for
  the report: [Ctrl+C stays the interrupt](#layout-independent-keys-p3-3l))
  and **undefines `susp`, `quit` and `lnext`** (plus `dsusp`,
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

P3 3L, the same process alternating the unit before 3L and after it, best of
12 rounds × 400 (Git-bash 5.3.15, laptop, µs; round-to-round noise here is
±10 %, timing decisions come from CI):

| key | before | after | |
|---|---|---|---|
| `a` (`decode`) | 86.6 | 87.4 | plain typing: one more assignment (`FV_KEY_BASE=''`) |
| `ж` (`decode`) | 141.0 | 139.3 | no table read |
| `a` / `ж` (`getKeyEvent`, file fd) | 162.1 / 231.1 | 167.9 / 256.7 | (other runs 0.89–1.07×: noise) |
| `ESC f` | 126.5 | 136.0 | |
| `ESC а` (legacy Alt + non-ASCII) | 207.0 | 245.5 | + the table lookup: `kbAltF` instead of `kbAltChar` |
| `ESC [ A`, `ESC [ 1 ; 5 D` | 225.2, 329.5 | 240.4, 355.9 | |
| `CSI 1072::102;3u` | 523.4 (kbUnknown) | 762.3 | the report decoded |

The 3L review's fixes (long CSIs, Ctrl+C, the table split) touch no code on
the plain typing path: the same harness, before → after the fixes, best of
24–30 × 600, gave `a` 86.7 → 85.3, `ж` 136.2 → 138.8, `getKeyEvent` `a`
153.5 → 158.4 µs, and a run with the same file on both sides spreads ±2 %
(swapped sides: 0.95–0.99×), so: unchanged within the noise. CI agrees:
the `fvviews` bench (run 44834457935, same-run A/B against the unit before
3L) kept every action at 0.96–1.05 on the Linux and Windows rows.

The first legacy Alt + non-ASCII key also loads the default tables: 1.9 ms
once (sourcing 0.7 ms + the 476-character table 1.0 ms); naming a variant in
`FV_KBD_LAYOUT` costs 2.3 ms once (all variants sourced, the table rebuilt);
one table lookup 3–4 µs; `fv.keyboard.layoutBase` 31 µs per call.

No path forks (`tests/007`: the whole API under `PATH=''`, and no `$( )`,
backtick, process substitution, pipe, `( )` subshell, `&` or `coproc` in the
code; `tests/012`: the tables' load, variants and lookups under `PATH=''`).

## Contract (kcl README §1) and deviations

§1; deviations:

* **plain functions, not a class** — the FPC `Keyboard` unit is procedural;
* **the answer is several globals** (`FV_KEY`, `FV_KEY_CHAR`, `FV_KEY_BASE`,
  `FV_KEY_SEQ`, `FV_KEY_LEN`, `FV_KEY_EOF`); `RESULT` holds the key name;
* **a reply decoded by `decode` still sets the reply state** (`__FV_KB_KITTY`,
  `__FV_KB_DA1`; the hook runs only from the readers);
* **the tables are a data file sourced at the first need** (not a dependency
  loaded by `kk.uses`): `fv.keyboard.layouts.sh` next to the unit
  (whitelisted in kcl/tests/001's no-source rule, `KCLT_DATASRC`);
* **a reader may raise SIGINT** (`kill -INT 0`, a builtin: no fork) for the
  kitty report of Ctrl+C while fv.video's TUI is on (`__FV_KB_ISIG`), as the
  tty does for 0x03;
* **a bracketed paste is one key, `kbPaste`, capped at `FV_PASTE_MAX`
  bytes** (default 64 KiB; the rest read and dropped with one debug line);
  a frame that stalls past `__FV_KB_PT` ends with the text so far and its
  tail comes as keys;
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

`bash kcl/fv.keyboard/tests/tests.sh` — 644 tests (Git-bash, 2026-11-22), no terminal (here-strings,
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
| 010_CsiU | the kitty protocol's reports: the design's Russian / Greek / Hebrew / Arabic Alt+F, Alt+Shift+F, Ctrl+F, Ctrl+Alt+F, Esc; a Latin layout (AZERTY); modified Enter / Tab / Backspace / Space / Esc, keypad, F13+, Super, a release, a text field; xterm's formatOtherKeys / modifyOtherKeys; exact consumption with trailing keys; malformed reports (kbUnknown, the next key intact, no hang); the 3L review: rxvt `CSI 1;2c` arrows, Alt + shifted punctuation (kbAltChar), Ctrl + M J I H [ (legacy names), a control-code shifted field, ESC + a report (nothing left over), kitty Ctrl+C raising SIGINT from every reader under `__FV_KB_ISIG` (in a job of its own, `set -m`) and not from decode / Ctrl+Alt+C / Ctrl+Shift+C / ISIG 0 |
| 011_Replies | the kitty and DA1 replies are no keys on every entry point, their state, the hook (readers only, once per reply), a reply alone never blocks a poll or waits twice, replies between typed keys, malformed replies; long DA1 replies (33-37 parameter bytes: Windows Terminal, xterm 525) on every reader path incl. a split within the Esc timeout before and past the 32-byte cap, long non-replies consumed exactly, 256 bytes without a final byte |
| 012_Layouts | the tables: the design's rows (ru, gr, il, ara, ua, ge, am, th, ir), the lazy load (never on plain typing, once, rebuilt from memory), `FV_KBD_LAYOUT` and the locale (incl. the Bulgarian phonetic example), `layoutBase`, a missing file, `set -eu`, fork-free, the data file's shape; the locale's POSIX precedence and `@latin`, symbols only for a named layout (`ESC § € № × “` kbAltChar by default), Greek `Σ` on S, Latin layout names skipped quietly without the variants (`us_rus` still loads) |
| 014_Paste | P3 3d, bracketed paste: one `kbPaste` (LEN, SEQ), newline / CR / Tab / escape sequences as text, empty and UTF-8 pastes, decode of an unended frame, the queue (keys around it), a file fd (two in a row), the frame split between the queue and the fd (the end marker too), delayed writers (two pieces, the end marker split, an ESC inside), a frame whose end never comes (`__FV_KB_PT`), one that stalls past it (its tail as keys, F7), `FV_PASTE_MAX` (the cut, the debug line, a cut UTF-8 character, 70 000 bytes from a file, head and tail of a cut never forging the end: F6), a NUL inside, pollKeyEvent, an ESC in front, nocasematch and an IFS of digits |
| 013_Generator | `tools/kbdlayout/tests/selftest.sh` with this runtime's awks |

Run on Git-bash 5.3.15, MSYS2 5.3.9 and Cygwin 5.2.21 (2026-11-09; P3 3L
2026-11-20).
