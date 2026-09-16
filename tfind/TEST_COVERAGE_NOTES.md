# tfind — test coverage notes

**Status: FINALIZED at P1 (2026-09-16).** Suite `004`–`007` = **226 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single`, against **GNU findutils 4.10.0**. The
per-file row counts below sum to 226 — 110 + 49 + 57 + 10 — and **every case in
the suite has a row**.

**Protocol.** `TFind` has no FPC upstream: it is the fourth wrapper on
[`TUtil`](../tutil/README.md), which is itself a kcl addition (see
[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)). The oracle is therefore **the
bare GNU tool on the same fixture**, run with the same expression, never a second
call into the code under test. Decision **D4** (of the tpipe plan) pins the
*dialect* — GNU findutils 4.10.0, the build MSYS2 ships, identical under both
target bashes — not a binary, so every behavioural file opens with the **GNU
banner gate**: if `find --version` does not begin with `find (GNU findutils) `,
every behavioural case is a loud SKIP and the case **count is unchanged**.

The suite splits in two on purpose:

* **`004_Argv.sh` never executes find.** Every typed option is pinned by
  comparing the built array, which is what `argv NAME` exists for; it is the fast
  half and it is where a wrapper's surface actually lives.
* **`005`/`006`/`007` run the tool** on a fixture tree of depth 3 whose entries
  are chosen for the traps: `a.txt`, `sub/b.TXT` (the case-sensitivity pair),
  `sub/deep/c.txt`, `with space.txt`, a name containing a **newline**, a
  directory literally named `-weird` with a file inside it, a real directory
  symlink and a broken one. **Every file holds `x\n`** so `-size +0` has
  something to match (critic finding 16).

**The comparison primitive** (PLAN §4, critic finding 6). find's traversal order
is not pinned, and a line-based sort turns the newline name into two elements
that can then interleave anywhere. So both sides are NUL framed and sorted with
`sort -z`:

```
wrapper   print0 = 1 -> toArray            ->  sortz
oracle    find … -print0 -> mapfile -d ''  ->  sortz
```

The one deliberate exception is the `-print` framing case (005 §C), which is
*about* the split.

The Basis column cites one of:

* **F1–F12**, plus **F5b**, **F8a/F8b**, **F10a/F10b** — a pinned fact of
  [`PLAN.md`](PLAN.md) §3.
* **C1–C20** — a finding of the 2026-09-16 critic pass ([`PLAN.md`](PLAN.md) §8).
  Every one of the twenty is cited by at least one row below, or named under
  "deliberate gaps".
* **P3-F1** — the tgrep finding this unit inherits with its guard
  ([../tgrep/README.md §4](../tgrep/README.md)).
* **D4 / D6** — a decision: D4 the GNU dialect gate, D6 final `subshellOk`.
* **§n** — a section of [`PLAN.md`](PLAN.md) (or of [README.md](README.md)).

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract ([../README.md](../README.md) §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `argv` | the typed option set → the pinned command line, asserted **without running find** |
| `tool-behaviour` | what GNU findutils 4.10.0 `find` actually does, measured against the bare tool as oracle |
| `representation` | start points and records are **data**: a space, a newline, a leading `-`, a Windows spelling, NUL framing |
| `boundary` | an edge the happy path never reaches: no start point, a missing one among good ones, a fatal reference, nesting, a reused instance name |
| `perf` | a [`PLAN.md`](PLAN.md) §5 P1 gate, asserted with a loose ceiling |

**Where the registry cases live.** The `TUTIL_OUT_PREFIXES` registry (PLAN §2.6)
is this unit's change to **tutil**, and its own cases — the registry name refused
as an out-name, the fail-closed behaviour of an empty / unset / scalar registry,
and the restored registry working again — are in
**[`../tutil/tests/001_Core.sh` §C](../tutil/tests/001_Core.sh)** (tutil 001 went
64 → 74 cases at this unit's P0, and 9 of those 10 were red against the
pre-registry `tutil._badOut`). This file's rows cover only the **tfind side**:
that `__tfd_` is registered, that the family prefixes are still refused through a
`TFind` instance, and that the registry survives a refusal aimed at it.

**Deliberate gaps** (each is stated in [`PLAN.md`](PLAN.md) §1.3 and restated in
[README.md](README.md)):

* **`-H` / `-P`** — the default is `-P`; wontfix, nothing to assert.
* **`-regex`, `-path`, `-size`, `-mtime`, `-empty`, the boolean operators and
  groups** — `addArg` territory, pinned as *argv position* (004 §D) rather than
  as behaviour of find's own predicates.
* **order-incompatible predicates** (`-quit`, `-prune`, `-delete`, **C13**) —
  they must precede or replace the action, which this builder pins last, so they
  are documented as hand-built (`print0 = 0` + a manual `nul`) and only their
  **refusal under `print0 = 1`** is asserted (004 §E).
* **BSD find** (D4) — nothing to assert on this box.
* **UNC start points** (`\\host\share`) — the tool itself refuses them.
* **permission-denied traversal** (**C20**) — `chmod 000` and `icacls /deny` do
  not stop find on this box, so no such test is possible here.
* **find's own stderr** — the tool's `find: …` lines pass through by design and
  their quoting follows the locale, so `005`/`006` count *our* lines and the
  tool's separately and match the tool's by **prefix** only.

---

## 004_Argv.sh — typed options to argv, nothing executed (P0) — 110 cases

**find is never started in this file.** Every case either compares the array
`f.argv GOT` handed over, or asserts a refusal.

### A. F4 lifecycle, and the out-name registry (20)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.a-vars-present | Create | every declared var (TFind's 9 + TUtil's 5) is present in `${inst}_data` right after `new` | contract | **F4**, §2.1 |
| 004.a-defaults | Create | the documented defaults: strings `''`, booleans `0`, `cmd` `find`, `_lastRc` `-1` | contract | **F4**, §1.2 |
| 004.a-args-empty | Create | `${f}_args` is EMPTY after `TFind.new f START` | contract | **F4**, §2.1 — the `inherited`-in-a-constructor trap would have made `cmd` the first start point and doubled the rest |
| 004.a-paths-verbatim | Create | `${f}_paths` holds every constructor argument verbatim, once each (a space, `./-weird`, a NEWLINE, `)paren`) | representation | **F4**, §2.1 |
| 004.a-no-arg | Create | `TFind.new f` with no argument leaves the start-point list empty — find's own `.` | boundary | **F4**, §2.1 |
| 004.a-reuse-clean | Create | a REUSED instance name starts clean: every var re-assigned, `_paths` replaced (`.new` does NOT clear `_data`) | boundary | **F4**, §2.1 |
| 004.a-delete-chains | Destroy | `delete` removes `_paths`, `_args` AND `_argv` (the descendant destructor chains with `inherited`) | contract | **F4**, §2.1 |
| 004.a-argv-nothing | argv | `argv` RUNS NOTHING — with `cmd` pointed at a function that would touch a flag file, the flag stays absent and the 4-word argv is still built | contract | **F1**, §1.2 |
| 004.a-badout-tfdv | argv | `f.argv __tfd_v` → rc 2 (TFind's own local prefix) | contract | **F4**, §2.6, **C1** |
| 004.a-badout-tfdp | argv | `f.argv __tfd_p` → rc 2 | contract | **F4**, §2.6, **C1** |
| 004.a-badout-tfda | toArray | `f.toArray __tfd_a` → rc 2, refused BEFORE anything runs | contract | **F4**, §2.6, **C1** |
| 004.a-badout-tu | argv | `f.argv __tu_x` is still rc 2 (TUtil's own prefix) | contract | **F4**, §2.6 |
| 004.a-badout-tg | argv | `f.argv __tg_x` is still rc 2 (tgrep) | contract | **F4**, §2.6 |
| 004.a-badout-th | argv | `f.argv __th_x` is still rc 2 (thead) | contract | **F4**, §2.6 |
| 004.a-badout-tt | argv | `f.argv __tt_x` is still rc 2 (ttail) — all five prefixes are one registry now | contract | **F4**, §2.6, **C1** |
| 004.a-badout-paths | argv | `f.argv fA_paths` → rc 2 (the instance's own start-point array) | contract | **F4**, §2.6 |
| 004.a-badout-registry | argv | `f.argv TUTIL_OUT_PREFIXES` → rc 2 — **the registry's own NAME is reserved** | contract | **F4**, §2.6, **C1** (blocker) |
| 004.a-registry-intact | argv | after that refusal the registry still holds exactly the five prefixes — without the reserved-name case one call replaced it with the argv and disarmed the guard process-wide | contract | **F4**, §2.6, **C1** |
| 004.a-registry-idempotent | *(load)* | sourcing `tfind.sh` twice more does NOT append `__tfd_` again: one entry, five in all | contract | **F4**, §2.6 |
| 004.a-badout-recovers | argv | an ordinary out-name still fills after every refusal above | contract | **F4**, §2.6 |

### B. F1 — every option, singly (11)

Each case resets the instance, sets exactly one property, and compares the whole
array. Class `argv`, basis **F1**, §1.2 throughout.

| ID | Case |
|---|---|
| 004.b-none | no option at all — `find START` (find's implied `-print`) |
| 004.b-name | `name = '*.txt'` → `-name '*.txt'` as TWO words |
| 004.b-iname | `iname = '*.TXT'` → `-iname` |
| 004.b-type-f | `type = f` → `-type f` |
| 004.b-type-list | `type = f,d` → `-type f,d` (a comma list is ONE word) |
| 004.b-maxdepth | `maxDepth = 2` → `-maxdepth 2` |
| 004.b-mindepth | `minDepth = 1` → `-mindepth 1` |
| 004.b-newer | `newer = ref` → `-newer ref` |
| 004.b-print0 | `print0 = 1` → `-print0` as THE action, last |
| 004.b-follow | `followSymlinks = 1` puts `-L` **before** the start points — the only place find accepts it (§6; an `addArg -L` would land after them) |
| 004.b-pattern-one-word | a pattern holding a glob, a space and a `[` is ONE argv element, never expanded or re-split by the wrapper |

### C. F1 — combinations, the pinned order, the boolean rule (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.c-global-first | the global option is emitted BEFORE the test whatever the caller's assignment order | argv | **F1**, §2.2 |
| 004.c-full-order | `-maxdepth` before `-mindepth` before `-name`/`-iname` before `-type` | argv | **F1**, §2.2 |
| 004.c-everything | EVERYTHING at once, two start points: `find -L 'dir one' 'dir two' -maxdepth 9 -mindepth 0 -name 'x y' -type d -newer 'ref file' -print0` | argv | **F1**, §1.2 |
| 004.c-boolean | a boolean is ON only for the exact string `1`: `2`, `yes`, `true`, `on`, `TRUE`, `-1`, `'1 '`, `' 1'`, `01`, `''`, `0` are all OFF (never `(( x ))`) | contract | §6 |

### D. F1 — start points are positional, no `--`, extras in place (15)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.d-nostart | NO start point at all — bare `find` (find's own `.`) | boundary | **F1**, §2.1 |
| 004.d-nostart-expr | no start point but an expression — `find -maxdepth 1 -name 'x*'`, which the tool accepts | boundary | **F1**, §1.1 |
| 004.d-three | three start points, all BEFORE the expression, no `--` | argv | **F1**, §2.1 |
| 004.d-dot-weird | `./-weird` is a legal start point — the `./` is what saves it | representation | **F1**, **C3**, §2.1 |
| 004.d-paren-comma | `)paren` and `,comma` are fine — only `-`, `!` and `(` are refused | representation | **F1**, §1.1 |
| 004.d-windows | a Windows-spelled start point (`C:\Users\x\tree`) travels verbatim | representation | **F1**, **C11**, §1.1 |
| 004.d-extra-after | an `addArg` extra lands AFTER the typed tests | argv | **F1**, §1.2 |
| 004.d-extra-before-action | extras sit between the typed tests and the action — `-print0` stays last | argv | **F1**, §1.2 |
| 004.d-group | a parenthesised group through `addArg` keeps its words | argv | **F1**, §1.3 |
| 004.d-clearargs | `clearArgs` empties the extras again | contract | **F1** |
| 004.d-paths-replace | `f.paths new1 'new 2'` REPLACES both old start points | contract | **F1**, §1.2 |
| 004.d-paths-none | `f.paths` with NO argument is the empty list = find's own `.` | boundary | **F1**, §2.1 |
| 004.d-no-dashdash | `--` is NEVER emitted, in **three** shapes (bare, typed options, print0 + extra + `-L`) — it ends the OPTION list only and cannot rescue a start point | argv | **F1**, **C3**, §1.1 |
| 004.d-no-accumulate | rebuilding does not ACCUMULATE: two `argv` calls agree word for word | contract | **F1** |
| 004.d-argv-copy | `argv` hands over a COPY — tampering with it does not touch `${inst}_argv` | contract | **F1** |

### E. F2 — the rc 2 list: nothing runs, `RESULT ''`, one line (40)

Every case asserts **five** things at once: rc 2, `RESULT ''`, the caller's array
**untouched**, `${inst}_argv` **EMPTY** (no stale command line can run
afterwards), and exactly **one** `kk.debug` line naming the reason. Class
`contract`, basis **F2** throughout.

| ID | Refusal | Extra basis |
|---|---|---|
| 004.e-cmd-empty | `cmd` is `''` (the instance was disarmed by hand) | §2.1 |
| 004.e-start-empty | a start point that is `''` — find's own `'': No such file or directory` | **C7** |
| 004.e-start-empty-among | an empty start point among GOOD ones | **C7** |
| 004.e-start-dash | a start point beginning with `-` (find reads it as a predicate) | **C3**, §2.1 |
| 004.e-start-dash-only | a start point of exactly `-` — it is NOT stdin for find | §1.1 |
| 004.e-start-bang | a start point beginning with `!` | §2.1 |
| 004.e-start-paren | a start point beginning with `(` | §2.1 |
| 004.e-start-anywhere | a refused start point ANYWHERE in the list, not only first | §2.1 |
| 004.e-type-x | `type = x` (outside `^[bcdflps](,[bcdflps])*$`) | §2.2 |
| 004.e-type-upper | `type = D` — uppercase is not in the class | §1.1 |
| 004.e-type-trailing | `type = 'f,'` | §2.2 |
| 004.e-type-leading | `type = ',f'` | §2.2 |
| 004.e-type-concat | `type = fd` — a list is comma separated, not concatenated | §2.2 |
| 004.e-type-space | `type = 'f d'` — never re-split into two words | representation |
| 004.e-max-x | `maxDepth = x` (`kk.isInt`) | §2.2 |
| 004.e-max-neg | `maxDepth = -1` — negative | §2.2 |
| 004.e-max-frac | `maxDepth = 1.5` | §2.2 |
| 004.e-max-blank | `maxDepth = ' 2'` — no surrounding blanks | §2.2 |
| 004.e-min-x | `minDepth = x` | §2.2 |
| 004.e-min-neg | `minDepth = -2` | §2.2 |
| 004.e-p0-action-`<w>` **(14 cases)** | `print0 = 1` together with the action extra `<w>`, one case for **each** word of the §2.3 set: `-print -print0 -printf -fprint -fprint0 -fprintf -ls -fls -exec -execdir -ok -okdir -delete -quit` | **C2** (blocker), §2.3 |
| 004.e-p0-action-late | the action word is NOT first among the extras — the WHOLE list is scanned | **C2** |
| 004.e-p0-off-ok | `print0 = 0` with the SAME `-exec` extra BUILDS fine — the extra's output is then the record stream | §1.3 item 3 |
| 004.e-p0-nonaction-ok | `print0 = 1` with a NON-action extra (`-size +0`) builds fine | §2.3 |
| 004.e-p0-substring-ok | an extra that merely CONTAINS an action word (`-execute`, `-printx`) is NOT refused — the match is on the WHOLE word | §2.3 |
| 004.e-p0-value-refused | `print0 = 1` + `addArg -name '-exec'` IS refused: the wrapper scans words and does not parse find's grammar — a **documented over-refusal**, with `print0 = 0` + a manual `nul` as the hatch | §2.3, README §5 |
| 004.e-each-alone-ok | each refused *ingredient* on its own (`type = f`, `maxDepth = 0`, `minDepth = 0`, `print0 = 1`, `addArg -delete`) builds fine — only the COMBINATION and the malformed values are refused | boundary |

### F. F3 — the depths are emitted from `$__KK_INT` (11)

`-maxdepth +1` is the **tool's** rc 1 (*Expected a positive decimal integer … got
'+1'*), so the wrapper emits the NORMALISED value. This is the **opposite**
decision from thead/ttail, where the sign is meaning and `kk.isInt` is forbidden.
Class `argv`, basis **F3**, **C9**, §2.2.

| ID | Case |
|---|---|
| 004.f-max-08 | `maxDepth = 08` → `-maxdepth 8` |
| 004.f-max-plus1 | `maxDepth = +1` → `-maxdepth 1` (verbatim would be the tool's rc 1) |
| 004.f-max-0 | `maxDepth = 0` → `-maxdepth 0` |
| 004.f-max-minus0 | `maxDepth = -0` → `-maxdepth 0` (and it is not refused as negative) |
| 004.f-max-007 | `maxDepth = 007` → `-maxdepth 7` |
| 004.f-min-08 | `minDepth = 08` → `-mindepth 8` |
| 004.f-min-plus2 | `minDepth = +2` → `-mindepth 2` |
| 004.f-min-0 | `minDepth = 0` → `-mindepth 0` |
| 004.f-no-writeback | the property still READS what the caller wrote (`08`, `+2`) after a build — only the ARGV is normalised, the OUTVAR form of `kk.isInt` would have rewritten it through the property nameref |
| 004.f-intmax | a depth above INT_MAX (`2147483648`) PASSES the guard and reaches find — *Numerical result out of range* is the TOOL's rc 1 (parity, 005 §H) |
| 004.f-type-dup | `type = f,f` PASSES the regex on purpose — the duplicate is the TOOL's rc 1 (**C8**, parity, 005 §H) |

### G. F5 — `print0` derives the sinks' `-0` (6)

The four-state sequence of tgrep 004 §G. Class `contract`, basis **F5**, §2.3.

| ID | Case | Extra basis |
|---|---|---|
| 004.g-derive | `print0 = 1` derives `nul = 1` and `_nulDerived = 1`; the argv ends in `-print0` | §2.3 |
| 004.g-undo | `print0 = 0` again takes the derived `-0` back off (both flags to 0) | §2.3 |
| 004.g-manual | a MANUAL `nul = 1` with `print0 = 0` is the caller's and survives a build untouched | §2.3 |
| 004.g-p3f1 | **P3-F1**: a deriving build does not CLAIM a `nul = 1` the caller already set — through `-print0` and back, `nul` stays the caller's 1 and `_nulDerived` never claims it | **P3-F1** |
| 004.g-refused | a REFUSED build derives nothing: the rc 2 path returns before the rule | **F2** |
| 004.g-crlf | `crlf` is never touched by `buildArgv` | contract |

### H. F5b — the caller-side glob trap (3)

The `cd` happens in **this file's own shell** and is undone immediately (never in
a subshell — **C5**, D6). Basis **F5b**, **C15**, §2.2.

| ID | Case | Class |
|---|---|---|
| 004.h-unquoted | `f.name = *.txt` UNQUOTED in a directory with two `.txt` files keeps ONE word — `one.txt` — silently; the argv carries `-name one.txt` | representation |
| 004.h-quoted | `f.name = '*.txt'` QUOTED keeps the pattern, which reaches find as one argv element | representation |
| 004.h-cd-undone | the `cd` was undone — this file's shell is back in its own directory | contract |

---

## 005_Run.sh — TFind against GNU find on a real tree (P0) — 49 cases

Oracle = the bare tool on the same fixture. Every comparison is NUL framed and
`sort -z`ed unless the case is *about* the `-print` framing.

### Z. the banner gate and the fixture (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.z-banner | the `find` on PATH is GNU findutils — otherwise every case below is a loud SKIP and the count is unchanged | contract | **D4** |
| 005.z-fixture | the fixture tree is in place: 6 files incl. a space name, a newline name and `-weird/inside.txt`, plus (when the box allows) a real directory symlink and a broken one | contract | §4, **C19** |

### A. F6 — every typed option against the bare tool (13)

Class `tool-behaviour`, basis **F6**, §1.2 throughout.

| ID | Case |
|---|---|
| 005.a-none | no option at all — every entry of the tree, NUL framed, rc 0, `lastRc` 0, identical to `find FX -print0` |
| 005.a-name | `name = '*.txt'` |
| 005.a-iname | `iname = '*.txt'` also takes `b.TXT` |
| 005.a-type-f | `type = f` |
| 005.a-type-d | `type = d` |
| 005.a-type-fd | `type = f,d` (a comma list) |
| 005.a-max1 | `maxDepth = 1` |
| 005.a-max0 | `maxDepth = 0` is the start point itself |
| 005.a-min2 | `minDepth = 2` |
| 005.a-newer | `newer = $FX/a.txt` |
| 005.a-case-sensitive | `-name` is case-**SENSITIVE** on NTFS under msys: `b.txt` finds nothing, `b.TXT` finds one (**C14**) |
| 005.a-iname-case | `iname = 'B.txt'` matches it whatever the case (**C14**) |
| 005.a-combined | `maxDepth` + `minDepth` + `type` together == the same bare expression |

### B. F6 — symlinks: `-L` vs the default `-P` (3)

A second gate (`kt_symlinks_supported` / `kt_make_symlink` from
[`../tdirectory/tests/symlink_helper.sh`](../tdirectory/tests/symlink_helper.sh)
— **C19**): plain `ln -s` runs in COPY mode on MSYS and would silently make a
directory copy. Class `tool-behaviour`, basis **F6**.

| ID | Case | Extra basis |
|---|---|---|
| 005.b-p-default | the DEFAULT (`-P`) does NOT descend the directory symlink — no record under `link/`, identical to the bare tool | §1.1 |
| 005.b-l-descends | `followSymlinks = 1` (`-L`) DOES descend it — the same files plus exactly 2 under `link/`, identical to `find -L` | §1.1 |
| 005.b-l-type-l | `type = l` under `-P` is BOTH links; under `followSymlinks = 1` only the **broken** one — the documented near no-op | **C12** |

### C. F7 — exotic names and the `-print` framing (4)

Class `representation`, basis **F7**.

| ID | Case | Extra basis |
|---|---|---|
| 005.c-newline-print | the newline name is **TWO** records under `-print` (`print0 = 0`), exactly as the bare `-print` splits it | **C6**, §2.3 |
| 005.c-newline-print0 | the SAME name is **ONE** record under `print0 = 1` — which is why the README leads every sink example with it | **C6**, §2.3 |
| 005.c-space | a name with a SPACE arrives as one record, intact | §4 |
| 005.c-weird-abs | an absolute path INTO `-weird` is a fine start point (it does not begin with `-`): 2 records, identical to the bare tool | §2.1 |

### D. F8 — a missing start point (partial) vs a missing `newer` (fatal) (5)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.d-partial | good + MISSING start point: records **KEPT**, `RESULT` = the real count, rc 1, `lastRc` 1, identical to the bare tool's own partial output | boundary | **F8a**, §2.4 (a) |
| 005.d-partial-onelines | the partial-failure path emits exactly **ONE** line of ours (`TFind` … `find exited 1`) while find's own `find: …` passes through, matched by PREFIX | contract | **F8a**, §2.4 (b) |
| 005.d-partial-sinks | `count` and `each` keep everything too, and `first` is still **rc 0** with a record | boundary | **F8a** |
| 005.d-newer-fatal | `newer` = a MISSING file is **FATAL**: zero records, the array emptied, rc 1, `lastRc` 1 — *not* the partial case | boundary | **F8b**, **C10** |
| 005.d-missing-alone | a MISSING start point ALONE — zero records, rc 1, `lastRc` 1 | boundary | **F8b** |

### E. F9 — the empty start-point list is find's own `.` (4)

The `cd` happens in **this file's own shell** and is undone; in a subshell the
sink would fill its array where the assertion cannot see it and D6 would fire
(**C5**).

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.e-cwd | no start point at all — every record begins `.` / `./…`, identical to bare `find -print0` | boundary | **F9**, §2.1 |
| 005.e-dot-weird | `./-weird` IS a legal start point: 2 records, identical to the bare tool | representation | **F9/F7**, **C3** |
| 005.e-bare-weird | the bare `-weird` is the wrapper's rc 2 — nothing ran, the caller's array untouched | contract | **F9/F7**, **C3** |
| 005.e-cd-undone | the `cd` was undone in THIS file's shell (never in a subshell) | contract | **C5**, **D6** |

### F. F10 — actions through `addArg` (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.f-exec-stream | `print0 = 0` + `-exec printf 'X:%s\n' {} \;` — the exec output **IS** the record stream; the implied `-print` was suppressed by the action, identical to the bare tool | tool-behaviour | **F10a**, §1.3 item 3 |
| 005.f-exec-semicolon | `-exec false {} \;` is **rc 0 with ZERO records** and not one diagnostic — deviation (c): the `\;` form swallows the child's status | tool-behaviour | **F10a**, **C4**, §2.4 (c) |
| 005.f-exec-plus | the SAME command as `-exec false {} +` **propagates**: rc 1, `lastRc` 1, one line of ours | tool-behaviour | **F10a**, **C4**, §2.4 (c) |
| 005.f-print0-size | `print0 = 1` + `addArg -size +0` keeps the NUL framing (the fixture files hold `x\n`), the newline name still ONE record, identical to the bare tool | representation | **F10b**, **C16** |

### G. F11 — `TFind.byName PATTERN START...` (10)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g-direct | `TFind.byName '*.txt' DIR` == `find DIR -name '*.txt'`, called DIRECTLY | tool-behaviour | **F11**, §2.5 |
| 005.g-pipe | the same through a PIPE (`\| od -c`) — byte-identical | contract | **F11** |
| 005.g-procsub | the same through `< <( )` — byte-identical | contract | **F11** |
| 005.g-two-starts | `byName` with TWO start points searches both | boundary | **F11** |
| 005.g-no-start | `byName` with NO start point is rc 2, prints nothing, one line — with none find would search the CALLER's cwd, which nobody means in a one-liner | contract | **F11**, §2.5 |
| 005.g-refused-start | a REFUSED start point propagates rc 2 out of `byName` through `run` | contract | **F11**, §2.5 |
| 005.g-missing-start | `byName` on a MISSING start point is rc 1 (find's own status, mapped), one line of ours, find's own passed through | contract | **F11**, §2.4 |
| 005.g-seq | `byName` deletes its throw-away instance and bumps `__TFD_SEQ` by one per call — nothing left behind | contract | **F11**, §2.5 |
| 005.g-nested | a nested `byName` inside an outer `each` — both complete, every inner answer correct, and the OUTER instance's argv and `lastRc` are untouched (the `${BASHPID}_${SEQ}` name is what makes this safe) | boundary | **F11**, §2.5 |
| 005.g-tpipe-both | `byName` composes with BOTH TPipe forms: `TPipe.each cb -- TFind.byName …` and, in a child with `shopt -s lastpipe`, a real pipe | contract | **F11** |

### H. F3 — the values the wrapper passes through (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.h-type-dup | `type = f,f` builds and is the TOOL's rc 1 (`lastRc` 1, one line of ours, find's own by prefix) — parity, not a second opinion | tool-behaviour | **F3**, **C8** |
| 005.h-depth-norm | `maxDepth = +1` really is DEPTH 1 and `= 08` really is DEPTH 8 against the bare tool — a verbatim `+1` would have been the tool's rc 1 | tool-behaviour | **F3**, **C9** |
| 005.h-intmax | a depth above INT_MAX reaches find and is its OWN rc 1 | tool-behaviour | **F3**, **C9** |
| 005.h-sinks-agree | every sink agrees on the same instance — `each` / `count` / `toArray` / `first` / `toList` / `run` all deliver the same record count | contract | **F6** |

---

## 006_Contract.sh — the kcl contract for TFind (P0) — 57 cases

### 0. source integrity (14)

Two earlier mechanical sweeps corrupted kcl sources while tests stayed green, so
this section reads the file itself. Class `contract` throughout.

| ID | Case | Basis |
|---|---|---|
| 006.0-parse | the unit source parses (`bash -n`) | §6 |
| 006.0-open-quote | no single-quoted `printf` format is left open at end of line | §6 |
| 006.0-inline-cr | no member body carries an inline `$'\r'` (it does not survive `build`) | §6 |
| 006.0-this | no internal member call is spelled `$this.NAME` | tutil PLAN §2.2 |
| 006.0-sentinel | the red-first skeleton sentinel `__TFIND_PENDING__` is GONE | §5 |
| 006.0-ctor | the CONSTRUCTOR calls `parent.constructor find`, never `inherited` — the front-end rewrites `inherited` to `parent.constructor "$@"` and would make `cmd` the first start point | §2.1 |
| 006.0-dtor | the DESTRUCTOR frees `${inst}_paths` and then chains with `inherited` | §2.1 |
| 006.0-regex-var | the `type` regex is held in a VARIABLE and applied with `[[ =~ $re ]]` — an inline pattern does not survive `build`'s `declare -f` round trip | §6 |
| 006.0-kkint | the depths are emitted from `$__KK_INT`, never from the property | §2.2, **C9** |
| 006.0-no-dashdash | the builder never emits a `--` word | §1.1, **C3** |
| 006.0-class-not-negated | the start-point class is `[-!\(]*`, **not** the NEGATED `[!-(]*` (which would silently stop refusing `-x`); comment lines are stripped first because this file's own prose names the wrong spelling | §6, **C18** |
| 006.0-no-shadow | no `var` shadows a TUtil or kklass member name, and there are exactly **9** of them (a method wrapper is generated after the property wrapper and wins silently) | tutil PLAN §1.2 |
| 006.0-one-source | the unit sources ONLY `../tutil/tutil.sh` | §1.4 |
| 006.0-registered | the unit registered `__tfd_` in `TUTIL_OUT_PREFIXES` at load — exactly once, five entries | §2.6, **C1** |

### Z. the banner gate (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.z-banner | the `find` on PATH is GNU findutils; otherwise every case that runs find is a loud SKIP | contract | **D4** |

### 1. `set -eu` — the instance and both TPipe forms, every outcome (21)

Each `expect_clean` case runs its snippet in a **child** under `set -eu` with the
unit freshly sourced, and asserts rc 0, stdout exactly `OK`, and **empty
stderr**. `$FX`/`$UNIT` reach the child through the environment; every sink call
inside is guarded `|| rc=$?`. Class `contract` throughout, basis **F12**.

| ID | Case |
|---|---|
| 006.1-load | the unit loads under `set -eu` |
| 006.1-load-twice | it loads TWICE (every re-source guard holds, and the registry append stays idempotent) |
| 006.1-each | `f.each`: an instance that delivers records — rc 0, 2 calls, `lastRc` 0 |
| 006.1-tpipe-argv | form 2: `TPipe.each CB -- "${argv[@]}"` with the argv TFind built (4 words) |
| 006.1-tpipe-byname | form 2 with `TFind.byName` as the producer command |
| 006.1-lastpipe | form 1: a REAL pipe under `shopt -s lastpipe` |
| 006.1-func-sinks | every func sink on an instance that delivers: `toArray`, `count`, `first` |
| 006.1-tolist | `toList` into a kklass instance with an `.Add` — offered 2, stored 2 |
| 006.1-tool-error | a TOOL ERROR (a missing start point, raw 1) — rc 1, 0 records, `lastRc` 1, the child survives |
| 006.1-partial | a PARTIAL failure — rc 1, records KEPT, `RESULT` == what was kept, `lastRc` 1 |
| 006.1-refused-start | a REFUSED build (a start point beginning with `-`) — rc 2, nothing ran, `lastRc` still `-1` |
| 006.1-refused-action | a REFUSED build (`print0` + an action extra) — rc 2 from `toArray`, `count` AND `run` |
| 006.1-refused-cmd | an EMPTY `cmd` — rc 2 from every runner |
| 006.1-refused-values | a bad `type` and a bad `maxDepth` — rc 2, no abort |
| 006.1-refused-byname | `TFind.byName` with no start point — rc 2, nothing printed |
| 006.1-run-streams | `run` streams (its stdout is find's, byte for byte) and the raw rc is readable afterwards |
| 006.1-delete-clean | `delete` on an instance that never ran anything leaves no `_paths`/`_args` |
| 006.1-subst-once | the `$( )` position: a func sink prints its value exactly ONCE (a doubled value would mean `__TPIPE_QUIET` is not in place) |
| 006.1-cwd-form | `paths` with no argument is find's own `.` — it runs in the CHILD's cwd and the records read `./…` |
| 006.1-d6 | **D6 final**: `subshellOk = 1` silences TPipe's subshell warning through TFind (empty stderr), and without it the verbatim `Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — …` appears |
| 006.1-f12-unguarded | **F12**: an UNGUARDED sink call with rc 1 aborts a `set -eu` caller (nothing printed after it) while the guarded one reads rc 1 and carries on — the documented caller rule, not a defect |

### 2. the debug switch — one line per rc 2 / tool-error path (20)

`check_one` asserts the rc, **exactly one** line of ours with the switch ON, and
**zero** lines of ours with the switch OFF (find's own `find: …` lines are
counted separately and never suppressed). `check_silent` asserts **no** line of
ours at all. Class `contract`, basis §1.2 of the kcl README.

| ID | Case |
|---|---|
| 006.2-rc2-start-each | rc 2: a start point beginning with `-`, through `each` |
| 006.2-rc2-start-count | the same through `count` (every runner reports once, not twice) |
| 006.2-rc2-start-empty | rc 2: an EMPTY start point (**C7**) |
| 006.2-rc2-type | rc 2: a bad `type` |
| 006.2-rc2-depth | rc 2: a negative `maxDepth` |
| 006.2-rc2-action | rc 2: `print0` + an action extra (**C2**) |
| 006.2-rc2-cmd | rc 2: an empty `cmd` |
| 006.2-rc2-byname | rc 2: `TFind.byName` with no start point |
| 006.2-rc2-out-result | rc 2: `toArray RESULT` — a bad out-name (TUtil's own check) |
| 006.2-rc2-out-tfd | rc 2: `toArray __tfd_x` — the `__tfd_` prefix (§2.6) |
| 006.2-rc2-out-registry | rc 2: `toArray TUTIL_OUT_PREFIXES` — the registry's own NAME (**C1**) |
| 006.2-raw1-partial | find raw 1 (a missing start point among good ones) — rc 1 and one line |
| 006.2-raw1-alone | find raw 1 (the only start point missing) — rc 1 and one line |
| 006.2-raw1-newer | find raw 1 (`newer` on a missing file, fatal) — rc 1 and one line (**C10**) |
| 006.2-silent-count | rc 0: a successful `count` says NOTHING |
| 006.2-silent-each | rc 0: `each` on records says NOTHING |
| 006.2-silent-toarray | rc 0: `toArray` on records says NOTHING |
| 006.2-silent-byname | rc 0: a `TFind.byName` that succeeded says NOTHING |
| 006.2-names-tfind | the `find exited` line names **TFind**, and find's OWN line is left alone |
| 006.2-registry-survived | the registry survived every refusal above and still holds five prefixes (**C1**) |

### 3. a Windows-spelled start point (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.3-winpath | **F12**: a `C:\…` start point (from `cygpath -w`, SKIP without it) yields records carrying that spelling as a **PREFIX** with `/` after it — pinned as prefix + separator, never as whole-record equality | representation | **F12**, **C11**, §1.1 |

---

## 007_Bench.sh — the PLAN §5 P1 performance gate (P1) — 10 cases

Class `perf` throughout (except the banner gate). **Two sets of numbers on
purpose**: [`../bench.sh`](bench.sh) measures the real **1.5×** gate by hand on
an idle box from the medians of 21 interleaved runs; this file asserts the same
shapes with a **10×** ceiling, because ktests runs test files threaded (8
workers) and the two sides of the ratio do not inflate together — `find` is its
own process while the wrapper's share is bash work in the contended shell. The
clock is `TStopwatch.getTimeStamp`; `date +%s%N` is forbidden here (~20 ms per
call on msys, paid twice per sample — **C17**).

| ID | Case | Basis |
|---|---|---|
| 007.z-banner | the `find` on PATH is GNU findutils — otherwise every timed case is a loud SKIP, count unchanged | **D4** |
| 007.a-gate-tree | `TFind.byName '*.txt'` over a 20-file tree costs at most **10×** a bare `find … -name '*.txt'`, from the MEDIANS of 7 INTERLEAVED runs, with both sides asserted to deliver the same 20 records | §5 P1, **C17** |
| 007.a-gate-one | the same over a **ONE-file** tree — the shape that shows corpus size is not the knob (the fork dominates both sides) | §5 P1, **C17** |
| 007.a-delta | the `byName` delta IS one instance: `new` + `name =` + `argv` + `delete` under 50 ms/call (~4.7 ms idle; nine properties where thead has six) | §5 P1 |
| 007.b-argv-nothing | 200 `buildArgv`/`argv` calls invoke the `cmd` **zero** times, never fork (`$BASHPID`), and build the 8 words in the pinned order | **F1**, §5 P1 |
| 007.b-argv-constant | the build stays constant-cost: 201 rebuilds do not accumulate words | **F1** |
| 007.b-refused-cheap | a REFUSED build is the cheap path too: 100 rc 2 calls invoke the `cmd` zero times, fork nothing, and leave `${inst}_argv` empty | **F2** |
| 007.c-count | `f.count` over 20 records costs at most 10× `find … -print0 \| tr -dc '\0' \| wc -c` — published, **not** the gate. Unlike thead's `wc -l` row this comparison is not one-sided: the shell equivalent needs THREE processes where the sink needs one, so at a small record count the **sink is faster** | §5 P1 |
| 007.d-sinks-fork | the five sinks: the callback and `.Add` run in THIS process, one record each | **F12** |
| 007.d-members-fork | the ONLY fork per call is find: twelve builder members, `run`, `byName` and **both rc 2 paths** leave `$BASHPID` untouched | **F12** |
