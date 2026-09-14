# tgrep — `TGrep`, the GNU grep wrapper

> **Status: COMPLETE (P2 + P3).** `TGrep : TUtil` is the whole unit — the typed
> option set, the pinned argv, the rc 2 list, the `mapRc` override, `paths`, the
> destructor, the static `search`, the bench and the docs. Suite:
> `tests/004_Argv.sh`, `tests/005_Search.sh`, `tests/006_Contract.sh`,
> `tests/007_Bench.sh` — **184 checks green on bash 5.2.37 and 184 on bash
> 5.3.9**, threaded and under `--mode single`, against **GNU grep 3.0**.
> What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. The design record, the
> `TProcess` comparison and every measurement the family rests on:
> **[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)**. Phase history:
> [../tutil/PLAN.md](../tutil/PLAN.md) /
> [../tutil/tutil_ledger.json](../tutil/tutil_ledger.json).
>
> **`P3-F1`, found and fixed at P3:** the §4 `-0` derivation used to clear a
> `nul = 1` the **caller** set, if the same instance also went through a `-Z` +
> `-l/-L` build and back again. Found while writing these docs, fixed in the
> same phase with a one-line guard, and pinned by `tests/004_Argv.sh` §G — the
> sequence and the measurement are in §4 and in
> [../tutil/docs/TUtil.md §3.8](../tutil/docs/TUtil.md#38-27--the--0-derivation-and-the-shape-it-used-to-get-wrong).

`TGrep` is the first wrapper built on [`TUtil`](../tutil/README.md): typed
properties instead of a hand-built command string, one rc convention, and the
five `TPipe` sinks for free.

```bash
source kcl/tgrep/tgrep.sh

TGrep.search "needle" src/            # the one-liner: `grep -r`, streamed

TGrep.new g "needle" src/ doc/        # or an instance, when you want options
g.ignoreCase = 1
g.recursive  = 1
g.include    = '*.sh'
g.each r.onLine                       # one call per matching line, THIS shell
g.toArray hits                        # RESULT = ${#hits[@]}
g.count                               # RESULT = how many
g.lastRc                              # RESULT = grep's RAW exit status
g.delete
```

What it buys over spelling the command out: a pattern that starts with `-` is
**data** (it always travels as `-e PATTERN`), a path with a space or a newline is
one word by construction, grep's 0/1/2 collapses onto the kcl rc convention while
the raw status stays readable, and the platform notes (text mode and the CR,
`Binary file X matches`, `-r` versus a directory symlink) live here instead of in
every script that calls grep.

---

## 1. Surface

```bash
TGrep.new INST [PATTERN [PATH...]]
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `pattern` | var | `-e PATTERN` | always via `-e`, so a leading `-` is data. `''` → **rc 2** |
| `ignoreCase` | var | `-i` | |
| `invert` | var | `-v` | |
| `wordRegexp` | var | `-w` | |
| `lineRegexp` | var | `-x` | |
| `fixed` | var | `-F` | with `extended` → **rc 2** |
| `extended` | var | `-E` | with `fixed` → **rc 2** |
| `recursive` | var | `-r` | never `-R` — see §6 |
| `lineNumber` | var | `-n` | |
| `filesOnly` | var | `-l` | with `filesWithoutMatch` → **rc 2** |
| `filesWithoutMatch` | var | `-L` | with `filesOnly` → **rc 2** |
| `countOnly` | var | `-c` | |
| `onlyMatching` | var | `-o` | one record per **match**, not per line |
| `noFilename` | var | `-h` | with `withFilename` → **rc 2** |
| `withFilename` | var | `-H` | with `noFilename` → **rc 2** |
| `maxCount` | var | `-m N` | `kk.isInt` **and** `>= 0`; `''` = off |
| `include` | var | `--include=GLOB` | `''` = off |
| `exclude` | var | `--exclude=GLOB` | |
| `excludeDir` | var | `--exclude-dir=GLOB` | |
| `binary` | var | `-U` | read input in binary mode — §5 |
| `nullData` | var | `-z` | NUL-terminated **input** records |
| `nullOut` | var | `-Z` | NUL after the file name — §4 |
| `paths PATH...` | proc | — | **replaces** the operand list; no argument = the stdin form |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §3 |
| `TGrep.search PATTERN PATH...` | static proc | — | `grep -r`, streamed; §7 |

Inherited from [`TUtil`](../tutil/README.md) unchanged: `cmd` (`grep`), `crlf`,
`nul`, `_lastRc`, `addArg`, `clearArgs`, `argv NAME`, `run`, `lastRc`, and the
five sinks `each` / `toArray` / `toList` / `first` / `count`.

A `var` is read as `$(g.pattern)` and written as `g.pattern = value` — a plain
`var` read at a **call site** prints and leaves `RESULT` empty, so `$( )` is the
only correct spelling outside a member body.

A boolean is on for the exact string **`1`** and off for anything else — `2`,
`yes`, `true`, `01` and `' 1'` are all off, because a property is compared as a
string (`[[ "$x" == 1 ]]`) and never evaluated as arithmetic.

### The argv, pinned

```
grep [-i] [-v] [-w] [-x] [-F|-E] [-r] [-n] [-l|-L] [-c] [-o] [-h|-H]
     [-m N] [--include=G] [--exclude=G] [--exclude-dir=G] [-U] [-z] [-Z]
     -e PATTERN [EXTRA ARGS from addArg] [-- PATH...]
```

* the order is **this builder's**, not the order the caller assigned in;
* `-e PATTERN` is always present and always in that slot;
* `addArg` extras land **after** `-e PATTERN` and **before** `--`;
* `--` appears only when there is at least one path. With none, grep reads
  **stdin** — that is the documented stdin form, not a bug:

```bash
TGrep.new g needle                      # no path
printf 'one needle\ntwo\n' | g.run      # -> one needle
```

`g.argv NAME` builds the array and **runs nothing**, which is how the whole
option set is pinned in `tests/004_Argv.sh` without executing grep once.

No `-P` (PCRE is optional in a GNU build and absent from the house ERE line,
[tregex](../tregex/README.md)) and no `--color`, ever — the output is data.
Context (`-A/-B/-C`) is out of scope because it breaks the one-record-one-match
model of the sinks; `addArg` plus `run` is the way to it.

---

## 2. The rc 2 list — a malformed call, and nothing runs

`buildArgv` refuses, `${inst}_argv` is left **empty** so no stale command line
can be executed afterwards, `RESULT` is `''`, `lastRc` is left untouched (a fresh
instance still reads `-1`), and exactly **one** `kk.debug` line names the reason:

| Refusal | Why |
|---|---|
| `cmd` empty | the instance was disarmed by hand |
| `pattern` empty | `grep -e ''` matches every line — no caller means that |
| `fixed` + `extended` | `-F -E`: grep itself answers 2 |
| `filesOnly` + `filesWithoutMatch` | grep **accepts** `-l -L` with last-flag-wins semantics, so the answer would depend on this builder's fixed order rather than on anything the caller wrote |
| `noFilename` + `withFilename` | the same for `-h -H` |
| `maxCount` not an integer, or negative | grep 3.0 reads `-m -1` as *no limit*, silently |

`maxCount` goes through `kk.isInt` and the **normalised** value is what reaches
grep — `08` becomes `-m 8` — while the property keeps what the caller wrote:

```bash
g.maxCount = 08
g.argv W          # W = (grep -m 8 -e pat -- f)
$(g.maxCount)     # still '08' — the OUTVAR form of kk.isInt would have
                  # written through the property nameref and changed it
```

---

## 3. Return contract

| Situation | rc | `lastRc` | RESULT | stderr |
|---|---|---|---|---|
| a line was selected | 0 | 0 | the count / the record | — |
| **no** line was selected | **1** | 1 | the count (`0`) | **nothing** — no match is an *answer* |
| grep error (bad regex, unreadable or missing operand, a directory without `recursive`) | **1** | 2 | see below | one line under the switch |
| a refused build (§2) | **2** | untouched | `''` | one line under the switch |
| `cmd` names nothing `command -v` can find | **1** | 127 | — | one line under the switch |
| `first` with no record at all | **1** | whatever grep answered | `''` | nothing |

A diagnostic reaches stderr **only** under `VERBOSE_KKLASS=debug` (`kk.debug`).
**grep's own** `grep: …` lines are the tool's stderr and pass through untouched
in every case — they are not ours to suppress, and a caller who does not want
them writes `2>/dev/null` on the call.

### The named deviation: rc 1 with a real `RESULT`

grep answers **2 while still delivering matches** when one operand of several is
unreadable. `mapRc` still maps that to rc 1 — the call was not fully successful
— but the sinks **keep every record that arrived** and `RESULT` is the **real
count**. This is the one place in this family where rc 1 does not imply an empty
`RESULT` (the [`TPipe`](../tpipe/README.md) deviation, inherited through
[`TUtil`](../tutil/README.md) §3):

```bash
TGrep.new g needle good1.txt missing.txt good2.txt
g.toArray hits 2>/dev/null      # rc 1
echo "$RESULT"                  # 3 — and hits holds all three
g.lastRc                        # RESULT = 2 (grep's raw status)
```

Callers who want all-or-nothing test the rc first. Callers who want *whatever
could be read* use the records and ignore it.

### `Binary file X matches` is a record

grep prints it on **stdout**, so it arrives through every sink as an ordinary
record (a first-hour hit under `-r` over a source tree), and the rc is **0**:

```bash
TGrep.new g needle bin.dat
g.toArray a        # a = ('Binary file bin.dat matches')
g.addArg -a        # or --binary-files=text — the documented escape hatch
g.toArray a        # a = ('needle bin')
```

`-a` / `-I` are not modelled as properties yet.

### `$( )` loses the instance's state

`$(g.run)` captures the bytes, but the subshell is thrown away with every
mutation it made — the instance's `_lastRc` is **not** updated. Call the member
directly and read `lastRc` afterwards; this is the line every kcl instance unit
carries.

---

## 4. `-Z` and NUL framing — the derived `-0`

`-Z` is NUL **termination** only together with `-l` / `-L`. With `-c`, and with
normal output, it merely replaces the separator after the file name and the
record still ends in `\n` — measured on grep 3.0:

| flags | bytes | a record is framed by |
|---|---|---|
| `-l -Z` | `a.txt\0b.txt\0` | **NUL** |
| `-L -Z` | `c.txt\0` | **NUL** |
| `-c -Z` | `a.txt\0 2\n` | `\n` |
| `-Z` alone | `a.txt\0 line\n` | `\n` |

Handing the last two to the sinks' `-0` would mis-frame every record, so
`buildArgv` **derives** the sinks' framing instead of making it a second meaning
of `nullOut`:

> `nullOut == 1` **and** (`filesOnly == 1` **or** `filesWithoutMatch == 1`)
> → `nul = 1`

```bash
TGrep.new g needle src/
g.recursive = 1
g.filesOnly = 1
g.nullOut   = 1
g.toArray files      # names with a space — or a NEWLINE — arrive intact
```

The derivation is **idempotent**: turning `filesOnly` back off takes the `-0`
back off, because `buildArgv` remembers that it was the one who set it (the
private `_nulDerived` var). A `nul = 1` the **caller** set — for `-z`, or for a
shape this wrapper does not model — is never touched, in any order:

```bash
g.nullData = 1       # -z: NUL-terminated input AND output
g.nul      = 1       # the caller's own framing decision, kept
```

### `P3-F1` — three states, not two

The bookkeeping has to tell **derived** (ours, undo it) from **caller-set**
(never touch) from **off**, and the first version of it claimed ownership
whenever the derivation *condition* held — even when `nul` was already `1`
because the caller had set it. A later build that stopped deriving then took the
caller's own `nul` down with it:

```bash
TGrep.new g needle .
g.nul = 1                     # the caller's decision
g.nullOut = 1; g.filesOnly = 1
g.buildArgv                   # was: nul=1 _nulDerived=1  <- claimed, but it was already 1
g.filesOnly = 0
g.buildArgv                   # was: nul=0                <- the caller's 1 was gone
```

Found at P3 while writing these docs, measured identically on both bashes
([../tutil/docs/TUtil.md §3.8](../tutil/docs/TUtil.md#38-27--the--0-derivation-and-the-shape-it-used-to-get-wrong)),
and **fixed in the same phase** with one guard — claim ownership only when the
derivation really changes the value:

```bash
if [[ "$nul" != 1 ]]; then nul=1; _nulDerived=1; fi
```

The sequence now reads `nul=1 _nulDerived=0` throughout, and it is pinned by
`tests/004_Argv.sh` §G alongside the six ordinary shapes.

`buildArgv` mutates no other state.

---

## 5. CRLF — grep opens input in text mode

Measured on this platform, both bashes, on a `x\r\ny\r\n` file: **GNU grep, sed
and gawk strip the CR themselves**; `cat`, `head` and bash's `read` keep it; a
pattern containing a literal `\r` never matches.

| setting | the record for `needle\r\n` |
|---|---|
| default | `needle` — grep already stripped it |
| `binary = 1` (`-U`) | `needle\r` — byte fidelity restored |
| `binary = 1` + `crlf = 1` | `needle` — the sink's `-c` takes it back off |

So `crlf` is a **no-op for this wrapper** on its own; it exists for the
coreutils wrappers (`thead`/`ttail`) and for bash-function producers, and here it
is only useful **together with** `binary`.

---

## 6. `recursive` is `-r`, never `-R`

`-r` does **not** follow a directory symlink found during the walk; `-R` does.
That difference is the whole reason the property maps to `-r`: a symlinked
directory inside a tree is normally a second path to bytes already scanned, and
under `-R` a loop is a real risk. A symlink **named on the command line** is
followed either way:

```bash
TGrep.new g needle tree/       # tree/link -> tree/real is NOT descended
g.recursive = 1
g.toArray hits

TGrep.new g needle tree/link/  # named explicitly: followed
g.recursive = 1
g.toArray hits
```

An instance **never** implies `-r`. A directory operand without it is grep's
`Is a directory`: rc 1 here, `lastRc` 2, zero records, one diagnostic line.

---

## 7. `TGrep.search` — the one-liner

```bash
TGrep.search PATTERN PATH...        # = grep -r -e PATTERN -- PATH... , streamed
```

* **`-r` is implied by definition.** The flagship call names a directory, and
  GNU grep 3.0 without `-r` answers `Is a directory`, rc 2, zero records.
* **At least one path is required.** `grep -r` with none searches the *current
  directory*, which no caller means by accident: that is **rc 2** and nothing
  runs. A caller who wants stdin, or any option at all, builds an instance.
* the rc is `mapRc`'s (0 / 1 / 1-with-a-line), the stdout is grep's, and the
  throw-away instance is deleted before it returns.
* it is a **static proc**: it prints, it has no `RESULT`.

### The three forms

All three deliver the same records in the same order — `tests/005_Search.sh` §E
runs them side by side in a child script and compares:

```bash
shopt -s lastpipe                                   # once, top of a NON-interactive script
TGrep.search needle src/ | TPipe.each r.onLine      # 1. a real pipe

TPipe.each r.onLine -- TGrep.search needle src/     # 2. TPipe's safe `--` form

TGrep.new g needle src/                             # 3. an instance
g.recursive = 1
g.each r.onLine
```

Form 2 and form 3 read the records in **this** shell, so a callback that mutates
an object keeps every mutation. Form 1 needs `lastpipe`, or the right-hand side
runs in a subshell and the mutations are lost.

### Nested `search` is safe

The throw-away instance is named `__tg_s_${BASHPID}_${__TG_SEQ}` — a monotonic
counter per process, and `BASHPID` because a `$( )` or `<( )` producer is a
different process. A **fixed** name was deleted out from under an outer `search`
by a nested one (a `search` started from inside the callback of an outer sink),
and the outer instance simply vanished. So this is fine:

```bash
cb() { inner="$(TGrep.search "$1" other/)"; … }
TPipe.each cb -- TGrep.search needle src/
```

The cost is one instance construction per call (sub-millisecond) on a convenience
whose body is a fork anyway.

---

## 8. Writing your own wrapper

`TGrep` is the worked example for the [`TUtil`](../tutil/README.md) §5 recipe.
The three rules that matter, each of them a bug that was measured before it was a
rule:

* **`parent.constructor grep`, never `inherited`.** In a *constructor* the Pascal
  front-end rewrites `inherited` to `parent.constructor "$@"`, which forwards the
  descendant's own arguments — `TGrep.Create PATTERN PATH...` would have handed
  `TUtil` `cmd=PATTERN` with every path as an extra arg, and every path would
  then appear **twice** in the built argv. (In a *destructor* `inherited` is the
  ordinary parent call and is exactly right: `TGrep.Destroy` frees
  `${inst}_paths` and then chains.)
* **Assign every declared `var` in the constructor.** kklass binds a property as
  a nameref onto `${inst}_data[NAME]`; an unassigned one is an *unbound variable*
  under `set -u`, and `.new` over a still-live instance does not clear `_data`,
  so it can inherit the previous instance's value.
* **Never declare a `var` named like an inherited member.** `TUtil` owns
  `cmd crlf nul _lastRc buildArgv addArg clearArgs argv run each toArray toList
  first count lastRc mapRc` and kklass owns `property call parent delete`; the
  method wrapper is generated after the property wrapper and wins silently, so
  `obj.count = 5` would be accepted and discarded.

And three more that are specific to a body like `buildArgv`:

* an internal call to another member is `kk.call_silent "$__inst__" NAME …`,
  never `$this.NAME` — `$this.NAME` does not set the silent flag, so the callee's
  `kk._return` would *print* whenever the outer member runs under `$( )`, `|` or
  `<( )` ([../tutil/docs/TUtil.md §3.1](../tutil/docs/TUtil.md#31-c1--thisfunc-prints-under--));
* a boolean is `[[ "$x" == 1 ]]`, never `(( x ))`, and an integer option goes
  through `kk.isInt` with the normalised value read back from `$__KK_INT` and
  `>= 0` checked separately — `kk.isInt` accepts a negative and grep 3.0 reads
  `-m -1` as *no limit* in silence;
* `${inst}_argv` is rebuilt through a nameref (`local -n a=…; a=()`), never with
  `unset "${inst}_argv[…]"` in double quotes, and no member body may carry an
  inline `$'\r'` — `build` re-creates every body from `declare -f` through
  `eval` and a literal control character does not survive that round trip.

The full list, one repro per rule, is
[`TUtil` `README.md` §5](../tutil/README.md#5-writing-a-descendant). Two of them
bite **tests** rather than bodies and matter here: a test file installs no
`trap … EXIT` of its own (it would replace ktests'), and a raw CR is dropped from
a **word of an array compound assignment** on this platform —
`A=( $'cr\r' )` has length 2, so a CR-bearing expected value is built with
`printf -v CR '\r'; A=( "cr$CR" )` and copied with a plain `C=( "${A[@]}" )`,
never `declare -a C=( … )`. `tests/005_Search.sh` §I does exactly that for the
CRLF cases.

---

## 9. Performance

`bash kcl/tgrep/bench.sh [NL] [NR] [ND]` — a generated corpus of NL = 10 000
lines in `tree/big.txt` (every 100th carrying the needle) plus `tree/sub/small.txt`,
NR = 20 interleaved runs per shape, ND = 300 per-call measurements, timed with
`TStopwatch.getTimeStamp`. Measured **2026-09-11** on Windows 11 / MSYS2 with the
threaded test runner idle, against **GNU grep 3.0**:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` — the override, 22 typed options | 895.5 µs/call | 909.6 µs/call |
| `argv NAME` (build + validate + copy, 11 words) | 1508.2 µs/call | 1637.0 µs/call |
| **baseline** — bare `grep -r -e needle -- TREE` (median of 20) | 28.65 ms | 26.97 ms |
| `TGrep.search needle TREE` (median of 20) | 33.77 ms — **1.17×** | 33.30 ms — **1.23×** |
| `TGrep.new` + `.delete` — *the search delta* | 2547.8 µs/call | 2410.4 µs/call |
| **baseline** — bare `grep -c -r` (median of 20) | 27.91 ms | 26.81 ms |
| `g.count`, 101 records read into bash | 41.05 ms — **1.47×** | 40.41 ms — **1.50×** |
| `g.countOnly = 1; g.toArray` — 2 records | 30.70 ms — **1.09×** | 29.60 ms — **1.10×** |
| `g.count`, **dense** — 10 002 records | 1534.84 ms — **54.97×** | 1525.05 ms — **56.87×** |
| forks per call | **1** (grep itself) | **1** |

Reading the table:

- **The gate is the `TGrep.search` row** (PLAN §5 P3.1): at most **1.3×** a bare
  `grep -r` over the same tree. It passes on both bashes. The delta is one
  throw-away instance construction (~2.5 ms, measured on its own line) plus four
  kklass dispatches — a fixed few milliseconds against a process start and a
  scan, and it does not grow with the corpus.
- **Medians, not means.** Every number here is one process start plus a scan, and
  on this platform a process start occasionally takes 200 ms for reasons outside
  this repo. Timed in separate blocks, the search ratio read 1.07×, 1.23× and
  1.51× on three consecutive runs of the same code; interleaving the two shapes
  and taking medians pinned it at 1.20 ± 0.03×. `bench.sh` prints the mean next
  to each median — a gap between them *is* the box telling you it was not idle.
- **`argv` runs nothing** and forks nothing: section (a) of the bench points
  `cmd` at a function that counts its own invocations and builds 300 times — the
  counter stays at 0.
- **The `count` sink is not `grep -c`, and the dense row is why.** The sink reads
  every matching line into bash at ~150 µs a record; `grep -c` counts inside grep
  and prints one line per file. On a sparse pattern the difference is 13 ms; on a
  pattern that matches every line it is 55×. When the answer you want is the
  *number*, let grep compute it:

  ```bash
  g.countOnly = 1          # -c: one record per FILE, holding grep's own count
  g.toArray counts         # ('big.txt:10000' 'sub/small.txt:2')
  ```

- **Small corpora.** The 1.3× gate is calibrated for NL = 10 000. Shrink the
  corpus (`bench.sh 200`) and the wrapper's fixed few milliseconds become a
  visible fraction of the whole — that is not a regression, re-run at the default.
- `tests/007_Bench.sh` asserts the same shapes with a ceiling of **10×**: under
  the threaded runner the two sides do not inflate together (grep is its own
  process and roughly doubles; the wrapper's share is bash work in the contended
  shell and has been seen to grow tenfold), and a first threaded run measured
  4.18× where the next measured 1.16×.

---

## 10. Tests

```bash
bash kcl/tgrep/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tgrep/tests/tests.sh
```

**184 cases, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and under `--mode single`, against GNU grep 3.0. Case-by-case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md). The behavioural files all open
with the **GNU banner gate**: this box carries a non-GNU `grep` (Embarcadero)
that can win the PATH race, and D4 pins the *dialect*, so without the banner
every behavioural case is a loud SKIP and the case count is unchanged.

