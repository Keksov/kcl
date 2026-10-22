# tsed — test coverage notes

**Status: FINALIZED at P1 (2026-09-23); extended at L2.7-C and H1.** Suite
`004`–`008` = **402 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single` (5.2.37), against **GNU sed 4.9**
(5.2.37 resolves Git for Windows' `sed.exe`, 5.3.9 msys64's). The per-file row
counts below sum to **402** — 160 + 78 + 66 + 11 + 87 (`004`–`008`; 293 at
P1, 315 after L2.7-C, 402 after H1) — and **every case in the suite has a
row**.

**H1 (launch L2.7-H, 2026-10-22):** `008_Helpers.sh` adds **87 cases** (the
last section); the suite is now **402** — `004` 160, `005` 78, `006` 66, `007`
11, `008` 87 — green on both bashes.

**Protocol.** `TSed` has no FPC upstream: it is the fifth wrapper on
[`TUtil`](../../../tutil/README.md), which is itself a kcl addition (see
[../tutil/docs/TUtil.md](../../../tutil/docs/TUtil.md)). The oracle is therefore **the
bare GNU tool on the same fixture**, run with the same arguments, never a second
call into the code under test. Decision **D4** (of the tpipe plan) pins the
*dialect* — GNU sed 4.9, identical under both target bashes although they
resolve two different binaries — not a binary, so every behavioural file opens
with the **GNU banner gate**: if `sed --version` does not begin with
`sed (GNU sed) `, every behavioural case is a loud SKIP and the case **count is
unchanged**.

The suite splits in two on purpose:

* **`004_Argv.sh` never executes sed.** Every typed option is pinned by
  comparing the built array, which is what `argv NAME` exists for; it is the fast
  half and it is where a wrapper's surface — and this unit's deny-list — lives.
* **`005`/`006`/`007` run the tool** on a fixture tree chosen for the traps: a
  3-line file (`a1 b2 c3`) and a second 2-line file, a CRLF file, a file ending
  in `\r\r\n`, a NUL-separated file with a CRLF **inside** a record and an
  unterminated last record, an unterminated last line, `a1` (for the ERE
  back-reference), a script file, a name with a space, a name starting with `-`,
  and a directory. In-place cases edit **copies** and assert the bytes with
  `od -c`; the sandbox cases prove "nothing ran" with **marker files**. CR
  fixtures are written with `printf`, never through an array literal.

The Basis column cites one of:

* **S1–S13** — a pinned fact of [`PLAN.md`](PLAN.md) §3.
* **Q1–Q6** — an owner decision of [`PLAN.md`](PLAN.md) §2.0.
* **C1–C18** — a finding of the 2026-09-22 critic pass ([`PLAN.md`](PLAN.md) §8).
  Every one of the eighteen is cited by at least one row below, or named under
  "deliberate gaps".
* **RR1** — review round 1 of P0 (2026-09-23, [`tsed_ledger.json`](tsed_ledger.json)):
  `sandbox` fails closed (12 cases of 004 and 1 of 006 were red against the P0
  source) and `--` among the extras is rc 2.
* **P0-dev** — the approved P0 deviation: the Q6 deny-list follows sed's getopt
  (unambiguous long-option abbreviations, the `--zero-terminated` alias, short
  options with an attached argument; `-l` stops the short scan).
* **P0-fact** — the P0 correction of PLAN §1.1: `*` in the in-place suffix is
  the **operand as given**, directory part included.
* **P3-F1** — the tgrep finding this unit inherits with its guard
  ([../tgrep/README.md §4](../../../tgrep/README.md)).
* **D4 / D6** — a decision: D4 the GNU dialect gate, D6 final `subshellOk`.
* **§n** — a section of [`PLAN.md`](PLAN.md) (or of [README.md](../../../tsed/README.md)).

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract ([../README.md](../../../README.md) §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `argv` | the typed option set → the pinned command line, asserted **without running sed** |
| `tool-behaviour` | what GNU sed 4.9 actually does, measured against the bare tool as oracle |
| `security` | the sandbox default (owner Q1): what it refuses, that it fails closed, that nothing ran |
| `representation` | paths, expressions and records are **data**: a space, a newline, a leading `-`, a CR, NUL framing, an unterminated tail |
| `boundary` | an edge the happy path never reaches: no script, no path, a missing file among good ones, an I/O error, nesting, a reused instance name |
| `perf` | a [`PLAN.md`](PLAN.md) §5 P1 gate, asserted with a loose ceiling |

**Where the registry cases live.** The `TUTIL_OUT_SUFFIXES` registry (PLAN §2.1)
is this unit's change to **tutil**, and its own cases — the registry
`_args _argv _paths` before any descendant, `uV_exprs` accepted before tsed
loads, the append on load, the registry's own NAME refused with the registry
intact, and the fail-closed EMPTIED / UNSET / SCALAR registry followed by the
restored one — are the twelve suffix-registry cases of
**[`../tutil/tests/001_Core.sh` §C](../../../tutil/tests/001_Core.sh)** (tutil went
197 → 209 at this unit's P0; 10 of the 12 were red against the unchanged tutil).
This file's rows cover only the **tsed side**: that `__tsd_` and `_exprs` are
registered once, that the family's names are still refused through a `TSed`
instance, and that the expression list survives every refusal.

**Deliberate gaps** (each is stated in [`PLAN.md`](PLAN.md) and restated in
[README.md](../../../tsed/README.md)):

* **BSD sed** (D4) — nothing to assert on this box.
* **`-i` on a symlink / across devices** (PLAN §1.3) — tool behaviour, not
  modelled.
* **a callback's bare assignment** (**C12**) — a callback that assigns a bare
  `sandbox=0` writes the instance's property through dynamic scoping; this is a
  documented caller rule (README §4, "callbacks declare `local`"), not a wrapper
  behaviour, so there is nothing of the unit's to assert.
* **`#n` and `a\` across `-e` chunks** (**C14**) — sed's own join semantics,
  documented (README §1); the join itself is pinned by the multi-`-e` block case.
* **`-i` implies `-s`** (**C18**) — documented; `separate` is inert under
  `inPlace` and nothing the wrapper does depends on it.
* **`F`, `=`, `l` under the sandbox** — allowed by sed and printed to stdout
  (PLAN §1.1, verified by the critic); documented, not re-asserted.
* **`tutil/docs/TUtil.md` §4** (**C13**) — a docs finding, closed at P0 by
  editing the row; no test.
* **sed's own stderr** — the tool's `sed: …` lines pass through by design and
  their quoting follows the locale, so `005`/`006` count *our* lines and the
  tool's separately and match the tool's by **prefix** only.

One title is stale and its assertion is not: **004.b-suffix-bak-star** still
says "base-name substitution" (written before the P0 measurement); the case pins
only the argv word `-ibak_*`, which is right either way, and 005 §G pins the
real behaviour (**P0-fact**). `tests/004_Argv.sh` is frozen at P0, so the title
is recorded here rather than edited.

---

## 004_Argv.sh — typed options to argv, nothing executed (P0; §CR added at L2.7-C) — 160 cases

**sed is never started in this file.** Every case either compares the array
`s.argv GOT` handed over, or asserts a refusal.

