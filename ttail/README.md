# ttail — `TTail`, the GNU `tail` wrapper

> **Status: COMPLETE (P0 + P1).** `TTail : TUtil` is the whole unit — the typed
> option set (`follow` included), the pinned argv, the rc 2 list, the `mapRc`
> override, the three overridden sinks, `paths`, the destructor, the static
> `take`, the bench and the docs. Suite: `tests/004_Argv.sh`, `tests/005_Run.sh`,
> `tests/006_Contract.sh`, `tests/007_Bench.sh` — **200 checks green on bash
> 5.2.37 and 200 on bash 5.3.9**, threaded and under `--mode single`, against
> **GNU coreutils 8.32**, with no follower of ours surviving a run. What the
> tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Design record:
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
| `TTail.take N PATH...` | static proc | — | `tail -n N -- PATH...`, streamed; §8 |

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

### The spelling the three overrides must use

With `follow = 0` the overrides do nothing but chain — and chaining has a trap
that was measured before it was a rule (critic finding C1): a `func` body that
merely **ends on** `inherited` returns **0** where the base returned 1, because
the compiled `kk._return` trailer replaces the rc. That would have silently
thrown away the partial-failure rc of §3 (a). So each override captures both
halves and re-raises them:

```bash
TTail.toArray() {
    if [[ "$follow" == 1 ]]; then
        kk.debug "Error: TTail.toArray: cannot finish with follow = 1 (tail -f never reaches EOF); use each with a stopping callback, first, or run"
        kk._return ""
        return 2
    fi
    local __tt_rc=0
    inherited toArray "$@" || __tt_rc=$?
    local __tt_n="$RESULT"
    kk._return "$__tt_n"
    return "$__tt_rc"
}
```

`tests/006_Contract.sh` §0 greps the three bodies for that shape, and
`tests/005_Run.sh` §H pins the behaviour it protects: with `follow = 0` and one
missing operand among good ones, all three answer **rc 1 with `RESULT` = the
real count** — which the naive spelling would have reported as rc 0.

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

## 9. Performance

