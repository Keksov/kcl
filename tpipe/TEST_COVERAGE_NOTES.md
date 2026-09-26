# tpipe — test coverage notes

**Status: updated at P3 (D6 final, 2026-09-15); previously FINALIZED at P2
(2026-09-11).** Suite `001`–`005` = **190 cases**, green on bash 5.2.37 (primary)
and on bash 5.3.9 (secondary), in the default threaded mode and under
`--mode single`. The per-file counts below sum to 190 —
44 + 13 + 68 + 59 + 6 — and **every case in the suite has a row**. (The P2
edition of this page carried 165 with `004` written down as 41; the file was
already 47 cases then, because `004`'s `check_rc2` / `expect_clean` helpers each
raise a case of their own. The counts here are now the runner's.)

**Protocol.** `TPipe` has **no upstream**: it is a kcl addition (`PLAN.md` §1.2),
so there is no FPC seed procedure to cite and nothing to argue from a Pascal
source. The oracle is **bash itself** — every sink's answer is compared with what
a bare `while read` / `mapfile` / `head -n1` / `wc -l` over the *same* producer
gives — and the design rests on a list of measured bash facts, **F1–F16**
(`PLAN.md` §3), each of which is a test. The Basis column therefore cites one of:

* **F1–F16** — a pinned fact of `PLAN.md` §3. The measurement behind each one,
  as a runnable script with its output on both bashes, is
  [docs/TPipe.md](docs/TPipe.md).
* **D2 / D6 final (Q1–Q9)** — an owner decision (`PLAN.md` §2.0). **D1**, the old
  rc 2 refusal of the stdin form in a subshell, was **superseded** by D6 final on
  2026-09-15; the rows that cited it are now the warning rows of §G / §3.
* **C1–C23** — a finding of the 2026-09-10 critic pass (`PLAN.md` §8, same
  numbering).
* **P0-Fn / P1-Fn** — a finding made by the implementing worker in that phase
  (`tpipe_ledger.json` `execution_log`).
* **§n** — a plain section of `PLAN.md` or of `README.md` where the rule is
  stated and nothing else needed proving.

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract (`../README.md` §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `bash-convention` | a bash fact the design rests on — subshells, `exec {fd}`/`wait`, SIGPIPE, `IFS`, dynamic scoping, `declare -F`, the `declare -f`/`eval` round trip, `mapfile` target attributes |
| `representation` | records are **data**: exotic bytes, a CR, a NUL delimiter, 64 KiB, byte-exact round trip |
| `boundary` | an edge the happy path never reaches: an empty producer, an empty record, an unterminated tail, nesting, a stray `stop` |
| `cross-check` | the sink's answer against a bare-bash oracle over the same producer |

**Deliberate gaps** (each is a `wontfix` of `PLAN.md` §1.4, restated in
`README.md` §7, and none is testable as a behaviour of this unit):

* a record containing a **NUL byte** — no bash variable can hold one, so there is
  nothing to assert but the limit itself;
* **producer timeouts** — `TPipe.first -- sleep 30` blocking is the contract;
  `timeout(1)` in the argv is the answer, and testing `timeout` is not this
  unit's job;
* **stderr capture** — the producer's stderr passes through by design, so the
  silence assertions are scoped to *TPipe's own* output;
* **multi-stage `-- a -- b`** — `--` is a single boundary; the second one is just
  a producer argument;
* the **interactive** behaviour of `shopt -s lastpipe` (inert under job control)
  — the suite runs non-interactively, so only the message that names the caveat
  is pinned, not the caveat.

---

## 001_Each.sh — the engine and `TPipe.each` (P0, §G/§J rewritten at P3) — 44 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.harness-frame | — | the test file itself runs at `BASH_SUBSHELL` 0 | contract | the warning templates pin `BASH_SUBSHELL=1`, so this must hold for §G to mean anything |
| 001.rc-external-4 | each, lastRc | an external producer exiting 4 → `RESULT` 1, rc 1, `lastRc` 4 | contract | **F3** |
| 001.rc-function-6 | each, lastRc | a shell **function** producer exiting 6 → `lastRc` 6 | contract | **F3** — a function is as good a producer as an executable (this is what lets `-- TGrep.search …` work) |
| 001.rc-missing-127 | each, lastRc | a command that does not exist → 0 records, rc 1, `lastRc` 127 | contract | **F3**, §2.5 — no `type` pre-check; `wait` reports it |
| 001.rc-ok | each, lastRc | a successful producer → rc 0, `lastRc` 0 | contract | §2.4 |
| 001.tail-unterminated | each | `printf 'a\nb'` delivers **2** records | boundary | **F10** — the `\|\| [[ -n ]]` tail |
| 001.tail-empty | each | `printf 'a\n\n'` delivers 2 records, the second empty | boundary | **F10** |
| 001.empty-producer | each | an empty producer: `RESULT` 0, rc 0, the callback never called | boundary | §2.4 |
| 001.exotic | each | the exotic matrix round-trips byte-exact: `''`, `-e`, `-n`, `-neE`, a backslash, `$( )`, a backtick, `*`, `]`, a space, a tab, a CR, UTF-8, 4 KiB | representation | `IFS= read -r` — records are data (§2.2) |
| 001.oracle-read | each | the `each` answer equals a bare `while read` over the same producer | cross-check | §4 — bash is the oracle |
| 001.index-basic | each | `TPIPE_INDEX` is 1-based and counts this sink's records | contract | **F13** |
| 001.index-nested | each | a nested sink has its **own** `TPIPE_INDEX` and the outer one is restored | boundary | **F13**, C23 — a frame-local, not a second positional |
| 001.index-global | each | `TPIPE_INDEX` reads as `0` outside any sink under `set -u`, 1..n inside | contract | **P0-F2** — the load-time global, and the `__tpi_n` mirror that keeps a callback's assignment out of `RESULT` |
| 001.nested-result | each, lastRc | a nested sink leaves the **outer** `RESULT`/`lastRc` as the outer sink's own | boundary | §2.1 — the engine's state is frame-local |
| 001.cb-instance | each | an **instance** member callback keeps its state | contract | **F9** — the whole point of the unit |
| 001.cb-static | each | a **static** member is a legal callback | contract | **F9** |
| 001.cb-nested-frame | each | a sink called from **inside** another instance member keeps the *callback's* state | contract | **F9** — `this`/`__inst__` resolve to the callback's instance |
| 001.cb-rc-ignored | each | a predicate callback answering rc 1 does not stop the stream | contract | **D2** |
| 001.rc2-not-a-function | each | a callback name that is not a function → rc 2, and the producer is **not** started | contract | §2.4 (the `THashSet.onNotify` model, `thashset.sh:638`, not `ForEach` — C14) |
| 001.rc2-missing-operand | each | a missing callback operand → rc 2 | contract | §2.5 step 2 |
| 001.rc2-bad-flag | each | an unknown flag → rc 2, producer not started | contract | §2.5 step 1 |
| 001.rc2-flag-after-cb | each | a flag written **after** the callback → rc 2 | contract | §2.5 step 3, C15 |
| 001.rc2-word-after-cb | each | any other word after the callback → rc 2 | contract | §2.5 step 3, C15 |
| 001.rc2-empty-argv | each | `--` with an empty producer argv → rc 2, not "read stdin" | contract | §2.5 step 4 |
| 001.sub-delivers | each | `producer \| TPipe.each r.onLine` **delivers** both records and answers rc 0 — nothing is refused | contract | **F1**, **D6 final Q1** — proved with an instance callback that also appends to a FILE, the only side effect that survives a subshell |
| 001.sub-parent-untouched | each | …and the object in the **parent** is unchanged (`RL.N` still 0) — the reason the warning exists | bash-convention | **F1** |
| 001.sub-warn-verbatim | each | exactly ONE line, the **stdin template**, byte-exact, with the callback name as written and the operand label `CB` | contract | **D6 final Q2/Q3**, §2.4 |
| 001.sub-warn-switch-off | each | the same single line with `VERBOSE_KKLASS` **unset** and under `debug` — it is `kk.warn`, not `kk.debug` | contract | **D6 final Q6** |
| 001.sub-warn-flag-s | each | `-s` silences it and the records still arrive | contract | **D6 final Q3** |
| 001.sub-warn-quiet | each | `VERBOSE_KKLASS=quiet` silences it | contract | **D6 final Q6** |
| 001.sub-plain-silent | each | a **plain function** callback in the same pipe RHS delivers and says nothing | contract | **D6 final Q2** — a plain callback loses nothing a subshell can take |
| 001.sub-cmdsubst | each | the stdin form inside `$( )` — same template, delivered, and **nothing on stdout** | contract | **D6 final Q1/Q7**, **F2** |
| 001.stdin-ok | each | the stdin form **outside** any subshell works | contract | §1.3 |
| 001.stdin-lastrc | each, lastRc | after a stdin-form sink `lastRc` is `-1` | contract | C11 — there was no producer of ours |
| 001.lastpipe-delivers | each | under `shopt -s lastpipe` the pipe RHS runs in this shell and delivers | bash-convention | **F2** |
| 001.lastpipe-mutates | each | under `lastpipe` an **instance** callback keeps its mutations | bash-convention | **F2** |
| 001.lastpipe-pipestatus | each, lastRc | `PIPESTATUS[0]` is the producer's own rc; `lastRc` stays `-1` | bash-convention | **F2**, C11 |
| 001.form12-plain | each | README form 1 (pipe + `lastpipe`) and form 2 (`--`) agree, plain function | cross-check | README §2 |
| 001.form12-instance | each | the same two forms agree with `r.onLine` | cross-check | README §2 |
| 001.q7-cmdsubst | each | `x="$(TPipe.each fmt -- p3)"` is **exactly** what `fmt` wrote — no record count | contract | **D6 final Q7**, C17 |
| 001.q7-pipe | each | `TPipe.each fmt -- p3 \| cat` likewise | contract | **D6 final Q7** |
| 001.q7-direct | each | a DIRECT call still sets `RESULT` to the count and prints nothing | contract | **D6 final Q7**, §2.4 |
| 001.q7-rc2 | each | an rc 2 path leaves `RESULT=''` and prints nothing, direct or in `$( )` | contract | **D6 final Q7**, §1.2 |
| 001.cmd-plain-silent | each | the `--` form under `$( )` with a plain callback delivers, prints nothing, warns not at all | contract | **D6 final Q2**, C4 |

## 002_Stop.sh — `stop`, `lastRc`, the close-kill-wait path (P0) — 13 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 002.lastrc-initial | lastRc | `-1` before any sink has run (this section must stay first in the file) | contract | §2.4 — the "no producer of ours" sentinel |
| 002.f4-each-yes | each, stop, lastRc | a stop on the first record of `yes` → 1 record, rc 0, the producer dead, `lastRc` **141 or 143** | bash-convention | **F4** — the close/kill race; both answers correct (§2.3) |
| 002.f5-each-sigpipe | each, stop, lastRc | a producer that **ignores SIGPIPE and stops writing** (`trap '' PIPE; echo a; sleep 8`) is terminated in < 4 s (fastest of 5 calls) with `lastRc` 143 | bash-convention | **F5**, **C2** — without the `kill -TERM`, `wait` blocks 8.0 s (measured, docs §4) |
| 002.f4-first-yes | first, lastRc | `TPipe.first -- yes` returns `y` in < 4 s, fastest of 5 calls (loose for the threaded runner; the latency gate is 005/bench.sh — a 263 ms run under the 5.3.9 master sweep tripped the 250 ms ceiling, a best-of-5 of 1.34 s under a fork storm the 1 s one; 4 s is half of the 8 s failure mode), `lastRc` 141 or 143 | bash-convention | **F4**, re-pointed at `first` at P1 (`PLAN.md` §3) |
| 002.f5-first-sigpipe | first, lastRc | the same SIGPIPE-ignoring producer through `first`: < 4 s (fastest of 5 calls), `lastRc` 143 | bash-convention | **F5** |
| 002.f6-bang-clobber | each, lastRc | a callback that starts a background job (`( : ) & wait $!`) does not disturb the captured producer pid | bash-convention | **F6** |
| 002.f12-outer-first | each, stop | an outer stop requested **before** an inner sink survives it: outer 2, inner 4 | boundary | **F12**, **C3** — the frame-local slot; the global-flag draft lost this |
| 002.f12-inner | each, stop | a stop inside the **inner** callback stops only the inner sink: outer 4, inner 1 | boundary | **F12** |
| 002.f12-stray | each, stop | a stray `TPipe.stop` writes the process-wide slot and no sink reads it | boundary | **F12**, §2.3 |
| 002.stop-result | stop | `stop` leaves `RESULT` untouched and answers rc 0 | contract | C20 — the callback may be mid-computation |
| 002.stop-rc0 | each, stop | a stopped sink is **rc 0** and `RESULT` counts the records delivered | contract | §2.3 — the consumer's success, not the producer's failure |
| 002.stop-record-done | each, stop | the record that requested the stop is still fully processed | boundary | §2.2 — the loop breaks *after* the callback returns |
| 002.lastrc-stdin | each, lastRc | `lastRc` is `-1` again after a sink that read stdin (4 → stdin sink → -1) | contract | C11 |

The two child-process cases (`F4`/`F5`) run under `timeout 5` so that a
regression which hangs `wait` **fails the case** instead of hanging the suite,
and give the producer `2>/dev/null`: a closed pipe routinely makes it print
`write error: Broken pipe`, which is the producer's stderr, not TPipe's (C19).

## 003_Sinks.sh — the four collecting sinks and the flags (P1) — 68 cases

### A. `toArray` against a bare `mapfile` — 11 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.arr-fill | toArray | fills the caller's array; `RESULT` is the element count | contract | §2.4 |
| 003.arr-oracle | toArray | equals a bare `mapfile` over the same producer, on the exotic matrix | cross-check | **F8**, §4 |
| 003.arr-64k | toArray | a 64 KiB record survives byte-exact | representation | §4 exotic matrix |
| 003.arr-replaced | toArray | the target array is **replaced**, not appended to | contract | §2.4 — `mapfile` clears it first |
| 003.arr-empty | toArray | an empty producer empties the target: `RESULT` 0, rc 0 | boundary | §2.4 |
| 003.arr-tail | toArray | `printf 'a\nb'` → 2 elements on both bashes | boundary | **F8** |
| 003.arr-tail-empty | toArray | `printf 'a\n\n'` → 2 elements, the second empty | boundary | **F8** |
| 003.arr-scalar-target | toArray | an existing **scalar** target is converted into the output array | bash-convention | **F15** (the accepted side; docs §9) |
| 003.arr-unset-target | toArray | a declared-but-unset array and a brand-new name both work | bash-convention | **F15** |
| 003.arr-stdin | toArray | the stdin form works outside a subshell | contract | §1.3 |
| 003.arr-stdin-lastrc | toArray, lastRc | after a stdin-form `toArray`, `lastRc` is `-1` | contract | C11 |

### B. `toArray` target refusals, and rc 2 runs nothing — 10 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.bad-assoc | toArray | an **associative** target → rc 2, `RESULT=''`, **no stderr**, storage untouched | bash-convention | **F15**, **C8** — `mapfile` would print `not an indexed array` |
| 003.bad-ro-array | toArray | a **readonly array** target → rc 2, no stderr | bash-convention | **F15**, C8 |
| 003.bad-ro-scalar | toArray | a **readonly scalar** target → rc 2, no stderr | bash-convention | **F15**, C8 |
| 003.bad-int | toArray | an **integer-attributed** target → rc 2, no stderr, the variable intact | bash-convention | **P1-F2** — `mapfile` *succeeds* here and rewrites every record arithmetically (`abc` → `0`); not in the critic's list |
| 003.bad-name | toArray | a malformed or **reserved** output name → rc 2 | contract | §1.7 + **P1-F3** (`TPIPE_INDEX` as a third reserved prefix — every sink shadows it with a `local`) |
| 003.f14-arr | toArray | a rc 2 `toArray` never starts the producer and leaves stdin **fully readable** | contract | **F14**, §2.5 |
| 003.f14-others | toList, first, count | the same for the other three sinks (bad operand / bad flag) | contract | **F14** |
| 003.rc2-flag-after | toArray, toList | a flag written after the operand → rc 2 | contract | §2.5 step 3, C15 |
| 003.rc2-empty-argv | all four | `--` with an empty producer argv → rc 2 | contract | §2.5 step 4 |
| 003.rc2-missing-operand | toArray, toList | a missing operand → rc 2 (`first`/`count` take none) | contract | §2.5 step 2 |

### C. `toList` — records **offered** — 9 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.list-basic | toList | `INST.Add` runs once per record; `RESULT` is the number **offered** | contract | §2.4 |
| 003.list-oracle | toList | equals a bare `while read` oracle on the exotic matrix, byte-exact | cross-check | §4 |
| 003.list-tstringlist | toList | a real `TStringList` round-trips the exotic matrix byte-exact (64 KiB included) | representation | duck typing — the unit sources no list class |
| 003.list-rejecting | toList | a **rejecting** `.Add` (THashSet duplicates) neither aborts nor miscounts | contract | §2.4 — `.Add`'s rc is ignored with `\|\| :` |
| 003.list-rejecting-setu | toList | the same rejecting `.Add` under `set -eu` in a child does not tear the frame down | contract | **C10** |
| 003.list-stop-in-add | toList, stop | `TPipe.stop` from inside `.Add` stops the sink after that record, rc 0 | boundary | §2.3 |
| 003.list-no-add | toList | an instance with no `.Add` → rc 2, the producer never starts | contract | §2.4 |
| 003.list-dangling | toList | a dangling instance name → rc 2 | contract | §2.4 — duck-typed on `declare -F -- "$INST.Add"` |
| 003.list-stdin | toList | the stdin form works outside a subshell | contract | §1.3 |

### D. `first` — one record, then the stop path — 7 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.first-oracle | first | equals `head -n1`: `RESULT` is the first record, rc 0 | cross-check | §4 |
| 003.first-empty-producer | first | an empty producer → `RESULT=''`, **rc 1** | boundary | §2.4 — the one sink that does not deviate |
| 003.first-unterminated | first | a single **unterminated** record is delivered | boundary | **F10** |
| 003.first-empty-record | first | a single **empty terminated** record → `RESULT=''` with **rc 0** | boundary | §2.4 — "an empty record" vs "no record" |
| 003.first-ignores-rc | first | once a record is read the producer's rc is irrelevant (rc 0) | contract | §2.3 — *we* ended the stream |
| 003.first-exotic | first | an exotic record comes back byte-exact | representation | §4 |
| 003.first-stdin-partial | first | the stdin form reads exactly **one** record and leaves the rest for the caller | boundary | §1.3 — stdin is shared, not consumed whole |

### E. `count` — 5 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.count-oracle | count | equals `wc -l` over the same producer | cross-check | §4 |
| 003.count-exotic | count | counts the exotic matrix exactly (a read-loop oracle) | cross-check | §4 |
| 003.count-tail | count | includes an unterminated last record — where `wc -l` would miss it | boundary | **F10**; the divergence from the `wc` oracle is the point |
| 003.count-empty | count | an empty producer → 0 with rc 0 | boundary | §2.4 |
| 003.count-stdin | count | the stdin form works outside a subshell | contract | §1.3 |

### F. the `-0` and `-c` flags — 11 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.nul-find | toArray | `-0` over `find -print0` on names containing a space and a **newline**, against a bare `mapfile -d ''` oracle | representation | **F7** — the `-print` form over-counts a name with a newline, which is what `-print0` exists for |
| 003.nul-byte-exact | toArray | the NUL records carry the embedded newline byte-exact | representation | **F7** |
| 003.nul-all-sinks | count, first, toList | `-0` through the other three agrees with the `-0` `toArray` | cross-check | **F7** |
| 003.ifs-delimiter | toArray | `IFS=':'` around a `-0` call still yields the right records | bash-convention | **F11**, **C1** — the delimiter is passed as a VALUE; `${d:+-d ''}` silently becomes a space (docs §5) |
| 003.cr-arr | toArray | `-c` strips **exactly one** trailing CR, and none without the flag | representation | §1.3 |
| 003.cr-list-first | toList, first | the same through `toList` and `first` | representation | §1.3 |
| 003.cr-each | each | the same through `each` — the P0 member | representation | **P1-F1** — this is the case that was red when `-c` was a silent no-op |
| 003.cr-round-trip | (unit) | the `-c` pattern survived the kklass `declare -f`/`eval` round trip | bash-convention | **P1-F1** — `__TPIPE_CR`, never an inline `$'\r'` (docs §8) |
| 003.cr-count | count | `-c` does not change what `count` counts | boundary | §2.4 — accepted for symmetry, a no-op there |
| 003.cr-nul-combined | toArray | `-0` and `-c` combine: one CR stripped from each NUL record | representation | §1.3 |
| 003.flag-unknown | all four | an unknown flag → rc 2 for every sink, and starts nothing | contract | §2.5 step 1 |

### G. stdin pass-through — 2 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.f16-arr | toArray | `-- cat` reads the here-string given to the **sink** call | bash-convention | **F16**, **C9** — the process substitution inherits the caller's stdin |
| 003.f16-others | count, first, toList | the same for the other three | bash-convention | **F16** |

### H. the rc 1 + non-empty `RESULT` deviation — 4 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.dev-arr | toArray, lastRc | a failing producer: rc 1, the array **kept**, `lastRc` 6 | contract | the named deviation, **C5** |
| 003.dev-count | count | a failing producer: rc 1 with the count **kept** | contract | the named deviation |
| 003.dev-list | toList | a failing producer: rc 1 with the records already offered | contract | the named deviation |
| 003.dev-127 | all four | a missing producer command → rc 1 with `lastRc` 127, for every sink | contract | **F3**, §2.5 |

### I. nesting — 3 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.nest-in-each | each, toArray, count, first | a `toArray`/`count`/`first` nested inside an `each` callback works | boundary | §2.1 — the engine's locals are per frame |
| 003.nest-lastrc | each, lastRc | a nested sink leaves the outer `lastRc` as the **outer** producer's | boundary | §2.4 |
| 003.nest-in-add | toList, toArray | a `toArray` nested inside a `toList` `.Add` keeps both frames straight | boundary | §2.1 |

### J. the P0 stub is gone — 3 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.no-pending-fn | (unit) | `tpipe._pending` no longer exists as a function | contract | P1.1 — the stub helper is deleted |
| 003.no-pending-src | (unit) | the unit source contains no reference to the pending sentinel | contract | P1.1 |
| 003.valid-silent | all five sinks | under `VERBOSE_KKLASS=debug` a **valid** call to each of the five is silent | contract | §1.2 |

### K. zero forks per record — 3 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.fork-list | toList | `.Add` runs in **this** process for every record | contract | §1.8 — `$BASHPID` probe |
| 003.fork-arr | toArray | the only fork per call is the producer: 5 records, one producer pid | contract | §1.8 |
| 003.fork-count-first | count, first | the same single producer pid | contract | §1.8 |

## 004_Contract.sh — the kcl-wide contract (P1, §3/§4 rewritten at P3) — 59 cases

### 0. source integrity — 2 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.parses | (unit) | `bash -n` on the unit source | contract | the house rule after two mechanical sweeps corrupted sources while tests stayed green |
| 004.no-open-quote | (unit) | no single-quoted string left open at end of line | contract | the same rule |

### 1. X-SETU — every sink, both forms, under `set -eu` — 13 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.setu-load | (unit) | the unit loads under `set -eu` | contract | X-SETU |
| 004.setu-reload | (unit) | loading it **twice** is a no-op | contract | the re-source guard |
| 004.setu-dashdash | all five | the `--` form of all five sinks runs clean | contract | X-SETU |
| 004.setu-stdin | all five | the **stdin** form of all five sinks runs clean (`first` on empty stdin is rc 1, `lastRc` -1) | contract | X-SETU + C11 |
| 004.setu-herestring | toArray | the stdin form actually reading a here-string | contract | §1.3 |
| 004.setu-stop-each | each, stop, lastRc | the **stop path** on an infinite producer: member rc 0 while `wait` answered 141/143 | contract | **C10** — a bare `wait` would abort this child |
| 004.setu-stop-first | first, lastRc | the same through `first` | contract | C10 |
| 004.setu-stop-add | toList, stop | the same through a `.Add` that calls `TPipe.stop` | contract | C10 |
| 004.setu-predicate | each | **D2**: a callback that always answers rc 1 does not abort | contract | **D2** |
| 004.setu-rejecting-add | toList | a rejecting `.Add` (rc 1 per record) does not abort | contract | §2.4 — the `\|\| :` on `.Add` |
| 004.setu-rc2 | toArray, toList, first, count | a malformed call is rc 2 and does not abort when caught by an `if` | contract | §1.2 |
| 004.fail-producer-exit | count, each, toArray | a producer exiting **4** ends a `set -eu` child with the **member's** rc 1, not 4 | contract | **C10** — the exit status tells a guarded `wait` from an unguarded one exactly |
| 004.fail-producer-noe | count, lastRc | the same child **without** `set -e` keeps running: rc 1, `RESULT` 2, `lastRc` 4 | contract | the named deviation, C5 |

### 2. exactly one `kk.debug` line per rc 2 path — 20 cases

Each row asserts three things at once: rc 2, **exactly one** line on stderr with
`VERBOSE_KKLASS=debug`, and **complete silence** with the switch off. Class
`contract`, basis `../README.md` §1.2 + `PLAN.md` §2.5, for all twenty.

| ID | Member | Malformed call |
|---|---|---|
| 004.dbg-arr-badname | toArray | a malformed output name (`1bad`) |
| 004.dbg-arr-reserved | toArray | a reserved output name (`RESULT`) |
| 004.dbg-arr-assoc | toArray | an associative target (**F15**) |
| 004.dbg-arr-int | toArray | an integer-attributed target (**P1-F2**) |
| 004.dbg-arr-word | toArray | a word after the operand (C15) |
| 004.dbg-arr-flag | toArray | an unknown flag |
| 004.dbg-arr-noargv | toArray | `--` with no producer |
| 004.dbg-arr-nooperand | toArray | a missing operand |
| 004.dbg-list-noadd | toList | an instance with no `.Add` |
| 004.dbg-list-word | toList | a word after the operand |
| 004.dbg-list-flag | toList | an unknown flag |
| 004.dbg-list-noargv | toList | `--` with no producer |
| 004.dbg-list-nooperand | toList | a missing operand |
| 004.dbg-first-flag | first | an unknown flag |
| 004.dbg-first-word | first | a word where `--` belongs |
| 004.dbg-first-noargv | first | `--` with no producer |
| 004.dbg-count-flag | count | an unknown flag |
| 004.dbg-count-word | count | a word where `--` belongs |
| 004.dbg-count-noargv | count | `--` with no producer |
| 004.dbg-each-notfn | each | a callback that is not a function |

### 3. the D6-final subshell warnings — 12 cases

Both templates are **rebuilt from their parts inside the test file**, so the
assertions pin the text rather than comparing the unit with itself. The driver
runs each call inside `$( )` (`BASH_SUBSHELL` 1, exactly as a pipe RHS) with a
two-record here-string on stdin.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.d6-templates | each, toArray, toList | **both** templates, byte-exact, for all three warning sinks (6 sub-cases): the stdin form names `lastpipe` and the `--` form with the operand **label**; the `--` form says "move the call out of `$( )` / `( )`" | contract | **D6 final Q2**, §2.4 |
| 004.d6-answer-unchanged | toArray, toList | the records still arrive next to the warning: `RESULT` 2, rc 0 | contract | **D6 final Q1** — a warning changes neither rc nor `RESULT` |
| 004.d6-first-count-silent | first, count | **never** warn, in either form (4 sub-cases) | contract | **D6 final Q2** — `RESULT` is the answer and the caller reads it |
| 004.d6-callback-kind | each | a **plain function** and a **static member** callback are both silent, in either form (4 sub-cases) — a dotted static name has no `_data` | contract | **D6 final Q2**, §6 (`declare -p "${cb%%.*}_data"`) |
| 004.d6-flag-s | each, toArray, toList | `-s` silences all three in both forms (6 sub-cases) and leaves the rc alone | contract | **D6 final Q3** |
| 004.d6-flag-s-inert | first, count | `-s` is **accepted** by the operand-less sinks and is inert (no rc 2 for an unknown flag) | contract | §1.3 |
| 004.d6-var-prefix | toArray | `KK_SUBSHELL_OK=1 TPipe.toArray … ` as a **prefix assignment** silences it | contract | **D6 final Q3** — the variable is the primitive |
| 004.d6-var-block | each, toArray, toList | `local KK_SUBSHELL_OK=1` covers a whole frame and ends with it; the next call outside warns again | contract | **D6 final Q3/Q4**, the dynamic-scoping seam `__TPIPE_QUIET` uses |
| 004.d6-quiet | each, toArray | `VERBOSE_KKLASS=quiet` silences it corpus-wide, `RESULT` unchanged | contract | **D6 final Q6** |
| 004.d6-switch-off-and-on | toArray | the **same single line** with the debug switch off and with it on — a warning is not a debug line, and there is no second copy | contract | **D6 final Q6** |
| 004.d6-rc2-never-warns | toArray | an rc 2 path in a subshell prints its `Error:` line under `debug`, nothing without it, and **never** a `Warning:` | contract | **D6 final**, §2.5 step 5 — the decision is made after validation |
| 004.d6-subshell-zero | each, toArray, toList | at `BASH_SUBSHELL` 0 nothing warns at all, the stdin form included (6 calls) | contract | **F2** — the position the unit exists for |

### 4. Q7 — `each` never prints — 5 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.q7-cmdsubst | each | `x="$(TPipe.each fmt -- printf 'a\nb\n')"` is exactly `fmt`'s output | contract | **D6 final Q7**, C17 |
| 004.q7-pipe | each | `TPipe.each fmt -- cmd \| cat` likewise | contract | **D6 final Q7** |
| 004.q7-direct | each | a DIRECT call sets `RESULT` to the count and writes nothing to stdout | contract | **D6 final Q7**, §2.4 |
| 004.q7-rc2 | each | an rc 2 path leaves `RESULT=''` and prints nothing, direct or in `$( )` | contract | §1.2 |
| 004.q7-rc1-count | each, lastRc | rc 1 (producer exited 4) still answers with the count in `RESULT`, `lastRc` 4, nothing printed | contract | the named deviation, C5 |

### 5. silence on the success paths — 1 case

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.silent-rc01 | all seven | TPipe prints nothing on any rc 0 / rc 1 path, **with the debug switch on** | contract | §1.1/§1.2; the producer's own stderr is out of scope (C19), so stop-path producers get `2>/dev/null` |

### 6. `__TPIPE_QUIET` — the composing caller's opt-out — 6 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.quiet-on | count | with `local __TPIPE_QUIET=1` in the caller's frame the sink prints nothing and `RESULT` is still set | contract | **P1 finding** — `$(u.count)` read `22` without it |
| 004.quiet-default | count | without it the same sink prints its `RESULT` once (the default is unchanged) | contract | §1.1 |
| 004.quiet-callback-stdout | each | the opt-out silences `tpipe._ret` only — a callback's own stdout still flows | contract | README §7 |
| 004.quiet-add-stdout | toList | nor does it touch a `toList` target's `.Add` output | contract | README §7 — a `>/dev/null` on the delegated call would have |
| 004.quiet-direct | count | a DIRECT call is unaffected in either state (nothing is printed at `BASH_SUBSHELL` 0 anyway) | contract | §1.1 |
| 004.quiet-setu-global | (unit) | the load-time global is readable under `set -u` outside any sink | contract | §6 — the `set -u` floor for every `__TPIPE_*` name |

## 005_Bench.sh — the §2.6 performance gates (P2) — 6 cases

The ceilings here are **3× looser** than the `PLAN.md` §2.6 gates that `bench.sh`
measures and `README.md` §6 publishes, because ktests runs test files threaded
with 8 workers by default (**C7**): seven other files compete for the same cores
while these loops run. A 3×-loose ceiling still catches every regression the
gates exist for — a fork per record, a subshell per record, an accidental `$( )`
in the reader, a lost `kill -TERM` — each of which costs an order of magnitude,
not 20 %. N is 2000 here against `bench.sh`'s 10 000, so the file stays under a
few seconds; each ratio is taken against a baseline measured in the same process
milliseconds earlier, so a slow machine moves both numbers.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.gate-each | each | `each` + a no-op **function** costs at most **6×** a bare `while IFS= read -r` loop (PLAN gate 2×; measured 1.12×/1.13×), and delivers all N records | contract | §2.6, **C6** — the gate is the plain-function path; the instance-member cost is kklass's and is published, not gated |
| 005.gate-toarray | toArray | `toArray` costs at most **4.5×** a bare `mapfile` (PLAN gate 1.5×; measured 1.06×/1.04×), with the first and last elements equal to the oracle's | cross-check | §2.6 |
| 005.gate-first | first, lastRc | `TPipe.first -- yes` answers within **3× a bare baseline + 300 ms** — best of 7 interleaved pairs, the baseline being `first`'s own open → read → close → `kill -TERM` → `wait` written out (PLAN gate 250 ms absolute stays in bench.sh; idle ceiling ~380 ms, measured 26–37 ms); any call over 10 s fails; `RESULT='y'` and `lastRc` 141 or 143 on every call | contract | §2.6, **F4** — run in a child under `timeout 180` with a per-pair log, so a regression that hangs `wait` fails the case (naming the hung call) instead of the suite |
| 005.fork-each | each | the callback runs in **this** process for every record, and the sink frame is still ours afterwards | contract | §1.8 |
| 005.fork-tolist | toList | `.Add` runs in this process for every record | contract | §1.8 |
| 005.fork-rest | toArray, count, first | the only fork per call is the producer: 5 records carry one producer pid, different from ours; `count` and `first` see it too | contract | §1.8 |

---

## What is pinned where — the F-list index

| Fact | Where it is asserted |
|---|---|
| **F1** RHS of `\|` is a subshell; object state lost | 001.sub-delivers, 001.sub-parent-untouched, 001.sub-warn-verbatim |
| **F2** `BASH_SUBSHELL` 1 in the pipe RHS, 0 under `lastpipe`, also for a static member | 001.lastpipe-delivers, 001.lastpipe-mutates, 001.lastpipe-pipestatus, 001.sub-cmdsubst, 004.d6-subshell-zero |
| **F3** `exec {fd}< <(cmd); pid=$!; wait $pid` = the producer's rc | 001.rc-external-4, 001.rc-function-6, 001.rc-missing-127, 003.dev-127 |
| **F4** closing the fd kills an infinite producer; `wait` returns | 002.f4-each-yes, 002.f4-first-yes, 005.gate-first |
| **F5** a SIGPIPE-ignoring producer that stops writing is terminated | 002.f5-each-sigpipe, 002.f5-first-sigpipe |
| **F6** `$!` clobbered by a callback does not move the captured pid | 002.f6-bang-clobber |
| **F7** `-d ''` delivers NUL records | 003.nul-find, 003.nul-byte-exact, 003.nul-all-sinks |
| **F8** `mapfile -t -u fd` fills from the fd; unterminated tail delivered | 003.arr-oracle, 003.arr-tail, 003.arr-tail-empty |
| **F9** nested dispatch keeps the callback's state | 001.cb-instance, 001.cb-static, 001.cb-nested-frame |
| **F10** an unterminated last record and a final empty record are delivered | 001.tail-unterminated, 001.tail-empty, 003.first-unterminated, 003.count-tail |
| **F11** `read -r -d "$d"` is IFS-proof | 003.ifs-delimiter |
| **F12** the stop is frame-local | 002.f12-outer-first, 002.f12-inner, 002.f12-stray |
| **F13** `TPIPE_INDEX` is 1-based per sink call and nested-safe | 001.index-basic, 001.index-nested, 001.index-global |
| **F14** rc 2 paths run nothing and leave stdin intact | 003.f14-arr, 003.f14-others |
| **F15** an associative / readonly / integer target is refused with rc 2 and no stderr | 003.bad-assoc, 003.bad-ro-array, 003.bad-ro-scalar, 003.bad-int, 004.dbg-arr-assoc, 004.dbg-arr-int |
| **F16** the producer inherits the caller's stdin | 003.f16-arr, 003.f16-others |

## D6 final (2026-09-15) — where each of the nine answers is asserted

| Answer | Where |
|---|---|
| **Q1** nothing is refused because of a subshell | 001.sub-delivers, 001.sub-cmdsubst, 004.d6-answer-unchanged |
| **Q2** a warning only where the loss is certain (callback kind; `first`/`count` never) | 004.d6-templates, 004.d6-callback-kind, 004.d6-first-count-silent, 001.sub-plain-silent, 001.cmd-plain-silent, 002.sink-warn-kind *(tutil)* |
| **Q3** `-s` and `KK_SUBSHELL_OK=1`, per call and per block | 004.d6-flag-s, 004.d6-flag-s-inert, 004.d6-var-prefix, 004.d6-var-block, 001.sub-warn-flag-s |
| **Q4** the switch is kcl-wide (`KK_`) and survives a wrapper | 004.d6-var-block; tutil `002.sink-kkvar`, tgrep `006.subshellok` |
| **Q5** one line per call, no de-duplication | every `ERRN -eq 1` assertion of 004 §3 |
| **Q6** the line goes through `kk.warn`: printed with the debug switch off, silenced by `quiet` | 004.d6-switch-off-and-on, 004.d6-quiet, 001.sub-warn-switch-off, 001.sub-warn-quiet, and `kkore/tests/007_DebugAndOutName.sh` for the helper itself |
| **Q7** `each` never prints | 004 §4 (5 cases), 001 §J (5 cases) |
| **Q8** recipes, no unit change | `../README.md` §3 — nothing to assert in code |
| **Q9** `tutil` gets `var subshellOk` | tutil `001`/`002`/`003`, tgrep `004`/`006` |
