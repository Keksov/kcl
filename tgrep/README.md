# tgrep — `TGrep`, the GNU grep wrapper

> **Status: P2 landed.** `TGrep : TUtil` is complete — the typed option set, the
> pinned argv, the rc 2 list, the `mapRc` override, `paths`, the destructor and
> the static `search`. Suite: `tests/004_Argv.sh`, `tests/005_Search.sh`,
> `tests/006_Contract.sh` — **174 checks green on bash 5.2.37 and on bash
> 5.3.9**, threaded and under `--mode single`, against **GNU grep 3.0**. Still to
> come: the bench/doc closeout (P3). Design record and phase history:
> [../tutil/PLAN.md](../tutil/PLAN.md) /
> [../tutil/tutil_ledger.json](../tutil/tutil_ledger.json).

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
private `_nulDerived` bookkeeping var). A `nul = 1` that the **caller** set — for
`-z`, or for a shape this wrapper does not model — is never touched:

```bash
g.nullData = 1       # -z: NUL-terminated input AND output
g.nul      = 1       # the caller's own framing decision, kept
```

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

And one more that is specific to a body like `buildArgv`: an internal call to
another member is `kk.call_silent "$__inst__" NAME …`, never `$this.NAME` —
`$this.NAME` does not set the silent flag, so the callee's `kk._return` would
*print* whenever the outer member runs under `$( )`, `|` or `<( )`.

---

## 9. Tests

```bash
bash kcl/tgrep/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tgrep/tests/tests.sh
```

| File | Cases | What it pins |
|---|---|---|
| `004_Argv.sh` | 73 | **grep is never executed.** The lifecycle (all 23 declared vars present in `${inst}_data` with their defaults, `${g}_args` empty after `new g PAT PATH`, `${g}_paths` filled once, a reused instance name starting clean, `delete` removing `_paths`/`_args`/`_argv`, `argv` running nothing); G1 — every flag singly, in combination, the full pinned order with everything on, the boolean-is-exactly-`1` rule, `-e` always, `--` only with paths, `addArg` extras in their slot, `paths` replacing the list, rebuilds not accumulating, `argv` handing over a copy; G2 — the five refusals with rc 2 / `RESULT ''` / the caller's array untouched / one diagnostic line, and an emptied `${inst}_argv`; G3 — `maxCount` through `kk.isInt` (`abc`, `-1`, `'1 2'`, `0x10` refused; `0`, `08`→`-m 8`, `+5`→`-m 5` accepted without a write-back); G4 — a flag-shaped pattern is data, and the §4 derivation in both directions |
| `005_Search.sh` | 53 | The GNU banner gate first, then a fixture tree (names with a space, a newline and a leading `-`, UTF-8, CRLF, a NUL-bearing file, a subdir, and **real** NTFS symlinks through `kt_make_symlink`) with the bare tool as the oracle: G5 no match on all five runners; G6 the `-E` dialect and the literal `(` without it; G7 the `-Z` framing in both directions; G8 a directory operand without `recursive`, `search` implying `-r`, and `search` refusing zero paths or an empty pattern; G9 the three forms; G10 the partial-failure deviation; G11 a nested `search` from inside a callback, in both shapes; G12 `-r` versus a real directory symlink (and `-R` as the counter-oracle); the CRLF table of §5; every remaining typed option against bare grep; and the binary-file record with its two escape hatches |
| `006_Contract.sh` | 48 | `bash -n`, the open-quote and inline-`$'\r'` greps, no `$this.` call, `parent.constructor` in the constructor and `inherited` in the destructor, no `var` shadowing an inherited member; every shape from a child script under `set -eu` (an instance, both `TPipe` forms, `search` as a producer, a hit, no match, a grep error, a partial failure, a refused build, a refused `search`, the stdin form, `run` streaming, `delete`); and the debug switch — exactly one line on each of the 9 rc 2 paths and the 3 grep-error paths, **none** on any rc 0 or no-match path, with complete silence from us when the switch is off while grep's own lines pass through |
