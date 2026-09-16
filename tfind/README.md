# tfind — `TFind`, the GNU `find` wrapper

> **Status: P0 done (first cut).** `TFind : TUtil` is the class, the pinned
> argv, the rc 2 list, the `mapRc` override, `paths`, the destructor and the
> static `byName`, plus the `TUTIL_OUT_PREFIXES` registry this unit introduced
> in [`../tutil`](../tutil/README.md). Suite: `tests/004_Argv.sh`,
> `tests/005_Run.sh`, `tests/006_Contract.sh` — **216 checks green on bash
> 5.2.37 and 216 on bash 5.3.9**, threaded and (5.2.37) under `--mode single`,
> against **GNU findutils 4.10.0**. P1 adds the bench, `007_Bench.sh`,
> `TEST_COVERAGE_NOTES.md` and the kcl README row. Design record:
> [PLAN.md](PLAN.md) (§8 is the critic pass every decision below survived) and
> [tfind_ledger.json](tfind_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the worked siblings:
> [`../tgrep`](../tgrep/README.md), [`../thead`](../thead/README.md),
> [`../ttail`](../ttail/README.md).

`TFind` is a [`TUtil`](../tutil/README.md) descendant: typed properties instead
of a hand-built command string, one rc convention, and the five `TPipe` sinks
for free.

```bash
source kcl/tfind/tfind.sh

TFind.byName '*.log' /var/log         # the one-liner: `find /var/log -name '*.log'`

TFind.new f src                       # or an instance, when you want options
f.name = '*.c'                        # ALWAYS quote the pattern — §2
f.type = f
f.maxDepth = 3
f.print0 = 1                          # -print0 + the sinks' -0
f.each r.onPath                       # one call per record, THIS shell
f.toArray sources                     # RESULT = ${#sources[@]}
f.count                               # RESULT = how many
f.lastRc                              # RESULT = find's RAW exit status
f.delete
```

What it buys over spelling the command out: a start point with a space or a
newline is one word by construction, the depth is normalised before find sees it
(`08` and `+1` both mean 8 and 1 — the verbatim `+1` is find's own rc 1), a
start point find would read as a predicate is refused **before** anything runs,
find's 0/1 collapses onto the kcl rc convention while the raw status stays
readable, and the platform notes (the start points come first, `-print0` framing,
`-name` case-sensitivity on NTFS, Windows paths) live here instead of in every
script.

---

## 1. Surface

```bash
TFind.new INST [START...]             # every argument is a start point
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `name` | var | `-name P` | `''` = off. **One argv element**, never expanded by the wrapper — quote it at the call site |
| `iname` | var | `-iname P` | `''` = off; case-insensitive |
| `type` | var | `-type T` | `''` = off; `T` must match `^[bcdflps](,[bcdflps])*$`, else **rc 2**. A duplicate list (`f,f`) passes and is the **tool's** rc 1 |
| `maxDepth` | var | `-maxdepth N` | `''` = off; `kk.isInt` **and** `>= 0`, else **rc 2**; emitted from `$__KK_INT` |
| `minDepth` | var | `-mindepth N` | `''` = off; same rule |
| `newer` | var | `-newer FILE` | `''` = off; a **missing** FILE is find's **fatal** rc 1 — no traversal at all |
| `followSymlinks` | var | `-L` | emitted **before** the start points, which is the only place find accepts it |
| `print0` | var | `-print0` | the action, last; derives the sinks' `-0` — §5. With an action extra → **rc 2** |
| `paths START...` | proc | — | **replaces** the start-point list; no argument = find's own `.` |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §3 |
| `TFind.byName PATTERN START...` | static proc | — | `find START... -name PATTERN`, streamed; §7 |

Inherited from [`TUtil`](../tutil/README.md) unchanged: `cmd` (`find`), `crlf`,
`nul`, `_lastRc`, **`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`,
`lastRc`, and the five sinks `each` / `toArray` / `toList` / `first` / `count`.

`subshellOk` is the D6-final switch (default `0`): `f.subshellOk = 1` makes every
sink pass `-s` to `TPipe`, which silences the subshell warning `$(f.toArray a)`
otherwise prints. It is inherited, not redeclared.

A `var` is read as `$(f.name)` and written as `f.name = value` — a plain `var`
read at a **call site** prints and leaves `RESULT` empty, so `$( )` is the only
correct spelling outside a member body.

A boolean is on for the exact string **`1`** and off for anything else — `2`,
`yes`, `true`, `01` and `' 1'` are all off, because a property is compared as a
string (`[[ "$x" == 1 ]]`) and never evaluated as arithmetic.

### The argv, pinned

```
find [-L] [START...] [-maxdepth N] [-mindepth N] [-name P] [-iname P]
     [-type T] [-newer F] [EXTRA ARGS from addArg] [-print0]
```

find's grammar is the **reverse** of grep's and head's: the start points come
**first** and the expression after them. So:

* **`-L` goes before the start points.** `find tree -L` is *unknown predicate*,
  rc 1 — which is why `followSymlinks` is a typed property and an `addArg -L`
  would silently land in the wrong place;
* **no `--`, ever.** `--` ends the **option** list (`-H/-L/-P`, `--version`) and
  does nothing for a start point: `find -- -weird` is still *unknown predicate*.
  Since it cannot rescue anything, this builder never emits it;
* **extras land in the expression**, after the typed tests and before the
  action:

```bash
f.addArg -size +1M
f.addArg -mtime -1
f.addArg '!' -name '*.o'
f.addArg '(' -name a -o -name b ')'
```

* the order is **this builder's**, not the order the caller assigned in;
* the global options (`-maxdepth`, `-mindepth`) are emitted first by convention;
  findutils 4.10 no longer warns about a late one, but the position is free.

`f.argv NAME` builds the array and **runs nothing**, which is how the whole
option set is pinned in `tests/004_Argv.sh` without executing find once.

### Start points are positional

| start point | what happens |
|---|---|
| `tree`, `/abs/path`, `C:\x\tree`, `)paren`, `,comma` | fine |
| *(none at all)* | find's own `.` — the records read `./…`, relative to the **caller's** working directory |
| `''` | **rc 2** (find would say `'': No such file or directory`) |
| `-weird`, `-`, `!x`, `(x` | **rc 2** — find reads them as the expression |
| `./-weird` | fine — the `./` is what saves it |
| `\\host\share` | the tool refuses it (rc 1); UNC is out of scope |

```bash
f.paths                               # no argument -> find's own `.`
f.toArray recs                        # recs = ( ./a.txt ./sub/… )
```

---

## 2. Patterns and values are **data** — quote them at the call site

`name`, `iname` and `newer` reach find as **one argv element each** and are never
glob-expanded, re-split or `eval`ed by the wrapper. The trap is on the caller's
side, and it is silent:

```bash
f.name = *.txt        # WRONG: the SHELL expands it here; the setter keeps
                      #        only the first match — `one.txt` — in silence
f.name = '*.txt'      # RIGHT: the pattern itself reaches find
```

A pattern containing `*`, `?`, `[`, a space or a newline survives verbatim once
it is quoted. Two more `-name` facts on this platform: it is **case-sensitive**
on NTFS under msys (`b.TXT` and `b.txt` are different — use `iname` when you mean
either), and a pattern containing `/` matches nothing, silently, because `-name`
tests the **base** name only.

`type` is checked against `^[bcdflps](,[bcdflps])*$`. A comma list works
(`f,d`); a duplicate (`f,f`) passes the regex on purpose and comes back as the
**tool's** rc 1 — parity beats a second opinion.

`maxDepth` / `minDepth` go through `kk.isInt` **and** a `>= 0` check, and the
**normalised** value is what reaches find:

| you write | find gets | why |
|---|---|---|
| `2` | `2` | — |
| `08` | `8` | decimal, and find would read `08` as 8 anyway |
| `+1` | `1` | a verbatim `+1` is find's **rc 1** (*Expected a positive decimal integer … got '+1'*) |
| `-1` | — | **rc 2** here |
| `2147483648` | `2147483648` | passes the guard; *Numerical result out of range* is the **tool's** rc 1 |

This is the **opposite** decision from [thead](../thead/README.md) /
[ttail](../ttail/README.md), where the sign carries meaning and `kk.isInt` is
forbidden. Nothing is written back onto the instance: `$(f.maxDepth)` still reads
`08` after a build.

`minDepth > maxDepth` is **not** refused — find simply answers nothing, rc 0.

---

## 3. Return contract

`rc 0` = find traversed and printed everything it was asked for. `rc 1` = it did
not. `rc 2` = the **call** was malformed and nothing ran. The raw status stays
readable through `lastRc`.

find has no "answer" rc the way grep's `1` (*no match*) is one: **every** failure
is `1`. `mapRc` is therefore `0 → 0` and anything else `→ 1` with one `kk.debug`
line.

### The rc 2 list — a malformed call, and nothing runs

`buildArgv` answers **rc 2** with `RESULT=''`, one `kk.debug` line naming the
reason, and `${inst}_argv` left **empty** so no stale command line can run
afterwards. Every runner (`run`, `argv` and all five sinks) passes that 2
straight back, and `lastRc` still reads `-1` on a fresh instance because nothing
was executed.

| refusal | why it is not left to find |
|---|---|
| `cmd` is empty | the instance was disarmed by hand |
| a start point that is **empty** | the tool's `'': No such file or directory` — a typo, not an intent |
| a start point beginning with `-`, `!` or `(` | find reads it as the expression, and `--` cannot protect it (§1) |
| `type` outside `^[bcdflps](,[bcdflps])*$` | `x`, `D`, `fd`, `f,`, `,f`, `'f d'` |
| `maxDepth`/`minDepth` not an integer, or negative | `x`, `1.5`, `' 2'`, `-1` |
| `print0 = 1` **and** an action word among the extras | §5 — two actions corrupt the NUL framing, and a failing `-exec` deletes the output entirely |

### Three named deviations

**(a) A partial failure keeps its records.** `find good missing` searches and
prints `good` and exits **1**. The sinks keep every record that arrived and
`RESULT` is the **real count** — this is the one place in this family where rc 1
does not imply an empty `RESULT`:

```bash
TFind.new f good_dir no_such_dir
f.print0 = 1
rc=0; f.toArray recs || rc=$?         # rc 1, RESULT = ${#recs[@]} > 0
f.lastRc                              # RESULT = 1 (find's raw status)
```

`newer` pointing at a **missing** file is *not* this case: it is fatal, no
traversal happens and there are **zero** records.

**(b) find's own stderr passes through unconditionally.** `find: '…': No such
file or directory` is the **tool's** stream, not ours; it is not gated by
`VERBOSE_KKLASS` and its quoting follows the locale. Redirect it where you do not
want it (`f.count 2>/dev/null`), and match it by **prefix** in a test. Exactly
**one** line of ours accompanies it.

**(c) `-exec CMD {} \;` swallows the child's status.** A command that fails —
or does not exist — leaves find at rc **0**, with only its own stderr to show for
it. The `{} +` form propagates the failure as rc 1:

```bash
f.addArg -exec false '{}' ';'         # rc 0, zero records
f.addArg -exec false '{}' '+'         # rc 1, lastRc 1
```

Use `{} +` when the child's status must reach `lastRc`.

### `$( )` loses the instance's state

Under `$( )` every mutation is lost with the subshell: `$(f.run)` captures the
bytes but the instance's `_lastRc` is **not** updated — the line every kcl
instance unit carries.

### An unguarded sink call aborts a `set -e` caller

rc 1 is a normal answer here (a missing start point), so a `set -e` script must
write `f.count || rc=$?`. That is the caller rule, not a defect; it is pinned in
`tests/006_Contract.sh`.

---

## 4. Actions through `addArg`

`-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-ls`, `-fls`, `-printf`,
`-fprint*`, `-print` and `-quit` are **not** modelled as properties. They go
through `addArg`, and they are allowed only with **`print0 = 0`**, where the
extra's output **is** the record stream — an explicit action suppresses find's
implied `-print`, which is exactly tool parity:

```bash
TFind.new f tree
f.name = 'a.txt'
f.addArg -exec printf 'X:%s\n' '{}' ';'
f.toArray recs                        # recs = ( 'X:tree/a.txt' ) — no plain path
```

`-quit` and `-prune` must come **before** the action and `-delete` **replaces**
it, so with this builder's fixed action position they are usable only in the
same hand-built shape (`print0 = 0`). A caller who needs `-print0` in a
hand-built position sets `nul = 1` manually and keeps `print0 = 0`.

---

## 5. `print0` — the NUL framing, and why it excludes every other action

`print0 = 1` emits `-print0` as **the** action and **derives** `nul = 1` so the
sinks read NUL-framed records. That is the shape every example should lead with,
because a file name may contain a newline:

```bash
TFind.new f tree
f.print0 = 1
f.toArray recs                        # one element per path, newlines and all
```

The same tree without it is two records for that one file — `-print` splits it.

**With `print0 = 1`, an action among the extras is rc 2.** Measured: two actions
both run and their output interleaves into a single corrupted NUL record
(`X:./a.txt\n./a.txt\0`), and an `-exec` that exits non-zero short-circuits
find's AND chain so `-print0` never fires at all — rc 0, **zero** records, no
diagnostic anywhere. The refused words are

```
-print -print0 -printf -fprint -fprint0 -fprintf -ls -fls -exec -execdir -ok -okdir -delete -quit
```

The scan is over the extras' **words**, and the wrapper does not parse find's
expression grammar — so `addArg -name '-exec'` (the action word as a *value*) is
refused too. Documented over-refusal; `print0 = 0` plus a manual `nul` is the way
out.

### Three states, not two

`_nulDerived` records that *we* set `nul`, which is what makes the derivation
idempotent:

* **derived** — `print0` went to 1 while `nul` was 0: we set `nul = 1` and
  remember it; turning `print0` back to 0 takes it off again;
* **caller-set** — `nul` was already 1 when the derivation ran: we never claim
  it, so a later build that stops deriving leaves the caller's `nul` alone;
* **off** — neither.

Claiming ownership whenever the *condition* held (rather than when we really set
the value) was `P3-F1` in tgrep; the same guard is here and the four-state
sequence is pinned in `tests/004_Argv.sh` §G.

---

## 6. Symlinks and Windows paths

### `followSymlinks` (`-L`)

The default is `-P`: a directory symlink is a record of its own and is **not**
descended. `followSymlinks = 1` emits `-L` before the start points and find
descends it:

```bash
f.type = f
f.toArray a                           # link/ is not entered
f.followSymlinks = 1
f.toArray b                           # b = a + everything under link/
```

One consequence worth stating: under `-L`, **`type = l` matches only broken
links** — every resolvable link has become the thing it points at. A near no-op,
documented rather than refused.

`-H` and `-P` are out of scope (the default is `-P`).

### Windows-spelled start points

`C:\Users\x\tree` and `C:/Users/x/tree` are both accepted under both bashes. The
start point's own spelling survives as the record **prefix**, and every separator
find appends after it is a forward slash:

```
C:\Users\x\tree/a.txt
```

So a test pins the prefix, never whole-record equality. A trailing slash is
normalised away; UNC (`\\host\share`) is refused by the tool.

---

## 7. `TFind.byName` — the one-liner

```bash
TFind.byName PATTERN START...         # find START... -name PATTERN, streamed
```

A `static proc`: it prints find's stdout untouched, answers with the mapped rc,
and has no return channel. The implied `-print` is what streams, so records are
newline framed — quote the pattern at the call site.

**At least one start point is required.** With none, find would search the
**caller's** working directory, which no caller means by accident in a one-liner
— that is rc 2 and nothing runs. Build an instance for that form, or for any
option at all. A start point the wrapper refuses comes back as rc 2 through
`run`, having executed nothing.

### The three forms

```bash
TFind.byName '*.log' /var/log                       # straight to the terminal
TFind.byName '*.log' /var/log | TPipe.each cb       # a real pipe (needs lastpipe)
TPipe.each cb -- TFind.byName '*.log' /var/log      # the safe `--` form
```

All three deliver byte-identical output to `find /var/log -name '*.log'`.

### Nested `byName` is safe

The throw-away instance is named `__tfd_b_${BASHPID}_${__TFD_SEQ}`, so a
`byName` started from inside the callback of an outer sink cannot delete the
outer one's instance out from under it. Cost: one construction per call.

---

## 8. The out-name registry this unit introduced

`tutil._badOut` used to hard-code the family's local prefixes, and three wrappers
in a row had edited that one line. It is now a registry
([`../tutil/README.md`](../tutil/README.md) §5):

```bash
declare -ga TUTIL_OUT_PREFIXES=( __tu_ __tg_ __th_ __tt_ )   # tutil.sh, at load
TUTIL_OUT_PREFIXES+=( __tfd_ )                               # tfind.sh, if absent
```

Two guards go with it, both from this unit's critic pass: the registry's **own
name** is refused as an out-name (otherwise one `f.argv TUTIL_OUT_PREFIXES`
replaces it with the argv and disarms the family guard process-wide), and it
**fails closed** — an empty, unset or non-array registry refuses **every** name,
because `"${arr[@]}"` on an unset array is silent under `set -u` and would
otherwise refuse none.

---

## 9. Tests

```bash
bash kcl/tfind/tests/tests.sh                 # the whole suite
bash kcl/tfind/tests/tests.sh --mode single   # sequential, for a stack trace
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tfind/tests/tests.sh
```

**216 cases, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and (5.2.37) under `--mode single`, against GNU findutils 4.10.0.

| file | cases | what it pins | runs find? |
|---|---|---|---|
| `004_Argv.sh` | 110 | the whole option set by **array comparison**: the lifecycle (every declared var in `${inst}_data` with its default, `${f}_args` empty after `new f START`, `_paths` verbatim, a reused name starting clean, `delete` freeing all three arrays, `argv` running nothing); the out-name registry (`__tfd_*`, the four older prefixes, `${inst}_paths`, and `TUTIL_OUT_PREFIXES` as a NAME with the registry intact afterwards, plus the idempotent append); every option singly and combined in the pinned order; the boolean-is-exactly-`1` rule; start points positional with **no `--` in any shape**; extras between the tests and the action; the rc 2 list — 36 refusals incl. every word of the action set, each asserting rc 2 + `RESULT ''` + the caller's array untouched + an EMPTY `${inst}_argv` + exactly one `kk.debug` line; the depths normalised through `$__KK_INT` with no write-back; the `print0` derivation's four states incl. `P3-F1`; and the caller-side glob trap (F5b) | **no** |
| `005_Run.sh` | 49 | behaviour against the bare tool on a fixture tree (depth 3, a space name, a **newline** name, a `-weird` directory, a real directory symlink and a broken one), every comparison NUL framed and `sort -z`ed: every typed option and three combinations; `-name` case-sensitive vs `-iname` on NTFS; `-L` descending the directory symlink while `-P` does not, and `-L` + `type = l` matching only the broken link; the newline name as 2 records under `-print` and 1 under `print0`; `./-weird` as a start point while `-weird` is rc 2; the partial failure (records kept, `RESULT` = the real count, rc 1, one line of ours, find's own matched by prefix) against the **fatal** `-newer MISSING`; the empty start-point list from a `cd` in this file's own shell; `-exec` as the record stream, `\;` leaving rc 0 and `+` propagating rc 1; and `TFind.byName` in three positions, with two start points, refused without one, propagating rc 2, nested inside an outer `each`, through both TPipe forms | yes (GNU banner gate first) |
| `006_Contract.sh` | 57 | source integrity (`bash -n`, the open-quote and inline-`$'…'` greps, no `$this.` call, the sentinel gone, `parent.constructor` in the constructor and `inherited` in the destructor, the `type` regex in a variable, the depths from `$__KK_INT`, no `--` append, the non-negated `[-!\(]*` class, no shadowed member name, exactly one `source` line, `__tfd_` registered); every shape from a child under `set -eu` — an instance, both TPipe forms, `byName` as a producer, records, a tool error, a partial failure, four refused builds, a refused `byName`, the cwd form, `run` streaming, `delete` — with every sink call guarded; the debug switch (exactly one line on each of the 11 rc 2 paths and the 3 tool-error paths, **none** on any rc 0 path); the **D6-final** `subshellOk` case; `F12`, that an unguarded rc 1 aborts a `set -eu` caller; and a Windows-spelled start point whose records carry that prefix and `/` after it | yes (gated) |

The behavioural files open with a **GNU banner gate**: if `find --version` does
not begin with `find (GNU findutils) `, every case below it is a loud `SKIP`
rather than a failure — D4 pins the dialect, not a binary, and the case **count
is unchanged**. The symlink cases add a second gate (`kt_symlinks_supported`
from `tdirectory/tests/symlink_helper.sh`): plain `ln -s` runs in **copy** mode
on MSYS and would silently make a directory copy.
