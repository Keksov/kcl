# ttail — test coverage notes

**Status: FINALIZED at P1 (2026-09-16).** Suite `004`–`007` = **200 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single`, against **GNU coreutils 8.32**. The
per-file row counts below sum to 200 — 74 + 61 + 55 + 10 — and **every case in
the suite has a row**.

**Protocol.** `TTail` has no FPC upstream: it is the fourth wrapper on
[`TUtil`](../tutil/README.md), which is itself a kcl addition (see
[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)). The oracle is therefore **the
bare GNU tool on the same fixture**, run with the same argv, never a second call
into the code under test. Decision **D4** (of the tpipe plan) pins the *dialect*
— GNU coreutils 8.32, the build MSYS2 ships — not a binary, so every behavioural
file opens with the **GNU banner gate**: if `tail --version` does not begin with
`tail (GNU coreutils) `, every behavioural case is a loud SKIP and the case
**count is unchanged**.

`TTail` is **not** a `THead` descendant and `ttail.sh` never sources `thead.sh`
(`+N` means opposite things in the two tools), so the shared shape is tested
twice on purpose — once per unit, against each unit's own tool. What this file
adds over
[`../thead/TEST_COVERAGE_NOTES.md`](../thead/TEST_COVERAGE_NOTES.md) is the
`follow` block (T2/T3), the `+N` sign table (T1) and the rc-preserving spelling
of the three overridden sinks.

The suite splits in two on purpose:

* **`004_Argv.sh` never executes tail.** Every typed option is pinned by
  comparing the built array, which is what `argv NAME` exists for — `-f`
  included, because `-f` reaches the argv even where three sinks refuse it.
* **`005`/`006`/`007` run the tool** on a fixture tree with a 5-line and an
  11-line file, two 3-line files for the header cases, an unterminated file
  (used alone *and* as the first of two operands), a CRLF file, a NUL-separated
  file whose last record is unterminated, a name with a space and a name
  starting with `-`.

**`tail -f` hygiene.** Every follow case runs in a child under `timeout 20` that
ends its own follower — through the TPipe stop path, or with
`addArg --pid=HELPER` for the `run` case. The background appender the
growing-file case needs is started by the test, its pid is recorded, and it is
`kill -TERM`ed in that case's own teardown; a final case asserts that no `tail`
process has the test as its parent (**C14**: leaked followers from earlier
sessions were found on this box). No test file installs a `trap … EXIT` of its
own — it would replace ktests' trap and swallow the `__COUNTS__` line.
`007_Bench.sh` starts **no** follower at all: it touches only the refusing path.

The Basis column cites one of:

* **H1–H12**, **H4b** — a pinned fact of [`../thead/PLAN.md`](../thead/PLAN.md)
  §3, mirrored here for tail.
* **T1–T4** — a pinned fact of [`PLAN.md`](PLAN.md) §3 (tail-specific).
* **C1–C19** — a finding of the 2026-09-15 critic pass
  ([`../thead/PLAN.md`](../thead/PLAN.md) §8).
* **P0-C1 / P0-C2** — the two plan facts corrected against the real tool at P0
  (see [`../thead/TEST_COVERAGE_NOTES.md`](../thead/TEST_COVERAGE_NOTES.md));
  P0-C1 (8 records, not 7) is pinned here too.
* **P3-F1** — the tgrep finding this unit inherits with its guard.
* **D4 / D6** — a decision: D4 the GNU dialect gate, D6 final `subshellOk`.
* **§n** — a section of [`PLAN.md`](PLAN.md), or of
  [`../thead/PLAN.md`](../thead/PLAN.md) where the decision is shared, or of
  [README.md](README.md).

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract ([../README.md](../README.md) §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `argv` | the typed option set → the pinned command line, asserted **without running tail** |
| `tool-behaviour` | what GNU coreutils 8.32 `tail` actually does, measured against the bare tool as oracle |
| `representation` | paths and records are **data**: a space, a newline, a leading `-`, a CR, a NUL delimiter, an unterminated last record |
| `boundary` | an edge the happy path never reaches: nothing selected, no path, a missing operand among good ones, nesting, a refused sink |
| `perf` | a [`PLAN.md`](PLAN.md) §4 P1 gate, asserted with a loose ceiling |

**Deliberate gaps** (each is stated in the plans and restated in
[README.md](README.md)):

* **suffix multipliers** (`-n 1K`, `-c 2M`) — refused by the count regex; the
  documented escape hatch `addArg -n 1K` is pinned instead (004 §E);
* **`--retry` / `--follow=name` / `-F`** — not modelled; `addArg` plus `run`;
* **BSD/macOS dialects** (D4);
* **a timeout or a cancellation for `follow`** — there is none, by design
  (**C4**): `each` and `first` block until a consumer calls `TPipe.stop`, and a
  caller who cannot guarantee a stop uses `run` under an external `timeout`.
  `--pid=PID` via `addArg` is the only self-terminating `-f` (**C16**) and is
  pinned in the argv (004 §D) and behaviourally (005 §H);
* **tail's own stderr** — the tool's `tail: …` lines pass through by design and
  their quoting follows the locale (**C10**), so `006` counts *our* lines and the
  tool's separately, while `005` matches the tool's by **prefix**.

---

## 004_Argv.sh — typed options to argv, nothing executed (P0) — 74 cases

**tail is never started in this file.**

### A. lifecycle, and the `__tt_` out-name refusals (15)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.a-vars-present | Create | every declared var (TTail's 7 + TUtil's 5) is present in `${inst}_data` right after `new` | contract | **H4**, §1.2 |
| 004.a-defaults | Create | the documented defaults: booleans `0` (**`follow` included**), `cmd` `tail`, `_lastRc` `-1` | contract | **H4**, §1.2 |
| 004.a-no-arg | Create | `TTail.new t` with no argument leaves `lines` `''` — tail's own default of 10 | boundary | §1.2 |
| 004.a-args-empty | Create | `${t}_args` is EMPTY after `TTail.new t N PATH` | contract | **H1** — the `inherited`-in-a-constructor trap |
| 004.a-paths-verbatim | Create | `${t}_paths` holds the constructor's paths verbatim, once each | representation | §1.2 |
| 004.a-reuse-clean | Create | a REUSED instance name starts clean — every var re-assigned | boundary | **H4** |
| 004.a-delete-chains | Destroy | `delete` removes `_paths`, `_args` AND `_argv` | contract | **H4** |
| 004.a-argv-nothing | argv | `argv` RUNS NOTHING — not even a `cmd` that exists | contract | **H1** |
| 004.a-badout-ttv | argv | `t.argv __tt_v` → rc 2 | contract | **H4b**, thead §2.8, **C8** |
| 004.a-badout-ttp | argv | `t.argv __tt_p` → rc 2 | contract | **H4b**, thead §2.8, **C8** |
| 004.a-badout-tta | toArray | `t.toArray __tt_a` → rc 2, refused BEFORE anything runs | contract | **H4b**, thead §2.8, **C8** |
| 004.a-badout-tu | argv | `t.argv __tu_x` is still rc 2 (TUtil's own prefix) | contract | **H4b**, thead §2.8 |
| 004.a-badout-tg | argv | `t.argv __tg_x` is still rc 2 (the tgrep prefix) | contract | **H4b**, thead §2.8 |
| 004.a-badout-th | argv | `t.argv __th_x` → rc 2 (the thead prefix — all four are registered together) | contract | **H4b**, thead §2.8, **C8** |
| 004.a-badout-paths | argv | `t.argv tA_paths` → rc 2 (the instance's own operand array) | contract | **H4b**, thead §2.8 |

### B. H1 — every option, singly (7)

Class `argv`, basis **H1**, §1.2 throughout.

| ID | Case |
|---|---|
| 004.b-none | no option at all — `tail -- PATH` (tail's own default of 10 lines) |
| 004.b-q | `quiet = 1` → `-q` |
| 004.b-v | `verbose = 1` → `-v` |
| 004.b-z | `zeroTerminated = 1` → `-z` (NUL-delimited INPUT records) |
| 004.b-f | `follow = 1` → `-f` — the sink rules of §2.1 are separate |
| 004.b-n | `lines = 3` → `-n 3` as TWO words |
| 004.b-c | `bytes = 3` → `-c 3` as TWO words |

### C. H1 — combinations, the pinned order, the boolean rule (7)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.c-order-fn | `-f` before `-n`, the pinned order | argv | **H1**, §1.2 |
| 004.c-order-qfn | `-q -f -n 5` — the ORDER is `buildArgv`'s, not the caller's | argv | **H1**, §1.2 |
| 004.c-qzfc | `-q -z -f -c 12` — the full pinned order on one path | argv | **H1**, §1.2 |
| 004.c-v-two-plus | `-v` with two paths and a `+N` count | argv | **H1**, **T1** |
| 004.c-all | EVERYTHING compatible at once, extras last | argv | **H1**, §1.2 |
| 004.c-argv-f | **T2**: `argv` with `follow = 1` STILL yields `-f` — the refusal is a SINK rule, not an argv rule | argv | **T2**, §2.1, **C2** |
| 004.c-bool | a boolean is ON only for the exact string `1` (`follow` included) | contract | thead §2.1 |

### D. H1 — `--` only with paths, extras in place, `paths` (12)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.d-stdin | `TTail.new t N` with no path is the STDIN form — no `--` at all | argv | **H1**, §1.2 |
| 004.d-one-space | one path → `-- 'a b'` | representation | **H1** |
| 004.d-three | three paths, all after the one `--` | argv | **H1** |
| 004.d-dash | a path that starts with `-` is an operand, not a flag | representation | **H1** |
| 004.d-extra-slot | an `addArg` extra lands AFTER the options and BEFORE `--` | argv | **H1** |
| 004.d-extra-replaces | `addArg -n 5` after `lines = 3` yields BOTH — tail is last-flag-wins | argv | **H1**, **C11** |
| 004.d-pid | `addArg --pid=PID` — the only self-terminating `-f` | argv | §2.1, **C16** |
| 004.d-clearargs | `clearArgs` empties the extras again | argv | **H1** |
| 004.d-paths-replace | `t.paths new1 'new 2'` REPLACED both old paths | argv | **H1**, §1.2 |
| 004.d-paths-none | `t.paths` with no argument is the stdin form | boundary | **H1**, §1.2 |
| 004.d-no-accumulate | rebuilding does not ACCUMULATE — two `argv` calls agree | contract | **H1** |
| 004.d-copy | `argv` hands over a COPY — writing it does not touch `${inst}_argv` | contract | **H1** |

### E. H2 — the rc 2 list: nothing runs, RESULT `''`, one line (15)

Every case asserts rc 2, `RESULT ''`, the caller's array untouched,
`${inst}_argv` EMPTY, and exactly ONE `kk.debug` line. Class `contract`, basis
**H2** + [../README.md](../README.md) §1.2 throughout.

| ID | Case | extra basis |
|---|---|---|
| 004.e-cmd | empty `cmd` | §1.2 |
| 004.e-n-and-c | `lines` + `bytes` — tail would silently take the last | §1.2 |
| 004.e-q-and-v | `quiet` + `verbose` | §1.2 |
| 004.e-z-two | `zeroTerminated` with TWO paths | thead §2.3, **C3** |
| 004.e-z-verbose | `zeroTerminated` + `verbose` | thead §2.3, **C3** |
| 004.e-n-x | `lines = x` — the count regex `^[+-]?[0-9]+$` | thead §2.2 |
| 004.e-n-1K | `lines = 1K` — the suffix hatch is `addArg -n 1K` | **C11** |
| 004.e-n-split | `lines = '1 2'` — never re-split into two words | thead §2.2 |
| 004.e-n-doubledash | `lines = '--5'` — one optional sign only | thead §2.2 |
| 004.e-n-20digits | a 20-digit `lines` — the magnitude guard | thead §2.2, **C9** |
| 004.e-c-abc | `bytes = abc` — the same regex | thead §2.2 |
| 004.e-c-20digits | a 20-digit `bytes` | thead §2.2, **C9** |
| 004.e-n-blank | `lines = ' 2'` — no surrounding blanks | thead §2.2 |
| 004.e-halves-ok | each half of a refused pair on its OWN builds fine, **`follow` too** | §2.1 |
| 004.e-z-legal | `zeroTerminated` with ONE path and with none is accepted | thead §2.3 |

### F. T1 — the count travels VERBATIM (12)

`kk.isInt` would turn `+2` into `2`, and for tail those are opposite ends of the
file. Class `argv`, basis **T1**, §2.2, thead §2.2, **C6** throughout.

| ID | Case |
|---|---|
| 004.f-n-plus2 | `lines = +2` → `-n +2` |
| 004.f-n-08 | `lines = 08` → `-n 08` |
| 004.f-n-minus2 | `lines = -2` → `-n -2` |
| 004.f-n-minus0 | `lines = -0` → `-n -0` |
| 004.f-n-plus0 | `lines = +0` → `-n +0` |
| 004.f-n-0 | `lines = 0` → `-n 0` |
| 004.f-c-plus3 | `bytes = +3` → `-c +3` |
| 004.f-c-08 | `bytes = 08` → `-c 08` |
| 004.f-c-minus2 | `bytes = -2` → `-c -2` |
| 004.f-c-minus0 | `bytes = -0` → `-c -0` |
| 004.f-19digits | a 19-digit count PASSES the guard and reaches tail verbatim |
| 004.f-no-writeback | the property still READS what the caller wrote (no write-back) |

### G. H5 — `zeroTerminated` derives the sinks' `-0`, with the P3-F1 guard (6)

Class `contract`, basis **H5**, thead §2.3, **P3-F1**.

| ID | Case |
|---|---|
| 004.g-derive | `zeroTerminated = 1` with one path DERIVES `nul = 1`, `_nulDerived = 1` |
| 004.g-undo | `zeroTerminated = 0` again takes the derived `-0` back off |
| 004.g-caller-set | a MANUAL `nul = 1` with `zeroTerminated = 0` is the caller's and survives |
| 004.g-p3f1 | **P3-F1**: a deriving build does not CLAIM a `nul = 1` the caller already set |
| 004.g-refused | a REFUSED build derives nothing |
| 004.g-crlf | `crlf` is never touched by `buildArgv` |

---

## 005_Run.sh — TTail against GNU tail on a real tree (P0) — 61 cases

### Z. the gate and the tree (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.z-banner | the `tail` on PATH is GNU coreutils — otherwise every case below is a loud SKIP | contract | **D4** |
| 005.z-tree | the fixture files are in place | contract | thead §4 |

### A. H6 — one file, every runner against the bare tool (9)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.a-each | each | `lines = 2`; `each` delivers exactly `tail -n 2`'s records | tool-behaviour | **H6** |
| 005.a-toarray | toArray | `toArray` == `tail -n 3` | tool-behaviour | **H6** |
| 005.a-count | count | `count` is the record count, rc 0, `lastRc` 0 (through the OVERRIDE) | contract | **H6**, **T3** |
| 005.a-first | first | `first` is the FIRST record of the tail window | contract | **H6** |
| 005.a-tolist | toList | `toList` offers every record to an instance with an `.Add` (through the OVERRIDE) | contract | **H6**, **T3** |
| 005.a-run | run | `run` streams tail's own bytes and leaves the raw rc readable | contract | **H6**, README §3 |
| 005.a-unterm | toArray | an UNTERMINATED last line is delivered as a record | representation | **H6**, **C19** |
| 005.a-zero | count/first | `lines = 0` runs tail and delivers NOTHING — rc 0, count 0, `first` rc 1 | boundary | **T1**, **H6** |
| 005.a-odd-names | toArray | a path with a SPACE and one starting with `-` are operands, not flags | representation | **H6** |

### B. H7 — the `==> NAME <==` headers are RECORDS (6)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.b-9 | two TERMINATED 3-line files under `-n 5` are **9** records | tool-behaviour | **H7**, thead §2.4, **C5** |
| 005.b-8 | the same pair with the FIRST file UNTERMINATED is **8** records | tool-behaviour | **H7**, **P0-C1** |
| 005.b-first | `first` on two files is the HEADER of the first one | boundary | **H7** |
| 005.b-quiet | `quiet = 1` on two files is DATA ONLY — 6 records | tool-behaviour | **H7** |
| 005.b-verbose | `verbose = 1` on ONE file forces the header — 2 records for `-n 1` | tool-behaviour | **H7** |
| 005.b-parity | ONE file without `verbose` has NO header (tool parity) | tool-behaviour | **H7** |

### C. H8 — a missing operand among good ones (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.c-toarray | `toArray` over good+MISSING+good — rc 1, `RESULT` = the real count, `lastRc` 1 | contract | **H8**, **T3**, §3 (a) |
| 005.c-count-each | `count` and `each` on the same operands keep everything too | contract | **H8**, **T3** |
| 005.c-one-line | the partial-failure path emits exactly ONE line of ours; tail's own passes through, matched by PREFIX | contract | **H8**, §3 (b), **C10** |
| 005.c-missing-alone | a MISSING file alone — zero records, rc 1, `lastRc` 1 | boundary | **H8** |

### D. H9 — tail is a BYTE tool: the CR survives, `crlf` trims it (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.d-keep | `crlf = 0` (the default) keeps the CR | representation | **H9**, thead §2.6 |
| 005.d-strip | `crlf = 1` strips exactly ONE CR per record | representation | **H9**, thead §2.6 |
| 005.d-bytes | `crlf = 1` works in BYTES mode too (`bytes = 3` cuts mid-record) | representation | **H9**, thead §2.6 |

### E. H10 — `-z`: NUL records in, NUL records out (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.e-nul | `zeroTerminated = 1` on a NUL-separated file gives NUL records | representation | **H10**, thead §2.3 |
| 005.e-unterm | the UNTERMINATED last NUL record is delivered | representation | **H10**, **C19** |
| 005.e-text | a TEXT file under `-z` is ONE record for any `lines >= 1` | tool-behaviour | **H10**, **C3** |

### F. T1 — the sign table: `+N` means FROM line N (10)

The mirror of head's table, and the reason `kk.isInt` is forbidden. Class
`tool-behaviour`, basis **T1**, §2.2, **C6** throughout.

| ID | Case |
|---|---|
| 005.f-2 | `lines = 2` — the LAST 2 |
| 005.f-minus2 | `lines = -2` — the last 2 as well |
| 005.f-plus3 | `lines = +3` — FROM line 3 (the mirror of head's `+N`) |
| 005.f-plus0 | `lines = +0` — EVERYTHING |
| 005.f-minus0 | `lines = -0` — nothing |
| 005.f-0 | `lines = 0` — nothing |
| 005.f-plus2-count | `lines = +2` on a 5-line file counts **4** — the pin `kk.isInt` would have broken |
| 005.f-08 | `lines = 08` is DECIMAL 8, pinned on an 11-line file |
| 005.f-addarg-n | `addArg -n 5` after `lines = 3` — the TOOL takes 5 (extras are last) — basis **H1**, **C11** |
| 005.f-c-plus3 | `bytes = +3` starts at BYTE 3 |

### G. T4 — `TTail.take N PATH...`, the static one-liner (11)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g-direct | `TTail.take 2 f` == `tail -n 2 -- f`, DIRECT | tool-behaviour | **T4** |
| 005.g-plus2 | `TTail.take +2 f` == `tail -n +2 -- f` | tool-behaviour | **T4**, §2.2 |
| 005.g-pipe | the same through a PIPE (`\| od -c`) — byte-identical | contract | **T4** |
| 005.g-procsub | the same through `< <( )` — byte-identical | contract | **T4** |
| 005.g-two-paths | `take` with TWO paths carries the headers (tool parity) | tool-behaviour | **T4**, **C13** |
| 005.g-no-path | `TTail.take` with NO path is rc 2, prints nothing, one line | boundary | **T4**, thead §2.7 |
| 005.g-bad-count | `TTail.take` with a BAD count is rc 2 and runs nothing | boundary | **T4**, thead §2.2 |
| 005.g-missing | `take` on a MISSING file is rc 1 (tail's own status, mapped) | boundary | **T4** |
| 005.g-cleanup | `take` deletes its throw-away instance and bumps `__TT_SEQ` | contract | **T4**, thead §2.7 |
| 005.g-nested | a nested `take` inside an outer `each` — both complete, the outer instance survives | boundary | **T4**, thead §2.7 |
| 005.g-tpipe | `take` composes with both TPipe forms | contract | **T4** |

### H. T2/T3 — `follow`: three sinks refuse, two stream (13)

The block this unit exists for. Every case that starts a follower ends it.

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.h-rc1-toarray | `toArray` with `follow = 0` and a missing operand — rc 1, `RESULT` = the real count | contract | **T3**, §2.1, **C1** — the naive `inherited` spelling would answer 0 |
| 005.h-rc1-count | `count` with `follow = 0` and a missing operand — rc 1, `RESULT` = the real count | contract | **T3**, **C1** |
| 005.h-rc1-tolist | `toList` with `follow = 0` and a missing operand — rc 1, `RESULT` = the real count | contract | **T3**, **C1** |
| 005.h-rc2-through | the three overrides also pass a rc 2 build straight through | contract | **T3**, **H2** |
| 005.h-refuse-toarray | `toArray` with `follow = 1` is rc 2 and NOTHING runs (a flag-file producer proves it) | boundary | **T2**, §2.1, **C2**, **C4** |
| 005.h-refuse-count | `count` with `follow = 1` is rc 2 and NOTHING runs | boundary | **T2**, §2.1 |
| 005.h-refuse-tolist | `toList` with `follow = 1` is rc 2 and NOTHING runs (no kcl list calls `TPipe.stop`) | boundary | **T2**, §2.1, **C4** |
| 005.h-refuse-msg | the refusal names the reason and points at the shapes that DO work | contract | **T2**, §2.1 |
| 005.h-refuse-state | `RESULT` is `''` on the refusal and the caller's array is left alone | contract | **T2**, [../README.md](../README.md) §1.2 |
| 005.h-each-stop | `each` + a stopping callback — rc 0, `lastRc` **143**, exactly one record, in a child under `timeout 20` | tool-behaviour | **T2**, §2.1, §1.1 |
| 005.h-first | `first` on a follow stream returns the last line and stops | tool-behaviour | **T2**, §2.1 |
| 005.h-run-grow | `run` with `follow = 1` streams a line appended while it waits (a bounded READY-flag handshake, `--pid=HELPER` ends the follow) | tool-behaviour | **T2**, §1.1, **C16** |
| 005.h-no-leak | no follower of ours survived the section | contract | **T2**, **C14** |

---

## 006_Contract.sh — the kcl contract for TTail (P0) — 55 cases

### 0. source integrity (11)

Class `contract` throughout.

| ID | Case | Basis |
|---|---|---|
| 006.0-parse | the unit source parses (`bash -n`) | [../README.md](../README.md) §1 |
| 006.0-quote | no single-quoted `printf` format is left open at end of line | the P2 sweep incident |
| 006.0-inline-cr | no member body carries an inline `$'…'` | thead §6 |
| 006.0-this | no internal member call is spelled `$this.NAME` | tutil PLAN §2.2 |
| 006.0-ctor | the CONSTRUCTOR calls `parent.constructor tail`, never `inherited` | thead §2.1 |
| 006.0-dtor | the DESTRUCTOR frees `${inst}_paths` and then chains with `inherited` | thead §2.1 |
| 006.0-no-isint | the count is NOT validated with `kk.isInt` — it would fold `+2` into `2` | §2.2, **C6** |
| 006.0-regex-var | the count regex is held in a VARIABLE and applied with `[[ =~ ]]` | thead §6 |
| 006.0-one-source | the unit sources ONLY `../tutil/tutil.sh` — `TTail : THead` would be wrong, `+N` differs | header, **C15** |
| 006.0-override-rc | the three overridden sinks use the rc-PRESERVING spelling (`inherited X "$@" \|\| rc=$?; n=$RESULT; kk._return $n; return $rc`) | **C1**, thead §6, §2.1 |
| 006.0-no-shadow | no `var` shadows a TUtil or kklass member name | thead §1.2 reserved set |

### Z. the gate (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.z-banner | the `tail` on PATH is GNU coreutils | contract | **D4** |

### 1. `set -eu` — the instance and BOTH TPipe forms, every outcome (22)

Every child runs under `set -eu` with `timeout 20` and its own stdin, and every
sink call in a child is guarded `|| rc=$?`. Class `contract`, basis **H12** +
[../README.md](../README.md) §1 throughout.

| ID | Case | extra basis |
|---|---|---|
| 006.1-load | the unit loads under `set -eu` | §1.4 |
| 006.1-load-twice | the unit loads TWICE under `set -eu` (every re-source guard holds) | §1.4 |
| 006.1-each | `t.each`: an instance that delivers records | **H6** |
| 006.1-form2 | form 2: `TPipe.each CB -- "${argv[@]}"` with the argv TTail built | **T4** |
| 006.1-form2-take | form 2 with `TTail.take` as the producer command | **T4** |
| 006.1-form1 | form 1: a REAL pipe under `shopt -s lastpipe` | **T4** |
| 006.1-sinks | every `func` sink on an instance that delivers | **H6**, **T3** |
| 006.1-tolist | `toList` into a kklass instance with an `.Add` | **T3** |
| 006.1-tool-error | a TOOL ERROR (a missing file, raw 1) — rc 1, the child survives | **H8** |
| 006.1-partial | PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT | **H8**, **T3** |
| 006.1-refused | a REFUSED build (`lines` + `bytes`) — rc 2, nothing runs, no abort | **H2** |
| 006.1-follow-refusal | the FOLLOW refusal (`toArray` with `follow = 1`) — rc 2, no abort, nothing runs | **T2**, §2.1 |
| 006.1-empty-cmd | an EMPTY `cmd` — rc 2 from every runner, no abort | **H2** |
| 006.1-bad-lines | a bad `lines` — rc 2, no abort | **H2** |
| 006.1-z-two | `zeroTerminated` with two paths — rc 2, no abort | **H2**, thead §2.3 |
| 006.1-take-nopath | `TTail.take` with no path — rc 2, no abort, nothing printed | **T4** |
| 006.1-run-stream | `run` streams and the raw rc is readable afterwards | README §3 |
| 006.1-delete-clean | `delete` on an instance that never ran anything | §1.9 |
| 006.1-stdin | an instance reading STDIN (no path) under `set -eu` | §1.2 |
| 006.1-cmdsub | the `$( )` position: a `func` sink prints its value exactly ONCE | §1.1 |
| 006.1-d6 | **D6 final**: `subshellOk = 1` silences TPipe's subshell warning through TTail | **D6** |
| 006.1-unguarded | **H12**: an UNGUARDED sink call with rc 1 aborts a `set -eu` caller | **C18** |

### 2. the debug switch — one line per rc 2 / tool-error path (21)

Class `contract`, basis [../README.md](../README.md) §1.2 throughout.

| ID | Case | extra basis |
|---|---|---|
| 006.2-nc-each | rc 2: `lines` + `bytes` — one line, through `each` | **H2** |
| 006.2-nc-count | rc 2: `lines` + `bytes` — one line, through `count` | **H2**, **T3** |
| 006.2-qv | rc 2: `quiet` + `verbose` — one line | **H2** |
| 006.2-z-two | rc 2: `zeroTerminated` with two paths — one line | **H2**, thead §2.3 |
| 006.2-z-verbose | rc 2: `zeroTerminated` + `verbose` — one line | **H2**, thead §2.3 |
| 006.2-bad-lines | rc 2: a bad `lines` — one line | **H2**, thead §2.2 |
| 006.2-empty-cmd | rc 2: an empty `cmd` — one line | **H2** |
| 006.2-take-nopath | rc 2: `TTail.take` with no path — one line | **T4** |
| 006.2-take-badn | rc 2: `TTail.take` with a bad count — one line | **T4** |
| 006.2-badout | rc 2: `toArray` with a bad out-name — one line (TUtil's own check) | thead §2.8 |
| 006.2-badout-tt | rc 2: `toArray __tt_x` — one line (the `__tt_` prefix) | **H4b**, **C8** |
| 006.2-follow-toarray | rc 2: `toArray` with `follow = 1` — one line | **T2**, §2.1 |
| 006.2-follow-count | rc 2: `count` with `follow = 1` — one line | **T2**, §2.1 |
| 006.2-follow-tolist | rc 2: `toList` with `follow = 1` — one line | **T2**, §2.1 |
| 006.2-raw1-partial | tail raw 1 (a missing operand among good ones) — rc 1 and one line | **H8** |
| 006.2-raw1-alone | tail raw 1 (the only operand missing) — rc 1 and one line | **H8** |
| 006.2-silent-run | rc 0: a successful `run` says NOTHING | §1.2 |
| 006.2-silent-each | rc 0: `each` on records says NOTHING | §1.2 |
| 006.2-silent-toarray | rc 0: `toArray` on records says NOTHING | §1.2 |
| 006.2-silent-take | rc 0: `TTail.take` that succeeded says NOTHING | §1.2 |
| 006.2-wording | the "tail exited" line names TTail, and tail's OWN line is left alone | §3 (b), **C10** |

*(11 + 1 + 22 + 21 = 55.)*

---

## 007_Bench.sh — the PLAN §4 P1 gate as assertions (P1) — 10 cases

The real gate is `../bench.sh`, run by hand on an idle box: **1.5×**, from the
medians of 21 interleaved runs. This file asserts the same shapes with a
**10× ceiling** because ktests runs test files threaded. Corpus: 2000 lines built
with `kt_fixture_tmpdir_create`; no `trap … EXIT` of its own; **no follower is
ever started** — only the refusing path of the three overrides is touched.

| ID | Case | Class | Basis |
|---|---|---|---|
| 007.z-banner | the `tail` on PATH is GNU coreutils — otherwise every timed case is a loud SKIP | contract | **D4** |
| 007.a-gate-1 | `TTail.take 1` costs at most 10× a bare `tail -n 1`, medians of 7 INTERLEAVED runs, both sides delivering 1 record | perf | §4 P1, **C7** |
| 007.a-gate-half | `TTail.take 1000` costs at most 10× a bare `tail -n 1000`, same treatment, both sides delivering 1000 records | perf | §4 P1, **C7** |
| 007.a-delta | the take delta IS one instance: `new` + `argv` + `delete` under 50 ms/call (3.2–3.4 ms idle) | perf | §4 P1 |
| 007.b-nothing | 200 `buildArgv`/`argv` calls invoke the `cmd` ZERO times, leave `$BASHPID` unchanged, and build the 7 words with `-f` in its slot | contract | **H1**, **T2** |
| 007.b-constant | the build stays constant-cost: 201 rebuilds do not accumulate words | contract | **H1** |
| 007.c-count | `t.count` over 200 records costs at most 10× the `wc -l` equivalent, both answering 200 | perf | README §9 |
| 007.d-sinks | the five sinks (the three OVERRIDDEN ones included): 2 records each, the callback and `.Add` both in THIS process | contract | §1.7 zero forks, **T3** |
| 007.d-builders | the seven builder members, `run` and `TTail.take` leave `$BASHPID` untouched — the only fork per call is tail itself | contract | §1.7 zero forks |
| 007.d-follow-refusals | the three `follow = 1` refusals are bash-only: rc 2 from all three, `RESULT ''`, `lastRc` still `-1` (nothing ran), `$BASHPID` unchanged | contract | **T2**, §2.1 |
