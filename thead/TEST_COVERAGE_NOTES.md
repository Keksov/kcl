# thead — test coverage notes

**Status: FINALIZED at P1 (2026-09-16).** Suite `004`–`007` = **182 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single`, against **GNU coreutils 8.32**. The
per-file row counts below sum to 182 — 73 + 50 + 50 + 9 — and **every case in
the suite has a row**.

**Protocol.** `THead` has no FPC upstream: it is the third wrapper on
[`TUtil`](../tutil/README.md), which is itself a kcl addition (see
[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)). The oracle is therefore **the
bare GNU tool on the same fixture**, run with the same argv, never a second call
into the code under test. Decision **D4** (of the tpipe plan) pins the *dialect*
— GNU coreutils 8.32, the build MSYS2 ships — not a binary, so every behavioural
file opens with the **GNU banner gate**: if `head --version` does not begin with
`head (GNU coreutils) `, every behavioural case is a loud SKIP and the case
**count is unchanged**.

The suite splits in two on purpose:

* **`004_Argv.sh` never executes head.** Every typed option is pinned by
  comparing the built array, which is what `argv NAME` exists for; it is the fast
  half and it is where a wrapper's surface actually lives.
* **`005`/`006`/`007` run the tool** on a fixture tree with a 5-line and an
  11-line file, two 3-line files for the header cases, an unterminated file
  (used alone *and* as the first of two operands), a CRLF file, a NUL-separated
  file whose last record is unterminated, a name with a space and a name
  starting with `-`.

The Basis column cites one of:

* **H1–H12**, **H4b** — a pinned fact of [`PLAN.md`](PLAN.md) §3.
* **C1–C19** — a finding of the 2026-09-15 critic pass ([`PLAN.md`](PLAN.md)
  §8). The ttail-only ones (C1, C2, C4, C14, C16) are pinned in
  [`../ttail/TEST_COVERAGE_NOTES.md`](../ttail/TEST_COVERAGE_NOTES.md).
* **P0-C1 / P0-C2** — the two plan facts the implementing worker **corrected**
  against the real tool at P0 and the supervisor accepted (see below).
* **P3-F1** — the tgrep finding this unit inherits with its guard
  ([../tgrep/README.md §4](../tgrep/README.md#4--z-and-nul-framing--the-derived--0)).
* **D4 / D6** — a decision: D4 the GNU dialect gate, D6 final `subshellOk`.
* **§n** — a section of [`PLAN.md`](PLAN.md) (or of [README.md](README.md)).

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract ([../README.md](../README.md) §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `argv` | the typed option set → the pinned command line, asserted **without running head** |
| `tool-behaviour` | what GNU coreutils 8.32 `head` actually does, measured against the bare tool as oracle |
| `representation` | paths and records are **data**: a space, a newline, a leading `-`, a CR, a NUL delimiter, an unterminated last record |
| `boundary` | an edge the happy path never reaches: nothing selected, no path, a missing operand among good ones, a directory operand, nesting |
| `perf` | a [`PLAN.md`](PLAN.md) §5 P1 gate, asserted with a loose ceiling |

**The two P0 corrections.** Both are plan facts that the tool contradicted, and
both are now written into `PLAN.md` (§2.4/§2.5, H3/H7, §8) with the measurement:

* **P0-C1** — §2.4 and the critic's finding C5 said two 3-line files under
  `-n 5` with the **first** unterminated are **7** records. Measured: **8**. The
  separator's leading `\n` terminates the previous file's last line instead of
  standing alone as an empty record, so exactly ONE record is lost relative to
  the terminated pair's 9. `005` §B pins the measured 8.
* **P0-C2** — §2.5 and C9 said an overflowing count comes back as an ordinary
  rc 1 with the tool's own message. A 19-digit **`-n`** is rc **0** (it fits
  `uintmax`); the shape that really overflows is a **negative byte** count,
  `head -c -9999999999999999999` → rc 1 *invalid number of bytes: Value too
  large*. `005` §F pins that shape.

**Deliberate gaps** (each is stated in [`PLAN.md`](PLAN.md) §1.3 and restated in
[README.md](README.md)):

* **suffix multipliers** (`-n 1K`, `-c 2M`) — refused by the count regex; the
  documented escape hatch `addArg -n 1K` is pinned instead (004 §E, 005 §F);
* **BSD/macOS dialects** (D4) — nothing to assert on this box;
* **anything else in `head --help`** (`--help`, `--version`) — `addArg`;
* **head's own stderr** — the tool's `head: …` lines pass through by design and
  their quoting follows the locale (C10), so `006` counts *our* lines and the
  tool's separately and asserts only that ours are silent, while `005` matches
  the tool's by **prefix**.

---

## 004_Argv.sh — typed options to argv, nothing executed (P0) — 73 cases

**head is never started in this file.** Every case either compares the array
`h.argv GOT` handed over, or asserts a refusal.

### A. lifecycle, and the `__th_` out-name refusals (15)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.a-vars-present | Create | every declared var (THead's 6 + TUtil's 5) is present in `${inst}_data` right after `new` | contract | **H4**, §2.1 |
| 004.a-defaults | Create | the documented defaults: booleans `0`, `bytes` `''`, `cmd` `head`, `_lastRc` `-1`, and the constructor's N in `lines` | contract | **H4**, §2.1 |
| 004.a-no-arg | Create | `THead.new h` with no argument leaves `lines` `''` — head's own default of 10 | boundary | §1.2 |
| 004.a-args-empty | Create | `${h}_args` is EMPTY after `THead.new h N PATH` | contract | **H1**, §2.1 — the `inherited`-in-a-constructor trap would have doubled every path |
| 004.a-paths-verbatim | Create | `${h}_paths` holds the constructor's paths verbatim, once each (a space, a leading `-`, a NEWLINE) | representation | §2.1 |
| 004.a-reuse-clean | Create | a REUSED instance name starts clean — every var re-assigned | boundary | **H4**, §2.1 |
| 004.a-delete-chains | Destroy | `delete` removes `_paths`, `_args` AND `_argv` (the descendant destructor chains with `inherited`) | contract | **H4**, §2.1 |
| 004.a-argv-nothing | argv | `argv` RUNS NOTHING — not even a `cmd` that exists (a flag file stays absent) | contract | **H1** |
| 004.a-badout-thv | argv | `h.argv __th_v` → rc 2 | contract | **H4b**, §2.8, **C8** |
| 004.a-badout-thp | argv | `h.argv __th_p` → rc 2 | contract | **H4b**, §2.8, **C8** |
| 004.a-badout-tha | toArray | `h.toArray __th_a` → rc 2, refused BEFORE anything runs | contract | **H4b**, §2.8, **C8** |
| 004.a-badout-tu | argv | `h.argv __tu_x` is still rc 2 (TUtil's own prefix) | contract | **H4b**, §2.8 |
| 004.a-badout-tg | argv | `h.argv __tg_x` is still rc 2 (the tgrep prefix) | contract | **H4b**, §2.8 |
| 004.a-badout-tt | argv | `h.argv __tt_x` → rc 2 (the ttail prefix — all four are registered together) | contract | **H4b**, §2.8, **C8** |
| 004.a-badout-paths | argv | `h.argv hA_paths` → rc 2 (the instance's own operand array) | contract | **H4b**, §2.8 |

### B. H1 — every option, singly (6)

Each case resets the instance, sets exactly one property, and compares the whole
array against `head FLAG -- f`. Class `argv`, basis **H1**, §1.2 throughout.

| ID | Case |
|---|---|
| 004.b-none | no option at all — `head -- PATH` (head's own default of 10 lines) |
| 004.b-q | `quiet = 1` → `-q` |
| 004.b-v | `verbose = 1` → `-v` |
| 004.b-z | `zeroTerminated = 1` → `-z` (NUL-delimited INPUT records) |
| 004.b-n | `lines = 3` → `-n 3` as TWO words |
| 004.b-c | `bytes = 3` → `-c 3` as TWO words |

### C. H1 — combinations, the pinned order, the boolean rule (6)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.c-order-qn | `-q` before `-n`, the pinned order | argv | **H1**, §1.2 |
| 004.c-order-assign | the ORDER is `buildArgv`'s, not the order the caller assigned in | argv | **H1**, §1.2 |
| 004.c-qzc | `-q -z -c 12` — one path, so `-z` is allowed | argv | **H1**, §2.3 |
| 004.c-v-two-neg | `-v` with two paths and a negative count | argv | **H1** |
| 004.c-all | EVERYTHING compatible at once — the full pinned order with an extra | argv | **H1**, §1.2 |
| 004.c-bool | a boolean is ON only for the exact string `1` (`2`, `yes`, `true`, `on`, `01`, `-1`, `' 1'`, `'1 '` are all OFF) | contract | §2.1 — a property is compared as a string, never `(( x ))` |

### D. H1 — `--` only with paths, extras in place, `paths` (12)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.d-stdin | `THead.new h N` with no path is the STDIN form — no `--` at all | argv | **H1**, §1.2 |
| 004.d-one-space | one path → `-- 'a b'` (a space is safe by construction) | representation | **H1** |
| 004.d-three | three paths, all after the one `--` | argv | **H1** |
| 004.d-dash | a path that starts with `-` is an operand, not a flag | representation | **H1** |
| 004.d-extra-slot | an `addArg` extra lands AFTER the options and BEFORE `--` | argv | **H1**, §1.3 |
| 004.d-extra-replaces | `addArg -n 5` after `lines = 3` yields BOTH — head is last-flag-wins | argv | **H1**, §1.3, **C11** |
| 004.d-extra-order | several extras keep their order, still between the options and `--` | argv | **H1** |
| 004.d-clearargs | `clearArgs` empties the extras again | argv | **H1** |
| 004.d-paths-replace | `h.paths new1 'new 2'` REPLACED both old paths | argv | **H1**, §1.2 |
| 004.d-paths-none | `h.paths` with no argument is the stdin form | boundary | **H1**, §1.2 |
| 004.d-no-accumulate | rebuilding does not ACCUMULATE — two `argv` calls agree | contract | **H1** |
| 004.d-copy | `argv` hands over a COPY — writing it does not touch `${inst}_argv` | contract | **H1** |

### E. H2 — the rc 2 list: nothing runs, RESULT `''`, one line (15)

Every case asserts **all five**: rc 2, `RESULT ''`, the caller's array untouched,
`${inst}_argv` EMPTY, and exactly ONE `kk.debug` line naming the reason. Class
`contract`, basis **H2** + [../README.md](../README.md) §1.2 throughout.

| ID | Case | extra basis |
|---|---|---|
| 004.e-cmd | empty `cmd` | §2.1 |
| 004.e-n-and-c | `lines` + `bytes` (`-n` and `-c`) — head would silently take the last | §1.2 |
| 004.e-q-and-v | `quiet` + `verbose` — head takes both, last flag wins | §1.2 |
| 004.e-z-two | `zeroTerminated` with TWO paths — the headers stay `\n`-framed under `-z` | §2.3, **C3** |
| 004.e-z-verbose | `zeroTerminated` + `verbose` — a forced header would frame wrong | §2.3, **C3** |
| 004.e-n-x | `lines = x` — the count regex `^[+-]?[0-9]+$` | §2.2 |
| 004.e-n-1K | `lines = 1K` — the suffix hatch is `addArg -n 1K` | §1.3, **C11** |
| 004.e-n-split | `lines = '1 2'` — never re-split into two words | §2.2 |
| 004.e-n-doubledash | `lines = '--5'` — one optional sign only | §2.2 |
| 004.e-n-20digits | a 20-digit `lines` — the magnitude guard, before the tool sees it | §2.2, **C9** |
| 004.e-c-abc | `bytes = abc` — the same regex | §2.2 |
| 004.e-c-20digits | a 20-digit `bytes` | §2.2, **C9** |
| 004.e-n-blank | `lines = ' 2'` — no surrounding blanks | §2.2 |
| 004.e-halves-ok | each half of a refused pair on its OWN builds fine — only the COMBINATION is refused | §1.2 |
| 004.e-z-legal | `zeroTerminated` with ONE path, with none, and with `-q` all build | §2.3 |

### F. H3 — the count travels VERBATIM (13)

`kk.isInt` is deliberately not used: it strips the sign and folds `+0`/`-0` into
`0`, and head reads those as opposite requests. Class `argv`, basis **H3**, §2.2,
**C6** throughout.

| ID | Case |
|---|---|
| 004.f-n-08 | `lines = 08` → `-n 08` |
| 004.f-n-plus3 | `lines = +3` → `-n +3` |
| 004.f-n-minus2 | `lines = -2` → `-n -2` |
| 004.f-n-minus0 | `lines = -0` → `-n -0` |
| 004.f-n-plus0 | `lines = +0` → `-n +0` |
| 004.f-n-0 | `lines = 0` → `-n 0` |
| 004.f-c-08 | `bytes = 08` → `-c 08` |
| 004.f-c-plus3 | `bytes = +3` → `-c +3` |
| 004.f-c-minus2 | `bytes = -2` → `-c -2` |
| 004.f-c-minus0 | `bytes = -0` → `-c -0` |
| 004.f-19digits | a 19-digit count PASSES the guard and reaches head verbatim (20 is rc 2, §E) |
| 004.f-19digits-sign | a 19-digit count with a SIGN passes too — the sign is not a digit |
| 004.f-no-writeback | the property still READS `08` / `-0` after a build (no write-back through a nameref) |

### G. H5 — `zeroTerminated` derives the sinks' `-0`, with the P3-F1 guard (6)

The four-state sequence of tgrep 004 §G, re-run for this unit. Class `contract`,
basis **H5**, §2.3, **P3-F1**.

| ID | Case |
|---|---|
| 004.g-derive | `zeroTerminated = 1` with one path DERIVES `nul = 1`, `_nulDerived = 1`, and `-z` is in the argv |
| 004.g-undo | `zeroTerminated = 0` again takes the derived `-0` back off |
| 004.g-caller-set | a MANUAL `nul = 1` with `zeroTerminated = 0` is the caller's and survives a build |
| 004.g-p3f1 | **P3-F1**: a deriving build does not CLAIM a `nul = 1` the caller already set — `nul` stays 1 through `-z` and back, `_nulDerived` never claims it |
| 004.g-refused | a REFUSED build derives nothing (`-z` with two paths never reaches the rule) |
| 004.g-crlf | `crlf` is never touched by `buildArgv` — the derivation mutates no other state |

---

## 005_Run.sh — THead against GNU head on a real tree (P0) — 50 cases

The bare tool is the oracle everywhere. Children run under `timeout 20`; calls
that make head itself write to stderr get `2>/dev/null`, and where the count
matters the helper separates OUR lines from the tool's.

### Z. the gate and the tree (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.z-banner | the `head` on PATH is GNU coreutils — otherwise every case below is a loud SKIP | contract | **D4** |
| 005.z-tree | the 9 fixture files are in place | contract | §4 |

### A. H6 — one file, every runner against the bare tool (9)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.a-each | each | `lines = 2`; `each` delivers exactly `head -n 2`'s records | tool-behaviour | **H6** |
| 005.a-toarray | toArray | `toArray` == `head -n 3` | tool-behaviour | **H6** |
| 005.a-count | count | `count` is the record count, rc 0, `lastRc` 0 | contract | **H6** |
| 005.a-first | first | `first` is the FIRST record and then stops the producer | contract | **H6** |
| 005.a-tolist | toList | `toList` offers every record to an instance with an `.Add` | contract | **H6** |
| 005.a-run | run | `run` streams head's own bytes and leaves the raw rc readable | contract | **H6**, README §3 |
| 005.a-unterm | toArray | an UNTERMINATED last line is delivered as a record | representation | **H6**, **C19** |
| 005.a-zero | count/first | `lines = 0` runs head and delivers NOTHING — rc 0, count 0, `first` rc 1 | boundary | **H3**, **H6** |
| 005.a-odd-names | toArray | a path with a SPACE and one starting with `-` are operands, not flags | representation | **H6** |

### B. H7 — the `==> NAME <==` headers are RECORDS (6)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.b-9 | two TERMINATED 3-line files under `-n 5` are **9** records | tool-behaviour | **H7**, §2.4, **C5** |
| 005.b-8 | the same pair with the FIRST file UNTERMINATED is **8** records | tool-behaviour | **H7**, §2.4, **P0-C1** (the critic's 7 was off by one) |
| 005.b-first | `first` on two files is the HEADER of the first one | boundary | **H7**, §2.4 |
| 005.b-quiet | `quiet = 1` on two files is DATA ONLY — 6 records | tool-behaviour | **H7** |
| 005.b-verbose | `verbose = 1` on ONE file forces the header — 2 records for `-n 1` | tool-behaviour | **H7** |
| 005.b-parity | ONE file without `verbose` has NO header (tool parity, default `quiet = 0`) | tool-behaviour | **H7**, §2.4 |

### C. H8 — a missing operand among good ones (5)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.c-toarray | `toArray` over good+MISSING+good — rc 1, `RESULT` = the real count, `lastRc` 1 | contract | **H8**, §2.5 (a) |
| 005.c-count-each | `count` and `each` on the same operands keep everything too | contract | **H8**, §2.5 (a) |
| 005.c-one-line | the partial-failure path emits exactly ONE line of ours; head's own passes through and is matched by PREFIX | contract | **H8**, §2.5 (b), **C10** |
| 005.c-missing-alone | a MISSING file alone — zero records, rc 1, `lastRc` 1 | boundary | **H8** |
| 005.c-dir | a DIRECTORY operand is rc 1 with head's own message (never rc 2) | boundary | **H8**, §1.1 |

### D. H9 — head is a BYTE tool: the CR survives, `crlf` trims it (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.d-keep | `crlf = 0` (the default) keeps the CR — this is where head differs from grep | representation | **H9**, §2.6 |
| 005.d-strip | `crlf = 1` strips exactly ONE CR per record | representation | **H9**, §2.6 |
| 005.d-bytes | `crlf = 1` works in BYTES mode too (`bytes = 5` cuts mid-record) | representation | **H9**, §2.6 |

### E. H10 — `-z`: NUL records in, NUL records out (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.e-nul | `zeroTerminated = 1` on a NUL-separated file gives NUL records | representation | **H10**, §2.3 |
| 005.e-unterm | the UNTERMINATED last NUL record is delivered (TPipe's `\|\| [[ -n ]]` tail) | representation | **H10**, **C19** |
| 005.e-text | a TEXT file under `-z` is ONE record for any `lines >= 1` | tool-behaviour | **H10**, §2.3, **C3** |

### F. H3 — the sign table, behaviourally (11)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.f-2 | `lines = 2` — the first 2 | tool-behaviour | **H3**, §2.2 |
| 005.f-plus3 | `lines = +3` — head reads `+N` as plain N (unlike tail) | tool-behaviour | **H3**, §2.2, **C6** |
| 005.f-minus2 | `lines = -2` — ALL BUT THE LAST 2 | tool-behaviour | **H3**, §2.2, **C6** |
| 005.f-minus0 | `lines = -0` — EVERYTHING ("all but the last 0") | tool-behaviour | **H3**, §2.2, **C6** |
| 005.f-plus0 | `lines = +0` — nothing | tool-behaviour | **H3**, §2.2, **C6** |
| 005.f-0 | `lines = 0` — nothing | tool-behaviour | **H3**, §2.2 |
| 005.f-08 | `lines = 08` is DECIMAL 8, pinned on an 11-line file | tool-behaviour | **H3**, §2.2 |
| 005.f-addarg-n | `addArg -n 5` after `lines = 3` — the TOOL takes 5 (extras are last) | tool-behaviour | **H1**, §1.3, **C11** |
| 005.f-addarg-c | `addArg -c 4` after `lines = 3` even switches head to BYTE mode | tool-behaviour | §1.3, **C11** |
| 005.f-c-minus3 | `bytes = -3` is "all but the last 3 bytes" | tool-behaviour | **H3**, §1.1 |
| 005.f-c-19digits | a 19-digit `bytes = -9999999999999999999` reaches head and is its OWN rc 1 ("Value too large") | boundary | **H3**, §2.5, **P0-C2** |

### G. H11 — `THead.take N PATH...`, the static one-liner (11)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g-direct | `THead.take 2 f` == `head -n 2 -- f`, DIRECT | tool-behaviour | **H11**, §2.7 |
| 005.g-pipe | the same through a PIPE (`\| od -c`) — byte-identical | contract | **H11**, §2.7 |
| 005.g-procsub | the same through `< <( )` — byte-identical | contract | **H11**, §2.7 |
| 005.g-two-paths | `take` with TWO paths carries the headers (tool parity) | tool-behaviour | **H11**, §2.7, **C13** |
| 005.g-signs | `take` accepts `+N` and `-N` verbatim | argv | **H11**, §2.2 |
| 005.g-no-path | `THead.take` with NO path is rc 2, prints nothing, one line | boundary | **H11**, §2.7 |
| 005.g-bad-count | `THead.take` with a BAD count is rc 2 and runs nothing | boundary | **H11**, §2.2 |
| 005.g-missing | `take` on a MISSING file is rc 1 (head's own status, mapped) | boundary | **H11**, §2.5 |
| 005.g-cleanup | `take` deletes its throw-away instance and bumps `__TH_SEQ` | contract | **H11**, §2.7 |
| 005.g-nested | a nested `take` inside an outer `each` — both complete, the outer instance survives | boundary | **H11**, §2.7 |
| 005.g-tpipe | `take` composes with both TPipe forms | contract | **H11**, §2.7 |

---

## 006_Contract.sh — the kcl contract for THead (P0) — 50 cases

### 0. source integrity (10)

A sweeping mechanical edit must not silently mangle the file: two earlier kcl
sweeps corrupted sources while the tests stayed green. Class `contract`
throughout.

| ID | Case | Basis |
|---|---|---|
| 006.0-parse | the unit source parses (`bash -n`) | [../README.md](../README.md) §1 |
| 006.0-quote | no single-quoted `printf` format is left open at end of line | the P2 sweep incident |
| 006.0-inline-cr | no member body carries an inline `$'…'` (it does not survive `build`'s `declare -f` round trip) | §6 |
| 006.0-this | no internal member call is spelled `$this.NAME` | tutil PLAN §2.2 |
| 006.0-ctor | the CONSTRUCTOR calls `parent.constructor head`, never `inherited` | §2.1 |
| 006.0-dtor | the DESTRUCTOR frees `${inst}_paths` and then chains with `inherited` | §2.1 |
| 006.0-no-isint | the count is NOT validated with `kk.isInt` | §2.2, **C6** |
| 006.0-regex-var | the count regex is held in a VARIABLE and applied with `[[ =~ ]]` | §6 |
| 006.0-no-shadow | no `var` shadows a TUtil or kklass member name | §1.2 reserved set |
| 006.0-one-source | the unit sources ONLY `../tutil/tutil.sh` — nothing is shared with ttail but the plan text | header, **C15** |

### Z. the gate (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.z-banner | the `head` on PATH is GNU coreutils | contract | **D4** |

### 1. `set -eu` — the instance and BOTH TPipe forms, every outcome (21)

Every child runs under `set -eu` with `timeout 20` and its own stdin, and
**every** sink call in a child is guarded `|| rc=$?`. Class `contract`, basis
**H12** + [../README.md](../README.md) §1 throughout.

| ID | Case | extra basis |
|---|---|---|
| 006.1-load | the unit loads under `set -eu` | §1.4 |
| 006.1-load-twice | the unit loads TWICE under `set -eu` (every re-source guard holds) | §1.4 |
| 006.1-each | `h.each`: an instance that delivers records | **H6** |
| 006.1-form2 | form 2: `TPipe.each CB -- "${argv[@]}"` with the argv THead built | **H11** |
| 006.1-form2-take | form 2 with `THead.take` as the producer command | **H11** |
| 006.1-form1 | form 1: a REAL pipe under `shopt -s lastpipe` | **H11** |
| 006.1-sinks | every `func` sink on an instance that delivers | **H6** |
| 006.1-tolist | `toList` into a kklass instance with an `.Add` | **H6** |
| 006.1-tool-error | a TOOL ERROR (a missing file, raw 1) — rc 1, the child survives | **H8** |
| 006.1-partial | PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT | **H8**, §2.5 (a) |
| 006.1-refused | a REFUSED build (`lines` + `bytes`) — rc 2, nothing runs, no abort | **H2** |
| 006.1-empty-cmd | an EMPTY `cmd` — rc 2 from every runner, no abort | **H2** |
| 006.1-bad-lines | a bad `lines` — rc 2, no abort | **H2** |
| 006.1-z-two | `zeroTerminated` with two paths — rc 2, no abort | **H2**, §2.3 |
| 006.1-take-nopath | `THead.take` with no path — rc 2, no abort, nothing printed | **H11**, §2.7 |
| 006.1-run-stream | `run` streams and the raw rc is readable afterwards | README §3 |
| 006.1-delete-clean | `delete` on an instance that never ran anything | §1.9 |
| 006.1-stdin | an instance reading STDIN (no path) under `set -eu` | §1.2 |
| 006.1-cmdsub | the `$( )` position: a `func` sink prints its value exactly ONCE | §1.1 |
| 006.1-d6 | **D6 final**: `subshellOk = 1` silences TPipe's subshell warning through THead (the child's stderr must be empty) | **D6** |
| 006.1-unguarded | **H12**: an UNGUARDED sink call with rc 1 aborts a `set -eu` caller — the documented caller rule | **C18** |

### 2. the debug switch — one line per rc 2 / tool-error path (18)

Exactly ONE `kk.debug` line on each rc 2 path and on each "head exited 1" path,
NOTHING on any rc 0 path, and complete silence from us when the switch is off
while head's own lines pass through. Class `contract`, basis
[../README.md](../README.md) §1.2 throughout.

| ID | Case | extra basis |
|---|---|---|
| 006.2-nc-each | rc 2: `lines` + `bytes` — one line, through `each` | **H2** |
| 006.2-nc-count | rc 2: `lines` + `bytes` — one line, through `count` | **H2** |
| 006.2-qv | rc 2: `quiet` + `verbose` — one line | **H2** |
| 006.2-z-two | rc 2: `zeroTerminated` with two paths — one line | **H2**, §2.3 |
| 006.2-z-verbose | rc 2: `zeroTerminated` + `verbose` — one line | **H2**, §2.3 |
| 006.2-bad-lines | rc 2: a bad `lines` — one line | **H2**, §2.2 |
| 006.2-empty-cmd | rc 2: an empty `cmd` — one line | **H2** |
| 006.2-take-nopath | rc 2: `THead.take` with no path — one line | **H11** |
| 006.2-take-badn | rc 2: `THead.take` with a bad count — one line | **H11** |
| 006.2-badout | rc 2: `toArray` with a bad out-name — one line (TUtil's own check) | §2.8 |
| 006.2-badout-th | rc 2: `toArray __th_x` — one line (the `__th_` prefix) | **H4b**, §2.8, **C8** |
| 006.2-raw1-partial | head raw 1 (a missing operand among good ones) — rc 1 and one line | **H8** |
| 006.2-raw1-alone | head raw 1 (the only operand missing) — rc 1 and one line | **H8** |
| 006.2-silent-run | rc 0: a successful `run` says NOTHING | §1.2 |
| 006.2-silent-each | rc 0: `each` on records says NOTHING | §1.2 |
| 006.2-silent-toarray | rc 0: `toArray` on records says NOTHING | §1.2 |
| 006.2-silent-take | rc 0: `THead.take` that succeeded says NOTHING | §1.2 |
| 006.2-wording | the "head exited" line names THead, and head's OWN line is left alone | §2.5 (b), **C10** |

*(10 + 1 + 21 + 18 = 50.)*

---

## 007_Bench.sh — the PLAN §5 P1 gate as assertions (P1) — 9 cases

The real gate is `../bench.sh`, run by hand on an idle box: **1.5×**, from the
medians of 21 interleaved runs. This file asserts the same shapes with a
**10× ceiling** because ktests runs test files threaded and the two sides of the
ratio do not inflate together. Corpus: 2000 lines built with
`kt_fixture_tmpdir_create`; no `trap … EXIT` of its own.

| ID | Case | Class | Basis |
|---|---|---|---|
| 007.z-banner | the `head` on PATH is GNU coreutils — otherwise every timed case is a loud SKIP | contract | **D4** |
| 007.a-gate-1 | `THead.take 1` costs at most 10× a bare `head -n 1`, medians of 7 INTERLEAVED runs, both sides delivering 1 record | perf | §5 P1, **C7** |
| 007.a-gate-half | `THead.take 1000` costs at most 10× a bare `head -n 1000`, same treatment, both sides delivering 1000 records | perf | §5 P1, **C7** |
| 007.a-delta | the take delta IS one instance: `new` + `argv` + `delete` under 50 ms/call (3.1–3.3 ms idle) | perf | §5 P1 |
| 007.b-nothing | 200 `buildArgv`/`argv` calls invoke the `cmd` ZERO times, leave `$BASHPID` unchanged, and build the 6 words in the pinned order | contract | **H1** |
| 007.b-constant | the build stays constant-cost: 201 rebuilds do not accumulate words | contract | **H1** |
| 007.c-count | `h.count` over 200 records costs at most 10× the `wc -l` equivalent, both answering 200 | perf | README §8 |
| 007.d-sinks | the five sinks: 2 records each, the callback and `.Add` both in THIS process | contract | §1.7 zero forks |
| 007.d-builders | the seven builder members, `run` and `THead.take` leave `$BASHPID` untouched — the only fork per call is head itself | contract | §1.7 zero forks |
