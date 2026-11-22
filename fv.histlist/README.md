# kcl/fv.histlist — the input history store of the fv.* text UI

Layer L3 of the `fv.*` text UI ([plan](../docs/dev/fv/PLAN.md), design
[P3_DESIGN.md](../docs/dev/fv/P3_DESIGN.md) §15, D28). Free Vision's
`HistList` unit (FV `histlist.inc`, FPC 2025): the lists of strings an input
line's [`THistory`](../fv.dialogs/README.md#the-input-history) records into
and its history window shows. Plain functions, no classes, no forks.

**Status: done in P3 stage 3h** (P3 complete; no part of it deferred). The
unit loads nothing but kbool; fv.dialogs loads it.

**Cost**: nothing measured on its own — a `historyAdd` is a few array
operations (a re-add scans its list once for the duplicate); the CI bench's
`dlg.80x24.history-open-close` (fv.dialogs README, "Cost") includes the
store's reads.

## Quick start

```bash
source /path/to/kbool/kbool.sh
kk.uses fv.histlist

fv.histlist.historyAdd 1 'first'
fv.histlist.historyAdd 1 'second'
fv.histlist.historyAdd 1 'first'          # moves to the front
fv.histlist.historyCount 1; echo "$RESULT"            # 2
fv.histlist.historyStr 1 0; echo "$RESULT"            # first
fv.histlist.historyStr 1 1; echo "$RESULT"            # second
fv.histlist.historyStr 1 2 || echo "no string 2"      # rc 1, RESULT ''
fv.histlist.clearHistory
```

## Functions

| Function | FV | Answer |
|---|---|---|
| `fv.histlist.historyAdd ID TEXT` | `HistoryAdd` | TEXT becomes list ID's newest string: a copy already in the list is deleted (FV deletes every duplicate), the store's oldest strings are dropped until TEXT's record fits `FV_HISTORY_SIZE`, TEXT is inserted at the front. `''` is not added (FV). The list's newest string added again keeps the list as it is (and becomes the store's youngest record, as FV's delete + insert). `RESULT` kept |
| `fv.histlist.historyCount ID` | `HistoryCount` | `RESULT` = the strings of list ID |
| `fv.histlist.historyStr ID INDEX` | `HistoryStr` | `RESULT` = string INDEX of list ID, 0 the newest; past the last string rc 1 and `RESULT=''` (FV answers `''`) |
| `fv.histlist.clearHistory` | `ClearHistory` | every list emptied, the store back to its empty state. `RESULT` kept |

* **ID**: 0–255, plain digits (FV: a `Byte`); `007` is 7.
* **Answers** (the kcl house style for plain functions, as
  `fv.dialogs.getText`): the getters answer in `RESULT`, the procedures keep
  it; a malformed call — an ID that is not 0–255, an INDEX that is not
  digits, a wrong argument count — is **rc 2** with `RESULT=''` and a
  `kk.debug` line (`VERBOSE_KKLASS=debug` shows it).
* Strings are kept byte-exact (blanks, tabs, newlines, `~`, glob characters,
  any script) and compared byte-exact: `Abc` and `abc` are two strings, also
  under the caller's `nocasematch`.

## The store

As FV's `HistoryBlock`, **one store for all lists**, `FV_HISTORY_SIZE` bytes
(FV `HistorySize`, default **65536**; read at each `historyAdd`: plain
digits, else 65536; a smaller value set later trims at the next add). Each
string takes FV_UNICODE's record: its UTF-8 bytes + the bytes of its
length in ULEB128 (1 below 128, 2 below 16 384, …) + 2; the empty store uses
1 byte (FV's `HistoryUsed`). A string that does not fit drops **the oldest
strings of the whole store**, whatever their list, and only as many as
needed. The byte count of a non-ASCII string in a UTF-8 caller is taken under
a local `LC_ALL=C` (kcl README §1.6); a C-locale caller's strings are its
bytes already.

The store lives in the process (FV keeps it in memory too) and survives a
re-source of the unit and `kk.unit --forget` + re-source; it is not saved.
The first load in a process starts empty and drops any `__FV_HL_*` the
environment brought (an exported scalar cannot pose as a list).

## Deviations from FV

* Plain bash arrays per list instead of FV's byte block (the same order,
  dedupe and drop rule; tests `003` run a model of FV's block against it).
* A string whose record alone is larger than the whole store is not added
  (its old copy, if any, stays); FV_UNICODE's `InsertString` would not end.
* `historyStr` past the end is rc 1 besides FV's `''`; an INDEX that is not
  digits is refused (FV's negative index reads the block's first record).
* Not ported: `InitHistory` / `DoneHistory` (nothing to allocate),
  `HistoryRemove`, `LoadHistory` / `StoreHistory` (streams).

## Contract (kcl README §1)

Locals `__fvh_*` (fv.drivers has `__fvd_`), globals `__FV_HL_*` and
`FV_HISTORY_SIZE`; fork-free (`PATH=''` and a static scan in `004`); `set -eu`
clean; the caller's IFS (default, `\x1f`, empty), `nocasematch`, `extglob`,
locale (C or UTF-8: `${#ж}` stays as it was) and `RESULT` (procedures)
neither change the answers nor are changed (`004`). An IFS holding `\x01`
is not supported (as in fv.views / fv.dialogs). The state:

| name | what |
|---|---|
| `__FV_HL_T<ID>` | list ID's strings, newest first |
| `__FV_HL_Q<ID>` | their sequence numbers, in the same order |
| `__FV_HL_ID[S]`, `__FV_HL_SZ[S]` | the list and the record size of the string with sequence number S (sparse; element 0 a sentinel) |
| `__FV_HL_SEQ`, `__FV_HL_LO`, `__FV_HL_USED` | the next sequence number, the oldest one that may still be live, the bytes in use |

fv.dialogs' THistoryViewer reads `__FV_HL_T<ID>` (a friend use, read only).

## Tests

`bash kcl/fv.histlist/tests/tests.sh`; `tests/fvh_testlib.sh` holds the
model of FV's block and fv.video's fork scanner.

| file | what |
|---|---|
| 001_Contract | `bash -n`; loads under set -eu (twice, by name); the main path under set -eu; a re-source and `kk.unit --forget` + re-source keep the history; the environment's `__FV_HL_*` dropped at the first load; a failing call under set -e; no stray names; fv.dialogs loads it by name |
| 002_Store | newest first, a repeat moves to the front, the newest again, `''`, ids 0 / 255 / `007`, past the end (rc 1), byte-exact strings, case under nocasematch, clearHistory, the refusals (rc 2 + a debug line), RESULT kept |
| 003_Cap | record sizes (ASCII, Cyrillic, CJK, emoji; 127 / 128 and 16 383 / 16 384 bytes), the store's oldest strings dropped across lists, a moved string young again, the newest re-added young, an oversized string not added, `FV_HISTORY_SIZE` (not digits, lowered later); 300 seeded adds against FV's model (two caps, and in a C-locale caller); the bookkeeping |
| 004_CallerState | `PATH=''`; the static fork scan; IFS default / `\x1f` / empty, nocasematch, extglob, set -u (answers and state kept); a C-locale caller (bytes, its locale kept); the byte count's local `LC_ALL=C` leaves a UTF-8 caller's locale |
