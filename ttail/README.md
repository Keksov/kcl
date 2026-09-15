# ttail — `TTail`, the GNU `tail` wrapper

> **Status: P0 done (the unit, the three test files, this first cut).** P1 adds
> `bench.sh`, `tests/007_Bench.sh`, `TEST_COVERAGE_NOTES.md` and the kcl README
> row. Suite: `tests/004_Argv.sh`, `tests/005_Run.sh`, `tests/006_Contract.sh`,
> run against **GNU coreutils 8.32** on bash 5.2.37 and 5.3.9. Design record:
> [PLAN.md](PLAN.md) plus [`../thead/PLAN.md`](../thead/PLAN.md), which carries
> every shared decision (§8 there is the critic pass), and
> [ttail_ledger.json](ttail_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the sibling written from the same
> plan: [`../thead/README.md`](../thead/README.md).

`TTail` is a [`TUtil`](../tutil/README.md) descendant: typed properties instead
of a hand-built command string, one rc convention, and the five `TPipe` sinks
for free — plus `follow`, which is the one property in this family that changes
which sinks you may call.

```bash
source kcl/ttail/ttail.sh

TTail.take 20 build.log               # the one-liner: `tail -n 20`, streamed
TTail.take +2 data.csv                # skip the header row

TTail.new t 20 a.log b.log            # or an instance, when you want options
t.quiet = 1                           # no `==> NAME <==` headers
t.each r.onLine                       # one call per record, THIS shell
t.toArray last20                      # RESULT = ${#last20[@]}
t.lastRc                              # RESULT = tail's RAW exit status

t.follow = 1                          # -f: run / each / first only — §6
t.first                               # "wait for the next line"
t.delete
```

`TTail` is **not** a descendant of `THead`, and `ttail.sh` never sources
`thead.sh`: the two tools spell the same options with different meanings (`+N`
above all), so the common `buildArgv` shape is duplicated on purpose. The two
units share their plan text and nothing else.

---

## 1. Surface

```bash
TTail.new INST [N [PATH...]]          # N becomes `lines`
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `lines` | var | `-n N` | `''` = off → tail's own default of 10 lines. With `bytes` → **rc 2** |
| `bytes` | var | `-c N` | `''` = off. With `lines` → **rc 2** |
| `quiet` | var | `-q` | never print the file-name headers. With `verbose` → **rc 2** |
| `verbose` | var | `-v` | always print them. With `quiet` → **rc 2** |
| `zeroTerminated` | var | `-z` | NUL-delimited **input** records; derives the sinks' `-0` — §5. With ≥ 2 paths or with `verbose` → **rc 2** |
| `follow` | var | `-f` | follow the file forever — §6 decides which sinks may be called |
| `paths PATH...` | proc | — | **replaces** the operand list; no argument = the stdin form |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §3 |
| `toArray` / `toList` / `count` | func | — | **overridden**: rc 2 when `follow = 1` — §6 |
| `TTail.take N PATH...` | static proc | — | `tail -n N -- PATH...`, streamed; §7 |

Inherited from [`TUtil`](../tutil/README.md) unchanged: `cmd` (`tail`), `crlf`,
`nul`, `_lastRc`, **`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`,
`lastRc`, `each` and `first`.

A boolean is on for the exact string **`1`** and off for anything else — `2`,
`yes`, `true`, `01` and `' 1'` are all off.

### The argv, pinned

```
tail [-q|-v] [-z] [-f] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
```

* the order is **this builder's**, not the order the caller assigned in;
* `addArg` extras land **after** the options and **before** `--`, and tail is
  last-flag-wins, so `addArg -n`/`-c` silently **replaces** `lines`/`bytes` —
  the documented hatch for the suffix forms (`addArg -n 1K`);
* `--` appears only when there is at least one path; with none tail reads
  **stdin**;
* `t.argv V` with `follow = 1` still yields `-f`. The refusal of §6 is a **sink**
  rule, not an argv rule.

`t.argv NAME` builds the array and **runs nothing**, which is how the whole
option set is pinned in `tests/004_Argv.sh` without executing tail once.

---

## 2. The rc 2 list — a malformed call, and nothing runs

`buildArgv` answers **rc 2** with `RESULT=''`, one `kk.debug` line naming the
reason, and `${inst}_argv` left **empty**. `lastRc` still reads `-1` on a fresh
instance, because nothing was executed.

| refusal | why it is not left to tail |
|---|---|
| `cmd` is empty | the instance was disarmed by hand |
| `lines` **and** `bytes` | tail takes both and the **last one silently wins** |
| `quiet` **and** `verbose` | tail takes both, last flag wins — the answer would depend on this builder's fixed order |
| `zeroTerminated` with **≥ 2 paths** | the `==> NAME <==` headers stay `\n`-terminated under `-z`, so the derived `-0` would frame a header **and its whole file** into one record (§5) |
| `zeroTerminated` with `verbose` | same, for the header `-v` forces onto a single operand |
| a count failing `^[+-]?[0-9]+$` | `x`, `1K`, `'1 2'`, `--5`, `' 2'` — §4 |
| a count of more than 19 digits | the magnitude guard |

A fourth rc 2 lives in the **sinks**, not here: `toArray` / `count` / `toList`
with `follow = 1` — §6.

---

## 3. Return contract

`rc 0` = tail delivered everything it was asked for. `rc 1` = it did not. `rc 2`
= the **call** was malformed and nothing ran. The raw status stays readable
through `lastRc`.

tail has no "answer" rc: **every** failure is `1`. `mapRc` is therefore `0 → 0`
and anything else `→ 1` with one `kk.debug` line.

### Two named deviations

**(a) A partial failure keeps its records.** `tail -n 1 good missing` prints
`good`'s line and exits **1**; the sinks keep every record that arrived and
`RESULT` is the **real count**. This holds for the three overridden sinks too —
they capture the base's rc and re-raise it, which is exactly what a body that
merely ended on `inherited toArray "$@"` would have lost (see §6).

**(b) tail's own stderr passes through unconditionally.** `tail: cannot open
'missing' for reading: No such file or directory` is the **tool's** stream; it is
not gated by `VERBOSE_KKLASS` and its quoting follows the locale. Redirect it
where you do not want it, and match it by **prefix** in a test.

Under `$( )` every mutation is lost with the subshell, and an unguarded sink call
with rc 1 aborts a `set -e` caller — write `t.count || rc=$?`.

---

## 4. The count: one regex, a 19-digit guard, and **verbatim**

`lines` and `bytes` accept `^[+-]?[0-9]+$` with at most 19 digits, and the string
reaches tail **unchanged**. `kk.isInt` is deliberately **not** used, and for tail
the reason bites twice: it would turn `+2` into `2`, and those are opposite ends
of the file.

| value | `tail -n` / `-c` | `head -n` / `-c` ([thead](../thead/README.md)) |
|---|---|---|
| `N` | the last N | the first N |
| `+N` | **from the N-th** (`+2` skips line 1) | the first N |
| `-N` | the last N (same as `N`) | all but the last N |
| `0`, `-0` | nothing | `0` / `+0` nothing, `-0` everything |
| `+0` | **everything** | nothing |

```bash
TTail.new t '' five_lines.txt
t.lines = +2
t.count                               # RESULT = 4 — lines 2..5
# kk.isInt would have normalised it to `2` and this would read 2
```

`08` reaches tail as `08` and tail reads it as **decimal 8**; the property still
reads `08` afterwards, because nothing is written back onto the instance. A
20-digit count is rc 2 here; a 19-digit one is built and handed over, and
whatever tail then says is an ordinary rc 1.

Suffix multipliers (`-n 1K`) fail the regex; `addArg -n 1K` is the hatch.

---

## 5. `-z` and NUL framing — the derived `-0`

`zeroTerminated = 1` emits `-z`, which re-delimits the **input** by NUL and
NUL-terminates the output records, and `buildArgv` **derives** `nul = 1` so the
sinks read NUL-framed records. A **text** file under `-z` is one single record;
an unterminated last NUL record is delivered as it stands.

**Two or more paths (or `verbose = 1`) is rc 2**: the `==> NAME <==` headers stay
newline-terminated even under `-z`, so a derived `-0` would glue a header and its
entire file into one record.

`_nulDerived` keeps the derivation idempotent and keeps three states apart —
derived (ours, undo it when `zeroTerminated` goes back to 0), caller-set (`nul`
was already 1: never touched), and off. That guard is tgrep's `P3-F1`; the
four-state sequence is pinned in `tests/004_Argv.sh` §G.

---

## 6. `follow` — which sinks you may call

`tail -f` never ends on its own. `buildArgv` cannot refuse per sink (it does not
know its caller), so the split lives in **three overridden sinks**:

| member | with `follow = 1` |
|---|---|
| `run` | streams until the **caller** kills it (Ctrl-C, `timeout`, a kill from elsewhere) |
| `each` | streams until the callback calls `TPipe.stop`; the tpipe stop path (close → `kill -TERM` → wait) then ends tail with raw rc **143** → member **rc 0**, `lastRc` 143. **Blocks forever** with a callback that never stops — there is no timeout and no cancellation from outside |
| `first` | one record, then the same stop path — the "wait for the next line" idiom; blocks until a record arrives |
| `toArray`, `count`, `toList` | **rc 2 in the overriding member, nothing runs.** The first two can only finish at EOF, which never comes; `toList` could only finish if `.Add` called `TPipe.stop`, and no kcl list does (`TStringList` / `TList` / `THashSet.Add` never stop) |

```bash
TTail.new t 1 app.log
t.follow = 1

onLine() { printf '%s\n' "$1"; [[ "$1" == *ERROR* ]] && TPipe.stop; return 0; }
t.each onLine                         # rc 0 when the callback stops it
t.lastRc                              # RESULT = 143

declare -a a=()
rc=0; t.toArray a || rc=$?            # rc 2, RESULT '', `a` untouched, nothing ran
```

`addArg --pid=PID` is the **only** shape in which `-f` terminates on its own
(once PID dies). The refusal is not lifted by inspecting the extras — a caller
who needs that shape uses `run`:

```bash
( sleep 30 ) & helper=$!
t.addArg --pid=$helper
t.run > captured.log                  # ends ~1 s after the helper does
```

A caller who cannot guarantee a stop should use `run` under an external
`timeout`. Every test in this unit that starts a follower ends it — see the
header of `tests/005_Run.sh`.

---

## 7. Two things tail shares with head

### The `==> NAME <==` headers are **records**

With two or more operands and neither `-q` nor `-v`, tail writes
`\n==> NAME <==\n` before every operand after the first. Through the sinks those
are ordinary records, and the leading `\n` is an **empty record** only when the
previous file's last line was terminated: two terminated 3-line files under
`-n 5` are **9** records, the same pair with the first unterminated is **8**.
`quiet = 1` gives the 6 data lines; `verbose = 1` forces the header even for one
operand.

### tail keeps the CR

tail is a **byte** tool, so TUtil's `crlf` does real work here: `crlf = 1` strips
exactly one trailing CR per record, in byte mode too.

---

## 8. `TTail.take` — the one-liner

```bash
TTail.take N PATH...                  # tail -n N -- PATH..., streamed
```

A `static proc`: it prints tail's stdout untouched and answers with the mapped
rc. `N` is validated exactly as `lines` is (§4), so `+2` works and `1K` is rc 2.

**At least one path is required** — with none tail would read the **caller's**
stdin. Build an instance for the stdin form, or for any option at all, `follow`
included. Tool parity is kept: with two or more paths the headers are in the
stream.

```bash
TTail.take 20 build.log                        # straight to the terminal
TTail.take 20 build.log | TPipe.each cb        # a real pipe (needs lastpipe)
TPipe.each cb -- TTail.take 20 build.log       # the safe `--` form
```

The throw-away instance is named `__tt_t_${BASHPID}_${__TT_SEQ}`, so a `take`
started from inside the callback of an outer sink is safe.

---

## 9. Tests

```bash
bash kcl/ttail/tests/tests.sh                 # the whole suite
bash kcl/ttail/tests/tests.sh --mode single   # sequential, for a stack trace
```

| file | what it pins | runs tail? |
|---|---|---|
| `004_Argv.sh` | the whole option set by **array comparison**, `-f` in its slot included; the rc 2 list; the count verbatim (`+2`, `-0`, `08`); the `-z` derivation's four states; the out-name refusals for all four family prefixes | **no** |
| `005_Run.sh` | behaviour against the bare tool: every sink, the headers-as-records counts, the partial failure, CRLF, `-z`, the sign table, `TTail.take` — and `follow`: the three refusals with a flag-file proof that nothing ran, `each` + stop (rc 0 / `lastRc` 143), `first`, and `run` on a file that grows | yes (GNU banner gate first) |
| `006_Contract.sh` | source integrity (`bash -n`, no `$this.`, no `inherited` in the constructor, no `kk.isInt`, the rc-preserving spelling of the three overrides, one `source` line), `set -eu` through both TPipe forms, one `kk.debug` line per refusal, the D6 subshell warning | yes (gated) |

Every follow case runs in a child under `timeout 20` and ends its own `tail`;
the background appender the growing-file case needs is started by the test, its
pid is recorded, and it is `kill -TERM`ed in the case's own teardown. No test
file installs a `trap … EXIT` of its own.
