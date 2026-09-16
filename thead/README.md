# thead — `THead`, the GNU `head` wrapper

> **Status: COMPLETE (P0 + P1).** `THead : TUtil` is the whole unit — the typed
> option set, the pinned argv, the rc 2 list, the `mapRc` override, `paths`, the
> destructor, the static `take`, the bench and the docs. Suite:
> `tests/004_Argv.sh`, `tests/005_Run.sh`, `tests/006_Contract.sh`,
> `tests/007_Bench.sh` — **182 checks green on bash 5.2.37 and 182 on bash
> 5.3.9**, threaded and under `--mode single`, against **GNU coreutils 8.32**.
> What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Design record:
> [PLAN.md](PLAN.md) (§8 is the critic pass every decision below survived) and
> [thead_ledger.json](thead_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the worked sibling example:
> [`../tgrep/README.md`](../tgrep/README.md); the `tail` wrapper, written from
> the same plan: [`../ttail/README.md`](../ttail/README.md).
>
> **Two plan facts were corrected against the real tool at P0**, and both are
> now what the tests pin: two 3-line files under `-n 5` with the **first**
> unterminated are **8** records, not 7 (§6); and a 19-digit `-n` is rc **0**
> (it fits `uintmax`) — the shape that really overflows is a negative **byte**
> count (§4).

`THead` is a [`TUtil`](../tutil/README.md) descendant: typed properties instead
of a hand-built command string, one rc convention, and the five `TPipe` sinks
for free.

```bash
source kcl/thead/thead.sh

THead.take 20 build.log               # the one-liner: `head -n 20`, streamed

THead.new h 20 a.log b.log            # or an instance, when you want options
h.quiet = 1                           # no `==> NAME <==` headers
h.each r.onLine                       # one call per record, THIS shell
h.toArray first20                     # RESULT = ${#first20[@]}
h.count                               # RESULT = how many
h.lastRc                              # RESULT = head's RAW exit status
h.delete
```

What it buys over spelling the command out: a path with a space, a newline or a
leading `-` is one word by construction, the count is validated before the tool
sees it and then passed through **verbatim** (`+3` and `-0` mean what you wrote),
head's 0/1 collapses onto the kcl rc convention while the raw status stays
readable, and the platform notes (the CR that head keeps, the `==> NAME <==`
headers that arrive as records, `-z`) live here instead of in every script.

---

## 1. Surface

```bash
THead.new INST [N [PATH...]]          # N becomes `lines`
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `lines` | var | `-n N` | `''` = off → head's own default of 10 lines. With `bytes` → **rc 2** |
| `bytes` | var | `-c N` | `''` = off. With `lines` → **rc 2** |
| `quiet` | var | `-q` | never print the file-name headers. With `verbose` → **rc 2** |
| `verbose` | var | `-v` | always print them. With `quiet` → **rc 2** |
| `zeroTerminated` | var | `-z` | NUL-delimited **input** records; derives the sinks' `-0` — §5. With ≥ 2 paths or with `verbose` → **rc 2** |
| `paths PATH...` | proc | — | **replaces** the operand list; no argument = the stdin form |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §3 |
| `THead.take N PATH...` | static proc | — | `head -n N -- PATH...`, streamed; §7 |

Inherited from [`TUtil`](../tutil/README.md) unchanged: `cmd` (`head`), `crlf`,
`nul`, `_lastRc`, **`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`,
`lastRc`, and the five sinks `each` / `toArray` / `toList` / `first` / `count`.

`subshellOk` is the D6-final switch (default `0`): `h.subshellOk = 1` makes every
sink pass `-s` to `TPipe`, which silences the subshell warning `$(h.toArray a)`
otherwise prints. It is inherited, not redeclared.

A `var` is read as `$(h.lines)` and written as `h.lines = value` — a plain `var`
read at a **call site** prints and leaves `RESULT` empty, so `$( )` is the only
correct spelling outside a member body.

A boolean is on for the exact string **`1`** and off for anything else — `2`,
`yes`, `true`, `01` and `' 1'` are all off, because a property is compared as a
string (`[[ "$x" == 1 ]]`) and never evaluated as arithmetic.

### The argv, pinned

```
head [-q|-v] [-z] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
```

* the order is **this builder's**, not the order the caller assigned in;
* `addArg` extras land **after** the options and **before** `--`;
* `--` appears only when there is at least one path. With none, head reads
  **stdin** — the documented stdin form:

```bash
THead.new h 2                           # no path
printf 's1\ns2\ns3\n' | h.run           # -> s1 s2
```

* **extras are last, and head is last-flag-wins**, so an `addArg -n`/`-c`
  silently **replaces** `lines`/`bytes` — even switching between line mode and
  byte mode. That is the documented escape hatch for the shapes this wrapper
  does not model (`addArg -n 1K`, `addArg -c 2M`):

```bash
h.lines = 3
h.addArg -n 5                           # argv: head -n 3 -n 5 -- f  → head takes 5
```

`h.argv NAME` builds the array and **runs nothing**, which is how the whole
option set is pinned in `tests/004_Argv.sh` without executing head once.

---

## 2. The rc 2 list — a malformed call, and nothing runs

`buildArgv` answers **rc 2** with `RESULT=''`, one `kk.debug` line naming the
reason, and `${inst}_argv` left **empty** so no stale command line can run
afterwards. Every runner (`run`, `argv` and all five sinks) passes that 2
straight back, and `lastRc` still reads `-1` on a fresh instance because nothing
was executed.

| refusal | why it is not left to head |
|---|---|
| `cmd` is empty | the instance was disarmed by hand |
| `lines` **and** `bytes` | head takes both and the **last one silently wins** |
| `quiet` **and** `verbose` | head takes both, last flag wins — the answer would depend on this builder's fixed order, not on what the caller wrote |
| `zeroTerminated` with **≥ 2 paths** | the `==> NAME <==` headers stay `\n`-terminated under `-z`, so the derived `-0` would frame a header **and its whole file** into one record (§5) |
| `zeroTerminated` with `verbose` | same, for the header `-v` forces onto a single operand |
| a count failing `^[+-]?[0-9]+$` | `x`, `1K`, `'1 2'`, `--5`, `' 2'` — §4 |
| a count of more than 19 digits | the magnitude guard: it would reach head only to be refused as *Value too large* |

---

## 3. Return contract

`rc 0` = head delivered everything it was asked for. `rc 1` = it did not. `rc 2`
= the **call** was malformed and nothing ran. The raw status stays readable
through `lastRc`.

head has no "answer" rc the way grep's `1` (*no match*) is one: **every** failure
is `1` — a missing or unreadable file, a directory operand, a count the tool
refuses, an unknown option. `mapRc` is therefore `0 → 0` and anything else
`→ 1` with one `kk.debug` line.

### Two named deviations

**(a) A partial failure keeps its records.** `head -n 1 good missing` prints
`good`'s line and exits **1**. The sinks keep every record that arrived and
`RESULT` is the **real count** — this is the one place in this family where rc 1
does not imply an empty `RESULT`:

```bash
THead.new h 1 a.txt no_such.txt b.txt
rc=0; h.toArray recs || rc=$?         # rc 1, RESULT = ${#recs[@]} > 0
h.lastRc                              # RESULT = 1 (head's raw status)
```

**(b) head's own stderr passes through unconditionally.** `head: cannot open
'missing' for reading: No such file or directory` is the **tool's** stream, not
ours; it is not gated by `VERBOSE_KKLASS` and its quoting follows the locale
(`'…'` under `LC_ALL=C`, `‘…’` under the unit's `C.UTF-8` self-heal). Redirect it
where you do not want it (`h.count 2>/dev/null`), and match it by **prefix** in a
test. Exactly **one** line of ours accompanies it.

### `$( )` loses the instance's state

Under `$( )` every mutation is lost with the subshell: `$(h.run)` captures the
bytes but the instance's `_lastRc` is **not** updated — the line every kcl
instance unit carries.

### An unguarded sink call aborts a `set -e` caller

rc 1 is a normal answer here (a missing operand), so a `set -e` script must
write `h.count || rc=$?`. That is the caller rule, not a defect; it is pinned in
`tests/006_Contract.sh`.

---

## 4. The count: one regex, a 19-digit guard, and **verbatim**

`lines` and `bytes` accept `^[+-]?[0-9]+$` with at most 19 digits, and the string
reaches head **unchanged**. `kk.isInt` is deliberately **not** used: it
normalises, and head reads the normalised value as a different request.

| value | `head -n` / `-c` | `tail -n` / `-c` ([ttail](../ttail/README.md)) |
|---|---|---|
| `N` | the first N | the last N |
| `+N` | the first N (same as `N`) | **from the N-th** (`+2` skips line 1) |
| `-N` | **all but the last N** | the last N (same as `N`) |
| `0`, `+0` | nothing | `0` / `-0` nothing, `+0` everything |
| `-0` | **everything** ("all but the last 0") | nothing |

`kk.isInt` would hand head `0` for `-0` — *everything* becomes *nothing*. `08`
reaches head as `08` and head reads it as **decimal 8** (not octal); the property
still reads `08` afterwards, because nothing is written back onto the instance.

The 19-digit guard is a magnitude bound, not a type check: a 20-digit count is
**rc 2** here, while a 19-digit one is built and handed over. Whether head then
accepts it is head's business — `bytes = -9999999999999999999` comes back as an
ordinary **rc 1** with `head: invalid number of bytes: … Value too large`.

Suffix multipliers (`-n 1K`, `-c 2M`) are **not** modelled: they fail the regex.
`addArg -n 1K` is the hatch (see §1 — extras come last and replace the option).

---

## 5. `-z` and NUL framing — the derived `-0`

`zeroTerminated = 1` emits `-z`, which re-delimits the **input** by NUL and
NUL-terminates the output records. The sinks must then read NUL-framed records,
so `buildArgv` **derives** `nul = 1` instead of making the caller set two
properties that must agree:

```bash
THead.new h 2 records.nul
h.zeroTerminated = 1
h.toArray recs                        # -z in the argv, -0 to TPipe
```

A **text** file under `-z` is one single record for any `lines ≥ 1` — there is no
NUL in it, so the whole file is the first "line". An unterminated last NUL record
is delivered as it stands.

**Two or more paths (or `verbose = 1`) is rc 2**, because the `==> NAME <==`
headers and the `\n` that separates the operands stay **newline**-terminated even
under `-z`: a derived `-0` would glue a header and its entire file into one
record. Use one path, or `quiet = 1` and one run per file.

### Three states, not two

`_nulDerived` records that *we* set `nul`, which is what makes the derivation
idempotent:

* **derived** — `zeroTerminated` went to 1 while `nul` was 0: we set `nul = 1`
  and remember it; turning `zeroTerminated` back to 0 takes it off again;
* **caller-set** — `nul` was already 1 when the derivation ran: we never claim
  it, so a later build that stops deriving leaves the caller's `nul` alone;
* **off** — neither.

Claiming ownership whenever the *condition* held (rather than when we really set
the value) was `P3-F1` in tgrep; the same guard is here and the four-state
sequence is pinned in `tests/004_Argv.sh` §G.

---

## 6. Two things head does that grep does not

### The `==> NAME <==` headers are **records**

With two or more operands and neither `-q` nor `-v`, head writes
`\n==> NAME <==\n` before every operand **after the first**. Through the sinks
those are ordinary records: `count` counts them, `first` on two files returns
`==> FIRST <==`, and the leading `\n` is an **empty record** — but only when the
previous file's last line was terminated.

```bash
# a.txt and b.txt: three terminated lines each
THead.new h 5 a.txt b.txt
h.count                               # RESULT = 9
#   ==> a.txt <== | a1 | a2 | a3 | (empty) | ==> b.txt <== | b1 | b2 | b3
```

With the **first** file unterminated the separator's `\n` terminates that file's
last line instead of standing alone, and the same pair is **8** records. Tool
parity is the default (`quiet = 0`); lead with `quiet = 1` when you want data:

```bash
h.quiet = 1
h.count                               # RESULT = 6 — the six data lines
```

`verbose = 1` forces the header even for a single operand (2 records for
`lines = 1`).

### head keeps the CR

head is a **byte** tool — unlike grep, sed and gawk, which open input in text
mode on this platform and strip the CR themselves. So this is the wrapper where
TUtil's `crlf` finally does something:

```bash
THead.new h 2 crlf.txt                # the file is 'x\r\ny\r\n'
h.toArray recs                        # recs = ( $'x\r' $'y\r' )
h.crlf = 1
h.toArray recs                        # recs = ( x y ) — one CR per record
```

It works in byte mode too: `bytes = 5` on that file cuts the stream at `x\r\ny\r`
and `crlf = 1` still yields `x`, `y`.

---

## 7. `THead.take` — the one-liner

```bash
THead.take N PATH...                  # head -n N -- PATH..., streamed
```

A `static proc`: it prints head's stdout untouched, answers with the mapped rc,
and has no return channel. `N` is validated exactly as `lines` is (§4), so `+2`,
`-0` and `08` all work and `1K` is rc 2.

**At least one path is required.** With none, head would read the **caller's**
stdin, which no caller means by accident — that is rc 2 and nothing runs. Build
an instance for the stdin form, or for any option at all.

Tool parity is kept: with two or more paths the `==> NAME <==` headers are in the
stream.

### The three forms

```bash
THead.take 20 build.log                        # straight to the terminal
THead.take 20 build.log | TPipe.each cb        # a real pipe (needs lastpipe)
TPipe.each cb -- THead.take 20 build.log       # the safe `--` form
```

All three deliver byte-identical output to `head -n 20 -- build.log`.

### Nested `take` is safe

The throw-away instance is named `__th_t_${BASHPID}_${__TH_SEQ}`, so a `take`
started from inside the callback of an outer sink cannot delete the outer one's
instance out from under it. Cost: one construction per call.

---

## 8. Performance

`bash kcl/thead/bench.sh [NL] [NR] [ND]` — a generated corpus of NL = 10 000
lines in a `mktemp -d` directory, NR = 21 **interleaved** runs per gated shape,
ND = 300 per-call measurements, timed with `TStopwatch.getTimeStamp`. Measured
**2026-09-16** on Windows 11 / MSYS2 with the machine idle, against **GNU
coreutils 8.32**:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` — the override | 653.4 µs/call | 692.2 µs/call |
| `argv NAME` (build + validate + copy, 6 words) | 1196.3 µs/call | 1290.6 µs/call |
| **`new` + `argv` + `delete`** — *the whole `take` delta* | **3120.6 µs/call** | **3199.5 µs/call** |
| **baseline** — bare `head -n 1 -- FILE` (median of 21) | 34.14 ms | 35.88 ms |
| `THead.take 1 FILE` (median of 21) | 39.40 ms — **1.15×** | 43.19 ms — **1.20×** |
| **baseline** — bare `head -n 5000 -- FILE` (median of 21) | 36.02 ms | 33.23 ms |
| `THead.take 5000 FILE` (median of 21) | 39.97 ms — **1.10×** | 41.12 ms — **1.23×** |
| **baseline** — `head -n 5000 -- FILE \| wc -l` (median of 21) | 51.05 ms | 48.93 ms |
| `h.lines = 5000; h.count` — 5000 records into bash | 725.67 ms — **14.21×** | 731.64 ms — **14.95×** |
| per record read into bash | ~134 µs | ~136 µs |
| forks per call | **1** (head itself) | **1** |

Reading the table:

- **The gate is the two `THead.take` rows** ([PLAN.md](PLAN.md) §5 P1): at most
  **1.5×** a bare `head -n N` on the same corpus. Both shapes pass on both
  bashes. The delta *is* the `new` + `argv` + `delete` row — one throw-away
  instance, measured on its own line — and it is a **per-call** cost, never a
  per-record one.
- **Corpus size is not the knob.** A whole `head` run costs 33–36 ms here (one
  msys process start plus the scan); the wrapper's fixed delta is 3.1–3.3 ms.
  The ratio is therefore ~(34 + 3.2)/34 and can only *fall* as the corpus grows
  — which is why `-n 1` and `-n 5000` land within a few percent of each other.
  The plan's estimates (~42 ms and ~3.9 ms) were close enough that the
  conclusion is unchanged.
- **Medians, not means.** Every timed number is one process start, and on this
  box a process start occasionally takes several hundred milliseconds for
  reasons outside this repo: the *means* printed beside these medians are
  routinely double them. A non-interleaved loop over the two shapes has been
  read as high as **2.4×** on code that interleaved medians put at 1.07–1.30×
  ([PLAN.md](PLAN.md) §8, finding 7) — which is why the gate is 1.5×, the two
  shapes are timed one-of-each per iteration, and the ratio is taken between
  medians.
- **`argv` runs nothing** and forks nothing: section (a) of the bench points
  `cmd` at a function that counts its own invocations and builds 900 times — the
  counter stays at 0 and `$BASHPID` never changes.
- **`count` is not `wc -l`, and the 14× row is why.** The sink reads every
  record into bash at ~135 µs a record; `wc` counts in a second process at
  memory speed. That is the price of having the records *in this shell*, where a
  callback can mutate an object — when all you want is the number, spell it
  `head -n N FILE | wc -l` and skip the wrapper. This row is **published, not
  gated**.
- **Reproduced.** A second run of the same file on the same idle box read
  **1.06× / 1.11×** on 5.2.37 and **1.08× / 1.09×** on 5.3.9 (the table's row is
  the first run). The spread between the two runs — up to nine points on one
  shape — is the process-start variance described above, and it is the reason
  the gate has head-room at 1.5× instead of sitting at 1.3×.
- `tests/007_Bench.sh` asserts the same shapes with a ceiling of **10×**: under
  the threaded runner the two sides do not inflate together (head is its own
  process; the wrapper's share is bash work in the contended shell).

---

## 9. Tests

```bash
bash kcl/thead/tests/tests.sh                 # the whole suite
bash kcl/thead/tests/tests.sh --mode single   # sequential, for a stack trace
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/thead/tests/tests.sh
```

**182 cases, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and under `--mode single`, against GNU coreutils 8.32. Case by case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| file | cases | what it pins | runs head? |
|---|---|---|---|
| `004_Argv.sh` | 73 | the whole option set by **array comparison**: the lifecycle (every declared var in `${inst}_data` with its default, `${h}_args` empty after `new h N PATH`, `_paths` verbatim, a reused name starting clean, `delete` freeing all three arrays, `argv` running nothing); every option singly and combined in the pinned order; the boolean-is-exactly-`1` rule; `--` only with paths; extras after the options and before `--`, with `addArg -n 5` replacing `lines`; the rc 2 list — 13 refusals, each asserting rc 2 + `RESULT ''` + the caller's array untouched + an EMPTY `${inst}_argv` + exactly one `kk.debug` line, plus two cases proving the legal shapes still build; the count verbatim (`08`, `+3`, `-2`, `-0`, `+0`, `0`, 19 digits) with no write-back; the `-z` derivation's four states incl. `P3-F1`; and the out-name refusals for all four family prefixes (`H4b`) | **no** |
| `005_Run.sh` | 50 | behaviour against the bare tool on a 9-file fixture tree: every sink and `run`; the unterminated last record; headers-as-records (**9** records for two terminated 3-line files under `-n 5`, **8** with the first unterminated, `first` = the header, `quiet`, `verbose` on one file); the partial failure (records kept, `RESULT` = the real count, rc 1, one line of ours, head's own matched by prefix); a directory operand; CRLF in line and byte mode; `-z` incl. the unterminated NUL record and a text file as one record; the sign table behaviourally incl. the 19-digit `-c -N` the tool itself refuses; and `THead.take` in three positions, with two paths, refused without a path, nested inside an outer `each` | yes (GNU banner gate first) |
| `006_Contract.sh` | 50 | source integrity (`bash -n`, the open-quote and inline-`$'…'` greps, no `$this.` call, `parent.constructor` in the constructor and `inherited` in the destructor, no `kk.isInt`, the regex in a variable, no shadowed member name, exactly one `source` line); every shape from a child under `set -eu` — an instance, both TPipe forms, `take` as a producer, records, a tool error, a partial failure, four refused builds, a refused `take`, the stdin form, `run` streaming, `delete` — with every sink call guarded; the debug switch (exactly one line on each of the 11 rc 2 paths and the 2 tool-error paths, **none** on any rc 0 path); the **D6-final** `subshellOk` case; and `H12`, that an unguarded rc 1 aborts a `set -eu` caller | yes (gated) |
| `007_Bench.sh` | 9 | the §5 P1 gate as assertions with a **10×** ceiling behind the same banner gate: `THead.take` against a bare `head -n` in both shapes (interleaved, medians, both sides asserted to deliver the same records), `new` + `argv` + `delete` under 50 ms, `h.count` against the `wc -l` equivalent; that 200 `buildArgv`/`argv` calls invoke the `cmd` **zero** times, fork nothing and do not accumulate words; and zero forks for every member — the callback and `.Add` run in this process, and the seven builder members plus `run` and `take` leave `$BASHPID` untouched | yes (gated) |

The behavioural files open with a **GNU banner gate**: if `head --version` does
not begin with `head (GNU coreutils) `, every case below it is a loud `SKIP`
rather than a failure — D4 pins the dialect, not a binary, and the case **count
is unchanged**.