`bash kcl/ttail/bench.sh [NL] [NR] [ND]` — a generated corpus of NL = 10 000
lines in a `mktemp -d` directory, NR = 21 **interleaved** runs per gated shape,
ND = 300 per-call measurements, timed with `TStopwatch.getTimeStamp`. Measured
**2026-09-16** on Windows 11 / MSYS2 with the machine idle, against **GNU
coreutils 8.32**:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` — the override | 679.2 µs/call | 661.9 µs/call |
| `argv NAME` (build + validate + copy, 6 words) | 1282.2 µs/call | 1385.8 µs/call |
| **`new` + `argv` + `delete`** — *the whole `take` delta* | **3202.1 µs/call** | **3333.2 µs/call** |
| **baseline** — bare `tail -n 1 -- FILE` (median of 21) | 35.03 ms | 35.08 ms |
| `TTail.take 1 FILE` (median of 21) | 39.13 ms — **1.11×** | 38.72 ms — **1.10×** |
| **baseline** — bare `tail -n 5000 -- FILE` (median of 21) | 33.72 ms | 32.56 ms |
| `TTail.take 5000 FILE` (median of 21) | 37.57 ms — **1.11×** | 38.10 ms — **1.17×** |
| **baseline** — `tail -n 5000 -- FILE \| wc -l` (median of 21) | 55.60 ms | 47.26 ms |
| `t.lines = 5000; t.count` — 5000 records into bash | 734.09 ms — **13.20×** | 738.49 ms — **15.62×** |
| per record read into bash | ~135 µs | ~138 µs |
| forks per call | **1** (tail itself) | **1** |

Reading the table:

- **The gate is the two `TTail.take` rows** ([PLAN.md](PLAN.md) §4 P1, the
  shared text is [`../thead/PLAN.md`](../thead/PLAN.md) §5 P1): at most **1.5×**
  a bare `tail -n N` on the same corpus. Both shapes pass on both bashes. The
  delta *is* the `new` + `argv` + `delete` row — one throw-away instance,
  measured on its own line — and it is a **per-call** cost, never a per-record
  one.
- **Corpus size is not the knob.** A whole `tail` run costs 32–36 ms here (one
  msys process start plus the scan); the wrapper's fixed delta is 3.2–3.4 ms.
  The ratio is therefore ~(34 + 3.3)/34 and can only *fall* as the corpus grows
  — which is why `-n 1` and `-n 5000` land within a few percent of each other.
- **Medians, not means.** Every timed number is one process start, and on this
  box a process start occasionally takes several hundred milliseconds for
  reasons outside this repo: the *means* printed beside these medians are
  routinely double them. A non-interleaved loop has been read as high as **2.4×**
  on code that interleaved medians put at 1.07–1.30×
  ([`../thead/PLAN.md`](../thead/PLAN.md) §8, finding 7) — which is why the gate
  is 1.5×, the two shapes are timed one-of-each per iteration, and the ratio is
  taken between medians.
- **`argv` runs nothing** and forks nothing — with `follow = 1` set, so the
  proof covers the `-f` build that three sinks refuse: the bench points `cmd` at
  a function that counts its own invocations and builds 900 times; the counter
  stays at 0 and `$BASHPID` never changes.
- **`follow` is not benched, and cannot be.** `tail -f` never ends on its own,
  so every shape it appears in is timed by the consumer's stopping rule or by an
  external kill, not by the wrapper (§6). The bench starts **no** follower, so it
  can leak none. For the record, measured at P0: the TPipe stop path ends
  `tail -f` in ~45 ms with raw rc 143 on both bashes; there is no inotify on
  msys, so an appended line reaches `each` after ~2 s (poll interval ~1 s).
- **`count` is not `wc -l`, and the 13–16× row is why.** The sink reads every
  record into bash at ~136 µs a record; `wc` counts in a second process at
  memory speed. That is the price of having the records *in this shell*. This row
  is **published, not gated**.
- **Reproduced.** A second run of the same file on the same idle box read
  **1.15× / 1.18×** on 5.2.37 and **1.13× / 1.10×** on 5.3.9 (the table's row is
  the first run). The spread between the two runs is the process-start variance
  described above, and it is the reason the gate has head-room at 1.5×.
- `tests/007_Bench.sh` asserts the same shapes with a ceiling of **10×**: under
  the threaded runner the two sides do not inflate together.

---

## 10. Tests

```bash
bash kcl/ttail/tests/tests.sh                 # the whole suite
bash kcl/ttail/tests/tests.sh --mode single   # sequential, for a stack trace
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/ttail/tests/tests.sh
```

**200 cases, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and under `--mode single`, against GNU coreutils 8.32. Case by case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| file | cases | what it pins | runs tail? |
|---|---|---|---|
| `004_Argv.sh` | 74 | the whole option set by **array comparison**, `-f` in its slot included: the lifecycle (every declared var with its default, `follow` among them, `${t}_args` empty after `new t N PATH`, `_paths` verbatim, a reused name starting clean, `delete` freeing all three arrays, `argv` running nothing); every option singly and combined in the pinned order; **T2** — `argv` with `follow = 1` STILL yields `-f`, because the refusal is a *sink* rule; the boolean rule; `--` only with paths; extras after the options, incl. `addArg --pid=PID`; the rc 2 list — 13 refusals, each asserting rc 2 + `RESULT ''` + the caller's array untouched + an EMPTY `${inst}_argv` + exactly one `kk.debug` line, plus two cases proving the legal shapes still build; **T1** — the count verbatim (`+2`, `08`, `-2`, `-0`, `+0`, `0`, 19 digits) with no write-back; the `-z` derivation's four states incl. `P3-F1`; the out-name refusals for all four family prefixes | **no** |
| `005_Run.sh` | 61 | behaviour against the bare tool: every sink (the three **overridden** ones included) and `run`; the unterminated last record; headers-as-records (**9** / **8** records, `first` = the header, `quiet`, `verbose`); the partial failure; CRLF in line and byte mode; `-z`; **T1** — the sign table where `+N` means *from line N* (`+2` on a 5-line file counts 4, the pin `kk.isInt` would have broken); **T4** — `take` in three positions incl. `+2`, with two paths, refused without a path, nested; and the **`follow` block**: the three refusals with a flag-file proof that nothing ran and `lastRc` still `-1`, `each` + a stopping callback (rc 0 / `lastRc` **143** / one record), `first`, `run` on a file that grows, the rc-1-with-a-real-`RESULT` behaviour of the three overrides with `follow = 0`, and a final case asserting **no follower of ours survived** | yes (GNU banner gate first) |
| `006_Contract.sh` | 55 | source integrity (`bash -n`, the open-quote and inline-`$'…'` greps, no `$this.`, `parent.constructor` in the constructor and `inherited` in the destructor, no `kk.isInt`, the regex in a variable, no shadowed member name, exactly one `source` line, and **the rc-preserving spelling of the three overrides**); every shape from a child under `set -eu` — both TPipe forms, `take` as a producer, records, a tool error, a partial failure, refused builds, **the follow refusal**, the stdin form, `run`, `delete` — with every sink call guarded; the debug switch (one line on each of the 14 rc 2 paths and the 2 tool-error paths, none on any rc 0 path); the **D6-final** `subshellOk` case; and `H12` | yes (gated) |
| `007_Bench.sh` | 10 | the §4 P1 gate as assertions with a **10×** ceiling behind the same banner gate: `TTail.take` against a bare `tail -n` in both shapes (interleaved, medians), `new` + `argv` + `delete` under 50 ms, `t.count` against the `wc -l` equivalent; that 200 `buildArgv`/`argv` calls with `follow = 1` invoke the `cmd` **zero** times and build the 7 words with `-f` in its slot; and zero forks for every member, for `take`, and for the three `follow = 1` refusals — which are bash-only and start no process, so this file creates no follower at all | yes (gated) |

Every follow case runs in a child under `timeout 20` and ends its own `tail`;
the background appender the growing-file case needs is started by the test, its
pid is recorded, and it is `kill -TERM`ed in the case's own teardown. No test
file installs a `trap … EXIT` of its own. The behavioural files open with a
**GNU banner gate**: without `tail (GNU coreutils) ` every case below it is a
loud `SKIP` and the case **count is unchanged**.
