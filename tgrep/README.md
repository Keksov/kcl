# tgrep — `TGrep`, the GNU grep wrapper

> **Status: COMPLETE (P2 + P3).** `TGrep : TUtil` is the whole unit — the typed
> option set, the pinned argv, the rc 2 list, the `mapRc` override, `paths`, the
> destructor, the static `search`, the bench and the docs. Suite:
> `tests/004_Argv.sh`, `tests/005_Search.sh`, `tests/006_Contract.sh`,
> `tests/007_Bench.sh`, `tests/008_Helpers.sh` — **253 checks green on bash
> 5.3.15 (Git-bash) and 253 on bash 5.3.9 (MSYS2)**, threaded and under `--mode single`, against
> **GNU grep 3.0**. The H2 helpers (`quiet`, `TGrep.contains`,
> `TGrep.countMatching`) are in §1 and
> [§7a](#7a-helpers--contains-and-countmatching).
> What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](../docs/dev/tgrep/TEST_COVERAGE_NOTES.md)**. The design record, the
> `TProcess` comparison and every measurement the family rests on:
> **[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)**. Phase history:
> [../tutil/PLAN.md](../docs/dev/tutil/PLAN.md) /
> [../tutil/tutil_ledger.json](../docs/dev/tutil/tutil_ledger.json).
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
source /path/to/kbool/kbool.sh
kk.uses tgrep

TGrep.search "needle" src/            # the one-liner: `grep -r`, streamed
TGrep.contains "needle" src/ && echo y   # rc only: is the LITERAL text in there?
TGrep.countMatching "needle" src/     # RESULT = how many lines hold it

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
| `quiet` | var | `-q` | no output at all, **the rc is the answer**; legal with every other option (no rc 2) — see “The argv, pinned” |
| `paths PATH...` | proc | — | **replaces** the operand list; no argument = the stdin form |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §3 |
| `TGrep.search PATTERN PATH...` | static proc | — | `grep -r`, streamed; §7 |
| `TGrep.contains TEXT PATH...` | static proc | — | `grep -r -F -q`, **rc only**; §7a |
| `TGrep.countMatching TEXT PATH...` | static proc | — | `grep -r -h -F` + the `count` sink, **RESULT** = matching lines; §7a |

Inherited from [`TUtil`](../tutil/README.md): `cmd` — **the absolute path of
the GNU grep the kkore unit `ktool` resolved** (`/usr/bin/grep` on Git-bash,
`/usr/local/bin/ggrep` on FreeBSD; `KCL_GNU_GREP=/path` picks one, and `ktool`
refuses a wrong one), set by the constructor; `crlf`, `nul`, `_lastRc`,
**`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`, `lastRc`, and the
five sinks `each` / `toArray` / `toList` / `first` / `count`. A `cmd` you set by
hand afterwards is used as given (no identity check). The resolved instance is
frozen: a later `PATH` or `KCL_GNU_GREP` change reaches the next `.new`, not
this one.

**No GNU grep on the box?** `.new` still succeeds (rc 0, silent) with `cmd` `''`;
the first member that builds the argv (`run`, a sink, or `argv`) and the static
`TGrep.search` answer **rc 2** with one `kk.debug` line carrying ktool's reason,
which names the package (`no GNU grep: …; FreeBSD: pkg install gnugrep`,
`Alpine: apk add grep`). Nothing runs. Setting `cmd` re-arms the instance;
`_toolErr` keeps ktool's reason after the re-arm, so a later hand-set
`cmd = ''` prints that reason again.

**In `$( )`:** ktool's answer is cached per process, so a `.new` (or `search`)
inside `$( … )` in a shell that never resolved grep pays the cold probe on
**every** call. Call `ktool.gnu grep` (or create one instance) once in the main
shell before using TGrep inside `$( )`.

