# kcl/fv.msgbox — message and input boxes of the fv.* text UI

Layer L3 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P3_DESIGN.md](../docs/dev/fv/P3_DESIGN.md) §6, P3-9). Free Vision's
`MsgBox` unit (FV `msgbox.inc`, FPC 2025): `MessageBox`, `MessageBoxRect`,
`InputBox`, `InputBoxRect` as plain functions that build a dialog from
[fv.dialogs](../fv.dialogs/README.md)' classes, run it modal and destroy
it, answering the command in `RESULT`. No classes of its own, no forks.

**Status: P3 stage 3e.** The unit loads `fv.dialogs` (and through it
`fv.views`); the boxes need an application ([fv.app](../fv.app/README.md):
`FV_DESKTOP`, `FV_APP`).

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.app fv.msgbox

TApplication.new app
fv.msgbox.messageBox 'File not found: %s' $(( FV_MF_ERROR | FV_MF_OKBUTTON )) -- "$f"
fv.msgbox.messageBox 'Save changes?' $(( FV_MF_CONFIRMATION | FV_MF_YESNOCANCEL ))
case $RESULT in cmYes) save ;; cmNo) ;; cmCancel) return ;; esac
name='untitled.txt'
fv.msgbox.inputBox 'Save as' '~N~ame' name 80
[[ $RESULT != cmCancel ]] && save "$name"
fv.msgbox.inputBox -p 'Login' '~P~assword' pass 64        # password mode (D29)
```

A box can be opened anywhere the screen's shell runs: before `app.Run`
(the first paint comes with it), from an application's `HandleEvent`, from
a dialog's `Valid` or an input line's `Validator`, from inside another box.

## Functions

| Function | FV | Answer |
|---|---|---|
| `fv.msgbox.messageBox MSG OPTIONS [-- PARAMS…]` | `MessageBox(Msg, Params, AOptions)` | a 40 × 9 box centred on the desktop (`FV_MF_INSERTINAPP`: on the application), then as `messageBoxRect`; `RESULT` = the command |
| `fv.msgbox.messageBoxRect AX AY BX BY MSG OPTIONS [-- PARAMS…]` | `MessageBoxRect` | the box over (AX, AY)–(BX, BY) in the owner's coordinates (B exclusive, as every fv.views bound); `RESULT` = the command |
| `fv.msgbox.inputBox [-p] TITLE LABEL VARNAME LIMIT` | `InputBox(Title, ALabel, S, Limit)` | a 60 × 8 box centred on the desktop, then as `inputBoxRect`; `RESULT` = the command |
| `fv.msgbox.inputBoxRect [-p] AX AY BX BY TITLE LABEL VARNAME LIMIT` | `InputBoxRect` | the box over the rectangle in the desktop's coordinates; `RESULT` = the command |

**The message box** (FV `MessageBoxRect` + `MessageBoxRectDlg`): a
`TDialog` titled by `OPTIONS & 3`; a `TStaticText` over (3, 2, SizeX − 2,
SizeY − 3) holding MSG — with `--`, `printf -v MSG PARAMS…` (FV's
`FormatStr`; `%%` is a `%`) — so a line starting with `^C` (`$'\x03'`) is
centred and a long message wraps at its blanks (TStaticText's rules); the
buttons `OPTIONS` names, in FV's order Yes, No, OK, Cancel, each 10 × 2,
two cells apart, centred on row SizeY − 3 by FV's `(SizeX − X) shr 1`
(four buttons in a 40-wide box start left of the frame, as in FV); FV's
`SelectNext(False)`: **the first button is selected** and takes the
default look, so Enter presses it.

**The input box** (FV `InputBoxRect`): a `TDialog` titled TITLE; a
`TInputLine` over (4 + CStrLen(LABEL), 2, SizeX − 3, 3) of **LIMIT
clusters** (CStrLen: LABEL's cells without its `~`); a `TLabel` over (2,
2, 3 + CStrLen(LABEL), 3) linked to it; `O~K~` (`cmOK`, the default
button) over (SizeX − 24, SizeY − 4)–(SizeX − 14, SizeY − 2) and
`Cancel` 12 cells right; the input line selected, holding **VARNAME's
value, all of it selected** (FV `SetData`: the first key replaces it; a
longer value is cut to LIMIT clusters, control characters dropped — the
input line's `setText`). Unless the answer is `cmCancel`, VARNAME is set
to the line's text (FV `GetData`, FV's `var S`); after a cancel it stays
as it was (unset stays unset). `-p`: `PasswordChar='*'`, one `*` cell per
cluster on the screen, VARNAME gets the real text (D29; fv.dialogs README,
"Password mode").

**Answers**: `RESULT` = the command that ended the box: `cmYes`, `cmNo`,
`cmOK`, `cmCancel` (a button: Enter on the selected one, Space on the
focused one, a click, Alt + its letter or the plain letter; an
application's `cmYes` / … command ends it too). **Esc, Ctrl+F4, the close
icon and the end of input answer `cmCancel`.** The rc is 0 for every
answer, so `inputBox … && [[ $RESULT != cmCancel ]]` reads as FV's
`<> cmCancel`.

### OPTIONS

One integer, the flags OR'd (`$(( FV_MF_ERROR | FV_MF_OKBUTTON ))`):
0–65535 in plain digits (FV's `Word`); bits FV does not read are ignored.
The readonly constants, FV's values:

| constant | value | FV |
|---|---|---|
| `FV_MF_WARNING` `FV_MF_ERROR` `FV_MF_INFORMATION` `FV_MF_CONFIRMATION` | 0 1 2 3 | `mfWarning` … `mfConfirmation`: the title |
| `FV_MF_INSERTINAPP` | 128 | `mfInsertInApp`: centred on and run by the application instead of the desktop (over the status line too) |
| `FV_MF_YESBUTTON` `FV_MF_NOBUTTON` `FV_MF_OKBUTTON` `FV_MF_CANCELBUTTON` | 256 512 1024 2048 | `mfYesButton` … `mfCancelButton` |
| `FV_MF_YESNOCANCEL` `FV_MF_OKCANCEL` | 2816 3072 | `mfYesNoCancel`, `mfOKCancel` |

A box with no button closes by Esc, Ctrl+F4 or its close icon.

### FormatStr: MSG and PARAMS

`-- PARAMS…` formats MSG with `printf -v` (FV's `FormatStr`: `%s`, `%d`,
`%x`, `%c`, widths, `%-` and `%0` work as printf's); **a surplus
parameter is ignored** (printf would repeat the format for it: the
arguments one pass of the format takes are counted, `%%` none, a `*` one
more); a missing one is printf's empty string / 0; a refused conversion
(`%d` of a word) shows what printf made of it, without its message.
**Without `--` MSG is shown as it is**: `'100% sure'` needs no escaping.

### Translations

FV's resourcestrings are two indexed arrays a script may change at any
time (before or after the load; a re-source keeps them):

| array | elements (defaults) |
|---|---|
| `FV_MSGBOX_TITLES` | 0–3 the message box's title by `OPTIONS & 3`: `Warning` `Error` `Information` `Confirm` (FV `MsgBoxTitles`: sWarning sError sInformation sConfirm) |
| `FV_MSGBOX_BUTTONS` | 0–3 the message box's buttons: `~Y~es` `~N~o` `O~k~` `Cancel` (FV `ButtonName`: slYes slNo slOk slCancel — FV's `O~k~` has a lowercase hot letter); 4–5 the input box's: `O~K~` `Cancel` (FV's literals in `InputBoxRect`) |

An element that is unset or `''` takes its default. A `~` marks the hot
letter (any script: `FV_MSGBOX_BUTTONS[0]='~Д~а'` makes `д` press Yes).

```bash
FV_MSGBOX_TITLES=(Предупреждение Ошибка Информация Подтверждение)
FV_MSGBOX_BUTTONS=('~Д~а' '~Н~ет' 'О~к~' 'Отмена' '~О~К' 'Отмена')
```

## Nesting and the end of input

**Each call builds, runs and destroys its dialog** (FV; no box is kept or
reused). The dialog's name is reserved: `${FV_DESKTOP}__fvmsgbox`; a box
opened while another runs — from a `Valid` or `Validator`, from an event
source or an `Idle` of yours — takes the first free name of the family
(`…__fvmsgbox2`, `…__fvmsgbox3`, …), so boxes nest to any depth; their
controls are named under the dialog (`…__fvtext`, `…__fvbtn0`–`3`,
`…__fvinput`, `…__fvlabel`, `…__fvok`, `…__fvcancel`). After a box the
screen equals a full repaint and no view, array or name of it is left
(`006`: 136 boxes, nested ones among them, leave nothing and grow no table).

**The end of input** (fv.views' latch `__FV_VW_EOF`): a box asked after
the end of input answers `cmCancel` at once — the dialog is made and
destroyed, nothing is drawn, an input box's variable is kept; the end of
input inside a nested box ends it and every box below it with `cmCancel`.

## Refusals

* **Not the screen's process** (inside `$( )`, a `( )` subshell, a
  pipeline): fv.views' owner rule for `execView`. Every function checks it
  first: rc 2, `RESULT=''`, exactly one line on stderr —
  `Error: fv.msgbox: messageBox: refused in a subshell (BASHPID …; the
  screen belongs to …): call it in the shell that owns the screen`
  (`VERBOSE_KKLASS=quiet` silences it) — nothing on stdout, nothing made,
  the terminal untouched. A box's answer is `RESULT` and a variable, which a
  subshell could not hand back anyway.
* **A malformed call**: a wrong argument count, OPTIONS that is not one
  integer 0–65535, PARAMS not after `--`, a corner that is not an integer;
  VARNAME that is not an identifier, is `RESULT`, starts with `_fv` /
  `__fv` (any case: this framework's names, which the box's own variables
  would hide), is readonly or an associative array; LIMIT that is not
  digits; **no application** — `FV_DESKTOP` (and, with
  `FV_MF_INSERTINAPP`, `FV_APP`) not a live group: rc 2, `RESULT=''`, one
  `kk.debug` line (`VERBOSE_KKLASS=debug` shows it), nothing drawn, the
  variable kept.

## Deviations from FV

* **Plain functions** over fv.dialogs' classes (P3-9): FV's
  `MessageBoxRectDlg` (a dialog object of the caller's class) is not
  ported — build such a dialog with fv.dialogs and `fv.views.execView`.
* **OPTIONS is one integer** (L4) and **PARAMS are words after `--`**
  (FV's untyped `Params` pointer); **without `--` MSG is not formatted**
  (FV always calls FormatStr, which reads `Params^` even when it is nil);
  the format is `printf`'s (`%s %d %x %c`, widths, `-`, `0` as FormatStr's;
  FormatStr's `#` parameter index has no printf counterpart, printf's other
  conversions are extra), and a surplus parameter is ignored as FormatStr
  does.