### A. S3 lifecycle and both out-name registries (22)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.a-vars-present | Create | every declared var (TSed's 11 + TUtil's 5, incl. `subshellOk`) is present in `${inst}_data` right after `new` — none unbound under `set -u` | contract | **S3**, §2.1 |
| 004.a-defaults | Create | the documented defaults: `expr` = argument 1, **`sandbox` 1**, the other flags `0`, strings `''`, `cmd` `sed`, `_lastRc` `-1`, `subshellOk` 0 | contract | **S3**, **Q1**, §2.1 |
| 004.a-args-empty | Create | `${s}_args` is EMPTY after `TSed.new s EXPR PATH` — the `inherited`-in-a-constructor trap would have made EXPR the command | contract | **S1**, **S3**, §2.1 |
| 004.a-paths-verbatim | Create | `${s}_paths` holds every argument after EXPR verbatim, once each (a space, `-dash`, a NEWLINE, `-`), and `${s}_exprs` is an EMPTY array | representation | **S3**, §2.1 |
| 004.a-no-arg | Create | `TSed.new s` with no argument: `expr` `''`, no path, no expression, `cmd` `sed` | boundary | **S3** |
| 004.a-reuse-clean | Create | a REUSED instance name starts clean — `expr`, `quiet`, `sandbox` (back to 1), `inPlace`, `backupSuffix`, both lists and the three `addReplace` arrays (H1) re-assigned (`.new` does NOT clear `_data`) | boundary | **S3**, §2.1 |
| 004.a-delete | Destroy | `delete` removes `_paths`, `_exprs`, `_rfrom`, `_rto`, `_rflags` (H1), `_args`, `_argv` and `_data` (the descendant destructor chains with `inherited`) | contract | **S3**, §2.1 |
| 004.a-argv-nothing | argv | `argv` RUNS NOTHING — with `cmd` pointed at a function that would touch a flag file, the flag stays absent and the 6-word argv is still built | contract | **S1**, §1.2 |
| 004.a-badout-tsdv | argv | `s.argv __tsd_v` → rc 2, one line naming the bad name (TSed's own local prefix) | contract | **S3**, §2.1 |
| 004.a-badout-tsdx | argv | `s.argv __tsd_x` → rc 2 | contract | **S3**, §2.1 |
| 004.a-badout-tsda | toArray | `s.toArray __tsd_a` → rc 2, refused BEFORE anything runs | contract | **S3**, §2.1 |
| 004.a-badout-exprs | argv | `s.argv sA_exprs` → rc 2 — the suffix registry's `_exprs` | contract | **S3**, **C3** |
| 004.a-badout-exprs-toarray | toArray | `s.toArray sA_exprs` → rc 2 — without it the records became the NEXT run's script | contract | **S3**, **C3** (major) |
| 004.a-badout-paths | argv | `s.argv sA_paths` → rc 2 (still refused, now through the registry) | contract | **S3**, §2.1 |
| 004.a-badout-args | argv | `s.argv sA_args` → rc 2 | contract | **S3**, §2.1 |
| 004.a-badout-sufreg | argv | `s.argv TUTIL_OUT_SUFFIXES` → rc 2 — the suffix registry's own NAME is reserved | contract | **S3**, **C3**, §2.1 |
| 004.a-badout-sufreg-toarray | toArray | `s.toArray TUTIL_OUT_SUFFIXES` → rc 2 | contract | **S3**, **C3** |
| 004.a-badout-prereg | argv | `s.argv TUTIL_OUT_PREFIXES` → rc 2 — the prefix registry's NAME too | contract | **S3**, §2.1 |
| 004.a-exprs-intact | — | after every refusal above the expression list is still `(s/b/B/ p)` and `expr` still `s/a/A/` | contract | **S3**, **C3** |
| 004.a-registries-once | *(load)* | both registries survived: `__tsd_` and `_exprs` registered exactly once; prefixes `(__tu_ __tg_ __th_ __tt_ __tsd_)`, suffixes `(_args _argv _paths _exprs _rfrom _rto _rflags)` (H1 added the last three) | contract | **S3**, §2.1 |
| 004.a-registries-idempotent | *(load)* | sourcing `tsed.sh` twice more appends NOTHING | contract | **S3**, §2.1 |
| 004.a-badout-recovers | argv | an ordinary out-name still fills after every refusal (`sed --sandbox -e s/a/A/ -e s/b/B/ -e p -- f.txt`) | contract | **S3** |

### B. S1 — every option, singly (16)

Each case resets the instance, sets one property (or the pair named), and
compares the whole array. Class `argv`, basis **S1**, §1.2 throughout.

| ID | Case | Extra basis |
|---|---|---|
| 004.b-none | no option at all — `sed --sandbox -e EXPR -- PATH` (sandbox by default) | **Q1** |
| 004.b-sandbox-0 | `sandbox = 0` drops `--sandbox` | **Q1** |
| 004.b-extended | `extended = 1` → `-E` | |
| 004.b-quiet | `quiet = 1` → `-n` | |
| 004.b-separate | `separate = 1` → `-s` | |
| 004.b-nulldata | `nullData = 1` → `-z` AND the derived `-b` | **Q5** |
| 004.b-binary | `binary = 1` → `-b` | |
| 004.b-inplace | `inPlace = 1` → the derived `-b`, then `-i` | **Q4**, **Q5** |
| 004.b-scriptfile | `scriptFile = s.sed` → `-f` AFTER the expressions | **Q2** |
| 004.b-suffix-bak | `backupSuffix = .bak` is ATTACHED to `-i` — one word, `-i.bak` | §2.2 |
| 004.b-suffix-bak-star | `backupSuffix = 'bak_*'` passes as `-ibak_*` (title predates **P0-fact**; see above) | **C7** |
| 004.b-suffix-dir | `backupSuffix = 'bk/*'` passes as `-ibk/*` (a directory; a missing one is the tool's rc 4) | **C7**, §2.2 |
| 004.b-suffix-space | a suffix with a space stays ONE argv word (`-i my bak`) | representation |
| 004.b-scriptfile-alone | `scriptFile` ALONE (`expr ''`) — no `-e` at all | **Q2** |
| 004.b-no-path | no path — no `--` (sed reads stdin) | §1.2 |
| 004.b-paths-after-dd | the paths follow `--` verbatim — `-weird`, `-` (stdin) and a space | representation |

### C. S1 — expressions, extras, the pinned order, the boolean rules (28)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.c-expr-first | `expr` FIRST, then every `addExpr` item in call order | argv | **S1**, **Q2** |
| 004.c-expr-empty-none | `expr = ''` means NONE — only the list is emitted | argv | **S1**, **Q2** |
| 004.c-identity | `addExpr ''` is a REAL element — `-e ''`, sed's identity | argv | **S1**, **C4** |
| 004.c-empty-slot | an empty element INSIDE the list keeps its slot | argv | **S1** |
| 004.c-newline-word | an expression holding a newline is ONE argv word | representation | **S1** |
| 004.c-clearexprs | `clearExprs` empties the list and keeps `expr` | argv | **S1**, **Q2** |
| 004.c-addexpr-noop | `addExpr` with no argument is a no-op | boundary | **S1** |
| 004.c-f-last | `-f` comes after ALL the expressions | argv | **S1**, **Q2** |
| 004.c-extra-position | an extra lands AFTER the typed options and BEFORE the first `-e` (`--sandbox -E --posix -e E0`) | argv | **S1**, §1.1 |
| 004.c-extras-order | several extras keep their order and their words (`-u -l 40 --follow-symlinks`) | argv | **S1** |
| 004.c-clearargs | `clearArgs` empties the extras again | contract | **S1** |
| 004.c-paths-replace | `s.paths new1 'new 2'` REPLACES both old paths | contract | **S1**, §1.2 |
| 004.c-paths-none | `s.paths` with NO argument is the stdin form — no `--` | boundary | **S1** |
| 004.c-everything | EVERYTHING at once, two paths: `sed --sandbox -E -n -s -z -b -i.bak --posix -u -l 40 -e E0 -e X1 -e X2 -f 'my script.sed' -- p1 'p 2'` — exactly ONE `-b` | argv | **S1**, **Q5**, §1.2 |
| 004.c-boolean | a boolean is ON only for the exact string `1`: `2`, `yes`, `true`, `on`, `TRUE`, `-1`, `'1 '`, `' 1'`, `01`, `''`, `0` are all OFF for `extended`, `quiet`, `separate`, `nullData`, `binary`, `inPlace` — every flag but `sandbox` (the loop no longer touches `sandbox` since **RR1**) | contract | §6, **RR1** |
| 004.c-sbx-empty | `sandbox = ''` → still `--sandbox` (fail closed) | security | **Q1**, **RR1** |
| 004.c-sbx-yes | `sandbox = yes` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-2 | `sandbox = 2` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-lead-space | `sandbox = ' 0'` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-trail-space | `sandbox = '0 '` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-00 | `sandbox = 00` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-false | `sandbox = false` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-off | `sandbox = off` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-minus0 | `sandbox = -0` → still `--sandbox` | security | **Q1**, **RR1** |
| 004.c-sbx-1 | `sandbox = 1` → `--sandbox` | security | **Q1** |
| 004.c-sbx-0 | `sandbox = 0` — the exact string, and the ONLY value — drops it | security | **Q1**, **RR1** |
| 004.c-no-accumulate | rebuilding does not ACCUMULATE — two `argv` calls agree word for word | contract | **S1** |
| 004.c-argv-copy | `argv` hands over a COPY — writing it does not touch `${inst}_argv` | contract | **S1** |

### D. S2 — the rc 2 list and the Q6 deny-list: nothing runs, `RESULT ''`, one line (68)

Every refusal case asserts **five** things at once: rc 2, `RESULT ''`, the
caller's array **untouched**, `${inst}_argv` **EMPTY** (no stale command line
can run afterwards), and exactly **one** `kk.debug` line naming the reason (for
a deny-list word: the property to use). Class `contract`, basis **S2**, §2.2
throughout.

#### D.1 the §2.2 list (9)

| ID | Refusal | Extra basis |
|---|---|---|
| 004.d-cmd-empty | `cmd` is `''` | §2.2 |
| 004.d-no-script | NO script at all (`expr ''`, no list, no `scriptFile`) — sed would read the path AS the script | §1.1, §6 |
| 004.d-no-script-cleared | no script after `addExpr E1; clearExprs` | §2.2 |
| 004.d-no-script-no-path | no script and no path | §2.2 |
| 004.d-inplace-no-path | `inPlace = 1` with NO path | **Q4** |
| 004.d-inplace-dash | `inPlace = 1` with the path `-` | **C15** |
| 004.d-inplace-dash-anywhere | `inPlace = 1` with `-` ANYWHERE in the paths (`good.txt -`) | **C15** |
| 004.d-suffix-no-inplace | `backupSuffix` with `inPlace = 0` | §2.2 |
| 004.d-suffix-star | `backupSuffix = '*'` — the backup name would BE the file: no backup, silently | **C7** |

#### D.2 the Q6 deny-list — the enumerated spellings (26)

Each case: `addArg WORD…` on an otherwise valid instance → rc 2, the line naming
the property. Extra basis **Q6**, **C2** (major) throughout.

| ID | `addArg` | property named |
|---|---|---|
| 004.d-deny-i | `-i` | `inPlace` |
| 004.d-deny-in-place | `--in-place` | `inPlace` |
| 004.d-deny-in-place-eq | `--in-place=.bak` | `inPlace` |
| 004.d-deny-z | `-z` | `nullData` |
| 004.d-deny-null-data | `--null-data` | `nullData` |
| 004.d-deny-e | `-e p` | `expr` |
| 004.d-deny-expression | `--expression p` | `expr` |
| 004.d-deny-expression-eq | `--expression=p` | `expr` |
| 004.d-deny-f | `-f s.sed` | `scriptFile` |
| 004.d-deny-file | `--file s.sed` | `scriptFile` |
| 004.d-deny-file-eq | `--file=s.sed` | `scriptFile` |
| 004.d-deny-n | `-n` | `quiet` |
| 004.d-deny-quiet | `--quiet` | `quiet` |
| 004.d-deny-silent | `--silent` | `quiet` |
| 004.d-deny-s | `-s` | `separate` |
| 004.d-deny-separate | `--separate` | `separate` |
| 004.d-deny-E | `-E` | `extended` |
| 004.d-deny-r | `-r` | `extended` |
| 004.d-deny-regexp-extended | `--regexp-extended` | `extended` |
| 004.d-deny-b | `-b` | `binary` |
| 004.d-deny-binary | `--binary` | `binary` |
| 004.d-deny-sandbox | `--sandbox` | `sandbox` |
| 004.d-deny-ni | `-ni` — a bundle; the first modelled letter is named | `quiet` |
| 004.d-deny-nE | `-nE` | `quiet` |
| 004.d-deny-us | `-us` — `-u` passes, the bundled `-s` does not | `separate` |
| 004.d-deny-ui | `-ui` | `inPlace` |

#### D.3 the same options in the other spellings sed's getopt reads identically (19)

Measured on sed 4.9: `--in=.bak` edited the file in place with rc 0. Extra basis
**Q6**, **P0-dev** throughout.

| ID | `addArg` | why it is the same option | property named |
|---|---|---|---|
| 004.d-deny-i-attached | `-i.bak` | a short option with its argument ATTACHED | `inPlace` |
| 004.d-deny-ni-attached | `-ni.bak` | a bundle ending in an attached `-i` | `quiet` |
| 004.d-deny-e-attached | `-es/a/b/` | `-e` with its script attached | `expr` |
| 004.d-deny-f-attached | `-fs.sed` | `-f` with its file attached | `scriptFile` |
| 004.d-deny-in-eq | `--in=.bak` | unambiguous prefix of `--in-place` | `inPlace` |
| 004.d-deny-in | `--in` | the same, without a value | `inPlace` |
| 004.d-deny-expr-eq | `--expr=p` | prefix of `--expression` | `expr` |
| 004.d-deny-fi-eq | `--fi=s.sed` | prefix of `--file` | `scriptFile` |
| 004.d-deny-null | `--null` | prefix of `--null-data` | `nullData` |
| 004.d-deny-zero-terminated | `--zero-terminated` | the undocumented alias of `-z` | `nullData` |
| 004.d-deny-zero | `--zero` | prefix of that alias | `nullData` |
| 004.d-deny-qui | `--qui` | prefix of `--quiet` | `quiet` |
| 004.d-deny-sil | `--sil` | prefix of `--silent` | `quiet` |
| 004.d-deny-sep | `--sep` | prefix of `--separate` | `separate` |
| 004.d-deny-reg | `--reg` | prefix of `--regexp-extended` | `extended` |
| 004.d-deny-bin | `--bin` | prefix of `--binary` | `binary` |
| 004.d-deny-sand | `--sand` | prefix of `--sandbox` | `sandbox` |
| 004.d-deny-sandbox-eq | `--sandbox=1` | a long form with `=VALUE` sed would itself reject | `sandbox` |
| 004.d-deny-quiet-eq | `--quiet=1` | the same | `quiet` |

#### D.4 `--` among the extras, and the whole-list scan (4)

| ID | Case | Extra basis |
|---|---|---|
| 004.d-dd | `addArg --` is rc 2 — `--` ends sed's options (measured: `sed --sandbox -- -e s/a/A/ -- f`, the expressions became operands); the wrapper emits its own `--` before the paths | **Q6**, **RR1** |
| 004.d-dd-middle | `--` in the MIDDLE of the extras (`-u -- --posix`) is rc 2 too | **RR1** |
| 004.d-dd-no-path | `addArg --` with NO path is rc 2 too | **RR1** |
| 004.d-deny-late | a denied word NOT first among the extras (`-u`, then `--posix -n`) is refused — the whole list is scanned | **Q6** |

#### D.5 what passes (10)

Class `argv` for the nine pass cases: the extra lands between the typed options
and the first `-e`, unchanged. Basis **Q6**, **P0-dev** (`-l` stops the short
scan).

| ID | Case |
|---|---|
| 004.d-pass-posix | `--posix` passes |
| 004.d-pass-u | `-u` passes |
| 004.d-pass-unbuffered | `--unbuffered` passes |
| 004.d-pass-l-40 | `-l 40` passes (two words) |
| 004.d-pass-l40 | `-l40` passes |
| 004.d-pass-ul40 | `-ul40` passes — `-u`, then `-l` whose argument `40` is never scanned as letters |
| 004.d-pass-line-length | `--line-length=40` passes |
| 004.d-pass-follow | `--follow-symlinks` passes |
| 004.d-pass-debug | `--debug` passes the BUILD (the sinks refuse it — 005 §G, 006 §2, 007 §D) |
| 004.d-ingredients-ok | each refused *ingredient* on its own builds: `inPlace` with a path, a suffix with `inPlace`, `-` without `inPlace`, `-f` alone, the identity — only the combinations are refused (class `boundary`) |

### E. S4 — `nullData` derives `-0` (P3-F1), and the derived `-b` (10)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.e-derive | `nullData = 1` DERIVES `nul = 1` and `_nulDerived = 1`; the argv has `-z -b` | contract | **S4**, §2.3 |
| 004.e-undo | `nullData = 0` again takes the derived `-0` back off (both flags to 0) | contract | **S4**, §2.3 |
| 004.e-manual | a MANUAL `nul = 1` with `nullData = 0` is the caller's and survives a build | contract | **S4**, §2.3 |
| 004.e-p3f1 | a deriving build does not CLAIM a `nul = 1` the caller already set — through `-z` and back, `nul` stays 1 and `_nulDerived` never claims it | contract | **S4**, **P3-F1** |
| 004.e-refused | a REFUSED build (no script) derives nothing — the rc 2 path returns before the rule | contract | **S4**, **S2** |
| 004.e-b-inplace | `inPlace = 1` derives exactly one `-b`, the `binary` property stays 0, and `inPlace = 0` takes the `-b` away | argv | **S4**, **Q5**, **C1** (major) |
| 004.e-b-nulldata | `nullData = 1` derives `-b` the same way | argv | **S4**, **Q5**, **C10** |
| 004.e-b-once | `binary` + `inPlace` + `nullData` — still exactly ONE `-b` (`sed --sandbox -z -b -i -e p -- f.txt`) | argv | **S4**, **Q5** |
| 004.e-b-caller | a caller's own `binary = 1` survives `inPlace` going 1 → 0 | argv | **S4**, **Q5** |
| 004.e-crlf | `crlf` is never touched by `buildArgv` (and `binary` stays 0 under `nullData` + `inPlace`) | contract | **S4**, §2.5 |

### F. S5 — every option precedes the first `-e` (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.f-e-late | `extended` set AFTER the expressions still emits `-E` BEFORE the first `-e` | argv | **S5**, §1.1 |
| 004.f-shapes | across four option shapes (quiet+extended; nullData+separate+extra; inPlace+suffix+scriptFile; binary+sandbox 0+extras) no option word follows the first `-e` | argv | **S5**, §1.1 |

---

### CR. the CR contract's argv where sed keeps the CR (L2.7-C) (14)

The file pins `__TUTIL_TOOLS_STRIP_CR=1` at the top (every other pinned argv is the cygwin/msys one); this section flips it.

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.cr-text | text mode: the prelude after the extras, before the first script `-e` | contract | DL11 |
| 004.cr-binary / -nulldata / -inplace ×3 | no prelude with `binary`, `nullData`, `inPlace` | contract | DL11 |
| 004.cr-back | back to text mode: the prelude again | contract | DL11 |
| 004.cr-hashn ×6 | `#n` → `-n`: as `expr`, as the first line of a multi-line `expr`, not for `#np`, one `-n` with `quiet`, as the first `addExpr`, as line 1 of `scriptFile`; none for a plain `scriptFile` | contract | DL11 |
| 004.cr-native | the cygwin/msys path: no prelude, `#n` left to sed | contract | DL11 |
| 004.cr-textmode | `_textMode` stays 0 on both paths | contract | DL11 |

## 005_Run.sh — TSed against GNU sed on a real tree (P0; §E extended at L2.7-C) — 78 cases

Oracle = the bare tool on the same fixture. Records are compared as arrays
(newline framed, the unterminated tail kept; NUL framed under `-z`), streams
byte for byte with `cmp` or `od -c`.

### Z. the banner gate and the fixture (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.z-banner | the `sed` on PATH is GNU sed — otherwise every case below is a loud SKIP and the count is unchanged; the PASS line names the binary (Git for Windows' under 5.2.37, msys64's under 5.3.9) | contract | **D4**, **C16** |
| 005.z-fixture | the fixture tree is in place: a 3-line file, a CRLF file (a real `\r` in its bytes), NUL, unterminated, a script, exotic names, a directory | contract | §4 |

### A. S6 — every sink against the bare tool (12)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.a-sinks | `toArray` / `each` / `count` / `first` / `toList` / `run` on `s/a/A/` all agree with bare sed: `(A1 b2 c3)`, rc 0, `lastRc` 0, `run` byte-identical | tool-behaviour | **S6** |
| 005.a-multi-e | a multi-`-e` block (`2{` + `s/b/J/` + `}`) — the chunks join into ONE script | tool-behaviour | **S6**, §1.1 |
| 005.a-scriptfile | `scriptFile` — the script from a file (`-f`) | tool-behaviour | **S6**, **Q2** |
| 005.a-expr-and-file | `expr` + `scriptFile` — both apply, `-e` first | tool-behaviour | **S6**, **Q2** |
| 005.a-quiet-p | `quiet = 1` + `2p` — exactly the printed line | tool-behaviour | **S6** |
| 005.a-quiet-no-p | `quiet = 1` with NO `p` — zero records, rc 0, RESULT 0, the array emptied | boundary | **S6**, §1.1 |
| 005.a-one-stream | two files are ONE stream by default (`$` = the last line of the LAST file) | tool-behaviour | **S6**, §1.1 |
| 005.a-separate | `separate = 1` makes them separate (`$` = the last line of EACH file) | tool-behaviour | **S6** |
| 005.a-unterminated | an unterminated last line stays unterminated (`run \| od -c` == bare) and is ONE record | representation | **S6** |
| 005.a-identity | `addExpr ''` is the IDENTITY — `run` byte-identical to bare `sed --sandbox -e ''` over an unterminated file and a normal one, `lastRc` 0 | tool-behaviour | **S6**, **C4** |
| 005.a-stdin | no path — `run` reads stdin; the path `-` is stdin explicitly; both identical to bare sed on stdin | boundary | **S6**, §1.1 |
| 005.a-exotic-names | a name with a SPACE and a name starting with `-` work behind `--` (`-dash.txt` read as a FILE); the `cd` is in this file's shell and undone | representation | **S6**, §1.1 |

### B. S5 — `-E` must precede the first `-e` (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.b-ere | `extended = 1` (assigned AFTER the expression) + `s/(a)1/[\1]/` on `a1` → `[a]` — the group and the back-reference compiled as ERE | tool-behaviour | **S5**, **C17** |
| 005.b-why | the reason: bare `sed -e 's/(a)1/[\1]/' -E` is rc 1 (`sed: …`) — each `-e` compiles when read | tool-behaviour | **S5**, §1.1 |

### C. S7 — partial failures, I/O errors, the script's own `q`/`Q` status (11)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.c-partial-toarray | a missing file among good ones: `toArray` rc 1, RESULT = the real count (3), `lastRc` 2, the records identical to the bare tool's partial output | boundary | **S7**, §2.4, **C5** (major) |
| 005.c-partial-count-tolist | the same: `count` rc 1 / 3; `toList` rc 1 / 3 offered, 3 stored | boundary | **S7**, **C5** |
| 005.c-partial-each | the same: `each` rc 1, three callbacks, RESULT UNTOUCHED (a proc) | boundary | **S7**, **C5** |
| 005.c-partial-first | the same: `first` rc 0, the first record, `lastRc` 2, NO line of ours (TUtil's consumer-stop contract) | boundary | **S7**, **C5** |
| 005.c-partial-lines | the partial path says ONE line of ours, worded per Q3 (`sed exited 2 (a sed error, or the script's q/Q 2)`), naming TSed; sed's own line passes through, matched by prefix | contract | **S7**, **Q3**, §2.6 (a)(b) |
| 005.c-dir-operand | a DIRECTORY operand: rc 1, `lastRc` 4, the earlier records kept, the LATER file NOT read — rc 4 stops, identical to the bare tool | boundary | **S7**, **C6** |
| 005.c-missing-f | a MISSING `-f` script: rc 1, `lastRc` 4, zero records, one line of ours (`sed exited 4`), sed's own passed through | boundary | **S7**, **C6** |
| 005.c-bad-script | a BAD script (`s/a`): rc 1, `lastRc` 1, zero records, one line of ours, sed's `-e expression #1` line | contract | **S7**, **Q3** |
| 005.c-q7 | `2q7`: rc 1 **SILENT** (no line of ours, none of sed's), `lastRc` 7, RESULT 2, `(a1 b2)` delivered — a script status, not an error | tool-behaviour | **S7**, **Q3**, §2.6 (d) |
| 005.c-q1 | `2q1`: rc 1 WITH the debug line — indistinguishable from sed's own 1, worded to say so; `(a1 b2)` delivered | contract | **S7**, **Q3**, **C8** |
| 005.c-q256 | `1q256` wraps to 0 (N mod 256): rc 0, `lastRc` 0, `(a1)` | tool-behaviour | **S7**, §1.1 |

### D. S8 — the sandbox default (9)

Each refusal case asserts rc 1, `lastRc` 1, zero records, one line of ours,
sed's own *… disabled in sandbox mode*, and that the **marker file** the command
would have created does NOT exist. Class `security`, basis **S8**, **Q1**
throughout.

| ID | Case | Extra basis |
|---|---|---|
| 005.d-se | `s///e` (`1s\|.*\|touch MARKER\|e`) is refused | |
| 005.d-e | the `e` command (`1e touch MARKER`) is refused | |
| 005.d-w | `w FILE` is refused — the file is never created | |
| 005.d-r | `r FILE` is refused | |
| 005.d-late-e | an `e` in a LATER `-e` (after a harmless `s/a/A/`) refuses the whole script at compile time | §1.1 |
| 005.d-f-w | a `-f` script containing `w` is refused too | §1.1 |
| 005.d-w-stdout | `s/a/X/w /dev/stdout` is refused by default — use `p`; nothing doubled, zero records | **C9** |
| 005.d-open | `sandbox = 0` RUNS `s///e`, `e`, `w` and the `-f` script — rc 0 each, every marker appears (`m_w` holding `a1`) | |
| 005.d-open-w-stdout | `sandbox = 0` + `s/a/X/w /dev/stdout` doubles the line — `(X1 X1 b2 c3)`, exactly like the bare tool | **C9** |

### E. S9 — the CR (13; the kbool contract since L2.7-C, tutil README §3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.e-text-strips | text mode delivers NO line-end CR on every platform — records `(a1 b2)`, the stream is the literal `a1\nb2\n` (the oracle is the bytes, not bare sed: text mode is the kbool contract, owner DL11) | contract | **S9**, §2.5, DL11 |
| 005.e-binary-keeps | `binary = 1` KEEPS the CR — records `(a1\r b2\r)`, `run` == the file's own bytes | representation | **S9**, §2.5 |
| 005.e-binary-crlf | `binary = 1` + `crlf = 1` strips EXACTLY one CR (`c3\r\r` → `c3\r`) | representation | **S9**, **C17** |
| 005.e-inplace-crlf | `inPlace = 1` on a CRLF file keeps EVERY CR on disk (`A1\r\nb2\r\n`, the derived `-b`), on every platform (the bare `sed -i` oracle was cygwin/msys-specific and is gone) | contract | **S9**, **Q5**, **C1** (major), DL11 |
| 005.e-nulldata-cr | `nullData = 1` keeps a CR embedded in a NUL record (`x\r\ny`), == the bare `sed -z -b` (the same on every platform) | contract | **S9**, **Q5**, **C10**, DL11 |
| 005.e-contract-prelude | the prelude path forced (`__TUTIL_TOOLS_STRIP_CR=0`, real sed, any host): the prelude in the argv; all five sinks `(a1 b2)`, `run` LF-only; `binary = 1` keeps the CR | contract | DL11 |
| 005.e-contract-tflag | the prelude path forced: the script's own `t` is not triggered by the prelude (`A1 b2`), `#n` (expr and scriptFile) still means `-n`, `s/$/\r/` keeps its CR | contract | DL11 |
| 005.e-contract-nostrip | no output strip on either path: a CR-keeping stand-in's CRs reach `toArray` and `run` | contract | DL11, critic B1 |
| 005.e-owner-alice | owner example: `s/Alice$/Bob/` on CRLF gives `name=Bob` (red on Linux before round 2) | contract | DL11 |
| 005.e-owner-blank | owner example: `/^$/d` deletes the blank CRLF line (red before round 2) | contract | DL11 |
| 005.e-owner-cr | a deliberate `s/$/\r/` keeps its CR in the sinks and `run`, every platform (red before round 2) | contract | DL11, critic B1 |
| 005.e-owner-t | the script's own `t` (real path of the platform) | contract | DL11 |
| 005.e-owner-hashn | `#n` via `expr` and via line 1 of `scriptFile` (real path of the platform) | contract | DL11 |

### F. S10 — `-z` NUL records (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.f-records | `nullData = 1` — 3 NUL records through the derived `-0`, `nul = 1` derived, `toArray` == bare, `count` 3, `first` `>a` | representation | **S10**, §2.3 |
| 005.f-unterminated | the unterminated last NUL record stays unterminated — `run` byte-identical to bare, the stream ends in `last` with no NUL | representation | **S10** |

### G. S11 — in-place (16)

Every case works on a COPY and asserts its bytes afterwards.

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g-run-edits | `inPlace = 1` + `run` edits the file, stdout EMPTY, rc 0, `lastRc` 0, no backup | tool-behaviour | **S11**, **Q4** |
| 005.g-bak | `backupSuffix = .bak` keeps the original bytes as `FILE.bak` | tool-behaviour | **S11** |
| 005.g-bak-star-bare | `backupSuffix = 'bak_*'` on a BARE operand (`cd` in this shell, undone) names the backup `bak_ip3.txt` | tool-behaviour | **S11**, **C7**, **P0-fact** |
| 005.g-bak-star-dir | `bak_*` on an operand WITH a directory — `*` is the whole operand: rc 1, `lastRc` 4, the file byte-identical, no `bak_…` created (added after the red run: on the skeleton it answered rc 2) | boundary | **S11**, **P0-fact** |
| 005.g-star | `backupSuffix = '*'` is rc 2 — one line, `lastRc` -1, the file byte-identical | contract | **S11**, **C7** |
| 005.g-nodir | a MISSING backup directory (`nodir/*`): rc 1, `lastRc` 4, one line of ours, sed's own by prefix, the file untouched | boundary | **S11**, **C7** |
| 005.g-dir-first | a DIRECTORY before a good file: rc 1, `lastRc` 4, the good file NOT edited (rc 4 stops) | boundary | **S11**, **C6** |
| 005.g-q-truncates | the documented TRAP — `inPlace` + `2q` TRUNCATES the file silently (rc 0, `c3` gone from disk) | tool-behaviour | **S11**, **C8**, §6 |
| 005.g-refuse-each | `each` with `inPlace = 1`: rc 2, ONE line naming `TSed.each`, *in-place*, *use run*; the file byte-identical, `lastRc` -1, RESULT the caller's (a proc); a second call with `cmd` pointed at a flag-writing function proves nothing ran | contract | **S11**, **Q4**, §2.4 |
| 005.g-refuse-toarray | the same for `toArray` (RESULT `''`) | contract | **S11**, **Q4** |
| 005.g-refuse-tolist | the same for `toList` | contract | **S11**, **Q4** |
| 005.g-refuse-first | the same for `first` | contract | **S11**, **Q4** |
| 005.g-refuse-count | the same for `count` | contract | **S11**, **Q4** |
| 005.g-refuse-array | the refusal leaves the caller's array alone (`(keep1 keep2)`, RESULT `''`) | contract | **S11**, §2.4 |
| 005.g-inplace-off | `inPlace` back to 0 — the same instance's sinks work again (`count` rc 0, 3) | boundary | **S11** |
| 005.g-debug | `--debug` among the extras: every sink rc 2 with one line naming `--debug` and *use run*, `lastRc` stays -1; `run` rc 0 streams the trace (first line `SED PROGRAM:`) | contract | §2.4, **C11** |

### H. S12 — `TSed.edit EXPR PATH...` (11)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.h-direct | `TSed.edit 's/a/A/' f` == `sed --sandbox -e 's/a/A/' -- f`, called DIRECTLY, bytes compared | tool-behaviour | **S12**, §2.7 |
| 005.h-pipe | the same through a PIPE (`\| od -c`), two files incl. the unterminated tail | contract | **S12** |
| 005.h-procsub | the same through `< <( )` | contract | **S12** |
| 005.h-identity | `TSed.edit '' f` is the IDENTITY (== `sed --sandbox -e '' -- f` == the file's bytes) | tool-behaviour | **S12**, **C4** (major) |
| 005.h-no-path | `TSed.edit EXPR` with NO path is rc 2, prints nothing, reads nothing from a here-string on stdin, one line naming `TSed.edit` | contract | **S12**, §2.7 |
| 005.h-no-arg | `TSed.edit` with NO argument at all is rc 2, one line | contract | **S12** |
| 005.h-sandbox-forced | `edit` with `s///e` is REFUSED (sandbox forced): rc 1, sed's *disabled in sandbox mode*, no marker | security | **S12**, **Q1** |
| 005.h-missing | `edit` on a MISSING file is rc 1 with one line of ours (`sed exited 2`), sed's own by prefix | contract | **S12**, **Q3** |
| 005.h-seq | `edit` deletes its throw-away instance (`_data`, `_paths`, `_exprs`, `_rfrom`, `_rto`, `_rflags`, `_args`, `_argv`, the `.delete` wrapper) and bumps `__TSD_SEQ` by one per call | contract | **S12**, §2.7 |
| 005.h-nested | a nested `edit` inside an outer `each` — 3 outer records, 3 nested edits each `d4\ne5`, the OUTER instance's argv and `lastRc` untouched | boundary | **S12**, §2.7 |
| 005.h-tpipe-both | `edit` composes with BOTH TPipe forms: `TPipe.each cb -- TSed.edit …` and, in a child with `shopt -s lastpipe`, a real pipe — 3 records each | contract | **S12** |

---

## 006_Contract.sh — the kcl contract for TSed (P0) — 66 cases

### 0. source integrity (13)

Two earlier mechanical sweeps corrupted kcl sources while tests stayed green, so
this section reads the file itself. Class `contract` throughout.

| ID | Case | Basis |
|---|---|---|
| 006.0-parse | the unit source parses (`bash -n`) | §6 |
| 006.0-open-quote | no single-quoted `printf` format is left open at end of line | §6 |
| 006.0-inline-cr | no member body carries an inline `$'\r'` (it does not survive `build`) | §6 |
| 006.0-this | no internal member call is spelled `$this.NAME` | tutil PLAN §2.2 |
| 006.0-sentinel | the red-first skeleton sentinel `__TSED_PENDING__` is GONE | §5 |
| 006.0-ctor | the CONSTRUCTOR calls `parent.constructor sed`, never `inherited`, and assigns `sandbox=1` and `expr="${1:-}"` | §2.1, **Q1** |
| 006.0-dtor | the DESTRUCTOR frees `${__inst__}_paths` AND `${__inst__}_exprs` with `unset -v`, then chains with `inherited` | §2.1 |
| 006.0-rc-preserving | the four overridden func sinks (`toArray`, `toList`, `first`, `count`) use the rc-PRESERVING spelling: a guarded `inherited X "$@" \|\| …`, RESULT saved, the rc re-raised, and no body ENDS on `inherited` | §2.4 (thead §6) |
| 006.0-each-proc | the overridden PROC `each` re-raises the rc and never answers RESULT | §2.4, **C5** |
| 006.0-no-bin-bookkeeping | the derived `-b` lives in `buildArgv` only — no `binary=` in the builder, no `_binDerived` anywhere | **Q5** |
| 006.0-no-shadow | no `var` shadows a TUtil or kklass member name, and there are exactly **11** of them | tutil PLAN §1.2 |
| 006.0-one-source | the unit sources ONLY `../tutil/tutil.sh` | §1.2 |
| 006.0-registered | the unit registered `__tsd_` and `_exprs` at load, once each | §2.1, **C3** |

### Z. the banner gate (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.z-banner | the `sed` on PATH is GNU sed; otherwise every case that runs sed is a loud SKIP | contract | **D4** |

### 1. `set -eu` — the instance, `s.each` and both TPipe forms, every outcome (22)

Each `expect_clean` case runs its snippet in a **child** under `set -eu` (and
`timeout 60`, stdin `/dev/null`) with the unit freshly sourced, and asserts rc 0,
stdout exactly `OK`, and **empty stderr**; every sink call inside is guarded
`|| rc=$?`. Class `contract`, basis **S13** throughout.

| ID | Case |
|---|---|
| 006.1-load | the unit loads under `set -eu` |
| 006.1-load-twice | it loads TWICE (every unit header makes the second load a no-op, the registry appends stay idempotent) |
| 006.1-each | `s.each`: an instance that delivers records — rc 0, 3 calls, `lastRc` 0 |
| 006.1-tpipe-argv | form 2: `TPipe.each CB -- "${argv[@]}"` with the argv TSed built (6 words) |
| 006.1-tpipe-edit | form 2 with `TSed.edit` as the producer command |
| 006.1-lastpipe | form 1: a REAL pipe under `shopt -s lastpipe`, from `edit` and from `s.run` (`quiet` + `2p` → 1 record) |
| 006.1-func-sinks | every func sink on an instance that delivers: `toArray` 3, `count` 3, `first` `A1` |
| 006.1-tolist | `toList` into a kklass instance with an `.Add` — offered 3, stored 3 |
| 006.1-sed-error | a sed ERROR (the only file missing, raw 2) — `each` rc 1, 0 callbacks, `lastRc` 2, the child survives |
| 006.1-partial | a PARTIAL failure — rc 1, records KEPT, `RESULT` == what was kept (3), `lastRc` 2 |
| 006.1-q7 | a script `q N` status (`2q7`) — `count` rc 1 RESULT 2, `lastRc` 7, no abort |
| 006.1-refused-noscript | a REFUSED build (no script) — rc 2 from `each` (0 callbacks) / `toArray` (array untouched, RESULT `''`) / `count` / `run`, `lastRc` still -1 |
| 006.1-inplace | in-place: every sink rc 2 with the file untouched, then `run` rc 0 edits it (`A1 b2 c3`) |
| 006.1-denied | a denied extra (`addArg -i`) — rc 2 from `toArray` / `count` / `run`, no abort |
| 006.1-cmd-empty | an EMPTY `cmd` — rc 2 from every runner, no abort |
| 006.1-edit-no-path | `TSed.edit` with no path — rc 2, no abort, nothing printed |
| 006.1-edit-sandbox | `TSed.edit` refused by the sandbox (`1e true`) — rc 1, no abort |
| 006.1-run-streams | `run` streams (`quiet` + `2p` → `b2`) and the raw rc is readable afterwards |
| 006.1-delete-clean | `delete` on an instance that never ran anything leaves no `_paths` / `_exprs` / `_args` |
| 006.1-subst-once | the `$( )` position: a func sink prints its value exactly ONCE (`count` 3, `first` `A1`; a doubled value would mean `__TPIPE_QUIET` is not in place) |
| 006.1-d6 | **D6 final**: `subshellOk = 1` silences TPipe's subshell warning through TSed (empty stderr, `n` 3), and without it the verbatim `Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — …` appears (basis **D6**) |
| 006.1-unguarded | an UNGUARDED sink call with rc 1 aborts a `set -eu` caller (nothing printed after it) while the guarded one reads rc 1 and carries on — the documented caller rule, not a defect |

### 2. the debug switch — one line per rc 2 / sed-error path, silence otherwise (30)

`check_one` asserts the rc, **exactly one** line of ours with the switch ON, and
**zero** lines of ours with the switch OFF (sed's own `sed: …` lines are counted
separately and never suppressed). `check_silent` asserts **no** line of ours at
all. Class `contract`, basis **S13** and §1.2 of the kcl README.

| ID | Case | Extra basis |
|---|---|---|
| 006.2-noscript-each | rc 2: no script, through `each` | §2.2 |
| 006.2-noscript-count | the same through `count` (every runner reports once, not twice) | §2.2 |
| 006.2-noscript-run | the same through `run` | §2.2 |
| 006.2-inplace-no-path | rc 2: `inPlace` with no path | **Q4** |
| 006.2-suffix-no-inplace | rc 2: `backupSuffix` without `inPlace` | §2.2 |
| 006.2-suffix-star | rc 2: `backupSuffix = '*'` | **C7** |
| 006.2-denied | rc 2: a denied extra (`--expression=p`), the line naming `expr` | **Q6**, **C2** |
| 006.2-dd | rc 2: `--` among the extras (the new case of **RR1**, red against the P0 source) | **RR1** |
| 006.2-cmd | rc 2: an empty `cmd` | §2.2 |
| 006.2-inplace-count | rc 2: `count` with `inPlace = 1` | **Q4**, §2.4 |
| 006.2-inplace-each | rc 2: `each` with `inPlace = 1` | **Q4**, §2.4 |
| 006.2-debug-first | rc 2: `first` with `--debug` in the extras | §2.4, **C11** |
| 006.2-edit-no-path | rc 2: `TSed.edit` with no path | §2.7 |
| 006.2-out-result | rc 2: `toArray RESULT` — a bad out-name (TUtil's own check) | §2.1 |
| 006.2-out-tsd | rc 2: `toArray __tsd_x` — the `__tsd_` prefix | §2.1 |
| 006.2-out-exprs | rc 2: `toArray dOk_exprs` — the `_exprs` suffix | **C3** |
| 006.2-out-sufreg | rc 2: `toArray TUTIL_OUT_SUFFIXES` — the registry's NAME | **C3** |
| 006.2-raw2 | sed raw 2 (a missing file among good ones) — rc 1 and one line (`sed exited 2`) | **Q3** |
| 006.2-raw1 | sed raw 1 (a bad script) — rc 1 and one line | **Q3** |
| 006.2-raw4 | sed raw 4 (a missing `-f` script) — rc 1 and one line | **Q3**, **C6** |
| 006.2-q1 | a script's `2q1` — rc 1 and one line, worded *or the script's q/Q 1* | **Q3**, **C8** |
| 006.2-silent-count | rc 0: a successful `count` says NOTHING | §1.2 |
| 006.2-silent-each | rc 0: `each` on records says NOTHING | §1.2 |
| 006.2-silent-toarray | rc 0: `toArray` on records says NOTHING | §1.2 |
| 006.2-silent-run | rc 0: `run` says NOTHING | §1.2 |
| 006.2-silent-edit | rc 0: a `TSed.edit` that succeeded says NOTHING | §1.2 |
| 006.2-silent-q7 | a script's `2q7` — rc 1 and SILENT (N outside {1, 2, 4, 127}) | **Q3**, §2.6 (d) |
| 006.2-silent-Q3 | a script's `1Q3` — rc 1 and SILENT | **Q3** |
| 006.2-silent-q256 | a script's `1q256` wraps to 0 — rc 0 and SILENT | **Q3**, §1.1 |
| 006.2-q-raw | the `q N` status reaches `lastRc` RAW (7 and 3) while the member answers 1 | **Q3** |

---

## 007_Bench.sh — the PLAN §5 P1 performance gate (P1) — 11 cases

Class `perf` throughout (except the banner gate). **Two sets of numbers on
purpose**: [`../bench.sh`](../../../tsed/bench.sh) measures the real **1.5×** gate by hand on
an idle box from the medians of 21 interleaved runs (README §10); this file
asserts the same shapes with a **10×** ceiling, because ktests runs test files
threaded (8 workers) and the two sides of the ratio do not inflate together —
`sed` is its own process while the wrapper's share is bash work in the contended
shell. The clock is `TStopwatch.getTimeStamp`; `date +%s%N` is forbidden here
(~20 ms per call on msys, paid twice per sample — tfind **C17** of its own
critic pass). The corpus comes from `kt_fixture_tmpdir_create`; the file
installs no `EXIT` trap of its own.

| ID | Case | Basis |
|---|---|---|
| 007.z-banner | the `sed` on PATH is GNU sed — otherwise every timed case is a loud SKIP, count unchanged | **D4** |
| 007.a-gate-big | `TSed.edit 's/a/A/'` over a 200-line file costs at most **10×** a bare `sed --sandbox -e 's/a/A/' --`, from the MEDIANS of 7 INTERLEAVED runs, with both sides' outputs asserted byte-identical (200 records) | §5 P1 |
| 007.a-gate-one | the same over a **ONE-line** file — the shape that shows corpus size is not the knob (the fork dominates both sides) | §5 P1 |
| 007.a-delta | the `edit` delta IS one instance: `new` + `addExpr` + `sandbox =` + `argv` + `delete` (fresh names, as `edit` uses) under 50 ms/call (~5 ms idle; eleven properties and two arrays), with the argv asserted | §5 P1 |
| 007.b-argv-nothing | 200 `buildArgv`/`argv` calls invoke the `cmd` **zero** times, never fork (`$BASHPID`), and build the 10 words in the pinned order (`--sandbox -E --posix -e … -e … -- FILE`) | **S1**, §5 P1 |
| 007.b-argv-constant | the build stays constant-cost: 201 rebuilds do not accumulate words | **S1** |
| 007.b-refused-cheap | a REFUSED build is the cheap path too: 100 deny-list rc 2 calls (`-ni` after `-u --posix`, so the whole scan runs) invoke the `cmd` zero times, fork nothing, and leave `${inst}_argv` empty | **S2**, **Q6** |
| 007.c-count | `s.count` over 200 records costs at most 10× `sed --sandbox -e … -- FILE \| wc -l` — published, **not** the gate; both count 200. At 200 records the two are close (the sink's fixed half is cheaper than a two-process pipeline); `../bench.sh` shows the pipeline ~10× ahead at 10 000 | §5 P1 |
| 007.d-sinks-fork | the five sinks: the callback and `.Add` run in THIS process, one record each (`first` = `A00001 xyz`) | **S13** |
| 007.d-members-fork | the ONLY fork per call is sed: ten property writes, nine builder members (`paths`, `addExpr`, `clearExprs`, `addArg`, `clearArgs`, `buildArgv`, `argv`, `mapRc` twice — 4 → 1, 7 → 1 —, `lastRc`), `run` and `edit` leave `$BASHPID` untouched | **S13**, **Q3** |
| 007.d-refused-fork | the rc 2 paths fork nothing: a deny-list hit (`--in=.bak`), an in-place sink, a `--debug` sink, a path-less `edit` — all rc 2, `lastRc` still -1 (sed never ran) | **S2**, **Q4**, **Q6**, **C11** |

---

## 008_Helpers.sh — H1 literal replace (launch L2.7-H, 2026-10-22) — 87 cases

The five members of [`../tutil/HELPERS_PLAN.md`](../tutil/HELPERS_PLAN.md) §2.1
(**HP** below): `TSed.quoteRe`, `TSed.quoteRepl`, `addReplace`, `TSed.replace`,
`TSed.replaceInFile`. The oracle is the bare GNU tool with a **hand-written**
escape — never the code under test's own escaper; the escaper cases compare
against the reference sets written out by hand from the owner probe
(`esc_probe.sh`: FROM `a.b*c[d]e^f$g\h/i+j?k|l(m){2}&`, TO `X&Y\1/Z<newline>W`).
The GNU banner gate opens the file as in 005; the argv cases (B) pin the
cygwin/msys argv (`__TUTIL_TOOLS_STRIP_CR = 1`, as 004) plus one case on the
prelude path, and restore the platform value. D3 = `replaceInFile` makes no
backup; DL11 = the CR contract (tutil README §3).

| ID | Case | Basis |
|---|---|---|
| 008.z01 | the `sed` on PATH is GNU sed (D4 pins the DIALECT, not a binary) | **D4** |
| 008.z02 | the fixture tree is in place | **D4** |
| 008.a01 | quoteRe PROBE (BRE): `\ / . * [ ^ $` escaped, `+ ? \| ( ) { } &` left alone — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a02 | quoteRe PROBE ere: also `+ ? ( ) { } \|` — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a03 | quoteRepl PROBE: `\ / &` escaped, the newline -> backslash + newline — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a04 | quoteRe: a newline becomes `\n` (BRE and ere alike) — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a05 | quoteRe ere: a newline becomes `\n` too — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a06 | quoteRe: a dialect word other than exactly `ere` (`ERE`, `-E`, `1`, `''` given) is rc 2, RESULT '', one line, `$( )` prints nothing — it fails CLOSED (a BRE escape fed to `sed -E` would leave `( ) { } \| + ?` live) | HP §2.1, critic F6 |
| 008.a07 | quoteRe: an empty TEXT is RESULT '', rc 0 — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a08 | quoteRe: a backslash already in TEXT is doubled ONCE (backslash escaped first) — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a09 | quoteRe: TAB, CR and multibyte pass through unescaped — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a10 | quoteRepl: `\1`, `&`, `/` and two newlines — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a11 | quoteRepl: an empty TEXT is RESULT '' — direct call: RESULT byte-exact (`od -c`), stdout and stderr empty | HP §2.1, §2.3 |
| 008.a12 | `$( )` prints the value exactly ONCE (quoteRe, quoteRe ere, quoteRepl) | HP §2.1, §2.3 |
| 008.a13 | the BRE escape of a string WITHOUT metacharacters is the string itself | HP §2.1, §2.3 |
| 008.a14 | the probe round-trips through REAL sed (BRE): `s/<quoteRe FROM>/<quoteRepl TO>/g` — FROM replaced, `axb` and `a.b` untouched | HP §2.1, §2.3 |
| 008.a15 | the probe round-trips through REAL sed -E: `quoteRe FROM ere` | HP §2.1, §2.3 |
| 008.b01 | no FLAGS = every occurrence: `s/a\.b/x\&y/g` | HP §2.1, §2.2, §2.4 |
| 008.b02 | FLAGS `rfIgnoreCase` = ONLY what it names: `I` (no `g` — TStringHelper's rule) | HP §2.1, §2.2, §2.4 |
| 008.b03 | FLAGS `''` (given, empty): neither `g` nor `I` — the first occurrence | HP §2.1, §2.2, §2.4 |
| 008.b04 | FLAGS `rfReplaceAll`: `g` | HP §2.1, §2.2, §2.4 |
| 008.b05 | `rfReplaceAll rfIgnoreCase` in any order and with any blanks: `gI` | HP §2.1, §2.2, §2.4 |
| 008.b06 | call order with interleaved addExpr (expr first; an empty addExpr keeps its slot) | HP §2.1, §2.2, §2.4 |
| 008.b07 | -E: `+?(){}\|` escaped, and the SAME argv whether `extended = 1` came before or after addReplace | HP §2.1, §2.2, §2.4 |
| 008.b08 | ... the `extended`-before build is identical word for word | HP §2.1, §2.2, §2.4 |
| 008.b09 | the dialect is read at BUILD time: `extended` back to 0 -> the BRE escape again | HP §2.1, §2.2, §2.4 |
| 008.b10 | the owner probe: FROM and TO escaped exactly like the hand-written reference | HP §2.1, §2.2, §2.4 |
| 008.b11 | `nullData = 1`: a newline in FROM is legal and becomes `\n` (+ the derived -z -b) | HP §2.1, §2.2, §2.4 |
| 008.b12 | a newline in TO is fine in line mode: backslash + newline, ONE word | HP §2.1, §2.2, §2.4 |
| 008.b13 | a CR in FROM is passed through (text mode strips the line-end CR before the script — §D) | HP §2.1, §2.2, §2.4 |
| 008.b14 | `inPlace = 1` + addReplace: -b -i, then the expression | HP §2.1, §2.2, §2.4 |
| 008.b15 | the prelude path (__TUTIL_TOOLS_STRIP_CR = 0): the CR prelude first, then the literal s/// | HP §2.1, §2.2, §2.4 |
| 008.b16 | storage: `_exprs` keeps call order with the marker, the raw data in three parallel arrays at the SAME index | HP §2.1, §2.2, §2.4 |
| 008.b17 | addReplace stores RAW and builds nothing: a refused FROM/FLAGS is stored as given, rc 0 | HP §2.1, §2.2, §2.4 |
| 008.b18 | `addReplace FROM` with NO TO: TO is '' — the text is deleted (`s/a\.b//g`) | HP §2.1, round-2 R2 |
| 008.b19 | `buildArgv` (a success and a refused build) and both escapers leave NO `__tsd_` scratch variable behind (`compgen -v`) | HP §2.2, round-2 R4 |
| 008.c01 | every sink and `run` agree with bare sed: `addReplace a.b Q` on (a.b xax 'a.b a.b') | HP §2.4 |
| 008.c02 | zero matches: rc 0, lastRc 0, `run` byte-identical to the file | HP §2.4 |
| 008.c03 | the metachar soup FROM is matched LITERALLY, TO with `& \1 / newline` is literal — == bare sed with the hand escape | HP §2.4 |
| 008.c04 | the same under `extended = 1` (the -E escape set) — the same bytes | HP §2.4 |
| 008.c05 | the flags against the text `A.B a.b a.b A.b`: default, `''`, rfIgnoreCase, both | HP §2.4 |
| 008.c06 | a multibyte FROM under LC_CTYPE=C.UTF-8 AND under C — the same bytes as bare sed in each | HP §2.4 |
| 008.c07 | a FROM with a TAB: `a<TAB>b` replaced, `a b` untouched | HP §2.4 |
| 008.c08 | addReplace and addExpr in one script, in call order: `addExpr 2d` + `addReplace a.b Q` + `addExpr s/Q/R/` | HP §2.4 |
| 008.c09 | `rfIgnoreCase` folds non-ASCII ONLY under a UTF-8 locale: on `é. É. É.é` / `а А`, `addReplace 'é.' X` and `addReplace 'а' Y` with `rfReplaceAll rfIgnoreCase` give `X X Xé` / `Y Y` under C.UTF-8 and `X É. É.é` / `Y А` under C, each == bare sed in that locale (LC_ALL exported inside the `$( )` around `run`) | HP §2.4, critic F1 |
| 008.d01 | text mode: a FROM ending in CR NEVER matches (the line-end CR is gone before the script) — both platform paths | HP §2.4, DL11 |
| 008.d02 | `binary = 1`: the same FROM MATCHES — records (Z b2\r), == bare `sed -b` | HP §2.4, DL11 |
| 008.d03 | `nullData = 1`: a newline inside FROM is legal and matches across the line — records (Q z) | HP §2.4, DL11 |
| 008.e01 | `inPlace = 1` + addReplace edits in place, CRLF KEPT on disk (the derived -b), stdout empty | HP §2.4, D3, **Q5** |
| 008.e02 | `TSed.replaceInFile` on two copies: both edited literally, CRLF kept, stdout empty, NO backup file | HP §2.4, D3, **Q5** |
| 008.e03 | `TSed.replaceInFile` with ZERO matches: rc 0, the bytes identical (sed still rewrites the file — mtime not asserted) | HP §2.4, D3, **Q5** |
| 008.e04 | `TSed.replaceInFile` on a MISSING file among good ones: rc 1, one line (sed's 2), the good file still edited | HP §2.4, D3, **Q5** |
| 008.f01 | an EMPTY FROM is rc 2 (sed would reuse the previous regex) — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f02 | a FROM holding a newline with `nullData = 0` is rc 2 (it can never match a line) — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f03 | ... and with `nullData = 2` (only the exact string 1 is on) — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f04 | an unknown FLAGS word is rc 2 and the line names it — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f05 | a comma-joined FLAGS string is ONE unknown word (blanks separate the tokens) — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f06 | the tokens are case-sensitive: `rfreplaceall` is unknown — rc 2, RESULT '', one line, `${inst}_argv` empty, the four arrays intact, `run` rc 2 with stdin unread | HP §2.1, §2.2 |
| 008.f07 | a refused build derives nothing: `nullData = 1` + a bad flag leaves `nul` at 0 | HP §2.1, §2.2 |
| 008.f08 | `addExpr '__tsd_r__'` is rc 2 with one line naming the reserved word; NOTHING of that call is appended | HP §2.1, §2.2 |
| 008.f09 | `TSed.edit '__tsd_r__' f` is rc 2 with ONE line, nothing printed | HP §2.1, §2.2 |
| 008.f10 | `TSed.replace FROM TO` with NO path is rc 2 (sed would read the caller's stdin) — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f11 | `TSed.replace` with no argument at all is rc 2 — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f12 | `TSed.replaceInFile FROM TO` with NO path is rc 2 — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f13 | `TSed.replaceInFile FROM TO -` is rc 2 (the in-place refusal of the path `-`) — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f14 | `TSed.replace '' TO f` is rc 2 (an empty FROM, buildArgv's line) — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f15 | `TSed.replace` with a newline in FROM is rc 2 — one line, nothing printed, stdin unread | HP §2.1, §2.2 |
| 008.f16 | `TSed.replaceInFile '' TO f` is rc 2 and the file is byte-identical | HP §2.1, §2.2 |
| 008.f17 | `addReplace` with MORE than three arguments (unquoted flags) is rc 2 AT THE CALL, one line naming the usage `addReplace FROM TO [FLAGS]`, the four arrays unchanged; the next build is unaffected | HP §2.1, round-2 R2 |
| 008.g01 | `TSed.replace` DIRECT == bare sed with the hand escape (bytes), rc 0 | HP §2.1, §2.4 |
| 008.g02 | `TSed.replace` never edits in place: the file is byte-identical afterwards | HP §2.1, §2.4 |
| 008.g03 | `TSed.replace` through a PIPE (`\| od -c`) and through `< <( )` — byte-identical | HP §2.1, §2.4 |
| 008.g04 | `TSed.replace` in the three positions: terminal (a file), lastpipe, the TPipe `--` form | HP §2.1, §2.4 |
| 008.g05 | `TSed.replace` on a MISSING file is rc 1 with one line of ours (sed's 2, mapped) | HP §2.1, §2.4 |
| 008.g06 | `replace` and `replaceInFile` delete their throw-away instance and bump `__TSD_SEQ` once each | HP §2.1, §2.4 |
| 008.g07 | a nested `TSed.replace` inside an outer `each` — both complete, the outer instance survives | HP §2.1, §2.4 |
| 008.h01 | `new` declares the three arrays EMPTY; a reused name starts clean | HP §2.2 |
| 008.h02 | `clearExprs` empties ALL FOUR arrays (and keeps `expr`) | HP §2.2 |
| 008.h03 | `delete` frees `_rfrom`, `_rto`, `_rflags` (and `_exprs`, `_paths`) | HP §2.2 |
| 008.h04 | `s.argv s_rfrom` is rc 2 (the suffix registry) — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h05 | `s.toArray s_rfrom` is rc 2 — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h06 | `s.argv s_rto` is rc 2 — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h07 | `s.toArray s_rto` is rc 2 — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h08 | `s.argv s_rflags` is rc 2 — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h09 | `s.toArray s_rflags` is rc 2 — one "bad output array name" line, storage intact | HP §2.2 |
| 008.h10 | each suffix is registered EXACTLY once (`_exprs _rfrom _rto _rflags`), `__tsd_` once | HP §2.2 |
| 008.h11 | ... still exactly once after a re-source AND after `kk.unit --forget tsed` + a re-source (a child under set -eu) | HP §2.2 |
