# thead — `THead`, the GNU `head` wrapper

> **Status: P0 done (the unit, the three test files, this first cut).** P1 adds
> `bench.sh`, `tests/007_Bench.sh`, `TEST_COVERAGE_NOTES.md` and the kcl README
> row. Suite: `tests/004_Argv.sh`, `tests/005_Run.sh`, `tests/006_Contract.sh`,
> run against **GNU coreutils 8.32** on bash 5.2.37 and 5.3.9. Design record:
> [PLAN.md](PLAN.md) (§8 is the critic pass every decision below survived) and
> [thead_ledger.json](thead_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the worked sibling example:
> [`../tgrep/README.md`](../tgrep/README.md); the `tail` wrapper, written from
> the same plan: [`../ttail/README.md`](../ttail/README.md).

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

## 8. Tests

```bash
bash kcl/thead/tests/tests.sh                 # the whole suite
bash kcl/thead/tests/tests.sh --mode single   # sequential, for a stack trace
```

| file | what it pins | runs head? |
|---|---|---|
| `004_Argv.sh` | the whole option set by **array comparison**: every option singly and combined, the pinned order, the boolean rule, `--` only with paths, extras in place, the rc 2 list, the count verbatim, the `-z` derivation's four states, and the out-name refusals for all four family prefixes | **no** |
| `005_Run.sh` | behaviour against the bare tool on a fixture tree: every sink, the headers-as-records counts, the partial failure, CRLF, `-z`, the sign table, and `THead.take` in three positions | yes (GNU banner gate first) |
| `006_Contract.sh` | source integrity (`bash -n`, no `$this.`, no `inherited` in the constructor, no `kk.isInt`), `set -eu` through both TPipe forms with every sink call guarded, one `kk.debug` line per refusal and silence on success, and the D6 subshell warning | yes (gated) |

The behavioural files open with a **GNU banner gate**: if `head --version` does
not begin with `head (GNU coreutils) `, every case below it is a loud `SKIP`
rather than a failure — D4 pins the dialect, not a binary.