* **LIMIT counts clusters** (TInputLine's model, P3-5) and is not capped at
  255 (FV's `Byte`).
* **Translations are arrays** (FV's resourcestrings); the input box's
  buttons are translatable too (FV hard-codes them).
* The answer is `RESULT` with rc 0; refusals are rc 2 (FV has none: it
  would run with a nil desktop). The subshell refusal is fv.views' owner
  rule.
* The dialogs' names are reserved and nested boxes take a depth suffix.

## Contract (kcl README §1)

Locals `__fvx_*` (fv.drivers has `__fvd_`, fv.dialogs `__fvg_`); globals
`FV_MF_*` (readonly), `FV_MSGBOX_TITLES`, `FV_MSGBOX_BUTTONS` and
`__FV_MB_*` (the defaults, the commands); fork-free (`PATH=''` and a
static scan in `005`); `set -eu` clean; the caller's IFS (default, `\x1f`,
empty), `nocasematch`, `extglob`, locale (C or UTF-8) and `set -u` neither
change the answers nor are changed (`006`: the boxes are made under the
caller's setup); `RESULT` is the answer. An IFS holding `\x01` is not
supported (fv.views / fv.dialogs README, "Contract").

**Friend uses** (the same framework): reads of fv.views' `__FV_VW_LIVE`,
`__FV_VW_GRP`, `__FV_VW_OWNER` and the views' `_data` fields (SizeX /
SizeY of the owner, the input line's `PasswordChar`); calls of
`fv.views._newReserved`, `fv.dialogs._ptCount` (the format's argument
count) and `fv.dialogs._aname` (VARNAME's rule).

## Cost

Exact counts (`tests/008_Budget.sh`, design §8.1's scene: an application
whose `HandleEvent` override calls `inherited`, two windows side by side;
the box opened by a key, closed by Ctrl+F4; the same in the `fvviews`
bench, `views-dialog-80`):

| action | dispatches (limit) | writes (limit) |
|---|---|---|
| `messageBox` with OK, end to end (built, run, closed, destroyed) | 13 (16) | 15 (20) |
| `messageBox` with Yes / No / Cancel | 17 (22) | 17 (24) |
| `inputBox`, end to end | 17 (24) | 17 (26) |

The dispatches are the constructors (`.new` and their `inherited` chains),
the destructor and the application's override for the key; the box's own
keys cost none. The bench rows `dlg.80x24.msgbox.e2e` (a real
`messageBox`) and `dlg.80x24.msgbox.standin` (the design's stand-in: the
same dialog, text and button built by hand) count the same 13 / 15; a
laptop run (Git-bash 5.3, noisy) took ~65 ms against ~61 ms for the
stand-in (design §8.3: ~52 ms laptop, ≤ 50 target, 34–46 ms estimated on
CI). The CI bench decides.

## Tests

`bash kcl/fv.msgbox/tests/tests.sh` — headless; `tests/fvx_testlib.sh`
reuses fv.app's test lib (the headless application, the scripted
terminal) and adds `char` / `alt` keys, the box's name, row snapshots and
the child scene of `005` / `006` (its reference answers in
`tests/fvx_want.sh`).

| file | what |
|---|---|
| 001_Contract | `bash -n`; the API, the readonly constants, the translations' defaults, fv.dialogs loaded; loads under set -eu (twice, by name); the main path under set -eu; a re-source and `kk.unit --forget` + re-source keep a replaced translation; a failing call under set -e; nothing on stdout; no stray names; every refusal (rc 2, `RESULT=''`, one debug line, nothing drawn, the variable kept) |
| 002_MessageBox | every flag set (titles, the buttons' order, labels and places, the text's rect, centring on the desktop and with `FV_MF_INSERTINAPP` on the application, messageBoxRect incl. narrow and negative rects, ignored bits); the cells of a box and the default button's colour; Enter, Tab / Shift+Tab + Enter, Space, Esc, Ctrl+F4, the end of input, Alt and plain hot letters, clicks on a button, a press released elsewhere, the close icon, an application's command; FormatStr (conversions, widths, `%%`, surplus and missing parameters, no `--`, a refused conversion, non-ASCII, `^C`, wrapping); translations (replaced, empty and unset elements, a Cyrillic hot letter); after each: nothing left, == a full repaint |
| 003_InputBox | the layout (CStrLen incl. a CJK label, inputBoxRect, a small rect) and the cells; typing over the selected value, Enter / OK by key, click and Alt+K; Esc, Ctrl+F4, the close icon, Cancel, the end of input keep the variable; the label's hot key; `-p` (one `*` per cluster, wide input); LIMIT in clusters (typing, ASCII / CJK / ZWJ / flag values cut on OK, kept on cancel, LIMIT 0); the variable unset under set -u, an indexed array, a caller's local, a framework variable |
| 004_Nested | a box from a dialog's `Valid` (No keeps the dialog, Yes ends it) and from an input line's `Validator`; two and three levels (`…__fvmsgbox2` while the first runs, the answers innermost first, a full repaint after the inner one, the first name free again); the end-of-input latch (cmCancel at once, nothing written, the variable kept; inside a nested box both end) |
| 005_ZeroFork | the child scene with `PATH=''`; the static fork scan of `fv.msgbox.sh` |
| 006_CallerState | the child scene under IFS default / `\x1f` / empty, nocasematch, extglob, `LC_ALL=C`, set -u and all at once: the reference answers and the state kept; RESULT is the answer, the caller's variables named like the box's words untouched; 136 boxes (nested ones among them) leave no view, array, variable or function and grow no table, == a full repaint |
| 007_Subshell | `$( )` of each function, a `( )` subshell and a pipeline: rc 2, one `Error:` line, nothing on stdout, the terminal and the screen buffer untouched, no view made, RESULT and the variable kept; `VERBOSE_KKLASS=quiet`; the refusal before the argument checks; the same calls work in the owner process |
| 008_Budget | design §8.1's end-to-end budget (the table above), each logged; the answer, nothing left, == a full repaint |