`subshellOk` is the D6-final switch (default `0`): `g.subshellOk = 1` makes every
sink pass `-s` to `TPipe`, which silences the subshell warning `$(g.toArray a)`
otherwise prints — see [tutil README §3](../tutil/README.md#subshellok--the-subshell-warning-and-how-to-say-you-meant-it)
and [tpipe README §3](../tpipe/README.md#3-a-sink-in-a-subshell--d6-final). It is
inherited, not redeclared: a descendant that declared a `var` of that name would
have it silently overridden by the method wrapper.

A `var` is read as `$(g.pattern)` and written as `g.pattern = value` — a plain
`var` read at a **call site** prints and leaves `RESULT` empty, so `$( )` is the
only correct spelling outside a member body.

A boolean is on for the exact string **`1`** and off for anything else — `2`,
`yes`, `true`, `01` and `' 1'` are all off, because a property is compared as a
string (`[[ "$x" == 1 ]]`) and never evaluated as arithmetic.

### The argv, pinned

```
grep [-i] [-v] [-w] [-x] [-F|-E] [-r] [-n] [-l|-L] [-c] [-o] [-h|-H]
     [-m N] [--include=G] [--exclude=G] [--exclude-dir=G] [-U] [-z] [-Z] [-q]
     -e PATTERN [EXTRA ARGS from addArg] [-- PATH...]
```

* the order is **this builder's**, not the order the caller assigned in;
* `-e PATTERN` is always present and always in that slot;
* `addArg` extras land **after** `-e PATTERN` and **before** `--`;
* `-q` (`quiet = 1`) is the last of the flags, just before `-e`. There is **no new
  rc 2 refusal** for it: `-q` together with `-l`, `-c`, `-o` and the rest is legal
  — grep simply prints nothing. With `quiet = 1` **every sink sees zero records**
  (`count` answers `0`, `toArray` leaves the array empty, `first` is rc 1) and the
  answer is the **rc**: 0 a line matched, 1 none did. GNU grep with `-q` exits 0
  **as soon as one match is found, even if another operand failed** — measured on
  grep 3.0, in both orders:

  | operands | grep `-q` rc | here |
  |---|---|---|
  | `plain.txt missing.txt` (a match, then a missing file) | 0 — it stops at the match and never reaches the second | rc 0, `lastRc` 0, no line |
  | `missing.txt plain.txt` (the missing file first) | 0 — grep prints its own complaint and still exits 0 | rc 0, `lastRc` 0, no line of ours |
  | `other.txt missing.txt` (no match anywhere) | 2 | rc 1, `lastRc` 2, one line |

  `quiet` is not a reserved name ([tutil §4](../tutil/README.md#4-reserved-member-names)),
  and `addArg` has no deny-list, so `addArg -q` was always possible; the property
  makes it typed.
* `--` appears only when there is at least one path. With none, grep reads
  **stdin** — that is the documented stdin form, not a bug:

```bash
TGrep.new g needle                      # no path
printf 'one needle\ntwo\n' | g.run      # -> one needle
```

`g.argv NAME` builds the array and **runs nothing**, which is how the whole
option set is pinned in `tests/004_Argv.sh` without executing grep once. In the diagrams `grep` stands for word 0, which is `cmd`: the resolved absolute path.

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
| `cmd` empty | the instance was disarmed by hand, or no GNU grep was found at `.new` (the line is then ktool's reason, with the package hint) |
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

grep 3.5 and later write `grep: FILE: binary file matches` to stderr instead: no record, rc 0.

`-a` / `-I` are not modelled as properties yet.
[`TGrep.countMatching`](#7a-helpers--contains-and-countmatching) keeps the record:
**a matching binary file adds ONE** to its number (no `-I`, no `-a`).

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

Besides `nul`/`_nulDerived`, `buildArgv` writes only TUtil's private
`_textMode` (the CR contract, §5).

---

## 5. CRLF — grep opens input in text mode

**The CR contract is TUtil's** — the tables, the delivery paths and the
residuals are in [tutil `README.md` §3 "CRLF: one result on every
platform"](../tutil/README.md#crlf-one-result-on-every-platform) (owner DL11).
For this wrapper: text mode means `binary = 0` **and** `nullData = 0`, and in
text mode a line record never carries the line-end CR, on every platform —
cygwin/msys grep strips it itself. grep has no input-side switch, so on
Linux/BSD/macOS:

* with **no path operand and no `recursive`** grep reads stdin, and the argv
  starts with `tutil._crStdin`: stdin goes through `sed [-u] 's/<CR>$//'`
  first, so `$`, `-x` and `^$` match exactly as on Windows (grep's rc is still
  grep's);
* with **file operands** the OUTPUT is cleaned (`_textMode = 1`: the sinks'
  `-c`, `run`'s `sed [-u]` filter) — grep's matching still sees the CR there,
  so `needle$`, `-x`, `-Fx` and `^$` do not match a CRLF line (the residual;
  use `binary = 1` and `\r?$`, or feed stdin);
* `filesOnly`/`filesWithoutMatch` (`-l`/`-L`) print names, not lines, and are
  never touched.

| setting | the record for `needle\r\n` |
|---|---|
| default | `needle` — on every platform |
| `binary = 1` (`-U`) | `needle\r` — byte fidelity restored, everywhere |
| `binary = 1` + `crlf = 1` | `needle` — the sink's `-c` takes it back off |
| `nullData = 1` (`-z`) | not text mode: grep `-z` keeps the CR on Windows too, so nothing is stripped anywhere |

So `crlf` is a **no-op for this wrapper** in text mode; it exists for the
coreutils wrappers (`thead`/`ttail`) and for bash-function producers, and here it
is only useful **together with** `binary`. On Windows grep never sees the
line-end CR (a pattern containing a literal `\r` never matches); off Windows
the same holds for stdin, while file operands keep the residual above.

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

## 7a. Helpers — `contains` and `countMatching`

Two more **static procs** for the questions asked most often. Like `search`, each
builds a throw-away instance (`__tg_s_${BASHPID}_${__TG_SEQ}`, deleted before it
returns, safe to nest) and takes **literal text** — `fixed = 1`, `recursive = 1`,
at least one path. Fewer than two arguments is **rc 2**, one `kk.debug` usage
line, nothing runs, stdin untouched; an empty TEXT is `buildArgv`'s rc 2.

```bash
TGrep.contains TEXT PATH...         # rc only: -r -F -q -e TEXT -- PATH...
TGrep.countMatching TEXT PATH...    # RESULT = the matching lines: -r -h -F -e TEXT -- PATH...
```

| `TGrep.contains` | rc |
|---|---|
| a line matched (grep stops at the first) | **0** — even when another operand failed (`-q`, above) |
| nothing matched | **1**, silent |
| a tool error (missing or unreadable operand, nothing matched) | **1** plus the one `mapRc` line — never rc 2 |
| fewer than two arguments, or an empty TEXT | **2**, nothing ran |

It **prints nothing**, direct or under `$( )`. Who must tell “not found” from
“grep failed” builds an instance and reads `lastRc` (1 / 2).

`countMatching` goes through the existing `count` sink — no parsing of
`file:count`, no `-c`, the `-h` keeps every record a bare line — so its answer is
what `count` answers, deviation included (§3): `0` matches is RESULT `0` with
rc 1, and a failed operand among good ones is the **real count** with rc 1. RESULT
is delivered the way `TSed.quoteRe` does: a direct call prints nothing, `$( )`
prints the value exactly once.

```bash
TGrep.contains 'a.b' src/ && echo "the text a.b is in there"   # a.b, not aXb
n=$(TGrep.countMatching TODO src/)                              # lines, over the tree
TGrep.countMatching TODO src/; echo "$RESULT"                   # the same, no subshell
```

* **The text is data** (`-F`): `.`, `*`, `[`, `$` and a leading `-` are plain
  characters. For a regex use an instance (`pattern`, `extended`).
* **CRLF**: text mode, as everywhere — the line end never takes part in a count.
* **A matching binary file counts as ONE record** — grep's `Binary file X matches`
  line (§3 “is a record”) is kept (no `-I`, no `-a`), so `countMatching` over a
  tree with one binary hit adds 1 however many lines inside it match. `contains`
  is unaffected: the match alone is the answer.
* Cost: one instance build + one fork (grep itself), like `search`; no new budget.

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
  `cmd crlf nul _lastRc subshellOk _toolErr buildArgv addArg clearArgs argv run each
  toArray toList first count lastRc mapRc` and kklass owns `property call parent delete`; the
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

**253 cases, green on bash 5.3.15 (Git-bash) and on bash 5.3.9 (MSYS2)** (launch L2.7-C; the move onto ktool, launch L3.4, adds 5 cases to `004` and 1 to `006`; the H2 helpers, launch L6.0, add 2 to `004` and the 48 of `008`), in the default threaded
mode and under `--mode single`, against GNU grep 3.0. Case-by-case:
[TEST_COVERAGE_NOTES.md](../docs/dev/tgrep/TEST_COVERAGE_NOTES.md). The behavioural files all open
with the **ktool gate**: one case asks the kkore unit ktool (through
`kt_gnu_gate grep GREP_BIN`, `tutil/tests/gnu_helper.sh`) for a GNU grep — ktool
skips a non-GNU `grep` earlier on PATH — and `GREP_BIN` is the very grep TGrep
resolves, so every oracle runs it. D4 pins the *dialect*, so with none every
behavioural case is a loud `SKIP: <ktool's reason>` (with the package hint) and
the case count is unchanged. `004` never runs grep: it selects a stub GNU grep
with `kt_gnu_stub` (`KCL_GNU_GREP`), so it runs in full on a box without one and
its argv pins hold the stub's path as word 0 (`tutil._crStdin`, then the stub, in
the stdin form).

| File | Cases | What it pins |
|---|---|---|
| `004_Argv.sh` | 86 | **grep is never executed** (a stub GNU grep; word 0 is its path). The lifecycle (all 23 declared vars plus TUtil's seven — `cmd`, `crlf`, `nul`, `_lastRc`, `subshellOk`, `_textMode`, `_toolErr` — present in `${inst}_data` with their defaults, `${g}_args` empty after `new g PAT PATH`, `${g}_paths` filled once, a reused instance name starting clean, `delete` removing `_paths`/`_args`/`_argv`, `argv` running nothing); G1 — every flag singly, in combination, the full pinned order with everything on, the boolean-is-exactly-`1` rule, `-e` always, `--` only with paths, `addArg` extras in their slot, `paths` replacing the list, rebuilds not accumulating, `argv` handing over a copy; G2 — the five refusals with rc 2 / `RESULT ''` / the caller's array untouched / one diagnostic line, and an emptied `${inst}_argv`; G3 — `maxCount` through `kk.isInt` (`abc`, `-1`, `'1 2'`, `0x10` refused; `0`, `08`→`-m 8`, `+5`→`-m 5` accepted without a write-back); G4 — a flag-shaped pattern is data, and the §4 derivation in both directions, including P3-F1 (a deriving build never CLAIMS a `nul` the caller already set); T6 — no GNU grep found (`KCL_GNU_GREP=/nonexistent`: `.new` rc 0 and silent, `argv`, `search`, `contains`, `countMatching`, a sink and the stdin form rc 2 with ktool's one line, `cmd = …` re-arms); and H2 — `quiet` is a declared var defaulting to `0`, `-q` singly and last of the flags in the all-on order |
| `005_Search.sh` | 60 | The ktool gate first, then a fixture tree (names with a space, a newline and a leading `-`, UTF-8, CRLF, a NUL-bearing file, a subdir, and **real** NTFS symlinks through `kt_make_symlink`) with the bare tool as the oracle: G5 no match on all five runners; G6 the `-E` dialect and the literal `(` without it; G7 the `-Z` framing in both directions; G8 a directory operand without `recursive`, `search` implying `-r`, and `search` refusing zero paths or an empty pattern; G9 the three forms; G10 the partial-failure deviation; G11 a nested `search` from inside a callback, in both shapes; G12 `-r` versus a real directory symlink (and `-R` as the counter-oracle); the CRLF table of §5; every remaining typed option against bare grep; and the binary-file record with its two escape hatches |
| `006_Contract.sh` | 50 | `bash -n`, the open-quote and inline-`$'\r'` greps, no `$this.` call, `parent.constructor` + `tutil._gnu grep` in the constructor and `inherited` in the destructor, no `var` shadowing an inherited member; every shape from a child script under `set -eu` (an instance, both `TPipe` forms, `search` as a producer, a hit, no match, a grep error, a partial failure, a refused build, a refused `search`, the stdin form, `run` streaming, `delete`); and the debug switch — exactly one line on each of the 9 rc 2 paths and the 3 grep-error paths, **none** on any rc 0 or no-match path, with complete silence from us when the switch is off while grep's own lines pass through; and one **D6-final** case: `g.subshellOk = 1` silences TPipe's subshell warning through two frames of wrapper (the child's stderr must be empty), while without it `$(g2.toArray A2)` carries the verbatim `Warning: TPipe.toArray: …` line |
| `007_Bench.sh` | 9 | The PLAN §5 P3.1 gates as assertions, behind the same ktool gate and with a 10× ceiling: `TGrep.search` against a bare `grep -r` over a 2000-line corpus (interleaved, medians, both sides asserted to find the same 21 hits), `TGrep.new` + `.delete` under 50 ms, `g.count` and the `countOnly` shortcut against `grep -c` (with grep's own per-file numbers compared as a set); that 200 `buildArgv` + `argv` calls invoke the `cmd` **zero** times, fork nothing and do not accumulate words; and zero forks for every member — the callback and `.Add` run in this process, and the seven builder members plus `run` and `search` leave `$BASHPID` untouched |
| `008_Helpers.sh` | 48 | H2, behind the same ktool gate. B0: the statics' argv pinned by a **recording stub** grep (`-F -r -q -e TEXT -- PATH...` and `-F -r -h -e TEXT -- PATH...`, a leading `-` after `-e`, `quiet` last among the flags, the usage refusals starting no process). A: `quiet` — `run` prints nothing, every sink sees zero records and `count` is `0`, rc 0 / 1, legal with `-l -L -c -o -n -v`, the **measured `-q` + failing-operand rcs** (match first, missing first, no match), the exact-`1` rule. B: `contains` — rc 0 / 1 silent direct and under `$( )`, the text is literal (`a.b` vs `aXb`, `[y]`, `$`, `a.*b`), a flag-shaped text is data, recursive, several paths, a CRLF file, a binary file, a tool error as rc 1 with ONE line (never rc 2), the usage and empty-TEXT rc 2 with one line and stdin unread. C: `countMatching` — RESULT equal to the bare tool's line count, a direct call silent and `$( )` once, zero matches `0`/rc 1, the failed-operand deviation (real count, rc 1, one line), no `file:count` parsing, **a binary file is ONE record**, a CRLF file, rc 2 with RESULT `''`. D: nesting inside an outer `each` and a `TPipe.each --` callback, `__TG_SEQ` and no instance left behind, the `quiet` lifecycle, `set -eu` predicates in a child | yes (gated; B0 not) |