| File | Cases | What it pins |
|---|---|---|
| `004_Argv.sh` | 74 | **grep is never executed.** The lifecycle (all 23 declared vars present in `${inst}_data` with their defaults, `${g}_args` empty after `new g PAT PATH`, `${g}_paths` filled once, a reused instance name starting clean, `delete` removing `_paths`/`_args`/`_argv`, `argv` running nothing); G1 — every flag singly, in combination, the full pinned order with everything on, the boolean-is-exactly-`1` rule, `-e` always, `--` only with paths, `addArg` extras in their slot, `paths` replacing the list, rebuilds not accumulating, `argv` handing over a copy; G2 — the five refusals with rc 2 / `RESULT ''` / the caller's array untouched / one diagnostic line, and an emptied `${inst}_argv`; G3 — `maxCount` through `kk.isInt` (`abc`, `-1`, `'1 2'`, `0x10` refused; `0`, `08`→`-m 8`, `+5`→`-m 5` accepted without a write-back); G4 — a flag-shaped pattern is data, and the §4 derivation in both directions, including P3-F1 (a deriving build never CLAIMS a `nul` the caller already set) |
| `005_Search.sh` | 53 | The GNU banner gate first, then a fixture tree (names with a space, a newline and a leading `-`, UTF-8, CRLF, a NUL-bearing file, a subdir, and **real** NTFS symlinks through `kt_make_symlink`) with the bare tool as the oracle: G5 no match on all five runners; G6 the `-E` dialect and the literal `(` without it; G7 the `-Z` framing in both directions; G8 a directory operand without `recursive`, `search` implying `-r`, and `search` refusing zero paths or an empty pattern; G9 the three forms; G10 the partial-failure deviation; G11 a nested `search` from inside a callback, in both shapes; G12 `-r` versus a real directory symlink (and `-R` as the counter-oracle); the CRLF table of §5; every remaining typed option against bare grep; and the binary-file record with its two escape hatches |
| `006_Contract.sh` | 48 | `bash -n`, the open-quote and inline-`$'\r'` greps, no `$this.` call, `parent.constructor` in the constructor and `inherited` in the destructor, no `var` shadowing an inherited member; every shape from a child script under `set -eu` (an instance, both `TPipe` forms, `search` as a producer, a hit, no match, a grep error, a partial failure, a refused build, a refused `search`, the stdin form, `run` streaming, `delete`); and the debug switch — exactly one line on each of the 9 rc 2 paths and the 3 grep-error paths, **none** on any rc 0 or no-match path, with complete silence from us when the switch is off while grep's own lines pass through |
| `007_Bench.sh` | 9 | The PLAN §5 P3.1 gates as assertions, behind the same banner gate and with a 10× ceiling: `TGrep.search` against a bare `grep -r` over a 2000-line corpus (interleaved, medians, both sides asserted to find the same 21 hits), `TGrep.new` + `.delete` under 50 ms, `g.count` and the `countOnly` shortcut against `grep -c` (with grep's own per-file numbers compared as a set); that 200 `buildArgv` + `argv` calls invoke the `cmd` **zero** times, fork nothing and do not accumulate words; and zero forks for every member — the callback and `.Add` run in this process, and the seven builder members plus `run` and `search` leave `$BASHPID` untouched |
